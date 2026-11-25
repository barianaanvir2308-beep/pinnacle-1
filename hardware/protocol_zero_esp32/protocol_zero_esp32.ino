/*
 * Protocol Zero - ESP32 controller
 * Pinnacle 1, Project 21 - Team Protocol Zero
 *
 * A joystick and two buttons that play the whole game: the stick moves a grid cursor, SELECT clicks, a long SELECT
 * is "back", and OVERDRIVE fires the in-game Emergency Overclock (the same thing as the O key). The board only
 * reports what the player does; the game decides what it means and checks every rule.
 *
 * BOARD   ESP32 DevKit V1 (30-pin, ESP32-WROOM-32), USB serial through its CP2102 or CH340 chip.
 *         Arduino IDE: board "ESP32 Dev Module".
 *
 * PIN MAP
 *   GPIO34  KY-023 VRx (joystick X, analog, 12-bit: 0..4095, centre about 1800-2000)
 *   GPIO35  KY-023 VRy (joystick Y, analog)
 *   3V3     KY-023 +5V/VCC pin   (3.3 V, so the stick's full range fits the ESP32 ADC)
 *   GND     KY-023 GND
 *   GPIO25  SELECT button to GND    (INPUT_PULLUP: HIGH released, LOW pressed)
 *   GPIO26  OVERDRIVE button to GND (INPUT_PULLUP)
 *   (KY-023 SW is not connected. GPIO34/35 are input-only pins with no pull-ups, which is fine for analog.)
 *
 * SERIAL PROTOCOL (USB, 115200 baud, 8N1, ASCII lines ending in '\n')
 *   ESP32 -> PC   "HELLO PZ3"          once after boot. PZ3 = this message set; PZ1 was the Uno LCD console and
 *                                      PZ2 the Uno joystick controller (hardware/protocol_zero_controller).
 *                 "HB PZ3"             heartbeat every 1 s: the controller is plugged in, and which kind it is
 *                                      (the bridge opens the port without resetting the board, so the game may
 *                                      never see HELLO; the heartbeat repeats the label)
 *                 "JOY <dx> <dy>"      stick direction, each -1, 0 or 1, sent only when it changes.
 *                                      dx: -1 left, 1 right. dy: -1 up, 1 down (screen direction). "JOY 0 0" = centred.
 *                                      The game moves the cursor one tile per nudge and auto-repeats while held.
 *                 "BTN SELECT"         SELECT pressed and released in under LONG_PRESS_MS (a click)
 *                 "BTN SELECT_LONG"    SELECT held for LONG_PRESS_MS (back / cancel). Sent once, as soon as the
 *                                      time is reached; releasing it afterwards sends nothing, so a long press
 *                                      never also counts as a click.
 *                 "BTN OVERDRIVE"      OVERDRIVE pressed (one message per press, never repeats while held)
 *   PC -> ESP32   "K <n>"              kill count               } accepted and remembered; this board has no
 *                 "S READY" | "S COOLDOWN <sec>" | "S LOCKED" | "S CRASH"   } screen or LED yet, so nothing is
 *                 "PING"               the game is alive        } shown. Unknown lines are ignored.
 *
 * Calibration: the stick's centre is measured at power-up (keep your thumb off it for the first moment). If the
 * reading is far from JOY_CENTER_X/Y (the stick was being pushed), the constants are used instead. A direction
 * switches on past JOY_ON_THRESHOLD from the centre and off again only inside JOY_OFF_THRESHOLD, so a stick
 * resting near the edge of the dead zone can't flicker.
 */

// ---------------- configuration ----------------
const uint8_t  JOY_X_PIN          = 34;
const uint8_t  JOY_Y_PIN          = 35;
const uint8_t  SELECT_PIN         = 25;
const uint8_t  OVERDRIVE_PIN      = 26;
const long     BAUD_RATE          = 115200;

