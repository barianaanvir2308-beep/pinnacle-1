# check_upgrades.gd — Headless upgrade-system checks (docs/scaling_and_upgrades.md E.4)
# Run: godot --headless --path . res://tools/checks/check_upgrades.tscn
extends Node

const CANNON = Globals.TowerType.ANTIVIRUS_CANNON
const SPIKE = Globals.TowerType.DATA_SPIKE
const EMP = Globals.TowerType.EMP_TOWER
const SNIPER = Globals.TowerType.SNIPER_NODE

var _fails: int = 0
var _tm: Node
var _upgrade_events: Array = []

func _check(cond: bool, msg: String) -> void:
	if not cond:
		_fails += 1
	print(("  ok    " if cond else "  FAIL  ") + msg)

func _ready() -> void:
	var main = load("res://scenes/main/Main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	Events.level_selected.emit(0)  # Bootloader = level index 0
	await get_tree().process_frame
	ResourceManager.current_energy = 5000
	ResourceManager.max_energy = 1000000  # these checks hand themselves lots of Energy; the real cap is 1000
	main.get_node("Managers/CombatManager").set_physics_process(false)
	_tm = main.get_node("Managers/TowerManager")
	Events.tower_upgraded.connect(func(t, g, p, tier): _upgrade_events.append([t, g, p, tier]))

	_check_fresh_cannon()
	_check_cannon_walkthrough()
	_check_reverse_crosspath()
	_check_blocked_cases()
	_check_sell_and_rebuild()
	_check_other_towers()

	print("check_upgrades: %d failure(s)" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)

func _place(cell: Vector2i, type: int) -> Node:
	_tm.place_tower(cell, type)
	return _tm.placed_towers[cell]

func _energy() -> int:
	return ResourceManager.current_energy

func _paid(action: Callable) -> int:
	var before := _energy()
	action.call()
	return before - _energy()

func _check_fresh_cannon() -> void:
	print("== fresh Antivirus Cannon")
	var t = _place(Vector2i(1, 1), CANNON)
	_check(t.path_tiers == {"A": 0, "B": 0} and t.chosen_path == "", "starts with no tiers and no chosen path")
	_check(t.damage == 15.0 and t.attack_interval == 1.0 and t.attack_range == 3.5, "base stats 15 dmg / 1.0 s / range 3.5")
	_check(t.total_spent == 100 and t.get_sell_value() == 60, "paid 100, sells for 60 (60%)")
	_check(t.tower_max_health == 100.0, "HP 100 (cost x 1.0)")
	_check(t.get_upgrade_cost("A") == 50 and t.get_upgrade_cost("B") == 50, "Tier 1 costs 50 on both paths")
	_tm.sell_tower(t)

func _check_cannon_walkthrough() -> void:
	print("== Cannon: A1, B1, A2, then the rest")
	var t = _place(Vector2i(1, 1), CANNON)
	t.take_tower_damage(50.0)  # 50% health
	_upgrade_events.clear()

	_check(_paid(func(): _tm.upgrade_tower(t, "A")) == 50, "A1 costs 50 Energy")
	_check(t.damage == 24.0 and t.attack_interval == 1.0, "A1: damage 24, interval unchanged")
	_check(is_equal_approx(t.tower_max_health, 115.0), "A1: max HP 115 (x1.15)")
	_check(is_equal_approx(t.tower_health / t.tower_max_health, 0.5), "A1: keeps 50%% health (%.1f/%.1f)" % [t.tower_health, t.tower_max_health])
	_check(t.chosen_path == "", "A1 does not choose a path yet")
	_check(t.can_upgrade("B"), "B1 is still buyable after A1")
	_check(_paid(func(): _tm.upgrade_tower(t, "B")) == 50, "B1 costs 50 Energy")
	_check(t.attack_interval == 0.7 and t.damage == 24.0, "A1+B1: damage 24 and interval 0.7")

	_check(_paid(func(): _tm.upgrade_tower(t, "A")) == 100, "A2 costs 100 Energy")
	_check(t.chosen_path == "A", "A2 makes A the chosen path")
	_check(t.damage == 28.0 and t.tier_stats.get("pierce") == 2 and t.attack_interval == 0.7 and t.attack_range == 3.5,
		"A2+B1: damage 28, pierce 2, interval 0.7, range 3.5 (the doc's example)")
	_check(t.tier_stats.get("stealth_detect_range") == 1.5, "A2 carries stealth_detect_range 1.5")
	_check(is_equal_approx(t.tower_max_health, 135.0), "A2: max HP 135 (x1.35)")
	_check(t.get_upgrade_status("B") == "path_locked", "B2 is locked once A2 is bought")
	_check(not _tm.upgrade_tower(t, "B"), "buying B2 is refused")

	_check(t.get_upgrade_status("A") == "ok", "A3 is available on Level 1 (there is no level gate on Tier 3)")
	_check(_paid(func(): _tm.upgrade_tower(t, "A")) == 300, "A3 costs 300 Energy")
	_check(t.damage == 28.0 and t.tier_stats.get("burst_count") == 3 and t.tier_stats.get("pierce") == 2, "A3: burst 3, keeps pierce")
	_check(is_equal_approx(t.tower_max_health, 170.0), "A3: max HP 170 (x1.7)")
	_check(t.get_upgrade_status("A") == "maxed" and t.get_upgrade_cost("A") == -1, "A is maxed after Tier 3")
	_check(_paid(func(): _tm.upgrade_tower(t, "A")) == 0, "upgrading a maxed path charges nothing")

	_check(t.get_total_spent() == 100 + 50 + 50 + 100 + 300, "total spent = 600")
	_check(t.get_sell_value() == 360, "sell value = 60% of 600 = 360")
	var expected := [[CANNON, Vector2i(1, 1), "A", 1], [CANNON, Vector2i(1, 1), "B", 1],
		[CANNON, Vector2i(1, 1), "A", 2], [CANNON, Vector2i(1, 1), "A", 3]]
	_check(_upgrade_events == expected, "tower_upgraded fired with (type, cell, path, tier) for each purchase")

	var before := _energy()
	_tm.sell_tower(t)
	_check(_energy() - before == 360 and not _tm.placed_towers.has(Vector2i(1, 1)), "selling refunds 360 and frees the cell")

func _check_reverse_crosspath() -> void:
	print("== Cannon: B2 disables A2")
	var t = _place(Vector2i(2, 1), CANNON)
	_tm.upgrade_tower(t, "B")
	_tm.upgrade_tower(t, "B")
	_check(t.chosen_path == "B", "B2 makes B the chosen path")
	_check(t.attack_interval == 0.7 and t.attack_range == 4.5 and t.tier_stats.get("splash_factor") == 0.3, "B2: interval 0.7, range 4.5, 30% splash")
	_check(t.get_upgrade_status("A") == "ok", "A1 is still buyable")
	_tm.upgrade_tower(t, "A")
	_check(t.get_upgrade_status("A") == "path_locked", "A2 is locked after B2")
	_check(t.damage == 24.0 and t.attack_interval == 0.7, "B2+A1: damage 24 (from A1) and interval 0.7")
	_tm.sell_tower(t)

func _check_blocked_cases() -> void:
	print("== blocked upgrades")
	var t = _place(Vector2i(6, 1), CANNON)
	var before := _energy()
	ResourceManager.current_energy = 10
	_check(t.get_upgrade_status("A") == "too_expensive", "status is too_expensive with 10 Energy")
	_check(not _tm.upgrade_tower(t, "A") and _energy() == 10, "refused and nothing spent")
	ResourceManager.current_energy = before
	t.set_disabled(true, 5.0)
	_check(t.get_upgrade_status("A") == "tower_locked", "a locked tower can't be upgraded")
	t.set_disabled(false)
	_check(t.can_upgrade("A"), "can upgrade again once unlocked")
	_check(t.get_upgrade_status("C") == "no_tree", "unknown path is refused")
	_tm.sell_tower(t)
	var s = _place(Vector2i(7, 1), SNIPER)
	_check(s.get_upgrade_status("A") == "no_tree" and not s.upgrade("A"), "a tower with no tree (Sniper) can't be upgraded")
	_tm.sell_tower(s)

func _check_sell_and_rebuild() -> void:
	print("== upgrade, sell, rebuild gives identical numbers")
	var first = _build_a2_b1(Vector2i(11, 1))
	var snap1 := _snapshot(first)
	_tm.sell_tower(first)
	var second = _build_a2_b1(Vector2i(11, 1))
	_check(_snapshot(second) == snap1, "rebuilt tower matches stats exactly: %s" % [snap1])
	_tm.sell_tower(second)

func _build_a2_b1(cell: Vector2i) -> Node:
	var t = _place(cell, CANNON)
	_tm.upgrade_tower(t, "A")
	_tm.upgrade_tower(t, "B")
	_tm.upgrade_tower(t, "A")
	return t

func _snapshot(t) -> Dictionary:
	return {"damage": t.damage, "range": t.attack_range, "interval": t.attack_interval,
		"hp": t.tower_max_health, "spent": t.total_spent, "tiers": t.path_tiers.duplicate(), "stats": t.tier_stats.duplicate()}

func _check_other_towers() -> void:
	print("== Data Spike and EMP use the same system")
	var sp = _place(Vector2i(12, 1), SPIKE)
	_check(_paid(func(): _tm.upgrade_tower(sp, "A")) == 115, "Data Spike A1 costs 115")
	_check(sp.damage == 120.0 and sp.attack_interval == 2.5 and sp.attack_range == 4.5, "A1: damage 120, interval 2.5, range 4.5")
	_tm.upgrade_tower(sp, "B")
	_check(sp.attack_interval == 1.7 and sp.damage == 120.0, "A1+B1: damage 120 and interval 1.7")
	_check(is_equal_approx(sp.tower_max_health, 225.0 * 1.15), "Spike HP scales from its cost (225)")
	_tm.sell_tower(sp)
	var emp = _place(Vector2i(13, 1), EMP)
	_check(_paid(func(): _tm.upgrade_tower(emp, "A")) == 90, "EMP A1 costs 90")
	_check(emp.attack_interval == 3.3 and emp.attack_range == 2.5, "A1: pulse every 3.3 s, radius unchanged")
	_tm.upgrade_tower(emp, "B")
	_check(emp.attack_range == 3.0 and emp.attack_interval == 3.3, "A1+B1: radius 3.0 and 3.3 s")
	_tm.sell_tower(emp)
