extends Control

var time_elapsed: float = 0.0
var glitch_intensity: float = 0.0
var state: int = 0
var next_level_index: int = 0

@onready var bg = ColorRect.new()
@onready var label1 = Label.new()
@onready var label2 = Label.new()

func _ready() -> void:
	next_level_index = Globals.current_level + 1
	
	bg.color = Color(0.0, 0.0, 0.0, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	
	var vbox = VBoxContainer.new()
	vbox.grow_horizontal = Control.GROW_DIRECTION_BOTH
	vbox.grow_vertical = Control.GROW_DIRECTION_BOTH
	vbox.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(vbox)
	
	label1.text = "THREAT NEUTRALIZED"
	label1.add_theme_color_override("font_color", Color(0.0, 1.0, 0.53))
	label1.add_theme_font_size_override("font_size", 64)
	label1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(label1)
	
	label2.text = "DECRYPTING NEXT NODE..."
	label2.add_theme_color_override("font_color", Color(0.2, 0.6, 1.0))
	label2.add_theme_font_size_override("font_size", 32)
	label2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label2.modulate.a = 0.0
	vbox.add_child(label2)

	if next_level_index >= Globals.LEVEL_DATA.size():
		label2.text = "ALL SYSTEMS SECURE. CAMPAIGN COMPLETE."
		label2.add_theme_color_override("font_color", Color(1.0, 0.84, 0.0))
		# Add a back to menu button for the final end
		var btn = Button.new()
		Audio.ui(btn)
		btn.text = "> RETURN TO ROOT_"
		btn.add_theme_color_override("font_color", Color(0.0, 1.0, 0.53))
		btn.add_theme_font_size_override("font_size", 24)
		btn.flat = true
		btn.pressed.connect(func(): Events.game_state_changed.emit(Globals.GameState.VICTORY, Globals.GameState.MAIN_MENU))
		vbox.add_child(btn)

func _process(delta: float) -> void:
	time_elapsed += delta
	
	# Sci-fi transition sequence
	if state == 0:
		# Initial display
		if time_elapsed > 1.5:
			state = 1
			glitch_intensity = 1.0
	elif state == 1:
		# Glitch phase
		glitch_intensity = max(0.0, glitch_intensity - delta)
		if randf() < glitch_intensity:
			label1.position.x = randf_range(-10, 10)
			label1.modulate = Color(randf(), randf(), 1.0)
		else:
			label1.position.x = 0
			label1.modulate = Color(0.0, 1.0, 0.53)
			
		label2.modulate.a = min(1.0, label2.modulate.a + delta * 2.0)
		
		if glitch_intensity <= 0.0 and time_elapsed > 4.0:
			if next_level_index < Globals.LEVEL_DATA.size():
				state = 2
	elif state == 2:
		# Execute transition
		var gsm = get_tree().current_scene.get_node_or_null("Managers/GameStateManager")
		if gsm:
			Events.level_selected.emit(next_level_index)
		state = 3
