# controller_input.gd — What a controller's joystick and buttons do in the game
#
# HardwareLink turns either board's serial lines into four calls on this node:
#   move(dir)         joystick step: moves the cursor one tile (or the highlight in a menu, the tower picker or the
#                     selected tower's panel)
#   press_select()    SELECT: choose / confirm (a left click on the cursor tile)
#   press_override()  OVERRIDE (Uno) / OVERDRIVE (ESP32): Emergency Overclock, exactly like the O key
#   press_back()      BACK (Uno) / SELECT held 600 ms (ESP32): go back / deselect / cancel, like Esc or a right click
#
# On the board, SELECT does the obvious thing for the tile under the cursor:
#   a tower            -> select it (its info panel opens). While a tower is selected the joystick moves between
#                         its upgrade cards, Repair and Sell, and SELECT presses the highlighted one; back deselects.
#   an empty socket    -> open the tower-choice menu beside it: up/down changes the tower, SELECT builds it, back
#                         closes the menu
#   the Arduino core   -> start the next wave (build phase only), like Space
# Nothing here changes a rule: every action goes through the same manager functions the mouse and keyboard use,
# and mouse and keyboard keep working at the same time.
class_name ControllerInput
extends Node

const MENU_STATES: Array = [Globals.GameState.MAIN_MENU, Globals.GameState.LEVEL_SELECT,
	Globals.GameState.GAME_OVER, Globals.GameState.VICTORY]

var active: bool = false                     # true once the controller has been used; shows the cursor
var cursor: Vector2i = Vector2i(-1, -1)      # grid tile under the cursor
var picker_open: bool = false                # choosing which tower to build on the cursor tile
var picker_index: int = 0                    # index into the level's unlocked towers
var menu_index: int = -1                     # highlighted button of the open menu
var panel_index: int = -1                    # highlighted button of the selected tower's panel (-1 = none yet)
var board: StringName = &""                  # which controller is talking (set by HardwareLink): &"uno" / &"esp32"
var choice_menu: TowerChoiceMenu             # the small tower menu shown beside the socket while picking

var _main: Node
var _menu_id: int = 0                        # instance id of the menu the highlight belongs to

func setup(main: Node) -> void:
	_main = main
	add_to_group("controller_input")

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Events.game_state_changed.connect(_on_game_state_changed)
	Events.level_selected.connect(func(_i): cursor = Vector2i(-1, -1))
	Events.hardware_connection_changed.connect(_on_connection_changed)
	Events.tower_selected.connect(func(_t): _reset_panel())
	Events.tower_deselected.connect(_reset_panel)

# =============================================================================
# THE FOUR INPUTS
# =============================================================================

func move(dir: Vector2i) -> void:
	active = true
	if _in_menu():
		_menu_step(1 if (dir.x > 0 or dir.y > 0) else -1)
	elif _in_play():
		if picker_open:
			var count: int = _towers().size()
			picker_index = wrapi(picker_index + _step_of(dir), 0, count)
			_show_picker()
		elif _panel_open():
			_panel_step(_step_of(dir))
		else:
			_ensure_cursor()
			cursor = Vector2i(clampi(cursor.x + dir.x, 0, Globals.GRID_WIDTH - 1),
				clampi(cursor.y + dir.y, 0, Globals.GRID_HEIGHT - 1))
		_refresh_cursor()

func press_select() -> void:
	active = true
	if _in_menu():
		_menu_press()
		return
	if not _in_play():
		return
	_ensure_cursor()
	var tower_mgr: Node = _main.tower_mgr
	if not picker_open and not _main.placement_mode and _panel_open():
		_panel_press()
		return
	if picker_open:
		_build(_towers()[picker_index])
	elif _main.placement_mode:  # a tower was already chosen with the keyboard or the mouse
		_build(_main.placement_tower_type)
	elif is_instance_valid(tower_mgr.placed_towers.get(cursor)):
		tower_mgr.select_tower(tower_mgr.placed_towers[cursor])
	elif Globals.get_cell_type(cursor) == Globals.CellType.BUILDABLE:
		tower_mgr.deselect_tower()
		picker_open = true
		picker_index = clampi(picker_index, 0, _towers().size() - 1)
		_show_picker()
	elif Globals.get_cell_type(cursor) == Globals.CellType.ARDUINO:
		if _main.game_state_mgr.current_state == Globals.GameState.BUILD_PHASE:
			_main._start_next_wave()
	else:
		Events.show_message.emit("NOTHING TO SELECT HERE  -  move to a green socket or a tower", 1.5)
	_refresh_cursor()

