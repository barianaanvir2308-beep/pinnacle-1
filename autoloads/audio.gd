# audio.gd — the sound system, autoloaded as "Audio" (docs/sound_design.md §3)
#
#   Audio.play(id)                   global one-shot (UI, core, waves, overclock)
#   Audio.play_at(id, pos)           one-shot at a place on the map (towers, viruses)
#   Audio.start_loop(id) / stop_loop(id) / set_loop_volume(id, linear)
#   Audio.music_state(state)         &"menu", &"build", &"wave", &"wave_late", &"victory", &"defeat", &"silent"
#   Audio.duck(db, time)             dips Music and SFX for a moment so an important sound cuts through
#   Audio.set_bus_linear(bus, v)     volume slider, 0..1 (0 mutes); saved to user://settings.cfg
#   Audio.set_mono(on)               no left/right panning
#   Audio.ui(button)                 hover and press sounds on any button
#
# Every sound id is listed in audio/sound_bank.gd with its bus, priority, cap and cooldown. A sound whose file doesn't
# exist yet is skipped with one warning, so the game runs silently until the sounds are generated.
#
# Game events reach it two ways: Events signals it listens to (_connect_events, docs §4.1) and one-line calls in the
# game scripts for things no signal covers (shots, hits, worm bites, Ransomware marks, the countdown; docs §4.2).
# Music arrives in Phase E; kill batching, the swarm loop and the pause duck in Phase F.
extends Node

const SoundBank = preload("res://audio/sound_bank.gd")

const POOL_SIZE: int = 24            # players for sounds at a place on the map
const GLOBAL_VOICES: int = 32        # voices for global and UI sounds (one polyphonic player)
# A stopped polyphonic voice only frees its slot after the next audio mix, so a voice that is taken can't be reused
# at once. The player gets a few spare slots; GLOBAL_VOICES is the limit this script enforces.
const GLOBAL_SPARE_SLOTS: int = 8
const MAX_DISTANCE: float = 2400.0   # about the viewport diagonal, so the whole map stays audible
const SETTINGS_PATH: String = "user://settings.cfg"
const SETTINGS_SECTION: String = "audio"
const BUSES: Array[StringName] = [&"Master", &"Music", &"SFX", &"UI", &"Ambience"]
const DUCKED_BUSES: Array[StringName] = [&"Music", &"SFX"]
const PROTECTED_PRIORITY: int = 2    # voices with priority 1-2 are never taken by a less important sound

var bank: Dictionary = SoundBank.SOUNDS   # a check can swap in its own bank
var settings_path: String = SETTINGS_PATH # a check can point this at a scratch file
var mono: bool = false
var missing_warnings: int = 0             # how many "file not found" warnings were given (one per id)
var enabled: bool = true                  # false: requests are still logged, but nothing plays (balance runs)
var log_calls: bool = false               # a check turns this on to see which sounds the game asks for
var calls: Array[Dictionary] = []         # {"kind", "id", "pos"} for every request while log_calls is on

var _pool: Array[AudioStreamPlayer2D] = []
var _pool_node: Node2D
var _global_player: AudioStreamPlayer
var _global_playback: AudioStreamPlaybackPolyphonic
var _global_voices: Array[Dictionary] = []   # {"voice": int, "id": StringName, "pri": int, "started": int}
var _streams: Dictionary = {}                # id -> loaded AudioStream
var _warned: Dictionary = {}                 # id -> true once a warning was given
var _last_played: Dictionary = {}            # id -> Time.get_ticks_msec() of the last play
var _loops: Dictionary = {}                  # id -> AudioStreamPlayer
var _music_state: StringName = &"silent"
var _bus_linear: Dictionary = {}             # bus -> 0..1 slider value
var _bus_base_db: Dictionary = {}            # bus -> mix level from default_bus_layout.tres (the slider scales it)
var _duck_db: float = 0.0                    # extra dip on DUCKED_BUSES while ducking
var _duck_tween: Tween
var _last_load: float = 0.0                  # System Load at the last update (warnings play on the upward crossing)

const DEATH_LARGE: Array = [Globals.EnemyType.TROJAN_HORSE, Globals.EnemyType.RANSOMWARE, Globals.EnemyType.SPYWARE,
	Globals.EnemyType.ROOTKIT]               # every other virus (Basic, Worm, DDoS, Trojan Minis) gets death_small
