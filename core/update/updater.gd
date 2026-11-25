extends Node
## Keeps an installed game up to date by itself (the `Updater` autoload).
##
## The game is installed once: `ProjectAres.exe` (the engine) and
## `ProjectAres.pck` (everything else) side by side, or on Linux
## `ProjectAres.x86_64` and its pack. Every merge to main publishes a new pack
## and a small manifest for each system on the rolling "latest" GitHub
## release (`.github/workflows/windows-client.yml`): `update.json` and
## `ProjectAres.pck` for Windows, `update-linux.json` and
## `ProjectAres-linux.pck` for Linux (`manifest_name`). On launch this asks
## for its system's manifest; a newer build is downloaded in the background,
## checked against the manifest's size and SHA-256, and kept under
## `user://updates`. If it is ready while the start screen is still up the game
## restarts into it at once (`start.gd` tells us with `on_start_screen`);
## otherwise it goes in on the next launch, or from the phone's Servers app.
##
## Going in (`_install`): the new pack replaces the one beside the exe and
## the game starts again. Exported games cannot be pointed at another pack
## (release templates refuse `--main-pack`), and Windows will not replace a
## pack the game holds open, so there a small batch script does the swap once
## the game has closed and starts it again (`install_script`). A folder that
## will not take the pack is tried on `MAX_TRIES` launches, never in a loop,
## and then the game says so (state "stuck").
##
## Only the pack is ever replaced, never the engine beside it, so the exe
## keeps its name (renamed or not, `pack_candidates`) and, on Linux, its
## executable bit. Only the engine cannot change this way. A manifest naming another Godot
## version than the running exe (`engine_version`) asks for a fresh install
## (state "reinstall"), offered on the start screen and the Servers app.
##
## It runs only in an exported game that was stamped with a build number by
## the release workflow (`BUILD_SETTING`), never in the editor, a test run, a
## dedicated server or headless. Nothing in it touches the simulation, and it
## uses no project class, so it keeps working whatever the pack holds.

signal changed

## Where the release workflow publishes; `--update-from <url>` overrides it
## (a test of the whole loop against a local server).
const RELEASE_BASE := "https://github.com/czinabu/projectares/releases/download/latest/"
const MANIFEST := "update.json"
## Linux reads its own manifest: its pack is exported for Linux, and a
## Windows game reading `MANIFEST` must never be handed it.
const LINUX_MANIFEST := "update-linux.json"
const DIR := "user://updates"
const PENDING := "user://updates/pending.json"
const PART := "user://updates/download.part"
## The release workflow writes these into project.godot before exporting.
const BUILD_SETTING := "ares/build/number"
const COMMIT_SETTING := "ares/build/commit"
## Added to the restart after an install, so a failed one never loops.
const UPDATED_ARG := "--ares-updated"
const OFF_ARG := "--no-update"
## Launches that may try to install one download before it is given up on.
const MAX_TRIES := 2
const FROM_ARG := "--update-from"

## Seconds between checks while playing, and how long a check may take.
var recheck_every := 1800.0
var check_timeout := 10.0
## A download that stalls this long gives up (and is tried again later).
var download_timeout := 600.0

## "off" (never updates: editor, server, unstamped), "idle", "checking",
## "current", "downloading", "verifying", "ready" (downloaded, goes in at the
## next start), "restarting", "reinstall" (the engine changed, or the pack is
## inside the exe), "stuck" (the game's folder would not take the new pack)
## or "failed" (no answer; asked again later).
var state := "off"
## The running build, and its commit.
var build := 0
var commit := ""
## The newest manifest heard (empty before a check answers).
var latest := {}
## 0..1 through a download.
var progress := 0.0
## True when this run is the first since the game moved to a new build.
var just_updated := false
## Set by `start.gd` while the title is up: an update ready then goes in at
## once instead of waiting for the next launch.
var on_start_screen := false

var _base := RELEASE_BASE
var _http: HTTPRequest
var _recheck_left := 0.0
var _hash_task := -1
var _hash := ""


func _ready() -> void:
	build = int(ProjectSettings.get_setting(BUILD_SETTING, 0))
	commit = str(ProjectSettings.get_setting(COMMIT_SETTING, ""))
	var args := OS.get_cmdline_user_args()
	var from := args.find(FROM_ARG)
	if from >= 0 and from + 1 < args.size():
		_base = args[from + 1].trim_suffix("/") + "/"
	# Only the playtest build updates itself: the latest release is that
	# build, and the dev build (every world) must never be swapped for it.
	if not enabled(OS.has_feature("template"), build, args, DisplayServer.get_name(),
			OS.has_feature("dedicated_server")) or not OS.has_feature("playtest"):
		set_process(false)
		return
	just_updated = UPDATED_ARG in args
	if _install_pending():
		return
	state = "idle"
	check()


