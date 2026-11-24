# Tower Defense Balancing Research (v2)

**Games:** Bloons TD Battles (with Bloons TD 5, whose towers Battles 1 uses), Plants vs. Zombies (PvZ1), Defense Grid: The Awakening
**Purpose:** Pull out balancing rules from these games that fit **Protocol Zero as described in the team's Pinnacle 1 framework document**. The raw numbers are in `docs/tower_stats.csv`, and the proposed values are in `docs/balance_spec.md`.
**Version:** v2, September 2026. This version replaces v1 and is aligned to the framework PDF (Storyline, Rules, Virus types, Tower types, Energy Economy, Game Loop).

> Note on data quality: the PvZ and Defense Grid numbers come from community wikis and FAQs that people got by reading the games' data files. The Bloons prices are BTD5 "Medium" values. BTD Battles 1 uses the BTD5 tower set, but its exact prices have changed between patches. Treat all of these as reference points, not exact figures.

---

## 0. The game we're balancing

### 0.1 Framework pillars (from the Pinnacle 1 document)

| Pillar | What the framework says | What it means for balance |
|---|---|---|
| **Modules matter, not only the Arduino** | Ransomware and Worms go after modules. "The player must balance protecting the Arduino with protecting important towers." The game loop includes "Repair or restore damaged modules." | Towers have HP and can be locked, so they are part of the defensive puzzle. Enemy "threat" means damage to the Arduino **and** to modules. |
| **Towers combine into systems** | "Combining modules can create stronger defensive systems." There are three families: Offensive, Defensive/Control and Support. | Control and support towers must be worth building even though they deal little or no damage. A single "best DPS tower" is the failure case to avoid. |
| **Energy is processing power** | "Instead of every virus simply dropping coins, energy is generated and recovered through the system." There is passive generation, a Power Module / Energy Decoder, kill energy, an **Energy Capacity** limit, and **Emergency Overclock**. | Most income should come from the system rather than kills. Hoarding is limited by the cap. Overclock is a risky burst of Energy you choose to trigger. |
| **Every virus needs a different answer** | "Each virus type should require a different defensive approach." | Each virus has one counter tower that is clearly best against it (mapped in §8). |
| **Viruses choose routes** *(red: unsure)* | "Viruses do not have one fixed path and can choose routes toward their objectives." "Each virus chooses a route based on its behaviour and objective." | Different viruses head for different targets: Basic → Arduino, Worm/Ransomware → modules. Firewall and Decoy steer them. |
| **Towers cannot block the path in v1** *(red: unsure)* | — | The Firewall may close **one direction**, but at least one route to the Arduino must always stay open. |
| **The player steps in during waves** | "The player can intervene by changing priorities, activating abilities, or adapting defenses." | Target-priority switching and the Emergency Overclock ability are core features, not extras. |
| **Input** | Keyboard and mouse, drag and drop onto a grid. Indicators prompt the player to react. | UI speed isn't a limit, so spawn spacing can be tight. On-screen warnings should come before Ransomware locks and Trojan splits. |

### 0.2 What changed from v1 of this research

