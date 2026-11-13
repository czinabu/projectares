extends Node3D
## Your own arms and hands in first person, where the body is not drawn.
##
## A second copy of your character (same build, outfit and skin tone) hangs
## under the camera with only its torso part kept, so the arms that come into
## view are yours. It holds the clip of the weapon in hand (`aim_gun` for a
## gun, `idle_melee` for a blade) still, which shapes the fingers round the
## grip, and two-bone IK then brings the hands to wherever the controller put
## the weapon: the first-person hold that `ActionPose` moves the same way the
## third-person arm moves. The off hand rides on a gun's fore end or a
## two-handed blade's handle, and comes up to read the watch when it is
## raised, in place of the HUD's grey box forearm.
##
## View only, like the rest of `Look`: no collision, nothing reads it back,
## and it is only built when there is a screen and a skin with the bones.

const WeaponArm := preload("res://core/visual/weapon_arm.gd")

var look: Node
var actor: Actor
var camera: Camera3D

## Where the copy's head bone sits in the camera's space: just behind the
## eye, so the torso stays out of view and the shoulders are where yours are.
var head_at := Vector3(0.0, -0.02, 0.06)
## The shoulders are brought this far forward of the copy's chest (camera
## space), as a gun's stock pulls them in to the cheek: the chest stays out
## of view behind the eye and the arms come in from the edges of the view,
## long enough to hold a rifle's fore end.
var shoulder_shift := Vector3(0.0, 0.0, -0.2)
## Where the elbows point, in the camera's space.
var elbow := Vector3(0.7, -0.9, 0.2)
var off_elbow := Vector3(-0.7, -0.9, 0.2)
var elbow_cocked := Vector3(0.8, 0.2, 0.3)
## Raising the watch: where the left wrist comes up to, in the camera's
## space, at the reference field of view.
var watch_at := Vector3(-0.1, -0.2, -0.32)
## A sidearm is held with the off hand cupped under the grip: its clip offset
## from the weapon hand is shrunk by this much.
var sidearm_support := 0.35
## Where the off wrist sits from a gun's "ForeGrip" marker, in the gun's
## space (x right, y up, z back), so the palm comes up under the fore end.
var fore_wrist := Vector3(-0.03, -0.07, 0.06)
## How a blade is turned in the hand at rest (see `MeleeWeapon.REST_POSE`):
## the clip holds it that way, so poses are measured from it.
var blade_rest := Basis(Vector3.RIGHT, MeleeWeapon.REST_POSE)

var model: Node3D
var skeleton: Skeleton3D
var _player: AnimationPlayer
var _anims := {}
var _clip := ""
var _wrist := -1
var _off_wrist := -1
var _shoulders: Array[int] = []
var _grip := -1
var _ik: TwoBoneIK3D
var _off_ik: TwoBoneIK3D
var _target := Node3D.new()
var _pole := Node3D.new()
var _off_target := Node3D.new()
var _off_pole := Node3D.new()
## The wrist turns the hooks give the hands this frame, in the world.
var _wrist_turn := Basis.IDENTITY
var _off_turn := Basis.IDENTITY
var _off_weight := 0.0
var _watch := 0.0
## The watch on the copy's left wrist.
var _worn_watch: Node3D


