extends Node
## Autoload `Sfx`: placeholder sounds synthesized in code, so the game has audio
## feedback before any real sound assets exist. Does nothing on a headless
## server. Swap `_streams` entries for recorded sounds later.

const RATE := 22050

## How close a round must pass the listener to be heard going by, and how
## far from its shooter it must be (your own shots never whizz).
const PASS_RADIUS := 2.5
const PASS_CLEAR := 4.0

var _streams := {}
var _enabled := false
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_enabled = DisplayServer.get_name() != "headless"
	if not _enabled:
		return
	_rng.seed = 99
	_streams["shot"] = _noise_burst(0.16, 30.0, 0.9, 110.0)
	# Each kind of gun has a voice of its own (the item's `shot_sound`), so a
	# fight can be read by ear: a sharp pistol crack, a fast light SMG, a
	# deep shotgun boom, a long marksman report and the hand cannon's thump.
	_streams["shot_pistol"] = _noise_burst(0.12, 38.0, 0.85, 165.0)
	_streams["shot_smg"] = _noise_burst(0.09, 52.0, 0.85, 195.0)
	_streams["shot_shotgun"] = _noise_burst(0.34, 11.0, 0.95, 68.0)
	_streams["shot_dmr"] = _noise_burst(0.32, 13.0, 0.9, 82.0)
	_streams["shot_cannon"] = _noise_burst(0.28, 15.0, 0.8, 58.0)
	# A round that passes close by: a short hiss that bends down as it goes.
	_streams["whizz"] = _whizz(0.16)
	# A round striking the world near you, and the hit marker's own voices:
	# a bright ping for a head, a dull tick for plates soaking it, and a
	# glassy crack when the plates give out.
	# A soldier calling out a target: a short rising radio chirp.
	_streams["alert"] = _tones([740.0, 1110.0, 1480.0], 0.22, 9.0, 0.35)
	_streams["impact"] = _noise_burst(0.05, 70.0, 0.95, 420.0)
	_streams["headshot"] = _tones([2250.0, 3380.0], 0.13, 24.0, 0.4)
	_streams["armor_hit"] = _tones([1050.0, 1580.0], 0.06, 55.0, 0.3)
	_streams["armor_break"] = _tones([2900.0, 3720.0, 4610.0], 0.32, 10.0, 0.42)
	_streams["slam"] = _noise_burst(0.4, 9.0, 0.9, 55.0)
	_streams["block"] = _noise_burst(0.1, 40.0, 0.5, 220.0)
	_streams["hurt"] = _noise_burst(0.14, 22.0, 0.25, 85.0)
	_streams["swing"] = _whoosh(0.2)
	_streams["dash"] = _whoosh(0.28)
	_streams["hit"] = _tones([1500.0], 0.05, 60.0, 0.35)
	_streams["kill"] = _tones([900.0, 1350.0], 0.16, 18.0, 0.4)
	_streams["parry"] = _tones([1800.0, 2700.0, 3650.0], 0.35, 11.0, 0.45)
	_streams["ability"] = _tones([520.0, 1040.0, 1560.0], 0.3, 9.0, 0.4)
	_streams["loot"] = _tones([660.0, 990.0], 0.14, 20.0, 0.3)
	_streams["thrust"] = _thrust_loop(0.6)
	# Power weapons: sci-fi placeholders, picked by each gun's `shot_sound`.
	_streams["rail"] = _tones([140.0, 2300.0, 3450.0], 0.6, 6.0, 0.55)
	_streams["plasma_shot"] = _tones([220.0, 330.0, 95.0], 0.35, 8.0, 0.5)
	_streams["arc_shot"] = _tones([480.0, 960.0, 1210.0], 0.22, 14.0, 0.4)
	_streams["pulse"] = _tones([620.0, 1240.0], 0.07, 45.0, 0.3)
	_streams["plasma_burst"] = _noise_burst(0.7, 6.0, 0.95, 42.0)
	# The watch: a rising digital sweep as something materializes out of it,
	# the same falling as it goes back in, a soft chime once the watch is
	# rested, and a low buzz when it is asked for something while resting.
	_streams["summon"] = _sweep(380.0, 1900.0, 0.42, 0.35)
	_streams["store"] = _sweep(1600.0, 340.0, 0.3, 0.3)
	_streams["watch_ready"] = _tones([1320.0, 1980.0], 0.25, 12.0, 0.25)
	_streams["watch_refused"] = _tones([150.0, 157.0], 0.2, 14.0, 0.45)
	# Airborne sign-out: a rising tone played from the beacon column.
	_streams["beacon"] = _tones([520.0, 780.0, 1040.0], 0.55, 3.5, 0.5)
	# Thin ice: a sharp crack with a low groan under it as it strains, and a
	# heavy splintering crash as it gives way.
	_streams["ice_crack"] = _noise_burst(0.45, 9.0, 0.75, 48.0)
	_streams["ice_break"] = _noise_burst(1.1, 3.5, 0.95, 36.0)
	# A linked faction's call for help: two quick rising chirps.
	_streams["grid_call"] = _sweep(700.0, 2600.0, 0.32, 0.4)


## Plays a sound. With a position it is 3D and fades with distance; without
## one it plays flat, for the local player's own actions and UI.
## `reach` is how far away it can still be heard (gunfire carries further).
## How close a sound is at full volume, before it falls away with distance.
const UNIT_SIZE := 9.0


