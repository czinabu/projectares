extends Control
## The plan table's customizer: the screen on the table's lectern while it is
## in use (`BenchView` mounts it as a `WorldScreen`). Three tabs: Layout (the
## hub's shape), Rooms (which room stands in which doorway) and Styles (how
## each room is laid out). Pointing at a choice shows it on the table's
## hologram at once (`HomeBase.plan_preview`); a click picks it
## (`HomeBase.plan_change`), and a choice not yet unlocked is bought with
## two clicks, the second to confirm (`HomeBase.plan_buy`), and put in use as
## soon as it is yours.
##
## A view only: the base decides nothing here and neither does this. It
## reads the base's plan, upgrades and scrip and redraws whenever they change.
##
## Load with `preload("res://core/ui/plan_panel.gd")`; give it `base`.

const BasePlan := preload("res://core/base/base_plan.gd")
const BaseUpgrades := preload("res://core/base/base_upgrades.gd")

const SIZE := Vector2(1600, 900)
const TABS := ["layout", "rooms", "styles"]
const TAB_TITLES := {"layout": "LAYOUT", "rooms": "ROOMS", "styles": "STYLES"}
const BG := Color(0.025, 0.05, 0.065)
const CARD := Color(0.06, 0.1, 0.125)
const CARD_HOT := Color(0.09, 0.16, 0.2)
const CYAN := Color(0.4, 0.88, 1.0)
const AMBER := Color(1.0, 0.66, 0.26)
const TEXT := Color(0.86, 0.93, 0.96)
const DIM := Color(0.5, 0.62, 0.68)
const GREEN := Color(0.5, 0.95, 0.65)

var base: HomeBase
## The tab on show (`TABS`).
var tab := "layout"
## Layout: the shape picked to look at. Rooms: the socket picked. Styles: the
## room picked and the style picked for it.
var shape_pick := ""
var socket_pick := ""
var room_pick := "armory"
var style_pick := ""
## A buy waiting for its confirming click, as [key, value], or [].
var confirming: Array = []
## A buy asked for, put in use once the unlock is owned, as [key, value].
var pending: Array = []
## One line of news under the action (a refusal, a purchase).
var note := ""

var _key := ""
var _dirty := false
var _body: Control


func _ready() -> void:
	size = SIZE
	custom_minimum_size = SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	_redraw()


## Draws the screen again once this frame's input is done (a button is
## never freed inside its own click).
func _refresh() -> void:
	if not _dirty:
		_dirty = true
		_redraw.call_deferred()


func _process(_delta: float) -> void:
	if base == null or not is_instance_valid(base):
		return
	var key := var_to_str([base.base_plan, base.upgrades, base.scrip])
	if key != _key:
		_key = key
		_settle_pending()
		_refresh()


## A right click: drop a confirm, else a pick, else nothing (false: leave).
func back() -> bool:
	if not confirming.is_empty():
		confirming = []
		_refresh()
		return true
	if tab == "rooms" and socket_pick != "":
		socket_pick = ""
		_preview({})
		_refresh()
		return true
	return false


func show_tab(id: String) -> void:
	if id not in TABS:
		return
	tab = id
	confirming = []
	note = ""
	_preview({})
	_refresh()


# --- What a choice means --------------------------------------------------

## The base's plan with one change made, for the hologram (never checked:
## a preview shows locked choices too).
func with_change(key: String, value: String) -> Dictionary:
	var plan := BasePlan.clean(base.base_plan)
	if key == "shape":
		plan["shape"] = value
	elif key.begins_with("style:"):
		plan["styles"][key.substr(6)] = value
	else:
		plan = BasePlan.place(plan, key, value)
	return plan


