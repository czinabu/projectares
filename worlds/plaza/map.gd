extends Node3D
## Greybox Concourse: a big open deck high over the city, with no wall, laid
## out in districts round a beacon spire. Each district has one job, and its
## name is on the building that does it. Nothing floats over the floor: no
## ads, no mast signs, no glowing pads. You walk up to a person at a counter,
## or through an arch, and the prompt says what it is.
##
##   centre      the spire plaza: the arrival pad, podiums to be seen on,
##               benches and stages
##   south       Market Row, a covered street of shopfronts, each staffed
##               and fitted out for its trade; the transit hall (the way
##               out) at its far end
##   north       the gate terrace: one arch per raid world, spares sealed,
##               and a dispatcher who knows how the worlds are doing
##   east        the civic square: the clan hall, the contract board (Rook),
##               the most-wanted board (Kade) and the big screen
##   west        the residences: the lift to your home base, with a concierge
##   south-east  the arena gate, with a promoter
##   south-west  the RC yard, shuttered until it opens
##   boulevards stops between the plaza and the districts: a food court
##               on the way to the civic square, a fountain square on the
##               way to the gates, a tea cart and bike park by the
##               residences, trees and light sculptures down the diagonals
##   between     gardens on the diagonals, slim towers with landing decks
##               and skybridges at DECK_HEIGHT, then a ground loop for bikes
##               and the balcony rail
##
## Angles in this file are compass bearings in degrees: 0 is north (-Z) and
## they turn clockwise, so 90 is east (+X). See `_at`. A thing that "faces"
## a way has its local +Z that way; its yaw is atan2(dir.x, dir.z).
##
## Portals follow the safe-zone contract in WorldDef: Marker3D nodes in group
## "portal" with a "destination" and a "label".

const VehicleScript := preload("res://core/vehicle/vehicle.gd")
const MEGACITY := preload("res://worlds/plaza/megacity.gd")

## The balcony rail, where the deck ends.
const RADIUS := 240.0
const PLAZA_RING := 40.0
const PODIUM_RING := 13.0
const PODIUMS := 6
const ARRIVAL := Vector3(0, 0, 28)
const LAYOUT_SEED := 707
## The shops come from the economy's shop list, read at runtime so the plaza
## still builds in a game without one.
const SHOP_DB := "res://core/economy/shop_db.gd"
## The contract rules, read the same way, for the jobs written on the board.
const CONTRACTS := "res://core/economy/contracts.gd"

## Market Row: a straight covered street running south from the plaza, the
## shopfronts facing each other across it. A front is SHOP_WIDTH along the
## street, SHOP_DEPTH back from it and SHOP_HEIGHT to the ceiling.
const ROW_FROM := 62.0
const ROW_TO := 146.0
const STREET_HALF := 6.5
const SHOP_WIDTH := 16.0
const SHOP_DEPTH := 11.0
const SHOP_HEIGHT := 6.0
## Where each front stands, in the shop list's order: [side, z]. Side -1 is
## the west side of the street (facing east), 1 the east side.
const ROW_SLOTS := [[-1.0, 80.0], [1.0, 80.0], [-1.0, 104.0], [1.0, 104.0], [-1.0, 128.0], [1.0, 128.0]]
## Shoppers keep to a lane either side of the street's middle, so they never
## walk through the benches down it.
const ROW_LANE := 3.5
## The player market's front, built in the next free slot after the shops.
const EXCHANGE := {"id": "exchange", "name": "Exchange", "destination": "market",
		"blurb": "PLAYER MARKET"}
## What each trade calls itself over its door, and its colour.
const TRADES := {
	"armory": ["GUNS  ·  BLADES  ·  ATTACHMENTS", Color(1.0, 0.42, 0.32)],
	"outfitter": ["ARMOR  ·  HELMETS  ·  FLIGHT RIGS  ·  MEDICAL", Color(0.4, 0.9, 0.55)],
	"garage": ["BIKES  ·  ROVERS  ·  REPAIRS", Color(1.0, 0.8, 0.3)],
	"furnisher": ["FOR YOUR QUARTERS", Color(0.55, 0.75, 1.0)],
	"tailor": ["CLOTHES  ·  YOURS FOR GOOD", Color(1.0, 0.4, 0.85)],
	"exchange": ["PLAYER MARKET", Color(0.3, 0.9, 1.0)],
	"black_market": ["NO QUESTIONS", Color(1.0, 0.25, 0.2)],
}
## Who works each counter: shop id -> [name, role, lines]. They greet you
## when you trade there (`core/social/plaza_locals.gd`).
const KEEPERS := {
	"armory": ["Vasko", "Armorer", ["Carbines came in this morning. Want one with a scope on it?",
			"Nothing fancy in here. The good stuff is out there, on someone else.",
			"Sell me what you don't carry. I'll find it a home."]],
	"outfitter": ["Ines", "Outfitter", ["First rig? Boots are cheap and quiet. Jetpacks get you seen.",
			"Plates first, then a helmet. You can't loot anything dead.",
			"Medkits are by the till. Take two."]],
	"garage": ["Bram", "Mechanic", ["She's no racer, but she'll get you out and back. Mostly.",
			"Throw it, ride it, bring it home. In that order.",
			"Bikes don't come back from Ashfront on their own."]],
	"furnisher": ["Pell", "Furnisher", ["Make that bunker feel like home.",
			"A lamp and a chair. You'd be surprised what that does to a room."]],
	"tailor": ["Odile", "Tailor", ["Try it on. The mirror's honest.",
			"Once it's yours, it's yours. Nobody loots a jacket off you here."]],
	"exchange": ["Tamsin", "Broker", ["List it, set a price, I'll hold it.",
			"Other people's finds, at other people's prices."]],
	"black_market": ["Sable", "Fence", ["Two pieces a day. When they're gone, they're gone.",
			"You want it cheap, go take it off a body. You want it now, you pay.",
			"Tomorrow's different. Always is."]],
}
## The back room's stall (a shop with "stall" in the shop list): down the
## alley between the first two fronts on the west side of Market Row.
const STALL_AT := Vector3(-STREET_HALF, 0, 92.0)

## The civic square, east of the spire: the clan hall on its far side, the
## big screen on its north side, the boards on its south side.
const CIVIC := Vector3(152, 0, 0)
const CIVIC_SIZE := Vector2(72, 84)
const CLAN_HALL_AT := Vector3(178, 0, 0)
const SCREEN_AT := Vector3(150, 0, -43)
const CONTRACT_BOARD_AT := Vector3(136, 0, 38)
## The most-wanted board, the contract board's twin across the square
## (DESIGN.md section 2, "Hub activities").
const WANTED_BOARD_AT := Vector3(164, 0, 38)
## The residences, west of the spire: the quarters' lift home on the far side.
const RESIDENCES := Vector3(-152, 0, 0)
const QUARTERS_AT := Vector3(-180, 0, 0)
const GARDENS := [45.0, 135.0, 225.0, 315.0]
const GARDEN_RING := 92.0
## The stops along the boulevards (see `_build_boulevards`), each halfway out
## to the district it serves, its carts and tables either side of the lane.
const FOOD_COURT := Vector3(78, 0, 0)
const FOUNTAIN := Vector3(0, 0, -100)
const BIKE_CORNER := Vector3(-80, 0, 0)
## Down the diagonals: trees either side, clear of the stroll ring (r50-56)
## and the gardens, and a pair of light sculptures where each leaves the plaza.
const TREE_RINGS := [64.0, 76.0, 116.0, 130.0, 144.0]
const TREE_SIDE := 6.0
const SCULPTURE_RING := 44.0
## The people of the Concourse you can talk to (`core/social/plaza_locals.gd`
## stands them there): id -> [where, facing yaw, name, role, lines, reads].
## Yaw 0 faces north (-Z); PI faces south. `lines` are said in turn; `reads`
## "worlds" makes the line out of how the worlds are doing instead.
const TALKERS := {
	"kade": [Vector3(166.6, 0, 35.9), 0.15, "Kade", "Bounty broker", [], ""],
	"dusk": [Vector3(19.5, 0, 12.0), 2.45, "Dusk", "Hears things", [], ""],
	"rook": [Vector3(129.5, 0, 35.0), -0.1, "Rook", "Odd jobs", [], ""],
	"marlo": [Vector3(-44.0, 0, -168.0), PI + 0.35, "Marlo", "Dispatcher", [], "worlds"],
	"wren": [Vector3(-175.6, 0, 6.0), -PI / 2.0, "Wren", "Concierge",
			["Your quarters are through the lift. It knows where you live.",
			"Anything you bring home stays home. Anything you take out is fair game.",
			"Visitors? Your friends can call on your base from their phones."], ""],
	"sola": [Vector3(117.0, 0, 126.9), PI / 4.0, "Sola", "Promoter",
			["Bouts in the Pit, any hour. Nobody loses their kit in there, only their pride.",
			"Bring a blade. The crowd likes a blade.",
			"Wager on yourself. Everyone else is."], ""],
}
## What someone says instead while the launch holds back what they talk
## about (`LaunchScope`): talker id -> {held feature: lines}.
const HELD_LINES := {
	"sola": {"arena": ["The Pit opens soon. I'll be the first to tell you.",
			"Keep your blade sharp. The crowd's waiting too."]},
	"wren": {"base_visits": ["Your quarters are through the lift. It knows where you live.",
			"Anything you bring home stays home. Anything you take out is fair game."]},
}


## The held-back feature a talker's lines are about, or "" if none is held.
static func _held_by(id: String) -> String:
	for feature: String in HELD_LINES.get(id, {}):
		if LaunchScope.holds(feature):
			return feature
	return ""


## What each of them wears for their work (`Human.random`'s pool: build ->
## outfits), so the armorer looks like an armorer and the tailor dresses
## well. Anyone missing is dressed at random.
const DRESS := {
	"keep_armory": {"m": ["Swat"]},
	"keep_outfitter": {"f": ["Adventurer"]},
	"keep_garage": {"m": ["Farmer"]},
	"keep_furnisher": {"m": ["Casual_2"]},
	"keep_tailor": {"f": ["Formal"]},
	"keep_exchange": {"f": ["Suit"]},
	"keep_black_market": {"f": ["Punk"]},
	"clerk": {"m": ["Suit"]},
	"marlo": {"f": ["Soldier"]},
	"wren": {"f": ["Formal"]},
	"sola": {"f": ["Punk"]},
	"kade": {"m": ["Punk"]},
	"dusk": {"m": ["Casual_Hoodie"]},
	"rook": {"m": ["Adventurer"]},
}
## The clan hall's clerk works its terminal like a keeper works a counter.
const CLERK := ["Ansel", "Clerk", ["Found a clan, or join one. The paperwork's lighter than the fighting.",
		"A clan shares its sites out there. And its grudges."]]
## The boulevards: bearings and widths, from the plaza out to the districts.
const SPOKES := [0.0, 45.0, 90.0, 135.0, 180.0, 225.0, 270.0, 315.0]
const TOWER_RING := 120.0
## The beacon spire's top, over everything on the deck.
const SPIRE_TOP := 194.0
## Taller than the deck is wide, so the near ring looks down on you (Caleb's
## ask: tall and grand from the ground).
const TOWER_HEIGHTS := [230.0, 135.0, 175.0, 120.0, 260.0, 150.0, 205.0, 140.0]
const TOWER_SIZE := 10.0
## Tops of the tower decks and skybridges. Three boot kicks reach 15 m.
const DECK_HEIGHT := 15.0
## The gate terrace: how far north, and how many arches (worlds fill the
## first ones, the rest stand sealed for worlds to come).
const GATE_LINE := 185.0
const GATE_ARCHES := 4
const GATE_SPACING := 22.0
const ARENA_BEARING := 135.0
const RC_BEARING := 225.0
const DISTRICT_RING := 175.0
const TRANSIT_AT := Vector3(0, 0, 205)
const BIKE_RING := 222.0
const BIKE_WIDTH := 10.0
## The casing of a terminal.
const DARK_GLASS := Color(0.12, 0.12, 0.14)
const CYAN := Color(0.25, 0.9, 1.0)
const MAGENTA := Color(1.0, 0.3, 0.85)
const WARM := Color(1.0, 0.88, 0.72)

var nav_region: NavigationRegion3D
var _art_rng := RandomNumberGenerator.new()
var _gates: Array[Dictionary] = []
## Every arch on the gate terrace, open or sealed (see `gate_bays`).
var _gate_bays: Array[Dictionary] = []
## Each shopfront: {id, at, yaw, color, door}: `at` is the middle of its
## front on the street, `door` where a window shopper stands.
var _fronts: Array[Dictionary] = []
var _glow_mats := {}
## Lit seams waiting to be drawn: colour -> [[size, transform], ...], drawn as
## one mesh per colour by `_flush_seams`.
var _seams := {}
var _glass_mat: StandardMaterial3D
## Plain parts of the map waiting to be drawn: [colour, glow] -> [[size, transform], ...].
var _parts := {}
## Solid walls, counters and shelves: one body holds every shape, and the
## boxes are drawn as one mesh per material (`_solid`, `_flush_seams`).
var _solid_body: StaticBody3D
var _solid_parts := {}
var _flushed := false
## Where the street lamps and shop lights hang; `_dress` lights each.
var _lamps: Array[Vector3] = []
var _shop_lights: Array[Array] = []
## Where a lamp washes up each near tower's foot (`_dress`).
var _foot_lights: Array[Vector3] = []
## The near towers' glass, lit floor by floor like the megacity's.
var _tower_glass: Material
## Each cart's customers, for the locals: see `locals_layout`'s "stops".
var _stops: Array[Dictionary] = []

## The deck reads as pale brushed alloy under the twilight: mostly diffuse
## (low metal, rougher), so it catches the lamps and the glow strips instead
## of mirroring the dark sky, which made it read as black.
@onready var FLOOR := Look.surface("metal", {"tint": Color(0.85, 0.9, 1.0), "grime": 0.0, "scale": 0.05,
		"wetness": 0.08, "metal": 0.15, "rough_mult": 1.5})
@onready var PAVING := Look.surface("metal", {"tint": Color(0.75, 0.8, 0.9), "grime": 0.1, "scale": 0.2,
		"metal": 0.15, "rough_mult": 1.4})
@onready var INLAY := Look.surface("metal", {"tint": Color(0.75, 0.55, 0.3), "grime": 0.3, "scale": 0.3})
## Dark glass and metal panels: the hub's buildings. Lit seams, never a grid of
## windows (that read as old flats, not sci-fi).
@onready var WALL := Look.surface("metal", {"tint": Color(0.17, 0.21, 0.31), "grime": 0.0, "scale": 0.08,
		"rough_mult": 0.25, "wetness": 0.8})
@onready var STEEL := Look.surface("metal", {"tint": Color(0.52, 0.55, 0.62), "grime": 0.2, "scale": 0.3,
		"metal": 0.5, "rough_mult": 1.2})
## Podiums, planters and stages: darker than the deck so they stand out, but
## not so metallic that they turn into black holes against the floor.
@onready var DARK := Look.surface("metal", {"tint": Color(0.4, 0.44, 0.52), "grime": 0.2, "scale": 0.3,
		"metal": 0.4, "rough_mult": 1.2})
## The near towers' feet: sci-fi plate, dark, so the lit glass above reads.
@onready var CLADDING := Look.surface("panels", {"tint": Color(0.62, 0.66, 0.8), "grime": 0.15, "scale": 0.16,
		"metal": 0.55, "rough_mult": 1.0})
## Inside a shop: warm pale panels, so the lights carry the room.
@onready var INSIDE := Look.surface("metal", {"tint": Color(0.78, 0.76, 0.74), "grime": 0.1, "scale": 0.25,
		"metal": 0.2, "rough_mult": 1.4})


