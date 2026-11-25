extends RefCounted
## The `home_base` checks. The test runner finds this file by itself and calls
## `run(t)`.

const StashRules := preload("res://core/account/stash_rules.gd")
const VehicleScript := preload("res://core/vehicle/vehicle.gd")
const BaseLayout := preload("res://core/base/base_layout.gd")
const BaseUpgrades := preload("res://core/base/base_upgrades.gd")
const BaseHudScript := preload("res://core/ui/base_hud.gd")


static func run(t: Node) -> void:
	print("Home base layout")
	t.check(BaseLayout.kind_for("dmr_longshot") == "rack_guns" and BaseLayout.kind_for("hammer_breaker") == "rack_melee"
			and BaseLayout.kind_for("pistol_machine") == "rack_sidearms" and BaseLayout.kind_for("power_rail_lance") == "heavy_wall"
			and BaseLayout.kind_for("frame_bulwark") == "armor_stand" and BaseLayout.kind_for("wings_glide") == "rig_stand"
			and BaseLayout.kind_for("chip_blink") == "chip_case" and BaseLayout.kind_for("bike_raider") == "bay"
			and BaseLayout.kind_for("medkit") == "supplies" and BaseLayout.kind_for("lattice_shard") == "trophy",
			"tags decide where an item is shown")
	t.check(BaseLayout.slot_for("rifle_carbine") == "primary" and BaseLayout.slot_for("bike_scrapper") == "vehicle"
			and BaseLayout.slot_for("scrap_metal") == "", "gear knows its loadout slot, loot has none")
	var stash: Array[String] = ["rifle_carbine", "dmr_longshot", "rifle_carbine", "blade_arc", "frame_trooper",
			"bike_scrapper", "bike_scrapper", "bike_raider", "medkit", "medkit", "medkit", "scrap_metal",
			"lattice_shard", "chip_blink", "jetpack_mk2", "no_such_item"]
	# The finished base: `_test_base_upgrades` covers the starter bunker.
	var full := BaseUpgrades.full()
	var plan := BaseLayout.plan(stash, {"primary": "rifle_carbine", "vehicle": "bike_scrapper"}, full)
	var by_kind := {}
	for entry in plan:
		if not by_kind.has(entry["kind"]):
			by_kind[entry["kind"]] = []
		by_kind[entry["kind"]].append(entry)
	var guns: Array = by_kind.get("rack_guns", [])
	t.check(guns.size() == 2 and guns[0]["id"] == "dmr_longshot" and guns[0]["index"] == 0
			and guns[1]["id"] == "rifle_carbine", "the most valuable gun gets the first spot")
	t.check(guns[1]["count"] == 2 and guns[1]["equipped"] and not guns[0]["equipped"],
			"copies share a spot with a count, and the equipped gun is marked")
	var bays: Array = by_kind.get("bay", [])
	t.check(bays.size() == 3 and bays[0]["id"] == "bike_raider", "every bike you own is parked")
	t.check(bays.filter(func(e: Dictionary) -> bool: return e["equipped"]).size() == 1,
			"only one of two identical bikes is marked as equipped")
	t.check(by_kind.get("trophy", []).size() == 2 and by_kind["trophy"][0]["id"] == "lattice_shard"
			and by_kind.get("supplies", []).size() == 1 and by_kind["supplies"][0]["count"] == 3,
			"loot goes on the trophy shelf and medkits with the supplies")
	t.check(plan.filter(func(e: Dictionary) -> bool: return e["id"] == "no_such_item").is_empty(),
			"unknown items are never shown")
	t.check(BaseLayout.plan([], {}, full).is_empty() and BaseLayout.stored_away(stash, full).is_empty(),
			"an empty stash is an empty base, and nothing is stored away while it fits")
	var many: Array[String] = []
	for i in 6:
		many.append("bike_scrapper")
	t.check(BaseLayout.plan(many, {}, full).size() == 4 and BaseLayout.stored_away(many, full) == {"bay": 2},
			"a full garage keeps the rest in storage")

	print("Home base room")
	var base := HomeBase.new()
	base.show_gear(stash, {"primary": "rifle_carbine"}, full)
	t.add_child(base)
	await t.frames(30)
	t.check(base.displays.size() == BaseLayout.plan(StashRules.equippable(stash), {"primary": "rifle_carbine"}, full).size(),
			"the room builds one display per planned spot, the free scrap pieces included")
	t.check(base.player != null and base.player.is_on_floor() and base.suited
			and base.player.weapons.any(func(w: Weapon) -> bool: return w.item_id == "rifle_carbine"),
			"you stand in your base already wearing your loadout")
	var start := base.player.global_position
	base.player.cmd.move = Vector2(0, 1)
	await t.frames(30)
	base.player.cmd.move = Vector2.ZERO
	t.check(base.player.global_position.distance_to(start) > 1.5, "you can walk around it")
	var spots := {}
	var apart := true
	for display in base.displays:
		var key := "%s/%d" % [display.kind, display.index]
		apart = apart and not spots.has(key) and base.inside(display.position)
		spots[key] = true
	t.check(apart, "every display has its own spot inside the room")
	await t._test_armory(base)
	var asked := []
	base.equip_requested.connect(func(slot: String, id: String) -> void: asked.append([slot, id]))
	var dmr := base.display_for("dmr_longshot")
	t._face_display(base.player, dmr)
	await t.frames(2)
	# Aim again from where the feet settled: the eye height decides which row
	# of the rack the look lands on.
	t._face_display(base.player, dmr)
	t.check(base.player.find_interactable() == dmr and dmr.get_prompt() == "[F] Equip Longshot DMR",
			"looking at a gun on the rack offers to equip it")
	await t._use(base.player)
	t.check(asked == [["primary", "dmr_longshot"]], "using it asks for that gun in the primary slot")
	var carbine := base.display_for("rifle_carbine")
	t.check(carbine.equipped and carbine.has_node("EquippedMark") and not dmr.has_node("EquippedMark"),
			"equipped gear is marked on its display")
	t._face_display(base.player, carbine)
	await t.frames(2)
	await t._use(base.player)
	t.check(asked.size() == 2 and asked[1] == ["primary", ""], "using equipped gear asks to take it off")
	var shard := base.display_for("lattice_shard")
	t._face_display(base.player, shard)
	await t.frames(2)
	await t._use(base.player)
	t.check(base.player.find_interactable() == shard and shard.get_prompt() == "Lattice Shard" and asked.size() == 2,
			"loot is only for looking at")
	var hud = BaseHudScript.new()
	hud.setup(base)
	base.add_child(hud)
	await t.frames(2)
	var lines: Array[String] = hud.describe(shard)
	t.check(lines[0] == "Lattice Shard" and "Relic" in lines[1], "the overlay names what you look at and its rarity")
	t.check(hud.tag.visible and hud.tag.text == lines[1] and hud.tag.global_position.distance_to(shard.global_position) < 2.0,
			"what it is shows on a tag over the gear itself, not on the screen")
	# Riding, F gets you off, so the vehicle under you is not offered
	# (playtest: "Warden Rover (ridden)" stayed on the screen in the base).
	var stood_at := base.player.global_position
	var ride = VehicleScript.new()
	ride.setup("rover_warden")
	ride.local_only = true
	base.add_child(ride)
	ride.global_position = stood_at + Vector3(0, 0.3, 0)
	await t.frames(2)
	t.check(ride.mount(base.player), "you can climb on a vehicle in the base")
	var aim_was := base.player.cmd.aim_dir
	base.player.cmd.aim_dir = Vector3(0.0, -1.0, -0.2)
	await t.frames(3)
	t.check(base.player.find_interactable() != null and hud.get("_prompt").text == "",
			"riding in the base, the vehicle under you is not offered on the screen")
	base.player.cmd.aim_dir = aim_was
	ride.dismount()
	ride.queue_free()
	base.player.global_position = stood_at
	await t.frames(2)
	# The watch works at home as in a raid (playtest: X half-raised the arm
	# with no card): it rises with the key and its card has every icon.
	t.check(hud.wrist != null and not hud.wrist.raised, "the base wears the watch, lowered")
	var watch_keys := PlayerController.new()
	watch_keys.setup(base.player)
	base.add_child(watch_keys)
	watch_keys.wrist_raised = true
	await t.frames(30)
	var watch_icons: Array = hud.wrist.card.slots.map(func(slot: Dictionary) -> String: return slot.id)
	t.check(hud.wrist.raised and hud.wrist.raise_amount >= 1.0 and watch_icons == Hud.Wrist.SLOTS
			and base.player.cmd.watch_up, "X raises the watch in the base and its card opens: %s" % ", ".join(watch_icons))
	var home := Hud.base_watch_slots("Home base", {"vehicle": "bike_raider"})
	var home_vehicle: Dictionary = home[Hud.Wrist.SLOTS.find("vehicle")]
	t.check(home[Hud.Wrist.SLOTS.find("map")].detail == "Home base" and home_vehicle.detail == ItemDB.item_name("bike_raider")
			and not home_vehicle.empty and Hud.base_watch_slots("Home base", {})[Hud.Wrist.SLOTS.find("vehicle")].empty,
			"at home the card says where you are and which vehicle you deploy with")
	watch_keys.wrist_raised = false
	await t.frames(30)
	t.check(hud.wrist.raise_amount <= 0.0 and not base.player.cmd.watch_up, "X lowers it again")
	# The raised wrist comes up into the line of sight from the eyes, so the
	# card over it is in view (playtest: it stayed under the view in first
	# person), wherever you are looking.
	var arm = preload("res://core/visual/weapon_arm.gd").new()
	arm.actor = base.player
	var in_view := true
	for look_pitch: float in [-0.4, 0.0, 0.4]:
		base.player.cmd.pitch = look_pitch
		var aim_dir: Vector3 = base.player.global_basis * Basis(Vector3.RIGHT, look_pitch) * Vector3.FORWARD
		var to_wrist: Vector3 = arm.watch_point() - base.player.get_eye_position()
		in_view = in_view and rad_to_deg(aim_dir.angle_to(to_wrist)) < 30.0 and to_wrist.length() < 0.6
	base.player.cmd.pitch = 0.0
	arm.free()
	t.check(in_view, "the raised watch comes up in front of the eyes, wherever you look")
	# A change of gear dresses the same body, and the watch on it keeps
	# working (playtest: X did nothing after suiting up).
	watch_keys.queue_free()
	await t.frames(2)
	var regeared := base.loadout.duplicate()
	regeared["primary"] = "dmr_longshot" if base.loadout.get("primary", "") != "dmr_longshot" else "rifle_carbine"
	base.show_gear(base.stash + [regeared.primary], regeared)
	await t.frames(3)
	var suited_keys := PlayerController.new()
	suited_keys.setup(base.player)
	base.add_child(suited_keys)
	suited_keys.wrist_raised = true
	await t.frames(30)
	t.check(is_instance_valid(hud.wrist) and hud.wrist.get_parent() == base.player and hud.wrist.raise_amount >= 1.0
			and hud.wrist.card.slots.size() == Hud.Wrist.SLOTS.size(), "the watch still raises after suiting up")
	suited_keys.queue_free()
	await t.frames(2)
	t.check(not base.has_node("Banner"), "no banner hangs in the room: the plates and consoles say what they are")
	for kind: String in BaseLayout.KINDS:
		var bike_or_gear: Array = by_kind.get(kind, [])
		if bike_or_gear.is_empty():
			continue
		var shown := base.display_for(bike_or_gear[0]["id"])
		t._face_display(base.player, shown)
		await t.frames(2)
		t.check(base.player.find_interactable() == shown, "a %s display can be walked up to and looked at" % kind)
	base.show_gear(["blade_arc"], {})
	await t.frames(2)
	t.check(base.displays.size() == 1 + StashRules.free_items().size() and base.display_for("dmr_longshot") == null,
			"gear that leaves the stash leaves the base")
	var left := [0]
	base.leave_requested.connect(func() -> void: left[0] += 1)
	t._face_display(base.player, base.door)
	await t.frames(2)
	await t._use(base.player)
	t.check(left[0] == 1, "the door asks to go back to the hub")
	base.read_only = true
	base.show_gear(["dmr_longshot"], {"primary": "dmr_longshot"})
	await t.frames(2)
	t._face_display(base.player, base.displays[0])
	await t.frames(2)
	await t._use(base.player)
	t.check(asked.size() == 2 and base.displays[0].get_prompt() == "Longshot DMR (equipped)",
			"a base you are visiting cannot be changed")
	base.queue_free()
	await t.frames(2)

	print("Home base from the hub")
	Profile.reset()
	Profile.welcome_granted = true
	Profile.add_to_stash(["rifle_carbine", "dmr_longshot", "frame_bulwark", "bike_scrapper", "alloy_ingot"])
	Profile.equip("primary", "rifle_carbine")
	Profile.base_upgrades = BaseUpgrades.full()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	t.add_child(main)
	await t.frames(2)
	await t.frames(20)
	t.check(main.base != null and not main.hub.visible and main.raid == null, "you start in your home base")
	t.check(main.controller != null and main.controller.camera.current and main.base_hud != null,
			"the base has a camera and an overlay")
	t.check(main.base.displays.size() == 5 + StashRules.free_items().size() and main.base.display_for("rifle_carbine").equipped,
			"it shows your stash and what you have equipped")
	# Real input: look at the DMR and press F.
	var target: Node3D = main.base.display_for("dmr_longshot")
	t._face_display(main.base.player, target)
	main.controller.yaw = main.base.player.cmd.yaw
	main.controller.pitch = main.base.player.cmd.pitch
	await t.frames(3)
	Input.action_press("interact")
	await t.frames(3)
	Input.action_release("interact")
	await t.frames(2)
	t.check(Profile.equipped("primary") == "dmr_longshot", "pressing E on a rack changes your loadout")
	t.check(main.base.display_for("dmr_longshot").equipped and not main.base.display_for("rifle_carbine").equipped,
			"the displays show the change")
	main.base.equip_requested.emit("vehicle", "bike_scrapper")
	main.base.equip_requested.emit("primary", "frame_bulwark")
	t.check(Profile.equipped("vehicle") == "bike_scrapper" and Profile.equipped("primary") == "dmr_longshot",
			"a parked bike can be picked, and gear cannot go in the wrong slot")
	# No bay to walk to: what you picked is already on you, and the controls
	# and camera went with you into the new body.
	await t.frames(3)
	var suited: Actor = main.base.player
	t.check(main.base.suited and suited.weapons.any(func(w: Weapon) -> bool: return w.item_id == "dmr_longshot"),
			"the DMR you picked off the rack is in your hands at once")
	t.check(main.controller.actor == suited and main.controller.camera.current,
			"the controls and camera follow you into your new gear")
	t.check(main.base.wall_mirror.viewer == suited and main.base.wall_mirror.eye == main.controller.camera,
			"the wall mirror shows you")
	t.check(main.hub.equipped("primary") == "dmr_longshot", "the locker shows the loadout chosen in the base")
	# Every station opens its screen over the room, and Esc steps away.
	for id: String in HomeBase.STATIONS:
		if id == "arena" or id == "wardrobe":
			continue  # A way out and a mirror, not screens: checked on their own.
		var console: HomeBase.Station = main.base.station(id)
		t._face_display(main.base.player, console)
		main.controller.yaw = main.base.player.cmd.yaw
		main.controller.pitch = main.base.player.cmd.pitch
		await t.frames(2)
		t.check(main.base.player.find_interactable() == console and console.get_prompt().begins_with("[F]"),
				"the %s can be walked up to and used" % id)
		console.interact(main.base.player)
		await t.frames(2)
		t.check(main.hub.visible and main.hub.station == id and main.controller.input_blocked
				and not main.base_hud.visible, "the %s opens its screen" % id)
		t.check(main.station_screen != null and main.station_screen.get_parent() == console.screen
				and main.station_screen.focused and main.get_viewport().get_camera_3d() != main.controller.camera
				and not main._travel.visible, "the %s's screen comes up on the console and the view moves in to it" % id)
		var esc := InputEventKey.new()
		esc.keycode = KEY_ESCAPE
		esc.pressed = true
		main.hub._unhandled_input(esc)
		await t.frames(2)
		t.check(not main.hub.visible and not main.controller.input_blocked and main.base_hud.visible
				and main.station_screen == null and main.get_viewport().get_camera_3d() == main.controller.camera,
				"Esc steps away from the %s and gives the view back" % id)
	# The screen is used by clicking on it in the world: a click where the
	# records board's "Step away" button shows goes to that button.
	main.open_station("records")
	await t.get_tree().create_timer(0.6).timeout
	var live: WorldScreen = main.station_screen
	var cam := main.get_viewport().get_camera_3d()
	var mid := cam.unproject_position(live.global_position)
	t.check(live.screen_point(cam.project_ray_origin(mid), cam.project_ray_normal(mid)).distance_to(
			Vector2(main.hub_screen.size) * 0.5) < 2.0, "the middle of the view is the middle of the screen")
	var step_away: Button = main.hub._close_button
	var spot := step_away.get_global_rect().get_center()
	var on_glass := Vector3((spot.x / main.hub_screen.size.x - 0.5) * live.size.x,
			(0.5 - spot.y / main.hub_screen.size.y) * live.size.y, 0.0)
	var at := cam.unproject_position(live.global_transform * on_glass)
	for pressed: bool in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		click.position = at
		click.global_position = at
		main.get_viewport().push_input(click)
		await t.frames(1)
	await t.frames(2)
	t.check(not main.hub.visible and main.station_screen == null and not main.controller.input_blocked,
			"clicking a button on the screen in the world presses it")
	# The wardrobe is a mirror: the phone's Mirror app comes up with its
	# glass as the mirror, no screen and no flat customizer.
	if main.controller.is_third_person():
		main.controller.toggle_view()
	var wardrobe: HomeBase.Station = main.base.station("wardrobe")
	t.check(wardrobe != null and wardrobe.screen == null and main.base.wardrobe_mirror != null
			and main.base.wardrobe_mirror.get_parent() == wardrobe, "the wardrobe is a standing mirror, not a console")
	t._face_display(main.base.player, wardrobe)
	main.controller.yaw = main.base.player.cmd.yaw
	main.controller.pitch = main.base.player.cmd.pitch
	await t.frames(2)
	t.check(main.base.player.find_interactable() == wardrobe and wardrobe.get_prompt().begins_with("[F] Wardrobe"),
			"the wardrobe can be walked up to and used")
	wardrobe.interact(main.base.player)
	await t.frames(3)
	t.check(main.phone.mirror_open() and not main.hub.visible and main.station_screen == null,
			"the wardrobe brings the phone up on its Mirror app")
	t.check(main.controller.phone_mirror == main.base.wardrobe_mirror and main.mirror == null,
			"in first person you look into the wardrobe's own glass, with no mirror of its own")
	main.phone.close()
	await t.frames(2)
	t.check(main.controller.phone_mirror == null and main._wardrobe_glass == null
			and is_instance_valid(main.base.wardrobe_mirror), "putting the phone away leaves the wardrobe's glass standing")
	main.open_station("mastery")
	t.check(main.hub._sections["mastery"].visible and not main.hub._sections["loadout"].visible,
			"a station shows only its own part of the old menu")
	main.hub.close()
	t.check(main.base.door.get_prompt().contains(Worlds.social_world().display_name),
			"the door of your own base says it leads out to the plaza")
	t.check(not HomeBase.STATIONS.has("uplink") and not Hub.STATIONS.has("uplink") and main.base.station("uplink") == null
			and not main.hub._sections.has("online"), "the base has no uplink console: going online is on the phone")
	main.phone.open("servers")
	await t.frames(1)
	var address_edit: LineEdit = main.phone._address_edit
	t.check(main.phone.app == "servers" and address_edit != null and address_edit.text == Profile.last_server
			and main.phone._body.find_child("NameEdit", true, false) != null
			and main.phone._body.find_children("*", "OptionButton", true, false).is_empty(),
			"the phone's Servers app takes your name and a server's address, and never asks for a map")
	main.phone.join_server("   ")
	await t.frames(1)
	t.check(main.net == null and main.base != null and main.phone.link_status == "Type the server's address first.",
			"joining with no address asks for one and stays home")
	main._leave_from_phone()
	t.check(main.net == null and main.base != null, "leaving with no server does nothing")
	main.phone.set_link_status("")
	main.phone.close()
	var door_path := "user://test_door_%d.json" % Time.get_ticks_usec()
	var real_path := Profile.save_path
	Profile.save_path = door_path
	Profile.persist = true
	Profile.home_server = "10.0.0.7:4000"
	Profile.save()
	Profile.home_server = ""
	Profile.load_profile()
	t.check(Profile.home_server == "10.0.0.7:4000", "the profile remembers the server your door leads to")
	Profile.persist = false
	Profile.save_path = real_path
	Profile.home_server = ""
	DirAccess.remove_absolute(ProjectSettings.globalize_path(door_path))
	# A server's stash is shown while in its lobby, and the local one is left alone.
	main.hub.update_account({"name": "Vex", "stash": ["blade_arc", "bike_raider"], "loadout": {"melee": "blade_arc"},
			"mastery": {}, "raids_played": 0, "raids_extracted": 0, "kills": 0})
	main.enter_base()
	await t.frames(5)
	t.check(main.base.displays.size() == BaseLayout.plan(StashRules.equippable(["blade_arc", "bike_raider"]),
				{"melee": "blade_arc"}, main.base.upgrades).size()
			and main.base.display_for("blade_arc").equipped and main.base.display_for("rifle_scrap") != null,
			"in a lobby the base shows the stash that server keeps")
	main.base.equip_requested.emit("vehicle", "bike_raider")
	t.check(Profile.equipped("vehicle") == "bike_scrapper", "online changes go to the server, not the local profile")
	main._on_online_account_changed({"name": "Vex", "stash": ["blade_arc", "bike_raider"],
			"loadout": {"melee": "blade_arc", "vehicle": "bike_raider"}, "mastery": {},
			"raids_played": 0, "raids_extracted": 0, "kills": 0})
	await t.frames(2)
	t.check(main.base.display_for("bike_raider").equipped, "the base updates when the server answers")
	main.leave_base()
	main.hub.leave_lobby()
	await t.frames(3)
	main.visit_base("Kestrel", ["lattice_shard", "hammer_breaker"], {"melee": "hammer_breaker"}, ["trophy_hall"])
	await t.frames(5)
	t.check(main.base != null and main.base.read_only and main.base.owner_name == "Kestrel"
			and main.base.displays.size() == 2 and main.base.upgrades == ["trophy_hall"],
			"someone else's base can be visited, with the upgrades they have")
	var own_melee := Profile.equipped("melee")
	main.base.displays[0].interact(main.base.player)
	main.base.displays[1].interact(main.base.player)
	t.check(Profile.equipped("melee") == own_melee, "visiting never changes your own loadout")
	main.base.station("locker").interact(main.base.player)
	t.check(not main.hub.visible, "another player's stations cannot be used")
	main.base.leave_requested.emit()
	await t.frames(3)
	t.check(main.base != null and not main.base.read_only, "the door of a base you visit takes you home")
	main.leave_base()
	await t.frames(3)
	main.start_raid("ashfront")
	await t.frames(5)
	t.check(main.raid != null and main.raid.player.weapons[0].item_id == "dmr_longshot",
			"gear picked in the base is what you deploy with")
	main.raid.player.kill("test")
	await t.frames(150)
	main.queue_free()
	await t.frames(2)
	Profile.reset()


# --- Arena ---------------------------------------------------------------------

## Scrip in a dictionary, for arena tests that need several wallets.
