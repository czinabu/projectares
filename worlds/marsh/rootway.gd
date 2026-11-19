extends RefCounted
## The Spore Marsh's Rootways (DESIGN.md "The Spore Marsh (the Rootways)"):
## its dungeons, part of the one running world like Frostline's Engine,
## each a way down under a forest worked to a keeper.
##
## A Rootway is cut into the ground, not built on it. Its mouth is an open
## cut: a ramp down between root walls, where the ground is left open
## (`Terrain.holes`) and the black water is not drawn. At the cut's foot the
## way goes on under the ground, roofed below the pools' beds: a throat, a
## gallery that loops round a root pillar, a passage down and the keeper's
## round chamber. Squads need room (Caleb's ask): no way is narrower than
## 9 m. A solo player must get through: nothing needs two people.
##
## Every Rootway is laid out the same in its own frame (`frame`): x across,
## z inward from the mouth, y the world's height. Its keeper's fight runs
## on the `Raid`'s keeper machinery ("spawn_boss" with the meta "keeper",
## "boss_socket", "purge" and "vault" markers), its kind in "keeper".

const Flora := preload("res://worlds/marsh/flora.gd")

## The Rootways: where each mouth opens (on whole even metres, so the cut
## lies on the ground's samples), which way it runs in, and its keeper.
const ROOTWAYS := [
	{"name": "the Westwood Rootway", "mouth": Vector2(-96.0, 164.0), "inward": Vector2(0.0, -1.0),
			"keeper": "rootmother", "boss_name": "The Rootmother"},
]

## The cut: a ramp this long, open to the sky, from the ground down to the
## tunnels' floor.
const CUT := 36.0
## Half a tunnel's width inside its walls, and how thick the walls and the
## roof are.
const HALF := 6.0
const WALL := 2.0
const ROOF_THICK := 0.8
## Where the hole in the ground reaches each side of the middle.
const CUT_HALF := HALF + WALL
## The floor under the throat and the gallery, and the roof over all of it:
## under the deepest pool's bed, with a squad's headroom.
const FLOOR := -10.0
const ROOF := -4.5
## The keeper's chamber is lower: more room over a big beast.
const CHAMBER_FLOOR := -12.0
## The throat, from the cut's foot to the gallery.
const THROAT_END := 44.0
## The gallery ([x0, x1, z0, z1]) and the root pillar it loops round.
const GALLERY := [-17.0, 17.0, 44.0, 72.0]
const PILLAR := [-5.0, 5.0, 53.0, 63.0]
## The passage down from the gallery to the chamber.
const PASSAGE_END := 80.0
## The keeper's chamber: its middle (on z) and its radius.
const CHAMBER_Z := 96.0
const CHAMBER_RADIUS := 16.0
const CHAMBER_SIDES := 20
## The far end of it all, walls included.
const END := CHAMBER_Z + CHAMBER_RADIUS + WALL

## The keeper's fight: how far its arena reaches round it, when it comes
## back, where its sockets are (degrees round the chamber, 0 at the door)
## and its purge lanes, the spore vents ([from, to] on the floor, x and z).
const ARENA := 17.0
const RESPAWN := 600.0
const SOCKETS := [70.0, 130.0, -70.0, -130.0]
const VENTS := [
	[Vector2(-13.0, 89.0), Vector2(13.0, 89.0)],
	[Vector2(-13.0, 103.0), Vector2(13.0, 103.0)],
	[Vector2(-8.0, 84.0), Vector2(-8.0, 108.0)],
	[Vector2(8.0, 84.0), Vector2(8.0, 108.0)],
]
const VENT_WIDTH := 4.0
const VENT_DAMAGE := 22.0


## A Rootway's frame: x across, y up, z inward from its mouth.
static func frame(way: Dictionary) -> Transform3D:
	var inward: Vector2 = way["inward"]
	var z := Vector3(inward.x, 0.0, inward.y)
	var x := Vector3.UP.cross(z)
	var mouth: Vector2 = way["mouth"]
	return Transform3D(Basis(x, Vector3.UP, z), Vector3(mouth.x, 0.0, mouth.y))


## Where a world point sits in a Rootway's frame.
static func local(way: Dictionary, pos: Vector3) -> Vector3:
	return frame(way).affine_inverse() * pos


## The open cut of each Rootway, as rectangles of the map (x, z): the
## ground is left open there (`Terrain.holes`).
static func holes() -> Array[Rect2]:
	var out: Array[Rect2] = []
	for way: Dictionary in ROOTWAYS:
		var f := frame(way)
		var a := f * Vector3(-CUT_HALF, 0.0, 0.0)
		var b := f * Vector3(CUT_HALF, 0.0, CUT)
		out.append(Rect2(Vector2(minf(a.x, b.x), minf(a.z, b.z)), Vector2(absf(a.x - b.x), absf(a.z - b.z))))
	return out


