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
## The plan table (`use_plan`): set `target` to "plan" and the view comes in
## over the table's lectern, with the base's hologram beyond it, and mounts
## the customizer (`plan_panel.gd`) on the lectern's screen as a
## `WorldScreen`. The mouse works the screen; a right click steps back on it
## (or leaves when there is nothing to step back from) and Esc leaves
## (`leave_plan`).
##
## Load with `preload("res://core/ui/bench_view.gd")`. Give it `base`, add it
## to the tree and call `focus()`. It frees itself and emits `closed` when the
## player leaves the bench.

signal closed

const PlanPanel := preload("res://core/ui/plan_panel.gd")

## Where the camera sits and what it looks at, in the bench's own space (local
## +Z is where you stand to use it).
var eye := Vector3(0.0, 1.8, 1.55)
var look_at_point := Vector3(0.0, 1.55, -0.1)
var fov := 55.0
## Seconds the view takes to move in.
var move_time := 0.35

var base: HomeBase
## What is being worked: "bench" (the gunsmith bench) or "plan" (the plan
## table). Each has its calls on `HomeBase` named after it.
var target := "bench":
	set(value):
		target = value
		if value == "plan":
			eye = Vector3(0.0, 2.09, 2.7)
			look_at_point = Vector3(0.0, 1.03, 1.0)
			fov = 70.0

var _camera: Camera3D
var _previous: Camera3D
var _from := Transform3D.IDENTITY
var _from_fov := 70.0
var _move := 1.0
## The plan table's screen while in use, and the customizer on it.
var screen: WorldScreen
var panel: Control
var _plan_view: SubViewport


## Moves the view in to the bench and starts taking the mouse.
func focus() -> void:
	if not is_inside_tree() or base == null:
		return
	_previous = get_viewport().get_camera_3d()
	_camera = Camera3D.new()
	_camera.name = "BenchCamera"
	# Your own head is left out of it (`PlayerController.screen_view_up`).
	_camera.set_meta(PlayerController.SCREEN_VIEW, true)
	_camera.cull_mask = 0xFFFFF & ~(1 << (PlayerController.MirrorScript.HEAD_LAYER - 1))
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
	if target == "plan":
		_mount_panel()


## The customizer on the plan table's lectern: a 2D panel in a viewport,
## shown on the screen there and worked through it.
func _mount_panel() -> void:
	if panel == null:
		var view := SubViewport.new()
		view.name = "PlanView"
		view.size = Vector2i(1600, 900)
		view.disable_3d = true
		view.gui_embed_subwindows = true
		panel = PlanPanel.new()
		panel.base = base
		view.add_child(panel)
		add_child(view)
		_plan_view = view
	_place_screen()


## Puts the customizer's screen on the lectern. A change to the plan rebuilds
## the table, and the screen with it, so this runs again whenever the screen
## is gone while the plan table is in use.
func _place_screen() -> bool:
	var face: Node3D = base.plan_screen()
	if face == null or _plan_view == null:
		return false
	screen = WorldScreen.new()
	screen.name = "LiveScreen"
	screen.size = HomeBase.PLAN_SCREEN
	screen.glow = 0.9
	screen.viewport = _plan_view
	face.add_child(screen)
	return true


## Whether the plan table's screen is up, putting it back on a rebuilt table.
func _screen_up() -> bool:
	if screen != null and is_instance_valid(screen):
		if screen.get_parent() == base.plan_screen() and screen.is_inside_tree():
			return true
		screen.queue_free()
	screen = null
	return _place_screen()


## Where the camera ends up, looking at the bench (global).
func view_transform() -> Transform3D:
	var bench: Transform3D = base.global_transform * base.call(target + "_transform")
	var from := bench * eye
	return Transform3D(Basis.looking_at(bench * look_at_point - from, Vector3.UP), from)


## Steps away: the base drops anything not picked, the view goes back to the
## camera that had it.
func leave() -> void:
	if screen != null and is_instance_valid(screen):
		screen.queue_free()
	screen = null
	if base != null and is_instance_valid(base):
		base.call("leave_" + target)
	if _previous != null and is_instance_valid(_previous) and _previous.is_inside_tree():
		_previous.make_current()
	_previous = null
	closed.emit()
	queue_free()


func _process(delta: float) -> void:
	if _camera == null or base == null or not is_instance_valid(base):
		return
	if target == "plan" and panel != null:
		_screen_up()
	var goal := view_transform()
	if _move < 1.0:
		_move = minf(1.0, _move + delta / maxf(move_time, 0.001))
		var t := ease(_move, -2.0)
		_camera.global_transform = _from.interpolate_with(goal, t)
		_camera.fov = lerpf(_from_fov, fov, t)
	else:
		_camera.global_transform = goal
		_camera.fov = fov


func _unhandled_input(event: InputEvent) -> void:
	if base == null or not is_instance_valid(base):
		return
	if target == "plan":
		if _screen_up():
			_screen_input(event)
		elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			leave()
		return
	var handled := true
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_DOWN:
				base.call(target + "_scroll", 1)
			MOUSE_BUTTON_WHEEL_UP:
				base.call(target + "_scroll", -1)
			MOUSE_BUTTON_LEFT:
				base.call(target + "_select")
			MOUSE_BUTTON_RIGHT:
				if not base.call(target + "_back"):
					leave()
			_:
				handled = false
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		leave()
	elif event.is_action_pressed("interact"):
		base.call(target + "_select")
	else:
		handled = false
	if handled and is_inside_tree():
		get_viewport().set_input_as_handled()


## The plan table's input: the mouse goes to the screen where it points, a
## right click steps back on it (or leaves), Esc leaves.
func _screen_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		leave()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		if not panel.back():
			leave()
	elif event is InputEventMouse:
		screen.forward_mouse(event, _camera)
	else:
		return
	if is_inside_tree():
		get_viewport().set_input_as_handled()
