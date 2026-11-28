extends Node3D
## Greybox Ashfront: one open battlefield, about 600 metres across.
##
## Rolling scorched ground, cratered by shelling and cut by trench lines, with
## five landmarks spread over it: a ruined foundry in the middle and four
## sites around it. Each landmark is a strongpoint with a depot and loot. Two
## armies start with two sites each, garrisoned, and muster their
## reinforcements on opposite sides of the rim; the foundry between them is
## nobody's. Between them lie the wrecks of war machines, which are the cover.
## Players drop in around the rim and ride or fly inward.
##
## The layout uses a fixed seed, so the map is the same every time while loot
## and spawns vary. The rest of the game relies only on the map contract in
## WorldDef. The ground, its collision and the navigation mesh are worked out
## once per run of the game and shared by every copy of the map.

const LAYOUT_SEED := 1337
## Metres between ground samples, and how many there are along each edge.
const CELL := 2.0
const SIDE := 321
## Beyond this distance from the middle the ground climbs into the rim.
const FIELD := 276.0
const RIM_HEIGHT := 46.0
## Players drop in on a ring this far out.
const SPAWN_RING := 248.0
const PLAYER_SPAWNS := 12
const HEIGHTS := [3.0, 6.0, 6.0, 10.0, 16.0]
const RAMP_LENGTH := 8.0
const RAMP_ANGLE_DEG := 15.0
const CRATERS := 80

## The battle this field remembers. Everything on it is placed from this
## story, not dropped at random: each army's supply roads, where each push
## was stopped, and where the giants fell.
##
## Supply roads, from each army's muster through the sites it holds and on
## toward the Forge.
const ROADS := [
	[Vector2(-212, 4), Vector2(-185, -50), Vector2(-150, -118)],
	[Vector2(-212, 4), Vector2(-190, 70), Vector2(-142, 136)],
	[Vector2(-212, 4), Vector2(-140, 8), Vector2(-60, 2)],
	[Vector2(212, -4), Vector2(190, -55), Vector2(158, -106)],
	[Vector2(212, -4), Vector2(185, 60), Vector2(134, 132)],
	[Vector2(212, -4), Vector2(140, -8), Vector2(60, -2)],
]
## Where the pushes died: wrecks of `kinds` (0 tank, 1 strider, 2 dropship)
## strung along the line from `from` to `to`, facing the way they were
## going, staggered `spread` metres either side.
const BATTLES := [
	# The Tide's last push: a tank column down the east road, stopped short
	# of the core.
	{"from": Vector2(118, -4), "to": Vector2(66, 2), "count": 9, "kinds": [0, 0, 0, 1], "spread": 9.0, "big": 1.3},
	# The Legion's air assault: dropships shot down coming in from the west,
	# their furrows all pointing at the Forge.
	{"from": Vector2(-165, -28), "to": Vector2(-82, -10), "count": 6, "kinds": [2], "spread": 14.0, "big": 1.6},
	# The Tide's striders broke on the Breach's line.
	{"from": Vector2(-76, 150), "to": Vector2(-98, 118), "count": 4, "kinds": [1], "spread": 8.0, "big": 1.4},
	# Tide tanks caught on the slope up to Signal Hill.
	{"from": Vector2(-88, -128), "to": Vector2(-112, -102), "count": 4, "kinds": [0], "spread": 7.0, "big": 1.2},
	# A Legion push on Rustfall, stopped in the open.
	{"from": Vector2(70, -132), "to": Vector2(112, -118), "count": 4, "kinds": [0, 2], "spread": 8.0, "big": 1.3},
	# A Legion convoy ambushed on the road to the Breach.
	{"from": Vector2(-198, 40), "to": Vector2(-186, 82), "count": 3, "kinds": [0], "spread": 5.0, "big": 1.0},
	# A Tide convoy hit on the road to Carrier Grave.
	{"from": Vector2(196, 30), "to": Vector2(180, 72), "count": 3, "kinds": [0], "spread": 5.0, "big": 1.0},
]
## The fallen titans: one guarding each lane into the core, the fifth on the
## Breach's flank. Each fell facing the Forge.
const TITAN_SPOTS := [Vector2(-104, -46), Vector2(30, -118), Vector2(110, 56), Vector2(-24, 112), Vector2(-62, 160)]
## Cover hops along every way in from the rim: a lot this far out on each
## drop point's spoke, swung a little to one side and the other.
const HOPS := [232.0, 180.0, 128.0, 82.0]
## The roads are for driving: nothing solid stands within this of a road's
## middle, the ground under them is graded (craters filled, trenches bridged)
## and the tank traps leave them a gap. A rover is 2 m wide.
const ROAD_CLEAR := 6.0
## The road from each muster to the middle starts straight: the first stretch
## past the camp is a runway, long enough for a jet to reach take-off speed
## (about 30 m) with room to spare, lit along its edges.
const RUNWAY_FROM := 16.0
const RUNWAY := 60.0
## Jump ramps sit on the shoulder of the flank roads (these indices into
## `ROADS`), pointing along them, so a bike at speed swerves onto one.
const RAMP_ROADS := [0, 1, 3, 4]
## Each army's motor pool: parked bikes beside its runway.
const MOTOR_POOL := 3
## How long an emptied strongpoint's vehicle spot waits for a new one.
const SITE_VEHICLE_RESPAWN := 600.0
## The Works: a ruined factory district in the middle ring, south of the
## Forge, between the two southern drop points. One street runs north from
## its mouth straight at the Forge, lined with halls; catwalks along the
## halls' street faces and gantries across the street make a second storey
## over it, and the roofs are left to the flight rigs. Close quarters to set
## against the open field: a jetpack or boots own it, wings are no use in it.
## Laid along the z axis, so every hall is square to the map.
const WORKS_FROM := 198.0
const WORKS_TO := 104.0
## Half the street's width: a rover and a bike pass, with the catwalks over
## their outer edges.
const WORKS_STREET := 9.0
## How far the district's ground is graded, either side of the street.
const WORKS_REACH := 24.0
## The halls: which side of the street (1 east, -1 west), the z of their
## outer and inner ends, depth back from the street, height, the roof
## ("flat", or "saw" for a sawtooth's tilted teeth), and whether the hall is
## an open-fronted shed (walls and a roof, open to the street, with a floor
## under cover to fight across) instead of a solid block. One alley on each
## side, staggered so no line runs clean across, and a cross street through
## the middle make a crossroads to flank through.
const WORKS_HALLS := [
	{"side": 1.0, "from": 198.0, "to": 180.0, "depth": 13.0, "height": 12.0, "roof": "saw"},
	{"side": 1.0, "from": 174.0, "to": 160.0, "depth": 12.0, "height": 10.0, "roof": "flat", "stacks": 1},
	{"side": 1.0, "from": 150.0, "to": 124.0, "depth": 13.0, "height": 16.0, "roof": "flat", "roof_cache": true, "stacks": 2},
	{"side": 1.0, "from": 124.0, "to": 106.0, "depth": 12.0, "height": 10.0, "roof": "flat", "shed": true},
	{"side": -1.0, "from": 196.0, "to": 176.0, "depth": 12.0, "height": 9.0, "roof": "flat", "shed": true},
	{"side": -1.0, "from": 176.0, "to": 160.0, "depth": 14.0, "height": 14.0, "roof": "saw"},
	{"side": -1.0, "from": 150.0, "to": 132.0, "depth": 13.0, "height": 12.0, "roof": "flat", "roof_cache": true},
	{"side": -1.0, "from": 126.0, "to": 108.0, "depth": 13.0, "height": 10.0, "roof": "saw"},
]
## The cross street, between these z.
const WORKS_CROSS := Vector2(150.0, 160.0)
## The second storey: catwalks this high along both sides' hall fronts
## (bridging the alleys and the cross street), a gantry across the street at
## each of these z, and a stair up out of each side's alley (side, z).
const WORKS_DECK := 6.0
const WORKS_GANTRIES := [188.0, 155.0, 116.0]
const WORKS_STAIRS := [Vector2(1.0, 177.0), Vector2(-1.0, 129.0)]
const WORKS_WALK := 2.0
const FIELD_PATROLS := 8
## Risk zones (DESIGN.md section 2): the core is the molten Foundry, the
## middle reaches past the four landmarks, the outer ring is the rest.
const CORE_RADIUS := 52.0
## The war intensity the Foundry waits on before the armies send their
## elites at it (`Strongpoint.hot_at`).
const FOUNDRY_HOT := 0.5
const MIDDLE_RADIUS := 225.0
## Gate outposts: safe bubbles on four of the rim's drop points, where
## players arrive. Each is a walled yard open toward the middle of the map.
const OUTPOSTS := [
	{"spawn": 2, "name": "Cinder Gate"},
	{"spawn": 5, "name": "Ember Gate"},
	{"spawn": 8, "name": "Slag Gate"},
	{"spawn": 11, "name": "Ash Gate"},
]
const OUTPOST_RADIUS := 13.0

## The landmarks: name, where, how wide, and how far the site is lifted above
## the ground around it.
const SITES := [
	{"name": "The Foundry", "at": Vector2(0, 0), "radius": 40.0, "lift": 0.0, "kind": "foundry", "army": ""},
	{"name": "Signal Hill", "at": Vector2(-150, -118), "radius": 28.0, "lift": 11.0, "kind": "hill", "army": "legion"},
	{"name": "Rustfall", "at": Vector2(158, -106), "radius": 32.0, "lift": 0.0, "kind": "graveyard", "army": "tide"},
	{"name": "The Breach", "at": Vector2(-142, 136), "radius": 32.0, "lift": 0.0, "kind": "breach", "army": "legion"},
	{"name": "Carrier Grave", "at": Vector2(134, 132), "radius": 34.0, "lift": 0.0, "kind": "carrier", "army": "tide"},
]
## The armies: what a site they hold shows as its holder, and where on the
## rim their reinforcements muster. The Legion has the west, the Tide the east.
const ARMIES := {
	"legion": {"holder_name": "the Legion", "muster": Vector2(-212, 4)},
	"tide": {"holder_name": "the Tide", "muster": Vector2(212, -4)},
}
const MUSTER_SPOTS := 6

## The Forge's tiers from the ground up: width and height of each block. The
## top is far over every flight rig's ceiling, so its upper tiers are only
## ever seen, never stood on.
const FORGE_AT := Vector2(2, -2)
const FORGE_TIERS := [Vector2(14.0, 10.0), Vector2(10.0, 14.0), Vector2(7.0, 22.0), Vector2(4.5, 18.0), Vector2(2.0, 16.0)]
## The four towers on the plinth's corners: width and height.
const FORGE_TOWER := Vector2(3.0, 34.0)
## The furnace mouth in each face of the plinth: width, and how far up from
## the plinth's sunk foot its opening in the cladding goes.
const FORGE_MOUTH := Vector2(2.8, 6.0)
## A dropship wreck's engine, before its `big`.
const WRECK_ENGINE := Vector3(1.3, 1.3, 2.6)
## The old front: which trench lines face across no man's land, so sandbags
## go on their lips and tank traps out in front of them.
const FRONT_LINES := [0, 1, 3, 4, 5]
## The trench lines, each a run of points on the field.
const TRENCHES := [
	# The Breach: two lines facing the middle, and a communication trench.
	[Vector2(-180, 96), Vector2(-132, 92), Vector2(-96, 110), Vector2(-88, 150)],
	[Vector2(-196, 82), Vector2(-150, 70), Vector2(-104, 78)],
	[Vector2(-132, 92), Vector2(-126, 118)],
	# The old front across the middle of the field.
	[Vector2(-70, -64), Vector2(-20, -78), Vector2(34, -70), Vector2(84, -86)],
	[Vector2(-84, 62), Vector2(-30, 74), Vector2(26, 66), Vector2(70, 80)],
	[Vector2(96, -30), Vector2(110, 20), Vector2(100, 62)],
]
## Skirmish lines (the enemy AI pass, step 4): each army keeps soldiers in
## the front's trenches on its own half of the field, this far apart along
## a line, on a "line_post" marker. A line well inside an army's half is
## its own; the old front across the middle is split down the centre.
const LINE_POST_EVERY := 14.0
const LINE_POST_MIDDLE := 12.0
const SANDBAG_EVERY := 15.0
const TRAP_OFFSET := 13.0
const TRAP_EVERY := 6.5
## How far the Forge's beacon is drawn: the whole map and past it.
const FAR_SIGHT := 2000.0
## How far the player's view draws here (the map's "view_far" meta): the
## skyline on the far side of the field from anywhere in it.
const VIEW_FAR := 1400.0
## The Colossus and the capital ship past the rim (view only).
const GIANTS := preload("res://worlds/ashfront/giants.gd")
const SKYFIRE := preload("res://worlds/ashfront/skyfire.gd")
const BATTLE := preload("res://worlds/ashfront/battle.gd")
const SUNSHAFTS := preload("res://worlds/ashfront/sunshafts.gd")
const LOWSKY := preload("res://worlds/ashfront/lowsky.gd")
const HORDE := preload("res://worlds/ashfront/horde.gd")
const FLARES := preload("res://worlds/ashfront/flares.gd")
const RIM_FORT := preload("res://worlds/ashfront/rim_fort.gd")
const KIT_DRESS := preload("res://worlds/ashfront/kit_dress.gd")
## The burning horizon: a ring of fire-glow this far out, behind the
## skyline, glowing this much when quiet and in all-out war.
const GLOW_RING := 560.0
const GLOW_STRENGTH := Vector2(0.35, 0.75)
## The Ashland's land past the rim (DESIGN.md "Planet kit"): its rise and
## ridges near the map, kept under the skyline's floor.
const FAR_RIM := 26.0
const FAR_RIDGES := 10.0
## The battle shelves (Caleb's call: the scenery army fights only where no
## one can go): past the rim on three sides the far land climbs in broad
## steps, high enough to be seen over the rim from the field, and the
## scenery army fights on their flats. Each shelf faces the field along one
## of the map's sides ("out", a unit axis) and runs along it between two
## "lateral" coordinates (along `Vector2(-out.y, out.x)`), clear of the
## skyline's set pieces. `SHELF_STEPS` are the steps by distance out from
## the middle along "out": [the rise's foot, its top, the flat's height];
## each flat runs on to the next rise's foot (the last to `SHELF_END`).
## `SHELF_EDGE` softens a shelf's ends into the land round it.
const SHELVES := [
	{"out": Vector2(1, 0), "lateral": Vector2(80, 270)},
	{"out": Vector2(-1, 0), "lateral": Vector2(-260, -60)},
	{"out": Vector2(0, -1), "lateral": Vector2(60, 250)},
]
const SHELF_STEPS := [Vector3(330, 352, 62), Vector3(402, 426, 79), Vector3(478, 502, 97)]
const SHELF_END := 570.0
const SHELF_EDGE := 34.0
## The planet's rocks stand this far past the field's edge, or further.
const PROPS_PAST_FIELD := 12.0
## Flashes on the horizon a second: when quiet, and in all-out war.
const FLASH_RATE := Vector2(0.25, 3.0)
const FLASH_TIME := 0.45
## Molten cracks running in to the core.
const CRACKS := 5
## What a cover lot is built from: concrete jersey barriers, sandbag walls and
## steel plates. `size` is length, height and depth.
const COVER_PIECES := [
	{"kind": "jersey", "size": Vector3(3.0, 1.1, 0.7)},
	{"kind": "sandbag", "size": Vector3(3.0, 1.0, 0.9)},
	{"kind": "plate", "size": Vector3(2.2, 1.6, 0.25)},
]

## Kept from the first map built in this run: { navmesh }.
static var _shared := {}
## The ground may be worked out on another thread ahead of a visit
## (`prepare_shared`); whoever comes second waits for the first.
static var _ground_lock := Mutex.new()
## The shared ground, { heights, collision }, kept apart from `_shared` so
## only this is ever touched from two threads, and only under the lock.
static var _ground_shared := {}

var nav_region: NavigationRegion3D
var terrain: Terrain
var _rng := RandomNumberGenerator.new()
## Dressing has its own generator so art never shifts the gameplay layout.
var _art_rng := RandomNumberGenerator.new()
var _noise := FastNoiseLite.new()
## Flat ground: { at: Vector2, radius, height }.
var _pads: Array[Dictionary] = []
var _craters: Array[Dictionary] = []
## Trench lines as pairs of points.
var _trenches: Array[PackedVector2Array] = []
var _buildings: Array[Dictionary] = []
var _wrecks: Array[Dictionary] = []
var _cover_spots: Array[Vector3] = []
## Barricade pieces (jersey barriers, sandbag walls, plates, tank traps): the
## dressing draws each one by its "cover" meta over its plain collision box.
var _cover_pieces: Array[StaticBody3D] = []
## Everything solid standing on the ground: { at: Vector2, reach }.
var _solids: Array[Dictionary] = []
var _weather: Node3D
var _beacon: MeshInstance3D
var _beacon_light: OmniLight3D
## The war seen from far off: flashes past the rim, more as it heats up, and
## searchlights sweeping from the Forge. View only, timed by `_art_rng`.
var _flashes: Array[MeshInstance3D] = []
var _flash_left: Array[float] = []
var _searchlights: Array[Node3D] = []
var _horizon_glow: ShaderMaterial
## The far land past the rim, shelves and all (`_far_ground`).
var _land: PlanetTerrain
## The distant war heard (view only; null where `Look` is off).
var _soundscape: Soundscape

