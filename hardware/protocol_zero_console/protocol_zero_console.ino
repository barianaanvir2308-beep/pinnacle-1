/*
 * Protocol Zero - Arduino "Overdrive" console
 * Pinnacle 1, Project 21 - Team Protocol Zero
 *
 * What it does
 *   - 16x2 I2C LCD   line 1: kill count sent by the game ("KILLS: 0127")
 *                    line 2: Overdrive state ("OVERDRIVE READY", "COOLDOWN 12s", "LOCKED", "SYSTEM CRASH", "NO SIGNAL")
 *   - Push button    one press = one Overdrive request (the in-game Emergency Overclock, same as the O key)
 *   - Status LED     solid = ready, ~2 Hz blink = cooldown, ~8 Hz blink = system crash, off = locked / no game
 *
 * PIN MAP
 *   D2   Push button S1 to GND (INPUT_PULLUP: HIGH released, LOW pressed)
 *   D9   220 ohm resistor R1 -> red LED D1 anode; LED cathode -> GND
 *   A4   LCD SDA (I2C)
 *   A5   LCD SCL (I2C)
 *   5V / GND  LCD VCC / GND
 *
 * SERIAL PROTOCOL (USB, 115200 baud, 8N1, ASCII lines ending in '\n')
 *   Arduino -> PC   "HELLO PZ1"       once after boot (handshake)
 *                   "HB"              heartbeat every 1 s, so the game knows the console is plugged in
 *                   "BTN OVERDRIVE"   the button was pressed (falling edge, debounced, never repeats while held)
 *   PC -> Arduino   "K <n>"           kill count, e.g. "K 127"
 *                   "S READY" | "S COOLDOWN <sec>" | "S LOCKED" | "S CRASH"   Overdrive state
 *                   "PING"            the game is alive (also sent once a second)
 *
 * The Arduino never decides whether Overdrive can fire. It only sends a request; the game checks the rules
 * (unlocked, cooldown over, not paused) and replies with the new state. The game stays the single source of truth.
 *
 * Libraries: Wire (built in) and LiquidCrystal_I2C (Frank de Brabander, Library Manager).
 * LCD address: real backpacks are usually 0x27 or 0x3F (run an I2C scanner); Tinkercad's PCF8574 LCD uses 0x20.
 */

#include <Wire.h>
#include <LiquidCrystal_I2C.h>

// ---------------- configuration ----------------
const uint8_t  BUTTON_PIN        = 2;
const uint8_t  LED_PIN           = 9;
const uint8_t  LCD_ADDRESS       = 0x27;   // change to 0x3F or 0x20 (Tinkercad) if the screen stays blank
const long     BAUD_RATE         = 115200;
const uint16_t DEBOUNCE_MS       = 40;     // the button must be stable this long before a press counts
const uint16_t HEARTBEAT_MS      = 1000;   // "HB" to the PC
const uint16_t SIGNAL_TIMEOUT_MS = 3000;   // no line from the game for this long -> "NO SIGNAL", LED off
const uint16_t BLINK_COOLDOWN_MS = 250;    // half-period: 2 Hz blink while cooling down
const uint16_t BLINK_CRASH_MS    = 62;     // half-period: 8 Hz blink during a system crash
const uint8_t  LINE_MAX          = 32;

LiquidCrystal_I2C lcd(LCD_ADDRESS, 16, 2);

// ---------------- state ----------------
enum OverdriveState { OD_NONE, OD_READY, OD_COOLDOWN, OD_LOCKED, OD_CRASH };
OverdriveState odState = OD_NONE;
int  cooldownSec = 0;
long kills = 0;

unsigned long lastRxMs = 0;          // last complete line from the game
bool          everHeard = false;
unsigned long lastHeartbeatMs = 0;

// button debounce
bool          buttonStable = HIGH;   // debounced level
bool          buttonLastRead = HIGH;
unsigned long buttonChangedMs = 0;

// serial line buffer
char    lineBuf[LINE_MAX];
uint8_t lineLen = 0;

// what is on the LCD now (only rewrite when it changes, so it never flickers)
char shown1[17] = "";
char shown2[17] = "";

// ---------------- helpers ----------------
void showLine(uint8_t row, const char *text, char *shown) {
  char padded[17];
  snprintf(padded, sizeof(padded), "%-16s", text);
  if (strcmp(padded, shown) == 0) return;
  strcpy(shown, padded);
  lcd.setCursor(0, row);
  lcd.print(padded);
}

bool gameConnected(unsigned long now) {
  return everHeard && (now - lastRxMs) < SIGNAL_TIMEOUT_MS;
}

void handleLine(char *line) {
  lastRxMs = millis();
  everHeard = true;
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
    } else if (lineLen < LINE_MAX - 1) {
      lineBuf[lineLen++] = c;
    } else {
      lineLen = 0;  // line too long: noise, drop it
    }
  }
}

// One "BTN OVERDRIVE" per press, on the debounced HIGH -> LOW edge
void readButton(unsigned long now) {
  bool reading = digitalRead(BUTTON_PIN);
  if (reading != buttonLastRead) {
    buttonLastRead = reading;
    buttonChangedMs = now;
  }
  if ((now - buttonChangedMs) >= DEBOUNCE_MS && reading != buttonStable) {
    buttonStable = reading;
    if (buttonStable == LOW) {
      Serial.println(F("BTN OVERDRIVE"));
    }
  }
}

void updateLed(unsigned long now) {
  bool on = false;
  if (gameConnected(now)) {
    switch (odState) {
      case OD_READY:    on = true; break;
      case OD_COOLDOWN: on = (now / BLINK_COOLDOWN_MS) % 2 == 0; break;
      case OD_CRASH:    on = (now / BLINK_CRASH_MS) % 2 == 0; break;
      default:          on = false; break;
    }
  }
  digitalWrite(LED_PIN, on ? HIGH : LOW);
}

void updateLcd(unsigned long now) {
  char text[17];
  snprintf(text, sizeof(text), "KILLS: %04ld", kills);
  showLine(0, text, shown1);
  if (!gameConnected(now)) {
    showLine(1, everHeard ? "NO SIGNAL" : "WAITING FOR GAME", shown2);
    return;
  }
  switch (odState) {
    case OD_READY:    showLine(1, "OVERDRIVE READY", shown2); break;
    case OD_COOLDOWN: snprintf(text, sizeof(text), "COOLDOWN %ds", cooldownSec); showLine(1, text, shown2); break;
    case OD_LOCKED:   showLine(1, "LOCKED", shown2); break;
    case OD_CRASH:    showLine(1, "SYSTEM CRASH", shown2); break;
    default:          showLine(1, "CONNECTED", shown2); break;
  }
}

// ---------------- setup / loop ----------------
void setup() {
  pinMode(BUTTON_PIN, INPUT_PULLUP);
  pinMode(LED_PIN, OUTPUT);
  digitalWrite(LED_PIN, LOW);
  Serial.begin(BAUD_RATE);
  lcd.init();
  lcd.backlight();
  showLine(0, "PROTOCOL ZERO", shown1);
  showLine(1, "WAITING FOR GAME", shown2);
  Serial.println(F("HELLO PZ1"));
}

void loop() {
  unsigned long now = millis();   // no delay() anywhere: the button stays responsive while the LED blinks
  readSerial();
  readButton(now);
  if (now - lastHeartbeatMs >= HEARTBEAT_MS) {
    lastHeartbeatMs = now;
    Serial.println(F("HB"));
  }
  updateLed(now);
  if (everHeard) updateLcd(now);  // keep the boot screen until the game first talks to us
}