## The state of a choice: "used", "owned" or "locked".
func state_of(key: String, value: String) -> String:
	var plan: Dictionary = base.base_plan
	var current := ""
	if key == "shape":
		current = str(plan.get("shape", ""))
	elif key.begins_with("style:"):
		current = str(plan.get("styles", {}).get(key.substr(6), ""))
	if current == value:
		return "used"
	return "locked" if base.plan_unlock(key, value) != "" else "owned"


## A click on the action for a choice: use it, or buy it (asking once more
## to confirm), or say why not.
func act(key: String, value: String) -> void:
	note = ""
	if key == "shape":
		shape_pick = value
	elif key.begins_with("style:"):
		room_pick = key.substr(6)
		style_pick = value
	match state_of(key, value):
		"used":
			return
		"owned":
			note = base.plan_change(key, value)
		"locked":
			if confirming != [key, value]:
				confirming = [key, value]
			else:
				confirming = []
				var why := base.plan_buy(key, value)
				if why == "":
					pending = [key, value]
					note = "Unlocking..."
				else:
					note = why
	_refresh()


## Once a bought unlock is owned, the choice it was bought for goes in use.
func _settle_pending() -> void:
	if pending.is_empty():
		return
	if base.plan_unlock(pending[0], pending[1]) == "":
		base.plan_change(pending[0], pending[1])
		note = "Unlocked and in use."
		pending = []


func _preview(plan: Dictionary) -> void:
	if base != null and is_instance_valid(base):
		base.plan_preview(plan)


# --- Drawing ---------------------------------------------------------------

func _redraw() -> void:
	_dirty = false
	for child in get_children():
		remove_child(child)
		child.queue_free()
	if base == null:
		return
	var frame := Panel.new()
	frame.size = SIZE
	frame.add_theme_stylebox_override("panel", _box(BG, CYAN.darkened(0.5), 3, 0))
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(frame)
	_header()
	_body = Control.new()
	_body.position = Vector2(40, 130)
	_body.size = Vector2(1520, 680)
	add_child(_body)
	match tab:
		"layout":
			_layout_tab()
		"rooms":
			_rooms_tab()
		"styles":
			_styles_tab()
	var hint := _text("Point to preview on the table   ·   Click to pick   ·   Right click: back   ·   Esc: leave", 24, DIM)
	hint.position = Vector2(40, 840)
	add_child(hint)


func _header() -> void:
	var title := _text("BASE PLAN", 44, CYAN)
	title.position = Vector2(40, 34)
	add_child(title)
	for i in TABS.size():
		var id: String = TABS[i]
		var button := _button(TAB_TITLES[id], 30, id == tab)
		button.position = Vector2(420 + 250 * i, 30)
		button.size = Vector2(230, 70)
		button.name = "Tab_%s" % id
		button.pressed.connect(show_tab.bind(id))
		add_child(button)
	var scrip := _text("%s scrip" % HomeBase.commas(base.scrip), 32, AMBER)
	scrip.position = Vector2(1200, 44)
	scrip.size = Vector2(360, 50)
	scrip.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(scrip)
	var rule := ColorRect.new()
	rule.color = CYAN.darkened(0.6)
	rule.position = Vector2(40, 112)
	rule.size = Vector2(1520, 2)
	add_child(rule)


## Layout: the four shapes as cards with their floor plans, and the one
## picked described with its action.
func _layout_tab() -> void:
	if shape_pick == "":
		shape_pick = str(base.base_plan.get("shape", "hall"))
	var shapes := BasePlan.shapes()
	for i in shapes.size():
		var id: String = shapes[i]
		var card := _card(Vector2(370 * (i % 2), 340 * (i / 2)), Vector2(350, 320), id == shape_pick, "Shape_%s" % id)
		var sketch := Sketch.new()
		sketch.position = Vector2(20, 16)
		sketch.size = Vector2(310, 220)
		sketch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_shape_drawing(sketch, id, "")
		card.add_child(sketch)
		_card_footer(card, BasePlan.shape_title(id), "shape", id)
		card.pressed.connect(func() -> void:
			shape_pick = id
			confirming = []
			_refresh())
		card.mouse_entered.connect(_preview.bind(with_change("shape", id)))
	_detail(BasePlan.shape_title(shape_pick), str(BasePlan.SHAPES[shape_pick]["blurb"]),
			"Your rooms keep their doorways; each stands at the same socket in the new layout.", "shape", shape_pick)


