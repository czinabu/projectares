class_name WorldDef
extends RefCounted
## The world contract. Every world is a folder under res://worlds/ with a
## `world.gd` that extends this class.
##
## Core code only ever talks to a world through this class, and never names a
## specific world. To add a world: copy a world folder, change the fields in
## `_init`, and override the hooks you need.
##
## Map contract: `create_map()` returns a Node3D that, once in the tree, has
##   - Marker3D nodes in group "spawn_player"
##   - Marker3D nodes in group "spawn_bot" (optional meta "faction": the
##     Raid sets it as the bot's faction before `equip_bot`, and sends new
##     bots where their faction is shortest of them)
##   - Marker3D nodes in group "spawn_cache" (optional meta "loot_source")
##   - Depot nodes in group "depot": where players bank what they carry
##   - optionally Marker3D nodes in group "spawn_vehicle" (optional meta
##     "loot_source", default "vehicle"). The Raid parks the first
##     vehicle-tagged item from `roll_loot` there, facing the marker's yaw.
##   - optionally a `bake_navigation()` method for bot pathfinding
##   - optionally a `ground_height(x, z)` method, on a map with open ground
##     that is not level (see `core/world/terrain.gd`). The Raid stands
##     players and bots on it when they spawn. Flight rig ceilings are
##     measured from it too (`FlightRig.ceiling`); a map without one has its
##     ground level at its own origin, so keep the floor there.
##   - optionally Marker3D nodes in group "strongpoint": sites to capture and
##     hold. Metas: "name" (String), "radius" (float, metres), and optionally
##     "holder" (a bot faction that holds it from the start) with
##     "holder_name" (what to call them). Put a depot near each one.
##
## Safe zones (`safe_zone = true`) are social spaces, not raids: nobody can be
## hurt, weapons and abilities are locked, nothing respawns, and players show
## up wearing their loadout without taking it out of the stash. Their map
## needs only "spawn_player" markers, and may add:
##   - Marker3D nodes in group "portal" with meta "destination" ("world:<id>",
##     "home", or anything the game's flow understands), "label" (what the
##     prompt says) and optionally "radius" (metres, default 3). A player
##     standing in one is offered the trip; see `core/social/plaza_view.gd`.
##     A portal that opens a screen (a shop) may have a child Node3D named
##     "Screen": a terminal's face, centred on it and facing its +Z, 1.6 by
##     0.9 metres. The screen is shown there (`WorldScreen`).
##
## Looks: a world may give a bot a model with `bot.set_meta("look", "<skin>")`
## in `equip_bot`. The skins are listed in `core/visual/look.gd`.

var id := ""
var display_name := "Unnamed world"
var description := ""
## How many bots the world keeps alive. A dead one is replaced after
## `bot_respawn_time` seconds, away from the players.
var bot_count := 8
## How many players a server lets into one copy of the world at once.
var max_players := 8
## A social space with no combat and nothing at stake. See "Safe zones" above.
var safe_zone := false
var bot_respawn_time := 45.0
## Seconds an emptied cache takes to fill again.
var cache_refill_time := 240.0
## Seconds before a vehicle that left its parking spot is replaced there, and
## before a vehicle nobody rides is cleared away.
var vehicle_respawn_time := 300.0
## Whether players may throw the toy vehicles on their watch here (see
## `Raid.throw_toy`). Off, a brought vehicle stays on the watch.
var vehicle_toys := true
## Whether the sky here is big and open enough for jets (items tagged
## "aircraft", DESIGN.md section 8). Off, a jet stays on the watch.
var open_skies := false
## Seconds a dead actor's bag lies around before it is cleared away.
var bag_lifetime := 300.0
## Seconds to stand in a depot to bank what you carry.
var depot_hold_time := 4.0
## Seconds a sign-out takes. Taking or dealing damage cancels it.
var sign_out_time := 10.0
## Seconds the body of a player who quit in a fight stays in the world.
var combat_log_time := 30.0
## Seconds after a hit, given or taken, that a player counts as in a fight.
var combat_time := 6.0
## Seconds a player who just dropped in cannot be hurt. Ends when they attack.
var spawn_protection := 4.0
## Death stakes. False is full loot: a dead player drops everything. True is
## a gentler world: the gear they had equipped goes back to their stash and
## only the backpack drops.
var keep_gear_on_death := false
## True when every player here is on one side (a co-op world). Strongpoints
## then belong to the players together, not to whoever took them.
var players_allied := false
## Seconds between bot pushes on a strongpoint that players hold, and how
## many bots go. 0 bots turns the pushes off.
var assault_interval := 120.0
var assault_size := 3
## Bots the world adds on top of `bot_count` as the war heats up: this many
## more at full war intensity, and a share of them below it. They arrive one
## every `reinforcement_time` seconds and are not replaced once it cools.
var war_reinforcements := 0
var reinforcement_time := 5.0
## True where the bot factions fight each other over the strongpoints: each
## keeps `garrison_size` bots on every site it holds and sends the rest
## against the nearest site it does not.
var bots_contest_sites := false
var garrison_size := 4
## How strongly fighting raises this world's war intensity (see
## `core/war/war_director.gd`). 0 keeps the world quiet whatever happens.
var war_scale := 1.0
## Power weapons (items tagged "power", see `core/war/power_armory.gd`):
## racks at strongpoints, beside supply pods and now and then beside a
## refilled cache, more often the hotter the war. A multiplier on how often
## they turn up; 0 keeps them out of this world.
var power_weapon_rate := 1.0
## World events: every so often the war throws something worth fighting over
## into the world, a supply pod or a warlord with an escort. This is the
## seconds between them while the world is quiet; an all-out war halves it.
## 0 turns events off.
var event_interval := 420.0
## Seconds an event stays before it is cleared away.
var event_lifetime := 300.0
## How many bots march with a warlord.
var warlord_escort := 2
## Artifacts (items tagged "artifact", DESIGN.md section 6). Until the PvE
## dungeons and arena tournaments that should hand them out exist, world
## events do: the chance that a warlord carries one, and that a supply pod
## holds one. 0 keeps them out of this world.
var warlord_artifact_chance := 0.5
var pod_artifact_chance := 0.1
## Blueprints and upgrade data (DESIGN.md section 10) come from the fights
## worth having: the chance that a warlord carries a blueprint and that a
## supply pod holds one, and how much upgrade data each always has. 0 keeps
## them out of this world, which is the default: only a PvP world hands
## them out.
var warlord_blueprint_chance := 0.0
var pod_blueprint_chance := 0.0
var warlord_upgrade_data := 0
var pod_upgrade_data := 0
## Seconds between dying and being allowed to drop in again.
var redeploy_delay := 3.0
## False for a venue where nobody loses gear (the arena). The server then
## hands out the loadout without taking it out of the stash, and never settles
## a result into the stash (see `StashService.deploy`).
var gear_at_risk := true


