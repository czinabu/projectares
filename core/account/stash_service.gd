extends RefCounted
## Server side: owns every player's stash, loadout and mastery, so a client
## can never claim gear it does not have. The dedicated server holds one
## `StashService`; clients only ever send requests (sign in, equip, deploy)
## and get back snapshots.
##
## Load with `const StashService := preload("res://core/account/stash_service.gd")`
## (no `class_name`, so it works before Godot rescans the project).
##
## Lifecycle of one online life (a player's stay is a string of these):
##   1. `sign_in(name, secret)`        -> account id (creates the account the first time)
##   2. `equip` / `unequip` / `pick_mastery` while in the hub
##   3. `deploy(account_id, world)`    -> the kit and picks to pass to `Raid.add_player`
##   4. `bank(account_id, items)`      any number of times: loot handed in at a depot
##   5. one of:
##      `settle(account_id, result)`   the raid's `player_finished` result: what was
##                                     carried comes home if they left alive, and
##                                     mastery XP and the record apply either way
##      `cancel_deploy(account_id)`    the life never really started (join failed,
##                                     server shut down): the gear goes back
##
## A deploy that was never settled survives a server restart: `load_account`
## returns its gear to the stash, because a crash is not the player's fault.
##
## Every call that can fail returns a Dictionary with "ok" (bool) and, when
## false, "error" (a short reason a client can show).

const StashRules := preload("res://core/account/stash_rules.gd")
const MasteryBook := preload("res://core/progression/mastery_book.gd")
const ProfileScript := preload("res://core/profile/profile.gd")
const Economy := preload("res://core/economy/economy.gd")

const SAVE_VERSION := 1
const MIN_NAME := 3
const MAX_NAME := 20
const MIN_SECRET := 16

## Where account files live. One JSON file per account.
var save_dir := "user://accounts"
## Tests turn this off so they never touch real saves.
var persist := true

## Account id -> Account. Loaded lazily from disk.
var _accounts := {}


## One player's server-side record. Plain data plus its save format.
class Account:
	var id := ""
	var shown_name := ""
	var salt := ""
	var secret_hash := ""
	var stash: Array[String] = []
	## Slot name (see Loadout.SLOTS) -> item id.
	var loadout := {}
	var mastery := MasteryBook.new()
	var crates_granted: Array[String] = []
	## Items taken out of the stash for a raid that has not been settled.
	var deployed: Array[String] = []
	var deployed_world := ""
	var raids_played := 0
	var raids_extracted := 0
	var kills := 0
	## Money for the hub shops. Only ever changed here, on the server.
	var credits := Economy.STARTING_CREDITS

	func is_deployed() -> bool:
		return deployed_world != ""

	func to_dict() -> Dictionary:
		return {
			"version": SAVE_VERSION,
			"id": id,
			"name": shown_name,
			"salt": salt,
			"secret_hash": secret_hash,
			"stash": stash,
			"loadout": loadout,
			"mastery": mastery.to_dict(),
			"crates_granted": crates_granted,
			"deployed": deployed,
			"deployed_world": deployed_world,
			"raids_played": raids_played,
			"raids_extracted": raids_extracted,
			"kills": kills,
			"credits": credits,
		}

	func load_dict(data: Dictionary) -> void:
		id = str(data.get("id", ""))
		shown_name = str(data.get("name", id)).left(MAX_NAME)
		salt = str(data.get("salt", ""))
		secret_hash = str(data.get("secret_hash", ""))
		stash.clear()
		var saved_stash: Variant = data.get("stash", [])
		if typeof(saved_stash) == TYPE_ARRAY:
			StashRules.add_items(stash, saved_stash)
		loadout.clear()
		var saved_loadout: Variant = data.get("loadout", {})
		if typeof(saved_loadout) == TYPE_DICTIONARY:
			loadout = saved_loadout.duplicate()
		mastery.load_dict(data.get("mastery", {}))
		crates_granted.clear()
		for crate: Variant in data.get("crates_granted", []):
			if typeof(crate) == TYPE_STRING:
				crates_granted.append(crate)
		deployed.clear()
		var saved_deployed: Variant = data.get("deployed", [])
		if typeof(saved_deployed) == TYPE_ARRAY:
			StashRules.add_items(deployed, saved_deployed)
		deployed_world = str(data.get("deployed_world", ""))
		# Gear that is out in a raid still counts as owned until it settles.
		var owned := stash.duplicate()
		owned.append_array(deployed)
		StashRules.validate_loadout(owned, loadout)
		raids_played = maxi(0, int(data.get("raids_played", 0)))
		raids_extracted = maxi(0, int(data.get("raids_extracted", 0)))
		kills = maxi(0, int(data.get("kills", 0)))
		credits = Economy.read_saved(data)


# --- Identity ----------------------------------------------------------------

## A fresh random secret for a client to keep in its own profile and send
## with `sign_in`. Whoever holds it owns the account, so never log it.
static func new_secret() -> String:
	return Crypto.new().generate_random_bytes(24).hex_encode()


