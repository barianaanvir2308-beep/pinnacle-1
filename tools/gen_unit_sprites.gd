# gen_unit_sprites.gd — Generates pixel-art towers, enemies and projectiles
# Run from the project folder:
#   godot --headless --path . --script res://tools/gen_unit_sprites.gd
# Optional contact sheet for reviewing the art:
#   ... --script res://tools/gen_unit_sprites.gd -- --preview=/absolute/path/preview.png
# Output: res://assets/sprites/pixel/
#   towers/<name>_base.png, towers/<name>_turret.png  — 28x28, turret faces up
#   enemies/<name>.png                                — faces up (worm is a 4-frame strip)
#   projectiles/<name>.png                            — faces right
# Upgrade-tier art (docs/scaling_and_upgrades.md E.3), so far for the Antivirus Cannon only:
#   towers/<name>_turret_a1.png ... _a3.png, _b1 ... _b3.png  (T3 files are 2-frame strips, 56x28)
#   towers/<name>_base_t3a.png, _t3b.png                      (pad with a path-coloured ring)
#   projectiles/cannon_a3.png, cannon_b3.png
# Art is drawn at 1 px = Globals.PIXEL_SCALE screen px, matching the map tiles.
extends SceneTree

const OUT := "res://assets/sprites/pixel/"

const OUTLINE := Color(0.02, 0.02, 0.06)
const M0 := Color(0.07, 0.08, 0.12)   # metal, darkest
const M1 := Color(0.15, 0.17, 0.24)
const M2 := Color(0.27, 0.30, 0.40)
const M3 := Color(0.46, 0.51, 0.63)   # metal, highlight
const WHITE_HOT := Color(0.9, 1.0, 1.0)
# Path B's shared "utility" colour. Keep equal to Globals.PATH_B_COLOR (tools/checks/check_art.gd tests it).
const PATH_B := Color(0.55, 0.35, 1.0)

var _preview: Array = []   # [label, Image] for the main contact sheet grid
var _tier_rows: Array = []  # one row of preview cells per tower with tier art
var _pads: Dictionary = {}     # tower name -> outlined base pad
var _turrets: Dictionary = {}  # tower name -> outlined base turret

func _init() -> void:
	for sub in ["towers", "enemies", "projectiles"]:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT + sub))

	# Accent colours match Globals.TOWER_DATA / ENEMY_DATA
	var towers := {
		"antivirus_cannon": [Color(0.0, 1.0, 0.53), _t_cannon],
		"data_spike": [Color(1.0, 0.2, 0.2), _t_data_spike],
		"emp_tower": [Color(0.2, 0.6, 1.0), _t_emp],
		"sniper_node": [Color(0.8, 0.2, 0.8), _t_sniper],
		"quarantine_zone": [Color(1.0, 0.64, 0.0), _t_quarantine],
		"firewall_beam": [Color(1.0, 0.9, 0.1), _t_firewall],
		"overclock_hub": [Color(1.0, 1.0, 1.0), _t_overclock],
	}
	for tower_name in towers:
		var accent: Color = towers[tower_name][0]
		var base := _base_pad(accent)
		_outline(base)
		_save(base, "towers/%s_base.png" % tower_name)
		var turret := _img(28, 28)
		towers[tower_name][1].call(turret, accent)
		_outline(turret)
		_save(turret, "towers/%s_turret.png" % tower_name)
		_pads[tower_name] = base
		_turrets[tower_name] = turret
	_make_tier_art("antivirus_cannon", towers["antivirus_cannon"][0], _cannon_tier, "cannon", _p_cannon(towers["antivirus_cannon"][0]), _p_cannon_tier)
	_make_tier_art("data_spike", towers["data_spike"][0], _spike_tier, "data_spike", _p_data_spike(towers["data_spike"][0]), _p_spike_tier)
	_make_tier_art("emp_tower", towers["emp_tower"][0], _emp_tier)

	# name: [accent, draw func, width, height, frames]
	var enemies := {
		"basic_virus": [Color(1.0, 0.3, 0.3), _e_virus, 20, 20, 1],
		"worm": [Color(0.3, 1.0, 0.3), _e_worm, 14, 26, 4],
		"trojan_horse": [Color(0.8, 0.2, 1.0), _e_trojan, 16, 28, 1],
		"ransomware": [Color(1.0, 0.0, 0.5), _e_ransomware, 18, 22, 1],
		"spyware": [Color(0.4, 0.8, 1.0), _e_spyware, 20, 20, 1],
		"rootkit": [Color(0.6, 0.4, 0.1), _e_rootkit, 24, 24, 1],
		"ddos_bot": [Color(1.0, 1.0, 0.2), _e_ddos, 16, 16, 1],
	}
	for enemy_name in enemies:
		var e: Array = enemies[enemy_name]
		var w: int = e[2]
		var h: int = e[3]
		var frames: int = e[4]
		var strip := _img(w * frames, h)
		for f in frames:
			var frame := _img(w, h)
			e[1].call(frame, e[0], f)
			_outline(frame)
			strip.blit_rect(frame, Rect2i(0, 0, w, h), Vector2i(f * w, 0))
		_save(strip, "enemies/%s.png" % enemy_name)

	_save(_p_cannon(Color(0.0, 1.0, 0.53)), "projectiles/cannon.png")
	_save(_p_data_spike(Color(1.0, 0.2, 0.2)), "projectiles/data_spike.png")
	_save(_p_sniper(Color(0.8, 0.2, 0.8)), "projectiles/sniper.png")
	_save(_p_default(), "projectiles/default.png")

	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--preview="):
			_write_preview(arg.trim_prefix("--preview="))

	print("Unit sprites written to ", OUT)
	quit()

# =============================================================================
# TOWERS (28x28, centre 14,14, turret points up)
# =============================================================================
func _base_pad(a: Color) -> Image:
	var img := _img(28, 28)
	_poly(img, PackedVector2Array([Vector2(5, 1), Vector2(23, 1), Vector2(27, 5), Vector2(27, 23),
		Vector2(23, 27), Vector2(5, 27), Vector2(1, 23), Vector2(1, 5)]), M1)
	_poly(img, PackedVector2Array([Vector2(6, 3), Vector2(22, 3), Vector2(25, 6), Vector2(25, 22),
		Vector2(22, 25), Vector2(6, 25), Vector2(3, 22), Vector2(3, 6)]), M0)
	_rect(img, 5, 1, 22, 1, M2)
	_rect(img, 1, 5, 1, 22, M2)
	_ring(img, 14, 14, 10.5, 9.5, M1)
	# Corner status lights
	for p in [Vector2i(5, 5), Vector2i(21, 5), Vector2i(5, 21), Vector2i(21, 21)]:
		_rect(img, p.x, p.y, p.x + 1, p.y + 1, a.darkened(0.45))
	_px(img, 5, 5, a)
	_px(img, 22, 5, a)
	_px(img, 5, 22, a)
	_px(img, 22, 22, a)
	# Edge ticks
	_rect(img, 13, 2, 14, 2, a.darkened(0.55))
	_rect(img, 13, 25, 14, 25, a.darkened(0.55))
	_rect(img, 2, 13, 2, 14, a.darkened(0.55))
	_rect(img, 25, 13, 25, 14, a.darkened(0.55))
	return img

