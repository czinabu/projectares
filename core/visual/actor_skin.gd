extends Node3D
## The model an actor wears. Added by `Look` as a child of the Actor; the
## Actor itself never knows about it. It reads the actor's state each frame
## and plays the matching animation, swaps greybox weapon parts for models,
## and plays the effects for shots and hits.

const Vfx := preload("res://core/visual/vfx.gd")
const WeaponArm := preload("res://core/visual/weapon_arm.gd")
const RigModel := preload("res://core/visual/rig_model.gd")
const Locomotion := preload("res://core/visual/locomotion.gd")
## Clips that loop and are cut between in step, keeping the stride's phase.
const GAITS: Array[String] = ["walk", "run", "run_back", "run_left", "run_right", "move_gun"]
## Standing clips. Cuts into and out of them blend for longer, so stopping
## settles into the stand instead of snapping.
const STANDS: Array[String] = ["idle", "idle_gun", "aim_gun", "idle_melee"]

## How long a standing gun stays raised after the last shot, in seconds.
var aim_hold := 1.5
## Blend times, in seconds: between two gaits, into or out of a stand, else.
var gait_blend := 0.2
var stand_blend := 0.35
var cut_blend := 0.15

## How far behind the back bone a back-worn rig sits, and how far the boots
## sit above and behind the ankle bone, in meters.
var back_gap := 0.11
var back_drop := -0.02
var boot_offset := Vector3(0, 0.0, 0.0)
## How fast wings spread and fold, in full swings per second.
var wing_speed := 3.5
## How long nozzles burn after an air jump, in seconds.
var burst_burn := 0.3
## Gliding, the body lies out flat, head first: how far it tips forward
## (radians), the height it tips about, and how fast it goes in and out of
## the pose (full changes per second). Arms trail back along the sides,
## a little out and up like a diver's, and the legs stay straight together.
## Directions are in the actor's frame before the tip: x right, y up, z back.
var glide_pitch := 1.4
var glide_pivot := 1.0
var glide_blend := 3.0
var glide_arm := Vector3(0.45, -1.0, 0.25)
var glide_leg := Vector3(0.06, -1.0, -0.06)
## How far the head tips back to look ahead while flying flat, and how far
## the feet point, in radians.
var glide_look := 1.0
var glide_toes := 1.0
## Off the ground the legs stop running. `air_grace` seconds after leaving
## it (so steps and kerbs do not flicker) they go to an air pose, blended in
## at `air_blend` full changes a second. Each pose is a thigh and a shin
## direction per leg in the actor's frame (x right, y up, z back), the lead
## leg first. Leaping: lead knee up, the other leg trailing. Falling: both
## knees a little up and apart, ready to land. Hanging (jets lit or
## thrusting): legs loose under the body, trailing a little.
var air_grace := 0.12
var air_blend := 6.0
var air_toes := 0.45
var leap_legs := [Vector3(0.05, -1.0, -0.75), Vector3(0.0, -1.0, 0.7), Vector3(0.05, -1.0, 0.3), Vector3(0.0, -1.0, 0.55)]
var fall_legs := [Vector3(0.22, -1.0, -0.45), Vector3(0.0, -1.0, 0.5), Vector3(0.2, -1.0, -0.15), Vector3(0.0, -1.0, 0.6)]
var hang_legs := [Vector3(0.07, -1.0, -0.18), Vector3(0.0, -1.0, 0.4), Vector3(0.07, -1.0, 0.08), Vector3(0.0, -1.0, 0.5)]
## Taking off, the legs first push straight down off the ground, toes
## pointed, for `takeoff_time` seconds before they tuck into the leap. A
## running takeoff also leans into the jump, by up to `leap_lean` radians at
## `leap_lean_speed` m/s, and rights itself as the fall begins.
var push_legs := [Vector3(0.04, -1.0, 0.06), Vector3(0.0, -1.0, 0.12), Vector3(0.04, -1.0, 0.2), Vector3(0.0, -1.0, 0.3)]
var push_toes := 0.9
var takeoff_time := 0.22
var leap_lean := 0.32
var leap_lean_speed := 8.0
## Landing, the knees take it: a squat that deepens with how hard you came
## down (full at `land_full_speed` m/s, never less than `land_min` for a
## touchdown worth showing), let out over `land_time` seconds.
var land_full_speed := 14.0
var land_min := 0.3
var land_time := 0.4
## Vertical speed at which a jump counts as fully rising or fully falling.
var air_rise_speed := 4.0
## A jetpack boost flies the same way with the arms held down along the
## sides, a little off the body (Caleb's call: never reaching out ahead).
var boost_arm := Vector3(0.3, -1.0, 0.08)
## How fast the body follows a change of attitude, and the most it banks into
## a turn, in radians. The bank is the real one for the turn: tan = v * w / g.
var attitude_follow := 8.0
var max_bank := 1.1
var bank_follow := 5.0
## Hovering on a jetpack, the body leans the way it flies: radians at full
## fly speed, and how far the legs trail.
var hover_lean := 0.45
## The roll keys twist the body round its own length, in radians a second.
var twist_speed := 7.0

## Riding, the head turns at most this far (radians) toward the aim; the
## body stays facing along the vehicle.
var ride_head_turn := 1.1
## Where the wrist sits behind the resting hand spot when a rider holds a gun
## out, in the actor's frame along the aim.
var ride_gun_wrist := Vector3(0.0, -0.02, 0.1)
## Riding, a weapon slung on the back rides this much higher up the back, so
## its lower end clears the seat and the bike's tail.
var ride_sling_lift := 0.28

