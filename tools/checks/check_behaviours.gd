# check_behaviours.gd — Headless checks for what each upgrade tier DOES (Cannon, Data Spike, EMP Tower)
# Run: godot --headless --path . res://tools/checks/check_behaviours.tscn
# Viruses are held still (their _process is off) so only the tower effects are measured.
extends Node

const CANNON = Globals.TowerType.ANTIVIRUS_CANNON
const SPIKE = Globals.TowerType.DATA_SPIKE
const EMP = Globals.TowerType.EMP_TOWER
const CELL := Vector2i(5, 4)

var _fails: int = 0
var _main: Node
var _tm: Node
var _enemies: Node
var _shots: Node
var _spawned: Array = []  # every Projectile that entered the container

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
	ResourceManager.current_energy = 90000
	ResourceManager.max_energy = 1000000  # these checks hand themselves lots of Energy; the real cap is 1000
	_main.get_node("Managers/CombatManager").set_physics_process(false)
	_tm = _main.get_node("Managers/TowerManager")
	_enemies = _main.get_node("EnemyContainer")
	_shots = _main.get_node("ProjectileContainer")
	_shots.child_entered_tree.connect(func(n): if n is Projectile: _spawned.append(n))

	print("== targeting")
	_check_targeting()
	print("== Antivirus Cannon")
	await _check_cannon_pierce()
	await _check_cannon_burst()
	await _check_cannon_splash()
	_check_cannon_stealth()
	print("== Data Spike")
	await _check_spike_bonus()
	await _check_spike_stun()
	await _check_spike_chain()
	await _check_spike_multishot()
	print("== EMP Tower")
	_check_emp_base()
	_check_emp_tiers()

	print("check_behaviours: %d failure(s)" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)

# ---- helpers ----
func _tower(type: int, path_sequence: String = "") -> Node:
	for cell in _tm.placed_towers.keys():
		_tm.sell_tower(_tm.placed_towers[cell])
	_tm.place_tower(CELL, type)
	var t = _tm.placed_towers[CELL]
	for p in path_sequence:
		_tm.upgrade_tower(t, p)
	return t

func _enemy(near: Node, offset: Vector2, hp_mult: float = 20.0, type: int = Globals.EnemyType.BASIC_VIRUS) -> Node:
	_main._on_spawn_enemy_requested(type, hp_mult, 1.0)
	var e = _enemies.get_child(_enemies.get_child_count() - 1)
	e.set_process(false)
	e.global_position = near.global_position + offset
	return e

func _reset() -> void:
	for e in _enemies.get_children():
		e.free()
	_main.get_node("Managers/EnemyManager").active_enemies.clear()
	for s in _shots.get_children():
		s.free()
	_spawned.clear()

func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout

# ---- targeting ----
func _check_targeting() -> void:
	_reset()
	var cannon = _tower(CANNON)
	_check(cannon.target_mode == Globals.TargetMode.FIRST, "the Cannon targets FIRST (from its data)")
	var spike = _tower(SPIKE)
	var a = _enemy(spike, Vector2(100, 0))
	var b = _enemy(spike, Vector2(100, 0))
	a.health = 150.0
	b.health = 150.0
	_check(spike.find_target([a, b]) == a and spike.find_target([b, a]) == b, "equal targets: the first in the list wins (deterministic)")
	_check(spike.target_mode == Globals.TargetMode.STRONGEST, "the Data Spike targets STRONGEST (it used to ignore its data)")
	var weak = _enemy(spike, Vector2(100, 0))
	var strong = _enemy(spike, Vector2(150, 0))
	var mid = _enemy(spike, Vector2(200, 0))
	weak.health = 100.0
	strong.health = 300.0
	mid.health = 200.0
	_check(spike.find_target([weak, strong, mid]) == strong, "the Spike picks the strongest virus")
	_check(spike.find_targets([weak, strong, mid], 3) == [strong, mid, weak], "find_targets lists the 3 best, strongest first")
	_check(spike.find_targets([weak, strong, mid], 2) == [strong, mid], "and respects the count")
	_reset()

