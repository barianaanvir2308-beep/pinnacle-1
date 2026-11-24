# check_economy.gd — Headless checks for the economy (docs/balance_spec.md section 2)
# Run: godot --headless --path . res://tools/checks/check_economy.tscn
# Passive income and its gating, the Energy Capacity, bounties, wave bonus, per-level start, repair,
# and the Emergency Overclock with System Load. Uses the real game scene.
extends Node

const CANNON = Globals.TowerType.ANTIVIRUS_CANNON
const CELL := Vector2i(5, 4)
const START_ENERGY := [300, 350, 400, 500, 600]  # Level 1 is 300 (difficulty_fix F6)

var _fails: int = 0
var _main: Node
var _tm: Node
var _oc: OverclockManager
var _wm: Node
var _enemies: Node
var _gsm: Node

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
	_tm = _main.get_node("Managers/TowerManager")
	_oc = _main.overclock_mgr
	_wm = _main.get_node("Managers/WaveManager")
	_enemies = _main.get_node("EnemyContainer")
	_gsm = _main.game_state_mgr
	_main.get_node("Managers/CombatManager").set_physics_process(false)

	print("== constants and level data")
	_check_data()
	print("== bounties")
	_check_bounties()
	print("== passive income")
	await _check_passive()
	print("== Energy Capacity")
	_check_cap()
	print("== wave bonus")
	await _check_wave_bonus()
	print("== repair")
	await _check_repair()
	print("== Emergency Overclock")
	await _check_overclock()
	print("== starting energy per level")
	await _check_levels()

	print("check_economy: %d failure(s)" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)

# ---- helpers ----
func _energy() -> int:
	return ResourceManager.current_energy

func _enemy(type: int = Globals.EnemyType.BASIC_VIRUS) -> Node:
	_main._on_spawn_enemy_requested(type, 1.0, 1.0)
	var e = _enemies.get_child(_enemies.get_child_count() - 1)
	e.set_process(false)
	return e

func _reset_enemies() -> void:
	for e in _enemies.get_children():
		e.free()
	_main.get_node("Managers/EnemyManager").active_enemies.clear()

func _clear_towers() -> void:
	for cell in _tm.placed_towers.keys():
		_tm.sell_tower(_tm.placed_towers[cell])

func _tower(path_sequence: String = "") -> Node:
	_clear_towers()
	_tm.place_tower(CELL, CANNON)
	var t = _tm.placed_towers[CELL]
	for p in path_sequence:
		_tm.upgrade_tower(t, p)
	return t

# Switches state (if it isn't there already) and waits two frames: main.gd updates its flags during a frame,
# after this script has run, so one frame is too early to read them
func _state(state: int) -> void:
	if _gsm.current_state != state:
		_gsm.change_state(state)
	await _frames(2)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

# ---- data ----
func _check_data() -> void:
	# TODO(difficulty_fix F2): passive is 3.0 until the Energy Decoder exists; change this (and the passive checks below) back to 2.0 then
	_check(Globals.MAX_ENERGY == 1000 and Globals.PASSIVE_ENERGY_RATE == 3.0 and Globals.SELL_REFUND_PERCENTAGE == 0.6, "cap 1000, passive 3 Energy/s (interim, difficulty_fix F2), sell refund 60%")
	var bonuses := range(1, 11).map(func(w): return Globals.wave_bonus(w))
	_check(bonuses == [25, 35, 45, 55, 65, 75, 85, 95, 105, 115], "wave bonus is 15 + 10 x wave: %s" % [bonuses])
	_check(START_ENERGY == Globals.LEVEL_DATA.map(func(l): return l.starting_energy), "starting Energy per level: %s" % [Globals.LEVEL_DATA.map(func(l): return l.starting_energy)])
	_check(Globals.LEVEL_DATA.all(func(l): return l.arduino_hp == 100), "Arduino HP is 100 on every level")
	var rewards := {Globals.EnemyType.BASIC_VIRUS: 4, Globals.EnemyType.WORM: 3, Globals.EnemyType.TROJAN_HORSE: 10, Globals.EnemyType.RANSOMWARE: 9,
		Globals.EnemyType.SPYWARE: 10, Globals.EnemyType.ROOTKIT: 20, Globals.EnemyType.DDOS_BOT: 1}
	var ok := true
	for type in rewards:
		if Globals.ENEMY_DATA[type].reward != rewards[type]:
			ok = false
	_check(ok, "kill bounties match balance_spec 4.1 (Basic 4, Worm 3, Trojan 10, Ransomware 9, Spyware 10, Rootkit 20, DDoS 1)")
	var tj: Dictionary = Globals.ENEMY_DATA[Globals.EnemyType.TROJAN_HORSE]
	_check(tj.split_reward == 1 and tj.split_damage == 3, "Trojan Minis pay 1 Energy and do 3 damage")

