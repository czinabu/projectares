extends RefCounted
## Checks that bots aim like people, not like an aimbot: a reaction delay, no
## snap onto a target, a wander that starts wide and settles, and worse aim
## at moving, airborne and distant targets. Called from the test runner
## (`-- --only bot_aim` runs just these).

const DT := 1.0 / 60.0


static func run(t: Node) -> void:
	print("Bot aim: human, not aimbot")
	var raid: Raid = await t._new_raid(31, false)
	var shooter: Actor = raid.bots[0]
	var foe: Actor = raid.bots[1]
	var brain := shooter.get_node("Brain") as BotBrain
	t.check(brain.skill >= 0.0 and brain.skill <= 1.0, "each bot rolls an aim skill between rookie and veteran")
	brain.skill = 1.0
	shooter.global_position = Vector3(0, 0, 0)
	shooter.velocity = Vector3.ZERO
	foe.global_position = Vector3(0, 0, -12)
	foe.velocity = Vector3.ZERO
	foe.airborne_time = 0.0

	# Facing straight away, the bot turns: it does not snap.
	brain.target = foe
	brain._aim_target = null
	brain._aim = Vector3.ZERO
	shooter.cmd.yaw = 0.0 + PI  # looking +Z, the foe is at -Z
	shooter.cmd.pitch = 0.0
	_tick(brain, 1)
	var to := _to(shooter, foe)
	t.check(rad_to_deg(brain._aim.angle_to(to)) > 150.0 and not brain._on_target,
			"a bot facing away does not snap onto a target in one tick")
	t.check(brain._reaction >= brain.reaction_time * 0.4, "even a veteran waits a reaction time before firing")
	_tick(brain, 90)
	t.check(rad_to_deg(brain._aim.angle_to(to)) < 15.0 and brain._on_target, "within a moment and a half it has turned onto it")

	# First sight is wide; it settles while held in view.
	var first := _spread(brain, foe, 0.0, 20)
	var settled := _spread(brain, foe, brain.settle_time + 0.5, 120)
	t.check(first > settled * 1.8, "aim on first sight is wider than once settled (%.2f vs %.2f deg)" % [first, settled])
	t.check(settled > 0.25, "even settled, a veteran's aim wanders (%.2f deg)" % settled)

	# Moving, airborne and distant targets are harder.
	foe.velocity = Vector3(6, 0, 0)
	var moving := _spread(brain, foe, 4.0, 120)
	foe.velocity = Vector3.ZERO
	t.check(moving > settled * 1.5, "a target running sideways is harder to track (%.2f vs %.2f deg)" % [moving, settled])
	foe.airborne_time = 1.0
	var flying := _spread(brain, foe, 4.0, 120)
	foe.airborne_time = 0.0
	t.check(flying > settled * 1.5, "a target in the air is harder to hit (%.2f vs %.2f deg)" % [flying, settled])
	foe.global_position = Vector3(0, 0, -30)
	var far := _spread(brain, foe, 4.0, 120)
	foe.global_position = Vector3(0, 0, -12)
	t.check(far > settled * 1.3, "a distant target gets a wider aim (%.2f vs %.2f deg)" % [far, settled])

	# A rookie is worse than a veteran.
	brain.skill = 0.0
	var rookie := _spread(brain, foe, 4.0, 120)
	t.check(rookie > settled * 1.5, "a rookie's aim wanders more than a veteran's (%.2f vs %.2f deg)" % [rookie, settled])
	brain._aim_target = null
	brain.target = foe
	_tick(brain, 1)
	t.check(brain._reaction > brain.reaction_time, "a rookie reacts slower than the base reaction time")
	await t._end_raid(raid)


static func _to(shooter: Actor, foe: Actor) -> Vector3:
	return (foe.global_position + Vector3(0, 1.1, 0) - shooter.get_eye_position()).normalized()


## Steps the brain's gun aim `count` ticks, as `_physics_process` would.
static func _tick(brain: BotBrain, count: int) -> void:
	var eye := brain.actor.get_eye_position()
	for i in count:
		var chest := brain.target.global_position + Vector3(0, 1.1, 0)
		brain._seen_time += DT
		brain._aim_gun(brain.actor.cmd, eye, chest, eye.distance_to(chest), DT)


## Mean angle, degrees, between the bot's aim and the target's chest over
## `count` ticks, starting `seen` seconds into holding it in view. The aim
## starts on the target and the rolls are seeded, so runs compare fairly.
static func _spread(brain: BotBrain, foe: Actor, seen: float, count: int) -> float:
	brain._rng.seed = 99
	brain.target = foe
	brain._aim_target = foe
	brain._seen_time = seen
	brain._wander = Vector2(0.6, 0.6)
	brain._wander_left = 0.0
	brain._aim = _to(brain.actor, foe)
	var total := 0.0
	for i in count:
		_tick(brain, 1)
		total += rad_to_deg(brain._aim.angle_to(_to(brain.actor, foe)))
	return total / count
