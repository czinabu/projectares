extends RefCounted
## Skyhook, Meridian's second Street circuit (DESIGN.md section 9): a figure
## of eight on stilts north of Coilrun's pits. Off the line it sweeps east
## and climbs onto the deck, turns back west over its own start straight on
## the Flyover, then winds a turn and a half down the Corkscrew round a lit
## pylon and runs back to the line along the flats.
##
## The track is data like Coilrun's (`CONTROL`, `CHECKPOINTS`, `LINE`, all
## from `AT`); the road, its low walls and the deck under it are laid along
## the same centre line with collision, so what you drive is what is judged.
## The road banks a little into the bends (at most `MAX_BANK`); the race only
## reads the centre line. Gantry, arches and board carry the meta "track"
## so `RaceView` keeps them apart from Coilrun's. Built by the map
## (`worlds/meridian/map.gd`); decoration only where `Look` is on.

const TRACK_ID := "skyhook"
const TRACK_NAME := "Skyhook"
const WIDTH := 13.0
const LAPS := 3
## Where the track's own coordinates start: the middle of its start straight.
const AT := Vector3(-190, 0, -125)
## The Corkscrew's pylon, from `AT`, and the turn's radius.
const CORKSCREW := Vector3(-110, 0, 70)
const CORKSCREW_R := 40.0
## How far the road leans into a bend, in radians.
const MAX_BANK := 0.1
## Below this a road sample is on the flats; above it, on the deck.
const DECK_FROM := 1.2
## The deck's walls: how high and how far above the flats they start.
const WALL_H := 1.1
const WALL_FROM := 2.0
const LINE := Vector3(-20, 0, 0)
const CHECKPOINTS := [Vector3(160, 8, -110), Vector3(-40, 18, 55), Vector3(-150, 1, 20)]
const MAGENTA := Color(1.0, 0.3, 0.7)
const CYAN := Color(0.3, 0.85, 1.0)

var map: Node3D
var track: RaceTrack
## The bank at each centre line sample, in radians (+ leans right side down).
var banks := PackedFloat32Array()


func _init(p_map: Node3D) -> void:
	map = p_map


## The centre line's control points, clockwise, in the world.
static func control() -> Array[Vector3]:
	var points: Array[Vector3] = [
		Vector3(-60, 0, 0), Vector3(60, 0, 0), Vector3(120, 0, 8), Vector3(170, 3, -40),
		Vector3(160, 8, -110), Vector3(90, 14, -135), Vector3(40, 18, -80), Vector3(0, 20, 0),
		Vector3(-40, 18, 55),
	]
	# The Corkscrew: a turn and a half down round the pylon.
	for k in 13:
		var th := 3.0 * PI * k / 12.0
		points.append(CORKSCREW + Vector3(cos(th) * CORKSCREW_R, 16.0 - 13.0 * k / 12.0, sin(th) * CORKSCREW_R))
	points.append_array([Vector3(-150, 1, 20), Vector3(-130, 0, -15), Vector3(-95, 0, -6)] as Array[Vector3])
	var out: Array[Vector3] = []
	for p in points:
		out.append(AT + p)
	return out


static func build_track() -> RaceTrack:
	var spots: Array[Vector3] = []
	for p: Vector3 in CHECKPOINTS:
		spots.append(AT + p)
	var t := RaceTrack.build(TRACK_ID, TRACK_NAME, control(), WIDTH, spots, AT + LINE, LAPS)
	return t


## Builds what the race needs everywhere, a server included: the road with
## its walls, the pits and their bays, the gantry, the arches and the board.
func build(p_track: RaceTrack) -> void:
	track = p_track
	_work_out_banks()
	_build_road()
	_build_pits()
	map.call("_build_gantry", track, TRACK_ID, MAGENTA)
	map.call("_build_gates", track, TRACK_ID, MAGENTA)