func press_override() -> void:
	var overclock: Node = _main.overclock_mgr
	if overclock == null or not is_instance_valid(overclock):
		return
	if not overclock.use():
		Events.show_message.emit("OVERCLOCK NOT READY", 1.5)

func press_back() -> void:
	active = true
	if _in_menu():
		var state: int = _main.game_state_mgr.current_state
		if state == Globals.GameState.LEVEL_SELECT:
			_main.game_state_mgr.change_state(Globals.GameState.MAIN_MENU)
		elif state == Globals.GameState.GAME_OVER or state == Globals.GameState.VICTORY:
			_main.game_state_mgr.change_state(Globals.GameState.LEVEL_SELECT)
		return
	if not _in_play():
		return
	if picker_open:
		_close_picker()
	elif _main.placement_mode:
		_main._on_tower_placement_cancelled()
	else:
		_main.tower_mgr.deselect_tower()
	_refresh_cursor()

# =============================================================================
# BOARD
# =============================================================================

# Up/down (or left/right on a step with no vertical part) as -1 or +1: down and right go to the next item
func _step_of(dir: Vector2i) -> int:
	var v: int = dir.y if dir.y != 0 else dir.x
	return 1 if v > 0 else -1

func _in_play() -> bool:
	var state: int = _main.game_state_mgr.current_state
	return state == Globals.GameState.BUILD_PHASE or state == Globals.GameState.WAVE_ACTIVE

func _towers() -> Array:
	return Globals.get_unlocked_towers(Globals.current_level)

# Builds on the cursor tile, and says why when it can't
func _build(tower_type: int) -> void:
	var tower_mgr: Node = _main.tower_mgr
	var cost: int = Globals.TOWER_DATA[tower_type].cost
	if tower_mgr.place_tower(cursor, tower_type):
		_close_picker()
	elif Globals.get_cell_type(cursor) != Globals.CellType.BUILDABLE or tower_mgr.placed_towers.has(cursor):
		Events.show_message.emit("CAN'T BUILD HERE", 1.5)
	elif not ResourceManager.can_afford(cost):
		Events.show_message.emit("NOT ENOUGH ENERGY  -  %s costs %d" % [Globals.TOWER_DATA[tower_type].name.to_upper(), cost], 2.0)

# Opens or updates the small tower-choice menu beside the cursor tile (and lights the matching build card)
func _show_picker() -> void:
	if choice_menu == null or not is_instance_valid(choice_menu):
		choice_menu = TowerChoiceMenu.new()
		choice_menu.name = "TowerChoiceMenu"
		_main.ui_layer.add_child(choice_menu)
	choice_menu.show_for(_towers(), picker_index, cursor, cancel_hint())
	if _main.tower_panel != null and _main.tower_panel.has_method("highlight"):
		_main.tower_panel.highlight(picker_index)

func _close_picker() -> void:
	if not picker_open:
		return
	picker_open = false
	if choice_menu != null and is_instance_valid(choice_menu):
		choice_menu.hide()
	if _main.tower_panel != null and _main.tower_panel.has_method("highlight"):
		_main.tower_panel.highlight(-1)

# How to cancel on the board in use: the Uno has a BACK button, the ESP32 a long SELECT
func cancel_hint() -> String:
	return "hold SELECT = cancel" if board == &"esp32" else "BACK = cancel"

# =============================================================================
# THE SELECTED TOWER'S PANEL (upgrade cards, Repair, Sell)
# =============================================================================

func _panel() -> Node:
	var panel = _main.tower_info_panel
	return panel if panel != null and is_instance_valid(panel) else null

func _panel_open() -> bool:
	var panel := _panel()
	return panel != null and panel.visible and is_instance_valid(_main.tower_mgr.selected_tower)

func _panel_step(step: int) -> void:
	var count: int = _panel().controller_buttons().size()
	if count == 0:
		return
	panel_index = wrapi(panel_index + step, 0, count) if panel_index >= 0 else 0
	_panel().controller_highlight(panel_index)

