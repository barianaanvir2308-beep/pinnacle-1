#!/usr/bin/env python3
"""
generate_all_maps_photo.py
Creates a master composite photo showcasing all 5 maps of Protocol Zero.
"""

import os
from PIL import Image, ImageDraw, ImageFont, ImageFilter

WIDTH = 2560
HEIGHT = 1760

def get_font(name_options, size, bold=False):
    for name in name_options:
        if os.path.exists(name):
            try:
                return ImageFont.truetype(name, size)
            except Exception:
                pass
    return ImageFont.load_default()

FONT_TITLE = get_font([
    "/System/Library/Fonts/HelveticaNeue.ttc",
    "/System/Library/Fonts/Supplemental/Arial Bold.ttf"
], 38, bold=True)

FONT_SUBTITLE = get_font([
    "/System/Library/Fonts/HelveticaNeue.ttc",
    "/System/Library/Fonts/Supplemental/Arial.ttf"
], 18)

FONT_CARD_TITLE = get_font([
    "/System/Library/Fonts/HelveticaNeue.ttc",
    "/System/Library/Fonts/Supplemental/Arial Bold.ttf"
], 22, bold=True)

FONT_BADGE = get_font([
    "/System/Library/Fonts/Menlo.ttc",
    "/System/Library/Fonts/Supplemental/Arial Bold.ttf"
], 13, bold=True)

FONT_STAT_LABEL = get_font([
    "/System/Library/Fonts/Menlo.ttc",
    "/System/Library/Fonts/Supplemental/Arial.ttf"
], 13)

FONT_STAT_VAL = get_font([
    "/System/Library/Fonts/HelveticaNeue.ttc",
    "/System/Library/Fonts/Supplemental/Arial Bold.ttf"
], 15, bold=True)

FONT_DESC = get_font([
    "/System/Library/Fonts/HelveticaNeue.ttc",
    "/System/Library/Fonts/Supplemental/Arial.ttf"
], 14)

FONT_LEGEND = get_font([
    "/System/Library/Fonts/HelveticaNeue.ttc",
    "/System/Library/Fonts/Supplemental/Arial Bold.ttf"
], 14, bold=True)

FONT_INTEL = get_font([
    "/System/Library/Fonts/HelveticaNeue.ttc",
    "/System/Library/Fonts/Supplemental/Arial.ttf"
], 13)