func _t_cannon(img: Image, a: Color) -> void:
	# Twin barrels with glowing muzzles
	_rect(img, 9, 2, 11, 11, M2)
	_rect(img, 16, 2, 18, 11, M2)
	_rect(img, 10, 4, 10, 11, M3)
	_rect(img, 17, 4, 17, 11, M3)
	_rect(img, 9, 2, 11, 3, a.lightened(0.2))
	_rect(img, 16, 2, 18, 3, a.lightened(0.2))
	_rect(img, 12, 8, 15, 11, M1)
	# Armoured body with bevel
	_rect(img, 7, 11, 20, 23, M2)
	_rect(img, 7, 11, 20, 11, M3)
	_rect(img, 7, 11, 7, 23, M3)
	_rect(img, 20, 12, 20, 23, M1)
	_rect(img, 8, 23, 20, 23, M1)
	# Green core panel
	_rect(img, 10, 14, 17, 20, a.darkened(0.55))
	_rect(img, 11, 15, 16, 19, a.darkened(0.15))
	_rect(img, 11, 15, 12, 15, a.lightened(0.5))
	for x in [9, 11, 16, 18]:
		_px(img, x, 21, M0)

func _t_data_spike(img: Image, a: Color) -> void:
	var blade := PackedVector2Array([Vector2(14, 1), Vector2(19, 9), Vector2(16.5, 21), Vector2(11.5, 21), Vector2(9, 9)])
	_poly(img, blade, a.darkened(0.4))
	_shape(img, a, func(x, y): return x < 14.0 and Geometry2D.is_point_in_polygon(Vector2(x, y), blade))
	for y in range(3, 20):
		if img.get_pixel(13, y).a > 0.0:
			_px(img, 13, y, a.lightened(0.45))
	# Guard and hilt
	_rect(img, 8, 21, 19, 22, M2)
	_rect(img, 8, 21, 19, 21, M3)
	_circle(img, 14, 25, 2.6, M2)
	_rect(img, 13, 24, 14, 25, a)

func _t_emp(img: Image, a: Color) -> void:
	# Four diagonal prongs
	for d in range(6, 12):
		for s in [Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)]:
			var x := 14 + d if s.x > 0 else 13 - d
			var y := 14 + d if s.y > 0 else 13 - d
			var c := a if d >= 10 else M2
			_px(img, x, y, c)
			_px(img, x - s.x, y, c)
	# Coil ring
	_ring(img, 14, 14, 9.5, 6.5, M2)
	_shape(img, M3, func(x, y):
		var d := Vector2(x - 14, y - 14)
		return d.length() > 8.5 and d.length() <= 9.5 and d.x + d.y < -3.0)
	# Charged core
	_circle(img, 14, 14, 5.5, a.darkened(0.35))
	_circle(img, 14, 14, 3.8, a)
	_circle(img, 14, 14, 1.8, WHITE_HOT)

func _t_sniper(img: Image, a: Color) -> void:
	var body := PackedVector2Array([Vector2(4, 24), Vector2(24, 24), Vector2(14, 9)])
	_poly(img, body, M1)
	_shape(img, M2, func(x, y): return x < 14.0 and Geometry2D.is_point_in_polygon(Vector2(x, y), body))
	# Eye lens
	_circle(img, 14, 19, 3.2, M0)
	_circle(img, 14, 19, 2.2, a)
	_px(img, 13, 18, WHITE_HOT)
	# Long barrel and scope
	_rect(img, 13, 0, 14, 12, M2)
	_rect(img, 13, 2, 13, 12, M3)
	_rect(img, 13, 0, 14, 1, a.lightened(0.3))
	_rect(img, 12, 10, 15, 11, M1)
	_rect(img, 17, 7, 18, 12, M1)
	_px(img, 17, 7, a.lightened(0.3))
	_px(img, 18, 7, a)

func _t_quarantine(img: Image, a: Color) -> void:
	var outer := _hex(14, 14, 12.5)
	var inner := _hex(14, 14, 10.5)
	_poly(img, outer, M1)
	_poly(img, inner, a.darkened(0.7))
	# Honeycomb cells
	for j in 6:
		var y := 6 + j * 3
		var off := (j % 2) * 2
		for x in range(5 + off, 23, 4):
			if Geometry2D.is_point_in_polygon(Vector2(x + 1, y + 0.5), inner):
				_rect(img, x, y, x + 1, y, a.darkened(0.2))
	for i in 6:
		var p := Vector2(14, 14) + Vector2.from_angle(i * TAU / 6) * 11.2
		_circle(img, p.x, p.y, 1.3, a)
	_circle(img, 14, 14, 2.6, a)
	_circle(img, 14, 14, 1.2, a.lightened(0.6))

func _t_firewall(img: Image, a: Color) -> void:
	_rect(img, 5, 9, 22, 23, M2)
	_rect(img, 5, 9, 22, 9, M3)
	_rect(img, 5, 9, 5, 23, M3)
	_rect(img, 22, 10, 22, 23, M1)
	_rect(img, 6, 23, 22, 23, M1)
	# Brick wall
	for y in range(12, 21):
		for x in range(7, 21):
			var row := (y - 12) / 3
			var mortar := (y - 12) % 3 == 2 or (x - 7 + (row % 2) * 2) % 5 == 4
			var top := (y - 12) % 3 == 0
			_px(img, x, y, M0 if mortar else (a.darkened(0.05) if top else a.darkened(0.35)))
	# Beam emitter
	_circle(img, 14, 7, 4.0, M2)
	_circle(img, 14, 7, 2.8, a)
	_circle(img, 14, 7, 1.3, Color(1.0, 1.0, 0.85))