const ABILITY_SOUNDS: Dictionary = {"purge": &"ability_purge", "system_freeze": &"ability_freeze"}
const LOW_HP_FRACTION: float = 0.3           # the low-HP warning loop runs at or below 30% Arduino HP
const LATE_WAVE: int = 7                     # from this wave the music switches to its "late" state

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # UI sounds and music keep working while paused
	for bus in BUSES:
		var idx := AudioServer.get_bus_index(bus)
		if idx < 0:
			push_warning("Audio: bus '%s' is missing from default_bus_layout.tres" % bus)
			continue
		_bus_base_db[bus] = AudioServer.get_bus_volume_db(idx)
		_bus_linear[bus] = 1.0
	_build_players()
	load_settings()
	_connect_events()

# Let go of the playback and the cached sounds on quit, so nothing is reported as leaked
func _exit_tree() -> void:
	if _duck_tween != null and _duck_tween.is_valid():
		_duck_tween.kill()
	_global_voices.clear()
	_global_playback = null
	if _global_player != null:
		_global_player.stop()
	_streams.clear()

func _build_players() -> void:
	# World sounds freeze with the game when it pauses
	_pool_node = Node2D.new()
	_pool_node.name = "WorldSounds"
	_pool_node.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_pool_node)
	for i in POOL_SIZE:
		var p := AudioStreamPlayer2D.new()
		p.bus = &"SFX"
		p.max_distance = MAX_DISTANCE
		p.set_meta("id", &"")
		p.set_meta("pri", 99)
		p.set_meta("started", 0)
		_pool_node.add_child(p)
		_pool.append(p)
	# Global and UI sounds share one polyphonic player
	_global_player = AudioStreamPlayer.new()
	_global_player.name = "GlobalSounds"
	var poly := AudioStreamPolyphonic.new()
	poly.polyphony = GLOBAL_VOICES + GLOBAL_SPARE_SLOTS
	_global_player.stream = poly
	add_child(_global_player)
	_apply_mono()

# The polyphonic player starts with the first global sound. (Started at load, Godot reports its playback as leaked
# when the game quits, even if no sound ever played.)
func _ensure_global_player() -> bool:
	if _global_playback == null:
		_global_player.play()
		_global_playback = _global_player.get_stream_playback() as AudioStreamPlaybackPolyphonic
	return _global_playback != null

# =============================================================================
# One-shots
# =============================================================================

# A global one-shot. Returns true if a voice started.
func play(id: StringName, pitch_semitones: float = 0.0) -> bool:
	_log(&"play", id)
	if not enabled:
		return false
	var entry := _entry(id)
	if entry.is_empty() or not _allowed(id, entry):
		return false
	var stream := _stream(id, entry)
	if stream == null:
		return false
	return _play_global(id, entry, stream, pitch_semitones)

# A one-shot at a place on the map (falls back to a global sound for ids that aren't positional). Returns true if
# a voice started.
func play_at(id: StringName, pos: Vector2, pitch_semitones: float = 0.0) -> bool:
	_log(&"play_at", id, pos)
	if not enabled:
		return false
	var entry := _entry(id)
	if entry.is_empty() or not _allowed(id, entry):
		return false
	var stream := _stream(id, entry)
	if stream == null:
		return false
	if not entry.get("pos", false):
		return _play_global(id, entry, stream, pitch_semitones)
	var player := _free_world_player(entry.get("pri", 5))
	if player == null:
		return false
	player.stop()
	player.stream = stream
	player.bus = entry.get("bus", &"SFX")
	player.volume_db = entry.get("db", 0.0)
	player.pitch_scale = pow(2.0, pitch_semitones / 12.0)
	player.global_position = pos
	player.set_meta("id", id)
	player.set_meta("pri", entry.get("pri", 5))
	player.set_meta("started", Time.get_ticks_msec())
	player.play()
	_last_played[id] = Time.get_ticks_msec()
	return true

func _play_global(id: StringName, entry: Dictionary, stream: AudioStream, pitch_semitones: float) -> bool:
	if not _ensure_global_player():
		return false
	_forget_finished_global_voices()
	var pri: int = entry.get("pri", 5)
	if _global_voices.size() >= GLOBAL_VOICES:
		var victim := _pick_victim(_global_voices, pri)
		if victim < 0:
			return false
		_global_playback.stop_stream(_global_voices[victim].voice)
		_global_voices.remove_at(victim)
	var voice := _global_playback.play_stream(stream, 0.0, entry.get("db", 0.0), pow(2.0, pitch_semitones / 12.0),
		AudioServer.PLAYBACK_TYPE_DEFAULT, entry.get("bus", &"SFX"))
	if voice == AudioStreamPlaybackPolyphonic.INVALID_ID:
		return false
	_global_voices.append({"voice": voice, "id": id, "pri": pri, "started": Time.get_ticks_msec()})
	_last_played[id] = Time.get_ticks_msec()
	return true

