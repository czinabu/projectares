extends RefCounted
## Checks for helmets and their visors. Kept in its own file and called from
## the test runner (`-- --only visors` runs just these).

const StashRules := preload("res://core/account/stash_rules.gd")
const BaseLayout := preload("res://core/base/base_layout.gd")
const Economy := preload("res://core/economy/economy.gd")

const SCRAP: Array[String] = ["rifle_scrap", "blade_scrap", "jetpack_mk1", "plate_light"]


static func run(t: Node) -> void:
	_rules(t)
	await _plain(t)
	await _zoom(t)
	await _scan(t)
	await _glass(t)


static func _kit(helmet: String) -> Array[String]:
	var kit := SCRAP.duplicate()
	kit.append(helmet)
	return kit


static func _rules(t: Node) -> void:
	print("Visors: the helmet slot")
	t.check(Loadout.SLOTS.get("helmet", "") == "helmet" and "helmet" not in Loadout.OPTIONAL_SLOTS,
			"helmets have a loadout slot of their own")
	var stash: Array[String] = ["helm_seeker", "chip_blink"]
	t.check(StashRules.can_equip(stash, "helmet", "helm_seeker")
			and not StashRules.can_equip(stash, "helmet", "chip_blink")
			and not StashRules.can_equip(stash, "ability", "helm_seeker"),
			"only a helmet fits the helmet slot, and it fits no other")
	var world := Worlds.get_world("ashfront")
	var free := StashRules.checkout([] as Array[String], {}, world)
	t.check("visor_scav" in free, "with no helmet picked you deploy in the free Scav Visor")
	var taken: Array[String] = []
	var kit := StashRules.checkout(stash, {"helmet": "helm_seeker", "ability": "chip_blink"}, world, taken)
	t.check("helm_seeker" in kit and "chip_blink" in kit and "visor_scav" not in kit and "helm_seeker" in taken,
			"a helmet deploys alongside an ability chip and leaves the stash")
	t.check(not StashRules.storable("visor_scav"), "the Scav Visor is scrap and is never stored")
	t.check("helm_spotter" in Economy.stock("outfitter") and "helm_seeker" in Economy.stock("outfitter")
			and "helm_spotter_mk2" not in Economy.stock("outfitter")
			and "helm_seeker_mk2" not in Economy.stock("outfitter"),
			"the Outfitter sells Mk1 helmets, and Mk2 helmets are loot only")
	t.check(BaseLayout.slot_for("helm_spotter") == "helmet", "the home base knows a helmet goes in the helmet slot")

	var cmd := ActorCommand.new()
	cmd.visor_pressed = true
	cmd.visor_level = 2
	var copy := ActorCommand.new()
	copy.apply_array(cmd.to_array())
	t.check(copy.visor_pressed and copy.visor_level == 2 and not copy.ability_pressed and not copy.slide,
			"the visor key and zoom level survive the trip through a command's network form")
	t.check(cmd.flags() & ActorCommand.ONE_SHOT_MASK == ActorCommand.FLAG_VISOR_PRESSED
			and cmd.flags() & ActorCommand.HELD_MASK == 2 << ActorCommand.VISOR_LEVEL_SHIFT,
			"a scan is a press and a zoom level is held")
	cmd.clear_one_shots()
	t.check(not cmd.visor_pressed and cmd.visor_level == 2, "the press lasts one tick, the zoom level stays")


