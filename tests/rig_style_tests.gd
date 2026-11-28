extends RefCounted
## Checks for the aerial rigs' style pass (Caleb's call): each rig flies its
## own way. Wings swoop (a dive's speed buys height back on a pull-up, never
## more than it cost), boots kick off walls, and every rig is heard.
## Run from the main test runner. Nothing here starts a server.

const GameSettings := preload("res://core/settings/game_settings.gd")
const WeaponArmScript := preload("res://core/visual/weapon_arm.gd")


static func run(t: Node) -> void:
	print("Rig style")
	await _test_swoop(t)
	await _test_wall_kick(t)
	await _test_heard(t)
	await _test_looks(t)


static func _arena(t: Node, at: Vector3, size := Vector3(200, 1, 2000)) -> Node3D:
	var arena := Node3D.new()
	t.add_child(arena)
	arena.position = at
	var ground := StaticBody3D.new()
	ground.collision_layer = Actor.LAYER_WORLD
	var shape := BoxShape3D.new()
	shape.size = size
	var col := CollisionShape3D.new()
	col.shape = shape
	ground.add_child(col)
	ground.position = Vector3(0, -0.5, -size.z * 0.5 + 20.0)
	arena.add_child(ground)
	return arena


static func _actor(arena: Node3D, kit: Array) -> Actor:
	var actor := Actor.new()
	arena.add_child(actor)
	Loadout.equip(actor, ["pistol_service", "frame_trooper"] + kit)
	actor.position = Vector3(0, 0.05, 0)
	actor.ground_map = arena
	return actor


static func _flat_speed(p: Actor) -> float:
	return Vector2(p.velocity.x, p.velocity.z).length()


## Wings: dive for speed, then pull up and the speed turns back into height.
## The swoop never climbs higher than the dive began.
static func _test_swoop(t: Node) -> void:
	var arena := _arena(t, Vector3(-900, 0, 14000))
	var p := _actor(arena, ["wings_glide"])
	var f := p.flight
	await t.frames(5)
	p.global_position.y = 36.0
	p.velocity = Vector3(0, -1, -22)
	p.cmd.jump = true
	await t.frames(30)
	var top := p.global_position.y
	p.cmd.move = Vector2(0, 1)
	await t.frames(150)
	var fast := _flat_speed(p)
	var low := p.global_position.y
	p.cmd.move = Vector2(0, -1)
	var peak := low
	for i in 300:
		await t.get_tree().physics_frame
		peak = maxf(peak, p.global_position.y)
	print("  swoop: from %.1f m dove to %.1f m at %.1f m/s, pulled up to %.1f m (gained %.1f), now %.1f m/s" % [top, low, fast, peak, peak - low, _flat_speed(p)])
	t.check(f.is_gliding and fast > 26.0, "a dive builds speed past the glide's 22 m/s (%.1f)" % fast)
	t.check(peak - low > 4.0, "pulled up out of the dive, the speed buys height back (%.1f m)" % (peak - low))
	t.check(peak < top, "a swoop never climbs higher than the dive began (%.1f of %.1f m)" % [peak, top])
	p.cmd = ActorCommand.new()
	arena.queue_free()
	await t.frames(2)


## Boots: jump in the air beside a wall kicks up and away from it, free,
## once a time in the air; the next press is an ordinary kick on a charge.
static func _test_wall_kick(t: Node) -> void:
	var arena := _arena(t, Vector3(-1300, 0, 14000))
	var wall := StaticBody3D.new()
	wall.collision_layer = Actor.LAYER_WORLD
	var shape := BoxShape3D.new()
	shape.size = Vector3(1, 12, 10)
	var col := CollisionShape3D.new()
	col.shape = shape
	wall.add_child(col)
	wall.position = Vector3(1.1, 6, 0)
	arena.add_child(wall)
	var p := _actor(arena, ["boots_thruster"])
	var f := p.flight
	await t.frames(5)
	p.global_position.y = 3.0
	p.velocity = Vector3.ZERO
	await t.frames(3)
	var charges := f.charges
	p.cmd.jump_pressed = true
	await t.frames(1)
	p.cmd.jump_pressed = false
	t.check(p.velocity.y > 6.0 and p.velocity.x < -5.0 and f.charges == charges,
			"beside a wall, jump kicks up and away from it for no charge (up %.1f, out %.1f m/s, %d charges)" % [p.velocity.y, -p.velocity.x, f.charges])
	await t.frames(10)
	p.cmd.jump_pressed = true
	await t.frames(1)
	p.cmd.jump_pressed = false
	t.check(f.charges == charges - 1, "a second press in the same jump is a kick on a charge (%d of %d)" % [f.charges, charges])
	# Away from any wall, the first press is a kick on a charge too.
	p.position = Vector3(-20, 3, 0)
	p.velocity = Vector3.ZERO
	await t.frames(90)
	p.velocity.y = 5.0
	await t.frames(10)
	charges = f.charges
	p.cmd.jump_pressed = true
	await t.frames(1)
	p.cmd.jump_pressed = false
	t.check(f.charges == charges - 1, "with no wall beside, jump is the usual kick (%d of %d)" % [f.charges, charges])
	# Other rigs never kick off walls.
	var jet := _actor(arena, ["jetpack_mk1"])
	await t.frames(5)
	jet.position = Vector3(0, 3, 2)
	jet.velocity = Vector3.ZERO
	await t.frames(2)
	t.check(jet.flight.wall_kick == 0.0 and jet.wall_beside(1.0) != Vector3.ZERO, "only boots kick off walls")
	p.cmd = ActorCommand.new()
	arena.queue_free()
	await t.frames(2)


