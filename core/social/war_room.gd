class_name WarRoom
extends Node3D
## The War Room: the Concourse's big screen, a live feed of the worlds that
## people gather in front of (DESIGN.md section 2, "Spectating screens").
## View only, made by `PlazaView` only where `Look` is on, so a server has
## none. Everything on it comes from what the client is already told,
## `NetSession.world_status` (each world's `Raid.status()`): who holds each
## landmark and so where the front line runs (`Raid.front`), the big
## moments (`Raid.live_moments`, and moments a world keeps on the wall
## clock, `WorldDef.clock_moments`), who the armies are hunting
## (`Raid.hunted`) and the AI races on a race world (`Race.race_feed`),
## shot by a track camera of its own (`TrackCam`). It never says where a
## person is: only landmarks, and AI racers on a track nobody is racing.
##
## The feed turns through its segments on the wall clock (`SEGMENT_TIME`),
## so everyone watching sees the same one. The console in front of it
## (`WarRoomPanel`) sets `focus` to a world while it is in use, and the
## screen shows that world for the one watching it, nobody else.

const PlazaLocals := preload("res://core/social/plaza_locals.gd")
const PlazaView := preload("res://core/social/plaza_view.gd")
const Strongpoint := preload("res://core/war/strongpoint.gd")

## The screen's picture, in pixels (the wall's 30 m by 11 m).
const SIZE := Vector2i(1920, 704)
## The screen's face in metres (the map's "screen_wall" glass).
const FACE := Vector2(30.0, 11.0)
## Seconds each segment holds the screen.
const SEGMENT_TIME := 14.0
## How often the picture is redrawn while someone is near, a second.
const FRAMES := 20.0
## Past this many metres nobody can read it: it stops drawing.
const WATCH_RANGE := 160.0
## Moments shown down the right side.
const MOMENTS_SHOWN := 4
## Players holding a landmark, apart from any army's colour.
const PLAYERS := Color(0.45, 1.0, 0.6)

var raid: Raid
## Shared with `PlazaView.world_status`.
var world_status := {}
## A world the console picked (local only), or "".
var focus := ""
var feed: Feed
var viewport: SubViewport
var track_cam: TrackCam
var _frame_in := 0.0


func setup(p_raid: Raid, p_status: Dictionary) -> void:
	raid = p_raid
	world_status = p_status


func _ready() -> void:
	var wall := _screen_wall()
	if wall == null:
		return
	viewport = SubViewport.new()
	viewport.name = "Feed"
	viewport.size = SIZE
	viewport.disable_3d = true
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(viewport)
	track_cam = TrackCam.new()
	track_cam.name = "TrackCam"
	add_child(track_cam)
	feed = Feed.new()
	feed.room = self
	viewport.add_child(feed)
	# The picture on the glass, a hair in front of it.
	var quad := QuadMesh.new()
	quad.size = FACE
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = viewport.get_texture()
	mat.emission_enabled = true
	mat.emission_texture = viewport.get_texture()
	mat.emission_energy_multiplier = 0.6
	var face := MeshInstance3D.new()
	face.name = "FeedFace"
	face.mesh = quad
	face.material_override = mat
	face.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	face.position = Vector3(0, 0, 0.07)
	wall.add_child(face)


func _screen_wall() -> Node3D:
	if raid == null or raid.map == null:
		return null
	for node in raid.get_tree().get_nodes_in_group("screen_wall"):
		if node is Node3D and raid.map.is_ancestor_of(node):
			return node as Node3D
	return null


func _process(delta: float) -> void:
	if viewport == null:
		return
	var near := _someone_near()
	track_cam.active = near and feed.segment_kind() == "race"
	if not near:
		return
	_frame_in -= delta
	if _frame_in > 0.0:
		return
	_frame_in = 1.0 / FRAMES
	feed.queue_redraw()
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func _someone_near() -> bool:
	var camera := get_viewport().get_camera_3d()
	var wall := _screen_wall()
	if camera == null or wall == null:
		return false
	return camera.global_position.distance_to(wall.global_position) < WATCH_RANGE


