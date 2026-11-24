# check_art.gd — Checks the tier art rules (docs/scaling_and_upgrades.md E.3) and that the game picks the right sprites
# Run: godot --headless --path . res://tools/checks/check_art.tscn
# Covers every tower that has an upgrade tree: Antivirus Cannon, Data Spike and EMP Tower.
extends Node

const DIR := "res://assets/sprites/pixel/"
const WHITE_HOT := Color(0.9, 1.0, 1.0)

# name = art file prefix, shot = projectile prefix ("" = the tower fires no projectile)
const TOWERS: Array = [
	{"name": "antivirus_cannon", "type": Globals.TowerType.ANTIVIRUS_CANNON, "shot": "cannon", "cells": [Vector2i(1, 1), Vector2i(2, 1)]},
	{"name": "data_spike", "type": Globals.TowerType.DATA_SPIKE, "shot": "data_spike", "cells": [Vector2i(6, 1), Vector2i(7, 1)]},
	{"name": "emp_tower", "type": Globals.TowerType.EMP_TOWER, "shot": "", "cells": [Vector2i(11, 1), Vector2i(12, 1)]},
]

var _fails: int = 0
var _main: Node
var _tm: Node

func _check(cond: bool, msg: String) -> void:
	if not cond:
		_fails += 1
	print(("  ok    " if cond else "  FAIL  ") + msg)

func _ready() -> void:
	for tower in TOWERS:
		print("== %s: files, tier rules, pads and shots" % tower.name)
		_check_files(tower)
		_check_tier_rules(tower)
		_check_pads_and_shots(tower)
	await _check_in_game()
	print("check_art: %d failure(s)" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)

func _img(rel: String) -> Image:
	return (load(DIR + rel) as Texture2D).get_image()  # the imported (lossless) texture, as the game sees it

