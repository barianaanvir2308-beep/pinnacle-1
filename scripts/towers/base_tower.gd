class_name BaseTower extends Node2D

@export var tower_type_export: int = 0
var tower_type: int
var damage: float = 0.0
var attack_range: float = 0.0
var attack_interval: float = 1.0  # seconds between shots
var target_mode: int = 0
var cooldown_timer: float = 0.0

var selected: bool = false
var tower_data: Dictionary = {}
var current_target: Node2D = null

# Tower health system
var tower_health: float = 100.0
var tower_max_health: float = 100.0
var is_tower_disabled: bool = false
var disable_timer: float = 0.0
var _disable_total: float = 1.0
var _disabled_flash: float = 0.0
var _mark_count: int = 0

# Upgrades (docs/scaling_and_upgrades.md): 2 paths x 3 tiers
var path_tiers: Dictionary = {"A": 0, "B": 0}
var chosen_path: String = ""      # set when a Tier 2 is bought; the other path is then capped at Tier 1
var total_spent: int = 0          # Energy actually paid: build cost + every tier bought
var tier_stats: Dictionary = {}   # merged tier values (pierce, splash, ...) for subclasses to read

# Art: the turret and pad follow the main path and tier (scaling_and_upgrades E.3)
const ART_DIR: String = "res://assets/sprites/pixel/"
const IDLE_FPS: float = 2.5  # Tier 3 turrets are 2-frame strips
var _art_name: String = ""
var _idle_time: float = 0.0

# Abilities (scaling_and_upgrades B6): at most one per tower, unlocked by a Tier 3
static var _next_order: int = 0
var placed_order: int = 0           # ability buttons and F-key slots follow placement order
var ability_cooldown_left: float = 0.0
var _fx_time: float = 0.0
var _fx_duration: float = 0.5
var _fx_radius: float = 0.0
var _fx_color: Color = Color.WHITE

var sprite: Sprite2D       # turret, rotates toward the target
var base_sprite: Sprite2D  # static pad under the turret

func _ready():
	if not Engine.is_editor_hint():
		tower_type = tower_type_export
		_init_from_data()
		add_to_group("towers")
		_setup_visuals()
		queue_redraw()

# Reads TOWER_DATA and puts the tower in its un-upgraded state
func _init_from_data() -> void:
	if Globals.TOWER_DATA.has(tower_type):
		tower_data = Globals.TOWER_DATA[tower_type]
	target_mode = tower_data.get("target_mode", Globals.TargetMode.FIRST)
	path_tiers = {"A": 0, "B": 0}
	chosen_path = ""
	total_spent = tower_data.get("cost", 100)
	if placed_order == 0:
		BaseTower._next_order += 1
		placed_order = BaseTower._next_order
	ability_cooldown_left = 0.0  # an ability is ready as soon as it is unlocked
	tower_max_health = 0.0  # so the first HP update starts at full health
	_apply_tier("", 0)

func _setup_visuals():
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	base_sprite = Sprite2D.new()
	base_sprite.scale = Vector2.ONE * Globals.PIXEL_SCALE
	base_sprite.show_behind_parent = true  # keep upgrade pips and health bar on top
	add_child(base_sprite)
	sprite = Sprite2D.new()
	sprite.scale = Vector2.ONE * Globals.PIXEL_SCALE
	sprite.show_behind_parent = true
	add_child(sprite)

# Remembers the art name and shows the sprites for the tower's current tier. Files live in
# res://assets/sprites/pixel/towers/: <name>_base.png and <name>_turret.png, plus optional
# <name>_turret_a1.png ... _b3.png and <name>_base_t3a.png / _t3b.png. A tier with no art
# of its own simply keeps the base look.
func _load_art(art_name: String) -> void:
	_art_name = art_name
	_refresh_art()

