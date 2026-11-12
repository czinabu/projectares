extends Node3D
## Greybox Concourse: a round, walled plaza around a beacon spire.
##
##   corners  the market: a storefront for every shop
##   north  the gate row: one deploy gate per raid world
##   west   the quarters: the door to your home base
##   east   the clan hall: closed for now, with room to grow
##   south-east  the arena gate
##   south  the arrival pad where everyone appears, and the show floor
##   centre the spire, ringed by podiums to stand on and be seen
##
## Portals follow the safe-zone contract in WorldDef: Marker3D nodes in group
## "portal" with a "destination" and a "label".

const RADIUS := 52.0
const GATE_RING := 40.0
const PODIUM_RING := 13.0
const PODIUMS := 6
const ARRIVAL := Vector3(0, 0, 30)
const LAYOUT_SEED := 707
## The shops come from the economy's shop list, read at runtime so the plaza
## still builds in a game without one.
const SHOP_DB := "res://core/economy/shop_db.gd"
const MARKET_RING := 43.0
## Where storefronts stand, as angles round the wall: the market quarters
## between the gates and the side doors, then the south-west corner.
const MARKET_SLOTS := [-PI * 0.25 - 0.19, -PI * 0.75 + 0.19, -PI * 0.25 + 0.19, -PI * 0.75 - 0.19,
		PI * 0.75, PI * 0.75 + 0.36, PI * 0.75 - 0.36]
## The casing of a terminal.
const DARK_GLASS := Color(0.12, 0.12, 0.14)
const SHOP_COLORS := [Color(1.0, 0.45, 0.3), Color(0.4, 0.85, 0.55), Color(1.0, 0.8, 0.3), Color(0.45, 0.7, 1.0),
		Color(0.9, 0.5, 0.95)]

var nav_region: NavigationRegion3D
var _art_rng := RandomNumberGenerator.new()
var _gates: Array[Dictionary] = []
var _stalls: Array[Dictionary] = []

@onready var FLOOR := Look.surface("concrete", {"tint": Color(0.5, 0.5, 0.54), "grime": 0.25, "scale": 0.12,
		"wetness": 0.35})
@onready var INLAY := Look.surface("metal", {"tint": Color(0.75, 0.55, 0.3), "grime": 0.3, "scale": 0.3})
@onready var WALL := Look.surface("concrete", {"tint": Color(0.36, 0.38, 0.44), "grime": 0.5, "scale": 0.1,
		"window_glow": Color(1.0, 0.75, 0.45), "lit_windows": 0.5})
@onready var STEEL := Look.surface("metal", {"tint": Color(0.42, 0.45, 0.52), "grime": 0.35, "scale": 0.3})
@onready var DARK := Look.surface("metal", {"tint": Color(0.2, 0.22, 0.27), "grime": 0.4, "scale": 0.3})


func _ready() -> void:
	_art_rng.seed = LAYOUT_SEED
	_build_environment()
	nav_region = NavigationRegion3D.new()
	nav_region.name = "Geometry"
	add_child(nav_region)
	_build_ground()
	_build_spire()
	_build_gates()
	_build_quarters()
	_build_clan_hall()
	_build_arena_gate()
	_build_market()
	_build_arrival()
	_build_show_floor()
	_dress()


func _build_environment() -> void:
	# Permanent dusk: a calm, warm sky after the grey of the warzones.
	Look.atmosphere(self, {
		"sky_tint": Color(1.0, 0.72, 0.55),
		"sky_saturation": 0.9,
		"sky_energy": 0.9,
		"fog_color": Color(0.45, 0.36, 0.42),
		"fog_density": 0.004,
		"sun_color": Color(1.0, 0.78, 0.6),
		"sun_energy": 1.5,
		"sun_angles": Vector3(-18, 35, 0),
		"ambient_color": Color(0.62, 0.6, 0.72),
		"ambient_energy": 1.1,
		"saturation": 1.05,
		"glow": 0.5,
	})
	Look.weather(self, "embers", RADIUS)


