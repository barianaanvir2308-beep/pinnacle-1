extends Node
class_name WaveManager

signal spawn_enemy_requested(enemy_type: int, health_mult: float, speed_mult: float)

var current_wave: int = 0
var enemies_remaining: int = 0
var is_spawning: bool = false
var spawn_timer: Timer
var _spawn_queue: Array = []
var _wave_complete_emitted: bool = false
var _level_waves: Array = []  # Wave data for current level

func _ready() -> void:
	spawn_timer = Timer.new()
	spawn_timer.one_shot = true
	spawn_timer.timeout.connect(_on_spawn_timer_timeout)
	add_child(spawn_timer)

func load_level_waves(level_index: int) -> void:
	stop_waves()  # also keeps wave_completed shut until start_wave() opens it
	_level_waves = Globals.get_level_waves(level_index)
	current_wave = 0
	enemies_remaining = 0

# Ends the current wave without completing it (Game Over, leaving to the menu, loading a level):
# drops the viruses still queued and the pending spawn, and stops this wave from ever
# reporting wave_completed. Otherwise the timer keeps spawning onto the hidden board and later
# fires on the next level's empty queue, which emits wave_completed(0, bonus) there.
func stop_waves() -> void:
	spawn_timer.stop()
	_spawn_queue.clear()
	is_spawning = false
	_wave_complete_emitted = true

func start_wave() -> void:
	if current_wave >= _level_waves.size() or is_spawning:
		return
	
	current_wave += 1
	var wave_data = get_current_wave_data()
	if wave_data.is_empty():
		return
	
	_spawn_queue.clear()
	_wave_complete_emitted = false
	
	var health_mult = wave_data.get("health_multiplier", 1.0)
	var speed_mult = wave_data.get("speed_multiplier", 1.0)
	var wave_interval = wave_data.get("spawn_interval", 1.0)
	
	# Groups spawn in the order listed. A group can set its own "interval" (e.g.
	# DDoS swarms at 0.2 s); the gap BEFORE each enemy is its own group's interval.
	for group in wave_data.get("enemies", []):
		for i in range(group.get("count", 0)):
			_spawn_queue.append({
				"type": group.get("type", Globals.EnemyType.BASIC_VIRUS),
				"health_mult": health_mult,
				"speed_mult": speed_mult,
				"interval": group.get("interval", wave_interval)
			})
	
	enemies_remaining = _spawn_queue.size()
	is_spawning = true
	Events.wave_started.emit(current_wave)
	
	_spawn_next()

func _spawn_next() -> void:
	if _spawn_queue.is_empty():
		is_spawning = false
		_check_wave_complete()
		return
	
	var next = _spawn_queue.pop_front()
	spawn_enemy_requested.emit(next.type, next.health_mult, next.speed_mult)
	
	if not _spawn_queue.is_empty():
		spawn_timer.wait_time = max(_spawn_queue[0].interval, 0.01)
		spawn_timer.start()
	else:
		is_spawning = false
		_check_wave_complete()

func _on_spawn_timer_timeout() -> void:
	_spawn_next()

func on_enemy_removed() -> void:
	_check_wave_complete()

func _check_wave_complete() -> void:
	if _wave_complete_emitted:
		return
	if not is_spawning:
		var enemy_mgr = get_node_or_null("../EnemyManager")
		if enemy_mgr and enemy_mgr.get_enemy_count() <= 0:
			_wave_complete_emitted = true
			Events.wave_completed.emit(current_wave, Globals.wave_bonus(current_wave))
			if current_wave >= _level_waves.size():
				Events.all_waves_completed.emit()

func force_check_wave_complete(live_enemy_count: int) -> void:
	if _wave_complete_emitted or is_spawning:
		return
	if live_enemy_count <= 0:
		_check_wave_complete()

func get_total_waves() -> int:
	return _level_waves.size()

func get_current_wave_data() -> Dictionary:
	if current_wave > 0 and current_wave <= _level_waves.size():
		return _level_waves[current_wave - 1]
	return {}
