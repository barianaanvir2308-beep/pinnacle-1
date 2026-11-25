# check_hardware.gd — Headless checks for the Arduino controller link (scripts/managers/hardware_link.gd and
# scripts/managers/controller_input.gd)
# Run: godot --headless --path . res://tools/checks/check_hardware.tscn
# This check plays the part of tools/hardware_bridge.py: it sends the board's lines to the game on UDP 9101, so the
# real network path is tested without a board. It checks that the game is unchanged with no controller, that the
# controller only counts while the board is heard from, that the joystick and SELECT / BACK work the menus, the
# cursor, the tower picker and tower selection, that OVERRIDE fires Overclock exactly once per press, and that
# mouse and keyboard keep working beside the controller and after it is unplugged.
extends Node

const TEST_PORT_OFFSET: int = 100

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
	# Ports 100 above the real ones, so this check can run while the game and its bridge are open
	HardwareLink.port_offset = TEST_PORT_OFFSET
	_bridge = PacketPeerUDP.new()
	_check(_bridge.bind(HardwareLink.BRIDGE_PORT + TEST_PORT_OFFSET, "127.0.0.1") == OK, "fake bridge listens on udp %d" % (HardwareLink.BRIDGE_PORT + TEST_PORT_OFFSET))
	_bridge.set_dest_address("127.0.0.1", HardwareLink.GAME_PORT + TEST_PORT_OFFSET)
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

	# ---- the ESP32 controller (PZ3): joystick + SELECT (long = back) + OVERDRIVE ----
	print("== ESP32 connects (PZ3); the Uno's lines are ignored")
	await _check_esp32_connect()
	print("== ESP32 in the menus (a long SELECT goes back)")
	await _check_esp32_menus()
	print("== ESP32 cursor and grid edges")
	await _check_esp32_cursor()
	print("== ESP32 auto-repeat")
	_check_esp32_repeat()
	print("== ESP32 short vs long SELECT")
	await _check_esp32_press()
	print("== ESP32 tower-choice menu")
	await _check_esp32_build()
	print("== ESP32 on a selected tower's panel")
	await _check_esp32_panel()
	print("== ESP32 OVERDRIVE")
	await _check_esp32_overdrive()
	print("== one board at a time")
	await _check_one_board()

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

# The controller badge on the open menu screen (null if none)
func _badge() -> ControllerBadge:
	var overlay = _main.active_overlay
	if overlay == null or not is_instance_valid(overlay):
		return null
	var found: Array = overlay.find_children("*", "ControllerBadge", true, false)
	return found[0] if not found.is_empty() else null

func _state() -> int:
	return _main.game_state_mgr.current_state

# Walks the cursor to a tile with joystick steps, like a player would
func _goto(target: Vector2i) -> void:
	_pad._ensure_cursor()
	while _pad.cursor.x != target.x:
		await _board("JOY R" if target.x > _pad.cursor.x else "JOY L")
	while _pad.cursor.y != target.y:
		await _board("JOY D" if target.y > _pad.cursor.y else "JOY U")

# One ESP32 stick nudge: push, then back to the centre (shorter than the repeat delay, so exactly one step)
func _nudge(dir: Vector2i) -> void:
	await _board("JOY %d %d" % [dir.x, dir.y])
	await _board("JOY 0 0")

# Walks the cursor to a tile with ESP32 nudges
func _goto_esp(target: Vector2i) -> void:
	_pad._ensure_cursor()
	while _pad.cursor.x != target.x:
		await _nudge(Vector2i(1 if target.x > _pad.cursor.x else -1, 0))
	while _pad.cursor.y != target.y:
		await _nudge(Vector2i(0, 1 if target.y > _pad.cursor.y else -1))

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
	var badge := _badge()
	_check(badge != null and badge.is_visible_in_tree() and not badge.linked and "NO CONTROLLER" in badge._title.text,
		"the start screen says NO CONTROLLER")

