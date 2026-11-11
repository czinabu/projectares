extends Node
## Autoload `Sfx`: placeholder sounds synthesized in code, so the game has audio
## feedback before any real sound assets exist. Does nothing on a headless
## server. Swap `_streams` entries for recorded sounds later.

const RATE := 22050

var _streams := {}
var _enabled := false
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_enabled = DisplayServer.get_name() != "headless"
	if not _enabled:
		return
	_rng.seed = 99
	_streams["shot"] = _noise_burst(0.16, 30.0, 0.9, 110.0)
	_streams["slam"] = _noise_burst(0.4, 9.0, 0.9, 55.0)
	_streams["block"] = _noise_burst(0.1, 40.0, 0.5, 220.0)
	_streams["hurt"] = _noise_burst(0.14, 22.0, 0.25, 85.0)
	_streams["swing"] = _whoosh(0.2)
	_streams["dash"] = _whoosh(0.28)
	_streams["hit"] = _tones([1500.0], 0.05, 60.0, 0.35)
	_streams["kill"] = _tones([900.0, 1350.0], 0.16, 18.0, 0.4)
	_streams["parry"] = _tones([1800.0, 2700.0, 3650.0], 0.35, 11.0, 0.45)
	_streams["loot"] = _tones([660.0, 990.0], 0.14, 20.0, 0.3)
	_streams["thrust"] = _thrust_loop(0.6)


## Plays a sound. With a position it is 3D and fades with distance; without
## one it plays flat, for the local player's own actions and UI.
func play(sound: String, at: Variant = null, volume_db := 0.0) -> void:
	if not _enabled or not _streams.has(sound):
		return
	if at is Vector3:
		var player := AudioStreamPlayer3D.new()
		player.stream = _streams[sound]
		player.volume_db = volume_db
		player.unit_size = 9.0
		player.max_distance = 90.0
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
