# check_abilities.gd — Headless checks for tower abilities and the ability bar
# Run: godot --headless --path . res://tools/checks/check_abilities.tscn
extends Node

const CANNON = Globals.TowerType.ANTIVIRUS_CANNON
const SPIKE = Globals.TowerType.DATA_SPIKE
const EMP = Globals.TowerType.EMP_TOWER

var _fails: int = 0
var _main: Node
var _tm: Node
var _mgr: AbilityManager
var _enemies: Node
var _messages: Array = []
var _used: Array = []

func _check(cond: bool, msg: String) -> void:
	if not cond:
		_fails += 1
	print(("  ok    " if cond else "  FAIL  ") + msg)

func _ready() -> void:
	_main = load("res://scenes/main/Main.tscn").instantiate()
	add_child(_main)
	await get_tree().process_frame
	Events.level_selected.emit(0)
	await get_tree().process_frame
	ResourceManager.current_energy = 50000
	ResourceManager.max_energy = 1000000  # these checks hand themselves lots of Energy; the real cap is 1000
	_main.get_node("Managers/CombatManager").set_physics_process(false)
	_tm = _main.get_node("Managers/TowerManager")
	_mgr = _main.ability_mgr
	_enemies = _main.get_node("EnemyContainer")
	Events.show_message.connect(func(text, _d): _messages.append(text))
	Events.ability_used.connect(func(t, id): _used.append([t, id]))

	await _check_unlocking()
	await _check_bar()
	await _check_purge()
	await _check_freeze()
	await _check_blocked()
	await _check_removal()
	await _check_many()

	print("check_abilities: %d failure(s)" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)

func _place(cell: Vector2i, type: int) -> Node:
	_tm.place_tower(cell, type)
	return _tm.placed_towers[cell]

func _buy(tower: Node, sequence: String) -> void:
	for path in sequence:
		_tm.upgrade_tower(tower, path)

func _spawn(offset_from: Node, dx: float, health_mult: float = 5.0) -> Node:
	_main._on_spawn_enemy_requested(Globals.EnemyType.BASIC_VIRUS, health_mult, 1.0)
	var enemy = _enemies.get_child(_enemies.get_child_count() - 1)
	enemy.global_position = offset_from.global_position + Vector2(dx, 0)
	return enemy

func _clear_enemies() -> void:
	for e in _enemies.get_children():
		e.free()
	_main.get_node("Managers/EnemyManager").active_enemies.clear()

func _press(action: StringName) -> void:
	for pressed in [true, false]:
		var ev := InputEventAction.new()
		ev.action = action
		ev.pressed = pressed
		Input.parse_input_event(ev)
	await get_tree().process_frame

func _check_unlocking() -> void:
	print("== which tiers give an ability")
	for i in range(1, 6):
		_check(InputMap.has_action("ability_%d" % i), "input action ability_%d exists" % i)
	var cannon = _place(Vector2i(1, 1), CANNON)
	_buy(cannon, "AAA")
	_check(cannon.path_tiers["A"] == 3 and not cannon.has_ability(), "Cannon A3 has no ability")
	_tm.sell_tower(cannon)
	var spike = _place(Vector2i(1, 1), SPIKE)
	_buy(spike, "BB")
	_check(not spike.has_ability(), "Data Spike B2 has no ability yet")
	_buy(spike, "B")
	_check(spike.has_ability() and spike.get_ability().id == "purge", "Data Spike B3 unlocks Purge")
	_check(spike.can_use_ability() and spike.get_ability_progress() == 1.0, "a new ability starts ready")
	_tm.sell_tower(spike)
	var spike_a = _place(Vector2i(1, 1), SPIKE)
	_buy(spike_a, "AAA")
	_check(not spike_a.has_ability(), "Data Spike A3 (Zero-Day) has no ability")
	_tm.sell_tower(spike_a)
	var emp = _place(Vector2i(1, 1), EMP)
	_buy(emp, "AAA")
	_check(emp.has_ability() and emp.get_ability().id == "system_freeze", "EMP A3 unlocks System Freeze")
	_tm.sell_tower(emp)
	var emp_b = _place(Vector2i(1, 1), EMP)
	_buy(emp_b, "BBB")
	_check(not emp_b.has_ability(), "EMP B3 (Ion Storm) has no ability")
	_tm.sell_tower(emp_b)

