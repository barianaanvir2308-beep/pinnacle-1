# check_viruses.gd — Headless checks for the reworked viruses (docs/balance_spec.md section 4)
# Run: godot --headless --path . res://tools/checks/check_viruses.tscn
# Stats, Trojan timed split, Ransomware mark and lock, Worm module hits and spread, Spyware aura and
# following, Rootkit armour. Viruses are held still (their own _process is off) and stepped by hand.
extends Node

const CANNON = Globals.TowerType.ANTIVIRUS_CANNON
const SPIKE = Globals.TowerType.DATA_SPIKE
const T = Globals.EnemyType
const CELL := Vector2i(5, 4)

var _fails: int = 0
var _main: Node
var _tm: Node
var _enemies: Node
var _shots: Node

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
	ResourceManager.current_energy = 1000
	ResourceManager.max_energy = 1000000
	_main.get_node("Managers/CombatManager").set_physics_process(false)
	_tm = _main.get_node("Managers/TowerManager")
	_enemies = _main.get_node("EnemyContainer")
	_shots = _main.get_node("ProjectileContainer")

	print("== stats and signals")
	_check_stats()
	print("== Trojan Horse")
	await _check_trojan()
	print("== Ransomware")
	await _check_ransomware()
	print("== Worm")
	await _check_worm()
	print("== Spyware")
	_check_spyware()
	print("== Rootkit")
	await _check_rootkit()

	print("check_viruses: %d failure(s)" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)

# ---- helpers ----
func _enemy(type: int, pos: Vector2 = Vector2.ZERO, hp_mult: float = 1.0) -> Node:
	_main._on_spawn_enemy_requested(type, hp_mult, 1.0)
	var e = _enemies.get_child(_enemies.get_child_count() - 1)
	e.set_process(false)
	if pos != Vector2.ZERO:
		_put(e, pos)
	return e

# Moves a virus. A Worm follows base_offset, so that has to move too.
func _put(e: Node, pos: Vector2) -> void:
	e.global_position = pos
	if "base_offset" in e:
		e.base_offset = pos

func _alive_enemies() -> Array:
	return _enemies.get_children().filter(func(n): return is_instance_valid(n) and not n.is_queued_for_deletion())

func _reset() -> void:
	for cell in _tm.placed_towers.keys():
		_tm.sell_tower(_tm.placed_towers[cell])
	for e in _enemies.get_children():
		e.free()
	_main.get_node("Managers/EnemyManager").active_enemies.clear()
	for s in _shots.get_children():
		s.free()
	ResourceManager.current_energy = 1000  # selling only refunds 60%, so top up between tests

func _tower(type: int, cell: Vector2i = CELL) -> Node:
	_tm.place_tower(cell, type)
	return _tm.placed_towers[cell]

# ---- stats ----
func _check_stats() -> void:
	var want := {
		T.BASIC_VIRUS: [60, 1.0, 5, 4], T.WORM: [35, 1.7, 1, 3], T.TROJAN_HORSE: [220, 0.6, 7, 10], T.RANSOMWARE: [160, 0.8, 5, 9],
		T.SPYWARE: [80, 1.0, 0, 10], T.ROOTKIT: [320, 0.42, 15, 20], T.DDOS_BOT: [20, 2.0, 1, 1],
	}
	for type in want:
		var d: Dictionary = Globals.ENEMY_DATA[type]
		_check([d.health, d.speed, d.base_damage, d.reward] == want[type],
			"%s: HP %d, speed %s, Arduino damage %d, bounty %d" % [d.name, want[type][0], want[type][1], want[type][2], want[type][3]])
	var worm: Dictionary = Globals.ENEMY_DATA[T.WORM]
	_check(Globals.ENEMY_DATA[T.TROJAN_HORSE].split_time == 8.0 and worm.module_damage == 15.0 and worm.max_bites == 2 and worm.clone_max_bites == 0,
		"Trojan splits at 8 s; Worm bites for 15, at most 2 modules (a clone: 0, interim) [difficulty_fix F3]")
	_check(Globals.ENEMY_DATA[T.ROOTKIT].armor_flat == 5.0 and not Globals.ENEMY_DATA[T.ROOTKIT].has("armor_factor"), "Rootkit armour is a flat 5 per hit")
	# TODO(difficulty_fix F4): lock_time 3 and max_locks 2 are interim; restore lock_time 5, drop max_locks when the Scanner exists
	var r: Dictionary = Globals.ENEMY_DATA[T.RANSOMWARE]
	_check(r.lock_time == 3.0 and r.max_locks == 2 and r.lock_damage == 10.0 and r.mark_lead_time == 2.0,
		"Ransomware: lock 3 s, at most 2 locks, 10 damage, mark 2 s ahead [difficulty_fix F4]")
	var sp: Dictionary = Globals.ENEMY_DATA[T.SPYWARE]
	_check(sp.aura_radius == 1.5 and sp.aura_speed == 1.2 and sp.aura_damage_taken == 0.8, "Spyware aura: radius 1.5, +20% speed, -20% damage taken")
	_check(not Events.has_signal("ransomware_died") and Events.has_signal("worm_spread"), "the old Ransomware death-lock signal is gone; Worm spread signal exists")