static func _plain(t: Node) -> void:
	print("Visors: no helmet and the Scav Visor")
	var raid: Raid = await t._kit_raid(310, SCRAP)
	var p := raid.player
	t.check(not p.visor.enabled and p.visor.status_text() == "", "a kit with no helmet wears none")
	p.cmd.visor_pressed = true
	p.cmd.visor_level = 2
	await t.frames(2)
	t.check(not p.visor.is_zoomed() and p.visor.cooldown_left <= 0.0, "with no helmet the visor key does nothing")
	await t._end_raid(raid)

	raid = await t._kit_raid(311, [] as Array[String])
	p = raid.player
	t.check(p.visor.enabled and p.visor.display_name == "Scav Visor" and p.visor.mode == ""
			and "visor_scav" in p.gear_items, "the scrap kit comes with the Scav Visor")
	p.cmd.visor_pressed = true
	p.cmd.visor_level = 1
	await t.frames(2)
	t.check(not p.visor.is_zoomed() and p.visor.ghosts.is_empty(), "the Scav Visor has no ability")
	t.check(PlayerController.next_visor_level(p.visor, 0) == 0, "its visor key never asks for a zoom")
	await t._end_raid(raid)

	raid = await t._kit_raid(312, _kit("helm_seeker"))
	p = raid.player
	t.check("helm_seeker" in p.get_drop_items(), "a helmet drops with the rest of your gear when you die")
	await t._end_raid(raid)


static func _zoom(t: Node) -> void:
	print("Visors: Spotter binoculars")
	var raid: Raid = await t._kit_raid(320, _kit("helm_spotter"))
	var p := raid.player
	var v := p.visor
	t.check(v.enabled and v.mode == "zoom" and v.zoom_levels == [4.0, 8.0], "Spotter stats come from the item")
	t.check(PlayerController.next_visor_level(v, 0) == 1 and PlayerController.next_visor_level(v, 1) == 2
			and PlayerController.next_visor_level(v, 2) == 0, "the visor key steps 4x, 8x, off")
	t.check(is_equal_approx(PlayerController.zoomed_fov(80.0, 1.0), 80.0)
			and absf(tan(deg_to_rad(PlayerController.zoomed_fov(80.0, 4.0)) * 0.5) * 4.0 - tan(deg_to_rad(40.0))) < 0.001,
			"a 4x zoom makes things four times as large")
	p.cmd.visor_level = 1
	await t.frames(2)
	t.check(v.is_zoomed() and is_equal_approx(v.zoom_factor(), 4.0), "asking for the first level zooms to 4x")
	p.cmd.visor_level = 2
	await t.frames(2)
	t.check(is_equal_approx(v.zoom_factor(), 8.0), "the second level is 8x")
	p.cmd.visor_level = 3
	await t.frames(2)
	t.check(is_equal_approx(v.zoom_factor(), 8.0), "a level the helmet lacks is capped at its strongest")

	# Zoomed: slow on your feet and no shooting.
	p.cmd.visor_level = 1
	p.cmd.move = Vector2(0, 1)
	p.cmd.sprint = true
	await t.frames(40)
	var speed := Vector2(p.velocity.x, p.velocity.z).length()
	t.check(speed <= p.walk_speed * v.zoom_move_mult + 0.2 and speed > 0.5,
			"zoomed in you walk at half speed and cannot sprint")
	p.cmd.move = Vector2.ZERO
	p.cmd.sprint = false
	var gun := p.get_active_weapon() as Gun
	var ammo := gun.ammo_in_mag
	p.cmd.primary = true
	p.cmd.primary_pressed = true
	await t.frames(3)
	p.cmd.primary = false
	p.cmd.primary_pressed = false
	t.check(gun.ammo_in_mag == ammo, "the gun does not fire while you look through binoculars")

	# No zoom in the air: it drops, and comes back on landing.
	p.global_position += Vector3(0, 12, 0)
	await t.frames(30)
	t.check(not p.is_on_floor() and not v.is_zoomed(), "the binoculars drop while you are in the air")
	await t._wait_until(func() -> bool: return p.is_on_floor(), 300)
	await t.frames(3)
	t.check(v.is_zoomed(), "they come back up once you land")
	p.stagger(1.0)
	await t.frames(2)
	t.check(not v.is_zoomed(), "a stagger knocks the binoculars down")
	await t.frames(70)

	# Tagging: fire while zoomed marks what you are looking at.
	var bot: Actor = raid.bots[0]
	bot.global_position = p.global_position + Vector3(0, 0.2, -30)
	bot.velocity = Vector3.ZERO
	await t.frames(3)
	var tagged: Array = []
	v.tagged.connect(func(target: Actor) -> void: tagged.append(target))
	p.cmd.yaw = 0.0
	p.cmd.pitch = 0.0
	p.cmd.aim_dir = (bot.global_position + Vector3(0, 1.0, 0) - p.get_eye_position()).normalized()
	p.cmd.visor_level = 0
	p.cmd.primary_pressed = true
	gun.ammo_in_mag = 0
	await t.frames(2)
	t.check(tagged.is_empty(), "firing without zooming tags nobody")
	p.cmd.primary_pressed = false
	p.cmd.visor_level = 2
	await t.frames(2)
	p.cmd.primary_pressed = true
	await t.frames(1)
	p.cmd.primary_pressed = false
	await t.frames(1)
	t.check(tagged == [bot] and v.tags.has(bot) and absf(v.tags[bot] - v.tag_time) < 0.2,
			"firing while zoomed tags the target under the crosshair")
	var health := bot.health.health
	t.check(is_equal_approx(health, bot.health.max_health), "a tag does no damage")
	p.cmd.primary_pressed = true
	await t.frames(1)
	p.cmd.primary_pressed = false
	t.check(tagged.size() == 1 and v.cooldown_left > 0.0, "tags have a short wait between them")
	await t.frames(int(v.tag_time * 60.0) + 10)
	t.check(not v.tags.has(bot), "a tag wears off")
	p.cmd.aim_dir = Vector3.ZERO
	await t._end_raid(raid)

	raid = await t._kit_raid(321, _kit("helm_spotter_mk2"))
	p = raid.player
	t.check(p.visor.zoom_levels == [4.0, 10.0] and p.visor.tag_time > 5.0 and p.visor.mode == "zoom",
			"the Mk2 Spotter sees further and tags for longer")
	await t._end_raid(raid)


