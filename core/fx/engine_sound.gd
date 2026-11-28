class_name EngineSound
extends Node3D
## A machine's engine, heard (`docs/systems/audio.md`). `Sfx` hangs one on every
## vehicle as it comes into the game; view only, so never on a headless
## server, and it reads only what every client already has of the machine
## (who rides it, its speed), so everyone hears the same engine.
##
## It runs only while someone rides the machine: an empty one is silent and
## costs nothing past a check of its seat. Its pitch and loudness follow the
## speed, so a machine pulling away is heard winding up. Kept affordable: an
## engine past `reach` from the ear stops, and no more than
## `Sfx.engines_at_once` run together (yours always does).

## How far off (m) an engine is heard at full sound detail.
var reach := 110.0
## The engine's pitch idling and at its top speed (a boost goes past it).
var idle_pitch := 0.75
var top_pitch := 1.45
## Its volume (dB) idling and at top speed.
var idle_db := -12.0
var top_db := -3.0
## How fast (per second) pitch and volume follow the machine.
var follow := 4.0
## Seconds the engine takes to die away once the rider is off.
var stop_time := 0.8

var vehicle: Node3D
var kind := "ground"
var _player: AudioStreamPlayer3D
var _level := 0.0
var _pitch := 1.0
var _counted := false


func _ready() -> void:
	vehicle = get_parent() as Node3D
	if vehicle == null or not "rider" in vehicle:
		set_process(false)
		return
	kind = kind_of(vehicle)
	# An airship's great engines run deep and far.
	if vehicle.get("floats"):
		idle_pitch = 0.5
		top_pitch = 0.7
		reach = 260.0


func _exit_tree() -> void:
	_release()


## Which engine a machine has: "air" for anything that flies, "hover" for a
## hoverbike, "ground" for wheels and legs.
static func kind_of(machine: Object) -> String:
	if machine.get("flies") or machine.get("floats"):
		return "air"
	if machine.get("hovers"):
		return "hover"
	return "ground"


## The engine's pitch and volume (dB) at `speed` (m/s) on a machine whose
## top speed is `top`: idle at a standstill, winding up to the top, a
## little past it on a boost.
func voice(speed: float, top: float) -> Vector2:
	var share := clampf(absf(speed) / maxf(top, 0.1), 0.0, 1.3)
	return Vector2(lerpf(idle_pitch, top_pitch, share), lerpf(idle_db, top_db, minf(share, 1.0)))


func _process(delta: float) -> void:
	var riding: bool = vehicle.get("rider") != null
	var camera := get_viewport().get_camera_3d()
	var far := reach * lerpf(0.6, 1.0, Sfx.sound_detail())
	var near := camera != null and camera.global_position.distance_squared_to(global_position) < far * far
	var own := riding and camera != null and camera.global_position.distance_to(global_position) < 8.0
	if not riding or not near:
		if _player != null and _player.playing:
			_level = move_toward(_level, 0.0, delta / stop_time)
			_player.volume_db = linear_to_db(maxf(_level, 0.001)) + idle_db
			if _level <= 0.0 or not near:
				_player.stop()
				_release()
		return
	if not _player_running(own):
		return
	_level = move_toward(_level, 1.0, delta * 2.0)
	var want := voice(float(vehicle.get("speed")), float(vehicle.get("max_speed")))
	var k := 1.0 - exp(-follow * delta)
	_pitch = lerpf(_pitch, want.x, k)
	_player.pitch_scale = maxf(_pitch, 0.1)
	_player.volume_db = lerpf(_player.volume_db, want.y + linear_to_db(maxf(_level, 0.001)), k)


## Starts the engine if it may run (under `Sfx.engines_at_once`, or it is
## yours) and says whether it runs.
func _player_running(own: bool) -> bool:
	if _player != null and _player.playing:
		return true
	if not own and Sfx.engines_running >= Sfx.engines_at_once():
		return false
	var stream := Sfx.get_stream("engine_" + kind)
	if stream == null:
		return false
	if _player == null:
		_player = AudioStreamPlayer3D.new()
		_player.unit_size = 10.0
		add_child(_player)
	_player.stream = stream
	_player.max_distance = reach
	_pitch = idle_pitch
	_player.pitch_scale = idle_pitch
	_player.volume_db = idle_db - 30.0
	_level = 0.0
	_player.play()
	if not _counted:
		_counted = true
		Sfx.engines_running += 1
	return true


func _release() -> void:
	if _counted:
		_counted = false
		Sfx.engines_running = maxi(Sfx.engines_running - 1, 0)