# ---- Trojan ----
func _check_trojan() -> void:
	_reset()
	var t = _enemy(T.TROJAN_HORSE)
	_check(t.split_progress() == 0.0, "a new Trojan's split ring is empty")
	t._process(4.0)
	_check(is_equal_approx(t.split_progress(), 0.5), "the ring is half full after 4 s")
	t._process(3.9)
	_check(t.is_alive and _alive_enemies().size() == 1, "at 7.9 s it has not split")
	t._process(0.2)
	var minis := _alive_enemies().filter(func(n): return n != t)
	_check(not t.is_alive and t.is_queued_for_deletion() and minis.size() == 3, "at 8 s it is replaced by 3 Minis")
	_check(minis.all(func(m): return m.enemy_type == T.BASIC_VIRUS and is_equal_approx(m.max_health, 30.0) and is_equal_approx(m.speed, 1.2) and m.reward == 1 and m.base_damage == 3),
		"each Mini has 30 HP, speed 1.2, bounty 1 and 3 Arduino damage (got %s)" % [minis.map(func(m): return [m.enemy_type, m.max_health, m.speed, m.reward, m.base_damage])])
	_check(minis.all(func(m): return m.global_position.distance_to(t.global_position) < 80.0), "and they appear where the Trojan was")

	_reset()
	var early = _enemy(T.TROJAN_HORSE)
	early._process(5.0)
	early.take_damage(99999.0)
	_check(_alive_enemies().filter(func(n): return n != early).is_empty(), "killed before 8 s, it never splits")

	_reset()
	var stunned = _enemy(T.TROJAN_HORSE)
	stunned.apply_stun(5.0)
	stunned._process(4.0)
	stunned._process(4.0)
	_check(stunned.split_timer == 0.0 and stunned.is_alive, "the split timer is frozen while it is stunned")
	stunned._process(1.0)
	_check(is_equal_approx(stunned.split_timer, 1.0), "and carries on once the stun ends")

# ---- Ransomware ----
func _check_ransomware() -> void:
	_reset()
	var tower = _tower(CANNON)
	var spot: Vector2 = tower.global_position
	var far = _enemy(T.RANSOMWARE, spot + Vector2(400, 0))   # 3.3 tiles: outside the reach (1.05 + 0.8 x 2 = 2.65)
	far._process(0.0)
	_check(not tower.is_marked(), "a module 3.3 tiles away is not marked yet")
	far.global_position = spot + Vector2(300, 0)             # 2.5 tiles
	far._process(0.0)
	_check(tower.is_marked() and not tower.is_tower_disabled, "within about 2 s of walking it is marked, not yet locked")
	far.global_position = spot + Vector2(120, 0)             # 1 tile
	far._process(0.0)
	_check(tower.is_tower_disabled and is_equal_approx(tower.disable_timer, 3.0) and tower._disable_total == 3.0, "within 1 tile it locks the module for 3 s")
	_check(tower.tower_health == tower.tower_max_health - 10.0 and not tower.is_marked(), "dealing 10 damage, and the mark is gone")
	far._process(0.0)
	_check(tower.tower_health == tower.tower_max_health - 10.0, "it does not hit the same module again")

	_reset()
	var cannon = _tower(CANNON, Vector2i(1, 1))
	var spike = _tower(SPIKE, Vector2i(2, 1))
	var ransom = _enemy(T.RANSOMWARE, (cannon.global_position + spike.global_position) * 0.5)
	ransom._process(0.0)
	_check(spike.is_tower_disabled and not cannon.is_tower_disabled, "with two modules in reach it locks the most valuable first (Spike 225 over Cannon 100)")
	ransom._process(0.0)
	_check(cannon.is_tower_disabled, "then moves on to the next module")
	_check(spike.module_value() > cannon.module_value(), "module value follows what the tower cost")

	# F4: at most 2 locks per Ransomware, however many modules are in reach
	_reset()
	var m1 = _tower(SPIKE, Vector2i(1, 1))
	var m2 = _tower(CANNON, Vector2i(2, 1))
	var m3 = _tower(CANNON, Vector2i(1, 2))
	var capped = _enemy(T.RANSOMWARE, (m1.global_position + m2.global_position + m3.global_position) / 3.0)
	for i in 4:
		capped._process(0.0)
	var locked_count := [m1, m2, m3].filter(func(m): return m.is_tower_disabled).size()
	_check(locked_count == 2 and m1.is_tower_disabled and m2.is_tower_disabled and not m3.is_tower_disabled, "a Ransomware locks at most 2 modules (the two most valuable here)")
	_check(not m3.is_marked(), "and it stops marking once it has used its locks")

	_reset()
	var victim = _tower(CANNON)
	var dying = _enemy(T.RANSOMWARE, victim.global_position + Vector2(300, 0))
	dying._process(0.0)
	_check(victim.is_marked(), "(marked)")
	dying.take_damage(99999.0)
	await get_tree().process_frame
	_check(not victim.is_tower_disabled and not victim.is_marked(), "a Ransomware that is killed locks nothing and its mark disappears")

	_reset()
	var safe = _tower(CANNON)
	var frozen = _enemy(T.RANSOMWARE, safe.global_position + Vector2(120, 0))
	frozen.apply_stun(5.0)
	frozen._process(0.1)
	_check(not safe.is_tower_disabled, "a stunned Ransomware can't lock")
	_check(safe.get_lock_duration(5.0) == 5.0, "a tower's lock duration is 5 s (the Scanner will change this)")

