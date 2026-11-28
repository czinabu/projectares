extends Node3D
## The fortress line on Ashfront's rim (DESIGN.md "The battle around you"):
## a ruined wall of armour plate with towers along its length, standing on
## the crest just past the map's edge, so the field reads as one sector of a
## bigger front instead of a quarry. Where a battle shelf rises behind it
## (the map's `SHELVES`) the wall is broken down to low stubs and gaps, so
## the far war shows through. View only and never in a server: the map adds
## it only where `Look` is on, and it stands past the walls nobody can cross,
## so it needs no collision and is never seen up close.
##
## It is a wall that has been fought over: its height steps up and down,
## some lengths lean back, a couple a side are blown open with a fire
## burning in the breach and smoke going up, and rubble spills down the
## slope under each breach, and fallen plate lies all along the wall's
## foot on the slope's steep top, where nobody stands.
##
## Built once from a handful of Modular Sci-Fi Megakit pieces (Quaternius,
## CC0), scaled up to fortress size, and plain boxes for rubble and fire,
## merged into one mesh a side with one surface a material (`KEYS`), so the
## whole ring costs at most `KEYS.size()` draw calls a side and nothing a
## frame; only the breaches' smoke moves.

## Megakit pieces, in `assets/props/megakit` (`KitMesh`).
const WALLS := ["WallBand_Straight", "WallPipe_Straight", "WallWideBand_Straight"]
const BROKEN := "WallBand_Straight_Broken"
const STUB := "ShortWall_DarkMetal2_Straight"
const CREST := "TopCables_Straight"
const TOWERS := ["Column_Large_Straight", "Column_Large2", "Column_Large3"]
const BUTTRESS := "Column_Pipes"
## How far out from the middle the line runs (m): on the rim's crest, past
## the walls at the map's edge (3 m past them) and short of the crest's
## back, where the far land drops away out of sight.
const LINE := 317.0
## A wall piece is 4 m long and 3 m tall; scaled this much it is a 20 m
## length of 15 m wall.
const SCALE := 5.0
const SEGMENT := 4.0 * SCALE
## How much bigger a tower is than the kit's 10 m column.
const TOWER_SCALE := 3.6
## How far into the ground every piece is sunk, so no slope shows under it.
const SINK := 2.5
## Where the wall is kept low in front of a shelf, past its ends (m).
const SHELF_MARGIN := 16.0
## The surfaces a side's mesh may have, in draw order.
const KEYS := ["plate", "dark", "glow", "beacon"]
## Breaches a side (where no shelf is), each two lengths wide.
const BREACHES := 2
## Chunks of fallen plate along the foot of the wall, a side.
const TALUS := 150
## Rubble chunks spilled under each breach.
const SPILL := 46

## Set by the map: the shelves (see the map's `SHELVES`) and the ground out
## there (`ground_at(x, z)`).
var shelves: Array = []
var ground_at := Callable()
## Set by the map: makes a column of smoke (`smoke_maker.call(at, width)`).
var smoke_maker := Callable()

## Every piece laid: { "file", "at" (its foot), "side", "stacked" (on top
## of another), "box" (its bounds) } (for checks).
var pieces: Array[Dictionary] = []
## Each breach's foot, the middle of the gap on the ground (for checks).
var breaches: Array[Vector3] = []
## Each side's pieces, merged as they are laid: side -> KitMesh.
var _sides := {}


func _ready() -> void:
	name = "RimFort"
	if Look.enabled:
		build()


## Lays the line along all four sides and merges each side into one mesh.
func build() -> void:
	if not ground_at.is_valid():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 7151
	for out: Vector2 in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, -1), Vector2(0, 1)]:
		_lay_side(out, rng)
	var materials := {
		"plate": Look.surface("metal", {"tint": Color(0.8, 0.73, 0.66), "grime": 1.0, "scale": 0.05}),
		"dark": Look.surface("metal", {"tint": Color(0.36, 0.33, 0.31), "grime": 1.0, "scale": 0.05}),
		"glow": Look.trim("orange"),
		"beacon": Look.trim("beacon"),
	}
	for side: String in _sides:
		add_child((_sides[side] as KitMesh).node("Side_" + side, materials, KEYS))
	_sides.clear()


