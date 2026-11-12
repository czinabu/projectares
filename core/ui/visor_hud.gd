class_name VisorHud
extends Control
## What a helmet shows its wearer. Two halves:
##
## The glass. Drawn over the view in first person only, and only while a
## helmet is worn: you are looking through the visor, so its readouts are on
## it. Every helmet has the rim and a health arc; the rest depends on the
## visor's `mode` (see `Visor`): a compass, range finder and binocular
## reticle for "zoom", a recharge ring for "scan". With no helmet, or in
## third person, nothing is drawn.
##
## The world. Things a visor puts out there, seen in either view: the frozen
## snapshots of a scan, markers over tagged targets, the ring of a scan pulse
## (anyone's), and the glint off a lens that is looking your way.
##
## A view only: it reads `Visor` state and never decides what is revealed.

## How long the mark for a scan that caught you stays on the glass.
var felt_time := 2.5
## How long a pulse's ring takes to cross its radius.
var ring_time := 0.7
## How squarely a lens must face you to glint, as the cosine of the angle.
var glint_facing := 0.94
## Seconds between range finder readings.
var range_interval := 0.1
var range_max := 600.0

var raid: Raid
var controller: PlayerController
## The range finder's last reading in metres, below zero for nothing in reach.
var range_reading := -1.0
## Scans that caught the wearer: {"origin": Vector3, "left": float}.
var felt: Array[Dictionary] = []

var _world: Node3D
var _ghosts: Array[MeshInstance3D] = []
var _tag_marks := {}
var _glints := {}
var _rings: Array[Dictionary] = []
var _heard := {}
var _range_wait := 0.0
var _time := 0.0


func setup(p_raid: Raid, p_controller: PlayerController) -> void:
	raid = p_raid
	controller = p_controller


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_world = Node3D.new()
	_world.name = "VisorWorld"
	raid.add_child.call_deferred(_world)
	if raid.player != null:
		raid.player.visor.felt_scan.connect(_on_felt_scan)


func _exit_tree() -> void:
	if _world != null and is_instance_valid(_world):
		_world.queue_free()


## True while the wearer is looking through the glass: a helmet on, alive,
## and the camera in their head.
func glass_shown() -> bool:
	var p := _player()
	if p == null or p.is_dead or not p.visor.enabled:
		return false
	return controller == null or not controller.is_third_person()


## Compass bearing in degrees for a yaw: 0 north (-Z), 90 east (+X).
static func bearing(yaw: float) -> float:
	return fposmod(-rad_to_deg(yaw), 360.0)


## Where `origin` lies for someone at `at` facing `yaw`, as an angle from
## straight ahead: positive to the right, PI behind.
static func angle_to(origin: Vector3, at: Vector3, yaw: float) -> float:
	var local := Basis(Vector3.UP, yaw).inverse() * (origin - at)
	return atan2(local.x, -local.z)


## The short name of a compass bearing: N, NE, E and so on.
static func compass_name(degrees: float) -> String:
	var names := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
	return names[posmod(roundi(degrees / 45.0), 8)]


func _player() -> Actor:
	if raid == null or raid.player == null or not is_instance_valid(raid.player):
		return null
	return raid.player


func _process(delta: float) -> void:
	_time += delta
	var p := _player()
	for mark in felt:
		mark.left -= delta
	felt = felt.filter(func(m: Dictionary) -> bool: return m.left > 0.0)
	if p == null or _world == null or not _world.is_inside_tree():
		queue_redraw()
		return
	_read_range(p, delta)
	_sync_ghosts(p)
	_sync_actors(p)
	_tick_rings(delta)
	queue_redraw()


func _on_felt_scan(origin: Vector3) -> void:
	felt.append({"origin": origin, "left": felt_time})
	Sfx.play("ability", null, -9.0)


## The range finder: how far the wearer's eyes see along their aim.
func _read_range(p: Actor, delta: float) -> void:
	_range_wait -= delta
	if _range_wait > 0.0 or p.visor.mode != "zoom" or not p.is_inside_tree():
		return
	_range_wait = range_interval
	var from := p.get_eye_position()
	var query := PhysicsRayQueryParameters3D.create(from, from + p.get_aim_dir() * range_max,
			Actor.LAYER_WORLD | Actor.LAYER_ACTORS)
	query.exclude = [p.get_rid()]
	var hit := p.get_world_3d().direct_space_state.intersect_ray(query)
	range_reading = -1.0 if hit.is_empty() else from.distance_to(hit.position)


# --- The world -----------------------------------------------------------------