# ---- Cannon ----
func _check_cannon_pierce() -> void:
	_reset()
	var base = _tower(CANNON)
	var a = _enemy(base, Vector2(150, 0))
	var b = _enemy(base, Vector2(250, 0))
	var hp: float = a.health
	base.fire_at(a)
	await _wait(0.7)
	_check(a.health == hp - 15.0 and b.health == hp, "base Cannon: the shot stops at its target (15 damage, none behind)")

	_reset()
	var deep = _tower(CANNON, "AA")
	_check(deep.tier_stats.get("pierce") == 2 and deep.damage == 28.0, "Deep Scan (A2): damage 28, pierce 2")
	var e1 = _enemy(deep, Vector2(150, 0))
	var e2 = _enemy(deep, Vector2(250, 0))
	var e3 = _enemy(deep, Vector2(350, 0))
	hp = e1.health
	deep.fire_at(e1)
	await _wait(0.9)
	_check(e1.health == hp - 28.0 and e2.health == hp - 28.0, "the shot pierces: both viruses in line take 28")
	_check(e3.health == hp, "but only 2 viruses in total: the third is untouched")

func _check_cannon_burst() -> void:
	_reset()
	var engine = _tower(CANNON, "AAA")
	_check(engine.tier_stats.get("burst_count") == 3, "Heuristic Engine (A3): burst of 3")
	var e = _enemy(engine, Vector2(100, 0))
	var hp: float = e.health
	engine.fire_at(e)
	_check(_spawned.size() == 1, "a burst fires its first shot straight away")
	await _wait(0.7)
	_check(_spawned.size() == 3 and e.health == hp - 84.0, "then 2 more follow: 3 shots, 3 x 28 = 84 damage")
	_reset()
	var e2 = _enemy(engine, Vector2(100, 0))
	engine.fire_at(e2)
	engine.set_disabled(true, 5.0)
	await _wait(0.5)
	_check(_spawned.size() == 1, "a tower that gets locked mid-burst stops firing")

func _check_cannon_splash() -> void:
	for spec in [["BB", 0.3, 4.5], ["BBB", 0.5, 7.5]]:
		_reset()
		var t = _tower(CANNON, spec[0])
		var prim = _enemy(t, Vector2(100, 0))
		var near = _enemy(prim, Vector2(0, 60))    # 0.5 tile from the target: inside the 0.75 tile splash
		var far = _enemy(prim, Vector2(0, 200))    # outside it
		var hp: float = prim.health
		t.fire_at(prim)
		await _wait(0.5)
		_check(prim.health == hp - 15.0 and is_equal_approx(near.health, hp - spec[2]) and far.health == hp,
			"%s: %d%% splash: target -15, the virus next to it -%s, the far one untouched" % [spec[0], spec[1] * 100, spec[2]])

func _check_cannon_stealth() -> void:
	_reset()
	var base = _tower(CANNON)
	var spy = _enemy(base, Vector2(120, 0), 1.0)
	spy.is_visible_to_towers = false  # what a Stealth virus will be (the virus itself doesn't exist yet)
	_check(base.find_target([spy]) == null, "a hidden virus can't be targeted by a base Cannon")
	spy.reveal(1.0)
	_check(base.find_target([spy]) == spy, "...until it is revealed")
	_reset()
	var scan = _tower(CANNON, "AA")
	var near = _enemy(scan, Vector2(120, 0), 1.0)   # 1 tile
	var far = _enemy(scan, Vector2(300, 0), 1.0)    # 2.5 tiles
	near.is_visible_to_towers = false
	far.is_visible_to_towers = false
	_check(scan.find_target([near]) == near and scan.find_target([far]) == null, "Deep Scan (A2) sees hidden viruses within 1.5 tiles, not beyond")
	_reset()

# ---- Data Spike ----
func _check_spike_bonus() -> void:
	_reset()
	var base = _tower(SPIKE)
	var trojan = _enemy(base, Vector2(150, 0), 20.0, Globals.EnemyType.TROJAN_HORSE)
	_check(base.get_damage_against(trojan) == 80.0, "base Spike: 80 damage to a Trojan (no bonus)")
	var exploit = _tower(SPIKE, "AA")
	var basic = _enemy(exploit, Vector2(100, 0))
	var trojan2 = _enemy(exploit, Vector2(150, 0), 20.0, Globals.EnemyType.TROJAN_HORSE)
	var boss = _enemy(exploit, Vector2(200, 0))
	boss.is_boss = true
	_check(exploit.get_damage_against(basic) == 160.0, "Kernel Exploit (A2): 160 damage to a normal virus")
	_check(exploit.get_damage_against(trojan2) == 240.0, "+50% against a Trojan: 240")
	_check(exploit.get_damage_against(boss) == 240.0, "+50% against anything flagged as a boss: 240 (the Boss virus does not exist yet)")
	var hp: float = trojan2.health
	exploit.fire_at(trojan2)
	await _wait(0.6)
	_check(trojan2.health == hp - 240.0, "a real shot at the Trojan lands for 240")