func _ready() -> void:
	_art_rng.seed = LAYOUT_SEED
	_tower_glass = MEGACITY.material_for(true)
	_build_environment()
	nav_region = NavigationRegion3D.new()
	nav_region.name = "Geometry"
	add_child(nav_region)
	_build_ground()
	_build_spire()
	_build_arrival()
	_build_towers()
	_build_gates()
	_build_market_row()
	_build_transit()
	_build_civic_square()
	_build_residences()
	_build_arena_gate()
	_build_rc_yard()
	_build_gardens()
	_build_boulevards()
	_build_talkers()
	_build_city_below()
	_flush_seams()
	_dress()


func _build_environment() -> void:
	# Permanent deep-blue twilight: dark enough that the hub's lights carry
	# it, a calm, cool sky after the grey of the warzones (Caleb's call: grand
	# and sci-fi, with the neon glowing).
	Look.atmosphere(self, {
		# A deep dusk over the megacity, warm where the canyon's light comes
		# up into the haze, so the windows and the traffic carry the sky.
		"sky": "qwantani_dusk_1_puresky_2k.hdr",
		"sky_tint": Color(0.68, 0.6, 1.0),
		"sky_saturation": 0.9,
		"sky_energy": 0.24,
		"fog_color": Color(0.42, 0.24, 0.32),
		"fog_density": 0.0022,
		"haze_height": 0.36,
		"sun_color": Color(0.75, 0.65, 1.0),
		"sun_energy": 0.55,
		"sun_angles": Vector3(-14, 35, 0),
		"ambient_color": Color(0.5, 0.52, 0.75),
		"ambient_energy": 1.0,
		"saturation": 0.95,
		"glow": 0.8,
	})
	Look.weather(self, "embers", RADIUS * 0.5)


## The deck: a round floor out to the balcony rail, paved where people walk,
## with glowing boulevards from the spire out to every district.
func _build_ground() -> void:
	_disc(RADIUS + 2.0, 1.0, Vector3(0, -0.5, 0), FLOOR)
	_build_tiles()
	# The rail: waist high, so the view stays open. Hop it and you fall to the
	# city, and the safe zone puts you back on the arrival pad.
	var segments := 120
	var rail: Array[Transform3D] = []
	for i in segments:
		var bearing := 360.0 * i / segments
		rail.append(Transform3D(Basis(Vector3.UP, -deg_to_rad(bearing)), _at(RADIUS, bearing) + Vector3(0, 0.55, 0)))
	_batch(Vector3(TAU * RADIUS / segments + 0.2, 1.1, 0.4), rail, STEEL, true)
	_slab_ring(RADIUS - 1.0, 0.5, 120, CYAN, 0.06)
	# The plaza round the spire, paved, with an inlaid ring at its edge.
	_slab_disc(PLAZA_RING, PAVING)
	_slab_ring(PLAZA_RING, 0.6, 72, CYAN)
	_slab_ring(PODIUM_RING + 4.0, 0.4, 48, Color.BLACK, 0.05, INLAY)
	# Boulevards: a paved strip with a light line down the middle, out to
	# where each district starts.
	var reach := {0.0: GATE_LINE - 26.0, 90.0: CIVIC.x - CIVIC_SIZE.x * 0.5, 180.0: ROW_FROM,
			270.0: -RESIDENCES.x - 36.0}
	for bearing: float in SPOKES:
		var main := int(bearing) % 90 == 0
		var width := 12.0 if main else 7.0
		var end: float = reach.get(bearing, DISTRICT_RING - 20.0)
		var length := end - PLAZA_RING
		var mid := _at(PLAZA_RING + length * 0.5, bearing)
		_slab(Vector3(width, 0.03, length), mid, PAVING, -deg_to_rad(bearing))
		_slab(Vector3(0.35, 0.05, length), mid, _glow(CYAN), -deg_to_rad(bearing))
		for side: float in [-1.0, 1.0]:
			var edge := mid + Basis(Vector3.UP, -deg_to_rad(bearing)) * Vector3(side * width * 0.5, 0, 0)
			_slab(Vector3(0.15, 0.05, length), edge, _glow(CYAN.darkened(0.4)), -deg_to_rad(bearing))
	# Past Market Row the street carries on to the transit hall.
	var tail := TRANSIT_AT.z - 6.0 - ROW_TO
	_slab(Vector3(12.0, 0.03, tail), Vector3(0, 0, ROW_TO + tail * 0.5), PAVING, 0.0)
	_slab(Vector3(0.35, 0.05, tail), Vector3(0, 0, ROW_TO + tail * 0.5), _glow(CYAN), 0.0)
	# The bike loop round the outside: a dark track between two light lines.
	_slab_ring(BIKE_RING, BIKE_WIDTH, 144, Color.BLACK, 0.02, DARK)
	for edge: float in [BIKE_RING - BIKE_WIDTH * 0.5, BIKE_RING + BIKE_WIDTH * 0.5]:
		_slab_ring(edge, 0.25, 144, Color(1.0, 0.65, 0.25), 0.04)


func _build_spire() -> void:
	_box(Vector3(10, 1.0, 10), Vector3(0, 0.5, 0), STEEL, PI / 4.0)
	_box(Vector3(5, 3.0, 5), Vector3(0, 2.5, 0), DARK, 0.0)
	# What this place is, on every face of the spire's base.
	for i in 4:
		var face := Basis(Vector3.UP, TAU * i / 4.0)
		_sign("SAFE ZONE", face * Vector3(0, 3.0, 2.53), TAU * i / 4.0, 0.55, Color(0.6, 0.95, 0.75))
		_sign("Weapons are locked here", face * Vector3(0, 2.35, 2.53), TAU * i / 4.0, 0.26, Color(0.9, 0.9, 0.9))
	# The shaft tapers as it climbs, a light seam up each corner.
	# Tall enough to stand over the near towers: the Concourse's own landmark.
	var levels := [[4.2, 4.0, 60.0], [3.2, 64.0, 50.0], [2.2, 114.0, 44.0], [1.3, 158.0, 36.0]]
	for level: Array in levels:
		var w: float = level[0]
		var base: float = level[1]
		var tall: float = level[2]
		_box(Vector3(w, tall, w), Vector3(0, base + tall * 0.5, 0), DARK, PI / 4.0)
		for i in 4:
			var corner := Basis(Vector3.UP, PI / 4.0 + TAU * i / 4.0) * Vector3(w * 0.5, 0, w * 0.5)
			_part(self, Vector3(0.18, tall, 0.18), corner + Vector3(0, base + tall * 0.5, 0), CYAN, true)
	_part(self, Vector3(1.2, 2.0, 1.2), Vector3(0, SPIRE_TOP + 1.0, 0), Color(0.75, 1.0, 1.0), true)
	_part(self, Vector3(0.3, 26.0, 0.3), Vector3(0, SPIRE_TOP + 15.0, 0), Color(0.75, 1.0, 1.0), true)
	# The beacon and mast on top are solid to anyone flying up to them.
	SolidProp.box(nav_region, Vector3(1.2, 2.0, 1.2), Transform3D(Basis.IDENTITY, Vector3(0, SPIRE_TOP + 1.0, 0)))
	SolidProp.box(nav_region, Vector3(0.3, 26.0, 0.3), Transform3D(Basis.IDENTITY, Vector3(0, SPIRE_TOP + 15.0, 0)))
	# Podiums: step up, strike a pose, be inspected.
	for i in PODIUMS:
		var bearing := 360.0 * i / PODIUMS + 180.0 / PODIUMS
		var at := _at(PODIUM_RING, bearing)
		_box(Vector3(3.2, 0.35, 3.2), at + Vector3(0, 0.175, 0), DARK, -deg_to_rad(bearing))
		_box(Vector3(2.4, 0.35, 2.4), at + Vector3(0, 0.525, 0), INLAY, -deg_to_rad(bearing))
		# A light skirt at the foot, so the podium reads against the floor.
		_part(self, Vector3(3.4, 0.05, 3.4), at + Vector3(0, 0.025, 0), CYAN.darkened(0.4), true, -deg_to_rad(bearing))
		_add_marker("podium", at + Vector3(0, 0.7, 0))
	# Two raised stages for showing off, benches round the spire, and street
	# lamps behind them so the floor people stand on is lit from close by.
	for bearing: float in [150.0, 210.0]:
		var at := _at(33.0, bearing)
		_box(Vector3(12, 0.4, 8), at + Vector3(0, 0.2, 0), DARK, -deg_to_rad(bearing))
		_add_marker("stage", at + Vector3(0, 0.45, 0))
	for i in 8:
		var bearing := 360.0 * i / 8.0 + 22.5
		_box(Vector3(4.0, 0.5, 1.0), _at(21.0, bearing) + Vector3(0, 0.25, 0), STEEL, -deg_to_rad(bearing))
		var at := _at(25.0, bearing)
		_part(self, Vector3(0.18, 4.6, 0.18), at + Vector3(0, 2.3, 0), Color(0.25, 0.28, 0.34))
		_part(self, Vector3(0.9, 0.12, 0.9), at + Vector3(0, 4.66, 0), Color(0.85, 0.95, 1.0), true)
		SolidProp.box(nav_region, Vector3(0.25, 4.6, 0.25), Transform3D(Basis.IDENTITY, at + Vector3(0, 2.3, 0)))
		_lamps.append(at + Vector3(0, 4.3, 0))


## South of the spire: a ring of arrival points, so a crowd does not stack
## on one spot.
func _build_arrival() -> void:
	_slab_disc(9.0, PAVING, ARRIVAL)
	_slab_ring(9.0, 0.4, 48, CYAN, 0.06, null, ARRIVAL)
	for i in 12:
		_add_marker("spawn_player", ARRIVAL + _at(5.0, 360.0 * i / 12.0) + Vector3(0, 0.2, 0))


## Slim towers round the districts. Each has a landing deck at DECK_HEIGHT
## and a skybridge to the next, so boots can hop the skyline; the tops are
## for wings and jetpacks.
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
		# The foot, up to the landing deck, is clad in plate where people
		# walk past it; the glass starts above.
		var foot := DECK_HEIGHT - 0.5
		_solid(Vector3(TOWER_SIZE, foot, TOWER_SIZE), at + Vector3(0, foot * 0.5, 0), CLADDING, yaw)
		tiers[0][1] = foot
		# A light strip at the foot and a lamp washing up the plate from the
		# deck side, so the cladding reads at night.
		_part(self, Vector3(TOWER_SIZE + 0.1, 0.12, TOWER_SIZE + 0.1), at + Vector3(0, 0.3, 0), color, true, yaw)
		_foot_lights.append(at - at.normalized() * (TOWER_SIZE * 0.5 + 5.0) + Vector3(0, 2.5, 0))
		for tier: Array in tiers:
			var w: float = tier[0]
			var size := Vector3(w, tier[2] - tier[1], w)
			var centre := at + Vector3(0, (tier[1] + tier[2]) * 0.5, 0)
			_solid(size, centre, _tower_glass, yaw)
			# Lit corners only: the windows are the material's.
			_add_seams(centre, size, yaw, color, size.y + 1.0)
			# A bright band where each tier steps in.
			_part(self, Vector3(w + 0.12, 0.25, w + 0.12), centre + Vector3(0, size.y * 0.5 - 0.15, 0), color, true, yaw)
		_part(self, Vector3(TOWER_SIZE * 0.5 + 0.3, 0.3, TOWER_SIZE * 0.5 + 0.3), at + Vector3(0, tall, 0), color, true)
		_part(self, Vector3(0.25, tall * 0.12, 0.25), at + Vector3(0, tall * 1.06, 0), color, true)
		_solid(Vector3(TOWER_SIZE + 8.0, 0.5, TOWER_SIZE + 8.0), at + Vector3(0, DECK_HEIGHT - 0.25, 0), DARK, yaw)
		_add_marker("landing_deck", at + Vector3(0, DECK_HEIGHT + 0.1, 0) + Basis(Vector3.UP, yaw)
				* Vector3(0, 0, TOWER_SIZE * 0.5 + 2.0))
		# The skybridge to the next tower, deck to deck.
		var next := _at(TOWER_RING, 360.0 * (i + 1.5) / count)
		var span := next - at
		var length := span.length() - TOWER_SIZE - 8.0
		var mid := at + span * 0.5 + Vector3(0, DECK_HEIGHT - 0.25, 0)
		var bridge_yaw := atan2(span.x, span.z)
		_solid(Vector3(4.0, 0.5, length), mid, DARK, bridge_yaw)
		# Glass sides with a light along the handrail and the floor edge.
		for side: float in [-1.0, 1.0]:
			var rail := mid + Basis(Vector3.UP, bridge_yaw) * Vector3(side * 1.95, 0.8, 0)
			_solid(Vector3(0.08, 1.1, length), rail, _glass(), bridge_yaw)
			_part(self, Vector3(0.14, 0.08, length), rail + Vector3(0, 0.58, 0), CYAN, true, bridge_yaw)
			_part(self, Vector3(0.1, 0.05, length), rail + Vector3(-side * 0.1, -0.52, 0), CYAN.darkened(0.3), true,
					bridge_yaw)
		_bridge_truss(mid, length, bridge_yaw)
		_deck_brackets(at, yaw)


## The girder under a skybridge (Caleb's feedback: they floated like
## paper): a deep spine, a bottom chord each side and lit webbing between,
## so the span reads as built. Scenery only: walking is on the deck above.
func _bridge_truss(mid: Vector3, length: float, yaw: float) -> void:
	var turn := Basis(Vector3.UP, yaw)
	var depth := 3.2
	var top := -0.4
	var bottom := top - depth
	_solid(Vector3(2.2, 1.0, length), mid + Vector3(0, top - 0.5, 0), STEEL, yaw, false)
	var bays := maxi(int(length / 6.0), 2)
	var step := length / bays
	for side: float in [-1.0, 1.0]:
		var x := side * 1.75
		_solid(Vector3(0.35, 0.45, length), mid + turn * Vector3(x, bottom, 0), STEEL, yaw, false)
		_part(self, Vector3(0.12, 0.12, length), mid + turn * Vector3(x * 1.08, bottom - 0.25, 0), CYAN.darkened(0.2),
				true, yaw)
		for k in bays:
			var z0 := -length * 0.5 + k * step
			var z1 := z0 + step
			var upper := mid + turn * Vector3(x, top, z0)
			var lower := mid + turn * Vector3(x, bottom, z1 if k % 2 == 0 else z0)
			_strut(upper if k % 2 == 0 else mid + turn * Vector3(x, top, z1), lower, 0.22, STEEL)
			_strut(mid + turn * Vector3(x, top, z1), mid + turn * Vector3(x, bottom, z1), 0.2, STEEL)


## Struts under a tower's landing deck, from its corners back to the tower.
func _deck_brackets(at: Vector3, yaw: float) -> void:
	var turn := Basis(Vector3.UP, yaw)
	var half := TOWER_SIZE * 0.5 + 4.0
	for cx: float in [-1.0, 1.0]:
		for cz: float in [-1.0, 1.0]:
			var corner := at + turn * Vector3(cx * (half - 0.6), DECK_HEIGHT - 0.6, cz * (half - 0.6))
			var root := at + turn * Vector3(cx * TOWER_SIZE * 0.45, DECK_HEIGHT - 7.0, cz * TOWER_SIZE * 0.45)
			_strut(corner, root, 0.5, STEEL)
	# A lit edge round the deck's underside, so its outline reads from below.
	for i in 4:
		var side := turn * Basis(Vector3.UP, TAU * i / 4.0)
		_part(self, Vector3(half * 2.0, 0.1, 0.12), at + side * Vector3(0, DECK_HEIGHT - 0.56, half - 0.1), CYAN.darkened(0.3),
				true, yaw + TAU * i / 4.0)


