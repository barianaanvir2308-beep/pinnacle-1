# Protocol Zero: UI / HUD Design Handoff

**For:** Claude Code (implementation) and the team (design review)
**Look we're going for:** cyberpunk / futuristic. "You are the computer's own defence terminal."
**Builds on:** the current UI code (`scripts/main/hud.gd`, `scripts/ui/*`) and the gameplay docs in `docs/`
**Version:** v1, October 2026

Part A is the research. Part B is the rules (why a UI is good *and* fun). Part C is the cyberpunk style guide. Part D specifies each screen and component. Part E is the build order for Claude Code.

---

## Part A: What the research says

### A.1 Tower defense games

| Game | What works | What doesn't |
|---|---|---|
| **Kingdom Rush** | The build/upgrade menu opens **around the selected tower** as a ring, so "the player never wondered where an option is". Empty build spots are marked as circles on the map. Purchases need a **second tap to confirm**, and tapping elsewhere cancels. Upgrade descriptions sit beside the options. Text is plain and legible during play. | Player powers sit in a **far corner**, so you have to move the mouse across the screen mid-fight and miss enemies. The powers menu opens by accident when it's near build spots. It isn't clear when the hero is selected. Players asked for a **speed-up button**. |
| **Bloons TD 5 / 6** | The upgrade panel groups the two paths side by side and shows the current tier in place. BTD6 hides the panel by default so the map stays the focus. | Scrolling a tower list with arrow keys gets hard after about 12 towers. Players complain that BTD6's upgrade panel **covers part of the map** and that ability buttons make towers near the bottom hard to click. |
| **Defense Grid 2** | **Spatial** elements (enemy path trail, weapon range) are obvious from the first minute. Towers **show their upgrade level on the model** (diegetic). | The placement/upgrade window covers about **a quarter of the screen**, locks the cursor, and repeats the same stats as both a graph and a paragraph. |
| **Plants vs. Zombies** *(general knowledge)* | Seed packets show cost on the card and **grey out with a recharge sweep**, so state is readable without text. | — |

### A.2 Other 2D and strategy games

| Game | Lesson |
|---|---|
| **Into the Breach** | "We would **sacrifice cool ideas for the sake of clarity every time**." Mechanics that couldn't be shown clearly were cut. Every enemy **telegraphs** its next attack. Animated tooltips that *show* a weapon working are "a thousand times more effective" than text. Early builds put damage indicators everywhere, and new players couldn't tell who was doing what. |
| **Slay the Spire** | Enemy **intents** make the next turn predictable. PC Gamer credits "how transparent Slay the Spire makes information and enemy intents". Big forgiving hitboxes. Cards leave streaks when moving, so you can follow the flow. **Animations never block input.** Attack icons change at damage thresholds, so you sense danger before reading the number. |
| **Cyberpunk 2077** (a cyberpunk reference, not 2D) | **Contextual HUD:** elements appear only when relevant (health only in combat), and every area can be hidden. Fixed screen zones for each kind of information. **What goes wrong:** almost everything is the **same red**, so decoration and information look alike. Red is used for ornaments as well as errors. **Readable words and numbers in decorative graphics get mistaken for real information.** Button styles vary too much, and quest markers are overdone, causing "information overload". Chromatic aberration works when it reads as the character's optics, not as random decoration. |

### A.3 UX and accessibility frameworks

