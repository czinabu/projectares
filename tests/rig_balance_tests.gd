extends RefCounted
## Checks for the flight rig balance pass (Caleb's call, DESIGN.md section 5):
## each rig has one job and one weakness. The jetpack holds height and
## hovers, the boots win on the ground and up close, the wings cross the map.
## These measure the Mk1 numbers from the design table, the mechanics that
## came with it (scan reach, roofs, fall damage) and fly every rig across the
## map and through the base's flight course.
## Run from the main test runner. Nothing here starts a server.

const RIGS := ["jetpack_mk1", "boots_thruster", "wings_glide"]
## The design table's cross-map times (s), and how far a measured run may
## stray from them.
const CROSS_TARGET := {"jetpack_mk1": 45.0, "boots_thruster": 60.0, "wings_glide": 25.0}
const CROSS_SLACK := 0.35
## How far "across Ashfront" is, in meters: its playable field, edge to edge.
const CROSS_DISTANCE := 550.0
## Where the wings start a crossing: off a perch this high, since they
## cannot climb on their own.
const WING_PERCH := 30.0


static func run(t: Node) -> void:
	print("Flight rig balance")
	await _test_jetpack(t)
	await _test_wings(t)
	_test_scan_reach(t)
	await _test_roofs(t)
	await _test_fall_damage(t)
	await _test_cross(t)
	await _test_course(t)


## A flat floor `size` wide at `at`, for flying over.
static func _arena(t: Node, at: Vector3, size := Vector3(80, 1, 80)) -> Node3D:
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
	Loadout.equip(actor, ["pistol_service"] + kit)
	actor.position = Vector3(0, 0.05, 0)
	actor.ground_map = arena
	return actor


## Ticks until `done` is true (at most `limit` seconds); returns the seconds.
static func _until(t: Node, done: Callable, limit: float) -> float:
	var tps := Engine.physics_ticks_per_second
	for i in int(limit * tps):
		await t.get_tree().physics_frame
		if done.call():
			return float(i + 1) / tps
	return INF


## Jetpack: hover 8 s on a full bar, climb at 8 m/s on 1.5x heat, a boost
## burns out in about 3 s on 2.5x, and the ground cools it in 4 s.
static func _test_jetpack(t: Node) -> void:
	var arena := _arena(t, Vector3(0, 0, 9000))
	var p := _actor(arena, ["jetpack_mk1"])
	var f := p.flight
	await t.frames(5)
	t.check(is_equal_approx(f.ceiling, 40.0) and is_equal_approx(f.max_rise_speed, 8.0)
			and is_equal_approx(f.boost_speed, 18.0), "the Mk1 jetpack climbs at 8 m/s to 40 m and boosts at 18 m/s")
	p.global_position.y = 20.0
	p.velocity = Vector3.ZERO
	p.cmd.secondary = true
	var hover := await _until(t, func() -> bool: return f.overheated, 15.0)
	t.check(absf(hover - 8.0) < 0.3, "a full bar hovers for 8 s (%.1f s)" % hover)
	p.cmd.secondary = false
	await _until(t, func() -> bool: return p.is_on_floor(), 10.0)
	var cool := await _until(t, func() -> bool: return f.heat <= 0.0, 10.0)
	t.check(cool <= 4.6, "the ground cools a full bar in about 4 s (%.1f s)" % cool)
	# Climbing: 8 m/s for 1.5x the hover's heat.
	f.heat = 0.0
	f.overheated = false
	p.cmd.jump_pressed = true
	p.cmd.jump = true
	await t.frames(1)
	p.cmd.jump_pressed = false
	p.cmd.secondary = true
	await t.frames(60)
	var rise := p.velocity.y
	var heat := f.heat
	await t.frames(60)
	var climb_rate := (f.heat - heat)
	t.check(absf(rise - 8.0) < 0.3 and absf(climb_rate - f.heat_per_sec * 1.5) < 0.5,
			"climbing rises at %.1f m/s for 1.5x the heat (%.1f a second)" % [rise, climb_rate])
	# Boosting: 2.5x, so a long boost overheats in about 3 s.
	p.cmd.jump = false
	f.heat = 0.0
	p.cmd.move = Vector2(0, 1)
	p.cmd.sprint = true
	p.cmd.sprint_pressed = true
	await t.frames(1)
	p.cmd.sprint_pressed = false
	var boost := await _until(t, func() -> bool: return f.overheated, 10.0)
	t.check(f.is_boosting or f.overheated, "Shift boosts the jetpack")
	# The Shift press that starts it is also an air dash, for its own heat.
	t.check(boost > 2.5 and boost < 4.3, "a held boost overheats in a few seconds (%.1f s)" % boost)
	p.cmd = ActorCommand.new()
	arena.queue_free()
	await t.frames(2)


