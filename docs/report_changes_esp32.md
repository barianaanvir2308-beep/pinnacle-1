# Report changes for the ESP32 controller

What to change in the project report (`ProtocolZero_21_Pinnacle1_Report.docx`) now that the console is an **ESP32 controller** (joystick + SELECT + OVERDRIVE) instead of the Arduino Uno console (LCD + one button + LED). Paragraph numbers are only to help you find the spot.

**Parts 1–4 are the four you asked about, with replacement text ready to paste. Part 5 lists every other place that still describes the old console.**

Two things to fill in yourself: the **real prices** in Table 9 (marked ✎), and a **new Figure 4** (a photo of the breadboard, or an updated drawing).

---

## 1. Section 6.1 "Board and why" (replace the whole paragraph)

> An ESP32 DevKit V1 (30-pin, ESP32-WROOM-32) with a KY-023 analog joystick and two push buttons. The first submitted console (an Arduino Uno with a 16×2 LCD kill counter, one Overdrive button and a status LED) was replaced after playtesting: players felt a single button duplicated the O key and added little (Section 12.2). The new controller plays the whole game: the joystick moves a grid cursor, SELECT places, selects and upgrades, a long SELECT goes back, and OVERDRIVE fires the Emergency Overclock.
>
> The ESP32 was chosen because its 12-bit ADC reads the joystick with fine resolution, it runs at 3.3 V (so the joystick is powered from 3V3 and its full range fits the ADC), it is cheap and widely available, and, like the Uno, it is powered, programmed and linked to the PC over one USB cable, so no Wi-Fi or Bluetooth pairing can fail during a demo. Its Wi-Fi and Bluetooth are left unused on purpose. The game still accepts the team's earlier Uno joystick controller, but only one board at a time.

**Figure 4 caption** (new picture needed):

> Figure 4: The controller: ESP32 DevKit V1, KY-023 joystick on GPIO34/35, SELECT on GPIO25 and OVERDRIVE on GPIO26, both to GND.

## 2. Table 6 "Pin map" (replace the table)

**Caption:** Table 6: Pin map (ESP32 DevKit V1; buttons use the internal pull-up and read LOW when pressed).

| Component | Pin | Purpose |
|---|---|---|
| KY-023 joystick VRx | GPIO34 (ADC, input only) | Left/right: moves the cursor or the highlight |
| KY-023 joystick VRy | GPIO35 (ADC, input only) | Up/down |
| KY-023 VCC, GND | 3V3, GND | Power at 3.3 V so the stick's full range fits the ADC (0–4095) |
| SELECT push button | GPIO25 (INPUT_PULLUP) → GND | Short press = click (place, select, confirm); held 600 ms = back/cancel |
| OVERDRIVE push button | GPIO26 (INPUT_PULLUP) → GND | Fires the in-game Emergency Overclock |
| Micro-USB cable | USB (CP2102 or CH340 USB-serial chip) | 5 V power, upload, and the serial link to the PC |

## 3. Table 7 "Serial protocol" (replace the table)

**Lead-in sentence in 6.2** (replace "finds the Arduino's port automatically (by USB vendor ID, then by name)"):

> …finds the board's port automatically (by the USB chip's vendor ID: Silicon Labs CP210x or WCH CH340 on the ESP32, or the Uno's own; then by name), opens it without resetting the board, drops the ESP32's start-up noise, and reopens it every second if the board is unplugged.

**Caption:** Table 7: Serial protocol (message set PZ3).

| Direction | Message | Meaning |
|---|---|---|
| ESP32 → PC | `HELLO PZ3` | Handshake once after boot |
| ESP32 → PC | `HB PZ3` | Heartbeat every 1 s: the board is plugged in, and which board it is |
| ESP32 → PC | `JOY <dx> <dy>` | Joystick direction (each −1, 0 or 1), sent only when it changes; the game steps the cursor at once and repeats after 350 ms, then every 120 ms |
| ESP32 → PC | `BTN SELECT` | SELECT pressed and released within 600 ms (a click) |
| ESP32 → PC | `BTN SELECT_LONG` | SELECT held 600 ms (back / cancel); no click is sent as well |
| ESP32 → PC | `BTN OVERDRIVE` | OVERDRIVE pressed (one message per press) |
| Bridge → game | `LINK UP <port>` / `LINK DOWN` | A serial port is open / no board (repeated every 1 s) |
| PC → ESP32 | `K <n>`, `S READY / COOLDOWN <s> / LOCKED / CRASH`, `PING` | Accepted for a future screen; not sent at present |

**Example exchange** (replace the paragraph under the table):

> The player pushes the stick right → the ESP32 sends `JOY 1 0` → the cursor moves one tile; the player holds it → the game keeps stepping every 120 ms; the stick returns → `JOY 0 0`. On an empty socket the player taps SELECT → `BTN SELECT` → a tower menu opens beside the tile; SELECT again → the game calls the same `TowerManager.place_tower()` as a mouse click, which refuses if Energy is short. Pressing OVERDRIVE → `BTN OVERDRIVE` → `OverclockManager.use()`, exactly like the O key.

## 4. Table 9 "Bill of materials" (replace the table) ✎

Remove the Uno, LCD, LED, resistor and USB A–B cable rows. ✎ = put your actual price.

| Item | Qty | Unit cost (₹) | Total (₹) | Source |
|---|---|---|---|---|
| ESP32 DevKit V1 (30-pin, ESP32-WROOM-32) | 1 | ✎ ~450 | ✎ | Local vendor |
| KY-023 joystick module | 1 | 100 | 100 | Local vendor |
| Tactile push button | 2 | 10 | 20 | Local vendor |
| Breadboard (400 point) | 1 | 80 | 80 | Local vendor |
| Jumper wire set | 1 | 100 | 100 | Local vendor |
| Micro-USB data cable | 1 | ✎ ~80 | ✎ | Local vendor |
| **Total** | | | **✎ ~830** | |

