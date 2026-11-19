class_name RaceTrack
extends RefCounted
## A race circuit as plain data: the centre line as a closed loop of points
## a couple of metres apart, how wide the road is, and the gates a lap goes
## through in order (gate 0 is the start/finish line). It knows nothing about
## any world: a map builds one from its control points (`build`) and hands it
## to the `Race` through the map contract (`race_track()`, see `Race`).
##
## Everything here is deterministic geometry, so the server, a client and a
## headless test all judge a lap the same way.

## How far above or below a gate a crossing still counts, in metres, so a
## road running over another never passes the gate under it.
const GATE_HEIGHT := 8.0
## Distance between centre line samples, in metres.
const STEP := 2.0
## How far past a gate's edge a crossing still counts, in metres.
const GATE_MARGIN := 3.0
## How far from the centre line, past the road's edge, you may stray before
## the lap no longer counts, in metres.
const OFF_TRACK := 10.0
## Samples searched either side of the last known one before a full search.
const LOCATE_WINDOW := 40

var id := ""
var display_name := ""
## The class of machine raced here ("street").
var race_class := "street"
var width := 14.0
var laps := 3
## The centre line, closed: the last point runs on into the first.
var points := PackedVector3Array()
## Each gate: {"index": sample index, "at": Vector3, "forward": Vector3
## (the way the race runs through it), "half": half its width}.
var gates: Array[Dictionary] = []
## Where a run waits for the lights, side by side behind the line.
var start_slots: Array[Transform3D] = []
## Stretches where a kind of machine has to keep to one side, as
## [{"from", "to" (sample indices, along the race), "offset" (meters right of
## the centre), "for" ("wheels" or "hover")}]: the Spillway's ramp is the
## only way across for wheels. Read by drivers that follow the line (the
## time-trial bench), never by the race's rules.
var keep_lines: Array[Dictionary] = []
## Pit row: where a finished racer is guided and set down (`Race.PIT_RADIUS`).
## Unset (INF), the first start slot.
var pit := Vector3.INF


## Where a finished racer is set down: `pit`, or the first start slot.
func pit_spot() -> Vector3:
	if pit != Vector3.INF:
		return pit
	return start_slots[0].origin if not start_slots.is_empty() else Vector3.ZERO


## Builds the track from control points (a smooth closed curve through
## them), the road width, the spots the checkpoints stand nearest to, and
## how far behind the line the start slots wait.
static func build(p_id: String, p_name: String, control: Array[Vector3], p_width: float,
		checkpoint_spots: Array[Vector3], line_spot: Vector3, p_laps := 3, slot_count := 8) -> RaceTrack:
	var track := RaceTrack.new()
	track.id = p_id
	track.display_name = p_name
	track.width = p_width
	track.laps = p_laps
	var curve := Curve3D.new()
	var n := control.size()
	for i in n + 1:
		var p: Vector3 = control[i % n]
		var prev: Vector3 = control[(i - 1 + n) % n]
		var next: Vector3 = control[(i + 1) % n]
		var h := (next - prev) * 0.22
		curve.add_point(p, -h, h)
	curve.bake_interval = STEP * 0.5
	var length := curve.get_baked_length()
	var count := maxi(8, int(length / STEP))
	for k in count:
		track.points.append(curve.sample_baked(length * k / count))
	var spots: Array[Vector3] = [line_spot]
	spots.append_array(checkpoint_spots)
	for spot in spots:
		var i := track.locate(spot)
		track.gates.append({"index": i, "at": track.points[i], "forward": track.forward(i),
				"half": p_width * 0.5})
	# The order the race meets them in: from the line round the lap.
	var line: int = track.gates[0].index
	var rest := track.gates.slice(1)
	rest.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return posmod(a.index - line, count) < posmod(b.index - line, count))
	track.gates = [track.gates[0]] as Array[Dictionary]
	track.gates.append_array(rest)
	# Start slots: two abreast, a few metres apart, just behind the line.
	for s in slot_count:
		var back := 6 + (s / 2) * 4
		var i := posmod(line - back, count)
		var lateral := (-1.0 if s % 2 == 0 else 1.0) * p_width * 0.22
		var at := track.points[i] + track.side(i) * lateral
		track.start_slots.append(Transform3D(Basis(Vector3.UP, track.heading(i)), at))
	return track


