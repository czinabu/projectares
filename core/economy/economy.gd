extends RefCounted
## The money rules: what scrip is earned for, what things cost, and what a
## shop may sell. Shared by the local `Profile` and the server's
## `StashService`, so solo and online play follow the same rules. Pure
## functions on plain data, like `StashRules`: no files, no network.
##
## Load with `const Economy := preload("res://core/economy/economy.gd")`.
##
## How the economy is meant to work:
##   - Loot is the money. Scrip come mostly from selling what you carried
##     home, so nothing is earned until loot survives the trip. Dying still
##     costs everything you carried.
##   - Kills pay a small bounty, most of it only if you get home alive. It is
##     kept small on purpose: a free scrap kit must never out-earn real risk.
##   - Scrip is safe in the bank, but it only turns into power as gear,
##     and bought gear is lost on death like any other.
##   - Shops sell base-level gear only (see `MAX_SHOP_RARITY`). Anything
##     better has to be found.
##   - Selling gear back pays less than buying it, so trading with a shop can
##     never make money.

const ShopDB := preload("res://core/economy/shop_db.gd")
const StashRules := preload("res://core/account/stash_rules.gd")

## What a new profile or account starts with: about one base weapon.
const STARTING_SCRIP := 500
const MAX_SCRIP := 9_999_999
## The best rarity a shop may ever sell (ItemDB.Rarity.UNCOMMON).
const MAX_SHOP_RARITY := 1
## Items a shop stocks carry this tag.
const VENDOR_TAG := "vendor"
## Loot with one of these tags is a trade good: it sells for its full value.
## A blueprint only stays in a stash as a spare copy of one already known
## (see `Crafting.learn`), so it is a trade good too.
const TRADE_TAGS := ["material", "augment", "relic", "blueprint"]
## Everything else (gear, furniture) sells back for this share of its value.
const SELL_BACK_RATE := 0.4
## Scrip is the one money. What you carry in a world is at stake: it joins
## your banked balance only once it is banked at a depot or carried out
## alive, and a death drops what is carried into the bag. These are what
## earns it in the field.
const KILL_BOUNTY := 10
const PLAYER_KILL_SCRIP := 60
const WARLORD_SCRIP := 150
const STRONGPOINT_SCRIP := 75
## The most of one item sold in a single request.
const MAX_SELL_COUNT := 99


## True if the item is loot meant to be sold rather than used.
static func is_trade_good(id: String) -> bool:
	for tag: String in TRADE_TAGS:
		if ItemDB.has_tag(id, tag):
			return true
	return false


## What a shop pays for the item. 0 means it cannot be sold.
static func sell_price(id: String) -> int:
	if not StashRules.storable(id):
		return 0
	var value := ItemDB.item_value(id)
	return value if is_trade_good(id) else int(floor(value * SELL_BACK_RATE))


## What a shop charges for the item.
static func buy_price(id: String) -> int:
	return ItemDB.item_value(id)


## True if any shop may sell the item: tagged for vendors, base level, and not
## part of the free scrap kit.
static func is_shop_item(id: String) -> bool:
	return (StashRules.storable(id) and ItemDB.has_tag(id, VENDOR_TAG)
			and ItemDB.item_rarity(id) <= MAX_SHOP_RARITY and buy_price(id) > 0)


## True if the shop `shop_id` sells the item.
static func for_sale(shop_id: String, id: String) -> bool:
	if not is_shop_item(id):
		return false
	for tag: String in ShopDB.shop(shop_id).get("tags", []):
		if ItemDB.has_tag(id, tag):
			return true
	return false


## Everything the shop sells, cheapest first.
static func stock(shop_id: String) -> Array[String]:
	var out: Array[String] = []
	for id: String in ItemDB.all_ids():
		if for_sale(shop_id, id):
			out.append(id)
	out.sort_custom(func(a: String, b: String) -> bool:
		return buy_price(a) < buy_price(b) if buy_price(a) != buy_price(b) else a < b)
	return out


