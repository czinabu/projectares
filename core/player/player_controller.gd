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
## While down: a place to land was picked, with a click on the watch's
## landing list or a number key (0 for the first on offer).
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
## The pack list's drop: put `item_id` out of the pack on the ground.
signal pack_drop_requested(item_id: String)
## The player pinged where they are looking from the watch.
signal ping_requested
## The watch's portal icon was clicked: open a squad portal to `destination`.
signal portal_requested(destination: String)
## On a race track, a pick on the race icon: "restart", "ghost" or "retire"
## (`Hud.RACE_ACTIONS`). `main.gd` asks the `Race` or flips the ghost.
signal race_requested(action: String)
## The player asked to pack the vehicle they are looking at onto the watch.
signal pack_requested
## A click on the opened map's target `index` (`map_targets`): set it as the
## waypoint, or clear it if it already is. The HUD keeps the waypoint.
signal map_target_clicked(index: int)

enum ViewMode { FIRST, THIRD }

## The meta a station's view camera carries (`screen_view_up`).
const SCREEN_VIEW := "screen_view"
const VIEW_NAMES := ["First-person", "Third-person"]
const STANCE_CONTROL_HINTS := [
	"flick the mouse left, right or up",
	"hold A, D or W as you attack or guard",
]
const VehicleScript := preload("res://core/vehicle/vehicle.gd")
const MirrorScript := preload("res://core/visual/mirror.gd")
const Handheld := preload("res://core/phone/handheld.gd")
const GameSettings := preload("res://core/settings/game_settings.gd")

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
## Set while a view setting's slider is dragged on the phone (`Main`, Caleb's
## ask for a live preview): the view stops dropping to the phone, zooming
## in on it and reading it from close, so the field of view and the camera
## are shown as they are; the phone stays in the hand.
var phone_preview := false
## The helmet is off, clipped to the hip (the helmet key, K,
## `toggle_helmet`): a toggle, sent as the held `ActorCommand.helmet_off`.
## It goes back on by itself when a new helmet is put on, and when you step
## out where people fight (weapons unlocked outside a safe zone or the base:
## leaving a gate outpost, a new life in a world), so it only stays off out
## there by choice.
var helmet_off := false
## The helmet's lamp is switched on (`toggle_lamp`), sent as the held
## `ActorCommand.lamp`.
var lamp_on := false
var _could_fight := false
var _helmet_seen := ""
var _helmet_actor: Actor = null
## Crouched by the crouch key: a toggle, sent as the held `ActorCommand.crouch`.
## Sprinting, jumping or getting on a vehicle stands you back up.
var crouch_toggled := false
## Third person never moves the camera for the phone (Caleb's call): the
## phone throws its screen up beside the character as a hologram
## (`Phone.HoloScreen`), like the watch's card. Only first person drops the
## eyes to the handheld and zooms in on it, at this rate.
var phone_read_rate := 6.0
## While the phone is out the first-person view zooms in on it (Caleb's pick
## over a bigger screen layout), like aiming down sights: only the
## field of view narrows, the hold and the camera stay put. It zooms until
## the phone stands this share of the view's height, whatever the player's
## field of view setting (Caleb's feedback: at a wide one a fixed zoom left it
## tiny), and never so far that the phone leaves the frame. Not with the
## Mirror app's mirror up, which needs the wide view.
var phone_zoom := 0.6
## How much of the view's half height and width the phone may reach out to.
var phone_zoom_edge := 0.94
## The eyes drop to the phone in the hand while it is out (radians of view
## pitch), in first person, the same way the model's head bows to it. Only the
## view moves: `pitch`, and so the aim, is left where it was.
var phone_view_pitch := -0.4
## With the Mirror app's mirror up (first person) the view frames your
## reflection instead of the phone in your hand, whose screen is thrown up
## beside it as a hologram (`Phone.HoloScreen`): it turns to put you
## `mirror_left` of the view's half width left of the middle and narrows
## until you stand `mirror_fill` of the view's height, the whole body, or
## the face while a face row is chosen (`mirror_focus`, 0 to 1, set by
## `Main` from the phone). Only the view moves: `yaw`, `pitch` and the aim
## stay as they were.
var mirror_left := 0.45
var mirror_fill := 0.86
var mirror_focus := 0.0
var mirror_focus_rate := 3.0
var _mirror_focus_now := 0.0
var _mirror_look := 0.0
## [yaw, pitch, fov] that frame the reflection this frame.
var _mirror_frame := Vector3.ZERO
var _phone_look := 0.0
## The mirror standing in front of you for the phone's Mirror app (`Main`),
## or null; the eyes drop less to see yourself in it.
var phone_mirror: Node3D
## The Mirror app in third person is a dressing room (Caleb's pick): the
## camera swings round in front of the character, `dressing_distance` out,
## looking at `dressing_look` metres over the feet, with the body framed left
## of the middle (`dressing_side`, metres) so the phone's hologram on the
## right never covers it. Dragging turns it round the body
## (`dressing_turn`, radians, 0 square in front). View only, set by `Main`.
var dressing_room := false
var dressing_turn := 0.0
var dressing_distance := 2.3
var dressing_look := 1.05
var dressing_side := 0.45
## The camera stands this high (m over the feet), over the phone held at the
## chest, so it looks down past it at the face instead of up into the phone.
var dressing_height := 1.6
## Close on the face (`mirror_focus`): this far out, framing the face.
var dressing_close := 0.95
var dressing_rate := 4.0
## How far into the dressing-room view the camera is now (0..1).
var dressing := 0.0
## How far behind the eyes the third-person camera sits, in meters: a view
## over the right shoulder (the phone's "Camera distance" setting). Aiming
## moves in to `aim_distance_ratio` of it.
var third_person_distance := 2.0
var aim_distance_ratio := 0.6
## A vehicle is bigger than a person: riding sits this much further back,
## more for a vehicle longer than a bike (`ride_scale`).
var ride_extra_distance := 1.6
## Where the third-person camera stands beside the eyes before it moves back,
## in metres right and up of them: over the right shoulder, so the body sits
## left of the crosshair and never covers it. Aiming moves it in
## (`aim_distance_ratio`) and out over the shoulder (`shoulder_aim`), so the
## head clears the sight line. Both fade out as the camera comes in to the
## eyes, so switching views glides between them.
var shoulder := Vector3(0.55, 0.22, 0.0)
var shoulder_aim := Vector3(0.62, 0.1, 0.0)
## How fast the shoulder moves between rest and aim, a second.
var shoulder_rate := 9.0
## The camera is a ball this wide (metres) when it backs into walls, so it
## stops short of them instead of looking through their edges.
var camera_radius := 0.2
## Pulled in by a wall the camera comes in at once; it backs out again at
## this many metres a second, so it never pops back and forth along a wall.
var wall_return := 3.0
var _shoulder_aim := 0.0
## How much of `_cam_dist` a wall is taking away now (metres).
var _wall_pull := 0.0
## The view used while riding. It starts in third-person and V switches it,
## separately from the on-foot view, which comes back when you get off.
var ride_view := ViewMode.THIRD
var base_fov := 80.0
## How far the view draws, in metres, unless the map asks for more (`_view_far`).
var view_far := 400.0
## Speed widens the view a little, so a boost, a dive or a bike reads as
## fast: up to `speed_fov` degrees more, from a sprint's speed up to
## `speed_fov_at` m/s. Never while aiming or zoomed.
var speed_fov := 9.0
var speed_fov_at := 26.0
## A landing dips the third-person view by the speed you came down at (m per
## m/s, up to `land_dip_max` m) and springs back. First person rides the
## head down through the body's own landing squat instead.
var land_dip := 0.016
var land_dip_max := 0.25
## A shell landing jolts the view (`feel_blast`): this much (degrees) right
## beside it, falling away to nothing at `blast_feel_reach` metres.
var blast_kick_deg := 2.4
var blast_feel_reach := 70.0
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
## The nearest the lens is taken to be in front of the eye, so the picture's
## zoom can never blow up while the gun is still coming up.
var scope_min_reach := 0.05
var _scope_view: SubViewport
var _scope_cam: Camera3D
var _scope_mat: ShaderMaterial
## The lens the magnified view is drawn on now, if any.
var _scope_lens: MeshInstance3D
## First person: how far the model's eyes are from the actor's eye point,
## eased so the view never jolts with a step.
var _eye_offset := Vector3.ZERO
## The most (metres) that easing may leave the first-person camera off the
## model's eyes, so it never trails into the body.
var eye_lag_reach := 0.04
## How much the camera rides the model's eyes this frame (1 in first person,
## off while sighted or out in third person), and whose head it rides.
var _eyes_weight := 0.0
var _eyes_skin: Node
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
## Three levels (Caleb's call): raised with its key, the watch starts on the
## tab row, where the wheel turns between the tabs (Summon, Status,
## Mission) and a click goes into the open one; in a tab the wheel moves
## across its icons only, and a click opens an icon that holds several
## things (`watch_open`). A right click backs out one level, and off the
## tab row it lowers the watch (`back_watch`).
var watch_tabs := false
## The icon last looked at on each tab (tab -> `watch_focus`), so turning
## back to a tab lands where you left it.
var _tab_focus := {}
## Which weapon and which artifact are picked out on the raised watch's
## carousel (`Hud.weapon_entries`, `Hud.artifact_entries`), counting from 0.
var weapon_pick := 0
var artifact_pick := 0
## Which destination is picked out on the watch's portal icon
## (`portal_choices`), counting from 0.
var portal_pick := 0
## Which emote is picked out on the watch's emote icon (`Emotes.IDS`), the
## emote playing ("" for none) and the seconds it has left (0 for one held
## until you move). Sent as the held `ActorCommand.emote`.
var emote_pick := 0
var emote_playing := ""
var emote_left := 0.0
## The quick emote wheel (Caleb's call): held on the emote key, it comes up
## at once without raising the watch, drawn on the visor glass with a
## helmet working (`VisorHud._draw_emote_wheel`) or as a small hologram
## over the wrist without one (`Hud.EmoteHolo`). While it is up the mouse
## picks a slice instead of turning the view, the wheel steps round it, a
## click or letting go of a hold plays the slice, and a right click or the
## key again closes it. A tap of the key leaves it up to pick at leisure.
var emote_wheel_open := false
## The slice the wheel points at (an `Emotes.IDS` index), and the mouse's
## pull from the middle that picks it, in pixels.
var emote_wheel_pick := 0
var emote_wheel_aim := Vector2.ZERO
## Held shorter than this, the key leaves the wheel up; longer, letting go
## plays the slice picked.
var emote_wheel_tap := 0.25
## How far the mouse must pull from the middle before a slice is picked,
## and how far the pull goes at most (pixels).
var emote_wheel_dead := 24.0
var emote_wheel_reach := 120.0
var _wheel_held_ms := 0
var _wheel_moved := false
## True on the tick an emote started, so its own holster is not taken for
## a weapon key that ends it.
var _emote_fresh := false
## The opened Status icons and the pack list (Caleb's call: Status icons open
## with a click): the map target picked out, the Standing page, and the
## item picked out in the pack. View only.
var map_pick := 0
var standing_pick := 0
var pack_pick := 0
## On a race track: the race icon's pick, and which ghost is shown
## (`Race.GHOST_PICKS`; view only, turned by `main.gd`).
var race_pick := 0
var ghost_pick := "mine"
## The mission log on the contract icon: what it holds (`Hud.mission_entries`,
## kept up to date by the HUD) and which one is picked out. A click turns
## the picked one from on the visor to the main one to off it and back
## (`GameSettings.cycle_mission`).
## View only.
var missions: Array[Dictionary] = []
var mission_pick := 0
## The opened map's targets (`Hud.map_targets`), kept up to date by the HUD
## while the watch is up, so the wheel knows how many there are. View only.
var map_targets: Array[Dictionary] = []
## While down, which place to land is picked out on the watch's death
## report (`Hud.drop_choices`), counting from 0. The wheel turns through
## them and a click drops in there. View only.
var drop_pick := 0
## The artifact icon was clicked; sent as `artifact_pressed` next command.
var _artifact_click := false
## Seconds left of the throw just made: the hand is busy, so the weapon
## stays put away and takes no input (`ActionPose.toy_throw_time`).
var _toy_busy_left := 0.0
## A mouse button pressed while the watch, the phone or a toy had the hands
## (or the click that took the mouse back) is theirs until it is let go, so
## neither its press nor its hold nor its release reaches the weapon
## (`_hold_back_clicks`).
var _fire_held_back := false
var _aim_held_back := false
var _cam_dist := 0.0
var _pending_switch := -1
## The zoom level asked of a helmet with binoculars. The visor key steps it.
var _visor_level := 0
var _rng := RandomNumberGenerator.new()
## The wind past your ears at speed, in the air or on a skate (the style
## pass): from `air_rush_from` m/s, full by `air_rush_full`.
var _air_rush: AudioStreamPlayer
var air_rush_from := 9.0
var air_rush_full := 30.0
## Flight's camera motion in first person (the style pass, Caleb's call):
## the view rolls with the wings' bank (`flight_bank_roll` of it) and a
## skate's carve (`skate_carve_roll`), sways `skate_sway_deg` with a skate's
## strides, and a jetpack boost rumbles (`boost_rumble_deg`) after a jolt as
## it lights (`boost_jolt_deg`). Camera only, so the body is the same in
## both views; scaled by the phone's `GameSettings.flight_camera_motion`,
## and never in third person, where the body shows it.
var flight_bank_roll := 0.33
var skate_carve_roll := 0.25
var skate_sway_deg := 1.0
var boost_rumble_deg := 0.18
var boost_jolt_deg := 0.8
var _flight_roll := 0.0
var _flight_rumble := Vector2.ZERO
var _was_boosting := false
## Fades hostile bodies the eyes cannot see out of the third-person view.
var peek_fade := PeekFade.new()
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
## A round's jolt to the view: this much for a 20 damage hit, and never more
## than the max (`bullet_flinch`).
var bullet_flinch_deg := 0.5
var bullet_flinch_max_deg := 1.4
var _shake := Vector2.ZERO
var _shake_speed := Vector2.ZERO
var _speed_fov_now := 0.0


