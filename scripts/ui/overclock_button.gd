# overclock_button.gd — The Emergency Overclock button (in the free space of the top bar):
# a cooldown ring, the O key, what it gives, and the System Load bar with its 60 and 90 marks.
class_name OverclockButton
extends Button

const BUTTON_SIZE: Vector2 = Vector2(250, 72)
const TOP_BAR_POSITION: Vector2 = Vector2(520, 4)  # the free stretch between the wave and Arduino HP labels
const COLOR_TEXT := Color(0.9, 1.0, 0.9)
const COLOR_DIM := Color(0.6, 0.66, 0.72)
const COLOR_OK := Color(1.0, 0.84, 0.0)
const COLOR_WARN := Color(1.0, 0.55, 0.1)
const COLOR_BAD := Color(1.0, 0.25, 0.25)

var manager: OverclockManager

func setup(overclock_manager: OverclockManager) -> void:
	manager = overclock_manager
	custom_minimum_size = BUTTON_SIZE
	size = BUTTON_SIZE
	focus_mode = Control.FOCUS_NONE
	visible = false
	for style_name in ["normal", "hover", "pressed", "disabled"]:
		add_theme_stylebox_override(style_name, _box(style_name))
	pressed.connect(func(): manager.use())
	position = TOP_BAR_POSITION

func _box(style_name: String) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = {"normal": Color(0.06, 0.06, 0.11, 0.95), "hover": Color(0.12, 0.12, 0.18, 0.95),
		"pressed": Color(0.18, 0.18, 0.25, 0.95), "disabled": Color(0.04, 0.04, 0.07, 0.9)}[style_name]
	s.border_color = Color(0.3, 0.3, 0.36, 0.8) if style_name == "disabled" else COLOR_OK
	s.set_border_width_all(2)
	s.set_corner_radius_all(8)
	return s

func _process(_delta: float) -> void:
	if manager == null:
		return
	visible = manager.is_unlocked() and manager.in_play()
	if visible:
		disabled = not manager.can_use()
		queue_redraw()

func _draw() -> void:
	if manager == null:
		return
	var font := ThemeDB.fallback_font
	var ready := manager.can_use()
	var center := Vector2(34.0, 30.0)
	var cooldown: float = Globals.OVERCLOCK.cooldown
	var progress := 1.0 - manager.cooldown_left / cooldown
	draw_arc(center, 20.0, 0.0, TAU, 48, Color(1, 1, 1, 0.12), 5.0)
	draw_arc(center, 20.0, -PI / 2.0, -PI / 2.0 + TAU * progress, 48, COLOR_OK if ready else COLOR_OK.darkened(0.45), 5.0)
	var ring_text := "O" if ready else (str(ceili(manager.cooldown_left)) if manager.cooldown_left > 0.0 else "")
	draw_string(font, Vector2(center.x - 20.0, center.y + 6.0), ring_text, HORIZONTAL_ALIGNMENT_CENTER, 40.0, 16, COLOR_TEXT)
	draw_string(font, Vector2(64.0, 26.0), "OVERCLOCK", HORIZONTAL_ALIGNMENT_LEFT, size.x - 70.0, 20, COLOR_TEXT if ready else COLOR_DIM)
	var status := "+%d ENERGY" % Globals.OVERCLOCK.energy
	if manager.towers_paused():
		status = "SYSTEM CRASH"
	elif manager.system_load >= Globals.OVERCLOCK.severe_threshold:
		status = "OVERLOAD: INCOME HALTED"
	elif manager.system_load >= Globals.OVERCLOCK.slow_threshold:
		status = "TOWERS SLOWED"
	draw_string(font, Vector2(64.0, 46.0), status, HORIZONTAL_ALIGNMENT_LEFT, size.x - 70.0, 15, COLOR_DIM)
	# System Load bar with marks at 60 and 90
	var bar := Rect2(10.0, size.y - 14.0, size.x - 20.0, 7.0)
	draw_rect(bar, Color(1, 1, 1, 0.12))
	var load_color := COLOR_OK
	if manager.system_load >= Globals.OVERCLOCK.severe_threshold:
		load_color = COLOR_BAD
	elif manager.system_load >= Globals.OVERCLOCK.slow_threshold:
		load_color = COLOR_WARN
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * manager.system_load / 100.0, bar.size.y)), load_color)
	for mark in [Globals.OVERCLOCK.slow_threshold, Globals.OVERCLOCK.severe_threshold]:
		var x: float = bar.position.x + bar.size.x * mark / 100.0
		draw_line(Vector2(x, bar.position.y - 2.0), Vector2(x, bar.end.y + 2.0), Color(1, 1, 1, 0.7), 2.0)
	draw_string(font, Vector2(size.x - 74.0, 22.0), "LOAD %d%%" % int(manager.system_load), HORIZONTAL_ALIGNMENT_RIGHT, 66.0, 12, load_color)
