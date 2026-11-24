extends RefCounted
## People. Each build is one body (Quaternius' Universal Base Characters,
## made into `body_<build>.glb` by `tools/human_rig`) cut into a head, body,
## legs and feet, everyone in the tactical suit. An "appearance" is a small
## dictionary naming an outfit per part and colours: the head's outfit picks
## the hair (`HAIR`), the others the suit's colours (`SUITS`). This script
## checks one, makes random ones, and builds the model.
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
	# Armor paints, frame look to paint (`ArmorPaint`); left out when none.
	var paints := ArmorPaint.clean(source.get("paints"))
	if not paints.is_empty():
		out["paints"] = paints
	# The thruster trail (`RigTrail`); left out when none.
	var trail := RigTrail.clean(source.get("trail"))
	if trail != "":
		out["trail"] = trail
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
## back to starter clothing, an armor paint not in `owned` comes off, and so does a thruster trail. Bots and other non-players use `sanitize`.
static func player_look(raw: Variant, owned: Array = []) -> Dictionary:
	var out := sanitize(raw)
	var allowed := wearable(out["build"], owned)
	for slot in SLOTS:
		if out[slot] not in allowed:
			out[slot] = allowed[0]
	# Only the armor paints owned ("paint:<id>" in `owned`).
	if out.has("paints"):
		var paints := ArmorPaint.clean(out["paints"], owned)
		if paints.is_empty():
			out.erase("paints")
		else:
			out["paints"] = paints
	# And only a thruster trail owned ("trail:<id>" in `owned`).
	if out.has("trail") and RigTrail.clean(out["trail"], owned) == "":
		out.erase("trail")
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
	return DIR + "body_%s.glb" % build


## The hairstyles a head outfit wears: meshes in the body file
## (`tools/human_rig`), shown together (a beard goes with a cut).
const HAIR := {
	"m": {
		"Swat": ["Hair_Buzzed"], "Spacesuit": ["Hair_Buzzed"], "Adventurer": ["Hair_SimpleParted"],
		"Casual_Hoodie": ["Hair_SimpleParted"], "Casual_2": ["Hair_Long"], "Punk": ["Hair_Buns"],
		"Farmer": ["Hair_Buzzed", "Hair_Beard"], "Suit": ["Hair_SimpleParted"], "Beach": ["Hair_Long"],
		"King": ["Hair_Long", "Hair_Beard"],
	},
	"f": {
		"Soldier": ["Hair_Buns"], "SciFi": ["Hair_BuzzedFemale"], "Adventurer": ["Hair_Long"], "Worker": ["Hair_Buns"],
		"Casual": ["Hair_Long"], "Punk": ["Hair_BuzzedFemale"], "Medieval": ["Hair_Long"], "Suit": ["Hair_Buns"],
		"Formal": ["Hair_SimpleParted"], "Witch": ["Hair_Long"],
	},
}
## The hair colour "As made" stands for: the pack's hair is drawn in grey
## to be tinted.
const NATURAL_HAIR := Color(0.2, 0.13, 0.08)
## Everyone wears the tactical suit (Caleb's call when the bodies moved to
## the Universal Base Characters): an outfit is its suit's colour and the
## trim lit at the cuffs, the boots a darker shade. A top or bottom colour
## picked in the customizer replaces the cloth.
const SUITS := {
	"Swat": [Color(0.12, 0.13, 0.15), Color(0.35, 0.85, 1.0)],
	"Soldier": [Color(0.12, 0.13, 0.15), Color(0.35, 0.85, 1.0)],
	"Spacesuit": [Color(0.72, 0.73, 0.75), Color(1.0, 0.55, 0.15)],
	"SciFi": [Color(0.72, 0.73, 0.75), Color(1.0, 0.55, 0.15)],
	"Adventurer": [Color(0.25, 0.26, 0.17), Color(1.0, 0.75, 0.3)],
	"Casual_Hoodie": [Color(0.18, 0.18, 0.2), Color(0.3, 1.0, 0.8)],
	"Casual_2": [Color(0.15, 0.19, 0.29), Color(0.85, 0.9, 1.0)],
	"Casual": [Color(0.15, 0.19, 0.29), Color(0.85, 0.9, 1.0)],
	"Punk": [Color(0.06, 0.06, 0.07), Color(1.0, 0.25, 0.75)],
	"Farmer": [Color(0.4, 0.31, 0.2), Color(1.0, 0.7, 0.3)],
	"Suit": [Color(0.07, 0.09, 0.15), Color(1.0, 0.8, 0.4)],
	"Beach": [Color(0.52, 0.45, 0.33), Color(0.35, 0.9, 1.0)],
	"King": [Color(0.3, 0.07, 0.07), Color(1.0, 0.78, 0.3)],
	"Worker": [Color(0.58, 0.3, 0.09), Color(1.0, 0.9, 0.3)],
	"Medieval": [Color(0.29, 0.19, 0.11), Color(1.0, 0.6, 0.25)],
	"Formal": [Color(0.78, 0.78, 0.8), Color(1.0, 0.8, 0.4)],
	"Witch": [Color(0.19, 0.09, 0.24), Color(0.55, 1.0, 0.45)],
}


