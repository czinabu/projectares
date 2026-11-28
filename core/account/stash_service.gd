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
##
## Official servers do not hold one of these themselves: they share the one
## inside the account service (`core/account/account_service.gd`) and reach
## it through an `AccountLink` (`core/account/account_link.gd`), which offers
## these same calls. So a session calls its accounts with `await`, which
## costs nothing here, where every call answers at once.

const StashRules := preload("res://core/account/stash_rules.gd")
const MasteryBook := preload("res://core/progression/mastery_book.gd")
const ProfileScript := preload("res://core/profile/profile.gd")
const Economy := preload("res://core/economy/economy.gd")
const BaseUpgrades := preload("res://core/base/base_upgrades.gd")
const BasePlan := preload("res://core/base/base_plan.gd")
const Contracts := preload("res://core/economy/contracts.gd")
const RaceLeague := preload("res://core/race/race_league.gd")
const Crafting := preload("res://core/progression/crafting.gd")
const SafetyNets := preload("res://core/economy/safety_nets.gd")
const DevMode := preload("res://core/dev/dev_mode.gd")  # DEV MODE
const AccountStore := preload("res://core/account/account_store.gd")
const SafeFile := preload("res://core/account/safe_file.gd")

const SAVE_VERSION := 1
const MIN_NAME := 3
const MAX_NAME := 20
const MIN_SECRET := 16
## How long a sign-in token is good for, in seconds (see `sign_in_with`).
const TOKEN_LIFE := 12.0 * 3600.0
## Recovery codes (`make_recovery_code`): letters and digits that cannot be
## mistaken for each other (no 0/O, 1/I/L), 16 of them in groups of 4. 32
## letters make 80 random bits, far past guessing.
const RECOVERY_LETTERS := "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
const RECOVERY_LENGTH := 16

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
## Tests only: the unix time insurance counts on, when 0 or more.
var time_override := -1.0

