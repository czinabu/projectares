extends RefCounted
## Checks that you are the same player everywhere you go, and arrive where
## you expect: the loadout you leave your base with is the one you wear in
## the plaza, a world and the arena, and coming back through a doorway puts
## you in front of it. The trips through a real server are in
## `travel_online_tests.gd`. Called from the test runner (`-- --groups
## TravelTests` runs just these).

const Accounts := preload("res://core/account/stash_service.gd")
const StashRules := preload("res://core/account/stash_rules.gd")


static func run(t: Node) -> void:
	print("Travel: one player state, arrivals by doorway")
	_handoff(t)
	await _doorways(t)
	await _base_to_arena(t)


## Your profile and your account on your own server are one player state,
## handed whole one way and the other.
static func _handoff(t: Node) -> void:
	Profile.reset()
	Profile.player_name = "Wren"
	Profile.welcome_granted = true
	Profile.add_to_stash(["dmr_longshot", "frame_bulwark", "rifle_carbine", "medkit"])
	Profile.equip("primary", "dmr_longshot")
	Profile.equip("frame", "frame_bulwark")
	Profile.scrip = 777
	var secret := Profile.get_online_secret()
	var service := Accounts.new()
	service.persist = false
	service.host_profile = Profile.to_dict()
	check_stranger(t, service)
	var signed := service.sign_in("Wren", secret)
	var me := service.snapshot(str(signed.get("account_id", "")))
	t.check(signed.get("ok", false) and me.loadout == Profile.loadout and me.loadout.primary == "dmr_longshot"
			and me.loadout.frame == "frame_bulwark"
			and int(me.scrip) == 777 and "dmr_longshot" in me.stash and not "rifle_scrap" in me.stash,
			"on your own server your account is your profile: same loadout, stash and scrip")
	t.check(service.host_profile.is_empty(), "the hand-over happens once")
	service.equip(signed.account_id, "primary", "rifle_carbine")
	service.change_scrip(signed.account_id, 23)
	service.sign_in("Wren", secret)
	me = service.snapshot(signed.account_id)
	t.check(me.loadout.primary == "rifle_carbine" and int(me.scrip) == 800,
			"signing in again (the next world on that server) keeps what you did there")
	Profile.adopt_account(me)
	t.check(Profile.equipped("primary") == "rifle_carbine" and Profile.equipped("frame") == "frame_bulwark"
			and Profile.scrip == 800 and Profile.player_name == "Wren" and Profile.online_secret == secret,
			"and the profile takes it back, keeping who you are")
	t.check(StashRules.CARRIED.all(func(key: String) -> bool: return Profile.to_dict().has(key) and me.has(key)),
			"every carried key is in both the profile and the account snapshot")
	Profile.reset()


## Someone else using the host's name never gets the host's profile.
static func check_stranger(t: Node, service: Accounts) -> void:
	var other := Accounts.new()
	other.persist = false
	other.host_profile = service.host_profile.duplicate(true)
	var stranger := other.sign_in("Wren", Accounts.new_secret())
	var theirs := other.snapshot(str(stranger.get("account_id", "")))
	t.check(stranger.get("ok", false) and theirs.loadout == StashRules.starter_loadout()
			and not other.host_profile.is_empty(),
			"a stranger signing in with the host's name does not get the host's gear")


## Back in a safe zone through a doorway, you stand in front of that door,
## clear of it, the same spot every time.
static func _doorways(t: Node) -> void:
	var plaza := Worlds.social_world()
	var raid := Raid.new()
	t.add_child(raid)
	raid.start(plaza, 5)
	await t.frames(2)
	var doors := {}
	for node in t.get_tree().get_nodes_in_group("portal"):
		if raid.map.is_ancestor_of(node):
			doors[str(node.get_meta("destination", ""))] = node
	var all_right := true
	var trips: Array[String] = ["home", "arena"]
	for world in Worlds.raid_worlds():
		trips.append("world:%s" % world.id)
	for trip in trips:
		var door: Node3D = doors.get(trip)
		if door == null:
			all_right = false
			t.check(false, "the plaza has a doorway to %s" % trip)
			continue
		var actor := raid.add_player([], {}, "You", "", 0, "from:" + trip)
		var flat := Vector2(actor.global_position.x - door.global_position.x, actor.global_position.z - door.global_position.z)
		var radius := float(door.get_meta("radius", 2.0))
		var again := raid.add_player([], {}, "You", "", 0, "from:" + trip)
		var ok := flat.length() > radius and flat.length() < radius + 4.0 \
				and again.global_position.distance_to(actor.global_position) < 0.01
		if not ok:
			t.check(false, "back from %s you land %.1f m from its door (radius %.1f)" % [trip, flat.length(), radius])
		all_right = all_right and ok
	t.check(all_right, "coming back from home, the arena or any world, you arrive just outside that doorway, every time")
	# Walk away: the spot in front of a door is open ground, not inside a wall.
	var back := raid.add_player([], {}, "You", "", 0, "from:world:%s" % Worlds.raid_worlds()[0].id)
	var from := back.global_position
	var inward := Vector3(-from.x, 0, -from.z).normalized()
	back.cmd.yaw = atan2(-inward.x, -inward.z)
	back.cmd.move = Vector2(0, 1)
	await t.frames(60)
	t.check(back.global_position.distance_to(from) > 2.0 and back.is_on_floor(),
			"and you can walk on from there (%.1f m)" % back.global_position.distance_to(from))
	var plain := raid.add_player([], {}, "You", "", 0, "from:nowhere")
	var pads := raid._map_nodes("spawn_player")
	t.check(pads.any(func(p: Node3D) -> bool:
			return Vector2(p.global_position.x - plain.global_position.x, p.global_position.z - plain.global_position.z).length() < 0.5),
			"from nowhere known you arrive on the arrival pad as before")
	raid.queue_free()
	await t.frames(2)


## Base to arena: what the base puts on you is what you wear in the pit,
## and the arena takes nothing from the stash.
static func _base_to_arena(t: Node) -> void:
	Profile.reset()
	Profile.welcome_granted = true
	Profile.add_to_stash(["dmr_longshot", "frame_bulwark", "medkit"])
	Profile.equip("primary", "dmr_longshot")
	Profile.equip("frame", "frame_bulwark")
	var stash_before := Profile.stash.duplicate()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	t.add_child(main)
	await t.frames(20)
	var wearing: Array[String] = main.base.suit_kit()
	main.open_arena()
	await t.frames(5)
	var fighter: Actor = main.raid.player if main.raid != null else null
	t.check(fighter != null and main.raid is Arena, "the base's arena gate takes you to the arena")
	if fighter != null:
		var missing := wearing.filter(func(id: String) -> bool: return not id in fighter.gear_items)
		t.check(missing.is_empty() and "dmr_longshot" in fighter.gear_items and "frame_bulwark" in fighter.gear_items,
				"base to arena: you fight in exactly what your base put on you (missing %s)" % [missing])
	t.check(Profile.stash == stash_before, "and nothing left the stash")
	main.leave_arena()
	await t.frames(5)
	t.check(main.base != null and Profile.equipped("primary") == "dmr_longshot", "leaving the arena takes you home, loadout unchanged")
	main.queue_free()
	await t.frames(5)
	Profile.reset()
