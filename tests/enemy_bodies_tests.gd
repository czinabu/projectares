extends RefCounted
## Enemy bodies (Caleb's call: no stock robots in every world). Heavies and
## bosses are people in full plate, each world's own; every boss has a
## body of its own; Frostline's Ferals are beasts; robots are left only to
## Frostline's station automata, built in code with the weapon in the arm.
## Ashfront's two armies are told apart by uniform, never by skin tone.
## The plain fighters have looks of their own too: a marksman or a runner
## is not its army's rifleman, and the Dune Sea's raiders are desert nomads.

const Human := preload("res://core/visual/human.gd")
const SkinScript := preload("res://core/visual/actor_skin.gd")
const ROBOT_MODELS: Array[String] = ["George.glb", "Enemy_2Legs_Gun.glb", "Mike.glb", "Enemy_Large_Gun.glb"]


static func run(t: Node) -> void:
	print("Enemy bodies")
	_skins(t)
	_tones(t)
	var holder := Node3D.new()
	t.add_child(holder)
	_ashfront(t, holder)
	_worlds(t, holder)
	_plain(t, holder)
	holder.queue_free()
	await t.frames(1)


static func _skins(t: Node) -> void:
	var stock := []
	for skin: String in Look.SKINS:
		for scene: String in Look.SKINS[skin].get("scenes", []):
			if scene in ROBOT_MODELS or (scene == "Stan.glb" and Look.SKINS[skin].get("chassis", "") != "android"):
				stock.append(skin)
	t.check(stock.is_empty(), "no skin wears a stock robot model (%s)" % ", ".join(stock))
	for skin: String in ["sentinel", "colossus", "core_colossus"]:
		var def: Dictionary = Look.SKINS[skin]
		t.check(def.get("chassis", "") == "android" and def.get("bare", false) and "Stan" in def.get("hide", []),
				"the %s is an android built in code, its weapon in its arm" % skin)
	for skin: String in ["vanguard", "tide_brute", "scrap_brute", "slag_brute", "warlord", "baron", "crown_lord"]:
		var def: Dictionary = Look.SKINS[skin]
		var frame: String = def.get("frame", "")
		t.check(def.has("people") and SkinScript.frame_weight("skin:" + frame) == "heavy"
				and SkinScript.FRAME_STYLES.has(SkinScript.frame_look("skin:" + frame))
				and ArmorPaint.PAINTS.has(def.get("paint", "")),
				"%s is a person in heavy %s plate, painted %s" % [skin, SkinScript.frame_look("skin:" + frame), def.get("paint", "")])
	var regalia := {}
	for skin: String in ["warlord", "baron", "crown_lord"]:
		regalia[Look.SKINS[skin].get("regalia", "")] = true
	t.check(regalia.size() == 3 and not regalia.has(""), "each boss wears regalia of its own (%s)" % ", ".join(regalia.keys()))
	t.check(Look.SKINS["core_colossus"].get("core_chassis", false) and not Look.SKINS["colossus"].get("core_chassis", false),
			"the core colossus is its own machine, not the colossus grown taller")
	t.check(Look.SKINS["feral"].get("creature", "") == "feral", "the Feral Stalker is a beast")
	# A skin's own plates name their look; a bare weight keeps its own.
	t.check(SkinScript.frame_look("skin:heavy:scrap") == "scrap" and SkinScript.frame_look("skin:heavy") == "bulwark"
			and SkinScript.frame_weight("skin:light") == "light", "a skin's plates may name their look")


## A person's skin tone comes from their name alone: the army's outfits
## never change it, so both armies draw from every tone.
static func _tones(t: Node) -> void:
	var legion: Dictionary = Look.SKINS["legionary"]["people"]
	var tide: Dictionary = Look.SKINS["tide"]["people"]
	var same := true
	var seen := {}
	for i in 200:
		var who := "Bot%d" % i
		var a := Human.for_name(who, legion)
		var b := Human.for_name(who, tide)
		same = same and a["skin"] == b["skin"]
		seen[a["skin"]] = true
	t.check(same, "a person's skin tone does not depend on their army")
	t.check(seen.size() == Human.SKIN_TONES.size(), "every skin tone turns up in each army (%d of %d)" % [seen.size(), Human.SKIN_TONES.size()])
	var shader := (load("res://assets/shaders/character.gdshader") as Shader).code
	t.check(shader.contains("bare_skin") and shader.contains("SKIN_BRIGHTNESS"),
			"the faction tint dresses clothes, never a person's skin")


