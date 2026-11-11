extends CanvasLayer
## The phone every player carries. It is the game's menu: open it with P in
## the hub or in a raid to reach other players, answer invites, read the
## news and change settings.
##
## It is a view. Online it shows the `NetSession.social_state` the server
## sent and turns taps into requests (`send_message`, `send_invite`,
## `answer_invite`, `change_contact`); it never decides anything itself.
## Offline it still has news and settings.
##
## Load with `const PhoneScript := preload("res://core/phone/phone.gd")`.

## The phone opened or closed. `Main` uses it to free the mouse and to stop
## your character while you look at the screen.
signal opened_changed(open: bool)
## A setting changed (see `GameSettings`). `Main` pushes it into the raid view.
signal settings_changed
signal quit_requested

const SocialService := preload("res://core/social/social_service.gd")
const GameSettings := preload("res://core/settings/game_settings.gd")
const UiTheme := preload("res://core/visual/ui_theme.gd")

const APPS := ["contacts", "messages", "invites", "news", "settings"]
const APP_NAMES := {"contacts": "Contacts", "messages": "Messages", "invites": "Invites",
		"news": "News", "settings": "Settings"}
## The shorter names on the bottom bar.
const NAV_NAMES := {"contacts": "People", "messages": "Chat", "invites": "Invites",
		"news": "News", "settings": "Settings"}

var screen_size := Vector2(480, 760)
## Seconds a pop-up stays on screen.
var notice_seconds := 4.5

## The online session, or null when playing solo.
var net: NetSession
var is_open := false
var app := "contacts"
## The contact whose conversation is open in Messages, or "".
var chat_with := ""
## Contact id -> newest message id (in your own log) you have seen.
var read_upto := {}
## News titles seen, so new ones get a badge.
var news_seen := {}

var _blocker: ColorRect
var _device: PanelContainer
var _status: Label
var _title: Label
var _body: VBoxContainer
var _scroll: ScrollContainer
var _nav := {}
var _notice_panel: PanelContainer
var _notice_label: Label
var _notice_left := 0.0
var _error: Label
var _compose: LineEdit


func _ready() -> void:
	layer = 50
	GameSettings.ensure_loaded()
	_blocker = ColorRect.new()
	_blocker.color = Color(0, 0, 0, 0.35)
	_blocker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	_blocker.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			close())
	add_child(_blocker)
	_build_device()
	_build_notice()
	for entry: Dictionary in SocialService.GAME_NEWS:
		news_seen[entry.title] = false
	_set_open(false)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("phone"):
		toggle()
		get_viewport().set_input_as_handled()
	elif is_open and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _notice_left > 0.0:
		_notice_left -= delta
		_notice_panel.modulate.a = clampf(_notice_left / 0.6, 0.0, 1.0)
		_notice_panel.visible = _notice_left > 0.0
	if is_open:
		_status.text = _status_text()


# ----------------------------------------------------------------- state ----

## Connects the phone to an online session, or `null` for solo play.
func set_session(session: NetSession) -> void:
	if net != null and is_instance_valid(net):
		for pair: Array in [[net.social_changed, _on_social_changed], [net.social_notice, show_notice],
				[net.social_error, _on_social_error], [net.tree_exiting, _on_session_gone]]:
			if pair[0].is_connected(pair[1]):
				pair[0].disconnect(pair[1])
	net = session
	chat_with = ""
	if net != null:
		net.social_changed.connect(_on_social_changed)
		net.social_notice.connect(show_notice)
		net.social_error.connect(_on_social_error)
		net.tree_exiting.connect(_on_session_gone)
	refresh()


func _on_session_gone() -> void:
	set_session(null)


func online() -> bool:
	return net != null and is_instance_valid(net) and not net.social_state.is_empty()


func social() -> Dictionary:
	return net.social_state if online() else {}


func my_id() -> String:
	return social().get("account_id", "")


func contacts() -> Array:
	return social().get("contacts", [])


func contact(id: String) -> Dictionary:
	for entry: Dictionary in contacts():
		if entry.id == id:
			return entry
	return {}


func invites() -> Array:
	return social().get("invites", [])


