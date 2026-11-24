# gen_map_tiles.gd — Generates the pixel-art map tiles and glow animation sheets
# Run from the project folder:
#   godot --headless --path . --script res://tools/gen_map_tiles.gd
# Output: res://assets/sprites/map/
#   tile_blocked.png, tile_buildable.png      — static 30x30 tiles
#   sheet_path.png     — 8 frames x 16 rows (one row per connection mask: 1=up 2=right 4=down 8=left)
#   sheet_arduino.png  — 8 frames x 1 row
#   sheet_spawn.png    — 8 frames x 1 row
# Tiles are drawn at 30px and scaled 4x in-game (TILE_SIZE 120) with nearest filtering.
extends SceneTree

const T := 30
const FRAMES := 8
const OUT := "res://assets/sprites/map/"

const GRID_COLOR := Color(0.08, 0.08, 0.18)
const CYAN := Color(0.0, 0.8, 1.0)
const CYAN_EDGE := Color(0.0, 0.9, 1.0)
const CYAN_LINK := Color(0.0, 0.7, 0.9)
const GREEN := Color(0.0, 1.0, 0.53)
const GOLD := Color(1.0, 0.84, 0.0)
const RED := Color(1.0, 0.2, 0.2)
const RED_EDGE := Color(1.0, 0.3, 0.3)

func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))

	_blocked().save_png(OUT + "tile_blocked.png")
	_buildable().save_png(OUT + "tile_buildable.png")

	var path_sheet := Image.create_empty(T * FRAMES, T * 16, false, Image.FORMAT_RGBA8)
	for mask in 16:
		for f in FRAMES:
			path_sheet.blit_rect(_path(mask, f), Rect2i(0, 0, T, T), Vector2i(f * T, mask * T))
	path_sheet.save_png(OUT + "sheet_path.png")

	_strip(_arduino).save_png(OUT + "sheet_arduino.png")
	_strip(_spawn).save_png(OUT + "sheet_spawn.png")

	print("Map tiles written to ", OUT)
	quit()

# Phase of the glow cycle for a frame, in radians.
func _phase(frame: int) -> float:
	return TAU * float(frame) / FRAMES

func _strip(draw_frame: Callable) -> Image:
	var img := Image.create_empty(T * FRAMES, T, false, Image.FORMAT_RGBA8)
	for f in FRAMES:
		img.blit_rect(draw_frame.call(f), Rect2i(0, 0, T, T), Vector2i(f * T, 0))
	return img

# =============================================================================
# TILES
# =============================================================================
func _blocked() -> Image:
	var img := _new_tile(Color(0.02, 0.02, 0.05))
	_fill(img, 11, 15, 18, 15, Color(0.06, 0.06, 0.12), 1.0)
	_grid(img)
	return img

func _buildable() -> Image:
	var img := _new_tile(Color(0.02, 0.03, 0.06))
	_fill(img, 2, 2, 27, 27, GREEN, 0.08)
	# Dashed pad border, 4px on / 4px off
	for i in range(2, 28):
		if ((i - 2) / 4) % 2 == 0:
			_blend(img, i, 2, GREEN, 0.25)
			_blend(img, i, 27, GREEN, 0.25)
			_blend(img, 2, i, GREEN, 0.25)
			_blend(img, 27, i, GREEN, 0.25)
	_grid(img)
	return img

func _path(mask: int, frame: int) -> Image:
	var glow := 0.5 + 0.15 * sin(_phase(frame))
	var img := _new_tile(Color(0.02, 0.02, 0.05))
	# Links toward connected neighbours (2px trace from centre to edge)
	if mask & 1: _fill(img, 14, 0, 15, 15, CYAN_LINK, 0.3)
	if mask & 2: _fill(img, 14, 14, 29, 15, CYAN_LINK, 0.3)
	if mask & 4: _fill(img, 14, 14, 15, 29, CYAN_LINK, 0.3)
	if mask & 8: _fill(img, 0, 14, 15, 15, CYAN_LINK, 0.3)
	# Soft halo, core and edge
	_outline(img, 7, 7, 22, 22, CYAN, glow * 0.35)
	_fill(img, 8, 8, 21, 21, CYAN, glow)
	_outline(img, 8, 8, 21, 21, CYAN_EDGE, glow + 0.1)
	# Pixel highlight in the top-left corner
	_fill(img, 9, 9, 11, 9, Color(0.7, 1.0, 1.0), glow * 0.6)
	_fill(img, 9, 10, 9, 11, Color(0.7, 1.0, 1.0), glow * 0.6)
	_grid(img)
	return img

func _arduino(frame: int) -> Image:
	var glow := 0.7 + 0.3 * sin(_phase(frame))
	var img := _new_tile(Color(0.15, 0.12, 0.0))
	_fill(img, 3, 3, 26, 26, GOLD, glow * 0.4)
	_outline(img, 3, 3, 26, 26, GOLD, glow * 0.8)
	# Die in the middle of the chip and pin-1 marker
	_fill(img, 11, 11, 18, 18, Color(0.1, 0.08, 0.0), 0.8)
	_outline(img, 11, 11, 18, 18, GOLD, glow * 0.5)
	_blend(img, 6, 6, Color.WHITE, glow * 0.7)
	# Pins on every side
	for px in [10, 15, 20]:
		_fill(img, px, 0, px, 2, GOLD, glow * 0.6)
		_fill(img, px, 27, px, 29, GOLD, glow * 0.6)
		_fill(img, 0, px, 2, px, GOLD, glow * 0.6)
		_fill(img, 27, px, 29, px, GOLD, glow * 0.6)
	_grid(img)
	return img

func _spawn(frame: int) -> Image:
	var pulse := 0.4 + 0.3 * sin(_phase(frame))
	var img := _new_tile(Color(0.08, 0.02, 0.02))
	_fill(img, 4, 4, 25, 25, RED, pulse)
	_outline(img, 4, 4, 25, 25, RED_EDGE, pulse + 0.2)
	# Right-pointing arrow
	for x in range(11, 20):
		var half := int(round((19 - x) * 0.5))
		_fill(img, x, 15 - half, x, 15 + half, Color(1.0, 0.6, 0.6), pulse + 0.2)
	_grid(img)
	return img

# =============================================================================
# PIXEL HELPERS
# =============================================================================
func _new_tile(bg: Color) -> Image:
	var img := Image.create_empty(T, T, false, Image.FORMAT_RGBA8)
	img.fill(bg)
	return img

func _blend(img: Image, x: int, y: int, c: Color, a: float) -> void:
	if x < 0 or y < 0 or x >= T or y >= T:
		return
	var base := img.get_pixel(x, y)
	img.set_pixel(x, y, base.lerp(Color(c.r, c.g, c.b, 1.0), clampf(a, 0.0, 1.0)))

func _fill(img: Image, x0: int, y0: int, x1: int, y1: int, c: Color, a: float) -> void:
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			_blend(img, x, y, c, a)

func _outline(img: Image, x0: int, y0: int, x1: int, y1: int, c: Color, a: float) -> void:
	for x in range(x0, x1 + 1):
		_blend(img, x, y0, c, a)
		_blend(img, x, y1, c, a)
	for y in range(y0 + 1, y1):
		_blend(img, x0, y, c, a)
		_blend(img, x1, y, c, a)

# Grid seam on the top and left edges only, so neighbouring tiles share one line
func _grid(img: Image) -> void:
	for i in T:
		_blend(img, i, 0, GRID_COLOR, 0.4)
		_blend(img, 0, i, GRID_COLOR, 0.4)
