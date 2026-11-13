extends RefCounted
## Checks for the character customizer: appearances, part-built models, the
## hub panel, the profile, and looks travelling through a server.
## Called from test_runner.gd.

const Human := preload("res://core/visual/human.gd")
const CharacterPanel := preload("res://core/ui/character_panel.gd")
const PhoneScript := preload("res://core/phone/phone.gd")
const MirrorScript := preload("res://core/visual/mirror.gd")


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
	# Players start with plain clothes; the rest has to be owned.
	t.check(Human.SLOTS.all(func(slot: String) -> bool: return plain[slot] in Human.STARTER[plain["build"]])
			and Human.player_look(null) == plain, "the default look is starter clothing")
	var locked := Human.player_look(mixed)
	t.check(locked["head"] in Human.STARTER["f"] and locked["body"] in Human.STARTER["f"] and locked["legs"] == "Worker"
			and locked["feet"] in Human.STARTER["f"] and locked["skin"] == 3 and locked["top"] == 6,
			"a player cannot wear outfits they do not own, and keeps the rest of the look")
	var unlocked := Human.player_look(mixed, [Human.outfit_id("f", "Punk"), Human.outfit_id("m", "Swat")])
	t.check(unlocked["head"] == "Punk" and unlocked["body"] in Human.STARTER["f"], "owning an outfit unlocks its parts only")
	t.check(Human.wearable("m").size() == Human.STARTER["m"].size()
			and Human.wearable("m").all(func(o: String) -> bool: return o in Human.STARTER["m"]),
			"with nothing owned only starter clothes are wearable")
	t.check(Human.wearable("m", ["m_King"]).has("King") and not Human.wearable("f", ["m_King"]).has("King")
			and Human.wearable("m", ["m_King"]).size() == Human.STARTER["m"].size() + 1, "an owned outfit is added for its build")
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
	Profile.set_appearance({"build": "f", "head": "Adventurer", "body": "Witch", "skin": 40})
	t.check(Profile.appearance["build"] == "f" and Profile.appearance["head"] == "Adventurer"
			and Profile.appearance["body"] in Human.STARTER["f"]
			and Profile.appearance["skin"] == Human.SKIN_TONES.size() - 1, "the profile keeps a cleaned copy of the look")

	# The hub panel.
	var hub := Hub.new()
	t.add_child(hub)
	await t.frames(2)
	var panel: CharacterPanel = hub.character
	t.check(panel != null and panel.appearance == Profile.appearance, "the hub shows the profile's look")
	var heard := []
	hub.look_changed.connect(func(appearance: Dictionary) -> void: heard.append(appearance))
	panel.choose("body", "Worker")
	t.check(heard.size() == 1 and heard[0]["body"] == "Worker" and heard[0]["head"] == "Adventurer",
			"picking a part changes only that part and tells the game")
	panel.choose("body", "Worker")
	t.check(heard.size() == 1, "picking what is already worn changes nothing")
	panel.choose("body", "Witch")
	t.check(heard.size() == 1, "an outfit that is not owned cannot be picked")
	panel.choose("build", "m")
	t.check(heard.size() == 2 and heard[1]["build"] == "m" and Human.SLOTS.all(func(slot: String) -> bool:
			return Human.OUTFITS["m"].has(heard[1][slot])) and heard[1]["skin"] == Profile.appearance["skin"],
			"switching build swaps to that build's outfits and keeps the colours")
	t.check(panel.options_for("head").size() == Human.STARTER["m"].size()
			and panel.options_for("skin").size() == Human.SKIN_TONES.size(), "the pickers offer starter clothes and every colour")
	panel.owned = [Human.outfit_id("m", "King")]
	t.check(panel.options_for("body").any(func(option: Array) -> bool: return option[0] == "King"),
			"an owned outfit shows up in the pickers")
	# What the phone's mirror scrolls through.
	t.check(panel.pick_keys() == ["build", "head", "body", "legs", "feet", "skin", "hair", "top", "bottom"],
			"the mirror lists the build, each part and each colour")
	var first_head: String = panel.options_for("head")[0][0]
	panel.choose("head", first_head)
	panel.step("head", -1)
	t.check(panel.appearance["head"] == panel.options_for("head")[-1][0] and panel.pick_position("head")[0]
			== panel.options_for("head").size() - 1, "scrolling back from the first option wraps round to the last")
	panel.step("head", 1)
	t.check(panel.appearance["head"] == first_head and panel.pick_label("head") == Human.OUTFITS["m"][first_head],
			"scrolling on wraps back to the first")
	panel.owned = [Human.outfit_id("m", "Punk")]
	panel.choose("body", "Punk")
	t.check(panel.appearance["body"] == "Punk" and panel.pick_source("body") == "From your stash: Punk Outfit",
			"an owned outfit says which stash item it came from")
	t.check(panel.pick_source("head") == "Starter clothes" and panel.pick_source("skin") == "",
			"starter clothes say so, and colours have no source")
	panel.choose("body", Human.STARTER["m"][0])
	panel.owned = []
	panel.show_customizer()
	await t.frames(3)
	t.check(panel.is_customizing() and panel._pickers.size() == 9 and panel._model != null,
			"the customizer opens with a picker for each choice and a preview model")
	var heard_before := heard.size()
	panel.randomize_look()
	t.check(heard.size() == heard_before + 1 and Human.player_look(heard[-1]) == heard[-1], "randomize picks a look from starter clothes")
	panel.hide_customizer()
	t.check(not panel.is_customizing(), "done closes the customizer")
	hub.queue_free()
	await t.frames(2)

	await _run_mirror(t)

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
	t.check(joined.get_meta("appearance")["head"] == Human.STARTER["f"][0] and joined.get_meta("appearance")["skin"] == 2
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
		alpha.send_look({"build": "f", "head": "Adventurer", "body": "Soldier", "legs": "Bogus", "feet": "Worker", "skin": 3,
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
			t.check(seen_look.get("build") == "f" and seen_look.get("head") == "Adventurer" and seen_look.get("feet") == "Worker"
					and seen_look.get("skin") == 3, "another player sees the look that was chosen")
			t.check(seen_look.get("legs", "") in Human.STARTER["f"] and seen_look.get("body", "") in Human.STARTER["f"]
					and seen_look.get("hair") == Human.HAIR_COLORS.size() - 1,
					"the server cleans a look before passing it on")
			t.check(alpha.raid.player.get_meta("appearance", {}) == seen_look, "the player's own game shows the same look")
			var other: Actor = alpha.actor_for(bravo.my_actor_id)
			t.check(other != null and not other.has_meta("appearance"), "a player who chose nothing is left to the default")
			# Changed in front of the mirror, mid-world: everyone sees it at once.
			alpha.send_look({"build": "f", "head": "Witch", "body": "Casual", "legs": "Worker", "feet": "Worker",
					"skin": 1})
			await t._wait_until(func() -> bool:
				return seen != null and is_instance_valid(seen) and seen.get_meta("appearance", {}).get("body") == "Casual", 120)
			var changed: Dictionary = seen.get_meta("appearance", {}) if is_instance_valid(seen) else {}
			t.check(changed.get("body") == "Casual" and changed.get("skin") == 1,
					"a look changed mid-world reaches the other player without redeploying")
			t.check(changed.get("head", "") in Human.STARTER["f"], "the server still strips clothes the player does not own")
			# Each client gets the change in its own packet, so the player's own copy can land a tick later.
			await t._wait_until(func() -> bool:
				return alpha.raid.player.get_meta("appearance", {}) == changed, 60)
			t.check(alpha.raid.player.get_meta("appearance", {}) == changed, "the player's own game shows what the server passed")
		await t._leave(bravo)
	await t._leave(alpha)
	OS.kill(pid)
	await t.frames(30)

	Profile.appearance = before
	Profile.persist = was_persist


## The phone's Mirror app: a mirror stands in front of you, wherever you are,
## and you scroll through the clothes and colours you own.
static func _run_mirror(t: Node) -> void:
	print("Character customizer: the phone's mirror")
	var hub := Hub.new()
	t.add_child(hub)
	var phone: CanvasLayer = PhoneScript.new()
	t.add_child(phone)
	await t.frames(2)
	phone.set_wardrobe(hub.character)
	var ups: Array = []
	phone.mirror_changed.connect(func(up: bool) -> void: ups.append(up))
	phone.open("mirror")
	await t.frames(1)
	t.check(phone.mirror_open() and ups == [true], "the Mirror app asks for a mirror")
	var rows: Array = phone._body.get_children().filter(func(child: Node) -> bool: return child is PanelContainer)
	t.check(rows.size() == 9, "the app has a row for the build, each part and each colour")
	var looks: Array = []
	hub.look_changed.connect(func(appearance: Dictionary) -> void: looks.append(appearance))
	var key := KEY_DOWN
	var down := InputEventKey.new()
	down.keycode = key
	down.pressed = true
	phone._unhandled_input(down)
	t.check(phone.mirror_row == 1 and looks.is_empty(), "down moves to the next choice without changing anything")
	var right := InputEventKey.new()
	right.keycode = KEY_D
	right.pressed = true
	var head_before: String = hub.character.appearance["head"]
	phone._unhandled_input(right)
	await t.frames(1)
	t.check(looks.size() == 1 and looks[0]["head"] != head_before and looks[0]["head"] in Human.wearable(looks[0]["build"]),
			"right scrolls the chosen part to the next outfit the player owns, and tells the game")
	phone.mirror_step("hair", 1)
	await t.frames(1)
	t.check(looks.size() == 2 and phone.mirror_row == 6, "a row's arrows scroll it and select it")
	phone.open_app("news")
	t.check(ups == [true, false], "leaving the app puts the mirror away")
	phone.open_app("mirror")
	phone.close()
	t.check(ups == [true, false, true, false], "putting the phone away puts the mirror away")
	phone.queue_free()
	hub.queue_free()
	await t.frames(2)

	# In the game: the mirror stands in front of the player in a world.
	var main: Node = load("res://scenes/main.tscn").instantiate()
	t.add_child(main)
	await t.frames(2)
	main.start_raid("ashfront")
	await t.frames(5)
	var me: Actor = main.raid.player
	var controller: PlayerController = main.controller
	main.phone.open("mirror")
	await t.frames(3)
	for i in 2:
		await t.get_tree().process_frame
	t.check(main.phone.holder == me and controller.actor == me,
			"the game hands the phone to the player's own body, so the screen goes in its hand")
	var mirror: Node3D = main.mirror
	t.check(mirror != null and mirror.get_parent() == main.raid and main.phone.mirror_up,
			"opening the Mirror app stands a mirror in the world")
	if mirror != null:
		var ahead := -controller.camera.global_basis.z
		ahead.y = 0.0
		var to_mirror := mirror.global_position - me.global_position
		t.check(to_mirror.normalized().dot(ahead.normalized()) > 0.95 and to_mirror.length() > 1.0
				and to_mirror.length() <= mirror.distance + mirror.side_offset and absf(to_mirror.y) < 0.2,
				"it stands on the floor in front of the player")
		var probe := PhysicsRayQueryParameters3D.create(mirror.global_position + Vector3.UP,
				mirror.global_position + Vector3.DOWN, Actor.LAYER_WORLD)
		var ground := me.get_world_3d().direct_space_state.intersect_ray(probe)
		t.check(not ground.is_empty() and absf(ground.position.y - mirror.global_position.y) < 0.02,
				"its feet are on the ground, not floating or sunk")
		t.check(mirror.global_basis.z.dot(-to_mirror.normalized()) > 0.95, "its glass faces the player")
		t.check(mirror.find_children("*", "CollisionObject3D", true, false).is_empty(), "the mirror has no collision")
		t.check(me.body_mesh.visible, "in first person the body stays drawn for the mirror")
		t.check(controller.camera.cull_mask & (1 << (MirrorScript.HEAD_LAYER - 1)) == 0,
				"but the player's own camera leaves the head out")
		t.check(not main.hud.crosshair.visible, "the crosshair is hidden so it does not sit on your face in the mirror")
	var before: Dictionary = me.get_meta("appearance", {}).duplicate()
	main.phone.mirror_step("body", 1)
	await t.frames(2)
	t.check(me.get_meta("appearance", {}).get("body") != before.get("body") and Profile.appearance == me.get_meta("appearance"),
			"scrolling in the mirror dresses the player at once and saves the look")
	main.phone.close()
	await t.frames(3)
	for i in 2:
		await t.get_tree().process_frame
	t.check(main.mirror == null and main.raid.find_children("Mirror", "", true, false).is_empty()
			and main.hud.crosshair.visible,
			"putting the phone away takes the mirror away and brings the crosshair back")

	# Rendered: a reflection camera through the glass, and the body on its layer.
	var was_enabled: bool = Look.enabled
	Look.enabled = true
	main.phone.open("mirror")
	await t.frames(4)
	for i in 2:
		await t.get_tree().process_frame
	mirror = main.mirror
	var reflection: Camera3D = mirror.find_child("Reflection", true, false).get_child(0) if mirror != null else null
	t.check(reflection != null and reflection.projection == Camera3D.PROJECTION_FRUSTUM
			and reflection.cull_mask & (1 << (MirrorScript.MIRROR_LAYER - 1)) == 0,
			"the mirror renders a reflection that leaves the mirror itself out")
	if reflection != null:
		var glass: Node3D = mirror.get_node("Glass")
		var eye := controller.camera.global_position
		var normal := mirror.global_basis.z
		var gap := (eye - glass.global_position).dot(normal)
		t.check(reflection.global_position.distance_to(eye - 2.0 * gap * normal) < 0.05,
				"the reflection looks from the player's eye mirrored through the glass")
	var skin := me.get_node_or_null("Skin")
	var head_seen := false
	if skin != null and reflection != null:
		for node in skin.find_children("*", "MeshInstance3D", true, false):
			if node.get_meta("slot", "") == "head" and (node as MeshInstance3D).layers & reflection.cull_mask != 0:
				head_seen = true
	t.check(reflection != null and head_seen, "the mirror's camera sees the head your own camera leaves out")
	main.phone.close()
	await t.frames(3)
	for i in 2:
		await t.get_tree().process_frame
	skin = me.get_node_or_null("Skin")
	var head_bit := 1 << (MirrorScript.HEAD_LAYER - 1)
	t.check(skin != null and skin.find_children("*", "VisualInstance3D", true, false).all(
			func(node: VisualInstance3D) -> bool: return node.layers == 1 or node.layers == head_bit),
			"afterwards the body is on the normal layer, with only the head left out of your own view")
	Look.enabled = was_enabled
	main.queue_free()
	await t.frames(3)
