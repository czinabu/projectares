extends Node
## Autoload `Worlds`: finds every world under res://worlds/ at startup.
## Dropping in a new folder with a `world.gd` is all it takes to add a world.

const WORLDS_DIR := "res://worlds"

## The world of the raid in progress, or null in the hub.
var current: WorldDef = null
var _worlds := {}


func _ready() -> void:
	scan()


func scan() -> void:
	_worlds.clear()
	var dir := DirAccess.open(WORLDS_DIR)
	if dir == null:
		push_error("Worlds: cannot open %s" % WORLDS_DIR)
		return
	for folder in dir.get_directories():
		var path := "%s/%s/world.gd" % [WORLDS_DIR, folder]
		if not ResourceLoader.exists(path):
			continue
		var script: GDScript = load(path)
		var world := script.new() as WorldDef
		if world == null or world.id == "":
			push_warning("Worlds: %s is not a valid WorldDef" % path)
			continue
		world.register_items()
		_worlds[world.id] = world


func all() -> Array[WorldDef]:
	var out: Array[WorldDef] = []
	for id: String in _worlds:
		out.append(_worlds[id])
	return out


func get_world(id: String) -> WorldDef:
	return _worlds.get(id)
