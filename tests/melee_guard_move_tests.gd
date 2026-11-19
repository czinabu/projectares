extends RefCounted
## A guard held while moving stays put: the blade keeps the angle its
## guard has (`ActionPose.guard_keys`) at a walk, a run and a strafe, and
## never swings or flips from one step to the next. The arm reaching for a
## guard by a bobbing chest once needed the fist rolled near a half turn,
## the roll flipped side to side each stride and the blade swung about
## (`WeaponArm.forearm_roll_limit`, `roll_keep`).

const WEAPONS := ["knife_gutter", "blade_scrap", "axe_splitter", "hammer_breaker", "blade_arc", "spear_lancer"]


static func run(t: Node) -> void:
	print("A held guard stays steady on the move")
	for id: String in WEAPONS:
		await _check_weapon(t, id)


static func _check_weapon(t: Node, id: String) -> void:
	Look.enabled = true
	var raid := Raid.new()
	t.add_child(raid)
	raid.start(Worlds.get_world("ashfront"), 41, ["rifle_carbine", id, "plate_light"])
	await t.frames(10)
	for bot in raid.bots.duplicate():
		raid.bots.erase(bot)
		bot.queue_free()
	raid.zone_rules = false
	var p := raid.player
	p.weapons_locked = false
	var blade: MeleeWeapon = null
	for i in p.weapons.size():
		if p.weapons[i] is MeleeWeapon:
			blade = p.weapons[i]
			p.active_weapon_index = i
	await t.frames(40)
	var holder: Node3D = blade.visual.get_node_or_null("Model") if blade != null and blade.visual != null else null
	t.check(holder != null, "%s is held as a model" % id)
	if holder == null:
		Look.enabled = false
		raid.queue_free()
		await t.frames(2)
		return
	var pose := ActionPose.of(p)
	p.cmd.secondary = true
	await t.frames(30)
	var wanted: Vector3 = (pose.guard_keys(blade, blade.guard_dir)[1] as Vector3).normalized()
	var turned := 0.0
	var off := 0.0
	var blocking := true
	for move: Vector2 in [Vector2(0, 1), Vector2(1, 0), Vector2(0, -1), Vector2(-1, 1)]:
		p.cmd.move = move
		var last := Vector3.ZERO
		for f in 45:
			await t.frames(1)
			blocking = blocking and blade.is_blocking()
			var aim := p.global_basis.orthonormalized() * Basis(Vector3.RIGHT, p.cmd.pitch)
			var up := aim.inverse() * holder.global_basis.y.normalized()
			if f >= 12:
				turned = maxf(turned, up.angle_to(last))
				off = maxf(off, up.angle_to(wanted))
			last = up
	p.cmd.move = Vector2.ZERO
	p.cmd.secondary = false
	t.check(blocking, "%s: the guard stays up on the move" % id)
	t.check(turned < 0.1, "%s: the guarding blade never jumps between frames on the move (%.2f rad at most)" % [id, turned])
	t.check(off < 0.35, "%s: the guarding blade keeps its guard's angle on the move (%.2f rad off at most)" % [id, off])
	Look.enabled = false
	raid.queue_free()
	await t.frames(2)
