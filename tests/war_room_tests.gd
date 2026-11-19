extends RefCounted
## Checks for the War Room, the Concourse's big screen (DESIGN.md section 2,
## "Spectating screens"): what a world tells the plaza of itself for it
## (`Raid.front`, `note_moment`, `hunted`, `Race.race_feed`), how a client
## checks that news, how the screen picks its segments and moments, the
## console that picks a world and deploys, and the screen and console on
## the plaza map. Called from the test runner (`-- --groups WarRoomTests`).

const PlazaMap := preload("res://worlds/plaza/map.gd")
const WarRoomPanel := preload("res://core/social/war_room_panel.gd")
const VisualCheck := preload("res://tests/visual/war_room.gd")


static func run(t: Node) -> void:
	print("War Room")
	_clean(t)
	_segments(t)
	_moments(t)
	_panel(t)
	_hunted(t)
	_tracks(t)
	await _front(t)
	await _plaza(t)


## A world's front: every landmark with its holder, no player's side key,
## and a landmark changing hands is a big moment.
static func _front(t: Node) -> void:
	var raid := Raid.new()
	t.add_child(raid)
	raid.apply_to_profile = false
	raid.start_server(Worlds.get_world("ashfront"), 31)
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
	await t.frames(2)
	var front: Array = raid.status().front
	t.check(front.size() == raid.strongpoints.size() and front.size() >= 5,
			"Ashfront tells the War Room every landmark (%d)" % front.size())
	var holders := front.map(func(site: Dictionary) -> String: return site.holder)
	t.check("legion" in holders and "tide" in holders and "" in holders,
			"each landmark says which army holds it, or nobody (%s)" % [holders])
	var hunter := raid.add_player(["rifle_carbine"] as Array[String], {}, "Holder", "acct-holder", 0)
	await t.frames(1)
	var point: Raid.Strongpoint = raid.strongpoints[0]
	var side: Array = raid.side_of(hunter)
	point.hold(side[0], side[1], true)
	raid._on_strongpoint_taken(point, [hunter] as Array[Actor], "", false)
	var site: Dictionary = raid.status().front[0]
	t.check(site.holder == "players" and not str(site).contains(str(side[0])),
			"a landmark players hold says so, never whose side key it is (%s)" % [site])
	var moments: Array = raid.status().moments
	t.check(not moments.is_empty() and str(moments[0].text).contains(point.title) and moments[0].kind == "front",
			"a landmark changing hands is a big moment (%s)" % [moments])
	for i in Raid.MOMENTS_KEPT + 3:
		raid.note_moment("boss", "Moment %d" % i)
	t.check(raid.moments.size() == Raid.MOMENTS_KEPT and raid.moments[0].text == "Moment %d" % (Raid.MOMENTS_KEPT + 2),
			"a world keeps only its newest few moments, newest first")
	raid.moments[0].at = int(Time.get_unix_time_from_system() - Raid.MOMENT_LIFETIME - 5)
	t.check(raid.live_moments().size() == Raid.MOMENTS_KEPT - 1, "an old moment is no longer news")
	# A warlord brought down is news in the plaza.
	raid.moments.clear()
	var lord: Actor = raid.bots[0]
	raid.warlords[lord] = true
	lord.kill("bullet", hunter)
	await t.frames(2)
	t.check(raid.moments.size() == 1 and raid.moments[0].kind == "boss"
			and str(raid.moments[0].text).begins_with("Holder brought down"),
			"a warlord brought down is a big moment, with who did it (%s)" % [raid.moments])
	raid.queue_free()
	await t.frames(2)


## Who the armies hunt: by name and army, never where, and only once a
## grudge is real.
static func _hunted(t: Node) -> void:
	var plain := Raid.new()
	plain.world = Worlds.get_world("ashfront")
	t.check(plain.hunted().is_empty(), "with no grudges kept nobody is hunted")
	plain.free()
	var raid := Raid.new()
	raid.world = Worlds.get_world("ashfront")
	var marked := Actor.new()
	marked.display_name = "Marked One"
	marked.clan_tag = "ARES"
	var other := Actor.new()
	other.display_name = "Bystander"
	var faint := Actor.new()
	faint.display_name = "Passer-by"
	# Grudges past half the hunt bar count; a faint one does not.
	var bar := raid.world.grudge_hunt
	raid.grudges = {marked: {"legion": bar * 1.3, "tide": bar * 0.2}, other: {"tide": bar * 0.7},
			faint: {"legion": bar * 0.1}}
	var rows := raid.hunted()
	t.check(rows.size() == 2 and rows[0].name == "Marked One" and rows[0].by == "legion" and rows[0].clan == "ARES"
			and rows[1].by == "tide", "the hunted list names each player and the army after them, biggest first (%s)" % [rows])
	t.check(rows.all(func(row: Dictionary) -> bool: return row.keys().size() == 3), "it says who and by whom, never where")
	marked.free()
	other.free()
	faint.free()
	raid.free()


