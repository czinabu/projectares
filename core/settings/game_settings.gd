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
## How the sun's shadows are drawn, best first: [name on the phone, splits
## (0 for none), share of the world's own shadow reach, shadow map size].
## "High" is the world as it was made; the others are for a slower graphics
## card, since every shadow split draws everything in it once more.
const SHADOWS := [
	["High", 4, 1.0, 4096],
	["Medium", 2, 0.6, 4096],
	["Low", 2, 0.35, 2048],
	["Off", 0, 0.0, 2048],
]
## Drawing the 3D view smaller and sharpening it up to the screen (AMD FSR
## 1), cheapest last: [name on the phone, scale]. The phone, the HUD and
## text are always drawn at full size.
const RENDER_SCALE := [
	["Full", 1.0],
	["Quality (77%)", 0.77],
	["Balanced (67%)", 0.67],
	["Performance (50%)", 0.5],
]
## How far and in how much detail a world is drawn, best first: [name on the
## phone, share of the world's own view reach (`view_far_for`), how far small
## things are drawn (a share of `Look`'s size rule), how far anything bigger
## is drawn (0: as far as the camera sees), mesh detail (the main view's
## `mesh_lod_threshold`: lower keeps more of a model's detail further out)].
## "High" is each world as it was made; "Ultra" draws the small things
## nearly twice as far and keeps model detail longer; "Medium" and "Low" are
## for a slower graphics card. (Caleb's ask: a short view spoils it.)
const VIEW_DISTANCE := [
	["Ultra", 1.0, 1.8, 0.0, 0.4],
	["High", 1.0, 1.0, 0.0, 1.0],
	["Medium", 0.75, 0.75, 1200.0, 1.5],
	["Low", 0.5, 0.5, 700.0, 2.5],
]
const VIEW_DISTANCE_DEFAULT := 1

## Every setting, in the order the phone's Settings app shows it (Caleb's
## call: a new setting is one row here and its var below, never new code in
## the phone). Each row: "key" (the var and the save file's key), "tab" (one
## of `Phone.SETTINGS_TABS`), "section" (a heading drawn above the first row
## of each section), "kind" ("slider", "toggle" or "choice"), "label",
## "default", and by kind: a slider's "range", "step" and "format" (see
## `shown`), a choice's "choices" (rows whose first field is the name on the
## phone). "preview" marks a view setting whose slider lets the view go while
## dragged. A row whose "tab" is "" is kept and saved but never drawn on the
## phone: a "list" (of strings) or a "text".
const SCHEMA := [
	{"key": "mouse_sensitivity", "tab": "input", "kind": "slider", "label": "Mouse sensitivity",
			"default": 0.0022, "range": SENSITIVITY_RANGE, "step": 0.0001, "format": "sensitivity"},
	{"key": "invert_y", "tab": "input", "kind": "toggle", "label": "Invert mouse up and down", "default": false},
	{"key": "fullscreen", "tab": "view", "section": "DISPLAY", "kind": "toggle", "label": "Fullscreen",
			"default": false},
	{"key": "anti_aliasing", "tab": "view", "section": "DISPLAY", "kind": "choice", "label": "Smooth edges",
			"default": ANTI_ALIASING_DEFAULT, "choices": ANTI_ALIASING},
	{"key": "edge_ink", "tab": "view", "section": "DISPLAY", "kind": "toggle",
			"label": "Outline far shapes (not with MSAA)", "default": true},
	{"key": "shadows", "tab": "view", "section": "PERFORMANCE", "kind": "choice", "label": "Shadows",
			"default": 0, "choices": SHADOWS},
	{"key": "render_scale", "tab": "view", "section": "PERFORMANCE", "kind": "choice", "label": "Render scale",
			"default": 0, "choices": RENDER_SCALE},
	{"key": "view_distance", "tab": "view", "section": "PERFORMANCE", "kind": "choice", "label": "View distance",
			"default": VIEW_DISTANCE_DEFAULT, "choices": VIEW_DISTANCE},
	{"key": "ambient_occlusion", "tab": "view", "section": "PERFORMANCE", "kind": "toggle",
			"label": "Ambient occlusion", "default": true},
	{"key": "ground_smoke", "tab": "view", "section": "PERFORMANCE", "kind": "toggle",
			"label": "Battle smoke over the ground", "default": true},
	{"key": "field_of_view", "tab": "view", "section": "CAMERA", "kind": "slider",
			"label": "Field of view, first person", "default": 80.0, "range": FOV_RANGE, "step": 1.0,
			"format": "whole", "preview": true},
	{"key": "field_of_view_third", "tab": "view", "section": "CAMERA", "kind": "slider",
			"label": "Field of view, third person", "default": 80.0, "range": FOV_RANGE, "step": 1.0,
			"format": "whole", "preview": true},
	{"key": "camera_distance", "tab": "view", "section": "CAMERA", "kind": "slider",
			"label": "Camera distance, third person", "default": 2.0, "range": CAMERA_DISTANCE_RANGE,
			"step": 0.1, "format": "metres", "preview": true},
	{"key": "eye_pullback", "tab": "view", "section": "CAMERA", "kind": "slider",
			"label": "Camera pulled back, first person", "default": 0.15, "range": EYE_PULLBACK_RANGE,
			"step": 0.01, "format": "centimetres", "preview": true},
	{"key": "show_nameplates", "tab": "view", "section": "CAMERA", "kind": "toggle",
			"label": "Names over other players", "default": true},
	{"key": "master_volume", "tab": "system", "kind": "slider", "label": "Volume", "default": 0.8,
			"range": Vector2(0.0, 1.0), "step": 0.05, "format": "percent"},
	# Kept but not on a Settings tab ("tab" ""): the watch's mission log.
	{"key": "untracked", "tab": "", "kind": "list", "default": []},
	{"key": "main_mission", "tab": "", "kind": "text", "default": ""},
]

