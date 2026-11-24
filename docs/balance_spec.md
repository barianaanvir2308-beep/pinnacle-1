# Protocol Zero: Balancing Spec v2

**Status:** Starting values for playtesting, not final numbers
**Aligned to:** the team framework *Pinnacle 1 Tower Defence Game* (the PDF) and `docs/td_research.md` v2
**Replaces:** v1. What changed and why is listed in `td_research.md` §0.2.
**Units:** range in tiles (1 tile = 120 px), speed in tiles per second, time in seconds, currency = Energy

Items the framework marks **red / unsure** are tagged *(unsure)*. The spec gives values for them, but they can be dropped without breaking anything else. Items in the current code that the framework doesn't mention are tagged *(optional)*.

---

## 0. Fix these before balancing

Found in the current code. Items 1–3 change combat math, and items 5–6 block route choice.

| # | Where | Problem | Fix |
|---|---|---|---|
| 1 | `base_tower.gd` `try_attack()` | `cooldown = 1.0 / fire_rate` treats `fire_rate` as shots per second. The project spec means seconds between shots. | Rename to `attack_interval` and set `cooldown_timer = attack_interval` |
| 2 | `base_tower.gd` `upgrade()` | Reads `upgrade_damage_mult`, but the data key is `upgrade_damage_multiplier`, so every tower gets ×1.5 | Use the per-level tables in §3 |
| 3 | `base_enemy.gd` | Reads `"damage"` instead of `"base_damage"`, so every leak does 1 damage | Read `base_damage` |
| 4 | `globals.gd` `MAX_ENERGY = 9999`, `PASSIVE_ENERGY_RATE = 0.0` | The framework wants an Energy Capacity and passive generation | 1000 and 2.0 (§2) |
| 5 | `MAP_1_BOOTLOADER`, `MAP_3_SPIRAL_CORE` | Spawns don't connect to the Arduino through PATH cells (Bootloader 0 of 6, Spiral 1 of 3), so enemies fly in a straight line | Fix the cells, and add a startup check |
| 6 | `game_board.gd` / `main.gd` | One A* path from spawn to Arduino for every enemy | For route choice: re-path per virus type toward its target (§4.2), and re-path when a Firewall closes a cell |
| 7 | `main.gd` spawn | `randi()` spawn choice | Cycle spawns in order so waves are deterministic |
| 8 | `wave_manager.gd` | One interval per wave | Optional per-group `interval` (DDoS groups at 0.20 s) |

---

## 1. Design rules

1. **Offensive exchange rate: 0.15 DPS per Energy (±10%).** The Antivirus Cannon is the reference.
2. **Control and support towers are priced by what they do** (stun uptime, trap time, damage boost, Energy per second), not by DPS. Each one needs a situation where it clearly beats buying another Cannon (research §1, §8).
3. **Upgrades:** offensive towers cost double each level (L2 = 1× base, L3 = 2× base) for DPS ×2.1 / ×4.4. Control, support and economy towers use flat costs with bigger effects (the Defense Grid Temporal/Command model).
4. **Modules are targets.** Tower HP, locks and repair are part of the balance. Every virus that attacks modules has a counter tower.
5. **Income: roughly 40% system, 35% kills, 20% wave bonus** (the model gives 33–48% / 28–41% / 13–21%, see §5.2). Energy is capped at 1000.
6. **Fixed speed per virus type**, HP +8% per wave, and spawn interval as the main knob. The difficulty curve is a sawtooth with Boss set pieces.
7. **Target pressure per wave:** `0.45, 0.50, 0.60, 0.55, 0.75, 0.65, 0.80, 0.75, 0.90, 1.00` (see §6).

---

## 2. Energy economy

### 2.1 Core values

| Parameter | Value | Framework basis |
|---|---|---|
| Starting Energy | L1 **250**, L2 **350**, L3 **400**, L4 **500**, L5 **600** | "Start with a limited amount of Energy and basic defenses" |
| Passive generation | **2.0 Energy/s** during waves and the 10 s build countdown. Stops while paused. | "The computer naturally generates a small amount of energy over time" |
| Energy Capacity | **1000**. Income above the cap is lost, and the HUD bar flashes at 90%. | "Players can't keep generating energy infinitely" |
| Kill Energy | Per-virus table in §4 (lower than v1) | "Destroyed viruses release energy… different amounts" |
| Wave-end bonus | **15 + 10 × wave** (25 … 115) | "Survive the Wave → receive additional rewards" |
| Sell refund | **60% of everything paid** (build + upgrades), always | "Selling returns only a fixed percentage" |
| Repair (build phase only) | Restoring a module to full HP costs **30% × (missing HP ÷ max HP) × total paid** for that tower. Locked modules can't be repaired until the lock ends. | Game loop step 7: "Repair or restore damaged modules" |
| Interest | **None.** It would fight the Energy Capacity rule. | — |

