# check_balance.gd — Autoplay balance check (docs/difficulty_fix.md section 5)
# Run all levels: godot --headless --path . res://tools/checks/check_balance.tscn
# One level:      godot --headless --path . res://tools/checks/check_balance.tscn -- --level=3
# (levels are 1-5; run several in separate processes to go faster)
# Options after the "--": --level=N, --speed=N (Engine.time_scale, default 4), --good=F (worth-a-Cannon fraction, default 0.3), --bot=specialist|spammer|upgrader|controller, --detail
#
# A simple bot plays each level through all 10 waves, in one of four playstyles (--bot=NAME). None of them uses
# Overclock or abilities, and all of them repair damaged towers first:
#   specialist (default)  counter-builder: Data Spikes for Trojans/Rootkits, an EMP for Worm/DDoS waves (below)
#   spammer               Antivirus Cannons on every worthwhile tile, then Tier 1 (Path A) upgrades only
#   upgrader              at most 6 Cannons, everything else goes into Path A upgrades
#   controller            1-2 EMPs where lanes converge (upgraded on Path A), Cannons for the rest
# The specialist, in every build phase (including the countdowns before a wave):
#   1. repairs every damaged tower it can afford,
#   2. buys counters first (saving up for them if it has to):
#        - Data Spikes, about 1 per 3 Cannons (at least 1), from the first wave that has Trojans or Rootkits,
#        - 1 EMP when the coming wave has 6+ Worms or any DDoS Bot (on Level 1: from wave 3 on),
#      placed where lanes converge (route tiles weighted by how many spawn lanes share them),
#   3. buys Antivirus Cannons on the free tile that covers the most route tiles within 3.5 tiles,
#   4. once fewer than 3 "good" tiles are free, buys Path A upgrades (cheapest, lowest tier first; Data Spikes
#      first on levels with Rootkits).
# "Worth a Cannon" = the tile covers at least --good (default 0.3) of the best tile's route tiles. Among those the
# bot picks the tile that adds the most coverage not already held by other towers (see _marginal).
# Option --detail prints the per-type breakdown (leaks and the HP they cost, towers lost and by what, Trojan
# splits, lock-seconds) for every wave; without it, only for Level 1 waves 6-8, Levels 4/5 waves 5-7 and the wave
# the Arduino died in.
# Per wave it logs Energy at the start of the build phase, Energy spent, Energy left when the wave began,
# towers lost, lock-seconds, leaks and Arduino HP after the wave, then a PASS/FAIL line per level against
# the targets in section 5.2. Exits with code 1 if any level misses its target.
extends Node

const CANNON = Globals.TowerType.ANTIVIRUS_CANNON
const SPIKE = Globals.TowerType.DATA_SPIKE

const COVER_RADIUS_TILES: float = 3.5      # section 5.1: "covers the most path tiles within 3.5 tiles"
const EMP = Globals.TowerType.EMP_TOWER
const UPGRADER_MAX_TOWERS: int = 6          # upgrader: never more than this many towers
const CONTROLLER_CANNONS_FIRST: int = 3     # controller: Cannons bought before its first EMP
const CONTROLLER_UPGRADE_FROM: int = 6      # controller: EMP Path A upgrades start once it has this many Cannons
const SPIKES_PER_CANNON: int = 3           # about 1 Data Spike per 3 Cannons
const EMP_WORM_WAVE: int = 6               # an EMP is wanted when the coming wave has this many Worms ...
const EMP_LEVEL_1_FROM_WAVE: int = 3       # ... or, on Level 1, from this wave on
# Waves that get the per-type breakdown without --detail: level index -> waves
const DETAIL_WAVES: Dictionary = {0: [6, 7, 8], 3: [5, 6, 7], 4: [5, 6, 7]}
const POLL_SECONDS: float = 0.25           # how often the bot looks at the game (game time)
const WAVE_TIMEOUT_SECONDS: float = 400.0  # game time; a wave that takes longer is reported as STUCK
const LEVEL_WALL_TIMEOUT_MS: int = 25 * 60 * 1000

