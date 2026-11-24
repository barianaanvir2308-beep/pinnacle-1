class_name DDosBotEnemy extends BaseEnemy

func _init() -> void:
	enemy_type = Globals.EnemyType.DDOS_BOT

func _setup_visuals() -> void:
	super._setup_visuals()
	_load_art("ddos_bot")
