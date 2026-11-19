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
	await _expedition(t)
	await _warzone(t)


## How many jobs the board offers: the ones that count anywhere, and each
## world tag's own.
static func _board_size() -> int:
	return Contracts.DAILY_OFFERS + Contracts.WEEKLY_OFFERS + Contracts.FAVOR_OFFERS \
			+ Contracts.tags().size() * (Contracts.TAGGED_DAILY_OFFERS + Contracts.TAGGED_WEEKLY_OFFERS)


static func _rules(t: Node) -> void:
	var offers := Contracts.offers_for(DAY)
	var dailies := offers.slice(0, Contracts.DAILY_OFFERS).filter(func(id: String) -> bool:
		return Contracts.job(id).kind == "daily" and not Contracts.job(id).has("world_tag"))
	t.check(offers.size() == _board_size() and dailies.size() == Contracts.DAILY_OFFERS
			and Contracts.offers_for(DAY) == offers,
			"the board offers 3 dailies and a weekly, Rook's favour, then each world's own, the same all day (%s)" % [offers])
	var changes := false
	for i in range(1, 6):
		changes = changes or Contracts.offers_for(DAY + i).slice(0, 3) != dailies
	t.check(changes and Contracts.offers_for(DAY + 1)[3] == offers[3] and Contracts.week_of(DAY) != Contracts.week_of(DAY + 7),
			"the dailies change with the day and the weekly with the week")
	var fair := true
	for id: String in Contracts.jobs():
		var job := Contracts.job(id)
		fair = fair and int(job.goal) > 0 and int(job.scrip) > 0 and job.kind in ["daily", "weekly", "favor"] \
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
	t.check(Contracts.reroll(state, DAY).ok and not Contracts.reroll(state, DAY).ok and state.offers.size() == _board_size()
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
	t.check(service.snapshot(id).contracts.offers.size() == _board_size(), "a snapshot is a copy: a client cannot edit the board")
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
	_mission_log(t, held)
	var state := Contracts.clean(null, DAY)
	Contracts.take(state, state.offers[0], DAY)
	var rows := ContractPanel.rows(state)
	var takes := rows.filter(func(r: Dictionary) -> bool: return r.action == "take")
	var drops := rows.filter(func(r: Dictionary) -> bool: return r.action == "drop")
	t.check(takes.size() == _board_size() - Contracts.FAVOR_OFFERS and drops.size() == 1 and not takes[0].enabled and takes[1].enabled,
			"the board's screen lists the offers to take (Rook's favour aside) and the held job to drop")
	var lines := PlazaMap.contract_lines()
	t.check(lines.size() == 2 + _board_size() - Contracts.FAVOR_OFFERS and lines[2].contains(Contracts.job(Contracts.offers_for(Contracts.today())[0]).title),
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


## A world's own contracts (DESIGN.md section 10, "World-tagged contracts"):
## Frostline's expedition jobs are on the board beside the rest, count only
## there, and the raid counts what they need.
static func _expedition(t: Node) -> void:
	print("Contracts: the expedition's own")
	var frost := Worlds.get_world("frostline")
	t.check(frost.contract_tag == "expedition" and Worlds.get_world("ashfront").contract_tag != "expedition"
			and "expedition" in Contracts.tags(), "Frostline tags its own contracts as the expedition's")
	var own := Contracts.ids("daily", "expedition") + Contracts.ids("weekly", "expedition")
	t.check(own.size() == frost.contract_jobs().size() and own.all(func(id: String) -> bool:
			return Contracts.job(id).get("world_tag", "") == "expedition"), "every one of its jobs is on the list, tagged")
	var offers := Contracts.offers_for(DAY)
	var on_board := offers.filter(func(id: String) -> bool: return Contracts.job(id).get("world_tag", "") == "expedition")
	t.check(on_board.size() == Contracts.TAGGED_DAILY_OFFERS + Contracts.TAGGED_WEEKLY_OFFERS
			and offers.slice(0, Contracts.DAILY_OFFERS + Contracts.WEEKLY_OFFERS).all(func(id: String) -> bool:
				return not Contracts.job(id).has("world_tag")),
			"the board offers an expedition daily and weekly after the jobs that count anywhere (%s)" % [on_board])
	t.check(Contracts.title_of("frost_relay").begins_with("Expedition: ") and Contracts.title_of("cull") == Contracts.job("cull").title,
			"its jobs are marked as the expedition's on the board")
	var weekly_bp := Contracts.ids("weekly", "expedition").all(func(id: String) -> bool:
			return Contracts.job(id).get("reward_tag", "") == "blueprint")
	t.check(weekly_bp, "its long expeditions pay a blueprint the account does not know yet: the slow route")
	# Counted only in a world with the tag.
	var state := Contracts.clean(null, DAY)
	state.offers = ["frost_cores", "cull"]
	Contracts.take(state, "frost_cores", DAY)
	var cores: Array = ["cryo_core", "cryo_core", "scrap_metal"]
	Contracts.settle(state, {"outcome": "left", "tally": {}, "loot": cores, "banked": ["cryo_core"],
			"contract_tag": ""}, DAY)
	t.check(state.active[0].have == 0, "an expedition job counts nothing in another world")
	var paid := Contracts.settle(state, {"outcome": "left", "tally": {}, "loot": cores, "banked": ["cryo_core"],
			"contract_tag": "expedition"}, DAY)
	t.check(state.active.is_empty() and paid.scrip == int(Contracts.job("frost_cores").scrip),
			"and counts there: three Cryo Cores home finish it")
	# The raid counts what they need.
	var raid := Raid.new()
	t.add_child(raid)
	raid.start_server(frost, 83)
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
		bot.set_physics_process(false)
	var p := raid.add_player(["rifle_scrap", "blade_scrap"], {}, "Expeditioner", "expeditioner")
	await t.frames(3)
	p.protected_left = 0.0
	var warden: Actor = null
	var boss: Actor = null
	for bot in raid.bots:
		if bot.get_meta("boss", "") != "":
			boss = bot
		elif warden == null and bot.faction == "warden":
			warden = bot
	Combat.deal(warden, DamageInfo.make(9999.0, p, "bullet"))
	if boss != null:
		Combat.deal(boss, DamageInfo.make(99999.0, p, "bullet"))
	await t.frames(2)
	t.check(int(p.tally.get("kills:warden", 0)) == 1 + (1 if boss != null else 0) and int(p.tally.get("bosses", 0)) == (1 if boss != null else 0),
			"Wardens killed and the Sentinel brought down count (%s)" % [p.tally])
	var relay: Dictionary = {}
	for cache: Dictionary in raid._caches:
		if cache.source == "relay":
			relay = cache
	t.check(not relay.is_empty(), "the relay is a cache the raid keeps")
	if not relay.is_empty():
		var box: LootContainer = relay.container
		box.set_items(["scrap_metal"])
		box.interact(p)
		box.set_items(["scrap_metal"])
		box.interact(p)
		t.check(int(p.tally.get("cache:relay", 0)) == 1, "looting the relay counts once a fill (%s)" % [p.tally])
	var results: Array[Dictionary] = []
	raid.player_finished.connect(func(_a: Actor, r: Dictionary) -> void: results.append(r))
	p.health.apply_damage(DamageInfo.make(9999.0, null, "test"))
	await t.frames(3)
	t.check(not results.is_empty() and results[0].get("contract_tag", "") == "expedition",
			"a Frostline life's result says which contracts it counts for")
	raid.queue_free()
	await t.frames(2)


## Ashfront's own jobs (DESIGN.md "Challenge and balance data"): from grab
## and go at the rim to holding the line, counted only there.
static func _warzone(t: Node) -> void:
	print("Contracts: the warzone's own")
	var ash := Worlds.get_world("ashfront")
	var own := Contracts.ids("daily", "warzone") + Contracts.ids("weekly", "warzone")
	t.check(ash.contract_tag == "warzone" and own.size() == ash.contract_jobs().size()
			and Contracts.title_of("war_hold").begins_with("Warzone: "),
			"Ashfront tags its own jobs as the warzone's")
	var stats := own.map(func(id: String) -> String: return Contracts.job(id).stat)
	t.check("cache:cache_outer" in stats and "cache:cache" in stats and "cache:cache_core" in stats
			and "hold_seconds" in stats and "banks" in stats,
			"they run from the rim's caches through the landmarks to the Foundry, banking and holding the line")
	var on_board := Contracts.offers_for(DAY).filter(func(id: String) -> bool:
		return Contracts.job(id).get("world_tag", "") == "warzone")
	t.check(on_board.size() == Contracts.TAGGED_DAILY_OFFERS + Contracts.TAGGED_WEEKLY_OFFERS,
			"the board offers a warzone daily and weekly")
	t.check(Contracts.amount("hold_seconds", {"outcome": "left", "tally": {"hold_seconds": 200}}) == 200
			and not Contracts.counts_in(Contracts.job("war_hold"), {"contract_tag": "expedition"}),
			"held seconds count from a sign-out, and never in another world")

	var raid: Raid = await t._new_raid(83, false)
	var p := raid.player
	var point: Node3D = raid.strongpoints[0]
	var side: Array = raid.side_of(p)
	point.holder = side[0]
	point.holder_name = side[1]
	point.holder_is_player = true
	for bot in raid.bots:
		bot.global_position = point.global_position + Vector3(400, 0, 400)
	p.global_position = point.global_position
	raid._tick_strongpoints(0.75)
	raid._tick_strongpoints(0.75)
	raid._tick_strongpoints(0.75)
	t.check(int(p.tally.get("hold_seconds", 0)) == 2,
			"standing in a site your side holds counts whole seconds held (%s)" % [p.tally])
	point.holder = "legion"
	raid._tick_strongpoints(2.0)
	t.check(int(p.tally.get("hold_seconds", 0)) == 2, "a site someone else holds counts nothing")
	p.inventory.add_item("scrap_metal")
	raid._on_actor_banked(p)
	t.check(int(p.tally.get("banks", 0)) == 1, "banking loot at a depot counts")
	await t._end_raid(raid)


## The mission log on the watch's contract icon (Caleb's ask): it lists the
## tour's step and every contract held, and a pick takes one off the visor's
## objective block or puts it back.
static func _mission_log(t: Node, held: Array[Dictionary]) -> void:
	var settings := preload("res://core/settings/game_settings.gd")
	var was := settings.persist
	settings.persist = false
	settings.untracked.clear()
	var missions := Hud.mission_entries(held, "Hit a plate on the test lane")
	t.check(missions.size() == 3 and missions[0].tour and missions[0].key == settings.TOUR_KEY
				and missions[1].key == "cull" and missions[2].key == "ride",
			"the mission log lists the tour's step first, then each contract held")
	var shut := Hud.mission_slot(missions, {}, 0, false)
	var open := Hud.mission_slot(missions, {"rides": 1}, 2, true)
	t.check(shut.value == "3" and shut.hints == ["click"] and open.hints == ["wheel", "click"] and open.index == 2
				and open.detail.begins_with("Ride 2 vehicles · 0/2 +1") and open.detail.ends_with("on visor"),
			"a click opens it, and the wheel turns through each mission with its progress (%s)" % open.detail)
	var visor := VisorHud.new()
	t.check(visor.objective_lines(held, {}, "Hit a plate").size() == 3, "everything is tracked on the visor to begin with")
	t.check(not settings.toggle_tracked("cull") and not settings.toggle_tracked(settings.TOUR_KEY)
				and Hud.mission_slot(missions, {}, 1, true).detail.ends_with("off visor"),
			"a pick takes a mission off the visor")
	var lines := visor.objective_lines(held, {}, "Hit a plate")
	t.check(lines.size() == 1 and lines[0].title == "Ride 2 vehicles", "and the visor lists only what is tracked")
	t.check(settings.toggle_tracked("cull") and visor.objective_lines(held, {}, "").size() == 2,
			"picking it again puts it back")
	visor.free()
	settings.untracked.clear()
	settings.persist = was