## A bar from `a` to `b`, `thick` square, drawn with the solid parts but
## never collided with.
func _strut(a: Vector3, b: Vector3, thick: float, material: Material) -> void:
	var along := b - a
	var length := along.length()
	if length < 0.01:
		return
	var z := along / length
	var up := Vector3.UP if absf(z.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var x := up.cross(z).normalized()
	var y := z.cross(x)
	if not _solid_parts.has(material):
		_solid_parts[material] = []
	(_solid_parts[material] as Array).append([Vector3(thick, thick, length),
			Transform3D(Basis(x, y, z), (a + b) * 0.5)])


## One arch per raid world along the gate terrace, north of the spire, with
## the spare arches sealed for worlds to come. You walk into an arch to go:
## its light comes up while you stand in it (the portal's "Lit" child, shown
## by `PlazaView`). Each open arch carries only what reads from across the
## plaza: its world's name, how risky it is (`gate_stakes`) and, from the
## server, how it is doing (`PlazaView.heat_signs`); the full write-up is on
## a console beside it. Where `Look` draws, the doorway shows a glimpse of
## the world, a sealed one a hologram, and the panels either side of an arch
## show how full its world is (`gate_bays`, driven by `PlazaView`).
func _build_gates() -> void:
	var worlds := Worlds.raid_worlds()
	var arches := maxi(GATE_ARCHES, worlds.size())
	var orange := Color(1.0, 0.55, 0.25)
	# The terrace: a wide paved apron with a back wall the arches stand in.
	var wall_width := arches * GATE_SPACING + 16.0
	_slab(Vector3(wall_width + 20.0, 0.04, 30.0), Vector3(0, 0, -GATE_LINE + 8.0), PAVING, 0.0)
	_slab(Vector3(wall_width + 20.0, 0.06, 0.4), Vector3(0, 0, -GATE_LINE + 23.0), _glow(orange), 0.0)
	_solid(Vector3(wall_width, 14.0, 4.0), Vector3(0, 7.0, -GATE_LINE - 3.4), WALL)
	_add_seams(Vector3(0, 7.0, -GATE_LINE - 3.4), Vector3(wall_width, 14.0, 4.0), 0.0, orange, 14.0)
	# A lit cornice and the terrace's name over the whole wall.
	_solid(Vector3(wall_width + 2.0, 1.2, 6.0), Vector3(0, 14.6, -GATE_LINE - 2.4), DARK)
	_part(self, Vector3(wall_width + 2.0, 0.2, 0.1), Vector3(0, 14.4, -GATE_LINE + 0.62), orange, true)
	_sign("DEPLOY", Vector3(0, 17.2, -GATE_LINE - 2.0), 0.0, 3.0, Color(1.0, 0.65, 0.35))
	# Fins between the arches, lit down their edges: each trim its own strip,
	# so a pulse can run up the two beside a gate someone steps into.
	var fins := Node3D.new()
	fins.name = "GateFins"
	add_child(fins)
	var trims: Array[MeshInstance3D] = []
	for i in arches + 1:
		var x := (float(i) - float(arches) * 0.5) * GATE_SPACING
		_solid(Vector3(1.2, 14.0, 3.0), Vector3(x, 7.0, -GATE_LINE - 0.4), WALL)
		_part(fins, Vector3(0.12, 13.6, 0.1), Vector3(x, 7.0, -GATE_LINE + 1.15), orange, true)
		trims.append(fins.get_child(fins.get_child_count() - 1) as MeshInstance3D)
	_gate_bays.clear()
	for i in arches:
		var at := Vector3((float(i) - float(arches - 1) * 0.5) * GATE_SPACING, 0, -GATE_LINE)
		var open := i < worlds.size()
		# Each open gate glows in its own world's colour (`Look.gate_color`,
		# from its planet), so the worlds read apart from across the plaza.
		var color := Look.gate_color(worlds[i].planet_type()) if open else Color(0.4, 0.42, 0.5)
		var bay := {"at": at, "color": color, "world_id": "", "portal": null, "max_players": 0,
				"fins": [trims[i], trims[i + 1]], "glimpse": null, "meters": []}
		_gate_bays.append(bay)
		_build_gate_frame(at, color)
		if not open:
			_build_sealed_doors(at, color)
			continue
		var world := worlds[i]
		var portal := _add_portal("world:%s" % world.id, "Deploy to %s" % world.display_name,
				at + Vector3(0, 0, 1.6), 3.2)
		portal.set_meta("world_id", world.id)
		bay["world_id"] = world.id
		bay["portal"] = portal
		bay["max_players"] = world.max_players
		# The arch's light: a faint sheet always, bright while you stand in it.
		_part(self, Vector3(8.2, 11.8, 0.04), at + Vector3(0, 5.95, -0.2), color.darkened(0.92), true)
		var lit := Node3D.new()
		lit.name = "Lit"
		lit.visible = false
		portal.add_child(lit)
		_part(lit, Vector3(8.2, 11.8, 0.04), Vector3(0, 5.95, -1.7), Color(color, 1.0).darkened(0.62), true)
		lit.get_child(lit.get_child_count() - 1).name = "Sheet"
		_part(lit, Vector3(8.4, 0.08, 1.2), Vector3(0, 0.04, -1.1), color, true)
		_gates.append({"at": at, "yaw": 0.0, "world": world})
		_sign(world.display_name.to_upper(), at + Vector3(0, 12.8, 1.25), 0.0, 1.1, color)
		var stakes := gate_stakes(world)
		_sign(str(stakes[0]), at + Vector3(0, 11.05, 0.4), 0.0, 0.44, stakes[1])
		_build_gate_console(world, at + Vector3(7.6, 0, 4.4), stakes)

	# The dispatcher's desk at the terrace's west end.
	var desk: Vector3 = TALKERS["marlo"][0]
	_solid(Vector3(2.6, 1.05, 0.9), desk + Basis(Vector3.UP, float(TALKERS["marlo"][1])) * Vector3(0, 0.525, -0.9),
			DARK, float(TALKERS["marlo"][1]))


## An arch's frame: the pillars and lintel, and in front of them a
## stepped surround (flanges either side and a crown over the top, standing
## proud of the wall) so the gate reads as a way through, not a hole in the
## wall, with lit edges in the gate's colour and a lit threshold to step on.
func _build_gate_frame(at: Vector3, color: Color) -> void:
	_solid(Vector3(1.6, 12.0, 2.4), at + Vector3(-5.0, 6.0, 0), STEEL)
	_solid(Vector3(1.6, 12.0, 2.4), at + Vector3(5.0, 6.0, 0), STEEL)
	_solid(Vector3(11.6, 1.6, 2.4), at + Vector3(0, 12.8, 0), DARK)
	_part(self, Vector3(8.4, 0.12, 0.12), at + Vector3(0, 11.95, 1.25), color, true)
	for side: float in [-1.0, 1.0]:
		_part(self, Vector3(0.12, 11.9, 0.12), at + Vector3(side * 4.15, 5.95, 1.25), color, true)
		# The flange: a second, deeper step outside the pillar, lit down
		# its inner front edge, with a plinth at its foot.
		_solid(Vector3(0.9, 13.2, 1.2), at + Vector3(side * 6.25, 6.6, 1.6), DARK)
		_part(self, Vector3(0.1, 13.0, 0.1), at + Vector3(side * 5.82, 6.6, 2.22), color, true)
		_solid(Vector3(1.3, 1.0, 1.6), at + Vector3(side * 6.25, 0.5, 1.7), STEEL)
	# The crown over the lintel, tying the flanges together.
	_solid(Vector3(13.4, 0.9, 1.2), at + Vector3(0, 13.65, 1.6), DARK)
	_part(self, Vector3(11.7, 0.1, 0.1), at + Vector3(0, 13.22, 2.22), color, true)
	# The threshold: a plate on the floor you step onto, edged in light.
	_slab(Vector3(9.4, 0.05, 3.2), at + Vector3(0, 0.025, 1.7), STEEL, 0.0)
	_slab(Vector3(9.4, 0.07, 0.14), at + Vector3(0, 0.035, 3.3), _glow(color), 0.0)


## A sealed arch: a shutter behind blast doors, barred across with two
## clamped beams, and the word that it is sealed.
func _build_sealed_doors(at: Vector3, color: Color) -> void:
	_solid(Vector3(8.4, 12.0, 0.6), at + Vector3(0, 6.0, 0), DARK)
	# The blast doors' meeting seam down the middle.
	_part(self, Vector3(0.08, 11.6, 0.05), at + Vector3(0, 6.0, 0.36), color.lightened(0.2), true)
	for y: float in [2.6, 11.0]:
		_solid(Vector3(10.0, 1.0, 0.6), at + Vector3(0, y, 0.95), STEEL)
		for stripe in 7:
			_part(self, Vector3(0.5, 0.8, 0.04), at + Vector3(-4.2 + stripe * 1.4, y, 1.27),
					Color(0.95, 0.65, 0.12), true, 0.0)
		for side: float in [-1.0, 1.0]:
			_solid(Vector3(0.9, 1.5, 0.9), at + Vector3(side * 4.9, y, 1.0), DARK)
	_sign("SEALED", at + Vector3(0, 10.2, 0.4), 0.0, 0.9, color.lightened(0.3))
	_sign("A NEW FRONT OPENS HERE SOON", at + Vector3(0, 9.35, 0.4), 0.0, 0.32, color.lightened(0.45))


## What a gate says about its world's risk, short enough to read from
## across the plaza: [text, colour]. Read from the world's rules, so a new
## world's gate says the right thing with no line here: who you fight
## (`players_allied`, `weapons_free`) and what a death costs
## (`keep_gear_on_death`, `gear_at_risk`, `death_drops_scrip`). Red for high risk, amber for medium, blue for low.
static func gate_stakes(world: WorldDef) -> Array:
	if not world.weapons_free:
		return ["NO RISK  ·  NOBODY FIGHTS", Color(0.55, 0.95, 0.75)]
	var keeps := world.keep_gear_on_death or not world.gear_at_risk
	var fight := "CO-OP" if world.players_allied else "PVP"
	var loss := "KEEP GEAR" if keeps else ("LOSE YOUR KIT" if world.death_drops_scrip else "FULL LOOT")
	var risk := 1
	if not world.players_allied:
		risk += 1
	if not keeps:
		risk += 1
	var words: Array[String] = ["", "LOW RISK", "MEDIUM RISK", "HIGH RISK"]
	var colors: Array[Color] = [Color.WHITE, Color(0.45, 0.85, 1.0), Color(1.0, 0.8, 0.3), Color(1.0, 0.38, 0.25)]
	return ["%s  ·  %s  ·  %s" % [words[risk], fight, loss], colors[risk]]


## A gate's console: a lectern beside the arch whose screen carries the
## world's full write-up, close enough to read when you walk up to it and
## not drawn from across the plaza.
func _build_gate_console(world: WorldDef, at: Vector3, stakes: Array) -> void:
	var tilt := deg_to_rad(-35.0)
	_solid(Vector3(1.5, 1.0, 0.5), at + Vector3(0, 0.5, 0), DARK)
	var head := Node3D.new()
	head.name = "GateConsole_%s" % world.id
	head.position = at + Vector3(0, 1.12, 0.05)
	head.rotation.x = tilt
	add_child(head)
	head.add_to_group("gate_console")
	head.set_meta("world_id", world.id)
	_part(head, Vector3(1.6, 1.0, 0.06), Vector3.ZERO, DARK_GLASS)
	_part(head, Vector3(1.6, 0.04, 0.07), Vector3(0, 0.5, 0), stakes[1], true)
	var text := Label3D.new()
	text.name = "Screen"
	text.text = "%s\n%s\n\n%s" % [world.display_name.to_upper(), stakes[0], world.description]
	text.pixel_size = 0.0022
	text.font_size = 36
	text.outline_size = 0
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.width = 1.42 / text.pixel_size
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	text.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	# A wrapped Label3D's block starts at its position, so it starts at the
	# screen's left edge.
	text.position = Vector3(-0.71, 0.44, 0.04)
	text.modulate = Color(0.92, 0.95, 1.0)
	text.visibility_range_end = 16.0
	text.visibility_range_end_margin = 3.0
	text.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	head.add_child(text)


## The arches of the gate terrace, left to right: {at, color, world_id ("" for
## a sealed one), portal, max_players, fins (the lit trims either side),
## glimpse (the doorway's view, or null), meters (its two panels, or none)}.
## The glimpse and meters exist only where `Look` draws.
func gate_bays() -> Array[Dictionary]:
	return _gate_bays


## The gates come alive: each open doorway shows its world (from the
## world's planet), each sealed one a hologram, and the dark wall either side
## of every arch carries a slatted panel that `PlazaView` fills with how many
## are in that world and pulses when someone steps through.
func _dress_gates(art: Node3D) -> void:
	var fin_color := Color(1.0, 0.55, 0.25)
	var dressed := {}
	for i in _gate_bays.size():
		var bay: Dictionary = _gate_bays[i]
		var at: Vector3 = bay["at"]
		var color: Color = bay["color"]
		for fin: MeshInstance3D in bay["fins"]:
			if not dressed.has(fin):
				Look.gate_trim(fin, fin_color, 13.6)
				dressed[fin] = true
		var portal: Node3D = bay["portal"]
		var meters: Array = []
		if portal != null:
			var world := Worlds.get_world(str(bay["world_id"]))
			var glimpse := Look.gate_window(world.planet_type() if world != null else null,
					Vector2(8.2, 11.8), color, float(i) * 3.7)
			glimpse.position = Vector3(0, 5.95, -1.74)
			portal.add_child(glimpse)
			bay["glimpse"] = glimpse
			# The greybox's lit sheet would stand in front of the glimpse
			# while you are in the gate: the glimpse brightens instead.
			var sheet := portal.get_node_or_null("Lit/Sheet")
			if sheet != null:
				sheet.free()
			# The world's crest on each pillar, under the lintel.
			var crest := Look.gate_crest(world.planet_type() if world != null else null, 1.55, color)
			for side: float in [-1.0, 1.0]:
				# The second shares the first's material.
				var one: Node3D = crest if side < 0.0 else crest.duplicate()
				one.position = at + Vector3(side * 5.0, 10.2, 1.22)
				art.add_child(one)
		else:
			var teaser := Look.gate_teaser(Vector2(8.4, 12.0), Color(0.45, 0.8, 1.0))
			teaser.position = at + Vector3(0, 6.0, 0.32)
			art.add_child(teaser)
		var slats := clampi(int(bay["max_players"]), 8, 24) if portal != null else 16
		for side: float in [-1.0, 1.0]:
			var meter := Look.gate_meter(Vector2(3.0, 10.5), color, slats)
			meter.position = at + Vector3(side * 8.1, 6.4, -1.37)
			art.add_child(meter)
			if portal == null:
				meter.set_instance_shader_parameter("idle", 1.0)
			meters.append(meter)
		bay["meters"] = meters


## The shops this game has: [{id, name, blurb}, ...], or none.
static func shops() -> Array:
	if not ResourceLoader.exists(SHOP_DB):
		return []
	var listed: Variant = (load(SHOP_DB) as Script).get_script_constant_map().get("SHOPS", [])
	return listed if typeof(listed) == TYPE_ARRAY else []


## Market Row: a covered street of shopfronts by trade, south of the spire.
## The next free front after the shops is the Exchange, the player market
## (`MarketService`, DESIGN.md section 10).
func _build_market_row() -> void:
	var length := ROW_TO - ROW_FROM
	var middle := (ROW_FROM + ROW_TO) * 0.5
	_slab(Vector3(STREET_HALF * 2.0, 0.03, length), Vector3(0, 0, middle), PAVING, 0.0)
	_slab(Vector3(0.3, 0.05, length), Vector3(0, 0, middle), _glow(CYAN.darkened(0.3)), 0.0)
	for x: float in [-STREET_HALF + 0.4, STREET_HALF - 0.4]:
		_slab(Vector3(0.12, 0.05, length), Vector3(x, 0, middle), _glow(CYAN.darkened(0.6)), 0.0)
	# The gateway at the plaza end, the street's name over it.
	var arch_z := ROW_FROM + 0.5
	for side: float in [-1.0, 1.0]:
		_solid(Vector3(1.2, 10.0, 1.2), Vector3(side * (STREET_HALF + 0.6), 5.0, arch_z), STEEL)
	_solid(Vector3(STREET_HALF * 2.0 + 2.4, 1.4, 1.2), Vector3(0, 10.4, arch_z), DARK)
	_part(self, Vector3(STREET_HALF * 2.0 + 2.4, 0.1, 0.1), Vector3(0, 9.65, arch_z - 0.62), MAGENTA, true)
	_sign("MARKET ROW", Vector3(0, 10.45, arch_z - 0.62), PI, 1.0, Color(0.95, 0.85, 1.0))
	# A glass canopy on ribs over the street, posts at the alleys.
	var canopy := length - 2.0
	_part(self, Vector3(STREET_HALF * 2.0 + 1.0, 0.1, canopy), Vector3(0, 9.6, middle), Color(0.35, 0.5, 0.7))
	var z := ROW_FROM + 2.0
	while z <= ROW_TO - 1.0:
		_part(self, Vector3(STREET_HALF * 2.0 + 1.4, 0.3, 0.3), Vector3(0, 9.45, z), Color(0.3, 0.33, 0.4))
		SolidProp.box(nav_region, Vector3(STREET_HALF * 2.0 + 1.4, 0.3, 0.3), Transform3D(Basis.IDENTITY, Vector3(0, 9.45, z)))
		z += 6.0
	for post_z: float in [92.0, 116.0, ROW_TO - 1.0]:
		for side: float in [-1.0, 1.0]:
			_solid(Vector3(0.3, 9.4, 0.3), Vector3(side * (STREET_HALF + 0.3), 4.7, post_z), STEEL)
	# Down the middle, between the fronts: benches and planters, and lamps
	# hung from the canopy. Shoppers cross only in front of a door.
	for bench_z: float in [92.0, 116.0]:
		_solid(Vector3(1.0, 0.45, 3.2), Vector3(0, 0.225, bench_z), STEEL)
	for pot_z: float in [68.0, ROW_TO - 4.0]:
		_planter(Vector3(0, 0, pot_z), 0.0, Color(0.35, 1.0, 0.75))
	for lamp_z: float in [74.0, 98.0, 122.0, 140.0]:
		_part(self, Vector3(0.05, 1.3, 0.05), Vector3(0, 8.95, lamp_z), Color(0.3, 0.33, 0.4))
		_part(self, Vector3(1.4, 0.1, 0.45), Vector3(0, 8.3, lamp_z), WARM, true)
		_lamps.append(Vector3(0, 7.8, lamp_z))
	var listed := shops().filter(func(entry: Dictionary) -> bool: return not entry.get("stall", false))
	# Held back at launch (`LaunchScope`): the Exchange's shutter stays down.
	listed.append(EXCHANGE.merged({"shuttered": LaunchScope.holds("market")}))
	for entry: Dictionary in shops():
		if entry.get("stall", false):
			_build_stall(entry, STALL_AT, PI / 2.0)
	for i in mini(listed.size(), ROW_SLOTS.size()):
		var slot: Array = ROW_SLOTS[i]
		var side: float = slot[0]
		var at := Vector3(side * STREET_HALF, 0, float(slot[1]))
		# West side faces east (+X), east side faces west.
		var yaw := PI / 2.0 if side < 0.0 else -PI / 2.0
		_build_shop(listed[i], at, yaw)


## One shopfront: a unit with display windows either side of its door, its
## name on the fascia and on a blade sign hung over the street, a counter
## inside with its keeper behind it and the till's screen on top, and the
## room fitted out for its trade (`_fit_out`). Local +Z is the street.
func _build_shop(entry: Dictionary, at: Vector3, yaw: float) -> void:
	var id: String = entry.get("id", "")
	var trade: Array = TRADES.get(id, [str(entry.get("blurb", "")).to_upper(), Color(0.8, 0.85, 1.0)])
	var color: Color = trade[1]
	var f := Transform3D(Basis(Vector3.UP, yaw), at)
	var w := SHOP_WIDTH
	var d := SHOP_DEPTH
	var h := SHOP_HEIGHT
	var door := 12.0 if id == "garage" else 3.6
	# The shell, its inside panelled pale.
	_slab(Vector3(w, 0.04, d), f * Vector3(0, 0, -d * 0.5), DARK, yaw)
	_solid(Vector3(w, h + 2.0, 0.4), f * Vector3(0, (h + 2.0) * 0.5, -d), WALL, yaw)
	for s: float in [-1.0, 1.0]:
		_solid(Vector3(0.4, h + 2.0, d), f * Vector3(s * w * 0.5, (h + 2.0) * 0.5, -d * 0.5), WALL, yaw)
		_solid(Vector3(0.05, h, d - 0.5), f * Vector3(s * (w * 0.5 - 0.23), h * 0.5, -d * 0.5), INSIDE, yaw, false)
	_solid(Vector3(w - 0.5, h, 0.05), f * Vector3(0, h * 0.5, -d + 0.23), INSIDE, yaw, false)
	_solid(Vector3(w + 0.4, 0.4, d), f * Vector3(0, h + 2.0, -d * 0.5), WALL, yaw)
	_solid(Vector3(w - 0.5, 0.05, d - 0.5), f * Vector3(0, h - 0.03, -d * 0.5), INSIDE, yaw, false)
	# The fascia over the windows, the shop's name and trade on it.
	_solid(Vector3(w + 0.4, 2.0, 0.5), f * Vector3(0, h + 1.0, 0), DARK, yaw)
	_part(self, Vector3(w + 0.4, 0.06, 0.06), f * Vector3(0, h + 0.02, 0.28), color, true, yaw)
	_sign(str(entry.get("name", "")).to_upper(), f * Vector3(0, h + 1.25, 0.27), yaw, 1.0, color)
	_sign(trade[0], f * Vector3(0, h + 0.5, 0.27), yaw, 0.3, Color(0.88, 0.9, 0.95))
	if entry.get("shuttered", false):
		# Not open yet: a shutter down across the whole front, nobody inside.
		_shutter(f, w, h, yaw)
		_sign("OPENING SOON", f * Vector3(0, h * 0.5, 0.32), yaw, 0.6, color)
		return
	# Display windows either side of the door (a garage is one wide bay with
	# its shutter rolled up instead).
	var span := (w - door) * 0.5
	for s: float in [-1.0, 1.0]:
		var mid := s * (door * 0.5 + span * 0.5)
		if id == "garage":
			_solid(Vector3(span, h, 0.5), f * Vector3(mid, h * 0.5, 0), DARK, yaw)
		else:
			_solid(Vector3(span, h - 0.5, 0.06), f * Vector3(mid, (h + 0.5) * 0.5, 0), _glass(), yaw)
			_solid(Vector3(span, 0.5, 0.3), f * Vector3(mid, 0.25, 0), DARK, yaw)
		_solid(Vector3(0.2, h, 0.3), f * Vector3(s * door * 0.5, h * 0.5, 0), STEEL, yaw)
	if id == "garage":
		_part(self, Vector3(door, 1.4, 0.15), f * Vector3(0, h - 0.7, 0.1), Color(0.45, 0.47, 0.52), false, yaw)
		for k in 6:
			_part(self, Vector3(door, 0.04, 0.05), f * Vector3(0, h - 1.3 + k * 0.22, 0.19), Color(0.2, 0.21, 0.24),
					false, yaw)
		for k in 9:
			_part(self, Vector3(0.5, 0.03, 0.9), f * Vector3(-4.8 + k * 1.2, 0.03, -0.6), color.darkened(0.3), true,
					yaw + 0.6)
	# The blade sign hung out over the street at the front's far corner.
	var across := yaw + PI / 2.0
	var blade := f * Vector3(w * 0.5 - 0.6, h + 0.2, 1.5)
	_part(self, Vector3(0.08, 0.08, 2.0), f * Vector3(w * 0.5 - 0.6, h + 1.0, 1.0), Color(0.3, 0.33, 0.4), false, yaw)
	_part(self, Vector3(1.9, 1.3, 0.06), blade, color.darkened(0.55), true, across)
	for face: float in [0.0, PI]:
		_sign(str(entry.get("name", "")).to_upper(), blade + Basis(Vector3.UP, across + face) * Vector3(0, 0, 0.05),
				across + face, 0.32, Color.WHITE.lerp(color, 0.3))
	# Warm light strips on the ceiling.
	for z: float in [-3.0, -7.5]:
		_part(self, Vector3(w - 4.0, 0.06, 0.4), f * Vector3(0, h - 0.1, z), WARM, true, yaw)
	# Lit like a shop: one light over the floor and one over the counter, so
	# the goods and the keeper's face both read from the street.
	_shop_lights.append([f * Vector3(0, h - 1.4, -d * 0.3), color])
	_shop_lights.append([f * Vector3(0, h - 1.6, -d * 0.72), color])
	# The counter, the till on it facing the customer, the keeper behind it.
	var counter_z := -6.4 if id != "garage" else -7.6
	var counter_w := 6.0 if id != "garage" else 3.6
	var counter_x := 0.0 if id != "garage" else 4.4
	_solid(Vector3(counter_w, 1.0, 0.8), f * Vector3(counter_x, 0.5, counter_z), DARK, yaw)
	_solid(Vector3(counter_w + 0.1, 0.06, 0.9), f * Vector3(counter_x, 1.03, counter_z), STEEL, yaw)
	_part(self, Vector3(counter_w, 0.04, 0.04), f * Vector3(counter_x, 0.08, counter_z + 0.42), color, true, yaw)
	var destination: String = entry.get("destination", "shop:%s" % id)
	var name_text: String = entry.get("name", "shop")
	var portal := _add_portal(destination, "Trade at the %s" % name_text,
			f * Vector3(counter_x, 0, counter_z + 2.0), 2.0)
	if destination.begins_with("shop:"):
		portal.add_to_group("shop_front")
		portal.set_meta("shop_id", id)
	var screen := Node3D.new()
	screen.name = "Screen"
	screen.position = Basis(Vector3.UP, yaw) * Vector3(0.8, 1.72, -1.9)
	screen.basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -0.18)
	portal.add_child(screen)
	_part(screen, Vector3(1.2, 0.72, 0.05), Vector3(0, 0, -0.035), DARK_GLASS)
	# Idle, the till shows a dim face in the shop's colour; the shop's own
	# screen takes it over in use.
	_part(screen, Vector3(1.12, 0.64, 0.01), Vector3.ZERO, color.darkened(0.88), true)
	_part(screen, Vector3(0.12, 0.4, 0.12), Vector3(0, -0.5, -0.06), DARK_GLASS)
	var keeper: Array = KEEPERS.get(id, ["Keeper", "Shopkeeper", ["Have a look round."]])
	var keeper_id := "keep_%s" % id
	portal.set_meta("keeper", keeper_id)
	var keeper_marker := _add_talker(keeper_id, f * Vector3(counter_x - 1.2, 0, counter_z - 1.1), yaw + PI,
			keeper[0], keeper[1], keeper[2], "", color)
	if destination.begins_with("shop:"):
		keeper_marker.set_meta("shop", id)
	_fronts.append({"id": id, "at": at, "yaw": yaw, "color": color,
			"door": f * Vector3(0, 0, 2.4)})
	_fit_out(id, f, color)


