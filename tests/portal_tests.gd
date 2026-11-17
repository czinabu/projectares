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
	await _home_from_a_world(t)
	_not_in_the_arena(t)
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
	var base := Portal.from_base()
	t.check(base.slice(0, where.size()) == where and base.back() == Portal.PLAZA and Portal.HOME not in base,
			"from your base a portal also leads out to the plaza: %s" % [base])
	t.check(Portal.is_place(Portal.HOME) and Portal.is_place(Portal.PLAZA) and Portal.is_place("ashfront")
			and not Portal.is_place("nowhere"), "the network accepts only real places")
	t.check(Portal.title_of(Portal.PLAZA) == Worlds.social_world().display_name, "the plaza goes by its own name")
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
	var here := Portal.choices_for(raid, ada)
	t.check(here.slice(0, Portal.destinations().size()) == Portal.destinations() and here.back() == Portal.HOME,
			"in the plaza a portal leads to every world, the arena and home: %s" % [here])
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
	# Home from the plaza: a trip, not a sign-out.
	raid.state_for(ada).portal_ready_at = -INF
	entered.clear()
	t.check(raid.open_portal(ada, Portal.HOME) == "" and raid.state_for(ada).sign_out_left < 0.0,
			"a portal home opens in the plaza, and starts no sign-out")
	var home: Portal = raid.portals.back() if not raid.portals.is_empty() else null
	if home != null:
		t.check(not home.signs_out and home.unfold_time < 1.0, "it opens as quickly as any other")
		await t.frames(int(home.unfold_time * 60.0) + 4)
		bo.global_position = home.global_position
		await t.frames(4)
		t.check(entered.size() == 1 and entered[0][0] == bo and entered[0][1] == Portal.HOME,
				"a squadmate walks through it home")
	raid.queue_free()
	await t.frames(2)


static func _home_from_a_world(t: Node) -> void:
	print("Portals: home from out in a world, as a sign-out")
	var raid := Raid.new()
	t.add_child(raid)
	raid.start_server(Worlds.get_world("ashfront"), 6)
	raid.set_squad("ada", "crew")
	raid.set_squad("bo", "crew")
	var ada := raid.add_player(KIT, {}, "Ada", "ada")
	var bo := raid.add_player(KIT, {}, "Bo", "bo")
	await t.frames(3)
	var state := raid.state_for(ada)
	t.check(not state.sheltered and Portal.choices_for(raid, ada) == [Portal.HOME],
			"out in a world the watch offers one portal, home")
	t.check(Hud.watch_slots(raid, ada)[Hud.Wrist.SLOTS.find("portal")].detail == "Portal home · signs you out",
			"and the icon says it signs you out")
	t.check(raid.open_portal(ada, "frostline") == "Out here a portal only leads home" and raid.portals.is_empty(),
			"no portal leads from one world into another")
	# In a fight it does not open: the sign-out refuses it.
	state.last_combat = raid.clock
	t.check(raid.open_portal(ada, Portal.HOME) == "You cannot sign out now" and raid.portals.is_empty(),
			"no portal home opens in a fight")
	state.last_combat = -INF
	var finished: Array = []
	raid.player_finished.connect(func(a: Actor, result: Dictionary) -> void: finished.append([a, result]))
	t.check(raid.open_portal(ada, Portal.HOME) == "" and state.sign_out_left > 0.0,
			"opening it starts the sign-out")
	t.check(is_equal_approx(state.sign_out_total, raid.world.sign_out_time),
			"at the full sign-out time on the ground (%.0f s), not the gate's" % state.sign_out_total)
	var portal: Portal = raid.portals[0] if not raid.portals.is_empty() else null
	if portal == null:
		raid.queue_free()
		return
	t.check(portal.signs_out and is_equal_approx(portal.unfold_time, state.sign_out_total)
			and portal.open_time > portal.unfold_time + 10.0,
			"the ring unfolds over the countdown, then stays open for the squad")
	# A hit cancels the sign-out, and the ring folds away with it.
	var closed: Array[Portal] = []
	raid.portal_closed.connect(func(p: Portal) -> void: closed.append(p))
	await t.frames(30)
	raid._mark_combat(state)
	await t.frames(2)
	t.check(state.sign_out_left < 0.0 and closed == [portal] and raid.portals.is_empty(),
			"a fight cancels it and the ring folds away")
	state.last_combat = -INF
	state.portal_ready_at = -INF
	t.check(raid.open_portal(ada, Portal.HOME) == "", "out of the fight it opens again")
	portal = raid.portals[0] if not raid.portals.is_empty() else null
	if portal == null:
		raid.queue_free()
		return
	t.check(raid.open_portal(ada, Portal.HOME) != "" and raid.portals.size() == 1,
			"one at a time while signing out")
	# Skip most of the countdown; the ring keeps in step.
	state.sign_out_left = 0.5
	await t.frames(3)
	t.check(portal.age > portal.unfold_time - 1.0, "the ring follows the countdown (%.1f of %.1f s)"
			% [portal.age, portal.unfold_time])
	await t.frames(45)
	t.check(finished.size() == 1 and finished[0][0] == ada and finished[0][1].get("outcome", "") == "left"
			and finished[0][1].get("door", "") == Portal.HOME,
			"when it ends they go home with their gear, through the portal's door")
	t.check(raid.portals.size() == 1 and is_instance_valid(portal) and portal.openness() == 1.0,
			"and the ring stays open for the squad")
	bo.global_position = portal.global_position
	await t.frames(3)
	var bo_state := raid.state_for(bo)
	t.check(bo_state.sign_out_left > 0.0 and bo_state.sign_out_door
			and is_equal_approx(bo_state.sign_out_total, raid.world.sign_out_time),
			"a squadmate stepping in starts their own full sign-out")
	raid.queue_free()
	await t.frames(2)


static func _not_in_the_arena(t: Node) -> void:
	var raid := Raid.new()
	raid.world = Arena.ArenaVenue.new()
	var actor := Actor.new()
	t.check(Portal.choices_for(raid, actor).is_empty(), "no portal opens in the arena: leaving it has its own way")
	actor.free()
	raid.free()


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
		t.check(Portal.choices_for(raid, outside) == [Portal.HOME] and not raid.state_for(outside).sheltered,
				"outside the outpost walls the portal home is there too, at the full sign-out time")
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
	t.check(controller.portal_choices() == Portal.from_base(), "in your base the watch can open a portal")
	var to := Portal.destinations().find("ashfront")
	controller.wrist_raised = true
	controller.watch_focus = Hud.Wrist.SLOTS.find("portal")
	controller.watch_focus_moved = true
	controller.portal_pick = to
	await t.frames(2)
	var card: Dictionary = Hud.base_watch_slots("Home base", base.loadout, [] as Array[Dictionary],
			controller.portal_pick)[Hud.Wrist.SLOTS.find("portal")]
	t.check(card.detail == "Portal to Ashfront", "the watch's portal icon offers %s" % card.detail)
	t.check(controller.watch_takes_fire() and controller.click_watch() and controller.watch_open == "portal"
			and base.portal == null, "a first click opens the icon's list of places")
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