## Whether (x, z) is in or at the edge of a Rootway's cut, by `margin`:
## nothing of the forest floor grows there.
static func in_cut(x: float, z: float, margin := 1.0) -> bool:
	for hole in holes():
		if hole.grow(margin).has_point(Vector2(x, z)):
			return true
	return false


## Whether a point is inside a Rootway, under its roof: out of the weather
## and in its close air.
static func inside(pos: Vector3) -> bool:
	return way_at(pos) >= 0


## The index of the Rootway a point is inside, or -1.
static func way_at(pos: Vector3) -> int:
	for i in ROOTWAYS.size():
		var p := local(ROOTWAYS[i], pos)
		if p.y > ROOF or p.y < CHAMBER_FLOOR - 1.0 or p.z < CUT or p.z > END:
			continue
		if absf(p.x) <= HALF + WALL * 0.5 or (p.z > GALLERY[2] - WALL and p.z < GALLERY[3] + WALL
				and absf(p.x) <= GALLERY[1] + WALL * 0.5):
			return i
		if Vector2(p.x, p.z - CHAMBER_Z).length() <= CHAMBER_RADIUS + WALL * 0.5:
			return i
	return -1


## The height of a Rootway's floor at (x, z) in its frame, `top` being the
## ground at its mouth: the ramp, the throat and gallery, the passage down,
## the chamber.
static func floor_at(z: float, top: float) -> float:
	if z <= CUT:
		return lerpf(top, FLOOR, clampf(z / CUT, 0.0, 1.0))
	if z <= GALLERY[3] + 1.0:
		return FLOOR
	if z < PASSAGE_END:
		return lerpf(FLOOR, CHAMBER_FLOOR, (z - GALLERY[3] - 1.0) / (PASSAGE_END - GALLERY[3] - 1.0))
	return CHAMBER_FLOOR


## Builds every Rootway into `map`: what is walked on and walked round
## (floors, the pillar, the knots) in a navigation region of its own (the
## open ground's bake would tangle with layers under it), its shell (walls,
## roofs, the cut's sides) beside it so no mesh is baked over their tops,
## all of it drawn merged, one mesh for the floors (`floor_material`) and
## one for the rest (`wall_material`); a link from the ground at the mouth
## onto the ramp; and its markers. Returns the regions, for the map to bake.
static func build(map: Node3D, floor_material: Material, wall_material: Material) -> Array[NavigationRegion3D]:
	var regions: Array[NavigationRegion3D] = []
	for i in ROOTWAYS.size():
		var way: Dictionary = ROOTWAYS[i]
		var f := frame(way)
		var parts := Parts.new(f, floor_material, wall_material)
		var region := NavigationRegion3D.new()
		region.name = "Rootway%d" % i
		map.add_child(region)
		regions.append(region)
		parts.floors.name = "Floors"
		region.add_child(parts.floors)
		parts.shell.name = "Shell"
		region.add_child(parts.shell)
		var top := float(map.call("ground_height", f.origin.x, f.origin.z))
		var ground := func(x: float, z: float) -> float:
			var at := f * Vector3(x, 0.0, z)
			return float(map.call("ground_height", at.x, at.z))
		_build_cut(parts, top, ground)
		_build_tunnels(parts)
		_build_chamber(parts)
		parts.flush()
		_place_markers(map, way, f)
		parts.floors.set_meta("top", top)
		var link := NavigationLink3D.new()
		link.name = "Mouth"
		link.bidirectional = true
		link.start_position = f * Vector3(0.0, float(ground.call(0.0, -1.5)), -1.5)
		link.end_position = f * Vector3(0.0, floor_at(2.0, top), 2.0)
		region.add_child(link)
	return regions


## The cut: a ramp down between root walls whose tops stand a little over
## the ground at the hole's edge, so it never shows.
static func _build_cut(parts: Parts, top: float, ground: Callable) -> void:
	parts.slope(-HALF, HALF, Vector2(0.0, top), Vector2(CUT, FLOOR), 1.0)
	var step := 4.0
	var z := 0.0
	while z < CUT:
		var z1 := minf(z + step, CUT)
		var low := floor_at(z1, top) - 1.0
		for side: float in [-1.0, 1.0]:
			var high := -INF
			for k in 5:
				high = maxf(high, float(ground.call(side * (CUT_HALF + 0.1), lerpf(z, z1, k / 4.0))))
				high = maxf(high, float(ground.call(side * (CUT_HALF - 1.0), lerpf(z, z1, k / 4.0))))
			parts.box(Vector3(side * (HALF + (WALL + 0.4) * 0.5), 0.0, (z + z1) * 0.5),
					Vector2(WALL + 0.4, z1 - z + 0.2), low, high + 0.4)
		z = z1
	# The portal at the cut's foot: from the roof up over the ground.
	var over := -INF
	for x: float in [-CUT_HALF, -HALF, 0.0, HALF, CUT_HALF]:
		over = maxf(over, float(ground.call(x, CUT + 0.5)))
	parts.box(Vector3(0.0, 0.0, CUT + 0.8), Vector2(CUT_HALF * 2.0 + 0.8, 2.0), ROOF, over + 0.4)


