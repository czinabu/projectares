extends RefCounted
## Server side: the player marketplace's board. Players list stash items at a
## price, other players buy them, and the board pays the seller. The rules
## (what trades, the price band, fees, the daily cap) are `Market`; this keeps
## the listings and moves items and scrip between accounts, only ever through
## the `StashService` it is handed, so no account is written from here.
##
## The ledger it is handed needs only five calls: `count_of(account, item)`,
## `scrip_of(account)`, `take_items(account, item, count)`,
## `give_items(account, items)` and `change_scrip(account, delta)`. Accounts
## are files on one server today; when they move to a shared account service
## (the server review's recommendation), that service implements these five
## and the board moves with it.
##
## Load with `const MarketService := preload("res://core/economy/market_service.gd")`.
##
## Listed items are held by the board (taken out of the seller's stash when
## listed), so a listing can always be delivered. A listing that is not
## bought within `Market.LISTING_DAYS` goes back to its seller's stash, and a
## seller can take one down at any time. Only a player standing in a safe
## zone, not deployed, may trade; `NetSession` checks that before asking.
##
## One file, `market.json`, in `save_dir`. Every session of a server shares
## one service, like the `StashService` and `ClanService`.
##
## Ordering: the board's file is written before any account is, so a crash
## part way through a trade can lose a listing's goods but never copy them.
## When accounts move to a real database this becomes one transaction.

const Market := preload("res://core/economy/market.gd")

const SAVE_VERSION := 1
## The most listings the whole board holds.
const MAX_BOARD := 500
## The most listings sent to one player at a time, cheapest of each item first.
const MAX_SENT := 120

## Where `market.json` lives.
var save_dir := "user://accounts"
## Tests turn this off so they never touch real saves.
var persist := true
## The day trades are counted on. Below zero is the real date (UTC); tests
## set it to move time.
var day_override := -1

var _listings: Array[Dictionary] = []  # Market.clean_listing entries
var _trades := {}  # account id -> {"day", "count"}
var _next_id := 1
var _opened := false


## Reads the saved board, once. Later calls do nothing, so sessions that
## share a service can each call it.
func open(p_dir: String, p_persist: bool) -> void:
	if _opened:
		return
	_opened = true
	save_dir = p_dir
	persist = p_persist
	if not persist or not FileAccess.file_exists(_path()):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(_path()))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("MarketService: %s is unreadable" % _path())
		return
	_next_id = maxi(1, int(parsed.get("next_id", 1)))
	for raw: Variant in parsed.get("listings", []):
		var listing := Market.clean_listing(raw)
		if not listing.is_empty() and listing.id > 0 and _listings.size() < MAX_BOARD:
			_listings.append(listing)
			_next_id = maxi(_next_id, listing.id + 1)
	var saved_trades: Variant = parsed.get("trades", {})
	if typeof(saved_trades) == TYPE_DICTIONARY:
		for account: Variant in saved_trades:
			if typeof(account) == TYPE_STRING:
				_trades[account] = Market.trades_today(saved_trades[account], today())


## The day (UTC, days since 1970) trades are counted on.
func today() -> int:
	return day_override if day_override >= 0 else int(Time.get_unix_time_from_system() / 86400.0)


## Lists `count` of `item_id` from the account's stash at `price` scrip each.
## The listing fee is paid now and kept. Returns {"ok"} or {"ok": false, "error"}.
func list(stash: RefCounted, account_id: String, item_id: String, count: int, price: int) -> Dictionary:
	expire(stash)
	var problem := Market.listing_problem(item_id, count, price)
	if problem != "":
		return _fail(problem)
	if _listings_of(account_id) >= Market.MAX_LISTINGS:
		return _fail("You have %d listings up already." % Market.MAX_LISTINGS)
	if _listings.size() >= MAX_BOARD:
		return _fail("The board is full. Try again later.")
	if trades_left(account_id) <= 0:
		return _fail("That is all the trading for today.")
	if stash.count_of(account_id, item_id) < count:
		return _fail("You do not have that many.")
	var fee := Market.listing_fee(price, count)
	if stash.scrip_of(account_id) < fee:
		return _fail("Listing that costs %d scrip." % fee)
	var listing := {"id": _next_id, "seller": account_id, "item": item_id, "count": count, "price": price,
			"day": today()}
	_next_id += 1
	_listings.append(listing)
	_count_trade(account_id)
	_save()
	if not stash.take_items(account_id, item_id, count) or not stash.change_scrip(account_id, -fee):
		# Checked above, so this only happens if an account vanished.
		_listings.erase(listing)
		_save()
		return _fail("That listing did not go up.")
	return {"ok": true, "id": listing.id, "fee": fee}


