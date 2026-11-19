extends RefCounted
## Checks for the enemy AI pass's foundations: smoke hides people from bots
## as it hides them from eyes (`Smoke`, `Raid.smoke`, a shell's column), a
## world can give a kind its own senses (metas "sight", "fov", "reach",
## "far_notice" read by `BotBrain`), and Frostline's factions build for the
## duel bench. Kept in its own file and called from the test runner.

const KIT: Array[String] = ["rifle_scrap", "blade_scrap"]
const Strongpoint := preload("res://core/war/strongpoint.gd")


static func run(t: Node) -> void:
	_smoke_shape(t)
	await _smoke_hides(t)
	_pincer_and_break(t)
	await _doctrines(t)
	await _grudges(t)
	await _battles_by_ground(t)


static func _smoke_shape(t: Node) -> void:
	print("Enemy AI: smoke")
	var smoke := Smoke.new()
	smoke.add(Vector3.ZERO, 6.0, 14.0, 13.0)
	smoke.tick(3.0)
	t.check(smoke.blocks(Vector3(-20, 1.6, 0), Vector3(20, 1.4, 0)), "a line through a cloud is hidden")
	t.check(not smoke.blocks(Vector3(-20, 1.6, 15), Vector3(20, 1.4, 15)), "a line beside it is not")
	t.check(not smoke.blocks(Vector3(-20, 30, 0), Vector3(20, 30, 0)), "nor one over its top")
	t.check(not smoke.blocks(Vector3(-2, 1.6, 0), Vector3(2, 1.4, 0)),
			"two people inside one, close up, still make each other out")
	smoke.tick(11.0)
	t.check(smoke.clouds.is_empty() and not smoke.blocks(Vector3(-20, 1.6, 0), Vector3(20, 1.4, 0)),
			"and once it has blown away, nothing is hidden")
	t.check(is_equal_approx(Smoke.segment_gap(Vector3(0, 0, 0), Vector3(10, 0, 0), Vector3(5, -1, 3), Vector3(5, 1, 3)), 3.0),
			"the gap between two lines is measured right")