func _refresh_art() -> void:
	if _art_name == "" or sprite == null:
		return
	var suffix := get_art_suffix()
	var tier: int = path_tiers[_main_path()]
	sprite.texture = _pick_art("towers/%s_turret" % _art_name, suffix)
	# A strip of square frames (28 px) animates; a single frame stays still
	sprite.hframes = maxi(1, sprite.texture.get_width() / maxi(1, sprite.texture.get_height()))
	sprite.frame = 0
	base_sprite.texture = _pick_art("towers/%s_base" % _art_name, "_t3%s" % _main_path().to_lower() if tier >= Globals.MAX_TIER else "")

# The art file suffix for the tower's current look: "" (base), "_a1" ... "_b3"
func get_art_suffix() -> String:
	var path := _main_path()
	var tier: int = path_tiers[path]
	return "" if tier == 0 else "_%s%d" % [path.to_lower(), tier]

# The path whose look the tower shows: the chosen one, else the one with more tiers (A on a tie)
func _main_path() -> String:
	if chosen_path != "":
		return chosen_path
	return "A" if path_tiers["A"] >= path_tiers["B"] else "B"

func _pick_art(stem: String, suffix: String) -> Texture2D:
	if suffix != "":
		var tiered := ART_DIR + stem + suffix + ".png"
		if ResourceLoader.exists(tiered):
			return load(tiered)
	return load(ART_DIR + stem + ".png")

func _process(delta):
	if cooldown_timer > 0:
		cooldown_timer -= delta / _system_slowdown()  # System Load makes towers attack slower
	if ability_cooldown_left > 0.0:
		ability_cooldown_left = maxf(ability_cooldown_left - delta, 0.0)
	if _fx_time > 0.0:
		_fx_time -= delta
	_process_pending_shots(delta)
	if sprite != null and sprite.hframes > 1:
		_idle_time += delta
		sprite.frame = int(_idle_time * IDLE_FPS) % sprite.hframes
	
	# Disabled countdown
	if is_tower_disabled:
		disable_timer -= delta
		_disabled_flash += delta
		if is_instance_valid(sprite):
			sprite.modulate = Color(1.0, 0.5, 0.5)
			base_sprite.modulate = Color(1.0, 0.5, 0.5)
		if disable_timer <= 0.0:
			is_tower_disabled = false
			_disabled_flash = 0.0
			if is_instance_valid(sprite):
				sprite.modulate = Color.WHITE
				base_sprite.modulate = Color.WHITE
				
	# Rotate towards target
	if not is_tower_disabled and is_instance_valid(sprite) and is_instance_valid(current_target):
		var target_pos = current_target.global_position
		sprite.rotation = lerp_angle(sprite.rotation, (target_pos - global_position).angle() + PI/2, delta * 15.0)
	
	queue_redraw()

# System Load from Emergency Overclock: 1.0 normally, 1.25 / 1.5 when the load is high
var _overclock: Node = null
func _system_slowdown() -> float:
	if _overclock == null or not is_instance_valid(_overclock):
		_overclock = get_tree().get_first_node_in_group("overclock_manager")
	return _overclock.attack_interval_mult() if _overclock != null else 1.0

# Shots of a burst still to fire (Heuristic Engine): {"time": seconds until it fires, "target": enemy}
const BURST_GAP: float = 0.12
var _pending_shots: Array = []

func try_attack(enemies: Array):
	if cooldown_timer > 0 or is_tower_disabled:
		return
	
	var target = find_target(enemies)
	if target != null:
		current_target = target
		fire_at(target)
		if tower_data.has("fire_sound"): Audio.play_at(tower_data.fire_sound, global_position)
		cooldown_timer = attack_interval
	else:
		current_target = null

# The best target for the tower's targeting mode, or null
func find_target(enemies: Array) -> Node2D:
	var best := find_targets(enemies, 1)
	return best[0] if not best.is_empty() else null

