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
const FirstPersonArms := preload("res://core/visual/first_person_arms.gd")
## Where a toy vehicle sits in the hand, and how big it is drawn there next
## to a thrown toy (it is close to the eye in first person).
const TOY_IN_HAND := Vector3(-0.08, 0.0, 0.1)
const TOY_HAND_SIZE := 0.55
const FIRST_PERSON_HAND := Vector3(0.16, -0.19, -0.3)

var actor: Actor
var camera: Camera3D
var view_mode := ViewMode.FIRST
var mouse_sensitivity := 0.0022
var invert_y := false
## Set while the phone is open: the character stands still and the mouse is
## left alone, so you can tap and type.
var input_blocked := false
## Set while the phone is out (`Main`): the character holds it up, which
## everyone else sees (`ActorCommand.phone`), and the weapon is put away in
## the view until the phone is.
var phone_out := false
## Set while a mirror stands in front of you (1-20, 0 for none). In first
## person your body stays drawn on this render layer, which this camera leaves
## out, so the mirror's camera can still show it.
var body_layer := 0
## How far behind the eyes the third-person camera sits, in meters: a view
## over the right shoulder (the phone's "Camera distance" setting). Aiming
## moves in to `aim_distance_ratio` of it.
var third_person_distance := 2.0
var aim_distance_ratio := 0.6
## A vehicle is bigger than a person: riding sits this much further back.
var ride_extra_distance := 1.6
## The view used while riding. It starts in third-person and V switches it,
## separately from the on-foot view, which comes back when you get off.
var ride_view := ViewMode.THIRD
var base_fov := 80.0
## First person moves the held weapon by the actor's `ActionPose`, the same
## state that moves the model's arm third person: melee reach is scaled by
## `first_person_reach` (the hand is nearer the eye than a shoulder is) and
## the shoulder turn swings the hand round the eye by `first_person_turn` of
## it. A switch drops the hand toward the holster's side to
## `first_person_stow` (camera space, x taken from the holster) and tips it
## by `first_person_stow_tilt`, out of view.
var first_person_reach := 0.45
var first_person_turn := 0.35
## The nearest the hand comes to the eye (m, straight ahead) and the furthest
## it goes to either side, in first person.
var first_person_near := 0.4
var first_person_side := 0.3
## A cocked hand is kept at least this far off the middle of the view (as
## sideways over ahead), so a windup's arm comes in from the edge instead of
## covering what you are about to hit. It fades out through the swing.
var first_person_clear := 0.5
var first_person_stow := Vector3(0.0, -0.7, -0.4)
var first_person_stow_tilt := Vector3(-1.1, 0.0, 0.0)
## Speed widens the view a little, so a boost, a dive or a bike reads as
## fast: up to `speed_fov` degrees more, from a sprint's speed up to
## `speed_fov_at` m/s. Never while aiming or zoomed.
var speed_fov := 9.0
var speed_fov_at := 26.0
## A landing dips the view by the speed you came down at (m per m/s, up to
## `land_dip_max` m) and springs back.
var land_dip := 0.016
var land_dip_max := 0.25
## Recoil. A shot's kick reaches the view over a few frames, not in one
## (`recoil_snap`, per second). Once the trigger rests for
## `recoil_settle_delay`, the view comes back down by `recoil_return` of the
## kick you did not pull down against yourself (`recoil_settle`, per second),
## so paced shots return to the aim point and a spray you fight stays put.
var recoil_snap := 45.0
var recoil_return := 1.0
var recoil_settle_delay := 0.1
var recoil_settle := 9.0
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
## The icon open on the raised watch's card (`Hud.Wrist.SLOTS`), counting
## from 0. The mouse wheel moves it across the card, one icon a notch, and on
## the vehicle icon it turns through the toys before moving on. The HUD sets
## it to the icon it would open on its own until the wheel turns
## (`watch_focus_moved`). The mouse only looks, so the view never drifts
## while you read the card. View only.
var watch_focus: int = Hud.Wrist.SLOTS.find("vehicle")
var watch_focus_moved := false
var _toy_node: Node3D
var _cam_dist := 0.0
var _pending_switch := -1
## The zoom level asked of a helmet with binoculars. The visor key steps it.
var _visor_level := 0
var _flick := Vector2.ZERO
var _rng := RandomNumberGenerator.new()
var _thrust_audio: AudioStreamPlayer
## Kick still on its way to the view (x pitch, y yaw, radians), the kick the
## view is holding that has yet to settle back, and seconds since a shot.
var _kick_coming := Vector2.ZERO
var _kick_held := 0.0
var _since_shot := 99.0
## The landing dip: how far the view is pushed down, and its speed.
var _dip := 0.0
var _dip_speed := 0.0
## A blade strike that connects jolts the view the way it swung, a parry
## throws it back, and a cut taken flinches it. View only: it never moves the
## aim (`pitch`, `yaw`), and springs back on its own.
var melee_kick_deg := 1.4
var parry_kick_deg := 3.0
var flinch_deg := 1.2
var _shake := Vector2.ZERO
var _shake_speed := Vector2.ZERO
var _speed_fov_now := 0.0
## Your own arms in first person, and the look they were built for.
var _arms: Node3D
var _arms_look := {}
var _arms_failed := false


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
		var blade := weapon as MeleeWeapon
		if blade:
			blade.contact.connect(_on_blade_contact.bind(blade))
	actor.hit_confirmed.connect(_on_hit_confirmed)
	actor.health.damaged.connect(_on_damaged)
	actor.landed.connect(_on_landed)
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
		# Pulling down against a spray: that much kick is yours, not the
		# gun's, and will not be given back.
		_kick_held = maxf(0.0, _kick_held - maxf(vertical * turn, 0.0))
		_flick += event.relative
	elif event is InputEventMouseButton and event.pressed and not captured:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseButton and event.pressed \
			and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		scroll(1 if event.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1)
	elif event.is_action_pressed("toggle_view"):
		toggle_view()
	elif event.is_action_pressed("check_wrist"):
		wrist_raised = not wrist_raised
		watch_focus_moved = false
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


