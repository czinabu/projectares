extends CanvasLayer
## The arena overlay: who is fighting with their health, the wager pools,
## the queue and tournament, and buttons to bet, challenge, practice and
## enter tournaments. Press Esc to free the mouse and click.
##
## It only reads the board (`Arena.view_board`) and sends requests through
## `Arena.ask`, so it works the same solo and online. Nothing here decides
## anything.
##
## Load with `const ArenaHud := preload("res://core/arena/arena_hud.gd")`.

## The player pressed "Leave the arena".
signal leave_requested

const RED := Color(0.95, 0.35, 0.3)
const BLUE := Color(0.4, 0.6, 1.0)
const GOLD := Color(1.0, 0.62, 0.22)
const BET_AMOUNTS := [10, 50, 100]
const STAKES := [0, 50, 200]

var arena: Arena

var _banner: Label
var _bars: Array[ProgressBar] = []
var _pools: Label
var _panel: VBoxContainer
var _shown := ""
var _refresh_left := 0.0
var _stake_index := 0


func setup(p_arena: Arena) -> void:
	arena = p_arena


func _ready() -> void:
	layer = 5
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_banner = _label(root, "", 22, GOLD)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place(_banner, 0.5, 0.0, Vector2(-400, 52), Vector2(800, 64))
	for side in 2:
		var bar := ProgressBar.new()
		bar.show_percentage = false
		var fill := StyleBoxFlat.new()
		fill.bg_color = RED if side == 0 else BLUE
		bar.add_theme_stylebox_override("fill", fill)
		bar.visible = false
		root.add_child(bar)
		_place(bar, 0.5, 0.0, Vector2(-330 if side == 0 else 30, 120), Vector2(300, 14))
		_bars.append(bar)
	_pools = _label(root, "", 15, Color(0.85, 0.85, 0.85))
	_pools.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place(_pools, 0.5, 0.0, Vector2(-400, 138), Vector2(800, 24))

	var back := PanelContainer.new()
	root.add_child(back)
	_place(back, 1.0, 0.0, Vector2(-340, 230), Vector2(320, 0))
	_panel = VBoxContainer.new()
	_panel.add_theme_constant_override("separation", 4)
	back.add_child(_panel)


func _process(delta: float) -> void:
	if arena == null or not is_instance_valid(arena):
		return
	var b := arena.view_board()
	_show_bout(b)
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


func _show_bout(b: Dictionary) -> void:
	var bout: Dictionary = b.get("bout", {})
	var phase: String = b.get("phase", "idle")
	var left := int(ceil(float(b.get("phase_left", 0.0))))
	if bout.is_empty():
		_banner.text = "THE PIT\n" + (str(b.get("last_result", "")) if str(b.get("last_result", "")) != "" \
				else "Waiting for the next bout")
		_pools.text = ""
		for bar in _bars:
			bar.visible = false
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
		_bars[side].visible = fighter != null
		if fighter != null:
			_bars[side].max_value = fighter.health.max_health
			_bars[side].value = fighter.health.health


func _rebuild(b: Dictionary) -> void:
	for child in _panel.get_children():
		child.queue_free()
	var you: Dictionary = b.get("you", {})
	_label(_panel, "ARENA", 18, GOLD)
	_label(_panel, "Credits: %d   (Esc frees the mouse)" % int(you.get("credits", 0)), 14, Color.WHITE)
	_label(_panel, "Nobody loses gear here. Beaten fighters yield.", 12, Color(0.65, 0.65, 0.65))

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
