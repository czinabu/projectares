extends RefCounted
## Checks for the Concourse's life (DESIGN.md section 2, "Locals" and the
## most-wanted board): the locals' routines and how they are kept out of the
## world, the people you talk to, Rook's daily favour, the most-wanted list a
## world tells the plaza, the board that shows it, and the bounty paid in
## scrip. Called from the test runner (`-- --groups PlazaLifeTests`).

const Contracts := preload("res://core/economy/contracts.gd")
const ContractPanel := preload("res://core/economy/contract_panel.gd")
const Economy := preload("res://core/economy/economy.gd")
const PlazaMap := preload("res://worlds/plaza/map.gd")
const PlazaLocals := preload("res://core/social/plaza_locals.gd")
const PlazaView := preload("res://core/social/plaza_view.gd")
const RaidRoster := preload("res://core/ui/raid_roster.gd")
const DAY := 20404


static func run(t: Node) -> void:
	print("Plaza life")
	_favours(t)
	_wanted_text(t)
	await _bounty_and_wanted(t)
	await _crowd(t)


## Rook's favour: one a day, the same for everyone, never rerolled, held and
## paid like any job, and left off the board's own lists.
static func _favours(t: Node) -> void:
	var favor := Contracts.favor_for(DAY)
	t.check(favor != "" and Contracts.job(favor).kind == "favor" and Contracts.favor_for(DAY) == favor,
			"Rook has one favour a day, the same all day (%s)" % favor)
	var offers := Contracts.offers_for(DAY)
	t.check(offers.count(favor) == 1, "the day's favour is among the offers, so it can be taken")
	var changes := false
	for day in range(DAY, DAY + 10):
		changes = changes or Contracts.favor_for(day) != favor
	t.check(changes, "the favour changes from day to day")
	for id: String in Contracts.ids("favor"):
		var job := Contracts.job(id)
		t.check(str(job.get("ask", "")) != "" and int(job.scrip) > 0 and int(job.scrip) < 150
				and not str(job.stat).contains("player"),
				"%s is asked in Rook's words and pays a little under a daily" % id)
	var state := Contracts.clean({}, DAY)
	Contracts.reroll(state, DAY)
	t.check(favor in state.offers, "a reroll keeps the favour on offer")
	t.check(Contracts.take(state, favor, DAY).ok and Contracts.held(state).size() == 1, "taking the favour holds it")
	Contracts.refresh(state, DAY + 1)
	t.check(Contracts.held(state).is_empty(), "a favour ends with its day")
	var lines := PlazaMap.contract_lines()
	t.check(not lines.any(func(line: String) -> bool: return line.begins_with("FAVOR")),
			"the board's wall leaves the favour to Rook")
	var rows := ContractPanel.rows(Contracts.clean({}, Contracts.today()))
	var offered := rows.filter(func(row: Dictionary) -> bool: return row.action == "take")
	t.check(not offered.any(func(row: Dictionary) -> bool: return Contracts.job(row.id).kind == "favor"),
			"the board's screen does not offer it either")
	# What Rook says, from the account's contracts.
	var account := {"contracts": Contracts.clean({}, DAY)}
	var offer := PlazaLocals.rook_line(account, DAY)
	t.check(offer.job == favor and str(offer.text).contains(str(Contracts.job(favor).ask)),
			"Rook asks today's favour in his own words")
	Contracts.take(account.contracts, favor, DAY)
	var held := PlazaLocals.rook_line(account, DAY)
	t.check(held.job == "" and str(held.text).begins_with("You're on it"), "once taken he says you're on it")
	(account.contracts.done as Array).append(favor)
	account.contracts.active = []
	t.check(PlazaLocals.rook_line(account, DAY).job == "", "once done he has nothing more that day")
	t.check(PlazaLocals.rook_line({}, DAY).job == "", "with no account he offers nothing")


## The board's text: the biggest bounties across the worlds, the Marked, and
## never anything about where anyone is.
static func _wanted_text(t: Node) -> void:
	t.check(PlazaView.wanted_text({}).begins_with("No bounties out right now"), "an empty board says so")
	var status := {
		"ashfront": {"players": 4, "wanted": [{"name": "Vex", "clan": "", "bounty": 150, "marked": false},
				{"name": "Juno", "clan": "IRON", "bounty": 300, "marked": true}]},
		"frostline": {"players": 1, "wanted": []},
	}
	var text := PlazaView.wanted_text(status)
	var lines := text.split("\n")
	t.check(lines[0].begins_with("1   [IRON] JUNO   300 scrip") and lines[0].ends_with("THE MARKED")
			and lines[1].begins_with("2   VEX   150 scrip"), "the board lists the biggest bounty first (%s)" % text)
	t.check(lines[0].contains("ASHFRONT"), "each line names the world")
	var kade := PlazaLocals.kade_lines(status)
	t.check(kade[0].begins_with("Juno is worth 300"), "Kade names the top bounty")
	var heard := PlazaLocals.rumours({"ashfront": {"players": 6, "war": 0.8, "level": "All-out war", "bounty": 300,
			"event": "Supply pod"}})
	t.check(heard.any(func(line: String) -> bool: return line.contains("supply pod"))
			and heard.any(func(line: String) -> bool: return line.contains("burning"))
			and heard.any(func(line: String) -> bool: return line.contains("300 bounty")),
			"Dusk's rumours come from the worlds' real news")
	t.check(PlazaLocals.rumours({}).size() >= 3, "and she always has something to say")
	# The session script by path, so this group stays offline (it starts no server).
	var session_script: Script = load("res://core/net/net_session.gd")
	var junk: Array = session_script.call("_clean_wanted", [{"name": "x".repeat(80), "bounty": -5, "marked": "yes"}, "junk", {"name": ""},
			{"name": "a"}, {"name": "b"}, {"name": "c"}, {"name": "d"}, {"name": "e"}])
	t.check(junk.size() == Raid.WANTED_SHOWN and junk[0].name.length() == 24 and junk[0].bounty == 0,
			"a client checks the wanted list it is sent")