## True while the watch is up with toy vehicles on it to pick from.
func is_browsing_toys() -> bool:
	return wrist_raised and held_toy == "" and actor != null and is_instance_valid(actor) \
			and not actor.is_dead and not is_riding() and not watch_toys().is_empty()


## True while the card is open on the vehicle icon with toys to pick from:
## the wheel turns through them and fire takes the picked one into the hand.
## Before the wheel turns the card opens on the vehicles on its own.
func is_picking_toys() -> bool:
	return is_browsing_toys() and (not watch_focus_moved or watch_focus == Hud.Wrist.SLOTS.find("vehicle"))


## Fire with the watch up: packs the vehicle being looked at onto the watch,
## or else takes the picked toy into the hand. False if the watch had no use
## for the click, and it is an ordinary shot.
func click_watch() -> bool:
	if pack_target() != null:
		pack_requested.emit()
		return true
	if is_picking_toys():
		take_picked_toy()
		return true
	return false


## The mouse wheel: the next weapon, or with the watch up, the next icon on
## its card (`step` 1 is down the wheel, to the right). With the watch up the
## wheel never switches weapons.
func scroll(step: int) -> void:
	if is_watch_up():
		step_watch(step)
	else:
		_pending_switch = actor.cycle_weapon_index(step)


## True while the raised watch takes the wheel: up, and you are alive.
func is_watch_up() -> bool:
	return wrist_raised and actor != null and is_instance_valid(actor) and not actor.is_dead


