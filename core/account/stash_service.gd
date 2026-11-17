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
## Accounts are kept in SQLite (`AccountStore`, `accounts.sqlite` in
## `save_dir`), where every save is one transaction. Several changes that must
## happen together (a trade between two players) go through `transaction`,
## which saves them all at once or changes nothing.
##
## Every call that can fail returns a Dictionary with "ok" (bool) and, when
## false, "error" (a short reason a client can show).

const StashRules := preload("res://core/account/stash_rules.gd")
const MasteryBook := preload("res://core/progression/mastery_book.gd")
const ProfileScript := preload("res://core/profile/profile.gd")
const Economy := preload("res://core/economy/economy.gd")
const BaseUpgrades := preload("res://core/base/base_upgrades.gd")
const Contracts := preload("res://core/economy/contracts.gd")
const Crafting := preload("res://core/progression/crafting.gd")
const DevMode := preload("res://core/dev/dev_mode.gd")  # DEV MODE
const AccountStore := preload("res://core/account/account_store.gd")
const SafeFile := preload("res://core/account/safe_file.gd")

const SAVE_VERSION := 1
const MIN_NAME := 3
const MAX_NAME := 20
const MIN_SECRET := 16

## The folder accounts live in: the SQLite database `accounts.sqlite`
## (`AccountStore`), beside the clan and phone records. Old one-file-per-account
## saves found here are imported into it once, the first time it opens.
var save_dir := "user://accounts"
## Tests turn this off so they never touch real saves.
var persist := true
## Keeps the old one-JSON-file-per-account format instead of SQLite (tests of
## the fallback; a build without the SQLite library falls back by itself).
var force_json := false
## The day contracts are counted on (`Contracts.today`). Below zero is the
## real date; tests set it to move time.
var day_override := -1

## Account id -> Account. Loaded lazily from disk.
var _accounts := {}
## The open store, made on first use (`_store_ready`).
var _store: RefCounted = null
## While a `transaction` runs: account id -> its save from before it, and the
## ids it changed, which are saved together when it ends.
var _tx_before := {}
var _tx_dirty: Array[String] = []
var _in_tx := false
## DEV MODE: account ids kept topped up with the dev stash (every piece of
## gear, max scrip) on this server. Only the host's own account joins it, and
## only on a server started from the editor with `--dev-host` (`dev_host`):
## it is the account that claims `host_profile` with the host's own secret,
## so nobody else gets in by signing in with the host's name. That server
## keeps its accounts in a separate folder, so real ones are never touched.
var dev_accounts: Array[String] = []
var dev_host := false
## The solo profile (`Profile.to_dict`) of the player hosting this server on
## their own computer, handed over when it starts (`main.gd host_and_join`).
## On their own server they are the same player as at home: the first time
## they sign in, their account here takes the profile's player state
## (`StashRules.CARRIED`), so they arrive with the loadout they left with.
## Only the profile's own name and secret claim it. Empty for anyone else's server.
var host_profile := {}
## Rolling backups of the whole save folder (accounts, clans, phone records)
## go in `backup_dir()`, one dated folder each: one when the server starts
## and then every `backup_every` seconds while it runs, keeping the newest
## `backups_kept`. 0 turns them off.
var backup_every := 3600.0
var backups_kept := 48
var _last_backup := -1.0


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
	## Lifetime renown. Only ever grows.
	var renown := 0
	## Money for the hub shops. Only ever changed here, on the server.
	var scrip := Economy.STARTING_SCRIP
	var arena_wins := 0
	var arena_losses := 0
	## The home base upgrades owned (ids from `BaseUpgrades`). Never lost.
	var base_upgrades: Array[String] = []
	## Contracts taken from the board and their progress (`Contracts.clean`).
	var contracts := {}
	## The blueprints known (blueprint item ids, see `Crafting`). Never lost.
	var blueprints: Array[String] = []

	## Adds the storable items in `ids` to the stash. A blueprint not known
	## yet is learned instead of stored. Anything that hands this account
	## items (loot, a reward) goes through here.
	func add_items(ids: Array) -> void:
		StashRules.add_items(stash, ids)
		Crafting.learn(stash, blueprints)

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
			StashRules.BARE_KEY: true,
			"mastery": mastery.to_dict(),
			"crates_granted": crates_granted,
			"deployed": deployed,
			"deployed_world": deployed_world,
			"raids_played": raids_played,
			"raids_extracted": raids_extracted,
			"kills": kills,
			"renown": renown,
			"scrip": scrip,
			"arena_wins": arena_wins,
			"arena_losses": arena_losses,
			"base_upgrades": base_upgrades,
			"contracts": contracts,
			"blueprints": blueprints,
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
		StashRules.upgrade_loadout(data, loadout)
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
		renown = maxi(0, int(data.get("renown", 0)))
		scrip = Economy.read_saved(data)
		arena_wins = maxi(0, int(data.get("arena_wins", 0)))
		arena_losses = maxi(0, int(data.get("arena_losses", 0)))
		base_upgrades = BaseUpgrades.clean(data.get("base_upgrades"))
		# Cleaned and brought up to date on first use (`_contracts_of`).
		var saved_contracts: Variant = data.get("contracts", {})
		contracts = saved_contracts.duplicate(true) if typeof(saved_contracts) == TYPE_DICTIONARY else {}
		blueprints = Crafting.clean(data.get("blueprints"))
		Crafting.learn(stash, blueprints)


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
		_adopt_host_profile(account, secret)
		_dev_top_up(account)  # DEV MODE
		return {"ok": true, "account_id": id, "created": false}
	if _is_saved(id):
		# The account is saved but could not be read: never start a new account
		# over it. The host can put one back from a backup.
		return _fail("This account could not be loaded. Ask the server's host to restore it from a backup.")
	account = Account.new()
	account.id = id
	account.shown_name = shown_name.strip_edges().left(MAX_NAME)
	account.salt = Crypto.new().generate_random_bytes(16).hex_encode()
	account.secret_hash = _hash(account.salt, secret)
	account.loadout = StashRules.new_player_loadout()
	StashRules.add_items(account.stash, ProfileScript.WELCOME_CRATE)
	_accounts[id] = account
	grant_gear_crates(account)
	_adopt_host_profile(account, secret)
	_dev_top_up(account)  # DEV MODE
	return {"ok": true, "account_id": id, "created": true}


