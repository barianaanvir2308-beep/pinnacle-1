extends Node2D

@onready var game_board: Node2D = $GameBoard
@onready var tower_container: Node2D = $TowerContainer
@onready var enemy_container: Node2D = $EnemyContainer
@onready var projectile_container: Node2D = $ProjectileContainer
@onready var hud: CanvasLayer = $HUD
@onready var ui_layer: CanvasLayer = $UILayer

@onready var managers: Node = $Managers
@onready var game_state_mgr: Node = $Managers/GameStateManager
@onready var wave_mgr: Node = $Managers/WaveManager
@onready var combat_mgr: Node = $Managers/CombatManager
@onready var tower_mgr: Node = $Managers/TowerManager
@onready var enemy_mgr: Node = $Managers/EnemyManager

var base_health: int
var max_base_health: int
var placement_mode: bool = false
var placement_tower_type: int = -1
var hover_grid_pos: Vector2i = Vector2i(-1, -1)
var _spawn_cycle: int = 0  # next spawn tile to use; makes waves deterministic

var main_menu_scene = preload("res://scenes/ui/MainMenu.tscn")
var level_select_scene = preload("res://scenes/ui/LevelSelect.tscn")
var tower_panel_scene = preload("res://scenes/ui/TowerPanel.tscn")
var game_over_scene = preload("res://scenes/ui/GameOverScreen.tscn")
var victory_scene = preload("res://scenes/ui/VictoryScreen.tscn")

var active_overlay: Control = null
var tower_panel: Control = null

# Wave transition timers
var build_countdown: float = -1.0
var wave_start_countdown: float = -1.0
var _between_waves: bool = false

# Popup labels
var popup_label: Label
var countdown_label: Label
var tower_info_panel: TowerInfoPanel
var ability_mgr: AbilityManager
var overclock_mgr: OverclockManager
var overclock_button: OverclockButton
var hardware_link: HardwareLink
var controller_input: ControllerInput

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	game_board.process_mode = Node.PROCESS_MODE_PAUSABLE
	tower_container.process_mode = Node.PROCESS_MODE_PAUSABLE
	enemy_container.process_mode = Node.PROCESS_MODE_PAUSABLE
	projectile_container.process_mode = Node.PROCESS_MODE_PAUSABLE
	projectile_container.add_to_group("projectile_container")  # towers add their shots here
	
	wave_mgr.process_mode = Node.PROCESS_MODE_PAUSABLE
	combat_mgr.process_mode = Node.PROCESS_MODE_PAUSABLE
	tower_mgr.process_mode = Node.PROCESS_MODE_PAUSABLE
	enemy_mgr.process_mode = Node.PROCESS_MODE_PAUSABLE
	
	max_base_health = Globals.BASE_MAX_HEALTH
	base_health = max_base_health
	
	tower_mgr.tower_container = tower_container
	enemy_mgr.enemy_container = enemy_container
	combat_mgr.setup(tower_container, enemy_mgr)
	
	_create_popup_ui()
	ability_mgr = AbilityManager.new()
	ability_mgr.name = "AbilityManager"
	managers.add_child(ability_mgr)
	ability_mgr.process_mode = Node.PROCESS_MODE_PAUSABLE
	ability_mgr.setup(ui_layer)
	overclock_mgr = OverclockManager.new()
	overclock_mgr.name = "OverclockManager"
	managers.add_child(overclock_mgr)
	overclock_mgr.process_mode = Node.PROCESS_MODE_PAUSABLE
	overclock_mgr.setup(game_state_mgr, wave_mgr)
	# Optional Arduino controller (joystick + SELECT, OVERRIDE and BACK buttons). Without it nothing changes.
	controller_input = ControllerInput.new()
	controller_input.name = "ControllerInput"
	controller_input.setup(self)
	managers.add_child(controller_input)
	hardware_link = HardwareLink.new()
	hardware_link.name = "HardwareLink"
	hardware_link.setup(controller_input)
	managers.add_child(hardware_link)
	overclock_button = OverclockButton.new()
	Audio.ui(overclock_button)
	ui_layer.add_child(overclock_button)
	overclock_button.setup(overclock_mgr)
	tower_info_panel = TowerInfoPanel.new()
	ui_layer.add_child(tower_info_panel)
	tower_info_panel.setup(tower_mgr)
	
	Events.game_state_changed.connect(_on_game_state_changed)
	Events.tower_placement_started.connect(_on_tower_placement_started)
	Events.tower_placement_cancelled.connect(_on_tower_placement_cancelled)
	Events.enemy_defeated.connect(_on_enemy_defeated)
	Events.enemy_reached_base.connect(_on_enemy_reached_base)
	Events.enemy_split.connect(_on_enemy_split)
	Events.wave_completed.connect(_on_wave_completed)
	Events.all_waves_completed.connect(_on_all_waves_completed)
	Events.level_selected.connect(_on_level_selected)
	Events.wave_started.connect(_on_wave_started)
	Events.worm_spread.connect(_on_worm_spread)
	
	wave_mgr.spawn_enemy_requested.connect(_on_spawn_enemy_requested)
	
	_show_main_menu()

