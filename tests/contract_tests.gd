extends RefCounted
## Checks for contracts (DESIGN.md section 10): the jobs and the daily board,
## taking, dropping and rerolling, what a life counts in the raid, paying on
## a sign-out only, the server's account, the watch and the hub's board.
## Called from the test runner (`-- --groups ContractTests` runs just these).

const Contracts := preload("res://core/economy/contracts.gd")
const ContractPanel := preload("res://core/economy/contract_panel.gd")
const Accounts := preload("res://core/account/stash_service.gd")
const PlazaMap := preload("res://worlds/plaza/map.gd")
## A Wednesday, so the week runs on for a few days.
const DAY := 20404


static func run(t: Node) -> void:
	print("Contracts")
	_rules(t)
	_counting(t)
	_server(t)
	_views(t)
	await _raid_tally(t)


static func _rules(t: Node) -> void:
	var offers := Contracts.offers_for(DAY)
	var dailies := offers.filter(func(id: String) -> bool: return Contracts.job(id).kind == "daily")
	t.check(offers.size() == Contracts.DAILY_OFFERS + Contracts.WEEKLY_OFFERS and dailies.size() == Contracts.DAILY_OFFERS
			and Contracts.offers_for(DAY) == offers, "the board offers 3 dailies and a weekly, the same all day (%s)" % [offers])
	var changes := false
	for i in range(1, 6):
		changes = changes or Contracts.offers_for(DAY + i).slice(0, 3) != dailies
	t.check(changes and Contracts.offers_for(DAY + 1)[3] == offers[3] and Contracts.week_of(DAY) != Contracts.week_of(DAY + 7),
			"the dailies change with the day and the weekly with the week")
	var fair := true
	for id: String in Contracts.JOBS:
		var job := Contracts.job(id)
		fair = fair and int(job.goal) > 0 and int(job.scrip) > 0 and job.kind in ["daily", "weekly"] \
				and not str(job.stat).contains("player")
	t.check(fair, "every job has a goal and pays scrip, and none counts player kills")

	var state := Contracts.clean(null, DAY)
	t.check(state.offers == offers and state.active.is_empty() and not state.rerolled, "a new account sees today's board")
	t.check(Contracts.take(state, offers[0], DAY).ok and Contracts.take(state, offers[3], DAY).ok,
			"a daily and a weekly can be taken")
	t.check(not Contracts.take(state, offers[0], DAY).ok and not Contracts.take(state, "no_such", DAY).ok,
			"a job is held once, and only jobs on the board are taken")
	t.check(Contracts.take(state, offers[1], DAY).ok and not Contracts.take(state, offers[2], DAY).ok
			and state.active.size() == Contracts.MAX_ACTIVE, "you hold 3 at most")
	t.check(Contracts.drop(state, offers[1], DAY).ok and not Contracts.drop(state, offers[1], DAY).ok
			and state.active.size() == 2, "a job can be dropped")
	var held_daily: String = offers[0]
	t.check(Contracts.reroll(state, DAY).ok and not Contracts.reroll(state, DAY).ok and state.offers.size() == 4
			and state.active.size() == 2, "the dailies reroll once a day, and jobs held stay held")
	var saved: Variant = JSON.parse_string(JSON.stringify(state))
	var loaded := Contracts.clean(saved, DAY)
	t.check(loaded.offers == state.offers and loaded.rerolled and loaded.active.size() == 2,
			"the board survives a save the same day")
	Contracts.refresh(loaded, DAY + 1)
	t.check(loaded.active.size() == 1 and loaded.active[0].id == offers[3] and not loaded.rerolled
			and loaded.offers == Contracts.offers_for(DAY + 1) and not loaded.active.any(func(e: Dictionary) -> bool:
				return e.id == held_daily), "the next day the daily ends, the weekly runs on and the board is new")
	Contracts.refresh(loaded, DAY + 7)
	t.check(loaded.active.is_empty(), "a weekly ends with its week")
	t.check(Contracts.clean("junk", DAY).offers == offers and Contracts.clean({"active": [{"id": "nope"}, 7]}, DAY).active.is_empty(),
			"a broken save starts a clean board")


static func _life(outcome: String, tally: Dictionary, loot: Array = [], banked: Array = []) -> Dictionary:
	return {"outcome": outcome, "tally": tally, "loot": loot, "banked": banked}


