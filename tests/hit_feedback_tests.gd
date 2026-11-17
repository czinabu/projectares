extends RefCounted
## Feedback: what a hit did is read at a glance and by ear. Plates soaking a
## hit and breaking are told apart from bare and head hits, rounds passing
## close are heard, walls take marks, and a round's jolt moves the view, never
## the aim. Views only; the rules they read are checked here.


static func run(t: Node) -> void:
	print("Hit feedback")
	_check_armor_flags(t)
	_check_marker_kinds(t)
	_check_near_miss(t)
	_check_flinch(t)
	await _check_wall_normal(t)


static func _check_armor_flags(t: Node) -> void:
	var health := HealthComponent.new()
	health.max_health = 100.0
	health.health = 100.0
	health.set_armor(20.0)
	var soaked := DamageInfo.make(20.0, null, "bullet")
	health.apply_damage(soaked)
	t.check(soaked.armored and not soaked.armor_broke, "plates soaking a hit say so")
	var breaking := DamageInfo.make(40.0, null, "bullet")
	health.apply_damage(breaking)
	t.check(breaking.armored and breaking.armor_broke and health.armor == 0.0,
			"the hit that empties the plates breaks them")
	var bare := DamageInfo.make(20.0, null, "bullet")
	health.apply_damage(bare)
	t.check(not bare.armored and not bare.armor_broke, "a bare hit is neither")
	var through := DamageInfo.make(20.0, null, "melee")
	through.armor_pierce = 1.0
	var plated := HealthComponent.new()
	plated.max_health = 100.0
	plated.health = 100.0
	plated.set_armor(50.0)
	plated.apply_damage(through)
	t.check(not through.armored, "a blade going past the plates is not an armor hit")
	health.free()
	plated.free()


static func _check_marker_kinds(t: Node) -> void:
	var info := DamageInfo.make(20.0, null, "bullet")
	t.check(Hud.HitMarker.kind_of(info, false) == "hit", "a plain hit shows the plain marker")
	info.armored = true
	t.check(Hud.HitMarker.kind_of(info, false) == "armor", "plates soaking it show the armor marker")
	info.armor_broke = true
	t.check(Hud.HitMarker.kind_of(info, false) == "armor_break", "breaking plates has a marker of its own")
	info.headshot = true
	t.check(Hud.HitMarker.kind_of(info, false) == "head", "a head outranks the plates")
	t.check(Hud.HitMarker.kind_of(info, true) == "kill", "a kill outranks everything")
	var guarded := DamageInfo.make(20.0, null, "melee")
	guarded.blocked = true
	t.check(Hud.HitMarker.kind_of(guarded, false) == "guarded", "a guarded hit shows as guarded")
	for kind: String in ["hit", "armor", "armor_break", "head", "guarded", "kill"]:
		t.check(Hud.HitMarker.KINDS.has(kind), "the marker has a look for '%s'" % kind)


static func _check_near_miss(t: Node) -> void:
	var from := Vector3.ZERO
	var ear := Vector3(1.0, 0.0, -30.0)
	t.check(Sfx.near_miss(from, Vector3(0, 0, -100), ear).is_finite(),
			"a round passing a metre away is heard going by")
	t.check(not Sfx.near_miss(from, Vector3(40, 0, -100), ear).is_finite(),
			"a round well wide is not")
	t.check(not Sfx.near_miss(from, Vector3(0, 0, -20), ear).is_finite(),
			"a round stopped short of you is not")
	t.check(not Sfx.near_miss(from, Vector3(0, 0, -100), Vector3(0.5, 0, -1)).is_finite(),
			"your own rounds never whizz")


static func _check_flinch(t: Node) -> void:
	var controller := PlayerController.new()
	var light := controller.bullet_flinch(10.0, 0.0)
	var heavy := controller.bullet_flinch(40.0, 0.0)
	var huge := controller.bullet_flinch(500.0, 0.0)
	t.check(light.length() > 0.0 and heavy.length() > light.length(), "a harder round jolts the view more")
	t.check(huge.y <= deg_to_rad(controller.bullet_flinch_max_deg) + 0.0001, "the jolt has a ceiling")
	var yaw := controller.yaw
	var pitch := controller.pitch
	controller.kick_view(heavy)
	t.check(controller.yaw == yaw and controller.pitch == pitch, "a jolt leaves the aim where it was")
	controller.free()


static func _check_wall_normal(t: Node) -> void:
	var raid := Raid.new()
	t.add_child(raid)
	raid.start(Worlds.get_world("ashfront"), 59)
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
	await t.frames(10)
	var p := raid.player
	p.set_physics_process(false)
	var at := Vector3(0, 400, -4800)
	p.global_position = at
	var wall := StaticBody3D.new()
	wall.collision_layer = Actor.LAYER_WORLD
	var shape := BoxShape3D.new()
	shape.size = Vector3(6, 4, 0.4)
	var col := CollisionShape3D.new()
	col.shape = shape
	wall.add_child(col)
	raid.add_child(wall)
	wall.global_position = at + Vector3(0, 1.5, -8)
	await t.frames(3)
	var eye := p.get_eye_position()
	var hit := Combat.trace(p, eye, eye + Vector3(0, 0, -30))
	var normal: Vector3 = hit.get("normal", Vector3.ZERO)
	t.check(not hit.is_empty() and normal.dot(Vector3(0, 0, 1)) > 0.95,
			"a round striking a wall knows which way the face looks, for its mark")
	wall.queue_free()
	raid.queue_free()
	await t.frames(2)