func _check_bounties() -> void:
	_reset_enemies()
	for type in [Globals.EnemyType.BASIC_VIRUS, Globals.EnemyType.WORM, Globals.EnemyType.RANSOMWARE, Globals.EnemyType.SPYWARE, Globals.EnemyType.ROOTKIT, Globals.EnemyType.DDOS_BOT]:
		ResourceManager.current_energy = 300
		var e = _enemy(type)
		var want: int = Globals.ENEMY_DATA[type].reward
		e.take_damage(99999.0)
		_check(_energy() == 300 + want, "killing a %s pays %d" % [Globals.ENEMY_DATA[type].name, want])
	_reset_enemies()
	ResourceManager.current_energy = 300
	var trojan = _enemy(Globals.EnemyType.TROJAN_HORSE)
	trojan.take_damage(99999.0)
	_check(_energy() == 310, "killing a Trojan pays 10")
	_check(_enemies.get_children().filter(func(n): return n != trojan and not n.is_queued_for_deletion()).is_empty(), "and it does not split when it is killed")
	# a Trojan that survives its 8 seconds splits instead, paying nothing
	var survivor = _enemy(Globals.EnemyType.TROJAN_HORSE)
	ResourceManager.current_energy = 300
	survivor._process(8.1)
	_check(_energy() == 300, "a Trojan that splits pays no Energy")
	var minis := _enemies.get_children().filter(func(n): return n != survivor and n != trojan and is_instance_valid(n) and not n.is_queued_for_deletion())
	_check(minis.size() == 3 and minis.all(func(m): return m.reward == 1 and m.base_damage == 3 and is_equal_approx(m.max_health, 30.0)),
		"it splits into 3 Minis with 30 HP, worth 1 Energy and doing 3 damage")
	ResourceManager.current_energy = 300
	minis[0].take_damage(99999.0)
	_check(_energy() == 301, "killing a Mini pays 1")
	_reset_enemies()

# ---- passive income ----
func _check_passive() -> void:
	ResourceManager.current_energy = 100
	await _state(Globals.GameState.BUILD_PHASE)
	_main.build_countdown = -1.0
	_main.wave_start_countdown = -1.0
	_check(not ResourceManager.passive_enabled, "no passive income while idling in the build phase at level start")
	var before := _energy()
	await get_tree().create_timer(1.2).timeout
	_check(_energy() == before, "...and none is earned there (%d -> %d)" % [before, _energy()])
	_main.build_countdown = 5.0
	await _frames(2)
	_check(ResourceManager.passive_enabled, "income flows during the 15 s build countdown")
	_main.build_countdown = -1.0
	_main.wave_start_countdown = 2.0
	await _frames(2)
	_check(ResourceManager.passive_enabled, "and during the 3 s countdown before the wave")
	_main.wave_start_countdown = -1.0
	await _state(Globals.GameState.WAVE_ACTIVE)
	_check(ResourceManager.passive_enabled, "and during a wave")
	before = _energy()
	await get_tree().create_timer(3.1).timeout
	var gained := _energy() - before
	_check(gained >= 8 and gained <= 10, "about 3 Energy/s is earned in real time (%d in 3.1 s)" % gained)
	await _state(Globals.GameState.PAUSED)
	_check(not ResourceManager.passive_enabled and get_tree().paused, "nothing is earned while paused")
	before = _energy()
	await get_tree().create_timer(0.6).timeout
	_check(_energy() == before, "...confirmed over 0.6 s paused")
	await _state(Globals.GameState.WAVE_ACTIVE)
	_oc.system_load = 95.0
	await _frames(2)
	_check(not ResourceManager.passive_enabled, "passive income stops at System Load 90 or more")
	_oc.system_load = 0.0
	# the arithmetic: fractions are carried over
	ResourceManager.passive_enabled = true
	ResourceManager.current_energy = 100
	ResourceManager._process(3.0)
	_check(_energy() == 109, "3 s of passive income adds exactly 9")
	var f := _energy()
	for i in 3:
		ResourceManager.add_energy_float(0.4)
	_check(_energy() == f + 1, "fractions are carried over: 3 x 0.4 = 1.2 adds 1")
	await _state(Globals.GameState.BUILD_PHASE)

