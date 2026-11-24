extends Node2D

var level_names = [
	"map_1_bootloader",
	"map_2_dual_bus",
	"map_3_spiral_core",
	"map_4_firewall_breach",
	"map_5_kernel_panic"
]

var game_board: Node2D = null
var current_level: int = 0
var frame_counter: int = 0

func _ready() -> void:
	var bg = ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.05)
	bg.size = Vector2(1920, 1360)
	add_child(bg)
	
	var board_script = load("res://scripts/main/game_board.gd")
	game_board = Node2D.new()
	game_board.set_script(board_script)
	add_child(game_board)
	
	_setup_level(0)

func _setup_level(idx: int) -> void:
	Globals.load_level(idx)
	if game_board.has_method("load_map"):
		game_board.load_map()
	game_board.set("_time", 1.5)
	game_board.queue_redraw()
	frame_counter = 0

func _process(_delta: float) -> void:
	frame_counter += 1
	if frame_counter == 5:
		var img = get_viewport().get_texture().get_image()
		# Save full image and cropped grid image
		var cropped = img.get_region(Rect2i(0, 80, 1920, 1080))
		cropped.save_png("res://" + level_names[current_level] + ".png")
		print("Saved: " + level_names[current_level] + ".png")
		
		current_level += 1
		if current_level < 5:
			_setup_level(current_level)
		else:
			print("All 5 maps saved successfully!")
			get_tree().quit()