## The throat, the gallery round its pillar and the passage down.
static func _build_tunnels(parts: Parts) -> void:
	var g: Array = GALLERY
	var p: Array = PILLAR
	var roof_top := ROOF + ROOF_THICK
	# The throat.
	parts.box(Vector3(0, 0, (CUT + THROAT_END) * 0.5), Vector2(HALF * 2.0, THROAT_END - CUT), FLOOR - 1.0, FLOOR, 0.0, true, true)
	for side: float in [-1.0, 1.0]:
		parts.box(Vector3(side * (HALF + WALL * 0.5), 0, (CUT + THROAT_END) * 0.5), Vector2(WALL, THROAT_END - CUT),
				FLOOR - 1.0, roof_top)
	parts.box(Vector3(0, 0, (CUT + THROAT_END) * 0.5), Vector2(CUT_HALF * 2.0, THROAT_END - CUT), ROOF, roof_top)
	# The gallery: a floor round the pillar, walls with the two doors, a roof.
	var x0 := float(g[0])
	var x1 := float(g[1])
	var z0 := float(g[2])
	var z1 := float(g[3]) + 1.0
	for piece: Array in [[x0, x1, z0, float(p[2])], [x0, x1, float(p[3]), z1], [x0, float(p[0]), float(p[2]), float(p[3])],
			[float(p[1]), x1, float(p[2]), float(p[3])]]:
		parts.box(Vector3((float(piece[0]) + float(piece[1])) * 0.5, 0, (float(piece[2]) + float(piece[3])) * 0.5),
				Vector2(float(piece[1]) - float(piece[0]), float(piece[3]) - float(piece[2])), FLOOR - 1.0, FLOOR, 0.0, true, true)
	var gx := x1 + WALL
	var gz0 := z0 - WALL
	var gz1 := float(g[3]) + WALL
	parts.box(Vector3(0, 0, (gz0 + gz1) * 0.5), Vector2(gx * 2.0, gz1 - gz0), ROOF, roof_top)
	for side: float in [-1.0, 1.0]:
		parts.box(Vector3(side * (x1 + WALL * 0.5), 0, (gz0 + gz1) * 0.5), Vector2(WALL, gz1 - gz0),
				FLOOR - 1.0, roof_top)
		var span := x1 + WALL - HALF
		for z: float in [z0 - WALL * 0.5, float(g[3]) + WALL * 0.5]:
			parts.box(Vector3(side * (HALF + span * 0.5), 0, z), Vector2(span, WALL), FLOOR - 1.0, roof_top)
	# The pillar: its foot is walked round, the rest stands up into the roof.
	var mid := Vector3((float(p[0]) + float(p[1])) * 0.5, 0, (float(p[2]) + float(p[3])) * 0.5)
	var size := Vector2(float(p[1]) - float(p[0]), float(p[3]) - float(p[2]))
	parts.box(mid, size, FLOOR - 1.0, FLOOR + 2.5, 0.0, true)
	parts.box(mid, size, FLOOR + 2.5, ROOF + 0.1)
	# The passage down to the chamber.
	var door := CHAMBER_Z - sqrt(CHAMBER_RADIUS * CHAMBER_RADIUS - CUT_HALF * CUT_HALF) + 1.0
	parts.slope(-HALF, HALF, Vector2(z1, FLOOR), Vector2(PASSAGE_END, CHAMBER_FLOOR), 1.0)
	for side: float in [-1.0, 1.0]:
		parts.box(Vector3(side * (HALF + WALL * 0.5), 0, (float(g[3]) + door) * 0.5), Vector2(WALL, door - float(g[3])),
				CHAMBER_FLOOR - 1.0, roof_top)
	parts.box(Vector3(0, 0, (float(g[3]) + door) * 0.5), Vector2(CUT_HALF * 2.0, door - float(g[3])), ROOF, roof_top)


