extends RefCounted
## Weapon sounds (`Sfx.shot`, `assets/sounds/weapons/`): every gun has a voice
## of its own that fits what it is, with takes for the open, a roof and far
## off; a shot under a roof is told from one in the open, and far off gives
## way to the far take. The sounds are a view, so only their rules and files
## are checked here.


static func run(t: Node) -> void:
	print("Weapon sounds")
	_check_voices(t)
	_check_files(t)
	_check_far(t)
	await _check_roof(t)
	_check_quiet_headless(t)


## Every firearm names a voice that exists, and no two guns share one: a
## fight can be read by ear.
static func _check_voices(t: Node) -> void:
	var owner := {}
	var all_named := true
	var unique := true
	for id: String in ItemDB.all_ids():
		# Other checks register made-up guns ("test_..."); only real ones count.
		if not ItemDB.has_tag(id, "firearm") or id.begins_with("test_"):
			continue
		var voice := Sfx.gun_voice(str(ItemDB.item_stats(id).get("shot_sound", "shot")))
		if not Sfx.GUN_VOICES.has(voice):
			all_named = false
			print("  %s has no gun voice (%s)" % [id, voice])
		if owner.has(voice):
			unique = false
			print("  %s and %s share %s" % [id, owner[voice], voice])
		owner[voice] = id
	t.check(all_named, "every firearm's shot sound is a gun voice")
	t.check(unique, "no two firearms share a voice")
	t.check(Sfx.gun_voice("shot") in Sfx.GUN_VOICES, "the plain old 'shot' still reaches a voice")


static func _check_files(t: Node) -> void:
	var missing: Array[String] = []
	for voice: String in Sfx.GUN_VOICES:
		for place: String in ["out", "in", "far"]:
			for i in (2 if place == "far" else 3):
				var path := Sfx.WEAPON_DIR + "%s_%s_%d.ogg" % [voice, place, i + 1]
				if not ResourceLoader.exists(path):
					missing.append(path)
	for sound: String in Sfx.WEAPON_ONE_SHOTS:
		if not ResourceLoader.exists(Sfx.WEAPON_DIR + sound + ".ogg"):
			missing.append(sound)
	t.check(missing.is_empty(), "every gun voice has its outdoor, indoor and far takes (%s)" % [missing])
	var takes := Sfx._takes("shot_carbine_out", 3) as AudioStreamRandomizer
	t.check(takes != null and takes.streams_count == 3
			and takes.playback_mode == AudioStreamRandomizer.PLAYBACK_RANDOM_NO_REPEATS,
			"a voice's takes play in turn at random, never the same one twice running")


static func _check_far(t: Node) -> void:
	t.check(Sfx.far_share(5.0) == 0.0 and Sfx.far_share(Sfx.FAR_FROM) == 0.0,
			"close by, only the full shot is heard")
	t.check(Sfx.far_share(Sfx.FAR_ONLY + 50.0) == 1.0, "far off, only the far take")
	var mid := Sfx.far_share((Sfx.FAR_FROM + Sfx.FAR_ONLY) * 0.5)
	t.check(mid > 0.3 and mid < 0.7, "and in between the two blend (%.2f)" % mid)


## A shot under a slab is indoors; beside it, in the open, it is not.
static func _check_roof(t: Node) -> void:
	var holder := Node3D.new()
	t.add_child(holder)
	var body := StaticBody3D.new()
	body.collision_layer = Actor.LAYER_WORLD
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(10.0, 0.5, 10.0)
	shape.shape = box
	body.add_child(shape)
	holder.add_child(body)
	body.global_position = Vector3(0.0, 1004.0, 0.0)
	await t.frames(3)
	var world := holder.get_world_3d()
	t.check(Sfx.roof_over(world, Vector3(0.0, 1000.0, 0.0)), "a shot under a roof is an indoor shot")
	t.check(not Sfx.roof_over(world, Vector3(30.0, 1000.0, 0.0)), "the same shot in the open is not")
	t.check(not Sfx.roof_over(world, Vector3(0.0, 1006.0, 0.0)), "nor one fired standing on the roof")
	holder.queue_free()
	await t.frames(1)


## Headless (a server, the tests) every sound call is a quiet no-op.
static func _check_quiet_headless(t: Node) -> void:
	Sfx.shot("shot_carbine", Vector3.ZERO, null, false)
	Sfx.shot("no_such_voice", Vector3.ZERO, null, true)
	t.check(not Sfx.indoors(null, Vector3.ZERO), "nothing is looked up for a sound on a server")
