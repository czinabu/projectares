extends WorldDef
## The Concourse: the shared social hub. A safe zone where players meet, show
## off what they have earned, and walk through a gate to deploy. Nothing here
## can hurt anyone and nothing carried here is at risk.

const MapScript := preload("res://worlds/plaza/map.gd")


func _init() -> void:
	id = "plaza"
	display_name = "The Concourse"
	description = "The safe zone between worlds. Meet people, show off your gear, and step through a gate to deploy."
	safe_zone = true
	bot_count = 0


func create_map() -> Node3D:
	return MapScript.new()


## Arriving with an empty loadout still gives you something to stand in.
func starter_loadout() -> Array[String]:
	var worlds := Worlds.raid_worlds()
	if worlds.is_empty():
		return []
	return worlds[0].starter_loadout()


func can_damage(_attacker: Node, _target: Node, _info: DamageInfo) -> bool:
	return false
