extends RefCounted
## Checks for the Pit's blade rules (DESIGN.md "Gladiator arena"): bouts
## fought with blades only (guns locked, rigs jammed, or boots allowed),
## gladiators that bring a blade to them, the rules held the same on a
## client from the board, and the Blade Tournament's weekly prize on the
## profile and the server's accounts. Called from the test runner
## (`-- --only arena_blades` runs just these).

const Contracts := preload("res://core/economy/contracts.gd")
const Market := preload("res://core/economy/market.gd")
const Economy := preload("res://core/economy/economy.gd")
const StashRules := preload("res://core/account/stash_rules.gd")
const StashService := preload("res://core/account/stash_service.gd")
const AccountService := preload("res://core/account/account_service.gd")
const ItemCard := preload("res://core/ui/item_card.gd")


## A bank that keeps money and the weekly prize in memory.
class PrizeBank:
	extends Arena.Bank

	var money := {}
	var weeks := {}
	var prizes := {}

	func scrip(key: String) -> int:
		return money.get(key, 0)

	func change(key: String, delta: int) -> bool:
		if scrip(key) + delta < 0:
			return false
		money[key] = scrip(key) + delta
		return true

	func prize_week(key: String) -> int:
		return int(weeks.get(key, -1))

	func prize(key: String, week: int, items: Array) -> void:
		weeks[key] = week
		prizes[key] = (prizes.get(key, []) as Array) + items


static func run(t: Node) -> void:
	print("Arena: blade bouts and the Blade Tournament")
	_rules(t)
	_accounts(t)
	await _bouts(t)
	await _tournament(t)


static func _rules(t: Node) -> void:
	t.check(Arena.clean_rules("blades") == "blades" and Arena.clean_rules("guns") == "open"
			and Arena.clean_rules(7) == "open", "bout rules are one of open, blades, or blades and boots")
	var matched := true
	for i in 40:
		var probe := Actor.new()
		var rng := RandomNumberGenerator.new()
		rng.seed = 1000 + i * 7919
		Arena.ArenaVenue.new().equip_bot(probe, rng)
		var has_blade := probe.blade_index() >= 0
		matched = matched and has_blade == Arena.ArenaVenue.gladiator_has_blade(1000 + i * 7919)
		probe.free()
	t.check(matched, "a gladiator's blade can be read from its seed, the way every machine builds it")
	t.check("trophy" in Market.UNTRADEABLE_TAGS and ItemDB.has_tag("trophy_blade_champion", "trophy"),
			"the Blade Champion trophy never trades")
	t.check(Economy.sell_price("trophy_blade_champion") == 0 and ItemCard.short_kind("trophy_blade_champion").ends_with("trophy"),
			"it is worth nothing to a trader and reads as a trophy")


static func _accounts(t: Node) -> void:
	Profile.reset()
	var week: int = Contracts.week_of(Contracts.today())
	t.check(Profile.arena_prize(week, ["trophy_blade_champion"]) and Profile.arena_prize_week == week
			and "trophy_blade_champion" in Profile.stash, "solo, the weekly prize goes in the stash")
	t.check(not Profile.arena_prize(week, ["trophy_blade_champion"])
			and Profile.stash.count("trophy_blade_champion") == 1, "and only once a week")
	var saved := Profile.to_dict()
	Profile.reset()
	Profile.load_dict(saved)
	t.check(Profile.arena_prize_week == week, "the profile remembers the week it was won")
	Profile.reset()

	var service := StashService.new()
	service.persist = false
	var made: Dictionary = service.sign_in("Kestrel", StashService.new_secret())
	var id: String = made.account_id
	t.check(service.arena_prize(id, week, ["trophy_blade_champion", "nonsense_item"]).ok
			and service.snapshot(id).stash.count("trophy_blade_champion") == 1
			and int(service.snapshot(id).arena_prize_week) == week, "online, the account takes the prize and shows the week")
	t.check(not service.arena_prize(id, week, ["trophy_blade_champion"]).ok
			and service.snapshot(id).stash.count("trophy_blade_champion") == 1, "the account pays it once a week")
	t.check(service.arena_prize(id, week + 1, ["trophy_blade_champion"]).ok, "next week it can be won again")
	t.check("arena_prize" in AccountService.HELD and AccountService.CALLS.has("arena_prize")
			and "arena_prize_week" in StashRules.CARRIED, "official servers pay it once through the account service")