## Account id -> Account. Loaded lazily from disk.
var _accounts := {}
## Account id -> kept race ghosts (`keep_ghost`), read from disk when first asked.
var _ghosts := {}
## The open store, made on first use (`_store_ready`).
var _store: RefCounted = null
## While a `transaction` runs: account id -> its save from before it, and the
## ids it changed, which are saved together when it ends.
var _tx_before := {}
var _tx_dirty: Array[String] = []
var _in_tx := false
## While a hold runs (`begin_hold`): the ids of the accounts saved in it,
## written together when it ends.
var _holding := false
var _held: Array[String] = []
## Sign-in tokens: the hash of each token -> {"account", "until" (unix time)},
## and each account's current one. Kept in memory only: a token that is gone
## just means signing in with the secret again.
var _tokens := {}
var _token_of := {}
## Whether an account found deployed when it is loaded gets its gear back
## (the server that held the deploy stopped, so the life is gone). The
## account service turns this off: its game servers outlive it, and it
## returns a server's deploys when that server says it started afresh
## (`release_deploys`).
var returns_lost_deploys := true
## With `track_touched`, the id of every account saved goes in `touched`,
## for whoever clears it to see what a call changed (the account service,
## which then tells the game servers those players are on).
var track_touched := false
var touched: Array[String] = []
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
	## The hash of the account's recovery code (`make_recovery_code`), or ""
	## when it has none. Only the hash is kept: the code is shown once.
	var recovery_hash := ""
	var stash: Array[String] = []
	## Slot name (see Loadout.SLOTS) -> item id.
	var loadout := {}
	var mastery := MasteryBook.new()
	var crates_granted: Array[String] = []
	## Items taken out of the stash for a raid that has not been settled.
	var deployed: Array[String] = []
	var deployed_world := ""
	## Which game server holds the deploy and the request that made it (the
	## account service only; "" on a server that keeps its own accounts).
	var deployed_by := ""
	var deploy_ref := ""
	var raids_played := 0
	var raids_extracted := 0
	var kills := 0
	## Lifetime renown. Only ever grows.
	var renown := 0
	## Money for the hub shops. Only ever changed here, on the server.
	var scrip := Economy.STARTING_SCRIP
	var arena_wins := 0
	var arena_losses := 0
	## The week the Blade Tournament's weekly prize was last won, or -1.
	var arena_prize_week := -1
	## The racing league (`RaceLeague`): moved only by live races.
	var racing := RaceLeague.fresh()
	## The home base upgrades owned (ids from `BaseUpgrades`). Never lost.
	var base_upgrades: Array[String] = []
	## Which room stands in which socket off the base's hub (`BasePlan`).
	var base_plan: Dictionary = BasePlan.clean(null)
	## Contracts taken from the board and their progress (`Contracts.clean`).
	var contracts := {}
	## The blueprints known (blueprint item ids, see `Crafting`). Never lost.
	var blueprints: Array[String] = []
	## The insurance policy (`SafetyNets`): {"item", "ready_at"}.
	var insurance := SafetyNets.fresh()

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
			"recovery_hash": recovery_hash,
			"stash": stash,
			"loadout": loadout,
			StashRules.BARE_KEY: true,
			"mastery": mastery.to_dict(),
			"crates_granted": crates_granted,
			"deployed": deployed,
			"deployed_world": deployed_world,
			"deployed_by": deployed_by,
			"deploy_ref": deploy_ref,
			"raids_played": raids_played,
			"raids_extracted": raids_extracted,
			"kills": kills,
			"renown": renown,
			"scrip": scrip,
			"arena_wins": arena_wins,
			"arena_losses": arena_losses,
			"arena_prize_week": arena_prize_week,
			"racing": racing,
			"base_upgrades": base_upgrades,
			"base_plan": base_plan,
			"contracts": contracts,
			"blueprints": blueprints,
			"insurance": insurance,
		}

	func load_dict(data: Dictionary) -> void:
		id = str(data.get("id", ""))
		shown_name = str(data.get("name", id)).left(MAX_NAME)
		salt = str(data.get("salt", ""))
		secret_hash = str(data.get("secret_hash", ""))
		recovery_hash = str(data.get("recovery_hash", ""))
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
		deployed_by = str(data.get("deployed_by", ""))
		deploy_ref = str(data.get("deploy_ref", ""))
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
		arena_prize_week = int(data.get("arena_prize_week", -1))
		racing = RaceLeague.clean(data.get("racing"))
		base_upgrades = BaseUpgrades.clean(data.get("base_upgrades"))
		base_plan = BasePlan.clean(data.get("base_plan"))
		# Cleaned and brought up to date on first use (`_contracts_of`).
		var saved_contracts: Variant = data.get("contracts", {})
		contracts = saved_contracts.duplicate(true) if typeof(saved_contracts) == TYPE_DICTIONARY else {}
		blueprints = Crafting.clean(data.get("blueprints"))
		Crafting.learn(stash, blueprints)
		insurance = SafetyNets.clean(data.get("insurance"))

	## The insurance policy, lapsed first if its item is no longer owned
	## (the stash, or out on this deploy).
	func policy() -> Dictionary:
		var owned := stash.duplicate()
		owned.append_array(deployed)
		SafetyNets.lapse(insurance, owned)
		return insurance


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


## Signing in, however the player proves who they are. `credentials` names a
## "method":
##   "secret"  {"name", "secret"}: the name and the secret the game made
##             (`sign_in`). The account is made the first time a name is seen.
##   "token"   {"token"}: a token an earlier sign-in handed out (below).
##   "recovery" {"name", "code", "secret"}: the account's recovery code, from
##             a computer whose game holds another secret (`recover`). The
##             account takes on that secret, so the old computer's stops
##             working, and the code is used up.
## A new way to sign in (a store login such as Steam, checked with the
## store's web service) is a new method here that ends in an account id, and
## nothing past this call changes: everything else is keyed by that id.
##
## Returns {"ok", "account_id", "created"} and, after a "secret" sign-in,
## "token": a random string good for `TOKEN_LIFE` that stands for this
## sign-in. The game keeps it and shows it to the next server it travels to
## instead of its secret; that server asks `verify`. An account has one
## token at a time: signing in with the secret again replaces it. A refused
## token answers {"ok": false, "error", "expired": true}: sign in with the
## secret.
func sign_in_with(credentials: Dictionary) -> Dictionary:
	match str(credentials.get("method", "secret")):
		"secret":
			var result := sign_in(str(credentials.get("name", "")).left(64), str(credentials.get("secret", "")).left(256))
			if result.ok:
				result["token"] = _issue_token(result.account_id)
			return result
		"token":
			return verify(str(credentials.get("token", "")).left(256))
		"recovery":
			var recovered := recover(str(credentials.get("name", "")).left(64), str(credentials.get("code", "")).left(64),
					str(credentials.get("secret", "")).left(256))
			if recovered.ok:
				recovered["token"] = _issue_token(recovered.account_id)
			return recovered
	return _fail("This server does not know that way of signing in.")