## The keeper's round chamber: a round floor, a ring of root walls with the
## door toward the passage, a roof, and a few knots of root for cover.
static func _build_chamber(parts: Parts) -> void:
	var roof_top := ROOF + ROOF_THICK
	var reach := CHAMBER_RADIUS + WALL
	parts.disc(Vector3(0, CHAMBER_FLOOR - 0.5, CHAMBER_Z), CHAMBER_RADIUS + 0.3, 1.0)
	# The step in from the passage, over the ring's edge.
	var door := CHAMBER_Z - CHAMBER_RADIUS
	parts.box(Vector3(0, 0, door + 1.0), Vector2(HALF * 2.0, 2.4), CHAMBER_FLOOR - 1.0, CHAMBER_FLOOR, 0.0, true, true)
	parts.box(Vector3(0, 0, CHAMBER_Z), Vector2(reach * 2.0, reach * 2.0), ROOF, roof_top)
	var step := TAU / CHAMBER_SIDES
	var width := 2.0 * reach * tan(step * 0.5) + 0.3
	for k in CHAMBER_SIDES:
		var a := k * step
		var out := Vector3(-sin(a), 0.0, -cos(a))
		# The door: the passage comes in from the cut's side (angle 0).
		if absf(CHAMBER_RADIUS * sin(a)) < CUT_HALF and cos(a) > 0.0:
			continue
		var mid := Vector3(0, 0, CHAMBER_Z) + out * (CHAMBER_RADIUS + WALL * 0.5)
		parts.box(mid, Vector2(width, WALL), CHAMBER_FLOOR - 1.0, roof_top, a)
	# Knots of root to duck behind, clear of the vents.
	for knot: Array in [[Vector2(-12.5, 96.0), 0.4], [Vector2(12.5, 96.0), -0.4]]:
		var at: Vector2 = knot[0]
		parts.box(Vector3(at.x, 0, at.y), Vector2(3.2, 1.8), CHAMBER_FLOOR - 0.2, CHAMBER_FLOOR + 1.5, float(knot[1]), true)


## The Rootway's markers: its garrison and caches in the gallery, its
## keeper in the chamber with its sockets, spore vents and vault.
static func _place_markers(map: Node3D, way: Dictionary, f: Transform3D) -> void:
	var kind: String = way["keeper"]
	for guard: Array in [[Vector3(-11.0, FLOOR, 58.0), "stalker", 7.0], [Vector3(11.0, FLOOR, 58.0), "stalker", 7.0],
			[Vector3(0.0, FLOOR, 68.0), "bloater", 4.0], [Vector3(0.0, FLOOR, 40.0), "stalker", 5.0]]:
		var marker: Marker3D = map.call("_add_marker", "spawn_guard", f * (guard[0] as Vector3))
		marker.set_meta("faction", guard[1])
		marker.set_meta("radius", guard[2])
	for spot: Vector3 in [Vector3(-14.5, FLOOR + 0.1, 46.5), Vector3(14.5, FLOOR + 0.1, 69.5)]:
		(map.call("_add_marker", "spawn_cache", f * spot) as Marker3D).set_meta("loot_source", "rootway")
	var boss: Marker3D = map.call("_add_marker", "spawn_boss", f * Vector3(0, CHAMBER_FLOOR + 0.1, CHAMBER_Z + 2.0))
	boss.set_meta("faction", "keeper")
	boss.set_meta("boss", kind)
	boss.set_meta("keeper", true)
	boss.set_meta("radius", CHAMBER_RADIUS - 4.0)
	boss.set_meta("arena", ARENA)
	boss.set_meta("respawn", RESPAWN)
	boss.set_meta("name", way["name"])
	for angle: float in SOCKETS:
		var a := deg_to_rad(angle)
		var at := Vector3(-sin(a), 0.0, -cos(a)) * (CHAMBER_RADIUS - 1.5) + Vector3(0, CHAMBER_FLOOR + 0.1, CHAMBER_Z)
		var socket: Marker3D = map.call("_add_marker", "boss_socket", f * at)
		socket.set_meta("keeper", kind)
		socket.set_meta("faction", "broodling")
	for lane: Array in VENTS:
		var from: Vector2 = lane[0]
		var to: Vector2 = lane[1]
		var purge: Marker3D = map.call("_add_marker", "purge", f * Vector3(from.x, CHAMBER_FLOOR + 0.1, from.y))
		purge.set_meta("keeper", kind)
		purge.set_meta("toward", f * Vector3(to.x, CHAMBER_FLOOR + 0.1, to.y))
		purge.set_meta("width", VENT_WIDTH)
		purge.set_meta("damage", VENT_DAMAGE)
	var vault: Marker3D = map.call("_add_marker", "vault", f * Vector3(0, CHAMBER_FLOOR + 0.1, CHAMBER_Z + CHAMBER_RADIUS - 3.5))
	vault.basis = f.basis
	vault.set_meta("keeper", kind)


