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
## Nothing floats off it (Caleb's call): the screen is read where it is, in
## the hand, from the eyes in first person and over the shoulder in third.
##
## Load with `const Handheld := preload("res://core/phone/handheld.gd")`.

const UiTheme := preload("res://core/visual/ui_theme.gd")

## The body's size (m): high, deep, and how round its corners are. Its width
## follows the screen's shape (`SCREEN_ASPECT`).
const HEIGHT := 0.21
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
## Builds the handheld with `screen` on its face (a plain lit glass if null).
## The face is the node "Body", surface 0.
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
	for node in root.find_children("*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return root


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