func _build_ground() -> void:
	var span := RADIUS * 2.0 + 8.0
	_box(Vector3(span, 1.0, span), Vector3(0, -0.5, 0), FLOOR, 0.0)
	# A wall of tower blocks all the way round. Nobody leaves except by a gate.
	var segments := 28
	for i in segments:
		var angle := TAU * i / segments
		var width := TAU * (RADIUS + 4.0) / segments + 1.0
		var height := 16.0 + float((i * 7) % 5) * 5.0
		var block := _box(Vector3(width, height, 8.0), _polar(RADIUS + 4.0, angle) + Vector3(0, height * 0.5, 0),
				WALL, -angle + PI / 2.0)
		Look.make_building(block.get_child(1), Vector3(width, height, 8.0), float(i))
	# Inlaid rings and walkways that lead the eye to the gates and doors.
	for ring: float in [PODIUM_RING + 4.0, 26.0]:
		for i in 48:
			var angle := TAU * i / 48.0
			_slab(Vector3(TAU * ring / 48.0 + 0.1, 0.04, 0.5), _polar(ring, angle), INLAY, -angle + PI / 2.0)
	for i in 4:
		var angle := TAU * i / 4.0
		_slab(Vector3(22.0, 0.04, 1.2), _polar(29.0, angle), INLAY, -angle)


## The beacon: the landmark you can see from every corner of the plaza.
func _build_spire() -> void:
	_box(Vector3(9, 1.0, 9), Vector3(0, 0.5, 0), STEEL, PI / 4.0)
	_box(Vector3(5, 3.0, 5), Vector3(0, 2.5, 0), DARK, 0.0)
	# What this place is, on every face of the spire's base.
	for i in 4:
		var face := Basis(Vector3.UP, TAU * i / 4.0)
		_sign("SAFE ZONE", face * Vector3(0, 3.0, 2.53), TAU * i / 4.0, 0.55, Color(0.6, 0.95, 0.75))
		_sign("Weapons are locked here", face * Vector3(0, 2.35, 2.53), TAU * i / 4.0, 0.26, Color(0.9, 0.9, 0.9))
	_box(Vector3(2.2, 26.0, 2.2), Vector3(0, 17.0, 0), STEEL, PI / 4.0)
	_box(Vector3(6, 0.5, 6), Vector3(0, 30.25, 0), STEEL, 0.0)
	# Podiums: step up, strike a pose, be inspected.
	for i in PODIUMS:
		var angle := TAU * i / PODIUMS + PI / PODIUMS
		var at := _polar(PODIUM_RING, angle)
		_box(Vector3(3.2, 0.35, 3.2), at + Vector3(0, 0.175, 0), DARK, -angle)
		_box(Vector3(2.4, 0.35, 2.4), at + Vector3(0, 0.525, 0), INLAY, -angle)
		_add_marker("podium", at + Vector3(0, 0.7, 0))


## One gate per raid world, in an arc along the north side.
func _build_gates() -> void:
	var worlds := Worlds.raid_worlds()
	var spread := 0.42
	for i in worlds.size():
		var world := worlds[i]
		var angle := -PI / 2.0 + (float(i) - float(worlds.size() - 1) * 0.5) * spread
		var at := _polar(GATE_RING, angle)
		# Local +Z looks back at the middle of the plaza.
		var yaw := -angle - PI / 2.0
		var facing := Basis(Vector3.UP, yaw)
		_box(Vector3(1.4, 9.0, 2.0), at + facing * Vector3(-4.0, 4.5, 0), STEEL, yaw)
		_box(Vector3(1.4, 9.0, 2.0), at + facing * Vector3(4.0, 4.5, 0), STEEL, yaw)
		_box(Vector3(9.4, 1.6, 2.0), at + Vector3(0, 9.8, 0), DARK, yaw)
		# Solid behind the arch, so the gate is the only way through.
		_box(Vector3(6.6, 9.0, 0.6), at + facing * Vector3(0, 4.5, -1.2), DARK, yaw)
		var portal := _add_portal("world:%s" % world.id, "Deploy to %s" % world.display_name,
				at + facing * Vector3(0, 0, 1.2), 3.2)
		portal.set_meta("world_id", world.id)
		_gates.append({"at": at, "yaw": yaw, "world": world})
		_sign(world.display_name.to_upper(), at + facing * Vector3(0, 9.8, 1.05), yaw, 1.1, Color(1.0, 0.6, 0.3))
		_sign(world.description, at + facing * Vector3(0, 8.6, 1.05), yaw, 0.32, Color(0.9, 0.9, 0.9), 8.5)