## Bots hear each rig at work as far as it carries: the jetpack loud, the
## wings a rush of air, boots quiet; and none at all at rest on the ground.
static func _test_heard(t: Node) -> void:
	var arena := _arena(t, Vector3(-1700, 0, 14000))
	var heard := {}
	for id: String in ["jetpack_mk1", "wings_glide", "boots_thruster"]:
		var p := _actor(arena, [id])
		await t.frames(3)
		t.check(BotBrain.noise_of(p) == 0.0, "%s: standing still, nobody hears it" % id)
		p.flight.is_thrusting = id == "jetpack_mk1"
		p.flight.is_gliding = id == "wings_glide"
		p.flight.is_skating = id == "boots_thruster"
		heard[id] = p.flight.noise()
		p.queue_free()
	t.check(heard["jetpack_mk1"] > heard["wings_glide"] and heard["wings_glide"] > heard["boots_thruster"]
			and heard["boots_thruster"] > 0.0 and heard["jetpack_mk1"] <= BotBrain.LOUDEST_HEARD,
			"heard at work: jetpack %.0f m, wings %.0f m, boots %.0f m" % [heard["jetpack_mk1"], heard["wings_glide"], heard["boots_thruster"]])
	arena.queue_free()
	await t.frames(2)


## The view side (all of it read from the simulated actor): a jetpack tips
## into its push like a helicopter and its flames grow with the throttle;
## wings fast past the glide tuck the arms, sweep back and stream vapor
## (never on Low); a kick off a skate spins the body; and the first-person
## view rolls with the wings' bank, as much as the phone's setting allows.
static func _test_looks(t: Node) -> void:
	Look.enabled = true
	var raid := Raid.new()
	t.add_child(raid)
	raid.start(Worlds.get_world("ashfront"), 23, ["rifle_carbine", "blade_scrap", "jetpack_mk1", "plate_light"])
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
		bot.global_position += Vector3(0, -500, 0)
	await t.frames(20)
	var p := raid.player
	p.set_physics_process(false)
	p.global_position += Vector3(0, 8, 0)
	p.airborne_time = 1.0
	var skin := p.get_node("Skin")
	var forward := -p.global_basis.z
	# Hovering, drifting forward at a steady 10 m/s: leaning into it.
	p.flight.is_hovering = true
	p.flight.is_thrusting = true
	for i in 60:
		p.velocity = forward * 10.0
		await t.get_tree().process_frame
	var cruising: Vector3 = skin.get("_tilt")
	# Then stopping hard: the body flares back against the push.
	for i in 12:
		p.velocity = forward * maxf(0.0, 10.0 - i * 1.2)
		await t.get_tree().process_frame
	var braking: Vector3 = skin.get("_tilt")
	t.check(cruising.z < -0.1 and braking.z > 0.05,
			"a jetpack leans into a drift and flares back to stop (%.2f, then %.2f rad)" % [-cruising.z, braking.z])
	# Climbing hard: the throttle and the flames grow.
	var flames := skin.find_children("Flame", "Node3D", true, false)
	for i in 60:
		p.velocity = Vector3.ZERO
		await t.get_tree().process_frame
	var still := float(skin.get("_jet_throttle"))
	for i in 20:
		p.velocity = Vector3(0, i * 0.5, 0)
		await t.get_tree().process_frame
	var climbing := float(skin.get("_jet_throttle"))
	t.check(flames.size() == 2 and absf(still - 1.0) < 0.1 and climbing > still + 0.3,
			"the jets burn longer as they push harder (throttle %.2f g hovering, %.2f g climbing)" % [still, climbing])
	# Pushing the stick forward while still at rest: the body leans in and
	# the hands reach forward before the drift starts.
	skin.set("_flight_hold", 0.0)
	skin.set("_flight_draw_left", 0.0)
	var rest_reach: float = await _hand_reach(skin, p)
	p.cmd.move = Vector2(0, 1)
	for i in 10:
		p.velocity = Vector3.ZERO
		await t.get_tree().process_frame
	var up_now: Vector3 = (skin as Node3D).transform.basis.y
	var reach: float = await _hand_reach(skin, p)
	t.check(up_now.z < -0.05 and float(skin.get("_tilt").z) > -0.02,
			"a jetpack leans into the stick before it drifts (%.2f rad of lead)" % -up_now.z)
	t.check(reach > rest_reach + 0.03, "the arms reach the way the stick points (hands %.2f m further ahead)" % (reach - rest_reach))
	p.cmd.move = Vector2.ZERO
	p.flight.is_hovering = false
	p.flight.is_thrusting = false

	# Wings, fast in a dive.
	Loadout.equip(p, ["pistol_service", "wings_glide"])
	await t.frames(3)
	var vapor_was: Variant = GameSettings.value_of("graphics")
	GameSettings._values["graphics"] = GameSettings.GRAPHICS_HIGH
	p.flight.is_gliding = true
	for i in 60:
		p.velocity = forward * 29.0 + Vector3(0, -6, 0)
		await t.get_tree().process_frame
	t.check(float(skin.get("_wing_fast")) > 0.7, "diving past the glide's speed, the wings sweep back and the arms tuck in")
	var vapor := skin.find_child("WingVapor", true, false)
	t.check(vapor != null, "fast, the wingtips stream vapor")
	if vapor:
		vapor.free()
		skin.set("_vapor", null)
	GameSettings._values["graphics"] = GameSettings.GRAPHICS_LOW
	for i in 10:
		p.velocity = forward * 29.0 + Vector3(0, -6, 0)
		await t.get_tree().process_frame
	t.check(skin.find_child("WingVapor", true, false) == null, "on the Low graphics there is no wingtip vapor")
	GameSettings._values["graphics"] = vapor_was if vapor_was != null else GameSettings.GRAPHICS_HIGH
	if vapor_was == null:
		GameSettings._values.erase("graphics")
	# A thin wisp, never a bar running back past the camera: tips flying at
	# 30 m/s leave streaks cut to `vapor_length`.
	var wisp: Variant = (skin.get_script() as GDScript).get("_Vapor").new()
	t.add_child(wisp)
	var cap := float(skin.get("vapor_length"))
	for k in 40:
		var tips: Array[Vector3] = [Vector3(-1, 5, -0.5 * k), Vector3(1, 5, -0.5 * k)]
		wisp.step(tips, 1.0 / 60.0, 0.6, cap, 0.03, 0.35, 4.0)
	var longest := 0.0
	for trail: Array in wisp.get("_trails"):
		var run := 0.0
		for k in range(1, trail.size()):
			run += (trail[k][0] as Vector3).distance_to(trail[k - 1][0])
		longest = maxf(longest, run)
	t.check(longest > cap - 1.0 and longest <= cap,
			"the wingtip vapor is cut to %.0f m (longest %.1f m of 19.5 flown)" % [cap, longest])
	wisp.free()

	# The limbs carry on as the body speeds up: they trail behind a burst of
	# speed, then settle back once it holds steady, and a turn flown with
	# the arms free twists the chest into it.
	skin.set("_flight_hold", 0.0)
	skin.set("_flight_draw_left", 0.0)
	for i in 90:
		p.velocity = forward * 14.0
		await t.get_tree().process_frame
	for i in 8:
		p.velocity = forward * (14.0 + i * 1.5)
		await t.get_tree().process_frame
	# The pull in the actor's frame: back, +Z, against the speed-up (lying
	# out head first, that is down the body toward the feet).
	var pulled: Vector3 = skin.get("_sway")
	for i in 120:
		p.velocity = forward * 26.0
		await t.get_tree().process_frame
	var settled: Vector3 = skin.get("_sway")
	t.check(pulled.z > 0.1 and settled.length() < 0.06,
			"speeding up, the limbs trail back (%.2f g), and settle once the speed holds (%.2f)" % [pulled.z, settled.length()])
	for i in 30:
		p.velocity = (forward * 24.0).rotated(Vector3.UP, i * 0.03)
		await t.get_tree().process_frame
	t.check(float(skin.get("_turn_rate")) > 0.8, "a turn is read for the chest to lead it (%.2f rad/s)" % float(skin.get("_turn_rate")))

	# The flyer leads the rig: looking right of the flight path in a glide,
	# the body banks right and the inside (right) arm drops before the path
	# has bent at all.
	for i in 40:
		p.velocity = forward * 24.0
		await t.get_tree().process_frame
	var hands: Vector2 = await _hand_heights(skin)
	var base_bank := float(skin.get("_bank"))
	var yaw_was := p.rotation.y
	p.rotation.y -= 0.45
	for i in 12:
		p.velocity = forward * 24.0
		await t.get_tree().process_frame
	var leaning: Vector2 = await _hand_heights(skin)
	var lead := float(skin.get("_lead_turn"))
	t.check(lead < -0.5 and absf(float(skin.get("_bank")) - base_bank) < 0.05,
			"looking right in a glide, the body leads into the turn (%.2f) before the path bends" % lead)
	t.check(leaning.x - leaning.y > hands.x - hands.y + 0.05,
			"the inside arm drops and the outside lifts to lead the turn (%.2f m against %.2f)" % [leaning.x - leaning.y, hands.x - hands.y])
	p.rotation.y = yaw_was

	# The first-person view rolls with the bank, scaled by the setting.
	var controller := PlayerController.new()
	controller.setup(p)
	raid.add_child(controller)
	controller.set_physics_process(false)
	controller.view_mode = PlayerController.ViewMode.FIRST
	skin.set("_bank", 0.8)
	skin.set("_glide", 1.0)
	controller._update_flight_motion(1.0)
	var full := controller._flight_roll
	var motion_was := GameSettings.flight_camera_motion
	GameSettings.flight_camera_motion = 0.0
	controller._flight_roll = 0.0
	controller._update_flight_motion(1.0)
	t.check(full > 0.15 and full < 0.8 and controller._flight_roll == 0.0,
			"the view rolls with a third or so of the wings' bank (%.2f rad), and not at all with it turned off" % full)
	GameSettings.flight_camera_motion = motion_was
	p.flight.is_gliding = false

	# Boots: a kick off a skate spins the body once round.
	Loadout.equip(p, ["pistol_service", "boots_thruster"])
	await t.frames(3)
	p.flight.is_skating = true
	skin.set("_flight_draw_left", 0.0)
	skin.set("_flight_hold", 0.0)
	p.flight.burst_fired.emit()
	t.check(float(skin.get("_spin_left")) > 0.0, "a kick off a skate spins the body")
	p.flight.is_skating = false
	raid.queue_free()
	await t.frames(3)
	Look.enabled = false


