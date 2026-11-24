# check_audio.gd — Headless checks for the sound system (docs/sound_design.md §3-§5, §10)
# Run: godot --headless --path . res://tools/checks/check_audio.tscn
# Phase A: buses, the Audio autoload, the sound registry, missing files, caps, cooldowns, priority stealing, bus
# volume and mute, and saving/loading settings.
# Phase B: every §4.1 signal asks for the right sound, the §4.2 calls fire in a real game, and every button has
# hover/press sounds. Audio.log_calls records each request; a test bank with a silent sound stands in for the
# missing files. (Death batching is Phase F and is checked then.)
# Phase C: tools/sfx/sfx_list.csv lists every registry id with valid numbers, and Audio loads and plays a real
# AudioStreamRandomizer file (what build_randomizers.gd makes).
# Phase D: every registry id resolves to its real file (one-shots: a randomizer holding every kept take; loops: a
# looping OGG), every sound plays with no warning, and the hand-set level trims are kept.
extends Node

const SoundBank = preload("res://audio/sound_bank.gd")
const SCRATCH_SETTINGS := "user://check_audio_settings.cfg"
const REQUIRED_FIELDS := ["path", "bus", "pos", "pri", "cap", "cooldown_ms", "db", "loop"]
# Ids the registry has that the §6 table doesn't: energy_tick is played on every kill by §4.1
const EXTRA_IDS := [&"energy_tick"]
const T = Globals.EnemyType
const S = Globals.GameState

var _fails: int = 0

func _check(cond: bool, msg: String) -> void:
	if not cond:
		_fails += 1
	print(("  ok    " if cond else "  FAIL  ") + msg)

func _ready() -> void:
	await get_tree().process_frame
	print("== buses and autoload")
	_check_buses()
	_check_autoload()
	print("== sound registry")
	_check_registry()
	print("== missing files")
	_check_missing_files()
	print("== caps, cooldowns and priority")
	await _check_voices()
	print("== volume, mute and settings")
	_check_settings()
	print("== event hooks (§4.1)")
	await _check_event_hooks()
	print("== calls inside the game (§4.2) and buttons")
	await _check_game_calls()
	print("== generation list and randomizer files (Phase C)")
	await _check_generation_list()
	print("== the real sounds (Phase D)")
	await _check_assets()

	# stop the test sounds and let the audio thread release them before quitting
	Audio.bank = SoundBank.SOUNDS
	Audio.stop_all()
	Audio._global_player.stop()
	Audio._global_playback = null
	await _let_audio_mix()
	print("check_audio: %d failure(s)" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)

# ---- buses ----
func _check_buses() -> void:
	var want := {&"Master": 0.0, &"Music": -10.0, &"SFX": -4.0, &"UI": -6.0, &"Ambience": -14.0}
	for bus in want:
		var idx := AudioServer.get_bus_index(bus)
		_check(idx >= 0, "bus %s exists" % bus)
		if idx < 0:
			continue
		if bus != &"Master":
			_check(AudioServer.get_bus_send(idx) == &"Master", "%s sends to Master" % bus)
	# the start levels are read before the saved sliders are applied, so read them from the layout file itself
	var layout := load("res://default_bus_layout.tres") as AudioBusLayout
	_check(layout != null, "default_bus_layout.tres loads")
	var master := AudioServer.get_bus_index(&"Master")
	var limiter := AudioServer.get_bus_effect(master, 0) if AudioServer.get_bus_effect_count(master) > 0 else null
	_check(limiter is AudioEffectHardLimiter and is_equal_approx(limiter.ceiling_db, -1.0) and AudioServer.is_bus_effect_enabled(master, 0),
		"Master has a hard limiter at -1 dB")
	var sfx := AudioServer.get_bus_index(&"SFX")
	_check(AudioServer.get_bus_effect_count(sfx) == 1 and AudioServer.get_bus_effect(sfx, 0) is AudioEffectLowPassFilter \
		and not AudioServer.is_bus_effect_enabled(sfx, 0), "SFX has the pause low-pass, switched off")
	for bus in want:
		_check(is_equal_approx(Audio._bus_base_db.get(bus, 99.0), want[bus]), "%s starts at %.0f dB" % [bus, want[bus]])
	_check(is_equal_approx(float(ProjectSettings.get_setting("audio/general/2d_panning_strength")), 0.3), "2D panning strength is 0.3")

# ---- autoload ----
func _check_autoload() -> void:
	var root := get_tree().root
	var audio := root.get_node_or_null("Audio")
	_check(audio != null, "the Audio autoload exists")
	if audio == null:
		return
	_check(audio.get_index() > root.get_node("Events").get_index(), "it is loaded after Events")
	_check(audio.process_mode == Node.PROCESS_MODE_ALWAYS, "it keeps running while the game is paused")
	_check(Audio._pool.size() == 24 and Audio._pool.all(func(p): return p is AudioStreamPlayer2D and is_equal_approx(p.max_distance, 2400.0)),
		"24 world players, max distance 2400")
	_check(Audio._pool_node.process_mode == Node.PROCESS_MODE_PAUSABLE, "world sounds pause with the game")
	_check(Audio._global_player.stream is AudioStreamPolyphonic and Audio.GLOBAL_VOICES == 32 \
		and Audio._global_player.stream.polyphony == Audio.GLOBAL_VOICES + Audio.GLOBAL_SPARE_SLOTS,
		"one polyphonic player for global sounds: 32 voices (+8 spare slots for voices being stopped)")
	_check(not FileAccess.file_exists("res://scripts/managers/audio_manager.gd") and FileAccess.file_exists("res://_to_delete/scripts/managers/audio_manager.gd"),
		"the old audio_manager.gd was moved to _to_delete/")

