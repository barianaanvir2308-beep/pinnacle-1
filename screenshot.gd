extends SceneTree

func _init() -> void:
	var root = get_root()
	var main_scene = load("res://scenes/main/Main.tscn").instantiate()
	root.add_child(main_scene)
	
	# Start game
	Events.game_state_changed.emit(-1, Globals.GameState.BUILD_PHASE)
	
	# Wait for 2 frames so UI can layout
	await process_frame
	await process_frame
	
	# Take screenshot
	var img = root.get_texture().get_image()
	img.save_png("res://main_screenshot.png")
	quit()