func news() -> Array:
	return social().get("news", SocialService.GAME_NEWS) if online() else SocialService.GAME_NEWS


## Every message to or from `other`, oldest first.
func conversation_with(other: String) -> Array:
	var out: Array = []
	for message: Dictionary in social().get("messages", []):
		if message.from == other or message.to == other:
			out.append(message)
	return out


## Contact ids you have messages with, newest conversation first.
func conversations() -> Array[String]:
	var out: Array[String] = []
	var messages: Array = social().get("messages", [])
	for i in range(messages.size() - 1, -1, -1):
		var message: Dictionary = messages[i]
		var other: String = message.to if message.from == my_id() else message.from
		if other not in out:
			out.append(other)
	return out


func unread_from(other: String) -> int:
	var count := 0
	var seen := int(read_upto.get(other, 0))
	for message: Dictionary in conversation_with(other):
		if message.from == other and int(message.get("id", 0)) > seen:
			count += 1
	return count


func unread_count() -> int:
	var total := 0
	for other in conversations():
		total += unread_from(other)
	return total


func unseen_news() -> int:
	var count := 0
	for entry: Dictionary in news():
		if not news_seen.get(entry.title, false):
			count += 1
	return count


func _mark_read(other: String) -> void:
	var newest := int(read_upto.get(other, 0))
	for message: Dictionary in conversation_with(other):
		newest = maxi(newest, int(message.get("id", 0)))
	read_upto[other] = newest


func _on_social_changed(_snapshot: Dictionary) -> void:
	if is_open and app == "messages" and chat_with != "":
		_mark_read(chat_with)
	refresh(app != "settings" and app != "news")


func _on_social_error(reason: String) -> void:
	show_notice(reason)
	if _error:
		_error.text = reason


# --------------------------------------------------------------- actions ----

func toggle() -> void:
	if is_open:
		close()
	else:
		open()


func open(p_app := "") -> void:
	if p_app != "":
		app = p_app
	_set_open(true)


func close() -> void:
	_set_open(false)


func _set_open(open_now: bool) -> void:
	var changed := open_now != is_open
	is_open = open_now
	_blocker.visible = open_now
	_device.visible = open_now
	if open_now:
		refresh()
	if changed:
		opened_changed.emit(open_now)


func open_app(p_app: String) -> void:
	if p_app not in APPS:
		return
	app = p_app
	chat_with = ""
	if app == "news":
		for entry: Dictionary in news():
			news_seen[entry.title] = true
	refresh()


func open_chat(other: String) -> void:
	app = "messages"
	chat_with = other
	_mark_read(other)
	refresh()
	if _compose:
		_compose.grab_focus.call_deferred()


func send_message(to: String, text: String) -> void:
	if online() and SocialService.clean_text(text) != "":
		net.send_message(to, text)


func send_invite(to: String, kind: String) -> void:
	if online():
		net.send_invite(to, kind)


func answer_invite(invite_id: int, accept: bool) -> void:
	if online():
		net.answer_invite(invite_id, accept)


func change_contact(action: String, other: String) -> void:
	if online():
		net.change_contact(action, other)


## A short pop-up at the top of the screen, shown even while the phone is away.
func show_notice(text: String) -> void:
	_notice_label.text = text
	_notice_left = notice_seconds
	_notice_panel.visible = true
	_notice_panel.modulate.a = 1.0
	refresh(false)


# ---------------------------------------------------------------- layout ----