func _check_connect() -> void:
	await _board("HELLO PZ2")
	_check(_link.connected, "connected after the board's HELLO")
	_check(_main.hud.console_label.visible, "HUD shows CONTROLLER LINKED")
	_check("ARDUINO CONTROLLER CONNECTED" in _messages, "the player is told the controller connected")
	_check(_link.inputs_received == 0, "HELLO and HB are not counted as inputs")
	await _frames(1)
	var badge := _badge()
	_check(badge != null and badge.linked and badge._title.text == "ARDUINO CONTROLLER LINKED" and "BACK back" in badge._help.text,
		"the start screen now says ARDUINO CONTROLLER LINKED, with its buttons")

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
	var menu: TowerChoiceMenu = _pad.choice_menu
	_check(menu != null and menu.visible and menu.rows.size() == towers.size() and menu.index == 0,
		"a tower-choice menu opens beside the socket, listing the %d unlocked towers" % towers.size())
	_check(Globals.TOWER_DATA[towers[0]].name.to_upper() in menu.rows[0].get_child(0).get_child(1).text and menu.rows[0].get_meta("mark").text == ">",
		"the first tower is highlighted")
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

# =============================================================================
# ESP32 CONTROLLER (PZ3)
# =============================================================================

func _check_esp32_connect() -> void:
	_check(not _link.connected and _link.board == &"", "after the Uno was lost, no board is remembered")
	await _board("HB PZ3")
	_check(_link.connected and _link.board == &"esp32" and _pad.board == &"esp32", "HB PZ3 identifies the ESP32 (no HELLO needed)")
	_check("ESP32 CONTROLLER CONNECTED" in _messages, "the player is told the ESP32 connected")
	_check(_main.hud.console_label.visible, "HUD shows CONTROLLER LINKED")
	var cur: Vector2i = _pad.cursor
	var e := ResourceManager.current_energy
	var n := _link.inputs_received
	for line in ["JOY L", "JOY U", "BTN BACK", "BTN OVERRIDE"]:
		await _board(line)
	_check(_pad.cursor == cur and ResourceManager.current_energy == e and _link.inputs_received == n,
		"while the ESP32 is linked, the Uno's lines (JOY L/U, BTN BACK, BTN OVERRIDE) are ignored")
	await _board("HB")
	_check(_link.board == &"esp32", "a plain HB (the Uno's heartbeat) doesn't switch boards")
	var badge := ControllerBadge.new()
	add_child(badge)
	await _frames(1)
	_check(badge.linked and badge._title.text == "ESP32 CONTROLLER LINKED" and "HOLD SELECT back" in badge._help.text
		and "OVERDRIVE overclock" in badge._help.text, "the menu badge says ESP32 CONTROLLER LINKED with its own buttons")
	badge.queue_free()

func _check_esp32_menus() -> void:
	var gsm = _main.game_state_mgr
	gsm.change_state(Globals.GameState.GAME_OVER)
	gsm.change_state(Globals.GameState.LEVEL_SELECT)
	await _frames(2)
	await _board("BTN SELECT_LONG")
	_check(_state() == Globals.GameState.MAIN_MENU, "a long SELECT on level select goes back to the main menu")
	await _frames(1)
	var badge := _badge()
	_check(badge != null and badge.linked and badge._title.text == "ESP32 CONTROLLER LINKED", "the start screen shows ESP32 CONTROLLER LINKED")
	await _board("BTN SELECT")
	_check(_state() == Globals.GameState.LEVEL_SELECT, "SELECT presses SELECT OPERATION")
	await _frames(2)
	await _board("BTN SELECT")
	_check(_state() == Globals.GameState.BUILD_PHASE and Globals.current_level == 0, "SELECT on the first level starts Level 1")
	_main.get_node("Managers/CombatManager").set_physics_process(false)
	ResourceManager.max_energy = 100000

func _check_esp32_cursor() -> void:
	var board: Node = _main.game_board
	await _nudge(Vector2i(1, 0))
	_check(_pad.active and board.controller_cursor == _pad.cursor and _pad.cursor.x >= 0, "a nudge shows the cursor at %s" % _pad.cursor)
	var c: Vector2i = _pad.cursor
	await _nudge(Vector2i(-1, 0))
	_check(_pad.cursor == c + Vector2i(-1, 0), "JOY -1 0 moves one tile left")
	await _nudge(Vector2i(0, -1))
	_check(_pad.cursor == c + Vector2i(-1, -1), "JOY 0 -1 moves one tile up")
	await _nudge(Vector2i(1, 1))
	_check(_pad.cursor == c, "JOY 1 1 moves diagonally (right and down)")
	await _nudge(Vector2i(0, 1))
	_check(_pad.cursor == c + Vector2i(0, 1), "JOY 0 1 moves one tile down")
	for i in Globals.GRID_WIDTH + 2:
		await _nudge(Vector2i(-1, 0))
	_check(_pad.cursor.x == 0, "the cursor stops at the left edge (x 0)")
	for i in Globals.GRID_HEIGHT + 2:
		await _nudge(Vector2i(0, -1))
	_check(_pad.cursor == Vector2i(0, 0), "and at the top edge (0, 0)")
	for i in Globals.GRID_WIDTH + 2:
		await _nudge(Vector2i(1, 0))
	_check(_pad.cursor.x == Globals.GRID_WIDTH - 1, "and at the right edge (x %d)" % (Globals.GRID_WIDTH - 1))
	for i in Globals.GRID_HEIGHT + 2:
		await _nudge(Vector2i(1, 1))
	_check(_pad.cursor == Vector2i(Globals.GRID_WIDTH - 1, Globals.GRID_HEIGHT - 1), "and in the bottom-right corner, even pushed diagonally")

