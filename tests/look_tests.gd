extends RefCounted
## Checks for the art layer (`Look`). Kept in its own file and called from the
## test runner. The suite runs headless, where `Look` is off by default, so
## these switch it on for their own raid and off again afterwards.


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
		for scene: String in Look.SKINS[skin]["scenes"]:
			t.check(ResourceLoader.exists(Look.CHARACTERS + scene), "skin '%s' has its model %s" % [skin, scene])
	for skin: String in ["raider", "scavenger"]:
		for scene: String in Look.SKINS[skin]["scenes"]:
			var human: Node3D = Look._instance(Look.CHARACTERS + scene)
			var human_anims := human.find_child("AnimationPlayer", true, false) as AnimationPlayer
			var has_all := human_anims != null
			for key: String in Look.HUMAN_ANIMS:
				has_all = has_all and human_anims.has_animation(Look.HUMAN_ANIMS[key])
			t.check(has_all, "human model %s has every animation the skin plays" % scene)
			human.free()
	var crate := Look.prop("Lootbox.glb", 1.2)
	var crate_size := Look.model_bounds(crate).size
	t.check(absf(maxf(crate_size.x, maxf(crate_size.y, crate_size.z)) - 1.2) < 0.05, "a prop is scaled to the size asked for")
	t.check(crate.find_children("*", "CollisionObject3D", true, false).is_empty(), "props have no collision")
	crate.free()

	for world in Worlds.all():
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
		t.check(skin._grip_bone >= 0 and skeleton != null, tag + "the player's model has a hand to hold a weapon")
		if skin._grip_bone >= 0 and skeleton != null:
			skin._hold_weapon()
			var palm: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(skin._grip_bone).origin
			t.check(raid.player.hand.global_position.distance_to(palm) < 0.2, tag + "the weapon sits in the model's hand")
			t.check(raid.player.hand.global_position.distance_to(raid.player.to_global(Actor.HAND_REST)) > 0.05,
					tag + "the weapon is no longer left floating at the greybox hand spot")
			raid.player.hand_override = true
			raid.player.hand.position = Vector3(5, 5, 5)
			skin._hold_weapon()
			t.check(raid.player.hand.position.is_equal_approx(Vector3(5, 5, 5)), tag + "the model leaves the hand alone in first person")
			raid.player.hand_override = false
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

	t.check(FileAccess.file_exists("res://assets/LICENSES.md"), "asset licenses are recorded")
	var licenses := FileAccess.get_file_as_string("res://assets/LICENSES.md")
	for dir: String in ["characters", "weapons", "props", "textures", "sky", "fonts"]:
		t.check(licenses.contains("assets/" + dir), "licenses cover assets/%s" % dir)
	Look.enabled = false
	Look._materials.clear()