## Turns a shown name into an account id: lower case letters, digits, _ and -.
## Returns "" if the name is not usable.
static func id_for_name(shown_name: String) -> String:
	var id := ""
	for c in shown_name.strip_edges().to_lower():
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9") or c == "_" or c == "-":
			id += c
		elif c == " ":
			id += "_"
	if id.length() < MIN_NAME or id.length() > MAX_NAME:
		return ""
	return id


## Signs in, creating the account (with the starter crates) the first time a
## name is seen. Returns {"ok", "account_id", "created"} or {"ok": false, "error"}.
func sign_in(shown_name: String, secret: String) -> Dictionary:
	var id := id_for_name(shown_name)
	if id == "":
		return _fail("Names are %d to %d letters, digits, _ or -." % [MIN_NAME, MAX_NAME])
	if secret.length() < MIN_SECRET:
		return _fail("Bad sign-in secret.")
	var account := load_account(id)
	if account != null:
		if _hash(account.salt, secret) != account.secret_hash:
			return _fail("That name belongs to someone else.")
		grant_gear_crates(account)
		return {"ok": true, "account_id": id, "created": false}
	account = Account.new()
	account.id = id
	account.shown_name = shown_name.strip_edges().left(MAX_NAME)
	account.salt = Crypto.new().generate_random_bytes(16).hex_encode()
	account.secret_hash = _hash(account.salt, secret)
	StashRules.add_items(account.stash, ProfileScript.WELCOME_CRATE)
	_accounts[id] = account
	grant_gear_crates(account)
	return {"ok": true, "account_id": id, "created": true}


## The account, from memory or disk, or null if there is none. Loading an
## account that was left deployed (the server stopped mid-raid) returns the
## deployed gear to its stash.
func load_account(id: String) -> Account:
	if _accounts.has(id):
		return _accounts[id]
	if not persist or id_for_name(id) != id:
		return null
	var path := _path_for(id)
	if not FileAccess.file_exists(path):
		return null
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY:
		push_warning("StashService: %s is unreadable" % path)
		return null
	var account := Account.new()
	account.load_dict(data)
	if account.id != id:
		push_warning("StashService: %s holds another account" % path)
		return null
	_accounts[id] = account
	if account.is_deployed():
		_return_deployed(account)
	return account


## Gives an account every gear crate it has not had yet (see Profile.GEAR_CRATES).
func grant_gear_crates(account: Account) -> void:
	var changed := false
	for crate: String in ProfileScript.GEAR_CRATES:
		if crate not in account.crates_granted:
			account.crates_granted.append(crate)
			StashRules.add_items(account.stash, ProfileScript.GEAR_CRATES[crate])
			changed = true
	if changed or not FileAccess.file_exists(_path_for(account.id)):
		_save(account)


# --- Hub requests ------------------------------------------------------------

## What a client needs to draw its hub. Safe to send over the network: no
## secrets in it.
func snapshot(account_id: String) -> Dictionary:
	var account := load_account(account_id)
	if account == null:
		return _fail("No such account.")
	return {
		"ok": true,
		"account_id": account.id,
		"name": account.shown_name,
		"stash": account.stash.duplicate(),
		"loadout": account.loadout.duplicate(),
		"mastery": account.mastery.to_dict(),
		"deployed": account.is_deployed(),
		"stash_value": ItemDB.total_value(account.stash),
		"raids_played": account.raids_played,
		"raids_extracted": account.raids_extracted,
		"kills": account.kills,
		"credits": account.credits,
	}


func equip(account_id: String, slot: String, item_id: String) -> Dictionary:
	var account := load_account(account_id)
	if account == null:
		return _fail("No such account.")
	if account.is_deployed():
		return _fail("You are in a raid.")
	if not StashRules.can_equip(account.stash, slot, item_id):
		return _fail("That does not fit there.")
	account.loadout[slot] = item_id
	_save(account)
	return {"ok": true}


func unequip(account_id: String, slot: String) -> Dictionary:
	var account := load_account(account_id)
	if account == null:
		return _fail("No such account.")
	if account.is_deployed():
		return _fail("You are in a raid.")
	account.loadout.erase(slot)
	_save(account)
	return {"ok": true}


## Picks a mastery variant, or "" for stock.
func pick_mastery(account_id: String, track: String, variant_id: String) -> Dictionary:
	var account := load_account(account_id)
	if account == null:
		return _fail("No such account.")
	if not account.mastery.pick(track, variant_id):
		return _fail("Not unlocked yet.")
	_save(account)
	return {"ok": true}


# --- Shops -------------------------------------------------------------------

## Buys one item from a hub shop into the stash. The price and whether the
## shop sells it are decided here, never by the client.
func buy(account_id: String, shop_id: String, item_id: String) -> Dictionary:
	var account := load_account(account_id)
	if account == null:
		return _fail("No such account.")
	if account.is_deployed():
		return _fail("You are in a raid.")
	return _bank(account, Economy.buy(account.stash, account.credits, shop_id, item_id))


