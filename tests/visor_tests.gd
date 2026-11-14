extends RefCounted
## Checks for helmets and their visors. Kept in its own file and called from
## the test runner (`-- --only visors` runs just these).

const SkinScript := preload("res://core/visual/actor_skin.gd")

const StashRules := preload("res://core/account/stash_rules.gd")
const BaseLayout := preload("res://core/base/base_layout.gd")
const Economy := preload("res://core/economy/economy.gd")

const SCRAP: Array[String] = ["rifle_scrap", "blade_scrap", "jetpack_mk1", "plate_light"]


static func run(t: Node) -> void:
	_rules(t)
	await _plain(t)
	await _wear(t)
	await _frames(t)
	await _zoom(t)
	await _scan(t)
	await _glass(t)
	await _base_glass(t)
	await _safe_zones(t)
	await _strip(t)
	await _threat(t)
	await _thermal(t)


## Players arrive inside a gate outpost, whose walls would stand between
## them and the bots these checks put round them: stand on an open drop point.
static func _out_in_the_open(raid: Raid, p: Actor) -> void:
	var at := Vector2.from_angle(TAU * 0.5 / 12.0) * 248.0
	p.global_position = raid._stand(Vector3(at.x, raid.map.call("ground_height", at.x, at.y), at.y))
	p.velocity = Vector3.ZERO


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
	t.check("visor_scav" not in free and StashRules.starter_loadout().get("helmet", "") == "visor_scav"
			and not StashRules.new_player_loadout().has("helmet")
			and "visor_scav" in StashRules.checkout([] as Array[String], {"helmet": "visor_scav"}, world),
			"with no helmet picked you deploy bareheaded; the free Scav Visor is yours to wear, and a new player starts bareheaded")
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


static func _wear(t: Node) -> void:
	print("Visors: putting helmets on from the pack")
	var raid: Raid = await t._kit_raid(315, _kit("helm_spotter"))
	var p := raid.player
	var changes: Array[String] = []
	p.helmet_changed.connect(func(id: String) -> void: changes.append(id))
	p.inventory.add_item("helm_seeker")
	var entries := Hud.weapon_entries(p)
	var at := entries.map(func(e: Dictionary) -> String: return e.id).find("helm_seeker")
	t.check(at >= 0 and int(entries[at].index) == -1, "a helmet carried in the pack is on the watch's carousel")
	var slot := Hud.weapon_slot(raid, p, at)
	t.check("Seeker Helmet · wear" in str(slot.detail) and "click" in slot.hints,
			"picked on the carousel, a click puts it on")
	p.visor.zoom_level = 1
	t.check(raid.summon(p, "helm_seeker") == "" and p.visor.mode == "scan" and p.visor.item_id == "helm_seeker"
			and p.visor.cooldown == 25.0 and p.visor.zoom_level == 0 and raid.summon_wait(p) <= 0.0,
			"the summon puts it on at once, its visor is the new helmet's, and the watch need not rest")
	t.check("helm_seeker" in p.gear_items and "helm_spotter" not in p.gear_items
			and p.inventory.has_item("helm_spotter") and not p.inventory.has_item("helm_seeker"),
			"the helmet taken off goes into the pack, and the one put on is worn gear")
	t.check("helm_seeker" in p.get_drop_items() and "helm_spotter" in p.get_drop_items(),
			"both drop on death: the worn one as gear, the other as loot")
	t.check("helm_seeker" in raid.state_for(p).kit and "helm_spotter" not in raid.state_for(p).kit,
			"the kit others are told about follows, so a late joiner sees the helmet worn now")
	t.check(raid.swap_worn(p, "helm_spotter") == "" and p.visor.mode == "zoom" and p.inventory.has_item("helm_seeker"),
			"and the old one can go back on the same way")
	t.check(raid.swap_worn(p, "helm_ember") != "" and p.visor.item_id == "helm_spotter",
			"a helmet not in the pack cannot be put on")
	t.check(changes == ["helm_seeker", "helm_spotter"], "each change is announced for the view and the network")
	Loadout.wear_helmet(p, "")
	t.check(not p.visor.enabled and p.visor.mode == "" and p.visor.levels() == 0 and "helm_spotter" not in p.gear_items,
			"taken off, the visor is bare")
	await t._end_raid(raid)

	var two := _kit("helm_warden")
	two.append("helm_ember")
	raid = await t._kit_raid(316, two)
	p = raid.player
	t.check(p.visor.mode == "threat" and p.inventory.has_item("helm_ember") and "helm_ember" not in p.gear_items,
			"one head: a second helmet in a kit is only carried")
	await t._end_raid(raid)

	var fittings := {"": "Crack", "zoom": "Lens0", "scan": "Fin", "threat": "Brow", "thermal": "Lens"}
	var built := true
	for mode: String in fittings:
		var model := SkinScript.build_helmet(mode, Color.WHITE, Vector3(0.27, 0.31, 0.31), Color.GRAY)
		built = built and model.get_node_or_null("Shell") != null and model.get_node_or_null("Glass") != null \
				and model.get_node_or_null(fittings[mode]) != null
		model.free()
	t.check(built, "every visor mode has a helmet model: a shell, its glass and its own fitting")


