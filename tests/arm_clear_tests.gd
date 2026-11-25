extends RefCounted
## The arms keep out of the body and the armor on it through a swing
## (Caleb's call: no arm through the armor in any swing, and held
## naturally). `WeaponArm.learn_trunk` learns the trunk's outline from the
## skin and what is worn on it; `WeaponArm._keep_clear` steers each arm
## round it. The checks read the posed bones inside `skeleton_updated`
## (the arms' reach holds only until the frame ends), and measure the arm
## against the outline the way the arm does. `--swing-clip-only` measures
## the real meshes.

const MOVES := ["light_right", "light_left", "overhead", "heavy"]


static func run(t: Node) -> void:
	print("Arms clear of the armor through a swing")
	Look.enabled = true
	var raid := Raid.new()
	t.add_child(raid)
	raid.start(Worlds.get_world("ashfront"), 44, ["blade_scrap", "frame_bulwark"])
	await t.frames(10)
	var p := raid.player
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
		bot.global_position += Vector3(0, -200, 0)
	var skin := p.get_node_or_null("Skin")
	var arm = skin.arm if skin != null else null
	t.check(arm != null and arm.has_method("learn_trunk"), "the player's model has a weapon arm that keeps clear")
	if arm == null:
		Look.enabled = false
		raid.queue_free()
		return
	await t.frames(5)
	# Heavy armor widens the outline it keeps out of; none, the body's own.
	var armored := _width(arm)
	t.check(armored > 0.0, "the trunk's outline is learned (%.2f wide)" % armored)
	p.frame_id = ""
	await t.frames(5)
	var bare := _width(arm)
	t.check(bare > 0.0 and armored > bare + 0.02,
			"heavy armor widens the outline the arms keep out of (%.2f against %.2f bare)" % [armored, bare])
	p.frame_id = "frame_bulwark"
	await t.frames(5)

	var blade: MeleeWeapon = null
	for i in p.weapons.size():
		if p.weapons[i] is MeleeWeapon:
			blade = p.weapons[i]
			p.active_weapon_index = i
	await t.frames(40)
	var sk: Skeleton3D = arm.skeleton
	var deepest := {}
	var catch := func() -> void:
		var key: String = deepest.get("key", "")
		if key != "":
			var d := _deepest(arm, sk)
			deepest[key] = maxf(deepest.get(key, -INF), d)
			if d > 0.02:
				deepest[key + "|in"] = int(deepest.get(key + "|in", 0)) + 1
	sk.skeleton_updated.connect(catch)
	for clear: bool in [false, true]:
		arm.keep_clear = clear
		for move: String in MOVES:
			blade.light_stamina = 0.0
			blade.heavy_stamina = 0.0
			p.stamina = p.max_stamina
			deepest["key"] = ""
			await t.frames(50)
			blade.combo_step = {"light_right": 0, "light_left": 1, "overhead": 2, "heavy": 0}[move]
			blade._combo_timer = 1.0 if blade.combo_step > 0 else 0.0
			deepest["key"] = "%s|%s" % [move, clear]
			if move == "heavy":
				p.cmd.tertiary_pressed = true
			else:
				p.cmd.primary_pressed = true
			for k in 70:
				await t.frames(1)
				p.cmd.primary_pressed = false
				p.cmd.tertiary_pressed = false
	deepest["key"] = ""
	sk.skeleton_updated.disconnect(catch)
	# Kept clear, an arm may still graze the armor for a frame or two as it
	# sweeps in faster than it is steered out; left alone, it goes through.
	for move: String in MOVES:
		var off: float = deepest.get("%s|false" % move, -INF)
		var on: float = deepest.get("%s|true" % move, -INF)
		var off_in: int = deepest.get("%s|false|in" % move, 0)
		var on_in: int = deepest.get("%s|true|in" % move, 0)
		t.check(on < 0.1 and on < off * 0.5 and on_in <= maxi(3, off_in / 4),
				"%s in heavy armor: the arms stay out of the trunk (%.3f m at the deepest, %d frames over 2 cm; left alone %.3f m, %d frames)"
				% [move, on, on_in, off, off_in])
	# Nothing in the way, nothing moves: a hold that clears keeps its pose.
	arm.keep_clear = true
	p.frame_id = ""
	await t.frames(60)
	t.check((arm._clear_now[0] as Vector3).is_zero_approx(),
			"with no armor the ready hold is left as it is (%s)" % [arm._clear_now[0]])
	Look.enabled = false
	raid.queue_free()
	await t.frames(2)


## The outline's widest reach.
static func _width(arm: Node) -> float:
	var widest := 0.0
	for r: float in arm._trunk:
		widest = maxf(widest, r)
	return widest / arm._unit()


## How deep (m) either arm is in the trunk now, the elbow and down.
static func _deepest(arm: Node, sk: Skeleton3D) -> float:
	var chest: Transform3D = sk.get_bone_global_pose(arm._chest).affine_inverse()
	var worst := -INF
	for bones: Array in [[arm._upper, arm._forearm, arm._wrist], [arm._off_upper, arm._off_forearm, arm._off_wrist]]:
		if bones.has(-1):
			continue
		var at: Array[Vector3] = []
		for b: int in bones:
			at.append(sk.get_bone_global_pose(b).origin)
		var elbow_on := at[0].distance_to(at[1])
		var hand_on := at[1].distance_to(at[2])
		var pole: Vector3 = at[1] + (at[1] - Geometry3D.get_closest_point_to_segment_uncapped(at[1], at[0], at[2]))
		worst = maxf(worst, arm._arm_depth(at[0], at[2], pole, elbow_on, hand_on, chest))
	return worst / arm._unit()
