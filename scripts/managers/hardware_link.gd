# hardware_link.gd — The Arduino "Overdrive" console (hardware/protocol_zero_console/protocol_zero_console.ino)
#
# The game talks to the board through tools/hardware_bridge.py, because Godot has no serial port API:
#   board --serial--> bridge --UDP 127.0.0.1:9101--> this node     "HELLO PZ1", "HB", "BTN OVERDRIVE", "LINK UP/DOWN"
#   board <--serial-- bridge <--UDP 127.0.0.1:9102-- this node     "K <kills>", "S READY|COOLDOWN <s>|LOCKED|CRASH", "PING"
#
# The console is optional. It only counts as connected while the board itself is heard from (it sends "HB" every
# second); with no board, no bridge or no Python the game simply plays with mouse and keyboard as usual.
# The board never decides anything: "BTN OVERDRIVE" calls OverclockManager.use(), exactly like the O key, so every
# rule (unlock, cooldown, System Load, crash) still applies.
class_name HardwareLink
extends Node

const GAME_PORT: int = 9101            # we listen here
const BRIDGE_PORT: int = 9102          # the bridge listens here
const SIGNAL_TIMEOUT: float = 3.0      # no line from the board for this long = disconnected
const KEEPALIVE: float = 1.0           # resend state and kill count this often while connected
const BRIDGE_SCRIPT: String = "res://tools/hardware_bridge.py"

var autostart_bridge: bool = true      # the checks turn this off
var kills: int = 0
var connected: bool = false
var link_port: String = ""             # serial port the bridge reported
var last_state: String = ""            # last "S ..." line sent
var button_presses: int = 0            # Overdrive requests received (for tests and the report)
var last_button_ms: int = -1           # Time.get_ticks_msec() of the last request (latency tests)

var _udp: PacketPeerUDP
var _listening: bool = false
var _since_board: float = INF
var _keepalive_left: float = 0.0
var _bridge_pid: int = -1
var _overclock: Node
var _state_mgr: Node

func setup(overclock_mgr: Node, state_mgr: Node) -> void:
	_overclock = overclock_mgr
	_state_mgr = state_mgr
	add_to_group("hardware_link")

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # keep the LCD and LED right while the game is paused
	Events.enemy_defeated.connect(_on_enemy_defeated)
	Events.level_selected.connect(_on_level_selected)
	_udp = PacketPeerUDP.new()
	if _udp.bind(GAME_PORT, "127.0.0.1") == OK:
		_listening = true
		_udp.set_dest_address("127.0.0.1", BRIDGE_PORT)
	else:
		print("[HardwareLink] UDP port %d is busy; Arduino console disabled, mouse and keyboard only" % GAME_PORT)
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
	print("[HardwareLink] Python not found; Arduino console disabled, mouse and keyboard only")

func _process(delta: float) -> void:
	if not _listening:
		return
	while _udp.get_available_packet_count() > 0:
		var text := _udp.get_packet().get_string_from_ascii()
		for line in text.split("\n", false):
			handle_line(line.strip_edges())
	_since_board += delta
	_set_connected(_since_board < SIGNAL_TIMEOUT)
	if not connected:
		return
	var state := overdrive_state()
	_keepalive_left -= delta
	if state != last_state or _keepalive_left <= 0.0:
		if _keepalive_left <= 0.0:
			_keepalive_left = KEEPALIVE
			send("PING")
			send("K %d" % kills)
		last_state = state
		send(state)

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
	if line == "BTN OVERDRIVE":
		button_presses += 1
		last_button_ms = Time.get_ticks_msec()
		_on_overdrive_pressed()

func _on_overdrive_pressed() -> void:
	if _overclock == null or not is_instance_valid(_overclock):
		return
	if not _overclock.use():
		Events.show_message.emit("OVERDRIVE NOT READY", 1.5)
	last_state = ""  # push the new state straight away

# The Overdrive state line for the LCD and LED (handoff 8.5)
func overdrive_state() -> String:
	if _overclock == null or not is_instance_valid(_overclock):
		return "S LOCKED"
	if _overclock.towers_paused():
		return "S CRASH"
	if not _overclock.is_unlocked() or not _overclock.in_play() or get_tree().paused:
		return "S LOCKED"
	if _overclock.cooldown_left > 0.0:
		return "S COOLDOWN %d" % ceili(_overclock.cooldown_left)
	return "S READY"

func send(line: String) -> void:
	if _listening:
		_udp.put_packet((line + "\n").to_ascii_buffer())

func _set_connected(value: bool) -> void:
	if value == connected:
		return
	connected = value
	if connected:
		last_state = ""
		_keepalive_left = 0.0  # send everything at once
		Events.show_message.emit("ARDUINO CONSOLE CONNECTED", 2.5)
	else:
		Events.show_message.emit("ARDUINO CONSOLE DISCONNECTED  -  mouse and keyboard still work", 3.0)
	Events.hardware_connection_changed.emit(connected)

func _on_enemy_defeated(_type: int, _reward: int, _pos: Vector2) -> void:
	kills += 1
	if connected:
		send("K %d" % kills)

func _on_level_selected(_level_index: int) -> void:
	kills = 0
	if connected:
		send("K 0")