| v1 recommendation | Why it conflicts with the framework | v2 revision |
|---|---|---|
| Passive income = 0; the wave bonus replaces it | The framework requires passive generation and an Energy Decoder | Passive 2 Energy/s from the system, the **Energy Decoder** tower as the investment choice, and a smaller wave bonus |
| Kill bounties as the main income | "Instead of every virus simply dropping coins…" | Kills are about 30–40% of income. System income (passive + Decoders) is about 40–50%. |
| Optional interest on banked Energy | The framework caps Energy, and interest rewards hoarding, which fights the cap | **Removed.** An Energy Capacity cap (1000) is added instead. |
| Overclock Hub as a 1000-Energy damage tower | The framework's "Overclock" is an **emergency ability** with a System Load risk | The tower is replaced by the **Emergency Overclock** ability (Energy now, tower slowdowns later) |
| EMP as a 15-DPS tower with a slow | "Temporarily disables viruses in an area. Mainly used for crowd control rather than damage." | EMP **stuns** everything in an area on a cooldown and does very little damage |
| Quarantine Zone as the AoE swarm-damage tower | "Temporarily traps a virus inside a designated area" | Quarantine **traps** one virus at a time. Swarm damage moves to a small EMP pulse plus Antivirus splash (only needed if DDoS stays). |
| Firewall Beam as a ramping laser | The framework's Firewall "controls or blocks movement in a specific direction" | **Firewall is a directional gate** that closes one branch of a junction |
| Spyware is invisible | The framework's Spyware "follows other viruses and provides them with support". Invisibility belongs to the **Stealth Virus**. | Spyware becomes an **aura escort** that buffs nearby viruses. Invisibility moves to the Stealth Virus, which the Scanner reveals. |
| Trojan splits on death | The framework says it splits "after surviving for a certain amount of time" | **Timed split:** kill it before 8 s and it never splits. Data Spike becomes the burst answer. |
| Balance assumes one fixed path per spawn | Viruses choose routes by objective | Route rules per virus type (§7). The model still uses the shortest route as the worst case. |
| Sell refund 70%, plus 100% refund in the same phase | "Selling a tower returns only a fixed percentage of its original cost" | One fixed percentage, **60% of what was paid**, with no special cases |
| No Decoy, Scanner, Signal Booster, Energy Decoder or Boss | These are in the framework | Added, each with a researched precedent (§6) |

---

## 1. Tower cost vs. damage

### What the three games do

| Game | Tower | Cost | DPS | DPS per unit of currency |
|---|---|---|---|---|
| PvZ | Peashooter | 100 sun | 20 dmg / 1.425 s = **14.0** | **0.140** |
| PvZ | Repeater | 200 sun | 40 / 1.425 s = 28.1 | 0.140 |
| PvZ | Snow Pea | 175 sun | 20 / 1.5 s = 13.3 | 0.076 (+50% slow) |
| PvZ | Garlic | 50 sun | 0 | Diverts zombies to another lane. 400 toughness. |
| PvZ | Ice-shroom | 75 sun | 20 once | Freezes all zombies for 3.25 s, then slows them 50% for 16 s |
| Defense Grid | Gun L1 → L2 → L3 | 100 → 300 → 700 total | 10 → 30 → 70 | **0.10 at every level** |
| Defense Grid | Temporal | 300 | 0 | Slows ~50% in an area |
| Defense Grid | Command | 300 | 0 | +25/35/45% resources from kills in range. Reveals stealth. |
| BTD5 | Monkey Village | $1,600 | 0 | Support: −10% cost in radius. Upgrades: +15% range (Beacon), +15% attack speed (Jungle Drums), camo detection (Radar Scanner) |

### Rules we can reuse

1. **Offensive towers share one exchange rate.** PvZ's Repeater is exactly 2× the Peashooter in cost and damage. Defense Grid's Gun keeps 0.10 DPS per resource at every level. For our offensive towers (Antivirus Cannon and Data Spike), hold **0.15 DPS per Energy ±10%**.
2. **Control and support towers are priced by what they do, not by DPS.** All three games sell towers that deal zero damage (Garlic, Temporal, Command, Monkey Village). A good rule: a support tower should cost about **as much as the extra damage it creates**. A 200-Energy Signal Booster giving +15% attack speed and +15% range adds roughly 32% delivered damage (1.15 × 1.15). At 0.15 DPS per Energy, 200 Energy buys 30 DPS, so the Booster breaks even once it covers about **94 DPS** of towers (≈6 Cannons, or 2 upgraded Data Spikes). BTD's Village is only a good buy when it's surrounded by towers, and that's intentional. It's the "combining modules creates stronger systems" pillar in number form.
3. **Crowd control is valued by the extra time it buys.** A stun that holds enemies 25% of the time makes every tower in the area deal about 1.33× damage to them (1 ÷ 0.75). Ice-shroom's 3.25 s freeze plus 16 s of 50% slow is the most extreme version, and PvZ balances it with a very slow recharge. **Cooldown is the price of control.**
4. **Range is a hidden damage multiplier.** Damage delivered = DPS × time in range, and range is what sets time in range.