static func _frames(t: Node) -> void:
	print("Armor: frames worn and put on from the pack")
	var kit: Array[String] = ["rifle_scrap", "blade_scrap", "jetpack_mk1", "frame_trooper", "frame_runner"]
	var raid: Raid = await t._kit_raid(317, kit)
	var p := raid.player
	var walk := p.walk_speed
	var signature := p.heat_signature
	t.check(p.frame_id == "frame_trooper" and is_equal_approx(p.health.max_armor, 85.0)
			and p.inventory.has_item("frame_runner") and "frame_runner" not in p.gear_items,
			"one frame is worn; a second in a kit is only carried")
	var changes: Array[String] = []
	p.frame_changed.connect(func(id: String) -> void: changes.append(id))
	var ids := Hud.weapon_entries(p).map(func(e: Dictionary) -> String: return e.id)
	t.check("frame_runner" in ids, "a frame carried in the pack is on the watch's carousel")
	p.health.armor = 40.0
	t.check(raid.summon(p, "frame_runner") == "" and p.frame_id == "frame_runner"
			and is_equal_approx(p.health.max_armor, 45.0) and is_equal_approx(p.health.armor, 45.0),
			"a summon puts the frame on, whole")
	t.check(is_equal_approx(p.walk_speed, walk * ItemDB.item_stats("frame_runner").speed_mult) and is_equal_approx(p.heat_signature, signature * 0.7),
			"the old frame's scaling comes off and the new one's goes on")
	t.check("frame_runner" in p.gear_items and "frame_trooper" not in p.gear_items
			and p.inventory.has_item("frame_trooper") and is_equal_approx(float(p.stowed_armor.get("frame_trooper", -1.0)), 40.0),
			"the frame taken off goes into the pack with the armor it had left")
	t.check(raid.summon_wait(p) > 0.0 and raid.swap_worn(p, "frame_trooper") != "",
			"after a frame the watch rests, so spare plates are no instant refill")
	raid.state_for(p).summon_ready_at = raid.clock
	t.check(raid.swap_worn(p, "frame_trooper") == "" and is_equal_approx(p.health.armor, 40.0)
			and is_equal_approx(p.walk_speed, walk) and is_equal_approx(p.heat_signature, signature),
			"put back on, it is as worn as it was, and the body is back as it was")
	t.check(changes == ["frame_runner", "frame_trooper"], "each change is announced for the view and the network")
	t.check("frame_trooper" in p.get_drop_items() and "frame_runner" in p.get_drop_items(),
			"both drop on death: the worn one as gear, the other as loot")
	await t._end_raid(raid)

	var built := true
	var fitted := true
	var coverage := []
	for weight: String in ["light", "medium", "heavy"]:
		var model := SkinScript.build_frame(weight, Color.GRAY)
		built = built and model.get_node_or_null("Chest") != null \
				and (model.get_node_or_null("Belly") != null) == (weight != "light") \
				and (model.get_node_or_null("Collar") != null) == (weight == "heavy")
		# Fitted, not blocky: every plate rides within a few centimetres of
		# the torso (about 0.13 m to each side and 0.1 m in front of the bone).
		var plates := 0
		for part: MeshInstance3D in model.find_children("*", "MeshInstance3D", false, false):
			var box := part.transform * part.get_aabb()
			fitted = fitted and box.position.z > -0.15 and absf(box.position.x) < 0.175 and box.end.x < 0.175
			plates += 1
		coverage.append(plates)
		model.free()
	t.check(fitted, "the plates are curved to the body and ride close to it")
	t.check(coverage[0] < coverage[1] and coverage[1] < coverage[2], "each heavier frame covers more")
	t.check(built and SkinScript.frame_weight("frame_bulwark") == "heavy"
			and SkinScript.frame_weight("plate_light") == "light", "each frame weight has its own plates")


static func _zoom(t: Node) -> void:
	print("Visors: Spotter binoculars")
	var raid: Raid = await t._kit_raid(320, _kit("helm_spotter"))
	var p := raid.player
	_out_in_the_open(raid, p)
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
	_out_in_the_open(raid, p)
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


