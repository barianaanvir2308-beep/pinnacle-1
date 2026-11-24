class_name BaseEnemy extends Node2D

var enemy_type: int
var health: float
var max_health: float
var speed: float
var base_damage: int
var reward: int

var path_points: Array[Vector2] = []
var current_path_index: int = 0
var is_alive: bool = true

var slow_factor: float = 1.0
var slow_timer: float = 0.0
var stun_timer: float = 0.0       # while > 0 the enemy cannot move
var stun_immune: bool = false     # bosses: stuns slow them 50% instead
var stun_vulnerability: float = 1.0  # damage multiplier while stunned (EMP Overload)
var revealed_timer: float = 0.0   # while > 0 towers can target it even if it is hidden
var is_boss: bool = false         # set by the Boss virus once it exists; towers read it for boss bonuses
var is_visible_to_towers: bool = true  # a Stealth virus will set this false until it is revealed
var health_mult: float = 1.0      # the wave's multipliers, kept so a spread Worm can copy them
var speed_mult: float = 1.0
var _aura_buffed: bool = false    # inside a Spyware's aura: +20% speed, -20% damage taken
var _aura_check_time: float = 0.0

const CONTACT_TILES: float = 1.05  # "within 1 tile" of a module (a tile beside the path is exactly 1 tile away)

var time_alive: float = 0.0
var glitch_offset: Vector2 = Vector2.ZERO

func _ready() -> void:
	add_to_group("enemies")
	if Globals.ENEMY_DATA.has(enemy_type):
		var data = Globals.ENEMY_DATA[enemy_type]
		max_health = data.get("health", 10.0)
		health = max_health
		speed = data.get("speed", 1.0)
		base_damage = data.get("base_damage", 1)
		reward = data.get("reward", 5)
	_setup_visuals()

func configure(type: int, p_health_mult: float, p_speed_mult: float) -> void:
	enemy_type = type
	health_mult = p_health_mult
	speed_mult = p_speed_mult
	if Globals.ENEMY_DATA.has(enemy_type):
		var data = Globals.ENEMY_DATA[enemy_type]
		max_health = data.get("health", 10.0) * p_health_mult
		health = max_health
		speed = data.get("speed", 1.0) * p_speed_mult
		base_damage = data.get("base_damage", 1)
		reward = data.get("reward", 5)
	queue_redraw()

func set_path(points: Array[Vector2]) -> void:
	path_points = points
	if path_points.size() > 0:
		position = path_points[0]
		current_path_index = 1

var sprite: Sprite2D

func _setup_visuals() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite = Sprite2D.new()
	sprite.scale = Vector2.ONE * Globals.PIXEL_SCALE
	sprite.show_behind_parent = true  # keep the health bar on top
	add_child(sprite)

# Loads res://assets/sprites/pixel/enemies/<art_name>.png (a horizontal strip when frames > 1)
func _load_art(art_name: String, frames: int = 1) -> void:
	sprite.texture = load("res://assets/sprites/pixel/enemies/%s.png" % art_name)
	sprite.hframes = frames

func _process(delta: float) -> void:
	if not is_alive or path_points.is_empty():
		return
		
	time_alive += delta
	_update_aura(delta)
	
	if slow_timer > 0.0:
		slow_timer -= delta
		if slow_timer <= 0.0:
			slow_factor = 1.0
			
	var stunned := _tick_status(delta)
	
	if not stunned and current_path_index < path_points.size():
		var target_pos = path_points[current_path_index]
		var move_dir = (target_pos - position).normalized()
		var dist = position.distance_to(target_pos)
		
		var move_dist = speed * Globals.TILE_SIZE * _speed_factor() * delta
		
		if dist <= move_dist:
			position = target_pos
			current_path_index += 1
			if current_path_index >= path_points.size():
				reach_base()
		else:
			position += move_dir * move_dist
			if is_instance_valid(sprite):
				sprite.rotation = lerp_angle(sprite.rotation, move_dir.angle() + PI/2, delta * 10.0)
			
	# Glitch effect update at low health
	if health / max_health < 0.3 and randf() < 0.2:
		glitch_offset = Vector2(randf_range(-3, 3), randf_range(-3, 3))
	else:
		glitch_offset = Vector2.ZERO
		
	if is_instance_valid(sprite):
		sprite.position = glitch_offset
	
	_update_status_tint()
	queue_redraw()

# Stunned enemies are tinted icy blue, enemies inside a Spyware aura a faint cyan
func _update_status_tint() -> void:
	var tint := Color.WHITE
	if stun_timer > 0.0:
		tint = Color(0.55, 0.8, 1.0)
	elif _aura_buffed:
		tint = Color(0.75, 1.0, 1.0)
	modulate = Color(tint.r, tint.g, tint.b, modulate.a)

# Walking pace: slowed by EMPs, sped up inside a Spyware aura
func _speed_factor() -> float:
	var aura_speed: float = Globals.ENEMY_DATA[Globals.EnemyType.SPYWARE].aura_speed
	return slow_factor * (aura_speed if _aura_buffed else 1.0)

