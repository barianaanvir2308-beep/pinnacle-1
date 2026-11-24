class_name Projectile extends Node2D

const HIT_RADIUS_PX: float = 36.0  # how close a piercing shot must pass to hit another virus

var target: Node2D = null
var damage: float = 0.0
var speed: float = 800.0
var tower_source: Node2D = null
var sprite: Sprite2D

# Tier effects, set by the tower that fires it
var pierce: int = 0                # viruses the shot can hit in total (0 or 1 = only its target)
var max_travel: float = 0.0        # how far a piercing shot keeps flying after its first hit
var splash_factor: float = 0.0     # share of the damage dealt to viruses near the one hit
var splash_radius_px: float = 0.0

var _hits_left: int = 1
var _straight: bool = false         # after the first hit a piercing shot flies straight on
var _dir: Vector2 = Vector2.RIGHT
var _travelled: float = 0.0
var _already_hit: Array = []

func _process(delta):
	# Built on the first frame because tower_source and the tier effects are set after add_child()
	if sprite == null:
		_setup_sprite()
		_hits_left = maxi(pierce, 1)
		if is_instance_valid(target):
			_dir = (target.global_position - global_position).normalized()
	if _straight:
		_fly_on(delta)
		return
	if not is_instance_valid(target):
		queue_free()
		return
		
	var dir = (target.global_position - global_position).normalized()
	var dist = global_position.distance_to(target.global_position)
	var move_amount = speed * delta
	
	if dist <= move_amount:
		hit()
	else:
		_dir = dir
		global_position += dir * move_amount
		rotation = dir.angle()

# The shot has reached its target
func hit():
	if is_instance_valid(target) and target.has_method("take_damage"):
		_apply_hit(target)
	_hits_left -= 1
	if _hits_left > 0 and is_instance_valid(target):
		_straight = true
	else:
		queue_free()

# After its first hit, a piercing shot flies straight on and hits viruses it passes
func _fly_on(delta: float) -> void:
	var step := speed * delta
	global_position += _dir * step
	_travelled += step
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(enemy) and enemy.is_alive and not _already_hit.has(enemy) \
				and global_position.distance_to(enemy.global_position) <= HIT_RADIUS_PX:
			_apply_hit(enemy)
			_hits_left -= 1
			if _hits_left <= 0:
				queue_free()
				return
	if _travelled >= max_travel:
		queue_free()

func _apply_hit(enemy: Node2D) -> void:
	_already_hit.append(enemy)
	Audio.play_at(&"hit_generic", enemy.global_position)
	var pierces_armor: bool = is_instance_valid(tower_source) and tower_source.tower_data.get("armor_pierce", false)
	enemy.take_damage(damage, pierces_armor)
	if splash_factor > 0.0 and splash_radius_px > 0.0:
		for other in get_tree().get_nodes_in_group("enemies"):
			if other != enemy and is_instance_valid(other) and other.is_alive \
					and other.global_position.distance_to(enemy.global_position) <= splash_radius_px:
				other.take_damage(damage * splash_factor)
	if is_instance_valid(tower_source) and tower_source.has_method("on_projectile_hit"):
		tower_source.on_projectile_hit(enemy, damage)

func _setup_sprite():
	sprite = Sprite2D.new()
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.scale = Vector2.ONE * Globals.PIXEL_SCALE
	var art = "default"
	if is_instance_valid(tower_source) and "tower_type" in tower_source:
		match tower_source.tower_type:
			Globals.TowerType.ANTIVIRUS_CANNON:
				art = "cannon"
			Globals.TowerType.DATA_SPIKE:
				art = "data_spike"
			Globals.TowerType.SNIPER_NODE:
				art = "sniper"
	# The default shot is white, tinted with the tower colour
	if art == "default" and is_instance_valid(tower_source) and "tower_data" in tower_source:
		sprite.modulate = tower_source.tower_data.get("color", Color(0.0, 1.0, 0.53))
	# Upgraded towers can have their own shot art (cannon_a3.png); otherwise the base one is used
	var path := "res://assets/sprites/pixel/projectiles/%s.png" % art
	if is_instance_valid(tower_source) and tower_source.has_method("get_art_suffix"):
		var tiered := "res://assets/sprites/pixel/projectiles/%s%s.png" % [art, tower_source.get_art_suffix()]
		if ResourceLoader.exists(tiered):
			path = tiered
	sprite.texture = load(path)
	add_child(sprite)
