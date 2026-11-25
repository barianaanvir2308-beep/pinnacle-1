# check_gameplay.gd — Headless behaviour checks
# Run: godot --headless --path . res://tools/checks/check_gameplay.tscn
# Starts the real game scene and checks behaviour (maps, tower timing, enemy damage,
# spawn order, projectile pausing, per-group wave intervals). Exit code 1 on any failure.
extends Node

# Shortest route lengths (tiles) from balance_spec / td_research §7 per map
const ROUTE_RANGES: Array = [[10, 19], [11, 12], [21, 45], [6, 11], [4, 9]]

var _fails: int = 0

func _check(cond: bool, msg: String) -> void:
	if not cond:
		_fails += 1
	print(("  ok    " if cond else "  FAIL  ") + msg)

func _ready() -> void:
	print("== maps")
	_check_maps()
	print("== combat, enemies, spawns")
	await _check_game()
	print("== wave spawn intervals")
	await _check_wave_intervals()
	print("== a wave cut short does not leak into the next level")
	await _check_wave_cut_short()
	print("check_gameplay: %d failure(s)" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)

func _check_maps() -> void:
	for i in Globals.LEVEL_DATA.size():
		Globals.load_level(i)
		var board := GameBoard.new()
		add_child(board)
		var name: String = Globals.LEVEL_DATA[i].name
		_check(board.unreachable_spawns().is_empty(), "%s: every spawn reaches the Arduino" % name)
		var lengths: Array[int] = []
		for spawn in board.get_spawn_points():
			lengths.append(board.find_path(spawn, board.get_arduino_position()).size() - 1)
		var lo: int = lengths.min()
		var hi: int = lengths.max()
		_check(lo >= ROUTE_RANGES[i][0] and hi <= ROUTE_RANGES[i][1],
			"%s: shortest routes %d–%d tiles (spec %d–%d)" % [name, lo, hi, ROUTE_RANGES[i][0], ROUTE_RANGES[i][1]])
		# only the spawn tiles a level really uses are drawn as spawners (Level 1: 2 of its 6 SPAWN cells)
		var drawn := 0
		for tile in board._tiles.get_children():
			if tile is AnimatedSprite2D and tile.animation == "spawn":
				drawn += 1
		_check(drawn == board.get_spawn_points().size(), "%s: %d spawner tiles drawn, %d in use" % [name, drawn, board.get_spawn_points().size()])
		board.free()
	# The check must be able to fail: cut the only link out of spawn (3,0) on Bootloader
	Globals.load_level(0)
	var cut := GameBoard.new()
	add_child(cut)
	cut.astar.remove_point(cut._cell_id(Vector2i(3, 1)))
	_check(cut.unreachable_spawns() == [Vector2i(3, 0)], "check detects a spawn that is cut off")
	cut.free()

