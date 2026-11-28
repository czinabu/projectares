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
const SafeFile := preload("res://core/account/safe_file.gd")
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
## text are always drawn at full size. "Auto" (scale 0) lets `AutoScale`
## pick the scale from how long the graphics card takes over a frame, so a
## laptop keeps its frame rate in a heavy fight and sharpens up in a quiet
## spot or on a small screen.
const RENDER_SCALE := [
	["Full", 1.0],
	["Quality (77%)", 0.77],
	["Balanced (67%)", 0.67],
	["Performance (50%)", 0.5],
	["Auto (keeps the frame rate)", 0.0],
]
const RENDER_SCALE_AUTO := 4
## The scales "Auto" steps between, sharpest first, and the one it starts on.
const AUTO_SCALES: Array[float] = [1.0, 0.85, 0.77, 0.67, 0.58, 0.5]
const AUTO_SCALE_START := 3
## The graphics card time a frame "Auto" aims under, in ms: a little under
## 60 frames a second, so the rest of the frame has room.
const AUTO_TARGET_MS := 14.0
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
## One pick that sets every PERFORMANCE setting at once (and the edge
## smoothing), best first: [name on the phone, then a value for each of
## `GRAPHICS_KEYS` in order]. "High" is the defaults, the world as made;
## "Low" is for a laptop's built-in graphics; "Lowest" for the weakest
## machines. Changing any one of those settings by hand reads "Custom" (the
## last row, which sets nothing). A weak graphics card is spotted on the
## first launch and given a lower one (`detect_graphics`).
const GRAPHICS := [
	["High", 0, 0, 1, true, true, 2, true, true, 0],
	["Medium", 1, 1, 1, false, true, 2, true, true, 0],
	["Low (laptops)", 2, RENDER_SCALE_AUTO, 2, false, false, 1, true, false, 1],
	["Lowest", 3, 3, 3, false, false, 1, false, false, 2],
	["Custom"],
]
const GRAPHICS_KEYS := ["shadows", "render_scale", "view_distance", "ambient_occlusion", "ground_smoke",
		"anti_aliasing", "edge_ink", "bloom", "war_scenery"]
## How busy a world's far, view-only war is (Ashfront's scenery army, flak,
## low sky, the horde past the rim, the air's embers): [name on the phone,
## share of the action kept]. Everything of it keeps happening on every
## pick, only fewer at once, so a laptop still sees a war.
const WAR_SCENERY := [
	["Full", 1.0],
	["Thinned", 0.6],
	["Light", 0.35],
]
const GRAPHICS_HIGH := 0
const GRAPHICS_MEDIUM := 1
const GRAPHICS_LOW := 2
const GRAPHICS_LOWEST := 3
const GRAPHICS_CUSTOM := 4
## Built-in graphics strong enough for Medium rather than Low, by a piece of
## their name (lower case).
const STRONG_BUILT_IN := ["780m", "880m", "890m", "8060s", "8050s", "arc(tm) 140", "arc 140", "arc(tm) b3", "apple m"]
## Software renderers (no graphics card at all): Lowest.
const SOFTWARE_GPU := ["llvmpipe", "lavapipe", "swiftshader", "softpipe", "microsoft basic render"]

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
	{"key": "graphics", "tab": "view", "section": "PERFORMANCE", "kind": "choice",
			"label": "Graphics quality (sets the rows below)", "default": GRAPHICS_HIGH, "choices": GRAPHICS},
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
	{"key": "bloom", "tab": "view", "section": "PERFORMANCE", "kind": "toggle",
			"label": "Glow around bright lights", "default": true},
	{"key": "war_scenery", "tab": "view", "section": "PERFORMANCE", "kind": "choice",
			"label": "Far battle scenery", "default": 0, "choices": WAR_SCENERY},
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
	{"key": "flight_camera_motion", "tab": "view", "section": "CAMERA", "kind": "slider",
			"label": "Camera motion in flight, first person", "default": 1.0, "range": Vector2(0.0, 1.0),
			"step": 0.05, "format": "percent"},
	{"key": "show_nameplates", "tab": "view", "section": "CAMERA", "kind": "toggle",
			"label": "Names over other players", "default": true},
	{"key": "master_volume", "tab": "system", "kind": "slider", "label": "Volume", "default": 0.8,
			"range": Vector2(0.0, 1.0), "step": 0.05, "format": "percent"},
	{"key": "music_volume", "tab": "system", "kind": "slider", "label": "Music", "default": 0.8,
			"range": Vector2(0.0, 1.0), "step": 0.05, "format": "percent"},
	# Kept but not on a Settings tab ("tab" ""): the watch's mission log.
	{"key": "untracked", "tab": "", "kind": "list", "default": []},
	{"key": "main_mission", "tab": "", "kind": "text", "default": ""},
	# The graphics card `detect_graphics` last looked at ("" before the first).
	{"key": "graphics_card", "tab": "", "kind": "text", "default": ""},
]