const int      JOY_CENTER_X       = 1900;  // centre reading if the start-up calibration can't be used
const int      JOY_CENTER_Y       = 1900;
// Dead zone. Raised for sticks that drift: a resting stick must stay inside JOY_ON_THRESHOLD of its centre.
// Full travel is about 1900 to 2200 from the centre, so a deliberate push still gets there easily.
// Still drifting? Set JOY_DEBUG to true, watch the RAW lines with the stick resting, and raise both numbers.
const int      JOY_ON_THRESHOLD   = 1300;  // distance from the centre that counts as a push (dead zone edge)
const int      JOY_OFF_THRESHOLD  = 1000;  // a push ends only when the stick is back this close to the centre
const int      JOY_CALIBRATE_MAX  = 600;   // start-up centre further than this from JOY_CENTER_* is ignored
const bool     JOY_INVERT_X       = false; // set true if pushing the stick right sends "JOY -1 0"
const bool     JOY_INVERT_Y       = false; // set true if pushing the stick up sends "JOY 0 1"
const uint8_t  JOY_SAMPLES        = 4;     // readings averaged per update (the ESP32 ADC is noisy)
const uint16_t JOY_SAMPLE_MS      = 10;    // how often the stick is read
const bool     JOY_DEBUG          = false; // true: also print "RAW <x> <y> <centreX> <centreY>" 5 times a second
                                           // (for measuring drift in the Serial Monitor; the game ignores it)

const uint16_t DEBOUNCE_MS        = 40;    // a button must be stable this long before a change counts
const uint16_t LONG_PRESS_MS      = 600;   // SELECT held this long = SELECT_LONG (back)
const uint16_t HEARTBEAT_MS       = 1000;  // "HB" to the PC
const uint8_t  RX_LINE_MAX        = 32;

// ---------------- state ----------------
int centerX = JOY_CENTER_X;
int centerY = JOY_CENTER_Y;
int joyDx = 0;                       // last direction sent
int joyDy = 0;
unsigned long lastJoySampleMs = 0;
unsigned long lastRawMs = 0;
unsigned long lastHeartbeatMs = 0;

// What the game told us. Nothing shows it yet (no LCD or LED on this board), but it is parsed and kept so a
// screen can be added later without touching the protocol.
long kills = 0;
enum OverdriveState { OD_NONE, OD_READY, OD_COOLDOWN, OD_LOCKED, OD_CRASH };
OverdriveState odState = OD_NONE;
int  cooldownSec = 0;
unsigned long lastRxMs = 0;

// A debounced button
struct Button {
  uint8_t pin;
  bool stable;                  // debounced level (HIGH = released)
  bool lastRead;
  unsigned long changedMs;      // when the raw reading last changed
  unsigned long pressedMs;      // when the debounced level went LOW
  bool longSent;                // SELECT_LONG already sent for this press
};
Button selectBtn    = {SELECT_PIN, HIGH, HIGH, 0, 0, false};
Button overdriveBtn = {OVERDRIVE_PIN, HIGH, HIGH, 0, 0, false};

char    lineBuf[RX_LINE_MAX];
uint8_t lineLen = 0;

// ---------------- joystick ----------------
int readAverage(uint8_t pin) {
  long sum = 0;
  for (uint8_t i = 0; i < JOY_SAMPLES; i++) sum += analogRead(pin);
  return (int)(sum / JOY_SAMPLES);
}

// Measures the resting centre at power-up. Falls back to the constant when the stick was being pushed.
int calibrateAxis(uint8_t pin, int fallback) {
  long sum = 0;
  const int n = 32;
  for (int i = 0; i < n; i++) sum += analogRead(pin);
  int measured = (int)(sum / n);
  return abs(measured - fallback) <= JOY_CALIBRATE_MAX ? measured : fallback;
}

// -1, 0 or 1 for one axis, with hysteresis: switching on needs JOY_ON_THRESHOLD, switching off needs the stick
// back inside JOY_OFF_THRESHOLD
int axisDirection(int raw, int center, int current, bool invert) {
  int offset = raw - center;
  if (invert) offset = -offset;
  if (current != 0) {
    if (offset * current > JOY_OFF_THRESHOLD) return current;   // still pushed the same way
  }
  if (offset > JOY_ON_THRESHOLD) return 1;
  if (offset < -JOY_ON_THRESHOLD) return -1;
  return 0;
}