## The planet the map stands on (`WorldDef.planet_type`), set before it
## enters the tree; a map made on its own (as the checks do) takes the
## Ashland.
var planet: PlanetType
@onready var WALL := Look.surface("concrete", {"tint": Color(0.45, 0.4, 0.38), "grime": 0.8, "scale": 0.12})
@onready var COVER_METAL := Look.surface("metal", {"tint": Color(0.7, 0.42, 0.28), "scale": 0.45})
@onready var WORKS_METAL := Look.surface("metal", {"tint": Color(0.52, 0.48, 0.45), "grime": 0.8, "scale": 0.3})
@onready var COVER_CONCRETE := Look.surface("concrete", {"tint": Color(0.8, 0.74, 0.68), "grime": 0.9, "scale": 0.5})
@onready var HULL := Look.surface("metal", {"tint": Color(0.62, 0.58, 0.55), "grime": 0.8, "scale": 0.3})
@onready var HULL_RUST := Look.surface("metal", {"tint": Color(0.8, 0.45, 0.3), "grime": 0.9, "scale": 0.35})


func _ready() -> void:
	if planet == null:
		planet = PlanetTypes.get_type("ashland")
	_seed_layout()
	_build_environment()
	nav_region = NavigationRegion3D.new()
	nav_region.name = "Geometry"
	add_child(nav_region)
	_plan()
	_build_ground()
	_build_sites()
	_build_spawns()
	_build_works()
	_build_field()
	_build_field_kit()
	_mark_zones()
	_art_rng.seed = LAYOUT_SEED
	_dress()
	set_meta("view_far", VIEW_FAR)
	if Look.enabled:
		_soundscape = Soundscape.new()
		_soundscape.name = "Soundscape"
		add_child(_soundscape)
		var giants: Node3D = GIANTS.new()
		giants.floor_y = RIM_HEIGHT - 8.0
		giants.soundscape = _soundscape
		giants.plume_maker = _plume
		add_child(giants)
		var skyfire: Node3D = SKYFIRE.new()
		skyfire.floor_y = RIM_HEIGHT - 8.0
		skyfire.soundscape = _soundscape
		skyfire.giants = giants
		add_child(skyfire)
		var shafts: Node3D = SUNSHAFTS.new()
		shafts.floor_y = RIM_HEIGHT - 8.0
		add_child(shafts)
		var battle := make_battle()
		add_child(battle)
		add_child(make_horde())
		add_child(make_rim_fort())
		add_child(FLARES.new())
		add_child(make_low_sky(battle))
	set_process(Look.enabled)


## The scenery army (view only): out on the battle shelves past the rim,
## where no one can go (`SHELVES`).
func make_battle() -> Node3D:
	var battle: Node3D = BATTLE.new()
	battle.field = SHELF_END + 60.0
	battle.shelves = SHELVES
	battle.flats = shelf_flats()
	battle.ground_at = scenery_height
	return battle


## The horde on the battle shelves (view only, `horde.gd`).
func make_horde() -> Node3D:
	var horde: Node3D = HORDE.new()
	horde.shelves = SHELVES
	horde.flats = shelf_flats()
	horde.ground_at = scenery_height
	return horde


## The fortress line on the rim (view only, `rim_fort.gd`): past the map's
## edge, broken down in front of each shelf so the far war shows through.
func make_rim_fort() -> Node3D:
	var fort: Node3D = RIM_FORT.new()
	fort.shelves = SHELVES
	fort.ground_at = scenery_height
	fort.smoke_maker = _smoke
	return fort


## The busy low sky (view only): gunships raking the scenery army, fighters
## going over and dropships coming down past the rim.
func make_low_sky(battle: Node3D) -> Node3D:
	var sky: Node3D = LOWSKY.new()
	sky.floor_y = RIM_HEIGHT - 8.0
	sky.field = FIELD
	sky.battle = battle
	sky.soundscape = _soundscape
	sky.plume_maker = _plume
	return sky


func _seed_layout() -> void:
	_rng.seed = LAYOUT_SEED
	_noise.seed = LAYOUT_SEED
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 0.006
	_noise.fractal_octaves = 3


## Works out the ground every copy of this map shares, on a map that is
## never added to the tree (`WorldDef.prepare_map`, off the main thread).
func prepare_shared() -> void:
	_ground_lock.lock()
	if not _ground_shared.has("heights"):
		_seed_layout()
		_plan()
		terrain = Terrain.new()
		terrain.cell = CELL
		terrain.side = SIDE
		_shape_ground()
		_ground_shared["collision"] = terrain.collision_data()
		_ground_shared["heights"] = terrain.heights
		terrain.free()
		terrain = null
	_ground_lock.unlock()


func bake_navigation() -> void:
	if not _shared.has("navmesh"):
		var navmesh := NavigationMesh.new()
		navmesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
		navmesh.geometry_collision_mask = Actor.LAYER_WORLD
		# Coarser than a street map needs: the ground is open and this keeps
		# the bake of a field this size to a moment.
		navmesh.cell_size = 0.5
		navmesh.cell_height = 0.25
		navmesh.agent_radius = 0.5
		navmesh.agent_height = 1.75
		navmesh.agent_max_climb = 0.5
		navmesh.agent_max_slope = 42.0
		nav_region.navigation_mesh = navmesh
		nav_region.bake_navigation_mesh(false)
		_shared["navmesh"] = navmesh
	nav_region.navigation_mesh = _shared["navmesh"]


## The height of the ground at a point on the map.
func ground_height(x: float, z: float) -> float:
	return terrain.height_at(x, z)


## The ground anywhere, the far land past the map's own included (view
## only: nothing out there collides). What the scenery army stands on.
func scenery_height(x: float, z: float) -> float:
	var half := terrain.extent() * 0.5 - CELL
	if maxf(absf(x), absf(z)) < half:
		return terrain.height_at(x, z)
	return _far_ground().height_at(x, z)


## The far land's height function (`FarLand`), made once.
func _far_ground() -> PlanetTerrain:
	if _land == null:
		var recipe := planet.terrain.duplicate()
		recipe["rim"] = FAR_RIM
		recipe["ridge_amp"] = FAR_RIDGES
		recipe["craters"] = 0
		_land = FarLand.new(recipe, LAYOUT_SEED)
	return _land


## The flats of the battle shelves the scenery army fights on: [from, to]
## distance out along a shelf's "out" (`SHELF_STEPS`), a little in from
## each edge.
static func shelf_flats() -> Array[Vector2]:
	var flats: Array[Vector2] = []
	for i in SHELF_STEPS.size():
		var step: Vector3 = SHELF_STEPS[i]
		var end := SHELF_END if i == SHELF_STEPS.size() - 1 else float((SHELF_STEPS[i + 1] as Vector3).x)
		flats.append(Vector2(step.y + 6.0, end - 6.0))
	return flats


## The far land with Ashfront's battle shelves stepped into it.
class FarLand extends PlanetTerrain:
	func height_at(x: float, z: float) -> float:
		var h := super.height_at(x, z)
		var shelf := FarLand.shelf(x, z)
		return lerpf(h, maxf(h, shelf.x), shelf.y)

	## A shelf's height at (x, z) and how much of it shows there (0 off every
	## shelf, 1 on one).
	static func shelf(x: float, z: float) -> Vector2:
		for entry: Dictionary in SHELVES:
			var out: Vector2 = entry["out"]
			var lateral: Vector2 = entry["lateral"]
			var p := Vector2(x, z)
			var d := p.dot(out)
			var l := p.dot(Vector2(-out.y, out.x))
			var w := smoothstep(lateral.x - SHELF_EDGE, lateral.x, l) * (1.0 - smoothstep(lateral.y, lateral.y + SHELF_EDGE, l))
			w *= smoothstep(SHELF_STEPS[0].x - 20.0, SHELF_STEPS[0].x, d)
			if w <= 0.0:
				continue
			var h := RIM_HEIGHT
			for step: Vector3 in SHELF_STEPS:
				h = lerpf(h, step.z, smoothstep(step.x, step.y, d))
			return Vector2(h, w)
		return Vector2.ZERO


func _process(delta: float) -> void:
	# The embers drift around whoever is looking, not over the whole field.
	var camera := get_viewport().get_camera_3d()
	if camera != null and is_instance_valid(_weather):
		_weather.global_position = Vector3(camera.global_position.x, camera.global_position.y + 6.0,
				camera.global_position.z)
	_tick_distant_war(delta)
	# The beacon breathes, slowly, like a warning light.
	if is_instance_valid(_beacon_light):
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.0021)
		_beacon_light.light_energy = 2.0 + 6.0 * pulse
		_beacon.scale = Vector3.ONE * (0.85 + 0.3 * pulse)


func _build_environment() -> void:
	# The Ashland (DESIGN.md "Planet kit"): smouldering even when it is
	# quiet, a rust-red sky over ash-grey smoke and a low, dull sun, so the
	# Forge, the cracks and the fires light the field; its storm mood is
	# the thick of an ash storm. The war mood is Ashfront's own.
	Planet.atmosphere(self, planet, {
		# All-out war: a blood-red and black sky, the horizon closing in and
		# the sun all but gone, but fog does not start inside 28 m and is not
		# solid before 120 m, so a fight at 30–50 m stays readable.
		# Look.soften_storm enforces that floor even if these numbers are
		# pushed. The column of smoke is overhead, not a wall at eye level.
		"sky_tint": Color(0.32, 0.18, 0.15),
		"sky_saturation": 0.38,
		"sky_energy": 0.38,
		"fog_color": Color(0.2, 0.19, 0.19),
		"fog_density": 0.86,
		"fog_depth_begin": 28.0,
		"fog_depth_end": 120.0,
		"fog_depth_curve": 1.0,
		"fog_height": 1.1,
		"fog_height_density": 0.12,
		"haze_height": 0.4,
		"sun_color": Color(0.95, 0.68, 0.55),
		"sun_energy": 1.35,
		"ambient_color": Color(0.45, 0.45, 0.47),
		"ambient_energy": 1.75,
		"exposure": 1.35,
		"saturation": 0.6,
		"contrast": 1.22,
		"glow": 0.9,
	})
	Look.weather(self, "embers", 45.0)
	_weather = get_node_or_null("Weather")


# --- Layout ---------------------------------------------------------------------

## Decides where everything goes, in the flat, before there is any ground.
func _plan() -> void:
	for site: Dictionary in SITES:
		var at: Vector2 = site["at"]
		_pads.append({"at": at, "radius": site["radius"], "height": _rolling(at.x, at.y) + site["lift"]})
	for i in PLAYER_SPAWNS:
		var at := Vector2.from_angle(TAU * (i + 0.5) / PLAYER_SPAWNS) * SPAWN_RING
		_pads.append({"at": at, "radius": 9.0, "height": _rolling(at.x, at.y)})
	for army: String in ARMIES:
		var muster: Vector2 = ARMIES[army]["muster"]
		_pads.append({"at": muster, "radius": 13.0, "height": _rolling(muster.x, muster.y)})
	# Jump ramps need level ground.
	for ramp in _ramp_spots():
		var at: Vector2 = ramp["at"]
		_pads.append({"at": at, "radius": 10.0, "height": _rolling(at.x, at.y)})
	_trenches.clear()
	for line: Array in TRENCHES:
		_trenches.append(PackedVector2Array(line))
	for i in CRATERS:
		var radius := _rng.randf_range(6.0, 15.0)
		var at := _free_spot(radius, false)
		_craters.append({"at": at, "radius": radius, "depth": radius * _rng.randf_range(0.16, 0.26)})


## A random point on the field that is clear of every pad (and, when
## `reserve` is true, becomes one itself so nothing else lands on it).
func _free_spot(radius: float, reserve := true, flat := false) -> Vector2:
	var at := Vector2.ZERO
	for attempt in 40:
		at = Vector2(_rng.randf_range(-FIELD + 20.0, FIELD - 20.0), _rng.randf_range(-FIELD + 20.0, FIELD - 20.0))
		var clear := true
		for pad in _pads:
			if at.distance_to(pad["at"]) < float(pad["radius"]) * 1.5 + radius:
				clear = false
				break
		if clear:
			break
	if reserve:
		_pads.append({"at": at, "radius": radius, "height": _rolling(at.x, at.y), "soft": not flat})
	return at


## The lie of the land before anything is dug or levelled.
func _rolling(x: float, z: float) -> float:
	return _noise.get_noise_2d(x, z) * 9.0


func _build_ground() -> void:
	terrain = Terrain.new()
	terrain.name = "Ground"
	terrain.cell = CELL
	terrain.side = SIDE
	_ground_lock.lock()
	if not _ground_shared.has("heights"):
		_shape_ground()
		_ground_shared["collision"] = terrain.collision_data()
		_ground_shared["heights"] = terrain.heights
	var collision: PackedFloat32Array = _ground_shared["collision"]
	terrain.heights = _ground_shared["heights"]
	_ground_lock.unlock()
	terrain.build(Planet.ground_material(planet), collision)
	nav_region.add_child(terrain)
	# The rim is too steep to climb, and these stop anyone flying over it.
	var edge := terrain.extent() * 0.5 - 6.0
	for side: Vector3 in [Vector3(0, 0, -edge), Vector3(0, 0, edge), Vector3(-edge, 0, 0), Vector3(edge, 0, 0)]:
		var wall := StaticBody3D.new()
		wall.collision_layer = Actor.LAYER_WORLD
		wall.collision_mask = 0
		var shape := BoxShape3D.new()
		shape.size = Vector3(edge * 2.0 + 2.0, 600.0, 2.0) if side.x == 0.0 else Vector3(2.0, 600.0, edge * 2.0 + 2.0)
		var col := CollisionShape3D.new()
		col.shape = shape
		wall.add_child(col)
		wall.position = side + Vector3(0, 250.0, 0)
		wall.add_to_group("map_edge")
		add_child(wall)


func _shape_ground() -> void:
	var heights := PackedFloat32Array()
	heights.resize(SIDE * SIDE)
	var half := (SIDE - 1) * CELL * 0.5
	for iz in SIDE:
		for ix in SIDE:
			var x := ix * CELL - half
			var z := iz * CELL - half
			var h := _rolling(x, z) + _noise.get_noise_2d(x * 6.0 + 400.0, z * 6.0) * 1.1
			var out := maxf(absf(x), absf(z))
			h += smoothstep(FIELD, half, out) * RIM_HEIGHT
			heights[iz * SIDE + ix] = h
	terrain.heights = heights
	for crater in _craters:
		_stamp(crater["at"], float(crater["radius"]) * 1.5, func(h: float, d: float) -> float:
			var r: float = crater["radius"]
			var t := d / r
			if t < 1.0:
				return h - float(crater["depth"]) * (1.0 - t * t)
			# The thrown-up lip.
			return h + float(crater["depth"]) * 0.25 * (1.0 - smoothstep(1.0, 1.5, t)))
	for line in _trenches:
		for i in line.size() - 1:
			_stamp_trench(line[i], line[i + 1])
	for road: Array in ROADS:
		for i in road.size() - 1:
			_stamp_road(road[i], road[i + 1])
	for pad in _pads:
		if pad.get("soft", false):
			continue
		var radius: float = pad["radius"]
		_stamp(pad["at"], radius * 1.9, func(h: float, d: float) -> float:
			return lerpf(float(pad["height"]), h, smoothstep(radius, radius * 1.9, d)))
	_grade_works()
	# Last, each road is eased along its length, so a climb (up Signal Hill,
	# off a levelled camp) is a long even grade a bike can take.
	for road: Array in ROADS:
		_ease_road(road)


## Runs `change(height, distance)` over every ground sample within `reach` of `at`.
func _stamp(at: Vector2, reach: float, change: Callable) -> void:
	var half := (SIDE - 1) * CELL * 0.5
	var x0 := maxi(int((at.x - reach + half) / CELL), 0)
	var x1 := mini(int((at.x + reach + half) / CELL) + 1, SIDE - 1)
	var z0 := maxi(int((at.y - reach + half) / CELL), 0)
	var z1 := mini(int((at.y + reach + half) / CELL) + 1, SIDE - 1)
	for iz in range(z0, z1 + 1):
		for ix in range(x0, x1 + 1):
			var d := Vector2(ix * CELL - half, iz * CELL - half).distance_to(at)
			if d <= reach:
				terrain.heights[iz * SIDE + ix] = change.call(terrain.heights[iz * SIDE + ix], d)


## A trench between two points: deep enough to hide in, with sides a soldier
## can still walk up.
func _stamp_trench(a: Vector2, b: Vector2) -> void:
	var half := (SIDE - 1) * CELL * 0.5
	var reach := 6.0
	var x0 := maxi(int((minf(a.x, b.x) - reach + half) / CELL), 0)
	var x1 := mini(int((maxf(a.x, b.x) + reach + half) / CELL) + 1, SIDE - 1)
	var z0 := maxi(int((minf(a.y, b.y) - reach + half) / CELL), 0)
	var z1 := mini(int((maxf(a.y, b.y) + reach + half) / CELL) + 1, SIDE - 1)
	for iz in range(z0, z1 + 1):
		for ix in range(x0, x1 + 1):
			var p := Vector2(ix * CELL - half, iz * CELL - half)
			var d := p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b))
			if d < reach:
				var i := iz * SIDE + ix
				var dug := _rolling(p.x, p.y) - 1.9 * (1.0 - smoothstep(1.5, 4.5, d)) \
						+ 0.5 * smoothstep(4.5, 5.0, d) * (1.0 - smoothstep(5.0, 6.0, d))
				terrain.heights[i] = minf(terrain.heights[i], dug) if d < 4.5 else maxf(terrain.heights[i], dug)


