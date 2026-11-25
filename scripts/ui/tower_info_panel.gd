# tower_info_panel.gd — Floating panel beside the selected tower
# Shows the tower's stats, its two upgrade paths (the NEXT tier of each: name, cost, effect and
# why it's blocked) and a Sell button. Created by main.gd; shown and hidden through the
# tower_selected / tower_deselected events that TowerManager emits.
class_name TowerInfoPanel
extends PanelContainer

const PANEL_WIDTH: float = 380.0
const PANEL_PADDING: float = 14.0
const CARD_PADDING: float = 10.0
const SELL_CONFIRM_SECONDS: float = 2.5
const HINT_SECONDS: float = 2.5
const REFRESH_INTERVAL: float = 0.2
const SCREEN_MARGIN: float = 8.0

const COLOR_TEXT := Color(0.9, 1.0, 0.9)
const COLOR_DIM := Color(0.6, 0.66, 0.72)
const COLOR_WARN := Color(1.0, 0.6, 0.2)
const COLOR_BAD := Color(1.0, 0.3, 0.3)

var tower_mgr: Node
var tower: Node = null
# "A" / "B" -> {panel, button, header, tier_line, desc, status, style_ok, style_off}
var cards: Dictionary = {}
var sell_button: Button
var repair_button: Button
var hint_label: Label

var _title: Label
var _stats: Label
var _no_upgrades: Label
var _sell_armed: float = 0.0
var _hint_time: float = 0.0
var _refresh_time: float = 0.0

func setup(manager: Node) -> void:
	tower_mgr = manager
	_build()
	visible = false
	Events.tower_selected.connect(_on_tower_selected)
	Events.tower_deselected.connect(_on_tower_deselected)
	Events.tower_upgraded.connect(func(_t, _g, _p, _tier): refresh())
	Events.energy_changed.connect(func(_e): refresh())

# =============================================================================
# BUILDING THE UI
# =============================================================================

func _build() -> void:
	custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	add_theme_stylebox_override("panel", _box(Color(0.04, 0.04, 0.09, 0.96), Color(0.2, 0.6, 1.0, 0.7), 2, 8, PANEL_PADDING))
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	add_child(vbox)

	var inner := PANEL_WIDTH - PANEL_PADDING * 2.0
	_title = _label(28, COLOR_TEXT, inner)
	_title.autowrap_mode = TextServer.AUTOWRAP_OFF
	vbox.add_child(_title)
	_stats = _label(19, COLOR_DIM, inner)
	vbox.add_child(_stats)
	_no_upgrades = _label(19, COLOR_DIM, inner)
	_no_upgrades.text = "No upgrades for this tower."
	vbox.add_child(_no_upgrades)

	for path in ["A", "B"]:
		vbox.add_child(_build_card(path, inner))

	hint_label = _label(18, COLOR_WARN, inner)
	hint_label.visible = false
	vbox.add_child(hint_label)

	repair_button = Button.new()
	Audio.ui(repair_button)
	repair_button.focus_mode = Control.FOCUS_NONE
	repair_button.custom_minimum_size = Vector2(0, 44)
	repair_button.add_theme_font_size_override("font_size", 20)
	repair_button.add_theme_color_override("font_color", COLOR_TEXT)
	repair_button.add_theme_color_override("font_disabled_color", COLOR_DIM)
	repair_button.add_theme_stylebox_override("normal", _box(Color(0.06, 0.1, 0.08), Color(0.0, 1.0, 0.53, 0.7), 2, 6, 6))
	repair_button.add_theme_stylebox_override("hover", _box(Color(0.1, 0.18, 0.14), Color(0.0, 1.0, 0.53), 2, 6, 6))
	repair_button.add_theme_stylebox_override("disabled", _box(Color(0.05, 0.05, 0.07), Color(0.3, 0.3, 0.36, 0.7), 2, 6, 6))
	repair_button.pressed.connect(_on_repair_pressed)
	repair_button.visible = false
	vbox.add_child(repair_button)

	sell_button = Button.new()
	Audio.ui(sell_button)
	sell_button.focus_mode = Control.FOCUS_NONE
	sell_button.custom_minimum_size = Vector2(0, 48)
	sell_button.add_theme_font_size_override("font_size", 22)
	sell_button.add_theme_color_override("font_color", COLOR_TEXT)
	sell_button.add_theme_stylebox_override("normal", _box(Color(0.08, 0.08, 0.12), Color(0.5, 0.5, 0.6, 0.6), 2, 6, 6))
	sell_button.add_theme_stylebox_override("hover", _box(Color(0.15, 0.15, 0.2), COLOR_WARN, 2, 6, 6))
	sell_button.pressed.connect(_on_sell_pressed)
	vbox.add_child(sell_button)