func _t_overclock(img: Image, a: Color) -> void:
	var up := PackedVector2Array()
	var down := PackedVector2Array()
	for i in 3:
		up.append(Vector2(14, 14) + Vector2.from_angle(-PI / 2 + i * TAU / 3) * 12.5)
		down.append(Vector2(14, 14) + Vector2.from_angle(PI / 2 + i * TAU / 3) * 12.5)
	_poly(img, up, M2)
	_poly(img, down, M2)
	_shape(img, M3, func(x, y):
		return x < 14.0 and y < 14.0 and (Geometry2D.is_point_in_polygon(Vector2(x, y), up) or Geometry2D.is_point_in_polygon(Vector2(x, y), down)))
	for i in 6:
		var p := Vector2(14, 14) + Vector2.from_angle(-PI / 2 + i * TAU / 6) * 10.5
		_px(img, int(p.x), int(p.y), Color(0.6, 0.95, 1.0))
	_circle(img, 14, 14, 5.5, a.darkened(0.3))
	_circle(img, 14, 14, 4.2, M0)
	_circle(img, 14, 14, 3.0, Color(0.55, 0.9, 1.0))
	_circle(img, 14, 14, 1.3, Color.WHITE)

# =============================================================================
# ENEMIES (face up)
# =============================================================================
func _e_virus(img: Image, a: Color, _f: int) -> void:
	var c := Vector2(10, 10)
	for i in 8:
		var dir := Vector2.from_angle(i * TAU / 8 - PI / 2)
		for r in [6.0, 7.0]:
			var p: Vector2 = c + dir * r
			_px(img, floori(p.x), floori(p.y), a.darkened(0.45))
		var knob := c + dir * 8.0
		_circle(img, knob.x, knob.y, 1.1, a.lightened(0.3))
	_circle(img, 10, 10, 5.8, a.darkened(0.35))
	_circle(img, 9.3, 9.3, 4.2, a.darkened(0.05))
	_circle(img, 8.4, 8.2, 1.6, a.lightened(0.5))
	for p in [Vector2i(11, 11), Vector2i(12, 9), Vector2i(9, 12)]:
		_px(img, p.x, p.y, a.darkened(0.55))

func _e_worm(img: Image, a: Color, f: int) -> void:
	var radii := [3.2, 2.8, 2.7, 2.5, 2.2, 1.8]
	var segs: Array[Vector2] = []
	for i in radii.size():
		var sway := sin(f * TAU / 4 + i * 1.1) * 1.6 * (i / 5.0 + 0.3)
		segs.append(Vector2(7 + sway, 5 + i * 3.3))
	# Tail first so the head draws on top
	for i in range(radii.size() - 1, -1, -1):
		var p := segs[i]
		var col := a if i == 0 else (a.darkened(0.3) if i % 2 else a.darkened(0.08))
		_circle(img, p.x, p.y, radii[i], col)
		_px(img, floori(p.x - 1), floori(p.y - 1), a.lightened(0.4))
	var head := segs[0]
	_px(img, floori(head.x - 1.3), floori(head.y - 0.8), M0)
	_px(img, floori(head.x + 1.3), floori(head.y - 0.8), M0)

func _e_trojan(img: Image, a: Color, _f: int) -> void:
	var hull := PackedVector2Array([Vector2(8, 1.5), Vector2(12.5, 7), Vector2(12.5, 22), Vector2(10.5, 25),
		Vector2(5.5, 25), Vector2(3.5, 22), Vector2(3.5, 7)])
	# Fins
	_poly(img, PackedVector2Array([Vector2(3.5, 17), Vector2(1, 24), Vector2(3.5, 23)]), M1)
	_poly(img, PackedVector2Array([Vector2(12.5, 17), Vector2(15, 24), Vector2(12.5, 23)]), M1)
	_poly(img, hull, M2)
	_shape(img, M3, func(x, y): return x < 5.5 and Geometry2D.is_point_in_polygon(Vector2(x, y), hull))
	_shape(img, M1, func(x, y): return x > 10.5 and Geometry2D.is_point_in_polygon(Vector2(x, y), hull))
	# Purple armour bands, window and nose
	for y in [10, 11, 18, 19]:
		for x in range(4, 13):
			if Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), hull):
				_px(img, x, y, a.darkened(0.2) if y % 2 else a)
	_circle(img, 8, 14.5, 2.3, M0)
	_circle(img, 8, 14.5, 1.5, a.lightened(0.3))
	_rect(img, 7, 3, 8, 5, a)
	_rect(img, 6, 25, 9, 26, a.darkened(0.2))

func _e_ransomware(img: Image, a: Color, _f: int) -> void:
	# Shackle
	_shape(img, M2, func(x, y):
		var d := Vector2(x - 9, y - 8).length()
		return d > 3.3 and d <= 5.5 and y < 10.0)
	_shape(img, M3, func(x, y):
		var d := Vector2(x - 9, y - 8).length()
		return d > 4.5 and d <= 5.5 and y < 9.0 and x < 9.0)
	# Lock body with screen and keyhole
	_rect(img, 3, 9, 14, 19, a.darkened(0.45))
	_rect(img, 3, 9, 14, 9, a.darkened(0.05))
	_rect(img, 3, 9, 3, 19, a.darkened(0.2))
	_rect(img, 5, 11, 12, 17, a.darkened(0.2))
	_rect(img, 5, 11, 12, 11, a.lightened(0.2))
	_circle(img, 9, 13.8, 1.6, M0)
	_rect(img, 8, 14, 9, 16, M0)

func _e_spyware(img: Image, a: Color, _f: int) -> void:
	# Four legs
	for d in range(4, 9):
		for s in [Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)]:
			var x := 10 + d if s.x > 0 else 9 - d
			var y := 10 + d if s.y > 0 else 9 - d
			_px(img, x, y, a.darkened(0.3) if d == 8 else M1)
	_circle(img, 10, 10, 5.5, M1)
	_circle(img, 10, 10, 4.5, M0)
	_circle(img, 10, 10, 3.4, Color(0.85, 0.95, 1.0))
	_circle(img, 10, 9.2, 2.2, a)
	_circle(img, 10, 9.2, 1.0, M0)
	_px(img, 8, 8, Color.WHITE)

func _e_rootkit(img: Image, a: Color, _f: int) -> void:
	var c := Vector2(12, 12)
	for i in 8:
		var dir := Vector2.from_angle(i * TAU / 8)
		_shape(img, M2, func(x, y):
			var q := Vector2(x, y) - c
			var along := q.dot(dir)
			return along >= 7.0 and along <= 11.0 and absf(q.cross(dir)) <= 1.8)
	_circle(img, 12, 12, 8.8, a.darkened(0.55))
	_ring(img, 12, 12, 8.8, 7.4, a.darkened(0.2))
	_shape(img, a.lightened(0.15), func(x, y):
		var q := Vector2(x, y) - c
		return q.length() > 7.4 and q.length() <= 8.8 and q.x + q.y < -3.0)
	_circle(img, 12, 12, 5.8, M0)
	for i in 4:
		var p := c + Vector2.from_angle(PI / 4 + i * PI / 2) * 6.6
		_px(img, floori(p.x), floori(p.y), a.lightened(0.2))
	_circle(img, 12, 12, 3.4, Color(0.9, 0.15, 0.1))
	_circle(img, 12, 12, 1.8, Color(1.0, 0.6, 0.2))
	_px(img, 11, 11, Color(1.0, 0.95, 0.7))