# ---- cap ----
func _check_cap() -> void:
	ResourceManager.lost_to_cap = 0
	ResourceManager.current_energy = 990
	ResourceManager.add_energy(50)
	_check(_energy() == 1000 and ResourceManager.lost_to_cap == 40, "income above the cap is lost (and counted): 990 + 50 -> 1000, lost 40")
	var hud = _main.hud
	_check(hud.energy_label.text == "ENERGY: 1000 / 1000" and is_equal_approx(hud.energy_bar_fill.size.x, 448.0), "the HUD shows Energy against the cap")
	_check(hud.energy_flashing, "the Energy bar flashes at 90% or more")
	ResourceManager.current_energy = 899
	Events.energy_changed.emit(899)
	_check(not hud.energy_flashing, "...and stops below 90%")
	ResourceManager.current_energy = 900
	Events.energy_changed.emit(900)
	_check(hud.energy_flashing, "...starting exactly at 900")

# ---- wave bonus ----
func _check_wave_bonus() -> void:
	await _state(Globals.GameState.WAVE_ACTIVE)  # a wave is cleared from the wave state
	var reported := []
	var listener := func(w, b): reported.append([w, b])
	Events.wave_completed.connect(listener)
	ResourceManager.current_energy = 300
	_wm.current_wave = 3
	_wm.is_spawning = false
	_wm._wave_complete_emitted = false
	_wm._check_wave_complete()
	Events.wave_completed.disconnect(listener)
	_check(reported == [[3, 45]], "clearing wave 3 reports a bonus of 45: %s" % [reported])
	_check(_energy() == 345 and _main.build_countdown == 15.0, "the bonus is paid and the 15 s build countdown starts (difficulty_fix F8)")
	_main.build_countdown = -1.0
	_wm.current_wave = 0

# ---- repair ----
func _check_repair() -> void:
	_reset_enemies()
	await _state(Globals.GameState.BUILD_PHASE)
	ResourceManager.current_energy = 500
	var t = _tower()
	_check(t.get_repair_cost() == 0 and _tm.repair_status(t) == "full_health", "a healthy tower has nothing to repair")
	t.take_tower_damage(50.0)
	_check(t.get_repair_cost() == 15, "50%% damaged, paid 100: repair costs 30%% x 0.5 x 100 = 15 (got %d)" % t.get_repair_cost())
	var repaired := []
	var listener := func(tw, cost): repaired.append(cost)
	Events.tower_repaired.connect(listener)
	await _state(Globals.GameState.WAVE_ACTIVE)
	var wave_energy := _energy()  # passive income ticks during a wave, so compare against this, not a fixed number
	_check(_tm.repair_status(t) == "not_build_phase" and not _tm.repair_tower(t) and _energy() >= wave_energy and t.tower_health == 50.0, "no repairs during a wave")
	await _state(Globals.GameState.BUILD_PHASE)
	var before_repair := _energy()
	_check(_tm.repair_tower(t), "repair works in the build phase")
	_check(before_repair - _energy() == 15 and t.tower_health == t.tower_max_health and repaired == [15], "it costs 15, restores full HP and announces it")
	var after_repair := _energy()
	_check(_tm.repair_status(t) == "full_health" and not _tm.repair_tower(t) and _energy() == after_repair, "repairing a healthy tower does nothing")
	Events.tower_repaired.disconnect(listener)

	var up = _tower("AA")   # paid 100 + 50 + 100 = 250, max HP 135
	up.take_tower_damage(108.0)  # 27 of 135 left: 80% missing
	_check(up.total_spent == 250 and up.get_repair_cost() == 60, "an upgraded tower repairs by everything paid: 30%% x 0.8 x 250 = 60 (got %d)" % up.get_repair_cost())
	up.set_disabled(true, 30.0)
	var before := _energy()
	_check(_tm.repair_status(up) == "tower_locked" and not _tm.repair_tower(up) and _energy() == before, "a locked tower can't be repaired")
	up.set_disabled(false)
	ResourceManager.current_energy = 5
	var shortfall := []
	var short_listener := func(cost, have): shortfall.append([cost, have])
	Events.energy_insufficient.connect(short_listener)
	_check(_tm.repair_status(up) == "too_expensive" and not _tm.repair_tower(up) and _energy() == 5 and shortfall == [[60, 5]], "without enough Energy it is refused and the player is told")
	Events.energy_insufficient.disconnect(short_listener)
	ResourceManager.current_energy = 500

	# the floating panel
	_tm.select_tower(up)
	var panel = _main.tower_info_panel
	_check(panel.repair_button.visible and panel.repair_button.text == "REPAIR  -60 ENERGY" and not panel.repair_button.disabled, "the panel offers the repair and its price")
	await _state(Globals.GameState.WAVE_ACTIVE)
	panel.refresh()
	_check(panel.repair_button.disabled and "BETWEEN WAVES" in panel.repair_button.text, "during a wave the button says repairs are for between waves")
	await _state(Globals.GameState.BUILD_PHASE)
	panel.refresh()
	for pressed in [true, false]:
		var ev := InputEventAction.new()
		ev.action = &"repair"
		ev.pressed = pressed
		Input.parse_input_event(ev)
	await get_tree().process_frame
	_check(up.tower_health == up.tower_max_health and _energy() == 440, "the R key repairs the selected tower (-60)")
	_check(not panel.repair_button.visible, "the repair button disappears once the tower is healthy")
	_tm.deselect_tower()
	_clear_towers()

