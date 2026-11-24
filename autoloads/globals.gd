# globals.gd — Global constants, enums, and configuration
# Autoloaded as "Globals"
extends Node

# =============================================================================
# GRID CONSTANTS
# =============================================================================
const TILE_SIZE: int = 120
const GRID_WIDTH: int = 16
const GRID_HEIGHT: int = 9
const GRID_OFFSET: Vector2 = Vector2(0, 80)
const PIXEL_SCALE: float = 4.0  # screen pixels per art pixel for pixel-art sprites

# =============================================================================
# GAME BALANCE (defaults — overridden per level)
# =============================================================================
const BASE_MAX_HEALTH: int = 100
const STARTING_ENERGY: int = 250  # Level 1; each level sets its own in LEVEL_DATA
const MAX_ENERGY: int = 1000  # Energy Capacity: income above it is lost
# TODO(difficulty_fix F2): 3.0 only stands in for the missing Energy Decoder. When Phase 4 adds the Decoder, set this back to 2.0.
const PASSIVE_ENERGY_RATE: float = 3.0  # Energy/s, only during waves and the countdowns before them
const SELL_REFUND_PERCENTAGE: float = 0.6  # of all Energy paid (scaling_and_upgrades B8)
const REPAIR_COST_FACTOR: float = 0.3  # repair = factor x missing-HP fraction x Energy paid for the tower

# Emergency Overclock and System Load (balance_spec 2.3)
const OVERCLOCK: Dictionary = {
	"energy": 150, "load": 50.0, "cooldown": 15.0,
	"decay_wave": 1.0, "decay_build": 2.0,                       # System Load lost per second
	"slow_threshold": 60.0, "slow_mult": 1.25,                   # towers attack 25% slower from this load
	"severe_threshold": 90.0, "severe_mult": 1.5,                # 50% slower, and passive income stops
	"crash_pause": 3.0, "crash_arduino_dmg_mult": 2.0, "crash_duration": 10.0, "crash_reset_load": 60.0,
	"unlock_wave_level_1": 3,                                    # Level 1 unlocks it at wave 3; later levels from the start
}

# Energy paid for clearing a wave: 15 + 10 x wave number (25 ... 115)
static func wave_bonus(wave_number: int) -> int:
	return 15 + 10 * wave_number
const TOTAL_WAVES: int = 10

# =============================================================================
# ENUMS
# =============================================================================
enum GameState {
	MAIN_MENU,
	LEVEL_SELECT,
	SETUP,
	BUILD_PHASE,
	WAVE_ACTIVE,
	WAVE_COMPLETE,
	PAUSED,
	GAME_OVER,
	VICTORY
}

enum CellType {
	BLOCKED,
	PATH,
	BUILDABLE,
	ARDUINO,
	SPAWN
}

enum TowerType {
	ANTIVIRUS_CANNON,
	DATA_SPIKE,
	EMP_TOWER,
	SNIPER_NODE,
	QUARANTINE_ZONE,
	FIREWALL_BEAM,
	OVERCLOCK_HUB
}

enum EnemyType {
	BASIC_VIRUS,
	TROJAN_HORSE,
	WORM,
	RANSOMWARE,
	SPYWARE,
	ROOTKIT,
	DDOS_BOT
}

enum TargetMode {
	FIRST,
	LAST,
	CLOSEST,
	STRONGEST
}

# =============================================================================
# TOWER DATA
# =============================================================================
const TOWER_DATA: Dictionary = {
	TowerType.ANTIVIRUS_CANNON: {
		"name": "Antivirus Cannon",
		"description": "General-purpose tower. Reliable damage at moderate range.",
		"cost": 100,
		"damage": 15,
		"range": 3.5,
		"attack_interval": 1.0,
		"target_mode": TargetMode.FIRST,
		"color": Color(0.0, 1.0, 0.53),
		"fire_sound": &"fire_cannon",  # sound id in audio/sound_bank.gd
		"scene_path": "res://scenes/towers/AntivirusCannon.tscn"
	},
	TowerType.DATA_SPIKE: {
		"name": "Data Spike",
		"description": "High damage, slow fire rate. Best against heavy targets.",
		"cost": 225,
		"damage": 80,
		"range": 4.5,
		"attack_interval": 2.5,
		"armor_pierce": true,  # behaviour added with the Rootkit armour rework
		"target_mode": TargetMode.STRONGEST,
		"color": Color(1.0, 0.2, 0.2),
		"fire_sound": &"fire_spike",
		"scene_path": "res://scenes/towers/DataSpike.tscn"
	},
	TowerType.EMP_TOWER: {
		"name": "EMP Tower",
		"description": "Pulses stun every virus in range. Crowd control, not damage.",
		"cost": 175,
		"damage": 4,
		"range": 2.5,
		"attack_interval": 4.0,
		"target_mode": TargetMode.CLOSEST,
		"stun": 1.0,  # seconds every virus in range is frozen by a pulse
		"color": Color(0.2, 0.6, 1.0),
		"scene_path": "res://scenes/towers/EMPTower.tscn"
	},
	TowerType.SNIPER_NODE: {
		"name": "Sniper Node",
		"description": "Extreme range, massive damage, very slow fire rate.",
		"cost": 350,
		"damage": 80,
		"range": 7.5,
		"attack_interval": 3.33,
		"target_mode": TargetMode.STRONGEST,
		"color": Color(0.8, 0.2, 0.8),
		"scene_path": "res://scenes/towers/SniperNode.tscn"
	},
	TowerType.QUARANTINE_ZONE: {
		"name": "Quarantine Zone",
		"description": "Deals rapid AoE damage. Essential against swarms.",
		"cost": 400,
		"damage": 8,
		"range": 2.5,
		"attack_interval": 5.0,
		"target_mode": TargetMode.FIRST,
		"color": Color(1.0, 0.64, 0.0),
		"scene_path": "res://scenes/towers/QuarantineZone.tscn"
	},
	TowerType.FIREWALL_BEAM: {
		"name": "Firewall Beam",
		"description": "Incredible fire rate that melts high armor targets.",
		"cost": 500,
		"damage": 2,
		"range": 4.0,
		"attack_interval": 20.0,
		"target_mode": TargetMode.CLOSEST,
		"color": Color(1.0, 0.9, 0.1),
		"fire_sound": &"fire_beam",
		"scene_path": "res://scenes/towers/FirewallBeam.tscn"
	},
	TowerType.OVERCLOCK_HUB: {
		"name": "Overclock Hub",
		"description": "Ultimate tower. Insane damage output.",
		"cost": 1000,
		"damage": 200,
		"range": 5.0,
		"attack_interval": 2.0,
		"target_mode": TargetMode.FIRST,
		"color": Color(1.0, 1.0, 1.0),
		"scene_path": "res://scenes/towers/OverclockHub.tscn"
	}
}

