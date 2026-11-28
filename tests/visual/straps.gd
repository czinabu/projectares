extends RefCounted
## `--straps-only`, a mode `visual_check.gd` finds by itself.
## `-- <output_dir> --straps-only` shoots each back rig's shoulder straps
## close up on both bodies, standing, flying and taking off, from the front
## and over the shoulder: `straps/<rig>_<build>_<state>_<view>.png`.


const RigModel := preload("res://core/visual/rig_model.gd")


static func shoot(v: Node, out_dir: String, _args: PackedStringArray) -> void:
	DirAccess.make_dir_recursive_absolute(out_dir.path_join("straps"))
	var raid := Raid.new()
	v.add_child(raid)
	raid.start(Worlds.get_world("ashfront"), 42, ["rifle_carbine"])
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
		bot.global_position += Vector3(0, -200, 0)
	raid.player.global_position += Vector3(0, -200, 0)
	var camera := Camera3D.new()
	camera.fov = 40.0
	raid.add_child(camera)
	camera.make_current()
	await v._settle(20)
	var spot := Vector3(0, 0, 0)
	for build: String in ["m", "f"]:
		for id: String in ["jetpack_mk1", "jetpack_mk3", "wings_glide"]:
			var p := Actor.new()
			p.set_meta("appearance", {"build": build})
			raid.add_child(p)
			Loadout.equip(p, ["frame_trooper", id])
			await v._settle(10)
			p.set_physics_process(false)
			spot = raid.player.global_position + Vector3(0, 208, 0)
			p.global_position = spot
			p.velocity = Vector3.ZERO
			var skin := p.get_node("Skin")
			for state: String in ["stand", "fly", "takeoff"]:
				var f := p.flight
				f.is_gliding = state != "stand" and f.can_glide()
				f.is_hovering = state != "stand" and not f.can_glide()
				f.is_thrusting = f.is_hovering
				p.airborne_time = 0.0 if state == "stand" else 1.0
				for i in 40:
					p.velocity = (-p.global_basis.z * 20.0 if f.is_gliding else Vector3.ZERO)
					if state == "takeoff":
						skin.set("_takeoff", 0.7)
						skin.set("_takeoff_kind", RigModel.kind_for(id))
					await v.get_tree().process_frame
				var chest := p.global_position + Vector3(0, 1.4, 0)
				if f.is_gliding:
					chest = p.global_position + Vector3(0, 0.9, 0)
				var fwd := -p.global_basis.z
				var side := p.global_basis.x
				var views := {"front": chest + fwd * 1.3 + side * 0.5 + Vector3(0, 0.25, 0),
						"over": chest - fwd * 0.6 + side * 0.9 + Vector3(0, 0.7, 0)}
				for view: String in views:
					camera.look_at_from_position(views[view], chest)
					await v._settle(3)
					await v._shot(out_dir.path_join("straps/%s_%s_%s_%s.png" % [id, build, state, view]))
			p.queue_free()
			await v._settle(3)
	raid.queue_free()
	await v._settle(3)