## A road between two points: the lie of the land with the scars taken out
## (craters filled, trenches bridged), blended back into the field at its
## shoulders, so a rover can drive it end to end.
func _stamp_road(a: Vector2, b: Vector2) -> void:
	var half := (SIDE - 1) * CELL * 0.5
	var reach := ROAD_CLEAR + 3.0
	var x0 := maxi(int((minf(a.x, b.x) - reach + half) / CELL), 0)
	var x1 := mini(int((maxf(a.x, b.x) + reach + half) / CELL) + 1, SIDE - 1)
	var z0 := maxi(int((minf(a.y, b.y) - reach + half) / CELL), 0)
	var z1 := mini(int((maxf(a.y, b.y) + reach + half) / CELL) + 1, SIDE - 1)
	for iz in range(z0, z1 + 1):
		for ix in range(x0, x1 + 1):
			var p := Vector2(ix * CELL - half, iz * CELL - half)
			var d := p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b))
			if d < reach:
				var i := iz * SIDE + ix
				terrain.heights[i] = lerpf(_rolling(p.x, p.y), terrain.heights[i], smoothstep(ROAD_CLEAR - 1.5, reach, d))


## Smooths the ground along a road: its height profile is averaged over a
## stretch either way, so no pad's edge or rise is steeper than a bike can
## climb, and laid back down blended into the shoulders. Inside a site the
## site's own ground is left alone.
func _ease_road(road: Array) -> void:
	var points := PackedVector2Array()
	for i in road.size() - 1:
		var a: Vector2 = road[i]
		var b: Vector2 = road[i + 1]
		var steps := maxi(int(a.distance_to(b) / CELL), 1)
		for k in steps:
			points.append(a.lerp(b, float(k) / steps))
	points.append(road[road.size() - 1])
	var profile := PackedFloat32Array()
	for at in points:
		profile.append(terrain.height_at(at.x, at.y))
	for pass_index in 4:
		var eased := profile.duplicate()
		for i in profile.size():
			var total := 0.0
			var count := 0
			for j in range(maxi(i - 6, 0), mini(i + 7, profile.size())):
				total += profile[j]
				count += 1
			eased[i] = total / count
		profile = eased
	var half := (SIDE - 1) * CELL * 0.5
	var reach := ROAD_CLEAR + 3.0
	var best := {}
	for i in points.size() - 1:
		var a := points[i]
		var b := points[i + 1]
		for iz in range(maxi(int((minf(a.y, b.y) - reach + half) / CELL), 0), mini(int((maxf(a.y, b.y) + reach + half) / CELL) + 1, SIDE - 1) + 1):
			for ix in range(maxi(int((minf(a.x, b.x) - reach + half) / CELL), 0), mini(int((maxf(a.x, b.x) + reach + half) / CELL) + 1, SIDE - 1) + 1):
				var p := Vector2(ix * CELL - half, iz * CELL - half)
				var near := Geometry2D.get_closest_point_to_segment(p, a, b)
				var d := p.distance_to(near)
				var cell := iz * SIDE + ix
				if d < reach and (not best.has(cell) or d < float(best[cell][0])):
					var along := clampf(a.distance_to(near) / maxf(a.distance_to(b), 0.001), 0.0, 1.0)
					best[cell] = [d, lerpf(profile[i], profile[i + 1], along)]
	for cell: int in best:
		var p := Vector2((cell % SIDE) * CELL - half, (cell / SIDE) * CELL - half)
		if _site_at(p, -10.0):
			continue
		var d: float = best[cell][0]
		terrain.heights[cell] = lerpf(float(best[cell][1]), terrain.heights[cell], smoothstep(ROAD_CLEAR - 1.5, reach, d))


## How far `at` is from the middle of the nearest road.
func _road_distance(at: Vector2) -> float:
	var best := INF
	for road: Array in ROADS:
		for i in road.size() - 1:
			best = minf(best, at.distance_to(Geometry2D.get_closest_point_to_segment(at, road[i], road[i + 1])))
	return best


## Where each jump ramp stands: on the shoulder of a flank road on its first
## straight out of the camp (well clear of a raised site's slope), on the
## side away from the middle, its high end pointing the way the road runs.
func _ramp_spots() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for index: int in RAMP_ROADS:
		var road: Array = ROADS[index]
		var a: Vector2 = road[0]
		var b: Vector2 = road[1]
		var dir := (b - a).normalized()
		var mid := a.lerp(b, 0.62)
		var side := dir.orthogonal()
		if (mid + side).length() < mid.length():
			side = -side
		out.append({"at": mid + side * 7.0, "dir": dir, "side": side})
	return out


## The straight first stretch of the road from a muster to the middle.
func _runway(army: String) -> Dictionary:
	var muster: Vector2 = ARMIES[army]["muster"]
	for road: Array in ROADS:
		if road[0] == muster and (road[2] as Vector2).length() < 100.0:
			return {"from": road[0], "dir": ((road[1] as Vector2) - (road[0] as Vector2)).normalized()}
	return {"from": muster, "dir": -muster.normalized()}


func _ground(at: Vector2) -> Vector3:
	return terrain.on_ground(at.x, at.y)


# --- Landmarks --------------------------------------------------------------------

func _build_sites() -> void:
	for site: Dictionary in SITES:
		var at: Vector2 = site["at"]
		var radius: float = site["radius"]
		var centre := _ground(at)
		var marker := _add_marker("strongpoint", centre)
		marker.set_meta("name", site["name"])
		marker.set_meta("radius", radius)
		match site["kind"]:
			"foundry":
				# Both armies' elites fight for it, and only in a hot war.
				marker.set_meta("hot_at", FOUNDRY_HOT)
				_build_foundry(at)
				# The Forge stands on the middle: the point bots are sent to
				# hold is the open ground at its foot.
				marker.position = _open(at, 2.0)
			"hill":
				_build_hill(at)
			"graveyard":
				_build_graveyard(at)
			"breach":
				_build_breach(at)
			"carrier":
				_build_carrier(at)
		# The depot sits on the side facing the middle of the map, or north at the middle.
		var inward := -at.normalized() if at.length() > 1.0 else Vector2(0, -1)
		# Its terminal backs away from the site; at the middle, where there is no
		# away, it backs east, across the way in.
		_add_depot(_open(at + inward * (radius - 10.0), 6.0), inward if at.length() > 1.0 else Vector2(1, 0))
		# The army that starts here, its garrison, and a bike for whoever takes the place.
		var army: String = site["army"]
		if army != "":
			marker.set_meta("holder", army)
			marker.set_meta("holder_name", ARMIES[army]["holder_name"])
			for i in 4:
				var post := _add_marker("spawn_bot", _open(at + Vector2.from_angle(TAU * i / 4.0 + 0.6) * radius * 0.45))
				post.set_meta("faction", army)
		# Holding a site pays: its spot has the best odds of a rare vehicle.
		var bike := _add_marker("spawn_vehicle", _open(at - inward.orthogonal() * (radius - 6.0), 2.0))
		bike.rotation.y = atan2(-inward.x, -inward.y)
		bike.set_meta("loot_source", "vehicle_site")
		bike.set_meta("respawn", SITE_VEHICLE_RESPAWN)


## The middle of the map: the shells of a works, tall enough that the best
## loot sits on roofs only a flight rig reaches.
func _build_foundry(at: Vector2) -> void:
	var lots := [Vector2(-16, -12), Vector2(14, -16), Vector2(-18, 14), Vector2(16, 12), Vector2(0, 26)]
	for i in lots.size():
		var h: float = [16.0, 10.0, 10.0, 6.0, 6.0][i]
		_add_building(at + lots[i], Vector3(_rng.randf_range(8.0, 11.0), h, _rng.randf_range(8.0, 11.0)), true)
	# The Forge: the spire everything on the field points at, and a landmark
	# you can steer by from anywhere. Solid all the way up.
	_build_forge(at + FORGE_AT)
	# The stack it replaced drew one number; keep drawing it so the rest of
	# the layout stays where it was.
	_rng.randf()
	for offset: Vector2 in [Vector2(-4, 4), Vector2(18, -30), Vector2(28, -2), Vector2(-30, 0)]:
		_add_cover(_ground(at + offset))
		_add_marker("spawn_cache", _open(at + offset + Vector2(2.5, 1.5)))


func _build_forge(at: Vector2) -> void:
	var base := _ground(at)
	var dark := Look.surface("metal", {"tint": Color(0.5, 0.45, 0.42), "grime": 1.0, "scale": 0.12})
	var y := -1.0
	for tier: Vector2 in FORGE_TIERS:
		var height := tier.y + (1.0 if y < 0.0 else 0.0)
		_box(Vector3(tier.x, height, tier.x), base + Vector3(0, y + height * 0.5, 0), dark if y > 0.0 else WALL)
		y += height
	# A tower on each of the plinth's corners, flanking the keep.
	var corner := FORGE_TIERS[0].x * 0.5 - FORGE_TOWER.x * 0.5
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_box(Vector3(FORGE_TOWER.x, FORGE_TOWER.y, FORGE_TOWER.x),
					base + Vector3(sx * corner, FORGE_TOWER.y * 0.5 - 1.0, sz * corner), dark)
			# The cap the dressing puts on it (`_dress_forge`).
			SolidProp.box(nav_region, Vector3(FORGE_TOWER.x + 0.8, 1.0, FORGE_TOWER.x + 0.8),
					Transform3D(Basis.IDENTITY, base + Vector3(sx * corner, FORGE_TOWER.y - 0.7, sz * corner)))
	# The beacon on the summit.
	SolidProp.box(nav_region, Vector3(2.2, 2.2, 2.2), Transform3D(Basis.IDENTITY, base + Vector3(0, y + 0.8, 0)))
	_buildings.append({"center": base, "size": Vector3(FORGE_TIERS[0].x, y, FORGE_TIERS[0].x), "landmark": true})


## A hill with a relay station on top. Whoever holds it sees half the field.
func _build_hill(at: Vector2) -> void:
	_add_building(at + Vector2(-6, -4), Vector3(8.0, 4.0, 6.0), true)
	_add_building(at + Vector2(8, 6), Vector3(5.0, 3.0, 5.0), false)
	# The mast.
	_add_building(at + Vector2(7, -9), Vector3(1.6, 26.0, 1.6), false)
	for i in 5:
		var spot := at + Vector2.from_angle(TAU * i / 5.0 + 0.3) * 19.0
		_add_wall(_ground(spot), Vector3(6.0, 1.3, 1.0), -Vector2.from_angle(TAU * i / 5.0 + 0.3).angle() + PI * 0.5)
	_add_marker("spawn_cache", _open(at + Vector2(-1, 5)))
	_add_marker("spawn_cache", _open(at + Vector2(12, -2)))


## Where a column of war machines was caught in the open.
func _build_graveyard(at: Vector2) -> void:
	for i in 7:
		var spot := at + Vector2.from_angle(TAU * i / 7.0 + 0.2) * _rng.randf_range(8.0, 26.0)
		_add_wreck(spot, i % 3, _rng.randf_range(0.0, TAU), 1.0 + 0.5 * float(i == 0))
	_add_marker("spawn_cache", _open(at + Vector2(3, 2)))
	_add_marker("spawn_cache", _open(at + Vector2(-14, 10)))
	_add_marker("spawn_cache", _open(at + Vector2(12, -16)))


## A fortified line with a hole blown through it.
func _build_breach(at: Vector2) -> void:
	for i in 7:
		if i == 3:
			continue
		var spot := at + Vector2((i - 3) * 9.0, -22.0 + absf(i - 3) * 2.0)
		_add_wall(_ground(spot), Vector3(8.0, 4.5, 1.6), 0.0)
	_add_building(at + Vector2(-14, 2), Vector3(7.0, 3.0, 6.0), true)
	_add_building(at + Vector2(15, 6), Vector3(6.0, 6.0, 6.0), true)
	for offset: Vector2 in [Vector2(-2, -12), Vector2(4, 14)]:
		_add_cover(_ground(at + offset))
		_add_marker("spawn_cache", _open(at + offset + Vector2(2.0, 2.0)))


## The broken hull of something that fell out of the sky. Its upper decks
## count as rooftops.
func _build_carrier(at: Vector2) -> void:
	var yaw := 0.5
	var along := Vector2(sin(yaw), cos(yaw))
	for i in 3:
		# The hull lies along one side of the site, leaving the middle open.
		var spot := at + along * (i - 1) * 21.0 + along.orthogonal() * ((i - 1) * 3.0 - 15.0)
		var size := Vector3(14.0, [10.0, 15.0, 8.0][i], 19.0)
		var base := _ground(spot)
		var body := _box(size, base + Vector3(0, size.y * 0.5 - 1.0, 0), HULL)
		body.rotation = Vector3(0.05 * (i - 1), yaw, 0.08 * (1 - i))
		_wrecks.append({"at": base, "size": size, "burning": i == 1})
		_buildings.append({"center": base, "size": Vector3(18.0, size.y, 21.0), "wreck": true})
		var deck := _add_marker("spawn_cache", base + Vector3(0, size.y - 0.3, 0))
		deck.set_meta("loot_source", "rooftop")
	# The tail fin still stands over the wreck.
	var fin := _box(Vector3(1.6, 22.0, 9.0), _ground(at + along * 27.0 - along.orthogonal() * 15.0) + Vector3(0, 13.0, 0), HULL_RUST)
	fin.rotation = Vector3(-0.3, yaw, 0.1)
	# A wing, torn off and dug into the ground: a ramp onto the hull.
	var wing := _box(Vector3(7.0, 0.6, 20.0), _ground(at - along.orthogonal() * 30.0) + Vector3(0, 2.6, 0), HULL_RUST)
	wing.rotation = Vector3(0.28, yaw + PI * 0.5, 0.0)
	_add_marker("spawn_cache", _open(at + along.orthogonal() * 12.0))
	_add_cover(_ground(at + along.orthogonal() * 14.0 + along * 6.0))


# --- The rim and the open field ---------------------------------------------------

func _build_spawns() -> void:
	var gates := {}
	for gate: Dictionary in OUTPOSTS:
		gates[gate["spawn"]] = gate["name"]
	for i in PLAYER_SPAWNS:
		var dir := Vector2.from_angle(TAU * (i + 0.5) / PLAYER_SPAWNS)
		var at := dir * SPAWN_RING
		if gates.has(i):
			_build_outpost(at, dir, gates[i])
		else:
			# The other drop points are open ground: a low wall to land behind.
			_add_wall(_ground(at - dir * 6.0), Vector3(6.0, 1.4, 1.0), -dir.angle() + PI * 0.5)
		# At every other drop point a bike.
		if i % 2 == 0:
			var bike := _add_marker("spawn_vehicle", _ground(at + dir.orthogonal() * 7.0))
			bike.rotation.y = atan2(dir.x, dir.y)
			bike.set_meta("loot_source", "vehicle_rim")


## A gate outpost: a walled yard open toward the middle (the gate), with a
## depot at the back and the players' arrival spots. The Raid makes it safe
## from the "outpost" marker.
func _build_outpost(at: Vector2, dir: Vector2, title: String) -> void:
	var marker := _add_marker("outpost", _ground(at))
	marker.set_meta("name", title)
	marker.set_meta("radius", OUTPOST_RADIUS)
	var segments := 12
	for k in segments:
		var angle := TAU * (k + 0.5) / segments
		var out := Vector2.from_angle(angle)
		# Leave the side facing the middle open: that is the gate.
		if out.dot(-dir) > 0.8:
			continue
		var spot := at + out * (OUTPOST_RADIUS + 0.6)
		_add_wall(_ground(spot), Vector3(7.2, 2.4, 0.8), -angle + PI * 0.5)
	# The gate posts either side of the opening.
	for side: float in [-1.0, 1.0]:
		var post := at - dir * (OUTPOST_RADIUS + 0.6) + dir.orthogonal() * side * 4.6
		var base := _ground(post)
		_box(Vector3(1.0, 7.0, 1.0), base + Vector3(0, 3.0, 0), COVER_CONCRETE)
	# A beam across the post tops: the gate's sign hangs from it.
	var beam := _box(Vector3(10.2, 0.8, 1.0), _gate_beam_at(at, dir), COVER_CONCRETE)
	beam.rotation.y = atan2(dir.x, dir.y)
	# The depot at the back of the yard, its terminal against the back wall.
	_add_depot(_ground(at + dir * 7.0), dir)
	for spot: Vector2 in [at + dir.orthogonal() * 4.0, at - dir.orthogonal() * 4.0, at - dir * 3.0]:
		_add_marker("spawn_player", _ground(spot))


## The middle of the beam over an outpost's gate, a little under the lower
## of the two post tops so it sits on both.
func _gate_beam_at(at: Vector2, dir: Vector2) -> Vector3:
	var gate := at - dir * (OUTPOST_RADIUS + 0.6)
	var low := INF
	for side: float in [-1.0, 1.0]:
		low = minf(low, _ground(gate + dir.orthogonal() * side * 4.6).y)
	return Vector3(gate.x, low + 6.1, gate.y)


## Risk zones: caches pay by the zone they stand in (rooftops keep their own
## table), and a warlord holds the core.
func _mark_zones() -> void:
	for node in get_children():
		if not node.is_in_group("spawn_cache") or node.get_meta("loot_source", "cache") != "cache":
			continue
		var out := Vector2(node.position.x, node.position.z).length()
		if out <= CORE_RADIUS:
			node.set_meta("loot_source", "cache_core")
		elif out > MIDDLE_RADIUS:
			node.set_meta("loot_source", "cache_outer")
	var boss := _add_marker("spawn_boss", _open(Vector2(-6, 6), 2.0))
	boss.set_meta("radius", 30.0)
	# He serves neither army: both fight him for the Foundry.
	boss.set_meta("faction", "warlord")