## A front's shutter, rolled down across its whole width: one solid sheet
## with its slats. Local +Z is the street, like a front.
func _shutter(f: Transform3D, w: float, h: float, yaw: float) -> void:
	_solid(Vector3(w, h, 0.3), f * Vector3(0, h * 0.5, 0), STEEL, yaw)
	for k in int(h / 0.32):
		_part(self, Vector3(w, 0.04, 0.05), f * Vector3(0, 0.2 + k * 0.32, 0.17), Color(0.2, 0.21, 0.24), false, yaw)


## A stall down an alley (the back room): no front, no windows, a counter
## across the alley's far end under one red lamp, crates either side and the
## fence behind it. Local +Z is the street, like a front.
func _build_stall(entry: Dictionary, at: Vector3, yaw: float) -> void:
	var id: String = entry.get("id", "")
	var trade: Array = TRADES.get(id, ["", Color(1.0, 0.3, 0.25)])
	var color: Color = trade[1]
	var f := Transform3D(Basis(Vector3.UP, yaw), at)
	# Back wall closing the alley, a tarp roof over the counter.
	_solid(Vector3(7.6, 4.0, 0.3), f * Vector3(0, 2.0, -6.2), WALL, yaw)
	_part(self, Vector3(7.4, 0.05, 3.2), f * Vector3(0, 3.2, -4.6), Color(0.14, 0.1, 0.1), false, yaw)
	_solid(Vector3(4.0, 1.0, 0.7), f * Vector3(0, 0.5, -3.6), DARK, yaw)
	_solid(Vector3(4.1, 0.06, 0.8), f * Vector3(0, 1.03, -3.6), STEEL, yaw)
	_part(self, Vector3(4.0, 0.04, 0.04), f * Vector3(0, 0.08, -3.22), color, true, yaw)
	for k in 4:
		var side := -1.0 if k < 2 else 1.0
		_solid(Vector3(0.9, 0.6, 0.7), f * Vector3(side * 2.9, 0.3 + (k % 2) * 0.6, -2.4 - (k % 2) * 0.3), STEEL, yaw)
	# A small sign over the counter, and the one lamp.
	_sign(str(entry.get("name", "")).to_upper(), f * Vector3(0, 2.7, -6.0), yaw, 0.45, color)
	_sign(trade[0], f * Vector3(0, 2.3, -6.0), yaw, 0.22, Color(0.85, 0.8, 0.8))
	_part(self, Vector3(0.5, 0.08, 0.5), f * Vector3(0, 3.1, -4.0), color, true, yaw)
	_shop_lights.append([f * Vector3(0, 2.9, -4.0), color])
	var portal := _add_portal("shop:%s" % id, "Trade at the %s" % entry.get("name", "stall"),
			f * Vector3(0, 0, -1.8), 1.6)
	portal.add_to_group("shop_front")
	portal.set_meta("shop_id", id)
	var keeper: Array = KEEPERS.get(id, ["Keeper", "Shopkeeper", ["Have a look round."]])
	var keeper_id := "keep_%s" % id
	portal.set_meta("keeper", keeper_id)
	var keeper_marker := _add_talker(keeper_id, f * Vector3(-0.8, 0, -4.7), yaw + PI,
			keeper[0], keeper[1], keeper[2], "", color)
	keeper_marker.set_meta("shop", id)