func _build_device() -> void:
	_device = PanelContainer.new()
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color(0.04, 0.04, 0.045, 0.98)
	frame.border_color = Color(0.22, 0.2, 0.18)
	frame.set_border_width_all(10)
	frame.set_corner_radius_all(34)
	frame.set_content_margin_all(18)
	frame.shadow_color = Color(0, 0, 0, 0.6)
	frame.shadow_size = 18
	_device.add_theme_stylebox_override("panel", frame)
	_device.custom_minimum_size = screen_size
	_device.anchor_left = 1.0
	_device.anchor_right = 1.0
	_device.anchor_top = 0.5
	_device.anchor_bottom = 0.5
	_device.offset_left = -screen_size.x - 60.0
	_device.offset_right = -60.0
	_device.offset_top = -screen_size.y * 0.5
	_device.offset_bottom = screen_size.y * 0.5
	add_child(_device)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	_device.add_child(column)

	var top := HBoxContainer.new()
	_status = _label("", 13, Color(0.7, 0.7, 0.7))
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_status)
	var close_button := Button.new()
	close_button.text = "Close (P)"
	close_button.pressed.connect(close)
	top.add_child(close_button)
	column.add_child(top)

	_title = _label("", 26, UiTheme.ACCENT)
	column.add_child(_title)
	_error = _label("", 13, Color(1.0, 0.55, 0.45))
	column.add_child(_error)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(_scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 8)
	_scroll.add_child(_body)

	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 4)
	for app_name: String in APPS:
		var button := Button.new()
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 14)
		button.add_theme_constant_override("h_separation", 0)
		button.toggle_mode = true
		button.pressed.connect(open_app.bind(app_name))
		nav.add_child(button)
		_nav[app_name] = button
	column.add_child(nav)


func _build_notice() -> void:
	_notice_panel = PanelContainer.new()
	_notice_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_notice_panel.anchor_left = 1.0
	_notice_panel.anchor_right = 1.0
	_notice_panel.offset_left = -480.0
	_notice_panel.offset_right = -60.0
	_notice_panel.offset_top = 24.0
	_notice_panel.offset_bottom = 70.0
	_notice_label = _label("", 16, UiTheme.INK)
	_notice_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_notice_panel.add_child(_notice_label)
	_notice_panel.visible = false
	add_child(_notice_panel)


func _status_text() -> String:
	var time := Time.get_time_dict_from_system()
	var clock := "%02d:%02d" % [time.hour, time.minute]
	if online():
		return "%s   Online as %s" % [clock, net.account.get("name", "")]
	return "%s   Offline (solo)" % clock


## Redraws the badges, and the open app unless `redraw` is false (so a
## pop-up does not reset a slider you are dragging).
func refresh(redraw := true) -> void:
	if _body == null:
		return
	for app_name: String in APPS:
		var badge := 0
		match app_name:
			"messages": badge = unread_count()
			"invites": badge = invites().size()
			"news": badge = unseen_news()
		_nav[app_name].text = NAV_NAMES[app_name] + (" %d" % badge if badge > 0 else "")
		_nav[app_name].set_pressed_no_signal(app_name == app)
	if not is_open or not redraw:
		return
	_status.text = _status_text()
	_title.text = APP_NAMES[app]
	_error.text = ""
	if app != "messages" or chat_with == "":
		_compose = null
	var keep_draft := _compose.text if _compose != null and is_instance_valid(_compose) else ""
	var had_focus := keep_draft != "" or (_compose != null and is_instance_valid(_compose) and _compose.has_focus())
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	match app:
		"contacts": _draw_contacts()
		"messages": _draw_messages(keep_draft)
		"invites": _draw_invites()
		"news": _draw_news()
		"settings": _draw_settings()
	if had_focus and _compose != null:
		_compose.grab_focus()
		_compose.caret_column = _compose.text.length()


func _offline_note() -> void:
	_body.add_child(_label("You are offline. Join a server from the hub to reach other players. "
			+ "Everyone signed in to the same server shows up here.", 15, Color(0.75, 0.75, 0.75)))