func _work_out_banks() -> void:
	var n := track.points.size()
	var raw := PackedFloat32Array()
	raw.resize(n)
	for i in n:
		var a := track.forward((i - 4 + n) % n)
		var b := track.forward((i + 4) % n)
		raw[i] = clampf(a.cross(b).y * 1.2, -MAX_BANK, MAX_BANK) if track.points[i].y > DECK_FROM else 0.0
	banks.resize(n)
	for i in n:
		var sum := 0.0
		for k in range(-6, 7):
			sum += raw[(i + k + n) % n]
		banks[i] = sum / 13.0


## Across the road at sample `i`, banked: right is +.
func across(i: int) -> Vector3:
	return track.side(i).rotated(track.forward(i), -banks[i])


func _build_road() -> void:
	var road := Look.surface("asphalt", {"tint": Color(0.5, 0.5, 0.56), "grime": 0.2, "scale": 0.25})
	var deck_mat := map.call("_metal", Color(0.14, 0.14, 0.17), 0.3) as Material
	var top := SurfaceTool.new()
	top.begin(Mesh.PRIMITIVE_TRIANGLES)
	var deck := SurfaceTool.new()
	deck.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lines := SurfaceTool.new()
	lines.begin(Mesh.PRIMITIVE_TRIANGLES)
	var walls := SurfaceTool.new()
	walls.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := PackedVector3Array()
	var pts := track.points
	var n := pts.size()
	var lift := Vector3(0, 0.06, 0)
	var half := WIDTH * 0.5
	for i in n:
		var j := (i + 1) % n
		var a := pts[i] + lift
		var b := pts[j] + lift
		var sa := across(i) * half
		var sb := across(j) * half
		var q := [a - sa, a + sa, b + sb, b - sb]
		for v: Vector3 in [q[0], q[2], q[1], q[0], q[3], q[2]]:
			top.set_normal(Vector3.UP)
			top.set_uv(Vector2(v.x, v.z) * 0.25)
			top.add_vertex(v)
			faces.append(v)
		# Glowing edge lines.
		for s: float in [-1.0, 1.0]:
			var oa := across(i) * s * (half - 0.4)
			var ob := across(j) * s * (half - 0.4)
			var wa := across(i) * 0.18
			var wb := across(j) * 0.18
			var up := Vector3(0, 0.02, 0)
			for v: Vector3 in [a + oa - wa + up, b + ob + wb + up, a + oa + wa + up, a + oa - wa + up,
					b + ob - wb + up, b + ob + wb + up]:
				lines.set_normal(Vector3.UP)
				lines.add_vertex(v)
		if a.y < DECK_FROM and b.y < DECK_FROM:
			continue
		# The deck under the road: its sides and underside.
		var d := Vector3(0, -1.6, 0)
		for v: Vector3 in [q[0] + d, q[1] + d, q[2] + d, q[0] + d, q[2] + d, q[3] + d,
				q[0], q[0] + d, q[3] + d, q[0], q[3] + d, q[3], q[1], q[2] + d, q[1] + d, q[1], q[2], q[2] + d]:
			deck.add_vertex(v)
		if a.y < WALL_FROM and b.y < WALL_FROM:
			continue
		# Low walls along both edges, solid, so a slide off the deck is a
		# scrape, not a fall.
		var h := Vector3(0, WALL_H, 0)
		for edge: Array in [[q[0], q[3]], [q[2], q[1]]]:
			var e0: Vector3 = edge[0]
			var e1: Vector3 = edge[1]
			for v: Vector3 in [e0, e1, e1 + h, e0, e1 + h, e0 + h]:
				walls.add_vertex(v)
				faces.append(v)
	var body := StaticBody3D.new()
	body.name = "SkyhookRoad"
	body.collision_layer = Actor.LAYER_WORLD
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	col.shape = shape
	body.add_child(col)
	top.generate_tangents()
	var top_node := MeshInstance3D.new()
	top_node.mesh = top.commit()
	top_node.mesh.surface_set_material(0, road)
	body.add_child(top_node)
	deck.generate_normals()
	var deck_node := MeshInstance3D.new()
	deck_node.mesh = deck.commit()
	deck_node.mesh.surface_set_material(0, deck_mat)
	body.add_child(deck_node)
	var line_node := MeshInstance3D.new()
	line_node.mesh = lines.commit()
	line_node.mesh.surface_set_material(0, map.call("_glow", MAGENTA, 2.5))
	line_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(line_node)
	walls.generate_normals()
	var wall_node := MeshInstance3D.new()
	wall_node.mesh = walls.commit()
	wall_node.mesh.surface_set_material(0, map.call("_glow", CYAN, 1.2, 0.35))
	wall_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(wall_node)
	map.nav_region.add_child(body)
	# The line and the grid boxes behind it.
	var line_i: int = track.gates[0].index
	map.call("_box", Vector3(WIDTH, 0.03, 1.0), pts[line_i] + Vector3(0, 0.08, 0), map.call("_glow", Color.WHITE, 3.0),
			track.heading(line_i), false)
	for slot in track.start_slots:
		map.call("_box", Vector3(2.6, 0.03, 0.25), slot.origin + slot.basis * Vector3(0, 0.08, -1.6),
				map.call("_glow", Color(0.9, 0.9, 1.0), 1.2), slot.basis.get_euler().y, false)


