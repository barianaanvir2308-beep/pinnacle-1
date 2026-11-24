class_name OverclockHub extends BaseTower

var rotation_angle: float = 0.0

func _init():
	tower_type = Globals.TowerType.OVERCLOCK_HUB
	tower_type_export = Globals.TowerType.OVERCLOCK_HUB

func _process(delta):
	super._process(delta)

func _setup_visuals():
	super._setup_visuals()
	_load_art("overclock_hub")
