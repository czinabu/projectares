extends CanvasLayer
## The phone every player carries. It is the game's menu: open it with P in
## the hub or in a raid to reach other players, answer invites, read the
## news, try on clothes in front of a mirror, look up the controls and change
## settings.
##
## It is a real phone in the world, not a panel over the screen: the
## character raises it (others see them looking at it, `ActorCommand.phone`),
## it is held up in front of the view at a slight angle with the scene dimmed
## behind it, and you click on its screen. The screen is a `SubViewport`
## showing a home screen of app icons with badges and a status bar; an app
## opens over it and the back arrow or the bar at the bottom goes home.
## With no 3D camera (a headless test) the same screen shows flat.
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

const SocialService := preload("res://core/social/social_service.gd")
const GameSettings := preload("res://core/settings/game_settings.gd")
const DevMode := preload("res://core/dev/dev_mode.gd")  # DEV MODE
const UiTheme := preload("res://core/visual/ui_theme.gd")
const CharacterPanel := preload("res://core/ui/character_panel.gd")

const MirrorScript := preload("res://core/visual/mirror.gd")

const APPS := ["contacts", "messages", "invites", "news", "mirror", "controls", "settings"]
const APP_NAMES := {"contacts": "Contacts", "messages": "Messages", "invites": "Invites",
		"news": "News", "mirror": "Mirror", "controls": "Controls", "settings": "Settings"}
## The names under the home screen's icons.
const NAV_NAMES := {"contacts": "People", "messages": "Chat", "invites": "Invites",
		"news": "News", "mirror": "Mirror", "controls": "Keys", "settings": "Settings"}
## Each app icon's colour.
const APP_TINTS := {"contacts": Color(0.22, 0.68, 0.45), "messages": Color(0.24, 0.52, 0.95),
		"invites": Color(0.95, 0.58, 0.2), "news": Color(0.88, 0.3, 0.3), "mirror": Color(0.58, 0.4, 0.9),
		"controls": Color(0.18, 0.66, 0.72), "settings": Color(0.42, 0.44, 0.48)}
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
		["Light the jets and hover", "Tap {jump} in the air"],
		["Cruise while hovering", "{move_forward} {move_left} {move_back} {move_right}"],
		["Coast down with the jets idle to cool", "Hold {slide}"],
		["Boost head first (Mk2)", "Hold {sprint} + {move_forward}"],
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
		["Open the phone at Settings, or close it; step back from a console", "Esc"],
		["Mirror app: choose, then scroll", "Arrows or W A S D"],
	]],
]

## The screen's pixels, bezel included (the phone is about 1:2).
var screen_size := Vector2i(440, 900)
## The phone's height in the world, metres. Held this size, it is a little
## further from the eyes than a real one, which keeps it clear of the near
## plane; it is drawn over the world anyway, so it never pokes into a wall.
var device_height := 0.32
var device_depth := 0.022
var corner_radius := 0.026
## How much of the view's height the phone fills when held up.
var fill := 0.74
## Where it is held, in the view (-1 to 1 across and up). Further right while
## the Mirror app is up, so the mirror is in view.
var hold_at := Vector2(0.4, 0.0)
var hold_at_mirror := Vector2(0.62, 0.0)
## Turned in toward the middle of the view, tipped away at the top, and
## rolled, in radians.
var hold_turn := 0.1
var hold_tilt := 0.08
var hold_roll := -0.035
## Seconds to raise it or put it away.
var raise_time := 0.22
## How dark the scene goes behind the phone.
var dim_alpha := 0.38
## The soft light the screen throws around the phone.
var glow_alpha := 0.4
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
## In the world: the phone, its glow and the shade over the scene.
var _device: MeshInstance3D
var _glow: MeshInstance3D
var _dim: MeshInstance3D
var _dim_mat: StandardMaterial3D
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
	_build_device()
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
	_raise = move_toward(_raise, 1.0 if is_open else 0.0, delta / maxf(raise_time, 0.001))
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
	_dim_mat.albedo_color.a = 0.0 if up else dim_alpha
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


## How dark the scene is behind the phone right now (none in front of a mirror).
func dim_amount() -> float:
	return _dim_mat.albedo_color.a if is_open else 0.0


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