# Time is stepped by hand here, so the frame rate can't change the result
func _check_esp32_repeat() -> void:
	_link.set_process(false)
	_pad.cursor = Vector2i(2, 4)
	var n := _link.inputs_received
	_link.handle_line("JOY 1 0")
	_check(_pad.cursor == Vector2i(3, 4), "pushing the stick steps at once")
	_link._repeat_joystick(0.34)
	_check(_pad.cursor == Vector2i(3, 4), "held 340 ms: no repeat yet")
	_link._repeat_joystick(0.02)
	_check(_pad.cursor == Vector2i(4, 4), "held 360 ms: the first repeat (after 350 ms)")
	for i in 3:
		_link._repeat_joystick(0.121)
	_check(_pad.cursor == Vector2i(7, 4), "then one step every 120 ms (3 more in 363 ms)")
	_check(_link.inputs_received == n + 1, "a held stick counts as one input, not one per repeat")
	_link.handle_line("JOY 0 0")
	_link._repeat_joystick(2.0)
	_check(_pad.cursor == Vector2i(7, 4), "back to the centre: no more steps")
	_link.handle_line("JOY 1 0")
	_link._repeat_joystick(0.2)
	_link.handle_line("JOY 0 1")
	_check(_pad.cursor == Vector2i(8, 5), "a new direction steps at once (diagonal JOY 1 0 -> JOY 0 1: right, then down)")
	_link._repeat_joystick(0.3)
	_check(_pad.cursor == Vector2i(8, 5), "and restarts the 350 ms wait")
	_link._repeat_joystick(0.06)
	_check(_pad.cursor == Vector2i(8, 6), "then repeats in the new direction")
	_link.handle_line("JOY -1 0")
	_link._repeat_joystick(5.0)
	_check(_pad.cursor == Vector2i(0, 6), "held left for 5 s: stops at the edge")
	_link.handle_line("JOY 0 0")
	_link.set_process(true)

func _check_esp32_press() -> void:
	var sockets := _free_sockets()
	await _goto_esp(sockets[0])
	await _board("BTN SELECT_LONG")
	_check(not _pad.picker_open and _main.tower_mgr.selected_tower == null, "a long SELECT on a socket does not click (no menu opens)")
	await _board("BTN SELECT")
	_check(_pad.picker_open, "a short SELECT on a socket clicks: the tower menu opens")
	await _board("BTN SELECT_LONG")
	_check(not _pad.picker_open and not _main.tower_mgr.placed_towers.has(sockets[0]), "a long SELECT closes it, nothing built")
	ResourceManager.current_energy = 5000
	_main.tower_mgr.place_tower(sockets[1], Globals.TowerType.ANTIVIRUS_CANNON)
	await _goto_esp(sockets[1])
	await _board("BTN SELECT_LONG")
	_check(_main.tower_mgr.selected_tower == null, "a long SELECT on a tower does not select it")
	await _board("BTN SELECT")
	_check(_main.tower_mgr.selected_tower == _main.tower_mgr.placed_towers[sockets[1]], "a short SELECT selects it")
	await _board("BTN SELECT_LONG")
	_check(_main.tower_mgr.selected_tower == null, "a long SELECT deselects it (like Esc / right click)")
	Input.parse_input_event(_key(KEY_1))
	await _frames(2)
	await _board("BTN SELECT_LONG")
	_check(not _main.placement_mode, "a long SELECT leaves placement mode")