## Solid parts in a Rootway's frame: a collision shape each, on `floors`
## (baked into the navigation mesh) or on `shell` (not), drawn merged as
## one mesh on the shell.
class Parts:
	var floors := StaticBody3D.new()
	var shell := StaticBody3D.new()
	var floor_material: Material
	var wall_material: Material
	var floor_tool := SurfaceTool.new()
	var wall_tool := SurfaceTool.new()

	func _init(frame: Transform3D, p_floor: Material, p_wall: Material) -> void:
		for body: StaticBody3D in [floors, shell]:
			body.collision_layer = Actor.LAYER_WORLD
			body.collision_mask = 0
			body.transform = frame
		floor_material = p_floor
		wall_material = p_wall
		floor_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		wall_tool.begin(Mesh.PRIMITIVE_TRIANGLES)

	## A box standing on (x, z) of `at` (its y ignored), `size` across (x)
	## and along (z), from `low` to `high`, turned `yaw` round the up axis;
	## `walked` puts it with the floors, `ground` draws it as one.
	func box(at: Vector3, size: Vector2, low: float, high: float, yaw := 0.0, walked := false, ground := false) -> void:
		var shape := BoxShape3D.new()
		shape.size = Vector3(size.x, high - low, size.y)
		var mesh := BoxMesh.new()
		mesh.size = shape.size
		add(shape, mesh, Transform3D(Basis(Vector3.UP, yaw), Vector3(at.x, (low + high) * 0.5, at.z)), walked, ground)

	## A slab from `a` to `b` (each (z, y), its top along that line) between
	## `x_from` and `x_to`: a ramp, walked on.
	func slope(x_from: float, x_to: float, a: Vector2, b: Vector2, thick: float) -> void:
		var run := b - a
		var basis := Basis(Vector3.RIGHT, atan2(-run.y, run.x))
		var mid := Vector3((x_from + x_to) * 0.5, (a.y + b.y) * 0.5, (a.x + b.x) * 0.5)
		var shape := BoxShape3D.new()
		shape.size = Vector3(x_to - x_from, thick, run.length())
		var mesh := BoxMesh.new()
		mesh.size = shape.size
		add(shape, mesh, Transform3D(basis, mid - basis.y * thick * 0.5), true, true)

	## A round floor, walked on, centred on `at`.
	func disc(at: Vector3, radius: float, thick: float) -> void:
		var shape := CylinderShape3D.new()
		shape.radius = radius
		shape.height = thick
		var mesh := CylinderMesh.new()
		mesh.top_radius = radius
		mesh.bottom_radius = radius
		mesh.height = thick
		mesh.radial_segments = 32
		mesh.rings = 1
		add(shape, mesh, Transform3D(Basis.IDENTITY, at), true, true)

	func add(shape: Shape3D, mesh: Mesh, at: Transform3D, walked: bool, ground: bool) -> void:
		var col := CollisionShape3D.new()
		col.shape = shape
		col.transform = at
		(floors if walked else shell).add_child(col)
		(floor_tool if ground else wall_tool).append_from(mesh, 0, at)

	func flush() -> void:
		var mesh := wall_tool.commit()
		mesh.surface_set_material(0, wall_material)
		floor_tool.commit(mesh)
		mesh.surface_set_material(1, floor_material)
		var node := MeshInstance3D.new()
		node.name = "Greybox"
		node.mesh = mesh
		shell.add_child(node)


# --- Dressing (view only) ---------------------------------------------------------

## The Rootway's walls and roof where `Look` is on: root flesh, a beast's
## hide (`creature.gdshader`) in dark bark and mauve, wet, with a few lit
## freckles, patterned in the Rootway's own frame.
static func wall_material() -> Material:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://assets/shaders/creature.gdshader") as Shader
	mat.set_shader_parameter("hide", Color(0.3, 0.23, 0.22))
	mat.set_shader_parameter("mottle", Color(0.19, 0.14, 0.15))
	mat.set_shader_parameter("under", Color(0.36, 0.3, 0.3))
	mat.set_shader_parameter("glow", Color(0.45, 1.0, 0.6))
	mat.set_shader_parameter("patches", 0.7)
	mat.set_shader_parameter("freckles", 0.05)
	mat.set_shader_parameter("freckle_energy", 2.2)
	mat.set_shader_parameter("wet", 0.65)
	mat.set_shader_parameter("rim", 0.0)
	return mat


