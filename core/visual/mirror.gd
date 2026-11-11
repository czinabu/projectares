extends Node3D
## A tall mirror that stands in front of the player while the phone's Mirror
## app is open, wherever they are: the home base, the plaza or a warzone.
## The phone lists the clothes and colours they own; the mirror shows the
## result on their own character as they scroll.
##
## It is a view only. It has no collision, nothing in the simulation reads
## it, and it never goes to a server. Headless it builds nothing.
##
## The reflection is a second camera at the viewer's eye mirrored through
## the glass, with its view cut to the glass (an off-centre frustum), so the
## image moves as you move. In first person the viewer's own body is moved to
## `BODY_LAYER`: their camera leaves that layer out (`PlayerController.body_layer`)
## while the mirror's camera still sees it.
##
## Load with `const MirrorScript := preload("res://core/visual/mirror.gd")`.

## Render layer (1-20) the viewer's body and held gear are drawn on while the
## mirror stands.
const BODY_LAYER := 19
## Render layer of the mirror itself, which its own camera leaves out.
const MIRROR_LAYER := 18
const ALL_LAYERS := 0xFFFFF

## Size of the glass in metres.
var width := 1.5
var height := 2.3
## How far in front of the viewer it stands, and the least it may when a
## wall is close.
var distance := 2.1
var min_distance := 1.1
## How far to the viewer's left it stands, clear of the phone on the right.
var side_offset := 0.3
## Height of the reflection in pixels.
var resolution := 900
## Seconds it takes to rise out of the floor.
var rise_seconds := 0.3

## The player it stands in front of, and the camera they look through.
var viewer: Actor
var eye: Camera3D

var _viewport: SubViewport
var _camera: Camera3D
var _glass: MeshInstance3D
var _rise := 0.0
var _stamped: Array[VisualInstance3D] = []


## Call before adding it to the tree.
func setup(p_viewer: Actor, p_eye: Camera3D) -> void:
	viewer = p_viewer
	eye = p_eye


func _ready() -> void:
	process_priority = 100
	if viewer == null or not is_instance_valid(viewer):
		return
	place()
	if not Look.enabled:
		return
	_build()
	scale = Vector3(1.0, 0.02, 1.0)


func _exit_tree() -> void:
	release_body()


## Stands the mirror on the floor in front of the viewer, facing them, closer
## if a wall is in the way.
func place() -> void:
	var forward := Vector3.FORWARD
	if eye != null and is_instance_valid(eye):
		forward = -eye.global_basis.z
	elif viewer.is_inside_tree():
		forward = -viewer.global_basis.z
	forward.y = 0.0
	forward = forward.normalized() if forward.length() > 0.01 else Vector3.FORWARD
	var at := distance
	if viewer.is_inside_tree():
		var from := viewer.get_eye_position()
		var query := PhysicsRayQueryParameters3D.create(from, from + forward * (distance + 0.4), Actor.LAYER_WORLD)
		var hit := viewer.get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			at = maxf(min_distance, from.distance_to(hit.position) - 0.4)
	var feet := viewer.global_position if viewer.is_inside_tree() else viewer.position
	# The glass faces the viewer: the mirror's +Z points back at them.
	var left := Vector3.UP.cross(forward).normalized()
	global_transform = Transform3D(Basis.looking_at(forward, Vector3.UP),
			feet + forward * at + left * side_offset * at / distance)


## Where the middle of the glass is.
func glass_centre() -> Vector3:
	return global_transform * Vector3(0, 0.1 + height * 0.5, 0)