## The pits, south of the start straight: a wall, the bays of stock
## machines facing the track, and the board.
func _build_pits() -> void:
	var dark := map.call("_metal", Color(0.14, 0.14, 0.17), 0.2) as Material
	map.call("_box", Vector3(64, 1.1, 0.8), AT + Vector3(40, 0.55, WIDTH * 0.5 + 4.0), map.call("_metal", Color(0.5, 0.5, 0.55)))
	for k in 8:
		var x := 18.0 + k * 6.5
		var source := "bay_scrapper" if k < 4 else "bay_raider"
		var color: Color = Color(1.0, 0.6, 0.2) if k < 4 else CYAN
		var marker := Marker3D.new()
		marker.add_to_group("spawn_vehicle")
		marker.set_meta("loot_source", source)
		marker.position = AT + Vector3(x, 0.1, 22.0)
		map.add_child(marker)
		map.call("_box", Vector3(4.0, 0.04, 6.0), AT + Vector3(x, 0.03, 22.0), map.call("_glow", color, 0.8, 0.5), 0.0, false)
		var tag := Label3D.new()
		tag.text = "SCRAPPER" if k < 4 else "RAIDER"
		tag.font_size = 64
		tag.pixel_size = 0.008
		tag.modulate = color
		tag.position = AT + Vector3(x, 0.05, 25.4)
		tag.rotation = Vector3(-PI / 2.0, PI, 0)
		map.add_child(tag)
	# The board on two legs past the bays, facing the track.
	var at := AT + Vector3(90, 0, 26)
	for x: float in [-11.0, 11.0]:
		map.call("_box", Vector3(1.2, 16, 1.2), at + Vector3(x, 8, 0), dark)
	map.call("_box", Vector3(26, 13, 0.8), at + Vector3(0, 18, 0), dark)
	var screen := MeshInstance3D.new()
	screen.mesh = QuadMesh.new()
	screen.mesh.size = Vector2(25, 12)
	screen.mesh.material = map.call("_glow", Color(0.02, 0.05, 0.08), 0.6)
	screen.position = at + Vector3(0, 18, -0.45)
	screen.rotation.y = PI
	map.add_child(screen)
	var head := Label3D.new()
	head.text = "%s  ·  STREET  ·  TIME TRIAL" % TRACK_NAME.to_upper()
	head.font_size = 96
	head.pixel_size = 0.012
	head.modulate = MAGENTA
	head.position = at + Vector3(0, 22.6, -0.5)
	head.rotation.y = PI
	map.add_child(head)
	var rows := Label3D.new()
	rows.name = "SkyhookBoard"
	rows.add_to_group("race_board")
	rows.set_meta("track", TRACK_ID)
	rows.text = "No times yet"
	rows.font_size = 72
	rows.pixel_size = 0.012
	rows.line_spacing = 8
	rows.modulate = Color(0.6, 0.9, 1.0)
	rows.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	rows.position = at + Vector3(0, 17.0, -0.5)
	rows.rotation.y = PI
	map.add_child(rows)


