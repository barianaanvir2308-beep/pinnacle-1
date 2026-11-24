#!/usr/bin/env python3
"""Protocol Zero hardware bridge: Arduino (USB serial) <-> Godot (UDP on localhost).

Godot 4 has no built-in serial port API, so this small program sits between the Arduino console and the game:

    Arduino --serial 115200--> bridge --UDP 127.0.0.1:9101--> game   (HELLO PZ1, HB, BTN OVERDRIVE)
    Arduino <--serial 115200-- bridge <--UDP 127.0.0.1:9102-- game   (K <n>, S READY / S COOLDOWN <s> / ..., PING)

The bridge also tells the game whether a board is plugged in, with its own lines:
    "LINK UP <port>"   a serial port was opened
    "LINK DOWN"        no board, or the board was unplugged (the game then ignores the console)

Usage
    pip3 install pyserial
    python3 tools/hardware_bridge.py                 # finds the Arduino automatically
    python3 tools/hardware_bridge.py --port COM5     # or /dev/cu.usbmodem1101 on macOS, /dev/ttyACM0 on Linux

The game starts this script by itself when it can (see scripts/managers/hardware_link.gd), so normally you only
need pyserial installed. If the board is unplugged the bridge keeps retrying every second, and the game keeps
working with mouse and keyboard.
"""
import argparse
import socket
import sys
import time

GAME_ADDR = ("127.0.0.1", 9101)   # the game listens here
BRIDGE_ADDR = ("127.0.0.1", 9102)  # the bridge listens here for lines from the game
BAUD = 115200
ARDUINO_VIDS = {0x2341, 0x2A03, 0x1A86, 0x0403, 0x10C4}  # Arduino, Arduino.org, CH340 clones, FTDI, CP210x


def log(msg):
    print("[bridge] " + msg, flush=True)


def find_port(serial_tools):
    """Best guess at the Arduino's port: a known USB vendor first, then anything that looks like one."""
    ports = list(serial_tools.comports())
    for p in ports:
        if p.vid in ARDUINO_VIDS:
            return p.device
    for p in ports:
        name = (p.device or "").lower()
        if "usbmodem" in name or "ttyacm" in name or "usbserial" in name or "ttyusb" in name:
            return p.device
    return None


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--port", help="serial port (default: auto-detect)")
    ap.add_argument("--baud", type=int, default=BAUD)
    a = ap.parse_args()

    try:
        import serial
        import serial.tools.list_ports as serial_tools
    except ImportError:
        log("pyserial is not installed: run  pip3 install pyserial")
        sys.exit(2)

    udp = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        udp.bind(BRIDGE_ADDR)
    except OSError:
        log("port %d is busy: another bridge is probably running already" % BRIDGE_ADDR[1])
        sys.exit(3)
    udp.setblocking(False)

    def to_game(line):
        udp.sendto((line + "\n").encode("ascii", "replace"), GAME_ADDR)

    ser = None
    buf = b""
    next_try = 0.0
    last_status = 0.0
    port_name = ""
    last_error = ""
    log("ready: game on udp %d, listening on udp %d" % (GAME_ADDR[1], BRIDGE_ADDR[1]))
    while True:
        now = time.monotonic()

        # 1. (re)open the serial port
        if ser is None and now >= next_try:
            port = a.port or find_port(serial_tools)
            if port:
                try:
                    ser = serial.Serial(port, a.baud, timeout=0)
                    buf = b""
                    port_name = port
                    last_error = ""
                    log("connected to " + port)
                    to_game("LINK UP " + port)
                except (serial.SerialException, OSError) as e:
                    if str(e) != last_error:  # log each problem once, not every second
                        log("cannot open %s: %s" % (port, e))
                        last_error = str(e)
                    ser = None
            next_try = now + 1.0
        if now - last_status >= 1.0:
            # repeated once a second so a game started after the bridge still learns the link state
            to_game("LINK UP " + port_name if ser is not None else "LINK DOWN")
            last_status = now

        # 2. Arduino -> game
        if ser is not None:
            try:
                data = ser.read(256)
            except (serial.SerialException, OSError):
                log("board unplugged")
                ser = None
                to_game("LINK DOWN")
                continue
            if data:
                buf += data
                while b"\n" in buf:
                    raw, buf = buf.split(b"\n", 1)
                    line = raw.strip().decode("ascii", "replace")
                    if line:
                        to_game(line)
                if len(buf) > 256:  # garbage with no newline: drop it
                    buf = b""

        # 3. game -> Arduino
        while True:
            try:
                pkt, _ = udp.recvfrom(512)
            except BlockingIOError:
                break
            except OSError:
                break
            if ser is not None:
                try:
                    ser.write(pkt if pkt.endswith(b"\n") else pkt + b"\n")
                except (serial.SerialException, OSError):
                    log("board unplugged")
                    ser = None
                    to_game("LINK DOWN")

        time.sleep(0.002)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