## Whose sign-in `token` stands for: {"ok", "account_id", "created": false},
## or a refusal with "expired" set.
func verify(token: String) -> Dictionary:
	var entry: Variant = _tokens.get(token.sha256_text())
	if token == "" or entry == null or float(entry.until) < Time.get_unix_time_from_system() \
			or load_account(str(entry.account)) == null:
		var refused := _fail("Sign in again.")
		refused["expired"] = true
		return refused
	return {"ok": true, "account_id": str(entry.account), "created": false}


func _issue_token(account_id: String) -> String:
	_tokens.erase(_token_of.get(account_id, ""))
	var now := Time.get_unix_time_from_system()
	for hash: String in _tokens.keys():
		if float(_tokens[hash].until) < now:
			_token_of.erase(_tokens[hash].account)
			_tokens.erase(hash)
	var token := Crypto.new().generate_random_bytes(32).hex_encode()
	_tokens[token.sha256_text()] = {"account": account_id, "until": now + TOKEN_LIFE}
	_token_of[account_id] = token.sha256_text()
	return token


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


## A new recovery code for the account (DESIGN.md section 14, "Sign-in"):
## {"ok", "code"}, the code written "ABCD-EFGH-JKMN-PQRS". Only its hash is
## kept, so this is the one time it is shown; a new one replaces the last.
## Whoever holds it and the account's name can move the account to another
## computer (`recover`).
func make_recovery_code(account_id: String) -> Dictionary:
	var account := load_account(account_id)
	if account == null:
		return _fail("No such account.")
	var bytes := Crypto.new().generate_random_bytes(RECOVERY_LENGTH)
	var code := ""
	for i in RECOVERY_LENGTH:
		# 256 is a multiple of the 32 letters, so each is as likely as the next.
		code += RECOVERY_LETTERS[bytes[i] % RECOVERY_LETTERS.length()]
	account.recovery_hash = _hash(account.salt, code)
	_save(account)
	return {"ok": true, "code": format_recovery_code(code)}


## The letters of a recovery code as a player may type them: upper case,
## with anything that is not one of `RECOVERY_LETTERS` (spaces, dashes)
## left out.
static func clean_recovery_code(code: String) -> String:
	var clean := ""
	for c in code.to_upper():
		if c in RECOVERY_LETTERS:
			clean += c
	return clean


## A code's letters in groups of four, for reading off and writing down.
static func format_recovery_code(code: String) -> String:
	var groups: Array[String] = []
	for i in range(0, code.length(), 4):
		groups.append(code.substr(i, 4))
	return "-".join(groups)


## Moves the account named `shown_name` to a computer whose game holds
## `secret`, if `code` is its recovery code: the account takes on that
## secret (the old one stops working), any sign-in token is dropped and the
## code is used up. Returns what `sign_in` does.
func recover(shown_name: String, code: String, secret: String) -> Dictionary:
	var id := id_for_name(shown_name)
	if id == "":
		return _fail("Names are %d to %d letters, digits, _ or -." % [MIN_NAME, MAX_NAME])
	if secret.length() < MIN_SECRET:
		return _fail("Bad sign-in secret.")
	var account := load_account(id)
	var clean := clean_recovery_code(code)
	if account == null or account.recovery_hash == "" or clean.length() != RECOVERY_LENGTH \
			or _hash(account.salt, clean) != account.recovery_hash:
		return _fail("That name and recovery code do not match an account here.")
	account.secret_hash = _hash(account.salt, secret)
	account.recovery_hash = ""
	_tokens.erase(_token_of.get(id, ""))
	_token_of.erase(id)
	_save(account)
	grant_gear_crates(account)
	_dev_top_up(account)  # DEV MODE
	return {"ok": true, "account_id": id, "created": false, "recovered": true}


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
	if account.is_deployed() and returns_lost_deploys:
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
		"arena_prize_week": account.arena_prize_week,
		"racing": account.racing.duplicate(true),
		"base_upgrades": account.base_upgrades.duplicate(),
		"base_plan": account.base_plan.duplicate(),
		"contracts": _contracts_of(account).duplicate(true),
		"blueprints": account.blueprints.duplicate(),
		"insurance": account.policy().duplicate(),
	}