---

## 2. Upgrade paths

| Game | Structure | Cost pattern | Power pattern |
|---|---|---|---|
| Defense Grid | 3 levels, linear | Each step costs double (Gun 100/200/400). Support towers (Temporal, Command) cost a **flat** 300/300/300. | Damage ×1/×3/×7, so value per resource is flat. Support levels grow the effect's size (+25/35/45%). |
| BTD5 / Battles | 2 paths × 4 tiers | Dart Monkey 90/120/500/1500 and 140/170/330/8000 | Tiers 1–2 are small bumps. Tiers 3–4 change what the tower does. |
| PvZ | "Upgrade plants" placed on top of a base plant | Extra cost + the base plant | Saves lane space |

### Rules we can reuse

1. **Offensive upgrades: doubling cost with a small efficiency bonus.** L2 costs 1× base and L3 costs 2× base, for DPS ×2.1 and ×4.4. The bonus pays for the framework's risk that Ransomware locks the tile you invested in.
2. **Support and control upgrades: flat cost, better effect** (the Defense Grid Temporal/Command model). Stun length, trap time, aura size and Decoder output go up in steps, so these towers never become DPS in disguise.
3. **Tower HP grows with level.** Since modules are targets in our game, a high-level tower needs more HP, or all that investment becomes an easy prize for Worms and Ransomware.

---

## 3. Enemies: HP, roles and scaling

### Enemy HP ratios (heaviest vs. basic)

| Game | Basic | Mid | Heavy | Boss/tank | Heaviest ÷ basic |
|---|---|---|---|---|---|
| PvZ | Zombie 200 | Conehead 640 (3.2×) | Buckethead 1370 (6.9×) | Gargantuar 3000 (15×) | 15× |
| Defense Grid | Walker 100 | Rhino 200 (2×) | Turtle 1000 (10×) | Crasher 4000 (40×) | 40× |
| BTD5 (Red Bloon Equivalents) | Red 1 | Ceramic 104 | MOAB 616 | ZOMG 16,656 | ~27× per class step |

### Enemies that attack defences instead of the base

This is the framework's central idea (Ransomware, Worm, "protect important towers"):

| Precedent | Behaviour | Counter the game provides |
|---|---|---|
| PvZ zombies | Eat any plant in their way before reaching the house | Wall-nut (4000 toughness), a cheap blocker |
| PvZ **Bungee Zombie** | Marks a plant with a target arrow about 1 s ahead, then steals it. 450 HP. | Umbrella Leaf protects nearby plants. Ice-shroom freezes it while it hovers. |
| PvZ **Gargantuar** | Smashes plants. At half health (1500 damage taken), throws an Imp deeper into the lawn. | Burst damage before the threshold |
| Defense Grid aliens | Head for the **power cores**, carry them off, and have to bring them back out | Kill them on the return trip. Cores drift home when the carrier dies. |

**Rules for Protocol Zero:**

* **Telegraph attacks on modules.** Bungee's target arrow is the model: Ransomware should visibly mark the module it's heading for, which fits the framework's on-screen "indicators".
* **Give every module-attacker a counter tower.** Worms → Decoy (Garlic model). Ransomware → Scanner "decryption" (shorter locks) plus Decoy.
* **Locks should be temporary and recoverable,** like a Defense Grid core drifting home, never "tower destroyed forever". Repair costs Energy.

### Timed and threshold splits (the framework's Trojan)

* Gargantuar releases its Imp at **half HP**. Bloons pop into children when damaged. Defense Grid's Seeker and Turtle spawn smaller aliens.
* The framework asks for a **time-based** split ("after surviving for a certain amount of time"). That's a *DPS check with a timer*: burst towers (Data Spike) are how you stop it. Show a countdown ring so the player can see the deadline.

### Support enemies (the framework's Spyware)

None of the three games has a true "escort that buffs its allies". Bloons' closest equivalents are properties (camo, regrow) that are built into a bloon rather than given by another one. Designing from first principles:

