extends RefCounted
## The phone's review pass (Caleb's "go through the phone"): buttons in a row
## keep their width, pop-ups live on the device and in the world (never flat
## on the view), keys rebind from Settings › Input, and chats read as
## bubbles over a typing box that stays put. The test runner finds this file
## by itself and calls `run(t)`.

const PhoneScript := preload("res://core/phone/phone.gd")
const GameSettings := preload("res://core/settings/game_settings.gd")
const SocialService := preload("res://core/social/social_service.gd")


static func run(t: Node) -> void:
	GameSettings.persist = false
	var phone: CanvasLayer = PhoneScript.new()
	t.add_child(phone)
	await t.frames(1)
	await _rows_keep_buttons(t, phone)
	await _notices_stay_in_the_world(t, phone)
	await _keys_rebind(t, phone)
	phone.queue_free()
	await t.frames(1)


## A sample online state: a squad of two, a friend in a raid, an invite.
static func _go_online(phone: CanvasLayer) -> NetSession:
	var net := NetSession.new()
	var now := Time.get_unix_time_from_system()
	net.account = {"name": "Tester"}
	net.social_state = {"account_id": "me",
		"contacts": [{"id": "a", "name": "Vex", "online": true, "where": "raid", "world": "ashfront",
				"friend": true, "squad": true, "saved": true, "blocked": false}],
		"messages": [{"id": 1, "from": "a", "from_name": "Vex", "to": "me", "to_name": "Tester",
				"text": "Meet at the north depot?", "time": now - 60}],
		"invites": [{"id": 7, "from": "a", "from_name": "Vex", "kind": "squad", "expires": now + 60}],
		"news": SocialService.GAME_NEWS,
		"squad": {"id": "s1", "members": [
			{"id": "me", "name": "Tester", "online": true, "where": "raid", "world": "ashfront", "leader": true},
			{"id": "a", "name": "Vex", "online": true, "where": "raid", "world": "ashfront", "leader": false}]}}
	phone.net = net
	return net


static func _rows_keep_buttons(t: Node, phone: CanvasLayer) -> void:
	var net := _go_online(phone)
	phone.open()
	for app: String in ["contacts", "invites"]:
		phone.open_app(app)
		await t.frames(3)
		var thin: Array[String] = []
		for node: Node in phone._body.find_children("*", "Button", true, false):
			var button := node as Button
			if button.get_parent() is HBoxContainer and button.is_visible_in_tree() and button.size.x < 60.0:
				thin.append("%s (%d px)" % [button.text, button.size.x])
		t.check(thin.is_empty(), "%s: a button beside others keeps its words on one line (%s)" % [app, ", ".join(thin)])
	phone.open_chat("a")
	await t.frames(3)
	var bubbles: Array = phone._body.find_children("*", "PanelContainer", true, false)
	t.check(not bubbles.is_empty() and phone._compose != null and phone._dock.is_ancestor_of(phone._compose),
			"a chat shows its messages as bubbles, the typing box held under the page")
	phone.close()
	phone.net = null
	net.free()
	phone.refresh()


static func _notices_stay_in_the_world(t: Node, phone: CanvasLayer) -> void:
	phone.show_notice("Vex invites you to their squad.")
	await t.frames(1)
	t.check(phone._notice_panel.visible and phone._glass.is_ancestor_of(phone._notice_panel),
			"a pop-up drops in on the phone's own glass, never flat on the view")
	t.check(phone._chassis.lit, "the chin's light is lit while there is news")
	# Headless there is nobody to stand a hologram by, so none shows.
	t.check(phone.notice_holo != null and not phone.notice_holo.visible,
			"the pop-up's hologram shows only for a body in a drawn world")
	phone.drop_notice("")
	phone._notice_left = 0.0
	phone._notice_panel.visible = false
	await t.frames(1)
	t.check(not phone._chassis.lit, "the light goes dark with nothing new")


static func _keys_rebind(t: Node, phone: CanvasLayer) -> void:
	GameSettings.reset_bindings()
	phone.open()
	phone.open_settings_tab("input")
	await t.frames(2)
	var cap := phone._body.find_child("Key_interact", true, false) as Button
	t.check(cap != null and cap.text == "F", "Settings › Input shows each key as a cap to click")
	cap.pressed.emit()
	await t.frames(1)
	var press := InputEventKey.new()
	press.physical_keycode = KEY_K  # the helmet's key
	press.pressed = true
	t.check(phone.rebinding == "interact" and phone._capture_rebind(press), "the next key pressed is taken")
	t.check(PhoneScript.key_name("interact") == "K" and PhoneScript.key_name("helmet") == "F",
			"a key already used swaps over, so no two actions share one")
	t.check(GameSettings.bindings_changed() and "interact=k:%d" % KEY_K in GameSettings.key_binds_saved(),
			"the rebound keys are kept in the settings")
	phone._start_rebind("jump")
	var escape := InputEventKey.new()
	escape.physical_keycode = KEY_ESCAPE
	escape.pressed = true
	phone._capture_rebind(escape)
	t.check(phone.rebinding == "" and PhoneScript.key_name("jump") == "Space", "Esc keeps the old key")
	phone._start_rebind("ping")
	var side := InputEventMouseButton.new()
	side.button_index = MOUSE_BUTTON_XBUTTON2
	side.pressed = true
	phone._capture_rebind(side)
	t.check(PhoneScript.key_name("ping") == "Mouse forward", "a mouse button can be bound too")
	var saved: Array = GameSettings.key_binds_saved().duplicate()
	GameSettings.reset_bindings()
	t.check(PhoneScript.key_name("interact") == "F" and PhoneScript.key_name("helmet") == "K"
			and PhoneScript.key_name("ping") == "Middle mouse" and not GameSettings.bindings_changed(),
			"putting every key back restores the defaults")
	GameSettings.use_saved({"key_binds": saved})
	t.check(PhoneScript.key_name("interact") == "K" and PhoneScript.key_name("helmet") == "F",
			"saved keys come back when the settings load")
	GameSettings.reset_bindings()
	phone.close()
