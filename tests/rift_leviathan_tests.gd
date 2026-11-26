extends RefCounted
## The Sky Leviathan (`worlds/rift/`, DESIGN.md "The Basalt Rift (part two)",
## Caleb's call: a world event that fights and falls): an armoured airship
## drifts along one of the map's routes over the rift, its weak spots at
## three heights (engine pods low, spine plates on its back, turrets on its
## tower). Its turrets fire on whoever is near, a broken weak spot drops
## salvage under it, and with all of them broken it goes down and its hold
## lands where it crashes, on top of the lava. Left alone it drifts off.
## The runner finds this file by itself.

const RiftWorld := preload("res://worlds/rift/world.gd")


static func run(t: Node) -> void:
	print("Basalt Rift: the Sky Leviathan")
	var world := Worlds.get_world("rift")
	_check_data(t, world)
	var raid := world.new_raid()
	t.add_child(raid)
	raid.start(world, 7)
	await t.frames(3)
	var map: Node3D = raid.map
	var me := raid.player
	me.protected_left = 999.0
	t.check(raid.start_event("airship"), "rift: the Sky Leviathan comes in as a world event")
	t.check(raid.event.get("title", "") == "Sky Leviathan", "rift: the event is named for it (%s)" % raid.event.get("title", ""))
	var ship: Node3D = raid.airship.get("ship")
	t.check(ship != null and ship in raid.vehicles and bool(ship.get("floats")),
			"rift: it is an airship in the world")
	t.check(ship.get_node_or_null("Seat") == null, "rift: nobody can climb aboard or pack it")
	var parts := _parts(ship)
	var kinds := {}
	for bot: Actor in parts:
		kinds[str(bot.get_meta("boss", ""))] = int(kinds.get(str(bot.get_meta("boss", "")), 0)) + 1
	t.check(parts.size() == RiftWorld.LEVIATHAN_SEATS.size() and kinds.get("leviathan_pod", 0) == 4
			and kinds.get("leviathan_spine", 0) == 2 and kinds.get("leviathan_turret", 0) == 2,
			"rift: a weak spot on every seat: 4 engine pods, 2 spine plates, 2 turrets (%s)" % str(kinds))
	t.check(parts.all(func(b: Actor) -> bool: return b.faction == RiftWorld.LEVIATHAN_FACTION and raid.bots.has(b)),
			"rift: they are the ship's own, not the rift's soldiers")
	var pod := _part(parts, "leviathan_pod")
	var spine := _part(parts, "leviathan_spine")
	var turret := _part(parts, "leviathan_turret")
	t.check(is_equal_approx(pod.body_radius, 1.5) and pod.inventory.items.is_empty(),
			"rift: an engine pod is a fat target and carries nothing")
	t.check(turret.get_active_weapon() != null and turret.get_active_weapon().item_id == RiftWorld.LEVIATHAN_GUN
			and turret.get_node("Brain").process_mode != Node.PROCESS_MODE_DISABLED
			and pod.get_node("Brain").process_mode == Node.PROCESS_MODE_DISABLED,
			"rift: a turret mans its gun; the pods and plates only take the hits")
	# Three heights: the pods low, the plates on its back, the turrets on top.
	await t.frames(2)
	var low := pod.global_position.y
	var mid := spine.global_position.y
	var high := turret.global_position.y
	t.check(low + 6.0 < mid and mid + 3.0 < high, "rift: weak spots at three heights (%.0f, %.0f, %.0f m)" % [low, mid, high])
	# It drifts along its route.
	var route: Array = raid.airship.route
	var start := ship.global_position
	await t.frames(240)
	var flat := Vector2(ship.global_position.x - start.x, ship.global_position.z - start.z)
	var way := Vector2(route[1].x - start.x, route[1].z - start.z).normalized()
	t.check(flat.dot(way) > 8.0, "rift: it drifts along its route (%.0f m in 4 s)" % flat.dot(way))
	t.check(_parts(ship).size() == parts.size(), "rift: its weak spots ride along with it")
	# A spine plate is soft to a dive from above.
	var side_hit := _hit(spine, me, spine.global_position + Vector3(30, 1, 0))
	var dive_hit := _hit(spine, me, spine.global_position + Vector3(2, 30, 0))
	t.check(dive_hit > side_hit * 2.0, "rift: a spine plate takes a dive from above hard (%.0f against %.0f)" % [dive_hit, side_hit])
	_check_same_part(t, raid, pod)
	await _check_client_view(t, raid, ship)
	await _check_turret(t, raid, ship, turret)
	await _check_breaking(t, raid, map, ship, pod)
	await _check_down(t, raid, map, ship)
	await _check_drift_off(t, raid)
	await t._end_raid(raid)