func _build_card(path: String, inner: float) -> Control:
	var card := PanelContainer.new()
	var accent: Color = Globals.PATH_B_COLOR if path == "B" else Color.WHITE
	var style_ok := _box(Color(0.06, 0.06, 0.11), accent, 2, 6, CARD_PADDING)
	var style_off := _box(Color(0.04, 0.04, 0.07), Color(0.3, 0.3, 0.36, 0.7), 2, 6, CARD_PADDING)
	card.add_theme_stylebox_override("panel", style_ok)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(v)
	var width := inner - CARD_PADDING * 2.0
	var header := _label(20, accent, width)
	var tier_line := _label(20, COLOR_TEXT, width)
	var desc := _label(17, COLOR_DIM, width)
	var cost_line := _label(18, COLOR_TEXT, width)
	var status := _label(17, COLOR_WARN, width)
	for l in [header, tier_line, desc, cost_line, status]:
		v.add_child(l)

	# A transparent button over the whole card takes the clicks
	var button := Button.new()
	Audio.ui(button)
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	button.add_theme_stylebox_override("disabled", StyleBoxEmpty.new())
	button.add_theme_stylebox_override("pressed", _box(Color(1, 1, 1, 0.12), Color(0, 0, 0, 0), 0, 6, 0))
	button.add_theme_stylebox_override("hover", _box(Color(1, 1, 1, 0.07), Color(0, 0, 0, 0), 0, 6, 0))
	button.pressed.connect(_on_card_pressed.bind(path))
	card.add_child(button)

	cards[path] = {"panel": card, "button": button, "header": header, "tier_line": tier_line,
		"desc": desc, "cost_line": cost_line, "status": status, "style_ok": style_ok, "style_off": style_off}
	return card

func _label(font_size: int, color: Color, width: float) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(width, 0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _box(bg: Color, border: Color, border_width: int, radius: int, padding: float) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_width)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(padding)
	return s

# =============================================================================
# SHOWING / HIDING
# =============================================================================

# =============================================================================
# CONTROLLER (joystick + SELECT, see controller_input.gd)
# =============================================================================

const COLOR_FOCUS := Color(0.176, 0.886, 1.0)  # cyan #2DE2FF: focus and selection (docs/ui_hud_design.md)
var _ctrl_lit: Button = null

# The panel's buttons in screen order, as the joystick steps through them: upgrade cards, Repair, Sell
func controller_buttons() -> Array:
	var out: Array = []
	for path in ["A", "B"]:
		if cards.has(path) and cards[path].panel.visible:
			out.append(cards[path].button)
	if repair_button.visible:
		out.append(repair_button)
	if sell_button.visible:
		out.append(sell_button)
	return out

# Lights one button with a cyan frame (-1 = none). Disabled buttons are lit too, so the player can read why.
func controller_highlight(index: int) -> void:
	var buttons := controller_buttons()
	var target: Button = buttons[index] if index >= 0 and index < buttons.size() else null
	if target == _ctrl_lit:
		return
	if _ctrl_lit != null and is_instance_valid(_ctrl_lit):
		for slot in ["normal", "disabled"]:
			_ctrl_lit.add_theme_stylebox_override(slot, _ctrl_lit.get_meta("ctrl_" + slot))
	_ctrl_lit = target
	if target == null:
		return
	for slot in ["normal", "disabled"]:
		var original: StyleBox = target.get_theme_stylebox(slot)
		target.set_meta("ctrl_" + slot, original)
		var lit := StyleBoxFlat.new()
		if original is StyleBoxFlat:
			lit = original.duplicate()
		else:
			lit.bg_color = Color(COLOR_FOCUS, 0.08)
			lit.set_corner_radius_all(6)
		lit.border_color = COLOR_FOCUS
		lit.set_border_width_all(3)
		target.add_theme_stylebox_override(slot, lit)