# Section 5.2: Arduino HP the bot must keep when it clears a level (L5: clear, or fail at wave 9-10)
const TARGET_HP: Array = [70, 50, 40, 20, -1]

var _main: Node
var _tm: Node
var _gsm: Node
var _wm: Node
var _board: Node

var _time_scale: float = 4.0
var _good_fraction: float = 0.3   # bot parameter: a tile is "worth a Cannon" at >= 30% of the best tile's route coverage (--good=0.3)

# per-level state
var _route: Array[Vector2i] = []   # route tiles from the spawn tiles in use to the Arduino
var _coverage: Dictionary = {}     # Vector2i -> route tiles within 3.5 tiles
var _min_good_cover: float = 0.0
var _path_count: Dictionary = {}   # route tile -> how many spawn lanes pass over it
var _level: int = 0
var _first_counter_wave: int = 999 # first wave (1-based) with Trojans or Rootkits
var _has_rootkits: bool = false
var _detail_all: bool = false
var _bot: String = "specialist"
var _rows: Array = []
var _row: Dictionary = {}
var _in_build: bool = false
var _spent_total: int = 0
var _last_wave_hp: int = 0
var _game_seconds: float = 0.0

func _ready() -> void:
	var only_level := -1
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--level="):
			only_level = int(arg.get_slice("=", 1)) - 1
		elif arg.begins_with("--speed="):
			_time_scale = float(arg.get_slice("=", 1))
		elif arg.begins_with("--bot="):
			_bot = arg.get_slice("=", 1)
		elif arg == "--detail":
			_detail_all = true
		elif arg.begins_with("--good="):
			_good_fraction = float(arg.get_slice("=", 1))
	seed(1)
	# No sound in balance runs. Randomizer sounds draw from the same random numbers as the game (Trojan Mini
	# placement), so with sound on, the results would depend on which sounds happened to play.
	Audio.enabled = false
	_main = load("res://scenes/main/Main.tscn").instantiate()
	add_child(_main)
	await get_tree().process_frame
	_tm = _main.get_node("Managers/TowerManager")
	_gsm = _main.get_node("Managers/GameStateManager")
	_wm = _main.get_node("Managers/WaveManager")
	_board = _main.get_node("GameBoard")
	Events.wave_started.connect(_on_wave_started)
	Events.wave_completed.connect(_on_wave_completed)
	Events.tower_destroyed.connect(_on_tower_destroyed)
	Events.enemy_reached_base.connect(_on_leak)
	Events.enemy_split.connect(func(_p, _c, _d): _row["splits"] = _row.get("splits", 0) + 1)
	Events.enemy_defeated.connect(func(type, _r, _p):
		if type == Globals.EnemyType.TROJAN_HORSE:
			_row["trojans_killed"] = _row.get("trojans_killed", 0) + 1)

	Engine.time_scale = _time_scale
	var summaries: Array[String] = []
	var failed := false
	var levels: Array = range(Globals.LEVEL_DATA.size()) if only_level < 0 else [only_level]
	for level in levels:
		var result: Dictionary = await _play_level(level)
		var line := _summary_line(level, result)
		summaries.append(line)
		print(line)
		print(_result_line(level, result))
		if not line.contains("PASS"):
			failed = true
	Engine.time_scale = 1.0
	print("")
	print("== check_balance summary (targets: docs/difficulty_fix.md 5.2) ==")
	for line in summaries:
		print(line)
	print("check_balance: %s" % ("FAIL" if failed else "PASS"))
	get_tree().quit(1 if failed else 0)

