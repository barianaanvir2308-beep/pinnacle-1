// sim_test.cpp — runs protocol_zero_esp32.ino on the computer with a fake Arduino layer, feeds it stick and button
// timelines, and checks every line it sends. No board needed.
// Run: bash hardware/firmware_test/run_sim_test.sh
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <deque>
#include <string>
#include <vector>

// ---------------- fake Arduino ----------------
#define HIGH 1
#define LOW 0
#define INPUT_PULLUP 2
#define ADC_11db 3
#define F(s) (s)
static unsigned long g_now = 0;
static int g_digital[64];
static int g_analog[64];
static std::vector<std::string> g_sent;      // complete lines sent by the board
static std::string g_partial;
static std::deque<char> g_rx;                // bytes "from the PC"
unsigned long millis() { return g_now; }
int digitalRead(uint8_t pin) { return g_digital[pin]; }
int analogRead(uint8_t pin) { return g_analog[pin]; }
void pinMode(uint8_t, int) {}
void analogReadResolution(int) {}
void analogSetPinAttenuation(uint8_t, int) {}
struct FakeSerial {
  void begin(long) {}
  int available() { return (int)g_rx.size(); }
  int read() { char c = g_rx.front(); g_rx.pop_front(); return (unsigned char)c; }
  void print(const char *s) { g_partial += s; }
  void print(char c) { g_partial += c; }
  void print(int v) { g_partial += std::to_string(v); }
  void println(const char *s) { print(s); println(); }
  void println(int v) { print(v); println(); }
  void println() { g_sent.push_back(g_partial); g_partial.clear(); }
} Serial;

#include "../protocol_zero_esp32/protocol_zero_esp32.ino"

// ---------------- test helpers ----------------
static int g_fails = 0;
static void check(bool ok, const std::string &msg) {
  if (!ok) g_fails++;
  printf("  %s  %s\n", ok ? "ok  " : "FAIL", msg.c_str());
}
static void run_for(unsigned long ms) { for (unsigned long i = 0; i < ms; i++) { g_now++; loop(); } }
static std::vector<std::string> take() { auto out = g_sent; g_sent.clear(); return out; }
static std::vector<std::string> only(const std::vector<std::string> &lines, const char *prefix) {
  std::vector<std::string> out;
  for (auto &l : lines) if (l.rfind(prefix, 0) == 0) out.push_back(l);
  return out;
}
static std::string join(const std::vector<std::string> &v) {
  std::string s; for (auto &x : v) { if (!s.empty()) s += " | "; s += x; } return s.empty() ? "(nothing)" : s;
}
static void boot(int x, int y) {
  g_now = 0; g_sent.clear(); g_partial.clear(); g_rx.clear();
  g_digital[SELECT_PIN] = HIGH; g_digital[OVERDRIVE_PIN] = HIGH;
  g_analog[JOY_X_PIN] = x; g_analog[JOY_Y_PIN] = y;
  joyDx = joyDy = 0; lastJoySampleMs = 0; lineLen = 0;
  selectBtn = {SELECT_PIN, HIGH, HIGH, 0, 0, false};
  overdriveBtn = {OVERDRIVE_PIN, HIGH, HIGH, 0, 0, false};
  setup();
}

