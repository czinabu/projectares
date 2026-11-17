extends RefCounted
## The player marketplace's rules (DESIGN.md section 10, "Two worlds, one
## loop"): what may be traded between players, the price band each item is
## held to, the fees, and how much one account may trade in a day. Pure
## functions on plain data, like `Economy`, so the server's `MarketService`
## and the kiosk's screen agree on them.
##
## Load with `const Market := preload("res://core/economy/market.gd")`.
##
## Why it is shaped like this:
##   - A player who only plays one world can still get what the other world
##     drops, by buying it from someone who played there. Parts and blueprints
##     come mostly from Frostline, upgrade data mostly from Ashfront.
##   - The chase stays earned: Mk3 gear, heavy weapons, artifacts and relics
##     never change hands, and a learned blueprint never leaves its account
##     (only a spare copy in the stash is an item at all).
##   - Fees drain scrip out of the game (a listing fee kept even if nothing
##     sells, and a cut of every sale), so trading back and forth can never
##     print money. The band stops dumping and gouging, and the daily cap
##     keeps one account from cornering the board.
##
## Every number here is a placeholder until the playtest (Caleb to confirm).

const StashRules := preload("res://core/account/stash_rules.gd")

## Never traded, by tag: the chase stays earned.
const UNTRADEABLE_TAGS := ["power", "artifact", "relic", "starter"]
## The highest Mk tier (`stats.tier`) that may be traded. Mk3 is earned.
const MAX_TRADE_TIER := 2
## The highest rarity that may be traded (ItemDB.Rarity.EPIC). Relics are
## prestige and stay with whoever earned them.
const MAX_TRADE_RARITY := 3
## What an item with no shop value is worth on the board, for its price band.
const BOARD_VALUE := {"upgrade_data": 400}
## The band a price is held to, as shares of the item's value.
const MIN_PRICE_SHARE := 0.5
const MAX_PRICE_SHARE := 3.0
## Paid when listing, a share of the asking total, kept even if nothing sells.
const LISTING_FEE_RATE := 0.05
const MIN_LISTING_FEE := 5
## The board's cut of every sale, taken from what the seller is paid.
const SALE_FEE_RATE := 0.10
## Listings one account may have up at once, and how many of one item a
## listing may hold.
const MAX_LISTINGS := 10
const MAX_STACK := 20
## Listings plus purchases one account may make in a day (UTC).
const DAILY_TRADES := 20
## Days a listing stays up before its items go back to the seller.
const LISTING_DAYS := 7


## True if the item may be listed on the board at all.
static func tradeable(id: String) -> bool:
	if not StashRules.storable(id) or ItemDB.item_rarity(id) > MAX_TRADE_RARITY:
		return false
	for tag: String in UNTRADEABLE_TAGS:
		if ItemDB.has_tag(id, tag):
			return false
	return int(ItemDB.item_stats(id).get("tier", 1)) <= MAX_TRADE_TIER and board_value(id) > 0


## What the board counts the item as worth: its shop value, or a set value
## for loot that no shop buys (upgrade data).
static func board_value(id: String) -> int:
	return int(BOARD_VALUE.get(id, ItemDB.item_value(id)))


## The lowest and highest price one of the item may be listed at.
static func min_price(id: String) -> int:
	return maxi(1, ceili(board_value(id) * MIN_PRICE_SHARE))


static func max_price(id: String) -> int:
	return maxi(min_price(id), floori(board_value(id) * MAX_PRICE_SHARE))


## The fee to list `count` of an item at `price` each.
static func listing_fee(price: int, count: int) -> int:
	return maxi(MIN_LISTING_FEE, ceili(price * count * LISTING_FEE_RATE))


## What the seller is paid for a sale of `total` scrip, after the board's cut.
static func seller_gets(total: int) -> int:
	return total - ceili(total * SALE_FEE_RATE)


## Why `count` of `id` cannot be listed at `price`, or "" if it can.
static func listing_problem(id: String, count: int, price: int) -> String:
	if not tradeable(id):
		return "That cannot be traded."
	if count < 1 or count > MAX_STACK:
		return "List 1 to %d at a time." % MAX_STACK
	if price < min_price(id) or price > max_price(id):
		return "Price it between %d and %d scrip." % [min_price(id), max_price(id)]
	return ""


## The trades counter for `today`: {"day", "count"}, reset on a new day.
static func trades_today(saved: Variant, today: int) -> Dictionary:
	if typeof(saved) != TYPE_DICTIONARY or int(saved.get("day", -1)) != today:
		return {"day": today, "count": 0}
	return {"day": today, "count": maxi(0, int(saved.get("count", 0)))}


## A listing as it is kept and sent, cleaned. Returns {} if it is not usable.
static func clean_listing(raw: Variant) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		return {}
	var item := str(raw.get("item", ""))
	var count := int(raw.get("count", 0))
	var price := int(raw.get("price", 0))
	var seller := str(raw.get("seller", ""))
	if seller == "" or not tradeable(item) or count < 1 or count > MAX_STACK or price < 1:
		return {}
	return {"id": int(raw.get("id", 0)), "seller": seller, "item": item, "count": count, "price": price,
			"day": int(raw.get("day", 0))}