func _e_ddos(img: Image, a: Color, _f: int) -> void:
	var c := Vector2(8, 8)
	for i in 6:
		var p := c + Vector2.from_angle(-PI / 2 + i * TAU / 6) * 5.0
		_line(img, 8, 8, floori(p.x), floori(p.y), M2)
		_circle(img, p.x, p.y, 1.2, a)
	_circle(img, 8, 8, 3.2, a.darkened(0.4))
	_circle(img, 8, 8, 2.0, a)
	_circle(img, 8, 8, 1.0, M0)

# =============================================================================
# UPGRADE TIERS (28x28 turrets, T3 = 2-frame strips, same facing as the base turret)
# T1 = accent stripe only. T2 = part swap. T3 = new silhouette, pad ring, 2-frame glow.
# Path A uses the tower's accent with white-hot tips. Path B uses PATH_B.
# =============================================================================
# Builds the tier art for one tower: 6 turrets, 2 T3 pads and (if it has shot art) 2 T3 projectiles.
# draw_fn(img, accent, path, tier, frame) draws one turret frame; shot_fn(path, accent) draws a T3 shot.
func _make_tier_art(name: String, accent: Color, draw_fn: Callable, shot_name: String = "",
		base_shot: Image = null, shot_fn: Callable = Callable()) -> void:
	var row: Array = [_composite(_pads[name], _turrets[name], 0)]
	var shots := {}
	for path in ["A", "B"]:
		var path_color := accent if path == "A" else PATH_B
		# T3 pad: the normal pad with its lights and a ring in the path colour
		var t3_pad := _base_pad(path_color)
		_ring(t3_pad, 14.0, 14.0, 12.4, 11.2, path_color)
		_outline(t3_pad)
		_save(t3_pad, "towers/%s_base_t3%s.png" % [name, path.to_lower()], false)
		for tier in [1, 2, 3]:
			var frames := 2 if tier == 3 else 1
			var strip := _img(28 * frames, 28)
			for f in frames:
				var frame := _img(28, 28)
				draw_fn.call(frame, accent, path, tier, f)
				_outline(frame)
				strip.blit_rect(frame, Rect2i(0, 0, 28, 28), Vector2i(f * 28, 0))
			_save(strip, "towers/%s_turret_%s%d.png" % [name, path.to_lower(), tier], false)
			for f in frames:
				row.append(_composite(t3_pad if tier == 3 else _pads[name], strip, f))
		if shot_fn.is_valid():
			shots[path] = shot_fn.call(path, accent)
			_save(shots[path], "projectiles/%s_%s3.png" % [shot_name, path.to_lower()], false)
	# Preview order: base, A1, A2, A3 f0, A3 f1, B1, B2, B3 f0, B3 f1, then the projectiles
	if base_shot != null:
		row.append(base_shot)
		row.append(shots["A"])
		row.append(shots["B"])
	_tier_rows.append(row)

func _cannon_tier(img: Image, a: Color, path: String, tier: int, frame: int) -> void:
	var pc := a if path == "A" else PATH_B
	var tip := WHITE_HOT if path == "A" else pc.lightened(0.55)
	if tier == 3:
		if path == "A":
			_cannon_a3(img, a, tip, frame)
		else:
			_cannon_b3(img, tip, frame)
		return
	_t_cannon(img, a)  # tiers 1 and 2 keep the base silhouette
	# T1: a 2 px stripe across the body in the path colour
	_rect(img, 8, 12, 19, 12, pc.lightened(0.25))
	_rect(img, 8, 13, 19, 13, pc)
	if tier == 2:
		if path == "A":
			# Deep Scan: long armoured barrels, side plates, a scanner eye and a big sensor mast.
			# (The T1 stripe at y12-13 is left alone.)
			_rect(img, 5, 14, 6, 22, M3)                      # side armour plates widen the body
			_rect(img, 21, 14, 22, 22, M1)
			_px(img, 5, 15, pc)
			_px(img, 22, 21, pc)
			_rect(img, 9, 1, 11, 2, tip)                      # longer barrels, white-hot tips
			_rect(img, 16, 1, 18, 2, tip)
			_rect(img, 9, 3, 11, 3, pc)
			_rect(img, 16, 3, 18, 3, pc)
			_rect(img, 9, 6, 11, 6, M1)                       # rifling bands
			_rect(img, 16, 6, 18, 6, M1)
			_rect(img, 9, 8, 11, 8, pc.darkened(0.3))
			_rect(img, 16, 8, 18, 8, pc.darkened(0.3))
			_rect(img, 12, 4, 15, 7, M1)                      # housing between the barrels
			_rect(img, 12, 4, 12, 7, M2)
			_rect(img, 11, 15, 16, 19, M0)                    # the core panel becomes a scanner eye
			_rect(img, 12, 16, 15, 18, pc.lightened(0.2))
			_rect(img, 13, 17, 14, 17, WHITE_HOT)
			_rect(img, 23, 15, 23, 16, M1)                    # sensor mast on the right
			_rect(img, 24, 8, 24, 16, M2)
			_rect(img, 22, 5, 25, 7, pc)
			_rect(img, 22, 5, 25, 5, pc.lightened(0.35))
			_px(img, 24, 3, WHITE_HOT)
			_px(img, 24, 4, WHITE_HOT)
		else:
			# Wide Scan: big flared muzzles, an emitter pod on each side and a vent grille.
			_rect(img, 7, 2, 12, 4, M2)                       # flared muzzles
			_rect(img, 15, 2, 20, 4, M2)
			_rect(img, 7, 1, 12, 1, tip)                      # glowing rims
			_rect(img, 15, 1, 20, 1, tip)
			_rect(img, 9, 2, 10, 4, M0)                       # open muzzle mouths
			_rect(img, 17, 2, 18, 4, M0)
			_rect(img, 9, 4, 10, 4, pc)
			_rect(img, 17, 4, 18, 4, pc)
			_rect(img, 7, 2, 7, 4, M3)
			_rect(img, 15, 2, 15, 4, M3)
			_rect(img, 3, 13, 6, 20, M2)                      # emitter pods, both sides
			_rect(img, 21, 13, 24, 20, M2)
			_rect(img, 3, 13, 6, 13, M3)
			_rect(img, 21, 13, 24, 13, M3)
			_rect(img, 3, 13, 3, 20, M3)
			_rect(img, 24, 14, 24, 20, M1)
			_rect(img, 4, 15, 5, 18, pc)
			_rect(img, 22, 15, 23, 18, pc)
			_px(img, 4, 15, tip)
			_px(img, 22, 15, tip)
			for x in range(10, 18, 2):                        # vent grille under the core
				_px(img, x, 22, pc)

