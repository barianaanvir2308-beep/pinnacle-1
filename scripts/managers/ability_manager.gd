# ability_manager.gd — The ability bar: one button per tower that owns an ability.
# An ability belongs to the tower that unlocked it (a Tier 3), so selling or losing the
# tower removes its button. Buttons and the F1–F5 keys follow tower placement order.
# The towers do the work: this only calls tower.use_ability() and keeps the bar in sync.
class_name AbilityManager
extends Node

const MAX_HOTKEYS: int = 5
const BUTTON_GAP: float = 10.0
const BAR_RIGHT_MARGIN: float = 12.0
const BAR_BOTTOM_MARGIN: float = 8.0
const SYNC_INTERVAL: float = 0.25

var bar: Control
var buttons: Array[AbilityButton] = []  # in F-key order
var _signature: Array = []
var _sync_time: float = 0.0
var _in_play: bool = false

func setup(ui_layer: CanvasLayer) -> void:
	bar = Control.new()
	bar.name = "AbilityBar"
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.visible = false
	ui_layer.add_child(bar)
	Events.tower_upgraded.connect(func(_t, _c, _p, _n): _sync_soon())
	Events.tower_sold.connect(func(_t, _c, _r): _sync_soon())
	Events.tower_destroyed.connect(func(_t, _c): _sync_soon())
	Events.game_state_changed.connect(_on_game_state_changed)

func _on_game_state_changed(_old: int, new_state: int) -> void:
	_in_play = new_state == Globals.GameState.BUILD_PHASE or new_state == Globals.GameState.WAVE_ACTIVE \
		or new_state == Globals.GameState.PAUSED
	bar.visible = _in_play and not buttons.is_empty()
	_sync_soon()

func _sync_soon() -> void:
	call_deferred("sync")  # a sold tower is only marked for deletion after its signal fires

func _process(delta: float) -> void:
	_sync_time += delta
	if _sync_time >= SYNC_INTERVAL:
		sync()

# Rebuilds the buttons when the set of ability-owning towers changes
func sync() -> void:
	_sync_time = 0.0
	var owners: Array = []
	for tower in get_tree().get_nodes_in_group("towers"):
		if is_instance_valid(tower) and not tower.is_queued_for_deletion() and tower.has_ability():
			owners.append(tower)
	owners.sort_custom(func(a, b): return a.placed_order < b.placed_order)
	var signature: Array = owners.map(func(t): return [t.get_instance_id(), t.get_ability().get("id", "")])
	if signature == _signature:
		return
	_signature = signature
	_rebuild(owners)

func _rebuild(owners: Array) -> void:
	for button in buttons:
		bar.remove_child(button)
		button.queue_free()
	buttons.clear()
	var seen_per_type := {}
	for i in owners.size():
		var tower = owners[i]
		var ordinal: int = seen_per_type.get(tower.tower_type, 0) + 1
		seen_per_type[tower.tower_type] = ordinal
		var button := AbilityButton.new()
		Audio.ui(button)
		bar.add_child(button)
		button.setup(tower, i if i < MAX_HOTKEYS else -1, ordinal)
		button.position = Vector2(i * (AbilityButton.BUTTON_SIZE.x + BUTTON_GAP), 0.0)
		button.pressed.connect(activate.bind(tower))
		buttons.append(button)
	_layout_bar()
	bar.visible = _in_play and not buttons.is_empty()

# Bottom-right, just above the build bar
func _layout_bar() -> void:
	var width := buttons.size() * (AbilityButton.BUTTON_SIZE.x + BUTTON_GAP) - BUTTON_GAP if not buttons.is_empty() else 0.0
	bar.size = Vector2(width, AbilityButton.BUTTON_SIZE.y)
	var screen := bar.get_viewport_rect().size
	var board_bottom: float = Globals.GRID_OFFSET.y + Globals.GRID_HEIGHT * Globals.TILE_SIZE
	bar.position = Vector2(screen.x - BAR_RIGHT_MARGIN - width, board_bottom - BAR_BOTTOM_MARGIN - AbilityButton.BUTTON_SIZE.y)

# Uses one tower's ability. Does nothing while paused or outside a level.
func activate(tower: Node) -> bool:
	if get_tree().paused or not _in_play or not is_instance_valid(tower):
		return false
	return tower.use_ability()

func _unhandled_input(event: InputEvent) -> void:
	if not _in_play:
		return
	for i in MAX_HOTKEYS:
		if event.is_action_pressed("ability_%d" % (i + 1)):
			if i < buttons.size():
				activate(buttons[i].tower)
			get_viewport().set_input_as_handled()
			return
