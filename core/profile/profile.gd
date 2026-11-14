extends Node
## Autoload `Profile`: what the player keeps between raids. Shared by all worlds.
## This is the save for solo play. Online, the server keeps its own copy of
## your stash (`core/account/stash_service.gd`) and this one is not used.
##
## Gear rules: the stash is safe. Whatever is in the loadout leaves the stash
## when you deploy, and only comes back if you leave the world alive.

const SAVE_PATH := "user://profile.json"
## DEV MODE: the separate save dev mode plays on (`core/dev/dev_mode.gd`), so
## the real stash above is never touched by it.
const DEV_SAVE_PATH := "user://profile_dev.json"
const DevMode := preload("res://core/dev/dev_mode.gd")
const MasteryBook := preload("res://core/progression/mastery_book.gd")
## The same gear rules the server's StashService uses.
const StashRules := preload("res://core/account/stash_rules.gd")
## The same money rules the server's StashService uses.
const Economy := preload("res://core/economy/economy.gd")
## The same home base upgrade rules the server's StashService uses.
const BaseUpgrades := preload("res://core/base/base_upgrades.gd")
## The same blueprint and crafting rules the server's StashService uses.
const Crafting := preload("res://core/progression/crafting.gd")
const Human := preload("res://core/visual/human.gd")
## Given once to every new player: a first gun, a frame, some healing and the
## starter motorbike (DESIGN.md section 8).
const WELCOME_CRATE: Array[String] = ["rifle_carbine", "frame_trooper", "medkit", "medkit", "bike_scrapper"]
## Later one-time crates, by name, granted to existing profiles. None for
## now: gear to test new features with comes from dev mode, never from a
## crate every player gets (Caleb's call, before the friends playtest).
const GEAR_CRATES := {}
## A save older than this is set back to a fresh player once, keeping who
## you are (name, look, online secret, controls), with the old save kept
## beside it at `FRESH_START_BACKUP`. 1: clears the free test gear, base
## upgrades and anything dev mode leaked in before the playtest.
const FRESH_START := 1
const FRESH_START_BACKUP := "user://profile_before_fresh_start.json"

## Tests turn this off so they never touch a real save.
var persist := true
## The file this profile saves to: `SAVE_PATH`, or `DEV_SAVE_PATH` in dev mode.
var save_path := SAVE_PATH
var stash: Array[String] = []
## Slot name (see Loadout.SLOTS) -> item id. A missing slot is bare.
var loadout := {}
var welcome_granted := false
## The `FRESH_START` this save has had.
var fresh_start := FRESH_START
var crates_granted: Array[String] = []
## Weapon, ability and frame mastery. Never lost on death.
var mastery := MasteryBook.new()
## How the melee side is picked: "mouse" (flick) or "move" (movement keys).
var melee_control := "move"
## Shown to other players online, and the last server address joined.
var player_name := "Raider"
var last_server := "127.0.0.1"
## Where your base's door leads: the address of the server you last joined
## from the uplink, or "" for a server of your own, started on this computer.
var home_server := ""
## Proves to a server that an online account is yours. Made on first use.
var online_secret := ""
## How your character looks (see `core/visual/human.gd`). Cosmetic only.
var appearance := Human.player_look({})
## Lives started, and lives that ended by leaving alive. The names are from
## when a life was a timed raid; they stay so old saves keep loading.
## Lifetime renown: only ever grows, and sets your rank (see `RenownLedger`).
var renown := 0
var raids_played := 0
var raids_extracted := 0
var kills := 0
## Money for the hub shops. Safe between raids: only gear is ever at risk.
var scrip := Economy.STARTING_SCRIP
var arena_wins := 0
var arena_losses := 0
## The home base upgrades owned (ids from `BaseUpgrades`). Never lost. A save
## from before upgrades existed has none: the starter bunker.
var base_upgrades: Array[String] = []
## The blueprints known (blueprint item ids, see `Crafting`). Never lost.
var blueprints: Array[String] = []


func _ready() -> void:
	# A dedicated server never uses the solo profile, so it never writes one
	# (it would race the game that started it for the same files).
	if "--server" in OS.get_cmdline_user_args():
		persist = false
	# A new player starts with nothing on; a save replaces it.
	loadout = StashRules.new_player_loadout()
	load_profile()
	grant_welcome_crate()
	grant_gear_crates()
	# DEV MODE: start on the dev save if dev mode was left on.
	DevMode.ensure_loaded()
	apply_dev_mode()


## DEV MODE: puts this profile on the save dev mode asks for (the dev save
## while it is on, the real one otherwise) and, while on, tops the dev stash
## up with everything. Call again whenever dev mode changes or after a run.
func apply_dev_mode() -> void:
	use_save(DEV_SAVE_PATH if DevMode.active() else SAVE_PATH)
	if save_path == DEV_SAVE_PATH:
		scrip = DevMode.top_up(stash)
		DevMode.top_up_base(base_upgrades)
		DevMode.top_up_blueprints(blueprints)
		save()


