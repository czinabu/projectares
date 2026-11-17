extends WorldDef
## The arena: a sunken fighting floor ringed by a wall, with tiered stands for
## the crowd. It is a venue, not a raid world, so it lives in core and is never
## listed with the deploy targets. It never names a specific world.
##
## Rules: nobody loses gear here (`gear_at_risk` is off), nobody can hurt
## anyone except the two fighters in the current bout, and the bout is run by
## `Arena` (core/arena/arena.gd), which this venue creates as its raid.
##
## The floor is laid out for blades, guns and flight alike, mirrored so
## neither side has an edge: a low dais in the middle, four tall pillars with
## perches round it, a high platform for each side, a wall in front of each
## door so nobody is shot coming out, low barriers, and rising barriers that
## take turns coming up during a fight (`barrier_raise`). An unseen ceiling (`CEILING`) keeps
## flight over the floor. Each fighter waits in a tunnel under the stands
## behind a door that opens as the fight starts (`doors_open`).
##
## Map contract, beyond WorldDef's: Marker3D nodes in group "arena_gate" with
## meta "side" (0 = red, 1 = blue) where fighters wait in their tunnel; Node3D
## faces in group "arena_board" (`BOARD_SIZE`, facing +Z) where the big board
## shows the bout; Marker3D nodes in group "arena_booth" where a spectator
## stands to use a bookmaker's booth, each with a child "Screen" (a
## `WorldScreen` face, 1.6 by 0.9 metres, facing +Z); and a `set_stage(phase,
## elapsed)` method the `Arena` calls every tick to move the doors and the
## rising barriers.
##
## Load with `const ArenaVenue := preload("res://core/arena/arena_venue.gd")`.

const ID := "arena"
const ArenaScript := preload("res://core/arena/arena.gd")

## Inside this radius from the center is the fighting floor. The stands start past the wall.
const PIT_RADIUS := 20.0
const WALL_RADIUS := 20.6
const WALL_HEIGHT := 4.4
const STAND_TIERS := 4
const TIER_DEPTH := 3.0
const TIER_RISE := 1.0
const OUTER_RADIUS := WALL_RADIUS + 0.6 + STAND_TIERS * TIER_DEPTH
## The wall and stands are built in this many pieces. The tunnels take the
## piece on the +X and -X axes, so keep it a multiple of 4.
const SEGMENTS := 32
## Fighters can fly no higher than this over the floor.
const CEILING := 16.0
## The tunnels run out along the X axis (red at -X, blue at +X), under the stands.
const TUNNEL_HALF_WIDTH := 1.9
const TUNNEL_HEIGHT := 3.2
const TUNNEL_END := OUTER_RADIUS - 0.4
## A fighter waits this far from the center, in the tunnel.
const GATE_DISTANCE := WALL_RADIUS + 3.0
## The doors stay open this long into a fight, then close behind the fighters.
const DOOR_OPEN_TIME := 5.0
## Rising barriers: two pairs that take turns being up, this long each, and
## how long one takes to rise or sink. Raised, they stand this high.
const BARRIER_PERIOD := 15.0
const BARRIER_MOVE := 1.5
const BARRIER_HEIGHT := 1.8
## Each face of the big board over the pit, in metres, how many faces the
## ring has, and how high it hangs (above the ceiling, out of the fight).
const BOARD_SIZE := Vector2(6.0, 3.4)
const BOARD_FACES := 8
const BOARD_HEIGHT := 19.0
## Bookmakers' booths in the stands: how many, and how close to one you stand to use it.
const BOOTHS := 4
const BOOTH_REACH := 1.8

## The cover on the floor, mirrored through the center so both sides match.
## Pillars: [x, z]. Platforms: [x, z, ramp direction along z]. Barriers: [x,
## z, yaw]. Rising barriers: [x, z, yaw, pair].
const PILLARS := [[5.7, 5.7], [-5.7, 5.7], [-5.7, -5.7], [5.7, -5.7]]
const PILLAR_SIZE := Vector3(1.8, 8.0, 1.8)
const PLATFORMS := [[-12.0, -9.0, 1.0], [12.0, 9.0, -1.0]]
const PLATFORM_SIZE := Vector3(5.0, 3.0, 4.0)
const LOW_BARRIERS := [[0.0, -13.0, 0.0], [0.0, 13.0, 0.0]]
const LOW_BARRIER_SIZE := Vector3(4.4, 1.1, 0.5)
## Walls in front of each door, tall enough to hide a fighter standing, so
## nobody is shot as they come out.
const GATE_WALLS := [[-10.0, 0.0, PI / 2.0], [10.0, 0.0, PI / 2.0]]
const GATE_WALL_SIZE := Vector3(4.4, 2.2, 0.5)
## Low cover near the wall, so nobody can circle the floor's edge in the open: [bearing].
const RIM_COVER := [PI / 3.0, 2.0 * PI / 3.0, -PI / 3.0, -2.0 * PI / 3.0]
const RIM_COVER_RADIUS := 16.5
const RIM_COVER_SIZE := Vector3(3.2, 1.1, 0.6)
## The dais in the middle: a sloped mound you walk up, with a low lip round its top.
const DAIS_RADIUS := 2.4
const DAIS_FOOT := 3.8
const DAIS_HEIGHT := 0.9
## Stadium floodlight towers round the rim: how many, and how tall a mast
## stands on the rim wall.
const FLOODLIGHTS := 12
const FLOODLIGHT_HEIGHT := 12.0
## Where the banks aim: swung this far round from the tower's own bearing,
## at these distances from the center in turn, so the light spreads over the
## floor out to the arena's edges (Caleb's call: never all at one point).
const FLOODLIGHT_SWING := deg_to_rad(130.0)
const FLOODLIGHT_REACH := [16.5, 12.5]
## Floodlights are plain white (Caleb's call), apart from the venue's amber.
const FLOOD_COLOR := Color(0.94, 0.97, 1.0)
## Colours of the look: amber for the venue, red and blue for the sides.
const AMBER := Color(1.0, 0.55, 0.18)
const SIDE_COLORS := [Color(1.0, 0.22, 0.16), Color(0.22, 0.45, 1.0)]
const RISING_BARRIERS := [[-12.0, 9.0, 0.0, 0], [12.0, -9.0, 0.0, 0], [0.0, -7.0, 0.0, 1], [0.0, 7.0, 0.0, 1]]
const RISING_BARRIER_SIZE := Vector3(3.2, BARRIER_HEIGHT, 0.6)

