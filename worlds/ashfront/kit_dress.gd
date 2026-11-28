extends RefCounted
## Ashfront's big greybox shapes clad in Modular Sci-Fi Megakit pieces
## (`KitMesh`), so the field's landmarks read as built things, not blocks.
## View only: the map's plain boxes stay its collision, and every piece
## here hugs a box's face (out by at most `SKIN`), so nothing you can see
## stands where you could walk into it. Called from the map's dressing,
## only where `Look` is on.

## Wall panels that are flat enough to hug a face: their front is at most
## 0.12 m (in the kit's 4 m cell) in front of the panel's plane at x = -2.
const FLAT_PANELS := ["WallBand_Straight", "WallPipe_Straight", "WallWideBand_Straight_TallBand", "WallWindow_Straight", "WallAstra_Straight_Window"]
## The panel's plane in its cell, and how far in front of a face it is set.
const PANEL_PLANE := -2.0
const PANEL_GAP := 0.03
## How far anything here may stand out from the solid under it (m), inside
## the collision check's `SKIN`.
const SKIN := 0.3
## How wide a panel is laid, about (m).
const PANEL_WIDTH := 4.0
## A box face narrower or lower than this is left plain (m).
const MIN_FACE := 0.9
## Flat deck plates, laid over a box's top.
const DECKS := ["Platform_DarkPlates", "Platform_Metal"]
## Short wall panels (2 m tall in the kit, flat), for low walls and plates.
const SHORT_PANELS := ["ShortWall_Metal2_Straight", "ShortWall_DarkMetal2_Straight", "ShortWall_Band2_Straight", "ShortWall_MetalPlates_Straight"]
## Panels for a wreck's hull: no windows.
const HULL_PANELS := ["WallBand_Straight", "WallPipe_Straight", "WallWideBand_Straight_TallBand"]


## The Forge: every tier's faces clad in panels, its windows glowing like a
## furnace, dark posts up each tier's corners, pipe-bundle columns round the
## four corner towers and vents on the plinth's roof. `mouth` (bottom
## middle, width and height) is left open on each face of the plinth for
## the furnace mouth.
static func forge(kit: KitMesh, base: Vector3, tiers: Array, tower: Vector2, mouth: Vector2, rng: RandomNumberGenerator) -> void:
	var y := -1.0
	for t in tiers.size():
		var tier: Vector2 = tiers[t]
		var height := tier.y + (1.0 if t == 0 else 0.0)
		var half := tier.x * 0.5
		for k in 4:
			var out := Vector3.FORWARD.rotated(Vector3.UP, k * PI * 0.5)
			var foot := base + out * half + Vector3(0, y, 0)
			# The plinth is laid in narrower panels, so the middle one is
			# the furnace mouth's width.
			var count := 5 if t == 0 else maxi(1, roundi(tier.x / PANEL_WIDTH))
			var skip := func(_i: int, _bottom: float, _top: float) -> bool: return false
			if t == 0:
				skip = func(i: int, bottom: float, _top: float) -> bool: return i == count / 2 and bottom < mouth.y
			clad_face(kit, foot, out, Vector3.UP, tier.x, height, count, skip, rng)
		# A dark post up each corner of the tiers above the plinth, set in so
		# it stands out of each face by little.
		if t > 0:
			for sx: float in [-1.0, 1.0]:
				for sz: float in [-1.0, 1.0]:
					var post := 0.5
					var at := base + Vector3(sx * (half - post * 0.5 + 0.2), y, sz * (half - post * 0.5 + 0.2))
					kit.add("Column_Dark", Transform3D(Basis.IDENTITY.scaled(Vector3(post, height / 5.0, post)), at), {"t1": "dark"})
		y += height
	# The corner towers wrapped in pipe-bundle columns, three high.
	var plinth: Vector2 = tiers[0]
	var corner := plinth.x * 0.5 - tower.x * 0.5
	var across := tower.x / 0.88 + 0.05
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			for level in 3:
				var rise := (tower.y + 1.0) / 3.0
				var at := base + Vector3(sx * corner, -1.0 + level * rise, sz * corner)
				var turn := Basis(Vector3.UP, rng.randi_range(0, 3) * PI * 0.5)
				kit.add("Column_Pipes", Transform3D(turn.scaled_local(Vector3(across, rise / 5.0, across)), at))
	# Vents on the plinth's roof, between the tower and its edge.
	var ring := (plinth.x + float((tiers[1] as Vector2).x)) * 0.25
	for k in 4:
		var out := Vector3.FORWARD.rotated(Vector3.UP, k * PI * 0.5)
		var along := out.cross(Vector3.UP)
		var at := base + out * ring + along * rng.randf_range(-1.5, 1.5) + Vector3(0, plinth.y + 0.07, 0)
		kit.add("Prop_Vent_Big", Transform3D(Basis(Vector3.UP, k * PI * 0.5), at))


