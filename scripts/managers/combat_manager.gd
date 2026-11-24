extends Node
class_name CombatManager

var tower_container: Node2D
var enemy_manager: Node # Using Node instead of EnemyManager just in case

func setup(p_tower_container: Node2D, p_enemy_manager: Node) -> void:
    tower_container = p_tower_container
    enemy_manager = p_enemy_manager

func _physics_process(_delta: float) -> void:
    if not is_instance_valid(tower_container) or not is_instance_valid(enemy_manager):
        return
    
    # After a System Crash (Emergency Overclock) every tower is offline for a few seconds
    var overclock = get_tree().get_first_node_in_group("overclock_manager")
    if overclock != null and overclock.towers_paused():
        return
    
    var enemies = enemy_manager.get_active_enemies()
    if enemies.is_empty():
        return
    
    for tower in tower_container.get_children():
        if tower.has_method("try_attack"):
            tower.try_attack(enemies)
