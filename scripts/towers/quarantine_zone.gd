class_name QuarantineZone extends BaseTower

var pulse_timer: float = 0.0

func _init():
	tower_type = Globals.TowerType.QUARANTINE_ZONE
	tower_type_export = Globals.TowerType.QUARANTINE_ZONE

func _process(delta):
	super._process(delta)
	if pulse_timer > 0:
		pulse_timer -= delta
		queue_redraw()

func try_attack(enemies: Array):
	if cooldown_timer > 0 or is_tower_disabled:
		return
	
	var valid_enemies = []
	for enemy in enemies:
		if is_instance_valid(enemy) and is_in_range(enemy):
			if "is_visible_to_towers" in enemy and not enemy.is_visible_to_towers:
				continue
			valid_enemies.append(enemy)
			
	if not valid_enemies.is_empty():
		# AoE damage
		for enemy in valid_enemies:
			if enemy.has_method("take_damage"):
				enemy.take_damage(damage)
				
		pulse_timer = 0.2
		cooldown_timer = attack_interval
		queue_redraw()

func fire_at(target: Node2D):
	# Overridden to do nothing since try_attack handles AoE
	pass

func _setup_visuals():
	super._setup_visuals()
	_load_art("quarantine_zone")

func _draw():
	if pulse_timer > 0:
		var color = Globals.TOWER_DATA[tower_type].color
		var range_pixels = Globals.get_tower_range_pixels(attack_range)
		var p = 1.0 - (pulse_timer / 0.2)
		draw_circle(Vector2.ZERO, range_pixels * p, Color(color.r, color.g, color.b, 0.4 * (1.0 - p)))
	super._draw()