func _check_esp32_build() -> void:
	var towers: Array = Globals.get_unlocked_towers(Globals.current_level)
	var s := _free_sockets()[0]
	ResourceManager.current_energy = 1000
	await _goto_esp(s)
	await _board("BTN SELECT")
	var menu: TowerChoiceMenu = _pad.choice_menu
	await _frames(1)
	var r := menu.get_rect()
	_check(_pad.picker_open and menu.visible and menu.rows.size() == towers.size() and menu.index == 0,
		"SELECT on a socket opens the menu with the %d unlocked towers, the first highlighted" % towers.size())
	_check(r.position.x >= 0 and r.position.y >= 0 and r.end.x <= 1920 and r.end.y <= 1360, "the menu is fully on screen (%s)" % r)
	_check("hold SELECT = cancel" in menu._hint.text, "its hint says how to cancel on this board")
	await _nudge(Vector2i(0, 1))
	_check(menu.index == 1 and menu.rows[1].get_meta("mark").text == ">", "down highlights the next tower")
	await _nudge(Vector2i(0, -1))
	await _nudge(Vector2i(0, -1))
	_check(menu.index == towers.size() - 1, "up from the first wraps to the last")
	await _nudge(Vector2i(0, 1))
	await _nudge(Vector2i(0, 1))
	_check(menu.index == 1 and _pad.cursor == s, "the cursor stays on the socket while choosing")
	var e := ResourceManager.current_energy
	await _board("BTN SELECT")
	var built = _main.tower_mgr.placed_towers.get(s)
	_check(is_instance_valid(built) and built.tower_type == towers[1], "SELECT builds the highlighted tower (%s)" % Globals.TOWER_DATA[towers[1]].name)
	_check(ResourceManager.current_energy == e - Globals.TOWER_DATA[towers[1]].cost, "through the normal placement: its cost is paid")
	_check(not _pad.picker_open and not menu.visible, "and the menu closes")

	# refused when Energy is too low
	var s2 := _free_sockets()[0]
	await _goto_esp(s2)
	var cheapest: int = Globals.TOWER_DATA[towers[0]].cost
	ResourceManager.current_energy = cheapest - 1
	await _board("BTN SELECT")
	_check(menu.visible and "NEED" in menu.rows[0].get_meta("cost").text, "with too little Energy the menu marks the tower NEED %d" % cheapest)
	_check(_main.game_board.controller_cursor_mode == 2, "and the tile shows red with a cross")
	await _board("BTN SELECT")
	_check(not _main.tower_mgr.placed_towers.has(s2) and ResourceManager.current_energy == cheapest - 1, "SELECT is refused: nothing built, no Energy spent")
	_check(_messages.back().begins_with("NOT ENOUGH ENERGY"), "the HUD says NOT ENOUGH ENERGY")
	_check(_pad.picker_open, "the menu stays open (the player can pick something else or cancel)")
	await _board("BTN SELECT_LONG")
	_check(not _pad.picker_open, "a long SELECT closes it")
	ResourceManager.current_energy = 1000