# The cap and the cooldown of this id
func _allowed(id: StringName, entry: Dictionary) -> bool:
	var cooldown: int = entry.get("cooldown_ms", 0)
	if cooldown > 0 and _last_played.has(id) and Time.get_ticks_msec() - int(_last_played[id]) < cooldown:
		return false
	return active_count(id) < int(entry.get("cap", 1))

# How many copies of a sound id are playing right now
func active_count(id: StringName) -> int:
	var n := 0
	for p in _pool:
		if p.playing and p.get_meta("id") == id:
			n += 1
	_forget_finished_global_voices()
	for v in _global_voices:
		if v.id == id:
			n += 1
	return n

# An idle world player, or the one to take from a less important sound (null if every voice is more important)
func _free_world_player(pri: int) -> AudioStreamPlayer2D:
	var busy: Array[Dictionary] = []
	for p in _pool:
		if not p.playing:
			return p
		busy.append({"player": p, "pri": p.get_meta("pri"), "started": p.get_meta("started")})
	var victim := _pick_victim(busy, pri)
	return null if victim < 0 else busy[victim].player

# The voice a sound of priority `pri` may take: the least important one (highest number), the oldest among
# those, and never a voice that is more important than the new sound. Returns its index, or -1.
func _pick_victim(voices: Array, pri: int) -> int:
	var best := -1
	for i in voices.size():
		var v: Dictionary = voices[i]
		if int(v.pri) < pri:
			continue  # more important than the new sound: never taken (so priority 1-2 voices are safe from 3-7)
		if best < 0 or int(v.pri) > int(voices[best].pri) \
				or (int(v.pri) == int(voices[best].pri) and int(v.started) < int(voices[best].started)):
			best = i
	return best

func _forget_finished_global_voices() -> void:
	if _global_playback == null:
		return
	for i in range(_global_voices.size() - 1, -1, -1):
		if not _global_playback.is_stream_playing(_global_voices[i].voice):
			_global_voices.remove_at(i)

# =============================================================================
# Loops and music
# =============================================================================

func start_loop(id: StringName) -> void:
	_log(&"start_loop", id)
	if not enabled or _loops.has(id):
		return
	var entry := _entry(id)
	if entry.is_empty():
		return
	var stream := _stream(id, entry)
	if stream == null:
		return
	var player := AudioStreamPlayer.new()
	player.name = "Loop_%s" % id
	player.stream = stream
	player.bus = entry.get("bus", &"SFX")
	player.volume_db = entry.get("db", 0.0)
	add_child(player)
	player.play()
	_loops[id] = player

func stop_loop(id: StringName) -> void:
	_log(&"stop_loop", id)
	if not _loops.has(id):
		return
	var player: AudioStreamPlayer = _loops[id]
	_loops.erase(id)
	player.stop()
	player.queue_free()

func stop_all_loops() -> void:
	for id in _loops.keys():
		stop_loop(id)
	_log(&"stop_all_loops", &"")

func is_loop_playing(id: StringName) -> bool:
	return _loops.has(id)

# 0..1; 0 is silent
func set_loop_volume(id: StringName, linear: float) -> void:
	if not _loops.has(id):
		return
	var entry := _entry(id)
	_loops[id].volume_db = entry.get("db", 0.0) + _linear_to_db_safe(linear)

# Until there is music (Phase E) this only remembers the state
func music_state(state: StringName) -> void:
	_log(&"music", state)
	_music_state = state

func get_music_state() -> StringName:
	return _music_state

# =============================================================================
# Mix: ducking, volume sliders, mono
# =============================================================================

# Dips Music and SFX by `db` at once, then brings them back over `time` seconds. A volume tween, not a compressor,
# so it also works in a Web build.
func duck(db: float = -5.0, time: float = 0.4) -> void:
	_log(&"duck", StringName(str(db)))
	if _duck_tween != null and _duck_tween.is_valid():
		_duck_tween.kill()
	_set_duck(minf(db, _duck_db))
	_duck_tween = create_tween()
	_duck_tween.tween_method(_set_duck, _duck_db, 0.0, time)

func _set_duck(db: float) -> void:
	_duck_db = db
	for bus in DUCKED_BUSES:
		_apply_bus(bus)

# A volume slider: 0..1 on top of the bus's mix level. 0 mutes the bus (linear_to_db(0) is -inf). Saves the settings.
func set_bus_linear(bus: StringName, v: float) -> void:
	if not _bus_linear.has(bus):
		push_warning("Audio: unknown bus '%s'" % bus)
		return
	_bus_linear[bus] = clampf(v, 0.0, 1.0)
	_apply_bus(bus)
	save_settings()

