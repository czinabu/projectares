extends CanvasLayer
## What the arena shows you, in the arena itself. The big board over the pit
## (the venue's "arena_board" faces) shows who is fighting with their health
## and the wager pools. A bookmaker's booth in the stands ("arena_booth") is
## where you bet, challenge, practice, enter tournaments and leave: stand at
## one and press F, and its screen comes up with the view moved in to it.
## Only the booth's prompt is drawn over the screen.
##
## It only reads the board (`Arena.view_board`) and sends requests through
## `Arena.ask`, so it works the same solo and online. Nothing here decides
## anything.
##
## Load with `const ArenaHud := preload("res://core/arena/arena_hud.gd")`.

## The player pressed "Leave the arena".
signal leave_requested
## A booth's screen was taken up (true) or put down (false). `Main` stops the
## character and frees the mouse meanwhile.
signal booth_changed(open: bool)

const RED := Color(0.95, 0.35, 0.3)
const BLUE := Color(0.4, 0.6, 1.0)
const GOLD := Color(1.0, 0.62, 0.22)
const BET_AMOUNTS := [10, 50, 100]
const STAKES := [0, 50, 200]
const ArenaVenue := preload("res://core/arena/arena_venue.gd")

var arena: Arena
## The 2D picture on the big board, and the one on a booth's screen.
var board_view: SubViewport
var booth_view: SubViewport
## The booth screen in use, else null.
var booth_screen: WorldScreen
var booth_open := false

var _banner: Label
var _bars: Array[ProgressBar] = []
var _pools: Label
var _panel: VBoxContainer
var _prompt: Label
var _shown := ""
var _refresh_left := 0.0
var _stake_index := 0
var _board_mounted := false


## A booth's screen: Esc puts it down.
class BoothScreen:
	extends Control

	signal escaped

	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			escaped.emit()


func setup(p_arena: Arena) -> void:
	arena = p_arena


func _ready() -> void:
	layer = 5
	# Over the screen: only the booth's prompt.
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_prompt = _label(root, "", 22, GOLD)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place(_prompt, 0.5, 0.5, Vector2(-400, 110), Vector2(800, 32))

	# The big board.
	board_view = _screen_viewport("BoardView")
	var board := _glass(board_view)
	var lines := VBoxContainer.new()
	lines.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lines.alignment = BoxContainer.ALIGNMENT_CENTER
	lines.add_theme_constant_override("separation", 24)
	board.add_child(lines)
	_banner = _label(lines, "", 104, GOLD)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var bars := HBoxContainer.new()
	bars.alignment = BoxContainer.ALIGNMENT_CENTER
	bars.add_theme_constant_override("separation", 60)
	lines.add_child(bars)
	for side in 2:
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(540, 70)
		var fill := StyleBoxFlat.new()
		fill.bg_color = RED if side == 0 else BLUE
		bar.add_theme_stylebox_override("fill", fill)
		bar.modulate.a = 0.0
		bars.add_child(bar)
		_bars.append(bar)
	_pools = _label(lines, "", 54, Color(0.85, 0.85, 0.85))
	_pools.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# A bookmaker's booth.
	# Smaller than the board's picture, so its text reads large on the screen.
	booth_view = _screen_viewport("BoothView", Vector2i(960, 540))
	var booth := BoothScreen.new()
	booth.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	booth.escaped.connect(close_booth)
	booth_view.add_child(booth)
	_glass(booth)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 150)
	for side: String in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	booth.add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	_panel = VBoxContainer.new()
	_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_panel.add_theme_constant_override("separation", 6)
	scroll.add_child(_panel)


func _screen_viewport(view_name: String, pixels := Vector2i(1280, 720)) -> SubViewport:
	var view := SubViewport.new()
	view.name = view_name
	view.size = pixels
	view.disable_3d = true
	add_child(view)
	return view


## A screen's dark glass, filling `parent`.
func _glass(parent: Node) -> Control:
	var glass := ColorRect.new()
	glass.color = Color(0.025, 0.03, 0.035)
	glass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glass.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(glass)
	return glass


## Puts the board's picture on every face of the big board.
func _mount_board() -> void:
	if _board_mounted or arena.map == null:
		return
	_board_mounted = true
	for face in get_tree().get_nodes_in_group("arena_board"):
		if not arena.map.is_ancestor_of(face):
			continue
		var screen := WorldScreen.new()
		screen.size = ArenaVenue.BOARD_SIZE
		screen.viewport = board_view
		screen.glow = 1.0
		face.add_child(screen)