# ---- registry ----
func _check_registry() -> void:
	var sounds: Dictionary = SoundBank.SOUNDS
	var bad: Array[String] = []
	for id in sounds:
		var e: Dictionary = sounds[id]
		for field in REQUIRED_FIELDS:
			if not e.has(field):
				bad.append("%s is missing '%s'" % [id, field])
		if not Audio.BUSES.has(e.get("bus")):
			bad.append("%s uses unknown bus %s" % [id, e.get("bus")])
		if int(e.get("pri", 0)) < 1 or int(e.get("pri", 0)) > 7:
			bad.append("%s priority %s is not 1-7" % [id, e.get("pri")])
		if int(e.get("cap", 0)) < 1 or int(e.get("cooldown_ms", -1)) < 0:
			bad.append("%s has a bad cap or cooldown" % id)
	_check(bad.is_empty(), "every id has path, bus, pos, pri, cap, cooldown_ms, db and loop%s" % ("" if bad.is_empty() else ": " + ", ".join(bad)))
	# every id in the spec's sound table (§6), with its priority, cap, cooldown and bus
	var table := _spec_table()
	if table.is_empty():
		_check(false, "could not read the sound table from docs/sound_design.md")
		return
	var missing := table.keys().filter(func(id): return not sounds.has(id))
	var extra := sounds.keys().filter(func(id): return not table.has(id) and not EXTRA_IDS.has(id))
	_check(missing.is_empty() and extra.is_empty(), "the registry has the %d ids of the §6 table (+ %s)%s" % [table.size(), EXTRA_IDS,
		"" if missing.is_empty() and extra.is_empty() else " (missing %s, extra %s)" % [missing, extra]])
	var wrong: Array[String] = []
	for id in table:
		if sounds.has(id):
			var t: Dictionary = table[id]
			var e: Dictionary = sounds[id]
			if int(e.pri) != t.pri or int(e.cap) != t.cap or int(e.cooldown_ms) != t.cd or e.bus != t.bus or bool(e.loop) != t.loop:
				wrong.append(String(id))
	_check(wrong.is_empty(), "priority, cap, cooldown, bus and loop match the table%s" % ("" if wrong.is_empty() else " except " + ", ".join(wrong)))

# Reads the §6 table: id -> {pri, cap, cd, bus, loop}. "–" for cap/cooldown means 1 / 0.
func _spec_table() -> Dictionary:
	var f := FileAccess.open("res://docs/sound_design.md", FileAccess.READ)
	if f == null:
		return {}
	var text := f.get_as_text()
	var start := text.find("## 6. Sound list")
	var end := text.find("## 7.")
	if start < 0 or end < 0:
		return {}
	var out := {}
	for line in text.substr(start, end - start).split("\n"):
		if not line.begins_with("|") or line.begins_with("|---") or line.begins_with("| id"):
			continue
		var cells := Array(line.strip_edges().trim_prefix("|").trim_suffix("|").split("|")).map(func(c): return c.strip_edges())
		if cells.size() < 8 or cells[0].begins_with("**"):
			continue
		var cap := 1
		var cd := 0
		if cells[6] != "–":
			var parts: PackedStringArray = cells[6].split("/")
			cap = int(parts[0].strip_edges())
			cd = 0 if parts[1].strip_edges() == "–" else int(parts[1].strip_edges())
		out[StringName(cells[0])] = {"pri": int(cells[5]), "cap": cap, "cd": cd, "bus": StringName(cells[7]), "loop": cells[3] == "✔"}
	return out

# ---- missing files ----
func _check_missing_files() -> void:
	# made-up ids whose files don't exist (every real id has its sound since Phase D)
	Audio.bank = {
		&"gone_global": {"path": "res://audio/sfx/no_such_file.tres", "bus": &"SFX", "pos": false, "pri": 1, "cap": 2, "cooldown_ms": 0, "db": 0.0, "loop": false},
		&"gone_world": {"path": "res://audio/sfx/no_such_file_2.tres", "bus": &"SFX", "pos": true, "pri": 5, "cap": 2, "cooldown_ms": 0, "db": 0.0, "loop": false},
		&"gone_loop": {"path": "res://audio/loops/no_such_loop.ogg", "bus": &"Ambience", "pos": false, "pri": 7, "cap": 1, "cooldown_ms": 0, "db": 0.0, "loop": true},
	}
	var before: int = Audio.missing_warnings
	var a := Audio.play(&"gone_global")
	var b := Audio.play(&"gone_global")
	var c := Audio.play_at(&"gone_world", Vector2(500, 500))
	Audio.start_loop(&"gone_loop")
	_check(not a and not b and not c and not Audio.is_loop_playing(&"gone_loop"), "sounds with no file play nothing and don't crash")
	_check(Audio.missing_warnings - before == 3, "one warning per missing id, not per play (%d)" % (Audio.missing_warnings - before))
	_check(not Audio.play(&"no_such_sound"), "an unknown id plays nothing")
	Audio.bank = SoundBank.SOUNDS

# ---- voices ----
func _silent(seconds: float) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = 22050
	wav.stereo = false
	var data := PackedByteArray()
	data.resize(int(22050 * seconds) * 2)
	wav.data = data
	return wav

