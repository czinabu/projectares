extends Node
## DEV MODE: dev tools for testing on Caleb's own machine, where a thread
## cannot measure anything (his graphics card, his frame rate). Two keys,
## read only in an editor or debug run (`DevMode.available`), never in an
## exported game, and never on a server or headless:
##   - F9, performance capture: `CAPTURE_SECONDS` of frame timings (frame,
##     process, physics, render CPU and GPU), draw calls, objects and
##     primitives, then one JSON file with a summary at the top, the
##     machine, the graphics settings, where it was taken and every frame.
##     F9 again stops it early.
##   - F10, bug snapshot: a screenshot, where the player is and what they
##     are doing (`Main.report_context`), the graphics settings and the
##     game's recent logs, in one zip.
## Both land under `SAVE_DIR` (shown with its full path in a notice) so the
## file can be sent back as it is. The keys are raw keys, not input
## actions: they are not controls of the game, so the phone's Controls app
## and the key checks leave them out. Main adds this node (a "DEV MODE"
## line), so deleting `core/dev/` removes it with dev mode.

const DevMode := preload("res://core/dev/dev_mode.gd")
const BugReportScript := preload("res://core/report/bug_report.gd")
const GameSettings := preload("res://core/settings/game_settings.gd")

const CAPTURE_KEY := KEY_F9
const SNAPSHOT_KEY := KEY_F10
const SAVE_DIR := "user://dev"
const CAPTURE_SECONDS := 30.0
## A frame this long or longer is a hitch (the frame bench's bar).
const HITCH_MS := 50.0
## The end of each log a snapshot keeps.
const LOG_TAIL := 400_000

## A line to show the player (Main puts it on the HUD).
signal notice(text: String)
## A capture or snapshot was written, with its path.
signal saved(kind: String, path: String)

## Where the player is and what they are doing (Main's `report_context`).
var context_source: Callable
## Where files go (tests point it elsewhere).
var save_dir := SAVE_DIR
## Tests run the tools without the key gate.
var force_enabled := false

var _capturing := false
var _capture_left := 0.0
var _frames: Array[Dictionary] = []
var _capture_context := {}
var _snapping := false


func enabled() -> bool:
	if force_enabled:
		return true
	return DevMode.available() and DisplayServer.get_name() != "headless"


func capturing() -> bool:
	return _capturing


func _input(event: InputEvent) -> void:
	if not enabled():
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.physical_keycode == CAPTURE_KEY:
		get_viewport().set_input_as_handled()
		if _capturing:
			stop_capture()
		else:
			start_capture()
	elif key.physical_keycode == SNAPSHOT_KEY:
		get_viewport().set_input_as_handled()
		snapshot()


# --- Performance capture -------------------------------------------------

func start_capture(seconds: float = CAPTURE_SECONDS) -> void:
	if _capturing:
		return
	_capturing = true
	_capture_left = seconds
	_frames.clear()
	_capture_context = _context()
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	notice.emit("Performance capture: %d s. Play as usual (F9 stops it)." % int(seconds))


func stop_capture() -> String:
	if not _capturing:
		return ""
	_capturing = false
	var report := capture_report(_frames, _capture_context)
	var path := _write_json("perf", report)
	_frames.clear()
	if path == "":
		notice.emit("Performance capture could not be written to %s." % ProjectSettings.globalize_path(save_dir))
		return ""
	var summary: Dictionary = report.summary
	notice.emit("Captured: %.0f fps, %.1f ms median, %d hitches. Saved %s" % [summary.fps, summary.frame_ms.median,
			summary.hitches, ProjectSettings.globalize_path(path)])
	saved.emit("perf", path)
	return path


func _process(delta: float) -> void:
	if not _capturing:
		return
	_frames.append(sample(delta, get_viewport().get_viewport_rid()))
	_capture_left -= delta
	if _capture_left <= 0.0:
		stop_capture()


## One frame's numbers.
static func sample(delta: float, viewport: RID) -> Dictionary:
	return {
		"frame_ms": delta * 1000.0,
		"process_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		"physics_ms": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		"render_cpu_ms": RenderingServer.viewport_get_measured_render_time_cpu(viewport)
				+ RenderingServer.get_frame_setup_time_cpu(),
		"render_gpu_ms": RenderingServer.viewport_get_measured_render_time_gpu(viewport),
		"draws": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"objects": int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		"primitives": int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
	}


## The whole capture as plain data: a summary first (what to read), then
## the machine, the settings, where it was taken and every frame.
static func capture_report(frames: Array[Dictionary], where: Dictionary) -> Dictionary:
	return {
		"summary": summarize(frames),
		"machine": machine(),
		"settings": GameSettings.to_dict(),
		"context": where,
		"frames": frames,
	}