## Buys one item into `stash`. Returns {"ok", "scrip"} with the new balance,
## or {"ok": false, "error", "scrip"} with the balance unchanged.
static func buy(stash: Array[String], scrip: int, shop_id: String, item_id: String) -> Dictionary:
	if not for_sale(shop_id, item_id):
		return _fail("That is not for sale here.", scrip)
	var price := buy_price(item_id)
	if scrip < price:
		return _fail("Not enough scrip.", scrip)
	stash.append(item_id)
	return {"ok": true, "scrip": scrip - price, "spent": price}


## Sells up to `count` of one item out of `stash`. Loadout entries that no
## longer have an item behind them are dropped. Returns {"ok", "scrip",
## "sold", "earned"}.
static func sell(stash: Array[String], loadout: Dictionary, scrip: int, item_id: String,
		count: int = 1) -> Dictionary:
	var price := sell_price(item_id)
	if price <= 0 or item_id not in stash:
		return _fail("You cannot sell that.", scrip)
	var sold := 0
	for i in clampi(count, 1, MAX_SELL_COUNT):
		if item_id not in stash:
			break
		stash.erase(item_id)
		sold += 1
	StashRules.validate_loadout(stash, loadout)
	return {"ok": true, "scrip": add(scrip, price * sold), "sold": sold, "earned": price * sold}


## Sells every trade good in `stash`. Gear and furniture are left alone.
static func sell_loot(stash: Array[String], scrip: int) -> Dictionary:
	var earned := 0
	var sold := 0
	for id: String in stash.duplicate():
		if is_trade_good(id) and sell_price(id) > 0:
			stash.erase(id)
			earned += sell_price(id)
			sold += 1
	if sold == 0:
		return _fail("No loot to sell.", scrip)
	return {"ok": true, "scrip": add(scrip, earned), "sold": sold, "earned": earned}


## What the stash's trade goods would sell for.
static func loot_value(stash: Array) -> int:
	var total := 0
	for id: Variant in stash:
		if typeof(id) == TYPE_STRING and is_trade_good(id):
			total += sell_price(id)
	return total


## The character customizer outfits the stash unlocks: every id in the
## "outfits" stat of the cosmetic items owned. Pass it to the customizer as
## its `owned` list.
static func unlocked_outfits(stash: Array) -> Array[String]:
	var out: Array[String] = []
	for id: Variant in stash:
		if typeof(id) != TYPE_STRING or not ItemDB.has_tag(id, "cosmetic"):
			continue
		for outfit: Variant in ItemDB.item_stats(id).get("outfits", []):
			if typeof(outfit) == TYPE_STRING and outfit not in out:
				out.append(outfit)
	return out


## Scrip a finished run pays on its own, before any loot is sold. `result`
## is a raid's `player_finished` dictionary and must come from the authority
## (the server online), never from a client.
static func payout(result: Dictionary) -> int:
	var home := maxi(int(result.get("scrip_banked", 0)), 0)
	if result.get("outcome", "") != "died":
		home += maxi(int(result.get("scrip", 0)), 0)
	return mini(home, MAX_SCRIP)


## True if `scrip` can take `delta` (a cost when negative) without going
## below zero.
static func can_change(scrip: int, delta: int) -> bool:
	return scrip + delta >= 0


## A balance after adding `amount`, kept inside the legal range.
static func add(scrip: int, amount: int) -> int:
	return clampi(scrip + amount, 0, MAX_SCRIP)


## Reads a saved balance. Saves from when it was called "credits" still load,
## and a save from before money existed gets the starting amount.
static func read_saved(data: Dictionary) -> int:
	var saved: Variant = data.get("scrip", data.get("credits", STARTING_SCRIP))
	if typeof(saved) != TYPE_INT and typeof(saved) != TYPE_FLOAT:
		return STARTING_SCRIP
	return clampi(int(saved), 0, MAX_SCRIP)


static func _fail(reason: String, scrip: int) -> Dictionary:
	return {"ok": false, "error": reason, "scrip": scrip}
