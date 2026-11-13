extends Node3D
## Greybox Concourse: an open district on a high deck around a beacon spire,
## with no wall. The edge is a balcony over the city far below.
##
##   centre  the beacon spire, ringed by podiums to stand on and be seen
##   ring    the market promenade: a covered arcade with a kiosk per shop
##   towers  slim towers round the promenade, with landing decks and
##           skybridges at DECK_HEIGHT (in reach of the thruster boots)
##   north   the gate terrace: one arch per raid world, spares sealed
##   west    the quarters: the door to your home base
##   east    the clan hall
##   south-east  the arena gate
##   south   the arrival pad, the way out, and the screens amphitheatre
##   south-west  a pad kept clear for the RC arena (later)
##   edge    a ground loop for bikes, then the balcony rail
##
## Angles in this file are compass bearings in degrees: 0 is north (-Z) and
## they turn clockwise, so 90 is east (+X). See `_at`.
##
## Portals follow the safe-zone contract in WorldDef: Marker3D nodes in group
## "portal" with a "destination" and a "label".

## The balcony rail, where the deck ends.
const RADIUS := 140.0
const PLAZA_RING := 30.0
const PODIUM_RING := 13.0
const PODIUMS := 6
const ARRIVAL := Vector3(0, 0, 40)
const LAYOUT_SEED := 707
## The shops come from the economy's shop list, read at runtime so the plaza
## still builds in a game without one.
const SHOP_DB := "res://core/economy/shop_db.gd"
## The arcade's middle line, its width and its roof height.
const MARKET_RING := 55.0
const ARCADE_WIDTH := 10.0
const ARCADE_HEIGHT := 8.0
## Bearings of the kiosks round the promenade, in the shop list's order.
const MARKET_SLOTS := [325.0, 35.0, 110.0, 215.0, 145.0, 250.0, 70.0]
## The boulevards: bearings and widths, from the plaza out to the bike loop.
const SPOKES := [0.0, 45.0, 90.0, 135.0, 180.0, 225.0, 270.0, 315.0]
const TOWER_RING := 78.0
const TOWER_HEIGHTS := [85.0, 45.0, 60.0, 40.0, 70.0, 50.0, 90.0, 55.0]
const TOWER_SIZE := 10.0
## Tops of the tower decks and skybridges. Three boot kicks reach 15 m.
const DECK_HEIGHT := 15.0
## The gate terrace: how far north, and how many arches (worlds fill the
## first ones, the rest stand sealed for worlds to come).
const GATE_LINE := 100.0
const GATE_ARCHES := 4
const GATE_SPACING := 18.0
const SIDE_DISTRICT := 95.0
const ARENA_BEARING := 135.0
const RC_BEARING := 225.0
const SCREENS_AT := Vector3(0, 0, 96)
const BIKE_RING := 120.0
const BIKE_WIDTH := 10.0
## The casing of a terminal.
const DARK_GLASS := Color(0.12, 0.12, 0.14)
const SHOP_COLORS := [Color(1.0, 0.45, 0.3), Color(0.4, 0.85, 0.55), Color(1.0, 0.8, 0.3), Color(0.45, 0.7, 1.0),
		Color(0.9, 0.5, 0.95)]
const CYAN := Color(0.25, 0.9, 1.0)
const MAGENTA := Color(1.0, 0.3, 0.85)

var nav_region: NavigationRegion3D
var _art_rng := RandomNumberGenerator.new()
var _gates: Array[Dictionary] = []
var _stalls: Array[Dictionary] = []
var _glow_mats := {}
## Lit seams waiting to be drawn: colour -> [[size, transform], ...], drawn as
## one mesh per colour by `_flush_seams`.
var _seams := {}
var _glass_mat: StandardMaterial3D
## Plain parts of the map waiting to be drawn: [colour, glow] -> [[size, transform], ...].
var _parts := {}
var _flushed := false

@onready var FLOOR := Look.surface("metal", {"tint": Color(0.36, 0.39, 0.46), "grime": 0.0, "scale": 0.05,
		"wetness": 0.25})
@onready var PAVING := Look.surface("metal", {"tint": Color(0.3, 0.33, 0.4), "grime": 0.1, "scale": 0.2})
@onready var INLAY := Look.surface("metal", {"tint": Color(0.75, 0.55, 0.3), "grime": 0.3, "scale": 0.3})
## Dark glass and metal panels: the hub's buildings. Lit seams, never a grid of
## windows (that read as old flats, not sci-fi).
@onready var WALL := Look.surface("metal", {"tint": Color(0.17, 0.21, 0.31), "grime": 0.0, "scale": 0.08,
		"rough_mult": 0.25, "wetness": 0.8})
@onready var STEEL := Look.surface("metal", {"tint": Color(0.42, 0.45, 0.52), "grime": 0.2, "scale": 0.3})
@onready var DARK := Look.surface("metal", {"tint": Color(0.16, 0.18, 0.23), "grime": 0.2, "scale": 0.3})


func _ready() -> void:
	_art_rng.seed = LAYOUT_SEED
	_build_environment()
	nav_region = NavigationRegion3D.new()
	nav_region.name = "Geometry"
	add_child(nav_region)
	_build_ground()
	_build_spire()
	_build_arcade()
	_build_towers()
	_build_gates()
	_build_quarters()
	_build_clan_hall()
	_build_arena_gate()
	_build_rc_pad()
	_build_market()
	_build_arrival()
	_build_screens()
	_build_show_floor()
	_build_fill()
	_build_city_below()
	_flush_seams()
	_dress()


func _build_environment() -> void:
	# Permanent dusk: a calm, warm sky after the grey of the warzones.
	Look.atmosphere(self, {
		"sky_tint": Color(1.0, 0.72, 0.55),
		"sky_saturation": 0.9,
		"sky_energy": 0.9,
		"fog_color": Color(0.45, 0.36, 0.42),
		"fog_density": 0.003,
		"sun_color": Color(1.0, 0.78, 0.6),
		"sun_energy": 1.5,
		"sun_angles": Vector3(-18, 35, 0),
		"ambient_color": Color(0.62, 0.6, 0.72),
		"ambient_energy": 1.1,
		"saturation": 1.05,
		"glow": 0.5,
	})
	Look.weather(self, "embers", RADIUS * 0.5)



