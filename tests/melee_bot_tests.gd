extends RefCounted
## Melee bots fight like people (DESIGN.md "Melee bots"): they hold heavies,
## feint by switching side mid-charge, open with a dash-strike from a sprint,
## and an army gunner cut by a blade flinches. Called from the test runner
## (`-- --only melee_bots` runs just these).

const DT := 1.0 / 60.0


static func run(t: Node) -> void:
	print("Melee bots: heavies, feints, dash-strikes and the flinch")
	var raid: Raid = await t._new_raid(43, false)
	var fighter: Actor = raid.bots[0]
	var foe: Actor = raid.bots[1]
	var brain := fighter.get_node("Brain") as BotBrain
	var probe := BotBrain.new()
	t.check(BotBrain.RING_DASH[0] == 0.0 and BotBrain.RING_DASH[2] > BotBrain.RING_DASH[1],
			"the outer ring never dash-strikes, the core most")
	t.check(BotBrain.RING_FEINT[0] == 0.0 and BotBrain.RING_FEINT[2] > 0.0, "feints come further in")
	t.check(BotBrain.RING_HEAVY[2] > BotBrain.RING_HEAVY[0], "core bots hold more heavies")
	probe.free()

	var blade := MeleeWeapon.new()
	blade.display_name = "Test blade"
	fighter.equip_weapon(blade)
	fighter.cmd.switch_weapon = fighter.weapons.size() - 1
	await t.frames(3)
	t.check(fighter.get_active_weapon() == blade, "the fighter holds the blade")
	brain.target = foe
	brain._seen_time = 10.0
	brain.reaction_time = 0.0
	foe.global_position = fighter.global_position + Vector3(0, 0, -2.0)
	_face(fighter, foe)

	# A held heavy: the charge turns into a heavy windup.
	brain.heavy_share = 1.0
	brain.feint_chance = 0.0
	brain.dash_chance = 0.0
	fighter.stamina = fighter.max_stamina
	var kinds := await _drive(t, brain, blade, 75)
	t.check("heavy" in kinds, "a bot holds the attack button into a heavy (%s)" % str(kinds))
	await _settle(t, brain, blade)

	# A feint: it shows one side, then lets go as a light from another.
	brain.heavy_share = 0.0
	brain.feint_chance = 1.0
	brain._melee_wait = 0.0
	foe.global_position = fighter.global_position + Vector3(0, 0, -2.0)
	_face(fighter, foe)
	fighter.stamina = fighter.max_stamina
	var shown := -1
	var struck := -1
	for i in 40:
		_think(brain, blade)
		if blade.is_charging() and shown < 0:
			shown = blade.threat_dir()
		await t.frames(1)
		if blade.is_winding_up() and struck < 0:
			struck = blade.attack_dir
	t.check(shown >= 0 and struck >= 0 and shown != struck,
			"a feint shows one side and strikes from another (%d then %d)" % [shown, struck])
	await _settle(t, brain, blade)

	# A dash-strike: sprinting in from out of reach.
	brain.feint_chance = 0.0
	brain.dash_chance = 1.0
	brain._dash_wait = 0.0
	# Posted where it stands, so closing in is within its leash.
	brain.post_to(fighter.global_position, 12.0)
	foe.global_position = fighter.global_position + Vector3(0, 0, -7.0)
	_face(fighter, foe)
	fighter.stamina = fighter.max_stamina
	var dashed := false
	for i in 30:
		_think(brain, blade)
		await t.frames(1)
		dashed = dashed or blade._dashing
	t.check(dashed, "a sprinting bot opens with a dash-strike from 7 m")
	await _settle(t, brain, blade)

	# The flinch: an army gunner cut by a blade holds fire, gun knocked off.
	var gunner: Actor
	for bot in raid.bots:
		if bot != fighter and bot.get_active_weapon() is Gun:
			gunner = bot
			break
	t.check(gunner != null, "a gun bot to cut")
	if gunner:
		var gun_brain := gunner.get_node("Brain") as BotBrain
		gun_brain._aim = Vector3.FORWARD
		var cut := DamageInfo.new()
		cut.kind = "melee"
		cut.amount = 20.0
		cut.source = fighter
		gun_brain._on_damaged(cut)
		t.check(gun_brain._flinch_left > 0.3, "a gunner cut by a blade flinches")
		t.check(rad_to_deg(gun_brain._aim.angle_to(Vector3.FORWARD)) > 8.0, "its gun is knocked off aim")
		gun_brain._flinch_left = 0.0
		var shot := DamageInfo.new()
		shot.kind = "bullet"
		shot.amount = 20.0
		shot.source = fighter
		gun_brain._on_damaged(shot)
		t.check(gun_brain._flinch_left <= 0.0, "a bullet does not make it flinch")
		gun_brain.uses_kit = true
		gun_brain._on_damaged(cut)
		t.check(gun_brain._flinch_left <= 0.0, "a bot that plays like a person never flinches (nor does a player)")
	await t._end_raid(raid)


## Runs the brain's melee step for `count` ticks and lists the swings made.
static func _drive(t: Node, brain: BotBrain, blade: MeleeWeapon, count: int) -> Array:
	var kinds := []
	var note := func(kind: String) -> void: kinds.append(kind)
	blade.swung.connect(note)
	for i in count:
		_think(brain, blade)
		await t.frames(1)
	blade.swung.disconnect(note)
	return kinds


static func _think(brain: BotBrain, blade: MeleeWeapon) -> void:
	# No player is near, so the raid thins these bots (a step every few
	# ticks) and a one-tick press could be missed: keep this one at every tick.
	brain.actor.thin(1)
	var cmd := brain.actor.cmd
	cmd.clear_one_shots()
	cmd.primary = false
	cmd.secondary = false
	cmd.sprint = false
	cmd.move = Vector2.ZERO
	brain._attack_melee(cmd, blade, DT)


## Lets the blade finish its swing and the brain forget its charge.
static func _settle(t: Node, brain: BotBrain, blade: MeleeWeapon) -> void:
	brain._hold_left = 0.0
	brain.actor.cmd.clear_one_shots()
	brain.actor.cmd.primary = false
	brain.actor.cmd.secondary = false
	brain.actor.cmd.sprint = false
	brain.actor.cmd.move = Vector2.ZERO
	await t.frames(90)
	brain._melee_wait = 0.0
	brain._guard_delay = 0.0


static func _face(actor: Actor, other: Actor) -> void:
	var to := other.global_position - actor.global_position
	actor.cmd.yaw = atan2(-to.x, -to.z)