func _build_field() -> void:
	_build_battles()
	_build_routes()
	# Patrols start on their own army's half of the field.
	for i in FIELD_PATROLS:
		var army := "legion" if i % 2 == 0 else "tide"
		var at := _free_spot(5.0)
		for attempt in 30:
			if (at.x < 0.0) == (army == "legion") and absf(at.x) > 30.0:
				break
			_pads.pop_back()
			at = _free_spot(5.0)
		_add_marker("spawn_bot", _open(at)).set_meta("faction", army)
	# Where each army's reinforcements arrive: a camp at the rim.
	for army: String in ARMIES:
		var muster: Vector2 = ARMIES[army]["muster"]
		var inward := -muster.normalized()
		for i in MUSTER_SPOTS:
			var spot := muster + inward.orthogonal() * (i % 3 - 1) * 5.0 + inward * (i / 3) * 5.0
			_add_marker("spawn_bot", _open(spot)).set_meta("faction", army)
		# The camp's wall, split where the runway goes out through it.
		var runway := _runway(army)
		var out: Vector2 = runway["dir"]
		for side: float in [-1.0, 1.0]:
			var post := muster + out * 13.0 + out.orthogonal() * side * (ROAD_CLEAR + 2.5)
			_add_wall(_ground(post), Vector3(4.5, 1.4, 1.0), -out.angle() + PI * 0.5)
		_add_cover(_ground(muster - inward * 7.0))
		# The motor pool: bikes parked nose out along the runway's side.
		for k in MOTOR_POOL:
			var spot := muster + out * (RUNWAY_FROM + 8.0 + k * 7.0) + out.orthogonal() * (ROAD_CLEAR + 3.5)
			var bike := _add_marker("spawn_vehicle", _ground(spot))
			bike.rotation.y = _facing(out)
			bike.set_meta("loot_source", "vehicle_rim")
	for ramp in _ramp_spots():
		var dir: Vector2 = ramp["dir"]
		var side: Vector2 = ramp["side"]
		var at: Vector2 = ramp["at"]
		_add_ramp_lot(_ground(at), _facing(dir), _ground(at + side * 4.0 - dir * 6.0))
	_fortify_front()
	_add_line_posts()


func _add_building(at: Vector2, size: Vector3, lootable: bool) -> void:
	var base := _ground(at)
	var shade := _rng.randf_range(0.26, 0.4)
	var tint := Color(shade, shade * 0.92, shade * 0.88) * 2.4
	var kind := "brick" if size.y <= 6.0 and shade > 0.33 else "concrete"
	# Sunk a little, so no slope shows daylight under a wall.
	var body := _box(size + Vector3(0, 1.5, 0), base + Vector3(0, size.y * 0.5 - 0.75, 0),
			Look.surface(kind, {"tint": tint, "grime": 0.7}))
	Look.make_building(body.get_child(1), size, shade * 100.0)
	_buildings.append({"center": base, "size": size})
	if lootable and size.y >= 6.0:
		var marker := _add_marker("spawn_cache", base + Vector3(0, size.y, 0))
		marker.set_meta("loot_source", "rooftop")


## A length of wall, turned to `yaw`.
func _add_wall(base: Vector3, size: Vector3, yaw: float) -> void:
	var body := _box(size + Vector3(0, 1.0, 0), base + Vector3(0, size.y * 0.5 - 0.5, 0), COVER_CONCRETE)
	body.rotation.y = yaw


## A barricade facing the middle of the map: a short bowed line of jersey
## barriers, sandbag walls and steel plates, so a cover lot reads as a
## position someone held, not boxes dropped at random.
func _add_cover(center: Vector3) -> void:
	var flat := Vector2(center.x, center.z)
	var inward := -flat.normalized() if flat.length() > 1.0 else Vector2(0, -1)
	var along := inward.orthogonal()
	var yaw := atan2(along.x, along.y)
	var count := _rng.randi_range(2, 4)
	for i in count:
		# The draws a lot has always made, so the layout after it stays put.
		var rolled := Vector3(_rng.randf_range(1.2, 3.0), _rng.randf_range(1.0, 1.6), _rng.randf_range(1.2, 3.0))
		var jitter := Vector2(_rng.randf_range(-4.5, 4.5), _rng.randf_range(-4.5, 4.5))
		var slot := i - (count - 1) * 0.5
		var spot := flat + along * (slot * 3.3 + jitter.x * 0.1) - inward * (absf(slot) * 0.8 + jitter.y * 0.08)
		var base := terrain.on_ground(spot.x, spot.y)
		var piece: Dictionary = COVER_PIECES[(i + int(rolled.x * 10.0)) % COVER_PIECES.size()]
		var size: Vector3 = piece["size"]
		size.x = clampf(rolled.x + rolled.z, 2.6, 3.4) if piece["kind"] != "plate" else size.x
		var body := _box(size + Vector3(0, 0.8, 0), base + Vector3(0, size.y * 0.5 - 0.4, 0),
				COVER_CONCRETE if piece["kind"] == "jersey" else COVER_METAL)
		body.rotation.y = yaw
		body.set_meta("cover", piece["kind"])
		_cover_pieces.append(body)
		_cover_spots.append(terrain.on_ground(spot.x - inward.x * 1.2, spot.y - inward.y * 1.2))


## The wreck of a war machine: a tank, a fallen strider, a crashed dropship or
## a titan. Each sits the way it came to rest, not tumbled at random; plain
## boxes that stop bullets, and the dressing adds the rest.
## The kit standing about the field that you bump into (docs/systems/
## worlds-and-war.md "Collision"): tents at each army's muster, a gun dug in
## behind every fourth sandbag wall, and the units on the roofs. Solids on
## the server as on a client, so they are placed from the layout alone, the
## roofs with their own random numbers so nothing else moves.
func _build_field_kit() -> void:
	for army: String in ARMIES:
		var muster: Vector2 = ARMIES[army]["muster"]
		var inward := -muster.normalized()
		for i in 3:
			var spot := muster - inward * 9.0 + inward.orthogonal() * (i - 1) * 7.0
			SolidProp.place(nav_region, "Tent.glb", 4.5, _ground(spot) + Vector3(0, -0.1, 0), atan2(inward.x, inward.y), 1.0)
	var count := 0
	for piece in _cover_pieces:
		if piece.get_meta("cover", "") != "sandbag":
			continue
		count += 1
		if count % 4 != 0:
			continue
		# The wall's face, turned to look over it toward the middle.
		var out := Basis(Vector3.UP, piece.rotation.y).x
		out = Vector3(-out.z, 0, out.x)
		if out.dot(-Vector3(piece.position.x, 0, piece.position.z)) < 0.0:
			out = -out
		var spot := piece.position - out * 1.6
		SolidProp.place(nav_region, "Turret_Gun.glb", 2.2, terrain.on_ground(spot.x, spot.z), atan2(out.x, out.z), 1.0)
	var roofs := RandomNumberGenerator.new()
	roofs.seed = LAYOUT_SEED + 11
	for b in _buildings:
		if b.get("wreck", false) or b.get("landmark", false) or b.get("saw", false):
			continue
		var size: Vector3 = b["size"]
		var top: Vector3 = b["center"] + Vector3(0, size.y, 0)
		if size.x < 4.0:
			continue
		for i in roofs.randi_range(1, 3):
			var file: String = ["AC.glb", "AC_Side.glb", "AC_Stacked.glb", "Antenna_1.glb", "Antenna_2.glb", "Tank.glb"][roofs.randi() % 6]
			var at := top + Vector3(roofs.randf_range(-0.35, 0.35) * size.x, 0, roofs.randf_range(-0.35, 0.35) * size.z)
			SolidProp.place(nav_region, file, 3.2 if file == "Antenna_1.glb" else 1.5, at, roofs.randi() % 4 * PI / 2.0)


func _add_wreck(at: Vector2, kind: int, yaw: float, big: float) -> void:
	var first := nav_region.get_child_count()
	var base := _ground(at)
	var turn := Basis(Vector3.UP, yaw)
	var size := Vector3.ZERO
	match kind:
		0:
			# Tank: a low hull on its tracks, the turret knocked round and the
			# barrel drooping.
			size = Vector3(4.4, 2.0, 8.0) * big
			var settle := Vector2(_rng.randf_range(-0.08, 0.08), _rng.randf_range(-0.1, 0.1)) * 0.3
			var hull := _box(size, base + Vector3(0, size.y * 0.5 - 0.2, 0), HULL)
			hull.rotation = Vector3(settle.x, yaw, settle.y)
			for side: float in [-1.0, 1.0]:
				var track := _box(Vector3(0.9, 1.3, 8.6) * big, base + turn * Vector3(side * (size.x * 0.5 + 0.35 * big), 0.45 * big, 0), HULL_RUST)
				track.rotation = Vector3(settle.x, yaw, settle.y)
			var turret := _box(Vector3(2.8, 1.2, 3.2) * big, base + turn * Vector3(0.0, size.y + 0.3 * big, 0.6 * big), HULL)
			turret.rotation.y = yaw + 0.6
			var barrel := _box(Vector3(0.45, 0.45, 5.0) * big, base + turn * Vector3(1.4 * big, size.y + 0.1 * big, -2.6 * big), HULL)
			barrel.rotation = Vector3(-0.1, yaw + 0.6, 0.0)
		1:
			# Strider: the cockpit on its side, one leg folded up at the knee,
			# the other lying out straight.
			size = Vector3(5.0, 3.6, 6.0) * big
			var body := _box(size, base + Vector3(0, size.y * 0.5 - 0.8, 0), HULL_RUST)
			body.rotation = Vector3(0.0, yaw, 0.38)
			var thigh := _box(Vector3(1.3, 6.0, 1.3) * big, base + turn * Vector3(-3.4, 3.4, 0.6) * big, HULL)
			thigh.rotation = Vector3(0.0, yaw, -0.5)
			var shin := _box(Vector3(1.1, 6.5, 1.1) * big, base + turn * Vector3(-7.4, 4.0, 0.6) * big, HULL)
			shin.rotation = Vector3(0.0, yaw, 0.55)
			var fallen := _box(Vector3(1.1, 1.1, 10.0) * big, base + turn * Vector3(4.4, 0.3, -2.0), HULL)
			fallen.rotation = Vector3(0.0, yaw + 0.5, 0.0)
		3:
			# Titan: a walker the height of a tower block, face down, with
			# two legs still standing where it stopped.
			size = Vector3(15.0, 9.0, 24.0)
			var torso := _box(size, base + Vector3(0, size.y * 0.5 - 1.5, 0), HULL)
			torso.rotation = Vector3(0.1, yaw, -0.07)
			var head := _box(Vector3(7.0, 6.0, 8.0), base + turn * Vector3(1.0, 2.0, -15.5), HULL_RUST)
			head.rotation = Vector3(0.35, yaw + 0.2, 0.1)
			for leg_side: float in [-1.0, 1.0]:
				var shin := _box(Vector3(3.2, 30.0, 3.2), base + turn * Vector3(leg_side * 9.0, 12.0, 19.0 + leg_side * 3.0), HULL)
				shin.rotation = Vector3(0.22 * leg_side, yaw, 0.16 * leg_side)
			var arm := _box(Vector3(2.6, 2.6, 19.0), base + turn * Vector3(-13.0, 0.8, -6.0), HULL_RUST)
			arm.rotation = Vector3(0.05, yaw - 0.5, 0.0)
			var back := _add_marker("spawn_cache", base + Vector3(0, size.y - 0.9, 0))
			back.set_meta("loot_source", "rooftop")
		_:
			# Dropship: came in low, nose first, broke its back on landing and
			# left a furrow behind it.
			size = Vector3(3.6, 3.2, 12.0) * big
			var front := _box(Vector3(size.x, size.y, size.z * 0.55), base + turn * Vector3(0, size.y * 0.5 - 0.9, -size.z * 0.24), HULL)
			front.rotation = Vector3(0.16, yaw, 0.0)
			var back := _box(Vector3(size.x * 0.95, size.y * 0.9, size.z * 0.45), base + turn * Vector3(0.3, size.y * 0.45 - 0.2, size.z * 0.28), HULL_RUST)
			back.rotation = Vector3(-0.05, yaw + 0.12, 0.0)
			for side: float in [-1.0, 1.0]:
				# One wing still on, the other snapped and lying in the dirt.
				var wing := _box(Vector3(4.2, 0.45, 2.8) * big,
						base + turn * Vector3(side * (size.x * 0.5 + 2.0 * big), size.y * 0.5 if side > 0.0 else 0.3, size.z * 0.12), HULL)
				wing.rotation = Vector3(0.0, yaw, -0.12 * side if side > 0.0 else 0.08)
			var fin := _box(Vector3(0.4, 2.6, 2.6) * big, base + turn * Vector3(0.3, size.y + 0.6 * big, size.z * 0.42), HULL_RUST)
			fin.rotation = Vector3(-0.05, yaw + 0.12, 0.0)
			for engine: Transform3D in _wreck_engines(base, yaw, size, big):
				SolidProp.box(nav_region, WRECK_ENGINE * big, engine)
	_wrecks.append({"at": base, "size": size, "burning": _rng.randf() < 0.4, "kind": kind, "yaw": yaw, "big": big, "boxes": _boxes_since(first)})
	_cover_spots.append(_ground(at + Vector2.from_angle(yaw) * (size.x * 0.5 + 2.0)))


## The plain boxes `_box` built under the navigation region since it had
## `first` children: [size, transform, rusty, its mesh] each, for the
## dressing to clad.
func _boxes_since(first: int) -> Array:
	var found := []
	for k in range(first, nav_region.get_child_count()):
		var body := nav_region.get_child(k) as StaticBody3D
		if body == null or body.get_child_count() < 2:
			continue
		var shown := body.get_child(1) as MeshInstance3D
		if shown == null or not shown.mesh is BoxMesh:
			continue
		var box := shown.mesh as BoxMesh
		found.append([box.size, body.transform, box.material == HULL_RUST, shown])
	return found


## Where a dropship wreck's two engines hang off its broken tail.
func _wreck_engines(base: Vector3, yaw: float, size: Vector3, big: float) -> Array[Transform3D]:
	var turn := Basis(Vector3.UP, yaw)
	var tail := Transform3D(Basis.from_euler(Vector3(-0.05, yaw + 0.12, 0.0)), base + turn * Vector3(0.3, size.y * 0.45 - 0.2, size.z * 0.28))
	var out: Array[Transform3D] = []
	for side: float in [-1.0, 1.0]:
		out.append(tail * Transform3D(Basis.IDENTITY, Vector3(side * (size.x * 0.5 + 0.5 * big), 0.2, size.z * 0.15)))
	return out


## Wrecks where the story put them. Each spot is nudged clear of anything
## already placed, and reserved so nothing lands on it later.
func _build_battles() -> void:
	for at: Vector2 in TITAN_SPOTS:
		var spot := _clear_spot(at, 26.0)
		_add_wreck(spot, 3, _facing(-spot) + _rng.randf_range(-0.3, 0.3), 1.0)
	for battle: Dictionary in BATTLES:
		var from: Vector2 = battle["from"]
		var to: Vector2 = battle["to"]
		var count: int = battle["count"]
		var kinds: Array = battle["kinds"]
		var heading := _facing(to - from)
		var side := (to - from).normalized().orthogonal()
		for i in count:
			var t := (i + 0.5) / count
			var stagger := float(battle["spread"]) * (1.0 if i % 2 == 0 else -1.0) * _rng.randf_range(0.4, 1.0)
			var big: float = battle["big"] * _rng.randf_range(0.85, 1.15)
			var spot := _clear_spot(from.lerp(to, t) + side * stagger, 7.0 * big)
			# Most kept their heading; a few slewed round as they were hit.
			var slew := _rng.randf_range(-0.25, 0.25) + (1.2 * signf(stagger) if i % 4 == 3 else 0.0)
			_add_wreck(spot, kinds[i % kinds.size()], heading + slew, big)


## Cover hops on the ways in: along each drop point's spoke toward the core,
## and a checkpoint beside each supply road where it bends. The first hop in
## from each drop point and a third of the rest keep a cache.
func _build_routes() -> void:
	var lots: Array[Vector2] = []
	var outer: Array[bool] = []
	for i in PLAYER_SPAWNS:
		var dir := Vector2.from_angle(TAU * (i + 0.5) / PLAYER_SPAWNS)
		for k in HOPS.size():
			var swing := 0.09 * (1.0 if (i + k) % 2 == 0 else -1.0)
			lots.append(dir.rotated(swing) * float(HOPS[k]))
			outer.append(k == 0)
	for road: Array in ROADS:
		lots.append(road[1])
		outer.append(false)
	var n := 0
	for index in lots.size():
		var at := lots[index]
		if _site_at(at, 8.0):
			continue
		var spot := _clear_spot(at, 6.0)
		_add_cover(_ground(spot))
		# The first hop in from every drop point has something to pick over,
		# so a fresh arrival is never long without a find.
		if outer[index] or n % 3 == 0:
			_add_marker("spawn_cache", _open(spot + Vector2(_rng.randf_range(-3, 3), _rng.randf_range(-3, 3))))
		n += 1


# --- The Works --------------------------------------------------------------------

## The height the whole district is levelled to: a works is built on flat ground.
func _works_level() -> float:
	return (_rolling(0.0, WORKS_FROM) + _rolling(0.0, WORKS_TO)) * 0.5


