extends RefCounted
## Checks for how Ashfront's scenery army is drawn (`worlds/ashfront/battle.gd`
## `_draw`): every extra shown lands in its side's and pose's batch, where it
## stands, and the batches are filled once a frame. Stand-in meshes take the
## place of the baked far copies, which need a renderer.


static func run(t: Node) -> void:
	print("Battle: drawing the scenery army")
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
	for i in 120:
		raid.map.set_meta("war_intensity", 1.0)
		if i % 4 == 0:
			battle._gather_watchers()
		battle._tick(0.1)
	for army: String in battle.ARMIES:
		var meshes := []
		for p in battle.POSES:
			meshes.append(BoxMesh.new())
		battle.baked[army] = meshes
	battle._build_tracers()
	battle._draw()
	var wanted := 0
	var spots := {}
	for soldier: Dictionary in battle.soldiers():
		if float(soldier.fade) > 0.01:
			wanted += 1
			spots[(soldier.pos as Vector3).snapped(Vector3.ONE * 0.01)] = true
	var drawn := 0
	var placed := true
	# Read back from the buffers handed to the batches: a headless renderer
	# keeps no instance transforms.
	for a in battle._draws.size():
		for p in battle._draws[a].size():
			var multimesh: MultiMesh = battle._draws[a][p]
			var buffer: PackedFloat32Array = battle._buffers[a][p]
			for i in multimesh.visible_instance_count:
				drawn += 1
				var at := Vector3(buffer[i * 16 + 3], buffer[i * 16 + 7], buffer[i * 16 + 11]).snapped(Vector3.ONE * 0.01)
				placed = placed and spots.has(at)
	t.check(wanted > 0 and drawn == wanted, "every extra shown is drawn once (%d of %d)" % [drawn, wanted])
	t.check(placed, "each one where it stands")
	# A second frame refills the same batches rather than adding to them.
	battle._draw()
	var again := 0
	for row: Array in battle._draws:
		for multimesh: MultiMesh in row:
			again += multimesh.visible_instance_count
	t.check(again == drawn, "the next frame draws the same extras again, no more")
	raid.queue_free()
	await t.frames(2)