## West: the way home. The home base itself is its own space.
func _build_quarters() -> void:
	var at := Vector3(-GATE_RING, 0, 0)
	_box(Vector3(8, 9, 18), at + Vector3(-3, 4.5, 0), WALL, 0.0)
	_box(Vector3(3, 0.4, 7), at + Vector3(2.4, 4.2, 0), DARK, 0.0)
	_box(Vector3(0.5, 4.0, 0.5), at + Vector3(3.6, 2.0, -3.2), STEEL, 0.0)
	_box(Vector3(0.5, 4.0, 0.5), at + Vector3(3.6, 2.0, 3.2), STEEL, 0.0)
	_add_portal("home", "Go to your home base", at + Vector3(2.6, 0, 0), 2.8)
	_sign("QUARTERS", at + Vector3(1.05, 5.6, 0), PI / 2.0, 1.0, Color(0.5, 0.85, 1.0))
	_sign("Your home base", at + Vector3(1.05, 4.75, 0), PI / 2.0, 0.34, Color(0.9, 0.9, 0.9))


## East: the clan hall. A real building with a closed door, ready for clans.
func _build_clan_hall() -> void:
	var at := Vector3(GATE_RING, 0, 0)
	_box(Vector3(10, 13, 24), at + Vector3(4, 6.5, 0), WALL, 0.0)
	_box(Vector3(4, 0.5, 12), at + Vector3(-3.0, 6.0, 0), DARK, 0.0)
	for z: float in [-5.5, 5.5]:
		_box(Vector3(0.8, 6.0, 0.8), at + Vector3(-4.4, 3.0, z), STEEL, 0.0)
	# Banner plinths either side of the door, for clan colours later.
	for z: float in [-9.0, 9.0]:
		_box(Vector3(1.6, 1.2, 1.6), at + Vector3(-3.0, 0.6, z), DARK, 0.0)
		_add_marker("clan_banner", at + Vector3(-3.0, 1.2, z))
	var portal := _add_portal("clans", "Use the clan hall terminal", at + Vector3(-3.2, 0, 0), 2.8)
	# The hall's terminal beside the door, its screen facing the plaza.
	var facing := Basis(Vector3.UP, -PI / 2.0)
	var screen := Node3D.new()
	screen.name = "Screen"
	screen.position = Vector3(2.1, 1.75, 0)
	screen.basis = facing * Basis(Vector3.RIGHT, -0.08)
	portal.add_child(screen)
	_part(screen, Vector3(1.7, 1.0, 0.06), Vector3(0, 0, -0.04), DARK_GLASS)
	_part(screen, Vector3(1.6, 0.9, 0.01), Vector3.ZERO, Color(0.85, 0.6, 1.0).darkened(0.75), true)
	_sign("CLAN HALL", at + Vector3(-1.05, 8.2, 0), -PI / 2.0, 1.0, Color(0.85, 0.6, 1.0))
	_sign("Found a clan, or join one", at + Vector3(-1.05, 7.3, 0), -PI / 2.0, 0.36, Color(0.9, 0.9, 0.9))