## The same as `snapshot`. An `AccountLink` answers `snapshot` at once from
## what it holds and only for accounts signed in on its server; `fetch` asks
## for any account and is awaited.
func fetch(account_id: String) -> Dictionary:
	return snapshot(account_id)


## The name an account shows, or its id if there is no such account.
func name_of(account_id: String) -> String:
	var account := load_account(account_id)
	return account.shown_name if account != null else account_id


## Nobody is signed in to this account on this server any more. Only an
## `AccountLink` cares (it stops keeping the account up to date).
func release(_account_id: String) -> void:
	pass


## False: this server keeps its own accounts (see `AccountLink.is_remote`).
func is_remote() -> bool:
	return false


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


## Changes the account's home base plan (`BasePlan.change`): a room moved
## into a socket (the room there taking its old socket), or with `key`
## "shape" or "style:<room>" a hub shape or room style, which the account's
## upgrades must unlock. Free, and only ever how things stand, so it is
## allowed while deployed too.
func place_room(account_id: String, key: String, value: String) -> Dictionary:
	var account := load_account(account_id)
	if account == null:
		return _fail("No such account.")
	var result := BasePlan.change(account.base_plan, account.base_upgrades, key, value)
	if not result.ok:
		return _fail(str(result.error))
	account.base_plan = result.plan
	_save(account)
	return {"ok": true}


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


## Insurance (`SafetyNets`): "insure" item `item_id` or "cancel" the policy.
## What it costs and whether it may be insured are decided here.
func insure(account_id: String, action: String, item_id: String = "") -> Dictionary:
	var account := load_account(account_id)
	if account == null:
		return _fail("No such account.")
	if account.is_deployed():
		return _fail("You are in a raid.")
	match action:
		"insure":
			return _bank(account, SafetyNets.insure(account.policy(), account.stash, account.scrip,
					item_id, now()))
		"cancel":
			var result := SafetyNets.cancel(account.policy())
			if result.ok:
				_save(account)
			return result
	return _fail("Unknown request.")


## The unix time insurance counts on.
func now() -> float:
	return time_override if time_override >= 0.0 else Time.get_unix_time_from_system()


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
	if _holding:
		# Written with the rest of the hold, when it ends.
		for id in _tx_dirty:
			if id not in _held:
				_held.append(id)
		_end_tx()
		return {"ok": true}
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


# --- Holds ---------------------------------------------------------------------
# How the account service does one request exactly once: every save the
# request makes is held back and written in one go together with the
# request's receipt (its id and answer). A request sent again because its
# answer was lost finds the receipt and is answered from it.

## Starts holding saves back (see `end_hold`).
func begin_hold() -> void:
	_holding = true
	_held.clear()


