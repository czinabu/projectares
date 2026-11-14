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
## The player took a toy vehicle off the watch into their hand, or put it
## back (""). The world shows it in the hand for everyone.
signal toy_hold_requested(item_id: String)
## The player picked a weapon in their pack on the watch: materialize it.
signal summon_requested(item_id: String)
## The watch's store: put weapon `item_id`, the one in hand, back into the pack.
signal store_requested(item_id: String)
## The player pinged where they are looking from the watch.
signal ping_requested
## The watch's portal icon was clicked: open a squad portal to `destination`.
signal portal_requested(destination: String)
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
const VehicleScript := preload("res://core/vehicle/vehicle.gd")
const MirrorScript := preload("res://core/visual/mirror.gd")
const Handheld := preload("res://core/phone/handheld.gd")

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
## Reading the phone in third person (Caleb's call, like the riding view: an
## exception to the camera never moving on its own, made by opening the
## phone): the camera eases in beside the head and looks square onto the
## handheld's screen in the hand (Caleb's pick, so it reads), and eases back
## out when the phone is put away. It stands this far (m) out from the
## screen, along the screen's facing turned this much toward the right
## shoulder and up, so the head stays out of the way. It looks at the same
## device first person reads; nothing floats in front of the view.
var phone_read_distance := 0.55
var phone_read_side := 0.65
var phone_read_lift := 0.25
## How far (0..1) the reading view tips with the phone so its lines read level.
var phone_read_tilt := 1.0
## With the Mirror app up it reads from over the shoulder instead, this far
## back from the eyes (m), out to the right and up, to keep the mirror in view.
var phone_mirror_spot := Vector3(0.65, 0.35, 0.75)
## How far (m) to aim left of the phone, so it sits right of the crosshair.
var phone_read_offset := 0.03
var phone_read_rate := 6.0
## With the Mirror app up the view widens and aims this far (0..1) from the
## phone toward the mirror's glass, so the reflection shows past the phone.
var phone_mirror_fov := 62.0
## While the phone is out the view zooms in on it (Caleb's pick over a
## bigger screen layout), in both views, like aiming down sights: only the
## field of view narrows, the hold and the camera stay put. It zooms until
## the phone stands this share of the view's height, whatever the player's
## field of view setting (Caleb's feedback: at a wide one a fixed zoom left it
## tiny), and never so far that the phone leaves the frame. Not with the
## Mirror app's mirror up, which needs the wide view.
var phone_zoom := 0.6
## How much of the view's half height and width the phone may reach out to.
var phone_zoom_edge := 0.94
var phone_mirror_aim := 0.55
## How far in to the phone the third-person camera is now (0..1).
var phone_read := 0.0
## The eyes drop to the phone in the hand while it is out (radians of view
## pitch), in both views, the same way the model's head bows to it. Only the
## view moves: `pitch`, and so the aim, is left where it was.
var phone_view_pitch := -0.4
## With the Mirror app's mirror up the eyes drop less, to see yourself in it
## over the phone.
var phone_mirror_pitch := -0.2
var _phone_look := 0.0
## The mirror standing in front of you for the phone's Mirror app (`Main`),
## or null; the third-person reading view keeps it in frame.
var phone_mirror: Node3D
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
## True while looking down the sights in first person: the HUD hides its
## crosshair, since the sight (an optic's reticle, or the plain sights) is
## in the middle of the view.
var sighted := false
## A scope (`Gun.scope_lens`) is picture in picture: aimed in first person,
## a second camera renders the magnified view onto its eyepiece's glass and
## the world around the scope stays as it is (Caleb's call: never a black
## screen). How many pixels across that picture is.
var scope_pixels := 640
## How far ahead the scope's camera starts drawing, so the gun and the scope
## itself are never in their own picture.
var scope_near := 0.9
var _scope_view: SubViewport
var _scope_cam: Camera3D
var _scope_mat: ShaderMaterial
## The lens the magnified view is drawn on now, if any.
var _scope_lens: MeshInstance3D
## First person: how far the model's eyes are from the actor's eye point,
## eased so the view never jolts with a step.
var _eye_offset := Vector3.ZERO
## First person: how far the camera sits back from the model's eyes, level
## along the view, in meters (the phone's "Camera pulled back" setting). The
## head is left out of this camera, so it never gets in the way. It eases
## off as the view tips down (gone by `pullback_fade_pitch`), or the camera
## would sit behind the neck and look down onto the shoulders.
var eye_pullback := 0.15
## How far down (radians) the view tips before the pullback is gone.
var pullback_fade_pitch := 0.45
## First person: how far the eyes move ahead, level, looking straight down,
## as a head bowing forward does, so the chest is seen from the front and
## never from over the shoulders.
var look_down_lean := 0.05
## How far the mouse has to move, in pixels, to count as a stance flick.
var flick_threshold := 45.0
## How quickly old mouse movement stops counting toward a flick.
var flick_decay := 9.0
var stance := 0
var stance_control := StanceControl.MOVE