* **The aura must be small and not stack,** otherwise a group of escorts is much harder than the numbers suggest.
* **The escort must be the obvious kill-first target,** which gives meaning to the framework's "change priorities" intervention. Give it no Arduino damage and a high bounty so killing it first always pays off.

### Bosses

* PvZ's Gargantuar is 15× a basic zombie and Defense Grid's Crasher is 40× a basic alien. For our game, **about 25× a Basic Virus** is the middle ground.
* Bosses in all three games shrug off some control effects. For example, PvZ's Gargantuar ignores Garlic because it doesn't eat plants. Make our Boss **immune to Quarantine traps and only slowed (not stunned) by EMP**, so control helps but can't lock it down.

### How difficulty ramps

* Bloons: fixed stats per bloon type. Difficulty comes from composition and **spacing** (BTD Battles sells "spaced", "grouped" and "tight" sends).
* PvZ: fixed zombie stats, a growing wave budget, and big "flag waves".
* Defense Grid: fixed base HP per alien, with harder types and more of them over time.
* **Rules:** fixed speed per type, a gentle HP multiplier (+8% per wave), and spawn interval as the main knob. Use a **sawtooth** curve with big waves where the Boss appears.

---

## 4. Economy and income

| Game | Guaranteed / system income | Investment income | Kill income | Hoarding control |
|---|---|---|---|---|
| PvZ | Sky sun, 25 per drop (day levels) | **Sunflower**: 50 sun, +25 at ~7 s then every 24 s (pays back after ~31 s) | None | Zombies eat Sunflowers, so the investment is exposed |
| BTD Battles | **Eco** paid every 6 s | Sending bloons raises eco | Pop cash | Strong sends lower eco (Battles 1) |
| Defense Grid | — | Command tower +25–45% | Per-kill resources, about 0.2 per HP (less for tanks) | Interest is paid **only while cores are at home**, so it's lost under pressure |

### Rules for Protocol Zero

1. **Split income roughly 45% system / 35% kills / 20% wave bonus.** This matches "energy is generated and recovered through the system" while still rewarding kills.
2. **The Energy Decoder is our Sunflower.** Cheap, it pays back within 2–3 waves, and it is an **attractive target** (the framework: "Power Modules are attractive targets for viruses"). Worms and Ransomware target it first, the way zombies chew Sunflowers. This one rule creates the "protect the economy" layer.
3. **The Energy cap replaces interest.** Defense Grid rewards banking resources. The framework does the opposite by capping them. A cap of 1000 (enough for any single purchase) makes players spend instead of hoarding and makes Overclock's burst of Energy more meaningful.
4. **Emergency Overclock follows Defense Grid's orbital laser** (a supplemental weapon that costs no resources but has a recharge) and BTD's ability cooldowns. Here the cost is **System Load**: using it gives Energy now and slows your towers later. Used once, it's a clutch save. Used back to back, it crashes the system. That's the framework's "towers could temporarily become less efficient/pause or the Core could become vulnerable".
5. **Bounty per HP drops for tanks and rises for nuisance/support enemies,** following Defense Grid's resources-per-kill pattern.

---

## 5. Difficulty pacing

* **Wave 1 is easy enough to win without thinking,** and each level teaches **one new idea**. Scanner and Stealth arrive together, and Decoy arrives with the first module-attacker.
* **Harder levels change the mix and spacing first, and raw HP last.** Map shape (route length) matters as much as HP.
* **Boss waves are set pieces** at the end of levels 2–5 (plus a smaller boss at L5 wave 5). The framework says bosses appear "during major waves or at the end of certain levels".

---

## 6. Framework mechanics and their closest precedents

