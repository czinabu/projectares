extends Node
## Dev tool: a contact sheet of people's bodies, bare (no armor or helmet):
## each look from the front, three quarters, the side and behind, then the
## face and the right hand up close. Needs a display (or xvfb):
##   godot --path . res://tests/body_check.tscn -- <output_dir> [--suit]
##       [--kit] [--world <id>] [--turn <degrees>] [--name <file>]
## `--suit` shows the suit as worn under a frame, `--kit` the world's kit instead of a bare body, `--turn`
## turns the body toward the light.

const Human := preload("res://core/visual/human.gd")

const LOOKS := [
	{"build": "m", "head": "Casual_2", "body": "Casual_2", "legs": "Casual_2", "feet": "Casual_2", "skin": 1},
	{"build": "f", "head": "Casual", "body": "Casual", "legs": "Casual", "feet": "Casual", "skin": 3},
	{"build": "m", "head": "Swat", "body": "Swat", "legs": "Swat", "feet": "Swat", "skin": 4},
	{"build": "f", "head": "SciFi", "body": "SciFi", "legs": "SciFi", "feet": "SciFi", "skin": 0},
]
const CELL := Vector2i(300, 420)


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 else "user://"
	Profile.persist = false
	var raid := Raid.new()
	add_child(raid)
	var kit: Array = [Loadout.BARE]
	if "--kit" in args:
		kit = []
	var world_id := "plaza"
	if "--world" in args:
		world_id = args[args.find("--world") + 1]
	raid.start(Worlds.get_world(world_id), 42, kit)
	for bot in raid.bots:
		bot.queue_free()
	raid.bots.clear()
	raid.set_physics_process(false)
	var player := raid.player
	player.set_physics_process(false)
	player.active_weapon_index = -1
	if "--turn" in args:
		player.rotation.y += deg_to_rad(float(args[args.find("--turn") + 1]))
	await _settle(10)
	var cam := Camera3D.new()
	raid.add_child(cam)
	cam.current = true
	# A soft fill from the camera, so a body is never a silhouette.
	var fill := OmniLight3D.new()
	fill.light_energy = 0.6
	fill.omni_range = 12.0
	fill.shadow_enabled = false
	cam.add_child(fill)
	fill.position = Vector3(0.6, 0.8, 0)
	var shots := [
		{"dir": Vector3(0, 0, -1), "dist": 3.4, "h": 0.95, "fov": 40.0},
		{"dir": Vector3(0.75, 0, -0.66), "dist": 3.4, "h": 0.95, "fov": 40.0},
		{"dir": Vector3(1, 0, 0), "dist": 3.4, "h": 0.95, "fov": 40.0},
		{"dir": Vector3(-0.6, 0, 0.8), "dist": 3.4, "h": 0.95, "fov": 40.0},
		{"dir": Vector3(0.3, 0.05, -1), "dist": 0.75, "h": 1.62, "fov": 40.0, "face": true},
		{"dir": Vector3(0.9, 0.1, -0.5), "dist": 0.55, "h": 0.0, "fov": 40.0, "hand": true},
	]
	var sheet := Image.create(shots.size() * CELL.x, LOOKS.size() * CELL.y, false, Image.FORMAT_RGBA8)
	for row in LOOKS.size():
		Look.set_appearance(player, LOOKS[row])
		await _settle(4)
		var skin: Node = player.get_node("Skin")
		for k in 30:
			skin._process(1.0 / 60.0)
			await get_tree().process_frame
		if "--suit" in args:
			for mat: ShaderMaterial in skin._materials:
				mat.set_shader_parameter("suit", 1.0)
		var skeleton := skin.find_child("Skeleton3D", true, false) as Skeleton3D
		for col in shots.size():
			var shot: Dictionary = shots[col]
			var at := player.global_position + Vector3(0, shot["h"], 0)
			if shot.has("hand") and skeleton:
				var bone := skeleton.find_bone("Wrist.R")
				at = skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin
			var dir: Vector3 = player.global_basis * (shot["dir"] as Vector3).normalized()
			cam.fov = shot["fov"]
			cam.global_position = at + dir * float(shot["dist"])
			cam.look_at(at)
			await RenderingServer.frame_post_draw
			var frame := get_viewport().get_texture().get_image()
			var w := frame.get_width()
			var h := frame.get_height()
			var cw := CELL.x * h / CELL.y
			var cut := frame.get_region(Rect2i(w / 2 - cw / 2, 0, cw, h))
			cut.resize(CELL.x, CELL.y)
			cut.convert(Image.FORMAT_RGBA8)
			sheet.blit_rect(cut, Rect2i(Vector2i.ZERO, CELL), Vector2i(col * CELL.x, row * CELL.y))
	var file := "bodies.png"
	if "--name" in args:
		file = args[args.find("--name") + 1]
	sheet.save_png(out_dir.path_join(file))
	print("saved ", file)
	get_tree().quit()


func _settle(count: int) -> void:
	for i in count:
		await get_tree().process_frame