## The routes and the reach: the pods hang in a Mk1 jetpack's reach from
## the lava over the rift, the plates and turrets above any rig's ceiling.
static func _check_data(t: Node, world: WorldDef) -> void:
	t.check(world.airship_vehicle == RiftWorld.LEVIATHAN and ItemDB.has_tag(world.airship_vehicle, "airship")
			and not ItemDB.has_tag(world.airship_vehicle, "vehicle"),
			"rift: its airship is an item of its own, never a vehicle to own")
	var map_script: GDScript = load("res://worlds/rift/map.gd")
	var routes: Array = map_script.get("AIRSHIP_ROUTES")
	var floor_y: float = map_script.get("FLOOR_Y")
	var field: float = map_script.get("FIELD")
	var mk1 := float(ItemDB.item_stats("jetpack_mk1").get("ceiling", 0.0))
	var pod_y := 0.0
	var spine_y := 0.0
	for row: Array in RiftWorld.LEVIATHAN_SEATS:
		if row[0] == "leviathan_pod":
			pod_y = (row[2] as Vector3).y
		elif row[0] == "leviathan_spine":
			spine_y = (row[2] as Vector3).y
	var pod_mid: float = RiftWorld.LEVIATHAN_PARTS["leviathan_pod"]["height"] * 0.5
	var reach := true
	var above := true
	for route: Array in routes:
		for point: Vector3 in route:
			# Its middle crossing, well inside the cliffs.
			if absf(point.x) > field * 0.7 or absf(point.z) > field * 0.7:
				continue
			# A jetpack held at its ceiling looks the pod in the eye.
			reach = reach and point.y + pod_y + pod_mid < floor_y + mk1 + 1.6
			above = above and point.y + spine_y > floor_y + mk1 + 5.0
	t.check(routes.size() >= 2 and reach and above,
			"rift: over the rift its pods hang in a Mk1's reach (%.0f m), its back and turrets above it" % (floor_y + mk1))


## The ship's weak spots aboard, alive.
static func _parts(ship: Node3D) -> Array[Actor]:
	var out: Array[Actor] = []
	for bot: Variant in ship.get("passengers"):
		if bot != null and is_instance_valid(bot) and not (bot as Actor).is_dead:
			out.append(bot)
	return out


static func _part(parts: Array[Actor], kind: String) -> Actor:
	for bot in parts:
		if bot.get_meta("boss", "") == kind:
			return bot
	return null


## What a 100-point hit from `from` takes off `bot`, healed after.
static func _hit(bot: Actor, source: Actor, from: Vector3) -> float:
	var was := source.global_position
	source.global_position = from
	var before := bot.health.health
	Combat.deal(bot, DamageInfo.make(100.0, source, "bullet", bot.global_position))
	var taken := before - bot.health.health
	bot.health.health = before
	source.global_position = was
	return taken


## A client builds a weak spot from what the server sends of it (its seed
## and its boss kind): the same body, health and armor.
static func _check_same_part(t: Node, raid: Raid, pod: Actor) -> void:
	var copy := raid.spawn_bot("PodCopy", pod.global_position + Vector3(0, 30, 0), int(raid.bot_seeds[pod]), false,
			pod.faction, int(pod.get_meta("zone", 0)), [], str(pod.get_meta("boss")))
	t.check(copy.display_name == pod.display_name and is_equal_approx(copy.body_radius, pod.body_radius)
			and is_equal_approx(copy.stand_height, pod.stand_height)
			and is_equal_approx(copy.health.max_health, pod.health.max_health)
			and is_equal_approx(copy.health.armor, pod.health.armor),
			"rift: a client builds the same weak spot from its seed and kind")
	raid._remove_actor(copy)


## A client moves the ship from the server's states and seats whoever the
## server says (its physics off): a weak spot's piece shows broken once its
## seat empties, from who sits where alone.
static func _check_client_view(t: Node, raid: Raid, ship: Node3D) -> void:
	var copy := raid.spawn_vehicle(str(ship.get("item_id")), ship.global_position + Vector3(0, 60, 0), 0.0)
	copy.set_physics_process(false)
	var stand_in := raid.spawn_bot("PodStandIn", copy.global_position, 1, false, "leviathan", 0, [], "leviathan_pod")
	copy.call("mount", stand_in, true, 0)
	await t.frames(2)
	var model: Node3D = copy.get_node("Model")
	var whole := (model.get_node("Part0") as Node3D).visible and not (model.get_node("Broken0") as Node3D).visible
	copy.call("get_off", stand_in)
	await t.frames(2)
	t.check(whole and not (model.get_node("Part0") as Node3D).visible and (model.get_node("Broken0") as Node3D).visible
			and (model.get_node("Part1") as Node3D).visible,
			"rift: on a client a weak spot shows broken once the server empties its seat")
	raid._remove_actor(stand_in)
	raid.remove_vehicle(copy)