## The toy vehicle in the hand (an item id off the watch), or "". While one
## is held the weapon is put away: fire throws it, aim puts it back.
var held_toy := ""
## Seconds left of looking over what is in the hand (the inspect key),
## sent as the held flag `ActorCommand.inspect` so everyone sees the item
## brought up and turned (`ActionPose.inspect`). Anything you do with your
## hands, sprinting, the watch or the phone stops it early. View only:
## nothing in the simulation reads it.
var inspect_left := 0.0

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
## The icon opened with a click ("" on the main row): only then does the
## wheel turn through what it holds (Caleb's call). A right click closes it.
var watch_open := ""
## Which weapon and which artifact are picked out on the raised watch's
## carousel (`Hud.weapon_entries`, `Hud.artifact_entries`), counting from 0.
var weapon_pick := 0
var artifact_pick := 0
## Which destination is picked out on the watch's portal icon
## (`portal_choices`), counting from 0.
var portal_pick := 0
## The artifact icon was clicked; sent as `artifact_pressed` next command.
var _artifact_click := false
## Seconds left of the throw just made: the hand is busy, so the weapon
## stays put away and takes no input (`ActionPose.toy_throw_time`).
var _toy_busy_left := 0.0
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
	_update_scope(null)


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
		watch_open = ""
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
	if raid != null:
		return raid.stowed_for(actor)
	# At home every vehicle the owner has is on the watch (`HomeBase`).
	var base := HomeBase.of(actor) if actor != null and is_instance_valid(actor) else null
	return base.watch_vehicles() if base != null else ([] as Array[String])


## The vehicle the raised watch would pack: the one being looked at, within
## reach, with nobody on it. Null with the watch down or a toy in the hand.
func pack_target() -> Node3D:
	if not wrist_raised or held_toy != "" or actor == null or not is_instance_valid(actor) \
			or actor.is_dead or is_riding():
		return null
	var seat := actor.find_interactable()
	var found: Variant = seat.get("vehicle") if seat != null else null
	return found if found is Node3D and not found.call("is_occupied") else null


## True while the watch is up with toy vehicles on it to pick from.
func is_browsing_toys() -> bool:
	return wrist_raised and held_toy == "" and actor != null and is_instance_valid(actor) \
			and not actor.is_dead and not is_riding() and not watch_toys().is_empty()


## True while the card is open on the vehicle icon with toys to pick from:
## the wheel turns through them and fire takes the picked one into the hand.
## Before the wheel turns the card opens on the vehicles on its own.
func is_picking_toys() -> bool:
	return is_browsing_toys() and (not watch_focus_moved or watch_focus == Hud.Wrist.SLOTS.find("vehicle")) \
			and _is_open("vehicle")


## True while the wheel has put the card on icon `id` (`Hud.Wrist.SLOTS`).
func is_watch_on(id: String) -> bool:
	return is_watch_up() and watch_focus_moved and watch_focus == Hud.Wrist.SLOTS.find(id)


## True while the card is open on the artifact icon with the attuned artifact
## picked out: fire uses it (`ActorCommand.artifact_pressed`).
func is_on_artifact() -> bool:
	return is_watch_on("artifact") and actor.artifact.enabled and artifact_pick == 0 and _is_open("artifact")


## Where a squad portal from the watch can lead from here
## (`Portal.destinations()`), or none where portals cannot open: anywhere but
## your base or a safe zone.
func portal_choices() -> Array[String]:
	if actor == null or not is_instance_valid(actor):
		return []
	return Portal.choices_for(Raid.of(actor), actor)