## What a shop shows of its trade: real gear on show (any node with the meta
## `display_item` is dressed by `Look`), shelves and fittings.
func _fit_out(id: String, f: Transform3D, color: Color) -> void:
	var yaw := f.basis.get_euler().y
	var d := SHOP_DEPTH
	match id:
		"armory":
			# The gun wall behind the counter: three lit rows.
			_part(self, Vector3(10.0, 3.6, 0.1), f * Vector3(0, 2.7, -d + 0.3), Color(0.08, 0.08, 0.1), false, yaw)
			var guns := ["rifle_carbine", "smg_stinger", "dmr_longshot", "shotgun_breacher", "rifle_scrap", "pistol_machine"]
			for row in 3:
				var y := 1.5 + row * 1.0
				_part(self, Vector3(9.6, 0.04, 0.14), f * Vector3(0, y - 0.32, -d + 0.4), color.darkened(0.3), true, yaw)
				for k in 4:
					_display(guns[(row * 4 + k) % guns.size()], f * Vector3(-3.6 + k * 2.4, y, -d + 0.48), yaw,
							Basis(Vector3.UP, PI / 2.0))
			# Blades along one wall, points up.
			var blades := ["knife_gutter", "axe_splitter", "hammer_breaker", "spear_lancer"]
			for k in blades.size():
				_display(blades[k], f * Vector3(-SHOP_WIDTH * 0.5 + 0.45, 2.4, -2.0 - k * 1.6), yaw + PI / 2.0,
						Basis(Vector3.RIGHT, -PI / 2.0))
			# Ammo crates stacked on the other side.
			for k in 5:
				_solid(Vector3(0.9, 0.5, 0.6), f * Vector3(6.6, 0.25 + (k % 3) * 0.5, -2.4 - (k / 3) * 1.2), STEEL, yaw)
			# A gun on a stand in each window.
			for s: float in [-1.0, 1.0]:
				_solid(Vector3(3.4, 0.8, 1.0), f * Vector3(s * 4.9, 0.4, -0.9), DARK, yaw)
				_display("rifle_carbine" if s < 0.0 else "smg_stinger", f * Vector3(s * 4.9, 1.2, -0.9), yaw,
						Basis(Vector3.UP, PI / 2.0), 1.3)
		"outfitter":
			# Rigs on stands along the back, more in the windows.
			var rigs := ["jetpack_mk1", "boots_thruster", "wings_glide"]
			for k in rigs.size():
				_display(rigs[k], f * Vector3(-4.0 + k * 4.0, 0.05, -d + 1.4), yaw)
			for s: float in [-1.0, 1.0]:
				_solid(Vector3(3.4, 0.5, 1.4), f * Vector3(s * 4.9, 0.25, -1.1), DARK, yaw)
				_display("jetpack_mk1" if s < 0.0 else "wings_glide", f * Vector3(s * 4.9, 0.5, -1.1), yaw)
			# Medical shelves on the side wall.
			for k in 4:
				_solid(Vector3(0.5, 0.05, 3.0), f * Vector3(7.3, 0.9 + k * 0.55, -4.6), STEEL, yaw)
				for j in 4:
					_part(self, Vector3(0.22, 0.28, 0.16), f * Vector3(7.3, 1.07 + k * 0.55, -5.8 + j * 0.8),
							Color(0.9, 0.95, 1.0).lerp(color, 0.3), true, yaw)
		"garage":
			# A bike on show in the bay, a lift and the tool wall.
			_display_vehicle("bike_scrapper", f * Vector3(-2.6, 0, -4.6), yaw + 2.3)
			_solid(Vector3(2.4, 0.2, 4.0), f * Vector3(-3.0, 0.6, -8.6), STEEL, yaw + PI / 2.0)
			for x: float in [-4.0, -2.0]:
				_solid(Vector3(0.2, 0.6, 0.2), f * Vector3(x, 0.3, -8.6), DARK, yaw)
			_part(self, Vector3(5.0, 2.4, 0.1), f * Vector3(3.5, 2.2, -d + 0.3), Color(0.12, 0.12, 0.14), false, yaw)
			for k in 8:
				_part(self, Vector3(0.08, 0.5, 0.05), f * Vector3(1.6 + k * 0.5, 2.4 + (k % 2) * 0.4, -d + 0.38),
						Color(0.6, 0.62, 0.68), false, yaw)
			# Hazard stripes along the bay's edge.
			for k in 6:
				_part(self, Vector3(0.6, 0.03, 0.3), f * Vector3(-5.0 + k * 1.6, 0.03, -d + 1.0), color.darkened(0.2),
						true, yaw)
		"furnisher":
			# A room set out in each window and one on the floor.
			for s: float in [-1.0, 1.0]:
				_solid(Vector3(2.4, 0.45, 0.9), f * Vector3(s * 4.9, 0.22, -1.2), STEEL, yaw)
				_solid(Vector3(2.4, 0.5, 0.25), f * Vector3(s * 4.9, 0.7, -1.55), STEEL, yaw)
				_part(self, Vector3(0.1, 1.6, 0.1), f * Vector3(s * 6.6, 0.8, -1.2), Color(0.3, 0.3, 0.33), false, yaw)
				_part(self, Vector3(0.5, 0.3, 0.5), f * Vector3(s * 6.6, 1.7, -1.2), WARM, true, yaw)
				SolidProp.box(nav_region, Vector3(0.3, 1.85, 0.3), Transform3D(Basis(Vector3.UP, yaw), f * Vector3(s * 6.6, 0.93, -1.2)))
			_solid(Vector3(1.6, 0.5, 1.0), f * Vector3(-4.0, 0.25, -8.6), DARK, yaw)
			_solid(Vector3(1.0, 0.8, 1.0), f * Vector3(4.0, 0.4, -8.6), STEEL, yaw)
			_part(self, Vector3(3.0, 1.8, 0.05), f * Vector3(4.0, 2.4, -d + 0.3), color.darkened(0.6), true, yaw)
		"tailor":
			# Mannequins in the windows and along the back, a rail of clothes
			# and a long mirror.
			for s: float in [-1.0, 1.0]:
				_mannequin(f * Vector3(s * 4.9, 0, -1.2), yaw, color)
			for k in 3:
				_mannequin(f * Vector3(-4.0 + k * 4.0, 0, -d + 1.0), yaw, Color(0.6, 0.7, 0.9).lerp(color, k * 0.4))
			_solid(Vector3(0.06, 0.06, 3.6), f * Vector3(-6.9, 1.9, -5.0), STEEL, yaw)
			for k in 7:
				_part(self, Vector3(0.5, 0.9, 0.06), f * Vector3(-6.9, 1.4, -6.6 + k * 0.5),
						Color.from_hsv(fposmod(0.1 * k + 0.5, 1.0), 0.45, 0.7), false, yaw + PI / 2.0)
			_part(self, Vector3(0.05, 2.4, 1.6), f * Vector3(7.5, 1.5, -5.0), Color(0.7, 0.8, 0.9), true, yaw)
		"exchange":
			# The trading floor: lit listing boards and two desks.
			_part(self, Vector3(10.0, 3.0, 0.05), f * Vector3(0, 3.2, -d + 0.3), color.darkened(0.75), true, yaw)
			for row in 6:
				_part(self, Vector3(9.0, 0.05, 0.02), f * Vector3(0, 2.0 + row * 0.45, -d + 0.34), color.darkened(0.3),
						true, yaw)
			for s: float in [-1.0, 1.0]:
				_solid(Vector3(2.0, 0.9, 1.0), f * Vector3(s * 4.9, 0.45, -1.4), DARK, yaw)
				_part(self, Vector3(0.9, 0.55, 0.04), f * Vector3(s * 4.9, 1.25, -1.6), color.darkened(0.5), true, yaw)


## A dressmaker's dummy on a stand: a plain figure in `color`, as solid as
## a person.
func _mannequin(at: Vector3, yaw: float, color: Color) -> void:
	_solid(Vector3(0.8, 0.2, 0.8), at + Vector3(0, 0.1, 0), DARK, yaw)
	SolidProp.box(nav_region, Vector3(0.46, 1.9, 0.3), Transform3D(Basis(Vector3.UP, yaw), at + Vector3(0, 1.15, 0)))
	_part(self, Vector3(0.06, 0.9, 0.06), at + Vector3(0, 0.65, 0), Color(0.3, 0.3, 0.33), false, yaw)
	_part(self, Vector3(0.46, 0.66, 0.26), at + Vector3(0, 1.43, 0), color, false, yaw)
	_part(self, Vector3(0.36, 0.5, 0.22), at + Vector3(0, 0.88, 0), color.darkened(0.35), false, yaw)
	_part(self, Vector3(0.2, 0.24, 0.2), at + Vector3(0, 1.9, 0), Color(0.75, 0.75, 0.78), false, yaw)


## Gear on show: a greybox stand-in `Look` swaps for the item's real model
## (`Look._dress_display`). Only where the game is drawn.
func _display(id: String, at: Vector3, yaw: float, turn := Basis.IDENTITY, size := 1.0) -> void:
	if not Look.enabled or not ItemDB.has_item(id):
		return
	var display := Node3D.new()
	display.set_meta("display_item", id)
	display.transform = Transform3D(Basis(Vector3.UP, yaw), at)
	var model := Node3D.new()
	model.name = "Model"
	var grey := Node3D.new()
	grey.transform = Transform3D(turn.scaled(Vector3.ONE * size), Vector3.ZERO)
	model.add_child(grey)
	display.add_child(model)
	add_child(display)


## A vehicle on show: its own greybox body, painted by `Look`. Only where
## the game is drawn.
func _display_vehicle(id: String, at: Vector3, yaw: float) -> void:
	if not ItemDB.has_item(id):
		return
	var vehicle: Node3D = VehicleScript.new()
	vehicle.setup(id)
	# Solid on the server too: the same box the machine rides on.
	var size: Vector3 = vehicle.get("body_size")
	SolidProp.box(nav_region, size, Transform3D(Basis(Vector3.UP, yaw), at + Vector3(0, size.y * 0.5, 0)))
	if not Look.enabled:
		vehicle.free()
		return
	var visual: Node3D = vehicle.build_visual()
	vehicle.free()
	var display := Node3D.new()
	display.set_meta("display_item", id)
	display.transform = Transform3D(Basis(Vector3.UP, yaw), at)
	var model := Node3D.new()
	model.name = "Model"
	model.add_child(visual)
	display.add_child(model)
	add_child(display)


## At the far end of Market Row: the transit hall, the way off the server.
func _build_transit() -> void:
	var at := TRANSIT_AT
	_solid(Vector3(24, 9, 6), at + Vector3(0, 4.5, 7.0), WALL)
	_add_seams(at + Vector3(0, 4.5, 7.0), Vector3(24, 9, 6), 0.0, Color(1.0, 0.55, 0.5), 3.0)
	_solid(Vector3(7, 6, 0.6), at + Vector3(0, 3, 3.9), DARK)
	_part(self, Vector3(5.6, 4.8, 0.05), at + Vector3(0, 2.6, 3.55), Color(1.0, 0.5, 0.45).darkened(0.7), true)
	_add_portal("leave", "Leave the server", at, 2.6)
	_sign("TRANSIT", at + Vector3(0, 7.0, 3.95), PI, 1.1, Color(1.0, 0.55, 0.5))


## East: the civic square. The clan hall on its far side, the big screen on
## its north side over tiers of seats, the contract and most-wanted boards on
## its south side.
func _build_civic_square() -> void:
	_slab(Vector3(CIVIC_SIZE.x, 0.03, CIVIC_SIZE.y), CIVIC, PAVING, 0.0)
	_slab_square(CIVIC, CIVIC_SIZE.y - 2.0, 0.0, Color(0.85, 0.6, 1.0).darkened(0.4))
	_build_clan_hall()
	_build_screen()
	_build_contract_board()
	_build_wanted_board()
	for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var at := CIVIC + Vector3(corner.x * 24.0, 0, corner.y * 18.0)
		_planter(at, 0.0, Color(0.85, 0.6, 1.0))
	for z: float in [-12.0, 12.0]:
		_solid(Vector3(4.0, 0.5, 1.0), CIVIC + Vector3(-14.0, 0.25, z), STEEL)
		var lamp := CIVIC + Vector3(-18.0, 0, z)
		_part(self, Vector3(0.18, 4.6, 0.18), lamp + Vector3(0, 2.3, 0), Color(0.25, 0.28, 0.34))
		_part(self, Vector3(0.9, 0.12, 0.9), lamp + Vector3(0, 4.66, 0), Color(0.85, 0.95, 1.0), true)
		_lamps.append(lamp + Vector3(0, 4.3, 0))


func _build_clan_hall() -> void:
	var at := CLAN_HALL_AT
	var purple := Color(0.85, 0.6, 1.0)
	_solid(Vector3(14, 12, 32), at + Vector3(9, 6, 0), WALL)
	_add_seams(at + Vector3(9, 6, 0), Vector3(14, 12, 32), 0.0, purple, 4.0)
	_solid(Vector3(5, 0.5, 14), at + Vector3(0.5, 6.0, 0), DARK)
	for z: float in [-6.5, 6.5]:
		_solid(Vector3(0.8, 6.0, 0.8), at + Vector3(-1.4, 3.0, z), STEEL)
	# Banner plinths either side of the door, for clan colours later.
	for z: float in [-10.0, 10.0]:
		_solid(Vector3(1.6, 1.2, 1.6), at + Vector3(0.0, 0.6, z), DARK)
		_add_marker("clan_banner", at + Vector3(0.0, 1.2, z))
	# The clerk's desk under the canopy, the terminal on it facing the square.
	_solid(Vector3(0.9, 1.05, 3.0), at + Vector3(-0.6, 0.525, 0), DARK)
	_solid(Vector3(1.0, 0.06, 3.1), at + Vector3(-0.6, 1.08, 0), STEEL)
	var portal := _add_portal("clans", "Use the clan hall terminal", at + Vector3(-3.0, 0, 0), 2.2)
	var screen := Node3D.new()
	screen.name = "Screen"
	screen.position = Vector3(2.15, 1.72, 0.6)
	screen.basis = Basis(Vector3.UP, -PI / 2.0) * Basis(Vector3.RIGHT, -0.18)
	portal.add_child(screen)
	_part(screen, Vector3(1.2, 0.72, 0.05), Vector3(0, 0, -0.035), DARK_GLASS)
	_part(screen, Vector3(1.12, 0.64, 0.01), Vector3.ZERO, purple.darkened(0.75), true)
	portal.set_meta("keeper", "clerk")
	_add_talker("clerk", at + Vector3(0.6, 0, -0.6), PI / 2.0, CLERK[0], CLERK[1], CLERK[2], "", purple)
	_sign("CLAN HALL", at + Vector3(1.95, 8.2, 0), -PI / 2.0, 1.2, purple)


## The big screen over tiers of seats, where people gather to watch how the
## worlds are doing: the War Room. What plays on it is `WarRoom`'s (view
## only, on the "screen_wall" node). The console in front of it picks a
## world to see on the screen and deploy to (its "war_room" portal).
func _build_screen() -> void:
	var wall_at := SCREEN_AT
	_solid(Vector3(40, 16, 3), wall_at + Vector3(0, 8, -1.5), WALL)
	_add_seams(wall_at + Vector3(0, 8, -1.5), Vector3(40, 16, 3), 0.0, CYAN, 20.0)
	for side: float in [-1.0, 1.0]:
		var pylon := wall_at + Vector3(side * 21.5, 10.0, -0.5)
		_solid(Vector3(3, 20, 4), pylon, WALL)
		_part(self, Vector3(0.25, 19.0, 0.1), pylon + Vector3(-side * 0.8, 0, 2.05), MAGENTA, true)
	var screen := Node3D.new()
	screen.name = "ScreenWall"
	screen.position = wall_at + Vector3(0, 8.5, 0.1)
	screen.add_to_group("screen_wall")
	add_child(screen)
	# The node faces the seats: its local -Z is toward the wall behind it.
	_part(screen, Vector3(31, 12, 0.08), Vector3(0, 0, -0.06), Color(0.05, 0.06, 0.08))
	_part(screen, Vector3(30, 11, 0.1), Vector3.ZERO, Color(0.04, 0.16, 0.26), true)
	for y: float in [-5.75, 5.75]:
		_part(screen, Vector3(31, 0.2, 0.12), Vector3(0, y, 0.04), CYAN, true)
	for x: float in [-15.5, 15.5]:
		_part(screen, Vector3(0.2, 11.7, 0.12), Vector3(x, 0, 0.04), CYAN, true)
	_sign("WAR ROOM", wall_at + Vector3(0, 15.4, 0.2), 0.0, 1.6, Color(0.6, 0.95, 1.0))
	# The console before the screen, its own screen tipped up to whoever
	# stands at it, facing the wall.
	var desk := wall_at + Vector3(0, 0, 7.0)
	_solid(Vector3(2.6, 1.05, 0.8), desk + Vector3(0, 0.525, 0), DARK)
	_solid(Vector3(2.7, 0.06, 0.9), desk + Vector3(0, 1.08, 0), STEEL)
	_part(self, Vector3(2.7, 0.05, 0.06), desk + Vector3(0, 1.1, 0.45), CYAN, true)
	var portal := _add_portal("war_room", "Use the War Room console", desk + Vector3(0, 0, 2.2), 1.8)
	var console := Node3D.new()
	console.name = "Screen"
	console.set_meta("walk_through", "stands on its desk, out of reach")
	console.position = Vector3(0, 1.62, -2.0)
	console.basis = Basis(Vector3.RIGHT, -0.35)
	portal.add_child(console)
	_part(console, Vector3(1.7, 1.0, 0.06), Vector3(0, 0, -0.04), DARK_GLASS)
	_part(console, Vector3(1.6, 0.9, 0.01), Vector3.ZERO, CYAN.darkened(0.75), true)
	# Tiers facing the screen, low enough to step up, a light along each edge.
	for row in 4:
		var tier := _tier(row)
		var tall := float(tier.centre.y)
		_solid(Vector3(tier.width, tall, tier.depth), Vector3(tier.centre.x, tall * 0.5, tier.centre.z), STEEL)
		_part(self, Vector3(tier.width, 0.06, 0.08), Vector3(tier.centre.x, tall - 0.05, tier.centre.z - 1.32), CYAN, true)