## A helmet shows its glass wherever it is worn, the home base included
## (Caleb: "the helmet HUDs should be visible everywhere").
static func _base_glass(t: Node) -> void:
	print("Visors: the glass at home")
	const BaseHudScript := preload("res://core/ui/base_hud.gd")
	var owned: Array[String] = ["helm_seeker"]
	var base := HomeBase.new()
	base.show_gear(owned, {"helmet": "helm_seeker"})
	t.add_child(base)
	await t.frames(10)
	var controller := PlayerController.new()
	controller.setup(base.player)
	base.add_child(controller)
	var hud = BaseHudScript.new()
	hud.setup(base, controller)
	base.add_child(hud)
	await t.frames(5)
	var glass: VisorHud = hud.visor
	t.check(glass != null and glass.glass_shown(), "wearing a helmet in your base, the visor's glass is on")
	for i in 90:
		glass._process(1.0 / 60.0)
	t.check(is_equal_approx(glass.boot, 1.0) and glass.compass_marks(base.player).is_empty(),
			"it boots up at home, with nothing from a world on its heading strip")
	base.player.health.damaged.emit(DamageInfo.new())
	t.check(is_equal_approx(glass.alert, 1.0), "and it follows the wearer's own state")
	controller.set("_cam_dist", 4.0)
	t.check(not glass.glass_shown(), "in third person the glass is gone, as out in a world")
	controller.set("_cam_dist", 0.0)
	base.show_gear(owned, {})
	await t.frames(3)
	t.check(not glass.glass_shown(), "taking the helmet off at home takes the glass away")
	hud.queue_free()
	base.queue_free()
	await t.frames(2)


## Helmets work in safe zones and at home, where weapons are locked
## (Caleb: "let helmets abilities work everywhere"). Nobody can fight there,
## so the people a helmet reads are not told.
static func _safe_zones(t: Node) -> void:
	print("Visors: safe zones and home")
	var base := HomeBase.new()
	base.show_gear(["helm_spotter"] as Array[String], {"helmet": "helm_spotter"})
	t.add_child(base)
	await t.frames(10)
	var p := base.player
	t.check(p.weapons_locked and p.visor.mode == "zoom", "at home the helmet is worn and weapons are locked")
	p.cmd.visor_level = 1
	await t.frames(2)
	t.check(p.visor.is_zoomed(), "binoculars zoom at home")
	p.cmd.visor_level = 0
	await t.frames(2)
	t.check(not p.visor.is_zoomed(), "and come back down")
	base.queue_free()
	await t.frames(2)

	var server := Raid.new()
	t.add_child(server)
	server.start_server(Worlds.get_world("plaza"), 341)
	var a := server.add_player(_kit("helm_seeker"), {}, "Alpha", "acct-a")
	var b := server.add_player(_kit("helm_warden"), {}, "Bravo", "acct-b")
	await t.frames(20)
	b.global_position = a.global_position + Vector3(6, 0.2, 0)
	await t.frames(2)
	var felt: Array = []
	var notices: Array[String] = []
	b.visor.felt_scan.connect(func(origin: Vector3) -> void: felt.append(origin))
	b.notice.connect(func(text: String) -> void: notices.append(text))
	a.cmd.visor_pressed = true
	await t.frames(1)
	a.cmd.visor_pressed = false
	t.check(a.weapons_locked and a.visor.cooldown_left > 0.0 and a.visor.ghosts.size() == 1,
			"in the plaza a scan goes out with weapons locked, and shows who is around")
	t.check(felt.is_empty() and "Scanned" not in notices, "nobody in a safe zone is told they were scanned")
	t.check(Visor.peaceful(a), "the plaza counts as peaceful")
	server.queue_free()
	await t.frames(2)


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
	t.check(not "Seeker Helmet" in Hud.wrist_text(raid, p, {}, 0.0),
			"the visor's state is on its own glass, not repeated on the watch")
	hud._process(0.016)
	t.check(hud.wrist.card.bars.is_empty(), "with the glass showing your vitals, the watch card leaves them off")
	if p.ability.enabled:
		t.check(VisorHud.ability_text(p.ability) == p.ability.display_name.to_upper(),
				"a ready ability is named under the vitals on the glass")
	# The glass is alive: it boots, trails the view, wakes on trouble and locks.
	# Stepped by hand so the checks do not depend on how fast frames run.
	var step := func(count: int) -> void:
		for i in count:
			glass._process(1.0 / 60.0)
	glass.boot = 0.0
	step.call(5)
	t.check(glass.boot > 0.0 and glass.boot < 1.0, "the display is still starting up a moment after it comes on")
	step.call(90)
	t.check(is_equal_approx(glass.boot, 1.0), "and is fully up within a second or so")
	glass.alert = 0.0
	step.call(2)
	t.check(glass.alert < 0.05 and glass.sway.length() < 0.5, "with nothing going on it rests dim and still")
	controller.yaw += 0.4
	await t.frames(3)
	step.call(2)
	t.check(glass.sway.length() > 2.0 and glass.sway.length() <= glass.sway_max + 0.01,
			"turning the head leaves the display trailing behind, within a limit")
	step.call(90)
	t.check(glass.sway.length() < 0.5, "and it settles back once the head is still")
	p.health.damaged.emit(DamageInfo.new())
	t.check(is_equal_approx(glass.alert, 1.0), "taking a hit wakes the display")
	step.call(120)
	t.check(glass.alert < 0.05, "and it dims again when things calm down")
	var mark: Actor = raid.bots[0]
	mark.global_position = p.get_eye_position() + p.get_aim_dir() * 12.0 - Vector3(0, 1.0, 0)
	await t.frames(4)
	mark.global_position = p.get_eye_position() + p.get_aim_dir() * 12.0 - Vector3(0, 1.0, 0)
	await t.frames(2)
	step.call(40)
	t.check(glass.aim_target == mark and glass.lock > 0.9, "the reticle locks onto whoever is under it")
	mark.global_position = p.global_position + Vector3(8, 0.2, 0)
	await t.frames(4)
	step.call(40)
	t.check(glass.aim_target == null and glass.lock < 0.1, "and lets go when they leave it")
	controller.view_mode = PlayerController.ViewMode.THIRD
	await t.frames(40)
	t.check(not glass.glass_shown(), "in third person the visor's readouts are gone")
	t.check(glass.boot == 0.0, "and the display is off, so it starts up again next time")
	t.check(glass.reticle_shown(), "but the ring at the crosshair stays in third person")
	mark.global_position = p.get_eye_position() + p.get_aim_dir() * 12.0 - Vector3(0, 1.0, 0)
	await t.frames(4)
	mark.global_position = p.get_eye_position() + p.get_aim_dir() * 12.0 - Vector3(0, 1.0, 0)
	await t.frames(2)
	step.call(40)
	t.check(glass.aim_target == mark and glass.lock > 0.9, "and so do the brackets on whoever is under it")
	mark.global_position = p.global_position + Vector3(8, 0.2, 0)
	await t.frames(4)
	# The helmet's light, worn on the back of the head for third person.
	var v := p.visor
	t.check(SkinScript.helmet_light(v) == "ready", "a charged Seeker's light shows ready")
	v.cooldown_left = 5.0
	t.check(SkinScript.helmet_light(v) == "charging", "a recharging one shows it")
	v.cooldown_left = 0.0
	var plain := Visor.new()
	plain.enabled = true
	t.check(SkinScript.helmet_light(plain) == "", "a plain visor has no light")
	plain.free()
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