## One side: wall lengths along it, a tower every few, a couple of
## breaches, and in front of a shelf only stubs and gaps; then the slope
## below it.
func _lay_side(out: Vector2, rng: RandomNumberGenerator) -> void:
	var side := "%d_%d" % [int(out.x), int(out.y)]
	var along := Vector2(-out.y, out.x)
	var count := int(LINE * 2.0 / SEGMENT)
	var span := _shelf_span(out)
	var lows: Array[bool] = []
	for i in count:
		var l := -LINE + SEGMENT * (float(i) + 0.5)
		lows.append(l > span.x - SHELF_MARGIN and l < span.y + SHELF_MARGIN)
	# Each breach is a gap two lengths wide (`i`, `i + 1`), clear of the
	# corners and the shelves, with a broken length either side.
	var gaps: Array[int] = []
	for tries in 40:
		if gaps.size() >= BREACHES:
			break
		var i := rng.randi_range(2, count - 4)
		var clear := true
		for k in range(i - 3, i + 5):
			clear = clear and not lows[clampi(k, 0, count - 1)] and not gaps.has(k)
		if clear:
			gaps.append(i)
	for i in count:
		var l := -LINE + SEGMENT * (float(i) + 0.5)
		var spot := out * LINE + along * l
		var roll := rng.randf()
		var gap := gaps.has(i) or gaps.has(i - 1)
		var edge := gaps.has(i + 1) or gaps.has(i - 2)
		if gap:
			if gaps.has(i):
				_breach(side, out * LINE + along * (l + SEGMENT * 0.5), out, along, rng)
		elif edge:
			_wall(side, BROKEN, spot, out, along, rng.randf_range(0.0, 0.12))
		elif lows[i]:
			if roll < 0.4:
				pass
			elif roll < 0.8:
				_wall(side, STUB, spot, out, along, rng.randf_range(-0.15, 0.25))
			else:
				_wall(side, BROKEN, spot, out, along, rng.randf_range(0.0, 0.1))
		elif roll < 0.06:
			pass
		elif roll < 0.22:
			_wall(side, BROKEN, spot, out, along, 0.0)
		else:
			# A whole length: some lean back, some carry a second tier, some
			# a cabled top.
			var lean := rng.randf_range(0.05, 0.13) if rng.randf() < 0.14 else 0.0
			var file: String = WALLS[rng.randi() % WALLS.size()]
			var top := _wall(side, file, spot, out, along, lean)
			var tier := rng.randf()
			if lean == 0.0 and tier < 0.22:
				var upper: String = WALLS[rng.randi() % WALLS.size()] if tier < 0.14 else BROKEN
				top = _wall(side, upper, spot, out, along, 0.0, top.y)
			if lean == 0.0 and rng.randf() < 0.35:
				_wall(side, CREST, spot, out, along, 0.0, top.y, -3.0)
		# Between lengths: a tower now and then, else a buttress.
		if i == 0 or lows[i] or gap or (i > 0 and gaps.has(i - 2)):
			continue
		var joint := out * LINE + along * (l - SEGMENT * 0.5)
		if i % 4 == 0:
			_tower(side, joint, out, rng)
		elif rng.randf() < 0.5:
			_column(side, BUTTRESS, joint, SCALE * 0.6, 0.0)
	# A tower on the corner this side leads into.
	_tower(side, out * LINE + along * LINE, out, rng)
	_slope(side, out, along, rng)


## A breach centred on `spot`: the fire still burning in it, smoke going
## up, and rubble spilled down the slope under it.
func _breach(side: String, spot: Vector2, out: Vector2, along: Vector2, rng: RandomNumberGenerator) -> void:
	var foot := Vector3(spot.x, _ground(spot), spot.y)
	breaches.append(foot)
	var fire := BoxMesh.new()
	fire.size = Vector3(SEGMENT * 1.2, 2.5, 3.0)
	var basis := Basis(Vector3(along.x, 0, along.y), Vector3.UP, Vector3(out.x, 0, out.y))
	_append(side, "glow", fire, 0, Transform3D(basis, foot + Vector3(0, 0.4, 0)))
	if smoke_maker.is_valid():
		add_child(smoke_maker.call(foot + Vector3(0, 6.0, 0), 6.0) as Node3D)
	# Rubble: chunks of plate and wall spilled down the slope, the fan
	# widening as it runs down.
	var chunk := BoxMesh.new()
	for k in SPILL:
		var down := pow(rng.randf(), 1.6) * 22.0
		var wide := 6.0 + down * 0.7
		var at2 := spot - out * (2.0 + down) + along * rng.randf_range(-wide, wide)
		var size := Vector3(rng.randf_range(1.2, 4.5), rng.randf_range(0.6, 2.2), rng.randf_range(1.2, 4.0)) * (1.0 - down / 40.0)
		var turn := Basis.from_euler(Vector3(rng.randf_range(-0.5, 0.5), rng.randf() * TAU, rng.randf_range(-0.5, 0.5)))
		var at := Vector3(at2.x, _ground(at2) + size.y * 0.15, at2.y)
		_append(side, "plate" if k % 3 == 0 else "dark", chunk, 0, Transform3D(turn.scaled_local(size), at))