# =============================================================================
# Playing one level
# =============================================================================
func _play_level(level: int) -> Dictionary:
	var config: Dictionary = Globals.get_level_config(level)
	_rows.clear()
	_row = {}
	_in_build = false
	_spent_total = 0
	_game_seconds = 0.0
	_level = level
	_first_counter_wave = _first_wave_with(level, [Globals.EnemyType.TROJAN_HORSE, Globals.EnemyType.ROOTKIT])
	_has_rootkits = _level_has(level, [Globals.EnemyType.ROOTKIT])
	print("")
	print("== [%s] Level %d: %s (start %d Energy, Arduino %d HP, %d waves%s)" % [_bot, level + 1, config.name, config.starting_energy,
		config.get("arduino_hp", 100), config.waves.size(),
		", Data Spikes from wave %d" % _first_counter_wave if _bot == "specialist" and _first_counter_wave < 999 else ""])

	if _gsm.current_state != Globals.GameState.MAIN_MENU and _gsm.current_state != Globals.GameState.VICTORY \
			and _gsm.current_state != Globals.GameState.GAME_OVER:
		_gsm.change_state(Globals.GameState.MAIN_MENU)
	Events.level_selected.emit(level)
	await get_tree().process_frame
	await get_tree().process_frame
	_analyse_map()
	print("   map: %d buildable tiles, %d route tiles, best tile covers %d, a tile is worth a Cannon at coverage >= %.1f (%d tiles worth it at the start)" % [
		_coverage.size(), _route.size(), _best_cover(), _min_good_cover, _free_good_tiles()])

	var started_ms := Time.get_ticks_msec()
	var outcome := ""
	var first_wave := true
	while true:
		await get_tree().create_timer(POLL_SECONDS).timeout
		_game_seconds += POLL_SECONDS
		var state: int = _gsm.current_state
		if state == Globals.GameState.VICTORY:
			outcome = "CLEARED"
			break
		if state == Globals.GameState.GAME_OVER:
			outcome = "FAILED"
			break
		if Time.get_ticks_msec() - started_ms > LEVEL_WALL_TIMEOUT_MS:
			outcome = "TIMEOUT"
			break
		if state == Globals.GameState.BUILD_PHASE:
			if not _in_build:
				_begin_build()
			while _bot_act() > 0:
				pass
			if first_wave:
				first_wave = false
				_main._start_next_wave()  # nothing starts the first wave by itself: the player presses Space
				_wave_began = _game_seconds
		elif state == Globals.GameState.WAVE_ACTIVE:
			_in_build = false
		# a wave that never ends (game time) is a stuck game
		if state == Globals.GameState.WAVE_ACTIVE and _game_seconds - _wave_began > WAVE_TIMEOUT_SECONDS:
			outcome = "STUCK"
			break
	if outcome == "FAILED" and not _row.is_empty():
		_row["hp"] = 0
		_row["died"] = true
		_print_detail(_row, _row.get("wave", _wm.current_wave), true)
		_rows.append(_row.duplicate())
	var hp: int = _main.base_health
	return {
		"outcome": outcome, "hp": hp, "max_hp": _main.max_base_health, "wave": _wm.current_wave,
		"towers": _tm.placed_towers.size(), "spent": _spent_total, "game_seconds": _game_seconds,
		"real_seconds": (Time.get_ticks_msec() - started_ms) / 1000.0,
	}

var _wave_began: float = 0.0

func _first_wave_with(level: int, types: Array) -> int:
	var waves := Globals.get_level_waves(level)
	for i in waves.size():
		for group in waves[i].get("enemies", []):
			if types.has(group.get("type")):
				return i + 1
	return 999

func _count_in_wave(level: int, wave: int, type: int) -> int:
	var waves := Globals.get_level_waves(level)
	if wave < 1 or wave > waves.size():
		return 0
	var n := 0
	for group in waves[wave - 1].get("enemies", []):
		if group.get("type") == type:
			n += group.get("count", 0)
	return n

func _level_has(level: int, types: Array) -> bool:
	for wave in Globals.get_level_waves(level):
		for group in wave.get("enemies", []):
			if types.has(group.get("type")):
				return true
	return false