## Tests turn this off so they never touch a real settings file.
static var persist := true
## The values, by `SCHEMA` key. The typed vars below read and write here.
static var _values := {}
static var _loaded := false

static var mouse_sensitivity: float:
	get: return _values["mouse_sensitivity"]
	set(v): _values["mouse_sensitivity"] = v
static var invert_y: bool:
	get: return _values["invert_y"]
	set(v): _values["invert_y"] = v
## Field of view in first person, and in third person. Each applies only while
## that view is active. (The first-person one keeps the old saved key.)
static var field_of_view: float:
	get: return _values["field_of_view"]
	set(v): _values["field_of_view"] = v
static var field_of_view_third: float:
	get: return _values["field_of_view_third"]
	set(v): _values["field_of_view_third"] = v
## How far behind the character the third-person camera sits, in meters.
static var camera_distance: float:
	get: return _values["camera_distance"]
	set(v): _values["camera_distance"] = v
## How far the first-person camera sits back from the face, in meters.
static var eye_pullback: float:
	get: return _values["eye_pullback"]
	set(v): _values["eye_pullback"] = v
## 0 to 1, applied to the master audio bus.
static var master_volume: float:
	get: return _values["master_volume"]
	set(v): _values["master_volume"] = v
static var fullscreen: bool:
	get: return _values["fullscreen"]
	set(v): _values["fullscreen"] = v
static var show_nameplates: bool:
	get: return _values["show_nameplates"]
	set(v): _values["show_nameplates"] = v
## An index into `ANTI_ALIASING`.
static var anti_aliasing: int:
	get: return _values["anti_aliasing"]
	set(v): _values["anti_aliasing"] = v
## A thin dark outline on far shapes out in a world (`Look.edge_ink`), so
## they read against the haze. Not drawn in the MSAA modes (`ink_shown`).
static var edge_ink: bool:
	get: return _values["edge_ink"]
	set(v): _values["edge_ink"] = v
## An index into `SHADOWS`.
static var shadows: int:
	get: return _values["shadows"]
	set(v): _values["shadows"] = v
## An index into `RENDER_SCALE`.
static var render_scale: int:
	get: return _values["render_scale"]
	set(v): _values["render_scale"] = v