## The deck: a round floor out to the balcony rail, paved where people walk,
## with glowing boulevards from the spire out to every district.
func _build_ground() -> void:
	_disc(RADIUS + 2.0, 1.0, Vector3(0, -0.5, 0), FLOOR)
	_build_tiles()
	# The rail: waist high, so the view stays open. Hop it and you fall to the
	# city, and the safe zone puts you back on the arrival pad.
	var segments := 72
	var rail: Array[Transform3D] = []
	for i in segments:
		var bearing := 360.0 * i / segments
		rail.append(Transform3D(Basis(Vector3.UP, -deg_to_rad(bearing)), _at(RADIUS, bearing) + Vector3(0, 0.55, 0)))
	_batch(Vector3(TAU * RADIUS / segments + 0.2, 1.1, 0.4), rail, STEEL, true)
	_slab_ring(RADIUS - 1.0, 0.5, 72, CYAN, 0.06)
	# The plaza round the spire, paved, with an inlaid ring at its edge.
	_slab_disc(PLAZA_RING, PAVING)
	_slab_ring(PLAZA_RING, 0.6, 64, CYAN)
	_slab_ring(PODIUM_RING + 4.0, 0.4, 48, Color.BLACK, 0.05, INLAY)
	# Boulevards: a paved strip with a light line down the middle.
	for bearing: float in SPOKES:
		var main := int(bearing) % 90 == 0
		var width := 12.0 if main else 7.0
		var length := BIKE_RING - PLAZA_RING
		var mid := _at(PLAZA_RING + length * 0.5, bearing)
		_slab(Vector3(width, 0.03, length), mid, PAVING, -deg_to_rad(bearing))
		_slab(Vector3(0.35, 0.05, length), mid, _glow(CYAN), -deg_to_rad(bearing))
		for side: float in [-1.0, 1.0]:
			var edge := mid + Basis(Vector3.UP, -deg_to_rad(bearing)) * Vector3(side * width * 0.5, 0, 0)
			_slab(Vector3(0.15, 0.05, length), edge, _glow(CYAN.darkened(0.4)), -deg_to_rad(bearing))
	# The bike loop round the outside: a dark track between two light lines.
	_slab_ring(BIKE_RING, BIKE_WIDTH, 96, Color.BLACK, 0.02, DARK)
	for edge: float in [BIKE_RING - BIKE_WIDTH * 0.5, BIKE_RING + BIKE_WIDTH * 0.5]:
		_slab_ring(edge, 0.25, 96, Color(1.0, 0.65, 0.25), 0.04)


## The beacon: a tall lit spire you can find from anywhere on the deck.
func _build_spire() -> void:
	_box(Vector3(10, 1.0, 10), Vector3(0, 0.5, 0), STEEL, PI / 4.0)
	_box(Vector3(5, 3.0, 5), Vector3(0, 2.5, 0), DARK, 0.0)
	# What this place is, on every face of the spire's base.
	for i in 4:
		var face := Basis(Vector3.UP, TAU * i / 4.0)
		_sign("SAFE ZONE", face * Vector3(0, 3.0, 2.53), TAU * i / 4.0, 0.55, Color(0.6, 0.95, 0.75))
		_sign("Weapons are locked here", face * Vector3(0, 2.35, 2.53), TAU * i / 4.0, 0.26, Color(0.9, 0.9, 0.9))
	# The shaft tapers as it climbs, a light seam up each corner.
	var levels := [[3.0, 4.0, 22.0], [2.2, 26.0, 18.0], [1.4, 44.0, 14.0]]
	for level: Array in levels:
		var w: float = level[0]
		var base: float = level[1]
		var tall: float = level[2]
		_box(Vector3(w, tall, w), Vector3(0, base + tall * 0.5, 0), DARK, PI / 4.0)
		for i in 4:
			var corner := Basis(Vector3.UP, PI / 4.0 + TAU * i / 4.0) * Vector3(w * 0.5, 0, w * 0.5)
			_part(self, Vector3(0.18, tall, 0.18), corner + Vector3(0, base + tall * 0.5, 0), CYAN, true)
	_part(self, Vector3(1.2, 2.0, 1.2), Vector3(0, 59.0, 0), Color(0.75, 1.0, 1.0), true)
	# Podiums: step up, strike a pose, be inspected.
	for i in PODIUMS:
		var bearing := 360.0 * i / PODIUMS + 180.0 / PODIUMS
		var at := _at(PODIUM_RING, bearing)
		_box(Vector3(3.2, 0.35, 3.2), at + Vector3(0, 0.175, 0), DARK, -deg_to_rad(bearing))
		_box(Vector3(2.4, 0.35, 2.4), at + Vector3(0, 0.525, 0), INLAY, -deg_to_rad(bearing))
		_add_marker("podium", at + Vector3(0, 0.7, 0))