## Holstered weapons are worn on the body instead of vanishing: a gun is
## slung across the back, muzzle up over the right shoulder, and over the
## outside of a back rig (a jetpack or wings) when one is worn. A two-handed
## melee weapon crosses the back the other way; a one-handed blade hangs from
## the left hip. Distances in meters, in the actor's frame (x right, y up, z back).
var sling_tilt := deg_to_rad(35.0)
var sling_height := -0.2
## Where the back is behind the back bone with nothing worn, and how far the
## middle of a slung weapon sits out from the back or the rig's outer face.
var back_surface := 0.13
var sling_clearance := 0.04
var hip_offset := Vector3(-0.2, 0.08, 0.02)
## How far a sheathed blade tips from pointing straight up, toward the back.
var sheath_angle := deg_to_rad(138.0)
## A sidearm rides muzzle down in a holster on the right hip.
var holster_offset := Vector3(0.21, -0.02, 0.0)
## Switching weapons is shown, not instant: the hand reaches to the holster
## and puts the old weapon away, moves on to the next one's holster and draws
## it. Seconds for each move. Only the view waits; the actor switched the
## moment it was told, and first person stays instant.
var reach_time := 0.22
## How long a blade takes to slide out of its hilt when drawn, or back in
## when put away (`Look.set_extend`).
var fold_time := 0.18
var between_time := 0.14
var return_time := 0.2

var look: Node
var actor: Actor

var _player: AnimationPlayer
var _anims := {}
var _current := ""
var _current_sign := 1.0
var _weapons_seen := 0
var _wired := {}
var _flash_left := 0.0
var _materials: Array[ShaderMaterial] = []
var _skeleton: Skeleton3D
var _def := {}
## The flight rig being worn: its item id, the nodes holding its parts, its
## back part (or null), and a flame per nozzle.
var _rig_id := ""
var _rig_holders: Array[Node3D] = []
var _rig_back: Node3D
var _flames: Array[Node3D] = []
var _burst_left := 0.0
var _spread := 0.0
## 0 standing, 1 flying flat.
var _glide := 0.0
## Bones the glide pose moves: [from, to] pairs to aim, per side.
var _glide_arms: Array = []
var _glide_legs: Array = []
var _glide_neck := -1
## 0 on the ground, 1 in the air pose; and within it, 0 leaping .. 1 falling
## and 0 ballistic .. 1 hanging from the jets.
var _air := 0.0
## Seconds the weapon stays out in flat flight after shooting or aiming, and
## how far the arms have come off the sides to hold it (0 sides, 1 holding).
var _flight_draw_left := 0.0
var _flight_hold := 0.0
var _air_fall := 0.0
var _air_hang := 0.0
## 1 at the moment of takeoff, running down to 0 over `takeoff_time`.
var _air_push := 0.0
var _was_airborne := false
## How deep the landing squat was, and how much of it is left (1..0).
var _land_depth := 0.0
var _land_left := 0.0
## 0 arms trailing wide (wings), 1 arms in at the sides (boost).
var _boost := 0.0
## Which way the body tips (the actor's space, level) times how far, radians.
var _tilt := Vector3.ZERO
## Roll about the body's length: banking into a turn (positive in a left
## turn), and from the roll keys (positive to the right).
var _bank := 0.0
var _twist := 0.0
## How far the model is turned to face the way it flies, radians.
var _face := 0.0
var _last_heading := 0.0
var _has_heading := false
var _attack_left := 0.0
var _aim_left := 0.0
## Weapon -> the copy of it worn while holstered (null if it has no model),
## and the rig they were placed for.
var _stowed := {}
var _stowed_rig := ""
## Weapon -> the model node inside its worn copy, which lines up with the
## "Model" node under the weapon's own visual.
var _stowed_models := {}
## The weapon shown in the hand, the weapons the hand visits in turn while
## switching (putting `_in_hand` away first), the active weapon that plan is
## for, and how far into it the hand is.
var _in_hand: Weapon
## Melee weapon -> how far its held model is out (1) or folded away (0).
var _extend := {}
var _plan: Array[Weapon] = []
var _plan_for: Weapon
var _plan_t := 0.0
## The weapon moving between hand and holster now, and how far it has gone
## from the hand (0) to the holster (1).
var _moving: Weapon
var _moving_weight := 0.0
## Makes the model hold its weapon, or null for skins without the bones.
var arm: Node
## Matches the legs to the actor's speed and direction.
var locomotion: Node

func _ready() -> void:
	var skin_name: String = actor.get_meta("look", look.DEFAULT_SKIN)
	var def: Dictionary = look.SKINS.get(skin_name, look.SKINS[look.DEFAULT_SKIN])
	var built: Dictionary = look.character(skin_name, actor.get_meta("appearance", {}), String(actor.name))
	if built.is_empty():
		return
	var model: Node3D = built["model"]
	_materials = built["materials"]
	add_child(model)
	# Pack models face +Z. Actors face -Z.
	rotation.y = PI

	_player = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _player:
		for key: String in def.get("anims", {}):
			var found := _find_animation(def["anims"][key])
			if found != "":
				_anims[key] = found
				if key != "death" and key != "attack":
					_player.get_animation(found).loop_mode = Animation.LOOP_LINEAR
		_play("idle")
		_player.advance(0.0)
	look.stand_model(self, model, def["height"])
	_def = def
	var skeleton := model.find_child("Skeleton3D", true, false) as Skeleton3D
	_skeleton = skeleton
	# Before the arm, so the arm's hooks run after the legs have turned.
	locomotion = Locomotion.new()
	locomotion.name = "Locomotion"
	locomotion.actor = actor
	locomotion.skeleton = skeleton
	add_child(locomotion)
	locomotion.setup(def, _player, _anims)
	if skeleton and def.has("grip_bone"):
		arm = WeaponArm.new()
		arm.name = "WeaponArm"
		arm.actor = actor
		arm.skeleton = skeleton
		arm.look = look
		add_child(arm)
		arm.setup(def, _player.get_animation(_anims["idle_melee"]) if _player and _anims.has("idle_melee") else null)
		# After the arm has put the hand on the model's hand.
		skeleton.skeleton_updated.connect(_carry_moving)
	if skeleton:
		_setup_glide_pose(skeleton, def)

	# The greybox capsule stays as the actor's body node, but draws nothing.
	if actor.body_mesh:
		actor.body_mesh.mesh = null
		for child in actor.body_mesh.get_children():
			if child is MeshInstance3D:
				child.visible = false
	actor.health.damaged.connect(_on_damaged)
	actor.hit_confirmed.connect(_on_hit_confirmed)
	actor.flight.burst_fired.connect(_on_burst)
	actor.landed.connect(_on_landed)


