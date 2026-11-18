class_name Crowd
extends Node3D
## A crowd of spectators, view only: low-poly figures in one MultiMesh per
## block of `CHUNK`, so blocks out of view are culled and the whole crowd
## costs a handful of draw calls. A map lists where people stand (`add`),
## then `build`s it; `assets/shaders/crowd.gdshader` sways them and makes
## those near the viewer cheer. Nothing here collides or is read by the
## game, and a map makes one only where `Look` is on.

const CHUNK := 1500
## Past this the crowd is not drawn.
const DRAW_RANGE := 900.0
const STICK := Color(0.3, 0.85, 1.0)

var _spots: Array[Transform3D] = []
var _colors: Array[Color] = []
var _custom: Array[Color] = []
var _material: ShaderMaterial


## Someone standing at `at` (their feet), facing `yaw`, in `clothes`. A
## `lively` one moves more; one with a `stick` holds up a light.
func add(at: Vector3, yaw: float, clothes: Color, lively: float, stick: bool, phase: float, size := 1.0) -> void:
	_spots.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * size), at))
	_colors.append(clothes)
	_custom.append(Color(phase, lively, 1.0 if stick else 0.0, 0.0))


func count() -> int:
	return _spots.size()


## Makes the multimeshes from everyone added so far.
func build() -> void:
	_material = ShaderMaterial.new()
	_material.shader = load("res://assets/shaders/crowd.gdshader") as Shader
	_material.set_shader_parameter("stick_color", STICK)
	var mesh := person_mesh()
	mesh.surface_set_material(0, _material)
	var from := 0
	while from < _spots.size():
		var to := mini(from + CHUNK, _spots.size())
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = mesh
		mm.instance_count = to - from
		for i in range(from, to):
			mm.set_instance_transform(i - from, _spots[i])
			mm.set_instance_color(i - from, _colors[i])
			mm.set_instance_custom_data(i - from, _custom[i])
		var node := MultiMeshInstance3D.new()
		node.name = "Crowd%d" % (from / CHUNK)
		node.multimesh = mm
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.visibility_range_end = DRAW_RANGE
		add_child(node)
		from = to


func _process(_delta: float) -> void:
	if _material == null:
		return
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		_material.set_shader_parameter("hype_at", cam.global_position)


## One spectator, about 1.7 m: a tapered six-sided body, a head and a light
## stick held up (its vertices marked with UV.x over 1, folded away by the
## shader for those without one).
static func person_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_prism(st, 6, 0.0, 1.3, 0.2, 0.25, 0.0)
	_prism(st, 6, 1.36, 1.62, 0.12, 0.1, 0.0)
	_prism(st, 4, 1.25, 1.95, 0.03, 0.03, 2.0, Vector3(0.28, 0, 0))
	st.generate_normals()
	return st.commit()


## A closed prism of `sides` from `y0` (radius `r0`) to `y1` (radius `r1`).
static func _prism(st: SurfaceTool, sides: int, y0: float, y1: float, r0: float, r1: float, u: float,
		at := Vector3.ZERO) -> void:
	for k in sides:
		var a0 := TAU * k / sides
		var a1 := TAU * (k + 1) / sides
		var b0 := at + Vector3(cos(a0) * r0, y0, sin(a0) * r0)
		var b1 := at + Vector3(cos(a1) * r0, y0, sin(a1) * r0)
		var t0 := at + Vector3(cos(a0) * r1, y1, sin(a0) * r1)
		var t1 := at + Vector3(cos(a1) * r1, y1, sin(a1) * r1)
		var top := at + Vector3(0, y1, 0)
		var bottom := at + Vector3(0, y0, 0)
		for v: Vector3 in [b0, t1, t0, b0, b1, t1, t0, t1, top, b1, b0, bottom]:
			st.set_uv(Vector2(u, 0))
			st.add_vertex(v)