## The promenade: a ring of roof on slim pillars over the kiosks, high enough
## for bikes and fliers to pass under and low enough to land on.
func _build_arcade() -> void:
	var segments := 48
	var inner := MARKET_RING - ARCADE_WIDTH * 0.5
	var outer := MARKET_RING + ARCADE_WIDTH * 0.5
	var roof: Array[Transform3D] = []
	for i in segments:
		var bearing := 360.0 * (i + 0.5) / segments
		roof.append(Transform3D(Basis(Vector3.UP, -deg_to_rad(bearing)),
				_at(MARKET_RING, bearing) + Vector3(0, ARCADE_HEIGHT - 0.1, 0)))
	# A thin glass canopy on steel ribs: the sky and the spire show through.
	_batch(Vector3(TAU * outer / segments + 0.3, 0.2, ARCADE_WIDTH), roof, _glass(), true)
	var ribs: Array[Transform3D] = []
	for place in roof:
		ribs.append(place.translated_local(Vector3(TAU * outer / segments * 0.5, 0, 0)))
	_batch(Vector3(0.25, 0.35, ARCADE_WIDTH), ribs, STEEL, false)
	_slab_ring(inner, 0.15, segments, MAGENTA, ARCADE_HEIGHT - 0.25)
	_slab_ring(outer, 0.15, segments, MAGENTA, ARCADE_HEIGHT - 0.25)
	# Pillars along both edges, kept out of the boulevards.
	var pillars: Array[Transform3D] = []
	for i in 24:
		var bearing := 360.0 * (i + 0.5) / 24.0
		if _near_spoke(bearing, MARKET_RING, 8.0) or _near_kiosk(bearing):
			continue
		for r: float in [inner + 0.4, outer - 0.4]:
			pillars.append(Transform3D(Basis(Vector3.UP, -deg_to_rad(bearing)),
					_at(r, bearing) + Vector3(0, (ARCADE_HEIGHT - 0.2) * 0.5, 0)))
	_batch(Vector3(0.3, ARCADE_HEIGHT - 0.2, 0.3), pillars, STEEL, true)


## Slim towers round the promenade. Each has a landing deck at DECK_HEIGHT and
## a skybridge to the next, so boots can hop the skyline; the tops are for
## wings and jetpacks.
func _build_towers() -> void:
	var count := TOWER_HEIGHTS.size()
	for i in count:
		var bearing := 360.0 * (i + 0.5) / count
		var tall: float = TOWER_HEIGHTS[i]
		var at := _at(TOWER_RING, bearing)
		var yaw := -deg_to_rad(bearing)
		# Three tiers stepping in as they climb, each with lit seams, and a
		# crown light on top.
		var tiers := [[TOWER_SIZE, 0.0, tall * 0.55], [TOWER_SIZE * 0.75, tall * 0.55, tall * 0.85],
				[TOWER_SIZE * 0.5, tall * 0.85, tall]]
		var color: Color = [CYAN, MAGENTA][i % 2]
		for tier: Array in tiers:
			var w: float = tier[0]
			var size := Vector3(w, tier[2] - tier[1], w)
			var centre := at + Vector3(0, (tier[1] + tier[2]) * 0.5, 0)
			_box(size, centre, WALL, yaw)
			_add_seams(centre, size, yaw, color, 6.0)
			# A bright band where each tier steps in.
			_part(self, Vector3(w + 0.12, 0.6, w + 0.12), centre + Vector3(0, size.y * 0.5 - 0.3, 0), color, true, yaw)
		_part(self, Vector3(TOWER_SIZE * 0.5 + 0.3, 0.3, TOWER_SIZE * 0.5 + 0.3), at + Vector3(0, tall, 0), color, true)
		_part(self, Vector3(0.25, tall * 0.12, 0.25), at + Vector3(0, tall * 1.06, 0), color, true)
		_box(Vector3(TOWER_SIZE + 8.0, 0.5, TOWER_SIZE + 8.0), at + Vector3(0, DECK_HEIGHT - 0.25, 0), DARK, yaw)
		_add_marker("landing_deck", at + Vector3(0, DECK_HEIGHT + 0.1, 0) + Basis(Vector3.UP, yaw)
				* Vector3(0, 0, TOWER_SIZE * 0.5 + 2.0))
		# The skybridge to the next tower, deck to deck.
		var next := _at(TOWER_RING, 360.0 * (i + 1.5) / count)
		var span := next - at
		var length := span.length() - TOWER_SIZE - 8.0
		var mid := at + span * 0.5 + Vector3(0, DECK_HEIGHT - 0.25, 0)
		var bridge_yaw := atan2(span.x, span.z)
		_box(Vector3(4.0, 0.5, length), mid, DARK, bridge_yaw)
		# Glass sides with a light along the handrail and the floor edge.
		for side: float in [-1.0, 1.0]:
			var rail := mid + Basis(Vector3.UP, bridge_yaw) * Vector3(side * 1.95, 0.8, 0)
			_box(Vector3(0.08, 1.1, length), rail, _glass(), bridge_yaw)
			_part(self, Vector3(0.14, 0.08, length), rail + Vector3(0, 0.58, 0), CYAN, true, bridge_yaw)
			_part(self, Vector3(0.1, 0.05, length), rail + Vector3(-side * 0.1, -0.52, 0), CYAN.darkened(0.3), true,
					bridge_yaw)