## Buys `count` from listing `listing_id`. The buyer pays the asking price,
## the items go into their stash, and the seller is paid less the board's cut.
func buy(stash: RefCounted, account_id: String, listing_id: int, count: int = 1) -> Dictionary:
	expire(stash)
	var listing := _find(listing_id)
	if listing.is_empty():
		return _fail("That listing is gone.")
	if listing.seller == account_id:
		return _fail("That is your own listing.")
	count = clampi(count, 1, int(listing.count))
	if trades_left(account_id) <= 0:
		return _fail("That is all the trading for today.")
	var total: int = int(listing.price) * count
	if stash.scrip_of(account_id) < total:
		return _fail("Not enough scrip.")
	listing.count = int(listing.count) - count
	if listing.count <= 0:
		_listings.erase(listing)
	_count_trade(account_id)
	_save()
	var items: Array[String] = []
	for i in count:
		items.append(listing.item)
	if not stash.change_scrip(account_id, -total):
		# Checked above, so this only happens if an account vanished: put the
		# listing back as it was.
		listing.count = int(listing.count) + count
		if listing not in _listings:
			_listings.append(listing)
		_save()
		return _fail("Not enough scrip.")
	stash.give_items(account_id, items)
	var paid := Market.seller_gets(total)
	stash.change_scrip(str(listing.seller), paid)
	return {"ok": true, "item": listing.item, "count": count, "spent": total, "seller": listing.seller,
			"seller_paid": paid}


## Takes the account's own listing down; its items go back to the stash.
## The listing fee is not returned.
func cancel(stash: RefCounted, account_id: String, listing_id: int) -> Dictionary:
	var listing := _find(listing_id)
	if listing.is_empty() or listing.seller != account_id:
		return _fail("That is not your listing.")
	_listings.erase(listing)
	_save()
	_return(stash, listing)
	return {"ok": true}


## Sends listings older than `Market.LISTING_DAYS` back to their sellers.
## Returns the sellers whose stash changed.
func expire(stash: RefCounted) -> Array[String]:
	var now := today()
	var old: Array[Dictionary] = _listings.filter(func(listing: Dictionary) -> bool:
		return now - int(listing.day) >= Market.LISTING_DAYS)
	var sellers: Array[String] = []
	if old.is_empty():
		return sellers
	for listing in old:
		_listings.erase(listing)
	_save()
	for listing in old:
		_return(stash, listing)
		if listing.seller not in sellers:
			sellers.append(listing.seller)
	return sellers


## Trades the account may still make today.
func trades_left(account_id: String) -> int:
	var counted := Market.trades_today(_trades.get(account_id), today())
	return maxi(0, Market.DAILY_TRADES - int(counted.count))


## What the kiosk shows one player: every listing (cheapest of each item
## first, at most `MAX_SENT`), which are theirs, and how much trading they
## have left today. `name_of` turns an account id into a shown name. Never
## carries another player's account id.
func snapshot(account_id: String, name_of: Callable) -> Dictionary:
	var sorted := _listings.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.item != b.item:
			return ItemDB.item_name(a.item) < ItemDB.item_name(b.item)
		return a.price < b.price if a.price != b.price else a.id < b.id)
	var out: Array[Dictionary] = []
	var names := {}
	for listing: Dictionary in sorted:
		var mine: bool = listing.seller == account_id
		if out.size() >= MAX_SENT and not mine:
			continue
		if not names.has(listing.seller):
			names[listing.seller] = str(name_of.call(listing.seller))
		out.append({"id": listing.id, "item": listing.item, "count": listing.count, "price": listing.price,
				"seller": names[listing.seller], "mine": mine,
				"days_left": maxi(0, Market.LISTING_DAYS - (today() - int(listing.day)))})
	return {"listings": out, "trades_left": trades_left(account_id), "listed": _listings_of(account_id)}


# --- Internals ---------------------------------------------------------------

func _find(listing_id: int) -> Dictionary:
	for listing in _listings:
		if int(listing.id) == listing_id:
			return listing
	return {}


func _listings_of(account_id: String) -> int:
	return _listings.filter(func(listing: Dictionary) -> bool: return listing.seller == account_id).size()


func _count_trade(account_id: String) -> void:
	var counted := Market.trades_today(_trades.get(account_id), today())
	counted.count = int(counted.count) + 1
	_trades[account_id] = counted


func _return(stash: RefCounted, listing: Dictionary) -> void:
	var items: Array[String] = []
	for i in int(listing.count):
		items.append(listing.item)
	stash.give_items(str(listing.seller), items)


func _path() -> String:
	return save_dir.path_join("market.json")


func _save() -> void:
	if not persist:
		return
	DirAccess.make_dir_recursive_absolute(save_dir)
	# Today's counters only: yesterday's are worth nothing.
	var trades := {}
	for account: String in _trades:
		if int(_trades[account].day) == today():
			trades[account] = _trades[account]
	var path := _path()
	var temp := path + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		push_warning("MarketService: could not write %s" % temp)
		return
	file.store_string(JSON.stringify({"version": SAVE_VERSION, "next_id": _next_id, "listings": _listings,
			"trades": trades}, "\t"))
	file.close()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	DirAccess.rename_absolute(temp, path)


static func _fail(reason: String) -> Dictionary:
	return {"ok": false, "error": reason}