## Moves the watch card's open icon `step` along (`Hud.Wrist.SLOTS`). On the
## vehicle icon with toys to pick, the wheel turns through them first, and
## steps off the icon past the first or last toy. Stops at the card's ends.
func step_watch(step: int) -> void:
	if step == 0:
		return
	var count: int = Hud.Wrist.SLOTS.size()
	var vehicle: int = Hud.Wrist.SLOTS.find("vehicle")
	watch_focus = clampi(watch_focus, 0, count - 1)
	watch_focus_moved = true
	var toys := watch_toys().size() if is_browsing_toys() else 0
	if watch_focus == vehicle and toys > 1:
		var next := watch_index + signi(step)
		if next >= 0 and next < toys:
			watch_index = next
			return
	var was := watch_focus
	watch_focus = clampi(watch_focus + signi(step), 0, count - 1)
	# Coming onto the vehicles from the right starts on the last toy.
	if watch_focus == vehicle and was != vehicle and toys > 0:
		watch_index = 0 if step > 0 else toys - 1


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
	cmd.phone = phone_out
	if input_blocked:
		# Hands on the phone: let go of everything, keep facing the same way.
		cmd.move = Vector2.ZERO
		cmd.sprint = false
		cmd.jump = false
		cmd.descend = false
		cmd.free_look = false
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
	cmd.sprint_pressed = Input.is_action_just_pressed("sprint")
	cmd.jump = Input.is_action_pressed("jump")
	cmd.jump_pressed = Input.is_action_just_pressed("jump")
	cmd.dash = Input.is_action_just_pressed("dash")
	cmd.slide = Input.is_action_just_pressed("slide")
	cmd.descend = Input.is_action_pressed("slide")
	cmd.free_look = Input.is_action_pressed("free_look")
	if cmd.dash and actor.stamina >= actor.dash_stamina:
		Sfx.play("dash", null, -6.0)
	elif cmd.sprint_pressed and not actor.is_on_floor() and actor.flight.enabled and not actor.flight.overheated:
		Sfx.play("dash", null, -6.0)
	cmd.primary = captured and Input.is_action_pressed("fire")
	cmd.primary_pressed = captured and Input.is_action_just_pressed("fire")
	cmd.secondary = captured and Input.is_action_pressed("alt_fire")
	cmd.secondary_pressed = captured and Input.is_action_just_pressed("alt_fire")
	if held_toy != "":
		_use_toy_hand(cmd)
	elif is_picking_toys() or pack_target() != null:
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
	cmd.watch_up = wrist_raised and not actor.is_dead
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
		target_dist = view_distance(aiming)
	_cam_dist = lerpf(_cam_dist, target_dist, 1.0 - exp(-12.0 * delta))
	if absf(_cam_dist - target_dist) < 0.01:
		_cam_dist = target_dist

	_update_recoil(delta)
	_update_dip(delta)
	_update_shake(delta)
	var look := Basis.from_euler(Vector3(pitch + _shake.y, yaw + _shake.x, 0.0))
	var pivot := actor.get_eye_position() - Vector3(0.0, _dip, 0.0)
	var t := minf(_cam_dist / third_person_distance, 1.0)
	var desired := pivot + look * Vector3(0.6 * t, 0.3 * t, _cam_dist)
	if _cam_dist > 0.05:
		# Pull the camera in when a wall is in the way.
		var query := PhysicsRayQueryParameters3D.create(pivot, desired, Actor.LAYER_WORLD)
		var hit := actor.get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			desired = pivot + (hit.position - pivot) * 0.85
	camera.global_transform = Transform3D(look, desired)
	var speeding := 0.0 if aiming or _zoom() > 1.0 else speed_fov_for(_view_speed())
	_speed_fov_now = lerpf(_speed_fov_now, speeding, 1.0 - exp(-4.0 * delta))
	var fov := aim_fov(weapon) if aiming else wanted_base_fov() + _speed_fov_now
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
	first_person = first_person and not for_mirror and not phone_out
	actor.hand_override = first_person
	var sight := _sight_of(weapon) if first_person else null
	_sight_blend = move_toward(_sight_blend, 1.0 if aiming and sight != null else 0.0, delta * 7.0)
	sighted = _sight_blend > 0.9
	if first_person:
		var pose := ActionPose.of(actor)
		pose.advance(delta)
		var hold := first_person_hold(pose)
		if sight != null and _sight_blend > 0.0:
			# Raise the gun so its optic's eye point is at the eye: the view
			# then looks straight down the sight.
			var in_hand := actor.hand.global_transform.affine_inverse() * sight.global_transform.origin
			var lined_up := Vector3(0, 0, -eye_relief) - in_hand
			hold = hold.interpolate_with(Transform3D(Basis.IDENTITY, lined_up), _sight_blend)
		actor.hand.global_transform = camera.global_transform * hold
		actor.hand.set_meta("shown", actor.hand.global_transform)
	_update_arms(first_person)


