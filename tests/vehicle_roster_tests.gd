extends RefCounted
## The `vehicle_roster` checks. The test runner finds this file by itself and calls
## `run(t)`.

const VehicleScript := preload("res://core/vehicle/vehicle.gd")


static func run(t: Node) -> void:
	print("Vehicles: rover, mech and jet")
	var arena: Node3D = t._vehicle_arena()
	var rider := Actor.new()
	arena.add_child(rider)
	rider.position = Vector3(-40, 0.1, 0)
	await t.frames(5)
	var bike_turn: float = ItemDB.item_stats("bike_scrapper").get("turn_rate", 2.3)
	for id: String in ["rover_warden", "mech_bulwark", "jet_kestrel"]:
		t.check(ItemDB.has_tag(id, "vehicle") and ItemDB.item_rarity(id) >= ItemDB.Rarity.RARE
				and not ItemDB.has_tag(id, "vendor"), "%s is a vehicle item, never sold" % id)
		var v = VehicleScript.new()
		v.setup(id)
		arena.add_child(v)
		v.position = Vector3(0, 0.5, 0)
		await t.frames(20)
		var model: Node3D = v.get_node("Model")
		t.check(v.is_on_floor() and model != null and model.get_child_count() > 10,
				"%s stands on the ground with its own greybox body" % id)
		var parked_dip: float = t._lowest_point(model) - arena.global_position.y
		t.check(absf(parked_dip) < 0.05, "%s rests on the ground, not in it (lowest point %.3f m)" % [id, parked_dip])
		# The ground is the arena's floor, at the arena's height (and the ramp
		# is far away): track the deepest the model goes from here on.
		var dip := {"min": INF}
		var watch_dip := func() -> void:
			var off: Vector3 = v.global_position - arena.global_position
			if is_instance_valid(model) and off.distance_to(Vector3(60, 0, -40)) > 15.0 \
					and absf(off.x) < 190.0 and absf(off.z) < 190.0:
				dip.min = minf(dip.min, t._lowest_point(model) - arena.global_position.y)
		t.get_tree().physics_frame.connect(watch_dip)
		var seat_at: Vector3 = v.seat_point
		t.check(v.grip_points.size() == 2 and v.peg_points.size() == 2
				and v.grip_points[0].x < v.grip_points[1].x and v.peg_points[0].x < v.peg_points[1].x,
				"%s lists two grips and two pegs, left then right" % id)
		t.check(v.grip_points[0].z < seat_at.z and v.grip_points[0].y > seat_at.y and v.peg_points[0].y < seat_at.y,
				"%s puts its grips ahead of and above the seat, its pegs below" % id)
		t.check(v.mount(rider) and rider.vehicle == v, "%s can be ridden" % id)
		await t.frames(2)
		var eye_up: float = rider.get_eye_position().y - v.global_position.y
		t.check(eye_up > seat_at.y + 0.3 and eye_up < seat_at.y + 1.0,
				"%s seats its rider on the seat (eyes %.2f m up, seat %.2f)" % [id, eye_up, seat_at.y])
		var toy: Node3D = VehicleScript.toy_model(id)
		t.check(toy.get_node_or_null("Model") != null, "%s has a toy for the watch" % id)
		toy.free()

		var start: Vector3 = v.global_position
		match id:
			"rover_warden":
				# The driver sees out: straight ahead from a seated driver's
				# eyes, nothing but see-through glass stands in the way.
				var eye := seat_at + Vector3(0.0, 0.78, 0.0)
				var blocked: Array[String] = []
				var glassed := false
				for node in model.find_children("*", "MeshInstance3D", true, false):
					var part := node as MeshInstance3D
					var box: AABB = (model.global_transform.affine_inverse() * part.global_transform) * part.get_aabb()
					for ahead: Vector3 in [Vector3(0, 0, -3), Vector3(0, -0.4, -3), Vector3(0.6, 0, -3), Vector3(-0.6, 0, -3)]:
						if box.intersects_segment(eye, eye + ahead) == null:
							continue
						var mat := part.material_override as BaseMaterial3D
						if mat != null and mat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
							glassed = true
						else:
							blocked.append("%s at %s" % [part.name, part.position])
						break
				t.check(blocked.is_empty() and glassed,
						"the rover's driver looks out through a see-through windscreen (blocked by %s)" % [blocked])
				rider.cmd.move = Vector2(0, 1)
				await t.frames(240)
				t.check(v.speed > FlightRig.CRUISE_SPEED, "the rover outruns flight cruise on the ground (%.1f m/s)" % v.speed)
				t.check(v.turn_rate < bike_turn and absf(v.lean) < 0.1, "the rover turns slower than a bike and does not lean in")
			"mech_bulwark":
				rider.cmd.move = Vector2(1, 0)
				var heading_before: float = v.heading
				await t.frames(30)
				t.check(v.heading < heading_before - 0.3 and v.global_position.distance_to(start) < 0.5,
						"the mech turns on the spot")
				rider.cmd.move = Vector2(0, 1)
				await t.frames(120)
				t.check(v.speed > 5.0 and v.speed <= v.max_speed + 0.1, "the mech walks, slowly (%.1f m/s)" % v.speed)
				var legs: Array = model.find_children("Leg?", "", false, false)
				var apart := 0.0
				for i in 30:
					await t.frames(1)
					if legs.size() == 2:
						apart = maxf(apart, absf(legs[0].rotation.x - legs[1].rotation.x))
				t.check(legs.size() == 2 and apart > 0.3, "its legs stride as it walks (%.2f apart)" % apart)
				rider.cmd.jump_pressed = true
				await t.frames(1)
				rider.cmd.jump_pressed = false
				var top: float = v.global_position.y
				for i in 60:
					await t.frames(1)
					top = maxf(top, v.global_position.y)
				t.check(top > start.y + 1.5, "jump-jets hop the mech up (%.1f m)" % (top - start.y))
				t.check(v._jump_wait > 0.0, "and need a moment before the next hop")
			"jet_kestrel":
				rider.cmd.jump = true
				rider.cmd.move = Vector2(0, 1)
				await t.frames(30)
				t.check(v.is_on_floor() and v.speed < v.takeoff_speed, "the jet rolls along the ground until it is fast enough")
				await t.frames(300)
				var climbed: float = v.global_position.y - start.y
				t.check(climbed > 5.0, "past takeoff speed, jump lifts it into the air (%.1f m up)" % climbed)
				rider.cmd.jump = false
				rider.cmd.move = Vector2.ZERO
				await t.frames(120)
				t.check(not v.is_on_floor() and v.speed >= v.stall_speed - 0.1,
						"off the throttle it keeps flying, it never hovers (%.1f m/s)" % v.speed)
				t.check(rider.global_position.distance_to(v.global_position) < 2.0, "the pilot rides along")
				rider.cmd.move = Vector2(-1, 0)
				await t.frames(20)
				t.check(v.lean < -0.2, "it banks into a turn (%.2f)" % v.lean)
				rider.cmd.move = Vector2.ZERO
				# Back over the middle of the floor, so it comes down on it.
				v.global_position = arena.global_position + Vector3(0, 12, 0)
				v.velocity = Vector3.ZERO
				v.speed = v.stall_speed
				await t.frames(2)
				v.dismount()
				var height: float = v.global_position.y
				await t.frames(60)
				t.check(v.global_position.y < height - 3.0, "with nobody at the stick it drops")
				await t._wait_until(func() -> bool: return v.is_on_floor(), 600)
				await t.frames(30)
				t.check(v.is_on_floor(), "and comes down on the ground")
		t.get_tree().physics_frame.disconnect(watch_dip)
		t.check(dip.min > -0.06, "%s never sinks into the ground driving, landing or hopping (deepest %.3f m)" % [id, dip.min])
		rider.cmd.move = Vector2.ZERO
		rider.cmd.jump = false
		v.dismount()
		v.queue_free()
		await t.frames(2)
		rider.global_position = arena.global_position + Vector3(-40, 0.2, 0)
		rider.velocity = Vector3.ZERO
		await t.frames(10)

	# On the watch: heavier vehicles take longer to recharge.
	var world := Worlds.get_world("ashfront")
	var raid := Raid.new()
	t.add_child(raid)
	raid.start(world, 73, world.starter_loadout() + (["jet_kestrel", "mech_bulwark"] as Array[String]))
	await t.frames(5)
	t.check(raid.toy_recharge("bike_scrapper") == raid.toy_cooldown
			and raid.toy_recharge("rover_warden") > raid.toy_recharge("bike_scrapper")
			and raid.toy_recharge("mech_bulwark") > raid.toy_recharge("rover_warden"),
			"heavier vehicles take longer for the watch to recharge")
	var p := raid.player
	raid.queue_free()
	arena.queue_free()
	await t.frames(2)