# SELECT on a lit button: exactly what a mouse click on it does. A disabled one explains itself instead.
func controller_press(index: int) -> void:
	var buttons := controller_buttons()
	if index < 0 or index >= buttons.size():
		return
	var button: Button = buttons[index]
	if not button.disabled:
		button.pressed.emit()
		return
	for path in cards:
		if cards[path].button == button:
			_show_hint(cards[path].status.text if cards[path].status.text != "" else "Not available")
			return
	_show_hint(button.text)

func _on_tower_selected(selected: Node) -> void:
	tower = selected
	_sell_armed = 0.0
	_hint_time = 0.0
	hint_label.visible = false
	visible = true
	refresh()

func _on_tower_deselected() -> void:
	controller_highlight(-1)
	tower = null
	visible = false

func _process(delta: float) -> void:
	if not visible:
		return
	if not is_instance_valid(tower):
		tower = null
		visible = false
		return
	_refresh_time += delta
	var needs_refresh := _refresh_time >= REFRESH_INTERVAL
	if _sell_armed > 0.0:
		_sell_armed -= delta
		needs_refresh = needs_refresh or _sell_armed <= 0.0
	if _hint_time > 0.0:
		_hint_time -= delta
		if _hint_time <= 0.0:
			hint_label.visible = false
	if needs_refresh:
		refresh()

# Rewrites every label from the tower's current state, then repositions the panel
func refresh() -> void:
	_refresh_time = 0.0
	if not is_instance_valid(tower):
		return
	var data: Dictionary = tower.tower_data
	var accent: Color = data.get("color", Color.WHITE)
	_title.text = str(data.get("name", "TOWER")).to_upper()
	_title.add_theme_color_override("font_color", accent)
	_stats.text = "HP %d/%d   DMG %d\nEVERY %.2fs   RNG %.1f" % [
		tower.tower_health, tower.tower_max_health, tower.damage, tower.attack_interval, tower.attack_range]

	var tree: Dictionary = Globals.UPGRADE_TREES.get(tower.tower_type, {})
	_no_upgrades.visible = tree.is_empty()
	for path in cards:
		cards[path].panel.visible = not tree.is_empty()
		if not tree.is_empty():
			_refresh_card(path, tree[path], accent)

	# Repair is offered only to a damaged tower, and only between waves
	var damaged: bool = tower.tower_health < tower.tower_max_health
	repair_button.visible = damaged
	if damaged:
		var cost: int = tower.get_repair_cost()
		var repair_status: String = tower_mgr.repair_status(tower)
		match repair_status:
			"ok":
				repair_button.text = "REPAIR  -%d ENERGY" % cost
			"too_expensive":
				repair_button.text = "REPAIR  -%d ENERGY (NOT ENOUGH)" % cost
			"not_build_phase":
				repair_button.text = "REPAIR: BETWEEN WAVES ONLY"
			"tower_locked":
				repair_button.text = "REPAIR: TOWER LOCKED"
		repair_button.disabled = repair_status != "ok"
	
	var armed := _sell_armed > 0.0
	sell_button.text = ("CONFIRM SELL?  +%d ENERGY" if armed else "SELL  +%d ENERGY") % tower.get_sell_value()
	sell_button.add_theme_color_override("font_color", COLOR_BAD if armed else COLOR_TEXT)
	_reposition()