func get_bus_linear(bus: StringName) -> float:
	return _bus_linear.get(bus, 1.0)

func _apply_bus(bus: StringName) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if idx < 0:
		return
	var v: float = _bus_linear.get(bus, 1.0)
	AudioServer.set_bus_mute(idx, v <= 0.0)
	if v > 0.0:
		var duck_db := _duck_db if DUCKED_BUSES.has(bus) else 0.0
		AudioServer.set_bus_volume_db(idx, _bus_base_db.get(bus, 0.0) + linear_to_db(v) + duck_db)

# Mono: no left/right panning on the world sounds (global sounds are already centred). Saves the settings.
func set_mono(on: bool) -> void:
	mono = on
	_apply_mono()
	save_settings()

func _apply_mono() -> void:
	for p in _pool:
		p.panning_strength = 0.0 if mono else 1.0

func _linear_to_db_safe(v: float) -> float:
	return -80.0 if v <= 0.0 else linear_to_db(v)

# =============================================================================
# Settings (user://settings.cfg)
# =============================================================================

func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(settings_path)  # keep anything else that is saved in the same file
	for bus in _bus_linear:
		cfg.set_value(SETTINGS_SECTION, String(bus).to_lower(), _bus_linear[bus])
	cfg.set_value(SETTINGS_SECTION, "mono", mono)
	var err := cfg.save(settings_path)
	if err != OK:
		push_warning("Audio: could not save %s (error %d)" % [settings_path, err])

# Missing file or missing keys: the defaults (every slider at 100%, stereo) are kept
func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(settings_path) == OK:
		for bus in _bus_linear.keys():
			_bus_linear[bus] = clampf(float(cfg.get_value(SETTINGS_SECTION, String(bus).to_lower(), 1.0)), 0.0, 1.0)
		mono = bool(cfg.get_value(SETTINGS_SECTION, "mono", false))
	for bus in _bus_linear:
		_apply_bus(bus)
	_apply_mono()

# =============================================================================
# Buttons
# =============================================================================

# Hover and press sounds on a button (UI bus). Safe to call twice on the same button.
func ui(button: BaseButton) -> void:
	if button == null:
		return
	var hover := func(): play(&"ui_hover")
	var press := func(): play(&"ui_click")
	if not button.has_meta("audio_ui"):
		button.set_meta("audio_ui", true)
		button.mouse_entered.connect(hover)
		button.pressed.connect(press)

# =============================================================================
# Game events -> sounds (docs/sound_design.md §4.1)
# =============================================================================

func _connect_events() -> void:
	Events.tower_placed.connect(func(_type, grid): play_at(&"tower_place", Globals.grid_to_world(grid)))
	Events.tower_upgraded.connect(_on_tower_upgraded)
	Events.tower_sold.connect(func(_type, grid, _refund): play_at(&"tower_sell", Globals.grid_to_world(grid)))
	Events.tower_repaired.connect(func(tower, _cost): play_at(&"tower_repair", tower.global_position if is_instance_valid(tower) else Vector2.ZERO))
	Events.tower_destroyed.connect(func(_type, grid): play_at(&"tower_destroyed", Globals.grid_to_world(grid)))
	Events.placement_invalid.connect(func(_reason): play(&"ui_error"))
	Events.energy_insufficient.connect(func(_required, _available): play(&"ui_error"))
	Events.tower_selected.connect(func(_tower): play(&"ui_select"))
	Events.ability_used.connect(_on_ability_used)
	Events.overclock_used.connect(func(_energy): _play_and_duck(&"overclock_activate", -5.0))
	Events.overclock_ready.connect(func(): play(&"overclock_ready"))
	Events.system_load_changed.connect(_on_system_load_changed)
	Events.system_crashed.connect(func(): _play_and_duck(&"core_crash", -8.0))
	Events.enemy_defeated.connect(_on_enemy_defeated)
	Events.enemy_split.connect(func(pos, _count, _data): play_at(&"trojan_split", pos))
	Events.worm_spread.connect(func(pos, _hp, _speed, _hit): play_at(&"worm_spread", pos))
	Events.base_damaged.connect(func(_damage, _hp): _play_and_duck(&"core_hit", -5.0))
	Events.base_health_changed.connect(_on_base_health_changed)
	Events.wave_started.connect(_on_wave_started)
	Events.wave_completed.connect(_on_wave_completed)
	Events.game_state_changed.connect(_on_game_state_changed)
	Events.level_selected.connect(_on_level_selected)

