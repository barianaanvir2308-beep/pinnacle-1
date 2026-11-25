# Protocol Zero — hardware controllers

A controller is optional. With none plugged in (or no Python), the game plays exactly as before with mouse and keyboard, and mouse and keyboard keep working while one is plugged in.

There are two controllers. The game understands both, but **listens to one at a time**: the first board it hears is used until it is unplugged.

| | **ESP32 controller (current)** | Arduino Uno controller (older) |
|---|---|---|
| Sketch | `protocol_zero_esp32/protocol_zero_esp32.ino` | `protocol_zero_controller/protocol_zero_controller.ino` |
| Board | ESP32 DevKit V1 (30-pin, ESP32-WROOM-32), USB chip CP2102 or CH340 | Arduino Uno R3 |
| Inputs | Joystick, SELECT (hold = back), OVERDRIVE | Joystick, SELECT, OVERRIDE, BACK |
| Message set | PZ3 | PZ2 |

Neither board has a screen or lights.

---

## ESP32 controller

### Parts and pins

| Part | ESP32 pin | Notes |
|---|---|---|
| KY-023 joystick **VRx** | **GPIO34** | Analog, 12-bit (0–4095); rests around 1800–2000 |
| KY-023 joystick **VRy** | **GPIO35** | Analog |
| KY-023 **+5V / VCC** | **3V3** | Use 3.3 V, not 5 V: the ESP32's ADC only reads up to 3.3 V |
| KY-023 **GND** | **GND** | |
| KY-023 **SW** | not connected | |
| **SELECT** button | **GPIO25** → button → GND | Internal pull-up: reads LOW when pressed |
| **OVERDRIVE** button | **GPIO26** → button → GND | Internal pull-up |
| USB cable (micro-USB) | USB | Power, upload and the serial link to the PC |

No resistors and no extra libraries. GPIO34/35 are input-only pins with no pull-ups, which is fine for the joystick. Each button sits across the gap in the middle of the breadboard: one leg goes to its pin, the diagonally opposite leg to the GND rail.

### What the controls do

| Control | On the board | With the tower menu open | With a tower selected | In a menu screen |
|---|---|---|---|---|
| Joystick | Moves the cyan cursor one tile per nudge; hold it and it repeats (after 350 ms, then every 120 ms) | Up/down chooses the tower | Moves between the upgrade cards, Repair and Sell | Moves between the buttons |
| SELECT (short) | Empty socket: opens the tower menu. Tower: selects it. Arduino core in the build phase: starts the next wave | Builds the highlighted tower | First press highlights, the next presses the highlighted button | Presses the highlighted button |
| SELECT (held 600 ms) | Leaves placement mode / deselects (like Esc or a right click) | Closes the menu | Deselects the tower | Goes back one screen |
| OVERDRIVE | Emergency Overclock: +150 Energy, +50 System Load (the same as the O key) | | | |

The start screen shows **ESP32 CONTROLLER LINKED** (green light) or **NO CONTROLLER**, and it changes the moment the board is plugged in or out.

### 1. Upload the sketch (once)

1. Install the **Arduino IDE 2** (arduino.cc/en/software).
2. Add the ESP32 boards (once): **Tools → Board → Boards Manager**, search **esp32**, install **"esp32 by Espressif Systems"**. If it isn't listed, add this URL in **Arduino IDE → Settings → Additional boards manager URLs** first:
   `https://espressif.github.io/arduino-esp32/package_esp32_index.json`
3. Plug the ESP32 in with a USB **data** cable (some micro-USB cables only charge).
4. Open `hardware/protocol_zero_esp32/protocol_zero_esp32.ino`.
5. **Tools → Board → esp32 → ESP32 Dev Module.**
6. **Tools → Port:** `/dev/cu.usbserial-…` (CP2102) or `/dev/cu.wchusbserial…` (CH340) on macOS, `COM…` on Windows.
7. **Close the game, the bridge and the Serial Monitor** — anything that has the port open makes the upload fail.
8. Click **Upload**.

If the upload fails, see *Troubleshooting* below.

### 2. Check it in the Serial Monitor (optional)

Open **Tools → Serial Monitor** at **115200** baud and press the board's **EN** (reset) button:

* `HELLO PZ3` once, then `HB PZ3` every second
* push the stick: `JOY 1 0` (right), `JOY -1 0` (left), `JOY 0 -1` (up), `JOY 0 1` (down), `JOY 0 0` when you let go
* tap SELECT: `BTN SELECT`; hold it: `BTN SELECT_LONG`; press OVERDRIVE: `BTN OVERDRIVE`

A few lines of start-up text from the ESP32 itself before `HELLO PZ3` are normal; the game ignores them.

**Calibrating** — all of these are constants at the top of the sketch; change them and upload again:

* The stick moves the cursor the wrong way: set `JOY_INVERT_X` or `JOY_INVERT_Y` to `true`.
* **Stick drift** (the cursor moves on its own): set `JOY_DEBUG` to `true`, upload, and leave the stick alone. The Serial Monitor shows `RAW <x> <y> <centreX> <centreY>` five times a second. Note how far x and y wander from the centre, then make `JOY_ON_THRESHOLD` (now 1300) and `JOY_OFF_THRESHOLD` (now 1000) larger than that. Set `JOY_DEBUG` back to `false` when done.
* Keep your thumb off the stick for the first moment after power-up: the board measures the stick's resting centre then.