## A world tells the plaza who is wanted, and killing one pays the bounty
## into the killer's carried scrip.
static func _bounty_and_wanted(t: Node) -> void:
	var raid := Raid.new()
	t.add_child(raid)
	raid.apply_to_profile = false
	raid.start_server(Worlds.get_world("ashfront"), 91)
	raid.war.scale = 0.0
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
	var kit: Array[String] = ["rifle_carbine", "frame_trooper"]
	var hunter := raid.add_player(kit, {}, "Hunter", "acct-hunter", 0)
	await t.frames(2)
	t.check(raid.wanted().is_empty() and raid.status().wanted.is_empty(), "nobody is wanted at first")
	for i in 3:
		var prey := raid.add_player(kit, {}, "Prey", "acct-prey", 0)
		await t.frames(1)
		prey.kill("bullet", hunter)
		await t.frames(1)
	var wanted := raid.status().wanted as Array
	t.check(wanted.size() == 1 and wanted[0].name == "Hunter" and wanted[0].bounty == hunter.bounty
			and hunter.bounty > 0, "a player with a bounty is on the world's wanted list (%s)" % [wanted])
	t.check(not wanted[0].has("position") and wanted[0].keys().size() == 4, "it says who, never where")
	var avenger := raid.add_player(kit, {}, "Avenger", "acct-avenger", 0)
	await t.frames(1)
	var before := avenger.scrip
	var bounty := hunter.bounty
	hunter.kill("bullet", avenger)
	await t.frames(2)
	t.check(avenger.scrip - before == Economy.PLAYER_KILL_SCRIP + Economy.bounty_scrip(bounty),
			"the bounty goes into the killer's carried scrip (%d)" % (avenger.scrip - before))
	t.check(not raid.wanted().any(func(w: Dictionary) -> bool: return w.name == "Hunter"),
			"and the name comes off the list")
	raid.queue_free()
	var plaza := Raid.new()
	t.add_child(plaza)
	plaza.start_server(Worlds.social_world(), 5)
	var guest := plaza.add_player(kit, {}, "Guest", "acct-guest", 0)
	guest.bounty = 500
	t.check(plaza.wanted().is_empty(), "a safe zone never lists anyone")
	plaza.queue_free()
	await t.frames(2)