## A row of seats facing the big screen: {centre (y is its top), width, depth}.
func _tier(row: int) -> Dictionary:
	return {"centre": Vector3(SCREEN_AT.x, 0.4 + row * 0.4, SCREEN_AT.z + 14.0 + row * 3.0),
			"width": 30.0 + row * 4.0, "depth": 2.6}


## The contract board, a lit wall listing today's jobs, with a terminal in
## front of it to take them (DESIGN.md section 10). Rook stands beside it.
## Each job is a card of its own in two columns, its title large enough to
## read from across the square (Caleb's screenshot: one block of small text
## could not be read a few steps away), its kind and pay under it.
func _build_contract_board() -> void:
	var at := CONTRACT_BOARD_AT
	var yaw := PI
	var facing := Basis(Vector3.UP, yaw)
	var amber := Color(1.0, 0.75, 0.3)
	# The board grows to fit the day's cards (each world adds jobs of its
	# own): two columns, a card's room `step`, above the terminal's top.
	var rows := contract_rows()
	var per_column := maxi(ceili(rows.size() / 2.0), 1)
	var step := 1.5
	var top := maxf(2.45 + per_column * step, 8.35)
	var tall := top + 2.25
	var wide := 14.0
	_solid(Vector3(wide, tall, 0.8), at + facing * Vector3(0, tall * 0.5, -0.4), WALL, yaw)
	for side: float in [-1.0, 1.0]:
		_part(self, Vector3(0.1, tall, 0.1), at + facing * Vector3(side * (wide * 0.5 + 0.02), tall * 0.5, 0.02), amber, true, yaw)
	# The cards stand above the terminal in front, so it never hides one.
	var panel := tall - 1.35 - 2.25
	_part(self, Vector3(wide - 1.0, panel + 0.1, 0.05), at + facing * Vector3(0, 2.25 + panel * 0.5, 0.02),
			Color(0.06, 0.05, 0.03), true, yaw)
	for y: float in [2.25, tall - 1.35]:
		_part(self, Vector3(wide - 0.8, 0.1, 0.08), at + facing * Vector3(0, y, 0.05), amber, true, yaw)
	_sign("CONTRACTS", at + facing * Vector3(0, tall - 0.65, 0.1), yaw, 1.0, amber)
	_sign(BOARD_NOTE, at + facing * Vector3(0, tall - 1.75, 0.1), yaw, 0.3, Color(1.0, 0.92, 0.8, 0.85))
	for i in rows.size():
		var column := floori(float(i) / per_column)
		var x := -6.2 + column * 6.6
		var y := top - (i % per_column) * step
		# A short amber tick down the card's left edge, the title on top and
		# its kind and pay under it, wrapped like the title where the card
		# has room, else set smaller to stay on one line.
		_part(self, Vector3(0.08, step * 0.75, 0.04), at + facing * Vector3(x - 0.2, y - step * 0.36, 0.06),
				amber, true, yaw)
		var title := str(rows[i].title)
		_sign_left(title, at + facing * Vector3(x, y, 0.1), yaw, 0.42, Color(1.0, 0.95, 0.86), CARD_WIDTH)
		var below := y - card_lines(title, 0.42) * 0.5 - 0.06
		var pay := "%s  ·  %s" % [rows[i].kind, rows[i].reward]
		var size := 0.3
		if (y - below) + card_lines(pay, size) * 0.36 > step - 0.1:
			size = minf(size, CARD_WIDTH / (pay.length() * GLYPH_WIDTH))
		_sign_left(pay, at + facing * Vector3(x, below, 0.1), yaw, size, amber, CARD_WIDTH)
	_build_contract_board_terminal(at, facing, yaw, amber)


## How wide a card's text runs on the contract board, in metres, and how
## wide a glyph is for its size, a little under half.
const CARD_WIDTH := 5.9
const GLYPH_WIDTH := 0.47


## About how many lines `text` takes on a card at glyphs of `size` metres.
static func card_lines(text: String, size: float) -> int:
	return maxi(1, ceili(text.length() * size * GLYPH_WIDTH / CARD_WIDTH))


## The terminal in front of the contract board, its screen facing the square.
func _build_contract_board_terminal(at: Vector3, facing: Basis, yaw: float, amber: Color) -> void:
	_solid(Vector3(1.2, 1.1, 0.6), at + facing * Vector3(0, 0.55, 1.4), STEEL, yaw)
	var portal := _add_portal("contracts", "Use the contract board", at + facing * Vector3(0, 0, 3.4), 2.2)
	var screen := Node3D.new()
	screen.name = "Screen"
	screen.set_meta("walk_through", "hangs over its terminal, out of reach")
	screen.position = facing * Vector3(0, 1.85, -1.95)
	screen.basis = facing * Basis(Vector3.RIGHT, -0.12)
	portal.add_child(screen)
	_part(screen, Vector3(1.7, 1.0, 0.06), Vector3(0, 0, -0.04), DARK_GLASS)
	_part(screen, Vector3(1.6, 0.9, 0.01), Vector3.ZERO, amber.darkened(0.75), true)


## The most-wanted board, a red lit wall listing the top bounties out in the
## worlds. What it says is written by `PlazaView` from the server's news
## (`world_status`'s "wanted"); the map only builds the wall and the label,
## in group "wanted_board".
func _build_wanted_board() -> void:
	var at := WANTED_BOARD_AT
	var yaw := PI
	var facing := Basis(Vector3.UP, yaw)
	var red := Color(1.0, 0.32, 0.26)
	_solid(Vector3(12, 7, 0.8), at + facing * Vector3(0, 3.5, -0.4), WALL, yaw)
	for side: float in [-1.0, 1.0]:
		_part(self, Vector3(0.1, 7.0, 0.1), at + facing * Vector3(side * 6.02, 3.5, 0.02), red, true, yaw)
	_part(self, Vector3(10.5, 4.6, 0.05), at + facing * Vector3(0, 3.6, 0.02), Color(0.07, 0.03, 0.03), true, yaw)
	for y: float in [1.25, 5.95]:
		_part(self, Vector3(10.7, 0.1, 0.08), at + facing * Vector3(0, y, 0.05), red, true, yaw)
	_sign("MOST WANTED", at + facing * Vector3(0, 6.6, 0.1), yaw, 1.0, red)
	var list := Label3D.new()
	list.name = "WantedList"
	list.add_to_group("wanted_board")
	list.text = "No bounties out right now."
	list.font_size = 64
	list.pixel_size = 0.005
	list.outline_size = 0
	list.modulate = Color(1.0, 0.9, 0.86)
	list.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	list.width = 10.0 / list.pixel_size
	list.position = at + facing * Vector3(0, 3.6, 0.1)
	list.rotation.y = yaw
	add_child(list)
	# A low plinth in front, where the broker stands his ground.
	_solid(Vector3(2.4, 0.3, 1.4), at + facing * Vector3(0, 0.15, 1.3), STEEL, yaw)
	_part(self, Vector3(2.5, 0.05, 1.5), at + facing * Vector3(0, 0.02, 1.3), red.darkened(0.4), true, yaw)


## West: the residences. Apartment blocks round a courtyard, and the
## quarters on the far side: the lift down to your home base, which is its
## own space, with the concierge's desk beside it.
func _build_residences() -> void:
	var blue := Color(0.5, 0.85, 1.0)
	_slab(Vector3(72, 0.03, 70), RESIDENCES, PAVING, 0.0)
	var at := QUARTERS_AT
	_solid(Vector3(14, 12, 32), at + Vector3(-9, 6, 0), WALL)
	_add_seams(at + Vector3(-9, 6, 0), Vector3(14, 12, 32), 0.0, blue, 4.0)
	# The lift: a lit door in a steel frame, a canopy over it.
	_solid(Vector3(0.4, 0.4, 9), at + Vector3(-0.6, 5.4, 0), DARK)
	for z: float in [-2.2, 2.2]:
		_solid(Vector3(0.6, 5.0, 0.5), at + Vector3(-1.8, 2.5, z), STEEL)
	_solid(Vector3(0.6, 0.6, 4.9), at + Vector3(-1.8, 5.2, 0), STEEL)
	_part(self, Vector3(0.05, 4.4, 3.8), at + Vector3(-2.08, 2.3, 0), blue.darkened(0.6), true)
	_add_portal("home", "Go to your home base", at + Vector3(3.5, 0, 0), 2.6)
	_sign("QUARTERS", at + Vector3(-1.85, 7.6, 0), PI / 2.0, 1.2, blue)
	# The concierge's desk.
	_solid(Vector3(1.0, 1.05, 2.6), at + Vector3(4.6 - 0.4, 0.525, 6.0), DARK)
	_solid(Vector3(1.1, 0.06, 2.7), at + Vector3(4.6 - 0.4, 1.08, 6.0), STEEL)
	# Apartment blocks either side of the courtyard, the avenue between.
	var blocks := [[Vector3(-136, 0, -26), 30.0], [Vector3(-160, 0, -28), 46.0], [Vector3(-136, 0, 26), 38.0],
			[Vector3(-160, 0, 28), 52.0]]
	for i in blocks.size():
		var base: Vector3 = blocks[i][0]
		var tall: float = blocks[i][1]
		var size := Vector3(13, tall, 12)
		_solid(size, base + Vector3(0, tall * 0.5, 0), WALL)
		_add_seams(base + Vector3(0, tall * 0.5, 0), size, 0.0, [blue, MAGENTA][i % 2], 5.0)
		_part(self, Vector3(3.0, 3.2, 0.06), base + Vector3(0, 1.6, -6.03 if base.z > 0.0 else 6.03),
				WARM.darkened(0.4), true)
	for z: float in [-13.0, 13.0]:
		_planter(RESIDENCES + Vector3(4.0, 0, z), 0.0, blue)
		_solid(Vector3(4.0, 0.5, 1.0), RESIDENCES + Vector3(-8.0, 0.25, z), STEEL)
	_lamps.append(at + Vector3(4.0, 3.4, 0))


## South-east: the gate to the arena, which is built as its own space.
func _build_arena_gate() -> void:
	var at := _at(DISTRICT_RING, ARENA_BEARING)
	var yaw := -deg_to_rad(ARENA_BEARING)
	var facing := Basis(Vector3.UP, yaw)
	var red := Color(1.0, 0.3, 0.35)
	_solid(Vector3(22, 10, 14), at + facing * Vector3(0, 5.0, -8.6), WALL, yaw)
	_add_seams(at + facing * Vector3(0, 5.0, -8.6), Vector3(22, 10, 14), yaw, red, 5.0)
	_solid(Vector3(1.6, 8.0, 2.4), at + facing * Vector3(-4.0, 4.0, 0), DARK, yaw)
	_solid(Vector3(1.6, 8.0, 2.4), at + facing * Vector3(4.0, 4.0, 0), DARK, yaw)
	_solid(Vector3(9.6, 1.4, 2.4), at + facing * Vector3(0, 8.7, 0), STEEL, yaw)
	_part(self, Vector3(6.4, 0.12, 0.12), at + facing * Vector3(0, 7.9, 1.25), red, true, yaw)
	_sign("ARENA", at + facing * Vector3(0, 8.7, 1.25), yaw, 1.0, Color(1.0, 0.4, 0.35))
	_solid(Vector3(1.6, 1.1, 0.8), at + facing * Vector3(7.0, 0.55, 1.4), DARK, yaw)
	if LaunchScope.holds("arena"):
		# Held back at launch (`LaunchScope`): the gate's shutter is down,
		# like the RC yard's.
		_shutter(Transform3D(facing, at), 6.4, 8.0, yaw)
		_sign("OPENING SOON", at + facing * Vector3(0, 4.0, 0.2), yaw, 0.7, red)
		return
	var portal := _add_portal("arena", "Enter the arena", at + facing * Vector3(0, 0, 1.4), 3.0)
	_part(self, Vector3(6.2, 7.0, 0.04), at + facing * Vector3(0, 3.6, -0.6), red.darkened(0.92), true, yaw)
	var lit := Node3D.new()
	lit.name = "Lit"
	lit.visible = false
	portal.add_child(lit)
	_part(lit, Vector3(6.2, 7.0, 0.04), facing * Vector3(0, 3.6, -1.9), red.darkened(0.62), true, yaw)


## South-west: a walled yard kept for the toy RC arena (a later game), its
## shutter down.
func _build_rc_yard() -> void:
	var at := _at(DISTRICT_RING, RC_BEARING)
	var yaw := -deg_to_rad(RC_BEARING)
	var facing := Basis(Vector3.UP, yaw)
	var gold := Color(1.0, 0.8, 0.3)
	_slab(Vector3(30, 0.05, 30), at, DARK, yaw)
	for i in 4:
		var side := Basis(Vector3.UP, yaw + TAU * i / 4.0)
		_solid(Vector3(30.0, 3.0, 0.4), at + side * Vector3(0, 1.5, 15.0), STEEL, yaw + TAU * i / 4.0)
	# The shutter in the wall facing the plaza, down.
	_part(self, Vector3(9.0, 2.6, 0.1), at + facing * Vector3(0, 1.4, 15.25), Color(0.4, 0.42, 0.46), false, yaw)
	for k in 8:
		_part(self, Vector3(9.0, 0.04, 0.05), at + facing * Vector3(0, 0.3 + k * 0.32, 15.32), Color(0.2, 0.21, 0.24),
				false, yaw)
	_add_marker("rc_arena", at)
	_sign("RC YARD", at + facing * Vector3(0, 3.6, 15.25), yaw, 1.0, gold)


## On the diagonals between the districts: gardens of lit reeds in planters
## round a clearing, benches between, the boulevard running through.
func _build_gardens() -> void:
	for bearing: float in GARDENS:
		var centre := _at(GARDEN_RING, bearing)
		_slab_disc(16.0, PAVING, centre)
		_slab_ring(16.0, 0.25, 48, Color(0.35, 1.0, 0.75).darkened(0.3), 0.05, null, centre)
		# Planters and benches off the boulevard, never on it.
		for k in 4:
			var turn: float = bearing + [60.0, 120.0, 240.0, 300.0][k]
			var at := centre + _at(10.5, turn)
			_planter(at, -deg_to_rad(turn), Color(0.35, 1.0, 0.75))
			var seat := centre + _at(7.0, turn + 25.0)
			_solid(Vector3(3.0, 0.45, 0.9), seat + Vector3(0, 0.225, 0), STEEL, -deg_to_rad(turn + 25.0))