## Rooms: the hub's plan with a tile per doorway; pick one, then the room to
## stand there.
func _rooms_tab() -> void:
	var shape := str(base.base_plan.get("shape", "hall"))
	var map := Sketch.new()
	map.position = Vector2(0, 0)
	map.size = Vector2(800, 680)
	map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shape_drawing(map, shape, socket_pick)
	_body.add_child(map)
	# A clickable spot over each tile.
	for socket: String in BasePlan.SOCKETS:
		var at: Vector2 = map.place(_centroid(base.socket_outline(shape, socket)))
		var spot := _button("", 1, socket == socket_pick)
		spot.name = "Socket_%s" % socket
		spot.flat = true
		spot.position = at - Vector2(70, 60)
		spot.size = Vector2(140, 120)
		spot.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		spot.add_theme_stylebox_override("hover", _box(Color(CYAN, 0.12), CYAN, 2, 10))
		spot.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
		spot.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		spot.pressed.connect(func() -> void:
			socket_pick = socket
			note = ""
			_refresh())
		spot.mouse_entered.connect(base.plan_mark.bind(str(base.base_plan[socket])))
		map.add_child(spot)
	var x := 840.0
	if socket_pick == "":
		var heading := _text("Pick a doorway", 40, TEXT)
		heading.position = Vector2(x, 10)
		_body.add_child(heading)
		var how := _text("Click a room on the plan, then the room to stand there. The room it moves out of takes its old doorway. Moving rooms is free and moves nothing in or out of your stash.", 28, DIM)
		how.position = Vector2(x, 80)
		how.size = Vector2(660, 300)
		how.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_body.add_child(how)
		return
	var here := str(base.base_plan[socket_pick])
	var heading := _text(BasePlan.socket_name(shape, socket_pick).to_upper(), 30, CYAN)
	heading.position = Vector2(x, 0)
	_body.add_child(heading)
	var rooms := BasePlan.rooms()
	for i in rooms.size():
		var room: String = rooms[i]
		var row := _card(Vector2(x, 54 + 96 * i), Vector2(680, 86), room == here, "Room_%s" % room)
		var swatch := ColorRect.new()
		swatch.color = HomeBase.ROOM_COLORS.get(room, CYAN)
		swatch.position = Vector2(14, 14)
		swatch.size = Vector2(10, 58)
		swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(swatch)
		var name_label := _text(BasePlan.title(room), 30, TEXT)
		name_label.position = Vector2(40, 6)
		row.add_child(name_label)
		var holds := _text(str(BasePlan.ROOMS[room]["holds"]), 22, DIM)
		holds.position = Vector2(40, 46)
		row.add_child(holds)
		if room == here:
			var tag := _text("HERE", 24, GREEN)
			tag.position = Vector2(580, 26)
			row.add_child(tag)
		row.pressed.connect(func() -> void:
			note = base.plan_change(socket_pick, room)
			socket_pick = ""
			_preview({})
			_refresh())
		row.mouse_entered.connect(_preview.bind(with_change(socket_pick, room)))
		row.mouse_entered.connect(base.plan_mark.bind(room))