static func _quick(t: Node, kits: Dictionary) -> Arena:
	var arena := Arena.new()
	t.add_child(arena)
	arena.call_time = 0.3
	arena.countdown_time = 0.2
	arena.fight_time = 30.0
	arena.result_time = 0.1
	arena.exhibition_delay = -1.0
	arena.tournament_signup_time = 0.2
	var bank := PrizeBank.new()
	arena.bank = bank
	arena.start_server(Arena.ArenaVenue.new(), 9)
	for n: String in kits:
		var actor := arena.add_player(kits[n], {}, n)
		arena.set_key(actor, n)
		bank.money[n] = 500
	await t.frames(3)
	return arena


static func _phase(t: Node, arena: Arena, p: int, max_frames := 240) -> bool:
	return await t._wait_until(func() -> bool: return arena.phase == p, max_frames)


static func _bouts(t: Node) -> void:
	var arena := await _quick(t, {
		"Ira": ["rifle_carbine", "blade_scrap", "jetpack_mk1"],
		"Jun": ["rifle_carbine", "blade_scrap", "boots_thruster"],
		"Kit": ["rifle_carbine"],
	})
	var ira := arena.players[0].actor
	var jun := arena.players[1].actor
	var kit := arena.players[2].actor
	t.check(not arena.request(kit, "practice", {"rules": "blades"}).ok and arena.request(kit, "practice", {}).ok,
			"a blades bout needs a melee weapon; an open one does not")
	arena.queue.clear()
	t.check(not arena.request(ira, "challenge", {"to": String(kit.name), "rules": "blades"}).ok,
			"nobody without a blade can be challenged to one")
	t.check(arena.request(ira, "challenge", {"to": String(jun.name), "rules": "blades"}).ok,
			"a challenge names its rules")
	var seen := arena.board_for(jun)
	t.check(seen.challenges.size() == 1 and seen.challenges[0].rules == "blades", "and the challenged player sees them")
	t.check(arena.request(jun, "accept", {"from": String(ira.name)}).ok, "a blade duel is accepted")
	ira.cmd.switch_weapon = ira.slot_order()[0]
	await t.frames(3)
	t.check(ira.get_active_weapon() is Gun, "before the bout a gun can be drawn")
	await _phase(t, arena, Arena.Phase.COUNTDOWN, 60)
	await t.frames(2)
	t.check(ira.guns_locked and ira.get_active_weapon() is MeleeWeapon and jun.get_active_weapon() is MeleeWeapon,
			"in a blade bout the gun is put away and the blade comes out")
	t.check(arena.board_for(ira).bout.rules == "blades", "the board names the bout's rules")
	await _phase(t, arena, Arena.Phase.FIGHT)
	ira.cmd.switch_weapon = ira.slot_order()[0]
	await t.frames(3)
	t.check(ira.get_active_weapon() is MeleeWeapon, "no gun can be drawn while it is fought")
	t.check(not ira.flight.working() and not jun.flight.working(), "and every flight rig stays off")
	ira.cmd.switch_weapon = -1
	for i in 50:
		if arena.phase != Arena.Phase.FIGHT:
			break
		Combat.deal(jun, DamageInfo.make(40.0, ira, "blade"))
		await t.frames(1)
	await _phase(t, arena, Arena.Phase.IDLE)
	await t.frames(2)
	t.check(not ira.guns_locked and ira.flight.working() and jun.flight.working(),
			"after the bout guns and rigs are free again")

	# Blades and boots: thruster boots fly, a jetpack does not.
	t.check(arena.request(ira, "challenge", {"to": String(jun.name), "rules": "blades_boots"}).ok
			and arena.request(jun, "accept", {"from": String(ira.name)}).ok, "a blades and boots duel")
	await _phase(t, arena, Arena.Phase.FIGHT)
	await t.frames(2)
	t.check(jun.flight.working() and not ira.flight.working(), "boots fly in it, a jetpack stays off")
	t.check(Arena.rig_allowed("open", ira) and not Arena.rig_allowed("blades", jun) and Arena.rig_allowed("blades_boots", jun),
			"which rig may fly follows the rules")

	# A client holds the same rules from the board alone.
	var mode_was := arena.mode
	arena.mode = Raid.Mode.CLIENT
	arena.board = {"phase": "fight", "bout": {"rules": "blades", "nodes": [String(ira.name), String(jun.name)]}}
	arena.set("_ruled", [])
	ira.guns_locked = false
	arena._apply_rules()
	t.check(ira.guns_locked and jun.guns_locked and not jun.flight.working(),
			"a client locks the guns and jams the rigs from the board the server sent")
	arena.board = {"phase": "result", "bout": {"rules": "blades", "nodes": [String(ira.name), String(jun.name)]}}
	arena._apply_rules()
	t.check(not ira.guns_locked and not jun.guns_locked, "and lets go once the fight is over")
	arena.mode = mode_was
	arena.board = {}
	arena.queue_free()
	await t.frames(3)

	# A practice blades bout brings a gladiator with a blade.
	arena = await _quick(t, {"Lux": ["rifle_carbine", "blade_scrap"]})
	var lux := arena.players[0].actor
	var blades_all := true
	for i in 3:
		t.check(arena.request(lux, "practice", {"rules": "blades"}).ok, "a blades practice bout is asked for")
		await _phase(t, arena, Arena.Phase.FIGHT)
		var bot: Actor = arena.bout.fighters[1]
		blades_all = blades_all and bot != null and bot.get_active_weapon() is MeleeWeapon and bot.guns_locked
		for j in 50:
			if arena.phase != Arena.Phase.FIGHT:
				break
			Combat.deal(arena.bout.fighters[1], DamageInfo.make(40.0, lux, "blade"))
			await t.frames(1)
		await _phase(t, arena, Arena.Phase.IDLE)
	t.check(blades_all, "a gladiator brought to a blades bout fights with a blade")
	arena.queue_free()
	await t.frames(3)