## The weapons on the raised watch's carousel (`Hud.weapon_entries`).
func watch_weapons() -> Array[Dictionary]:
	if actor == null or not is_instance_valid(actor):
		return []
	var entries := Hud.weapon_entries(actor)
	# At home the carousel turns on through every weapon the owner has
	# (`HomeBase.watch_weapons`); picking one equips it.
	var base := HomeBase.of(actor) if Raid.of(actor) == null else null
	if base != null:
		for id in base.watch_weapons():
			if not entries.any(func(e: Dictionary) -> bool: return e.id == id):
				entries.append({"id": id, "index": -1})
	return entries


## True while the card is open on the weapon icon with weapons to pick from:
## the wheel turns through them and fire draws or summons the picked one.
func is_picking_weapons() -> bool:
	return is_watch_on("weapon") and not is_riding() and not watch_weapons().is_empty() and _is_open("weapon")


## Fire with the watch up: packs the vehicle being looked at onto the watch,
## takes the picked toy into the hand, draws or summons the picked weapon,
## uses the artifact, or pings. False if the watch had no use for the
## click, and it is an ordinary shot.
func click_watch() -> bool:
	if pack_target() != null:
		pack_requested.emit()
		return true
	# Two levels (Caleb's call): on the main row a click opens an icon that
	# holds several things, and only then does the wheel turn through them.
	var here := focused_watch_icon()
	if watch_open == "" and watch_entries(here) > 1:
		watch_open = here
		watch_focus = Hud.Wrist.SLOTS.find(here)
		watch_focus_moved = true
		return true
	if is_picking_toys():
		take_picked_toy()
		return true
	if is_picking_weapons():
		take_picked_weapon()
		return true
	if is_on_artifact():
		_artifact_click = true
		return true
	if is_watch_on("ping"):
		ping_requested.emit()
		return true
	if is_watch_on("portal") and not portal_choices().is_empty() and _is_open("portal"):
		var choices := portal_choices()
		portal_requested.emit(choices[clampi(portal_pick, 0, choices.size() - 1)])
		wrist_raised = false
		watch_open = ""
		return true
	return false


## True while fire works the raised watch instead of the weapon.
func watch_takes_fire() -> bool:
	return (watch_open == "" and watch_entries(focused_watch_icon()) > 1) or is_picking_toys() or pack_target() != null or is_picking_weapons() or is_on_artifact() \
			or is_watch_on("ping") or is_watch_on("portal")


## Draws the weapon picked on the carousel if it is worn, stores it back
## into the pack if it is the one in hand, or asks the world to materialize
## it out of the pack, and lowers the wrist.
func take_picked_weapon() -> void:
	var entries := watch_weapons()
	if entries.is_empty():
		return
	var entry := entries[clampi(weapon_pick, 0, entries.size() - 1)]
	if int(entry.index) >= 0 and int(entry.index) == actor.active_weapon_index \
			and actor.get_active_weapon() != null and Loadout.summonable(entry.id):
		# The one in hand: put it back into the pack (the summon in reverse).
		store_requested.emit(entry.id)
	elif int(entry.index) >= 0:
		_pending_switch = int(entry.index)
	else:
		summon_requested.emit(entry.id)
	wrist_raised = false
	watch_open = ""


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


## How many things the wheel turns through on icon `id` before stepping on:
## the weapons, the toys or the artifacts carried. 0 for a plain icon.
func watch_entries(id: String) -> int:
	match id:
		"weapon":
			return watch_weapons().size() if not is_riding() else 0
		"vehicle":
			return watch_toys().size() if is_browsing_toys() else 0
		"artifact":
			return Hud.artifact_entries(actor).size()
		"portal":
			return portal_choices().size()
	return 0


func _watch_pick(id: String) -> int:
	match id:
		"weapon":
			return weapon_pick
		"vehicle":
			return watch_index
		"artifact":
			return artifact_pick
		"portal":
			return portal_pick
	return 0


func _set_watch_pick(id: String, pick: int) -> void:
	match id:
		"weapon":
			weapon_pick = pick
		"vehicle":
			watch_index = pick
		"artifact":
			artifact_pick = pick
		"portal":
			portal_pick = pick


