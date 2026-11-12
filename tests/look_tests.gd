extends RefCounted
## Checks for the art layer (`Look`). Kept in its own file and called from the
## test runner. The suite runs headless, where `Look` is off by default, so
## these switch it on for their own raid and off again afterwards.

const Locomotion := preload("res://core/visual/locomotion.gd")


static func run(t: Node) -> void:
	t.check(not Look.enabled, "the art layer is off on a headless server")
	var plain := Look.surface("concrete", {"tint": Color.RED})
	t.check(plain is StandardMaterial3D, "headless surfaces are plain materials with no textures")
	t.check(Look.prop("AC.glb", 1.0) == null, "headless props are not loaded")
	var bare := Raid.new()
	t.add_child(bare)
	bare.start(Worlds.get_world("ashfront"), 5)
	await t.frames(3)
	t.check(not bare.player.has_node("Skin") and bare.player.body_mesh.mesh != null,
			"headless actors keep their greybox body")
	bare.queue_free()
	await t.frames(2)

	Look.enabled = true
	Look._materials.clear()
	var concrete := Look.surface("concrete", {"tint": Color(0.5, 0.5, 0.5)})
	t.check(concrete is ShaderMaterial and concrete.get_shader_parameter("albedo_tex") != null,
			"a surface is a textured material")
	t.check(Look.surface("concrete", {"tint": Color(0.5, 0.5, 0.5)}) == concrete, "equal surfaces are shared")
	for kind: String in Look.SURFACES:
		var dir: String = Look.TEXTURES + Look.SURFACES[kind]["tex"] + "/"
		t.check(ResourceLoader.exists(dir + "Color.jpg") and ResourceLoader.exists(dir + "NormalGL.jpg")
				and ResourceLoader.exists(dir + "Roughness.jpg"), "surface '%s' has its textures" % kind)
	for skin: String in Look.SKINS:
		for scene: String in Look.SKINS[skin].get("scenes", []):
			t.check(ResourceLoader.exists(Look.CHARACTERS + scene), "skin '%s' has its model %s" % [skin, scene])
	for build in Look.Human.BUILDS:
		var human: Node3D = Look._instance(Look.Human.rig_path(build))
		var human_anims := human.find_child("AnimationPlayer", true, false) as AnimationPlayer
		var has_all := human_anims != null
		for key: String in Look.HUMAN_ANIMS:
			has_all = has_all and human_anims.has_animation(Look.HUMAN_ANIMS[key])
		t.check(has_all, "human rig %s has every animation the skin plays" % build)
		human.free()
	var crate := Look.prop("Lootbox.glb", 1.2)
	var crate_size := Look.model_bounds(crate).size
	t.check(absf(maxf(crate_size.x, maxf(crate_size.y, crate_size.z)) - 1.2) < 0.05, "a prop is scaled to the size asked for")
	t.check(crate.find_children("*", "CollisionObject3D", true, false).is_empty(), "props have no collision")
	crate.free()

	for world in Worlds.raid_worlds():
		var raid := Raid.new()
		t.add_child(raid)
		raid.start(world, 11)
		await t.frames(4)
		var tag := "[%s] " % world.id
		t.check(raid.find_child("Atmosphere", true, false) is WorldEnvironment, tag + "the map has a sky and atmosphere")
		t.check(raid.find_child("Dressing", true, false) != null, tag + "the map is dressed")
		var skin := raid.player.get_node_or_null("Skin")
		t.check(skin != null and skin.find_child("AnimationPlayer", true, false) != null,
				tag + "the player wears an animated model")
		t.check(raid.player.body_mesh != null and raid.player.body_mesh.mesh == null,
				tag + "the greybox capsule is no longer drawn")
		var skeleton := skin.find_child("Skeleton3D", true, false) as Skeleton3D
		t.check(skin.arm.grip_bone >= 0 and skeleton != null, tag + "the player's model has a hand to hold a weapon")
		if skin.arm.grip_bone >= 0 and skeleton != null:
			skin.arm.hold_weapon()
			var palm: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(skin.arm.grip_bone).origin
			t.check(raid.player.hand.global_position.distance_to(palm) < 0.2, tag + "the weapon sits in the model's hand")
			t.check(raid.player.hand.global_position.distance_to(raid.player.to_global(Actor.HAND_REST)) > 0.05,
					tag + "the weapon is no longer left floating at the greybox hand spot")
			raid.player.hand_override = true
			raid.player.hand.position = Vector3(5, 5, 5)
			skin.arm.hold_weapon()
			t.check(raid.player.hand.position.is_equal_approx(Vector3(5, 5, 5)), tag + "the model leaves the hand alone in first person")
			raid.player.hand_override = false
		# The weapon arm shows the side of a melee attack or guard.
		var sword: MeleeWeapon = null
		for held in raid.player.weapons:
			if held is MeleeWeapon:
				sword = held
		t.check(skin.arm.reach_ik != null, tag + "the player's model can pose its weapon arm")
		if sword != null and skin.arm.reach_ik != null:
			t.check(skin.arm.arm_reach(sword) == null, tag + "the animation keeps the arm when no attack or guard is up")
			var reaches := {}
			for side: int in [MeleeWeapon.Dir.LEFT, MeleeWeapon.Dir.RIGHT, MeleeWeapon.Dir.OVERHEAD]:
				sword._windup_left = 1.0
				sword.attack_dir = side
				reaches[skin.arm.arm_reach(sword)] = true
			t.check(reaches.size() == 3 and not reaches.has(null), tag + "each attack side cocks the arm differently")
			var left: Vector3 = skin.arm.arm_windup[MeleeWeapon.Dir.LEFT]
			var right: Vector3 = skin.arm.arm_windup[MeleeWeapon.Dir.RIGHT]
			t.check(left.x < right.x, tag + "a left windup holds the hand further to the actor's left")
			t.check(skin.arm.arm_windup[MeleeWeapon.Dir.OVERHEAD].y > maxf(left.y, right.y), tag + "an overhead windup raises the hand highest")
			# The body turns with the arm, opposite ways for opposite sides.
			sword.attack_dir = MeleeWeapon.Dir.LEFT
			var turn_left: Vector2 = skin.arm.body_turn(sword)
			sword.attack_dir = MeleeWeapon.Dir.RIGHT
			var turn_right: Vector2 = skin.arm.body_turn(sword)
			t.check(turn_left.x > 0.1 and turn_right.x < -0.1, tag + "the shoulders turn toward the side being wound up")
			# The swing sweeps round in front instead of cutting straight across.
			sword._windup_left = 0.0
			sword._swing_left = MeleeWeapon.SWING_TIME * 0.5
			var mid: Vector3 = skin.arm.arm_reach(sword)
			var straight: Vector3 = (skin.arm.arm_windup[MeleeWeapon.Dir.RIGHT] + skin.arm.arm_follow[MeleeWeapon.Dir.RIGHT]) * 0.5
			t.check(mid.z < straight.z - 0.05, tag + "the hand bows forward through a swing")
			t.check(signf(skin.arm.body_turn(sword).x - turn_right.x) > 0.0, tag + "the shoulders unwind through a swing")
			sword._swing_left = 0.0
			skin.arm._follow_left = 0.1
			skin.arm._follow_dir = MeleeWeapon.Dir.RIGHT
			t.check(skin.arm.arm_reach(sword) == skin.arm.arm_follow[MeleeWeapon.Dir.RIGHT], tag + "the follow-through is held after the swing lands")
			skin.arm._follow_left = 0.0
			sword._windup_left = 1.0
			t.check(not skin.arm._fist.is_empty() and skin.arm._grip_axis.length() > 0.9, tag + "the model knows how to close its hand on a handle")
			t.check(skin.arm.off_ik != null and not skin.arm._off_fist.is_empty(), tag + "the model has an off hand for two-handed weapons")
			raid.player.hand_override = true
			t.check(skin.arm.arm_reach(sword) == null, tag + "the arm is left alone in first person")
			raid.player.hand_override = false
			sword._windup_left = 0.0
			sword._blocking = true
			t.check(skin.arm.arm_reach(sword) != null, tag + "a guard raises the arm")
			sword._blocking = false
			var was_active := raid.player.active_weapon_index
			raid.player.active_weapon_index = raid.player.weapons.find(sword)
			sword.visual.position = Vector3(0.2, 0.1, 0.0)
			skin.arm.hold_weapon()
			var grip_at: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(skin.arm.grip_bone).origin
			t.check(sword.visual.global_position.distance_to(grip_at) < 0.02, tag + "the blade stays in the hand when its pose shifts it")
			sword.visual.position = Vector3.ZERO
			raid.player.active_weapon_index = was_active
		_check_legs(t, tag, raid.player, skin, skeleton)
		var dressed := 0
		var skins := {}
		for bot in raid.bots:
			if bot.has_node("Skin"):
				dressed += 1
				skins[bot.get_meta("look", "")] = true
		t.check(dressed == raid.bots.size(), tag + "every bot wears a model")
		t.check(not skins.has("") and not skins.is_empty(), tag + "the world picks its bots' skins")
		var gun := raid.player.weapons[0] as Gun
		t.check(gun != null and gun.visual.get_node_or_null("Model") != null, tag + "the rifle has a gun model")
		var crates := 0
		var caches := 0
		for node in raid.find_children("*", "StaticBody3D", true, false):
			if node is LootContainer:
				caches += 1
				crates += 1 if node.has_node("Crate") else 0
		t.check(caches > 0 and crates == caches, tag + "every cache is a crate")
		# The art layer must not change the simulation.
		var before := raid.player.health.health
		Combat.deal(raid.player, DamageInfo.make(10.0, raid.bots[0], "bullet"))
		t.check(raid.player.health.health < before or raid.player.health.armor >= 0.0, tag + "damage still lands on a dressed actor")
		raid.player.health.health = 1.0
		raid.player.health.armor = 0.0
		Combat.deal(raid.player, DamageInfo.make(500.0, raid.bots[0], "bullet"))
		await t.frames(2)
		t.check(raid.player.is_dead, tag + "a dressed actor still dies")
		raid.queue_free()
		await t.frames(2)

	# Gun models are picked by tag.
	var picks := {}
	for tag: String in ["smg", "marksman", "shotgun", "rifle"]:
		for entry: Array in Look.GUN_MODELS:
			if entry[0] == tag:
				picks[entry[1]] = true
				t.check(ResourceLoader.exists(Look.WEAPONS + entry[1]), "a '%s' has a model" % tag)
	t.check(picks.size() == 4, "each gun type has its own model")

	# Melee models, also by tag, standing blade-up with the grip at the hand.
	for entry: Array in Look.MELEE_MODELS + [Look.DEFAULT_MELEE]:
		t.check(ResourceLoader.exists(Look.WEAPONS + entry[1]), "melee model %s exists" % entry[1])
	var blade := MeleeWeapon.new()
	var blade_model := Look.weapon_model(blade)
	t.check(blade_model != null, "a blade gets a model")
	if blade_model:
		var blade_box := Look.model_bounds(blade_model)
		t.check(blade_box.size.y > 3.0 * maxf(blade_box.size.x, blade_box.size.z), "the blade model stands along the blade")
		t.check(blade_box.position.y < -0.05 and blade_box.end.y > 0.9, "the blade model is gripped near its handle")
		t.check(blade_model.find_children("*", "CollisionObject3D", true, false).is_empty(), "the blade model has no collision")
		blade_model.free()
	t.check(not Look.is_two_handed(blade), "a plain blade is one-handed")
	blade.item_id = "hammer_breaker"
	t.check(Look.is_two_handed(blade), "a hammer takes both hands")
	blade.free()

	t.check(FileAccess.file_exists("res://assets/LICENSES.md"), "asset licenses are recorded")
	var licenses := FileAccess.get_file_as_string("res://assets/LICENSES.md")
	for dir: String in ["characters", "weapons", "props", "textures", "sky", "fonts"]:
		t.check(licenses.contains("assets/" + dir), "licenses cover assets/%s" % dir)
	Look.enabled = false
	Look._materials.clear()


