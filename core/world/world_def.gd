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
## Looks: a world may give a bot a model with `bot.set_meta("look", "<skin>")`
## in `equip_bot`. The skins are listed in `core/visual/look.gd`.

var id := ""
var display_name := "Unnamed world"
var description := ""
## How many bots the world keeps alive. A dead one is replaced after
## `bot_respawn_time` seconds, away from the players.
var bot_count := 8
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
## Seconds between dying and being allowed to drop in again.
var redeploy_delay := 3.0


func create_map() -> Node3D:
	return null


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
