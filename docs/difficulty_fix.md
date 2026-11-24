# Protocol Zero: Difficulty Fix

**For:** Claude Code (implementation) and the team (review)
**Based on:** a read-through of the current code (after balance_spec Phases 1–3 and the team's own changes) plus the balance model in `balance_spec.md` §6.1
**Status:** interim fix, to apply **before** Phase 4. It replaces the wave tables in `balance_spec.md` §5.3 **until Phase 4 (new towers and viruses) is done**. After that, go back to the §5.3 tables.
**Date:** October 2026

---

## 1. Summary

The game is too hard mainly because **the Phase 1–3 economy is running against the old wave tables**. Kill rewards dropped about 75%, but the waves still use the old HP and speed multipliers, which were tuned for the old, much richer economy. On top of that, four mechanics hit harder than intended because their counters (Decoy, Scanner, Energy Decoder) arrive in Phase 4, which hasn't been built yet.

Model pressure (1.0 = an average defence that spent everything is just enough; the target curve is 0.45 → 1.00):

| Level | Now: highest wave pressure | After this fix |
|---|---|---|
| L1 Bootloader | **1.17** (wave 10), and wave 1 already at **0.99** | 0.45 → 0.96 |
| L2 Dual Bus | **1.65** | 0.45 → 0.99 |
| L3 Spiral Core | **1.38** (very uneven: 0.27–1.38) | 0.46 → ~1.0 |
| L4 Firewall Breach | **3.13** | 0.45 → 1.00 |
| L5 Kernel Panic | **7.72** | 0.45 → 1.03 |

The model doesn't count towers lost to Worms and Ransomware (causes 3–4 below), so the game *feels* even harder than these numbers.

---

## 2. Why it's too hard (ranked by impact)

### Cause 1: New economy, old waves

`LEVEL_DATA` still has the original wave tables (`health_multiplier` up to 1.75 on L1 and 3.0 on L5, `speed_multiplier` up to 1.25–1.4, spawn intervals down to 0.08 s). The economy is now the v2 one:

| Energy over a whole level | Old game | Now |
|---|---|---|
| L1 kill rewards | ≈ 3,970 | ≈ 850 |
| L1 wave bonuses | 905 | 700 |
| L1 passive | 0 | ≈ 750 |
| **L1 total (incl. start)** | **≈ 5,200** | **≈ 2,550** |

The same waves are being fought with **about half the Energy**. The v2 economy only works with the v2 waves (Phase 6), which haven't been put in yet.

### Cause 2: No Energy Decoder yet

The v2 economy expects about 15–19% of income to come from the Energy Decoder (Phase 4). Without it, players fall further behind every wave.

### Cause 3: Worms delete towers (and bite twice)

`worm.gd` → `_attack_modules()`: a Worm hits **every** module within 1.05 tiles for 25, once per module. Towers next to the path are exactly 1 tile away, so **every Worm bites every tower it passes**. The first bite also spreads a clone at the same spot, and the clone starts with an empty `_hit_modules` list, so **it bites the same tower again straight away**.

Example: one L1 wave-8 group (8 Worms) does about 50 damage per Worm to the first tower on its lane (400 total), then about 25 per Worm to each tower after that. An Antivirus Cannon has 100 HP, so most of the early defence is destroyed, with no refund. The Decoy (the counter) doesn't exist yet.

### Cause 4: Ransomware locks with no counter

Each Ransomware locks every valuable module it reaches, one after another, for 5 s, and deals 10 damage each time. It picks the most valuable module first, which is usually your upgraded tower. Old L2 waves have 3–8 Ransomware per wave, and the Scanner (the counter, which halves lock time) is a Phase 4 tower.

### Cause 5: The Bootloader map fix made L1 harder

Rows 3 and 5 are now solid path. That fixed the routing, but **buildable tiles dropped from 35 to 21**, and a 3.5-tile tower now sees **4.9 path tiles instead of 6.8 (−27%)**. Spawns cycle through all 6 entrances, so the tutorial attacks from 6 lanes at once.

### Cause 6: Lower start, faster enemies

L1 starting Energy went 300 → 250. Old waves keep `speed_multiplier` above 1.0, and a 1.25× Worm in a Spyware aura moves at 2.55 tiles/s. The v2 rules keep speed at 1.0 in L1–L3.

### Cause 7: Spyware counts were meant for the old Spyware

The old L3–L5 waves include 3–6 Spyware per wave, back when Spyware was just an invisible scout. Now every Spyware gives nearby viruses +20% speed and −20% damage taken. With 4–6 in a wave, nearly every virus is buffed, which works out to roughly +40% effective HP for the whole wave.

### Cause 8: Weak towers unlocked on L2–L5

Sniper Node (24 DPS for 350, 0.07 DPS/Energy) and Quarantine Zone (8 AoE damage every 5 s for 400) are still in `get_unlocked_towers()`. They are about half as cost-effective as a Cannon (or worse), so players who try new towers get punished. Phase 4 replaces them.

---

## 3. Fixes (do them in this order)

| # | Change | Where | Expected effect |
|---|---|---|---|
| **F1** | **Replace `LEVEL_DATA`** with the interim tables in §4. No speed multipliers in L1–L3, Worms capped at 10 per wave, Spyware ≤ 3–4, and DDoS groups spawn at 0.20 s. Stealth and Boss (not built yet) are replaced with Basic / Trojan / Rootkit. | `globals.gd` | Fixes causes 1, 6 and 7. Puts every level on the target curve. |
| **F2** | **Passive income 2.0 → 3.0 E/s** *until the Energy Decoder exists*. When Phase 4 adds the Decoder, set it back to 2.0. Leave a `# TODO(difficulty_fix F2)` comment. | `globals.gd PASSIVE_ENERGY_RATE` | Makes up for cause 2. The §4 tables already assume 3.0. |
| **F3** | **Worm fixes:** (a) a clone **inherits its parent's `_hit_modules`**, so it can't bite the same tower again; (b) an original Worm bites **at most 2 modules** and a clone **at most 1**; (c) `module_damage` **25 → 15**. Add `"max_bites": 2, "clone_max_bites": 1` to `ENEMY_DATA.WORM`. | `worm.gd`, `main.gd _on_worm_spread()`, `globals.gd` | A Cannon survives about 6 bites instead of 2. Worms still threaten towers but can't wipe a lane. |
| **F4** | **Ransomware fixes (until the Scanner exists):** `lock_time` **5 → 3 s**, and each Ransomware locks **at most 2 modules** (`"max_locks": 2`). Leave a `# TODO(difficulty_fix F4)` comment: when the Scanner exists, restore 5 s and remove the cap. | `ransomware.gd`, `globals.gd` | Locks become a nuisance, not a shutdown. |
| **F5** | **Level 1 uses only the 2 left spawns** `(0,3)` and `(0,5)`. Add an optional `"spawns"` array to a level, and have `game_board.get_spawn_points()` return it when it's present (all SPAWN cells otherwise). | `globals.gd`, `game_board.gd` | 2 lanes instead of 6 for the tutorial. The row-4 tiles cover both lanes. |
| **F6** | **L1 starting Energy 250 → 300.** | `globals.gd` (in §4), `tools/checks/check_economy.gd START_ENERGY` | 3 Cannons at wave 1 |
| **F7** | **Hide the weak towers until Phase 4:** remove Sniper Node, Quarantine Zone and Overclock Hub from `get_unlocked_towers()`. Keep Firewall Beam (120 DPS for 500 is fine) on L4+. Don't delete the code. | `globals.gd get_unlocked_towers()` | No more traps in the build menu |
| **F8** | **Build countdown 10 s → 15 s** between waves (the early-start key still works). | `main.gd` (both `build_countdown = 10.0` lines) | More time to repair, upgrade and react, which matters now that towers can be damaged and locked |

Not changed: tower stats, upgrade trees, bounties, wave bonus formula (15 + 10 × wave), Energy cap, Overclock, sell and repair rates.

---

## 4. Interim `LEVEL_DATA` (paste over the existing constant)

Produced by the balance model with the current map coverage (Bootloader with 2 spawns: 5.4 tiles; Spiral Core: 15.3), passive 3.0 E/s, no Decoder, and the 15 s build gap. Groups spawn in the order listed. Each `"interval"` on a DDoS group needs the per-group interval support that `wave_manager.gd` already has. **The wave bonus comes from `Globals.wave_bonus()`, so there's no `wave_bonus` key.**

```gdscript
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
			{"wave_id":3, "enemies":[{"type":EnemyType.BASIC_VIRUS,"count":8},{"type":EnemyType.WORM,"count":4}], "spawn_interval":1.10, "health_multiplier":1.16, "speed_multiplier":1.00, "description":"ALERT: Worm detected"},
			{"wave_id":4, "enemies":[{"type":EnemyType.BASIC_VIRUS,"count":10},{"type":EnemyType.WORM,"count":6}], "spawn_interval":1.00, "health_multiplier":1.24, "speed_multiplier":1.00, "description":"CRITICAL: Mixed threat incoming"},
			{"wave_id":5, "enemies":[{"type":EnemyType.TROJAN_HORSE,"count":2},{"type":EnemyType.BASIC_VIRUS,"count":10}], "spawn_interval":1.00, "health_multiplier":1.32, "speed_multiplier":1.00, "description":"DANGER: Trojan Horse detected"},
			{"wave_id":6, "enemies":[{"type":EnemyType.WORM,"count":10},{"type":EnemyType.BASIC_VIRUS,"count":10}], "spawn_interval":0.55, "health_multiplier":1.40, "speed_multiplier":1.00, "description":"SEVERE: Complex attack pattern"},
			{"wave_id":7, "enemies":[{"type":EnemyType.BASIC_VIRUS,"count":14},{"type":EnemyType.WORM,"count":8},{"type":EnemyType.TROJAN_HORSE,"count":3}], "spawn_interval":0.65, "health_multiplier":1.48, "speed_multiplier":1.00, "description":"EMERGENCY: Mass infiltration"},
			{"wave_id":8, "enemies":[{"type":EnemyType.BASIC_VIRUS,"count":15},{"type":EnemyType.WORM,"count":10},{"type":EnemyType.TROJAN_HORSE,"count":3}], "spawn_interval":0.60, "health_multiplier":1.56, "speed_multiplier":1.00, "description":"CRITICAL: System overload"},
			{"wave_id":9, "enemies":[{"type":EnemyType.BASIC_VIRUS,"count":19},{"type":EnemyType.WORM,"count":10},{"type":EnemyType.TROJAN_HORSE,"count":5}], "spawn_interval":0.50, "health_multiplier":1.64, "speed_multiplier":1.00, "description":"BREACH: Firewall failing"},
			{"wave_id":10, "enemies":[{"type":EnemyType.BASIC_VIRUS,"count":24},{"type":EnemyType.WORM,"count":10},{"type":EnemyType.TROJAN_HORSE,"count":7}], "spawn_interval":0.45, "health_multiplier":1.72, "speed_multiplier":1.00, "description":"FINAL: All viruses converging"},
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
			{"wave_id":2, "enemies":[{"type":EnemyType.BASIC_VIRUS,"count":6},{"type":EnemyType.WORM,"count":6}], "spawn_interval":1.70, "health_multiplier":1.19, "speed_multiplier":1.00, "description":"WARNING: Mixed signals on both buses"},
			{"wave_id":3, "enemies":[{"type":EnemyType.RANSOMWARE,"count":2},{"type":EnemyType.BASIC_VIRUS,"count":10}], "spawn_interval":1.75, "health_multiplier":1.28, "speed_multiplier":1.00, "description":"ALERT: RANSOMWARE DETECTED — towers at risk!"},
			{"wave_id":4, "enemies":[{"type":EnemyType.TROJAN_HORSE,"count":2},{"type":EnemyType.WORM,"count":10},{"type":EnemyType.BASIC_VIRUS,"count":6}], "spawn_interval":1.50, "health_multiplier":1.36, "speed_multiplier":1.00, "description":"DANGER: Multi-vector attack"},
			{"wave_id":5, "enemies":[{"type":EnemyType.RANSOMWARE,"count":4},{"type":EnemyType.BASIC_VIRUS,"count":12},{"type":EnemyType.TROJAN_HORSE,"count":2},{"type":EnemyType.SPYWARE,"count":1}], "spawn_interval":1.45, "health_multiplier":1.45, "speed_multiplier":1.00, "description":"CRITICAL: Ransomware swarm"},
			{"wave_id":6, "enemies":[{"type":EnemyType.WORM,"count":10},{"type":EnemyType.TROJAN_HORSE,"count":4},{"type":EnemyType.BASIC_VIRUS,"count":3}], "spawn_interval":1.15, "health_multiplier":1.54, "speed_multiplier":1.00, "description":"SEVERE: Bus overload imminent"},
			{"wave_id":7, "enemies":[{"type":EnemyType.BASIC_VIRUS,"count":16},{"type":EnemyType.RANSOMWARE,"count":5},{"type":EnemyType.WORM,"count":10},{"type":EnemyType.SPYWARE,"count":2}], "spawn_interval":0.70, "health_multiplier":1.63, "speed_multiplier":1.00, "description":"EMERGENCY: Encryption spreading"},
			{"wave_id":8, "enemies":[{"type":EnemyType.TROJAN_HORSE,"count":5},{"type":EnemyType.RANSOMWARE,"count":5},{"type":EnemyType.BASIC_VIRUS,"count":14}], "spawn_interval":1.00, "health_multiplier":1.72, "speed_multiplier":1.00, "description":"BREACH: Dual bus compromised"},
			{"wave_id":9, "enemies":[{"type":EnemyType.RANSOMWARE,"count":6},{"type":EnemyType.TROJAN_HORSE,"count":6},{"type":EnemyType.WORM,"count":10},{"type":EnemyType.SPYWARE,"count":2},{"type":EnemyType.BASIC_VIRUS,"count":3}], "spawn_interval":0.80, "health_multiplier":1.80, "speed_multiplier":1.00, "description":"MELTDOWN: All defenses targeted"},
			{"wave_id":10, "enemies":[{"type":EnemyType.TROJAN_HORSE,"count":3},{"type":EnemyType.BASIC_VIRUS,"count":14},{"type":EnemyType.RANSOMWARE,"count":5},{"type":EnemyType.WORM,"count":10}], "spawn_interval":0.40, "health_multiplier":1.89, "speed_multiplier":1.00, "description":"FINAL: Total bus lockdown"},
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
			{"wave_id":5, "enemies":[{"type":EnemyType.BASIC_VIRUS,"count":5},{"type":EnemyType.TROJAN_HORSE,"count":4},{"type":EnemyType.WORM,"count":10},{"type":EnemyType.SPYWARE,"count":2}], "spawn_interval":0.70, "health_multiplier":1.58, "speed_multiplier":1.00, "description":"CRITICAL: Escorted assault in progress"},
			{"wave_id":6, "enemies":[{"type":EnemyType.DDOS_BOT,"count":45,"interval":0.2},{"type":EnemyType.BASIC_VIRUS,"count":5}], "spawn_interval":0.30, "health_multiplier":2.20, "speed_multiplier":1.00, "description":"SWARM: Packet flood on the spiral"},
			{"wave_id":7, "enemies":[{"type":EnemyType.RANSOMWARE,"count":5},{"type":EnemyType.TROJAN_HORSE,"count":5},{"type":EnemyType.BASIC_VIRUS,"count":17},{"type":EnemyType.SPYWARE,"count":2}], "spawn_interval":0.65, "health_multiplier":1.78, "speed_multiplier":1.00, "description":"EMERGENCY: Core defenses under siege"},
			{"wave_id":8, "enemies":[{"type":EnemyType.DDOS_BOT,"count":50,"interval":0.2},{"type":EnemyType.RANSOMWARE,"count":6},{"type":EnemyType.WORM,"count":10}], "spawn_interval":0.30, "health_multiplier":2.20, "speed_multiplier":1.00, "description":"MELTDOWN: Spiral overwhelmed"},
			{"wave_id":9, "enemies":[{"type":EnemyType.BASIC_VIRUS,"count":21},{"type":EnemyType.TROJAN_HORSE,"count":6},{"type":EnemyType.RANSOMWARE,"count":6},{"type":EnemyType.SPYWARE,"count":3}], "spawn_interval":0.35, "health_multiplier":1.97, "speed_multiplier":1.00, "description":"BREACH: All spiral layers penetrated"},
			{"wave_id":10, "enemies":[{"type":EnemyType.TROJAN_HORSE,"count":3},{"type":EnemyType.DDOS_BOT,"count":40,"interval":0.2},{"type":EnemyType.BASIC_VIRUS,"count":6},{"type":EnemyType.RANSOMWARE,"count":5},{"type":EnemyType.SPYWARE,"count":2}], "spawn_interval":0.30, "health_multiplier":2.30, "speed_multiplier":1.00, "description":"FINAL: Core meltdown imminent"},
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
			{"wave_id":5, "enemies":[{"type":EnemyType.TROJAN_HORSE,"count":4},{"type":EnemyType.ROOTKIT,"count":2},{"type":EnemyType.DDOS_BOT,"count":30,"interval":0.2},{"type":EnemyType.SPYWARE,"count":2}], "spawn_interval":2.00, "health_multiplier":1.00, "speed_multiplier":1.00, "description":"CRITICAL: Heavy units with DDoS screen"},
			{"wave_id":6, "enemies":[{"type":EnemyType.BASIC_VIRUS,"count":6},{"type":EnemyType.RANSOMWARE,"count":6},{"type":EnemyType.ROOTKIT,"count":2}], "spawn_interval":1.90, "health_multiplier":1.61, "speed_multiplier":1.00, "description":"SEVERE: Disable + armour combo"},
			{"wave_id":7, "enemies":[{"type":EnemyType.ROOTKIT,"count":3},{"type":EnemyType.TROJAN_HORSE,"count":5},{"type":EnemyType.BASIC_VIRUS,"count":14},{"type":EnemyType.SPYWARE,"count":3}], "spawn_interval":1.45, "health_multiplier":1.70, "speed_multiplier":1.00, "description":"EMERGENCY: Tank column approaching"},
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
			{"wave_id":1, "enemies":[{"type":EnemyType.BASIC_VIRUS,"count":12},{"type":EnemyType.WORM,"count":8},{"type":EnemyType.DDOS_BOT,"count":20,"interval":0.2}], "spawn_interval":2.00, "health_multiplier":1.20, "speed_multiplier":1.05, "description":"KERNEL PANIC: All ports under attack"},
			{"wave_id":2, "enemies":[{"type":EnemyType.RANSOMWARE,"count":4},{"type":EnemyType.BASIC_VIRUS,"count":12},{"type":EnemyType.TROJAN_HORSE,"count":3},{"type":EnemyType.SPYWARE,"count":2}], "spawn_interval":2.00, "health_multiplier":0.90, "speed_multiplier":1.05, "description":"CRITICAL: Heavy assault from all sides"},
			{"wave_id":3, "enemies":[{"type":EnemyType.DDOS_BOT,"count":45,"interval":0.2},{"type":EnemyType.BASIC_VIRUS,"count":6}], "spawn_interval":0.80, "health_multiplier":1.39, "speed_multiplier":1.05, "description":"SWARM: Flood from every direction"},
			{"wave_id":4, "enemies":[{"type":EnemyType.TROJAN_HORSE,"count":6},{"type":EnemyType.RANSOMWARE,"count":5},{"type":EnemyType.ROOTKIT,"count":1}], "spawn_interval":2.00, "health_multiplier":0.85, "speed_multiplier":1.05, "description":"DANGER: Elite virus squad deployed"},
			{"wave_id":5, "enemies":[{"type":EnemyType.TROJAN_HORSE,"count":3},{"type":EnemyType.BASIC_VIRUS,"count":10},{"type":EnemyType.WORM,"count":8},{"type":EnemyType.SPYWARE,"count":2}], "spawn_interval":0.85, "health_multiplier":1.58, "speed_multiplier":1.05, "description":"FLOOD: System resources exhausted"},
			{"wave_id":6, "enemies":[{"type":EnemyType.ROOTKIT,"count":2},{"type":EnemyType.RANSOMWARE,"count":6},{"type":EnemyType.TROJAN_HORSE,"count":6},{"type":EnemyType.BASIC_VIRUS,"count":6}], "spawn_interval":2.00, "health_multiplier":1.60, "speed_multiplier":1.05, "description":"SEVERE: Coordinated multi-vector assault"},
			{"wave_id":7, "enemies":[{"type":EnemyType.DDOS_BOT,"count":55,"interval":0.2},{"type":EnemyType.ROOTKIT,"count":2},{"type":EnemyType.RANSOMWARE,"count":6},{"type":EnemyType.WORM,"count":10},{"type":EnemyType.SPYWARE,"count":3},{"type":EnemyType.BASIC_VIRUS,"count":2}], "spawn_interval":0.80, "health_multiplier":1.78, "speed_multiplier":1.05, "description":"MELTDOWN: Kernel integrity failing"},
			{"wave_id":8, "enemies":[{"type":EnemyType.ROOTKIT,"count":4},{"type":EnemyType.TROJAN_HORSE,"count":7},{"type":EnemyType.BASIC_VIRUS,"count":7},{"type":EnemyType.RANSOMWARE,"count":7},{"type":EnemyType.SPYWARE,"count":3}], "spawn_interval":1.65, "health_multiplier":1.87, "speed_multiplier":1.10, "description":"CRITICAL: Elite forces converging"},
			{"wave_id":9, "enemies":[{"type":EnemyType.DDOS_BOT,"count":60,"interval":0.2},{"type":EnemyType.BASIC_VIRUS,"count":18},{"type":EnemyType.WORM,"count":10},{"type":EnemyType.ROOTKIT,"count":3},{"type":EnemyType.RANSOMWARE,"count":5}], "spawn_interval":0.35, "health_multiplier":1.97, "speed_multiplier":1.10, "description":"APOCALYPSE: Total system failure imminent"},
			{"wave_id":10, "enemies":[{"type":EnemyType.ROOTKIT,"count":4},{"type":EnemyType.TROJAN_HORSE,"count":6},{"type":EnemyType.RANSOMWARE,"count":6},{"type":EnemyType.BASIC_VIRUS,"count":7},{"type":EnemyType.DDOS_BOT,"count":50,"interval":0.2},{"type":EnemyType.WORM,"count":10},{"type":EnemyType.SPYWARE,"count":4}], "spawn_interval":0.55, "health_multiplier":2.06, "speed_multiplier":1.10, "description":"FINAL: KERNEL PANIC — SURVIVE OR DIE"},
		]
	},
]
```

---

## 5. How to check it worked

### 5.1 Add an autoplay balance check

Create `tools/checks/check_balance.gd` and `.tscn`, following the style of the other checks. For each level it should:

1. Load the level with `Engine.time_scale = 4`.
2. Act as a simple "reference player". In every build phase:
   - Repair any damaged tower, if affordable.
   - Then buy Antivirus Cannons on the free buildable tile that covers the most path tiles within 3.5 tiles.
   - When fewer than 3 good tiles are left, buy Path A upgrades (and a Data Spike on any level with Trojans or Rootkits, once Energy ≥ 400).
   - Never use Overclock.
3. Play all 10 waves and log, per wave: Energy at start, Energy spent, towers lost, lock-seconds, leaks, and Arduino HP after the wave.
4. Print one summary line per level: `PASS` if the bot clears it. L1 and L2 should finish with ≥ 50 HP, and L5 may finish with < 30 HP or fail at wave 9 or later.

### 5.2 Targets for the reference bot

| Level | Bot result | Arduino HP left |
|---|---|---|
| L1 | Clears | ≥ 70 |
| L2 | Clears | ≥ 50 |
| L3 | Clears | ≥ 40 |
| L4 | Clears | ≥ 20 |
| L5 | Clears, or fails at wave 9–10 | — |

If a level misses its target, adjust **only that level's spawn intervals** (±0.1 s on the failing waves) and re-run. Don't touch tower stats.

### 5.3 Update existing checks

- `check_economy.gd`: `START_ENERGY` becomes `[300, 350, 400, 500, 600]`, and the passive rate becomes 3.0.
- `check_viruses.gd` (or wherever Worms and Ransomware are tested): add the F3 and F4 rules (no double bite, bite and lock caps).

---

## 6. When Phase 4 lands

1. Put the `balance_spec.md` §5.3 wave tables back in (they include Stealth and Boss, which will exist by then).
2. Set passive back to 2.0 (F2), and restore Ransomware to 5 s locks with no cap (F4).
3. Keep F3 (the Worm clone fix is a bug fix, and the bite caps keep Worms readable), F5, F6, F7 (Phase 4 removes those towers anyway) and F8.
4. Re-run `check_balance`.
