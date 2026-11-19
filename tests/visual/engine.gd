extends RefCounted
## `--engine-only`, a mode `visual_check.gd` finds by itself.
## `-- <output_dir> --engine-only` shows the Engine's inside: the drum and
## its open hatch, the hatch from close, the Drum Hall with a squad in it,
## the Shaft from its lip and from its foot, and a whiteout at the hatch
## seen from inside.


static func shoot(v: Node, out_dir: String, _args: PackedStringArray) -> void:
	const MapScript := preload("res://worlds/frostline/map.gd")
	var raid := Raid.new()
	v.add_child(raid)
	raid.start_server(Worlds.get_world("frostline"), 42)
	var frame := MapScript.engine_frame()
	var f := MapScript.HALL_FLOOR
	var at := func(local: Vector3) -> Vector3: return frame * local
	var squad: Array[Actor] = []
	var kits := [["rifle_carbine", "pistol_service", "jetpack_mk1", "frame_trooper", "helm_spotter"],
			["smg_stinger", "pistol_machine", "boots_thruster", "frame_runner", "helm_seeker"],
			["rifle_carbine", "blade_scrap", "jetpack_mk1", "frame_trooper", "helm_warden"],
			["smg_stinger", "pistol_service", "boots_thruster", "frame_runner", "helm_ember"]]
	for i in kits.size():
		squad.append(raid.add_player(kits[i], {}, "Delver%d" % i, "delver%d" % i))
	for actor in squad + raid.bots:
		var brain := actor.get_node_or_null("Brain")
		if brain != null:
			brain.set_physics_process(false)
		actor.set_physics_process(false)
	var place := func(actors: Array, spots: Array, face: Vector3) -> void:
		for i in mini(actors.size(), spots.size()):
			var a: Actor = actors[i]
			a.global_position = at.call(spots[i])
			var look: Vector3 = at.call(face) - a.global_position
			a.rotation.y = atan2(-look.x, -look.z)
	var guards: Array = raid._guards.map(func(g: Dictionary) -> Variant: return g.bot)
	var cam := Camera3D.new()
	cam.fov = 64.0
	cam.far = 1500.0
	raid.add_child(cam)
	cam.current = true
	# 1. The drum from the valley, its hatch open.
	place.call(squad, [Vector3(-38, f, -14), Vector3(-40, f, -10), Vector3(-42, f, -16), Vector3(-36, f, -8)],
			Vector3(-22, f, -12))
	cam.look_at_from_position(at.call(Vector3(-75, 9, -2)), at.call(Vector3(-10, 2, -6)))
	await v._settle(40)
	await v._shot(out_dir.path_join("engine_1_drum.png"))
	# 2. The hatch from close, looking into the hall.
	place.call(squad, [Vector3(-26, f, -14), Vector3(-27, f, -10), Vector3(-20, f, -13), Vector3(-17, f, -9)],
			Vector3(0, f, -12))
	cam.look_at_from_position(at.call(Vector3(-34, f + 2.2, -12)), at.call(Vector3(0, f + 2.5, -12)))
	await v._settle(20)
	await v._shot(out_dir.path_join("engine_2_hatch.png"))
	# 3. The Drum Hall from its west end, a squad moving up through the cover.
	place.call(squad, [Vector3(-6, f, -26), Vector3(4, f, -24), Vector3(-12, f, -16), Vector3(16, f + 8, -24)],
			Vector3(0, f, 10))
	place.call(guards, [Vector3(6, f, -6), Vector3(-8, f, 0), Vector3(-17, f + 8, 4), Vector3(14, f, 4)],
			Vector3(0, f, -30))
	cam.look_at_from_position(at.call(Vector3(0, f + 4.5, -34)), at.call(Vector3(0, f + 2, 10)))
	await v._settle(30)
	await v._shot(out_dir.path_join("engine_3_hall.png"))
	# 4. The Shaft from its lip.
	place.call(squad, [Vector3(6, f, 2), Vector3(-6, f, 3), Vector3(14, f, 8), Vector3(7, f - 4, 12)],
			Vector3(0, f - 26, 20))
	cam.look_at_from_position(at.call(Vector3(-4, f + 12, -4)), at.call(Vector3(0, f - 24, 24)))
	await v._settle(20)
	await v._shot(out_dir.path_join("engine_4_shaft.png"))
	# 5. The Shaft's foot, looking up the ramps.
	place.call(squad, [Vector3(2, f - 26, 14), Vector3(-6, f - 26, 2), Vector3(-6, f - 20, 16), Vector3(0, f - 13, 29)],
			Vector3(0, f - 26, 30))
	place.call(guards, [Vector3(4, f - 26, 26), Vector3(-2, f - 26, 28)], Vector3(0, f - 26, 0))
	cam.look_at_from_position(at.call(Vector3(-3, f - 24, -0.5)), at.call(Vector3(2, f - 12, 26)))
	await v._settle(20)
	await v._shot(out_dir.path_join("engine_5_foot.png"))
	# 6. The north Coil Gallery from the first cross hall, coils glowing in the alcoves.
	var g := MapScript.GALLERY_FLOOR
	var bottom := MapScript.DESCENT_FLOOR
	var step := MapScript.DESCENT_DROP / 3.0
	place.call(squad, [Vector3(10, g, 44), Vector3(16, g, 47), Vector3(12, g, 54), Vector3(8, g, 41)],
			Vector3(13, g, 100))
	place.call(guards, [Vector3(14, g, 76), Vector3(9, g, 86), Vector3(18, g, 96)], Vector3(13, g, 40))
	cam.look_at_from_position(at.call(Vector3(13, g + 5.5, 39)), at.call(Vector3(14, g + 1.0, 100)))
	await v._settle(20)
	await v._shot(out_dir.path_join("engine_6_galleries.png"))
	# 6b. The walkway, from the gallery floor under its far ramp.
	place.call(squad, [Vector3(18, g + MapScript.WALKWAY_UP, 62), Vector3(18, g + MapScript.WALKWAY_UP, 70),
			Vector3(10, g, 66), Vector3(13, g, 80)], Vector3(13, g, 100))
	cam.look_at_from_position(at.call(Vector3(9, g + 3.0, 104)), at.call(Vector3(17, g + 3.5, 60)))
	await v._settle(20)
	await v._shot(out_dir.path_join("engine_6b_walkway.png"))
	# 7. The south gallery's coolant channel, the dry walk beside it.
	place.call(squad, [Vector3(-8, g, 50), Vector3(-17, g, 46), Vector3(-9, g, 58), Vector3(-13, g, 42)],
			Vector3(-13, g, 100))
	place.call(guards, [Vector3(-9, g, 80), Vector3(-17, g, 92), Vector3(-12, g, 104)], Vector3(-13, g, 40))
	cam.look_at_from_position(at.call(Vector3(-8, g + 5.5, 39)), at.call(Vector3(-14, g, 100)))
	await v._settle(20)
	await v._shot(out_dir.path_join("engine_7_coolant.png"))
	# 8. The Descent from its top landing, the switchback ramps going down.
	place.call(squad, [Vector3(4, g, 117), Vector3(7, g - 5, 132), Vector3(-6, g - step, 161), Vector3(-6, g - step * 1.5, 140)],
			Vector3(0, bottom, 160))
	place.call(guards, [Vector3(5, g - step * 2.0, 117), Vector3(6, bottom, 167), Vector3(-3, bottom, 163)],
			Vector3(0, g, 116))
	cam.look_at_from_position(at.call(Vector3(-9, g + 7, 115)), at.call(Vector3(3, bottom + 4, 165)))
	await v._settle(20)
	await v._shot(out_dir.path_join("engine_8_descent.png"))
	# 9. The Descent's foot: the lift cage, powered, and the open way to the Heart.
	raid.lifts[MapScript.LIFT_ID].left = 600.0
	raid._tick_lifts(0.0)
	place.call(squad, [Vector3(-1, bottom, 174), Vector3(-7, bottom, 168), Vector3(4, bottom, 170), Vector3(8, bottom, 160)],
			Vector3(0, bottom, 176))
	cam.look_at_from_position(at.call(Vector3(6, bottom + 5, 148)), at.call(Vector3(-3, bottom + 3, 174)))
	await v._settle(20)
	await v._shot(out_dir.path_join("engine_9_lift_foot.png"))
	# 10. The lift's top stop in the hall, running.
	place.call(squad, [Vector3(14, f, -9), Vector3(17, f, -7), Vector3(8, f, -12), Vector3(10, f, -4)],
			Vector3(15.5, f, -8))
	cam.look_at_from_position(at.call(Vector3(0, f + 4, -22)), at.call(Vector3(15.5, f + 3, -8)))
	await v._settle(20)
	await v._shot(out_dir.path_join("engine_10_lift_top.png"))
	# 12. The Heart from its door: the keeper under the frozen core, Wardens
	# coming out of the wall sockets, a squad fanning out.
	var c := MapScript.HEART_Z
	var kind := MapScript.HEART_KEEPER
	var heart: Dictionary = {}
	for entry: Dictionary in raid._bosses:
		if (entry.marker as Node3D).get_meta("boss", "") == kind:
			heart = entry
	var keeper: Actor = heart.bot if not heart.is_empty() else null
	var calls: Array[Actor] = []
	calls.assign(squad)
	for i in 3:
		raid._call_from_socket(heart, kind, calls)
	for add: Actor in heart.adds:
		add.set_physics_process(false)
		var add_brain := add.get_node_or_null("Brain")
		if add_brain != null:
			add_brain.set_physics_process(false)
	place.call(squad, [Vector3(-4, bottom, c - 28), Vector3(5, bottom, c - 26), Vector3(-12, bottom, c - 22),
			Vector3(26, bottom + 3, c - 6)], Vector3(0, bottom, c))
	if keeper != null:
		place.call([keeper], [Vector3(0, bottom, c + 2)], Vector3(0, bottom, c - 30))
	cam.look_at_from_position(at.call(Vector3(0, bottom + 4.5, c - 36)), at.call(Vector3(0, bottom + 9, c + 4)))
	await v._settle(30)
	await v._shot(out_dir.path_join("engine_12_heart.png"))
	# 13. From the balcony, looking down on the second phase: the core
	# thawing, one pair of lanes warning and the other venting.
	raid._set_keeper_phase(kind, 2)
	raid.purge_changed.emit(0, 1)
	raid.purge_changed.emit(1, 1)
	raid.purge_changed.emit(2, 2)
	raid.purge_changed.emit(3, 2)
	cam.look_at_from_position(at.call(Vector3(-22, bottom + 13, c - 22)), at.call(Vector3(4, bottom, c + 6)))
	await v._settle(20)
	await v._shot(out_dir.path_join("engine_13_purges.png"))
	# 14. After the fall: a share for each who fought, the deep beacon lit.
	for i in 4:
		raid.purge_changed.emit(i, 0)
	if keeper != null:
		keeper.visible = false
	raid._set_keeper_phase(kind, 0)
	var vault: Node3D = raid._vaults[0] if not raid._vaults.is_empty() else null
	if vault != null:
		for i in 4:
			raid.spawn_container(["engine_coil"], false, "Delver%d's share" % i,
					vault.global_position + vault.global_transform.basis.x * (float(i) - 1.5) * Raid.VAULT_SPACING)
	place.call(squad, [Vector3(-2, bottom, c + 26), Vector3(3, bottom, c + 27), Vector3(0, bottom, c + 20), Vector3(-6, bottom, c + 18)],
			Vector3(0, bottom, c + 34))
	cam.look_at_from_position(at.call(Vector3(6, bottom + 6, c + 4)), at.call(Vector3(0, bottom + 3, c + 32)))
	await v._settle(20)
	await v._shot(out_dir.path_join("engine_14_vault.png"))
	# 11. A whiteout at the hatch, seen from inside.
	var weather := raid.weather
	weather.start()
	weather.velocity = Vector3(0, 0, 0.2)
	weather.life = 100000.0
	weather.age = 1000.0
	weather.strength = 1.0
	var outside: Vector3 = at.call(Vector3(-60, 0, -12))
	weather.centre = Vector3(outside.x, 0.0, outside.z)
	Look.weather_follow = 100.0
	place.call(squad, [Vector3(-16, f, -14), Vector3(-14, f, -9), Vector3(-10, f, -12), Vector3(-30, f, -11)],
			Vector3(-30, f, -12))
	cam.look_at_from_position(at.call(Vector3(-4, f + 2.0, -12)), at.call(Vector3(-40, f + 2.0, -12)))
	await v._settle(60)
	await v._shot(out_dir.path_join("engine_11_storm_at_hatch.png"))
	Look.weather_follow = 0.35
	raid.queue_free()
	await v._settle(4)
