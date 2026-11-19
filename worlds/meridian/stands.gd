extends RefCounted
## Meridian's spectacle, decoration only: grandstands, canopies, floodlight
## masts, section signs and the crowd that fills them. Shapes are batched
## into one mesh per material (`finish`), so a stand of a thousand rows is a
## handful of draw calls, and the people are one `Crowd`. Nothing here
## collides or is read by the race; the map builds it only where `Look` is
## on, with its own RNG so the layout never shifts.

const CYAN := Color(0.3, 0.85, 1.0)
const AMBER := Color(1.0, 0.6, 0.2)
const MAGENTA := Color(1.0, 0.3, 0.7)

var root: Node3D
var rng := RandomNumberGenerator.new()
var crowd: Crowd
var steel: Material
var dark: Material
var glass: Material
## Material -> SurfaceTool, the shapes waiting to be merged.
var _batches := {}
var _glows := {}


func _init(p_root: Node3D, p_seed: int) -> void:
	root = p_root
	rng.seed = p_seed
	crowd = Crowd.new()
	crowd.name = "Crowd"
	steel = Look.surface("metal", {"metal": 0.4, "tint": Color(0.22, 0.23, 0.27), "grime": 0.25, "scale": 0.3})
	dark = Look.surface("metal", {"metal": 0.3, "tint": Color(0.1, 0.1, 0.13), "grime": 0.15, "scale": 0.3})
	glass = glow(Color(0.25, 0.6, 0.8), 0.4, 0.06)


## A lit, unshaded material; the same colour and strength share one.
func glow(color: Color, energy: float, alpha := 1.0) -> StandardMaterial3D:
	var key := "%s/%s/%s" % [color, energy, alpha]
	if _glows.has(key):
		return _glows[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color, alpha)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_glows[key] = m
	return m


## A box of `size` placed by `xf`, merged later with every other in `mat`.
func box(size: Vector3, xf: Transform3D, mat: Material) -> void:
	if not _batches.has(mat):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_batches[mat] = st
	var mesh := BoxMesh.new()
	mesh.size = size
	(_batches[mat] as SurfaceTool).append_from(mesh, 0, xf)


func label(text: String, xf: Transform3D, size: int, color: Color, px := 0.02) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = px
	l.modulate = color
	l.outline_size = 0
	l.transform = xf
	root.add_child(l)


## Merges everything into the scene: one mesh per material, then the crowd.
func finish() -> void:
	for mat: Material in _batches:
		var node := MeshInstance3D.new()
		node.mesh = (_batches[mat] as SurfaceTool).commit()
		node.mesh.surface_set_material(0, mat)
		if mat is StandardMaterial3D and (mat as StandardMaterial3D).emission_enabled:
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.set_meta("walk_through", "the spectacle is decoration only (docs/systems/arena-and-race.md)")
		root.add_child(node)
	_batches.clear()
	if crowd.count() > 0:
		root.add_child(crowd)
		crowd.build()


# --- People -------------------------------------------------------------------

## One spectator at `p` facing `yaw`: mostly dark clothes, some in the
## circuit's cyan and amber, a few with a light stick.
func person(p: Vector3, yaw: float) -> void:
	var pick := rng.randf()
	var c: Color
	if pick < 0.14:
		c = CYAN.darkened(rng.randf_range(0.35, 0.65))
	elif pick < 0.26:
		c = AMBER.darkened(rng.randf_range(0.35, 0.65))
	elif pick < 0.3:
		c = MAGENTA.darkened(0.55)
	else:
		c = Color.from_hsv(rng.randf_range(0.5, 0.75), rng.randf_range(0.05, 0.3), rng.randf_range(0.06, 0.3))
	crowd.add(p, yaw + rng.randf_range(-0.3, 0.3), c, rng.randf(), rng.randf() < 0.12, rng.randf(),
			rng.randf_range(0.9, 1.1))


## People scattered over a flat deck: `xf` its middle, `half` its half size.
func fill_deck(xf: Transform3D, half: Vector2, count: int, facing := NAN) -> void:
	for k in count:
		var yaw := rng.randf() * TAU if is_nan(facing) else facing + (PI if rng.randf() < 0.5 else 0.0)
		person(xf * Vector3(rng.randf_range(-half.x, half.x), 0, rng.randf_range(-half.y, half.y)), yaw)


# --- Stands -------------------------------------------------------------------

