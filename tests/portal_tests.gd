extends RefCounted
## Checks for squad portals (DESIGN.md section 3, the watch's Mission tab):
## where they can lead and where they can open, who may walk through, how
## long they stay, the watch's portal icon, and landing at a world's gate
## outpost. Kept in its own file and called from the test runner. The trip
## out of the home base is `through_base`, called from the main flow test;
## the online trip through the plaza is in `_test_plaza_online`.

const KIT: Array[String] = ["rifle_scrap", "blade_scrap"]


static func run(t: Node) -> void:
	_rules(t)
	await _in_plaza(t)
	await _not_in_a_fight(t)
	await _outpost_drop(t)
	await _outpost_home(t)


static func _rules(t: Node) -> void:
	print("Portals: destinations and the watch icon")
	var where := Portal.destinations()
	var every := true
	for world in Worlds.raid_worlds():
		every = every and world.id in where
	t.check(every and Arena.ArenaVenue.ID in where and Worlds.social_world().id not in where,
			"a portal leads to every world and the arena, never to the plaza: %s" % [where])
	t.check(Hud.Wrist.TAB_SLOTS["mission"][0] == "portal" and "portal" in Hud.Wrist.SLOTS,
			"the portal is the first icon on the watch's Mission tab")
	var icon := Hud.portal_slot(where, 1)
	t.check(icon.detail == "Portal to %s" % Portal.title_of(where[1]) and icon.count == where.size()
			and icon.index == 1 and "wheel" in icon.hints and "click" in icon.hints,
			"the icon is a carousel of destinations: the wheel picks one, a click opens it (%s)" % icon.detail)
	var shut := Hud.portal_slot([] as Array[String])
	t.check(shut.empty and shut.hints.is_empty(), "outside a safe space the icon is an empty socket")
	var home := Hud.base_watch_slots("Home base", {}, [] as Array[Dictionary], 0)
	t.check(home.size() == Hud.Wrist.SLOTS.size() and home[Hud.Wrist.SLOTS.find("portal")].detail.begins_with("Portal to"),
			"the home base watch offers a portal too")


static func _in_plaza(t: Node) -> void:
	print("Portals: opened in the plaza for a squad")
	var raid := Raid.new()
	t.add_child(raid)
	raid.start_server(Worlds.social_world(), 5)
	raid.set_squad("ada", "crew")
	raid.set_squad("bo", "crew")
	var ada := raid.add_player(KIT, {}, "Ada", "ada")
	var bo := raid.add_player(KIT, {}, "Bo", "bo")
	var cy := raid.add_player(KIT, {}, "Cy", "cy")
	await t.frames(3)
	var opened: Array[Portal] = []
	raid.portal_opened.connect(func(p: Portal) -> void: opened.append(p))
	var entered: Array = []
	raid.portal_entered.connect(func(a: Actor, d: String) -> void: entered.append([a, d]))
	t.check(raid.open_portal(ada, "plaza") != "", "a portal never leads back to the plaza")
	t.check(raid.open_portal(ada, "ashfront") == "" and opened.size() == 1, "a player in the plaza opens a portal")
	var portal: Portal = opened[0] if not opened.is_empty() else null
	if portal == null:
		raid.queue_free()
		return
	var gap := portal.global_position - ada.global_position
	gap.y = 0.0
	var ahead := gap.normalized().dot(Vector3(ada.get_aim_dir().x, 0, ada.get_aim_dir().z).normalized())
	t.check(gap.length() > 0.7 and gap.length() < 3.5 and ahead > 0.9,
			"it unfolds in front of them (%.1f m ahead)" % gap.length())
	t.check(portal.open_time >= 10.0 and portal.open_time <= 20.0 and portal.openness() < 1.0,
			"it stays open about 15 seconds (%.0f s), unfolding first" % portal.open_time)
	t.check(raid.open_portal(ada, "frostline") == "Portal recharging", "the watch rests before the next portal")
	await t.frames(int(portal.unfold_time * 60.0) + 4)
	t.check(portal.openness() == 1.0, "and is fully open after %.1f s" % portal.unfold_time)
	# Someone outside the squad steps in: nothing happens.
	cy.global_position = portal.global_position
	await t.frames(4)
	t.check(entered.is_empty(), "someone outside the squad cannot walk through")
	# A squadmate steps in: the world sends them through, once.
	bo.global_position = portal.global_position
	await t.frames(4)
	t.check(entered.size() == 1 and entered[0][0] == bo and entered[0][1] == "ashfront",
			"a squadmate walks through to the world")
	await t.frames(4)
	t.check(entered.size() == 1, "and is sent only once")
	ada.global_position = portal.global_position
	await t.frames(4)
	t.check(entered.size() == 2 and entered[1][0] == ada, "the one who opened it can follow")
	var closed: Array[Portal] = []
	raid.portal_closed.connect(func(p: Portal) -> void: closed.append(p))
	portal.age = portal.open_time - 0.05
	await t.frames(6)
	t.check(closed == [portal] and raid.portals.is_empty() and not is_instance_valid(portal),
			"once its time is up the portal folds away")
	raid.queue_free()
	await t.frames(2)


static func _not_in_a_fight(t: Node) -> void:
	print("Portals: never out of a fight")
	var raid := Raid.new()
	t.add_child(raid)
	raid.start_server(Worlds.get_world("ashfront"), 6)
	var ada := raid.add_player(KIT, {}, "Ada", "ada")
	await t.frames(2)
	t.check(not raid.may_open_portal(ada) and raid.open_portal(ada, "frostline") == "Portals open only in safe zones and gate outposts"
			and raid.portals.is_empty(), "no portal opens in a world: getting out still means signing out")
	var slots := Hud.watch_slots(raid, ada)
	t.check(slots[Hud.Wrist.SLOTS.find("portal")].empty, "and the watch's portal icon is shut there")
	raid.queue_free()
	await t.frames(2)