## Wings: 25 s of glide stamina that refills on the ground only (in about
## 5 s), two boosts a flight, and a glide at 22 m/s that dives to 30.
static func _test_wings(t: Node) -> void:
	var arena := _arena(t, Vector3(0, 0, 9400), Vector3(80, 1, 1600))
	var p := _actor(arena, ["wings_glide"])
	var f := p.flight
	await t.frames(5)
	t.check(f.max_charges == 2 and f.charges == 2 and is_equal_approx(f.glide_speed, 22.0)
			and absf(f.glide_speed * (1.0 + f.glide_dive_gain) - 30.0) < 0.1,
			"Mk1 wings glide at 22 m/s, dive at 30, with two boosts")
	f.ceiling = 0.0
	p.global_position.y = 400.0
	p.velocity = Vector3(0, -1, -15)
	p.cmd.jump = true
	var glide := await _until(t, func() -> bool: return f.overheated, 40.0)
	t.check(absf(glide - 25.0) < 1.0 and not f.is_gliding, "a full bar of glide stamina lasts 25 s (%.1f s)" % glide)
	f.charges = 0
	p.cmd.jump = false
	await _until(t, func() -> bool: return p.is_on_floor(), 30.0)
	t.check(f.charges == 0 and f.heat > 90.0, "nothing refills in the air")
	var refill := await _until(t, func() -> bool: return f.heat <= 0.0, 10.0)
	t.check(refill <= 5.3 and f.charges == 2, "on the ground the stamina refills in about 5 s (%.1f s), and the boosts" % refill)
	arena.queue_free()
	await t.frames(2)


## A scan or thermal picks a rig up from its own reach: the jetpack far, the
## wings middling, the boots close (under a Seeker's own 40 m).
static func _test_scan_reach(t: Node) -> void:
	var reach := {}
	for id: String in RIGS:
		var a := Actor.new()
		Loadout.equip(a, [id])
		reach[id] = Visor.reach_to(a, 40.0)
		a.free()
	var bare := Actor.new()
	t.check(is_equal_approx(reach["jetpack_mk1"], 120.0) and is_equal_approx(reach["wings_glide"], 80.0)
			and is_equal_approx(reach["boots_thruster"], 30.0) and is_equal_approx(Visor.reach_to(bare, 40.0), 40.0),
			"scans and thermal reach a jetpack at 120 m, wings at 80 m, boots at 30 m, no rig at the visor's own range")
	bare.free()


## Under a roof: wings cannot open, a jetpack climbs and flies at half
## speed, boots work as in the open.
static func _test_roofs(t: Node) -> void:
	var arena := _arena(t, Vector3(0, 0, 11400))
	var roof := StaticBody3D.new()
	roof.collision_layer = Actor.LAYER_WORLD
	var shape := BoxShape3D.new()
	shape.size = Vector3(60, 0.5, 60)
	var col := CollisionShape3D.new()
	col.shape = shape
	roof.add_child(col)
	roof.position = Vector3(0, 9.0, 0)
	arena.add_child(roof)
	var wings := _actor(arena, ["wings_glide"])
	var jet := _actor(arena, ["jetpack_mk1"])
	var boots := _actor(arena, ["boots_thruster"])
	jet.position.x = 6.0
	boots.position.x = -6.0
	await t.frames(5)
	for a: Actor in [wings, jet, boots]:
		a.cmd.jump_pressed = true
		a.cmd.jump = true
	await t.frames(1)
	for a: Actor in [wings, jet, boots]:
		a.cmd.jump_pressed = false
	await t.frames(8)
	# A second press: wings try to launch, boots kick.
	wings.cmd.jump_pressed = true
	boots.cmd.jump_pressed = true
	jet.cmd.secondary = true
	await t.frames(1)
	wings.cmd.jump_pressed = false
	boots.cmd.jump_pressed = false
	t.check(wings.flight.indoors and not wings.flight.launched and not wings.flight.can_glide(),
			"under a roof the wings cannot launch or open")
	t.check(boots.flight.charges == boots.flight.max_charges - 1 and not boots.flight.indoors,
			"boots kick under a roof as in the open")
	await t.frames(30)
	t.check(jet.flight.indoors and absf(jet.velocity.y - jet.flight.max_rise_speed * jet.flight.indoor_mult) < 0.3,
			"a jetpack under a roof climbs at half speed (%.1f m/s)" % jet.velocity.y)
	for a: Actor in [wings, jet, boots]:
		a.cmd = ActorCommand.new()
	arena.queue_free()
	await t.frames(2)


