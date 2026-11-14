extends CanvasLayer
## The phone every player carries. It is the game's menu: open it with P in
## the hub or in a raid to reach other players, answer invites, read the
## news, try on clothes in front of a mirror, look up the controls and change
## settings.
##
## It is a real thing in the world, not a panel over the screen: a rugged
## handheld with a pistol grip (`core/phone/handheld.gd`) that your
## character's own right hand closes round and raises (`ActorCommand.phone`),
## so first person, third person, other players and a mirror all see the
## same device in the same hand, and only the camera differs. You click on
## its face. The screen is a `SubViewport` with the device's frame and chin
## keys, a home screen of live readouts and app icons, and the page an app
## draws on. With no hand to hold it (a headless test) the same screen
## shows flat.
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
## DEV MODE: dev mode or one of its cheats was switched (`core/dev/dev_mode.gd`).
signal dev_mode_changed
signal quit_requested
## The Mirror app was opened (true) or left (false). `Main` stands a mirror
## in front of the player while it is up (`core/visual/mirror.gd`).
signal mirror_changed(up: bool)
## The new player's tour was asked to stop ("skip") or start over ("replay")
## from Settings. `Main` runs the tour (`Onboarding`).
signal tour_requested(action: String)

const SocialService := preload("res://core/social/social_service.gd")
const GameSettings := preload("res://core/settings/game_settings.gd")
const DevMode := preload("res://core/dev/dev_mode.gd")  # DEV MODE
const UiTheme := preload("res://core/visual/ui_theme.gd")
const CharacterPanel := preload("res://core/ui/character_panel.gd")

const MirrorScript := preload("res://core/visual/mirror.gd")
const Handheld := preload("res://core/phone/handheld.gd")

const APPS := ["contacts", "messages", "invites", "news", "mirror", "controls", "settings"]
const APP_NAMES := {"contacts": "Contacts", "messages": "Messages", "invites": "Invites",
		"news": "News", "mirror": "Mirror", "controls": "Controls", "settings": "Settings"}
## The names under the home screen's icons.
const NAV_NAMES := {"contacts": "People", "messages": "Chat", "invites": "Invites",
		"news": "News", "mirror": "Mirror", "controls": "Keys", "settings": "Settings"}
## The screen's colours: the dark glass, the panels on it, and the dimmer
## ink for secondary text. The device's body is gunmetal.
const SCREEN_BG := Color(0.035, 0.04, 0.047)
const PANEL_BG := Color(0.06, 0.065, 0.075, 0.92)
const DIM_INK := Color(0.62, 0.62, 0.6)
const CASE_COLOR := Color(0.12, 0.122, 0.13)
## The Settings app's tabs, in order, and their names. "dev" is only shown
## where dev mode is available (DEV MODE).
const SETTINGS_TABS := ["input", "view", "system", "dev"]
const SETTINGS_TAB_NAMES := {"input": "Input", "view": "View", "system": "System", "dev": "Dev"}
## The home screen, which is not an app of its own.
const HOME := "home"

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
	["FLYING: EVERY RIG", [
		["Dash the way you steer, on heat (in the air)", "{sprint} + {move_forward} {move_left} {move_back} {move_right}"],
		["Dash forward (in the air)", "Tap {sprint}"],
	]],
	["FLYING: JETPACK", [
		["Climb (in the air)", "Hold {jump}"],
		["Hover (in the air)", "Hold {alt_fire}"],
		["Cruise while hovering", "{move_forward} {move_left} {move_back} {move_right}"],
		["Coast down with the jets idle to cool", "Hold {slide} while hovering"],
		["Boost head first, prone (Mk2)", "{sprint} in the air, hold to keep going"],
	]],
	["FLYING: THRUSTER BOOTS", [
		["Kick up and the way you steer (three reach a roof)", "{jump} in the air"],
		["Skim low (cools near a street or a roof)", "Hold {jump} in the air"],
	]],
	["FLYING: GLIDE WINGS", [
		["Launch", "{jump} in the air"],
		["Glide (while falling)", "Hold {jump}"],
		["Pulse up while gliding", "{jump} again"],
		["Steer: the wings fly where you look", "Mouse"],
		["Free look (the wings fly straight on)", "Hold {free_look}"],
		["Bank round harder", "{move_left} / {move_right}"],
		["Dive for speed, pull up to climb on it", "{move_forward} / {move_back}"],
		["Boost ahead the way you face", "{sprint}"],
		["Boost upward (wings pulled up)", "{sprint} + {move_back}"],
	]],
	["WEAPONS", [
		["Fire", "{fire}"],
		["Aim down sights", "Hold {alt_fire}"],
		["Reload", "{reload}"],
		["Primary / sidearm / melee", "{weapon_1} {weapon_2} {weapon_3}, or the wheel (watch down)"],
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
		["Move across the watch's icons and tabs (watch up)", "Mouse wheel"],
		["Open an icon's list: weapons, toy vehicles, artifacts, portals (watch up)", "{fire}"],
		["Pick from an opened list (watch up)", "Mouse wheel"],
		["Close the list, back to the icons (watch up)", "{alt_fire}"],
		["Draw the picked weapon, summon it out of your pack, or put on a helmet or armor from it (watch up)", "{fire}"],
		["Take the toy in your hand (watch up)", "{fire}"],
		["Throw the toy, or put it back", "{fire}, or {alt_fire}"],
		["Pack the bike you look at (watch up)", "{fire}"],
		["Use your artifact (watch up, on the artifact icon)", "{fire}"],
		["Ping where you look for your squad (watch up, on the ping icon)", "{fire}"],
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
		["Open the phone at Settings, or close it; step back from a console", "Esc"],
		["Mirror app: choose, then scroll", "Arrows or W A S D"],
	]],
]

## The screen's pixels, the hardware round it included: the frame, the
## corner screws and the chin with its two buttons are drawn on the same
## viewport, so the whole face is one picture and one place to click.
var screen_size := Vector2i(480, 800)
## Text on the screen is drawn this much bigger than the sizes the apps ask
## for, so it still reads with the device held small and low.
var text_scale := 1.6
## Where the glass sits inside the frame (left, top, right, bottom, pixels).
var glass_inset := Vector4(22, 44, 22, 104)
## Seconds a pop-up stays on screen.
var notice_seconds := 4.5

## The online session, or null when playing solo.
var net: NetSession
var is_open := false
var app := HOME
## Tests set this: a headless run has no real mouse mode to capture.
var mouse_in_world := false
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
## Messages kept on this phone only, offline too: the new player's handler
## (`Onboarding.HANDLER_ID`). Each like a server message: {id, from,
## from_name, to, to_name, text, time}. `Main` fills it.
var local_messages: Array[Dictionary] = []
## Contact id -> shown name, for the senders of `local_messages`.
var local_names := {}
## Whether the Settings app offers to skip the tour (it is running) or to
## play it again. `Main` sets it.
var tour_running := false

