class_name PlayerController
extends Node
## Local player input and camera. Reads the keyboard and mouse, writes the
## Actor's command, and runs the first/third-person camera.
##
## The camera only changes when the player presses the toggle. Shots always
## come from the character's eyes, so third-person never lets you shoot from
## behind cover.

## The player pressed the sign-out key. Alive, that starts or cancels a
## sign-out. Dead, it means going back to the hub.
signal sign_out_requested
## The player, dead, asked to drop back in.
signal redeploy_requested
## While down: a number key picked a place to land (0 for the first on offer).
signal drop_requested(index: int)

enum ViewMode { FIRST, THIRD }
## How the melee side is picked: by flicking the mouse, or by the movement keys.
enum StanceControl { MOUSE, MOVE }

const VIEW_NAMES := ["First-person", "Third-person"]
const STANCE_CONTROL_NAMES := ["mouse flick", "movement keys"]
const STANCE_CONTROL_HINTS := [
	"flick the mouse left, right or up",
	"hold A, D or W as you attack or guard",
]
## Where the held weapon sits relative to the camera in first-person.
const FIRST_PERSON_HAND := Vector3(0.32, -0.3, -0.75)

var actor: Actor
var camera: Camera3D
var view_mode := ViewMode.FIRST
var mouse_sensitivity := 0.0022
var invert_y := false
## Set while the phone is open: the character stands still and the mouse is
## left alone, so you can tap and type.
var input_blocked := false
## Set while a mirror stands in front of you (1-20, 0 for none). In first
## person your body stays drawn on this render layer, which this camera leaves
## out, so the mirror's camera can still show it.
var body_layer := 0
var third_person_distance := 3.8
var third_person_aim_distance := 2.2
## Camera distance while riding a vehicle, which is bigger than a person.
var ride_distance := 5.2
## The view used while riding. It starts in third-person and V switches it,
## separately from the on-foot view, which comes back when you get off.
var ride_view := ViewMode.THIRD
var base_fov := 80.0
## True while the player has the watch on their wrist raised to read it
## (the `check_wrist` key toggles it). Only the HUD reads it.
var wrist_raised := false
## The field of view while the camera is behind the character.
var base_fov_third := 80.0
var ads_fov := 55.0
## How far the mouse has to move, in pixels, to count as a stance flick.
var flick_threshold := 45.0
## How quickly old mouse movement stops counting toward a flick.
var flick_decay := 9.0
var stance := 0
var stance_control := StanceControl.MOUSE

var yaw := 0.0
var pitch := 0.0
var _cam_dist := 0.0
var _pending_switch := -1
var _flick := Vector2.ZERO
var _rng := RandomNumberGenerator.new()
var _thrust_audio: AudioStreamPlayer


func setup(p_actor: Actor) -> void:
	actor = p_actor
	stance_control = StanceControl.MOVE if Profile.melee_control == "move" else StanceControl.MOUSE
	yaw = actor.cmd.yaw


func _ready() -> void:
	process_physics_priority = -10
	camera = Camera3D.new()
	camera.fov = base_fov
	camera.far = 400.0
	add_child(camera)
	camera.make_current()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	for weapon in actor.weapons:
		var gun := weapon as Gun
		if gun:
			gun.fired.connect(_on_gun_fired.bind(gun))
	actor.hit_confirmed.connect(_on_hit_confirmed)
	actor.health.damaged.connect(_on_damaged)
	var thrust_stream := Sfx.get_stream("thrust")
	if thrust_stream:
		_thrust_audio = AudioStreamPlayer.new()
		_thrust_audio.stream = thrust_stream
		_thrust_audio.volume_db = -10.0
		add_child(_thrust_audio)


func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _unhandled_input(event: InputEvent) -> void:
	if input_blocked:
		return
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if event is InputEventMouseMotion and captured:
		yaw -= event.relative.x * mouse_sensitivity
		var vertical: float = -event.relative.y if invert_y else event.relative.y
		pitch = clampf(pitch - vertical * mouse_sensitivity, -1.5, 1.5)
		_flick += event.relative
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if captured else Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseButton and event.pressed and not captured:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseButton and event.pressed \
			and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var count := actor.weapons.size()
		if count > 1:
			var step := 1 if event.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1
			_pending_switch = posmod(actor.active_weapon_index + step, count)
	elif event.is_action_pressed("toggle_view"):
		toggle_view()
	elif event.is_action_pressed("check_wrist"):
		wrist_raised = not wrist_raised
	elif event.is_action_pressed("melee_control"):
		toggle_stance_control()
	elif event.is_action_pressed("sign_out"):
		sign_out_requested.emit()
	elif event.is_action_pressed("redeploy") and is_instance_valid(actor) and actor.is_dead:
		redeploy_requested.emit()
	elif event is InputEventKey and event.pressed and not event.echo and is_instance_valid(actor) \
			and actor.is_dead and event.keycode >= KEY_1 and event.keycode <= KEY_9:
		drop_requested.emit(event.keycode - KEY_1)


