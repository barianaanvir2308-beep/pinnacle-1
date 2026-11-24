# Protocol Zero: Scaling & Upgrades Spec

**For:** Claude Code (implementation) and the team (design review)
**Builds on:** `docs/balance_spec.md` v2 and `docs/td_research.md` v2
**Replaces:** the linear L1/L2/L3 upgrade rules in `balance_spec.md` §3 (the "Upgrades" lines under §3.1, the L2/L3 columns in §3.2–3.3, and the §2.2 Decoder level table). **Base (unupgraded) tower stats in `balance_spec.md` stay as they are.**
**Version:** v1, October 2026. All numbers are starting values for playtesting.

---

## How Claude Code should use this doc

1. Read Part A only for context. Parts B–E are the instructions.
2. Implement in the order in **Part E.1**. Keep every number in `autoloads/globals.gd` (an `UPGRADE_TREES` dictionary) so the team can tune it in one place.
3. If something here conflicts with the current code or with `balance_spec.md`, **this doc wins for upgrades**, and `balance_spec.md` wins for everything else. List any conflicts for the user before coding.
4. After each step in Part E.1, run the project headless to check for script errors and stop for review.

---

## Part A: How upgrades work in Bloons TD Battles (research)

Bloons TD Battles (BTD Battles 1) is built on Bloons TD 5 and shares most of its towers, upgrades and bloons. Battles changes how upgrades are *unlocked* and *paid for*, not how the trees are shaped.

### A.1 Structure

| Rule | BTD5 / Battles | Source |
|---|---|---|
| Paths per tower | **2**, hard-coded in Battles | Blooncyclopedia "Upgrade"; Nexus Mods Battles modder notes |
| Tiers per path | **4**, each requiring the one before it | Blooncyclopedia "Upgrade"; tower pages |
| Crosspathing | Experienced players build "4-2", meaning one path to tier 4 and the other to tier 2 (e.g. a "4-2 Ninja"). The other path is capped, so you have to choose. | HubPages Battles defense guide |
| Unlocking tiers (Battles) | Tiers 1–2 come with the tower. **Tier 3 costs 5–25 Medallions** and **tier 4 costs 30–60 Medallions** (Medallions are meta-currency earned by playing matches). BTD5 instead unlocks tier 4 by rank/XP. | HubPages guide; Blooncyclopedia "Upgrade" |
| Abilities | Many tier-4 upgrades add an **activated ability** with a cooldown | Tower pages (below) |
| Battle-wide boosts | "Battle Energy" doubles attack speed for all your towers (limit 10 uses, 15 s apart) | HubPages guide |

### A.2 How towers change design and behaviour as they upgrade

There's a clear pattern across every tower:

| Tier | What changes | Examples (BTD5 medium prices) |
|---|---|---|
| **1** | **Small stat bump**: rate, range, pierce | Tack Shooter *Faster Shooting* $210. Dart *Long Range Darts* $90. Boomerang *Multi-Target* $250 (pierce 3 → 7). |
| **2** | **A new capability** (can hit a type it couldn't before), or a second stat bump | Sniper *Night Vision Goggles* $300 (camo). Boomerang *Sonic Boom* $100 (frozen) / *Red Hot 'Rangs* $150 (lead). Sniper *Full Metal Jacket* $350 (lead, 4 layers). |
| **3** | **Changes how it attacks**, and what it fires visibly changes | Tack *Tack Sprayer* $500 (8 → 16 tacks). Tack *Blade Shooter* $680 (fires blades). Boomerang *Glaive Ricochet* $1,500 (bounces between targets). Boomerang *Bionic Boomer* $1,600 ("replaces the arm with a bionic one", 2× throw speed). Sniper *Semi-Automatic* $3,500 (3× speed). |
| **4** | **A new identity or an activated ability**: big power spike, new look | Tack *Ring of Fire* $2,500 ("replaces tacks with a ring of flame"). Tack *Blade Maelstrom* $2,700 (ability). Boomerang *Glaive Lord* $9,000 (orbiting glaives, hits camo). Boomerang *Turbo Charge* $3,000 (ability: hypersonic speed for 10 s). Sniper *Cripple MOAB* $12,500 (immobilises bosses). Sniper *Supply Drop* $12,000 (ability: drops cash). |

Design takeaways:
- **Tiers 1–2 are numbers. Tiers 3–4 change what you see.** The look changes when the behaviour changes, so a player can read a tower's job from its sprite.
- **The two paths have different jobs.** Usually one path adds power or area (Tack: more tacks, then fire ring) and the other adds reach, utility or an ability (Tack: range, then blades and an ability). Sniper: damage path vs. speed/utility path.
- **Cheap tiers fix weaknesses.** BTD puts "can now hit camo / lead / frozen" on cheap tiers 1–2, so solving a counter isn't priced out of reach.

### A.3 What upgrades cost relative to the base tower

Upgrade price ÷ base tower price (BTD5 medium):

| Tower (base) | Path 1 T1 / T2 / T3 / T4 | Path 2 T1 / T2 / T3 / T4 | Full path vs base |
|---|---|---|---|
| Dart Monkey ($200) | 0.45 / 0.6 / 2.5 / 7.5 | 0.7 / 0.85 / 1.65 / 40 | 12× / 44× |
| Tack Shooter ($360) | 0.58 / 0.83 / 1.39 / 6.9 | 0.28 / 0.63 / 1.89 / 7.5 | 11× / 11× |
| Sniper Monkey ($350) | 1.0 / 6.3 / 11.4 / 35.7 | 1.14 / 0.86 / 10.0 / 34.3 | 55× / 47× |
| Boomerang ($400) | 0.62 / 0.7 / 3.75 / 22.5 | 0.25 / 0.38 / 4.0 / 7.5 | 29× / 13× |

So:
- **T1–T2 ≈ 0.3–1× base**: cheap enough to buy in the first few rounds.
- **T3 ≈ 1.5–11× base**: a mid-game investment.
- **T4 ≈ 7–40× base**: an endgame capstone, often the price of 10+ base towers.
- Towers with weak bases (Sniper) put a big jump at T2–T3. Strong-base towers (Tack) keep it flat until T4.
- **Difficulty pricing** (BTD5): Easy ×0.85, Hard ×1.075, Impoppable ×1.2 of Medium. Every tier uses the same multiplier.

### A.4 How it scales as the game goes on

- **Prices never change during a match. Income does.** In Battles, cash arrives every 6 s from an *income* stat. A defense-mode guide describes starting at $650, raising income from about $50–120 per 6 s early on to about $600–1,500 per 6 s by round 25 (the first MOABs). That's **10–30× income growth**, roughly the same as the 10–40× jump from T1 to T4 prices. **Tier prices are pinned to the income curve**, so each tier becomes affordable around the round where its power is needed.
- **The guide's buy/upgrade rhythm:** early rounds go into economy plus a few base towers. Around rounds 14–20 you spread out more base towers (about 4, then about 8, then about 15 Dart Monkeys). Around round 23 you start a 4-2 specialist for MOABs, and save $8,000 for an ability-tier upgrade (Super Monkey Fan Club) for round 25+.
- **Out-of-match unlocks:** Medallions gate tiers 3–4, so new players see simple trees first.

---

## Part B: Design rules for Protocol Zero upgrades

| # | Rule | Why (from Part A) |
|---|---|---|
| B1 | **Every tower has 2 paths × 3 tiers.** Path A = power / core job. Path B = utility, reach or an ability. | BTD's 2 paths. Scaled to 3 tiers because our levels are 10 waves, not 50+ rounds. |
| B2 | **Crosspath "3-1":** you can buy Tier 1 on both paths, but Tier 2+ only on one path, which then becomes the tower's path. | BTD's 4-2, scaled down: the choice is clear and easy to read. |
| B3 | **Cost: T1 = 0.5× base, T2 = 1.0× base, T3 = 3.0× base** (rounded to 5). A full path costs 5.5× base. | Same shape as BTD's T1–T2 cheap / T3+ expensive, compressed to match our ~3.5× in-level income growth (balance_spec §5.2). |
| B4 | **Tier roles:** T1 = stat bump. T2 = **new capability** (hit Stealth, chain, bonus vs. bosses, slow…). T3 = **new attack or an ability** and a new silhouette. | A.2 pattern |
| B5 | **Offensive value per Energy rises slightly by tier:** about 0.15 at base, ≥0.16 at T1–T2, about 0.16–0.18 at T3 on path A. Path B can be lower when it adds utility or an ability. | Upgrades should beat building another tower a little (balance_spec rule 3). |
| B6 | **Abilities:** at most one per tower, always on T3 Path B (or A for EMP/Booster). Cooldown 40–60 s. They don't cost Energy, but some add **System Load** (ties into Emergency Overclock). | BTD T4 abilities; Battle Energy's attack-speed boost |
| B7 | **Tier 3 unlocks one level after the tower is introduced** (see Part D). | Battles' Medallion gating |
| B8 | **Sell = 60% of all Energy paid.** Upgrades can be bought at any time except while the tower is locked. | balance_spec §2.1; the framework's "adapt defenses" |
| B9 | **Tower HP multiplier by tier:** base 1.0, T1 1.15, T2 1.35, T3 1.7 (on the best tier owned). | Modules are targets, so bigger investments need to survive. |

---

## Part C: Upgrade trees

Notation: costs in Energy, cumulative spend in brackets. "DPS/E" = single-target DPS ÷ cumulative spend (multi-target effects counted as written).

### C.1 Antivirus Cannon (base 100 · 15 dmg / 1.0 s · range 3.5)

| Tier | Path A: **Heuristics** (precision) | Path B: **Scan Rate** (speed/area) |
|---|---|---|
| T1 · 50 [150] | *Signature Update*: damage 15 → **24** (DPS 24, 0.16) | *Multithreaded*: interval 1.0 → **0.7 s** (DPS 21, 0.14) |
| T2 · 100 [250] | *Deep Scan*: damage **28**, shots **pierce 2 viruses**, and **can target Stealth within 1.5 tiles** (≈42 DPS-equiv, 0.17) | *Wide Scan*: range **+1.0**, **30% splash** in 0.75 tiles (≈36 equiv, 0.15) |
| T3 · 300 [550] | *Heuristic Engine*: **3-shot burst** of 28 every 1.0 s, pierce 2 (≈100 equiv, 0.18) | *Full System Scan*: interval **0.35 s**, splash **50%** (≈84 equiv, 0.15). The swarm answer. |

### C.2 Data Spike (base 225 · 80 dmg / 2.5 s · range 4.5 · armour-pierce)

| Tier | Path A: **Payload** (single target) | Path B: **Spike Array** (multi / ability) |
|---|---|---|
| T1 · 115 [340] | *Larger Payload*: damage **120** (48 DPS, 0.14) | *Fast Compile*: interval **1.7 s** (47 DPS, 0.14) |
| T2 · 225 [565] | *Kernel Exploit*: damage **160**, **+50% vs Boss and unsplit Trojans** (64 / 96 DPS, 0.11 / 0.17) | *Chain Spike*: each spike jumps to a 2nd target for 50% damage, range **+0.5** (≈71 equiv, 0.13) |
| T3 · 675 [1240] | *Zero-Day*: damage **500**. Every 3rd hit **stuns** the target 1.0 s (bosses slowed 50% for 1 s instead). (200 DPS, 0.16) | *Spike Storm*: fires **3 spikes** at the 3 strongest targets. **Ability "Purge"** (cd 45 s): 150 damage to every virus in range. (≈141 equiv + ability) |

### C.3 EMP Tower (base 175 · stun 1.0 s every 4.0 s · radius 2.5 · 4 dmg)

| Tier | Path A: **Pulse Control** | Path B: **Disruptor** |
|---|---|---|
| T1 · 90 [265] | *Capacitor*: pulse every **3.3 s** | *Wide Pulse*: radius **3.0** |
| T2 · 175 [440] | *Overload*: stun **1.5 s**. Stunned viruses take **+15% damage**. | *Scrambler*: after the stun, **30% slow for 2 s**. Each pulse **reveals Stealth** in its radius for 1 s. |
| T3 · 525 [965] | *System Freeze*, **ability** (cd 50 s): freezes **every virus on the map for 3 s**, then 50% slow for 6 s (bosses: slow only). Passive as T2. | *Ion Storm*: pulses deal **25 damage**, and **bosses are stunned 0.5 s** (normally immune). |

### C.4 Firewall (base 150 · gate · HP 300)

| Tier | Path A: **Hardened** | Path B: **Active Rules** |
|---|---|---|
| T1 · 75 [225] | *Reinforced*: HP **500** | *Throttle*: viruses next to the gate slowed **20%** |
| T2 · 150 [375] | *Self-Repair*: HP **650**, regenerates **10 HP/s** | *Burn Rule*: viruses next to the gate take **8 DPS** |
| T3 · 450 [825] | *Fortress Gate*: HP **1200**. A virus that hits the gate is **pushed back 1 tile** (once per virus every 5 s). | *Dynamic Routing*: the player can **flip which direction the gate closes** during a wave (8 s cooldown). It still can never close the last route. |

### C.5 Quarantine Tower (base 200 · traps FIRST virus in 3.0 tiles for 2.5 s every 6 s · boss immune)

| Tier | Path A: **Containment** | Path B: **Rapid Response** |
|---|---|---|
| T1 · 100 [300] | *Longer Hold*: trap **3.0 s** | *Quick Seal*: cooldown **4.5 s** |
| T2 · 200 [500] | *Isolation Cell*: trapped virus takes **+30% damage**, and a Trojan's split timer **resets to 0** | *Long-Range Lock*: range **4.5**, and it can trap revealed Stealth |
| T3 · 600 [1100] | *Sandbox*: traps **3 viruses** at once. A virus that dies while trapped gives **2× Energy**. | *Mass Quarantine*, **ability** (cd 45 s): traps every non-boss virus within 3 tiles for 2 s (bosses slowed 50%) |

### C.6 Decoy Tower (base 100 · HP 400 · taunt 3.0)

| Tier | Path A: **Honeypot** | Path B: **Hardened Decoy** |
|---|---|---|
| T1 · 50 [150] | *Bigger Bait*: taunt radius **3.75** | *Padding*: HP **650** |
| T2 · 100 [250] | *Sticky Data*: viruses that attacked it are **slowed 20% for 3 s** after leaving | *Recompile*: rebuilds itself **8 s after being destroyed** at 50% HP (once per wave) |
| T3 · 300 [550] | *Tarpit*: each virus that reaches it is **trapped 2 s** (once per virus), and Worms that hit it **can't spread** | *Mirror Node*: HP **1100**, **reflects 25%** of damage taken back to the attacker |

### C.7 Scanner (base 150 · radius 3.5 · reveals Stealth · halves Ransomware locks)

| Tier | Path A: **Detection** | Path B: **Decryption** |
|---|---|---|
| T1 · 75 [225] | *Wider Sweep*: radius **4.5** | *Fast Decrypt*: locks in radius last **35%** of normal (instead of 50%) |
| T2 · 150 [375] | *Threat Intel*: towers in radius deal **+15% damage to Spyware and Stealth**, and **Spyware auras are switched off** inside the radius | *Lock Breaker*: the player can click a locked module in radius to **unlock it instantly** (20 s cooldown) |
| T3 · 450 [825] | *Global Scan*: reveals Stealth **on the whole map**. The next-wave preview shows **spawn points and exact counts**. | *Immune System*: modules in radius **can't be locked**, and Ransomware in radius is **slowed 30%** |

### C.8 Signal Booster (base 200 · radius 2.0 · +15% range & attack speed)

| Tier | Path A: **Amplifier** | Path B: **Network** |
|---|---|---|
| T1 · 100 [300] | *Gain*: **+20% / +20%** | *Wider Mesh*: radius **2.75** |
| T2 · 200 [500] | *Damage Amp*: also **+15% damage** | *Shared Targeting*: towers in radius can hit **any Stealth virus that one of them can see**, plus **+10% range** |
| T3 · 600 [1100] | *Overdrive*, **ability** (cd 40 s): towers in radius attack **2× as fast for 6 s**. Each use adds **+10 System Load**. | *Discount Node*: towers placed or upgraded in radius **cost 10% less**, and towers in radius get **+25% HP** (BTD Monkey Village base effect) |

### C.9 Energy Decoder (base 150 · +1.5 E/s · HP 150)

| Tier | Path A: **Throughput** | Path B: **Reserve** |
|---|---|---|
| T1 · 75 [225] | *Overclocked Core*: **+2.0 E/s** (payback 112 s) | *Capacitor Bank*: Energy cap **+150** |
| T2 · 150 [375] | *Parallel Cores*: **+3.0 E/s** (payback 125 s) | *Kill Harvest*: viruses killed within 3.0 tiles give **+25% Energy** (Defense Grid Command model) |
| T3 · 450 [825] | *Quantum Decoder*: **+6.0 E/s** (payback 137 s) | *Burst Transfer*, **ability** (cd 60 s): **+200 Energy** instantly, **no System Load** |

Payback gets slightly longer with each Path A tier (112 → 125 → 137 s), so a Decoder-only strategy pays off less the more you put in. Path B is for players who want burst Energy instead.

---

## Part D: Scaling with game progression

### D.1 Tier unlocks by level (Medallion analog)

| Level | T1–T2 available for | T3 available for |
|---|---|---|
| L1 Bootloader | Cannon, Data Spike, EMP, Energy Decoder | — (the tooltip says "Tier 3 unlocks in Level 2") |
| L2 Dual Bus | + Decoy, Quarantine, Signal Booster | Cannon, Data Spike, EMP, Energy Decoder |
| L3 Spiral Core | + Scanner | + Decoy, Quarantine, Signal Booster |
| L4 Firewall Breach | + Firewall | + Scanner |
| L5 Kernel Panic | all | all (+ Firewall) |

### D.2 Prices vs. income

Using the income model in `balance_spec.md` §5.2 (Energy gained per wave grows from ~120 to ~450 within a level):

| Purchase | Cost range | ≈ Waves of income | When players should be able to afford it |
|---|---|---|---|
| T1 | 50–115 | ~0.5 early wave | Waves 1–3 |
| T2 | 100–225 | ~1 early-mid wave | Waves 3–6 |
| T3 | 300–675 | ~1–2 late waves | Waves 6–10 (from L2 on) |

- **No price inflation during a level.** Like BTD, prices stay fixed and rising income makes upgrades affordable.
- **Optional difficulty modes:** multiply every tower and upgrade price by **Easy ×0.85 / Normal ×1.0 / Hard ×1.075 / Expert ×1.2** (BTD5's ratios).
- **Energy cap check:** the most expensive single purchase is 675 (Data Spike T3), under the 1000 cap ✓.

---

## Part E: Implementation (Claude Code)

### E.1 Order of work (stop for review after each step)

1. **Data:** add `UPGRADE_TREES` to `globals.gd` (format in E.2). Keep base stats in `TOWER_DATA`. Remove the old `upgrade_*_multiplier` keys and `max_level`.
2. **Tower logic:** in `base_tower.gd`, replace `level` with `path_tiers: Dictionary = {"A": 0, "B": 0}` plus `chosen_path: String = ""` (set when a T2 is bought). Add:
   - `can_upgrade(path) -> bool`: checks the crosspath rule B2, the tier unlock (Part D), max tier 3, not locked, and affordability.
   - `get_upgrade_cost(path) -> int`: next tier's cost, with the Booster discount if applicable.
   - `upgrade(path)`: spends Energy, increments the tier, and calls `_apply_tier(path, tier)`.
   - `_apply_tier(path, tier)`: **recomputes stats from base + the tier's absolute values**. Never multiply repeatedly.
   - `get_total_spent()` and `get_sell_value()` (60%).
   - Subclasses override `_apply_tier` for behaviour flags (pierce, splash, chain, etc.).
3. **UI:** in `tower_panel.gd`, show two upgrade buttons (Path A / Path B), each with the name, cost, a one-line effect and its state (available / too expensive / locked by path / locked until Level N). Hotkey `U` upgrades the chosen path (or opens the choice if none is chosen yet). Replace the level dots over the tower with **path pips**: up to 3 pips in the path colour, plus 1 small pip for the other path's T1.
4. **Abilities:** add an `AbilityManager` (or extend `main.gd`) with a bottom-bar button for each owned ability, showing its cooldown ring. Hotkeys 1–5 in placement order. Abilities fire signals that the towers handle. Overdrive adds System Load through the Overclock system from balance_spec §2.3.
5. **Sprites:** extend `tools/gen_unit_sprites.gd` (rules in E.3), regenerate, and update `_load_art()` to pick the sprite for the current path and tier.
6. **Per-tower behaviours:** implement Part C tower by tower, offensive towers first (Cannon, Spike, EMP), then control, then support and economy. Towers that don't exist yet in code (Firewall gate, Decoy, Scanner, Booster, Decoder) come from `balance_spec.md` Phase 4. Add their trees when the towers are built.
7. **Tests:** see E.4.

### E.2 Data format (`globals.gd`)

```gdscript
const TIER_COST_MULT: Array = [0.5, 1.0, 3.0]           # T1, T2, T3 × base cost
const TIER_HP_MULT: Array = [1.0, 1.15, 1.35, 1.7]      # by highest tier owned (0..3)
const CROSSPATH_SECONDARY_MAX: int = 1                  # other path capped at T1
const SELL_REFUND_PERCENTAGE: float = 0.6
# tower_type -> level index (0-based) where its T3 unlocks
const T3_UNLOCK_LEVEL: Dictionary = {
	TowerType.ANTIVIRUS_CANNON: 1, TowerType.DATA_SPIKE: 1, TowerType.EMP_TOWER: 1, TowerType.ENERGY_DECODER: 1,
	TowerType.DECOY_TOWER: 2, TowerType.QUARANTINE_TOWER: 2, TowerType.SIGNAL_BOOSTER: 2,
	TowerType.SCANNER: 3, TowerType.FIREWALL: 4,
}

# Each tier lists ABSOLUTE stat values (not multipliers) plus behaviour flags.
const UPGRADE_TREES: Dictionary = {
	TowerType.ANTIVIRUS_CANNON: {
		"A": {"name": "Heuristics", "tiers": [
			{"name": "Signature Update", "cost": 50,  "damage": 24.0},
			{"name": "Deep Scan",        "cost": 100, "damage": 28.0, "pierce": 2, "stealth_detect_range": 1.5},
			{"name": "Heuristic Engine", "cost": 300, "damage": 28.0, "pierce": 2, "burst_count": 3, "stealth_detect_range": 1.5},
		]},
		"B": {"name": "Scan Rate", "tiers": [
			{"name": "Multithreaded",    "cost": 50,  "attack_interval": 0.7},
			{"name": "Wide Scan",        "cost": 100, "attack_interval": 0.7, "range": 4.5, "splash_factor": 0.3, "splash_radius": 0.75},
			{"name": "Full System Scan", "cost": 300, "attack_interval": 0.35, "range": 4.5, "splash_factor": 0.5, "splash_radius": 0.75},
		]},
	},
	# ... one entry per tower, copying every value from Part C ...
	# ability tiers add: "ability": {"id": "purge", "cooldown": 45.0, ...params}
}
```

Rules for `_apply_tier`:
- Start from `TOWER_DATA` base values. Apply the **chosen path's** current tier dictionary. If the *other* path has T1, apply that tier's keys **only where the chosen path's tier doesn't set the same key**.
- Example: Cannon A2 + B1 → damage 28, pierce 2, interval 0.7. That's allowed: a 2-1 build.

### E.3 Visual design rules (sprites are 28×28, drawn by `tools/gen_unit_sprites.gd`)

| Tier | What changes in the sprite | Readable at a glance as… |
|---|---|---|
| Base | Current art | "Tower type" |
| T1 | **Accent detail only:** a 2–3 px stripe or highlight on the turret in the **path colour** | "Upgraded a little" |
| T2 | **Part swap:** new barrel, antenna or emitter shape (e.g. Cannon A2 longer barrel; B2 wider muzzle; EMP B2 extra coil) | "Has a new ability" |
| T3 | **New turret silhouette** and a **base pad ring** in the path colour, plus a 2-frame idle glow (like the worm strip) | "Fully specialised" |

- **Path colours:** Path A = the tower's accent colour with `WHITE_HOT` tips. Path B = a shared secondary colour for "utility" (suggest `Color(0.55, 0.35, 1.0)`) so B-path towers read as one family.
- File names: `towers/<name>_turret_a1.png … _a3.png`, `_b1 … _b3`, and `<name>_base_t3a.png` / `_t3b.png`. The base pad stays the same below T3.
- Projectiles: A3/B3 towers that change what they fire get their own sprite (`projectiles/<name>_a3.png`), e.g. Spike Storm's triple spikes, or Full System Scan's small fast pellets.
- Extend `--preview` so the contact sheet shows every tower's base, A1–A3 and B1–B3 in one row for review.

### E.4 Acceptance checklist

- [ ] Buying A2 disables B2/B3, and the reverse. B1 stays buyable after A2 if B1 wasn't bought.
- [ ] T3 buttons show "Unlocks in Level N" on levels before their unlock.
- [ ] Stats come from absolute values: upgrading then selling then rebuilding gives identical numbers.
- [ ] Sell refund = 60% of base + every tier bought, with the Booster discount applied to what was actually paid.
- [ ] Tower HP updates on upgrade (Part B9) and keeps the same *percentage* of HP.
- [ ] Locked towers (Ransomware) can't be upgraded until they unlock.
- [ ] Each ability button appears when its T3 is bought, disappears when that tower is sold, and shows its cooldown. Overdrive raises System Load.
- [ ] The headless run has no errors, and the sprite contact sheet regenerates with every tier.
- [ ] Log per wave (balance_spec §6.2): upgrades bought by tower, path and tier, plus ability uses.

---

## Sources

- [Blooncyclopedia: Upgrade](https://www.bloonswiki.com/Upgrade): two paths, tier rules, Battles tier 4 via Medallions
- [Blooncyclopedia: Bloons TD Battles](https://www.bloonswiki.com/Bloons_TD_Battles): based on BTD5, income every 6 s, Medallions unlock higher tiers
- [Blooncyclopedia: Dart Monkey (BTD5)](https://www.bloonswiki.com/Dart_Monkey_(BTD5)), [Tack Shooter (BTD5)](https://www.bloonswiki.com/Tack_Shooter_(BTD5)), [Sniper Monkey (BTD5)](https://www.bloonswiki.com/Sniper_Monkey_(BTD5)), [Boomerang Thrower (BTD5)](https://www.bloonswiki.com/Boomerang_Thrower_(BTD5)), [Monkey Village (BTD5)](https://www.bloonswiki.com/Monkey_Village_(BTD5)): upgrade prices and effects
- ["Bloons TD Battles" Defense Strategy Guide (HubPages)](https://discover.hubpages.com/games-hobbies/Bloon-Battles-Tower-Defense-Strategy-Guide-Defense): $650 start, income growth, Medallion costs for tiers 3–4, 4-2 builds, round-by-round buy/upgrade rhythm, Battle Energy
- [Nexus Mods: Different Tower Upgrades (BTD Battles)](https://www.nexusmods.com/bloonstdbattles/mods/78): Battles is hard-coded to 2 upgrade paths