## Someone hovering near its turrets gets shot at.
static func _check_turret(t: Node, raid: Raid, ship: Node3D, turret: Actor) -> void:
	var me := raid.player
	var gun: Gun = turret.get_active_weapon()
	me.protected_left = 0.0
	me.health.max_health = 99999.0
	me.health.health = 99999.0
	me.set_physics_process(false)
	var fired := false
	# Alone up there it takes its time to notice someone (about five
	# seconds); with the cult fighting round it, sooner.
	for i in 600:
		me.global_position = ship.global_position + Vector3(25.0, 16.0, 0.0)
		me.velocity = Vector3.ZERO
		await t.frames(1)
		if gun.ammo_in_mag < gun.mag_size:
			fired = true
			break
	t.check(fired, "rift: its turrets open up on a flyer close by")
	me.global_position = (raid.get_tree().get_nodes_in_group("spawn_player")[0] as Node3D).global_position + Vector3(0, 0.2, 0)
	me.health.max_health = 100.0
	me.health.health = 100.0
	me.protected_left = 999.0


## A broken weak spot: its salvage falls under the ship, its piece shows
## wrecked, and the ship flies on.
static func _check_breaking(t: Node, raid: Raid, map: Node3D, ship: Node3D, pod: Actor) -> void:
	var spawned: Array[LootContainer] = []
	var on_spawn := func(c: LootContainer) -> void: spawned.append(c)
	raid.container_spawned.connect(on_spawn)
	var seat: int = (ship.get("passengers") as Array).find(pod)
	var under := raid.drop_spot(pod)
	Combat.deal(pod, DamageInfo.make(99999.0, raid.player, "bullet", pod.global_position))
	await t.frames(3)
	t.check(pod.is_dead and (ship.get("passengers") as Array)[seat] == null, "rift: an engine pod breaks off")
	var salvage := spawned.filter(func(c: LootContainer) -> bool:
			return is_instance_valid(c) and not c.items.is_empty() and c.global_position.distance_to(under) < 12.0)
	t.check(not salvage.is_empty() and salvage[0].global_position.y >= map.LAVA_Y - 0.01,
			"rift: its salvage falls under the ship, never into the lava")
	var model: Node3D = ship.get_node("Model")
	t.check(not (model.get_node("Part%d" % seat) as Node3D).visible and (model.get_node("Broken%d" % seat) as Node3D).visible,
			"rift: its piece shows wrecked")
	t.check(not raid.event.is_empty() and not bool(raid.airship.down), "rift: the ship flies on")
	raid.container_spawned.disconnect(on_spawn)


## Every weak spot broken: it goes down, and its hold lands on the lava or
## the rock under it; the event is over.
static func _check_down(t: Node, raid: Raid, map: Node3D, ship: Node3D) -> void:
	var holds: Array[LootContainer] = []
	var on_spawn := func(c: LootContainer) -> void:
		if c.label.ends_with("hold"):
			holds.append(c)
	raid.container_spawned.connect(on_spawn)
	# Over the middle of the rift.
	var route: Array = raid.airship.route
	ship.global_position = route[route.size() / 2]
	await t.frames(2)
	for bot in _parts(ship):
		Combat.deal(bot, DamageInfo.make(99999.0, raid.player, "bullet", bot.global_position))
	await t.frames(3)
	t.check(bool(raid.airship.get("down", false)) and ship.get("course") == Vector3.INF,
			"rift: with every weak spot broken it goes down")
	var high := ship.global_position.y
	await t.frames(60)
	t.check(ship.global_position.y < high - 3.0, "rift: falling (%.0f m to %.0f m)" % [high, ship.global_position.y])
	var fell: bool = await t._wait_until(func() -> bool: return raid.event.is_empty(), 60 * 30)
	t.check(fell and not holds.is_empty() and holds[0].items.size() >= 4
			and holds[0].global_position.y >= map.LAVA_Y - 0.01,
			"rift: it crashes and its hold lands on top of whatever is under it (%d items)"
			% (holds[0].items.size() if not holds.is_empty() else 0))
	t.check(not is_instance_valid(ship) or ship.is_queued_for_deletion() or ship not in raid.vehicles,
			"rift: the wreck is gone, the event over")
	raid.container_spawned.disconnect(on_spawn)


## Left alone it crosses its route its passes, then drifts off with its
## weak spots.
static func _check_drift_off(t: Node, raid: Raid) -> void:
	t.check(raid.start_event("airship"), "rift: another one comes in")
	var ship: Node3D = raid.airship.ship
	var parts := _parts(ship)
	var route: Array = raid.airship.route
	raid.airship.passes = 1
	raid.airship.next = route.size() - 1
	var last: Vector3 = route[route.size() - 1]
	ship.global_position = last + Vector3(0, 0, 1)
	await t.frames(3)
	t.check(raid.event.is_empty() and (not is_instance_valid(ship) or ship.is_queued_for_deletion()),
			"rift: through its passes, it drifts off")
	t.check(parts.all(func(b: Variant) -> bool: return not is_instance_valid(b) or not raid.bots.has(b)),
			"rift: and its weak spots with it")
