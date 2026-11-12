class_name WorldScreen
extends Node3D
## A screen that stands in the world: a flat panel that shows a 2D viewport
## (a console's display, a shop terminal, a board) and takes the mouse and
## keyboard while you use it. This is how menus are done without leaving the
## world: walk up, press E, the view moves in to face the screen, and you
## click on the screen itself.
##
## The screen faces its local +Z and is centred on its origin, `size` metres
## across. Give it the viewport to show (`viewport`) before it enters the
## tree, then `focus()` to use it and `unfocus()` to step back. It is a view:
## it never decides anything, and whatever owns the viewport's controls acts
## on what they emit.
##
## Input reaches the viewport through `_unhandled_input`, so anything on the
## screen layer above (the phone) gets first say. Keys go to the screen too,
## so text fields work; a key the screen does not use falls through.

## The size of the screen face in metres.
var size := Vector2(1.6, 0.9)
## The 2D viewport shown on the screen and sent its input.
var viewport: SubViewport
## How much of the view the screen fills once focused.
var fill := 0.9
## Seconds the view takes to move in to the screen.
var move_time := 0.35
## How brightly the screen glows, so it reads in a dark room.
var glow := 0.6

## True while the screen is in use.
var focused := false

var _quad: MeshInstance3D
var _camera: Camera3D
var _previous: Camera3D
var _from := Transform3D.IDENTITY
var _from_fov := 70.0
var _move := 1.0


func _ready() -> void:
	_quad = MeshInstance3D.new()
	_quad.name = "Face"
	var mesh := QuadMesh.new()
	mesh.size = size
	_quad.mesh = mesh
	_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	if viewport:
		mat.albedo_texture = viewport.get_texture()
		mat.emission_enabled = true
		mat.emission_texture = viewport.get_texture()
		mat.emission_energy_multiplier = glow
	_quad.material_override = mat
	# A hair in front of whatever it is mounted on, so it never flickers.
	_quad.position = Vector3(0, 0, 0.02)
	add_child(_quad)


func _exit_tree() -> void:
	if focused:
		unfocus()


## Moves the view in to face the screen and starts sending it input.
func focus() -> void:
	if focused or not is_inside_tree():
		return
	focused = true
	_previous = get_viewport().get_camera_3d()
	_camera = Camera3D.new()
	_camera.name = "ScreenView"
	_camera.near = 0.05
	add_child(_camera)
	if _previous:
		_from = _previous.global_transform
		_from_fov = _previous.fov
		_camera.fov = _from_fov
		_move = 0.0
	else:
		_move = 1.0
	_camera.top_level = true
	_camera.global_transform = _from if _previous else view_transform()
	_camera.make_current()


## Gives the view back to the camera that had it and stops taking input.
func unfocus() -> void:
	if not focused:
		return
	focused = false
	if _previous != null and is_instance_valid(_previous) and _previous.is_inside_tree():
		_previous.make_current()
	_previous = null
	if _camera:
		_camera.queue_free()
		_camera = null


## Where the camera sits to frame the whole screen, `fill` of the view.
func view_transform() -> Transform3D:
	var fov := deg_to_rad(_camera.fov if _camera else 70.0)
	var aspect := 16.0 / 9.0
	if is_inside_tree():
		var rect := get_viewport().get_visible_rect().size
		if rect.y > 0.0:
			aspect = rect.x / rect.y
	var half_v := tan(fov * 0.5)
	var by_height := size.y * 0.5 / half_v
	var by_width := size.x * 0.5 / (half_v * aspect)
	var distance := maxf(by_height, by_width) / fill
	var face := global_transform.orthonormalized()
	return Transform3D(face.basis, face.origin + face.basis.z * distance)


func _process(delta: float) -> void:
	if not focused or _camera == null:
		return
	var target := view_transform()
	if _move < 1.0:
		_move = minf(1.0, _move + delta / maxf(move_time, 0.001))
		var t := ease(_move, -2.0)
		_camera.global_transform = _from.interpolate_with(target, t)
	else:
		_camera.global_transform = target


## Where a ray from `origin` along `direction` (global) meets the screen, in
## the viewport's pixels. (-1, -1) when it misses.
func screen_point(origin: Vector3, direction: Vector3) -> Vector2:
	var miss := Vector2(-1, -1)
	if viewport == null:
		return miss
	var to_local := global_transform.affine_inverse()
	var o := to_local * origin
	var d := to_local.basis * direction
	if absf(d.z) < 0.00001:
		return miss
	var t := -o.z / d.z
	if t < 0.0:
		return miss
	var p := o + d * t
	var u := p.x / size.x + 0.5
	var v := 0.5 - p.y / size.y
	if u < 0.0 or u > 1.0 or v < 0.0 or v > 1.0:
		return miss
	return Vector2(u * viewport.size.x, v * viewport.size.y)


func _unhandled_input(event: InputEvent) -> void:
	if not focused or viewport == null:
		return
	if event is InputEventMouse:
		var camera := get_viewport().get_camera_3d()
		if camera == null:
			return
		var mouse := event as InputEventMouse
		var at := screen_point(camera.project_ray_origin(mouse.position), camera.project_ray_normal(mouse.position))
		if at.x < 0.0:
			return
		var moved := mouse.duplicate() as InputEventMouse
		moved.position = at
		moved.global_position = at
		viewport.push_input(moved, true)
		get_viewport().set_input_as_handled()
	elif event is InputEventKey:
		viewport.push_input(event.duplicate(), true)
		if viewport.is_input_handled():
			get_viewport().set_input_as_handled()
