extends RefCounted
## The collision of Meridian's spectacle (docs/systems/arena-and-race.md):
## every shape `stands.gd` and `works.gd` draw becomes a box, a cylinder or
## a ball on `Actor.LAYER_WORLD`, gathered in one static body per `CHUNK`
## of ground as shape owners (no node per shape). The map builds the
## spectacle on the server too, where nothing is drawn, so this is the same
## on every machine. Shapes thinner than `THIN` (wires, light strips, a
## sign's face) are left out: nobody walks into those.

const CHUNK := 200.0
const THIN := 0.1
## A cone's sides, for its hull.
const SIDES := 10

var parent: Node3D
var _bodies := {}
var _boxes := {}


func _init(p_parent: Node3D) -> void:
	parent = p_parent


func box(size: Vector3, xf: Transform3D) -> void:
	size *= xf.basis.get_scale()
	if minf(size.x, minf(size.y, size.z)) < THIN:
		return
	var key := size.snapped(Vector3.ONE * 0.01)
	var shape: BoxShape3D = _boxes.get(key)
	if shape == null:
		shape = BoxShape3D.new()
		shape.size = key
		_boxes[key] = shape
	_add(shape, xf.orthonormalized())


func cyl(r_top: float, r_bottom: float, h: float, xf: Transform3D) -> void:
	if maxf(r_top, r_bottom) * 2.0 < THIN or h < THIN:
		return
	if is_equal_approx(r_top, r_bottom):
		var drum := CylinderShape3D.new()
		drum.radius = r_top
		drum.height = h
		_add(drum, xf)
		return
	var hull := ConvexPolygonShape3D.new()
	var points := PackedVector3Array()
	for k in SIDES:
		var a := TAU * k / SIDES
		var out := Vector3(cos(a), 0, sin(a))
		points.append(out * r_top + Vector3(0, h * 0.5, 0))
		points.append(out * r_bottom - Vector3(0, h * 0.5, 0))
	hull.points = points
	_add(hull, xf)


func ball(r: float, xf: Transform3D) -> void:
	var round_shape := SphereShape3D.new()
	round_shape.radius = r
	_add(round_shape, xf)


func _add(shape: Shape3D, xf: Transform3D) -> void:
	var cell := Vector2i(floori(xf.origin.x / CHUNK), floori(xf.origin.z / CHUNK))
	var body: StaticBody3D = _bodies.get(cell)
	if body == null:
		body = StaticBody3D.new()
		body.name = "Spectacle_%d_%d" % [cell.x, cell.y]
		body.collision_layer = Actor.LAYER_WORLD
		body.collision_mask = 0
		_bodies[cell] = body
	var owner_id := body.create_shape_owner(body)
	body.shape_owner_add_shape(owner_id, shape)
	body.shape_owner_set_transform(owner_id, xf)


## Puts the bodies in the scene, each whole, so the physics builds each
## once instead of once a shape.
func finish() -> void:
	for body: StaticBody3D in _bodies.values():
		if body.get_parent() == null:
			parent.add_child(body)


## How many shapes in all, for checks.
func count() -> int:
	var n := 0
	for body: StaticBody3D in _bodies.values():
		n += body.get_shape_owners().size()
	return n
