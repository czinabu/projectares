extends Node3D
## The fortress line on Ashfront's rim (DESIGN.md "The battle around you"):
## a ruined wall of armour plate with towers along its length, standing on
## the crest just past the map's edge, so the field reads as one sector of a
## bigger front instead of a quarry. Where a battle shelf rises behind it
## (the map's `SHELVES`) the wall is broken down to low stubs and gaps, so
## the far war shows through. View only and never in a server: the map adds
## it only where `Look` is on, and it stands past the walls nobody can cross,
## so it needs no collision and is never seen up close.
##
## Built once from a handful of Modular Sci-Fi Megakit pieces (Quaternius,
## CC0), scaled up to fortress size and merged into one mesh a side with one
## surface a material, so the whole ring costs at most sixteen draw calls and
## nothing a frame.

## Megakit pieces, in `assets/props/megakit`.
const DIR := "res://assets/props/megakit/"
const WALLS := ["WallBand_Straight", "WallPipe_Straight", "WallWideBand_Straight"]
const BROKEN := "WallBand_Straight_Broken"
const STUB := "ShortWall_DarkMetal2_Straight"
const CREST := "TopCables_Straight"
const TOWERS := ["Column_Large_Straight", "Column_Large2", "Column_Large3"]
const BUTTRESS := "Column_Pipes"
## How far out from the middle the line runs (m): on the rim's crest, past
## the walls at the map's edge (3 m past them) and short of the crest's
## back, where the far land drops away out of sight.
const LINE := 317.0
## A wall piece is 4 m long and 3 m tall; scaled this much it is a 20 m
## length of 15 m wall.
const SCALE := 5.0
const SEGMENT := 4.0 * SCALE
## How much bigger a tower is than the kit's 10 m column.
const TOWER_SCALE := 3.6
## How far into the ground every piece is sunk, so no slope shows under it.
const SINK := 2.5
## Where the wall is kept low in front of a shelf, past its ends (m).
const SHELF_MARGIN := 16.0
## Which surfaces get which material, by the kit's material names. Anything
## else (decals, collision shapes) is left out.
const PLATE := ["MI_Trim_01", "MI_Trim_02", "MI_PaddedWall"]
const GLOW := ["MI_Trim_03_Cables", "M_Glass"]
const DARK := ["MI_Trim_03", "M_Black"]

## Set by the map: the shelves (see the map's `SHELVES`) and the ground out
## there (`ground_at(x, z)`).
var shelves: Array = []
var ground_at := Callable()

## Every piece laid: { "file", "at" (its foot), "side" } (for checks).
var pieces: Array[Dictionary] = []
## Each surface's arrays, per side: side -> { key -> [verts, normals, indices] }.
var _sides := {}
## Each model's drawable surfaces, read once: file -> [[mesh, surface, key, xform], ...].
static var _parts := {}


func _ready() -> void:
	name = "RimFort"
	if Look.enabled:
		build()


## Lays the line along all four sides and merges each side into one mesh.
func build() -> void:
	if not ground_at.is_valid():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 7151
	for out: Vector2 in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, -1), Vector2(0, 1)]:
		_lay_side(out, rng)
	var materials := {
		"plate": Look.surface("metal", {"tint": Color(0.72, 0.66, 0.6), "grime": 1.0, "scale": 0.05}),
		"dark": Look.surface("metal", {"tint": Color(0.36, 0.33, 0.31), "grime": 1.0, "scale": 0.05}),
		"glow": Look.trim("orange"),
		"beacon": Look.trim("beacon"),
	}
	for side: String in _sides:
		var mesh := ArrayMesh.new()
		var lo := Vector3.INF
		var hi := -Vector3.INF
		for key: String in ["plate", "dark", "glow", "beacon"]:
			if not _sides[side].has(key):
				continue
			var parts: Array = _sides[side][key]
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = parts[0]
			arrays[Mesh.ARRAY_NORMAL] = parts[1]
			arrays[Mesh.ARRAY_INDEX] = parts[2]
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			mesh.surface_set_material(mesh.get_surface_count() - 1, materials[key])
		var node := MeshInstance3D.new()
		node.name = "Side_" + side
		node.mesh = mesh
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
	_sides.clear()


