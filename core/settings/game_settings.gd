extends RefCounted
## The player's settings, changed from the phone and kept in their own file so
## they never mix with the stash save. One shared copy, held in static vars:
## load with `const GameSettings := preload("res://core/settings/game_settings.gd")`
## and read `GameSettings.mouse_sensitivity` and so on.
##
## Only the local game reads these. A server never does, and nothing here
## changes how the simulation runs: they are about how the game looks, sounds
## and feels in your hands. (The melee side control lives in `Profile`, which
## already saves it.)

const SAVE_PATH := "user://settings.json"
const SENSITIVITY_RANGE := Vector2(0.0005, 0.006)
const FOV_RANGE := Vector2(60.0, 110.0)
## How far behind the character the third-person camera sits, in meters.
const CAMERA_DISTANCE_RANGE := Vector2(1.2, 4.5)
## How far the first-person camera sits back from the face, in meters.
const EYE_PULLBACK_RANGE := Vector2(0.0, 0.25)

## Tests turn this off so they never touch a real settings file.
static var persist := true
static var mouse_sensitivity := 0.0022
static var invert_y := false
## Field of view in first person, and in third person. Each applies only while
## that view is active. (The first-person one keeps the old saved key.)
static var field_of_view := 80.0
static var field_of_view_third := 80.0
static var camera_distance := 2.0
static var eye_pullback := 0.15
## 0 to 1, applied to the master audio bus.
static var master_volume := 0.8
static var fullscreen := false
static var show_nameplates := true
static var _loaded := false


## Loads once and applies. Safe to call any number of times.
static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	load_settings()
	apply()


static func reset() -> void:
	mouse_sensitivity = 0.0022
	invert_y = false
	field_of_view = 80.0
	field_of_view_third = 80.0
	camera_distance = 2.0
	eye_pullback = 0.15
	master_volume = 0.8
	fullscreen = false
	show_nameplates = true


static func set_value(key: String, value: Variant) -> void:
	match key:
		"mouse_sensitivity":
			mouse_sensitivity = clampf(float(value), SENSITIVITY_RANGE.x, SENSITIVITY_RANGE.y)
		"invert_y":
			invert_y = bool(value)
		"field_of_view":
			field_of_view = clampf(float(value), FOV_RANGE.x, FOV_RANGE.y)
		"field_of_view_third":
			field_of_view_third = clampf(float(value), FOV_RANGE.x, FOV_RANGE.y)
		"camera_distance":
			camera_distance = clampf(float(value), CAMERA_DISTANCE_RANGE.x, CAMERA_DISTANCE_RANGE.y)
		"eye_pullback":
			eye_pullback = clampf(float(value), EYE_PULLBACK_RANGE.x, EYE_PULLBACK_RANGE.y)
		"master_volume":
			master_volume = clampf(float(value), 0.0, 1.0)
		"fullscreen":
			fullscreen = bool(value)
		"show_nameplates":
			show_nameplates = bool(value)
		_:
			return
	apply()
	save()


static func to_dict() -> Dictionary:
	return {"mouse_sensitivity": mouse_sensitivity, "invert_y": invert_y, "field_of_view": field_of_view,
			"field_of_view_third": field_of_view_third, "camera_distance": camera_distance,
			"eye_pullback": eye_pullback,
			"master_volume": master_volume, "fullscreen": fullscreen, "show_nameplates": show_nameplates}


## Pushes the settings that live outside the game's own nodes: volume and the
## window. Does nothing to the window when there is none.
static func apply() -> void:
	var bus := AudioServer.get_bus_index("Master")
	if bus >= 0:
		AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(master_volume, 0.0001)))
		AudioServer.set_bus_mute(bus, master_volume <= 0.001)
	if DisplayServer.get_name() == "headless":
		return
	var want := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	var mode := DisplayServer.window_get_mode()
	var is_full := mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	if is_full != fullscreen:
		DisplayServer.window_set_mode(want)


static func save() -> void:
	if not persist:
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("GameSettings: could not write %s" % SAVE_PATH)
		return
	file.store_string(JSON.stringify(to_dict(), "\t"))


static func load_settings() -> void:
	if not persist or not FileAccess.file_exists(SAVE_PATH):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if typeof(data) != TYPE_DICTIONARY:
		push_warning("GameSettings: %s is unreadable, using defaults" % SAVE_PATH)
		return
	var was_persisting := persist
	persist = false
	for key: String in to_dict():
		if data.has(key):
			set_value(key, data[key])
	persist = was_persisting