# Heuristic Engine: three barrels (a 3-shot burst), wider armoured body, glowing core
func _cannon_a3(img: Image, a: Color, tip: Color, frame: int) -> void:
	var lit := frame == 1
	# barrels: short sides, long centre
	_rect(img, 5, 6, 7, 15, M2)
	_rect(img, 20, 6, 22, 15, M2)
	_rect(img, 12, 1, 15, 15, M2)
	_rect(img, 5, 7, 5, 15, M3)
	_rect(img, 20, 7, 20, 15, M3)
	_rect(img, 12, 2, 12, 15, M3)
	_rect(img, 7, 7, 7, 15, M1)
	_rect(img, 22, 7, 22, 15, M1)
	_rect(img, 15, 2, 15, 15, M1)
	# muzzles
	_rect(img, 5, 6, 7, 7, tip if lit else a.lightened(0.2))
	_rect(img, 20, 6, 22, 7, tip if lit else a.lightened(0.2))
	_rect(img, 12, 1, 15, 3, tip)
	# wide armoured body with bevel and shoulder plates
	_rect(img, 3, 15, 24, 26, M2)
	_rect(img, 3, 15, 24, 15, M3)
	_rect(img, 3, 15, 3, 26, M3)
	_rect(img, 24, 16, 24, 26, M1)
	_rect(img, 4, 26, 24, 26, M1)
	_rect(img, 4, 17, 6, 24, M1)
	_rect(img, 21, 17, 23, 24, M1)
	_rect(img, 4, 17, 6, 17, M3)
	_rect(img, 21, 17, 23, 17, M3)
	# accent band and core
	_rect(img, 7, 16, 20, 16, a)
	_rect(img, 9, 18, 18, 24, a.darkened(0.55))
	_rect(img, 10, 19, 17, 23, a.lightened(0.45) if lit else a.darkened(0.15))
	_rect(img, 10, 19, 12, 19, WHITE_HOT if lit else a.lightened(0.5))
	for x in [8, 19]:
		_px(img, x, 25, M0)

# Full System Scan: a four-barrel rotary cluster that spins (the two frames swap the lit barrels)
func _cannon_b3(img: Image, tip: Color, frame: int) -> void:
	var spin := frame == 1
	var pc := PATH_B
	var xs := [6, 10, 15, 19]
	for i in 4:
		var x: int = xs[i]
		var lit := (i % 2 == 0) != spin
		_rect(img, x, 1, x + 2, 12, M2)
		_rect(img, x, 1, x, 12, M3 if lit else M1)
		_rect(img, x + 2, 1, x + 2, 12, M1)
		_rect(img, x, 1, x + 2, 2, pc.lightened(0.35) if lit else pc.darkened(0.25))
	if spin:
		_px(img, 7, 0, tip)
		_px(img, 16, 0, tip)
	else:
		_px(img, 11, 0, tip)
		_px(img, 20, 0, tip)
	# shroud ring around the barrel cluster
	_rect(img, 5, 10, 23, 13, M1)
	_rect(img, 5, 10, 23, 10, M3)
	_rect(img, 5, 12, 23, 12, pc)
	# body with side radiators
	_rect(img, 5, 13, 23, 25, M2)
	_rect(img, 5, 13, 5, 25, M3)
	_rect(img, 23, 14, 23, 25, M1)
	_rect(img, 6, 25, 23, 25, M1)
	_rect(img, 2, 15, 4, 23, M1)
	_rect(img, 24, 15, 26, 23, M1)
	for y in [16, 18, 20, 22]:
		_rect(img, 2, y, 4, y, M0)
		_rect(img, 24, y, 26, y, M0)
	# purple core
	_rect(img, 9, 16, 19, 23, pc.darkened(0.55))
	_rect(img, 10, 17, 18, 22, pc.lightened(0.3) if spin else pc.darkened(0.1))
	_rect(img, 10, 17, 12, 17, tip if spin else pc.lightened(0.5))

# -----------------------------------------------------------------------------
# DATA SPIKE tiers (a vertical blade over a guard and hilt)
# T1: stripe on the guard. A2 Kernel Exploit: wide barbed blade, kernel chip, winged guard.
# A3 Zero-Day: a massive crystal blade with energy cracks. B2 Chain Spike: side prongs joined by arcs.
# B3 Spike Storm: a fan of three blades.
# -----------------------------------------------------------------------------
func _spike_tier(img: Image, a: Color, path: String, tier: int, frame: int) -> void:
	var pc := a if path == "A" else PATH_B
	var tip := WHITE_HOT if path == "A" else pc.lightened(0.55)
	if tier == 3:
		if path == "A":
			_spike_a3(img, a, frame)
		else:
			_spike_b3(img, frame)
		return
	_t_data_spike(img, a)
	# T1: a 2 px stripe across the guard in the path colour
	_rect(img, 8, 21, 19, 21, pc.lightened(0.25))
	_rect(img, 8, 22, 19, 22, pc)
	if tier == 2:
		if path == "A":
			# Kernel Exploit: a wider blade with barbs, a kernel chip, and a winged guard
			var blade := PackedVector2Array([Vector2(14, 1), Vector2(20.5, 9), Vector2(18, 21), Vector2(10, 21), Vector2(7.5, 9)])
			_poly(img, blade, a.darkened(0.4))
			_shape(img, a, func(x, y): return x < 14.0 and Geometry2D.is_point_in_polygon(Vector2(x, y), blade))
			for y in range(3, 20):
				if img.get_pixel(13, y).a > 0.0:
					_px(img, 13, y, a.lightened(0.45))
			_rect(img, 5, 12, 7, 12, a)
			_rect(img, 6, 15, 8, 15, a)
			_rect(img, 7, 18, 9, 18, a)
			_rect(img, 20, 12, 22, 12, a.darkened(0.4))
			_rect(img, 19, 15, 21, 15, a.darkened(0.4))
			_rect(img, 18, 18, 20, 18, a.darkened(0.4))
			_rect(img, 12, 8, 15, 11, M0)
			_rect(img, 13, 9, 14, 10, tip)
			_rect(img, 3, 20, 7, 23, M2)
			_rect(img, 20, 20, 24, 23, M2)
			_rect(img, 3, 20, 7, 20, M3)
			_rect(img, 20, 20, 24, 20, M3)
			_rect(img, 3, 22, 4, 23, pc)
			_rect(img, 23, 22, 24, 23, pc)
		else:
			# Chain Spike: a smaller spike on each side, arcs linking their tips to the blade
			for side in [-1, 1]:
				var cx: float = 14.0 + side * 10.0
				var prong := PackedVector2Array([Vector2(cx, 8), Vector2(cx + 3.0, 20), Vector2(cx - 3.0, 20)])
				_poly(img, prong, pc.darkened(0.45))
				_shape(img, pc, func(x, y): return x < cx and Geometry2D.is_point_in_polygon(Vector2(x, y), prong))
				_px(img, int(cx), 8, tip)
			_line(img, 4, 9, 9, 6, tip.darkened(0.2))
			_line(img, 9, 6, 12, 8, tip.darkened(0.2))
			_line(img, 24, 9, 19, 6, tip.darkened(0.2))
			_line(img, 19, 6, 16, 8, tip.darkened(0.2))
			_rect(img, 3, 21, 7, 23, M2)
			_rect(img, 20, 21, 24, 23, M2)
			_rect(img, 3, 21, 7, 21, M3)
			_rect(img, 20, 21, 24, 21, M3)
			_rect(img, 4, 22, 6, 22, pc)
			_rect(img, 21, 22, 23, 22, pc)