func _check_spike_stun() -> void:
	_reset()
	var t = _tower(SPIKE, "AAA")
	_check(t.damage == 500.0 and t.tier_stats.get("stun_every_n_hits") == 3, "Zero-Day (A3): damage 500, stun on every 3rd hit")
	var e = _enemy(t, Vector2(150, 0), 200.0)
	t.on_projectile_hit(e, 500.0)
	t.on_projectile_hit(e, 500.0)
	_check(e.stun_timer == 0.0, "hits 1 and 2 do not stun")
	t.on_projectile_hit(e, 500.0)
	_check(is_equal_approx(e.stun_timer, 1.0), "the 3rd hit stuns for 1 s")
	var boss_tower = _tower(SPIKE, "AAA")
	var boss = _enemy(boss_tower, Vector2(150, 0), 200.0)
	boss.stun_immune = true
	for i in 3:
		boss_tower.on_projectile_hit(boss, 500.0)
	_check(boss.stun_timer == 0.0 and boss.slow_factor == 0.5 and is_equal_approx(boss.slow_timer, 1.0), "a stun-immune virus is slowed 50% for 1 s instead")
	var shooter = _tower(SPIKE, "AAA")
	var target = _enemy(shooter, Vector2(150, 0), 200.0)
	var hp: float = target.health
	shooter.fire_at(target)
	await _wait(0.6)
	_check(target.health == hp - 500.0, "a real Zero-Day shot lands for 500")

func _check_spike_chain() -> void:
	_reset()
	var t = _tower(SPIKE, "BB")
	_check(t.tier_stats.get("chain_targets") == 1 and t.attack_range == 5.0, "Chain Spike (B2): 1 chain, range 5.0")
	var first = _enemy(t, Vector2(150, 0))
	var next = _enemy(first, Vector2(200, 0))       # 1.7 tiles from the first: inside the 3 tile jump
	var next2 = _enemy(first, Vector2(300, 0))      # also inside, but farther than `next`
	var beyond = _enemy(first, Vector2(0, 500))     # outside the jump
	var hp: float = first.health
	t.on_projectile_hit(first, 80.0)
	_check(next.health == hp - 40.0, "the spike jumps to the nearest other virus for 50%: 40")
	_check(next2.health == hp and beyond.health == hp, "only one jump: the next-nearest and the far one are untouched")
	var arcs := _shots.get_children().filter(func(n): return n is Line2D)
	_check(arcs.size() == 1, "a lightning arc is drawn for the jump")
	_reset()
	var shooter = _tower(SPIKE, "BB")
	var a = _enemy(shooter, Vector2(150, 0))
	var b = _enemy(a, Vector2(180, 0))
	hp = a.health
	shooter.fire_at(a)
	await _wait(0.6)
	_check(a.health == hp - 80.0 and b.health == hp - 40.0, "a real shot: 80 to the target, 40 to the chained virus")

func _check_spike_multishot() -> void:
	_reset()
	var t = _tower(SPIKE, "BBB")
	_check(t.tier_stats.get("multishot") == 3 and t.has_ability(), "Spike Storm (B3): 3 spikes and the Purge ability")
	var low = _enemy(t, Vector2(100, 0))
	var high = _enemy(t, Vector2(150, 0))
	var mid = _enemy(t, Vector2(200, 0))
	low.health = 100.0
	high.health = 300.0
	mid.health = 200.0
	t.fire_at(high)
	_check(_spawned.size() == 3 and _spawned.map(func(p): return p.target) == [high, mid, low], "3 viruses: one spike at each, strongest first")
	_reset()
	var a = _enemy(t, Vector2(100, 0))
	var b = _enemy(t, Vector2(150, 0))
	a.health = 100.0
	b.health = 300.0
	t.fire_at(a)
	_check(_spawned.size() == 3 and _spawned.map(func(p): return p.target) == [b, a, b], "2 viruses: the third spike goes back to the strongest")
	_reset()
	var only = _enemy(t, Vector2(100, 0))
	t.fire_at(only)
	_check(_spawned.size() == 3 and _spawned.all(func(p): return p.target == only), "1 virus: all 3 spikes hit it")
	_reset()