## South: a ring of arrival points, so a crowd does not stack on one spot.
func _build_arrival() -> void:
	_slab(Vector3(16, 0.05, 16), ARRIVAL, INLAY, PI / 4.0)
	for i in 12:
		_add_marker("spawn_player", ARRIVAL + _polar(5.0, TAU * i / 12.0) + Vector3(0, 0.2, 0))
	# The way out, on the south wall behind the pad.
	var door := Vector3(0, 0, RADIUS - 6.0)
	_box(Vector3(7, 6, 2), door + Vector3(0, 3, 3.5), DARK, 0.0)
	_add_portal("leave", "Leave the server", door, 2.6)
	_sign("EXIT", door + Vector3(0, 4.6, 2.45), PI, 0.9, Color(1.0, 0.45, 0.4))


## The shops this game has: [{id, name, blurb}, ...], or none.
static func shops() -> Array:
	if not ResourceLoader.exists(SHOP_DB):
		return []
	var listed: Variant = (load(SHOP_DB) as Script).get_script_constant_map().get("SHOPS", [])
	return listed if typeof(listed) == TYPE_ARRAY else []


## A storefront for every shop: an open-fronted stall with a counter, its
## name over the awning, and a pad at the counter to trade from.
func _build_market() -> void:
	var listed := shops()
	for i in mini(listed.size(), MARKET_SLOTS.size()):
		var entry: Dictionary = listed[i]
		var angle: float = MARKET_SLOTS[i]
		var at := _polar(MARKET_RING, angle)
		var yaw := -angle - PI / 2.0
		var facing := Basis(Vector3.UP, yaw)
		var color: Color = SHOP_COLORS[i % SHOP_COLORS.size()]
		# Back wall, side walls and roof, open toward the plaza.
		_box(Vector3(9.0, 5.0, 0.6), at + facing * Vector3(0, 2.5, -2.4), WALL, yaw)
		_box(Vector3(0.6, 5.0, 5.0), at + facing * Vector3(-4.5, 2.5, 0), WALL, yaw)
		_box(Vector3(0.6, 5.0, 5.0), at + facing * Vector3(4.5, 2.5, 0), WALL, yaw)
		_box(Vector3(10.0, 0.5, 7.0), at + facing * Vector3(0, 5.25, 0.8), DARK, yaw)
		_box(Vector3(6.4, 1.1, 0.9), at + facing * Vector3(0, 0.55, 2.0), STEEL, yaw)
		var portal := _add_portal("shop:%s" % entry.get("id", ""), "Trade at the %s" % entry.get("name", "shop"),
				at + facing * Vector3(0, 0, 4.2), 2.4)
		portal.add_to_group("shop_front")
		portal.set_meta("shop_id", entry.get("id", ""))
		# The shop's terminal on the counter, its screen facing the plaza.
		var screen := Node3D.new()
		screen.name = "Screen"
		screen.position = facing * Vector3(0, 1.82, 2.05 - 4.2)
		screen.basis = facing * Basis(Vector3.RIGHT, -0.12)
		portal.add_child(screen)
		_part(screen, Vector3(1.7, 1.0, 0.06), Vector3(0, 0, -0.04), DARK_GLASS)
		_part(screen, Vector3(1.6, 0.9, 0.01), Vector3.ZERO, Color(color, 1.0).darkened(0.75), true)
		_part(screen, Vector3(0.14, 0.4, 0.14), Vector3(0, -0.62, -0.06), DARK_GLASS)
		_sign(str(entry.get("name", "")).to_upper(), at + facing * Vector3(0, 6.2, 4.35), yaw, 0.9, color)
		_sign(entry.get("blurb", ""), at + facing * Vector3(0, 4.3, -2.05), yaw, 0.26, Color(0.9, 0.9, 0.9), 8.0)
		_box(Vector3(10.0, 1.4, 0.3), at + facing * Vector3(0, 6.2, 4.15), DARK, yaw)
		_stalls.append({"at": at, "yaw": yaw, "color": color})


