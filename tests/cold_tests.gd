extends RefCounted
## Checks for Frostline's cold (DESIGN.md section 2, "Frostline"): body heat
## drains out in the open, faster up the valley and up in the wind, comes
## back at heaters, vents and running engines, and hurts through
## `Combat.deal` once it is gone; the views read it. Kept in its own file and
## called from the test runner.

const MapScript := preload("res://worlds/frostline/map.gd")
const Locomotion := preload("res://core/visual/locomotion.gd")


static func run(t: Node) -> void:
	_rules(t)
	Raid.zone_rules = true
	var raid := Raid.new()
	t.add_child(raid)
	raid.start(Worlds.get_world("frostline"), 4242)
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
		bot.set_physics_process(false)
		bot.global_position = Vector3(500, 0, 500)
	await t.frames(3)
	_warmth_on_the_map(t, raid)
	await _drain_and_warm(t, raid)
	await _engines(t, raid)
	await _freezing(t, raid)
	_views(t, raid)
	raid.queue_free()
	await t.frames(2)
	Raid.zone_rules = false


static func _rules(t: Node) -> void:
	print("The cold: rules")
	var frost := Worlds.get_world("frostline")
	var floor_mid := MapScript.floor_at(0.0)
	t.check(frost.cold > 0.0 and Worlds.get_world("ashfront").cold == 0.0 and Worlds.get_world("plaza").cold == 0.0,
			"Frostline is cold, Ashfront and the plaza are not")
	t.check(frost.cold_at(Vector3(0, MapScript.floor_at(260.0), 260.0)) < frost.cold_at(Vector3(0, floor_mid, 0.0))
			and frost.cold_at(Vector3(0, floor_mid, 0.0)) < frost.cold_at(Vector3(0, MapScript.floor_at(-230.0), -230.0)),
			"it gets colder up the valley, from the river mouth to the glacier head")
	t.check(frost.cold_at(Vector3(0, floor_mid + MapScript.RIM, 0.0)) > frost.cold_at(Vector3(0, floor_mid, 0.0))
			and is_equal_approx(frost.cold_at(Vector3(0, floor_mid + MapScript.SHELF, 0.0)), frost.cold_at(Vector3(0, floor_mid, 0.0))),
			"and colder up on the rims and in the air, while the shelves are as cold as the floor below")
	t.check(ActorCommand.STATE_CHILLED & (ActorCommand.HELD_MASK | ActorCommand.ONE_SHOT_MASK
			| ActorCommand.STATE_HOVERING | ActorCommand.STATE_SHELTERED | ActorCommand.STATE_SIGN_OUT_BEACON) == 0,
			"the shivering bit in the state is no input and no other state")


static func _warmth_on_the_map(t: Node, raid: Raid) -> void:
	print("The cold: warmth on the map")
	var heaters := raid.warmth.filter(func(w: Node3D) -> bool:
		return is_equal_approx(float(w.get_meta("warmth")), MapScript.HEATER["warmth"]))
	var vents := raid.warmth.filter(func(w: Node3D) -> bool:
		return is_equal_approx(float(w.get_meta("warmth")), MapScript.VENT["warmth"]))
	t.check(heaters.size() >= MapScript.HUTS.size() + MapScript.POSTS.size(),
			"every heater hut and strongpoint hut has a heater (%d)" % heaters.size())
	t.check(vents.size() == MapScript.VENTS.size(), "the floor has its warm vents")
	var mouth := false
	var core := false
	for w in raid.warmth:
		mouth = mouth or raid.world.zone_at(w.global_position) == 0 and w.global_position.z > 250.0
		core = core or raid.world.zone_at(w.global_position) == 2
	t.check(mouth and core, "there is warmth at the river mouth and at the glacier head")
	var floor_vents := vents.all(func(w: Node3D) -> bool:
		return absf(w.global_position.y - raid.map.call("ground_height", w.global_position.x, w.global_position.z)) < 0.5)
	t.check(floor_vents, "the vents lie on the ground, where anyone can walk to them")


static func _put(raid: Raid, actor: Actor, at: Vector3) -> void:
	actor.global_position = raid._stand(Vector3(at.x, raid.map.call("ground_height", at.x, at.z), at.z))
	actor.velocity = Vector3.ZERO


