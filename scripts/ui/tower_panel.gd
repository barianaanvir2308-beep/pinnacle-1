extends Control

var cards: Array[Control] = []

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	custom_minimum_size = Vector2(0, 200)
	
	# Professional Sci-Fi Background
	var bg = ColorRect.new()
	bg.color = Color(0.03, 0.03, 0.06, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	
	# Top border line for HUD
	var border = ColorRect.new()
	border.color = Color(0.0, 1.0, 0.53, 0.5)
	border.custom_minimum_size = Vector2(0, 2)
	border.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	add_child(border)
	
	var hbox = HBoxContainer.new()
	hbox.name = "HBox"
	hbox.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hbox.grow_vertical = Control.GROW_DIRECTION_BOTH
	hbox.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	hbox.add_theme_constant_override("separation", 50)
	add_child(hbox)
	
	Events.energy_changed.connect(_on_energy_changed)
	refresh()

func refresh() -> void:
	var hbox = get_node_or_null("HBox")
	if not hbox: return
	
	for child in hbox.get_children():
		child.queue_free()
	cards.clear()
	
	var unlocked_towers = Globals.get_unlocked_towers(Globals.current_level)
	for type in unlocked_towers:
		var card = _create_card(type, unlocked_towers.find(type) + 1)
		hbox.add_child(card)
		cards.append(card)
		
	if ResourceManager:
		_on_energy_changed(ResourceManager.current_energy)

func _create_card(type: int, hotkey_idx: int) -> Control:
	var btn = Button.new()
	Audio.ui(btn)
	btn.custom_minimum_size = Vector2(300, 150)
	var data = Globals.TOWER_DATA[type]
	
	# Style the button to look like a control terminal
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.12, 1.0)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.2, 0.6, 1.0, 0.5)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	btn.add_theme_stylebox_override("normal", style)
	
	var hover_style = style.duplicate()
	hover_style.bg_color = Color(0.15, 0.15, 0.2, 1.0)
	hover_style.border_color = Color(0.0, 1.0, 0.53, 1.0)
	btn.add_theme_stylebox_override("hover", hover_style)
	btn.set_meta("style_normal", style)
	btn.set_meta("style_highlight", hover_style)
	
	var disabled_style = style.duplicate()
	disabled_style.bg_color = Color(0.05, 0.05, 0.05, 1.0)
	disabled_style.border_color = Color(0.3, 0.1, 0.1, 1.0)
	btn.add_theme_stylebox_override("disabled", disabled_style)
	btn.set_meta("style_disabled", disabled_style)
	
	btn.text = "[KEY: %d]  %s\nCOST: %d ENERGY" % [hotkey_idx, data.name.to_upper(), data.cost]
	btn.add_theme_font_size_override("font_size", 24)
	btn.add_theme_color_override("font_color", Color(0.9, 1.0, 0.9))
	
	btn.pressed.connect(func(): Events.tower_placement_started.emit(type))
	# Don't keep keyboard focus, or Space presses this button instead of starting the wave
	btn.focus_mode = Control.FOCUS_NONE
	return btn

# The Arduino controller's tower picker lights up the card it is on (-1 = none)
func highlight(index: int) -> void:
	for i in range(cards.size()):
		var lit: bool = i == index
		cards[i].add_theme_stylebox_override("normal", cards[i].get_meta("style_highlight" if lit else "style_normal"))
		cards[i].add_theme_stylebox_override("disabled", cards[i].get_meta("style_highlight" if lit else "style_disabled"))

func _on_energy_changed(amount: int) -> void:
	for i in range(cards.size()):
		var type = Globals.TOWER_DATA.keys()[i]
		var cost = Globals.TOWER_DATA[type].cost
		cards[i].disabled = amount < cost

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var unlocked_towers = Globals.get_unlocked_towers(Globals.current_level)
		var key_idx = event.keycode - KEY_1
		if key_idx >= 0 and key_idx < unlocked_towers.size():
			Events.tower_placement_started.emit(unlocked_towers[key_idx])