# =============================================================================
# Per-wave log
# =============================================================================
func _process(delta: float) -> void:
	for tower in get_tree().get_nodes_in_group("towers"):
		if is_instance_valid(tower) and tower.is_tower_disabled:
			_row["lock_s"] = _row.get("lock_s", 0.0) + delta

func _begin_build() -> void:
	_in_build = true
	_row = {"wave": _wm.current_wave + 1, "e_build": ResourceManager.current_energy, "spent": 0, "lost": 0, "leaks": 0, "lock_s": 0.0}

func _type_name(type: int) -> String:
	return Globals.ENEMY_DATA[type].name

# A Arduino hit: counted per virus type, with the HP it cost (no Overclock, so damage is what the virus is worth)
func _on_leak(type: int, damage: int) -> void:
	_row["leaks"] = _row.get("leaks", 0) + 1
	var by: Dictionary = _row.get("leak_by", {})
	var entry: Dictionary = by.get(type, {"n": 0, "hp": 0})
	entry.n += 1
	entry.hp += damage
	by[type] = entry
	_row["leak_by"] = by

# A tower died. The killer is the nearest Worm or Ransomware within 2 tiles (the one that most likely landed
# the last bite or lock), else "unknown".
func _on_tower_destroyed(tower_type: int, grid_pos: Vector2i) -> void:
	_row["lost"] = _row.get("lost", 0) + 1
	var at := Globals.grid_to_world(grid_pos)
	var killer := "unknown"
	var best := Globals.TILE_SIZE * 2.0
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e) or not e.is_alive:
			continue
		if e.enemy_type != Globals.EnemyType.WORM and e.enemy_type != Globals.EnemyType.RANSOMWARE:
			continue
		var d: float = e.global_position.distance_to(at)
		if d < best:
			best = d
			killer = _type_name(e.enemy_type) + (" clone" if "is_clone" in e and e.is_clone else "")
	var by: Dictionary = _row.get("lost_by", {})
	var label := "%s (%s)" % [Globals.TOWER_DATA[tower_type].name, killer]
	by[label] = by.get(label, 0) + 1
	_row["lost_by"] = by

func _on_wave_started(wave_number: int) -> void:
	_wave_began = _game_seconds
	if _row.is_empty() or _row.get("wave", -1) != wave_number:
		_begin_build()
		_row["wave"] = wave_number
	_row["e_left"] = ResourceManager.current_energy
	_row["towers_at_start"] = _tm.placed_towers.size()
	_row["trojans"] = _count_in_wave(_level, wave_number, Globals.EnemyType.TROJAN_HORSE)
	_row["spikes"] = _count_type(SPIKE)
	_row["emps"] = _count_type(EMP)

func _on_wave_completed(wave_number: int, _bonus: int) -> void:
	_row["hp"] = _main.base_health
	_row["towers_end"] = _tm.placed_towers.size()
	_rows.append(_row.duplicate())
	var r := _row
	print("   wave %2d  E@build %4d  spent %4d  left %4d | towers %2d  lost %d  lock %5.1fs  leaks %2d | Arduino %3d HP" % [
		wave_number, r.get("e_build", 0), r.get("spent", 0), r.get("e_left", 0), r.get("towers_at_start", 0),
		r.get("lost", 0), r.get("lock_s", 0.0), r.get("leaks", 0), r.get("hp", 0)])
	if _detail_all or DETAIL_WAVES.get(_level, []).has(wave_number):
		_print_detail(r, wave_number, false)
	_row = {}
	_in_build = false