func setup(p_actor: Actor) -> void:
	actor = p_actor
	yaw = actor.cmd.yaw


func _ready() -> void:
	process_physics_priority = -10
	add_to_group("player_controllers")
	var live := LiveAim.new()
	live.name = "LiveAim"
	live.run = _live_aim
	add_child(live)
	camera = Camera3D.new()
	camera.fov = base_fov
	camera.far = view_far
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
	# A rig's own voice comes from the body (`ActorSkin._update_rig_voice`);
	# here only the wind past your ears.
	var rush_stream := Sfx.get_stream("air_rush")
	if rush_stream:
		_air_rush = AudioStreamPlayer.new()
		_air_rush.stream = rush_stream
		_air_rush.volume_db = -60.0
		add_child(_air_rush)


func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_update_scope(null)


func _unhandled_input(event: InputEvent) -> void:
	if input_blocked:
		return
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if emote_wheel_open and _wheel_input(event):
		get_viewport().set_input_as_handled()
		return
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
	elif event is InputEventMouseButton and event.pressed and not captured:
		# The click that takes the mouse back is not a shot or an aim.
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_fire_held_back = true
		_aim_held_back = true
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT \
			and is_instance_valid(actor) and actor.is_dead:
		click_landing()
	elif event is InputEventMouseButton and event.pressed \
			and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		scroll(1 if event.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1)
	elif event.is_action_pressed("toggle_view"):
		toggle_view()
	elif event.is_action_pressed("check_wrist"):
		wrist_raised = not wrist_raised
		watch_focus_moved = false
		watch_open = ""
		watch_tabs = wrist_raised
	elif event.is_action_pressed("emote_wheel") and not event.is_echo():
		open_emote_wheel()
	elif event.is_action_pressed("watch_map"):
		watch_shortcut("map")
	elif event.is_action_pressed("helmet"):
		toggle_helmet()
	elif event.is_action_pressed("lamp"):
		toggle_lamp()
	elif event.is_action_pressed("quick_emote"):
		quick_emote()
	elif event.is_action_pressed("ping") and captured and is_instance_valid(actor) and not actor.is_dead:
		ping_requested.emit()
	elif event.is_action_pressed("sign_out"):
		sign_out_requested.emit()
	elif event.is_action_pressed("redeploy") and is_instance_valid(actor) and actor.is_dead:
		redeploy_requested.emit()
	elif event is InputEventKey and event.pressed and not event.echo and is_instance_valid(actor) \
			and actor.is_dead and event.keycode >= KEY_1 and event.keycode <= KEY_9:
		drop_pick = event.keycode - KEY_1
		drop_requested.emit(event.keycode - KEY_1)