## Whether `at` is within `margin` of the Works' footprint (street and halls).
func _in_works(at: Vector2, margin: float) -> bool:
	return absf(at.x) < WORKS_REACH + margin and at.y > WORKS_TO - margin and at.y < WORKS_FROM + margin


## The district's ground, levelled (craters filled, rises cut) and blended
## back into the field round it over a long run, so the street's mouth is a
## grade a bike takes.
func _grade_works() -> void:
	var level := _works_level()
	var blend := 22.0
	var half := (SIDE - 1) * CELL * 0.5
	for iz in SIDE:
		var z := iz * CELL - half
		if z < WORKS_TO - blend or z > WORKS_FROM + blend:
			continue
		for ix in SIDE:
			var x := ix * CELL - half
			if absf(x) > WORKS_REACH + blend:
				continue
			var out := maxf(absf(x) - WORKS_REACH, maxf(WORKS_TO - z, z - WORKS_FROM))
			var i := iz * SIDE + ix
			terrain.heights[i] = lerpf(level, terrain.heights[i], smoothstep(0.0, blend, out))


func _build_works() -> void:
	var level := _works_level()
	var deck_y := level + WORKS_DECK - 0.2
	for i in WORKS_HALLS.size():
		var hall: Dictionary = WORKS_HALLS[i]
		var side: float = hall["side"]
		var depth: float = hall["depth"]
		var length: float = float(hall["from"]) - float(hall["to"])
		var base := Vector3(side * (WORKS_STREET + depth * 0.5), level, (float(hall["from"]) + float(hall["to"])) * 0.5)
		var size := Vector3(depth, float(hall["height"]), length)
		if hall.get("shed", false):
			_add_shed(base, size, side)
		else:
			_add_hall(base, size, 0.28 + 0.03 * (i % 4), hall.get("roof_cache", false))
		if hall["roof"] == "saw":
			_add_sawtooth(base + Vector3(0, size.y, 0), size)
			_buildings[_buildings.size() - 1]["saw"] = true
		# Stacks stand on the back corners, away from the street.
		for k in int(hall.get("stacks", 0)):
			var corner := base + Vector3(side * (depth * 0.5 - 2.0), size.y, (length * 0.5 - 2.5) * (1.0 if k == 0 else -1.0))
			_box(Vector3(2.2, 14.0, 2.2), corner + Vector3(0, 7.0, 0), WALL).set_meta("works_stack", true)
	# The catwalks: one along each side's hall fronts.
	for side: float in [-1.0, 1.0]:
		var from := -INF
		var to := INF
		for hall: Dictionary in WORKS_HALLS:
			if hall["side"] == side:
				from = maxf(from, hall["from"])
				to = minf(to, hall["to"])
		_box(Vector3(WORKS_WALK, 0.4, from - to), Vector3(side * (WORKS_STREET - WORKS_WALK * 0.5), deck_y, (from + to) * 0.5), WORKS_METAL)
	# The stairs, running out from the street up the alleys so they never
	# narrow it.
	for stair_at: Vector2 in WORKS_STAIRS:
		var run := 12.0
		var stair := _box(Vector3(Vector2(run, WORKS_DECK).length() + 0.6, 0.4, WORKS_WALK),
				Vector3(stair_at.x * (WORKS_STREET + run * 0.5), level + WORKS_DECK * 0.5 - 0.1, stair_at.y), WORKS_METAL)
		stair.rotation.z = -stair_at.x * atan2(WORKS_DECK, run)
		stair.set_meta("works_stair", true)
	# The gantries across the street, joining the two sides' catwalks.
	for z: float in WORKS_GANTRIES:
		var gantry := _box(Vector3(WORKS_STREET * 2.0 - WORKS_WALK * 2.0 + 0.2, 0.4, 3.0), Vector3(0, deck_y, z), WORKS_METAL)
		gantry.set_meta("works_gantry", true)
	_add_marker("spawn_cache", Vector3(0, deck_y + 0.2, WORKS_GANTRIES[1]))
	# The crossroads' landmark: a gantry crane astride the street, its legs
	# out in the cross street, seen over the roofs from across the field.
	var cross_z := (WORKS_CROSS.x + WORKS_CROSS.y) * 0.5
	var span := WORKS_STREET + 3.0
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_box(Vector3(1.2, 21.0, 1.2), Vector3(sx * span, level + 10.0, cross_z + sz * 3.5), WORKS_METAL)
	for sz: float in [-1.0, 1.0]:
		_box(Vector3(span * 2.0 + 1.2, 1.6, 1.4), Vector3(0, level + 20.4, cross_z + sz * 3.5), WORKS_METAL).set_meta("works_crane", true)
	_box(Vector3(3.0, 2.2, 8.4), Vector3(-2.5, level + 18.5, cross_z), WORKS_METAL)
	# The crane that came down across the street: cover, and a break in the
	# long sight line from the mouth to the Forge.
	var girder := _box(Vector3(1.8, 1.8, 17.0), Vector3(-1.0, level + 0.6, 138.0), WORKS_METAL)
	girder.rotation.y = 0.65
	# Where the district was held: a barricade at each end of the street.
	_add_cover(Vector3(3.0, level, 178.0))
	_add_cover(Vector3(-3.0, level, 112.0))
	# Each army sends soldiers in from here, so the Works never sits empty:
	# one in each shed, at opposite ends and behind walls, so nobody arrives
	# already in the other army's sights.
	_add_marker("spawn_bot", Vector3(-WORKS_STREET - 6.0, level, 186.0)).set_meta("faction", "legion")
	_add_marker("spawn_bot", Vector3(WORKS_STREET + 6.0, level, 115.0)).set_meta("faction", "tide")


## A sawtooth roof on a hall: teeth across it, each a tilted slab rising
## toward the street's inner end with a steep face behind it. Solid, so a
## flyer lands on what they see.
func _add_sawtooth(top: Vector3, size: Vector3) -> void:
	var pitch := 6.0
	var rise := 2.4
	var teeth := maxi(int(size.z / pitch), 1)
	var step := size.z / teeth
	for k in teeth:
		var z0 := top.z + size.z * 0.5 - k * step
		var slab := _box(Vector3(size.x, 0.35, Vector2(step, rise).length()), Vector3(top.x, top.y + rise * 0.5, z0 - step * 0.5), WALL)
		slab.rotation.x = atan2(rise, step)
		_box(Vector3(size.x, rise, 0.3), Vector3(top.x, top.y + rise * 0.5, z0 - step + 0.15), WORKS_METAL)


## A solid factory hall: a block, its roof for whoever can fly up there.
func _add_hall(base: Vector3, size: Vector3, shade: float, roof_cache: bool) -> void:
	var tint := Color(shade, shade * 0.92, shade * 0.88) * 2.4
	var body := _box(size + Vector3(0, 1.5, 0), base + Vector3(0, size.y * 0.5 - 0.75, 0),
			Look.surface("concrete", {"tint": tint, "grime": 0.8}))
	Look.make_building(body.get_child(1), size, shade * 100.0)
	_buildings.append({"center": base, "size": size, "works": true})
	if roof_cache:
		var marker := _add_marker("spawn_cache", base + Vector3(0, size.y, 0))
		marker.set_meta("loot_source", "rooftop")


## An open-fronted shed: back and end walls and a roof, open to the street, so
## there is a floor under cover to fight across (and no flying in it on wings).
func _add_shed(base: Vector3, size: Vector3, side: float) -> void:
	var wall := 0.6
	var back := base + Vector3(side * (size.x * 0.5 - wall * 0.5), 0, 0)
	_box(Vector3(wall, size.y + 1.0, size.z), back + Vector3(0, size.y * 0.5 - 0.5, 0), WALL)
	for end: float in [-1.0, 1.0]:
		var at := base + Vector3(0, 0, end * (size.z * 0.5 - wall * 0.5))
		_box(Vector3(size.x, size.y + 1.0, wall), at + Vector3(0, size.y * 0.5 - 0.5, 0), WALL)
	_box(Vector3(size.x, 0.6, size.z), base + Vector3(0, size.y - 0.3, 0), WALL)
	_buildings.append({"center": base, "size": size, "works": true, "shed": true})
	# Its walls are solids too wide for `_open` to find the floor between.
	_add_marker("spawn_cache", base + Vector3(side * 2.0, 0, 0))


## The heading a wreck has when its nose points along `dir`.
func _facing(dir: Vector2) -> float:
	return atan2(-dir.x, -dir.y)


func _site_at(at: Vector2, margin: float) -> bool:
	for site: Dictionary in SITES:
		if at.distance_to(site["at"]) < float(site["radius"]) + margin:
			return true
	return false


## The open spot nearest `at` that is clear of every pad, site and trench,
## reserved as a pad of `radius` so nothing else lands on it.
func _clear_spot(at: Vector2, radius: float) -> Vector2:
	var best := at
	for ring in 16:
		var found := false
		for step in maxi(ring * 6, 1):
			var spot := at + Vector2.from_angle(TAU * step / maxf(ring * 6.0, 1.0)) * ring * 3.0
			if _spot_clear(spot, radius):
				best = spot
				found = true
				break
		if found:
			break
	_pads.append({"at": best, "radius": radius, "height": _rolling(best.x, best.y), "soft": true})
	return best


func _spot_clear(at: Vector2, radius: float) -> bool:
	if maxf(absf(at.x), absf(at.y)) > FIELD - 20.0:
		return false
	if _in_works(at, radius):
		return false
	if _road_distance(at) < radius * 0.7 + ROAD_CLEAR:
		return false
	for pad in _pads:
		if at.distance_to(pad["at"]) < float(pad["radius"]) * (1.0 if pad.get("soft", false) else 1.5) + radius:
			return false
	for line in _trenches:
		for i in line.size() - 1:
			if at.distance_to(Geometry2D.get_closest_point_to_segment(at, line[i], line[i + 1])) < radius * 0.7 + 5.0:
				return false
	return true


## The skirmish lines' posts: on the fire step of each front trench, just
## behind the sandbags on its lip, every `LINE_POST_EVERY` along it, each
## the army's whose half of the field it is on. Laid after the sandbags, so
## those stand where they were. The lines take turns in the list, so an
## army that mans only a few posts spreads them along its front.
func _add_line_posts() -> void:
	var lines: Array = []
	for index: int in FRONT_LINES:
		var line: PackedVector2Array = _trenches[index]
		var spots: Array[Vector2] = []
		for i in line.size() - 1:
			var a := line[i]
			var b := line[i + 1]
			var along := (b - a).normalized()
			var out := along.orthogonal()
			if out.dot(-(a + b) * 0.5) < 0.0:
				out = -out
			var d := LINE_POST_EVERY * 0.5
			while d < a.distance_to(b):
				var spot := a + along * d + out * 3.5
				if absf(spot.x) > LINE_POST_MIDDLE and _road_distance(spot) > ROAD_CLEAR:
					spots.append(spot)
				d += LINE_POST_EVERY
		lines.append(spots)
	var left := true
	var n := 0
	while left:
		left = false
		for spots: Array in lines:
			if n < spots.size():
				left = true
				var spot: Vector2 = spots[n]
				var post := _add_marker("line_post", _ground(spot))
				post.set_meta("faction", "legion" if spot.x < 0.0 else "tide")
		n += 1


## The front lines, dug in: sandbag walls along the lips of the trenches
## facing no man's land, with gaps to climb out through, and a row of tank
## traps out in front. Placed along the trench lines, not drawn at random,
## and kept clear of every marker and solid already down.
func _fortify_front() -> void:
	var keep_clear: Array[Vector2] = []
	for node in get_children():
		if node is Marker3D or node is Depot:
			keep_clear.append(Vector2(node.position.x, node.position.z))
	var clear := func(spot: Vector2, room: float) -> bool:
		if _road_distance(spot) < ROAD_CLEAR + room:
			return false
		for site: Dictionary in SITES:
			if spot.distance_to(site["at"]) < float(site["radius"]) * 0.8:
				return false
		for pad in _pads:
			if not pad.get("soft", false) and spot.distance_to(pad["at"]) < float(pad["radius"]) + room:
				return false
		for mark in keep_clear:
			if spot.distance_to(mark) < room + 2.5:
				return false
		for solid in _solids:
			if spot.distance_to(solid["at"]) < float(solid["reach"]) + room:
				return false
		return true
	for index: int in FRONT_LINES:
		var line: PackedVector2Array = _trenches[index]
		var walked := SANDBAG_EVERY * 0.5
		for i in line.size() - 1:
			var a := line[i]
			var b := line[i + 1]
			var along := (b - a).normalized()
			var out := along.orthogonal()
			if out.dot(-(a + b) * 0.5) < 0.0:
				out = -out
			var length := a.distance_to(b)
			var yaw := atan2(along.x, along.y)
			# Sandbags on the lip toward the enemy.
			var d := walked
			while d < length:
				var spot := a + along * d + out * 5.2
				if clear.call(spot, 1.8):
					var base := terrain.on_ground(spot.x, spot.y)
					var wall := _box(Vector3(3.4, 1.0 + 0.6, 0.9), base + Vector3(0, 0.5 - 0.3, 0), WALL)
					wall.rotation.y = yaw
					wall.set_meta("cover", "sandbag")
					_cover_pieces.append(wall)
				d += SANDBAG_EVERY
			walked = d - length
			# Tank traps out in front, every third one left out for a lane.
			var k := 0
			var t := TRAP_EVERY * 0.5
			while t < length:
				var spot := a + along * t + out * TRAP_OFFSET
				if k % 3 != 2 and clear.call(spot, 1.2):
					var base := terrain.on_ground(spot.x, spot.y)
					var trap := _box(Vector3(1.5, 1.2, 1.5), base + Vector3(0, 0.5, 0), HULL)
					trap.rotation.y = yaw + 0.4 * k
					trap.set_meta("cover", "trap")
					_cover_pieces.append(trap)
				k += 1
				t += TRAP_EVERY


## A jump ramp facing `yaw`, with a bike marker parked at `park`.
func _add_ramp_lot(center: Vector3, yaw: float, park: Vector3) -> void:
	var angle := deg_to_rad(RAMP_ANGLE_DEG)
	var thickness := 0.4
	var body := StaticBody3D.new()
	body.collision_layer = Actor.LAYER_WORLD
	body.collision_mask = 0
	# Sit the low end flush with the ground; the high end lifts toward -Z.
	body.position = center + Vector3(0, RAMP_LENGTH * 0.5 * sin(angle) - thickness * 0.5 * cos(angle), 0)
	body.basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, angle)
	var size := Vector3(4.0, thickness, RAMP_LENGTH)
	var shape := BoxShape3D.new()
	shape.size = size
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = Look.surface("metal", {"tint": Color(0.75, 0.55, 0.3), "scale": 0.5})
	var mesh_node := MeshInstance3D.new()
	mesh_node.mesh = mesh
	body.add_child(mesh_node)
	nav_region.add_child(body)
	# Parked off the road behind the low end, pointing up the ramp.
	var marker := _add_marker("spawn_vehicle", park)
	marker.rotation.y = yaw


## A depot whose uplink terminal stands on the `back` side of its pad (a
## direction on the ground; zero leaves it on the +Z side).
func _add_depot(at: Vector3, back := Vector2.ZERO) -> void:
	var zone := Depot.new()
	zone.add_to_group("depot")
	zone.position = at + Vector3(0, 2.0, 0)
	if back != Vector2.ZERO:
		zone.rotation.y = atan2(back.x, back.y)
	add_child(zone)


func _add_marker(group: String, at: Vector3) -> Marker3D:
	var marker := Marker3D.new()
	marker.add_to_group(group)
	marker.position = at
	add_child(marker)
	return marker


func _box(size: Vector3, at: Vector3, material: Material) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = Actor.LAYER_WORLD
	body.collision_mask = 0
	body.position = at
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
	_solids.append({"at": Vector2(at.x, at.z), "reach": Vector2(size.x, size.z).length() * 0.5})
	return body


## The ground at the open spot nearest to `at`: clear of every wall and wreck
## built so far, with `room` metres to spare.
func _open(at: Vector2, room := 1.2) -> Vector3:
	for ring in 12:
		for step in maxi(ring * 6, 1):
			var spot := at + Vector2.from_angle(TAU * step / maxf(ring * 6.0, 1.0)) * ring * 1.5
			var clear := true
			for solid in _solids:
				if spot.distance_to(solid["at"]) < float(solid["reach"]) + room:
					clear = false
					break
			if clear:
				return _ground(spot)
	return _ground(at)


# --- Dressing ---------------------------------------------------------------------

## Everything below is decoration: no collision, nothing the game depends on.
func _dress() -> void:
	if not Look.enabled:
		return
	var art := Node3D.new()
	art.name = "Dressing"
	add_child(art)
	_dress_rooftops(art)
	_dress_field(art)
	_dress_fires(art)
	_dress_core(art)
	_dress_forge(art)
	_dress_wrecks(art)
	_dress_cover(art)
	_dress_cracks(art)
	_dress_roads(art)
	_dress_outposts(art)
	_dress_works(art)
	_dress_horizon(art)


