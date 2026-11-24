# game_board.gd — Grid rendering and A* pathfinding
# Supports loading different maps per level
extends Node2D
class_name GameBoard

# Pixel-art tiles are 30px and scaled up to TILE_SIZE with nearest filtering.
# Regenerate the art with res://tools/gen_map_tiles.gd
const TILE_PX: int = 30
const GLOW_FRAMES: int = 8
const PATH_FPS: float = 8.0 / PI          # one glow cycle every PI seconds
const ARDUINO_FPS: float = 8.0 * 3.0 / TAU
const SPAWN_FPS: float = 8.0 * 4.0 / TAU

const TEX_BLOCKED: Texture2D = preload("res://assets/sprites/map/tile_blocked.png")
const TEX_BUILDABLE: Texture2D = preload("res://assets/sprites/map/tile_buildable.png")
const SHEET_PATH: Texture2D = preload("res://assets/sprites/map/sheet_path.png")
const SHEET_ARDUINO: Texture2D = preload("res://assets/sprites/map/sheet_arduino.png")
const SHEET_SPAWN: Texture2D = preload("res://assets/sprites/map/sheet_spawn.png")

var placement_preview_pos: Vector2i = Vector2i(-1, -1)
var placement_valid: bool = false
var astar: AStar2D
var _tiles: Node2D
var _tile_frames: SpriteFrames
var _active_spawns: Array[Vector2i] = []  # the spawn tiles this level really uses (see get_spawn_points)

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_tiles = Node2D.new()
	_tiles.name = "Tiles"
	_tiles.show_behind_parent = true  # keep the placement preview on top
	add_child(_tiles)
	_tile_frames = _build_tile_frames()
	_build_astar()
	_build_tiles()

func load_map() -> void:
	_build_astar()
	_build_tiles()
	queue_redraw()

func _build_astar() -> void:
	astar = AStar2D.new()
	var width = Globals.GRID_WIDTH
	var height = Globals.GRID_HEIGHT

	for y in range(height):
		for x in range(width):
			var cell = Globals.get_cell_type(Vector2i(x, y))
			if cell == Globals.CellType.PATH or cell == Globals.CellType.SPAWN or cell == Globals.CellType.ARDUINO:
				var id = y * width + x
				astar.add_point(id, Vector2(x, y))

	for y in range(height):
		for x in range(width):
			var id1 = y * width + x
			if not astar.has_point(id1):
				continue
			if x < width - 1:
				var id2 = y * width + (x + 1)
				if astar.has_point(id2):
					astar.connect_points(id1, id2)
			if y < height - 1:
				var id3 = (y + 1) * width + x
				if astar.has_point(id3):
					astar.connect_points(id1, id3)
	_validate_routes()

# Spawn tiles with no path-tile route to the Arduino. Enemies from these would
# have nowhere to walk, so a map that returns any is a map-data bug. Every SPAWN cell on the map is
# checked, not just the ones the level uses.
func unreachable_spawns() -> Array[Vector2i]:
	var bad: Array[Vector2i] = []
	var arduino_id = _cell_id(get_arduino_position())
	for spawn in _all_spawn_cells():
		if astar.get_id_path(_cell_id(spawn), arduino_id).is_empty():
			bad.append(spawn)
	return bad

func _cell_id(cell: Vector2i) -> int:
	return cell.y * Globals.GRID_WIDTH + cell.x

func _validate_routes() -> void:
	for spawn in unreachable_spawns():
		push_error("Map '%s': spawn %s has no path to the Arduino" % [
			Globals.get_level_config(Globals.current_level).get("name", "?"), spawn])

# The spawn tiles enemies actually use. A level can list its own "spawns" (Level 1 uses only two of its six
# entrances, difficulty_fix F5); otherwise every SPAWN cell on the map is used.
func get_spawn_points() -> Array[Vector2i]:
	var listed: Array = Globals.get_level_config(Globals.current_level).get("spawns", [])
	if not listed.is_empty():
		var chosen: Array[Vector2i] = []
		chosen.assign(listed)
		return chosen
	return _all_spawn_cells()

func _all_spawn_cells() -> Array[Vector2i]:
	var spawns: Array[Vector2i] = []
	for y in range(Globals.GRID_HEIGHT):
		for x in range(Globals.GRID_WIDTH):
			if Globals.get_cell_type(Vector2i(x, y)) == Globals.CellType.SPAWN:
				spawns.append(Vector2i(x, y))
	return spawns

func get_arduino_position() -> Vector2i:
	for y in range(Globals.GRID_HEIGHT):
		for x in range(Globals.GRID_WIDTH):
			if Globals.get_cell_type(Vector2i(x, y)) == Globals.CellType.ARDUINO:
				return Vector2i(x, y)
	return Vector2i(7, 4)