func _check_bar() -> void:
	print("== the ability bar")
	await get_tree().process_frame
	_check(_mgr.buttons.is_empty() and not _mgr.bar.visible, "no buttons while no tower owns an ability")
	var s1 = _place(Vector2i(1, 1), SPIKE)
	var e1 = _place(Vector2i(2, 1), EMP)
	var s2 = _place(Vector2i(6, 1), SPIKE)
	_buy(s1, "BBB")
	_buy(e1, "AAA")
	_buy(s2, "BBB")
	_check(_mgr.buttons.is_empty(), "the bar waits for its next sync")
	await get_tree().process_frame
	await get_tree().process_frame
	_check(_mgr.buttons.size() == 3, "three towers with abilities give three buttons (%d)" % _mgr.buttons.size())
	_check(_mgr.buttons[0].tower == s1 and _mgr.buttons[1].tower == e1 and _mgr.buttons[2].tower == s2,
		"buttons are in tower placement order")
	_check(_mgr.buttons[0].subtitle == "Data Spike #1" and _mgr.buttons[1].subtitle == "EMP Tower #1" and _mgr.buttons[2].subtitle == "Data Spike #2",
		"labels: %s, %s, %s" % [_mgr.buttons[0].subtitle, _mgr.buttons[1].subtitle, _mgr.buttons[2].subtitle])
	_check(_mgr.buttons[0].title == "PURGE" and _mgr.buttons[1].title == "SYSTEM FREEZE", "titles: %s, %s" % [_mgr.buttons[0].title, _mgr.buttons[1].title])
	_check([_mgr.buttons[0].slot, _mgr.buttons[1].slot, _mgr.buttons[2].slot] == [0, 1, 2], "hotkey slots F1, F2, F3")
	_check(_mgr.bar.visible, "the bar is shown during a level")
	var screen := _mgr.bar.get_viewport_rect().size
	var rect := Rect2(_mgr.bar.position, _mgr.bar.size)
	var bar_zone := Rect2(0, 0, screen.x, Globals.GRID_OFFSET.y + Globals.GRID_HEIGHT * Globals.TILE_SIZE)
	_check(bar_zone.encloses(rect) and absf(rect.end.x - (screen.x - 12.0)) < 1.0,
		"bar sits bottom-right above the build bar: %s" % [rect])

func _check_purge() -> void:
	print("== Purge")
	_clear_enemies()
	var spike: Node = _mgr.buttons[0].tower
	var near_a = _spawn(spike, 100.0)
	var near_b = _spawn(spike, 450.0)
	var far = _spawn(spike, 900.0)  # range is 5 tiles = 600 px
	var hp_far: float = far.health
	var hp_near: float = near_a.health
	_used.clear()
	_check(_mgr.activate(spike), "Purge goes off")
	_check(near_a.health == hp_near - 150.0 and near_b.health == hp_near - 150.0, "150 damage to each virus in range (%.0f left)" % near_a.health)
	_check(far.health == hp_far, "a virus out of range is untouched")
	_check(is_equal_approx(spike.ability_cooldown_left, 45.0) and not spike.can_use_ability(), "cooldown 45 s starts")
	_check(not _mgr.activate(spike) and near_a.health == hp_near - 150.0, "a second press during cooldown does nothing")
	await get_tree().process_frame
	_check(_mgr.buttons[0].disabled, "the button is greyed out while cooling down")
	_check(_used.size() == 1 and _used[0][0] == spike and _used[0][1] == "purge", "ability_used fired once with (tower, id)")
	_check(spike.get_ability_progress() < 0.01, "ring starts empty")
	spike.ability_cooldown_left = 22.5
	_check(is_equal_approx(spike.get_ability_progress(), 0.5), "ring is half full at half the cooldown")
	spike.ability_cooldown_left = 0.0
	_check(spike.can_use_ability(), "ready again when the cooldown ends")

	_clear_enemies()
	var cd_before: float = spike.ability_cooldown_left
	_messages.clear()
	_check(not _mgr.activate(spike) and spike.ability_cooldown_left == cd_before, "with no virus in range it is refused and the cooldown is not used")
	_check(_messages.size() == 1 and "NO VIRUSES IN RANGE" in _messages[0], "player is told why: %s" % [_messages])

	var killable = _spawn(spike, 100.0, 1.0)  # a Basic Virus has 60 HP
	var dead_before := is_instance_valid(killable)
	spike.ability_cooldown_left = 0.0
	_mgr.activate(spike)
	await get_tree().process_frame
	_check(dead_before and (not is_instance_valid(killable) or killable.is_queued_for_deletion()), "Purge kills a weak virus")
	_clear_enemies()

