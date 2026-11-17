extends RefCounted
## Sign-out tension (DESIGN.md section 7): 15 s on the ground, 25 s in the
## air with a beacon, and a heavy weapon banked home to the armory wall.
## Called from the test runner (`-- --only` does not reach this file; the
## runner calls `run`).

const StashRules := preload("res://core/account/stash_rules.gd")
const BaseLayout := preload("res://core/base/base_layout.gd")
const Economy := preload("res://core/economy/economy.gd")
const SessionScript := preload("res://core/net/net_session.gd")
const ArenaVenue := preload("res://core/arena/arena_venue.gd")


static func run(t: Node) -> void:
	print("Extraction: heavy weapons on the wall")
	_rules(t)
	await _wall(t)
	await _sign_out(t)


static func _rules(t: Node) -> void:
	var ash := Worlds.get_world("ashfront")
	var frost := Worlds.get_world("frostline")
	var plaza := Worlds.get_world("plaza")
	t.check(is_equal_approx(ash.sign_out_time, 15.0) and is_equal_approx(ash.sign_out_air_time, 25.0)
			and is_equal_approx(ash.outpost_sign_out_time, 3.0),
			"Ashfront signs out in 15 s on the ground, 25 s in the air, and 3 s at a gate")
	t.check(is_equal_approx(plaza.sign_out_time, 1.0) and is_equal_approx(plaza.sign_out_air_time, 1.0),
			"the plaza keeps its short sign-out")
	t.check(ash.carries_power_weapons() and not frost.carries_power_weapons()
			and not plaza.carries_power_weapons() and not ArenaVenue.new().carries_power_weapons(),
			"only a PvP world lets you deploy with a heavy from the wall")
	t.check(Loadout.fits("power", "power_rail_lance") and not Loadout.fits("primary", "power_rail_lance")
			and Loadout.slot_of("power_rail_lance") == "power",
			"a heavy fits the power slot and never the primary")
	t.check(StashRules.storable("power_rail_lance") and Economy.sell_price("power_rail_lance") == 1000
			and not Economy.is_shop_item("power_rail_lance") and not Economy.for_sale("armory", "power_rail_lance"),
			"a heavy can be stored and sells back for 1,000, and no shop stocks it")
	var selling: Array[String] = ["power_rail_lance"]
	var sold := Economy.sell(selling, {}, 0, "power_rail_lance")
	t.check(sold.ok and sold.earned == 1000 and selling.is_empty(), "the trader buys a banked heavy back")
	var stash: Array[String] = ["power_helion", "rifle_carbine"]
	var loadout := {"primary": "rifle_carbine", "power": "power_helion"}
	var taken: Array[String] = []
	var kit := StashRules.checkout(stash, loadout, ash, taken)
	t.check("power_helion" in kit and "power_helion" in taken and "power_helion" not in stash,
			"deploying into Ashfront takes the heavy out of the stash")
	var stayed: Array[String] = ["power_helion", "rifle_carbine"]
	var left_behind := StashRules.checkout(stayed, loadout.duplicate(), frost)
	t.check("power_helion" not in left_behind and "power_helion" in stayed,
			"Frostline leaves the heavy on the wall")
	var safe: Array[String] = ["power_helion"]
	t.check("power_helion" not in StashRules.checkout(safe, {"power": "power_helion"}, plaza)
			and "power_helion" in safe, "a safe zone does not empty the chamber onto you")
	var actor := Actor.new()
	t.add_child(actor)
	Loadout.equip(actor, kit)
	await t.frames(2)
	t.check(Loadout.power_index(actor) >= 0 and actor.get_active_weapon() != null
			and actor.get_active_weapon().item_id == "rifle_carbine",
			"the heavy deploys into the chamber, and the primary stays in hand")
	actor.queue_free()
	t.check(BaseLayout.kind_for("power_storm_cannon") == "heavy_wall"
			and BaseLayout.spots("heavy_wall") == 0
			and BaseLayout.spots("heavy_wall", ["armory_alcove", "heavy_wall"]) == 4,
			"heavies have a wall of their own, empty until that upgrade is bought")
	var plan := BaseLayout.plan(["power_rail_lance", "power_rail_lance", "power_helion"],
			{"power": "power_rail_lance"}, ["armory_alcove", "heavy_wall"])
	var rails: Array = plan.filter(func(e: Dictionary) -> bool: return e.id == "power_rail_lance")
	var helions: Array = plan.filter(func(e: Dictionary) -> bool: return e.id == "power_helion")
	t.check(plan.size() == 2 and rails.size() == 1 and rails[0].count == 2 and rails[0].equipped
			and helions.size() == 1 and not helions[0].equipped and rails[0].kind == "heavy_wall",
			"copies stack on one spot, and the one you will deploy is marked")
	t.check(BaseLayout.plan(["power_rail_lance", "power_helion"], {}).is_empty()
			and BaseLayout.stored_away(["power_rail_lance", "power_helion"], []) == {"heavy_wall": 2},
			"without the wall, banked heavies are owned and not on show")
	t.check(ActorCommand.STATE_SIGN_OUT_BEACON & (ActorCommand.HELD_MASK | ActorCommand.ONE_SHOT_MASK
			| ActorCommand.STATE_HOVERING | ActorCommand.STATE_SHELTERED) == 0,
			"the beacon bit is not an input and not another state bit")