## One side: wall lengths along it, a tower every few, and in front of a
## shelf only stubs and gaps.
func _lay_side(out: Vector2, rng: RandomNumberGenerator) -> void:
	var side := "%d_%d" % [int(out.x), int(out.y)]
	var along := Vector2(-out.y, out.x)
	var count := int(LINE * 2.0 / SEGMENT)
	var span := _shelf_span(out)
	for i in count:
		var l := -LINE + SEGMENT * (float(i) + 0.5)
		var low := l > span.x - SHELF_MARGIN and l < span.y + SHELF_MARGIN
		var spot := out * LINE + along * l
		var roll := rng.randf()
		if low:
			if roll < 0.4:
				pass
			elif roll < 0.8:
				_wall(side, STUB, spot, out, along, rng.randf_range(-0.25, 0.2))
			else:
				_wall(side, BROKEN, spot, out, along, rng.randf_range(-0.1, 0.1))
		else:
			if roll < 0.07:
				pass
			elif roll < 0.25:
				_wall(side, BROKEN, spot, out, along, 0.0)
			else:
				var file: String = WALLS[rng.randi() % WALLS.size()]
				var foot := _wall(side, file, spot, out, along, 0.0)
				if rng.randf() < 0.35:
					_wall(side, CREST, spot, out, along, 0.0, foot.y)
		# Between lengths: a tower now and then, else a buttress.
		if i == 0 or low:
			continue
		var joint := out * LINE + along * (l - SEGMENT * 0.5)
		if i % 4 == 0:
			_tower(side, joint, out, rng)
		elif rng.randf() < 0.5:
			_column(side, BUTTRESS, joint, SCALE * 0.6, 0.0)
	# A tower on the corner this side leads into.
	_tower(side, out * LINE + along * LINE, out, rng)


## The lateral span of the shelf behind this side, or an empty one.
func _shelf_span(out: Vector2) -> Vector2:
	for shelf: Dictionary in shelves:
		if (shelf["out"] as Vector2).is_equal_approx(out):
			return shelf["lateral"]
	return Vector2(INF, -INF)


## A length of wall centred on `spot`, its face to the field, leaned back
## by `lean` (radians) when broken. Returns its foot.
func _wall(side: String, file: String, spot: Vector2, out: Vector2, along: Vector2, lean: float, base := INF) -> Vector3:
	var half := along * SEGMENT * 0.5
	var y := base
	if not is_finite(base):
		y = minf(_ground(spot), minf(_ground(spot - half), _ground(spot + half))) - SINK
	# The kit's wall stands at x = -2.1 in its cell, facing +x and running
	# along z; turned so +x faces the field and centred on the line.
	var basis := Basis(Vector3(-out.x, 0, -out.y), Vector3.UP, Vector3(-along.x, 0, -along.y))
	basis = basis * Basis(Vector3(0, 0, 1), lean)
	var at := Vector3(spot.x, y, spot.y)
	# A crest piece starts 3 m up in its cell; dropped onto the wall's top.
	var lift := -3.0 if is_finite(base) else 0.0
	var xform := Transform3D(basis.scaled_local(Vector3.ONE * SCALE), at) * Transform3D(Basis.IDENTITY, Vector3(2.1, lift, 0))
	_add(side, file, xform, at)
	return Vector3(spot.x, y + 3.0 * SCALE, spot.y)


## A tower: one of the kit's big columns, scaled up, with a red lamp on top.
## The columns are long one way (their z); that way runs along the wall, so
## none reaches in over the rim's slope.
func _tower(side: String, spot: Vector2, out: Vector2, rng: RandomNumberGenerator) -> void:
	var file: String = TOWERS[rng.randi() % TOWERS.size()]
	var yaw := (0.0 if out.y == 0.0 else PI * 0.5) + float(rng.randi() % 2) * PI
	var top := _column(side, file, spot, TOWER_SCALE, yaw)
	_beacon(side, top + Vector3(0, 0.8, 0))