| Framework element | Closest precedent | Design takeaway |
|---|---|---|
| Energy Decoder / Power Module | PvZ Sunflower; BTD Monkey Town (+50% pop cash); DG Command | Short payback (~100 s), and viruses target it |
| Emergency Overclock + System Load | DG orbital laser (recharge, gives no resources); BTD ability cooldowns | Big instant Energy, paid for with a slowly decaying load that slows towers |
| Energy Capacity | (the opposite of DG interest) | A cap slightly above the most expensive single purchase |
| EMP Tower (area disable) | PvZ Ice-shroom; DG Temporal | Stun on a cooldown, very little damage |
| Quarantine Tower (trap) | Ice-shroom freeze, but on one target | Traps the lead virus. Boss immune. |
| Firewall (directional block) | DG route-shaping (aliens always take the shortest open route); PvZ Wall-nut / Tall-nut | Closes one branch of a junction. Can never close the last route. |
| Decoy Tower | **PvZ Garlic** (50 sun, 400 toughness, diverts biters) | Cheap, low HP, redirects module-seekers. Some viruses ignore it (as Gargantuar ignores Garlic). |
| Scanner *(red)* | BTD Radar Scanner; DG Command (reveals stealth) | Reveals Stealth, previews the next wave, speeds up Ransomware unlocks |
| Signal Booster | BTD Monkey Beacon (+15% range) / Jungle Drums (+15% attack speed) | +15% range and attack speed nearby. Doesn't stack. |
| Worm (seeks modules, spreads) | PvZ zombies eating plants; Bungee stealing plants | Fast, low HP. Spreads once after hitting a module. |
| Ransomware (locks a module) | PvZ Bungee Zombie (telegraphed plant theft) | Marks its target, locks it for a while, and the lock can be shortened |
| Trojan (timed split) | PvZ Gargantuar Imp throw at half HP | Split timer with a visible countdown |
| Stealth Virus *(red)* | BTD camo bloons; DG Lurker | Only visible in Scanner range, or when very close to any tower |
| Boss Virus | Gargantuar (15×), Crasher (40×) | About 25× a Basic. Immune to trap, slowed by EMP. |

---

## 7. Protocol Zero map analysis (from `globals.gd`)

Damage delivered = DPS × time in range. A shortest-path search over each map gives:

| Map | Spawns | Shortest route (tiles) | Path seen by a 3.5-tile tower (best spots) | Alternate routes? |
|---|---|---|---|---|
| 1 Bootloader | 6 | 10–19 | 6.8 | Yes (upper/lower loops) |
| 2 Dual Bus | 4 | 11–12 | 4.1 | Yes (two buses) |
| 3 Spiral Core | 3 | 21–45 | 12.2 | Few (single spiral) |
| 4 Firewall Breach | 8 | 6–11 | 3.6 | Yes (many junctions) |
| 5 Kernel Panic | 6 | **4–9** | 3.1 | Yes (two main lanes) |

* **Route choice (framework rule, currently marked unsure):** Basic Virus, Trojan and Boss take the shortest open route to the Arduino. Worms and Ransomware route to their target module. Spyware follows the nearest virus. Firewalls and Decoys change these routes. The balance model uses the **shortest** route, which is the hardest case.
* Firewall Breach and Kernel Panic have lots of junctions, so they suit the Firewall tower. Spiral Core has few, so Firewall should unlock after it or be weak there.
* **Map data bug (still present):** on Bootloader none of the 6 spawns connect to the Arduino through PATH cells, and on Spiral Core 2 of 3 don't. `main.gd` then sends enemies in a straight line. Route choice can't work until the maps connect.

---

## 8. Counter map: every virus needs a different answer

| Virus | Primary counter | Secondary | Wrong answer (on purpose) |
|---|---|---|---|
| Basic Virus | Antivirus Cannon | anything | — |
| Worm | Decoy | EMP stun (catches fast movers) | Data Spike (too slow to hit them) |
| Trojan Horse | Data Spike (kill before the split) | Quarantine (freezes the split timer) | Many Cannons spread thin |
| Ransomware | Scanner (halves lock time) + Decoy | Quarantine | Stacking all towers in one spot |
| Spyware | Target priority "SUPPORT" / focus fire | Data Spike | Ignoring it |
| Stealth Virus | Scanner | Towers placed right beside the path | Long-range towers without a Scanner |
| Boss Virus | Data Spike + Signal Booster | EMP slow, Overclock timing | Quarantine (immune) |
| *DDoS Bot (code only)* | EMP pulse | Antivirus splash | Data Spike |
| *Rootkit (code only)* | Data Spike (armour-piercing) | — | Cannon |

