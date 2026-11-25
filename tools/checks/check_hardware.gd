# check_hardware.gd — Headless checks for the Arduino controller link (scripts/managers/hardware_link.gd and
# scripts/managers/controller_input.gd)
# Run: godot --headless --path . res://tools/checks/check_hardware.tscn
# This check plays the part of tools/hardware_bridge.py: it sends the board's lines to the game on UDP 9101, so the
# real network path is tested without a board. It checks that the game is unchanged with no controller, that the
# controller only counts while the board is heard from, that the joystick and SELECT / BACK work the menus, the
# cursor, the tower picker and tower selection, that OVERRIDE fires Overclock exactly once per press, and that
# mouse and keyboard keep working beside the controller and after it is unplugged.
extends Node

var _fails: int = 0
var _main: Node
var _link: HardwareLink
var _pad: ControllerInput
var _oc: OverclockManager
var _bridge: PacketPeerUDP
var _messages: Array[String] = []

func _check(cond: bool, msg: String) -> void:
	if not cond:
		_fails += 1
	print(("  ok    " if cond else "  FAIL  ") + msg)

func _ready() -> void:
	_bridge = PacketPeerUDP.new()
	_check(_bridge.bind(HardwareLink.BRIDGE_PORT, "127.0.0.1") == OK, "fake bridge listens on udp %d" % HardwareLink.BRIDGE_PORT)
	_bridge.set_dest_address("127.0.0.1", HardwareLink.GAME_PORT)
	Events.show_message.connect(func(t, _d): _messages.append(t))
	Globals.levels_unlocked = 5  # so the level list has more than one entry to move through

	_main = load("res://scenes/main/Main.tscn").instantiate()
	await get_tree().process_frame
	get_tree().root.add_child(_main)
	get_tree().current_scene = _main  # as in the real game: the menus look their managers up through current_scene
	await _frames(2)
	_link = _main.hardware_link
	_pad = _main.controller_input
	_oc = _main.overclock_mgr
	_check(_link != null and _link.is_inside_tree(), "Main creates a HardwareLink under Managers")
	_check(_pad != null and _pad.is_inside_tree(), "Main creates a ControllerInput under Managers")

	print("== no controller plugged in")
	await _check_offline()
	print("== controller connects")
	await _check_connect()
	print("== menus")
	await _check_menus()
	print("== joystick cursor")
	await _check_cursor()
	print("== SELECT builds a tower, BACK cancels")
	await _check_build()
	print("== SELECT / BACK on a tower")
	await _check_tower_select()
	print("== OVERRIDE button")
	await _check_override()
	print("== keyboard beside the controller")
	await _check_keyboard_mix()
	print("== paused")
	await _check_pause()
	print("== start a wave from the controller")
	await _check_start_wave()
	print("== controller lost")
	await _check_disconnect()

	print("check_hardware: %d failure(s)" % _fails)
	_bridge.close()
	get_tree().quit(1 if _fails > 0 else 0)

# ---- helpers ----
func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

# One line from the board, then time for the game to read it
func _board(line: String) -> void:
	_bridge.put_packet((line + "\n").to_ascii_buffer())
	await _frames(3)

func _state() -> int:
	return _main.game_state_mgr.current_state

# Walks the cursor to a tile with joystick steps, like a player would
func _goto(target: Vector2i) -> void:
	_pad._ensure_cursor()
	while _pad.cursor.x != target.x:
		await _board("JOY R" if target.x > _pad.cursor.x else "JOY L")
	while _pad.cursor.y != target.y:
		await _board("JOY D" if target.y > _pad.cursor.y else "JOY U")

func _free_sockets() -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	for y in Globals.GRID_HEIGHT:
		for x in Globals.GRID_WIDTH:
			var cell := Vector2i(x, y)
			if Globals.get_cell_type(cell) == Globals.CellType.BUILDABLE and not _main.tower_mgr.placed_towers.has(cell):
				found.append(cell)
	return found

func _key(code: Key) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.keycode = code
	ev.pressed = true
	return ev

# ---- checks ----
func _check_offline() -> void:
	_check(not _link.connected, "not connected when nothing has been heard")
	_check(not _main.hud.console_label.visible, "no CONTROLLER LINKED label")
	await _board("LINK UP /dev/ttyACM0")
	_check(not _link.connected, "a bridge with a port open is not enough: the board itself must talk")
	_check(_link.link_port == "/dev/ttyACM0", "the bridge's port is remembered")
	_check(not _pad.active and _main.game_board.controller_cursor.x < 0, "no controller cursor is drawn")
	_check(_state() == Globals.GameState.MAIN_MENU, "the game sits on the main menu as usual")

