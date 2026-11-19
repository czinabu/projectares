extends RefCounted
## Bug reports (`core/report/bug_report.gd`, the phone's Report app): what a
## report carries, the upload Discord is sent, the copy kept on the
## tester's computer, the limits that stop a flood, and the app asking for
## one. No report leaves this machine here: the webhook is a closed local
## port, or none.
## Called from the test runner (`-- --only` does not reach this file; the
## runner calls `run`).

const BugReportScript := preload("res://core/report/bug_report.gd")
const PhoneScript := preload("res://core/phone/phone.gd")
const DIR := "user://test_reports"


static func run(t: Node) -> void:
	print("Bug reports: what they carry, where they go")
	_check_contents(t)
	await _check_sending(t)
	await _check_phone_app(t)


static func _check_contents(t: Node) -> void:
	var context := {"place": "Ashfront (ashfront)", "position": "1.0, 2.0, 3.0", "last_life": "{\"outcome\":\"died\"}"}
	var report: Dictionary = BugReportScript.compose("  The bike fell through the floor  ", context)
	t.check(report.text == "The bike fell through the floor" and report.has("build") and report.has("engine")
			and report.has("os") and report.context.position == "1.0, 2.0, 3.0",
			"a report carries what was written, the build, the machine and where the player was")
	var summary: String = BugReportScript.summary(report)
	t.check(summary.contains("The bike fell through the floor") and summary.contains("Ashfront")
			and not summary.contains("outcome"),
			"the channel's message leads with the words and the place, the last life goes in the attachment")
	var long := BugReportScript.compose("x".repeat(5000), {"note": "y".repeat(5000)})
	t.check(long.text.length() == BugReportScript.TEXT_LIMIT
			and BugReportScript.summary(long).length() <= BugReportScript.MESSAGE_LIMIT,
			"what is written and the message stay inside their limits")
	var body: String = BugReportScript.multipart(report, {"this-run.log": "line one\nline two".to_utf8_buffer()}, "B0UND") \
			.get_string_from_utf8()
	t.check(body.begins_with("--B0UND\r\n") and body.contains("name=\"payload_json\"")
			and body.contains("filename=\"report.json\"") and body.contains("filename=\"this-run.log\"")
			and body.contains("line two") and body.ends_with("--B0UND--\r\n")
			and body.contains("\"allowed_mentions\""),
			"the upload is the message, the report and each log, and the message pings nobody")
	DirAccess.make_dir_recursive_absolute(DIR)
	var big := DIR.path_join("big.log")
	var file := FileAccess.open(big, FileAccess.WRITE)
	file.store_string("old ".repeat(1000) + "THE END")
	file.close()
	var end: PackedByteArray = BugReportScript.tail(big, 50)
	t.check(end.size() == 50 and end.get_string_from_utf8().ends_with("THE END"),
			"a long log is cut to its end, where the trouble is")
	var kept: String = BugReportScript.save_copy(report, {"this-run.log": "a log".to_utf8_buffer()}, DIR)
	var copy := FileAccess.get_file_as_string(kept)
	t.check(copy.contains("The bike fell through the floor") and copy.contains("===== this-run.log =====")
			and copy.contains("a log"), "a copy of the report and its logs is kept on the computer")


static func _check_sending(t: Node) -> void:
	var sender: Node = BugReportScript.new()
	sender.save_dir = DIR
	t.add_child(sender)
	var heard: Array = []
	sender.finished.connect(func(ok: bool, note: String) -> void: heard.append([ok, note]))
	t.check(not sender.send("   ", {}) and heard.size() == 1 and not heard[0][0],
			"an empty report is refused with a reason")
	# This build has no webhook stamped: the report is kept, not sent.
	t.check(BugReportScript.webhook() == "", "a build without the secret has no webhook")
	heard.clear()
	t.check(sender.send("Kept here", {"place": "home base"}) and heard.size() == 1 and heard[0][0]
			and str(heard[0][1]).begins_with("Kept on this computer"),
			"with no webhook a report is kept on the computer, and says so")
	heard.clear()
	t.check(not sender.send("Again at once", {}) and heard.size() == 1 and str(heard[0][1]).begins_with("Wait"),
			"a second report straight after is refused, so the channel cannot be flooded")
	# Nothing listens on port 9: the send fails and the copy is kept.
	sender.report_every = 0.0
	sender.webhook_override = "http://127.0.0.1:9/api/webhooks/1/test"
	heard.clear()
	sender.send("Nobody hears this", {})
	var frames := 0
	while heard.is_empty() and frames < 600:
		await t.frames(1)
		frames += 1
	t.check(heard.size() == 1 and not heard[0][0] and str(heard[0][1]).contains("Kept on this computer")
			and not sender.busy(), "a report that cannot be sent says so and is kept (%s)" % str(heard))
	sender.queue_free()
	for name in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR.path_join(name))


static func _check_phone_app(t: Node) -> void:
	var phone: CanvasLayer = PhoneScript.new()
	t.add_child(phone)
	await t.frames(1)
	var asked: Array[String] = []
	phone.report_requested.connect(func(text: String) -> void: asked.append(text))
	phone.toggle()
	phone.open_app("report")
	await t.frames(1)
	var edit := phone._body.find_child("ReportEdit", true, false) as LineEdit
	t.check(edit != null and "report" in PhoneScript.APPS, "the phone has a Report app with somewhere to write")
	phone.send_report()
	t.check(asked.is_empty() and phone.report_status != "", "it will not send an empty report")
	if edit != null:
		edit.text = "Stuck on the travel screen"
		edit.text_changed.emit(edit.text)
	phone.send_report()
	t.check(asked == ["Stuck on the travel screen"] and phone.report_sending, "Send hands the words over")
	phone.send_report()
	t.check(asked.size() == 1, "and only once while it is on its way")
	phone.set_report_status("Sent. Thank you!", true)
	await t.frames(1)
	var shown := false
	for label in phone._body.find_children("*", "Label", true, false):
		shown = shown or (label as Label).text == "Sent. Thank you!"
	var cleared := phone._body.find_child("ReportEdit", true, false) as LineEdit
	t.check(shown and not phone.report_sending and cleared != null and cleared.text == "",
			"the app says how it went and clears what was sent")
	phone.close()
	phone.queue_free()
	await t.frames(1)
