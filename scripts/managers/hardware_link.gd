# hardware_link.gd — The controller boards (hardware/README.md)
#
# The game hears the board through tools/hardware_bridge.py, because Godot has no serial port API:
#   board --serial--> bridge --UDP 127.0.0.1:9101--> this node
# Two boards speak two message sets. Only one is listened to at a time: the first board identified is locked in
# until it disconnects, and lines in the other board's format are ignored meanwhile.
#   Arduino Uno controller, PZ2 (hardware/protocol_zero_controller):
#       "HELLO PZ2", "HB"                          the board is there (its heartbeat has no label)
#       "JOY U" / "JOY D" / "JOY L" / "JOY R"      one joystick step (the board repeats it while held)
#       "BTN SELECT" / "BTN OVERRIDE" / "BTN BACK" one button press
#   ESP32 controller, PZ3 (hardware/protocol_zero_esp32):
#       "HELLO PZ3", "HB PZ3"                      the board is there
#       "JOY <dx> <dy>"                            the stick's direction (-1, 0, 1 each) whenever it changes; this
#                                                  node steps the cursor at once, then repeats while it is held
#       "BTN SELECT" / "BTN SELECT_LONG" / "BTN OVERDRIVE"   click / back (SELECT held 600 ms) / Overclock
#   From the bridge itself: "LINK UP <port>" / "LINK DOWN"
# Neither board has a screen or lights, so the game sends nothing back.
#
# The controller is optional. It only counts as connected while the board itself is heard from (it sends "HB"
# every second); with no board, no bridge or no Python the game simply plays with mouse and keyboard as usual.
# The board never decides anything: each line becomes a call on ControllerInput, which uses the same manager
# functions as the mouse and keyboard, so every rule (Energy, unlock, cooldown, System Load) still applies.
class_name HardwareLink
extends Node

const GAME_PORT: int = 9101            # we listen here
const BRIDGE_PORT: int = 9102          # the bridge listens here
const SIGNAL_TIMEOUT: float = 3.0      # no line from the board for this long = disconnected
const BRIDGE_SCRIPT: String = "res://tools/hardware_bridge.py"
const JOY_STEPS: Dictionary = {
	"JOY U": Vector2i(0, -1), "JOY D": Vector2i(0, 1), "JOY L": Vector2i(-1, 0), "JOY R": Vector2i(1, 0),
}
const BOARD_UNO: StringName = &"uno"       # PZ2: Arduino Uno joystick controller, 3 buttons
const BOARD_ESP32: StringName = &"esp32"   # PZ3: ESP32 controller, 2 buttons
const BOARD_NAMES: Dictionary = {&"uno": "ARDUINO", &"esp32": "ESP32"}
# Lines only one of the boards sends: they also identify a board that hasn't said who it is yet
const UNO_ONLY: Array = ["JOY U", "JOY D", "JOY L", "JOY R", "BTN OVERRIDE", "BTN BACK"]
const ESP32_ONLY: Array = ["BTN SELECT_LONG", "BTN OVERDRIVE"]
const REPEAT_FIRST: float = 0.35           # ESP32 stick held: the second step comes after this long...
const REPEAT_NEXT: float = 0.12            # ...then one step this often

var autostart_bridge: bool = true      # the checks turn this off
# Added to both ports. 0 in the game; check_hardware sets it so it can run while the real game and bridge are open.
static var port_offset: int = 0
var connected: bool = false
var link_port: String = ""             # serial port the bridge reported
var inputs_received: int = 0           # joystick steps and button presses received (for tests and the report)
var last_input_ms: int = -1            # Time.get_ticks_msec() of the last one (latency tests)
var board: StringName = &""            # which board is talking: BOARD_UNO, BOARD_ESP32, or "" (not known yet)
var joy_held: Vector2i = Vector2i.ZERO # ESP32 stick direction being held
var _repeat_left: float = 0.0

var _udp: PacketPeerUDP
var _listening: bool = false
var _since_board: float = INF
var _bridge_pid: int = -1
var _controller: ControllerInput

func setup(controller: ControllerInput) -> void:
	_controller = controller
	add_to_group("hardware_link")

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # menus and the pause screen still hear the controller
	_udp = PacketPeerUDP.new()
	if _udp.bind(GAME_PORT + port_offset, "127.0.0.1") == OK:
		_listening = true
	else:
		print("[HardwareLink] UDP port %d is busy; controller disabled, mouse and keyboard only" % (GAME_PORT + port_offset))
	if _listening and autostart_bridge:
		_start_bridge()

func _exit_tree() -> void:
	if _bridge_pid > 0:
		OS.kill(_bridge_pid)
		_bridge_pid = -1
	if _udp != null:
		_udp.close()

# Starts tools/hardware_bridge.py in the background if Python is there. Silent if it can't: the game works without it.
func _start_bridge() -> void:
	if OS.has_feature("web") or DisplayServer.get_name() == "headless":
		return
	var script_path := ProjectSettings.globalize_path(BRIDGE_SCRIPT)
	if not FileAccess.file_exists(BRIDGE_SCRIPT):
		return  # exported builds: run the bridge by hand (see the report, appendix E)
	var candidates: Array = ["py", "python"] if OS.get_name() == "Windows" else ["python3", "python"]
	if OS.get_name() == "macOS":  # apps started from Finder don't see Homebrew's PATH
		for p in ["/opt/homebrew/bin/python3", "/usr/local/bin/python3"]:
			if FileAccess.file_exists(p):
				candidates.push_front(p)
	for python in candidates:
		var pid := OS.create_process(python, [script_path])
		if pid > 0:
			_bridge_pid = pid
			print("[HardwareLink] started hardware bridge with %s (pid %d)" % [python, pid])
			return
	print("[HardwareLink] Python not found; Arduino controller disabled, mouse and keyboard only")