static func _scan(t: Node) -> void:
	print("Visors: Seeker scan")
	var raid: Raid = await t._kit_raid(330, _kit("helm_seeker"))
	var p := raid.player
	var v := p.visor
	t.check(v.mode == "scan" and is_equal_approx(v.scan_radius, 40.0) and is_equal_approx(v.cooldown, 25.0),
			"Seeker stats come from the item")
	# Three bots: one near behind a wall's worth of distance, one at the
	# edge, one outside. Everyone else is moved well away.
	for i in raid.bots.size():
		raid.bots[i].global_position = p.global_position + Vector3(300.0 + i * 5.0, 2.0, 300.0)
	var near: Actor = raid.bots[0]
	var edge: Actor = raid.bots[1]
	var far: Actor = raid.bots[2]
	near.global_position = p.global_position + Vector3(12, 0.2, 0)
	edge.global_position = p.global_position + Vector3(0, 0.2, -38)
	far.global_position = p.global_position + Vector3(-46, 0.2, 0)
	await t.frames(2)
	var pulses: Array = []
	var felt := {}
	var notices: Array[String] = []
	v.pulsed.connect(func(origin: Vector3) -> void: pulses.append(origin))
	for bot: Actor in [near, edge, far]:
		bot.visor.felt_scan.connect(func(origin: Vector3) -> void: felt[bot] = origin)
	near.notice.connect(func(text: String) -> void: notices.append(text))
	var near_at := near.global_position
	p.cmd.visor_pressed = true
	await t.frames(1)
	p.cmd.visor_pressed = false
	t.check(pulses.size() == 1 and v.ghosts.size() == 2 and is_equal_approx(v.cooldown_left, v.cooldown) or
			(pulses.size() == 1 and v.ghosts.size() == 2 and v.cooldown_left > v.cooldown - 0.1),
			"a scan shows everyone within its radius and nobody outside it")
	t.check(felt.has(near) and felt.has(edge) and not felt.has(far) and "Scanned" in notices
			and felt[near].distance_to(p.global_position) < 2.0,
			"everyone caught is told, and told where the scan came from")
	# A snapshot: the figure stays where the target stood.
	near.global_position += Vector3(0, 0, 9)
	await t.frames(10)
	var stays := false
	for ghost in v.ghosts:
		stays = stays or ghost.at.distance_to(near_at) < 0.5
	t.check(stays and v.ghosts.size() == 2, "the snapshot stays put when the target moves on")
	p.cmd.visor_pressed = true
	await t.frames(1)
	p.cmd.visor_pressed = false
	t.check(pulses.size() == 1, "the scan cannot be used again until it recharges")
	await t.frames(int(v.ghost_time * 60.0))
	t.check(v.ghosts.is_empty(), "the snapshots fade after a few seconds")
	v.cooldown_left = 0.0
	p.stagger(1.0)
	p.cmd.visor_pressed = true
	await t.frames(1)
	p.cmd.visor_pressed = false
	t.check(pulses.size() == 1, "you cannot scan while staggered")
	await t.frames(70)

	# The dead are not shown, and a client only predicts: the server answers.
	near.kill("bullet")
	await t.frames(2)
	t.check(v.scan() and v.ghosts.size() == 1, "the dead do not show up on a scan")
	v.cooldown_left = 0.0
	Combat.authoritative = false
	var fired := v.scan()
	Combat.authoritative = true
	t.check(fired and pulses.size() == 3 and v.ghosts.size() == 1 and v.cooldown_left > 0.0,
			"on a client the scan fires and recharges but reveals nothing by itself")
	v.show_ghosts([{"at": Vector3(1, 2, 3), "yaw": 0.5}, "junk", {"yaw": 1.0}])
	t.check(v.ghosts.size() == 1 and v.ghosts[0].at == Vector3(1, 2, 3)
			and is_equal_approx(v.ghosts[0].left, v.ghost_time), "the server's answer is shown, junk is dropped")
	await t._end_raid(raid)

	# Sides: allies are never revealed or pinged, rival players are.
	var world := Worlds.get_world("ashfront")
	var server := Raid.new()
	t.add_child(server)
	server.start_server(world, 331)
	for bot in server.bots:
		bot.get_node("Brain").set_physics_process(false)
		bot.global_position += Vector3(0, 0, 400)
	var a := server.add_player(_kit("helm_seeker"), {}, "Alpha", "acct-a")
	var b := server.add_player(_kit("helm_spotter"), {}, "Bravo", "acct-b")
	await t.frames(20)
	b.global_position = a.global_position + Vector3(6, 0.2, 0)
	await t.frames(2)
	var b_felt: Array = []
	b.visor.felt_scan.connect(func(origin: Vector3) -> void: b_felt.append(origin))
	var allied := world.players_allied
	world.players_allied = false
	t.check(a.visor.scan() and a.visor.ghosts.size() == 1 and b_felt.size() == 1,
			"a rival player is revealed and feels it")
	a.visor.cooldown_left = 0.0
	world.players_allied = true
	t.check(a.visor.scan() and a.visor.ghosts.is_empty() and b_felt.size() == 1,
			"players on the same side are neither revealed nor pinged")
	world.players_allied = allied
	server.queue_free()
	await t.frames(2)

	raid = await t._kit_raid(332, _kit("helm_seeker_mk2"))
	t.check(raid.player.visor.scan_radius > 40.0 and raid.player.visor.cooldown < 25.0,
			"the Mk2 Seeker reaches further and recharges sooner")
	await t._end_raid(raid)