## The screen: a 2D viewport with the bezel, the status bar, the home
## screen and the page an app draws on.
func _build_screen() -> void:
	_screen = SubViewport.new()
	_screen.name = "Screen"
	_screen.size = screen_size
	_screen.disable_3d = true
	_screen.transparent_bg = true
	_screen.gui_embed_subwindows = true
	_screen.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	add_child(_screen)

	var bezel := Panel.new()
	bezel.name = "Bezel"
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color(0.02, 0.02, 0.025)
	frame.border_color = Color(0.2, 0.19, 0.18)
	frame.set_border_width_all(3)
	frame.set_corner_radius_all(int(screen_size.x * corner_radius / (device_height * screen_size.x / screen_size.y)))
	frame.anti_aliasing_size = 1.5
	bezel.add_theme_stylebox_override("panel", frame)
	bezel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_screen.add_child(bezel)

	# The glass: a lit wallpaper inside the bezel, with everything clipped to
	# its rounded corners.
	var glass := Panel.new()
	glass.name = "Glass"
	var lit := StyleBoxFlat.new()
	lit.bg_color = Color(0.055, 0.06, 0.075)
	lit.set_corner_radius_all(maxi(frame.corner_radius_top_left - 12, 8))
	lit.anti_aliasing_size = 1.5
	glass.add_theme_stylebox_override("panel", lit)
	glass.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	glass.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: Side in [SIDE_LEFT, SIDE_TOP]:
		glass.set_offset(side, 12.0)
	for side: Side in [SIDE_RIGHT, SIDE_BOTTOM]:
		glass.set_offset(side, -12.0)
	bezel.add_child(glass)
	var wallpaper := TextureRect.new()
	var shade := GradientTexture2D.new()
	shade.gradient = Gradient.new()
	shade.gradient.set_color(0, Color(0.46, 0.26, 0.14))
	shade.gradient.set_color(1, Color(0.1, 0.13, 0.26))
	shade.fill_from = Vector2(0.2, 0.0)
	shade.fill_to = Vector2(0.7, 1.0)
	wallpaper.texture = shade
	wallpaper.stretch_mode = TextureRect.STRETCH_SCALE
	wallpaper.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	wallpaper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wallpaper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glass.add_child(wallpaper)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 8)
	glass.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	margin.add_child(column)

	# Status bar: the time, the signal and who you are signed in as.
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	# Clear of the rounded corners.
	var inset := Control.new()
	inset.custom_minimum_size = Vector2(26, 0)
	bar.add_child(inset)
	_status = _label("", 15, UiTheme.INK)
	_status.autowrap_mode = TextServer.AUTOWRAP_OFF
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(_status)
	_bars = SignalBars.new()
	_bars.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_child(_bars)
	_who = _label("", 15, Color(0.78, 0.78, 0.78))
	_who.autowrap_mode = TextServer.AUTOWRAP_OFF
	_who.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_who.custom_minimum_size = Vector2(0, 0)
	bar.add_child(_who)
	bar.add_child(inset.duplicate())
	column.add_child(bar)

	# The home screen: a clock and the app icons.
	_home = VBoxContainer.new()
	_home.name = "Home"
	_home.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_home.add_theme_constant_override("separation", 0)
	column.add_child(_home)
	var top_gap := Control.new()
	top_gap.custom_minimum_size = Vector2(0, 30)
	_home.add_child(top_gap)
	_clock = _label("", 72, UiTheme.INK)
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_home.add_child(_clock)
	_home_note = _label("", 16, Color(0.8, 0.78, 0.74))
	_home_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_home.add_child(_home_note)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 46)
	_home.add_child(gap)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 18)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_home.add_child(grid)
	for app_name: String in APPS:
		var icon := AppIcon.new()
		icon.app = app_name
		icon.title = NAV_NAMES[app_name]
		icon.tint = APP_TINTS[app_name]
		icon.tapped.connect(open_app.bind(app_name))
		grid.add_child(icon)
		_icons[app_name] = icon

	# An app's page: a back arrow and its name, then what it shows.
	_page = VBoxContainer.new()
	_page.name = "Page"
	_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_page.add_theme_constant_override("separation", 6)
	column.add_child(_page)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 4)
	var back := Button.new()
	back.text = "<"
	back.flat = true
	back.focus_mode = Control.FOCUS_NONE
	back.custom_minimum_size = Vector2(40, 40)
	back.add_theme_font_size_override("font_size", 26)
	back.add_theme_color_override("font_color", UiTheme.ACCENT)
	back.pressed.connect(go_back)
	head.add_child(back)
	_title = _label("", 28, UiTheme.ACCENT)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	_page.add_child(head)
	_error = _label("", 13, Color(1.0, 0.55, 0.45))
	_page.add_child(_error)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_page.add_child(_scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 8)
	_scroll.add_child(_body)

	# The home bar: tap it to go home from anywhere.
	var home_bar := HomeBar.new()
	home_bar.tapped.connect(go_home)
	column.add_child(home_bar)