func _find_animation(wanted: String) -> String:
	for anim_name in _player.get_animation_list():
		var short := String(anim_name).get_slice("|", String(anim_name).get_slice_count("|") - 1)
		if short == wanted:
			return anim_name
	return ""


## Plays a clip at a speed, negative to play it backwards. Moving from one
## walk or run clip to another keeps the point in the stride.
func _play(key: String, speed := 1.0) -> void:
	if _player == null or not _anims.has(key):
		return
	_player.speed_scale = speed
	_current_sign = signf(speed) if speed != 0.0 else 1.0
	if _current == key:
		return
	var phase := -1.0
	if _current in GAITS and key in GAITS and _player.current_animation_length > 0.0:
		phase = _player.current_animation_position / _player.current_animation_length
	var previous := _current
	_current = key
	if locomotion:
		locomotion.current_anim = _anims[key]
	var blend := gait_blend if phase >= 0.0 else cut_blend
	if key in STANDS or previous in STANDS:
		blend = stand_blend
	_player.play(_anims[key], blend)
	if phase >= 0.0:
		_player.seek(phase * _player.current_animation_length)


func _process(delta: float) -> void:
	if actor == null or not is_instance_valid(actor):
		return
	if actor.body_mesh:
		visible = actor.body_mesh.visible
	if actor.weapons.size() != _weapons_seen or _has_bare_weapon():
		_dress_weapons()
	if _flash_left > 0.0:
		_flash_left -= delta
		if _flash_left <= 0.0:
			_set_flash(0.0)
	_flight_draw_left = aim_hold if actor.cmd.primary or actor.cmd.secondary else maxf(_flight_draw_left - delta, 0.0)
	_flight_hold = move_toward(_flight_hold, 1.0 if _flight_draw_left > 0.0 else 0.0, glide_blend * delta)
	_update_rig(delta)
	_update_glide(delta)
	_update_stowed()
	_update_switch(delta)
	_aim_left = maxf(_aim_left - delta, 0.0)
	var weapon := actor.get_active_weapon()
	var melee := weapon as MeleeWeapon
	if locomotion == null:
		return
	_update_ride()
	locomotion.update(delta)
	locomotion.twist_target = 0.0
	locomotion.stride_target = 1.0
	locomotion.overlay = false
	locomotion.stand_legs = false
	if actor.is_dead:
		_play("death")
		return
	if melee and melee.is_winding_up() and _attack_left <= 0.0:
		_attack_left = 0.6
		_current = ""
		_play("attack", 1.3)
	_attack_left -= delta
	if _attack_left > 0.0:
		return
	# With a gun out the arm stays up, so the gun keeps pointing where it shoots.
	var armed := weapon != null and melee == null and _anims.has("move_gun")
	# Read from velocity alone, so a remote player, whose velocity comes with
	# each state from the server, moves its legs the same as a local one.
	var gait: Dictionary = {} if actor.vehicle != null or _glide > 0.0 else \
			locomotion.choose(locomotion.velocity, armed, _current, _current_sign)
	var airborne := is_airborne()
	_update_air(delta, airborne)
	if actor.vehicle != null:
		# Seated by the locomotion's riding pose over the clip of an empty,
		# armed or blade-holding stand, which still decides the weapon arm.
		_play("idle_melee" if melee and _anims.has("idle_melee") else stand_key(weapon))
	elif _glide > 0.0:
		_play("idle")
	elif airborne:
		# No ground under the feet: never a run cycle. A stand plays under
		# the air pose, so the arms keep their hold on the weapon.
		_play("idle_melee" if melee and _anims.has("idle_melee") else stand_key(weapon))
		locomotion.stand_legs = _current == "idle_gun"
	elif actor.is_sliding():
		# The slide pose bends whatever plays under it; the arms keep their hold.
		_play("idle_melee" if melee and _anims.has("idle_melee") else "idle")
		locomotion.twist_target = clampf(Locomotion.heading(locomotion.velocity), -locomotion.max_twist, locomotion.max_twist)
	elif not gait.is_empty():
		_play(gait["key"], gait["speed"])
		locomotion.twist_target = gait["twist"]
		locomotion.stride_target = gait["stride"]
		locomotion.overlay = armed and gait["key"] != "move_gun"
		if _player and _player.current_animation_length > 0.0:
			locomotion.overlay_phase = _player.current_animation_position / _player.current_animation_length
	elif melee and _anims.has("idle_melee"):
		_play("idle_melee")
	else:
		_play(stand_key(weapon))
		locomotion.stand_legs = _current == "idle_gun"


## True while the body lies flat in flight (gliding or boosting) and is not
## shooting or aiming: the weapon in hand is shown worn. View only; in first
## person the weapon stays in front of the camera.
func flies_stowed() -> bool:
	if actor.is_dead or actor.vehicle != null or actor.hand_override:
		return false
	if not (actor.flight.is_gliding or actor.flight.is_boosting):
		return false
	return _flight_draw_left <= 0.0


## True once the actor has been off the ground long enough to show it.
## Read from the actor's own timer, which a client keeps for remote players
## too (it simulates them from their commands).
func is_airborne() -> bool:
	return not actor.is_dead and actor.vehicle == null and actor.airborne_time > air_grace


## A touchdown: starts the landing squat. Called for remote players too,
## whose landing this game simulates from their commands.
func _on_landed(impact_speed: float) -> void:
	if impact_speed < 1.0 or actor.is_dead or actor.vehicle != null:
		return
	_land_depth = clampf(impact_speed / land_full_speed, land_min, 1.0)
	_land_left = 1.0