# Up to `count` targets, best first (ties keep the order of the list, so waves stay deterministic)
func find_targets(enemies: Array, count: int) -> Array:
	var scored: Array = []
	for i in enemies.size():
		if _can_target(enemies[i]):
			scored.append([_target_score(enemies[i]), i, enemies[i]])
	scored.sort_custom(func(x, y): return x[0] > y[0] or (x[0] == y[0] and x[1] < y[1]))
	var out: Array = []
	for entry in scored.slice(0, count):
		out.append(entry[2])
	return out

# In range, and visible: hidden enemies (Spyware today, Stealth later) can only be hit when revealed
# by an EMP Scrambler pulse or when they come within this tower's stealth_detect_range (Cannon Deep Scan)
func _can_target(enemy) -> bool:
	if not is_instance_valid(enemy) or not is_in_range(enemy):
		return false
	if "is_visible_to_towers" in enemy and not enemy.is_visible_to_towers:
		if "revealed_timer" in enemy and enemy.revealed_timer > 0.0:
			return true
		var detect: float = tier_stats.get("stealth_detect_range", 0.0)
		return detect > 0.0 and global_position.distance_to(enemy.global_position) <= detect * Globals.TILE_SIZE
	return true

# Higher is better, according to the targeting mode
func _target_score(enemy) -> float:
	match target_mode:
		Globals.TargetMode.LAST:
			return -_progress(enemy)
		Globals.TargetMode.CLOSEST:
			return -global_position.distance_to(enemy.global_position)
		Globals.TargetMode.STRONGEST:
			return enemy.health if "health" in enemy else 0.0
	return _progress(enemy)  # FIRST: furthest along its path

func _progress(enemy) -> float:
	return enemy.get_path_progress() if enemy.has_method("get_path_progress") else 0.0

func is_in_range(enemy: Node2D) -> bool:
	var range_pixels = Globals.get_tower_range_pixels(attack_range)
	return global_position.distance_to(enemy.global_position) <= range_pixels

# Fires at the target. A burst (burst_count) fires the first shot now and the rest a moment apart.
func fire_at(target: Node2D):
	_launch(target)
	for i in range(1, int(tier_stats.get("burst_count", 1))):
		_pending_shots.append({"time": i * BURST_GAP, "target": target})

# Creates one projectile with this tower's tier effects (pierce, splash) on it
func _launch(target: Node2D) -> Node:
	var proj_scene = load("res://scenes/projectiles/Projectile.tscn")
	if proj_scene == null:
		return null
	var proj = proj_scene.instantiate()
	# Shots live in ProjectileContainer so they pause and hide with the game
	var parent = get_tree().get_first_node_in_group("projectile_container")
	if parent == null:
		parent = get_tree().current_scene
	parent.add_child(proj)
	proj.global_position = global_position
	proj.target = target
	proj.damage = get_damage_against(target)
	proj.tower_source = self
	proj.pierce = int(tier_stats.get("pierce", 0))
	proj.max_travel = Globals.get_tower_range_pixels(attack_range)
	proj.splash_factor = tier_stats.get("splash_factor", 0.0)
	proj.splash_radius_px = tier_stats.get("splash_radius", 0.0) * Globals.TILE_SIZE
	return proj

# Damage one shot does to this enemy. Towers with bonuses against some enemies override this.
func get_damage_against(_enemy: Node2D) -> float:
	return damage

# Called by a projectile after it has damaged an enemy (hit_damage = what the shot carried)
func on_projectile_hit(_enemy: Node2D, _hit_damage: float) -> void:
	pass

func _process_pending_shots(delta: float) -> void:
	if _pending_shots.is_empty():
		return
	if is_tower_disabled:
		_pending_shots.clear()
		return
	var due: Array = []
	var waiting: Array = []
	for shot in _pending_shots:
		shot.time -= delta
		(due if shot.time <= 0.0 else waiting).append(shot)
	_pending_shots = waiting
	for shot in due:
		var target = shot.target
		if not (is_instance_valid(target) and target.is_alive and is_in_range(target)):
			target = find_target(_live_enemies())  # the target died: carry on at the next one
		if target != null:
			_launch(target)