static func _tournament(t: Node) -> void:
	var arena := await _quick(t, {"Mox": ["blade_scrap"], "Nia": ["blade_scrap"]})
	var bank: PrizeBank = arena.bank
	var mox := arena.players[0].actor
	var nia := arena.players[1].actor
	t.check(arena.request(mox, "join_tournament", {"rules": "blades"}).ok
			and arena.request(nia, "join_tournament", {"rules": "open"}).ok
			and arena.tournament.rules == "blades", "the first entrant picks the rules; it is a Blade Tournament")
	t.check(arena.board_for(mox).tournament.rules == "blades", "the board names it")
	var won := await _play_out(t, arena)
	t.check(won and arena.last_result.ends_with("is the Blade Champion"), "the bracket crowns a Blade Champion (%s)"
			% arena.last_result)
	var champion := ""
	for key: String in bank.prizes:
		champion = key
	t.check(champion != "" and "trophy_blade_champion" in bank.prizes[champion]
			and bank.prize_week(champion) == Contracts.week_of(Contracts.today()),
			"the champion takes the weekly trophy")
	var prized := (bank.prizes[champion] as Array).size() if champion != "" else 0
	t.check(arena.board_for(mox if champion == "Mox" else nia).you.prized, "and the board says it is held this week")
	# Again in the same week: the pot, but no second trophy.
	arena.request(mox, "join_tournament", {"rules": "blades"})
	arena.request(nia, "join_tournament", {})
	await _play_out(t, arena)
	t.check(champion == "" or (bank.prizes.get(champion, []) as Array).size() == prized,
			"a second win the same week pays no second prize")
	arena.queue_free()
	await t.frames(3)


## Plays a tournament through: the player side wins each bout.
static func _play_out(t: Node, arena: Arena) -> bool:
	for i in 8:
		if arena.tournament == null:
			break
		await _phase(t, arena, Arena.Phase.FIGHT, 120)
		if arena.bout == null:
			break
		var side := 0 if arena.bout.sides[0] is Actor else 1
		for j in 50:
			if arena.phase != Arena.Phase.FIGHT:
				break
			Combat.deal(arena.bout.fighters[1 - side], DamageInfo.make(40.0, arena.bout.fighters[side], "blade"))
			await t.frames(1)
		await _phase(t, arena, Arena.Phase.IDLE)
	await t.frames(5)
	return arena.tournament == null