# SELECT on the panel: nothing lit yet -> light the first button (so a quick double press never buys anything by
# accident); otherwise press the lit one, exactly like a mouse click on it
func _panel_press() -> void:
	if panel_index < 0:
		_panel_step(1)
		return
	_panel().controller_press(panel_index)

func _reset_panel() -> void:
	panel_index = -1
	var panel := _panel()
	if panel != null:
		panel.controller_highlight(-1)

# The cursor starts on the buildable tile nearest the middle of the board
func _ensure_cursor() -> void:
	if Globals.is_valid_grid_pos(cursor):
		return
	var centre := Vector2(Globals.GRID_WIDTH - 1, Globals.GRID_HEIGHT - 1) * 0.5
	var best := INF
	cursor = Vector2i(Globals.GRID_WIDTH / 2, Globals.GRID_HEIGHT / 2)
	for y in Globals.GRID_HEIGHT:
		for x in Globals.GRID_WIDTH:
			var d := Vector2(x, y).distance_squared_to(centre)
			if Globals.get_cell_type(Vector2i(x, y)) == Globals.CellType.BUILDABLE and d < best:
				best = d
				cursor = Vector2i(x, y)

# Draws the cursor on the board: yellow normally; green or red while a tower is waiting to be built there
func _refresh_cursor() -> void:
	var board: Node = _main.game_board
	if not active or not _in_play():
		board.show_controller_cursor(Vector2i(-1, -1), 0)
		return
	_ensure_cursor()
	var mode := 0
	if picker_open:
		mode = 1 if _main.tower_mgr.can_place_tower(cursor, _towers()[picker_index]) else 2
	elif _main.placement_mode:
		mode = 1 if _main.tower_mgr.can_place_tower(cursor, _main.placement_tower_type) else 2
	board.show_controller_cursor(cursor, mode)

# =============================================================================
# MENUS
# =============================================================================

func _in_menu() -> bool:
	return MENU_STATES.has(_main.game_state_mgr.current_state)

# The buttons of the open menu that can be pressed, top to bottom
func _menu_buttons() -> Array:
	var found: Array = []
	var overlay: Node = _main.active_overlay
	if overlay == null or not is_instance_valid(overlay):
		return found
	for node in overlay.find_children("*", "Button", true, false):
		if node.is_visible_in_tree() and not node.disabled and not node.is_queued_for_deletion():
			found.append(node)
	return found

func _menu_step(step: int) -> void:
	var buttons := _menu_buttons()
	if buttons.is_empty():
		return
	menu_index = wrapi(menu_index + step, 0, buttons.size()) if menu_index >= 0 else 0
	buttons[menu_index].grab_focus()

func _menu_press() -> void:
	var buttons := _menu_buttons()
	if buttons.is_empty():
		return
	if menu_index < 0 or menu_index >= buttons.size():
		_menu_step(1)  # nothing highlighted yet: highlight the first button
		return
	buttons[menu_index].pressed.emit()

func _process(_delta: float) -> void:
	if not active:
		return
	# A new menu opened: highlight its first button so SELECT works straight away
	var overlay: Node = _main.active_overlay
	var id: int = overlay.get_instance_id() if (overlay != null and is_instance_valid(overlay)) else 0
	if id != _menu_id:
		_menu_id = id
		menu_index = -1
		if id != 0 and _in_menu():
			_menu_step(1)
	if picker_open or _main.placement_mode:
		_refresh_cursor()  # keep the green / red preview right as Energy changes
	if picker_open and choice_menu != null and is_instance_valid(choice_menu):
		choice_menu.refresh()  # affordability changes as Energy comes in
	if panel_index >= 0 and _panel_open():
		# the panel rebuilds its buttons as Energy and tiers change: keep the highlight on a valid one
		panel_index = clampi(panel_index, 0, maxi(_panel().controller_buttons().size() - 1, 0))
		_panel().controller_highlight(panel_index)

func _on_game_state_changed(_old: int, _new: int) -> void:
	if not _in_play():
		_close_picker()
	elif picker_open:
		_show_picker.call_deferred()  # the tower cards are rebuilt at each build phase: light the card again
	_refresh_cursor.call_deferred()

func _on_connection_changed(connected: bool) -> void:
	if not connected:
		_close_picker()
		_reset_panel()
		active = false
		_refresh_cursor()