## The phone in the world: a rounded slab whose face shows the screen, a soft
## glow behind it, and a shade over the scene. All of it is drawn over the
## world (no depth test), in that order, on `MirrorScript.HELD_LAYER` so a
## mirror never shows it.
func _build_device() -> void:
	var height := device_height
	var width := height * float(screen_size.x) / float(screen_size.y)
	var face := StandardMaterial3D.new()
	face.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	face.albedo_texture = _screen.get_texture()
	face.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	# Lit from within, so it reads in a dark street and the bloom catches it.
	face.emission_enabled = true
	face.emission_texture = _screen.get_texture()
	face.emission_energy_multiplier = 0.6
	var case := StandardMaterial3D.new()
	case.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	case.albedo_color = Color(0.17, 0.165, 0.16)
	# Flat-coloured and drawn over the world, so which side is in front does
	# not matter.
	case.cull_mode = BaseMaterial3D.CULL_DISABLED
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	var halo := GradientTexture2D.new()
	halo.fill = GradientTexture2D.FILL_RADIAL
	halo.fill_from = Vector2(0.5, 0.5)
	halo.fill_to = Vector2(1.0, 0.5)
	halo.gradient = Gradient.new()
	halo.gradient.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	halo.gradient.colors = PackedColorArray([Color(1.0, 0.75, 0.5, glow_alpha),
			Color(1.0, 0.75, 0.5, glow_alpha * 0.8), Color(1.0, 0.75, 0.5, 0.0)])
	glow.albedo_texture = halo
	_dim_mat = StandardMaterial3D.new()
	_dim_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_dim_mat.albedo_color = Color(0.0, 0.0, 0.0, dim_alpha)
	var order := 0
	for mat: StandardMaterial3D in [_dim_mat, glow, case, face]:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.no_depth_test = true
		mat.disable_receive_shadows = true
		mat.render_priority = 100 + order
		order += 1

	_dim = _held_mesh("Dim", QuadMesh.new(), _dim_mat)
	_glow = _held_mesh("Glow", QuadMesh.new(), glow)
	(_glow.mesh as QuadMesh).size = Vector2(width, height) * 2.2
	_device = _held_mesh("Device", rounded_slab(Vector2(width, height), device_depth, corner_radius), null)
	_device.set_surface_override_material(0, face)
	_device.set_surface_override_material(1, case)

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


func _held_mesh(node_name: String, mesh: Mesh, mat: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = mesh
	if mat:
		node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.layers = 1 << (MirrorScript.HELD_LAYER - 1)
	node.visible = false
	add_child(node)
	return node


## Puts the phone where it is held in front of `camera`: raised into place as
## it comes out, lowered as it goes away. With no camera the screen shows flat.
func _hold(camera: Camera3D) -> void:
	var showing := _raise > 0.0
	var in_world := camera != null and is_instance_valid(camera) and camera.is_inside_tree()
	_flat.visible = is_open and not in_world
	for node: MeshInstance3D in [_device, _glow, _dim]:
		node.visible = showing and in_world
	if not showing or not in_world:
		return
	var aspect := 16.0 / 9.0
	var rect := get_viewport().get_visible_rect().size
	if rect.y > 0.0:
		aspect = rect.x / rect.y
	var half_v := tan(deg_to_rad(camera.fov) * 0.5)
	var distance := device_height * 0.5 / (half_v * fill)
	var spot := hold_at_mirror if mirror_open() else hold_at
	var up := ease(_raise, -2.0)
	var lift := (1.0 - up) * 1.7
	var origin := Vector3(spot.x * half_v * aspect * distance, (spot.y - lift) * half_v * distance, -distance)
	# Square to the view, which keeps the screen undistorted, then turned in a
	# little, tipped back at the top and rolled a touch: more on the way up.
	var basis := Basis(Vector3.UP, hold_turn * signf(spot.x)) \
			* Basis(Vector3.RIGHT, -hold_tilt - (1.0 - up) * 0.7) * Basis(Vector3.BACK, hold_roll)
	var view := camera.global_transform
	_device.global_transform = view * Transform3D(basis, origin)
	_glow.global_transform = view * Transform3D(basis, origin + basis.z * -0.02)
	(_glow.material_override as StandardMaterial3D).albedo_color.a = up
	var near := maxf(camera.near * 1.5, 0.02)
	(_dim.mesh as QuadMesh).size = Vector2(half_v * aspect, half_v) * near * 2.4
	_dim.global_transform = view * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, -near))
	_dim.transparency = 1.0 - up


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
	if camera == null or not _device.visible:
		return miss
	var to_local := _device.global_transform.affine_inverse()
	var o := to_local * camera.project_ray_origin(mouse)
	var d := to_local.basis * camera.project_ray_normal(mouse)
	var front := device_depth * 0.5
	if absf(d.z) < 0.00001:
		return miss
	var t := (front - o.z) / d.z
	if t < 0.0:
		return miss
	var p := o + d * t
	var size := Vector2(device_height * float(screen_size.x) / float(screen_size.y), device_height)
	var u := p.x / size.x + 0.5
	var v := 0.5 - p.y / size.y
	if u < 0.0 or u > 1.0 or v < 0.0 or v > 1.0:
		return miss
	return Vector2(u * screen_size.x, v * screen_size.y)


