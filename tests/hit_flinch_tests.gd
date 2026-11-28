extends RefCounted
## The body flinching from hits: `Actor.hit_mark`, set by the authority and
## carried in the state, and `Locomotion` laying the pack's hit clips over
## the body by where a hit landed and which way it came from.

const Locomotion := preload("res://core/visual/locomotion.gd")


static func run(t: Node) -> void:
	await _marks(t)
	await _flinches(t)


static func _quiet_raid(t: Node) -> Raid:
	var raid := Raid.new()
	t.add_child(raid)
	raid.start(Worlds.get_world("ashfront"), 42, ["rifle_carbine", "blade_scrap", "frame_trooper"])
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
		bot.global_position += Vector3(0, -200, 0)
	raid.zone_rules = false
	return raid


## Hits `p` with `amount` landing at `height` (a share of the eyes' height)
## and `side` m to its right, from a shooter in `from` (the body's frame).
static func _hit(raid: Raid, p: Actor, from: Vector3, height: float, side := 0.0, amount := 30.0,
		headshot := false) -> DamageInfo:
	var shooter := Node3D.new()
	raid.add_child(shooter)
	shooter.global_position = p.global_position + p.global_basis * (from * 8.0)
	var info := DamageInfo.make(amount, shooter, "bullet",
			p.global_position + p.global_basis * Vector3(side, height * p.eye_height, 0.0))
	info.headshot = headshot
	p.health.health = p.health.max_health
	p.protected_left = 0.0
	Combat.deal(p, info)
	shooter.free()
	return info


static func _marks(t: Node) -> void:
	print("Hit flinch: the mark")
	var raid := _quiet_raid(t)
	var p := raid.player
	await t.frames(10)
	var before := p.hit_mark
	_hit(raid, p, Vector3(0, 0, -1), 0.72)
	t.check(p.hit_mark != before and Actor.hit_zone(p.hit_mark) == Actor.HIT_CHEST,
			"a shot to the chest marks a chest hit")
	t.check(is_zero_approx(Actor.hit_way(p.hit_mark)), "from straight ahead")
	t.check(Actor.hit_strength(p.hit_mark) == 2, "a 30 point hit is the third step of four")
	var first := p.hit_mark
	_hit(raid, p, Vector3(0, 0, -1), 0.72)
	t.check(p.hit_mark != first and Actor.hit_zone(p.hit_mark) == Actor.HIT_CHEST,
			"the same hit again still changes the mark, so it flinches again")
	_hit(raid, p, Vector3(0, 0, -1), 1.0, 0.0, 30.0, true)
	t.check(Actor.hit_zone(p.hit_mark) == Actor.HIT_HEAD, "a headshot marks the head")
	_hit(raid, p, Vector3(0, 0, -1), 0.45)
	t.check(Actor.hit_zone(p.hit_mark) == Actor.HIT_STOMACH, "a low hit marks the stomach")
	_hit(raid, p, Vector3(0, 0, -1), 0.86, -0.18)
	t.check(Actor.hit_zone(p.hit_mark) == Actor.HIT_LEFT, "a high hit on the left marks the left shoulder")
	_hit(raid, p, Vector3(0, 0, -1), 0.86, 0.18)
	t.check(Actor.hit_zone(p.hit_mark) == Actor.HIT_RIGHT, "and on the right the right one")
	_hit(raid, p, Vector3(0, 0, 1), 0.72)
	t.check(absf(Actor.hit_way(p.hit_mark) - PI) < 0.01, "a shot from behind comes from behind")
	_hit(raid, p, Vector3(-1, 0, 0), 0.72)
	t.check(absf(Actor.hit_way(p.hit_mark) - PI * 1.5) < 0.01, "and one from the left from the left")
	_hit(raid, p, Vector3(0, 0, -1), 0.72, 0.0, 5.0)
	t.check(Actor.hit_strength(p.hit_mark) == 0, "a graze is the lightest step")
	var kept := p.hit_mark
	p.health.health = p.health.max_health
	Combat.deal(p, DamageInfo.make(5.0, null, "storm"))
	t.check(p.hit_mark == kept, "a hit with no place (a storm, the cold) moves nobody")
	Combat.authoritative = false
	_hit(raid, p, Vector3(0, 0, -1), 0.72)
	Combat.authoritative = true
	t.check(p.hit_mark == kept, "a client never marks a hit: the server's mark comes in the state")
	# The mark reaches every view in the state.
	_hit(raid, p, Vector3(0, 0, 1), 0.45)
	var net := NetSession.new()
	net.raid = raid
	net._actors[7] = p
	var entry := net._state_entry(7, 0)
	var sent := p.hit_mark
	p.hit_mark = 0
	net._apply_state(p, entry, false)
	t.check(p.hit_mark == sent, "the state a client is sent carries the mark")
	net.free()
	p.health.health = p.health.max_health
	raid.queue_free()
	await t.frames(2)


