class_name RootkitEnemy extends BaseEnemy

func _init() -> void:
	enemy_type = Globals.EnemyType.ROOTKIT

# Armour takes a flat amount off every hit (at least 1 damage still gets through), except from the Data Spike
# (armor_pierce)
func take_damage(amount: float, armor_pierce: bool = false) -> void:
	if not armor_pierce:
		if is_alive: Audio.play_at(&"hit_armor", global_position)
		amount = maxf(amount - Globals.ENEMY_DATA[Globals.EnemyType.ROOTKIT].get("armor_flat", 5.0), 1.0)
	super.take_damage(amount, armor_pierce)

func _setup_visuals() -> void:
	super._setup_visuals()
	_load_art("rootkit")
