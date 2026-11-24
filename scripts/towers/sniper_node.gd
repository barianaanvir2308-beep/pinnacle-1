class_name SniperNode extends BaseTower

var muzzle_flash_timer: float = 0.0

func _init():
	tower_type = Globals.TowerType.SNIPER_NODE
	tower_type_export = Globals.TowerType.SNIPER_NODE

func _process(delta):
	super._process(delta)
	if muzzle_flash_timer > 0:
		muzzle_flash_timer -= delta
		queue_redraw()

func fire_at(target: Node2D):
	super.fire_at(target)
	muzzle_flash_timer = 0.3
	queue_redraw()

func _setup_visuals():
	super._setup_visuals()
	_load_art("sniper_node")

func _draw():
	if muzzle_flash_timer > 0:
		var angle = -PI/2
		if is_instance_valid(current_target):
			angle = (current_target.global_position - global_position).angle()
		var barrel_length = 56.0
		var flash_pos = Vector2(barrel_length, 0).rotated(angle)
		var flash_end = Vector2(barrel_length + 40, 0).rotated(angle)
		draw_line(flash_pos, flash_end, Color(1.0, 1.0, 1.0, muzzle_flash_timer * 3.0), 3.0)
	super._draw()