## Clads one face of a box: a grid of `count` panels across `width` and as
## many rows as keep them about square, up `height` from `foot` (the face's
## bottom middle), facing `out` with `up` its up. A cell
## `skip.call(column, bottom, top)` turns down is left bare. Each column
## takes one of `files`, and now and then a cell above the first row one
## of `windows`.
static func clad_face(kit: KitMesh, foot: Vector3, out: Vector3, up: Vector3, width: float, height: float, count: int, skip: Callable, rng: RandomNumberGenerator,
		files: Array = FLAT_PANELS.slice(0, 3), windows: Array = FLAT_PANELS.slice(3), recolor := {}, cell := 3.0) -> void:
	var across := width / (4.0 * count)
	var rows := maxi(1, roundi(height / (cell * across)))
	var tall := height / (cell * rows)
	# Not so deep that a panel's relief stands out past `SKIN`.
	var deep := minf(across, (SKIN - PANEL_GAP) / 0.12)
	var along := out.cross(up)
	var basis := Basis(out, up, along).scaled_local(Vector3(deep, tall, across))
	for i in count:
		var file: String = files[rng.randi() % files.size()]
		for j in rows:
			var bottom := j * height / rows
			if skip.call(i, bottom, bottom + height / rows):
				continue
			var piece := file
			if j > 0 and not windows.is_empty() and rng.randf() < 0.22:
				piece = windows[rng.randi() % windows.size()]
			var at := foot + along * (-width * 0.5 + (i + 0.5) * width / count) + up * bottom
			kit.add(piece, Transform3D(basis, at + out * (PANEL_GAP - PANEL_PLANE * deep)), recolor)


## Clads a box of `size` placed at `xform` (its centre and turn): panels on
## its four sides and deck plates on top. Faces smaller than `MIN_FACE`
## either way are left plain. `cell` is the panels' height in the kit (3 m
## for a wall, 2 for a short wall).
static func clad_box(kit: KitMesh, xform: Transform3D, size: Vector3, rng: RandomNumberGenerator, files: Array, windows: Array = [], recolor := {}, cell := 3.0) -> void:
	var basis := xform.basis.orthonormalized()
	var up := basis.y
	var bottom := xform.origin - up * size.y * 0.5
	var none := func(_i: int, _b: float, _t: float) -> bool: return false
	for k in 4:
		var out: Vector3 = [basis.x, -basis.x, basis.z, -basis.z][k]
		var half: float = (size.x if k < 2 else size.z) * 0.5
		var width: float = size.z if k < 2 else size.x
		if width < MIN_FACE or size.y < MIN_FACE:
			continue
		var count := maxi(1, roundi(width / PANEL_WIDTH))
		clad_face(kit, bottom + out * half, out, up, width, size.y, count, none, rng, files, windows, recolor, cell)
	if size.x < MIN_FACE or size.z < MIN_FACE:
		return
	# Deck plates: the kit's flat 4 m platform, laid in tiles over the top.
	var nx := maxi(1, roundi(size.x / PANEL_WIDTH))
	var nz := maxi(1, roundi(size.z / PANEL_WIDTH))
	var tile := Basis(basis.x, up, basis.z).scaled_local(Vector3(size.x / (4.0 * nx), 1.0, size.z / (4.0 * nz)))
	var top := xform.origin + up * (size.y * 0.5 + PANEL_GAP)
	for i in nx:
		for j in nz:
			var at := top + basis.x * (-size.x * 0.5 + (i + 0.5) * size.x / nx) + basis.z * (-size.z * 0.5 + (j + 0.5) * size.z / nz)
			kit.add(DECKS[rng.randi() % DECKS.size()], Transform3D(tile, at), recolor)