# Is a Spyware (other than this enemy) close enough to buff it? Auras do not stack, and Spyware
# are not buffed themselves. Checked a few times a second.
func _update_aura(delta: float) -> void:
	_aura_check_time -= delta
	if _aura_check_time > 0.0:
		return
	_aura_check_time = 0.15
	_aura_buffed = false
	if enemy_type == Globals.EnemyType.SPYWARE:
		return
	var radius: float = Globals.ENEMY_DATA[Globals.EnemyType.SPYWARE].aura_radius * Globals.TILE_SIZE
	for spy in get_tree().get_nodes_in_group("spyware"):
		if is_instance_valid(spy) and spy.is_alive and global_position.distance_to(spy.global_position) <= radius:
			_aura_buffed = true
			return

# Towers ("modules") within a distance of this enemy, nearest first
func _modules_near(radius_px: float) -> Array:
	var found: Array = []
	for tower in get_tree().get_nodes_in_group("towers"):
		if is_instance_valid(tower) and not tower.is_queued_for_deletion() \
				and global_position.distance_to(tower.global_position) <= radius_px:
			found.append(tower)
	found.sort_custom(func(a, b): return global_position.distance_squared_to(a.global_position) < global_position.distance_squared_to(b.global_position))
	return found

# armor_pierce is set by the Data Spike, which ignores the Rootkit's armour
func take_damage(amount: float, _armor_pierce: bool = false) -> void:
	if not is_alive: return
	if stun_timer > 0.0:
		amount *= stun_vulnerability
	if _aura_buffed:
		amount *= Globals.ENEMY_DATA[Globals.EnemyType.SPYWARE].aura_damage_taken
	health -= amount
	if health <= 0:
		die()
	queue_redraw()

func die() -> void:
	is_alive = false
	Events.enemy_defeated.emit(enemy_type, reward, position)
	queue_free()

func reach_base() -> void:
	is_alive = false
	Events.enemy_reached_base.emit(enemy_type, base_damage)
	queue_free()

# Counts down stun and reveal timers. Returns true while the enemy is stunned (so it can't move this frame).
func _tick_status(delta: float) -> bool:
	if revealed_timer > 0.0:
		revealed_timer -= delta
	var stunned := stun_timer > 0.0
	if stunned:
		stun_timer -= delta
		if stun_timer <= 0.0:
			stun_vulnerability = 1.0
	return stunned

# Freezes the enemy in place. Bosses can't be stunned and are slowed 50% instead, unless force is set
# (Ion Storm stuns bosses). damage_mult makes it take extra damage while it is stunned.
func apply_stun(duration: float, damage_mult: float = 1.0, force: bool = false) -> void:
	if stun_immune and not force:
		apply_slow(0.5, duration)
		return
	stun_timer = maxf(stun_timer, duration)
	stun_vulnerability = maxf(stun_vulnerability, damage_mult)

# Lets towers target it for a while even if it is hidden (EMP Scrambler)
func reveal(duration: float) -> void:
	revealed_timer = maxf(revealed_timer, duration)

func is_stunned() -> bool:
	return stun_timer > 0.0

func apply_slow(factor: float, duration: float) -> void:
	if factor < slow_factor:
		slow_factor = factor
	slow_timer = duration

func get_path_progress() -> float:
	if path_points.size() < 2: return 0.0
	var total_segments = path_points.size() - 1
	var current_segment = max(0, current_path_index - 1)
	var progress_per_segment = 1.0 / total_segments
	
	var segment_progress = 0.0
	if current_path_index < path_points.size() and current_path_index > 0:
		var start_pos = path_points[current_path_index - 1]
		var end_pos = path_points[current_path_index]
		var dist_total = start_pos.distance_to(end_pos)
		var dist_current = start_pos.distance_to(position)
		if dist_total > 0:
			segment_progress = clamp(dist_current / dist_total, 0.0, 1.0)
			
	return (current_segment + segment_progress) * progress_per_segment



func _draw() -> void:
	var health_pct = health / max_health
	var bar_width = 40.0
	var bar_height = 4.0
	var bar_y = -44.0
	
	# Draw Health Bar Background
	draw_rect(Rect2(-bar_width / 2, bar_y, bar_width, bar_height), Color(0.1, 0.1, 0.1, 0.8))
	
	# Draw Health Bar Foreground
	var hp_color = Color(0.0, 1.0, 0.53) # Green
	if health_pct < 0.3:
		hp_color = Color(1.0, 0.2, 0.2) # Red
	elif health_pct < 0.6:
		hp_color = Color(1.0, 0.84, 0.0) # Yellow
		
	var current_bar_width = bar_width * health_pct
	if current_bar_width > 0:
		draw_rect(Rect2(-bar_width / 2, bar_y, current_bar_width, bar_height), hp_color)