# ---- EMP ----
func _check_emp_base() -> void:
	_reset()
	var emp = _tower(EMP)
	var in1 = _enemy(emp, Vector2(100, 0))
	var in2 = _enemy(emp, Vector2(250, 0))
	var out = _enemy(emp, Vector2(350, 0))     # radius is 2.5 tiles = 300 px
	var hp: float = in1.health
	emp.try_attack([in1, in2, out])
	_check(in1.stun_timer == 1.0 and in2.stun_timer == 1.0 and out.stun_timer == 0.0, "the pulse stuns every virus in radius for 1 s, and no others")
	_check(in1.health == hp - 4.0 and out.health == hp, "and deals 4 damage to those in radius")
	_check(emp.cooldown_timer == 4.0, "it then waits 4 s")
	_reset()
	var idle = _tower(EMP)
	var far = _enemy(idle, Vector2(400, 0))
	idle.try_attack([far])
	_check(idle.cooldown_timer == 0.0 and far.stun_timer == 0.0, "with nothing in radius the pulse is not used up")

func _check_emp_tiers() -> void:
	# A1: faster pulse; A2: longer stun and bonus damage while stunned; A3 keeps both
	_reset()
	var a1 = _tower(EMP, "A")
	a1.try_attack([_enemy(a1, Vector2(100, 0))])
	_check(is_equal_approx(a1.cooldown_timer, 3.3), "Capacitor (A1): pulses every 3.3 s")
	_reset()
	var a2 = _tower(EMP, "AA")
	var e = _enemy(a2, Vector2(100, 0))
	a2.try_attack([e])
	_check(e.stun_timer == 1.5 and is_equal_approx(e.stun_vulnerability, 1.15), "Overload (A2): stun 1.5 s, stunned viruses take +15%")
	var before: float = e.health
	e.take_damage(100.0)
	_check(is_equal_approx(before - e.health, 115.0), "a stunned virus takes 115 from a 100 hit")
	e._tick_status(2.0)
	before = e.health
	e.take_damage(100.0)
	_check(e.stun_vulnerability == 1.0 and is_equal_approx(before - e.health, 100.0), "once the stun ends it takes normal damage")
	_reset()
	var a3 = _tower(EMP, "AAA")
	_check(a3.tier_stats.get("stun") == 1.5 and a3.attack_interval == 3.3 and a3.has_ability(), "System Freeze (A3) keeps the T2 stun and has its ability")
	# B1: wider pulse
	_reset()
	var base = _tower(EMP)
	var edge = _enemy(base, Vector2(336, 0))   # 2.8 tiles
	base.try_attack([edge])
	_check(edge.stun_timer == 0.0, "base EMP (radius 2.5): a virus at 2.8 tiles is missed")
	_reset()
	var wide = _tower(EMP, "B")
	var edge2 = _enemy(wide, Vector2(336, 0))
	wide.try_attack([edge2])
	_check(edge2.stun_timer == 1.0 and wide.attack_range == 3.0, "Wide Pulse (B1): radius 3.0 reaches it")
	# B2: slow after the stun, and reveals hidden viruses
	_reset()
	var scr = _tower(EMP, "BB")
	var v = _enemy(scr, Vector2(100, 0))
	var boss = _enemy(scr, Vector2(150, 0))
	boss.stun_immune = true
	scr.try_attack([v, boss])
	_check(v.stun_timer == 1.0 and v.slow_factor == 0.7 and is_equal_approx(v.slow_timer, 3.0), "Scrambler (B2): 30% slow lasting 2 s after the 1 s stun")
	_check(v.revealed_timer == 1.0 and boss.revealed_timer == 1.0, "and every virus hit is revealed for 1 s")
	_check(boss.stun_timer == 0.0 and boss.slow_factor == 0.5 and is_equal_approx(boss.slow_timer, 1.0), "a stun-immune virus is only slowed 50%")
	# B3: 25 damage, and bosses are stunned 0.5 s
	_reset()
	var ion = _tower(EMP, "BBB")
	var w = _enemy(ion, Vector2(100, 0))
	var b2 = _enemy(ion, Vector2(150, 0))
	b2.stun_immune = true
	var hp: float = w.health
	ion.try_attack([w, b2])
	_check(ion.damage == 25.0 and w.health == hp - 25.0, "Ion Storm (B3): pulses deal 25 damage")
	_check(is_equal_approx(b2.stun_timer, 0.5), "and stun bosses for 0.5 s")
	_reset()
