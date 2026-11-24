extends Node
class_name EnemyManager

var active_enemies: Array[Node] = []
@export var enemy_container: Node2D

var enemy_scenes: Dictionary = {
	Globals.EnemyType.BASIC_VIRUS: "res://scenes/enemies/BasicVirus.tscn",
	Globals.EnemyType.TROJAN_HORSE: "res://scenes/enemies/TrojanHorse.tscn",
	Globals.EnemyType.WORM: "res://scenes/enemies/Worm.tscn",
	Globals.EnemyType.RANSOMWARE: "res://scenes/enemies/Ransomware.tscn",
	Globals.EnemyType.SPYWARE: "res://scenes/enemies/Spyware.tscn",
	Globals.EnemyType.ROOTKIT: "res://scenes/enemies/Rootkit.tscn",
	Globals.EnemyType.DDOS_BOT: "res://scenes/enemies/DDoSBot.tscn"
}

func _ready() -> void:
	pass

func spawn_enemy(enemy_type: int, health_mult: float, speed_mult: float, spawn_pos: Vector2, path_points: Array[Vector2]) -> Node:
	var scene_path = enemy_scenes.get(enemy_type, "")
	if scene_path == "":
		push_error("Enemy scene not found for type: %d" % enemy_type)
		return null
	
	var scene = load(scene_path)
	if scene == null:
		push_error("Failed to load enemy scene: %s" % scene_path)
		return null
	
	if not is_instance_valid(enemy_container):
		push_error("Enemy container not assigned in EnemyManager")
		return null
	
	var enemy = scene.instantiate()
	enemy.position = spawn_pos
	enemy_container.add_child(enemy)
	
	if enemy.has_method("configure"):
		enemy.configure(enemy_type, health_mult, speed_mult)
	if enemy.has_method("set_path"):
		enemy.set_path(path_points)
	
	active_enemies.append(enemy)
	enemy.tree_exiting.connect(_on_enemy_tree_exiting.bind(enemy))
	return enemy

func _on_enemy_tree_exiting(enemy: Node) -> void:
	if active_enemies.has(enemy):
		active_enemies.erase(enemy)

func get_active_enemies() -> Array[Node]:
	active_enemies = active_enemies.filter(func(e): return is_instance_valid(e))
	return active_enemies

func get_enemy_count() -> int:
	return get_active_enemies().size()

func clear_all_enemies() -> void:
	for enemy in active_enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()
	active_enemies.clear()