## Styles: the six rooms down the left, the picked room's three styles as
## cards with their layouts sketched, and the one picked described.
func _styles_tab() -> void:
	var rooms := BasePlan.rooms()
	for i in rooms.size():
		var room: String = rooms[i]
		var row := _card(Vector2(0, 104 * i), Vector2(360, 94), room == room_pick, "StyleRoom_%s" % room)
		var swatch := ColorRect.new()
		swatch.color = HomeBase.ROOM_COLORS.get(room, CYAN)
		swatch.position = Vector2(12, 14)
		swatch.size = Vector2(8, 66)
		swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(swatch)
		var name_label := _text(BasePlan.title(room), 30, TEXT)
		name_label.position = Vector2(34, 8)
		row.add_child(name_label)
		var style := _text(BasePlan.style_title(room, base.room_style(room)), 22, DIM)
		style.position = Vector2(34, 52)
		row.add_child(style)
		row.pressed.connect(func() -> void:
			room_pick = room
			style_pick = ""
			confirming = []
			note = ""
			base.plan_mark(room)
			_refresh())
	if style_pick == "" or not BasePlan.STYLES[room_pick].has(style_pick):
		style_pick = base.room_style(room_pick)
	var styles := BasePlan.styles(room_pick)
	var key := "style:" + room_pick
	for i in styles.size():
		var id: String = styles[i]
		var card := _card(Vector2(390 + 380 * i, 0), Vector2(360, 380), id == style_pick, "Style_%s" % id)
		var sketch := Sketch.new()
		sketch.position = Vector2(20, 16)
		sketch.size = Vector2(320, 280)
		sketch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_style_drawing(sketch, room_pick, id)
		card.add_child(sketch)
		_card_footer(card, BasePlan.style_title(room_pick, id), key, id)
		card.pressed.connect(func() -> void:
			style_pick = id
			confirming = []
			_refresh())
		card.mouse_entered.connect(_preview.bind(with_change(key, id)))
		card.mouse_entered.connect(base.plan_mark.bind(room_pick))
	var info: Dictionary = BasePlan.STYLES[room_pick][style_pick]
	var action := _action(key, style_pick)
	action.position = Vector2(390, 420)
	_body.add_child(action)
	var blurb := _text("%s: %s" % [BasePlan.style_title(room_pick, style_pick), info["blurb"]], 26, TEXT)
	blurb.position = Vector2(390 + 420, 420)
	blurb.size = Vector2(720, 120)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(blurb)
	_note_at(Vector2(390, 540))


## Under a card's picture: its name and whether it is in use, yours or for
## sale.
func _card_footer(card: Control, title: String, key: String, value: String) -> void:
	var name_label := _text(title, 30, TEXT)
	name_label.position = Vector2(20, card.size.y - 74)
	card.add_child(name_label)
	var state := state_of(key, value)
	var tag := _text({"used": "IN USE", "owned": "OWNED"}.get(state,
			"%s scrip" % HomeBase.commas(BaseUpgrades.price(BasePlan.unlock_for(key, value)))), 22,
			GREEN if state == "used" else (CYAN if state == "owned" else AMBER))
	tag.position = Vector2(20, card.size.y - 36)
	card.add_child(tag)


## The right side of the layout tab: the choice's name, what it is and its
## action.
func _detail(title: String, blurb: String, more: String, key: String, value: String) -> void:
	var x := 780.0
	var heading := _text(title, 48, TEXT)
	heading.position = Vector2(x, 0)
	_body.add_child(heading)
	var what := _text(blurb, 28, TEXT)
	what.position = Vector2(x, 80)
	what.size = Vector2(720, 120)
	what.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(what)
	var extra := _text(more, 24, DIM)
	extra.position = Vector2(x, 200)
	extra.size = Vector2(720, 120)
	extra.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(extra)
	var action := _action(key, value)
	action.position = Vector2(x, 340)
	_body.add_child(action)
	_note_at(Vector2(x, 460))


