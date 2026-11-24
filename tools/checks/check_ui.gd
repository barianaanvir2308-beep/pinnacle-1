# check_ui.gd — Headless checks for tower selection and the floating upgrade panel
# Run: godot --headless --path . res://tools/checks/check_ui.tscn
extends Node

const CANNON = Globals.TowerType.ANTIVIRUS_CANNON
const SNIPER = Globals.TowerType.SNIPER_NODE

var _fails: int = 0
var _main: Node
var _tm: Node
var _panel: TowerInfoPanel

func _check(cond: bool, msg: String) -> void:
	if not cond:
		_fails += 1
	print(("  ok    " if cond else "  FAIL  ") + msg)

func _ready() -> void:
	_main = load("res://scenes/main/Main.tscn").instantiate()
	add_child(_main)
	await get_tree().process_frame
	Events.level_selected.emit(0)
	await get_tree().process_frame
	ResourceManager.current_energy = 5000
	ResourceManager.max_energy = 1000000  # these checks hand themselves lots of Energy; the real cap is 1000
	_main.get_node("Managers/CombatManager").set_physics_process(false)
	_tm = _main.get_node("Managers/TowerManager")
	_panel = _main.tower_info_panel

	await _check_selection_and_position()
	await _check_buying_with_cards()
	await _check_blocked_states()
	await _check_keys()
	await _check_sell()
	await _check_deselect_paths()

	print("check_ui: %d failure(s)" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)

func _place(cell: Vector2i, type: int = CANNON) -> Node:
	_tm.place_tower(cell, type)
	return _tm.placed_towers[cell]

func _click(cell: Vector2i) -> void:
	_main._on_world_click(Globals.grid_to_world(cell))

func _press(action: StringName) -> void:
	for pressed in [true, false]:
		var ev := InputEventAction.new()
		ev.action = action
		ev.pressed = pressed
		Input.parse_input_event(ev)
	await get_tree().process_frame

func _card(path: String, key: String):
	return _panel.cards[path][key]

func _check_selection_and_position() -> void:
	print("== clicking towers")
	var t = _place(Vector2i(1, 1))
	_check(not _panel.visible, "panel is hidden when nothing is selected")
	_click(Vector2i(2, 1))  # empty buildable tile
	_check(_tm.selected_tower == null and not _panel.visible, "clicking an empty tile selects nothing")
	_click(Vector2i(1, 1))
	await get_tree().process_frame
	_check(_tm.selected_tower == t and _panel.visible, "clicking a tower selects it and shows the panel")
	_check(t.selected, "the tower shows its range ring (selected)")
	_check(_panel._title.text == "ANTIVIRUS CANNON", "title shows the tower name")
	_check("HP 100/100" in _panel._stats.text and "DMG 15" in _panel._stats.text and "EVERY 1.00s" in _panel._stats.text,
		"stats line: %s" % _panel._stats.text)
	_check(_card("A", "header").text.begins_with("PATH A: HEURISTICS") and _card("B", "header").text.begins_with("PATH B: SCAN RATE"),
		"both paths are shown by name")
	_check("Signature Update" in _card("A", "tier_line").text and "NEXT: 50 ENERGY" in _card("A", "cost_line").text,
		"Path A shows its next tier and cost: %s / %s" % [_card("A", "tier_line").text, _card("A", "cost_line").text])
	_check(_card("B", "desc").text == "Fires every 0.7 s", "Path B shows what the next tier does")
	_check(not _card("A", "button").disabled and not _card("B", "button").disabled, "both upgrade buttons are enabled")
	_check(_panel.sell_button.text == "SELL  +60 ENERGY", "sell button shows the refund: %s" % _panel.sell_button.text)
	_tm.deselect_tower()

	# The panel must stay on the board and never cover the tower, wherever the tower is
	var screen := _panel.get_viewport_rect().size
	for cell in [Vector2i(1, 1), Vector2i(13, 1), Vector2i(1, 7), Vector2i(13, 7), Vector2i(7, 1)]:
		_tm.sell_tower(_tm.placed_towers[Vector2i(1, 1)]) if _tm.placed_towers.has(Vector2i(1, 1)) and cell != Vector2i(1, 1) else null
		var tower = _tm.placed_towers[cell] if _tm.placed_towers.has(cell) else _place(cell)
		_tm.select_tower(tower)
		await get_tree().process_frame
		var rect := Rect2(_panel.position, _panel.size)
		var tower_rect := Rect2(tower.global_position - Vector2(60, 60), Vector2(120, 120))
		var board := Rect2(0, Globals.GRID_OFFSET.y, screen.x, Globals.GRID_HEIGHT * Globals.TILE_SIZE)
		_check(board.encloses(rect) and not rect.intersects(tower_rect),
			"tower at %s: panel %s is on the board and clear of the tower" % [cell, rect])
		_tm.deselect_tower()
	for cell in _tm.placed_towers.keys():
		_tm.sell_tower(_tm.placed_towers[cell])