def create_master_photo():
    img = Image.new("RGBA", (WIDTH, HEIGHT), (6, 8, 16, 255))
    draw = ImageDraw.Draw(img)

    # 1. Subtle background circuit grid pattern
    for x in range(0, WIDTH, 40):
        draw.line([(x, 0), (x, HEIGHT)], fill=(12, 16, 30, 255), width=1)
    for y in range(0, HEIGHT, 40):
        draw.line([(0, y), (WIDTH, y)], fill=(12, 16, 30, 255), width=1)

    # Glow highlights in background
    glow_overlay = Image.new("RGBA", (WIDTH, HEIGHT), (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow_overlay)
    glow_draw.ellipse([WIDTH//2 - 600, -200, WIDTH//2 + 600, 300], fill=(0, 150, 255, 18))
    glow_draw.ellipse([200, HEIGHT//2 - 200, 800, HEIGHT//2 + 400], fill=(0, 255, 136, 12))
    glow_draw.ellipse([WIDTH - 800, HEIGHT//2 - 200, WIDTH - 200, HEIGHT//2 + 400], fill=(180, 0, 255, 12))
    glow_overlay = glow_overlay.filter(ImageFilter.GaussianBlur(80))
    img = Image.alpha_composite(img, glow_overlay)
    draw = ImageDraw.Draw(img)

    # 2. Header Banner
    header_box = [40, 28, WIDTH - 40, 128]
    draw.rounded_rectangle(header_box, radius=12, fill=(10, 14, 28, 220), outline=(0, 180, 255, 80), width=1)
    
    # Header Decorative Top Bar
    draw.line([(60, 30), (220, 30)], fill=(0, 229, 255, 255), width=3)
    draw.line([(WIDTH - 220, 30), (WIDTH - 60, 30)], fill=(0, 255, 136, 255), width=3)

    # Header Title
    draw.text((64, 44), "PROTOCOL ZERO", font=FONT_BADGE, fill=(0, 229, 255, 255))
    draw.text((64, 62), "SYSTEM DEFENSE TOPOLOGIES // ALL 5 MAP BLUEPRINTS", font=FONT_TITLE, fill=(245, 250, 255, 255))
    draw.text((64, 105), "TACTICAL OVERVIEW OF ALL 16×9 MICROGRID SECTORS • ARDUINO CORE HARDPOINTS • INGRESS VECTORS", font=FONT_SUBTITLE, fill=(140, 165, 195, 255))

    # Header Right Badges
    sys_badge_x = WIDTH - 380
    draw.rounded_rectangle([sys_badge_x, 48, WIDTH - 64, 108], radius=8, fill=(16, 22, 42, 240), outline=(0, 255, 136, 90), width=1)
    draw.text((sys_badge_x + 16, 58), "GRID SYSTEM: 16×9 ARRAYS", font=FONT_BADGE, fill=(0, 255, 136, 255))
    draw.text((sys_badge_x + 16, 76), "TOTAL SECTORS: 5 LEVELS", font=FONT_BADGE, fill=(0, 229, 255, 255))
    draw.text((sys_badge_x + 16, 92), "TARGET: ARDUINO CPU CORE", font=FONT_BADGE, fill=(255, 215, 0, 255))

    # 3. Global Map Legend Bar
    legend_box = [40, 140, WIDTH - 40, 188]
    draw.rounded_rectangle(legend_box, radius=8, fill=(12, 16, 32, 230), outline=(50, 70, 110, 120), width=1)
    
    draw.text((60, 154), "MAP KEY:", font=FONT_BADGE, fill=(0, 229, 255, 255))

    legend_items = [
        ("VIRUS SPAWN PORT", (255, 60, 60, 255), "Infiltration Entry Point with Ingress Vectors"),
        ("DATA BUS PATH", (0, 210, 255, 255), "High-Speed Cyan Cyber-Conduit for Malware Traversal"),
        ("DEFENSE HARDPOINT", (0, 255, 136, 255), "Buildable Tech Socket for Defensive Towers"),
        ("ARDUINO CORE", (255, 215, 0, 255), "Central Microcontroller Target to Protect at all Costs"),
        ("SILICON SUBSTRATE", (70, 80, 105, 255), "Non-Conductive Blocked Territory"),
    ]

    leg_x = 160
    for label, color, tip in legend_items:
        draw.rectangle([leg_x, 155, leg_x + 18, 173], fill=color, outline=(255, 255, 255, 120), width=1)
        draw.text((leg_x + 28, 154), label, font=FONT_LEGEND, fill=(230, 240, 255, 255))
        leg_x += len(label) * 11 + 90

    # 4. Define Cards Data
    cards_data = [
        {
            "sector": "SECTOR 01",
            "name": "BOOTLOADER",
            "tag": "TUTORIAL // BALANCED ROUTING",
            "tag_color": (0, 229, 255, 255),
            "img_file": "map_1_bootloader.png",
            "stats": [
                ("WAVES", "10 Waves"),
                ("ENERGY", "300 pts"),
                ("CORE HP", "100 HP"),
                ("SPAWNS", "4 Ingress Ports")
            ],
            "threats": "Basic Virus • Trojan Horse • Worm",
            "briefing": "Initial boot sequence. Symmetrical data bus entering from north, south, and west, converging at the east-flank Arduino core. Ideal for foundational choke point defense."
        },
        {
            "sector": "SECTOR 02",
            "name": "DUAL BUS",
            "tag": "RANSOMWARE HAZARD",
            "tag_color": (255, 100, 100, 255),
            "img_file": "map_2_dual_bus.png",
            "stats": [
                ("WAVES", "10 Waves"),
                ("ENERGY", "350 pts"),
                ("CORE HP", "100 HP"),
                ("SPAWNS", "4 Corner Ports")
            ],
            "threats": "Ransomware (TOWER DISABLE) • Trojan • Worm",
            "briefing": "Two parallel high-throughput data highways. Defeated Ransomware unleashes cryptographic pulses that disable nearby defense towers. Protect the central Arduino."
        },
        {
            "sector": "SECTOR 03",
            "name": "SPIRAL CORE",
            "tag": "STEALTH & SWARM ALERT",
            "tag_color": (200, 100, 255, 255),
            "img_file": "map_3_spiral_core.png",
            "stats": [
                ("WAVES", "10 Waves"),
                ("ENERGY", "400 pts"),
                ("CORE HP", "90 HP"),
                ("SPAWNS", "3 Perimeter Ports")
            ],
            "threats": "Spyware (CLOAKED) • DDoS Bot (MASS SWARM)",
            "briefing": "Concentric cyber-labyrinth spiraling inward toward the central CPU. Features invisible Spyware requiring True Sight and rapid-fire DDoS packet swarms."
        },
        {
            "sector": "SECTOR 04",
            "name": "FIREWALL BREACH",
            "tag": "ARMORED JUGGERNAUTS",
            "tag_color": (255, 180, 0, 255),
            "img_file": "map_4_firewall_breach.png",
            "stats": [
                ("WAVES", "10 Waves"),
                ("ENERGY", "450 pts"),
                ("CORE HP", "85 HP"),
                ("SPAWNS", "8 Breach Ports")
            ],
            "threats": "Rootkit (HEAVY ARMOR) • Spyware • Swarms",
            "briefing": "Perimeter security firewall ruptured. 8 separate infiltration conduits along north and south buses channel armored Rootkits directly into the central Arduino processor."
        },
        {
            "sector": "SECTOR 05",
            "name": "KERNEL PANIC",
            "tag": "MAXIMUM THREAT LEVEL",
            "tag_color": (255, 40, 80, 255),
            "img_file": "map_5_kernel_panic.png",
            "stats": [
                ("WAVES", "10 Waves"),
                ("ENERGY", "500 pts"),
                ("CORE HP", "80 HP"),
                ("SPAWNS", "6 Omnidirectional Ports")
            ],
            "threats": "All 7 Threat Archetypes • Final System Siege",
            "briefing": "Complete system emergency. Omnidirectional 360-degree crossfire converging from all sides onto the epicenter. Requires coordinated high-tier defenses to survive."
        },
        {
            "sector": "TACTICAL INTEL",
            "name": "THREAT MATRIX & ARSENAL",
            "tag": "COUNTERMEASURES GUIDE",
            "tag_color": (0, 255, 136, 255),
            "img_file": None,  # Specialized Intel Card!
            "stats": [
                ("ENEMIES", "7 Virus Types"),
                ("TOWERS", "7 Tower Types"),
                ("UPGRADES", "Level 1 to 3"),
                ("GOAL", "Survive Wave 10")
            ],
            "threats": "Basic Virus, Trojan, Worm, Ransomware, Spyware, Rootkit, DDoS",
            "briefing": "Comprehensive threat intelligence and defensive deployment guide."
        }
    ]

    # Grid geometry
    col_w = 800
    row_h = 750
    spacing_x = 30
    spacing_y = 26
    start_x = 40
    start_y = 200

    for idx, card in enumerate(cards_data):
        row = idx // 3
        col = idx % 3
        cx = start_x + col * (col_w + spacing_x)
        cy = start_y + row * (row_h + spacing_y)
        card_box = [cx, cy, cx + col_w, cy + row_h]

        # Draw card container
        draw.rounded_rectangle(card_box, radius=12, fill=(11, 15, 28, 245), outline=(35, 55, 90, 200), width=1)
        
        # Subtle header bar inside card
        header_h = 56
        draw.rounded_rectangle([cx, cy, cx + col_w, cy + header_h], radius=12, fill=(16, 23, 44, 255), outline=(0, 180, 255, 50), width=1)
        draw.rectangle([cx, cy + header_h - 10, cx + col_w, cy + header_h], fill=(16, 23, 44, 255)) # square bottom corners of header

        # Card Title and Sector
        draw.text((cx + 18, cy + 12), card["sector"] + " //", font=FONT_BADGE, fill=(0, 229, 255, 255))
        draw.text((cx + 18, cy + 28), card["name"], font=FONT_CARD_TITLE, fill=(255, 255, 255, 255))

        # Tag Badge (top right)
        tag_text = card["tag"]
        tag_color = card["tag_color"]
        bbox = draw.textbbox((0, 0), tag_text, font=FONT_BADGE)
        tw = bbox[2] - bbox[0] + 16
        th = bbox[3] - bbox[1] + 10
        tag_x = cx + col_w - tw - 16
        tag_y = cy + 16
        draw.rounded_rectangle([tag_x, tag_y, tag_x + tw, tag_y + th], radius=6, fill=(20, 28, 54, 255), outline=tag_color, width=1)
        draw.text((tag_x + 8, tag_y + 4), tag_text, font=FONT_BADGE, fill=tag_color)

        if card["img_file"]:
            # Load and display map
            map_path = card["img_file"]
            map_img = Image.open(map_path)
            # Map target area
            mw = col_w - 32
            mh = int(mw * 9 / 16) # exact 16:9 ratio
            map_resized = map_img.resize((mw, mh), Image.Resampling.LANCZOS)
            
            map_pos = (cx + 16, cy + header_h + 12)
            # Border behind map
            draw.rounded_rectangle([map_pos[0]-2, map_pos[1]-2, map_pos[0] + mw + 2, map_pos[1] + mh + 2], radius=6, outline=(0, 180, 255, 100), width=2)
            img.paste(map_resized, map_pos)

            # Draw Tech Corner Brackets on Map
            brk_len = 16
            bx1, by1 = map_pos[0], map_pos[1]
            bx2, by2 = map_pos[0] + mw, map_pos[1] + mh
            # TL
            draw.line([(bx1, by1), (bx1 + brk_len, by1)], fill=(0, 229, 255, 255), width=2)
            draw.line([(bx1, by1), (bx1, by1 + brk_len)], fill=(0, 229, 255, 255), width=2)
            # TR
            draw.line([(bx2, by1), (bx2 - brk_len, by1)], fill=(0, 229, 255, 255), width=2)
            draw.line([(bx2, by1), (bx2, by1 + brk_len)], fill=(0, 229, 255, 255), width=2)
            # BL
            draw.line([(bx1, by2), (bx1 + brk_len, by2)], fill=(0, 229, 255, 255), width=2)
            draw.line([(bx1, by2), (bx1, by2 - brk_len)], fill=(0, 229, 255, 255), width=2)
            # BR
            draw.line([(bx2, by2), (bx2 - brk_len, by2)], fill=(0, 229, 255, 255), width=2)
            draw.line([(bx2, by2), (bx2, by2 - brk_len)], fill=(0, 229, 255, 255), width=2)

            info_y = map_pos[1] + mh + 14
        else:
            # Intel card specialized content
            info_y = cy + header_h + 12
            # Draw Arsenal & Threat Matrix inside Card 6
            intel_box_h = 425
            draw.rounded_rectangle([cx + 16, info_y, cx + col_w - 16, info_y + intel_box_h], radius=8, fill=(15, 20, 38, 255), outline=(0, 255, 136, 80), width=1)
            
            # Viruses Title
            draw.text((cx + 28, info_y + 12), "VIRUS SIGNATURE DATABASE", font=FONT_BADGE, fill=(255, 100, 100, 255))
            
            # Draw virus sprites & specs
            viruses = [
                ("basic_virus.png", "BASIC VIRUS", "Fast recon scout"),
                ("trojan_horse.png", "TROJAN HORSE", "Splits on death"),
                ("worm1.png", "WORM", "Segmented crawler"),
                ("ransomware.png", "RANSOMWARE", "Freezes towers"),
                ("spyware.png", "SPYWARE", "Invisible stealth"),
                ("rootkit.png", "ROOTKIT", "Armored juggernaut"),
                ("ddos_bot.png", "DDOS BOT", "High-volume flood")
            ]
            
            vy = info_y + 36
            for spr_name, v_title, v_desc in viruses:
                spr_path = os.path.join("assets/sprites", spr_name)
                if os.path.exists(spr_path):
                    spr = Image.open(spr_path).convert("RGBA")
                    spr.thumbnail((36, 36))
                    # Center sprite in a 40x40 box
                    paste_x = cx + 32 + (40 - spr.width)//2
                    paste_y = vy + (40 - spr.height)//2
                    img.paste(spr, (paste_x, paste_y), spr)
                
                draw.text((cx + 82, vy + 4), v_title, font=FONT_BADGE, fill=(255, 230, 230, 255))
                draw.text((cx + 82, vy + 20), v_desc, font=FONT_INTEL, fill=(170, 185, 210, 255))
                
                vy += 48
                if vy > info_y + 360:
                    break

            # Right side of intel card: Tower Defense Summary
            tx = cx + 400
            draw.line([(tx - 20, info_y + 12), (tx - 20, info_y + intel_box_h - 12)], fill=(30, 45, 80, 255), width=1)
            draw.text((tx, info_y + 12), "TACTICAL DEFENSE ARSENAL", font=FONT_BADGE, fill=(0, 229, 255, 255))

            towers = [
                ("antivirus_cannon.png", "ANTIVIRUS CANNON", "Rapid single-target"),
                ("data_spike.png", "DATA SPIKE", "Piercing laser spike"),
                ("emp_tower.png", "EMP SHOCK TOWER", "Area slowdown pulse"),
                ("sniper_node.png", "SNIPER NODE", "True Sight & long range"),
                ("quarantine_zone.png", "QUARANTINE ZONE", "Trap & quarantine barrier"),
                ("firewall_beam.png", "FIREWALL BEAM", "Continuous burn laser"),
                ("overclock_hub.png", "OVERCLOCK HUB", "Boosts adjacent towers")
            ]

            ty = info_y + 36
            for spr_name, t_title, t_desc in towers:
                spr_path = os.path.join("assets/sprites", spr_name)
                if os.path.exists(spr_path):
                    spr = Image.open(spr_path).convert("RGBA")
                    spr.thumbnail((36, 36))
                    paste_x = tx + (40 - spr.width)//2
                    paste_y = ty + (40 - spr.height)//2
                    img.paste(spr, (paste_x, paste_y), spr)
                
                draw.text((tx + 50, ty + 4), t_title, font=FONT_BADGE, fill=(220, 245, 255, 255))
                draw.text((tx + 50, ty + 20), t_desc, font=FONT_INTEL, fill=(150, 200, 225, 255))
                ty += 48
                if ty > info_y + 360:
                    break

            info_y = info_y + intel_box_h + 14

        # Stats Panel
        stats_w = col_w - 32
        stats_h = 58
        draw.rounded_rectangle([cx + 16, info_y, cx + 16 + stats_w, info_y + stats_h], radius=6, fill=(16, 22, 40, 255), outline=(0, 180, 255, 40), width=1)

        # 4 Stat Columns
        stat_col_w = stats_w // 4
        for s_idx, (s_lbl, s_val) in enumerate(card["stats"]):
            sc_x = cx + 16 + s_idx * stat_col_w
            draw.text((sc_x + 12, info_y + 10), s_lbl, font=FONT_STAT_LABEL, fill=(110, 140, 180, 255))
            val_col = (0, 255, 136, 255) if "pts" in s_val or "10" in s_val else (255, 215, 0, 255) if "HP" in s_val else (255, 120, 120, 255) if "Ports" in s_val else (230, 240, 255, 255)
            draw.text((sc_x + 12, info_y + 28), s_val, font=FONT_STAT_VAL, fill=val_col)
            if s_idx < 3:
                draw.line([(sc_x + stat_col_w, info_y + 8), (sc_x + stat_col_w, info_y + stats_h - 8)], fill=(30, 45, 75, 255), width=1)

        # Threats & Briefing
        info_y += stats_h + 10
        draw.text((cx + 18, info_y), "PRIMARY THREATS: ", font=FONT_BADGE, fill=(255, 100, 100, 255))
        draw.text((cx + 160, info_y), card["threats"], font=FONT_INTEL, fill=(230, 235, 245, 255))
        
        info_y += 22
        draw.text((cx + 18, info_y), "TACTICAL BRIEF:", font=FONT_BADGE, fill=(0, 229, 255, 255))
        
        # Word wrap briefing
        words = card["briefing"].split()
        lines = []
        cur_line = []
        for w in words:
            test_line = " ".join(cur_line + [w])
            bbox = draw.textbbox((0, 0), test_line, font=FONT_DESC)
            if bbox[2] - bbox[0] > (col_w - 180):
                lines.append(" ".join(cur_line))
                cur_line = [w]
            else:
                cur_line.append(w)
        if cur_line:
            lines.append(" ".join(cur_line))

        for l_idx, line in enumerate(lines[:3]):
            draw.text((cx + 160, info_y + l_idx * 20), line, font=FONT_DESC, fill=(160, 180, 205, 255))

    # Save output
    output_path = "all_game_maps.png"
    img.save(output_path, "PNG")
    print(f"Master photo successfully saved: {output_path} ({WIDTH}x{HEIGHT})")

if __name__ == "__main__":
    create_master_photo()
