extends RefCounted
## The first release's scope (`LaunchScope`, DESIGN.md "More worlds"): with
## the switch on, the release build offers only the home base, the
## Concourse, Ashfront and Frostline, and holds back the Pit, the Racing app,
## the player market, the trophy shelf and artifact case, the base lounge,
## base visits, the rover, mech and jet and artifacts; the dev build (the
## switch never applies there) keeps everything.

const Crafting := preload("res://core/progression/crafting.gd")
const Contracts := preload("res://core/economy/contracts.gd")
const Economy := preload("res://core/economy/economy.gd")
const BaseLayout := preload("res://core/base/base_layout.gd")
const BasePlan := preload("res://core/base/base_plan.gd")
const BaseUpgrades := preload("res://core/base/base_upgrades.gd")
const StashRules := preload("res://core/account/stash_rules.gd")

const HELD_ITEMS: Array[String] = ["rover_warden", "mech_bulwark", "jet_kestrel", "bp_mech_bulwark", "bp_jet_kestrel",
		"artifact_rewind", "artifact_cloak", "stalker_fang", "blade_hook", "bp_blade_hook", "bp_spear_reed"]
const KEPT_ITEMS: Array[String] = ["bike_scrapper", "bike_raider", "bp_jetpack", "jetpack_mk1", "bp_frame_thermal",
		"bp_grip_glacier", "frame_thermal"]


static func run(t: Node) -> void:
	print("Launch scope")
	t.check(bool(ProjectSettings.get_setting(LaunchScope.SETTING, false)),
			"the release build ships the launch scope (%s)" % LaunchScope.SETTING)
	t.check(not LaunchScope.on and not LaunchScope.applies(false),
			"the dev build and the tests never apply it")
	t.check(Worlds.get_world("ashfront").max_players == 24 and Worlds.get_world("frostline").max_players == 8,
			"Ashfront takes 24 players, Frostline 8")
	Worlds.choose_offered(true)
	await _held(t)
	Worlds.choose_offered(false)
	_restored(t)


