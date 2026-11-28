extends RefCounted
## The bodies a bike or a hoverbike can wear (`VehicleModel.BODIES`, picked
## by the item's "body" stat): every one builds round the item's own seat,
## bars and pegs, stands on the ground (a bike) or floats with no wheels (a
## hover), and has the moving parts the vehicle turns; the Raider's fans
## spin faster with its speed. `-- --groups vehicle_bodies` runs just these.

const VehicleScript := preload("res://core/vehicle/vehicle.gd")
const VehicleModel := preload("res://core/vehicle/vehicle_model.gd")


static func run(t: Node) -> void:
	print("Vehicles: bodies")
	t.check(VehicleModel.body_of("bike", "") == "scrambler" and VehicleModel.body_of("hoverbike", "") == "ducted"
			and VehicleModel.body_of("bike", "manta") == "scrambler" and VehicleModel.body_of("hoverbike", "lancer") == "lancer"
			and VehicleModel.body_of("rover", "street") == "",
			"a bike or a hoverbike wears the body its item names, or its first; other models have none")
	for id: String in ["bike_scrapper", "bike_raider"]:
		var toy: Node3D = VehicleScript.toy_model(id)
		var model := toy.get_node("Model")
		t.check(str(model.get_meta("body", "")) == ("scrambler" if id == "bike_scrapper" else "ducted"),
				"%s wears its own body (%s)" % [id, model.get_meta("body", "")])
		toy.free()
	for kind: String in ["bike", "hoverbike"]:
		var id := "bike_scrapper" if kind == "bike" else "bike_raider"
		for body: String in VehicleModel.BODIES[kind]:
			_check_body(t, id, body)
	await _check_rotors(t)


static func _check_body(t: Node, id: String, body: String) -> void:
	var v = VehicleScript.new()
	v.setup(id)
	v.body = body
	var model: Node3D = v.build_visual()
	var tag := "%s as a %s: " % [id, body]
	t.check(str(model.get_meta("body", "")) == body, tag + "it builds")
	var steer := model.get_node_or_null("Steer") as Node3D
	t.check(steer != null and steer.get_meta("grips", false), tag + "its bars turn, with the hands on them")
	# The grips are where the rider's hands go.
	var near := 0
	if steer != null:
		for grip: Vector3 in v.grip_points:
			for node in steer.get_children():
				var part := node as MeshInstance3D
				if part != null and (steer.position + part.position).distance_to(grip) < 0.06:
					near += 1
					break
	t.check(near == 2, tag + "a grip on each end of the bars, where the hands go (%d)" % near)
	var low := INF
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var part := node as MeshInstance3D
		var to_model := Transform3D.IDENTITY
		var at: Node = part
		while at != model:
			to_model = (at as Node3D).transform * to_model
			at = at.get_parent()
		var box := part.get_aabb()
		for i in 8:
			low = minf(low, (to_model * box.get_endpoint(i)).y)
	if v.hovers:
		var lying := model.find_children("*", "MeshInstance3D", true, false).filter(func(m: MeshInstance3D) -> bool:
				return m.mesh is CylinderMesh and absf(m.basis.y.normalized().x) > 0.7)
		t.check(lying.is_empty() and model.find_children("Wheel*", "Node3D", true, false).is_empty()
				and model.find_children("Thruster*", "MeshInstance3D", true, false).size() >= 2
				and model.get_node_or_null("Fin0") != null,
				tag + "no wheels, lift thrusters under it and a rudder fin")
		t.check(low > 0.0, tag + "nothing hangs below its cushion (lowest %.3f m)" % low)
	else:
		var wheels := model.find_children("Wheel*", "Node3D", true, false)
		t.check(wheels.size() == 2 and steer != null and steer.get_node_or_null("WheelFront") != null,
				tag + "two wheels, the front one on the fork")
		t.check(absf(low) < 0.012, tag + "its wheels stand on the ground (lowest %.3f m)" % low)
	model.free()
	v.free()


## The Raider's fans spin while it runs, faster at speed.
static func _check_rotors(t: Node) -> void:
	var arena: Node3D = t._vehicle_arena()
	var v = VehicleScript.new()
	v.setup("bike_raider")
	arena.add_child(v)
	v.position = Vector3(40, 0.6, 40)
	await t.frames(5)
	var rotor := v.get_node("Model").find_children("Rotor*", "Node3D", true, false)[0] as Node3D
	v.set_physics_process(false)
	var turned := func(frames: int) -> float:
		var total := 0.0
		for i in frames:
			var before := rotor.basis.get_euler().y
			await t.frames(1)
			total += absf(wrapf(rotor.basis.get_euler().y - before, -PI, PI))
		return total
	v.speed = 0.0
	var idle: float = await turned.call(20)
	v.speed = v.max_speed
	var fast: float = await turned.call(20)
	t.check(idle > 0.05 and fast > idle * 1.5, "the fans spin idling, and faster at speed (%.2f, %.2f rad)" % [idle, fast])
	arena.queue_free()
	await t.frames(2)
