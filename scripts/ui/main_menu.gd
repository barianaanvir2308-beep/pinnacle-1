extends Control

func _ready() -> void:
	var bg = ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.05, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	
	var vbox = VBoxContainer.new()
	vbox.grow_horizontal = Control.GROW_DIRECTION_BOTH
	vbox.grow_vertical = Control.GROW_DIRECTION_BOTH
	vbox.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(vbox)
	
	var title = Label.new()
	title.text = "PROTOCOL ZERO"
	title.add_theme_color_override("font_color", Color(0.0, 1.0, 0.53))
	title.add_theme_font_size_override("font_size", 64)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	
	var sub = Label.new()
	sub.text = "TOWER DEFENCE SYSTEM v2.0"
	sub.add_theme_color_override("font_color", Color(0.2, 0.6, 1.0))
	sub.add_theme_font_size_override("font_size", 24)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(sub)
	
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 50)
	vbox.add_child(spacer)
	
	var btn = Button.new()
	Audio.ui(btn)
	btn.text = "> SELECT OPERATION_"
	btn.add_theme_color_override("font_color", Color(0.0, 1.0, 0.53))
	btn.add_theme_font_size_override("font_size", 32)
	btn.flat = true
	btn.pressed.connect(_on_start_pressed)
	vbox.add_child(btn)
	
	var exit_btn = Button.new()
	Audio.ui(exit_btn)
	exit_btn.text = "> EXIT SYSTEM_"
	exit_btn.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2))
	exit_btn.add_theme_font_size_override("font_size", 32)
	exit_btn.flat = true
	exit_btn.pressed.connect(func(): get_tree().quit())
	vbox.add_child(exit_btn)

func _on_start_pressed() -> void:
	var gsm = get_tree().current_scene.get_node_or_null("Managers/GameStateManager")
	if gsm:
		gsm.change_state(Globals.GameState.LEVEL_SELECT)
	else:
		Events.game_state_changed.emit(Globals.GameState.MAIN_MENU, Globals.GameState.LEVEL_SELECT)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_I:
			_on_start_pressed()
