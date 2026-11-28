class_name FlightHolo
extends Node3D
## A small hologram of yourself that the watch beams out ahead and to the
## left of the eyes while you fly in first person (Caleb's ask, after the ship
## silhouette in a cockpit), so you can see your attitude and pose from
## outside while looking out of your own eyes. It is drawn from your own
## body's skeleton as it was posed this frame (the same bones both views
## show, so it is never a second model or a second pose), seen from behind
## and a little above against a level ring: it pitches, rolls and turns
## with you, the limbs move as yours do (the lead into a turn, a skater's
## strides), the rig shows as its wingtips and lit flames, and a line ahead
## shows where the body is really going. A faint beam runs to it from the
## watch, so it is the watch's projection in the world, not a screen overlay.
##
## View only and first person only: `Hud.Wrist` mounts it (beside the
## emote wheel's hologram, `Hud.EmoteHolo`), it reads the skin and never
## the simulation, and the phone's "Flight hologram" toggle
## (`GameSettings.flight_hologram`) turns it off. One draw a frame.

const GameSettings := preload("res://core/settings/game_settings.gd")
const WeaponArm := preload("res://core/visual/weapon_arm.gd")
const INK := Color(0.45, 0.95, 1.0)

## Where the figure stands (Caleb's call, since the wrist is out of view
## while flying): beamed from the watch to a spot in the world ahead and
## to the left of the eyes, `ahead` metres out, at a share of the way from
## the view's middle to its left and top edges (`corner`, so it keeps its
## place whatever the field of view); and how big a 1.8 m body is drawn.
## The beam comes up from the watch on the wrist, in view or not.
var ahead := 0.6
var corner := Vector2(0.66, 0.5)
var size := 0.1
## The angle it is seen from: above (radians down onto it) and from the
## side (a three-quarter view, so a dive and a climb read).
var view_down := 0.38
var view_side := 0.45
## The level ring (metres round the hips, body scale), the speed line
## (metres a m/s, body scale) and the strokes' width (metres, display scale).
var ring_radius := 1.1
var speed_scale := 0.05
var stroke := 0.0016
## Seconds to fade in or out.
var fade_time := 0.25

## How far in it is, 0 to 1.
var shown := 0.0

## The bones drawn and the lines between them: each bone to its parent when
## both are drawn (the human rig's names; another rig's are simply absent).
const BONES := ["Hips", "Abdomen", "Torso", "Chest", "Neck", "Head",
		"Shoulder.L", "UpperArm.L", "LowerArm.L", "Wrist.L",
		"Shoulder.R", "UpperArm.R", "LowerArm.R", "Wrist.R",
		"UpperLeg.L", "LowerLeg.L", "Foot.L", "UpperLeg.R", "LowerLeg.R", "Foot.R"]

var _mesh := ImmediateMesh.new()
var _draw: MeshInstance3D
var _skeleton: Skeleton3D
var _probe: SkeletonModifier3D
## The bones' places (world) as last posed, read by `_probe` after every
## other modifier, since the skeleton puts its poses back once drawn.
var _posed := {}
var _ids: Array[int] = []
var _parents: Array[int] = []


func _ready() -> void:
	top_level = true
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.vertex_color_use_as_albedo = true
	mat.render_priority = 1
	_draw = MeshInstance3D.new()
	_draw.name = "Figure"
	_draw.mesh = _mesh
	_draw.material_override = mat
	_draw.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_draw.top_level = true
	add_child(_draw)


func _exit_tree() -> void:
	_drop_probe()


## Whether `p` flies in a way the hologram is for: in the air (or on a
## skate) with a working rig, alive and on foot.
static func flying(p: Actor) -> bool:
	if p == null or p.is_dead or p.vehicle != null or not p.flight.enabled or not p.flight.working():
		return false
	var f := p.flight
	return f.is_gliding or f.is_hovering or f.is_thrusting or f.is_boosting or f.is_skating or f.is_skimming \
			or (not p.is_on_floor() and p.airborne_time > 0.3)


## Whether the hologram is wanted for `p` now: flying, first person, the
## setting on, and nothing else in front of the eyes (the phone, the card).
static func wanted(p: Actor, controller: PlayerController, card_up: bool) -> bool:
	if controller == null or controller.camera == null or not GameSettings.flight_hologram:
		return false
	if controller.is_third_person() or controller.phone_out or card_up or controller.sighted:
		return false
	return flying(p)