## The Works dressed as a working district gone dark: a teal band under each
## roof, a few windows still lit over the street, glazing in the sawtooth
## teeth, hazard-striped kick plates and railings on the catwalks and
## gantries, work lights in the sheds, smoke from the stacks, and the crane
## striped with a warning lamp on top.
func _dress_works(art: Node3D) -> void:
	var level := _works_level()
	var teal := Look.trim("band")
	var hazard := Look.trim("hazard")
	var lit := Look.trim("orange")
	for hall: Dictionary in WORKS_HALLS:
		var side: float = hall["side"]
		var depth: float = hall["depth"]
		var height: float = hall["height"]
		var length: float = float(hall["from"]) - float(hall["to"])
		var base := Vector3(side * (WORKS_STREET + depth * 0.5), level, (float(hall["from"]) + float(hall["to"])) * 0.5)
		if hall.get("shed", false):
			# Work lights under the roof, and the open front's edge striped.
			var lamp := OmniLight3D.new()
			lamp.light_color = Color(1.0, 0.62, 0.32)
			lamp.light_energy = 2.2
			lamp.omni_range = maxf(depth, length) * 0.8
			lamp.position = base + Vector3(0, height - 1.6, 0)
			art.add_child(lamp)
			for k in 3:
				var at := base + Vector3(0, height - 0.9, (k - 1) * length * 0.3)
				art.add_child(_slab(Vector3(depth * 0.5, 0.12, 0.35), at, lit))
			art.add_child(_slab(Vector3(0.1, 0.5, length), base + Vector3(-side * depth * 0.5, height - 0.85, 0), hazard))
			continue
		art.add_child(_slab(Vector3(depth + 0.12, 0.3, length + 0.12), base + Vector3(0, height - 1.0, 0), teal))
		# Windows over the street, above the catwalk; most are dark now.
		var face := side * (WORKS_STREET - 0.03)
		var rows := int((height - WORKS_DECK - 2.5) / 3.0)
		for row in rows:
			var y := level + WORKS_DECK + 2.4 + row * 3.0
			var count := int(length / 4.0)
			for k in count:
				if _art_rng.randf() < 0.7:
					continue
				var z := base.z - length * 0.5 + (k + 0.5) * length / count
				art.add_child(_slab(Vector3(0.06, 0.9, 1.8), Vector3(face, y, z), lit))
		if hall["roof"] == "saw":
			var teeth := maxi(int(length / 6.0), 1)
			var step := length / teeth
			for k in teeth:
				var z0 := base.z + length * 0.5 - k * step
				art.add_child(_slab(Vector3(depth - 1.2, 1.3, 0.06), Vector3(base.x, level + height + 1.2, z0 - step - 0.03), teal))
		for k in int(hall.get("stacks", 0)):
			var corner := base + Vector3(side * (depth * 0.5 - 2.0), height, (length * 0.5 - 2.5) * (1.0 if k == 0 else -1.0))
			art.add_child(_slab(Vector3(2.4, 0.4, 2.4), corner + Vector3(0, 11.5, 0), teal))
			art.add_child(_smoke(corner + Vector3(0, 14.5, 0), 0.8))
	# Kick plates and railings: down the street edge of both catwalks and
	# along both sides of each gantry.
	var deck := level + WORKS_DECK
	var rails: Array[PackedVector3Array] = []
	for side: float in [-1.0, 1.0]:
		var from := -INF
		var to := INF
		for hall: Dictionary in WORKS_HALLS:
			if hall["side"] == side:
				from = maxf(from, hall["from"])
				to = minf(to, hall["to"])
		var x := side * (WORKS_STREET - WORKS_WALK) - side * 0.05
		# The rail breaks where a gantry joins.
		var cuts: Array[float] = [to]
		for z: float in WORKS_GANTRIES:
			cuts.append(z - 1.5)
			cuts.append(z + 1.5)
		cuts.append(from)
		for k in range(0, cuts.size(), 2):
			rails.append(PackedVector3Array([Vector3(x, deck, cuts[k]), Vector3(x, deck, cuts[k + 1])]))
	for z: float in WORKS_GANTRIES:
		for sz: float in [-1.0, 1.0]:
			var w := WORKS_STREET - WORKS_WALK
			rails.append(PackedVector3Array([Vector3(-w, deck, z + sz * 1.45), Vector3(w, deck, z + sz * 1.45)]))
	for rail in rails:
		var a := rail[0]
		var b := rail[1]
		var along := b - a
		var mid := (a + b) * 0.5
		var span := Vector3(absf(along.x), 0, absf(along.z))
		var thin := Vector3(0.06, 0, 0.06)
		art.add_child(_slab(Vector3(maxf(span.x, 0.06), 0.3, maxf(span.z, 0.06)), mid + Vector3(0, 0.15, 0), hazard))
		art.add_child(_slab(Vector3(maxf(span.x, thin.x), 0.07, maxf(span.z, thin.z)), mid + Vector3(0, 1.05, 0), WORKS_METAL))
		var posts := maxi(int(along.length() / 2.5), 1)
		for k in posts + 1:
			art.add_child(_slab(Vector3(0.07, 1.05, 0.07), a.lerp(b, float(k) / posts) + Vector3(0, 0.52, 0), WORKS_METAL))
	# The crane: striped beams, a band round each leg, a hook hanging over
	# the crossroads and a warning lamp that can be seen across the field.
	var cross_z := (WORKS_CROSS.x + WORKS_CROSS.y) * 0.5
	var span_x := WORKS_STREET + 3.0
	for sz: float in [-1.0, 1.0]:
		art.add_child(_slab(Vector3(span_x * 2.0, 0.5, 1.45), Vector3(0, level + 21.0, cross_z + sz * 3.5), hazard))
		for sx: float in [-1.0, 1.0]:
			art.add_child(_slab(Vector3(1.35, 0.3, 1.35), Vector3(sx * span_x, level + 7.0, cross_z + sz * 3.5), teal))
	art.add_child(_slab(Vector3(0.08, 9.0, 0.08), Vector3(-2.5, level + 13.0, cross_z), WORKS_METAL))
	art.add_child(_slab(Vector3(1.0, 0.9, 0.7), Vector3(-2.5, level + 8.2, cross_z), hazard, true))
	var warn := _slab(Vector3(0.5, 0.5, 0.5), Vector3(span_x, level + 21.6, cross_z), Look.trim("beacon"))
	art.add_child(warn)



func _dress_rooftops(art: Node3D) -> void:
	for b in _buildings:
		if b.get("wreck", false) or b.get("landmark", false) or b.get("saw", false):
			continue
		var size: Vector3 = b["size"]
		var top: Vector3 = b["center"] + Vector3(0, size.y, 0)
		if size.x < 4.0:
			continue
		# A parapet so roofs do not end in a knife edge.
		var rim := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(size.x + 0.3, 0.35, size.z + 0.3)
		mesh.material = WALL
		rim.mesh = mesh
		rim.position = top + Vector3(0, -0.1, 0)
		art.add_child(rim)


## Litter of a long war, left where people were: kit behind the cover they
## held. The tents and dug-in guns are solids (`_build_field_kit`).
func _dress_field(art: Node3D) -> void:
	var litter := ["GasCan.glb", "PropaneTank.glb", "Trashcan.glb", "Backpack.glb", "Computer.glb", "Support.glb"]
	for spot in _cover_spots:
		if _art_rng.randf() < 0.5:
			continue
		var file: String = litter[_art_rng.randi() % litter.size()]
		var p := Look.prop(file, _art_rng.randf_range(0.5, 0.9), 0.9)
		p.position = spot
		p.rotation.y = _art_rng.randf() * TAU
		art.add_child(p)


## The core reads as dangerous from across the field: molten slag pooled
## between the works, a red glow under the smoke and heat haze over it all.
## Decoration only; the burn itself is `hazard_at` in the world.
func _dress_core(art: Node3D) -> void:
	var slag := StandardMaterial3D.new()
	slag.albedo_color = Color(0.25, 0.06, 0.02)
	slag.emission_enabled = true
	slag.emission = Color(1.0, 0.36, 0.08)
	slag.emission_energy_multiplier = 2.6
	slag.roughness = 0.35
	for i in 16:
		var at := Vector2.from_angle(_art_rng.randf() * TAU) * _art_rng.randf_range(8.0, CORE_RADIUS - 6.0)
		if _under_building(at, 5.0):
			continue
		var pool := MeshInstance3D.new()
		var disc := CylinderMesh.new()
		var width := _art_rng.randf_range(2.5, 5.5)
		disc.top_radius = width
		disc.bottom_radius = width
		disc.height = 0.1
		disc.material = slag
		pool.mesh = disc
		pool.scale = Vector3(1.0, 1.0, _art_rng.randf_range(0.5, 1.0))
		pool.rotation.y = _art_rng.randf() * TAU
		pool.position = _ground(at) + Vector3(0, 0.06, 0)
		pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		art.add_child(pool)
		var glow := OmniLight3D.new()
		glow.light_color = Color(1.0, 0.42, 0.15)
		glow.light_energy = 2.2
		glow.omni_range = width * 3.0
		glow.position = pool.position + Vector3(0, 1.2, 0)
		art.add_child(glow)
	for i in 4:
		var at := Vector2.from_angle(TAU * i / 4.0 + 0.4) * CORE_RADIUS * 0.6
		art.add_child(_smoke(_ground(at) + Vector3(0, 1.0, 0), 5.0))
	# The rim of the core: a line of glowing cracks you see before you cross it,
	# each laid on the ground where it lies.
	var scorch := StandardMaterial3D.new()
	scorch.albedo_color = Color(0.08, 0.04, 0.03)
	scorch.emission_enabled = true
	scorch.emission = Color(0.9, 0.24, 0.05)
	scorch.emission_energy_multiplier = 1.2
	var crack := BoxMesh.new()
	crack.size = Vector3(0.7, 0.12, 3.2)
	crack.material = scorch
	for k in 72:
		var angle := TAU * k / 72.0 + _art_rng.randf_range(-0.01, 0.01)
		var at := Vector2.from_angle(angle) * CORE_RADIUS
		if _blocked(at):
			continue
		var piece := MeshInstance3D.new()
		piece.mesh = crack
		piece.position = _ground(at) + Vector3(0, 0.02, 0)
		piece.rotation.y = -angle
		piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		art.add_child(piece)


## Gate outposts read as a sheltered yard without any overlay: a sign hung
## from the gate beam, its name and rule on the outer face and what waits
## outside on the inner one; shield emitters on the post tops and lamps along
## the walls, all in a calm green; and the line where the bubble ends, laid
## across the gate's mouth as a lit, striped threshold between two emitter
## bollards. The line follows the bubble's own radius, so crossing it is
## exactly where protection stops.
func _dress_outposts(art: Node3D) -> void:
	var green := Color(0.4, 1.0, 0.6)
	var glow := StandardMaterial3D.new()
	glow.albedo_color = green * 0.3
	glow.emission_enabled = true
	glow.emission = green
	glow.emission_energy_multiplier = 2.0
	var plate_mat := Look.surface("metal", {"tint": Color(0.22, 0.24, 0.23), "scale": 0.5, "grime": 0.6})
	for node in get_children():
		if not node.is_in_group("outpost"):
			continue
		var at := Vector2(node.position.x, node.position.z)
		var dir := at.normalized()
		var title := str(node.get_meta("name", "Outpost")).to_upper()
		var radius := float(node.get_meta("radius", OUTPOST_RADIUS))
		# The sign under the beam.
		var beam := _gate_beam_at(at, dir)
		var panel := MeshInstance3D.new()
		var board := BoxMesh.new()
		board.size = Vector3(7.6, 1.5, 0.16)
		board.material = plate_mat
		panel.mesh = board
		panel.position = beam - Vector3(0, 1.3, 0)
		panel.rotation.y = atan2(dir.x, dir.y)
		art.add_child(panel)
		for strip_y: float in [0.71, -0.71]:
			var trim := MeshInstance3D.new()
			var edge := BoxMesh.new()
			edge.size = Vector3(7.6, 0.06, 0.2)
			edge.material = glow
			trim.mesh = edge
			trim.position = panel.position + Vector3(0, strip_y, 0)
			trim.rotation.y = panel.rotation.y
			trim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			art.add_child(trim)
		# Outside (facing the field, -dir) and inside (facing the yard, +dir).
		for face: Array in [
				[-dir, title, "SAFE ZONE · WEAPONS LOCKED"],
				[dir, title, "LEAVING SAFE ZONE · WEAPONS FREE PAST THE LINE"]]:
			var normal: Vector2 = face[0]
			var yaw := atan2(normal.x, normal.y)
			var front := panel.position + Vector3(normal.x, 0, normal.y) * 0.1
			art.add_child(_gate_label(face[1], front + Vector3(0, 0.25, 0), yaw, 56, Color(0.7, 1.0, 0.8)))
			art.add_child(_gate_label(face[2], front + Vector3(0, -0.4, 0), yaw, 30, Color(0.9, 0.92, 0.88)))
		# Shield emitters on the post tops: a lit head on each.
		var ortho := dir.orthogonal()
		for side: float in [-1.0, 1.0]:
			var post := at - dir * (radius + 0.6) + ortho * side * 4.6
			var top := _ground(post) + Vector3(0, 6.6, 0)
			var head := MeshInstance3D.new()
			var cell := CylinderMesh.new()
			cell.top_radius = 0.35
			cell.bottom_radius = 0.5
			cell.height = 0.5
			cell.material = glow
			head.mesh = cell
			head.position = top
			head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			art.add_child(head)
			var lamp := Look.lamp(green, 2.0, 14.0)
			lamp.position = top + Vector3(0, 0.4, 0)
			art.add_child(lamp)
		# Lamps along the wall tops, on the yard side, every other segment.
		for k in 12:
			var angle := TAU * (k + 0.5) / 12.0
			var out := Vector2.from_angle(angle)
			if out.dot(-dir) > 0.8 or k % 2 == 1:
				continue
			var spot := at + out * (radius + 0.6 - 0.5)
			var fitting := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(0.6, 0.18, 0.22)
			box.material = glow
			fitting.mesh = box
			fitting.position = _ground(spot) + Vector3(0, 2.25, 0)
			fitting.rotation.y = -angle + PI * 0.5
			fitting.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			art.add_child(fitting)
		# The line where the bubble ends, across the open gate: hazard stripes
		# with a lit edge on the yard side, laid on the ground along the arc.
		var reach := deg_to_rad(32.0)
		var middle := (-dir).angle()
		var pieces := 14
		for k in pieces + 1:
			var angle := middle - reach + 2.0 * reach * k / pieces
			var out := Vector2.from_angle(angle)
			var spot := at + out * radius
			var stripe := MeshInstance3D.new()
			var slab := BoxMesh.new()
			slab.size = Vector3(radius * 2.0 * reach / pieces + 0.05, 0.08, 0.5)
			slab.material = Look.trim("hazard")
			stripe.mesh = slab
			stripe.position = _ground(spot) + Vector3(0, 0.03, 0)
			stripe.rotation.y = -angle + PI * 0.5
			stripe.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			art.add_child(stripe)
			var lit := MeshInstance3D.new()
			var line := BoxMesh.new()
			line.size = Vector3(slab.size.x, 0.06, 0.12)
			line.material = glow
			lit.mesh = line
			lit.position = _ground(at + out * (radius - 0.35)) + Vector3(0, 0.04, 0)
			lit.rotation.y = stripe.rotation.y
			lit.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			art.add_child(lit)
		# A bollard with an emitter cap at each end of the line.
		for end: float in [-1.0, 1.0]:
			var spot := at + Vector2.from_angle(middle + end * (reach + 0.04)) * radius
			var foot := _ground(spot)
			var bollard := MeshInstance3D.new()
			var pole := BoxMesh.new()
			pole.size = Vector3(0.35, 1.3, 0.35)
			pole.material = Look.trim("hazard")
			bollard.mesh = pole
			bollard.position = foot + Vector3(0, 0.6, 0)
			bollard.set_meta("walk_through", "a slim emitter post marking the line")
			art.add_child(bollard)
			var cap := MeshInstance3D.new()
			var lens := BoxMesh.new()
			lens.size = Vector3(0.4, 0.2, 0.4)
			lens.material = glow
			cap.mesh = lens
			cap.position = foot + Vector3(0, 1.35, 0)
			cap.set_meta("walk_through", "the lamp on an emitter post")
			cap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			art.add_child(cap)


## One face of a gate sign: printed on the board, readable from its front only.
func _gate_label(text: String, at: Vector3, yaw: float, size: int, color: Color) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font_size = size
	label.pixel_size = 0.01
	label.outline_size = 0
	label.modulate = color
	label.double_sided = false
	label.position = at
	label.rotation.y = yaw
	return label


## Whether a point is within `margin` metres of a building's footprint.
func _under_building(at: Vector2, margin: float) -> bool:
	for b in _buildings:
		var size: Vector3 = b["size"]
		var c: Vector3 = b["center"]
		if absf(at.x - c.x) < size.x * 0.5 + margin and absf(at.y - c.z) < size.z * 0.5 + margin:
			return true
	return false


## Some wrecks still burn: a fire, its light, and smoke that leans downwind.
func _dress_fires(art: Node3D) -> void:
	var lit := 0
	for wreck in _wrecks:
		if not wreck["burning"]:
			continue
		var size: Vector3 = wreck["size"]
		var at: Vector3 = wreck["at"] + Vector3(_art_rng.randf_range(-1.0, 1.0), size.y * 0.7, _art_rng.randf_range(-1.0, 1.0))
		art.add_child(_smoke(at, size.x * 0.35))
		var fire := Look.prop("Bonfire.glb", 1.6, 0.3)
		fire.position = at
		art.add_child(fire)
		if lit < 16:
			lit += 1
			var glow := Look.lamp(Color(1.0, 0.45, 0.15), 7.0, 22.0)
			glow.position = at + Vector3(0, 1.2, 0)
			art.add_child(glow)