func _check_esp32_panel() -> void:
	var panel: TowerInfoPanel = _main.tower_info_panel
	var tile: Vector2i = _main.tower_mgr.placed_towers.keys()[0]
	var tower = _main.tower_mgr.placed_towers[tile]
	ResourceManager.current_energy = 1000
	await _goto_esp(tile)
	await _board("BTN SELECT")
	_check(_main.tower_mgr.selected_tower == tower and panel.visible, "SELECT on a tower opens its panel")
	var e := ResourceManager.current_energy
	await _board("BTN SELECT")
	var buttons := panel.controller_buttons()
	_check(_pad.panel_index == 0 and panel._ctrl_lit == buttons[0] and ResourceManager.current_energy == e,
		"the first SELECT only highlights the first upgrade card (nothing bought by a double press)")
	var tier_before: int = tower.path_tiers["A"]
	await _board("BTN SELECT")
	_check(tower.path_tiers["A"] == tier_before + 1 and ResourceManager.current_energy < e, "the next SELECT buys it (Path A tier %d)" % tower.path_tiers["A"])
	await _nudge(Vector2i(0, 1))
	_check(_pad.panel_index == 1 and panel._ctrl_lit == panel.controller_buttons()[1], "down moves to the next button")
	await _nudge(Vector2i(0, -1))
	await _nudge(Vector2i(0, -1))
	var last: int = panel.controller_buttons().size() - 1
	_check(_pad.panel_index == last and panel._ctrl_lit == panel.sell_button, "up from the top wraps to Sell")
	var e2 := ResourceManager.current_energy
	await _board("BTN SELECT")
	_check(is_instance_valid(tower) and _main.tower_mgr.placed_towers.has(tile), "the first SELECT on Sell only arms it (as with the mouse)")
	await _board("BTN SELECT")
	_check(not _main.tower_mgr.placed_towers.has(tile) and ResourceManager.current_energy > e2, "the second sells the tower and refunds Energy")
	_check(not panel.visible and _pad.panel_index == -1, "the panel closes and the highlight resets")

	# a disabled button explains itself
	ResourceManager.current_energy = 5000
	var t2 := _free_sockets()[0]
	_main.tower_mgr.place_tower(t2, Globals.TowerType.ANTIVIRUS_CANNON)
	ResourceManager.current_energy = 0
	await _goto_esp(t2)
	await _board("BTN SELECT")
	await _board("BTN SELECT")
	_check(panel.controller_buttons()[0].disabled and panel._ctrl_lit == panel.controller_buttons()[0], "an upgrade you can't afford can still be highlighted")
	await _board("BTN SELECT")
	_check(panel.hint_label.visible and panel.hint_label.text != "", "and SELECT on it shows why: %s" % panel.hint_label.text)
	await _board("BTN SELECT_LONG")
	_check(_main.tower_mgr.selected_tower == null, "a long SELECT deselects the tower")
	ResourceManager.current_energy = 1000

func _check_esp32_overdrive() -> void:
	_oc.reset()
	_main.wave_mgr.current_wave = Globals.OVERCLOCK.unlock_wave_level_1  # Level 1 unlocks Overclock at wave 3
	var used := [0]
	var count := func(_e): used[0] += 1
	Events.overclock_used.connect(count)
	var e := ResourceManager.current_energy
	var n := _link.inputs_received
	await _board("BTN OVERDRIVE")
	_check(ResourceManager.current_energy == e + Globals.OVERCLOCK.energy and used[0] == 1, "BTN OVERDRIVE fires Overclock once (+%d Energy)" % Globals.OVERCLOCK.energy)
	_check(_oc.cooldown_left > 14.0 and _link.inputs_received == n + 1, "through OverclockManager.use(): the 15 s cooldown started")
	var e2 := ResourceManager.current_energy
	await _board("BTN OVERDRIVE")
	_check(ResourceManager.current_energy == e2 and used[0] == 1, "a second press during the cooldown is refused")
	_check(_messages.back() == "OVERCLOCK NOT READY", "and the HUD says OVERCLOCK NOT READY")
	Events.overclock_used.disconnect(count)
	_oc.reset()
	_main.wave_mgr.current_wave = 0

func _check_one_board() -> void:
	await _board("LINK DOWN")
	_check(_link.board == &"" and not _link.connected, "unplugging the ESP32 forgets it")
	var n := _link.inputs_received
	await _board("BTN SELECT")
	_check(_link.board == &"" and _link.inputs_received == n, "BTN SELECT alone (sent by both boards) doesn't decide which board it is")
	await _board("HELLO PZ2")
	_check(_link.board == &"uno" and _pad.board == &"uno", "then the Uno connects (HELLO PZ2)")
	var cur: Vector2i = _pad.cursor
	var e := ResourceManager.current_energy
	for line in ["JOY 1 0", "JOY 0 0", "BTN SELECT_LONG", "BTN OVERDRIVE"]:
		await _board(line)
	_check(_pad.cursor == cur and ResourceManager.current_energy == e and _link.inputs_received == n,
		"while the Uno is linked, the ESP32's lines are ignored")
	await _board("HB PZ3")
	_check(_link.board == &"uno", "an ESP32 heartbeat doesn't take over while the Uno is linked")
	await _board("JOY R")
	_check(_pad.cursor == Vector2i(mini(cur.x + 1, Globals.GRID_WIDTH - 1), cur.y), "the Uno's own JOY R still works")
	await _board("LINK DOWN")
	await _board("JOY 0 1")
	_check(_link.board == &"esp32", "after the Uno is unplugged, an ESP32-only line (JOY 0 1) identifies the ESP32")
	await _board("JOY 0 0")
