class_name SolidProp
extends RefCounted
## A prop model you cannot walk through (docs/systems/worlds-and-war.md
## "Collision"). A map places it in its gameplay pass, on the server and the
## client alike: a static body on `Actor.LAYER_WORLD` with plain boxes cut to
## the model (`SHAPES`), and, only where `Look` is on, the model itself hung
## inside it. Put under a map's navigation region before the bake, bots path
## round it too.
##
## The placement must not depend on `Look` or on a map's decoration RNG, or
## the server and the client would disagree about where the solid stands.
## Small litter (a gas can, a backpack) stays decoration and is never solid.

## Each model's collision as boxes `[size, centre]`, measured with the model
## fitted the way `Look.prop` fits it: its largest side 1, standing on y = 0
## and centred over the origin. Scaled by the `size` the map asks for.
## `tests/collision_tests.gd` holds every entry to its model.
const SHAPES := {
	"AC.glb": [[Vector3(1.0, 0.66, 0.74), Vector3(0.0, 0.33, 0.0)]],
	"AC_Side.glb": [[Vector3(1.0, 0.53, 0.48), Vector3(0.0, 0.265, 0.0)]],
	"AC_Stacked.glb": [[Vector3(0.67, 1.0, 0.51), Vector3(0.0, 0.5, 0.0)]],
	"Antenna_1.glb": [[Vector3(0.24, 1.0, 0.04), Vector3(0.0, 0.5, 0.0)]],
	"Antenna_2.glb": [[Vector3(0.85, 1.0, 0.9), Vector3(0.0, 0.5, 0.0)]],
	"Tank.glb": [[Vector3(0.68, 1.0, 0.74), Vector3(0.0, 0.5, 0.0)]],
	"Tent.glb": [[Vector3(0.59, 0.42, 1.0), Vector3(0.0, 0.21, 0.0)]],
	"Turret_Gun.glb": [[Vector3(0.99, 0.5, 1.0), Vector3(0.0, 0.25, 0.0)]],
	# The pole, and the lamp head on top of it.
	"Light_Street_2.glb": [
		[Vector3(0.07, 0.92, 0.07), Vector3(0.0, 0.46, -0.068)],
		[Vector3(0.51, 0.09, 0.45), Vector3(0.0, 0.955, 0.0)],
	],
}

## Set on every body this makes. The collision check trusts what hangs in it
## to be its model: the boxes are held to the model by the check instead.
const META := "solid_prop"


## Builds `file` as a solid `size` metres on its longest side, standing on
## `at` and turned `yaw` about the vertical, under `parent`. Returns the body.
static func place(parent: Node3D, file: String, size: float, at: Vector3, yaw: float, wear := 0.6) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = file.get_basename()
	body.collision_layer = Actor.LAYER_WORLD
	body.collision_mask = 0
	body.position = at
	body.rotation.y = yaw
	body.set_meta(META, file)
	for part: Array in SHAPES.get(file, []):
		var shape := BoxShape3D.new()
		shape.size = (part[0] as Vector3) * size
		var col := CollisionShape3D.new()
		col.shape = shape
		col.position = (part[1] as Vector3) * size
		body.add_child(col)
	var model := Look.prop(file, size, wear)
	if model != null:
		body.add_child(model)
	parent.add_child(body)
	return body


## Collision alone for a piece a map's dressing draws: a box `size` across
## at `at`, under `parent` (the navigation region, so bots path round it).
## The dressing is view only; this is what makes the piece solid everywhere.
static func box(parent: Node3D, size: Vector3, at: Transform3D) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = Actor.LAYER_WORLD
	body.collision_mask = 0
	body.transform = at
	var shape := BoxShape3D.new()
	shape.size = size
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)
	parent.add_child(body)
	return body


## The size of the box round every part of `file` at `size`, for checks.
static func box_size(file: String, size: float) -> Vector3:
	var out := AABB()
	var first := true
	for part: Array in SHAPES.get(file, []):
		var box := AABB((part[1] as Vector3) - (part[0] as Vector3) * 0.5, part[0] as Vector3)
		out = box if first else out.merge(box)
		first = false
	return out.size * size