func create_map() -> Node3D:
	return null


## The node that runs this world: a plain `Raid` for every world. A venue with
## its own rules (the arena) returns its own `Raid` subclass. Called on servers,
## clients and solo alike, so the same class runs everywhere.
func new_raid() -> Raid:
	return Raid.new()


## Register items that only this world adds, with ItemDB.register. Called once
## when the registry finds the world. Ids are global, so prefix them with the
## world id to avoid clashes. Items stay usable in every world once stashed.
func register_items() -> void:
	pass


## Item ids every raider gets for free when they deploy with nothing.
func starter_loadout() -> Array[String]:
	return []


## Items for a loot source: "cache", "rooftop", "bot", or anything a map defines.
func roll_loot(_source: String, _rng: RandomNumberGenerator) -> Array[String]:
	return []


## Loot for a source while war intensity is `intensity` (0 to 1). A hotter
## war pays better: the roll is repeated and the rarest haul wins. A world
## with tables of its own for wartime can override this.
func roll_war_loot(source: String, rng: RandomNumberGenerator, intensity: float) -> Array[String]:
	var best := roll_loot(source, rng)
	for i in roundi(clampf(intensity, 0.0, 1.0) * 2.0):
		var again := roll_loot(source, rng)
		if _haul_rarity(again) > _haul_rarity(best):
			best = again
	return best


func _haul_rarity(ids: Array[String]) -> int:
	var total := 0
	for id in ids:
		total += ItemDB.item_rarity(id)
	return total


## An artifact with chance `chance`, picked evenly from every item tagged
## "artifact", or "" for none.
func roll_artifact(rng: RandomNumberGenerator, chance: float) -> String:
	if chance <= 0.0 or rng.randf() >= chance:
		return ""
	var ids: Array[String] = []
	for id: String in ItemDB.all_ids():
		if ItemDB.has_tag(id, "artifact"):
			ids.append(id)
	if ids.is_empty():
		return ""
	ids.sort()
	return ids[rng.randi() % ids.size()]


## PvP rules live here. Called for every hit before damage is applied.
## What a world event adds for crafting: a blueprint with chance `chance`,
## picked evenly from every item tagged "blueprint", and `data` upgrade data.
func roll_crafting_loot(rng: RandomNumberGenerator, chance: float, data: int) -> Array[String]:
	var out: Array[String] = []
	if chance > 0.0 and rng.randf() < chance:
		var ids: Array[String] = []
		for id: String in ItemDB.all_ids():
			if ItemDB.has_tag(id, "blueprint"):
				ids.append(id)
		if not ids.is_empty():
			ids.sort()
			out.append(ids[rng.randi() % ids.size()])
	for i in maxi(data, 0):
		out.append("upgrade_data")
	return out


func can_damage(attacker: Node, target: Node, _info: DamageInfo) -> bool:
	return attacker != target


## Set up a bot's faction, gear and stats.
func equip_bot(_bot: Actor, _rng: RandomNumberGenerator) -> void:
	pass


## Turns a freshly equipped bot into a warlord, the boss of a world event.
## Runs on clients too, so keep it free of randomness.
func make_warlord(bot: Actor) -> void:
	bot.display_name = "Warlord"
	bot.health.max_health *= 3.0
	bot.health.health = bot.health.max_health


func on_spawn(_actor: Actor) -> void:
	pass


func on_death(_actor: Actor, _info: DamageInfo) -> void:
	pass


## A player left the world alive, taking what they carried home.
func on_leave(_actor: Actor) -> void:
	pass