static func _smoke_hides(t: Node) -> void:
	var raid := Raid.new()
	t.add_child(raid)
	raid.start_server(Worlds.get_world("ashfront"), 71)
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
		bot.set_physics_process(false)
		bot.global_position = Vector3(600, 0, 600)
	var me := raid.add_player(KIT, {}, "Walker", "walker")
	await t.frames(3)
	var spot := raid._stand(Vector3(-150, 0, 40))
	me.global_position = spot
	me.protected_left = 0.0
	# Open ground with nothing between: try a few bearings until the line is clear.
	var space := me.get_world_3d().direct_space_state
	var chest := me.global_position + Vector3(0, me.body_height() * 0.6, 0)
	var from := Vector3.ZERO
	for i in 16:
		var at := raid._stand(spot + Vector3(sin(i * TAU / 16.0), 0, cos(i * TAU / 16.0)) * 22.0)
		var q := PhysicsRayQueryParameters3D.create(at + Vector3(0, 1.6, 0), chest, Actor.LAYER_WORLD)
		if space.intersect_ray(q).is_empty():
			from = at
			break
	var bot := raid.spawn_bot("Looker", from, 5, false, "legion", 1)
	var brain := BotBrain.new()
	brain.name = "Brain"
	brain.seed_value = 5
	bot.add_child(brain)
	brain.set_physics_process(false)
	var to := me.global_position - bot.global_position
	bot.cmd.yaw = atan2(-to.x, -to.z)
	await t.frames(2)
	t.check(brain._find_target() == me, "a bot sees a player in the open")
	raid.shelling.land(raid, (spot + from) * 0.5)
	t.check(raid.smoke.clouds.size() == 1, "a shell that lands leaves a column of smoke")
	t.check(brain._find_target() == null, "and the bot cannot see the player through it")
	raid.smoke.clear()
	t.check(brain._find_target() == me, "once it clears, it can again")
	# Senses a world gives a kind.
	var eyed := raid.spawn_bot("Eyed", raid._stand(spot + Vector3(30, 0, 0)), 6, false, "legion", 1)
	eyed.set_meta("sight", 72.0)
	eyed.set_meta("fov", 90.0)
	eyed.set_meta("reach", 60.0)
	eyed.set_meta("far_notice", 2.2)
	var sharp := BotBrain.new()
	sharp.name = "Brain"
	eyed.add_child(sharp)
	t.check(sharp.sight_range == 72.0 and sharp.fov_deg == 90.0 and sharp.attack_range == 60.0
			and sharp.far_notice_mult == 2.2, "a world can give a kind its own senses")
	var plain := raid.spawn_bot("Plain", raid._stand(spot + Vector3(-30, 0, 0)), 7, false, "legion", 1)
	for key in ["sight", "fov", "reach", "far_notice", "range"]:
		plain.remove_meta(key)
	var usual := BotBrain.new()
	usual.name = "Brain"
	plain.add_child(usual)
	t.check(usual.sight_range == 38.0 and usual.preferred_range == 14.0,
			"and a kind it gives none keeps the usual")
	raid.queue_free()
	await t.frames(2)
	# Frostline's factions build from their markers, for the duel bench.
	var frost := Raid.new()
	t.add_child(frost)
	frost.start_server(Worlds.get_world("frostline"), 72)
	for b in frost.bots:
		b.get_node("Brain").set_physics_process(false)
		b.set_physics_process(false)
		b.global_position = Vector3(0, -500, 0)
	var warden := frost.spawn_bot("W", Vector3(0, 40, 0), 3, false, "warden", 2)
	var feral := frost.spawn_bot("F", Vector3(5, 40, 0), 4, false, "feral", 2)
	t.check(warden.faction == "warden" and warden.get_active_weapon() is Gun, "a Warden marker builds a Warden")
	t.check(feral.faction == "feral" and feral.get_active_weapon() is MeleeWeapon, "a Feral den builds a Feral")
	print("Enemy AI: Frostline's enemies")
	t.check(float(warden.get_meta("sight")) > 38.0 and float(warden.get_meta("lock_time")) > 0.0,
			"a Warden sees far and holds a beam before it fires")
	var mouth := frost.spawn_bot("W0", Vector3(0, 40, 0), 3, false, "warden", 0)
	t.check(warden.health.max_health > mouth.health.max_health, "and is tougher at the glacier head than at the mouth")
	t.check(feral.has_meta("tracker") and feral.has_meta("shuns_warmth"), "a Feral hunts by tracks and keeps out of the warm")
	var ws := Worlds.get_world("frostline")
	t.check(ws.bot_count >= 18, "the valley holds packs, not a handful of bots")
	# A Feral keeps out of the warm: nobody in a heater's ring is its target.
	var heat: Node3D = null
	for source in frost.warmth:
		if not frost.waits_on_keeper(source) and source.global_position.y > -50.0:
			heat = source
			break
	var hiker := frost.add_player(KIT, {}, "Hiker", "hiker")
	await t.frames(3)
	hiker.protected_left = 0.0
	var ring := float(heat.get_meta("radius", 4.0))
	hiker.global_position = heat.global_position + Vector3(ring * 0.4, 0.2, 0)
	var stalker := frost.spawn_bot("S", heat.global_position + Vector3(ring + 6.0, 0.6, 0), 9, false, "feral", 1)
	var hunter := BotBrain.new()
	hunter.name = "Brain"
	hunter.seed_value = 9
	stalker.add_child(hunter)
	hunter.set_physics_process(false)
	var toward := hiker.global_position - stalker.global_position
	stalker.cmd.yaw = atan2(-toward.x, -toward.z)
	await t.frames(2)
	t.check(BotBrain.in_warmth(frost, hiker.global_position) and hunter._find_target() == null,
			"a Feral will not go for someone standing in a heater's warmth")
	t.check(hunter._outside_warmth(heat.global_position).distance_to(heat.global_position) > ring,
			"and steps round the ring rather than into it")
	# A Feral follows fresh tracks to where someone went.
	hiker.global_position = stalker.global_position + Vector3(0, 0, 40)
	var mark_at := stalker.global_position + Vector3(0, 0, 12)
	frost.tracks.add(mark_at, 0.0, Tracks.Kind.LEFT, frost.clock)
	hunter._sniff(5.0)
	t.check(hunter.state == BotBrain.State.CHASE and hunter._last_seen.distance_to(mark_at) < 1.0,
			"a Feral that finds fresh tracks follows them to the mark, not to the person")
	frost.queue_free()
	await t.frames(2)


