#!/usr/bin/env python3
"""Generates the game's sound effects with ElevenLabs (docs/sound_design.md §7.1).

    python3 tools/sfx/generate_sfx.py --dry-run          # list the requests and the credit cost, call nothing
    python3 tools/sfx/generate_sfx.py                     # generate (asks first)
    python3 tools/sfx/generate_sfx.py --yes               # generate without asking
    python3 tools/sfx/generate_sfx.py --only core_hit,fire_cannon
    python3 tools/sfx/generate_sfx.py --list tools/sfx/music_list.csv   # the music loops (month 2, see the README)

Each take is saved as tools/sfx/raw/<id>/<id>_<n>.mp3. Files that already exist are skipped, so the script can be
stopped and re-run at any time; only the missing takes are requested (and counted in the estimate).

Needs: pip3 install elevenlabs, and the key in the ELEVENLABS_API_KEY environment variable (never in a file
that is committed). The Free plan allows 2 requests at once, so requests run one at a time.
"""
import argparse
import csv
import inspect
import os
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DEFAULT_LIST = os.path.join(ROOT, "tools", "sfx", "sfx_list.csv")
RAW_DIR = os.path.join(ROOT, "tools", "sfx", "raw")

MODEL_ID = "eleven_text_to_sound_v3"   # always set: the API default is the deprecated v2
OUTPUT_FORMAT = "mp3_44100_128"        # the Free plan only gives MP3; process_sfx.sh converts it
CREDITS_PER_SECOND = 40                # the spec's figure (§6) for a request with a set duration
FREE_PLAN_STOP = 9000                  # §8: stop if a run would cost more than this (10,000 a month on Free)
MIN_DURATION, MAX_DURATION = 0.5, 30.0
RETRY_WAIT = 5.0                       # seconds to wait after a 429 (too many requests)
MAX_RETRIES = 5

ONE_SHOT_SUFFIX = ", clean digital sci-fi game sound effect, one-shot, dry, no reverb, no music, no voice"
LOOP_SUFFIX = ", seamless loop, no music, no voice"
MUSIC_SUFFIX = ", seamless loop, no voice"   # for the music_* stems in music_list.csv (they *are* music)
# The victory and defeat stingers are short pieces of music, so their suffix leaves out "no music"
STINGER_IDS = {"victory", "defeat"}
STINGER_SUFFIX = ", clean digital sci-fi game sound, one-shot, dry, no reverb, no voice"


def read_list(path):
    """The rows of the sound list, with the numbers parsed."""
    rows = []
    with open(path, newline="", encoding="utf-8") as f:
        for i, row in enumerate(csv.DictReader(f), start=2):
            try:
                rows.append({
                    "id": row["id"].strip(),
                    "prompt": row["prompt"].strip(),
                    "duration": min(max(float(row["duration"]), MIN_DURATION), MAX_DURATION),
                    "loop": row["loop"].strip().lower() in ("true", "1", "yes"),
                    "takes": int(row["takes"]),
                    "prompt_influence": float(row.get("prompt_influence") or 0.7),
                })
            except (KeyError, ValueError) as e:
                sys.exit("%s line %d is not valid (%s)" % (path, i, e))
    return rows


def requests_for(rows):
    """One request per take that doesn't exist yet: (row, take number, output path)."""
    todo, done = [], 0
    for row in rows:
        for n in range(1, row["takes"] + 1):
            out = os.path.join(RAW_DIR, row["id"], "%s_%d.mp3" % (row["id"], n))
            if os.path.exists(out):
                done += 1
            else:
                todo.append((row, n, out))
    return todo, done


def full_prompt(row):
    if row["id"].startswith("music_"):
        return row["prompt"] + MUSIC_SUFFIX
    if row["id"] in STINGER_IDS:
        return row["prompt"] + STINGER_SUFFIX
    return row["prompt"] + (LOOP_SUFFIX if row["loop"] else ONE_SHOT_SUFFIX)


def print_plan(todo, done):
    seconds = sum(row["duration"] for row, _, _ in todo)
    credits = int(round(seconds * CREDITS_PER_SECOND))
    print("%-20s %4s %6s %5s  %s" % ("id", "take", "dur s", "loop", "prompt"))
    for row, n, _ in todo:
        print("%-20s %4d %6.1f %5s  %s" % (row["id"], n, row["duration"], "yes" if row["loop"] else "-", full_prompt(row)))
    print()
    print("Requests: %d (already on disk, skipped: %d)" % (len(todo), done))
    print("Seconds requested: %.1f" % seconds)
    print("Estimated credits: %d  (%d per second; Free plan: 10,000 a month)" % (credits, CREDITS_PER_SECOND))
    return credits


