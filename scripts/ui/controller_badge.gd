# controller_badge.gd — Shows on the menus whether a controller is linked, and which one
#
# Linked:      a pulsing green light, "ESP32 CONTROLLER LINKED" (or ARDUINO) and how its buttons work
# Not linked:  a grey light and "NO CONTROLLER - mouse and keyboard"
# It reads HardwareLink (group "hardware_link") every frame, so it changes the moment the board is plugged in or
# pulled out, even while the menu is open. Colours follow docs/ui_hud_design.md; the light and the words carry the
# state as well as the colour.
class_name ControllerBadge
extends PanelContainer

const COLOR_PANEL := Color(0.043, 0.067, 0.125, 0.92)   # bg_panel
const COLOR_CYAN := Color(0.176, 0.886, 1.0)             # focus / your system
const COLOR_GREEN := Color(0.361, 1.0, 0.616)            # linked
const COLOR_TEXT := Color(0.902, 0.945, 1.0)
const COLOR_DIM := Color(0.541, 0.608, 0.722)
const COLOR_LINE := Color(0.133, 0.188, 0.302)

const HELP := {
	&"esp32": "JOYSTICK move   SELECT choose   HOLD SELECT back   OVERDRIVE overclock",
	&"uno": "JOYSTICK move   SELECT choose   BACK back   OVERRIDE overclock",
}

var compact: bool = false       # one line only (corner of the level select screen)
var linked: bool = false
var board: StringName = &""

var _light: StatusLight
var _title: Label
var _help: Label
var _style: StyleBoxFlat
var _shown_key: String = "?"

# A round status light: drawn, so it doesn't depend on the font having a circle character
class StatusLight extends Control:
	var color: Color = Color.GRAY
	var glow: float = 0.0
	func _init() -> void:
		custom_minimum_size = Vector2(22, 22)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var c := size * 0.5
		if glow > 0.0:
			draw_circle(c, 11.0, Color(color, 0.25 * glow))
		draw_circle(c, 7.0, color)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style = StyleBoxFlat.new()
	_style.bg_color = COLOR_PANEL
	_style.set_border_width_all(2)
	_style.set_corner_radius_all(8)
	_style.set_content_margin_all(12 if not compact else 8)
	add_theme_stylebox_override("panel", _style)
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 4)
	add_child(v)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row)
	_light = StatusLight.new()
	row.add_child(_light)
	_title = _label(24 if not compact else 18, COLOR_TEXT)
	row.add_child(_title)
	_help = _label(17, COLOR_DIM)
	_help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_help.visible = not compact
	v.add_child(_help)
	_update(true)

func _label(size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _process(_delta: float) -> void:
	_update(false)

func _update(force: bool) -> void:
	var link := get_tree().get_first_node_in_group("hardware_link") if is_inside_tree() else null
	linked = link != null and link.connected
	board = link.board if linked else &""
	var key := "%s/%s" % [linked, board]
	if force or key != _shown_key:
		_shown_key = key
		if linked:
			var who: String = {&"esp32": "ESP32 ", &"uno": "ARDUINO "}.get(board, "")
			_title.text = "%sCONTROLLER LINKED" % who
			_title.add_theme_color_override("font_color", COLOR_GREEN)
			_help.text = HELP.get(board, "identifying the board...")
			_style.border_color = COLOR_CYAN
			_light.color = COLOR_GREEN
		else:
			_title.text = "NO CONTROLLER  -  mouse and keyboard"
			_title.add_theme_color_override("font_color", COLOR_DIM)
			_help.text = "Plug in the controller to play with the joystick"
			_style.border_color = COLOR_LINE
			_light.color = COLOR_DIM
	# the light breathes while linked
	_light.glow = (0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * TAU * 0.8)) if linked else 0.0
	_light.queue_redraw()