static func _threat(t: Node) -> void:
	print("Visors: Warden")
	t.check("helm_warden" in Economy.stock("outfitter") and "helm_warden_mk2" not in Economy.stock("outfitter")
			and "helm_ember" in Economy.stock("outfitter") and "helm_ember_mk2" not in Economy.stock("outfitter"),
			"the Outfitter sells the Mk1 Warden and Ember, never the Mk2s")
	var raid: Raid = await t._kit_raid(350, _kit("helm_warden"))
	var p := raid.player
	var v := p.visor
	t.check(v.mode == "threat" and is_equal_approx(v.threat_range, 60.0) and is_equal_approx(v.cooldown, 30.0)
			and v.levels() == 0, "Warden stats come from the item")
	for i in raid.bots.size():
		raid.bots[i].global_position = p.global_position + Vector3(300.0 + i * 5.0, 2.0, 300.0)
	var aimer: Actor = raid.bots[0]
	var idler: Actor = raid.bots[1]
	var distant: Actor = raid.bots[2]
	aimer.global_position = p.global_position + Vector3(20, 0.2, 0)
	idler.global_position = p.global_position + Vector3(0, 0.2, 20)
	distant.global_position = p.global_position + Vector3(-90, 0.2, 0)
	await t.frames(3)
	var chest := p.global_position + Vector3(0, Actor.BODY_HEIGHT * 0.5, 0)
	aimer.cmd.aim_dir = (chest - aimer.get_eye_position()).normalized()
	idler.cmd.aim_dir = Vector3(0, 0, 1)
	distant.cmd.aim_dir = (chest - distant.get_eye_position()).normalized()
	t.check(v.is_aimed_at_by(aimer) and not v.is_aimed_at_by(idler) and not v.is_aimed_at_by(distant),
			"aiming at you means pointing at you from within reach")
	var notices: Array[String] = []
	aimer.notice.connect(func(text: String) -> void: notices.append(text))
	await t.frames(5)
	t.check(v.threats.is_empty(), "nobody is outlined until Threat Sense is used")
	p.cmd.visor_pressed = true
	await t.frames(1)
	p.cmd.visor_pressed = false
	await t.frames(15)
	t.check(v.is_sensing() and v.threats == ([aimer] as Array[Actor]),
			"Threat Sense outlines who is aiming at you, and only them")
	t.check(notices.count("Sensed") == 1, "someone it shows is told, once")
	# Looking away drops you off it; looking back puts you on again.
	aimer.cmd.aim_dir = Vector3(0, 0, -1)
	await t.frames(15)
	t.check(v.threats.is_empty(), "stop aiming and the outline goes")
	idler.cmd.aim_dir = (chest - idler.get_eye_position()).normalized()
	await t.frames(15)
	t.check(v.threats == ([idler] as Array[Actor]), "start aiming and it appears")
	p.cmd.visor_pressed = true
	await t.frames(1)
	p.cmd.visor_pressed = false
	t.check(v.active_left < v.threat_time - 0.5, "it cannot be restarted while it recharges")
	await t.frames(int(v.threat_time * 60.0))
	t.check(not v.is_sensing() and v.threats.is_empty() and v.cooldown_left > 0.0,
			"Threat Sense ends after five seconds and everyone drops off it")

	# Where a hit came from.
	var origins: Array = []
	v.threatened.connect(func(origin: Vector3) -> void: origins.append(origin))
	p.protected_left = 0.0
	var hitter: Actor = null
	for bot in raid.bots:
		if is_instance_valid(bot) and not bot.is_dead:
			hitter = bot
			break
	Combat.deal(p, DamageInfo.make(5.0, hitter, "bullet", p.global_position))
	t.check(origins.size() == 1 and origins[0].distance_to(hitter.global_position) < 0.1,
			"a hit tells a Warden where it came from")
	Combat.deal(p, DamageInfo.make(5.0, null, "storm", p.global_position))
	t.check(origins.size() == 1, "damage with nobody behind it points nowhere")
	Combat.authoritative = false
	v.cooldown_left = 0.0
	var started := v.sense_threats()
	v._threat_wait = 0.0
	await t.frames(10)
	Combat.authoritative = true
	t.check(started and v.threats.is_empty(), "on a client Threat Sense waits for the server's word")
	v.show_threats([hitter, "junk", null])
	t.check(v.threats == ([hitter] as Array[Actor]), "the server's list is shown, junk is dropped")
	await t._end_raid(raid)

	# A plain visor learns nothing from being hit.
	raid = await t._kit_raid(351, _kit("helm_seeker"))
	origins = []
	raid.player.visor.threatened.connect(func(origin: Vector3) -> void: origins.append(origin))
	raid.player.protected_left = 0.0
	Combat.deal(raid.player, DamageInfo.make(5.0, raid.bots[0], "bullet", raid.player.global_position))
	t.check(origins.is_empty(), "only a tactical visor shows where a hit came from")
	await t._end_raid(raid)

	# The glass: target readout, loot peek and outlines.
	t.check(VisorHud.loot_text([]) == "" and VisorHud.loot_text(["scrap_metal"]) == ItemDB.item_name("scrap_metal")
			and VisorHud.loot_text(["scrap_metal", "reactor_core", "medkit"]) == ItemDB.item_name("reactor_core") + " +2",
			"a container's tag names its best item and counts the rest")
	raid = await t._kit_raid(352, _kit("helm_warden_mk2"))
	p = raid.player
	t.check(p.visor.threat_range > 60.0 and p.visor.cooldown < 30.0 and p.visor.read_range > 30.0,
			"the Mk2 Warden reaches further and recharges sooner")
	var controller := PlayerController.new()
	controller.setup(p)
	raid.add_child(controller)
	var hud := Hud.new()
	hud.setup(raid, controller)
	raid.add_child(hud)
	await t.frames(5)
	var bot: Actor = raid.bots[0]
	var ahead := Basis(Vector3.UP, controller.yaw) * Vector3(0, 0, -12)
	bot.global_position = p.global_position + ahead + Vector3(0, 0.2, 0)
	bot.velocity = Vector3.ZERO
	await t.frames(3)
	var to_bot := bot.global_position + Vector3(0, 1.0, 0) - p.get_eye_position()
	controller.yaw = atan2(-to_bot.x, -to_bot.z)
	controller.pitch = asin(to_bot.normalized().y)
	await t.frames(12)
	t.check(hud.visor.read_target == bot, "a tactical visor reads whoever is under the crosshair")
	bot.global_position = p.global_position + ahead * 6.0 + Vector3(0, 0.2, 0)
	await t.frames(3)
	to_bot = bot.global_position + Vector3(0, 1.0, 0) - p.get_eye_position()
	controller.yaw = atan2(-to_bot.x, -to_bot.z)
	controller.pitch = asin(to_bot.normalized().y)
	await t.frames(12)
	t.check(hud.visor.read_target == null, "but not someone beyond its reach")
	p.visor.show_threats([bot])
	await t.frames(3)
	t.check(hud.visor._threat_marks.has(bot), "someone Threat Sense shows is outlined in the world")
	p.visor.show_threats([])
	await t.frames(3)
	t.check(hud.visor._threat_marks.is_empty(), "and the outline goes when they drop off it")
	p.visor.threatened.emit(bot.global_position)
	await t.frames(1)
	t.check(hud.visor.hit_marks.size() == 1, "a hit leaves a mark on the glass")
	await t._end_raid(raid)


