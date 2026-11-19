extends RefCounted
## `--visors-only`, a mode `visual_check.gd` finds by itself.
## `-- <output_dir> --visors-only` shoots each helmet's visor in first person.


## Each helmet's visor through its wearer's eyes: the Scav Visor, the
## Spotter resting and zoomed, the Seeker ready and just after a scan, the
## Warden with Threat Sense running, and the Ember in thermal.
static func shoot(v: Node, out_dir: String, _args: PackedStringArray) -> void:
	var scrap: Array[String] = ["rifle_scrap", "blade_scrap", "jetpack_mk1", "plate_light", "chip_blink"]
	for helmet: String in ["visor_scav", "helm_spotter", "helm_seeker", "helm_warden", "helm_ember"]:
		var raid := Raid.new()
		v.add_child(raid)
		var kit := scrap.duplicate()
		kit.append(helmet)
		raid.start(Worlds.get_world("ashfront"), 42, kit)
		v._armed(raid)
		for bot in raid.bots:
			bot.get_node("Brain").set_physics_process(false)
		var p := raid.player
		var controller := PlayerController.new()
		controller.setup(p)
		raid.add_child(controller)
		var hud := Hud.new()
		hud.setup(raid, controller)
		raid.add_child(hud)
		await v._settle(30)
		var look := Basis.from_euler(Vector3(0.0, controller.yaw, 0.0))
		var places := [Vector3(3, 0.3, -14), Vector3(-5, 0.3, -24), Vector3(9, 0.3, -30)]
		for i in places.size():
			raid.bots[i].global_position = p.global_position + look * places[i]
			raid.bots[i].cmd.yaw = controller.yaw + PI
		p.health.health = 28.0 if helmet == "visor_scav" else p.health.max_health
		# A squadmate off to the left, a ping ahead, a contract held and a hot war,
		# so the heading strip has what it marks.
		var mate: Actor = raid.bots[3]
		mate.global_position = p.global_position + look * Vector3(-30, 0.3, -40)
		mate.display_name = "Rook"
		var mate_state := Raid.PlayerState.new()
		mate_state.actor = mate
		raid.players.append(mate_state)
		p.clan = "squad"
		mate.clan = "squad"
		raid.pinged.emit(p, p.global_position + look * Vector3(12, 0, -60))
		raid.war.intensity = 0.7
		raid.war.centre = p.global_position + look * Vector3(150, 0, -120)
		hud.contracts.assign([{"id": "cull", "title": "Kill 8 enemies", "stat": "kills", "goal": 8, "have": 3},
				{"id": "haul", "title": "Bring home 600 scrip of loot", "stat": "loot_value", "goal": 600, "have": 240},
				{"id": "ride", "title": "Ride 2 vehicles", "stat": "rides", "goal": 2, "have": 2}])
		hud.objective = "Bank your loot at a depot"
		p.flight.heat = p.flight.max_heat * 0.45
		p.tally["kills"] = 2
		# Out of the gate outpost's lock, gun drawn, mag empty: the readout
		# bottom right wakes up and asks for the reload.
		p.weapons_locked = false
		v._armed(raid)
		await v._settle(2)
		var held_gun := p.get_active_weapon() as Gun
		if held_gun != null:
			held_gun.ammo_in_mag = 0
		await v._settle(20)
		await v._shot(out_dir.path_join("visor_%s.png" % helmet))
		if helmet == "helm_spotter":
			var to_bot: Vector3 = raid.bots[1].global_position + Vector3(0, 1.1, 0) - p.get_eye_position()
			controller.yaw = atan2(-to_bot.x, -to_bot.z)
			controller.pitch = asin(to_bot.normalized().y)
			controller._visor_level = 1
			await v._settle(40)
			await v._shot(out_dir.path_join("visor_helm_spotter_zoom.png"))
			p.visor.add_tag(raid.bots[1], 5.0)
			await v._settle(6)
			await v._shot(out_dir.path_join("visor_helm_spotter_tag.png"))
		elif helmet == "helm_warden":
			# The landing warning: high up, the jetpack overheated, in both views.
			var held_at := p.global_position
			p.global_position = held_at + Vector3(0, 32, 0)
			p.velocity = Vector3.ZERO
			p.flight.heat = p.flight.max_heat
			p.flight.overheated = true
			await v._settle(8)
			await v._shot(out_dir.path_join("visor_landing_first.png"))
			controller.toggle_view()
			p.global_position = held_at + Vector3(0, 32, 0)
			p.velocity = Vector3.ZERO
			controller.yaw += PI
			await v._settle(8)
			await v._shot(out_dir.path_join("visor_landing_third.png"))
			controller.yaw -= PI
			controller.toggle_view()
			p.flight.heat = p.flight.max_heat * 0.45
			p.flight.overheated = false
			p.global_position = held_at
			p.velocity = Vector3.ZERO
			await v._settle(20)
			var near: Actor = raid.bots[0]
			var to_near: Vector3 = near.global_position + Vector3(0, 1.1, 0) - p.get_eye_position()
			controller.yaw = atan2(-to_near.x, -to_near.z)
			controller.pitch = asin(to_near.normalized().y)
			var cache := LootContainer.new()
			cache.setup(["reactor_core", "scrap_metal", "medkit"], false, "Cache")
			raid.add_child(cache)
			cache.global_position = p.global_position + Basis(Vector3.UP, controller.yaw) * Vector3(-1.6, 0, -3.2)
			for aimer: Actor in [raid.bots[1], raid.bots[2]]:
				aimer.cmd.aim_dir = (p.global_position + Vector3(0, 0.9, 0) - aimer.get_eye_position()).normalized()
			p.visor.sense_threats()
			await v._settle(12)
			p.visor.threatened.emit(p.global_position + look * Vector3(-20, 0, 6))
			await v._settle(2)
			await v._shot(out_dir.path_join("visor_helm_warden_sense.png"))
		elif helmet == "helm_ember":
			raid.bots[1].flight.enabled = true
			raid.bots[1].flight.heat = raid.bots[1].flight.max_heat
			controller._visor_level = 1
			await v._settle(20)
			await v._shot(out_dir.path_join("visor_helm_ember_thermal.png"))
		elif helmet == "helm_seeker":
			p.visor.scan()
			await v._settle(12)
			await v._shot(out_dir.path_join("visor_helm_seeker_scan.png"))
			p.visor.felt_scan.emit(p.global_position + look * Vector3(20, 0, 5))
			await v._settle(30)
			await v._shot(out_dir.path_join("visor_helm_seeker_after.png"))
		raid.queue_free()
		await v._settle(3)
	# The same glass at home: a helmet shows it wherever it is worn.
	var base := HomeBase.new()
	base.show_gear(["helm_warden", "rifle_carbine", "frame_trooper", "jetpack_mk1"],
			{"helmet": "helm_warden", "primary": "rifle_carbine", "frame": "frame_trooper", "rig": "jetpack_mk1"})
	v.add_child(base)
	var home_controller := PlayerController.new()
	home_controller.setup(base.player)
	base.add_child(home_controller)
	var base_hud: CanvasLayer = preload("res://core/ui/base_hud.gd").new()
	base_hud.setup(base, home_controller)
	base_hud.contracts.assign([{"id": "cull", "title": "Kill 8 enemies", "stat": "kills", "goal": 8, "have": 5}])
	base_hud.objective = "Head out to the plaza"
	base.add_child(base_hud)
	await v._settle(60)
	await v._shot(out_dir.path_join("visor_home_base.png"))
	base.queue_free()
	await v._settle(3)