## Gladiator names for bots, picked by seed so a client builds the same one.
const GLADIATOR_NAMES := ["Varro", "Priscus", "Spiculus", "Flamma", "Crixus", "Tetraites", "Carpophorus",
		"Verus", "Marcus Attilius", "Hermes", "Triumphus", "Celadus"]

## The arena that is using this venue. Set by `Arena` when it starts.
var arena: Node = null


func _init() -> void:
	id = ID
	display_name = "The Pit"
	description = "Duels, tournaments and wagers. Nobody loses gear in the arena."
	bot_count = 0
	event_interval = 0.0
	power_weapon_rate = 0.0
	warlord_artifact_chance = 0.0
	pod_artifact_chance = 0.0
	gear_at_risk = false
	# Nobody can be hurt outside a bout anyway, and fighters start together.
	spawn_protection = 0.0


func new_raid() -> Raid:
	return ArenaScript.new()


func create_map() -> Node3D:
	return Pit.new()


## The free scrap kit from the core item list, for a fighter added with no
## kit at all (bots, tests). A player's kit is their loadout, bare slots
## included. No healing: there is none in the pit.
func starter_loadout() -> Array[String]:
	return ["rifle_scrap", "blade_scrap", "pistol_service", "jetpack_mk1", "plate_light", "visor_scav"]


## Only the two fighters in a running bout can hurt each other. `info` is
## null when a bot is only asking whether someone is a target.
func can_damage(attacker: Node, target: Node, _info: DamageInfo) -> bool:
	if attacker == target or arena == null or not is_instance_valid(arena):
		return false
	return arena.call("may_hurt", attacker, target)


## A bot gladiator, the same from the same seed on every machine.
func equip_bot(bot: Actor, rng: RandomNumberGenerator) -> void:
	bot.faction = "gladiator_%d" % rng.randi()
	bot.display_name = GLADIATOR_NAMES[rng.randi() % GLADIATOR_NAMES.size()]
	bot.set_meta("look", "scavenger")
	bot.body_color = Color(0.75, 0.6, 0.3)
	var kit: Array[String] = ["plate_light"]
	# Most gladiators fight with a blade, the rest with a rifle.
	if rng.randf() < 0.65:
		kit.append("blade_scrap")
	else:
		kit.append("rifle_scrap")
	Loadout.equip(bot, kit)
	bot.health.max_health = rng.randf_range(90.0, 110.0)
	bot.health.health = bot.health.max_health




## True if `at` is on the fighting floor, inside the wall and under the ceiling.
static func in_pit(at: Vector3) -> bool:
	return Vector2(at.x, at.z).length() < WALL_RADIUS + 0.2 and at.y < CEILING + 1.0


## True if `at` is in one of the fighters' tunnels under the stands.
static func in_tunnel(at: Vector3) -> bool:
	return absf(at.z) < TUNNEL_HALF_WIDTH + 0.2 and absf(at.x) > WALL_RADIUS - 0.4 \
			and absf(at.x) < TUNNEL_END + 0.2 and at.y < TUNNEL_HEIGHT


## True if `at` is anywhere a fighter may be: the floor or a tunnel.
static func in_bounds(at: Vector3) -> bool:
	return in_pit(at) or in_tunnel(at)


## Where a fighter who strays out of bounds mid-fight is put back: on the
## floor just inside their own door.
static func entry_point(side: int) -> Vector3:
	return Vector3((-1.0 if side == 0 else 1.0) * (PIT_RADIUS - 1.5), 0.1, 0.0)


## Whether the tunnel doors are open: from the start of a fight for
## `DOOR_OPEN_TIME` seconds. `elapsed` is how far into the fight it is.
static func doors_open(phase: String, elapsed: float) -> bool:
	return phase == "fight" and elapsed < DOOR_OPEN_TIME


## How far up a rising barrier of `pair` is, 0 (sunk into the floor) to 1.
## Pair 0 starts up; every `BARRIER_PERIOD` of a fight the pairs swap. Outside
## a fight (`elapsed` below 0) they rest as a fight starts.
static func barrier_raise(pair: int, elapsed: float) -> float:
	var t := maxf(elapsed, 0.0)
	var stretch := int(t / BARRIER_PERIOD)
	var up := 1.0 if stretch % 2 == pair else 0.0
	if stretch == 0:
		return up
	var into := t - stretch * BARRIER_PERIOD
	return lerpf(1.0 - up, up, smoothstep(0.0, BARRIER_MOVE, into))