## The crowd: made the same from the seed, scattered rather than spaced
## evenly, on open floor, out of the world, and the talkers answer.
static func _crowd(t: Node) -> void:
	var raid := Raid.new()
	t.add_child(raid)
	raid.start_server(Worlds.social_world(), 5)
	var layout: Dictionary = raid.map.call("locals_layout")
	var counts := {"strollers": 6, "shoppers": 5, "watchers": 7, "chats": 2, "wanderers": 3}
	var a := RandomNumberGenerator.new()
	a.seed = PlazaLocals.CROWD_SEED
	var b := RandomNumberGenerator.new()
	b.seed = PlazaLocals.CROWD_SEED
	var plan_a := PlazaLocals.plan_crowd(layout, a, counts)
	var plan_b := PlazaLocals.plan_crowd(layout, b, counts)
	var same := plan_a.size() == plan_b.size()
	for i in mini(plan_a.size(), plan_b.size()):
		same = same and plan_a[i].routine.sample(1000.0 + plan_a[i].offset).pos.is_equal_approx(
				plan_b[i].routine.sample(1000.0 + plan_b[i].offset).pos)
	t.check(same and plan_a.size() >= 20, "every client makes the same crowd (%d locals)" % plan_a.size())
	# Scattered: the gaps to each local's nearest neighbour are all different.
	var spots: Array[Vector3] = []
	for entry in plan_a:
		spots.append(entry.routine.sample(5000.0 + entry.offset).pos)
	var gaps: Array[float] = []
	var too_close := 0
	for i in spots.size():
		var nearest := INF
		for j in spots.size():
			if i != j and plan_a[i].routine != plan_a[j].routine:
				nearest = minf(nearest, spots[i].distance_to(spots[j]))
		if nearest < 0.5:
			too_close += 1
		gaps.append(snappedf(nearest, 0.1))
	var distinct := {}
	for gap in gaps:
		distinct[gap] = true
	t.check(distinct.size() > gaps.size() / 2 and too_close <= 2,
			"the crowd is scattered, not spaced evenly (%d distinct gaps of %d)" % [distinct.size(), gaps.size()])
	# Every point a routine passes is open floor.
	var space := raid.get_world_3d().direct_space_state
	var shape := CapsuleShape3D.new()
	shape.radius = 0.3
	shape.height = 1.4
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = Actor.LAYER_WORLD
	await t.frames(2)
	var blocked: Array[String] = []
	for entry in plan_a:
		var routine: PlazaLocals.Routine = entry.routine
		var at := 0.0
		while at < routine.length and blocked.size() < 5:
			var pos: Vector3 = routine.sample(at).pos
			query.transform = Transform3D(Basis.IDENTITY, pos + Vector3(0, 1.0, 0))
			if not space.intersect_shape(query, 1).is_empty():
				blocked.append("%s" % [pos.snapped(Vector3.ONE * 0.1)])
			at += 0.8
	t.check(blocked.is_empty(), "the locals' routines keep to open floor %s" % [blocked])
	# The people you talk to have their spots, each with a way to talk.
	var talkers := raid.get_tree().get_nodes_in_group("talker").filter(func(n: Node) -> bool:
		return raid.map.is_ancestor_of(n))
	var talk_portals := raid.get_tree().get_nodes_in_group("portal").filter(func(n: Node) -> bool:
		return raid.map.is_ancestor_of(n) and str(n.get_meta("destination", "")).begins_with("talk:"))
	t.check(talkers.size() == 3 and talk_portals.size() == 3, "Kade, Dusk and Rook have their spots")
	t.check(raid.get_tree().get_nodes_in_group("wanted_board").size() == 1, "the most-wanted board stands in the plaza")

	# The view itself, as a client would make it.
	var guest := raid.add_player([Loadout.BARE], {}, "Guest", "acct-guest", 0)
	var locals := PlazaLocals.new()
	locals.clock_override = 1000.0
	locals.setup(raid)
	raid.add_child(locals)
	await t.frames(3)
	t.check(locals.locals.size() == plan_a.size() + 3, "the view stands up the crowd and the talkers")
	var outside := true
	for entry in locals.locals:
		var actor: Actor = entry.actor
		outside = outside and not actor.is_in_group("actors") and actor.collision_layer == 0 \
				and actor.weapons_locked
	t.check(outside, "locals are out of the world: no actor group, no collision, weapons locked")
	t.check(not RaidRoster.players_in(raid).any(func(p: Actor) -> bool: return p.display_name == "Local"),
			"the roster never lists a local")
	t.check(not locals.locals.any(func(e: Dictionary) -> bool: return (e.actor as Actor).is_in_group("actors")),
			"nothing that scans for actors sees them")
	# They keep to their routines.
	var walker: Dictionary = locals.locals.filter(func(e: Dictionary) -> bool:
		return (e.routine as PlazaLocals.Routine).legs.any(func(l: Dictionary) -> bool: return l.walking))[0]
	for i in 90:
		locals.clock_override += 1.0 / 60.0
		await t.frames(1)
	var want: Vector3 = (walker.routine as PlazaLocals.Routine).sample(locals.clock_override + walker.offset).pos
	t.check(Vector2(want.x, want.z).distance_to(Vector2((walker.actor as Actor).global_position.x,
			(walker.actor as Actor).global_position.z)) < 3.0, "a local walks where their routine says")
	# Someone in their way is stepped round, and looked at.
	var kade: Dictionary = locals.talkers["kade"]
	guest.global_position = (kade.actor as Actor).global_position + Vector3(2.0, 0, 0)
	guest.velocity = Vector3.ZERO
	for i in 40:
		await t.frames(1)
	var to_guest := guest.global_position - (kade.actor as Actor).global_position
	var facing := Basis(Vector3.UP, (kade.actor as Actor).cmd.yaw) * Vector3.FORWARD
	t.check(facing.angle_to(Vector3(to_guest.x, 0, to_guest.z)) < 0.5, "a talker turns to face someone close by")
	# Talking.
	var status := {"ashfront": {"players": 2, "war": 0.2, "level": "Skirmish", "bounty": 150, "event": "",
			"wanted": [{"name": "Vex", "clan": "", "bounty": 150, "marked": false}]}}
	t.check(locals.talk("kade", status, {}) == "" and locals.speaking == "kade", "Kade answers")
	var account := {"contracts": Contracts.clean({}, Contracts.today())}
	t.check(locals.talk("rook", status, account) == "" and locals.speaking == "rook" and locals.offered_job != "",
			"Rook offers his favour")
	var favor := locals.offered_job
	t.check(locals.talk("rook", status, account) == favor, "talking to him again takes it")
	locals.hush()
	t.check(locals.speaking == "", "a line can be taken down")
	raid.queue_free()
	await t.frames(2)