# difficulty_fix F7: Sniper Node, Quarantine Zone and Overclock Hub are hidden from the build menu until Phase 4 replaces
# them (the code stays). Firewall Beam stays on Level 4 and up.
func get_unlocked_towers(level_idx: int) -> Array[int]:
	var towers: Array[int] = [TowerType.ANTIVIRUS_CANNON, TowerType.DATA_SPIKE, TowerType.EMP_TOWER]
	if level_idx >= 3: towers.append(TowerType.FIREWALL_BEAM)
	return towers

# =============================================================================
# UPGRADE TREES (docs/scaling_and_upgrades.md)
# 2 paths × 3 tiers. Each tier lists ABSOLUTE stat values, not multipliers.
# A tier repeats every effect it keeps from the tiers below it.
# Slow factors multiply speed: 0.7 = 30% slower.
# Towers still to be built (Firewall, Quarantine Tower, Decoy, Scanner,
# Signal Booster, Energy Decoder) get their trees when they are added.
# =============================================================================
const TIER_COST_MULT: Array = [0.5, 1.0, 3.0]           # T1, T2, T3 × base cost (rounded to 5)
const TIER_HP_MULT: Array = [1.0, 1.15, 1.35, 1.7]      # by highest tier owned (0..3)
const CROSSPATH_SECONDARY_MAX: int = 1                  # other path capped at T1
const MAX_TIER: int = 3
const PATH_B_COLOR: Color = Color(0.55, 0.35, 1.0)      # shared "utility" colour for path B

const UPGRADE_TREES: Dictionary = {
	TowerType.ANTIVIRUS_CANNON: {
		"A": {"name": "Heuristics", "tiers": [
			{"name": "Signature Update", "cost": 50, "desc": "Damage 15 → 24",
				"damage": 24.0},
			{"name": "Deep Scan", "cost": 100, "desc": "Damage 28, pierces 2, sees Stealth within 1.5 tiles",
				"damage": 28.0, "pierce": 2, "stealth_detect_range": 1.5},
			{"name": "Heuristic Engine", "cost": 300, "desc": "Fires a 3-shot burst",
				"damage": 28.0, "pierce": 2, "burst_count": 3, "stealth_detect_range": 1.5},
		]},
		"B": {"name": "Scan Rate", "tiers": [
			{"name": "Multithreaded", "cost": 50, "desc": "Fires every 0.7 s",
				"attack_interval": 0.7},
			{"name": "Wide Scan", "cost": 100, "desc": "Range +1, 30% splash",
				"attack_interval": 0.7, "range": 4.5, "splash_factor": 0.3, "splash_radius": 0.75},
			{"name": "Full System Scan", "cost": 300, "desc": "Fires every 0.35 s, 50% splash",
				"attack_interval": 0.35, "range": 4.5, "splash_factor": 0.5, "splash_radius": 0.75},
		]},
	},
	TowerType.DATA_SPIKE: {
		"A": {"name": "Payload", "tiers": [
			{"name": "Larger Payload", "cost": 115, "desc": "Damage 80 → 120",
				"damage": 120.0},
			{"name": "Kernel Exploit", "cost": 225, "desc": "Damage 160, +50% vs Bosses and unsplit Trojans",
				"damage": 160.0, "boss_trojan_bonus": 0.5},
			{"name": "Zero-Day", "cost": 675, "desc": "Damage 500, every 3rd hit stuns 1 s",
				"damage": 500.0,
				"stun_every_n_hits": 3, "stun_duration": 1.0, "boss_slow_factor": 0.5, "boss_slow_duration": 1.0},
		]},
		"B": {"name": "Spike Array", "tiers": [
			{"name": "Fast Compile", "cost": 115, "desc": "Fires every 1.7 s",
				"attack_interval": 1.7},
			{"name": "Chain Spike", "cost": 225, "desc": "Jumps to a 2nd target for 50%, range +0.5",
				"attack_interval": 1.7, "range": 5.0, "chain_targets": 1, "chain_damage_factor": 0.5},
			{"name": "Spike Storm", "cost": 675, "desc": "3 spikes at the 3 strongest. Ability: Purge",
				"attack_interval": 1.7, "range": 5.0,
				"multishot": 3,
				"ability": {"id": "purge", "name": "Purge", "cooldown": 45.0, "damage": 150.0}},
		]},
	},
	TowerType.EMP_TOWER: {
		"A": {"name": "Pulse Control", "tiers": [
			{"name": "Capacitor", "cost": 90, "desc": "Pulses every 3.3 s",
				"attack_interval": 3.3},
			{"name": "Overload", "cost": 175, "desc": "Stun 1.5 s, stunned viruses take +15% damage",
				"attack_interval": 3.3, "stun": 1.5, "stunned_damage_taken_mult": 1.15},
			{"name": "System Freeze", "cost": 525, "desc": "Ability: freeze every virus for 3 s",
				"attack_interval": 3.3, "stun": 1.5, "stunned_damage_taken_mult": 1.15,
				"ability": {"id": "system_freeze", "name": "System Freeze", "cooldown": 50.0, "freeze": 3.0,
					"slow_factor": 0.5, "slow_duration": 6.0}},
		]},
		"B": {"name": "Disruptor", "tiers": [
			{"name": "Wide Pulse", "cost": 90, "desc": "Radius 2.5 → 3.0",
				"range": 3.0},
			{"name": "Scrambler", "cost": 175, "desc": "30% slow for 2 s after the stun, reveals Stealth",
				"range": 3.0, "post_stun_slow_factor": 0.7, "post_stun_slow_duration": 2.0,
				"reveal_stealth_duration": 1.0},
			{"name": "Ion Storm", "cost": 525, "desc": "Pulses deal 25 damage and stun bosses 0.5 s",
				"range": 3.0, "post_stun_slow_factor": 0.7, "post_stun_slow_duration": 2.0,
				"reveal_stealth_duration": 1.0, "damage": 25.0, "boss_stun": 0.5},
		]},
	},
}