# ---- Worm ----
func _check_worm() -> void:
	_reset()
	var tower = _tower(CANNON)
	var near = _enemy(T.WORM, tower.global_position + Vector2(180, 0))   # 1.5 tiles: out of contact
	near._process(0.016)
	_check(tower.tower_health == tower.tower_max_health and _alive_enemies().size() == 1, "a Worm 1.5 tiles away does nothing")
	_put(near, tower.global_position + Vector2(120, 0))
	near._process(0.016)
	_check(tower.tower_health == tower.tower_max_health - 15.0, "on contact it bites the module for 15")
	var worms := _alive_enemies().filter(func(n): return n.enemy_type == T.WORM)
	_check(worms.size() == 2, "and spreads: a second Worm appears")
	var clone = worms.filter(func(w): return w != near)[0]
	_check(near.can_spread and not clone.can_spread and clone.is_clone and is_equal_approx(clone.max_health, near.max_health), "the clone cannot spread, is marked as a clone and has the same HP")
	_check(clone._hit_modules.has(tower), "the clone inherits the modules its parent already bit")
	clone.set_process(false)
	_put(clone, tower.global_position + Vector2(100, 0))
	for i in 5:
		clone._process(0.016)
		near._process(0.016)
	_check(tower.tower_health == tower.tower_max_health - 15.0 and _alive_enemies().size() == 2, "neither bites that module again, and nothing spreads twice")

	# F3: an original bites at most 2 modules, a clone none (clone_max_bites is 0 for now; the test reads the data)
	_reset()
	await get_tree().process_frame  # sold towers are freed at the end of the frame
	var a1 = _tower(SPIKE, Vector2i(1, 1))
	var a2 = _tower(CANNON, Vector2i(2, 1))
	var a3 = _tower(CANNON, Vector2i(1, 2))
	var centre: Vector2 = (a1.global_position + a2.global_position + a3.global_position) / 3.0
	var original = _enemy(T.WORM, centre)
	for i in 5:
		original._process(0.016)
	var bitten := [a1, a2, a3].filter(func(m): return m.tower_health < m.tower_max_health)
	# the two cannons are equally valuable, so which one is second is a tie: only the Data Spike is certain
	_check(bitten.size() == 2 and a1.tower_health == a1.tower_max_health - 15.0 and bitten.all(func(m): return is_equal_approx(m.tower_health, m.tower_max_health - 15.0)),
		"an original Worm bites at most 2 of 3 modules (the Data Spike first, then one Cannon)")
	_check(_alive_enemies().filter(func(n): return n.enemy_type == T.WORM).size() == 2, "and spreads once")
	_reset()
	await get_tree().process_frame
	var b1 = _tower(SPIKE, Vector2i(1, 1))
	var b2 = _tower(CANNON, Vector2i(2, 1))
	var b3 = _tower(CANNON, Vector2i(1, 2))
	var spawned = _enemy(T.WORM, (b1.global_position + b2.global_position + b3.global_position) / 3.0)
	spawned.can_spread = false
	spawned.is_clone = true
	for i in 5:
		spawned._process(0.016)
	var clone_bites := [b1, b2, b3].filter(func(m): return m.tower_health < m.tower_max_health).size()
	_check(clone_bites == Globals.ENEMY_DATA[T.WORM].clone_max_bites and _alive_enemies().size() == 1, "a clone bites at most clone_max_bites (%d) modules, and never spreads" % Globals.ENEMY_DATA[T.WORM].clone_max_bites)

	_reset()
	await get_tree().process_frame
	var still = _tower(CANNON)
	var held = _enemy(T.WORM, still.global_position + Vector2(100, 0))
	held.apply_stun(5.0)
	held._process(0.016)
	_check(still.tower_health == still.tower_max_health, "a stunned Worm does not attack")

