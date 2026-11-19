extends RefCounted
## The core loop end to end, in each world where gear is at stake: deploy
## from the account, fight, loot, sign out, keep what came home, craft with
## it and deploy again with what was made; then a life that ends in death,
## and what the world's rules let the account keep. The account is a
## `StashService` and the world a server `Raid`, joined the way the online session
## joins them (deploy, `add_player`, `player_finished`, settle), with no
## network in between, so it runs in the offline tier.
## Called from the test runner (`-- --only` does not reach this file; the
## runner calls `run`).

const StashService := preload("res://core/account/stash_service.gd")
const Economy := preload("res://core/economy/economy.gd")

## A recipe whose blueprint and parts can all be found in a cache.
const CRAFT := "shotgun_breacher"
const CRAFT_FINDS: Array[String] = ["bp_shotgun_breacher", "alloy_ingot", "scrap_metal", "scrap_metal", "scrap_metal"]


static func run(t: Node) -> void:
	print("Core loop: drop in, fight, loot, get out, craft, go again")
	for world_id: String in ["ashfront", "frostline"]:
		await _loop(t, world_id)


static func _loop(t: Node, world_id: String) -> void:
	var world := Worlds.get_world(world_id)
	var service := StashService.new()
	service.persist = false
	var id: String = service.sign_in("Loop %s" % world_id, StashService.new_secret()).account_id
	service.change_scrip(id, 1000)
	t.check(service.equip(id, "primary", "rifle_carbine").get("ok", false),
			"%s: a new account equips the carbine from its crate" % world.display_name)

	var raid := Raid.new()
	t.add_child(raid)
	raid.mode = Raid.Mode.SERVER
	raid.start_server(world, 11)
	await t.frames(3)
	# Bots stand still: the loop is what is checked here, not a firefight.
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
	var results: Array = []
	raid.player_finished.connect(func(_a: Actor, result: Dictionary) -> void: results.append(result))

	# --- First life: fight, loot, sign out -----------------------------------
	var player := await _deploy(t, service, id, raid)
	if player == null:
		raid.queue_free()
		return
	var tag := world.display_name
	t.check("rifle_carbine" not in service.snapshot(id).stash,
			"%s: deployed gear leaves the stash" % tag)
	var scrip_before := service.scrip_of(id)

	var foe: Actor = raid.bots[0] if not raid.bots.is_empty() else null
	t.check(foe != null, "%s: there are bots to fight" % tag)
	if foe != null:
		Combat.deal(foe, DamageInfo.make(10000.0, player, "bullet", foe.global_position))
		await t.frames(2)
		t.check(foe.is_dead, "%s: the player can kill a bot" % tag)

	var cache := _nearest_cache(raid, player)
	t.check(cache != null, "%s: there is a cache to loot" % tag)
	if cache != null:
		cache.set_items(CRAFT_FINDS.duplicate())
		cache.interact(player)
		await t.frames(2)
		var picked := player.inventory.items.count("scrap_metal") >= 3 \
				and player.inventory.has_item("alloy_ingot") and player.inventory.has_item("bp_shotgun_breacher")
		t.check(picked, "%s: looting a cache puts it in the pack" % tag)

	await _sign_out(t, raid, player, world)
	t.check(results.size() == 1 and results[0].get("outcome", "") == "left",
			"%s: a finished sign-out ends the life as left" % tag)
	if results.size() != 1:
		raid.queue_free()
		return
	var settled := service.settle(id, results[0])
	var home := service.snapshot(id)
	t.check(settled.get("ok", false) and "rifle_carbine" in home.stash and not home.deployed,
			"%s: the gear is home after the sign-out" % tag)
	t.check("bp_shotgun_breacher" in home.get("blueprints", []) and "alloy_ingot" in home.stash
			and home.stash.count("scrap_metal") >= 3,
			"%s: what was looted is home, and the blueprint is learned" % tag)
	t.check(service.scrip_of(id) >= scrip_before, "%s: a sign-out never costs scrip" % tag)

	# --- Craft with what came home, and take it back out ---------------------
	var made := service.craft(id, CRAFT)
	t.check(made.get("ok", false) and CRAFT in service.snapshot(id).stash,
			"%s: the loot crafts a %s (%s)" % [tag, CRAFT, made.get("error", "ok")])
	t.check(service.equip(id, "primary", CRAFT).get("ok", false), "%s: the crafted gun equips" % tag)
	player = await _deploy(t, service, id, raid)
	if player == null:
		raid.queue_free()
		return
	t.check(CRAFT in player.gear_items and player.get_active_weapon() != null
			and player.get_active_weapon().item_id == CRAFT,
			"%s: the next life deploys with the crafted gun in hand" % tag)

	# --- Second life ends in death -------------------------------------------
	var killer: Actor = null
	for bot in raid.bots:
		if is_instance_valid(bot) and not bot.is_dead:
			killer = bot
			break
	player.protected_left = 0.0
	if killer != null:
		Combat.deal(player, DamageInfo.make(10000.0, killer, "bullet", player.global_position))
	await t.frames(5)
	t.check(results.size() == 2 and results[1].get("outcome", "") == "died",
			"%s: a death ends the life as died" % tag)
	if results.size() == 2:
		service.settle(id, results[1])
		var after := service.snapshot(id)
		t.check(not after.deployed, "%s: the account is free to deploy again after a death" % tag)
		if world.keep_gear_on_death:
			t.check(CRAFT in after.stash, "%s keeps worn gear on death: the crafted gun came home" % tag)
		else:
			t.check(CRAFT not in after.stash and after.loadout.get("primary", "") != CRAFT,
					"%s is full loot: the crafted gun is lost and the slot falls back" % tag)
			if world.death_drops_scrip:
				t.check(_pile_paying(raid, CRAFT), "%s: the gun is sold into the dead player's scrip pile" % tag)
			else:
				t.check(_bag_holding(raid, CRAFT), "%s: the gun lies in the dead player's bag" % tag)
	raid.queue_free()
	await t.frames(2)