## Moves the watch card's open icon `step` along (`Hud.Wrist.SLOTS`), tab
## after tab. On an icon that holds several things (weapons, toys,
## artifacts) the wheel turns through them first, and steps off the icon
## past the first or last. Stops at the card's ends.
func step_watch(step: int) -> void:
	if step == 0:
		return
	var slots: Array = Hud.Wrist.SLOTS
	watch_focus = clampi(watch_focus, 0, slots.size() - 1)
	# An opened icon keeps the wheel until a right click closes it.
	if watch_open != "":
		var held := watch_entries(watch_open)
		if held > 0:
			_set_watch_pick(watch_open, clampi(_watch_pick(watch_open) + signi(step), 0, held - 1))
		return
	if not watch_focus_moved and is_browsing_toys():
		watch_focus = slots.find("vehicle")
	watch_focus_moved = true
	watch_focus = clampi(watch_focus + signi(step), 0, slots.size() - 1)


## The icon the card is on (`Hud.Wrist.SLOTS`): where the wheel put it, or
## before it moved, the vehicles if there are toys to throw.
func focused_watch_icon() -> String:
	if not is_watch_up():
		return ""
	if not watch_focus_moved:
		return "vehicle" if is_browsing_toys() else ""
	return Hud.Wrist.SLOTS[clampi(watch_focus, 0, Hud.Wrist.SLOTS.size() - 1)]


## True if icon `id`'s things can be acted on now: it is opened, or holds
## only one, so a click acts on it straight away.
func _is_open(id: String) -> bool:
	return watch_open == id or watch_entries(id) <= 1


## Right click on the watch: closes an opened icon back to the main row.
## False if nothing was open.
func close_watch_icon() -> bool:
	if watch_open == "":
		return false
	watch_open = ""
	return true


## Takes the picked toy off the raised watch, and lowers the wrist to throw.
func take_picked_toy() -> void:
	var toys := watch_toys()
	if toys.is_empty():
		return
	watch_index = clampi(watch_index, 0, toys.size() - 1)
	hold_toy(toys[watch_index])
	if held_toy != "":
		wrist_raised = false
		watch_open = ""


## Takes the toy `item_id` off the watch into the hand ("" puts it back).
func hold_toy(item_id: String) -> void:
	if item_id != "" and (item_id not in watch_toys() or actor.is_dead or is_riding() or _toy_busy_left > 0.0):
		item_id = ""
	if item_id == held_toy:
		return
	held_toy = item_id
	toy_hold_requested.emit(item_id)
	if item_id != "":
		actor.notice.emit("%s in hand. Fire to throw it, aim to put it back" % ItemDB.item_name(item_id))


## Throws the toy in the hand. The world decides whether it leaves the hand.
func throw_held_toy() -> void:
	if held_toy == "":
		return
	var id := held_toy
	held_toy = ""
	_toy_busy_left = ActionPose.of(actor).toy_throw_time
	toy_throw_requested.emit(id)


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
		stop_inspect()
		cmd.inspect = false
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
	var busy_hands := cmd.primary_pressed or cmd.secondary_pressed or cmd.sprint or cmd.dash or cmd.slide
	if not wrist_raised:
		watch_open = ""
	elif watch_open != "" and cmd.secondary_pressed:
		# Right click backs out of an opened icon to the main row.
		close_watch_icon()
		cmd.secondary = false
		cmd.secondary_pressed = false
	elif watch_open != "":
		cmd.secondary = false
	if held_toy != "" or _toy_busy_left > 0.0:
		_use_toy_hand(cmd)
	elif watch_takes_fire():
		# With the watch up and something for it to do, fire works the watch.
		if cmd.primary_pressed:
			click_watch()
		cmd.primary = false
		cmd.primary_pressed = false
	cmd.reload_pressed = Input.is_action_just_pressed("reload")
	cmd.interact_pressed = Input.is_action_just_pressed("interact")
	cmd.heal_pressed = Input.is_action_just_pressed("heal")
	cmd.ability_pressed = captured and Input.is_action_just_pressed("ability")
	cmd.artifact_pressed = _artifact_click
	_artifact_click = false
	cmd.visor_pressed = captured and Input.is_action_just_pressed("visor")
	if cmd.visor_pressed:
		_visor_level = next_visor_level(actor.visor, _visor_level)
	cmd.visor_level = _visor_level
	cmd.watch_up = wrist_raised and not actor.is_dead
	var key_slot := -1
	for n in range(1, 4):
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
	if Input.is_action_just_pressed("inspect"):
		if inspect_left > 0.0:
			stop_inspect()
		else:
			start_inspect()
	elif busy_hands or cmd.reload_pressed or cmd.heal_pressed or cmd.ability_pressed \
			or cmd.interact_pressed or cmd.switch_weapon != -1:
		stop_inspect()
	_tick_inspect(cmd, delta)