func toggle_view() -> void:
	if is_riding():
		ride_view = ViewMode.THIRD if ride_view == ViewMode.FIRST else ViewMode.FIRST
	else:
		view_mode = ViewMode.THIRD if view_mode == ViewMode.FIRST else ViewMode.FIRST
	actor.notice.emit("Camera: %s" % VIEW_NAMES[active_view()])


func is_riding() -> bool:
	return actor != null and actor.vehicle != null


## The view in use right now: the riding view on a vehicle, otherwise view_mode.
func active_view() -> int:
	return ride_view if is_riding() else view_mode


## Turns recent mouse movement into a melee stance: a flick left or right
## picks that side, a flick up picks overhead. Anything else keeps `current`.
static func stance_from_flick(flick: Vector2, current: int, threshold: float) -> int:
	if flick.length() < threshold:
		return current
	if absf(flick.x) >= absf(flick.y):
		return MeleeWeapon.Dir.LEFT if flick.x < 0.0 else MeleeWeapon.Dir.RIGHT
	if flick.y < 0.0:
		return MeleeWeapon.Dir.OVERHEAD
	return current


## Turns the movement keys into a melee stance: strafing left or right picks
## that side, moving forward picks overhead. Standing still or backing up
## keeps `current`.
static func stance_from_move(move: Vector2, current: int) -> int:
	if absf(move.x) > 0.5 and absf(move.x) >= absf(move.y):
		return MeleeWeapon.Dir.LEFT if move.x < 0.0 else MeleeWeapon.Dir.RIGHT
	if move.y > 0.5:
		return MeleeWeapon.Dir.OVERHEAD
	return current


func toggle_stance_control() -> void:
	stance_control = StanceControl.MOVE if stance_control == StanceControl.MOUSE else StanceControl.MOUSE
	Profile.melee_control = "move" if stance_control == StanceControl.MOVE else "mouse"
	Profile.save()
	actor.notice.emit("Melee side: %s" % STANCE_CONTROL_NAMES[stance_control])


func _physics_process(delta: float) -> void:
	if actor == null or not is_instance_valid(actor) or actor.is_dead:
		return
	var cmd := actor.cmd
	cmd.clear_one_shots()
	if input_blocked:
		# Hands on the phone: let go of everything, keep facing the same way.
		cmd.move = Vector2.ZERO
		cmd.sprint = false
		cmd.jump = false
		cmd.primary = false
		cmd.secondary = false
		cmd.switch_weapon = -1
		return
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	cmd.yaw = yaw
	cmd.pitch = pitch
	cmd.move = Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_back", "move_forward"))
	if stance_control == StanceControl.MOVE:
		stance = stance_from_move(cmd.move, stance)
	else:
		stance = stance_from_flick(_flick, stance, flick_threshold)
	_flick *= exp(-flick_decay * delta)
	cmd.stance = stance
	cmd.sprint = Input.is_action_pressed("sprint")
	cmd.jump = Input.is_action_pressed("jump")
	cmd.jump_pressed = Input.is_action_just_pressed("jump")
	cmd.dash = Input.is_action_just_pressed("dash")
	cmd.slide = Input.is_action_just_pressed("slide")
	if cmd.dash and actor.stamina >= actor.dash_stamina:
		Sfx.play("dash", null, -6.0)
	cmd.primary = captured and Input.is_action_pressed("fire")
	cmd.primary_pressed = captured and Input.is_action_just_pressed("fire")
	cmd.secondary = captured and Input.is_action_pressed("alt_fire")
	cmd.secondary_pressed = captured and Input.is_action_just_pressed("alt_fire")
	cmd.tertiary_pressed = captured and Input.is_action_just_pressed("heavy")
	cmd.reload_pressed = Input.is_action_just_pressed("reload")
	cmd.interact_pressed = Input.is_action_just_pressed("interact")
	cmd.heal_pressed = Input.is_action_just_pressed("heal")
	cmd.ability_pressed = captured and Input.is_action_just_pressed("ability")
	if Input.is_action_just_pressed("weapon_1"):
		cmd.switch_weapon = 0
	elif Input.is_action_just_pressed("weapon_2"):
		cmd.switch_weapon = 1
	elif Input.is_action_just_pressed("holster"):
		# Put the weapon away, or draw the one last put away. Sent as an
		# index, not a toggle, so a repeated or late packet lands the same.
		if actor.get_active_weapon():
			cmd.switch_weapon = ActorCommand.HOLSTER
		elif not actor.weapons.is_empty():
			cmd.switch_weapon = clampi(actor.last_drawn, 0, actor.weapons.size() - 1)
	elif _pending_switch >= 0:
		cmd.switch_weapon = _pending_switch
	_pending_switch = -1
	cmd.aim_dir = _compute_aim_dir()