## The vents' colours: dim cracks at rest, ochre while one warns, a bright
## jade gush while it vents.
const VENT_REST := Color(0.25, 0.55, 0.4)
const VENT_WARN := Color(1.0, 0.62, 0.2)
const VENT_GUSH := Color(0.6, 1.0, 0.55)
## The chamber's light by its keeper's phase: fallen (a calm warm glow),
## standing (jade), venting (ochre).
const CHAMBER_GLOW := [Color(1.0, 0.78, 0.5), Color(0.45, 1.0, 0.6), Color(1.0, 0.55, 0.25)]


## Dresses every Rootway into `art` where `Look` is on: roots hanging from
## the roof and climbing the walls, glowcaps along the walls' feet, jade
## lights, egg sacs in the keeper's sockets, its vault's cocoon and its
## spore vents. Returns the vents' views, by their place among the map's
## "purge" markers ({ material, column, state, since }), and the chamber
## lights ({ light, keeper }).
static func dress(art: Node3D, seed: int, ground: Callable) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var vents: Array[Dictionary] = []
	var lights: Array[Dictionary] = []
	var roots := SurfaceTool.new()
	roots.begin(Mesh.PRIMITIVE_TRIANGLES)
	var caps: Array[Transform3D] = []
	var eggs: Array[Transform3D] = []
	for way: Dictionary in ROOTWAYS:
		var f := frame(way)
		var top := float(ground.call(f.origin.x, f.origin.z))
		_dress_roots(roots, f, rng, top)
		_dress_caps(caps, f, rng, top)
		# Jade lights down the way, none casting shadows.
		for spot: Vector3 in [Vector3(0, FLOOR + 4.2, 40.0), Vector3(-11.0, FLOOR + 4.2, 52.0), Vector3(11.0, FLOOR + 4.2, 64.0),
				Vector3(0, FLOOR + 3.5, 76.0)]:
			art.add_child(_light(f * spot, Color(0.45, 1.0, 0.65), 2.4, 15.0))
		var chamber := _light(f * Vector3(0, ROOF - 1.5, CHAMBER_Z), CHAMBER_GLOW[1], 3.0, 28.0)
		art.add_child(chamber)
		lights.append({"light": chamber, "keeper": way["keeper"]})
		# The sockets' egg sacs and the vault's cocoon.
		for angle: float in SOCKETS:
			var a := deg_to_rad(angle)
			var at := Vector3(-sin(a), 0.0, -cos(a)) * (CHAMBER_RADIUS - 0.4) + Vector3(0, CHAMBER_FLOOR, CHAMBER_Z)
			for k in 9:
				var s := rng.randf_range(0.3, 0.6)
				var up := rng.randf_range(0.3, 2.6)
				var off := Vector3(rng.randf_range(-1.3, 1.3), up, rng.randf_range(-0.3, 0.3))
				eggs.append(Transform3D(Basis(Vector3.UP, -a).scaled(Vector3(s, s * 1.3, s)), f * (at + Basis(Vector3.UP, -a) * off)))
			art.add_child(_light(f * (at + Vector3(0, 1.6, 0) - Vector3(-sin(a), 0, -cos(a)) * 1.2), Color(0.6, 1.0, 0.5), 1.5, 8.0))
		var vault := f * Vector3(0, CHAMBER_FLOOR, CHAMBER_Z + CHAMBER_RADIUS - 1.6)
		for k in 14:
			var s := rng.randf_range(0.4, 0.9)
			eggs.append(Transform3D(Basis.from_scale(Vector3(s * 1.2, s * 1.5, s)),
					vault + f.basis * Vector3(rng.randf_range(-2.2, 2.2), rng.randf_range(0.3, 2.8), rng.randf_range(-0.4, 0.6))))
		# The vents: a crack along each lane's floor and a column over it.
		for lane: Array in VENTS:
			vents.append(_vent(art, f, lane))
	var root_mat := StandardMaterial3D.new()
	root_mat.vertex_color_use_as_albedo = true
	root_mat.roughness = 0.7
	roots.generate_normals()
	roots.set_material(root_mat)
	var root_node := MeshInstance3D.new()
	root_node.name = "Roots"
	root_node.mesh = roots.commit()
	art.add_child(root_node)
	art.add_child(_scatter("RootwayCaps", _cap_mesh(), caps))
	var egg := SphereMesh.new()
	egg.radius = 0.5
	egg.height = 1.0
	egg.radial_segments = 12
	egg.rings = 6
	var egg_mat := StandardMaterial3D.new()
	egg_mat.albedo_color = Color(0.55, 0.62, 0.4)
	egg_mat.emission_enabled = true
	egg_mat.emission = Color(0.6, 0.95, 0.45)
	egg_mat.emission_energy_multiplier = 0.8
	egg_mat.roughness = 0.3
	egg.material = egg_mat
	art.add_child(_scatter("RootwayEggs", egg, eggs))
	return {"vents": vents, "lights": lights}


