extends RefCounted
## The shape of the people's bodies at rest, for armor that fits them
## (`armor_model.gd`): how far the skin reaches out round the trunk at any
## height, and round each limb along it, for each build (`Human.BUILDS`).
## Measured from the bodies by `tools/body_fit` into `body_fit_data.gd`;
## run it again when the bodies change. View only.
##
## Plates should bridge the hollows, not follow them (the groove of the
## spine, between the pecs), so every reach read here is the widest of its
## neighbours (`reach`, `limb_reach`), never a dip.
##
## Load with `const BodyFit := preload("res://core/visual/body_fit.gd")`.

const D := preload("res://core/visual/body_fit_data.gd")


## The build to measure `build` by: a person's own, "m" for anything else.
static func build_of(build: String) -> String:
	return build if D.DATA.has(build) else "m"


## Where bone `name` sits at rest in `build`, actor frame (feet at 0, front
## -Z). A limb's is its left one; a right one is mirrored in X.
static func bone(build: String, name: String) -> Vector3:
	return D.DATA[build_of(build)]["bones"].get(name, Vector3.ZERO)


## How far out the trunk's skin reaches at height `y` (actor frame) toward
## angle `a` (0 toward -Z, PI/2 toward +X), from the upright axis through
## (0, y, `axis_z()`): the widest of the neighbouring readings.
static func reach(build: String, y: float, a: float) -> float:
	var rows: Array = _hulled(build_of(build), "trunk")
	var fy := clampf((y - D.TRUNK_LOW) / D.TRUNK_STEP, 0.0, rows.size() - 1.001)
	var j := int(fy)
	var best := 0.0
	for dj: int in [-1, 0, 1]:
		var r0 := _ring(rows[clampi(j + dj, 0, rows.size() - 1)], a)
		var r1 := _ring(rows[clampi(j + dj + 1, 0, rows.size() - 1)], a)
		var r := lerpf(r0, r1, fy - j)
		best = maxf(best, r if dj == 0 else r - 0.006)
	return best


## Whether `p` (actor frame) is inside the trunk's skin pushed out by
## `gap`: within its reach at that height and toward that side. Above or
## below the measured trunk nothing is inside.
static func inside(build: String, p: Vector3, gap := 0.0) -> bool:
	var top := D.TRUNK_LOW + D.TRUNK_STEP * (_hulled(build_of(build), "trunk").size() - 1)
	if p.y < D.TRUNK_LOW or p.y > top:
		return false
	var d := Vector2(p.x, p.z - D.TRUNK_Z)
	return d.length() < reach(build, p.y, atan2(p.x, -(p.z - D.TRUNK_Z))) + gap


## Where an upper arm's piece is carried, in each stance the trunk is
## measured in, relative to the chest: from its rest place (actor frame)
## to where it stands against the measured trunk. `out` -1 is the left
## arm, 1 the right (its mirror).
static func arm_poses(build: String, out: float) -> Array[Transform3D]:
	var poses: Array[Transform3D] = []
	var flip := Transform3D(Basis.from_scale(Vector3(-1, 1, 1)), Vector3.ZERO)
	for x: Transform3D in D.DATA[build_of(build)].get("arm_poses", []):
		poses.append(x if out < 0.0 else flip * x * flip)
	return poses


## The trunk's axis, actor frame Z.
static func axis_z() -> float:
	return D.TRUNK_Z


## A point on the trunk's skin at height `y` toward angle `a`, pushed out
## by `gap`, actor frame.
static func trunk_point(build: String, y: float, a: float, gap := 0.0) -> Vector3:
	var r := reach(build, y, a) + gap
	return Vector3(r * sin(a), y, D.TRUNK_Z - r * cos(a))


## How far out limb `limb` ("UpperArm", "LowerArm", "UpperLeg",
## "LowerLeg") reaches from its bone at `t` along it (0 at its joint, 1 at
## the next) toward angle `a` in the piece's frame (`ActorSkin._hang_limb`:
## 0 toward -Z, PI/2 toward +X). `out` -1 is the left limb, 1 the right
## (its mirror).
static func limb_reach(build: String, limb: String, t: float, a: float, out: float) -> float:
	var cuts: Array = _hulled(build_of(build), limb)
	var ang := a if out < 0.0 else -a
	var ft := clampf(t, 0.0, 1.0) * (cuts.size() - 1)
	var k := mini(int(ft), cuts.size() - 2)
	var best := 0.0
	for dk: int in [-1, 0, 1]:
		var r0 := _ring(cuts[clampi(k + dk, 0, cuts.size() - 1)], ang)
		var r1 := _ring(cuts[clampi(k + dk + 1, 0, cuts.size() - 1)], ang)
		var r := lerpf(r0, r1, ft - k)
		best = maxf(best, r if dk == 0 else r - 0.004)
	return best


## The length of `limb` in `build`, joint to joint.
static func limb_length(build: String, limb: String) -> float:
	return D.DATA[build_of(build)][limb]["length"]


## A point on limb `limb`'s skin `along` metres down it from its joint
## toward angle `a`, pushed out by `gap`, in the piece's frame (Y up the
## limb, so down it is -Y).
static func limb_point(build: String, limb: String, along: float, a: float, out: float, gap := 0.0) -> Vector3:
	var r := limb_reach(build, limb, along / limb_length(build, limb), a, out) + gap
	return Vector3(r * sin(a), -along, -r * cos(a))


## Every ring of `part` ("trunk" or a limb) in `build`, with its hollows
## bridged: each ring is replaced by its convex hull, so a plate spans the
## groove between the pecs or down the spine. Worked out once.
static var _hulls := {}


static func _hulled(build: String, part: String) -> Array:
	var key := build + ":" + part
	if _hulls.has(key):
		return _hulls[key]
	var data: Dictionary = D.DATA[build]
	var rings: Array = data["trunk"] if part == "trunk" else data[part]["cuts"]
	var out := []
	for ring: Array in rings:
		out.append(_hull_ring(ring))
	_hulls[key] = out
	return out


## A ring of reaches (evenly round from angle 0) as its convex hull's.
static func _hull_ring(ring: Array) -> Array:
	var n := ring.size()
	var pts: Array[Vector2] = []
	for i in n:
		var a := TAU * i / n
		pts.append(Vector2(sin(a), cos(a)) * float(ring[i]))
	var hull := Geometry2D.convex_hull(PackedVector2Array(pts))
	if hull.size() < 3:
		return ring
	var out := []
	for i in n:
		var a := TAU * i / n
		var dir := Vector2(sin(a), cos(a))
		var best := float(ring[i])
		for k in hull.size() - 1:
			var p := hull[k]
			var e := hull[k + 1] - p
			var den := dir.x * e.y - dir.y * e.x
			if absf(den) < 0.0000001:
				continue
			var u := (p.x * e.y - p.y * e.x) / den
			var v := (p.x * dir.y - p.y * dir.x) / den
			if u > 0.0 and v >= -0.0001 and v <= 1.0001:
				best = maxf(best, u)
		out.append(best)
	return out


## A ring's reach toward `a`, the widest of the nearest three readings
## (bridging hollows), blended between its two nearest.
static func _ring(ring: Array, a: float) -> float:
	var n := ring.size()
	var f := fposmod(a, TAU) / TAU * n
	var i := int(f) % n
	var w := f - floorf(f)
	var at := func(k: int) -> float:
		return maxf(float(ring[posmod(k, n)]), maxf(float(ring[posmod(k - 1, n)]), float(ring[posmod(k + 1, n)])) - 0.004)
	return lerpf(at.call(i), at.call(i + 1), w)