## Eases the air pose in and out and between its shapes, and plays out the
## takeoff push and the landing squat.
func _update_air(delta: float, airborne: bool) -> void:
	_air = move_toward(_air, 1.0 if airborne else 0.0, air_blend * delta)
	if airborne and not _was_airborne:
		# Going up is a takeoff; walking off a ledge is not.
		_air_push = 1.0 if actor.velocity.y > 1.0 else 0.0
		_land_left = 0.0
	_was_airborne = airborne
	_air_push = move_toward(_air_push, 0.0, delta / takeoff_time)
	_land_left = move_toward(_land_left, 0.0, delta / land_time)
	if locomotion:
		# Down fast, up slow: sin over the squat's life, peaking early.
		var life := 1.0 - _land_left
		locomotion.squat = _land_depth * sin(PI * pow(life, 0.55)) if _land_left > 0.0 and not actor.is_sliding() and actor.vehicle == null else 0.0
	if not airborne:
		return
	var follow := 1.0 - exp(-attitude_follow * delta)
	var jets := actor.flight.is_hovering or actor.flight.is_thrusting or actor.flight.is_skimming
	_air_hang = lerpf(_air_hang, 1.0 if jets else 0.0, follow)
	_air_fall = lerpf(_air_fall, clampf(0.5 - actor.velocity.y / (2.0 * air_rise_speed), 0.0, 1.0), follow)


## The clip for standing still out of a fight: hands empty, a gun held low,
## or a gun raised while the actor shoots or aims and for `aim_hold` after.
## Skins without the gun clips fall back to plain `idle`.
func stand_key(weapon: Weapon) -> String:
	if weapon == null or weapon is MeleeWeapon or weapon.visual == null:
		return "idle"
	if actor.cmd.primary or actor.cmd.secondary:
		_aim_left = aim_hold
	if _aim_left > 0.0 and _anims.has("aim_gun"):
		return "aim_gun"
	return "idle_gun" if _anims.has("idle_gun") else "idle"


## True when a weapon was swapped in without the count changing.
func _has_bare_weapon() -> bool:
	for weapon in actor.weapons:
		if weapon.visual and not weapon.visual.has_meta("dressed"):
			return true
	return false


## Swaps greybox gun parts for a model and wires up shot effects. Runs again
## whenever the actor's weapon list changes.
func _dress_weapons() -> void:
	_weapons_seen = actor.weapons.size()
	for weapon in actor.weapons:
		if weapon.visual == null:
			continue
		# Shot effects belong to this skin, so a skin that replaces an earlier
		# one wires them up again even though the models are already on.
		var gun := weapon as Gun
		if gun and not _wired.has(gun):
			_wired[gun] = true
			gun.fired.connect(_on_fired.bind(gun))
		if weapon.visual.has_meta("dressed"):
			continue
		weapon.visual.set_meta("dressed", true)
		var model: Node3D = look.weapon_model(weapon)
		if model:
			for child in weapon.visual.get_children():
				if child is MeshInstance3D:
					child.visible = false
			weapon.visual.add_child(model)
			look.mount_attachments(weapon.visual)
		elif weapon is MeleeWeapon:
			look.restyle_melee(weapon.visual)


## Shows every holstered weapon where it is worn, and hides the one in hand.
func _update_stowed() -> void:
	if _skeleton == null:
		return
	if _stowed_rig != _rig_id:
		_stowed_rig = _rig_id
		_clear_stowed()
	for weapon: Variant in _stowed.keys():
		if not is_instance_valid(weapon) or not weapon in actor.weapons:
			if _stowed[weapon]:
				_stowed[weapon].queue_free()
			_stowed.erase(weapon)
			_stowed_models.erase(weapon)
			_extend.erase(weapon)
	for weapon in actor.weapons:
		# Every weapon gets its worn copy, the one in hand too, so a draw
		# can start from it.
		if weapon.visual != null and not actor.is_dead and not _stowed.has(weapon):
			_stowed[weapon] = _stow(weapon)
	# Riding, what is slung on the back moves up it, clear of the seat.
	var lift := ride_sling_lift * (smoothstep(0.0, 1.0, locomotion.ride_weight) if locomotion else 0.0)
	for weapon: Variant in _stowed:
		var root: Node3D = _stowed[weapon]
		if root == null or not root.get_meta("slung", false):
			continue
		var holder := root.get_node_or_null("Part") as Node3D
		if holder != null and holder.has_meta("rest"):
			var rest: Transform3D = holder.get_meta("rest")
			holder.transform = Transform3D(rest.basis, rest.origin + (holder.get_meta("up") as Vector3) * lift)


## Plays a weapon switch: the hand reaches to each holster in `_plan` in turn,
## a weapon put away goes onto the body as the hand arrives, and one drawn
## leaves the body and comes back with the hand. Then shows each weapon in
## its place: the one in hand on the hand, the rest where they are worn.
func _update_switch(delta: float) -> void:
	var active := actor.get_active_weapon()
	# Flying flat with the arms at the sides, the weapon is worn, not left
	# hanging in the air where the hands were. Shooting or aiming draws it.
	if flies_stowed():
		active = null
	if _in_hand != null and (not is_instance_valid(_in_hand) or not _in_hand in actor.weapons):
		_in_hand = null
	_moving = null
	_moving_weight = 0.0
	var instant := arm == null or actor.hand_override or actor.is_dead or _skeleton == null
	if instant or (_plan.is_empty() and _in_hand == active):
		_in_hand = active
		_plan_for = active
		_plan.clear()
	elif _plan_for != active or _plan.is_empty():
		# A new switch, or a change of mind halfway: go from what is in hand.
		_plan.clear()
		for weapon in [_in_hand, active]:
			if weapon != null and _stowed_models.get(weapon) != null and not weapon in _plan:
				_plan.append(weapon)
		_plan_for = active
		_plan_t = 0.0
		if _plan.is_empty():
			_in_hand = active
	if not _plan.is_empty():
		_plan_t += delta
		_play_plan()
	if arm:
		arm.override_weight = _moving_weight if _moving else 0.0
		if _moving:
			arm.override_point = _hand_at_holster(_moving)
	for weapon in actor.weapons:
		if weapon.visual:
			weapon.visual.visible = weapon == _in_hand
		var worn: Node3D = _stowed.get(weapon)
		if worn:
			worn.visible = weapon != _in_hand and weapon.visual != null and not actor.is_dead
	_update_fold(delta)