func _build() -> void:
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.13, 0.12, 0.11)
	dark.metallic = 0.7
	dark.roughness = 0.35
	var trim := StandardMaterial3D.new()
	trim.albedo_color = Color(1.0, 0.62, 0.22)
	trim.emission_enabled = true
	trim.emission = Color(1.0, 0.55, 0.2)
	trim.emission_energy_multiplier = 1.4
	var mid := 0.1 + height * 0.5
	var bar := 0.09
	# Frame, back panel, feet and a lit strip along the inside edge.
	_part(Vector3(width + bar * 2.0, bar, 0.1), Vector3(0, mid + height * 0.5 + bar * 0.5, 0), dark)
	_part(Vector3(width + bar * 2.0, bar, 0.1), Vector3(0, mid - height * 0.5 - bar * 0.5, 0), dark)
	_part(Vector3(bar, height, 0.1), Vector3(-width * 0.5 - bar * 0.5, mid, 0), dark)
	_part(Vector3(bar, height, 0.1), Vector3(width * 0.5 + bar * 0.5, mid, 0), dark)
	_part(Vector3(width + bar * 2.0, height + bar * 2.0, 0.03), Vector3(0, mid, -0.06), dark)
	_part(Vector3(width + bar * 2.0, 0.02, 0.02), Vector3(0, mid + height * 0.5, 0.05), trim)
	for side in [-1.0, 1.0]:
		_part(Vector3(0.12, 0.06, 0.55), Vector3(side * (width * 0.5 + bar * 0.5), 0.03, 0), dark)

	_viewport = SubViewport.new()
	_viewport.name = "Reflection"
	_viewport.size = Vector2i(roundi(resolution * width / height), resolution)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.msaa_3d = Viewport.MSAA_2X
	_viewport.world_3d = get_world_3d()
	add_child(_viewport)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_FRUSTUM
	_camera.cull_mask = ALL_LAYERS & ~(1 << (MIRROR_LAYER - 1))
	_camera.top_level = true
	_viewport.add_child(_camera)
	_camera.current = true

	var glass_mat := StandardMaterial3D.new()
	glass_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glass_mat.albedo_texture = _viewport.get_texture()
	glass_mat.albedo_color = Color(0.94, 0.96, 1.0)
	# Seen from the front, the picture runs the other way.
	glass_mat.uv1_scale = Vector3(-1.0, 1.0, 1.0)
	glass_mat.uv1_offset = Vector3(1.0, 0.0, 0.0)
	var quad := QuadMesh.new()
	quad.size = Vector2(width, height)
	_glass = MeshInstance3D.new()
	_glass.name = "Glass"
	_glass.mesh = quad
	_glass.material_override = glass_mat
	_glass.position = Vector3(0, mid, 0.0)
	_glass.layers = 1 << (MIRROR_LAYER - 1)
	_glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_glass)


func _part(size: Vector3, at: Vector3, mat: Material) -> void:
	var box := BoxMesh.new()
	box.size = size
	var part := MeshInstance3D.new()
	part.mesh = box
	part.material_override = mat
	part.position = at
	part.layers = 1 << (MIRROR_LAYER - 1)
	add_child(part)


func _process(delta: float) -> void:
	if viewer == null or not is_instance_valid(viewer) or not viewer.is_inside_tree():
		release_body()
		return
	if _camera == null:
		return
	if _rise < rise_seconds:
		_rise = minf(_rise + delta, rise_seconds)
		var t := _rise / rise_seconds
		scale = Vector3(1.0, lerpf(0.02, 1.0, 1.0 - pow(1.0 - t, 3.0)), 1.0)
	_stamp_body()
	_aim_reflection()


## Puts the reflection camera at the viewer's eye mirrored through the glass,
## with its view cut exactly to the glass.
func _aim_reflection() -> void:
	if eye == null or not is_instance_valid(eye):
		return
	var basis := global_basis.orthonormalized()
	var normal := basis.z
	var centre := _glass.global_position
	var gap := (eye.global_position - centre).dot(normal)
	if gap < 0.05:
		# Standing behind the mirror: nothing to see.
		return
	var reflected := eye.global_position - 2.0 * gap * normal
	var cam_basis := Basis(-basis.x, basis.y, -normal)
	_camera.global_transform = Transform3D(cam_basis, reflected)
	var local := cam_basis.inverse() * (centre - reflected)
	_camera.set_frustum(height * scale.y, Vector2(local.x, local.y), maxf(gap, 0.05), 300.0)


## Moves the viewer's model and held gear to `BODY_LAYER`, every frame, since
## a new look or weapon brings new parts.
func _stamp_body() -> void:
	var bit := 1 << (BODY_LAYER - 1)
	for root: Node in [viewer.get_node_or_null("Skin"), viewer.hand]:
		if root == null:
			continue
		for node: Node in root.find_children("*", "VisualInstance3D", true, false):
			var visual := node as VisualInstance3D
			if visual.layers != bit:
				visual.layers = bit
				_stamped.append(visual)


## Puts the viewer's body back on the normal layer.
func release_body() -> void:
	for visual in _stamped:
		if is_instance_valid(visual):
			visual.layers = 1
	_stamped.clear()