## A rounded slab `size` across and `depth` thick, its face toward +Z.
## Surface 0 is the face, mapped 0 to 1 across it; surface 1 the edge and back.
static func rounded_slab(size: Vector2, depth: float, radius: float, steps := 8) -> ArrayMesh:
	var outline: Array[Vector2] = []
	var half := size * 0.5
	var r := minf(radius, minf(half.x, half.y))
	var corners := [Vector2(half.x - r, half.y - r), Vector2(-half.x + r, half.y - r),
			Vector2(-half.x + r, -half.y + r), Vector2(half.x - r, -half.y + r)]
	for c in 4:
		for i in steps + 1:
			var angle := (c + float(i) / steps) * PI * 0.5
			outline.append((corners[c] as Vector2) + Vector2(cos(angle), sin(angle)) * r)
	var front := depth * 0.5
	var mesh := ArrayMesh.new()
	var face := SurfaceTool.new()
	face.begin(Mesh.PRIMITIVE_TRIANGLES)
	face.set_normal(Vector3.BACK)
	for i in outline.size():
		var a := outline[i]
		var b := outline[(i + 1) % outline.size()]
		for point: Vector2 in [Vector2.ZERO, b, a]:
			face.set_uv(Vector2(point.x / size.x + 0.5, 0.5 - point.y / size.y))
			face.add_vertex(Vector3(point.x, point.y, front))
	face.commit(mesh)
	var shell := SurfaceTool.new()
	shell.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in outline.size():
		var a := outline[i]
		var b := outline[(i + 1) % outline.size()]
		var out := Vector3(a.x + b.x, a.y + b.y, 0.0).normalized()
		shell.set_normal(out)
		for point: Vector3 in [Vector3(a.x, a.y, front), Vector3(b.x, b.y, front), Vector3(b.x, b.y, -front),
				Vector3(a.x, a.y, front), Vector3(b.x, b.y, -front), Vector3(a.x, a.y, -front)]:
			shell.add_vertex(point)
		shell.set_normal(Vector3.FORWARD)
		for point: Vector2 in [Vector2.ZERO, a, b]:
			shell.add_vertex(Vector3(point.x, point.y, -front))
	shell.commit(mesh)
	return mesh


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


## The status bar's clock, signal and name, and the home screen's clock.
func _update_status() -> void:
	var time := Time.get_time_dict_from_system()
	var clock := "%02d:%02d" % [time.hour, time.minute]
	_status.text = clock
	_bars.strength = 4 if online() else 0
	_who.text = net.account.get("name", "") if online() else "Solo"
	_clock.text = clock
	_home_note.text = ("Online as %s" % net.account.get("name", "")) if online() else "Offline (solo)"


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
	if not is_open or not redraw:
		return
	_update_status()
	var home := app == HOME
	_home.visible = home
	_page.visible = not home
	_title.text = "" if home else APP_NAMES[app]
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
	_slider("Camera distance (third person)", "camera_distance", GameSettings.CAMERA_DISTANCE_RANGE, 0.1,
			GameSettings.camera_distance, func(v: float) -> String: return "%.1f m" % v)
	_slider("Volume", "master_volume", Vector2(0.0, 1.0), 0.05, GameSettings.master_volume,
			func(v: float) -> String: return "%d%%" % roundi(v * 100.0))
	_toggle("Fullscreen", "fullscreen", GameSettings.fullscreen)
	_toggle("Names over other players", "show_nameplates", GameSettings.show_nameplates)
	_draw_dev_mode()  # DEV MODE
	_body.add_child(_label("GAME", 15, UiTheme.ACCENT))
	_body.add_child(_button("Quit the game", func() -> void: quit_requested.emit()))


