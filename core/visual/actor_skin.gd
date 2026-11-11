extends Node3D
## The model an actor wears. Added by `Look` as a child of the Actor; the
## Actor itself never knows about it. It reads the actor's state each frame
## and plays the matching animation, swaps greybox weapon parts for models,
## and plays the effects for shots and hits.

const Vfx := preload("res://core/visual/vfx.gd")
const WeaponArm := preload("res://core/visual/weapon_arm.gd")
const RigModel := preload("res://core/visual/rig_model.gd")

## How far behind the back bone a back-worn rig sits, and how far the boots
## sit above and behind the ankle bone, in meters.
var back_gap := 0.11
var back_drop := -0.02
var boot_offset := Vector3(0, 0.0, 0.0)
## How fast wings spread and fold, in full swings per second.
var wing_speed := 3.5
## How long nozzles burn after an air jump, in seconds.
var burst_burn := 0.3

var look: Node
var actor: Actor

var _player: AnimationPlayer
var _anims := {}
var _current := ""
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
var _attack_left := 0.0
## Makes the model hold its weapon, or null for skins without the bones.
var arm: Node

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
	if skeleton and def.has("grip_bone"):
		arm = WeaponArm.new()
		arm.name = "WeaponArm"
		arm.actor = actor
		arm.skeleton = skeleton
		arm.look = look
		add_child(arm)
		arm.setup(def, _player.get_animation(_anims["idle_melee"]) if _player and _anims.has("idle_melee") else null)

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


func _play(key: String, speed := 1.0) -> void:
	if _player == null or not _anims.has(key):
		return
	if _current == key:
		_player.speed_scale = speed
		return
	_current = key
	_player.play(_anims[key], 0.15, speed)


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
	var weapon := actor.get_active_weapon()
	var melee := weapon as MeleeWeapon
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
	var flat := Vector2(actor.velocity.x, actor.velocity.z).length()
	# With a gun out the arm stays up, so the gun keeps pointing where it shoots.
	var armed := weapon != null and melee == null and _anims.has("move_gun")
	if actor.vehicle != null:
		_play("idle")
	elif flat > 0.4 and armed:
		_play("move_gun", clampf(flat / 7.0, 0.45, 1.6))
	elif flat > actor.walk_speed + 0.5:
		_play("run", clampf(flat / 7.0, 0.8, 1.6))
	elif flat > 0.4:
		_play("walk", clampf(flat / 2.5, 0.7, 2.2))
	elif melee and _anims.has("idle_melee"):
		_play("idle_melee")
	else:
		_play("idle")


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
		if _spread != was:
			RigModel.set_wing_spread(_rig_back, _spread)


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