int main() {
  printf("== boot, heartbeat, calibration\n");
  boot(1980, 1850);
  auto lines = take();
  check(lines.size() == 1 && lines[0] == "HELLO PZ3", "first line is HELLO PZ3 (got " + join(lines) + ")");
  check(centerX == 1980 && centerY == 1850, "the resting centre is measured at start-up (1980, 1850)");
  run_for(3050);
  lines = only(take(), "HB");
  check(lines.size() == 3 && lines[0] == "HB PZ3", "HB PZ3 once a second (3 in 3 s, got " + join(lines) + ")");
  boot(4095, 1900);
  check(centerX == JOY_CENTER_X, "a stick pushed during start-up is not taken as the centre (falls back to 1900)");
  take();

  printf("== joystick\n");
  boot(1900, 1900);
  take();
  for (int i = 0; i < 200; i++) { g_analog[JOY_X_PIN] = 1900 + ((i * 37) % 401) - 200; g_now++; loop(); }
  check(only(take(), "JOY").empty(), "ADC noise of +-200 around the centre sends nothing");
  // stick drift: resting well off centre (but inside the dead zone), with noise on top
  for (int i = 0; i < 400; i++) {
    g_analog[JOY_X_PIN] = 1900 + (JOY_ON_THRESHOLD - 250) + ((i * 37) % 201) - 100;
    g_analog[JOY_Y_PIN] = 1900 - (JOY_ON_THRESHOLD - 250) + ((i * 53) % 201) - 100;
    g_now++; loop();
  }
  check(only(take(), "JOY").empty(), "a drifting stick resting " + std::to_string(JOY_ON_THRESHOLD - 250) +
        " off centre on both axes sends nothing");
  g_analog[JOY_Y_PIN] = 1900;
  g_analog[JOY_X_PIN] = 1900;
  g_analog[JOY_X_PIN] = 4095; run_for(30);
  lines = only(take(), "JOY");
  check(lines.size() == 1 && lines[0] == "JOY 1 0", "stick right -> JOY 1 0 (got " + join(lines) + ")");
  run_for(1000);
  check(only(take(), "JOY").empty(), "held right: nothing more (the game does the auto-repeat)");
  g_analog[JOY_X_PIN] = 1900 + JOY_OFF_THRESHOLD + 100; run_for(30);
  check(only(take(), "JOY").empty(), "easing back to just outside JOY_OFF_THRESHOLD still counts as pushed (hysteresis)");
  g_analog[JOY_X_PIN] = 1900 + JOY_OFF_THRESHOLD - 200; run_for(30);
  lines = only(take(), "JOY");
  check(lines.size() == 1 && lines[0] == "JOY 0 0", "back inside JOY_OFF_THRESHOLD -> JOY 0 0 (got " + join(lines) + ")");
  g_analog[JOY_X_PIN] = 1900 + JOY_ON_THRESHOLD - 100; run_for(30);
  check(only(take(), "JOY").empty(), "just short of JOY_ON_THRESHOLD (" + std::to_string(JOY_ON_THRESHOLD) + ") is not a push");
  g_analog[JOY_X_PIN] = 1900; g_analog[JOY_Y_PIN] = 0; run_for(30);
  lines = only(take(), "JOY");
  check(lines.size() == 1 && lines[0] == "JOY 0 -1", "stick up (low VRy) -> JOY 0 -1 (got " + join(lines) + ")");
  check(JOY_ON_THRESHOLD < 1800, "a full push (about 1900 from the centre) still reaches the dead-zone edge");
  g_analog[JOY_X_PIN] = 0; run_for(30);
  lines = only(take(), "JOY");
  check(lines.size() == 1 && lines[0] == "JOY -1 -1", "up-left -> JOY -1 -1 (got " + join(lines) + ")");
  g_analog[JOY_X_PIN] = 1900; g_analog[JOY_Y_PIN] = 1900; run_for(30);
  take();

  printf("== SELECT\n");
  g_digital[SELECT_PIN] = LOW; run_for(150); g_digital[SELECT_PIN] = HIGH; run_for(60);
  lines = only(take(), "BTN");
  check(lines.size() == 1 && lines[0] == "BTN SELECT", "a 150 ms press -> BTN SELECT on release (got " + join(lines) + ")");
  for (int i = 0; i < 6; i++) { g_digital[SELECT_PIN] = (i % 2) ? HIGH : LOW; run_for(5); }
  g_digital[SELECT_PIN] = LOW; run_for(150); g_digital[SELECT_PIN] = HIGH; run_for(60);
  lines = only(take(), "BTN");
  check(lines.size() == 1 && lines[0] == "BTN SELECT", "contact bounce before a press still gives one click (got " + join(lines) + ")");
  g_digital[SELECT_PIN] = LOW; run_for(20); g_digital[SELECT_PIN] = HIGH; run_for(100);
  check(only(take(), "BTN").empty(), "a 20 ms blip (shorter than the 40 ms debounce) is ignored");
  g_digital[SELECT_PIN] = LOW; run_for(500);
  check(only(take(), "BTN").empty(), "held 500 ms: nothing yet");
  run_for(200);
  lines = only(take(), "BTN");
  check(lines.size() == 1 && lines[0] == "BTN SELECT_LONG", "held past 600 ms -> BTN SELECT_LONG while still held (got " + join(lines) + ")");
  run_for(2000); g_digital[SELECT_PIN] = HIGH; run_for(100);
  check(only(take(), "BTN").empty(), "holding on and releasing after a long press sends nothing (no extra click)");

  printf("== OVERDRIVE\n");
  g_digital[OVERDRIVE_PIN] = LOW; run_for(2000);
  lines = only(take(), "BTN");
  check(lines.size() == 1 && lines[0] == "BTN OVERDRIVE", "a press -> one BTN OVERDRIVE, even held 2 s (got " + join(lines) + ")");
  g_digital[OVERDRIVE_PIN] = HIGH; run_for(100);
  check(only(take(), "BTN").empty(), "releasing sends nothing");
  for (int i = 0; i < 8; i++) { g_digital[OVERDRIVE_PIN] = (i % 2) ? HIGH : LOW; run_for(3); }
  g_digital[OVERDRIVE_PIN] = LOW; run_for(100); g_digital[OVERDRIVE_PIN] = HIGH; run_for(100);
  check(only(take(), "BTN").size() == 1, "a bouncy press still fires once");

  printf("== messages from the game\n");
  const char *in = "K 127\nS COOLDOWN 12\r\nPING\nGARBAGE_THAT_IS_FAR_TOO_LONG_FOR_THE_BUFFER_XXXXXXXXXXXXXXXXX\nS READY\n";
  for (const char *p = in; *p; p++) g_rx.push_back(*p);
  run_for(5);
  check(kills == 127, "K 127 is remembered");
  check(odState == OD_READY, "S COOLDOWN then S READY: state follows the last line");
  check(cooldownSec == 12, "S COOLDOWN 12 parsed (with a Windows line ending)");
  check(lastRxMs > 0, "PING and the other lines count as the game being alive");
  lines = take();
  check(only(lines, "JOY").empty() && only(lines, "BTN").empty(), "incoming lines never make the board send anything");

  printf("sim_test: %d failure(s)\n", g_fails);
  return g_fails ? 1 : 0;
}