static func _pincer_and_break(t: Node) -> void:
	print("Enemy AI: Ashfront's doctrines")
	SquadBoard.clear()
	var who := 4242
	t.check(SquadBoard.flank(who, 1, 0, 4.0, 2) and SquadBoard.flank(who, 2, 0, 4.0, 2)
			and not SquadBoard.flank(who, 3, 0, 4.0, 2), "a pincer takes two flankers, and only two")
	t.check(SquadBoard.flank_side(who, 1) == -SquadBoard.flank_side(who, 2) and SquadBoard.flank_side(who, 3) == 0,
			"and they come round opposite sides")
	SquadBoard.clear()
	var brain := BotBrain.new()
	brain.breaks_at = 0.33
	brain.set_team(7, 3)
	brain.ally_down()
	t.check(brain.is_broken(), "a team of three that loses one breaks off")
	var steady := BotBrain.new()
	steady.set_team(7, 3)
	steady.ally_down()
	steady.ally_down()
	t.check(not steady.is_broken(), "a team with no breaking point fights on")
	var big := BotBrain.new()
	big.breaks_at = 0.33
	big.set_team(9, 6)
	big.ally_down()
	t.check(not big.is_broken(), "a team of six shrugs off one loss")
	big.set_team(10, 6)
	big.ally_down()
	t.check(not big.is_broken(), "and a new team counts afresh")
	brain.free()
	steady.free()
	big.free()


static func _doctrines(t: Node) -> void:
	var raid := Raid.new()
	t.add_child(raid)
	raid.start_server(Worlds.get_world("ashfront"), 73)
	var kinds := {}
	var legion_range := true
	var tide_close := true
	for i in 400:
		var faction := "legion" if i % 2 == 0 else "tide"
		var bot := raid.spawn_bot("K%d" % i, Vector3(0, -400, 0), 1000 + i, false, faction, 1 + i % 2)
		var kind := str(bot.get_meta("kind", ""))
		kinds["%s:%s" % [faction, kind]] = bot
		if kind == "soldier":
			if faction == "legion":
				legion_range = legion_range and float(bot.get_meta("range")) >= 30.0
			else:
				tide_close = tide_close and float(bot.get_meta("range")) <= 12.0 \
						and int(bot.get_meta("flankers")) == 2 and float(bot.get_meta("breaks_at")) > 0.0
	t.check(legion_range, "Legion riflemen hold their distance")
	t.check(tide_close, "Tide riflemen close in, pincer and break")
	var marksman: Actor = kinds.get("legion:marksman")
	t.check(marksman != null and not kinds.has("tide:marksman"), "the Legion fields marksmen, the Tide none")
	if marksman:
		var rifle := marksman.get_active_weapon() as Gun
		t.check(rifle != null and rifle.damage > 40.0 and float(marksman.get_meta("sight")) > 60.0,
				"a marksman sees far and hits hard")
	var runner: Actor = kinds.get("tide:runner")
	t.check(runner != null and not kinds.has("legion:runner"), "the Tide fields runners, the Legion none")
	if runner:
		t.check(runner.get_active_weapon() is MeleeWeapon and runner.sprint_speed > 9.0
				and runner.health.max_health < 200.0, "a runner is quick, lighter than a heavy and carries a knife")
	# The mix leans each army's way: more exos in the Legion, more blades in the Tide.
	var legion_exo := 0
	var tide_exo := 0
	var legion_blade := 0
	var tide_blade := 0
	for i in 600:
		var faction := "legion" if i % 2 == 0 else "tide"
		var rng := RandomNumberGenerator.new()
		rng.seed = 5000 + i
		var dummy := Actor.new()
		dummy.faction = faction
		dummy.set_meta("zone", 2)
		raid.world.equip_bot(dummy, rng)
		var kind := str(dummy.get_meta("kind"))
		if kind == "exo":
			if faction == "legion":
				legion_exo += 1
			else:
				tide_exo += 1
		if kind in ["heavy", "runner"]:
			if faction == "legion":
				legion_blade += 1
			else:
				tide_blade += 1
		dummy.free()
	t.check(legion_exo > tide_exo and tide_blade > legion_blade * 2,
			"the Legion brings more exos, the Tide more blades (%d/%d exos, %d/%d blades)"
			% [legion_exo, tide_exo, legion_blade, tide_blade])
	raid.queue_free()
	await t.frames(2)