## One arch per raid world along the gate terrace, north of the spire, with
## the spare arches sealed for worlds to come.
func _build_gates() -> void:
	var worlds := Worlds.raid_worlds()
	var arches := maxi(GATE_ARCHES, worlds.size())
	# The terrace: a wide paved apron with a back wall the arches stand in.
	var wall_width := arches * GATE_SPACING + 16.0
	_slab(Vector3(wall_width, 0.04, 26.0), Vector3(0, 0, -GATE_LINE + 6.0), PAVING, 0.0)
	_slab(Vector3(wall_width, 0.06, 0.4), Vector3(0, 0, -GATE_LINE + 19.0), _glow(Color(1.0, 0.55, 0.25)), 0.0)
	_box(Vector3(wall_width, 14.0, 4.0), Vector3(0, 7.0, -GATE_LINE - 3.4), WALL, 0.0)
	_add_seams(Vector3(0, 7.0, -GATE_LINE - 3.4), Vector3(wall_width, 14.0, 4.0), 0.0, Color(1.0, 0.55, 0.25), 14.0)
	# A lit cornice and a header over the whole terrace.
	_box(Vector3(wall_width + 2.0, 1.2, 6.0), Vector3(0, 14.6, -GATE_LINE - 2.4), DARK, 0.0)
	_part(self, Vector3(wall_width + 2.0, 0.2, 0.1), Vector3(0, 14.4, -GATE_LINE + 0.62), Color(1.0, 0.55, 0.25), true)
	_sign("DEPLOY", Vector3(0, 17.2, -GATE_LINE - 2.0), 0.0, 3.0, Color(1.0, 0.65, 0.35))
	# Fins between the arches, lit down their edges.
	for i in arches + 1:
		var x := (float(i) - float(arches) * 0.5) * GATE_SPACING
		_box(Vector3(1.2, 14.0, 3.0), Vector3(x, 7.0, -GATE_LINE - 0.4), WALL, 0.0)
		_part(self, Vector3(0.12, 13.6, 0.1), Vector3(x, 7.0, -GATE_LINE + 1.15), Color(1.0, 0.55, 0.25), true)
	for i in arches:
		var at := Vector3((float(i) - float(arches - 1) * 0.5) * GATE_SPACING, 0, -GATE_LINE)
		var open := i < worlds.size()
		var color := Color(1.0, 0.6, 0.3) if open else Color(0.4, 0.42, 0.5)
		# Local +Z looks back at the middle of the plaza.
		var yaw := 0.0
		_box(Vector3(1.6, 12.0, 2.4), at + Vector3(-5.0, 6.0, 0), STEEL, yaw)
		_box(Vector3(1.6, 12.0, 2.4), at + Vector3(5.0, 6.0, 0), STEEL, yaw)
		_box(Vector3(11.6, 1.6, 2.4), at + Vector3(0, 12.8, 0), DARK, yaw)
		_part(self, Vector3(8.4, 0.12, 0.12), at + Vector3(0, 11.95, 1.25), color, true)
		for side: float in [-1.0, 1.0]:
			_part(self, Vector3(0.12, 11.9, 0.12), at + Vector3(side * 4.15, 5.95, 1.25), color, true)
		if not open:
			_box(Vector3(8.4, 12.0, 0.6), at + Vector3(0, 6.0, 0), DARK, yaw)
			_sign("SEALED", at + Vector3(0, 6.0, 0.35), yaw, 0.7, color)
			continue
		var world := worlds[i]
		var portal := _add_portal("world:%s" % world.id, "Deploy to %s" % world.display_name,
				at + Vector3(0, 0, 1.6), 3.2)
		portal.set_meta("world_id", world.id)
		_gates.append({"at": at, "yaw": yaw, "world": world})
		_sign(world.display_name.to_upper(), at + Vector3(0, 12.8, 1.25), yaw, 1.1, color)
		_sign(world.description, at + Vector3(0, 10.6, 0.1), yaw, 0.32, Color(0.9, 0.9, 0.9), 8.0)


## West: the way home. The home base itself is its own space. Its roof is in
## reach of the boots.
func _build_quarters() -> void:
	var at := Vector3(-SIDE_DISTRICT, 0, 0)
	_box(Vector3(14, 12, 28), at + Vector3(-6, 6, 0), WALL, 0.0)
	_add_seams(at + Vector3(-6, 6, 0), Vector3(14, 12, 28), 0.0, Color(0.5, 0.85, 1.0), 4.0)
	_box(Vector3(4, 0.4, 9), at + Vector3(2.5, 5.2, 0), DARK, 0.0)
	_box(Vector3(0.5, 5.0, 0.5), at + Vector3(4.2, 2.5, -4.2), STEEL, 0.0)
	_box(Vector3(0.5, 5.0, 0.5), at + Vector3(4.2, 2.5, 4.2), STEEL, 0.0)
	_add_portal("home", "Go to your home base", at + Vector3(2.6, 0, 0), 2.8)
	_sign("QUARTERS", at + Vector3(1.05, 7.4, 0), PI / 2.0, 1.2, Color(0.5, 0.85, 1.0))
	_sign("Your home base", at + Vector3(1.05, 6.3, 0), PI / 2.0, 0.4, Color(0.9, 0.9, 0.9))


## East: the clan hall, with banner plinths for clan colours.
func _build_clan_hall() -> void:
	var at := Vector3(SIDE_DISTRICT, 0, 0)
	_box(Vector3(14, 12, 30), at + Vector3(6, 6, 0), WALL, 0.0)
	_add_seams(at + Vector3(6, 6, 0), Vector3(14, 12, 30), 0.0, Color(0.85, 0.6, 1.0), 4.0)
	_box(Vector3(5, 0.5, 14), at + Vector3(-1.5, 6.0, 0), DARK, 0.0)
	for z: float in [-6.5, 6.5]:
		_box(Vector3(0.8, 6.0, 0.8), at + Vector3(-3.4, 3.0, z), STEEL, 0.0)
	# Banner plinths either side of the door, for clan colours later.
	for z: float in [-10.0, 10.0]:
		_box(Vector3(1.6, 1.2, 1.6), at + Vector3(-2.0, 0.6, z), DARK, 0.0)
		_add_marker("clan_banner", at + Vector3(-2.0, 1.2, z))
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
	_sign("CLAN HALL", at + Vector3(-1.05, 8.2, 0), -PI / 2.0, 1.2, Color(0.85, 0.6, 1.0))
	_sign("Found a clan, or join one", at + Vector3(-1.05, 7.1, 0), -PI / 2.0, 0.4, Color(0.9, 0.9, 0.9))


## South-east: the gate to the arena, which is built as its own space.
func _build_arena_gate() -> void:
	var at := _at(98.0, ARENA_BEARING)
	var yaw := -deg_to_rad(ARENA_BEARING)
	var facing := Basis(Vector3.UP, yaw)
	_box(Vector3(22, 10, 14), at + facing * Vector3(0, 5.0, -8.6), WALL, yaw)
	_add_seams(at + facing * Vector3(0, 5.0, -8.6), Vector3(22, 10, 14), yaw, Color(1.0, 0.3, 0.35), 5.0)
	_box(Vector3(1.6, 8.0, 2.4), at + facing * Vector3(-4.0, 4.0, 0), DARK, yaw)
	_box(Vector3(1.6, 8.0, 2.4), at + facing * Vector3(4.0, 4.0, 0), DARK, yaw)
	_box(Vector3(9.6, 1.4, 2.4), at + facing * Vector3(0, 8.7, 0), STEEL, yaw)
	_part(self, Vector3(6.4, 0.12, 0.12), at + facing * Vector3(0, 7.9, 1.25), Color(1.0, 0.3, 0.35), true)
	_add_portal("arena", "Enter the arena", at + facing * Vector3(0, 0, 1.4), 3.0)
	_sign("ARENA", at + facing * Vector3(0, 8.7, 1.25), yaw, 1.0, Color(1.0, 0.4, 0.35))