## Roots: hanging from the roof all the way down, and climbing the walls.
static func _dress_roots(st: SurfaceTool, f: Transform3D, rng: RandomNumberGenerator, top: float) -> void:
	var dark := Color(0.16, 0.12, 0.12)
	var pale := Color(0.4, 0.32, 0.3)
	var spots: Array[Vector2] = []
	var z := CUT + 2.0
	while z < END - 2.0:
		for k in 3:
			spots.append(Vector2(rng.randf_range(-HALF + 0.5, HALF - 0.5), z + rng.randf_range(-1.5, 1.5)))
			if z > GALLERY[2] and z < GALLERY[3]:
				spots.append(Vector2(rng.randf_range(GALLERY[0] + 0.5, GALLERY[1] - 0.5), z + rng.randf_range(-1.5, 1.5)))
			if z > CHAMBER_Z - CHAMBER_RADIUS and z < CHAMBER_Z + CHAMBER_RADIUS:
				var a := rng.randf() * TAU
				spots.append(Vector2(cos(a), sin(a)) * sqrt(rng.randf()) * (CHAMBER_RADIUS - 1.0) + Vector2(0, CHAMBER_Z))
		z += 2.5
	for at in spots:
		var roof := ROOF
		var low := floor_at(at.y, top) + 2.4
		var length := rng.randf_range(0.8, minf(3.2, roof - low))
		var points := PackedVector3Array()
		var radii := PackedFloat32Array()
		var colours: Array[Color] = []
		var sway := Vector3(rng.randf_range(-0.4, 0.4), 0, rng.randf_range(-0.4, 0.4))
		var thick := rng.randf_range(0.05, 0.16)
		for i in 5:
			var t := i / 4.0
			points.append(f * (Vector3(at.x, roof + 0.05 - length * t, at.y) + sway * t * t))
			radii.append(thick * (1.0 - t * 0.85))
			colours.append(dark.lerp(pale, t))
		Flora._tube(st, points, radii, colours, 5)
	# Thick roots down the walls of the cut and round the chamber.
	for k in 26:
		var side := -1.0 if k % 2 == 0 else 1.0
		var z0 := rng.randf_range(2.0, CUT - 2.0)
		var zz := z0 + rng.randf_range(-3.0, 3.0)
		var high := floor_at(z0, top) + 7.0
		_wall_root(st, f, Vector3(side * (HALF + 0.15), minf(high, top + 0.2), z0), Vector3(side * (HALF + 0.15), floor_at(zz, top) - 0.2, zz),
				rng, dark, pale)
	for k in 18:
		var a := rng.randf() * TAU
		if cos(a) > 0.92:
			continue
		var out := Vector3(-sin(a), 0, -cos(a))
		var foot := Vector3(0, CHAMBER_FLOOR - 0.2, CHAMBER_Z) + out * (CHAMBER_RADIUS - 0.1)
		var b := a + rng.randf_range(-0.25, 0.25)
		var head := Vector3(0, ROOF - 0.1, CHAMBER_Z) + Vector3(-sin(b), 0, -cos(b)) * (CHAMBER_RADIUS - 0.1)
		_wall_root(st, f, head, foot, rng, dark, pale)


static func _wall_root(st: SurfaceTool, f: Transform3D, from: Vector3, to: Vector3, rng: RandomNumberGenerator, dark: Color,
		pale: Color) -> void:
	var points := PackedVector3Array()
	var radii := PackedFloat32Array()
	var colours: Array[Color] = []
	var thick := rng.randf_range(0.12, 0.28)
	var wobble := rng.randf() * TAU
	for i in 9:
		var t := i / 8.0
		var p := from.lerp(to, t)
		p += Vector3(0, 0, sin(t * 5.0 + wobble) * 0.25)
		points.append(f * p)
		radii.append(thick * (0.7 + 0.3 * sin(t * PI)))
		colours.append(dark.lerp(pale, 0.3 + 0.3 * sin(t * 3.0 + wobble)))
	Flora._tube(st, points, radii, colours, 6)


