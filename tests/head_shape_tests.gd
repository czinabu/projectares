extends RefCounted
## Checks for the head's looks: hairstyles and facial hair cut from the
## pack's (`HeadShape._cut`), face shapes (`HeadShape._field`) and the
## suit's patterns.

const Human := preload("res://core/visual/human.gd")
const HeadShape := preload("res://core/visual/head_shape.gd")


static func run(t: Node) -> void:
	print("Head shapes and suit patterns")
	# Every style names meshes the pack has, whole or cut.
	var cuts := ["mohawk", "bob", "swept", "knot", "fringe", "short", "goatee", "moustache", "chinstrap"]
	var named := true
	for table: Dictionary in [Human.STYLES, Human.FACIAL]:
		for id: String in table:
			for spec: String in table[id][1]:
				var bits := spec.split(":")
				named = named and bits[0].begins_with("Hair_") and (bits.size() == 1 or bits[1] in cuts)
	t.check(named and Human.STYLES.size() >= 11 and Human.FACIAL.size() >= 6,
			"eleven hairstyles and six facial hair choices, each made from the pack's own hair")
	# A face and a pattern are kept, and anything else falls back.
	var look := Human.sanitize({"build": "f", "face": "square", "pattern": 2, "style": "knot", "facial": "goatee"})
	t.check(look["face"] == "square" and look["pattern"] == 2 and look["style"] == "knot" and look["facial"] == "goatee",
			"a face shape, a suit pattern and the new hair are kept as chosen")
	var junk := Human.sanitize({"face": "../x", "pattern": 99})
	t.check(junk["face"] == "standard" and junk["pattern"] == Human.PATTERNS.size() - 1,
			"an unknown face is the standard one and the pattern is clamped")
	t.check(Human.sanitize({"build": "m", "head": "Swat"})["style"] == "buzzed",
			"a look from before hairstyles keeps its buzz cut, not a cut made from it")
	t.check(Human.player_look(look)["face"] == "square" and Human.player_look(look)["pattern"] == 2,
			"faces and patterns are free: nothing has to be owned")
	t.check(Human.suit_for(look, "legs")["pattern"] == 2 and Human.suit_for(look, "head").is_empty(),
			"the suit is printed in the chosen pattern")
	t.check(Human.sanitize(JSON.parse_string(JSON.stringify(look))) == Human.sanitize(look),
			"a face and pattern survive a trip through a save file")
	var shader: Shader = load("res://assets/shaders/character.gdshader")
	t.check(shader.code.contains("uniform int suit_pattern") and shader.code.contains("suit_print("),
			"the character shader prints the suit's patterns")

	# Cuts: two pieces, one at the front and one behind.
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	var verts := PackedVector3Array([
		Vector3(0, 1.7, 0.08), Vector3(0.01, 1.7, 0.08), Vector3(0, 1.71, 0.08),
		Vector3(0, 1.7, -0.1), Vector3(0.01, 1.7, -0.1), Vector3(0, 1.71, -0.1),
		Vector3(0.05, 1.55, -0.1), Vector3(0.06, 1.55, -0.1), Vector3(0.05, 1.56, -0.1)])
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 3, 4, 5, 6, 7, 8])
	var swept: Array = HeadShape._cut(arrays, "swept")
	t.check((swept[Mesh.ARRAY_INDEX] as PackedInt32Array).size() == 6
			and not (swept[Mesh.ARRAY_INDEX] as PackedInt32Array).has(0),
			"sweeping long hair back drops the strands at the front whole")
	var bob: Array = HeadShape._cut(arrays, "bob")
	var folded: PackedVector3Array = bob[Mesh.ARRAY_VERTEX]
	t.check(folded[6].y > 1.55 and folded[6].y < 1.64 and folded[0] == verts[0],
			"a bob folds what hangs low up toward the jaw and leaves the rest")
	t.check((HeadShape._cut(arrays, "goatee")[Mesh.ARRAY_INDEX] as PackedInt32Array).size() == 0
			and (verts as PackedVector3Array) == arrays[Mesh.ARRAY_VERTEX], "a cut never changes the pack's own mesh")

	# Face shapes: the jaw moves, the neck's edge and the back of the head stay.
	var frame := {"eyes": Vector3(0, 0.1, 0.08), "seam": PackedVector3Array([Vector3(0, -0.02, 0.03), Vector3(0.05, 0.0, -0.05)])}
	var jaw := Vector3(0.05, 0.03, 0.06)
	var wide := HeadShape._field(jaw, {"jaw": 1.15}, frame)
	t.check(wide.x > 0.004, "a broad jaw widens the jaw")
	t.check(HeadShape._field(jaw, {"jaw": 0.85}, frame).x < -0.004, "a narrow jaw narrows it")
	t.check(HeadShape._field(Vector3(0.05, 0.0, -0.05), {"jaw": 1.2, "length": 1.1}, frame).length() < 0.0001,
			"the edge the body meets never moves")
	t.check(HeadShape._field(Vector3(0.06, 0.1, -0.12), {"jaw": 1.2, "cheeks": 1.2}, frame).length() < 0.0001,
			"the back of the head stays as it is")
	t.check(HeadShape._field(jaw, {}, frame) == Vector3.ZERO, "the standard face moves nothing")
	t.check(Human.FACES.values().all(func(face: Array) -> bool:
			return (face[1] as Dictionary).keys().all(func(part: String) -> bool: return part in HeadShape.FACE_PARTS)),
			"every face shape moves only parts a face has")