## A shortcut key for watch icon `id` (the emote wheel, the map): raises
## the watch straight onto it, opened if it holds several things, or lowers
## it if it is already up there. The same watch the check-wrist key raises,
## so the wheel and a click work on it as usual.
func watch_shortcut(id: String) -> void:
	if wrist_raised and watch_focus_moved and focused_watch_icon() == id:
		wrist_raised = false
		watch_open = ""
		return
	wrist_raised = true
	watch_tabs = false
	watch_focus = Hud.Wrist.SLOTS.find(id)
	watch_focus_moved = true
	watch_open = id if watch_entries(id) > 1 else ""


## Brings the quick emote wheel up on the emote key, pointing at the emote
## last picked. Not while down, riding or with the phone out; the watch goes
## down for it.
func open_emote_wheel() -> void:
	if actor == null or not is_instance_valid(actor) or actor.is_dead or is_riding() or phone_out:
		return
	emote_wheel_open = true
	emote_wheel_pick = clampi(emote_pick, 0, Emotes.IDS.size() - 1)
	emote_wheel_aim = Vector2.ZERO
	_wheel_moved = false
	_wheel_held_ms = Time.get_ticks_msec()
	wrist_raised = false
	watch_open = ""


## Puts the wheel away, playing the slice it points at when `play` (or
## stopping it, if that emote is already playing).
func close_emote_wheel(play: bool) -> void:
	if not emote_wheel_open:
		return
	emote_wheel_open = false
	emote_wheel_aim = Vector2.ZERO
	if not play:
		return
	emote_pick = emote_wheel_pick
	var picked: String = Emotes.IDS[clampi(emote_wheel_pick, 0, Emotes.IDS.size() - 1)]
	if picked == emote_playing:
		stop_emote()
	else:
		start_emote(picked)


## The slice of the wheel (an `Emotes.IDS` index) a pull of the mouse
## points at: the first at the top, then round clockwise. -1 inside the
## dead middle.
func wheel_slice(pull: Vector2) -> int:
	if pull.length() < emote_wheel_dead:
		return -1
	var count := Emotes.IDS.size()
	var turn := fposmod(atan2(pull.x, -pull.y), TAU)
	return int(round(turn / (TAU / count))) % count


## The wheel's own input while it is up. True when it took the event.
func _wheel_input(event: InputEvent) -> bool:
	if event is InputEventMouseMotion:
		emote_wheel_aim = (emote_wheel_aim + (event as InputEventMouseMotion).relative).limit_length(emote_wheel_reach)
		var slice := wheel_slice(emote_wheel_aim)
		if slice >= 0:
			emote_wheel_pick = slice
			_wheel_moved = true
		return true
	if event is InputEventMouseButton and event.pressed:
		match (event as InputEventMouseButton).button_index:
			MOUSE_BUTTON_LEFT:
				close_emote_wheel(true)
			MOUSE_BUTTON_RIGHT:
				close_emote_wheel(false)
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				var step := 1 if event.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1
				emote_wheel_pick = posmod(emote_wheel_pick + step, Emotes.IDS.size())
				_wheel_moved = true
			_:
				return false
		return true
	if event.is_action_pressed("emote_wheel") and not event.is_echo():
		# Tapped up, the key again puts it away.
		close_emote_wheel(false)
		return true
	if event.is_action_released("emote_wheel"):
		# Held, letting go plays what it points at; a tap leaves it up.
		if Time.get_ticks_msec() - _wheel_held_ms >= int(emote_wheel_tap * 1000.0):
			close_emote_wheel(_wheel_moved)
		return true
	return false


## The quick emote key: plays the emote last picked on the watch, or stops
## the one playing.
func quick_emote() -> void:
	if emote_playing != "":
		stop_emote()
	else:
		start_emote(Emotes.IDS[clampi(emote_pick, 0, Emotes.IDS.size() - 1)])


## How many places to land the watch's death report offers now.
func landing_count() -> int:
	var raid := Raid.of(actor) if actor != null and is_instance_valid(actor) else null
	return Hud.drop_choices(raid, actor).size() if raid != null else 0


## A click while down, on the watch's death report: drops in at the place
## picked out (`drop_pick`), or anywhere when there is no choice to make.
## The world refuses it until the wait is over.
func click_landing() -> void:
	var places := landing_count()
	if places > 1:
		drop_pick = clampi(drop_pick, 0, places - 1)
		drop_requested.emit(drop_pick)
	else:
		redeploy_requested.emit()


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
	return is_watch_on("artifact") and actor.artifact.enabled and _is_open("artifact")


## Where a squad portal from the watch can lead from here
## (`Portal.choices_for`): worlds, the arena and the plaza from your base,
## worlds, the arena and home from a safe zone, only home (a sign-out) out
## in a world, and none in the arena or while down.
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
## click; it still never shoots (`_hold_back_clicks`).
func click_watch() -> bool:
	if pack_target() != null:
		pack_requested.emit()
		return true
	if watch_tabs and is_watch_up():
		# On the tab row a click goes into the open tab, on the icon it
		# shows (where you last were on it, or where the card opened).
		watch_tabs = false
		watch_focus_moved = true
		return true
	# On a tab a click opens an icon that holds several things, and only
	# then does the wheel turn through them.
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
	if is_on_sign_out():
		sign_out_requested.emit()
		return true
	if is_watch_on("map") and _is_open("map") and not map_targets.is_empty():
		map_target_clicked.emit(clampi(map_pick, 0, map_targets.size() - 1))
		return true
	if is_watch_on("pack") and _is_open("pack"):
		# The pack list: a click puts on the picked piece of gear.
		take_picked_from_pack()
		return true
	if is_watch_on("standing") and watch_open != "":
		# Pages to read: a click has nothing more to do, and never shoots.
		return true
	if is_on_race() and _is_open("contract"):
		race_requested.emit(Hud.RACE_ACTIONS[clampi(race_pick, 0, Hud.RACE_ACTIONS.size() - 1)])
		if Hud.RACE_ACTIONS[clampi(race_pick, 0, Hud.RACE_ACTIONS.size() - 1)] != "ghost":
			wrist_raised = false
			watch_open = ""
		return true
	if is_on_missions() and _is_open("contract"):
		var at := clampi(mission_pick if watch_open == "contract" else 0, 0, missions.size() - 1)
		GameSettings.cycle_mission(str(missions[at].key))
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
	return (watch_tabs and is_watch_up()) or (watch_open == "" and watch_entries(focused_watch_icon()) > 1) or is_picking_toys() or pack_target() != null or is_picking_weapons() or is_on_artifact() \
			or is_watch_on("portal") or is_on_sign_out() \
			or (is_watch_on("map") and not map_targets.is_empty()) \
			or (watch_open == "standing" and is_watch_on(watch_open)) \
			or (is_watch_on("pack") and _is_open("pack") and not actor.inventory.items.is_empty()) or is_on_race() \
			or is_on_missions()


## True while the raised watch is on the mission log (the contract icon
## anywhere but a race track) and it holds something to track.
func is_on_missions() -> bool:
	return is_watch_on("contract") and not (Raid.of(actor) is Race) and not missions.is_empty()


## True while the raised watch is on the sign-out icon out in a world, where
## a click starts or cancels the sign-out like the L key. At home there is
## nothing to sign out of.
func is_on_sign_out() -> bool:
	return is_watch_on("leave") and Raid.of(actor) != null


## True while the raised watch is on the race icon on a race track (the
## contract's place there, `Hud.race_slot`).
func is_on_race() -> bool:
	return is_watch_on("contract") and Raid.of(actor) is Race


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
	elif int(entry.index) >= 0 and int(entry.index) == actor.active_weapon_index \
			and int(entry.index) == Loadout.power_index(actor):
		# The heavy weapon in hand goes back into the watch's chamber (never
		# the pack): back to the weapon drawn before it, or empty hands.
		var back := actor.last_drawn
		if back < 0 or back >= actor.weapons.size() or back == int(entry.index):
			back = actor.weapon_for_key(1)
		_pending_switch = back if back >= 0 else ActorCommand.HOLSTER
	elif int(entry.index) >= 0:
		_pending_switch = int(entry.index)
	else:
		var raid := Raid.of(actor)
		if raid != null and raid.summon_wait(actor) > 0.0:
			# Still resting: a low buzz says no, and the watch stays up to show
			# the rest running out. The world refuses it too, with a notice.
			Sfx.play("watch_refused", null, -6.0)
			summon_requested.emit(entry.id)
			return
		summon_requested.emit(entry.id)
	wrist_raised = false
	watch_open = ""


