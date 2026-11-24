# check_project.gd — Headless project check
# Run: godot --headless --path . res://tools/checks/check_project.tscn
# Loads every script and scene (so a parse error in any file is reported, even
# ones the game hasn't opened yet), then checks the game data. Exits with code 1
# if anything failed.
extends Node

var _errors: Array[String] = []
var _loaded: int = 0

func _ready() -> void:
	_load_all("res://")
	_check_upgrade_trees()
	print("check_project: loaded %d files, %d problem(s)" % [_loaded, _errors.size()])
	for e in _errors:
		printerr("  FAIL: ", e)
	get_tree().quit(1 if _errors.size() > 0 else 0)

func _load_all(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	if FileAccess.file_exists(dir_path.path_join(".gdignore")):
		return
	for sub in dir.get_directories():
		if not sub.begins_with("."):
			_load_all(dir_path.path_join(sub))
	for file in dir.get_files():
		if file.ends_with(".gd") or file.ends_with(".tscn"):
			var path := dir_path.path_join(file)
			if load(path) == null:
				_errors.append("could not load " + path)
			else:
				_loaded += 1

# Rules from docs/scaling_and_upgrades.md (B1, B3, E.2)
func _check_upgrade_trees() -> void:
	for tower_type in Globals.UPGRADE_TREES:
		var tower_name: String = Globals.TOWER_DATA[tower_type].name
		var base_cost: int = Globals.TOWER_DATA[tower_type].cost
		var tree: Dictionary = Globals.UPGRADE_TREES[tower_type]
		for path in ["A", "B"]:
			if not tree.has(path):
				_errors.append("%s is missing path %s" % [tower_name, path])
				continue
			var tiers: Array = tree[path].tiers
			if tiers.size() != Globals.MAX_TIER:
				_errors.append("%s path %s has %d tiers" % [tower_name, path, tiers.size()])
			for i in tiers.size():
				var tier: Dictionary = tiers[i]
				for key in ["name", "cost", "desc"]:
					if not tier.has(key):
						_errors.append("%s %s%d is missing '%s'" % [tower_name, path, i + 1, key])
				var expected := int(round(base_cost * Globals.TIER_COST_MULT[i] / 5.0) * 5)
				if tier.get("cost", -1) != expected:
					_errors.append("%s %s%d costs %s, rule B3 gives %d (base %d)" % [
						tower_name, path, i + 1, tier.get("cost"), expected, base_cost])
		# Rule B6: at most one ability per tower, only on a Tier 3, cooldown 40-60 s
		var abilities := 0
		for path in ["A", "B"]:
			var tiers: Array = tree[path].tiers
			for i in tiers.size():
				if not tiers[i].has("ability"):
					continue
				abilities += 1
				var ability: Dictionary = tiers[i].ability
				if i != Globals.MAX_TIER - 1:
					_errors.append("%s %s%d has an ability but is not Tier 3" % [tower_name, path, i + 1])
				for key in ["id", "name", "cooldown"]:
					if not ability.has(key):
						_errors.append("%s %s%d ability is missing '%s'" % [tower_name, path, i + 1, key])
				if ability.get("cooldown", 0.0) < 40.0 or ability.get("cooldown", 0.0) > 60.0:
					_errors.append("%s %s%d ability cooldown %s is outside 40-60 s" % [tower_name, path, i + 1, ability.get("cooldown")])
		if abilities > 1:
			_errors.append("%s has %d abilities (max 1)" % [tower_name, abilities])
		for key in ["upgrade_cost_multiplier", "upgrade_damage_multiplier", "upgrade_range_multiplier", "max_level"]:
			if Globals.TOWER_DATA[tower_type].has(key):
				_errors.append("%s still has old key '%s'" % [tower_name, key])