## The boulevards between the plaza and the districts, dressed as somewhere
## to stop, never in the lane: each stop is halfway out and serves the people
## going that way. The food court feeds the civic square's crowd, the
## fountain is where people wait before the gates, the tea cart and bike
## park sit by the residences. Carts are staffed; their customers queue,
## eat at the standing tables beside them and walk on (`locals_layout`).
## No signs: a cart says what it is by what is on it.
func _build_boulevards() -> void:
	_build_food_court()
	_build_fountain()
	_build_bike_corner()
	var green := Color(0.35, 1.0, 0.75)
	for bearing: float in GARDENS:
		var yaw := -deg_to_rad(bearing)
		var across := Basis(Vector3.UP, yaw) * Vector3.RIGHT
		for side: float in [-1.0, 1.0]:
			for ring: float in TREE_RINGS:
				_tree(_at(ring, bearing) + across * side * TREE_SIDE, green)
			_light_sculpture(_at(SCULPTURE_RING, bearing) + across * side * TREE_SIDE, [CYAN, MAGENTA][int(side > 0.0)])
		# A bench between each pair of trees, facing the avenue.
		for ring: float in [70.0, 123.0, 137.0]:
			var side := 1.0 if int(ring) % 2 == 0 else -1.0
			_bench(_at(ring, bearing) + across * side * (TREE_SIDE - 0.4), yaw - PI / 2.0 * side)


## East, on the way to the civic square: two carts either side of the lane,
## noodles to the north and a grill to the south, with standing tables.
func _build_food_court() -> void:
	var at := FOOD_COURT
	var amber := Color(1.0, 0.7, 0.35)
	_slab(Vector3(30, 0.03, 40), at, PAVING, 0.0)
	for side: float in [-1.0, 1.0]:
		var edge := at + Vector3(0, 0, side * 20.0)
		_slab(Vector3(30.0, 0.05, 0.2), edge, _glow(amber.darkened(0.35)), 0.0)
		# The cart faces the lane.
		var cart := at + Vector3(0, 0, side * 16.5)
		var facing := 0.0 if side < 0.0 else PI
		_cart(cart, facing, amber, "noodles" if side < 0.0 else "grill",
				[at + Vector3(-8.0, 0, side * 12.5), at + Vector3(8.0, 0, side * 12.5),
				at + Vector3(-7.0, 0, side * 17.5), at + Vector3(7.5, 0, side * 17.0)],
				at + Vector3(-4.0, 0, side * 7.0), at + Vector3(-26.0, 0, side * 3.5))
		for x: float in [-13.0, 13.0]:
			_tree(at + Vector3(x, 0, side * 18.0), Color(0.35, 1.0, 0.75))
			_bench(at + Vector3(x, 0, side * 9.0), facing)


## North, on the way to the gates: a round square with a fountain in the
## middle of the boulevard (the lane parts round it), benches round it, and a
## coffee kiosk on its west side.
func _build_fountain() -> void:
	var at := FOUNTAIN
	var blue := Color(0.45, 0.8, 1.0)
	_slab_disc(19.0, PAVING, at)
	_slab_ring(19.0, 0.25, 64, blue.darkened(0.3), 0.05, null, at)
	# The basin: a low rim you can sit on, glowing water, a stepped centre
	# with a jet of light rising out of it.
	var rim: Array[Transform3D] = []
	var segments := 28
	for i in segments:
		var bearing := 360.0 * (i + 0.5) / segments
		rim.append(Transform3D(Basis(Vector3.UP, -deg_to_rad(bearing)), at + _at(4.6, bearing) + Vector3(0, 0.275, 0)))
	_batch(Vector3(TAU * 4.6 / segments + 0.08, 0.55, 0.5), rim, STEEL, true)
	_slab_ring(4.85, 0.06, segments, blue, 0.56, null, at)
	var water := CylinderMesh.new()
	water.top_radius = 4.35
	water.bottom_radius = 4.35
	water.height = 0.04
	water.radial_segments = 48
	water.material = _water()
	var surface := MeshInstance3D.new()
	surface.mesh = water
	surface.position = at + Vector3(0, 0.38, 0)
	add_child(surface)
	_solid(Vector3(1.8, 0.7, 1.8), at + Vector3(0, 0.35, 0), DARK, PI / 4.0)
	_solid(Vector3(1.0, 1.4, 1.0), at + Vector3(0, 0.7, 0), DARK)
	_part(self, Vector3(2.6, 0.08, 2.6), at + Vector3(0, 1.45, 0), blue, true, PI / 4.0)
	SolidProp.box(nav_region, Vector3(2.6, 0.1, 2.6), Transform3D(Basis(Vector3.UP, PI / 4.0), at + Vector3(0, 1.45, 0)))
	# The jet: a lit column with rings of spray stepping out as they fall.
	_part(self, Vector3(0.24, 3.6, 0.24), at + Vector3(0, 3.2, 0), blue, true)
	SolidProp.box(nav_region, Vector3(0.3, 3.6, 0.3), Transform3D(Basis.IDENTITY, at + Vector3(0, 3.2, 0)))
	for k in 3:
		var ring := 0.7 + 0.55 * k
		for turn: float in [0.0, PI / 4.0]:
			_part(self, Vector3(ring, 0.05, ring), at + Vector3(0, 5.0 - 0.9 * k, 0), blue.darkened(0.15 * k), true,
					turn + 0.3 * k)
	_lamps.append(at + Vector3(0, 3.5, 0))
	# East of the water, benches on the diagonals facing it and trees behind;
	# west of it the coffee kiosk, its tables at the water's edge where the
	# benches would be, and trees out past them.
	for bearing: float in [45.0, 135.0]:
		_bench(at + _at(12.0, bearing), -deg_to_rad(bearing))
		_tree(at + _at(16.0, bearing), Color(0.35, 1.0, 0.75))
	for bearing: float in [235.0, 305.0]:
		_tree(at + _at(17.0, bearing), Color(0.35, 1.0, 0.75))
	_cart(at + Vector3(-15.5, 0, 0), PI / 2.0, Color(1.0, 0.75, 0.45), "coffee",
			[at + _at(12.0, 225.0), at + _at(12.0, 315.0)], at + Vector3(-10.8, 0, 10.0), at + Vector3(-4.0, 0, 28.0))
	# A long planter on the east side, a bench in front of it.
	_solid(Vector3(1.6, 0.7, 9.0), at + Vector3(16.0, 0.35, 0), DARK)
	_part(self, Vector3(1.7, 0.06, 9.1), at + Vector3(16.0, 0.72, 0), Color(0.35, 1.0, 0.75).darkened(0.2), true)
	for k in 7:
		var tall := 1.1 + 0.3 * (k * 5 % 4)
		_part(self, Vector3(0.07, tall, 0.07), at + Vector3(16.0 + 0.3 * (k % 2 * 2 - 1), 0.7 + tall * 0.5,
				-3.6 + 1.2 * k), Color(0.35, 1.0, 0.75), true)
	_bench(at + Vector3(13.6, 0, 0), -PI / 2.0)


## West, by the residences: the residents' bikes parked in a bay south of the
## lane, and a tea cart with tables to the north.
func _build_bike_corner() -> void:
	var at := BIKE_CORNER
	var blue := Color(0.5, 0.85, 1.0)
	_slab(Vector3(30, 0.03, 40), at, PAVING, 0.0)
	_slab(Vector3(30.0, 0.05, 0.2), at + Vector3(0, 0, -20.0), _glow(blue.darkened(0.35)), 0.0)
	_cart(at + Vector3(2.0, 0, -16.5), 0.0, Color(0.6, 1.0, 0.7), "tea",
			[at + Vector3(-6.5, 0, -12.5), at + Vector3(9.5, 0, -13.0), at + Vector3(-6.0, 0, -17.5)],
			at + Vector3(4.0, 0, -7.0), at + Vector3(26.0, 0, -3.5))
	# The bay: a dark apron with lit stall lines, a low rail behind, the bikes
	# nose out to the lane.
	var bay := at + Vector3(0, 0, 14.5)
	_slab(Vector3(18.0, 0.035, 6.0), bay, DARK, 0.0)
	for k in 6:
		_slab(Vector3(0.1, 0.05, 5.0), bay + Vector3(-7.5 + 3.0 * k, 0, 0), _glow(Color(1.0, 0.65, 0.25).darkened(0.3)), 0.0)
	_solid(Vector3(18.0, 0.5, 0.25), bay + Vector3(0, 0.25, 3.3), STEEL)
	_part(self, Vector3(18.0, 0.05, 0.27), bay + Vector3(0, 0.52, 3.3), blue.darkened(0.2), true)
	var bikes := ["bike_scrapper", "bike_raider", "bike_scrapper", "bike_scrapper"]
	for k in bikes.size():
		if k == 2:
			continue  # an empty stall: someone is out riding
		_display_vehicle(bikes[k], bay + Vector3(-6.0 + 3.0 * k + (k % 2) * 0.15, 0, 0.4), 0.06 * (k % 3 - 1))
	_display_vehicle("bike_scrapper", bay + Vector3(6.0, 0, 0.4), -0.05)
	for x: float in [-13.0, 13.0]:
		_tree(at + Vector3(x, 0, -18.0), Color(0.35, 1.0, 0.75))
		_tree(at + Vector3(x, 0, 16.0), Color(0.35, 1.0, 0.75))
	_bench(at + Vector3(-10.0, 0, -9.0), 0.0)
	_lamps.append(bay + Vector3(0, 3.6, -1.0))


## A street cart facing `yaw` (its customers stand on its local +Z side):
## counter, canopy on two posts, what it sells laid out on top, a lamp, and
## its standing `tables`. Its customers' spots go to `_stops`: they come in
## from `far` (out on the lane) by way of `enter`, and leave the same way.
func _cart(at: Vector3, yaw: float, color: Color, kind: String, tables: Array, enter: Vector3, far: Vector3) -> void:
	var turn := Basis(Vector3.UP, yaw)
	_solid(Vector3(2.8, 1.0, 1.3), at + Vector3(0, 0.5, 0), DARK, yaw)
	_solid(Vector3(3.0, 0.06, 1.5), at + Vector3(0, 1.03, 0), STEEL, yaw)
	# What stands on the counter (urns, pots, a grill) stops a hand too.
	SolidProp.box(nav_region, Vector3(2.8, 0.7, 1.0), Transform3D(turn, at + turn * Vector3(0, 1.41, -0.15)))
	_part(self, Vector3(2.8, 0.08, 0.04), at + turn * Vector3(0, 0.82, 0.67), color, true, yaw)
	for x: float in [-1.45, 1.45]:
		_part(self, Vector3(0.14, 0.56, 0.56), at + turn * Vector3(x, 0.3, -0.1), Color(0.12, 0.12, 0.14), false, yaw)
		_part(self, Vector3(0.08, 2.3, 0.08), at + turn * Vector3(x * 0.95, 2.18, -0.6), Color(0.3, 0.32, 0.36), false, yaw)
		SolidProp.box(nav_region, Vector3(0.15, 2.3, 0.15), Transform3D(turn, at + turn * Vector3(x * 0.95, 2.18, -0.6)))
	# The canopy: a dark sheet with a lit front edge, pitched over the counter.
	_part(self, Vector3(3.5, 0.07, 2.3), at + turn * Vector3(0, 3.32, 0.2), Color(0.16, 0.18, 0.24), false, yaw)
	_part(self, Vector3(3.5, 0.08, 0.08), at + turn * Vector3(0, 3.3, 1.35), color, true, yaw)
	_part(self, Vector3(3.5, 0.3, 0.05), at + turn * Vector3(0, 3.12, 1.35), color.darkened(0.55), true, yaw)
	match kind:
		"noodles":
			# Steaming pots and a stack of bowls.
			for x: float in [-0.8, 0.0]:
				_part(self, Vector3(0.5, 0.42, 0.5), at + turn * Vector3(x, 1.27, -0.2), Color(0.55, 0.57, 0.6), false, yaw)
				_part(self, Vector3(0.42, 0.04, 0.42), at + turn * Vector3(x, 1.49, -0.2), Color(1.0, 0.85, 0.6), true, yaw)
			for k in 4:
				_part(self, Vector3(0.3, 0.07, 0.3), at + turn * Vector3(0.9, 1.1 + 0.075 * k, 0.25), Color(0.9, 0.9, 0.92), false, yaw)
		"grill":
			# A hot plate glowing orange and skewers along it.
			_part(self, Vector3(1.6, 0.12, 0.7), at + turn * Vector3(-0.4, 1.12, -0.15), Color(0.15, 0.15, 0.16), false, yaw)
			_part(self, Vector3(1.5, 0.03, 0.6), at + turn * Vector3(-0.4, 1.19, -0.15), Color(1.0, 0.45, 0.15), true, yaw)
			for k in 6:
				_part(self, Vector3(0.05, 0.05, 0.5), at + turn * Vector3(-1.0 + 0.24 * k, 1.23, -0.15), Color(0.55, 0.3, 0.2), false, yaw)
			_part(self, Vector3(0.5, 0.3, 0.35), at + turn * Vector3(0.95, 1.21, 0.2), Color(0.85, 0.6, 0.3), false, yaw)
		"coffee", "tea":
			# Urns with lit taps, cups beside them.
			for x: float in [-0.9, -0.3]:
				_part(self, Vector3(0.38, 0.62, 0.38), at + turn * Vector3(x, 1.37, -0.25), Color(0.62, 0.64, 0.68), false, yaw)
				_part(self, Vector3(0.08, 0.08, 0.1), at + turn * Vector3(x, 1.2, -0.03), color, true, yaw)
			for k in 3:
				_part(self, Vector3(0.12, 0.16, 0.12), at + turn * Vector3(0.5 + 0.22 * k, 1.14, 0.3),
						Color(0.95, 0.95, 0.95) if kind == "coffee" else Color(0.6, 0.85, 0.65), false, yaw)
	_lamps.append(at + turn * Vector3(0, 2.9, 0.6))
	for table: Vector3 in tables:
		_high_table(table, color)
	# The cook behind the counter; customers in front, queueing back from it.
	var front := at + turn * Vector3(0, 0, 1.55)
	# Where a customer steps to with their order, out of the queue's way.
	var served := front + turn * Vector3(0.8, 0, 1.6)
	var places: Array = []
	for table: Vector3 in tables:
		# Places on the side people reach the table from (the counter) and
		# leave it by (the way out), so nobody walks through the table.
		var from := (served - table).normalized() + (enter - table).normalized()
		var toward := atan2(from.z, from.x)
		for angle: float in [toward - 1.3, toward, toward + 1.3]:
			var spot := table + Vector3(cos(angle), 0, sin(angle)) * 0.85
			places.append([spot, atan2(spot.x - table.x, spot.z - table.z)])
	# A local faces along -Z at yaw 0 (`PlazaLocals.yaw_of`): customers face
	# the cart at its own yaw, the cook faces them.
	_stops.append({"counter": front, "served": served, "yaw": yaw, "queue": turn * Vector3(0, 0, 1),
			"cook": [at + turn * Vector3(-0.5, 0, -1.15), yaw + PI], "places": places, "enter": enter, "far": far})


## A standing table: a post, a round-ish top and a lit ring under it.
func _high_table(at: Vector3, color: Color) -> void:
	_solid(Vector3(0.14, 1.05, 0.14), at + Vector3(0, 0.525, 0), STEEL)
	_part(self, Vector3(0.6, 0.06, 0.6), at + Vector3(0, 0.03, 0), Color(0.3, 0.32, 0.38))
	for turn: float in [0.0, PI / 4.0]:
		_part(self, Vector3(0.78, 0.05, 0.78), at + Vector3(0, 1.08, 0), Color(0.62, 0.64, 0.7), false, turn)
	_part(self, Vector3(0.5, 0.03, 0.5), at + Vector3(0, 1.03, 0), color, true, PI / 8.0)


## A bench facing `yaw`: a slatted seat and back on two dark legs.
func _bench(at: Vector3, yaw: float) -> void:
	var turn := Basis(Vector3.UP, yaw)
	for x: float in [-1.2, 1.2]:
		_solid(Vector3(0.14, 0.42, 0.75), at + turn * Vector3(x, 0.21, -0.05), DARK, yaw)
		_solid(Vector3(0.12, 0.62, 0.1), at + turn * Vector3(x, 0.72, -0.4), DARK, yaw)
	for z: float in [-0.28, 0.0, 0.28]:
		_solid(Vector3(3.0, 0.07, 0.24), at + turn * Vector3(0, 0.46, z), STEEL, yaw)
	for y: float in [0.68, 0.92]:
		_solid(Vector3(3.0, 0.16, 0.06), at + turn * Vector3(0, y, -0.44), STEEL, yaw)
	_part(self, Vector3(2.4, 0.03, 0.04), at + turn * Vector3(0, 0.42, 0.38), CYAN.darkened(0.3), true, yaw)