## South-east: the gate to the arena, which is built as its own space.
func _build_arena_gate() -> void:
	var angle := PI / 4.0
	var at := _polar(GATE_RING, angle)
	var yaw := -angle - PI / 2.0
	var facing := Basis(Vector3.UP, yaw)
	_box(Vector3(1.6, 7.0, 2.4), at + facing * Vector3(-3.6, 3.5, 0), DARK, yaw)
	_box(Vector3(1.6, 7.0, 2.4), at + facing * Vector3(3.6, 3.5, 0), DARK, yaw)
	_box(Vector3(8.8, 1.4, 2.4), at + Vector3(0, 7.7, 0), STEEL, yaw)
	_box(Vector3(5.6, 7.0, 0.6), at + facing * Vector3(0, 3.5, -1.4), DARK, yaw)
	_add_portal("arena", "Enter the arena", at + facing * Vector3(0, 0, 1.4), 3.0)
	_sign("ARENA", at + facing * Vector3(0, 7.7, 1.25), yaw, 1.0, Color(1.0, 0.4, 0.35))


## A raised floor with a back wall, lit like a stage, for showing off.
func _build_show_floor() -> void:
	for side: float in [-1.0, 1.0]:
		var at := Vector3(side * 24.0, 0, 24.0)
		_box(Vector3(12, 0.4, 8), at + Vector3(0, 0.2, 0), DARK, side * -0.6)
		_add_marker("stage", at + Vector3(0, 0.45, 0))
	# Benches and low walls to gather round.
	for i in 8:
		var angle := TAU * i / 8.0 + PI / 8.0
		_box(Vector3(4.0, 0.5, 1.0), _polar(21.0, angle) + Vector3(0, 0.25, 0), STEEL, -angle + PI / 2.0)


func _dress() -> void:
	if not Look.enabled:
		return
	var art := Node3D.new()
	art.name = "Dressing"
	add_child(art)
	var beacon := Look.lamp(Color(1.0, 0.7, 0.35), 8.0, 45.0)
	beacon.position = Vector3(0, 31.5, 0)
	art.add_child(beacon)
	var whip := Look.prop("Antenna_1.glb", 6.0, 0.3)
	if whip:
		whip.position = Vector3(0, 30.5, 0)
		art.add_child(whip)
	for i in PODIUMS:
		var angle := TAU * i / PODIUMS + PI / PODIUMS
		var spot := Look.lamp(Color(1.0, 0.9, 0.75), 3.0, 7.0)
		spot.position = _polar(PODIUM_RING, angle) + Vector3(0, 4.0, 0)
		art.add_child(spot)
	for gate in _gates:
		var glow := Look.lamp(Color(1.0, 0.5, 0.2), 5.0, 14.0)
		glow.position = gate["at"] + Vector3(0, 4.0, 0) + Basis(Vector3.UP, gate["yaw"]) * Vector3(0, 0, 1.5)
		art.add_child(glow)
	var wares := ["Lootbox.glb", "Backpack.glb", "PropaneTank.glb", "Computer.glb", "GasCan.glb"]
	for i in _stalls.size():
		var stall := _stalls[i]
		var facing := Basis(Vector3.UP, stall["yaw"])
		var light := Look.lamp(stall["color"], 4.0, 11.0)
		light.position = stall["at"] + facing * Vector3(0, 4.2, 1.0)
		art.add_child(light)
		# Wares either side of the counter's terminal.
		for side: float in [-2.2, 2.2]:
			var ware := Look.prop(wares[(i + int(side)) % wares.size()], 0.8, 0.3)
			if ware:
				ware.position = stall["at"] + facing * Vector3(side, 1.1, 2.0)
				ware.rotation.y = _art_rng.randf() * TAU
				art.add_child(ware)
	var home := Look.lamp(Color(0.45, 0.8, 1.0), 4.0, 12.0)
	home.position = Vector3(-GATE_RING + 2.5, 3.4, 0)
	art.add_child(home)
	var clan := Look.lamp(Color(0.8, 0.5, 1.0), 4.0, 14.0)
	clan.position = Vector3(GATE_RING - 3.0, 5.0, 0)
	art.add_child(clan)
	# Street lamps round the middle ring, and a little life by the benches.
	for i in 12:
		var angle := TAU * i / 12.0
		var post := Look.prop("Streetlight_Single.glb", 6.0, 0.4)
		if post:
			post.position = _polar(26.0, angle)
			post.rotation.y = -angle
			art.add_child(post)
		var light := Look.lamp(Color(1.0, 0.82, 0.6), 2.5, 13.0)
		light.position = _polar(26.0, angle) + Vector3(0, 5.5, 0)
		art.add_child(light)
	for i in 8:
		var angle := TAU * i / 8.0 + PI / 8.0
		var file: String = ["Bonfire.glb", "Lootbox.glb", "Computer_Large.glb", "Backpack.glb"][i % 4]
		var junk := Look.prop(file, 1.1, 0.4)
		if junk:
			junk.position = _polar(22.6, angle + 0.12)
			junk.rotation.y = _art_rng.randf() * TAU
			art.add_child(junk)
		if file == "Bonfire.glb":
			var fire := Look.lamp(Color(1.0, 0.5, 0.2), 3.0, 8.0)
			fire.position = _polar(22.6, angle + 0.12) + Vector3(0, 0.8, 0)
			art.add_child(fire)


