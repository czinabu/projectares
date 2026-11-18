class_name Soundscape
extends Node
## The war you cannot see, heard (DESIGN.md "Scale you can see"): a deep
## rumble under everything that rises with the war, far gunfire rattling in
## from where the fighting is, a far gun's boom arriving after its flash
## (sound is slower than light), and a quiet wind. View only: a map adds one
## only where `Look` is on, it reads the map's "war_intensity" and
## "war_centre" metas like every other view, and `Sfx` makes no sound on a
## headless server. Nothing here names a world; a map tunes it with its vars.

## Speed of sound, m/s: a far flash is heard this much later per metre.
const SOUND_SPEED := 340.0
## The longest a boom waits after its flash, so it still reads as that flash.
const BOOM_DELAY_MAX := 2.5

## The rumble's volume (dB) quiet and in all-out war.
var rumble_db := Vector2(-30.0, -13.0)
## The always-on wind's volume (dB); a storm brings its own (`WeatherView`).
var wind_db := -30.0
## Bursts of far gunfire a second, quiet and in all-out war.
var fire_rate := Vector2(0.12, 1.4)
## How far off (m) a far burst is placed from the ear, toward the fighting,
## and how widely its bearing scatters about that way (radians).
var fire_distance := 45.0
var fire_spread := 1.0
## How loud (dB) a far boom is.
var boom_db := -6.0
## How much (dB) the bed drops in the thick of a storm, where the wind is
## what you hear.
var storm_duck_db := 8.0

var _rumble: AudioStreamPlayer
var _wind: AudioStreamPlayer
var _rng := RandomNumberGenerator.new()
## Booms waiting to be heard: [seconds left, where the flash was].
var _booms: Array[Array] = []


func _ready() -> void:
	_rng.seed = 4242
	_rumble = _loop("war_rumble")
	_wind = _loop("wind")


func _loop(sound: String) -> AudioStreamPlayer:
	var stream := Sfx.get_stream(sound)
	if stream == null:
		return null
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = -60.0
	add_child(player)
	player.play()
	return player


## A far gun went off at `at` (a flash on the horizon): its boom comes once
## the sound has had time to arrive.
func boom(at: Vector3) -> void:
	var ear := _ear()
	if ear.is_finite():
		_booms.append([boom_delay(ear.distance_to(at)), at])


## How long a boom from this far off takes to arrive, capped so it still
## follows its flash.
static func boom_delay(distance: float) -> float:
	return minf(distance / SOUND_SPEED, BOOM_DELAY_MAX)


## Far gunfire bursts a second at this war intensity.
func bursts_per_second(heat: float) -> float:
	return lerpf(fire_rate.x, fire_rate.y, clampf(heat, 0.0, 1.0))


## Where a far burst is heard from: off toward the fighting from the ear,
## scattered about that way, or anywhere around when the fight is on top of
## you (or nowhere in particular).
static func burst_from(ear: Vector3, centre: Vector3, distance: float, scatter: float) -> Vector3:
	var flat := Vector3(centre.x - ear.x, 0.0, centre.z - ear.z)
	var bearing := atan2(flat.x, flat.z) + scatter if flat.length() > 60.0 else scatter * PI
	return ear + Vector3(sin(bearing), 0.15, cos(bearing)) * distance


func _ear() -> Vector3:
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	return camera.global_position if camera != null else Vector3.INF


func _process(delta: float) -> void:
	var map := get_parent()
	var heat := clampf(float(map.get_meta("war_intensity", 0.0)), 0.0, 1.0)
	var duck := storm_duck_db * Look.weather_cover
	if _rumble != null:
		_rumble.volume_db = lerpf(rumble_db.x, rumble_db.y, heat) - duck
	if _wind != null:
		_wind.volume_db = wind_db - duck
	var ear := _ear()
	if not ear.is_finite():
		return
	for i in range(_booms.size() - 1, -1, -1):
		_booms[i][0] -= delta
		if _booms[i][0] <= 0.0:
			var from: Vector3 = _booms[i][1]
			var way := Vector3(from.x - ear.x, 0.0, from.z - ear.z).normalized()
			Sfx.play("far_boom", ear + way * 50.0 + Vector3(0, 6, 0), boom_db - duck, 400.0, 40.0)
			_booms.remove_at(i)
	if _rng.randf() < bursts_per_second(heat) * delta:
		var centre: Variant = map.get_meta("war_centre", Vector3.ZERO)
		var at := burst_from(ear, centre if centre is Vector3 else Vector3.ZERO, fire_distance,
				_rng.randf_range(-fire_spread, fire_spread))
		Sfx.play("far_fire", at, _rng.randf_range(-16.0, -8.0) - duck, 300.0, 25.0)