## One frozen figure per snapshot of the wearer's last scan, seen through walls.
func _sync_ghosts(p: Actor) -> void:
	var wanted := p.visor.ghosts
	while _ghosts.size() > wanted.size():
		_ghosts.pop_back().queue_free()
	while _ghosts.size() < wanted.size():
		var mesh := CapsuleMesh.new()
		mesh.radius = Actor.BODY_RADIUS
		mesh.height = Actor.BODY_HEIGHT
		mesh.material = _see_through(p.visor.glass_color)
		var node := MeshInstance3D.new()
		node.mesh = mesh
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_world.add_child(node)
		_ghosts.append(node)
	for i in wanted.size():
		var ghost: Dictionary = wanted[i]
		_ghosts[i].global_position = ghost.at + Vector3(0.0, Actor.BODY_HEIGHT * 0.5, 0.0)
		var mat: StandardMaterial3D = _ghosts[i].mesh.material
		mat.albedo_color.a = 0.5 * clampf(ghost.left / maxf(p.visor.ghost_time, 0.01), 0.0, 1.0)


## Everything that follows another actor: pulse rings, tag marks and glints.
func _sync_actors(p: Actor) -> void:
	var camera := get_viewport().get_camera_3d()
	var tagged := {}
	var glinting := {}
	for node in get_tree().get_nodes_in_group("actors"):
		var other := node as Actor
		if other == null or not Raid.together(other, p):
			continue
		if not _heard.has(other):
			_heard[other] = true
			other.visor.pulsed.connect(_on_pulsed.bind(other.visor.scan_radius, other.visor.glass_color))
			other.tree_exiting.connect(func() -> void: _heard.erase(other))
		# Tags held by the wearer's side. Online the server only sends those.
		if other == p or not Combat.authoritative or Visor.allied(p, other):
			for target: Variant in other.visor.tags:
				if is_instance_valid(target):
					tagged[target] = true
		if other != p and not other.is_dead and other.visor.is_zoomed() and camera != null:
			var eye := other.get_eye_position()
			var to_me := camera.global_position - eye
			if to_me.length() > 1.0 and other.get_aim_dir().dot(to_me.normalized()) >= glint_facing:
				glinting[other] = eye + to_me.normalized() * 0.4
	_sync_marks(_tag_marks, tagged, _new_tag_mark)
	_sync_marks(_glints, glinting, _new_glint)
	for target: Actor in _tag_marks:
		_tag_marks[target].global_position = target.global_position + Vector3(0.0, 2.5, 0.0)
	for other: Actor in _glints:
		var glint: MeshInstance3D = _glints[other]
		glint.global_position = glinting[other]
		# Far away a glint would be a single pixel: it grows with distance.
		var away: float = camera.global_position.distance_to(glint.global_position)
		glint.scale = Vector3.ONE * clampf(away * 0.03, 1.0, 9.0) * (0.8 + 0.2 * sin(_time * 23.0))


## Keeps one node in `marks` for every key of `wanted`, built by `make`.
func _sync_marks(marks: Dictionary, wanted: Dictionary, make: Callable) -> void:
	for key: Variant in marks.keys():
		if not wanted.has(key) or not is_instance_valid(key):
			marks[key].queue_free()
			marks.erase(key)
	for key: Variant in wanted:
		if not marks.has(key):
			var node: Node3D = make.call()
			_world.add_child(node)
			marks[key] = node


func _new_tag_mark() -> Node3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.28
	mesh.bottom_radius = 0.0
	mesh.height = 0.45
	mesh.radial_segments = 4
	mesh.material = _see_through(Color(1.0, 0.25, 0.15, 0.9))
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


func _new_glint() -> Node3D:
	var mesh := SphereMesh.new()
	mesh.radius = 0.07
	mesh.height = 0.14
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 1.0, 0.92)
	mesh.material = mat
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


func _on_pulsed(origin: Vector3, radius: float, color: Color) -> void:
	if _world == null or not _world.is_inside_tree():
		return
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(color.r, color.g, color.b, 0.22)
	mesh.material = mat
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_world.add_child(node)
	node.global_position = origin
	_rings.append({"node": node, "age": 0.0, "radius": radius})


func _tick_rings(delta: float) -> void:
	for ring in _rings:
		ring.age += delta
		var done := clampf(ring.age / ring_time, 0.0, 1.0)
		var node: MeshInstance3D = ring.node
		node.scale = Vector3.ONE * maxf(0.5, ring.radius * done)
		var mat: StandardMaterial3D = node.mesh.material
		mat.albedo_color.a = 0.22 * (1.0 - done)
		if done >= 1.0:
			node.queue_free()
	_rings = _rings.filter(func(r: Dictionary) -> bool: return r.age < ring_time)


