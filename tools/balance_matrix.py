#!/usr/bin/env python3
"""Runs check_balance for every level x bot in parallel and prints a table (level x bot).

    python3 tools/balance_matrix.py                  # all 5 levels x 4 bots
    python3 tools/balance_matrix.py --levels 1 2     # only some levels
    python3 tools/balance_matrix.py --bots spammer   # only some bots
    python3 tools/balance_matrix.py --jobs 10        # how many Godot processes at once (default 10)
    python3 tools/balance_matrix.py --realtime       # use real frame timing (results then vary by about 20 HP per run)

By default Godot runs with --fixed-fps 60, so every frame is exactly the same length and the same game always
gives the same result (and runs much faster).

Each run's full log is saved in tools/balance_logs/<bot>_L<level>.txt (with the per-wave breakdown).
Needs the Godot path below; override it with the GODOT environment variable.
"""
import argparse, os, re, subprocess, sys
from concurrent.futures import ThreadPoolExecutor

GODOT = os.environ.get("GODOT", os.path.expanduser("~/Desktop/Godot/Godot.app/Contents/MacOS/Godot"))
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BOTS = ["specialist", "spammer", "upgrader", "controller"]
LOGS = os.path.join(ROOT, "tools", "balance_logs")


def run(level, bot, fixed=True):
    os.makedirs(LOGS, exist_ok=True)
    log = os.path.join(LOGS, "%s_L%d.txt" % (bot, level))
    cmd = [GODOT, "--headless"] + (["--fixed-fps", "60"] if fixed else []) + ["--path", ROOT, "res://tools/checks/check_balance.tscn", "--",
           "--level=%d" % level, "--bot=%s" % bot, "--detail"]
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=1500).stdout
    except subprocess.TimeoutExpired:
        out = "RESULT level=%d bot=%s outcome=TIMEOUT hp=0 wave=0 ddos=-\n" % (level, bot)
    open(log, "w").write(out)
    m = re.search(r"^RESULT level=(\d+) bot=(\S+) outcome=(\S+) hp=(-?\d+) wave=(\d+) ddos=(\S+)", out, re.M)
    if not m:
        return {"level": level, "bot": bot, "outcome": "ERROR", "hp": 0, "wave": 0, "ddos": "-"}
    return {"level": level, "bot": bot, "outcome": m.group(3), "hp": int(m.group(4)), "wave": int(m.group(5)), "ddos": m.group(6)}


def cell(r):
    if r["outcome"] == "CLEARED":
        return "%d HP" % r["hp"]
    if r["outcome"] == "FAILED":
        return "died w%d" % r["wave"]
    return r["outcome"]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--levels", type=int, nargs="*", default=[1, 2, 3, 4, 5])
    ap.add_argument("--bots", nargs="*", default=BOTS)
    ap.add_argument("--jobs", type=int, default=10)
    ap.add_argument("--realtime", action="store_true")
    a = ap.parse_args()
    jobs = [(l, b) for l in a.levels for b in a.bots]
    with ThreadPoolExecutor(a.jobs) as ex:
        results = list(ex.map(lambda j: run(j[0], j[1], not a.realtime), jobs))
    res = {(r["level"], r["bot"]): r for r in results}

    width = 14
    print("\nLevel x bot  (cleared: Arduino HP left; failed: wave the Arduino died on)\n")
    print("%-18s" % "" + "".join("%-*s" % (width, b) for b in a.bots))
    names = {1: "L1 Bootloader", 2: "L2 Dual Bus", 3: "L3 Spiral Core", 4: "L4 Firewall", 5: "L5 Kernel Panic"}
    for l in a.levels:
        print("%-18s" % names[l] + "".join("%-*s" % (width, cell(res[(l, b)])) for b in a.bots))

    if 5 in a.levels:
        print("\nL5 DDoS Bots that reached the Arduino, per swarm wave (wave:leaks; each leak = 1 HP)\n")
        for b in a.bots:
            print("  %-12s %s" % (b, res[(5, b)]["ddos"].replace(",", "  ")))

    print("\nTargets")
    ok_all = True
    for l, need_all in ((1, True), (2, True)):
        if l in a.levels:
            n = sum(res[(l, b)]["outcome"] == "CLEARED" for b in a.bots)
            ok = n == len(a.bots)
            ok_all &= ok
            print("  %s: all %d bots clear -> %s (%d clear)" % (names[l], len(a.bots), "PASS" if ok else "FAIL", n))
    for l in (3, 4, 5):
        if l in a.levels:
            n = sum(res[(l, b)]["outcome"] == "CLEARED" for b in a.bots)
            ok = n >= 2
            ok_all &= ok
            print("  %s: at least 2 bots clear -> %s (%d clear)" % (names[l], "PASS" if ok else "FAIL", n))
    if all(l in a.levels for l in (1, 2, 3, 4, 5)):
        dominant = [b for b in a.bots if all(res[(l, b)]["outcome"] == "CLEARED" and res[(l, b)]["hp"] >= 60 for l in a.levels)]
        ok = not dominant
        ok_all &= ok
        print("  no bot clears all 5 levels with >= 60 HP -> %s%s" % ("PASS" if ok else "FAIL", "" if ok else " (dominant: %s)" % ", ".join(dominant)))
    print("\nOverall: %s" % ("PASS" if ok_all else "FAIL"))


main()
