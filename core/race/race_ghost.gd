class_name RaceGhost
extends RefCounted
## A lap as the racer drove it, for a time trial's ghost (DESIGN.md section
## 9): where the machine was and which way it faced, sampled every `STEP`
## seconds from the lap's start, and played back between the samples. View
## only: nothing in a `Race` reads it. `RaceView` records the local racer's
## laps and keeps the best per track and machine on disk.

## Seconds between samples.
const STEP := 0.1

var machine := ""
var lap_time := -1.0
var _times := PackedFloat32Array()
var _points := PackedVector3Array()
var _yaws := PackedFloat32Array()


## Adds where the machine was `time` seconds into the lap. Closer samples
## than `STEP` are skipped.
func record(time: float, at: Vector3, yaw: float) -> void:
	if not _times.is_empty() and time - _times[_times.size() - 1] < STEP * 0.99:
		return
	_times.append(time)
	_points.append(at)
	_yaws.append(yaw)


func samples() -> int:
	return _times.size()


func clear() -> void:
	_times.clear()
	_points.clear()
	_yaws.clear()
	lap_time = -1.0


## Where the ghost is `time` seconds into the lap.
func sample(time: float) -> Transform3D:
	var n := _times.size()
	if n == 0:
		return Transform3D.IDENTITY
	if time <= _times[0]:
		return _at(0, 0, 0.0)
	if time >= _times[n - 1]:
		return _at(n - 1, n - 1, 0.0)
	# Samples are evenly spaced, so start the search near the right one.
	var i := clampi(int(time / STEP), 0, n - 2)
	while i > 0 and _times[i] > time:
		i -= 1
	while i < n - 2 and _times[i + 1] < time:
		i += 1
	var span := _times[i + 1] - _times[i]
	return _at(i, i + 1, (time - _times[i]) / span if span > 0.0 else 0.0)


func _at(a: int, b: int, w: float) -> Transform3D:
	var yaw := lerp_angle(_yaws[a], _yaws[b], w)
	return Transform3D(Basis(Vector3.UP, yaw), _points[a].lerp(_points[b], w))


## As plain data for a JSON file.
func to_data() -> Dictionary:
	var flat: Array[float] = []
	for p in _points:
		flat.append_array([snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01)])
	var yaws: Array[float] = []
	for y in _yaws:
		yaws.append(snappedf(y, 0.001))
	var times: Array[float] = []
	for time in _times:
		times.append(snappedf(time, 0.001))
	return {"machine": machine, "lap": lap_time, "t": times, "p": flat, "y": yaws}


## Back from `to_data`, or null when the data is not a ghost.
static func from_data(data: Variant) -> RaceGhost:
	if not data is Dictionary:
		return null
	var times: Variant = data.get("t")
	var flat: Variant = data.get("p")
	var yaws: Variant = data.get("y")
	if not (times is Array and flat is Array and yaws is Array):
		return null
	if flat.size() != times.size() * 3 or yaws.size() != times.size() or times.is_empty():
		return null
	var ghost := RaceGhost.new()
	ghost.machine = str(data.get("machine", ""))
	ghost.lap_time = float(data.get("lap", -1.0))
	for i in times.size():
		ghost._times.append(float(times[i]))
		ghost._points.append(Vector3(float(flat[i * 3]), float(flat[i * 3 + 1]), float(flat[i * 3 + 2])))
		ghost._yaws.append(float(yaws[i]))
	return ghost