## Starts looking over what is in the hand: the weapon drawn, or a toy
## vehicle. Nothing happens with empty hands, on a vehicle, with the watch
## up or the phone out.
func start_inspect() -> void:
	if actor == null or not is_instance_valid(actor) or actor.is_dead or is_riding() \
			or wrist_raised or phone_out:
		return
	if held_toy == "" and actor.get_active_weapon() == null:
		return
	inspect_left = ActionPose.INSPECT_SECONDS


## Puts the item back to the ready hold before the look over is done.
func stop_inspect() -> void:
	inspect_left = 0.0


## Counts the look over down, and stops it once the hands are wanted for
## something else (the watch, the phone, a vehicle, or nothing left in hand).
func _tick_inspect(cmd: ActorCommand, delta: float) -> void:
	if inspect_left > 0.0 and (wrist_raised or phone_out or is_riding() or actor.is_dead \
			or (held_toy == "" and actor.get_active_weapon() == null)):
		stop_inspect()
	inspect_left = maxf(inspect_left - delta, 0.0)
	cmd.inspect = inspect_left > 0.0


## With a toy in the hand the weapon is away: fire throws, aim puts it back.
func _use_toy_hand(cmd: ActorCommand) -> void:
	if held_toy == "":
		pass
	elif is_riding() or held_toy not in watch_toys():
		hold_toy("")
	elif cmd.primary_pressed:
		throw_held_toy()
	elif cmd.secondary_pressed:
		hold_toy("")
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
	if actor.is_dead and held_toy != "":
		hold_toy("")
	_toy_busy_left = maxf(_toy_busy_left - delta, 0.0)
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
	_phone_look = move_toward(_phone_look, 1.0 if phone_out and not actor.is_dead else 0.0, phone_read_rate * delta)
	var reading_pitch := phone_mirror_pitch if mirror_in_view() else phone_view_pitch
	var view_pitch := lerpf(pitch, reading_pitch, smoothstep(0.0, 1.0, _phone_look))
	var look := Basis.from_euler(Vector3(view_pitch + _shake.y, yaw + _shake.x, 0.0))
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
	_read_phone(delta)
	if _thrust_audio:
		var thrusting := actor.flight.is_thrusting and not actor.is_dead
		if thrusting and not _thrust_audio.playing:
			_thrust_audio.play()
		elif not thrusting and _thrust_audio.playing:
			_thrust_audio.stop()
	var first_person := not actor.is_dead and pivot.distance_to(desired) <= 0.7
	var skin := actor.get_node_or_null("Skin")
	# First person looks out of the model's own eyes (`ActorSkin.eye_point`),
	# which sit a little ahead of the actor's eye point; aim is still judged
	# from the actor.
	var eyes: Variant = skin.eye_point(look) if first_person and skin != null and skin.has_method("eye_point") else null
	var offset: Vector3 = eyes - actor.get_eye_position() if eyes != null else Vector3.ZERO
	if eyes != null:
		var ahead := Basis(Vector3.UP, yaw) * Vector3.FORWARD
		var down := clampf(-sin(view_pitch), 0.0, 1.0)
		var pull := eye_pullback * (1.0 - smoothstep(0.0, sin(pullback_fade_pitch), down))
		offset += ahead * (down * look_down_lean - pull)
	_eye_offset = _eye_offset.lerp(offset, 1.0 - exp(-18.0 * delta)) if first_person else offset
	if first_person:
		camera.global_position += _eye_offset * (1.0 - minf(_cam_dist / 0.7, 1.0))
	# The field of view, from where the camera has ended up (the phone's zoom
	# measures the phone from there).
	var speeding := 0.0 if aiming or _zoom() > 1.0 else speed_fov_for(_view_speed())
	_speed_fov_now = lerpf(_speed_fov_now, speeding, 1.0 - exp(-4.0 * delta))
	var fov := aim_fov(weapon) if aiming else wanted_base_fov() + _speed_fov_now
	if _zoom() > 1.0:
		fov = zoomed_fov(wanted_base_fov(), _zoom())
	if phone_read > 0.0 and mirror_in_view():
		fov = lerpf(fov, phone_mirror_fov, smoothstep(0.0, 1.0, phone_read))
	if phone_zoomed():
		fov = minf(fov, phone_fit_fov())
	camera.fov = lerpf(camera.fov, fov, 1.0 - exp(-14.0 * delta))
	# First and third person differ only in where the camera is (Caleb's
	# rule): your own body is drawn and posed the same in both, holding the
	# same weapon in the same hand. First person only leaves your head out of
	# this camera (`Mirror.HEAD_LAYER`), since the eyes are inside it; a
	# mirror's camera still sees it.
	if actor.body_mesh:
		actor.body_mesh.visible = true
	camera.cull_mask = 0xFFFFF & ~(1 << (MirrorScript.HEAD_LAYER - 1)) if first_person else 0xFFFFF
	if skin != null and skin.has_method("hide_head"):
		skin.hide_head(first_person)
	ActionPose.of(actor).advance(delta)
	# Aiming down sights the body brings the gun up to its eyes, the same in
	# both views (`ActionPose.ads`). First person then settles the eye on the
	# sight line as the gun comes up, so it looks straight down it; the gun
	# is never moved to the camera. The sight is read where it is drawn
	# (`ActionPose.sight_shown`), never where a physics tick left the hand.
	var pose := ActionPose.of(actor)
	var gun := weapon as Gun if first_person and not phone_out else null
	var up := pose.ads if gun != null and gun.visual != null and gun.visual.visible else 0.0
	sighted = up > 0.9
	if up > 0.0:
		var at := ActionPose.sight_shown(gun) + look * Vector3(0.0, 0.0, (pose.relief_now if pose.relief_now >= 0.0 else pose.relief_for(gun)) + eye_relief)
		camera.global_transform = camera.global_transform.interpolate_with(Transform3D(look, at), up)
	_update_scope(gun if up > 0.5 else null)


