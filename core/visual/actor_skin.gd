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
## A jetpack boost flies the same way with the arms out ahead, like a diver's.
var boost_arm := Vector3(0.16, 1.0, -0.12)
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
## 0 arms trailing (wings), 1 arms ahead (boost).
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
	_update_rig(delta)
	_update_glide(delta)
	_aim_left = maxf(_aim_left - delta, 0.0)
	var weapon := actor.get_active_weapon()
	var melee := weapon as MeleeWeapon
	if locomotion == null:
		return
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
	if actor.vehicle != null or _glide > 0.0:
		_play("idle")
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
		elif weapon is MeleeWeapon:
			look.restyle_melee(weapon.visual)


func _on_fired(from: Vector3, to: Vector3, gun: Gun) -> void:
	_aim_left = aim_hold
	var parent := actor.get_parent()
	if parent == null:
		return
	var muzzle := from + (to - from).normalized() * 0.9
	if gun.visual and gun.visual.is_inside_tree():
		muzzle = gun.visual.global_transform * Vector3(0, -0.04, -0.5)
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
	var burning := not actor.is_dead and (actor.flight.is_thrusting or _burst_left > 0.0)
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
	var follow := 1.0 - exp(-attitude_follow * delta)
	_tilt = _tilt.lerp(tilt, follow)
	_face = lerp_angle(_face, face, follow)
	_bank = lerpf(_bank, bank, 1.0 - exp(-bank_follow * delta))
	# The roll keys: held, the body keeps turning; let go, it rights itself
	# the short way round.
	var in_air := alive and (flat or actor.flight.is_hovering)
	if in_air and actor.cmd.roll != 0:
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
	if _glide <= 0.0 or _skeleton == null:
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
		_aim_bone(limb[0], limb[1], wanted, w)
		_aim_bone(limb[1], limb[2], wanted, w)
	for limb: Array in _glide_legs:
		if not limb.is_empty():
			_pose_leg(limb, to_skeleton * Vector3(glide_leg.x * limb[3], glide_leg.y, glide_leg.z), right, w)
	if _glide_neck >= 0:
		var pose := _skeleton.get_bone_global_pose(_glide_neck)
		pose.basis = Basis((to_skeleton * Vector3.RIGHT).normalized(), glide_look * w) * pose.basis
		_skeleton.set_bone_global_pose(_glide_neck, pose)


## Straightens a leg along `dir`. The human rig's foot is an IK handle under
## the root, not a child of the shin, so it is carried to the end of the
## straightened shin by hand, turned with it and pointed.
func _pose_leg(limb: Array, dir: Vector3, right: Vector3, w: float) -> void:
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
	var turn := Quaternion.IDENTITY.slerp(Quaternion(now.normalized(), dir.normalized()), w)
	shin.basis = Basis(turn) * shin.basis
	_skeleton.set_bone_global_pose(limb[1], shin)
	# Turn the foot as the shin turned in all, then point the toes.
	var whole := Quaternion(reach.normalized(), (Basis(turn) * now).normalized())
	foot.origin = shin.origin + Basis(turn) * now
	foot.basis = Basis(right, glide_toes * w) * Basis(whole) * foot.basis
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


## Hangs a rig part on a bone so it moves with the body. Parts are built in
## meters for a wearer facing the actor's way; this undoes the model's scale
## and turn so they come out that way. `offset` is from the bone, in the
## actor's frame. Skins without the bone get the part at `fallback` (actor
## frame), fixed to the body.
func _wear_part(part: Node3D, bone_name: String, offset: Vector3, fallback: Vector3) -> void:
	look._weather_model(part, 0.5, 0.6)
	var bone := _skeleton.find_bone(bone_name) if _skeleton and bone_name != "" else -1
	var holder := Node3D.new()
	holder.name = "Rig" + part.name
	holder.add_child(part)
	var to_actor := actor.global_transform.affine_inverse()
	if bone < 0:
		add_child(holder)
		holder.transform = global_transform.affine_inverse() * actor.global_transform * Transform3D(Basis.IDENTITY, fallback)
		_rig_holders.append(holder)
		return
	var attach := BoneAttachment3D.new()
	attach.name = "Rig" + part.name
	attach.bone_name = bone_name
	_skeleton.add_child(attach)
	attach.add_child(holder)
	holder.name = "Part"
	# Where the bone sits at rest, as the actor sees it, and where the part goes.
	var bone_at := to_actor * _skeleton.global_transform * _skeleton.get_bone_global_rest(bone)
	var want := Transform3D(Basis.IDENTITY, bone_at.origin + offset)
	holder.transform = bone_at.affine_inverse() * want
	_rig_holders.append(attach)
