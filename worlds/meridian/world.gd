extends WorldDef
## Meridian: a tidally locked launch world where the sun never leaves the
## horizon. The war made its mass driver worthless; now the Meridian Circuit
## races through the dead launch works. Nobody fights here and nobody loses
## gear: you race the track's stock machines against the clock and your own
## ghost (DESIGN.md section 9). Run by `Race`.

const MapScript := preload("res://worlds/meridian/map.gd")
const SkyhookScript := preload("res://worlds/meridian/skyhook.gd")


var _feed_tracks: Array[RaceTrack] = []


func _init() -> void:
	take_planet("saltflat")
	# The pan's crust is slick, but the circuits are paved and the race
	# profiles are tuned on full grip (DESIGN.md section 9).
	planet_grip = 1.0
	id = "meridian"
	display_name = "Meridian"
	description = "The racing world. Time trials on Coilrun and Skyhook in stock street machines. Nobody fights, nobody loses gear."
	gear_at_risk = false
	weapons_free = false
	bot_count = 0
	war_scale = 0.0
	power_weapon_rate = 0.0
	warlord_artifact_chance = 0.0
	pod_artifact_chance = 0.0
	event_interval = 0.0
	# The machines are the track's, never thrown from a watch.
	vehicle_toys = false
	# An abandoned machine goes back to its bay soon, and an empty bay fills.
	vehicle_respawn_time = 4.0
	sign_out_time = 3.0
	sign_out_air_time = 3.0
	spawn_protection = 0.0
	max_players = 16


func create_map() -> Node3D:
	var map := MapScript.new()
	map.planet = planet_type()
	return map


func new_raid() -> Raid:
	return Race.new()


## Coilrun and Skyhook, for the War Room's track cam.
func feed_tracks() -> Array[RaceTrack]:
	if _feed_tracks.is_empty():
		_feed_tracks = [MapScript.build_coilrun(), SkyhookScript.build_track()]
	return _feed_tracks


## Each pit bay holds the stock machine its marker names.
func roll_loot(source: String, _rng: RandomNumberGenerator) -> Array[String]:
	match source:
		"bay_scrapper":
			return ["bike_scrapper"] as Array[String]
		"bay_raider":
			return ["bike_raider"] as Array[String]
	return [] as Array[String]


## Nothing you own is needed or at risk here: you race in what you wear.
func starter_loadout() -> Array[String]:
	return [Loadout.BARE] as Array[String]
