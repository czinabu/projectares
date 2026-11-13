extends RefCounted
## Checks that you can go bare (Caleb's call): every loadout slot can be left
## empty and stays empty, with no free scrap piece put in its place, in the
## base, a world, the plaza and the arena, in both views. The scrap pieces
## are free gear you equip like any other. Called from the test runner
## (`-- --groups BareLoadoutTests` runs just these).

const Accounts := preload("res://core/account/stash_service.gd")
const StashRules := preload("res://core/account/stash_rules.gd")


static func run(t: Node) -> void:
	print("Bare loadout: an empty slot stays empty")
	_rules(t)
	_saves(t)
	await _raids(t)
	await _solo_trip(t)
	Profile.reset()
	Profile.welcome_granted = true


static func _rules(t: Node) -> void:
	var world := Worlds.get_world("ashfront")
	var stash: Array[String] = ["rifle_carbine"]
	t.check(StashRules.checkout(stash.duplicate(), {}, world).filter(func(id: String) -> bool:
				return not ItemDB.has_tag(id, "heal")).is_empty(),
			"an empty loadout deploys with no gear at all")
	t.check(StashRules.checkout([] as Array[String], {}, Worlds.get_world("frostline")).all(func(id: String) -> bool:
				return ItemDB.has_tag(id, "heal")),
			"in every world: Frostline too")
	t.check(StashRules.checkout([] as Array[String], {}, Arena.ArenaVenue.new()) == ([Loadout.BARE] as Array[String]),
			"nothing at all is a bare kit, not an empty one (the arena hands out no healing)")
	var free := StashRules.free_items()
	t.check(free.size() >= 6 and free.all(func(id: String) -> bool: return ItemDB.has_tag(id, "starter")),
			"the free scrap gear is the starter items that go in a slot: %s" % [free])
	t.check(StashRules.can_equip([] as Array[String], "primary", "rifle_scrap")
			and not StashRules.can_equip([] as Array[String], "primary", "rifle_carbine")
			and not StashRules.can_equip([] as Array[String], "primary", "field_dressing"),
			"scrap gear can be equipped without owning a copy; other gear still needs one")
	var keep: Array[String] = ["rifle_carbine"]
	var taken: Array[String] = []
	var kit := StashRules.checkout(keep, {"primary": "rifle_scrap", "melee": "blade_scrap"}, world, taken)
	t.check("rifle_scrap" in kit and "blade_scrap" in kit and taken.filter(func(id: String) -> bool:
				return not ItemDB.has_tag(id, "heal")).is_empty() and keep == (["rifle_carbine"] as Array[String]),
			"equipped scrap deploys and takes nothing from the stash")
	var lost := {"primary": "rifle_carbine", "melee": "knife_gutter", "optic": "optic_scope"}
	StashRules.validate_loadout([] as Array[String], lost)
	t.check(lost == {"primary": "rifle_scrap", "melee": "blade_scrap"},
			"gear that is lost falls back to its free scrap piece, and a slot with none empties (%s)" % [lost])


## Saves from before the bare rule keep what they deployed with; saves after
## it keep their empty slots.
static func _saves(t: Node) -> void:
	Profile.reset()
	Profile.welcome_granted = true
	t.check(Profile.loadout == StashRules.starter_loadout() and Profile.equipped("primary") == "rifle_scrap",
			"a new player starts in the free scrap kit")
	for slot: String in Loadout.SLOTS:
		Profile.unequip(slot)
	t.check(Profile.loadout.is_empty(), "every slot can be taken off")
	Profile.load_dict(Profile.to_dict())
	t.check(Profile.loadout.is_empty(), "and stays off after a save")
	var old := Profile.to_dict()
	old.erase(StashRules.BARE_KEY)
	old["loadout"] = {"primary": "rifle_carbine"}
	old["stash"] = ["rifle_carbine"]
	Profile.load_dict(old)
	t.check(Profile.equipped("primary") == "rifle_carbine" and Profile.equipped("melee") == "blade_scrap"
			and Profile.equipped("helmet") == "visor_scav" and Profile.equipped("artifact") == "",
			"an older save's empty slots get the scrap piece they always deployed with")
	var service := Accounts.new()
	service.persist = false
	var signed := service.sign_in("Bare", Accounts.new_secret())
	var id := str(signed.get("account_id", ""))
	t.check(service.snapshot(id).loadout == StashRules.starter_loadout(), "a new account starts in the scrap kit too")
	for slot: String in Loadout.SLOTS:
		service.unequip(id, slot)
	t.check(service.snapshot(id).loadout.is_empty() and service.deploy(id, Arena.ArenaVenue.new()).kit.all(
				func(gear: String) -> bool: return gear == Loadout.BARE or ItemDB.has_tag(gear, "heal")),
			"an account taken bare deploys bare (healing from the stash aside)")
	t.check(service.equip(id, "sidearm", "pistol_service").ok and service.snapshot(id).loadout == {"sidearm": "pistol_service"},
			"and can put the free sidearm back on")


