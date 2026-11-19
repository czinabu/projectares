extends Node
## Autoload `Sfx`: placeholder sounds synthesized in code, so the game has audio
## feedback before any real sound assets exist. Does nothing on a headless
## server. A recorded sound in `RECORDED_DIR` replaces its synthesized one
## when the file is there (`recorded`); without it the synth plays.

const RATE := 22050

## How close a round must pass the listener to be heard going by, and how
## far from its shooter it must be (your own shots never whizz).
const PASS_RADIUS := 2.5
const PASS_CLEAR := 4.0

## Recorded sounds (Sonniss GDC bundle clips, see `assets/LICENSES.md`).
## They are kept out of the public repository, so each one is optional: a
## checkout without the files keeps the synthesized voice. Several takes of
## one sound are played in turn at random.
const RECORDED_DIR := "res://assets/sounds/"
const RECORDED := {
	"wind": ["wind_storm"],
	"war_rumble": ["war_rumble"],
	"far_boom": ["far_boom_1", "far_boom_2", "far_boom_3"],
}
const RECORDED_LOOPS := ["wind", "war_rumble"]

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
	# A storm's wind around you (`WeatherView`): a low, slow howl.
	_streams["wind"] = _wind_loop(3.0)
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
	# The phone buzzing in its holster: a short low rattle, twice.
	_streams["phone_buzz"] = _tones([172.0, 181.0], 0.38, 7.0, 0.35)
	# Airborne sign-out: a rising tone played from the beacon column.
	_streams["beacon"] = _tones([520.0, 780.0, 1040.0], 0.55, 3.5, 0.5)
	# Thin ice: a sharp crack with a low groan under it as it strains, and a
	# heavy splintering crash as it gives way.
	_streams["ice_crack"] = _noise_burst(0.45, 9.0, 0.75, 48.0)
	_streams["ice_break"] = _noise_burst(1.1, 3.5, 0.95, 36.0)
	# A linked faction's call for help: two quick rising chirps.
	_streams["grid_call"] = _sweep(700.0, 2600.0, 0.32, 0.4)
	# The war you cannot see (`Soundscape`): a deep, constant roll under
	# everything, a far gun's thump with its echo rolling back off the rim,
	# and a muffled burst of far gunfire.
	_streams["war_rumble"] = _rumble_loop(4.0)
	_streams["far_boom"] = _far_boom(2.6)
	_streams["far_fire"] = _far_fire(9)
	# An army's push on a strongpoint: a long low war horn, heard far off.
	_streams["war_horn"] = _tones([98.0, 147.0, 196.0], 1.8, 1.4, 0.6)
	# The war's artillery (`ShellView`): a falling whistle as a shell comes
	# in, and its blast, a deep crack with a long roll after it.
	_streams["shell_whistle"] = _sweep(2300.0, 700.0, 1.1, 0.3)
	_streams["shell_blast"] = _noise_burst(1.6, 3.2, 0.95, 38.0)
	# The race radio: a short burst of static as a rival keys up.
	_streams["radio"] = _noise_burst(0.14, 26.0, 0.7, 1300.0)
	for sound: String in RECORDED:
		var stream := recorded(sound)
		if stream != null:
			_streams[sound] = stream
	_load_weapon_sounds()


## Weapon voices made by `assets/sounds/weapons/make_weapon_sounds.py`
## (our own, from code). Each gun voice is three takes outdoors, three
## indoors and two far off; a checkout without the files keeps the synth.
const WEAPON_DIR := "res://assets/sounds/weapons/"
## Every gun voice a `shot_sound` can name, and how loud it sits against the
## others in dB (a fast gun is quieter a round, so a burst is not a wall).
const GUN_VOICES := {
	"shot_scrap": -1.0, "shot_carbine": -1.0, "shot_smg": -3.0, "shot_dmr": 0.0,
	"shot_shotgun": 0.0, "shot_pistol": -2.0, "shot_mpistol": -4.0, "shot_cannon": 0.0,
	"rail": 0.0, "plasma_shot": -1.0, "arc_shot": -2.0, "pulse": -6.0,
}
## Older names that still reach a voice: the plain "shot" every gun had.
const GUN_ALIASES := {"shot": "shot_carbine"}
## One-shots in that folder that replace a synthesized voice of the same
## name (the hit marker's voices, the draws, a charge and a spin).
const WEAPON_ONE_SHOTS := ["hit", "headshot", "armor_hit", "armor_break", "kill",
		"draw_gun", "draw_blade", "rail_charge", "storm_spin"]
const WEAPON_LOOPS := ["storm_spin"]
## Where a shot heard from far off starts to give way to its far take, and
## where only the far take is left. Sound is given its travel time past
## `FAR_FROM` (`SOUND_SPEED`), so a distant fight is seen before it is heard.
const FAR_FROM := 35.0
const FAR_ONLY := 110.0
const SOUND_SPEED := 343.0
## How far over a shot a roof must be to make it an indoor shot, and how
## long one look up is trusted for the same shooter.
const ROOF_REACH := 9.0
const ROOF_TRUST := 0.4

var _roofs := {}
var _own := {}