## Ends the hold `begin_hold` started and writes every account saved in it,
## with `receipt` ([request id, answer text], or [] for none), all or
## nothing. Returns {"ok", "changed": the account ids}. If the write fails
## those accounts are dropped from memory, so they are read again as they
## were saved, and the caller must not say the request worked.
func end_hold(receipt: Array = []) -> Dictionary:
	_holding = false
	var changed := _held.duplicate()
	_held.clear()
	var saves: Array = []
	for id in changed:
		if _accounts.has(id):
			saves.append(_accounts[id].to_dict())
	if persist and _store_ready() and not _store.write(saves, receipt):
		for id in changed:
			_accounts.erase(id)
		return {"ok": false, "changed": changed}
	return {"ok": true, "changed": changed}


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
##
## `by` and `ref` are the account service's: the game server that asked and
## the request it asked with, kept on the account so only that server can
## bank into, settle or call off the deploy.
func deploy(account_id: String, world: WorldDef, by := "", ref := "") -> Dictionary:
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
	account.deployed_by = by
	account.deploy_ref = ref
	_save(account)
	# The insured item, if this deploy took it: pass it to `Raid.add_player`.
	return {"ok": true, "kit": kit, "picks": account.mastery.active_picks(),
			"insured": SafetyNets.covered(account.policy(), taken)}


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
	# The safety nets: salvage for crafted gear lost with the body, and the
	# insured item's claim (it came home in `brought_home`).
	var salvage: Variant = result.get("salvage", [])
	if typeof(salvage) == TYPE_ARRAY:
		account.add_items(salvage)
	SafetyNets.claim(account.insurance, str(result.get("recalled", "")), now())
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
	account.deployed_by = ""
	account.deploy_ref = ""
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


## Pays the Blade Tournament's weekly prize (`Arena._crown`): `items` go to
## the account once in `week`. Only an `Arena` on the authority sends it.
func arena_prize(account_id: String, week: int, items: Array) -> Dictionary:
	var account := load_account(account_id)
	if account == null:
		return _fail("No such account.")
	if account.arena_prize_week == week:
		return _fail("This week's prize is already won.")
	var given: Array = []
	for id: Variant in items:
		if typeof(id) == TYPE_STRING and ItemDB.has_item(id) and StashRules.storable(id):
			given.append(id)
	account.arena_prize_week = week
	account.add_items(given)
	_save(account)
	return {"ok": true, "items": given}


## Records a live race's result on the account (`RaceLeague.apply`): the
## league standing moves and the race's scrip is paid, capped by the day.
func record_race(account_id: String, result: Dictionary) -> Dictionary:
	var account := load_account(account_id)
	if account == null:
		return _fail("No such account.")
	var applied := RaceLeague.apply(account.racing, result, today())
	account.racing = applied.state
	account.scrip = Economy.add(account.scrip, int(applied.scrip))
	_save(account)
	return {"ok": true, "points": applied.points, "scrip": applied.scrip, "promoted": applied.promoted}


## Fits a tuning kit to a machine on the account (`RaceLeague.set_kit`:
## only a kit the account's league has unlocked). Only a `Race` on the
## authority sends one, from its pit bench.
func tune_race(account_id: String, machine: String, kit: String) -> Dictionary:
	var account := load_account(account_id)
	if account == null:
		return _fail("No such account.")
	if not RaceLeague.set_kit(account.racing, machine, kit):
		return _fail("That kit is not yours to fit.")
	_save(account)
	return {"ok": true}


## Keeps a lap's ghost (`RaceGhost.to_packed`) on the account when it is
## its best on that track and machine (`RaceLeague.note_best`): the best
## time goes in the account's racing state, the ghost beside the account in
## a file of its own (`ghosts/<id>.json`, never in the account's row, so a
## save stays small). Only a `Race` on the authority sends one.
func keep_ghost(account_id: String, track_id: String, machine: String, lap: float, packed: String) -> Dictionary:
	var account := load_account(account_id)
	if account == null:
		return _fail("No such account.")
	if RaceGhost.from_packed(packed) == null:
		return _fail("That is not a lap.")
	if not RaceLeague.note_best(account.racing, track_id, machine, lap):
		return {"ok": true, "kept": false}
	var ghosts := _ghosts_of(account_id)
	ghosts[RaceLeague.ghost_key(track_id, machine)] = {"lap": lap, "ghost": packed}
	# Pairs that lost their best (a full list) lose their ghost too.
	for key: String in ghosts.keys():
		if not account.racing.bests.has(key):
			ghosts.erase(key)
	if persist:
		DirAccess.make_dir_recursive_absolute(save_dir.path_join("ghosts"))
		SafeFile.write(_ghost_path(account_id), JSON.stringify(ghosts))
	_save(account)
	return {"ok": true, "kept": true}


