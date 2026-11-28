extends RefCounted
## `-- <output_dir> --passage-only`, a mode `visual_check.gd` finds by itself.
## The passage through a gate that fills the view between places
## (`GateLook.transit`, `Main._fade_travel`): for every world, the step in
## (its flash), the passage while the world loads, and the passage opening
## onto that world as it stands; and the plain one on the way home. Add
## `--worlds` to also shoot the opening over the real world for the first
## two worlds (slower: each map is built).


static func shoot(vc: Node, out_dir: String, args: PackedStringArray) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 90
	vc.add_child(layer)
	var cover := ColorRect.new()
	cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cover.material = Look.gate_transit()
	layer.add_child(cover)
	var mat := cover.material as ShaderMaterial
	var view := vc.get_viewport().get_visible_rect().size
	mat.set_shader_parameter("aspect", view.x / maxf(view.y, 1.0))
	var targets: Array = [null]
	targets.append_array(Worlds.raid_worlds())
	targets.append(Worlds.social_world())
	for world in targets:
		var tag: String = (world as WorldDef).id if world != null else "home"
		Look.aim_gate_transit(mat, (world as WorldDef).planet_type() if world != null else null)
		for step: Array in [["in", 0.08, 0.0], ["loading", 2.4, 0.0], ["opening", 3.0, 0.55]]:
			mat.set_shader_parameter("t", step[1])
			mat.set_shader_parameter("arrive", step[2])
			await vc._settle(2)
			await vc._shot(out_dir.path_join("passage_%s_%s.png" % [tag, step[0]]))
	if "--worlds" in args:
		var camera := Camera3D.new()
		camera.far = 2000.0
		vc.add_child(camera)
		for world in Worlds.raid_worlds().slice(0, 2):
			var raid := Raid.new()
			vc.add_child(raid)
			raid.start(world, 7)
			camera.look_at_from_position(Vector3(0, 40, 90), Vector3(0, 5, 0))
			camera.make_current()
			Look.aim_gate_transit(mat, world.planet_type())
			mat.set_shader_parameter("t", 3.2)
			for open: float in [0.3, 0.7]:
				mat.set_shader_parameter("arrive", open)
				cover.color.a = 1.0 - open
				await vc._settle(20)
				await vc._shot(out_dir.path_join("passage_%s_arriving_%d.png" % [world.id, int(open * 100)]))
			raid.queue_free()
			await vc._settle(2)
		cover.color.a = 1.0