## The host signing in to their own server: their account takes on the
## player state of the profile they left home with (see `host_profile`).
func _adopt_host_profile(account: Account, secret: String) -> void:
	if host_profile.is_empty() or account.id != id_for_name(str(host_profile.get("player_name", ""))) \
			or secret != str(host_profile.get("online_secret", "")):
		return
	var data := account.to_dict().duplicate(true)
	for key: String in StashRules.CARRIED:
		if host_profile.has(key):
			data[key] = host_profile[key]
	# The profile is the whole truth: nothing of this account is still out.
	data["deployed"] = []
	data["deployed_world"] = ""
	account.load_dict(data)
	host_profile = {}
	if dev_host and account.id not in dev_accounts:  # DEV MODE
		dev_accounts.append(account.id)
	_save(account)


## The account, from memory or disk, or null if there is none. Loading an
## account that was left deployed (the server stopped mid-raid) returns the
## deployed gear to its stash.
func load_account(id: String) -> Account:
	if _accounts.has(id):
		return _accounts[id]
	if not persist or id_for_name(id) != id or not _store_ready():
		return null
	var data: Dictionary = _store.read(id)
	if data.is_empty():
		return null
	var account := Account.new()
	account.load_dict(data)
	if account.id != id:
		push_warning("StashService: the save for %s holds another account" % id)
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
	if changed or not _is_saved(account.id):
		_save(account)


# --- Hub requests ------------------------------------------------------------

## What a client needs to draw its hub. Safe to send over the network: no
## secrets in it.
func snapshot(account_id: String) -> Dictionary:
	var account := load_account(account_id)
	if account == null:
		return _fail("No such account.")
	_dev_top_up(account)  # DEV MODE: gear lost in a run comes back
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
		"renown": account.renown,
		"scrip": account.scrip,
		"arena_wins": account.arena_wins,
		"arena_losses": account.arena_losses,
		"base_upgrades": account.base_upgrades.duplicate(),
		"contracts": _contracts_of(account).duplicate(true),
		"blueprints": account.blueprints.duplicate(),
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
	return _bank(account, Economy.buy(account.stash, account.scrip, shop_id, item_id))