## A client checks the news it is sent.
static func _clean(t: Node) -> void:
	var front := NetSession.clean_front([{"name": "X".repeat(60), "x": 99999, "z": -3, "holder": "tide",
			"contested": "yes"}, "junk", 4])
	t.check(front.size() == 1 and str(front[0].name).length() == 24 and front[0].x == 5000 and not front[0].contested,
			"a front is checked: names cut short, places clamped, junk dropped (%s)" % [front])
	var many := []
	for i in 20:
		many.append({"kind": "boss", "text": "m%d" % i, "at": i})
	t.check(NetSession.clean_moments(many).size() == Raid.MOMENTS_KEPT and NetSession.clean_moments([{"text": " "}]).is_empty(),
			"moments are capped and an empty one is dropped")
	t.check(NetSession.clean_hunted([{"name": "A", "by": "legion", "where": Vector3.ONE}])[0].keys().size() == 3,
			"a hunted row keeps only who, their clan and the army, whatever else is sent")
	var race := NetSession.clean_race({"track": "coilrun", "name": "Coilrun", "laps": 3,
			"racers": [{"name": "Vex", "lap": 2, "at": 4.0, "place": 1}]})
	t.check(race.racers.size() == 1 and race.racers[0].at == 1.0 and NetSession.clean_race("x").is_empty(),
			"a race feed is checked (%s)" % [race])


static func _segments(t: Node) -> void:
	var news := VisualCheck.war_room_news()
	var list := WarRoom.segments(news)
	t.check(list.has("front:ashfront") and list.has("race:meridian") and list.back() == "worlds"
			and not list.has("front:frostline"),
			"the screen turns through each front, each race world and the worlds at a glance (%s)" % [list])
	var at := 1000.0 * WarRoom.SEGMENT_TIME
	t.check(WarRoom.segment_at(news, at) == WarRoom.segment_at(news, at + WarRoom.SEGMENT_TIME * 0.9)
			and WarRoom.segment_at(news, at) != WarRoom.segment_at(news, at + WarRoom.SEGMENT_TIME),
			"segments change on the wall clock, the same on every screen")
	t.check(WarRoom.segment_at(news, at, "ashfront") == "front:ashfront"
			and WarRoom.segment_at(news, at, "meridian") == "race:meridian"
			and WarRoom.segment_at(news, at, "frostline") == "world:frostline",
			"a world picked at the console holds the screen")
	t.check(WarRoom.segments({}) == ["worlds"], "with no news the screen still has something to show")
	var held := WarRoom.holdings(news.ashfront.front)
	t.check(held.tide == 3 and held.legion == 1 and held.players == 1, "who holds the field is counted per side")
	var ash := Worlds.get_world("ashfront")
	t.check(WarRoom.holder_name(ash, "legion") == "The Legion" and WarRoom.holder_name(ash, "") == "Nobody"
			and WarRoom.holder_color(ash, "legion") != WarRoom.holder_color(ash, "tide")
			and WarRoom.holder_color(ash, "players") != WarRoom.holder_color(ash, "legion"),
			"each side has its own name and colour on the screen")


