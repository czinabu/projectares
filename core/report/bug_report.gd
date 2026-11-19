extends Node
## Bug reports from testers (the must-work checklist, "Bug reporting with
## logs"): the phone's Report app (`Phone.report_requested`) hands `Main` a
## line of text, and this bundles it with what the game knows: the build,
## where the player is and what they were doing (the context `Main` gives),
## the last life the life log kept, and the game's own log files, the one
## running now and the one before it, which is the run that crashed if the
## game crashed. It goes to the webhook the release build stamps in
## (`WEBHOOK_SETTING`, from the repository secret, never in the code) as a
## Discord message with the logs attached, and a copy is always kept under
## `SAVE_DIR`. A game with no webhook (the editor, a test, a build without
## the secret) only keeps the copy. View and client only: a server never
## makes one, and nothing here reads or changes a profile or an account.

## Where the release build stamps the webhook (`windows-client.yml`).
const WEBHOOK_SETTING := "ares/report/webhook"
const BUILD_SETTING := "ares/build/number"
const COMMIT_SETTING := "ares/build/commit"
const SAVE_DIR := "user://reports"
## The most of each log sent: its end, where the trouble is.
const LOG_TAIL := 1_500_000
## Discord's message text limit, with room to spare.
const MESSAGE_LIMIT := 1900
## What a tester may type.
const TEXT_LIMIT := 600

## Emitted once a report is sent, refused or kept: whether it reached the
## channel (or was kept, where there is no channel) and a line to show.
signal finished(ok: bool, note: String)

## Seconds between reports, so a held key cannot flood the channel.
var report_every := 30.0
var _last_sent := -INF
var _http: HTTPRequest
## Overrides the stamped webhook (tests).
var webhook_override := ""
## Where the copies go (tests point it elsewhere).
var save_dir := SAVE_DIR


## True while a report is on its way.
func busy() -> bool:
	return _http != null


## Seconds until another report may go, 0 if one may now.
func wait_left() -> float:
	return maxf(0.0, _last_sent + report_every - Time.get_ticks_msec() / 1000.0)


## Sends a report of `text` with `context` (place, position and the like,
## plain values from `Main`). Returns false if it was refused at once (empty,
## too soon, one already going); `finished` says how it went otherwise.
func send(text: String, context: Dictionary) -> bool:
	text = text.strip_edges().left(TEXT_LIMIT)
	if text == "":
		finished.emit(false, "Write what happened first.")
		return false
	if busy():
		finished.emit(false, "A report is still on its way.")
		return false
	if wait_left() > 0.0:
		finished.emit(false, "Wait %d s before the next report." % ceili(wait_left()))
		return false
	_last_sent = Time.get_ticks_msec() / 1000.0
	var report := compose(text, context)
	var files := log_files()
	var kept := save_copy(report, files, save_dir)
	var url := webhook_override if webhook_override != "" else webhook()
	if url == "":
		finished.emit(true, "Kept on this computer (this build sends nowhere): %s" % ProjectSettings.globalize_path(kept))
		return true
	var boundary := "AresReport%d" % randi()
	_http = HTTPRequest.new()
	_http.timeout = 30.0
	add_child(_http)
	_http.request_completed.connect(_on_sent.bind(kept))
	var error := _http.request_raw(url, ["Content-Type: multipart/form-data; boundary=" + boundary],
			HTTPClient.METHOD_POST, multipart(report, files, boundary))
	if error != OK:
		_done(false, "Could not send it (%s). Kept on this computer: %s" % [error_string(error),
				ProjectSettings.globalize_path(kept)])
	return true


func _on_sent(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray, kept: String) -> void:
	if result == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 300:
		_done(true, "Sent. Thank you!")
	else:
		_done(false, "Could not send it (%s). Kept on this computer: %s"
				% ["error %d" % code if result == HTTPRequest.RESULT_SUCCESS else "no connection",
				ProjectSettings.globalize_path(kept)])


func _done(ok: bool, note: String) -> void:
	if _http != null:
		_http.queue_free()
		_http = null
	finished.emit(ok, note)


## The stamped webhook, or "" in a build without one.
static func webhook() -> String:
	return str(ProjectSettings.get_setting(WEBHOOK_SETTING, "")).strip_edges()