## Ambient occlusion (the soft shade in corners and under things).
static var ambient_occlusion: bool:
	get: return _values["ambient_occlusion"]
	set(v): _values["ambient_occlusion"] = v
## Low battle smoke over the ground where a planet has some
## (`PlanetType.smoke`, `Planet.GroundSmoke`): volumetric fog, so it costs
## frame time and can be switched off.
static var ground_smoke: bool:
	get: return _values["ground_smoke"]
	set(v): _values["ground_smoke"] = v
## The watch's mission log: what the player took off the visor's objective
## block (a contract's id, or `TOUR_KEY` for the new player's tour). Every
## mission is tracked until it is picked off. View only.
static var untracked: Array[String]:
	get: return _values["untracked"]
	set(v): _values["untracked"] = v
const TOUR_KEY := "tour"
## The one mission pinned as the main one (a key as in `untracked`, "" for
## none): listed first and lit on the visor. View only.
static var main_mission: String:
	get: return _values["main_mission"]
	set(v): _values["main_mission"] = v
## An index into `VIEW_DISTANCE`.
static var view_distance: int:
	get: return _values["view_distance"]
	set(v): _values["view_distance"] = v


static func _static_init() -> void:
	reset()


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
	for row: Dictionary in SCHEMA:
		if row["kind"] == "list":
			var list: Array[String] = []
			_values[row["key"]] = list
		else:
			_values[row["key"]] = row["default"]


## The `SCHEMA` row for a key, or an empty one.
static func row_of(key: String) -> Dictionary:
	for row: Dictionary in SCHEMA:
		if row["key"] == key:
			return row
	return {}


