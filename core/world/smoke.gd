class_name Smoke
extends RefCounted
## Smoke that hides people from bots the way it hides them from a player's
## eyes (the enemy AI pass, step 1). Every cloud a player sees as a wall (a
## shell's column for now) is also kept here as a column of air: a bot's
## line of sight that passes through one sees nothing past it, unless the
## two are close enough to make each other out anyway (`see_through`).
##
## Authority only: the `Raid` ages it every tick and `BotBrain._find_target`
## asks `blocks`. What the smoke looks like stays the view's (`ShellView`),
## timed from the same landing, so the column and what it hides agree. Any
## new smoke a player cannot see through (a smoke grenade, a burning wreck
## that matters) is one more `add` where it starts, never a second check.

## Metres within which two people see each other through any smoke.
var see_through := 5.0
## At most this many clouds; the oldest gives way.
var max_clouds := 24

## Each cloud: "at" (its foot), "radius" (fully grown), "height", "life"
## (seconds it hides for), "age".
var clouds: Array[Dictionary] = []


## A cloud rises from `at`: `radius` wide once grown (it grows over its first
## few seconds), `height` tall, hiding for `life` seconds.
func add(at: Vector3, radius: float, height: float, life: float) -> void:
	clouds.append({"at": at, "radius": radius, "height": height, "life": life, "age": 0.0})
	while clouds.size() > max_clouds:
		clouds.pop_front()


func tick(delta: float) -> void:
	if clouds.is_empty():
		return
	for i in range(clouds.size() - 1, -1, -1):
		var cloud: Dictionary = clouds[i]
		cloud.age = float(cloud.age) + delta
		if float(cloud.age) >= float(cloud.life):
			clouds.remove_at(i)


func clear() -> void:
	clouds.clear()


## How wide a cloud is now: it billows out over its first few seconds and
## thins over its last.
static func width_of(cloud: Dictionary) -> float:
	var age := float(cloud.age)
	var grown := clampf(age / 3.0, 0.35, 1.0)
	var fading := clampf((float(cloud.life) - age) / 3.0, 0.0, 1.0)
	return float(cloud.radius) * grown * lerpf(0.5, 1.0, fading)


## Whether smoke stands between `from` and `to`.
func blocks(from: Vector3, to: Vector3) -> bool:
	if clouds.is_empty() or from.distance_to(to) <= see_through:
		return false
	for cloud: Dictionary in clouds:
		var foot: Vector3 = cloud.at
		var top := foot + Vector3(0.0, float(cloud.height), 0.0)
		var gap := segment_gap(from, to, foot, top)
		if gap < width_of(cloud):
			return true
	return false


## The closest two segments (`a0`-`a1` and `b0`-`b1`) come to each other.
static func segment_gap(a0: Vector3, a1: Vector3, b0: Vector3, b1: Vector3) -> float:
	var d1 := a1 - a0
	var d2 := b1 - b0
	var r := a0 - b0
	var a := d1.dot(d1)
	var e := d2.dot(d2)
	var f := d2.dot(r)
	var s := 0.0
	var t := 0.0
	if a <= 1e-6 and e <= 1e-6:
		return a0.distance_to(b0)
	if a <= 1e-6:
		t = clampf(f / e, 0.0, 1.0)
	else:
		var c := d1.dot(r)
		if e <= 1e-6:
			s = clampf(-c / a, 0.0, 1.0)
		else:
			var b := d1.dot(d2)
			var denom := a * e - b * b
			if denom > 1e-6:
				s = clampf((b * f - c * e) / denom, 0.0, 1.0)
			t = (b * s + f) / e
			if t < 0.0:
				t = 0.0
				s = clampf(-c / a, 0.0, 1.0)
			elif t > 1.0:
				t = 1.0
				s = clampf((b - c) / a, 0.0, 1.0)
	return (a0 + d1 * s).distance_to(b0 + d2 * t)
