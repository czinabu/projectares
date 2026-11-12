extends Node3D
## The model an actor wears. Added by `Look` as a child of the Actor; the
## Actor itself never knows about it. It reads the actor's state each frame
## and plays the matching animation, swaps greybox weapon parts for models,
## and plays the effects for shots and hits.

const Vfx := preload("res://core/visual/vfx.gd")
const WeaponArm := preload("res://core/visual/weapon_arm.gd")
const Locomotion := preload("res://core/visual/locomotion.gd")
## Clips that loop and are cut between in step, keeping the stride's phase.
const GAITS: Array[String] = ["walk", "run", "run_back", "run_left", "run_right", "move_gun"]

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
var _thrust: Node3D
var _attack_left := 0.0
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
	var skeleton := model.find_child("Skeleton3D", true, false) as Skeleton3D
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
	_current = key
	_player.play(_anims[key], 0.2 if phase >= 0.0 else 0.15)
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
	_update_thrust()
	var weapon := actor.get_active_weapon()
	var melee := weapon as MeleeWeapon
	if locomotion == null:
		return
	locomotion.update(delta)
	locomotion.twist_target = 0.0
	locomotion.overlay = false
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
	var gait: Dictionary = {} if actor.vehicle != null else \
			locomotion.choose(locomotion.velocity, armed, _current, _current_sign)
	if actor.vehicle != null:
		_play("idle")
	elif not gait.is_empty():
		_play(gait["key"], gait["speed"])
		locomotion.twist_target = gait["twist"]
		locomotion.overlay = armed and gait["key"] != "move_gun"
		if _player and _player.current_animation_length > 0.0:
			locomotion.overlay_phase = _player.current_animation_position / _player.current_animation_length
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


func _update_thrust() -> void:
	var on := actor.flight.is_thrusting and not actor.is_dead
	if on and _thrust == null:
		_thrust = Vfx.thruster()
		_thrust.position = Vector3(0, 1.0, -0.28)
		add_child(_thrust)
	if _thrust:
		_thrust.visible = on