static func _grudges(t: Node) -> void:
	print("Enemy AI: grudges")
	var raid := Raid.new()
	t.add_child(raid)
	raid.start_server(Worlds.get_world("ashfront"), 74)
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
		bot.set_physics_process(false)
		bot.global_position = Vector3(600, 0, 600)
	var me := raid.add_player(KIT, {}, "Grudger", "grudger")
	await t.frames(3)
	me.protected_left = 0.0
	var spot := raid._stand(Vector3(-150, 0, 40))
	me.global_position = spot
	var victim := raid.spawn_bot("Victim", raid._stand(spot + Vector3(10, 0, 0)), 11, false, "legion", 1)
	# Wired as the map's own soldiers are (`Raid._add_bot`).
	victim.health.damaged.connect(raid._on_army_hurt.bind(victim))
	victim.died.connect(raid._on_actor_died)
	Combat.deal(victim, DamageInfo.make(40.0, me, "bullet"))
	var held: Dictionary = raid.grudges.get(me, {})
	t.check(is_equal_approx(float(held.get("legion", 0.0)), 40.0) and not held.has("tide"),
			"hurting the Legion raises its grudge, not the Tide's")
	Combat.deal(victim, DamageInfo.make(9999.0, me, "bullet"))
	held = raid.grudges.get(me, {})
	t.check(float(held.get("legion", 0.0)) >= 40.0 + raid.world.grudge_per_kill,
			"and a kill raises it more")
	var before := float(held.get("legion", 0.0))
	raid._tick_grudges(1.0)
	t.check(is_equal_approx(float(raid.grudges[me]["legion"]), before - raid.world.grudge_fade) and me.hunted_by == "",
			"it fades, and a small grudge sends nobody")
	# Over the line, the army sends a couple of its own after the player.
	var hunter := raid.spawn_bot("Hunter", raid._stand(spot + Vector3(0, 0, 40)), 12, false, "legion", 1)
	var brain := BotBrain.new()
	brain.name = "Brain"
	brain.seed_value = 12
	hunter.add_child(brain)
	brain.set_physics_process(false)
	brain.post_to(hunter.global_position, 10.0)
	var bystander := raid.spawn_bot("Bystander", raid._stand(spot + Vector3(0, 0, -40)), 13, false, "tide", 1)
	var calm := BotBrain.new()
	calm.name = "Brain"
	bystander.add_child(calm)
	calm.set_physics_process(false)
	await t.frames(2)
	raid.grudges[me]["legion"] = raid.world.grudge_hunt + 100.0
	raid._grudge_in = 0.0
	raid._tick_grudges(0.1)
	t.check(me.hunted_by == "legion", "an army over its line hunts the player")
	t.check(brain.state == BotBrain.State.CHASE and brain._last_seen.distance_to(me.global_position) < 8.0,
			"and sends its nearest after where they roughly are")
	t.check(calm.state != BotBrain.State.CHASE, "while the other army takes no notice")
	t.check(VisorHud.hunted_text(me) == "THE LEGION IS HUNTING YOU", "the visor says who is after you")
	Combat.deal(me, DamageInfo.make(99999.0, hunter, "bullet"))
	t.check(not raid.grudges.has(me) and me.hunted_by == "", "and death clears the grudge")
	raid.queue_free()
	await t.frames(2)