def make_client():
    if not os.environ.get("ELEVENLABS_API_KEY"):
        sys.exit("Set your key first:  export ELEVENLABS_API_KEY=...   (never write it into a project file)")
    try:
        from elevenlabs.client import ElevenLabs
    except ImportError:
        sys.exit("The ElevenLabs package is missing. Install it with:  pip3 install elevenlabs")
    return ElevenLabs()  # reads ELEVENLABS_API_KEY


def convert(client, row):
    """Calls the API once and returns the MP3 bytes."""
    kwargs = dict(
        text=full_prompt(row),
        duration_seconds=row["duration"],
        prompt_influence=row["prompt_influence"],
        model_id=MODEL_ID,
        output_format=OUTPUT_FORMAT,
    )
    if row["loop"]:
        kwargs["loop"] = True
    audio = client.text_to_sound_effects.convert(**kwargs)
    return b"".join(audio) if not isinstance(audio, (bytes, bytearray)) else bytes(audio)


def status_of(err):
    return getattr(err, "status_code", None) or getattr(getattr(err, "response", None), "status_code", None)


def generate(todo, client):
    os.makedirs(RAW_DIR, exist_ok=True)
    open(os.path.join(RAW_DIR, ".gdignore"), "a").close()  # keeps Godot from importing the raw MP3s
    params = inspect.signature(client.text_to_sound_effects.convert).parameters
    accepts_loop = "loop" in params
    if not accepts_loop and any(row["loop"] for row, _, _ in todo):
        sys.exit("This version of the elevenlabs package has no 'loop' option, but the list has loops.\n"
                 "Update it (pip3 install -U elevenlabs) or run with --only on the one-shots.")
    for i, (row, n, out) in enumerate(todo, start=1):
        os.makedirs(os.path.dirname(out), exist_ok=True)
        for attempt in range(1, MAX_RETRIES + 1):
            try:
                data = convert(client, row)
                break
            except Exception as err:  # the SDK raises its own ApiError; check the status code
                text = str(err)
                if "unknown model" in text.lower() or "model_not_found" in text.lower() or "invalid model" in text.lower():
                    sys.exit("ElevenLabs does not know the model '%s'. Stopping: tell whoever maintains the tools "
                             "(the spec says not to fall back to the old v2 model).\n%s" % (MODEL_ID, text))
                if status_of(err) == 429 and attempt < MAX_RETRIES:
                    print("  busy (429), retrying in %.0f s..." % RETRY_WAIT)
                    time.sleep(RETRY_WAIT)
                    continue
                sys.exit("Request for %s take %d failed: %s\n(Takes already saved are kept; re-run to continue.)"
                         % (row["id"], n, text))
        # write to a temporary name first so a half-written file never counts as done
        with open(out + ".part", "wb") as f:
            f.write(data)
        os.replace(out + ".part", out)
        print("[%d/%d] %s take %d -> %s" % (i, len(todo), row["id"], n, os.path.relpath(out, ROOT)))
    print("Done. Next: bash tools/sfx/process_sfx.sh")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--dry-run", action="store_true", help="print the requests and the credit estimate, call nothing")
    ap.add_argument("--yes", action="store_true", help="don't ask before generating")
    ap.add_argument("--only", default="", help="comma-separated ids to generate (default: all)")
    ap.add_argument("--list", default=DEFAULT_LIST, help="the sound list CSV (default: tools/sfx/sfx_list.csv)")
    a = ap.parse_args()

    rows = read_list(a.list)
    if a.only:
        wanted = {x.strip() for x in a.only.split(",") if x.strip()}
        unknown = wanted - {r["id"] for r in rows}
        if unknown:
            sys.exit("Not in %s: %s" % (os.path.basename(a.list), ", ".join(sorted(unknown))))
        rows = [r for r in rows if r["id"] in wanted]
    todo, done = requests_for(rows)
    credits = print_plan(todo, done)
    if a.dry_run:
        print("Dry run: nothing was requested.")
        return
    if not todo:
        print("Every take already exists. Nothing to do.")
        return
    if credits > FREE_PLAN_STOP:
        sys.exit("Stopping: %d credits is more than the %d limit for the Free plan. Use --only to split the run."
                 % (credits, FREE_PLAN_STOP))
    client = make_client()  # checks the key and the package before asking
    if not a.yes:
        try:
            answer = input("Generate %d takes for about %d credits? Type yes to continue: " % (len(todo), credits))
        except EOFError:
            answer = ""
        if answer.strip().lower() not in ("yes", "y"):
            print("Cancelled.")
            return
    generate(todo, client)


if __name__ == "__main__":
    main()
