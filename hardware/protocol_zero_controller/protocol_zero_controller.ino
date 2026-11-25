/*
 * Protocol Zero - Arduino controller (joystick + 3 buttons)
 * Pinnacle 1, Project 21 - Team Protocol Zero
 *
 * What it does
 *   - Analog joystick    moves the selection cursor around the grid, one tile a push.
 *                        Hold it over and the cursor keeps stepping.
 *   - Button 1 SELECT    choose / confirm (pick a tile, confirm a tower, menu button)
 *   - Button 2 OVERRIDE  fires the in-game Emergency Overclock (same as the O key)
 *   - Button 3 BACK      go back / deselect / cancel
 *
 * PIN MAP
 *   A0   Joystick VRx (left / right)
 *   A1   Joystick VRy (up / down)
 *   5V   Joystick +5V
 *   GND  Joystick GND, and one leg of every button
 *   D2   Button 1 SELECT   -> GND (INPUT_PULLUP: HIGH released, LOW pressed)
 *   D3   Button 2 OVERRIDE -> GND (INPUT_PULLUP)
 *   D4   Button 3 BACK     -> GND (INPUT_PULLUP)
 *   The joystick's own SW pin (press-down click) is not used.
 *
 * SERIAL PROTOCOL (USB, 115200 baud, 8N1, ASCII lines ending in '\n')
 * The board only sends:
 *   "HELLO PZ2"      once after boot (handshake)
 *   "HB"             heartbeat every 1 s, so the game knows the board is plugged in
 *   "JOY U" | "JOY D" | "JOY L" | "JOY R"        one cursor step
 *   "BTN SELECT" | "BTN OVERRIDE" | "BTN BACK"   one message per press
 *                                                (never repeats while held)
 *
 * The Arduino never decides anything about the game. It only reports what the player
 * did; the game checks its own rules and stays the single source of truth.
 *
 * Libraries: none.
 */

// ---------------- configuration ----------------
const uint8_t  JOY_X_PIN       = A0;
const uint8_t  JOY_Y_PIN       = A1;
const uint8_t  BUTTON_PINS[3]  = {2, 3, 4};
const char    *BUTTON_NAMES[3] = {"BTN SELECT", "BTN OVERRIDE", "BTN BACK"};

const long     BAUD_RATE       = 115200;
const uint16_t DEBOUNCE_MS     = 40;     // a button must be stable this long to count
const uint16_t HEARTBEAT_MS    = 1000;   // "HB" to the PC
const int      JOY_CENTRE      = 512;    // the stick rests near the middle of 0..1023
const int      JOY_PUSH        = 300;    // further than this from the centre = pushed
const int      JOY_RELEASE     = 200;    // closer than this to the centre = let go
const uint16_t REPEAT_FIRST_MS = 400;    // held over: wait before the second step...
const uint16_t REPEAT_NEXT_MS  = 150;    // ...then step this often

// If the cursor moves the wrong way for how your joystick is mounted,
// flip these and upload again.
const bool INVERT_X = false;   // true: swap left and right
const bool INVERT_Y = false;   // true: swap up and down
const bool SWAP_XY  = false;   // true: the module is turned 90 degrees

// ---------------- state ----------------
bool          buttonStable[3]    = {HIGH, HIGH, HIGH};   // debounced level
bool          buttonLastRead[3]  = {HIGH, HIGH, HIGH};
unsigned long buttonChangedMs[3] = {0, 0, 0};

char          joyDir = 0;          // 'U', 'D', 'L', 'R', or 0 when centred
unsigned long joyNextStepMs = 0;

unsigned long lastHeartbeatMs = 0;

// ---------------- buttons ----------------
// One message per press, on the debounced HIGH -> LOW edge
void readButtons(unsigned long now) {
  for (uint8_t i = 0; i < 3; i++) {
    bool reading = digitalRead(BUTTON_PINS[i]);
    if (reading != buttonLastRead[i]) {
      buttonLastRead[i] = reading;
      buttonChangedMs[i] = now;
    }
    if ((now - buttonChangedMs[i]) >= DEBOUNCE_MS && reading != buttonStable[i]) {
      buttonStable[i] = reading;
      if (buttonStable[i] == LOW) {
        Serial.println(BUTTON_NAMES[i]);
      }
    }
  }
}

// ---------------- joystick ----------------
// Which way the stick is pushed. `limit` is how far from the centre counts.
char joystickDirection(int limit) {
  int x = analogRead(JOY_X_PIN) - JOY_CENTRE;
  int y = analogRead(JOY_Y_PIN) - JOY_CENTRE;
  if (SWAP_XY) { int t = x; x = y; y = t; }
  if (INVERT_X) x = -x;
  if (INVERT_Y) y = -y;
  if (abs(x) < limit && abs(y) < limit) return 0;
  // the stronger axis wins, so there are no diagonal steps
  if (abs(x) >= abs(y)) return (x < 0) ? 'L' : 'R';
  return (y < 0) ? 'U' : 'D';
}

void sendStep(char dir) {
  Serial.print(F("JOY "));
  Serial.println(dir);
}

void readJoystick(unsigned long now) {
  // A wider limit to start a push than to keep it, so a stick resting near the
  // threshold does not flicker
  char dir = joystickDirection(joyDir == 0 ? JOY_PUSH : JOY_RELEASE);
  if (dir == 0) {
    joyDir = 0;
    return;
  }
  if (dir != joyDir) {              // a new push: step straight away
    joyDir = dir;
    sendStep(dir);
    joyNextStepMs = now + REPEAT_FIRST_MS;
  } else if ((long)(now - joyNextStepMs) >= 0) {   // still held: keep stepping
    sendStep(dir);
    joyNextStepMs = now + REPEAT_NEXT_MS;
  }
}

// ---------------- setup / loop ----------------
void setup() {
  for (uint8_t i = 0; i < 3; i++) {
    pinMode(BUTTON_PINS[i], INPUT_PULLUP);
  }
  Serial.begin(BAUD_RATE);
  Serial.println(F("HELLO PZ2"));
}

void loop() {
  unsigned long now = millis();   // no delay() anywhere, so nothing is ever missed
  readButtons(now);
  readJoystick(now);
  if (now - lastHeartbeatMs >= HEARTBEAT_MS) {
    lastHeartbeatMs = now;
    Serial.println(F("HB"));
  }
}