func _smoke(at: Vector3, width: float) -> GPUParticles3D:
	var smoke := GPUParticles3D.new()
	smoke.amount = 36
	smoke.lifetime = 14.0
	smoke.preprocess = 14.0
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = width
	mat.direction = Vector3(0.35, 1, 0.12)
	mat.spread = 10.0
	mat.gravity = Vector3(0.5, 0.15, 0.2)
	mat.initial_velocity_min = 2.5
	mat.initial_velocity_max = 4.0
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.25))
	grow.add_point(Vector2(1.0, 1.0))
	var grow_tex := CurveTexture.new()
	grow_tex.curve = grow
	mat.scale_curve = grow_tex
	var fade := Gradient.new()
	fade.set_color(0, Color(0.9, 0.35, 0.1, 0.0))
	fade.add_point(0.06, Color(0.32, 0.14, 0.08, 0.6))
	fade.add_point(0.4, Color(0.09, 0.08, 0.08, 0.5))
	fade.set_color(fade.get_point_count() - 1, Color(0.06, 0.06, 0.06, 0.0))
	var fade_tex := GradientTexture1D.new()
	fade_tex.gradient = fade
	mat.color_ramp = fade_tex
	var quad := QuadMesh.new()
	quad.size = Vector2(13, 13)
	var draw := StandardMaterial3D.new()
	draw.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	draw.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	draw.vertex_color_use_as_albedo = true
	draw.albedo_texture = Look._soft_dot()
	quad.material = draw
	smoke.process_material = mat
	smoke.draw_pass_1 = quad
	smoke.visibility_aabb = AABB(Vector3(-40, -5, -40), Vector3(80, 90, 80))
	smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	smoke.position = at
	return smoke


## True if a building or wreck covers `at`, or it is on a landmark.
func _blocked(at: Vector2) -> bool:
	for site: Dictionary in SITES:
		if at.distance_to(site["at"]) < float(site["radius"]):
			return true
	if _under_building(at, 1.0):
		return true
	for w in _wrecks:
		var c: Vector3 = w["at"]
		if at.distance_to(Vector2(c.x, c.z)) < 10.0:
			return true
	return false


## The Forge dressed: a teal band at the top of each tier, a furnace mouth
## glowing on every face of the plinth, molten metal pouring down two faces,
## smoke from its shoulders and the red beacon on the needle.
func _dress_forge(art: Node3D) -> void:
	var base := _ground(FORGE_AT)
	var y := -1.0
	var teal := Look.trim("teal")
	for tier: Vector2 in FORGE_TIERS:
		var height := tier.y + (1.0 if y < 0.0 else 0.0)
		y += height
		art.add_child(_slab(Vector3(tier.x + 0.64, 0.35, tier.x + 0.64), base + Vector3(0, y - 0.9, 0), teal))
	var plinth: Vector2 = FORGE_TIERS[0]
	var tower: Vector2 = FORGE_TIERS[1]
	# Clad in kit panels and posts, so it reads as built, not a plain block;
	# each face of the plinth left open in the middle for the furnace mouth.
	var kit := KitMesh.new()
	var clad_rng := RandomNumberGenerator.new()
	clad_rng.seed = LAYOUT_SEED + 23
	KIT_DRESS.forge(kit, base, FORGE_TIERS, FORGE_TOWER, FORGE_MOUTH, clad_rng)
	art.add_child(kit.node("ForgeClad", {
		"plate": Look.surface("metal", {"tint": Color(0.9, 0.8, 0.7), "grime": 1.0, "scale": 0.08}),
		"dark": Look.surface("metal", {"tint": Color(0.46, 0.42, 0.39), "grime": 1.0, "scale": 0.08}),
		"glow": Look.trim("orange"),
	}, ["plate", "dark", "glow"]))
	art.add_child(_slab(Vector3(plinth.x + 0.64, 0.7, plinth.x + 0.64), base + Vector3(0, plinth.y - 1.6, 0), Look.trim("hazard")))
	for k in 4:
		var face := Vector3.FORWARD.rotated(Vector3.UP, k * PI * 0.5)
		var mouth := _slab(Vector3(FORGE_MOUTH.x, FORGE_MOUTH.y - 0.4, 0.2), base + face * (plinth.x * 0.5 + 0.05) + Vector3(0, (FORGE_MOUTH.y - 0.4) * 0.5, 0), Look.trim("orange"))
		mouth.rotation.y = k * PI * 0.5
		art.add_child(mouth)
		var glow := Look.lamp(Color(1.0, 0.45, 0.15), 4.0, 24.0)
		glow.position = base + face * (plinth.x * 0.5 + 3.0) + Vector3(0, 2.5, 0)
		art.add_child(glow)
		if k % 2 == 0:
			# The pour, beside the furnace mouth: down the tower, across the
			# plinth's roof and over its lip to the ground.
			var slag := Look.trim("slag")
			var aside := face.cross(Vector3.UP) * 2.6
			var parts := [
				[Vector3(1.5, tower.y - 4.0, 0.16), face * (tower.x * 0.5 + 0.24) + Vector3(0, plinth.y - 1.0 + (tower.y - 4.0) * 0.5, 0)],
				[Vector3(1.5, 0.25, (plinth.x - tower.x) * 0.5 + 0.3), face * ((plinth.x + tower.x) * 0.25 + 0.1) + Vector3(0, plinth.y - 0.85, 0)],
				[Vector3(1.6, plinth.y - 1.0, 0.16), face * (plinth.x * 0.5 + 0.24) + Vector3(0, (plinth.y - 1.0) * 0.5, 0)],
			]
			for part: Array in parts:
				var pour := _slab(part[0], base + aside + part[1], slag)
				pour.rotation.y = k * PI * 0.5
				art.add_child(pour)
	# Each corner tower capped, with a furnace slit near the top facing out.
	var corner := plinth.x * 0.5 - FORGE_TOWER.x * 0.5
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var top := base + Vector3(sx * corner, FORGE_TOWER.y - 1.0, sz * corner)
			art.add_child(_slab(Vector3(FORGE_TOWER.x + 0.8, 1.0, FORGE_TOWER.x + 0.8), top + Vector3(0, 0.3, 0), WALL, true))
			art.add_child(_slab(Vector3(FORGE_TOWER.x + 0.1, 0.3, FORGE_TOWER.x + 0.1), top + Vector3(0, -2.0, 0), teal))
			for out: Vector3 in [Vector3(sx, 0, 0), Vector3(0, 0, sz)]:
				var slit := _slab(Vector3(0.5, 3.0, 0.5), top + out * (FORGE_TOWER.x * 0.5) + Vector3(0, -5.0, 0), Look.trim("orange"))
				art.add_child(slit)
	for side: float in [-1.0, 1.0]:
		art.add_child(_smoke(base + Vector3(side * tower.x * 0.4, plinth.y + tower.y - 1.0, -side * tower.x * 0.4), 2.0))
	_beacon = _slab(Vector3(2.2, 2.2, 2.2), base + Vector3(0, y + 0.8, 0), Look.trim("beacon"))
	art.add_child(_beacon)
	# The halo that finds the beacon from the rim, through the smoke.
	var halo := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(16, 16)
	quad.material = Look.trim("halo")
	halo.mesh = quad
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Seen from anywhere on the map: never faded out with the small props.
	halo.visibility_range_end = FAR_SIGHT
	_beacon.visibility_range_end = FAR_SIGHT
	_beacon.add_child(halo)
	# The Forge lights the ground round it, warmest at its foot.
	var heat := Look.lamp(Color(1.0, 0.42, 0.14), 2.2, 70.0)
	heat.position = base + Vector3(0, 14.0, 0)
	art.add_child(heat)
	# Two searchlights on opposite corner towers, sweeping the sky slowly.
	var reach := plinth.x * 0.5 - FORGE_TOWER.x * 0.5
	for sign: float in [-1.0, 1.0]:
		var pivot := Node3D.new()
		pivot.position = base + Vector3(sign * reach, FORGE_TOWER.y + 0.5, sign * reach)
		pivot.rotation = Vector3(0.38, 0.0 if sign > 0.0 else PI, 0.0)
		var cone := MeshInstance3D.new()
		var shape := CylinderMesh.new()
		# Its lamp is the cone's top, where the beam is lit from.
		shape.top_radius = 0.5
		shape.bottom_radius = 10.0
		shape.height = 180.0
		shape.cap_top = false
		shape.cap_bottom = false
		shape.material = Look.trim("beam")
		cone.mesh = shape
		cone.rotation.x = PI * 0.5
		cone.position = Vector3(0, 0, -90.0)
		cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		cone.visibility_range_end = FAR_SIGHT
		pivot.add_child(cone)
		art.add_child(pivot)
		_searchlights.append(pivot)
	_beacon_light = Look.lamp(Color(1.0, 0.12, 0.08), 6.0, 40.0)
	_beacon_light.position = _beacon.position
	art.add_child(_beacon_light)


## The war past the rim: gun flashes and blasts flaring and fading on the
## horizon, rare when the field is quiet and constant in all-out war (the
## map's `war_intensity`), and the Forge's searchlights turning.
func _tick_distant_war(delta: float) -> void:
	if _searchlights.is_empty():
		return
	var heat := clampf(float(get_meta("war_intensity", 0.0)), 0.0, 1.0)
	if _horizon_glow != null:
		# The fires burn higher with the war; a storm's ash hides them.
		_horizon_glow.set_shader_parameter("strength",
				lerpf(GLOW_STRENGTH.x, GLOW_STRENGTH.y, heat) * (1.0 - Look.weather_cover))
	for i in _searchlights.size():
		_searchlights[i].rotation.y += delta * (0.12 + 0.05 * i) * (1.0 + heat)
	if _flashes.is_empty():
		for i in 6:
			var flash := MeshInstance3D.new()
			var quad := QuadMesh.new()
			quad.size = Vector2(1, 1)
			quad.material = Look.trim("flash")
			flash.mesh = quad
			flash.visible = false
			flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			flash.visibility_range_end = FAR_SIGHT
			add_child(flash)
			_flashes.append(flash)
			_flash_left.append(0.0)
	for i in _flashes.size():
		if _flash_left[i] <= 0.0:
			continue
		_flash_left[i] -= delta
		var t := clampf(_flash_left[i] / FLASH_TIME, 0.0, 1.0)
		_flashes[i].transparency = 1.0 - t * t
		_flashes[i].visible = _flash_left[i] > 0.0
	if _art_rng.randf() < lerpf(FLASH_RATE.x, FLASH_RATE.y, heat) * delta:
		for i in _flashes.size():
			if _flash_left[i] > 0.0:
				continue
			var angle := _art_rng.randf() * TAU
			var reach := _art_rng.randf_range(360.0, 500.0)
			var size := _art_rng.randf_range(30.0, 70.0)
			_flashes[i].scale = Vector3.ONE * size
			_flashes[i].position = Vector3(cos(angle) * reach, RIM_HEIGHT + _art_rng.randf_range(0.0, 25.0), sin(angle) * reach)
			_flashes[i].visible = true
			_flash_left[i] = FLASH_TIME
			if _soundscape != null:
				_soundscape.boom(_flashes[i].global_position)
			break


## A plain dressed box with no collision and no shadow.
func _slab(size: Vector3, at: Vector3, material: Material, shadow := false) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	node.mesh = mesh
	node.position = at
	if not shadow:
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


## The wrecks finished off by one detail each, the same detail on every one
## of a kind: a tank's dead teal running light along its hull, a strider's
## cockpit slit, a dropship's hazard-striped fin and the furrow it ploughed.
func _dress_wrecks(art: Node3D) -> void:
	# Every wreck's hull clad in kit plating, all in one mesh.
	var kit := KitMesh.new()
	var clad_rng := RandomNumberGenerator.new()
	clad_rng.seed = LAYOUT_SEED + 29
	for wreck in _wrecks:
		var boxes: Array = wreck.get("boxes", [])
		if int(wreck.get("kind", -1)) == 0 and not boxes.is_empty():
			# A tank is the real thing: the boxes stay its collision, drawn
			# as a burnt-out tank model sat the way the hull settled.
			for part: Array in boxes:
				(part[3] as MeshInstance3D).visible = false
			var hull: Transform3D = boxes[0][1]
			var big: float = wreck["big"]
			var tank := Look.prop("Wreck_Tank.glb", 8.8 * big, 1.0)
			tank.transform = Transform3D(hull.basis.orthonormalized() * Basis(Vector3.UP, PI * 0.5), Vector3(hull.origin.x, float(wreck["at"].y) - 0.3, hull.origin.z))
			art.add_child(tank)
			continue
		for part: Array in boxes:
			KIT_DRESS.clad_box(kit, part[1], part[0], clad_rng, KIT_DRESS.HULL_PANELS, [], {"plate": "rust"} if part[2] else {})
	if not kit.is_empty():
		art.add_child(kit.node("WreckClad", {
			"plate": Look.surface("metal", {"tint": Color(0.7, 0.66, 0.62), "grime": 1.0, "scale": 0.1}),
			"rust": Look.surface("metal", {"tint": Color(0.85, 0.5, 0.34), "grime": 1.0, "scale": 0.12}),
			"dark": Look.surface("metal", {"tint": Color(0.3, 0.28, 0.27), "grime": 1.0, "scale": 0.1}),
			"glow": Look.trim("orange"),
		}, ["plate", "rust", "dark", "glow"]))
	var furrows: Array[PackedVector2Array] = []
	for wreck in _wrecks:
		if not wreck.has("kind"):
			continue
		var base: Vector3 = wreck["at"]
		var yaw: float = wreck["yaw"]
		var big: float = wreck["big"]
		var size: Vector3 = wreck["size"]
		var turn := Basis(Vector3.UP, yaw)
		match int(wreck["kind"]):
			1:
				var slit := _slab(Vector3(size.x * 0.6, 0.25, 0.08), Vector3.ZERO, Look.trim("teal"))
				slit.transform = Transform3D(Basis.from_euler(Vector3(0.0, yaw, 0.38)),
						base + Vector3(0, size.y * 0.5 - 0.8, 0)) * Transform3D(Basis.IDENTITY, Vector3(0, size.y * 0.15, -size.z * 0.5 - 0.05))
				art.add_child(slit)
			2:
				var fin := _slab(Vector3(0.45, 1.0 * big, 2.65 * big), base + turn * Vector3(0.3, size.y + 0.6 * big, size.z * 0.42), Look.trim("hazard"))
				fin.rotation = Vector3(-0.05, yaw + 0.12, 0.0)
				art.add_child(fin)
				# The canopy on the buried nose, and the engines on the broken tail.
				var front := Transform3D(Basis.from_euler(Vector3(0.16, yaw, 0.0)), base + turn * Vector3(0, size.y * 0.5 - 0.9, -size.z * 0.24))
				var canopy := _slab(Vector3(size.x * 0.7, 0.5, 1.8 * big), Vector3.ZERO, Look.trim("teal"))
				canopy.transform = front * Transform3D(Basis.IDENTITY, Vector3(0, size.y * 0.5 + 0.1, -size.z * 0.17))
				art.add_child(canopy)
				for at: Transform3D in _wreck_engines(base, yaw, size, big):
					var engine := _slab(WRECK_ENGINE * big, Vector3.ZERO, HULL_RUST, true)
					engine.transform = at
					art.add_child(engine)
					var nozzle := _slab(Vector3(1.0, 1.0, 0.1) * big, Vector3.ZERO, Look.trim("scorch"))
					nozzle.transform = engine.transform * Transform3D(Basis.IDENTITY, Vector3(0, 0, 1.31 * big))
					art.add_child(nozzle)
				var behind := Vector2(sin(yaw), cos(yaw))
				var from := Vector2(base.x, base.z) + behind * size.z * 0.5
				furrows.append(PackedVector2Array([from, from + behind * size.z * 1.6]))
	_ground_strips(art, furrows, 2.2, Look.trim("scorch"), 0.04)