## In a world a hard landing hurts: in full with no rig, half in a jetpack,
## not at all in boots or out of a glide.
static func _test_fall_damage(t: Node) -> void:
	var lost := {}
	for kit: Array in [["rifle_scrap"], ["rifle_scrap", "jetpack_mk1"], ["rifle_scrap", "boots_thruster"],
			["rifle_scrap", "wings_glide"]]:
		var raid := Raid.new()
		t.add_child(raid)
		raid.start(Worlds.get_world("ashfront"), 71, kit)
		for bot in raid.bots:
			bot.get_node("Brain").set_physics_process(false)
		await t.frames(20)
		var p := raid.player
		if kit.size() == 1:
			Loadout.equip(p, [])
			p.flight.enabled = false
		p.protected_left = 0.0
		p.health.armor = 0.0
		p.global_position.y = p.ground_level() + 20.0
		p.velocity = Vector3.ZERO
		# Wings glide down; the rest fall.
		p.cmd.jump = p.flight.can_glide()
		var before := p.health.health
		await _until(t, func() -> bool: return p.is_on_floor(), 30.0)
		await t.frames(2)
		lost[kit.back()] = before - p.health.health
		raid.queue_free()
		await t.frames(2)
	t.check(lost["rifle_scrap"] > 30.0, "a 20 m fall hurts with no rig (%.0f)" % lost["rifle_scrap"])
	t.check(absf(lost["jetpack_mk1"] - lost["rifle_scrap"] * 0.5) < 3.0,
			"a jetpack takes half the fall damage (%.0f)" % lost["jetpack_mk1"])
	t.check(is_zero_approx(lost["boots_thruster"]) and is_zero_approx(lost["wings_glide"]),
			"boots and a glide land without a scratch")


## Every rig crosses the map flown its own way, all at once: the wings off
## a perch (they cannot climb), the jetpack cruising and coasting to cool,
## the boots running. Each lands near the design's time, and the order is
## wings, then jetpack, then boots.
static func _test_cross(t: Node) -> void:
	var results := {}
	var index := 0
	for id: String in RIGS:
		var arena := _arena(t, Vector3(-9000.0 + index * 200.0, 0, -9000), Vector3(60, 1, CROSS_DISTANCE + 80.0))
		index += 1
		var p := _actor(arena, [id])
		_cross_one(t, p, id, results)
	await t.frames(5)
	for i in 120 * 60:
		if results.size() == RIGS.size():
			break
		await t.frames(1)
	for id: String in RIGS:
		var took: float = results.get(id, INF)
		var target: float = CROSS_TARGET[id]
		t.check(absf(took - target) <= target * CROSS_SLACK,
				"%s crosses %d m in %.0f s (design: about %.0f s)" % [id, int(CROSS_DISTANCE), took, target])
	t.check(results.get("wings_glide", INF) < results.get("jetpack_mk1", INF)
			and results.get("jetpack_mk1", INF) < results.get("boots_thruster", INF),
			"across the map the wings are fastest, then the jetpack, then the boots")
	for node in t.get_children():
		if node is Node3D and (node as Node3D).position.z == -9000.0:
			node.queue_free()
	await t.frames(2)


