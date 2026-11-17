extends RefCounted
## Checks for Ashfront's heavy units (DESIGN.md "Heavy units"): the exo
## trooper and the Kiln Walker in the armies' spawn mix, the walker's size,
## weak spot, slow turn and one-per-landmark cap, and that the spider model
## has left Ashfront. Kept in its own file and called from the test runner.

const World := preload("res://worlds/ashfront/world.gd")


static func run(t: Node) -> void:
	await _mix(t)
	var raid: Raid = await t._new_raid(6262, false)
	await _walker_body(t, raid)
	await _weak_spot(t, raid)
	await _cap(t, raid)
	await t._end_raid(raid)


## A bot of `kind` from zone `zone`, rolled from seeds until the world gives one.
static func find_kind(raid: Raid, kind: String, zone: int, at: Vector3, from_seed := 1) -> Actor:
	for i in 400:
		var bot := raid.spawn_bot("Heavy%d" % (from_seed + i), at, from_seed + i, false, "", zone)
		if bot.get_meta("kind", "") == kind:
			return bot
		raid.bots.erase(bot)
		raid.bot_seeds.erase(bot)
		bot.free()
	return null


static func _mix(t: Node) -> void:
	print("Heavy units: the spawn mix")
	var world := Worlds.get_world("ashfront")
	var holder := Node3D.new()
	t.add_child(holder)
	var rolls := 1500
	var shares := []
	var looks := {}
	var same := true
	for zone in 3:
		var counts := {"soldier": 0, "heavy": 0, "exo": 0, "walker": 0}
		for i in rolls:
			var bot := Actor.new()
			bot.set_meta("zone", zone)
			holder.add_child(bot)
			var rng := RandomNumberGenerator.new()
			rng.seed = zone * 100000 + i
			world.equip_bot(bot, rng)
			var kind: String = bot.get_meta("kind", "")
			counts[kind] = counts.get(kind, 0) + 1
			looks[bot.get_meta("look", "")] = true
			if i < 40:
				# A client builds the bot from the same seed: it must be the same.
				var copy := Actor.new()
				copy.set_meta("zone", zone)
				holder.add_child(copy)
				var again := RandomNumberGenerator.new()
				again.seed = zone * 100000 + i
				world.equip_bot(copy, again)
				same = same and copy.get_meta("kind") == kind and copy.display_name == bot.display_name \
						and is_equal_approx(copy.stand_height, bot.stand_height)
				copy.free()
			bot.free()
		shares.append(counts)
	holder.queue_free()
	var near := func(count: int, share: float) -> bool:
		return absf(float(count) / rolls - share) < 0.03
	var fits := true
	for zone in 3:
		var c: Dictionary = shares[zone]
		fits = fits and near.call(c.exo, World.EXO_CHANCE[zone]) and near.call(c.walker, World.WALKER_CHANCE[zone])
	t.check(fits, "exo troopers and walkers come in their shares by ring (%s)" % str(shares))
	t.check(shares[0].walker == 0, "no walker in the outer ring")
	t.check(shares[2].walker > shares[1].walker and shares[1].walker > 0, "walkers are rarer in the middle than the core")
	t.check(not looks.has("stalker"), "the spider model has left Ashfront (%s)" % ", ".join(looks.keys()))
	t.check(looks.has("exo") and looks.has("walker") and looks.has("legionary"),
			"Ashfront's armies wear the exo, walker and Legion soldier skins")
	t.check(same, "a client rolls the same kind from the same seed")
	await t.frames(1)


