extends RefCounted
## Checks for Ashfront's scenery army (`worlds/ashfront/battle.gd`, DESIGN.md
## "The battle around you"): fights stand only on the battle shelves past the
## rim, where no one can go, and are seen over it; they are placed far from everyone, nothing of
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
	t.check(not battle.shelves.is_empty() and not battle.flats.is_empty(), "the map gives the army its battle shelves")
	var me: Vector3 = raid.player.global_position
	_run(battle, raid, 0.0, 6.0)
	_out_of_reach(t, raid, battle)
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
	_low_sky(t, raid, battle)
	raid.queue_free()
	await t.frames(2)


## The busy low sky (`worlds/ashfront/lowsky.gd`): gunships rake only the
## scenery army, never near a player, and leave; the fight shoots back up;
## fighters go over; a dropship comes down past the rim.
static func _low_sky(t: Node, raid: Raid, battle: Node3D) -> void:
	raid.player.global_position = raid._stand(Vector3(-190, 0, 30))
	_run(battle, raid, 1.0, 6.0)
	var sky: Node3D = raid.map.call("make_low_sky", battle)
	raid.map.add_child(sky)
	sky.set_process(false)
	t.check(sky.gap_at(sky.GUNSHIP_GAP, 1.0) < sky.gap_at(sky.GUNSHIP_GAP, 0.0)
			and sky.gap_at(sky.WRECK_GAP, 1.0) < sky.gap_at(sky.WRECK_GAP, 0.0)
			and sky.gunships_at(1.0) > sky.gunships_at(0.0), "the hotter the war, the busier the sky")
	var run: Dictionary = sky.send_gunship()
	var on_fight := false
	for fight: Dictionary in battle.fight_list():
		on_fight = on_fight or (fight.centre as Vector3).distance_to(Vector3(run.target.x, fight.centre.y, run.target.z)) < 1.0
	t.check(on_fight, "a gunship runs in over a scenery fight")
	var landed := 0
	var up := 0
	var near := false
	var me: Vector3 = raid.player.global_position
	var seen := {}
	for i in 500:
		raid.map.set_meta("war_intensity", 1.0)
		if i % 4 == 0:
			battle._gather_watchers()
		sky._tick_gunships(0.1, 1.0)
		for tracer: Dictionary in sky._tracers:
			if seen.has(tracer):
				continue
			seen[tracer] = true
			if tracer.lands:
				landed += 1
				near = near or Vector2(tracer.to.x - me.x, tracer.to.z - me.z).length() < battle.keep_off
			elif (tracer.dir as Vector3).y > 0.0:
				up += 1
		sky._tick_tracers(0.1)
	t.check(landed > 20 and not near, "it strafes the fight, never near the player")
	t.check(up > 5, "and the fight shoots back up at it")
	t.check(sky._gunships.is_empty(), "and it flies on and away")
	var pair: Dictionary = sky.send_fighters()
	var closest := INF
	for i in 200:
		sky._tick_pairs(0.1)
		if not sky._pairs.is_empty():
			var lead: Vector3 = sky.lead_at(pair)
			closest = minf(closest, Vector2(lead.x, lead.z).length())
	t.check(closest < sky.FIGHTER_PASS + 60.0 and sky._pairs.is_empty(), "fighters go over in pairs and away")
	var wreck: Dictionary = sky.drop_wreck()
	t.check(Vector2(wreck.to.x, wreck.to.z).length() > sky.field, "a hit dropship comes down past the rim, where nobody stands")
	for i in int((float(wreck.time) + 1.0) * 10.0):
		sky._tick_wrecks(0.1)
	t.check(wreck.down, "it falls burning and crashes")
	for i in int(sky.WRECK_BURNS * 10.0) + 5:
		sky._tick_wrecks(0.1)
	t.check(sky._wrecks.is_empty(), "and its wreck burns out")
	sky.queue_free()


## Caleb's call: no fake soldier stands anywhere a player can go, so none
## ever vanishes in front of one. Every extra is past the map's edge walls,
## on the far land (`scenery_height`), and the shelves rise high enough to
## be seen over the rim from the middle of the field.
static func _out_of_reach(t: Node, raid: Raid, battle: Node3D) -> void:
	var map: Node = raid.map
	var walls := float(map.terrain.extent()) * 0.5 - 6.0
	var outside := true
	var grounded := true
	for soldier: Dictionary in battle.soldiers():
		var pos: Vector3 = soldier.pos
		outside = outside and maxf(absf(pos.x), absf(pos.z)) > walls + 20.0
		grounded = grounded and absf(pos.y - float(map.call("scenery_height", pos.x, pos.z))) < 0.5
	t.check(not battle.soldiers().is_empty() and outside, "every extra stands past the map's walls, where no one can go")
	t.check(grounded, "and stands on the far land")
	# From eye height in the middle, over the rim's crest along each shelf.
	var eye := float(map.call("ground_height", 0.0, 0.0)) + 1.7
	var seen := true
	for shelf: Dictionary in battle.shelves:
		var out: Vector2 = shelf["out"]
		var lateral: Vector2 = shelf["lateral"]
		var along := Vector2(-out.y, out.x)
		var l := (lateral.x + lateral.y) * 0.5
		var crest := -INF
		for d in range(200, int(walls) + 8, 2):
			var p := out * d + along * l
			var h := float(map.call("scenery_height", p.x, p.y))
			if (h - eye) / d > crest:
				crest = (h - eye) / d
		for flat: Vector2 in battle.flats:
			var mid := out * ((flat.x + flat.y) * 0.5) + along * l
			var h := float(map.call("scenery_height", mid.x, mid.y)) + 1.0
			seen = seen and (h - eye) / mid.length() > crest
	t.check(seen, "every shelf's flats are seen over the rim from the middle of the field")


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
