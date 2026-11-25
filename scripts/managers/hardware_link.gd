# hardware_link.gd — The Arduino controller (hardware/protocol_zero_controller/protocol_zero_controller.ino)
#
# The game hears the board through tools/hardware_bridge.py, because Godot has no serial port API:
#   board --serial--> bridge --UDP 127.0.0.1:9101--> this node
#       "HELLO PZ2", "HB"                          the board is there
#       "JOY U" / "JOY D" / "JOY L" / "JOY R"      one joystick step
#       "BTN SELECT" / "BTN OVERRIDE" / "BTN BACK" one button press
#       "LINK UP <port>" / "LINK DOWN"             from the bridge itself
# The board has no screen or lights, so the game sends nothing back.
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

var autostart_bridge: bool = true      # the checks turn this off
var connected: bool = false
var link_port: String = ""             # serial port the bridge reported
var inputs_received: int = 0           # joystick steps and button presses received (for tests and the report)
var last_input_ms: int = -1            # Time.get_ticks_msec() of the last one (latency tests)

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
	if _udp.bind(GAME_PORT, "127.0.0.1") == OK:
		_listening = true
	else:
		print("[HardwareLink] UDP port %d is busy; Arduino controller disabled, mouse and keyboard only" % GAME_PORT)
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
	if _controller == null or not is_instance_valid(_controller):
		return
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
	# "HELLO PZ2", "HB" and anything unknown only prove the board is there

func _count_input() -> void:
	inputs_received += 1
	last_input_ms = Time.get_ticks_msec()

func _set_connected(value: bool) -> void:
	if value == connected:
		return
	connected = value
	if connected:
		Events.show_message.emit("ARDUINO CONTROLLER CONNECTED", 2.5)
	else:
		Events.show_message.emit("ARDUINO CONTROLLER DISCONNECTED  -  mouse and keyboard still work", 3.0)
	Events.hardware_connection_changed.emit(connected)