## A straight stand. `xf` is the middle of its front edge on the ground,
## local +z away from the track and +x along it. Rows step up and back
## (`depth` deep, `rise` higher each) from a front wall `base` high; people
## fill `fill` of the seats. Returns how deep it is.
func stand(xf: Transform3D, length: float, rows: int, depth := 1.6, rise := 0.9, base := 3.0, fill := 0.85) -> float:
	var facing := xf.basis.get_euler().y + PI
	for r in rows:
		var h := base + r * rise
		box(Vector3(length, h, depth), xf * Transform3D(Basis(), Vector3(0, h * 0.5, r * depth + depth * 0.5)), steel)
		if r % 5 == 0:
			box(Vector3(length, 0.12, 0.08), xf * Transform3D(Basis(), Vector3(0, h + 0.02, r * depth + 0.06)),
					glow(CYAN if r % 10 == 0 else AMBER, 2.2))
		var x := -length * 0.5 + 0.4
		while x < length * 0.5 - 0.4:
			if rng.randf() < fill:
				person(xf * Vector3(x + rng.randf_range(-0.08, 0.08), h, r * depth + depth * 0.55), facing)
			x += 0.72
	# The front wall with its lit band.
	box(Vector3(length, base + 1.1, 0.4), xf * Transform3D(Basis(), Vector3(0, (base + 1.1) * 0.5, -0.2)), dark)
	box(Vector3(length, 0.25, 0.05), xf * Transform3D(Basis(), Vector3(0, base * 0.55, -0.43)), glow(CYAN, 3.0))
	return rows * depth


## A curved stand round `centre`: straight pieces from angle `from` to `to`
## (radians round +y, 0 along +x) at `radius`, rising outward, or inward
## when `inward`.
func curved_stand(centre: Vector3, radius: float, from: float, to: float, pieces: int, rows: int,
		depth := 1.6, rise := 1.0, base := 2.5, inward := false) -> void:
	var step := (to - from) / pieces
	for k in pieces:
		var a := from + step * (k + 0.5)
		var out := Vector3(cos(a), 0, sin(a))
		var away := -out if inward else out
		stand(Transform3D(Basis(Vector3.UP, atan2(away.x, away.z)), centre + out * radius),
				2.0 * radius * sin(absf(step) * 0.5) + 0.4, rows, depth, rise, base)


## A roof over a stand: columns at the back (`back` from the front edge), a
## canopy `height` up reaching `reach` out over the front, lit seams under.
func canopy(xf: Transform3D, length: float, back: float, height: float, reach: float) -> void:
	var span := back + reach
	var col := length / 6.0
	for k in 7:
		var x := -length * 0.5 + k * col
		box(Vector3(1.6, height, 1.6), xf * Transform3D(Basis(), Vector3(x, height * 0.5, back + 1.0)), dark)
		box(Vector3(0.8, 14, 0.8), xf * Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-62)), Vector3(x, height - 6, back - 3)),
				dark)
	box(Vector3(length + 4, 1.0, span), xf * Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-6)),
			Vector3(0, height + 0.5, back + 1.0 - span * 0.5)), dark)
	for k in 5:
		var z := back - k * span / 5.0
		box(Vector3(length, 0.15, 0.3), xf * Transform3D(Basis(), Vector3(0, height - 0.3 + (back - z) * 0.1, z)), glow(CYAN, 2.5))
	box(Vector3(length + 4, 0.5, 0.4), xf * Transform3D(Basis(), Vector3(0, height + span * 0.1, -reach + 1.0)), glow(CYAN, 3.5))


## A floodlight mast `h` tall with a bank of lamps facing -z.
func mast(at: Vector3, h: float, yaw := 0.0) -> void:
	var xf := Transform3D(Basis(Vector3.UP, yaw), at)
	box(Vector3(1.4, h, 1.4), xf * Transform3D(Basis(), Vector3(0, h * 0.5, 0)), dark)
	box(Vector3(9, 4, 0.8), xf * Transform3D(Basis(), Vector3(0, h + 1.5, 0)), dark)
	for k in 4:
		for j in 2:
			box(Vector3(1.6, 1.4, 0.2), xf * Transform3D(Basis(), Vector3(-3.3 + k * 2.2, h + 0.6 + j * 1.8, -0.5)),
					glow(Color(1.0, 0.95, 0.85), 6.0))


## A section's name on a dark board with a lit frame on two legs, facing
## the way `xf`'s +z points.
func section_sign(text: String, xf: Transform3D, color: Color) -> void:
	var w := text.length() * 2.1 + 4.0
	box(Vector3(w, 5.0, 0.5), xf, dark)
	for y: float in [2.6, -2.6]:
		box(Vector3(w + 0.4, 0.25, 0.55), xf * Transform3D(Basis(), Vector3(0, y, 0)), glow(color, 3.0))
	var foot := xf.origin.y
	for s: float in [-1.0, 1.0]:
		box(Vector3(0.8, foot, 0.8), xf * Transform3D(Basis(), Vector3(s * w * 0.4, -foot * 0.5, -0.6)), dark)
	label(text, xf * Transform3D(Basis(), Vector3(0, 0, 0.3)), 300, color, 0.012)
