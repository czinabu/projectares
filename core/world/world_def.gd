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
##   - ExtractionZone nodes in group "exit"
##   - optionally a `bake_navigation()` method for bot pathfinding

var id := ""
var display_name := "Unnamed world"
var description := ""
## Seconds until the storm kills anyone still inside.
var raid_duration := 900.0
var bot_count := 8
var exit_hold_time := 4.0


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


func on_extract(_actor: Actor) -> void:
	pass
