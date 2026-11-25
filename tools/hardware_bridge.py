#!/usr/bin/env python3
"""Protocol Zero hardware bridge: controller board (USB serial) <-> Godot (UDP on localhost).

Godot 4 has no built-in serial port API, so this small program sits between the controller and the game:

    board --serial 115200--> bridge --UDP 127.0.0.1:9101--> game

It works with both controller boards and passes their lines on unchanged:
    Arduino Uno   (hardware/protocol_zero_controller)  HELLO PZ2, HB, JOY U|D|L|R, BTN SELECT|OVERRIDE|BACK
    ESP32 DevKit  (hardware/protocol_zero_esp32)       HELLO PZ3, HB PZ3, JOY <dx> <dy>, BTN SELECT|SELECT_LONG|OVERDRIVE
The board is found by the USB chip's vendor ID: the Uno's own (Arduino), or the USB-serial chip on ESP32 boards and
Uno clones (Silicon Labs CP210x, WCH CH340/CH9102, FTDI).

The controller has no screen or lights, so the game sends nothing back. (Anything the game does send to UDP 9102
is still passed on to the board.)

The bridge also tells the game whether a board is plugged in, with its own lines:
    "LINK UP <port>"   a serial port was opened
    "LINK DOWN"        no board, or the board was unplugged (the game then ignores the controller)

Usage
    pip3 install pyserial
    python3 tools/hardware_bridge.py                 # finds the board automatically
    python3 tools/hardware_bridge.py --port COM5     # or /dev/cu.usbmodem1101 (Uno) / /dev/cu.usbserial-0001 (ESP32)
    python3 tools/hardware_bridge.py --list          # show the serial ports and which one would be picked
    python3 tools/hardware_bridge.py --self-test     # check the port detection and line filter (no board needed)

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
# USB vendor IDs, best match first. The ESP32 DevKit's USB-serial chip is a CP2102 or a CH340.
BOARD_VIDS = {
    0x2341: "Arduino",                     # genuine Uno (its own USB chip)
    0x2A03: "Arduino.org",
    0x10C4: "Silicon Labs CP210x (ESP32)",
    0x1A86: "WCH CH340/CH9102 (ESP32 or Uno clone)",
    0x0403: "FTDI",
}
ARDUINO_VIDS = set(BOARD_VIDS)            # kept under the old name
# Port names that look like a board when the vendor ID isn't known (macOS, Linux, the CP210x/CH340 drivers)
PORT_NAME_HINTS = ("usbmodem", "ttyacm", "usbserial", "ttyusb", "slab_usbtouart", "wchusbserial")
MAX_LINE = 256


def log(msg):
    print("[bridge] " + msg, flush=True)


def pick_port(ports):
    """Best guess at the board's port from a list of pyserial port infos: (device, why), or (None, None).

    A known USB vendor ID wins (in the order of BOARD_VIDS), then a port whose name looks like a board."""
    for vid, chip in BOARD_VIDS.items():
        for p in ports:
            if getattr(p, "vid", None) == vid:
                return p.device, chip
    for p in ports:
        name = (p.device or "").lower()
        if any(h in name for h in PORT_NAME_HINTS):
            return p.device, "name looks like a USB serial board"
    return None, None


def find_port(serial_tools):
    """The board's port, or None."""
    return pick_port(list(serial_tools.comports()))[0]


def clean_line(raw):
    """A line from the board as text, or None if it is noise.

    After a reset the ESP32 prints its boot log (partly at another baud rate, so it arrives as junk bytes). Lines
    with anything but printable ASCII, or longer than MAX_LINE, are dropped; the game ignores unknown text lines."""
    raw = raw.strip()
    if not raw or len(raw) > MAX_LINE or any(b < 0x20 or b > 0x7E for b in raw):
        return None
    return raw.decode("ascii")


def open_port(serial, port, baud):
    """Opens the port without resetting the board. On ESP32 DevKits the DTR and RTS lines drive the reset (EN)
    and boot (IO0) pins, so they are held off before opening; on an Uno this only skips its auto-reset."""
    ser = serial.Serial()
    ser.port = port
    ser.baudrate = baud
    ser.timeout = 0
    ser.dtr = False
    ser.rts = False
    ser.open()
    return ser