## Shows your own arms holding the weapon in first person (when the art
## layer is on and the character has arms to copy).
func _update_arms(first_person: bool) -> void:
	if not Look.enabled or not actor.has_node("Skin"):
		return
	var wanted: Dictionary = {"skin": actor.get_meta("look", Look.DEFAULT_SKIN), "appearance": actor.get_meta("appearance", {})}
	if _arms != null and wanted != _arms_look:
		_arms.queue_free()
		_arms = null
		_arms_failed = false
	if _arms == null and not _arms_failed:
		_arms_look = wanted
		_arms = FirstPersonArms.new()
		_arms.name = "FirstPersonArms"
		_arms.look = Look
		_arms.actor = actor
		_arms.camera = camera
		camera.add_child(_arms)
		if not _arms.build(wanted["skin"], wanted["appearance"]):
			_arms.queue_free()
			_arms = null
			_arms_failed = true
			return
	if _arms != null:
		_arms.update(first_person, ActionPose.of(actor).watch, held_toy != "")


## True while your own arms are drawn in first person.
func has_arms() -> bool:
	return _arms != null and is_instance_valid(_arms)


## Where the weapon hand goes in first person, in the camera's space: the
## resting hold moved by the same shared pose the third-person arm follows
## (melee reach and shoulder turn, a reload, the low ready, a switch).
func first_person_hold(pose: ActionPose) -> Transform3D:
	var at := FIRST_PERSON_HAND
	var basis := Basis.IDENTITY
	if pose == null:
		return Transform3D(basis, at)
	at += pose.reach * (first_person_reach * pose.reach_weight)
	var gun := pose.gun_offset(true)
	at += gun.origin
	basis = gun.basis
	var swing := Basis(Vector3.UP, pose.turn.x * first_person_turn) * Basis(Vector3.RIGHT, pose.turn.y * first_person_turn)
	at = swing * at
	basis = swing * basis
	# However a pose moves it, the hand stays far enough out in front that
	# the arm holding it does not fill the view.
	if pose.reach_weight > 0.0:
		at.z = lerpf(at.z, minf(at.z, -first_person_near), pose.reach_weight)
		at.x = lerpf(at.x, clampf(at.x, -first_person_side, first_person_side), pose.reach_weight)
		var off := Vector2(at.x, at.y)
		var clear := first_person_clear * -at.z
		if off.length() < clear:
			var way := off.normalized() if off.length() > 0.03 else Vector2(0.8, 0.6)
			var w := pose.reach_weight * pose.elbow_raise
			at.x = lerpf(at.x, way.x * clear, w)
			at.y = lerpf(at.y, way.y * clear, w)
	if pose.switch_weight > 0.0:
		var side := clampf(pose.switch_point.x, -0.45, 0.45)
		var stow := Vector3(side, first_person_stow.y, first_person_stow.z)
		var tip := Basis.from_euler(first_person_stow_tilt + Vector3(0.0, 0.0, -0.5 * side))
		var w := smoothstep(0.0, 1.0, pose.switch_weight)
		at = at.lerp(stow, w)
		basis = basis.slerp(tip, w)
	return Transform3D(basis, at)


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
## hold a spray on target. The kick arrives and settles in `_update_recoil`.
func _on_gun_fired(_from: Vector3, _to: Vector3, gun: Gun) -> void:
	var scale := 0.6 if gun.is_aiming() else 1.0
	_kick_coming.x += deg_to_rad(gun.recoil_kick_deg) * scale
	_kick_coming.y += deg_to_rad(_rng.randf_range(-gun.recoil_side_deg, gun.recoil_side_deg)) * scale
	_since_shot = 0.0


## Moves the kick of recent shots into the view, and lets the view settle
## back down once the trigger rests.
func _update_recoil(delta: float) -> void:
	_since_shot += delta
	if _kick_coming.length() > 0.00001:
		var step := _kick_coming * (1.0 - exp(-recoil_snap * delta))
		_kick_coming -= step
		var before := pitch
		pitch = clampf(pitch + step.x, -1.5, 1.5)
		yaw += step.y
		_kick_held += (pitch - before) * recoil_return
	else:
		_kick_coming = Vector2.ZERO
	if _since_shot >= recoil_settle_delay and _kick_held > 0.0:
		var back := _kick_held * (1.0 - exp(-recoil_settle * delta)) if _kick_held > 0.0005 else _kick_held
		_kick_held -= back
		pitch = clampf(pitch - back, -1.5, 1.5)