## The pack list's click (Caleb's call: loot it, then put it on in the
## field): asks the world to put on the picked item if it is gear the watch
## can put on (`Loadout.wearable_from_pack`), the worn one going into the
## pack in its place, and lowers the wrist. Anything else in the pack (loot,
## heals, an artifact or attachment) is only read here. The world decides
## and refuses with a notice (`Raid.summon`).
func take_picked_from_pack() -> void:
	var items := actor.inventory.items
	if items.is_empty():
		return
	var id: String = items[clampi(pack_pick, 0, items.size() - 1)]
	if not Loadout.wearable_from_pack(id):
		Sfx.play("watch_refused", null, -6.0)
		return
	var raid := Raid.of(actor)
	if raid != null and raid.summon_wait(actor) > 0.0:
		# Still resting: a low buzz, and the watch stays up to show it.
		Sfx.play("watch_refused", null, -6.0)
		summon_requested.emit(id)
		return
	summon_requested.emit(id)
	wrist_raised = false
	watch_open = ""


## True while the raised watch is on the pack list with something in it:
## the interact key then drops the picked item (`drop_picked_from_pack`).
func is_on_pack_list() -> bool:
	return is_watch_on("pack") and _is_open("pack") and not actor.inventory.items.is_empty()


## The pack list's drop (Caleb's call: a way to be rid of what you do not
## want): asks the world to put the picked item out of the pack where you
## stand, in a bag anyone may loot. The watch stays up on the list, so
## several can go one after another. The world decides and refuses with a
## notice (`Raid.drop_item`).
func drop_picked_from_pack() -> void:
	var items := actor.inventory.items
	if items.is_empty():
		return
	var id: String = items[clampi(pack_pick, 0, items.size() - 1)]
	if not Hud.can_drop_here(Raid.of(actor)):
		# A low buzz; the world says why with a notice.
		Sfx.play("watch_refused", null, -6.0)
	# The pick stays where it is, so the next item down moves up under it.
	pack_drop_requested.emit(id)


## The mouse wheel: the next weapon, or with the watch up, the next icon on
## its card (`step` 1 is down the wheel, to the right). With the watch up the
## wheel never switches weapons.
func scroll(step: int) -> void:
	if actor != null and is_instance_valid(actor) and actor.is_dead:
		# Down, the wheel turns through the places to land.
		drop_pick = clampi(drop_pick + signi(step), 0, maxi(landing_count() - 1, 0))
	elif is_watch_up():
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
		"map":
			return map_targets.size()
		"standing":
			# Three pages out in a world: at stake, safe, this life.
			return Hud.STANDING_PAGES.size() if Raid.of(actor) != null else 0
		"pack":
			return actor.inventory.items.size()
		"contract":
			return Hud.RACE_ACTIONS.size() if Raid.of(actor) is Race else missions.size()
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
		"map":
			return map_pick
		"standing":
			return standing_pick
		"pack":
			return pack_pick
		"contract":
			return race_pick if Raid.of(actor) is Race else mission_pick
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
		"map":
			map_pick = pick
		"standing":
			standing_pick = pick
		"pack":
			pack_pick = pick
		"contract":
			if Raid.of(actor) is Race:
				race_pick = pick
			else:
				mission_pick = pick


## Moves the watch card one notch of the wheel (`step` 1 is down, to the
## right), at the level it is on: an opened icon turns through what it
## holds, stopping at the list's ends; on the tab row it turns to the next
## tab, landing on the icon last looked at there; in a tab it moves across
## that tab's icons and stops at the tab's ends.
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
	var tab := Hud.Wrist.tab_of(slots[watch_focus])
	if watch_tabs:
		var tabs: Array = Hud.Wrist.TABS
		var next: String = tabs[clampi(tabs.find(tab) + signi(step), 0, tabs.size() - 1)]
		if next != tab:
			_tab_focus[tab] = watch_focus
			watch_focus = int(_tab_focus.get(next, slots.find(Hud.Wrist.row(next)[0])))
		return
	var row: Array = Hud.Wrist.row(tab)
	var id: String = row[clampi(row.find(slots[watch_focus]) + signi(step), 0, row.size() - 1)]
	watch_focus = slots.find(id)
	_tab_focus[tab] = watch_focus


## Right click on the watch: backs out one level. An opened icon closes back
## to its tab, a tab goes back to the tab row, and the tab row lowers the
## watch. False if the watch is down.
func back_watch() -> bool:
	if not is_watch_up():
		return false
	if close_watch_icon():
		return true
	if not watch_tabs:
		watch_tabs = true
		return true
	wrist_raised = false
	watch_tabs = false
	return true


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


## Closes an opened icon back to its tab's icons. False if nothing was open.
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


## The crouch key (C), after the move, sprint and jump keys are in `cmd`:
## pressed while sprinting forward it is a slide (`ActorCommand.slide`);
## otherwise it toggles the crouch. In the air with a flight rig it only
## coasts the jets down (`ActorCommand.descend`). A sprint or a jump stands
## you up, and nobody rides crouched.
func crouch_key(pressed: bool) -> void:
	var cmd := actor.cmd
	var on_floor := actor.is_on_floor()
	if pressed and cmd.sprint and cmd.move.y > 0.0 and on_floor:
		cmd.slide = true
		crouch_toggled = false
	elif pressed and (on_floor or not actor.flight.enabled):
		crouch_toggled = not crouch_toggled
	elif (cmd.sprint_pressed and on_floor) or (cmd.jump_pressed and on_floor):
		crouch_toggled = false
	if actor.vehicle != null:
		crouch_toggled = false
	cmd.crouch = crouch_toggled


func _physics_process(delta: float) -> void:
	if actor == null or not is_instance_valid(actor) or actor.is_dead:
		crouch_toggled = false
		_could_fight = false
		emote_wheel_open = false
		return
	if emote_wheel_open and (input_blocked or wrist_raised or phone_out or is_riding()):
		close_emote_wheel(false)
	var cmd := actor.cmd
	cmd.clear_one_shots()
	cmd.phone = phone_out
	_keep_helmet(cmd)
	if input_blocked:
		# Hands on the phone: let go of everything, keep facing the same way.
		cmd.move = Vector2.ZERO
		cmd.sprint = false
		cmd.jump = false
		cmd.descend = false
		cmd.free_look = false
		cmd.primary = false
		cmd.secondary = false
		_fire_held_back = _fire_held_back or Input.is_action_pressed("fire")
		_aim_held_back = _aim_held_back or Input.is_action_pressed("alt_fire")
		cmd.switch_weapon = -1
		_visor_level = 0
		cmd.visor_level = 0
		stop_inspect()
		cmd.inspect = false
		stop_emote()
		cmd.emote = 0
		return
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if not is_nan(actor.turn_request):
		# Turned by the game (a shadow step): the view turns with the body.
		yaw = actor.turn_request
		actor.turn_request = NAN
	cmd.yaw = yaw
	cmd.pitch = pitch
	cmd.move = Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_back", "move_forward"))
	cmd.sprint = Input.is_action_pressed("sprint")
	cmd.sprint_pressed = Input.is_action_just_pressed("sprint")
	cmd.jump = Input.is_action_pressed("jump")
	cmd.jump_pressed = Input.is_action_just_pressed("jump")
	cmd.dash = Input.is_action_just_pressed("dash")
	cmd.kick_pressed = Input.is_action_just_pressed("kick")
	cmd.weapon_ability_pressed = Input.is_action_just_pressed("weapon_ability")
	cmd.descend = Input.is_action_pressed("crouch")
	crouch_key(Input.is_action_just_pressed("crouch"))
	cmd.free_look = Input.is_action_pressed("free_look")
	if cmd.dash and actor.stamina >= actor.dash_stamina:
		Sfx.play("dash", null, -6.0)
	elif cmd.sprint_pressed and not actor.is_on_floor() and actor.flight.enabled and not actor.flight.overheated:
		Sfx.play("dash", null, -6.0)
	cmd.primary = captured and Input.is_action_pressed("fire")
	cmd.primary_pressed = captured and Input.is_action_just_pressed("fire")
	cmd.secondary = captured and Input.is_action_pressed("alt_fire")
	cmd.secondary_pressed = captured and Input.is_action_just_pressed("alt_fire")
	if emote_wheel_open:
		# The wheel has the mouse's buttons: a click picks, never shoots.
		cmd.primary = false
		cmd.primary_pressed = false
		cmd.secondary = false
		cmd.secondary_pressed = false
	var busy_hands := cmd.primary_pressed or cmd.secondary_pressed or cmd.sprint or cmd.dash or cmd.slide
	_hold_back_clicks(cmd)
	cmd.reload_pressed = Input.is_action_just_pressed("reload")
	cmd.interact_pressed = Input.is_action_just_pressed("interact")
	if cmd.interact_pressed and is_on_pack_list():
		# On the opened pack list the interact key drops the picked item,
		# and never reaches for a door or a cache as well.
		drop_picked_from_pack()
		cmd.interact_pressed = false
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
	# 4 draws the heavy weapon waiting in the watch's chamber (Caleb's call,
	# replacing "from the watch only"); it materializes as from the watch.
	if Input.is_action_just_pressed("weapon_4"):
		key_slot = Loadout.power_index(actor)
	if key_slot >= 0:
		cmd.switch_weapon = key_slot
	elif Input.is_action_just_pressed("holster"):
		# Put the weapon away, or draw the one last put away. Sent as an
		# index, not a toggle, so a repeated or late packet lands the same.
		if actor.get_active_weapon():
			cmd.switch_weapon = ActorCommand.HOLSTER
		elif not actor.weapons.is_empty():
			cmd.switch_weapon = clampi(actor.last_drawn, 0, actor.weapons.size() - 1)
	elif _pending_switch != -1:
		cmd.switch_weapon = _pending_switch
	_pending_switch = -1
	cmd.aim_dir = _compute_aim_dir()
	if Input.is_action_just_pressed("inspect"):
		if inspect_left > 0.0:
			stop_inspect()
		else:
			start_inspect()
	elif busy_hands or cmd.reload_pressed or cmd.heal_pressed or cmd.ability_pressed \
			or cmd.weapon_ability_pressed or cmd.interact_pressed or cmd.switch_weapon != -1:
		stop_inspect()
	_tick_inspect(cmd, delta)
	_tick_emote(cmd, delta)