void updateJoystick(unsigned long now) {
  if (now - lastJoySampleMs < JOY_SAMPLE_MS) return;
  lastJoySampleMs = now;
  int rawX = readAverage(JOY_X_PIN);
  int rawY = readAverage(JOY_Y_PIN);
  if (JOY_DEBUG && now - lastRawMs >= 200) {
    lastRawMs = now;
    Serial.print(F("RAW "));
    Serial.print(rawX); Serial.print(' ');
    Serial.print(rawY); Serial.print(' ');
    Serial.print(centerX); Serial.print(' ');
    Serial.println(centerY);
  }
  int dx = axisDirection(rawX, centerX, joyDx, JOY_INVERT_X);
  int dy = axisDirection(rawY, centerY, joyDy, JOY_INVERT_Y);
  if (dx != joyDx || dy != joyDy) {
    joyDx = dx;
    joyDy = dy;
    Serial.print(F("JOY "));
    Serial.print(dx);
    Serial.print(' ');
    Serial.println(dy);
  }
}

// ---------------- buttons ----------------
// Returns true when the debounced level changed this call
bool debounce(Button &b, unsigned long now) {
  bool reading = digitalRead(b.pin);
  if (reading != b.lastRead) {
    b.lastRead = reading;
    b.changedMs = now;
  }
  if ((now - b.changedMs) >= DEBOUNCE_MS && reading != b.stable) {
    b.stable = reading;
    return true;
  }
  return false;
}

// SELECT: a click on release if it was short; SELECT_LONG as soon as it has been held long enough
void updateSelect(unsigned long now) {
  if (debounce(selectBtn, now)) {
    if (selectBtn.stable == LOW) {
      selectBtn.pressedMs = now;
      selectBtn.longSent = false;
    } else if (!selectBtn.longSent) {
      Serial.println(F("BTN SELECT"));
    }
  }
  if (selectBtn.stable == LOW && !selectBtn.longSent && now - selectBtn.pressedMs >= LONG_PRESS_MS) {
    selectBtn.longSent = true;
    Serial.println(F("BTN SELECT_LONG"));
  }
}

// OVERDRIVE: one request per press, on the debounced press
void updateOverdrive(unsigned long now) {
  if (debounce(overdriveBtn, now) && overdriveBtn.stable == LOW) {
    Serial.println(F("BTN OVERDRIVE"));
  }
}

// ---------------- messages from the game ----------------
void handleLine(char *line) {
  lastRxMs = millis();
  if (line[0] == 'K' && line[1] == ' ') {
    kills = atol(line + 2);
  } else if (strncmp(line, "S READY", 7) == 0) {
    odState = OD_READY;
  } else if (strncmp(line, "S COOLDOWN", 10) == 0) {
    odState = OD_COOLDOWN;
    cooldownSec = atoi(line + 10);
  } else if (strncmp(line, "S LOCKED", 8) == 0) {
    odState = OD_LOCKED;
  } else if (strncmp(line, "S CRASH", 7) == 0) {
    odState = OD_CRASH;
  }
  // "PING" and anything unknown only refresh lastRxMs
}

// Non-blocking: collect characters until '\n', then parse the line
void readSerial() {
  while (Serial.available() > 0) {
    char c = (char)Serial.read();
    if (c == '\r') continue;
    if (c == '\n') {
      lineBuf[lineLen] = '\0';
      if (lineLen > 0) handleLine(lineBuf);
      lineLen = 0;
    } else if (lineLen < RX_LINE_MAX - 1) {
      lineBuf[lineLen++] = c;
    } else {
      lineLen = 0;  // line too long: noise, drop it
    }
  }
}

// ---------------- main ----------------
void setup() {
  Serial.begin(BAUD_RATE);
  pinMode(SELECT_PIN, INPUT_PULLUP);
  pinMode(OVERDRIVE_PIN, INPUT_PULLUP);
  analogReadResolution(12);
  analogSetPinAttenuation(JOY_X_PIN, ADC_11db);   // full 0-3.3 V range
  analogSetPinAttenuation(JOY_Y_PIN, ADC_11db);
  centerX = calibrateAxis(JOY_X_PIN, JOY_CENTER_X);
  centerY = calibrateAxis(JOY_Y_PIN, JOY_CENTER_Y);
  Serial.println(F("HELLO PZ3"));
  lastHeartbeatMs = millis();
}

void loop() {
  unsigned long now = millis();
  readSerial();
  updateJoystick(now);
  updateSelect(now);
  updateOverdrive(now);
  if (now - lastHeartbeatMs >= HEARTBEAT_MS) {
    lastHeartbeatMs = now;
    Serial.println(F("HB PZ3"));
  }
}
