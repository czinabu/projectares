extends RefCounted
## The game updates itself (`core/update/updater.gd`, the `Updater`
## autoload): when it runs, what a release's manifest means, how a restart
## onto a downloaded pack is put together, and how the pack is put in place
## beside the exe. `-- --only updater` runs just these.

const UpdaterScript := preload("res://core/update/updater.gd")
const DIR := "user://test_updater"


static func run(t: Node) -> void:
	print("Updater: a release's manifest, the restart and the install")
	_when_it_runs(t)
	_manifests(t)
	_restarts(t)
	_install(t)
	_wiring(t)


static func _when_it_runs(t: Node) -> void:
	var none := PackedStringArray()
	t.check(UpdaterScript.enabled(true, 12, none, "Windows", false),
			"an exported, stamped game keeps itself up to date")
	t.check(not UpdaterScript.enabled(false, 12, none, "Windows", false),
			"the editor and test runs never update")
	t.check(not UpdaterScript.enabled(true, 0, none, "Windows", false),
			"a build the release workflow did not stamp never updates")
	t.check(not UpdaterScript.enabled(true, 12, none, "headless", false)
			and not UpdaterScript.enabled(true, 12, none, "Windows", true)
			and not UpdaterScript.enabled(true, 12, PackedStringArray(["--server"]), "Windows", false)
			and not UpdaterScript.enabled(true, 12, PackedStringArray(["--no-update"]), "Windows", false),
			"servers, headless runs and --no-update never update")
	t.check(Updater.state == "off", "this test run's updater is off")
	t.check(UpdaterScript.engine_version().begins_with("%d.%d" % [Engine.get_version_info().major,
			Engine.get_version_info().minor]), "the engine is named as the release workflow names it")


static func _manifests(t: Node) -> void:
	var sha := "a".repeat(64)
	var good := {"build": 20, "commit": "abc1234", "godot": "4.7", "platform": "windows",
			"pack": "ProjectAres.pck", "size": 1000, "sha256": sha}
	t.check(UpdaterScript.decide(good, 19, "4.7", "Windows") == "download", "a newer build is downloaded")
	t.check(UpdaterScript.decide(good, 20, "4.7", "Windows") == "current"
			and UpdaterScript.decide(good, 25, "4.7", "Windows") == "current",
			"the same or an older build leaves the game alone")
	t.check(UpdaterScript.decide(good, 19, "4.8", "Windows") == "reinstall",
			"a build for another engine asks for a fresh install instead")
	t.check(UpdaterScript.decide(good, 19, "4.7", "Linux") == "other", "a build for another system is ignored")
	var bad_sha := good.duplicate()
	bad_sha.sha256 = "123"
	var escape := good.duplicate()
	escape.pack = "../../evil.pck"
	var no_size := good.duplicate()
	no_size.erase("size")
	t.check(UpdaterScript.decide({}, 19, "4.7", "Windows") == "bad"
			and UpdaterScript.decide(bad_sha, 19, "4.7", "Windows") == "bad"
			and UpdaterScript.decide(escape, 19, "4.7", "Windows") == "bad"
			and UpdaterScript.decide(no_size, 19, "4.7", "Windows") == "bad",
			"a manifest without a checksum, a size or a plain file name is refused")
	t.check(UpdaterScript.pack_path(20) == "user://updates/build-20.pck", "a download waits under user://updates")


static func _restarts(t: Node) -> void:
	var plain := UpdaterScript.restart_args(PackedStringArray())
	t.check(plain == PackedStringArray(["--", UpdaterScript.UPDATED_ARG]),
			"the restart after an install says it is one")
	var again := UpdaterScript.restart_args(PackedStringArray(["--fullscreen", "--", "--", "--dev",
			UpdaterScript.UPDATED_ARG]))
	t.check(again == PackedStringArray(["--fullscreen", "--", "--dev", UpdaterScript.UPDATED_ARG]),
			"the game's own arguments are kept, and the mark only once")
	var script := UpdaterScript.install_script("C:\\Users\\A 100%\\build-20.pck", "D:\\Games\\Ares\\ProjectAres.pck",
			"D:\\Games\\Ares\\ProjectAres.exe", PackedStringArray(["--", UpdaterScript.UPDATED_ARG]))
	t.check("move /y \"C:\\Users\\A 100%%\\build-20.pck\" \"D:\\Games\\Ares\\ProjectAres.pck\"" in script
			and "start \"\" \"D:\\Games\\Ares\\ProjectAres.exe\" \"--\" \"%s\"" % UpdaterScript.UPDATED_ARG in script
			and "goto wait" in script and "geq 60" in script,
			"on Windows a script waits for the game to close, moves the pack in, quoted, and starts it again")