static func _counting(t: Node) -> void:
	var value_loot: Array[String] = []
	var materials: Array[String] = []
	for id: String in ItemDB.all_ids():
		if ItemDB.has_tag(id, "material") and materials.size() < 4:
			materials.append(id)
	var worth := ItemDB.total_value(materials)
	value_loot.assign(materials)
	t.check(Contracts.amount("kills", _life("left", {"kills": 3})) == 3
			and Contracts.amount("kills", _life("died", {"kills": 3})) == 0, "only a sign-out counts")
	t.check(Contracts.amount("carry:material", _life("left", {}, materials.slice(0, 2), materials.slice(2))) == materials.size()
			and Contracts.amount("loot_value", _life("left", {}, value_loot)) == worth,
			"what came home counts, carried out or banked")
	t.check(Contracts.amount("extracts", _life("left", {})) == 0
			and Contracts.amount("extracts", _life("left", {}, value_loot)) == (1 if worth >= Contracts.EXTRACT_MIN_VALUE else 0),
			"signing straight out with nothing is no extract")

	var state := Contracts.clean(null, DAY)
	state.offers = ["cull", "warlord", "ride", "veteran"]
	Contracts.take(state, "cull", DAY)
	Contracts.take(state, "warlord", DAY)
	var dead := Contracts.settle(state, _life("died", {"kills": 20, "warlords": 1}), DAY)
	t.check(dead.scrip == 0 and state.active[0].have == 0, "dying counts nothing toward a contract")
	var part := Contracts.settle(state, _life("left", {"kills": 5}), DAY)
	t.check(part.scrip == 0 and state.active[0].have == 5 and state.active.size() == 2, "progress builds over lives")
	var done := Contracts.settle(state, _life("left", {"kills": 9, "warlords": 1}), DAY)
	var data_reward := ItemDB.has_item("upgrade_data")
	t.check(done.scrip == Contracts.job("cull").scrip + Contracts.job("warlord").scrip and state.active.is_empty()
			and done.finished.size() == 2 and ("upgrade_data" in done.items) == data_reward and state.done.size() == 2,
			"finished jobs pay at once and leave the board (%d scrip, %s)" % [done.scrip, done.items])
	t.check(not Contracts.take(state, "cull", DAY).ok, "a finished job is not taken twice in a day")
	var blueprints := ItemDB.all_ids().filter(func(id: String) -> bool: return ItemDB.has_tag(id, "blueprint"))
	var picked := Contracts.reward_for("blueprint", 5)
	t.check((picked == "") == blueprints.is_empty() and Contracts.reward_for("blueprint", 5, blueprints) == ""
			and Contracts.reward_for("", 5) == "", "a weekly's blueprint is one you do not know yet, if there are any")


static func _server(t: Node) -> void:
	var service := Accounts.new()
	service.persist = false
	service.day_override = DAY
	var id: String = service.sign_in("Contractor", "a-long-enough-secret-for-tests").account_id
	var board: Dictionary = service.snapshot(id).contracts
	t.check(board.offers == Contracts.offers_for(DAY) and board.active.is_empty(), "an account's snapshot carries the board")
	t.check(service.contract(id, "take", "no_such").ok == false and not service.contract(id, "steal", "").ok
			and not service.contract("nobody", "take", board.offers[0]).ok, "the server refuses bad requests")
	board.offers.clear()
	t.check(service.snapshot(id).contracts.offers.size() == 4, "a snapshot is a copy: a client cannot edit the board")
	var account: Accounts.Account = service.load_account(id)
	account.contracts.offers = ["cull", "warlord", "sites", "tyrant"]
	t.check(service.contract(id, "take", "cull").ok and service.snapshot(id).contracts.active.size() == 1,
			"taking a job is kept on the account")
	var before := service.scrip_of(id)
	service.deploy(id, Worlds.raid_worlds()[0])
	var settled: Dictionary = service.settle(id, {"outcome": "left", "brought_home": [], "tally": {"kills": 8}})
	t.check(settled.ok and service.scrip_of(id) == before + Contracts.job("cull").scrip
			and service.snapshot(id).contracts.active.is_empty() and settled.contracts.finished == [Contracts.job("cull").title],
			"settling a sign-out pays the finished job into the account")
	t.check(service.contract(id, "take", "tyrant").ok, "a weekly can be taken")
	var known_before := account.blueprints.size()
	service.deploy(id, Worlds.raid_worlds()[0])
	service.settle(id, {"outcome": "left", "brought_home": [], "tally": {"warlords": 3}})
	t.check(account.blueprints.size() == known_before + 1 and "upgrade_data" in account.stash
			and not account.stash.any(func(item: String) -> bool: return ItemDB.has_tag(item, "blueprint")),
			"a weekly's blueprint reward is learned, not stored, and upgrade data comes with it")
	var saved := account.to_dict()
	var loaded := Accounts.Account.new()
	loaded.load_dict(JSON.parse_string(JSON.stringify(saved)))
	t.check("cull" in Contracts.clean(loaded.contracts, DAY).done, "an account's contracts survive a save")
	saved.erase("contracts")
	loaded.load_dict(saved)
	t.check(Contracts.clean(loaded.contracts, DAY).active.is_empty(), "a save from before contracts opens a fresh board")