# Per-type breakdown of one wave
func _print_detail(r: Dictionary, wave_number: int, died: bool) -> void:
	var leaks_text := "none"
	var by: Dictionary = r.get("leak_by", {})
	if not by.is_empty():
		var parts: Array[String] = []
		for type in by:
			parts.append("%s x%d (-%d HP)" % [_type_name(type), by[type].n, by[type].hp])
		leaks_text = ", ".join(parts)
	var lost_text := "none"
	var lost_by: Dictionary = r.get("lost_by", {})
	if not lost_by.is_empty():
		var parts: Array[String] = []
		for label in lost_by:
			parts.append("%s x%d" % [label, lost_by[label]])
		lost_text = ", ".join(parts)
	var trojans: int = r.get("trojans", 0)
	var splits: int = r.get("splits", 0)
	var killed: int = r.get("trojans_killed", 0)
	var trojan_text := "no Trojans"
	if trojans > 0:
		trojan_text = "%d Trojan(s): %d split, %d killed before splitting, %d still on the field or leaked" % [
			trojans, splits, killed, maxi(0, trojans - splits - killed)]
	print("      >> wave %d%s: leaks by type: %s | towers lost: %s | %s | lock %.1fs | counters at start: %d Spike, %d EMP" % [
		wave_number, " (ARDUINO DESTROYED)" if died else "", leaks_text, lost_text, trojan_text, r.get("lock_s", 0.0),
		r.get("spikes", 0), r.get("emps", 0)])

func _count_type(type: int) -> int:
	var n := 0
	for t in _tm.placed_towers.values():
		if is_instance_valid(t) and t.tower_type == type:
			n += 1
	return n

func _summary_line(level: int, res: Dictionary) -> String:
	var name: String = Globals.get_level_config(level).name
	var target: int = TARGET_HP[level]
	var pass_ok := false
	var target_text := ""
	if level == 4:
		target_text = "clears, or fails at wave 9-10"
		pass_ok = res.outcome == "CLEARED" or (res.outcome == "FAILED" and res.wave >= 9)
	else:
		target_text = "clears with >= %d HP" % target
		pass_ok = res.outcome == "CLEARED" and res.hp >= target
	var totals := _totals()
	return "[%s] L%d %-11s %-7s Arduino %3d/%d HP  (reached wave %d, %d towers, spent %d, lost %d towers, %d lock-s, %d leaks | game %.0fs, real %.0fs) target: %s  -> %s" % [
		_bot, level + 1, name, res.outcome, res.hp, res.max_hp, res.wave, res.towers, res.spent, totals.lost, int(totals.lock_s), totals.leaks,
		res.game_seconds, res.real_seconds, target_text, "PASS" if pass_ok else "FAIL"]

# One line a script can read (tools/balance_matrix.py): outcome, HP, wave reached and DDoS leaks per swarm wave
func _result_line(level: int, res: Dictionary) -> String:
	var ddos: Array[String] = []
	for r in _rows:
		if _count_in_wave(level, r.get("wave", 0), Globals.EnemyType.DDOS_BOT) > 0:
			var n: int = r.get("leak_by", {}).get(Globals.EnemyType.DDOS_BOT, {"n": 0}).n
			ddos.append("%d:%d" % [r.get("wave", 0), n])
	return "RESULT level=%d bot=%s outcome=%s hp=%d wave=%d ddos=%s" % [
		level + 1, _bot, res.outcome, res.hp, res.wave, ",".join(ddos) if not ddos.is_empty() else "-"]

func _totals() -> Dictionary:
	var t := {"lost": 0, "lock_s": 0.0, "leaks": 0}
	for r in _rows:
		t.lost += r.get("lost", 0)
		t.lock_s += r.get("lock_s", 0.0)
		t.leaks += r.get("leaks", 0)
	return t

# =============================================================================
# The reference player
# =============================================================================

# Finds the route tiles (from the spawn tiles this level uses to the Arduino) and scores every buildable tile
func _analyse_map() -> void:
	var route: Dictionary = {}
	_route.clear()
	var arduino: Vector2i = _board.get_arduino_position()
	_path_count.clear()
	for spawn in _board.get_spawn_points():
		var lane: Dictionary = {}
		for world_pos in _board.find_path(spawn, arduino):
			lane[Globals.world_to_grid(world_pos)] = true
		for cell in lane:
			route[cell] = true
			_path_count[cell] = _path_count.get(cell, 0) + 1
	_route.assign(route.keys())
	_coverage.clear()
	for y in Globals.GRID_HEIGHT:
		for x in Globals.GRID_WIDTH:
			var cell := Vector2i(x, y)
			if Globals.get_cell_type(cell) != Globals.CellType.BUILDABLE:
				continue
			var n := 0
			for r in route:
				if Vector2(cell - r).length() <= COVER_RADIUS_TILES:
					n += 1
			_coverage[cell] = n
	_min_good_cover = _best_cover() * _good_fraction

