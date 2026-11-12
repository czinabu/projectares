extends CanvasLayer
## The phone every player carries. It is the game's menu: open it with P in
## the hub or in a raid to reach other players, answer invites, read the
## news, try on clothes in front of a mirror, look up the controls and change
## settings.
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
## The Mirror app was opened (true) or left (false). `Main` stands a mirror
## in front of the player while it is up (`core/visual/mirror.gd`).
signal mirror_changed(up: bool)

const SocialService := preload("res://core/social/social_service.gd")
const GameSettings := preload("res://core/settings/game_settings.gd")
const UiTheme := preload("res://core/visual/ui_theme.gd")
const CharacterPanel := preload("res://core/ui/character_panel.gd")

const APPS := ["contacts", "messages", "invites", "news", "mirror", "controls", "settings"]
const APP_NAMES := {"contacts": "Contacts", "messages": "Messages", "invites": "Invites",
		"news": "News", "mirror": "Mirror", "controls": "Controls", "settings": "Settings"}
## The shorter names on the bottom bar.
const NAV_NAMES := {"contacts": "People", "messages": "Chat", "invites": "Invites",
		"news": "News", "mirror": "Mirror", "controls": "Keys", "settings": "Settings"}

## The Controls app: what every key does, in sections. Each row is
## [what it does, the keys]. `{action}` in the keys is replaced by whatever is
## bound to that input action right now (`key_name`), so the list follows the
## input map, rebinding included. Anything else is shown as written (the
## mouse, Esc, keys the code reads directly). Every action in `InputSetup`
## must appear here at least once; a test checks it.
const CONTROLS := [
	["ON FOOT", [
		["Move", "{move_forward} {move_left} {move_back} {move_right}"],
		["Look around", "Mouse"],
		["Sprint", "Hold {sprint}"],
		["Jump", "{jump}"],
		["Dash", "{dash}"],
		["Slide (while sprinting)", "{slide}"],
		["First or third person", "{toggle_view}"],
	]],
	["FLYING: JETPACK", [
		["Climb (in the air)", "Hold {jump}"],
		["Light the jets and hover", "Tap {jump} in the air"],
		["Cruise while hovering", "{move_forward} {move_left} {move_back} {move_right}"],
		["Coast down with the jets idle to cool", "Hold {slide}"],
		["Boost head first (Mk2)", "{sprint} + {move_forward}"],
	]],
	["FLYING: THRUSTER BOOTS", [
		["Kick up and the way you steer (three reach a roof)", "{jump} in the air"],
		["Skim low (cools near a street or a roof)", "Hold {jump} in the air"],
		["Dash on heat", "{dash} in the air"],
	]],
	["FLYING: GLIDE WINGS", [
		["Launch", "{jump} in the air"],
		["Glide (while falling)", "Hold {jump}"],
		["Pulse up while gliding", "{jump} again"],
		["Bank round", "{move_left} / {move_right}"],
		["Dive for speed, pull up to climb on it", "{move_forward} / {move_back}"],
		["Barrel roll while gliding", "{roll_left} / {roll_right}"],
		["Roll the body while boosting", "{roll_left} / {roll_right}"],
	]],
	["WEAPONS", [
		["Fire", "{fire}"],
		["Aim down sights", "Hold {alt_fire}"],
		["Reload", "{reload}"],
		["Primary / sidearm / melee / power weapon", "{weapon_1} {weapon_2} {weapon_3} {weapon_4}, or the wheel"],
		["Put away, or draw again", "{holster}"],
		["Use a medkit", "{heal}"],
		["Use your ability", "{ability}"],
		["Use your helmet's visor (zoom, scan, thermal)", "{visor}, again to step or turn off"],
	]],
	["MELEE", [
		["Light attack (combo)", "Tap {fire}"],
		["Heavy attack (a dive slam in the air)", "Hold {fire}"],
		["Block", "Hold {alt_fire}"],
		["Parry", "{alt_fire} just before a hit"],
		["Pick a side: left, right or overhead", "Flick the mouse, or hold {move_left} {move_right} {move_forward}"],
		["Switch how the side is picked", "{melee_control}"],
	]],
	["WATCH", [
		["Raise or lower the watch", "{check_wrist}"],
		["Pick a toy vehicle (watch up)", "Mouse wheel"],
		["Take the toy in your hand (watch up)", "{fire}"],
		["Throw the toy, or put it back", "{fire}, or {alt_fire}"],
		["Pack the bike you look at (watch up)", "{fire}"],
	]],
	["VEHICLES", [
		["Get on or off", "{interact}"],
		["Throttle / brake or reverse", "{move_forward} / {move_back}"],
		["Steer", "{move_left} / {move_right}"],
		["Boost", "{sprint}"],
	]],
	["IN THE WORLD", [
		["Loot, use a console or a doorway", "{interact}"],
		["Scoreboard", "Hold {scoreboard}"],
		["Sign out and go home (10 s, out of a fight)", "{sign_out}"],
		["After dying: drop back in", "{redeploy}"],
		["After dying: pick where to land", "1 to 9"],
		["After dying: go home", "{sign_out}"],
	]],
	["PHONE AND MOUSE", [
		["Open or close the phone", "{phone}"],
		["Free the mouse, step back from a console", "Esc"],
		["Mirror app: choose, then scroll", "Arrows or W A S D"],
	]],
]

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
## The customizer's choices (the hub's `CharacterPanel`), which the Mirror
## app scrolls through. Set with `set_wardrobe`.
var wardrobe: CharacterPanel
## True while a mirror stands in the world for the Mirror app.
var mirror_up := false
## The choice the Mirror app's keys move (an index of `wardrobe.pick_keys()`).
var mirror_row := 0

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
var _mirror_was_up := false


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
	elif mirror_open() and event is InputEventKey and event.pressed and _mirror_key(event.keycode):
		get_viewport().set_input_as_handled()