static func _views(t: Node) -> void:
	var held: Array[Dictionary] = [{"id": "cull", "title": "Kill 8 enemies", "have": 2, "goal": 8, "stat": "kills"},
			{"id": "ride", "title": "Ride 2 vehicles", "have": 0, "goal": 2, "stat": "rides"}]
	var slot := Hud.contract_slot(held, {"rides": 1})
	t.check(slot.id == "contract" and slot.value == "2" and slot.detail.begins_with("Ride 2 vehicles · 0/2 +1")
			and is_equal_approx(float(slot.progress), 0.5) and not slot.empty,
			"the watch shows the job nearest done, with this life's progress on top (%s)" % slot.detail)
	t.check(Hud.contract_slot([] as Array[Dictionary], {}).empty and Hud.contract_slot(held, {"rides": 2}).alert,
			"no contracts is an empty socket, and a job that will finish on sign-out glows")
	var home := Hud.base_watch_slots("Base", {}, held)
	t.check(home.size() == Hud.Wrist.SLOTS.size() and home[Hud.Wrist.SLOTS.find("contract")].value == "2",
			"the watch at home shows the contracts held too")
	var state := Contracts.clean(null, DAY)
	Contracts.take(state, state.offers[0], DAY)
	var rows := ContractPanel.rows(state)
	var takes := rows.filter(func(r: Dictionary) -> bool: return r.action == "take")
	var drops := rows.filter(func(r: Dictionary) -> bool: return r.action == "drop")
	t.check(takes.size() == 4 and drops.size() == 1 and not takes[0].enabled and takes[1].enabled,
			"the board's screen lists the offers to take and the held job to drop")
	var lines := PlazaMap.contract_lines()
	t.check(lines.size() == 2 + 4 and lines[2].contains(Contracts.job(Contracts.offers_for(Contracts.today())[0]).title),
			"the board's wall in the plaza lists today's jobs")


static func _raid_tally(t: Node) -> void:
	var kit: Array[String] = ["rifle_scrap", "blade_scrap", "plate_light", "artifact_bloom"]
	var raid: Raid = await t._kit_raid(81, kit)
	var p := raid.player
	p.protected_left = 0.0
	var results: Array[Dictionary] = []
	raid.player_finished.connect(func(_a: Actor, r: Dictionary) -> void: results.append(r))
	var counted := [0]
	raid.tally_changed.connect(func(_a: Actor) -> void: counted[0] += 1)
	var foe: Actor = raid.bots[0]
	var chief: Actor = raid.bots[1]
	raid.warlords[chief] = true
	Combat.deal(foe, DamageInfo.make(9999.0, p, "bullet"))
	Combat.deal(chief, DamageInfo.make(9999.0, p, "bullet"))
	await t.frames(2)
	t.check(p.tally.get("kills", 0) == 2 and p.tally.get("warlords", 0) == 1 and counted[0] >= 3,
			"kills and warlords count toward contracts, and the actor carries the count (%s)" % [p.tally])
	var bike := raid.spawn_vehicle("bike_scrapper", p.global_position + Vector3(4, 0, 0), 0.0)
	await t.frames(5)
	bike.call("mount", p)
	await t.frames(3)
	bike.call("dismount")
	await t.frames(3)
	bike.call("mount", p)
	await t.frames(3)
	t.check(p.tally.get("rides", 0) == 1, "a vehicle counts once a life however often you get on")
	if p.vehicle != null:
		p.vehicle.call("dismount")
	await t.frames(3)
	p.cmd.artifact_pressed = true
	await t.frames(1)
	p.cmd.artifact_pressed = false
	await t.frames(2)
	t.check(p.tally.get("artifacts", 0) == 1, "using the artifact counts")
	raid.clock += raid.world.combat_time + 1.0
	raid.begin_sign_out(p)
	raid.state_for(p).sign_out_left = 0.2
	await t.frames(30)
	t.check(results.size() == 1 and results[0].outcome == "left" and results[0].tally.get("kills", 0) == 2
			and results[0].tally.get("rides", 0) == 1, "the life's counts travel home in the result")
	await t._end_raid(raid)