static func _held(t: Node) -> void:
	t.check(LaunchScope.on, "the release build turns it on")
	var ids := Worlds.all().map(func(w: WorldDef) -> String: return w.id)
	ids.sort()
	t.check(ids == ["ashfront", "frostline", "plaza"], "it offers the Concourse, Ashfront and Frostline (%s)" % ", ".join(ids))
	t.check(["marsh", "dunes", "rift", "meridian"].all(func(id: String) -> bool:
		return Worlds.get_world(id) != null and not Worlds.offered(id)),
			"the held worlds are still known (old saves stay good) but never offered")
	var places := Portal.destinations()
	t.check(places == ["ashfront", "frostline"] or places == ["frostline", "ashfront"],
			"portals and the base's door lead only to the launch worlds, not the Pit (%s)" % ", ".join(places))
	t.check(not WarRoom.segments({"meridian": {}}).any(func(s: String) -> bool: return s.begins_with("race:")),
			"the War Room shows no race feed")

	# Items: never sold, rolled, paid or crafted.
	t.check(HELD_ITEMS.all(func(id: String) -> bool: return LaunchScope.holds_item(id))
			and not KEPT_ITEMS.any(func(id: String) -> bool: return LaunchScope.holds_item(id)),
			"the rover, mech, jet, artifacts, the Marsh's parts and blades and their blueprints are held; the bikes and Frostline's blueprints are not")
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var table := [{"id": "rover_warden", "weight": 1000.0}, {"id": "bike_scrapper", "weight": 1.0}]
	var rolled := {}
	for i in 200:
		rolled[ItemDB.roll(table, rng)] = true
	t.check(rolled.keys() == ["bike_scrapper"], "a loot table never rolls a held item (%s)" % ", ".join(rolled.keys()))
	var world := Worlds.get_world("ashfront")
	var crafted := {}
	var relics := 0
	for i in 300:
		for id in world.roll_crafting_loot(rng, 1.0, 0):
			crafted[id] = true
		if world.roll_artifact(rng, 1.0) != "":
			relics += 1
	t.check(relics == 0, "no world event hands out an artifact")
	t.check(not crafted.is_empty() and not crafted.keys().any(func(id: String) -> bool: return LaunchScope.holds_item(id)),
			"no world event hands out a held blueprint (%s)" % ", ".join(crafted.keys()))
	var frost := Worlds.get_world("frostline")
	var vault_relic := false
	for i in 200:
		vault_relic = vault_relic or frost.roll_vault("heart", rng).any(func(id: String) -> bool:
			return ItemDB.has_tag(id, "artifact"))
	t.check(not vault_relic, "the Heart's vault pays no artifact")
	var sold: Array[String] = []
	for shop: String in ["armory", "outfitter", "garage", Economy.BLACK_MARKET]:
		sold.append_array(Economy.stock(shop))
	t.check(not sold.any(func(id: String) -> bool: return LaunchScope.holds_item(id)) and "bike_scrapper" in sold,
			"no shop sells a held item, and the garage still sells the bike")
	var paid := {}
	for i in 200:
		paid[Contracts.reward_for("blueprint", i)] = true
	t.check(not paid.keys().any(func(id: String) -> bool: return LaunchScope.holds_item(id)),
			"no job pays a held blueprint, the Marsh blades' included")
	t.check("mech_bulwark" not in Crafting.ids() and "jet_kestrel" not in Crafting.ids() and "jetpack_mk2" in Crafting.ids(),
			"the fabricator offers no mech or jet")
	t.check(Crafting.blocked(["reactor_core", "alloy_ingot", "alloy_ingot", "alloy_ingot", "power_cell", "power_cell"],
			["bp_mech_bulwark"], 99999, "mech_bulwark") != "", "and will not make one even with its blueprint known")

	# The watch: no artifact icon.
	t.check("artifact" not in Hud.Wrist.row("summon") and Hud.Wrist.tab_of("artifact") == ""
			and "artifact" not in Hud.Wrist.tab_line("summon"), "the watch has no artifact icon")

	# The base: no trophy shelf, artifact case or lounge.
	var full := BaseUpgrades.full()
	t.check(BaseLayout.spots("trophy", full) == 0 and BaseLayout.spots("artifact_case", full) == 0
			and BaseLayout.spots("supplies", full) > 0, "the base has no trophy shelf or artifact case")
	t.check("lounge" not in BasePlan.rooms() and not BaseUpgrades.is_ready("lounge")
			and not BaseUpgrades.is_ready("style_lounge_bar") and "trophy" not in BaseUpgrades.adds("trophy_hall").to_lower(),
			"the lounge and its upgrades are not on offer")
	var base := HomeBase.new()
	base.show_gear(["rifle_scrap", "rover_warden", "bike_scrapper", "artifact_rewind"], StashRules.starter_loadout(), full)
	t.add_child(base)
	await t.frames(5)
	var lounge := base.get_node_or_null("Room_%s" % BasePlan.socket_of(base.base_plan, "lounge"))
	t.check(lounge != null and lounge.get_node_or_null("SealedDoor") != null and lounge.get_child_count() == 1,
			"the lounge's doorway is sealed, with no room behind it")
	t.check(base.watch_vehicles() == ["bike_scrapper"], "the watch offers the bike, never the rover")
	t.check(not base.displays.any(func(d: HomeBase.Display) -> bool: return d.item_id == "artifact_rewind"),
			"an artifact is not on show")
	base.queue_free()

	# The Concourse: gates for the launch worlds, the arena door and the
	# Exchange shuttered.
	var raid := Raid.new()
	t.add_child(raid)
	raid.mode = Raid.Mode.SERVER
	raid.start_server(Worlds.social_world(), 5)
	await t.frames(2)
	var destinations := raid.map.get_children().filter(func(n: Node) -> bool: return n.is_in_group("portal")) \
			.map(func(n: Node) -> String: return n.get_meta("destination", ""))
	t.check("world:ashfront" in destinations and "world:frostline" in destinations
			and not destinations.any(func(d: String) -> bool: return d in ["world:marsh", "world:dunes", "world:rift", "world:meridian"]),
			"the gate terrace opens on Ashfront and Frostline only")
	t.check("arena" not in destinations and "market" not in destinations,
			"the arena door and the Exchange are shuttered")
	raid.queue_free()
	await t.frames(2)


static func _restored(t: Node) -> void:
	t.check(not LaunchScope.on and Worlds.all().size() >= 7 and "arena" in Portal.destinations(),
			"the dev build offers every world and the Pit again")
	t.check(not HELD_ITEMS.any(func(id: String) -> bool: return LaunchScope.holds_item(id))
			and "mech_bulwark" in Crafting.ids() and "lounge" in BasePlan.rooms()
			and BaseLayout.spots("trophy", BaseUpgrades.full()) > 0 and "artifact" in Hud.Wrist.row("summon"),
			"and everything held back")
