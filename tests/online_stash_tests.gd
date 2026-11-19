extends RefCounted
## The `online_stash` checks. The test runner finds this file by itself and calls
## `run(t)`.

const BasePlan := preload("res://core/base/base_plan.gd")
const StashService := preload("res://core/account/stash_service.gd")


static func run(t: Node) -> void:
	print("Online: the server owns the stash")
	var local_stash := Profile.stash.duplicate()
	var port := 24813
	var pid: int = t._start_server(port, ["--bots", "0", "--squad-spawn"])
	var cara: NetSession = await t._sign_in("Cara", port)
	t.check(cara != null, "a client signs in and waits in the lobby")
	if cara == null:
		OS.kill(pid)
		return
	t.check(cara.raid == null and cara.my_actor_id < 0, "signing in does not enter the raid")
	t.check("rifle_carbine" in cara.account.stash and cara.account.loadout.is_empty()
			and not cara.account.has("secret_hash"),
			"the lobby shows the stash the server keeps, with a new account's crates, nothing equipped")

	# Someone else cannot take the name.
	var thief: NetSession = t._new_client("Cara", StashService.new_secret())
	var refusal := [""]
	thief.failed.connect(func(reason: String) -> void: refusal[0] = reason)
	thief.join("127.0.0.1", port)
	await t._wait_until(func() -> bool: return refusal[0] != "", 240)
	t.check(refusal[0] != "" and thief.refused and thief.account.is_empty(), "the same name with another secret is refused (%s)" % refusal[0])
	await t._leave(thief)

	# Loadout changes are requests. The server checks them against its stash.
	var errors: Array[String] = []
	cara.lobby_error.connect(func(reason: String) -> void: errors.append(reason))
	cara.equip("primary", "dmr_longshot")
	await t._wait_until(func() -> bool: return not errors.is_empty(), 120)
	t.check(errors.size() == 1 and cara.account.loadout.get("primary", "") == "",
			"the server refuses gear the account does not own")
	cara.equip("primary", "rifle_carbine")
	await t._wait_until(func() -> bool: return cara.account.loadout.get("primary", "") == "rifle_carbine", 120)
	t.check(cara.account.loadout.get("primary", "") == "rifle_carbine", "owned gear equips through the server")
	cara.pick_mastery("rifle", "cut_down")
	await t._wait_until(func() -> bool: return errors.size() == 2, 120)
	t.check(errors.size() == 2 and cara.account.mastery.get("picks", {}).is_empty(), "a locked mastery variant is refused")
	# Home base upgrades are bought on the server too, at its price.
	t.check(cara.account.get("base_upgrades", ["?"]) == [] and int(cara.account.scrip) == 500,
			"a new account starts in the starter bunker")
	cara.buy_upgrade("ops_consoles")
	await t._wait_until(func() -> bool: return cara.account.get("base_upgrades", []) == ["ops_consoles"], 120)
	t.check(cara.account.get("base_upgrades", []) == ["ops_consoles"] and int(cara.account.scrip) == 0,
			"the server sells a base upgrade and takes the scrip")
	cara.buy_upgrade("gear_hall")
	await t._wait_until(func() -> bool: return errors.size() == 3, 120)
	t.check(errors.size() == 3 and cara.account.get("base_upgrades", []).size() == 1,
			"the server refuses an upgrade the account cannot pay for")
	# The base's plan is kept on the server too.
	t.check(cara.account.get("base_plan", {}) == BasePlan.DEFAULT, "a new account has the default base plan")
	cara.place_room("E1", "armory")
	await t._wait_until(func() -> bool: return cara.account.get("base_plan", {}).get("E1", "") == "armory", 120)
	t.check(cara.account.get("base_plan", {}).get("E1", "") == "armory" and cara.account.base_plan["W1"] == BasePlan.DEFAULT["E1"],
			"moving a room is asked of the server, and the snapshot brings the new plan")
	# Crafting is decided on the server too: no blueprint, no craft.
	t.check(cara.account.get("blueprints", ["?"]) == [], "a new account knows no blueprints")
	cara.craft("jetpack_mk2")
	await t._wait_until(func() -> bool: return errors.size() == 4, 120)
	t.check(errors.size() == 4 and "jetpack_mk2" not in cara.account.stash and int(cara.account.scrip) == 0,
			"the server refuses a craft without its blueprint (%s)" % [errors.back()])

	cara.deploy()
	await t._wait_until(func() -> bool: return cara.raid != null and cara.raid.player != null, 240)
	t.check(cara.raid != null and cara.raid.player != null, "deploying from the lobby enters the raid")
	if cara.raid != null and cara.raid.player != null:
		var state := cara.raid.state_for(cara.raid.player)
		t.check(state != null and "rifle_carbine" in state.kit and state.kit.count("medkit") == 2,
				"the kit is the one the server took from the stash")
		await t._wait_until(func() -> bool: return cara.account.deployed, 120)
		t.check(cara.account.deployed and "rifle_carbine" not in cara.account.stash and "medkit" not in cara.account.stash,
				"deployed gear has left the server stash")
	# Dropping the connection leaves the body in the world for the sign-out
	# time. Nobody kills it here, so the gear then comes home.
	await t._leave(cara)
	await t.frames(30)
	cara = await t._sign_in("Cara", port)
	t.check(cara != null, "the same name and secret sign back in")
	if cara != null:
		t.check(cara.account.deployed and "rifle_carbine" not in cara.account.stash,
				"the body is still out there, with the gear on it")
		# Back in time: the server puts you in that body (a reconnect), no
		# second deploy and no second kit.
		await t._wait_until(func() -> bool: return cara.raid != null and cara.raid.player != null, 240)
		t.check(cara.resuming and cara.raid != null and cara.raid.player != null
				and "rifle_carbine" in cara.raid.player.gear_items,
				"signing back in puts you back in the body you left, gear and all")
		cara.sign_out()
		await t._wait_until(func() -> bool: return not cara.account.deployed,
				int(Worlds.get_world("ashfront").sign_out_time * 60.0) + 300)
		t.check(not cara.account.deployed and "rifle_carbine" in cara.account.stash
				and cara.account.loadout.get("primary", "") == "rifle_carbine" and cara.account.raids_played == 1
				and cara.account.raids_extracted == 1,
				"the body signed out: the gear is home and the account is told")
		t.check("bike_scrapper" in cara.account.stash, "gear that stayed in the stash is safe")
	await t._leave(cara)
	OS.kill(pid)
	await t.frames(30)

	# A new server process reads the same accounts from disk.
	pid = t._start_server(port + 1, ["--bots", "0"])
	cara = await t._sign_in("Cara", port + 1)
	t.check(cara != null and cara.account.raids_played == 1 and "rifle_carbine" in cara.account.stash,
			"the stash survives a server restart")
	await t._leave(cara)
	OS.kill(pid)
	t.check(Profile.stash == local_stash, "online play never touches the local stash")

	print("Online: the hub as a lobby")
	var hub := Hub.new()
	t.add_child(hub)
	await t.frames(1)
	var service := StashService.new()
	service.persist = false
	var id: String = service.sign_in("Lobby Tester", StashService.new_secret()).account_id
	var asked: Array = []
	hub.online_equip_requested.connect(func(slot: String, item_id: String) -> void: asked.append([slot, item_id]))
	hub.enter_lobby(service.snapshot(id), Worlds.get_world("ashfront"))
	t.check(hub.in_lobby() and hub.options_for("primary") == (["rifle_carbine", "rifle_scrap"] as Array[String])
			and hub.equipped("primary") == "", "in a lobby the hub lists the server's stash and the free scrap, nothing on yet")
	var loadout_before := Profile.loadout.duplicate()
	hub._on_picked(1, "primary")
	t.check(asked == [["primary", "rifle_carbine"]] and Profile.loadout == loadout_before,
			"picking gear in a lobby asks the server and leaves the local profile alone")
	service.equip(id, "primary", "rifle_carbine")
	hub.update_account(service.snapshot(id))
	t.check(hub.equipped("primary") == "rifle_carbine" and "rifle" in hub._mastery.loadout_tracks(),
			"the hub shows the loadout the server confirmed")
	hub.leave_lobby()
	t.check(not hub.in_lobby() and hub.equipped("primary") == Profile.equipped("primary"), "leaving the lobby shows the solo stash again")
	hub.queue_free()


# --- Server-owned stash --------------------------------------------------------