## Lap length in metres.
func length() -> float:
	return points.size() * STEP


## The way the race runs at sample `i`, level.
func forward(i: int) -> Vector3:
	var n := points.size()
	var d := points[(i + 1) % n] - points[(i - 1 + n) % n]
	d.y = 0.0
	return d.normalized() if d.length() > 0.001 else Vector3.FORWARD


## To the right of the way the race runs at sample `i`.
func side(i: int) -> Vector3:
	return forward(i).cross(Vector3.UP).normalized()


## The yaw (`rotation.y`) that faces the way the race runs at sample `i`.
func heading(i: int) -> float:
	var f := forward(i)
	return atan2(-f.x, -f.z)


## The centre line sample nearest `pos` (level distance; a full search also
## weighs height). With a `hint` (the
## sample found last time) it looks near there first.
func locate(pos: Vector3, hint := -1) -> int:
	var n := points.size()
	if n == 0:
		return -1
	var best := -1
	var best_d := INF
	if hint >= 0:
		for k in range(-LOCATE_WINDOW, LOCATE_WINDOW + 1):
			var i := posmod(hint + k, n)
			var d := _flat(points[i] - pos)
			if d < best_d:
				best_d = d
				best = i
		if best_d < width * width:
			return best
	# A full search counts height too, so where a road runs over another
	# (Skyhook's flyover and Corkscrew) the level you are on wins.
	best_d = INF
	for i in n:
		var dy := points[i].y - pos.y
		var d := _flat(points[i] - pos) + dy * dy * 4.0
		if d < best_d:
			best_d = d
			best = i
	return best


## How far `pos` is from the centre line at sample `i`, level.
func offset(pos: Vector3, i: int) -> float:
	return sqrt(_flat(points[i] - pos))


## True if `pos` is too far off the road for the lap to count.
## Marks samples `from` to `to` as a stretch where machines of `kind`
## ("wheels" or "hover") keep `offset` meters right of the centre.
func keep_to(from: int, to: int, offset: float, kind: String) -> void:
	keep_lines.append({"from": from, "to": to, "offset": offset, "for": kind})


## Where a machine that `hovers` or not should run at sample `i`: meters
## right of the centre line (0 almost everywhere).
func line_offset(i: int, hovers: bool) -> float:
	var n := points.size()
	for entry in keep_lines:
		if str(entry.for) != ("hover" if hovers else "wheels"):
			continue
		var from := int(entry.from)
		if (i - from + n) % n <= (int(entry.to) - from + n) % n:
			return float(entry.offset)
	return 0.0


func is_off_track(pos: Vector3, i: int) -> bool:
	return offset(pos, i) > width * 0.5 + OFF_TRACK


## Where between `from` (0) and `to` (1) the move went through gate `g` the
## right way, or -1 if it did not.
func cross(g: int, from: Vector3, to: Vector3) -> float:
	var gate: Dictionary = gates[g]
	var at: Vector3 = gate.at
	var fwd: Vector3 = gate.forward
	var before := (from - at).dot(fwd)
	var after := (to - at).dot(fwd)
	if before > 0.0 or after < 0.0 or before == after:
		return -1.0
	var t := before / (before - after)
	var through := from.lerp(to, t)
	var across := fwd.cross(Vector3.UP).normalized()
	if absf((through - at).dot(across)) > float(gate.half) + GATE_MARGIN or absf(through.y - at.y) > GATE_HEIGHT:
		return -1.0
	return t


func _flat(d: Vector3) -> float:
	return d.x * d.x + d.z * d.z