## DEV MODE: the temporary switches for testing. Only in a debug or editor
## run (`DevMode.available`), never in an exported game.
func _draw_dev_mode() -> void:
	if not DevMode.available():
		return
	DevMode.ensure_loaded()
	_body.add_child(_label("DEV MODE (TESTING ONLY)", 15, UiTheme.ACCENT))
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
	show_notice("Dev mode on: every item, max credits, cheats in solo worlds." if DevMode.enabled
			else "Dev mode off: back on your real save.")
	if app == "settings":
		# Redrawn after the click is done: the switch that was clicked goes.
		refresh.call_deferred(true)


## DEV MODE: turns one cheat on or off.
func set_dev_cheat(on: bool, cheat: String) -> void:
	DevMode.set_cheat(cheat, on)
	dev_mode_changed.emit()


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


# ------------------------------------------------------------ home screen ----

## An app on the home screen: a rounded tile in the app's colour with a
## glyph drawn on it, the name below and a badge with the count of anything
## new. Tap it to open the app.
class AppIcon extends Control:
	signal tapped
	var app := ""
	var title := ""
	var tint := Color.GRAY
	var badge := 0:
		set(value):
			if value != badge:
				badge = value
				queue_redraw()
	var tile := 70.0
	var _hover := false

	func _init() -> void:
		custom_minimum_size = Vector2(92, 104)
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
		var style := StyleBoxFlat.new()
		style.bg_color = tint.lightened(0.12) if _hover else tint
		style.set_corner_radius_all(18)
		style.anti_aliasing_size = 1.2
		style.shadow_color = Color(0, 0, 0, 0.35)
		style.shadow_size = 6
		style.shadow_offset = Vector2(0, 3)
		draw_style_box(style, box)
		# A lighter top half reads as a lit, slightly curved tile.
		var sheen := StyleBoxFlat.new()
		sheen.bg_color = Color(1, 1, 1, 0.12)
		sheen.corner_radius_top_left = 18
		sheen.corner_radius_top_right = 18
		sheen.anti_aliasing_size = 1.2
		draw_style_box(sheen, Rect2(box.position, Vector2(tile, tile * 0.5)))
		_draw_glyph(box.get_center(), tile / 70.0)
		var font := get_theme_default_font()
		var width := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		var at := Vector2((size.x - width) * 0.5, box.end.y + 20.0)
		draw_string(font, at + Vector2(0, 1.5), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0, 0, 0, 0.6))
		draw_string(font, at, title, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UiTheme.INK)
		if badge > 0:
			var shown := str(badge) if badge < 100 else "99+"
			var text_w := font.get_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
			var pill := Rect2(Vector2(box.end.x - 14.0, box.position.y - 6.0), Vector2(maxf(24.0, text_w + 12.0), 24.0))
			var red := StyleBoxFlat.new()
			red.bg_color = Color(0.92, 0.2, 0.18)
			red.border_color = Color(0.02, 0.02, 0.025)
			red.set_border_width_all(2)
			red.set_corner_radius_all(12)
			red.anti_aliasing_size = 1.2
			draw_style_box(red, pill)
			draw_string(font, Vector2(pill.get_center().x - text_w * 0.5, pill.position.y + 18.0), shown,
					HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)

	## Each app's picture, in white on the tile, `k` scaling it.
	func _draw_glyph(c: Vector2, k: float) -> void:
		var ink := Color(1, 1, 1, 0.95)
		var deep := tint.darkened(0.25)
		match app:
			"contacts":
				_person(c + Vector2(9, -2) * k, 0.8 * k, Color(1, 1, 1, 0.55))
				_person(c + Vector2(-5, 2) * k, k, ink)
			"messages":
				var bubble := StyleBoxFlat.new()
				bubble.bg_color = ink
				bubble.set_corner_radius_all(int(12 * k))
				bubble.anti_aliasing_size = 1.0
				draw_style_box(bubble, Rect2(c + Vector2(-21, -16) * k, Vector2(42, 28) * k))
				draw_colored_polygon(PackedVector2Array([c + Vector2(-12, 10) * k, c + Vector2(-2, 10) * k,
						c + Vector2(-16, 20) * k]), ink)
				for i in 3:
					draw_circle(c + Vector2(-10 + i * 10, -2) * k, 3.2 * k, deep)
			"invites":
				var r := Rect2(c + Vector2(-22, -15) * k, Vector2(44, 30) * k)
				draw_rect(r, ink)
				draw_polyline(PackedVector2Array([r.position, c + Vector2(0, 3) * k, Vector2(r.end.x, r.position.y)]),
						deep, 3.0 * k, true)
			"news":
				draw_rect(Rect2(c + Vector2(-17, -21) * k, Vector2(34, 42) * k), ink)
				draw_rect(Rect2(c + Vector2(-12, -16) * k, Vector2(24, 9) * k), deep)
				for i in 4:
					var w := 24.0 if i % 2 == 0 else 17.0
					draw_rect(Rect2(c + Vector2(-12, -2 + i * 5.5) * k, Vector2(w, 2.4) * k), deep)
			"mirror":
				var ring := PackedVector2Array()
				for i in 33:
					var angle := TAU * i / 32.0
					ring.append(c + Vector2(cos(angle) * 15.0, sin(angle) * 21.0) * k)
				draw_colored_polygon(ring, Color(1, 1, 1, 0.3))
				draw_polyline(ring, ink, 3.5 * k, true)
				draw_line(c + Vector2(-7, -4) * k, c + Vector2(3, -14) * k, ink, 3.0 * k, true)
				draw_line(c + Vector2(-6, 6) * k, c + Vector2(8, -8) * k, Color(1, 1, 1, 0.6), 2.0 * k, true)
			"controls":
				var cap := StyleBoxFlat.new()
				cap.bg_color = ink
				cap.set_corner_radius_all(int(3 * k))
				for row in 2:
					for col in 4:
						draw_style_box(cap, Rect2(c + Vector2(-22 + col * 11.5, -16 + row * 11.5) * k, Vector2(9, 9) * k))
				draw_style_box(cap, Rect2(c + Vector2(-14, 7) * k, Vector2(28, 9) * k))
			"settings":
				var gear := PackedVector2Array()
				var teeth := 8
				for i in teeth * 4:
					var angle := TAU * i / (teeth * 4.0)
					var outer := (i % 4) < 2
					gear.append(c + Vector2.from_angle(angle + PI / (teeth * 4.0)) * (21.0 if outer else 15.5) * k)
				draw_colored_polygon(gear, ink)
				draw_circle(c, 7.0 * k, deep)

	func _person(at: Vector2, k: float, color: Color) -> void:
		draw_circle(at + Vector2(0, -9) * k, 8.0 * k, color)
		var shoulders := PackedVector2Array()
		for i in 17:
			var angle := PI + PI * i / 16.0
			shoulders.append(at + Vector2(0, 19) * k + Vector2(cos(angle), sin(angle)) * Vector2(15, 17) * k)
		draw_colored_polygon(shoulders, color)