## Saves to the current file, then switches to `path` and loads it. Who you
## are (name, look, online secret, controls) comes along, so dev mode and
## online play see the same player.
func use_save(path: String) -> void:
	if path == save_path:
		return
	save()
	var keep := {"player_name": player_name, "last_server": last_server, "home_server": home_server,
			"online_secret": online_secret,
			"melee_control": melee_control, "appearance": appearance}
	save_path = path
	reset()
	load_profile()
	grant_welcome_crate()
	grant_gear_crates()
	player_name = keep.player_name
	last_server = keep.last_server
	home_server = keep.home_server
	online_secret = keep.online_secret
	melee_control = keep.melee_control
	appearance = keep.appearance
	save()


func reset() -> void:
	crates_granted.clear()
	mastery.clear()
	stash.clear()
	loadout = StashRules.new_player_loadout()
	welcome_granted = false
	fresh_start = FRESH_START
	raids_played = 0
	raids_extracted = 0
	kills = 0
	renown = 0
	scrip = Economy.STARTING_SCRIP
	arena_wins = 0
	arena_losses = 0
	base_upgrades.clear()
	blueprints.clear()


func record_arena(won: bool) -> void:
	if won:
		arena_wins += 1
	else:
		arena_losses += 1
	save()


func grant_welcome_crate() -> void:
	if welcome_granted:
		return
	welcome_granted = true
	add_to_stash(WELCOME_CRATE)


## Grants every gear crate this profile has not had yet.
func grant_gear_crates() -> void:
	for crate: String in GEAR_CRATES:
		if crate not in crates_granted:
			crates_granted.append(crate)
			add_to_stash(GEAR_CRATES[crate])


## Adds items to the stash. Starter kit items are free and never stashed,
## and a blueprint not known yet is learned instead of stored.
func add_to_stash(ids: Array) -> void:
	StashRules.add_items(stash, ids)
	Crafting.learn(stash, blueprints)
	save()


## Puts a stash item in a loadout slot. Returns false if it does not fit.
func equip(slot: String, id: String) -> bool:
	if not StashRules.can_equip(stash, slot, id):
		return false
	loadout[slot] = id
	save()
	return true


func unequip(slot: String) -> void:
	loadout.erase(slot)
	save()


func equipped(slot: String) -> String:
	return loadout.get(slot, "")


## Drops loadout entries whose item is no longer in the stash (lost in a raid).
func validate_loadout() -> void:
	StashRules.validate_loadout(stash, loadout)
	save()


## Takes the loadout out of the stash for a raid and returns the full kit:
## chosen gear and healing (see `StashRules.checkout`).
func checkout_loadout(world: WorldDef) -> Array[String]:
	var kit := StashRules.checkout(stash, loadout, world)
	save()
	return kit


## Buys one item from a hub shop into the stash. Returns {"ok"} or {"ok": false, "error"}.
func buy(shop_id: String, item_id: String) -> Dictionary:
	return _bank(Economy.buy(stash, scrip, shop_id, item_id))


## Sells up to `count` of a stash item to the shops.
func sell(item_id: String, count: int = 1) -> Dictionary:
	return _bank(Economy.sell(stash, loadout, scrip, item_id, count))


## Sells every trade good (loot that is not gear) in the stash.
func sell_loot() -> Dictionary:
	return _bank(Economy.sell_loot(stash, scrip))


## Buys a home base upgrade (an id from `BaseUpgrades`): checks what it needs
## and its price, and takes the scrip. Returns {"ok"} or {"ok": false, "error"}.
func buy_upgrade(upgrade_id: String) -> Dictionary:
	return _bank(BaseUpgrades.buy(base_upgrades, scrip, upgrade_id))


## Crafts one item (an id from `Crafting.RECIPES`) at the gunsmith bench:
## checks the blueprint, takes the parts and the fee, and adds what was made
## to the stash. Returns {"ok"} or {"ok": false, "error"}.
func craft(item_id: String) -> Dictionary:
	return _bank(Crafting.craft(stash, blueprints, scrip, item_id))


## Adds `delta` scrip (a cost when negative) for anything outside the
## shops, such as a wager. Refuses, changing nothing, if it would go below zero.
func change_scrip(delta: int) -> bool:
	if not Economy.can_change(scrip, delta):
		return false
	scrip = Economy.add(scrip, delta)
	save()
	return true


func _bank(result: Dictionary) -> Dictionary:
	scrip = result.scrip
	if result.ok:
		save()
	return result


## Saves a look. Parts from outfits that are neither starter clothing nor in
## `owned` (outfit ids) fall back to starter clothing. `owned` null means
## what the local stash unlocks; online, pass what the server's stash unlocks.
func set_appearance(p_appearance: Variant, owned: Variant = null) -> void:
	appearance = Human.player_look(p_appearance, owned_outfits() if owned == null else owned)
	save()


## The customizer outfits the clothing in the local stash unlocks.
func owned_outfits() -> Array[String]:
	return Economy.unlocked_outfits(stash)


## The secret this game signs in to servers with, created the first time.
func get_online_secret() -> String:
	if online_secret.length() < 16:
		online_secret = Crypto.new().generate_random_bytes(24).hex_encode()
		save()
	return online_secret