**Paragraph under the table** (replace "Actual spend was ₹1,143 … "):

> Actual spend was ₹✎, far below the handbook's indicative ₹12,000–₹16,000. The first console (Arduino Uno, 16×2 I2C LCD, button, LED; ₹1,143) was replaced by this ESP32 controller, which reuses the joystick, buttons, breadboard and wires.

(If you count both builds as project spend, keep the Uno rows in a second "first console" block and add both totals.)

---

## 5. Everything else that still describes the old console

| ¶ | Where | What to change |
|---|---|---|
| 3 | Title / subtitle | "an Arduino 'Overdrive' console" → "an ESP32 joystick controller" |
| 30 | Abstract | Describe the controller (joystick cursor, SELECT, OVERDRIVE) instead of the LCD kill counter and button |
| 40 | 1.3 What makes it original | "A risk-and-reward resource button, on real hardware" still holds; add that the whole game can be played from the controller |
| 66 | Comparison table row "Arduino LCD, Overdrive button, status LED" | → "ESP32 joystick controller: cursor, SELECT, OVERDRIVE" |
| 68 | 2. Target player | "No reflexes are needed beyond pressing one button at the right moment" → mention the joystick |
| 78 | 3.2 Score | "the kill count shown on the Arduino LCD" — there is no LCD now: the kill count is only in the game |
| 218 | Table 5 (main scripts) | Add `controller_input.gd` (cursor, tower menu, panel navigation), `tower_choice_menu.gd`, `controller_badge.gd`; update the `hardware_link.gd` row (two boards, one at a time, auto-repeat) |
| 236 | 6 intro | Sketch path → `hardware/protocol_zero_esp32/protocol_zero_esp32.ino`; mention `controller_input.gd` |
| 239 | Figure 4 | New picture and caption (see Part 1) |
| 285–290 | 6.3 Noise, debouncing and disconnection | Debounce is 40 ms on both buttons; add the joystick: **dead zone with hysteresis** (a push starts 1300 from the centre and ends inside 1000, raised after stick drift was found), averaged ADC readings, start-up centre calibration. Long press: SELECT_LONG fires at 600 ms and the release sends nothing. Remove the LCD/LED "NO SIGNAL" lines (no screen now). The HUD tag is now "CONTROLLER LINKED", and the start screen shows "ESP32 CONTROLLER LINKED" / "NO CONTROLLER". The bridge opens the port with DTR/RTS off so it doesn't reset the ESP32. |
| 292 | 6.4 Why the interface is meaningful | Rewrite around playing the whole game from the controller (cursor, tower menu, upgrades, Overclock), answering the 12.2 feedback |
| 298 | Screenshots caption | "a yellow CONSOLE LINKED tag" → the start-screen badge and the HUD "CONTROLLER LINKED" tag; a screenshot of the start screen with the controller linked would help |
| 302 | 7.1 Feedback design | Remove the LED/LCD sentence; add the cyan cursor (green/red + cross when building), the tower menu, the highlighted panel buttons |
| 339 | Libraries table | Remove LiquidCrystal_I2C / Wire; add "esp32 by Espressif Systems (Arduino core)" and pyserial |
| 412–413 | Excerpt 4 (`hardware_link.gd`) | The code changed: show `_identify()` (which board, one at a time) and `_handle_esp32()`, or the joystick repeat |
| 454, 464, 537–576 | Tests (Table 11, H01–H07) | `check_hardware` now has 135 checks, including the ESP32: cursor and edges, auto-repeat timing, short vs long press, the tower menu (incl. refusal with too little Energy), the panel, OVERDRIVE, one board at a time. Also `hardware/firmware_test` (28 checks on the sketch itself) and `hardware_bridge.py --self-test` (16). The kill-count and LCD/LED rows (H03, H07) no longer apply; redo H07 by hand on the ESP32. |
| 631–632 | 12.2 Player feedback | Keep the feedback; add that the controller was redesigned in response (it now plays the whole game) |
| 641, 681 | Table 13 / 14 | Add a row: "Console replaced by an ESP32 joystick controller (26-11)" |
| 692–693 | 14. Limitations | The physical ESP32 was tested by hand; timings come from the simulated tests. Still needs Python + pyserial. Tinkercad has no ESP32, so the circuit can't be simulated there. |
| 706 | 15. Q8 | The LED flash no longer exists; keep the reduced-flash note for glitch effects |
| 712 | 16. Reflections (Jehan) | Ask Jehan whether to mention the ESP32 rework |
| 714 | 17. Conclusion | Mention the ESP32 controller |
| 718 | Reference [3] | Add: Espressif Systems, "ESP32 Series Datasheet," and "Arduino-ESP32 documentation," docs.espressif.com, [Accessed: …]. Keep or drop the Uno reference |
| 735–737 | Appendix A | Replace the listing with `hardware/protocol_zero_esp32/protocol_zero_esp32.ino` |
| 761 | Table 14 timeline | Add the ESP32 controller date |
| 771 | Appendix E (setup) | Replace with: install "esp32 by Espressif Systems" in the Arduino IDE, upload `hardware/protocol_zero_esp32/protocol_zero_esp32.ino` with board "ESP32 Dev Module", `pip3 install pyserial`, plug in and start the game (details in `hardware/README.md`) |