## A flat colour that shows through walls.
func _see_through(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	mat.albedo_color = color
	return mat


# --- The glass -----------------------------------------------------------------

func _draw() -> void:
	if not glass_shown():
		return
	var p := _player()
	var v := p.visor
	var ink := v.glass_color
	var centre := size * 0.5
	if v.is_zoomed():
		_draw_binoculars(v, ink, centre)
	_draw_rim(ink)
	_draw_health(p, ink, centre)
	match v.mode:
		"":
			_draw_cracks(ink)
		"zoom":
			_draw_compass(p, ink)
			_draw_range(ink, centre)
		"scan":
			_draw_scan_ring(v, ink)
	_draw_felt(p, centre)


## The edge of the glass: dark corners where the helmet's shell cuts in, and
## a thin line just inside it.
func _draw_rim(ink: Color) -> void:
	var w := size.x
	var h := size.y
	var cut := h * 0.16
	var shell := Color(0.02, 0.025, 0.03, 0.88)
	draw_colored_polygon(PackedVector2Array([Vector2(0, 0), Vector2(cut * 1.6, 0), Vector2(0, cut)]), shell)
	draw_colored_polygon(PackedVector2Array([Vector2(w, 0), Vector2(w - cut * 1.6, 0), Vector2(w, cut)]), shell)
	draw_colored_polygon(PackedVector2Array([Vector2(0, h), Vector2(cut * 1.6, h), Vector2(0, h - cut)]), shell)
	draw_colored_polygon(PackedVector2Array([Vector2(w, h), Vector2(w - cut * 1.6, h), Vector2(w, h - cut)]), shell)
	var inset := 10.0
	var edge := PackedVector2Array([
		Vector2(cut * 1.6 + inset, inset), Vector2(w - cut * 1.6 - inset, inset),
		Vector2(w - inset, cut + inset), Vector2(w - inset, h - cut - inset),
		Vector2(w - cut * 1.6 - inset, h - inset), Vector2(cut * 1.6 + inset, h - inset),
		Vector2(inset, h - cut - inset), Vector2(inset, cut + inset), Vector2(cut * 1.6 + inset, inset)])
	draw_polyline(edge, Color(ink.r, ink.g, ink.b, 0.28), 1.5, true)
	# The faintest wash of the glass's colour over everything seen through it.
	draw_rect(Rect2(Vector2.ZERO, size), Color(ink.r, ink.g, ink.b, 0.035))


## A thin arc low on the glass: full is unhurt. It turns red and pulses when
## the wearer is badly hurt.
func _draw_health(p: Actor, ink: Color, centre: Vector2) -> void:
	var share := clampf(p.health.health / maxf(p.health.max_health, 1.0), 0.0, 1.0)
	var radius := size.y * 0.47
	var half := 0.42
	draw_arc(centre, radius, PI * 0.5 - half, PI * 0.5 + half, 48, Color(ink.r, ink.g, ink.b, 0.16), 3.0, true)
	var color := Color(ink.r, ink.g, ink.b, 0.8)
	if share < 0.35:
		color = Color(1.0, 0.2, 0.12, 0.6 + 0.4 * sin(_time * 9.0))
	if share > 0.0:
		draw_arc(centre, radius, PI * 0.5 - half * share, PI * 0.5 + half * share, 48, color, 3.0, true)


## A plain visor has seen better days.
func _draw_cracks(ink: Color) -> void:
	var color := Color(ink.r, ink.g, ink.b, 0.3)
	var from := Vector2(size.x * 0.13, size.y * 0.1)
	var unit := size.y * 0.05
	draw_polyline(PackedVector2Array([from, from + Vector2(1.4, 0.9) * unit, from + Vector2(1.7, 2.2) * unit,
			from + Vector2(3.0, 2.9) * unit]), color, 1.5, true)
	draw_polyline(PackedVector2Array([from + Vector2(1.4, 0.9) * unit, from + Vector2(2.8, 0.7) * unit,
			from + Vector2(3.6, 1.5) * unit]), color, 1.2, true)
	draw_polyline(PackedVector2Array([from + Vector2(1.7, 2.2) * unit, from + Vector2(0.9, 3.3) * unit]),
			color, 1.2, true)


## A strip of bearings across the top that slides as the wearer turns.
func _draw_compass(p: Actor, ink: Color) -> void:
	var font := ThemeDB.fallback_font
	var heading := bearing(p.cmd.yaw)
	var per_degree := size.x * 0.0045
	var y := size.y * 0.075
	var color := Color(ink.r, ink.g, ink.b, 0.85)
	var first := int(floor((heading - 45.0) / 5.0)) * 5
	for mark in range(first, first + 95, 5):
		var x := size.x * 0.5 + (mark - heading) * per_degree
		if absf(mark - heading) > 45.0:
			continue
		var cardinal := posmod(mark, 45) == 0
		draw_line(Vector2(x, y), Vector2(x, y + (12.0 if cardinal else 6.0)), color, 1.5)
		if cardinal:
			draw_string(font, Vector2(x - 30.0, y - 6.0), compass_name(mark), HORIZONTAL_ALIGNMENT_CENTER,
					60.0, 15, color)
	draw_line(Vector2(size.x * 0.5, y + 16.0), Vector2(size.x * 0.5, y + 26.0), color, 2.0)
	draw_string(font, Vector2(size.x * 0.5 - 40.0, y + 44.0), "%03d" % roundi(heading),
			HORIZONTAL_ALIGNMENT_CENTER, 80.0, 14, color)


func _draw_range(ink: Color, centre: Vector2) -> void:
	var text := "--- m" if range_reading < 0.0 else "%d m" % roundi(range_reading)
	draw_string(ThemeDB.fallback_font, centre + Vector2(-60.0, 74.0), text, HORIZONTAL_ALIGNMENT_CENTER,
			120.0, 16, Color(ink.r, ink.g, ink.b, 0.9))


## Looking through the binoculars: everything outside the lens goes dark,
## and the lens carries a reticle with marks for judging drop and lead.
func _draw_binoculars(v: Visor, ink: Color, centre: Vector2) -> void:
	var radius := size.y * 0.45
	var band := size.x
	draw_arc(centre, radius + band * 0.5, 0.0, TAU, 96, Color(0.0, 0.0, 0.0, 0.94), band, true)
	draw_arc(centre, radius, 0.0, TAU, 96, Color(ink.r, ink.g, ink.b, 0.5), 2.0, true)
	var color := Color(ink.r, ink.g, ink.b, 0.75)
	var gap := 14.0
	draw_line(centre + Vector2(-radius, 0), centre + Vector2(-gap, 0), color, 1.0)
	draw_line(centre + Vector2(gap, 0), centre + Vector2(radius, 0), color, 1.0)
	draw_line(centre + Vector2(0, -radius), centre + Vector2(0, -gap), color, 1.0)
	draw_line(centre + Vector2(0, gap), centre + Vector2(0, radius), color, 1.0)
	for step in range(1, 6):
		var out := radius * 0.14 * step
		draw_line(centre + Vector2(out, -5), centre + Vector2(out, 5), color, 1.0)
		draw_line(centre + Vector2(-out, -5), centre + Vector2(-out, 5), color, 1.0)
		draw_line(centre + Vector2(-5, out), centre + Vector2(5, out), color, 1.0)
	draw_string(ThemeDB.fallback_font, centre + Vector2(radius * 0.55, radius * 0.62),
			"%dx" % roundi(v.zoom_factor()), HORIZONTAL_ALIGNMENT_LEFT, 80.0, 18, color)


## The scanner's ring, low on the right: it fills as the scan recharges.
func _draw_scan_ring(v: Visor, ink: Color) -> void:
	var at := Vector2(size.x * 0.8, size.y * 0.78)
	var radius := size.y * 0.045
	var ready := v.cooldown_left <= 0.0
	var share := 1.0 - clampf(v.cooldown_left / maxf(v.cooldown, 0.01), 0.0, 1.0)
	draw_arc(at, radius, 0.0, TAU, 48, Color(ink.r, ink.g, ink.b, 0.18), 4.0, true)
	var alpha := 0.7 + 0.3 * sin(_time * 5.0) if ready else 0.75
	draw_arc(at, radius, -PI * 0.5, -PI * 0.5 + TAU * share, 48, Color(ink.r, ink.g, ink.b, alpha), 4.0, true)
	if ready:
		draw_arc(at, radius * 0.45, 0.0, TAU, 24, Color(ink.r, ink.g, ink.b, 0.5), 1.5, true)
	var text := "SCAN" if ready else "%d" % ceili(v.cooldown_left)
	draw_string(ThemeDB.fallback_font, at + Vector2(-50.0, radius + 22.0), text, HORIZONTAL_ALIGNMENT_CENTER,
			100.0, 14, Color(ink.r, ink.g, ink.b, 0.9))


## A red sliver on the side of the glass a scan came from.
func _draw_felt(p: Actor, centre: Vector2) -> void:
	for mark in felt:
		var angle := angle_to(mark.origin, p.global_position, p.cmd.yaw) - PI * 0.5
		var alpha := clampf(mark.left / felt_time, 0.0, 1.0)
		draw_arc(centre, size.y * 0.4, angle - 0.2, angle + 0.2, 24, Color(1.0, 0.2, 0.12, alpha), 7.0, true)