static func _walker_body(t: Node, raid: Raid) -> void:
	print("Heavy units: the walker's body")
	var at := raid.player.global_position + Vector3(30, 0.2, 0)
	var walker := find_kind(raid, "walker", 1, at)
	t.check(walker != null, "the middle ring can roll a walker")
	if walker == null:
		return
	await t.frames(2)
	t.check(is_equal_approx(walker.body_height(), World.WALKER_HEIGHT), "a walker stands %.1f m tall" % walker.body_height())
	var shape := (walker._body_shape as CapsuleShape3D)
	t.check(shape != null and is_equal_approx(shape.height, World.WALKER_HEIGHT),
			"its collision capsule is as tall as it is")
	t.check(walker.get_eye_position().y - walker.global_position.y > 2.0, "its cannon looks out from up high")
	t.check(walker.walk_speed < 4.0 and walker.sprint_speed < 4.0, "a walker is slow on its feet")
	var brain := BotBrain.new()
	brain.name = "Brain"
	walker.add_child(brain)
	t.check(is_equal_approx(brain.turn_speed_deg, World.WALKER_TURN) and brain.air_error_deg < 1.0,
			"its aim comes round slowly but leads fliers well")
	var gun := walker.get_active_weapon() as Gun
	t.check(gun != null and gun.projectile == "", "it carries a hitscan cannon")
	var exo := find_kind(raid, "exo", 0, at + Vector3(4, 0, 0))
	t.check(exo != null and exo.health.max_armor > 0.0 and exo.get_active_weapon() is Gun
			and exo.walk_speed < 4.5, "an exo trooper is armored, a little slower, and carries a rifle, no blade")
	for bot: Actor in [walker, exo]:
		if bot:
			raid._remove_actor(bot)


static func _weak_spot(t: Node, raid: Raid) -> void:
	print("Heavy units: the walker's weak spot")
	var at := raid.player.global_position + Vector3(40, 0.2, 0)
	var walker := find_kind(raid, "walker", 2, at, 900)
	if walker == null:
		t.check(false, "the core can roll a walker")
		return
	walker.cmd.yaw = 0.0
	var shooter := raid.player
	var hit := func(from: Vector3) -> float:
		walker.health.health = walker.health.max_health
		walker.health.armor = 0.0
		var was := shooter.global_position
		shooter.global_position = from
		Combat.deal(walker, DamageInfo.make(20.0, shooter, "bullet", walker.global_position + Vector3(0, 1.2, 0)))
		shooter.global_position = was
		return walker.health.max_health - walker.health.health
	# The walker faces -Z: the front is toward -Z, the back toward +Z.
	var front: float = hit.call(at + Vector3(0, 0, -10))
	var side: float = hit.call(at + Vector3(10, 0, 0))
	var back: float = hit.call(at + Vector3(0, 0, 10))
	var above: float = hit.call(at + Vector3(1, 15, 1))
	t.check(is_equal_approx(front, 20.0) and is_equal_approx(side, 20.0),
			"from the front and the side a hit lands as it is (%.0f, %.0f)" % [front, side])
	t.check(is_equal_approx(back, 20.0 * World.WALKER_REAR_MULT) and is_equal_approx(above, back),
			"from behind or above it finds the power plant (%.0f, %.0f)" % [back, above])
	raid._remove_actor(walker)


static func _cap(t: Node, raid: Raid) -> void:
	print("Heavy units: one walker at each landmark")
	var world := raid.world
	if raid.strongpoints.size() < 2:
		t.check(false, "Ashfront has landmarks")
		return
	# The raid's own armies may already have walkers out: clear them, so the
	# cap is measured from nothing.
	for bot in raid.bots.duplicate():
		if bot.get_meta("kind", "") == "walker":
			raid._remove_actor(bot)
	await t.frames(1)
	var site := raid.strongpoints[0].global_position
	var other_site := raid.strongpoints[1].global_position
	var first := find_kind(raid, "walker", 1, site + Vector3(3, 0.5, 0), 2000)
	t.check(first != null and world.bot_allowed(first, raid), "the first walker at a landmark is let in")
	var second := find_kind(raid, "walker", 1, site + Vector3(-3, 0.5, 0), 3000)
	t.check(second != null and not world.bot_allowed(second, raid), "a second walker at the same landmark is turned away")
	var elsewhere := find_kind(raid, "walker", 1, other_site + Vector3(3, 0.5, 0), 4000)
	t.check(elsewhere != null and world.bot_allowed(elsewhere, raid), "another landmark may have its own")
	var exo := find_kind(raid, "exo", 1, site + Vector3(0, 0.5, 3), 5000)
	t.check(exo != null and world.bot_allowed(exo, raid), "exo troopers are not capped")
	if second:
		raid.warlords[second] = true
		t.check(not world.bot_allowed(second, raid), "a warlord is never a walker")
		raid.warlords.erase(second)
	for bot: Actor in [first, second, elsewhere, exo]:
		if bot:
			raid._remove_actor(bot)
