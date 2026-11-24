class_name SpywareEnemy extends BaseEnemy

# An escort. It walks its route at the pace of the nearest virus it is following (or its own pace when
# none is left). Other viruses within the aura move 20% faster and take 20% less damage (see BaseEnemy).
var follow_target: Node2D = null
var _own_speed: float = 1.0
var _follow_check_time: float = 0.0

func _init() -> void:
	enemy_type = Globals.EnemyType.SPYWARE

func _ready() -> void:
	super._ready()
	add_to_group("spyware")
	_own_speed = speed

func configure(type: int, p_health_mult: float, p_speed_mult: float) -> void:
	super.configure(type, p_health_mult, p_speed_mult)
	_own_speed = speed

func _process(delta: float) -> void:
	_update_follow(delta)
	super._process(delta)

# Re-picks the nearest other virus a few times a second and matches its pace
func _update_follow(delta: float) -> void:
	_follow_check_time -= delta
	if _follow_check_time > 0.0 and is_instance_valid(follow_target) and follow_target.is_alive:
		return
	_follow_check_time = 0.4
	follow_target = null
	var nearest := INF
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy == self or not is_instance_valid(enemy) or not enemy.is_alive or enemy.enemy_type == Globals.EnemyType.SPYWARE:
			continue
		var d := global_position.distance_squared_to(enemy.global_position)
		if d < nearest:
			nearest = d
			follow_target = enemy
	speed = follow_target.speed if follow_target != null else _own_speed

func _setup_visuals() -> void:
	super._setup_visuals()
	_load_art("spyware")

# The aura, as a faint ring
func _draw() -> void:
	super._draw()
	var radius: float = Globals.ENEMY_DATA[Globals.EnemyType.SPYWARE].aura_radius * Globals.TILE_SIZE
	draw_circle(Vector2.ZERO, radius, Color(0.4, 0.8, 1.0, 0.06))
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, Color(0.4, 0.8, 1.0, 0.35), 2.0)