## The mouse buttons with the watch up, the phone out or a toy in the hand
## (playtest feedback: a pick on the watch fired a round, a right click back
## brought the sight up). The watch and the toy hand get the press first;
## then any button that went down while one of them had the hands is held
## back from the weapon until it is let go, so a click that lowers the watch
## (an emote, a portal, the helmet) never carries on as a held trigger, and
## a right click that backs out never aims. Fire and aim never reach the
## weapon while the watch is up, the same in both views.
func _hold_back_clicks(cmd: ActorCommand) -> void:
	var fire_down := cmd.primary
	var aim_down := cmd.secondary
	var hands_taken := wrist_raised or phone_out or held_toy != "" or _toy_busy_left > 0.0
	if hands_taken and fire_down:
		_fire_held_back = true
	if hands_taken and aim_down:
		_aim_held_back = true
	if not wrist_raised:
		watch_open = ""
		watch_tabs = false
	elif cmd.secondary_pressed:
		# Right click backs out one level: an opened icon to its tab, a tab
		# to the tab row, the tab row puts the watch down. Never an aim.
		back_watch()
		cmd.secondary = false
		cmd.secondary_pressed = false
	if held_toy != "" or _toy_busy_left > 0.0:
		_use_toy_hand(cmd)
	elif watch_takes_fire():
		# With the watch up and something for it to do, fire works the watch.
		if cmd.primary_pressed:
			click_watch()
		cmd.primary = false
		cmd.primary_pressed = false
	if wrist_raised:
		cmd.primary = false
		cmd.primary_pressed = false
		cmd.secondary = false
		cmd.secondary_pressed = false
	if not fire_down:
		_fire_held_back = false
	elif _fire_held_back:
		cmd.primary = false
		cmd.primary_pressed = false
	if not aim_down:
		_aim_held_back = false
	elif _aim_held_back:
		cmd.secondary = false
		cmd.secondary_pressed = false


## Starts emote `id` (`Emotes`): the weapon in hand is put away and the body
## plays it until it ends, or until you move, jump, fire, draw, ride or get
## the phone or watch out. Nothing on a vehicle, in the air or down.
func start_emote(id: String) -> void:
	if actor == null or not is_instance_valid(actor) or actor.is_dead or is_riding() \
			or not actor.is_on_floor() or Emotes.number_of(id) <= 0:
		return
	emote_playing = id
	emote_left = Emotes.seconds_of(id)
	_emote_fresh = actor.get_active_weapon() != null
	crouch_toggled = false
	stop_inspect()
	if actor.get_active_weapon() != null:
		_pending_switch = ActorCommand.HOLSTER


func stop_emote() -> void:
	emote_playing = ""
	emote_left = 0.0
	_emote_fresh = false


## Counts a one-off emote down and ends any once the body is wanted for
## something else. Sends what is playing as the held `cmd.emote`.
func _tick_emote(cmd: ActorCommand, delta: float) -> void:
	if emote_playing != "":
		var switched := cmd.switch_weapon != -1 and not (_emote_fresh and cmd.switch_weapon == ActorCommand.HOLSTER)
		if cmd.move.length() > 0.1 or cmd.jump_pressed or cmd.jump or cmd.sprint or cmd.dash or cmd.slide \
				or cmd.crouch or cmd.primary_pressed or cmd.secondary_pressed or cmd.reload_pressed \
				or cmd.heal_pressed or cmd.ability_pressed or cmd.kick_pressed or cmd.weapon_ability_pressed \
				or cmd.interact_pressed or switched or wrist_raised or phone_out or is_riding() or actor.is_dead \
				or actor.airborne_time > 0.15 or held_toy != "":
			stop_emote()
		elif emote_left > 0.0:
			emote_left -= delta
			if emote_left <= 0.0:
				stop_emote()
	if cmd.switch_weapon != -1:
		_emote_fresh = false
	cmd.emote = Emotes.number_of(emote_playing) if emote_playing != "" else 0


## Takes the worn helmet off onto the hip, or puts it back on (the helmet
## key, K; it left the watch once it had a key of its own). It takes both hands (Caleb's call), so a weapon in hand is
## put away first, as with the holster key. Nothing to do bare-headed.
func toggle_helmet() -> void:
	if actor != null and is_instance_valid(actor) and actor.visor.enabled and not actor.is_dead:
		helmet_off = not helmet_off
		if actor.get_active_weapon() != null and not is_riding():
			_pending_switch = ActorCommand.HOLSTER


## Switches the lamp on the helmet's brow on or off (J, Caleb's ask). Kept
## while the helmet is on the hip, so it lights again when it goes back on.
## Nothing to switch bare-headed.
func toggle_lamp() -> void:
	if actor != null and is_instance_valid(actor) and actor.visor.enabled and not actor.is_dead:
		lamp_on = not lamp_on


## Sends whether the helmet is off (`helmet_off`), putting it back on by
## itself where it should go back on (see `helmet_off`).
func _keep_helmet(cmd: ActorCommand) -> void:
	var worn := actor.visor.item_id if actor.visor.enabled else ""
	if actor != _helmet_actor:
		# A new body (a trip, a new life): one that comes with the same
		# helmet still has it on the hip, already clipped there.
		_helmet_actor = actor
		if helmet_off and worn == _helmet_seen and worn != "":
			actor.helmet_stow = 1.0
			actor.visor.stowed = true
			ActionPose.of(actor).helmet = 1.0
	if worn != _helmet_seen:
		helmet_off = false
		_helmet_seen = worn
	var can_fight := not actor.weapons_locked and not Visor.peaceful(actor)
	if can_fight and not _could_fight:
		helmet_off = false
	_could_fight = can_fight
	if worn == "":
		helmet_off = false
		lamp_on = false
	elif not actor.visor.working():
		# Nothing to look through: a zoom or thermal left on starts off.
		_visor_level = 0
	cmd.helmet_off = helmet_off
	cmd.lamp = lamp_on


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


## How far the view draws: a map with things to see past its rim (a
## skyline, giants on the horizon) asks for more with its "view_far" meta,
## and a planet's far land ring with "horizon_far" (`Planet.atmosphere`);
## the View distance setting takes its share of that
## (`GameSettings.view_far_for`), never less than `view_far`.
func _view_far() -> float:
	var raid := Raid.of(actor)
	if raid != null and is_instance_valid(raid.map):
		var world := maxf(float(raid.map.get_meta("view_far", 0.0)), float(raid.map.get_meta("horizon_far", 0.0)))
		return GameSettings.view_far_for(world, view_far)
	return view_far