static func _install(t: Node) -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var pack := ProjectSettings.globalize_path(DIR.path_join("new.pck"))
	var target := ProjectSettings.globalize_path(DIR.path_join("ProjectAres.pck"))
	_write(pack, "new build")
	DirAccess.remove_absolute(target)
	t.check(UpdaterScript.install_over(pack, target) == ERR_FILE_NOT_FOUND and not FileAccess.file_exists(target),
			"an install with its pack inside the exe gets no pack beside it")
	_write(target, "old")
	t.check(UpdaterScript.install_over(pack, target) == OK
			and FileAccess.get_file_as_string(target) == "new build"
			and not FileAccess.file_exists(target + ".new"),
			"the downloaded pack is copied over the one beside the exe, whole")
	for file in [pack, target]:
		DirAccess.remove_absolute(file)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR))


static func _wiring(t: Node) -> void:
	var project := FileAccess.get_file_as_string("res://project.godot")
	t.check(project.find("Boot=") < project.find("Updater=")
			and project.find("Updater=") < project.find("InputSetup="),
			"the updater is the second autoload, straight after Boot")
	var presets := ConfigFile.new()
	presets.load("res://export_presets.cfg")
	var client := ""
	for section in presets.get_sections():
		if presets.get_value(section, "name", "") == "Windows Client":
			client = section
	t.check(client != "" and presets.get_value(client + ".options", "binary_format/embed_pck", true) == false,
			"the Windows client keeps its pack beside the exe, so an update can replace it")
	var workflow := FileAccess.get_file_as_string("res://.github/workflows/windows-client.yml")
	t.check(workflow == "" or (UpdaterScript.BUILD_SETTING.get_slice("/", 2) in workflow
			and UpdaterScript.MANIFEST in workflow and "ProjectAres.pck" in workflow),
			"the release workflow stamps the build and publishes the pack and its manifest")
	t.check(str(ProjectSettings.get_setting("application/config/icon", "")).begins_with("res://assets/branding/")
			and str(ProjectSettings.get_setting("application/boot_splash/image", "")).begins_with("res://assets/branding/")
			and str(presets.get_value(client + ".options", "application/icon", "")).ends_with(".ico")
			and FileAccess.file_exists("res://assets/branding/icon.ico"),
			"the game wears its own logo: window, boot splash and the exe's icon")
	var installer := FileAccess.get_file_as_string("res://.github/installer/ProjectAres.nsi")
	t.check(installer == "" or ("RequestExecutionLevel user" in installer
			and "$LOCALAPPDATA\\Programs" in installer and "$DESKTOP" in installer),
			"the installer installs per user, where the game can update itself, with a desktop shortcut")
	var main_script: Script = load("res://core/main.gd")
	var installed: PackedStringArray = main_script.server_process_args(PackedStringArray(["--server"]), true)
	var checkout: PackedStringArray = main_script.server_process_args(PackedStringArray(["--server"]), false)
	t.check(installed == PackedStringArray(["--headless", "--", "--server"])
			and "--path" in checkout and checkout[checkout.size() - 1] == "--server",
			"an installed game starts its own server without --path, which release builds refuse")
	var screen := StartScreen.new()
	t.add_child(screen)
	screen.set_status("Downloading build 20: 40%")
	t.check(screen.status_label.text == "DOWNLOADING BUILD 20: 40%", "the start screen shows what the updater is doing")
	screen.queue_free()


static func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()
