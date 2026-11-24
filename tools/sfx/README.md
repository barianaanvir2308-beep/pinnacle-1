# Making the game's sounds

How to turn the sound list into sounds the game plays (docs/sound_design.md §7). Run every command from the
project folder (`cd ~/Desktop/trialgame`). Steps 1 to 4 cost ElevenLabs credits only in step 3.

| File | What it is |
|---|---|
| `sfx_list.csv` | Every sound: id, prompt, length, loop, number of takes. Made from the §6 table, highest-priority sounds first. |
| `music_list.csv` | The 4 music loops. Kept apart because they cost 3,200 credits (generate them next month). |
| `generate_sfx.py` | Asks ElevenLabs for each take and saves `raw/<id>/<id>_<n>.mp3` |
| `process_sfx.sh` | Trims, levels and converts the MP3s into the files the game uses |
| `build_randomizers.gd` | Wraps the takes you keep into one file per sound, which plays a random take each time |
| `raw/`, `rejected/` | Generated MP3s, and takes you didn't keep. Godot ignores both folders. |

## 1. Install the tools (once)

```bash
pip3 install elevenlabs
```

```bash
brew install ffmpeg
```

## 2. Check the plan and the cost

```bash
python3 tools/sfx/generate_sfx.py --dry-run
```

This calls nothing. It lists every request and the estimated credits: about **5,400** for the full set (the Free
plan gives 10,000 a month). The script refuses to start a run above 9,000.

## 3. Generate

Put your key in the terminal session only. **Never write it into a file in the project.**

```bash
export ELEVENLABS_API_KEY=your-key-here
```

```bash
python3 tools/sfx/generate_sfx.py
```

It shows the estimate again and asks you to type `yes`. Requests run one at a time (the Free plan allows 2 at once).
You can stop it at any time with Ctrl+C and run it again: takes already saved are skipped and not paid for twice.
To try a few sounds first:

```bash
python3 tools/sfx/generate_sfx.py --only core_hit,fire_cannon,death_small
```

If it says ElevenLabs doesn't know the model, stop and report it: the spec says not to fall back to the old model.

## 4. Process

```bash
bash tools/sfx/process_sfx.sh
```

One-shots go to `audio/sfx/<id>/<id>_<n>.wav`, loops to `audio/loops/<id>.ogg`. Add `--dry-run` to see what it
would do first. Run it again after generating more takes: finished files are skipped.

## 5. Listen and pick (you)

Listen to each sound's takes in `audio/sfx/<id>/` (Finder's Quick Look: select a file and press Space).

* Keep the best **2 or 3** takes of sounds that repeat a lot (shots, hits, deaths, clicks) and the best **1** of rare
  ones (crash, victory, level start).
* Move the others to `tools/sfx/rejected/<id>/`. Don't delete them.
* A sound is bad everywhere? Change its prompt in `sfx_list.csv`, move its MP3s from `raw/<id>/` to `rejected/`,
  and generate it again with `--only <id>`.
* For each loop in `audio/loops/`: open the project in Godot, select the `.ogg` file, tick **Loop** in the Import
  dock and press **Reimport**. If a loop has several takes, keep one and rename it `<id>.ogg`.

## 6. Build the randomizers

```bash
~/Desktop/Godot/Godot.app/Contents/MacOS/Godot --headless --path . --import
```

```bash
~/Desktop/Godot/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tools/sfx/build_randomizers.gd
```

This writes `audio/sfx/<id>.tres` for every sound that has takes. The game picks them up straight away: start it
and the sounds play. Sounds without files stay silent (one warning each in the Output panel).

## Credits

The sounds are made on the ElevenLabs Free plan, so the game must show the line
**"Sound effects generated with ElevenLabs (elevenlabs.io)"** (main menu, credits, report, video description), may
never be sold, and the raw sound files may not be published as a pack (docs/sound_design.md §8).