## South-west: a walled pad kept clear for the toy RC arena (a later game).
func _build_rc_pad() -> void:
	var at := _at(98.0, RC_BEARING)
	var yaw := -deg_to_rad(RC_BEARING)
	var facing := Basis(Vector3.UP, yaw)
	_slab(Vector3(30, 0.05, 30), at, DARK, yaw)
	for i in 4:
		var side := Basis(Vector3.UP, yaw + TAU * i / 4.0)
		# Low walls, open in the middle of the side facing the plaza.
		if i == 0:
			for half: float in [-1.0, 1.0]:
				_box(Vector3(11.0, 0.8, 0.4), at + side * Vector3(half * 9.5, 0.4, 15.0), STEEL, yaw)
		else:
			_box(Vector3(30.0, 0.8, 0.4), at + side * Vector3(0, 0.4, 15.0), STEEL, yaw + TAU * i / 4.0)
	_slab_square(at, 29.0, yaw, Color(1.0, 0.8, 0.25))
	_add_marker("rc_arena", at)
	_sign("RC ARENA", at + facing * Vector3(0, 3.2, 15.2), yaw, 1.0, Color(1.0, 0.8, 0.3))
	_sign("Coming soon", at + facing * Vector3(0, 2.3, 15.2), yaw, 0.4, Color(0.9, 0.9, 0.9))


## The shops this game has: [{id, name, blurb}, ...], or none.
static func shops() -> Array:
	if not ResourceLoader.exists(SHOP_DB):
		return []
	var listed: Variant = (load(SHOP_DB) as Script).get_script_constant_map().get("SHOPS", [])
	return listed if typeof(listed) == TYPE_ARRAY else []


## A kiosk for every shop under the arcade roof: an open-fronted booth with a
## counter, its name over the front, and a pad at the counter to trade from.
func _build_market() -> void:
	var listed := shops()
	for i in mini(listed.size(), MARKET_SLOTS.size()):
		var entry: Dictionary = listed[i]
		var bearing: float = MARKET_SLOTS[i]
		var at := _at(MARKET_RING + 1.5, bearing)
		var yaw := -deg_to_rad(bearing)
		var facing := Basis(Vector3.UP, yaw)
		var color: Color = SHOP_COLORS[i % SHOP_COLORS.size()]
		# Back wall, side walls and roof, open toward the plaza.
		_box(Vector3(9.0, 5.0, 0.6), at + facing * Vector3(0, 2.5, -2.4), WALL, yaw)
		_box(Vector3(0.12, 5.0, 5.0), at + facing * Vector3(-4.5, 2.5, 0), _glass(), yaw)
		_box(Vector3(0.12, 5.0, 5.0), at + facing * Vector3(4.5, 2.5, 0), _glass(), yaw)
		# A backlit wall behind the counter and a lit counter top.
		_part(self, Vector3(8.0, 3.2, 0.05), at + facing * Vector3(0, 2.6, -2.07), Color(color, 1.0).darkened(0.6), true, yaw)
		_part(self, Vector3(6.5, 0.06, 0.95), at + facing * Vector3(0, 1.13, 2.0), Color(color, 1.0).lightened(0.2), true, yaw)
		_box(Vector3(10.0, 0.5, 6.0), at + facing * Vector3(0, 5.25, 0.3), DARK, yaw)
		_box(Vector3(6.4, 1.1, 0.9), at + facing * Vector3(0, 0.55, 2.0), STEEL, yaw)
		_part(self, Vector3(6.4, 0.08, 0.08), at + facing * Vector3(0, 1.14, 2.46), color, true)
		for side: float in [-1.0, 1.0]:
			_part(self, Vector3(0.1, 5.0, 0.1), at + facing * Vector3(side * 4.78, 2.5, 2.52), color, true, yaw)
		_part(self, Vector3(10.0, 0.1, 0.1), at + facing * Vector3(0, 5.5, 3.32), color, true, yaw)
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
		_sign(str(entry.get("name", "")).to_upper(), at + facing * Vector3(0, 6.2, 3.45), yaw, 0.9, color)
		_sign(entry.get("blurb", ""), at + facing * Vector3(0, 4.3, -2.05), yaw, 0.26, Color(0.9, 0.9, 0.9), 8.0)
		_box(Vector3(10.0, 1.4, 0.3), at + facing * Vector3(0, 6.2, 3.25), DARK, yaw)
		# A tall holo sign over the arcade, so each shop can be found from the
		# spire: a slim mast through the canopy and a lit blade with its name.
		var mast := at + facing * Vector3(0, 0, -2.0)
		_part(self, Vector3(0.3, 16.0, 0.3), mast + Vector3(0, 8.0, 0), Color(0.25, 0.28, 0.34), false, yaw)
		var blade := mast + Vector3(0, 13.5, 0)
		_part(self, Vector3(7.0, 3.0, 0.15), blade, Color(color, 1.0).darkened(0.55), true, yaw)
		_part(self, Vector3(7.4, 0.12, 0.2), blade + Vector3(0, 1.56, 0), color, true, yaw)
		_part(self, Vector3(7.4, 0.12, 0.2), blade - Vector3(0, 1.56, 0), color, true, yaw)
		for face: float in [0.0, PI]:
			_sign(str(entry.get("name", "")).to_upper(), blade + Basis(Vector3.UP, yaw + face) * Vector3(0, 0, 0.1),
					yaw + face, 1.6, Color(1, 1, 1).lerp(color, 0.35))
		_stalls.append({"at": at, "yaw": yaw, "color": color})


