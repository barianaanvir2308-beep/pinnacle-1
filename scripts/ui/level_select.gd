extends Control

@onready var title_label = $MarginContainer/VBoxContainer/TitleLabel
@onready var levels_container = $MarginContainer/VBoxContainer/LevelsContainer
@onready var back_button = $MarginContainer/VBoxContainer/BackButton

func _ready() -> void:
	if back_button:
		back_button.pressed.connect(_on_back_pressed)
		Audio.ui(back_button)
	# Controller status, small, in the top-right corner
	var badge := ControllerBadge.new()
	badge.name = "ControllerBadge"
	badge.compact = true
	badge.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	badge.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	badge.position += Vector2(-24, 24)
	add_child(badge)
	_populate_levels()

func _populate_levels() -> void:
	for child in levels_container.get_children():
		child.queue_free()
		
	for i in range(5):
		var btn = Button.new()
		Audio.ui(btn)
		var is_unlocked = i < Globals.levels_unlocked
		
		var level_data = {}
		if i < Globals.LEVEL_DATA.size():
			level_data = Globals.LEVEL_DATA[i]
		else:
			level_data = {"name": "Unknown", "description": "???"}
			
		var status_text = "[UNLOCKED]" if is_unlocked else "[LOCKED]"
		btn.text = "LEVEL %d: %s %s\n%s" % [i + 1, level_data.get("name", "").to_upper(), status_text, level_data.get("description", "")]
		btn.disabled = not is_unlocked
		
		var style = StyleBoxFlat.new()
		style.bg_color = Color(0.1, 0.1, 0.15, 1.0)
		style.border_width_left = 4
		style.content_margin_left = 20
		style.content_margin_top = 15
		style.content_margin_bottom = 15
		
		if is_unlocked:
			style.border_color = Color(0.0, 1.0, 0.53, 1.0)
			btn.add_theme_color_override("font_color", Color(0.8, 1.0, 0.9))
		else:
			style.border_color = Color(0.3, 0.3, 0.3, 1.0)
			btn.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
			
		btn.add_theme_stylebox_override("normal", style)
		
		var hover_style = style.duplicate()
		if is_unlocked:
			hover_style.bg_color = Color(0.2, 0.2, 0.25, 1.0)
		btn.add_theme_stylebox_override("hover", hover_style)
		
		btn.add_theme_font_size_override("font_size", 24)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		
		btn.pressed.connect(func(): _on_level_selected(i))
		levels_container.add_child(btn)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_back_pressed()
	
	for i in range(5):
		var key = KEY_1 + i
		if event is InputEventKey and event.pressed and not event.echo and event.keycode == key:
			if i < Globals.levels_unlocked:
				_on_level_selected(i)

func _on_level_selected(index: int) -> void:
	Events.level_selected.emit(index)

func _on_back_pressed() -> void:
	var gsm = get_tree().current_scene.get_node_or_null("Managers/GameStateManager")
	if gsm:
		gsm.change_state(Globals.GameState.MAIN_MENU)
	else:
		Events.game_state_changed.emit(Globals.GameState.LEVEL_SELECT, Globals.GameState.MAIN_MENU)
