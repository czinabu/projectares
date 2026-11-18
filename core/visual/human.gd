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
			part.mesh = shaped(source.mesh, source.skin) if reshape else source.mesh
			# Outfit files bind their meshes to bones by name, and every file
			# names its bones the same, so a part fits any rig of its build.
			part.skin = source.skin
			part.set_meta("slot", slot)
			skeleton.add_child(part)
			part.skeleton = part.get_path_to(skeleton)
		donor.free()
	return rig


## How `character.gdshader` treats a surface: 1 skin, 2 skin the undersuit
## covers (anywhere below the head), 3 eyes, 0 anything else.
static func surface_kind(slot: String, material_name: String) -> int:
	if material_name.begins_with("Skin"):
		return 1 if slot == "head" else 2
	if material_name == "Eye" or material_name == "Eyes":
		return 3
	return 0


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



## Off only to compare against the packs' own meshes (`tests/body_check`).
static var reshape := true
## Reshaped copies of the packs' meshes, one per source mesh.
static var _shape_cache := {}
## Faces meeting at a sharper angle than this keep their edge.
const SMOOTH_ANGLE := 62.0
## The packs' heads are cartoon-large; this brings them toward an adult's
## proportions. The Head bone (and with it the eyes and anything worn on
## it) stays where it is: only the mesh weighted to it shrinks about it.
const HEAD_SCALE := 0.9
## Bones whose skin the undersuit covers with a glove.
const HAND_BONES: Array[String] = ["Wrist", "Thumb", "Index", "Middle", "Ring", "Pinky"]


## `mesh` as the game wears it: normals averaged across faces that meet at
## a shallow angle, so the faceted pack bodies shade as rounded forms while
## a crease (a cuff, a sole, a collar) keeps its edge, and the head drawn
## in to `HEAD_SCALE`. Same vertex count, bones and weights, so it poses
## and costs exactly as the original. Cached per mesh.
static func shaped(mesh: Mesh, skin: Skin = null) -> Mesh:
	var source := mesh as ArrayMesh
	if source == null:
		return mesh
	if _shape_cache.has(source):
		return _shape_cache[source]
	# Where the head pivots, in the mesh's space, and its bone's index.
	var head := -1
	var pivot := Vector3.ZERO
	if skin:
		for b in skin.get_bind_count():
			if skin.get_bind_name(b) == "Head":
				# Mesh bone indices count the skin's binds.
				head = b
				pivot = skin.get_bind_pose(b).affine_inverse().origin
				break
	# The hand's bones, for the undersuit's gloves.
	var hand_binds := {}
	if skin:
		for b in skin.get_bind_count():
			var bone_name := String(skin.get_bind_name(b))
			for prefix: String in HAND_BONES:
				if bone_name.begins_with(prefix):
					hand_binds[b] = true
	var out := ArrayMesh.new()
	out.resource_name = source.resource_name
	var limit := cos(deg_to_rad(SMOOTH_ANGLE))
	for i in source.get_surface_count():
		var arrays := source.surface_get_arrays(i)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		if normals.size() == verts.size() and verts.size() > 0:
			# Gather every vertex sharing a position.
			var groups := {}
			for v in verts.size():
				var at := (verts[v] * 2000.0).round()
				if groups.has(at):
					(groups[at] as Array).append(v)
				else:
					groups[at] = [v]
			var smooth := normals.duplicate()
			for at: Vector3 in groups:
				var members: Array = groups[at]
				if members.size() < 2:
					continue
				for v: int in members:
					var sum := Vector3.ZERO
					for u: int in members:
						if normals[v].dot(normals[u]) >= limit:
							sum += normals[u]
					if sum.length_squared() > 0.000001:
						smooth[v] = sum.normalized()
			arrays[Mesh.ARRAY_NORMAL] = smooth
			arrays[Mesh.ARRAY_TANGENT] = null
			arrays[Mesh.ARRAY_CUSTOM0] = _rest_marks(arrays, hand_binds)
			if head >= 0 and not is_equal_approx(HEAD_SCALE, 1.0):
				arrays[Mesh.ARRAY_VERTEX] = _draw_in_head(arrays, head, pivot)
		var format := source.surface_get_format(i)
		var flags := format & (Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS | Mesh.ARRAY_FLAG_USE_DYNAMIC_UPDATE)
		if arrays[Mesh.ARRAY_CUSTOM0] != null:
			flags |= Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
		out.add_surface_from_arrays(source.surface_get_primitive_type(i), arrays,
			source.surface_get_blend_shape_arrays(i), {}, flags)
		out.surface_set_material(i, source.surface_get_material(i))
		out.surface_set_name(i, source.surface_get_name(i))
	_shape_cache[source] = out
	return out


## Each vertex's place on the body at rest (xyz) and how much it belongs to
## a hand (w), as CUSTOM0 for `character.gdshader`: patterns drawn from the
## rest position stay on the body as it moves, so cloth weave and the
## undersuit's seams never swim.
static func _rest_marks(arrays: Array, hand_binds: Dictionary) -> PackedFloat32Array:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones = arrays[Mesh.ARRAY_BONES]
	var weights = arrays[Mesh.ARRAY_WEIGHTS]
	var per: int = bones.size() / verts.size() if bones != null and weights != null else 0
	var out := PackedFloat32Array()
	out.resize(verts.size() * 4)
	for v in verts.size():
		var hand := 0.0
		for k in per:
			if hand_binds.has(int(bones[v * per + k])):
				hand += float(weights[v * per + k])
		out[v * 4] = verts[v].x
		out[v * 4 + 1] = verts[v].y
		out[v * 4 + 2] = verts[v].z
		out[v * 4 + 3] = clampf(hand, 0.0, 1.0)
	return out


## Vertex positions with whatever is weighted to bone `head` drawn in
## toward `pivot`, by as much as it is weighted there.
static func _draw_in_head(arrays: Array, head: int, pivot: Vector3) -> PackedVector3Array:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones = arrays[Mesh.ARRAY_BONES]
	var weights = arrays[Mesh.ARRAY_WEIGHTS]
	if bones == null or weights == null or verts.is_empty():
		return verts
	var per: int = bones.size() / verts.size()
	for v in verts.size():
		var w := 0.0
		for k in per:
			if int(bones[v * per + k]) == head:
				w += float(weights[v * per + k])
		if w > 0.0:
			verts[v] = verts[v].lerp(pivot + (verts[v] - pivot) * HEAD_SCALE, w)
	return verts
