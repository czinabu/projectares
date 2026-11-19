extends RefCounted
## The `racing_online` checks. The test runner finds this file by itself and calls
## `run(t)`.
##
## A time trial on a race server: the client gets its own run and the
## board from the server, is held for the lights like the server holds it,
## joins a live race the server fills with AI racers, and asks the server
## to stop the run.

const NET_ACCOUNTS := "user://test_accounts_net"
const StashService := preload("res://core/account/stash_service.gd")


static func run(t: Node) -> void:
	print("Racing online: a time trial on a race server")
	var port := 24921
	t._wipe_dir(NET_ACCOUNTS)
	# A friend who has raced here before: their best lap's ghost is kept
	# beside their account.
	var accounts := StashService.new()
	accounts.save_dir = NET_ACCOUNTS
	t._net_secrets["Theo"] = StashService.new_secret()
	var theo_id: String = accounts.sign_in("Theo", t._net_secrets["Theo"]).account_id
	var theo_lap := RaceGhost.new()
	for k in 300:
		theo_lap.record(k * 0.1, Vector3(k, 0, 0), 0.0)
	accounts.keep_ghost(theo_id, "coilrun", "bike_scrapper", 61.5, theo_lap.to_packed())
	accounts.close()
	var pid: int = t._start_server(port, ["--bots", "0"], "meridian")
	var rhea: NetSession = await t._join("Rhea", port)
	t.check(rhea != null and rhea.raid is Race, "a client joins the race world, run by a Race")
	if rhea == null or not rhea.raid is Race:
		OS.kill(pid)
		return
	var race := rhea.raid as Race
	var me := race.player
	t.check(me.weapons_locked and race.track != null, "weapons are locked and the client has the track")
	var bike: Node3D = null
	for v: Node3D in race.vehicles:
		if v.get("item_id") == "bike_scrapper" and v.get("rider") == null and (bike == null
				or v.global_position.distance_to(me.global_position) < bike.global_position.distance_to(me.global_position)):
			bike = v
	t.check(bike != null and is_equal_approx(float(bike.get("max_speed")), float(ItemDB.RACE_SCRAPPER.max_speed)),
			"the client's bay machines run on their race profile too")
	if bike == null:
		await t._leave(rhea)
		OS.kill(pid)
		return
	for step in 600:
		var to := bike.global_position - me.global_position
		to.y = 0.0
		me.cmd.yaw = atan2(-to.x, -to.z)
		me.cmd.move = Vector2(0, 1) if to.length() > 1.8 else Vector2.ZERO
		if to.length() <= 1.8:
			break
		await t.frames(1)
	me.cmd.move = Vector2.ZERO
	await t.frames(10)
	for attempt in 5:
		# Look at it, then use it (once on the server's word: a second press
		# would get off again).
		me.cmd.aim_dir = (bike.global_position + Vector3(0, 0.6, 0) - me.get_eye_position()).normalized()
		me.cmd.interact_pressed = true
		await t.frames(1)
		me.cmd.interact_pressed = false
		if await t._wait_until(func() -> bool: return not race.remote_run.is_empty(), 60):
			break
	me.cmd.aim_dir = Vector3.ZERO
	await t._wait_until(func() -> bool: return me.vehicle != null, 240)
	t.check(str(race.remote_run.get("phase", "")) == "grid" and me.vehicle != null,
			"getting on sends the client its run, waiting on the grid")
	me.cmd.move = Vector2(0, 1)
	await t.frames(30)
	t.check(me.vehicle != null and bool(me.vehicle.get("held")) and absf(float(me.vehicle.get("speed"))) < 0.5,
			"the client holds its machine for the lights like the server")
	# Ghosts: none of your own yet; a saved friend's best is on the board
	# and comes to chase.
	race.want_ghost("mine", race.track.id, "bike_scrapper")
	await t._wait_until(func() -> bool: return not race.ghosts.get("mine|%s|bike_scrapper" % race.track.id, {"waiting": true}).has("waiting"), 240)
	t.check(race.ghosts.has("mine|%s|bike_scrapper" % race.track.id) and race.ghost_shown("mine", race.track.id,
			"bike_scrapper").is_empty(), "the server answers that there is no ghost of your own yet")
	# Met on this server, then saved as a contact.
	var theo: NetSession = await t._sign_in("Theo", port)
	await t._wait_until(func() -> bool: return rhea.social_state.get("contacts", []).any(
			func(c: Dictionary) -> bool: return c.id == theo_id), 240)
	rhea.change_contact("add", theo_id)
	await t._wait_until(func() -> bool: return not race.friends_on(race.track.id).is_empty(), 240)
	await t._leave(theo)
	var friends := race.friends_on(race.track.id)
	t.check(friends.size() == 1 and friends[0].name == "Theo" and is_equal_approx(float(friends[0].time), 61.5),
			"a saved friend's best lap reaches the pit board")
	t.check(RaceView.board_text(race.board_for(race.track.id), {}, friends).contains("FRIENDS"),
			"and is written under the board's own times")
	race.want_ghost("friend", race.track.id, "bike_scrapper")
	await t._wait_until(func() -> bool: return not race.ghost_shown("friend", race.track.id, "bike_scrapper").is_empty(), 240)
	var friend_ghost := race.ghost_shown("friend", race.track.id, "bike_scrapper")
	t.check(not friend_ghost.is_empty() and friend_ghost.name == "Theo" and is_equal_approx(float(friend_ghost.lap), 61.5)
			and (friend_ghost.ghost as RaceGhost).samples() == 300, "the friend's ghost comes from the server to chase")
	await t._wait_until(func() -> bool: return str(race.remote_run.get("phase", "")) == "racing", 400)
	await t.frames(40)
	t.check(str(race.remote_run.get("phase", "")) == "racing" and me.vehicle != null
			and absf(float(me.vehicle.get("speed"))) > 3.0, "at the go it races")
	me.cmd.move = Vector2.ZERO
	var radio: Array = []
	race.radio.connect(func(a: Actor, from: String, text: String) -> void: radio.append([a, from, text]))
	var races_before := int(rhea.account.get("racing", {}).get("races", 0))
	# A live race: the server forms it, fills it with AI racers and starts it.
	race.ask("race")
	await t._wait_until(func() -> bool: return str(race.remote_run.get("phase", "")) == "waiting", 240)
	t.check(str(race.remote_run.get("heat", "")) == "forming" and str(race.heat_view(race.track.id).get("phase", "")) == "forming",
			"asking to race puts the client on the grid of the next race, and its board hears of it")
	await t._wait_until(func() -> bool: return str(race.remote_run.get("heat", "")) == "racing", int((Race.FORM_TIME + 5.0) * 60))
	# Only this track's: the other track runs an AI race of its own.
	var on_grid := func() -> Array:
		return race.vehicles.filter(func(v: Variant) -> bool:
			return (is_instance_valid(v) and (v as Node3D).get("rider") != null and (v as Node3D).get("rider") != me
					and race.track_near((v as Node3D).global_position) == race.track))
	await t._wait_until(func() -> bool: return on_grid.call().size() >= Race.GRID_SIZE - 1, 240)
	var riders: Array = on_grid.call()
	t.check(riders.size() == Race.GRID_SIZE - 1, "the client sees AI racers fill the grid (%d)" % riders.size())
	await t._wait_until(func() -> bool: return int(race.remote_run.get("place", 0)) > 0, 600)
	t.check(int(race.remote_run.get("place", 0)) > 0 and Race.place_tag(race.remote_run).begins_with("P"),
			"and is told its place")
	t.check(radio.size() >= 1 and radio[0][0] == me and str(radio[0][1]) != "" and str(radio[0][2]) != "",
			"a rival's line at the lights reaches the racer's own radio")
	race.ask("retire")
	await t._wait_until(func() -> bool: return race.remote_run.is_empty() and me.vehicle == null, 240)
	t.check(race.remote_run.is_empty() and me.vehicle == null, "asking to stop ends the run on the server and gets off")
	await t._wait_until(func() -> bool:
		return int(rhea.account.get("racing", {}).get("races", 0)) > races_before, 240)
	t.check(int(rhea.account.get("racing", {}).get("races", 0)) == races_before + 1,
			"leaving a race counts as a finish that did not finish, on the server's account")
	# A desk sign-up reaches the server, which decides it: away from race
	# control it is turned away with the reason.
	var notices: Array = []
	me.notice.connect(func(text: String) -> void: notices.append(text))
	race.ask("signup:%s:bike_raider" % race.track.id)
	await t._wait_until(func() -> bool: return not notices.is_empty(), 240)
	t.check(notices.has("Sign up at race control's desk") and me.vehicle == null,
			"a desk sign-up is the server's to decide (%s)" % str(notices))
	notices.clear()
	race.ask("tune:bike_raider")
	await t._wait_until(func() -> bool: return not notices.is_empty(), 240)
	t.check(notices.has("Tune a machine at its bench in the pits"), "and so is tuning at a pit bench (%s)" % str(notices))
	await t._leave(rhea)
	OS.kill(pid)
