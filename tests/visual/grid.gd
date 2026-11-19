extends RefCounted
## `--grid-only`, a mode `visual_check.gd` finds by itself.
## `-- <output_dir> --grid-only` shows Frostline's defence grid: the
## Engine Sentinel at the hatch beside a Warden, its tracking beam held on
## a target, and a Warden calling the grid.


static func shoot(v: Node, out_dir: String, _args: PackedStringArray) -> void:
	var raid := Raid.new()
	v.add_child(raid)
	raid.start(Worlds.get_world("frostline"), 42)
	v._armed(raid)
	var boss: Actor = null
	var warden: Actor = null
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
		bot.set_physics_process(false)
		if bot.get_meta("boss", "") == "sentinel":
			boss = bot
		elif warden == null and bot.faction == "warden":
			warden = bot
		else:
			bot.global_position = Vector3(500, 0, 500)
	raid.player.set_physics_process(false)
	raid.player.visible = false
	var at := boss.global_position
	# Both face down the valley, toward the camera.
	for bot: Actor in [boss, warden]:
		bot.cmd.yaw = PI
		bot.rotation.y = PI
	warden.global_position = at + Vector3(-3.0, 0.0, 0.0)
	var camera := Camera3D.new()
	camera.far = 900.0
	raid.add_child(camera)
	camera.make_current()
	camera.global_position = at + Vector3(-3.0, 3.0, 11.0)
	camera.look_at(at + Vector3(-1.5, 1.8, 0.0))
	await v._settle(40)
	await v._shot(out_dir.path_join("grid_sentinel.png"))
	# The beam held on a target down the valley, from the side.
	boss.cmd.secondary = true
	boss.cmd.aim_dir = Vector3(0.1, -0.06, 1.0).normalized()
	camera.global_position = at + Vector3(-12.0, 4.0, 8.0)
	camera.look_at(at + Vector3(0.0, 2.0, 10.0))
	await v._settle(50)
	await v._shot(out_dir.path_join("grid_beam.png"))
	boss.cmd.secondary = false
	camera.global_position = warden.global_position + Vector3(-6.0, 7.0, 14.0)
	camera.look_at(warden.global_position)
	await v._settle(5)
	raid.grid_called.emit(warden, null)
	await v._settle(2)
	await v._shot(out_dir.path_join("grid_call.png"))
	raid.queue_free()