## The Mirror app's keys: up and down (or W and S) pick a choice, left and
## right (or A and D) scroll through it.
func _mirror_key(key: Key) -> bool:
	var rows := wardrobe.pick_keys().size() if wardrobe != null else 0
	if rows == 0:
		return false
	match key:
		KEY_UP, KEY_W: mirror_row = posmod(mirror_row - 1, rows)
		KEY_DOWN, KEY_S: mirror_row = posmod(mirror_row + 1, rows)
		KEY_LEFT, KEY_A: mirror_step(wardrobe.pick_keys()[mirror_row], -1)
		KEY_RIGHT, KEY_D: mirror_step(wardrobe.pick_keys()[mirror_row], 1)
		_: return false
	refresh()
	return true


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


## Connects the Mirror app to the customizer's choices.
func set_wardrobe(panel: CharacterPanel) -> void:
	if wardrobe != null and is_instance_valid(wardrobe) and wardrobe.changed.is_connected(_on_wardrobe_changed):
		wardrobe.changed.disconnect(_on_wardrobe_changed)
	wardrobe = panel
	if wardrobe != null:
		wardrobe.changed.connect(_on_wardrobe_changed)
	refresh()


func _on_wardrobe_changed(_appearance: Dictionary) -> void:
	if mirror_open():
		# Deferred: the change may come from a row that the redraw frees.
		refresh.call_deferred()


## True while the phone is out on the Mirror app.
func mirror_open() -> bool:
	return is_open and app == "mirror"


## `Main` reports whether a mirror could stand in front of the player.
func set_mirror_up(up: bool) -> void:
	mirror_up = up
	if mirror_open():
		refresh()


## Scrolls one choice of the look, from what the player owns.
func mirror_step(key: String, steps: int) -> void:
	if wardrobe != null:
		wardrobe.step(key, steps)
		var keys := wardrobe.pick_keys()
		if key in keys:
			mirror_row = keys.find(key)