func _draw_contacts() -> void:
	if not online():
		_offline_note()
		return
	var list := contacts()
	if list.is_empty():
		_body.add_child(_label("Nobody else is on this server yet. Players appear here as they sign in.",
				15, Color(0.75, 0.75, 0.75)))
	for entry: Dictionary in list:
		var card := _card()
		var box: VBoxContainer = card.get_child(0)
		var head := HBoxContainer.new()
		var name_label := _label(entry.name, 19, UiTheme.INK if entry.online else Color(0.6, 0.6, 0.6))
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(name_label)
		var place: String = "Blocked" if entry.blocked else (
				SocialService.PLACE_NAMES.get(entry.where, "Online") if entry.online else "Offline")
		var place_label := _label(place, 13, Color(0.5, 0.9, 0.55) if entry.online and not entry.blocked else Color(0.6, 0.6, 0.6))
		place_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		head.add_child(place_label)
		box.add_child(head)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		if not entry.blocked:
			if entry.online or entry.saved:
				row.add_child(_button("Message", open_chat.bind(entry.id)))
			if entry.online:
				row.add_child(_button("Invite to raid", send_invite.bind(entry.id, "world")))
				row.add_child(_button("Invite to base", send_invite.bind(entry.id, "base")))
		box.add_child(row)
		var row2 := HBoxContainer.new()
		row2.add_theme_constant_override("separation", 4)
		if not entry.blocked:
			row2.add_child(_button("Remove contact" if entry.saved else "Save contact",
					change_contact.bind("remove" if entry.saved else "add", entry.id)))
		row2.add_child(_button("Unblock" if entry.blocked else "Block",
				change_contact.bind("unblock" if entry.blocked else "block", entry.id)))
		box.add_child(row2)
		_body.add_child(card)


func _draw_messages(draft: String) -> void:
	if not online():
		_offline_note()
		return
	if chat_with == "":
		var others := conversations()
		if others.is_empty():
			_body.add_child(_label("No messages yet. Open Contacts and tap Message.", 15, Color(0.75, 0.75, 0.75)))
		for other in others:
			var thread := conversation_with(other)
			var last: Dictionary = thread[thread.size() - 1]
			var unread := unread_from(other)
			var shown: String = last.from_name if last.from == other else last.to_name
			var button := _button("%s%s\n%s" % [shown, "  (%d new)" % unread if unread > 0 else "",
					_preview(last.text)], open_chat.bind(other))
			button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			button.custom_minimum_size = Vector2(0, 58)
			_body.add_child(button)
		return
	var info := contact(chat_with)
	var head := HBoxContainer.new()
	head.add_child(_button("< Back", open_app.bind("messages")))
	var who := _label(info.get("name", chat_with), 19, UiTheme.INK)
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(who)
	_body.add_child(head)
	for message: Dictionary in conversation_with(chat_with):
		var mine: bool = message.from == my_id()
		var bubble := _label(message.text, 16, Color(1.0, 0.85, 0.65) if mine else UiTheme.INK)
		bubble.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if mine else HORIZONTAL_ALIGNMENT_LEFT
		var stamp := _label("%s  %s" % ["You" if mine else message.from_name,
				_local_time(float(message.get("time", 0)))], 11, Color(0.55, 0.55, 0.55))
		stamp.horizontal_alignment = bubble.horizontal_alignment
		_body.add_child(stamp)
		_body.add_child(bubble)
	var row := HBoxContainer.new()
	_compose = LineEdit.new()
	_compose.max_length = SocialService.MAX_MESSAGE
	_compose.placeholder_text = "Message"
	_compose.text = draft
	_compose.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var target := chat_with
	var send := func() -> void:
		var text := _compose.text
		_compose.text = ""
		send_message(target, text)
	_compose.text_submitted.connect(func(_t: String) -> void: send.call())
	row.add_child(_compose)
	row.add_child(_button("Send", send))
	_body.add_child(row)
	if not info.get("online", false):
		_body.add_child(_label("They are offline. They will see it when they next sign in here.", 12, Color(0.6, 0.6, 0.6)))
	_scroll.set_deferred("scroll_vertical", 1 << 20)


func _draw_invites() -> void:
	if not online():
		_offline_note()
		return
	var list := invites()
	if list.is_empty():
		_body.add_child(_label("No invites right now. When someone invites you to their raid or base, it shows up here.",
				15, Color(0.75, 0.75, 0.75)))
	var now := Time.get_unix_time_from_system()
	for invite: Dictionary in list:
		var card := _card()
		var box: VBoxContainer = card.get_child(0)
		var where := "their home base"
		if invite.kind == "world":
			var world := Worlds.get_world(invite.get("world_id", ""))
			where = "the raid in %s" % world.display_name if world else "their raid"
		box.add_child(_label("%s invites you to %s." % [invite.from_name, where], 17, UiTheme.INK))
		box.add_child(_label("Open for %d more seconds." % maxi(0, int(float(invite.expires) - now)), 12, Color(0.6, 0.6, 0.6)))
		var row := HBoxContainer.new()
		row.add_child(_button("Accept", answer_invite.bind(int(invite.id), true)))
		row.add_child(_button("Decline", answer_invite.bind(int(invite.id), false)))
		box.add_child(row)
		_body.add_child(card)


