extends RefCounted
## Checks for the character customizer: appearances, part-built models, the
## hub panel, the profile, and looks travelling through a server.
## Called from test_runner.gd.

const Human := preload("res://core/visual/human.gd")
const CharacterPanel := preload("res://core/ui/character_panel.gd")


static func run(t: Node) -> void:
	print("Character customizer")
	# Appearances are never trusted.
	var plain := Human.sanitize(null)
	t.check(plain["build"] in Human.BUILDS and Human.SLOTS.all(func(slot: String) -> bool:
			return Human.OUTFITS[plain["build"]].has(plain[slot])), "nothing at all becomes a valid default look")
	var junk := Human.sanitize({"build": "zz", "head": 7, "body": "../../etc", "legs": "Witch", "skin": 999,
			"hair": -5, "top": "red", "bottom": 2.0, "extra": "ignored"})
	t.check(junk["build"] == "m" and Human.OUTFITS["m"].has(junk["head"]) and Human.OUTFITS["m"].has(junk["body"])
			and junk["legs"] != "Witch", "unknown builds and parts fall back, and a part cannot come from the other build")
	t.check(junk["skin"] == Human.SKIN_TONES.size() - 1 and junk["hair"] == 0 and junk["top"] == 0
			and junk["bottom"] == 2 and not junk.has("extra"), "colours are clamped and anything extra is dropped")
	var mixed := Human.sanitize({"build": "f", "head": "Punk", "body": "Soldier", "legs": "Worker", "feet": "SciFi",
			"skin": 3, "hair": 5, "top": 6, "bottom": 1})
	t.check(mixed["head"] == "Punk" and mixed["body"] == "Soldier" and mixed["legs"] == "Worker"
			and mixed["feet"] == "SciFi" and mixed["skin"] == 3, "a valid mixed look is kept as chosen")
	t.check(Human.sanitize(JSON.parse_string(JSON.stringify(mixed))) == mixed, "a look survives a trip through a save file")
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var pool := {"f": ["Worker", "Punk"]}
	var in_pool := true
	for i in 20:
		var picked := Human.random(rng, pool)
		in_pool = in_pool and picked["build"] == "f" and Human.SLOTS.all(func(slot: String) -> bool:
				return picked[slot] in pool["f"])
	t.check(in_pool, "a random look stays inside the outfits it is given")
	t.check(Human.for_name("Bot3") == Human.for_name("Bot3"), "someone with no chosen look gets the same one every time")
	t.check(Human.color_for(mixed, "body", "Skin")["color"] == Human.SKIN_TONES[3], "skin takes the chosen tone on every part")
	t.check(Human.color_for(plain, "head", "Hair").is_empty() and Human.color_for(mixed, "head", "Hair_Brown").has("color"),
			"hair keeps its own colour unless one is chosen")
	t.check(Human.color_for(mixed, "body", "Swat")["keep_shading"] and Human.color_for(mixed, "head", "Swat").is_empty()
			and Human.color_for(mixed, "legs", "Eye").is_empty(), "clothing is dyed on the body and legs, not hats or eyes")

	# Every outfit ships all four parts on the shared skeleton.
	var complete := true
	var count := 0
	for build in Human.BUILDS:
		complete = complete and ResourceLoader.exists(Human.rig_path(build))
		for outfit: String in Human.OUTFITS[build]:
			count += 1
			var scene := load(Human.outfit_path(build, outfit)) as PackedScene
			if scene == null:
				complete = false
				continue
			var parts: Node = scene.instantiate()
			for slot in Human.SLOTS:
				var part := parts.find_child(Human.SLOT_NODES[slot], true, false) as MeshInstance3D
				complete = complete and part != null and part.skin != null and String(part.skin.get_bind_name(0)) != ""
			parts.free()
	t.check(complete and count == 20, "all 20 outfits have a head, body, legs and feet bound to bones by name")

	# A look builds into one animated model wearing the chosen parts.
	Look.enabled = true
	var built: Dictionary = Look.character("raider", mixed)
	t.check(not built.is_empty(), "a look builds into a model")
	if not built.is_empty():
		var model: Node3D = built["model"]
		var skeleton := model.find_child("Skeleton3D", true, false) as Skeleton3D
		var worn := model.find_children("*", "MeshInstance3D", true, false)
		t.check(worn.size() == 4 and worn.all(func(part: MeshInstance3D) -> bool:
				return part.get_parent() == skeleton and part.skin != null), "the model wears exactly the four chosen parts")
		var legs_source := (load(Human.outfit_path("f", "Worker")) as PackedScene).instantiate()
		var legs := model.find_child("PartLegs", true, false) as MeshInstance3D
		t.check(legs != null and legs.mesh == (legs_source.find_child("PartLegs", true, false) as MeshInstance3D).mesh,
				"each part comes from the outfit that was picked for it")
		legs_source.free()
		t.check(model.find_child("AnimationPlayer", true, false) != null, "the built model keeps the rig's animations")
		var toned := 0
		for mat: ShaderMaterial in built["materials"]:
			if mat.get_shader_parameter("recolor") == Human.SKIN_TONES[3] and mat.get_shader_parameter("recolor_amount") == 1.0:
				toned += 1
		t.check(toned > 0, "the chosen skin tone reaches the model's materials")
		t.check(model.find_children("*", "CollisionObject3D", true, false).is_empty(), "a built character has no collision")
		model.free()

	# The profile keeps the look, cleaned.
	var was_persist := Profile.persist
	Profile.persist = false
	var before := Profile.appearance
	Profile.set_appearance({"build": "f", "head": "Witch", "skin": 40})
	t.check(Profile.appearance["build"] == "f" and Profile.appearance["head"] == "Witch"
			and Profile.appearance["skin"] == Human.SKIN_TONES.size() - 1, "the profile keeps a cleaned copy of the look")

	# The hub panel.
	var hub := Hub.new()
	t.add_child(hub)
	await t.frames(2)
	var panel: CharacterPanel = hub.character
	t.check(panel != null and panel.appearance == Profile.appearance, "the hub shows the profile's look")
	var heard := []
	hub.look_changed.connect(func(appearance: Dictionary) -> void: heard.append(appearance))
	panel.choose("body", "Punk")
	t.check(heard.size() == 1 and heard[0]["body"] == "Punk" and heard[0]["head"] == "Witch",
			"picking a part changes only that part and tells the game")
	panel.choose("body", "Punk")
	t.check(heard.size() == 1, "picking what is already worn changes nothing")
	panel.choose("build", "m")
	t.check(heard.size() == 2 and heard[1]["build"] == "m" and Human.SLOTS.all(func(slot: String) -> bool:
			return Human.OUTFITS["m"].has(heard[1][slot])) and heard[1]["skin"] == Profile.appearance["skin"],
			"switching build swaps to that build's outfits and keeps the colours")
	t.check(panel.options_for("head").size() == Human.OUTFITS["m"].size()
			and panel.options_for("skin").size() == Human.SKIN_TONES.size(), "the pickers offer every outfit and colour")
	panel.show_customizer()
	await t.frames(3)
	t.check(panel.is_customizing() and panel._pickers.size() == 9 and panel._model != null,
			"the customizer opens with a picker for each choice and a preview model")
	panel.randomize_look()
	t.check(heard.size() == 3 and Human.sanitize(heard[2]) == heard[2], "randomize picks a valid look")
	panel.hide_customizer()
	t.check(not panel.is_customizing(), "done closes the customizer")
	hub.queue_free()
	await t.frames(2)

	# In a raid, the player wears the chosen look and can be given a new one.
	var raid := Raid.new()
	t.add_child(raid)
	raid.start(Worlds.get_world("ashfront"), 31)
	Look.set_appearance(raid.player, mixed)
	await t.frames(4)
	var skin := raid.player.get_node_or_null("Skin")
	var head := skin.find_child("PartHead", true, false) as MeshInstance3D if skin else null
	var punk_head := (load(Human.outfit_path("f", "Punk")) as PackedScene).instantiate()
	t.check(head != null and head.mesh == (punk_head.find_child("PartHead", true, false) as MeshInstance3D).mesh,
			"the player wears the chosen look in a raid")
	punk_head.free()
	var skins := raid.player.get_children().filter(func(child: Node) -> bool: return child.name.begins_with("Skin"))
	t.check(skins.size() == 1 and skin.arm != null and skin.arm.grip_bone >= 0,
			"changing the look leaves one model, which still holds its weapon")
	var unchosen := raid.bots.filter(func(bot: Actor) -> bool: return bot.get_meta("look", "") == "scavenger")
	t.check(not unchosen.is_empty() and unchosen[0].get_node_or_null("Skin") != null
			and unchosen[0].get_node("Skin").find_child("PartHead", true, false) != null,
			"scavengers are built from parts too")
	raid.queue_free()
	await t.frames(2)
	Look.enabled = false
	Look._materials.clear()

	# A headless server only records the look.
	var server_raid := Raid.new()
	t.add_child(server_raid)
	server_raid.start_server(Worlds.get_world("ashfront"), 32)
	var joined := server_raid.add_player([], {}, "Alpha")
	Look.set_appearance(joined, {"build": "f", "head": "Nope", "skin": 2})
	await t.frames(3)
	t.check(joined.get_meta("appearance")["head"] == Human.OUTFITS["f"].keys()[0] and joined.get_meta("appearance")["skin"] == 2
			and not joined.has_node("Skin"), "a headless server records a cleaned look and builds no model")
	server_raid.queue_free()
	await t.frames(2)

	# Through a real server: each player sees how the other looks.
	print("Character customizer: looks through a server")
	var port := 24831
	var server_args: Array[String] = ["--bots", "0", "--squad-spawn"]
	var pid: int = t._start_server(port, server_args)
	var alpha: NetSession = await t._sign_in("Alpha", port)
	t.check(alpha != null, "a client signs in to set its look")
	if alpha != null:
		# Sent raw, to show the server does the checking.
		alpha.send_look({"build": "f", "head": "Punk", "body": "Soldier", "legs": "Bogus", "feet": "SciFi", "skin": 3,
				"hair": 500})
		alpha.deploy()
		await t._wait_until(func() -> bool: return alpha.raid != null and alpha.raid.player != null, 240)
		var bravo: NetSession = await t._join("Bravo", port)
		t.check(bravo != null, "a second client joins")
		if bravo != null and alpha.raid != null:
			await t._wait_until(func() -> bool:
				return bravo.actor_for(alpha.my_actor_id) != null and alpha.actor_for(bravo.my_actor_id) != null, 180)
			var seen: Actor = bravo.actor_for(alpha.my_actor_id)
			var seen_look: Dictionary = seen.get_meta("appearance", {}) if seen != null else {}
			t.check(seen_look.get("build") == "f" and seen_look.get("head") == "Punk" and seen_look.get("body") == "Soldier"
					and seen_look.get("skin") == 3, "another player sees the look that was chosen")
			t.check(Human.OUTFITS["f"].has(seen_look.get("legs", "")) and seen_look.get("hair") == Human.HAIR_COLORS.size() - 1,
					"the server cleans a look before passing it on")
			t.check(alpha.raid.player.get_meta("appearance", {}) == seen_look, "the player's own game shows the same look")
			var other: Actor = alpha.actor_for(bravo.my_actor_id)
			t.check(other != null and not other.has_meta("appearance"), "a player who chose nothing is left to the default")
		await t._leave(bravo)
	await t._leave(alpha)
	OS.kill(pid)
	await t.frames(30)

	Profile.appearance = before
	Profile.persist = was_persist