static func _thermal(t: Node) -> void:
	print("Visors: Ember")
	var raid: Raid = await t._kit_raid(360, _kit("helm_ember"))
	var p := raid.player
	var v := p.visor
	t.check(v.mode == "thermal" and is_equal_approx(v.battery, 12.0) and v.levels() == 1
			and PlayerController.next_visor_level(v, 0) == 1 and PlayerController.next_visor_level(v, 1) == 0,
			"Ember stats come from the item, and its key switches thermal on and off")
	await t.frames(2)
	t.check(not v.thermal_on and is_equal_approx(v.charge_fraction(), 1.0), "it starts off with a full battery")
	p.cmd.visor_level = 1
	await t.frames(60)
	t.check(v.thermal_on and absf(v.charge - (v.battery - 1.0)) < 0.1, "thermal drains the battery while it is on")
	p.cmd.visor_level = 0
	await t.frames(2)
	var low := v.charge
	await t.frames(60)
	t.check(not v.thermal_on and v.charge > low + 0.5, "switched off, the battery refills")
	# Run it flat: it cuts out and stays out until the key is let go.
	p.cmd.visor_level = 1
	v.charge = 0.3
	await t.frames(30)
	t.check(not v.thermal_on and v.charge < 1.0, "a flat battery switches thermal off")
	await t.frames(int(v.battery_refill * 60.0 * 0.5))
	t.check(not v.thermal_on, "it does not flicker back on while the key is still held")
	p.cmd.visor_level = 0
	await t.frames(2)
	v.charge = v.battery * 0.1
	p.cmd.visor_level = 1
	await t.frames(3)
	t.check(not v.thermal_on, "it needs a quarter charge to start")
	v.charge = v.battery * 0.5
	await t.frames(3)
	t.check(v.thermal_on, "with enough charge it starts again")
	p.stagger(0.5)
	await t.frames(2)
	t.check(not v.thermal_on, "a stagger knocks thermal off")
	p.cmd.visor_level = 0
	await t.frames(40)

	# Heat: jetpacks shine, heavy frames run hot, light frames run cool.
	var bot: Actor = raid.bots[0]
	var base := Visor.heat_of(bot)
	bot.flight.enabled = true
	bot.flight.heat = bot.flight.max_heat
	t.check(Visor.heat_of(bot) > base * 1.8, "a hot jetpack makes its wearer shine on thermal")
	await t._end_raid(raid)
	raid = await t._kit_raid(361, ["rifle_scrap", "blade_scrap", "jetpack_mk1", "frame_bulwark"] as Array[String])
	var heavy := Visor.heat_of(raid.player)
	await t._end_raid(raid)
	raid = await t._kit_raid(362, ["rifle_scrap", "blade_scrap", "jetpack_mk1", "frame_runner"] as Array[String])
	var light := Visor.heat_of(raid.player)
	await t._end_raid(raid)
	raid = await t._kit_raid(363, ["rifle_scrap", "blade_scrap", "jetpack_mk1", "plate_light"] as Array[String])
	var plain := Visor.heat_of(raid.player)
	await t._end_raid(raid)
	t.check(heavy > plain and plain > light, "a heavy frame is bright on thermal and a light one is dim")

	# The picture.
	raid = await t._kit_raid(364, _kit("helm_ember_mk2"))
	p = raid.player
	t.check(p.visor.battery > 12.0 and p.visor.battery_refill < 18.0, "the Mk2 Ember holds more charge")
	var controller := PlayerController.new()
	controller.setup(p)
	raid.add_child(controller)
	var hud := Hud.new()
	hud.setup(raid, controller)
	raid.add_child(hud)
	await t.frames(5)
	var glass := hud.visor
	t.check(not glass.thermal_shown and glass._heat.is_empty(), "with thermal off the view is as it always is")
	controller._visor_level = 1
	await t.frames(6)
	t.check(p.visor.thermal_on and glass.thermal_shown and glass._thermal.visible
			and glass._heat.size() == raid.bots.size(), "thermal shows the heat picture and every warm body")
	var cold: Actor = raid.bots[0]
	cold.kill("bullet")
	await t.frames(4)
	t.check(not glass._heat.has(cold), "the dead go cold")
	controller.view_mode = PlayerController.ViewMode.THIRD
	await t.frames(40)
	t.check(not glass.thermal_shown and glass._heat.is_empty(), "in third person there is no heat picture")
	controller.view_mode = PlayerController.ViewMode.FIRST
	controller._visor_level = 0
	await t.frames(40)
	# Someone else's thermal visor shows as an ember up close.
	var other: Actor = raid.bots[1]
	other.visor.enabled = true
	other.visor.mode = "thermal"
	other.cmd.visor_level = 1
	other.global_position = p.global_position + Vector3(0, 0.2, -8)
	await t.frames(5)
	t.check(other.visor.thermal_on and glass._embers.has(other), "a thermal visor in use glows when seen up close")
	other.global_position = p.global_position + Vector3(0, 0.2, -60)
	await t.frames(5)
	t.check(not glass._embers.has(other), "and cannot be seen from far away")
	await t._end_raid(raid)


