extends RefCounted
## The `online` checks. The test runner finds this file by itself and calls
## `run(t)`.

const RaidRoster := preload("res://core/ui/raid_roster.gd")
const NET_ACCOUNTS := "user://test_accounts_net"


static func run(t: Node) -> void:
	print("Online: commands and raids with several players")
	var cmd := ActorCommand.new()
	cmd.move = Vector2(0.5, -1.0)
	cmd.yaw = 1.25
	cmd.pitch = -0.4
	cmd.aim_dir = Vector3(0, 0, -1)
	cmd.sprint = true
	cmd.primary = true
	cmd.dash = true
	cmd.ability_pressed = true
	cmd.stance = 2
	cmd.switch_weapon = 1
	var copy := ActorCommand.new()
	copy.apply_array(cmd.to_array())
	t.check(copy.move.is_equal_approx(cmd.move) and is_equal_approx(copy.yaw, 1.25)
			and copy.sprint and copy.primary and copy.dash and copy.ability_pressed
			and not copy.jump and not copy.heal_pressed and copy.stance == 2 and copy.switch_weapon == 1,
			"a command survives the trip through its network form")
	cmd.watch_up = true
	var packed: Array = NetSession.unpack_inputs(NetSession.pack_inputs([[1, cmd.to_array(), 0]]))[0][1]
	copy.apply_array(packed)
	t.check(copy.watch_up and int(packed[ActorCommand.FLAGS_INDEX]) & ActorCommand.HELD_MASK & ActorCommand.FLAG_WATCH_UP != 0,
			"a raised watch travels with the held keys, so others see it")
	copy.apply_array([99.0, 99.0, "x", 50.0, NAN, 0.0, 0.0, 0, 7, 99])
	t.check(copy.move == Vector2.ONE and is_zero_approx(copy.yaw) and copy.pitch <= 1.5
			and copy.aim_dir == Vector3.ZERO and copy.stance == 2 and copy.switch_weapon <= 8,
			"a command from the network is clamped to legal values")
	# The server must play the very move the client predicted with. A
	# keyboard diagonal is (1, 1), and riding with throttle and steer held is
	# exactly that; shortened on the way, the server rode a slower, wider turn.
	var diagonal := ActorCommand.new()
	for move: Vector2 in [Vector2(1, 1), Vector2(0.7, 1), Vector2(-0.5, 1), Vector2(-1, -1)]:
		diagonal.move = move
		var sent: Array = NetSession.unpack_inputs(NetSession.pack_inputs([[1, diagonal.to_array(), 0]]))[0][1]
		copy.apply_array(sent)
		t.check(copy.move.is_equal_approx(move), "a move of %s reaches the server as the client predicted it (%s)" % [move, copy.move])
	cmd.switch_weapon = ActorCommand.HOLSTER
	copy.apply_array(cmd.to_array())
	t.check(copy.switch_weapon == ActorCommand.HOLSTER, "putting the weapon away survives the network form")
	cmd.switch_weapon = 1
	copy.apply_array([1.0])
	t.check(copy.stance == 2, "a malformed command is ignored")
	t.check(cmd.flags() & ActorCommand.ONE_SHOT_MASK != 0 and cmd.flags() & ActorCommand.HELD_MASK != 0
			and ActorCommand.ONE_SHOT_MASK & ActorCommand.HELD_MASK == 0, "held keys and presses are told apart")

	# A server raid with two players, no network involved.
	Profile.reset()
	Profile.welcome_granted = true
	var raid := Raid.new()
	t.add_child(raid)
	raid.start_server(Worlds.get_world("ashfront"), 70)
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
	t.check(raid.player == null and raid.players.is_empty() and raid.bots.size() == raid.world.bot_count + raid._bosses.size() + raid._guards.size(),
			"a server raid starts with bots and no players")
	var a := raid.add_player([], {}, "Alpha")
	var b := raid.add_player(["rifle_carbine", "blade_scrap", "jetpack_mk1", "plate_light"], {}, "Bravo")
	await t.frames(20)
	t.check(raid.players.size() == 2 and a.weapons.size() == 3 and b.weapons[0].display_name == "Ashfront Carbine"
			and not a.is_player, "players join a server raid with their own kits")
	var finished := []
	raid.player_finished.connect(func(actor: Actor, result: Dictionary) -> void: finished.append([actor, result]))
	b.kill("bullet", a)
	await t.frames(5)
	t.check(finished.size() == 1 and finished[0][0] == b and finished[0][1].outcome == "died"
			and "rifle_carbine" in finished[0][1].lost, "a player who dies gets their own result")
	t.check(raid.state_for(a).kills == 1 and not a.is_dead and raid.active_players() == ([a] as Array[Actor]),
			"the raid carries on for the others, and the kill is credited")
	var b_again := raid.add_player([], {}, "Bravo")
	t.check(raid.active_players().size() == 2 and b_again.protected_left > 0.0
			and b_again.global_position.distance_to(a.global_position) > 10.0,
			"the dead player drops back in, protected and away from the others")
	var banked := []
	raid.player_banked.connect(func(actor: Actor, items: Array) -> void: banked.append([actor, items]))
	b_again.inventory.add_item("alloy_ingot")
	var depot := raid.depots[0]
	b_again.global_position = Vector3(depot.global_position.x, depot.global_position.y - 1.8, depot.global_position.z)
	await t.frames(int(raid.world.depot_hold_time * 60.0) + 30)
	t.check(banked.size() == 1 and banked[0][0] == b_again and banked[0][1] == ["alloy_ingot"]
			and not b_again.inventory.has_item("alloy_ingot"),
			"a depot works for players on a server, and reports what was banked")
	# A dropped connection leaves the body standing until its sign-out ends.
	b_again.cmd.move = Vector2(0, 1)
	raid.remove_player(b_again)
	t.check(not b_again.is_dead and raid.sign_out_progress(b_again) >= 0.0 and b_again.cmd.move == Vector2.ZERO,
			"a player who disconnects leaves a helpless body behind")
	raid.cancel_sign_out(b_again)
	Combat.deal(b_again, DamageInfo.make(5.0, a, "bullet"))
	t.check(raid.sign_out_progress(b_again) >= 0.0, "that sign-out cannot be called off, by them or by a hit")
	var wait_before: float = raid.state_for(b_again).sign_out_left
	raid.remove_player(b_again)
	t.check(raid.state_for(b_again).sign_out_left <= wait_before, "asking twice never makes the wait longer")
	# Back before it ran out (a reconnect): the body is theirs again.
	t.check(raid.is_unguarded(b_again), "a body left by a drop can be taken back")
	t.check(raid.reclaim_player(b_again) and raid.sign_out_progress(b_again) < 0.0
			and not raid.state_for(b_again).sign_out_forced and not raid.is_unguarded(b_again),
			"a player back in time takes the body over; the forced countdown ends (they were hit, so nothing resumes)")
	t.check(not raid.reclaim_player(b_again), "a body someone plays cannot be reclaimed")
	# A sign-out they had started carries on when they come back.
	raid.state_for(b_again).last_combat = -INF
	t.check(raid.begin_sign_out(b_again), "a quiet player starts signing out")
	raid.state_for(b_again).sign_out_left -= 4.0
	var left_before: float = raid.state_for(b_again).sign_out_left
	raid.remove_player(b_again)
	raid.state_for(b_again).sign_out_left -= 1.0
	raid.reclaim_player(b_again)
	var resumed := raid.state_for(b_again)
	t.check(resumed.sign_out_left > 0.0 and resumed.sign_out_left <= left_before - 1.0 + 0.01
			and not resumed.sign_out_forced and resumed.sign_out_total == raid.world.sign_out_time,
			"their own sign-out resumes where it stands after a reconnect, the gap counted (%.1f s left)" % resumed.sign_out_left)
	raid.cancel_sign_out(b_again)
	t.check(raid.sign_out_progress(b_again) < 0.0, "and it is theirs to call off again")
	raid.remove_player(b_again)
	b_again.kill("bullet", a)
	await t.frames(2)
	t.check(finished.size() == 2 and finished[1][1].outcome == "died" and raid.state_for(a).kills == 2,
			"a body that is killed before its sign-out ends is a death")
	finished.remove_at(1)
	t.check(Profile.stash.is_empty() and Profile.raids_played == 0, "a server raid never touches a profile")
	a.inventory.add_item("scrap_metal")
	raid._leave(raid.state_for(a))
	await t.frames(2)
	t.check(finished.size() == 2 and finished[1][1].outcome == "left"
			and "scrap_metal" in finished[1][1].brought_home, "a player who leaves gets a result listing what comes home")
	Raid.apply_result(finished[1][1])
	t.check("scrap_metal" in Profile.stash and Profile.raids_extracted == 1, "the result can be applied to the player's own profile")
	await t._end_raid(raid)
	Profile.reset()

	# Containers and vehicles are announced, so a server can replicate them.
	raid = Raid.new()
	t.add_child(raid)
	var announced := {"containers": 0, "vehicles": 0, "removed": 0}
	raid.container_spawned.connect(func(_c: LootContainer) -> void: announced.containers += 1)
	raid.vehicle_spawned.connect(func(_v: Node3D) -> void: announced.vehicles += 1)
	raid.vehicle_removed.connect(func(_v: Node3D) -> void: announced.removed += 1)
	raid.start_server(Worlds.get_world("ashfront"), 71)
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
	var map_vehicles := raid.vehicles.size()
	t.check(announced.containers > 3 and announced.vehicles == map_vehicles, "a server raid announces its caches and vehicles")
	var rider := raid.add_player(raid.world.starter_loadout() + (["bike_scrapper"] as Array[String]), {}, "Rider")
	await t.frames(10)
	t.check(raid.vehicles.size() == map_vehicles and raid.state_for(rider).deployed_vehicles == (["bike_scrapper"] as Array[String])
			and raid.stowed_for(rider) == (["bike_scrapper"] as Array[String]),
			"a player who brings a vehicle to a server raid has it on their watch")
	raid.state_for(rider).stowed.clear()
	var own_bike: Node3D = raid.spawn_vehicle("bike_scrapper", rider.global_position + Vector3(2.5, 0.3, 0), 0.0)
	t.check(own_bike.call("mount", rider), "they can ride it")
	var outcome := [{}]
	raid.player_finished.connect(func(_a: Actor, r: Dictionary) -> void: outcome[0] = r)
	var bags_before: int = announced.containers
	raid._leave(raid.state_for(rider))
	await t.frames(3)
	t.check("bike_scrapper" in outcome[0].get("brought_home", []) and announced.removed == 1
			and (not is_instance_valid(own_bike) or own_bike not in raid.vehicles), "leaving on a vehicle takes it home and out of the raid")
	t.check(announced.containers == bags_before, "leaving alive drops no loot bag")
	await t._end_raid(raid)

	print("Online: a real server and two clients")
	t._wipe_dir(NET_ACCOUNTS)
	var port := 24811
	var pid: int = t._start_server(port, [])
	t.check(pid > 0, "a dedicated server process starts")
	var alpha: NetSession = await t._join("Alpha", port)
	t.check(alpha != null, "a client connects and joins the raid")
	if alpha == null:
		OS.kill(pid)
		return
	var world := Worlds.get_world("ashfront")
	t.check(alpha.raid.mode == Raid.Mode.CLIENT and alpha.raid.player.weapons.size() == 3
			and alpha.raid.player.is_player and not Combat.authoritative,
			"the client has its own actor and leaves damage to the server")
	await t._wait_until(func() -> bool: return alpha.raid.bots.size() == world.bot_count, 180)
	t.check(alpha.raid.bots.size() == world.bot_count + alpha.raid._map_nodes("spawn_boss").size(),
			"the client sees the server's bots")
	# Interest: the client hears about itself and what is near in every
	# update, and about the far side of the field a fraction as often.
	await t.frames(30)
	alpha.entries_received.clear()
	# Counted in the server's updates, not in time: a server sharing a busy
	# machine sends fewer a second, and the shares are what matter.
	await t._wait_until(func() -> bool: return int(alpha.entries_received.get(alpha.my_actor_id, 0)) >= 60, 900)
	var own_updates := int(alpha.entries_received.get(alpha.my_actor_id, 0))
	var heard := 0
	var seldom := 0
	var far_bots := 0
	var thinned := 0
	for bot in alpha.raid.bots:
		var updates := int(alpha.entries_received.get(alpha._ids.get(bot, -1), 0))
		heard += updates
		if bot.global_position.distance_to(alpha.raid.player.global_position) > NetSession.MID_RANGE + 10.0:
			far_bots += 1
			if updates >= 2 and updates <= own_updates / 4:
				seldom += 1
			if bot.tick_every > 1:
				thinned += 1
	t.check(own_updates >= 60, "a client hears about its own player in every update (%d updates)" % own_updates)
	t.check(far_bots >= 10 and seldom == far_bots,
			"and about bots across the field only now and then (%d of %d far bots)" % [seldom, far_bots])
	t.check(heard < world.bot_count * own_updates / 2,
			"so a big field costs a fraction of the traffic (%d bot updates, %d if all were sent)"
			% [heard, world.bot_count * own_updates])
	t.check(thinned == far_bots, "the client also simulates far bots in longer steps (%d of %d)" % [thinned, far_bots])
	var bravo: NetSession = await t._join("Bravo", port)
	t.check(bravo != null, "a second client joins the same raid")
	if bravo != null:
		var see_each_other := func() -> bool:
			return bravo.actor_for(alpha.my_actor_id) != null and alpha.actor_for(bravo.my_actor_id) != null
		await t._wait_until(see_each_other, 180)
		var seen := bravo.actor_for(alpha.my_actor_id)
		t.check(seen != null and seen.display_name == "Alpha" and seen.weapons.size() == 3 and not seen.is_player,
				"each client sees the other player, with their name and gear")
		t.check(bravo.raid.players.size() == 2 and bravo.raid.active_players().size() == 2
				and alpha.raid.bots.size() == world.bot_count + alpha.raid._map_nodes("spawn_boss").size(),
				"a client's raid lists the players, separate from the bots (%d players, %d bots for %d)"
				% [bravo.raid.players.size(), alpha.raid.bots.size(), world.bot_count + alpha.raid._map_nodes("spawn_boss").size()])
		if seen != null:
			var from := seen.global_position
			# Walk where there is room, so nothing knocks the two screens apart.
			var walker := alpha.raid.player
			walker.cmd.yaw = t._yaw_toward(t._clear_run(walker, walker.global_position, Vector3.FORWARD, 14.0))
			await t.frames(10)
			walker.cmd.move = Vector2(0, 1)
			await t.frames(90)
			alpha.raid.player.cmd.move = Vector2.ZERO
			# On a busy machine the server can be a moment behind the walker.
			await t._wait_until(func() -> bool: return from.distance_to(seen.global_position) > 3.0, 240)
			await t.frames(30)
			var moved := from.distance_to(seen.global_position)
			t.check(moved > 3.0, "one player's movement reaches the other through the server (%.1f m)" % moved)
			# The server may still be playing the last inputs on a busy machine
			# (a CI runner has been seen 5 m behind after two seconds), so give
			# it time to catch up before judging.
			var agree := func() -> bool:
				return seen.global_position.distance_to(alpha.raid.player.global_position) < 2.0
			await t._wait_until(agree, 360)
			var apart := seen.global_position.distance_to(alpha.raid.player.global_position)
			t.check(apart < 2.0, "both clients agree where that player is (%.2f m apart)" % apart)
		var roster := RaidRoster.new(bravo.raid, bravo.raid.player)
		roster.refresh()
		var names := roster.entries.map(func(e: Dictionary) -> String: return e.name)
		t.check(roster.entries.size() == 2 and "Alpha" in names and "Bravo" in names
				and roster.entries.all(func(e: Dictionary) -> bool: return e.status == RaidRoster.IN_RAID),
				"a client's scoreboard lists both players and none of the bots")
	await t._leave(bravo)
	await t._leave(alpha)
	OS.kill(pid)
	await t.frames(30)

	print("Online: fighting through the server")
	port = 24812
	pid = t._start_server(port, ["--bots", "0", "--squad-spawn"])
	alpha = await t._join("Alpha", port, {"vehicle": "bike_scrapper"})
	bravo = await t._join("Bravo", port) if alpha != null else null
	t.check(alpha != null and bravo != null, "two clients join a squad-spawn server")
	if alpha != null and bravo != null:
		await t._wait_until(func() -> bool: return alpha.actor_for(bravo.my_actor_id) != null, 180)
		# Alpha walks back from the bike to Bravo and then to the bag, and the
		# drop point's wall can stand between: it finds the way round.
		await t._lay_navigation(alpha)
		var me := alpha.raid.player
		var target := alpha.actor_for(bravo.my_actor_id)
		var victim := bravo.raid.player
		# Measured before Alpha walks off to the bike and rides it.
		var spawn_gap := me.global_position.distance_to(target.global_position) if target != null else INF
		var face := func(point: Vector3) -> void:
			var aim := point - me.get_eye_position()
			me.cmd.aim_dir = aim.normalized()
			me.cmd.yaw = atan2(-aim.x, -aim.z)
			me.cmd.pitch = asin(clampf(aim.normalized().y, -1.0, 1.0))
		var press_use := func() -> void:
			me.cmd.interact_pressed = true
			await t.frames(1)
			me.cmd.interact_pressed = false

		# Loot caches and the bike Alpha brought exist on both clients.
		await t._throw_own_bike(alpha)
		await t._wait_until(func() -> bool: return not alpha.vehicles().is_empty() and not bravo.vehicles().is_empty(), 120)
		t.check(alpha.containers().size() > 3 and alpha.containers().size() == bravo.containers().size(),
				"both clients see the server's loot caches (%d)" % alpha.containers().size())
		t.check(alpha.vehicles().size() >= 1 and bravo.vehicles().size() == alpha.vehicles().size(),
				"both clients see the vehicle a player brought")
		var bike: Node3D = null
		for v: Node3D in alpha.vehicles():
			if bike == null or v.global_position.distance_to(me.global_position) \
					< bike.global_position.distance_to(me.global_position):
				bike = v
		if bike != null:
			var their_bike: Node3D = null
			for v: Node3D in bravo.vehicles():
				if v.global_position.distance_to(bike.global_position) < 1.5:
					their_bike = v
			face.call(bike.global_position + Vector3(0, 0.6, 0))
			await t.frames(6)
			await press_use.call()
			await t._wait_until(func() -> bool: return me.vehicle == bike, 90)
			t.check(me.vehicle == bike and bike.get("rider") == me, "pressing use on the bike mounts it, by the server's say")
			var bike_from := bike.global_position
			me.cmd.move = Vector2(0, 1)
			await t.frames(30)
			me.cmd.move = Vector2.ZERO
			await t.frames(10)
			t.check(bike.global_position.distance_to(bike_from) > 0.5
					and me.global_position.distance_to(bike.global_position) < 1.5,
					"the server drives the bike and the rider goes with it")
			var seen_rider := bravo.actor_for(alpha.my_actor_id)
			# The bike is still rolling to a stop, and the other client's view
			# of it trails by a few ticks: up to 2.9 m at this speed. Let it
			# come to rest before comparing.
			var same_ride := func() -> bool:
				return their_bike != null and their_bike.get("rider") == seen_rider \
						and their_bike.global_position.distance_to(bike.global_position) < 1.5
			await t._wait_until(same_ride, 120)
			t.check(same_ride.call(), "the other client sees the same player riding the same bike")
			await press_use.call()
			await t._wait_until(func() -> bool: return me.vehicle == null, 90)
			t.check(me.vehicle == null and bike.get("rider") == null, "pressing use again gets off")
			await t.frames(20)
		t.check(alpha.raid.bots.is_empty() and target != null and spawn_gap < 12.0,
				"squad spawn puts the players together (%.1f m apart)" % spawn_gap)
		var hits := [0]
		var notices: Array[String] = []
		me.hit_confirmed.connect(func(_t: Actor, _i: DamageInfo, _l: bool) -> void: hits[0] += 1)
		me.notice.connect(func(text: String) -> void: notices.append(text))
		var picked: Array[String] = []
		me.looted.connect(func(ids: Array[String]) -> void: picked.append_array(ids))
		var result := [{}]
		bravo.run_finished.connect(func(r: Dictionary) -> void: result[0] = r)
		var before := victim.health.health + victim.health.armor
		var war_feed: Array[String] = []
		bravo.raid.war_feed.connect(func(text: String) -> void: war_feed.append(text))
		me.cmd.primary = true
		for i in 600:
			if target == null or not is_instance_valid(target) or target.is_dead or not result[0].is_empty():
				break
			var aim := (target.global_position + Vector3(0, 1.1, 0)) - me.get_eye_position()
			me.cmd.aim_dir = aim.normalized()
			me.cmd.yaw = atan2(-aim.x, -aim.z)
			# Close in, round the drop point's wall if it is in the way, so
			# nothing on the map sits between them.
			me.cmd.move = t._move_toward(me, target.global_position) if aim.length() > 4.0 else Vector2.ZERO
			if i % 40 == 39:
				me.cmd.reload_pressed = true
			await t.frames(1)
			me.cmd.reload_pressed = false
		me.cmd.primary = false
		me.cmd.move = Vector2.ZERO
		t.check(hits[0] > 0, "the shooter is told about hits the server confirmed (%d)" % hits[0])
		await t._wait_until(func() -> bool: return not result[0].is_empty(), 240)
		t.check(victim.health.health + victim.health.armor < before or victim.is_dead,
				"the victim's health drops on their own screen")
		t.check(result[0].get("outcome", "") == "died" and not result[0].get("lost", []).is_empty(),
				"the server tells a player their run is over and what they lost")
		await t._wait_until(func() -> bool: return victim.is_dead, 60)
		t.check(victim.is_dead, "the dead player falls on their own screen")
		t.check(notices.any(func(text: String) -> bool: return text.begins_with("Killed ")),
				"the killer gets the kill notice from the server")
		var scores := func() -> bool:
			var mine := alpha.raid.state_for(me)
			var theirs := bravo.raid.state_for(bravo.actor_for(alpha.my_actor_id))
			return mine != null and mine.kills == 1 and theirs != null and theirs.kills == 1
		await t._wait_until(scores, 90)
		t.check(scores.call() and alpha.raid.kills == 1, "every client is told each player's kill count")
		var famous := func() -> bool:
			var seen := bravo.actor_for(alpha.my_actor_id)
			return me.renown > 0 and seen != null and seen.renown == me.renown and seen.streak == 1
		await t._wait_until(famous, 90)
		t.check(famous.call(), "the server tells every client the killer's renown (%d)" % me.renown)
		t.check(war_feed.any(func(text: String) -> bool: return " killed " in text),
				"the kill is announced to everyone in the world (%s)" % " / ".join(war_feed))
		# The dead player's bag appears for the killer, who walks over and loots it.
		var found: Array[LootContainer] = []
		var find_bag := func() -> bool:
			for c: Variant in alpha.containers():
				if is_instance_valid(c) and c.is_bag and found.is_empty():
					found.append(c)
			return not found.is_empty()
		await t._wait_until(find_bag, 120)
		var bag: LootContainer = found[0] if not found.is_empty() else null
		t.check(bag != null and not bag.items.is_empty(), "the dead player's bag appears on the killer's screen")
		if bag != null:
			var bag_id := bag.get_instance_id()
			var carried := me.inventory.items.size()
			var looted := func() -> bool: return me.inventory.items.size() > carried
			# The server loots whatever the eyes' ray meets first, like a
			# player's use key. The bike ridden earlier, or a bump in the
			# ground, can stand between the looter and the bag, so press only
			# while the ray is on the bag, and step round it until it is.
			var in_way := "nothing"
			var gap := 99.0
			for i in 600:
				if looted.call() or not is_instance_valid(bag):
					break
				face.call(bag.global_position + Vector3(0, 0.3, 0))
				gap = Vector2(bag.global_position.x - me.global_position.x,
						bag.global_position.z - me.global_position.z).length()
				var aimed := me.find_interactable()
				var on_bag := aimed == bag
				if gap <= 2.6 and not on_bag:
					in_way = aimed.name if aimed != null else "the ground or a wall"
				if gap > 1.6:
					me.cmd.move = t._move_toward(me, bag.global_position)
				else:
					me.cmd.move = Vector2.ZERO if on_bag else Vector2(1, 0)
				me.cmd.interact_pressed = gap <= 2.6 and on_bag and i % 10 == 0
				await t.frames(1)
			me.cmd.move = Vector2.ZERO
			me.cmd.interact_pressed = false
			await t._wait_until(looted, 60)
			t.check(looted.call(), "looting the bag fills the backpack from the server (%d items; %.1f m from the bag, last in the way: %s)"
					% [me.inventory.items.size(), gap, in_way])
			# The notice is its own message and can land a moment after the backpack.
			var told_loot := func() -> bool:
				return notices.any(func(text: String) -> bool: return text.begins_with("Looted "))
			await t._wait_until(told_loot, 60)
			t.check(told_loot.call(), "the looter is told what they picked up")
			await t._wait_until(func() -> bool: return not picked.is_empty(), 60)
			t.check(not picked.is_empty() and picked.all(func(id: String) -> bool: return id in me.inventory.items),
					"and item by item, for the visor's pickup feed (%s)" % ", ".join(picked))
			var bag_gone := func() -> bool: return not is_instance_id_valid(bag_id)
			await t._wait_until(bag_gone, 90)
			t.check(bag_gone.call(), "the emptied bag disappears on the client too")
		await t._wait_until(func() -> bool: return alpha.actor_for(bravo.my_actor_id) == null, 400)
		t.check(alpha.actor_for(bravo.my_actor_id) == null, "a dead player is removed from the other client's raid")

		# Bravo is still connected, and drops back into the same world.
		var dead_id := bravo.my_actor_id
		var world_before := bravo.raid
		bravo.deploy()
		var back := func() -> bool:
			return bravo.my_actor_id != dead_id and bravo.raid != null and bravo.raid.player != null \
					and is_instance_valid(bravo.raid.player) and not bravo.raid.player.is_dead
		await t._wait_until(back, 300)
		t.check(back.call() and bravo.raid == world_before and bravo.raid.player != victim,
				"a dead player drops back into the same world without reconnecting")
		await t._wait_until(func() -> bool: return alpha.actor_for(bravo.my_actor_id) != null, 180)
		t.check(alpha.actor_for(bravo.my_actor_id) != null and bravo.raid.players.size() == 2
				and bravo.containers().size() == alpha.containers().size(),
				"the other client sees them return, and they still see the world")
		# The watch's summon, online: Alpha materializes a weapon looted from the bag.
		# Prefer one unlike the weapon worn in its slot, so the swap is visible.
		var looted_weapon := ""
		for id in me.inventory.items:
			if not Loadout.summonable(id):
				continue
			var worn_at := Loadout.worn_index(me, Loadout.weapon_slot(id))
			var differs: bool = worn_at < 0 or me.weapons[worn_at].item_id != id
			if looted_weapon == "" or differs:
				looted_weapon = id
				if differs:
					break
		if looted_weapon == "" and back.call():
			# Ashfront drops a scrip pile, not the dead player's guns (DESIGN.md
			# "Scrip piles"), so nothing in the pack is a gun of theirs: store
			# the gun in hand, then summon it back out of the pack.
			var held_at := Loadout.worn_index(me, "primary")
			var held: String = me.weapons[held_at].item_id if held_at >= 0 else ""
			t.check(held != "", "the client holds a primary to store")
			if held != "":
				await t._wait_until(func() -> bool: return me.materialize_left <= 0.0, 180)
				var put := [0, 0]
				me.weapon_stored.connect(func(_id: String, _m: int, _r: int) -> void: put[0] += 1)
				me.weapon_swapped.connect(func(_id: String, _m: int, _r: int) -> void: put[1] += 1)
				var pack_now := me.inventory.items.size()
				alpha.store(held)
				var stowed := func() -> bool:
					return put[0] > 0 and Loadout.worn_index(me, "primary") < 0 and me.inventory.items.size() == pack_now + 1
				await t._wait_until(stowed, 240)
				t.check(stowed.call() and held not in me.gear_items and me.inventory.has_item(held),
						"the server stores the weapon in hand: it fades out and is in the pack")
				var seen_put := func() -> bool:
					var there := bravo.actor_for(alpha.my_actor_id)
					return there != null and Loadout.worn_index(there, "primary") < 0
				await t._wait_until(seen_put, 180)
				t.check(seen_put.call(), "the other client sees it put away")
				await t._wait_until(func() -> bool: return me.dematerialize_left <= 0.0 and alpha.raid.summon_wait(me) <= 0.0, 240)
				alpha.summon(held)
				var out := func() -> bool:
					var at := Loadout.worn_index(me, "primary")
					return put[1] > 0 and at >= 0 and me.weapons[at].item_id == held and not me.inventory.has_item(held)
				await t._wait_until(out, 180)
				t.check(out.call() and held in me.gear_items, "the server summons it back out of the pack, into the hand")
				t.check(me.materialize_time > 0.0, "it materializes on the summoner's screen (%.1f s)" % me.materialize_time)
				var seen_out := func() -> bool:
					var there := bravo.actor_for(alpha.my_actor_id)
					return there != null and Loadout.worn_index(there, "primary") >= 0
				await t._wait_until(seen_out, 180)
				t.check(seen_out.call(), "the other client sees the summoned weapon on them")
		if looted_weapon != "" and back.call():
			var slot := Loadout.weapon_slot(looted_weapon)
			var worn_before: String = me.weapons[Loadout.worn_index(me, slot)].item_id
			var pack_before := me.inventory.items.size()
			t.check(alpha.raid.summon(me, looted_weapon) != "" and me.weapons[Loadout.worn_index(me, slot)].item_id == worn_before,
					"a client cannot summon a weapon on its own")
			alpha.summon("smg_stinger" if looted_weapon != "smg_stinger" and worn_before != "smg_stinger" else "rifle_carbine")
			await t.frames(30)
			t.check(me.weapons[Loadout.worn_index(me, slot)].item_id == worn_before and me.inventory.items.size() == pack_before,
					"the server refuses a weapon that is not in the pack it keeps")
			var swaps := [0]
			me.weapon_swapped.connect(func(_id: String, _m: int, _r: int) -> void: swaps[0] += 1)
			alpha.summon(looted_weapon)
			var summoned := func() -> bool:
				var at := Loadout.worn_index(me, slot)
				return swaps[0] > 0 and at >= 0 and me.weapons[at].item_id == looted_weapon and at == me.active_weapon_index \
						and (worn_before == looted_weapon or me.inventory.has_item(worn_before))
			await t._wait_until(summoned, 180)
			t.check(summoned.call() and looted_weapon in me.gear_items and me.inventory.items.size() == pack_before,
					"the server summons it: it is in the hand, and the one worn is in the pack")
			t.check(me.materialize_time > 0.0, "it materializes on the summoner's screen (%.1f s)" % me.materialize_time)
			await t._wait_until(func() -> bool: return alpha.raid.summon_wait(me) > 0.0, 60)
			t.check(alpha.raid.summon_wait(me) > 0.0, "and the client is told its watch is resting")
			var seen_swap := func() -> bool:
				var there := bravo.actor_for(alpha.my_actor_id)
				return there != null and there.weapons.any(func(w: Weapon) -> bool: return w.item_id == looted_weapon) \
						and (worn_before == looted_weapon
						or not there.weapons.any(func(w: Weapon) -> bool: return w.item_id == worn_before))
			await t._wait_until(seen_swap, 180)
			t.check(seen_swap.call(), "the other client sees the summoned weapon on them")
			# The watch's store, online: the summoned weapon goes back into the pack.
			await t._wait_until(func() -> bool: return me.materialize_left <= 0.0, 180)
			var stores := [0]
			me.weapon_stored.connect(func(_id: String, _m: int, _r: int) -> void: stores[0] += 1)
			var pack_now := me.inventory.items.size()
			alpha.store(looted_weapon)
			var put_away := func() -> bool:
				return stores[0] > 0 and Loadout.worn_index(me, slot) < 0 and me.inventory.items.size() == pack_now + 1
			await t._wait_until(put_away, 240)
			t.check(put_away.call() and looted_weapon not in me.gear_items,
					"the server stores the weapon in hand: it fades out and is in the pack")
			var seen_store := func() -> bool:
				var there := bravo.actor_for(alpha.my_actor_id)
				return there != null and Loadout.worn_index(there, slot) < 0
			await t._wait_until(seen_store, 180)
			t.check(seen_store.call(), "the other client sees it put away")
		if back.call() and not me.inventory.items.is_empty():
			# The pack list's drop, online: the server takes it out of the
			# pack it keeps and lays a bag the other client sees.
			var dropped: String = me.inventory.items[0]
			var pack_was := me.inventory.items.size()
			t.check(alpha.raid.drop_item(me, dropped) != "" and me.inventory.items.size() == pack_was,
					"a client cannot drop out of its pack on its own")
			alpha.drop(dropped)
			var bag_seen := func() -> bool:
				if me.inventory.items.size() != pack_was - 1:
					return false
				for node in bravo.raid.get_tree().get_nodes_in_group("loot_containers"):
					var lying := node as LootContainer
					if lying != null and lying.is_bag and Raid.of(lying) == bravo.raid and dropped in lying.items \
							and lying.global_position.distance_to(me.global_position) < 6.0:
						return true
				return false
			await t._wait_until(bag_seen, 180)
			t.check(bag_seen.call(), "the server drops it: out of the pack, in a bag the other client sees")
		if back.call():
			# A ping reaches the pinger; a stranger on another side hears nothing.
			var ping_heard := [0, 0]
			alpha.raid.pinged.connect(func(_a: Actor, _at: Vector3) -> void: ping_heard[0] += 1)
			bravo.raid.pinged.connect(func(_a: Actor, _at: Vector3) -> void: ping_heard[1] += 1)
			me.cmd.pitch = -0.6
			me.cmd.aim_dir = Vector3.ZERO
			await t.frames(10)
			alpha.ping()
			await t._wait_until(func() -> bool: return ping_heard[0] > 0, 120)
			await t.frames(20)
			var allied: bool = alpha.raid.world.players_allied
			t.check(ping_heard[0] == 1 and ping_heard[1] == (1 if allied else 0),
					"a ping reaches the pinger and their side, nobody else")
		if back.call():
			var from := bravo.raid.player.global_position
			# Walk where there is room: a drop point has a wall and a bike by it.
			bravo.raid.player.cmd.yaw = t._yaw_toward(t._clear_run(bravo.raid.player, from, Vector3.FORWARD, 10.0))
			await t.frames(10)
			bravo.raid.player.cmd.move = Vector2(0, 1)
			await t.frames(60)
			bravo.raid.player.cmd.move = Vector2.ZERO
			await t.frames(20)
			var seen_again := alpha.actor_for(bravo.my_actor_id)
			t.check(bravo.raid.player.global_position.distance_to(from) > 2.0 and seen_again != null
					and seen_again.global_position.distance_to(bravo.raid.player.global_position) < 2.0,
					"the new body answers to their input, on both screens")
			# Signing out is asked of the server, and ends the stay alive.
			result[0] = {}
			await t.frames(int(world.combat_time * 60.0))
			bravo.sign_out()
			var counting := func() -> bool: return bravo.raid.sign_out_progress(bravo.raid.player) >= 0.0
			await t._wait_until(counting, 120)
			t.check(counting.call(), "the server starts a sign-out and the client shows the countdown")
			await t._wait_until(func() -> bool: return not result[0].is_empty(), int(world.sign_out_time * 60.0) + 240)
			t.check(result[0].get("outcome", "") == "left", "a finished sign-out ends the life as left")
			await t._wait_until(func() -> bool: return alpha.actor_for(bravo.my_actor_id) == null, 120)
			t.check(alpha.actor_for(bravo.my_actor_id) == null, "a player who left is gone from the other client's world")
	await t._leave(bravo)
	await t._leave(alpha)
	OS.kill(pid)
	await t.frames(30)
	t._wipe_dir(NET_ACCOUNTS)
	t.check(Combat.authoritative, "leaving an online raid hands damage back to this game")


## How many ticks a jump pressed by `me` takes to show on the copy of them
## another client sees (`seen`), averaged over `presses` jumps.
