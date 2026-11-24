class_name FirewallBeam extends BaseTower

func _init():
	tower_type = Globals.TowerType.FIREWALL_BEAM
	tower_type_export = Globals.TowerType.FIREWALL_BEAM

func _process(delta):
	super._process(delta)
	
	if is_instance_valid(current_target) and not is_tower_disabled:
		if is_in_range(current_target):
			# Continuous damage
			if current_target.has_method("take_damage"):
				current_target.take_damage(damage * delta * 60.0) # continuous beam: damage is per frame, attack_interval is unused
		else:
			current_target = null
	
	queue_redraw()

func try_attack(enemies: Array):
	if is_tower_disabled:
		current_target = null
		return
		
	if not is_instance_valid(current_target) or not is_in_range(current_target):
		current_target = find_target(enemies)
		if current_target != null: Audio.play_at(tower_data.get("fire_sound", &"fire_beam"), global_position)  # the beam locks on

func fire_at(target: Node2D):
	# Overridden to do nothing, laser is continuous in _process
	pass

func _setup_visuals():
	super._setup_visuals()
	_load_art("firewall_beam")

func _draw():
	if is_instance_valid(current_target) and not is_tower_disabled:
		var color = Globals.TOWER_DATA[tower_type].color
		var target_pos = current_target.global_position - global_position
		draw_line(Vector2.ZERO, target_pos, color, 4.0 + randf() * 4.0)
		draw_line(Vector2.ZERO, target_pos, Color(1, 1, 1, 0.8), 2.0)
		# Draw hit flare
		draw_circle(target_pos, 8.0 + randf() * 5.0, color)
	super._draw()
