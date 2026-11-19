extends VBoxContainer
## The War Room console in front of the big screen: pick a world to see its
## map, its front and its news, and deploy to it from there (DESIGN.md
## section 2). Only a view: it reads `world_status` and `routes` as the
## server last told them, says what it picked with `picked` (the big screen
## then shows that world for you, `WarRoom.focus`) and asks to deploy with
## `deploy_asked`; `main.gd` takes the trip the way a gate does.
##
## Load with `preload("res://core/social/war_room_panel.gd")`.

const PlazaView := preload("res://core/social/plaza_view.gd")
const TITLE_COLOR := Color(0.35, 0.85, 1.0)

signal picked(world_id: String)
signal deploy_asked(world_id: String)

## Shared with `NetSession.world_status` and `routes`.
var world_status := {}
var routes := {}
## The world shown, or "" before one is picked.
var chosen := ""

var _list: VBoxContainer
var _map: MapView
var _name: Label
var _about: Label
var _news: Label
var _deploy: Button
var _message: Label


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	add_child(_label("WAR ROOM", 22, TITLE_COLOR))
	add_child(_label("Pick a world to put its map up on the big screen. Deploy from here goes straight in, "
			+ "the same as walking through its gate.", 14, Color(0.65, 0.65, 0.65), true))
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 16)
	add_child(body)
	_list = VBoxContainer.new()
	_list.custom_minimum_size = Vector2(300, 0)
	_list.add_theme_constant_override("separation", 6)
	body.add_child(_list)
	_map = MapView.new()
	_map.custom_minimum_size = Vector2(430, 430)
	body.add_child(_map)
	var side := VBoxContainer.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.add_theme_constant_override("separation", 8)
	body.add_child(side)
	_name = _label("", 24, Color(0.92, 0.96, 1.0))
	side.add_child(_name)
	_about = _label("", 14, Color(0.65, 0.7, 0.75), true)
	side.add_child(_about)
	_news = _label("", 15, Color(1.0, 0.8, 0.5), true)
	side.add_child(_news)
	_deploy = Button.new()
	_deploy.custom_minimum_size = Vector2(0, 48)
	_deploy.pressed.connect(func() -> void:
		if is_open(chosen, routes):
			deploy_asked.emit(chosen))
	side.add_child(_deploy)
	_message = _label("", 15, Color(1.0, 0.8, 0.4), true)
	side.add_child(_message)
	var worlds := choices()
	if chosen == "" and not worlds.is_empty():
		chosen = worlds[0]
	refresh()


func show_message(text: String) -> void:
	if _message:
		_message.text = text


## The worlds on offer, in the registry's order: every world you deploy into.
static func choices() -> Array[String]:
	var out: Array[String] = []
	for world in Worlds.raid_worlds():
		out.append(world.id)
	return out


static func is_open(world_id: String, p_routes: Dictionary) -> bool:
	return world_id != "" and p_routes.has(world_id)


