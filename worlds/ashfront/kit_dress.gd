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
			clad_face(kit, foot, out, tier.x, height, count, skip, rng)
		# A dark post up each corner of the tiers above the plinth, set in so
		# it stands out of each face by little.
		if t > 0:
			for sx: float in [-1.0, 1.0]:
				for sz: float in [-1.0, 1.0]:
					var post := 0.5
					var at := base + Vector3(sx * (half - post * 0.5 + 0.2), y, sz * (half - post * 0.5 + 0.2))
					kit.add("Column_Dark", Transform3D(Basis.IDENTITY.scaled(Vector3(post, height / 5.0, post)), at), {"plate": "dark"})
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
## bottom middle), facing `out`. A cell `skip.call(column, bottom, top)`
## turns down is left bare.
static func clad_face(kit: KitMesh, foot: Vector3, out: Vector3, width: float, height: float, count: int, skip: Callable, rng: RandomNumberGenerator) -> void:
	var across := width / (4.0 * count)
	var rows := maxi(1, roundi(height / (3.0 * across)))
	var up := height / (3.0 * rows)
	# Not so deep that a panel's relief stands out past `SKIN`.
	var deep := minf(across, (SKIN - PANEL_GAP) / 0.12)
	var along := out.cross(Vector3.UP)
	var basis := Basis(out, Vector3.UP, along).scaled_local(Vector3(deep, up, across))
	# One look per column, so a face reads as built in bays, with a window
	# now and then.
	for i in count:
		var file: String = FLAT_PANELS[rng.randi() % 3]
		for j in rows:
			var bottom := j * height / rows
			if skip.call(i, bottom, bottom + height / rows):
				continue
			var cell := file
			if j > 0 and rng.randf() < 0.22:
				cell = FLAT_PANELS[3 + rng.randi() % 2]
			var at := foot + along * (-width * 0.5 + (i + 0.5) * width / count) + Vector3(0, bottom, 0)
			kit.add(cell, Transform3D(basis, at + out * (PANEL_GAP - PANEL_PLANE * deep)))