# Zero-Day: a massive crystal blade, cracked with energy. The frames swap dim and white-hot cracks.
func _spike_a3(img: Image, a: Color, frame: int) -> void:
	var lit := frame == 1
	var blade := PackedVector2Array([Vector2(14, 1), Vector2(21.5, 8), Vector2(20, 18), Vector2(14, 22), Vector2(8, 18), Vector2(6.5, 8)])
	_poly(img, blade, a.darkened(0.5))
	_shape(img, a.darkened(0.15), func(x, y): return x < 14.0 and Geometry2D.is_point_in_polygon(Vector2(x, y), blade))
	var facet := PackedVector2Array([Vector2(14, 4), Vector2(18, 9), Vector2(17, 17), Vector2(14, 20), Vector2(11, 17), Vector2(10, 9)])
	_poly(img, facet, a.darkened(0.25))
	_shape(img, a.lightened(0.2), func(x, y): return x < 14.0 and Geometry2D.is_point_in_polygon(Vector2(x, y), facet))
	# energy cracks
	var crack := WHITE_HOT if lit else a.lightened(0.5)
	for y in range(4, 21):
		_px(img, 13, y, crack)
	for p in [Vector2i(12, 8), Vector2i(15, 10), Vector2i(12, 13), Vector2i(15, 15), Vector2i(12, 18)]:
		_px(img, p.x, p.y, crack)
	_px(img, 14, 1, WHITE_HOT)
	_px(img, 14, 2, WHITE_HOT if lit else a.lightened(0.6))
	# wide guard, caps in the accent, and a short hilt
	_rect(img, 4, 22, 23, 23, M2)
	_rect(img, 4, 22, 23, 22, M3)
	_rect(img, 4, 22, 5, 23, a)
	_rect(img, 22, 22, 23, 23, a)
	_rect(img, 12, 24, 15, 26, M1)
	_px(img, 13, 25, a.lightened(0.3) if lit else a)

# Spike Storm: three blades fanned out of one hub. The frames swap which tips spark.
func _spike_b3(img: Image, frame: int) -> void:
	var pc := PATH_B
	var lit := frame == 1
	var blades := [
		[Vector2(3.5, 5), Vector2(5.5, 20), Vector2(10.5, 20)],
		[Vector2(24.5, 5), Vector2(22.5, 20), Vector2(17.5, 20)],
		[Vector2(14, 0.5), Vector2(17.5, 20), Vector2(10.5, 20)],
	]
	for i in blades.size():
		var pts := PackedVector2Array(blades[i])
		_poly(img, pts, pc.darkened(0.5))
		var mid: float = (pts[1].x + pts[2].x) * 0.5
		_shape(img, pc, func(x, y): return x < mid and Geometry2D.is_point_in_polygon(Vector2(x, y), pts))
		var sparks := (i == 2) != lit
		_px(img, int(pts[0].x), int(pts[0].y) + 1, WHITE_HOT if sparks else pc.lightened(0.5))
		_px(img, int(pts[0].x), int(pts[0].y), pc.lightened(0.6) if sparks else pc.lightened(0.3))
	# hub plate and core
	_rect(img, 5, 20, 22, 23, M2)
	_rect(img, 5, 20, 22, 20, M3)
	_rect(img, 6, 22, 21, 22, pc)
	_rect(img, 11, 24, 16, 26, M1)
	_circle(img, 14, 24, 2.4, pc.lightened(0.3) if lit else pc.darkened(0.1))
	_px(img, 13, 23, WHITE_HOT)

# Small projectile art for the tier-3 Data Spike. A3: a heavy lance. B3: a thin fast shard (fired in threes).
func _p_spike_tier(path: String, a: Color) -> Image:
	if path == "A":
		var img := _img(15, 7)
		_rect(img, 0, 3, 3, 3, Color(a, 0.4))
		_rect(img, 3, 1, 10, 1, a.darkened(0.3))
		_rect(img, 3, 5, 10, 5, a.darkened(0.3))
		_rect(img, 3, 2, 11, 4, a)
		_rect(img, 4, 3, 11, 3, a.lightened(0.45))
		_rect(img, 12, 2, 14, 4, WHITE_HOT)
		_px(img, 14, 3, Color.WHITE)
		return img
	var shard := _img(9, 3)
	_rect(shard, 0, 1, 2, 1, Color(PATH_B, 0.4))
	_rect(shard, 3, 0, 6, 2, PATH_B)
	_rect(shard, 7, 1, 8, 1, PATH_B.lightened(0.6))
	return shard