## Tells `Main` when the Mirror app comes up or goes away, and clears the
## shade so the mirror can be seen.
func _sync_mirror() -> void:
	var up := mirror_open()
	_blocker.color.a = 0.0 if up else 0.35
	if up != _mirror_was_up:
		_mirror_was_up = up
		mirror_changed.emit(up)


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
	_sync_mirror()


func open_app(p_app: String) -> void:
	if p_app not in APPS:
		return
	app = p_app
	chat_with = ""
	if app == "news":
		for entry: Dictionary in news():
			news_seen[entry.title] = true
	refresh()
	_sync_mirror()


func open_chat(other: String) -> void:
	app = "messages"
	chat_with = other
	_mark_read(other)
	refresh()
	_sync_mirror()
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
		"mirror": _draw_mirror()
		"controls": _draw_controls()
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


## Each choice of the look as a row to scroll through: arrows, the mouse
## wheel over the row, or the keys. Only starter clothes and outfits the
## player owns are offered, so this is their wardrobe.
func _draw_mirror() -> void:
	if wardrobe == null:
		_body.add_child(_label("Your wardrobe is not here.", 15, UiTheme.INK))
		return
	_body.add_child(_label("Look ahead: the mirror shows you. Scroll through what you own. Changes save as you go."
			if mirror_up else "Out in the world a mirror stands in front of you. Changes still save as you go.",
			14, Color(0.7, 0.7, 0.7)))
	var keys := wardrobe.pick_keys()
	mirror_row = clampi(mirror_row, 0, keys.size() - 1)
	for i in keys.size():
		var row := _mirror_row(keys[i], i == mirror_row)
		_body.add_child(row)
		if i == mirror_row:
			_keep_in_view.call_deferred(row)
	_body.add_child(_label("Up / down: choose   Left / right or the wheel: scroll", 13, Color(0.6, 0.6, 0.6)))
	var shuffle := _button("Surprise me", func() -> void: wardrobe.randomize_look())
	shuffle.focus_mode = Control.FOCUS_NONE
	_body.add_child(shuffle)


## Scrolls the phone so the chosen row shows, unless a redraw replaced it.
func _keep_in_view(row: Control) -> void:
	if is_instance_valid(row) and _body.is_ancestor_of(row):
		_scroll.ensure_control_visible(row)


func _mirror_row(key: String, selected: bool) -> PanelContainer:
	var card := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.11, 0.1, 0.95) if selected else Color(0.08, 0.075, 0.07, 0.9)
	style.border_color = UiTheme.ACCENT if selected else Color(0.2, 0.19, 0.17)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(6)
	card.add_theme_stylebox_override("panel", style)
	card.gui_input.connect(func(event: InputEvent) -> void:
		var button := event as InputEventMouseButton
		if button == null or not button.pressed:
			return
		if button.button_index not in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_LEFT]:
			return
		# Taken before the redraw below frees this row.
		card.accept_event()
		match button.button_index:
			MOUSE_BUTTON_WHEEL_UP: mirror_step(key, -1)
			MOUSE_BUTTON_WHEEL_DOWN: mirror_step(key, 1)
			MOUSE_BUTTON_LEFT: mirror_row = wardrobe.pick_keys().find(key)
		refresh.call_deferred())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	card.add_child(row)
	var back := _button("<", mirror_step.bind(key, -1))
	back.focus_mode = Control.FOCUS_NONE
	back.custom_minimum_size = Vector2(40, 40)
	row.add_child(back)
	var middle := VBoxContainer.new()
	middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	middle.add_theme_constant_override("separation", 0)
	middle.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(middle)
	var at: Array = wardrobe.pick_position(key)
	var head := _label("%s   %d / %d" % [wardrobe.pick_title(key).to_upper(), at[0] + 1, at[1]], 12,
			UiTheme.ACCENT if selected else Color(0.6, 0.6, 0.6))
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	middle.add_child(head)
	var value := _label(wardrobe.pick_label(key), 19, UiTheme.INK)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	middle.add_child(value)
	var source := wardrobe.pick_source(key)
	if source != "":
		var from := _label(source, 12, Color(0.65, 0.6, 0.55))
		from.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		middle.add_child(from)
	for label: Label in [head, value]:
		label.mouse_filter = Control.MOUSE_FILTER_PASS
	var next := _button(">", mirror_step.bind(key, 1))
	next.focus_mode = Control.FOCUS_NONE
	next.custom_minimum_size = Vector2(40, 40)
	row.add_child(next)
	return card