## The fastest kept ghost on a track among the accounts `ids` (on
## `machine`, or any machine with none): {"ok", "id", "name", "machine",
## "lap", "ghost"}, or {"ok": false} when none of them has one.
func race_ghost(ids: Array, track_id: String, machine := "") -> Dictionary:
	var best := {}
	for id: Variant in ids.slice(0, 64):
		var account := load_account(str(id))
		if account == null:
			continue
		var on := machine if machine != "" else RaceLeague.best_machine(account.racing, track_id)
		var lap := RaceLeague.best_lap(account.racing, track_id, on)
		if lap <= 0.0 or (not best.is_empty() and lap >= float(best.lap)):
			continue
		var kept: Dictionary = _ghosts_of(account.id).get(RaceLeague.ghost_key(track_id, on), {})
		if kept.is_empty():
			continue
		best = {"ok": true, "id": account.id, "name": account.shown_name, "machine": on, "lap": lap,
				"ghost": str(kept.get("ghost", ""))}
	return best if not best.is_empty() else _fail("No lap kept there yet.")


## Each of the accounts `ids`' best lap on every track they have one:
## [{"name", "track", "machine", "time"}], fastest first (the pit boards'
## friends' times).
func race_bests(ids: Array) -> Array:
	var rows: Array = []
	for id: Variant in ids.slice(0, 64):
		var account := load_account(str(id))
		if account == null:
			continue
		var tracks := {}
		for key: String in account.racing.get("bests", {}):
			tracks[key.get_slice("|", 0)] = true
		for track_id: String in tracks:
			var machine := RaceLeague.best_machine(account.racing, track_id)
			rows.append({"name": account.shown_name, "track": track_id, "machine": machine,
					"time": RaceLeague.best_lap(account.racing, track_id, machine)})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.time) < float(b.time))
	return rows


func _ghosts_of(account_id: String) -> Dictionary:
	if not _ghosts.has(account_id):
		var read: Variant = SafeFile.read_json(_ghost_path(account_id)) if persist else null
		var kept := {}
		if read is Dictionary:
			for key: Variant in read:
				if read[key] is Dictionary:
					kept[str(key)] = read[key]
		_ghosts[account_id] = kept
	return _ghosts[account_id]


func _ghost_path(account_id: String) -> String:
	return save_dir.path_join("ghosts").path_join(account_id.validate_filename() + ".json")


## Calls off a deploy that never became a real run: the gear goes back.
func cancel_deploy(account_id: String) -> Dictionary:
	var account := load_account(account_id)
	if account == null:
		return _fail("No such account.")
	if not account.is_deployed():
		return _fail("Not in a raid.")
	_return_deployed(account)
	return {"ok": true}


## Calls off the deploy that request `ref` made, if it is still the one out.
## For a server that asked to deploy and never heard the answer: it cannot
## know whether the gear left the stash, and it must not call off a deploy
## made before or after. Always {"ok": true}.
func undo_deploy(account_id: String, ref: String) -> Dictionary:
	var account := load_account(account_id)
	if account != null and account.is_deployed() and ref != "" and account.deploy_ref == ref:
		_return_deployed(account)
	return {"ok": true}


## True while game server `by` holds this account's deploy.
func holds_deploy(account_id: String, by: String) -> bool:
	var account := load_account(account_id)
	return account != null and account.is_deployed() and account.deployed_by == by


## Returns every deploy game server `by` holds, in memory or saved: it has
## started afresh, so those lives are gone. Returns how many.
func release_deploys(by: String) -> int:
	var ids: Array[String] = []
	if persist and _store_ready():
		ids = _store.deployed_ids()
	for id: String in _accounts:
		if id not in ids:
			ids.append(id)
	var count := 0
	for id in ids:
		var account := load_account(id)
		if account != null and account.is_deployed() and account.deployed_by == by:
			_return_deployed(account)
			count += 1
	return count


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
	account.deployed_by = ""
	account.deploy_ref = ""
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
	if track_touched and account.id not in touched:
		touched.append(account.id)
	if _in_tx:
		if account.id not in _tx_dirty:
			_tx_dirty.append(account.id)
		return
	if _holding:
		if account.id not in _held:
			_held.append(account.id)
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
