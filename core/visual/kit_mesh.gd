class_name KitMesh
extends RefCounted
## Big scenery built from many placed pieces of a model kit (the Modular
## Sci-Fi Megakit in `assets/props/megakit`) and plain boxes, merged into
## one mesh with one surface a material, so a whole building or a mile of
## wall costs a few draw calls and nothing a frame.
##
## Kit models' own materials are dropped: each surface is sorted into a key
## by its material's name (`GLOW`, `DARK`, `PLATE`; anything else, decals and
## collision shapes, is left out), and `build` dresses each key with the
## material the caller gives. Only positions and normals are kept, so the
## materials must not need UVs (`Look.surface` is laid on by world position).
## View only: never collision, never built on a server.

const DIR := "res://assets/props/megakit/"
## Kit material names (prefixes) for each key.
const GLOW := ["MI_Trim_03_Cables", "M_Glass", "M_Light"]
const DARK := ["MI_Trim_03", "M_Black"]
const PLATE := ["MI_Trim_01", "MI_Trim_02", "MI_PaddedWall"]

## key -> [verts, normals, indices], in the order keys were first used.
var _surfaces := {}
## Each model's drawable surfaces, read once a run: file -> [[mesh, surface, key, xform], ...].
static var _parts := {}
## Each mesh surface's arrays, read once a run: "<id>:<surface>" -> arrays.
static var _arrays := {}


## Adds every drawable surface of kit model `file` at `xform`; returns the
## bounds it covers. `recolor` maps a key to another ("plate" -> "dark").
func add(file: String, xform: Transform3D, recolor := {}) -> AABB:
	var box := AABB(xform.origin, Vector3.ZERO)
	var first := true
	for part: Array in model_parts(file):
		var placed := xform * (part[3] as Transform3D)
		var drawn := placed * (part[0] as Mesh).get_aabb()
		box = drawn if first else box.merge(drawn)
		first = false
		add_mesh(str(recolor.get(part[2], part[2])), part[0], part[1], placed)
	return box


## A plain box of `size` at `xform` on surface `key`.
func add_box(key: String, size: Vector3, xform: Transform3D) -> void:
	add_mesh(key, _unit_box(), 0, xform * Transform3D(Basis.IDENTITY.scaled(size), Vector3.ZERO))


## Adds one surface of `mesh` at `xform` to surface `key`.
func add_mesh(key: String, mesh: Mesh, surface: int, xform: Transform3D) -> void:
	var id := "%d:%d" % [mesh.get_instance_id(), surface]
	if not _arrays.has(id):
		_arrays[id] = mesh.surface_get_arrays(surface)
	var arrays: Array = _arrays[id]
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var placed := PackedVector3Array()
	var turned := PackedVector3Array()
	placed.resize(verts.size())
	turned.resize(verts.size())
	var turn := xform.basis.inverse().transposed()
	# A mirroring transform turns faces inside out: wind them the other way.
	var flip := xform.basis.determinant() < 0.0
	for k in verts.size():
		placed[k] = xform * verts[k]
		turned[k] = (turn * normals[k]).normalized() if k < normals.size() else Vector3.UP
	if indices.is_empty():
		indices.resize(verts.size())
		for k in verts.size():
			indices[k] = k
	if flip:
		indices = indices.duplicate()
		for k in range(0, indices.size() - 2, 3):
			var swap := indices[k + 1]
			indices[k + 1] = indices[k + 2]
			indices[k + 2] = swap
	add_arrays(key, placed, turned, indices)


## Adds ready-placed triangles to surface `key`.
func add_arrays(key: String, verts: PackedVector3Array, normals: PackedVector3Array, indices: PackedInt32Array) -> void:
	if not _surfaces.has(key):
		_surfaces[key] = [PackedVector3Array(), PackedVector3Array(), PackedInt32Array()]
	var into: Array = _surfaces[key]
	var v_out: PackedVector3Array = into[0]
	var n_out: PackedVector3Array = into[1]
	var i_out: PackedInt32Array = into[2]
	var start := v_out.size()
	v_out.append_array(verts)
	n_out.append_array(normals)
	var from := i_out.size()
	i_out.resize(from + indices.size())
	for k in indices.size():
		i_out[from + k] = start + indices[k]
	into[0] = v_out
	into[1] = n_out
	into[2] = i_out


func is_empty() -> bool:
	return _surfaces.is_empty()


## The merged mesh: one surface a key, in `order` (keys not in it follow),
## each with `materials[key]`. Clears what was added.
func build(materials: Dictionary, order: Array = []) -> ArrayMesh:
	var keys: Array = order.filter(func(k: Variant) -> bool: return _surfaces.has(k))
	for key: String in _surfaces:
		if not keys.has(key):
			keys.append(key)
	var mesh := ArrayMesh.new()
	for key: String in keys:
		var parts: Array = _surfaces[key]
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = parts[0]
		arrays[Mesh.ARRAY_NORMAL] = parts[1]
		arrays[Mesh.ARRAY_INDEX] = parts[2]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, materials.get(key))
	_surfaces.clear()
	return mesh


## `build` wrapped in a node that casts no shadow unless `shadow`.
func node(title: String, materials: Dictionary, order: Array = [], shadow := false) -> MeshInstance3D:
	var shown := MeshInstance3D.new()
	shown.name = title
	shown.mesh = build(materials, order)
	shown.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return shown


## A kit model's drawable surfaces with their place in the model, read once
## a run: [mesh, surface, key, transform].
static func model_parts(file: String) -> Array:
	if _parts.has(file):
		return _parts[file]
	var found: Array = []
	var scene := load(DIR + file + ".glb") as PackedScene
	if scene == null:
		push_warning("KitMesh: missing model %s" % file)
		_parts[file] = found
		return found
	var root := scene.instantiate() as Node3D
	for child in root.find_children("*", "MeshInstance3D", true, false):
		var piece := child as MeshInstance3D
		if str(piece.name).contains("colonly") or piece.mesh == null:
			continue
		var xform := Transform3D.IDENTITY
		var walk: Node = piece
		while walk != root and walk is Node3D:
			xform = (walk as Node3D).transform * xform
			walk = walk.get_parent()
		for s in piece.mesh.get_surface_count():
			var key := key_of(piece.mesh.surface_get_material(s))
			if key != "":
				found.append([piece.mesh, s, key, xform])
	root.free()
	_parts[file] = found
	return found


## The bounds of a kit model as drawn (no collision shapes).
static func model_box(file: String) -> AABB:
	var box := AABB()
	var first := true
	for part: Array in model_parts(file):
		var placed := (part[3] as Transform3D) * (part[0] as Mesh).get_aabb()
		box = placed if first else box.merge(placed)
		first = false
	return box


## Which key a kit material becomes ("" to leave it out).
static func key_of(material: Material) -> String:
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


static var _box_mesh: BoxMesh

static func _unit_box() -> BoxMesh:
	if _box_mesh == null:
		_box_mesh = BoxMesh.new()
	return _box_mesh