static func _drain_and_warm(t: Node, raid: Raid) -> void:
	print("The cold: body heat")
	var me := raid.player
	t.check(me.body_heat > me.max_body_heat - 1.0 and not me.shivering, "you set out warm")
	# Out in the open, in the Narrows, away from any vent.
	_put(raid, me, Vector3(MapScript.centre(0.0) - 20.0, 0, 0.0))
	await t.frames(1)
	t.check(raid.warmth_at(me) == 0.0, "the open floor has no warmth")
	me.body_heat = 50.0
	await t.frames(60)
	var lost := 50.0 - me.body_heat
	t.check(lost > 0.5 and lost < 2.0 and not me.warming,
			"out in the open body heat drains (%.2f in a second)" % lost)
	# A Thermal Frame keeps out part of the cold.
	Loadout.wear_frame(me, "frame_thermal")
	me.body_heat = 50.0
	await t.frames(60)
	var insulated := 50.0 - me.body_heat
	t.check(insulated > 0.0 and insulated < lost * 0.75 and is_equal_approx(Raid.insulation_of(me), 0.4),
			"a Thermal Frame keeps out some of the cold (%.2f against %.2f)" % [insulated, lost])
	Loadout.wear_frame(me, "")
	me.body_heat = 30.0
	await t.frames(2)
	t.check(me.shivering, "cold enough, you shiver")
	# Into a heater hut.
	var heater: Node3D = null
	for w in raid.warmth:
		if is_equal_approx(float(w.get_meta("warmth")), MapScript.HEATER["warmth"]):
			heater = w
			break
	me.global_position = heater.global_position + Vector3(0, 0.1, 0)
	me.velocity = Vector3.ZERO
	await t.frames(60)
	t.check(me.warming and me.body_heat > 35.0,
			"a heater warms you back up (%.1f after a second)" % me.body_heat)
	t.check(raid.zone_label(me).ends_with("· warm"), "the watch says you are somewhere warm")
	me.body_heat = 60.0
	await t.frames(2)
	t.check(not me.shivering, "warm again, the shivering stops")
	me.body_heat = me.max_body_heat
	await t.frames(30)
	t.check(me.body_heat == me.max_body_heat, "warmth never fills you past full")


static func _engines(t: Node, raid: Raid) -> void:
	print("The cold: engines")
	var me := raid.player
	var at := Vector3(MapScript.centre(60.0) - 25.0, 0, 60.0)
	_put(raid, me, at)
	var bike := raid.spawn_vehicle("bike_scrapper", me.global_position + Vector3(3, 0, 0), 0.0)
	await t.frames(2)
	t.check(raid.warmth_at(me) == 0.0, "a parked vehicle nobody rides is cold")
	var bot := raid.bots[0]
	bot.global_position = bike.global_position + Vector3(0, 0.5, 0)
	t.check(bike.call("mount", bot), "someone gets on")
	await t.frames(2)
	t.check(raid.warmth_at(me) == raid.world.engine_warmth and raid.warmth_at(bot) == raid.world.engine_warmth,
			"a running engine warms its rider and anyone standing close")
	bike.call("dismount")
	await t.frames(2)
	raid.remove_vehicle(bike)
	await t.frames(2)


static func _freezing(t: Node, raid: Raid) -> void:
	print("The cold: freezing")
	var me := raid.player
	_put(raid, me, Vector3(MapScript.centre(0.0) - 20.0, 0, 0.0))
	await t.frames(1)
	me.protected_left = 0.0
	me.health.health = me.health.max_health
	var armor := me.health.armor
	me.body_heat = 0.0
	await t.frames(130)
	t.check(me.health.health < me.health.max_health, "with no body heat left, the cold hurts")
	t.check(me.health.armor == armor, "and it goes past armor")
	me.health.health = me.health.max_health
	me.protected_left = 5.0
	await t.frames(70)
	t.check(me.health.health == me.health.max_health, "it goes through Combat.deal, so drop-in protection stops it")
	me.body_heat = me.max_body_heat


static func _views(t: Node, raid: Raid) -> void:
	print("The cold: what you see")
	var me := raid.player
	var bars := Hud.wrist_bars(me)
	t.check(bars.size() == 5 and bars[4] >= 0.0 and Hud.feels_cold(me), "the watch has a body heat bar in the cold")
	var glass := VisorHud.new()
	var kinds := glass.vital_cells(me, Color.WHITE).map(func(c: Dictionary) -> String: return c.kind)
	t.check("body_heat" in kinds, "the visor has a body heat cell in the cold")
	me.body_heat = 10.0
	me.shivering = true
	var cell: Dictionary = glass.vital_cells(me, Color.WHITE).filter(
			func(c: Dictionary) -> bool: return c.kind == "body_heat")[0]
	t.check(cell.label == "COLD" and cell.warn, "cold, the cell warns")
	glass.free()
	me.body_heat = me.max_body_heat
	me.shivering = false
	var loco: Locomotion = Locomotion.new()
	loco.actor = me
	me.shivering = true
	loco.update(0.5)
	t.check(loco.shiver > 0.0 and loco.shiver < 1.0, "shivering comes on gently, not at once")
	me.shivering = false
	loco.free()