- **Celia Hodent's game usability principles** (*The Gamer's Brain*, Epic Games): signs and feedback · clarity · form follows function · consistency · minimum workload · error prevention and recovery · flexibility and accessibility. They apply to *accidental* friction, not to challenge you designed on purpose.
- **Kinds of game UI** (Fagerholt & Lorentzon's framework): **non-diegetic** (HUD bars), **spatial** (in the world but not seen by characters, e.g. range rings), **meta** (screen effects like a red flash when hurt), and **diegetic** (part of the world, e.g. towers changing look when upgraded). Good TD UIs move as much as possible into spatial and diegetic forms.
- **Xbox Accessibility Guideline 103:** "Color alone should never be used to represent information". Pair colour with a shape, icon, pattern or label, and greyed-out states need a second cue such as a lock icon.
- **Xbox Accessibility Guideline 102:** **4.5:1** contrast for important text and visuals, **3:1** for large text and inactive items, **7:1** in a high-contrast mode. Large text on PC starts at **36 px at 1080p**.
- **"Juice it or lose it"** (Jonasson & Purho, 2012): tweening, scaling and screen shake turn a dull game into a satisfying one without changing its rules.
- **A cyberpunk UI design system** (designmd.app): near-black backgrounds, **each neon colour carries one meaning that never changes**, neon covers at most **10–15%** of a surface, accent saturation is capped, glitch effects stay **subtle (0.3 s), one per view**, scanlines are optional at about 0.1 opacity, and motion only animates transform and opacity.

---

## Part B: The rules (why a UI is good and fun)

Each rule gives the evidence and what it means for Protocol Zero.

### Good: the player always knows what's happening

**R1. Clarity beats cool, every time.** *(Into the Breach)*
If an effect, ornament or animation makes something harder to read, cut it or tone it down. Cyberpunk style is applied *on top of* a clear layout, never instead of one.

**R2. Telegraph the threat before it arrives.** *(Into the Breach, Slay the Spire)*
Most of the tension and fun in strategy comes from *seeing what's coming and planning for it*. For Protocol Zero:
- Show a **wave preview** of what's coming (icons and counts per entrance) during the build countdown.
- Ransomware's **target marker**, the Trojan's **split ring** and the Worm's bite target are all attack forecasts and must be easy to read.

**R3. Put information where the eyes already are.** *(Kingdom Rush ring menu; BTD6 and Defense Grid 2 complaints)*
Information about a tower appears **next to that tower**. Global information lives at the **screen edges**. Nothing should cover the path while enemies are on it. Panels must never take a quarter of the screen.

**R4. Show, don't tell.** *(Into the Breach animated tooltips; Defense Grid diegetic upgrades)*
Prefer a **range ring preview**, a **ghost ring for the next upgrade's range**, a tower sprite that changes per tier, and enemy status icons over text.

**R5. One colour, one meaning. Decoration must never look like information.** *(Cyberpunk 2077 critique; cyberpunk design system)*
The colour roles are in §C.2, and they never change. Decoration uses its own dim colour and **abstract glyphs** (hex fragments, barcodes, circuit traces), **never readable words or numbers**.

**R6. Never rely on colour alone.** *(Xbox Accessibility Guideline 103)*
Every coloured state also has an **icon, shape or label**. "Can't afford" = red cost **plus** a dimmed card **plus** a lock or ✕ glyph. Enemy statuses use different icon shapes, not just tints.

**R7. Readable at a glance.** *(Xbox Accessibility Guideline 102)*
Important text is ≥ 4.5:1 contrast and inactive text ≥ 3:1. Minimum sizes are in §C.3. Numbers that change during play use a **monospace** font so they don't jitter.

**R8. Show only what matters right now.** *(Cyberpunk 2077 contextual HUD)*
- Enemy health bars appear only when the enemy is damaged.
- Tower health bars appear only when the tower is damaged or locked.
- The upgrade panel appears only when a tower is selected.
- Alerts fade after their time is up.

**R9. Be consistent.** *(Hodent; the Cyberpunk "five button styles" problem)*
There is one button component with a fixed set of states (§D.9), and every button in the game uses it. The same action always looks the same.

### Fun: the UI rewards the player

**R10. Every action gets instant feedback that never blocks.** *(Juice it or lose it; Slay the Spire)*
Placing, upgrading, selling, killing and leaking each get a small animation and a sound within **0.1 s**. UI animations are 120–250 ms. Nothing makes the player wait to give the next input.

**R11. Build tension, then pay it off.** *(Telegraphing plus juice)*
- The wave preview and countdown build anticipation.
- A clean wave earns a **"WAVE CLEARED"** banner, an Energy count-up and a short chime.
- Losing Arduino HP is loud: screen-edge flash and HUD shake. A leak should feel bad, but should never hide the board.

**R12. Prevent mistakes and make them easy to undo.** *(Hodent; Kingdom Rush second-tap confirm)*
- Selling an upgraded tower asks for a second click (the button turns into "CONFIRM SELL").
- Right-click / Esc always cancels placement.
- Placement previews show green (valid) or red with ✕ (invalid) **before** the click.

**R13. Keep effort low.** *(Hodent; Kingdom Rush power-placement and speed-up critiques)*
- Every frequent action has a hotkey shown on its button.
- Abilities and Overclock sit in **one cluster**, all reachable by key.
- Add a **2× speed toggle** and an **early wave start** (the early-start key already exists, so give it a button).

**R14. Let the player tune it.** *(Hodent's flexibility; Xbox guidelines)*
Settings to turn **screen shake, scanlines, glitch and chromatic aberration** off, plus a UI scale option (100 / 125%).

---

## Part C: Cyberpunk style guide

### C.1 Mood
"A terminal inside the machine." Dark **glass panels** float over the circuit board. Their thin **neon edges** carry meaning, and data readouts flicker to life. The map already has a near-black base, cyan circuit paths, red spawns and an amber Arduino, so the UI should continue that language, not compete with it.

### C.2 Colour roles

These were checked against the backgrounds below with WCAG contrast maths. The "Deuteranopia" column is an approximate simulation of how someone with the most common colour-vision deficiency sees each colour (Machado 2009).

| Token | Hex | Meaning (never reused for anything else) | Contrast on `void` / `panel` / `raised` | Deuteranopia sees |
|---|---|---|---|---|
| `bg_void` | `#05070D` | Screen and map background | — | — |
| `bg_panel` | `#0B1120` (92% opacity) | HUD bars and panels ("glass") | — | — |
| `bg_raised` | `#131C30` | Cards, hovered rows, inner boxes | — | — |
| `line` | `#22304D` | Panel borders when idle, dividers | 1.5 (decorative only) | — |
| `deco` | `#1E3A52` | Decorative glyphs, circuit traces, corner brackets | 1.7 (decorative only, never information) | — |
| `text` | `#E6F1FF` | Primary text and numbers | 17.6 / 16.5 / 14.9 | — |
| `text_dim` | `#8A9BB8` | Secondary text, labels, units | 7.2 / 6.7 / 6.0 | — |
| `text_disabled` | `#6B7A96` | Inactive text (always with a lock or ✕ glyph) | 4.7 / 4.4 / 3.9 | — |
| `cyan` | `#2DE2FF` | **Your system:** interactive controls, selection, focus, range rings, "wave cleared" | 12.9 / 12.0 / 10.9 | pale blue |
| `green` | `#5CFF9D` | **Energy:** amount, income, affordable costs, repair | 15.6 / 14.6 / 13.1 | pale yellow ⚠ |
| `amber` | `#FFC53D` | **Arduino and warnings:** Arduino integrity, timers, countdowns, System Load 60–89 | 12.8 / 11.9 / 10.8 | yellow ⚠ |
| `red` | `#FF4D5E` | **Danger and errors:** HP loss, leaks, "can't afford", invalid placement, System Load 90+, crash | 6.2 / 5.8 / 5.2 | olive |
| `magenta` | `#FF3EA5` | **Virus intent:** wave preview icons, Ransomware marks and locks, Spyware aura, the Trojan split ring | 6.2 / 5.8 / 5.2 | grey |
| `violet` | `#A27BFF` | **Upgrade Path B** (already in `globals.gd` as `PATH_B_COLOR`) | 6.5 / 6.1 / 5.5 | blue |
| Tower accents | from `TOWER_DATA.color` | Tower identity only: card stripe, sprite accent, Path A pips | — | — |

⚠ Under deuteranopia, **green (Energy) and amber (Arduino) look alike**, which is why rule R6 matters: Energy always shows a ⚡ glyph and Arduino always shows a chip glyph, and they live in different HUD zones.

**The 60 / 30 / 10 rule:** about 60% `bg_void`, 30% panels, and ≤ 10–15% neon on any screen region. If a panel looks "too neon", remove glow before removing colour.

### C.3 Typography

| Use | Font (free, SIL Open Font License, from Google Fonts) | Size at 1920×1360 | Style |
|---|---|---|---|
| Headings, banners, button labels | **Chakra Petch** SemiBold | 28–64 px | UPPERCASE, letter-spacing +1–2 px |
| Body text, descriptions, tooltips | **Chakra Petch** Regular | 20–24 px (never under 20) | Sentence case |
| Numbers (Energy, HP, costs, timers, wave counts) | **Share Tech Mono** | 24–40 px | Monospace, so changing numbers don't jitter |
| Tiny tags (hotkeys, units) | Share Tech Mono | 16–18 px, only inside a box or tag shape | UPPERCASE |

- Put the font files in `assets/fonts/` with their `OFL.txt` licence files. Check the licence on each download.
- Godot's default font must not appear anywhere once the theme is applied.
- Text sharper than the pixel-art sprites is intentional (Into the Breach does the same). Clean type keeps information readable over busy art.

### C.4 Shapes and lines
- **Chamfered corners** (45° cuts), not rounded ones. In Godot: `StyleBoxFlat` with `corner_radius_* = 8–12` and **`corner_detail = 1`** gives straight-cut corners.
- **Thin lines:** 1 px idle and 2 px for hover, selected or active borders. Never thicker than 3 px.
- **Corner brackets** (`⌐ ¬` style L-shapes in `deco` or the role colour) mark selected panels and the selected tower instead of a full box.
- **Segmented bars** (blocks with 2 px gaps) for Arduino integrity, System Load, the wave progress counter and cooldowns. They read as "machine" and are easy to count.
- **Angled tabs** for panel titles (a short parallelogram behind the heading).

### C.5 Effects budget
| Effect | Where it's allowed | Limit |
|---|---|---|
| Glow (outline or shadow in the role colour) | Hovered or selected controls, critical numbers (Arduino under 30%), ready abilities | Never on body text. At most a 6 px blur. |
| Scanlines (full-screen overlay) | Whole screen | ≤ 6% opacity. Can be turned off in settings. |
| Glitch (horizontal slice offset + RGB split) | Errors, System Crash, level start and end transitions, a virus locking a tower | ≤ 0.3 s, one at a time, never on numbers you need to read |
| Chromatic aberration | Arduino hit and System Crash only | ≤ 0.25 s. Can be turned off. |
| Screen shake | Arduino hit (small), System Crash (medium) | ≤ 6 px, ≤ 0.25 s. Can be turned off. |
| Flicker-in | Panels appearing | 2–3 opacity steps over ≤ 150 ms |

### C.6 Motion
- UI tweens run **120–250 ms**, ease-out. Hover is 120 ms, panels opening 180 ms, banners 250 ms.
- Animate only position, scale, opacity and colour, never layout size.
- Count numbers up or down over 300 ms when they change by more than 10.
- No animation may ever block input (rule R10).

### C.7 Sound pairing (so the UI feels physical)
Short synth blips: hover is soft and quiet, click is crisp, an error is a low double buzz, purchase or upgrade is a rising arpeggio, a leak is a distorted thud, and a cleared wave is a three-note chime. Keep UI sounds quieter than combat sounds.

---

## Part D: Screens and components

### D.1 Screen layout (viewport 1920 × 1360)

```
┌──────────────────────────────── TOP BAR  80 px ────────────────────────────────┐
│ LVL 1 · BOOTLOADER   WAVE ▮▮▮▯▯▯▯▯▯▯ 3/10   │  ARDUINO ▮▮▮▮▮▮▮▮▯▯ 82  │  ⚡ 640 / 1000  +2.0/s │
├────────────────────────────────────────────────────────────────────────────────┤
│                                                                                │
│                         MAP 1920 × 1080  (y 80 → 1160)                          │
│   spatial UI only: range rings, placement ghost, status icons, contextual       │
│   tower panel beside the selected tower, alert banner under the top bar          │
│                                                                                │
├──────────────────────────── BOTTOM DOCK 200 px ────────────────────────────────┤
│ [1 CANNON][2 SPIKE][3 EMP][4 ...]          │ NEXT WAVE: preview │ [ABILITIES][OVERCLOCK] [▶ START][2×] │
└────────────────────────────────────────────────────────────────────────────────┘
```

- **Top bar = global state** (where am I, how am I doing, what can I spend).
- **Bottom dock = actions** (build, call the wave, abilities, Overclock).
- The map in between holds **only spatial UI** (rule R3).
- Nothing floats over the map except the contextual tower panel and banners, and both avoid the path (§D.4).

### D.2 Top bar
| Zone | Content | Behaviour |
|---|---|---|
| Left | `LVL 1 · BOOTLOADER` (heading font, `text_dim`). Then `WAVE` plus **10 segmented pips** (filled pips in cyan) and `3/10` in mono. | The current wave's pip pulses during the wave |
| Centre | Chip glyph + **ARDUINO** + a **10-segment integrity bar** + HP number (mono) | Amber normally. Under 30% it turns red, the glyph glows and the bar blinks slowly. **On a hit:** the bar shakes 4 px for 0.2 s, the lost segments flash red then drain, and the screen edges flash red at 15% opacity for 0.25 s. |
| Right | ⚡ glyph + **Energy** number (mono, green) + `/ 1000` (`text_dim`) + income rate `+2.0/s` + a thin capacity bar | Counts up and down when it changes. At ≥ 90% of the cap the bar turns amber and a small `CAP` tag appears (this replaces the current flashing). Energy lost to the cap shows a tiny red `-n` that floats off. |

Drop the text labels "ARDUINO HP:" and "ENERGY:". The glyph plus position plus colour carries the meaning (rules R5 and R6), and a tooltip on hover gives the full name.

### D.3 Tower cards (bottom dock, left)
Each card is **220 × 150**, chamfered, and contains:
- Top-left hotkey tag `[1]`. Tower sprite (base plus turret) at 2× on the left. Name in the heading font. A one-line **role tag** (e.g. `ANTI-ARMOUR`, `CROWD CONTROL`). Cost with ⚡ at the bottom in mono.
- A 3 px stripe in the tower's accent colour along the left edge (tower identity).
- **States** (each one changes more than colour, per rule R6):

| State | Look |
|---|---|
| Affordable | Cost in green, border `line`, normal opacity |
| Hover | Border cyan 2 px, card lifts 4 px, and a **tooltip** shows stats, the counter role and "Good vs …" |
| Selected (placing) | Border cyan 2 px with corner brackets, glow |
| Can't afford | Card at 55% opacity, cost in red with a ✕ glyph, plus a thin bar showing progress toward the cost |
| Locked (later level) | Padlock glyph and `UNLOCKS LV 3` in `text_disabled` |

- **Just became affordable:** a single 150 ms scale punch (1.0 → 1.05 → 1.0) plus a soft blip.
- **Bug to fix while you're here:** `tower_panel.gd _on_energy_changed()` matches card *i* to `TOWER_DATA.keys()[i]`, not to the unlocked list. Once some towers are hidden, cards show the wrong affordability. Use the same list the cards were built from.

### D.4 Contextual tower panel (`tower_info_panel.gd`)
Keep the current idea: it opens **beside the selected tower** (the Kingdom Rush principle). Change it as follows:
- **Size:** ≤ 380 × 420 px, glass panel, corner brackets in the tower's accent colour.
- **Placement:** open on the side of the tower **away from the nearest path tile**. If both sides have path, open toward the screen centre. Never cover the Arduino.
- **Contents, top to bottom:**
  1. Name and current path/tier pips
  2. **Three key stats** as small icon + number pairs: DPS, range, special. Don't repeat stats as both text and graph (the Defense Grid 2 mistake).
  3. **Two upgrade buttons** (Path A in the accent colour, Path B in violet), each showing name, a one-line effect, cost and state (§D.9)
  4. Target-priority selector (a left/right cycle with the current mode as text)
  5. Repair and Sell
- **On hovering an upgrade:** draw a **ghost range ring** for the new range on the map, and show the stat changes as `24 → 28`, with the new number in green (rule R4).
- **Sell:** one click turns the button into `CONFIRM SELL ⚡ 132` (red, 2 s timeout). The second click sells. Unupgraded towers sell on one click.
- Close with Esc, right-click or clicking empty map.

### D.5 Placement preview (spatial)
- **Valid:** a ghost tower sprite at 60% plus a cyan range ring (1 px, 15% fill), with the path tiles inside range highlighted at 20%.
- **Invalid:** a red ghost plus a ✕ glyph plus a short reason under the cursor (`NOT BUILDABLE`, `OCCUPIED`, `NEED ⚡ 40 MORE`).
- **Empty buildable tiles** show a faint cyan corner-bracket outline only while placing (Kingdom Rush's "blank circles").

### D.6 Enemy and tower status (spatial)
| Status | Indicator (shape, not just colour) |
|---|---|
| Enemy damaged | Thin HP bar above it, only after the first hit |
| Stunned | Small **lightning** glyph plus an icy tint (the tint already exists) |
| In a Spyware aura | Small **eye** glyph plus the aura ring (the ring already exists) |
| Trojan split timer | The existing ring, coloured magenta → red. Pulse during the last 2 s. |
| Ransomware target | A **magenta crosshair** on the marked tower, 2 s ahead |
| Tower locked | **Padlock** glyph plus a countdown ring, and the turret desaturated |
| Tower damaged | HP bar under the tower, only while below 100% |
| Boss (Phase 4) | A wider HP bar plus its name, pinned under the top bar while it's alive |

Enemy glyphs are **12–16 px** and sit above the HP bar, at most 2 per enemy (priority: stunned > aura > others).

### D.7 Wave preview and wave control (bottom dock, middle and right)
- **During the build countdown**, the dock shows `NEXT WAVE 4` plus a **row of virus icons with counts** (`🦠×10 🪱×6`, using the actual sprites), and a magenta **arrow at each entrance** that will be used. This is the Slay the Spire "intent" idea applied to waves (rule R2).
- **`▶ START NOW`** button (key Space) with the countdown in mono (`12`). If an early-start bonus is added later, show it as `+⚡n` on the button.
- **`2×` speed toggle** (key F). When on, it shows as a cyan filled tag, and it's remembered between waves.

### D.8 Abilities and Overclock (bottom dock, right)
- These form **one cluster** (the fix for Kingdom Rush's corner problem): ability buttons left to right in placement order with keys `Q W E R T`, and **Overclock** as a larger button on the far right (key `O`, matching the current input map name if one exists).
- **Ability button:** an icon, a radial cooldown sweep (PvZ seed-packet style), the hotkey tag, and a glow plus a soft chime when it becomes ready.
- **Overclock button:** label, `+⚡150`, a **segmented System Load bar** (green < 60, amber 60–89, red 90+), with tick marks at 60 and 90.
  - On hover: a tooltip that explains the risk in one line.
  - At load ≥ 60: the whole cluster gets an amber border.
  - On a System Crash: a full-screen glitch (0.3 s), the banner `SYSTEM CRASH`, and red tower overlays for 3 s.

### D.9 The one button component
Every button in the game (cards excepted) uses this component with these states:

| State | Border | Fill | Text | Extra cue |
|---|---|---|---|---|
| Normal | `line` 1 px | `bg_raised` | `text` | — |
| Hover | cyan 2 px | `bg_raised` +6% light | `text` | 120 ms lift |
| Pressed | cyan 2 px | cyan at 20% | `text` | 1 px down |
| Disabled | `line` 1 px | `bg_panel` | `text_disabled` | ✕ or padlock glyph |
| Danger (sell, confirm) | red 2 px | red at 12% | `text` | — |
| Path A / Path B | accent / violet 2 px | that colour at 10% | `text` | Tier pips |

### D.10 Alerts and banners
- **One banner at a time,** centred under the top bar, in a queue. Each one has an **icon + short text + a role-coloured left stripe**.

| Type | Colour | Examples | Time |
|---|---|---|---|
| Info | cyan | `WAVE 3 CLEARED  +⚡45` | 1.5 s |
| Threat | magenta | `RANSOMWARE DETECTED`, new virus introductions | 2.5 s, glitch-in |
| Warning | amber | `ENERGY AT CAPACITY`, `SYSTEM LOAD HIGH` | 2 s |
| Danger | red | `ARDUINO CRITICAL`, `SYSTEM CRASH` | 3 s |

- **First appearance of a new virus:** a small card slides in from the right with the sprite, name, a one-line behaviour description and its counter (`COUNTER: DATA SPIKE`). It closes itself after 4 s or on click. This is the "show the new thing in a light wave" rule from the research doc, done in the UI.

### D.11 Full screens (main menu, level select, pause, victory, game over)
- Same glass panels and type. A slow animated circuit-trace background in `deco` at 30% opacity.
- **Level select:** chamfered cards with the map thumbnail, name, new viruses and towers introduced (icons), and the best result (Arduino HP left, shown as segments).
- **Victory:** the integrity bar fills up, there's a stat count-up (viruses purged, Energy earned, towers built), and a cyan glitch-in on the title.
- **Game over:** a brief red glitch, `SYSTEM FAILURE`, and the wave reached. The main button is **RETRY**, with level select as the secondary option.
- **Pause** (P / Esc when nothing is selected): resume, restart, settings (§R14 toggles, volume, UI scale), quit.

---

## Part E: Build order for Claude Code

Do the steps in order, stop after each for review, and run the existing checks after each. Take a screenshot with `screenshot.gd` at the end of each step so the team can review the look.

1. **Style source.** Create `autoloads/ui_style.gd` (autoload `UiStyle`) holding every colour token (§C.2), font, size (§C.3), timing (§C.6) and helper functions: `panel_box(role)`, `button_boxes(role)` returning the state styles from §D.9 with `corner_detail = 1`, and `label(text, kind)`. Build one `Theme` at runtime and set it on the HUD and the UI roots. **Remove hardcoded `Color(...)` and `font_size` values from `scripts/ui/*` and `hud.gd`.** Tower accent colours still come from `TOWER_DATA`.
2. **Fonts.** Add Chakra Petch (Regular, SemiBold) and Share Tech Mono to `assets/fonts/` with their OFL licence files. If you can't download them, stop and ask the team to add them. Don't substitute other fonts silently.
3. **Top bar** (§D.2): segmented wave pips, the Arduino integrity bar with hit feedback, and the Energy readout with income rate, count-up and cap state.
4. **Bottom dock** (§D.1, §D.3, §D.7, §D.8): tower cards with sprite, role tag and states (and the affordability bug fix), the wave preview, Start Now plus 2× speed (`Engine.time_scale = 2`), and the ability + Overclock cluster with radial cooldowns.
5. **Tower panel** (§D.4): restyle, keep it away from the path, add the upgrade ghost ring and stat deltas, and confirm before selling.
6. **Spatial UI** (§D.5, §D.6): placement ghost with reasons, buildable-tile brackets while placing, enemy and tower status glyphs, and the Ransomware crosshair.
7. **Banners and new-virus cards** (§D.10).
8. **Effects layer:** a `CanvasLayer` on top with a scanline shader (≤ 6%), plus glitch and chromatic aberration shaders triggered by events. Add screen shake on the camera or root. All of them obey the settings toggles (R14).
9. **Full screens** (§D.11) and a **settings** menu with the R14 toggles and UI scale.
10. **Checks.** Extend `tools/checks/check_ui.gd`:
    - Every colour pair used for text meets the contrast numbers in §C.2. Compute the contrast from `UiStyle` so it stays true when colours change.
    - No `Color(` literals are left in `scripts/ui/` or `hud.gd`.
    - Every disabled button has a glyph.
    - The game is playable with effects off and at 125% UI scale.

**Don't change:** gameplay numbers, the map art, tower and enemy sprites (only add status glyphs over them), and existing input actions (add new ones for speed and Start Now).

---

## Sources

- [Emily Miles: Kingdom Rush UI review](https://emilym.space/thumbelina-hurts-mobile-ui-blog/2018/6/26/kingdom-rush-a-tower-defense-trilogy-with-ui-design-approaching-perfection-and-entertainment-worth-missing-bedtime-for)
- [Josh Bauer: User Interface Analysis of Tower Defence Games](https://joshbauer94.wordpress.com/2014/11/08/user-interface-analysis-of-tower-defence-games/) (BTD5, Kingdom Rush, Defense Grid 2)
- [Steam discussion: "UI placement was better in Bloons TD5"](https://steamcommunity.com/app/960090/discussions/0/2986411348905563000/)
- [Game Developer: Into the Breach dev on UI design, "Sacrifice cool ideas for the sake of clarity every time"](https://www.gamedeveloper.com/design/-i-into-the-breach-i-dev-on-ui-design-sacrifice-cool-ideas-for-the-sake-of-clarity-every-time-)
- [PC Gamer: Best Design 2019, Slay the Spire](https://www.pcgamer.com/best-design-2019-slay-the-spire/)
- [Cloudfall Studios: Flash Thoughts, Slay the Spire's UI](https://www.cloudfallstudios.com/blog/2018/2/20/flash-thoughts-slay-the-spires-ui)
- [Interface In Game: Cyberpunk 2077 UX/UI critique](https://interfaceingame.com/articles/cyberpunk-2077-ux-ui-critique/)
- [Super Jump: A UX analysis of Cyberpunk 2077's HUD](https://medium.com/super-jump/a-ux-analysis-of-cyberpunk-2077s-hud-f74afe6b9961)
- [designmd.app: Cyberpunk UI design system](https://designmd.app/library/cyberpunk-ui/)
- [Interaction Design Foundation: The Game UX Twist (Celia Hodent's principles)](https://ixdf.org/literature/article/the-game-ux-twist-usability-principles-for-games)
- [Xbox Accessibility Guideline 102: contrast](https://learn.microsoft.com/en-us/xbox/accessibility/xbox-accessibility-guidelines/102)
- [Xbox Accessibility Guideline 103: don't rely on colour alone](https://learn.microsoft.com/en-us/xbox/accessibility/xbox-accessibility-guidelines/103)
- [Juice It or Lose It (Jonasson & Purho, 2012)](https://www.richtaur.com/GameDevTreasure/post/juice-it-or-lose-it/)
- [Beyond the HUD: User Interfaces for Increased Player Immersion in FPS Games (Fagerholt & Lorentzon)](https://www.researchgate.net/publication/277202228_Beyond_the_HUD_-_User_Interfaces_for_Increased_Player_Immersion_in_FPS_Games)