# =============================================================================
# UPGRADES
# =============================================================================

# Why a path can or can't be upgraded right now. "ok" means it can be bought.
# Others: no_tree, maxed, path_locked, tower_locked, too_expensive
func get_upgrade_status(path: String) -> String:
	if not Globals.UPGRADE_TREES.has(tower_type) or not path_tiers.has(path):
		return "no_tree"
	var next: int = path_tiers[path] + 1
	if next > Globals.MAX_TIER:
		return "maxed"
	# Crosspath: once a Tier 2 is bought, the other path can only reach Tier 1
	if chosen_path != "" and path != chosen_path and next > Globals.CROSSPATH_SECONDARY_MAX:
		return "path_locked"
	if is_tower_disabled:
		return "tower_locked"
	if not ResourceManager.can_afford(get_upgrade_cost(path)):
		return "too_expensive"
	return "ok"

func can_upgrade(path: String) -> bool:
	return get_upgrade_status(path) == "ok"

# Energy for the next tier on this path, or -1 if there isn't one
func get_upgrade_cost(path: String) -> int:
	if not path_tiers.has(path):
		return -1
	var tier = _tier_data(path, path_tiers[path] + 1)
	if tier.is_empty():
		return -1
	return int(round(tier.cost * get_cost_mult()))

# Discount on purchases. 1.0 until the Signal Booster (Discount Node) exists.
func get_cost_mult() -> float:
	return 1.0

# Buys the next tier of a path. Returns false (and spends nothing) if it can't.
func upgrade(path: String) -> bool:
	if not can_upgrade(path):
		return false
	var cost = get_upgrade_cost(path)
	if not ResourceManager.spend_energy(cost):
		return false
	total_spent += cost
	path_tiers[path] += 1
	if path_tiers[path] >= 2 and chosen_path == "":
		chosen_path = path
	_apply_tier(path, path_tiers[path])
	queue_redraw()
	return true

# Recomputes every stat from the base data plus the tiers owned. Tiers hold absolute
# values, so nothing is ever multiplied repeatedly. Subclasses override this to set
# behaviour flags from tier_stats, and call super first.
func _apply_tier(_path: String, _tier: int) -> void:
	tier_stats = _merged_tier_stats()
	damage = tier_stats.get("damage", tower_data.get("damage", 10.0))
	attack_range = tier_stats.get("range", tower_data.get("range", 2.0))
	attack_interval = tier_stats.get("attack_interval", tower_data.get("attack_interval", 1.0))
	_update_max_health()
	_refresh_art()

func _tier_data(path: String, tier: int) -> Dictionary:
	var tiers: Array = Globals.UPGRADE_TREES.get(tower_type, {}).get(path, {}).get("tiers", [])
	if tier < 1 or tier > tiers.size():
		return {}
	return tiers[tier - 1]

# The chosen path's current tier wins. The other path's tier only fills in keys
# the chosen path doesn't set (so Cannon A2 + B1 = damage 28, pierce 2, interval 0.7).
func _merged_tier_stats() -> Dictionary:
	var merged := {}
	for p in (["B", "A"] if chosen_path == "B" else ["A", "B"]):
		var tier: Dictionary = _tier_data(p, path_tiers[p]) if path_tiers[p] > 0 else {}
		for key in tier:
			if key != "name" and key != "cost" and key != "desc" and not merged.has(key):
				merged[key] = tier[key]
	return merged

# HP follows the best tier owned (rule B9) and keeps the same percentage of health
func _update_max_health() -> void:
	var highest: int = maxi(path_tiers["A"], path_tiers["B"])
	var new_max: float = tower_data.get("hp", tower_data.get("cost", 100)) * Globals.TIER_HP_MULT[highest]
	var pct: float = tower_health / tower_max_health if tower_max_health > 0.0 else 1.0
	tower_max_health = new_max
	tower_health = new_max * pct

