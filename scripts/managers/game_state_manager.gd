extends Node
class_name GameStateManager

var current_state: int = Globals.GameState.MAIN_MENU
var previous_state: int = Globals.GameState.BUILD_PHASE

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("game_state_manager")
	Events.base_health_changed.connect(_on_base_health_changed)
	Events.all_waves_completed.connect(_on_all_waves_completed)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		if current_state == Globals.GameState.WAVE_ACTIVE or current_state == Globals.GameState.BUILD_PHASE:
			previous_state = current_state
			change_state(Globals.GameState.PAUSED)
		elif current_state == Globals.GameState.PAUSED:
			change_state(previous_state)

func _is_valid_transition(from_state: int, to_state: int) -> bool:
	match from_state:
		Globals.GameState.MAIN_MENU:
			return to_state == Globals.GameState.LEVEL_SELECT or to_state == Globals.GameState.SETUP
		Globals.GameState.LEVEL_SELECT:
			return to_state == Globals.GameState.SETUP or to_state == Globals.GameState.MAIN_MENU
		Globals.GameState.SETUP:
			return to_state == Globals.GameState.BUILD_PHASE or to_state == Globals.GameState.MAIN_MENU
		Globals.GameState.BUILD_PHASE:
			return to_state == Globals.GameState.WAVE_ACTIVE or to_state == Globals.GameState.PAUSED or to_state == Globals.GameState.MAIN_MENU or to_state == Globals.GameState.VICTORY or to_state == Globals.GameState.GAME_OVER
		Globals.GameState.WAVE_ACTIVE:
			return to_state == Globals.GameState.WAVE_COMPLETE or to_state == Globals.GameState.BUILD_PHASE or to_state == Globals.GameState.GAME_OVER or to_state == Globals.GameState.PAUSED or to_state == Globals.GameState.VICTORY
		Globals.GameState.WAVE_COMPLETE:
			return to_state == Globals.GameState.BUILD_PHASE or to_state == Globals.GameState.VICTORY or to_state == Globals.GameState.MAIN_MENU
		Globals.GameState.PAUSED:
			return to_state == Globals.GameState.BUILD_PHASE or to_state == Globals.GameState.WAVE_ACTIVE or to_state == Globals.GameState.MAIN_MENU or to_state == Globals.GameState.LEVEL_SELECT
		Globals.GameState.GAME_OVER:
			return to_state == Globals.GameState.MAIN_MENU or to_state == Globals.GameState.LEVEL_SELECT or to_state == Globals.GameState.SETUP
		Globals.GameState.VICTORY:
			return to_state == Globals.GameState.MAIN_MENU or to_state == Globals.GameState.LEVEL_SELECT or to_state == Globals.GameState.SETUP
	return false

func change_state(new_state: int) -> bool:
	if not _is_valid_transition(current_state, new_state):
		push_warning("Invalid state transition from %s to %s" % [current_state, new_state])
		return false
	var old_state = current_state
	current_state = new_state
	match new_state:
		Globals.GameState.PAUSED:
			get_tree().paused = true
		Globals.GameState.WAVE_ACTIVE, Globals.GameState.BUILD_PHASE, Globals.GameState.SETUP, Globals.GameState.LEVEL_SELECT, Globals.GameState.MAIN_MENU:
			get_tree().paused = false
	Events.game_state_changed.emit(old_state, new_state)
	return true

func _on_base_health_changed(current_health: int, _max_health: int) -> void:
	if current_health <= 0 and current_state != Globals.GameState.GAME_OVER:
		change_state(Globals.GameState.GAME_OVER)
		Events.game_over.emit()

func _on_all_waves_completed() -> void:
	pass