## South: a ring of arrival points, so a crowd does not stack on one spot,
## and the way out beside it.
func _build_arrival() -> void:
	_slab_disc(9.0, PAVING, ARRIVAL)
	_slab_ring(9.0, 0.4, 48, CYAN, 0.06, null, ARRIVAL)
	for i in 12:
		_add_marker("spawn_player", ARRIVAL + _at(5.0, 360.0 * i / 12.0) + Vector3(0, 0.2, 0))
	# The way out, at the far end of the south boulevard past the screens.
	var door := Vector3(0, 0, RADIUS - 10.0)
	_box(Vector3(7, 6, 2), door + Vector3(0, 3, 3.5), DARK, 0.0)
	_add_portal("leave", "Leave the server", door, 2.6)
	_sign("EXIT", door + Vector3(0, 4.6, 2.45), PI, 0.9, Color(1.0, 0.45, 0.4))


## South, past the arcade: a big screen wall over tiers of seats, where
## people gather to watch how the worlds are doing. What plays on it comes later.
func _build_screens() -> void:
	var wall_at := SCREENS_AT + Vector3(0, 0, 10)
	_box(Vector3(40, 16, 3), wall_at + Vector3(0, 8, 1.5), WALL, 0.0)
	_add_seams(wall_at + Vector3(0, 8, 1.5), Vector3(40, 16, 3), 0.0, CYAN, 20.0)
	# Pylons either side, lit up their fronts.
	for side: float in [-1.0, 1.0]:
		var pylon := wall_at + Vector3(side * 21.5, 10.0, 0.5)
		_box(Vector3(3, 20, 4), pylon, WALL, 0.0)
		_part(self, Vector3(0.25, 19.0, 0.1), pylon + Vector3(-side * 0.8, 0, -2.05), MAGENTA, true)
		_part(self, Vector3(0.25, 19.0, 0.1), pylon + Vector3(side * 0.8, 0, -2.05), MAGENTA, true)
	var screen := Node3D.new()
	screen.name = "ScreenWall"
	screen.position = wall_at + Vector3(0, 8.5, -0.1)
	screen.rotation.y = PI
	screen.add_to_group("screen_wall")
	add_child(screen)
	# The node faces the seats: its local -Z is toward the wall behind it.
	_part(screen, Vector3(31, 12, 0.08), Vector3(0, 0, -0.06), Color(0.05, 0.06, 0.08))
	_part(screen, Vector3(30, 11, 0.1), Vector3.ZERO, Color(0.04, 0.16, 0.26), true)
	# A lit frame round the picture.
	for y: float in [-5.75, 5.75]:
		_part(screen, Vector3(31, 0.2, 0.12), Vector3(0, y, 0.04), CYAN, true)
	for x: float in [-15.5, 15.5]:
		_part(screen, Vector3(0.2, 11.7, 0.12), Vector3(x, 0, 0.04), CYAN, true)
	_sign("THE BIG SCREEN", wall_at + Vector3(0, 15.2, -0.2), PI, 1.4, CYAN)
	_sign("WAR ROOM", wall_at + Vector3(0, 10.5, -0.25), PI, 2.4, Color(0.6, 0.95, 1.0))
	_sign("Live from the worlds", wall_at + Vector3(0, 8.4, -0.25), PI, 0.8, Color(0.85, 0.9, 1.0))
	# Tiers facing the screen, low enough to step up, a light along each edge.
	for row in 4:
		var z := SCREENS_AT.z - 14.0 - row * 3.0
		var tall := 0.4 + row * 0.4
		var width := 30.0 + row * 4.0
		_box(Vector3(width, tall, 2.6), Vector3(0, tall * 0.5, z), STEEL, 0.0)
		_part(self, Vector3(width, 0.06, 0.08), Vector3(0, tall - 0.05, z + 1.32), CYAN, true)


## Two raised stages by the spire, lit for showing off, and benches round it.
func _build_show_floor() -> void:
	for bearing: float in [150.0, 210.0]:
		var at := _at(40.0, bearing)
		_box(Vector3(12, 0.4, 8), at + Vector3(0, 0.2, 0), DARK, -deg_to_rad(bearing))
		_add_marker("stage", at + Vector3(0, 0.45, 0))
	for i in 8:
		var bearing := 360.0 * i / 8.0 + 22.5
		_box(Vector3(4.0, 0.5, 1.0), _at(21.0, bearing) + Vector3(0, 0.25, 0), STEEL, -deg_to_rad(bearing))


## Between the plaza and the arcade: floating holo-ads, lit planters and
## seats, so the open floor feels lived in without boxing it in. The ads are
## made-up brands; nothing here has collision but the planters and seats.
const ADS := [["RIG TUNING", "Fly further. Ask the Outfitter.", CYAN],
		["THE PIT", "Bouts every hour. Bring a blade.", Color(1.0, 0.35, 0.4)],
		["FROSTLINE", "Quiet snow. Old secrets.", Color(0.55, 0.85, 1.0)],
		["NOVA THREADS", "Look the part. Tailor, west arcade.", MAGENTA],
		["ASHFRONT", "Full loot. No refunds.", Color(1.0, 0.6, 0.3)],
		["HOMEWARD", "Your quarters, your trophies.", Color(0.5, 1.0, 0.75)]]