static func _cross_one(t: Node, p: Actor, id: String, results: Dictionary) -> void:
	var f := p.flight
	var tps := Engine.physics_ticks_per_second
	await t.frames(3)
	var start := p.global_position.z
	p.cmd.yaw = 0.0
	p.cmd.move = Vector2(0, 1)
	p.cmd.sprint = true
	if f.can_glide():
		p.global_position.y += WING_PERCH
		p.cmd.sprint = false
		p.cmd.jump_pressed = true
		await t.frames(1)
		p.cmd.jump_pressed = false
		# Level, not diving: the furthest a glide goes.
		p.cmd.move = Vector2.ZERO
		p.cmd.jump = true
	elif f.can_hover():
		p.cmd.sprint = false
		p.cmd.jump_pressed = true
		await t.frames(1)
		p.cmd.jump_pressed = false
	var cooling := false
	for i in 110 * tps:
		if start - p.global_position.z >= CROSS_DISTANCE:
			results[id] = float(i) / tps
			break
		if f.can_hover():
			var height := p.global_position.y - p.ground_level()
			if f.heat > 80.0:
				cooling = true
			elif f.heat < 25.0:
				cooling = false
			p.cmd.secondary = not f.overheated
			p.cmd.jump = not cooling and height < 18.0
			p.cmd.descend = cooling and height > 3.0
			p.cmd.jump_pressed = p.is_on_floor() and not f.overheated and i % 20 == 0
		elif f.glide_fall_speed > 0.0 and p.is_on_floor():
			# Wings down: run the rest.
			p.cmd.jump = false
			p.cmd.move = Vector2(0, 1)
			p.cmd.sprint = true
		await t.get_tree().physics_frame
	if not results.has(id):
		results[id] = INF
	p.cmd = ActorCommand.new()


## The flight course in the base's yard: every rig flies it, the board times
## it in stages, and falling into the gap ends the run.
static func _test_course(t: Node) -> void:
	var times := {}
	for id: String in RIGS:
		var base := HomeBase.new()
		base.show_gear([], {"rig": id})
		t.add_child(base)
		base.position = Vector3(0, 0, -14000)
		await t.frames(10)
		var p := base.player
		t.check(p.flight.item_id == id, "the base suits you up in %s for the course" % id)
		var marks := base.course_marks()
		t.check(base.in_course(Vector3(base._tower_x(), 1.0, marks.tower_a)) and base.inside(Vector3(0, 1.0, marks.finish)),
				"the course yard is part of the base")
		if id == RIGS[0]:
			# Falling into the gap ends the run.
			p.global_position = base.to_global(Vector3(base._tower_x(), 0.1, marks.start + 1.0))
			p.cmd.yaw = 0.0
			p.cmd.move = Vector2(0, 1)
			await _until(t, func() -> bool: return base.course_stage == 0, 3.0)
			t.check(base.course_stage == 0 and base.course_board.text.contains("climb"), "crossing the start line starts the clock")
			p.cmd.move = Vector2.ZERO
			p.global_position = base.to_global(Vector3(base._tower_x(), base.course_tower.y + 0.2, marks.tower_a))
			p.velocity = Vector3.ZERO
			await _until(t, func() -> bool: return base.course_stage == 1, 2.0)
			t.check(base.course_stage == 1 and base.course_splits.size() == 1, "standing on the first tower ends the climb")
			p.global_position = base.to_global(Vector3(base._tower_x(), 2.0, (marks.tower_a + marks.tower_b) * 0.5))
			p.velocity = Vector3.ZERO
			await _until(t, func() -> bool: return base.course_stage == -1, 3.0)
			t.check(base.course_stage == -1 and base.course_last.contains("fell in the gap"), "touching the floor in the gap ends the run")
		p.cmd = ActorCommand.new()
		p.global_position = base.to_global(Vector3(base._tower_x(), 0.1, marks.start + 2.0))
		p.velocity = Vector3.ZERO
		await t.frames(5)
		var total: float = await _fly_course(t, base, id)
		times[id] = [total] + Array(base.course_splits)
		t.check(total < INF, "%s flies the course: %s" % [id, base.course_last])
		t.check(base.course_board.text.contains("Best: "), "the board keeps %s's best time" % id)
		base.queue_free()
		await t.frames(2)
	if times.size() == RIGS.size():
		var climb := func(id: String) -> float: return times[id][1] if times[id].size() > 1 else INF
		t.check(climb.call("wings_glide") > climb.call("jetpack_mk1") and climb.call("wings_glide") > climb.call("boots_thruster"),
				"wings take the ramp, so they climb slowest")