func _polar(radius: float, angle: float) -> Vector3:
	return Vector3(cos(angle) * radius, 0, sin(angle) * radius)


func _add_marker(group: String, at: Vector3) -> Marker3D:
	var marker := Marker3D.new()
	marker.add_to_group(group)
	marker.position = at
	add_child(marker)
	return marker


func _add_portal(destination: String, label: String, at: Vector3, radius: float) -> Marker3D:
	var portal := _add_marker("portal", at)
	portal.set_meta("destination", destination)
	portal.set_meta("label", label)
	portal.set_meta("radius", radius)
	# A glowing pad marks where to stand.
	var pad := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 0.06
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.6, 0.25, 0.35)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.55, 0.2)
	mat.emission_energy_multiplier = 1.5
	mesh.material = mat
	pad.mesh = mesh
	pad.position = Vector3(0, 0.04, 0)
	portal.add_child(pad)
	return portal


## Lettering on a wall. `width` wraps long text.
func _sign(text: String, at: Vector3, yaw: float, size: float, color: Color, width := 0.0) -> void:
	var label := Label3D.new()
	label.text = text
	label.pixel_size = 0.01
	label.font_size = int(size * 100.0)
	label.outline_size = int(size * 12.0)
	label.modulate = color
	label.position = at
	label.rotation.y = yaw
	if width > 0.0:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.width = width * 100.0
	add_child(label)


## A plain box with no collision under `parent` (a terminal's casing).
func _part(parent: Node3D, size: Vector3, at: Vector3, color: Color, glow := false) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	if glow:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 1.2
	mesh.material = mat
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = at
	parent.add_child(node)


## A thin decorative plate set into the floor. No collision.
func _slab(size: Vector3, at: Vector3, material: Material, yaw: float) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = at + Vector3(0, size.y * 0.5, 0)
	node.rotation.y = yaw
	add_child(node)


func _box(size: Vector3, at: Vector3, material: Material, yaw: float) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = Actor.LAYER_WORLD
	body.collision_mask = 0
	body.position = at
	body.rotation.y = yaw
	var shape := BoxShape3D.new()
	shape.size = size
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var mesh_node := MeshInstance3D.new()
	mesh_node.mesh = mesh
	body.add_child(mesh_node)
	nav_region.add_child(body)
	return body