static func _glass(t: Node) -> void:
	print("Visors: the glass")
	t.check(is_equal_approx(VisorHud.bearing(0.0), 0.0) and is_equal_approx(VisorHud.bearing(-PI * 0.5), 90.0)
			and is_equal_approx(VisorHud.bearing(PI * 0.5), 270.0), "the compass reads north at -Z and east at +X")
	t.check(VisorHud.compass_name(0.0) == "N" and VisorHud.compass_name(90.0) == "E"
			and VisorHud.compass_name(225.0) == "SW" and VisorHud.compass_name(360.0) == "N",
			"bearings have compass names")
	t.check(absf(VisorHud.angle_to(Vector3(0, 0, -5), Vector3.ZERO, 0.0)) < 0.01
			and absf(VisorHud.angle_to(Vector3(5, 0, 0), Vector3.ZERO, 0.0) - PI * 0.5) < 0.01
			and absf(VisorHud.angle_to(Vector3(5, 0, 0), Vector3.ZERO, -PI * 0.5)) < 0.01,
			"a scan's direction is read from where you are facing")

	var raid: Raid = await t._kit_raid(340, _kit("helm_seeker"))
	var p := raid.player
	var controller := PlayerController.new()
	controller.setup(p)
	raid.add_child(controller)
	var hud := Hud.new()
	hud.setup(raid, controller)
	raid.add_child(hud)
	await t.frames(5)
	var glass := hud.visor
	t.check(glass != null and glass.glass_shown(), "wearing a helmet in first person, the visor is on")
	t.check("[X] Seeker Helmet" in Hud.wrist_text(raid, p, {}, 0.0, [] as Array[String]),
			"the wrist names the visor key and what it does")
	controller.view_mode = PlayerController.ViewMode.THIRD
	await t.frames(40)
	t.check(not glass.glass_shown(), "in third person the visor's readouts are gone")
	# What the visor shows in the world is there in either view.
	var bot: Actor = raid.bots[0]
	bot.global_position = p.global_position + Vector3(8, 0.2, 0)
	await t.frames(2)
	p.visor.scan()
	await t.frames(3)
	t.check(glass._ghosts.size() == p.visor.ghosts.size() and glass._ghosts.size() >= 1
			and glass._rings.size() == 1, "a scan draws its ring and its snapshots in the world")
	p.visor.add_tag(bot, 3.0)
	await t.frames(3)
	t.check(glass._tag_marks.has(bot), "a tagged target carries a marker")
	p.visor.felt_scan.emit(bot.global_position)
	await t.frames(1)
	t.check(glass.felt.size() == 1, "a scan that catches you leaves a mark on the glass")
	controller.view_mode = PlayerController.ViewMode.FIRST
	await t.frames(40)
	t.check(glass.glass_shown(), "back in first person the visor is on again")
	# A lens looking your way glints; one looking elsewhere does not.
	bot.visor.enabled = true
	bot.visor.mode = "zoom"
	bot.global_position = p.global_position + Vector3(0, 0.2, -25)
	bot.cmd.visor_level = 1
	bot.cmd.aim_dir = (p.get_eye_position() - bot.get_eye_position()).normalized()
	await t.frames(5)
	t.check(bot.visor.is_zoomed() and glass._glints.has(bot), "binoculars pointed at you glint")
	bot.cmd.aim_dir = Vector3(1, 0, 0)
	await t.frames(3)
	t.check(not glass._glints.has(bot), "binoculars pointed elsewhere do not")
	p.kill("bullet")
	await t.frames(3)
	t.check(not glass.glass_shown(), "the visor goes dark when you die")
	await t._end_raid(raid)

	raid = await t._kit_raid(341, SCRAP)
	controller = PlayerController.new()
	controller.setup(raid.player)
	raid.add_child(controller)
	hud = Hud.new()
	hud.setup(raid, controller)
	raid.add_child(hud)
	await t.frames(5)
	t.check(not hud.visor.glass_shown(), "with no helmet there is no visor: the view stays bare")
	await t._end_raid(raid)