## Flies the course with `id`'s rig, its own way, and returns the time (INF
## if it never finishes). Targets are each tower's top, then the finish.
static func _fly_course(t: Node, base: HomeBase, id: String) -> float:
	var p := base.player
	var f := p.flight
	var marks := base.course_marks()
	var tx: float = base._tower_x()
	var ramp_foot := Vector3(tx - base.course_tower.x * 0.5 - base.course_tower.y / tan(deg_to_rad(34.0)) - 1.5, 0.0, marks.tower_a)
	var on_ramp := false
	var tps := Engine.physics_ticks_per_second
	base.course_last = ""
	for i in 60 * tps:
		if base.course_stage == -1 and base.course_last != "":
			break
		var lp := base.to_local(p.global_position)
		var stage: int = maxi(base.course_stage, 0)
		var target := Vector3(tx, base.course_tower.y, marks.tower_a)
		if stage == 1:
			target.z = marks.tower_b
		elif stage == 2:
			target = Vector3(tx, 0.0, marks.finish - 6.0)
		if id == "wings_glide" and stage == 0 and not on_ramp:
			# Up the ramp: wings cannot climb.
			if Vector2(lp.x - ramp_foot.x, lp.z - ramp_foot.z).length() < 1.0:
				on_ramp = true
			else:
				target = ramp_foot
		var to := Vector3(target.x - lp.x, 0.0, target.z - lp.z)
		var h := to.length()
		if h > 0.3:
			p.cmd.yaw = atan2(-to.x, -to.z)
		var above := lp.y > target.y + 0.3
		p.cmd.jump_pressed = false
		p.cmd.sprint_pressed = false
		match id:
			"jetpack_mk1":
				var over := stage < 2 and h < 1.2 and above
				p.cmd.secondary = not over and not f.overheated
				p.cmd.jump = not over and lp.y < target.y + 2.0
				p.cmd.jump_pressed = p.is_on_floor() and i % 10 == 0
				# Brake in time: the jets stop you at `fly_accel`.
				var flat := Vector2(p.velocity.x, p.velocity.z).length()
				var brake := flat * flat / (2.0 * f.fly_accel) + 0.6
				p.cmd.move = Vector2(0, 1) if (above or lp.y > target.y + 1.0 or h > 6.0) and h > brake else Vector2.ZERO
			"boots_thruster":
				p.cmd.sprint = true
				var over := stage < 2 and h < 2.5 and above
				p.cmd.move = Vector2(0, -1) if over and Vector2(p.velocity.x, p.velocity.z).length() > 2.0 \
						else (Vector2.ZERO if over else Vector2(0, 1))
				if stage == 1 and p.is_on_floor() and f.charges < f.max_charges:
					# Gather the charges on the tower before the gap.
					p.cmd.move = Vector2.ZERO
				elif stage < 2 and not above and (h > 2.8 or lp.y < target.y - 0.5):
					var want_kick := (p.is_on_floor() and (h < 5.0 or stage == 1)) or (not p.is_on_floor() and p.velocity.y <= 0.0)
					p.cmd.jump_pressed = want_kick and i % 2 == 0
			"wings_glide":
				# Fold the wings once the tower top is a moment's flight away.
				var flat := Vector2(p.velocity.x, p.velocity.z).length()
				var over := stage < 2 and h < maxf(1.5, flat * 0.3) and above
				var air := not p.is_on_floor()
				p.cmd.sprint = not air
				p.cmd.move = Vector2.ZERO if (air or over) else Vector2(0, 1)
				if stage == 0:
					p.cmd.jump = false
				else:
					# Jump off, launch, and glide; let go over the tower to land.
					p.cmd.jump = not over
					p.cmd.jump_pressed = (p.is_on_floor() or not f.launched) and i % 2 == 0
					if air and f.is_gliding:
						# Pull up to bleed speed coming in to land.
						p.cmd.move = Vector2(0, -1) if stage == 1 and h < 12.0 else Vector2.ZERO
		if OS.get_environment("COURSE_DEBUG") != "" and i % 20 == 0:
			print("  %s t=%.2f stage=%d lp=%s v=%s floor=%s charges=%d glide=%s" % [id, float(i) / tps, base.course_stage,
					str(lp.snapped(Vector3.ONE * 0.1)), str(p.velocity.snapped(Vector3.ONE * 0.1)), p.is_on_floor(), f.charges, f.is_gliding])
		await t.get_tree().physics_frame
	p.cmd = ActorCommand.new()
	if base.course_last.contains(" s "):
		return base.course_best.get(f.display_name, INF)
	return INF
