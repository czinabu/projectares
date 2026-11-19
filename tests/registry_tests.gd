extends RefCounted
## The `registry` checks. The test runner finds this file by itself and calls
## `run(t)`.


static func run(t: Node) -> void:
	var declared: Array[String] = Boot.declared_classes("res://")
	t.check("Actor" in declared and "Ability" in declared and "MeleeWeapon" in declared,
			"the boot check finds the project's script classes")
	t.check(Boot.find_missing_classes().is_empty(), "every script class is registered with Godot")
	print("World registry")
	var world := Worlds.get_world("ashfront")
	t.check(world != null, "ashfront is discovered from its folder")
	t.check(Worlds.all().size() >= 1, "registry lists worlds")
	t.check(world != null and world.starter_loadout().size() > 0, "world provides a starter loadout")