## Builds the model: the build's body (skeleton, animations and the four
## parts), with the head outfit's hair showing. Returns null if art is
## missing. Colours are applied later by `color_for` and `suit_for`, when
## the caller makes its materials.
static func build(look: Node, appearance: Dictionary) -> Node3D:
	var rig: Node3D = look._instance(rig_path(appearance["build"]))
	if rig == null:
		return null
	var skeleton := rig.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		rig.free()
		return null
	var hair: Array = HAIR.get(appearance["build"], {}).get(appearance["head"], [])
	for node in skeleton.get_children():
		var part := node as MeshInstance3D
		if part == null:
			continue
		var slot := ""
		for key: String in SLOT_NODES:
			if SLOT_NODES[key] == part.name:
				slot = key
		if slot == "" and String(part.name) in hair:
			slot = "head"
		if slot == "":
			skeleton.remove_child(part)
			part.free()
			continue
		part.set_meta("slot", slot)
	return rig


## Whether a pack material is skin: the body's own material, by its name.
static func is_skin(material_name: String) -> bool:
	return material_name.begins_with("Skin") or (material_name.begins_with("MI_")
			and not material_name.begins_with("MI_Hair") and not material_name.begins_with("MI_Eye"))


## How `character.gdshader` treats a surface: 1 skin, 2 skin the suit
## covers (anywhere below the head), 3 eyes, 0 anything else.
static func surface_kind(slot: String, material_name: String) -> int:
	if is_skin(material_name):
		return 1 if slot == "head" else 2
	if material_name.begins_with("Eye") or material_name.begins_with("MI_Eye"):
		return 3
	return 0


## What a surface should be coloured, given the part it is on and the name of
## its material in the pack. Returns {} to leave the pack's colour alone, or
## {"color": Color, "keep_shading": bool}. With `keep_shading` the chosen
## colour replaces the hue but the texture's light and dark stay.
static func color_for(appearance: Dictionary, slot: String, material_name: String) -> Dictionary:
	if is_skin(material_name):
		return {"color": SKIN_TONES[appearance["skin"]], "keep_shading": true}
	if material_name.begins_with("MI_Hair") or material_name.begins_with("Hair") or material_name == "Eyebrows":
		var hair: int = appearance["hair"]
		return {"color": HAIR_COLORS[hair] if hair > 0 else NATURAL_HAIR, "keep_shading": true}
	return {}


## The suit a part is drawn in: {"color", "trim"} for the body, legs and
## feet ({} for the head). The boots are the cloth darkened.
static func suit_for(appearance: Dictionary, slot: String) -> Dictionary:
	if slot == "head" or slot == "":
		return {}
	var style: Array = SUITS.get(appearance.get(slot, ""), SUITS["Swat"])
	var cloth: Color = style[0]
	var pick: int = appearance.get("top" if slot == "body" else "bottom", 0)
	if pick > 0:
		cloth = CLOTH_COLORS[pick]
	if slot == "feet":
		cloth = cloth.darkened(0.55)
	return {"color": cloth, "trim": style[1]}