## Sells up to `count` of a stash item. An empty `item_id` sells every trade
## good (loot that is not gear) at once.
func sell(account_id: String, item_id: String, count: int = 1) -> Dictionary:
	var account := load_account(account_id)
	if account == null:
		return _fail("No such account.")
	if account.is_deployed():
		return _fail("You are in a raid.")
	if item_id == "":
		return _bank(account, Economy.sell_loot(account.stash, account.scrip))
	return _bank(account, Economy.sell(account.stash, account.loadout, account.scrip, item_id, count))


## Buys a home base upgrade (an id from `BaseUpgrades`). What it needs and
## what it costs are decided here, never by the client.
func buy_upgrade(account_id: String, upgrade_id: String) -> Dictionary:
	var account := load_account(account_id)
	if account == null:
		return _fail("No such account.")
	if account.is_deployed():
		return _fail("You are in a raid.")
	return _bank(account, BaseUpgrades.buy(account.base_upgrades, account.scrip, upgrade_id))


## The contract board: "take" or "drop" job `job_id`, or "reroll" today's
## offers. The rules are `Contracts`; the server decides.
func contract(account_id: String, action: String, job_id: String = "") -> Dictionary:
	var account := load_account(account_id)
	if account == null:
		return _fail("No such account.")
	var state := _contracts_of(account)
	var result: Dictionary
	match action:
		"take":
			result = Contracts.take(state, job_id, today())
		"drop":
			result = Contracts.drop(state, job_id, today())
		"reroll":
			result = Contracts.reroll(state, today())
		_:
			return _fail("Unknown request.")
	if result.ok:
		_save(account)
	return result


## The day contracts count on.
func today() -> int:
	return day_override if day_override >= 0 else Contracts.today()


func _contracts_of(account: Account) -> Dictionary:
	account.contracts = Contracts.clean(account.contracts, today())
	return account.contracts


## Crafts one item (an id from `Crafting.RECIPES`) into the stash. Whether
## the blueprint is known and what it costs are decided here, never by the
## client.
func craft(account_id: String, item_id: String) -> Dictionary:
	var account := load_account(account_id)
	if account == null:
		return _fail("No such account.")
	if account.is_deployed():
		return _fail("You are in a raid.")
	return _bank(account, Crafting.craft(account.stash, account.blueprints, account.scrip, item_id))


## The account's balance, or 0 if there is no such account.
func scrip_of(account_id: String) -> int:
	var account := load_account(account_id)
	return account.scrip if account != null else 0


## Adds `delta` scrip (a cost when negative) for anything outside the
## shops, such as a wager or a reward. Refuses, changing nothing, if it would
## go below zero. Server code only: never pass on an amount a client chose.
func change_scrip(account_id: String, delta: int) -> bool:
	var account := load_account(account_id)
	if account == null or not Economy.can_change(account.scrip, delta):
		return false
	account.scrip = Economy.add(account.scrip, delta)
	_save(account)
	return true


# --- Market ledger -----------------------------------------------------------
# The five calls `MarketService` moves goods with. Server code only: the item
# and amount always come from the board's own listing, never from a client.

## How many of `item_id` the account's stash holds.
func count_of(account_id: String, item_id: String) -> int:
	var account := load_account(account_id)
	return account.stash.count(item_id) if account != null else 0


## Takes `count` of `item_id` out of the stash (unequipping it if the last
## one is worn). Refuses, changing nothing, while deployed or if there are
## not that many.
func take_items(account_id: String, item_id: String, count: int) -> bool:
	var account := load_account(account_id)
	if account == null or account.is_deployed() or count < 1 or account.stash.count(item_id) < count:
		return false
	for i in count:
		account.stash.erase(item_id)
	StashRules.validate_loadout(account.stash, account.loadout)
	_save(account)
	return true


## Puts items into the stash (a blueprint not known yet is learned).
func give_items(account_id: String, items: Array) -> bool:
	var account := load_account(account_id)
	if account == null:
		return false
	account.add_items(items)
	_save(account)
	return true


# --- Transactions -------------------------------------------------------------

