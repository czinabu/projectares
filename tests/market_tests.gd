extends RefCounted
## Checks for the player market (DESIGN.md section 10, "Two worlds, one
## loop"): what may be traded, the price band and fees, the board's listing,
## buying, taking down and expiry, the daily cap, that goods are never copied,
## and the kiosk's screen. The online trade is checked in the plaza group.
## Called from the test runner (`-- --groups MarketTests` runs just these).

const Market := preload("res://core/economy/market.gd")
const MarketService := preload("res://core/economy/market_service.gd")
const MarketPanel := preload("res://core/economy/market_panel.gd")
const Accounts := preload("res://core/account/stash_service.gd")
const DAY := 20404
const SECRET := "a-long-enough-secret-for-tests"


static func run(t: Node) -> void:
	print("Player market")
	_rules(t)
	_board(t)
	_limits(t)
	_saved(t)
	_all_or_nothing(t)
	_views(t)


static func _rules(t: Node) -> void:
	t.check(Market.tradeable("scrap_metal") and Market.tradeable("upgrade_data") and Market.tradeable("bp_jetpack")
			and Market.tradeable("rifle_carbine") and Market.tradeable("jetpack_mk2"),
			"parts, upgrade data, spare blueprints, gear and Mk2 rigs trade")
	t.check(not Market.tradeable("jetpack_mk3") and not Market.tradeable("power_rail_lance")
			and not Market.tradeable("artifact_cloak") and not Market.tradeable("lattice_shard")
			and not Market.tradeable("rifle_scrap") and not Market.tradeable("no_such_item"),
			"Mk3 gear, heavy weapons, artifacts, relics and the free scrap kit never trade")
	var value := Market.board_value("alloy_ingot")
	t.check(Market.min_price("alloy_ingot") == ceili(value * Market.MIN_PRICE_SHARE)
			and Market.max_price("alloy_ingot") == floori(value * Market.MAX_PRICE_SHARE)
			and Market.board_value("upgrade_data") > 0, "prices are held to a band round the item's value")
	t.check(Market.listing_problem("alloy_ingot", 1, value) == ""
			and Market.listing_problem("alloy_ingot", 1, Market.max_price("alloy_ingot") + 1) != ""
			and Market.listing_problem("alloy_ingot", 1, Market.min_price("alloy_ingot") - 1) != ""
			and Market.listing_problem("alloy_ingot", 0, value) != ""
			and Market.listing_problem("alloy_ingot", Market.MAX_STACK + 1, value) != ""
			and Market.listing_problem("jetpack_mk3", 1, 100) != "", "a listing outside the rules is refused")
	t.check(Market.seller_gets(1000) == 900 and Market.listing_fee(100, 1) == Market.MIN_LISTING_FEE
			and Market.listing_fee(1000, 4) == 200, "the fees: 5% to list, 10% of every sale")
	# Fees always drain: a round trip loses scrip, so trading can never print money.
	var price := Market.max_price("alloy_ingot")
	t.check(Market.seller_gets(price) - Market.listing_fee(price, 1) < price, "buying and relisting never makes scrip")


static func _service() -> Array:
	var stash := Accounts.new()
	stash.persist = false
	var market := MarketService.new()
	market.persist = false
	market.day_override = DAY
	var ada: String = stash.sign_in("Ada", SECRET).account_id
	var bo: String = stash.sign_in("Bob", SECRET).account_id
	return [stash, market, ada, bo]


