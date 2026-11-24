# ability_button.gd — One ability button: a cooldown ring, the F-key, the ability name and
# which tower owns it. Created by AbilityManager (one per tower that owns an ability).
class_name AbilityButton
extends Button

const BUTTON_SIZE: Vector2 = Vector2(214, 64)
const RING_RADIUS: float = 20.0
const COLOR_TEXT := Color(0.9, 1.0, 0.9)
const COLOR_DIM := Color(0.6, 0.66, 0.72)
const COLOR_LOCKED := Color(1.0, 0.3, 0.3)

var tower: Node
var slot: int = -1  # F-key slot 0..4, or -1 when there are more than five abilities
var title: String = ""
var subtitle: String = ""
var accent: Color = Color.WHITE
var _title_size: int = 20

func setup(owner_tower: Node, hotkey_slot: int, ordinal: int) -> void:
	tower = owner_tower
	slot = hotkey_slot
	var ability: Dictionary = tower.get_ability()
	title = str(ability.get("name", ability.get("id", "ABILITY"))).to_upper()
	subtitle = "%s #%d" % [tower.tower_data.get("name", "Tower"), ordinal]
	accent = Globals.PATH_B_COLOR if tower.chosen_path == "B" else tower.tower_data.get("color", Color.WHITE)
	# Long names (SYSTEM FREEZE) shrink until they fit beside the ring
	var room := BUTTON_SIZE.x - 70.0
	_title_size = 20
	while _title_size > 13 and ThemeDB.fallback_font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, _title_size).x > room:
		_title_size -= 1
	custom_minimum_size = BUTTON_SIZE
	size = BUTTON_SIZE
	focus_mode = Control.FOCUS_NONE
	add_theme_stylebox_override("normal", _box(Color(0.06, 0.06, 0.11, 0.95), accent))
	add_theme_stylebox_override("hover", _box(Color(0.12, 0.12, 0.18, 0.95), accent.lightened(0.3)))
	add_theme_stylebox_override("pressed", _box(Color(0.18, 0.18, 0.25, 0.95), Color.WHITE))
	add_theme_stylebox_override("disabled", _box(Color(0.04, 0.04, 0.07, 0.9), Color(0.3, 0.3, 0.36, 0.8)))

func _box(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(2)
	s.set_corner_radius_all(8)
	return s

func _process(_delta: float) -> void:
	if not is_instance_valid(tower):
		return
	disabled = not tower.can_use_ability()
	queue_redraw()

func _draw() -> void:
	if not is_instance_valid(tower):
		return
	var font := ThemeDB.fallback_font
	var ready: bool = tower.can_use_ability()
	var locked: bool = tower.is_tower_disabled
	var center := Vector2(34.0, size.y * 0.5)

	# Cooldown ring: fills clockwise from the top as the ability recharges
	var ring_color := COLOR_LOCKED if locked else (accent if ready else accent.darkened(0.45))
	draw_arc(center, RING_RADIUS, 0.0, TAU, 48, Color(1, 1, 1, 0.12), 5.0)
	var progress: float = tower.get_ability_progress()
	if progress > 0.0:
		draw_arc(center, RING_RADIUS, -PI / 2.0, -PI / 2.0 + TAU * progress, 48, ring_color, 5.0)

	var ring_text := ""
	if locked:
		ring_text = "LCK"
	elif ready:
		ring_text = "F%d" % (slot + 1) if slot >= 0 else ""
	else:
		ring_text = str(ceili(tower.ability_cooldown_left))
	draw_string(font, Vector2(center.x - 20.0, center.y + 6.0), ring_text, HORIZONTAL_ALIGNMENT_CENTER, 40.0, 16,
		COLOR_LOCKED if locked else COLOR_TEXT)
	draw_string(font, Vector2(64.0, 28.0), title, HORIZONTAL_ALIGNMENT_LEFT, size.x - 70.0, _title_size,
		COLOR_TEXT if ready else COLOR_DIM)
	draw_string(font, Vector2(64.0, 50.0), subtitle, HORIZONTAL_ALIGNMENT_LEFT, size.x - 70.0, 15, COLOR_DIM)
