extends Node
## The new-world starter: one command makes a world that plugs in and
## passes its tests, from the templates beside this file.
##
##   godot --headless --path . res://tools/new_world/new_world.tscn -- --id ember --name "Ember Reach" [--planet basalt]
##
## It writes
##   worlds/<id>/world.gd       the `WorldDef`: planet, rules, an enemy
##                              roster as data, loot tables, zones, contracts
##   worlds/<id>/map.gd         a map on a `Terrain` with every marker the
##                              contract asks for (spawns, depots, caches,
##                              an outpost, strongpoints, a boss, vehicles)
##   tests/<id>_tests.gd        its checks (the runner finds them by itself)
##   tests/visual/<id>.gd       `visual_check.tscn -- <dir> --<id>-only`
##   docs/systems/<id>.md       its rules file
## and adds the rules file's line to CLAUDE.md's index. The registry finds
## the folder by itself, so the world is in the portal and the plaza at
## once. It never overwrites: a world or file that exists stops it. Then it
## prints what is left to do by hand. `--root <dir>` writes somewhere else
## (the tests use it); `--dry` only lists what it would write.

const TEMPLATES := "res://tools/new_world/templates"
## Template, then where it goes (`{id}` is the world's id).
const FILES := [
	["world.gd.tmpl", "worlds/{id}/world.gd"],
	["map.gd.tmpl", "worlds/{id}/map.gd"],
	["tests.gd.tmpl", "tests/{id}_tests.gd"],
	["visual.gd.tmpl", "tests/visual/{id}.gd"],
	["system.md.tmpl", "docs/systems/{id}.md"],
]
const INDEX_FILE := "CLAUDE.md"
const INDEX_AFTER := "- `docs/systems/"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var result := make(_arg(args, "--id"), _arg(args, "--name"), _arg(args, "--planet", "ashland"),
			_arg(args, "--root", "res://"), "--dry" in args)
	for line: String in result.lines:
		print(line)
	get_tree().quit(0 if result.ok else 1)


## Makes the world. Returns {ok, lines (what to print), files (written)}.
static func make(id: String, display_name: String, planet: String, root: String, dry := false) -> Dictionary:
	var problem := check(id, display_name, planet, root)
	if problem != "":
		return {"ok": false, "lines": ["new_world: " + problem, _usage()], "files": []}
	var values := {"__ID__": id, "__NAME__": display_name, "__PLANET__": planet, "__SEED__": str(absi(hash(id)) % 9000 + 1000)}
	var written: Array[String] = []
	var lines: Array[String] = []
	for entry: Array in FILES:
		var target := root.path_join(str(entry[1]).replace("{id}", id))
		var text := fill(FileAccess.get_file_as_string(TEMPLATES.path_join(entry[0])), values)
		if dry:
			lines.append("would write " + target)
			continue
		DirAccess.make_dir_recursive_absolute(target.get_base_dir())
		var file := FileAccess.open(target, FileAccess.WRITE)
		if file == null:
			return {"ok": false, "lines": lines + ["new_world: could not write " + target], "files": written}
		file.store_string(text)
		file.close()
		written.append(target)
		lines.append("wrote " + target)
	var index := root.path_join(INDEX_FILE)
	if not dry and FileAccess.file_exists(index):
		var claude := FileAccess.get_file_as_string(index)
		var added := add_index_line(claude, id, display_name)
		if added != claude:
			var file := FileAccess.open(index, FileAccess.WRITE)
			file.store_string(added)
			file.close()
			lines.append("added docs/systems/%s.md to %s's index" % [id, INDEX_FILE])
	lines.append_array([
		"",
		"%s is in. Next:" % display_name,
		"  godot --headless --path . --import",
		"  godot --headless --path . res://tests/test_runner.tscn -- --only %s" % id,
		"  godot --path . res://tests/visual_check.tscn -- <dir> --%s-only" % id,
		"By hand: its DESIGN.md section and a docs/design-gaps.md row; the roster, loot",
		"and rules in worlds/%s/world.gd; the places in worlds/%s/map.gd; new item ids" % [id, id],
		"prefixed '%s_' in register_items; new art through Look's kits." % id,
	])
	return {"ok": true, "lines": lines, "files": written}


## Why the world cannot be made, or "".
static func check(id: String, display_name: String, planet: String, root: String) -> String:
	var shape := RegEx.create_from_string("^[a-z][a-z0-9_]{1,23}$")
	if id == "" or shape.search(id) == null:
		return "--id must be lower case letters, digits and _, starting with a letter (got '%s')" % id
	if display_name.strip_edges() == "" or display_name.contains("\"") or display_name.contains("\\"):
		return "--name is the world's name as players see it, with no quotes"
	if PlanetTypes.get_type(planet) == null:
		return "--planet must be one of %s (got '%s')" % [", ".join(PlanetTypes.ids()), planet]
	if root == "res://" and Worlds.get_world(id) != null:
		return "a world with id '%s' already exists" % id
	for entry: Array in FILES:
		var target := root.path_join(str(entry[1]).replace("{id}", id))
		if FileAccess.file_exists(target):
			return "%s already exists; nothing was written" % target
	return ""


## The template with every placeholder replaced.
static func fill(text: String, values: Dictionary) -> String:
	for key: String in values:
		text = text.replace(key, values[key])
	return text


## CLAUDE.md with the world's rules file added after the last line of the
## system index (unchanged if it is there or there is no index).
static func add_index_line(claude: String, id: String, display_name: String) -> String:
	var line := "- `docs/systems/%s.md`: %s's rules (made by `tools/new_world`)." % [id, display_name]
	if claude.contains("`docs/systems/%s.md`" % id):
		return claude
	var lines := claude.split("\n")
	var last := -1
	for i in lines.size():
		if lines[i].begins_with(INDEX_AFTER):
			last = i
	if last < 0:
		return claude
	lines.insert(last + 1, line)
	return "\n".join(lines)


static func _usage() -> String:
	return "usage: godot --headless --path . res://tools/new_world/new_world.tscn -- --id <id> --name \"<Name>\" [--planet <type>] [--dry]"


static func _arg(args: PackedStringArray, key: String, fallback := "") -> String:
	var at := args.find(key)
	return args[at + 1] if at >= 0 and at + 1 < args.size() else fallback