static func _board(t: Node) -> void:
	var made := _service()
	var stash: Accounts = made[0]
	var market: MarketService = made[1]
	var ada: String = made[2]
	var bo: String = made[3]
	var start_ada := stash.scrip_of(ada)
	var start_bo := stash.scrip_of(bo)
	stash.give_items(ada, ["alloy_ingot", "alloy_ingot", "alloy_ingot"])
	var price := Market.board_value("alloy_ingot")
	t.check(not market.list(stash, ada, "alloy_ingot", 4, price).ok, "you cannot list more than you have")
	var listed := market.list(stash, ada, "alloy_ingot", 2, price)
	var fee := Market.listing_fee(price, 2)
	t.check(listed.ok and stash.count_of(ada, "alloy_ingot") == 1 and stash.scrip_of(ada) == start_ada - fee,
			"listing takes the items into the board and charges the fee")
	var seen := market.snapshot(bo, func(id: String) -> String: return id.capitalize())
	t.check(seen.listings.size() == 1 and seen.listings[0].seller == "Ada" and not seen.listings[0].mine
			and seen.listings[0].count == 2 and not seen.listings[0].has("seller_id"),
			"the board shows the listing by the seller's name, never their account")
	t.check(not market.buy(stash, ada, listed.id, 1).ok, "you cannot buy your own listing")
	var bought := market.buy(stash, bo, listed.id, 1)
	t.check(bought.ok and stash.count_of(bo, "alloy_ingot") == 1 and stash.scrip_of(bo) == start_bo - price
			and stash.scrip_of(ada) == start_ada - fee + Market.seller_gets(price),
			"a buyer pays the price, gets the item, and the seller is paid less the board's cut")
	t.check(market.snapshot(ada, func(id: String) -> String: return id).listings[0].count == 1,
			"the rest of the listing stays up")
	# Nothing was copied: three ingots in, three ingots out.
	var total := stash.count_of(ada, "alloy_ingot") + stash.count_of(bo, "alloy_ingot") + 1
	t.check(total == 3, "goods are moved, never copied (%d)" % total)
	t.check(not market.cancel(stash, bo, listed.id).ok and market.cancel(stash, ada, listed.id).ok
			and stash.count_of(ada, "alloy_ingot") == 2 and not market.buy(stash, bo, listed.id, 1).ok,
			"only the seller takes a listing down, and its items go home")
	# A buyer short of scrip changes nothing.
	var again := market.list(stash, ada, "alloy_ingot", 1, Market.max_price("alloy_ingot"))
	stash.change_scrip(bo, -stash.scrip_of(bo))
	t.check(not market.buy(stash, bo, again.id, 1).ok and stash.count_of(bo, "alloy_ingot") == 1
			and market.snapshot(bo, func(id: String) -> String: return id).listings.size() == 1,
			"a buyer without the scrip gets nothing and the listing stays")
	# A deployed seller cannot list (the kiosk is in the plaza, but check the ledger too).
	t.check(not stash.take_items(ada, "alloy_ingot", 99), "the ledger never takes more than there is")
	# Old listings come home.
	market.day_override = DAY + Market.LISTING_DAYS
	var sellers := market.expire(stash)
	t.check(sellers == [ada] and stash.count_of(ada, "alloy_ingot") == 2
			and market.snapshot(ada, func(id: String) -> String: return id).listings.is_empty(),
			"a listing left up for %d days goes back to its seller" % Market.LISTING_DAYS)
	# Buying a spare blueprint you do not know teaches it.
	market.day_override = DAY + 10
	stash.give_items(ada, [])
	var ada_account := stash.load_account(ada)
	ada_account.stash.append("bp_jetpack")  # a spare copy, as if Ada already knew it
	var bp := market.list(stash, ada, "bp_jetpack", 1, Market.board_value("bp_jetpack"))
	stash.change_scrip(bo, 5000)
	t.check(bp.ok and market.buy(stash, bo, bp.id, 1).ok and "bp_jetpack" in stash.snapshot(bo).blueprints,
			"a blueprint bought on the board is learned")


static func _limits(t: Node) -> void:
	var made := _service()
	var stash: Accounts = made[0]
	var market: MarketService = made[1]
	var ada: String = made[2]
	var bo: String = made[3]
	var many: Array[String] = []
	for i in Market.MAX_LISTINGS + 1:
		many.append("scrap_metal")
	stash.give_items(ada, many)
	stash.change_scrip(ada, 5000)
	var ok := true
	for i in Market.MAX_LISTINGS:
		ok = ok and market.list(stash, ada, "scrap_metal", 1, Market.board_value("scrap_metal")).ok
	t.check(ok and not market.list(stash, ada, "scrap_metal", 1, Market.board_value("scrap_metal")).ok,
			"one account has at most %d listings up" % Market.MAX_LISTINGS)
	stash.change_scrip(bo, 5000)
	var listings: Array = market.snapshot(bo, func(id: String) -> String: return id).listings
	var bought := 0
	for i in Market.DAILY_TRADES + 2:
		if market.buy(stash, bo, int(listings[i % listings.size()].id), 1).ok:
			bought += 1
	t.check(bought == Market.MAX_LISTINGS, "every listing can be bought once (%d)" % bought)
	market._trades[bo] = {"day": DAY, "count": Market.DAILY_TRADES}
	stash.give_items(bo, ["scrap_metal"])
	t.check(market.trades_left(bo) == 0 and not market.list(stash, bo, "scrap_metal", 1, Market.board_value("scrap_metal")).ok,
			"the daily cap stops more trading")
	market.day_override = DAY + 1
	t.check(market.trades_left(bo) == Market.DAILY_TRADES, "the cap resets the next day")