## Builds the copy. False when there is no skin with arms to copy.
func build(skin_name: String, appearance: Dictionary) -> bool:
	var def: Dictionary = look.SKINS.get(skin_name, look.SKINS[look.DEFAULT_SKIN])
	var arm: Array = def.get("arm", [])
	var off_arm: Array = def.get("off_arm", [])
	if arm.size() != 3 or off_arm.size() != 3:
		return false
	var built: Dictionary = look.character(skin_name, appearance, String(actor.name))
	if built.is_empty():
		return false
	model = built["model"]
	add_child(model)
	# Pack models face +Z; the camera looks down -Z.
	model.rotation.y = PI
	skeleton = model.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		return false
	_wrist = skeleton.find_bone(arm[2])
	_off_wrist = skeleton.find_bone(off_arm[2])
	_grip = skeleton.find_bone(def.get("grip_bone", ""))
	for bone: String in [arm[0], off_arm[0]]:
		_shoulders.append(skeleton.find_bone(bone))
	if _wrist < 0 or _off_wrist < 0 or _grip < 0:
		return false
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Only the torso part carries the arms; the rest would only get in
		# the way of the view (or of the near plane).
		var slot: String = mesh.get_meta("slot", "body")
		if slot != "body":
			mesh.visible = false
	_player = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _player:
		for key: String in ["aim_gun", "idle_melee", "idle"]:
			var wanted: String = def.get("anims", {}).get(key, "")
			for found in _player.get_animation_list():
				if found == wanted or found.ends_with("/" + wanted):
					_anims[key] = found
		_hold_clip("idle")
	look.stand_model(self, model, def["height"])
	var head := skeleton.find_bone("Head")
	if head < 0:
		head = skeleton.find_bone(def.get("neck", ""))
	if head >= 0:
		var at := global_transform.affine_inverse() * (skeleton.global_transform * skeleton.get_bone_global_pose(head).origin)
		model.position += head_at - at
	for node: Node3D in [_target, _pole, _off_target, _off_pole]:
		add_child(node)
		node.top_level = true
	var measure := WeaponArm.Hook.new()
	measure.name = "Measure"
	measure.run = _measure
	skeleton.add_child(measure)
	_ik = _two_bone("ArmReach", arm, _target, _pole)
	_off_ik = _two_bone("OffArmReach", off_arm, _off_target, _off_pole)
	var wrists := WeaponArm.Hook.new()
	wrists.name = "Wrists"
	wrists.run = _turn_wrists
	skeleton.add_child(wrists)
	var attach := BoneAttachment3D.new()
	attach.name = "WornWatch"
	attach.bone_name = off_arm[2]
	skeleton.add_child(attach)
	_worn_watch = Hud.Wrist._watch()
	var s := skeleton.global_basis.get_scale()
	_worn_watch.scale = Vector3(1.0 / maxf(s.x, 0.001), 1.0 / maxf(s.y, 0.001), 1.0 / maxf(s.z, 0.001))
	attach.add_child(_worn_watch)
	return true


func _two_bone(ik_name: String, bones: Array, target: Node3D, pole: Node3D) -> TwoBoneIK3D:
	var ik := TwoBoneIK3D.new()
	ik.name = ik_name
	ik.setting_count = 1
	ik.set_root_bone_name(0, bones[0])
	ik.set_middle_bone_name(0, bones[1])
	ik.set_end_bone_name(0, bones[2])
	ik.influence = 1.0
	skeleton.add_child(ik)
	ik.set_target_node(0, ik.get_path_to(target))
	ik.set_pole_node(0, ik.get_path_to(pole))
	return ik


## Holds the first frame of a clip still: the fingers' grip and the arms'
## starting pose for the IK.
func _hold_clip(key: String) -> void:
	if _player == null or not _anims.has(key) or _clip == key:
		return
	_clip = key
	_player.play(_anims[key], 0.0)
	_player.seek(0.0, true)
	_player.pause()


## The weapon whose model is in the hand now, or null.
func held_visual() -> Node3D:
	var weapon := actor.get_active_weapon()
	if weapon != null and weapon.visual != null and weapon.visual.visible:
		return weapon.visual
	return null


## Called by the controller each frame after it has placed the hand.
## `shown` is whether first person is being drawn at all; `watch` how far
## the watch is raised (0..1); `toy` true while a toy vehicle is in the hand.
func update(shown: bool, watch: float, toy: bool) -> void:
	var weapon := actor.get_active_weapon()
	var held := held_visual()
	visible = shown and (held != null or toy or watch > 0.0)
	_watch = watch
	if not visible:
		return
	if weapon is MeleeWeapon:
		_hold_clip("idle_melee")
	elif held != null:
		_hold_clip("aim_gun")
	else:
		_hold_clip("idle")
	var two_handed: bool = held != null and (weapon is Gun or look.is_two_handed(weapon))
	_off_weight = 1.0 if two_handed else 0.0
	_ik.influence = 1.0 if held != null or toy else 0.0
	_off_ik.influence = maxf(_off_weight, watch)
	_worn_watch.visible = true