## Tests turn this off so they never touch a real settings file.
static var persist := true
## The "Auto" render scale's node while it runs (`AutoScale`).
static var _auto: Node
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
## 0 to 1, applied to the music's own bus (`MUSIC_BUS`), under the volume.
static var music_volume: float:
	get: return _values["music_volume"]
	set(v): _values["music_volume"] = v
static var fullscreen: bool:
	get: return _values["fullscreen"]
	set(v): _values["fullscreen"] = v
## How much the first-person view moves with flight (`PlayerController`'s
## flight motion: rolling with the wings' bank and a skate's carve, a
## boost's rumble), 0 for none.
static var flight_camera_motion: float:
	get: return _values.get("flight_camera_motion", 1.0)
	set(v): _values["flight_camera_motion"] = v
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
## The soft glow around bright and glowing things (the atmosphere's glow,
## `Look.atmosphere`): a few blurred copies of the frame, so a weak
## graphics card can do without.
static var bloom: bool:
	get: return _values["bloom"]
	set(v): _values["bloom"] = v
## An index into `WAR_SCENERY`.
static var war_scenery: int:
	get: return _values["war_scenery"]
	set(v): _values["war_scenery"] = v


## The share of the far, view-only war kept on this machine (`WAR_SCENERY`):
## 1 on Full. Read by the scenery each time it decides how much to show, so
## a change on the phone takes at once.
static func war_share() -> float:
	if not _values.has("war_scenery"):
		return 1.0
	return float(WAR_SCENERY[clampi(war_scenery, 0, WAR_SCENERY.size() - 1)][1])
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
## An index into `GRAPHICS`: the pick that set the PERFORMANCE rows, or
## `GRAPHICS_CUSTOM` once one of them was changed by hand.
static var graphics: int:
	get: return _values["graphics"]
	set(v): _values["graphics"] = v
## The name of the graphics card `detect_graphics` looked at, so it looks
## only once.
static var graphics_card: String:
	get: return _values["graphics_card"]
	set(v): _values["graphics_card"] = v
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
	detect_graphics()
	apply()
	# Once more after the first frame: a window still being shown at start
	# can drop the mode set before it, leaving it the other way round from
	# the setting.
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		tree.process_frame.connect(apply_window, CONNECT_ONE_SHOT)
		tree.process_frame.connect(fit_window_to_screen, CONNECT_ONE_SHOT)


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
	if key == "graphics":
		_use_graphics(graphics)
	elif key in GRAPHICS_KEYS:
		_values["graphics"] = graphics_matching()
	apply()
	save()


## Sets every one of `GRAPHICS_KEYS` from the `GRAPHICS` row `pick` (not
## "Custom", which sets nothing).
static func _use_graphics(pick: int) -> void:
	var row: Array = GRAPHICS[pick]
	if row.size() < GRAPHICS_KEYS.size() + 1:
		return
	for i: int in GRAPHICS_KEYS.size():
		_values[GRAPHICS_KEYS[i]] = row[i + 1]
	_values["graphics"] = pick


## The `GRAPHICS` row the settings are on now, or `GRAPHICS_CUSTOM`.
static func graphics_matching() -> int:
	for pick: int in GRAPHICS.size():
		var row: Array = GRAPHICS[pick]
		if row.size() < GRAPHICS_KEYS.size() + 1:
			continue
		var same := true
		for i: int in GRAPHICS_KEYS.size():
			if _values[GRAPHICS_KEYS[i]] != row[i + 1]:
				same = false
				break
		if same:
			return pick
	return GRAPHICS_CUSTOM