# --- Decoration only -------------------------------------------------------------

## Stilts, the Corkscrew's pylon and its arms, the ring dives, and the stand
## by the line under the Flyover. `stands` is the map's spectacle builder.
func dress(stands: RefCounted) -> void:
	var pts := track.points
	var n := pts.size()
	var steel: Material = stands.get("steel")
	var dark: Material = stands.get("dark")
	var lit: Material = stands.call("glow", CYAN, 2.0)
	var pink: Material = stands.call("glow", MAGENTA, 3.0)
	var pylon := AT + CORKSCREW
	for i in range(0, n, 9):
		var p := pts[i]
		if p.y < 3.0:
			continue
		if _over_road(p):
			# Hung from the pylon instead: an arm out to the deck's edge.
			if p.distance_to(Vector3(pylon.x, p.y, pylon.z)) < CORKSCREW_R + WIDTH:
				var to := Vector3(p.x, p.y - 1.0, p.z)
				var from := Vector3(pylon.x, p.y + 2.0, pylon.z)
				var mid := (to + from) * 0.5
				var span := from.distance_to(to)
				stands.call("box", Vector3(0.8, 0.8, span), Transform3D(Basis.looking_at(to - from), mid), dark)
			continue
		var h := p.y - 1.6
		stands.call("box", Vector3(2.2, h, 2.2), Transform3D(Basis(), Vector3(p.x, h * 0.5, p.z)), steel)
		stands.call("box", Vector3(2.3, 0.3, 2.3), Transform3D(Basis(), Vector3(p.x, h * 0.5, p.z)), lit)
	# The pylon, lit up its length.
	stands.call("box", Vector3(5, 34, 5), Transform3D(Basis(), pylon + Vector3(0, 17, 0)), dark)
	for k in 6:
		stands.call("box", Vector3(5.2, 0.4, 5.2), Transform3D(Basis(), pylon + Vector3(0, 4 + k * 5.5, 0)), pink)
	# Rings to dive through at the Flyover and out of the Corkscrew.
	for spot: Vector3 in [Vector3(0, 20, 0), Vector3(-150, 1, 20)]:
		var i := track.locate(AT + spot)
		var f := (pts[(i + 1) % n] - pts[i]).normalized()
		var basis := Basis.looking_at(f) * Basis(Vector3.RIGHT, PI / 2.0)
		for spec: Array in [[10.5, 12.0, steel, 8], [10.3, 10.6, pink, 6]]:
			var ring := MeshInstance3D.new()
			var torus := TorusMesh.new()
			torus.inner_radius = spec[0]
			torus.outer_radius = spec[1]
			torus.rings = 48
			torus.ring_segments = spec[3]
			torus.material = spec[2]
			ring.mesh = torus
			ring.basis = basis
			ring.position = pts[i] + Vector3(0, 2.0, 0)
			stands.get("root").add_child(ring)
	# The stand by the line, across the straight from the pits.
	var xf := Transform3D(Basis(Vector3.UP, PI), AT + Vector3(-38, 0, -WIDTH * 0.5 - 7.5))
	var depth: float = stands.call("stand", xf, 66.0, 14)
	var top := 3.0 + 14 * 0.9 + 6.0
	stands.call("canopy", xf, 66.0, depth, top, 5.0)
	stands.call("label", "SKYHOOK", xf * Transform3D(Basis(Vector3.UP, PI), Vector3(0, top + 5.0, -2.0)), 700, MAGENTA, 0.025)
	stands.call("section_sign", "CORKSCREW", Transform3D(Basis(Vector3.UP, PI * 0.5), pylon + Vector3(-62, 14, 0)), MAGENTA)


## True where another stretch of road runs under `p`.
func _over_road(p: Vector3) -> bool:
	for q in track.points:
		if q.y < p.y - 4.0 and Vector2(q.x - p.x, q.z - p.z).length() < 10.0:
			return true
	return false