## A blade slides out of its hilt once it is in hand and back in as the hand
## takes it to put it away, so it is worn folded (see `_stow`). A weapon
## already in hand when first seen starts out.
func _update_fold(delta: float) -> void:
	for weapon in actor.weapons:
		if not weapon is MeleeWeapon or weapon.visual == null:
			continue
		var held: Node3D = weapon.visual.get_node_or_null("Model")
		if held == null:
			continue
		var target := 1.0 if weapon == _in_hand and (_plan.is_empty() or weapon == _plan_for) else 0.0
		var now: float = _extend.get(weapon, -1.0)
		var next := target if now < 0.0 else move_toward(now, target, delta / fold_time)
		if next != now:
			look.set_extend(held, next)
			_extend[weapon] = next


## Where the plan has got to at `_plan_t`: which weapon the hand is with,
## how far toward its holster, and what has changed hands on the way.
func _play_plan() -> void:
	var arrive: Array[float] = []
	for i in _plan.size():
		arrive.append(reach_time + between_time * i)
	var last := arrive[arrive.size() - 1]
	for i in _plan.size():
		if _plan_t >= arrive[i]:
			var weapon := _plan[i]
			# Arriving at a holster: put the weapon away, or take it out.
			if weapon == _in_hand and weapon != _plan_for:
				_in_hand = null
			elif weapon == _plan_for:
				_in_hand = weapon
	if _plan_t >= last + return_time:
		_plan.clear()
		_in_hand = _plan_for
		return
	if _plan_t < arrive[0]:
		_moving = _plan[0]
		_moving_weight = smoothstep(0.0, reach_time, _plan_t)
	elif _plan_t < last:
		var i := int((_plan_t - reach_time) / between_time)
		var u := (_plan_t - arrive[i]) / between_time
		# Between two holsters the hand carries nothing it has not put away.
		_moving = _plan[i + 1] if u > 0.5 else _plan[i]
		_moving_weight = 1.0
	else:
		_moving = _plan[_plan.size() - 1]
		_moving_weight = 1.0 - smoothstep(last, last + return_time, _plan_t)


## Where the weapon hand goes to take a weapon from its holster: the spot its
## hand point has in the worn copy, in the actor's frame.
func _hand_at_holster(weapon: Weapon) -> Vector3:
	var model: Node3D = _stowed_models.get(weapon)
	var held: Node3D = weapon.visual.get_node_or_null("Model") if weapon.visual else null
	if model == null or held == null or not model.is_inside_tree():
		return Actor.HAND_REST
	var hand: Transform3D = model.global_transform * held.transform.affine_inverse()
	return actor.global_transform.affine_inverse() * hand.origin


## After the hand is placed each frame: the weapon moving between hand and
## holster is turned and carried from how it is held toward how it is worn,
## so it lands exactly in place when the hand gets there.
func _carry_moving() -> void:
	for weapon in actor.weapons:
		var held: Node3D = weapon.visual.get_node_or_null("Model") if weapon.visual else null
		if held == null:
			continue
		if not held.has_meta("held_at"):
			held.set_meta("held_at", held.transform)
		var base: Transform3D = held.get_meta("held_at")
		var worn: Node3D = _stowed_models.get(weapon)
		if weapon != _moving or worn == null or _moving_weight <= 0.0 or not worn.is_inside_tree():
			held.transform = base
			continue
		var from := weapon.visual.global_transform * base
		held.global_transform = from.interpolate_with(worn.global_transform, _moving_weight)


func _clear_stowed() -> void:
	for weapon: Variant in _stowed:
		if _stowed[weapon]:
			_stowed[weapon].queue_free()
	_stowed.clear()
	_stowed_models.clear()


## Where a holstered weapon is worn: {"bone", "at" (from the bone, actor
## frame), "basis" (turns the model from how it is held), "centre" (true to
## hang it by its middle rather than its grip)}.
func stow_place(weapon: Weapon) -> Dictionary:
	var back_bone: String = _def.get("back_bone", "")
	var out := Vector3(0.0, sling_height, back_surface + sling_clearance)
	if _rig_back:
		var box: AABB = look.model_bounds(_rig_back)
		out.z = back_gap + box.end.z + sling_clearance
	if weapon is MeleeWeapon and not look.is_two_handed(weapon):
		# Blades stand along +Y with the grip at the origin: tip it down and
		# back from the hip, grip up by the belt.
		return {"bone": _def.get("hip_bone", ""), "at": hip_offset, "basis": Basis(Vector3.RIGHT, sheath_angle),
			"centre": false}
	if is_sidearm(weapon):
		# Muzzle down, grip to the rear, its side to the world.
		return {"bone": _def.get("hip_bone", ""), "at": holster_offset, "basis": Basis(Vector3.RIGHT, -PI / 2.0),
			"centre": false}
	if weapon is MeleeWeapon:
		# Head up over the left shoulder, crossing a slung gun.
		return {"bone": back_bone, "at": out + Vector3(0, 0, sling_clearance), "basis": Basis(Vector3.BACK, sling_tilt),
			"centre": true}
	# Guns point along -Z in the hand, top up: roll it onto its side so its
	# profile shows, stand it muzzle up, then lean it over the right shoulder.
	return {"bone": back_bone, "at": out,
		"basis": Basis(Vector3.BACK, -sling_tilt) * Basis(Vector3.RIGHT, PI / 2.0) * Basis(Vector3.BACK, PI / 2.0),
		"centre": true}


## A small gun worn in a hip holster rather than slung (`Weapon.is_sidearm`).
static func is_sidearm(weapon: Weapon) -> bool:
	return weapon is Gun and (weapon.is_sidearm or (weapon.item_id != "" and ItemDB.has_tag(weapon.item_id, "sidearm")))


## Builds the worn copy of a holstered weapon. Purely a view: the weapon's own
## node stays on the actor's hand, hidden.
func _stow(weapon: Weapon) -> Node3D:
	var model: Node3D = look.weapon_model(weapon)
	if model == null:
		return null
	# Worn folded away, so a blade does not stick out from the hip.
	look.set_extend(model, 0.0)
	var place := stow_place(weapon)
	var pivot := Node3D.new()
	pivot.add_child(model)
	if place["centre"]:
		model.position -= look.folded_bounds(model).get_center()
	pivot.basis = place["basis"]
	var fallback: Vector3 = Vector3(0.0, _def.get("height", 1.8) * 0.7, 0.0) + place["at"]
	var root := _hang(pivot, "Stowed" + str(actor.weapons.find(weapon)), place["bone"], place["at"], fallback)
	root.set_meta("slung", place["centre"])
	_stowed_models[weapon] = model
	return root


