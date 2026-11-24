class_name WormEnemy extends BaseEnemy

const WIGGLE_FRAMES: int = 4
const WIGGLE_FPS: float = 8.0

var base_offset: Vector2 = Vector2.ZERO
var can_spread: bool = true       # a Worm made by spreading cannot spread again
var is_clone: bool = false        # made by spreading: it bites fewer modules
var _hit_modules: Array = []      # it hits each module once (a clone starts with its parent's list)
var _bites: int = 0               # modules this Worm has bitten itself
var _has_spread: bool = false
var _bite_flash: float = 0.0

func _init() -> void:
	enemy_type = Globals.EnemyType.WORM

func _process(delta: float) -> void:
	if not is_alive or path_points.is_empty():
		return
		
	time_alive += delta
	_update_aura(delta)
	if is_instance_valid(sprite):
		sprite.frame = int(time_alive * WIGGLE_FPS) % WIGGLE_FRAMES

	if slow_timer > 0.0:
		slow_timer -= delta
		if slow_timer <= 0.0:
			slow_factor = 1.0
			
	var stunned := _tick_status(delta)
	
	if not stunned and current_path_index < path_points.size():
		var target_pos = path_points[current_path_index]
		var move_dir = (target_pos - base_offset).normalized()
		var dist = base_offset.distance_to(target_pos)
		
		var move_dist = speed * Globals.TILE_SIZE * _speed_factor() * delta
		
		if dist <= move_dist:
			base_offset = target_pos
			current_path_index += 1
			if current_path_index >= path_points.size():
				position = base_offset
				reach_base()
				return
		else:
			base_offset += move_dir * move_dist
			if is_instance_valid(sprite):
				sprite.rotation = lerp_angle(sprite.rotation, move_dir.angle() + PI/2, delta * 10.0)
			
		# Zigzag effect
		var perp_dir = Vector2(-move_dir.y, move_dir.x)
		var wave = sin(time_alive * 15.0) * 10.0
		position = base_offset + perp_dir * wave
	
	_bite_flash = max(_bite_flash - delta * 4.0, 0.0)
	if not stunned:
		_attack_modules()
	
	if health / max_health < 0.3 and randf() < 0.2:
		glitch_offset = Vector2(randf_range(-3, 3), randf_range(-3, 3))
	else:
		glitch_offset = Vector2.ZERO
		
	if is_instance_valid(sprite):
		sprite.position = glitch_offset
		if _bite_flash > 0:
			sprite.modulate = Color(1.0, 0.3, 0.0)
		else:
			sprite.modulate = Color.WHITE
	
	_update_status_tint()
	queue_redraw()

# On contact (within 1 tile) the Worm bites a module, once per module and at most max_bites modules in total
# (a spread clone: clone_max_bites). The first time it bites, it spreads: a second Worm appears that knows
# which modules were already bitten (so it cannot bite them again) and cannot spread itself.
func _attack_modules() -> void:
	var data: Dictionary = Globals.ENEMY_DATA[enemy_type]
	if _bites >= (data.get("clone_max_bites", 1) if is_clone else data.get("max_bites", 2)):
		return
	var best: Node = null
	for module in _modules_near(CONTACT_TILES * Globals.TILE_SIZE):
		if _hit_modules.has(module):
			continue
		if best == null or module.module_value() > best.module_value():
			best = module   # the list is nearest first, so ties go to the nearest
	if best == null:
		return
	_hit_modules.append(best)
	_bites += 1
	best.take_tower_damage(data.get("module_damage", 15.0))
	Audio.play_at(&"worm_bite", best.global_position)
	_bite_flash = 1.0
	if can_spread and not _has_spread:
		_has_spread = true
		Events.worm_spread.emit(global_position, health_mult, speed_mult, _hit_modules.duplicate())

func set_path(points: Array[Vector2]) -> void:
	path_points = points
	if path_points.size() > 0:
		base_offset = path_points[0]
		position = base_offset
		current_path_index = 1

func _setup_visuals() -> void:
	super._setup_visuals()
	_load_art("worm", WIGGLE_FRAMES)