# =============================================================================
# ABILITIES
# =============================================================================

func get_ability() -> Dictionary:
	return tier_stats.get("ability", {})

func has_ability() -> bool:
	return not get_ability().is_empty()

func can_use_ability() -> bool:
	return has_ability() and ability_cooldown_left <= 0.0 and not is_tower_disabled

# 0.0 = just used, 1.0 = ready
func get_ability_progress() -> float:
	var cooldown: float = get_ability().get("cooldown", 0.0)
	if cooldown <= 0.0:
		return 1.0
	return clampf(1.0 - ability_cooldown_left / cooldown, 0.0, 1.0)

# Fires the ability and starts its cooldown. A press with nothing to hit is refused
# without using the cooldown. Returns true when the ability went off.
func use_ability() -> bool:
	if not can_use_ability():
		return false
	var ability := get_ability()
	if not _ability_has_targets(ability):
		Events.show_message.emit("%s: %s" % [str(ability.get("name", "ABILITY")).to_upper(), _no_targets_text()], 1.5)
		return false
	ability_cooldown_left = ability.get("cooldown", 0.0)
	_perform_ability(ability)
	Events.ability_used.emit(self, ability.get("id", ""))
	queue_redraw()
	return true

# Overridden by towers that have an ability
func _ability_has_targets(_ability: Dictionary) -> bool:
	return true

func _perform_ability(_ability: Dictionary) -> void:
	pass

func _no_targets_text() -> String:
	return "NO VIRUSES IN RANGE"

func _live_enemies() -> Array:
	return get_tree().get_nodes_in_group("enemies").filter(func(e): return is_instance_valid(e) and e.is_alive)

func _enemies_in_range() -> Array:
	return _live_enemies().filter(func(e): return is_in_range(e))

# An expanding ring around the tower, as feedback that an ability went off
func _start_ring_fx(radius_px: float, color: Color, duration: float = 0.5) -> void:
	_fx_radius = radius_px
	_fx_color = color
	_fx_duration = duration
	_fx_time = duration

# Energy to restore the tower to full HP: 30% x (missing share of HP) x everything paid for it
func get_repair_cost() -> int:
	if tower_health >= tower_max_health:
		return 0
	var missing := 1.0 - tower_health / tower_max_health
	return ceili(Globals.REPAIR_COST_FACTOR * missing * total_spent)

func repair() -> void:
	tower_health = tower_max_health
	queue_redraw()

func get_total_spent() -> int:
	return total_spent

# Selling returns 60% of everything paid
func get_sell_value() -> int:
	return int(total_spent * Globals.SELL_REFUND_PERCENTAGE)


# =============================================================================
# TOWER DAMAGE / DISABLE SYSTEM
# =============================================================================

func take_tower_damage(amount: float) -> void:
	if tower_health <= 0:
		return
	tower_health -= amount
	if tower_health <= 0:
		tower_health = 0
		_on_tower_destroyed()
	queue_redraw()

func set_disabled(disabled: bool, duration: float = 3.0) -> void:
	is_tower_disabled = disabled
	if disabled:
		disable_timer = duration
		_disable_total = maxf(duration, 0.01)
		_disabled_flash = 0.0

# ---- Worms and Ransomware treat towers as "modules" ----
# Decoders and Boosters (priority) first, then by what the tower cost
func module_value() -> float:
	return tower_data.get("module_priority", 0) * 100000.0 + tower_data.get("cost", 0)

# How long a Ransomware lock lasts on this tower (the Scanner will halve it)
func get_lock_duration(base_duration: float) -> float:
	return base_duration

# Ransomware marks the module it is about to lock (a flashing target ring)
func add_mark() -> void:
	_mark_count += 1

func remove_mark() -> void:
	_mark_count = maxi(_mark_count - 1, 0)

func is_marked() -> bool:
	return _mark_count > 0

func _on_tower_destroyed() -> void:
	var grid_pos = Globals.world_to_grid(global_position)
	Events.tower_destroyed.emit(tower_type, grid_pos)
	queue_free()

