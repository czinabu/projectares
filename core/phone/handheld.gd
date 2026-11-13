extends RefCounted
## The phone as a thing in the hand: a rugged handheld with a pistol grip
## under it. One model, built here, for every view of it: your own
## character's hand holds it in first and third person, and other players
## see the same one (`ActorSkin`). Its origin is the middle of the grip,
## where the fist closes, and its screen faces +Z.
##
## The face of the body is a surface of its own, so the screen can be any
## material: your own phone shows its screen's viewport there
## (`Phone.screen_texture`), everyone else's shows a lit, unreadable glass.
##
## Load with `const Handheld := preload("res://core/phone/handheld.gd")`.

const UiTheme := preload("res://core/visual/ui_theme.gd")

## The body's size (m): high, deep, and how round its corners are. Its width
## follows the screen's shape (`SCREEN_ASPECT`).
const HEIGHT := 0.16
const DEPTH := 0.018
const CORNER := 0.013
## Width over height of the screen picture (`Phone.screen_size`).
const SCREEN_ASPECT := 480.0 / 800.0
## The grip: its size (m), how far across the bottom it sits (0 the middle,
## 0.5 the right edge), and how far it rakes back like a pistol's.
const GRIP_SIZE := Vector3(0.026, 0.08, 0.022)
const GRIP_ACROSS := 0.16
const GRIP_RAKE := -0.3

const CASE_COLOR := Color(0.12, 0.122, 0.13)
## The holo panel the device projects its screen onto (Caleb's call, so the
## screen reads in third person as in first): its size (m), how far over the
## device's top edge it floats, and how far its top tips back to the eyes.
## It is part of the device, so every view shows the same one.
const HOLO_SIZE := Vector2(0.24, 0.4)
## How solid the holo of a readable screen is.
const HOLO_OPACITY := 0.94
const HOLO_GAP := 0.035
const HOLO_TIP := 0.22
## How far out to the right (m) the panel floats, and how far it turns back
## in to face the eyes: it clears the head, so it shows from over the
## shoulder in third person too.
const HOLO_OUT := 0.09
const HOLO_TURN := 0.3


## Builds the handheld with `screen` on its face (a plain lit glass if null).
## The face is the node "Body", surface 0.
const MirrorScript := preload("res://core/visual/mirror.gd")