static func _wall(t: Node) -> void:
	var base := HomeBase.new()
	base.upgrades = ["armory_alcove", "heavy_wall"]
	var at0 := base.spot_transform("heavy_wall", 0).origin
	var at3 := base.spot_transform("heavy_wall", 3).origin
	t.check(base.in_armory(at0) and base.in_armory(at3) and at0.y > 3.5,
			"the heavy wall hangs inside the armory, above the long guns")
	t.add_child(base)
	base.show_gear(["power_rail_lance", "power_rail_lance"], {"power": "power_rail_lance"},
			["armory_alcove", "heavy_wall"])
	await t.frames(2)
	var shown: Array = base.displays.filter(func(d: HomeBase.Display) -> bool: return d.kind == "heavy_wall")
	t.check(shown.size() == 1 and shown[0].count == 2 and shown[0].equipped and shown[0].slot == "power"
			and shown[0].get_prompt().begins_with("[F] Take off"),
			"the wall shows the stack, and the equipped one can be taken off")
	t.check(base.player != null and Loadout.power_index(base.player) < 0,
			"at home the heavy stays on the wall, not in your hands")
	base.queue_free()
	await t.frames(2)


static func _sign_out(t: Node) -> void:
	print("Extraction: sign-out rates, beacon, banking")
	Profile.reset()
	var raid: Raid = await t._new_raid(77, false)
	var p := raid.player
	var state := raid.state_for(p)
	# Clear the spawn fight window. Nothing has hit them.
	state.last_combat = -INF

	print("Extraction: ground, air, gate, disconnect")
	t.check(raid.begin_sign_out(p) and is_equal_approx(state.sign_out_left, 15.0)
			and is_equal_approx(state.sign_out_total, 15.0) and not p.sign_out_beacon,
			"a sign-out on the ground is 15 seconds and raises no beacon")
	raid._tick_sign_outs(10.0)
	t.check(is_equal_approx(state.sign_out_left, 5.0), "ten seconds on the ground leaves five")
	p.airborne_time = 1.0
	raid._tick_sign_outs(0.0)
	t.check(is_equal_approx(state.sign_out_left, 25.0 / 3.0) and is_equal_approx(state.sign_out_total, 25.0)
			and p.sign_out_beacon and p.get_node_or_null("SignOutBeacon") != null,
			"lifting off keeps the progress and switches to the 25 s rate, beacon up")
	var beam := p.get_node("SignOutBeacon")
	t.check(beam.get_child_count() > 0 and (beam.get_child(0) as Node).has_meta("uncloaked"),
			"the column is marked so a cloak cannot hide it")
	p.airborne_time = 0.0
	raid._tick_sign_outs(0.0)
	t.check(is_equal_approx(state.sign_out_left, 5.0) and is_equal_approx(state.sign_out_total, 15.0)
			and not p.sign_out_beacon and p.get_node_or_null("SignOutBeacon") == null,
			"landing drops the timer back to the ground rate and takes the beacon down")
	raid.cancel_sign_out(p)

	p.airborne_time = 1.0
	t.check(raid.begin_sign_out(p) and is_equal_approx(state.sign_out_left, 25.0),
			"starting in the air is a 25 second sign-out")
	raid._tick_sign_outs(10.0)
	t.check(is_equal_approx(state.sign_out_left, 15.0) and p.sign_out_beacon, "ten seconds in the air leaves fifteen")
	p.airborne_time = 0.0
	raid._tick_sign_outs(0.0)
	t.check(is_equal_approx(state.sign_out_left, 9.0) and is_equal_approx(state.sign_out_total, 15.0),
			"landing after 10 s of air leaves 9 s, the ground rate's remainder")
	raid.cancel_sign_out(p)

	state.sheltered = true
	p.airborne_time = 2.0
	t.check(raid.begin_sign_out(p) and is_equal_approx(state.sign_out_left, raid.world.outpost_sign_out_time)
			and not p.sign_out_beacon, "a gate sign-out stays short and quiet, even off the floor")
	raid._tick_sign_outs(1.0)
	t.check(is_equal_approx(state.sign_out_left, raid.world.outpost_sign_out_time - 1.0) and not p.sign_out_beacon,
			"the gate countdown does not switch to the air rate")
	state.sheltered = false
	raid.cancel_sign_out(p)
	p.airborne_time = 0.0

	# A second add_player in solo replaces the body, so the disconnect wait is
	# checked on this same player and then released.
	p.airborne_time = 3.0
	t.check(raid.begin_sign_out(p, true) and is_equal_approx(state.sign_out_left, raid.world.sign_out_time)
			and not p.sign_out_beacon, "a disconnect uses the ground sign-out and raises no beacon")
	var stuck := state.sign_out_left
	raid.cancel_sign_out(p)
	raid._tick_sign_outs(0.5)
	t.check(is_equal_approx(state.sign_out_left, stuck - 0.5) and not p.sign_out_beacon,
			"that sign-out cannot be called off, and being in the air does not lengthen it")
	state.sign_out_forced = false
	state.sign_out_fixed = false
	raid.cancel_sign_out(p)
	p.airborne_time = 0.0

	print("Extraction: the beacon is server state, and bots hear it")
	p.airborne_time = 1.0
	var started := raid.begin_sign_out(p)
	raid._tick_sign_outs(0.0)
	var session = SessionScript.new()
	session.raid = raid
	session._actors[3] = p
	var entry: Array = session._state_entry(3, 0)
	var bits := int(entry[3][ActorCommand.FLAGS_INDEX])
	t.check(started and p.sign_out_beacon and bits & ActorCommand.STATE_SIGN_OUT_BEACON != 0,
			"the server's state says the beacon is up")
	var viewer := Actor.new()
	raid.add_child(viewer)
	session._apply_state(viewer, entry, false)
	t.check(viewer.sign_out_beacon and viewer.get_node_or_null("SignOutBeacon") != null,
			"a client draws the column from that state")
	p.set_sign_out_beacon(false)
	entry = session._state_entry(3, 0)
	session._apply_state(viewer, entry, false)
	t.check(not viewer.sign_out_beacon and viewer.get_node_or_null("SignOutBeacon") == null,
			"the column goes when the server drops the bit")
	viewer.queue_free()
	# The raid still has the player signing out in the air. Put the column back
	# the way the authority would, then see who hears the next pulse.
	raid._tick_sign_outs(0.0)
	t.check(p.sign_out_beacon, "the authority raises the column again")
	var near: Actor = raid.bots[0]
	var far: Actor = raid.bots[1]
	near.global_position = p.global_position + Vector3(20, 0, 0)
	far.global_position = p.global_position + Vector3(0, 0, Raid.SIGN_OUT_BEACON_HEAR + 40.0)
	var heard_near := [false]
	var heard_far := [false]
	near.heard.connect(func(_at: Vector3, source: Actor) -> void:
		heard_near[0] = source == p)
	far.heard.connect(func(_at: Vector3, _source: Actor) -> void:
		heard_far[0] = true)
	state.beacon_hum = 0.0
	raid._tick_sign_outs(0.05)
	t.check(heard_near[0] and not heard_far[0], "a bot near the beacon hears it, and one past its reach does not")
	raid.cancel_sign_out(p)
	p.airborne_time = 0.0

	print("Extraction: a cloak pauses the countdown and leaves the column")
	p.global_position += Vector3(0, 40, 0)
	p.velocity = Vector3.ZERO
	p.airborne_time = 1.0
	raid.begin_sign_out(p)
	await t.frames(3)
	t.check(p.sign_out_beacon and p.get_node_or_null("SignOutBeacon") != null, "the column is up while they fall")
	p.artifact.effect = "cloak"
	p.artifact.active_left = 5.0
	var left := state.sign_out_left
	await t.frames(20)
	var column := p.get_node_or_null("SignOutBeacon") as Node3D
	var solid := column != null and column.visible
	if column != null:
		for child in column.find_children("*", "GeometryInstance3D", true, false):
			solid = solid and (child as GeometryInstance3D).visible
	t.check(p.is_cloaked() and is_equal_approx(state.sign_out_left, left) and solid,
			"while cloaked the countdown waits and the column stays visible")
	p.artifact.active_left = 0.0
	raid.cancel_sign_out(p)
	p.velocity = Vector3.ZERO
	p.global_position = raid._stand(p.global_position)

	print("Extraction: banking the chamber, then signing it out")
	for id in p.inventory.items.duplicate():
		if not ItemDB.has_tag(id, "heal"):
			p.inventory.remove_item(id)
	Loadout.set_power(p, "power_rail_lance", 2, 0, false)
	t.check(Depot.bankable(p) == ["power_rail_lance"], "the depot banks the chamber and not the healing")
	var depot: Depot = raid.depots[0]
	p.global_position = Vector3(depot.global_position.x, depot.global_position.y - 1.8, depot.global_position.z)
	p.velocity = Vector3.ZERO
	await t.frames(8)
	t.check(depot.progress_for(p) > 0.0, "standing in a depot with only a heavy starts the upload")
	await t.frames(int(raid.world.depot_hold_time * 60.0) + 20)
	t.check("power_rail_lance" in Profile.stash and Loadout.power_index(p) < 0,
			"the upload sends the heavy home and clears the chamber")
	t.check(raid.bank_progress() == 0.0 or depot.progress_for(p) == 0.0, "with the chamber empty the upload stops")

	Loadout.set_power(p, "power_helion", -1, -1, false)
	state.last_combat = -INF
	var results: Array[Dictionary] = []
	raid.player_finished.connect(func(_a: Actor, result: Dictionary) -> void: results.append(result))
	t.check(raid.begin_sign_out(p), "a sign-out can still start after banking")
	state.sign_out_left = 0.15
	await t.frames(20)
	t.check(results.size() == 1 and results[0].outcome == "left" and "power_helion" in results[0].brought_home
			and "power_rail_lance" in results[0].banked and "power_helion" in Profile.stash,
			"signing out brings the chambered heavy home, and the banked one was already there")
	await t._end_raid(raid)
