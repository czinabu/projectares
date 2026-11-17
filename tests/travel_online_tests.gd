extends RefCounted
## The trips through a real server: out of your base's door to the plaza of
## a server of your own, through a gate into a world, and home again, with
## the loadout you chose staying on you the whole way (one player state, see
## `StashRules.CARRIED`). Starts a server (a `NetSession` per world), so it
## runs in the online tier. `-- --groups TravelOnlineTests` runs just these.

const PORT := 24961


static func run(t: Node) -> void:
	print("Travel online: base to plaza to world and home, one loadout")
	Profile.reset()
	Profile.home_server = ""
	Profile.player_name = "Wren"
	Profile.welcome_granted = true
	Profile.add_to_stash(["dmr_longshot", "frame_bulwark", "rifle_carbine", "medkit"])
	Profile.equip("primary", "dmr_longshot")
	Profile.equip("frame", "frame_bulwark")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.host_port = PORT
	main.host_args = PackedStringArray(["--accounts", t.NET_ACCOUNTS, "--bots", "0"])
	t.add_child(main)
	await t.frames(20)

	# Base to hub: out of the door to a server of your own.
	main.base.leave_requested.emit()
	await t._wait_until(func() -> bool: return main.raid != null and main.raid.player != null, 3600)
	var me: Actor = main.raid.player if main.raid != null else null
	t.check(me != null and main.raid.world.safe_zone and main._server_pid > 0, "the door takes you to your own server's plaza")
	if me == null:
		await _done(t, main)
		return
	t.check("dmr_longshot" in me.gear_items and "frame_bulwark" in me.gear_items and not "rifle_scrap" in me.gear_items,
			"base to hub: you arrive wearing the loadout you left your base with")
	var home_door := _door(t, main, "home")
	var off := me.global_position - home_door.global_position
	t.check(Vector2(off.x, off.z).length() < float(home_door.get_meta("radius", 2.0)) + 4.0,
			"and you come out at the quarters door, the way back to your base (%.1f m)" % Vector2(off.x, off.z).length())

	# A change made out there is your change at home too.
	main.net.equip("primary", "rifle_carbine")
	await t._wait_until(func() -> bool: return Profile.equipped("primary") == "rifle_carbine", 240)
	t.check(Profile.equipped("primary") == "rifle_carbine" and Profile.equipped("frame") == "frame_bulwark",
			"a loadout change on your own server is your profile's loadout too")

	# Hub to world: through the gate, straight in, in the same gear.
	var world_id: String = Worlds.raid_worlds()[0].id
	main.use_portal("world:" + world_id)
	await t._wait_until(func() -> bool:
		return main.raid != null and main.raid.player != null and main.raid.world.id == world_id, 1200)
	var fighter: Actor = main.raid.player if main.raid != null else null
	t.check(fighter != null and main.raid.world.id == world_id and main.base == null,
			"hub to world: the gate drops you straight into %s" % world_id)
	if fighter != null:
		t.check("rifle_carbine" in fighter.gear_items and "frame_bulwark" in fighter.gear_items,
				"wearing the loadout you had in the hub")
	await t.frames(30)
	t.check("rifle_carbine" in Profile.stash and "frame_bulwark" in Profile.stash,
			"while you are out, your profile still holds the gear you carry")

	# Back to the plaza, in front of the gate you used.
	main._return_to_lobby({})
	await t._wait_until(func() -> bool: return main.raid != null and main.raid.player != null and main.raid.world.safe_zone, 1200)
	if main.raid != null and main.raid.player != null:
		var gate := _door(t, main, "world:" + world_id)
		off = main.raid.player.global_position - gate.global_position
		t.check(Vector2(off.x, off.z).length() < float(gate.get_meta("radius", 2.0)) + 4.0,
				"world to hub: you arrive in front of that world's gate (%.1f m)" % Vector2(off.x, off.z).length())
	else:
		t.check(false, "world to hub: you are back in the plaza")

	# Home: the base shows the same loadout.
	main.use_portal("leave")
	await t._wait_until(func() -> bool: return main.base != null and main.net == null, 600)
	t.check(main.base != null and main._server_pid <= 0 and main.base.suit_kit().has("rifle_carbine")
			and main.base.suit_kit().has("frame_bulwark"), "back home, your base has the same loadout on you")
	await _done(t, main)


static func _door(t: Node, main: Node, destination: String) -> Node3D:
	for node in t.get_tree().get_nodes_in_group("portal"):
		if main.raid.map.is_ancestor_of(node) and node.get_meta("destination", "") == destination:
			return node
	return null


static func _done(t: Node, main: Node) -> void:
	main._stop_local_server()
	main.queue_free()
	await t.frames(30)
	Profile.reset()
	Profile.home_server = ""
