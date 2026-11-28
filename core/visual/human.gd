extends RefCounted
## People. Each build is one body (Quaternius' Universal Base Characters,
## made into `body_<build>.glb` by `tools/human_rig`) cut into a head, body,
## legs and feet, everyone in the tactical suit. An "appearance" is a small
## dictionary naming a hairstyle (`STYLES`), facial hair (`FACIAL`), a face
## shape (`FACES`), a suit pattern (`PATTERNS`), an
## outfit per part (the body, legs and feet pick the suit's style,
## `SUIT_STYLES`, and the colours it comes in, `SUITS`) and colours for skin,
## hair, eyes, the suit and its trim. A look saved before the
## hairstyle was its own choice takes the head outfit's hair (`HAIR`). This
## script checks one, makes random ones, and builds the model.
##
## An appearance is only ever cosmetic. `sanitize` is safe to run on a
## headless server on whatever a client sent: it loads no art.

const SuitShape := preload("res://core/visual/suit_shape.gd")
const HeadShape := preload("res://core/visual/head_shape.gd")
const BodyFitData := preload("res://core/visual/body_fit_data.gd")
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
## Iris colours (`character.gdshader` tints the iris only). Index 0 keeps the
## pack's brown.
const EYE_COLORS: Array[Color] = [
	Color.WHITE, Color(0.12, 0.07, 0.04), Color(0.45, 0.33, 0.12), Color(0.22, 0.5, 0.2),
	Color(0.2, 0.42, 0.85), Color(0.5, 0.56, 0.62), Color(0.85, 0.55, 0.12), Color(0.55, 0.25, 0.75),
]
const EYE_NAMES: Array[String] = ["Brown", "Dark brown", "Hazel", "Green", "Blue", "Grey", "Amber", "Violet"]
const CLOTH_COLORS: Array[Color] = [
	Color.WHITE, Color(0.16, 0.17, 0.19), Color(0.55, 0.57, 0.60), Color(0.42, 0.44, 0.30),
	Color(0.55, 0.42, 0.28), Color(0.50, 0.16, 0.14), Color(0.18, 0.30, 0.50), Color(0.75, 0.45, 0.15),
	Color(0.85, 0.85, 0.82),
]
const CLOTH_NAMES: Array[String] = ["As made", "Black", "Grey", "Olive", "Tan", "Rust", "Navy", "Orange", "White"]
const SKIN_NAMES: Array[String] = ["Tone 1", "Tone 2", "Tone 3", "Tone 4", "Tone 5", "Tone 6"]
## Trim colours: the lit cuffs and piping, and the stripes, braid and
## stitching a style draws in it. Index 0 keeps the outfit's own; "Unlit"
## turns the glow off and draws the trim dark.
const TRIM_COLORS: Array[Color] = [
	Color.WHITE, Color(0.35, 0.85, 1.0), Color(1.0, 0.55, 0.15), Color(1.0, 0.8, 0.4), Color(0.55, 1.0, 0.45),
	Color(1.0, 0.25, 0.75), Color(1.0, 0.22, 0.18), Color(0.9, 0.92, 1.0), Color(0.03, 0.03, 0.035),
]
const TRIM_NAMES: Array[String] = ["As made", "Cyan", "Orange", "Gold", "Green", "Pink", "Red", "White", "Unlit"]
## Patterns the suit can be printed in (`character.gdshader`), drawn in
## the suit's own colour: index -> name. 0 is plain.
const PATTERNS: Array[String] = ["Plain", "Woodland", "Digital", "Tiger stripe", "Splinter"]
## Colour and pattern choices: key -> [label, names].
const COLOR_KEYS := {
	"skin": ["Skin", SKIN_NAMES], "hair": ["Hair colour", HAIR_NAMES], "eyes": ["Eyes", EYE_NAMES],
	"top": ["Top colour", CLOTH_NAMES], "bottom": ["Bottom colour", CLOTH_NAMES],
	"trim": ["Trim colour", TRIM_NAMES], "pattern": ["Suit pattern", PATTERNS],
}
## Hairstyles, picked on their own on either body: id -> [name, the hair
## meshes in the body file (`tools/human_rig`)]. Every one is free.
## A mesh named "Hair_Long:bob" is a cut of the pack's mesh (`HeadShape`).
const STYLES := {
	"buzzed": ["Buzz cut", ["Hair_Buzzed"]], "cropped": ["Crop", ["Hair_BuzzedFemale"]],
	"fringe": ["Crop and fringe", ["Hair_Buzzed", "Hair_Buns:fringe"]],
	"parted": ["Side part", ["Hair_SimpleParted"]], "mohawk": ["Mohawk", ["Hair_Buzzed:mohawk"]],
	"bob": ["Bob", ["Hair_Long:bob"]], "long": ["Long", ["Hair_Long"]],
	"swept": ["Long, swept back", ["Hair_Long:swept"]], "buns": ["Buns", ["Hair_Buns"]],
	"knot": ["Top knot", ["Hair_Buns:knot"]], "shaved": ["Shaved", []],
}
## Facial hair, on either body: id -> [name, meshes].
const FACIAL := {
	"none": ["None", []], "beard": ["Beard", ["Hair_Beard"]], "short": ["Short beard", ["Hair_Beard:short"]],
	"goatee": ["Goatee", ["Hair_Beard:goatee"]], "moustache": ["Moustache", ["Hair_Beard:moustache"]],
	"chinstrap": ["Chin strap", ["Hair_Beard:chinstrap"]],
}
## Face shapes, on either body: id -> [name, the parts it moves
## (`HeadShape.FACE_PARTS`)]. Small moves: a face stays the face it is.
const FACES := {
	"standard": ["Standard", {}],
	"broad": ["Broad", {"jaw": 1.12, "cheeks": 1.06, "chin": 0.003}],
	"narrow": ["Narrow", {"jaw": 0.88, "cheeks": 0.94, "length": 1.04}],
	"square": ["Square jaw", {"jaw": 1.16, "chin_down": 0.004, "chin": 0.004}],
	"long": ["Long", {"length": 1.1, "jaw": 0.95, "chin_down": 0.003}],
	"round": ["Round", {"cheeks": 1.1, "jaw": 1.07, "length": 0.94}],
	"brow": ["Heavy brow", {"brow": 0.005, "chin": 0.004, "jaw": 1.04}],
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
	# The hairstyle and facial hair; a look from before they were their own
	# choice keeps the head outfit's hair.
	var legacy := _legacy_hair(build, out["head"])
	var style: Variant = source.get("style")
	out["style"] = style if typeof(style) == TYPE_STRING and STYLES.has(style) else legacy[0]
	var facial: Variant = source.get("facial")
	out["facial"] = facial if typeof(facial) == TYPE_STRING and FACIAL.has(facial) else legacy[1]
	var face: Variant = source.get("face")
	out["face"] = face if typeof(face) == TYPE_STRING and FACES.has(face) else "standard"
	# Armor paints, frame look to paint (`ArmorPaint`); left out when none.
	var paints := ArmorPaint.clean(source.get("paints"))
	if not paints.is_empty():
		out["paints"] = paints
	# The thruster trail (`RigTrail`); left out when none.
	var trail := RigTrail.clean(source.get("trail"))
	if trail != "":
		out["trail"] = trail
	return out


## [style, facial] matching the hair a head outfit used to pick (`HAIR`).
static func _legacy_hair(build: String, head: String) -> Array:
	var meshes: Array = HAIR.get(build, {}).get(head, [])
	var style := "shaved"
	for id: String in STYLES:
		var wanted: Array = STYLES[id][1]
		# Only the pack's own meshes, worn whole, were ever a head's hair.
		if wanted.size() == 1 and not String(wanted[0]).contains(":") and wanted[0] in meshes:
			style = id
	return [style, "beard" if "Hair_Beard" in meshes else "none"]


## The hair meshes a look shows: its hairstyle's and its facial hair's.
static func hair_meshes(appearance: Dictionary) -> Array:
	var out: Array = []
	out.append_array(STYLES.get(appearance.get("style", ""), ["", []])[1])
	out.append_array(FACIAL.get(appearance.get("facial", ""), ["", []])[1])
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
	out["eyes"] = rng.randi() % EYE_COLORS.size()
	out["face"] = FACES.keys()[rng.randi() % FACES.size()]
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


## The hair a head outfit picked before the hairstyle was its own choice
## (`_legacy_hair`): meshes in the body file, a beard with a cut.
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

## What each outfit's suit looks like beyond its colour (Caleb asked for
## real styles, not only a colour): outfit -> [cut, cloth, second colour].
## The cut (`character.gdshader` `suit_style`) lays out panels, seams,
## pockets, stripes and trims; the cloth (`suit_weave`) is the weave and
## sheen; the second colour is a shade of the suit's own (`second_shade`:
## below 0 darker, above 0 lighter), so a style still reads under any dye or
## armor paint. Everything is drawn on the one suit shape (`SuitShape`), so a
## style can never poke through armor and looks the same in either view.
## The boots are their own cut (`BOOT_CUT`) in the outfit's cloth.
const SUIT_STYLES := {
	"Swat": [0, 0, -0.55], "Soldier": [0, 0, -0.55],
	"Spacesuit": [1, 6, 0.45], "SciFi": [1, 6, 0.45],
	"Adventurer": [2, 1, -0.35],
	"Casual_Hoodie": [3, 2, -0.3],
	"Casual_2": [4, 4, 0.55], "Casual": [4, 4, 0.55],
	"Punk": [5, 3, -0.45],
	"Farmer": [6, 7, -0.4],
	"Suit": [7, 8, -0.5],
	"Beach": [8, 9, 0.7],
	"King": [9, 5, -0.45],
	"Worker": [10, 1, -0.45],
	"Medieval": [11, 10, -0.6],
	"Witch": [12, 4, -0.5],
	"Formal": [13, 4, -0.4],
}
const BOOT_CUT := 50


## Builds the model: the build's body (skeleton, animations and the four
## parts), with the look's hairstyle and facial hair showing. Returns null if art is
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
	# The suit hangs as cloth, not painted on the bare body.
	SuitShape.apply(rig, appearance["build"])
	# The hair and facial hair, cut from the pack's, and the face's shape.
	var face: String = appearance.get("face", "standard")
	var hair: Array[String] = HeadShape.dress(skeleton, appearance["build"], hair_meshes(appearance), face,
			FACES.get(face, FACES["standard"])[1])
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


## The iris colour a look's eyes are tinted, or null to keep the pack's.
static func iris_for(appearance: Dictionary) -> Variant:
	var pick: int = appearance.get("eyes", 0)
	return EYE_COLORS[pick] if pick > 0 and pick < EYE_COLORS.size() else null


## The suit a part is drawn in: {"color", "trim", "pattern", "cut",
## "material", "contrast", "second"} for the body, legs and feet ({} for the
## head). The boots are the cloth darkened, in their own cut.
static func suit_for(appearance: Dictionary, slot: String) -> Dictionary:
	if slot == "head" or slot == "":
		return {}
	var outfit: String = appearance.get(slot, "")
	var style: Array = SUITS.get(outfit, SUITS["Swat"])
	var cut: Array = SUIT_STYLES.get(outfit, SUIT_STYLES["Swat"])
	var cloth: Color = style[0]
	var pick: int = appearance.get("top" if slot == "body" else "bottom", 0)
	if pick > 0:
		cloth = CLOTH_COLORS[pick]
	if slot == "feet":
		cloth = cloth.darkened(0.55)
	var trim: Color = style[1]
	var trim_pick: int = appearance.get("trim", 0)
	if trim_pick > 0 and trim_pick < TRIM_COLORS.size():
		trim = TRIM_COLORS[trim_pick]
	var contrast: float = cut[2]
	return {"color": cloth, "trim": trim, "pattern": appearance.get("pattern", 0),
			"cut": BOOT_CUT if slot == "feet" else cut[0], "material": cut[1], "contrast": contrast,
			"second": second_shade(cloth, contrast)}


## A style's second colour from the suit's: `contrast` below 0 darkens it,
## above 0 lightens it, by that much. A very dark suit lightens instead and
## a very light one darkens, so the panels always show.
static func second_shade(cloth: Color, contrast: float) -> Color:
	var lum := cloth.get_luminance()
	if contrast < 0.0 and lum < 0.2:
		return cloth.lightened(-contrast * 0.3)
	if contrast > 0.0 and lum > 0.75:
		return cloth.darkened(contrast * 0.4)
	return cloth.darkened(-contrast) if contrast < 0.0 else cloth.lightened(contrast)


## Where a build's body is at rest, for the suit's styles to sit on
## (`character.gdshader` `suit_trunk`, `suit_arm`, `suit_leg`), from the
## measured bones (`BodyFitData`).
static func body_marks(build: String) -> Dictionary:
	var data: Dictionary = BodyFitData.DATA.get(build, BodyFitData.DATA["m"])
	var bones: Dictionary = data["bones"]
	var arm: Vector3 = bones["UpperArm"]
	var leg: Vector3 = bones["UpperLeg"]
	return {
		"suit_trunk": Vector4(bones["Hips"].y, bones["Chest"].y, bones["Neck"].y, absf(arm.x)),
		"suit_arm": Vector4(arm.y, arm.z, absf(bones["LowerArm"].x), absf(bones["Wrist"].x)),
		"suit_leg": Vector4(absf(leg.x), bones["LowerLeg"].y, bones["Foot"].y, leg.z),
	}
