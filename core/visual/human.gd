extends RefCounted
## People, built from parts. Every outfit in the human packs is split into a
## head, body, legs and feet on one shared skeleton, so any head can go with
## any body. An "appearance" is a small dictionary naming the parts and
## colours; this script checks one, makes random ones, and builds the model.
##
## An appearance is only ever cosmetic. `sanitize` is safe to run on a
## headless server on whatever a client sent: it loads no art.

const DIR := "res://assets/characters/humans/"
const SLOTS: Array[String] = ["head", "body", "legs", "feet"]
const SLOT_NAMES := {"head": "Head", "body": "Torso", "legs": "Legs", "feet": "Shoes"}
## The mesh node each slot is stored under in an outfit file.
const SLOT_NODES := {"head": "PartHead", "body": "PartBody", "legs": "PartLegs", "feet": "PartFeet"}
const BUILDS: Array[String] = ["m", "f"]
const BUILD_NAMES := {"m": "Build A", "f": "Build B"}
## Outfit file name (after the build prefix) -> name shown in the customizer.
const OUTFITS := {
	"m": {
		"Swat": "Trooper", "Spacesuit": "Void suit", "Adventurer": "Scout", "Casual_Hoodie": "Hoodie",
		"Casual_2": "Street", "Punk": "Punk", "Farmer": "Homesteader", "Suit": "Suit", "Beach": "Drifter",
		"King": "Warlord",
	},
	"f": {
		"Soldier": "Trooper", "SciFi": "Void suit", "Adventurer": "Scout", "Worker": "Rigger",
		"Casual": "Street", "Punk": "Punk", "Medieval": "Sellsword", "Suit": "Suit", "Formal": "Envoy",
		"Witch": "Mystic",
	},
}
## The plain clothes everyone can wear from the start. Every other outfit has
## to be owned (bought or earned) before a player may wear any part of it.
const STARTER := {
	"m": ["Casual_2", "Casual_Hoodie", "Farmer", "Beach"],
	"f": ["Casual", "Worker", "Adventurer"],
}
const SKIN_TONES: Array[Color] = [
	Color(0.96, 0.80, 0.69), Color(0.89, 0.69, 0.55), Color(0.78, 0.57, 0.42), Color(0.62, 0.43, 0.30),
	Color(0.45, 0.30, 0.21), Color(0.30, 0.20, 0.14),
]
## Index 0 keeps the colours the outfit came with.
const HAIR_COLORS: Array[Color] = [
	Color.WHITE, Color(0.09, 0.07, 0.06), Color(0.30, 0.19, 0.11), Color(0.55, 0.36, 0.18),
	Color(0.85, 0.70, 0.40), Color(0.60, 0.20, 0.12), Color(0.75, 0.75, 0.78), Color(0.25, 0.45, 0.75),
]
const HAIR_NAMES: Array[String] = ["As made", "Black", "Brown", "Chestnut", "Blond", "Red", "Grey", "Blue"]
const CLOTH_COLORS: Array[Color] = [
	Color.WHITE, Color(0.16, 0.17, 0.19), Color(0.55, 0.57, 0.60), Color(0.42, 0.44, 0.30),
	Color(0.55, 0.42, 0.28), Color(0.50, 0.16, 0.14), Color(0.18, 0.30, 0.50), Color(0.75, 0.45, 0.15),
	Color(0.85, 0.85, 0.82),
]
const CLOTH_NAMES: Array[String] = ["As made", "Black", "Grey", "Olive", "Tan", "Rust", "Navy", "Orange", "White"]
const SKIN_NAMES: Array[String] = ["Tone 1", "Tone 2", "Tone 3", "Tone 4", "Tone 5", "Tone 6"]
## Colour choices: key -> [label, names].
const COLOR_KEYS := {
	"skin": ["Skin", SKIN_NAMES], "hair": ["Hair", HAIR_NAMES],
	"top": ["Top colour", CLOTH_NAMES], "bottom": ["Bottom colour", CLOTH_NAMES],
}


## A valid appearance from anything: unknown parts and out-of-range colours
## fall back to defaults. Never trusts its input.
static func sanitize(raw: Variant) -> Dictionary:
	var source: Dictionary = raw if typeof(raw) == TYPE_DICTIONARY else {}
	var build: String = source.get("build", "") if typeof(source.get("build")) == TYPE_STRING else ""
	if build not in BUILDS:
		build = BUILDS[0]
	var outfits: Dictionary = OUTFITS[build]
	var out := {"build": build}
	for slot in SLOTS:
		var part: Variant = source.get(slot)
		out[slot] = part if typeof(part) == TYPE_STRING and outfits.has(part) else STARTER[build][0]
	for key: String in COLOR_KEYS:
		var names: Array = COLOR_KEYS[key][1]
		var index: Variant = source.get(key)
		# JSON hands numbers back as floats.
		out[key] = clampi(int(index), 0, names.size() - 1) if typeof(index) in [TYPE_INT, TYPE_FLOAT] else 0
	return out