static func _outpost_drop(t: Node) -> void:
	print("Portals: arriving at the gate outpost")
	var raid := Raid.new()
	t.add_child(raid)
	raid.start_server(Worlds.get_world("ashfront"), 7)
	t.check(not raid.outposts.is_empty(), "Ashfront has gate outposts to arrive at (%d)" % raid.outposts.size())
	var squad: Array[Actor] = []
	for key: String in ["bo", "cy"]:
		raid.set_squad(key, "crew")
		squad.append(raid.add_player(KIT, {}, key, key, 0, Raid.PORTAL_DROP))
	var landed: Array[Node3D] = []
	for actor in squad:
		landed.append(raid.outpost_at(actor.global_position))
	t.check(landed[0] != null and landed[0] == landed[1],
			"through a portal you land at the world's gate outpost, beside your squad")
	raid.queue_free()
	await t.frames(2)


static func _outpost_home(t: Node) -> void:
	print("Portals: home from a gate outpost, as a sign-out")
	Raid.zone_rules = true
	var raid := Raid.new()
	t.add_child(raid)
	raid.start_server(Worlds.get_world("ashfront"), 8)
	var squad: Array[Actor] = []
	for key: String in ["bo", "cy"]:
		raid.set_squad(key, "crew")
		squad.append(raid.add_player(KIT, {}, key, key, 0, Raid.PORTAL_DROP))
	var bo := squad[0]
	var cy := squad[1]
	var dy := raid.add_player(KIT, {}, "dy", "dy", 0, Raid.PORTAL_DROP)
	await t.frames(3)
	var outside := raid.add_player(KIT, {}, "ed", "ed")
	await t.frames(2)
	t.check(raid.state_for(bo).sheltered and Portal.choices_for(raid, bo) == [Portal.HOME],
			"in a gate outpost the watch offers one portal: home")
	t.check(Hud.watch_slots(raid, bo)[Hud.Wrist.SLOTS.find("portal")].detail == "Portal home · signs you out",
			"and the icon says it signs you out")
	t.check(raid.open_portal(bo, "frostline") != "", "no portal leads from an outpost to another world")
	if raid.outpost_at(outside.global_position) == null:
		t.check(Portal.choices_for(raid, outside).is_empty() and raid.open_portal(outside, Portal.HOME) != "",
				"outside the outpost walls no portal opens")
	var finished: Array = []
	raid.player_finished.connect(func(a: Actor, result: Dictionary) -> void: finished.append([a, result.get("outcome", "")]))
	t.check(raid.open_portal(bo, Portal.HOME) == "" and raid.state_for(bo).sign_out_left > 0.0,
			"opening it starts the gate sign-out")
	var portal: Portal = raid.portals[0] if not raid.portals.is_empty() else null
	if portal == null:
		raid.queue_free()
		Raid.zone_rules = false
		return
	t.check(portal.destination == Portal.HOME and is_equal_approx(portal.unfold_time, raid.world.outpost_sign_out_time),
			"the ring unfolds over the countdown")
	await t.frames(int(raid.world.outpost_sign_out_time * 60.0) + 6)
	t.check(finished.size() == 1 and finished[0][0] == bo and finished[0][1] == "left",
			"when the countdown ends the opener goes home with their gear (%s)" % [finished])
	dy.global_position = portal.global_position
	await t.frames(3)
	t.check(raid.state_for(dy).sign_out_left < 0.0, "someone outside the squad stepping in starts nothing")
	cy.global_position = portal.global_position
	await t.frames(3)
	t.check(raid.state_for(cy).sign_out_left > 0.0, "a squadmate stepping in starts their own sign-out")
	await t.frames(int(raid.world.outpost_sign_out_time * 60.0) + 6)
	t.check(finished.size() == 2 and finished[1][0] == cy and finished[1][1] == "left",
			"and follows home when it ends")
	raid.queue_free()
	Raid.zone_rules = false
	await t.frames(2)


## The trip out of your own base: raise the watch, pick a world on the
## portal icon, click, and walk through. `main` is in its home base.
static func through_base(t: Node, main: Node) -> void:
	print("Portals: out of the home base")
	var controller: PlayerController = main.controller
	var base: HomeBase = main.base
	t.check(controller.portal_choices() == Portal.destinations(), "in your base the watch can open a portal")
	var to := Portal.destinations().find("ashfront")
	controller.wrist_raised = true
	controller.watch_focus = Hud.Wrist.SLOTS.find("portal")
	controller.watch_focus_moved = true
	controller.portal_pick = to
	await t.frames(2)
	var card: Dictionary = Hud.base_watch_slots("Home base", base.loadout, [] as Array[Dictionary],
			controller.portal_pick)[Hud.Wrist.SLOTS.find("portal")]
	t.check(card.detail == "Portal to Ashfront", "the watch's portal icon offers %s" % card.detail)
	t.check(controller.watch_takes_fire() and controller.click_watch(), "a click on it opens the portal")
	var portal: Portal = base.portal
	t.check(portal != null and portal.destination == "ashfront" and not controller.wrist_raised,
			"the portal unfolds in the room and the watch goes down")
	if portal == null:
		return
	t.check(base.inside(base.to_local(portal.global_position)), "inside the room, clear of the walls")
	await t.frames(int(portal.unfold_time * 60.0) + 4)
	base.player.global_position = portal.global_position
	await t.frames(6)
	t.check(main.raid != null and main.base == null and main.raid.world.id == "ashfront",
			"walking through it starts the world")