## Whether a game started like this keeps itself up to date.
static func enabled(exported: bool, build_number: int, user_args: PackedStringArray,
		display: String, dedicated: bool) -> bool:
	if not exported or build_number <= 0 or dedicated or display == "headless":
		return false
	for arg in ["--server", "--account-service", OFF_ARG]:
		if arg in user_args:
			return false
	return true


## The manifest a game on `platform` (OS.get_name()) reads.
static func manifest_name(platform: String) -> String:
	return LINUX_MANIFEST if platform.to_lower() == "linux" else MANIFEST


## The running engine as the release workflow names it: "4.7", "4.7.1".
static func engine_version() -> String:
	var v := Engine.get_version_info()
	var out := "%d.%d" % [int(v.major), int(v.minor)]
	if int(v.patch) > 0:
		out += ".%d" % int(v.patch)
	return out


## What a manifest means for a game of `own_build` on `engine` and
## `platform` (OS.get_name()): "bad" (unreadable), "other" (built for another
## system), "current", "reinstall" (needs a new engine) or "download".
static func decide(manifest: Dictionary, own_build: int, engine: String, platform: String) -> String:
	var number := int(manifest.get("build", 0))
	var sha := str(manifest.get("sha256", ""))
	if number <= 0 or sha.length() != 64 or int(manifest.get("size", 0)) <= 0 \
			or not _safe_name(str(manifest.get("pack", ""))):
		return "bad"
	if str(manifest.get("platform", "")).to_lower() != platform.to_lower():
		return "other"
	if number <= own_build:
		return "current"
	if str(manifest.get("godot", "")) != engine:
		return "reinstall"
	return "download"


## A file name from a manifest: nothing that could leave the release's folder.
static func _safe_name(file: String) -> bool:
	return file != "" and file.is_valid_filename() and not ".." in file


## Where a downloaded build waits.
static func pack_path(number: int) -> String:
	return DIR.path_join("build-%d.pck" % number)


## One line on where the game stands, for the start screen and the phone.
func status_line() -> String:
	var newest := int(latest.get("build", 0))
	match state:
		"checking":
			return "Checking for updates"
		"current":
			return "Build %d, up to date" % build if not just_updated else "Updated to build %d" % build
		"downloading":
			return "Downloading build %d: %d%%" % [newest, roundi(progress * 100.0)]
		"verifying":
			return "Checking the download"
		"ready":
			return "Build %d is ready. It goes in when you next start the game." % newest
		"restarting":
			return "Installing build %d" % newest
		"reinstall":
			return "Build %d needs a fresh install of the game." % newest
		"stuck":
			return "Build %d could not be put in the game's folder. Install it fresh." % newest
		"failed":
			return "Build %d. Could not check for updates." % build
		"idle":
			return "Build %d" % build
	return ""


## Asks for the newest manifest now (it is asked at launch and every
## `recheck_every` seconds anyway).
func check() -> void:
	if state in ["off", "checking", "downloading", "verifying", "restarting"]:
		return
	_set_state("checking")
	_http = _new_request(check_timeout)
	_http.request_completed.connect(_on_manifest, CONNECT_ONE_SHOT)
	if _http.request(_base + manifest_name(OS.get_name())) != OK:
		_fail()


## Restarts into the downloaded build now (the Servers app's button). The
## caller saves anything it needs to first.
func restart_now() -> void:
	if state != "ready":
		return
	_install(int(latest.get("build", 0)))


## The release page, for a fresh install.
func open_downloads() -> void:
	OS.shell_open(RELEASE_BASE.trim_suffix("download/latest/") + "tag/latest")


func _process(delta: float) -> void:
	if state == "downloading" and _http != null:
		var size := maxi(int(latest.get("size", 1)), 1)
		var now := clampf(float(_http.get_downloaded_bytes()) / size, 0.0, 1.0)
		if absf(now - progress) >= 0.01:
			progress = now
			changed.emit()
	if state == "verifying" and _hash_task >= 0 and WorkerThreadPool.is_task_completed(_hash_task):
		WorkerThreadPool.wait_for_task_completion(_hash_task)
		_hash_task = -1
		_on_hashed()
	if state in ["current", "failed", "idle"]:
		_recheck_left -= delta
		if _recheck_left <= 0.0:
			check()