static func build(screen: Material = null) -> Node3D:
	var root := Node3D.new()
	root.name = "Handheld"
	var size := body_size()
	var half := size * 0.5
	var d := DEPTH
	var case := hardware_material(CASE_COLOR)
	var rubber := hardware_material(Color(0.07, 0.07, 0.075))
	var armour := hardware_material(Color(0.3, 0.17, 0.06))

	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = rounded_slab(size, d, CORNER)
	body.position = -grip_in_body()
	body.set_surface_override_material(0, screen if screen != null else glass_material())
	body.set_surface_override_material(1, case)
	root.add_child(body)

	for side: float in [-1.0, 1.0]:
		_box(body, "Rail", Vector3(0.0035, size.y * 0.55, d * 1.2), Vector3(side * (half.x + 0.001), 0.0, 0.0), rubber)
		for end: float in [-1.0, 1.0]:
			_box(body, "Corner", Vector3(0.011, 0.011, d * 1.25),
					Vector3(side * (half.x - 0.0035), end * (half.y - 0.0035), 0.0), armour)
	var antenna := CylinderMesh.new()
	antenna.top_radius = 0.003
	antenna.bottom_radius = 0.0042
	antenna.height = 0.028
	antenna.radial_segments = 8
	var stub := MeshInstance3D.new()
	stub.name = "Antenna"
	stub.mesh = antenna
	stub.material_override = rubber
	stub.position = Vector3(-half.x + 0.014, half.y + 0.011, -d * 0.2)
	body.add_child(stub)
	var handle := _box(root, "Handle", GRIP_SIZE, Vector3.ZERO, rubber)
	handle.basis = Basis(Vector3.RIGHT, GRIP_RAKE)
	var cap := _box(root, "GripCap", Vector3(GRIP_SIZE.x * 1.15, 0.01, GRIP_SIZE.z * 1.2), Vector3.ZERO, armour)
	cap.basis = handle.basis
	cap.position = handle.basis * Vector3(0.0, -GRIP_SIZE.y * 0.5, 0.0)
	var holo := MeshInstance3D.new()
	holo.name = "Holo"
	var panel := QuadMesh.new()
	panel.size = HOLO_SIZE
	holo.mesh = panel
	holo.transform = holo_in_body()
	holo.material_override = holo_material(null)
	body.add_child(holo)
	var beam := MeshInstance3D.new()
	beam.name = "Beam"
	beam.mesh = _beam_mesh(size)
	beam.material_override = _beam_material()
	body.add_child(beam)
	# The holo is for reading from outside: your own first-person camera
	# leaves it out with the head (Caleb's call) and reads the screen itself.
	holo.layers = 1 << (MirrorScript.HEAD_LAYER - 1)
	beam.layers = holo.layers
	for node in root.find_children("*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return root


## Where the holo panel sits in the body's frame: centred over the top edge,
## a gap above it, its top tipped back toward the eyes.
static func holo_in_body() -> Transform3D:
	var top := body_size().y * 0.5
	var tip := Basis(Vector3.UP, HOLO_TURN) * Basis(Vector3.RIGHT, HOLO_TIP)
	var bottom := Vector3(HOLO_OUT, top + HOLO_GAP, DEPTH * 0.5)
	return Transform3D(tip, bottom + tip * Vector3(0.0, HOLO_SIZE.y * 0.5, 0.0))


## The holo panel of a built handheld, or null.
static func holo_of(handheld: Node3D) -> MeshInstance3D:
	var face := face_of(handheld)
	return face.get_node_or_null("Holo") as MeshInstance3D if face != null else null


## The light the screen is projected in: `texture` (your own phone's screen)
## added onto the world, so its dark glass is see-through and its lines and
## text glow; null for a phone you cannot read, a faint unreadable sheen.
static func holo_material(texture: Texture2D) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.disable_receive_shadows = true
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if texture != null:
		# A readable screen is near solid (playtest feedback: the world bled
		# through), and drawn after the scene's other see-through things so a
		# sign behind it never prints over it.
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_texture = texture
		mat.albedo_color = Color(1.0, 0.97, 0.94, HOLO_OPACITY)
		mat.render_priority = Material.RENDER_PRIORITY_MAX
	else:
		var sheen := GradientTexture2D.new()
		sheen.fill_from = Vector2(0.5, 0.0)
		sheen.fill_to = Vector2(0.5, 1.0)
		sheen.gradient = Gradient.new()
		sheen.gradient.colors = PackedColorArray([_dim(UiTheme.ACCENT, 0.14), _dim(UiTheme.ACCENT, 0.03)])
		mat.albedo_texture = sheen
	return mat


## `color` scaled down for additive light, kept opaque so it adds only that much.
static func _dim(color: Color, amount: float) -> Color:
	return Color(color.r * amount, color.g * amount, color.b * amount, 1.0)


## A faint fan of light from the device's top edge up to the panel.
static func _beam_mesh(size: Vector2) -> ArrayMesh:
	var holo := holo_in_body()
	var top := size.y * 0.5
	var base := [Vector3(-size.x * 0.32, top, DEPTH * 0.5), Vector3(size.x * 0.32, top, DEPTH * 0.5)]
	var lift := [holo * Vector3(-HOLO_SIZE.x * 0.5, -HOLO_SIZE.y * 0.5, 0.0), holo * Vector3(HOLO_SIZE.x * 0.5, -HOLO_SIZE.y * 0.5, 0.0)]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var low := Color(UiTheme.ACCENT, 0.3)
	var high := Color(UiTheme.ACCENT, 0.04)
	for tri: Array in [[base[0], base[1], lift[1]], [base[0], lift[1], lift[0]]]:
		for point: Vector3 in tri:
			st.set_color(low if point.y <= top + 0.001 else high)
			st.add_vertex(point)
	return st.commit()


static func _beam_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return mat


## The body's width and height (m).
static func body_size() -> Vector2:
	return Vector2(HEIGHT * SCREEN_ASPECT, HEIGHT)


## Where the middle of the grip is in the body's frame: under the bottom
## edge, a little right of centre and back from the face.
static func grip_in_body() -> Vector3:
	var size := body_size()
	return Vector3(size.x * GRIP_ACROSS, -size.y * 0.5 - GRIP_SIZE.y * 0.42, -DEPTH * 0.15)


## The face of a built handheld (the "Body" node), or null.
static func face_of(handheld: Node3D) -> MeshInstance3D:
	return handheld.get_node_or_null("Body") as MeshInstance3D if handheld != null else null


## The screen of a phone you cannot read: dark glass with a faint warm glow,
## so a player on their phone reads from across a street.
static func glass_material() -> StandardMaterial3D:
	var lit := StandardMaterial3D.new()
	lit.albedo_color = Color(0.05, 0.055, 0.06)
	lit.emission_enabled = true
	lit.emission = UiTheme.ACCENT
	lit.emission_energy_multiplier = 0.35
	lit.roughness = 0.6
	return lit


## The screen of your own phone: the picture `texture`, lit from within so
## it reads in a dark street and the bloom catches it.
static func screen_material(texture: Texture2D) -> StandardMaterial3D:
	var face := StandardMaterial3D.new()
	face.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	face.albedo_texture = texture
	face.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	face.emission_enabled = true
	face.emission_texture = texture
	face.emission_energy_multiplier = 0.4
	return face


## A dark, lightly lit material for the body and its parts, with a little
## light of its own so it never goes black in a dark street.
static func hardware_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.55
	mat.metallic = 0.35
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 0.35
	return mat


static func _box(parent: Node3D, node_name: String, size: Vector3, at: Vector3, mat: Material) -> MeshInstance3D:
	var box := BoxMesh.new()
	box.size = size
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = box
	node.material_override = mat
	node.position = at
	parent.add_child(node)
	return node


## A rounded slab `size` across and `depth` thick, its face toward +Z.
## Surface 0 is the face, mapped 0 to 1 across it; surface 1 the edge and back.
static func rounded_slab(size: Vector2, depth: float, radius: float, steps := 8) -> ArrayMesh:
	var outline: Array[Vector2] = []
	var half := size * 0.5
	var r := minf(radius, minf(half.x, half.y))
	var corners := [Vector2(half.x - r, half.y - r), Vector2(-half.x + r, half.y - r),
			Vector2(-half.x + r, -half.y + r), Vector2(half.x - r, -half.y + r)]
	for c in 4:
		for i in steps + 1:
			var angle := (c + float(i) / steps) * PI * 0.5
			outline.append((corners[c] as Vector2) + Vector2(cos(angle), sin(angle)) * r)
	var front := depth * 0.5
	var mesh := ArrayMesh.new()
	var face := SurfaceTool.new()
	face.begin(Mesh.PRIMITIVE_TRIANGLES)
	face.set_normal(Vector3.BACK)
	for i in outline.size():
		var a := outline[i]
		var b := outline[(i + 1) % outline.size()]
		for point: Vector2 in [Vector2.ZERO, b, a]:
			face.set_uv(Vector2(point.x / size.x + 0.5, 0.5 - point.y / size.y))
			face.add_vertex(Vector3(point.x, point.y, front))
	face.commit(mesh)
	var shell := SurfaceTool.new()
	shell.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in outline.size():
		var a := outline[i]
		var b := outline[(i + 1) % outline.size()]
		var out := Vector3(a.x + b.x, a.y + b.y, 0.0).normalized()
		shell.set_normal(out)
		for point: Vector3 in [Vector3(a.x, a.y, front), Vector3(b.x, b.y, front), Vector3(b.x, b.y, -front),
				Vector3(a.x, a.y, front), Vector3(b.x, b.y, -front), Vector3(a.x, a.y, -front)]:
			shell.add_vertex(point)
		shell.set_normal(Vector3.FORWARD)
		for point: Vector2 in [Vector2.ZERO, a, b]:
			shell.add_vertex(Vector3(point.x, point.y, -front))
	shell.commit(mesh)
	return mesh