## Sells up to `count` of a stash item. An empty `item_id` sells every trade
## good (loot that is not gear) at once.
func sell(account_id: String, item_id: String, count: int = 1) -> Dictionary:
	var account := load_account(account_id)
	if account == null:
		return _fail("No such account.")
	if account.is_deployed():
		return _fail("You are in a raid.")
	if item_id == "":
		return _bank(account, Economy.sell_loot(account.stash, account.credits))
	return _bank(account, Economy.sell(account.stash, account.loadout, account.credits, item_id, count))


## The account's balance, or 0 if there is no such account.
func credits_of(account_id: String) -> int:
	var account := load_account(account_id)
	return account.credits if account != null else 0


## Adds `delta` credits (a cost when negative) for anything outside the
## shops, such as a wager or a reward. Refuses, changing nothing, if it would
## go below zero. Server code only: never pass on an amount a client chose.
func change_credits(account_id: String, delta: int) -> bool:
	var account := load_account(account_id)
	if account == null or not Economy.can_change(account.credits, delta):
		return false
	account.credits = Economy.add(account.credits, delta)
	_save(account)
	return true


func _bank(account: Account, result: Dictionary) -> Dictionary:
	account.credits = result.credits
	if result.ok:
		_save(account)
	return result


# --- Raids -------------------------------------------------------------------

## Takes the account's loadout out of its stash for a raid in `world`.
## Returns {"ok", "kit", "picks"}: pass both straight to `Raid.add_player`.
## An account can only be deployed once at a time.
func deploy(account_id: String, world: WorldDef) -> Dictionary:
	var account := load_account(account_id)
	if account == null:
		return _fail("No such account.")
	if account.is_deployed():
		return _fail("Your last body is still out there. Try again in a moment.")
	var taken: Array[String] = []
	var kit := StashRules.checkout(account.stash, account.loadout, world, taken)
	account.deployed = taken
	account.deployed_world = world.id
	_save(account)
	return {"ok": true, "kit": kit, "picks": account.mastery.active_picks()}


## Puts loot a deployed player handed in at a depot into their stash.
## `items` must come from the server's own raid, never from a client.
func bank(account_id: String, items: Array) -> Dictionary:
	var account := load_account(account_id)
	if account == null:
		return _fail("No such account.")
	if not account.is_deployed():
		return _fail("Not in a raid.")
	StashRules.add_items(account.stash, items)
	_save(account)
	return {"ok": true}


## Applies a finished life (the `player_finished` result from a SERVER raid):
## brought-home gear goes into the stash, the record and mastery XP update,
## and the deploy ends. What was deployed and not brought home is gone.
## The result must come from the server's own raid, never from a client.
func settle(account_id: String, result: Dictionary) -> Dictionary:
	var account := load_account(account_id)
	if account == null:
		return _fail("No such account.")
	if not account.is_deployed():
		return _fail("Not in a raid.")
	var home: Variant = result.get("brought_home", [])
	if typeof(home) == TYPE_ARRAY:
		StashRules.add_items(account.stash, home)
	account.raids_played += 1
	if result.get("outcome", "") == "left":
		account.raids_extracted += 1
	account.kills += maxi(0, int(result.get("kills", 0)))
	account.credits = Economy.add(account.credits, Economy.payout(result))
	var gained: Variant = result.get("mastery_xp", {})
	if typeof(gained) == TYPE_DICTIONARY:
		for track: Variant in gained:
			if typeof(track) == TYPE_STRING:
				account.mastery.add_xp(track, int(gained[track]))
	account.deployed.clear()
	account.deployed_world = ""
	StashRules.validate_loadout(account.stash, account.loadout)
	_save(account)
	return {"ok": true}


## Calls off a deploy that never became a real run: the gear goes back.
func cancel_deploy(account_id: String) -> Dictionary:
	var account := load_account(account_id)
	if account == null:
		return _fail("No such account.")
	if not account.is_deployed():
		return _fail("Not in a raid.")
	_return_deployed(account)
	return {"ok": true}


## True while the account has gear out in a raid.
func is_deployed(account_id: String) -> bool:
	var account := load_account(account_id)
	return account != null and account.is_deployed()


## Returns every outstanding deploy, for a clean server shutdown.
func cancel_all_deploys() -> void:
	for account: Account in _accounts.values():
		if account.is_deployed():
			_return_deployed(account)


# --- Internals ---------------------------------------------------------------

func _return_deployed(account: Account) -> void:
	StashRules.add_items(account.stash, account.deployed)
	account.deployed.clear()
	account.deployed_world = ""
	StashRules.validate_loadout(account.stash, account.loadout)
	_save(account)


func _path_for(id: String) -> String:
	return save_dir.path_join(id + ".json")


func _save(account: Account) -> void:
	if not persist:
		return
	DirAccess.make_dir_recursive_absolute(save_dir)
	# Write beside the real file, then swap, so a crash never leaves half a save.
	var path := _path_for(account.id)
	var temp := path + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		push_warning("StashService: could not write %s" % temp)
		return
	file.store_string(JSON.stringify(account.to_dict(), "\t"))
	file.close()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	DirAccess.rename_absolute(temp, path)


static func _hash(salt: String, secret: String) -> String:
	return (salt + ":" + secret).sha256_text()


static func _fail(reason: String) -> Dictionary:
	return {"ok": false, "error": reason}