func record_raid(result: Dictionary) -> void:
	raids_played += 1
	if result.get("outcome", "") == "left":
		raids_extracted += 1
	kills += result.get("kills", 0)
	renown += maxi(0, int(result.get("renown", 0)))
	scrip = Economy.add(scrip, Economy.payout(result))
	var gained: Dictionary = result.get("mastery_xp", {})
	for track: String in gained:
		mastery.add_xp(track, int(gained[track]))
	validate_loadout()


func stash_value() -> int:
	return ItemDB.total_value(stash)


## Takes on the player state (`StashRules.CARRIED`) of your account on a
## server you host yourself, where you are the same player: what you did
## there is what you have at home. `snapshot` is `StashService.snapshot`.
func adopt_account(snapshot: Dictionary) -> void:
	var data := to_dict()
	for key: String in StashRules.CARRIED:
		if snapshot.has(key):
			data[key] = snapshot[key]
	load_dict(data)


func save() -> void:
	if not persist:
		return
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		push_warning("Profile: could not write %s" % save_path)
		return
	file.store_string(JSON.stringify(to_dict(), "\t"))


## Everything the save holds, as plain data.
func to_dict() -> Dictionary:
	return {
		"version": 2,
		"stash": stash,
		"loadout": loadout,
		StashRules.BARE_KEY: true,
		"welcome_granted": welcome_granted,
		"fresh_start": fresh_start,
		"crates_granted": crates_granted,
		"mastery": mastery.to_dict(),
		"melee_control": melee_control,
		"player_name": player_name,
		"last_server": last_server,
		"home_server": home_server,
		"online_secret": online_secret,
		"appearance": appearance,
		"raids_played": raids_played,
		"raids_extracted": raids_extracted,
		"kills": kills,
		"renown": renown,
		"scrip": scrip,
		"arena_wins": arena_wins,
		"arena_losses": arena_losses,
		"base_upgrades": base_upgrades,
		"blueprints": blueprints,
	}.duplicate(true)


func load_profile() -> void:
	if not persist or not FileAccess.file_exists(save_path):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if typeof(data) != TYPE_DICTIONARY:
		push_warning("Profile: save file is unreadable, starting fresh")
		return
	load_dict(data)
	if save_path == SAVE_PATH and fresh_start < FRESH_START:
		DirAccess.copy_absolute(save_path, FRESH_START_BACKUP)
		start_fresh()


## Sets this profile back to a fresh player (see `FRESH_START`), keeping who
## you are. The welcome crate follows (`grant_welcome_crate`).
func start_fresh() -> void:
	var keep := {"player_name": player_name, "last_server": last_server, "home_server": home_server,
			"online_secret": online_secret, "melee_control": melee_control, "appearance": appearance}
	reset()
	for key: String in keep:
		set(key, keep[key])
	# Clothing bought before is gone with the stash.
	appearance = Human.player_look(appearance, owned_outfits())
	fresh_start = FRESH_START
	save()


## Takes on a save's data, checked as it goes.
func load_dict(data: Dictionary) -> void:
	stash.clear()
	for id: Variant in data.get("stash", []):
		if typeof(id) == TYPE_STRING and ItemDB.has_item(id) and not ItemDB.has_tag(id, "starter"):
			stash.append(id)
	loadout.clear()
	var saved_loadout: Variant = data.get("loadout", {})
	if typeof(saved_loadout) == TYPE_DICTIONARY:
		for slot: Variant in saved_loadout:
			if typeof(slot) == TYPE_STRING and typeof(saved_loadout[slot]) == TYPE_STRING:
				loadout[slot] = saved_loadout[slot]
	StashRules.upgrade_loadout(data, loadout)
	welcome_granted = bool(data.get("welcome_granted", false))
	fresh_start = int(data.get("fresh_start", 0))
	crates_granted.clear()
	for crate: Variant in data.get("crates_granted", []):
		if typeof(crate) == TYPE_STRING:
			crates_granted.append(crate)
	mastery.load_dict(data.get("mastery", {}))
	melee_control = "mouse" if data.get("melee_control", "move") == "mouse" else "move"
	player_name = str(data.get("player_name", "Raider")).left(20)
	last_server = str(data.get("last_server", "127.0.0.1")).left(80)
	home_server = str(data.get("home_server", "")).left(80)
	online_secret = str(data.get("online_secret", "")).left(128)
	# Kept as chosen: clothing bought on a server is not in the local stash.
	# What may actually be worn is checked wherever the look is used.
	appearance = Human.sanitize(data.get("appearance"))
	raids_played = int(data.get("raids_played", 0))
	raids_extracted = int(data.get("raids_extracted", 0))
	kills = int(data.get("kills", 0))
	renown = maxi(0, int(data.get("renown", 0)))
	scrip = Economy.read_saved(data)
	arena_wins = maxi(0, int(data.get("arena_wins", 0)))
	arena_losses = maxi(0, int(data.get("arena_losses", 0)))
	base_upgrades = BaseUpgrades.clean(data.get("base_upgrades"))
	blueprints = Crafting.clean(data.get("blueprints"))
	Crafting.learn(stash, blueprints)
	validate_loadout()