func _build_fill() -> void:
	var slots := [22.5, 67.5, 112.5, 247.5, 292.5, 337.5]
	for i in slots.size():
		var bearing: float = slots[i]
		var ad: Array = ADS[i % ADS.size()]
		var at := _at(40.0, bearing)
		var yaw := -deg_to_rad(bearing)
		var color: Color = ad[2]
		# A slim post and a floating panel facing the spire.
		_part(self, Vector3(0.2, 5.0, 0.2), at + Vector3(0, 2.5, 0), Color(0.25, 0.28, 0.34))
		var panel := at + Vector3(0, 6.5, 0)
		_part(self, Vector3(5.0, 2.6, 0.06), panel, Color(color, 1.0).darkened(0.7), true, yaw)
		_part(self, Vector3(5.2, 0.08, 0.1), panel + Vector3(0, 1.34, 0), color, true, yaw)
		var front := Basis(Vector3.UP, yaw) * Vector3(0, 0, 0.06)
		_sign(ad[0], panel + front + Vector3(0, 0.45, 0), yaw, 0.75, Color(1, 1, 1).lerp(color, 0.3))
		_sign(ad[1], panel + front - Vector3(0, 0.45, 0), yaw, 0.28, Color(0.9, 0.92, 1.0), 4.6)
		# Planters with a light rim either side, and a seat between.
		var across := Basis(Vector3.UP, yaw) * Vector3(1, 0, 0)
		for side: float in [-1.0, 1.0]:
			var pot := at + across * side * 5.0
			_box(Vector3(2.6, 0.8, 2.6), pot + Vector3(0, 0.4, 0), DARK, yaw)
			_part(self, Vector3(2.7, 0.06, 2.7), pot + Vector3(0, 0.82, 0), color.darkened(0.2), true, yaw)
			# Light reeds: thin glowing stems of different heights.
			for k in 5:
				var stem := pot + Basis(Vector3.UP, yaw + k * 1.3) * Vector3(0.7, 0, 0) * (0.3 + 0.15 * k)
				var tall := 1.4 + 0.35 * ((k * 3 + i) % 4)
				_part(self, Vector3(0.07, tall, 0.07), stem + Vector3(0, 0.8 + tall * 0.5, 0), Color(0.35, 1.0, 0.75), true)
		_box(Vector3(3.4, 0.45, 0.9), at + Basis(Vector3.UP, yaw) * Vector3(0, 0.225, 1.6), STEEL, yaw)


## Clean floor tiles: a fine grid of seams over the deck, drawn as one mesh.
func _build_tiles() -> void:
	var step := 6.0
	var parts: Array = []
	var reach := RADIUS - 2.0
	var lines := int(reach / step)
	for i in range(-lines, lines + 1):
		var offset := i * step
		var half := sqrt(maxf(reach * reach - offset * offset, 0.0))
		if half < 1.0:
			continue
		parts.append([Vector3(0.06, 0.012, half * 2.0), Transform3D(Basis.IDENTITY, Vector3(offset, 0.006, 0))])
		parts.append([Vector3(half * 2.0, 0.012, 0.06), Transform3D(Basis.IDENTITY, Vector3(0, 0.006, offset))])
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.08, 0.09, 0.12)
	mat.roughness = 0.4
	_batch_sized(parts, mat)


## The city far below the balcony and the skyline round it: scenery only, with
## no collision, out of reach. Its own RNG so it never shifts the layout.
func _build_city_below() -> void:
	if not Look.enabled:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = LAYOUT_SEED + 1
	var city := Node3D.new()
	city.name = "City"
	add_child(city)
	var streets := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(4000, 4000)
	plane.material = Look.surface("asphalt", {"tint": Color(0.18, 0.18, 0.22), "grime": 0.3, "scale": 0.02})
	streets.mesh = plane
	streets.position = Vector3(0, -80.0, 0)
	streets.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	city.add_child(streets)
	# Stepped towers of the same dark glass with lit seams, drawn as one mesh.
	var blocks: Array = []
	for i in 60:
		var bearing := rng.randf() * 360.0
		var r := rng.randf_range(RADIUS + 40.0, RADIUS + 260.0)
		var w := rng.randf_range(14.0, 30.0)
		var tall := rng.randf_range(80.0, 200.0) if r > RADIUS + 120.0 else rng.randf_range(20.0, 70.0)
		var floor_y := -80.0
		var yaw := rng.randf() * TAU
		var base := _at(r, bearing) + Vector3(0, floor_y, 0)
		var color: Color = [CYAN, MAGENTA, Color(0.55, 0.7, 1.0)][i % 3]
		var tiers := [[w, 0.0, tall * 0.6], [w * 0.7, tall * 0.6, tall]]
		for tier: Array in tiers:
			var size := Vector3(tier[0], tier[2] - tier[1], tier[0])
			var centre := base + Vector3(0, (tier[1] + tier[2]) * 0.5, 0)
			blocks.append([size, Transform3D(Basis(Vector3.UP, yaw), centre)])
			_add_seams(centre, size, yaw, color, 10.0)
	_batch_sized(blocks, WALL)


func _dress() -> void:
	if not Look.enabled:
		return
	var art := Node3D.new()
	art.name = "Dressing"
	add_child(art)
	# Few real lights: the glow strips carry the look, lamps only where people
	# stand to read something.
	var beacon := Look.lamp(Color(0.6, 0.95, 1.0), 10.0, 60.0)
	beacon.position = Vector3(0, 61.0, 0)
	art.add_child(beacon)
	var base := Look.lamp(Color(0.5, 0.9, 1.0), 4.0, 24.0)
	base.position = Vector3(0, 6.0, 0)
	art.add_child(base)
	for gate in _gates:
		var glow := Look.lamp(Color(1.0, 0.5, 0.2), 5.0, 16.0)
		glow.position = gate["at"] + Vector3(0, 5.0, 2.0)
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
	home.position = Vector3(-SIDE_DISTRICT + 2.5, 3.4, 0)
	art.add_child(home)
	var clan := Look.lamp(Color(0.8, 0.5, 1.0), 4.0, 14.0)
	clan.position = Vector3(SIDE_DISTRICT - 3.0, 5.0, 0)
	art.add_child(clan)
	var screens := Look.lamp(CYAN, 6.0, 30.0)
	screens.position = SCREENS_AT + Vector3(0, 8.0, 4.0)
	art.add_child(screens)


## A point `radius` metres out on compass `bearing` (degrees, 0 north, clockwise).
func _at(radius: float, bearing: float) -> Vector3:
	var a := deg_to_rad(bearing)
	return Vector3(sin(a) * radius, 0, -cos(a) * radius)


func _near_spoke(bearing: float, radius: float, clearance: float) -> bool:
	for spoke: float in SPOKES:
		var off := absf(wrapf(bearing - spoke, -180.0, 180.0))
		if deg_to_rad(off) * radius < clearance:
			return true
	return false


