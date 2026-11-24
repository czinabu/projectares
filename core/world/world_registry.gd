extends Node
## Autoload `Worlds`: finds every world under res://worlds/ at startup.
## Dropping in a new folder with a `world.gd` is all it takes to add a world.

const WORLDS_DIR := "res://worlds"

## The world of the raid in progress, or null in the hub.
var current: WorldDef = null
var _worlds := {}
## The playtest build (an export with the feature tag "playtest", or a run
## with `--playtest`) offers only the worlds listed in the project setting
## `ares/release/playtest_worlds`; the dev build (no tag) offers every one.
## A world left out is still loaded and its items still known, so a save
## holding them stays good; it is only never listed, offered or travelled to
## (`all`, `raid_worlds`, `social_world`).
var playtest := false
var _offered := {}


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
	choose_offered(is_playtest())


## Picks the worlds offered: every one, or for the playtest build only the
## ready list (`ares/release/playtest_worlds`).
func choose_offered(as_playtest: bool) -> void:
	playtest = as_playtest
	_offered.clear()
	var ready: PackedStringArray = ProjectSettings.get_setting("ares/release/playtest_worlds", PackedStringArray())
	for id: String in _worlds:
		if not as_playtest or id in ready:
			_offered[id] = true


## Whether this program is the playtest build: the export's feature tag, or
## `--playtest` on the command line to try it from the editor.
static func is_playtest() -> bool:
	return OS.has_feature("playtest") or "--playtest" in OS.get_cmdline_user_args()


## Whether a world is offered in this build (see `playtest`).
func offered(id: String) -> bool:
	return _offered.has(id)


func all() -> Array[WorldDef]:
	var out: Array[WorldDef] = []
	for id: String in _worlds:
		if _offered.has(id):
			out.append(_worlds[id])
	return out


## Worlds you deploy into and fight in: everything except safe zones.
func raid_worlds() -> Array[WorldDef]:
	return all().filter(func(world: WorldDef) -> bool: return not world.safe_zone)


## The social hub: the first safe zone found, or null if there is none.
func social_world() -> WorldDef:
	for world in all():
		if world.safe_zone:
			return world
	return null


## The world a node is in: the world of the raid that contains it. Several
## raids can run in one process (a server with a plaza and a warzone), so
## rules are looked up from the node, with `current` only as a fallback.
func of(node: Node) -> WorldDef:
	var raid := Raid.of(node)
	return raid.world if raid != null and raid.world != null else current


func get_world(id: String) -> WorldDef:
	return _worlds.get(id)