## Eases the hologram toward `on` and draws `p`'s body into it, from the
## eyes of `camera`, with a beam back to the watch at `watch` when it is in
## view. Called each frame by the watch.
func update(p: Actor, camera: Camera3D, on: bool, watch: Vector3, delta: float) -> void:
	shown = move_toward(shown, 1.0 if on else 0.0, delta / maxf(fade_time, 0.01)) if delta > 0.0 else (1.0 if on else 0.0)
	visible = shown > 0.0 and watch != Vector3.INF
	_mesh.clear_surfaces()
	if not visible or camera == null or p == null or watch == Vector3.INF:
		_drop_probe()
		return
	var skin := p.get_node_or_null("Skin")
	var skeleton: Skeleton3D = skin.call("bones") if skin != null and skin.has_method("bones") else null
	if skeleton != _skeleton:
		_drop_probe()
		_skeleton = skeleton
		_ids.clear()
		_parents.clear()
		_posed.clear()
		if skeleton != null:
			_index_bones(skeleton)
			_probe = WeaponArm.Hook.new()
			_probe.name = "FlightHoloProbe"
			_probe.run = _read_pose
			skeleton.add_child(_probe)
	if _posed.is_empty():
		return
	var hips: Vector3 = _posed.get(_ids[0], p.global_position + Vector3.UP)
	var look := camera.global_basis.orthonormalized()
	var yaw := atan2(-look.z.x, -look.z.z)
	# From the world to the figure's own frame: level, facing the way the
	# view does, round the hips. Then into the corner of the view, seen from
	# behind, a little above and a little to the side.
	var to_body := Basis(Vector3.UP, yaw).inverse()
	var turn := look * Basis(Vector3.UP, view_side) * Basis(Vector3.RIGHT, view_down)
	var scale_by := size / 1.8
	var tall := tan(deg_to_rad(camera.fov) * 0.5)
	var screen := camera.get_viewport().get_visible_rect().size
	var wide := tall * (screen.x / maxf(screen.y, 1.0))
	var middle := camera.global_position + look * Vector3(-wide * corner.x * ahead, tall * corner.y * ahead, -ahead)
	global_position = middle
	var place := func(at: Vector3) -> Vector3:
		return middle + turn * (to_body * (at - hips)) * scale_by
	var eye := camera.global_position
	var flicker := 0.9 + 0.1 * sin(Time.get_ticks_msec() * 0.031)
	var ink := Color(INK, 0.85 * shown * flicker)
	var faint := Color(INK, 0.3 * shown * flicker)
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	# The level ring, flat whatever the body does, so its pitch and roll read.
	var ring := 24
	for i in ring:
		var a := TAU * i / ring
		var b := TAU * (i + 1) / ring
		var flat_a := hips + Basis(Vector3.UP, yaw) * Vector3(cos(a), 0.0, sin(a)) * ring_radius
		var flat_b := hips + Basis(Vector3.UP, yaw) * Vector3(cos(b), 0.0, sin(b)) * ring_radius
		_line(place.call(flat_a), place.call(flat_b), eye, faint, stroke * 0.7)
	# The nose of the ring: the way the view faces.
	_line(place.call(hips + Basis(Vector3.UP, yaw) * Vector3(0, 0, -ring_radius)),
			place.call(hips + Basis(Vector3.UP, yaw) * Vector3(0, 0, -ring_radius * 1.25)), eye, faint, stroke)
	# The body, bone by bone.
	for i in _ids.size():
		var parent := _parents[i]
		if parent < 0:
			continue
		var a_at: Variant = _posed.get(_ids[i])
		var b_at: Variant = _posed.get(parent)
		if a_at == null or b_at == null:
			continue
		_line(place.call(a_at), place.call(b_at), eye, ink, stroke)
	# The head as a small diamond on the neck.
	var head: Variant = _posed.get(skeleton.find_bone("Head"))
	if head != null:
		var h: Vector3 = place.call(head as Vector3 + Vector3.UP * 0.12)
		var r := 0.1 * scale_by
		var side := (turn * Vector3.RIGHT) * r
		var rise := (turn * Vector3.UP) * r
		_line(h + rise, h + side, eye, ink, stroke)
		_line(h + side, h - rise, eye, ink, stroke)
		_line(h - rise, h - side, eye, ink, stroke)
		_line(h - side, h + rise, eye, ink, stroke)
	# The rig: the wingtips from the shoulders, and every lit flame.
	if skin != null and skin.has_method("rig_marks"):
		var marks: Array = skin.call("rig_marks")
		for mark: Array in marks:
			_line(place.call(mark[0]), place.call(mark[1]), eye, ink if mark.size() < 3 else Color(1.0, 0.75, 0.4, 0.8 * shown), stroke)
	# Where the body is really going.
	var going := p.velocity * speed_scale
	if going.length() > 0.05:
		_line(place.call(hips), place.call(hips + going.limit_length(2.5)), eye, faint, stroke)
	# The faint beam it is thrown on, up from the watch face.
	_line(watch, middle + turn * Vector3.DOWN * size * 0.6, eye, Color(INK, 0.12 * shown), stroke * 2.0)
	_mesh.surface_end()


## Draws a stroke from `a` to `b` as a thin ribbon facing `eye`.
func _line(a: Vector3, b: Vector3, eye: Vector3, ink: Color, width: float) -> void:
	var along := b - a
	if along.length_squared() < 1e-10:
		return
	var side := along.cross(eye - a).normalized() * width * 0.5
	_mesh.surface_set_color(ink)
	_mesh.surface_add_vertex(a - side)
	_mesh.surface_add_vertex(a + side)
	_mesh.surface_add_vertex(b + side)
	_mesh.surface_add_vertex(a - side)
	_mesh.surface_add_vertex(b + side)
	_mesh.surface_add_vertex(b - side)


static func _in_view(camera: Camera3D, at: Vector3) -> bool:
	return not camera.is_position_behind(at) \
			and Rect2(Vector2.ZERO, camera.get_viewport().get_visible_rect().size).has_point(camera.unproject_position(at))


func _index_bones(skeleton: Skeleton3D) -> void:
	var drawn := {}
	for bone_name: String in BONES:
		var bone := skeleton.find_bone(bone_name)
		if bone >= 0:
			drawn[bone] = true
			_ids.append(bone)
	for bone in _ids:
		var parent := skeleton.get_bone_parent(bone)
		while parent >= 0 and not drawn.has(parent):
			parent = skeleton.get_bone_parent(parent)
		_parents.append(parent)


## Run by `_probe` after the other modifiers: where every drawn bone is.
func _read_pose() -> void:
	if _skeleton == null or not is_instance_valid(_skeleton):
		return
	var frame := _skeleton.global_transform
	for bone in _ids:
		_posed[bone] = frame * _skeleton.get_bone_global_pose(bone).origin


func _drop_probe() -> void:
	if _probe != null and is_instance_valid(_probe):
		_probe.queue_free()
	_probe = null
	_skeleton = null
	_posed.clear()
