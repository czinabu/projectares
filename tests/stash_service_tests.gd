extends RefCounted
## The `stash_service` checks. The test runner finds this file by itself and calls
## `run(t)`.

const StashService := preload("res://core/account/stash_service.gd")


static func run(t: Node) -> void:
	print("Server stash service")
	var world := Worlds.get_world("ashfront")
	var profile_stash := Profile.stash.duplicate()
	var dir := "user://test_accounts_%d" % Time.get_ticks_usec()
	var service := StashService.new()
	service.save_dir = dir
	var secret := StashService.new_secret()
	t.check(secret.length() >= StashService.MIN_SECRET and secret != StashService.new_secret(), "secrets are long and random")

	t.check(not service.sign_in("x", secret).ok, "a too-short name is refused")
	t.check(not service.sign_in("Vex", "short").ok, "a weak secret is refused")
	var first := service.sign_in("Vex Runner", secret)
	t.check(first.ok and first.created and first.account_id == "vex_runner", "the first sign-in creates the account")
	var again := service.sign_in("vex runner", secret)
	t.check(again.ok and not again.created and again.account_id == "vex_runner", "the same name and secret sign back in")
	t.check(not service.sign_in("Vex Runner", StashService.new_secret()).ok, "someone else's secret cannot take the name")
	var id: String = first.account_id

	var snap := service.snapshot(id)
	t.check(snap.ok and "rifle_carbine" in snap.stash and "bike_scrapper" in snap.stash, "a new account gets the welcome and gear crates")
	t.check(not snap.has("secret_hash") and not snap.has("salt"), "a snapshot carries no secrets")
	var crate_size: int = snap.stash.size()
	service.sign_in("Vex Runner", secret)
	t.check(service.snapshot(id).stash.size() == crate_size, "crates are granted only once")

	t.check(not service.equip(id, "primary", "dmr_longshot").ok, "the server refuses gear the account does not own")
	t.check(not service.equip(id, "melee", "rifle_carbine").ok, "the server refuses gear in the wrong slot")
	t.check(service.equip(id, "primary", "rifle_carbine").ok and service.equip(id, "frame", "frame_trooper").ok,
			"owned gear equips")
	t.check(not service.pick_mastery(id, "rifle", "cut_down").ok, "a locked mastery variant cannot be picked")

	var deploy := service.deploy(id, world)
	t.check(deploy.ok and "rifle_carbine" in deploy.kit and "frame_trooper" in deploy.kit, "deploying hands back the kit")
	t.check(deploy.kit.count("medkit") == 2, "deploying takes the healing items")
	var after_deploy: Array = service.snapshot(id).stash
	t.check("rifle_carbine" not in after_deploy and "medkit" not in after_deploy, "deployed gear leaves the server stash")
	t.check(not service.deploy(id, world).ok, "an account cannot deploy twice at once")
	t.check(not service.equip(id, "primary", "rifle_carbine").ok, "the loadout is locked during a raid")

	# A server crash mid-raid: a fresh service loads the save and returns the gear.
	var restarted := StashService.new()
	restarted.save_dir = dir
	var reloaded := restarted.snapshot(id)
	t.check(reloaded.ok and not reloaded.deployed and "rifle_carbine" in reloaded.stash and reloaded.stash.count("medkit") == 2,
			"an unsettled deploy is returned after a restart")
	t.check(reloaded.loadout.get("primary", "") == "rifle_carbine", "the loadout survives a restart")
	t.check(restarted.sign_in("Vex Runner", secret).ok and not restarted.sign_in("Vex Runner", StashService.new_secret()).ok,
			"sign-in still checks the secret after a restart")

	# Bank, then leave a real raid alive, and settle its result.
	deploy = restarted.deploy(id, world)
	var raid := Raid.new()
	raid.apply_to_profile = false
	t.add_child(raid)
	raid.start(world, 61, deploy.kit, deploy.picks)
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
	await t.frames(3)
	var results: Array[Dictionary] = []
	raid.player_finished.connect(func(_a: Actor, r: Dictionary) -> void: results.append(r))
	t.check(restarted.bank(id, ["alloy_ingot", "rifle_scrap", "no_such_item"]).ok
			and restarted.snapshot(id).stash.count("alloy_ingot") == 1
			and "rifle_scrap" not in restarted.snapshot(id).stash and restarted.snapshot(id).deployed,
			"banked loot reaches the stash while still deployed, and scrap never does")
	raid.player.inventory.add_item("scrap_metal")
	raid.begin_sign_out(raid.player)
	raid.state_for(raid.player).sign_out_left = 0.1
	await t.frames(20)
	t.check(results.size() == 1 and results[0].outcome == "left", "the server-stash life ends by leaving")
	if results.size() == 1:
		t.check(restarted.settle(id, results[0]).ok, "the result settles")
	var home := restarted.snapshot(id)
	t.check("rifle_carbine" in home.stash and "scrap_metal" in home.stash and home.raids_extracted == 1,
			"leaving alive brings gear and loot into the server stash")
	t.check(not home.deployed and not restarted.settle(id, results[0] if results.size() == 1 else {}).ok,
			"a result cannot be settled twice")
	t.check(not restarted.bank(id, ["alloy_ingot"]).ok, "nothing can be banked from the hub")
	t.check(Profile.stash == profile_stash, "the server stash never touches the local profile")
	await t._end_raid(raid)

	# Dying loses the deployed gear.
	deploy = restarted.deploy(id, world)
	restarted.settle(id, {"outcome": "died", "brought_home": [], "kills": 2, "mastery_xp": {"rifle": 999999}})
	home = restarted.snapshot(id)
	t.check("rifle_carbine" not in home.stash and home.loadout.get("primary", "") == "rifle_scrap",
			"dying loses the gear, and the free scrap gun takes its slot")
	t.check(home.kills == 2 and restarted.pick_mastery(id, "rifle", "cut_down").ok, "mastery XP is kept after death")

	# A join that never happened gives everything back.
	var before: Array = restarted.snapshot(id).stash
	restarted.deploy(id, world)
	t.check(restarted.cancel_deploy(id).ok and restarted.snapshot(id).stash.size() == before.size(),
			"cancelling a deploy returns the gear")
	t.check(restarted.snapshot("nobody").ok == false and not restarted.deploy("nobody", world).ok,
			"unknown accounts are refused")

	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)


# --- The phone ---------------------------------------------------------------