### 2.2 Energy Decoder (Power Module)

| Level | Upgrade cost | Total paid | Output | Payback | HP |
|---|---|---|---|---|---|
| L1 | — | 150 | +1.5 E/s | 100 s (≈ 2 waves) | 150 |
| L2 | 150 | 300 | +2.5 E/s | 120 s | 200 |
| L3 | 300 | 600 | +5.0 E/s | 120 s | 260 |

* **It's an attractive target** (framework): Worms and Ransomware pick the nearest Energy Decoder first (§4.2). A locked Decoder produces nothing.
* At L3, 5 E/s plus the 2 E/s base fills the 1000 cap from empty in about 2.4 minutes, so the cap limits a greedy Decoder strategy by itself.

### 2.3 Emergency Overclock (ability, replaces the Overclock Hub tower)

| Parameter | Value |
|---|---|
| Effect | **+150 Energy instantly** (capped at 1000) |
| Cost | **+50 System Load** (load runs from 0 to 100) |
| Load decay | −1 per second during waves, −2 per second in the build phase |
| Cooldown | 15 s |
| Load ≥ 60 | All towers attack **25% slower** (attack interval ×1.25) |
| Load ≥ 90 | Towers attack **50% slower** and passive generation stops |
| Load reaches 100 | **System crash:** all towers pause for 3 s, the Arduino takes **double damage for 10 s**, and load resets to 60 |
| Unlock | L1, from wave 3 (with a tutorial prompt) |

About once per wave is safe: +50 load at use, and most of it decays over a 40–60 s wave plus the build phase. Two uses close together push you into slowdown. A third use in a row crashes the system. That's the framework's "towers could temporarily become less efficient/pause or the Core could become vulnerable". The wave tables in §5 **don't** count Overclock income. It's the player's emergency margin.

### 2.4 Expected income per level (model)

Assumes every virus is killed, one L1 Energy Decoder is built at wave 2, and Overclock is never used.


---

## 3. Towers

### 3.1 Offensive towers

| Tower | Cost | Damage | Interval (s) | DPS | Range | DPS / Energy | Targeting | Special |
|---|---|---|---|---|---|---|---|---|
| **Antivirus Cannon** | 100 | 15 | 1.0 | 15 | 3.5 | 0.150 | FIRST | *(optional, only if DDoS stays)* 25% splash within 0.5 tiles |
| **Data Spike** | 225 | 80 | 2.5 | 32 | 4.5 | 0.142 | STRONGEST | Ignores armour *(Rootkit)*. The burst answer to Trojans and Bosses. |
| **EMP Tower** | 175 | 4 to all in area | 4.0 (pulse) | ~1 per enemy | 2.5 radius | — (control) | area | **Stuns** every virus in the radius for 1.0 s. Bosses are slowed 50% instead. |

Upgrades:

* **Cannon and Data Spike:** L2 costs 1× base, L3 costs 2× base. Damage ×2.1 / ×4.4, range ×1.1 / ×1.2.
* **EMP:** flat 175 per level.
  * L2: stun 1.25 s, radius 2.75
  * L3: stun 1.5 s, radius 3.0, pulse every 3.5 s

Why these numbers:

* **Data Spike vs. Trojan.** A base Trojan (220 HP) dies to 3 Spike hits in 5.0 s, inside the 8 s split timer. By wave 7–10 (HP ×1.48–1.72, about 325–380 HP) one L1 Spike can't make it in time. You need an L2 Spike, a second Spike, or a Quarantine freeze. That's the escalating Trojan check.
* **EMP.** A 1 s stun every 4 s holds enemies 25% of the time, so every tower near it deals about 1.33× damage. For 175 Energy that's worth it once about 80 DPS of towers cover the EMP's area. It's a mid-game combo piece, as the framework intends ("crowd control rather than damage").

### 3.2 Defensive / control towers