func _load_weapon_sounds() -> void:
	for voice: String in GUN_VOICES:
		for place: String in ["out", "in", "far"]:
			var stream := _takes(voice + "_" + place, 3 if place != "far" else 2)
			if stream != null:
				_streams[voice + "_" + place] = stream
		# The plain name plays the outdoor take, for anything that asks for it.
		if _streams.has(voice + "_out"):
			_streams[voice] = _streams[voice + "_out"]
	for alias: String in GUN_ALIASES:
		if _streams.has(GUN_ALIASES[alias] + "_out"):
			_streams[alias] = _streams[GUN_ALIASES[alias] + "_out"]
	for sound: String in WEAPON_ONE_SHOTS:
		var path: String = WEAPON_DIR + sound + ".ogg"
		if ResourceLoader.exists(path):
			var stream := load(path) as AudioStream
			if stream is AudioStreamOggVorbis and sound in WEAPON_LOOPS:
				(stream as AudioStreamOggVorbis).loop = true
			_streams[sound] = stream


## `count` takes of one sound in a randomizer that never plays the same take
## twice running, with a touch of pitch so a burst never repeats itself.
static func _takes(base: String, count: int) -> AudioStream:
	var pick := AudioStreamRandomizer.new()
	pick.random_pitch = 1.04
	pick.random_volume_offset_db = 0.8
	pick.playback_mode = AudioStreamRandomizer.PLAYBACK_RANDOM_NO_REPEATS
	for i in count:
		var path := WEAPON_DIR + "%s_%d.ogg" % [base, i + 1]
		if ResourceLoader.exists(path):
			pick.add_stream(-1, load(path))
	return pick if pick.streams_count > 0 else null


## The voice a gun's `shot_sound` names, after its aliases.
static func gun_voice(sound: String) -> String:
	return GUN_ALIASES.get(sound, sound)


## A gun going off at `at`, fired by `shooter`. Your own is played flat the
## moment it fires (no position, no travel). Anyone else's is placed in the
## world: near it is the full shot, far off its far take after the sound's
## travel time, and both answer the place: under a roof the tight indoor
## take, in the open the long echo. `reach` and `unit` are as `play`'s.
func shot(sound: String, at: Vector3, shooter: Node, own: bool, volume_db := 0.0,
		reach := 220.0, unit := UNIT_SIZE) -> void:
	if not _enabled:
		return
	var voice := gun_voice(sound)
	if not _streams.has(voice + "_out"):
		play(sound, null if own else at, volume_db, reach, unit)
		return
	var trim: float = GUN_VOICES.get(voice, 0.0)
	var room := voice + ("_in" if indoors(shooter, at) else "_out")
	if not _streams.has(room):
		room = voice + "_out"
	if own:
		_play_own(room, volume_db + trim)
		return
	var ear := _ear(shooter)
	var far := ear.distance_to(at) if ear.is_finite() else 0.0
	var fade := far_share(far)
	if fade < 1.0:
		play(room, at, volume_db + trim + linear_to_db(maxf(1.0 - fade, 0.001)), reach, unit)
	if fade > 0.0 and _streams.has(voice + "_far") and far <= reach:
		var player := _player_3d(voice + "_far", at, volume_db + trim + linear_to_db(fade) + 4.0,
				reach, unit * 2.5)
		get_tree().create_timer((far - FAR_FROM) / SOUND_SPEED).timeout.connect(player.play)


## How much of a shot `distance` metres off is its far take: none inside
## `FAR_FROM`, all of it past `FAR_ONLY`.
static func far_share(distance: float) -> float:
	return clampf((distance - FAR_FROM) / (FAR_ONLY - FAR_FROM), 0.0, 1.0)


## Your own gun: one flat player per voice that plays every round over the
## last (`max_polyphony`), so a fast gun makes no new node a shot.
func _play_own(sound: String, volume_db: float) -> void:
	var player: AudioStreamPlayer = _own.get(sound)
	if player == null or not is_instance_valid(player):
		player = AudioStreamPlayer.new()
		player.stream = _streams[sound]
		player.max_polyphony = 12
		add_child(player)
		_own[sound] = player
	player.volume_db = volume_db - 4.0
	player.play()


## Whether a shot at `at` goes off under a roof (a ceiling within
## `ROOF_REACH` overhead), so it gets the indoor take. One look up per
## shooter is trusted for `ROOF_TRUST` seconds: a gun firing twenty rounds a
## second asks once. View only: it reads the world, never changes it.
func indoors(shooter: Node, at: Vector3) -> bool:
	if not _enabled or not shooter is Node3D or not shooter.is_inside_tree():
		return false
	var key := shooter.get_instance_id()
	var now := Time.get_ticks_msec() / 1000.0
	var seen: Variant = _roofs.get(key)
	if seen is Array and now - float(seen[0]) < ROOF_TRUST:
		return seen[1]
	var roofed := roof_over((shooter as Node3D).get_world_3d(), at)
	if _roofs.size() > 256:
		_roofs.clear()
	_roofs[key] = [now, roofed]
	return roofed


