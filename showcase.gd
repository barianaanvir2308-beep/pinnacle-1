extends Node2D

var enemies = [
	Globals.EnemyType.BASIC_VIRUS,
	Globals.EnemyType.TROJAN_HORSE,
	Globals.EnemyType.WORM,
	Globals.EnemyType.RANSOMWARE,
	Globals.EnemyType.SPYWARE,
	Globals.EnemyType.ROOTKIT,
	Globals.EnemyType.DDOS_BOT
]

var enemy_scripts = [
	"res://scripts/enemies/basic_virus.gd",
	"res://scripts/enemies/trojan_horse.gd",
	"res://scripts/enemies/worm.gd",
	"res://scripts/enemies/ransomware.gd",
	"res://scripts/enemies/spyware.gd",
	"res://scripts/enemies/rootkit.gd",
	"res://scripts/enemies/ddos_bot.gd"
]

var towers = [
	Globals.TowerType.ANTIVIRUS_CANNON,
	Globals.TowerType.DATA_SPIKE,
	Globals.TowerType.EMP_TOWER,
	Globals.TowerType.SNIPER_NODE,
	Globals.TowerType.QUARANTINE_ZONE,
	Globals.TowerType.FIREWALL_BEAM,
	Globals.TowerType.OVERCLOCK_HUB
]

func _ready():
	var bg = ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.08)
	bg.size = Vector2(1920, 1080)
	add_child(bg)
	
	var font = ThemeDB.fallback_font
	
	# Draw Enemies
	for i in range(enemies.size()):
		var script = load(enemy_scripts[i])
		if script:
			var e = Node2D.new()
			e.set_script(script)
			e.position = Vector2(200 + i * 200, 300)
			add_child(e)
			if e.has_method("configure"):
				e.configure(enemies[i], 1.0, 1.0)
			
			var lbl = Label.new()
			lbl.text = Globals.ENEMY_DATA[enemies[i]].name
			lbl.position = e.position + Vector2(-50, 50)
			add_child(lbl)
			
	# Draw Towers
	for i in range(towers.size()):
		var scene_path = Globals.TOWER_DATA[towers[i]].scene_path
		var scene = load(scene_path)
		if scene:
			var t = scene.instantiate()
			t.position = Vector2(200 + i * 200, 700)
			add_child(t)
			if t.has_method("setup"):
				t.setup(towers[i], Vector2i.ZERO)
				
			var lbl = Label.new()
			lbl.text = Globals.TOWER_DATA[towers[i]].name
			lbl.position = t.position + Vector2(-50, 70)
			add_child(lbl)

	get_tree().process_frame.connect(_on_frame)

var frames = 0
func _on_frame():
	frames += 1
	if frames == 10:
		var img = get_viewport().get_texture().get_image()
		img.save_png("res://showcase.png")
		get_tree().quit()
