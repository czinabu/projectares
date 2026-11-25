extends RefCounted
## The `nameplates_and_scoreboard` checks. The test runner finds this file by itself and calls
## `run(t)`.

const RaidRoster := preload("res://core/ui/raid_roster.gd")
const NameplatesScript := preload("res://core/ui/nameplates.gd")
const ScoreboardScript := preload("res://core/ui/scoreboard.gd")


static func run(t: Node) -> void:
	print("Nameplates and scoreboard")
	t.check(InputMap.has_action("scoreboard") and InputMap.action_get_events("scoreboard").any(
			func(e: InputEvent) -> bool: return e is InputEventKey and e.physical_keycode == KEY_O),
			"O is bound to the scoreboard (Q is the weapon ability)")
	var raid := Raid.new()
	t.add_child(raid)
	raid.start_server(Worlds.get_world("ashfront"), 71)
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
	var a := raid.add_player([], {}, "Alpha")
	var b := raid.add_player([], {}, "Bravo")
	var c := raid.add_player([], {}, "Charlie")
	await t.frames(5)
	var roster := RaidRoster.new(raid, a)
	roster.refresh()
	var board := ScoreboardScript.new()
	board.setup(raid, a)
	raid.add_child(board)
	await t.frames(1)
	t.check(roster.entries.size() == 3 and roster.entries.all(
			func(e: Dictionary) -> bool: return e.status == RaidRoster.IN_RAID),
			"the roster lists every player as in the raid")
	t.check(roster.bots_alive() == raid.bots.size(), "the roster counts the bots still standing")
	b.kill("bullet", a)
	raid._leave(raid.state_for(c))
	await t.frames(3)
	roster.refresh()
	var by_name := {}
	for e in roster.entries:
		by_name[e.name] = e
	t.check(by_name.Alpha.kills == 1 and by_name.Alpha.is_me and by_name.Alpha.status == RaidRoster.IN_RAID,
			"your kills are counted on the scoreboard")
	t.check(by_name.Bravo.status == RaidRoster.DOWN, "a player who died shows as down")
	t.check(by_name.Charlie.status == RaidRoster.LEFT, "a player who left alive shows as left")
	t.check(roster.entries[0].name == "Alpha", "players still in the raid are listed first")

	# Bravo drops back in as a new actor and stays one row on the board.
	var b2 := raid.add_player([], {}, "Bravo")
	raid.bots[0].kill("bullet", b2)
	await t.frames(2)
	roster.refresh()
	t.check(roster.entries.size() == 3 and by_name.Bravo.status == RaidRoster.IN_RAID and by_name.Bravo.kills == 1,
			"a player who drops back in keeps one row on the board")
	b2.kill("bullet", a)
	b = raid.add_player([], {}, "Bravo")
	raid.bots[0].kill("bullet", b)
	b.kill("bullet", a)
	await t.frames(2)
	roster.refresh()
	t.check(roster.entries.size() == 3 and by_name.Bravo.kills == 2 and by_name.Bravo.status == RaidRoster.DOWN
			and by_name.Alpha.kills == 3, "kills add up across a player's lives")

	t.check(not board.visible, "the scoreboard is closed until asked for")
	board.show_board(true)
	var rows: Array = board.rows()
	t.check(board.visible and rows.size() == 3 and rows[0].slice(0, 3) == ["Alpha (you)", RaidRoster.IN_RAID, "3"],
			"the scoreboard shows each player's name, status and kills")
	board.show_board(false)
	t.check(not board.visible, "the scoreboard closes again")

	# Nameplates, high above the map so only the test's own wall can block the view.
	var d := raid.add_player([], {}, "Delta")
	var camera := Camera3D.new()
	raid.add_child(camera)
	camera.make_current()
	var plates := NameplatesScript.new()
	plates.setup(raid, a)
	raid.add_child(plates)
	var sky := a.global_position + Vector3(0, 120, 0)
	var place := func(d_offset: Vector3, facing: Vector3) -> void:
		a.global_position = sky
		d.global_position = sky + d_offset
		b.global_position = sky + Vector3(0, 0, -5)
		camera.global_position = sky + Vector3(0, 1.6, 0)
		camera.look_at(camera.global_position + facing)
		plates.update_plates()
	place.call(Vector3(0, -0.5, -10), Vector3.FORWARD)
	var shown: Dictionary = plates.plates()
	t.check(shown.has(d.get_instance_id()) and not shown.has(a.get_instance_id()),
			"another player in view gets a nameplate, you do not")
	t.check(not shown.has(b.get_instance_id()), "a player who is down has no nameplate")
	if shown.has(d.get_instance_id()):
		var plate: Control = shown[d.get_instance_id()]
		var label: Label = plate.get_child(0)
		var middle := camera.get_viewport().get_visible_rect().size * 0.5
		t.check(label.text == "Delta  Recruit" and plate.position.x < middle.x and plate.position.x + plate.size.x > middle.x,
				"the nameplate carries the name and rank and sits over the player")
	place.call(Vector3(0, -0.5, -10), Vector3.BACK)
	t.check(plates.plates().is_empty(), "no nameplate for a player behind you")
	place.call(Vector3(0, -0.5, -(plates.max_distance + 5.0)), Vector3.FORWARD)
	t.check(plates.plates().is_empty(), "no nameplate past the nameplate range")
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = Vector3(6, 6, 0.5)
	wall.add_child(shape)
	raid.add_child(wall)
	wall.global_position = sky + Vector3(0, 1, -5)
	await t.frames(1)
	place.call(Vector3(0, -0.5, -10), Vector3.FORWARD)
	t.check(plates.plates().is_empty(), "no nameplate through a wall")
	wall.queue_free()
	await t.frames(1)
	d.kill("bullet")
	place.call(Vector3(0, -0.5, -10), Vector3.FORWARD)
	t.check(plates.plates().is_empty(), "the nameplate goes when the player goes down")
	await t._end_raid(raid)
