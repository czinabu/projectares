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
## image moves as you move. In first person the viewer's own head is on
## `HEAD_LAYER`, which their camera leaves out and the mirror's camera sees.
##
## Load with `const MirrorScript := preload("res://core/visual/mirror.gd")`.

## Render layer of the mirror itself, which its own camera leaves out.
const MIRROR_LAYER := 18
## Render layer of the phone held up to the viewer's eyes (`Phone`), which
## the mirror's camera leaves out: it is the viewer's close-up, not a thing in
## the room.
const HELD_LAYER := 17
## Render layer of your own head (and whatever is worn on it) while you look
## out of it in first person: your camera leaves it out, everyone else's and
## the mirror's see it (`ActorSkin.hide_head`).
const HEAD_LAYER := 16
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
## How thick the frame is round the glass.
var frame_width := 0.035
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
	var left := Vector3.UP.cross(forward).normalized()
	var spot := feet + forward * at + left * side_offset * at / distance
	if viewer.is_inside_tree():
		# Stand on the ground where it is, which may sit higher or lower than
		# the viewer's feet on a slope or a step.
		var down := PhysicsRayQueryParameters3D.create(spot + Vector3.UP * 1.0, spot + Vector3.DOWN * 2.0,
				Actor.LAYER_WORLD)
		var ground := viewer.get_world_3d().direct_space_state.intersect_ray(down)
		if not ground.is_empty():
			spot.y = ground.position.y
	# The glass faces the viewer: the mirror's +Z points back at them.
	global_transform = Transform3D(Basis.looking_at(forward, Vector3.UP), spot)


## Where the middle of the glass is.
func glass_centre() -> Vector3:
	return global_transform * Vector3(0, 0.12 + height * 0.5, 0)


func _build() -> void:
	# A slim frame of dark brushed metal with a pale chamfer round the glass,
	# like a bevelled edge catching the light, and a soft shadow on the floor.
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.3, 0.29, 0.28)
	metal.metallic = 0.45
	metal.roughness = 0.38
	var bevel := StandardMaterial3D.new()
	bevel.albedo_color = Color(0.62, 0.6, 0.56)
	bevel.metallic = 0.9
	bevel.roughness = 0.22
	var mid := 0.12 + height * 0.5
	var bar := frame_width
	var outer := Vector2(width + bar * 2.0, height + bar * 2.0)
	_part(Vector3(outer.x, bar, 0.05), Vector3(0, mid + height * 0.5 + bar * 0.5, -0.01), metal)
	_part(Vector3(outer.x, bar, 0.05), Vector3(0, mid - height * 0.5 - bar * 0.5, -0.01), metal)
	_part(Vector3(bar, height, 0.05), Vector3(-width * 0.5 - bar * 0.5, mid, -0.01), metal)
	_part(Vector3(bar, height, 0.05), Vector3(width * 0.5 + bar * 0.5, mid, -0.01), metal)
	# The chamfer: four thin strips just inside the frame, angled in to the glass.
	var lip := 0.014
	for edge: Array in [[Vector3(width, lip, 0.01), Vector3(0, mid + height * 0.5 - lip * 0.5, 0.004), Vector3(-0.6, 0, 0)],
			[Vector3(width, lip, 0.01), Vector3(0, mid - height * 0.5 + lip * 0.5, 0.004), Vector3(0.6, 0, 0)],
			[Vector3(lip, height, 0.01), Vector3(-width * 0.5 + lip * 0.5, mid, 0.004), Vector3(0, 0.6, 0)],
			[Vector3(lip, height, 0.01), Vector3(width * 0.5 - lip * 0.5, mid, 0.004), Vector3(0, -0.6, 0)]]:
		_part(edge[0], edge[1], bevel).rotation = edge[2]
	_part(Vector3(outer.x, outer.y, 0.02), Vector3(0, mid, -0.04), metal)
	# Two slim feet, swept back so it looks stood, not floating.
	for side in [-1.0, 1.0]:
		_part(Vector3(0.05, 0.04, 0.5), Vector3(side * (width * 0.5 - 0.1), 0.02, -0.12), metal)
	_add_shadow(Vector2(outer.x + 0.9, 1.5))

	_viewport = SubViewport.new()
	_viewport.name = "Reflection"
	_viewport.size = Vector2i(roundi(resolution * width / height), resolution)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.msaa_3d = Viewport.MSAA_2X
	_viewport.world_3d = get_world_3d()
	add_child(_viewport)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_FRUSTUM
	_camera.cull_mask = ALL_LAYERS & ~(1 << (MIRROR_LAYER - 1)) & ~(1 << (HELD_LAYER - 1))
	_camera.top_level = true
	_viewport.add_child(_camera)
	_camera.current = true

	var glass_mat := ShaderMaterial.new()
	glass_mat.shader = _glass_shader()
	glass_mat.set_shader_parameter("reflection", _viewport.get_texture())
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


## The glass: the reflection, turned round as a mirror shows it, with a
## faint cool tint, a soft darkening into the corners and a sheen at glancing
## angles.
static func _glass_shader() -> Shader:
	var shader := Shader.new()
	shader.code = """shader_type spatial;
render_mode unshaded, cull_back;
uniform sampler2D reflection : source_color, filter_linear;
void fragment() {
	vec2 uv = vec2(1.0 - UV.x, UV.y);
	vec3 col = texture(reflection, uv).rgb * vec3(0.93, 0.96, 1.0);
	vec2 d = abs(UV - 0.5) * 2.0;
	float edge = smoothstep(0.82, 1.0, max(d.x, d.y));
	col *= 1.0 - edge * 0.22;
	float glance = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	ALBEDO = col + vec3(0.06, 0.07, 0.08) * glance;
}
"""
	return shader


## A soft dark patch on the floor under the mirror, so it sits on the ground.
func _add_shadow(size: Vector2) -> void:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0, 0, 0, 0.75))
	gradient.set_color(1, Color(0, 0, 0, 0.0))
	gradient.add_point(0.45, Color(0, 0, 0, 0.45))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(0.5, 0.0)
	texture.width = 128
	texture.height = 128
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = texture
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	var plane := PlaneMesh.new()
	plane.size = size
	var shadow := MeshInstance3D.new()
	shadow.name = "Shadow"
	shadow.mesh = plane
	shadow.material_override = mat
	shadow.position = Vector3(0, 0.025, 0.0)
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shadow.layers = 1 << (MIRROR_LAYER - 1)
	add_child(shadow)


func _part(size: Vector3, at: Vector3, mat: Material) -> MeshInstance3D:
	var box := BoxMesh.new()
	box.size = size
	var part := MeshInstance3D.new()
	part.mesh = box
	part.material_override = mat
	part.position = at
	part.layers = 1 << (MIRROR_LAYER - 1)
	add_child(part)
	return part


func _process(delta: float) -> void:
	if viewer == null or not is_instance_valid(viewer) or not viewer.is_inside_tree():
		return
	if _camera == null:
		return
	if _rise < rise_seconds:
		_rise = minf(_rise + delta, rise_seconds)
		var t := _rise / rise_seconds
		scale = Vector3(1.0, lerpf(0.02, 1.0, 1.0 - pow(1.0 - t, 3.0)), 1.0)
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