# ---- Spyware ----
func _check_spyware() -> void:
	_reset()
	var spy = _enemy(T.SPYWARE, Vector2(600, 600))
	var inside = _enemy(T.BASIC_VIRUS, Vector2(700, 600), 20.0)    # 100 px: inside the 180 px aura
	var outside = _enemy(T.BASIC_VIRUS, Vector2(850, 600), 20.0)   # 250 px: outside
	inside._update_aura(1.0)
	outside._update_aura(1.0)
	_check(inside._aura_buffed and not outside._aura_buffed, "a virus inside the Spyware's aura is buffed, one outside is not")
	_check(is_equal_approx(inside._speed_factor(), 1.2) and outside._speed_factor() == 1.0, "buffed: +20% speed")
	var hp: float = inside.health
	inside.take_damage(100.0)
	outside.take_damage(100.0)
	_check(is_equal_approx(hp - inside.health, 80.0) and is_equal_approx(outside.max_health - outside.health, 100.0), "buffed: takes 20% less damage (80 of a 100 hit)")
	var spy2 = _enemy(T.SPYWARE, Vector2(650, 600))
	inside._aura_check_time = 0.0
	inside._update_aura(1.0)
	var before: float = inside.health
	inside.take_damage(100.0)
	_check(is_equal_approx(before - inside.health, 80.0) and is_equal_approx(inside._speed_factor(), 1.2), "two Spyware do not stack the buff")
	spy._update_aura(1.0)
	spy2._update_aura(1.0)
	_check(not spy._aura_buffed and not spy2._aura_buffed, "Spyware are not buffed by each other")
	spy.take_damage(99999.0)
	spy2.take_damage(99999.0)
	inside._aura_check_time = 0.0
	inside._update_aura(1.0)
	_check(not inside._aura_buffed, "when the Spyware die the buff is gone")

	_reset()
	var escort = _enemy(T.SPYWARE, Vector2(600, 600))
	_check(escort.is_visible_to_towers and escort.modulate.a == 1.0, "Spyware is no longer invisible")
	escort._update_follow(1.0)
	_check(escort.follow_target == null and is_equal_approx(escort.speed, 1.0), "with no other virus it walks at its own pace (1.0)")
	var worm = _enemy(T.WORM, Vector2(700, 600))
	var slow = _enemy(T.ROOTKIT, Vector2(1500, 900))
	escort._update_follow(1.0)
	_check(escort.follow_target == worm and is_equal_approx(escort.speed, worm.speed), "it follows the nearest virus and matches its pace (Worm 1.7)")
	worm.take_damage(99999.0)
	escort._update_follow(1.0)
	_check(escort.follow_target == slow and is_equal_approx(escort.speed, 0.42), "when that one dies it follows the next nearest (Rootkit 0.42)")
	var base_hp: int = _main.base_health
	escort.reach_base()
	_check(_main.base_health == base_hp, "a Spyware that reaches the Arduino does 0 damage")

# ---- Rootkit ----
func _check_rootkit() -> void:
	_reset()
	var rk = _enemy(T.ROOTKIT, Vector2(600, 600), 20.0)
	var hp: float = rk.health
	rk.take_damage(100.0)
	_check(is_equal_approx(hp - rk.health, 95.0), "armour takes 5 off a hit: 100 -> 95")
	hp = rk.health
	rk.take_damage(100.0, true)
	_check(is_equal_approx(hp - rk.health, 100.0), "armour-piercing damage ignores the armour")
	hp = rk.health
	rk.take_damage(4.0)
	_check(is_equal_approx(hp - rk.health, 1.0), "a weak hit still does at least 1 damage (4 -> 1)")

	_reset()
	var spike = _tower(SPIKE)
	var cannon = _tower(CANNON, Vector2i(10, 4))
	var target = _enemy(T.ROOTKIT, spike.global_position + Vector2(150, 0), 20.0)
	hp = target.health
	spike.fire_at(target)
	await get_tree().create_timer(0.6).timeout
	_check(is_equal_approx(hp - target.health, 80.0), "a Data Spike shot ignores the armour: full 80")
	hp = target.health
	target.global_position = cannon.global_position + Vector2(150, 0)
	cannon.fire_at(target)
	await get_tree().create_timer(0.6).timeout
	_check(is_equal_approx(hp - target.health, 10.0), "a Cannon shot loses 5: 15 -> 10")