## Whether the world has a roof (anything on the world layer) within
## `ROOF_REACH` straight over `at`.
static func roof_over(world: World3D, at: Vector3) -> bool:
	if world == null:
		return false
	var query := PhysicsRayQueryParameters3D.create(at, at + Vector3(0.0, ROOF_REACH, 0.0), Actor.LAYER_WORLD)
	return not world.direct_space_state.intersect_ray(query).is_empty()


## Where the listener is: the camera of the viewport `node` is drawn in.
func _ear(node: Node) -> Vector3:
	if node == null or not node.is_inside_tree():
		return Vector3.INF
	var camera := node.get_viewport().get_camera_3d()
	return camera.global_position if camera != null else Vector3.INF


func _player_3d(sound: String, at: Vector3, volume_db: float, reach: float, unit: float) -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	player.stream = _streams[sound]
	player.volume_db = volume_db
	player.unit_size = unit
	player.max_distance = reach
	add_child(player)
	player.global_position = at
	player.finished.connect(player.queue_free)
	return player


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


## The recorded stream for `sound`, or null when none of its files are here:
## one take as it is, several in a randomizer, a loop set to loop.
static func recorded(sound: String) -> AudioStream:
	var takes: Array[AudioStream] = []
	for take: String in RECORDED.get(sound, []):
		var path := RECORDED_DIR + take + ".ogg"
		if ResourceLoader.exists(path):
			var stream := load(path) as AudioStream
			if stream != null:
				takes.append(stream)
	if takes.is_empty():
		return null
	if sound in RECORDED_LOOPS:
		for stream in takes:
			if stream is AudioStreamOggVorbis:
				(stream as AudioStreamOggVorbis).loop = true
	if takes.size() == 1:
		return takes[0]
	var pick := AudioStreamRandomizer.new()
	pick.random_pitch = 1.06
	for stream in takes:
		pick.add_stream(-1, stream)
	return pick


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


func _wind_loop(duration: float) -> AudioStreamWAV:
	var samples := PackedFloat32Array()
	var count := int(duration * RATE)
	var low := 0.0
	var band := 0.0
	for i in count:
		var t := float(i) / RATE
		low = lerpf(low, _rng.randf_range(-1.0, 1.0), 0.02)
		band = lerpf(band, _rng.randf_range(-1.0, 1.0), 0.18)
		# Gusts: the howl swells and eases twice a loop.
		var swell := 0.55 + 0.45 * sin(TAU * t / duration * 2.0)
		samples.append((low * 1.6 + band * 0.25 * swell) * (0.5 + 0.5 * swell) * 0.6)
	var fade := int(0.2 * RATE)
	for i in fade:
		var k := float(i) / fade
		samples[i] = samples[i] * k + samples[count - fade + i] * (1.0 - k)
	samples.resize(count - fade)
	return _to_stream(samples, true)


func _rumble_loop(duration: float) -> AudioStreamWAV:
	var samples := PackedFloat32Array()
	var count := int(duration * RATE)
	var deep := 0.0
	var deeper := 0.0
	for i in count:
		var t := float(i) / RATE
		deep = lerpf(deep, _rng.randf_range(-1.0, 1.0), 0.006)
		deeper = lerpf(deeper, deep, 0.02)
		# It swells and eases, like a battle beyond the hills.
		var swell := 0.7 + 0.3 * sin(TAU * t / duration * 3.0)
		samples.append(deeper * 9.0 * swell)
	var fade := int(0.3 * RATE)
	for i in fade:
		var k := float(i) / fade
		samples[i] = samples[i] * k + samples[count - fade + i] * (1.0 - k)
	samples.resize(count - fade)
	return _to_stream(samples, true)


func _far_boom(duration: float) -> AudioStreamWAV:
	var count := int(duration * RATE)
	var body := PackedFloat32Array()
	body.resize(count)
	var low := 0.0
	for i in count:
		var t := float(i) / RATE
		low = lerpf(low, _rng.randf_range(-1.0, 1.0), 0.03)
		body[i] = (low * 3.0 + sin(TAU * (40.0 - 12.0 * t) * t) * 0.7) * exp(-t * 3.2)
	# The echo off the rim: the same blast again, later and softer.
	var samples := body.duplicate()
	for echo: Vector2 in [Vector2(0.38, 0.45), Vector2(0.9, 0.28), Vector2(1.5, 0.15)]:
		var at := int(echo.x * RATE)
		for i in count - at:
			samples[at + i] += body[i] * echo.y
	return _to_stream(samples, false)


func _far_fire(rounds: int) -> AudioStreamWAV:
	var gap := 0.085
	var count := int((rounds * gap + 0.4) * RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var low := 0.0
	for n in rounds:
		var start := int((n * gap + _rng.randf_range(0.0, 0.02)) * RATE)
		var loud := _rng.randf_range(0.6, 1.0)
		for i in int(0.12 * RATE):
			if start + i >= count:
				break
			var t := float(i) / RATE
			# Far away only the low crack is left.
			low = lerpf(low, _rng.randf_range(-1.0, 1.0), 0.12)
			samples[start + i] += (low * 1.8 + sin(TAU * 130.0 * t) * 0.4) * exp(-t * 38.0) * loud
	return _to_stream(samples, false)


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