def self_test():
    """Checks pick_port and clean_line with made-up ports and lines. Needs no board and no pyserial."""
    class P:
        def __init__(self, device, vid=None):
            self.device, self.vid = device, vid
    cases = [
        ("Uno", [P("/dev/cu.Bluetooth-Incoming-Port"), P("/dev/cu.usbmodem1101", 0x2341)], "/dev/cu.usbmodem1101"),
        ("ESP32 with CP2102", [P("/dev/cu.Bluetooth-Incoming-Port"), P("/dev/cu.usbserial-0001", 0x10C4)], "/dev/cu.usbserial-0001"),
        ("ESP32 with CH340", [P("/dev/cu.wchusbserial1420", 0x1A86)], "/dev/cu.wchusbserial1420"),
        ("Windows CP2102", [P("COM1"), P("COM5", 0x10C4)], "COM5"),
        ("Linux CH340", [P("/dev/ttyS0"), P("/dev/ttyUSB0", 0x1A86)], "/dev/ttyUSB0"),
        ("old CP210x driver name, no VID", [P("/dev/cu.SLAB_USBtoUART")], "/dev/cu.SLAB_USBtoUART"),
        ("Uno beats an unknown USB serial port", [P("/dev/cu.usbserial-99"), P("/dev/cu.usbmodem1", 0x2341)], "/dev/cu.usbmodem1"),
        ("nothing plugged in", [P("/dev/cu.Bluetooth-Incoming-Port"), P("/dev/cu.debug-console")], None),
    ]
    fails = 0
    for name, ports, want in cases:
        got = pick_port(ports)[0]
        ok = got == want
        fails += not ok
        print("  %s  port: %s -> %s" % ("ok  " if ok else "FAIL", name, got))
    lines = [
        (b"HELLO PZ3\r", "HELLO PZ3"), (b"HB PZ3", "HB PZ3"), (b"JOY -1 0", "JOY -1 0"), (b"BTN SELECT_LONG", "BTN SELECT_LONG"),
        (b"ets Jul 29 2019 12:21:46", "ets Jul 29 2019 12:21:46"),   # boot text: passed on, the game ignores it
        (b"\x00\xe2\x80\x9a\xff junk", None), (b"   ", None), (b"X" * 300, None),
    ]
    for raw, want in lines:
        got = clean_line(raw)
        ok = got == want
        fails += not ok
        print("  %s  line: %r -> %r" % ("ok  " if ok else "FAIL", raw[:30], got))
    print("bridge self-test: %d failure(s)" % fails)
    return 1 if fails else 0


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--port", help="serial port (default: auto-detect)")
    ap.add_argument("--baud", type=int, default=BAUD)
    ap.add_argument("--list", action="store_true", help="list the serial ports and the one that would be used")
    ap.add_argument("--self-test", action="store_true", help="test port detection and line filtering, then exit")
    a = ap.parse_args()
    if a.self_test:
        sys.exit(self_test())

    try:
        import serial
        import serial.tools.list_ports as serial_tools
    except ImportError:
        log("pyserial is not installed: run  pip3 install pyserial")
        sys.exit(2)

    if a.list:
        ports = list(serial_tools.comports())
        for p in ports:
            vid = getattr(p, "vid", None)
            print("  %-34s vid %-6s %s" % (p.device, "0x%04X" % vid if vid else "-", BOARD_VIDS.get(vid, "")))
        port, why = pick_port(ports)
        print("would use: %s%s" % (port or "nothing (no board found)", " (%s)" % why if why else ""))
        return

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
            port, why = (a.port, "given with --port") if a.port else pick_port(list(serial_tools.comports()))
            if port:
                try:
                    ser = open_port(serial, port, a.baud)
                    buf = b""
                    port_name = port
                    last_error = ""
                    log("connected to %s (%s)" % (port, why))
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
                    line = clean_line(raw)
                    if line:
                        to_game(line)
                if len(buf) > MAX_LINE:  # garbage with no newline: drop it
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
