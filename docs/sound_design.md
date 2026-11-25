# Protocol Zero: Sound Design and Audio Integration Spec

**For:** whoever implements it (a developer or a coding agent) working in the Godot 4.7 project `trialgame/`
**Status:** The game has no audio yet. `scripts/managers/audio_manager.gd` only prints placeholder messages and is never added to the game. There are no audio buses and no sound files.
**Sound source:** sound effects are generated with **ElevenLabs** (Sound Effects v3).
**Research behind this spec:** `docs/research/Tower defense game sound design.md`, with sources.
**Read with:** `docs/HANDOFF.md` (project overview and working rules) and `docs/ui_hud_design.md` (the cyberpunk look).

---

## 0. How to use this document

1. Work **one phase at a time** (§10). At the end of each phase:
   - run the headless checks;
   - list what changed;
   - **stop for review**.
2. **You cannot hear audio.** Verify behaviour with code and headless checks (§10, `check_audio`). Leave anything that depends on how it sounds (levels, which take is best, whether it's annoying) to the human, and give them a short listening checklist.
3. **Code first, sounds later.** Build the whole system so the game runs silently when a sound file is missing: log it once and carry on. The code can then be merged before any audio exists.
4. **Never commit the ElevenLabs API key.** Read it from the `ELEVENLABS_API_KEY` environment variable. Add `.env` and `tools/sfx/raw/` to `.gitignore`.
5. **Don't delete files.** Move anything you replace (for example the old `audio_manager.gd`) into `_to_delete/`.
6. **Gameplay must not change.** Audio only listens and reacts. The only gameplay-file changes allowed are one-line calls to the audio system and the few new signals listed in §4.4.
7. If something in this spec doesn't match the code, trust the code. Adapt the spec and tell the human what was different.

---

## 1. What makes game audio good (research summary)

| Principle | What it means here |
|---|---|
| **Sound is information first, decoration second** | Every event that matters gets one distinct sound that is used for nothing else. A player should be able to hear "the core got hit" with their eyes closed. |
| **Priority, not loudness, decides what's heard** | Overwatch dropped a "loudest sound wins" mix and replaced it with an importance system. Core damage and Overdrive must always cut through 30 towers firing. |
| **Variation, or the sound gets annoying** | Towers fire for a whole session. Every frequent sound needs 2–5 takes, a small random pitch change (about ±1 semitone) and a small random volume change. |
| **Cap and throttle frequent sounds** | Limit how many copies of one sound can play at once and set a minimum gap between replays. The professional audio tools (Unreal, Wwise, CRI) all do this. When many enemies die at once, play one "sweep" sound instead of a stack. |
| **UI grammar** | Rising, in-key sounds mean success. Falling, duller sounds mean failure. **Never use a harsh buzzer for errors.** Quietly reward frequent actions so efficient players aren't annoyed. |
| **Music follows the threat** | Plants vs. Zombies: a calm loop while you plan, drums when the wave arrives, a fuller "horde" layer late in the level. Players complained when the remaster shipped without this. |
| **A voice in the machine** *(optional)* | Defense Grid's talking AI, Fletcher, was widely praised. A system-AI voice fits Protocol Zero's computer-core story. |
| **Mix for laptop speakers** | MacBook speakers reproduce little bass. A cannon "boom" also needs upper-mid content or it vanishes. Check against loudness ≈ **-24 LUFS** over a long session, with peaks at or below **-1 dBTP** (IESD guideline for PC). |
| **Accessibility** | Separate volume and mute for Master, Music, SFX and UI, plus a mono option (Xbox Accessibility Guideline 105). Every audio cue also has a visual cue, which most already do. |

---

## 2. Sound direction for Protocol Zero

**Core rule: defenders sound clean and musical; invaders sound noisy and glitchy.** The player can tell good from bad without looking.

* **Towers and player actions:** clean synth tones, FM "zips", solid mechanical "lock-in" thunks. Pitched rewards stay in one key (for example A minor), so successive sounds fit together.
* **Viruses:** bitcrush, glitch, digital crunch, modem-style noise. Keep the harshest distortion for **rare** threat events, not for sounds that repeat every half second.
* **Ground the digital in the physical:** relay clicks, hard-drive seeks, fan hum, a piezo buzzer. This follows Cyberpunk 2077's "analog feel for even our most futuristic guns" approach. It also ties the game to the team's physical Arduino console.
* **Music references:** darksynth and 90s bleep-techno energy for waves (Hacknet: Carpenter Brut, The Algorithm), and mellow Ghost in the Shell-style pads for build phases (Ruiner's contrast).

### 2.1 Priority ladder (highest first)

| Pri | Category | Examples |
|---|---|---|
| 1 | Core in danger | core_hit, core_crash, core_low_hp |
| 2 | Big moments | overclock_activate, wave_start, victory, defeat |
| 3 | Player actions | tower_place, tower_upgrade, tower_sell, ui_error |
| 4 | Threats to modules | ransomware_mark, tower_locked, trojan_split_warn, worm_bite, tower_destroyed |
| 5 | Combat | fire_*, emp_pulse, hit_* |
| 6 | Deaths | death_small, death_large |
| 7 | Rewards and ambience | energy_tick, amb_server |

When a priority 1 or 2 sound plays, **duck** SFX and Music by about 4–6 dB for about 0.4 s. Do this with a volume tween (§4.3), not a compressor, so it also works in a Web build.

---

## 3. Architecture

### 3.1 Files to create

```
autoloads/audio.gd                   # autoload "Audio" (replaces the unused scripts/managers/audio_manager.gd)
audio/
  sound_bank.gd                      # const SOUNDS registry (§5) — data only
  sfx/<id>/<id>_1.wav, _2.wav ...    # processed one-shots (mono WAV)
  sfx/<id>.tres                      # AudioStreamRandomizer per id (built by tools/sfx/build_randomizers.gd)
  loops/<id>.ogg                     # loops and music (OGG, loop enabled in import)
default_bus_layout.tres              # buses
tools/sfx/
  sfx_list.csv                       # generated from the §6 table
  generate_sfx.py                    # ElevenLabs batch generator
  process_sfx.sh                     # ffmpeg trim/normalise/convert
  build_randomizers.gd               # editor/headless script: wraps takes into .tres
tools/checks/check_audio.gd/.tscn    # headless check
scripts/ui/audio_settings_panel.gd   # volume sliders (pause menu)
```

Register the autoload in `project.godot` **after** `Events`: `Audio="*res://autoloads/audio.gd"`.

### 3.2 Buses (`default_bus_layout.tres`)

```
Master  ── AudioEffectHardLimiter (ceiling -1.0 dB)
 ├─ Music   (start -10 dB)
 ├─ SFX     (start  -4 dB)
 │   └─ (optional, desktop only) AudioEffectLowPassFilter, disabled — pause muffle
 ├─ UI      (start  -6 dB)
 └─ Ambience(start -14 dB)
```

* The starting levels are guesses to tune by ear. Look up buses with `AudioServer.get_bus_index(&"SFX")` and never hard-code the index.
* Godot 4.7 has **no** setting that sends GUI sounds to a bus automatically (it arrives in 4.8). Route UI sounds explicitly to the `UI` bus.
* The old `AudioEffectLimiter` is deprecated. Use `AudioEffectHardLimiter`.

### 3.3 The `Audio` autoload: public API

```gdscript
Audio.play(id: StringName)                       # global one-shot (UI, core, wave, overclock)
Audio.play_at(id: StringName, pos: Vector2)      # positional one-shot (towers, enemies)
Audio.start_loop(id: StringName) / stop_loop(id) # ambience, swarm, firewall hum, low-HP beep
Audio.set_loop_volume(id, linear: float)         # e.g. swarm loop follows enemy count
Audio.music_state(state: StringName)             # &"menu", &"build", &"wave", &"wave_late", &"victory", &"defeat", &"silent"
Audio.duck(db := -5.0, time := 0.4)
Audio.set_bus_linear(bus: StringName, v: float)  # 0..1, saves to user://settings.cfg
Audio.ui(button: BaseButton)                     # connects hover/press sounds to any button
```

### 3.4 Implementation rules

* **Two kinds of player:**
  * A pool of **24 `AudioStreamPlayer2D`** on `SFX` for world sounds. Use `max_distance` ≈ 2400 (about the viewport diagonal) and keep panning subtle: set project setting `audio/general/2d_panning_strength` ≈ 0.3, because the map fills one screen.
  * One `AudioStreamPlayer` with an **`AudioStreamPolyphonic`** stream (32 voices) for global and UI one-shots. Use `play_stream(stream, 0, volume_db, pitch, AudioServer.PLAYBACK_TYPE_DEFAULT, bus)`. It returns `INVALID_ID` (-1) when full; ignore that.
* **Caps and cooldowns per sound id** come from the registry (§5). Before playing, count the active copies of that id and check the time since its last play. If it's over the cap or inside the cooldown, skip it. When the pool is full, take the oldest voice that has the **lowest priority**, and never take a priority 1–2 voice for a lower one.
* **Variation:** every frequent id points to an `AudioStreamRandomizer` `.tres`:
  * `playback_mode = PLAYBACK_RANDOM_NO_REPEATS`;
  * `random_pitch_semitones` ≈ 1.0 (this property exists in 4.6+; use `random_pitch` ≈ 1.06 otherwise);
  * `random_volume_offset_db` ≈ 2.0.
* **Pause:**
  * The autoload node is `PROCESS_MODE_ALWAYS`, so UI and music keep working.
  * The world SFX pool is `PROCESS_MODE_PAUSABLE`, so tower and enemy sounds freeze with the game.
  * On pause, tween Music down about 6 dB. If the build is not for the Web, also enable the SFX low-pass.
* **Missing files:** if a registry path doesn't exist, `push_warning` once for that id and play nothing. The game must never crash or stall because of audio.
* **Kill batching:** if 4 or more `death_small` requests arrive within 120 ms, play `death_sweep` once instead.
* **Settings:**
  * Save the Master, Music, SFX, UI and Ambience values, plus `mono`, to `user://settings.cfg` with `ConfigFile`.
  * At 0, call `AudioServer.set_bus_mute(idx, true)`, because `linear_to_db(0)` is -inf.
  * For mono, set `AudioServer.set_bus_effect_enabled` on a disabled `AudioEffectPanner` / stereo-enhance on Master, or simply set 2D panning strength to 0.
* **Web builds** (itch.io): Godot ≥4.3 Web exports default to "Sample" playback, where **bus effects (compressor, low-pass, reverb) don't run**. That's why ducking and the pause muffle are done with **volume tweens**, which always work. Treat the low-pass as an optional desktop extra.

---

## 4. Hooking sounds into the game

### 4.1 Existing `Events` signals → sounds (connect in `Audio._ready`)

| Signal | Sound | Notes |
|---|---|---|
| `tower_placed(type, grid)` | `tower_place` at `Globals.grid_to_world(grid)` | |
| `tower_upgraded(type, grid, path, tier)` | `tower_upgrade` (tier 1–2), `tower_upgrade_t3` (tier 3) | Pitch +2 semitones per tier for tiers 1–2 |
| `tower_sold(type, grid, refund)` | `tower_sell` | |
| `tower_repaired(node, cost)` | `tower_repair` at the node | |
| `tower_destroyed(type, grid)` | `tower_destroyed` | Priority 4 |
| `placement_invalid(reason)` | `ui_error` | Soft, never a buzzer |
| `energy_insufficient(req, have)` | `ui_error` | Cooldown 250 ms |
| `tower_selected` / `tower_deselected` | `ui_select` / none | |
| `ability_used(node, id)` | `ability_purge` / `ability_freeze` by `id` | |
| `overclock_used(energy)` | `overclock_activate` + `duck()` | This is also the hardware "Overdrive" button |
| `system_load_changed(load, max)` | `load_warning` when crossing ≥60 upward, `load_critical` when crossing ≥90 | Only on the upward crossing |
| `system_crashed()` | `core_crash` + `duck(-8)` | |
| `enemy_defeated(type, reward, pos)` | `death_small` or `death_large` at `pos` (map below) and a batched `energy_tick` | `energy_tick` cap 2, cooldown 90 ms |
| `enemy_split(pos, count, data)` | `trojan_split` at `pos` | |
| `worm_spread(pos, ...)` | `worm_spread` at `pos` | |
| `base_damaged(dmg, hp)` | `core_hit` + `duck()` | Cooldown 150 ms |
| `base_health_changed(hp, max)` | `start_loop(&"core_low_hp")` when hp ≤ 30% of max; stop above that or on level end | |
| `wave_started(n)` | `wave_start`, then `music_state(&"wave")`; from wave 7 on `music_state(&"wave_late")` | |
| `wave_completed(n, bonus)` | `wave_clear`, then `music_state(&"build")` | |
| `victory()` / `game_over()` | `victory` / `defeat` stingers, `music_state(&"victory"/&"defeat")`, stop all loops | |
| `game_state_changed(old, new)` | `new == PAUSED` → `ui_pause` and the pause duck; `old == PAUSED` → `ui_resume` | `game_paused` / `game_resumed` exist in `events.gd` but nothing emits them. Use `game_state_changed`. |
| `level_selected(i)` | `level_start`, `music_state(&"build")`, `start_loop(&"amb_server")` | |

**Death size map:**
* `death_small`: BASIC_VIRUS, WORM, DDOS_BOT and Trojan Minis.
* `death_large`: TROJAN_HORSE, RANSOMWARE, SPYWARE, ROOTKIT.

### 4.2 Direct calls to add (one line each)

| File / function | Call |
|---|---|
| `scripts/towers/base_tower.gd` `fire_at()` | `Audio.play_at(fire_id, global_position)`. The tower type gives `fire_id`: Cannon → `fire_cannon`, Data Spike → `fire_spike`, Firewall Beam → `fire_beam`. Add a `fire_sound` key to `TOWER_DATA` instead of a `match`. |
| `scripts/towers/emp_tower.gd` `_pulse()` | `Audio.play_at(&"emp_pulse", global_position)`. The EMP overrides `fire_at()`, so the call goes in `_pulse()`, not in the base `fire_at()`. |
| `scripts/towers/base_tower.gd` `on_projectile_hit()` | `Audio.play_at(&"hit_generic", enemy.global_position)` |
| `scripts/enemies/base_enemy.gd` `take_damage()` | When Rootkit armour reduced the hit and it wasn't armour-piercing: `Audio.play_at(&"hit_armor", global_position)` |
| `scripts/enemies/trojan_horse.gd` | When `split_progress()` first passes 0.75: `Audio.play_at(&"trojan_split_warn", global_position)`, once per Trojan. This is the on-screen warning before the split that the framework asks for. |
| `scripts/enemies/worm.gd` `_attack_modules()` | `Audio.play_at(&"worm_bite", module.global_position)` |
| `scripts/enemies/ransomware.gd` `_pick_target()` / `_lock()` | `ransomware_mark` at the target module; `tower_locked` at the module |
| `scripts/main/main.gd` countdowns | On each of the last 3 whole seconds of the build/wave countdown: `Audio.play(&"countdown_tick")` |
| `scripts/ui/*.gd` and `main.gd` | Call `Audio.ui(btn)` on every Button created (menus, tower panel, upgrade cards, ability and overclock buttons) |
| Swarm loop | In `Audio._process`, about 4 times a second, count live DDoS bots (nodes in group `"enemies"` whose type is `DDOS_BOT`). Play `swarm_loop` and set its volume to `clamp(count/30, 0, 1)` |

### 4.3 Music states

| State | When | Content |
|---|---|---|
| `menu` | Main menu / level select | Moody pad loop |
| `build` | Build phase and countdown | **Base layer only** (calm pads + soft pulse) |
| `wave` | Waves 1–6 | Base + **drums/bass layer** |
| `wave_late` | Waves 7–10 | Base + drums + **"horde" lead layer** |
| `victory` / `defeat` | End screens | One-shot stinger, then silence or the menu loop |

* **Layering:** use one `AudioStreamSynchronized` (Godot 4.3+) with three stems: base, drums, lead. Fade each stem in or out over about 1.5 s with `set_sync_stream_volume(i, db)` driven by a tween. Silent stems sit at -60 dB.
* **Between menu and gameplay:** a simple crossfade between two `AudioStreamPlayer`s. `AudioStreamInteractive` is optional.
* **Until music assets exist:** `music_state()` just stores the state and does nothing.
* **Music sources** (the team is on the ElevenLabs Free plan, so Eleven Music is **not** available):
  1. **Short loop beds from the SFX endpoint** with `loop: true` (up to 30 s each). Generate them as three stems for `AudioStreamSynchronized`:
     * `music_base`: "Calm dark synth pad with a soft slow pulse, cyberpunk, 90 BPM, seamless loop, no drums"
     * `music_drums`: "Driving electronic drum and bass groove, darksynth, 90 BPM, seamless loop, no melody"
     * `music_lead`: "Aggressive gritty synth arpeggio lead, darksynth, 90 BPM, seamless loop, no drums"
     * `music_menu`: one moody pad loop

     These stems won't line up perfectly. If the drums or lead drift against the base, fall back to swapping whole loops per state with a 1.5 s crossfade instead of layering.
  2. **Royalty-free music**, with a licence that allows non-commercial use in a student game. The team checks the licence and credits the composer next to the ElevenLabs credit.

  Add `music_*` rows to `sfx_list.csv`, about 4 × 20 s ≈ 3,200 credits. **This doesn't fit in one month together with the full SFX set**, so generate SFX in month 1 and music in month 2, or use royalty-free music. Set loop (and `bpm`/`beat_count` if known) in the OGG import settings.

### 4.4 New signals allowed (additive only)

* `Events.overclock_ready`: emitted by `OverclockManager` when `cooldown_left` reaches 0 while unlocked. It plays `overclock_ready`, and the hardware LED will use it later.
* `Events.trojan_split_warning(pos)` *(optional)*, if you prefer a signal to a direct call.

---

## 5. Sound registry format (`audio/sound_bank.gd`)

```gdscript
const SOUNDS := {
    &"fire_cannon": {"path": "res://audio/sfx/fire_cannon.tres", "bus": &"SFX", "pos": true,
                     "pri": 5, "cap": 4, "cooldown_ms": 50, "db": -6.0},
    &"core_hit":    {"path": "res://audio/sfx/core_hit.tres", "bus": &"SFX", "pos": false,
                     "pri": 1, "cap": 2, "cooldown_ms": 150, "db": 0.0},
    # ... one entry per id in §6
}
```

`db` is the per-sound level trim, set by ear after generation. Caps and cooldowns are **starting values**; no source gives tested numbers.

---

## 6. Sound list and ElevenLabs prompts

**Style suffix** (add to every one-shot prompt):
`, clean digital sci-fi game sound effect, one-shot, dry, no reverb, no music, no voice`

**Loop suffix** (instead, for loops):
`, seamless loop, no music, no voice`

| id | Prompt (before suffix) | Dur (s) | Loop | Takes | Pri | Cap / cd (ms) | Bus |
|---|---|---|---|---|---|---|---|
| **UI** | | | | | | | |
| ui_hover | Very short soft high digital tick | 0.5 | – | 2 | 7 | 2 / 40 | UI |
| ui_click | Sharp, high plastic click with a tiny bright digital blip | 0.5 | – | 3 | 3 | 3 / 30 | UI |
| ui_confirm | Two quick rising clean synth notes, positive confirmation chime | 0.6 | – | 2 | 3 | 2 / 60 | UI |
| ui_back | Two quick falling soft synth notes, gentle | 0.5 | – | 2 | 3 | 2 / 60 | UI |
| ui_error | Soft muted low double blip, descending, dull and gentle, not a buzzer | 0.5 | – | 2 | 3 | 1 / 250 | UI |
| ui_select | Short crisp scanner lock-on beep | 0.5 | – | 2 | 3 | 2 / 60 | UI |
| ui_pause | Quick downward tape-stop style synth swoop, soft | 0.7 | – | 1 | 2 | 1 / 200 | UI |
| ui_resume | Quick upward synth swoop, soft | 0.7 | – | 1 | 2 | 1 / 200 | UI |
| countdown_tick | Clean digital countdown tick, short metallic beep | 0.5 | – | 1 | 2 | 1 / 500 | UI |
| **Building** | | | | | | | |
| tower_place | Heavy mechanical lock-in thunk, then a short rising electronic power-up hum | 1.0 | – | 3 | 3 | 2 / 80 | SFX |
| tower_upgrade | Mechanical lock-in thunk, then three quick rising clean arpeggio notes | 1.0 | – | 2 | 3 | 2 / 100 | SFX |
| tower_upgrade_t3 | Powerful energy surge rising, then a bright resonant chord hit, triumphant tech upgrade | 1.8 | – | 2 | 2 | 1 / 300 | SFX |
| tower_sell | Quick descending digital blips like data being refunded, then a soft click | 0.8 | – | 2 | 3 | 2 / 100 | SFX |
| tower_repair | Short electric welding crackle, then a gentle rising confirmation tone | 1.0 | – | 2 | 3 | 2 / 150 | SFX |
| tower_destroyed | Electrical short circuit pop, then sparks and a sad falling power-down whine | 1.5 | – | 2 | 4 | 2 / 200 | SFX |
| tower_locked | Heavy digital padlock clamp, then a short ominous encrypted glitch | 1.0 | – | 2 | 4 | 2 / 200 | SFX |
| **Tower attacks** | | | | | | | |
| fire_cannon | Short punchy square-wave blaster thunk with a burst of white noise | 0.5 | – | 4 | 5 | 4 / 50 | SFX |
| fire_spike | Very short bright FM laser zip with fast pitch drop, sharp piercing | 0.5 | – | 4 | 5 | 3 / 60 | SFX |
| fire_beam | Thin crackling electric laser beam fire, short burst | 0.6 | – | 3 | 5 | 3 / 80 | SFX |
| emp_pulse | Deep electric EMP discharge, low whump, then fading crackle | 1.0 | – | 3 | 5 | 2 / 150 | SFX |
| hit_generic | Tiny crisp digital impact tick, subtle | 0.5 | – | 4 | 6 | 5 / 35 | SFX |
| hit_armor | Small hard metallic clank, deflected hit on armor plating | 0.5 | – | 3 | 5 | 3 / 80 | SFX |
| ability_purge | Charging high whine, then a massive sharp digital blast cleansing the screen | 2.0 | – | 2 | 2 | 1 / 500 | SFX |
| ability_freeze | Crystalline freeze, rising shimmer, then a deep frozen digital stasis hum | 2.0 | – | 2 | 2 | 1 / 500 | SFX |
| **Viruses** | | | | | | | |
| death_small | Crunchy bitcrushed digital pop as a computer virus is deleted, glitch | 0.5 | – | 4 | 6 | 4 / 40 | SFX |
| death_large | Bigger corrupted data explosion, glitchy crunch then digital debris scatter | 1.0 | – | 3 | 6 | 3 / 80 | SFX |
| death_sweep | Rapid burst of many small glitchy digital pops, like a cluster of files deleted at once | 1.0 | – | 2 | 6 | 1 / 200 | SFX |
| trojan_split_warn | Rising glitchy alarm chirp, unstable digital warbling, building tension | 1.0 | – | 2 | 4 | 2 / 300 | SFX |
| trojan_split | Digital object cracking open, then three small glitchy chirps scattering | 1.0 | – | 2 | 4 | 2 / 300 | SFX |
| worm_bite | Quick wet-sounding digital chomp with a short electric crackle | 0.5 | – | 3 | 4 | 3 / 100 | SFX |
| worm_spread | Squelchy glitch replicate sound, a digital organism duplicating | 0.8 | – | 2 | 4 | 2 / 200 | SFX |
| ransomware_mark | Ominous dial-up modem screech fragment, short warning, target locked | 1.0 | – | 2 | 4 | 2 / 400 | SFX |
| **Core and Overdrive** | | | | | | | |
| core_hit | Unique short urgent alarm tone with a low impact thump, computer core damaged | 0.8 | – | 3 | 1 | 2 / 150 | SFX |
| core_crash | System crash: loud electrical failure, then a falling power-down and digital static | 2.5 | – | 1 | 1 | 1 / 1000 | SFX |
| overclock_activate | Rising charge-up whine, then a wide powerful electrical surge, overdrive engaged | 2.0 | – | 2 | 2 | 1 / 500 | SFX |
| overclock_ready | Short bright two-tone ready chime, energy recharged | 0.6 | – | 1 | 3 | 1 / 1000 | UI |
| load_warning | Single amber warning beep, computer system strain | 0.6 | – | 1 | 3 | 1 / 1000 | UI |
| load_critical | Double urgent red-alert beep, system overheating | 0.8 | – | 1 | 2 | 1 / 1000 | UI |
| **Waves and level** | | | | | | | |
| level_start | System boot-up sequence: hard-drive spin-up, then clean startup chime | 2.5 | – | 1 | 2 | 1 / – | SFX |
| wave_start | Incoming connection alert: modem handshake chirp, then a deep synth alarm swell | 2.5 | – | 2 | 2 | 1 / – | SFX |
| wave_clear | Resolving clean synth chord with a soft scan-complete chime | 2.0 | – | 2 | 2 | 1 / – | SFX |
| victory | Triumphant short synthwave fanfare stinger, bright and resolved | 4.0 | – | 2 | 2 | 1 / – | Music |
| defeat | Ominous system failure stinger, distorted descending synth and static fade | 4.0 | – | 2 | 2 | 1 / – | Music |
| **Loops** | | | | | | | |
| amb_server | Low server room hum with fans, faint hard-drive clicks and soft electrical buzz | 20 | ✔ | 1 | 7 | – | Ambience |
| core_low_hp | Slow repeating warning beep, about one beep per second, with a low pulse | 4 | ✔ | 1 | 1 | – | SFX |
| swarm_loop | Dense buzzing swarm of tiny glitchy digital insects, chattering data noise | 10 | ✔ | 1 | 6 | – | SFX |

**Credit estimate:** about 45 sounds × about 1.2 s × about 2.3 takes ≈ 125 s, plus loops ≈ 34 s. That's about **160 s × 40 credits ≈ 6,400 credits**. It fits in the Free plan's 10,000 a month (§8), with about 3,600 left for re-takes. Generate the high-priority sounds first (core, Overdrive, tower fire, deaths, wave, UI) in case credits run out.

---

## 7. Generating and processing the sounds

### 7.1 `tools/sfx/generate_sfx.py`

* `pip install elevenlabs` (official SDK). The key comes from `ELEVENLABS_API_KEY`.
* Read `sfx_list.csv` with columns: `id, prompt, duration, loop, takes, prompt_influence`.
* For each take, call:

  ```python
  from elevenlabs.client import ElevenLabs
  client = ElevenLabs()  # reads ELEVENLABS_API_KEY
  audio = client.text_to_sound_effects.convert(
      text=prompt + suffix,
      duration_seconds=duration,       # always set (0.5–30)
      prompt_influence=0.7,            # 0.6–0.8 for a consistent set; default is 0.3
      loop=is_loop,                    # check the param name against the installed SDK version
      model_id="eleven_text_to_sound_v3",   # ALWAYS set; API default is deprecated v2 (removed 1 Mar 2027)
      output_format="mp3_44100_128",   # PCM/WAV via API needs the Pro plan
  )
  with open(f"tools/sfx/raw/{id}/{id}_{n}.mp3", "wb") as f:
      for chunk in audio: f.write(chunk)
  ```

* Run the requests **one at a time**, because Free allows only 2 at once and Starter 3. Skip files that already exist so the script can be re-run, and retry a 429 error after 5 s.
* If v3 returns "Unknown model", stop and tell the human. Don't silently switch to v2.
* Print the total seconds requested and the estimated credits **before** generating, then ask for confirmation (`--yes` to skip).

### 7.2 `tools/sfx/process_sfx.sh` (ffmpeg)

**One-shots:** trim the silence at the start and end, normalise, then save as mono 44.1 kHz WAV:

```bash
ffmpeg -y -i in.mp3 -af "silenceremove=start_periods=1:start_threshold=-50dB,areverse,silenceremove=start_periods=1:start_threshold=-50dB,areverse,loudnorm=I=-18:TP=-1.5:LRA=11" -ac 1 -ar 44100 out.wav
```

ElevenLabs v3 output volume varies by 15–20 dB between clips, so normalising is essential. For clips under about 1 s `loudnorm` is unreliable; peak-normalise to -3 dBFS instead.

**Loops:** **don't trim**, because that breaks the seamless loop point. Normalise and convert to OGG:

```bash
ffmpeg -y -i in.mp3 -af "loudnorm=I=-24:TP=-2" -c:a libvorbis -q:a 6 out.ogg
```

Then enable **Loop** in Godot's import dock.

### 7.3 Picking takes and importing

* The **human** listens and keeps the best 2–3 takes of each frequent sound and 1 of each rare one. Delete nothing; move rejects to `tools/sfx/rejected/`.
* `build_randomizers.gd` wraps each id's kept WAVs into `audio/sfx/<id>.tres` (`AudioStreamRandomizer`).
* Keep the WAV import defaults (QOA compression, the 4.4+ default). Leave loops as OGG with `loop = true`.

---

## 8. Licensing — DECIDED: ElevenLabs Free plan, non-commercial course project

The team uses the **Free plan** and the game **will not be released or sold**. That is allowed, with these rules:

* **Attribution is required.** Add a credit line **"Sound effects generated with ElevenLabs (elevenlabs.io)"**:
  * on the main menu (small footer text) **and**
  * in any credits screen, the course report and the demo video description.

  This is part of Phase F and checked in `check_audio` (the string must exist in the main menu scene or script).
* **No commercial use, ever.** Free-plan sounds can't be switched to commercial later. If the game is ever sold, these sounds must be regenerated on a paid plan.
* **Don't publish the raw sound files** as a pack or library. Shipping them inside the game build and the course submission is fine.
* **Free-plan limits that affect the tools:**
  * 10,000 credits a month. The §6 set is about 6,400, which leaves about 3,600 for re-takes.
  * At most 2 requests at once, so the generator runs one request at a time.
  * Output is MP3 only (`mp3_44100_128`), so it is always converted with ffmpeg (§7.2).
  * The generator must print the credit estimate and stop if it is above 9,000.
* **Eleven Music is paid-only, so it isn't available.** Music comes from the alternatives in §4.3.

---

## 9. Accessibility and settings

* **Pause menu:** an "AUDIO" panel with sliders for Master, Music, SFX, UI and Ambience (0–100%), a **Mono** toggle and **Mute all**. Style it to match the cyberpunk HUD (`ui_hud_design.md`).
* **Every audio cue keeps a visual cue:**
  * core_hit → the core flash already exists;
  * trojan_split_warn → a visual ring or flash;
  * ransomware_mark → a mark icon;
  * load warnings → the System Load bar colour.
* Nothing important is communicated by sound alone.
* No sound above about 4 kHz is both loud and sustained. Keep harsh glitch and bitcrush sounds short.

---

## 10. Implementation phases (stop for review after each)

| Phase | Work | Done when |
|---|---|---|
| **A. Skeleton** | Buses, the `Audio` autoload, an **empty** registry with all ids from §6, the player pool, caps/cooldowns/priority stealing, missing-file handling, settings save/load. Move the old `audio_manager.gd` to `_to_delete/`. | The game runs exactly as before with no audio files; `check_audio` passes |
| **B. Hooks** | All §4.1 signal connections, the §4.2 one-line calls, `Audio.ui()` on every button, `overclock_ready` signal | `check_audio` shows every hook firing the right id (use a fake bank that records calls) |
| **C. Generation tools** | `sfx_list.csv` from §6, `generate_sfx.py`, `process_sfx.sh`, `build_randomizers.gd`. **Don't run generation;** the human runs it with their key. | Scripts run with `--dry-run`, which prints the request list and credit estimate |
| **D. Assets in** | After the human generates and picks takes: build the randomizers, fill in the registry paths | All ids resolve to files; no warnings |
| **E. Music** | `AudioStreamSynchronized` stems and the state switching from §4.3 (stub it if there's no music yet) | State changes are correct in `check_audio` |
| **F. Settings UI and polish** | Audio panel, mono, pause duck, kill batching, swarm loop, low-HP loop, **ElevenLabs credit line on the main menu** (§8) | Human listening test passes (checklist below) |

### `tools/checks/check_audio.gd`

It must check:

* every registry id has the required fields;
* playing an id with no file doesn't crash;
* a cap of N blocks the N+1th copy;
* a cooldown blocks a quick replay;
* priority 1 can take a voice from priority 6 but not the other way round;
* `set_bus_linear(…, 0)` mutes the bus;
* settings survive a save/load round-trip;
* every §4.1 signal triggers its id;
* the death batching rule.

### Human listening checklist (give this to the human after phases D–F)

1. With 20 or more towers firing on Level 3, wave 8, can you still clearly hear the core being hit?
2. After 10 minutes, does any sound feel grating? Name it, then lower its `db` or raise its cooldown.
3. Can you tell a virus dying from a tower firing with your eyes closed?
4. Is the error sound gentle, not a buzzer?
5. Does the music clearly lift when a wave starts and settle when it ends?
6. Check on MacBook speakers **and** headphones: are the cannon and EMP still audible on speakers?
7. Do all sliders control what they say? Does Mute all really mute?

---

## 11. Open decisions for the team

1. **Web build or desktop?** If Web (itch.io), skip all bus effects. This spec already avoids depending on them.
2. ~~Free or paid ElevenLabs?~~ **Decided: Free plan, never released** (§8). Attribution is required.
3. **Music source:** short SFX-endpoint loops (next month's credits) or royalty-free (§4.3).
4. **Operator voice** *(optional, Defense Grid-style)*, using ElevenLabs text-to-speech: "Wave incoming", "Core integrity critical", "Overdrive online". If yes, add a `Voice` bus and a priority 2 voice channel that ducks Music.
5. **Hardware:** the course spec lists a buzzer on the physical console. It could play a short alert at the same moment as `core_hit` and `wave_start`, linking the game sound to the console.