## The skeleton's posed bones as the modifiers leave them, read by a probe
## added after them all (the skeleton puts its poses back once drawn).
static func _probe(skin: Node) -> Dictionary:
	var skeleton: Skeleton3D = skin.get("_skeleton")
	var seen := {}
	var probe: SkeletonModifier3D = WeaponArmScript.Hook.new()
	probe.set("run", func() -> void:
		for b in skeleton.get_bone_count():
			seen[b] = skeleton.global_transform * skeleton.get_bone_global_pose(b).origin)
	skeleton.add_child(probe)
	await skin.get_tree().process_frame
	await skin.get_tree().process_frame
	probe.free()
	return seen


## The two hands' heights in the world (left, right).
static func _hand_heights(skin: Node) -> Vector2:
	var seen: Dictionary = await _probe(skin)
	var arms: Array = skin.get("_glide_arms")
	return Vector2((seen[arms[0][2]] as Vector3).y, (seen[arms[1][2]] as Vector3).y)


## How far ahead of the shoulders the hands are, on average (metres along
## the actor's facing).
static func _hand_reach(skin: Node, p: Actor) -> float:
	var seen: Dictionary = await _probe(skin)
	var to_actor := p.global_transform.affine_inverse()
	var total := 0.0
	for limb: Array in skin.get("_glide_arms"):
		total += (to_actor * (seen[limb[2]] as Vector3)).z * -1.0 - (to_actor * (seen[limb[0]] as Vector3)).z * -1.0
	return total / 2.0