# =============================================================================
# POPUP UI
# =============================================================================

func _create_popup_ui() -> void:
	popup_label = Label.new()
	popup_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	popup_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	popup_label.add_theme_color_override("font_color", Color(0.0, 1.0, 0.53))
	popup_label.add_theme_font_size_override("font_size", 48)
	popup_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	popup_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	popup_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	popup_label.position.y -= 60
	popup_label.visible = false
	popup_label.z_index = 100
	ui_layer.add_child(popup_label)
	
	countdown_label = Label.new()
	countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	countdown_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	countdown_label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.0))
	countdown_label.add_theme_font_size_override("font_size", 72)
	countdown_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	countdown_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	countdown_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	countdown_label.position.y += 30
	countdown_label.visible = false
	countdown_label.z_index = 100
	ui_layer.add_child(countdown_label)

func _show_popup(text: String) -> void:
	popup_label.text = text
	popup_label.visible = true

func _hide_popup() -> void:
	popup_label.visible = false
	countdown_label.visible = false

# =============================================================================
# STATE MANAGEMENT
# =============================================================================

func _show_main_menu() -> void:
	_clear_overlay()
	active_overlay = main_menu_scene.instantiate()
	ui_layer.add_child(active_overlay)
	if tower_panel:
		tower_panel.hide()

func _show_level_select() -> void:
	_clear_overlay()
	active_overlay = level_select_scene.instantiate()
	ui_layer.add_child(active_overlay)
	if tower_panel:
		tower_panel.hide()

func _set_game_visible(is_visible: bool) -> void:
	game_board.visible = is_visible
	tower_container.visible = is_visible
	enemy_container.visible = is_visible
	projectile_container.visible = is_visible
	hud.visible = is_visible

func _on_game_state_changed(old_state: int, new_state: int) -> void:
	# Only keep a tower selected while the board is in play
	if new_state != Globals.GameState.BUILD_PHASE and new_state != Globals.GameState.WAVE_ACTIVE \
			and new_state != Globals.GameState.PAUSED:
		tower_mgr.deselect_tower()
	# A level that ends mid-wave must not keep spawning (the tree is not paused on these screens)
	if new_state == Globals.GameState.GAME_OVER or new_state == Globals.GameState.MAIN_MENU \
			or new_state == Globals.GameState.LEVEL_SELECT:
		wave_mgr.stop_waves()
	match new_state:
		Globals.GameState.MAIN_MENU:
			_set_game_visible(false)
			_show_main_menu()
		Globals.GameState.LEVEL_SELECT:
			_set_game_visible(false)
			_show_level_select()
		Globals.GameState.SETUP:
			_set_game_visible(true)
			_setup_level()
		Globals.GameState.BUILD_PHASE:
			_set_game_visible(true)
			_clear_overlay()
			if not tower_panel:
				tower_panel = tower_panel_scene.instantiate()
				ui_layer.add_child(tower_panel)
			else:
				if tower_panel.has_method("refresh"):
					tower_panel.refresh()
			tower_panel.show()
		Globals.GameState.WAVE_ACTIVE:
			_set_game_visible(true)
			pass
		Globals.GameState.GAME_OVER:
			_hide_popup()
			build_countdown = -1.0
			wave_start_countdown = -1.0
			_between_waves = false
			_clear_overlay()
			active_overlay = game_over_scene.instantiate()
			ui_layer.add_child(active_overlay)
			if tower_panel:
				tower_panel.hide()
		Globals.GameState.VICTORY:
			_hide_popup()
			build_countdown = -1.0
			wave_start_countdown = -1.0
			_between_waves = false
			# Unlock next level
			Globals.unlock_next_level()
			Events.level_completed.emit(Globals.current_level)
			_clear_overlay()
			active_overlay = victory_scene.instantiate()
			ui_layer.add_child(active_overlay)
			if tower_panel:
				tower_panel.hide()

func _clear_overlay() -> void:
	if active_overlay and is_instance_valid(active_overlay):
		active_overlay.queue_free()
		active_overlay = null

func _on_level_selected(level_index: int) -> void:
	Globals.load_level(level_index)
	game_state_mgr.change_state(Globals.GameState.SETUP)