## The `GRAPHICS` pick for a graphics card, from what Godot says of it
## (`RenderingServer.get_video_adapter_type` and `_name`) and whether the
## game is drawing with the full Vulkan renderer (`full_renderer`; false on
## the OpenGL fallback a card with no Vulkan gets). A laptop's built-in
## graphics gets Low (the strongest of them Medium), a software renderer
## Lowest, and a separate card High.
static func graphics_for(device_type: int, card: String, full_renderer := true) -> int:
	var lower := card.to_lower()
	for each: String in SOFTWARE_GPU:
		if lower.contains(each):
			return GRAPHICS_LOWEST
	if device_type == RenderingDevice.DEVICE_TYPE_CPU:
		return GRAPHICS_LOWEST
	if not full_renderer:
		return GRAPHICS_LOW
	match device_type:
		RenderingDevice.DEVICE_TYPE_DISCRETE_GPU:
			return GRAPHICS_HIGH
		RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU:
			for each: String in STRONG_BUILT_IN:
				if lower.contains(each):
					return GRAPHICS_MEDIUM
			return GRAPHICS_LOW
	return GRAPHICS_MEDIUM


## On the first launch on a graphics card (`graphics_card` is the last one
## looked at), picks the `GRAPHICS` row for it (`graphics_for`), so a laptop
## starts on settings it can run. It only lowers the defaults: settings the
## player chose by hand are kept. Nothing with no window.
static func detect_graphics() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var card := RenderingServer.get_video_adapter_name()
	if card == "" or card == graphics_card:
		return
	var full := RenderingServer.get_current_rendering_method() != "gl_compatibility"
	var pick := graphics_for(RenderingServer.get_video_adapter_type(), card, full)
	_values["graphics_card"] = card
	if graphics_matching() == GRAPHICS_HIGH and pick != GRAPHICS_HIGH:
		_use_graphics(pick)
		print("GameSettings: %s, starting on %s graphics" % [card, GRAPHICS[pick][0]])
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
	var music := music_bus()
	AudioServer.set_bus_volume_db(music, linear_to_db(maxf(music_volume, 0.0001)))
	AudioServer.set_bus_mute(music, music_volume <= 0.001)
	if DisplayServer.get_name() == "headless":
		return
	apply_graphics()
	apply_window()


## The bus the music plays on (`Sfx.music`), so it has its own volume.
const MUSIC_BUS := "Music"


## The music's bus (`MUSIC_BUS`), made under the master bus the first
## time it is asked for, so the music has a volume of its own.
static func music_bus() -> int:
	var bus := AudioServer.get_bus_index(MUSIC_BUS)
	if bus < 0:
		AudioServer.add_bus()
		bus = AudioServer.bus_count - 1
		AudioServer.set_bus_name(bus, MUSIC_BUS)
		AudioServer.set_bus_send(bus, &"Master")
	return bus


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


## A window bigger than the screen it opens on (the game asks for 1600x900,
## more than many laptop screens) is shrunk to fit and put in the middle.
static func fit_window_to_screen() -> void:
	if DisplayServer.get_name() == "headless" or window_is_full():
		return
	var screen := DisplayServer.window_get_current_screen()
	var room := DisplayServer.screen_get_usable_rect(screen)
	if room.size.x <= 0 or room.size.y <= 0:
		return
	var size := DisplayServer.window_get_size()
	var fitted := window_fit(size, room.size)
	if fitted == size:
		return
	DisplayServer.window_set_size(fitted)
	DisplayServer.window_set_position(room.position + (room.size - fitted) / 2)


## A window of `size` shrunk, keeping its shape, to fit in `room` with a
## margin for the window's frame; the same size when it already fits.
static func window_fit(size: Vector2i, room: Vector2i) -> Vector2i:
	if size.x <= room.x and size.y <= room.y:
		return size
	var share := minf(room.x * 0.92 / size.x, room.y * 0.88 / size.y)
	return Vector2i(floori(size.x * share), floori(size.y * share))


## Sets the main view's edge smoothing and render scale (only the main
## view: the scope's and the mirror's small pictures keep their own), shows
## or hides the edge ink on far shapes, and fits every world's sun and
## atmosphere to the shadow and ambient occlusion settings.
static func apply_graphics() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	var mode: Array = ANTI_ALIASING[anti_aliasing]
	# The OpenGL fallback (a card with no Vulkan) has neither the screen-space
	# smoothing nor FSR: it keeps MSAA and scales plainly.
	var full := RenderingServer.get_current_rendering_method() != "gl_compatibility"
	tree.root.msaa_3d = mode[1]
	tree.root.screen_space_aa = mode[2] if full else Viewport.SCREEN_SPACE_AA_DISABLED
	if render_scale == RENDER_SCALE_AUTO:
		if not is_instance_valid(_auto):
			_auto = AutoScale.new()
			tree.root.add_child.call_deferred(_auto)
			AutoScale.set_scale(tree.root, AUTO_SCALES[AUTO_SCALE_START])
	else:
		if is_instance_valid(_auto):
			_auto.queue_free()
		_auto = null
		AutoScale.set_scale(tree.root, RENDER_SCALE[render_scale][1])
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