## A standing piece at `spot`, its foot sunk into the ground. Returns its top.
func _column(side: String, file: String, spot: Vector2, scale: float, yaw: float) -> Vector3:
	var y := _ground(spot) - SINK
	var at := Vector3(spot.x, y, spot.y)
	var xform := Transform3D(Basis(Vector3.UP, yaw).scaled_local(Vector3.ONE * scale), at)
	_add(side, file, xform, at)
	return at + Vector3(0, 10.0 * scale if TOWERS.has(file) else 0.0, 0)


## A red warning lamp: a small box on the "beacon" trim.
func _beacon(side: String, at: Vector3) -> void:
	var box := BoxMesh.new()
	box.size = Vector3(1.6, 1.6, 1.6)
	_append(side, "beacon", box, 0, Transform3D(Basis.IDENTITY, at))


func _ground(spot: Vector2) -> float:
	return float(ground_at.call(spot.x, spot.y))


## Adds every drawable surface of a kit model at `xform` to its side.
func _add(side: String, file: String, xform: Transform3D, at: Vector3) -> void:
	pieces.append({"file": file, "at": at, "side": side})
	for part: Array in _model_parts(file):
		_append(side, part[2], part[0], part[1], xform * (part[3] as Transform3D))


func _append(side: String, key: String, mesh: Mesh, surface: int, xform: Transform3D) -> void:
	if not _sides.has(side):
		_sides[side] = {}
	if not _sides[side].has(key):
		_sides[side][key] = [PackedVector3Array(), PackedVector3Array(), PackedInt32Array()]
	var into: Array = _sides[side][key]
	var arrays := mesh.surface_get_arrays(surface)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var start: int = (into[0] as PackedVector3Array).size()
	var turn := xform.basis.inverse().transposed()
	var v_out: PackedVector3Array = into[0]
	var n_out: PackedVector3Array = into[1]
	var i_out: PackedInt32Array = into[2]
	for k in verts.size():
		v_out.append(xform * verts[k])
		n_out.append((turn * normals[k]).normalized() if k < normals.size() else Vector3.UP)
	if indices.is_empty():
		for k in verts.size():
			i_out.append(start + k)
	else:
		for k in indices.size():
			i_out.append(start + indices[k])
	into[0] = v_out
	into[1] = n_out
	into[2] = i_out


## A kit model's drawable surfaces with their place in the model, read once
## a run: [mesh, surface, material key, transform].
static func _model_parts(file: String) -> Array:
	if _parts.has(file):
		return _parts[file]
	var found: Array = []
	var scene := load(DIR + file + ".glb") as PackedScene
	if scene == null:
		push_warning("RimFort: missing model %s" % file)
		_parts[file] = found
		return found
	var root := scene.instantiate() as Node3D
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var piece := node as MeshInstance3D
		if str(piece.name).contains("colonly") or piece.mesh == null:
			continue
		var xform := Transform3D.IDENTITY
		var walk: Node = piece
		while walk != root and walk is Node3D:
			xform = (walk as Node3D).transform * xform
			walk = walk.get_parent()
		for s in piece.mesh.get_surface_count():
			var key := _key(piece.mesh.surface_get_material(s))
			if key != "":
				found.append([piece.mesh, s, key, xform])
	root.free()
	_parts[file] = found
	return found


## Which of our materials a kit material becomes ("" to leave it out).
static func _key(material: Material) -> String:
	if material == null:
		return ""
	var named := material.resource_name
	for prefix: String in GLOW:
		if named.begins_with(prefix):
			return "glow"
	for prefix: String in DARK:
		if named.begins_with(prefix):
			return "dark"
	for prefix: String in PLATE:
		if named.begins_with(prefix):
			return "plate"
	return ""