func _draw_news() -> void:
	for entry: Dictionary in news():
		var card := _card()
		var box: VBoxContainer = card.get_child(0)
		box.add_child(_label(str(entry.get("date", "")), 12, Color(0.6, 0.6, 0.6)))
		box.add_child(_label(str(entry.title), 19, UiTheme.ACCENT))
		box.add_child(_label(str(entry.get("body", "")), 15, UiTheme.INK))
		_body.add_child(card)


func _draw_settings() -> void:
	_body.add_child(_label("CONTROLS", 15, UiTheme.ACCENT))
	_slider("Mouse sensitivity", "mouse_sensitivity", GameSettings.SENSITIVITY_RANGE, 0.0001,
			GameSettings.mouse_sensitivity, func(v: float) -> String: return "%.1f" % (v * 1000.0))
	_toggle("Invert mouse up and down", "invert_y", GameSettings.invert_y)
	var melee := OptionButton.new()
	melee.add_item("Melee side: mouse flick")
	melee.add_item("Melee side: movement keys")
	melee.select(1 if Profile.melee_control == "move" else 0)
	melee.item_selected.connect(func(index: int) -> void:
		Profile.melee_control = "move" if index == 1 else "mouse"
		Profile.save()
		settings_changed.emit())
	_body.add_child(melee)
	_body.add_child(_label("VIEW AND SOUND", 15, UiTheme.ACCENT))
	_slider("Field of view (first person)", "field_of_view", GameSettings.FOV_RANGE, 1.0, GameSettings.field_of_view,
			func(v: float) -> String: return "%d" % roundi(v))
	_slider("Field of view (third person)", "field_of_view_third", GameSettings.FOV_RANGE, 1.0,
			GameSettings.field_of_view_third, func(v: float) -> String: return "%d" % roundi(v))
	_slider("Volume", "master_volume", Vector2(0.0, 1.0), 0.05, GameSettings.master_volume,
			func(v: float) -> String: return "%d%%" % roundi(v * 100.0))
	_toggle("Fullscreen", "fullscreen", GameSettings.fullscreen)
	_toggle("Names over other players", "show_nameplates", GameSettings.show_nameplates)
	_body.add_child(_label("GAME", 15, UiTheme.ACCENT))
	_body.add_child(_button("Quit the game", func() -> void: quit_requested.emit()))


func _slider(text: String, key: String, range_: Vector2, step: float, value: float, shown: Callable) -> void:
	var head := HBoxContainer.new()
	var name_label := _label(text, 15, UiTheme.INK)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name_label)
	var value_label := _label(shown.call(value), 15, Color(0.75, 0.75, 0.75))
	value_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	head.add_child(value_label)
	_body.add_child(head)
	var slider := HSlider.new()
	slider.min_value = range_.x
	slider.max_value = range_.y
	slider.step = step
	slider.value = value
	slider.value_changed.connect(func(v: float) -> void:
		value_label.text = shown.call(v)
		change_setting(key, v))
	_body.add_child(slider)


func _toggle(text: String, key: String, value: bool) -> void:
	var box := CheckButton.new()
	box.text = text
	box.button_pressed = value
	box.toggled.connect(func(on: bool) -> void: change_setting(key, on))
	_body.add_child(box)


func change_setting(key: String, value: Variant) -> void:
	GameSettings.set_value(key, value)
	settings_changed.emit()


# --------------------------------------------------------------- widgets ----

func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", 14)
	button.pressed.connect(action)
	return button


func _card() -> PanelContainer:
	var card := PanelContainer.new()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	card.add_child(box)
	return card


static func _local_time(unix: float) -> String:
	var bias := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	return Time.get_time_string_from_unix_time(int(unix) + bias).left(5)


static func _preview(text: String) -> String:
	return text if text.length() <= 48 else text.left(45) + "..."