func _on_fired(from: Vector3, to: Vector3, gun: Gun) -> void:
	_aim_left = aim_hold
	var parent := actor.get_parent()
	if parent == null:
		return
	var muzzle := from + (to - from).normalized() * 0.9
	if gun.visual and gun.visual.is_inside_tree():
		muzzle = gun.visual.global_transform * Vector3(0, -0.04, -0.5)
	if not gun.quiet:
		Vfx.muzzle_flash(parent, muzzle, (to - from).normalized())
	if from.distance_to(to) < gun.max_range - 0.5:
		Vfx.impact(parent, to, (from - to).normalized())


func _on_hit_confirmed(target: Actor, info: DamageInfo, _lethal: bool) -> void:
	if target == null or not is_instance_valid(target) or info.kind == "bullet":
		return
	var parent := actor.get_parent()
	if parent:
		var at := target.global_position + Vector3(0, 1.1, 0)
		Vfx.impact(parent, at, (actor.global_position - target.global_position).normalized(), info.blocked or info.parried)


func _on_damaged(_info: DamageInfo) -> void:
	_flash_left = 0.07
	_set_flash(0.8)


func _set_flash(amount: float) -> void:
	for mat in _materials:
		mat.set_shader_parameter("flash", amount)


## Keeps the worn flight rig in step with the actor: puts on the model of
## whatever rig is equipped, burns the nozzles while it thrusts or just after
## an air jump, and spreads the wings while gliding.
func _update_rig(delta: float) -> void:
	var id := actor.flight.item_id if actor.flight.enabled else ""
	if id != _rig_id:
		_wear_rig(id)
	if _rig_holders.is_empty():
		return
	_burst_left = maxf(0.0, _burst_left - delta)
	var burning := not actor.is_dead and (actor.flight.is_thrusting or actor.flight.is_skimming or _burst_left > 0.0)
	for flame in _flames:
		flame.visible = burning
	if _rig_back and _rig_back.has_node("WingL"):
		var want := 1.0 if actor.flight.is_gliding and not actor.is_dead else 0.0
		var was := _spread
		_spread = move_toward(_spread, want, wing_speed * delta)
		if _spread != was or _spread > 0.0:
			RigModel.set_wing_spread(_rig_back, _spread, clampf(-_bank / max_bank, -1.0, 1.0), actor.glide_trim())


## Sets the whole model's attitude in the air, about the actor's middle.
## Gliding or boosting it lies flat along the way it flies (nose down in a
## dive, up in a climb), turned to face that way and banked into the turn.
## Hovering it leans the way it drifts. The roll keys twist it round. All of
## it is read from velocity and the command, so remote players match.
## The arms and legs are posed by `_pose_glide`, last in the skeleton's order.
func _update_glide(delta: float) -> void:
	var alive := not actor.is_dead and actor.vehicle == null
	var flat := alive and (actor.flight.is_gliding or actor.flight.is_boosting)
	_glide = move_toward(_glide, 1.0 if flat else 0.0, glide_blend * delta)
	_boost = move_toward(_boost, 1.0 if alive and actor.flight.is_boosting else 0.0, glide_blend * delta)

	var local := actor.global_basis.inverse() * actor.velocity
	var level := Vector3(local.x, 0.0, local.z)
	var speed := level.length()
	var dir := level / speed if speed > 0.5 else Vector3.FORWARD
	var tilt := Vector3.ZERO
	var face := 0.0
	var bank := 0.0
	if flat:
		var path := atan2(actor.velocity.y, maxf(speed, 0.5)) if actor.velocity.length() > 1.0 else 0.0
		var lie := glide_pitch if actor.flight.is_gliding else PI / 2.0
		if speed <= 0.5:
			dir = Vector3.FORWARD
		tilt = dir * clampf(lie - path, 0.0, PI * 0.95)
		face = Locomotion.heading(dir)
		# Bank for the turn being flown: how fast the heading is swinging.
		var heading := atan2(-actor.velocity.x, -actor.velocity.z)
		if _has_heading and speed > 2.0 and delta > 0.0:
			var rate := wrapf(heading - _last_heading, -PI, PI) / delta
			bank = clampf(atan(speed * rate / 9.8), -max_bank, max_bank)
		_last_heading = heading
		_has_heading = speed > 2.0
	else:
		_has_heading = false
		if alive and actor.flight.is_hovering:
			tilt = dir * hover_lean * clampf(speed / maxf(actor.flight.fly_speed, 0.1), 0.0, 1.0)
		elif alive and _air > 0.0 and is_airborne():
			# A running jump leans into it, and rights itself for the landing.
			tilt = dir * leap_lean * clampf(speed / leap_lean_speed, 0.0, 1.0) * (1.0 - _air_fall)
	var follow := 1.0 - exp(-attitude_follow * delta)
	_tilt = _tilt.lerp(tilt, follow)
	_face = lerp_angle(_face, face, follow)
	_bank = lerpf(_bank, bank, 1.0 - exp(-bank_follow * delta))
	# The roll keys: held, the body keeps turning; let go, it rights itself
	# the short way round.
	if flat and actor.cmd.roll != 0:
		_twist += actor.cmd.roll * twist_speed * delta
	else:
		_twist = wrapf(_twist, -PI, PI)
		_twist = move_toward(_twist, 0.0, twist_speed * delta)

	var angle := _tilt.length()
	var tip := Basis(Vector3.UP.cross(_tilt / angle).normalized(), angle) if angle > 0.001 else Basis.IDENTITY
	# A positive bank or twist rolls to the right: right side down.
	var turn := tip * Basis(Vector3.UP, _face - _bank + _twist)
	var pivot := Vector3(0, glide_pivot, 0)
	transform = Transform3D(turn * Basis(Vector3.UP, PI), pivot - turn * pivot)
	var seated: Variant = ride_frame()
	if seated != null and locomotion != null and locomotion.ride_weight > 0.0:
		transform = transform.interpolate_with(seated, smoothstep(0.0, 1.0, locomotion.ride_weight))


