# check_hardware.gd — Headless checks for the Arduino console link (scripts/managers/hardware_link.gd)
# Run: godot --headless --path . res://tools/checks/check_hardware.tscn
# This check plays the part of tools/hardware_bridge.py: it listens on UDP 9102 and sends board lines to the game on
# UDP 9101, so the real network path is tested without a board. It checks that the game is unchanged with no console,
# that the console only counts while the board is heard from, the kill count and Overdrive state messages, that one
# button press fires Overdrive exactly once (and is refused during the cooldown), and it measures the delay from a
# "BTN OVERDRIVE" packet to the Energy being added.
extends Node

var _fails: int = 0
var _main: Node
var _link: HardwareLink
var _oc: OverclockManager
var _bridge: PacketPeerUDP
var _received: Array[String] = []
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

	_main = load("res://scenes/main/Main.tscn").instantiate()
	add_child(_main)
	await get_tree().process_frame
	_link = _main.hardware_link
	_oc = _main.overclock_mgr
	_check(_link != null and _link.is_inside_tree(), "Main creates a HardwareLink under Managers")
	Events.level_selected.emit(1)  # Dual Bus: Overclock is unlocked from the start
	await _frames(3)
	_main.get_node("Managers/CombatManager").set_physics_process(false)

	print("== no console plugged in")
	await _check_offline()
	print("== console connects")
	await _check_connect()
	print("== kill count")
	await _check_kills()
	print("== Overdrive button")
	await _check_button()
	print("== state while paused")
	await _check_pause()
	print("== console lost")
	await _check_disconnect()

	print("check_hardware: %d failure(s)" % _fails)
	_bridge.close()
	get_tree().quit(1 if _fails > 0 else 0)

# ---- helpers ----
func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _board(line: String) -> void:
	_bridge.put_packet((line + "\n").to_ascii_buffer())

func _drain() -> void:
	while _bridge.get_available_packet_count() > 0:
		for l in _bridge.get_packet().get_string_from_ascii().split("\n", false):
			_received.append(l)

# Waits up to `timeout` s for the game to send `line`; true if it did
func _expect(line: String, timeout: float = 0.5) -> bool:
	var t := 0.0
	while t < timeout:
		_drain()
		if line in _received:
			return true
		await get_tree().process_frame
		t += get_process_delta_time()
	return false

# ---- checks ----
func _check_offline() -> void:
	_check(not _link.connected, "not connected when nothing has been heard")
	_check(not _main.hud.console_label.visible, "no CONSOLE LINKED label")
	_board("LINK UP /dev/ttyACM0")
	await _frames(3)
	_check(not _link.connected, "a bridge with a port open is not enough: the board itself must talk")
	_check(_link.link_port == "/dev/ttyACM0", "the bridge's port is remembered")
	_drain()
	_check(_received.is_empty(), "nothing is sent to the board while it is not connected")
	var e := ResourceManager.current_energy
	Input.parse_input_event(_key(KEY_O))
	await _frames(2)
	_check(ResourceManager.current_energy == e + Globals.OVERCLOCK.energy, "the O key still fires Overclock with no console (+150)")
	_oc.reset()
	await _frames(1)

func _check_connect() -> void:
	_received.clear()
	_board("HELLO PZ1")
	await _frames(3)
	_check(_link.connected, "connected after the board's HELLO")
	_check(_main.hud.console_label.visible, "HUD shows CONSOLE LINKED")
	_check("ARDUINO CONSOLE CONNECTED" in _messages, "the player is told the console connected")
	_check(await _expect("S READY"), "the board is told Overdrive is READY")
	_check(await _expect("K 0"), "the board gets the kill count (0)")

func _check_kills() -> void:
	_received.clear()
	for i in 3:  # straight to the link, so the wave logic in main.gd doesn't react to fake kills
		_link._on_enemy_defeated(Globals.EnemyType.BASIC_VIRUS, 0, Vector2.ZERO)
	_check(await _expect("K 3"), "three kills -> K 3")
	_check(_link.kills == 3, "kill counter is 3")

func _check_button() -> void:
	_received.clear()
	_board("HB")
	var e := ResourceManager.current_energy
	var t0 := Time.get_ticks_usec()
	_board("BTN OVERDRIVE")
	var waited := 0
	while ResourceManager.current_energy == e and waited < 60:
		await get_tree().process_frame
		waited += 1
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	_check(ResourceManager.current_energy == mini(e + Globals.OVERCLOCK.energy, Globals.MAX_ENERGY), "BTN OVERDRIVE fires Overclock (+150 Energy)")
	print("  info  packet -> Overclock applied in %.1f ms (%d frames)" % [ms, waited])
	_check(ms < 100.0, "the game reacts within 100 ms")
	_check(_link.button_presses == 1, "exactly one Overdrive request counted")
	_check(_oc.cooldown_left > 14.0, "cooldown started (15 s)")
	_check(await _expect("S COOLDOWN 15"), "the board is told COOLDOWN 15 straight away")
	var e2 := ResourceManager.current_energy
	_messages.clear()
	_board("BTN OVERDRIVE")
	await _frames(3)
	_check(ResourceManager.current_energy == e2, "a second press during the cooldown is refused (no Energy)")
	_check("OVERDRIVE NOT READY" in _messages, "and the HUD says OVERDRIVE NOT READY")
	_oc.reset()
	_received.clear()
	_check(await _expect("S READY"), "after the cooldown the board is told READY again")

func _check_pause() -> void:
	_received.clear()
	_main.game_state_mgr.change_state(Globals.GameState.PAUSED)
	_check(await _expect("S LOCKED"), "paused -> LOCKED (LED off)")
	_main.game_state_mgr.change_state(Globals.GameState.BUILD_PHASE)
	_received.clear()
	_check(await _expect("S READY"), "resumed -> READY")
	_link._on_level_selected(1)
	await _frames(1)
	_check(_link.kills == 0, "starting a level resets the kill count")

func _check_disconnect() -> void:
	_board("LINK DOWN")
	await _frames(2)
	_check(not _link.connected, "LINK DOWN disconnects at once")
	_check(not _main.hud.console_label.visible, "CONSOLE LINKED label hidden")
	_board("HB")
	await _frames(2)
	_check(_link.connected, "a heartbeat reconnects")
	await get_tree().create_timer(HardwareLink.SIGNAL_TIMEOUT + 0.3).timeout
	_check(not _link.connected, "silence for 3 s (board unplugged) disconnects")
	var e := ResourceManager.current_energy
	Input.parse_input_event(_key(KEY_O))
	await _frames(2)
	_check(ResourceManager.current_energy > e, "mouse and keyboard keep working after the console is lost")

func _key(code: Key) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.keycode = code
	ev.pressed = true
	return ev