func find_path(from: Vector2i, to: Vector2i) -> Array[Vector2]:
	var from_id = from.y * Globals.GRID_WIDTH + from.x
	var to_id = to.y * Globals.GRID_WIDTH + to.x

	if not astar.has_point(from_id):
		from_id = astar.get_closest_point(Vector2(from.x, from.y))
	if not astar.has_point(to_id):
		to_id = astar.get_closest_point(Vector2(to.x, to.y))

	var grid_path = astar.get_point_path(from_id, to_id)
	var world_path: Array[Vector2] = []
	for point in grid_path:
		world_path.append(Globals.grid_to_world(Vector2i(int(point.x), int(point.y))))
	return world_path

func show_placement_preview(grid_pos: Vector2i, valid: bool) -> void:
	placement_preview_pos = grid_pos
	placement_valid = valid
	queue_redraw()

func clear_preview() -> void:
	placement_preview_pos = Vector2i(-1, -1)
	queue_redraw()

# =============================================================================
# TILE SPRITES
# =============================================================================
func _build_tile_frames() -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	for mask in 16:
		_add_glow_animation(frames, "path_%d" % mask, SHEET_PATH, mask, PATH_FPS)
	_add_glow_animation(frames, "arduino", SHEET_ARDUINO, 0, ARDUINO_FPS)
	_add_glow_animation(frames, "spawn", SHEET_SPAWN, 0, SPAWN_FPS)
	return frames

func _add_glow_animation(frames: SpriteFrames, anim: String, sheet: Texture2D, row: int, fps: float) -> void:
	frames.add_animation(anim)
	frames.set_animation_speed(anim, fps)
	frames.set_animation_loop(anim, true)
	for f in GLOW_FRAMES:
		var atlas := AtlasTexture.new()
		atlas.atlas = sheet
		atlas.region = Rect2(f * TILE_PX, row * TILE_PX, TILE_PX, TILE_PX)
		frames.add_frame(anim, atlas)

func _build_tiles() -> void:
	_active_spawns = get_spawn_points()
	for child in _tiles.get_children():
		child.queue_free()
	var ts = Globals.TILE_SIZE
	var tile_scale = Vector2.ONE * float(ts) / TILE_PX
	for y in range(Globals.GRID_HEIGHT):
		for x in range(Globals.GRID_WIDTH):
			var tile: Node2D
			match Globals.get_cell_type(Vector2i(x, y)):
				Globals.CellType.PATH:
					# Offset each path tile's glow so it ripples across the board
					var phase = x * 0.5 + y * 0.3
					var start_frame = int(round(phase / TAU * GLOW_FRAMES)) % GLOW_FRAMES
					tile = _animated_tile("path_%d" % _path_mask(x, y), start_frame)
				Globals.CellType.ARDUINO:
					tile = _animated_tile("arduino", 0)
				Globals.CellType.SPAWN:
					# A spawn tile the level doesn't use (Level 1 uses 2 of its 6) is drawn as plain blocked wall
					tile = _animated_tile("spawn", 0) if _is_active_spawn(Vector2i(x, y)) else _static_tile(TEX_BLOCKED)
				Globals.CellType.BUILDABLE:
					tile = _static_tile(TEX_BUILDABLE)
				_:
					tile = _static_tile(TEX_BLOCKED)
			tile.position = Vector2(x * ts, y * ts) + Globals.GRID_OFFSET + Vector2(ts, ts) * 0.5
			tile.scale = tile_scale
			_tiles.add_child(tile)

func _static_tile(tex: Texture2D) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = tex
	return sprite

func _animated_tile(anim: String, start_frame: int) -> AnimatedSprite2D:
	var sprite := AnimatedSprite2D.new()
	sprite.sprite_frames = _tile_frames
	sprite.play(anim)
	sprite.frame = start_frame
	return sprite

# Bitmask of connected neighbours: 1 = up, 2 = right, 4 = down, 8 = left
func _path_mask(x: int, y: int) -> int:
	var mask := 0
	if _is_route(Vector2i(x, y - 1)): mask |= 1
	if _is_route(Vector2i(x + 1, y)): mask |= 2
	if _is_route(Vector2i(x, y + 1)): mask |= 4
	if _is_route(Vector2i(x - 1, y)): mask |= 8
	return mask

func _is_route(grid_pos: Vector2i) -> bool:
	var cell = Globals.get_cell_type(grid_pos)
	if cell == Globals.CellType.SPAWN:
		return _is_active_spawn(grid_pos)
	return cell == Globals.CellType.PATH or cell == Globals.CellType.ARDUINO

func _is_active_spawn(grid_pos: Vector2i) -> bool:
	return _active_spawns.has(grid_pos)

func _draw() -> void:
	if placement_preview_pos.x >= 0 and placement_preview_pos.y >= 0:
		var ts = Globals.TILE_SIZE
		var offset = Globals.GRID_OFFSET
		var preview_rect = Rect2(placement_preview_pos.x * ts + offset.x, placement_preview_pos.y * ts + offset.y, ts, ts)
		var color = Color(0.0, 1.0, 0.53, 0.35) if placement_valid else Color(1.0, 0.2, 0.2, 0.35)
		draw_rect(preview_rect, color)
		draw_rect(preview_rect, color * 1.5, false, 2.0)