## Each drawn frame, before anything is posed or shown from the body: the
## look the next tick will send, given to the body now, so on a screen faster
## than the ticks the body, its arms and the gun turn with the mouse every
## frame (`ShownMotion.live_yaw`). The next tick sets the same values again
## before simulating, so nothing simulated reads them early.
func _live_aim() -> void:
	if actor == null or not is_instance_valid(actor) or actor.is_dead or input_blocked:
		return
	actor.cmd.yaw = yaw
	actor.cmd.pitch = pitch
	actor.cmd.aim_dir = _compute_aim_dir()
	actor.hand.rotation = Vector3(pitch, 0.0, 0.0)
	var motion := ShownMotion.of(actor)
	if motion != null:
		motion.live_yaw = yaw


## True while a station's own view has the screen (a `WorldScreen` or the
## bench's view, which set `SCREEN_VIEW` on their camera): they stand about
## where the head is, so the head is left out of them as in first person,
## wherever the player stands (Caleb's feedback: it blocked the bench).
func screen_view_up() -> bool:
	if not is_inside_tree():
		return false
	var current := get_viewport().get_camera_3d()
	return current != null and current != camera and current.has_meta(SCREEN_VIEW)


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

	camera.far = _view_far()
	_update_recoil(delta)
	_update_dip(delta)
	_update_shake(delta)
	_phone_look = move_toward(_phone_look, 1.0 if phone_out and not phone_preview and not actor.is_dead \
			and not _wants_third_person() else 0.0, phone_read_rate * delta)
	var view_pitch := lerpf(pitch, phone_view_pitch, smoothstep(0.0, 1.0, _phone_look))
	var view_yaw := yaw
	_mirror_focus_now = move_toward(_mirror_focus_now, mirror_focus, mirror_focus_rate * delta)
	var framing := mirror_in_view() and not actor.is_dead and not _wants_third_person()
	if framing:
		_mirror_frame = mirror_frame(actor.get_eye_position())
	_mirror_look = move_toward(_mirror_look, 1.0 if framing else 0.0, phone_read_rate * delta)
	if _mirror_look > 0.0:
		var k := smoothstep(0.0, 1.0, _mirror_look)
		view_yaw = lerp_angle(yaw, _mirror_frame.x, k)
		view_pitch = lerpf(view_pitch, _mirror_frame.y, k)
	_update_flight_motion(delta)
	var look := Basis.from_euler(Vector3(view_pitch + _shake.y + _flight_rumble.y, view_yaw + _shake.x + _flight_rumble.x, 0.0))
	var pivot := actor.get_eye_position() - Vector3(0.0, _dip, 0.0)
	_shoulder_aim = move_toward(_shoulder_aim, 1.0 if aiming else 0.0, shoulder_rate * delta)
	var desired := pivot + _third_person_offset(look, pivot, delta)
	camera.global_transform = Transform3D(look * Basis(Vector3.BACK, _flight_roll * _eyes_weight), desired)
	_dress_view(delta)
	peek_fade.update(actor, camera, peek_rule_applies() and is_third_person(), delta)
	_update_air_rush()
	var first_person := not actor.is_dead and pivot.distance_to(desired) <= 0.7
	var skin := actor.get_node_or_null("Skin")
	# First person looks out of the model's own eyes (`ActorSkin.eye_point`),
	# which sit a little ahead of the actor's eye point; aim is still judged
	# from the actor.
	var eyes: Variant = skin.eye_point(look) if first_person and skin != null and skin.has_method("eye_point") else null
	# From the dipped pivot: first person looks out of the head, which takes
	# a landing in the body's own squat, so the camera's landing dip on top
	# of it would sink the eyes into the chest (third person keeps the dip).
	var offset: Vector3 = eyes - pivot if eyes != null else Vector3.ZERO
	if eyes != null:
		var ahead := Basis(Vector3.UP, yaw) * Vector3.FORWARD
		var down := clampf(-sin(view_pitch), 0.0, 1.0)
		var pull := eye_pullback * (1.0 - smoothstep(0.0, sin(pullback_fade_pitch), down))
		offset += ahead * (down * look_down_lean - pull)
	_eye_offset = _eye_offset.lerp(offset, 1.0 - exp(-18.0 * delta)) if first_person else offset
	# The easing may only trail the eyes so far: a quick move of the head (a
	# hard landing, springing up from it, a dive pulled out of, the view
	# swung) left the camera inside the neck or the armor's collar.
	_eye_offset = offset + (_eye_offset - offset).limit_length(eye_lag_reach)
	_eyes_weight = 0.0
	if first_person:
		_eyes_weight = 1.0 - minf(_cam_dist / 0.7, 1.0)
		camera.global_position += _eye_offset * _eyes_weight
	if skin != _eyes_skin:
		if _eyes_skin != null and is_instance_valid(_eyes_skin) and _eyes_skin.has_signal("head_posed"):
			_eyes_skin.disconnect("head_posed", _on_head_posed)
		_eyes_skin = skin
		if skin != null and skin.has_signal("head_posed"):
			skin.connect("head_posed", _on_head_posed)
	# The field of view, from where the camera has ended up (the phone's zoom
	# measures the phone from there).
	var speeding := 0.0 if aiming or _zoom() > 1.0 else speed_fov_for(_view_speed())
	_speed_fov_now = lerpf(_speed_fov_now, speeding, 1.0 - exp(-4.0 * delta))
	var fov := aim_fov(weapon) if aiming else wanted_base_fov() + _speed_fov_now
	if _zoom() > 1.0:
		fov = zoomed_fov(wanted_base_fov(), _zoom())
	if phone_zoomed():
		fov = minf(fov, phone_fit_fov())
	if _mirror_look > 0.0:
		fov = lerpf(fov, minf(fov, _mirror_frame.z), smoothstep(0.0, 1.0, _mirror_look))
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
		skin.hide_head(first_person or screen_view_up())
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
	# Sighted, the eye sits on the gun's sight line, not on the head.
	_eyes_weight *= 1.0 - up
	if up > 0.0:
		var at := ActionPose.sight_shown(gun) + look * Vector3(0.0, 0.0, (pose.relief_now if pose.relief_now >= 0.0 else pose.relief_for(gun)) + eye_relief) - look * pose.sight_aside(gun)
		camera.global_transform = camera.global_transform.interpolate_with(Transform3D(look, at), up)
	_update_scope(gun if up > 0.5 else null)


## The head was posed after the camera was placed from it (`ActorSkin.head_posed`):
## first person follows it by as much, this same frame.
func _on_head_posed(by: Vector3) -> void:
	if _eyes_weight > 0.0 and camera != null:
		camera.global_position += by * _eyes_weight


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
	# The lens is read where it is drawn this frame (`ActionPose.shown_global`),
	# never where the last physics tick parked the hand: that spot is off the
	# eye line, so the zoom worked out from it jumped about from frame to
	# frame (Caleb's buggy 4x and 8x picture).
	var glass := ActionPose.shown_global(gun, lens.global_transform)
	var eye := camera.global_transform
	var ahead := -eye.basis.z.normalized()
	var reach := maxf((glass.origin - eye.origin).dot(ahead), scope_min_reach)
	var half := (lens.mesh as QuadMesh).size.y * 0.5 * glass.basis.get_scale().y
	var zoom := maxf(gun.aim_zoom(), 1.0)
	# The picture looks where the eye aims, turned with the glass it is drawn
	# on, so a canted scope never shows the world tipped inside its lens.
	var up := glass.basis.y - ahead * glass.basis.y.dot(ahead)
	if up.length_squared() < 0.0001:
		up = eye.basis.y
	_scope_cam.global_transform = Transform3D(Basis.looking_at(ahead, up.normalized()), eye.origin)
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


## Each shot kicks the view along the gun's pattern (`Gun.recoil_for`: a
## climb that builds through a spray and the gun's own drift), with a little
## left to chance. The player learns to pull against it to hold a spray on
## target. The kick arrives and settles in `_update_recoil`.
func _on_gun_fired(_from: Vector3, _to: Vector3, gun: Gun) -> void:
	var scale := 0.6 if gun.is_aiming() else 1.0
	var jitter := gun.recoil_side_deg * gun.recoil_jitter
	_kick_coming.x += deg_to_rad(gun.last_recoil.x) * scale
	# The view's yaw grows to the left, so a kick to the right takes it down.
	_kick_coming.y += deg_to_rad(-gun.last_recoil.y + _rng.randf_range(-jitter, jitter)) * scale
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


