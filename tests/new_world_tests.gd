extends RefCounted
## The new-world starter (`tools/new_world`): it refuses bad input and never
## overwrites, and what it writes is a world that plugs in, runs a raid
## headless and keeps the map contract. It writes under `user://`, never
## into the project.

const NewWorld := preload("res://tools/new_world/new_world.gd")
const ROOT := "user://test_new_world"


static func run(t: Node) -> void:
	print("New-world starter: a world from one command")
	_clear(ROOT)
	t.check(NewWorld.check("Bad Id", "X", "ashland", ROOT) != "" and NewWorld.check("ok_id", "", "ashland", ROOT) != ""
			and NewWorld.check("ok_id", "X", "no_such_planet", ROOT) != "" and NewWorld.check("ashfront", "X", "ashland", "res://") != "",
			"it refuses a bad id, an empty name, an unknown planet and a world that exists")
	DirAccess.make_dir_recursive_absolute(ROOT)
	var index := FileAccess.open(ROOT.path_join("CLAUDE.md"), FileAccess.WRITE)
	index.store_string("## Systems\n\n- `docs/systems/one.md`: One.\n- `docs/systems/two.md`: Two.\n\n## Conventions\n")
	index.close()
	var dry: Dictionary = NewWorld.make("scaffold_probe", "Scaffold Probe", "dunes", ROOT, true)
	t.check(dry.ok and dry.files.is_empty() and not DirAccess.dir_exists_absolute(ROOT.path_join("worlds")),
			"--dry only lists what it would write")
	var made: Dictionary = NewWorld.make("scaffold_probe", "Scaffold Probe", "dunes", ROOT)
	t.check(made.ok and made.files.size() == NewWorld.FILES.size(), "it writes every file (%s)" % ", ".join(made.files))
	var claude := FileAccess.get_file_as_string(ROOT.path_join("CLAUDE.md"))
	t.check(claude.contains("- `docs/systems/two.md`: Two.\n- `docs/systems/scaffold_probe.md`")
			and claude.ends_with("## Conventions\n"), "it adds the rules file to the index, after the last entry")
	t.check(not NewWorld.make("scaffold_probe", "Again", "dunes", ROOT).ok, "it never overwrites a world")
	var all_filled := true
	for path: String in made.files:
		all_filled = all_filled and not FileAccess.get_file_as_string(path).contains("__")
	t.check(all_filled, "every placeholder is filled")
	var script: GDScript = load(ROOT.path_join("worlds/scaffold_probe/world.gd"))
	var world := script.new() as WorldDef if script != null else null
	t.check(world != null and world.id == "scaffold_probe" and world.planet == "dunes"
			and world.display_name == "Scaffold Probe", "the world script compiles and names itself")
	if world == null:
		return
	world.register_items()
	var raid := world.new_raid()
	t.add_child(raid)
	raid.start(world, 3)
	await t.frames(3)
	t.check(raid.player != null and not raid.player.is_dead and not raid.depots.is_empty()
			and raid.strongpoints.size() == 3 and raid.bots.size() >= world.bot_count
			and raid.bots.all(func(b: Actor) -> bool: return b.weapons.size() > 0),
			"its raid runs: you land, depots and strongpoints stand, the roster spawns armed")
	await t.frames(60)
	t.check(raid.clock > 0.5 and not raid.player.is_dead, "the world keeps running")
	await t._end_raid(raid)
	var tests: GDScript = load(ROOT.path_join("tests/scaffold_probe_tests.gd"))
	var visual: GDScript = load(ROOT.path_join("tests/visual/scaffold_probe.gd"))
	t.check(tests != null and tests.can_instantiate() and visual != null and visual.can_instantiate(),
			"its test and visual check files compile")
	_clear(ROOT)


static func _clear(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for name in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(name))
	for name in DirAccess.get_directories_at(dir):
		_clear(dir.path_join(name))
	DirAccess.remove_absolute(dir)