# =============================================================================
# ENEMY DATA
# =============================================================================
const ENEMY_DATA: Dictionary = {
	EnemyType.BASIC_VIRUS: {
		"name": "Basic Virus",
		"description": "Standard virus. Takes the shortest route to the Arduino.",
		"health": 60, "speed": 1.0, "base_damage": 5, "reward": 4,
		"color": Color(1.0, 0.3, 0.3),
		"scene_path": "res://scenes/enemies/BasicVirus.tscn"
	},
	EnemyType.WORM: {
		"name": "Worm",
		"description": "Fast. Hits every module it reaches for 25 damage, then spreads once.",
		"health": 35, "speed": 1.7, "base_damage": 1, "reward": 3,  # base_damage 2 -> 1 (balance playtest)
		"module_damage": 15.0,  # damage to each module it bites (difficulty_fix F3; the balance_spec value is 25)
		"max_bites": 2,         # an original Worm bites at most this many modules
		# TODO(difficulty_fix F3): 0 is interim - a spread clone walks to the Arduino without biting (it was 1, which
		# let Worm clones keep killing Cannons on Level 1). Decide the final value when balancing is revisited.
		"clone_max_bites": 0,   # and the Worm it spreads bites at most this many
		"color": Color(0.3, 1.0, 0.3),
		"scene_path": "res://scenes/enemies/Worm.tscn"
	},
	EnemyType.TROJAN_HORSE: {
		"name": "Trojan Horse",
		"description": "Tough and slow. After 8 seconds alive it splits into 3 Minis. Kill it first.",
		"health": 220, "speed": 0.6, "base_damage": 7, "reward": 10,  # base_damage 15 -> 10 -> 7 (balance playtest)
		"split_time": 8.0,  # seconds alive before it splits (paused while stunned or trapped)
		"split_count": 3, "split_health": 30, "split_speed": 1.2,
		"split_damage": 3, "split_reward": 1,
		"color": Color(0.8, 0.2, 1.0),
		"scene_path": "res://scenes/enemies/TrojanHorse.tscn"
	},
	EnemyType.RANSOMWARE: {
		"name": "Ransomware",
		"description": "Marks the most valuable module near it, then locks it for 5 seconds.",
		"health": 160, "speed": 0.8, "base_damage": 5, "reward": 9,
		# TODO(difficulty_fix F4): lock_time 3.0 and max_locks 2 stand in for the missing Scanner. When Phase 4 adds the
		# Scanner, restore lock_time to 5.0 and remove max_locks (and its check in ransomware.gd).
		"lock_time": 3.0, "max_locks": 2, "lock_damage": 10.0, "mark_lead_time": 2.0,
		"color": Color(1.0, 0.0, 0.5),
		"scene_path": "res://scenes/enemies/Ransomware.tscn"
	},
	EnemyType.SPYWARE: {
		"name": "Spyware",
		"description": "Escort. Follows the nearest virus; viruses near it move 20% faster and take 20% less damage.",
		"health": 80, "speed": 1.0, "base_damage": 0, "reward": 10,
		"aura_radius": 1.5,  # tiles
		"aura_speed": 1.2, "aura_damage_taken": 0.8,
		"color": Color(0.4, 0.8, 1.0),
		"scene_path": "res://scenes/enemies/Spyware.tscn"
	},
	EnemyType.ROOTKIT: {
		"name": "Rootkit",
		"description": "Heavy armour takes 5 off every hit (minimum 1), except from the Data Spike.",
		"health": 320, "speed": 0.42, "base_damage": 15, "reward": 20,  # base_damage 25 -> 15 (balance playtest); the balance_spec value is 25
		"armor_flat": 5.0,  # damage removed from every hit (a hit always does at least 1); the Data Spike ignores it (8 -> 5, balance playtest)
		"color": Color(0.6, 0.4, 0.1),
		"scene_path": "res://scenes/enemies/Rootkit.tscn"
	},
	EnemyType.DDOS_BOT: {
		"name": "DDoS Bot",
		"description": "Tiny and fast. Dangerous in massive swarms.",
		"health": 20, "speed": 2.0, "base_damage": 1, "reward": 1,
		"color": Color(1.0, 1.0, 0.2),
		"scene_path": "res://scenes/enemies/DDoSBot.tscn"
	}
}

# =============================================================================
# MAP LAYOUTS (16×9 each)
# 0=BLOCKED, 1=PATH, 2=BUILDABLE, 3=ARDUINO, 4=SPAWN
# =============================================================================