func _test_bank() -> Dictionary:
	var s := _silent(10.0)
	return {
		&"capped": {"bus": &"SFX", "pos": false, "pri": 5, "cap": 3, "cooldown_ms": 0, "db": 0.0, "loop": false, "stream": s},
		&"capped_pos": {"bus": &"SFX", "pos": true, "pri": 5, "cap": 2, "cooldown_ms": 0, "db": 0.0, "loop": false, "stream": s},
		&"slow": {"bus": &"UI", "pos": false, "pri": 3, "cap": 10, "cooldown_ms": 400, "db": 0.0, "loop": false, "stream": s},
		&"low": {"bus": &"SFX", "pos": true, "pri": 6, "cap": 100, "cooldown_ms": 0, "db": 0.0, "loop": false, "stream": s},
		&"high": {"bus": &"SFX", "pos": true, "pri": 1, "cap": 100, "cooldown_ms": 0, "db": 0.0, "loop": false, "stream": s},
		&"low_g": {"bus": &"SFX", "pos": false, "pri": 6, "cap": 100, "cooldown_ms": 0, "db": 0.0, "loop": false, "stream": s},
		&"high_g": {"bus": &"SFX", "pos": false, "pri": 1, "cap": 100, "cooldown_ms": 0, "db": 0.0, "loop": false, "stream": s},
		&"looping": {"bus": &"Ambience", "pos": false, "pri": 7, "cap": 1, "cooldown_ms": 0, "db": 0.0, "loop": true, "stream": s},
	}

# A stopped global voice frees its slot only after the next audio mix
func _let_audio_mix() -> void:
	var until := Time.get_ticks_msec() + 150
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame

func _check_voices() -> void:
	Audio.bank = _test_bank()
	Audio.stop_all()

	# cap
	var started := 0
	for i in 4:
		if Audio.play(&"capped"):
			started += 1
	_check(started == 3 and Audio.active_count(&"capped") == 3, "a cap of 3 blocks the 4th copy (global sound)")
	var started_pos := 0
	for i in 3:
		if Audio.play_at(&"capped_pos", Vector2(300, 300)):
			started_pos += 1
	_check(started_pos == 2 and Audio.active_count(&"capped_pos") == 2, "a cap of 2 blocks the 3rd copy (sound on the map)")

	# cooldown
	_check(Audio.play(&"slow"), "a sound with a 400 ms cooldown plays")
	_check(not Audio.play(&"slow"), "and is blocked when played again at once")
	# cooldowns use the real clock (Time.get_ticks_msec), so wait on that, not on a game-time timer
	var until := Time.get_ticks_msec() + 450
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame
	_check(Audio.play(&"slow"), "and plays again after the cooldown")

	# priority stealing on the map players
	Audio.stop_all()
	for i in Audio.POOL_SIZE:
		Audio.play_at(&"low", Vector2(i * 10, 0))
	_check(Audio.active_count(&"low") == Audio.POOL_SIZE, "all 24 map players busy with a priority 6 sound")
	_check(Audio.play_at(&"high", Vector2(0, 0)), "a priority 1 sound takes a voice from priority 6")
	_check(Audio.active_count(&"high") == 1 and Audio.active_count(&"low") == Audio.POOL_SIZE - 1, "the priority 6 sound lost exactly one voice")
	Audio.stop_all()
	for i in Audio.POOL_SIZE:
		Audio.play_at(&"high", Vector2(i * 10, 0))
	_check(not Audio.play_at(&"low", Vector2(0, 0)), "a priority 6 sound can't take a voice from priority 1")
	_check(Audio.active_count(&"high") == Audio.POOL_SIZE and Audio.active_count(&"low") == 0, "the priority 1 sounds keep all their voices")

	# the oldest of the least important voices is the one taken
	Audio.stop_all()
	for i in Audio.POOL_SIZE:
		Audio.play_at(&"low", Vector2(i * 10, 0))
	var oldest: AudioStreamPlayer2D = Audio._pool[0]
	oldest.set_meta("started", 0)
	Audio.play_at(&"high", Vector2(0, 0))
	_check(oldest.get_meta("id") == &"high", "the oldest voice of the lowest priority is the one taken")

	# priority stealing on the global voices (after stop_all, let the audio thread free the stopped voices' slots)
	Audio.stop_all()
	await _let_audio_mix()
	for i in Audio.GLOBAL_VOICES:
		Audio.play(&"low_g")
	_check(Audio._global_playback != null and Audio.active_count(&"low_g") == Audio.GLOBAL_VOICES, "all 32 global voices busy with a priority 6 sound")
	_check(Audio.play(&"high_g") and Audio.active_count(&"low_g") == Audio.GLOBAL_VOICES - 1, "a global priority 1 sound takes one of them")
	Audio.stop_all()
	await _let_audio_mix()
	for i in Audio.GLOBAL_VOICES:
		Audio.play(&"high_g")
	_check(not Audio.play(&"low_g") and Audio.active_count(&"high_g") == Audio.GLOBAL_VOICES, "a global priority 6 sound can't take a priority 1 voice")

	# loops
	Audio.stop_all()
	Audio.start_loop(&"looping")
	_check(Audio.is_loop_playing(&"looping"), "a loop starts")
	Audio.set_loop_volume(&"looping", 0.0)
	_check(Audio._loops[&"looping"].volume_db <= -79.0, "a loop at volume 0 is silent")
	Audio.stop_loop(&"looping")
	_check(not Audio.is_loop_playing(&"looping"), "and stops")

	# music state is only remembered until music exists (Phase E)
	Audio.music_state(&"wave")
	_check(Audio.get_music_state() == &"wave", "music_state() remembers the state")
	Audio.music_state(&"silent")
	Audio.stop_all()