# Priority 1-2 sounds dip Music and SFX so they cut through (only when the sound really played)
func _play_and_duck(id: StringName, db: float) -> void:
	if play(id):
		duck(db)

func _on_ability_used(_tower: Node, ability_id: String) -> void:
	if ABILITY_SOUNDS.has(ability_id):
		play(ABILITY_SOUNDS[ability_id])

# Tiers 1-2 share a sound, pitched up 2 semitones per tier above the first; tier 3 has its own
func _on_tower_upgraded(_type: int, grid: Vector2i, _path: String, tier: int) -> void:
	var pos := Globals.grid_to_world(grid)
	if tier >= 3:
		play_at(&"tower_upgrade_t3", pos)
	else:
		play_at(&"tower_upgrade", pos, (tier - 1) * 2.0)

# Warnings play only when the load climbs past 60 or 90, not on the way down
func _on_system_load_changed(load_value: float, _max_load: float) -> void:
	if _last_load < Globals.OVERCLOCK.severe_threshold and load_value >= Globals.OVERCLOCK.severe_threshold:
		play(&"load_critical")
	elif _last_load < Globals.OVERCLOCK.slow_threshold and load_value >= Globals.OVERCLOCK.slow_threshold:
		play(&"load_warning")
	_last_load = load_value

func _on_enemy_defeated(enemy_type: int, _reward: int, pos: Vector2) -> void:
	play_at(&"death_large" if DEATH_LARGE.has(enemy_type) else &"death_small", pos)
	play(&"energy_tick")

func _on_base_health_changed(hp: int, max_hp: int) -> void:
	if hp > 0 and hp <= max_hp * LOW_HP_FRACTION:
		start_loop(&"core_low_hp")
	elif is_loop_playing(&"core_low_hp"):
		stop_loop(&"core_low_hp")

func _on_wave_started(wave: int) -> void:
	play(&"wave_start")
	music_state(&"wave_late" if wave >= LATE_WAVE else &"wave")

func _on_wave_completed(_wave: int, _bonus: int) -> void:
	play(&"wave_clear")
	music_state(&"build")

# Pause and resume, and the end of a level. (Events.victory is never emitted in the code and game_over only in one
# place, so the win/lose stingers follow the game state instead.)
func _on_game_state_changed(old_state: int, new_state: int) -> void:
	if new_state == Globals.GameState.PAUSED:
		play(&"ui_pause")
	elif old_state == Globals.GameState.PAUSED:
		play(&"ui_resume")
	match new_state:
		Globals.GameState.VICTORY:
			stop_all_loops()
			play(&"victory")
			music_state(&"victory")
		Globals.GameState.GAME_OVER:
			stop_all_loops()
			play(&"defeat")
			music_state(&"defeat")
		Globals.GameState.MAIN_MENU, Globals.GameState.LEVEL_SELECT:
			stop_all_loops()
			music_state(&"menu")

func _on_level_selected(_level: int) -> void:
	_last_load = 0.0
	play(&"level_start")
	music_state(&"build")
	start_loop(&"amb_server")

func _log(kind: StringName, id: StringName, pos: Vector2 = Vector2.ZERO) -> void:
	if log_calls:
		calls.append({"kind": kind, "id": id, "pos": pos})

# =============================================================================
# Registry and files
# =============================================================================

func _entry(id: StringName) -> Dictionary:
	if bank.has(id):
		return bank[id]
	_warn_once(id, "Audio: unknown sound id '%s'" % id)
	return {}

# The stream for an id: an entry's own "stream" (used by checks) or its file. Missing file: one warning, then null.
func _stream(id: StringName, entry: Dictionary) -> AudioStream:
	if entry.has("stream"):
		return entry.stream
	if _streams.has(id):
		return _streams[id]
	var path: String = entry.get("path", "")
	if path == "" or not ResourceLoader.exists(path):
		_warn_once(id, "Audio: no file for '%s' (%s); it stays silent until the sound is added" % [id, path])
		return null
	var stream := load(path) as AudioStream
	if stream == null:
		_warn_once(id, "Audio: '%s' is not an audio file" % path)
		return null
	_streams[id] = stream
	return stream

func _warn_once(id: StringName, text: String) -> void:
	if _warned.has(id):
		return
	_warned[id] = true
	missing_warnings += 1
	push_warning(text)

# Stops every one-shot (checks use this between tests)
func stop_all() -> void:
	for p in _pool:
		p.stop()
		p.stream = null
		p.set_meta("id", &"")
	if _global_playback != null:
		for v in _global_voices:
			_global_playback.stop_stream(v.voice)
	_global_voices.clear()
	_last_played.clear()