const MAP_1_BOOTLOADER: Array = [
	[0, 0, 0, 4, 0, 0, 0, 0, 4, 0, 0, 0, 0, 0, 0, 0],
	[0, 2, 2, 1, 1, 1, 2, 2, 1, 1, 1, 2, 2, 2, 0, 0],
	[0, 2, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 2, 0, 0],
	[4, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0],
	[0, 2, 0, 1, 0, 2, 0, 0, 0, 0, 2, 0, 0, 1, 3, 0],
	[4, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0],
	[0, 2, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 2, 0, 0],
	[0, 2, 2, 1, 1, 1, 2, 2, 1, 1, 1, 2, 2, 2, 0, 0],
	[0, 0, 0, 4, 0, 0, 0, 0, 4, 0, 0, 0, 0, 0, 0, 0],
]

const MAP_2_DUAL_BUS: Array = [
	[4, 1, 1, 1, 1, 2, 0, 0, 0, 0, 2, 1, 1, 1, 1, 4],
	[0, 2, 0, 0, 1, 2, 0, 0, 0, 0, 2, 1, 0, 0, 2, 0],
	[0, 2, 2, 0, 1, 2, 2, 2, 2, 2, 2, 1, 0, 2, 2, 0],
	[0, 0, 2, 0, 1, 1, 1, 1, 1, 1, 1, 1, 0, 2, 0, 0],
	[0, 0, 2, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0, 2, 0, 0],
	[0, 0, 2, 0, 1, 1, 1, 1, 1, 1, 1, 1, 0, 2, 0, 0],
	[0, 2, 2, 0, 1, 2, 2, 2, 2, 2, 2, 1, 0, 2, 2, 0],
	[0, 2, 0, 0, 1, 2, 0, 0, 0, 0, 2, 1, 0, 0, 2, 0],
	[4, 1, 1, 1, 1, 2, 0, 0, 0, 0, 2, 1, 1, 1, 1, 4],
]

const MAP_3_SPIRAL_CORE: Array = [
	[4, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 4],
	[0, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 0],
	[0, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0],
	[0, 2, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 2, 1, 0],
	[0, 2, 1, 2, 1, 1, 1, 3, 1, 1, 1, 2, 1, 2, 1, 0],
	[0, 2, 1, 2, 2, 2, 2, 2, 2, 2, 1, 2, 1, 2, 1, 0],
	[0, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 1, 2, 1, 0],
	[0, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 2, 1, 0],
	[4, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 1, 0],
]

const MAP_4_FIREWALL_BREACH: Array = [
	[0, 4, 0, 0, 0, 4, 0, 0, 0, 0, 4, 0, 0, 0, 4, 0],
	[0, 1, 2, 2, 0, 1, 2, 0, 0, 2, 1, 0, 2, 2, 1, 0],
	[0, 1, 0, 2, 0, 1, 2, 0, 0, 2, 1, 0, 2, 0, 1, 0],
	[0, 1, 1, 1, 1, 1, 2, 0, 0, 2, 1, 1, 1, 1, 1, 0],
	[0, 0, 0, 2, 0, 1, 1, 1, 3, 1, 1, 0, 2, 0, 0, 0],
	[0, 1, 1, 1, 1, 1, 2, 0, 0, 2, 1, 1, 1, 1, 1, 0],
	[0, 1, 0, 2, 0, 1, 2, 0, 0, 2, 1, 0, 2, 0, 1, 0],
	[0, 1, 2, 2, 0, 1, 2, 0, 0, 2, 1, 0, 2, 2, 1, 0],
	[0, 4, 0, 0, 0, 4, 0, 0, 0, 0, 4, 0, 0, 0, 4, 0],
]

const MAP_5_KERNEL_PANIC: Array = [
	[0, 0, 0, 0, 0, 0, 0, 4, 0, 0, 0, 0, 0, 0, 0, 0],
	[0, 2, 2, 2, 0, 2, 0, 1, 0, 2, 0, 2, 2, 2, 0, 0],
	[0, 2, 0, 2, 0, 2, 0, 1, 0, 2, 0, 2, 0, 2, 0, 0],
	[4, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 4],
	[0, 2, 0, 2, 0, 2, 0, 3, 0, 2, 0, 2, 0, 2, 0, 0],
	[4, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 4],
	[0, 2, 0, 2, 0, 2, 0, 1, 0, 2, 0, 2, 0, 2, 0, 0],
	[0, 2, 2, 2, 0, 2, 0, 1, 0, 2, 0, 2, 2, 2, 0, 0],
	[0, 0, 0, 0, 0, 0, 0, 4, 0, 0, 0, 0, 0, 0, 0, 0],
]

# Current active map (changed when loading a level)
var active_map: Array = MAP_1_BOOTLOADER

