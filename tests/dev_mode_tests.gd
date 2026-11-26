extends RefCounted
## The `dev_mode` checks. The test runner finds this file by itself and calls
## `run(t)`.

const StashService := preload("res://core/account/stash_service.gd")
const PhoneScript := preload("res://core/phone/phone.gd")
const DevMode := preload("res://core/dev/dev_mode.gd")
const DevEconomy := preload("res://core/economy/economy.gd")
const DevStashRules := preload("res://core/account/stash_rules.gd")
const DevBaseUpgrades := preload("res://core/base/base_upgrades.gd")


## DEV MODE: the temporary testing mode (`core/dev/dev_mode.gd`). Delete this
## group along with it.


static func run(t: Node) -> void:
	print("Dev mode (temporary)")
	DevMode.persist = false
	DevMode.enabled = false
	t.check(DevMode.available(), "dev mode can be switched on in a debug run")
	t.check(DevMode.available_in(true, false, false) and not DevMode.available_in(true, true, false)
			and not DevMode.available_in(true, true, true) and not DevMode.available_in(false, false, false),
			"the exported dev build has dev mode; the exported release build and its server never do")
	t.check(DevMode.starts_on_in(true, false) and not DevMode.starts_on_in(true, true)
			and not DevMode.starts_on_in(false, false) and not DevMode.starts_on(),
			"the exported dev build starts with dev mode on; the editor and the tests keep the saved choice")
	t.check(DevMode.raid_cheats().is_empty(), "with dev mode off a raid gets no cheats")

	# The dev stash: every piece of gear, healing in bulk, max scrip.
	var stash: Array[String] = []
	t.check(DevMode.top_up(stash) == DevEconomy.MAX_SCRIP, "dev mode holds as many scrip as a stash can")
	var every_fit := true
	for id: String in ItemDB.all_ids():
		if not DevStashRules.storable(id):
			t.check(id not in stash, "%s (starter or power) never enters a dev stash" % id)
			continue
		for slot: String in Loadout.SLOTS:
			if Loadout.fits(slot, id) and id not in stash:
				every_fit = false
	t.check(every_fit, "every rig, gun, blade, helmet, ability, attachment and vehicle is in the dev stash")
	t.check(stash.count("medkit") == DevMode.CONSUMABLE_COPIES, "the dev stash has healing in bulk")
	var full := stash.size()
	DevMode.top_up(stash)
	t.check(stash.size() == full, "topping up again adds nothing")
	stash.erase("wings_glide")
	DevMode.top_up(stash)
	t.check("wings_glide" in stash and stash.size() == full, "gear lost in a run comes back on the next top-up")

	# The dev save never touches the real one, and you stay you.
	var real_path := "user://test_profile_real.json"
	var dev_path := "user://test_profile_dev.json"
	for path in [real_path, dev_path]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	Profile.reset()
	Profile.persist = true
	Profile.save_path = real_path
	Profile.player_name = "Tester"
	Profile.add_to_stash(["rifle_carbine", "rifle_carbine", "rifle_carbine"])
	var real_scrip := Profile.scrip
	Profile.use_save(dev_path)
	Profile.scrip = DevMode.top_up(Profile.stash)
	Profile.save()
	t.check(Profile.save_path == dev_path and "helm_ember_mk2" in Profile.stash and Profile.player_name == "Tester",
			"the dev save has everything and keeps who you are")
	Profile.use_save(real_path)
	t.check("helm_ember_mk2" not in Profile.stash and Profile.stash.count("rifle_carbine") >= 3
			and Profile.scrip == real_scrip, "switching back finds the real stash untouched")
	Profile.use_save(dev_path)
	t.check("helm_ember_mk2" in Profile.stash and Profile.scrip == DevEconomy.MAX_SCRIP,
			"the dev save is kept between switches")
	Profile.persist = false
	Profile.save_path = Profile.SAVE_PATH
	Profile.player_name = "Raider"
	Profile.reset()
	for path in [real_path, dev_path]:
		DirAccess.remove_absolute(path)

	# A save from before the fresh start (free test gear, a full base, leaked
	# dev scrip) is set back to a fresh player once, keeping who you are.
	Profile.reset()
	var old_save := Profile.to_dict()
	old_save.erase("fresh_start")
	old_save.player_name = "Caleb"
	old_save.online_secret = "kept-secret"
	old_save.stash = ["wings_glide", "boots_thruster", "chip_blink", "helm_ember_mk2"]
	old_save.scrip = DevEconomy.MAX_SCRIP
	old_save.base_upgrades = DevBaseUpgrades.full()
	old_save.welcome_granted = true
	Profile.load_dict(old_save)
	t.check(Profile.fresh_start < Profile.FRESH_START, "a save from before the fresh start is spotted")
	Profile.start_fresh()
	Profile.grant_welcome_crate()
	t.check(Profile.player_name == "Caleb" and Profile.online_secret == "kept-secret"
			and Profile.scrip == DevEconomy.STARTING_SCRIP and Profile.base_upgrades.is_empty()
			and "wings_glide" not in Profile.stash and "helm_ember_mk2" not in Profile.stash
			and "bike_scrapper" in Profile.stash and Profile.fresh_start == Profile.FRESH_START,
			"the fresh start keeps who you are and leaves a new player's stash, scrip and base")
	Profile.load_dict(Profile.to_dict())
	t.check(Profile.fresh_start == Profile.FRESH_START, "and it happens only once")
	Profile.player_name = "Raider"
	Profile.online_secret = ""
	Profile.reset()

	# A dev server's snapshots never go back into the real save: the game only
	# takes on snapshots from a server it hosted from the same save.
	var main_view: Node = load("res://core/main.gd").new()
	main_view._server_pid = 1
	main_view._join_address = "127.0.0.1"
	main_view._hosted_save = Profile.DEV_SAVE_PATH
	var dev_snapshot := {"ok": true, "stash": ["helm_ember_mk2"], "scrip": DevEconomy.MAX_SCRIP,
			"base_upgrades": DevBaseUpgrades.full()}
	main_view._keep_profile_in_step(dev_snapshot)
	t.check("helm_ember_mk2" not in Profile.stash and Profile.base_upgrades.is_empty()
			and Profile.scrip == DevEconomy.STARTING_SCRIP,
			"turning dev mode off on your own dev server leaks nothing into the real profile")
	main_view._hosted_save = Profile.save_path
	main_view._keep_profile_in_step(dev_snapshot)
	t.check("helm_ember_mk2" in Profile.stash, "a server hosted from this save still keeps it in step")
	main_view._server_pid = -1
	main_view.free()
	Profile.reset()

	# Online: a server hosted in dev mode tops up the host's account only, and
	# the host is whoever claims the handed profile with its secret, never
	# just someone using the host's name.
	var service := StashService.new()
	service.persist = false
	service.dev_host = true
	var host_secret := StashService.new_secret()
	service.host_profile = {"player_name": "Dev Host", "online_secret": host_secret}
	var host_id: String = service.sign_in("Dev Host", host_secret).account_id
	var friend_id: String = service.sign_in("Dev Friend", StashService.new_secret()).account_id
	var spoofed := StashService.new()
	spoofed.persist = false
	spoofed.dev_host = true
	spoofed.host_profile = {"player_name": "Dev Host", "online_secret": host_secret}
	var faker: String = spoofed.sign_in("Dev Host", StashService.new_secret()).account_id
	t.check("helm_ember_mk2" not in spoofed.snapshot(faker).stash,
			"signing in with the host's name but not their secret gets no dev stash")
	var host_view := service.snapshot(host_id)
	t.check("helm_ember_mk2" in host_view.stash and host_view.scrip == DevEconomy.MAX_SCRIP,
			"a dev server gives the host's account everything and max scrip")
	t.check("helm_ember_mk2" not in service.snapshot(friend_id).stash, "other players on it get nothing extra")
	var host_account = service.load_account(host_id)
	host_account.stash.erase("wings_glide")
	t.check("wings_glide" in service.snapshot(host_id).stash, "gear the host lost comes back on the server too")

	# Cheats in a solo raid.
	DevMode.enabled = true
	t.check(DevMode.raid_cheats().size() == DevMode.CHEATS.size(), "dev mode on hands a raid its cheats")
	DevMode.set_cheat("ammo", false)
	t.check(not DevMode.raid_cheats().has("ammo"), "a cheat can be switched off on its own")
	DevMode.set_cheat("ammo", true)
	var raid: Raid = await t._new_raid(77, false)
	raid.set_dev_cheats(DevMode.raid_cheats())
	await t.frames(2)
	var me := raid.player
	me.protected_left = 0.0
	var bot: Actor = raid.bots[0] if not raid.bots.is_empty() else null
	var hit := Combat.deal(me, DamageInfo.make(500.0, bot, "bullet"))
	t.check(not hit and not me.is_dead and me.dev_invulnerable, "god mode: no hit gets through")
	me.flight.heat = me.flight.max_heat
	me.flight.overheated = true
	me.ability.cooldown_left = 5.0
	var gun: Gun = null
	for weapon in me.weapons:
		if weapon is Gun:
			gun = weapon
	if gun != null:
		gun.ammo_in_mag = 0
	await t.frames(2)
	t.check(me.flight.heat == 0.0 and not me.flight.overheated, "endless flight heat")
	t.check(me.ability.cooldown_left == 0.0, "no ability cooldowns")
	t.check(gun != null and gun.ammo_in_mag == gun.mag_size, "endless ammo keeps the magazine full")
	raid.set_dev_cheats({})
	await t.frames(1)
	me.protected_left = 0.0
	t.check(not me.dev_invulnerable and Combat.deal(me, DamageInfo.make(5.0, bot, "bullet")),
			"turning god mode off lets hits through again")
	await t._end_raid(raid)
	var server := Raid.new()
	server.mode = Raid.Mode.SERVER
	server.set_dev_cheats({"god": true})
	t.check(server.dev_cheats.is_empty(), "an online server raid never runs dev cheats")
	server.free()

	# The switch lives in the phone's settings.
	DevMode.enabled = false
	var phone: CanvasLayer = PhoneScript.new()
	t.add_child(phone)
	await t.frames(1)
	var changes := [0]
	phone.dev_mode_changed.connect(func() -> void: changes[0] += 1)
	phone.toggle()
	phone.open_app("settings")
	t.check("dev" in phone.settings_tabs(), "in a debug run the phone's settings have a Dev tab")
	for child in phone._body.get_children():
		t.check(not (child is CheckButton and (child as CheckButton).text.begins_with("Dev mode")),
				"the dev switches stay off the other tabs")
	phone.open_settings_tab("dev")
	await t.frames(1)
	var switch_shown := false
	for child in phone._body.get_children():
		if child is CheckButton and (child as CheckButton).text.begins_with("Dev mode"):
			switch_shown = true
	t.check(switch_shown, "the phone's settings have the dev mode switch")
	phone.set_dev_mode(true)
	t.check(DevMode.enabled and changes[0] == 1, "the phone turns dev mode on")
	phone.set_dev_mode(false)
	t.check(not DevMode.enabled and changes[0] == 2, "and off again")
	phone.close()
	phone.queue_free()
	await t.frames(1)