## Every control, read from the input map as it is now.
func _draw_controls() -> void:
	_body.add_child(_label("What every key does right now.", 14, Color(0.7, 0.7, 0.7)))
	for section: Array in CONTROLS:
		_body.add_child(_label(section[0], 15, UiTheme.ACCENT))
		for row: Array in section[1]:
			var line := HBoxContainer.new()
			line.add_theme_constant_override("separation", 10)
			var what := _label(row[0], 14, UiTheme.INK)
			what.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			what.size_flags_stretch_ratio = 1.3
			line.add_child(what)
			var keys := _label(controls_text(row[1]), 14, Color(1.0, 0.85, 0.65))
			keys.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			keys.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			line.add_child(keys)
			# Clear of the scroll bar.
			var pad := Control.new()
			pad.custom_minimum_size = Vector2(4, 0)
			line.add_child(pad)
			_body.add_child(line)


## A `CONTROLS` key spec with each `{action}` replaced by its bound keys.
static func controls_text(spec: String) -> String:
	var out := spec
	var at := out.find("{")
	while at >= 0:
		var end := out.find("}", at)
		if end < 0:
			break
		var shown := key_name(out.substr(at + 1, end - at - 1))
		out = out.left(at) + shown + out.substr(end + 1)
		at = out.find("{", at + shown.length())
	return out


## The keys and buttons bound to an input action, as a player reads them
## ("F", "Left mouse or Mouse back"). "?" when nothing is bound.
static func key_name(action: String) -> String:
	if not InputMap.has_action(action):
		return "?"
	var names: Array[String] = []
	for event: InputEvent in InputMap.action_get_events(action):
		var shown := _event_name(event)
		if shown != "" and shown not in names:
			names.append(shown)
	return " or ".join(names) if not names.is_empty() else "?"


static func _event_name(event: InputEvent) -> String:
	if event is InputEventMouseButton:
		match (event as InputEventMouseButton).button_index:
			MOUSE_BUTTON_LEFT: return "Left mouse"
			MOUSE_BUTTON_RIGHT: return "Right mouse"
			MOUSE_BUTTON_MIDDLE: return "Middle mouse"
			MOUSE_BUTTON_XBUTTON1: return "Mouse back"
			MOUSE_BUTTON_XBUTTON2: return "Mouse forward"
			MOUSE_BUTTON_WHEEL_UP: return "Wheel up"
			MOUSE_BUTTON_WHEEL_DOWN: return "Wheel down"
		return "Mouse %d" % (event as InputEventMouseButton).button_index
	if event is InputEventKey:
		var key := event as InputEventKey
		var code := key.physical_keycode
		if code != KEY_NONE:
			# The key in that spot on this keyboard's layout (Z on AZERTY for W).
			if DisplayServer.get_name() != "headless":
				code = DisplayServer.keyboard_get_keycode_from_physical(code)
		else:
			code = key.keycode
		return OS.get_keycode_string(code)
	return ""


func _draw_settings() -> void:
	_body.add_child(_label("CONTROLS", 15, UiTheme.ACCENT))
	_body.add_child(_button("See what every key does", open_app.bind("controls")))
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