# =============================================================================
# LEVEL DATA — 5 levels, each with map + waves + config
# =============================================================================
# INTERIM wave tables from docs/difficulty_fix.md (F1). They replace the balance_spec 5.3 tables
# only until Phase 4 (new towers and the Stealth/Boss viruses) is done.
# TODO(difficulty_fix): when Phase 4 lands, put the balance_spec 5.3 tables back (see difficulty_fix.md section 6).
const LEVEL_DATA: Array = [
	# ===== LEVEL 1: BOOTLOADER =====
	{
		"name": "Bootloader",
		"description": "Basic system initialization. Learn the fundamentals.",
		"map": "MAP_1_BOOTLOADER",
		"spawns": [Vector2i(0, 3), Vector2i(0, 5)],  # Level 1 uses only the two left spawns (difficulty_fix F5)
		"starting_energy": 300,
		"arduino_hp": 100,
		"waves": [
			{"wave_id":1, "enemies":[{"type":EnemyType.BASIC_VIRUS,"count":5}], "spawn_interval":2.00, "health_multiplier":0.85, "speed_multiplier":1.00, "description":"INCOMING: Basic virus detected"},
			{"wave_id":2, "enemies":[{"type":EnemyType.BASIC_VIRUS,"count":7}], "spawn_interval":1.80, "health_multiplier":1.08, "speed_multiplier":1.00, "description":"WARNING: Virus count increasing"},
			{"wave_id":3, "enemies":[{"type":EnemyType.BASIC_VIRUS,"count":8},{"type":EnemyType.WORM,"count":4}], "spawn_interval":1.20, "health_multiplier":1.16, "speed_multiplier":1.00, "description":"ALERT: Worm detected"},
			{"wave_id":4, "enemies":[{"type":EnemyType.BASIC_VIRUS,"count":10},{"type":EnemyType.WORM,"count":6}], "spawn_interval":1.10, "health_multiplier":1.24, "speed_multiplier":1.00, "description":"CRITICAL: Mixed threat incoming"},
			{"wave_id":5, "enemies":[{"type":EnemyType.TROJAN_HORSE,"count":2},{"type":EnemyType.BASIC_VIRUS,"count":10}], "spawn_interval":1.00, "health_multiplier":1.32, "speed_multiplier":1.00, "description":"DANGER: Trojan Horse detected"},
			{"wave_id":6, "enemies":[{"type":EnemyType.WORM,"count":10},{"type":EnemyType.BASIC_VIRUS,"count":10}], "spawn_interval":0.85, "health_multiplier":1.40, "speed_multiplier":1.00, "description":"SEVERE: Complex attack pattern"},
			{"wave_id":7, "enemies":[{"type":EnemyType.BASIC_VIRUS,"count":14},{"type":EnemyType.WORM,"count":8},{"type":EnemyType.TROJAN_HORSE,"count":3}], "spawn_interval":0.95, "health_multiplier":1.48, "speed_multiplier":1.00, "description":"EMERGENCY: Mass infiltration"},
			{"wave_id":8, "enemies":[{"type":EnemyType.BASIC_VIRUS,"count":15},{"type":EnemyType.WORM,"count":10},{"type":EnemyType.TROJAN_HORSE,"count":3}], "spawn_interval":0.90, "health_multiplier":1.56, "speed_multiplier":1.00, "description":"CRITICAL: System overload"},
			{"wave_id":9, "enemies":[{"type":EnemyType.BASIC_VIRUS,"count":19},{"type":EnemyType.WORM,"count":10},{"type":EnemyType.TROJAN_HORSE,"count":5}], "spawn_interval":0.90, "health_multiplier":1.64, "speed_multiplier":1.00, "description":"BREACH: Firewall failing"},
			{"wave_id":10, "enemies":[{"type":EnemyType.BASIC_VIRUS,"count":24},{"type":EnemyType.WORM,"count":10},{"type":EnemyType.TROJAN_HORSE,"count":7}], "spawn_interval":0.85, "health_multiplier":1.72, "speed_multiplier":1.00, "description":"FINAL: All viruses converging"},
		]
	},
	# ===== LEVEL 2: DUAL BUS =====
	{
		"name": "Dual Bus",
		"description": "Two parallel data buses. Ransomware disables your towers.",
		"map": "MAP_2_DUAL_BUS",
		"starting_energy": 350,
		"arduino_hp": 100,
		"waves": [
			{"wave_id":1, "enemies":[{"type":EnemyType.BASIC_VIRUS,"count":8}], "spawn_interval":2.00, "health_multiplier":0.80, "speed_multiplier":1.00, "description":"SCANNING: Dual bus traffic detected"},
			{"wave_id":2, "enemies":[{"type":EnemyType.BASIC_VIRUS,"count":6},{"type":EnemyType.WORM,"count":6}], "spawn_interval":1.80, "health_multiplier":1.19, "speed_multiplier":1.00, "description":"WARNING: Mixed signals on both buses"},
			{"wave_id":3, "enemies":[{"type":EnemyType.RANSOMWARE,"count":2},{"type":EnemyType.BASIC_VIRUS,"count":10}], "spawn_interval":1.75, "health_multiplier":1.28, "speed_multiplier":1.00, "description":"ALERT: RANSOMWARE DETECTED — towers at risk!"},
			{"wave_id":4, "enemies":[{"type":EnemyType.TROJAN_HORSE,"count":2},{"type":EnemyType.WORM,"count":10},{"type":EnemyType.BASIC_VIRUS,"count":6}], "spawn_interval":1.60, "health_multiplier":1.36, "speed_multiplier":1.00, "description":"DANGER: Multi-vector attack"},
			{"wave_id":5, "enemies":[{"type":EnemyType.RANSOMWARE,"count":4},{"type":EnemyType.BASIC_VIRUS,"count":12},{"type":EnemyType.TROJAN_HORSE,"count":2},{"type":EnemyType.SPYWARE,"count":1}], "spawn_interval":1.45, "health_multiplier":1.45, "speed_multiplier":1.00, "description":"CRITICAL: Ransomware swarm"},
			{"wave_id":6, "enemies":[{"type":EnemyType.WORM,"count":10},{"type":EnemyType.TROJAN_HORSE,"count":4},{"type":EnemyType.BASIC_VIRUS,"count":3}], "spawn_interval":1.15, "health_multiplier":1.54, "speed_multiplier":1.00, "description":"SEVERE: Bus overload imminent"},
			{"wave_id":7, "enemies":[{"type":EnemyType.BASIC_VIRUS,"count":16},{"type":EnemyType.RANSOMWARE,"count":5},{"type":EnemyType.WORM,"count":10},{"type":EnemyType.SPYWARE,"count":2}], "spawn_interval":0.80, "health_multiplier":1.63, "speed_multiplier":1.00, "description":"EMERGENCY: Encryption spreading"},
			{"wave_id":8, "enemies":[{"type":EnemyType.TROJAN_HORSE,"count":5},{"type":EnemyType.RANSOMWARE,"count":5},{"type":EnemyType.BASIC_VIRUS,"count":14}], "spawn_interval":1.00, "health_multiplier":1.72, "speed_multiplier":1.00, "description":"BREACH: Dual bus compromised"},
			{"wave_id":9, "enemies":[{"type":EnemyType.RANSOMWARE,"count":6},{"type":EnemyType.TROJAN_HORSE,"count":6},{"type":EnemyType.WORM,"count":10},{"type":EnemyType.SPYWARE,"count":2},{"type":EnemyType.BASIC_VIRUS,"count":3}], "spawn_interval":1.10, "health_multiplier":1.80, "speed_multiplier":1.00, "description":"MELTDOWN: All defenses targeted"},
			{"wave_id":10, "enemies":[{"type":EnemyType.TROJAN_HORSE,"count":3},{"type":EnemyType.BASIC_VIRUS,"count":14},{"type":EnemyType.RANSOMWARE,"count":5},{"type":EnemyType.WORM,"count":10}], "spawn_interval":0.70, "health_multiplier":1.89, "speed_multiplier":1.00, "description":"FINAL: Total bus lockdown"},
		]
	},
	# ===== LEVEL 3: SPIRAL CORE =====
	{
		"name": "Spiral Core",
		"description": "Spiral paths to the core. Spyware escorts and DDoS swarms.",
		"map": "MAP_3_SPIRAL_CORE",
		"starting_energy": 400,
		"arduino_hp": 100,
		"waves": [
			{"wave_id":1, "enemies":[{"type":EnemyType.BASIC_VIRUS,"count":10},{"type":EnemyType.WORM,"count":5}], "spawn_interval":2.00, "health_multiplier":1.20, "speed_multiplier":1.00, "description":"SPIRAL SCAN: Threats entering from edges"},
			{"wave_id":2, "enemies":[{"type":EnemyType.DDOS_BOT,"count":30,"interval":0.2}], "spawn_interval":0.30, "health_multiplier":1.50, "speed_multiplier":1.00, "description":"ALERT: DDoS SWARM INCOMING — mass targets!"},
			{"wave_id":3, "enemies":[{"type":EnemyType.BASIC_VIRUS,"count":14}], "spawn_interval":0.30, "health_multiplier":1.45, "speed_multiplier":1.00, "description":"WARNING: Virus density rising"},
			{"wave_id":4, "enemies":[{"type":EnemyType.DDOS_BOT,"count":35,"interval":0.2},{"type":EnemyType.RANSOMWARE,"count":3}], "spawn_interval":1.20, "health_multiplier":1.49, "speed_multiplier":1.00, "description":"DANGER: DDoS cover for ransomware"},
			{"wave_id":5, "enemies":[{"type":EnemyType.BASIC_VIRUS,"count":5},{"type":EnemyType.TROJAN_HORSE,"count":4},{"type":EnemyType.WORM,"count":10},{"type":EnemyType.SPYWARE,"count":2}], "spawn_interval":0.70, "health_multiplier":1.88, "speed_multiplier":1.00, "description":"CRITICAL: Escorted assault in progress"},
			{"wave_id":6, "enemies":[{"type":EnemyType.DDOS_BOT,"count":45,"interval":0.2},{"type":EnemyType.BASIC_VIRUS,"count":5}], "spawn_interval":0.30, "health_multiplier":2.50, "speed_multiplier":1.00, "description":"SWARM: Packet flood on the spiral"},
			{"wave_id":7, "enemies":[{"type":EnemyType.RANSOMWARE,"count":5},{"type":EnemyType.TROJAN_HORSE,"count":5},{"type":EnemyType.BASIC_VIRUS,"count":17},{"type":EnemyType.SPYWARE,"count":2}], "spawn_interval":0.65, "health_multiplier":2.08, "speed_multiplier":1.00, "description":"EMERGENCY: Core defenses under siege"},
			{"wave_id":8, "enemies":[{"type":EnemyType.DDOS_BOT,"count":50,"interval":0.2},{"type":EnemyType.RANSOMWARE,"count":6},{"type":EnemyType.WORM,"count":10}], "spawn_interval":0.30, "health_multiplier":2.50, "speed_multiplier":1.00, "description":"MELTDOWN: Spiral overwhelmed"},
			{"wave_id":9, "enemies":[{"type":EnemyType.BASIC_VIRUS,"count":21},{"type":EnemyType.TROJAN_HORSE,"count":6},{"type":EnemyType.RANSOMWARE,"count":6},{"type":EnemyType.SPYWARE,"count":3}], "spawn_interval":0.35, "health_multiplier":2.27, "speed_multiplier":1.00, "description":"BREACH: All spiral layers penetrated"},
			{"wave_id":10, "enemies":[{"type":EnemyType.TROJAN_HORSE,"count":3},{"type":EnemyType.DDOS_BOT,"count":40,"interval":0.2},{"type":EnemyType.BASIC_VIRUS,"count":6},{"type":EnemyType.RANSOMWARE,"count":5},{"type":EnemyType.SPYWARE,"count":2}], "spawn_interval":0.30, "health_multiplier":2.60, "speed_multiplier":1.00, "description":"FINAL: Core meltdown imminent"},
		]
	},
	# ===== LEVEL 4: FIREWALL BREACH =====
	{
		"name": "Firewall Breach",
		"description": "The firewall has been breached. Rootkits are nearly invincible.",
		"map": "MAP_4_FIREWALL_BREACH",
		"starting_energy": 500,
		"arduino_hp": 100,
		"waves": [
			{"wave_id":1, "enemies":[{"type":EnemyType.BASIC_VIRUS,"count":12},{"type":EnemyType.RANSOMWARE,"count":3}], "spawn_interval":2.00, "health_multiplier":0.75, "speed_multiplier":1.00, "description":"BREACH: Firewall perimeter compromised"},
			{"wave_id":2, "enemies":[{"type":EnemyType.BASIC_VIRUS,"count":13},{"type":EnemyType.WORM,"count":8}], "spawn_interval":1.35, "health_multiplier":1.24, "speed_multiplier":1.00, "description":"ALERT: ROOTKIT DETECTED — armoured threat!"},
			{"wave_id":3, "enemies":[{"type":EnemyType.DDOS_BOT,"count":35,"interval":0.2},{"type":EnemyType.BASIC_VIRUS,"count":4}], "spawn_interval":1.15, "health_multiplier":1.33, "speed_multiplier":1.00, "description":"SWARM: DDoS flood incoming"},
			{"wave_id":4, "enemies":[{"type":EnemyType.ROOTKIT,"count":1},{"type":EnemyType.RANSOMWARE,"count":3},{"type":EnemyType.WORM,"count":10}], "spawn_interval":2.00, "health_multiplier":1.00, "speed_multiplier":1.00, "description":"DANGER: Armoured assault with support"},
			{"wave_id":5, "enemies":[{"type":EnemyType.TROJAN_HORSE,"count":4},{"type":EnemyType.ROOTKIT,"count":2},{"type":EnemyType.DDOS_BOT,"count":30,"interval":0.2},{"type":EnemyType.SPYWARE,"count":2}], "spawn_interval":2.10, "health_multiplier":1.00, "speed_multiplier":1.00, "description":"CRITICAL: Heavy units with DDoS screen"},
			{"wave_id":6, "enemies":[{"type":EnemyType.BASIC_VIRUS,"count":6},{"type":EnemyType.RANSOMWARE,"count":6},{"type":EnemyType.ROOTKIT,"count":2}], "spawn_interval":1.90, "health_multiplier":1.61, "speed_multiplier":1.00, "description":"SEVERE: Disable + armour combo"},
			{"wave_id":7, "enemies":[{"type":EnemyType.ROOTKIT,"count":3},{"type":EnemyType.TROJAN_HORSE,"count":5},{"type":EnemyType.BASIC_VIRUS,"count":14},{"type":EnemyType.SPYWARE,"count":3}], "spawn_interval":1.55, "health_multiplier":1.70, "speed_multiplier":1.00, "description":"EMERGENCY: Tank column approaching"},
			{"wave_id":8, "enemies":[{"type":EnemyType.DDOS_BOT,"count":40,"interval":0.2},{"type":EnemyType.ROOTKIT,"count":3},{"type":EnemyType.RANSOMWARE,"count":6},{"type":EnemyType.WORM,"count":10}], "spawn_interval":1.00, "health_multiplier":1.79, "speed_multiplier":1.05, "description":"MELTDOWN: Full spectrum assault"},
			{"wave_id":9, "enemies":[{"type":EnemyType.ROOTKIT,"count":4},{"type":EnemyType.BASIC_VIRUS,"count":7},{"type":EnemyType.TROJAN_HORSE,"count":6},{"type":EnemyType.RANSOMWARE,"count":6},{"type":EnemyType.SPYWARE,"count":3}], "spawn_interval":1.30, "health_multiplier":1.89, "speed_multiplier":1.05, "description":"BREACH: Deep system compromise"},
			{"wave_id":10, "enemies":[{"type":EnemyType.ROOTKIT,"count":5},{"type":EnemyType.DDOS_BOT,"count":40,"interval":0.2},{"type":EnemyType.RANSOMWARE,"count":6},{"type":EnemyType.TROJAN_HORSE,"count":4},{"type":EnemyType.SPYWARE,"count":3}], "spawn_interval":1.15, "health_multiplier":1.98, "speed_multiplier":1.05, "description":"FINAL: Firewall completely destroyed"},
		]
	},
	# ===== LEVEL 5: KERNEL PANIC =====
	{
		"name": "Kernel Panic",
		"description": "All systems failing. Enemies from every direction. Survive.",
		"map": "MAP_5_KERNEL_PANIC",
		"starting_energy": 600,
		"arduino_hp": 100,
		"waves": [
			{"wave_id":1, "enemies":[{"type":EnemyType.BASIC_VIRUS,"count":12},{"type":EnemyType.WORM,"count":8},{"type":EnemyType.DDOS_BOT,"count":20,"interval":0.30}], "spawn_interval":2.10, "health_multiplier":1.20, "speed_multiplier":1.05, "description":"KERNEL PANIC: All ports under attack"},
			{"wave_id":2, "enemies":[{"type":EnemyType.RANSOMWARE,"count":4},{"type":EnemyType.BASIC_VIRUS,"count":12},{"type":EnemyType.TROJAN_HORSE,"count":3},{"type":EnemyType.SPYWARE,"count":2}], "spawn_interval":2.00, "health_multiplier":0.90, "speed_multiplier":1.05, "description":"CRITICAL: Heavy assault from all sides"},
			{"wave_id":3, "enemies":[{"type":EnemyType.DDOS_BOT,"count":45,"interval":0.30},{"type":EnemyType.BASIC_VIRUS,"count":6}], "spawn_interval":0.90, "health_multiplier":1.39, "speed_multiplier":1.05, "description":"SWARM: Flood from every direction"},
			{"wave_id":4, "enemies":[{"type":EnemyType.TROJAN_HORSE,"count":6},{"type":EnemyType.RANSOMWARE,"count":5},{"type":EnemyType.ROOTKIT,"count":1}], "spawn_interval":2.00, "health_multiplier":0.85, "speed_multiplier":1.05, "description":"DANGER: Elite virus squad deployed"},
			{"wave_id":5, "enemies":[{"type":EnemyType.TROJAN_HORSE,"count":3},{"type":EnemyType.BASIC_VIRUS,"count":10},{"type":EnemyType.WORM,"count":8},{"type":EnemyType.SPYWARE,"count":2}], "spawn_interval":0.95, "health_multiplier":1.58, "speed_multiplier":1.05, "description":"FLOOD: System resources exhausted"},
			{"wave_id":6, "enemies":[{"type":EnemyType.ROOTKIT,"count":2},{"type":EnemyType.RANSOMWARE,"count":6},{"type":EnemyType.TROJAN_HORSE,"count":6},{"type":EnemyType.BASIC_VIRUS,"count":6}], "spawn_interval":2.10, "health_multiplier":1.60, "speed_multiplier":1.05, "description":"SEVERE: Coordinated multi-vector assault"},
			{"wave_id":7, "enemies":[{"type":EnemyType.DDOS_BOT,"count":55,"interval":0.30},{"type":EnemyType.ROOTKIT,"count":2},{"type":EnemyType.RANSOMWARE,"count":6},{"type":EnemyType.WORM,"count":10},{"type":EnemyType.SPYWARE,"count":3},{"type":EnemyType.BASIC_VIRUS,"count":2}], "spawn_interval":0.90, "health_multiplier":1.78, "speed_multiplier":1.05, "description":"MELTDOWN: Kernel integrity failing"},
			{"wave_id":8, "enemies":[{"type":EnemyType.ROOTKIT,"count":4},{"type":EnemyType.TROJAN_HORSE,"count":7},{"type":EnemyType.BASIC_VIRUS,"count":7},{"type":EnemyType.RANSOMWARE,"count":7},{"type":EnemyType.SPYWARE,"count":3}], "spawn_interval":1.65, "health_multiplier":1.87, "speed_multiplier":1.10, "description":"CRITICAL: Elite forces converging"},
			{"wave_id":9, "enemies":[{"type":EnemyType.DDOS_BOT,"count":60,"interval":0.2},{"type":EnemyType.BASIC_VIRUS,"count":18},{"type":EnemyType.WORM,"count":10},{"type":EnemyType.ROOTKIT,"count":3},{"type":EnemyType.RANSOMWARE,"count":5}], "spawn_interval":0.35, "health_multiplier":1.97, "speed_multiplier":1.10, "description":"APOCALYPSE: Total system failure imminent"},
			{"wave_id":10, "enemies":[{"type":EnemyType.ROOTKIT,"count":4},{"type":EnemyType.TROJAN_HORSE,"count":6},{"type":EnemyType.RANSOMWARE,"count":6},{"type":EnemyType.BASIC_VIRUS,"count":7},{"type":EnemyType.DDOS_BOT,"count":50,"interval":0.2},{"type":EnemyType.WORM,"count":10},{"type":EnemyType.SPYWARE,"count":4}], "spawn_interval":0.85, "health_multiplier":2.06, "speed_multiplier":1.10, "description":"FINAL: KERNEL PANIC — SURVIVE OR DIE"},
		]
	},
]