# -----------------------------------------------------------------------------
# EMP tiers (a round coil emitter with four diagonal prongs)
# T1: four small bars on the coil ring. A2 Overload: capacitor banks N/S/E/W. A3 System Freeze: a snowflake
# emitter. B2 Scrambler: radar dishes on the prong tips. B3 Ion Storm: a tesla coil with lightning arms.
# -----------------------------------------------------------------------------
func _emp_tier(img: Image, a: Color, path: String, tier: int, frame: int) -> void:
	var pc := a if path == "A" else PATH_B
	var tip := WHITE_HOT if path == "A" else pc.lightened(0.55)
	if tier == 3:
		if path == "A":
			_emp_a3(img, a, frame)
		else:
			_emp_b3(img, frame)
		return
	_t_emp(img, a)
	# T1: four 3x2 bars on the coil ring, one on each side
	for bar in [Rect2i(13, 5, 3, 2), Rect2i(13, 21, 3, 2), Rect2i(5, 13, 2, 3), Rect2i(21, 13, 2, 3)]:
		_rect(img, bar.position.x, bar.position.y, bar.end.x - 1, bar.end.y - 1, pc)
	if tier == 2:
		if path == "A":
			# Overload: a capacitor bank on every side, and a ringed core
			for bank in [Rect2i(11, 1, 6, 4), Rect2i(11, 23, 6, 4), Rect2i(1, 11, 4, 6), Rect2i(23, 11, 4, 6)]:
				_rect(img, bank.position.x, bank.position.y, bank.end.x - 1, bank.end.y - 1, M2)
				_rect(img, bank.position.x, bank.position.y, bank.end.x - 1, bank.position.y, M3)
			for window in [Rect2i(12, 2, 4, 2), Rect2i(12, 24, 4, 2), Rect2i(2, 12, 2, 4), Rect2i(24, 12, 2, 4)]:
				_rect(img, window.position.x, window.position.y, window.end.x - 1, window.end.y - 1, pc.darkened(0.3))
			for spark in [Vector2i(13, 2), Vector2i(13, 24), Vector2i(2, 13), Vector2i(24, 13)]:
				_px(img, spark.x, spark.y, tip)
			_ring(img, 14, 14, 4.9, 4.0, pc.lightened(0.2))
		else:
			# Scrambler: a radar dish on each prong tip, and a purple ring on the core
			for dish in [Vector2i(1, 1), Vector2i(23, 1), Vector2i(1, 23), Vector2i(23, 23)]:
				_rect(img, dish.x, dish.y, dish.x + 3, dish.y + 3, M2)
				_rect(img, dish.x, dish.y, dish.x + 3, dish.y, M3)
				_rect(img, dish.x + 1, dish.y + 1, dish.x + 2, dish.y + 2, pc)
				_px(img, dish.x + 1, dish.y + 1, tip)
			_ring(img, 14, 14, 4.9, 4.0, pc)

# System Freeze: an eight-armed frost emitter. The frames swap dim and white-hot tips and core.
func _emp_a3(img: Image, a: Color, frame: int) -> void:
	var lit := frame == 1
	var arm := a.darkened(0.35)
	# cardinal arms (2 px thick)
	_rect(img, 2, 13, 25, 14, arm)
	_rect(img, 13, 2, 14, 25, arm)
	_rect(img, 4, 13, 23, 13, a)
	_rect(img, 13, 4, 13, 23, a)
	# diagonal arms
	for off in [0, 1]:
		_line(img, 11 + off, 11, 4 + off, 4, arm)
		_line(img, 16 - off, 11, 23 - off, 4, arm)
		_line(img, 11 + off, 16, 4 + off, 23, arm)
		_line(img, 16 - off, 16, 23 - off, 23, arm)
	# side branches on the cardinal arms
	for d in [6, 9]:
		var w := 3 if d == 6 else 2
		for y in [13 - d, 14 + d]:
			_rect(img, 13 - w, y, 13 - 1, y, a)
			_rect(img, 15, y, 14 + w, y, a)
		for x in [13 - d, 14 + d]:
			_rect(img, x, 13 - w, x, 13 - 1, a)
			_rect(img, x, 15, x, 14 + w, a)
	# tips
	var tipc := WHITE_HOT if lit else a.lightened(0.45)
	for t in [Vector2i(2, 13), Vector2i(25, 13), Vector2i(13, 2), Vector2i(13, 25)]:
		_rect(img, t.x, t.y, t.x + 1, t.y + 1, tipc)
	for t in [Vector2i(4, 4), Vector2i(23, 4), Vector2i(4, 23), Vector2i(23, 23)]:
		_px(img, t.x, t.y, tipc)
	# core
	_circle(img, 13.5, 13.5, 5.2, M1)
	_circle(img, 13.5, 13.5, 4.2, a.darkened(0.3))
	_circle(img, 13.5, 13.5, 3.0, a.lightened(0.45) if lit else a)
	_circle(img, 13.5, 13.5, 1.4, WHITE_HOT)

# Ion Storm: a tesla spire with a charged sphere, and lightning to four outer nodes.
# The frames swap which way the arcs zigzag.
func _emp_b3(img: Image, frame: int) -> void:
	var pc := PATH_B
	var tip := pc.lightened(0.55)
	var flip := 1 if frame == 1 else -1
	# the four outer nodes
	for node in [Vector2i(1, 4), Vector2i(24, 4), Vector2i(1, 20), Vector2i(24, 20)]:
		_rect(img, node.x, node.y, node.x + 2, node.y + 2, M2)
		_rect(img, node.x, node.y, node.x + 2, node.y, M3)
		_px(img, node.x + 1, node.y + 1, pc.lightened(0.3))
	# lightning from the spire and the sphere to the nodes (zigzags, mirrored left/right)
	for side in [-1, 1]:
		var x0 := 13 if side < 0 else 14
		var edge := 3 if side < 0 else 24
		for arc in [[3, 5], [19, 21]]:
			var y0: int = arc[0] + 1
			var mid_x: int = x0 + side * 5
			var jig: int = flip * side
			_line(img, x0, y0 if arc[0] < 10 else y0 - 4, mid_x, y0 + jig + (0 if arc[0] < 10 else -4), tip)
			_line(img, mid_x, y0 + jig + (0 if arc[0] < 10 else -4), edge + (1 if side < 0 else 0), arc[1], tip)
	# spire
	_rect(img, 12, 1, 15, 15, M2)
	_rect(img, 12, 2, 12, 15, M3)
	_rect(img, 15, 2, 15, 15, M1)
	_rect(img, 12, 1, 15, 2, tip)
	_rect(img, 12, 8, 15, 8, pc)
	# charged sphere at the base
	_circle(img, 13.5, 19.5, 6.4, M1)
	_circle(img, 13.5, 19.5, 5.0, pc.darkened(0.5))
	_circle(img, 13.5, 19.5, 3.4, pc.lightened(0.3) if frame == 1 else pc)
	_circle(img, 13.5, 19.5, 1.4, WHITE_HOT)

# Small projectile art for the tier-3 Cannon. A3: a longer bolt (pierces). B3: tiny fast pellets.
func _p_cannon_tier(path: String, a: Color) -> Image:
	if path == "A":
		var img := _img(12, 6)
		_rect(img, 0, 2, 3, 3, Color(a, 0.35))
		_rect(img, 3, 1, 8, 1, Color(a, 0.45))
		_rect(img, 3, 4, 8, 4, Color(a, 0.45))
		_rect(img, 3, 2, 9, 3, a)
		_rect(img, 9, 2, 11, 3, WHITE_HOT)
		return img
	var pellet := _img(6, 4)
	_rect(pellet, 0, 1, 1, 2, Color(PATH_B, 0.4))
	_rect(pellet, 2, 1, 4, 2, PATH_B)
	_rect(pellet, 5, 1, 5, 2, PATH_B.lightened(0.6))
	_px(pellet, 3, 0, Color(PATH_B, 0.5))
	_px(pellet, 3, 3, Color(PATH_B, 0.5))
	return pellet