## Before the arms reach: where each hand goes this frame. The clip's hands
## are moved as one with the weapon, from how the clip holds it (weapon
## straight ahead) to how the weapon is held now.
func _measure() -> void:
	var cam := camera.global_transform
	var to_world := skeleton.global_transform
	var shift := to_world.basis.inverse() * (cam.basis * shoulder_shift)
	for bone in _shoulders:
		var at := skeleton.get_bone_global_pose(bone)
		at.origin += shift
		skeleton.set_bone_global_pose(bone, at)
	var anchor := actor.hand.global_transform.orthonormalized()
	var rest := cam.basis.orthonormalized()
	var held := held_visual()
	if held != null:
		anchor = held.global_transform.orthonormalized()
		if actor.get_active_weapon() is MeleeWeapon:
			rest = rest * blade_rest
	var turn := anchor.basis * rest.inverse()
	var wrist := to_world * skeleton.get_bone_global_pose(_wrist).origin
	var grip := to_world * skeleton.get_bone_global_pose(_grip).origin
	var wrist_basis := to_world.basis.orthonormalized() * skeleton.get_bone_global_pose(_wrist).basis.orthonormalized()
	var new_wrist := anchor.origin - turn * (grip - wrist)
	_target.global_position = new_wrist
	_wrist_turn = turn * wrist_basis
	# The elbow rides high with the arm cocked for a windup, as third person.
	var raise := ActionPose.of(actor).elbow_raise if actor.get_active_weapon() is MeleeWeapon else 0.0
	_pole.global_position = cam * elbow.lerp(elbow_cocked, raise)

	var off := to_world * skeleton.get_bone_global_pose(_off_wrist).origin
	var off_basis := to_world.basis.orthonormalized() * skeleton.get_bone_global_pose(_off_wrist).basis.orthonormalized()
	var weapon := actor.get_active_weapon()
	var off_at := new_wrist + turn * (off - wrist)
	var fore := held.get_node_or_null("ForeGrip") as Node3D if held != null else null
	if weapon is Gun and (weapon as Gun).is_sidearm:
		off_at = new_wrist + turn * ((off - wrist) * sidearm_support)
	elif weapon is Gun and fore != null:
		# The palm under the fore end: the wrist sits a hand's width below
		# and behind it.
		off_at = fore.global_position + anchor.basis * fore_wrist
	elif weapon is MeleeWeapon and held != null:
		off_at = held.global_transform * Vector3(0.0, -0.16, 0.0)
	_off_turn = turn * off_basis
	if _watch > 0.0:
		var k := tan(deg_to_rad(camera.fov) * 0.5) / tan(deg_to_rad(80.0) * 0.5)
		var up := cam * Vector3(watch_at.x * k, watch_at.y * k, watch_at.z)
		off_at = up if _off_weight <= 0.0 else off_at.lerp(up, _watch)
		# Turn the forearm so the watch face looks back at the eye.
		var face := (off_basis * Vector3.UP).normalized()
		var to_eye := (cam.origin - up).normalized()
		var swing := Quaternion(face, to_eye)
		_off_turn = (off_basis if _off_weight <= 0.0 else _off_turn).slerp(Basis(swing) * off_basis, _watch)
	_off_target.global_position = off_at
	_off_pole.global_position = cam * off_elbow


## After the arms reach: turn each wrist so the hand meets the weapon the way
## the clip holds it.
func _turn_wrists() -> void:
	var to_skeleton := skeleton.global_basis.orthonormalized().inverse()
	if _ik.influence > 0.0:
		_set_turn(_wrist, to_skeleton * _wrist_turn)
	if _off_ik.influence > 0.0:
		_set_turn(_off_wrist, to_skeleton * _off_turn)


func _set_turn(bone: int, turn: Basis) -> void:
	var pose := skeleton.get_bone_global_pose(bone)
	pose.basis = turn.orthonormalized().scaled(pose.basis.get_scale())
	skeleton.set_bone_global_pose(bone, pose)