## Glowcaps in clumps along the walls' feet, thickest in the chamber.
static func _dress_caps(caps: Array[Transform3D], f: Transform3D, rng: RandomNumberGenerator, top: float) -> void:
	var clumps: Array[Vector2] = []
	var z := 4.0
	while z < GALLERY[3]:
		var half := HALF if z < GALLERY[2] or z > GALLERY[3] else GALLERY[1]
		clumps.append(Vector2(-(half - 0.5), z + rng.randf_range(-1.0, 1.0)))
		clumps.append(Vector2(half - 0.5, z + rng.randf_range(2.0, 4.0)))
		z += 6.0
	for k in 16:
		var a := TAU * k / 16.0 + rng.randf_range(-0.1, 0.1)
		if cos(a) > 0.85:
			continue
		clumps.append(Vector2(-sin(a), -cos(a)) * (CHAMBER_RADIUS - 0.6) + Vector2(0, CHAMBER_Z))
	for clump in clumps:
		for k in rng.randi_range(4, 9):
			var at := clump + Vector2(rng.randf_range(-0.6, 0.6), rng.randf_range(-0.9, 0.9))
			var y := floor_at(at.y, top)
			var size := rng.randf_range(0.8, 2.4)
			caps.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * size), f * Vector3(at.x, y - 0.02, at.y)))


static func _cap_mesh() -> Mesh:
	var cap := SphereMesh.new()
	cap.radius = 0.13
	cap.height = 0.14
	cap.is_hemisphere = true
	cap.radial_segments = 8
	cap.rings = 3
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.55, 0.45)
	mat.emission_enabled = true
	mat.emission = Color(0.3, 0.9, 0.6)
	mat.emission_energy_multiplier = 1.2
	cap.material = mat
	return cap


static func _scatter(title: String, mesh: Mesh, spots: Array[Transform3D]) -> MultiMeshInstance3D:
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = spots.size()
	for i in spots.size():
		multi.set_instance_transform(i, spots[i])
	var node := MultiMeshInstance3D.new()
	node.name = title
	node.multimesh = multi
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


static func _light(at: Vector3, color: Color, energy: float, reach: float) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.position = at
	light.light_color = color
	light.light_energy = energy
	light.omni_range = reach
	light.shadow_enabled = false
	return light


## One vent's view: a lit crack along the lane and a column of spores over
## it that shows only while it vents.
static func _vent(art: Node3D, f: Transform3D, lane: Array) -> Dictionary:
	var from: Vector2 = lane[0]
	var to: Vector2 = lane[1]
	var run := to - from
	var mid := (from + to) * 0.5
	var basis := f.basis * Basis(Vector3.UP, atan2(run.x, run.y))
	var crack_mat := StandardMaterial3D.new()
	crack_mat.albedo_color = Color(0.05, 0.06, 0.05)
	crack_mat.emission_enabled = true
	crack_mat.emission = VENT_REST
	crack_mat.emission_energy_multiplier = 0.6
	var crack := BoxMesh.new()
	crack.size = Vector3(0.7, 0.06, run.length())
	crack.material = crack_mat
	var crack_node := MeshInstance3D.new()
	crack_node.mesh = crack
	crack_node.transform = Transform3D(basis, f * Vector3(mid.x, CHAMBER_FLOOR + 0.02, mid.y))
	crack_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	art.add_child(crack_node)
	var column_mat := StandardMaterial3D.new()
	column_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	column_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	column_mat.albedo_color = Color(VENT_GUSH, 0.0)
	column_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	column_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	var column := BoxMesh.new()
	column.size = Vector3(VENT_WIDTH, 3.2, run.length())
	column.material = column_mat
	var column_node := MeshInstance3D.new()
	column_node.mesh = column
	column_node.transform = Transform3D(basis, f * Vector3(mid.x, CHAMBER_FLOOR + 1.6, mid.y))
	column_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	column_node.visible = false
	art.add_child(column_node)
	return {"crack": crack_mat, "column": column_node, "column_mat": column_mat, "state": 0, "since": 0.0}


## Plays the vents and the chamber's light (view only): `vents` from
## `dress`, `phases` the map's "keepers" meta, `now` in seconds.
static func animate(views: Dictionary, phases: Dictionary, now: float) -> void:
	for view: Dictionary in views.get("vents", []):
		var crack := view.crack as StandardMaterial3D
		var column := view.column as MeshInstance3D
		var age := now - float(view.since)
		match int(view.state):
			1:
				crack.emission = VENT_WARN
				crack.emission_energy_multiplier = 2.0 + 2.0 * sin(age * 14.0)
				column.visible = false
			2:
				crack.emission = VENT_GUSH
				crack.emission_energy_multiplier = 5.0
				column.visible = true
				(view.column_mat as StandardMaterial3D).albedo_color = Color(VENT_GUSH, 0.35 * clampf(1.0 - age * 0.6, 0.25, 1.0))
			_:
				crack.emission = VENT_REST
				crack.emission_energy_multiplier = 0.6
				column.visible = false
	for entry: Dictionary in views.get("lights", []):
		var phase := int(phases.get(entry.keeper, 1))
		var light := entry.light as OmniLight3D
		light.light_color = CHAMBER_GLOW[clampi(phase, 0, 2)]
		light.light_energy = 3.0 if phase != 0 else 1.8
