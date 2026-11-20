extends RefCounted
## `--leviathan-only`, a mode `visual_check.gd` finds by itself:
## `-- <output_dir> --leviathan-only` shoots the Basalt Rift's Sky Leviathan
## over the rift: from the side, from under its engine pods, from above
## onto its spine and turrets, with an engine pod broken, and going down.


static func shoot(v: Node, out_dir: String, _args: PackedStringArray) -> void:
	var raid := Raid.new()
	v.add_child(raid)
	raid.start(Worlds.get_world("rift"), 42)
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
		bot.set_physics_process(false)
	var player := raid.player
	player.set_physics_process(false)
	player.visible = false
	var cam := Camera3D.new()
	cam.fov = 65.0
	cam.far = 1500.0
	raid.add_child(cam)
	cam.current = true
	raid.start_event("airship")
	var ship: Node3D = raid.airship.ship
	var route: Array = raid.airship.route
	# Hold it over the middle of the rift, side on.
	var at: Vector3 = route[route.size() / 2]
	ship.set_physics_process(false)
	ship.global_position = at
	ship.set("heading", PI * 0.5)
	ship.rotation.y = PI * 0.5
	ship.call("_place_rider")
	await v._settle(40)
	var mid := at + Vector3(0, 5.0, 0)
	cam.look_at_from_position(mid + Vector3(-6.0, 6.0, 46.0), mid)
	await v._settle(4)
	await v._shot(out_dir.path_join("leviathan_side.png"))
	# From a jetpack's height under it: the engine pods.
	cam.look_at_from_position(at + Vector3(14.0, -6.0, 22.0), at + Vector3(0, 0.0, 0))
	await v._settle(4)
	await v._shot(out_dir.path_join("leviathan_pods.png"))
	# From an updraft's top: its back, the spine plates and the turrets.
	cam.look_at_from_position(at + Vector3(20.0, 30.0, 18.0), at + Vector3(0, 10.0, 0))
	await v._settle(4)
	await v._shot(out_dir.path_join("leviathan_top.png"))
	# An engine pod broken, the next one still whole.
	var pod: Actor = (ship.get("passengers") as Array)[0]
	Combat.deal(pod, DamageInfo.make(99999.0, player, "bullet", pod.global_position))
	await v._settle(30)
	cam.look_at_from_position(at + Vector3(18.0, -4.0, 20.0), at + Vector3(0, 0.0, 0))
	await v._settle(4)
	await v._shot(out_dir.path_join("leviathan_broken.png"))
	# Every weak spot broken: it goes down.
	for bot: Variant in ship.get("passengers"):
		if bot != null and is_instance_valid(bot) and not (bot as Actor).is_dead:
			Combat.deal(bot, DamageInfo.make(99999.0, player, "bullet", (bot as Actor).global_position))
	ship.set_physics_process(true)
	await v._settle(6)
	if is_instance_valid(ship) and not ship.is_queued_for_deletion():
		var now := ship.global_position + Vector3(0, 5.0, 0)
		cam.look_at_from_position(now + Vector3(-10.0, 4.0, 50.0), now + Vector3(0, -4.0, 0))
		await v._settle(4)
		await v._shot(out_dir.path_join("leviathan_falling.png"))