func _best_cover() -> int:
	var best := 0
	for cell in _coverage:
		best = maxi(best, _coverage[cell])
	return best

# Route tiles within 3.5 tiles of a cell
func _covered_by(cell: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for r in _route:
		if Vector2(cell - r).length() <= COVER_RADIUS_TILES:
			out.append(r)
	return out

# Coverage a new tower on this cell would add: each route tile counts 1 / (1 + towers already covering it),
# so the second and third tower prefer parts of the route that are still thinly defended
func _marginal(cell: Vector2i, held: Dictionary) -> float:
	var total := 0.0
	for r in _covered_by(cell):
		total += 1.0 / (1.0 + held.get(r, 0))
	return total

# How many towers already cover each route tile
func _held_coverage() -> Dictionary:
	var held: Dictionary = {}
	for cell in _tm.placed_towers:
		for r in _covered_by(cell):
			held[r] = held.get(r, 0) + 1
	return held

# The free buildable tile that adds the most coverage, or (-1, -1). With worth_only, only tiles that are worth a
# Cannon (raw coverage at least the --good share of the best tile's).
func _best_free_tile(worth_only: bool) -> Vector2i:
	var held := _held_coverage()
	var best := Vector2i(-1, -1)
	var best_score := 0.0
	for cell in _coverage:
		if _tm.placed_towers.has(cell):
			continue
		if worth_only and _coverage[cell] < _min_good_cover:
			continue
		var score := _marginal(cell, held)
		if score > best_score:
			best_score = score
			best = cell
	return best

# Free tiles that are worth a Cannon
func _free_good_tiles() -> int:
	var n := 0
	for cell in _coverage:
		if not _tm.placed_towers.has(cell) and _coverage[cell] >= _min_good_cover:
			n += 1
	return n

func _spend(before: int) -> void:
	var cost := before - ResourceManager.current_energy
	_spent_total += cost
	_row["spent"] = _row.get("spent", 0) + cost

# One pass of the bot's shopping. Returns how many things it bought or repaired.
func _bot_act() -> int:
	var done := 0
	# 1. repairs
	for tower in _tm.placed_towers.values():
		if is_instance_valid(tower) and _tm.repair_status(tower) == "ok":
			var before: int = ResourceManager.current_energy
			if _tm.repair_tower(tower):
				_spend(before)
				done += 1
	match _bot:
		"spammer":
			return _act_spammer(done)
		"upgrader":
			return _act_upgrader(done)
		"controller":
			return _act_controller(done)
	return _act_specialist(done)

# ---- specialist: counters for the coming wave, then Cannons, then upgrades ----
func _act_specialist(done: int) -> int:
	# 2. counters: Data Spikes (about 1 per 3 Cannons) and an EMP when the coming wave needs one. The bot saves up for
	# them rather than spending on Cannons first.
	var upcoming: int = _wm.current_wave + 1
	var cannons := _count_type(CANNON)
	if upcoming >= _first_counter_wave and _count_type(SPIKE) < maxi(1, cannons / SPIKES_PER_CANNON):
		var bought := _buy_counter(SPIKE)
		if bought > 0 or _can_save_for(SPIKE):
			return done + bought
	if _emp_wanted(upcoming) and _count_type(EMP) == 0:
		var bought := _buy_counter(EMP)
		if bought > 0 or _can_save_for(EMP):
			return done + bought
	# 3. Cannons while there are 3 or more good tiles left
	if _free_good_tiles() >= 3:
		var cell := _best_free_tile(true)
		if cell.x >= 0 and _tm.can_place_tower(cell, CANNON):
			var before: int = ResourceManager.current_energy
			if _tm.place_tower(cell, CANNON):
				_spend(before)
				done += 1
		return done
	# 4. otherwise Path A upgrades (Data Spikes first on levels with Rootkits)
	var pick: Node = _cheapest_upgrade(true) if _has_rootkits else null
	if pick == null:
		pick = _cheapest_upgrade(false)
	if pick != null:
		var before: int = ResourceManager.current_energy
		if _tm.upgrade_tower(pick, "A"):
			_spend(before)
			done += 1
	return done

# True if waiting is worth it: the build countdown left plus passive income will reach the price before the wave
# starts. If not, the bot spends on Cannons instead of letting Energy sit idle through the wave.
func _can_save_for(type: int) -> bool:
	var time_left: float = maxf(_main.build_countdown, 0.0) + maxf(_main.wave_start_countdown, 0.0)
	return ResourceManager.current_energy + Globals.PASSIVE_ENERGY_RATE * time_left >= Globals.TOWER_DATA[type].cost

# An EMP is wanted for a wave with 6+ Worms or any DDoS Bot (Level 1: from wave 3 on)
func _emp_wanted(wave: int) -> bool:
	if _level == 0 and wave >= EMP_LEVEL_1_FROM_WAVE:
		return true
	return _count_in_wave(_level, wave, Globals.EnemyType.DDOS_BOT) > 0 \
		or _count_in_wave(_level, wave, Globals.EnemyType.WORM) >= EMP_WORM_WAVE

# Buys one counter tower on the tile where the most lanes converge. Returns 1 if bought, 0 otherwise (not
# affordable yet, or no free tile).
func _buy_counter(type: int) -> int:
	var cell := _best_convergence_tile(Globals.TOWER_DATA[type].range)
	if cell.x < 0 or not _tm.can_place_tower(cell, type):
		return 0
	var before: int = ResourceManager.current_energy
	if _tm.place_tower(cell, type):
		_spend(before)
		return 1
	return 0

# The free buildable tile whose range reaches the most route, counting a route tile once per lane sharing it,
# squared, so tiles where lanes merge win (on a single lane this is just coverage)
func _best_convergence_tile(range_tiles: float) -> Vector2i:
	var held := _held_coverage()
	var best := Vector2i(-1, -1)
	var best_score := 0.0
	for cell in _coverage:
		if _tm.placed_towers.has(cell):
			continue
		var score := 0.0
		for r in _route:
			if Vector2(cell - r).length() <= range_tiles:
				score += _path_count.get(r, 1) * _path_count.get(r, 1)
		score += _marginal(cell, held) * 0.001  # tiny tie-break: prefer thinly covered ground
		if score > best_score:
			best_score = score
			best = cell
	return best

# The tower with the cheapest next Path A tier (lowest tier first); only Data Spikes when spikes_only
func _cheapest_upgrade(spikes_only: bool) -> Node:
	var pick: Node = null
	var pick_key := Vector2i(999, 99999)
	for tower in _tm.placed_towers.values():
		if not is_instance_valid(tower) or tower.get_upgrade_status("A") != "ok":
			continue
		if spikes_only and tower.tower_type != SPIKE:
			continue
		var key := Vector2i(tower.path_tiers["A"], tower.get_upgrade_cost("A"))
		if key.x < pick_key.x or (key.x == pick_key.x and key.y < pick_key.y):
			pick = tower
			pick_key = key
	return pick

# ---- spammer: Cannons on every worthwhile tile, then Tier 1 (Path A) upgrades only ----
func _act_spammer(done: int) -> int:
	if _free_good_tiles() >= 1:
		return done + _buy_cannon()
	var pick: Node = null
	var pick_cost := 99999
	for tower in _tm.placed_towers.values():
		if is_instance_valid(tower) and tower.path_tiers["A"] == 0 and tower.get_upgrade_status("A") == "ok" \
				and tower.get_upgrade_cost("A") < pick_cost:
			pick = tower
			pick_cost = tower.get_upgrade_cost("A")
	return done + _upgrade(pick)

# ---- upgrader: at most 6 Cannons, then everything into Path A upgrades ----
func _act_upgrader(done: int) -> int:
	if _tm.placed_towers.size() < UPGRADER_MAX_TOWERS and _free_good_tiles() >= 1:
		return done + _buy_cannon()
	return done + _upgrade(_cheapest_upgrade(false))

# ---- controller: 1-2 EMPs where lanes converge (upgraded on Path A), Cannons for the rest ----
# Cannons come first: 3 Cannons, then the first EMP, then Cannons up to CONTROLLER_UPGRADE_FROM; after that each
# 2 more Cannons allow one more EMP tier, and a 2nd EMP comes with the 8th Cannon.
func _act_controller(done: int) -> int:
	var emps := _count_type(EMP)
	var cannons := _count_type(CANNON)
	var free_tile := _free_good_tiles() >= 1
	if cannons >= CONTROLLER_CANNONS_FIRST and emps < 1:
		var bought := _buy_counter(EMP)
		if bought > 0 or _can_save_for(EMP):
			return done + bought
	if cannons >= CONTROLLER_UPGRADE_FROM + 2 and emps < 2:
		var bought := _buy_counter(EMP)
		if bought > 0 or _can_save_for(EMP):
			return done + bought
	if cannons >= CONTROLLER_UPGRADE_FROM or not free_tile:
		var tiers_owned := 0
		for t in _tm.placed_towers.values():
			if is_instance_valid(t) and t.tower_type == EMP:
				tiers_owned += t.path_tiers["A"]
		if tiers_owned < (cannons - CONTROLLER_UPGRADE_FROM) / 2 + 1 or not free_tile:
			var emp := _cheapest_emp_upgrade()
			if emp != null:
				return done + _upgrade(emp)
			if _any_emp_upgrade_blocked_by_energy():
				return done
	if free_tile:
		return done + _buy_cannon()
	return done

# Buys a Cannon on the best worthwhile tile (1 if bought). When it can't be afforded yet the bot just waits.
func _buy_cannon() -> int:
	var cell := _best_free_tile(true)
	if cell.x < 0 or not _tm.can_place_tower(cell, CANNON):
		return 0
	var before: int = ResourceManager.current_energy
	if _tm.place_tower(cell, CANNON):
		_spend(before)
		return 1
	return 0

# Buys the next Path A tier of a tower (1 if bought)
func _upgrade(tower: Node) -> int:
	if tower == null:
		return 0
	var before: int = ResourceManager.current_energy
	if _tm.upgrade_tower(tower, "A"):
		_spend(before)
		return 1
	return 0

# The EMP with the cheapest Path A tier that can be bought right now (null if none)
func _cheapest_emp_upgrade() -> Node:
	var pick: Node = null
	var pick_key := Vector2i(999, 99999)
	for tower in _tm.placed_towers.values():
		if not is_instance_valid(tower) or tower.tower_type != EMP or tower.get_upgrade_status("A") != "ok":
			continue
		var key := Vector2i(tower.path_tiers["A"], tower.get_upgrade_cost("A"))
		if key.x < pick_key.x or (key.x == pick_key.x and key.y < pick_key.y):
			pick = tower
			pick_key = key
	return pick

# True if an EMP has another Path A tier that is only waiting for Energy that will arrive before the wave
func _any_emp_upgrade_blocked_by_energy() -> bool:
	var time_left: float = maxf(_main.build_countdown, 0.0) + maxf(_main.wave_start_countdown, 0.0)
	for tower in _tm.placed_towers.values():
		if is_instance_valid(tower) and tower.tower_type == EMP and tower.get_upgrade_status("A") == "too_expensive":
			if ResourceManager.current_energy + Globals.PASSIVE_ENERGY_RATE * time_left >= tower.get_upgrade_cost("A"):
				return true
	return false