func _process(delta: float) -> void:
	if not _listening:
		return
	while _udp.get_available_packet_count() > 0:
		var text := _udp.get_packet().get_string_from_ascii()
		for line in text.split("\n", false):
			handle_line(line.strip_edges())
	_since_board += delta
	_set_connected(_since_board < SIGNAL_TIMEOUT)
	_repeat_joystick(delta)

# ESP32: a held stick keeps stepping (first repeat after REPEAT_FIRST, then every REPEAT_NEXT)
func _repeat_joystick(delta: float) -> void:
	if board != BOARD_ESP32 or joy_held == Vector2i.ZERO or not connected:
		return
	_repeat_left -= delta
	while _repeat_left <= 0.0:
		_repeat_left += REPEAT_NEXT
		if _controller != null and is_instance_valid(_controller):
			_controller.move(joy_held)

# One line from the bridge. Public so tests can inject lines without a board.
func handle_line(line: String) -> void:
	if line.is_empty():
		return
	if line.begins_with("LINK UP"):
		link_port = line.substr(8)
		return
	if line == "LINK DOWN":
		_since_board = INF
		_set_connected(false)
		return
	# Anything else comes from the board itself, so it proves the board is there
	_since_board = 0.0
	_set_connected(true)
	if not _identify(line):
		return
	if _controller == null or not is_instance_valid(_controller):
		return
	if board == BOARD_UNO:
		_handle_uno(line)
	else:
		_handle_esp32(line)

# Works out which board is talking. Returns false when the line isn't a controller input to act on: a
# handshake or heartbeat, a line before the board is known, or a line in the other board's format.
func _identify(line: String) -> bool:
	match line:
		"HELLO PZ2":
			_set_board(BOARD_UNO)       # a handshake means a board (re)started: it always decides
			return false
		"HELLO PZ3":
			_set_board(BOARD_ESP32)
			return false
		"HB":
			if board == &"":
				_set_board(BOARD_UNO)   # the Uno's heartbeat has no label
			return false
		"HB PZ3":
			if board == &"":
				_set_board(BOARD_ESP32)
			return false
	if board == &"":
		if UNO_ONLY.has(line):
			_set_board(BOARD_UNO)
		elif ESP32_ONLY.has(line) or _parse_joy(line) != null:
			_set_board(BOARD_ESP32)
		else:
			return false                # e.g. BTN SELECT, which both send: wait for the heartbeat (1 s)
	if board == BOARD_UNO:
		return UNO_ONLY.has(line) or line == "BTN SELECT"
	return ESP32_ONLY.has(line) or line == "BTN SELECT" or _parse_joy(line) != null

func _handle_uno(line: String) -> void:
	if JOY_STEPS.has(line):
		_count_input()
		_controller.move(JOY_STEPS[line])
	elif line == "BTN SELECT":
		_count_input()
		_controller.press_select()
	elif line == "BTN OVERRIDE":
		_count_input()
		_controller.press_override()
	elif line == "BTN BACK":
		_count_input()
		_controller.press_back()

func _handle_esp32(line: String) -> void:
	var joy = _parse_joy(line)
	if joy != null:
		_set_joy(joy)
	elif line == "BTN SELECT":
		_count_input()
		_controller.press_select()
	elif line == "BTN SELECT_LONG":
		_count_input()
		_controller.press_back()        # held SELECT = back, like Esc or a right click
	elif line == "BTN OVERDRIVE":
		_count_input()
		_controller.press_override()

# "JOY <dx> <dy>" with each value -1, 0 or 1 -> Vector2i, or null for anything else
func _parse_joy(line: String):
	var parts := line.split(" ", false)
	if parts.size() != 3 or parts[0] != "JOY":
		return null
	for p in [parts[1], parts[2]]:
		if not (p in ["-1", "0", "1"]):
			return null
	return Vector2i(int(parts[1]), int(parts[2]))

# The ESP32 stick changed direction: one step now, and the repeat timer starts again
func _set_joy(dir: Vector2i) -> void:
	if dir == joy_held:
		return
	joy_held = dir
	_repeat_left = REPEAT_FIRST
	if dir != Vector2i.ZERO:
		_count_input()
		_controller.move(dir)

func _set_board(kind: StringName) -> void:
	if kind == board:
		return
	board = kind
	joy_held = Vector2i.ZERO
	if _controller != null and is_instance_valid(_controller):
		_controller.board = kind
	Events.show_message.emit("%s CONTROLLER CONNECTED" % BOARD_NAMES[kind], 2.5)

func _count_input() -> void:
	inputs_received += 1
	last_input_ms = Time.get_ticks_msec()

func _set_connected(value: bool) -> void:
	if value == connected:
		return
	connected = value
	if not connected:
		# the board is gone: forget which one it was, so the next board to connect decides
		if board != &"":
			Events.show_message.emit("%s CONTROLLER DISCONNECTED  -  mouse and keyboard still work" % BOARD_NAMES[board], 3.0)
		board = &""
		joy_held = Vector2i.ZERO
		if _controller != null and is_instance_valid(_controller):
			_controller.board = &""
	Events.hardware_connection_changed.emit(connected)