## The screen's 2D viewport: everything on the phone draws here.
var _screen: SubViewport
var _status: Label
var _who: Label
var _bars: SignalBars
var _clock: Label
var _home_note: Label
var _home: Control
var _page: Control
var _title: Label
var _body: VBoxContainer
var _scroll: ScrollContainer
var _icons := {}
## The home screen's live readings ("link", "inbox", "news").
var _readouts := {}
## The Settings app's open tab (`SETTINGS_TABS`) and the row of tabs.
var settings_tab := "input"
var _tabs: HBoxContainer
var _chassis: Control
## Who holds this phone (your own actor, `set_holder`): their character's
## hand holds the handheld (`ActorSkin.handheld`) and its face shows this
## screen. Null in a test with no world.
var holder: Node3D
## The holo panel of the handheld being held now, where clicks land, or
## null (then the screen shows flat, as with no world at all).
var _device: MeshInstance3D
## The material that puts this screen on the handheld's face.
var _face_mat: StandardMaterial3D
## Without a camera: the screen shown flat.
var _flat: TextureRect
## 0 put away, 1 held up.
var _raise := 0.0
var _notice_panel: PanelContainer
var _notice_label: Label
var _notice_left := 0.0
var _error: Label
var _compose: LineEdit
var _mirror_was_up := false


func _ready() -> void:
	layer = 50
	GameSettings.ensure_loaded()
	_build_screen()
	_build_flat()
	_build_notice()
	for entry: Dictionary in SocialService.GAME_NEWS:
		news_seen[entry.title] = false
	_set_open(false)


## While the phone is out it has the mouse: a click on its screen lands on the
## screen, a click anywhere else puts it away. Keys go to the screen first,
## so typing a message works; one it does not use falls through to
## `_unhandled_input`.
func _input(event: InputEvent) -> void:
	if not is_open:
		return
	if event is InputEventMouse:
		var mouse := event as InputEventMouse
		var at := screen_point(mouse.position)
		get_viewport().set_input_as_handled()
		if at.x < 0.0:
			var button := mouse as InputEventMouseButton
			if button != null and button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
				close()
			return
		var button := mouse as InputEventMouseButton
		if button != null and button.pressed and button.button_index == MOUSE_BUTTON_XBUTTON1:
			go_back()
			return
		var moved := mouse.duplicate() as InputEventMouse
		moved.position = at
		moved.global_position = at
		_screen.push_input(moved, true)
	elif event is InputEventKey:
		_screen.push_input(event.duplicate(), true)
		if _screen.is_input_handled():
			get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("phone"):
		toggle()
		get_viewport().set_input_as_handled()
	elif is_open and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()
	elif not is_open and opens_on_escape(event):
		open("settings")
		get_viewport().set_input_as_handled()
	elif mirror_open() and event is InputEventKey and event.pressed and _mirror_key(event.keycode):
		get_viewport().set_input_as_handled()


## Esc in the world opens the phone at Settings. Only when nothing else has
## the mouse: a station, booth or shop shows the mouse and takes Esc for
## itself, so Esc there steps away as before.
func opens_on_escape(event: InputEvent) -> bool:
	return event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_ESCAPE \
			and (mouse_in_world or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED)


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
		_update_status()
	_hold(get_viewport().get_camera_3d())


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


## The server's messages, then the ones kept on this phone (the handler).
func all_messages() -> Array:
	return social().get("messages", []) + local_messages


## A message from someone who lives on this phone only (the new player's
## handler), shown in Messages offline too, with a notice that names them.
## `notice` is the short line the notice shows ("" shows the message);
## `quiet` adds it with no notice at all (putting back old messages).
func add_local_message(from: String, from_name: String, text: String, notice := "", quiet := false) -> void:
	local_names[from] = from_name
	local_messages.append({"id": local_messages.size() + 1, "from": from, "from_name": from_name,
			"to": "", "to_name": "", "text": text, "time": Time.get_unix_time_from_system()})
	if is_open and app == "messages" and chat_with == from:
		_mark_read(from)
	if not quiet:
		show_notice("%s: %s" % [from_name, notice if notice != "" else _preview(text)])
	refresh(app == "messages")


## Forgets the messages from `from` kept on this phone.
func clear_local_messages(from: String) -> void:
	local_messages = local_messages.filter(func(m: Dictionary) -> bool: return m.from != from)
	for i in local_messages.size():
		local_messages[i].id = i + 1
	read_upto.erase(from)
	refresh(app == "messages")


## Every message to or from `other`, oldest first.
func conversation_with(other: String) -> Array:
	var out: Array = []
	for message: Dictionary in all_messages():
		if message.from == other or message.to == other:
			out.append(message)
	return out


## Contact ids you have messages with, newest conversation first.
func conversations() -> Array[String]:
	var out: Array[String] = []
	var messages := all_messages()
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
	_screen.render_target_update_mode = SubViewport.UPDATE_ALWAYS if open_now else SubViewport.UPDATE_WHEN_VISIBLE
	if open_now:
		refresh()
	else:
		# Whatever was hovered or typed in lets go.
		var focused := _screen.gui_get_focus_owner()
		if focused:
			focused.release_focus()
		_hold(get_viewport().get_camera_3d() if is_inside_tree() else null)
	if changed:
		opened_changed.emit(open_now)
	_sync_mirror()


## The home screen, from any app.
func go_home() -> void:
	open_app(HOME)


## One step back: from a conversation to the list of them, from an app to
## the home screen.
func go_back() -> void:
	if app == "messages" and chat_with != "":
		open_app("messages")
	elif app != HOME:
		go_home()


func open_app(p_app: String) -> void:
	if p_app not in APPS and p_app != HOME:
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