static func _ashfront(t: Node, holder: Node3D) -> void:
	var world := Worlds.get_world("ashfront")
	var uniforms := {}
	var heavies := {}
	var warlords := {}
	for i in 600:
		var bot := Actor.new()
		bot.faction = "legion" if i % 2 == 0 else "tide"
		bot.set_meta("zone", 2)
		holder.add_child(bot)
		var rng := RandomNumberGenerator.new()
		rng.seed = 7000 + i
		world.equip_bot(bot, rng)
		var uniform: Dictionary = bot.get_meta("uniform", {})
		uniforms[bot.faction] = uniform
		if bot.get_meta("kind", "") == "heavy":
			heavies[bot.get_meta("look", "")] = true
		if i < 40:
			world.make_warlord(bot)
			warlords[bot.get_meta("look", "")] = true
		bot.free()
	t.check(uniforms.size() == 2 and not uniforms["legion"].is_empty() and uniforms["legion"] != uniforms["tide"],
			"the Legion and the Tide wear uniforms of their own (%s)" % str(uniforms))
	var dressed: Dictionary = Human.sanitize(Human.for_name("Uniform").merged(uniforms["legion"], true))
	t.check(dressed["top"] == uniforms["legion"]["top"] and dressed["bottom"] == uniforms["legion"]["bottom"],
			"a uniform is a valid appearance")
	t.check(heavies.has("vanguard") and heavies.has("tide_brute") and heavies.size() == 2,
			"Ashfront's heavies are the Legion Vanguard and the Tide Brute in plate (%s)" % ", ".join(heavies.keys()))
	warlords.erase("walker")
	t.check(warlords.keys() == ["warlord"], "an Ashfront warlord has its own body (%s)" % ", ".join(warlords.keys()))


static func _worlds(t: Node, holder: Node3D) -> void:
	for plan: Array in [["dunes", "scrap_brute", "baron"], ["rift", "slag_brute", "crown_lord"]]:
		var world := Worlds.get_world(plan[0])
		var roster: Dictionary = world.get_script().get_script_constant_map()["ROSTER"]
		t.check(roster["brute"]["look"] == plan[1], "%s's brute is a person in plate (%s)" % [plan[0], plan[1]])
		var bot := Actor.new()
		holder.add_child(bot)
		var rng := RandomNumberGenerator.new()
		rng.seed = 3
		world.equip_bot(bot, rng)
		world.make_warlord(bot)
		t.check(bot.get_meta("look", "") == plan[2], "%s's boss has its own body (%s)" % [plan[0], bot.get_meta("look", "")])
		bot.free()
	var frost := Worlds.get_world("frostline")
	var looks := {}
	for faction: String in ["warden", "feral"]:
		var bot := Actor.new()
		bot.faction = faction
		bot.set_meta("zone", 1)
		holder.add_child(bot)
		var rng := RandomNumberGenerator.new()
		rng.seed = 11
		frost.equip_bot(bot, rng)
		looks[faction] = bot.get_meta("look", "")
		bot.free()
	t.check(looks == {"warden": "sentinel", "feral": "feral"}, "Frostline: Wardens are automata, Ferals beasts (%s)" % str(looks))


## No world's fighter wears a player's or a civilian's clothes, and each
## marksman and runner has a touch of its own ("gear").
static func _plain(t: Node, holder: Node3D) -> void:
	var generic := ["raider", "scavenger"]
	var ash: Dictionary = Worlds.get_world("ashfront").get_script().get_script_constant_map()["ARMIES"]
	var gear := {}
	for army: String in ash:
		for kind: String in ash[army]:
			if not ash[army][kind] is Dictionary or not ash[army][kind].has("look"):
				continue
			var look: String = ash[army][kind]["look"]
			t.check(not look in generic, "Ashfront's %s %s has its own look (%s)" % [army, kind, look])
			if kind in ["marksman", "runner"]:
				gear[look] = Look.SKINS[look].get("gear", "")
	t.check(gear == {"legion_marksman": "hood", "tide_runner": "scarf"}, "a marksman wears a hood, a runner a scarf (%s)" % str(gear))
	for id: String in ["dunes", "rift"]:
		var roster: Dictionary = Worlds.get_world(id).get_script().get_script_constant_map()["ROSTER"]
		for kind: String in roster:
			t.check(not roster[kind]["look"] in generic, "the %s's %s has its own look (%s)" % [id, kind, roster[kind]["look"]])
	var dunes: Dictionary = Worlds.get_world("dunes").get_script().get_script_constant_map()["ROSTER"]
	var raider: Dictionary = Look.SKINS[dunes["grunt"]["look"]]
	t.check(raider.get("gear", "") == "nomad" and raider.get("paint", "") == "desert"
			and Look.SKINS[dunes["marksman"]["look"]].get("gear", "") == "duster",
			"the Dune Sea's raiders are desert nomads, its marksmen in dusters")
	var world := Worlds.get_world("ashfront")
	var gun: Gun = null
	for i in 300:
		var bot := Actor.new()
		bot.faction = "legion"
		bot.set_meta("zone", 1)
		holder.add_child(bot)
		var rng := RandomNumberGenerator.new()
		rng.seed = i
		world.equip_bot(bot, rng)
		var marksman: bool = bot.get_meta("kind", "") == "marksman" and not bot.weapons.is_empty()
		if marksman:
			gun = bot.weapons[0] as Gun
			t.check(gun != null and "optic_longscope" in gun.attachments and is_equal_approx(gun.ads_zoom, 1.0),
					"a Legion Marksman's rifle carries a long scope, shown only")
		bot.free()
		if marksman:
			return
	t.check(false, "a Legion Marksman to look at")