## Runs several ledger calls as one all-or-nothing change, the way a trade
## must: either every step happens and every account it touched is saved in
## one write, or nothing changes, in memory or on disk. Each step is an Array
## naming one of the market's calls and its arguments:
##   ["take_items", account_id, item_id, count]
##   ["give_items", account_id, items]
##   ["change_scrip", account_id, delta]
## Steps run in order, so a step sees what the ones before it did (the money
## a sale just paid can pay the next step). Returns {"ok": true} or
## {"ok": false, "error", "step"} with the index of the step that refused.
## Server code only: build the steps from server data, never from a client.
func transaction(steps: Array) -> Dictionary:
	if _in_tx:
		return _fail("A transaction is already running.")
	if steps.is_empty():
		return {"ok": true}
	_in_tx = true
	_tx_before.clear()
	_tx_dirty.clear()
	for i in steps.size():
		if not _run_step(steps[i]):
			_rollback()
			var refused := _fail("The trade could not go through.")
			refused["step"] = i
			return refused
	var saves: Array = []
	for id in _tx_dirty:
		saves.append(_accounts[id].to_dict())
	if persist and _store_ready() and not _store.write(saves):
		_rollback()
		var unsaved := _fail("The trade could not be saved.")
		unsaved["step"] = -1
		return unsaved
	_end_tx()
	return {"ok": true}


func _run_step(step: Variant) -> bool:
	if typeof(step) != TYPE_ARRAY or step.size() < 3 or typeof(step[1]) != TYPE_STRING:
		return false
	var id: String = step[1]
	var account := load_account(id)
	if account == null:
		return false
	if not _tx_before.has(id):
		_tx_before[id] = account.to_dict().duplicate(true)
	match str(step[0]):
		"take_items":
			return step.size() == 4 and typeof(step[2]) == TYPE_STRING and typeof(step[3]) == TYPE_INT \
					and take_items(id, step[2], step[3])
		"give_items":
			return typeof(step[2]) == TYPE_ARRAY and give_items(id, step[2])
		"change_scrip":
			return typeof(step[2]) == TYPE_INT and change_scrip(id, step[2])
	return false


## Puts every account a failed transaction touched back as it was.
func _rollback() -> void:
	for id: String in _tx_before:
		var account: Account = _accounts.get(id)
		if account != null:
			account.load_dict(_tx_before[id])
	_end_tx()


func _end_tx() -> void:
	_in_tx = false
	_tx_before.clear()
	_tx_dirty.clear()


func _bank(account: Account, result: Dictionary) -> Dictionary:
	account.scrip = result.scrip
	if result.ok:
		_save(account)
	return result


# --- Raids -------------------------------------------------------------------

## Takes the account's loadout out of its stash for a raid in `world`.
## Returns {"ok", "kit", "picks"}: pass both straight to `Raid.add_player`.
## An account can only be deployed once at a time.
##
## A world with `gear_at_risk` off (the arena) gets the same kit, but nothing
## leaves the stash and the account is not marked as deployed: there is
## nothing to settle afterwards.
func deploy(account_id: String, world: WorldDef) -> Dictionary:
	var account := load_account(account_id)
	if account == null:
		return _fail("No such account.")
	_dev_top_up(account)  # DEV MODE
	if not world.gear_at_risk:
		var copy := account.stash.duplicate()
		var kit := StashRules.checkout(copy, account.loadout.duplicate(), world)
		return {"ok": true, "kit": kit, "picks": account.mastery.active_picks()}
	if account.is_deployed():
		return _fail("Your last body is still out there. Try again in a moment.")
	var taken: Array[String] = []
	var kit := StashRules.checkout(account.stash, account.loadout, world, taken)
	account.deployed = taken
	account.deployed_world = world.id
	_save(account)
	return {"ok": true, "kit": kit, "picks": account.mastery.active_picks()}


## The kit an account would deploy with, without taking anything out of the
## stash. For safe zones, where gear is worn to be seen and nothing is at risk.
func showcase(account_id: String, world: WorldDef) -> Dictionary:
	var account := load_account(account_id)
	if account == null:
		return _fail("No such account.")
	var kit := StashRules.checkout(account.stash.duplicate(), account.loadout.duplicate(), world)
	return {"ok": true, "kit": kit, "picks": account.mastery.active_picks()}


