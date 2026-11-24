# hud.gd — Heads-Up Display overlay
extends CanvasLayer

var top_bar: ColorRect
var level_label: Label
var wave_label: Label
var health_label: Label
var energy_label: Label
var energy_bar_fill: ColorRect
var energy_flashing: bool = false  # the bar flashes once Energy is within 10% of the capacity
var _energy: int = 0
var _flash_time: float = 0.0
var console_label: Label  # "CONSOLE LINKED" while the Arduino console is plugged in
var message_label: Label
var message_timer: Timer

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_create_ui()
	Events.energy_changed.connect(_on_energy_changed)
	Events.base_health_changed.connect(_on_health_changed)
	Events.wave_started.connect(_on_wave_started)
	Events.wave_completed.connect(_on_wave_completed)
	Events.show_message.connect(_on_show_message)
	Events.game_state_changed.connect(_on_state_changed)
	Events.hardware_connection_changed.connect(_on_hardware_connection_changed)
	
	_on_health_changed(Globals.BASE_MAX_HEALTH, Globals.BASE_MAX_HEALTH)
	if ResourceManager:
		_on_energy_changed(ResourceManager.current_energy)

func _create_ui() -> void:
	top_bar = ColorRect.new()
	top_bar.color = Color(0.05, 0.05, 0.15, 0.92)
	top_bar.custom_minimum_size = Vector2(1920, 80)
	top_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top_bar.offset_bottom = 80
	add_child(top_bar)
	
	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 32)
	margin.add_theme_constant_override("margin_right", 32)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	top_bar.add_child(margin)
	
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 40)
	margin.add_child(hbox)
	
	level_label = Label.new()
	level_label.text = "LVL: --"
	level_label.add_theme_color_override("font_color", Color(0.8, 0.2, 1.0))
	level_label.add_theme_font_size_override("font_size", 28)
	hbox.add_child(level_label)
	
	wave_label = Label.new()
	wave_label.text = "WAVE: 0/10"
	wave_label.add_theme_color_override("font_color", Color(0.2, 0.6, 1.0))
	wave_label.add_theme_font_size_override("font_size", 28)
	wave_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(wave_label)
	
	health_label = Label.new()
	health_label.text = "ARDUINO HP: 100/100"
	health_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	health_label.add_theme_font_size_override("font_size", 28)
	health_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	health_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(health_label)
	
	energy_label = Label.new()
	energy_label.text = "ENERGY: 0"
	energy_label.add_theme_color_override("font_color", Color(0.0, 1.0, 0.53))
	energy_label.add_theme_font_size_override("font_size", 28)
	energy_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	energy_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(energy_label)
	
	# Energy Capacity bar under the Energy number
	var bar_back := ColorRect.new()
	bar_back.color = Color(1, 1, 1, 0.12)
	bar_back.position = Vector2(1440, 62)
	bar_back.size = Vector2(448, 8)
	top_bar.add_child(bar_back)
	energy_bar_fill = ColorRect.new()
	energy_bar_fill.color = Color(0.0, 1.0, 0.53)
	energy_bar_fill.position = bar_back.position
	energy_bar_fill.size = Vector2(0, 8)
	top_bar.add_child(energy_bar_fill)
	
	console_label = Label.new()
	console_label.text = "CONSOLE LINKED"
	console_label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.0))
	console_label.add_theme_font_size_override("font_size", 14)
	console_label.position = Vector2(1440, 4)
	console_label.visible = false
	top_bar.add_child(console_label)
	
	message_label = Label.new()
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	message_label.add_theme_color_override("font_color", Color(0.0, 1.0, 0.53, 0.9))
	message_label.add_theme_font_size_override("font_size", 28)
	message_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	message_label.offset_top = 96.0
	message_label.offset_bottom = 140.0
	message_label.visible = false
	add_child(message_label)
	
	message_timer = Timer.new()
	message_timer.one_shot = true
	message_timer.timeout.connect(_on_message_timer_timeout)
	add_child(message_timer)

func _on_state_changed(_old: int, new_state: int) -> void:
	if new_state == Globals.GameState.BUILD_PHASE or new_state == Globals.GameState.WAVE_ACTIVE:
		var config = Globals.get_level_config(Globals.current_level)
		var name = config.get("name", "???")
		level_label.text = "LVL %d: %s" % [Globals.current_level + 1, name.to_upper()]
		if _old == Globals.GameState.SETUP:
			var total = Globals.get_level_waves(Globals.current_level).size()
			wave_label.text = "WAVE: 0/%d" % total

func _on_energy_changed(amount: int) -> void:
	_energy = amount
	var cap: int = maxi(ResourceManager.max_energy, 1)
	energy_label.text = "ENERGY: %d / %d" % [amount, cap]
	energy_bar_fill.size.x = 448.0 * clampf(float(amount) / cap, 0.0, 1.0)
	energy_flashing = amount >= 0.9 * cap
	if not energy_flashing:
		energy_bar_fill.modulate.a = 1.0
		energy_bar_fill.color = Color(0.0, 1.0, 0.53)

func _process(delta: float) -> void:
	if energy_flashing:
		_flash_time += delta
		energy_bar_fill.color = Color(1.0, 0.55, 0.1)
		energy_bar_fill.modulate.a = 0.5 + 0.5 * absf(sin(_flash_time * 6.0))

func _on_health_changed(new_health: int, max_health: int) -> void:
	health_label.text = "ARDUINO HP: %d/%d" % [new_health, max_health]
	var pct = float(new_health) / max(max_health, 1)
	if pct > 0.6:
		health_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3))
	elif pct > 0.3:
		health_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.0))
	else:
		health_label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2))

func _on_wave_started(wave_number: int) -> void:
	var total = Globals.get_level_waves(Globals.current_level).size()
	wave_label.text = "WAVE: %d/%d" % [wave_number, total]

func _on_wave_completed(wave_number: int, bonus: int) -> void:
	pass  # Popups handled by main.gd

func _on_show_message(msg: String, dur: float) -> void:
	message_label.text = msg
	message_label.visible = true
	message_timer.wait_time = dur
	message_timer.start()

func _on_message_timer_timeout() -> void:
	message_label.visible = false

func _on_hardware_connection_changed(is_connected: bool) -> void:
	console_label.visible = is_connected
