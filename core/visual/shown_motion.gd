class_name ShownMotion
extends Node
## Shows a body between physics ticks (view only). Bodies move 60 times a
## second; a faster screen would show them, and a camera riding them, in
## steps. For each drawn frame this puts its parent (an `Actor` or a
## vehicle) where it is between its last two ticks, so everything posed or
## placed from it (the skin, held weapons, the camera) reads the same smooth
## place, and puts it back where the simulation left it just before the next
## tick (`SceneTree.physics_frame`), so nothing simulated ever sees it.
##
## `Look` adds one to every actor and vehicle it dresses, so a headless
## server has none. The player's own body also turns with the mouse every
## frame (`live_yaw`, set by `PlayerController`), not only every tick.

## A move further than this in one tick is a jump (a teleport, a respawn),
## shown at once.
const JUMP := 3.0

## The yaw (radians) to show the body at this frame, or NAN to take it from
## the ticks. Set each frame by the controller of the player's own body.
var live_yaw := NAN

var _body: Node3D
var _tick := -1
var _from := Transform3D.IDENTITY
var _to := Transform3D.IDENTITY
## Where the simulation left the body, and where it is being shown, while
## the two differ.
var _true := Transform3D.IDENTITY
var _shown := Transform3D.IDENTITY
var _swapped := false


func _ready() -> void:
	_body = get_parent() as Node3D
	# Before the skin poses from the body and the camera follows it.
	process_priority = -100
	if _body != null:
		_to = _body.global_transform
		_from = _to
	get_tree().physics_frame.connect(restore)


func _exit_tree() -> void:
	restore()
	if get_tree().physics_frame.is_connected(restore):
		get_tree().physics_frame.disconnect(restore)


## The body back where the simulation left it, unless something else has
## moved it since it was shown.
func restore() -> void:
	if _swapped and is_instance_valid(_body) and _body.is_inside_tree() \
			and _body.global_transform.is_equal_approx(_shown):
		_body.global_transform = _true
	_swapped = false


func _process(_delta: float) -> void:
	show_at(Engine.get_physics_frames(), Engine.get_physics_interpolation_fraction())


## Shows the body `fraction` of the way from its tick before `ticks` to it.
func show_at(ticks: int, fraction: float) -> void:
	if _body == null or not is_instance_valid(_body) or not _body.is_inside_tree():
		return
	var now := _true if _swapped and _body.global_transform.is_equal_approx(_shown) else _body.global_transform
	_swapped = false
	if ticks != _tick:
		var steady := ticks == _tick + 1 and _to.origin.distance_to(now.origin) < JUMP
		_from = _to if steady else now
		_to = now
		_tick = ticks
	var thinned: bool = _body is Actor and (_body as Actor).tick_every > 1
	var shown := now if thinned else _from.interpolate_with(_to, clampf(fraction, 0.0, 1.0))
	if not is_nan(live_yaw):
		shown.basis = Basis(Vector3.UP, live_yaw).scaled(now.basis.get_scale())
		live_yaw = NAN
	if shown.is_equal_approx(now):
		_body.global_transform = now
		return
	_true = now
	_shown = shown
	_body.global_transform = shown
	_shown = _body.global_transform
	_swapped = true


## The shown motion of `body`, or null where nothing dresses it.
static func of(body: Node) -> ShownMotion:
	return body.get_node_or_null("ShownMotion") as ShownMotion if body != null else null