## The slope under one side: fallen plate along the wall's foot.
func _slope(side: String, out: Vector2, along: Vector2, rng: RandomNumberGenerator) -> void:
	# Talus: broken plate fallen from the wall all along its foot.
	var chunk := BoxMesh.new()
	for k in TALUS:
		var l := rng.randf_range(-LINE + 6.0, LINE - 6.0)
		var down := pow(rng.randf(), 2.0) * 9.0
		var at2 := out * (LINE - 3.5 - down) + along * l
		var size := Vector3(rng.randf_range(0.8, 3.2), rng.randf_range(0.5, 1.6), rng.randf_range(0.8, 3.0))
		var turn := Basis.from_euler(Vector3(rng.randf_range(-0.6, 0.6), rng.randf() * TAU, rng.randf_range(-0.6, 0.6)))
		var at := Vector3(at2.x, _ground(at2) + size.y * 0.1, at2.y)
		_append(side, "dark" if k % 2 == 0 else "plate", chunk, 0, Transform3D(turn.scaled_local(size), at))


## The lateral span of the shelf behind this side, or an empty one.
func _shelf_span(out: Vector2) -> Vector2:
	for shelf: Dictionary in shelves:
		if (shelf["out"] as Vector2).is_equal_approx(out):
			return shelf["lateral"]
	return Vector2(INF, -INF)


## A length of wall centred on `spot`, its face to the field, leaned back
## by `lean` (radians) when broken. Returns its foot.
func _wall(side: String, file: String, spot: Vector2, out: Vector2, along: Vector2, lean: float, base := INF, lift := 0.0) -> Vector3:
	var half := along * SEGMENT * 0.5
	var y := base
	if not is_finite(base):
		y = minf(_ground(spot), minf(_ground(spot - half), _ground(spot + half))) - SINK
	# The kit's wall stands at x = -2.1 in its cell, facing +x and running
	# along z; turned so +x faces the field and centred on the line.
	var basis := Basis(Vector3(-out.x, 0, -out.y), Vector3.UP, Vector3(-along.x, 0, -along.y))
	basis = basis * Basis(Vector3(0, 0, 1), lean)
	var at := Vector3(spot.x, y, spot.y)
	# Stacked on a wall below when `base` is given; a crest piece starts 3 m
	# up in its cell (`lift` -3 drops it onto the top).
	var xform := Transform3D(basis.scaled_local(Vector3.ONE * SCALE), at) * Transform3D(Basis.IDENTITY, Vector3(2.1, lift, 0))
	_add(side, file, xform, at, is_finite(base))
	# The piece's top: a wall is 3 m tall in its cell, a dropped crest 2 m.
	return Vector3(spot.x, y + (2.0 if lift != 0.0 else 3.0) * SCALE, spot.y)


## A tower: one of the kit's big columns, scaled up, with a red lamp on top.
## The columns are long one way (their z); that way runs along the wall, so
## none reaches in over the rim's slope.
func _tower(side: String, spot: Vector2, out: Vector2, rng: RandomNumberGenerator) -> void:
	var file: String = TOWERS[rng.randi() % TOWERS.size()]
	var yaw := (0.0 if out.y == 0.0 else PI * 0.5) + float(rng.randi() % 2) * PI
	var top := _column(side, file, spot, TOWER_SCALE, yaw)
	_beacon(side, top + Vector3(0, 0.8, 0))


## A standing piece at `spot`, its foot sunk into the ground. Returns its top.
func _column(side: String, file: String, spot: Vector2, scale: float, yaw: float) -> Vector3:
	var y := _ground(spot) - SINK
	var at := Vector3(spot.x, y, spot.y)
	var xform := Transform3D(Basis(Vector3.UP, yaw).scaled_local(Vector3.ONE * scale), at)
	_add(side, file, xform, at)
	return at + Vector3(0, 10.0 * scale if TOWERS.has(file) else 0.0, 0)


## A red warning lamp: a small box on the "beacon" trim.
func _beacon(side: String, at: Vector3) -> void:
	var box := BoxMesh.new()
	box.size = Vector3(1.6, 1.6, 1.6)
	_append(side, "beacon", box, 0, Transform3D(Basis.IDENTITY, at))


func _ground(spot: Vector2) -> float:
	return float(ground_at.call(spot.x, spot.y))


## Adds every drawable surface of a kit model at `xform` to its side.
func _add(side: String, file: String, xform: Transform3D, at: Vector3, stacked := false) -> void:
	var box := _kit(side).add(file, xform)
	pieces.append({"file": file, "at": at, "side": side, "stacked": stacked, "box": box.merge(AABB(at, Vector3.ZERO))})


func _append(side: String, key: String, mesh: Mesh, surface: int, xform: Transform3D) -> void:
	_kit(side).add_mesh(key, mesh, surface, xform)


func _kit(side: String) -> KitMesh:
	if not _sides.has(side):
		_sides[side] = KitMesh.new()
	return _sides[side]