## A scoped gun aimed in first person shows its magnified view on the glass
## of its eyepiece, rendered from the eye by a camera of its own, and leaves
## everything around the scope as the eye sees it. The picture spans what the
## lens covers in the view divided by the scope's zoom, so it is magnified by
## exactly that. Everything else is left alone; the glass goes back to plain
## glass when the gun comes down.
func _update_scope(gun: Gun) -> void:
	var lens: MeshInstance3D = null
	if gun != null and gun.scope_lens and gun.visual != null:
		lens = gun.visual.find_child("Lens", true, false) as MeshInstance3D
	if lens != _scope_lens:
		if _scope_lens != null and is_instance_valid(_scope_lens):
			_scope_lens.material_override = null
		_scope_lens = lens
		if _scope_view != null:
			_scope_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if lens == null or camera == null:
		return
	if _scope_view == null:
		_scope_view = SubViewport.new()
		_scope_view.name = "ScopeView"
		_scope_view.size = Vector2i(scope_pixels, scope_pixels)
		add_child(_scope_view)
		_scope_cam = Camera3D.new()
		_scope_view.add_child(_scope_cam)
		_scope_mat = ShaderMaterial.new()
		_scope_mat.shader = load("res://assets/shaders/scope_lens.gdshader")
		_scope_mat.set_shader_parameter("view", _scope_view.get_texture())
	_scope_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	lens.material_override = _scope_mat
	var eye := camera.global_transform
	var ahead := -eye.basis.z.normalized()
	var reach := maxf((lens.global_position - eye.origin).dot(ahead), 0.01)
	var half := (lens.mesh as QuadMesh).size.y * 0.5 * lens.global_basis.get_scale().y
	var zoom := maxf(gun.aim_zoom(), 1.0)
	_scope_cam.global_transform = eye
	_scope_cam.cull_mask = camera.cull_mask
	_scope_cam.near = scope_near
	_scope_cam.fov = rad_to_deg(2.0 * atan(half / reach / zoom))


## Whether the magnified view is being drawn in a scope's lens right now.
func scoped() -> bool:
	return _scope_lens != null and is_instance_valid(_scope_lens)


## The field of view while aiming `weapon`: optics zoom further in.
func aim_fov(weapon: Weapon) -> float:
	if weapon is Gun and (weapon as Gun).scope_lens:
		# A scope magnifies inside its lens only (`_update_scope`).
		return ads_fov
	return ads_fov / maxf(1.0, weapon.aim_zoom() if weapon else 1.0)