# ---- settings ----
func _check_settings() -> void:
	var real_path: String = Audio.settings_path
	var saved := {}
	for bus in Audio.BUSES:
		saved[bus] = Audio.get_bus_linear(bus)
	var saved_mono: bool = Audio.mono
	Audio.settings_path = SCRATCH_SETTINGS
	if FileAccess.file_exists(SCRATCH_SETTINGS):
		DirAccess.remove_absolute(SCRATCH_SETTINGS)

	var sfx := AudioServer.get_bus_index(&"SFX")
	Audio.set_bus_linear(&"SFX", 0.0)
	_check(AudioServer.is_bus_mute(sfx), "set_bus_linear(SFX, 0) mutes the SFX bus")
	Audio.set_bus_linear(&"SFX", 0.5)
	_check(not AudioServer.is_bus_mute(sfx) and is_equal_approx(AudioServer.get_bus_volume_db(sfx), -4.0 + linear_to_db(0.5)),
		"at 0.5 it is unmuted and 6 dB under its -4 dB mix level")
	Audio.set_bus_linear(&"Music", 1.5)
	_check(is_equal_approx(Audio.get_bus_linear(&"Music"), 1.0), "values above 1 are clamped")

	# ducking dips Music and SFX, then comes back
	Audio.set_bus_linear(&"SFX", 1.0)
	Audio.duck(-5.0, 0.4)
	_check(is_equal_approx(AudioServer.get_bus_volume_db(sfx), -4.0 - 5.0), "duck() dips SFX by 5 dB")
	_check(is_equal_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"UI")), -6.0), "and leaves UI alone")
	Audio._duck_tween.custom_step(1.0)
	_check(is_equal_approx(AudioServer.get_bus_volume_db(sfx), -4.0), "and SFX is back at its level afterwards")

	# round trip
	Audio.set_bus_linear(&"Master", 0.8)
	Audio.set_bus_linear(&"Music", 0.3)
	Audio.set_bus_linear(&"SFX", 0.0)
	Audio.set_bus_linear(&"UI", 0.6)
	Audio.set_bus_linear(&"Ambience", 0.25)
	Audio.set_mono(true)
	_check(FileAccess.file_exists(SCRATCH_SETTINGS), "changing a slider saves the settings file")
	_check(Audio._pool.all(func(p): return p.panning_strength == 0.0), "mono turns off panning on the map sounds")
	for bus in Audio.BUSES:
		Audio._bus_linear[bus] = 1.0
	Audio.mono = false
	Audio.load_settings()
	_check(is_equal_approx(Audio.get_bus_linear(&"Master"), 0.8) and is_equal_approx(Audio.get_bus_linear(&"Music"), 0.3)
		and Audio.get_bus_linear(&"SFX") == 0.0 and is_equal_approx(Audio.get_bus_linear(&"UI"), 0.6)
		and is_equal_approx(Audio.get_bus_linear(&"Ambience"), 0.25) and Audio.mono, "settings survive a save/load round trip")
	_check(AudioServer.is_bus_mute(sfx), "and a bus saved at 0 comes back muted")
	var cfg := ConfigFile.new()
	_check(cfg.load(SCRATCH_SETTINGS) == OK and cfg.has_section_key("audio", "ambience") and cfg.has_section_key("audio", "mono"),
		"the file has an [audio] section with every bus and mono")

	# put the player's real settings back
	DirAccess.remove_absolute(SCRATCH_SETTINGS)
	for bus in Audio.BUSES:
		Audio._bus_linear[bus] = saved[bus]
		Audio._apply_bus(bus)
	Audio.mono = saved_mono
	Audio._apply_mono()
	Audio.settings_path = real_path

# =============================================================================
# Phase B
# =============================================================================

# Every registry id with a silent sound and no cap or cooldown, so each request really plays
func _recording_bank() -> Dictionary:
	var s := _silent(0.2)
	var out := {}
	for id in SoundBank.SOUNDS:
		var e: Dictionary = SoundBank.SOUNDS[id].duplicate()
		e["stream"] = s
		e["cap"] = 99
		e["cooldown_ms"] = 0
		out[id] = e
	return out

func _start_log() -> void:
	Audio.calls.clear()
	Audio.log_calls = true

# The ids requested since _start_log, optionally only one kind (&"play", &"play_at", &"start_loop", ...)
func _ids(kind: StringName = &"") -> Array:
	return Audio.calls.filter(func(c): return kind == &"" or c.kind == kind).map(func(c): return c.id)

func _hook(what: String, emit: Callable, want: Array) -> void:
	_start_log()
	emit.call()
	var got := _ids()
	var ok := want.all(func(id): return got.has(id))
	_check(ok, "%s -> %s%s" % [what, ", ".join(want.map(func(x): return String(x))), "" if ok else "  (got %s)" % [got]])