## Puts loot a deployed player handed in at a depot into their stash.
## `items` must come from the server's own raid, never from a client.
func bank(account_id: String, items: Array) -> Dictionary:
	var account := load_account(account_id)
	if account == null:
		return _fail("No such account.")
	if not account.is_deployed():
		return _fail("Not in a raid.")
	account.add_items(items)
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
		account.add_items(home)
	account.raids_played += 1
	if result.get("outcome", "") == "left":
		account.raids_extracted += 1
	account.kills += maxi(0, int(result.get("kills", 0)))
	account.renown += maxi(0, int(result.get("renown", 0)))
	account.scrip = Economy.add(account.scrip, Economy.payout(result))
	# Contracts count a sign-out and pay at once.
	# A blueprint reward is one the account does not know yet, and is learned.
	var paid := Contracts.settle(_contracts_of(account), result, today(), account.blueprints)
	account.scrip = Economy.add(account.scrip, paid.scrip)
	account.add_items(paid.items)
	var gained: Variant = result.get("mastery_xp", {})
	if typeof(gained) == TYPE_DICTIONARY:
		for track: Variant in gained:
			if typeof(track) == TYPE_STRING:
				account.mastery.add_xp(track, int(gained[track]))
	account.deployed.clear()
	account.deployed_world = ""
	StashRules.validate_loadout(account.stash, account.loadout)
	_save(account)
	return {"ok": true, "contracts": paid}


# --- Arena ---------------------------------------------------------------------

## Records an arena fight on the account.
func record_arena(account_id: String, won: bool) -> void:
	var account := load_account(account_id)
	if account == null:
		return
	if won:
		account.arena_wins += 1
	else:
		account.arena_losses += 1
	_save(account)


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


## DEV MODE: tops a dev account up (see `dev_accounts`). Does nothing to any
## other account.
func _dev_top_up(account: Account) -> void:
	if account.id not in dev_accounts or account.is_deployed():
		return
	var had := account.stash.size()
	var had_scrip := account.scrip
	account.scrip = DevMode.top_up(account.stash)
	var learned := DevMode.top_up_blueprints(account.blueprints)
	if DevMode.top_up_base(account.base_upgrades) or learned or account.stash.size() != had or account.scrip != had_scrip:
		_save(account)


## Opens the store in `save_dir` the first time it is needed (importing any
## old account files there once). False if it cannot be opened.
func _store_ready() -> bool:
	if _store != null and _store.is_open() and _store.dir == save_dir:
		return true
	if _store == null:
		_store = AccountStore.new()
	return _store.open(save_dir, force_json)


## The store in use, opened if needed: "sqlite" or "json" (null if `persist`
## is off or it cannot be opened). For tests and the server's log.
func store() -> RefCounted:
	return _store if persist and _store_ready() else null


## Closes the database. Safe to call more than once; the next save opens it
## again.
func close() -> void:
	if _store != null:
		_store.close()


func _is_saved(id: String) -> bool:
	return persist and _store_ready() and _store.has(id)


## Saves one account, at once, or with the rest of a running `transaction`
## when it ends.
func _save(account: Account) -> void:
	if _in_tx:
		if account.id not in _tx_dirty:
			_tx_dirty.append(account.id)
		return
	if not persist or not _store_ready():
		return
	if not _store.write([account.to_dict()]):
		push_warning("StashService: could not save %s" % account.id)


## Where the rolling backups go: beside the save folder, never inside it.
func backup_dir() -> String:
	return save_dir.trim_suffix("/") + "_backups"


## Backs up the save folder if one is due (see `backup_every`). Cheap to call
## often: every session sharing this service may call it, and only one copy
## is made. Returns the new backup's folder, or "". The clan and phone
## records are copied as files; the accounts database is copied by
## `AccountStore.backup_to`, never as the live file, which may be mid-write.
func backup_if_due() -> String:
	if not persist or backup_every <= 0.0:
		return ""
	var now := Time.get_unix_time_from_system()
	if _last_backup >= 0.0 and now - _last_backup < backup_every:
		return ""
	_last_backup = now
	var made := SafeFile.backup(save_dir, backup_dir(), backups_kept)
	if made != "" and _store_ready() and _store.kind == "sqlite":
		for suffix: String in ["", "-wal", "-shm"]:
			DirAccess.remove_absolute(made.path_join(AccountStore.FILE_NAME + suffix))
		if not _store.backup_to(made):
			push_warning("StashService: the accounts database could not be backed up to %s" % made)
	if made != "":
		print("Server: backed up accounts to %s" % ProjectSettings.globalize_path(made))
	return made


static func _hash(salt: String, secret: String) -> String:
	return (salt + ":" + secret).sha256_text()


static func _fail(reason: String) -> Dictionary:
	return {"ok": false, "error": reason}