func _check_game() -> void:
	var main = load("res://scenes/main/Main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	Events.level_selected.emit(0)
	await get_tree().process_frame
	ResourceManager.current_energy = 5000
	ResourceManager.max_energy = 1000000  # these checks hand themselves lots of Energy; the real cap is 1000
	main.get_node("Managers/CombatManager").set_physics_process(false)  # we drive attacks by hand

	# --- spawn order: round-robin over the spawn tiles, restarting each level
	_check(main._spawn_cycle == 0, "spawn cycle restarts when a level loads")
	var spawns: Array[Vector2i] = main.game_board.get_spawn_points()
	var enemy_container = main.get_node("EnemyContainer")
	var in_order := true
	for k in spawns.size() + 2:
		main._on_spawn_enemy_requested(Globals.EnemyType.BASIC_VIRUS, 1.0, 1.0)
		var e = enemy_container.get_child(enemy_container.get_child_count() - 1)
		if not e.position.is_equal_approx(Globals.grid_to_world(spawns[k % spawns.size()])):
			in_order = false
	_check(in_order, "enemies spawn at the %d spawn tiles in a fixed rotation" % spawns.size())

	# --- enemy damage comes from base_damage
	var basic = enemy_container.get_child(0)
	_check(basic.base_damage == Globals.ENEMY_DATA[Globals.EnemyType.BASIC_VIRUS].base_damage,
		"Basic Virus Arduino damage = %d (data value)" % basic.base_damage)
	main._on_spawn_enemy_requested(Globals.EnemyType.TROJAN_HORSE, 1.0, 1.0)
	var trojan = enemy_container.get_child(enemy_container.get_child_count() - 1)
	_check(trojan.base_damage == 7, "Trojan Horse Arduino damage = %d" % trojan.base_damage)

	# --- tower cooldown = attack_interval (seconds between shots)
	var tm = main.get_node("Managers/TowerManager")
	var expected := {
		Vector2i(5, 4): [Globals.TowerType.DATA_SPIKE, 225, 2.5],
		Vector2i(10, 4): [Globals.TowerType.ANTIVIRUS_CANNON, 100, 1.0],
		Vector2i(1, 1): [Globals.TowerType.EMP_TOWER, 175, 4.0],
	}
	var towers := {}
	for cell in expected:
		var before: int = ResourceManager.current_energy
		_check(tm.place_tower(cell, expected[cell][0]), "placed %s" % Globals.TOWER_DATA[expected[cell][0]].name)
		_check(before - ResourceManager.current_energy == expected[cell][1],
			"  costs %d Energy" % expected[cell][1])
		towers[cell] = tm.placed_towers[cell]
	for cell in towers:
		var t = towers[cell]
		var target = enemy_container.get_child(0)
		target.global_position = t.global_position + Vector2(100, 0)
		t.try_attack([target])
		_check(is_equal_approx(t.cooldown_timer, expected[cell][2]),
			"  %s waits %.1f s between shots" % [Globals.TOWER_DATA[expected[cell][0]].name, t.cooldown_timer])

	# --- projectiles live in ProjectileContainer and stop while paused
	var shots = main.get_node("ProjectileContainer").get_children()
	_check(shots.size() >= 2, "shots are created inside ProjectileContainer (%d)" % shots.size())
	get_tree().paused = true
	var any_running := false
	for s in shots:
		if s.can_process():
			any_running = true
	_check(not any_running, "shots do not move while the game is paused")
	get_tree().paused = false

	main.queue_free()
	await get_tree().process_frame

func _check_wave_intervals() -> void:
	await get_tree().create_timer(0.3).timeout  # let the frame time settle after freeing Main
	var wm := WaveManager.new()
	add_child(wm)
	var stamps: Array[float] = []
	wm.spawn_enemy_requested.connect(func(_t, _h, _s): stamps.append(Time.get_ticks_msec() / 1000.0))
	# Group A sets its own interval (0.06 s). Group B has none, so uses the wave's (0.25 s).
	wm._level_waves = [{
		"wave_id": 1, "spawn_interval": 0.25, "health_multiplier": 1.0, "speed_multiplier": 1.0, "wave_bonus": 0,
		"enemies": [
			{"type": Globals.EnemyType.DDOS_BOT, "count": 3, "interval": 0.06},
			{"type": Globals.EnemyType.BASIC_VIRUS, "count": 2},
		],
	}]
	wm.start_wave()
	await get_tree().create_timer(1.0).timeout
	_check(stamps.size() == 5, "wave spawns all 5 enemies (%d)" % stamps.size())
	if stamps.size() == 5:
		var gaps: Array[float] = []
		for i in range(1, stamps.size()):
			gaps.append(stamps[i] - stamps[i - 1])
		var want: Array[float] = [0.06, 0.06, 0.25, 0.25]  # gap BEFORE each enemy = its own group's interval
		var ok := true
		for i in gaps.size():
			if absf(gaps[i] - want[i]) > 0.03:
				ok = false
		_check(ok, "gaps between spawns follow each group's interval (got %s)" % [gaps.map(func(g): return snappedf(g, 0.01))])
	wm.free()

# Regression: a level that ends mid-wave (Game Over, or leaving to the menu) used to leave the
# WaveManager's spawn timer running. It kept spawning onto the hidden board during GAME_OVER and,
# once a new level had loaded, fired on the empty queue and emitted wave_completed(0, bonus):
# +15 Energy, "WAVE 0 CLEARED" and a 15 s build countdown on a fresh level.
func _check_wave_cut_short() -> void:
	# load_level_waves on its own must stop a pending spawn
	var wm := WaveManager.new()
	add_child(wm)
	wm.load_level_waves(0)
	wm.start_wave()
	_check(not wm.spawn_timer.is_stopped(), "a running wave has a spawn pending")
	wm.load_level_waves(1)
	_check(wm.spawn_timer.is_stopped() and wm._spawn_queue.is_empty() and not wm.is_spawning,
		"load_level_waves stops the spawn timer and clears the queue")
	wm.free()

	# The real flow: wave running -> GAME_OVER -> LEVEL_SELECT -> another level
	var main = load("res://scenes/main/Main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	Events.level_selected.emit(0)
	await get_tree().process_frame
	var gsm = main.game_state_mgr
	var spawned := [0]
	main.wave_mgr.spawn_enemy_requested.connect(func(_t, _h, _s): spawned[0] += 1)
	var completed: Array = []
	var on_completed := func(w, b): completed.append([w, b])
	Events.wave_completed.connect(on_completed)
	main._start_next_wave()  # Level 1 wave 1: 5 Basic Viruses, 2.0 s apart
	await get_tree().process_frame
	_check(spawned[0] == 1 and main.wave_mgr._spawn_queue.size() == 4, "wave 1 started with 4 viruses still queued")

	gsm.change_state(Globals.GameState.GAME_OVER)
	await get_tree().create_timer(2.3).timeout  # longer than the 2.0 s spawn interval
	_check(spawned[0] == 1, "no viruses spawn after GAME_OVER (spawned %d)" % spawned[0])
	# a virus left on the board dying during GAME_OVER must not clear the wave either
	main.enemy_mgr.clear_all_enemies()
	main.wave_mgr.on_enemy_removed()
	await get_tree().process_frame

	gsm.change_state(Globals.GameState.LEVEL_SELECT)
	Events.level_selected.emit(1)
	await get_tree().process_frame
	var start_energy: int = Globals.get_level_config(1).get("starting_energy", 300)
	await get_tree().create_timer(2.3).timeout
	_check(completed.is_empty(), "no wave_completed after the level ended mid-wave (got %s)" % [completed])
	_check(ResourceManager.current_energy == start_energy,
		"Energy on the new level = its starting_energy %d (got %d)" % [start_energy, ResourceManager.current_energy])
	_check(main.build_countdown <= 0.0, "no build countdown running on the new level (%.1f)" % main.build_countdown)
	_check(gsm.current_state == Globals.GameState.BUILD_PHASE and main.wave_mgr.current_wave == 0,
		"the new level waits in BUILD_PHASE at wave 0")
	_check(spawned[0] == 1, "no viruses spawned on the new level (spawned %d)" % spawned[0])

	Events.wave_completed.disconnect(on_completed)
	main.queue_free()
	await get_tree().process_frame