## Tells the legs' riding pose what is being ridden and what the hands may do:
## the left hand always takes its grip, the right one only while nothing is
## in it (holster with Z to ride with both hands). The head turns to the aim.
func _update_ride() -> void:
	var vehicle: Node3D = actor.vehicle if not actor.is_dead else null
	locomotion.ride = vehicle
	if arm:
		arm.ride_grip = locomotion.grip_hold()
	if vehicle == null:
		return
	var free := _in_hand == null and _plan.is_empty()
	locomotion.ride_hands = Vector2(1.0, 1.0 if free else 0.0)
	# A gun in hand is held out toward the aim, where it would be on foot.
	var gun := _in_hand as Gun
	locomotion.ride_gun_wrist = null
	if gun != null and _plan.is_empty() and not actor.hand_override:
		var aim := Basis(Vector3.RIGHT, actor.cmd.pitch)
		locomotion.ride_gun_wrist = actor.global_transform * (Actor.HAND_REST + aim * ride_gun_wrist)
	locomotion.ride_turn = clampf(wrapf(actor.global_rotation.y - vehicle.global_rotation.y, -PI, PI), -ride_head_turn, ride_head_turn)


## Where the model goes while riding, in the actor's frame: facing along the
## vehicle rather than the aim, and tipped with the bike's lean and pitch
## about its wheels. Null on foot. The vehicle carries the actor at its
## `seat_offset`, so that is where the model's feet start from.
func ride_frame() -> Variant:
	var vehicle: Node3D = locomotion.get("_ride_on") if locomotion else null
	if vehicle == null or not is_instance_valid(vehicle) or not vehicle.is_inside_tree():
		return null
	var model := vehicle.get_node_or_null("Model") as Node3D
	var frame: Transform3D = model.global_transform if model else vehicle.global_transform
	var offset: Vector3 = vehicle.get("seat_offset")
	return actor.global_transform.affine_inverse() * frame * Transform3D(Basis(Vector3.UP, PI), offset)


func _setup_glide_pose(skeleton: Skeleton3D, def: Dictionary) -> void:
	var arm_bones := {"L": ["UpperArm.L", "LowerArm.L", "Wrist.L"], "R": ["UpperArm.R", "LowerArm.R", "Wrist.R"]}
	for side: String in ["L", "R"]:
		var chain: Array = def.get("off_arm" if side == "L" else "arm", arm_bones[side])
		_glide_arms.append(_bone_chain(skeleton, chain, -1.0 if side == "L" else 1.0))
	var feet: Array = def.get("feet", [])
	for i in feet.size():
		var foot := String(feet[i])
		var suffix := foot.get_slice(".", 1)
		_glide_legs.append(_bone_chain(skeleton, ["UpperLeg." + suffix, "LowerLeg." + suffix, foot], -1.0 if i == 0 else 1.0))
	_glide_neck = skeleton.find_bone(def.get("neck", ""))
	var hook := WeaponArm.Hook.new()
	hook.name = "GlidePose"
	hook.run = _pose_glide
	skeleton.add_child(hook)


## [bones..., side] for a limb, or [] if the skeleton lacks any of them.
func _bone_chain(skeleton: Skeleton3D, names: Array, side: float) -> Array:
	var out := []
	for bone_name: String in names:
		var bone := skeleton.find_bone(bone_name)
		if bone < 0:
			return []
		out.append(bone)
	out.append(side)
	return out


## Straightens the limbs into the flying pose, blended by how far into it
## the body is. Runs after the animation, the legs and the weapon arm.
func _pose_glide() -> void:
	if _skeleton == null:
		return
	_pose_air()
	if _glide <= 0.0:
		return
	var w := smoothstep(0.0, 1.0, _glide)

	# From the body's own frame (before the tip) to the skeleton's.
	# The skin faces the model's way, turned half round from the actor.
	var to_skeleton := _skeleton.basis.orthonormalized().inverse() * _model_basis_inverse() * Basis(Vector3.UP, PI)
	var right := (to_skeleton * Vector3.RIGHT).normalized()
	for limb: Array in _glide_arms:
		if limb.is_empty():
			continue
		var arm_dir := glide_arm.lerp(boost_arm, smoothstep(0.0, 1.0, _boost))
		var wanted := to_skeleton * Vector3(arm_dir.x * limb[3], arm_dir.y, arm_dir.z)
		# Shooting or aiming, the arms keep their hold on the weapon.
		var arm_w := w * (1.0 - smoothstep(0.0, 1.0, _flight_hold))
		_aim_bone(limb[0], limb[1], wanted, arm_w)
		_aim_bone(limb[1], limb[2], wanted, arm_w)
	for limb: Array in _glide_legs:
		if not limb.is_empty():
			_pose_leg(limb, to_skeleton * Vector3(glide_leg.x * limb[3], glide_leg.y, glide_leg.z), right, w)
	if _glide_neck >= 0:
		var pose := _skeleton.get_bone_global_pose(_glide_neck)
		pose.basis = Basis((to_skeleton * Vector3.RIGHT).normalized(), glide_look * w) * pose.basis
		_skeleton.set_bone_global_pose(_glide_neck, pose)


## Bends the legs into the air pose. The flat flying pose, applied after,
## takes over as the body lies out.
func _pose_air() -> void:
	var w := smoothstep(0.0, 1.0, _air) * (1.0 - smoothstep(0.0, 1.0, _glide))
	if w <= 0.0:
		return
	var to_skeleton := _skeleton.basis.orthonormalized().inverse() * _model_basis_inverse() * Basis(Vector3.UP, PI)
	var right := (to_skeleton * Vector3.RIGHT).normalized()
	for i in _glide_legs.size():
		var limb: Array = _glide_legs[i]
		if limb.is_empty():
			continue
		var at := mini(i, 1) * 2
		var push := smoothstep(0.0, 1.0, _air_push)
		var thigh: Vector3 = (leap_legs[at] as Vector3).lerp(fall_legs[at], _air_fall).lerp(hang_legs[at], _air_hang) \
				.lerp(push_legs[at], push)
		var shin: Vector3 = (leap_legs[at + 1] as Vector3).lerp(fall_legs[at + 1], _air_fall).lerp(hang_legs[at + 1], _air_hang) \
				.lerp(push_legs[at + 1], push)
		_pose_leg(limb, to_skeleton * Vector3(thigh.x * limb[3], thigh.y, thigh.z), right, w,
				to_skeleton * Vector3(shin.x * limb[3], shin.y, shin.z), lerpf(air_toes, push_toes, push))


