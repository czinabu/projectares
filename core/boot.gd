extends Node
## First autoload. Makes sure Godot knows every script class before the game
## starts.
##
## Godot keeps a list of `class_name` scripts in its project cache and only
## refreshes it when the editor scans the project. After pulling new code, a
## game started before that scan cannot find the new classes, scripts fail to
## load, and the result is a broken raid or a missing HUD. When that happens
## this runs Godot's own import step, which rebuilds the list, and restarts the
## game once. If that cannot fix it, it says so on screen.
##
## This script must not use any project class, or it would break the same way.

const RETRY_ARG := "--ares-classes-refreshed"
const SKIP_DIRS := [".godot", ".git", "addons"]

var missing: Array[String] = []


func _ready() -> void:
	# Exported builds ship a complete class list and no editor to refresh it.
	if not OS.is_debug_build() or OS.has_feature("template"):
		return
	missing = find_missing_classes()
	if missing.is_empty():
		return
	push_warning("Boot: classes missing from the project cache: %s" % ", ".join(missing))
	if RETRY_ARG in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		_show_problem()
		return
	_show_message("Updating the project after new code. The game restarts in a moment.")
	await get_tree().process_frame
	await get_tree().process_frame
	var project_dir := ProjectSettings.globalize_path("res://")
	OS.execute(OS.get_executable_path(), ["--headless", "--path", project_dir, "--import"])
	var args := Array(OS.get_cmdline_args())
	if "--" not in args:
		args.append("--")
	args.append(RETRY_ARG)
	OS.set_restart_on_exit(true, PackedStringArray(args))
	get_tree().quit()


## Names declared with `class_name` in the project that Godot has not registered.
static func find_missing_classes() -> Array[String]:
	var known := {}
	for entry: Dictionary in ProjectSettings.get_global_class_list():
		known[String(entry.get("class", ""))] = true
	var out: Array[String] = []
	for name in declared_classes("res://"):
		if not known.has(name):
			out.append(name)
	return out


## Every `class_name` declared by a script under `dir`.
static func declared_classes(dir: String) -> Array[String]:
	var out: Array[String] = []
	var access := DirAccess.open(dir)
	if access == null:
		return out
	for sub in access.get_directories():
		if sub not in SKIP_DIRS:
			out.append_array(declared_classes(dir.path_join(sub)))
	for file in access.get_files():
		if not file.ends_with(".gd"):
			continue
		for line in FileAccess.get_file_as_string(dir.path_join(file)).split("\n"):
			if line.begins_with("class_name "):
				out.append(line.substr(11).strip_edges().get_slice(" ", 0))
				break
	return out


func _show_problem() -> void:
	_show_message("The project needs a reload before it can run.\n\n"
			+ "Close the game, open the project in the Godot editor,\n"
			+ "choose Project, then Reload Current Project, and play again.\n\n"
			+ "Not loaded: %s" % ", ".join(missing))


func _show_message(text: String) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	var back := ColorRect.new()
	back.color = Color(0.05, 0.05, 0.06, 0.92)
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(back)
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 24)
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(label)
