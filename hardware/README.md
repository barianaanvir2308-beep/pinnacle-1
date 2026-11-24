# Protocol Zero — Arduino Overdrive console

The console is optional. With it unplugged (or with no Python), the game plays exactly as before with mouse and keyboard.

## Parts and pins

| Part | Pin |
|---|---|
| Push button (to GND, internal pull-up) | D2 |
| Red LED + 220 Ω resistor (to GND) | D9 |
| 16×2 LCD with I2C backpack | SDA A4, SCL A5, 5V, GND |

## 1. Upload the sketch (once)

1. Arduino IDE → Library Manager → install **LiquidCrystal I2C** (Frank de Brabander).
2. Open `protocol_zero_console/protocol_zero_console.ino`, board **Arduino Uno**, pick the port, Upload.
3. If the LCD stays blank, change `LCD_ADDRESS` (0x27, 0x3F, or 0x20 in Tinkercad) and upload again.
4. Optional test in the Serial Monitor (115200 baud, newline): type `K 5`, `S READY`, `S COOLDOWN 10`; press the button and see `BTN OVERDRIVE`.

Close the Serial Monitor before starting the game: only one program can use the port.

## 2. Install the bridge's one dependency (once)

```
pip3 install pyserial
```

## 3. Play

Plug the Arduino in and start the game. The game starts `tools/hardware_bridge.py` by itself; when the board is
found the HUD shows **CONSOLE LINKED** and the LCD shows the kill count. If it doesn't connect, run the bridge by hand
in a terminal to see what it says:

```
python3 tools/hardware_bridge.py            # or: --port /dev/cu.usbmodem1101 (macOS), COM5 (Windows)
```

| LCD line 2 / LED | Meaning |
|---|---|
| OVERDRIVE READY / solid | Press the button for +150 Energy (adds 50 System Load) |
| COOLDOWN 12s / slow blink | Wait |
| LOCKED / off | Not unlocked yet (Level 1 before wave 3), paused, or in a menu |
| SYSTEM CRASH / fast blink | System Load hit 100: towers offline |
| NO SIGNAL / off | The game stopped talking to the board for 3 s |

## Test without a board

```
godot --headless --path . res://tools/checks/check_hardware.tscn
```