static func _saved(t: Node) -> void:
	var dir := "user://test_market"
	for file in DirAccess.get_files_at(dir) if DirAccess.dir_exists_absolute(dir) else PackedStringArray():
		DirAccess.remove_absolute(dir.path_join(file))
	var stash := Accounts.new()
	stash.persist = false
	var ada: String = stash.sign_in("Ada", SECRET).account_id
	stash.give_items(ada, ["power_cell", "power_cell"])
	var market := MarketService.new()
	market.day_override = DAY
	market.open(dir, true)
	var listed := market.list(stash, ada, "power_cell", 2, Market.board_value("power_cell"))
	var reopened := MarketService.new()
	reopened.day_override = DAY
	reopened.open(dir, true)
	var seen: Array = reopened.snapshot(ada, func(id: String) -> String: return id).listings
	t.check(listed.ok and seen.size() == 1 and seen[0].id == listed.id and seen[0].count == 2
			and reopened.trades_left(ada) == Market.DAILY_TRADES - 1, "the board and today's trades survive a restart")
	var next := reopened.list(stash, ada, "alloy_ingot", 1, Market.board_value("alloy_ingot"))
	t.check(not next.ok, "and its rules still hold (nothing listed you do not have)")


## A ledger whose transactions all refuse, as if a save failed part way.
class Refusing:
	extends RefCounted
	var real: RefCounted
	func count_of(a: String, i: String) -> int: return real.count_of(a, i)
	func scrip_of(a: String) -> int: return real.scrip_of(a)
	func take_items(a: String, i: String, c: int) -> bool: return real.take_items(a, i, c)
	func give_items(a: String, items: Array) -> bool: return real.give_items(a, items)
	func change_scrip(a: String, d: int) -> bool: return real.change_scrip(a, d)
	func transaction(_steps: Array) -> Dictionary: return {"ok": false, "error": "refused", "step": -1}


static func _all_or_nothing(t: Node) -> void:
	var made := _service()
	var stash: Accounts = made[0]
	var market: MarketService = made[1]
	var ada: String = made[2]
	var bo: String = made[3]
	stash.give_items(ada, ["alloy_ingot", "alloy_ingot"])
	var price := Market.board_value("alloy_ingot")
	var refusing := Refusing.new()
	refusing.real = stash
	var ada_scrip := stash.scrip_of(ada)
	t.check(not market.list(refusing, ada, "alloy_ingot", 1, price).ok and stash.count_of(ada, "alloy_ingot") == 2
			and stash.scrip_of(ada) == ada_scrip and market.snapshot(ada, func(id: String) -> String: return id).listings.is_empty(),
			"a listing whose charge fails goes nowhere and costs nothing")
	var listed := market.list(stash, ada, "alloy_ingot", 1, price)
	ada_scrip = stash.scrip_of(ada)
	var bo_scrip := stash.scrip_of(bo)
	var bo_had := stash.count_of(bo, "alloy_ingot")
	t.check(listed.ok and not market.buy(refusing, bo, listed.id, 1).ok and stash.scrip_of(bo) == bo_scrip
			and stash.scrip_of(ada) == ada_scrip and stash.count_of(bo, "alloy_ingot") == bo_had
			and market.snapshot(bo, func(id: String) -> String: return id).listings[0].count == 1
			and market.trades_left(bo) == Market.DAILY_TRADES,
			"a sale that cannot be saved charges nobody, pays nobody and leaves the listing up")


static func _views(t: Node) -> void:
	var state := {"listings": [
			{"id": 3, "item": "alloy_ingot", "count": 2, "price": 240, "seller": "Bo", "mine": false, "days_left": 6},
			{"id": 4, "item": "power_cell", "count": 1, "price": 110, "seller": "Ada", "mine": true, "days_left": 2}],
			"trades_left": 5, "listed": 1}
	var rows := MarketPanel.listing_rows(state, 200)
	t.check(rows.size() == 3 and rows[0].text.begins_with("5 TRADES") and rows[1].action == "buy"
			and not rows[1].enabled and "from Bo" in rows[1].text and rows[2].action == "cancel" and rows[2].enabled,
			"the kiosk lists the board, greys out what you cannot afford, and lets you take yours down")
	t.check(MarketPanel.listing_rows({}, 0)[0].action == "", "before the board arrives it says so")
	var sell := MarketPanel.sellable(["scrap_metal", "scrap_metal", "rifle_scrap", "jetpack_mk3", "upgrade_data"])
	t.check(sell.size() == 2 and sell.any(func(e: Dictionary) -> bool: return e.id == "scrap_metal" and e.have == 2)
			and sell.any(func(e: Dictionary) -> bool: return e.id == "upgrade_data"),
			"only tradeable stash items are offered for listing")