func _process(delta: float) -> void:
	if actor == null or not is_instance_valid(actor):
		return
	var weapon := actor.get_active_weapon()
	var aiming := weapon != null and weapon.is_aiming()
	var target_dist := 0.0
	if _wants_third_person():
		var far := ride_distance if is_riding() else third_person_distance
		target_dist = third_person_aim_distance if aiming else far
	_cam_dist = lerpf(_cam_dist, target_dist, 1.0 - exp(-12.0 * delta))
	if absf(_cam_dist - target_dist) < 0.01:
		_cam_dist = target_dist

	var look := Basis.from_euler(Vector3(pitch, yaw, 0.0))
	var pivot := actor.get_eye_position()
	var t := minf(_cam_dist / third_person_distance, 1.0)
	var desired := pivot + look * Vector3(0.6 * t, 0.3 * t, _cam_dist)
	if _cam_dist > 0.05:
		# Pull the camera in when a wall is in the way.
		var query := PhysicsRayQueryParameters3D.create(pivot, desired, Actor.LAYER_WORLD)
		var hit := actor.get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			desired = pivot + (hit.position - pivot) * 0.85
	camera.global_transform = Transform3D(look, desired)
	camera.fov = lerpf(camera.fov, ads_fov if aiming else wanted_base_fov(), 1.0 - exp(-14.0 * delta))
	if _thrust_audio:
		var thrusting := actor.flight.is_thrusting and not actor.is_dead
		if thrusting and not _thrust_audio.playing:
			_thrust_audio.play()
		elif not thrusting and _thrust_audio.playing:
			_thrust_audio.stop()
	var first_person := not actor.is_dead and pivot.distance_to(desired) <= 0.7
	var for_mirror := first_person and body_layer > 0
	if actor.body_mesh:
		actor.body_mesh.visible = not first_person or for_mirror
	camera.cull_mask = 0xFFFFF & ~(1 << (body_layer - 1)) if for_mirror else 0xFFFFF
	# In first-person the weapon is held in front of the camera; otherwise it
	# rests on the body, where the Actor poses it. In front of a mirror the
	# hands are on the phone, so it rests on the body there too.
	first_person = first_person and not for_mirror
	actor.hand_override = first_person
	if first_person:
		actor.hand.global_transform = camera.global_transform * Transform3D(Basis.IDENTITY, FIRST_PERSON_HAND)


## Each shot kicks the view up and a little sideways. The player pulls down to
## hold a spray on target.
func _on_gun_fired(_from: Vector3, _to: Vector3, gun: Gun) -> void:
	var scale := 0.6 if gun.is_aiming() else 1.0
	pitch = clampf(pitch + deg_to_rad(gun.recoil_kick_deg) * scale, -1.5, 1.5)
	yaw += deg_to_rad(_rng.randf_range(-gun.recoil_side_deg, gun.recoil_side_deg)) * scale


func _on_hit_confirmed(_target: Actor, info: DamageInfo, lethal: bool) -> void:
	if lethal:
		Sfx.play("kill")
	elif info.parried or info.blocked:
		Sfx.play("block", null, -6.0)
	else:
		Sfx.play("hit")


func _on_damaged(_info: DamageInfo) -> void:
	Sfx.play("hurt")


## The resting field of view for the view in use.
func wanted_base_fov() -> float:
	return base_fov_third if _wants_third_person() else base_fov


func is_third_person() -> bool:
	return _cam_dist > 0.5


func _wants_third_person() -> bool:
	return actor.is_dead or active_view() == ViewMode.THIRD


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