func _near_kiosk(bearing: float) -> bool:
	for slot: float in MARKET_SLOTS:
		if deg_to_rad(absf(wrapf(bearing - slot, -180.0, 180.0))) * MARKET_RING < 7.0:
			return true
	return false


## Lit seams on a box: a band round it every `spacing` metres and a strip up
## each corner. Collected and drawn as one mesh per colour (`_flush_seams`).
func _add_seams(centre: Vector3, size: Vector3, yaw: float, color: Color, spacing: float) -> void:
	if not _seams.has(color):
		_seams[color] = []
	var list: Array = _seams[color]
	var turn := Basis(Vector3.UP, yaw)
	var bottom := -size.y * 0.5
	var y := spacing
	while y < size.y - 0.5:
		for face in 4:
			var along_x := face % 2 == 0
			var sign_f := 1.0 if face < 2 else -1.0
			var offset := Vector3(0, bottom + y, sign_f * (size.z * 0.5 + 0.03)) if along_x \
					else Vector3(sign_f * (size.x * 0.5 + 0.03), bottom + y, 0)
			var band := Vector3(size.x + 0.02, 0.12, 0.04) if along_x else Vector3(0.04, 0.12, size.z + 0.02)
			list.append([band, Transform3D(turn, centre + turn * offset)])
		y += spacing
	for cx: float in [-1.0, 1.0]:
		for cz: float in [-1.0, 1.0]:
			var corner := Vector3(cx * (size.x * 0.5 + 0.02), 0, cz * (size.z * 0.5 + 0.02))
			list.append([Vector3(0.1, size.y, 0.1), Transform3D(turn, centre + turn * corner)])


func _flush_seams() -> void:
	for color: Color in _seams:
		_batch_sized(_seams[color], _glow(color))
	_seams.clear()
	for key: Array in _parts:
		var mat: Material
		if key[1]:
			mat = _glow(key[0])
		else:
			var plain := StandardMaterial3D.new()
			plain.albedo_color = key[0]
			mat = plain
		_batch_sized(_parts[key], mat)
	_parts.clear()
	_flushed = true


## Boxes of many sizes as one mesh, no collision: [[size, transform], ...].
func _batch_sized(parts: Array, material: Material) -> void:
	if parts.is_empty():
		return
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for part: Array in parts:
		var box := BoxMesh.new()
		box.size = part[0]
		tool.append_from(box, 0, part[1])
	var mesh := tool.commit()
	mesh.surface_set_material(0, material)
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)


## Tinted glass for canopies: see-through, with a sheen.
func _glass() -> StandardMaterial3D:
	if _glass_mat:
		return _glass_mat
	_glass_mat = StandardMaterial3D.new()
	_glass_mat.albedo_color = Color(0.45, 0.8, 1.0, 0.2)
	_glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glass_mat.metallic = 0.6
	_glass_mat.roughness = 0.05
	_glass_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _glass_mat


## A glowing material, one per colour.
func _glow(color: Color) -> StandardMaterial3D:
	if _glow_mats.has(color):
		return _glow_mats[color]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color.darkened(0.3)
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 2.0
	_glow_mats[color] = mat
	return mat


## The floor itself: a flat round slab with collision.
func _disc(radius: float, height: float, at: Vector3, material: Material) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = Actor.LAYER_WORLD
	body.collision_mask = 0
	body.position = at
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 96
	mesh.material = material
	var node := MeshInstance3D.new()
	node.mesh = mesh
	body.add_child(node)
	nav_region.add_child(body)


## A thin round plate set into the floor. No collision.
func _slab_disc(radius: float, material: Material, at := Vector3.ZERO) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 0.03
	mesh.radial_segments = 64
	mesh.material = material
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = at + Vector3(0, 0.015, 0)
	add_child(node)


## A ring of thin plates (a glowing line unless a material is given), drawn
## as one mesh. No collision.
func _slab_ring(radius: float, width: float, segments: int, color: Color, height := 0.05,
		material: Material = null, centre := Vector3.ZERO) -> void:
	var plates: Array[Transform3D] = []
	for i in segments:
		var bearing := 360.0 * (i + 0.5) / segments
		var at := centre + _at(radius, bearing)
		at.y = height
		plates.append(Transform3D(Basis(Vector3.UP, -deg_to_rad(bearing)), at))
	_batch(Vector3(TAU * radius / segments + 0.05, 0.04, width), plates, material if material else _glow(color), false)


## Many boxes of one size and material as a single mesh, so a ring of them is
## one draw call; with `collide`, one static body holds a shape for each.
func _batch(size: Vector3, places: Array[Transform3D], material: Material, collide: bool) -> void:
	if places.is_empty():
		return
	var box := BoxMesh.new()
	box.size = size
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for place in places:
		tool.append_from(box, 0, place)
	var mesh := tool.commit()
	mesh.surface_set_material(0, material)
	var node := MeshInstance3D.new()
	node.mesh = mesh
	if not collide:
		add_child(node)
		return
	var body := StaticBody3D.new()
	body.collision_layer = Actor.LAYER_WORLD
	body.collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = size
	for place in places:
		var col := CollisionShape3D.new()
		col.shape = shape
		col.transform = place
		body.add_child(col)
	body.add_child(node)
	nav_region.add_child(body)


## A glowing square outline on the floor. No collision.
func _slab_square(at: Vector3, size: float, yaw: float, color: Color) -> void:
	for i in 4:
		var side := Basis(Vector3.UP, yaw + TAU * i / 4.0)
		_slab(Vector3(size, 0.05, 0.25), at + side * Vector3(0, 0, size * 0.5), _glow(color), yaw + TAU * i / 4.0)


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
func _part(parent: Node3D, size: Vector3, at: Vector3, color: Color, glow := false, yaw := 0.0) -> void:
	# Fixed parts of the map itself are drawn in batches by colour.
	if parent == self and not _flushed:
		var key := [color, glow]
		if not _parts.has(key):
			_parts[key] = []
		(_parts[key] as Array).append([size, Transform3D(Basis(Vector3.UP, yaw), at)])
		return
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
	node.rotation.y = yaw
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
