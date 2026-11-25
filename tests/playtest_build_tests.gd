extends RefCounted
## The playtest and dev builds from one codebase (`Worlds.choose_offered`):
## the playtest build offers only the ready worlds, the dev build all of
## them, and a world left out is still known so an old save stays good.


static func run(t: Node) -> void:
	print("Playtest and dev builds")
	var every := Worlds.all().size()
	var was: Variant = ProjectSettings.get_setting("ares/release/playtest_worlds")
	# The ready list on its own: the launch scope (`launch_scope_tests.gd`)
	# replaces it when it applies.
	var launch: Variant = ProjectSettings.get_setting(LaunchScope.SETTING)
	ProjectSettings.set_setting(LaunchScope.SETTING, false)
	ProjectSettings.set_setting("ares/release/playtest_worlds", PackedStringArray(["plaza", "ashfront"]))
	Worlds.choose_offered(true)
	var ids := Worlds.all().map(func(w: WorldDef) -> String: return w.id)
	ids.sort()
	t.check(ids == ["ashfront", "plaza"], "the playtest build offers only the ready worlds (%s)" % ", ".join(ids))
	t.check(Worlds.raid_worlds().size() == 1 and Worlds.social_world() != null,
			"one warzone to deploy to, and the plaza to meet in")
	t.check(Worlds.get_world("rift") != null and not Worlds.offered("rift"),
			"a world left out is still known (old saves keep working) but never offered")
	ProjectSettings.set_setting("ares/release/playtest_worlds", was)
	ProjectSettings.set_setting(LaunchScope.SETTING, launch)
	Worlds.choose_offered(false)
	t.check(Worlds.all().size() == every and every >= 7, "the dev build offers every world (%d)" % every)
	var presets := ConfigFile.new()
	t.check(presets.load("res://export_presets.cfg") == OK, "the export presets read")
	var features := {}
	for section in presets.get_sections():
		if presets.has_section_key(section, "name"):
			features[presets.get_value(section, "name")] = str(presets.get_value(section, "custom_features", ""))
	t.check(features.get("Windows Client", "") == "playtest" and features.get("Linux Server", "") == "playtest",
			"the client testers get and the server they join are the playtest build")
	t.check(features.has("Windows Dev") and "playtest" not in str(features["Windows Dev"]),
			"the dev build is its own preset with every world")
	t.check(features.has("Linux Dev") and "playtest" not in str(features["Linux Dev"]),
			"the dev build has a Linux preset too, with every world")
	var ready: PackedStringArray = ProjectSettings.get_setting("ares/release/playtest_worlds", PackedStringArray())
	t.check(not ready.is_empty() and ready.has("plaza") and Array(ready).all(func(id: String) -> bool: return Worlds.get_world(id) != null),
			"the ready list names real worlds and keeps the plaza (%s)" % ", ".join(ready))