static func _flinches(t: Node) -> void:
	print("Hit flinch: the body")
	Look.enabled = true
	var raid := _quiet_raid(t)
	var p := raid.player
	await t.frames(40)
	var skin: Node = p.get_node_or_null("Skin")
	var loco: Locomotion = skin.locomotion if skin != null else null
	t.check(loco != null and loco.skeleton.has_node("HitFlinch"), "a person's body has the flinch")
	if loco == null:
		Look.enabled = false
		raid.queue_free()
		return
	var sk: Skeleton3D = loco.skeleton
	var head := sk.find_bone("Head")
	var seen := [Vector3.ZERO]
	var watch := func() -> void:
		seen[0] = p.global_transform.affine_inverse() * (sk.global_transform * sk.get_bone_global_pose(head)).origin
	sk.skeleton_updated.connect(watch)
	# [from, how the head moves in the body's frame: away from the shooter]
	for case: Array in [[Vector3(0, 0, -1), Vector3(0, 0, 1), "a shot from ahead throws the head back"],
			[Vector3(0, 0, 1), Vector3(0, 0, -1), "one from behind throws it forward"],
			[Vector3(-1, 0, 0), Vector3(1, 0, 0), "one from the left throws it right"]]:
		await t.frames(30)
		var still: Vector3 = seen[0]
		_hit(raid, p, case[0], 0.72)
		var most := 0.0
		var weight := 0.0
		for i in 12:
			await t.frames(1)
			most = maxf(most, ((seen[0] as Vector3) - still).dot(case[1]))
			weight = maxf(weight, loco.flinch_weight())
		t.check(most > 0.08, "%s (%.0f cm)" % [case[2], most * 100.0])
		t.check(weight > 0.5, "the flinch comes on fast (%.2f)" % weight)
		await t.frames(40)
		t.check(loco.flinch_weight() == 0.0 and ((seen[0] as Vector3) - still).length() < 0.02,
				"and it is over in well under a second")
	# A stomach hit doubles over, from the front.
	await t.frames(20)
	var upright: Vector3 = seen[0]
	_hit(raid, p, Vector3(0, 0, -1), 0.45)
	var bent := 0.0
	for i in 20:
		await t.frames(1)
		bent = maxf(bent, upright.z - (seen[0] as Vector3).z)
	t.check(bent > 0.06, "a stomach hit doubles the body over toward the shooter (%.0f cm)" % (bent * 100.0))
	await t.frames(40)
	# Aimed down the sights the body is braced.
	var aimed := 0.0
	p._draw_weapon(p.weapon_for_key(1))
	await t.frames(30)
	p.cmd.secondary = true
	await t.frames(30)
	t.check(ActionPose.of(p).ads > 0.9, "the rifle comes up to the eye")
	var steady: Vector3 = seen[0]
	_hit(raid, p, Vector3(0, 0, -1), 0.72)
	for i in 12:
		await t.frames(1)
		aimed = maxf(aimed, (seen[0] as Vector3).z - steady.z)
	p.cmd.secondary = false
	t.check(aimed > 0.02 and aimed < 0.1, "aimed, it flinches less (%.0f cm)" % (aimed * 100.0))
	await t.frames(40)
	# A killing hit plays the death, not a flinch.
	p.health.health = 10.0
	p.protected_left = 0.0
	Combat.deal(p, DamageInfo.make(50.0, null, "bullet", p.global_position + Vector3(0, 1.2, 0)))
	await t.frames(2)
	t.check(p.is_dead and loco.flinch_weight() == 0.0, "a killing hit plays the death, not a flinch")
	sk.skeleton_updated.disconnect(watch)
	Look.enabled = false
	raid.queue_free()
	await t.frames(2)
