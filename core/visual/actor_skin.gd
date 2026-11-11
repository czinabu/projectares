extends Node3D
## The model an actor wears. Added by `Look` as a child of the Actor; the
## Actor itself never knows about it. It reads the actor's state each frame
## and plays the matching animation, swaps greybox weapon parts for models,
## and plays the effects for shots and hits.

const Vfx := preload("res://core/visual/vfx.gd")
const CHARACTER_SHADER := preload("res://assets/shaders/character.gdshader")

## From the grip bone to where the weapon's handle sits, in the hand's space.
var grip_offset := Vector3(0.0, 0.0, 0.0)

var look: Node
var actor: Actor

var _player: AnimationPlayer
var _anims := {}
var _current := ""
var _weapons_seen := 0
var _flash_left := 0.0
var _materials: Array[ShaderMaterial] = []
var _thrust: Node3D
var _attack_left := 0.0
var _skeleton: Skeleton3D
var _grip_bone := -1


func _ready() -> void:
	var skin_name: String = actor.get_meta("look", look.DEFAULT_SKIN)
	var def: Dictionary = look.SKINS.get(skin_name, look.SKINS[look.DEFAULT_SKIN])
	var scenes: Array = def["scenes"]
	var path: String = look.CHARACTERS + scenes[hash(String(actor.name)) % scenes.size()]
	var model: Node3D = look._instance(path)
	if model == null:
		return
	add_child(model)
	# Pack models face +Z. Actors face -Z.
	rotation.y = PI
	for hidden: String in def.get("hide", []):
		var node := model.find_child(hidden, true, false) as Node3D
		if node:
			node.visible = false
	var tint: Color = def.get("tint", Color.WHITE)
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		for i in mesh_node.mesh.get_surface_count():
			var source := mesh_node.get_active_material(i) as BaseMaterial3D
			if source == null:
				continue
			var mat := ShaderMaterial.new()
			mat.shader = CHARACTER_SHADER
			if source.albedo_texture:
				mat.set_shader_parameter("base_tex", source.albedo_texture)
			mat.set_shader_parameter("base_color", source.albedo_color)
			mat.set_shader_parameter("tint", tint)
			for param: String in ["saturation", "brightness", "metal", "rough"]:
				if def.has(param):
					mat.set_shader_parameter(param, def[param])
			if source.emission_enabled:
				mat.set_shader_parameter("emission_color", source.emission * 2.5)
			mesh_node.set_surface_override_material(i, mat)
			_materials.append(mat)

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
	_stand(model, def["height"])
	_skeleton = model.find_child("Skeleton3D", true, false) as Skeleton3D
	if _skeleton and def.has("grip_bone"):
		_grip_bone = _skeleton.find_bone(def["grip_bone"])
		# After the pose is applied, so the weapon never trails the hand.
		_skeleton.skeleton_updated.connect(_hold_weapon)

	# The greybox capsule stays as the actor's body node, but draws nothing.
	if actor.body_mesh:
		actor.body_mesh.mesh = null
		for child in actor.body_mesh.get_children():
			if child is MeshInstance3D:
				child.visible = false
	actor.health.damaged.connect(_on_damaged)
	actor.hit_confirmed.connect(_on_hit_confirmed)


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
	if actor.weapons.size() != _weapons_seen:
		_dress_weapons()
	if _flash_left > 0.0:
		_flash_left -= delta
		if _flash_left <= 0.0:
			_set_flash(0.0)
	_update_thrust()
	if actor.is_dead:
		_play("death")
		return
	var weapon := actor.get_active_weapon()
	var melee := weapon as MeleeWeapon
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


## Puts the actor's hand node, which carries the weapon, on the model's hand.
## The controller owns the hand in first person, so this leaves it alone then.
## The actor resets the hand every physics tick and nothing in the simulation
## reads it, so this only changes what is drawn.
func _hold_weapon() -> void:
	if _grip_bone < 0 or actor.hand_override or actor.is_dead:
		return
	var grip: Vector3 = _skeleton.global_transform * _skeleton.get_bone_global_pose(_grip_bone).origin
	actor.hand.global_position = grip + actor.hand.global_basis * grip_offset


## Swaps greybox gun parts for a model and wires up shot effects. Runs again
## whenever the actor's weapon list changes.
func _dress_weapons() -> void:
	_weapons_seen = actor.weapons.size()
	for weapon in actor.weapons:
		if weapon.visual == null or weapon.visual.has_meta("dressed"):
			continue
		weapon.visual.set_meta("dressed", true)
		var gun := weapon as Gun
		if gun:
			var model: Node3D = look.weapon_model(gun)
			if model:
				for child in weapon.visual.get_children():
					if child is MeshInstance3D:
						child.visible = false
				weapon.visual.add_child(model)
			gun.fired.connect(_on_fired.bind(gun))
		else:
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


## Scales the model to `height` meters and puts its feet on the ground, going
## by where the skeleton's bones are in the idle pose. Mesh bounds are no use
## here: skinned meshes report their unposed size.
func _stand(model: Node3D, height: float) -> void:
	var skeleton := model.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		look._fit(model, "skin:" + model.name, height, true)
		return
	var to_skin := global_transform.affine_inverse() * skeleton.global_transform
	var low := INF
	var high := -INF
	for i in skeleton.get_bone_count():
		var y := (to_skin * skeleton.get_bone_global_pose(i).origin).y
		low = minf(low, y)
		high = maxf(high, y)
	if high - low < 0.001:
		return
	# Bones stop at the ankle and the base of the head; allow for both ends.
	var s := height / ((high - low) * 1.22)
	model.scale *= s
	model.position.y = -low * s + height * 0.06


func _update_thrust() -> void:
	var on := actor.flight.is_thrusting and not actor.is_dead
	if on and _thrust == null:
		_thrust = Vfx.thruster()
		_thrust.position = Vector3(0, 1.0, -0.28)
		add_child(_thrust)
	if _thrust:
		_thrust.visible = on
