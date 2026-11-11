extends Node
## Dev tool: runs a real raid with camera and HUD and saves screenshots, so the
## visuals can be checked without playing. Needs a display (or xvfb):
##   godot --path . res://tests/visual_check.tscn -- <output_dir>

func _ready() -> void:
	var out_dir := "user://"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	Profile.persist = false

	var hub := Hub.new()
	add_child(hub)
	await _settle(10)
	await _shot(out_dir.path_join("hub.png"))
	hub.queue_free()

	var raid := Raid.new()
	add_child(raid)
	raid.start(Worlds.get_world("ashfront"), 42)
	var controller := PlayerController.new()
	controller.setup(raid.player)
	raid.add_child(controller)
	var hud := Hud.new()
	hud.setup(raid, controller)
	raid.add_child(hud)

	await _settle(90)
	await _shot(out_dir.path_join("first_person.png"))
	controller.view_mode = PlayerController.ViewMode.THIRD
	await _settle(60)
	await _shot(out_dir.path_join("third_person.png"))
	get_tree().quit()


func _settle(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)
