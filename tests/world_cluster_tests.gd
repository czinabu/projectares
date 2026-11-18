extends RefCounted
## One program per world (DESIGN.md section 14, "Scaling") and the travel
## between them ("Travel that hides its wait").
##
## First the pieces by themselves: a player who is signed in to two worlds
## at once on the way from one to the next (seats), the clans as a copy a
## game server reads, and a certificate several programs can share.
##
## Then the account service with two game servers' links in this process:
## clans, the phone and the directory of worlds, shared across servers.
##
## Then for real: a cluster (`-- --server --cluster`), every world its own
## program. A game walks into the plaza, connects ahead to a world while it
## still stands there and steps through; a world's program is stopped and
## the others carry on while it is started again.
## Starts servers (a `NetSession` per world), so it runs in the online tier.
## `-- --groups WorldClusterTests` runs just these.

const AccountService := preload("res://core/account/account_service.gd")
const AccountLink := preload("res://core/account/account_link.gd")
const Accounts := preload("res://core/account/stash_service.gd")
const SocialService := preload("res://core/social/social_service.gd")
const ServerTrust := preload("res://core/net/server_trust.gd")

const PORT := 25650          # the in-process service
const CLUSTER_PORT := 25600  # the cluster's plaza; worlds after it, the arena ten above
const CLUSTER_SERVICE := 25690
const KEY := "0123456789abcdef0123456789abcdef"
## DESIGN.md section 14: travel between worlds within about 3 s.
const TRAVEL_TARGET := 3.0


static func run(t: Node) -> void:
	print("One program per world: shared clans, phones and routes, and travel that connects ahead")
	_seats(t)
	_clan_copy(t)
	_shared_certificate(t)
	_prepared_ground(t)
	await _in_process(t)
	await _for_real(t)


static func _dir(tag: String) -> String:
	return "user://test_cluster_%s_%d" % [tag, Time.get_ticks_usec()]