### 3. Install the bridge's one dependency (once)

```
pip3 install pyserial
```

### 4. Play

Close the Serial Monitor, plug the board in and start the game. The game starts `tools/hardware_bridge.py` by itself, and within about a second the start screen shows **ESP32 CONTROLLER LINKED**.

If it doesn't connect, run the bridge by hand in a terminal to see what it says:

```
python3 tools/hardware_bridge.py --list     # shows the serial ports and which one it would use
python3 tools/hardware_bridge.py            # runs it; stop it with Control+C
python3 tools/hardware_bridge.py --port /dev/cu.usbserial-0001
```

The bridge finds the board by its USB chip (Silicon Labs CP210x, WCH CH340/CH9102, FTDI, or the Uno's own), opens the port without resetting the board, and drops the ESP32's start-up noise.

---

## Messages (USB serial, 115200 baud, ASCII lines ending in `\n`)

| From | ESP32 (PZ3) | Uno (PZ2) | Meaning |
|---|---|---|---|
| Board | `HELLO PZ3` | `HELLO PZ2` | Handshake once after boot |
| Board | `HB PZ3` | `HB` | Heartbeat every 1 s; the ESP32's also says which board it is |
| Board | `JOY <dx> <dy>` (each -1, 0, 1), sent when the direction changes; the game repeats while held | `JOY U` / `D` / `L` / `R`, one per step; the board repeats while held | Joystick |
| Board | `BTN SELECT` | `BTN SELECT` | Click |
| Board | `BTN SELECT_LONG` (SELECT held 600 ms; no click is sent as well) | `BTN BACK` | Back / cancel |
| Board | `BTN OVERDRIVE` | `BTN OVERRIDE` | Emergency Overclock |
| Bridge | `LINK UP <port>` / `LINK DOWN` | same | A port is open / no board |
| Game | `K <n>`, `S READY` / `S COOLDOWN <s>` / `S LOCKED` / `S CRASH`, `PING` | — | Accepted by the ESP32 sketch for a future screen; the game doesn't send them now |

The board never decides anything: the game checks every rule (Energy, unlock, cooldown, System Load), and every action goes through the same functions as the mouse and keyboard.

The game decides which board is talking from `HELLO PZ2` / `HELLO PZ3`, the heartbeat (`HB` / `HB PZ3`), or the first line only one board sends. Lines in the other board's format are then ignored until the board disconnects (3 s of silence or `LINK DOWN`).

---

## Troubleshooting

| Problem | Fix |
|---|---|
| Upload: `Unable to verify flash chip connection (No more data to read from the serial port)` | Something else has the port open: stop the bridge (Control+C in its terminal, or `pkill -f hardware_bridge.py`), close the game and the Serial Monitor, then upload again. Still failing: **Tools → Upload Speed → 115200**. |
| Upload stops at `Connecting.......` | Hold the board's **BOOT** button while it says Connecting, release when it starts writing. |
| No `usbserial` / `wchusbserial` port appears | Try another USB cable (charge-only cables have no data lines). On older macOS, install the CP210x driver (Silicon Labs) or the CH34x driver (WCH). |
| The cursor drifts on its own | Raise the dead zone (see *Calibrating* above). |
| The cursor moves the wrong way | `JOY_INVERT_X` / `JOY_INVERT_Y` at the top of the sketch. |
| Start screen says NO CONTROLLER | Run `python3 tools/hardware_bridge.py --list`: no port means the cable or driver; a port listed means start the game again, or run the bridge by hand to see its messages. Is `pyserial` installed? |

---

## Tests (no board needed)

```
godot --headless --path . res://tools/checks/check_hardware.tscn   # the game side: both boards, fake messages over UDP
bash hardware/firmware_test/run_sim_test.sh                        # the ESP32 sketch, run on the computer with a fake board
python3 tools/hardware_bridge.py --self-test                       # port detection and line filtering
```

---

## Older: Arduino Uno controller (joystick + 3 buttons)

Still supported by the game and the bridge.

| Part | Uno pin |
|---|---|
| Joystick VRx / VRy | A0 / A1 |
| Joystick +5V, GND | 5V, GND |
| Button 1 **SELECT** (to GND, internal pull-up) | D2 |
| Button 2 **OVERRIDE** (to GND, internal pull-up) | D3 |
| Button 3 **BACK** (to GND, internal pull-up) | D4 |

Upload `protocol_zero_controller/protocol_zero_controller.ino` with board **Arduino Uno**. In the Serial Monitor (115200) it shows `HELLO PZ2`, `HB` every second, `JOY U/D/L/R` and `BTN SELECT / OVERRIDE / BACK`. If the cursor moves the wrong way, change `INVERT_X`, `INVERT_Y` or `SWAP_XY` at the top of that sketch. `controller_circuit.png` is a drawing of this Uno circuit (`make_circuit.py` makes it as an SVG).

**In Tinkercad:** an Arduino Uno R3, a small breadboard, three pushbuttons, and two potentiometers in place of the joystick (wiper to A0 / A1, ends to 5V and GND). Each button: one leg to D2 / D3 / D4, the diagonally opposite leg to the − rail, and the − rail to GND. Paste the sketch under Code → Text and start the simulation. (Tinkercad has no ESP32, so the ESP32 controller can't be simulated there; `hardware/firmware_test/` tests its sketch instead.)
