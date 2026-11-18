class_name Tracks
extends RefCounted
## Footprints and vehicle tracks left in open ground (DESIGN.md "Frostline"):
## the marks one world keeps, kept by the authority's `Raid` (`Raid.tracks`)
## and copied to each client only near where it stands
## (`NetSession._send_tracks`). A mark is where someone walked or drove, laid
## down after they passed, never where they are now, so following tracks is
## a trail to read, not live tracking. Marks fade after `lifetime` seconds.
##
## Kept in square cells so a nearby lookup touches only a few, and in each
## cell in the order they were made (oldest first), which is also the order
## of their ids, so a server can send a cell's new marks by the last id sent.

## What made a mark: a left or right foot, or a ground vehicle's wheels.
enum Kind { LEFT, RIGHT, TREAD }

## Metres along a side of a cell.
const CELL := 24.0
## Most marks one cell holds: the oldest go first past it, so a crowd
## trampling one spot never grows the store.
const CELL_CAP := 400

## Seconds a mark lasts.
var lifetime := 240.0
## Every mark kept: cell (Vector2i) -> Array of marks, oldest first. A mark is
## [id, position (Vector3), yaw, kind, born (the owner's clock)].
var _cells := {}
var _next_id := 1


static func cell_of(at: Vector3) -> Vector2i:
	return Vector2i(floori(at.x / CELL), floori(at.z / CELL))


## Lays a mark down and returns its id.
func add(at: Vector3, yaw: float, kind: int, born: float) -> int:
	var cell := cell_of(at)
	var marks: Array = _cells.get(cell, [])
	if marks.is_empty():
		_cells[cell] = marks
	var id := _next_id
	_next_id += 1
	marks.append([id, at, yaw, kind, born])
	if marks.size() > CELL_CAP:
		marks.pop_front()
	return id


## How many marks are kept.
func count() -> int:
	var total := 0
	for marks: Array in _cells.values():
		total += marks.size()
	return total


## The cells within `radius` of `at`.
func cells_near(at: Vector3, radius: float) -> Array[Vector2i]:
	var from := cell_of(at - Vector3(radius, 0, radius))
	var to := cell_of(at + Vector3(radius, 0, radius))
	var out: Array[Vector2i] = []
	for x in range(from.x, to.x + 1):
		for y in range(from.y, to.y + 1):
			if _cells.has(Vector2i(x, y)):
				out.append(Vector2i(x, y))
	return out


## Every mark within `radius` of `at` (flat distance).
func near(at: Vector3, radius: float) -> Array:
	var out := []
	var reach := radius * radius
	for cell in cells_near(at, radius):
		for mark: Array in _cells[cell]:
			var off: Vector3 = mark[1] - at
			if off.x * off.x + off.z * off.z <= reach:
				out.append(mark)
	return out


## A cell's marks made after the mark `after` (an id), oldest first.
func since(cell: Vector2i, after: int) -> Array:
	var marks: Array = _cells.get(cell, [])
	var out := []
	for k in range(marks.size() - 1, -1, -1):
		if int(marks[k][0]) <= after:
			break
		out.push_front(marks[k])
	return out


## Lets go of marks older than `lifetime` at the owner's clock `now`.
func expire(now: float) -> void:
	for cell: Vector2i in _cells.keys():
		var marks: Array = _cells[cell]
		while not marks.is_empty() and now - float(marks[0][4]) > lifetime:
			marks.pop_front()
		if marks.is_empty():
			_cells.erase(cell)


## Every mark within `radius` of `at` gone (a storm's fresh snow passing).
func wipe(at: Vector3, radius: float) -> void:
	var reach := radius * radius
	for cell in cells_near(at, radius):
		var marks: Array = _cells[cell]
		marks = marks.filter(func(mark: Array) -> bool:
			var off: Vector3 = mark[1] - at
			return off.x * off.x + off.z * off.z > reach)
		if marks.is_empty():
			_cells.erase(cell)
		else:
			_cells[cell] = marks


## Every mark gone at once (a whiteout's fresh snow, later).
func clear() -> void:
	_cells.clear()


## Marks packed small for the wire: x, y, z, yaw, kind and age for each.
static func pack(marks: Array, now: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(marks.size() * 6)
	var k := 0
	for mark: Array in marks:
		var at: Vector3 = mark[1]
		out[k] = at.x
		out[k + 1] = at.y
		out[k + 2] = at.z
		out[k + 3] = float(mark[2])
		out[k + 4] = float(mark[3])
		out[k + 5] = now - float(mark[4])
		k += 6
	return out


## Adds packed marks (see `pack`), aged from the clock `now`.
func unpack(data: PackedFloat32Array, now: float) -> void:
	for k in range(0, data.size() - 5, 6):
		var kind := clampi(int(data[k + 4]), 0, Kind.TREAD)
		var age := clampf(data[k + 5], 0.0, lifetime)
		add(Vector3(data[k], data[k + 1], data[k + 2]), data[k + 3], kind, now - age)