func _check_buying_with_cards() -> void:
	print("== buying through the panel")
	var t = _place(Vector2i(1, 1))
	_tm.select_tower(t)
	var before := ResourceManager.current_energy
	_card("A", "button").pressed.emit()
	await get_tree().process_frame
	_check(t.path_tiers["A"] == 1 and before - ResourceManager.current_energy == 50, "clicking Path A buys Tier 1 for 50")
	_check(_card("A", "cost_line").text.begins_with("OWNED 1/3"), "card now reads OWNED 1/3")
	_check("Deep Scan" in _card("A", "tier_line").text and "NEXT: 100 ENERGY" in _card("A", "cost_line").text,
		"Path A now offers Tier 2: %s / %s" % [_card("A", "tier_line").text, _card("A", "cost_line").text])
	_check(_panel.sell_button.text == "SELL  +90 ENERGY", "sell value follows what was paid (150 x 60%%): %s" % _panel.sell_button.text)
	_check(not _card("B", "button").disabled and _card("B", "status").text == "", "Path B1 is still on offer after A1")
	_card("B", "button").pressed.emit()
	_card("A", "button").pressed.emit()
	await get_tree().process_frame
	_check(t.path_tiers == {"A": 2, "B": 1} and t.chosen_path == "A" and "[CHOSEN]" in _card("A", "header").text,
		"A1 + B1 + A2: Tier 2 makes A the chosen path")
	_check(_card("B", "button").disabled and "LOCKED: you chose path A" in _card("B", "status").text,
		"Path B2 shows it is locked by the choice: %s" % _card("B", "status").text)
	_check("T2: " in _card("B", "tier_line").text, "locked B2 still shows its name and cost")
	_check(not _card("A", "button").disabled and _card("A", "status").text == "" and "Heuristic Engine" in _card("A", "tier_line").text,
		"Tier 3 is on offer at once on Level 1: %s" % _card("A", "tier_line").text)

func _check_blocked_states() -> void:
	print("== blocked states")
	var t = _tm.selected_tower
	Events.energy_changed.emit(ResourceManager.current_energy)  # the panel listens for this
	ResourceManager.current_energy = 10
	Events.energy_changed.emit(10)
	_check(_card("A", "button").disabled and "NOT ENOUGH ENERGY (290 more)" in _card("A", "status").text,
		"too expensive: %s" % _card("A", "status").text)
	_card("A", "button").pressed.emit()
	_check(t.path_tiers["A"] == 2 and ResourceManager.current_energy == 10, "pressing a blocked card buys nothing")
	ResourceManager.current_energy = 5000
	t.set_disabled(true, 30.0)
	_panel.refresh()
	_check("TOWER LOCKED" in _card("A", "status").text and _card("A", "button").disabled, "a locked tower shows TOWER LOCKED")
	t.set_disabled(false)
	_panel.refresh()