## The id an outfit is owned under: the build and the outfit, e.g. "m_Punk".
static func outfit_id(build: String, outfit: String) -> String:
	return "%s_%s" % [build, outfit]


## The outfits of a build a player may wear: the starter clothes plus any in
## `owned` (outfit ids), in the order the customizer lists them.
static func wearable(build: String, owned: Array = []) -> Array[String]:
	var out: Array[String] = []
	for outfit: String in OUTFITS[build]:
		if outfit in STARTER[build] or outfit_id(build, outfit) in owned:
			out.append(outfit)
	return out


## A valid appearance a player is allowed to wear. Like `sanitize`, but any
## part from an outfit that is neither starter clothing nor in `owned` falls
## back to starter clothing. Bots and other non-players use `sanitize`.
static func player_look(raw: Variant, owned: Array = []) -> Dictionary:
	var out := sanitize(raw)
	var allowed := wearable(out["build"], owned)
	for slot in SLOTS:
		if out[slot] not in allowed:
			out[slot] = allowed[0]
	return out


## A random appearance. `pool` limits the outfits, per build, e.g.
## {"m": ["Punk", "Farmer"], "f": ["Worker"]}; a build left out is not used.
static func random(rng: RandomNumberGenerator, pool: Dictionary = {}) -> Dictionary:
	var builds: Array = BUILDS.filter(func(b: String) -> bool: return pool.is_empty() or pool.has(b))
	var build: String = builds[rng.randi() % builds.size()]
	var outfits: Array = pool[build] if pool.has(build) else OUTFITS[build].keys()
	var out := {"build": build}
	for slot in SLOTS:
		out[slot] = outfits[rng.randi() % outfits.size()]
	out["skin"] = rng.randi() % SKIN_TONES.size()
	out["hair"] = rng.randi() % HAIR_COLORS.size()
	out["top"] = 0
	out["bottom"] = 0
	return sanitize(out)


## The appearance for someone who has not chosen one, steady for a given name.
static func for_name(actor_name: String, pool: Dictionary = {}) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(actor_name)
	return random(rng, pool)


static func rig_path(build: String) -> String:
	return DIR + "rig_%s.glb" % build


static func outfit_path(build: String, outfit: String) -> String:
	return DIR + "%s_%s.glb" % [build, outfit]


## Builds the model: the build's rig (skeleton and animations) wearing the
## chosen parts. Returns null if art is missing. Colours are applied later by
## `color_for`, when the caller makes its materials.
static func build(look: Node, appearance: Dictionary) -> Node3D:
	var rig: Node3D = look._instance(rig_path(appearance["build"]))
	if rig == null:
		return null
	var skeleton := rig.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		rig.free()
		return null
	# The rig file is a whole character; only its bones and animations are wanted.
	for node in rig.find_children("*", "MeshInstance3D", true, false):
		node.get_parent().remove_child(node)
		node.free()
	for slot in SLOTS:
		var donor: Node3D = look._instance(outfit_path(appearance["build"], appearance[slot]))
		if donor == null:
			continue
		var source := donor.find_child(SLOT_NODES[slot], true, false) as MeshInstance3D
		if source:
			var part := MeshInstance3D.new()
			part.name = SLOT_NODES[slot]
			part.mesh = source.mesh
			# Outfit files bind their meshes to bones by name, and every file
			# names its bones the same, so a part fits any rig of its build.
			part.skin = source.skin
			part.set_meta("slot", slot)
			skeleton.add_child(part)
			part.skeleton = part.get_path_to(skeleton)
		donor.free()
	return rig


## What a surface should be coloured, given the part it is on and the name of
## its material in the pack. Returns {} to leave the pack's colour alone, or
## {"color": Color, "keep_shading": bool}. With `keep_shading` the chosen
## colour replaces the hue but light and dark panels stay distinct.
static func color_for(appearance: Dictionary, slot: String, material_name: String) -> Dictionary:
	if material_name.begins_with("Skin"):
		var tone := SKIN_TONES[appearance["skin"]]
		return {"color": tone * 0.82 if material_name != "Skin" else tone, "keep_shading": false}
	if material_name.begins_with("Eye") and material_name != "Eyebrows":
		return {}
	if slot == "head":
		if (material_name.begins_with("Hair") or material_name == "Eyebrows") and appearance["hair"] > 0:
			return {"color": HAIR_COLORS[appearance["hair"]], "keep_shading": false}
		return {}
	var key := "top" if slot == "body" else "bottom"
	if appearance[key] > 0:
		return {"color": CLOTH_COLORS[appearance[key]], "keep_shading": true}
	return {}

