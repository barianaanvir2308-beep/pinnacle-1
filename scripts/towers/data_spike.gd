class_name DataSpikeTower extends BaseTower

const CHAIN_JUMP_TILES: float = 3.0  # how far a chained spike can jump from the virus it hit

var _hit_count: int = 0  # spikes landed so far (Zero-Day stuns on every Nth)

func _init():
	tower_type = Globals.TowerType.DATA_SPIKE
	tower_type_export = Globals.TowerType.DATA_SPIKE

func _setup_visuals():
	super._setup_visuals()
	_load_art("data_spike")

# Purge: damages every virus in range
func _ability_has_targets(_ability: Dictionary) -> bool:
	return not _enemies_in_range().is_empty()

func _perform_ability(ability: Dictionary) -> void:
	if ability.get("id") != "purge":
		return
	for enemy in _enemies_in_range():
		enemy.take_damage(ability.get("damage", 0.0), true)  # the Data Spike's damage ignores armour
	_start_ring_fx(Globals.get_tower_range_pixels(attack_range), Color(1.0, 0.3, 0.3))

# Kernel Exploit: extra damage against Bosses and against Trojans that haven't split yet
func get_damage_against(enemy: Node2D) -> float:
	var bonus: float = tier_stats.get("boss_trojan_bonus", 0.0)
	if bonus > 0.0 and (enemy.is_boss or enemy.enemy_type == Globals.EnemyType.TROJAN_HORSE):
		return damage * (1.0 + bonus)
	return damage

# Spike Storm: one spike at each of the strongest viruses (the extra spikes cycle back to them if
# there are fewer viruses than spikes)
func fire_at(target: Node2D) -> void:
	var shots: int = tier_stats.get("multishot", 1)
	if shots <= 1:
		super.fire_at(target)
		return
	var targets := find_targets(_enemies_in_range(), shots)
	if targets.is_empty():
		targets = [target]
	for i in shots:
		_launch(targets[i % targets.size()])

# Chain Spike and Zero-Day act when a spike lands
func on_projectile_hit(enemy: Node2D, hit_damage: float) -> void:
	_chain_from(enemy, hit_damage)
	var every: int = tier_stats.get("stun_every_n_hits", 0)
	if every <= 0:
		return
	_hit_count += 1
	if _hit_count % every != 0 or not enemy.is_alive:
		return
	if enemy.stun_immune:
		enemy.apply_slow(tier_stats.get("boss_slow_factor", 0.5), tier_stats.get("boss_slow_duration", 1.0))
	else:
		enemy.apply_stun(tier_stats.get("stun_duration", 1.0))

# The spike jumps to the nearest other virus(es) for a share of the damage
func _chain_from(enemy: Node2D, hit_damage: float) -> void:
	var jumps: int = tier_stats.get("chain_targets", 0)
	if jumps <= 0:
		return
	var jump_px := CHAIN_JUMP_TILES * Globals.TILE_SIZE
	var candidates := _live_enemies().filter(func(e): return e != enemy and e.global_position.distance_to(enemy.global_position) <= jump_px)
	candidates.sort_custom(func(a, b): return a.global_position.distance_to(enemy.global_position) < b.global_position.distance_to(enemy.global_position))
	for i in mini(jumps, candidates.size()):
		_spawn_arc(enemy.global_position, candidates[i].global_position)
		candidates[i].take_damage(hit_damage * tier_stats.get("chain_damage_factor", 0.5), true)

# A short purple lightning bolt between the two viruses, fading out
func _spawn_arc(from: Vector2, to: Vector2) -> void:
	var parent = get_tree().get_first_node_in_group("projectile_container")
	if parent == null:
		return
	var mid := from.lerp(to, 0.5) + (to - from).orthogonal().normalized() * 14.0
	var line := Line2D.new()
	line.points = PackedVector2Array([from, mid, to])
	line.width = 4.0
	line.default_color = Globals.PATH_B_COLOR.lightened(0.5)
	parent.add_child(line)
	var tween := line.create_tween()
	tween.tween_property(line, "modulate:a", 0.0, 0.2)
	tween.tween_callback(line.queue_free)