## The layout round the edges (Caleb's redesign): vitals as hex cells on
## the lower left curve, the contact scope top left, objectives top right.
static func _layout(t: Node, raid: Raid, glass: VisorHud) -> void:
	print("Visors: the layout round the edges")
	var p := raid.player
	glass.size = Vector2(1920, 1080)
	var ink := p.visor.glass_color
	var kinds := func() -> Array:
		return glass.vital_cells(p, ink).map(func(c: Dictionary) -> String: return c.kind)
	t.check(kinds.call().slice(0, 1) == ["health"] and "stamina" in kinds.call() and "armor" in kinds.call()
			and "heat" in kinds.call(), "the vitals are cells: health first, then armor, stamina and the rig's heat")
	p.flight.enabled = false
	t.check(not "heat" in kinds.call(), "with no flight rig there is no heat cell")
	p.flight.enabled = true
	p.health.health = p.health.max_health * 0.2
	var health: Dictionary = glass.vital_cells(p, ink)[0]
	t.check(health.warn and health.label == "CRITICAL" and health.value == "20%",
			"low on health, its cell turns red and says so")
	p.health.health = p.health.max_health
	var first := glass.cell_point(0.0)
	var last := glass.cell_point(4.0)
	t.check(first.x < last.x and last.x < 960.0 * 0.7 and first.y > 540.0 * 1.5 and last.y > first.y,
			"the cells run along the lower left curve of the glass, lifting toward its edge, clear of the middle")
	t.check(VisorHud.hex_points(Vector2.ZERO, 10.0).size() == 6, "each cell is a hexagon")
	# The scope: a mark close by plots inside it, one far off waits on its rim.
	var scope := glass.scope_rect()
	t.check(scope.end.x < 960.0 * 0.5 and scope.end.y < 540.0, "the contact scope sits in the top left corner")
	raid.pinged.emit(p, p.global_position + p.get_aim_dir().slide(Vector3.UP).normalized() * 30.0)
	var near: Array = glass.scope_points(p).filter(func(d: Dictionary) -> bool: return d.mark.kind == "ping")
	t.check(near.size() == 1 and near[0].inside and near[0].at.y < scope.get_center().y,
			"a ping 30 m ahead plots inside the scope, above the middle")
	raid.pinged.emit(p, p.global_position + Vector3(400, 0, 0))
	var far: Array = glass.scope_points(p).filter(func(d: Dictionary) -> bool:
		return d.mark.kind == "ping" and not d.inside)
	t.check(far.size() == 1 and absf(far[0].at.distance_to(scope.get_center()) - (scope.size.x * 0.5 - 6.0)) < 1.0,
			"one beyond its reach waits on the rim, pointing the way")
	# The objective block: nearest done first, this life's counts on top, the
	# tour's step last.
	var held: Array[Dictionary] = [{"title": "Kill 8 enemies", "stat": "kills", "goal": 8, "have": 1},
			{"title": "Ride 2 vehicles", "stat": "rides", "goal": 2, "have": 1}]
	var lines: Array[Dictionary] = glass.objective_lines(held, {"kills": 2}, "Bank your loot at a depot")
	t.check(lines.size() == 3 and lines[0].title == "Ride 2 vehicles" and lines[1].have == 3 and lines[1].goal == 8
			and lines[2].tour and not lines[0].done, "objectives list nearest done first, with this life's kills counted")
	lines = glass.objective_lines(held, {"rides": 1}, "")
	t.check(lines.size() == 2 and lines[0].done and lines[0].share == 1.0, "a finished contract is marked done")
	t.check(glass.objective_lines([] as Array[Dictionary], {}, "").is_empty(), "with nothing to do the block is empty")
	# The weapon readout, bottom right: dim at rest, lit when it matters.
	var gun := p.get_active_weapon() as Gun
	if gun != null:
		gun.ammo_in_mag = gun.mag_size
		for i in 240:
			glass._process(1.0 / 60.0)
		t.check(not glass.weapon_awake(gun) and glass.weapon_lit < 0.05,
				"with a full mag and no switch, the weapon readout rests dim (ammo is read off the gun)")
		gun.ammo_in_mag = 1
		for i in 30:
			glass._process(1.0 / 60.0)
		t.check(glass.weapon_awake(gun) and glass.weapon_lit > 0.9, "a low mag lights it up")
		gun.ammo_in_mag = gun.mag_size
		gun.ammo_in_mag -= 5
		gun.start_reload()
		t.check(gun.is_reloading() and glass.weapon_awake(gun), "so does a reload")
		gun.ammo_in_mag = gun.mag_size


