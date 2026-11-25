#!/usr/bin/env python3
"""Draws the Protocol Zero controller circuit (Arduino Uno + joystick + 3 buttons) as an SVG in the
style of a Tinkercad Circuits breadboard view. Usage: python3 make_circuit.py out.svg"""
import sys

W, H = 1700, 1080
out = []
def add(s): out.append(s)

def rect(x, y, w, h, fill, rx=0, stroke="none", sw=0, extra=""):
    add(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{rx}" fill="{fill}" stroke="{stroke}" stroke-width="{sw}" {extra}/>')

def circle(cx, cy, r, fill, stroke="none", sw=0):
    add(f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="{fill}" stroke="{stroke}" stroke-width="{sw}"/>')

def text(x, y, s, size=14, fill="#222", anchor="middle", weight="normal", rotate=None, family="Arial, Helvetica, sans-serif"):
    tr = f' transform="rotate({rotate} {x} {y})"' if rotate is not None else ""
    add(f'<text x="{x}" y="{y}" font-family="{family}" font-size="{size}" fill="{fill}" text-anchor="{anchor}" font-weight="{weight}"{tr}>{s}</text>')

def wire(points, color, width=7):
    d = "M " + " L ".join(f"{x} {y}" for x, y in points)
    add(f'<path d="{d}" fill="none" stroke="#00000030" stroke-width="{width + 3}" stroke-linecap="round" stroke-linejoin="round"/>')
    add(f'<path d="{d}" fill="none" stroke="{color}" stroke-width="{width}" stroke-linecap="round" stroke-linejoin="round"/>')
    for x, y in (points[0], points[-1]):
        circle(x, y, 4.5, "#d9d9d9", "#555", 1)

add(f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">')
rect(0, 0, W, H, "#f4f5f7")

# ------------------------------------------------------------------ title
text(40, 52, "Protocol Zero controller: Arduino Uno + analog joystick + 3 push buttons", 28, "#1f2937", "start", "bold")
text(40, 82, "Breadboard view (drawn to match the Tinkercad Circuits style). Buttons use the Uno's internal pull-ups, so no resistors are needed.", 16, "#4b5563", "start")

# ------------------------------------------------------------------ Arduino Uno
AX, AY, AW, AH = 290, 190, 540, 420
BLUE, DARK = "#2a6f9e", "#1d5378"
# USB cable + plug
rect(40, AY + 78, 150, 60, "#2b2b2b", 10)
rect(20, AY + 96, 30, 24, "#2b2b2b", 8)
rect(190, AY + 88, 70, 40, "#b8b8b8", 3)
# board
add(f'<path d="M {AX} {AY+12} Q {AX} {AY} {AX+12} {AY} L {AX+AW-40} {AY} L {AX+AW-25} {AY+15} L {AX+AW-25} {AY+95} L {AX+AW} {AY+120} L {AX+AW} {AY+AH-12} Q {AX+AW} {AY+AH} {AX+AW-12} {AY+AH} L {AX+12} {AY+AH} Q {AX} {AY+AH} {AX} {AY+AH-12} Z" fill="{BLUE}"/>')
rect(AX - 45, AY + 70, 120, 76, "#c9c9c9", 3, "#9a9a9a", 2)                      # USB-B socket
rect(AX - 18, AY + 318, 86, 74, "#222", 4)                                      # barrel jack
rect(AX + 22, AY + 22, 46, 46, "#d8d8d8", 4); circle(AX + 45, AY + 45, 13, "#b5492c")   # reset button
rect(AX + 225, AY + 225, 265, 62, "#222", 3)                                     # ATmega328P
for i in range(14):
    rect(AX + 232 + i * 18.5, AY + 219, 9, 6, "#bbb"); rect(AX + 232 + i * 18.5, AY + 287, 9, 6, "#bbb")
circle(AX + 260, AY + 256, 6, "#3a3a3a"); circle(AX + 460, AY + 256, 6, "#3a3a3a")
rect(AX + 92, AY + 188, 86, 30, "#d5d5d5", 15, "#aaa", 2)                        # crystal
rect(AX + 122, AY + 120, 40, 40, "#333", 3)
for cx in (AX + 125, AX + 178):
    circle(cx, AY + 345, 22, "#d0d0d0", "#888", 2); add(f'<path d="M {cx-22} {AY+345} A 22 22 0 0 0 {cx+22} {AY+345} Z" fill="#444"/>')
for cx, cy in ((AX + 76, AY + 18), (AX + AW - 12, AY + 130), (AX + 102, AY + AH - 18), (AX + AW - 12, AY + AH - 60)):
    circle(cx, cy, 10, "#f4f5f7", "#d6c27a", 3)
# logo
add(f'<g fill="none" stroke="#fff" stroke-width="7"><circle cx="{AX+252}" cy="{AY+106}" r="17"/><circle cx="{AX+292}" cy="{AY+106}" r="17"/></g>')
text(AX + 252, AY + 112, "−", 20, "#fff", weight="bold"); text(AX + 292, AY + 113, "+", 20, "#fff", weight="bold")
text(AX + 272, AY + 150, "ARDUINO", 16, "#fff", weight="bold")
add(f'<rect x="{AX+330}" y="{AY+88}" width="78" height="36" rx="18" fill="none" stroke="#fff" stroke-width="2" stroke-dasharray="3 3"/>')
text(AX + 369, AY + 115, "UNO", 26, "#fff")

PITCH = 21
pins = {}
def header(x0, y, labels, label_above):
    rect(x0 - 12, y - 11, len(labels) * PITCH + 3, 22, "#1b1b1b", 2)
    for i, lab in enumerate(labels):
        x = x0 + i * PITCH
        rect(x - 6, y - 6, 12, 12, "#3c3c3c")
        rect(x - 3, y - 3, 6, 6, "#0c0c0c")
        pins[lab] = (x, y)
        ty = y + 22 if label_above else y - 18
        text(x + 4, ty, ("GND" if lab.startswith("GND") else lab), 11, "#fff", "start" if label_above else "end", rotate=90 if label_above else 90)

TOP = AY + 20
header(AX + 108, TOP, ["SCL", "SDA", "AREF", "GND_", "13", "12", "~11", "~10", "~9", "8"], True)
header(AX + 108 + 10 * PITCH + 12, TOP, ["7", "~6", "~5", "4", "~3", "2", "TX1", "RX0"], True)
text(AX + 300, AY + 78, "DIGITAL (PWM ~)", 12, "#fff", weight="bold")
BOT = AY + AH - 20
header(AX + 205, BOT, ["IOREF", "RESET", "3.3V", "5V", "GND", "GND2", "Vin"], False)
header(AX + 205 + 7 * PITCH + 14, BOT, ["A0", "A1", "A2", "A3", "A4", "A5"], False)
# bottom labels are drawn rotated, reading upward from the header
text(AX + 268, AY + AH - 92, "POWER", 12, "#fff", weight="bold"); text(AX + 420, AY + AH - 92, "ANALOG IN", 12, "#fff", weight="bold")

# ------------------------------------------------------------------ breadboard
BX, BY, BW, BH = 870, 330, 790, 420
P = 24
rect(BX, BY, BW, BH, "#e3e3e3", 6, "#c9c9c9", 2)
rect(BX, BY + BH / 2 - 9, BW, 18, "#d2d2d2")
COL0 = BX + 46
def col_x(c): return COL0 + (c - 1) * P            # c = 1..30
ROW_Y = {}
top_rows, bot_rows = "jihgf", "edcba"
for i, r in enumerate(top_rows): ROW_Y[r] = BY + 98 + i * P
for i, r in enumerate(bot_rows): ROW_Y[r] = BY + BH - 98 - (4 - i) * P
RAIL = {"t-": BY + 24, "t+": BY + 48, "b+": BY + BH - 48, "b-": BY + BH - 24}
def hole(x, y): rect(x - 4.5, y - 4.5, 9, 9, "#3b3b3b", 1.5)
for c in range(1, 31):
    for r in ROW_Y: hole(col_x(c), ROW_Y[r])
    text(col_x(c), BY + 80, str(c), 9, "#777"); text(col_x(c), BY + BH - 72, str(c), 9, "#777")
    if (c - 1) % 6 != 5:
        for k in RAIL: hole(col_x(c), RAIL[k])
for r in ROW_Y:
    text(BX + 22, ROW_Y[r] + 4, r, 11, "#777"); text(BX + BW - 22, ROW_Y[r] + 4, r, 11, "#777")
for k, colr in (("t-", "#333"), ("t+", "#d33"), ("b+", "#d33"), ("b-", "#333")):
    yy = RAIL[k] + (-12 if k in ("t-", "b+") else 12)
    add(f'<line x1="{BX+34}" y1="{yy}" x2="{BX+BW-34}" y2="{yy}" stroke="{colr}" stroke-width="1.5"/>')
    text(BX + 18, RAIL[k] + 5, "−" if "-" in k else "+", 14, colr, weight="bold"); text(BX + BW - 18, RAIL[k] + 5, "−" if "-" in k else "+", 14, colr, weight="bold")

# ------------------------------------------------------------------ push buttons (straddle the centre gap)
BTN = [("SELECT", "D2", 5, "#2e9e4f"), ("OVERRIDE", "D3", 14, "#e8871e"), ("BACK", "D4", 23, "#2f7fd1")]
def button(c):
    x1, x2, y1, y2 = col_x(c), col_x(c + 2), ROW_Y["f"], ROW_Y["e"]
    for x in (x1, x2):
        rect(x - 3.5, y1 - 5, 7, 14, "#8f8f8f", 1); rect(x - 3.5, y2 - 9, 7, 14, "#8f8f8f", 1)
    cx, cy = (x1 + x2) / 2, (y1 + y2) / 2
    rect(cx - 27, cy - 20, 54, 40, "#cfcfcf", 5, "#8c8c8c", 2)
    for dx in (-20, 20):
        for dy in (-13, 13): circle(cx + dx, cy + dy, 2.5, "#9a9a9a")
    circle(cx, cy, 14, "#2a2a2a", "#111", 2); circle(cx - 3, cy - 3, 5, "#4a4a4a")

# ------------------------------------------------------------------ joystick module
JX, JY, JW, JH = 380, 775, 260, 250
rect(JX, JY, JW, JH, "#1f1f1f", 8, "#000", 2)
for cx, cy in ((JX + 18, JY + 52), (JX + JW - 18, JY + 52), (JX + 18, JY + JH - 18), (JX + JW - 18, JY + JH - 18)):
    circle(cx, cy, 9, "#f4f5f7", "#c9b36a", 3)
rect(JX + 55, JY + 70, 150, 150, "#bfbfbf", 8, "#8d8d8d", 2)
circle(JX + 130, JY + 145, 62, "#2b2b2b", "#111", 3); circle(JX + 130, JY + 145, 44, "#3a3a3a"); circle(JX + 118, JY + 133, 14, "#4d4d4d")
JPIN = {}
jl = ["GND", "+5V", "VRx", "VRy", "SW"]
rect(JX + 50, JY + 6, len(jl) * 32 + 4, 24, "#111", 2)
for i, lab in enumerate(jl):
    x = JX + 68 + i * 32
    rect(x - 5, JY + 13, 10, 10, "#c8a84a")
    JPIN[lab] = (x, JY + 18)
    text(x, JY + 48, lab, 11, "#fff")
text(JX + JW / 2, JY + JH - 10, "Analog joystick module", 13, "#ddd")

# ------------------------------------------------------------------ wires
# joystick -> Uno (four jumper wires straight up to the bottom headers)
JW_COL = {"GND": "#1c1c1c", "+5V": "#d62f2f", "VRx": "#e6c229", "VRy": "#8e44ad"}
for lab, target, bend in (("GND", "GND", 668), ("+5V", "5V", 690), ("VRx", "A0", 712), ("VRy", "A1", 734)):
    jx, jy = JPIN[lab]; px, py = pins[target]
    wire([(jx, jy), (jx, bend), (px, bend), (px, py)], JW_COL[lab])
# Uno GND -> breadboard bottom "-" rail
gx, gy = pins["GND2"]
wire([(gx, gy), (gx, 640), (845, 640), (845, RAIL["b-"]), (col_x(1), RAIL["b-"])], "#1c1c1c")
# buttons: Dn -> row j on the button's left leg; right leg row a -> "-" rail
for i, (name, pin, c, colr) in enumerate(BTN):
    px, py = pins[pin[1:]] if pin[1:] in pins else pins["~" + pin[1:]]
    up = 150 - i * 18
    wire([(px, py), (px, up), (col_x(c), up), (col_x(c), ROW_Y["j"])], colr)
    wire([(col_x(c + 2), ROW_Y["a"]), (col_x(c + 2), RAIL["b-"])], "#1c1c1c", 6)
for name, pin, c, colr in BTN:
    button(c)
    cx = col_x(c + 1)
    cx = col_x(c) + 14 + 82
    rect(cx - 82, BY - 62, 164, 44, "#ffffff", 8, colr, 3)
    text(cx, BY - 43, f"Button {BTN.index((name, pin, c, colr)) + 1}: {name}", 14, "#111", weight="bold")
    text(cx, BY - 26, f"{pin} → button → GND", 12, "#444")

# ------------------------------------------------------------------ connection table
TX, TY = 870, 800
rect(TX, TY, 790, 222, "#ffffff", 8, "#cfd3da", 2)
text(TX + 20, TY + 30, "Connections", 17, "#111", "start", "bold")
rows = [("#e6c229", "Joystick VRx", "A0", "left / right"), ("#8e44ad", "Joystick VRy", "A1", "up / down"),
        ("#d62f2f", "Joystick +5V", "5V", "power"), ("#1c1c1c", "Joystick GND", "GND", "ground"),
        ("#2e9e4f", "Button 1 SELECT", "D2 and GND rail", "choose / confirm"), ("#e8871e", "Button 2 OVERRIDE", "D3 and GND rail", "Emergency Overclock"),
        ("#2f7fd1", "Button 3 BACK", "D4 and GND rail", "go back / deselect"), ("#1c1c1c", "Breadboard − rail", "GND", "shared ground for the buttons")]
for i, (colr, a, b, c) in enumerate(rows):
    x = TX + 20 + (i // 4) * 390; y = TY + 62 + (i % 4) * 38
    rect(x, y - 12, 34, 9, colr, 4)
    text(x + 46, y - 3, a, 14, "#111", "start", "bold")
    text(x + 46, y + 14, f"{b}  ·  {c}", 12.5, "#555", "start")
text(40, H - 22, "Joystick SW pin is left unconnected. Each button sits across the centre gap; wire one leg to its pin and the diagonally opposite leg to the − rail.", 13, "#6b7280", "start")
add("</svg>")
open(sys.argv[1], "w").write("\n".join(out))