## The segments on the screen now, in order: a front map for each world
## with landmarks, the track cam for each world with races, and the worlds
## at a glance. Keys like "front:ashfront", "race:meridian", "worlds".
static func segments(status: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var ids: Array = status.keys()
	ids.sort()
	for id: Variant in ids:
		var entry: Variant = status[id]
		if typeof(entry) == TYPE_DICTIONARY and not (entry.get("front", []) as Array).is_empty():
			out.append("front:%s" % id)
	for id: Variant in ids:
		var world := Worlds.get_world(str(id))
		if world != null and not world.feed_tracks().is_empty():
			out.append("race:%s" % id)
	out.append("worlds")
	return out


## The segment for `unix` seconds: everyone in the plaza sees the same one.
## A world the console picked holds the screen.
static func segment_at(status: Dictionary, unix: float, p_focus := "") -> String:
	if p_focus != "":
		var world := Worlds.get_world(p_focus)
		var entry: Variant = status.get(p_focus, {})
		if typeof(entry) == TYPE_DICTIONARY and not (entry.get("front", []) as Array).is_empty():
			return "front:" + p_focus
		if world != null and not world.feed_tracks().is_empty():
			return "race:" + p_focus
		return "world:" + p_focus
	var list := segments(status)
	return list[int(unix / SEGMENT_TIME) % list.size()]


## The big moments across every world, newest first: each {world, kind,
## text, at}, from the server's news and each world's own clock.
static func moments(status: Dictionary, unix: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: Variant in status:
		var entry: Variant = status[id]
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		for moment: Variant in entry.get("moments", []):
			if typeof(moment) == TYPE_DICTIONARY:
				var row: Dictionary = moment.duplicate()
				row["world"] = str(id)
				out.append(row)
		var world := Worlds.get_world(str(id))
		if world != null:
			for moment in world.clock_moments(unix):
				var row := moment.duplicate()
				row["world"] = str(id)
				out.append(row)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("at", 0)) > int(b.get("at", 0)))
	return out