func _check_connect() -> void:
	await _board("HELLO PZ2")
	_check(_link.connected, "connected after the board's HELLO")
	_check(_main.hud.console_label.visible, "HUD shows CONTROLLER LINKED")
	_check("ARDUINO CONTROLLER CONNECTED" in _messages, "the player is told the controller connected")
	_check(_link.inputs_received == 0, "HELLO and HB are not counted as inputs")

func _check_menus() -> void:
	await _board("JOY D")
	var focused := get_viewport().gui_get_focus_owner()
	_check(focused is Button and "SELECT OPERATION" in focused.text, "joystick highlights the first main-menu button")
	await _board("JOY D")
	focused = get_viewport().gui_get_focus_owner()
	_check(focused is Button and "EXIT" in focused.text, "joystick down moves to the next button")
	await _board("JOY U")
	await _board("BTN SELECT")
	_check(_state() == Globals.GameState.LEVEL_SELECT, "SELECT presses it: level select opens")
	await _board("BTN BACK")
	_check(_state() == Globals.GameState.MAIN_MENU, "BACK returns to the main menu")
	await _board("BTN SELECT")
	_check(_state() == Globals.GameState.LEVEL_SELECT, "SELECT works straight away on a new menu (first button is highlighted)")
	await _board("JOY D")
	await _board("BTN SELECT")
	_check(_state() == Globals.GameState.BUILD_PHASE and Globals.current_level == 1, "joystick down + SELECT starts Level 2")
	_main.get_node("Managers/CombatManager").set_physics_process(false)

func _check_cursor() -> void:
	await _board("JOY R")
	var board: Node = _main.game_board
	_check(_pad.active and board.controller_cursor == _pad.cursor and _pad.cursor.x >= 0, "the cursor appears on the board at %s" % _pad.cursor)
	var before: Vector2i = _pad.cursor
	await _board("JOY L")
	_check(_pad.cursor == before + Vector2i(-1, 0), "JOY L moves one tile left")
	await _board("JOY U")
	_check(_pad.cursor == before + Vector2i(-1, -1), "JOY U moves one tile up")
	await _board("JOY D")
	await _board("JOY R")
	_check(_pad.cursor == before, "JOY D and JOY R move back")
	for i in Globals.GRID_WIDTH + 2:
		await _board("JOY L")
	_check(_pad.cursor.x == 0, "the cursor stops at the left edge")
	for i in Globals.GRID_HEIGHT + 2:
		await _board("JOY D")
	_check(_pad.cursor.y == Globals.GRID_HEIGHT - 1, "and at the bottom edge")

func _check_build() -> void:
	var sockets := _free_sockets()
	var towers: Array = Globals.get_unlocked_towers(Globals.current_level)
	var tile: Vector2i = sockets[0]
	await _goto(tile)
	await _board("BTN SELECT")
	_check(_pad.picker_open and _pad.picker_index == 0, "SELECT on an empty socket opens the tower picker")
	_check(_main.game_board.controller_cursor_mode == 1, "the tile shows green (can build)")
	_check(_messages.back().begins_with("BUILD:") and Globals.TOWER_DATA[towers[0]].name.to_upper() in _messages.back(), "the HUD names the tower: %s" % _messages.back().substr(0, 36).strip_edges())
	await _board("JOY R")
	_check(_pad.picker_index == 1 and _pad.cursor == tile, "joystick changes the tower, the cursor stays put")
	await _board("JOY L")
	await _board("JOY L")
	_check(_pad.picker_index == towers.size() - 1, "and wraps round the list")
	await _board("JOY R")
	var e := ResourceManager.current_energy
	await _board("BTN SELECT")
	var built = _main.tower_mgr.placed_towers.get(tile)
	_check(is_instance_valid(built) and built.tower_type == towers[0], "SELECT again builds the %s on that tile" % Globals.TOWER_DATA[towers[0]].name)
	_check(ResourceManager.current_energy == e - Globals.TOWER_DATA[towers[0]].cost, "and its cost is paid")
	_check(not _pad.picker_open, "the picker closes")

	var other: Vector2i = sockets[1]
	await _goto(other)
	await _board("BTN SELECT")
	await _board("BTN BACK")
	_check(not _pad.picker_open and not _main.tower_mgr.placed_towers.has(other), "BACK cancels the picker, nothing is built")
	var all_energy := ResourceManager.current_energy
	ResourceManager.current_energy = 0
	await _board("BTN SELECT")
	_check(_main.game_board.controller_cursor_mode == 2, "with no Energy the tile shows red")
	await _board("BTN SELECT")
	_check(not _main.tower_mgr.placed_towers.has(other) and _messages.back().begins_with("NOT ENOUGH ENERGY"), "and SELECT is refused: NOT ENOUGH ENERGY")
	await _board("BTN BACK")
	ResourceManager.current_energy = all_energy