## A blast at `at` (a shell, `ShellView`) jolts the view, harder the
## nearer it is. View only.
func feel_blast(at: Vector3) -> void:
	if camera == null or not is_instance_valid(camera):
		return
	var near := 1.0 - camera.global_position.distance_to(at) / blast_feel_reach
	if near <= 0.0:
		return
	kick_view(Vector2(_rng.randf_range(-0.6, 0.6), -1.0) * deg_to_rad(blast_kick_deg) * near * near)


## Works out flight's camera motion for this frame (see `flight_bank_roll`):
## the roll, eased, and the boost's rumble. Only the first-person camera
## takes it (`_eyes_weight`).
func _update_flight_motion(delta: float) -> void:
	var amount := clampf(GameSettings.flight_camera_motion, 0.0, 1.0)
	var skin := actor.get_node_or_null("Skin")
	var roll := 0.0
	var rumble := 0.0
	if amount > 0.0 and skin != null and skin.has_method("flight_bank") and not actor.is_dead:
		roll = float(skin.call("flight_bank")) * flight_bank_roll + float(skin.call("skate_carve")) * skate_carve_roll
		var stride: float = skin.call("stride_phase")
		if not is_nan(stride):
			roll += sin(stride) * deg_to_rad(skate_sway_deg)
		rumble = float(skin.call("boost_push"))
	var boosting := actor.flight.is_boosting and not actor.is_dead
	if boosting and not _was_boosting and amount > 0.0:
		# The pack lights: the view is pushed back a little.
		kick_view(Vector2(0.0, deg_to_rad(boost_jolt_deg) * amount))
	_was_boosting = boosting
	_flight_roll = lerpf(_flight_roll, roll * amount, 1.0 - exp(-8.0 * delta))
	var shake := deg_to_rad(boost_rumble_deg) * rumble * amount
	_flight_rumble = Vector2(_rng.randf_range(-shake, shake), _rng.randf_range(-shake, shake)) if shake > 0.0 else Vector2.ZERO


## The wind past your ears: louder and higher the faster you fly or skate.
func _update_air_rush() -> void:
	if _air_rush == null:
		return
	var moving := not actor.is_dead and actor.vehicle == null and (not actor.is_on_floor() or actor.flight.is_skating)
	var share := clampf((actor.velocity.length() - air_rush_from) / maxf(air_rush_full - air_rush_from, 0.1), 0.0, 1.0) \
			if moving else 0.0
	if share > 0.0 and not _air_rush.playing:
		_air_rush.play()
	elif share <= 0.0 and _air_rush.playing:
		_air_rush.stop()
	_air_rush.volume_db = lerpf(-30.0, -6.0, share)
	_air_rush.pitch_scale = 0.8 + 0.4 * share


## Jolts the view by `kick` (yaw, pitch in radians); it springs back.
func kick_view(kick: Vector2) -> void:
	_shake_speed += kick * 30.0


func _update_shake(delta: float) -> void:
	if _shake.is_zero_approx() and _shake_speed.is_zero_approx():
		return
	# A stiff, critically damped spring, like the landing dip, and stepped in
	# short slices like it: in one long frame (a hitch, a slow machine) the
	# spring would overshoot further each frame until the view was lost.
	var left := delta
	while left > 0.0:
		var step := minf(left, 1.0 / 120.0)
		_shake_speed += (-400.0 * _shake - 40.0 * _shake_speed) * step
		_shake += _shake_speed * step
		left -= step
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
	elif info.headshot:
		Sfx.play("headshot")
	elif info.armor_broke:
		Sfx.play("armor_break", null, -2.0)
	elif info.armored:
		Sfx.play("armor_hit")
	else:
		Sfx.play("hit")


func _on_damaged(info: DamageInfo) -> void:
	Sfx.play("hurt")
	if info.kind in ["melee", "slam"]:
		kick_view(Vector2(_rng.randf_range(-0.5, 0.5), -1.0) * deg_to_rad(flinch_deg))
	elif info.kind == "bullet":
		kick_view(bullet_flinch(info.amount, _rng.randf_range(-1.0, 1.0)))


## How far a round of `amount` damage jolts the view (yaw, pitch in radians),
## `side` from -1 to 1 picking which way it tips. View only: the aim stays
## where it was, so being shot shakes your picture but never moves your
## shots. It grows with the hit, up to `bullet_flinch_max_deg`.
func bullet_flinch(amount: float, side: float) -> Vector2:
	var deg := minf(bullet_flinch_deg * amount / 20.0, bullet_flinch_max_deg)
	return Vector2(side * 0.6, 1.0) * deg_to_rad(deg)


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


## How far back the third-person camera wants to be.
func view_distance(aiming: bool) -> float:
	if aiming:
		return third_person_distance * aim_distance_ratio
	return third_person_distance + (ride_extra_distance * ride_scale() if is_riding() else 0.0)


## How much bigger than a bike the vehicle being ridden is, for framing it:
## 1 for a bike, more for a rover, a walker or a jet.
func ride_scale() -> float:
	var vehicle: Node3D = actor.vehicle if actor != null else null
	if vehicle == null or not is_instance_valid(vehicle):
		return 1.0
	var size: Variant = vehicle.get("body_size")
	if not size is Vector3:
		return 1.0
	var v := size as Vector3
	# A bike's body is 2 m long; framed by its biggest side.
	return clampf(maxf(v.x, maxf(v.y, v.z)) / 2.0, 1.0, 2.5)


## Where the third-person camera stands from the eyes (`pivot`), looking
## along `look`: out over the shoulder (`shoulder`, `shoulder_aim`), then back
## `_cam_dist`, both fading in together as the camera leaves the eyes. A wall
## in the way stops it short, swept as a ball (`camera_radius`) so it never
## looks through an edge, and it eases back out (`wall_return`).
func _third_person_offset(look: Basis, pivot: Vector3, delta: float) -> Vector3:
	var out := clampf(_cam_dist / maxf(third_person_distance * aim_distance_ratio, 0.1), 0.0, 1.0)
	out = smoothstep(0.0, 1.0, out)
	var side := shoulder.lerp(shoulder_aim, smoothstep(0.0, 1.0, _shoulder_aim)) * out
	var offset := look * Vector3(side.x, side.y, _cam_dist)
	if _cam_dist <= 0.05 or not actor.is_inside_tree():
		_wall_pull = 0.0
		return offset
	var space := actor.get_world_3d().direct_space_state
	var ball := SphereShape3D.new()
	ball.radius = camera_radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = ball
	query.collision_mask = Actor.LAYER_WORLD
	# Out to the shoulder first, then back from it: the camera never ends up
	# on the far side of a wall the shoulder is pressed against.
	var shoulder_at := look * Vector3(side.x, side.y, 0.0)
	query.transform = Transform3D(Basis.IDENTITY, pivot)
	query.motion = shoulder_at
	var free_side: float = space.cast_motion(query)[0]
	shoulder_at *= free_side
	var back := look * Vector3(0.0, 0.0, _cam_dist)
	query.transform = Transform3D(Basis.IDENTITY, pivot + shoulder_at)
	query.motion = back
	var pull: float = (1.0 - space.cast_motion(query)[0]) * _cam_dist
	_wall_pull = pull if pull > _wall_pull else move_toward(_wall_pull, pull, wall_return * delta)
	return shoulder_at + back.normalized() * maxf(_cam_dist - _wall_pull, 0.0)


func wanted_base_fov() -> float:
	return base_fov_third if _wants_third_person() else base_fov


func is_third_person() -> bool:
	return _cam_dist > 0.5


## Swings the third-person camera round in front of the character while the
## Mirror app is up (`dressing_room`), and back after.
func _dress_view(delta: float) -> void:
	var wanted := dressing_room and _wants_third_person() and not actor.is_dead and actor.is_inside_tree()
	dressing = move_toward(dressing, 1.0 if wanted else 0.0, dressing_rate * delta)
	if dressing <= 0.0:
		return
	var f := smoothstep(0.0, 1.0, _mirror_focus_now)
	var face := actor.get_eye_position().y - actor.global_position.y - 0.04
	var centre := actor.global_position + Vector3.UP * lerpf(dressing_look, face, f)
	var high := actor.global_position + Vector3.UP * lerpf(dressing_height, face + 0.04, f)
	var out := Basis(Vector3.UP, yaw + dressing_turn) * Vector3.FORWARD
	var far := lerpf(dressing_distance, dressing_close, f)
	var reach := far
	var space := actor.get_world_3d().direct_space_state
	var ray := PhysicsRayQueryParameters3D.create(high, high + out * (far + camera_radius), Actor.LAYER_WORLD)
	var hit := space.intersect_ray(ray)
	if not hit.is_empty():
		reach = clampf(high.distance_to(hit.position) - camera_radius, 0.6, far)
	var spot := high + out * reach
	var facing := Basis.looking_at(centre - spot, Vector3.UP)
	var aim_at := centre + facing.x * dressing_side * reach / dressing_distance
	var front := Transform3D(Basis.looking_at(aim_at - spot, Vector3.UP), spot)
	camera.global_transform = camera.global_transform.interpolate_with(front, smoothstep(0.0, 1.0, dressing))


