class_name AntivirusCannon extends BaseTower

var muzzle_flash_timer: float = 0.0

func _init():
	tower_type = Globals.TowerType.ANTIVIRUS_CANNON
	tower_type_export = Globals.TowerType.ANTIVIRUS_CANNON

func _process(delta):
	super._process(delta)
	if muzzle_flash_timer > 0:
		muzzle_flash_timer -= delta
		queue_redraw()

func fire_at(target: Node2D):
	super.fire_at(target)
	muzzle_flash_timer = 0.1
	queue_redraw()

func _setup_visuals():
	super._setup_visuals()
	_load_art("antivirus_cannon")