## A tree in a planter: a slim trunk and a crown of tiers, each an
## eight-sided plate stepping in as it climbs, a faint glow under each.
func _tree(at: Vector3, color: Color) -> void:
	_solid(Vector3(1.5, 0.55, 1.5), at + Vector3(0, 0.275, 0), DARK)
	_part(self, Vector3(1.55, 0.05, 1.55), at + Vector3(0, 0.57, 0), color.darkened(0.3), true)
	_solid(Vector3(0.22, 3.2, 0.22), at + Vector3(0, 2.1, 0), STEEL)
	var leaf := Color(0.12, 0.3, 0.24)
	var tiers := [[2.5, 3.1, 0.55], [2.1, 3.65, 0.5], [1.6, 4.15, 0.45], [1.0, 4.6, 0.4], [0.45, 4.95, 0.3]]
	for k in tiers.size():
		var tier: Array = tiers[k]
		var w: float = tier[0]
		var y: float = tier[1]
		var tall: float = tier[2]
		for turn: float in [0.0, PI / 4.0]:
			_part(self, Vector3(w, tall, w), at + Vector3(0, y, 0), leaf.lightened(0.04 * k), false, turn + 0.2 * k)
		if k < 3:
			_part(self, Vector3(w * 0.8, 0.03, w * 0.8), at + Vector3(0, y - tall * 0.5 - 0.02, 0), color.darkened(0.5),
					true, PI / 8.0 + 0.2 * k)


## A light sculpture: lit slats stacked up a dark spine, each turned a little
## further, so it twists as it climbs.
func _light_sculpture(at: Vector3, color: Color) -> void:
	_solid(Vector3(1.3, 0.4, 1.3), at + Vector3(0, 0.2, 0), DARK, PI / 4.0)
	_solid(Vector3(0.2, 5.6, 0.2), at + Vector3(0, 3.2, 0), STEEL)
	for k in 11:
		var y := 0.9 + 0.48 * k
		var w := 1.5 - absf(k - 5.0) * 0.13
		_part(self, Vector3(w, 0.06, 0.22), at + Vector3(0, y, 0), color if k % 2 == 0 else color.darkened(0.35), true,
				deg_to_rad(17.0 * k))
	# The slats turn round the spine: you walk round them, not through.
	var slats := CylinderShape3D.new()
	slats.radius = 0.7
	slats.height = 4.9
	_solid_shape(slats, at + Vector3(0, 3.35, 0))


## The fountain's water: lit from below, a little see-through.
func _water() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.18, 0.45, 0.7, 0.75)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(0.2, 0.55, 0.95)
	mat.emission_energy_multiplier = 0.9
	mat.metallic = 0.3
	mat.roughness = 0.05
	return mat


## A planter with a light rim and glowing reeds of different heights.
func _planter(at: Vector3, yaw: float, color: Color) -> void:
	_solid(Vector3(2.6, 0.8, 2.6), at + Vector3(0, 0.4, 0), DARK, yaw)
	_part(self, Vector3(2.7, 0.06, 2.7), at + Vector3(0, 0.82, 0), color.darkened(0.2), true, yaw)
	for k in 5:
		var stem := at + Basis(Vector3.UP, yaw + k * 1.3) * Vector3(0.7, 0, 0) * (0.3 + 0.15 * k)
		var tall := 1.4 + 0.35 * ((k * 3 + int(absf(at.x))) % 4)
		_part(self, Vector3(0.07, tall, 0.07), stem + Vector3(0, 0.8 + tall * 0.5, 0), Color(0.35, 1.0, 0.75), true)


## Where the Concourse's locals spend their day, as plain data for
## `core/social/plaza_locals.gd` (a view that walks them on every client):
##   centre     what the rings go round
##   rings      [inner, outer] radius bands of open floor to stroll round
##   browse     [stand point, yaw] at each shopfront's door
##   street     {from, to, lane}: the street the fronts face; shoppers keep
##              to a lane either side of its middle and cross at a door
##   watch      tiers facing the big screen: {centre, width, depth, yaw}
##   gather     open spots where a few stand and talk
##   routes     polylines a wanderer walks out along and back
##   stops      the boulevards' carts: {counter, served, yaw, queue, cook, places,
##              enter, far}; customers queue back from the counter along
##              `queue`, eat at a place ([pos, yaw]) and walk on
## Kept clear of the benches, podiums, stages, planters and pillars.
func locals_layout() -> Dictionary:
	var browse: Array = []
	for front: Dictionary in _fronts:
		# Facing the shop: the front's own yaw looks out at the street.
		browse.append([front.door, float(front.yaw)])
	var watch: Array = []
	for row in 4:
		var tier := _tier(row)
		watch.append({"centre": tier.centre, "width": tier.width, "depth": tier.depth, "yaw": 0.0})
	return {
		"centre": Vector3.ZERO,
		"rings": [[16.4, 18.2], [27.0, 29.5], [50.0, 56.0]],
		"browse": browse,
		"street": {"from": Vector3(0, 0, ROW_FROM + 3.0), "to": Vector3(0, 0, ROW_TO - 8.0), "lane": ROW_LANE},
		"watch": watch,
		"gather": [_at(23.4, 350.0), _at(30.5, 230.0), _at(36.0, 120.0), _at(24.0, 90.0), _at(31.0, 268.0),
				ARRIVAL + Vector3(3.0, 0, 10.0), CIVIC + Vector3(-6.0, 0, 6.0), CIVIC + Vector3(4.0, 0, -8.0),
				RESIDENCES + Vector3(-2.0, 0, -9.0), RESIDENCES + Vector3(12.0, 0, 8.0),
				Vector3(14.0, 0, -GATE_LINE + 12.0), Vector3(-20.0, 0, -GATE_LINE + 15.0),
				_at(GARDEN_RING, 45.0) + Vector3(-3.0, 0, -3.0), _at(GARDEN_RING, 315.0) + Vector3(3.0, 0, 2.0)],
		"stops": _stops,
		"routes": [[_at(30.0, 90.0), Vector3(70, 0, -2.5), Vector3(118, 0, -2.5), CIVIC + Vector3(-4.0, 0, -2.0)],
				[_at(30.0, 270.0), Vector3(-70, 0, 2.5), Vector3(-118, 0, 2.5), RESIDENCES + Vector3(8.0, 0, 3.0)],
				[_at(30.0, 2.0), Vector3(2.5, 0, -86), FOUNTAIN + Vector3(7.5, 0, 0), Vector3(2.5, 0, -114),
						Vector3(2.5, 0, -150), Vector3(4.0, 0, -GATE_LINE + 14.0)],
				[_at(31.0, 180.0), Vector3(-3.5, 0, 66), Vector3(-3.5, 0, 140), Vector3(-2.0, 0, 192)],
				[_at(31.0, 45.0), _at(GARDEN_RING - 4.0, 45.0)],
				[_at(31.0, 225.0), _at(GARDEN_RING - 4.0, 225.0)],
				[_at(42.0, 45.0), _at(150.0, 45.0)], [_at(42.0, 135.0), _at(150.0, 135.0)],
				[_at(42.0, 225.0), _at(150.0, 225.0)], [_at(42.0, 315.0), _at(150.0, 315.0)]],
	}


## Where each person you can talk to stands: a "talker" marker (meta "id",
## "yaw", "name", "role", and "lines", "reads", "color" where they have
## them) and, for those who do not work a counter, a portal in front of
## them whose destination is "talk:<id>". `PlazaView` answers those itself.
func _build_talkers() -> void:
	for id: String in TALKERS:
		var entry: Array = TALKERS[id]
		var at: Vector3 = entry[0]
		var yaw: float = entry[1]
		_add_talker(id, at, yaw, entry[2], entry[3], HELD_LINES.get(id, {}).get(_held_by(id), entry[4]), entry[5])
		var front := Basis(Vector3.UP, yaw) * Vector3.FORWARD
		# No glowing pad: you walk up to a person, not onto a spot.
		var portal := _add_portal("talk:%s" % id, "Talk to %s" % entry[2], at + front * 1.5, 1.8)
		portal.set_meta("talker", id)


## A "talker" marker. A keeper (one with a counter) has no portal of their
## own: the counter's portal names them with its "keeper" meta, and they
## greet whoever trades there.
func _add_talker(id: String, at: Vector3, yaw: float, who: String, role: String, lines: Array,
		reads: String, color := Color(0, 0, 0, 0)) -> Marker3D:
	var marker := _add_marker("talker", at)
	marker.set_meta("id", id)
	marker.set_meta("yaw", yaw)
	marker.set_meta("name", who)
	marker.set_meta("role", role)
	if not lines.is_empty():
		marker.set_meta("lines", lines.duplicate())
	if reads != "":
		marker.set_meta("reads", reads)
	if color.a > 0.0:
		marker.set_meta("color", color)
	if DRESS.has(id):
		marker.set_meta("dress", DRESS[id])
	return marker


## The line under the board's heading.
const BOARD_NOTE := "Jobs that pay scrip. They count when you sign out alive."


## What the board's wall says: today's jobs and how they pay, one line each.
## The same for everyone, since the offers follow the date (a reroll only
## changes your own screen).
static func contract_lines() -> Array[String]:
	var out: Array[String] = [BOARD_NOTE, ""]
	for row in contract_rows():
		out.append("%s  %s   %s" % [row.kind, row.title, row.reward])
	return out


## Today's jobs as the board's cards: [{"kind", "title", "reward"}].
static func contract_rows() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not ResourceLoader.exists(CONTRACTS):
		return out
	var rules := load(CONTRACTS) as Script
	for id: String in rules.call("offers_for", rules.call("today")):
		var job: Dictionary = rules.call("job", id)
		# Favours are Rook's to offer, in person.
		if str(job.get("kind", "")) == "favor":
			continue
		out.append({"kind": str(job.get("kind", "")).to_upper(), "title": str(rules.call("title_of", id)),
				"reward": str(rules.call("reward_text", id))})
	return out


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


## The megacity round the deck (`megacity.gd`): towers from a canyon far
## below up past the top of the view, skyways and air traffic. Scenery only,
## no collision, out of reach, from its own RNG so it never shifts the
## layout; the view is drawn far enough to see it (the "view_far" meta).
func _build_city_below() -> void:
	set_meta("view_far", MEGACITY.VIEW_FAR)
	if not Look.enabled:
		return
	var city: Node3D = MEGACITY.new(LAYOUT_SEED + 1, RADIUS)
	add_child(city)
	var near: Array = []
	for i in TOWER_HEIGHTS.size():
		near.append([_at(TOWER_RING, 360.0 * (i + 0.5) / TOWER_HEIGHTS.size()), TOWER_HEIGHTS[i]])
	city.build(near)


func _dress() -> void:
	if not Look.enabled:
		return
	var art := Node3D.new()
	art.name = "Dressing"
	add_child(art)
	# Few real lights: the glow strips carry the look, lamps only where people
	# stand to read something or go in somewhere.
	var beacon := Look.lamp(Color(0.6, 0.95, 1.0), 10.0, 60.0)
	beacon.position = Vector3(0, SPIRE_TOP + 3.0, 0)
	art.add_child(beacon)
	var base := Look.lamp(Color(0.5, 0.9, 1.0), 4.0, 24.0)
	base.position = Vector3(0, 6.0, 0)
	art.add_child(base)
	for at in _lamps:
		var pool := Look.lamp(Color(0.8, 0.9, 1.0).lerp(WARM, 0.4), 5.0, 18.0)
		pool.position = at
		art.add_child(pool)
	for at in _foot_lights:
		var wash := Look.lamp(Color(0.75, 0.85, 1.0), 3.0, 18.0)
		wash.position = at
		art.add_child(wash)
	for gate in _gates:
		var glow := Look.lamp(Look.gate_color((gate["world"] as WorldDef).planet_type()), 5.0, 16.0)
		glow.position = gate["at"] + Vector3(0, 5.0, 2.0)
		art.add_child(glow)
	_dress_gates(art)
	# Each shop lit warm inside, a touch of its colour.
	for light: Array in _shop_lights:
		var lamp := Look.lamp(WARM.lerp(light[1], 0.12), 6.5, 11.0)
		lamp.position = light[0]
		art.add_child(lamp)
	var clan := Look.lamp(Color(0.8, 0.5, 1.0), 4.0, 14.0)
	clan.position = CLAN_HALL_AT + Vector3(-2.0, 5.0, 0)
	art.add_child(clan)
	var screens := Look.lamp(CYAN, 6.0, 30.0)
	screens.position = SCREEN_AT + Vector3(0, 8.0, 6.0)
	art.add_child(screens)
	var arena := Look.lamp(Color(1.0, 0.4, 0.35), 4.0, 14.0)
	arena.position = _at(DISTRICT_RING - 3.0, ARENA_BEARING) + Vector3(0, 5.0, 0)
	art.add_child(arena)


## A point `radius` metres out on compass `bearing` (degrees, 0 north, clockwise).
func _at(radius: float, bearing: float) -> Vector3:
	var a := deg_to_rad(bearing)
	return Vector3(sin(a) * radius, 0, -cos(a) * radius)


## A box in the map's one solid body, drawn with the others of its material
## as one mesh (`_flush_seams`). Without `collide` it is only drawn (an
## inside panel).
func _solid(size: Vector3, at: Vector3, material: Material, yaw := 0.0, collide := true) -> void:
	var place := Transform3D(Basis(Vector3.UP, yaw), at)
	if collide:
		if _solid_body == null:
			_solid_body = StaticBody3D.new()
			_solid_body.name = "Solid"
			_solid_body.collision_layer = Actor.LAYER_WORLD
			_solid_body.collision_mask = 0
			nav_region.add_child(_solid_body)
		var shape := BoxShape3D.new()
		shape.size = size
		var col := CollisionShape3D.new()
		col.shape = shape
		col.transform = place
		_solid_body.add_child(col)
	if not _solid_parts.has(material):
		_solid_parts[material] = []
	(_solid_parts[material] as Array).append([size, place])


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
	for mat: Material in _solid_parts:
		_batch_sized(_solid_parts[mat], mat)
	_solid_parts.clear()
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


## A static body holding `shape` at `at`, under the navigation region.
func _solid_shape(shape: Shape3D, at: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = Actor.LAYER_WORLD
	body.collision_mask = 0
	body.position = at
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)
	nav_region.add_child(body)


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


## A doorway: where to stand to use something (see the safe-zone contract in
## `WorldDef`). Nothing marks the floor: you walk up to a person, a counter or
## an arch, and the prompt says what it is.
func _add_portal(destination: String, label: String, at: Vector3, radius: float) -> Marker3D:
	var portal := _add_marker("portal", at)
	portal.set_meta("destination", destination)
	portal.set_meta("label", label)
	portal.set_meta("radius", radius)
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


## A sign whose text starts at `at` and runs to the right (as you face it),
## its top line at `at`, wrapped at `width` metres (0 for one line).
func _sign_left(text: String, at: Vector3, yaw: float, size: float, color: Color, width: float) -> void:
	var label := Label3D.new()
	label.text = text
	label.pixel_size = 0.01
	label.font_size = int(size * 100.0)
	label.outline_size = int(size * 12.0)
	label.modulate = color
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	if width > 0.0:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.width = width * 100.0
	else:
		# Unwrapped, the label is laid out from its position: left alignment
		# alone starts the text there.
		label.offset = Vector2.ZERO
	label.position = at
	label.rotation.y = yaw
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