# ---- Emergency Overclock ----
func _check_overclock() -> void:
	await _state(Globals.GameState.BUILD_PHASE)
	_oc.reset()
	_wm.current_wave = 0
	_check(not _oc.is_unlocked() and not _oc.can_use() and not _main.overclock_button.visible, "Level 1: Overclock is locked before wave 3 (and its button hidden)")
	_wm.current_wave = 3
	await get_tree().process_frame
	_check(_oc.is_unlocked() and _main.overclock_button.visible, "it unlocks at wave 3")
	_wm.current_wave = 0
	Globals.current_level = 1
	_check(_oc.is_unlocked(), "from Level 2 on it is available from the start")
	Globals.current_level = 0
	_wm.current_wave = 3
	var prompted := []
	var msg := func(text, _d): prompted.append(text)
	Events.show_message.connect(msg)
	_main._on_wave_started(3)
	Events.show_message.disconnect(msg)
	_check(prompted.size() == 1 and "OVERCLOCK UNLOCKED" in prompted[0], "reaching wave 3 on Level 1 shows the tutorial prompt")

	# using it
	ResourceManager.current_energy = 400
	var used := []
	var listener := func(e): used.append(e)
	Events.overclock_used.connect(listener)
	_check(_oc.use(), "Overclock can be used")
	_check(_energy() == 550 and is_equal_approx(_oc.system_load, 50.0) and used == [150], "+150 Energy, +50 System Load")
	_check(is_equal_approx(_oc.cooldown_left, 15.0) and not _oc.can_use() and not _oc.use(), "then a 15 s cooldown blocks a second use")
	Events.overclock_used.disconnect(listener)
	await get_tree().process_frame
	_check(_main.overclock_button.disabled, "its button is greyed out while cooling down")
	_oc.reset()
	ResourceManager.lost_to_cap = 0
	ResourceManager.current_energy = 950
	_oc.use()
	_check(_energy() == 1000 and ResourceManager.lost_to_cap == 100, "the +150 is capped too: 950 -> 1000, 100 lost")

	# decay
	_oc.reset()
	_oc.system_load = 50.0
	await _state(Globals.GameState.WAVE_ACTIVE)
	_oc._process(10.0)
	_check(absf(_oc.system_load - 40.0) < 0.5, "System Load decays 1 per second during a wave (50 -> 40 over 10 s): %.1f" % _oc.system_load)
	await _state(Globals.GameState.BUILD_PHASE)
	_oc._process(10.0)
	_check(absf(_oc.system_load - 20.0) < 0.5, "and 2 per second in the build phase (40 -> 20): %.1f" % _oc.system_load)

	# thresholds and what they do
	var t = _tower()
	for spec in [[59.0, 1.0, true], [60.0, 1.25, true], [89.0, 1.25, true], [90.0, 1.5, false], [100.0, 1.5, false]]:
		_oc.system_load = spec[0]
		_check(_oc.attack_interval_mult() == spec[1] and _oc.passive_allowed() == spec[2],
			"load %d: towers attack at x%s interval, passive income %s" % [spec[0], spec[1], "on" if spec[2] else "off"])
	for spec in [[0.0, 0.5], [60.0, 0.6], [90.0, 1.0 - 0.5 / 1.5]]:
		_oc.system_load = spec[0]
		t.cooldown_timer = 1.0
		t._process(0.5)
		_check(is_equal_approx(t.cooldown_timer, spec[1]), "at load %d a 1 s cooldown is %.2f s after half a second" % [spec[0], spec[1]])

	# crash
	_oc.reset()
	await _state(Globals.GameState.BUILD_PHASE)
	_oc.system_load = 50.0
	ResourceManager.current_energy = 100
	var crashed := []
	var crash_listener := func(): crashed.append(true)
	Events.system_crashed.connect(crash_listener)
	_check(_oc.use() and crashed.size() == 1, "using it at load 50 reaches 100: a System Crash")
	Events.system_crashed.disconnect(crash_listener)
	_check(_energy() == 250 and is_equal_approx(_oc.system_load, 60.0), "the Energy is still paid and the load resets to 60")
	_check(_oc.towers_paused() and _oc.arduino_damage_mult() == 2.0, "towers are paused and the Arduino takes double damage")
	_main.base_health = 100
	_main._on_enemy_reached_base(0, 5)
	_check(_main.base_health == 90, "a 5 damage leak does 10 during the crash")
	# towers are offline for 3 s: CombatManager doesn't ask them to attack
	var target = _enemy()
	target.global_position = t.global_position + Vector2(100, 0)
	t.cooldown_timer = 0.0
	var combat = _main.get_node("Managers/CombatManager")
	combat._physics_process(0.0)
	_check(t.cooldown_timer == 0.0, "no tower attacks during the crash")
	_oc._process(3.1)
	_check(not _oc.towers_paused() and _oc.arduino_damage_mult() == 2.0, "after 3 s the towers are back but the Arduino is still exposed")
	combat._physics_process(0.0)
	_check(t.cooldown_timer > 0.0, "and they attack again")
	_main.base_health = 100
	_oc._process(8.0)
	_main._on_enemy_reached_base(0, 5)
	_check(_oc.arduino_damage_mult() == 1.0 and _main.base_health == 95, "after 10 s damage is normal again")
	_reset_enemies()
	_clear_towers()

	# keys and states
	_oc.reset()
	ResourceManager.current_energy = 100
	for pressed in [true, false]:
		var ev := InputEventAction.new()
		ev.action = &"overclock"
		ev.pressed = pressed
		Input.parse_input_event(ev)
	await get_tree().process_frame
	_check(_energy() == 250 and _oc.system_load >= 49.0, "the O key uses it")
	_oc.reset()
	await _state(Globals.GameState.PAUSED)
	_check(not _oc.can_use() and not _oc.use(), "it can't be used while paused")
	await _state(Globals.GameState.BUILD_PHASE)
	_oc.system_load = 40.0
	_oc.cooldown_left = 5.0
	_main.overclock_mgr.reset()
	_check(_oc.system_load == 0.0 and _oc.cooldown_left == 0.0 and not _oc.towers_paused(), "reset clears load, cooldown and crash")

# ---- per-level start ----
func _check_levels() -> void:
	for i in 5:
		await _state(Globals.GameState.MAIN_MENU)
		_oc.system_load = 33.0
		Events.level_selected.emit(i)
		await get_tree().process_frame
		await get_tree().process_frame
		_check(_energy() == START_ENERGY[i] and _main.base_health == 100 and _main.max_base_health == 100 and _oc.system_load == 0.0,
			"%s starts with %d Energy, 100 Arduino HP and no System Load" % [Globals.LEVEL_DATA[i].name, START_ENERGY[i]])
	Globals.current_level = 0
