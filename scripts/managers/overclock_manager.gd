# overclock_manager.gd — Emergency Overclock and System Load (balance_spec 2.3)
# Overclock gives +150 Energy at once and adds System Load. Load slows towers and stops passive income,
# and if it reaches 100 the system crashes. Numbers are in Globals.OVERCLOCK.
class_name OverclockManager
extends Node

var system_load: float = 0.0
var cooldown_left: float = 0.0
var crash_left: float = 0.0          # towers are paused while this runs
var double_damage_left: float = 0.0  # the Arduino takes double damage while this runs

var _state_mgr: Node
var _wave_mgr: Node
var _last_load_event: int = -1

func setup(state_mgr: Node, wave_mgr: Node) -> void:
	_state_mgr = state_mgr
	_wave_mgr = wave_mgr
	add_to_group("overclock_manager")

# Level 1 teaches it: it unlocks at wave 3. Later levels have it from the start.
func is_unlocked() -> bool:
	if Globals.current_level > 0:
		return true
	return _wave_mgr != null and _wave_mgr.current_wave >= Globals.OVERCLOCK.unlock_wave_level_1

func in_play() -> bool:
	if _state_mgr == null:
		return false
	var state: int = _state_mgr.current_state
	return state == Globals.GameState.BUILD_PHASE or state == Globals.GameState.WAVE_ACTIVE

func can_use() -> bool:
	return is_unlocked() and in_play() and cooldown_left <= 0.0 and not get_tree().paused

func use() -> bool:
	if not can_use():
		return false
	ResourceManager.add_energy(Globals.OVERCLOCK.energy)
	cooldown_left = Globals.OVERCLOCK.cooldown
	system_load += Globals.OVERCLOCK.load
	Events.overclock_used.emit(Globals.OVERCLOCK.energy)
	if system_load >= 100.0:
		_crash()
	_announce_load()
	return true

# Load hit 100: towers go offline, the Arduino is exposed, and load drops back to 60
func _crash() -> void:
	crash_left = Globals.OVERCLOCK.crash_pause
	double_damage_left = Globals.OVERCLOCK.crash_duration
	system_load = Globals.OVERCLOCK.crash_reset_load
	Events.system_crashed.emit()
	Events.show_message.emit("SYSTEM CRASH!  TOWERS OFFLINE  -  ARDUINO EXPOSED", 3.0)

func _process(delta: float) -> void:
	var was_cooling := cooldown_left > 0.0
	cooldown_left = maxf(cooldown_left - delta, 0.0)
	if was_cooling and cooldown_left <= 0.0 and is_unlocked():
		Events.overclock_ready.emit()
	crash_left = maxf(crash_left - delta, 0.0)
	double_damage_left = maxf(double_damage_left - delta, 0.0)
	if system_load > 0.0 and _state_mgr != null:
		var rate := 0.0
		if _state_mgr.current_state == Globals.GameState.WAVE_ACTIVE:
			rate = Globals.OVERCLOCK.decay_wave
		elif _state_mgr.current_state == Globals.GameState.BUILD_PHASE:
			rate = Globals.OVERCLOCK.decay_build
		if rate > 0.0:
			system_load = maxf(system_load - rate * delta, 0.0)
			_announce_load()

func _announce_load() -> void:
	if int(system_load) != _last_load_event:
		_last_load_event = int(system_load)
		Events.system_load_changed.emit(system_load, 100.0)

# ---- what System Load does to the rest of the game ----
func attack_interval_mult() -> float:
	if system_load >= Globals.OVERCLOCK.severe_threshold:
		return Globals.OVERCLOCK.severe_mult
	if system_load >= Globals.OVERCLOCK.slow_threshold:
		return Globals.OVERCLOCK.slow_mult
	return 1.0

func passive_allowed() -> bool:
	return system_load < Globals.OVERCLOCK.severe_threshold

func towers_paused() -> bool:
	return crash_left > 0.0

func arduino_damage_mult() -> float:
	return Globals.OVERCLOCK.crash_arduino_dmg_mult if double_damage_left > 0.0 else 1.0

func reset() -> void:
	system_load = 0.0
	cooldown_left = 0.0
	crash_left = 0.0
	double_damage_left = 0.0
	_last_load_event = -1
	_announce_load()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("overclock"):
		use()
		get_viewport().set_input_as_handled()