## The report as plain data: what the tester wrote, the build and the
## machine, and the context.
static func compose(text: String, context: Dictionary) -> Dictionary:
	return {
		"text": text.strip_edges().left(TEXT_LIMIT),
		"build": int(ProjectSettings.get_setting(BUILD_SETTING, 0)),
		"commit": str(ProjectSettings.get_setting(COMMIT_SETTING, "")),
		"engine": Engine.get_version_info().get("string", ""),
		"os": "%s %s" % [OS.get_name(), OS.get_version()],
		"gpu": RenderingServer.get_video_adapter_name(),
		"time": Time.get_datetime_string_from_system(true) + " UTC",
		"context": context,
	}


## The message the channel shows: the tester's words first, then the facts
## that say where to look. Kept under Discord's limit.
static func summary(report: Dictionary) -> String:
	var lines: Array[String] = ["**Bug report**", "> " + str(report.get("text", "")).replace("\n", "\n> ")]
	var build := int(report.get("build", 0))
	lines.append("Build %s%s, Godot %s, %s, %s" % [str(build) if build > 0 else "dev",
			(" (%s)" % report.commit) if str(report.get("commit", "")) != "" else "",
			report.get("engine", ""), report.get("os", ""), report.get("gpu", "")])
	var context: Dictionary = report.get("context", {})
	for key: String in context.keys():
		if key == "last_life":
			continue
		lines.append("%s: %s" % [key.capitalize(), str(context[key])])
	lines.append(str(report.get("time", "")))
	var out := "\n".join(lines)
	if out.length() > MESSAGE_LIMIT:
		out = out.left(MESSAGE_LIMIT - 3) + "..."
	return out


## The game's log files to attach, by file name: the log of this run and
## the one before it (the run that crashed, if one did), the end of each.
static func log_files() -> Dictionary:
	var files := {}
	var current := str(ProjectSettings.get_setting("debug/file_logging/log_path", "user://logs/godot.log"))
	if FileAccess.file_exists(current):
		files["this-run.log"] = tail(current, LOG_TAIL)
	var dir := current.get_base_dir()
	var stem := current.get_file().get_basename()
	var newest := ""
	for name in DirAccess.get_files_at(dir):
		var path := dir.path_join(name)
		if path == current or not name.begins_with(stem) or not name.ends_with(".log"):
			continue
		if newest == "" or FileAccess.get_modified_time(path) > FileAccess.get_modified_time(newest):
			newest = path
	if newest != "":
		files["last-run.log"] = tail(newest, LOG_TAIL)
	return files


## The last `most` bytes of a file.
static func tail(path: String, most: int) -> PackedByteArray:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return PackedByteArray()
	var size := file.get_length()
	file.seek(maxi(0, size - most))
	var bytes := file.get_buffer(mini(size, most))
	file.close()
	return bytes


## The report and its files as a Discord webhook upload: the message as
## `payload_json`, the report itself as JSON, and each log.
static func multipart(report: Dictionary, files: Dictionary, boundary: String) -> PackedByteArray:
	var body := PackedByteArray()
	var part := func(head: String, data: PackedByteArray) -> void:
		body.append_array(("--%s\r\n%s\r\n\r\n" % [boundary, head]).to_utf8_buffer())
		body.append_array(data)
		body.append_array("\r\n".to_utf8_buffer())
	part.call("Content-Disposition: form-data; name=\"payload_json\"\r\nContent-Type: application/json",
			JSON.stringify({"content": summary(report), "allowed_mentions": {"parse": []}}).to_utf8_buffer())
	var attached: Dictionary = {"report.json": JSON.stringify(report, "\t").to_utf8_buffer()}
	attached.merge(files)
	var index := 0
	for name: String in attached.keys():
		part.call("Content-Disposition: form-data; name=\"files[%d]\"; filename=\"%s\"\r\nContent-Type: %s"
				% [index, name, "application/json" if name.ends_with(".json") else "text/plain"], attached[name])
		index += 1
	body.append_array(("--%s--\r\n" % boundary).to_utf8_buffer())
	return body


## Keeps a copy of the report and its logs in one text file under `dir`,
## and returns its path.
static func save_copy(report: Dictionary, files: Dictionary, dir: String) -> String:
	DirAccess.make_dir_recursive_absolute(dir)
	var stamp := Time.get_datetime_string_from_system(true).replace(":", "-")
	var path := dir.path_join("report-%s.txt" % stamp)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return ""
	file.store_string(summary(report) + "\n\n" + JSON.stringify(report, "\t") + "\n")
	for name: String in files.keys():
		file.store_string("\n===== %s =====\n" % name)
		file.store_buffer(files[name])
	file.close()
	return path