## Median, 95th and 99th percentile and worst of each timing, the average
## of the counts, frames a second and hitches.
static func summarize(frames: Array[Dictionary]) -> Dictionary:
	var out := {"frames": frames.size()}
	var total := 0.0
	for frame: Dictionary in frames:
		total += float(frame.get("frame_ms", 0.0))
	out["seconds"] = total / 1000.0
	out["fps"] = frames.size() / (total / 1000.0) if total > 0.0 else 0.0
	out["hitches"] = frames.filter(func(f: Dictionary) -> bool: return float(f.get("frame_ms", 0.0)) >= HITCH_MS).size()
	out["hitch_ms"] = HITCH_MS
	for key: String in ["frame_ms", "process_ms", "physics_ms", "render_cpu_ms", "render_gpu_ms"]:
		var values: Array[float] = []
		for frame: Dictionary in frames:
			values.append(float(frame.get(key, 0.0)))
		out[key] = spread(values)
	for key: String in ["draws", "objects", "primitives"]:
		var sum := 0.0
		var most := 0
		for frame: Dictionary in frames:
			sum += float(frame.get(key, 0))
			most = maxi(most, int(frame.get(key, 0)))
		out[key] = {"average": sum / frames.size() if not frames.is_empty() else 0.0, "most": most}
	return out


static func spread(values: Array[float]) -> Dictionary:
	if values.is_empty():
		return {"median": 0.0, "p95": 0.0, "p99": 0.0, "worst": 0.0}
	var sorted := values.duplicate()
	sorted.sort()
	var at := func(share: float) -> float: return sorted[mini(int(sorted.size() * share), sorted.size() - 1)]
	return {"median": at.call(0.5), "p95": at.call(0.95), "p99": at.call(0.99), "worst": sorted[sorted.size() - 1]}


static func machine() -> Dictionary:
	var window := DisplayServer.window_get_size() if DisplayServer.get_name() != "headless" else Vector2i.ZERO
	return {
		"gpu": RenderingServer.get_video_adapter_name(),
		"gpu_vendor": RenderingServer.get_video_adapter_vendor(),
		"driver": RenderingServer.get_video_adapter_api_version(),
		"renderer": str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "")),
		"cpu": OS.get_processor_name(),
		"cores": OS.get_processor_count(),
		"os": "%s %s" % [OS.get_name(), OS.get_version()],
		"engine": Engine.get_version_info().get("string", ""),
		"build": int(ProjectSettings.get_setting(BugReportScript.BUILD_SETTING, 0)),
		"window": "%dx%d" % [window.x, window.y],
		"vsync": DisplayServer.window_get_vsync_mode() if DisplayServer.get_name() != "headless" else -1,
		"max_fps": Engine.max_fps,
		"debug_build": OS.is_debug_build(),
	}


# --- Bug snapshot --------------------------------------------------------

## Saves a screenshot, the context, the settings and the recent logs in one
## zip. Returns its path ("" if it failed or one is already being taken).
func snapshot() -> String:
	if _snapping:
		return ""
	_snapping = true
	var image: Image = null
	if DisplayServer.get_name() != "headless":
		# The frame as drawn, HUD and all.
		await RenderingServer.frame_post_draw
		image = get_viewport().get_texture().get_image()
	var path := write_snapshot(image, _context(), save_dir)
	_snapping = false
	if path == "":
		notice.emit("Snapshot could not be written to %s." % ProjectSettings.globalize_path(save_dir))
		return ""
	notice.emit("Snapshot saved: %s" % ProjectSettings.globalize_path(path))
	saved.emit("snapshot", path)
	return path


static func write_snapshot(image: Image, where: Dictionary, dir: String) -> String:
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join("snapshot-%s.zip" % _stamp())
	var zip := ZIPPacker.new()
	if zip.open(path) != OK:
		return ""
	var info := {"time": Time.get_datetime_string_from_system(true) + " UTC", "context": where,
			"machine": machine(), "settings": GameSettings.to_dict()}
	_zip_file(zip, "snapshot.json", JSON.stringify(info, "\t").to_utf8_buffer())
	if image != null and not image.is_empty():
		_zip_file(zip, "screenshot.png", image.save_png_to_buffer())
	var logs: Dictionary = BugReportScript.log_files()
	for name: String in logs.keys():
		var bytes: PackedByteArray = logs[name]
		if bytes.size() > LOG_TAIL:
			bytes = bytes.slice(bytes.size() - LOG_TAIL)
		_zip_file(zip, name, bytes)
	zip.close()
	return path


static func _zip_file(zip: ZIPPacker, name: String, bytes: PackedByteArray) -> void:
	zip.start_file(name)
	zip.write_file(bytes)
	zip.close_file()


# --- Shared --------------------------------------------------------------

func _context() -> Dictionary:
	if context_source.is_valid():
		var out: Variant = context_source.call()
		if typeof(out) == TYPE_DICTIONARY:
			return out
	return {}


func _write_json(kind: String, data: Dictionary) -> String:
	DirAccess.make_dir_recursive_absolute(save_dir)
	var path := save_dir.path_join("%s-%s.json" % [kind, _stamp()])
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return ""
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	return path


static func _stamp() -> String:
	return Time.get_datetime_string_from_system(true).replace(":", "-") + "-%03d" % (Time.get_ticks_msec() % 1000)