## The legs follow how the actor really moves: strides match speed, and the
## clip and the lower body follow the direction of travel.
static func _check_legs(t: Node, tag: String, player: Actor, skin: Node, skeleton: Skeleton3D) -> void:
	var loco: Node = skin.locomotion
	t.check(loco != null and loco.gaits.has("run") and loco.gaits.has("walk"),
			tag + "the model knows how fast its walk and run carry it")
	if loco == null or not loco.gaits.has("run") or not loco.gaits.has("walk"):
		return
	var run: Vector3 = loco.gaits["run"]
	t.check(run.z < 0.0 and absf(run.x) < 0.2 * run.length(), tag + "the run clip is measured carrying the body forward")
	t.check(run.length() > 1.5 and run.length() < 6.0, tag + "a run is measured at a person's speed (%.2f m/s)" % run.length())
	t.check(loco.gaits["walk"].length() < run.length() * 0.7, tag + "a walk is measured slower than a run")
	var sides := ["run_left", "run_right", "run_back"].all(func(k: String) -> bool: return loco.gaits.has(k))
	t.check(sides, tag + "the model has clips for running left, right and backward")
	if sides:
		t.check(loco.gaits["run_left"].x < 0.0 and loco.gaits["run_right"].x > 0.0 and loco.gaits["run_back"].z > 0.0,
				tag + "each side clip is measured going its own way")

	# No foot sliding: playback speed times the clip's own speed is the actor's.
	# No foot sliding at any speed: playback times stride times the clip's
	# own speed is the actor's speed.
	var steady := run.length() * 1.2
	var pick: Dictionary = loco.choose(Vector3(0.0, 0.0, -steady), false)
	t.check(pick.get("key") == "run" and is_equal_approx(pick["stride"], 1.0)
			and absf(pick["speed"] * run.length() - steady) < 0.01, tag + "a relaxed run plays at the speed the actor moves")
	var sprint: Dictionary = loco.choose(Vector3(0.0, 0.0, -player.sprint_speed), false)
	t.check(sprint.get("stride", 1.0) > 1.2 and absf(sprint["speed"] * sprint["stride"] * run.length() - player.sprint_speed) < 0.01,
			tag + "a sprint lengthens the stride instead of only spinning the legs, and the feet stay planted")
	t.check(sprint.get("speed", 0.0) > pick.get("speed", 0.0), tag + "a sprint still takes quicker strides than a jog")
	t.check(loco.choose(Vector3(0.0, 0.0, -loco.gaits["walk"].length()), false).get("stride") == 1.0,
			tag + "a walk keeps its own stride")
	var slow: Dictionary = loco.choose(Vector3(0.0, 0.0, -loco.gaits["walk"].length()), false)
	t.check(slow.get("key") == "walk" and absf(slow["speed"] - 1.0) < 0.01, tag + "a slow actor walks at the walk's own pace")
	t.check(loco.choose(Vector3(0.0, 0.0, -0.1), false).is_empty(), tag + "a still actor stands")

	# Direction: the clip going the right way, and no lower-body turn when it fits.
	var going := {"run_left": Vector3(-5, 0, 0), "run_right": Vector3(5, 0, 0), "run_back": Vector3(0, 0, 5)}
	for key: String in going:
		var way: Dictionary = loco.choose(going[key], false)
		t.check(way.get("key") == key and way["speed"] > 0.0 and absf(way["twist"]) < 0.1,
				tag + "moving that way plays %s" % key)
	var diagonal: Dictionary = loco.choose(Vector3(-4, 0, -4), false)
	var turned_left: bool = diagonal.get("twist", 0.0) > 0.0 if diagonal.get("key") == "run" else diagonal.get("twist", 0.0) < 0.0
	t.check(diagonal.get("key") in ["run", "run_left"] and absf(absf(diagonal["twist"]) - PI / 4.0) < 0.1 and turned_left,
			tag + "running diagonally turns the legs the rest of the way")
	t.check(loco.choose(Vector3(0, 0, -5), true).get("key") == "move_gun", tag + "running forward with a gun keeps it raised")
	t.check(loco.choose(Vector3(-5, 0, 0), true).get("key") == "run_left", tag + "strafing with a gun uses the strafe clip")
	var hold: Dictionary = loco.choose(Vector3(-5, 0, 0.3), false, "run_left", 1.0)
	t.check(hold.get("key") == "run_left", tag + "the clip playing now is kept near a border")

	# A model with only a forward run plays it backwards to backpedal.
	var plain := Locomotion.new()
	plain.gaits = {"run": Vector3(0, 0, -3)}
	var back: Dictionary = plain.choose(Vector3(0, 0, 4), false)
	t.check(back.get("key") == "run" and back["speed"] < 0.0 and absf(back["twist"]) < 0.01,
			"a model with no backward clip runs its forward one in reverse")
	var side: Dictionary = plain.choose(Vector3(-4, 0, 0), false)
	t.check(side.get("twist", 0.0) > 0.5, "a model with no side clip turns its legs toward the side it goes")
	plain.free()

	# End to end, from velocity alone, as a remote player's arrives from the server.
	var was_weapon := player.active_weapon_index
	var was_velocity := player.velocity
	player.active_weapon_index = 0
	player.velocity = player.global_basis * Vector3(-5, 0, 0)
	skin._process(1.0)
	skin._process(1.0)
	t.check(skin._current == "run_left", tag + "a strafing actor's model runs sideways")
	t.check(loco.overlay == (player.get_active_weapon() is Gun),
			tag + "the gun stays raised over the strafing legs")
	player.velocity = player.global_basis * Vector3(-4, 0, -4)
	skin._process(1.0)
	skin._process(1.0)
	t.check(absf(loco.twist_target) > 0.5 and absf(loco.twist) > 0.3, tag + "a model running diagonally turns its legs")
	# A sprint stretches the legs about their average pose: the feet reach
	# further apart than the clip alone puts them.
	player.velocity = player.global_basis * Vector3(0, 0, -player.sprint_speed)
	skin._process(1.0)
	skin._process(1.0)
	t.check(loco.stride > 1.2 and loco._means.has(loco.current_anim), tag + "a sprinting model lengthens its stride")
	if skeleton and loco._lead.size() == 3:
		var lead_foot: int = loco._lead[2]
		var trail_foot: int = loco._trail[2]
		var spread := func() -> float:
			return skeleton.get_bone_global_pose(lead_foot).origin.distance_to(skeleton.get_bone_global_pose(trail_foot).origin)
		var saved_feet := {}
		for bone: int in loco._legs + loco._feet:
			saved_feet[bone] = [skeleton.get_bone_pose_position(bone), skeleton.get_bone_pose_rotation(bone)]
		var before: float = spread.call()
		loco._stretch_stride()
		t.check(spread.call() > before - 0.001, tag + "a stretched stride puts the feet further apart")
		var shin_end: Vector3 = (skeleton.get_bone_global_pose(loco._lead[1]) * loco._foot_on_shin[lead_foot]).origin
		t.check(shin_end.distance_to(skeleton.get_bone_global_pose(lead_foot).origin) < 0.01,
				tag + "the legs reach the stretched feet, so no foot comes off its shin")
		for bone: int in saved_feet:
			skeleton.set_bone_pose_position(bone, saved_feet[bone][0])
			skeleton.set_bone_pose_rotation(bone, saved_feet[bone][1])

	# A slide bends the model: hips down, lead leg out in front.
	player.slide_left = 0.5
	player.crouch = 1.0
	player.velocity = player.global_basis * Vector3(0, 0, -player.slide_speed)
	skin._process(1.0)
	t.check(skin._current in ["idle", "idle_melee"], tag + "a sliding model stops running its legs")
	if skeleton and loco._lead.size() == 3:
		var saved_slide := {}
		for bone in skeleton.get_bone_count():
			saved_slide[bone] = [skeleton.get_bone_pose_position(bone), skeleton.get_bone_pose_rotation(bone)]
		var to_actor := player.global_transform.affine_inverse() * skeleton.global_transform
		var hips_before := (to_actor * skeleton.get_bone_global_pose(loco._lead[0]).origin).y
		loco._slide_pose()
		var hips_after := (to_actor * skeleton.get_bone_global_pose(loco._lead[0]).origin).y
		var lead_at := to_actor * skeleton.get_bone_global_pose(loco._lead[2]).origin
		var trail_at := to_actor * skeleton.get_bone_global_pose(loco._trail[2]).origin
		t.check(hips_after < hips_before - 0.3, tag + "a sliding model drops its hips")
		t.check(lead_at.z < trail_at.z - 0.3, tag + "a sliding model reaches its lead leg out in front")
		for bone: int in saved_slide:
			skeleton.set_bone_pose_position(bone, saved_slide[bone][0])
			skeleton.set_bone_pose_rotation(bone, saved_slide[bone][1])
	player.slide_left = 0.0
	player.crouch = 0.0

	# Standing still: a relaxed stand, not a gun pointed at nothing.
	player.velocity = Vector3.ZERO
	loco.velocity = Vector3.ZERO
	player.active_weapon_index = -1
	skin._aim_left = 0.0
	skin._process(1.0)
	t.check(skin._current == "idle", tag + "an actor standing empty-handed plays the plain idle")
	if skin._anims.has("aim_gun"):
		t.check(skin._anims["idle"] != skin._anims["aim_gun"], tag + "the empty-handed idle is not the gun-pointing pose")
	var gun_index := -1
	for i in player.weapons.size():
		if player.weapons[i] is Gun:
			gun_index = i
	if gun_index >= 0 and skin._anims.has("idle_gun"):
		player.active_weapon_index = gun_index
		skin._process(1.0)
		skin._process(1.0)
		t.check(skin._current == "idle_gun", tag + "an actor standing with a gun holds it low")
		t.check(loco.stand_legs and loco.stand_legs_weight > 0.99, tag + "with the gun held low the legs take the relaxed stand")
		if skeleton and loco._lead.size() == 3 and not loco._stand_tracks.is_empty():
			var to_actor_stand := player.global_transform.affine_inverse() * skeleton.global_transform
			var feet_apart := func() -> float:
				var a := to_actor_stand * skeleton.get_bone_global_pose(loco._lead[2]).origin
				var b := to_actor_stand * skeleton.get_bone_global_pose(loco._trail[2]).origin
				return absf(a.z - b.z)
			var saved_stand := {}
			for bone in skeleton.get_bone_count():
				saved_stand[bone] = [skeleton.get_bone_pose_position(bone), skeleton.get_bone_pose_rotation(bone)]
			var anim: Animation = skin._player.get_animation(skin._anims["aim_gun"])
			for track in anim.get_track_count():
				var bone := skeleton.find_bone(String(anim.track_get_path(track)).get_slice(":", 1))
				if bone < 0:
					continue
				if anim.track_get_type(track) == Animation.TYPE_ROTATION_3D:
					skeleton.set_bone_pose_rotation(bone, anim.rotation_track_interpolate(track, 0.0))
				elif anim.track_get_type(track) == Animation.TYPE_POSITION_3D:
					skeleton.set_bone_pose_position(bone, anim.position_track_interpolate(track, 0.0))
			var staggered: float = feet_apart.call()
			loco._stand_legs()
			var planted: float = feet_apart.call()
			t.check(planted < staggered - 0.05 and planted < 0.15,
					tag + "the relaxed stand puts the feet side by side (%.2f m apart front to back, was %.2f)" % [planted, staggered])
			for bone: int in saved_stand:
				skeleton.set_bone_pose_position(bone, saved_stand[bone][0])
				skeleton.set_bone_pose_rotation(bone, saved_stand[bone][1])
		if skin._anims.has("aim_gun"):
			player.cmd.primary = true
			skin._process(0.1)
			t.check(skin._current == "aim_gun" and not loco.stand_legs, tag + "firing from a stand raises the gun")
			player.cmd.primary = false
			skin._process(0.1)
			t.check(skin._current == "aim_gun", tag + "the gun stays up for a moment after the last shot")
			skin._process(skin.aim_hold)
			skin._process(0.1)
			t.check(skin._current == "idle_gun", tag + "the gun lowers again once the shooting stops")
	player.velocity = was_velocity
	player.active_weapon_index = was_weapon

	# The legs turn while the chest keeps facing the aim.
	if skeleton and not loco._spine.is_empty():
		var chest: int = loco._spine[loco._spine.size() - 1]
		var foot := skeleton.find_bone("Foot.L")
		var chest_before := skeleton.get_bone_global_pose(chest).basis.orthonormalized()
		var foot_before := skeleton.get_bone_global_pose(foot).origin
		var saved := {}
		for bone: int in loco._roots + loco._spine:
			saved[bone] = skeleton.get_bone_pose(bone)
		loco.twist = 0.6
		loco._turn_lower()
		var chest_after := skeleton.get_bone_global_pose(chest).basis.orthonormalized()
		var chest_moved := (chest_before.inverse() * chest_after).get_rotation_quaternion().get_angle()
		t.check(chest_moved < 0.02, tag + "the chest keeps facing the aim while the legs turn")
		t.check(skeleton.get_bone_global_pose(foot).origin.distance_to(foot_before) > 0.01 * skeleton.global_basis.inverse().get_scale().x,
				tag + "the feet turn toward the way the actor goes")
		loco.twist = 0.0
		for bone: int in saved:
			skeleton.set_bone_pose(bone, saved[bone])