func _check_keys() -> void:
	print("== U key")
	var t2 = _place(Vector2i(2, 1))
	_tm.select_tower(t2)
	await _press(&"upgrade")
	_check(t2.path_tiers == {"A": 0, "B": 0} and _panel.hint_label.visible, "U with no chosen path buys nothing and shows a hint")
	_card("B", "button").pressed.emit()
	await _press(&"upgrade")
	_check(t2.path_tiers == {"A": 0, "B": 1} and t2.chosen_path == "", "U still waits while only Tier 1 is owned")
	_card("B", "button").pressed.emit()
	_check(t2.chosen_path == "B", "choosing a path by clicking Tier 2")
	var spent_before := ResourceManager.current_energy
	await _press(&"upgrade")
	_check(t2.path_tiers["B"] == 3 and spent_before - ResourceManager.current_energy == 300, "U buys the next tier of the chosen path (B3 for 300)")
	await _press(&"upgrade")
	_check(t2.path_tiers["B"] == 3 and "MAX TIER" in _card("B", "tier_line").text, "U on a maxed path does nothing; card reads MAX TIER")
	_tm.sell_tower(t2)

func _check_sell() -> void:
	print("== selling")
	var t = _tm.selected_tower if _tm.selected_tower != null else _place(Vector2i(6, 1))
	var cell := Globals.world_to_grid(t.position)
	_tm.select_tower(t)
	var value: int = t.get_sell_value()
	var before := ResourceManager.current_energy
	_panel.sell_button.pressed.emit()
	_check("CONFIRM SELL?" in _panel.sell_button.text and ResourceManager.current_energy == before and is_instance_valid(t),
		"first click only arms the sale: %s" % _panel.sell_button.text)
	_panel._sell_armed = 0.01
	await get_tree().create_timer(0.3).timeout
	_check(_panel.sell_button.text.begins_with("SELL  +") and is_instance_valid(t), "an armed sale cancels itself after a moment")
	_panel.sell_button.pressed.emit()
	_panel.sell_button.pressed.emit()
	await get_tree().process_frame
	_check(ResourceManager.current_energy - before == value and not _tm.placed_towers.has(cell),
		"second click sells for +%d and frees the cell" % value)
	_check(not _panel.visible and _tm.selected_tower == null, "panel closes after selling")

	var s = _place(Vector2i(7, 1))
	_tm.select_tower(s)
	before = ResourceManager.current_energy
	await _press(&"sell")
	_check("CONFIRM" in _panel.sell_button.text, "S key arms the sale")
	await _press(&"sell")
	_check(ResourceManager.current_energy - before == 60 and not _panel.visible, "pressing S again sells (+60)")

func _check_deselect_paths() -> void:
	print("== closing the panel")
	var t = _place(Vector2i(1, 1))
	_click(Vector2i(1, 1))
	_check(_panel.visible, "selected")
	var right := InputEventMouseButton.new()
	right.button_index = MOUSE_BUTTON_RIGHT
	right.pressed = true
	_main._unhandled_input(right)
	_check(not _panel.visible and _tm.selected_tower == null, "right-click deselects")

	_click(Vector2i(1, 1))
	_click(Vector2i(12, 1))
	_check(not _panel.visible, "clicking an empty tile deselects")

	_click(Vector2i(1, 1))
	Events.tower_placement_started.emit(CANNON)
	_check(not _panel.visible and _main.placement_mode, "starting to place a tower closes the panel")
	_main._on_tower_placement_cancelled()

	_click(Vector2i(1, 1))
	t.take_tower_damage(99999.0)
	await get_tree().process_frame
	_check(not _panel.visible and _tm.selected_tower == null, "panel closes when the selected tower is destroyed")

	var s = _place(Vector2i(2, 1), SNIPER)
	_click(Vector2i(2, 1))
	await get_tree().process_frame
	_check(_panel.visible and _panel._no_upgrades.visible and not _card("A", "panel").visible, "a tower with no upgrades shows only a note and Sell")
	_main.game_state_mgr.change_state(Globals.GameState.GAME_OVER)
	_check(not _panel.visible and _tm.selected_tower == null, "panel closes when the game ends")
