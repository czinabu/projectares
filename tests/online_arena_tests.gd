extends RefCounted
## The `online_arena` checks. The test runner finds this file by itself and calls
## `run(t)`.

const NET_ACCOUNTS := "user://test_accounts_net"
const StashService := preload("res://core/account/stash_service.gd")


static func run(t: Node) -> void:
	print("Arena: online")
	var service := StashService.new()
	service.persist = false
	var made := service.sign_in("Wren", StashService.new_secret())
	var stash_before: Array = service.snapshot(made.account_id).stash
	t.check(service.scrip_of("wren") == StashService.Economy.STARTING_SCRIP, "a new account starts with scrip")
	t.check(not service.change_scrip("wren", -10000) and service.change_scrip("wren", -50)
			and service.scrip_of("wren") == StashService.Economy.STARTING_SCRIP - 50, "scrip never go below zero")
	service.equip("wren", "primary", "rifle_carbine")
	var deployed := service.deploy("wren", Arena.ArenaVenue.new())
	t.check(deployed.ok and "rifle_carbine" in deployed.kit and service.snapshot("wren").stash == stash_before
			and not service.is_deployed("wren"), "entering the arena hands out the loadout without taking it")

	t._wipe_dir(NET_ACCOUNTS)
	var port := 24821
	var pid: int = t._start_server(port, ["--bots", "0"])
	var arena_port := port + 10
	var ash: NetSession = await t._join("Ashe", arena_port)
	var bex: NetSession = await t._join("Brix", arena_port)
	t.check(ash != null and bex != null and ash.raid is Arena and bex.raid is Arena,
			"players join the server's arena on its own port")
	if ash == null or bex == null:
		OS.kill(pid)
		await t._leave(ash)
		await t._leave(bex)
		return
	t.check(not ash.account.get("deployed", true), "nothing left the stash to enter the arena")
	var ash_arena: Arena = ash.raid
	await t._wait_until(func() -> bool: return ash_arena.board.get("players", []).size() == 1, 240)
	t.check(ash_arena.board.get("you", {}).get("scrip", 0) == StashService.Economy.STARTING_SCRIP
			and ash_arena.board.players[0].name == "Brix", "each player gets the board, with their scrip")
	var notices: Array[String] = []
	ash.raid.player.notice.connect(func(text: String) -> void: notices.append(text))
	ash_arena.ask("bet", {"side": 0, "amount": 10})
	await t._wait_until(func() -> bool: return not notices.is_empty(), 120)
	t.check(notices.size() == 1 and notices[0].begins_with("Bets are closed"), "the server refuses a bad request with a notice")
	ash_arena.ask("challenge", {"to": ash_arena.board.players[0].node, "stake": 25})
	var bex_arena: Arena = bex.raid
	await t._wait_until(func() -> bool: return not bex_arena.board.get("challenges", []).is_empty(), 240)
	t.check(not bex_arena.board.get("challenges", []).is_empty(), "the challenge reaches the other player")
	if not bex_arena.board.get("challenges", []).is_empty():
		bex_arena.ask("accept", {"from": bex_arena.board.challenges[0].from_node})
	await t._wait_until(func() -> bool: return bex_arena.board.get("phase", "") == "calling", 240)
	t.check(bex_arena.board.get("phase", "") == "calling" and bex_arena.board.bout.names == ["Ashe", "Brix"]
			and bex_arena.board.bout.stake == 50, "the server calls the duel with both stakes in the purse")
	t.check(str(bex_arena.board.get("bout", {}).get("rules", "")) == "open",
			"the board carries the bout's rules, which a client holds its fighters to")
	t.check(int(bex_arena.board.get("you", {}).get("scrip", 0)) == StashService.Economy.STARTING_SCRIP - 25,
			"the stake is taken from the server's account")
	OS.kill(pid)
	await t._leave(ash)
	await t._leave(bex)

	# With the plaza: its routes point the arena gate at the arena's port.
	port = 24841
	pid = t._start_server(port, ["--bots", "0", "--plaza"])
	var visitor: NetSession = await t._sign_in("Vale", port)
	t.check(visitor != null, "a client signs in to the plaza")
	if visitor != null:
		await t._wait_until(func() -> bool: return visitor.routes.has("arena"), 240)
		t.check(int(visitor.routes.get("arena", -1)) == port + 10, "the plaza's routes include the arena")
		await t._leave(visitor)
		var fighter: NetSession = await t._join("Vale", port + 10)
		t.check(fighter != null and fighter.raid is Arena, "the arena runs beside the plaza on the same server")
		await t._leave(fighter)
	OS.kill(pid)
	t._wipe_dir(NET_ACCOUNTS)
