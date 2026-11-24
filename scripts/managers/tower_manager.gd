extends Node
class_name TowerManager

@export var tower_container: Node2D

var placed_towers: Dictionary = {} # Vector2i -> tower_node
var selected_tower: Node = null
var placement_mode: bool = false
var placement_tower_type: int = Globals.TowerType.ANTIVIRUS_CANNON



func _ready() -> void:
	Events.tower_destroyed.connect(_on_tower_destroyed)

func _on_tower_destroyed(tower_type: int, grid_pos: Vector2i) -> void:
	if placed_towers.has(grid_pos):
		var tower = placed_towers[grid_pos]
		if selected_tower == tower:
			deselect_tower()
		placed_towers.erase(grid_pos)

func can_place_tower(grid_pos: Vector2i, tower_type: int) -> bool:
	if not Globals.is_valid_grid_pos(grid_pos):
		return false
	if Globals.get_cell_type(grid_pos) != Globals.CellType.BUILDABLE:
		return false
	if placed_towers.has(grid_pos):
		return false
		
	var tower_data = Globals.TOWER_DATA.get(tower_type, {})
	var cost = tower_data.get("cost", 9999)
	if not ResourceManager.can_afford(cost):
		return false
		
	return true

func place_tower(grid_pos: Vector2i, tower_type: int) -> bool:
	if not can_place_tower(grid_pos, tower_type):
		Events.placement_invalid.emit("Cannot place tower here")
		return false
		
	var tower_data = Globals.TOWER_DATA.get(tower_type, {})
	var cost = tower_data.get("cost", 0)
	
	if not ResourceManager.spend_energy(cost):
		return false
		
	var scene_path = tower_data.get("scene_path", "")
	if scene_path == "":
		push_error("Tower scene path not defined for type: ", tower_type)
		return false
		
	var scene = load(scene_path)
	if scene == null:
		push_error("Tower scene not found at path: ", scene_path)
		return false
		
	var tower = scene.instantiate()
	tower.position = Globals.grid_to_world(grid_pos)
	tower_container.add_child(tower)
	
	# Configure tower if it has setup method
	if tower.has_method("setup"):
		tower.setup(tower_type, grid_pos)
		
	placed_towers[grid_pos] = tower
	Events.tower_placed.emit(tower_type, grid_pos)
	
	exit_placement_mode()
	return true

func upgrade_tower(tower_node: Node, path: String) -> bool:
	if not is_instance_valid(tower_node) or not tower_node.has_method("upgrade"):
		return false
	if tower_node.get_upgrade_status(path) == "too_expensive":
		Events.energy_insufficient.emit(tower_node.get_upgrade_cost(path), ResourceManager.current_energy)
		return false
	if not tower_node.upgrade(path):
		return false
	var t_type = tower_node.get("tower_type") if "tower_type" in tower_node else 0
	Events.tower_upgraded.emit(t_type, Globals.world_to_grid(tower_node.position), path, tower_node.path_tiers[path])
	return true

func sell_tower(tower_node: Node) -> void:
	if not is_instance_valid(tower_node):
		return
		
	var grid_pos = Globals.world_to_grid(tower_node.position)
	if placed_towers.has(grid_pos):
		placed_towers.erase(grid_pos)
		
	var refund = tower_node.get_sell_value() if tower_node.has_method("get_sell_value") else 0
	ResourceManager.add_energy(refund)
	
	if selected_tower == tower_node:
		deselect_tower()
		
	var t_type = tower_node.get("tower_type") if "tower_type" in tower_node else 0
	Events.tower_sold.emit(t_type, grid_pos, refund)
	tower_node.queue_free()

# Why a tower can or can't be repaired right now: ok, full_health, tower_locked, not_build_phase, too_expensive
func repair_status(tower_node: Node) -> String:
	if tower_node.tower_health >= tower_node.tower_max_health:
		return "full_health"
	if tower_node.is_tower_disabled:
		return "tower_locked"  # a locked module can't be repaired until the lock ends
	if not _is_build_phase():
		return "not_build_phase"
	if not ResourceManager.can_afford(tower_node.get_repair_cost()):
		return "too_expensive"
	return "ok"

func repair_tower(tower_node: Node) -> bool:
	if not is_instance_valid(tower_node) or not tower_node.has_method("get_repair_cost"):
		return false
	var status := repair_status(tower_node)
	if status == "too_expensive":
		Events.energy_insufficient.emit(tower_node.get_repair_cost(), ResourceManager.current_energy)
	elif status == "not_build_phase":
		Events.show_message.emit("REPAIRS ARE ONLY POSSIBLE BETWEEN WAVES", 2.0)
	if status != "ok":
		return false
	var cost: int = tower_node.get_repair_cost()
	ResourceManager.spend_energy(cost)
	tower_node.repair()
	Events.tower_repaired.emit(tower_node, cost)
	return true

func _is_build_phase() -> bool:
	var state_mgr = get_tree().get_first_node_in_group("game_state_manager")
	return state_mgr != null and state_mgr.current_state == Globals.GameState.BUILD_PHASE

func select_tower(tower_node: Node) -> void:
	if selected_tower != tower_node:
		if is_instance_valid(selected_tower) and selected_tower.has_method("set_selected"):
			selected_tower.set_selected(false)
			
		selected_tower = tower_node
		
		if is_instance_valid(selected_tower) and selected_tower.has_method("set_selected"):
			selected_tower.set_selected(true)
			
		Events.tower_selected.emit(tower_node)

func deselect_tower() -> void:
	if is_instance_valid(selected_tower) and selected_tower.has_method("set_selected"):
		selected_tower.set_selected(false)
	var had_selection = selected_tower != null
	selected_tower = null  # cleared even if the tower was already freed
	if had_selection:
		Events.tower_deselected.emit()

func enter_placement_mode(tower_type: int) -> void:
	placement_mode = true
	placement_tower_type = tower_type
	deselect_tower()
	Events.tower_placement_started.emit(tower_type)

func exit_placement_mode() -> void:
	if placement_mode:
		placement_mode = false
		Events.tower_placement_cancelled.emit()
