class_name Terrain
extends StaticBody3D
## Open ground for a map: a square heightfield with collision and a mesh.
##
## A map fills `heights` (a grid of `side` x `side` samples, `cell` metres
## apart, centred on the node) with `shape`, or hands in a grid it kept from
## before, then calls `build`. `height_at` answers how high the ground is
## anywhere, so a map can stand its markers and props on it.
##
## The collision is a heightmap sampled every metre from the same grid the
## mesh uses, so what you see is what you stand on. Knows nothing about any
## world.

## Metres between samples. The mesh has one quad per cell.
var cell := 4.0
## Samples along each edge. The ground is `(side - 1) * cell` metres across.
var side := 161
## Row by row along Z, `side * side` values.
var heights := PackedFloat32Array()
## The ground is drawn in square tiles this many cells across, so only the
## tiles in view (and near enough to cast a shadow there) are drawn.
var tile_cells := 80
var tiles: Array[MeshInstance3D] = []


## The width of the ground in metres.
func extent() -> float:
	return (side - 1) * cell


## Fills the grid from `height_of`, called with the (x, z) of every sample.
func shape(height_of: Callable) -> void:
	heights.resize(side * side)
	var half := extent() * 0.5
	for iz in side:
		for ix in side:
			heights[iz * side + ix] = height_of.call(ix * cell - half, iz * cell - half)


## The height of the ground at (x, z) in the terrain's own space. Outside the
## grid it answers for the nearest edge.
func height_at(x: float, z: float) -> float:
	var half := extent() * 0.5
	var fx := clampf((x + half) / cell, 0.0, side - 1.0)
	var fz := clampf((z + half) / cell, 0.0, side - 1.0)
	var ix := mini(int(fx), side - 2)
	var iz := mini(int(fz), side - 2)
	var tx := fx - ix
	var tz := fz - iz
	var a := heights[iz * side + ix]
	var b := heights[iz * side + ix + 1]
	var c := heights[(iz + 1) * side + ix]
	var d := heights[(iz + 1) * side + ix + 1]
	return lerpf(lerpf(a, b, tx), lerpf(c, d, tx), tz)


## The point on the ground under (x, z).
func on_ground(x: float, z: float) -> Vector3:
	return Vector3(x, height_at(x, z), z)


## How steep the ground is at (x, z): 0 is flat, 1 is a 45 degree slope.
func slope_at(x: float, z: float) -> float:
	var dx := height_at(x + cell, z) - height_at(x - cell, z)
	var dz := height_at(x, z + cell) - height_at(x, z - cell)
	return Vector2(dx, dz).length() / (2.0 * cell)


## Creates the collision and the mesh from `heights`. `collision` is the
## heightmap from an earlier build of the same grid (see `collision_data`),
## which saves working it out again.
func build(material: Material, collision: PackedFloat32Array = PackedFloat32Array()) -> void:
	collision_layer = Actor.LAYER_WORLD
	collision_mask = 0
	var field := HeightMapShape3D.new()
	var width := int(extent()) + 1
	field.map_width = width
	field.map_depth = width
	field.map_data = collision if collision.size() == width * width else collision_data()
	var col := CollisionShape3D.new()
	col.shape = field
	add_child(col)
	var cells := side - 1
	var step := maxi(tile_cells, 1)
	for z0 in range(0, cells, step):
		for x0 in range(0, cells, step):
			var tile := MeshInstance3D.new()
			tile.name = "Tile_%d_%d" % [x0 / step, z0 / step]
			tile.mesh = _mesh(material, x0, z0, mini(step, cells - x0), mini(step, cells - z0))
			add_child(tile)
			tiles.append(tile)


## The ground sampled every metre, as the heightmap shape wants it.
func collision_data() -> PackedFloat32Array:
	var width := int(extent()) + 1
	var half := extent() * 0.5
	var data := PackedFloat32Array()
	data.resize(width * width)
	for iz in width:
		for ix in width:
			data[iz * width + ix] = height_at(ix - half, iz - half)
	return data


## The mesh of one tile: `count_x` by `count_z` cells from cell (x0, z0).
## Neighbouring tiles share their edge samples and normals, so no seam shows.
func _mesh(material: Material, x0: int, z0: int, count_x: int, count_z: int) -> ArrayMesh:
	var half := extent() * 0.5
	var row := count_x + 1
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	verts.resize(row * (count_z + 1))
	normals.resize(verts.size())
	uvs.resize(verts.size())
	for tz in count_z + 1:
		for tx in row:
			var ix := x0 + tx
			var iz := z0 + tz
			var i := tz * row + tx
			verts[i] = Vector3(ix * cell - half, heights[iz * side + ix], iz * cell - half)
			var left := heights[iz * side + maxi(ix - 1, 0)]
			var right := heights[iz * side + mini(ix + 1, side - 1)]
			var up := heights[maxi(iz - 1, 0) * side + ix]
			var down := heights[mini(iz + 1, side - 1) * side + ix]
			normals[i] = Vector3(left - right, 2.0 * cell, up - down).normalized()
			uvs[i] = Vector2(ix, iz)
	indices.resize(count_x * count_z * 6)
	var n := 0
	for tz in count_z:
		for tx in count_x:
			var i := tz * row + tx
			indices[n] = i
			indices[n + 1] = i + 1
			indices[n + 2] = i + row
			indices[n + 3] = i + 1
			indices[n + 4] = i + row + 1
			indices[n + 5] = i + row
			n += 6
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	return mesh