static func _battles_by_ground(t: Node) -> void:
	print("Enemy AI: battles by ground")
	# A style is laid over the bot's own numbers, never over the last style.
	var lone := Actor.new()
	t.add_child(lone)
	var brain := BotBrain.new()
	brain.name = "Brain"
	lone.add_child(brain)
	brain.set_physics_process(false)
	await t.frames(1)
	var own := Vector3(brain.preferred_range, brain.max_hunters, brain.leash)
	brain.set_ground("line", {"range": 1.4, "leash": 8.0, "hunters": -2})
	t.check(is_equal_approx(brain.preferred_range, own.x * 1.4) and brain.leash == 8.0
			and brain.max_hunters == maxi(0, int(own.y) - 2), "a trench line keeps its distance and its post")
	brain.set_ground("works", {"range": 0.55, "notice": 0.85})
	t.check(is_equal_approx(brain.preferred_range, own.x * 0.55) and brain.leash == own.z
			and brain.max_hunters == int(own.y) and brain.ground_notice == 0.85,
			"and the next ground starts from the bot's own numbers")
	var wide := brain.patrol_radius
	brain.post_to(Vector3.ZERO, 3.0)
	brain.post_to(Vector3.ZERO, 200.0)
	t.check(brain.patrol_radius == wide, "a tight post does not keep the next one tight")
	lone.queue_free()
	# Ashfront names its ground.
	var world := Worlds.get_world("ashfront")
	var named := {
		"works": Vector3(0, 0, 150), "foundry": Vector3(5, 0, 5), "landmark": Vector3(-150, 0, -118),
		"front": Vector3(-20, 0, -76), "rim": Vector3(250, 0, 250), "field": Vector3(-60, 0, 0),
	}
	var all_named := true
	for kind: String in named:
		if world.ground_at(named[kind]) != kind:
			all_named = false
			print("  ground at %s is %s, not %s" % [named[kind], world.ground_at(named[kind]), kind])
	t.check(all_named, "Ashfront tells the Works, the Foundry, landmarks, the front, the rim and the field apart")
	var raid := Raid.new()
	t.add_child(raid)
	raid.start_server(world, 75)
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
		bot.set_physics_process(false)
	await t.frames(2)
	var sides := {}
	for post: Node3D in raid.line_posts:
		sides[str(post.get_meta("faction", ""))] = int(sides.get(str(post.get_meta("faction", "")), 0)) + 1
	t.check(int(sides.get("legion", 0)) >= 6 and int(sides.get("tide", 0)) >= 6 and sides.size() == 2,
			"both armies have line posts in the front's trenches")
	var legion: Array = raid.bots.filter(func(b: Actor) -> bool: return b.faction == "legion" and not raid._is_extra(b))
	var on_line := {}
	raid._man_lines("legion", legion, on_line)
	var manned := raid._line_of.duplicate()
	var own_posts := true
	for bot: Actor in on_line:
		own_posts = own_posts and str(raid._line_of[bot].get_meta("faction")) == "legion"
	t.check(on_line.size() == roundi(legion.size() * world.line_share) and own_posts,
			"a share of the army mans its own line posts")
	on_line.clear()
	raid._man_lines("legion", legion, on_line)
	t.check(raid._line_of == manned, "and keeps them from one round to the next")
	# The Foundry waits on the war, and then on the elites.
	var foundry: Strongpoint = null
	for point in raid.strongpoints:
		if point.hot_at > 0.0:
			foundry = point
	t.check(foundry != null, "the Foundry waits on a hot war")
	var army: Array = legion.slice(0, 15)
	for i in army.size():
		(army[i] as Actor).set_meta("kind", "exo" if i < 5 else "soldier")
		(army[i] as Actor).global_position = raid._stand(Vector3(-60 + i, 0, 10))
	var teams := {}
	var cold := raid.commander.plan("legion", army, raid.strongpoints, {}, [], 0, teams, 1, 0.1, world.elite_kinds)
	t.check(not cold.values().has(foundry), "nobody is sent at it while the war is cool")
	teams.clear()
	var hot := raid.commander.plan("legion", army, raid.strongpoints, {}, [], 0, teams, 1, 0.9, world.elite_kinds)
	var elites_there := 0
	var others_there := 0
	for bot: Actor in hot:
		if hot[bot] == foundry:
			if str(bot.get_meta("kind")) == "exo":
				elites_there += 1
			else:
				others_there += 1
	t.check(elites_there == 5 and others_there == 0, "and once it runs hot the elites go for it, nobody else")
	# A held site with its holders standing is rung before it is stormed.
	var held: Strongpoint = raid.strongpoints[1]
	held.hold("faction:tide", "the Tide", false)
	t.check(raid._besieging("legion", held, {"tide": 3}) and not raid._besieging("legion", held, {"tide": 1})
			and not raid._besieging("tide", held, {"legion": 3}), "a held, manned site is besieged")
	var ring := raid._siege_spot(held, held.global_position + Vector3(100, 0, 0), 0, 1)
	var off := Vector2(ring.x - held.global_position.x, ring.z - held.global_position.z)
	t.check(absf(off.length() - (held.radius + world.siege_reach)) < 0.5 and off.x > 0.0,
			"from a ring past its edge, on the side the team comes from")
	raid.queue_free()
	await t.frames(2)