func _setup_level() -> void:
	var config = Globals.get_level_config(Globals.current_level)
	max_base_health = config.get("arduino_hp", 100)
	base_health = max_base_health
	
	Events.base_health_changed.emit(base_health, max_base_health)
	ResourceManager.reset()
	overclock_mgr.reset()
	# Override starting energy for this level
	ResourceManager.current_energy = config.get("starting_energy", 300)
	Events.energy_changed.emit(ResourceManager.current_energy)
	
	enemy_mgr.clear_all_enemies()
	# Clear towers
	for child in tower_container.get_children():
		child.queue_free()
	tower_mgr.placed_towers.clear()
	# Clear projectiles
	for child in projectile_container.get_children():
		child.queue_free()
	
	# Reload map and waves
	_spawn_cycle = 0
	game_board.load_map()
	wave_mgr.load_level_waves(Globals.current_level)
	
	_between_waves = false
	build_countdown = -1.0
	wave_start_countdown = -1.0
	_hide_popup()
	
	game_state_mgr.change_state(Globals.GameState.BUILD_PHASE)

# =============================================================================
# TOWER PLACEMENT
# =============================================================================

func _on_tower_placement_started(tower_type: int) -> void:
	tower_mgr.deselect_tower()
	placement_mode = true
	placement_tower_type = tower_type

func _on_tower_placement_cancelled() -> void:
	placement_mode = false
	placement_tower_type = -1
	hover_grid_pos = Vector2i(-1, -1)
	if game_board.has_method("clear_preview"):
		game_board.clear_preview()

# =============================================================================
# ENEMY SPAWNING
# =============================================================================

func _on_spawn_enemy_requested(enemy_type: int, health_mult: float, speed_mult: float) -> void:
	var spawn_points = game_board.get_spawn_points()
	if spawn_points.is_empty():
		return
	
	var spawn_grid = spawn_points[_spawn_cycle % spawn_points.size()]
	_spawn_cycle += 1
	var arduino_pos = game_board.get_arduino_position()
	var path: Array[Vector2] = game_board.find_path(spawn_grid, arduino_pos)
	
	if path.is_empty():
		path = [Globals.grid_to_world(spawn_grid), Globals.grid_to_world(arduino_pos)] as Array[Vector2]
	
	var spawn_world = Globals.grid_to_world(spawn_grid)
	enemy_mgr.spawn_enemy(enemy_type, health_mult, speed_mult, spawn_world, path)

# =============================================================================
# ENEMY EVENTS
# =============================================================================

func _on_enemy_defeated(enemy_type: int, reward: int, pos: Vector2) -> void:
	ResourceManager.add_energy(reward)
	wave_mgr.on_enemy_removed()

func _on_enemy_reached_base(enemy_type: int, damage: int) -> void:
	damage = int(ceil(damage * overclock_mgr.arduino_damage_mult()))  # double damage after a System Crash
	base_health -= damage
	base_health = max(base_health, 0)
	Events.base_health_changed.emit(base_health, max_base_health)
	Events.base_damaged.emit(damage, base_health)
	wave_mgr.on_enemy_removed()
	
	if base_health <= 0:
		game_state_mgr.change_state(Globals.GameState.GAME_OVER)

func _on_enemy_split(pos: Vector2, count: int, enemy_data: Dictionary) -> void:
	for i in range(count):
		var offset = Vector2(randf_range(-30, 30), randf_range(-30, 30))
		var split_pos = pos + offset
		var grid_pos = Globals.world_to_grid(split_pos)
		var arduino_pos = game_board.get_arduino_position()
		var path: Array[Vector2] = game_board.find_path(grid_pos, arduino_pos)
		if path.is_empty():
			path = [split_pos, Globals.grid_to_world(arduino_pos)] as Array[Vector2]
		var basic: Dictionary = Globals.ENEMY_DATA[Globals.EnemyType.BASIC_VIRUS]
		var mini = enemy_mgr.spawn_enemy(
			Globals.EnemyType.BASIC_VIRUS,
			float(enemy_data.get("health", 30.0)) / float(basic.health),   # a Mini is a Basic Virus scaled to the Trojan's split stats
			float(enemy_data.get("speed", 1.2)) / float(basic.speed),
			split_pos,
			path
		)
		if mini != null:  # Minis pay and hurt as the Trojan's data says (1 Energy, 3 damage), not like a Basic Virus
			mini.reward = enemy_data.get("reward", 1)
			mini.base_damage = enemy_data.get("damage", 3)

# A Worm that hit a module spreads: one more Worm appears there (it cannot spread itself)
func _on_worm_spread(pos: Vector2, health_mult: float, speed_mult: float, hit_modules: Array) -> void:
	var arduino_pos = game_board.get_arduino_position()
	var path: Array[Vector2] = game_board.find_path(Globals.world_to_grid(pos), arduino_pos)
	if path.is_empty():
		path = [pos, Globals.grid_to_world(arduino_pos)] as Array[Vector2]
	var worm = enemy_mgr.spawn_enemy(Globals.EnemyType.WORM, health_mult, speed_mult, pos, path)
	if worm != null:
		worm.can_spread = false
		worm.is_clone = true
		worm._hit_modules = hit_modules  # it must not bite the module its parent just bitten