## The colosseum, built from plain boxes that `Look` dresses. Boxes that
## never move are merged into one mesh per material and one body per part
## (floor, stands), so the whole venue is a handful of draws.
class Pit:
	extends Node3D

	## The floor, wall, cover and tunnels: what bots walk on and around.
	var nav_region: NavigationRegion3D
	var _floor_mat: Material
	var _wall_mat: Material
	var _cover_mat: Material
	var _stand_mat: Material
	var _stand_alt_mat: Material
	## Material -> SurfaceTool, filled by `_add` and turned into meshes by `_flush`.
	var _batches := {}
	## Parent node -> its shared StaticBody3D.
	var _bodies := {}
	## The moving parts: [body, rest position, lowered offset, pair or -1 for a door].
	var _movers: Array = []
	## Glow materials by [colour, energy].
	var _glows := {}
	var _art_rng := RandomNumberGenerator.new()
	## The venue script, for its rules (an inner class cannot call them bare).
	var _venue: GDScript = load("res://core/arena/arena_venue.gd")

	func _ready() -> void:
		# A warm sci-fi night (Caleb's call): dark gunmetal under amber lit
		# edges, red against blue, next to the hub's cool twilight.
		_floor_mat = Look.surface("concrete", {"tint": Color(0.27, 0.28, 0.32), "grime": 0.1, "scale": 0.3, "saturation": 0.4})
		_wall_mat = Look.surface("metal", {"tint": Color(0.3, 0.28, 0.28), "grime": 0.3, "scale": 0.2})
		_cover_mat = Look.surface("concrete", {"tint": Color(0.33, 0.34, 0.38), "grime": 0.1, "scale": 0.4, "saturation": 0.4})
		_stand_mat = Look.surface("concrete", {"tint": Color(0.4, 0.36, 0.34), "grime": 0.4, "scale": 0.25})
		_stand_alt_mat = Look.surface("concrete", {"tint": Color(0.3, 0.27, 0.26), "grime": 0.5, "scale": 0.25})
		Look.atmosphere(self, {
			"sky_tint": Color(0.5, 0.48, 0.72),
			"sky_saturation": 0.7,
			"sky_energy": 0.22,
			"fog_color": Color(0.08, 0.08, 0.12),
			"fog_density": 0.004,
			"sun_color": Color(1.0, 0.7, 0.5),
			"sun_energy": 0.25,
			"sun_angles": Vector3(-35, 140, 0),
			"ambient_color": Color(0.72, 0.66, 0.68),
			"ambient_energy": 1.8,
			"exposure": 1.3,
			"saturation": 1.0,
			"glow": 0.7,
		})
		nav_region = NavigationRegion3D.new()
		nav_region.name = "Floor"
		add_child(nav_region)
		_build_floor()
		_build_cover()
		_build_tunnels()
		_build_stands()
		_build_ceiling()
		_spectator_spots()
		_board()
		_booths()
		_dress()
		_flush()
		set_stage("idle", -1.0)

	func bake_navigation() -> void:
		var navmesh := NavigationMesh.new()
		navmesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
		navmesh.geometry_collision_mask = Actor.LAYER_WORLD
		navmesh.cell_size = 0.25
		navmesh.agent_radius = 0.5
		navmesh.agent_height = 1.75
		navmesh.agent_max_climb = 0.5
		navmesh.agent_max_slope = 40.0
		nav_region.navigation_mesh = navmesh
		nav_region.bake_navigation_mesh(false)

	## Moves the doors and the rising barriers for the arena's phase and how
	## far into the fight it is. Called by `Arena` every tick, on every machine.
	func set_stage(phase: String, elapsed: float) -> void:
		var open: bool = _venue.doors_open(phase, elapsed)
		for mover in _movers:
			var body: AnimatableBody3D = mover[0]
			var rest: Vector3 = mover[1]
			var drop: float = mover[2]
			var pair: int = mover[3]
			var down: float = (1.0 if open else 0.0) if pair < 0 else 1.0 - float(_venue.barrier_raise(pair, elapsed))
			var at := rest - Vector3(0, drop * down, 0)
			if not body.position.is_equal_approx(at):
				body.position = at

	# --- The floor ------------------------------------------------------------

	func _build_floor() -> void:
		var size := OUTER_RADIUS * 2.0 + 6.0
		_add(Vector3(size, 0.5, size), Vector3(0, -0.25, 0), 0.0, _floor_mat, nav_region)
		# The center dais: a mound with sloped sides, worth holding.
		_add_dais(nav_region)
		# The pit wall, with a doorway on each tunnel.
		var door_top := TUNNEL_HEIGHT
		for i in SEGMENTS:
			if _is_tunnel_segment(i):
				_segment(i, WALL_RADIUS, 0.6, door_top, WALL_HEIGHT, _wall_mat, nav_region)
			else:
				_segment(i, WALL_RADIUS, 0.6, 0.0, WALL_HEIGHT, _wall_mat, nav_region)

	func _build_cover() -> void:
		for p in PILLARS:
			_add(PILLAR_SIZE, Vector3(p[0], PILLAR_SIZE.y * 0.5, p[1]), 0.0, _cover_mat, nav_region)
			# A perch on top, wider than the pillar, to land on.
			_add(Vector3(2.8, 0.3, 2.8), Vector3(p[0], PILLAR_SIZE.y + 0.15, p[1]), 0.0, _cover_mat, nav_region)
		for p in PLATFORMS:
			var at := Vector3(p[0], PLATFORM_SIZE.y * 0.5, p[1])
			_add(PLATFORM_SIZE, at, 0.0, _cover_mat, nav_region)
			# A ramp down from the platform's side that faces the middle.
			var run := 5.6
			var slope := atan2(PLATFORM_SIZE.y, run)
			var length := sqrt(run * run + PLATFORM_SIZE.y * PLATFORM_SIZE.y)
			var dir: float = p[2]
			var ramp_mid := Vector3(p[0], PLATFORM_SIZE.y * 0.5 - 0.1, p[1] + dir * (PLATFORM_SIZE.z * 0.5 + run * 0.5))
			_add(Vector3(2.2, 0.3, length), ramp_mid, 0.0, _cover_mat, nav_region, Vector3(dir * slope, 0, 0))
		for b in LOW_BARRIERS:
			_add(LOW_BARRIER_SIZE, Vector3(b[0], LOW_BARRIER_SIZE.y * 0.5, b[1]), b[2], _cover_mat, nav_region)
		for bearing: float in RIM_COVER:
			var at := Vector3(cos(bearing), 0, sin(bearing)) * RIM_COVER_RADIUS + Vector3(0, RIM_COVER_SIZE.y * 0.5, 0)
			_add(RIM_COVER_SIZE, at, -(bearing + PI / 2.0), _cover_mat, nav_region)
		for b in GATE_WALLS:
			_add(GATE_WALL_SIZE, Vector3(b[0], GATE_WALL_SIZE.y * 0.5, b[1]), b[2], _cover_mat, nav_region)
		# Rising barriers move, so they are bodies of their own and not part
		# of the navigation mesh: bots path as if they were down.
		for i in RISING_BARRIERS.size():
			var b: Array = RISING_BARRIERS[i]
			var rest := Vector3(b[0], RISING_BARRIER_SIZE.y * 0.5, b[1])
			_mover(RISING_BARRIER_SIZE, rest, b[2], RISING_BARRIER_SIZE.y + 0.05, int(b[3]), "Barrier%d" % i)

	# --- Tunnels and doors ----------------------------------------------------

	func _build_tunnels() -> void:
		for side in 2:
			var dir := -1.0 if side == 0 else 1.0
			var inner := WALL_RADIUS + 0.3
			var length := TUNNEL_END - inner
			var mid_x := dir * (inner + length * 0.5)
			for wall_z in [-1.0, 1.0]:
				_add(Vector3(length, TUNNEL_HEIGHT, 0.3), Vector3(mid_x, TUNNEL_HEIGHT * 0.5,
						wall_z * (TUNNEL_HALF_WIDTH + 0.15)), 0.0, _wall_mat, nav_region)
			_add(Vector3(0.4, TUNNEL_HEIGHT, TUNNEL_HALF_WIDTH * 2.0 + 0.6),
					Vector3(dir * (TUNNEL_END + 0.2), TUNNEL_HEIGHT * 0.5, 0), 0.0, _wall_mat, nav_region)
			var marker := Marker3D.new()
			marker.name = "Gate%d" % side
			marker.position = Vector3(dir * GATE_DISTANCE, 0.1, 0)
			marker.set_meta("side", side)
			marker.add_to_group("arena_gate")
			add_child(marker)
			# The door in the pit wall sinks into the floor to open.
			var door_size := Vector3(0.4, TUNNEL_HEIGHT, TUNNEL_HALF_WIDTH * 2.0 + 0.4)
			var door := _mover(door_size, Vector3(dir * WALL_RADIUS, TUNNEL_HEIGHT * 0.5, 0), 0.0,
					TUNNEL_HEIGHT + 0.05, -1, "Door%d" % side)
			var color := Color(0.9, 0.25, 0.2) if side == 0 else Color(0.25, 0.45, 0.95)
			var mat := StandardMaterial3D.new()
			mat.albedo_color = color
			mat.emission_enabled = true
			mat.emission = color * 0.5
			(door.get_child(1) as MeshInstance3D).material_override = mat

	func _is_tunnel_segment(i: int) -> bool:
		return i == SEGMENTS / 4 or i == SEGMENTS * 3 / 4

	# --- The stands -----------------------------------------------------------

	func _build_stands() -> void:
		var stands := Node3D.new()
		stands.name = "Stands"
		add_child(stands)
		for tier in STAND_TIERS:
			var inner := WALL_RADIUS + 0.3 + tier * TIER_DEPTH
			var top := WALL_HEIGHT - 0.6 + tier * TIER_RISE
			var mat := _stand_alt_mat if tier % 2 == 0 else _stand_mat
			for i in SEGMENTS:
				# Over a tunnel the tier is a roof, not solid to the ground.
				var bottom := TUNNEL_HEIGHT if _is_tunnel_segment(i) else 0.0
				_segment(i, inner + TIER_DEPTH * 0.5, TIER_DEPTH, bottom, top, mat, stands)
		var rim_top := WALL_HEIGHT + STAND_TIERS * TIER_RISE + 4.0
		for i in SEGMENTS:
			_segment(i, OUTER_RADIUS + 0.5, 1.0, 0.0, rim_top, _wall_mat, stands)

	## An unseen lid over the floor: fighters fly under it, never over the stands' heads.
	func _build_ceiling() -> void:
		var body := StaticBody3D.new()
		body.name = "Ceiling"
		body.collision_layer = Actor.LAYER_WORLD
		body.collision_mask = 0
		body.position = Vector3(0, CEILING + 0.5, 0)
		var shape := CylinderShape3D.new()
		shape.radius = WALL_RADIUS + 0.3
		shape.height = 1.0
		var col := CollisionShape3D.new()
		col.shape = shape
		body.add_child(col)
		add_child(body)

	## The big board hanging over the middle of the pit: a ring of screens
	## facing out and tipped down at the stands, so every seat can read it.
	## Thin open panels with lit edges, so from the floor it reads as a frame
	## of light rather than a lid.
	func _board() -> void:
		for i in BOARD_FACES:
			var place := _board_face(i)
			# A thin back behind the screen, joined into the venue's walls mesh.
			_batch(_wall_mat).append_from(_box_mesh(Vector3(BOARD_SIZE.x + 0.1, BOARD_SIZE.y + 0.25, 0.08)), 0,
					place * Transform3D(Basis.IDENTITY, Vector3(0, 0, -0.06)))
			var face := Node3D.new()
			face.name = "Board%d" % i
			face.transform = place
			face.add_to_group("arena_board")
			add_child(face)
		var title := Label3D.new()
		title.text = "THE PIT"
		title.font_size = 128
		title.pixel_size = 0.024
		title.modulate = AMBER
		title.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		title.position = Vector3(0, BOARD_HEIGHT + BOARD_SIZE.y * 0.5 + 1.6, 0)
		add_child(title)

	## Where face `i` of the board ring hangs, facing out and tipped down.
	func _board_face(i: int) -> Transform3D:
		var radius := BOARD_SIZE.x * 0.5 / tan(PI / BOARD_FACES) + 0.1
		var angle := TAU * i / BOARD_FACES
		var at := Vector3(sin(angle), 0, cos(angle)) * radius + Vector3(0, BOARD_HEIGHT, 0)
		return Transform3D(Basis.from_euler(Vector3(0.22, angle, 0)), at)

	## Bookmakers' booths on the lowest tier, between the spectator spots:
	## a kiosk facing the pit, its screen at head height, and a spot in
	## front of it to stand on.
	func _booths() -> void:
		var floor_y := WALL_HEIGHT - 0.6
		for i in BOOTHS:
			var angle := TAU * i / BOOTHS + PI / BOOTHS
			var out := Vector3(sin(angle), 0, cos(angle))
			_add(Vector3(1.9, 2.4, 0.6), out * (WALL_RADIUS + 2.9) + Vector3(0, floor_y + 1.2, 0), angle,
					_stand_alt_mat, self)
			var marker := Marker3D.new()
			marker.name = "Booth%d" % i
			marker.position = out * (WALL_RADIUS + 1.5) + Vector3(0, floor_y, 0)
			marker.rotation.y = angle
			marker.set_meta("label", "Bookmaker: bet, duel, tournaments, or leave")
			marker.add_to_group("arena_booth")
			add_child(marker)
			# The screen faces the pit (the marker's -Z), in front of the kiosk.
			var screen := Node3D.new()
			screen.name = "Screen"
			screen.position = Vector3(0, 1.6, 1.08)
			screen.rotation.y = PI
			marker.add_child(screen)
			var glow := MeshInstance3D.new()
			var quad := QuadMesh.new()
			quad.size = Vector2(1.6, 0.9)
			var lit := StandardMaterial3D.new()
			lit.albedo_color = Color(0.16, 0.1, 0.04)
			lit.emission_enabled = true
			lit.emission = Color(1.0, 0.62, 0.22) * 0.12
			quad.material = lit
			glow.mesh = quad
			screen.add_child(glow)
			var sign_label := Label3D.new()
			sign_label.text = "BOOKMAKER"
			sign_label.font_size = 64
			sign_label.pixel_size = 0.0028
			sign_label.modulate = Color(1.0, 0.62, 0.22)
			sign_label.position = Vector3(0, 0.66, 0)
			screen.add_child(sign_label)

	## Spectators arrive on the lower tiers, spread around the ring.
	func _spectator_spots() -> void:
		for tier in 2:
			var radius := WALL_RADIUS + 0.3 + (tier + 0.5) * TIER_DEPTH
			var height := WALL_HEIGHT - 0.6 + tier * TIER_RISE + 0.1
			for i in 8:
				var angle := TAU * (i + 0.5 * tier) / 8.0 + PI / 16.0
				var marker := Marker3D.new()
				marker.position = Vector3(sin(angle) * radius, height, cos(angle) * radius)
				# Facing the pit.
				marker.rotation.y = angle
				marker.add_to_group("spawn_player")
				add_child(marker)

	# --- Building blocks ------------------------------------------------------

	## One piece `i` of a ring round the center: `radius` to its middle,
	## `depth` thick, from `bottom` to `top`.
	func _segment(i: int, radius: float, depth: float, bottom: float, top: float, material: Material,
			parent: Node3D) -> void:
		var width := 2.0 * (radius + depth * 0.5) * tan(PI / SEGMENTS) + 0.1
		var angle := TAU * i / SEGMENTS
		var at := Vector3(sin(angle), 0, cos(angle)) * radius
		at.y = (bottom + top) * 0.5
		_add(Vector3(width, top - bottom, depth), at, angle, material, parent)

	## A box that never moves: its shape joins `parent`'s shared body and its
	## mesh joins the batch for its material.
	func _add(size: Vector3, at: Vector3, yaw: float, material: Material, parent: Node3D,
			tilt := Vector3.ZERO) -> void:
		var basis := Basis.from_euler(Vector3(tilt.x, yaw, tilt.z))
		var shape := BoxShape3D.new()
		shape.size = size
		var col := CollisionShape3D.new()
		col.shape = shape
		col.transform = Transform3D(basis, at)
		_body_for(parent).add_child(col)
		var mesh := BoxMesh.new()
		mesh.size = size
		_batch(material).append_from(mesh, 0, Transform3D(basis, at))

	## The mound in the middle of the floor, its sides gentle enough to walk
	## up, and a low lip round the top in pieces, with gaps to walk through.
	func _add_dais(parent: Node3D) -> void:
		var mesh := CylinderMesh.new()
		mesh.top_radius = DAIS_RADIUS
		mesh.bottom_radius = DAIS_FOOT
		mesh.height = DAIS_HEIGHT
		mesh.radial_segments = 24
		mesh.rings = 1
		var at := Transform3D(Basis.IDENTITY, Vector3(0, DAIS_HEIGHT * 0.5, 0))
		var col := CollisionShape3D.new()
		col.shape = mesh.create_convex_shape(true, false)
		col.transform = at
		_body_for(parent).add_child(col)
		_batch(_cover_mat).append_from(mesh, 0, at)
		for i in 6:
			var angle := TAU * (i + 0.5) / 6.0
			_add(Vector3(1.3, 0.4, 0.25), Vector3(sin(angle), 0, cos(angle)) * (DAIS_RADIUS - 0.15)
					+ Vector3(0, DAIS_HEIGHT + 0.2, 0), angle, _cover_mat, parent)

	## A box that moves (a door or a rising barrier): a body of its own,
	## lowered `drop` metres to sink it.
	func _mover(size: Vector3, rest: Vector3, yaw: float, drop: float, pair: int, label: String) -> AnimatableBody3D:
		var body := AnimatableBody3D.new()
		body.name = label
		body.collision_layer = Actor.LAYER_WORLD
		body.collision_mask = 0
		body.sync_to_physics = true
		body.position = rest
		body.rotation.y = yaw
		var shape := BoxShape3D.new()
		shape.size = size
		var col := CollisionShape3D.new()
		col.shape = shape
		body.add_child(col)
		var mesh := BoxMesh.new()
		mesh.size = size
		mesh.material = _cover_mat
		var mesh_node := MeshInstance3D.new()
		mesh_node.mesh = mesh
		body.add_child(mesh_node)
		add_child(body)
		if label.begins_with("Barrier"):
			body.add_to_group("arena_barrier")
		_movers.append([body, rest, drop, pair])
		return body

	func _body_for(parent: Node3D) -> StaticBody3D:
		if not _bodies.has(parent):
			var body := StaticBody3D.new()
			body.collision_layer = Actor.LAYER_WORLD
			body.collision_mask = 0
			parent.add_child(body)
			_bodies[parent] = body
		return _bodies[parent]

	func _batch(material: Material) -> SurfaceTool:
		if not _batches.has(material):
			var tool := SurfaceTool.new()
			tool.begin(Mesh.PRIMITIVE_TRIANGLES)
			_batches[material] = tool
		return _batches[material]

	## Turns every batch into one mesh on the map.
	func _flush() -> void:
		for material in _batches:
			var tool: SurfaceTool = _batches[material]
			var mesh := tool.commit()
			mesh.surface_set_material(0, material)
			var node := MeshInstance3D.new()
			node.mesh = mesh
			if _glows.values().has(material):
				node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(node)
		_batches.clear()

	func _box_mesh(size: Vector3) -> BoxMesh:
		var mesh := BoxMesh.new()
		mesh.size = size
		return mesh

	# --- The look -------------------------------------------------------------
	# Only on a machine that draws: lit edges, team colours, the holographic
	# crowd, spotlights and banners. None of it collides or touches the rules,
	# and its randomness has its own seed so it never moves the layout.

	func _dress() -> void:
		if not Look.enabled:
			return
		_art_rng.seed = 1771
		_dress_floor()
		_dress_wall_and_stands()
		_dress_cover()
		_dress_tunnels()
		_dress_board()
		_dress_lights()
		_dress_crowd()

	func _dress_floor() -> void:
		_glow_ring(PIT_RADIUS - 0.4, 0.15, 0.02, 0.0, AMBER, 1.8, 96)
		_glow_ring(DAIS_FOOT + 0.35, 0.12, 0.02, 0.0, AMBER, 2.0, 48)
		_glow_ring(DAIS_RADIUS - 0.02, 0.06, 0.04, DAIS_HEIGHT, AMBER, 3.0, 32)
		# Each side's half of the floor is marked in its colour, round its door.
		for side in 2:
			var gate_bearing := PI * 1.5 if side == 0 else PI * 0.5
			_glow_ring(PIT_RADIUS - 1.6, 0.4, 0.02, 0.0, SIDE_COLORS[side], 2.5, 96, gate_bearing, deg_to_rad(38.0))
			# A lane from the door toward the middle.
			var dir := -1.0 if side == 0 else 1.0
			for k in 5:
				var x := dir * (PIT_RADIUS - 3.2 - k * 1.4)
				_glow(Vector3(0.7, 0.02, 0.18), Transform3D(Basis.IDENTITY, Vector3(x, 0.011, 0)), SIDE_COLORS[side], 2.0)

	func _dress_wall_and_stands() -> void:
		# The pit wall's top edge, and the front edge of every tier above it.
		_glow_ring(WALL_RADIUS - 0.32, 0.08, 0.1, WALL_HEIGHT - 0.06, AMBER, 3.0, 96)
		_glow_ring(WALL_RADIUS - 0.32, 0.05, 0.06, 1.2, AMBER, 1.2, 96)
		for tier in range(1, STAND_TIERS):
			var inner := WALL_RADIUS + 0.3 + tier * TIER_DEPTH
			var top := WALL_HEIGHT - 0.6 + tier * TIER_RISE
			_glow_ring(inner - 0.04, 0.05, 0.05, top - 0.04, AMBER, 0.7, 96)
		var rim_top := WALL_HEIGHT + STAND_TIERS * TIER_RISE + 4.0
		_glow_ring(OUTER_RADIUS - 0.04, 0.08, 0.1, rim_top - 0.08, AMBER, 1.6, 96)
		# Banners on the rim either side of each side's tunnel.
		for side in 2:
			var gate_bearing := PI * 1.5 if side == 0 else PI * 0.5
			for off: float in [-0.13, 0.13]:
				var bearing := gate_bearing + off
				var out := Vector3(sin(bearing), 0, cos(bearing))
				var banner := MeshInstance3D.new()
				var quad := QuadMesh.new()
				quad.size = Vector2(2.6, 4.6)
				var mat := StandardMaterial3D.new()
				var c: Color = SIDE_COLORS[side]
				mat.albedo_color = c.darkened(0.5)
				mat.emission_enabled = true
				mat.emission = c
				mat.emission_energy_multiplier = 0.9
				quad.material = mat
				banner.mesh = quad
				banner.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				banner.position = out * (OUTER_RADIUS - 0.05) + Vector3(0, rim_top - 3.0, 0)
				banner.rotation.y = bearing + PI
				add_child(banner)
				# A bright stripe down the middle of each banner.
				_glow(Vector3(0.18, 4.6, 0.02), Transform3D(Basis(Vector3.UP, bearing),
						out * (OUTER_RADIUS - 0.08) + Vector3(0, rim_top - 3.0, 0)), AMBER, 2.5)

	func _dress_cover() -> void:
		for p in PILLARS:
			_edges(Vector3(p[0], PILLAR_SIZE.y * 0.5, p[1]), PILLAR_SIZE, 0.0, AMBER, 2.5, true)
			_edges(Vector3(p[0], PILLAR_SIZE.y + 0.15, p[1]), Vector3(2.8, 0.3, 2.8), 0.0, AMBER, 2.5, false)
		for side in 2:
			var p: Array = PLATFORMS[side]
			_edges(Vector3(p[0], PLATFORM_SIZE.y * 0.5, p[1]), PLATFORM_SIZE, 0.0, SIDE_COLORS[side], 3.0, false)
			var b: Array = GATE_WALLS[side]
			_edges(Vector3(b[0], GATE_WALL_SIZE.y * 0.5, b[1]), GATE_WALL_SIZE, b[2], SIDE_COLORS[side], 3.0, false)
		for b in LOW_BARRIERS:
			_edges(Vector3(b[0], LOW_BARRIER_SIZE.y * 0.5, b[1]), LOW_BARRIER_SIZE, b[2], AMBER, 2.0, false)
		for bearing: float in RIM_COVER:
			var at := Vector3(cos(bearing), 0, sin(bearing)) * RIM_COVER_RADIUS + Vector3(0, RIM_COVER_SIZE.y * 0.5, 0)
			_edges(at, RIM_COVER_SIZE, -(bearing + PI / 2.0), AMBER, 2.0, false)
		# The rising barriers carry a hot warning edge on top, which still
		# shows as a line in the floor while they are sunk.
		var warn := _glow_mat(Color(1.0, 0.3, 0.1), 4.0)
		for mover in _movers:
			if int(mover[3]) < 0:
				continue
			var body: AnimatableBody3D = mover[0]
			var strip := MeshInstance3D.new()
			strip.mesh = _box_mesh(Vector3(RISING_BARRIER_SIZE.x + 0.02, 0.06, RISING_BARRIER_SIZE.z + 0.02))
			strip.material_override = warn
			strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			strip.position = Vector3(0, RISING_BARRIER_SIZE.y * 0.5 + 0.02, 0)
			body.add_child(strip)

	func _dress_tunnels() -> void:
		for side in 2:
			var dir := -1.0 if side == 0 else 1.0
			var c: Color = SIDE_COLORS[side]
			var inner := WALL_RADIUS + 0.3
			var length := TUNNEL_END - inner
			for wall_z: float in [-1.0, 1.0]:
				_glow(Vector3(length, 0.08, 0.05), Transform3D(Basis.IDENTITY, Vector3(dir * (inner + length * 0.5),
						TUNNEL_HEIGHT - 0.4, wall_z * TUNNEL_HALF_WIDTH)), c, 3.0)
				# The doorway's frame on the pit side.
				_glow(Vector3(0.1, TUNNEL_HEIGHT, 0.12), Transform3D(Basis.IDENTITY, Vector3(dir * (WALL_RADIUS - 0.32),
						TUNNEL_HEIGHT * 0.5, wall_z * (TUNNEL_HALF_WIDTH + 0.25))), c, 4.0)
			_glow(Vector3(0.1, 0.12, TUNNEL_HALF_WIDTH * 2.0 + 0.6), Transform3D(Basis.IDENTITY,
					Vector3(dir * (WALL_RADIUS - 0.32), TUNNEL_HEIGHT + 0.06, 0)), c, 4.0)
			var lamp := Look.lamp(c, 4.0, 10.0)
			lamp.position = Vector3(dir * (inner + length * 0.5), TUNNEL_HEIGHT - 0.6, 0)
			add_child(lamp)
			# The door itself glows in the side's colour.
			var door := get_node("Door%d" % side) as AnimatableBody3D
			(door.get_child(1) as MeshInstance3D).material_override = _glow_mat(c.darkened(0.3), 0.5)

	func _dress_board() -> void:
		for i in BOARD_FACES:
			var place := _board_face(i)
			for y_sign: float in [-1.0, 1.0]:
				_glow(Vector3(BOARD_SIZE.x + 0.1, 0.08, 0.1), place * Transform3D(Basis.IDENTITY,
						Vector3(0, y_sign * (BOARD_SIZE.y * 0.5 + 0.12), 0.0)), AMBER, 4.0)

	## Stadium floodlights: a ring of tall towers round the rim, each with a
	## bank of lamps tipped at the floor, so the fighters stand out from the
	## night. Every tower glows and throws a soft beam through the haze; only
	## every other one carries a real light, to keep the cost down.
	func _dress_lights() -> void:
		var centre := Look.lamp(FLOOD_COLOR, 2.0, 24.0)
		centre.position = Vector3(0, 13.0, 0)
		add_child(centre)
		var rim_top := WALL_HEIGHT + STAND_TIERS * TIER_RISE + 4.0
		var lens := _glow_mat(FLOOD_COLOR, 6.0)
		var beams := SurfaceTool.new()
		beams.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in FLOODLIGHTS:
			var bearing := TAU * (i + 0.5) / FLOODLIGHTS
			var out := Vector3(cos(bearing), 0, sin(bearing))
			var across := Vector3(-out.z, 0, out.x)
			var foot := out * (OUTER_RADIUS + 0.6) + Vector3(0, rim_top, 0)
			# The tower: a mast with two braces back to the rim.
			_batch(_wall_mat).append_from(_box_mesh(Vector3(0.7, FLOODLIGHT_HEIGHT, 0.7)), 0,
					Transform3D(Basis.IDENTITY, foot + Vector3(0, FLOODLIGHT_HEIGHT * 0.5, 0)))
			for side: float in [-1.0, 1.0]:
				var brace_from := foot + across * side * 2.2
				var brace_to := foot + Vector3(0, FLOODLIGHT_HEIGHT * 0.55, 0)
				_batch(_wall_mat).append_from(_box_mesh(Vector3(0.25, brace_from.distance_to(brace_to), 0.25)), 0,
						_between(brace_from, brace_to))
			# The lamp bank faces the middle, tipped down at the floor.
			var head := foot + Vector3(0, FLOODLIGHT_HEIGHT + 1.4, 0) - out * 0.4
			# Each bank lights its own patch across the floor, swung round
			# from straight across, so the beams spread over the floor
			# instead of meeting in the middle.
			var aim := bearing + FLOODLIGHT_SWING
			var reach: float = FLOODLIGHT_REACH[i % FLOODLIGHT_REACH.size()]
			var target := Vector3(cos(aim), 0, sin(aim)) * reach
			var facing := Basis.looking_at(target - head, Vector3.UP)
			_batch(_wall_mat).append_from(_box_mesh(Vector3(4.6, 2.8, 0.5)), 0, Transform3D(facing, head))
			_glow(Vector3(4.8, 0.1, 0.55), Transform3D(facing, head + facing * Vector3(0, 1.45, 0)), AMBER, 2.5)
			for row in 3:
				for col in 5:
					var lamp_at := head + facing * Vector3((col - 2) * 0.85, (row - 1) * 0.8, -0.3)
					_batch(lens).append_from(_box_mesh(Vector3(0.62, 0.55, 0.12)), 0, Transform3D(facing, lamp_at))
			# A soft shaft of light toward the floor.
			var length := head.distance_to(target) * 0.9
			var cone := CylinderMesh.new()
			cone.top_radius = 1.6
			cone.bottom_radius = 3.6
			cone.height = length
			cone.radial_segments = 24
			cone.rings = 1
			cone.cap_top = false
			cone.cap_bottom = false
			var down := (target - head).normalized()
			beams.append_from(cone, 0, _between(head + down * length, head))
			if i % 2 == 0:
				var spot := SpotLight3D.new()
				spot.light_color = FLOOD_COLOR
				spot.light_energy = 9.0
				spot.spot_range = 80.0
				spot.spot_angle = 34.0
				spot.spot_attenuation = 0.5
				spot.shadow_enabled = false
				add_child(spot)
				spot.look_at_from_position(head - out * 0.5, target)
		var beam_mesh := beams.commit()
		var beam_mat := ShaderMaterial.new()
		beam_mat.shader = load("res://assets/shaders/light_beam.gdshader") as Shader
		beam_mat.set_shader_parameter("tint", FLOOD_COLOR)
		beam_mesh.surface_set_material(0, beam_mat)
		var beam_node := MeshInstance3D.new()
		beam_node.name = "Beams"
		beam_node.mesh = beam_mesh
		beam_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(beam_node)

	## A transform that stands a Y-up mesh between `a` (bottom) and `b` (top).
	func _between(a: Vector3, b: Vector3) -> Transform3D:
		var up := (b - a).normalized()
		var side := up.cross(Vector3.FORWARD if absf(up.z) < 0.9 else Vector3.RIGHT).normalized()
		var basis := Basis(side, up, side.cross(up)).orthonormalized()
		return Transform3D(basis, (a + b) * 0.5)

	## The holographic crowd: glowing figures filling the stands, one draw for
	## them all. Fans on each side lean toward that side's colour.
	func _dress_crowd() -> void:
		var shader := load("res://assets/shaders/holo_crowd.gdshader") as Shader
		if shader == null:
			return
		var places: Array[Transform3D] = []
		var tints: Array[Color] = []
		for tier in STAND_TIERS:
			var inner := WALL_RADIUS + 0.3 + tier * TIER_DEPTH
			var top := WALL_HEIGHT - 0.6 + tier * TIER_RISE
			var count := int(TAU * (inner + 2.2) / 0.75)
			for i in count:
				if _art_rng.randf() > 0.7:
					continue
				var bearing := TAU * (i + _art_rng.randf() * 0.4) / count
				# Leave the bookmakers' booths clear on the lowest tier.
				if tier == 0 and _near_booth(bearing):
					continue
				# The back of the tier: the front stays clear for real spectators.
				var radius := inner + 1.9 + _art_rng.randf() * (TIER_DEPTH - 2.3)
				var height := _art_rng.randf_range(1.15, 1.4)
				var at := Vector3(sin(bearing) * radius, top + height * 0.5, cos(bearing) * radius)
				places.append(Transform3D(Basis.IDENTITY.scaled(Vector3(height * 0.55, height, 1.0)), at))
				var side := 0 if at.x < 0.0 else 1
				var tint := AMBER
				if _art_rng.randf() < 0.5:
					tint = AMBER.lerp(SIDE_COLORS[side], 0.75)
				tints.append(tint)
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.use_colors = true
		multimesh.use_custom_data = true
		var quad := QuadMesh.new()
		quad.size = Vector2(1.0, 1.0)
		var mat := ShaderMaterial.new()
		mat.shader = shader
		quad.material = mat
		multimesh.mesh = quad
		multimesh.instance_count = places.size()
		for i in places.size():
			multimesh.set_instance_transform(i, places[i])
			multimesh.set_instance_color(i, tints[i])
			multimesh.set_instance_custom_data(i, Color(_art_rng.randf(), _art_rng.randf_range(0.2, 1.0), 0, 0))
		var crowd := MultiMeshInstance3D.new()
		crowd.name = "Crowd"
		crowd.multimesh = multimesh
		crowd.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(crowd)

	func _near_booth(bearing: float) -> bool:
		for i in BOOTHS:
			var angle := TAU * i / BOOTHS + PI / BOOTHS
			if absf(wrapf(bearing - angle, -PI, PI)) < 0.12:
				return true
		return false

	## A ring of glowing strips round the center: `radius` to its middle,
	## `width` across, `height` tall, its bottom at `y`. With `span` above 0
	## only the arc within `span` of `bearing` is drawn.
	func _glow_ring(radius: float, width: float, height: float, y: float, color: Color, energy: float,
			segments: int, bearing := 0.0, span := 0.0) -> void:
		var piece := 2.0 * radius * tan(PI / segments) + 0.01
		for i in segments:
			var angle := TAU * i / segments
			if span > 0.0 and absf(wrapf(angle - bearing, -PI, PI)) > span:
				continue
			var at := Vector3(sin(angle), 0, cos(angle)) * radius + Vector3(0, y + height * 0.5, 0)
			_glow(Vector3(piece, height, width), Transform3D(Basis(Vector3.UP, angle), at), color, energy)

	## Lit edges on a box: up its four corners when `corners`, and round its top.
	func _edges(centre: Vector3, size: Vector3, yaw: float, color: Color, energy: float, corners: bool) -> void:
		var turn := Basis(Vector3.UP, yaw)
		var top := size.y * 0.5
		for sx: float in [-1.0, 1.0]:
			_glow(Vector3(0.06, 0.06, size.z + 0.06), Transform3D(turn, centre + turn * Vector3(sx * (size.x * 0.5 + 0.01), top, 0)), color, energy)
			_glow(Vector3(size.x + 0.06, 0.06, 0.06), Transform3D(turn, centre + turn * Vector3(0, top, sx * (size.z * 0.5 + 0.01))), color, energy)
			if corners:
				for sz: float in [-1.0, 1.0]:
					_glow(Vector3(0.06, size.y, 0.06), Transform3D(turn, centre + turn
							* Vector3(sx * (size.x * 0.5 + 0.01), 0, sz * (size.z * 0.5 + 0.01))), color, energy)

	## A glowing box with no collision, batched with the rest of its colour.
	func _glow(size: Vector3, place: Transform3D, color: Color, energy: float) -> void:
		_batch(_glow_mat(color, energy)).append_from(_box_mesh(size), 0, place)

	func _glow_mat(color: Color, energy: float) -> StandardMaterial3D:
		var key := [color, energy]
		if not _glows.has(key):
			var mat := StandardMaterial3D.new()
			mat.albedo_color = color.darkened(0.4)
			mat.emission_enabled = true
			mat.emission = color
			mat.emission_energy_multiplier = energy
			_glows[key] = mat
		return _glows[key]