## The screen: a 2D viewport with the device's frame and chin, the glass
## inside it (a dark backdrop, the status bar, the home screen and the page
## an app draws on) and the chin's back and home buttons.
func _build_screen() -> void:
	_screen = SubViewport.new()
	_screen.name = "Screen"
	_screen.size = screen_size
	_screen.disable_3d = true
	_screen.transparent_bg = true
	_screen.gui_embed_subwindows = true
	_screen.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	add_child(_screen)

	var chassis := Chassis.new()
	chassis.name = "Bezel"
	chassis.glass = glass_inset
	chassis.theme = screen_theme(text_scale)
	chassis.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_screen.add_child(chassis)
	_chassis = chassis

	# The glass: everything on it is clipped to its rounded corners.
	var glass := Panel.new()
	glass.name = "Glass"
	var lit := StyleBoxFlat.new()
	lit.bg_color = SCREEN_BG
	lit.set_corner_radius_all(14)
	lit.anti_aliasing_size = 1.5
	glass.add_theme_stylebox_override("panel", lit)
	glass.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	glass.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glass.offset_left = glass_inset.x
	glass.offset_top = glass_inset.y
	glass.offset_right = -glass_inset.z
	glass.offset_bottom = -glass_inset.w
	chassis.add_child(glass)
	var backdrop := Backdrop.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glass.add_child(backdrop)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 12)
	glass.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)

	# Status bar: the time, the link and who you are signed in as.
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 10)
	_status = _label("", 14, UiTheme.INK)
	_status.autowrap_mode = TextServer.AUTOWRAP_OFF
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(_status)
	_bars = SignalBars.new()
	_bars.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_child(_bars)
	_who = _label("", 14, DIM_INK)
	_who.autowrap_mode = TextServer.AUTOWRAP_OFF
	bar.add_child(_who)
	column.add_child(bar)
	var rule := ColorRect.new()
	rule.color = Color(UiTheme.ACCENT, 0.35)
	rule.custom_minimum_size = Vector2(0, 2)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(rule)

	# The home screen: the clock, three live readouts and the apps.
	_home = VBoxContainer.new()
	_home.name = "Home"
	_home.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_home.add_theme_constant_override("separation", 10)
	column.add_child(_home)
	var clock_row := HBoxContainer.new()
	clock_row.add_theme_constant_override("separation", 12)
	_clock = _label("", 40, UiTheme.INK)
	_clock.autowrap_mode = TextServer.AUTOWRAP_OFF
	clock_row.add_child(_clock)
	var clock_side := VBoxContainer.new()
	clock_side.alignment = BoxContainer.ALIGNMENT_CENTER
	clock_side.add_theme_constant_override("separation", -4)
	clock_side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var brand := _label("ARES // LINK", 11, UiTheme.ACCENT)
	brand.autowrap_mode = TextServer.AUTOWRAP_OFF
	clock_side.add_child(brand)
	_home_note = _label("", 12, DIM_INK)
	_home_note.autowrap_mode = TextServer.AUTOWRAP_OFF
	_home_note.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	clock_side.add_child(_home_note)
	clock_row.add_child(clock_side)
	_home.add_child(clock_row)

	var readouts := HBoxContainer.new()
	readouts.add_theme_constant_override("separation", 8)
	_home.add_child(readouts)
	for spec: Array in [["link", "LINK", "contacts"], ["inbox", "INBOX", "messages"]]:
		var widget := Readout.new(spec[1])
		widget.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		widget.tapped.connect(open_app.bind(spec[2]))
		readouts.add_child(widget)
		_readouts[spec[0]] = widget
	var latest := Readout.new("LATEST")
	latest.tapped.connect(open_app.bind("news"))
	_home.add_child(latest)
	_readouts["news"] = latest

	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_home.add_child(grid)
	for app_name: String in APPS:
		var icon := AppIcon.new()
		icon.app = app_name
		icon.title = NAV_NAMES[app_name]
		icon.tapped.connect(open_app.bind(app_name))
		grid.add_child(icon)
		_icons[app_name] = icon

	# An app's page: its name, then what it shows.
	_page = VBoxContainer.new()
	_page.name = "Page"
	_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_page.add_theme_constant_override("separation", 8)
	column.add_child(_page)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	var back := Button.new()
	back.text = "<"
	back.flat = true
	back.focus_mode = Control.FOCUS_NONE
	back.custom_minimum_size = Vector2(44, 44)
	back.add_theme_font_size_override("font_size", 30)
	back.add_theme_color_override("font_color", UiTheme.ACCENT)
	back.pressed.connect(go_back)
	head.add_child(back)
	_title = _label("", 20, UiTheme.ACCENT)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.uppercase = true
	head.add_child(_title)
	_page.add_child(head)
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 4)
	_page.add_child(_tabs)
	_error = _label("", 12, Color(1.0, 0.55, 0.45))
	_page.add_child(_error)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_page.add_child(_scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 10)
	_scroll.add_child(_body)

	# The chin's hardware buttons: back, and home from anywhere.
	var keys := HBoxContainer.new()
	keys.add_theme_constant_override("separation", 40)
	keys.anchor_left = 0.5
	keys.anchor_right = 0.5
	keys.anchor_top = 1.0
	keys.anchor_bottom = 1.0
	keys.offset_left = -80
	keys.offset_right = 80
	keys.offset_top = -glass_inset.w + 24
	keys.offset_bottom = -glass_inset.w + 72
	keys.alignment = BoxContainer.ALIGNMENT_CENTER
	chassis.add_child(keys)
	for kind: String in ["back", "home"]:
		var key := ChinKey.new()
		key.kind = kind
		key.tapped.connect(go_back if kind == "back" else go_home)
		keys.add_child(key)


