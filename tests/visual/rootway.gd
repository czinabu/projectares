extends RefCounted
## `--rootway-only`, a mode `visual_check.gd` finds by itself.
## `-- <output_dir> --rootway-only` shoots the Spore Marsh's first Rootway
## (DESIGN.md "The Spore Marsh (the Rootways)"): its mouth from the shore,
## down the cut, the throat, the gallery round its pillar, the keeper's
## chamber with the Rootmother in it, and a vent going off.

const Rootway := preload("res://worlds/marsh/rootway.gd")


static func shoot(v: Node, out_dir: String, _args: PackedStringArray) -> void:
	var raid := Raid.new()
	v.add_child(raid)
	raid.start(Worlds.get_world("marsh"), 42)
	var way: Dictionary = Rootway.ROOTWAYS[0]
	var f := Rootway.frame(way)
	var keeper: Actor = null
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
		bot.set_physics_process(false)
		if bot.get_meta("boss", "") == way["keeper"]:
			keeper = bot
		elif not Rootway.inside(bot.global_position + Vector3(0, 1.0, 0)):
			bot.global_position += Vector3(0, -400, 0)
	var player := raid.player
	player.set_physics_process(false)
	player.visible = false
	player.global_position = f * Vector3(0, 0, -30.0)
	var top := float(raid.map.call("ground_height", f.origin.x, f.origin.z))
	var cam := Camera3D.new()
	cam.fov = 70.0
	cam.far = 800.0
	raid.add_child(cam)
	cam.current = true
	await v._settle(40)
	var shots: Array = [
		["rootway_mouth", Vector3(4.0, top + 2.0, -22.0), Vector3(0, top - 3.0, 12.0)],
		["rootway_above", Vector3(-30.0, top + 30.0, -30.0), Vector3(0, top - 4.0, 30.0)],
		["rootway_cut", Vector3(0.0, top + 1.8, 4.0), Vector3(0, Rootway.FLOOR + 2.0, Rootway.CUT + 6.0)],
		["rootway_portal", Vector3(2.0, Rootway.floor_at(26.0, top) + 1.8, 26.0), Vector3(0, Rootway.FLOOR + 2.0, Rootway.THROAT_END)],
		["rootway_gallery", Vector3(-3.0, Rootway.FLOOR + 1.8, 42.0), Vector3(-11.0, Rootway.FLOOR + 1.5, 60.0)],
		["rootway_loop", Vector3(-11.0, Rootway.FLOOR + 1.8, 48.0), Vector3(-11.0, Rootway.FLOOR + 1.0, 72.0)],
		["rootway_bend", Vector3(-8.0, Rootway.FLOOR + 1.8, 68.0), Vector3(Rootway.BEND, Rootway.FLOOR, 76.0)],
		["rootway_chamber", Vector3(Rootway.BEND, Rootway.floor_at(76.0, top) + 1.8, 76.0), Vector3(Rootway.BEND, Rootway.CHAMBER_FLOOR + 2.0, Rootway.CHAMBER_Z)],
	]
	for shot: Array in shots:
		cam.look_at_from_position(f * (shot[1] as Vector3), f * (shot[2] as Vector3))
		player.global_position = cam.global_position - Vector3(0, 1.6, 0)
		await v._settle(6)
		await v._shot(out_dir.path_join("%s.png" % shot[0]))
	if keeper != null:
		keeper.global_position = f * Vector3(Rootway.BEND, Rootway.CHAMBER_FLOOR, Rootway.CHAMBER_Z)
		var at := keeper.global_position
		var reach := keeper.body_height() / 1.4
		var eye := at - f.basis.z * 2.6 * reach + Vector3(0, 0.8 * reach, 0) + f.basis.x * 1.4 * reach
		var toward := eye - at
		keeper.cmd.yaw = atan2(-toward.x, -toward.z)
		keeper.rotation.y = keeper.cmd.yaw
		cam.look_at_from_position(eye, at + Vector3(0, 0.55 * reach, 0))
		await v._settle(8)
		await v._shot(out_dir.path_join("rootway_keeper.png"))
		# From her side, lit by a lamp for the shot alone, to judge her shape.
		var lamp := OmniLight3D.new()
		lamp.omni_range = 14.0
		lamp.light_energy = 2.5
		raid.add_child(lamp)
		var beside := at + f.basis.x * 3.4 * reach + Vector3(0, 0.9 * reach, 0) - f.basis.z * 0.8 * reach
		lamp.global_position = beside + Vector3(0, 1.0, 0)
		cam.look_at_from_position(beside, at + Vector3(0, 0.5 * reach, 0))
		await v._settle(8)
		await v._shot(out_dir.path_join("rootway_keeper_side.png"))
		lamp.queue_free()
	# A vent warns, then vents.
	for state in [1, 2]:
		raid.map.call("show_purge", 0, state)
		raid.map.call("show_purge", 2, state)
		cam.look_at_from_position(f * Vector3(Rootway.BEND - 3.0, Rootway.CHAMBER_FLOOR + 4.0, 83.0), f * Vector3(Rootway.BEND + 4.0, Rootway.CHAMBER_FLOOR, 98.0))
		await v._settle(20)
		await v._shot(out_dir.path_join("rootway_vent_%d.png" % state))
	raid.queue_free()
