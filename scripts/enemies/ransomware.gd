class_name RansomwareEnemy extends BaseEnemy

# Marks the most valuable module near it, then locks it for a few seconds when it gets within 1 tile.
# It then moves on to the next module. Nothing happens when it dies.
var _target: Node = null
var _locked: Array = []       # modules already locked, so it never picks them again
var _lock_flash: float = 0.0

func _init() -> void:
	enemy_type = Globals.EnemyType.RANSOMWARE

func _process(delta: float) -> void:
	super._process(delta)
	if not is_alive:
		return
	_lock_flash = maxf(_lock_flash - delta * 3.0, 0.0)
	if stun_timer > 0.0:
		return  # a stunned Ransomware can't act
	if not _target_is_good():
		_drop_target()
		# TODO(difficulty_fix F4): this cap stands in for the missing Scanner. Remove it when Phase 4 adds the Scanner.
		if _locked.size() < _data().get("max_locks", 2):
			_pick_target()
	if _target != null and global_position.distance_to(_target.global_position) <= CONTACT_TILES * Globals.TILE_SIZE:
		_lock(_target)

func _data() -> Dictionary:
	return Globals.ENEMY_DATA[Globals.EnemyType.RANSOMWARE]

func _target_is_good() -> bool:
	return is_instance_valid(_target) and not _target.is_queued_for_deletion() and not _target.is_tower_disabled

# The most valuable module within reach: the distance it covers in the mark lead time (2 s) plus 1 tile,
# so a module is marked about 2 seconds before the Ransomware gets to it
func _pick_target() -> void:
	var data := _data()
	var reach_tiles: float = CONTACT_TILES + speed * data.get("mark_lead_time", 2.0)
	var best: Node = null
	for module in _modules_near(reach_tiles * Globals.TILE_SIZE):
		if module.is_tower_disabled or _locked.has(module):
			continue
		if best == null or module.module_value() > best.module_value():
			best = module   # the list is nearest first, so ties go to the nearest
	_target = best
	if _target != null:
		_target.add_mark()
		Audio.play_at(&"ransomware_mark", _target.global_position)

func _drop_target() -> void:
	if is_instance_valid(_target):
		_target.remove_mark()
	_target = null

func _lock(module: Node) -> void:
	var data := _data()
	_locked.append(module)
	module.remove_mark()
	_target = null
	module.set_disabled(true, module.get_lock_duration(data.get("lock_time", 3.0)))
	module.take_tower_damage(data.get("lock_damage", 10.0))
	Audio.play_at(&"tower_locked", module.global_position)
	_lock_flash = 1.0
	queue_redraw()

# The mark must not outlive the Ransomware
func _exit_tree() -> void:
	_drop_target()

func _setup_visuals() -> void:
	super._setup_visuals()
	_load_art("ransomware")
