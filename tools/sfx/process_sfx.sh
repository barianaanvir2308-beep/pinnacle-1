#!/usr/bin/env bash
# process_sfx.sh — turns the generated MP3s into game-ready files (docs/sound_design.md §7.2)
#
#   bash tools/sfx/process_sfx.sh             # process every take in tools/sfx/raw/
#   bash tools/sfx/process_sfx.sh --dry-run   # print what it would do, change nothing (works without ffmpeg)
#   bash tools/sfx/process_sfx.sh --force     # redo files that were already processed
#
# One-shots: silence trimmed from both ends, level normalised, saved as mono 44.1 kHz WAV in
#            audio/sfx/<id>/<id>_<n>.wav. Clips of 1 s or more use loudnorm (-18 LUFS, -1.5 dBTP); shorter clips
#            are peak-normalised to -3 dBFS instead, because loudnorm is unreliable on very short sounds.
# Loops:     not trimmed (that would break the loop point), loudnorm to -24 LUFS, saved as OGG in
#            audio/loops/<id>.ogg (or <id>_<n>.ogg when there are several takes: keep one and rename it).
#            Then enable Loop for it in Godot's Import dock.
# Which ids are loops is read from tools/sfx/sfx_list.csv and tools/sfx/music_list.csv.
#
# Needs ffmpeg (macOS: brew install ffmpeg).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RAW="${SFX_RAW_DIR:-$ROOT/tools/sfx/raw}"   # SFX_RAW_DIR overrides it (used to test the script)
SFX_OUT="$ROOT/audio/sfx"
LOOP_OUT="$ROOT/audio/loops"
SHORT_CLIP=1.0      # seconds: below this, peak-normalise instead of loudnorm
PEAK_TARGET=-3.0    # dBFS for short clips

DRY=0
FORCE=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY=1 ;;
    --force) FORCE=1 ;;
    -h|--help) sed -n '2,19p' "$0"; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

if [ "$DRY" -eq 0 ] && ! command -v ffmpeg >/dev/null 2>&1; then
  echo "ffmpeg is not installed. On a Mac: brew install ffmpeg   (or use --dry-run to see the plan)" >&2
  exit 1
fi

# OGG encoder: Homebrew's plain ffmpeg has no libvorbis, so fall back to ffmpeg's built-in Vorbis encoder
VORBIS_ARGS=(-c:a libvorbis -q:a 6 -ar 44100)
if [ "$DRY" -eq 0 ] && ! ffmpeg -hide_banner -encoders 2>/dev/null | grep -q libvorbis; then
  VORBIS_ARGS=(-c:a vorbis -strict -2 -ac 2 -b:a 192k -ar 44100)
fi

# ids marked as loops in the sound lists (prompts contain commas, so parse the CSV properly)
LOOP_IDS=" $(python3 - "$ROOT" <<'PY'
import csv, os, sys
root = sys.argv[1]
ids = []
for name in ("sfx_list.csv", "music_list.csv"):
    path = os.path.join(root, "tools", "sfx", name)
    if os.path.exists(path):
        with open(path, newline="", encoding="utf-8") as f:
            ids += [r["id"] for r in csv.DictReader(f) if r["loop"].strip().lower() in ("true", "1", "yes")]
print(" ".join(ids))
PY
) "

is_loop() { [[ "$LOOP_IDS" == *" $1 "* ]]; }

run() {  # print the command in a dry run, otherwise run it quietly
  if [ "$DRY" -eq 1 ]; then
    echo "  $*"
  else
    "$@" -hide_banner -loglevel error
  fi
}

TRIM="silenceremove=start_periods=1:start_threshold=-50dB,areverse,silenceremove=start_periods=1:start_threshold=-50dB,areverse"

if [ ! -d "$RAW" ] || [ -z "$(find "$RAW" -name '*.mp3' -print -quit 2>/dev/null)" ]; then
  echo "No generated sounds in tools/sfx/raw/ yet. Run tools/sfx/generate_sfx.py first."
  [ "$DRY" -eq 1 ] && echo "(Dry run: with takes present, each would be converted as described at the top of this file.)"
  exit 0
fi

done_count=0
skip_count=0
for dir in "$RAW"/*/; do
  id="$(basename "$dir")"
  takes=("$dir"*.mp3)
  [ -e "${takes[0]}" ] || continue
  for src in "${takes[@]}"; do
    name="$(basename "$src" .mp3)"          # <id>_<n>
    if is_loop "$id"; then
      [ "$DRY" -eq 1 ] || mkdir -p "$LOOP_OUT"
      if [ "${#takes[@]}" -eq 1 ]; then out="$LOOP_OUT/$id.ogg"; else out="$LOOP_OUT/$name.ogg"; fi
      if [ "$FORCE" -eq 0 ] && [ -f "$out" ] && [ "$out" -nt "$src" ]; then skip_count=$((skip_count + 1)); continue; fi
      echo "loop     $id -> ${out#$ROOT/}"
      run ffmpeg -y -i "$src" -af "loudnorm=I=-24:TP=-2" "${VORBIS_ARGS[@]}" "$out"
    else
      [ "$DRY" -eq 1 ] || mkdir -p "$SFX_OUT/$id"
      out="$SFX_OUT/$id/$name.wav"
      if [ "$FORCE" -eq 0 ] && [ -f "$out" ] && [ "$out" -nt "$src" ]; then skip_count=$((skip_count + 1)); continue; fi
      if [ "$DRY" -eq 1 ]; then
        echo "one-shot $id -> ${out#$ROOT/}  (loudnorm, or peak -3 dBFS if under ${SHORT_CLIP}s after trimming)"
        run ffmpeg -y -i "$src" -af "$TRIM,loudnorm=I=-18:TP=-1.5:LRA=11" -ac 1 -ar 44100 "$out"
      else
        tmp="$(mktemp -t pz_sfx).wav"
        ffmpeg -y -hide_banner -loglevel error -i "$src" -af "$TRIM" -ac 1 -ar 44100 "$tmp"
        length="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$tmp")"
        if awk -v d="$length" -v s="$SHORT_CLIP" 'BEGIN { exit !(d < s) }'; then
          peak="$(ffmpeg -hide_banner -i "$tmp" -af volumedetect -f null - 2>&1 | sed -n 's/.*max_volume: \(-*[0-9.]*\) dB.*/\1/p')"
          gain="$(awk -v p="${peak:-0}" -v t="$PEAK_TARGET" 'BEGIN { printf "%.2f", t - p }')"
          echo "one-shot $id -> ${out#$ROOT/}  (${length}s, peak ${peak} dB, gain ${gain} dB)"
          ffmpeg -y -hide_banner -loglevel error -i "$tmp" -af "volume=${gain}dB" -ac 1 -ar 44100 "$out"
        else
          echo "one-shot $id -> ${out#$ROOT/}  (${length}s, loudnorm)"
          ffmpeg -y -hide_banner -loglevel error -i "$tmp" -af "loudnorm=I=-18:TP=-1.5:LRA=11" -ac 1 -ar 44100 "$out"
        fi
        rm -f "$tmp"
      fi
    fi
    done_count=$((done_count + 1))
  done
done

echo
if [ "$DRY" -eq 1 ]; then
  echo "Dry run: $done_count file(s) would be processed, $skip_count already up to date. Nothing was changed."
else
  echo "Processed $done_count file(s), $skip_count already up to date."
  echo "Next: listen to the takes in audio/sfx/<id>/, move the ones you don't want to tools/sfx/rejected/<id>/,"
  echo "then build the randomizers (see tools/sfx/README.md)."
fi
