class_name TrojanHorseEnemy extends BaseEnemy

# After split_time seconds alive the Trojan splits into Minis. Kill it before that and it never splits.
# The timer is frozen while the Trojan is stunned (and, once the Quarantine Tower exists, trapped).
var split_timer: float = 0.0
var _split_warned: bool = false  # the warning sound plays once, when the split ring is 75% full

func _init() -> void:
	enemy_type = Globals.EnemyType.TROJAN_HORSE

func _process(delta: float) -> void:
	var frozen := stun_timer > 0.0
	super._process(delta)
	if not is_alive or frozen or path_points.is_empty():
		return
	split_timer += delta
	if not _split_warned and split_progress() >= 0.75:
		_split_warned = true
		Audio.play_at(&"trojan_split_warn", global_position)
	if split_timer >= _split_time():
		_split()

func _split_time() -> float:
	return Globals.ENEMY_DATA[enemy_type].get("split_time", 8.0)

# 0.0 just spawned ... 1.0 about to split (drives the countdown ring)
func split_progress() -> float:
	return clampf(split_timer / _split_time(), 0.0, 1.0)

# The Trojan is replaced by its Minis. It does not die, so it pays no Energy.
func _split() -> void:
	is_alive = false
	var data: Dictionary = Globals.ENEMY_DATA[enemy_type]
	Events.enemy_split.emit(position, data.get("split_count", 3), {
		"health": data.get("split_health", 30.0),
		"speed": data.get("split_speed", 1.2),
		"damage": data.get("split_damage", 3),
		"reward": data.get("split_reward", 1),
	})
	queue_free()

func _setup_visuals() -> void:
	super._setup_visuals()
	_load_art("trojan_horse")

# A ring around the Trojan that fills as the split gets closer
func _draw() -> void:
	super._draw()
	var progress := split_progress()
	if progress <= 0.0:
		return
	var color := Color(1.0, 0.85, 0.2).lerp(Color(1.0, 0.2, 0.2), progress)
	draw_arc(Vector2.ZERO, 40.0, 0.0, TAU, 32, Color(1, 1, 1, 0.12), 4.0)
	draw_arc(Vector2.ZERO, 40.0, -PI / 2.0, -PI / 2.0 + TAU * progress, 32, color, 4.0)
