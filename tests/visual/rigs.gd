extends RefCounted
## `--rigs-only`, a mode `visual_check.gd` finds by itself.
## `-- <output_dir> --rigs-only` shoots each flight rig being worn.


## Each flight rig on a player, at rest and firing (thrusting, an air jump's
## burn, or gliding), from behind, the side and the front.
static func shoot(v: Node, out_dir: String, _args: PackedStringArray) -> void:
	for id: String in ["jetpack_mk1", "jetpack_mk2", "boots_thruster", "wings_glide"]:
		var raid := Raid.new()
		v.add_child(raid)
		raid.start(Worlds.get_world("ashfront"), 42, ["rifle_carbine", "blade_scrap", id, "frame_trooper"])
		v._armed(raid)
		for bot in raid.bots:
			bot.get_node("Brain").set_physics_process(false)
			bot.global_position += Vector3(0, -200, 0)
		var camera := Camera3D.new()
		camera.fov = 50.0
		raid.add_child(camera)
		camera.make_current()
		var p := raid.player
		# The HUD lights a jetpack's screen bay with its heat; hidden, so
		# nothing else of it shows.
		var hud := Hud.new()
		hud.setup(raid, null)
		hud.visible = false
		raid.add_child(hud)
		await v._settle(30)
		p.set_physics_process(false)
		p.flight.heat = p.flight.max_heat * 0.55
		var at := p.global_position
		var back := p.global_transform.basis.z
		var side := p.global_transform.basis.x
		var skin := p.get_node("Skin")
		var views := {
			"back": at + back * 2.6 + side * 0.6 + Vector3(0, 1.7, 0),
			"side": at + side * 2.6 + back * 0.9 + Vector3(0, 1.3, 0),
			"front": at - back * 2.6 + side * 0.9 + Vector3(0, 1.5, 0),
			"above": at + back * 1.6 + side * 0.4 + Vector3(0, 3.2, 0),
		}
		for active: bool in [false, true]:
			p.flight.is_thrusting = active and p.flight.thrust_accel > 0.0
			p.flight.is_gliding = active and p.flight.can_glide()
			for view: String in views:
				if active and p.flight.burst_velocity > 0.0 and not p.flight.can_glide():
					skin._burst_left = 10.0
				camera.look_at_from_position(views[view], at + Vector3(0, 0.95 if view != "front" else 1.0, 0))
				await v._settle(30 if active and view == "back" else 6)
				await v._shot(out_dir.path_join("rig_%s_%s%s.png" % [id, view, "_on" if active else ""]))
		raid.queue_free()
		await v._settle(3)