## Lays a leg along `dir`, or bends it: the thigh along `dir` and the shin
## along `shin_dir` when one is given. The human rig's foot is an IK handle
## under the root, not a child of the shin, so it is carried to the end of
## the shin by hand, turned with it and pointed by `toes` radians.
func _pose_leg(limb: Array, dir: Vector3, right: Vector3, w: float, shin_dir := Vector3.ZERO, toes := -1.0) -> void:
	if shin_dir == Vector3.ZERO:
		shin_dir = dir
	if toes < 0.0:
		toes = glide_toes
	var shin := _skeleton.get_bone_global_pose(limb[1])
	var foot := _skeleton.get_bone_global_pose(limb[2])
	var reach := foot.origin - shin.origin
	# The shin's line to the foot, held in the shin's own frame.
	var along := shin.basis.inverse() * reach
	_aim_bone(limb[0], limb[1], dir, w)
	shin = _skeleton.get_bone_global_pose(limb[1])
	var now := shin.basis * along
	if now.length_squared() < 0.000001:
		return
	var turn := Quaternion.IDENTITY.slerp(Quaternion(now.normalized(), shin_dir.normalized()), w)
	shin.basis = Basis(turn) * shin.basis
	_skeleton.set_bone_global_pose(limb[1], shin)
	# Turn the foot as the shin turned in all, then point the toes.
	var whole := Quaternion(reach.normalized(), (Basis(turn) * now).normalized())
	foot.origin = shin.origin + Basis(turn) * now
	foot.basis = Basis(right, toes * w) * Basis(whole) * foot.basis
	_skeleton.set_bone_global_pose(limb[2], foot)


## From this skin's space to the skeleton's parent, turns only.
func _model_basis_inverse() -> Basis:
	var up := _skeleton.get_parent()
	var basis := Basis.IDENTITY
	while up != null and up != self:
		if up is Node3D:
			basis = (up as Node3D).basis.orthonormalized() * basis
		up = up.get_parent()
	return basis.inverse()


## Turns `bone` (in the skeleton's space) so its child lies along `dir`.
func _aim_bone(bone: int, child: int, dir: Vector3, weight: float) -> void:
	var pose := _skeleton.get_bone_global_pose(bone)
	var now := _skeleton.get_bone_global_pose(child).origin - pose.origin
	if now.length_squared() < 0.000001:
		return
	var turn := Quaternion(now.normalized(), dir.normalized())
	pose.basis = Basis(Quaternion.IDENTITY.slerp(turn, weight)) * pose.basis
	_skeleton.set_bone_global_pose(bone, pose)


func _on_burst() -> void:
	_burst_left = burst_burn


## Swaps the rig model for the one `id` needs ("" takes it off).
func _wear_rig(id: String) -> void:
	_rig_id = id
	for holder in _rig_holders:
		holder.queue_free()
	_rig_holders.clear()
	_flames.clear()
	_rig_back = null
	_spread = 0.0
	if id == "":
		return
	var back := RigModel.build_back(id)
	if back:
		_rig_back = back
		_wear_part(back, _def.get("back_bone", ""), Vector3(0, back_drop, back_gap), Vector3(0, _def.get("height", 1.8) * 0.74, back_gap + 0.06))
	var feet: Array = _def.get("feet", [])
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var boot := RigModel.build_boot(id, side)
		if boot == null:
			continue
		var bone: String = feet[i] if feet.size() == 2 else ""
		_wear_part(boot, bone, boot_offset, Vector3(side * 0.12, 0.1, 0.0))
	var lit := false
	for holder in _rig_holders:
		for nozzle in RigModel.nozzles(holder):
			var size: Vector2 = nozzle.get_meta("flame", Vector2(0.05, 0.5))
			var flame := Vfx.nozzle_flame(size.x, size.y, not lit)
			lit = true
			flame.visible = false
			nozzle.add_child(flame)
			_flames.append(flame)


## Hangs a rig part on a bone so it moves with the body (see `_hang`).
func _wear_part(part: Node3D, bone_name: String, offset: Vector3, fallback: Vector3) -> void:
	look._weather_model(part, 0.5, 0.6)
	_rig_holders.append(_hang(part, "Rig" + part.name, bone_name, offset, fallback))


## Hangs a part on a bone so it moves with the body, and returns the node to
## free to take it off. Parts are built in meters for a wearer facing the
## actor's way; this undoes the model's scale and turn so they come out that
## way. `offset` is from the bone, in the actor's frame. Skins without the
## bone get the part at `fallback` (actor frame), fixed to the body.
func _hang(part: Node3D, holder_name: String, bone_name: String, offset: Vector3, fallback: Vector3) -> Node3D:
	var bone := _skeleton.find_bone(bone_name) if _skeleton and bone_name != "" else -1
	var holder := Node3D.new()
	holder.name = holder_name
	holder.add_child(part)
	var to_actor := actor.global_transform.affine_inverse()
	if bone < 0:
		add_child(holder)
		holder.transform = global_transform.affine_inverse() * actor.global_transform * Transform3D(Basis.IDENTITY, fallback)
		return holder
	var attach := BoneAttachment3D.new()
	attach.name = holder_name
	attach.bone_name = bone_name
	_skeleton.add_child(attach)
	attach.add_child(holder)
	holder.name = "Part"
	# Where the bone sits at rest, as the actor sees it, and where the part goes.
	var bone_at := to_actor * _skeleton.global_transform * _skeleton.get_bone_global_rest(bone)
	var want := Transform3D(Basis.IDENTITY, bone_at.origin + offset)
	holder.transform = bone_at.affine_inverse() * want
	# What moving the part up the body (actor frame) is, in the holder's parent.
	holder.set_meta("rest", holder.transform)
	holder.set_meta("up", bone_at.basis.inverse() * Vector3.UP)
	return attach