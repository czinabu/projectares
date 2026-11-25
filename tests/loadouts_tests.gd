extends RefCounted
## The `loadouts` checks. The test runner finds this file by itself and calls
## `run(t)`.

const StashRules := preload("res://core/account/stash_rules.gd")


static func run(t: Node) -> void:
	print("Loadouts")
	var world := Worlds.get_world("ashfront")
	Profile.reset()
	Profile.grant_welcome_crate()
	var crate_size := Profile.stash.size()
	Profile.grant_welcome_crate()
	t.check(crate_size > 0 and Profile.stash.size() == crate_size, "the welcome crate is granted once")

	Profile.reset()
	Profile.welcome_granted = true
	# Wearing the scrap kit (a new player starts bare and puts it on by hand).
	Profile.loadout = StashRules.starter_loadout()
	Profile.add_to_stash(["rifle_carbine", "frame_bulwark", "hammer_breaker", "medkit", "medkit", "medkit", "scrap_metal"])
	t.check(not Profile.equip("primary", "hammer_breaker"), "an item cannot go in the wrong slot")
	t.check(not Profile.equip("primary", "dmr_longshot"), "an item you do not own cannot be equipped")
	t.check(Profile.equip("primary", "rifle_carbine") and Profile.equip("frame", "frame_bulwark")
			and Profile.equip("melee", "hammer_breaker"), "owned gear equips into its slot")

	var kit := Profile.checkout_loadout(world)
	t.check("rifle_carbine" in kit and "frame_bulwark" in kit and "hammer_breaker" in kit,
			"deploying takes the chosen gear")
	t.check("jetpack_mk1" in kit, "a scrap piece left on deploys with the rest")
	t.check(kit.count("medkit") == 2 and "field_dressing" not in kit, "up to two medkits come along")
	t.check(Profile.stash == (["medkit", "scrap_metal"] as Array[String]), "deployed gear leaves the stash")

	# Leave alive with the gear: it all comes home.
	var raid := Raid.new()
	t.add_child(raid)
	raid.start(world, 60, kit)
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
	await t.frames(3)
	var p := raid.player
	var gun := p.weapons[0] as Gun
	var hammer := p.weapons[1] as MeleeWeapon
	t.check(gun.display_name == "Ashfront Carbine" and is_equal_approx(gun.damage, 24.0), "weapon stats come from the item")
	t.check(hammer.display_name == "Breaker Hammer" and is_equal_approx(hammer.heavy_damage, ItemDB.item_stats("hammer_breaker").heavy_damage), "melee stats come from the item")
	t.check(is_equal_approx(p.health.armor, float(ItemDB.item_stats("frame_bulwark").armor)), "the frame sets armor")
	var base := Actor.new()
	t.check(p.walk_speed < base.walk_speed and is_equal_approx(p.flight.heat_per_sec, FlightRig.new().heat_per_sec),
			"a heavy frame is slower, and a jetpack carries it without running hotter")
	var wings := Actor.new()
	Loadout.equip(wings, ["wings_glide", "frame_bulwark"])
	t.check(wings.flight.glide_heat > ItemDB.item_stats("wings_glide")["glide_heat"],
			"a heavy frame runs other rigs hotter: the wings' glide stamina drains faster")
	wings.free()
	base.free()
	var results: Array[Dictionary] = []
	raid.player_finished.connect(func(_a: Actor, r: Dictionary) -> void: results.append(r))
	raid.begin_sign_out(p)
	raid.state_for(p).sign_out_left = 0.1
	await t.frames(20)
	t.check(results.size() == 1 and results[0].outcome == "left", "a life with a loadout ends by signing out")
	t.check("rifle_carbine" in Profile.stash and "frame_bulwark" in Profile.stash and "hammer_breaker" in Profile.stash,
			"leaving alive brings your gear home")
	t.check("jetpack_mk1" not in Profile.stash and "rifle_scrap" not in Profile.stash, "scrap gear does not come home")
	t.check(Profile.equipped("primary") == "rifle_carbine", "the loadout stays equipped after leaving")
	await t._end_raid(raid)

	# Die with the gear: it is gone and the slot empties.
	kit = Profile.checkout_loadout(world)
	raid = Raid.new()
	t.add_child(raid)
	raid.start(world, 61, kit)
	await t.frames(3)
	raid.player.kill("test")
	await t.frames(2)
	t.check("rifle_carbine" not in Profile.stash and "frame_bulwark" not in Profile.stash, "dying loses your gear")
	t.check(Profile.equipped("primary") == "rifle_scrap" and Profile.equipped("frame") == "plate_light",
			"lost gear leaves the loadout, and the free scrap piece takes its slot")
	await t._end_raid(raid)

	# A new player has nothing on, so deploys bare; the scrap kit put on by
	# hand deploys as the full free scrap kit.
	Profile.reset()
	Profile.welcome_granted = true
	kit = Profile.checkout_loadout(world)
	t.check(kit.all(func(id: String) -> bool: return ItemDB.has_tag(id, "heal")),
			"a new player with nothing equipped deploys bare (healing aside): %s" % [kit])
	Profile.loadout = StashRules.starter_loadout()
	kit = Profile.checkout_loadout(world)
	t.check(kit == world.starter_loadout(), "with the scrap kit put on, an empty stash deploys the scrap kit")

	# Healing uses any heal item and its own strength.
	raid = await t._new_raid(62, false)
	p = raid.player
	await t.frames(40)
	Combat.deal(p, DamageInfo.make(80.0, null, "bullet"))
	var hurt := p.health.health
	p.cmd.heal_pressed = true
	await t.frames(1)
	p.cmd.heal_pressed = false
	await t.frames(200)
	t.check(is_equal_approx(p.health.health - hurt, 30.0) and p.inventory.count_with_tag("heal") == 0,
			"a field dressing heals its own amount and is used up")

	# Shotgun: several pellets per shot.
	var shotgun := Gun.new()
	Loadout._setup_weapon(shotgun, "shotgun_breacher", ItemDB.item_stats("shotgun_breacher"))
	p.equip_weapon(shotgun)
	p.cmd.switch_weapon = p.weapons.size() - 1
	var arena: Vector3 = t._open_ground(raid)
	p.global_position = Vector3(arena.x, arena.y - 1.9, arena.z + 3.0)
	var target := raid.bots[0]
	target.global_position = p.global_position + Vector3(0, 0, -3.0)
	await t.frames(10)
	p.cmd.switch_weapon = -1
	p.cmd.yaw = 0.0
	p.cmd.aim_dir = (target.global_position + Vector3(0, 1, 0) - p.get_eye_position()).normalized()
	var before := target.health.health
	p.cmd.primary = true
	await t.frames(1)
	p.cmd.primary = false
	await t.frames(2)
	t.check(before - target.health.health > shotgun.damage * 3.0, "a shotgun lands several pellets at once")
	t.check(shotgun.ammo_in_mag == 5, "a shotgun blast uses one shell")
	await t._end_raid(raid)

	# The hub offers what you own.
	Profile.reset()
	Profile.welcome_granted = true
	Profile.add_to_stash(["rifle_carbine", "dmr_longshot", "frame_runner"])
	var hub := Hub.new()
	t.add_child(hub)
	await t.frames(2)
	t.check(hub.options_for("primary") == (["dmr_longshot", "rifle_carbine", "rifle_scrap"] as Array[String])
			and hub.options_for("frame") == (["frame_runner", "plate_light"] as Array[String]),
			"the hub lists owned gear per slot, and the free scrap piece")
	hub._on_picked(1, "primary")
	t.check(Profile.equipped("primary") == "dmr_longshot", "picking in the hub equips the item")
	hub._on_picked(0, "primary")
	t.check(Profile.equipped("primary") == "", "picking None unequips")
	hub.queue_free()
	Profile.reset()
	Profile.welcome_granted = true