## The rows one Settings tab shows, in order.
static func rows_in(tab: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for row: Dictionary in SCHEMA:
		if row["tab"] == tab:
			out.append(row)
	return out


## What a setting is now, as the phone shows it. Fullscreen is read off the
## window itself (`window_is_full`).
static func value_of(key: String) -> Variant:
	if key == "fullscreen":
		return window_is_full()
	return _values.get(key)


## A slider's value as the phone writes it beside the slider, by the row's
## "format".
static func shown(row: Dictionary, value: float) -> String:
	match row.get("format", ""):
		"sensitivity":
			return "%.1f" % (value * 1000.0)
		"whole":
			return "%d" % roundi(value)
		"metres":
			return "%.1f m" % value
		"centimetres":
			return "%d cm" % roundi(value * 100.0)
		"percent":
			return "%d%%" % roundi(value * 100.0)
	return "%.2f" % value


static func set_value(key: String, value: Variant) -> void:
	var row := row_of(key)
	if row.is_empty():
		return
	match row["kind"]:
		"slider":
			var range_: Vector2 = row["range"]
			_values[key] = clampf(float(value), range_.x, range_.y)
		"toggle":
			_values[key] = bool(value)
		"choice":
			_values[key] = clampi(int(value), 0, (row["choices"] as Array).size() - 1)
		"text":
			_values[key] = str(value)
		"list":
			var list: Array[String] = []
			if value is Array:
				for each: Variant in value:
					if str(each) != "" and str(each) not in list:
						list.append(str(each))
			_values[key] = list
	apply()
	save()


static func to_dict() -> Dictionary:
	return _values.duplicate(true)


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


## Sets the main view's edge smoothing and render scale (only the main
## view: the scope's and the mirror's small pictures keep their own), shows
## or hides the edge ink on far shapes, and fits every world's sun and
## atmosphere to the shadow and ambient occlusion settings.
static func apply_graphics() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	var mode: Array = ANTI_ALIASING[anti_aliasing]
	tree.root.msaa_3d = mode[1]
	tree.root.screen_space_aa = mode[2]
	var scale: float = RENDER_SCALE[render_scale][1]
	tree.root.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if scale < 1.0 else Viewport.SCALING_3D_MODE_BILINEAR
	tree.root.scaling_3d_scale = scale
	for ink: Node in tree.get_nodes_in_group("edge_ink"):
		(ink as Node3D).visible = ink_shown()
	RenderingServer.directional_shadow_atlas_set_size(SHADOWS[shadows][3], true)
	for sun: Node in tree.get_nodes_in_group(SUN_GROUP):
		fit_sun(sun as DirectionalLight3D)
	for atmosphere: Node in tree.get_nodes_in_group(ATMOSPHERE_GROUP):
		fit_atmosphere(atmosphere as WorldEnvironment)
	for smoke: Node in tree.get_nodes_in_group("ground_smoke"):
		smoke.call("show_smoke", ground_smoke)
	tree.root.mesh_lod_threshold = VIEW_DISTANCE[view_distance][4]
	for map: Node in tree.get_nodes_in_group(DRAWN_MAP_GROUP):
		Look.fit_draw_distance(map as Node3D)


## A world's sun and atmosphere (`Look.atmosphere`) are in these groups, so
## a changed setting reaches the world already standing.
const SUN_GROUP := "world_sun"
const ATMOSPHERE_GROUP := "world_atmosphere"


## Fits a world's sun to the shadow setting. `reach` is how far the world
## itself draws its shadows (kept on the sun for later changes); without one
## the sun keeps the reach it was given last.
static func fit_sun(sun: DirectionalLight3D, reach := -1.0) -> void:
	if sun == null:
		return
	if reach > 0.0:
		sun.set_meta("shadow_reach", reach)
	var own: float = sun.get_meta("shadow_reach", sun.directional_shadow_max_distance)
	var pick: Array = SHADOWS[shadows]
	sun.shadow_enabled = int(pick[1]) > 0
	if int(pick[1]) > 0:
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if int(pick[1]) >= 4 \
				else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		sun.directional_shadow_max_distance = own * float(pick[2])


## Fits a world's atmosphere to the ambient occlusion setting.
static func fit_atmosphere(atmosphere: WorldEnvironment) -> void:
	if atmosphere == null or atmosphere.environment == null:
		return
	atmosphere.environment.ssao_enabled = ambient_occlusion


## A map whose props `Look` gave a draw distance (`Look._limit_draw_distance`)
## is in this group, so a changed View distance reaches it at once.
const DRAWN_MAP_GROUP := "drawn_map"


## How far the player's view draws in a world that asks for `world_far`
## metres (its "view_far" or its planet's "horizon_far" meta), never under
## `floor`, at the View distance setting.
static func view_far_for(world_far: float, floor: float) -> float:
	return maxf(floor, world_far * float(VIEW_DISTANCE[view_distance][1]))


## How far small things are drawn, as a share of how `Look` would draw them.
static func detail_reach() -> float:
	return float(VIEW_DISTANCE[view_distance][2])


## How far anything too big for `detail_reach` is drawn: 0 for as far as
## the camera sees.
static func big_reach() -> float:
	return float(VIEW_DISTANCE[view_distance][3])


## Whether mission `key` shows in the visor's objective block.
static func is_tracked(key: String) -> bool:
	return key not in untracked


## Tracks mission `key` again, or takes it off the visor (the watch's
## mission log). Returns whether it is tracked now. A mission taken off is
## no longer the main one.
static func toggle_tracked(key: String) -> bool:
	var keys := untracked.duplicate()
	if key in keys:
		keys.erase(key)
	else:
		keys.append(key)
		if main_mission == key:
			set_value("main_mission", "")
	set_value("untracked", keys)
	return is_tracked(key)


## Where mission `key` stands on the visor: "main", "on" or "off".
static func mission_state(key: String) -> String:
	if not is_tracked(key):
		return "off"
	return "main" if key == main_mission else "on"


## A click on a mission in the watch's mission log: on the visor, it becomes
## the main one; the main one is taken off the visor; one off it goes back
## on. Returns the new state.
static func cycle_mission(key: String) -> String:
	match mission_state(key):
		"on":
			set_value("main_mission", key)
		"main":
			toggle_tracked(key)
		_:
			toggle_tracked(key)
	return mission_state(key)


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