func _near(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.02 and absf(a.g - b.g) < 0.02 and absf(a.b - b.b) < 0.02 and absf(a.a - b.a) < 0.02

func _frame(strip: Image, i: int) -> Image:
	return strip.get_region(Rect2i(i * 28, 0, 28, 28))

# Pixels that differ between two same-sized images
func _diff(a: Image, b: Image) -> Array:
	var out: Array = []
	for y in a.get_height():
		for x in a.get_width():
			if not _near(a.get_pixel(x, y), b.get_pixel(x, y)):
				out.append(Vector2i(x, y))
	return out

# How many pixels switch between opaque and transparent: a change of shape, not just colour
func _shape_diff(a: Image, b: Image) -> int:
	var n := 0
	for y in 28:
		for x in 28:
			if (a.get_pixel(x, y).a > 0.5) != (b.get_pixel(x, y).a > 0.5):
				n += 1
	return n

func _contains_color(img: Image, c: Color) -> bool:
	for y in img.get_height():
		for x in img.get_width():
			if _near(img.get_pixel(x, y), c):
				return true
	return false

func _turret(tower: Dictionary, path: String, tier: int) -> Image:
	return _img("towers/%s_turret_%s%d.png" % [tower.name, path, tier])

func _check_files(tower: Dictionary) -> void:
	var accent: Color = Globals.TOWER_DATA[tower.type].color
	for path in ["a", "b"]:
		for tier in [1, 2, 3]:
			var img := _turret(tower, path, tier)
			var want := Vector2i(56, 28) if tier == 3 else Vector2i(28, 28)
			_check(img.get_size() == want, "turret_%s%d.png is %s (T3 = 2-frame strip)" % [path, tier, want])
		_check(_img("towers/%s_base_t3%s.png" % [tower.name, path]).get_size() == Vector2i(28, 28), "base_t3%s.png is 28x28" % path)
	_check(_near(Globals.PATH_B_COLOR, Color(0.55, 0.35, 1.0)) and accent != Globals.PATH_B_COLOR, "path B colour is the shared purple, not the tower accent")

func _check_tier_rules(tower: Dictionary) -> void:
	var name: String = tower.name
	var base := _img("towers/%s_turret.png" % name)
	var accent: Color = Globals.TOWER_DATA[tower.type].color
	for path in ["a", "b"]:
		var P: String = path.to_upper()
		var pc: Color = accent if path == "a" else Globals.PATH_B_COLOR
		var t1 := _turret(tower, path, 1)
		var t2 := _turret(tower, path, 2)
		var t3 := _turret(tower, path, 3)
		# T1: accent detail only: at most 24 changed pixels, every one in the path colour
		var d1 := _diff(base, t1)
		var only_accent := true
		for p in d1:
			var c := t1.get_pixel(p.x, p.y)
			if not (_near(c, pc) or _near(c, pc.lightened(0.25))):
				only_accent = false
		_check(d1.size() > 0 and d1.size() <= 24 and only_accent, "%s1 differs from the base only by path-coloured accents (%d px)" % [P, d1.size()])
		# T2: a clear part swap on top of T1 (many pixels, many of them a change of shape), keeping T1's accents
		var d2 := _diff(t1, t2)
		var shape2 := _shape_diff(t1, t2)
		_check(d2.size() >= 120 and shape2 >= 40, "%s2 is a clear step up from %s1: %d px differ, %d change the shape" % [P, P, d2.size(), shape2])
		var kept := true
		for p in d1:
			if not _near(t2.get_pixel(p.x, p.y), t1.get_pixel(p.x, p.y)):
				kept = false
		_check(kept, "%s2 keeps the %s1 accents" % [P, P])
		# T3: a new silhouette, two frames that differ
		var f0 := _frame(t3, 0)
		var f1 := _frame(t3, 1)
		_check(_shape_diff(base, f0) >= 60, "%s3 has a new silhouette (%d px of shape differ from the base)" % [P, _shape_diff(base, f0)])
		_check(_diff(f0, f1).size() >= 8, "%s3 idle frames differ (%d px)" % [P, _diff(f0, f1).size()])
		_check(_contains_color(t3, pc), "%s3 uses the path colour" % P)
	_check(_contains_color(_turret(tower, "a", 2), WHITE_HOT) and _contains_color(_turret(tower, "a", 3), WHITE_HOT), "path A T2 and T3 have white-hot highlights")
	_check(not _contains_color(_turret(tower, "a", 1), Globals.PATH_B_COLOR), "path A never uses the path B colour")
	_check(_contains_color(_turret(tower, "b", 1), Globals.PATH_B_COLOR), "path B uses the path B colour")
	var seen := {}
	for path in ["a", "b"]:
		for tier in [1, 2, 3]:
			seen[_turret(tower, path, tier).get_data().hex_encode()] = true
	_check(seen.size() == 6, "all six tier sprites are different from each other")

func _check_pads_and_shots(tower: Dictionary) -> void:
	var accent: Color = Globals.TOWER_DATA[tower.type].color
	var base_pad := _img("towers/%s_base.png" % tower.name)
	var pad_a := _img("towers/%s_base_t3a.png" % tower.name)
	var pad_b := _img("towers/%s_base_t3b.png" % tower.name)
	_check(_diff(base_pad, pad_a).size() > 20 and _diff(pad_a, pad_b).size() > 20, "the T3 pads differ from the base pad and from each other")
	_check(_near(pad_a.get_pixel(14, 2), accent) and _near(pad_b.get_pixel(14, 2), Globals.PATH_B_COLOR), "T3 pad rings are in the path colours")
	if tower.shot == "":
		return
	var shot := _img("projectiles/%s.png" % tower.shot)
	var shot_a := _img("projectiles/%s_a3.png" % tower.shot)
	var shot_b := _img("projectiles/%s_b3.png" % tower.shot)
	_check(shot_a.get_size() != shot.get_size() and shot_b.get_size() != shot.get_size() and shot_a.get_size() != shot_b.get_size(),
		"tier 3 shots differ in size from the base shot and from each other (%s, %s, %s)" % [shot.get_size(), shot_a.get_size(), shot_b.get_size()])
	_check(_contains_color(shot_a, WHITE_HOT) and _contains_color(shot_b, Globals.PATH_B_COLOR.lightened(0.6)), "A3 shot has a white-hot tip, B3 shot is purple")

func _tex_name(sprite: Sprite2D) -> String:
	return sprite.texture.resource_path.get_file()

func _check_in_game() -> void:
	print("== sprites chosen in game")
	_main = load("res://scenes/main/Main.tscn").instantiate()
	add_child(_main)
	await get_tree().process_frame
	Events.level_selected.emit(0)
	await get_tree().process_frame
	ResourceManager.current_energy = 50000
	ResourceManager.max_energy = 1000000  # these checks hand themselves lots of Energy; the real cap is 1000
	_main.get_node("Managers/CombatManager").set_physics_process(false)
	_tm = _main.get_node("Managers/TowerManager")
	_main._on_spawn_enemy_requested(Globals.EnemyType.BASIC_VIRUS, 50.0, 1.0)
	var enemy = _main.get_node("EnemyContainer").get_child(0)
	for tower in TOWERS:
		await _check_tower_in_game(tower, enemy)
	# a tier with no art file keeps the base look
	_tm.place_tower(Vector2i(13, 1), Globals.TowerType.ANTIVIRUS_CANNON)
	var t = _tm.placed_towers[Vector2i(13, 1)]
	_check(t._pick_art("towers/antivirus_cannon_turret", "_a9").resource_path.get_file() == "antivirus_cannon_turret.png",
		"a tier with no art file falls back to the base art")

func _check_tower_in_game(tower: Dictionary, enemy: Node) -> void:
	var n: String = tower.name
	var cell_a: Vector2i = tower.cells[0]
	var cell_b: Vector2i = tower.cells[1]
	_tm.place_tower(cell_a, tower.type)
	var t = _tm.placed_towers[cell_a]
	_check(_tex_name(t.sprite) == "%s_turret.png" % n and _tex_name(t.base_sprite) == "%s_base.png" % n and t.sprite.hframes == 1, "%s: a new tower shows the base art" % n)
	t.sprite.rotation = 1.0
	_tm.upgrade_tower(t, "A")
	_check(_tex_name(t.sprite) == "%s_turret_a1.png" % n and t.get_art_suffix() == "_a1", "%s: A1 -> turret_a1" % n)
	_check(t.sprite.rotation == 1.0, "%s: swapping art keeps the turret's aim" % n)
	_tm.upgrade_tower(t, "B")
	_check(_tex_name(t.sprite) == "%s_turret_a1.png" % n, "%s: A1 + B1 shows A (same rule as the pips)" % n)
	_tm.upgrade_tower(t, "A")
	_check(_tex_name(t.sprite) == "%s_turret_a2.png" % n and _tex_name(t.base_sprite) == "%s_base.png" % n, "%s: A2 -> turret_a2, normal pad" % n)
	_tm.upgrade_tower(t, "A")
	_check(_tex_name(t.sprite) == "%s_turret_a3.png" % n and _tex_name(t.base_sprite) == "%s_base_t3a.png" % n and t.sprite.hframes == 2,
		"%s: A3 -> turret_a3 (2 frames) on the A ring pad" % n)
	var frames_seen := {}
	for i in 12:
		await get_tree().create_timer(0.1).timeout
		frames_seen[t.sprite.frame] = true
	_check(frames_seen.size() == 2, "%s: the T3 idle glow animates between its 2 frames" % n)
	if tower.shot != "":
		enemy.global_position = t.global_position + Vector2(100, 0)
		t.fire_at(enemy)
		_check(await _fired_tex() == "%s_a3.png" % tower.shot, "%s: an A3 tower fires %s_a3.png (got '%s')" % [n, tower.shot, _proj_tex()])
		_clear_shots()

	_tm.place_tower(cell_b, tower.type)
	var b = _tm.placed_towers[cell_b]
	_tm.upgrade_tower(b, "B")
	_check(_tex_name(b.sprite) == "%s_turret_b1.png" % n, "%s: B1 alone -> turret_b1" % n)
	if tower.shot != "":
		enemy.global_position = b.global_position + Vector2(100, 0)
		b.fire_at(enemy)
		_check(await _fired_tex() == "%s.png" % tower.shot, "%s: a B1 tower still fires the base shot" % n)
		_clear_shots()
	_tm.upgrade_tower(b, "B")
	_check(_tex_name(b.sprite) == "%s_turret_b2.png" % n and b.chosen_path == "B", "%s: B2 -> turret_b2" % n)
	_tm.upgrade_tower(b, "B")
	_check(_tex_name(b.sprite) == "%s_turret_b3.png" % n and _tex_name(b.base_sprite) == "%s_base_t3b.png" % n, "%s: B3 -> turret_b3 on the B ring pad" % n)
	if tower.shot != "":
		enemy.global_position = b.global_position + Vector2(100, 0)
		b.fire_at(enemy)
		_check(await _fired_tex() == "%s_b3.png" % tower.shot, "%s: a B3 tower fires %s_b3.png (got '%s')" % [n, tower.shot, _proj_tex()])
		_clear_shots()

	_tm.sell_tower(t)
	_tm.place_tower(cell_a, tower.type)
	var fresh = _tm.placed_towers[cell_a]
	_check(_tex_name(fresh.sprite) == "%s_turret.png" % n and fresh.sprite.hframes == 1, "%s: selling and rebuilding gives the base art again" % n)

# A projectile builds its sprite on its first frame, so wait two frames before looking
func _fired_tex() -> String:
	await get_tree().process_frame
	await get_tree().process_frame
	return _proj_tex()

func _proj_tex() -> String:
	var shots = _main.get_node("ProjectileContainer").get_children()
	if shots.is_empty() or shots[-1].sprite == null:
		return ""
	return shots[-1].sprite.texture.resource_path.get_file()

func _clear_shots() -> void:
	for s in _main.get_node("ProjectileContainer").get_children():
		s.free()