func _check_event_hooks() -> void:
	Audio.bank = _recording_bank()
	Audio.stop_all()
	await _let_audio_mix()  # free the voices the earlier tests stopped, so every hook gets a voice
	var grid := Vector2i(3, 2)
	_hook("tower_placed", func(): Events.tower_placed.emit(0, grid), [&"tower_place"])
	_check(Audio.calls[0].kind == &"play_at" and Audio.calls[0].pos == Globals.grid_to_world(grid), "  and it plays on the tower's tile")
	_hook("tower_upgraded tier 1", func(): Events.tower_upgraded.emit(0, grid, "A", 1), [&"tower_upgrade"])
	_hook("tower_upgraded tier 3", func(): Events.tower_upgraded.emit(0, grid, "A", 3), [&"tower_upgrade_t3"])
	_hook("tower_sold", func(): Events.tower_sold.emit(0, grid, 60), [&"tower_sell"])
	var fake_tower := Node2D.new()
	add_child(fake_tower)
	_hook("tower_repaired", func(): Events.tower_repaired.emit(fake_tower, 20), [&"tower_repair"])
	_hook("tower_destroyed", func(): Events.tower_destroyed.emit(0, grid), [&"tower_destroyed"])
	_hook("placement_invalid", func(): Events.placement_invalid.emit("no"), [&"ui_error"])
	_hook("energy_insufficient", func(): Events.energy_insufficient.emit(100, 5), [&"ui_error"])
	_hook("tower_selected", func(): Events.tower_selected.emit(fake_tower), [&"ui_select"])
	_hook("ability_used purge", func(): Events.ability_used.emit(fake_tower, "purge"), [&"ability_purge"])
	_hook("ability_used system_freeze", func(): Events.ability_used.emit(fake_tower, "system_freeze"), [&"ability_freeze"])
	fake_tower.queue_free()
	_hook("overclock_used", func(): Events.overclock_used.emit(150), [&"overclock_activate"])
	_check(_ids(&"duck").size() == 1, "  and it ducks the mix")
	_hook("overclock_ready", func(): Events.overclock_ready.emit(), [&"overclock_ready"])
	_hook("system_crashed", func(): Events.system_crashed.emit(), [&"core_crash"])
	_check(_ids(&"duck") == [&"-8.0"], "  and it ducks by 8 dB")
	_hook("enemy_defeated (Basic)", func(): Events.enemy_defeated.emit(T.BASIC_VIRUS, 4, Vector2(10, 10)), [&"death_small", &"energy_tick"])
	_hook("enemy_defeated (DDoS)", func(): Events.enemy_defeated.emit(T.DDOS_BOT, 1, Vector2(10, 10)), [&"death_small"])
	_hook("enemy_defeated (Rootkit)", func(): Events.enemy_defeated.emit(T.ROOTKIT, 20, Vector2(10, 10)), [&"death_large", &"energy_tick"])
	_check(not _ids().has(&"death_small"), "  a Rootkit doesn't get the small death sound")
	_hook("enemy_split", func(): Events.enemy_split.emit(Vector2(5, 5), 3, {}), [&"trojan_split"])
	_hook("worm_spread", func(): Events.worm_spread.emit(Vector2(5, 5), 1.0, 1.0, []), [&"worm_spread"])
	_hook("base_damaged", func(): Events.base_damaged.emit(5, 95), [&"core_hit"])
	_check(_ids(&"duck").size() == 1, "  and it ducks the mix")

	# System Load: warnings only on the way up past 60 and 90
	Events.level_selected.emit(0)  # resets the remembered load
	_start_log()
	for load_value in [30.0, 65.0, 70.0, 95.0, 50.0, 61.0]:
		Events.system_load_changed.emit(load_value, 100.0)
	_check(_ids(&"play") == [&"load_warning", &"load_critical", &"load_warning"], "system_load_changed 30-65-70-95-50-61 -> warning, critical, warning (got %s)" % [_ids(&"play")])

	# low-HP loop
	Audio.stop_all_loops()
	_hook("base_health_changed 25/100", func(): Events.base_health_changed.emit(25, 100), [&"core_low_hp"])
	_check(Audio.is_loop_playing(&"core_low_hp"), "  the low-HP loop runs at 30% or less")
	_hook("base_health_changed 80/100", func(): Events.base_health_changed.emit(80, 100), [&"core_low_hp"])
	_check(not Audio.is_loop_playing(&"core_low_hp") and _ids(&"stop_loop").has(&"core_low_hp"), "  and stops above 30%")

	# waves and music
	_hook("wave_started 3", func(): Events.wave_started.emit(3), [&"wave_start", &"wave"])
	_hook("wave_started 7", func(): Events.wave_started.emit(7), [&"wave_start", &"wave_late"])
	_hook("wave_completed", func(): Events.wave_completed.emit(3, 45), [&"wave_clear", &"build"])
	_check(Audio.get_music_state() == &"build", "  music back to the build state")

	# pause and the end of a level
	_hook("game_state_changed -> PAUSED", func(): Events.game_state_changed.emit(S.WAVE_ACTIVE, S.PAUSED), [&"ui_pause"])
	_hook("game_state_changed PAUSED -> WAVE_ACTIVE", func(): Events.game_state_changed.emit(S.PAUSED, S.WAVE_ACTIVE), [&"ui_resume"])
	Audio.start_loop(&"amb_server")
	_hook("game_state_changed -> VICTORY", func(): Events.game_state_changed.emit(S.WAVE_ACTIVE, S.VICTORY), [&"victory", &"victory"])
	_check(_ids(&"stop_all_loops").size() == 1 and not Audio.is_loop_playing(&"amb_server"), "  and all loops stop")
	Audio.start_loop(&"amb_server")
	_hook("game_state_changed -> GAME_OVER", func(): Events.game_state_changed.emit(S.WAVE_ACTIVE, S.GAME_OVER), [&"defeat", &"defeat"])
	_check(not Audio.is_loop_playing(&"amb_server"), "  and all loops stop")
	_hook("game_state_changed -> MAIN_MENU", func(): Events.game_state_changed.emit(S.GAME_OVER, S.MAIN_MENU), [&"menu"])
	_hook("level_selected", func(): Events.level_selected.emit(1), [&"level_start", &"build", &"amb_server"])
	_check(Audio.is_loop_playing(&"amb_server"), "  the server-room ambience loop runs")
	Audio.stop_all_loops()
	Audio.log_calls = false

