extends RefCounted
## The `online_pillion` checks. The test runner finds this file by itself and calls
## `run(t)`.

const NET_ACCOUNTS := "user://test_accounts_net"
const StashService := preload("res://core/account/stash_service.gd")


static func run(t: Node) -> void:
	print("Online: a passenger behind the rider")
	t._wipe_dir(NET_ACCOUNTS)
	# Hal owns a Raider hoverbike: put one in the account before the server reads it.
	var service := StashService.new()
	service.save_dir = NET_ACCOUNTS
	if not t._net_secrets.has("Hal"):
		t._net_secrets["Hal"] = StashService.new_secret()
	service.sign_in("Hal", t._net_secrets["Hal"])
	var account := service.load_account(StashService.id_for_name("Hal"))
	account.add_items(["bike_raider"])
	service._save(account)
	var port := 24881
	var pid: int = t._start_server(port, ["--bots", "0", "--squad-spawn"])
	var hal: NetSession = await t._join("Hal", port, {"vehicle": "bike_raider"})
	var ida: NetSession = await t._join("Ida", port) if hal != null else null
	t.check(hal != null and ida != null, "two clients join for the passenger checks")
	var bike: Node3D = null
	if hal != null and ida != null:
		await t._throw_own_bike(hal)
		for v: Node3D in hal.vehicles():
			if v.get("item_id") == "bike_raider":
				bike = v
	if bike == null:
		t.check(false, "the hoverbike is there")
		await t._leave(ida)
		await t._leave(hal)
		OS.kill(pid)
		await t.frames(30)
		return
	var me := hal.raid.player
	t._aim_at(me, bike.global_position + Vector3(0, 0.6, 0))
	await t.frames(6)
	me.cmd.interact_pressed = true
	await t.frames(1)
	me.cmd.interact_pressed = false
	await t._wait_until(func() -> bool: return me.vehicle == bike, 90)
	t.check(me.vehicle == bike, "the rider gets on the hoverbike")
	# Ida walks up and climbs on behind.
	var her := ida.raid.player
	var her_bike: Node3D = null
	for v: Node3D in ida.vehicles():
		if v.get("item_id") == "bike_raider":
			her_bike = v
	for i in 400:
		var gap := her_bike.global_position - her.global_position if her_bike != null else Vector3.ZERO
		gap.y = 0.0
		if gap.length() < 2.0:
			break
		her.cmd.yaw = t._yaw_toward(gap)
		her.cmd.pitch = 0.0
		her.cmd.aim_dir = Vector3.ZERO
		her.cmd.move = Vector2(0, 1)
		await t.frames(1)
	her.cmd.move = Vector2.ZERO
	await t.frames(10)
	if her_bike != null:
		t._aim_at(her, her_bike.global_position + Vector3(0, 0.7, 0.3))
	await t.frames(6)
	her.cmd.interact_pressed = true
	await t.frames(1)
	her.cmd.interact_pressed = false
	var ida_on_hal := func() -> Actor:
		return hal._actors.get(ida.my_actor_id)
	await t._wait_until(func() -> bool:
		return her.vehicle == her_bike and bike.get("passenger") != null and bike.get("passenger") == ida_on_hal.call(), 120)
	t.check(her.vehicle == her_bike and her_bike.get("passenger") == her and her_bike.get("rider") != null,
			"the passenger sits behind the rider in their own game")
	t.check(bike.get("passenger") != null and bike.get("passenger") == ida_on_hal.call() and bike.get("rider") == me,
			"and the rider's game seats them there too")
	# The rider drives two up on a slow connection; the server agrees.
	hal.simulated_lag = 0.12
	await t.frames(40)
	hal.max_correction = 0.0
	var from := bike.global_position
	me.cmd.move = Vector2(0, 1)
	await t.frames(60)
	me.cmd.move = Vector2(-0.8, 1)
	await t.frames(40)
	me.cmd.move = Vector2(0, -1)
	await t._wait_until(func() -> bool: return float(bike.get("speed")) <= 0.5, 150)
	me.cmd.move = Vector2.ZERO
	var carried := bike.global_position.distance_to(from)
	t.check(carried > 3.0, "the hoverbike carries both (%.1f m)" % carried)
	t.check(hal.max_correction < 0.6, "the server agrees with the predicted two-up drift (worst %.2f m)" % hal.max_correction)
	await t.frames(60)
	var apart := her_bike.global_position.distance_to(bike.global_position)
	t.check(apart < 0.6 and her.global_position.distance_to(her_bike.global_position) < 1.5,
			"the passenger is carried where the rider has it (%.2f m apart)" % apart)
	# F lets the passenger off; the rider stays on.
	her.cmd.interact_pressed = true
	await t.frames(1)
	her.cmd.interact_pressed = false
	await t._wait_until(func() -> bool: return her.vehicle == null and bike.get("passenger") == null, 120)
	t.check(her.vehicle == null and bike.get("passenger") == null and me.vehicle == bike,
			"F lets the passenger off for everyone and the rider rides on")
	await t._leave(ida)
	await t._leave(hal)
	OS.kill(pid)
	await t.frames(30)


## Aims an actor at a point, the way a controller would.