## A bare body in a world, the plaza and the arena: nothing worn, nothing in
## hand, and everything you can press still safe.
static func _raids(t: Node) -> void:
	var bare: Array[String] = [Loadout.BARE]
	for world: WorldDef in [Worlds.get_world("ashfront"), Worlds.social_world(), Arena.ArenaVenue.new()]:
		var raid: Raid = world.new_raid()
		t.add_child(raid)
		raid.start(world, 5, bare)
		await t.frames(5)
		var p := raid.player
		t.check(p != null and _is_bare(p), "%s: you arrive bare" % world.id)
		if p == null:
			raid.queue_free()
			continue
		await _press_everything(t, p)
		t.check(is_instance_valid(p) and _is_bare(p),
				"%s: every key is safe with nothing in hand" % world.id)
		raid.queue_free()
		await t.frames(2)
	var arena: Raid = Arena.ArenaVenue.new().new_raid()
	t.add_child(arena)
	arena.start(Arena.ArenaVenue.new(), 6, ["field_dressing"] as Array[String])
	await t.frames(3)
	t.check(arena.player != null and _is_bare(arena.player),
			"the pit takes away healing and vehicles, and what is left of a kit of only those is bare")
	arena.queue_free()
	await t.frames(2)


static func _is_bare(p: Actor) -> bool:
	return p.weapons.is_empty() and p.frame_id == "" and not p.visor.enabled and not p.flight.enabled \
			and not p.ability.enabled and not p.artifact.enabled and p.gear_items.is_empty()


static func _press_everything(t: Node, p: Actor) -> void:
	for step in 6:
		p.cmd.primary = step % 2 == 0
		p.cmd.primary_pressed = step % 2 == 0
		p.cmd.secondary = step == 1
		p.cmd.tertiary_pressed = step == 2
		p.cmd.reload_pressed = step == 3
		p.cmd.heal_pressed = step == 3
		p.cmd.ability_pressed = step == 4
		p.cmd.artifact_pressed = step == 4
		p.cmd.visor_pressed = step == 5
		p.cmd.sprint_pressed = step == 5
		p.cmd.jump_pressed = step == 1
		p.cmd.watch_up = step >= 2
		p.cmd.switch_weapon = [0, 1, 2, ActorCommand.HOLSTER, -1, 0][step]
		await t.frames(4)
	p.cmd.primary = false
	p.cmd.switch_weapon = -1
	p.cmd.watch_up = false
	await t.frames(4)


## The whole trip solo: a bare base, the watch, a world in both views, and
## the arena, all with nothing worn.
static func _solo_trip(t: Node) -> void:
	Profile.reset()
	Profile.welcome_granted = true
	for slot: String in Loadout.SLOTS:
		Profile.unequip(slot)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	t.add_child(main)
	await t.frames(20)
	t.check(main.base != null and main.base.suit_kit().is_empty() and main.base.player != null
			and _is_bare(main.base.player), "your base dresses you in nothing when nothing is equipped")
	t.check(main.base.display_for("rifle_scrap") != null and not main.base.display_for("rifle_scrap").equipped,
			"the scrap rifle hangs on the rack, not worn")
	t.check(main.base.watch_weapons().has("rifle_scrap"), "and is on the watch at home, to put on from there")
	main.base.display_for("rifle_scrap").interact(main.base.player)
	await t.frames(4)
	t.check(Profile.equipped("primary") == "rifle_scrap" and main.base.player.weapons.size() == 1,
			"taking the scrap rifle off the rack puts it straight on")
	main.base.display_for("rifle_scrap").interact(main.base.player)
	await t.frames(4)
	t.check(Profile.loadout.is_empty() and main.base.player.weapons.is_empty(),
			"and taking it off again leaves your hands empty, with nothing put in its place")
	main.start_raid("ashfront")
	await t.frames(10)
	var p: Actor = main.raid.player if main.raid != null else null
	t.check(p != null and _is_bare(p), "out in a world you are as bare as at home")
	if p != null and main.controller != null:
		for view in 2:
			main.controller.wrist_raised = true
			for i in 12:
				main.controller.scroll(-1 if i < 6 else 1)
				await t.frames(1)
			main.controller.click_watch()
			main.controller.wrist_raised = false
			await _press_everything(t, p)
			t.check(is_instance_valid(p) and _is_bare(p) and main.hud != null
					and Hud.weapon_entries(p).is_empty(),
					"%s person: the watch and every key work with nothing to summon"
					% ("third" if main.controller.is_third_person() else "first"))
			main.controller.toggle_view()
			await t.frames(3)
		p.kill("test")
		await t.frames(5)
	t.check(Profile.loadout.is_empty(), "dying bare loses nothing and puts nothing on")
	main.queue_free()
	await t.frames(5)
