# tower_choice_menu.gd — The small "which tower?" menu a controller opens on an empty socket
#
# Shown beside the cursor tile by ControllerInput while the player picks a tower with the joystick (up/down) and
# SELECT. It only shows the choice; building goes through TowerManager.place_tower like a mouse click.
# Style follows docs/ui_hud_design.md: dark glass panel, cyan for the focused row, green/red costs with a second
# cue (a cross and "NEED") so colour is never the only signal.
class_name TowerChoiceMenu
extends PanelContainer

const COLOR_PANEL := Color(0.043, 0.067, 0.125, 0.94)   # bg_panel #0B1120
const COLOR_RAISED := Color(0.075, 0.11, 0.19)           # bg_raised #131C30
const COLOR_LINE := Color(0.133, 0.188, 0.302)           # line #22304D
const COLOR_FOCUS := Color(0.176, 0.886, 1.0)            # cyan #2DE2FF
const COLOR_TEXT := Color(0.902, 0.945, 1.0)             # text #E6F1FF
const COLOR_DIM := Color(0.541, 0.608, 0.722)            # text_dim #8A9BB8
const COLOR_OK := Color(0.361, 1.0, 0.616)               # green #5CFF9D
const COLOR_BAD := Color(1.0, 0.302, 0.369)              # red #FF4D5E
const GAP: float = 14.0
const SCREEN_MARGIN: float = 8.0

var towers: Array = []
var index: int = 0
var tile: Vector2i = Vector2i(-1, -1)
var rows: Array = []          # one PanelContainer per tower
var _list: VBoxContainer
var _hint: Label

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := StyleBoxFlat.new()
	box.bg_color = COLOR_PANEL
	box.border_color = Color(COLOR_FOCUS, 0.7)
	box.set_border_width_all(2)
	box.set_corner_radius_all(8)
	box.set_content_margin_all(12)
	add_theme_stylebox_override("panel", box)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(v)
	v.add_child(_label("BUILD MODULE", 16, COLOR_DIM))
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 4)
	_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_list)
	_hint = _label("", 15, COLOR_DIM)
	v.add_child(_hint)
	hide()

func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

# Opens (or updates) the menu for these towers, with `selected` highlighted, beside grid tile `at`
func show_for(tower_types: Array, selected: int, at: Vector2i, cancel_hint: String) -> void:
	if tower_types != towers:
		towers = tower_types.duplicate()
		_build_rows()
	index = selected
	tile = at
	_hint.text = "SELECT = build    %s" % cancel_hint
	refresh()
	show()
	_place.call_deferred()

func _build_rows() -> void:
	for r in rows:
		r.queue_free()
	rows.clear()
	for type in towers:
		var row := PanelContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 14)
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(h)
		var mark := _label("", 20, COLOR_FOCUS)
		mark.custom_minimum_size = Vector2(18, 0)
		var name := _label(Globals.TOWER_DATA[type].name.to_upper(), 20, COLOR_TEXT)
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name.custom_minimum_size = Vector2(230, 0)
		var cost := _label("", 20, COLOR_OK)
		cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		cost.custom_minimum_size = Vector2(120, 0)
		for c in [mark, name, cost]:
			h.add_child(c)
		row.set_meta("mark", mark)
		row.set_meta("cost", cost)
		_list.add_child(row)
		rows.append(row)

# Highlight and costs (affordability changes as Energy comes in)
func refresh() -> void:
	for i in rows.size():
		var row: PanelContainer = rows[i]
		var focused: bool = i == index
		var style := StyleBoxFlat.new()
		style.bg_color = COLOR_RAISED if focused else Color(0, 0, 0, 0)
		style.border_color = COLOR_FOCUS if focused else COLOR_LINE
		style.set_border_width_all(2 if focused else 1)
		style.set_corner_radius_all(4)
		style.set_content_margin_all(6)
		row.add_theme_stylebox_override("panel", style)
		row.get_meta("mark").text = ">" if focused else ""
		var cost: int = Globals.TOWER_DATA[towers[i]].cost
		var label: Label = row.get_meta("cost")
		if ResourceManager.can_afford(cost):
			label.text = "%d E" % cost
			label.add_theme_color_override("font_color", COLOR_OK)
		else:
			label.text = "x NEED %d" % cost
			label.add_theme_color_override("font_color", COLOR_BAD)

# Beside the tile: to its right, or to its left near the right edge; kept on screen
func _place() -> void:
	if not visible:
		return
	size = get_combined_minimum_size()
	var ts := float(Globals.TILE_SIZE)
	var tile_pos := Globals.grid_to_world(tile) - Vector2(ts, ts) * 0.5
	var screen := get_viewport_rect().size
	var pos := Vector2(tile_pos.x + ts + GAP, tile_pos.y)
	if pos.x + size.x > screen.x - SCREEN_MARGIN:
		pos.x = tile_pos.x - GAP - size.x
	pos.x = clampf(pos.x, SCREEN_MARGIN, screen.x - size.x - SCREEN_MARGIN)
	pos.y = clampf(pos.y, SCREEN_MARGIN, screen.y - size.y - SCREEN_MARGIN)
	position = pos
