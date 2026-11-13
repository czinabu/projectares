extends Node3D
## The view while the player works the gunsmith bench: the camera eases in
## from where it was to look down at the gun on the bench and the card behind
## it, and the mouse works the bench through `HomeBase`'s bench calls. The
## wheel turns, a click (or F) picks, a right click steps back and Esc
## leaves. Nothing on the screen: everything shown is on the bench itself.
##
## A view only, like `WorldScreen`: the base decides nothing here, it only
## changes what the bench shows and asks for equips through its own signal.
##
## Load with `preload("res://core/ui/bench_view.gd")`. Give it `base`, add it
## to the tree and call `focus()`. It frees itself and emits `closed` when the
## player leaves the bench.

signal closed

## Where the camera sits and what it looks at, in the bench's own space (local
## +Z is where you stand to use it).
var eye := Vector3(0.0, 1.8, 1.55)
var look_at_point := Vector3(0.0, 1.55, -0.1)
var fov := 55.0
## Seconds the view takes to move in.
var move_time := 0.35

var base: HomeBase

var _camera: Camera3D
var _previous: Camera3D
var _from := Transform3D.IDENTITY
var _from_fov := 70.0
var _move := 1.0


## Moves the view in to the bench and starts taking the mouse.
func focus() -> void:
	if not is_inside_tree() or base == null:
		return
	_previous = get_viewport().get_camera_3d()
	_camera = Camera3D.new()
	_camera.name = "BenchCamera"
	_camera.near = 0.05
	_camera.top_level = true
	add_child(_camera)
	if _previous:
		_from = _previous.global_transform
		_from_fov = _previous.fov
		_move = 0.0
	else:
		_move = 1.0
	_camera.global_transform = _from if _previous else view_transform()
	_camera.fov = _from_fov if _previous else fov
	_camera.make_current()


## Where the camera ends up, looking at the bench (global).
func view_transform() -> Transform3D:
	var bench := base.global_transform * base.bench_transform()
	var from := bench * eye
	return Transform3D(Basis.looking_at(bench * look_at_point - from, Vector3.UP), from)


## Steps away: the base drops anything not picked, the view goes back to the
## camera that had it.
func leave() -> void:
	if base != null and is_instance_valid(base):
		base.leave_bench()
	if _previous != null and is_instance_valid(_previous) and _previous.is_inside_tree():
		_previous.make_current()
	_previous = null
	closed.emit()
	queue_free()


func _process(delta: float) -> void:
	if _camera == null or base == null or not is_instance_valid(base):
		return
	var target := view_transform()
	if _move < 1.0:
		_move = minf(1.0, _move + delta / maxf(move_time, 0.001))
		var t := ease(_move, -2.0)
		_camera.global_transform = _from.interpolate_with(target, t)
		_camera.fov = lerpf(_from_fov, fov, t)
	else:
		_camera.global_transform = target
		_camera.fov = fov


func _unhandled_input(event: InputEvent) -> void:
	if base == null or not is_instance_valid(base):
		return
	var handled := true
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_DOWN:
				base.bench_scroll(1)
			MOUSE_BUTTON_WHEEL_UP:
				base.bench_scroll(-1)
			MOUSE_BUTTON_LEFT:
				base.bench_select()
			MOUSE_BUTTON_RIGHT:
				if not base.bench_back():
					leave()
			_:
				handled = false
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		leave()
	elif event.is_action_pressed("interact"):
		base.bench_select()
	else:
		handled = false
	if handled and is_inside_tree():
		get_viewport().set_input_as_handled()
