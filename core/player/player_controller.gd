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

## The player threw the toy vehicle in their hand.
signal toy_throw_requested(item_id: String)
## The player asked to pack the vehicle they are looking at onto the watch.
signal pack_requested

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
const VehicleScript := preload("res://core/vehicle/vehicle.gd")
## Where a toy vehicle sits in the hand, and how big it is drawn there next
## to a thrown toy (it is close to the eye in first person).
const TOY_IN_HAND := Vector3(-0.08, 0.0, 0.1)
const TOY_HAND_SIZE := 0.55
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
## Extra distance between the eye and an optic's own eye point (its "Sight"
## marker) when looking through it in first person, in meters.
var eye_relief := 0.0
## True while looking through an optic in first person: the HUD hides its
## crosshair, since the optic's own reticle is in the middle of the view.
var sighted := false
var _sight_blend := 0.0
## How far the mouse has to move, in pixels, to count as a stance flick.
var flick_threshold := 45.0
## How quickly old mouse movement stops counting toward a flick.
var flick_decay := 9.0
var stance := 0
var stance_control := StanceControl.MOUSE

## The toy vehicle in the hand (an item id off the watch), or "". While one
## is held the weapon is put away: fire throws it, aim puts it back.
var held_toy := ""

var yaw := 0.0
var pitch := 0.0
## Which toy on the raised watch is picked out, counting from 0.
var watch_index := 0
var _toy_node: Node3D
var _cam_dist := 0.0
var _pending_switch := -1
## The zoom level asked of a helmet with binoculars. The visor key steps it.
var _visor_level := 0
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
		# Zoomed in (a scope or binoculars), the mouse turns the view less, so
		# a target moves across the screen at the same speed as without it.
		var turn := mouse_sensitivity * _zoom_scale()
		yaw -= event.relative.x * turn
		var vertical: float = -event.relative.y if invert_y else event.relative.y
		pitch = clampf(pitch - vertical * turn, -1.5, 1.5)
		_flick += event.relative
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if captured else Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseButton and event.pressed and not captured:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseButton and event.pressed \
			and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		scroll(1 if event.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1)
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


## The toy vehicles on the player's watch (item ids), as the world last said.
func watch_toys() -> Array[String]:
	var raid := Raid.of(actor) if actor != null and is_instance_valid(actor) else null
	return raid.stowed_for(actor) if raid != null else ([] as Array[String])


## The vehicle the raised watch would pack: the one being looked at, within
## reach, with nobody on it. Null with the watch down or a toy in the hand.
func pack_target() -> Node3D:
	if not wrist_raised or held_toy != "" or actor == null or not is_instance_valid(actor) \
			or actor.is_dead or is_riding():
		return null
	var seat := actor.find_interactable()
	var found: Variant = seat.get("vehicle") if seat != null else null
	return found if found is Node3D and found.get("rider") == null else null


## True while the watch is up with toy vehicles on it to pick from: the wheel
## turns through them and fire takes the picked one into the hand.
func is_browsing_toys() -> bool:
	return wrist_raised and held_toy == "" and actor != null and is_instance_valid(actor) \
			and not actor.is_dead and not is_riding() and not watch_toys().is_empty()


## Fire with the watch up: packs the vehicle being looked at onto the watch,
## or else takes the picked toy into the hand. False if the watch had no use
## for the click, and it is an ordinary shot.
func click_watch() -> bool:
	if pack_target() != null:
		pack_requested.emit()
		return true
	if is_browsing_toys():
		take_picked_toy()
		return true
	return false


## The mouse wheel: the next weapon, or with the watch up, the next toy on it.
func scroll(step: int) -> void:
	if is_browsing_toys():
		watch_index = posmod(watch_index + step, watch_toys().size())
	else:
		_pending_switch = actor.cycle_weapon_index(step)


## Takes the picked toy off the raised watch, and lowers the wrist to throw.
func take_picked_toy() -> void:
	var toys := watch_toys()
	if toys.is_empty():
		return
	watch_index = clampi(watch_index, 0, toys.size() - 1)
	hold_toy(toys[watch_index])
	if held_toy != "":
		wrist_raised = false


## Takes the toy `item_id` off the watch into the hand ("" puts it back).
func hold_toy(item_id: String) -> void:
	if item_id != "" and (item_id not in watch_toys() or actor.is_dead or is_riding()):
		item_id = ""
	if item_id == held_toy:
		return
	held_toy = item_id
	if item_id != "":
		actor.notice.emit("%s in hand. Fire to throw it, aim to put it back" % ItemDB.item_name(item_id))


## Throws the toy in the hand. The world decides whether it leaves the hand.
func throw_held_toy() -> void:
	if held_toy == "":
		return
	var id := held_toy
	held_toy = ""
	toy_throw_requested.emit(id)


