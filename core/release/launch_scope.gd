class_name LaunchScope
extends RefCounted
## The first release's scope (Caleb's call, 25 November 2026, DESIGN.md
## "More worlds"): the home base, the Concourse, Ashfront and Frostline, and
## of what is built only what has a real purpose there yet. Everything else
## stays in the code for later updates, held back by this one switch.
##
## The switch is the project setting `ares/release/launch_scope`. It applies
## only to the release build (the export presets with the feature tag
## "playtest", or `--playtest` on the command line); the dev build and the
## tests never apply it, so they keep every world and everything held back.
## `Worlds.choose_offered` sets `on` at startup. Turn the setting off (or take
## a world off the list, or a feature out of `HELD`) to ship what was held.
##
## Held back while it is on:
##   - every world but `ares/release/launch_worlds` (the Spore Marsh, the
##     Dune Sea, the Basalt Rift, Meridian): `Worlds` never offers them, so no
##     gate, portal, War Room deploy, server or race feed names them
##   - the features in `HELD` (the Pit and the hub's arena door, the Racing
##     app, the player market, the trophy shelf and artifact case, the base
##     lounge and base visits): each place that offers one asks `holds`
##   - the items in `held_item` (the rover, mech and jet, their blueprints,
##     and artifacts): never sold, rolled as loot, paid by a job, crafted or
##     offered on the watch

## The switch, and the worlds it ships.
const SETTING := "ares/release/launch_scope"
const WORLDS_SETTING := "ares/release/launch_worlds"

## The features held back:
##   arena        the Pit, the hub's arena door and the promoter's bouts
##   races        the phone's Racing app (the War Room's race feed goes with
##                the race world, which is not offered)
##   market       the player market (the Exchange on Market Row)
##   trophies     the trophy shelf in the stores and the artifact case
##   lounge       the base's lounge room
##   base_visits  calling on a friend's base
const HELD: Array[String] = ["arena", "races", "market", "trophies", "lounge", "base_visits"]

## Items with one of these tags are held back: the rover, the mech, the jet
## and every artifact. A blueprint whose recipe makes one is held too.
const HELD_TAGS: Array[String] = ["rover", "walker", "aircraft", "artifact"]

const Crafting := preload("res://core/progression/crafting.gd")

## Whether the launch scope is in force in this program.
static var on := false


## Whether a build with the release tag (`as_release`) ships the launch scope.
static func applies(as_release: bool) -> bool:
	return as_release and bool(ProjectSettings.get_setting(SETTING, false))


## The worlds the launch ships (ids, the Concourse among them).
static func worlds() -> PackedStringArray:
	return ProjectSettings.get_setting(WORLDS_SETTING, PackedStringArray())


## Whether a feature (one of `HELD`) is held back right now.
static func holds(feature: String) -> bool:
	return on and feature in HELD


## Whether items with this tag (one of `HELD_TAGS`) are held back right now.
static func holds_tag(tag: String) -> bool:
	return on and tag in HELD_TAGS


## Whether an item is held back right now (see `held_item`).
static func holds_item(id: String) -> bool:
	return on and held_item(id)


## Whether an item is one the launch holds back, switch or not: tagged with
## one of `HELD_TAGS`, or a blueprint whose recipe makes such an item.
static func held_item(id: String) -> bool:
	for tag in HELD_TAGS:
		if ItemDB.has_tag(id, tag):
			return true
	if ItemDB.has_tag(id, Crafting.BLUEPRINT_TAG):
		for made: String in Crafting.RECIPES:
			if str(Crafting.RECIPES[made].get("blueprint", "")) == id and held_item(made):
				return true
	return false


## `ids` without anything held back.
static func keep(ids: Array) -> Array[String]:
	var out: Array[String] = []
	for id: Variant in ids:
		if typeof(id) == TYPE_STRING and not holds_item(id):
			out.append(id)
	return out