static func _strip(t: Node) -> void:
	print("Visors: the heading strip, squad and roles")
	t.check(VisorHud.role_name("zoom") == "RECON" and VisorHud.role_name("scan") == "INTEL"
			and VisorHud.role_name("threat") == "TACTICAL" and VisorHud.role_name("thermal") == "THERMAL"
			and VisorHud.role_name("") == "SCRAP", "every helmet has a role it shows as it comes on")
	t.check(VisorHud.signature_text(0.5) == "SIG LOW" and VisorHud.signature_text(0.75) == "SIG MED"
			and VisorHud.signature_text(1.6) == "SIG HIGH", "an Ember reads how warm its wearer looks")
	var none: Array[Dictionary] = []
	t.check(VisorHud.tracker_text(none, {}) == "", "with no contract held the tracker is blank")

	var raid: Raid = await t._kit_raid(345, _kit("helm_warden"))
	var p := raid.player
	var glass := VisorHud.new()
	glass.setup(raid, null)
	raid.add_child(glass)
	await t.frames(2)
	var kinds := func() -> Array:
		return glass.compass_marks(p).map(func(m: Dictionary) -> String: return m.kind)
	t.check(raid.depots.is_empty() or "depot" in kinds.call(), "every working visor marks the nearest depot")
	raid.war.intensity = 0.0
	t.check(not "hot" in kinds.call(), "a quiet war has no hot zone on the strip")
	raid.war.intensity = 0.8
	t.check("hot" in kinds.call(), "a tactical visor marks where the war is hottest")
	# Another player in the world: a squadmate only when they share a clan.
	var other: Actor = raid.bots[0]
	t.check(not VisorHud.squadmate(raid, p, other), "a bot is never on the squad")
	var state := Raid.PlayerState.new()
	state.actor = other
	raid.players.append(state)
	p.clan = "wolves"
	other.clan = "ravens"
	t.check(not VisorHud.squadmate(raid, p, other), "a player of another clan is never marked")
	other.clan = "wolves"
	t.check(VisorHud.squadmate(raid, p, other), "a clanmate is on the squad")
	glass._process(0.016)
	t.check(other in glass.squad and "squad" in kinds.call(), "and the strip marks where they are")
	other.health.health = 0.0
	other.is_dead = true
	t.check(not VisorHud.squadmate(raid, p, other), "a fallen squadmate leaves the strip")
	other.is_dead = false
	raid.players.erase(state)
	p.clan = ""
	glass._process(0.016)
	t.check(glass.squad.is_empty(), "alone, there is no squad to mark")
	raid.pinged.emit(p, p.global_position + Vector3(10, 0, 0))
	t.check("ping" in kinds.call(), "your own ping is marked on the strip")
	for i in 3:
		glass._process(raid.ping_time * 0.5)
	t.check(not "ping" in kinds.call(), "and goes when the ping does")
	await _layout(t, raid, glass)
	glass.queue_free()
	await t._end_raid(raid)

	raid = await t._kit_raid(346, _kit("visor_scav"))
	glass = VisorHud.new()
	glass.setup(raid, null)
	raid.add_child(glass)
	await t.frames(2)
	t.check(glass.compass_marks(raid.player).is_empty(), "a scrap visor marks nothing, only a bearing")
	glass.queue_free()
	await t._end_raid(raid)
