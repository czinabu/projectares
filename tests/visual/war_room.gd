extends RefCounted
## `--war-room-only`, a mode `visual_check.gd` finds by itself.
## `-- <output_dir> --war-room-only` shoots the Concourse's big screen
## (`WarRoom`) on made-up news: each segment flat, from the tiers, and
## the console in front of it in use.


## Made-up news from the worlds, as a server would send it, for the War Room.
static func war_room_news() -> Dictionary:
	var now := int(Time.get_unix_time_from_system())
	return {
		"ashfront": {"players": 7, "war": 0.65, "level": "Battle", "bounty": 420, "event": "Warlord", "storm": "",
			"wanted": [],
			"front": [
				{"name": "The Foundry", "x": 2, "z": -2, "holder": "tide", "contested": true},
				{"name": "Signal Hill", "x": -150, "z": -118, "holder": "legion", "contested": false},
				{"name": "Rustfall", "x": 158, "z": -106, "holder": "tide", "contested": false},
				{"name": "The Breach", "x": -142, "z": 136, "holder": "players", "contested": false},
				{"name": "Carrier Grave", "x": 134, "z": 132, "holder": "tide", "contested": false}],
			"moments": [{"kind": "boss", "text": "Vex brought down the Ashfront Warlord", "at": now - 140},
				{"kind": "front", "text": "The Tide took The Foundry", "at": now - 400}],
			"hunted": [{"name": "Caleb", "clan": "ARES", "by": "legion"}, {"name": "Nyx", "clan": "", "by": "tide"}],
			"race": {}},
		"frostline": {"players": 2, "war": 0.1, "level": "Quiet", "bounty": 0, "event": "", "storm": "Whiteout",
			"wanted": [], "front": [], "moments": [], "hunted": [], "race": {}},
		"meridian": {"players": 1, "war": 0.0, "level": "Quiet", "bounty": 0, "event": "", "storm": "",
			"wanted": [], "front": [], "moments": [], "hunted": [],
			"race": {"track": "coilrun", "name": "Coilrun", "laps": 3, "racers": [
				{"name": "Vex Morrow", "lap": 2, "at": 0.41, "place": 1}, {"name": "Juno Kade", "lap": 2, "at": 0.39, "place": 2},
				{"name": "Sable Ito", "lap": 2, "at": 0.33, "place": 3}, {"name": "Dax Ferro", "lap": 2, "at": 0.31, "place": 4},
				{"name": "Rook Halloran", "lap": 2, "at": 0.24, "place": 5}]}},
	}


## The War Room: each of the big screen's segments flat, the screen from
## the tiers as the crowd sees it, and the console in front of it in use.
static func shoot(v: Node, out_dir: String, _args: PackedStringArray) -> void:
	var raid := Raid.new()
	v.add_child(raid)
	raid.start(Worlds.social_world(), 5)
	var camera := Camera3D.new()
	camera.far = 1500.0
	camera.fov = 70.0
	v.add_child(camera)
	camera.make_current()
	var news := war_room_news()
	var routes := {"ashfront": 1, "frostline": 2, "meridian": 3}
	var view: CanvasLayer = load("res://core/social/plaza_view.gd").new()
	view.setup(raid, routes, news)
	raid.add_child(view)
	await v._settle(5)
	var room: Node = view.get("war_room")
	if room == null:
		push_error("no War Room was made")
		return
	var wall: Node3D = v.get_tree().get_nodes_in_group("screen_wall")[0]
	var from_tiers := wall.global_position + Vector3(0, -5.0, 26.0)
	var looking := wall.global_position + Vector3(0, -0.8, 0)
	camera.look_at_from_position(from_tiers, looking)
	for focus: String in ["ashfront", "meridian", "frostline", ""]:
		room.set("focus", focus)
		await v._settle(45)
		await RenderingServer.frame_post_draw
		var picture: Image = (room.get("viewport") as SubViewport).get_texture().get_image()
		picture.save_png(out_dir.path_join("war_room_feed_%s.png" % (focus if focus != "" else "worlds")))
		await v._shot(out_dir.path_join("war_room_tiers_%s.png" % (focus if focus != "" else "worlds")))
	# The console, in use, Ashfront picked.
	var console: Node3D = null
	for portal in v.get_tree().get_nodes_in_group("portal"):
		if portal.get_meta("destination", "") == "war_room":
			console = portal
	var mount: Node3D = console.get_node("Screen")
	var screen_view := SubViewport.new()
	screen_view.size = Vector2i(1280, 720)
	screen_view.disable_3d = true
	var shop: Control = (load("res://core/main.gd") as GDScript).ShopView.new()
	var panel: Control = load("res://core/social/war_room_panel.gd").new()
	panel.set("world_status", news)
	panel.set("routes", routes)
	shop.panel = panel
	screen_view.add_child(shop)
	raid.add_child(screen_view)
	var live := WorldScreen.new()
	live.viewport = screen_view
	mount.add_child(live)
	room.set("focus", "ashfront")
	camera.look_at_from_position(console.global_position + Vector3(0, 2.6, 2.4), mount.global_position)
	await v._settle(30)
	await v._shot(out_dir.path_join("war_room_console.png"))
	await RenderingServer.frame_post_draw
	screen_view.get_texture().get_image().save_png(out_dir.path_join("war_room_console_flat.png"))
	camera.queue_free()
	raid.queue_free()
	await v._settle(2)