func _on_manifest(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_drop_request()
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_fail()
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	var manifest: Dictionary = parsed if parsed is Dictionary else {}
	match decide(manifest, build, engine_version(), OS.get_name()):
		"current", "other":
			latest = manifest
			_set_state("current")
		"reinstall":
			latest = manifest
			_set_state("reinstall")
		"download":
			latest = manifest
			if not FileAccess.file_exists(installed_pack()):
				# A build with its pack inside the exe cannot take a new one.
				_set_state("reinstall")
				return
			var number := int(manifest.get("build", 0))
			if _pending_build() == number and FileAccess.file_exists(pack_path(number)):
				_ready_to_go()
			else:
				_download()
		_:
			_fail()


func _download() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	progress = 0.0
	_set_state("downloading")
	_http = _new_request(download_timeout)
	_http.download_file = PART
	_http.request_completed.connect(_on_downloaded, CONNECT_ONE_SHOT)
	if _http.request(_base + str(latest.get("pack", ""))) != OK:
		_fail()


func _on_downloaded(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	_drop_request()
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 \
			or FileAccess.get_size(PART) != int(latest.get("size", -1)):
		DirAccess.remove_absolute(PART)
		_fail()
		return
	# Hashing a few hundred megabytes takes a moment: off the main thread.
	_set_state("verifying")
	_hash = ""
	var path := ProjectSettings.globalize_path(PART)
	_hash_task = WorkerThreadPool.add_task(func() -> void: _hash = FileAccess.get_sha256(path))


func _on_hashed() -> void:
	var number := int(latest.get("build", 0))
	if _hash != str(latest.get("sha256", "")).to_lower():
		DirAccess.remove_absolute(PART)
		_fail()
		return
	var target := pack_path(number)
	DirAccess.remove_absolute(target)
	if DirAccess.rename_absolute(PART, target) != OK:
		_fail()
		return
	if not _write_json(PENDING, {"build": number, "commit": str(latest.get("commit", "")),
			"godot": str(latest.get("godot", ""))}):
		_fail()
		return
	_clean_old(number)
	_ready_to_go()


func _ready_to_go() -> void:
	if on_start_screen:
		_install(int(latest.get("build", 0)))
	else:
		_set_state("ready")


## At launch: a build downloaded earlier and newer than this one goes in
## now. Returns true when the game is restarting for it.
func _install_pending() -> bool:
	var pending := _read_pending()
	var number := int(pending.get("build", 0))
	if number <= build:
		# Installed (or older than what is installed): the download is spent.
		if number > 0:
			_clean_old(build + 1)
		return false
	if str(pending.get("godot", "")) != engine_version() or not FileAccess.file_exists(pack_path(number)):
		_clean_old(0)
		return false
	latest = pending
	# Just restarted from an install and still on the old build, or tried
	# too often: the game's folder would not take it. Never loop.
	if UPDATED_ARG in OS.get_cmdline_user_args() or int(pending.get("tries", 0)) >= MAX_TRIES:
		_set_state("stuck")
		return false
	_install(number)
	return true


## Puts the downloaded `number` in place of the pack beside the exe and
## starts the game again. A running game holds its pack open, and Windows
## will not replace an open file, so there a small script waits for the game
## to close, moves the pack in and starts it (`install_script`). Elsewhere
## the pack is swapped in at once and the game restarts itself.
func _install(number: int) -> void:
	var target := installed_pack()
	if not FileAccess.file_exists(target):
		# Its pack is inside the exe (a build from before updates): only a
		# fresh install can change it.
		_set_state("reinstall")
		return
	var pending := _read_pending()
	pending["tries"] = int(pending.get("tries", 0)) + 1
	_write_json(PENDING, pending)
	var pack := ProjectSettings.globalize_path(pack_path(number))
	var args := restart_args(OS.get_cmdline_args() + PackedStringArray(["--"]) + OS.get_cmdline_user_args())
	_set_state("restarting")
	if OS.get_name() == "Windows":
		var script := ProjectSettings.globalize_path(DIR.path_join("install.cmd"))
		var file := FileAccess.open(script, FileAccess.WRITE)
		if file == null:
			_set_state("stuck")
			return
		file.store_string(install_script(pack.replace("/", "\\"), target.replace("/", "\\"),
				OS.get_executable_path().replace("/", "\\"), args))
		file.close()
		if OS.create_process("cmd.exe", PackedStringArray(["/c", script.replace("/", "\\")])) <= 0:
			_set_state("stuck")
			return
	else:
		if install_over(pack, target) != OK:
			_set_state("stuck")
			return
		OS.set_restart_on_exit(true, args)
	get_tree().quit()


## The pack the exe loads: beside it, with its name.
static func installed_pack() -> String:
	var candidates := pack_candidates(OS.get_executable_path())
	for path in candidates:
		if FileAccess.file_exists(path):
			return path
	return candidates[0]


## Where the engine looks for its pack, in its order: the exe's name without
## its extension, then the whole name ("Verge.x86_64" finds "Verge.pck",
## then "Verge.x86_64.pck"; a Linux exe renamed to plain "Verge" finds
## "Verge.pck"). An exe renamed with its pack still runs, and updates.
static func pack_candidates(exe: String) -> PackedStringArray:
	var out := PackedStringArray([exe.get_basename() + ".pck"])
	if exe.get_extension() != "":
		out.append(exe + ".pck")
	return out


## The command line for the restart after an install: the same arguments
## (the engine's, "--", the game's), with `UPDATED_ARG` among the game's once.
static func restart_args(current: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	var user := false
	for arg in current:
		if arg == "--":
			if user:
				continue
			user = true
		if arg != UPDATED_ARG:
			out.append(arg)
	if not user:
		out.append("--")
	out.append(UPDATED_ARG)
	return out


## A Windows batch script that waits for the game to let go of `target`
## (up to a minute), moves `pack` over it and starts `exe` with `args`. If
## the move never works it starts the game anyway, which then says so.
static func install_script(pack: String, target: String, exe: String, args: PackedStringArray) -> String:
	var quoted := PackedStringArray()
	for arg in args:
		quoted.append(_cmd_quote(arg))
	return "\r\n".join(PackedStringArray([
		"@echo off",
		"chcp 65001 >nul",
		"set tries=0",
		":wait",
		"move /y %s %s >nul 2>&1" % [_cmd_quote(pack), _cmd_quote(target)],
		"if not errorlevel 1 goto done",
		"set /a tries+=1",
		"if %tries% geq 60 goto done",
		"ping -n 2 127.0.0.1 >nul",
		"goto wait",
		":done",
		"start \"\" %s %s" % [_cmd_quote(exe), " ".join(quoted)],
		"",
	]))


## One argument for a batch script: quoted, with its percent signs doubled
## so cmd does not read them as variables.
static func _cmd_quote(arg: String) -> String:
	return "\"%s\"" % arg.replace("%", "%%").replace("\"", "")


## Copies `pack` over `target` whole: written beside it, then swapped in. Only
## where a pack already stands (an install that embeds its pack has none).
static func install_over(pack: String, target: String) -> Error:
	if not FileAccess.file_exists(target):
		return ERR_FILE_NOT_FOUND
	var fresh := target + ".new"
	var err := DirAccess.copy_absolute(pack, fresh)
	if err == OK and FileAccess.get_size(fresh) != FileAccess.get_size(pack):
		err = ERR_FILE_CORRUPT
	if err == OK:
		err = DirAccess.rename_absolute(fresh, target)
	if err != OK:
		DirAccess.remove_absolute(fresh)
	return err


static func _write_json(path: String, data: Dictionary) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(data))
	file.close()
	return true


func _read_pending() -> Dictionary:
	if not FileAccess.file_exists(PENDING):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PENDING))
	return parsed if parsed is Dictionary else {}


func _pending_build() -> int:
	return int(_read_pending().get("build", 0))


## Removes downloaded packs older than `keep_from` (and the pending note if
## it names one of them).
func _clean_old(keep_from: int) -> void:
	var dir := DirAccess.open(DIR)
	if dir == null:
		return
	for file in dir.get_files():
		if file.begins_with("build-") and file.ends_with(".pck") \
				and file.trim_prefix("build-").trim_suffix(".pck").to_int() < keep_from:
			dir.remove(file)
	if _pending_build() < keep_from:
		dir.remove(PENDING.get_file())


func _fail() -> void:
	_drop_request()
	_set_state("failed")


func _set_state(next: String) -> void:
	if next in ["current", "failed"]:
		_recheck_left = recheck_every
	state = next
	changed.emit()


func _new_request(timeout: float) -> HTTPRequest:
	_drop_request()
	var request := HTTPRequest.new()
	request.timeout = timeout
	request.download_chunk_size = 1 << 18
	request.use_threads = true
	add_child(request)
	return request


func _drop_request() -> void:
	if _http != null:
		_http.queue_free()
		_http = null
