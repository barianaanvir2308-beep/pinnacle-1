class_name EMPTower extends BaseTower

var rotation_angle: float = 0.0
var pulse_radius: float = 0.0
var pulsing: bool = false

func _init():
	tower_type = Globals.TowerType.EMP_TOWER
	tower_type_export = Globals.TowerType.EMP_TOWER

func _process(delta):
	super._process(delta)
	rotation_angle += delta * 1.5
	
	if pulsing:
		pulse_radius += delta * 600.0
		var max_radius = Globals.get_tower_range_pixels(attack_range) if attack_range > 0 else 200.0
		if pulse_radius > max_radius:
			pulsing = false
	
	queue_redraw()

# The EMP pulses instead of shooting: every virus in range is stunned (see _pulse)
func try_attack(enemies: Array):
	if cooldown_timer > 0.0 or is_tower_disabled:
		return
	var in_range := enemies.filter(func(e): return is_instance_valid(e) and e.is_alive and is_in_range(e))
	if in_range.is_empty():
		return  # nothing to hit: the pulse is not wasted
	cooldown_timer = attack_interval
	_pulse(in_range)

func fire_at(_target: Node2D):
	pass  # the pulse hits an area, see try_attack

# Stuns every virus in range. Tiers add a longer stun and bonus damage while stunned (Overload), a slow after
# the stun and revealing hidden viruses (Scrambler), more damage and stunning bosses (Ion Storm).
func _pulse(targets: Array) -> void:
	pulse_radius = 20.0
	pulsing = true
	Audio.play_at(&"emp_pulse", global_position)
	var stun: float = tier_stats.get("stun", tower_data.get("stun", 1.0))
	var vulnerability: float = tier_stats.get("stunned_damage_taken_mult", 1.0)
	var slow_factor: float = tier_stats.get("post_stun_slow_factor", 1.0)
	var slow_time: float = tier_stats.get("post_stun_slow_duration", 0.0)
	var boss_stun: float = tier_stats.get("boss_stun", 0.0)
	var reveal: float = tier_stats.get("reveal_stealth_duration", 0.0)
	for enemy in targets:
		if reveal > 0.0:
			enemy.reveal(reveal)
		enemy.apply_stun(stun, vulnerability)  # bosses are slowed 50% instead
		if enemy.stun_immune:
			if boss_stun > 0.0:
				enemy.apply_stun(boss_stun, vulnerability, true)
		elif slow_factor < 1.0:
			enemy.apply_slow(slow_factor, stun + slow_time)  # the slow carries on after the stun ends
		enemy.take_damage(damage)

func _setup_visuals():
	super._setup_visuals()
	_load_art("emp_tower")

# System Freeze: every virus on the map. Bosses can't be frozen, so they are only slowed.
func _ability_has_targets(_ability: Dictionary) -> bool:
	return not _live_enemies().is_empty()

func _no_targets_text() -> String:
	return "NO VIRUSES ON THE MAP"

func _perform_ability(ability: Dictionary) -> void:
	if ability.get("id") != "system_freeze":
		return
	var freeze: float = ability.get("freeze", 0.0)
	var slow_factor: float = ability.get("slow_factor", 1.0)
	var slow_duration: float = ability.get("slow_duration", 0.0)
	for enemy in _live_enemies():
		if enemy.stun_immune:
			enemy.apply_slow(slow_factor, slow_duration)
		else:
			enemy.apply_stun(freeze)
			enemy.apply_slow(slow_factor, freeze + slow_duration)  # the slow runs on after the freeze ends
	_start_ring_fx(2400.0, Color(0.4, 0.8, 1.0), 0.9)

func _draw():
	if pulsing:
		var alpha = 1.0 - (pulse_radius / max(1.0, Globals.get_tower_range_pixels(attack_range)))
		alpha = clamp(alpha, 0.0, 1.0)
		var pulse_color = Color(0.2, 0.6, 1.0)
		pulse_color.a = alpha
		draw_arc(Vector2.ZERO, pulse_radius, 0, TAU, 32, pulse_color, 4.0 * alpha)
	super._draw()