## "Auto" render scale (`RENDER_SCALE_AUTO`): a node on the window's root
## while it is picked. It times the graphics card's work on the main view
## and every `WINDOW` seconds moves the scale a step (`next_step`). Each
## change rebuilds the view's buffers, a small hitch, so after one it waits
## `SETTLE` seconds and ignores that stretch. View only: nothing here
## touches the game, and first and third person are drawn alike.
class AutoScale extends Node:
	const NODE_NAME := "AutoRenderScale"
	const WINDOW := 1.5
	const SETTLE := 2.0
	var step := AUTO_SCALE_START
	var _time := 0.0
	var _gpu := 0.0
	var _frames := 0
	var _wait := SETTLE

	## Draws the main view's 3D at `scale` of the window, sharpened up with FSR
	## (plainly scaled on the OpenGL fallback, which has no FSR).
	static func set_scale(view: Viewport, scale: float) -> void:
		var full := RenderingServer.get_current_rendering_method() != "gl_compatibility"
		view.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if scale < 1.0 and full else Viewport.SCALING_3D_MODE_BILINEAR
		view.scaling_3d_scale = scale

	## The `AUTO_SCALES` step "Auto" moves to from step `at`, after a stretch
	## whose frames took the graphics card `gpu_ms` on average: a step smaller
	## when over `AUTO_TARGET_MS` (two when far over), a step sharper when the
	## sharper step's pixels would still fit well under it (the cost taken as
	## growing with the pixels drawn, which overstates it), else the same.
	static func next_step(at: int, gpu_ms: float) -> int:
		var last := AUTO_SCALES.size() - 1
		if gpu_ms <= 0.0:
			return at
		if gpu_ms > AUTO_TARGET_MS * 1.4:
			return mini(at + 2, last)
		if gpu_ms > AUTO_TARGET_MS:
			return mini(at + 1, last)
		if at > 0:
			var grow := pow(AUTO_SCALES[at - 1] / AUTO_SCALES[at], 2.0)
			if gpu_ms * grow < AUTO_TARGET_MS * 0.85:
				return at - 1
		return at

	func _init() -> void:
		name = NODE_NAME
		process_mode = Node.PROCESS_MODE_ALWAYS

	func _ready() -> void:
		if DisplayServer.get_name() == "headless":
			set_process(false)
			return
		RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)

	func _process(delta: float) -> void:
		if _wait > 0.0:
			_wait -= delta
			return
		var gpu := RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())
		# No timing from the card (the OpenGL fallback gives none): the scale
		# it started on stays.
		if gpu <= 0.0:
			return
		_gpu += gpu
		_frames += 1
		_time += delta
		if _time < WINDOW:
			return
		var next := next_step(step, _gpu / maxi(_frames, 1))
		_time = 0.0
		_gpu = 0.0
		_frames = 0
		if next == step:
			return
		step = next
		set_scale(get_viewport(), AUTO_SCALES[step])
		_wait = SETTLE


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
	atmosphere.environment.glow_enabled = bloom


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
	# Whole or not at all, so a crash mid-save keeps the old settings.
	if not SafeFile.write(SAVE_PATH, JSON.stringify(to_dict(), "\t")):
		push_warning("GameSettings: could not write %s" % SAVE_PATH)


static func load_settings() -> void:
	if not persist or not SafeFile.exists(SAVE_PATH):
		return
	var data: Variant = SafeFile.read_json(SAVE_PATH)
	if typeof(data) != TYPE_DICTIONARY:
		push_warning("GameSettings: %s is unreadable, using defaults" % SAVE_PATH)
		return
	use_saved(data)


## Takes the settings in `data` (as saved), without saving them again.
static func use_saved(data: Dictionary) -> void:
	var was_persisting := persist
	persist = false
	for key: String in to_dict():
		if data.has(key):
			set_value(key, data[key])
	# A saved Graphics quality pick (not Custom) takes the pick's rows as
	# they are now, so a player on Low gets what Low became since.
	var pick := int(data.get("graphics", GRAPHICS_CUSTOM))
	if pick >= 0 and pick < GRAPHICS_CUSTOM:
		_use_graphics(pick)
	persist = was_persisting