static func _until(t: Node, condition: Callable, seconds := 5.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if condition.call():
			return true
		OS.delay_msec(2)
		await t.frames(1)
	return condition.call()


## A player on the way between two worlds is signed in to both for a moment.
static func _seats(t: Node) -> void:
	var social := SocialService.new()
	social.persist = false
	social.player_online("ana", "Ana", "hub", "plaza")
	social.player_online("ben", "Ben", "hub", "plaza")
	social.player_online("ana", "Ana", "lobby", "ashfront")
	t.check(social.where("ana") == "hub", "signed in ahead to the next world, a player still shows where they are")
	social.set_where("ana", "raid", "ashfront")
	t.check(social.where("ana") == "raid", "and where they went once they are through")
	t.check(not social.player_offline("ana", "plaza") and social.is_online("ana") and social.where("ana") == "raid",
			"leaving the world they came from does not take them offline")
	t.check(social.player_offline("ana", "ashfront") and not social.is_online("ana"),
			"they are offline when their last connection goes")
	social.player_online("ana", "Ana", "raid", "one/ashfront")
	social.player_online("ana", "Ana", "lobby", "two/frostline")
	t.check(social.drop_seats("one/") and social.is_online("ana") and social.where("ana") == "lobby"
			and social.drop_seats("two/") and not social.is_online("ana") and not social.drop_seats("two/"),
			"a game server that goes away takes only its own connections with it")

	# One request runner for a server's own service and the account service.
	social.player_online("ana", "Ana", "hub", "plaza")
	var seated := social.run("online", "cy", ["Cy", "lobby", "plaza"])
	t.check(seated.ok and SocialService.EVERYONE in seated.tell and social.is_online("cy"),
			"signing on is a request like any other, and everyone online hears of it")
	var sent := social.run("message", "ana", ["ben", "over here"])
	t.check(sent.ok and "ana" in sent.tell and "ben" in sent.tell and sent.notices.get("ben", []) == ["Ana: over here"],
			"a message names whose phones changed and what the receiver is shown")
	var asked := social.run("invite", "ana", ["ben", "world", "ashfront"])
	t.check(asked.ok and "Ashfront" in str(asked.notices.get("ben", [""])[0]) and asked.notices.has("ana"),
			"an invite tells both sides (%s)" % str(asked.notices.get("ben", [])))
	var answered := social.run("answer", "ben", [int(asked.invite.id), true])
	t.check(answered.ok and answered.accepted and "accepted" in str(answered.notices.get("ana", [""])[0]),
			"and the answer goes back to whoever asked")
	t.check(not social.run("message", "ana", [7, "x"]).ok and not social.run("nonsense", "ana", []).ok
			and not social.run("message", "", ["ben", "x"]).ok,
			"a request that makes no sense is refused")
	t.check(social.run("contact", "ana", ["add", "ben"]).ok and social.snapshot("ana").contacts.any(
			func(c: Dictionary) -> bool: return c.id == "ben" and c.saved), "contacts go through it too")
	t.check(not social.run("offline", "cy", ["elsewhere"]).tell.has(SocialService.EVERYONE) and social.is_online("cy")
			and SocialService.EVERYONE in social.run("offline", "cy", ["plaza"]).tell,
			"only giving up the last connection tells everyone they left")


static func _clan_copy(t: Node) -> void:
	var clans := ClanService.new()
	clans.persist = false
	clans._opened = true
	var made := clans.ask("create", "ana", "Iron Wake", "iw")
	t.check(made.ok and clans.ask("join", "ben", made.clan).ok and not clans.ask("rename", "ana").ok,
			"a clan request is asked by name")
	var copy := ClanService.new()
	copy.load_state(clans.state())
	t.check(copy.clan_of("ben") == made.clan and copy.tag_of(made.clan) == "IW" and copy.name_of(made.clan) == "Iron Wake"
			and copy.members_of(made.clan).size() == 2 and not copy.persist,
			"a copy of the clans answers who is in which, and saves nothing")
	clans.ask("leave", "ana")
	copy.load_state(clans.state())
	t.check(copy.clan_of("ana") == "" and copy.snapshot("ben", func(id: String) -> String: return id).clan.is_leader,
			"and follows a change")
	copy.load_state({"clans": "nonsense"})
	t.check(copy.clan_of("ben") == "", "a state that makes no sense leaves an empty copy")


## Several programs sharing one folder show one certificate, even when they
## all start at the same moment with none there yet.
static func _shared_certificate(t: Node) -> void:
	var dir := ProjectSettings.globalize_path(_dir("cert")).path_join("server_identity")
	DirAccess.make_dir_recursive_absolute(dir.get_base_dir())
	var first := ServerTrust.pem_of(ServerTrust.identity(dir)[1])
	t.check(first != "" and FileAccess.file_exists(dir.path_join(ServerTrust.CERT_FILE)),
			"a server makes its certificate on its first start")
	# Another program: nothing remembered, the same folder.
	ServerTrust._identities.erase(dir)
	t.check(ServerTrust.pem_of(ServerTrust.identity(dir)[1]) == first, "another program reads the same one")
	# One that made its own at the same moment and lost the race.
	ServerTrust._identities.erase(dir)
	var late := "%s.new-1-1" % dir
	DirAccess.make_dir_recursive_absolute(late)
	t.check(DirAccess.rename_absolute(late, dir) != OK, "a second pair is never moved over the first")
	DirAccess.remove_absolute(late)
	var left := Array(DirAccess.get_directories_at(dir.get_base_dir())).filter(
			func(d: String) -> bool: return ".new-" in d)
	t.check(left.is_empty(), "and nothing is left lying beside it (%s)" % str(left))
	ServerTrust._identities.erase(dir)
	t._wipe_dir(dir.get_base_dir())


## A world's ground can be worked out on another thread before the first visit.
static func _prepared_ground(t: Node) -> void:
	for id: String in ["ashfront", "frostline"]:
		var world := Worlds.get_world(id)
		var script: Script = world.create_map().get_script()
		var store: Dictionary = script.get("_ground_shared")
		var kept := store.duplicate()
		store.clear()
		var task := WorkerThreadPool.add_task(world.prepare_map)
		WorkerThreadPool.wait_for_task_completion(task)
		t.check(store.has("heights") and store.has("collision"), "%s works its ground out off the main thread" % id)
		var ahead: PackedFloat32Array = store.get("heights", PackedFloat32Array())
		store.clear()
		var map := world.create_map()
		t.add_child(map)
		t.check(ahead.size() > 0 and ahead == store.get("heights"), "and it is the very ground a map builds for itself")
		map.queue_free()
		if not kept.is_empty():
			store.clear()
			store.merge(kept)
	Worlds.social_world().prepare_map()
	t.check(true, "a world with nothing to prepare does nothing")


static func _service(t: Node, dir: String) -> AccountService:
	var service := AccountService.new()
	service.stash.save_dir = dir
	service.stash.backup_every = 0.0
	service.key = KEY
	t.add_child(service)
	t.check(service.start(PORT) == OK, "the account service starts")
	return service


static func _link(t: Node, server_id: String) -> AccountLink:
	var link := AccountLink.new()
	link.url = "ws://127.0.0.1:%d" % PORT
	link.key = KEY
	link.server_id = server_id
	link.persist = false
	link.retry_every = 0.2
	t.add_child(link)
	return link


static func _in_process(t: Node) -> void:
	var dir := _dir("inproc")
	var service := _service(t, dir)
	var plaza := _link(t, "plaza")
	var front := _link(t, "ashfront")
	await _until(t, func() -> bool: return plaza.is_up() and front.is_up())
	t.check(plaza.is_up() and front.is_up(), "two game servers connect")
	var ada: String = (await plaza.sign_in_with({"method": "secret", "name": "Ada Vane",
			"secret": Accounts.new_secret()})).get("account_id", "")
	var bo: String = (await front.sign_in_with({"method": "secret", "name": "Bodil",
			"secret": Accounts.new_secret()})).get("account_id", "")
	t.check(ada != "" and bo != "", "a player signs in on each")

	# The directory of worlds.
	plaza.announce({"world": "plaza", "host": "", "port": 4001, "max": 32, "status": {"players": 1}})
	front.announce({"world": "ashfront", "host": "front.example", "port": 4002, "max": 32,
			"status": {"players": 3, "level": "Battle"}})
	await _until(t, func() -> bool: return plaza.worlds.has("ashfront") and front.worlds.has("plaza"), 4.0)
	t.check(plaza.worlds.get("ashfront", {}).get("port", 0) == 4002 and plaza.worlds.ashfront.host == "front.example"
			and int(plaza.worlds.ashfront.status.get("players", 0)) == 3 and front.worlds.has("plaza")
			and not plaza.worlds.ashfront.has("server"),
			"each server hears where the other's world is and how it is doing")
	front.announce({"world": "ashfront", "host": "front.example", "port": 4002, "max": 32,
			"status": {"players": 4, "level": "Battle"}})
	await _until(t, func() -> bool: return int(plaza.worlds.get("ashfront", {}).get("status", {}).get("players", 0)) == 4, 4.0)
	t.check(int(plaza.worlds.ashfront.status.players) == 4, "and its news as it changes")
	front.announce({"world": "no_such_world", "host": "", "port": 4003, "max": 1, "status": {}})
	front.announce({"world": "plaza", "host": "", "port": 0, "max": 1, "status": {}})
	await t.frames(20)
	t.check(not service.directory().has("no_such_world") and service.directory().plaza.port == 4001,
			"a world the game does not have, or one with no port, is not listed")

	# Clans: kept by the service, read from a copy on every server.
	var heard := {"front": 0}
	front.clans_changed.connect(func() -> void: heard.front += 1)
	var made: Dictionary = await plaza.clan("create", ada, "Iron Wake", "iw")
	t.check(made.get("ok", false) and plaza.clans.clan_of(ada) == made.get("clan", "?"),
			"a clan founded through one server is in that server's copy when the answer is back")
	await _until(t, func() -> bool: return front.clans.clan_of(ada) != "", 3.0)
	t.check(front.clans.tag_of(front.clans.clan_of(ada)) == "IW" and heard.front > 0,
			"and reaches the other server's copy")
	t.check((await front.clan("join", bo, str(made.get("clan", "")))).get("ok", false)
			and front.clans.members_of(str(made.clan)).size() == 2, "a player on the other server joins it")
	await _until(t, func() -> bool: return plaza.clans.members_of(str(made.clan)).size() == 2, 3.0)
	t.check(plaza.clans.members_of(str(made.clan)).size() == 2, "which the first server hears in turn")
	t.check(not (await front.clan("create", bo, "Second", "S2")).get("ok", true), "a refusal says so and changes nothing")
	await front.equip(bo, "primary", "rifle_scrap")
	t.check((await front.deploy(bo, Worlds.get_world("ashfront"))).get("ok", false)
			and not (await front.clan("leave", bo)).get("ok", true) and front.clans.clan_of(bo) != "",
			"nobody changes clan while deployed, whichever server asks")
	await front.cancel_deploy(bo)

	# The phone: one set of records and one list of who is online.
	var pinged: Array[String] = []
	front.social_noticed.connect(func(id: String, text: String) -> void: pinged.append("%s|%s" % [id, text]))
	await plaza.social("online", ada, ["Ada Vane", "hub", "plaza"])
	var mine: Dictionary = await front.social("online", bo, ["Bodil", "raid", "ashfront"])
	t.check(mine.get("ok", false) and front.social_snapshot(bo).get("contacts", []).any(
			func(c: Dictionary) -> bool: return c.id == ada and c.online and c.where == "hub"),
			"a player out in a world sees who is in the plaza")
	await _until(t, func() -> bool: return plaza.social_snapshot(ada).get("contacts", []).any(
			func(c: Dictionary) -> bool: return c.id == bo and c.online), 4.0)
	t.check(plaza.social_snapshot(ada).get("contacts", []).any(func(c: Dictionary) -> bool: return c.id == bo and c.where == "raid"),
			"and the player in the plaza is told who came online elsewhere")
	var sent: Dictionary = await plaza.social("message", ada, [bo, "meet at the gate"])
	t.check(sent.get("ok", false) and plaza.social_snapshot(ada).get("messages", []).size() == 1,
			"a message sent from one world")
	await _until(t, func() -> bool: return not pinged.is_empty(), 3.0)
	t.check(pinged == ["%s|Ada Vane: meet at the gate" % bo] and front.social_snapshot(bo).get("messages", []).size() == 1,
			"reaches a player in another, on their own server (%s)" % str(pinged))
	# Ada connects ahead to the world, then leaves the plaza: never offline.
	await front.sign_in_with({"method": "token", "token": service.stash.sign_in_with(
			{"method": "token", "token": ""}).get("token", "")})
	await front.social("online", ada, ["Ada Vane", "lobby", "ashfront"])
	await plaza.social("offline", ada, ["plaza"])
	await t.frames(5)
	t.check(service.social.is_online(ada) and service.social.where(ada) == "lobby",
			"a player who connected ahead and then left the plaza was online throughout")
	# A game server goes away: its players are offline and its world is off the directory.
	front.queue_free()
	await _until(t, func() -> bool: return not plaza.worlds.has("ashfront"), 5.0)
	t.check(not plaza.worlds.has("ashfront") and plaza.worlds.has("plaza") and not service.social.is_online(bo)
			and not service.social.is_online(ada),
			"a game server that goes away is off the directory, and everyone on it is offline")
	# The service itself comes back: the server says again what it runs.
	service.stop()
	service.queue_free()
	await t.frames(2)
	await _until(t, func() -> bool: return not plaza.is_up(), 3.0)
	service = _service(t, dir)
	await _until(t, func() -> bool: return plaza.is_up() and service.directory().has("plaza"), 5.0)
	t.check(service.directory().has("plaza"), "after the service restarts the server is back on its directory")
	await _until(t, func() -> bool: return plaza.clans.clan_of(ada) != "", 3.0)
	t.check(service.clans.clan_of(ada) != "" and plaza.clans.clan_of(ada) != "",
			"and the clans are still there (%s, %s)" % [service.clans.clan_of(ada), plaza.clans.clan_of(ada)])

	plaza.queue_free()
	service.stop()
	service.queue_free()
	await t.frames(2)
	t._wipe_dir(dir)


## The official layout on one machine: every world its own program.
static func _for_real(t: Node) -> void:
	var dir := ProjectSettings.globalize_path(_dir("real"))
	var godot := OS.get_executable_path()
	var cluster := OS.create_process(godot, PackedStringArray(["--headless", "--path",
			ProjectSettings.globalize_path("res://"), "--", "--server", "--cluster", "--port", str(CLUSTER_PORT),
			"--account-port", str(CLUSTER_SERVICE), "--accounts", dir, "--bots", "0", "--no-zone-rules"]))
	var worlds: Array[String] = []
	for world in Worlds.raid_worlds():
		worlds.append(world.id)
	var first: String = worlds[0]

	var ana: NetSession = await t._sign_in("Ana", CLUSTER_PORT)
	t.check(ana != null, "a game signs in at the plaza of a cluster")
	if ana == null:
		await _stop(t, cluster, dir)
		return
	await t._wait_until(func() -> bool:
		return worlds.all(func(id: String) -> bool: return ana.routes.has(id)) and ana.routes.has(Arena.ArenaVenue.ID), 1800)
	t.check(worlds.all(func(id: String) -> bool: return typeof(ana.routes.get(id)) == TYPE_INT)
			and ana.routes.get(first) == CLUSTER_PORT + 1 and ana.routes.get(Arena.ArenaVenue.ID) == CLUSTER_PORT + 10
			and not ana.routes.has(ana.world_id),
			"the plaza knows the way to every world and the arena, each a program of its own (%s)" % str(ana.routes))
	await t._wait_until(func() -> bool: return ana.world_status.has(first), 600)
	t.check(ana.world_status.has(first) and str(ana.world_status[first].get("level", "")) != "",
			"and how each is doing, for the signs over its gates")
	ana.deploy()
	await t._wait_until(func() -> bool: return ana.raid != null and ana.raid.player != null, 600)
	t.check(ana.raid != null and ana.raid.player != null and ana.raid.world.safe_zone, "they walk into the plaza")

	# Connect ahead: signed in to the world while still standing in the plaza.
	var ahead: NetSession = t._new_client("Ana")
	ahead.ticket = ana.ticket
	ahead.ahead = true
	ahead.join("127.0.0.1", CLUSTER_PORT + 1)
	await t._wait_until(func() -> bool: return not ahead.account.is_empty(), 600)
	t.check(not ahead.account.is_empty() and ahead.world_id == first and ahead.raid == null,
			"the game signs in to the next world ahead of the trip, on the token alone")
	await t.frames(30)
	t.check(ana.is_live() and not ana.replaced and ana.raid != null and ana.raid.player != null,
			"and still stands in the plaza: the two are different programs")
	t.check(ahead.routes.has(Worlds.social_world().id) and ahead.routes.has(worlds[1] if worlds.size() > 1 else first)
			or worlds.size() == 1,
			"a world knows the way on to the others, so a portal there can lead anywhere")
	var began := Time.get_ticks_msec()
	ahead.deploy()
	await t._wait_until(func() -> bool: return ahead.raid != null and ahead.raid.player != null, 600)
	var took := (Time.get_ticks_msec() - began) / 1000.0
	t.check(ahead.raid != null and ahead.raid.player != null and ahead.raid.world.id == first,
			"stepping through only waits for the deploy")
	t.check(took < TRAVEL_TARGET, "which takes %.2f s, against the %.0f s target for a whole trip" % [took, TRAVEL_TARGET])
	await t._leave(ana)

	# Clans and the phone reach across programs.
	var ben: NetSession = await t._sign_in("Ben", CLUSTER_PORT)
	t.check(ben != null, "a second player signs in at the plaza")
	if ben != null:
		ben.deploy()
		await t._wait_until(func() -> bool: return ben.raid != null and ben.raid.player != null, 600)
		ben.clan_ask("create", "Iron Wake", "IW")
		await t._wait_until(func() -> bool: return not ben.clan_state.get("clan", {}).is_empty(), 600)
		t.check(ben.clan_state.get("clan", {}).get("tag", "") == "IW", "a clan founded at the plaza's clan hall")
		await t._wait_until(func() -> bool:
			return ahead.clan_state.get("clans", []).any(func(c: Dictionary) -> bool: return c.tag == "IW"), 600)
		t.check(ahead.clan_state.get("clans", []).any(func(c: Dictionary) -> bool: return c.tag == "IW"),
				"is on the list a player out in a world is shown")
		var notices: Array[String] = []
		ahead.social_notice.connect(func(text: String) -> void: notices.append(text))
		await t._wait_until(func() -> bool: return ben.social_state.get("contacts", []).any(
				func(c: Dictionary) -> bool: return c.name == "Ana" and c.online), 600)
		t.check(ben.social_state.get("contacts", []).any(func(c: Dictionary) -> bool: return c.name == "Ana" and c.where == "raid"),
				"the plaza's phone shows a player out in a world as online, and where")
		var ana_id := ""
		for contact: Dictionary in ben.social_state.get("contacts", []):
			if contact.name == "Ana":
				ana_id = contact.id
		ben.send_message(ana_id, "come back in one piece")
		await t._wait_until(func() -> bool: return not notices.is_empty(), 600)
		t.check(notices == ["Ben: come back in one piece"], "and a message from the plaza reaches them there (%s)" % str(notices))

	await _game_travels(t, first)

	# One world's program stops: the rest carry on, and it is started again.
	if ben != null and OS.get_name() == "Linux":
		OS.execute("pkill", PackedStringArray(["-f", "--", "--only %s --port %d" % [first, CLUSTER_PORT + 1]]))
		await t._wait_until(func() -> bool: return not ben.routes.has(first), 900)
		t.check(not ben.routes.has(first) and ben.is_live() and ben.raid != null and ben.routes.has(Arena.ArenaVenue.ID),
				"a world whose program stops is off the plaza's routes, and the plaza carries on")
		await t._wait_until(func() -> bool: return ben.routes.has(first), 3600)
		t.check(ben.routes.has(first), "the cluster starts that world again and its gate opens once more")
		var back: NetSession = await t._sign_in("Ben2", CLUSTER_PORT + 1)
		t.check(back != null, "and it lets players in")
		await t._leave(back)
	await t._leave(ben)
	await t._leave(ahead)
	await _stop(t, cluster, dir)


## The game itself: into the plaza, connected ahead to the world behind the
## nearest doorway, and through the gate on that connection.
static func _game_travels(t: Node, first: String) -> void:
	Profile.reset()
	Profile.home_server = ""
	Profile.player_name = "Kestrel"
	Profile.welcome_granted = true
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.ahead_range = 0.0
	t.add_child(main)
	await t.frames(20)
	main.join_online("127.0.0.1:%d" % CLUSTER_PORT, false)
	await t._wait_until(func() -> bool: return main.raid != null and main.raid.player != null, 1800)
	t.check(main.raid != null and main.raid.player != null and main.raid.world.safe_zone, "the game walks into the cluster's plaza")
	if main.raid == null or main.raid.player == null:
		main.queue_free()
		await t.frames(30)
		Profile.reset()
		return
	await t._wait_until(func() -> bool: return main.net.routes.has(first), 600)
	t.check(main._where_leads("world:" + first) == ["127.0.0.1", CLUSTER_PORT + 1, first]
			and main._where_leads("shop:armory").is_empty() and main._where_leads("").is_empty()
			and main._where_leads("world:" + main.net.world_id).is_empty()
			and main._where_leads(Arena.ArenaVenue.ID) == ["127.0.0.1", CLUSTER_PORT + 10, Arena.ArenaVenue.ID],
			"it knows which doorways lead to another server, and where (%s)" % str(main._where_leads("world:" + first)))
	main._tick_ahead(0.5)
	t.check(main._ahead == null, "far from any doorway it connects to nothing ahead")
	# Near a doorway: the game signs in behind it while you still stand here.
	main.ahead_range = 10000.0
	main._tick_ahead(0.5)
	t.check(main._ahead != null and main._ahead.ahead, "near a doorway it connects ahead to where that leads")
	# Which doorway is nearest is the plaza's business: the trip checked
	# here is the one to the first world.
	main.ahead_range = 0.0
	main._drop_ahead()
	main._connect_ahead("127.0.0.1", CLUSTER_PORT + 1, first)
	await t._wait_until(func() -> bool:
		return main._ahead == null or not is_instance_valid(main._ahead) or not main._ahead.account.is_empty(), 900)
	var ahead: NetSession = main._ahead
	t.check(ahead != null and is_instance_valid(ahead) and not ahead.account.is_empty() and ahead.raid == null
			and main.raid != null and main.raid.world.safe_zone and main.net.is_live(),
			"and is signed in there while it stands in the plaza")
	if ahead != null and is_instance_valid(ahead):
		var world_id: String = ahead.world_id
		var ahead_id := ahead.get_instance_id()
		var began := Time.get_ticks_msec()
		main.use_portal("world:" + world_id)
		t.check(main.net != null and main.net.get_instance_id() == ahead_id and main._ahead == null,
				"stepping through carries on with that connection")
		await t._wait_until(func() -> bool:
			return main.raid != null and main.raid.player != null and main.raid.world.id == world_id, 900)
		var took := (Time.get_ticks_msec() - began) / 1000.0
		t.check(main.raid != null and main.raid.player != null and main.raid.world.id == world_id,
				"and the gate drops you into %s" % world_id)
		t.check(took < TRAVEL_TARGET, "in %.2f s through the gate (target %.0f s)" % [took, TRAVEL_TARGET])
		await t.frames(40)
		t.check(main._cover.color.a < 0.05 and not main._travel.visible, "the world has faded in")
		# Out in a world nothing leads on until a portal or a sign-out does.
		main._tick_ahead(0.5)
		t.check(main._ahead == null, "out in the world it holds no second connection")
		# A connection ahead that is never used is given up.
		main._connect_ahead("127.0.0.1", CLUSTER_PORT, "plaza")
		t.check(main._ahead != null, "a connection made ahead")
		main.ahead_linger = 1.0
		main._tick_ahead(0.6)
		main._tick_ahead(0.6)
		t.check(main._ahead == null, "is dropped again when the trip is not made")
	# One that cannot get in is dropped quietly and left alone for a while.
	main.ahead_linger = 20.0
	main._connect_ahead("127.0.0.1", CLUSTER_PORT + 77, "")
	await t._wait_until(func() -> bool: return main._ahead == null, 1800)
	main._connect_ahead("127.0.0.1", CLUSTER_PORT + 77, "")
	t.check(main._ahead == null and main.net != null and main.raid != null,
			"a server that cannot be reached ahead costs nothing: the game carries on where it is")
	main.queue_free()
	await t.frames(30)
	Profile.reset()
	Profile.home_server = ""


static func _stop(t: Node, cluster: int, dir: String) -> void:
	OS.kill(cluster)
	if OS.get_name() == "Linux":
		# Its worlds would stop by themselves once their heartbeat goes stale;
		# the ports are wanted back sooner than that.
		OS.execute("pkill", PackedStringArray(["-f", "--", "--account-url ws://127.0.0.1:%d" % CLUSTER_SERVICE]))
	await t.frames(30)
	t._wipe_dir(dir)
	t._wipe_dir(dir + "_backups")
