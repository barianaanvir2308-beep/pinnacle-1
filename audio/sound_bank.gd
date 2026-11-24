# sound_bank.gd — the sound registry: one entry per sound id (docs/sound_design.md §5 and §6). Data only.
#
# Fields:
#   path         the file to play. One-shots point to an AudioStreamRandomizer (.tres) that wraps the takes; loops to an
#                .ogg. The files don't exist until the sounds are generated (Phase C/D); a missing file is skipped
#                with one warning.
#   bus          the audio bus it plays on (Master > Music / SFX / UI / Ambience, see default_bus_layout.tres)
#   pos          true: a place on the map (Audio.play_at), false: global (Audio.play)
#   pri          priority, 1 = most important (core in danger) ... 7 = rewards and ambience. When all voices are busy,
#                a sound can only take a voice from a sound with the same or a lower priority (higher number).
#   cap          most copies of this id that may play at once
#   cooldown_ms  least time between two plays of this id (0 = none)
#   db           level trim, set by ear once the sounds exist
#   loop         true for loops (Audio.start_loop)
# Caps and cooldowns are the spec's starting values; no source gives tested numbers.
extends RefCounted

const SOUNDS := {
	# ---- UI ----
	&"ui_hover": {"path": "res://audio/sfx/ui_hover.tres", "bus": &"UI", "pos": false, "pri": 7, "cap": 2, "cooldown_ms": 40, "db": -6.0, "loop": false},
	&"ui_click": {"path": "res://audio/sfx/ui_click.tres", "bus": &"UI", "pos": false, "pri": 3, "cap": 3, "cooldown_ms": 30, "db": -6.0, "loop": false},
	&"ui_confirm": {"path": "res://audio/sfx/ui_confirm.tres", "bus": &"UI", "pos": false, "pri": 3, "cap": 2, "cooldown_ms": 60, "db": -6.0, "loop": false},
	&"ui_back": {"path": "res://audio/sfx/ui_back.tres", "bus": &"UI", "pos": false, "pri": 3, "cap": 2, "cooldown_ms": 60, "db": -6.0, "loop": false},
	&"ui_error": {"path": "res://audio/sfx/ui_error.tres", "bus": &"UI", "pos": false, "pri": 3, "cap": 1, "cooldown_ms": 250, "db": -6.0, "loop": false},
	&"ui_select": {"path": "res://audio/sfx/ui_select.tres", "bus": &"UI", "pos": false, "pri": 3, "cap": 2, "cooldown_ms": 60, "db": -6.0, "loop": false},
	&"ui_pause": {"path": "res://audio/sfx/ui_pause.tres", "bus": &"UI", "pos": false, "pri": 2, "cap": 1, "cooldown_ms": 200, "db": -6.0, "loop": false},
	&"ui_resume": {"path": "res://audio/sfx/ui_resume.tres", "bus": &"UI", "pos": false, "pri": 2, "cap": 1, "cooldown_ms": 200, "db": -6.0, "loop": false},
	&"countdown_tick": {"path": "res://audio/sfx/countdown_tick.tres", "bus": &"UI", "pos": false, "pri": 2, "cap": 1, "cooldown_ms": 500, "db": -8.0, "loop": false},
	# ---- Building ----
	&"tower_place": {"path": "res://audio/sfx/tower_place.tres", "bus": &"SFX", "pos": true, "pri": 3, "cap": 2, "cooldown_ms": 80, "db": 0.0, "loop": false},
	&"tower_upgrade": {"path": "res://audio/sfx/tower_upgrade.tres", "bus": &"SFX", "pos": true, "pri": 3, "cap": 2, "cooldown_ms": 100, "db": 0.0, "loop": false},
	&"tower_upgrade_t3": {"path": "res://audio/sfx/tower_upgrade_t3.tres", "bus": &"SFX", "pos": true, "pri": 2, "cap": 1, "cooldown_ms": 300, "db": 0.0, "loop": false},
	&"tower_sell": {"path": "res://audio/sfx/tower_sell.tres", "bus": &"SFX", "pos": true, "pri": 3, "cap": 2, "cooldown_ms": 100, "db": 0.0, "loop": false},
	&"tower_repair": {"path": "res://audio/sfx/tower_repair.tres", "bus": &"SFX", "pos": true, "pri": 3, "cap": 2, "cooldown_ms": 150, "db": 0.0, "loop": false},
	&"tower_destroyed": {"path": "res://audio/sfx/tower_destroyed.tres", "bus": &"SFX", "pos": true, "pri": 4, "cap": 2, "cooldown_ms": 200, "db": 0.0, "loop": false},
	&"tower_locked": {"path": "res://audio/sfx/tower_locked.tres", "bus": &"SFX", "pos": true, "pri": 4, "cap": 2, "cooldown_ms": 200, "db": 0.0, "loop": false},
	# ---- Tower attacks ----
	&"fire_cannon": {"path": "res://audio/sfx/fire_cannon.tres", "bus": &"SFX", "pos": true, "pri": 5, "cap": 4, "cooldown_ms": 50, "db": 0.0, "loop": false},
	&"fire_spike": {"path": "res://audio/sfx/fire_spike.tres", "bus": &"SFX", "pos": true, "pri": 5, "cap": 3, "cooldown_ms": 60, "db": 0.0, "loop": false},
	&"fire_beam": {"path": "res://audio/sfx/fire_beam.tres", "bus": &"SFX", "pos": true, "pri": 5, "cap": 3, "cooldown_ms": 80, "db": 0.0, "loop": false},
	&"emp_pulse": {"path": "res://audio/sfx/emp_pulse.tres", "bus": &"SFX", "pos": true, "pri": 5, "cap": 2, "cooldown_ms": 150, "db": 0.0, "loop": false},
	&"hit_generic": {"path": "res://audio/sfx/hit_generic.tres", "bus": &"SFX", "pos": true, "pri": 6, "cap": 5, "cooldown_ms": 35, "db": 0.0, "loop": false},
	&"hit_armor": {"path": "res://audio/sfx/hit_armor.tres", "bus": &"SFX", "pos": true, "pri": 5, "cap": 3, "cooldown_ms": 80, "db": 0.0, "loop": false},
	&"ability_purge": {"path": "res://audio/sfx/ability_purge.tres", "bus": &"SFX", "pos": false, "pri": 2, "cap": 1, "cooldown_ms": 500, "db": 0.0, "loop": false},
	&"ability_freeze": {"path": "res://audio/sfx/ability_freeze.tres", "bus": &"SFX", "pos": false, "pri": 2, "cap": 1, "cooldown_ms": 500, "db": 0.0, "loop": false},
	# ---- Viruses ----
	&"death_small": {"path": "res://audio/sfx/death_small.tres", "bus": &"SFX", "pos": true, "pri": 6, "cap": 4, "cooldown_ms": 40, "db": 0.0, "loop": false},
	&"death_large": {"path": "res://audio/sfx/death_large.tres", "bus": &"SFX", "pos": true, "pri": 6, "cap": 3, "cooldown_ms": 80, "db": 0.0, "loop": false},
	&"death_sweep": {"path": "res://audio/sfx/death_sweep.tres", "bus": &"SFX", "pos": true, "pri": 6, "cap": 1, "cooldown_ms": 200, "db": 0.0, "loop": false},
	&"trojan_split_warn": {"path": "res://audio/sfx/trojan_split_warn.tres", "bus": &"SFX", "pos": true, "pri": 4, "cap": 2, "cooldown_ms": 300, "db": 0.0, "loop": false},
	&"trojan_split": {"path": "res://audio/sfx/trojan_split.tres", "bus": &"SFX", "pos": true, "pri": 4, "cap": 2, "cooldown_ms": 300, "db": 0.0, "loop": false},
	&"worm_bite": {"path": "res://audio/sfx/worm_bite.tres", "bus": &"SFX", "pos": true, "pri": 4, "cap": 3, "cooldown_ms": 100, "db": 0.0, "loop": false},
	&"worm_spread": {"path": "res://audio/sfx/worm_spread.tres", "bus": &"SFX", "pos": true, "pri": 4, "cap": 2, "cooldown_ms": 200, "db": 0.0, "loop": false},
	&"ransomware_mark": {"path": "res://audio/sfx/ransomware_mark.tres", "bus": &"SFX", "pos": true, "pri": 4, "cap": 2, "cooldown_ms": 400, "db": 0.0, "loop": false},
	# ---- Core and Overdrive ----
	&"core_hit": {"path": "res://audio/sfx/core_hit.tres", "bus": &"SFX", "pos": false, "pri": 1, "cap": 2, "cooldown_ms": 150, "db": -4.0, "loop": false},
	&"core_crash": {"path": "res://audio/sfx/core_crash.tres", "bus": &"SFX", "pos": false, "pri": 1, "cap": 1, "cooldown_ms": 1000, "db": 0.0, "loop": false},
	&"overclock_activate": {"path": "res://audio/sfx/overclock_activate.tres", "bus": &"SFX", "pos": false, "pri": 2, "cap": 1, "cooldown_ms": 500, "db": 0.0, "loop": false},
	&"overclock_ready": {"path": "res://audio/sfx/overclock_ready.tres", "bus": &"UI", "pos": false, "pri": 3, "cap": 1, "cooldown_ms": 1000, "db": 0.0, "loop": false},
	&"load_warning": {"path": "res://audio/sfx/load_warning.tres", "bus": &"UI", "pos": false, "pri": 3, "cap": 1, "cooldown_ms": 1000, "db": 0.0, "loop": false},
	&"load_critical": {"path": "res://audio/sfx/load_critical.tres", "bus": &"UI", "pos": false, "pri": 2, "cap": 1, "cooldown_ms": 1000, "db": 0.0, "loop": false},
	# ---- Waves and level ----
	&"level_start": {"path": "res://audio/sfx/level_start.tres", "bus": &"SFX", "pos": false, "pri": 2, "cap": 1, "cooldown_ms": 0, "db": 0.0, "loop": false},
	&"wave_start": {"path": "res://audio/sfx/wave_start.tres", "bus": &"SFX", "pos": false, "pri": 2, "cap": 1, "cooldown_ms": 0, "db": 0.0, "loop": false},
	&"wave_clear": {"path": "res://audio/sfx/wave_clear.tres", "bus": &"SFX", "pos": false, "pri": 2, "cap": 1, "cooldown_ms": 0, "db": 0.0, "loop": false},
	&"victory": {"path": "res://audio/sfx/victory.tres", "bus": &"Music", "pos": false, "pri": 2, "cap": 1, "cooldown_ms": 0, "db": 0.0, "loop": false},
	&"defeat": {"path": "res://audio/sfx/defeat.tres", "bus": &"Music", "pos": false, "pri": 2, "cap": 1, "cooldown_ms": 0, "db": 0.0, "loop": false},
	# ---- Not in the §6 table, but §4.1 plays it on every kill (cap 2, cooldown 90 ms) and §2.1 ranks it priority 7 ----
	&"energy_tick": {"path": "res://audio/sfx/energy_tick.tres", "bus": &"UI", "pos": false, "pri": 7, "cap": 2, "cooldown_ms": 90, "db": -4.0, "loop": false},
	# ---- Loops ----
	&"amb_server": {"path": "res://audio/loops/amb_server.ogg", "bus": &"Ambience", "pos": false, "pri": 7, "cap": 1, "cooldown_ms": 0, "db": 0.0, "loop": true},
	&"core_low_hp": {"path": "res://audio/loops/core_low_hp.ogg", "bus": &"SFX", "pos": false, "pri": 1, "cap": 1, "cooldown_ms": 0, "db": 0.0, "loop": true},
	&"swarm_loop": {"path": "res://audio/loops/swarm_loop.ogg", "bus": &"SFX", "pos": false, "pri": 6, "cap": 1, "cooldown_ms": 0, "db": 0.0, "loop": true},
}