## The big button for a choice: in use, use it, unlock it, or confirm.
func _action(key: String, value: String) -> Button:
	var state := state_of(key, value)
	var price := BaseUpgrades.price(BasePlan.unlock_for(key, value))
	var text := ""
	var color := CYAN
	match state:
		"used":
			text = "In use"
			color = GREEN
		"owned":
			text = "Use this"
		_:
			if confirming == [key, value]:
				text = "Confirm: %s scrip" % HomeBase.commas(price)
			else:
				text = "Unlock for %s scrip" % HomeBase.commas(price)
			color = AMBER
	var button := _button(text, 32, state != "used")
	button.name = "Action"
	button.size = Vector2(400, 90)
	button.add_theme_color_override("font_color", color)
	button.add_theme_color_override("font_hover_color", color.lightened(0.3))
	button.add_theme_stylebox_override("normal", _box(color.darkened(0.82), color.darkened(0.2), 3, 12))
	button.add_theme_stylebox_override("hover", _box(color.darkened(0.7), color, 3, 12))
	button.disabled = state == "used"
	button.pressed.connect(act.bind(key, value))
	return button


func _note_at(at: Vector2) -> void:
	var line := note
	if line == "" and not confirming.is_empty():
		line = "Bought once: switch to it and back for free after."
	if line == "":
		return
	var label := _text(line, 24, AMBER)
	label.name = "Note"
	label.position = at
	label.size = Vector2(720, 80)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(label)


## A hub's floor plan on a sketch: the hub, the corridor, and each socket's
## room in its colour, named; `hot` stands out.
func _shape_drawing(sketch: Sketch, shape: String, hot: String) -> void:
	var size: Vector3 = HomeBase.HUB_SIZES[shape]
	var outlines: Array = []
	for socket: String in BasePlan.SOCKETS:
		outlines.append(base.socket_outline(shape, socket))
	var lane_from := size.z * 0.5
	var lane_to := base.shape_range_from(shape)
	var lane := PackedVector2Array([Vector2(-1.5, -lane_from), Vector2(1.5, -lane_from), Vector2(1.5, -lane_to), Vector2(-1.5, -lane_to)])
	sketch.fit([base.shape_outline(shape), lane] + outlines)
	sketch.add_poly(base.shape_outline(shape), Color(CYAN, 0.12), CYAN.darkened(0.2))
	sketch.add_poly(lane, Color(CYAN, 0.08), CYAN.darkened(0.4))
	for socket: String in BasePlan.SOCKETS:
		var room := str(base.base_plan[socket])
		var color: Color = HomeBase.ROOM_COLORS.get(room, CYAN)
		var mine := socket == hot
		sketch.add_poly(base.socket_outline(shape, socket), Color(AMBER if mine else color, 0.5 if mine else 0.25),
				AMBER if mine else color.darkened(0.2))
		sketch.add_label(_centroid(base.socket_outline(shape, socket)), BasePlan.title(room), color.lightened(0.4))
	# The way out.
	sketch.add_poly(PackedVector2Array([Vector2(-1.3, size.z * 0.5 - 0.6), Vector2(1.3, size.z * 0.5 - 0.6),
			Vector2(1.3, size.z * 0.5 + 0.4), Vector2(-1.3, size.z * 0.5 + 0.4)]), AMBER, AMBER)


## A room in a style, from above: its walls and every piece in it.
func _style_drawing(sketch: Sketch, room: String, style: String) -> void:
	var half := base.socket_size.x * 0.5
	var depth := base.socket_size.z
	var walls := PackedVector2Array([Vector2(-half, 0), Vector2(half, 0), Vector2(half, -depth), Vector2(-half, -depth)])
	sketch.fit([walls])
	var color: Color = HomeBase.ROOM_COLORS.get(room, CYAN)
	sketch.add_poly(walls, Color(color, 0.08), color.darkened(0.3))
	for piece: Array in base.style_sketch(room, style):
		var at: Vector3 = piece[0]
		var box: Vector3 = piece[1]
		var hx := box.x * 0.5
		var hz := box.z * 0.5
		sketch.add_poly(PackedVector2Array([Vector2(at.x - hx, at.z - hz), Vector2(at.x + hx, at.z - hz),
				Vector2(at.x + hx, at.z + hz), Vector2(at.x - hx, at.z + hz)]), Color(color, 0.55), color.lightened(0.3))
	# The doorway.
	sketch.add_poly(PackedVector2Array([Vector2(-2.0, -0.15), Vector2(2.0, -0.15), Vector2(2.0, 0.25), Vector2(-2.0, 0.25)]), BG, CYAN)