## How much the mouse turns the view right now, relative to the resting view.
func _zoom_scale() -> float:
	if camera == null:
		return 1.0
	var scale := tan(deg_to_rad(camera.fov) * 0.5) / tan(deg_to_rad(wanted_base_fov()) * 0.5)
	if scoped():
		# Aim through the lens as steadily as the view it magnifies.
		scale /= maxf(actor.get_active_weapon().aim_zoom(), 1.0) if actor and actor.get_active_weapon() else 1.0
	return clampf(scale, 0.05, 1.0)


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


## Eases the third-person camera in beside the head, square onto the
## phone's screen in the hand, while it is out, and back out after. The view
## is only moved, never switched. With the Mirror app's mirror up it reads
## from over the shoulder and widens to keep the reflection in frame.
func _read_phone(delta: float) -> void:
	var face := phone_panel()
	var wanted := 1.0 if phone_out and face != null and _wants_third_person() and not actor.is_dead else 0.0
	phone_read = move_toward(phone_read, wanted, phone_read_rate * delta)
	if phone_read <= 0.0 or face == null:
		return
	var w := smoothstep(0.0, 1.0, phone_read)
	var centre := face.global_position
	var heading := Basis.from_euler(Vector3(0.0, yaw, 0.0))
	# Aim a little past its left edge so the phone sits right of the
	# crosshair, off the middle of the scene.
	var aim_at := centre - heading * Vector3(phone_read_offset, 0.0, 0.0)
	var spot: Vector3
	var up := Vector3.UP
	if mirror_in_view():
		spot = actor.get_eye_position() + heading * phone_mirror_spot
		aim_at = aim_at.lerp(phone_mirror.glass_centre(), phone_mirror_aim)
	else:
		var facing := face.global_basis.z.normalized()
		var along := (facing + heading * Vector3.RIGHT * phone_read_side + Vector3.UP * phone_read_lift).normalized()
		spot = centre + along * phone_read_distance
		# The view tips with the phone so its lines read level, as a head
		# tilts to read one.
		up = face.global_basis.y.normalized().lerp(Vector3.UP, 1.0 - phone_read_tilt).normalized()
	var reading := Transform3D(Basis.looking_at(aim_at - spot, up), spot)
	camera.global_transform = camera.global_transform.interpolate_with(reading, w)


## Whether the view is zoomed in on the phone in the hand (`phone_zoom`).
func phone_zoomed() -> bool:
	return phone_out and phone_panel() != null and not actor.is_dead and not mirror_in_view()


## The field of view (degrees) from where the camera is now at which the
## phone in the hand stands `phone_zoom` of the view's height, widened as
## needed to keep all of it in frame. Works from the device's corners as the
## camera sees them, so it holds for any view, distance or setting.
func phone_fit_fov() -> float:
	var face := phone_panel() as VisualInstance3D
	if face == null:
		return 179.0
	var view := camera.global_transform.affine_inverse() * face.global_transform
	var box := face.get_aabb()
	var aspect := 16.0 / 9.0
	var shown := camera.get_viewport().get_visible_rect().size if camera.get_viewport() else Vector2.ZERO
	if shown.y > 0.0:
		aspect = shown.x / shown.y
	var low := INF
	var high := -INF
	var reach := 0.0
	for i in 8:
		var corner := view * box.get_endpoint(i)
		var ahead := maxf(-corner.z, 0.01)
		var up := corner.y / ahead
		low = minf(low, up)
		high = maxf(high, up)
		reach = maxf(reach, maxf(absf(up), absf(corner.x / ahead) / aspect))
	var half := maxf((high - low) * 0.5 / phone_zoom, reach / phone_zoom_edge)
	return rad_to_deg(2.0 * atan(half))




## True while the Mirror app's mirror stands in front of you.
func mirror_in_view() -> bool:
	return phone_mirror != null and is_instance_valid(phone_mirror) and phone_mirror.is_inside_tree() \
			and phone_mirror.has_method("glass_centre")


## The face of the phone in your hand, or null while it is away.
func phone_panel() -> Node3D:
	var skin := actor.get_node_or_null("Skin")
	if skin == null or not skin.has_method("handheld"):
		return null
	var face := Handheld.face_of(skin.handheld())
	return face if face != null and face.is_visible_in_tree() else null


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