## The screen's look: dark panels with a thin accent edge, chamfered
## switches and sliders in the accent, and text at `scale` times the size
## asked for, so the device reads held small.
static func screen_theme(scale: float) -> Theme:
	var theme := Theme.new()
	theme.default_font_size = roundi(15 * scale)
	theme.set_constant("outline_size", "Label", 0)
	theme.set_constant("shadow_offset_y", "Label", 0)
	theme.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0))
	for type: String in ["Button", "OptionButton"]:
		theme.set_stylebox("normal", type, _flat_box(PANEL_BG, Color(UiTheme.ACCENT, 0.35), 2, 8))
		theme.set_stylebox("hover", type, _flat_box(Color(0.14, 0.1, 0.06), UiTheme.ACCENT, 2, 8))
		theme.set_stylebox("pressed", type, _flat_box(Color(0.3, 0.17, 0.05), UiTheme.ACCENT, 2, 8))
		theme.set_stylebox("focus", type, StyleBoxEmpty.new())
		theme.set_color("font_color", type, UiTheme.INK)
		theme.set_color("font_hover_color", type, UiTheme.ACCENT.lightened(0.3))
		theme.set_color("font_focus_color", type, UiTheme.INK)
		theme.set_color("font_pressed_color", type, Color.WHITE)
	for type: String in ["CheckButton"]:
		var row := _flat_box(PANEL_BG, Color(1, 1, 1, 0.06), 1, 10)
		theme.set_stylebox("normal", type, row)
		theme.set_stylebox("pressed", type, row)
		theme.set_stylebox("hover", type, _flat_box(Color(0.1, 0.09, 0.08), Color(UiTheme.ACCENT, 0.5), 1, 10))
		theme.set_stylebox("hover_pressed", type, _flat_box(Color(0.1, 0.09, 0.08), Color(UiTheme.ACCENT, 0.5), 1, 10))
		theme.set_stylebox("focus", type, StyleBoxEmpty.new())
		theme.set_color("font_color", type, UiTheme.INK)
		theme.set_color("font_hover_color", type, UiTheme.INK)
		theme.set_color("font_pressed_color", type, UiTheme.INK)
		theme.set_color("font_hover_pressed_color", type, UiTheme.INK)
		theme.set_color("font_focus_color", type, UiTheme.INK)
		theme.set_icon("checked", type, switch_icon(true))
		theme.set_icon("unchecked", type, switch_icon(false))
	var track := _flat_box(Color(1, 1, 1, 0.12), Color(0, 0, 0, 0), 0, 0)
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	theme.set_stylebox("slider", "HSlider", track)
	var filled := _flat_box(Color(UiTheme.ACCENT, 0.85), Color(0, 0, 0, 0), 0, 0)
	theme.set_stylebox("grabber_area", "HSlider", filled)
	theme.set_stylebox("grabber_area_highlight", "HSlider", filled)
	theme.set_icon("grabber", "HSlider", grabber_icon(false))
	theme.set_icon("grabber_highlight", "HSlider", grabber_icon(true))
	var lane := _flat_box(Color(1, 1, 1, 0.04), Color(0, 0, 0, 0), 0, 0)
	lane.content_margin_left = 3
	lane.content_margin_right = 3
	theme.set_stylebox("scroll", "VScrollBar", lane)
	for state: String in ["grabber", "grabber_highlight", "grabber_pressed"]:
		theme.set_stylebox(state, "VScrollBar", _flat_box(Color(UiTheme.ACCENT, 0.55 if state == "grabber" else 0.9), Color(0, 0, 0, 0), 0, 0))
	theme.set_stylebox("normal", "LineEdit", _flat_box(Color(0.02, 0.025, 0.03), Color(UiTheme.ACCENT, 0.35), 2, 8))
	theme.set_stylebox("focus", "LineEdit", _flat_box(Color(0, 0, 0, 0), UiTheme.ACCENT, 2, 8))
	theme.set_stylebox("panel", "PanelContainer", _flat_box(PANEL_BG, Color(1, 1, 1, 0.07), 1, 10))
	theme.set_stylebox("panel", "PopupMenu", _flat_box(Color(0.04, 0.045, 0.05), Color(UiTheme.ACCENT, 0.6), 2, 6))
	theme.set_stylebox("hover", "PopupMenu", _flat_box(Color(0.3, 0.17, 0.05), Color(0, 0, 0, 0), 0, 4))
	theme.set_color("font_color", "PopupMenu", UiTheme.INK)
	theme.set_font_size("font_size", "PopupMenu", roundi(14 * scale))
	return theme


