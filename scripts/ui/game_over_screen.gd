extends Control

func _ready() -> void:
	var bg = ColorRect.new()
	bg.color = Color(0.1, 0.0, 0.0, 0.9)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	
	var vbox = VBoxContainer.new()
	vbox.grow_horizontal = Control.GROW_DIRECTION_BOTH
	vbox.grow_vertical = Control.GROW_DIRECTION_BOTH
	vbox.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(vbox)
	
	var title = Label.new()
	title.text = "SYSTEM FAILURE"
	title.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2))
	title.add_theme_font_size_override("font_size", 64)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	
	var sub = Label.new()
	sub.text = "The Arduino has been compromised"
	sub.add_theme_color_override("font_color", Color(1.0, 0.5, 0.5))
	sub.add_theme_font_size_override("font_size", 24)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(sub)
	
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 50)
	vbox.add_child(spacer)
	
	var btn = Button.new()
	Audio.ui(btn)
	btn.text = "> REBOOT SYSTEM_"
	btn.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2))
	btn.add_theme_font_size_override("font_size", 32)
	btn.flat = true
	btn.pressed.connect(_on_reboot_pressed)
	vbox.add_child(btn)

func _on_reboot_pressed() -> void:
	var gsm = get_tree().current_scene.get_node_or_null("Managers/GameStateManager")
	if gsm:
		gsm.change_state(Globals.GameState.LEVEL_SELECT)