# =============================================================================
# WAVE COMPLETION & COUNTDOWN
# =============================================================================

func _on_wave_completed(wave_number: int, bonus: int) -> void:
	ResourceManager.add_energy(bonus)
	_between_waves = true
	var level_name = Globals.get_level_config(Globals.current_level).get("name", "")
	_show_popup(">>> WAVE %d CLEARED <<<\n+%d ENERGY" % [wave_number, bonus])
	game_state_mgr.change_state(Globals.GameState.BUILD_PHASE)
	build_countdown = 15.0

func _on_all_waves_completed() -> void:
	_between_waves = false
	build_countdown = -1.0
	wave_start_countdown = -1.0
	game_state_mgr.change_state(Globals.GameState.VICTORY)

# Level 1 teaches the Emergency Overclock when it unlocks, at wave 3
func _on_wave_started(wave_number: int) -> void:
	if Globals.current_level == 0 and wave_number == Globals.OVERCLOCK.unlock_wave_level_1:
		Events.show_message.emit("EMERGENCY OVERCLOCK UNLOCKED:  press O or the controller's OVERRIDE / OVERDRIVE button for +%d Energy  (it adds System Load)" % Globals.OVERCLOCK.energy, 6.0)

func _start_next_wave() -> void:
	_between_waves = false
	build_countdown = -1.0
	wave_start_countdown = -1.0
	_hide_popup()
	game_state_mgr.change_state(Globals.GameState.WAVE_ACTIVE)
	wave_mgr.start_wave()

# =============================================================================
# PROCESS
# =============================================================================

func _process(delta: float) -> void:
	# Passive Energy only flows during a wave and the countdowns leading into it (not while idling at level
	# start or paused), and stops when System Load is critical
	var state: int = game_state_mgr.current_state
	ResourceManager.passive_enabled = state != Globals.GameState.PAUSED \
		and (state == Globals.GameState.WAVE_ACTIVE or build_countdown > 0.0 or wave_start_countdown > 0.0) \
		and overclock_mgr.passive_allowed()
	
	if placement_mode:
		var mouse_pos = get_global_mouse_position()
		var grid_pos = Globals.world_to_grid(mouse_pos)
		if grid_pos != hover_grid_pos:
			hover_grid_pos = grid_pos
			var valid = tower_mgr.can_place_tower(grid_pos, placement_tower_type)
			if game_board.has_method("show_placement_preview"):
				game_board.show_placement_preview(grid_pos, valid)
	
	# Fallback wave completion check
	if game_state_mgr.current_state == Globals.GameState.WAVE_ACTIVE:
		if not wave_mgr.is_spawning:
			var live_enemies = enemy_mgr.get_enemy_count()
			if live_enemies <= 0:
				wave_mgr.force_check_wave_complete(live_enemies)
	
	# Build phase countdown (10s)
	if build_countdown > 0.0:
		build_countdown -= delta
		var secs = int(ceil(build_countdown))
		countdown_label.text = str(secs)
		countdown_label.visible = true
		if build_countdown > 0.0:
			_show_popup("PLACE TOWERS!\nNext wave in...")
		if build_countdown <= 0.0:
			build_countdown = -1.0
			wave_start_countdown = 3.0
			_show_popup(">>> WAVE STARTING <<<")
	
	# Pre-wave countdown (3s)
	if wave_start_countdown > 0.0:
		wave_start_countdown -= delta
		var secs = int(ceil(wave_start_countdown))
		if secs > 0 and countdown_label.text != str(secs): Audio.play(&"countdown_tick")  # 3, 2, 1 before the wave
		countdown_label.text = str(secs)
		countdown_label.visible = true
		if wave_start_countdown <= 0.0:
			_start_next_wave()

# =============================================================================
# INPUT
# =============================================================================

# Left click on the board: place a tower in placement mode, otherwise select the tower
# under the cursor (or deselect when the click lands on an empty tile)
func _on_world_click(world_pos: Vector2) -> void:
	var grid_pos = Globals.world_to_grid(world_pos)
	if placement_mode:
		tower_mgr.place_tower(grid_pos, placement_tower_type)
		return
	var clicked = tower_mgr.placed_towers.get(grid_pos)
	if is_instance_valid(clicked):
		tower_mgr.select_tower(clicked)
	else:
		tower_mgr.deselect_tower()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_on_world_click(get_global_mouse_position())
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if placement_mode:
				_on_tower_placement_cancelled()
			else:
				tower_mgr.deselect_tower()
	
	if event.is_action_pressed("start_wave"):
		if game_state_mgr.current_state == Globals.GameState.BUILD_PHASE:
			build_countdown = -1.0
			wave_start_countdown = -1.0
			_start_next_wave()