## Who the armies hunt, across every world: each {name, clan, by, world}.
static func hunted(status: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: Variant in status:
		var entry: Variant = status[id]
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		for row: Variant in entry.get("hunted", []):
			if typeof(row) == TYPE_DICTIONARY:
				var line: Dictionary = row.duplicate()
				line["world"] = str(id)
				out.append(line)
	return out


## How long ago, said short: "now", "3m", "1h".
static func ago(seconds: int) -> String:
	if seconds < 60:
		return "now"
	if seconds < 3600:
		return "%dm" % (seconds / 60)
	return "%dh" % (seconds / 3600)


## Who holds what in a front: holder -> how many landmarks.
static func holdings(front: Array) -> Dictionary:
	var out := {}
	for site: Variant in front:
		if typeof(site) == TYPE_DICTIONARY:
			var key := str(site.get("holder", ""))
			out[key] = int(out.get(key, 0)) + 1
	return out


## A holder's name as people say it: an army's title, "Players", "Nobody".
static func holder_name(world: WorldDef, holder: String) -> String:
	if holder == "":
		return "Nobody"
	if holder == "players":
		return "Players"
	var title := world.faction_title(holder) if world != null else holder.capitalize()
	return title.left(1).to_upper() + title.substr(1)


static func holder_color(world: WorldDef, holder: String) -> Color:
	if holder == "players":
		return PLAYERS
	if holder == "":
		return Strongpoint.NOBODY
	return world.faction_color(holder) if world != null else Strongpoint.BOTS


## Draws a world's front on `canvas` inside `rect`: ground split by whoever
## holds the nearest landmark (where two sides meet is the front line), the
## world's risk zones as faint rings, and each landmark with its holder.
## Shared by the big screen and the console (`WarRoomPanel`).
static func draw_front(canvas: CanvasItem, rect: Rect2, world: WorldDef, front: Array, font: Font,
		unix: float, label_size := 18) -> void:
	var sites: Array[Dictionary] = []
	for site: Variant in front:
		if typeof(site) == TYPE_DICTIONARY:
			sites.append(site)
	canvas.draw_rect(rect, Color(0.02, 0.05, 0.08))
	if sites.is_empty():
		return
	var reach := 1.0
	for site in sites:
		reach = maxf(reach, maxf(absf(float(site.x)), absf(float(site.z))))
	reach *= 1.35
	var side := minf(rect.size.x, rect.size.y)
	var square := Rect2(rect.position + (rect.size - Vector2(side, side)) * 0.5, Vector2(side, side))
	var to_map := func(x: float, z: float) -> Vector2:
		return square.position + Vector2((x / reach * 0.5 + 0.5) * side, (z / reach * 0.5 + 0.5) * side)
	# Territory: cells coloured by the nearest landmark's holder, and a
	# bright edge wherever the next cell belongs to someone else; the risk
	# zones as faint dots on their edges. Worked out once per front.
	var plan := _front_plan(world, sites, reach)
	var cells: int = plan.cells
	var step := side / cells
	var owner_of: Array = plan.owners
	for j in cells:
		for i in cells:
			var holder: String = owner_of[j][i]
			var color := holder_color(world, holder)
			var cell := Rect2(square.position + Vector2(i * step, j * step), Vector2(step + 0.5, step + 0.5))
			canvas.draw_rect(cell, Color(color, 0.16))
			var right: String = owner_of[j][i + 1] if i + 1 < cells else holder
			var down: String = owner_of[j + 1][i] if j + 1 < cells else holder
			if right != holder:
				canvas.draw_line(cell.position + Vector2(step, 0), cell.position + Vector2(step, step),
						Color(1.0, 0.85, 0.6, 0.8), 2.0)
			if down != holder:
				canvas.draw_line(cell.position + Vector2(0, step), cell.position + Vector2(step, step),
						Color(1.0, 0.85, 0.6, 0.8), 2.0)
	for dot: Vector2 in plan.zone_dots:
		canvas.draw_rect(Rect2(square.position + dot * side, Vector2(2, 2)), Color(0.6, 0.9, 1.0, 0.35))
	# A faint grid, like a plotting table.
	for g in 9:
		var t := square.position + Vector2(g * side / 8.0, 0)
		canvas.draw_line(t, t + Vector2(0, side), Color(0.35, 0.85, 1.0, 0.07), 1.0)
		var u := square.position + Vector2(0, g * side / 8.0)
		canvas.draw_line(u, u + Vector2(side, 0), Color(0.35, 0.85, 1.0, 0.07), 1.0)
	canvas.draw_rect(square, Color(0.35, 0.85, 1.0, 0.5), false, 2.0)
	# The landmarks.
	for site in sites:
		var at: Vector2 = to_map.call(float(site.x), float(site.z))
		var holder := str(site.holder)
		var color := holder_color(world, holder)
		var r := side * 0.022
		var diamond := PackedVector2Array([at + Vector2(0, -r), at + Vector2(r, 0), at + Vector2(0, r), at + Vector2(-r, 0)])
		canvas.draw_colored_polygon(diamond, color)
		diamond.append(diamond[0])
		canvas.draw_polyline(diamond, Color(1, 1, 1, 0.9), 2.0)
		if bool(site.get("contested", false)):
			var pulse := 0.5 + 0.5 * sin(unix * 6.0)
			canvas.draw_arc(at, r * (1.6 + pulse * 0.6), 0.0, TAU, 32, Color(1.0, 0.2, 0.15, 0.4 + pulse * 0.5), 3.0)
		var name := str(site.name).to_upper()
		canvas.draw_string(font, at + Vector2(-200, -r - 8), name, HORIZONTAL_ALIGNMENT_CENTER, 400, label_size,
				Color(0.92, 0.96, 1.0))
		var who := holder_name(world, holder) + ("  UNDER ATTACK" if bool(site.get("contested", false)) else "")
		canvas.draw_string(font, at + Vector2(-200, r + label_size + 4), who, HORIZONTAL_ALIGNMENT_CENTER, 400,
				int(label_size * 0.8), color.lightened(0.25))


static var _plans := {}


## Who holds each cell of a front's map and where its risk zones' edges
## run (as shares of the map's side), kept until the front changes.
static func _front_plan(world: WorldDef, sites: Array[Dictionary], reach: float) -> Dictionary:
	var key := "%s|%s" % [world.id if world != null else "", str(sites.map(func(site: Dictionary) -> Array:
			return [site.x, site.z, site.holder]))]
	if _plans.has(key):
		return _plans[key]
	var cells := 40
	var owners := []
	for j in cells:
		var row := []
		for i in cells:
			var wx := ((i + 0.5) / cells * 2.0 - 1.0) * reach
			var wz := ((j + 0.5) / cells * 2.0 - 1.0) * reach
			var best := 0
			var best_d := INF
			for k in sites.size():
				var d := Vector2(wx - float(sites[k].x), wz - float(sites[k].z)).length_squared()
				if d < best_d:
					best_d = d
					best = k
			row.append(str(sites[best].holder))
		owners.append(row)
	var dots: Array[Vector2] = []
	if world != null:
		var zones := 64
		for j in zones:
			for i in zones:
				var wx := ((i + 0.5) / zones * 2.0 - 1.0) * reach
				var wz := ((j + 0.5) / zones * 2.0 - 1.0) * reach
				var here := world.zone_at(Vector3(wx, 0, wz))
				if here < 0:
					continue
				if world.zone_at(Vector3(wx + reach * 2.0 / zones, 0, wz)) != here \
						or world.zone_at(Vector3(wx, 0, wz + reach * 2.0 / zones)) != here:
					dots.append(Vector2(float(i) / zones, float(j) / zones))
	if _plans.size() > 16:
		_plans.clear()
	_plans[key] = {"cells": cells, "owners": owners, "zone_dots": dots}
	return _plans[key]


## The screen's picture, drawn by hand each frame it is shown.
class Feed:
	extends Control

	const CYAN := Color(0.35, 0.85, 1.0)
	const AMBER := Color(1.0, 0.62, 0.22)
	const INK := Color(0.9, 0.94, 0.98)
	const DIM := Color(0.55, 0.65, 0.72)
	const RED := Color(1.0, 0.32, 0.26)

	var room: Node
	var font: Font

	func _ready() -> void:
		size = Vector2(WarRoom.SIZE)
		font = ThemeDB.fallback_font

	func _status() -> Dictionary:
		return room.world_status if room != null else {}

	func _now() -> float:
		return Time.get_unix_time_from_system()

	func segment() -> String:
		return WarRoom.segment_at(_status(), _now(), room.focus if room != null else "")

	func segment_kind() -> String:
		return segment().get_slice(":", 0)

	func _draw() -> void:
		var now := _now()
		var status := _status()
		var seg := segment()
		var kind := seg.get_slice(":", 0)
		var id := seg.get_slice(":", 1) if seg.contains(":") else ""
		var world := Worlds.get_world(id) if id != "" else null
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.015, 0.03, 0.05))
		# Scanlines and a slow sweep: a lit screen, not a flat panel.
		for y in range(0, int(size.y), 6):
			draw_line(Vector2(0, y), Vector2(size.x, y), Color(0.35, 0.85, 1.0, 0.025), 1.0)
		var sweep := fposmod(now * 90.0, size.y + 200.0) - 100.0
		draw_rect(Rect2(0, sweep, size.x, 80), Color(0.35, 0.85, 1.0, 0.03))
		# The header.
		draw_rect(Rect2(0, 0, size.x, 70), Color(0.03, 0.07, 0.1))
		draw_line(Vector2(0, 70), Vector2(size.x, 70), CYAN, 3.0)
		var live := 0.5 + 0.5 * sin(now * 4.0)
		draw_circle(Vector2(44, 35), 11, Color(RED, 0.5 + live * 0.5))
		draw_string(font, Vector2(66, 48), "LIVE", HORIZONTAL_ALIGNMENT_LEFT, -1, 34, RED)
		draw_string(font, Vector2(170, 48), _title(kind, id, world, status), HORIZONTAL_ALIGNMENT_LEFT, 1100, 36, INK)
		if room != null and room.focus != "":
			draw_string(font, Vector2(1300, 48), "PICKED AT THE CONSOLE", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, AMBER)
		else:
			_draw_pips(seg, status)
		# The main panel.
		var main := Rect2(28, 92, 1260, 560)
		match kind:
			"front":
				_draw_front_segment(main, world, status.get(id, {}), now)
			"race":
				_draw_race_segment(main, id, world, status.get(id, {}))
			"world":
				_draw_world_card(main, id, world, status.get(id, {}))
			_:
				_draw_worlds(main, status)
		draw_rect(main, Color(CYAN, 0.6), false, 2.0)
		# The right side: big moments, then who is hunted.
		_draw_side(Rect2(1316, 92, 576, 560), status, int(now))
		# The crawl along the bottom.
		_draw_crawl(Rect2(0, 664, size.x, 40), status, now)

	func _title(kind: String, id: String, world: WorldDef, status: Dictionary) -> String:
		var name := world.display_name.to_upper() if world != null else id.to_upper()
		match kind:
			"front":
				var entry: Dictionary = status.get(id, {})
				return "%s  //  THE FRONT  //  %s" % [name, str(entry.get("level", "")).to_upper()]
			"race":
				return "%s  //  TRACK CAM" % name
			"world":
				return name
		return "THE WORLDS"

	func _draw_pips(seg: String, status: Dictionary) -> void:
		var list := WarRoom.segments(status)
		for i in list.size():
			var at := Vector2(size.x - 40 - (list.size() - 1 - i) * 30, 35)
			if list[i] == seg:
				draw_circle(at, 8, CYAN)
			else:
				draw_arc(at, 8, 0, TAU, 16, Color(CYAN, 0.5), 2.0)

	func _draw_front_segment(main: Rect2, world: WorldDef, entry: Dictionary, now: float) -> void:
		var front: Array = entry.get("front", [])
		var map_rect := Rect2(main.position + Vector2(10, 10), Vector2(main.size.y - 20, main.size.y - 20))
		WarRoom.draw_front(self, map_rect, world, front, font, now, 26)
		# Who holds what, and the war meter.
		var x := map_rect.end.x + 40
		var y := main.position.y + 50
		draw_string(font, Vector2(x, y), "WHO HOLDS THE FIELD", HORIZONTAL_ALIGNMENT_LEFT, -1, 34, CYAN)
		y += 50
		var held := WarRoom.holdings(front)
		var keys: Array = held.keys()
		keys.sort_custom(func(a: String, b: String) -> bool: return int(held[a]) > int(held[b]))
		for holder: String in keys:
			var color := WarRoom.holder_color(world, holder)
			draw_rect(Rect2(x, y - 30, 34, 34), color)
			draw_string(font, Vector2(x + 50, y), "%s   %d of %d" % [WarRoom.holder_name(world, holder), int(held[holder]),
					front.size()], HORIZONTAL_ALIGNMENT_LEFT, -1, 36, INK)
			y += 58
		y += 20
		for site: Variant in front:
			if typeof(site) == TYPE_DICTIONARY and bool(site.get("contested", false)):
				draw_string(font, Vector2(x, y), "%s is under attack" % str(site.name), HORIZONTAL_ALIGNMENT_LEFT, 600,
						32, RED)
				y += 44
		var war := clampf(float(entry.get("war", 0.0)), 0.0, 1.0)
		var bar := Rect2(x, main.end.y - 100, 580, 28)
		draw_string(font, bar.position + Vector2(0, -14), "WAR  %s" % str(entry.get("level", "Quiet")).to_upper(),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 32, PlazaView.heat_color(war))
		draw_rect(bar, Color(1, 1, 1, 0.08))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * war, bar.size.y)), PlazaView.heat_color(war))
		var players := int(entry.get("players", 0))
		var line := "1 player out there" if players == 1 else "%d players out there" % players
		if str(entry.get("storm", "")) != "":
			line += "   %s" % str(entry.storm)
		draw_string(font, Vector2(x, main.end.y - 30), line, HORIZONTAL_ALIGNMENT_LEFT, 600, 30, DIM)

	func _draw_race_segment(main: Rect2, id: String, world: WorldDef, entry: Dictionary) -> void:
		var race: Dictionary = entry.get("race", {})
		var cam: TrackCam = room.track_cam if room != null else null
		if cam != null:
			cam.show_world(world, race)
			draw_texture_rect(cam.texture(), main, false)
		var live := cam != null and cam.live
		var tag := "LIVE  //  %s" % str(race.get("name", "")).to_upper() if live else "EXHIBITION LAPS  //  NO RACE ON RIGHT NOW"
		if cam != null and cam.track != null and not live:
			tag = "EXHIBITION LAPS  //  %s" % cam.track.display_name.to_upper()
		draw_rect(Rect2(main.position, Vector2(main.size.x, 44)), Color(0, 0, 0, 0.55))
		draw_string(font, main.position + Vector2(18, 32), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, AMBER if live else DIM)
		if cam != null:
			draw_string(font, main.position + Vector2(main.size.x - 360, 32), cam.shot_name().to_upper(),
					HORIZONTAL_ALIGNMENT_RIGHT, 340, 22, CYAN)
		# The order, leader first.
		var order := cam.standings() if cam != null else []
		var box := Rect2(main.position + Vector2(18, main.size.y - 40 - 34 * mini(order.size(), 6)),
				Vector2(380, 34 * mini(order.size(), 6) + 22))
		if not order.is_empty():
			draw_rect(box, Color(0, 0, 0, 0.6))
		for i in mini(order.size(), 6):
			var row: Dictionary = order[i]
			draw_string(font, box.position + Vector2(14, 30 + i * 34), "%d  %s" % [i + 1, str(row.name).to_upper()],
					HORIZONTAL_ALIGNMENT_LEFT, 270, 22, INK if i > 0 else AMBER)
			draw_string(font, box.position + Vector2(280, 30 + i * 34), "LAP %d" % int(row.lap),
					HORIZONTAL_ALIGNMENT_LEFT, -1, 20, DIM)
		if race.has("phase"):
			var people := int(race.get("people", 0))
			draw_string(font, main.position + Vector2(18, 80), "A live race is %s on %s: %d %s." % [
					"forming" if race.phase == "forming" else "running", str(race.name),
					people, "racer" if people == 1 else "racers"], HORIZONTAL_ALIGNMENT_LEFT, -1, 24, AMBER)

	func _draw_world_card(main: Rect2, id: String, world: WorldDef, entry: Dictionary) -> void:
		var y := main.position.y + 80
		draw_string(font, Vector2(main.position.x + 40, y), world.display_name.to_upper() if world else id,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 56, INK)
		y += 60
		if world != null:
			draw_multiline_string(font, Vector2(main.position.x + 40, y), world.description, HORIZONTAL_ALIGNMENT_LEFT,
					main.size.x - 80, 28, -1, DIM)
		y += 160
		var line := PlazaView.heat_text(entry)
		draw_string(font, Vector2(main.position.x + 40, y), line if line != "" else "No news from there yet.",
				HORIZONTAL_ALIGNMENT_LEFT, main.size.x - 80, 30, PlazaView.heat_color(float(entry.get("war", 0.0))))

	func _draw_worlds(main: Rect2, status: Dictionary) -> void:
		var y := main.position.y + 70
		for world in Worlds.raid_worlds():
			var entry: Dictionary = status.get(world.id, {})
			var war := float(entry.get("war", 0.0))
			draw_rect(Rect2(main.position.x + 30, y - 40, 10, 56), PlazaView.heat_color(war))
			draw_string(font, Vector2(main.position.x + 60, y), world.display_name.to_upper(), HORIZONTAL_ALIGNMENT_LEFT,
					-1, 40, INK)
			var line := PlazaView.heat_text(entry)
			draw_string(font, Vector2(main.position.x + 60, y + 34), line if line != "" else "Not running on this server",
					HORIZONTAL_ALIGNMENT_LEFT, main.size.x - 100, 24, PlazaView.heat_color(war) if line != "" else DIM)
			y += 110
			if y > main.end.y:
				break

	func _draw_side(side: Rect2, status: Dictionary, unix: int) -> void:
		draw_rect(side, Color(0.02, 0.05, 0.08, 0.9))
		draw_rect(side, Color(CYAN, 0.6), false, 2.0)
		var y := side.position.y + 40
		draw_string(font, Vector2(side.position.x + 20, y), "BIG MOMENTS", HORIZONTAL_ALIGNMENT_LEFT, -1, 34, CYAN)
		y += 16
		var list := WarRoom.moments(status, unix)
		if list.is_empty():
			y += 36
			draw_string(font, Vector2(side.position.x + 20, y), "Nothing big yet. Watch this space.",
					HORIZONTAL_ALIGNMENT_LEFT, side.size.x - 40, 22, DIM)
		for moment in list.slice(0, WarRoom.MOMENTS_SHOWN):
			y += 40
			var world := Worlds.get_world(str(moment.world))
			var head := "%s  %s" % [(world.display_name if world else str(moment.world)).to_upper(),
					WarRoom.ago(maxi(0, unix - int(moment.get("at", unix))))]
			draw_string(font, Vector2(side.position.x + 20, y), head, HORIZONTAL_ALIGNMENT_LEFT, -1, 22,
					AMBER if str(moment.get("kind", "")) in ["boss", "colossus"] else DIM)
			y += 34
			draw_string(font, Vector2(side.position.x + 20, y), str(moment.text), HORIZONTAL_ALIGNMENT_LEFT,
					side.size.x - 40, 28, INK)
		y = side.position.y + 380
		draw_line(Vector2(side.position.x + 20, y - 40), Vector2(side.end.x - 20, y - 40), Color(CYAN, 0.3), 1.0)
		draw_string(font, Vector2(side.position.x + 20, y), "HUNTED BY THE ARMIES", HORIZONTAL_ALIGNMENT_LEFT, -1, 34, RED)
		var hunted_list := WarRoom.hunted(status)
		if hunted_list.is_empty():
			draw_string(font, Vector2(side.position.x + 20, y + 40), "No army has a grudge right now.",
					HORIZONTAL_ALIGNMENT_LEFT, side.size.x - 40, 22, DIM)
		for i in mini(hunted_list.size(), 4):
			var row: Dictionary = hunted_list[i]
			var world := Worlds.get_world(str(row.world))
			var who := str(row.name).to_upper()
			if str(row.get("clan", "")) != "":
				who = "[%s] %s" % [row.clan, who]
			var by := WarRoom.holder_name(world, str(row.by))
			var color := WarRoom.holder_color(world, str(row.by))
			draw_rect(Rect2(side.position.x + 20, y + 22 + i * 46, 10, 34), color)
			draw_string(font, Vector2(side.position.x + 44, y + 50 + i * 46), "%s   by %s" % [who, by],
					HORIZONTAL_ALIGNMENT_LEFT, side.size.x - 64, 28, INK)

	func _draw_crawl(bar: Rect2, status: Dictionary, now: float) -> void:
		draw_rect(bar, Color(0.05, 0.03, 0.01))
		draw_line(bar.position, bar.position + Vector2(bar.size.x, 0), AMBER, 2.0)
		var parts: Array[String] = []
		for world in Worlds.raid_worlds():
			var line := PlazaView.heat_text(status.get(world.id, {}))
			if line != "":
				parts.append("%s   %s" % [world.display_name.to_upper(), line])
		if parts.is_empty():
			parts.append("THE WORLDS ARE QUIET")
		var text := "      //      ".join(parts) + "      //      "
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
		var shift := fposmod(now * 80.0, maxf(width, 1.0))
		var x := bar.position.x - shift
		while x < bar.end.x:
			draw_string(font, Vector2(x, bar.position.y + 30), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, AMBER)
			x += width