# =============================================================================
# RUNTIME STATE
# =============================================================================
var current_level: int = 0  # Index into LEVEL_DATA
var levels_unlocked: int = 1  # How many levels are unlocked (1-5)

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

static func grid_to_world(grid_pos: Vector2i) -> Vector2:
	return Vector2(
		grid_pos.x * TILE_SIZE + TILE_SIZE / 2.0 + GRID_OFFSET.x,
		grid_pos.y * TILE_SIZE + TILE_SIZE / 2.0 + GRID_OFFSET.y
	)

static func world_to_grid(world_pos: Vector2) -> Vector2i:
	return Vector2i(
		int((world_pos.x - GRID_OFFSET.x) / TILE_SIZE),
		int((world_pos.y - GRID_OFFSET.y) / TILE_SIZE)
	)

static func is_valid_grid_pos(grid_pos: Vector2i) -> bool:
	return grid_pos.x >= 0 and grid_pos.x < GRID_WIDTH and \
		   grid_pos.y >= 0 and grid_pos.y < GRID_HEIGHT

func get_cell_type(grid_pos: Vector2i) -> CellType:
	if not is_valid_grid_pos(grid_pos):
		return CellType.BLOCKED
	return active_map[grid_pos.y][grid_pos.x] as CellType

static func get_tower_range_pixels(range_tiles: float) -> float:
	return range_tiles * TILE_SIZE

func get_map_for_level(level_index: int) -> Array:
	var map_name = LEVEL_DATA[level_index].map
	match map_name:
		"MAP_1_BOOTLOADER": return MAP_1_BOOTLOADER
		"MAP_2_DUAL_BUS": return MAP_2_DUAL_BUS
		"MAP_3_SPIRAL_CORE": return MAP_3_SPIRAL_CORE
		"MAP_4_FIREWALL_BREACH": return MAP_4_FIREWALL_BREACH
		"MAP_5_KERNEL_PANIC": return MAP_5_KERNEL_PANIC
	return MAP_1_BOOTLOADER

func load_level(level_index: int) -> void:
	current_level = level_index
	active_map = get_map_for_level(level_index)

func get_level_waves(level_index: int) -> Array:
	if level_index >= 0 and level_index < LEVEL_DATA.size():
		return LEVEL_DATA[level_index].waves
	return []

func get_level_config(level_index: int) -> Dictionary:
	if level_index >= 0 and level_index < LEVEL_DATA.size():
		return LEVEL_DATA[level_index]
	return {}

func unlock_next_level() -> void:
	if levels_unlocked < LEVEL_DATA.size():
		levels_unlocked += 1