func _refresh_card(path: String, path_data: Dictionary, accent: Color) -> void:
	var card: Dictionary = cards[path]
	var owned: int = tower.path_tiers[path]
	var path_color: Color = Globals.PATH_B_COLOR if path == "B" else accent
	var chosen := "  [CHOSEN]" if tower.chosen_path == path else ""
	card.header.text = "PATH %s: %s%s" % [path, str(path_data.name).to_upper(), chosen]
	card.header.add_theme_color_override("font_color", path_color)

	var status: String = tower.get_upgrade_status(path)
	if owned >= Globals.MAX_TIER:
		var last: Dictionary = path_data.tiers[owned - 1]
		card.tier_line.text = "MAX TIER"
		card.desc.text = "%s: %s" % [last.name, last.desc]
		card.cost_line.text = "OWNED %d/%d" % [owned, Globals.MAX_TIER]
	else:
		var next: Dictionary = path_data.tiers[owned]
		card.tier_line.text = "T%d: %s" % [owned + 1, next.name]
		card.desc.text = next.desc
		card.cost_line.text = "OWNED %d/%d  |  NEXT: %d ENERGY" % [owned, Globals.MAX_TIER, tower.get_upgrade_cost(path)]

	var reason := _status_text(status, path)
	card.status.text = reason
	card.status.visible = reason != ""
	var usable := status == "ok"
	card.button.disabled = not usable
	var box: StyleBoxFlat = card.style_ok if usable else card.style_off
	if usable:
		box.border_color = path_color
	card.panel.add_theme_stylebox_override("panel", box)
	card.tier_line.add_theme_color_override("font_color", COLOR_TEXT if usable else COLOR_DIM)
	card.cost_line.add_theme_color_override("font_color", Color(0.5, 1.0, 0.7) if usable else COLOR_DIM)

func _status_text(status: String, path: String) -> String:
	match status:
		"path_locked":
			return "LOCKED: you chose path %s" % tower.chosen_path
		"tower_locked":
			return "TOWER LOCKED"
		"too_expensive":
			return "NOT ENOUGH ENERGY (%d more)" % (tower.get_upgrade_cost(path) - ResourceManager.current_energy)
	return ""

# Puts the panel beside the tower: right side if there's room, else left; kept on the board
func _reposition() -> void:
	reset_size()
	var screen := get_viewport_rect().size
	var gap := Globals.TILE_SIZE * 0.5 + 16.0
	var x: float = tower.global_position.x + gap
	if x + size.x > screen.x - SCREEN_MARGIN:
		x = tower.global_position.x - gap - size.x
	var top: float = Globals.GRID_OFFSET.y + SCREEN_MARGIN
	var bottom: float = Globals.GRID_OFFSET.y + Globals.GRID_HEIGHT * Globals.TILE_SIZE - SCREEN_MARGIN
	var y := clampf(tower.global_position.y - size.y * 0.5, top, maxf(top, bottom - size.y))
	position = Vector2(x, y)

# =============================================================================
# ACTIONS
# =============================================================================

func _on_card_pressed(path: String) -> void:
	_buy(path)

func _buy(path: String) -> void:
	if not is_instance_valid(tower):
		return
	_sell_armed = 0.0
	tower_mgr.upgrade_tower(tower, path)
	refresh()

# U: upgrades the chosen path. With no path chosen yet there is nothing to pick for you.
func _on_upgrade_key() -> void:
	if not Globals.UPGRADE_TREES.has(tower.tower_type):
		return
	if tower.chosen_path != "":
		_buy(tower.chosen_path)
	else:
		_show_hint("No path chosen yet: click Path A or Path B")

func _show_hint(text: String) -> void:
	hint_label.text = text
	hint_label.visible = true
	_hint_time = HINT_SECONDS
	refresh()

# First press arms the sale, second press (within a few seconds) sells
func _on_repair_pressed() -> void:
	if not is_instance_valid(tower):
		return
	tower_mgr.repair_tower(tower)
	refresh()

func _on_sell_pressed() -> void:
	if not is_instance_valid(tower):
		return
	if _sell_armed <= 0.0:
		_sell_armed = SELL_CONFIRM_SECONDS
		refresh()
		return
	_sell_armed = 0.0
	tower_mgr.sell_tower(tower)  # also deselects, which hides this panel

func _unhandled_input(event: InputEvent) -> void:
	if not visible or not is_instance_valid(tower):
		return
	if event.is_action_pressed("upgrade"):
		_on_upgrade_key()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("repair"):
		_on_repair_pressed()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("sell"):
		_on_sell_pressed()
		get_viewport().set_input_as_handled()