### Items in the current code that aren't in the framework

| In code | In the framework? | Recommendation |
|---|---|---|
| Sniper Node | No | Cut, or merge into Data Spike (range 5.0). It overlaps Data Spike's role. |
| Firewall Beam (laser) | No. The framework's Firewall is a gate. | Rename/replace with the Firewall gate |
| Overclock Hub (tower) | No. Overclock is an ability. | Replace with the Emergency Overclock ability |
| Quarantine Zone (AoE damage) | Role differs | Change to a trap |
| Spyware = invisible | Role differs | Move invisibility to the Stealth Virus. Spyware becomes an escort. |
| Rootkit | No | Team decision. It works as an "armoured" variant that gives Data Spike a second job. Kept in the tables as optional. |
| DDoS Bot | No | Team decision. It needs some AoE damage (EMP pulse). Kept as optional. |

---

## Sources

* [Plants vs. Zombies Wiki (wiki.gg): Peashooter](https://plantsvszombies.wiki.gg/wiki/Peashooter_(PvZ)), [Sunflower](https://plantsvszombies.wiki.gg/wiki/Sunflower_(PvZ)), [Snow Pea](https://plantsvszombies.wiki.gg/wiki/Snow_Pea_(PvZ)), [Wall-nut](https://plantsvszombies.wiki.gg/wiki/Wall-nut_(PvZ)), [Garlic](https://plantsvszombies.wiki.gg/wiki/Garlic_(PvZ)), [Ice-shroom](https://plantsvszombies.wiki.gg/wiki/Ice-shroom_(PvZ)), [Gargantuar](https://plantsvszombies.wiki.gg/wiki/Gargantuar_(PvZ)), [Bungee Zombie](https://plantsvszombies.wiki.gg/wiki/Bungee_Zombie)
* [StrategyWiki: Plants vs. Zombies/Zombies](https://strategywiki.org/wiki/Plants_vs._Zombies/Zombies) (zombie health)
* [GameFAQs: Defense Grid: The Awakening FAQ by Brixx79](https://gamefaqs.gamespot.com/pc/955296-defense-grid-the-awakening/faqs/57896) (tower costs, DPS ranges, alien HP and kill values)
* [Ayumilove Defense Grid guide](https://ayumilove.net/defense-grid/) (upgrade costs, Command tower bonus)
* [Aussiedroid's DG Tower Guide (Steam)](https://steamcommunity.com/sharedfiles/filedetails/?id=121597561) (Gun ×1/×3/×7)
* [Defense Grid manual (Steam)](https://cdn.akamai.steamstatic.com/steam/apps/18500/manuals/manual_english.pdf?t=1667008094) (interest, 75% sell refund, stealth reveal)
* [Wikipedia: Defense Grid: The Awakening](https://en.wikipedia.org/wiki/Defense_Grid:_The_Awakening) (cores, orbital laser, shortest-route aliens)
* [How to Defense Grid (Steam guide)](https://steamcommunity.com/sharedfiles/filedetails/?id=218777908) (interest only while cores are home)
* [Bloons Wiki: Eco (BTDB2)](https://bloons.fandom.com/wiki/Eco_(BTDB2)) (6 s payout)
* [Steam guide: How to eco (no farm)](https://steamcommunity.com/sharedfiles/filedetails/?id=3051052520) (starting eco 250)
* [Blooncyclopedia: Dart Monkey (BTD5)](https://www.bloonswiki.com/Dart_Monkey_(BTD5)), [Monkey Village (BTD5)](https://www.bloonswiki.com/Monkey_Village_(BTD5))
* [Steam guide: Bloons (BTD5 bloon table)](https://steamcommunity.com/sharedfiles/filedetails/?id=590203873) (RBE values)
* Team framework: *Pinnacle 1 Tower Defence Game* (Protocol Zero concept, rules, virus and tower types, energy economy, game loop)