# A pad with a turret frame on top, as it looks in game
func _composite(pad: Image, turret_strip: Image, frame: int) -> Image:
	var img := pad.duplicate()
	var turret := turret_strip.get_region(Rect2i(frame * 28, 0, 28, 28))
	img.blend_rect(turret, Rect2i(0, 0, 28, 28), Vector2i.ZERO)
	return img

# =============================================================================
# PROJECTILES (face right, no outline — they glow instead)
# =============================================================================
func _p_cannon(a: Color) -> Image:
	var img := _img(8, 6)
	_rect(img, 0, 2, 1, 3, Color(a, 0.35))
	_rect(img, 3, 1, 5, 1, Color(a, 0.4))
	_rect(img, 3, 4, 5, 4, Color(a, 0.4))
	_rect(img, 2, 2, 5, 3, a)
	_rect(img, 6, 2, 6, 3, a.lightened(0.6))
	return img

func _p_data_spike(a: Color) -> Image:
	var img := _img(11, 5)
	_rect(img, 0, 2, 2, 2, Color(a, 0.5))
	_rect(img, 3, 2, 9, 2, a)
	_rect(img, 4, 1, 8, 1, a.darkened(0.3))
	_rect(img, 4, 3, 8, 3, a.darkened(0.3))
	_rect(img, 6, 0, 7, 0, Color(a, 0.3))
	_rect(img, 6, 4, 7, 4, Color(a, 0.3))
	_px(img, 10, 2, WHITE_HOT)
	return img

func _p_sniper(a: Color) -> Image:
	var img := _img(14, 3)
	for x in 14:
		var t := x / 13.0
		_px(img, x, 1, Color(a.lerp(Color.WHITE, t), 0.25 + 0.75 * t))
	_rect(img, 10, 0, 13, 0, Color(a, 0.4))
	_rect(img, 10, 2, 13, 2, Color(a, 0.4))
	return img

# White so the projectile can be tinted with the tower colour
func _p_default() -> Image:
	var img := _img(8, 4)
	_rect(img, 1, 1, 6, 2, Color(0.85, 0.85, 0.85))
	_rect(img, 7, 1, 7, 2, Color.WHITE)
	_px(img, 0, 0, Color(1, 1, 1, 0.5))
	_px(img, 0, 3, Color(1, 1, 1, 0.5))
	return img

# =============================================================================
# PIXEL HELPERS
# =============================================================================
func _img(w: int, h: int) -> Image:
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	return img

func _px(img: Image, x: int, y: int, c: Color) -> void:
	if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
		img.set_pixel(x, y, c)

func _rect(img: Image, x0: int, y0: int, x1: int, y1: int, c: Color) -> void:
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			_px(img, x, y, c)

# Fill every pixel whose centre satisfies cond(x, y)
func _shape(img: Image, c: Color, cond: Callable) -> void:
	for y in img.get_height():
		for x in img.get_width():
			if cond.call(x + 0.5, y + 0.5):
				img.set_pixel(x, y, c)

func _circle(img: Image, cx: float, cy: float, r: float, c: Color) -> void:
	_shape(img, c, func(x, y): return Vector2(x - cx, y - cy).length() <= r)

func _ring(img: Image, cx: float, cy: float, r_out: float, r_in: float, c: Color) -> void:
	_shape(img, c, func(x, y):
		var d := Vector2(x - cx, y - cy).length()
		return d > r_in and d <= r_out)

func _poly(img: Image, pts: PackedVector2Array, c: Color) -> void:
	_shape(img, c, func(x, y): return Geometry2D.is_point_in_polygon(Vector2(x, y), pts))

func _hex(cx: float, cy: float, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 6:
		pts.append(Vector2(cx, cy) + Vector2.from_angle(i * TAU / 6) * r)
	return pts

func _line(img: Image, x0: int, y0: int, x1: int, y1: int, c: Color) -> void:
	var dx := absi(x1 - x0)
	var dy := -absi(y1 - y0)
	var sx := 1 if x0 < x1 else -1
	var sy := 1 if y0 < y1 else -1
	var err := dx + dy
	while true:
		_px(img, x0, y0, c)
		if x0 == x1 and y0 == y1:
			break
		var e2 := 2 * err
		if e2 >= dy:
			err += dy
			x0 += sx
		if e2 <= dx:
			err += dx
			y0 += sy

# 1px dark outline around everything drawn
func _outline(img: Image) -> void:
	var edge: Array[Vector2i] = []
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).a > 0.0:
				continue
			for n in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var q: Vector2i = Vector2i(x, y) + n
				if q.x >= 0 and q.y >= 0 and q.x < img.get_width() and q.y < img.get_height() and img.get_pixel(q.x, q.y).a > 0.5:
					edge.append(Vector2i(x, y))
					break
	for p in edge:
		img.set_pixel(p.x, p.y, OUTLINE)

func _save(img: Image, rel_path: String, in_grid: bool = true) -> void:
	img.save_png(OUT + rel_path)
	if in_grid:
		_preview.append([rel_path, img])

# Contact sheet: every sprite at 4x on the map background colour. Below the grid, one row per tower
# with tier art: base | A1 | A2 | A3 (2 frames) | B1 | B2 | B3 (2 frames) | projectiles (base, A3, B3)
func _write_preview(path: String) -> void:
	var cell := 140
	var cols := 8
	var rows := ceili(_preview.size() / float(cols))
	var tier_cols := 12
	var sheet := Image.create_empty(maxi(cols, tier_cols) * cell, (rows + _tier_rows.size()) * cell, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.02, 0.03, 0.06))
	for i in _preview.size():
		_blit_cell(sheet, _preview[i][1], (i % cols) * cell, (i / cols) * cell, cell)
	for r in _tier_rows.size():
		var cells: Array = _tier_rows[r]
		for c in cells.size():
			_blit_cell(sheet, cells[c], c * cell, (rows + r) * cell, cell)
	sheet.save_png(path)

func _blit_cell(sheet: Image, source: Image, x: int, y: int, cell: int) -> void:
	var img: Image = source.duplicate()
	img.resize(img.get_width() * 4, img.get_height() * 4, Image.INTERPOLATE_NEAREST)
	var w := mini(img.get_width(), cell)
	var h := mini(img.get_height(), cell)
	sheet.blend_rect(img, Rect2i(0, 0, w, h), Vector2i(x + (cell - w) / 2, y + (cell - h) / 2))