## Keeps the toy model in the hand in step with `held_toy`.
func _show_held_toy() -> void:
	var shown: String = _toy_node.get_meta("display_item", "") if _toy_node != null else ""
	if _toy_node != null:
		# Close to the eye in first person it is drawn smaller.
		_toy_node.scale = Vector3.ONE * VehicleScript.TOY_SCALE * (1.0 if is_third_person() else TOY_HAND_SIZE)
	if shown == held_toy:
		return
	if _toy_node != null:
		_toy_node.queue_free()
		_toy_node = null
	if held_toy != "":
		_toy_node = VehicleScript.toy_model(held_toy)
		_toy_node.position = TOY_IN_HAND
		_toy_node.rotation = Vector3(0.0, -1.2, 0.0)
		actor.hand.add_child(_toy_node)
		for weapon in actor.weapons:
			if weapon.visual:
				weapon.visual.visible = false
	else:
		actor._refresh_weapon_visuals()


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
		cmd.descend = false
		cmd.roll = 0
		cmd.primary = false
		cmd.secondary = false
		cmd.switch_weapon = -1
		_visor_level = 0
		cmd.visor_level = 0
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
	cmd.descend = Input.is_action_pressed("slide")
	cmd.roll = int(Input.is_action_pressed("roll_right")) - int(Input.is_action_pressed("roll_left"))
	if cmd.dash and actor.stamina >= actor.dash_stamina:
		Sfx.play("dash", null, -6.0)
	cmd.primary = captured and Input.is_action_pressed("fire")
	cmd.primary_pressed = captured and Input.is_action_just_pressed("fire")
	cmd.secondary = captured and Input.is_action_pressed("alt_fire")
	cmd.secondary_pressed = captured and Input.is_action_just_pressed("alt_fire")
	cmd.tertiary_pressed = captured and Input.is_action_just_pressed("heavy")
	if held_toy != "":
		_use_toy_hand(cmd)
	elif is_browsing_toys() or pack_target() != null:
		# With the watch up and something for it to do, fire works the watch.
		if cmd.primary_pressed:
			click_watch()
		cmd.primary = false
		cmd.primary_pressed = false
	cmd.reload_pressed = Input.is_action_just_pressed("reload")
	cmd.interact_pressed = Input.is_action_just_pressed("interact")
	cmd.heal_pressed = Input.is_action_just_pressed("heal")
	cmd.ability_pressed = captured and Input.is_action_just_pressed("ability")
	cmd.visor_pressed = captured and Input.is_action_just_pressed("visor")
	if cmd.visor_pressed:
		_visor_level = next_visor_level(actor.visor, _visor_level)
	cmd.visor_level = _visor_level
	var key_slot := -1
	for n in range(1, 5):
		if Input.is_action_just_pressed("weapon_%d" % n):
			key_slot = actor.weapon_for_key(n)
	if key_slot >= 0:
		cmd.switch_weapon = key_slot
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


## With a toy in the hand the weapon is away: fire throws, aim puts it back.
func _use_toy_hand(cmd: ActorCommand) -> void:
	if is_riding() or held_toy not in watch_toys():
		held_toy = ""
	elif cmd.primary_pressed:
		throw_held_toy()
	elif cmd.secondary_pressed:
		held_toy = ""
	cmd.primary = false
	cmd.primary_pressed = false
	cmd.secondary = false
	cmd.secondary_pressed = false
	cmd.tertiary_pressed = false
	cmd.switch_weapon = -1
	_pending_switch = -1


func _process(delta: float) -> void:
	if actor == null or not is_instance_valid(actor):
		return
	if actor.is_dead:
		held_toy = ""
	_show_held_toy()
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
	var fov := aim_fov(weapon) if aiming else wanted_base_fov()
	if _zoom() > 1.0:
		fov = zoomed_fov(wanted_base_fov(), _zoom())
	camera.fov = lerpf(camera.fov, fov, 1.0 - exp(-14.0 * delta))
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
	var sight := _sight_of(weapon) if first_person else null
	_sight_blend = move_toward(_sight_blend, 1.0 if aiming and sight != null else 0.0, delta * 7.0)
	sighted = _sight_blend > 0.9
	if first_person:
		var hand_at := FIRST_PERSON_HAND
		if sight != null and _sight_blend > 0.0:
			# Raise the gun so its optic's eye point is at the eye: the view
			# then looks straight down the sight.
			var in_hand := actor.hand.global_transform.affine_inverse() * sight.global_transform.origin
			var lined_up := Vector3(0, 0, -eye_relief) - in_hand
			hand_at = FIRST_PERSON_HAND.lerp(lined_up, _sight_blend)
		actor.hand.global_transform = camera.global_transform * Transform3D(Basis.IDENTITY, hand_at)


## The field of view while aiming `weapon`: optics zoom further in.
func aim_fov(weapon: Weapon) -> float:
	return ads_fov / maxf(1.0, weapon.aim_zoom() if weapon else 1.0)


## The sight line marker of the optic on `weapon`, or null for plain sights.
func _sight_of(weapon: Weapon) -> Node3D:
	if weapon == null or weapon.visual == null:
		return null
	return weapon.visual.get_node_or_null("Attachments/optic/Sight") as Node3D


## How much the mouse turns the view right now, relative to the resting view.
func _zoom_scale() -> float:
	if camera == null:
		return 1.0
	return clampf(tan(deg_to_rad(camera.fov) * 0.5) / tan(deg_to_rad(wanted_base_fov()) * 0.5), 0.1, 1.0)


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


## The visor level the visor key moves to from `level`: up through the
## helmet's levels (zoom strengths, thermal on) and back to off. A helmet
## with none stays at 0.
static func next_visor_level(visor: Visor, level: int) -> int:
	if visor == null or visor.levels() <= 0:
		return 0
	return (level + 1) % (visor.levels() + 1)


## The field of view that makes things look `factor` times closer than at `fov`.
static func zoomed_fov(fov: float, factor: float) -> float:
	return rad_to_deg(2.0 * atan(tan(deg_to_rad(fov) * 0.5) / maxf(factor, 1.0)))


## How much the helmet's binoculars magnify right now: 1 when they are down.
func _zoom() -> float:
	if actor == null or not is_instance_valid(actor):
		return 1.0
	return actor.visor.zoom_factor()


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
