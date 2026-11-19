extends RefCounted
## Checks for Ashfront's scenery army (`worlds/ashfront/battle.gd`, DESIGN.md
## "The battle around you"): fights are placed far from everyone, nothing of
## them is shown near a player, a fight a player walks up to ends, the war
## brings more of them, and a round or a shell drops an extra.
## Kept in its own file and called from the test runner.


static func run(t: Node) -> void:
	print("Battle: the scenery army")
	var raid := Raid.new()
	t.add_child(raid)
	raid.start(Worlds.get_world("ashfront"), 42)
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
		bot.set_physics_process(false)
		bot.global_position = Vector3(0, -500, 0)
	raid.player.global_position = raid._stand(Vector3(-190, 0, 30))
	var battle: Node3D = raid.map.call("make_battle")
	raid.map.add_child(battle)
	battle.set_process(false)
	t.check(battle.field < 276.0 and not battle.avoid.is_empty(), "the map keeps the army off the rim and out of its landmarks")
	var me: Vector3 = raid.player.global_position
	_run(battle, raid, 0.0, 6.0)
	var quiet: int = battle.fight_list().size()
	t.check(quiet >= 1 and quiet <= battle.fights.x, "a quiet war has a few fights")
	var far := true
	for fight: Dictionary in battle.fight_list():
		far = far and Vector2(fight.centre.x - me.x, fight.centre.z - me.z).length() >= battle.place_off
	t.check(far, "every fight starts far from the player")
	_run(battle, raid, 1.0, 20.0)
	var live := 0
	for fight: Dictionary in battle.fight_list():
		if not fight.ending:
			live += 1
	t.check(live > quiet, "the hotter the war, the more fights")
	var soldiers: Array = battle.soldiers()
	t.check(soldiers.size() >= live * battle.squad.x * 2 - 4, "each fight is two squads")
	var shown := 0
	var near_shown := false
	for soldier: Dictionary in soldiers:
		if float(soldier.fade) > 0.0:
			shown += 1
			if Vector2(soldier.pos.x - me.x, soldier.pos.z - me.z).length() < battle.keep_off:
				near_shown = true
	t.check(shown > 0 and not near_shown, "extras are shown, but never near the player")
	# A round through one drops it, and only the first on the line.
	var target: Dictionary = {}
	for soldier: Dictionary in soldiers:
		if int(soldier.state) != battle.FALLEN and float(soldier.fade) > 0.9:
			target = soldier
			break
	t.check(not target.is_empty(), "an extra stands to be shot")
	if not target.is_empty():
		var at: Vector3 = target.pos + Vector3(0, 0.7 if target.kneel and int(target.state) == battle.HOLD else 1.0, 0)
		var from := at + (me - at).normalized() * 60.0 + Vector3(0, 0.3, 0)
		var before := _fallen(soldiers)
		battle.shot(from, at + (at - from).normalized() * 200.0)
		t.check(int(target.state) == battle.FALLEN and _fallen(soldiers) == before + 1, "a round through an extra drops it, and only it")
		# A shell drops everyone near where it lands.
		battle.shell_landed(target.pos)
		var spared := true
		for soldier: Dictionary in soldiers:
			if (soldier.pos as Vector3).distance_to(target.pos) < battle.shell_reach and int(soldier.state) != battle.FALLEN:
				spared = false
		t.check(spared, "a shell drops every extra near where it lands")
	# Walking up to a fight ends it, and it starts again elsewhere.
	var fight: Dictionary = battle.fight_list()[0]
	raid.player.global_position = raid._stand(fight.centre)
	_run(battle, raid, 1.0, 1.0)
	t.check(fight.ending, "a fight a player walks up to ends")
	var any_near := false
	for soldier: Dictionary in battle.soldiers():
		if float(soldier.fade) > 0.0 and (soldier.pos as Vector3).distance_to(raid.player.global_position) < battle.keep_off:
			any_near = true
	t.check(not any_near, "and nothing of it shows beside them")
	_run(battle, raid, 1.0, 10.0)
	t.check(not battle.fight_list().has(fight), "it is gone once its soldiers have faded")
	raid.queue_free()
	await t.frames(2)


static func _run(battle: Node3D, raid: Raid, heat: float, seconds: float) -> void:
	for i in int(seconds * 10.0):
		raid.map.set_meta("war_intensity", heat)
		if i % 4 == 0:
			battle._gather_watchers()
		battle._tick(0.1)


static func _fallen(soldiers: Array) -> int:
	var n := 0
	for soldier: Dictionary in soldiers:
		if int(soldier.state) == 2:
			n += 1
	return n
