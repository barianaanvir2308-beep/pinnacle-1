class_name BasicVirusEnemy extends BaseEnemy

func _init() -> void:
	enemy_type = Globals.EnemyType.BASIC_VIRUS

func _setup_visuals() -> void:
	super._setup_visuals()
	_load_art("basic_virus")