func _check_freeze() -> void:
	print("== System Freeze")
	_clear_enemies()
	var emp: Node = _mgr.buttons[1].tower
	var a = _spawn(emp, 100.0)
	var b = _spawn(emp, 1400.0)   # far outside any tower range: it is map-wide
	var boss = _spawn(emp, 300.0)
	boss.stun_immune = true
	_check(_mgr.activate(emp), "System Freeze goes off")
	_check(a.stun_timer == 3.0 and b.stun_timer == 3.0, "every virus on the map is frozen for 3 s")
	_check(a.slow_factor == 0.5 and a.slow_timer == 9.0, "and slowed 50%% for 6 s after (slow timer %.0f)" % a.slow_timer)
	_check(boss.stun_timer == 0.0 and boss.slow_factor == 0.5 and boss.slow_timer == 6.0, "a boss is only slowed 50% for 6 s")
	_check(is_equal_approx(emp.ability_cooldown_left, 50.0), "cooldown 50 s starts")
	var pos_a: Vector2 = a.position
	var pos_free = null
	var free_enemy = _spawn(emp, -100.0)
	pos_free = free_enemy.position
	await get_tree().create_timer(0.4).timeout
	_check(a.position == pos_a, "a frozen virus does not move")
	_check(free_enemy.position != pos_free, "an unfrozen virus does move")
	a.stun_timer = 0.05
	await get_tree().create_timer(0.3).timeout
	_check(a.stun_timer <= 0.0 and a.position != pos_a, "it moves again when the freeze ends")
	_check(a.slow_factor == 0.5, "and is still slowed")
	_clear_enemies()
	emp.ability_cooldown_left = 0.0
	_messages.clear()
	_check(not _mgr.activate(emp) and emp.ability_cooldown_left == 0.0, "with no virus anywhere it is refused and the cooldown is kept")
	_check(_messages.size() == 1 and _messages[0] == "SYSTEM FREEZE: NO VIRUSES ON THE MAP", "message names the map, not the range: %s" % [_messages])

func _check_blocked() -> void:
	print("== when an ability can't be used")
	var spike: Node = _mgr.buttons[0].tower
	var e = _spawn(spike, 100.0)
	spike.ability_cooldown_left = 0.0
	spike.set_disabled(true, 30.0)
	_check(not spike.can_use_ability() and not _mgr.activate(spike), "a locked tower can't use its ability")
	await get_tree().process_frame
	_check(_mgr.buttons[0].disabled, "its button is greyed out")
	spike.set_disabled(false)
	get_tree().paused = true
	_check(not _mgr.activate(spike), "abilities can't be used while paused")
	get_tree().paused = false
	_check(_mgr.activate(spike), "usable again after unpausing")
	spike.ability_cooldown_left = 0.0
	_clear_enemies()
	_spawn(spike, 100.0, 50.0)
	await _press(&"ability_1")
	_check(not spike.can_use_ability() and is_equal_approx(spike.ability_cooldown_left, 45.0), "the F1 key uses the first ability")
	var emp: Node = _mgr.buttons[1].tower
	emp.ability_cooldown_left = 0.0
	await _press(&"ability_2")
	_check(is_equal_approx(emp.ability_cooldown_left, 50.0), "the F2 key uses the second ability")
	var third: Node = _mgr.buttons[2].tower
	await _press(&"ability_5")
	_check(third.can_use_ability(), "F5 with only three abilities does nothing")
	_clear_enemies()

func _check_removal() -> void:
	print("== losing the tower removes its ability")
	var s2: Node = _mgr.buttons[2].tower
	_tm.sell_tower(s2)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(_mgr.buttons.size() == 2 and _mgr.buttons.all(func(b): return is_instance_valid(b.tower)), "selling a tower removes its button")
	var e1: Node = _mgr.buttons[1].tower
	e1.take_tower_damage(99999.0)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(_mgr.buttons.size() == 1, "a destroyed tower loses its button")
	_check(_mgr.buttons[0].slot == 0, "the remaining ability keeps slot F1")
	_main.game_state_mgr.change_state(Globals.GameState.PAUSED)
	_check(_mgr.bar.visible, "the bar stays visible while paused")
	_main.game_state_mgr.change_state(Globals.GameState.BUILD_PHASE)
	_main.game_state_mgr.change_state(Globals.GameState.GAME_OVER)
	_check(not _mgr.bar.visible, "the bar hides when the level ends")
	var spike: Node = _mgr.buttons[0].tower
	spike.ability_cooldown_left = 0.0
	_spawn(spike, 100.0)
	await _press(&"ability_1")
	_check(spike.can_use_ability(), "F-keys do nothing outside a level")
	_clear_enemies()
	_main.game_state_mgr.change_state(Globals.GameState.MAIN_MENU)
	Events.level_selected.emit(0)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(_mgr.buttons.is_empty(), "starting a new level clears the bar")
	ResourceManager.current_energy = 50000

func _check_many() -> void:
	print("== more than five abilities")
	var cells := [Vector2i(1, 1), Vector2i(2, 1), Vector2i(6, 1), Vector2i(7, 1), Vector2i(11, 1), Vector2i(12, 1)]
	var towers: Array = []
	for cell in cells:
		var t = _place(cell, SPIKE)
		_buy(t, "BBB")
		towers.append(t)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(_mgr.buttons.size() == 6, "six abilities give six buttons")
	_check(_mgr.buttons[4].slot == 4 and _mgr.buttons[5].slot == -1, "only the first five have an F-key")
	var rect := Rect2(_mgr.bar.position, _mgr.bar.size)
	_check(rect.position.x >= 0.0 and rect.end.x <= _mgr.bar.get_viewport_rect().size.x, "six buttons still fit on screen: %s" % [rect])
	_check(_mgr.buttons.map(func(b): return b.subtitle)[5] == "Data Spike #6", "ordinals count per tower type")