## The status bar's signal strength: four bars, lit by `strength`.
class SignalBars extends Control:
	var strength := 0:
		set(value):
			if value != strength:
				strength = value
				queue_redraw()

	func _init() -> void:
		custom_minimum_size = Vector2(22, 14)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		for i in 4:
			var h := 4.0 + i * 3.3
			var lit := i < strength
			draw_rect(Rect2(Vector2(i * 5.5, size.y - h), Vector2(3.5, h)),
					UiTheme.INK if lit else Color(1, 1, 1, 0.22))
		if strength == 0:
			draw_line(Vector2(13, 1), Vector2(21, 9), Color(0.95, 0.4, 0.35), 2.0, true)
			draw_line(Vector2(21, 1), Vector2(13, 9), Color(0.95, 0.4, 0.35), 2.0, true)


## The bar along the bottom of the screen. Tap it to go home.
class HomeBar extends Control:
	signal tapped
	var _hover := false

	func _init() -> void:
		custom_minimum_size = Vector2(0, 22)
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
		var pill := StyleBoxFlat.new()
		pill.bg_color = Color(1, 1, 1, 0.85 if _hover else 0.55)
		pill.set_corner_radius_all(3)
		pill.anti_aliasing_size = 1.0
		var w := 130.0
		draw_style_box(pill, Rect2(Vector2((size.x - w) * 0.5, size.y * 0.5 - 3.0), Vector2(w, 6.0)))
