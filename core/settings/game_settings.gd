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
## Smoothing of jagged edges, cheapest first: [name on the phone, MSAA,
## screen-space pass]. SMAA (the default) smooths every edge in one cheap
## pass after the frame; MSAA on top of it draws the outlines of shapes
## sharper, at a cost, and leaves no depth for the edge ink to read, so the
## ink is off in those modes. TAA is left out on purpose: it smears fast
## motion.
const ANTI_ALIASING := [
	["Off", Viewport.MSAA_DISABLED, Viewport.SCREEN_SPACE_AA_DISABLED],
	["Light (FXAA)", Viewport.MSAA_DISABLED, Viewport.SCREEN_SPACE_AA_FXAA],
	["Smooth (SMAA)", Viewport.MSAA_DISABLED, Viewport.SCREEN_SPACE_AA_SMAA],
	["Sharp edges (MSAA 2x + SMAA)", Viewport.MSAA_2X, Viewport.SCREEN_SPACE_AA_SMAA],
	["Best (MSAA 4x + SMAA)", Viewport.MSAA_4X, Viewport.SCREEN_SPACE_AA_SMAA],
]
const ANTI_ALIASING_DEFAULT := 2

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
## An index into `ANTI_ALIASING`.
static var anti_aliasing := ANTI_ALIASING_DEFAULT
## A thin dark outline on far shapes out in a world (`Look.edge_ink`), so
## they read against the haze. Not drawn in the MSAA modes (`ink_shown`).
static var edge_ink := true
## Low battle smoke over the ground where a planet has some
## (`PlanetType.smoke`, `Planet.GroundSmoke`): volumetric fog, so it costs
## frame time and can be switched off.
static var ground_smoke := true
static var _loaded := false


## Loads once and applies. Safe to call any number of times.
static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	load_settings()
	apply()
	# Once more after the first frame: a window still being shown at start
	# can drop the mode set before it, leaving it the other way round from
	# the setting.
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		tree.process_frame.connect(apply_window, CONNECT_ONE_SHOT)


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
	anti_aliasing = ANTI_ALIASING_DEFAULT
	edge_ink = true
	ground_smoke = true


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
		"anti_aliasing":
			anti_aliasing = clampi(int(value), 0, ANTI_ALIASING.size() - 1)
		"edge_ink":
			edge_ink = bool(value)
		"ground_smoke":
			ground_smoke = bool(value)
		_:
			return
	apply()
	save()


static func to_dict() -> Dictionary:
	return {"mouse_sensitivity": mouse_sensitivity, "invert_y": invert_y, "field_of_view": field_of_view,
			"field_of_view_third": field_of_view_third, "camera_distance": camera_distance,
			"eye_pullback": eye_pullback,
			"master_volume": master_volume, "fullscreen": fullscreen, "show_nameplates": show_nameplates,
			"anti_aliasing": anti_aliasing, "edge_ink": edge_ink, "ground_smoke": ground_smoke}


## Pushes the settings that live outside the game's own nodes: volume, the
## window and how the main view is drawn. Does nothing to the window when
## there is none.
static func apply() -> void:
	var bus := AudioServer.get_bus_index("Master")
	if bus >= 0:
		AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(master_volume, 0.0001)))
		AudioServer.set_bus_mute(bus, master_volume <= 0.001)
	if DisplayServer.get_name() == "headless":
		return
	apply_graphics()
	apply_window()


## Whether the game's window is fullscreen now, read from the window
## itself (Caleb's report: the switch read the other way round when the
## window and the saved setting disagreed). With no window, the setting.
static func window_is_full() -> bool:
	if DisplayServer.get_name() == "headless":
		return fullscreen
	var mode := DisplayServer.window_get_mode()
	return mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN


## Puts the window in the mode the setting asks for, whatever it is in now.
static func apply_window() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if window_is_full() != fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen
				else DisplayServer.WINDOW_MODE_WINDOWED)


## Sets the main view's edge smoothing (only the main view: the scope's and
## the mirror's small pictures keep their own) and shows or hides the edge
## ink on far shapes.
static func apply_graphics() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	var mode: Array = ANTI_ALIASING[anti_aliasing]
	tree.root.msaa_3d = mode[1]
	tree.root.screen_space_aa = mode[2]
	for ink: Node in tree.get_nodes_in_group("edge_ink"):
		(ink as Node3D).visible = ink_shown()
	for smoke: Node in tree.get_nodes_in_group("ground_smoke"):
		smoke.call("show_smoke", ground_smoke)


## Whether the edge ink is drawn: switched on, and no MSAA, which leaves the
## ink no depth to read.
static func ink_shown() -> bool:
	return edge_ink and ANTI_ALIASING[anti_aliasing][1] == Viewport.MSAA_DISABLED


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