func _check_tower_select() -> void:
	var tile: Vector2i = _main.tower_mgr.placed_towers.keys()[0]
	await _goto(tile)
	await _board("BTN SELECT")
	_check(_main.tower_mgr.selected_tower == _main.tower_mgr.placed_towers[tile], "SELECT on a tower selects it")
	_check(_main.tower_info_panel.visible, "its info panel opens")
	await _board("BTN BACK")
	_check(_main.tower_mgr.selected_tower == null, "BACK deselects it")

func _check_override() -> void:
	var before := _link.inputs_received
	var e := ResourceManager.current_energy
	var t0 := Time.get_ticks_usec()
	_bridge.put_packet("BTN OVERRIDE\n".to_ascii_buffer())
	var waited := 0
	while ResourceManager.current_energy == e and waited < 60:
		await get_tree().process_frame
		waited += 1
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	_check(ResourceManager.current_energy == mini(e + Globals.OVERCLOCK.energy, Globals.MAX_ENERGY), "BTN OVERRIDE fires Overclock (+150 Energy)")
	print("  info  packet -> Overclock applied in %.1f ms (%d frames)" % [ms, waited])
	_check(ms < 100.0, "the game reacts within 100 ms")
	_check(_link.inputs_received == before + 1, "exactly one input counted")
	_check(_oc.cooldown_left > 14.0, "cooldown started (15 s)")
	var e2 := ResourceManager.current_energy
	await _board("BTN OVERRIDE")
	_check(ResourceManager.current_energy == e2, "a second press during the cooldown is refused (no Energy)")
	_check("OVERCLOCK NOT READY" in _messages, "and the HUD says OVERCLOCK NOT READY")
	_oc.reset()
	await _frames(1)

func _check_keyboard_mix() -> void:
	var e := ResourceManager.current_energy
	Input.parse_input_event(_key(KEY_O))
	await _frames(2)
	_check(ResourceManager.current_energy == e + Globals.OVERCLOCK.energy, "the O key still fires Overclock while the controller is linked")
	_oc.reset()
	var tile: Vector2i = _free_sockets()[0]
	await _goto(tile)
	Input.parse_input_event(_key(KEY_2))
	await _frames(2)
	_check(_main.placement_mode, "the 2 key still picks a tower")
	await _board("BTN SELECT")
	var towers: Array = Globals.get_unlocked_towers(Globals.current_level)
	var built = _main.tower_mgr.placed_towers.get(tile)
	_check(is_instance_valid(built) and built.tower_type == towers[1], "and SELECT builds that tower on the cursor tile")
	await _board("BTN BACK")
	_check(not _main.placement_mode, "BACK leaves placement mode")

func _check_pause() -> void:
	_main.game_state_mgr.change_state(Globals.GameState.PAUSED)
	var cur: Vector2i = _pad.cursor
	var e := ResourceManager.current_energy
	await _board("JOY R")
	await _board("BTN OVERRIDE")
	_check(_pad.cursor == cur and ResourceManager.current_energy == e, "while paused the joystick and OVERRIDE do nothing")
	_main.game_state_mgr.change_state(Globals.GameState.BUILD_PHASE)
	await _frames(2)

func _check_start_wave() -> void:
	await _goto(_main.game_board.get_arduino_position())
	_check(_state() == Globals.GameState.BUILD_PHASE, "still in the build phase")
	await _board("BTN SELECT")
	_check(_state() == Globals.GameState.WAVE_ACTIVE and _main.wave_mgr.current_wave == 1, "SELECT on the Arduino core starts wave 1")

func _check_disconnect() -> void:
	await _board("LINK DOWN")
	_check(not _link.connected, "LINK DOWN disconnects at once")
	_check(not _main.hud.console_label.visible, "CONTROLLER LINKED label hidden")
	_check(_main.game_board.controller_cursor.x < 0, "the cursor is removed")
	await _board("HB")
	_check(_link.connected, "a heartbeat reconnects")
	await get_tree().create_timer(HardwareLink.SIGNAL_TIMEOUT + 0.3).timeout
	_check(not _link.connected, "silence for 3 s (board unplugged) disconnects")
	var e := ResourceManager.current_energy
	Input.parse_input_event(_key(KEY_O))
	await _frames(2)
	_check(ResourceManager.current_energy > e, "mouse and keyboard keep working after the controller is lost")
