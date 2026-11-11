class_name PlayerController
extends Node
## Local player input and camera. Reads the keyboard and mouse, writes the
## Actor's command, and runs the first/third-person camera.
##
## Camera rule: AUTO uses first-person with guns and third-person for melee and
## flight. Aiming down sights always forces first-person, and shots always come
## from the character's eyes, so third-person never lets you shoot from cover.

enum ViewMode { AUTO, FIRST, THIRD }

const VIEW_NAMES := ["Auto", "First-person", "Third-person"]

var actor: Actor
var camera: Camera3D
var view_mode := ViewMode.AUTO
var mouse_sensitivity := 0.0022
var third_person_distance := 3.8
var base_fov := 80.0
var ads_fov := 55.0

var yaw := 0.0
var pitch := 0.0
var _cam_dist := 0.0


func setup(p_actor: Actor) -> void:
	actor = p_actor
	yaw = actor.cmd.yaw


func _ready() -> void:
	process_physics_priority = -10
	camera = Camera3D.new()
	camera.fov = base_fov
	camera.far = 400.0
	add_child(camera)
	camera.make_current()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _unhandled_input(event: InputEvent) -> void:
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if event is InputEventMouseMotion and captured:
		yaw -= event.relative.x * mouse_sensitivity
		pitch = clampf(pitch - event.relative.y * mouse_sensitivity, -1.5, 1.5)
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if captured else Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseButton and event.pressed and not captured:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed("toggle_view"):
		view_mode = ((view_mode + 1) % 3) as ViewMode
		actor.notice.emit("Camera: %s" % VIEW_NAMES[view_mode])


func _physics_process(_delta: float) -> void:
	if actor == null or not is_instance_valid(actor) or actor.is_dead:
		return
	var cmd := actor.cmd
	cmd.clear_one_shots()
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	cmd.yaw = yaw
	cmd.pitch = pitch
	cmd.move = Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_back", "move_forward"))
	cmd.sprint = Input.is_action_pressed("sprint")
	cmd.jump = Input.is_action_pressed("jump")
	cmd.jump_pressed = Input.is_action_just_pressed("jump")
	cmd.dash = Input.is_action_just_pressed("dash")
	cmd.primary = captured and Input.is_action_pressed("fire")
	cmd.primary_pressed = captured and Input.is_action_just_pressed("fire")
	cmd.secondary = captured and Input.is_action_pressed("alt_fire")
	cmd.secondary_pressed = captured and Input.is_action_just_pressed("alt_fire")
	cmd.reload_pressed = Input.is_action_just_pressed("reload")
	cmd.interact_pressed = Input.is_action_just_pressed("interact")
	cmd.heal_pressed = Input.is_action_just_pressed("heal")
	if Input.is_action_just_pressed("weapon_1"):
		cmd.switch_weapon = 0
	elif Input.is_action_just_pressed("weapon_2"):
		cmd.switch_weapon = 1
	cmd.aim_dir = _compute_aim_dir()


func _process(delta: float) -> void:
	if actor == null or not is_instance_valid(actor):
		return
	var weapon := actor.get_active_weapon()
	var aiming := weapon != null and weapon.is_aiming()
	var target_dist := third_person_distance if _wants_third_person(weapon, aiming) else 0.0
	_cam_dist = lerpf(_cam_dist, target_dist, 1.0 - exp(-12.0 * delta))
	if absf(_cam_dist - target_dist) < 0.01:
		_cam_dist = target_dist

	var look := Basis.from_euler(Vector3(pitch, yaw, 0.0))
	var pivot := actor.get_eye_position()
	var t := _cam_dist / third_person_distance
	var desired := pivot + look * Vector3(0.6 * t, 0.3 * t, _cam_dist)
	if _cam_dist > 0.05:
		# Pull the camera in when a wall is in the way.
		var query := PhysicsRayQueryParameters3D.create(pivot, desired, Actor.LAYER_WORLD)
		var hit := actor.get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			desired = pivot + (hit.position - pivot) * 0.85
	camera.global_transform = Transform3D(look, desired)
	camera.fov = lerpf(camera.fov, ads_fov if aiming else base_fov, 1.0 - exp(-14.0 * delta))
	if actor.body_mesh:
		actor.body_mesh.visible = actor.is_dead or pivot.distance_to(desired) > 0.7


func is_third_person() -> bool:
	return _cam_dist > 0.5


func _wants_third_person(weapon: Weapon, aiming: bool) -> bool:
	if actor.is_dead:
		return true
	if aiming:
		return false
	match view_mode:
		ViewMode.FIRST:
			return false
		ViewMode.THIRD:
			return true
	if weapon and weapon.prefers_third_person():
		return true
	return actor.flight.enabled and actor.airborne_time > 0.35


## Where the crosshair points, converted to a direction from the actor's eyes.
func _compute_aim_dir() -> Vector3:
	var forward := Basis.from_euler(Vector3(pitch, yaw, 0.0)) * Vector3.FORWARD
	if _cam_dist < 0.3 or camera == null:
		return forward
	var from := camera.global_position
	var to := from + forward * 300.0
	var query := PhysicsRayQueryParameters3D.create(from, to, Actor.LAYER_WORLD | Actor.LAYER_ACTORS)
	query.exclude = [actor.get_rid()]
	var hit := actor.get_world_3d().direct_space_state.intersect_ray(query)
	var point: Vector3 = hit.position if not hit.is_empty() else to
	var eye := actor.get_eye_position()
	if eye.distance_to(point) < 2.0 or forward.dot(point - eye) <= 0.0:
		return forward
	return (point - eye).normalized()
