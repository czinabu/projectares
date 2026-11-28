extends RefCounted
## `--fp-flight-only`, a mode `visual_check.gd` finds by itself.
## `-- <output_dir> --fp-flight-only [--move <name>]` (run with `--fixed-fps
## 60`) flies the flight rigs' moves from `flight.gd` in first person, with
## the HUD and the watch up: the view's bob and lean, the hologram the watch
## throws up, the visor's streaks and the rig at the edges of the view. Saves
## every sixth tick's frame to `fp_flight/<move>/NNN.png`.

const Flight := preload("res://tests/visual/flight.gd")
const MOVES := {
	"wings_swoop": {"rig": "wings_glide", "lift": 30.0, "ticks": 300},
	"jetpack_hover": {"rig": "jetpack_mk1", "lift": 0.0, "ticks": 300},
	"boots_skate": {"rig": "boots_thruster", "lift": 0.0, "ticks": 300},
}


static func shoot(v: Node, out_dir: String, args: PackedStringArray) -> void:
	var only := ""
	var at := args.find("--move")
	if at >= 0 and at + 1 < args.size():
		only = args[at + 1]
	for move: String in MOVES:
		if only == "" or only == move:
			await _fly(v, out_dir, move)


static func _fly(v: Node, out_dir: String, move: String) -> void:
	var spec: Dictionary = MOVES[move]
	var raid := Raid.new()
	v.add_child(raid)
	raid.start(Worlds.get_world("ashfront"), 42, ["rifle_carbine", spec["rig"], "frame_trooper", "visor_scav"])
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
		bot.global_position += Vector3(0, -300, 0)
	var p := raid.player
	p.protected_left = 0.0
	var controller := PlayerController.new()
	controller.setup(p)
	raid.add_child(controller)
	var hud := Hud.new()
	hud.setup(raid, controller)
	raid.add_child(hud)
	await v._settle(30)
	# The test flies it, not the keyboard.
	controller.set_physics_process(false)
	controller.view_mode = PlayerController.ViewMode.FIRST
	p.global_position += Vector3(0, float(spec["lift"]), 0)
	p.velocity = Vector3.ZERO
	p.cmd.yaw = p.rotation.y
	p.cmd.pitch = 0.0
	var dir := out_dir.path_join("fp_flight").path_join(move)
	DirAccess.make_dir_recursive_absolute(dir)
	var yaw0 := p.cmd.yaw
	for tick in int(spec["ticks"]):
		Flight._controls(p.cmd, move, tick)
		if move != "jetpack_hover":
			p.cmd.yaw = yaw0 - 0.5 * sin(float(tick - 120) / 120.0 * PI) * clampf((tick - 120) / 60.0, 0.0, 1.0)
		if not move.begins_with("wings"):
			p.cmd.pitch = -0.15
		controller.yaw = p.cmd.yaw
		controller.pitch = p.cmd.pitch
		p.cmd.aim_dir = -p.global_basis.z
		await v.get_tree().physics_frame
		await v.get_tree().process_frame
		if tick % 6 != 0:
			continue
		await RenderingServer.frame_post_draw
		var frame := v.get_viewport().get_texture().get_image()
		frame.resize(frame.get_width() / 2, frame.get_height() / 2)
		frame.save_png(dir.path_join("%03d.png" % (tick / 6)))
	print("saved fp_flight/", move)
	raid.queue_free()
	await v._settle(2)