## The booth `at` is close enough to use, or null.
static func booth_at(p_arena: Raid, at: Vector3) -> Node3D:
	if p_arena == null or p_arena.map == null:
		return null
	var best: Node3D = null
	var best_distance := ArenaVenue.BOOTH_REACH
	for node in p_arena.get_tree().get_nodes_in_group("arena_booth"):
		var booth := node as Node3D
		if booth == null or not p_arena.map.is_ancestor_of(booth):
			continue
		var gap := booth.global_position - at
		if absf(gap.y) > 1.5:
			continue
		gap.y = 0.0
		if gap.length() <= best_distance:
			best = booth
			best_distance = gap.length()
	return best


## Takes up a booth's screen: the view moves in to it and the mouse works it.
func open_booth(booth: Node3D) -> void:
	var mount := booth.get_node_or_null("Screen") as Node3D if booth else null
	if booth_open or mount == null:
		return
	booth_screen = WorldScreen.new()
	booth_screen.name = "LiveScreen"
	booth_screen.viewport = booth_view
	mount.add_child(booth_screen)
	booth_screen.focus()
	booth_open = true
	_prompt.text = ""
	booth_changed.emit(true)


## Puts the booth's screen down and gives the view back.
func close_booth() -> void:
	if not booth_open:
		return
	booth_open = false
	if booth_screen != null and is_instance_valid(booth_screen):
		booth_screen.unfocus()
		booth_screen.queue_free()
	booth_screen = null
	booth_changed.emit(false)


func _process(delta: float) -> void:
	if arena == null or not is_instance_valid(arena):
		return
	_mount_board()
	var b := arena.view_board()
	_show_bout(b)
	_offer_booth()
	_refresh_left -= delta
	if _refresh_left > 0.0:
		return
	_refresh_left = 0.25
	# Only rebuild the buttons when something on them changed.
	var key := b.duplicate(true)
	key.erase("phase_left")
	if key.has("tournament") and not key.tournament.is_empty():
		key.tournament.erase("starts_in")
	var text := JSON.stringify(key) + str(_stake_index)
	if text != _shown:
		_shown = text
		_rebuild(b)


## The prompt for a booth you are standing at, and F to use it.
func _offer_booth() -> void:
	var me := arena.player
	if booth_open or me == null or not is_instance_valid(me):
		_prompt.text = ""
		return
	var booth := booth_at(arena, me.global_position)
	_prompt.text = "[F]  %s" % booth.get_meta("label", "Bookmaker") if booth else ""
	if booth != null and Input.is_action_just_pressed("interact"):
		open_booth(booth)


func _show_bout(b: Dictionary) -> void:
	var bout: Dictionary = b.get("bout", {})
	var phase: String = b.get("phase", "idle")
	var left := int(ceil(float(b.get("phase_left", 0.0))))
	if bout.is_empty():
		_banner.text = "THE PIT\n" + (str(b.get("last_result", "")) if str(b.get("last_result", "")) != "" \
				else "Waiting for the next bout")
		_pools.text = ""
		for bar in _bars:
			bar.modulate.a = 0.0
		return
	var names: Array = bout.get("names", ["", ""])
	var title := "%s  vs  %s" % [names[0], names[1]]
	if str(bout.get("round", "")) != "":
		title = "%s: %s" % [bout.round, title]
	var status := ""
	match phase:
		"calling":
			status = "Bets close in %d" % left
		"countdown":
			status = "Fight in %d" % left
		"fight":
			status = "%d:%02d" % [left / 60, left % 60]
		"result":
			status = str(b.get("last_result", ""))
	_banner.text = "%s\n%s" % [title, status]
	var pools: Array = bout.get("pools", [0, 0])
	var stake := int(bout.get("stake", 0))
	_pools.text = "Red pool %d   |   Blue pool %d%s" % [pools[0], pools[1],
			"   |   Purse %d" % stake if stake > 0 else ""]
	var nodes: Array = bout.get("nodes", ["", ""])
	for side in 2:
		var fighter := arena.get_node_or_null(NodePath(str(nodes[side]))) as Actor if str(nodes[side]) != "" else null
		_bars[side].modulate.a = 1.0 if fighter != null else 0.0
		if fighter != null:
			_bars[side].max_value = fighter.health.max_health
			_bars[side].value = fighter.health.health