static func _moments(t: Node) -> void:
	var news := VisualCheck.war_room_news()
	var now := int(Time.get_unix_time_from_system())
	var list := WarRoom.moments(news, now)
	var sorted := true
	for i in list.size() - 1:
		sorted = sorted and int(list[i].at) >= int(list[i + 1].at)
	t.check(list.size() >= 2 and sorted and list.all(func(m: Dictionary) -> bool: return m.has("world")),
			"moments from every world come newest first, each with its world")
	# The Colossus falls on the wall clock (`giants.gd`): the War Room tells
	# of it the same way.
	var ash := Worlds.get_world("ashfront")
	var giants: GDScript = load("res://worlds/ashfront/giants.gd")
	var strike := 300000 + int(giants.get_script_constant_map()["LANCE_EVERY"]) * 10 + int(giants.get_script_constant_map()["LANCE_AT"])
	var falling := ash.clock_moments(strike + 30)
	var coming := ash.clock_moments(strike - 60)
	t.check(falling.size() == 1 and str(falling[0].text).contains("Colossus") and int(falling[0].at) == strike,
			"the Colossus's fall is a big moment, timed as every screen draws it (%s)" % [falling])
	t.check(coming.size() == 1 and str(coming[0].text).contains("1:00"), "the lance is counted down (%s)" % [coming])
	t.check(WarRoom.ago(30) == "now" and WarRoom.ago(150) == "2m" and WarRoom.ago(7300) == "2h", "times read short")


## The console: every world to pick, its news, and deploy only where it runs.
static func _panel(t: Node) -> void:
	var news := VisualCheck.war_room_news()
	t.check(WarRoomPanel.choices().size() == Worlds.raid_worlds().size(), "the console offers every world you deploy into")
	var lines := WarRoomPanel.news_lines("ashfront", news)
	t.check(lines.size() >= 4 and lines[1].begins_with("Landmarks held") and lines.any(func(l: String) -> bool:
			return l.contains("hunted by The Legion")), "the console tells a world's news, front and hunted (%s)" % [lines])
	t.check(WarRoomPanel.news_lines("meridian", news).any(func(l: String) -> bool: return l.begins_with("AI race")),
			"and a race world's race")
	var panel: VBoxContainer = WarRoomPanel.new()
	panel.world_status = news
	panel.routes = {"ashfront": 7001}
	t.add_child(panel)
	var asked: Array[String] = []
	var shown: Array[String] = []
	panel.deploy_asked.connect(func(id: String) -> void: asked.append(id))
	panel.picked.connect(func(id: String) -> void: shown.append(id))
	panel.pick("frostline")
	panel._deploy.pressed.emit()
	t.check(asked.is_empty() and panel._deploy.disabled, "a world not running here cannot be deployed to")
	panel.pick("ashfront")
	panel._deploy.pressed.emit()
	t.check(shown == ["frostline", "ashfront"] and asked == ["ashfront"], "a pick shows the world, deploy asks to go there")
	panel.free()


static func _tracks(t: Node) -> void:
	var tracks := Worlds.get_world("meridian").feed_tracks()
	t.check(tracks.size() == 2 and tracks[0].id == "coilrun" and not tracks[0].points.is_empty()
			and not tracks[1].points.is_empty(), "the race world hands the track cam its circuits without its map")
	t.check(Worlds.get_world("ashfront").feed_tracks().is_empty(), "a world without races has none")


## The plaza map: the big screen to draw on and the console before it.
static func _plaza(t: Node) -> void:
	var raid := Raid.new()
	t.add_child(raid)
	raid.start_server(Worlds.social_world(), 5)
	var walls := raid.get_tree().get_nodes_in_group("screen_wall").filter(func(n: Node) -> bool:
		return raid.map.is_ancestor_of(n))
	var console: Node3D = null
	for portal in raid.get_tree().get_nodes_in_group("portal"):
		if raid.map.is_ancestor_of(portal) and portal.get_meta("destination", "") == "war_room":
			console = portal
	t.check(walls.size() == 1 and console != null and console.get_node_or_null("Screen") != null,
			"the plaza has the War Room's screen and a console with its own screen")
	if console != null and walls.size() == 1:
		var wall := walls[0] as Node3D
		var gap := console.global_position - wall.global_position
		t.check(gap.z > 3.0 and gap.z < 14.0 and absf(gap.x) < 2.0, "the console stands in front of the big screen")
	# Headless, the screen itself is never made: it is a view.
	var view: CanvasLayer = load("res://core/social/plaza_view.gd").new()
	view.setup(raid, {}, VisualCheck.war_room_news())
	raid.add_child(view)
	await t.frames(1)
	t.check(view.get("war_room") == null or Look.enabled, "a headless plaza makes no War Room")
	raid.queue_free()
	await t.frames(2)