## The view dips on a landing and springs back.
func _on_landed(impact_speed: float) -> void:
	_dip_speed += minf(impact_speed * land_dip, land_dip_max) * 36.0


func _update_dip(delta: float) -> void:
	if is_zero_approx(_dip) and is_zero_approx(_dip_speed):
		return
	# A critically damped spring: down fast, back without a bounce. Stepped
	# in short slices, since one long frame (a hitch, a slow machine) would
	# otherwise throw the spring off and the camera with it.
	var left := delta
	while left > 0.0:
		var step := minf(left, 1.0 / 120.0)
		_dip_speed += (-180.0 * _dip - 26.8 * _dip_speed) * step
		_dip += _dip_speed * step
		left -= step
	if absf(_dip) < 0.0005 and absf(_dip_speed) < 0.005:
		_dip = 0.0
		_dip_speed = 0.0


## How fast the player is travelling, for the view: their ride's speed on a vehicle.
func _view_speed() -> float:
	if actor.vehicle != null:
		return absf(float(actor.vehicle.get("speed")))
	return actor.velocity.length()


## Degrees the view widens at `speed` m/s: none up to a sprint, all of
## `speed_fov` from `speed_fov_at`.
func speed_fov_for(speed: float) -> float:
	return speed_fov * smoothstep(actor.sprint_speed, speed_fov_at, speed)


## The blade reached someone: answer now, before the server's word (which
## still drives the hit marker). The sound and the jolt follow the local
## guess of what their guard did.
func _on_blade_contact(_target: Actor, outcome: String, _at: Vector3, blade: MeleeWeapon) -> void:
	var side := MeleeWeapon._side(blade.attack_dir)
	match outcome:
		"parry":
			Sfx.play("parry", null, -4.0)
			kick_view(Vector2(0.0, deg_to_rad(parry_kick_deg)))
		"block":
			Sfx.play("block")
			kick_view(Vector2(side * 0.5, 0.3) * deg_to_rad(melee_kick_deg))
		_:
			Sfx.play("hit")
			# The view follows through: sideways for a side cut, down for overhead.
			var down := 1.0 if blade.attack_dir == MeleeWeapon.Dir.OVERHEAD else 0.25
			kick_view(Vector2(side, -down) * deg_to_rad(melee_kick_deg))


## Jolts the view by `kick` (yaw, pitch in radians); it springs back.
func kick_view(kick: Vector2) -> void:
	_shake_speed += kick * 30.0


func _update_shake(delta: float) -> void:
	if _shake.is_zero_approx() and _shake_speed.is_zero_approx():
		return
	# A stiff, critically damped spring, like the landing dip.
	_shake_speed += (-400.0 * _shake - 40.0 * _shake_speed) * delta
	_shake += _shake_speed * delta
	if _shake.length() < 0.00005 and _shake_speed.length() < 0.0005:
		_shake = Vector2.ZERO
		_shake_speed = Vector2.ZERO


## How far the view is jolted right now, (yaw, pitch) in radians.
func view_shake() -> Vector2:
	return _shake


func _on_hit_confirmed(_target: Actor, info: DamageInfo, lethal: bool) -> void:
	if lethal:
		Sfx.play("kill")
	elif info.kind == "melee":
		pass  # The blade's contact already answered.
	elif info.parried or info.blocked:
		Sfx.play("block", null, -6.0)
	else:
		Sfx.play("hit")


func _on_damaged(info: DamageInfo) -> void:
	Sfx.play("hurt")
	if info.kind in ["melee", "slam"]:
		kick_view(Vector2(_rng.randf_range(-0.5, 0.5), -1.0) * deg_to_rad(flinch_deg))


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
## How far back the third-person camera wants to be.
func view_distance(aiming: bool) -> float:
	if aiming:
		return third_person_distance * aim_distance_ratio
	return third_person_distance + (ride_extra_distance if is_riding() else 0.0)


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