func _rebuild(b: Dictionary) -> void:
	for child in _panel.get_children():
		child.queue_free()
	var you: Dictionary = b.get("you", {})
	_label(_panel, "BOOKMAKER", 26, GOLD)
	_label(_panel, "Scrip: %d" % int(you.get("scrip", 0)), 18, Color.WHITE)
	_label(_panel, "Nobody loses gear here. Beaten fighters yield.", 15, Color(0.65, 0.65, 0.65))

	var bout: Dictionary = b.get("bout", {})
	if b.get("phase", "") == "calling" and not bout.is_empty() and not you.get("fighting", false):
		_label(_panel, "BET ON THIS BOUT", 15, GOLD)
		if you.has("bet"):
			_label(_panel, "You have %d on %s" % [int(you.bet), "red" if int(you.bet_side) == 0 else "blue"],
					13, Color.WHITE)
		var names: Array = bout.get("names", ["", ""])
		for side in 2:
			if you.has("bet_side") and int(you.bet_side) != side:
				continue
			var row := HBoxContainer.new()
			_panel.add_child(row)
			var who := _label(row, str(names[side]), 13, RED if side == 0 else BLUE)
			who.custom_minimum_size = Vector2(110, 0)
			who.clip_text = true
			for amount: int in BET_AMOUNTS:
				_button(row, str(amount), func() -> void: arena.ask("bet", {"side": side, "amount": amount}))

	var challenges: Array = b.get("challenges", [])
	if not challenges.is_empty():
		_label(_panel, "CHALLENGES", 15, GOLD)
		for c: Dictionary in challenges:
			var stake := " for %d" % int(c.stake) if int(c.stake) > 0 else ""
			if c.get("incoming", false):
				_label(_panel, "%s challenges you%s" % [c.from, stake], 13, Color.WHITE)
				var row := HBoxContainer.new()
				_panel.add_child(row)
				var from: String = c.from_node
				_button(row, "Accept", func() -> void: arena.ask("accept", {"from": from}))
				_button(row, "Decline", func() -> void: arena.ask("decline", {"from": from}))
			else:
				_label(_panel, "You challenged %s%s" % [c.to, stake], 13, Color(0.75, 0.75, 0.75))

	if not you.get("busy", false):
		_label(_panel, "FIGHT", 15, GOLD)
		_button(_panel, "Practice against a gladiator", func() -> void: arena.ask("practice"))
		var others: Array = b.get("players", [])
		if not others.is_empty():
			_button(_panel, "Duel stake: %d (change)" % STAKES[_stake_index], func() -> void:
				_stake_index = (_stake_index + 1) % STAKES.size())
			for p: Dictionary in others:
				if p.get("busy", false):
					continue
				var node: String = p.node
				_button(_panel, "Challenge %s" % p.name, func() -> void:
					arena.ask("challenge", {"to": node, "stake": STAKES[_stake_index]}))

	var t: Dictionary = b.get("tournament", {})
	_label(_panel, "TOURNAMENT", 15, GOLD)
	if t.is_empty():
		_button(_panel, "Start a tournament (entry %d)" % int(b.get("fee", 0)), func() -> void:
			arena.ask("join_tournament"))
	else:
		var entrants: Array = t.get("entrants", [])
		if t.get("running", false):
			_label(_panel, "Under way, pot %d. %s" % [int(t.pot), ", ".join(entrants)], 13, Color.WHITE)
		else:
			_label(_panel, "Starts in %ds, pot %d: %s" % [int(t.starts_in), int(t.pot), ", ".join(entrants)],
					13, Color.WHITE)
			if you.get("entered", false):
				_button(_panel, "Drop out (refund)", func() -> void: arena.ask("leave_tournament"))
			else:
				_button(_panel, "Join (entry %d)" % int(b.get("fee", 0)), func() -> void: arena.ask("join_tournament"))

	var queue: Array = b.get("queue", [])
	if not queue.is_empty():
		_label(_panel, "UP NEXT", 15, GOLD)
		for line: String in queue.slice(0, 5):
			_label(_panel, line, 12, Color(0.8, 0.8, 0.8))

	_button(_panel, "Leave the arena", func() -> void: leave_requested.emit())
	_button(_panel, "Step away  (Esc)", close_booth)


func _button(parent: Control, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func _label(parent: Control, text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("outline_size", 4)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


func _place(control: Control, ax: float, ay: float, offset: Vector2, size: Vector2) -> void:
	control.anchor_left = ax
	control.anchor_right = ax
	control.anchor_top = ay
	control.anchor_bottom = ay
	control.offset_left = offset.x
	control.offset_top = offset.y
	control.offset_right = offset.x + size.x
	control.offset_bottom = offset.y + size.y