| Tower | Cost | HP | Effect | L2 (flat cost) | L3 (flat cost) |
|---|---|---|---|---|---|
| **Firewall** | 150 | 300 | Placed on a buildable tile next to a path tile. It **closes that path tile in one chosen direction**, so viruses re-path. **It can't close the last open route** from any spawn to the Arduino (placement is refused, with feedback). *(unsure: "cannot block path in v1")* | HP 500 | HP 800, and viruses passing next to it are slowed 20% |
| **Quarantine Tower** | 200 | 200 | Every 6 s, **traps the FIRST virus within 3.0 tiles** for 2.5 s. The trapped virus can't move, but towers can still damage it. Its Trojan split timer and Ransomware lock are frozen. **Bosses are immune.** | Trap 3.0 s, cooldown 5 s | Traps the 2 leading viruses |
| **Decoy Tower** | 100 | 400 | **Taunt radius 3.0.** Worms and Ransomware whose route passes within the radius target the Decoy first. Basic viruses and Trojans within 1.5 tiles stop to attack it (10 dmg/s each) before moving on. **Bosses ignore it** (as PvZ's Gargantuar ignores Garlic). | HP 700, radius 3.5 | HP 1100, radius 4.0 |

### 3.3 Support towers

| Tower | Cost | HP | Effect | L2 (flat cost) | L3 (flat cost) |
|---|---|---|---|---|---|
| **Scanner** *(unsure)* | 150 | 150 | Radius 3.5. **Reveals Stealth viruses.** Shows a preview of the next wave. Ransomware locks inside the radius last **half as long**. Towers inside the radius get two extra target priorities: STEALTH and SUPPORT. | Radius 4.5 | Radius 5.5, and Ransomware's target marker shows 2 s earlier |
| **Signal Booster** | 200 | 200 | Towers within 2.0 tiles get **+15% range and +15% attack speed**. Doesn't stack, and doesn't boost other Boosters. | +20% / +20% | +25% / +25% |
| **Energy Decoder** | 150 | 150 | See §2.2 | §2.2 | §2.2 |

Break-even for the Signal Booster: +15%/+15% ≈ +32% delivered damage, so 200 Energy pays off once it covers about 94 DPS of towers (≈6 Cannons or 2 L2 Data Spikes).

### 3.4 Module HP, locks and targeting

* **Tower HP** = cost × (1.0 / 1.3 / 1.6) by level, unless the tables above give a value.
* **Locked** modules do nothing: no attacks, no auras, no Energy. They show a padlock and a countdown ring.
* **Target priority** can be changed during a wave (framework: "changing priorities"): FIRST, LAST, STRONGEST, CLOSEST, plus SUPPORT and STEALTH when inside Scanner range.

### 3.5 Unlocks

| Level | New towers / abilities | Teaches |
|---|---|---|
| L1 Bootloader | Antivirus Cannon, Data Spike, EMP, Energy Decoder, Emergency Overclock (wave 3) | Economy, Trojan burst |
| L2 Dual Bus | Decoy, Quarantine, Signal Booster | Module-attackers (Ransomware), combos |
| L3 Spiral Core | Scanner | Stealth |
| L4 Firewall Breach | Firewall | Route control on a map with many junctions |
| L5 Kernel Panic | — (everything) | Final exam |

### 3.6 Towers in the current code that are replaced

| Code | Becomes |
|---|---|
| Sniper Node | Cut, or merge into Data Spike (not in framework) |
| Firewall Beam | Firewall (gate) |
| Quarantine Zone (AoE damage) | Quarantine Tower (trap) |
| Overclock Hub (tower) | Emergency Overclock (ability) |

---

## 4. Viruses

### 4.1 Stats

Values at HP multiplier 1.0. "Cannon hits" = how many 15-damage shots it takes to kill one.

| Virus | HP | Speed | Arduino dmg | Energy on kill | Cannon hits | Behaviour |
|---|---|---|---|---|---|---|
| **Basic Virus** | 60 | 1.0 | 5 | 4 | 4 | Shortest route to the Arduino |
| **Worm** | 35 | 1.7 | 2 | 3 | 3 | Targets the nearest module (Energy Decoder first). On contact: 25 damage to the module, then **spreads once** (spawns 1 Worm that can't spread), then heads for the next module or the Arduino. |
| **Trojan Horse** | 220 | 0.6 | 15 | 10 | 15 | **Splits after 8.0 s alive** into 3 Minis (30 HP, speed 1.2, 3 Arduino dmg, 1 Energy each). Kill it before 8 s and it never splits. The timer is frozen while it's trapped or stunned, and a countdown ring shows. |
| **Ransomware** | 160 | 0.8 | 5 | 9 | 11 | Targets the **most valuable module in reach** (Energy Decoder or Signal Booster first) and marks it 2 s ahead. Within 1 tile it **locks** that module for 5 s (2.5 s in Scanner range) and deals 10 damage, then moves to the next target. No lock on death. |
| **Spyware** | 80 | 1.0 (matches the virus it follows) | 0 | 10 | 6 | **Follows the nearest virus.** Aura radius 1.5: other viruses get **+20% speed** and take **20% less damage**. Doesn't stack. |
| **Stealth Virus** *(unsure)* | 50 | 1.3 | 8 | 8 | 4 | Can't be targeted unless inside Scanner range or within 1.0 tile of any tower |
| **Boss Virus** | see wave tables (≈25× Basic × wave HP mult) | 0.5 | 40 | 80 | — | Immune to Quarantine. EMP slows it 50% instead of stunning. Ignores Decoy. Has one ability per level (§4.3). |
| *DDoS Bot (optional)* | 20 | 2.0 | 1 | 1 | 2 | Swarm. Group spawn interval 0.20 s. |
| *Rootkit (optional)* | 320 | 0.5 | 25 | 20 | 43 (5 Data Spike hits) | Armour 0.5, except against Data Spike |

Energy per HP is highest for Spyware (0.125) and Stealth (0.16), because killing them first should always pay. It's lowest for tanks and the Boss (0.06 or less). That follows Defense Grid's pattern of paying more for nuisance enemies and less for tanks (research §4).

### 4.2 Route choice *(unsure; framework red text)*

| Virus | Target | Route |
|---|---|---|
| Basic, Trojan, Minis, Boss, *DDoS*, *Rootkit* | Arduino | Shortest open route |
| Worm | Nearest module (Decoder first). Decoy if within taunt range. | Shortest route to that module, then onward |
| Ransomware | Most valuable module in reach (Decoder > Booster > others by cost). Decoy if within taunt range. | Shortest route to that module |
| Spyware | Nearest virus | Follows it |
| Stealth | Arduino | Shortest open route |

Re-path when a Firewall is placed or removed, or when a virus's target module is sold, destroyed or locked. If route choice is cut, everything uses the Arduino route and Worm/Ransomware only attack modules they pass within 1 tile of.

### 4.3 Boss abilities

| Appearance | Ability |
|---|---|
| L2 W10 | **Encrypt:** every 8 s, locks the nearest module for 3 s |
| L3 W10 | **Cloak:** Stealth for 3 s out of every 10 s (Scanner counters it) |
| L4 W10 | **Breach:** ignores Firewall gates |
| L5 W5 (mini-boss) | **Replicate:** spawns 2 Basic Viruses every 6 s |
| L5 W10 (×2) | One with Encrypt and one with Cloak |

---

## 5. Waves

### 5.1 Rules

* **HP multiplier:** `level_base × (1 + 0.08 × (wave − 1))`, with `level_base = 1.0 / 1.1 / 1.2 / 1.15 / 1.2`. The tables adjust individual waves where the model said the mix was too hard or too easy.
* **Boss HP** = 25 × Basic HP × the wave's HP multiplier, capped so that a single Boss needs no more than 70% of the player's expected DPS.
* **Speed multiplier:** 1.0, except L4 waves 8–10 (1.05) and L5 (1.05, then 1.10 for waves 8–10).
* **Spawn interval** is set to hit the target pressure. DDoS groups always use 0.20 s.
* **Introductions:** Worm L1 W3 · Trojan L1 W5 · Ransomware L2 W3 · Spyware L2 W5 · Boss L2 W10 · *DDoS* L3 W2 · Stealth L3 W3 · *Rootkit* L4 W4.
* Italic viruses are *optional* (they're in the code, not the framework). If you cut them, replace each with Basic Viruses of equal total HP (DDoS ×20 HP; Rootkit ×320 HP × 1.6 for armour) and re-check pressure.

### 5.2 Expected income

| Level | Start | Kills | Passive (2 E/s) | 1 Energy Decoder (from W2) | Wave bonuses | Total over level | System share |
|---|---|---|---|---|---|---|---|
| L1 Bootloader | 250 | 910 | 840 | 572 | 700 | ≈3,300 | 43% |
| L2 Dual Bus | 350 | 1140 | 900 | 615 | 700 | ≈3,700 | 41% |
| L3 Spiral Core | 400 | 1282 | 1306 | 859 | 700 | ≈4,500 | 48% |
| L4 Firewall Breach | 500 | 1572 | 939 | 628 | 700 | ≈4,300 | 36% |
| L5 Kernel Panic | 600 | 2091 | 1010 | 663 | 700 | ≈5,100 | 33% |

### 5.3 Wave tables

\* "Energy earned before wave" is cumulative income (start + kills + passive + 1 Decoder + bonuses), assuming no losses. Pressure is explained in §6.1: about 0.5 is comfortable, and 1.0 means an average-efficiency defence that spent everything is just barely enough.

#### Level 1: Bootloader (start 250 Energy)

| Wave | Viruses | Spawn interval (s) | HP mult | Speed mult | Boss HP | Wave bonus | Energy earned before wave* | Model pressure |
|---|---|---|---|---|---|---|---|---|
| 1 | Basic ×5 | 2.00 | 0.75 | 1.00 | — | 25 | 250 | 0.45 |
| 2 | Basic ×7 | 2.00 | 0.70 | 1.00 | — | 35 | 372 | 0.53 |
| 3 | Basic ×8, Worm ×4 | 1.45 | 1.16 | 1.00 | — | 45 | 583 | 0.61 |
| 4 | Basic ×10, Worm ×8 | 1.05 | 1.24 | 1.00 | — | 55 | 832 | 0.55 |
| 5 | Trojan ×2, Basic ×10 | 0.85 | 1.32 | 1.00 | — | 65 | 1117 | 0.74 |
| 6 | Worm ×14, Basic ×8 | 0.45 | 1.40 | 1.00 | — | 75 | 1380 | 0.63 |
| 7 | Basic ×14, Worm ×8, Trojan ×3 | 0.55 | 1.48 | 1.00 | — | 85 | 1663 | 0.80 |
| 8 | Basic ×14, Worm ×12, Trojan ×3 | 0.45 | 1.56 | 1.00 | — | 95 | 2010 | 0.78 |
| 9 | Basic ×18, Worm ×12, Trojan ×5 | 0.40 | 1.64 | 1.00 | — | 105 | 2376 | 0.88 |
| 10 | Basic ×22, Worm ×14, Trojan ×7 | 0.35 | 1.72 | 1.00 | — | 115 | 2795 | 0.95 |

#### Level 2: Dual Bus (start 350 Energy)

| Wave | Viruses | Spawn interval (s) | HP mult | Speed mult | Boss HP | Wave bonus | Energy earned before wave* | Model pressure |
|---|---|---|---|---|---|---|---|---|
| 1 | Basic ×8 | 2.00 | 0.80 | 1.00 | — | 25 | 350 | 0.45 |
| 2 | Basic ×6, Worm ×6 | 2.00 | 0.95 | 1.00 | — | 35 | 488 | 0.49 |
| 3 | Ransomware ×2, Basic ×10 | 2.00 | 1.28 | 1.00 | — | 45 | 734 | 0.59 |
| 4 | Trojan ×2, Worm ×10, Basic ×6 | 1.50 | 1.36 | 1.00 | — | 55 | 1006 | 0.55 |
| 5 | Ransomware ×4, Basic ×12, Trojan ×2, Spyware ×1 | 1.35 | 1.45 | 1.00 | — | 65 | 1318 | 0.75 |
| 6 | Worm ×16, Trojan ×4 | 0.90 | 1.54 | 1.00 | — | 75 | 1675 | 0.66 |
| 7 | Basic ×16, Ransomware ×5, Worm ×10, Spyware ×2 | 0.60 | 1.63 | 1.00 | — | 85 | 1993 | 0.80 |
| 8 | Trojan ×5, Ransomware ×5, Basic ×14 | 0.85 | 1.72 | 1.00 | — | 95 | 2391 | 0.75 |
| 9 | Ransomware ×6, Trojan ×6, Worm ×16, Spyware ×2 | 0.65 | 1.80 | 1.00 | — | 105 | 2801 | 0.89 |
| 10 | Boss ×1, Basic ×14, Ransomware ×5, Worm ×10 | 0.40 | 1.89 | 1.00 | 2850 | 115 | 3251 | 0.98 |

#### Level 3: Spiral Core (start 400 Energy)

| Wave | Viruses | Spawn interval (s) | HP mult | Speed mult | Boss HP | Wave bonus | Energy earned before wave* | Model pressure |
|---|---|---|---|---|---|---|---|---|
| 1 | Basic ×10, Worm ×5 | 2.00 | 1.10 | 1.00 | — | 25 | 400 | 0.45 |
| 2 | *DDoS* ×30 | 2.00 | 1.00 | 1.00 | — | 35 | 642 | 0.50 |
| 3 | Stealth ×4, Basic ×10 | 0.75 | 1.39 | 1.00 | — | 45 | 906 | 0.61 |
| 4 | *DDoS* ×35, Ransomware ×3 | 1.75 | 1.49 | 1.00 | — | 55 | 1238 | 0.55 |
| 5 | Stealth ×5, Trojan ×4, Worm ×10, Spyware ×2 | 0.80 | 1.58 | 1.00 | — | 65 | 1576 | 0.75 |
| 6 | *DDoS* ×45, Stealth ×5 | 0.30 | 2.85 | 1.00 | — | 75 | 2013 | 0.66 |
| 7 | Ransomware ×5, Trojan ×5, Stealth ×5, Basic ×12, Spyware ×2 | 0.65 | 1.78 | 1.00 | — | 85 | 2388 | 0.78 |
| 8 | *DDoS* ×50, Ransomware ×6, Worm ×10 | 0.30 | 2.80 | 1.00 | — | 95 | 2928 | 0.75 |
| 9 | Stealth ×7, Trojan ×6, Ransomware ×6, Basic ×14, Spyware ×3 | 0.35 | 1.97 | 1.00 | — | 105 | 3387 | 0.93 |
| 10 | Boss ×1, *DDoS* ×40, Stealth ×6, Ransomware ×5, Spyware ×2 | 0.30 | 2.75 | 1.00 | 3100 | 115 | 3979 | 0.91 |

#### Level 4: Firewall Breach (start 500 Energy)

| Wave | Viruses | Spawn interval (s) | HP mult | Speed mult | Boss HP | Wave bonus | Energy earned before wave* | Model pressure |
|---|---|---|---|---|---|---|---|---|
| 1 | Basic ×12, Ransomware ×3 | 2.00 | 0.75 | 1.00 | — | 25 | 500 | 0.45 |
| 2 | Basic ×10, Worm ×8, Stealth ×3 | 1.80 | 1.24 | 1.00 | — | 35 | 701 | 0.50 |
| 3 | *DDoS* ×35, Stealth ×4 | 1.35 | 1.33 | 1.00 | — | 45 | 1029 | 0.60 |
| 4 | *Rootkit* ×1, Ransomware ×3, Worm ×10 | 2.00 | 1.00 | 1.00 | — | 55 | 1256 | 0.54 |
| 5 | Trojan ×4, *Rootkit* ×2, *DDoS* ×30, Spyware ×2 | 2.00 | 1.05 | 1.00 | — | 65 | 1559 | 0.74 |
| 6 | Stealth ×6, Ransomware ×6, *Rootkit* ×2 | 1.75 | 1.61 | 1.00 | — | 75 | 1909 | 0.64 |
| 7 | *Rootkit* ×3, Trojan ×5, Basic ×14, Spyware ×3 | 1.25 | 1.70 | 1.00 | — | 85 | 2284 | 0.81 |
| 8 | *DDoS* ×40, *Rootkit* ×3, Ransomware ×6, Worm ×10 | 0.80 | 1.79 | 1.05 | — | 95 | 2754 | 0.76 |
| 9 | *Rootkit* ×4, Stealth ×7, Trojan ×6, Ransomware ×6, Spyware ×3 | 1.15 | 1.89 | 1.05 | — | 105 | 3186 | 0.89 |
| 10 | Boss ×1, *Rootkit* ×3, *DDoS* ×40, Ransomware ×6, Trojan ×4, Spyware ×3 | 0.95 | 1.98 | 1.05 | 2950 | 115 | 3757 | 1.01 |

#### Level 5: Kernel Panic (start 600 Energy)

| Wave | Viruses | Spawn interval (s) | HP mult | Speed mult | Boss HP | Wave bonus | Energy earned before wave* | Model pressure |
|---|---|---|---|---|---|---|---|---|
| 1 | Basic ×12, Worm ×8, *DDoS* ×20 | 2.00 | 1.20 | 1.05 | — | 25 | 600 | 0.45 |
| 2 | Ransomware ×4, Basic ×12, Trojan ×3, Spyware ×2 | 2.00 | 0.75 | 1.05 | — | 35 | 842 | 0.51 |
| 3 | *DDoS* ×45, Stealth ×6 | 1.00 | 1.39 | 1.05 | — | 45 | 1229 | 0.60 |
| 4 | Trojan ×6, Ransomware ×5, *Rootkit* ×1 | 2.00 | 0.85 | 1.05 | — | 55 | 1485 | 0.54 |
| 5 | Boss ×1, Basic ×10, Worm ×8, Spyware ×2 | 2.00 | 1.45 | 1.05 | 1200 | 65 | 1823 | 0.83 |
| 6 | *Rootkit* ×2, Ransomware ×6, Trojan ×6, Stealth ×6 | 1.85 | 1.68 | 1.05 | — | 75 | 2265 | 0.65 |
| 7 | *DDoS* ×55, *Rootkit* ×2, Ransomware ×6, Worm ×14, Spyware ×3 | 0.55 | 1.78 | 1.05 | — | 85 | 2746 | 0.80 |
| 8 | *Rootkit* ×4, Trojan ×7, Stealth ×7, Ransomware ×7, Spyware ×3 | 1.40 | 1.87 | 1.10 | — | 95 | 3204 | 0.75 |
| 9 | *DDoS* ×60, Basic ×16, Worm ×14, *Rootkit* ×3, Ransomware ×5 | 0.30 | 2.20 | 1.10 | — | 105 | 3812 | 0.90 |
| 10 | Boss ×2, Trojan ×6, Ransomware ×6, Stealth ×6, *DDoS* ×50, Worm ×12, Spyware ×4 | 0.45 | 2.06 | 1.10 | 2900 | 115 | 4335 | 0.99 |

---

## 6. How to verify and tune

### 6.1 The pressure model

```
exposure_time  = path_tiles_in_range / virus_speed        # shortest route, 3.5-tile tower at a top-25% spot
required_DPS   = max( total_effective_HP / (spawn_span + avg_exposure),
                      max_single_effective_HP / its_exposure )
available_DPS  = (energy_earned − 150 for the Decoder) × 0.15 × 0.80
pressure       = required_DPS / available_DPS
```

Effective HP includes: Spyware aura (×1.1 HP and speed for the others in that wave), Stealth (×1.3 for lost targeting time), half of Trojan splits (assuming half are killed in time), *Rootkit* armour (×1.6) and *DDoS* AoE (×0.6). The Boss gets ×1.5 exposure from the EMP slow. The model **ignores** stuns, traps, Decoy detours, module locks, the Booster and Overclock. It sets the *shape* of the curve, and playtesting sets the final numbers.

### 6.2 What to log in playtests

Per wave: Energy at start/end, Energy lost to the cap, Overclock uses and peak System Load, towers built/upgraded/sold/repaired, **module lock-seconds**, **module HP lost**, leaks (count and Arduino damage), Trojan splits that happened vs. were prevented, and damage dealt per tower type.

### 6.3 Targets

| Metric | Target |
|---|---|
| L1 first-try clear rate | 80%+ |
| L5 first-try clear rate | 20–35% |
| Arduino HP lost on wave 10 (players who clear) | 20–60 |
| Players who build an Energy Decoder by L1 W3 | 60%+. If lower, cut its cost to 125. If ~100%, it's mandatory: cut output to 1.25 E/s. |
| Energy lost to the cap | Under 5% of income. If higher, raise the cap to 1200. |
| System crashes from Overclock | 0–1 per level for average players |
| Share of total damage from any one tower type | No single type above 50% by L3 |
| Control/support towers per player at L3+ | At least 2. If fewer, they're too weak or too expensive. |
| Trojan splits prevented at L1 W5 | 50%+. It's the first burst check. |

### 6.4 Tuning knobs, in order

1. Spawn interval for one wave (±0.1 s)
2. Count of the defining virus (±1–2)
3. HP multiplier for that wave (±0.05)
4. Starting Energy (±50) or passive rate (±0.25 E/s) if the first three waves are wrong
5. Control/support effect sizes (stun, trap, aura %) before offensive damage
6. Offensive tower stats last

---

## 7. Ready-to-paste data (`globals.gd`)

This assumes fixes #1–#4. New tower types (`FIREWALL`, `DECOY_TOWER`, `SCANNER`, `SIGNAL_BOOSTER`, `ENERGY_DECODER`) and virus types (`STEALTH_VIRUS`, `BOSS_VIRUS`) need enum entries, scenes and scripts. Only the balance fields are shown.

```gdscript
# --- Economy ---
const STARTING_ENERGY_BY_LEVEL: Array = [250, 350, 400, 500, 600]
const PASSIVE_ENERGY_RATE: float = 2.0      # E/s, waves + build countdown
const MAX_ENERGY: int = 1000                # Energy Capacity
const SELL_REFUND_PERCENTAGE: float = 0.6   # of total paid
const REPAIR_COST_FACTOR: float = 0.3       # × missing-HP fraction × total paid
# wave_bonus = 15 + 10 * wave_id ; arduino_hp = 100 on all levels

const OVERCLOCK: Dictionary = {"energy": 150, "load": 50, "cooldown": 15.0,
	"decay_wave": 1.0, "decay_build": 2.0,
	"slow_threshold": 60, "slow_mult": 1.25, "severe_threshold": 90, "severe_mult": 1.5,
	"crash_pause": 3.0, "crash_arduino_dmg_mult": 2.0, "crash_duration": 10.0, "crash_reset_load": 60}

# --- Upgrades ---
const OFFENSE_UPGRADE_COST_MULT: Array = [0.0, 1.0, 2.0]   # × base cost to reach L2, L3
const OFFENSE_DMG_MULT: Array = [1.0, 2.1, 4.4]
const OFFENSE_RANGE_MULT: Array = [1.0, 1.1, 1.2]
const TOWER_HP_MULT: Array = [1.0, 1.3, 1.6]
# Control/support towers: each upgrade costs 1× base; effects per level are listed per tower below

# --- Towers ---
TowerType.ANTIVIRUS_CANNON: {"cost": 100, "damage": 15.0, "attack_interval": 1.0, "range": 3.5, "target_mode": TargetMode.FIRST},
TowerType.DATA_SPIKE:       {"cost": 225, "damage": 80.0, "attack_interval": 2.5, "range": 4.5, "target_mode": TargetMode.STRONGEST, "armor_pierce": true},
TowerType.EMP_TOWER:        {"cost": 175, "damage": 4.0, "attack_interval": [4.0, 4.0, 3.5], "radius": [2.5, 2.75, 3.0],
                             "stun": [1.0, 1.25, 1.5], "boss_slow_factor": 0.5},
TowerType.FIREWALL:         {"cost": 150, "hp": [300, 500, 800], "adjacent_slow_l3": 0.8},
TowerType.QUARANTINE_TOWER: {"cost": 200, "hp": 200, "range": 3.0, "trap_time": [2.5, 3.0, 3.0], "cooldown": [6.0, 5.0, 5.0], "targets": [1, 1, 2]},
TowerType.DECOY_TOWER:      {"cost": 100, "hp": [400, 700, 1100], "taunt_radius": [3.0, 3.5, 4.0], "melee_radius": 1.5},
TowerType.SCANNER:          {"cost": 150, "hp": 150, "radius": [3.5, 4.5, 5.5], "lock_time_mult": 0.5},
TowerType.SIGNAL_BOOSTER:   {"cost": 200, "hp": 200, "radius": 2.0, "range_bonus": [0.15, 0.20, 0.25], "speed_bonus": [0.15, 0.20, 0.25]},
TowerType.ENERGY_DECODER:   {"cost": 150, "hp": [150, 200, 260], "energy_per_s": [1.5, 2.5, 5.0], "upgrade_cost": [0, 150, 300]},

# --- Viruses --- (health at multiplier 1.0; reward = Energy on kill)
EnemyType.BASIC_VIRUS:   {"health": 60,  "speed": 1.0, "base_damage": 5,  "reward": 4,  "target": "arduino"},
EnemyType.WORM:          {"health": 35,  "speed": 1.7, "base_damage": 2,  "reward": 3,  "target": "module", "module_damage": 25, "spread_count": 1},
EnemyType.TROJAN_HORSE:  {"health": 220, "speed": 0.6, "base_damage": 15, "reward": 10, "target": "arduino",
                          "split_time": 8.0, "split_count": 3, "split_health": 30, "split_speed": 1.2, "split_damage": 3, "split_reward": 1},
EnemyType.RANSOMWARE:    {"health": 160, "speed": 0.8, "base_damage": 5,  "reward": 9,  "target": "valuable_module",
                          "lock_time": 5.0, "lock_damage": 10, "mark_lead_time": 2.0},
EnemyType.SPYWARE:       {"health": 80,  "speed": 1.0, "base_damage": 0,  "reward": 10, "target": "follow",
                          "aura_radius": 1.5, "aura_speed": 1.2, "aura_damage_taken": 0.8},
EnemyType.STEALTH_VIRUS: {"health": 50,  "speed": 1.3, "base_damage": 8,  "reward": 8,  "target": "arduino", "reveal_distance": 1.0},
EnemyType.BOSS_VIRUS:    {"health": 1500, "speed": 0.5, "base_damage": 40, "reward": 80, "target": "arduino",   # health overridden per wave
                          "trap_immune": true, "emp_slow_factor": 0.5, "ignores_decoy": true},
EnemyType.DDOS_BOT:      {"health": 20,  "speed": 2.0, "base_damage": 1,  "reward": 1},                         # optional
EnemyType.ROOTKIT:       {"health": 320, "speed": 0.5, "base_damage": 25, "reward": 20, "armor_factor": 0.5},  # optional
```

---

*v2, September 2026. Recalculate §5 after any change to §2–§4.*