static func _centroid(points: PackedVector2Array) -> Vector2:
	var sum := Vector2.ZERO
	for p in points:
		sum += p
	return sum / maxf(1.0, float(points.size()))


# --- Pieces ----------------------------------------------------------------

func _card(at: Vector2, card_size: Vector2, picked: bool, card_name: String) -> Button:
	var card := Button.new()
	card.name = card_name
	card.position = at
	card.size = card_size
	card.add_theme_stylebox_override("normal", _box(CARD_HOT if picked else CARD, CYAN if picked else CYAN.darkened(0.65), 3 if picked else 2, 12))
	card.add_theme_stylebox_override("hover", _box(CARD_HOT, CYAN.lightened(0.2), 3, 12))
	card.add_theme_stylebox_override("pressed", _box(CARD_HOT, CYAN, 3, 12))
	card.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_body.add_child(card)
	return card


func _button(text: String, font_size: int, lit: bool) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_color_override("font_color", CYAN if lit else DIM)
	button.add_theme_color_override("font_hover_color", CYAN.lightened(0.3))
	button.add_theme_stylebox_override("normal", _box(CARD_HOT if lit else CARD, CYAN if lit else CYAN.darkened(0.65), 2, 10))
	button.add_theme_stylebox_override("hover", _box(CARD_HOT, CYAN, 2, 10))
	button.add_theme_stylebox_override("pressed", _box(CARD_HOT, CYAN, 2, 10))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return button


func _text(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


static func _box(fill: Color, edge: Color, width: int, corner: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = edge
	box.set_border_width_all(width)
	box.set_corner_radius_all(corner)
	return box


## A plan drawn from above: polygons in the base's x, z (metres), fitted into
## the control with +z toward its bottom (the way out at the bottom).
class Sketch:
	extends Control

	var _polys: Array = []
	var _labels: Array = []
	var _scale := 1.0
	var _offset := Vector2.ZERO

	## Fits these polygons into the control, with a margin.
	func fit(polys: Array) -> void:
		var low := Vector2(INF, INF)
		var high := Vector2(-INF, -INF)
		for poly: PackedVector2Array in polys:
			for p in poly:
				low = low.min(p)
				high = high.max(p)
		var span := (high - low).max(Vector2(0.01, 0.01))
		_scale = minf((size.x - 16.0) / span.x, (size.y - 16.0) / span.y)
		_offset = size * 0.5 - (low + high) * 0.5 * _scale

	## Where a point (x, z) is drawn.
	func place(p: Vector2) -> Vector2:
		return p * _scale + _offset

	func add_poly(points: PackedVector2Array, fill: Color, edge: Color) -> void:
		_polys.append([points, fill, edge])
		queue_redraw()

	func add_label(at: Vector2, text: String, color: Color) -> void:
		_labels.append([at, text, color])
		queue_redraw()

	func _draw() -> void:
		for poly: Array in _polys:
			var drawn := PackedVector2Array()
			for p: Vector2 in poly[0]:
				drawn.append(place(p))
			draw_colored_polygon(drawn, poly[1])
			drawn.append(drawn[0])
			draw_polyline(drawn, poly[2], 2.0, true)
		var font := get_theme_default_font()
		var font_size := clampi(int(_scale * 1.3), 14, 26)
		for label: Array in _labels:
			var width := font.get_string_size(label[1], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			draw_string(font, place(label[0]) + Vector2(-width * 0.5, font_size * 0.35), label[1],
					HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, label[2])