## `unit` is the distance it is heard at full volume: more carries further.
func play(sound: String, at: Variant = null, volume_db := 0.0, reach := 90.0, unit := UNIT_SIZE) -> void:
	if not _enabled or not _streams.has(sound):
		return
	if at is Vector3:
		var player := AudioStreamPlayer3D.new()
		player.stream = _streams[sound]
		player.volume_db = volume_db
		player.unit_size = unit
		player.max_distance = reach
		add_child(player)
		player.global_position = at
		player.finished.connect(player.queue_free)
		player.play()
	else:
		var player := AudioStreamPlayer.new()
		player.stream = _streams[sound]
		player.volume_db = volume_db - 4.0
		add_child(player)
		player.finished.connect(player.queue_free)
		player.play()


## A round flew from `from` to `to`, fired by `shooter`: if it passed close
## to the listener (the camera) without stopping short of them, it is heard
## going by, from the point on its line nearest to them. Your own rounds
## never are. View only, like everything here.
func pass_by(from: Vector3, to: Vector3, shooter: Node) -> void:
	if not _enabled or shooter == null or not shooter.is_inside_tree():
		return
	var camera := shooter.get_viewport().get_camera_3d()
	if camera == null:
		return
	var ear := camera.global_position
	var near := near_miss(from, to, ear)
	if near.is_finite():
		play("whizz", near, -2.0 - 3.0 * near.distance_to(ear), 20.0)


## Where a round's line from `from` to `to` passes `ear` close enough to be
## heard going by (within `PASS_RADIUS`, well clear of the shooter, and not
## stopped before it got there), or a vector of INF when it does not.
static func near_miss(from: Vector3, to: Vector3, ear: Vector3) -> Vector3:
	var line := to - from
	var length := line.length()
	if length < 0.01 or from.distance_to(ear) < PASS_CLEAR:
		return Vector3.INF
	var t := clampf((ear - from).dot(line) / (length * length), 0.0, 1.0)
	if t * length < PASS_CLEAR or t > 0.98:
		return Vector3.INF
	var near := from + line * t
	return near if near.distance_to(ear) <= PASS_RADIUS else Vector3.INF


## The raw stream, for callers that manage their own looping player.
func get_stream(sound: String) -> AudioStream:
	return _streams.get(sound)


func _noise_burst(duration: float, decay: float, noise_mix: float, thump_hz: float) -> AudioStreamWAV:
	var samples := PackedFloat32Array()
	var count := int(duration * RATE)
	var low := 0.0
	for i in count:
		var t := float(i) / RATE
		low = lerpf(low, _rng.randf_range(-1.0, 1.0), 0.45)
		var thump := sin(TAU * thump_hz * t) * exp(-t * decay * 0.6)
		samples.append((low * noise_mix + thump * 0.8) * exp(-t * decay))
	return _to_stream(samples, false)


func _whoosh(duration: float) -> AudioStreamWAV:
	var samples := PackedFloat32Array()
	var count := int(duration * RATE)
	var low := 0.0
	for i in count:
		var p := float(i) / count
		low = lerpf(low, _rng.randf_range(-1.0, 1.0), 0.08 + 0.25 * p)
		samples.append(low * sin(PI * p) * 0.7)
	return _to_stream(samples, false)


func _whizz(duration: float) -> AudioStreamWAV:
	var samples := PackedFloat32Array()
	var count := int(duration * RATE)
	var low := 0.0
	var phase := 0.0
	for i in count:
		var p := float(i) / count
		# Bright noise sliding down in pitch as the round goes by.
		low = lerpf(low, _rng.randf_range(-1.0, 1.0), lerpf(0.9, 0.35, p))
		phase += TAU * lerpf(3200.0, 1100.0, p) / RATE
		var swell := sin(PI * pow(p, 0.6))
		samples.append((low * 0.6 + sin(phase) * 0.25) * swell * 0.8)
	return _to_stream(samples, false)


func _tones(freqs: Array, duration: float, decay: float, gain: float) -> AudioStreamWAV:
	var samples := PackedFloat32Array()
	var count := int(duration * RATE)
	for i in count:
		var t := float(i) / RATE
		var v := 0.0
		for f: float in freqs:
			v += sin(TAU * f * t)
		samples.append(v / freqs.size() * exp(-t * decay) * gain)
	return _to_stream(samples, false)


## A tone gliding from `from_hz` to `to_hz`, broken into quick steps like
## something digital, rising then fading.
func _sweep(from_hz: float, to_hz: float, duration: float, gain: float) -> AudioStreamWAV:
	var samples := PackedFloat32Array()
	var count := int(duration * RATE)
	var phase := 0.0
	for i in count:
		var p := float(i) / count
		var stepped := floorf(p * 14.0) / 14.0
		var hz := lerpf(from_hz, to_hz, stepped)
		phase += TAU * hz / RATE
		var shimmer := 0.75 + 0.25 * sin(TAU * 31.0 * p * duration)
		samples.append((sin(phase) + 0.35 * sin(phase * 2.0)) * sin(PI * p) * shimmer * gain)
	return _to_stream(samples, false)


func _thrust_loop(duration: float) -> AudioStreamWAV:
	var samples := PackedFloat32Array()
	var count := int(duration * RATE)
	var low := 0.0
	for i in count:
		var t := float(i) / RATE
		low = lerpf(low, _rng.randf_range(-1.0, 1.0), 0.12)
		samples.append(low * 0.5 + sin(TAU * 70.0 * t) * 0.12)
	# Crossfade the tail into the head so the loop has no click.
	var fade := int(0.05 * RATE)
	for i in fade:
		var k := float(i) / fade
		samples[i] = samples[i] * k + samples[count - fade + i] * (1.0 - k)
	samples.resize(count - fade)
	return _to_stream(samples, true)


func _to_stream(samples: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = bytes
	if loop:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = samples.size()
	return stream