func _check_game_calls() -> void:
	Audio.bank = _recording_bank()
	Audio.stop_all()
	var main = load("res://scenes/main/Main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	Events.level_selected.emit(0)
	await get_tree().process_frame
	ResourceManager.max_energy = 1000000
	ResourceManager.current_energy = 100000
	main.get_node("Managers/CombatManager").set_physics_process(false)
	var tm = main.get_node("Managers/TowerManager")
	var enemies: Node = main.get_node("EnemyContainer")
	var cell := Vector2i(5, 4)

	var spawn := func(type: int, pos: Vector2) -> Node:
		main._on_spawn_enemy_requested(type, 1.0, 1.0)
		var e = enemies.get_child(enemies.get_child_count() - 1)
		e.set_process(false)
		e.global_position = pos
		if "base_offset" in e:
			e.base_offset = pos
		return e
	var clear := func() -> void:
		for c in tm.placed_towers.keys():
			tm.sell_tower(tm.placed_towers[c])
		for e in enemies.get_children():
			e.free()
		main.get_node("Managers/EnemyManager").active_enemies.clear()

	# towers firing, and a shot landing
	tm.place_tower(cell, Globals.TowerType.ANTIVIRUS_CANNON)
	var cannon = tm.placed_towers[cell]
	var target = spawn.call(T.BASIC_VIRUS, cannon.global_position + Vector2(120, 0))
	_start_log()
	cannon.try_attack([target])
	_check(_ids(&"play_at").has(&"fire_cannon"), "a Cannon shot -> fire_cannon")
	for i in 30:
		await get_tree().process_frame
	_check(_ids(&"play_at").has(&"hit_generic"), "its projectile landing -> hit_generic")
	clear.call()
	await get_tree().process_frame

	tm.place_tower(cell, Globals.TowerType.DATA_SPIKE)
	var spike = tm.placed_towers[cell]
	target = spawn.call(T.BASIC_VIRUS, spike.global_position + Vector2(120, 0))
	_start_log()
	spike.try_attack([target])
	_check(_ids(&"play_at") == [&"fire_spike"], "a Data Spike shot -> fire_spike (got %s)" % [_ids(&"play_at")])
	clear.call()
	await get_tree().process_frame

	tm.place_tower(cell, Globals.TowerType.EMP_TOWER)
	var emp = tm.placed_towers[cell]
	target = spawn.call(T.BASIC_VIRUS, emp.global_position + Vector2(120, 0))
	_start_log()
	emp.try_attack([target])
	_check(_ids(&"play_at").has(&"emp_pulse"), "an EMP pulse -> emp_pulse")
	clear.call()
	await get_tree().process_frame

	tm.place_tower(cell, Globals.TowerType.FIREWALL_BEAM)
	var beam = tm.placed_towers[cell]
	target = spawn.call(T.BASIC_VIRUS, beam.global_position + Vector2(120, 0))
	_start_log()
	beam.try_attack([target])
	beam.try_attack([target])
	_check(_ids(&"play_at") == [&"fire_beam"], "a Firewall Beam locking on -> fire_beam, once per new target (got %s)" % [_ids(&"play_at")])
	clear.call()
	await get_tree().process_frame

	# Rootkit armour
	var rk = spawn.call(T.ROOTKIT, Vector2(600, 600))
	_start_log()
	rk.take_damage(20.0)
	_check(_ids(&"play_at") == [&"hit_armor"], "a hit the Rootkit's armour reduces -> hit_armor")
	_start_log()
	rk.take_damage(20.0, true)
	_check(not _ids().has(&"hit_armor"), "an armour-piercing hit doesn't clank")
	clear.call()

	# Trojan split warning: once, when the ring is 75% full
	var trojan = spawn.call(T.TROJAN_HORSE, Vector2(600, 600))
	_start_log()
	trojan._process(5.9)
	_check(not _ids().has(&"trojan_split_warn"), "no Trojan warning before 75%")
	trojan._process(0.2)
	trojan._process(0.5)
	_check(_ids(&"play_at").count(&"trojan_split_warn") == 1, "the Trojan warning plays once when the ring passes 75%")
	clear.call()
	await get_tree().process_frame

	# Worm bite, Ransomware mark and lock
	tm.place_tower(cell, Globals.TowerType.ANTIVIRUS_CANNON)
	var module = tm.placed_towers[cell]
	var worm = spawn.call(T.WORM, module.global_position + Vector2(100, 0))
	_start_log()
	worm._process(0.016)
	_check(_ids(&"play_at").has(&"worm_bite"), "a Worm biting a module -> worm_bite")
	_check(Audio.calls.filter(func(c): return c.id == &"worm_bite")[0].pos == module.global_position, "  played at the module")
	clear.call()
	await get_tree().process_frame
	tm.place_tower(cell, Globals.TowerType.ANTIVIRUS_CANNON)
	module = tm.placed_towers[cell]
	var ransom = spawn.call(T.RANSOMWARE, module.global_position + Vector2(100, 0))
	_start_log()
	ransom._process(0.0)
	_check(_ids(&"play_at").has(&"ransomware_mark") and _ids(&"play_at").has(&"tower_locked"), "a Ransomware marking and locking a module -> ransomware_mark, tower_locked (got %s)" % [_ids(&"play_at")])
	clear.call()
	await get_tree().process_frame

	# the 3-2-1 countdown before a wave
	main.countdown_label.text = ""
	main.wave_start_countdown = 3.0
	_start_log()
	for step in [0.1, 0.1, 1.0, 0.1, 1.0, 1.0]:
		main._process(step)
	_check(_ids(&"play").count(&"countdown_tick") == 3, "the countdown ticks 3 times: 3, 2, 1 (got %d)" % _ids(&"play").count(&"countdown_tick"))
	await get_tree().process_frame

	# Overclock ready: only when the cooldown ends while it is unlocked
	var oc = main.overclock_mgr
	var wm = main.get_node("Managers/WaveManager")
	wm.current_wave = 0
	oc.cooldown_left = 0.05
	_start_log()
	oc._process(0.1)
	_check(not _ids().has(&"overclock_ready"), "no ready sound while Overclock is still locked (Level 1 before wave 3)")
	wm.current_wave = 3
	oc.cooldown_left = 0.05
	_start_log()
	oc._process(0.1)
	oc._process(0.1)
	_check(_ids(&"play").count(&"overclock_ready") == 1, "Events.overclock_ready fires once when the cooldown ends -> overclock_ready")
	wm.current_wave = 0

	# buttons: every button in every screen has the hover and press sounds
	ResourceManager.current_energy = 100000
	tm.place_tower(cell, Globals.TowerType.DATA_SPIKE)
	var t3 = tm.placed_towers[cell]
	for i in 3:
		tm.upgrade_tower(t3, "A")
	tm.select_tower(t3)
	for i in 5:
		await get_tree().process_frame
	_check_buttons(main, "in play (build bar, tower panel, ability and Overclock buttons)")
	# then every screen, in an order the game allows (the countdown test above started a wave)
	var gsm = main.get_node("Managers/GameStateManager")
	gsm.change_state(S.GAME_OVER)
	await get_tree().process_frame
	_check_buttons(main, "game over screen")
	gsm.change_state(S.MAIN_MENU)
	await get_tree().process_frame
	_check_buttons(main, "main menu")
	gsm.change_state(S.LEVEL_SELECT)
	await get_tree().process_frame
	_check_buttons(main, "level select")
	Globals.levels_unlocked = 5
	Events.level_selected.emit(4)  # only the last level's victory screen has a button
	await get_tree().process_frame
	gsm.change_state(S.VICTORY)
	await get_tree().process_frame
	_check_buttons(main, "victory screen (campaign complete)")
	Globals.levels_unlocked = 1
	Globals.current_level = 0
	var any_button: BaseButton = _buttons(main)[0] if not _buttons(main).is_empty() else null
	if any_button != null:
		_start_log()
		any_button.mouse_entered.emit()
		_check(_ids(&"play") == [&"ui_hover"], "hovering a button -> ui_hover")
		_start_log()
		any_button.pressed.emit()
		_check(_ids(&"play").has(&"ui_click"), "pressing a button -> ui_click")

	Audio.log_calls = false
	main.queue_free()
	await get_tree().process_frame

func _buttons(root: Node) -> Array:
	var out: Array = []
	for n in root.find_children("*", "BaseButton", true, false):
		if not n.is_queued_for_deletion():
			out.append(n)  # hidden ones too (the tower info panel's Sell, Repair and upgrade buttons)
	return out

func _check_buttons(root: Node, where: String) -> void:
	var buttons := _buttons(root)
	var silent := buttons.filter(func(b): return not b.has_meta("audio_ui"))
	_check(not buttons.is_empty() and silent.is_empty(), "%s: all %d buttons have sounds%s" % [where, buttons.size(),
		"" if silent.is_empty() else " except " + ", ".join(silent.map(func(b): return "%s '%s'" % [b.get_class(), b.text]))])

# =============================================================================
# Phase C
# =============================================================================

func _read_csv(path: String) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return rows
	var header := f.get_csv_line()
	while not f.eof_reached():
		var line := f.get_csv_line()
		if line.size() == header.size():
			var row := {}
			for i in header.size():
				row[header[i]] = line[i]
			rows.append(row)
	return rows

func _check_generation_list() -> void:
	var rows := _read_csv("res://tools/sfx/sfx_list.csv")
	_check(not rows.is_empty() and rows[0].keys() == ["id", "prompt", "duration", "loop", "takes", "prompt_influence"],
		"sfx_list.csv has the columns id, prompt, duration, loop, takes, prompt_influence")
	var ids := rows.map(func(r): return StringName(r.id))
	var bank_ids: Array = SoundBank.SOUNDS.keys()
	var missing := bank_ids.filter(func(id): return not ids.has(id))
	var extra := ids.filter(func(id): return not bank_ids.has(id))
	_check(missing.is_empty() and extra.is_empty() and ids.size() == bank_ids.size(), "it lists every registry id once%s" % (
		"" if missing.is_empty() and extra.is_empty() else " (missing %s, extra %s)" % [missing, extra]))
	var bad: Array[String] = []
	var seconds := 0.0
	for r in rows:
		var dur := float(r.duration)
		var loop: bool = r.loop == "true"
		if r.prompt.strip_edges() == "" or dur < 0.5 or dur > 30.0 or int(r.takes) < 1 or float(r.prompt_influence) <= 0.0 \
				or (SoundBank.SOUNDS.has(StringName(r.id)) and loop != bool(SoundBank.SOUNDS[StringName(r.id)].loop)):
			bad.append(String(r.id))
		seconds += dur * int(r.takes)
	_check(bad.is_empty(), "every row has a prompt, 0.5-30 s, 1+ takes and the registry's loop flag%s" % ("" if bad.is_empty() else ": " + ", ".join(bad)))
	_check(seconds * 40 <= 9000, "the full set fits the Free plan's 9,000-credit stop (%d credits)" % int(seconds * 40))
	var music := _read_csv("res://tools/sfx/music_list.csv")
	_check(music.size() == 4 and music.all(func(r): return r.id.begins_with("music_") and r.loop == "true"), "music_list.csv has the 4 music loops (generated separately)")
	for path in ["res://tools/sfx/generate_sfx.py", "res://tools/sfx/process_sfx.sh", "res://tools/sfx/build_randomizers.gd", "res://tools/sfx/README.md"]:
		_check(FileAccess.file_exists(path), "%s exists" % path.get_file())
	_check(FileAccess.file_exists("res://tools/sfx/raw/.gdignore") and FileAccess.file_exists("res://tools/sfx/rejected/.gdignore"),
		"Godot ignores tools/sfx/raw/ and tools/sfx/rejected/")

	# a randomizer file like build_randomizers.gd makes, loaded from its path and played
	var r := AudioStreamRandomizer.new()
	r.add_stream(-1, _silent(0.3), 1.0)
	r.add_stream(-1, _silent(0.3), 1.0)
	r.playback_mode = AudioStreamRandomizer.PLAYBACK_RANDOM_NO_REPEATS
	var path := "user://check_audio_randomizer.tres"
	_check(ResourceSaver.save(r, path) == OK, "a test randomizer saves")
	await _let_audio_mix()
	Audio.stop_all()
	Audio._streams.clear()
	Audio.bank = {&"from_file": {"path": path, "bus": &"SFX", "pos": true, "pri": 5, "cap": 2, "cooldown_ms": 0, "db": 0.0, "loop": false}}
	_check(Audio.play_at(&"from_file", Vector2(200, 200)) and Audio._streams.get(&"from_file") is AudioStreamRandomizer,
		"Audio loads a randomizer .tres from its registry path and plays it")
	Audio.stop_all()
	Audio._streams.clear()
	DirAccess.remove_absolute(path)

# =============================================================================
# Phase D
# =============================================================================

# The WAV takes kept for a one-shot (audio/sfx/<id>/*.wav)
func _take_files(id: StringName) -> Array:
	var out: Array = []
	var dir := DirAccess.open("res://audio/sfx/%s" % id)
	if dir != null:
		for f in dir.get_files():
			if f.get_extension().to_lower() == "wav":
				out.append(f)
	return out

func _check_assets() -> void:
	var sounds: Dictionary = SoundBank.SOUNDS
	var unresolved: Array[String] = []
	var wrong_takes: Array[String] = []
	var not_mono: Array[String] = []
	var no_variation: Array[String] = []
	var not_looping: Array[String] = []
	var loop_rates: Array[String] = []
	for id in sounds:
		var e: Dictionary = sounds[id]
		if not ResourceLoader.exists(e.path):
			unresolved.append(String(id))
			continue
		var stream: Resource = load(e.path)
		if e.loop:
			if not (stream is AudioStreamOggVorbis):
				unresolved.append("%s (not an OGG)" % id)
			elif not stream.loop:
				not_looping.append(String(id))
			elif stream.packet_sequence != null and int(stream.packet_sequence.sampling_rate) != 44100:
				loop_rates.append("%s %d Hz" % [id, int(stream.packet_sequence.sampling_rate)])
			continue
		if not (stream is AudioStreamRandomizer):
			unresolved.append("%s (not a randomizer)" % id)
			continue
		var takes := _take_files(id)
		if stream.streams_count != takes.size() or takes.is_empty():
			wrong_takes.append("%s (%d in the .tres, %d WAVs)" % [id, stream.streams_count, takes.size()])
		for i in stream.streams_count:
			var take: AudioStream = stream.get_stream(i)
			if not (take is AudioStreamWAV) or take.stereo:
				not_mono.append(String(id))
				break
		if e.bus == &"SFX" and stream.streams_count >= 2 and (stream.playback_mode != AudioStreamRandomizer.PLAYBACK_RANDOM_NO_REPEATS
				or is_zero_approx(float(stream.get("random_pitch_semitones")))):
			no_variation.append(String(id))
	_check(unresolved.is_empty(), "all %d registry ids resolve to their files%s" % [sounds.size(), "" if unresolved.is_empty() else ": missing " + ", ".join(unresolved)])
	_check(wrong_takes.is_empty(), "every one-shot's randomizer holds all of its kept takes%s" % ("" if wrong_takes.is_empty() else ": " + ", ".join(wrong_takes)))
	_check(not_mono.is_empty(), "every take is a mono WAV%s" % ("" if not_mono.is_empty() else ": " + ", ".join(not_mono)))
	_check(no_variation.is_empty(), "frequent SFX sounds never repeat a take and vary in pitch%s" % ("" if no_variation.is_empty() else ": " + ", ".join(no_variation)))
	_check(not_looping.is_empty(), "every .ogg in audio/loops/ has Loop on%s" % ("" if not_looping.is_empty() else ": " + ", ".join(not_looping)))
	_check(loop_rates.is_empty(), "every loop is 44.1 kHz%s" % ("" if loop_rates.is_empty() else ": " + ", ".join(loop_rates)))
	var takes_total := 0
	for id in sounds:
		takes_total += _take_files(id).size()
	print("        (%d one-shots with %d takes, %d loops)" % [sounds.values().filter(func(x): return not x.loop).size(), takes_total,
		sounds.values().filter(func(x): return x.loop).size()])

	# the level trims set by hand stay
	_check(is_equal_approx(sounds[&"core_hit"].db, -4.0) and is_equal_approx(sounds[&"countdown_tick"].db, -8.0) and is_equal_approx(sounds[&"energy_tick"].db, -4.0),
		"hand-set trims kept: core_hit -4 dB, countdown_tick -8 dB, energy_tick -4 dB")

	# every real sound plays, with no "missing file" warning
	await _let_audio_mix()
	Audio.bank = sounds
	Audio.stop_all()
	Audio.stop_all_loops()
	Audio._streams.clear()
	var before: int = Audio.missing_warnings
	var silent: Array[String] = []
	for id in sounds:
		var e: Dictionary = sounds[id]
		if e.loop:
			Audio.start_loop(id)
			if not Audio.is_loop_playing(id):
				silent.append(String(id))
		elif not (Audio.play_at(id, Vector2(400, 400)) if e.pos else Audio.play(id)):
			silent.append(String(id))
	_check(silent.is_empty(), "every one of the %d sounds plays%s" % [sounds.size(), "" if silent.is_empty() else ", except " + ", ".join(silent)])
	_check(Audio.missing_warnings == before, "and no sound is reported missing")
	var loop_player: AudioStreamPlayer = Audio._loops.get(&"amb_server")
	_check(loop_player != null and loop_player.bus == &"Ambience", "the server-room loop plays on the Ambience bus")
	Audio.stop_all_loops()
	Audio.stop_all()
	Audio._streams.clear()