## What the console says of a world: its news, its front and who is hunted
## there, one line each, from `world_status`.
static func news_lines(world_id: String, status: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var entry: Dictionary = status.get(world_id, {})
	var world := Worlds.get_world(world_id)
	var heat := PlazaView.heat_text(entry)
	out.append(heat if heat != "" else "No news from there yet.")
	var held := WarRoom.holdings(entry.get("front", []))
	if not held.is_empty():
		var parts: Array[String] = []
		for holder: String in held:
			parts.append("%s %d" % [WarRoom.holder_name(world, holder), int(held[holder])])
		out.append("Landmarks held:  " + ",  ".join(parts))
	for moment: Variant in entry.get("moments", []):
		if typeof(moment) == TYPE_DICTIONARY:
			out.append(str(moment.text))
			break
	for row: Variant in entry.get("hunted", []):
		if typeof(row) == TYPE_DICTIONARY:
			out.append("%s is hunted by %s" % [str(row.name), WarRoom.holder_name(world, str(row.by))])
	var race: Variant = entry.get("race", {})
	if typeof(race) == TYPE_DICTIONARY and not (race as Dictionary).is_empty():
		var racers: Array = race.get("racers", [])
		out.append("AI race on %s, %d racers" % [str(race.get("name", "")), racers.size()] if not racers.is_empty()
				else "A live race is %s on %s" % [str(race.get("phase", "on")), str(race.get("name", ""))])
	return out


func pick(world_id: String) -> void:
	chosen = world_id
	show_message("")
	picked.emit(world_id)
	refresh()


func refresh() -> void:
	if _list == null:
		return
	for child in _list.get_children():
		child.queue_free()
	for id in choices():
		var world := Worlds.get_world(id)
		var button := Button.new()
		var entry: Dictionary = world_status.get(id, {})
		var level := str(entry.get("level", "")) if not entry.is_empty() else ("Closed" if not is_open(id, routes) else "")
		button.text = "%s   %s" % [world.display_name, level] if level != "" else world.display_name
		button.toggle_mode = true
		button.button_pressed = id == chosen
		button.custom_minimum_size = Vector2(0, 44)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(pick.bind(id))
		_list.add_child(button)
	var world := Worlds.get_world(chosen)
	_map.world = world
	_map.entry = world_status.get(chosen, {})
	_map.queue_redraw()
	_name.text = world.display_name.to_upper() if world != null else ""
	_about.text = world.description if world != null else ""
	_news.text = "\n".join(news_lines(chosen, world_status)) if chosen != "" else ""
	var open := is_open(chosen, routes)
	_deploy.text = "Deploy to %s" % world.display_name if open and world != null else "Not running on this server"
	_deploy.disabled = not open


func _label(text: String, size: int, color: Color, wrap := false) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


## The picked world's map: its front where it has landmarks, its circuit
## where it races, else its name.
class MapView:
	extends Control

	var world: WorldDef
	var entry := {}

	func _process(_delta: float) -> void:
		if not (entry.get("front", []) as Array).is_empty():
			queue_redraw()

	func _draw() -> void:
		var rect := Rect2(Vector2.ZERO, size)
		var font := ThemeDB.fallback_font
		var front: Array = entry.get("front", [])
		if not front.is_empty():
			WarRoom.draw_front(self, rect, world, front, font, Time.get_unix_time_from_system(), 14)
			return
		draw_rect(rect, Color(0.02, 0.05, 0.08))
		draw_rect(rect, Color(TITLE_COLOR, 0.5), false, 2.0)
		var tracks := world.feed_tracks() if world != null else [] as Array[RaceTrack]
		if not tracks.is_empty():
			_draw_tracks(rect, tracks, font)
			return
		draw_string(font, Vector2(0, size.y * 0.5), (world.display_name if world else "").to_upper(),
				HORIZONTAL_ALIGNMENT_CENTER, size.x, 28, Color(0.6, 0.75, 0.85))
		draw_string(font, Vector2(0, size.y * 0.5 + 30), "No landmarks to hold here", HORIZONTAL_ALIGNMENT_CENTER,
				size.x, 14, Color(0.5, 0.55, 0.6))

	## Each circuit's line from above, side by side.
	func _draw_tracks(rect: Rect2, tracks: Array[RaceTrack], font: Font) -> void:
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for t in tracks:
			for p in t.points:
				lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.z))
				hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.z))
		var span := maxf(hi.x - lo.x, hi.y - lo.y) * 1.1
		var colors: Array[Color] = [Color(1.0, 0.62, 0.22), TITLE_COLOR]
		for k in tracks.size():
			var line := PackedVector2Array()
			for i in range(0, tracks[k].points.size(), 3):
				var p := tracks[k].points[i]
				line.append(rect.position + rect.size * 0.05 + Vector2(p.x - lo.x, p.z - lo.y) / span * rect.size.x * 0.9)
			if not line.is_empty():
				line.append(line[0])
				draw_polyline(line, colors[k % colors.size()], 3.0)
				draw_string(font, line[0] + Vector2(6, -6), tracks[k].display_name.to_upper(), HORIZONTAL_ALIGNMENT_LEFT,
						-1, 14, colors[k % colors.size()])
