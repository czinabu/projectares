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
##   - Marker3D nodes in group "spawn_bot"
##   - Marker3D nodes in group "spawn_cache" (optional meta "loot_source")
##   - Depot nodes in group "depot": where players bank what they carry
##   - optionally Marker3D nodes in group "spawn_vehicle" (optional meta
##     "loot_source", default "vehicle"). The Raid parks the first
##     vehicle-tagged item from `roll_loot` there, facing the marker's yaw.
##   - optionally a `bake_navigation()` method for bot pathfinding
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
## A social space with no combat and nothing at stake. See "Safe zones" above.
var safe_zone := false
var bot_respawn_time := 45.0
## Seconds an emptied cache takes to fill again.
var cache_refill_time := 240.0
## Seconds before a vehicle that left its parking spot is replaced there, and
## before a vehicle nobody rides is cleared away.
var vehicle_respawn_time := 300.0
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
## How strongly fighting raises this world's war intensity (see
## `core/war/war_director.gd`). 0 keeps the world quiet whatever happens.
var war_scale := 1.0
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


## PvP rules live here. Called for every hit before damage is applied.
func can_damage(attacker: Node, target: Node, _info: DamageInfo) -> bool:
	return attacker != target


## Set up a bot's faction, gear and stats.
func equip_bot(_bot: Actor, _rng: RandomNumberGenerator) -> void:
	pass


func on_spawn(_actor: Actor) -> void:
	pass


func on_death(_actor: Actor, _info: DamageInfo) -> void:
	pass


## A player left the world alive, taking what they carried home.
func on_leave(_actor: Actor) -> void:
	pass