## Whether the view is zoomed in on the phone in the hand (`phone_zoom`):
## first person only, since third person reads the hologram.
func phone_zoomed() -> bool:
	return phone_out and not phone_preview and not _wants_third_person() and phone_panel() != null and not actor.is_dead and not mirror_in_view()


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
## The view's [yaw, pitch, field of view] that frames your reflection in
## `phone_mirror` from `eye`: you `mirror_left` left of the middle, standing
## `mirror_fill` of the view's height, the whole body or (`mirror_focus`)
## the face. The hologram of the phone stands on the right.
func mirror_frame(eye: Vector3) -> Vector3:
	var normal := phone_mirror.global_basis.z.normalized()
	var across := phone_mirror.global_basis.x.normalized()
	var centre: Vector3 = phone_mirror.glass_centre()
	var head := actor.get_eye_position()
	var feet := actor.global_position
	var f := smoothstep(0.0, 1.0, _mirror_focus_now)
	var top := head + Vector3.UP * lerpf(0.22, 0.2, f)
	var bottom := feet.lerp(head - Vector3.UP * 0.22, f)
	var wide := lerpf(0.32, 0.16, f)
	var points: Array[Vector3] = [top, bottom, (top + bottom) * 0.5 + across * wide, (top + bottom) * 0.5 - across * wide]
	for i in points.size():
		points[i] = points[i] - 2.0 * (points[i] - centre).dot(normal) * normal
	# Across, the middle follows the head, which leans and turns with the
	# phone; the feet stay put.
	var middle := (points[0] + points[1]) * 0.5
	var head_seen := head - 2.0 * (head - centre).dot(normal) * normal
	middle += across * (head_seen - middle).dot(across)
	var to := (middle - eye).normalized()
	var aspect := 16.0 / 9.0
	var shown := camera.get_viewport().get_visible_rect().size if camera.get_viewport() else Vector2.ZERO
	if shown.y > 0.0:
		aspect = shown.x / shown.y
	var half_wide := tan(deg_to_rad(camera.fov) * 0.5) * aspect
	var view_yaw := atan2(-to.x, -to.z) - atan(mirror_left * half_wide)
	var view_pitch := asin(clampf(to.y, -1.0, 1.0))
	var view := Basis.from_euler(Vector3(view_pitch, view_yaw, 0.0)).inverse()
	var need := 0.01
	for point in points:
		var p := view * (point - eye)
		var ahead := maxf(-p.z, 0.05)
		need = maxf(need, absf(p.y) / ahead / mirror_fill)
		need = maxf(need, absf(p.x) / ahead / aspect / 0.97)
	return Vector3(view_yaw, view_pitch, clampf(rad_to_deg(2.0 * atan(need)), 12.0, 179.0))


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


## True where third person must not show more than the eyes see: out in a
## world where gear is at stake (`PeekFade`). Safe zones, the arena and the
## home base are left alone.
func peek_rule_applies() -> bool:
	var raid := Raid.of(actor)
	return raid != null and raid.world != null and raid.world.gear_at_risk and not raid.world.safe_zone


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


## Runs `_live_aim` first thing each drawn frame, before the body is shown
## between ticks (`ShownMotion`) and posed.
class LiveAim:
	extends Node
	var run: Callable

	func _ready() -> void:
		process_priority = -200

	func _process(_delta: float) -> void:
		if run.is_valid():
			run.call()


## Third person never shows more than the eyes see (Caleb's call): where gear
## is at stake, a hostile body the actor's eyes have no line to fades out of
## the third-person view, so looking round a corner from over the shoulder
## shows nothing a first-person player could not see. View only: nothing in
## the simulation reads it, and first person is left alone.
class PeekFade:
	## Seconds between line-of-sight checks.
	const CHECK_EVERY := 0.1
	## Drawn opacity lost or gained a second.
	const FADE_RATE := 7.0
	## A body stays drawn this long after the eyes lose it, so it does not
	## flicker at a doorframe.
	const HOLD := 0.3
	## Bodies further than this are never checked (left as they are drawn).
	const REACH := 160.0

	var _check_left := 0.0
	## Actor -> seconds since the eyes last had a line to it.
	var _unseen := {}
	## Actor -> drawn opacity, 0 to 1. Only bodies not fully drawn are kept.
	var _alpha := {}

	## Steps the fade. `active` is false in first person or wherever the rule
	## does not apply, which brings every faded body back.
	func update(viewer: Actor, camera: Camera3D, active: bool, delta: float) -> void:
		_check_left -= delta
		var check := _check_left <= 0.0
		if check:
			_check_left = CHECK_EVERY
		if active and check:
			var raid := Raid.of(viewer)
			var space := viewer.get_world_3d().direct_space_state
			var eye := viewer.get_eye_position()
			for node in viewer.get_tree().get_nodes_in_group("actors"):
				var other := node as Actor
				if other == null or other == viewer or not Raid.together(viewer, other):
					continue
				if other.is_dead or VisorHud.squadmate(raid, viewer, other) \
						or eye.distance_to(other.global_position) > REACH:
					_unseen.erase(other)
					continue
				# Off screen it does not matter yet: keep what was decided.
				if camera != null and not camera.is_position_in_frustum(other.global_position + Vector3(0, 1, 0)):
					continue
				if seen_from(space, eye, other):
					_unseen[other] = 0.0
				else:
					_unseen[other] = float(_unseen.get(other, 0.0)) + CHECK_EVERY
		# Keys are checked before they are typed: a body freed since (a dead
		# bot cleared away, a world left) cannot be assigned to an `Actor`,
		# and that error stopped the game in the editor's debugger.
		for key: Variant in _unseen.keys():
			if not is_instance_valid(key):
				_unseen.erase(key)
				_alpha.erase(key)
				continue
			var other := key as Actor
			var want := 0.0 if active and float(_unseen[other]) > HOLD else 1.0
			_fade(other, move_toward(float(_alpha.get(other, 1.0)), want, FADE_RATE * delta))
		for key: Variant in _alpha.keys():
			if not is_instance_valid(key):
				_alpha.erase(key)
			elif not _unseen.has(key):
				_fade(key as Actor, move_toward(float(_alpha[key]), 1.0, FADE_RATE * delta))

	## How much of `other` is drawn now (1 when it is not faded at all).
	func drawn(other: Actor) -> float:
		return float(_alpha.get(other, 1.0))

	func _fade(other: Actor, alpha: float) -> void:
		var was := float(_alpha.get(other, 1.0))
		if alpha >= 1.0 and was >= 1.0:
			return
		for node in other.find_children("*", "GeometryInstance3D", true, false):
			(node as GeometryInstance3D).transparency = 1.0 - alpha
		if alpha >= 1.0:
			_alpha.erase(other)
		else:
			_alpha[other] = alpha

	## True if the eyes at `eye` have a clear line to any part of `other`: the
	## head, the chest, the hips, or either side of the chest, so a body only
	## fades once all of it is behind something.
	static func seen_from(space: PhysicsDirectSpaceState3D, eye: Vector3, other: Actor) -> bool:
		var feet := other.global_position
		var height := other.body_height()
		var across := (feet - eye).cross(Vector3.UP)
		across = across.normalized() * Actor.BODY_RADIUS if across.length_squared() > 0.0001 else Vector3.ZERO
		var chest := feet + Vector3(0, height * 0.65, 0)
		for point: Vector3 in [feet + Vector3(0, height - 0.12, 0), chest, feet + Vector3(0, height * 0.4, 0),
				chest + across, chest - across]:
			var query := PhysicsRayQueryParameters3D.create(eye, point, Actor.LAYER_WORLD)
			if space.intersect_ray(query).is_empty():
				return true
		return false