## Deploys the account into `raid` the way the online session does and returns the
## new body, or null.
static func _deploy(t: Node, service: StashService, id: String, raid: Raid) -> Actor:
	var deployed := service.deploy(id, raid.world)
	t.check(deployed.get("ok", false), "%s: the account deploys (%s)"
			% [raid.world.display_name, deployed.get("error", "ok")])
	if not deployed.get("ok", false):
		return null
	var who := service.snapshot(id)
	var actor := raid.add_player(deployed.kit, deployed.picks, who.name, id, int(who.get("renown", 0)),
			"", str(deployed.get("insured", "")))
	await t.frames(5)
	return actor


static func _bag_holding(raid: Raid, item: String) -> bool:
	for node in raid.get_children():
		if node is LootContainer and (node as LootContainer).is_bag and item in (node as LootContainer).items:
			return true
	return false


## A scrip pile (DESIGN.md "Scrip piles") worth at least what a trader pays
## for `item`, with the item itself not in it.
static func _pile_paying(raid: Raid, item: String) -> bool:
	for node: Variant in raid.piles:
		if is_instance_valid(node) and item not in (node as LootContainer).items \
				and (node as LootContainer).scrip >= Economy.sell_price(item):
			return true
	return false


static func _nearest_cache(raid: Raid, actor: Actor) -> LootContainer:
	var best: LootContainer = null
	for node in raid.get_children():
		if node is LootContainer and not (node as LootContainer).is_bag and not (node as LootContainer).is_rack():
			if best == null or actor.global_position.distance_to(node.global_position) \
					< actor.global_position.distance_to(best.global_position):
				best = node
	return best


## Signs `actor` out, at a beacon where the world asks for one, and waits for
## the count to finish.
static func _sign_out(t: Node, raid: Raid, actor: Actor, world: WorldDef) -> void:
	# Out of the fight first: the kill just now counts as one.
	await t.frames(int(world.combat_time * 60.0) + 5)
	if world.sign_out_at_beacons and not raid.beacons.is_empty():
		var beacon: Node3D = raid.beacons[0]
		actor.global_position = beacon.global_position + Vector3(1.0, 0.5, 0.0)
		actor.velocity = Vector3.ZERO
		await t.frames(10)
	var started := raid.begin_sign_out(actor)
	t.check(started, "%s: the player can start a sign-out" % world.display_name)
	var wait := maxf(world.sign_out_time, world.beacon_sign_out_time if world.sign_out_at_beacons else 0.0)
	var ticks := 0
	# A body that signed out is freed with its life.
	while ticks < int(wait * 60.0) + 300 and is_instance_valid(actor) \
			and raid.state_for(actor) != null and not raid.state_for(actor).finished:
		await t.frames(10)
		ticks += 10