# =============================================================================
# DRAW
# =============================================================================

func _draw():
	if _fx_time > 0.0:
		var progress := 1.0 - _fx_time / _fx_duration
		var alpha := 1.0 - progress
		draw_circle(Vector2.ZERO, _fx_radius * progress, Color(_fx_color, 0.10 * alpha))
		draw_arc(Vector2.ZERO, _fx_radius * progress, 0.0, TAU, 96, Color(_fx_color, alpha), 6.0)
	_draw_pips()
	
	# Tower health bar (only show when damaged)
	if tower_health < tower_max_health:
		var bar_w = 50.0
		var bar_h = 4.0
		var bar_y = 45.0
		var hp_pct = tower_health / tower_max_health
		draw_rect(Rect2(-bar_w / 2, bar_y, bar_w, bar_h), Color(0.1, 0.1, 0.1, 0.8))
		var hp_color = Color(0.2, 0.6, 1.0) if hp_pct > 0.3 else Color(1.0, 0.3, 0.0)
		draw_rect(Rect2(-bar_w / 2, bar_y, bar_w * hp_pct, bar_h), hp_color)
	
	# Locked: a countdown ring around the tile and a padlock
	if is_tower_disabled:
		var lock_color := Color(1.0, 0.0, 0.5)
		draw_arc(Vector2.ZERO, 56.0, 0.0, TAU, 48, Color(lock_color, 0.2), 4.0)
		draw_arc(Vector2.ZERO, 56.0, -PI / 2.0, -PI / 2.0 + TAU * clampf(disable_timer / _disable_total, 0.0, 1.0), 48, lock_color, 4.0)
		draw_rect(Rect2(-8, -62, 16, 12), lock_color)
		draw_arc(Vector2(0, -62), 5.5, PI, TAU, 12, lock_color, 3.0)
	# Marked by a Ransomware: a flashing target ring
	if is_marked():
		var flash := 0.55 + 0.45 * sin(Time.get_ticks_msec() / 90.0)
		draw_arc(Vector2.ZERO, 62.0, 0.0, TAU, 32, Color(1.0, 0.2, 0.2, flash), 4.0)
		for tick in [Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0)]:
			draw_line(tick * 52.0, tick * 70.0, Color(1.0, 0.2, 0.2, flash), 4.0)
	
	# Selection range ring
	if selected:
		var range_pixels = Globals.get_tower_range_pixels(attack_range)
		draw_circle(Vector2.ZERO, range_pixels, Color(0.0, 1.0, 0.53, 0.1))
		draw_arc(Vector2.ZERO, range_pixels, 0, TAU, 32, Color(0.0, 1.0, 0.53, 0.5), 2.0)

# Up to 3 pips in the main path's colour, plus one small pip for the other path's Tier 1
func _draw_pips() -> void:
	var main_path := _main_path()
	var other_path = "B" if main_path == "A" else "A"
	# Just above the tile edge, with a dark ring so they stand out from the sprite
	for i in range(path_tiers[main_path]):
		var pos := Vector2(-20 + i * 15, -68)
		draw_circle(pos, 6.5, Color(0.02, 0.02, 0.06))
		draw_circle(pos, 4.5, _path_color(main_path))
	if path_tiers[other_path] > 0:
		var pos := Vector2(25, -68)
		draw_circle(pos, 4.5, Color(0.02, 0.02, 0.06))
		draw_circle(pos, 2.8, _path_color(other_path))

# Path A uses the tower's own colour, path B the shared "utility" colour
func _path_color(path: String) -> Color:
	return tower_data.get("color", Color.WHITE) if path == "A" else Globals.PATH_B_COLOR

func set_selected(is_selected: bool):
	selected = is_selected
	queue_redraw()

func setup(type: int, _grid_pos: Vector2i):
	tower_type = type
	tower_type_export = type
	_init_from_data()
	queue_redraw()
