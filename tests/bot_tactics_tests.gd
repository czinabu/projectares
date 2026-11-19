extends RefCounted
## Group fights (DESIGN.md "Group fights"): army bots take turns shooting at a
## person (attack slots by ring), shoot back when hit or up close, hold off in
## cover while they wait, spot a far or crouched body more slowly, and raise
## the gun before the first shot. Called from the test runner (`-- --only
## bot_tactics` runs just these).

const DT := 1.0 / 60.0


static func run(t: Node) -> void:
	print("Bot tactics: group fights take turns")
	BotBrain._slots.clear()
	var tps := Engine.physics_ticks_per_second

	# Slots on one person: never more than allowed, and a beat between turns.
	var key := 900001
	t.check(BotBrain.take_slot(key, 1, 2, 1000, null), "the first bot gets a slot")
	t.check(not BotBrain.take_slot(key, 2, 2, 1001, null), "a second waits a beat before the next slot opens")
	var beat_end := 1000 + int(0.5 * tps) + 10
	t.check(BotBrain.take_slot(key, 2, 2, beat_end, null), "after the beat the second slot is taken")
	t.check(not BotBrain.take_slot(key, 3, 2, beat_end + tps, null), "a third bot waits while both slots are held")
	t.check(BotBrain.slot_holders(key, beat_end + tps) == 2, "two hold slots on the person")
	t.check(BotBrain.take_slot(key, 1, 2, beat_end + tps, null), "a holder keeps its slot while it lasts")
	# The first hold (3 s without a brain) runs out: its slot passes on after a beat.
	var expired := 1000 + 3 * tps
	t.check(not BotBrain.take_slot(key, 3, 2, expired, null), "a slot let go is not taken in the same tick")
	t.check(BotBrain.take_slot(key, 3, 2, expired + int(0.5 * tps), null), "it passes to a waiting bot after the beat")
	var one_key := 900002
	t.check(BotBrain.take_slot(one_key, 1, 1, 0, null) and not BotBrain.take_slot(one_key, 2, 1, 2 * tps, null),
			"an outer-ring person is shot at by one bot at a time")
	BotBrain._slots.clear()

	# Spotting slows with distance and a crouch.
	var near := BotBrain.notice_mult(5.0, 60.0, false, 1.6, 1.3)
	var far := BotBrain.notice_mult(60.0, 60.0, false, 1.6, 1.3)
	var low := BotBrain.notice_mult(5.0, 60.0, true, 1.6, 1.3)
	t.check(near < 1.1 and absf(far - 1.6) < 0.01, "a body at the edge of sight takes 1.6x as long to spot (%.2f, %.2f)" % [near, far])
	t.check(low > near * 1.25, "a crouched body takes longer to spot (%.2f vs %.2f)" % [low, near])

	var raid: Raid = await t._new_raid(41, false)
	var player := raid.add_player()
	await t.frames(2)
	var bots: Array[Actor] = []
	for bot in raid.bots:
		if bot.weapons.size() > 0 and bot.get_active_weapon() is Gun and bots.size() < 3:
			bots.append(bot)
	t.check(bots.size() == 3, "three gun bots to test with")
	t.check(BotBrain.is_person(player), "a player takes slots")
	t.check(not BotBrain.is_person(bots[0]), "an army bot does not")
	var brains: Array[BotBrain] = []
	for i in bots.size():
		var brain := bots[i].get_node("Brain") as BotBrain
		brains.append(brain)
	t.check(brains[0].attack_slots == BotBrain.RING_SLOTS[clampi(int(bots[0].get_meta("zone", 1)), 0, 2)],
			"a bot's slots come from its ring")

	# Three outer-ring bots on one player at 20 m: one shoots, two hold off.
	for i in bots.size():
		var brain := brains[i]
		brain.attack_slots = 1
		brain.target = player
		brain._rest_until = 0
		brain._hit_at = -1000000
		bots[i].global_position = player.global_position + Vector3.FORWARD.rotated(Vector3.UP, 0.3 * (i - 1)) * 20.0
	var shooting := 0
	for i in bots.size():
		if brains[i]._may_attack(20.0):
			shooting += 1
	t.check(shooting == 1, "with one slot only one of three bots may shoot (%d)" % shooting)
	t.check(BotBrain.slot_holders(player.get_instance_id(), Engine.get_physics_frames()) == 1, "the slot is held on the player")
	var waiting := brains[2] if brains[0]._may_attack(20.0) else brains[0]
	# A waiting bot never pulls the trigger.
	var cmd := waiting.actor.cmd
	cmd.primary = false
	waiting._seen_time = 10.0
	waiting._wait_turn(cmd, DT, 20.0)
	t.check(not cmd.primary and not cmd.primary_pressed, "a bot waiting its turn holds fire")
	# Hit by the player, it shoots back at once; up close, too.
	waiting._hit_by = player
	waiting._hit_at = Engine.get_physics_frames()
	t.check(waiting._may_attack(20.0), "a bot that was just shot always shoots back")
	waiting.holds_turn = true
	t.check(not waiting._may_attack(20.0), "unless its kind holds its turn when hit")
	t.check(waiting._may_attack(4.0), "which still fights back at point blank")
	waiting.holds_turn = false
	waiting._hit_at = -1000000
	t.check(waiting._may_attack(4.0), "a bot always fights someone at point blank")
	t.check(not waiting._may_attack(20.0), "otherwise it waits its turn")
	# Another bot as the target is never rationed.
	waiting.target = bots[1] if waiting != brains[1] else bots[0]
	t.check(waiting._may_attack(20.0), "bots fighting bots are not rationed")
	waiting.target = player
	# Dying lets the slot go.
	var holder: BotBrain
	for brain in brains:
		if BotBrain._slots.get(player.get_instance_id(), {}).get("holders", {}).has(brain.get_instance_id()):
			holder = brain
	t.check(holder != null, "one bot is the slot holder")
	if holder:
		holder._release()
		t.check(BotBrain.slot_holders(player.get_instance_id(), Engine.get_physics_frames()) == 0,
				"a bot that dies or loses its target lets go of its slot")

	# A first sight that comes from being shot is quicker.
	var react := brains[1]
	react._rng.seed = 7
	react._aim_target = null
	react._hit_at = -1000000
	var eye := react.actor.get_eye_position()
	var chest := player.global_position + Vector3(0, 1.1, 0)
	react._aim_gun(react.actor.cmd, eye, chest, eye.distance_to(chest), DT)
	var calm := react._reaction
	react._rng.seed = 7
	react._aim_target = null
	react._hit_by = player
	react._hit_at = Engine.get_physics_frames()
	react._aim_gun(react.actor.cmd, eye, chest, eye.distance_to(chest), DT)
	t.check(react._reaction < calm * 0.6, "a bot shot by someone reacts to them faster (%.2f vs %.2f s)" % [react._reaction, calm])
	BotBrain._slots.clear()
	await t._end_raid(raid)