## A panel with square corners cut by `cut` pixels at the top left and the
## bottom right, the device's chamfered look, and a `width` edge.
static func _flat_box(fill_color: Color, edge: Color, width: int, pad: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill_color
	box.border_color = edge
	box.set_border_width_all(width)
	box.corner_radius_top_left = 8
	box.corner_radius_bottom_right = 8
	box.corner_radius_top_right = 2
	box.corner_radius_bottom_left = 2
	box.corner_detail = 1
	box.anti_aliasing_size = 1.0
	box.set_content_margin_all(pad)
	return box


## The switch on a toggle row: a square-cut slot, its block to the right and
## lit in the accent when on.
static func switch_icon(on: bool) -> ImageTexture:
	var w := 64
	var h := 32
	var image := Image.create(w, h, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var edge := UiTheme.ACCENT if on else Color(0.45, 0.45, 0.45)
	image.fill_rect(Rect2i(0, 0, w, h), edge)
	image.fill_rect(Rect2i(2, 2, w - 4, h - 4), Color(0.25, 0.14, 0.04) if on else Color(0.05, 0.055, 0.06))
	var block := Rect2i(w - 28, 5, 23, h - 10) if on else Rect2i(5, 5, 23, h - 10)
	image.fill_rect(block, UiTheme.ACCENT if on else Color(0.4, 0.4, 0.4))
	for i in 3:
		image.fill_rect(Rect2i(block.position.x + 7 + i * 4, block.position.y + 6, 2, block.size.y - 12),
				Color(0, 0, 0, 0.35))
	return ImageTexture.create_from_image(image)


## A slider's handle: an upright bar in the accent with a dark notch.
static func grabber_icon(lit: bool) -> ImageTexture:
	var image := Image.create(16, 30, false, Image.FORMAT_RGBA8)
	image.fill(UiTheme.ACCENT.lightened(0.25) if lit else UiTheme.ACCENT)
	image.fill_rect(Rect2i(7, 6, 2, 18), Color(0, 0, 0, 0.45))
	return ImageTexture.create_from_image(image)


## The screen shown flat, for when there is no hand to hold the device (a
## headless test, or before your character is built).
func _build_flat() -> void:
	_face_mat = Handheld.screen_material(_screen.get_texture())
	_flat = TextureRect.new()
	_flat.name = "Flat"
	_flat.texture = _screen.get_texture()
	_flat.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flat.anchor_left = 1.0
	_flat.anchor_right = 1.0
	_flat.anchor_top = 0.5
	_flat.anchor_bottom = 0.5
	_flat.offset_left = -screen_size.x - 60.0
	_flat.offset_right = -60.0
	_flat.offset_top = -screen_size.y * 0.5
	_flat.offset_bottom = screen_size.y * 0.5
	_flat.visible = false
	add_child(_flat)


## The phone is held by `actor`'s own hand: the same handheld every view
## shows (first person, third person, other players, a mirror), with this
## screen on its face.
func set_holder(actor: Node3D) -> void:
	if holder != null and is_instance_valid(holder) and holder != actor:
		var old := holder.get_node_or_null("Skin")
		if old != null and old.has_method("set_phone_screen"):
			old.set_phone_screen(null)
	holder = actor
	_device = null


## Finds the handheld in the holder's hand and puts this screen on it. With
## none (no world, or the phone still coming up) the screen shows flat while
## the phone is open, so it can always be used.
func _hold(_camera: Camera3D) -> void:
	_device = null
	if holder != null and is_instance_valid(holder) and holder.is_inside_tree():
		var skin := holder.get_node_or_null("Skin")
		if skin != null and skin.has_method("handheld"):
			if skin.phone_screen != _face_mat:
				skin.set_phone_screen(_face_mat)
			# Clicks land on the holo panel, where the screen is read.
			_device = Handheld.holo_of(skin.handheld())
	_flat.visible = is_open and _device == null and not has_hand()


## True when the holder has a hand to hold the device in (a dressed
## character). Then the screen waits for the hand to bring it up rather than
## flashing up flat.
func has_hand() -> bool:
	if holder == null or not is_instance_valid(holder):
		return false
	var skin := holder.get_node_or_null("Skin")
	return skin != null and skin.has_method("handheld") and skin.get("locomotion") != null


## Where a mouse position on the game's screen lands on the phone's screen,
## in its pixels. (-1, -1) when it misses the phone.
func screen_point(mouse: Vector2) -> Vector2:
	var miss := Vector2(-1, -1)
	if _flat.visible:
		var local := mouse - _flat.get_global_rect().position
		var scale := _flat.get_global_rect().size / Vector2(screen_size)
		var at := local / scale
		return at if Rect2(Vector2.ZERO, Vector2(screen_size)).has_point(at) else miss
	var camera := get_viewport().get_camera_3d()
	if camera == null or _device == null or not _device.is_visible_in_tree():
		return miss
	var target := _device
	if camera.cull_mask & _device.layers == 0:
		# A camera that leaves out the holo (first person) clicks on the face.
		target = _device.get_parent() as MeshInstance3D
		if target == null:
			return miss
	var to_local := target.global_transform.affine_inverse()
	var o := to_local * camera.project_ray_origin(mouse)
	var d := to_local.basis * camera.project_ray_normal(mouse)
	var panel := target.mesh as QuadMesh
	var front := 0.0 if panel != null else Handheld.DEPTH * 0.5
	if absf(d.z) < 0.00001:
		return miss
	var t := (front - o.z) / d.z
	if t < 0.0:
		return miss
	var p := o + d * t
	var size := panel.size if panel != null else Handheld.body_size()
	var u := p.x / size.x + 0.5
	var v := 0.5 - p.y / size.y
	if u < 0.0 or u > 1.0 or v < 0.0 or v > 1.0:
		return miss
	return Vector2(u * screen_size.x, v * screen_size.y)


## A rounded slab `size` across and `depth` thick (see `Handheld`).
static func rounded_slab(size: Vector2, depth: float, radius: float, steps := 8) -> ArrayMesh:
	return Handheld.rounded_slab(size, depth, radius, steps)


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
	_notice_label.add_theme_font_size_override("font_size", 16)
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


## The status bar's clock, signal and name, and the home screen's clock.
func _update_status() -> void:
	var time := Time.get_time_dict_from_system()
	var clock := "%02d:%02d" % [time.hour, time.minute]
	_status.text = clock
	_bars.strength = 4 if online() else 0
	_who.text = str(net.account.get("name", "")).left(16) if online() else "Solo"
	_clock.text = clock
	_home_note.text = ("Online as %s" % net.account.get("name", "")) if online() else "Offline, solo"


## The home screen's readings: the link (who is about), the inbox and the
## newest headline.
func _update_readouts() -> void:
	if _readouts.is_empty():
		return
	if online():
		var here := contacts().filter(func(c: Dictionary) -> bool: return c.online and not c.blocked).size()
		_readouts["link"].show_reading("ONLINE", "%d %s here" % [here, "player" if here == 1 else "players"])
		var unread := unread_count()
		_readouts["inbox"].show_reading("%d new" % unread if unread > 0 else "Clear",
				"%d %s" % [invites().size(), "invite" if invites().size() == 1 else "invites"])
	else:
		_readouts["link"].show_reading("SOLO", "No server link")
		_readouts["inbox"].show_reading("Offline", "Join a server")
	var latest := news()
	if latest.is_empty():
		_readouts["news"].show_reading("No news", "")
	else:
		var top: Dictionary = latest[0]
		var fresh := unseen_news()
		_readouts["news"].show_reading(str(top.title), ("%d unread" % fresh) if fresh > 0 else str(top.get("date", "")))


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
		_icons[app_name].badge = badge
	_update_readouts()
	if not is_open or not redraw:
		return
	_update_status()
	var home := app == HOME
	_home.visible = home
	_page.visible = not home
	_title.text = "" if home else APP_NAMES[app]
	_build_tabs()
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
	if not online() and local_messages.is_empty():
		_offline_note()
		return
	if chat_with == "":
		var others := conversations()
		if others.is_empty():
			_body.add_child(_label("No messages yet. Open Contacts and tap Message.", 15, Color(0.75, 0.75, 0.75)))
		if not online():
			_body.add_child(_label("You are offline: other players' messages reach you on a server.",
					13, Color(0.6, 0.6, 0.6)))
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
	var who := _label(info.get("name", local_names.get(chat_with, chat_with)), 19, UiTheme.INK)
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
	if local_names.has(chat_with):
		# Someone who lives on this phone only does not read replies.
		_compose = null
		_scroll.set_deferred("scroll_vertical", 1 << 20)
		return
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


## The tabs under the Settings app's name; none for any other app.
func _build_tabs() -> void:
	for child in _tabs.get_children():
		_tabs.remove_child(child)
		child.queue_free()
	_tabs.visible = app == "settings"
	if app != "settings":
		return
	var tabs := settings_tabs()
	if settings_tab not in tabs:
		settings_tab = tabs[0]
	for tab: String in tabs:
		var button := Button.new()
		button.text = SETTINGS_TAB_NAMES[tab].to_upper()
		button.toggle_mode = true
		button.button_pressed = tab == settings_tab
		button.focus_mode = Control.FOCUS_NONE
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", roundi(13 * text_scale))
		if tab == settings_tab:
			button.add_theme_color_override("font_color", UiTheme.ACCENT)
			button.add_theme_stylebox_override("normal", _flat_box(Color(0.2, 0.12, 0.04), UiTheme.ACCENT, 2, 6))
		button.pressed.connect(open_settings_tab.bind(tab))
		_tabs.add_child(button)


## The Settings tabs on offer here: the dev tab only where dev mode is
## available (DEV MODE).
func settings_tabs() -> Array[String]:
	var out: Array[String] = []
	for tab: String in SETTINGS_TABS:
		if tab != "dev" or DevMode.available():  # DEV MODE
			out.append(tab)
	return out


## Opens the Settings app at one of its tabs.
func open_settings_tab(tab: String) -> void:
	settings_tab = tab
	if app != "settings":
		open_app("settings")
	else:
		# Deferred: the tab that was clicked is freed by the redraw.
		refresh.call_deferred()


## Settings, grouped in tabs: Input (mouse, melee, the key list), View
## (fields of view, camera, names, fullscreen), System (sound, quit) and,
## in a debug run, Dev.
func _draw_settings() -> void:
	match settings_tab:
		"input":
			_slider("Mouse sensitivity", "mouse_sensitivity", GameSettings.SENSITIVITY_RANGE, 0.0001,
					GameSettings.mouse_sensitivity, func(v: float) -> String: return "%.1f" % (v * 1000.0))
			_toggle("Invert mouse up and down", "invert_y", GameSettings.invert_y)
			_body.add_child(_section("MELEE SIDE"))
			var melee := OptionButton.new()
			melee.add_item("Mouse flick")
			melee.add_item("Movement keys")
			melee.select(1 if Profile.melee_control == "move" else 0)
			melee.item_selected.connect(func(index: int) -> void:
				Profile.melee_control = "move" if index == 1 else "mouse"
				Profile.save()
				settings_changed.emit())
			_body.add_child(melee)
			_body.add_child(_button("See what every key does", open_app.bind("controls")))
		"view":
			_slider("Field of view, first person", "field_of_view", GameSettings.FOV_RANGE, 1.0, GameSettings.field_of_view,
					func(v: float) -> String: return "%d" % roundi(v))
			_slider("Field of view, third person", "field_of_view_third", GameSettings.FOV_RANGE, 1.0,
					GameSettings.field_of_view_third, func(v: float) -> String: return "%d" % roundi(v))
			_slider("Camera distance, third person", "camera_distance", GameSettings.CAMERA_DISTANCE_RANGE, 0.1,
					GameSettings.camera_distance, func(v: float) -> String: return "%.1f m" % v)
			_slider("Camera pulled back, first person", "eye_pullback", GameSettings.EYE_PULLBACK_RANGE, 0.01,
					GameSettings.eye_pullback, func(v: float) -> String: return "%d cm" % roundi(v * 100.0))
			_toggle("Names over other players", "show_nameplates", GameSettings.show_nameplates)
			_toggle("Fullscreen", "fullscreen", GameSettings.fullscreen)
		"system":
			_slider("Volume", "master_volume", Vector2(0.0, 1.0), 0.05, GameSettings.master_volume,
					func(v: float) -> String: return "%d%%" % roundi(v * 100.0))
			_body.add_child(_section("NEW PLAYER TOUR"))
			if tour_running:
				_body.add_child(_label("Your handler is walking you through the basics in Messages.", 13, DIM_INK))
				_body.add_child(_button("Skip the tour", _ask_tour.bind("skip")))
			else:
				_body.add_child(_button("Play the tour again", _ask_tour.bind("replay")))
			_body.add_child(_section("GAME"))
			_body.add_child(_button("Quit the game", func() -> void: quit_requested.emit()))
		"dev":
			_draw_dev_mode()  # DEV MODE


## Skip or replay the tour, then redraw (deferred: the button that was
## clicked goes with the redraw).
func _ask_tour(action: String) -> void:
	tour_requested.emit(action)
	refresh.call_deferred()


## A small heading inside an app's page.
func _section(text: String) -> Label:
	return _label(text, 12, UiTheme.ACCENT)


## DEV MODE: the temporary switches for testing. Only in a debug or editor
## run (`DevMode.available`), never in an exported game.
func _draw_dev_mode() -> void:
	if not DevMode.available():
		return
	DevMode.ensure_loaded()
	_body.add_child(_section("TESTING ONLY, NEVER IN A RELEASE"))
	var main := CheckButton.new()
	main.text = "Dev mode: everything unlocked"
	main.button_pressed = DevMode.enabled
	main.toggled.connect(set_dev_mode)
	_body.add_child(main)
	if not DevMode.enabled:
		_body.add_child(_label("Works solo and on a server you host from here. Plays on separate saves, so your real stash is untouched.",
				13, Color(0.75, 0.75, 0.75)))
		return
	for cheat: String in DevMode.CHEATS:
		var box := CheckButton.new()
		box.text = DevMode.CHEAT_NAMES[cheat]
		box.button_pressed = DevMode.cheats.get(cheat, false)
		box.toggled.connect(set_dev_cheat.bind(cheat))
		_body.add_child(box)


## DEV MODE: turns dev mode on or off.
func set_dev_mode(on: bool) -> void:
	DevMode.set_enabled(on)
	dev_mode_changed.emit()
	show_notice("Dev mode on: every item, max scrip, cheats in solo worlds." if DevMode.enabled
			else "Dev mode off: back on your real save.")
	if app == "settings":
		# Redrawn after the click is done: the switch that was clicked goes.
		refresh.call_deferred(true)


## DEV MODE: turns one cheat on or off.
func set_dev_cheat(on: bool, cheat: String) -> void:
	DevMode.set_cheat(cheat, on)
	dev_mode_changed.emit()


## A setting with a range: its name and value over the slider, on a card.
func _slider(text: String, key: String, range_: Vector2, step: float, value: float, shown: Callable) -> void:
	var card := _card()
	var box: VBoxContainer = card.get_child(0)
	var head := HBoxContainer.new()
	var name_label := _label(text, 14, UiTheme.INK)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name_label)
	var value_label := _label(shown.call(value), 14, UiTheme.ACCENT)
	value_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	head.add_child(value_label)
	box.add_child(head)
	var slider := HSlider.new()
	slider.min_value = range_.x
	slider.max_value = range_.y
	slider.step = step
	slider.value = value
	slider.value_changed.connect(func(v: float) -> void:
		value_label.text = shown.call(v)
		change_setting(key, v))
	slider.custom_minimum_size = Vector2(0, 30)
	box.add_child(slider)
	_body.add_child(card)


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
	label.add_theme_font_size_override("font_size", roundi(font_size * text_scale))
	label.add_theme_color_override("font_color", color)
	return label


func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", roundi(14 * text_scale))
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


# ------------------------------------------------------------ home screen ----

## An app on the home screen: a dark chamfered tile with the app's glyph
## drawn in thin accent lines, the name below and a count of anything new in
## an accent tag. Tap it to open the app.
class AppIcon extends Control:
	signal tapped
	var app := ""
	var title := ""
	var badge := 0:
		set(value):
			if value != badge:
				badge = value
				queue_redraw()
	var tile := 78.0
	var _hover := false

	func _init() -> void:
		custom_minimum_size = Vector2(92, 116)
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_entered.connect(_set_hover.bind(true))
		mouse_exited.connect(_set_hover.bind(false))

	func _set_hover(on: bool) -> void:
		_hover = on
		queue_redraw()

	func _gui_input(event: InputEvent) -> void:
		var button := event as InputEventMouseButton
		if button != null and button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
			accept_event()
			tapped.emit()

	func _draw() -> void:
		var box := Rect2(Vector2((size.x - tile) * 0.5, 4.0), Vector2(tile, tile))
		var cut := 14.0
		var outline := PackedVector2Array([box.position + Vector2(cut, 0), Vector2(box.end.x, box.position.y),
				Vector2(box.end.x, box.end.y - cut), box.end - Vector2(cut, 0), Vector2(box.position.x, box.end.y),
				box.position + Vector2(0, cut)])
		draw_colored_polygon(outline, Color(0.1, 0.085, 0.07) if _hover else Color(0.055, 0.06, 0.068))
		var edge := outline.duplicate()
		edge.append(outline[0])
		draw_polyline(edge, Color(UiTheme.ACCENT, 0.9 if _hover else 0.4), 2.0, true)
		# A short lit tick on the top edge, like a status light.
		draw_line(box.position + Vector2(cut + 6, 5), box.position + Vector2(cut + 22, 5), Color(UiTheme.ACCENT, 0.8), 2.0)
		_draw_glyph(box.get_center() + Vector2(0, 2), tile / 70.0)
		var font := get_theme_default_font()
		var text := title.to_upper()
		var font_size := 21
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		draw_string(font, Vector2((size.x - width) * 0.5, box.end.y + 22.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1,
				font_size, UiTheme.INK if _hover else DIM_INK)
		if badge > 0:
			var shown := str(badge) if badge < 100 else "99+"
			var text_w := font.get_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, -1, 19).x
			var tag := Rect2(Vector2(box.end.x - 16.0, box.position.y - 6.0), Vector2(maxf(26.0, text_w + 10.0), 26.0))
			draw_rect(tag, UiTheme.ACCENT)
			draw_rect(tag, SCREEN_BG, false, 2.0)
			draw_string(font, Vector2(tag.get_center().x - text_w * 0.5, tag.position.y + 20.0), shown,
					HORIZONTAL_ALIGNMENT_LEFT, -1, 19, SCREEN_BG)

	## Each app's picture in accent lines, `k` scaling it.
	func _draw_glyph(c: Vector2, k: float) -> void:
		var ink := UiTheme.ACCENT.lightened(0.15) if _hover else UiTheme.ACCENT
		var w := 2.6 * k
		match app:
			"contacts":
				draw_arc(c + Vector2(-6, -8) * k, 7.0 * k, 0.0, TAU, 20, ink, w, true)
				draw_arc(c + Vector2(-6, 16) * k, 14.0 * k, PI * 1.08, PI * 1.92, 16, ink, w, true)
				draw_arc(c + Vector2(11, -5) * k, 5.5 * k, 0.0, TAU, 16, Color(ink, 0.6), w, true)
				draw_arc(c + Vector2(13, 15) * k, 11.0 * k, PI * 1.15, PI * 1.85, 12, Color(ink, 0.6), w, true)
			"messages":
				var b := PackedVector2Array([c + Vector2(-20, -15) * k, c + Vector2(20, -15) * k, c + Vector2(20, 9) * k,
						c + Vector2(-4, 9) * k, c + Vector2(-13, 18) * k, c + Vector2(-13, 9) * k, c + Vector2(-20, 9) * k,
						c + Vector2(-20, -15) * k])
				draw_polyline(b, ink, w, true)
				for i in 3:
					draw_rect(Rect2(c + Vector2(-11 + i * 9, -5) * k, Vector2(4, 4) * k), ink)
			"invites":
				var r := Rect2(c + Vector2(-21, -14) * k, Vector2(42, 28) * k)
				draw_rect(r, ink, false, w)
				draw_polyline(PackedVector2Array([r.position, c + Vector2(0, 3) * k, Vector2(r.end.x, r.position.y)]), ink, w, true)
			"news":
				draw_rect(Rect2(c + Vector2(-16, -20) * k, Vector2(32, 40) * k), ink, false, w)
				draw_rect(Rect2(c + Vector2(-10, -13) * k, Vector2(20, 7) * k), ink)
				for i in 3:
					draw_line(c + Vector2(-10, 0 + i * 6.5) * k, c + Vector2(10 if i % 2 == 0 else 4, 0 + i * 6.5) * k, ink, 2.0 * k)
			"mirror":
				var ring := PackedVector2Array()
				for i in 33:
					var angle := TAU * i / 32.0
					ring.append(c + Vector2(cos(angle) * 14.0, sin(angle) * 20.0) * k)
				draw_polyline(ring, ink, w, true)
				draw_line(c + Vector2(-6, -3) * k, c + Vector2(3, -12) * k, Color(ink, 0.7), 2.0 * k, true)
				draw_line(c + Vector2(-5, 6) * k, c + Vector2(7, -6) * k, Color(ink, 0.45), 2.0 * k, true)
			"controls":
				for row in 2:
					for col in 4:
						draw_rect(Rect2(c + Vector2(-21 + col * 11, -14 + row * 11) * k, Vector2(8, 8) * k), ink, false, 2.0 * k)
				draw_rect(Rect2(c + Vector2(-13, 9) * k, Vector2(26, 7) * k), ink, false, 2.0 * k)
			"settings":
				var gear := PackedVector2Array()
				var teeth := 8
				for i in teeth * 4 + 1:
					var angle := TAU * i / (teeth * 4.0)
					var outer := (i % 4) < 2
					gear.append(c + Vector2.from_angle(angle + PI / (teeth * 4.0)) * (19.0 if outer else 14.0) * k)
				draw_polyline(gear, ink, w * 0.85, true)
				draw_arc(c, 6.0 * k, 0.0, TAU, 16, ink, w, true)


## A live reading on the home screen (the link, the inbox, the latest
## news): a small heading over a line or two. Tap it to open its app.
class Readout extends PanelContainer:
	signal tapped
	var heading: Label
	var value: Label
	var detail: Label

	func _init(title: String) -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", -2)
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(box)
		heading = _line(title, 18, UiTheme.ACCENT)
		value = _line("", 28, UiTheme.INK)
		detail = _line("", 20, DIM_INK)
		for label: Label in [heading, value, detail]:
			box.add_child(label)

	func show_reading(main: String, more: String) -> void:
		value.text = main
		detail.text = more
		detail.visible = more != ""

	func _gui_input(event: InputEvent) -> void:
		var button := event as InputEventMouseButton
		if button != null and button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
			accept_event()
			tapped.emit()

	static func _line(text: String, font_size: int, color: Color) -> Label:
		var label := Label.new()
		label.text = text
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.add_theme_font_size_override("font_size", font_size)
		label.add_theme_color_override("font_color", color)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return label


## The status bar's link strength: four stepped bars, lit by `strength`.
## Off the network they all stay dim; nothing flashes.
class SignalBars extends Control:
	var strength := 0:
		set(value):
			if value != strength:
				strength = value
				queue_redraw()

	func _init() -> void:
		custom_minimum_size = Vector2(30, 18)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		for i in 4:
			var h := 5.0 + i * 4.0
			var lit := i < strength
			draw_rect(Rect2(Vector2(i * 7.5, size.y - h), Vector2(5.0, h)),
					UiTheme.ACCENT if lit else Color(1, 1, 1, 0.18))


## The device's frame round the glass: gunmetal with an accent edge, screws
## in the corners, a speaker slot and camera over the glass, and the chin
## under it with the maker's mark. Drawn in the screen's own viewport, so it
## is part of the face.
class Chassis extends Control:
	## Where the glass sits (left, top, right, bottom insets, pixels).
	var glass := Vector4(22, 44, 22, 104)

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var body := StyleBoxFlat.new()
		body.bg_color = CASE_COLOR.lightened(0.08)
		body.border_color = Color(0.05, 0.05, 0.055)
		body.set_border_width_all(4)
		body.set_corner_radius_all(30)
		body.anti_aliasing_size = 1.5
		draw_style_box(body, Rect2(Vector2.ZERO, size))
		# A lighter band down the top and a fine accent line round the glass.
		var shine := StyleBoxFlat.new()
		shine.bg_color = Color(1, 1, 1, 0.035)
		shine.corner_radius_top_left = 28
		shine.corner_radius_top_right = 28
		draw_style_box(shine, Rect2(Vector2(4, 4), Vector2(size.x - 8, glass.y * 0.6)))
		var inner := Rect2(Vector2(glass.x, glass.y), size - Vector2(glass.x + glass.z, glass.y + glass.w))
		var edge := StyleBoxFlat.new()
		edge.bg_color = Color(0, 0, 0, 0)
		edge.border_color = Color(UiTheme.ACCENT, 0.5)
		edge.set_border_width_all(2)
		edge.set_corner_radius_all(16)
		edge.anti_aliasing_size = 1.2
		draw_style_box(edge, inner.grow(4))
		# Screws.
		for at: Vector2 in [Vector2(20, 20), Vector2(size.x - 20, 20), Vector2(20, size.y - 20), Vector2(size.x - 20, size.y - 20)]:
			draw_circle(at, 6.0, Color(0.05, 0.05, 0.055))
			draw_circle(at, 4.5, Color(0.32, 0.32, 0.34))
			draw_line(at + Vector2(-3, -3), at + Vector2(3, 3), Color(0.08, 0.08, 0.08), 1.5)
		# Speaker slot and camera.
		var slot := StyleBoxFlat.new()
		slot.bg_color = Color(0.03, 0.03, 0.035)
		slot.set_corner_radius_all(3)
		draw_style_box(slot, Rect2(Vector2(size.x * 0.5 - 40, glass.y * 0.36), Vector2(80, 6)))
		draw_circle(Vector2(size.x * 0.5 + 64, glass.y * 0.36 + 3), 5.0, Color(0.03, 0.03, 0.035))
		draw_circle(Vector2(size.x * 0.5 + 64, glass.y * 0.36 + 3), 2.0, Color(0.2, 0.35, 0.5))
		# The chin: the maker's mark and a vent either side of the keys.
		var font := get_theme_default_font()
		var chin := size.y - glass.w
		var mark := "ARES  //  LINK-7"
		var mark_w := font.get_string_size(mark, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		draw_string(font, Vector2((size.x - mark_w) * 0.5, chin + 20.0), mark, HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
				Color(0.55, 0.53, 0.5))
		for side: float in [-1.0, 1.0]:
			for i in 4:
				var x := size.x * 0.5 + side * (120.0 + i * 10.0)
				draw_line(Vector2(x, chin + 40.0), Vector2(x, chin + 70.0), Color(0.03, 0.03, 0.035), 4.0)
		# A status light on the chin's corner.
		draw_circle(Vector2(size.x - 44, chin + 20.0), 4.0, Color(UiTheme.ACCENT, 0.9))


## The dark glass behind every screen: a deep gradient, a faint grid and
## scan lines, and the maker's emblem low down.
class Backdrop extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var rows := 24
		for i in rows:
			var t := float(i) / rows
			draw_rect(Rect2(Vector2(0, size.y * t), Vector2(size.x, size.y / rows + 1.0)),
					SCREEN_BG.lerp(Color(0.012, 0.016, 0.02), t))
		var step := 28.0
		var line := Color(UiTheme.ACCENT, 0.045)
		var x := step
		while x < size.x:
			draw_line(Vector2(x, 0), Vector2(x, size.y), line, 1.0)
			x += step
		var y := step
		while y < size.y:
			draw_line(Vector2(0, y), Vector2(size.x, y), line, 1.0)
			y += step
		y = 0.0
		while y < size.y:
			draw_line(Vector2(0, y), Vector2(size.x, y), Color(0, 0, 0, 0.18), 1.0)
			y += 3.0
		# The emblem: a hexagon round a chevron.
		var c := Vector2(size.x * 0.5, size.y * 0.82)
		var hex := PackedVector2Array()
		for i in 7:
			hex.append(c + Vector2.from_angle(PI / 6.0 + TAU * i / 6.0) * 70.0)
		draw_polyline(hex, Color(UiTheme.ACCENT, 0.07), 3.0, true)
		draw_polyline(PackedVector2Array([c + Vector2(-30, 26), c + Vector2(0, -30), c + Vector2(30, 26)]),
				Color(UiTheme.ACCENT, 0.08), 6.0, true)
		draw_line(c + Vector2(-14, 6), c + Vector2(14, 6), Color(UiTheme.ACCENT, 0.08), 5.0)


## A hardware key on the device's chin: back (a chevron) or home (a ring).
class ChinKey extends Control:
	signal tapped
	var kind := "home"
	var _hover := false

	func _init() -> void:
		custom_minimum_size = Vector2(52, 44)
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_entered.connect(_set_hover.bind(true))
		mouse_exited.connect(_set_hover.bind(false))

	func _set_hover(on: bool) -> void:
		_hover = on
		queue_redraw()

	func _gui_input(event: InputEvent) -> void:
		var button := event as InputEventMouseButton
		if button != null and button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
			accept_event()
			tapped.emit()

	func _draw() -> void:
		var c := size * 0.5
		var cap := StyleBoxFlat.new()
		cap.bg_color = Color(0.09, 0.09, 0.1) if not _hover else Color(0.16, 0.12, 0.08)
		cap.border_color = Color(0.03, 0.03, 0.035)
		cap.set_border_width_all(2)
		cap.set_corner_radius_all(8)
		draw_style_box(cap, Rect2(Vector2.ZERO, size))
		var ink := UiTheme.ACCENT if _hover else Color(0.6, 0.58, 0.55)
		if kind == "back":
			draw_polyline(PackedVector2Array([c + Vector2(5, -9), c + Vector2(-5, 0), c + Vector2(5, 9)]), ink, 3.0, true)
		else:
			draw_arc(c, 9.0, 0.0, TAU, 20, ink, 3.0, true)