## The race world's track camera: the circuit drawn as a lit ribbon in a
## little 3D world of its own, the AI racers on it, and a camera cutting
## between shots (chasing the leader, over the field, by the side of the
## road). Live from `Race.race_feed` when an AI race runs; otherwise it
## shows exhibition laps on the wall clock, and says so.
class TrackCam:
	extends SubViewport

	## Seconds a shot holds before the camera cuts.
	const SHOT_TIME := 5.0
	const SHOTS: Array[String] = ["chase cam", "over the field", "trackside"]
	## A lap's length in seconds when nothing better is known.
	const LAP_GUESS := 80.0
	const EXHIBITION_FIELD := 6
	const COLORS: Array[Color] = [Color(1.0, 0.62, 0.22), Color(0.35, 0.85, 1.0), Color(1.0, 0.35, 0.6),
			Color(0.5, 1.0, 0.5), Color(0.9, 0.9, 0.3), Color(0.75, 0.55, 1.0), Color(1, 1, 1), Color(1.0, 0.45, 0.2)]

	var active := false
	var live := false
	var track: RaceTrack
	var _world_id := ""
	var _road: MeshInstance3D
	var _cars: Array[MeshInstance3D] = []
	var _camera: Camera3D
	## Racers as shown: name -> {"p" (laps, fractional), "rate" (laps a
	## second), "seen" (unix seconds), "lap"}.
	var _shown := {}

	func _init() -> void:
		size = Vector2i(1260, 560)
		own_world_3d = true
		render_target_update_mode = SubViewport.UPDATE_DISABLED
		var env := WorldEnvironment.new()
		var e := Environment.new()
		e.background_mode = Environment.BG_COLOR
		e.background_color = Color(0.02, 0.03, 0.06)
		e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		e.ambient_light_color = Color(0.4, 0.5, 0.6)
		e.glow_enabled = true
		e.fog_enabled = true
		e.fog_light_color = Color(0.05, 0.08, 0.12)
		e.fog_density = 0.0025
		env.environment = e
		add_child(env)
		var sun := DirectionalLight3D.new()
		sun.rotation = Vector3(-0.9, 0.6, 0)
		sun.light_color = Color(1.0, 0.75, 0.5)
		add_child(sun)
		_camera = Camera3D.new()
		_camera.fov = 50.0
		_camera.far = 3000.0
		add_child(_camera)
		_camera.current = true
		# The salt below, a grid of light out to the dunes.
		var ground := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(2400, 2400)
		ground.mesh = plane
		var gm := StandardMaterial3D.new()
		gm.albedo_color = Color(0.06, 0.05, 0.05)
		ground.mesh.surface_set_material(0, gm)
		ground.position.y = -0.2
		add_child(ground)

	func texture() -> ViewportTexture:
		return get_texture()

	func shot_name() -> String:
		return SHOTS[int(Time.get_unix_time_from_system() / SHOT_TIME) % SHOTS.size()]

	## Shows `world`'s race: the live AI race in `race`, else exhibition laps
	## on its first track.
	func show_world(world: WorldDef, race: Dictionary) -> void:
		if world == null:
			return
		var tracks := world.feed_tracks()
		if tracks.is_empty():
			return
		var want: RaceTrack = tracks[0]
		live = not (race.get("racers", []) as Array).is_empty()
		if live:
			for t in tracks:
				if t.id == str(race.get("track", "")):
					want = t
		elif tracks.size() > 1:
			# No race on: the exhibition visits each circuit in turn.
			want = tracks[int(Time.get_unix_time_from_system() / (WarRoom.SEGMENT_TIME * 3.0)) % tracks.size()]
		if want != track or world.id != _world_id:
			_world_id = world.id
			_set_track(want)
		if live:
			_take_live(race.get("racers", []))

	func _set_track(p_track: RaceTrack) -> void:
		track = p_track
		_shown.clear()
		if _road != null:
			_road.queue_free()
		_road = MeshInstance3D.new()
		_road.mesh = _ribbon(track)
		add_child(_road)

	## The road as a lit ribbon: a dark deck with glowing edges.
	static func _ribbon(t: RaceTrack) -> ArrayMesh:
		var deck := SurfaceTool.new()
		deck.begin(Mesh.PRIMITIVE_TRIANGLES)
		var edge := SurfaceTool.new()
		edge.begin(Mesh.PRIMITIVE_TRIANGLES)
		var n := t.points.size()
		var every := 2
		for i in range(0, n, every):
			var a := t.points[i]
			var b := t.points[(i + every) % n]
			var ra := _across(t, i) * t.width * 0.5
			var rb := _across(t, (i + every) % n) * t.width * 0.5
			_quad(deck, a - ra, a + ra, b + rb, b - rb)
			for s: float in [-1.0, 1.0]:
				var oa := a + ra * s
				var ob := b + rb * s
				var ia := a + ra * s * 0.86
				var ib := b + rb * s * 0.86
				_quad(edge, oa + Vector3.UP * 0.1, ia + Vector3.UP * 0.1, ib + Vector3.UP * 0.1, ob + Vector3.UP * 0.1)
		var mesh := ArrayMesh.new()
		deck.generate_normals()
		mesh = deck.commit(mesh)
		var dm := StandardMaterial3D.new()
		dm.albedo_color = Color(0.16, 0.17, 0.2)
		dm.cull_mode = BaseMaterial3D.CULL_DISABLED
		mesh.surface_set_material(0, dm)
		edge.generate_normals()
		mesh = edge.commit(mesh)
		var em := StandardMaterial3D.new()
		em.albedo_color = Color(0.35, 0.85, 1.0)
		em.emission_enabled = true
		em.emission = Color(0.35, 0.85, 1.0)
		em.emission_energy_multiplier = 1.4
		em.cull_mode = BaseMaterial3D.CULL_DISABLED
		mesh.surface_set_material(1, em)
		return mesh

	static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
		for v: Vector3 in [a, b, c, a, c, d]:
			st.add_vertex(v)

	static func _across(t: RaceTrack, i: int) -> Vector3:
		var n := t.points.size()
		var ahead := (t.points[(i + 1) % n] - t.points[(i - 1 + n) % n])
		ahead.y = 0.0
		return ahead.normalized().cross(Vector3.UP) if ahead.length() > 0.01 else Vector3.RIGHT

	## Where `p` laps round (its fraction) is on the road, and which way.
	func _on_track(p: float, lane: float) -> Transform3D:
		var n := track.points.size()
		var f := fposmod(p, 1.0) * n
		var i := int(f) % n
		var a := track.points[i]
		var b := track.points[(i + 1) % n]
		var at := a.lerp(b, f - int(f))
		var ahead := (b - a).normalized() if a.distance_to(b) > 0.01 else Vector3.FORWARD
		at += _across(track, i) * lane
		return Transform3D(Basis.looking_at(ahead, Vector3.UP), at + Vector3.UP * 0.7)

	## Takes the server's racers: each one's place round the lap, carried on
	## between updates at the pace it was last seen going.
	func _take_live(rows: Array) -> void:
		var now := Time.get_unix_time_from_system()
		var names := {}
		for row: Variant in rows:
			if typeof(row) != TYPE_DICTIONARY:
				continue
			var name := str(row.name)
			names[name] = true
			var p := float(int(row.lap) - 1) + float(row.at)
			var was: Dictionary = _shown.get(name, {})
			if was.is_empty():
				_shown[name] = {"p": p, "rate": 1.0 / LAP_GUESS, "seen": now, "told": p, "lap": int(row.lap)}
				continue
			if not is_equal_approx(float(was.told), p):
				var gap := now - float(was.seen)
				if gap > 0.2 and p > float(was.told):
					was.rate = lerpf(float(was.rate), (p - float(was.told)) / gap, 0.5)
				was.told = p
				was.seen = now
				was.lap = int(row.lap)
				# Ease toward what the server said rather than jumping.
				if absf(float(was.p) - p) > 0.25:
					was.p = p
		for name: Variant in _shown.keys():
			if not names.has(name):
				_shown.erase(name)

	## The racers in order, leader first: {name, lap, p}.
	func standings() -> Array:
		var out: Array = []
		if live:
			for name: Variant in _shown:
				out.append({"name": name, "lap": int(_shown[name].lap), "p": float(_shown[name].p)})
		elif track != null:
			var now := Time.get_unix_time_from_system()
			for i in EXHIBITION_FIELD:
				var p := _exhibition(i, now)
				out.append({"name": Race.AI_NAMES[i % Race.AI_NAMES.size()], "lap": int(fposmod(p, track.laps)) + 1, "p": p})
		out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.p) > float(b.p))
		return out

	## An exhibition racer's laps at `now`: each a little quicker or slower,
	## a little ahead or behind, the same on every screen.
	func _exhibition(i: int, now: float) -> float:
		var lap_time := LAP_GUESS * (1.0 + 0.012 * i)
		return fposmod(now, 3600.0) / lap_time - i * 0.018

	func _process(delta: float) -> void:
		render_target_update_mode = SubViewport.UPDATE_ALWAYS if active and track != null else SubViewport.UPDATE_DISABLED
		if not active or track == null:
			return
		if live:
			for name: Variant in _shown:
				var row: Dictionary = _shown[name]
				# Run on at the pace last seen, and close on where the server said.
				var told := float(row.told) + float(row.rate) * (Time.get_unix_time_from_system() - float(row.seen))
				row.p = lerpf(float(row.p) + float(row.rate) * delta, told, minf(1.0, delta * 2.0))
		var order := standings()
		while _cars.size() < order.size():
			var car := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(2.2, 1.1, 4.6)
			var m := StandardMaterial3D.new()
			var color := COLORS[_cars.size() % COLORS.size()]
			m.albedo_color = color
			m.emission_enabled = true
			m.emission = color
			m.emission_energy_multiplier = 2.5
			box.material = m
			car.mesh = box
			add_child(car)
			_cars.append(car)
		for i in _cars.size():
			_cars[i].visible = i < order.size()
		# Each car keeps its colour by name, so a pass does not swap them.
		var names: Array = order.map(func(r: Dictionary) -> String: return str(r.name))
		var sorted_names := names.duplicate()
		sorted_names.sort()
		for row: Dictionary in order:
			var slot := sorted_names.find(str(row.name))
			var lane := (float(slot % 3) - 1.0) * track.width * 0.25
			_cars[slot].transform = _on_track(float(row.p), lane)
		if order.is_empty():
			return
		_frame(_on_track(float(order[0].p), 0.0), delta)

	func _frame(leader: Transform3D, _delta: float) -> void:
		var shot := shot_name()
		var at := leader.origin
		var ahead := -leader.basis.z
		match shot:
			"chase cam":
				# Down low behind the second car, the leader just ahead.
				var order := standings()
				var chaser := _on_track(float(order[mini(1, order.size() - 1)].p), 0.0)
				var back := -chaser.basis.z
				_camera.global_position = chaser.origin - back * 14.0 + Vector3.UP * 4.0
				_camera.look_at(at.lerp(chaser.origin, 0.4) + Vector3.UP * 1.0, Vector3.UP)
			"over the field":
				# High over the pack, the road curling away under it.
				_camera.global_position = at - ahead * 60.0 + Vector3.UP * 75.0
				_camera.look_at(at + ahead * 10.0, Vector3.UP)
			_:
				# A fixed camera by the road a little ahead of the leader at
				# the start of the shot, panning as the field goes by.
				var start := floorf(Time.get_unix_time_from_system() / SHOT_TIME) * SHOT_TIME
				var order := standings()
				var p0 := float(order[0].p) - (Time.get_unix_time_from_system() - start) / LAP_GUESS + 0.03
				var post := _on_track(p0, track.width * 1.2)
				_camera.global_position = post.origin + Vector3.UP * 3.0
				_camera.look_at(at, Vector3.UP)