## Each barricade piece drawn over its plain box: a jersey barrier's sloped
## concrete, a sandbag wall laid in courses, a steel plate with hazard
## stripes along its top, and a tank trap of three crossed beams.
func _dress_cover(art: Node3D) -> void:
	var bags := MultiMesh.new()
	bags.transform_format = MultiMesh.TRANSFORM_3D
	var bag := BoxMesh.new()
	bag.size = Vector3(0.62, 0.24, 0.42)
	bag.material = Look.trim("sandbag")
	bags.mesh = bag
	var beams := MultiMesh.new()
	beams.transform_format = MultiMesh.TRANSFORM_3D
	var beam := BoxMesh.new()
	beam.size = Vector3(0.22, 0.22, 2.0)
	beam.material = HULL
	beams.mesh = beam
	var bag_at: Array[Transform3D] = []
	var beam_at: Array[Transform3D] = []
	for piece in _cover_pieces:
		var kind: String = piece.get_meta("cover", "")
		var shown := piece.get_child(1) as MeshInstance3D
		var size: Vector3 = (shown.mesh as BoxMesh).size
		var frame := Transform3D(Basis(Vector3.UP, piece.rotation.y), piece.position)
		var ground_y := -size.y * 0.5 + 0.8 * 0.5
		match kind:
			"sandbag":
				shown.queue_free()
				var length := size.x
				for course in 4:
					var count := int(length / 0.6)
					for n in count:
						var x := -length * 0.5 + 0.3 + n * (length - 0.6) / maxf(count - 1, 1) + (0.15 if course % 2 == 1 else 0.0)
						for row: float in [-0.2, 0.2]:
							if course == 3 and row > 0.0:
								continue
							bag_at.append(frame * Transform3D(Basis(Vector3.UP, 0.04 * ((n + course) % 3 - 1)),
									Vector3(clampf(x, -length * 0.5 + 0.3, length * 0.5 - 0.3), ground_y - 0.15 + course * 0.24, row)))
			"trap":
				shown.queue_free()
				for axis in 3:
					var turn := Basis.from_euler([Vector3(0.6, 0.0, 0.0), Vector3(0.0, 0.0, 0.6) * 1.0 + Vector3(0, PI * 0.5, 0), Vector3(PI * 0.5, 0.35, 0.0)][axis])
					beam_at.append(frame * Transform3D(turn, Vector3(0, ground_y + 0.9, 0)))
			"plate":
				art.add_child(_slab(Vector3(size.x + 0.02, 0.3, size.z + 0.02), Vector3.ZERO, Look.trim("hazard")))
				art.get_child(art.get_child_count() - 1).transform = frame * Transform3D(Basis.IDENTITY, Vector3(0, size.y * 0.5 - 0.55, 0))
			"jersey":
				# The barrier's sloped foot, so it reads as a cast barrier.
				var foot := _slab(Vector3(size.x, 0.45, size.z + 0.5), Vector3.ZERO, COVER_CONCRETE, true)
				foot.transform = frame * Transform3D(Basis.IDENTITY, Vector3(0, ground_y + 0.2, 0))
				art.add_child(foot)
	for set: Array in [[bags, bag_at], [beams, beam_at]]:
		var mm: MultiMesh = set[0]
		var list: Array = set[1]
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i])
		var node := MultiMeshInstance3D.new()
		node.multimesh = mm
		art.add_child(node)


## Cracks of molten metal running in from the field to the core's rim, so
## the ground itself leads the eye to the Forge. Each is drawn in segments
## laid on the ground, wider near the core, and stops where something stands.
func _dress_cracks(art: Node3D) -> void:
	var lines: Array[PackedVector2Array] = []
	for k in CRACKS:
		var angle := TAU * (k + 0.5) / CRACKS + _art_rng.randf_range(-0.15, 0.15)
		var line := PackedVector2Array()
		var reach := _art_rng.randf_range(130.0, 180.0)
		var r := 12.0
		var heading := angle
		while r < reach:
			heading += _art_rng.randf_range(-0.012, 0.012)
			heading = lerpf(heading, angle, 0.04)
			# Flow round whatever stands in the way instead of stopping.
			var spot := Vector2.from_angle(heading) * r
			for bend in 8:
				if not _crack_blocked(spot, 1.5):
					break
				var turn := 0.04 * (bend / 2 + 1) * (1.0 if bend % 2 == 0 else -1.0)
				spot = Vector2.from_angle(heading + turn) * r
			if _crack_blocked(spot, 1.5):
				if line.size() > 1:
					lines.append(line)
				line = PackedVector2Array()
			else:
				heading = spot.angle()
				line.append(spot)
			r += 2.0
		if line.size() > 1:
			lines.append(line)
	# A charred bed under each crack, then the glow in it, widest at the core.
	_ground_strips(art, lines, 3.6, Look.trim("scorch"), 0.06, true)
	_ground_strips(art, lines, 1.0, Look.trim("crack"), 0.1, true)


## The supply roads: packed, rutted tracks, so the way an army came and went
## reads on the ground.
func _dress_roads(art: Node3D) -> void:
	var lines: Array[PackedVector2Array] = []
	for road: Array in ROADS:
		var line := PackedVector2Array()
		for i in road.size() - 1:
			var a: Vector2 = road[i]
			var b: Vector2 = road[i + 1]
			var steps := maxi(int(a.distance_to(b) / 2.5), 1)
			for k in steps:
				line.append(a.lerp(b, float(k) / steps))
		line.append(road[road.size() - 1])
		lines.append(line)
	# A pale bed of packed gravel the dirt never is, so a road reads from the
	# saddle, and two dark wheel ruts worn down it by the convoys.
	_ground_strips(art, lines, 6.0, Look.trim("track"), 0.1, false, false)
	for side: float in [-1.0, 1.0]:
		var ruts: Array[PackedVector2Array] = []
		for line in lines:
			var rut := PackedVector2Array()
			for i in line.size():
				var dir := (line[mini(i + 1, line.size() - 1)] - line[maxi(i - 1, 0)]).normalized()
				rut.append(line[i] + dir.orthogonal() * side * 1.15)
			ruts.append(rut)
		_ground_strips(art, ruts, 0.45, Look.trim("rut"), 0.14, false, false)
	# Each muster's runway: edge lamps down both sides and a hazard bar
	# across each end, so a pilot can find it and line up on it.
	for army: String in ARMIES:
		var runway := _runway(army)
		var from: Vector2 = runway["from"]
		var dir: Vector2 = runway["dir"]
		var yaw := atan2(dir.x, dir.y)
		for end: float in [RUNWAY_FROM, RUNWAY_FROM + RUNWAY]:
			var at := from + dir * end
			var bar := _slab(Vector3(5.6, 0.08, 0.9), terrain.on_ground(at.x, at.y) + Vector3(0, 0.05, 0), Look.trim("hazard"))
			bar.rotation.y = yaw
			art.add_child(bar)
		var d := RUNWAY_FROM + 4.0
		while d < RUNWAY_FROM + RUNWAY:
			for side: float in [-1.0, 1.0]:
				var at := from + dir * d + dir.orthogonal() * side * 3.4
				var lamp := _slab(Vector3(0.25, 0.18, 0.5), terrain.on_ground(at.x, at.y) + Vector3(0, 0.09, 0), Look.trim("orange"))
				lamp.rotation.y = yaw
				art.add_child(lamp)
			d += 8.0


## Draws each polyline as short boxes laid on the ground and tipped with it,
## in one MultiMesh. `taper` narrows a line toward its far end.
func _ground_strips(art: Node3D, lines: Array[PackedVector2Array], width: float, material: Material, lift: float, taper := false, keep_off_runways := true) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var box := BoxMesh.new()
	# Thick and sunk, so a bump in the ground between samples never hides it.
	box.size = Vector3(1.0, 0.6, 1.0)
	box.material = material
	mm.mesh = box
	var placed: Array[Transform3D] = []
	for line in lines:
		for i in line.size() - 1:
			var a := line[i]
			var b := line[i + 1]
			var mid := (a + b) * 0.5
			if _crack_blocked(mid, 0.2, keep_off_runways):
				continue
			var pa := terrain.on_ground(a.x, a.y)
			var pb := terrain.on_ground(b.x, b.y)
			var along := pb - pa
			var t := float(i) / maxf(line.size() - 1, 1)
			var w := width * (lerpf(1.0, 0.35, t) if taper else 1.0)
			var forward := along.normalized()
			# Right-handed (x, y, z), or the box is mirrored and shows its
			# insides: its top face would be culled.
			var right := Vector3.UP.cross(forward).normalized()
			var up := forward.cross(right)
			var basis := Basis(right * w, up, forward * (along.length() + 0.3))
			placed.append(Transform3D(basis, (pa + pb) * 0.5 + up * (lift - 0.3)))
	mm.instance_count = placed.size()
	for i in placed.size():
		mm.set_instance_transform(i, placed[i])
	var node := MultiMeshInstance3D.new()
	node.multimesh = mm
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	art.add_child(node)


func _crack_blocked(at: Vector2, room := 0.5, keep_off_runways := true) -> bool:
	for solid in _solids:
		if at.distance_to(solid["at"]) < float(solid["reach"]) + room:
			return true
	# The runways are kept for take-off, so the cracks flow round them.
	if not keep_off_runways:
		return false
	for army: String in ARMIES:
		var runway := _runway(army)
		var from: Vector2 = runway["from"]
		var dir: Vector2 = runway["dir"]
		var a := from + dir * (RUNWAY_FROM - 4.0)
		var b := from + dir * (RUNWAY_FROM + RUNWAY + 4.0)
		if at.distance_to(Geometry2D.get_closest_point_to_segment(at, a, b)) < ROAD_CLEAR + room:
			return true
	return false


## The skyline: a few huge, simple shapes past the rim, each placed on
## purpose so the world reads as enormous. A capital ship that came down
## nose first in the north, each army's smokestacks behind its muster, a
## megabridge broken in the southwest, a toppled tower in the northeast,
## and between them the low line of a ruined city. Built from four pieces
## (hull, stack, pylon, block) used over and over.
func _dress_horizon(art: Node3D) -> void:
	var hulk := Look.trim("distant")
	# The burning horizon: fires past the city, so the skyline stands dark
	# against red. One open ring, no shadow.
	var ring := MeshInstance3D.new()
	var band := CylinderMesh.new()
	band.top_radius = GLOW_RING
	band.bottom_radius = GLOW_RING
	band.height = 220.0
	band.cap_top = false
	band.cap_bottom = false
	band.radial_segments = 64
	band.rings = 1
	_horizon_glow = Look.trim("horizon_glow") as ShaderMaterial
	band.material = _horizon_glow
	ring.mesh = band
	ring.name = "HorizonGlow"
	ring.position = Vector3(0, 110.0, 0)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	art.add_child(ring)
	_far_land(art)
	var floor_y := RIM_HEIGHT - 8.0
	var at := func(angle_deg: float, reach: float, up := 0.0) -> Vector3:
		var a := deg_to_rad(angle_deg)
		return Vector3(cos(a) * reach, floor_y + up, sin(a) * reach)
	var put := func(size: Vector3, xform: Transform3D, material: Material = hulk) -> void:
		var node := _slab(size, Vector3.ZERO, material)
		node.transform = xform
		art.add_child(node)
	# The ruined city's blocks still have a little life in them.
	var city := Look.trim("distant_lit")
	# The capital ship, broadside to the field: nose buried in the west,
	# hull rising away to the east.
	var ship_at: Vector3 = at.call(-95.0, 490.0)
	var ship := Transform3D(Basis(Vector3.UP, PI * 0.5 + 0.1) * Basis(Vector3.RIGHT, -0.3), ship_at + Vector3(0, 40, 0))
	put.call(Vector3(46, 40, 300), ship)
	put.call(Vector3(30, 22, 60), ship * Transform3D(Basis.IDENTITY, Vector3(0, -2, -170)))
	put.call(Vector3(22, 36, 34), ship * Transform3D(Basis.IDENTITY, Vector3(0, 30, 95)))
	for side: float in [-1.0, 1.0]:
		put.call(Vector3(18, 18, 30), ship * Transform3D(Basis.IDENTITY, Vector3(side * 16, -4, 160)))
	art.add_child(_plume(ship * Vector3(0, 12, 120), 10.0))
	# Smokestacks, four to an army, behind each muster, joined by a hall.
	for angle: float in [184.0, -4.0]:
		var hall_at: Vector3 = at.call(angle, 440.0)
		var face := Basis(Vector3.UP, -deg_to_rad(angle))
		put.call(Vector3(40, 34, 120), Transform3D(face, hall_at + Vector3(0, 17, 0)))
		for n in 4:
			var height: float = [150.0, 120.0, 135.0, 105.0][n]
			var stack: Vector3 = hall_at + face * Vector3(0, 0, (n - 1.5) * 30.0)
			var node := MeshInstance3D.new()
			var tube := CylinderMesh.new()
			tube.top_radius = 4.5
			tube.bottom_radius = 6.5
			tube.height = height
			tube.radial_segments = 8
			tube.material = hulk
			node.mesh = tube
			node.position = stack + Vector3(0, height * 0.5, 0)
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			art.add_child(node)
			if n % 2 == 0:
				art.add_child(_plume(stack + Vector3(0, height, 0), 4.0))
	# The megabridge: two pylons, half the deck still up, half fallen.
	var bridge_at: Vector3 = at.call(130.0, 470.0)
	var span := Basis(Vector3.UP, -deg_to_rad(130.0) + PI * 0.5)
	for side: float in [-1.0, 1.0]:
		put.call(Vector3(26, 160, 26), Transform3D(span, bridge_at + span * Vector3(side * 85, 80, 0)))
	put.call(Vector3(80, 10, 30), Transform3D(span, bridge_at + span * Vector3(-45, 150, 0)))
	put.call(Vector3(96, 10, 30), Transform3D(span * Basis(Vector3.BACK, -1.05), bridge_at + span * Vector3(52, 72, 0)))
	# The toppled tower, leaning on the rim.
	var tower_at: Vector3 = at.call(-40.0, 470.0)
	var lean := Basis(Vector3.UP, -deg_to_rad(-40.0)) * Basis(Vector3.BACK, 0.62)
	put.call(Vector3(48, 240, 48), Transform3D(lean, tower_at + Vector3(0, 90, 0)))
	put.call(Vector3(56, 12, 56), Transform3D(lean, tower_at + Vector3(0, 90, 0) + lean * Vector3(0, 60, 0)))
	# Broken pylons in the south, the bridge's sisters.
	for n in 3:
		var pylon_at: Vector3 = at.call(70.0 + n * 14.0, 450.0 + n * 25.0)
		var height: float = [120.0, 75.0, 95.0][n]
		put.call(Vector3(26, height, 26), Transform3D(Basis(Vector3.UP, n * 0.4), pylon_at + Vector3(0, height * 0.5, 0)))
	# The ruined city between the set pieces: square blocks, upright, gapped.
	var landmarks := [-95.0, 184.0, -4.0, 130.0, -40.0, 84.0]
	var angle := -180.0
	while angle < 180.0:
		var near := false
		for mark: float in landmarks:
			if absf(wrapf(angle - mark, -180.0, 180.0)) < 16.0:
				near = true
		if not near:
			var width := _art_rng.randf_range(20.0, 48.0)
			var reach := _art_rng.randf_range(400.0, 470.0)
			var height := _art_rng.randf_range(30.0, 85.0)
			var block_at: Vector3 = at.call(angle, reach, height * 0.5)
			# The battle shelves stay open for the scenery army.
			if FarLand.shelf(block_at.x, block_at.z).y > 0.0:
				angle += _art_rng.randf_range(7.0, 11.0)
				continue
			var face := Basis(Vector3.UP, -deg_to_rad(angle))
			put.call(Vector3(width, height, width * _art_rng.randf_range(0.5, 0.9)), Transform3D(face, block_at), city)
			# Some kept a mast or a stepped wing beside them.
			var extra := _art_rng.randf()
			if extra < 0.2:
				put.call(Vector3(2.5, 34.0, 2.5), Transform3D(face, block_at + face * Vector3(width * 0.25, height * 0.5 + 17.0, 0)))
			elif extra < 0.45:
				var wing := height * _art_rng.randf_range(0.35, 0.6)
				put.call(Vector3(width * 0.6, wing, width * 0.6), Transform3D(face, block_at + face * Vector3(width * 0.75, (wing - height) * 0.5, 0)), city)
			# Most blocks were shelled: a narrower broken storey left on one side.
			if _art_rng.randf() < 0.6:
				var side := _art_rng.randf_range(-0.3, 0.3) * width
				var storey := _art_rng.randf_range(10.0, 26.0)
				put.call(Vector3(width * 0.35, storey, width * 0.5), Transform3D(face, block_at + face * Vector3(side, (height + storey) * 0.5, 0)), city)
		angle += _art_rng.randf_range(7.0, 11.0)
	# Smoke off the battle shelves, one column each, where their fights are.
	var flats := shelf_flats()
	for shelf: Dictionary in SHELVES:
		var out: Vector2 = shelf["out"]
		var lateral: Vector2 = shelf["lateral"]
		var flat: Vector2 = flats[_art_rng.randi() % flats.size()]
		var spot := out * (flat.x + flat.y) * 0.5 + Vector2(-out.y, out.x) * _art_rng.randf_range(lateral.x + 30.0, lateral.y - 30.0)
		art.add_child(_plume(Vector3(spot.x, scenery_height(spot.x, spot.y), spot.y), 6.0))


## A tall smoke plume for the skyline: the fire smoke, scaled up to be read
## from across the map.
func _plume(at: Vector3, width: float) -> GPUParticles3D:
	var plume := _smoke(at, width)
	(plume.draw_pass_1 as QuadMesh).size = Vector2(40, 40)
	var mat := plume.process_material as ParticleProcessMaterial
	mat.initial_velocity_min = 7.0
	mat.initial_velocity_max = 10.0
	plume.visibility_aabb = AABB(Vector3(-150, -10, -150), Vector3(300, 260, 300))
	return plume


## Past the rim the Ashland's own land runs on to the horizon, under the
## skyline and the giants; none of it collides. It is kept low near the
## map (`FAR_RIM`, `FAR_RIDGES`) so the skyline still stands on it rather
## than in it. The planet's rocks stand only on the rim's slope and out
## past it (`FIELD` plus `PROPS_PAST_FIELD`), never where anyone fights.
func _far_land(art: Node3D) -> void:
	var land := _far_ground()
	var half := terrain.extent() * 0.5
	art.add_child(Planet.horizon(planet, land, half, 0.0, func(x: float, z: float) -> float:
		return 1.0 - FarLand.shelf(x, z).y))
	var height_of := func(x: float, z: float) -> float:
		return terrain.height_at(x, z) if maxf(absf(x), absf(z)) < half else land.height_at(x, z)
	var clear := func(x: float, z: float) -> bool:
		return maxf(absf(x), absf(z)) > FIELD + PROPS_PAST_FIELD
	PlanetProps.scatter(art, planet, height_of, half, LAYOUT_SEED + 3, clear)
