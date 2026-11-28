extends RefCounted
## Checks for leaving a world quickly and quitting the game (DESIGN.md
## "Abandon" and "Quitting"): the watch's Abandon is a death where you
## stand (the bag drops, the insured item is recalled, a recent attacker
## gets the kill, the game goes home), held for a few seconds so a stray
## click never throws a life away, and only where gear is at stake; the
## phone's power button quits on a second tap; a body left standing by a
## solo quit goes home with what it carries once its countdown ends.

const PhoneScript := preload("res://core/phone/phone.gd")
const KIT: Array[String] = ["rifle_carbine", "jetpack_mk2", "blade_scrap"]


static func run(t: Node) -> void:
	Profile.reset()
	var ashfront := Worlds.get_world("ashfront")
	# The bag path; Ashfront's scrip piles follow the same death rule.
	ashfront.death_drops_scrip = false
	await _abandon_is_a_death(t)
	await _abandon_credits_the_attacker(t)
	await _abandon_where(t)
	ashfront.death_drops_scrip = true
	await _watch_hold(t)
	await _phone_two_taps(t)
	await _quit_body_goes_home(t)


static func _raid(t: Node, p_seed: int, insured := "") -> Raid:
	var raid := Raid.new()
	raid.apply_to_profile = false
	t.add_child(raid)
	raid.start(Worlds.get_world("ashfront"), p_seed, KIT, {}, "", 0, "", insured)
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
	await t.frames(30)
	raid.player.protected_left = 0.0
	return raid


static func _abandon_is_a_death(t: Node) -> void:
	print("Abandon: a death where you stand, the bag and the safety nets included")
	var raid := await _raid(t, 501, "rifle_carbine")
	var results: Array[Dictionary] = []
	raid.player_finished.connect(func(_a: Actor, r: Dictionary) -> void: results.append(r))
	raid.player.inventory.add_item("scrap_metal")
	t.check(raid.can_abandon(raid.player), "out in a world with gear at stake, a life can be abandoned")
	t.check(raid.abandon(raid.player) and raid.player.is_dead, "abandoning ends the life at once")
	await t.frames(2)
	var bag: LootContainer = null
	for child in raid.get_children():
		if child is LootContainer and (child as LootContainer).is_bag:
			bag = child
	t.check(bag != null and "scrap_metal" in bag.items and "jetpack_mk2" in bag.items
			and "rifle_carbine" not in bag.items,
			"what was carried lies in the bag for anyone; the insured item is not in it")
	var r: Dictionary = results[0] if not results.is_empty() else {}
	t.check(r.get("outcome", "") == "died" and r.get("abandoned", false) and r.get("cause", "") == "abandon",
			"the result is a death, marked abandoned, so the game goes straight home")
	t.check(r.get("recalled", "") == "rifle_carbine" and "rifle_carbine" in r.get("brought_home", []),
			"the insured item is recalled home, as on any death")
	t.check(r.get("salvaged", []) == ["jetpack_mk2"], "and the crafted rig lost pays its salvage")
	t.check(r.get("killed_by", "x") == "", "nobody hurt them, so nobody gets the kill")
	t.check(not raid.abandon(raid.player), "a dead body cannot abandon again")
	raid.queue_free()
	await t.frames(2)


static func _abandon_credits_the_attacker(t: Node) -> void:
	print("Abandon: in a fight the last attacker gets the kill")
	var raid := await _raid(t, 502)
	var results: Array[Dictionary] = []
	raid.player_finished.connect(func(_a: Actor, r: Dictionary) -> void: results.append(r))
	var foe: Actor = raid.bots[0] if not raid.bots.is_empty() else null
	t.check(foe != null, "a bot to do the hurting")
	if foe == null:
		raid.queue_free()
		return
	var hit := DamageInfo.make(5.0, foe, "bullet", raid.player.global_position)
	Combat.deal(raid.player, hit)
	t.check(not raid.player.is_dead, "a scratch, not a kill")
	raid.abandon(raid.player)
	await t.frames(2)
	var r: Dictionary = results[0] if not results.is_empty() else {}
	t.check(r.get("killed_by", "") == foe.display_name,
			"giving up mid-fight hands the kill to whoever last hurt you: %s" % r.get("killed_by", ""))
	raid.queue_free()
	await t.frames(2)

	# Long after the fight, it is nobody's kill.
	raid = await _raid(t, 503)
	results.clear()
	raid.player_finished.connect(func(_a: Actor, r2: Dictionary) -> void: results.append(r2))
	foe = raid.bots[0]
	Combat.deal(raid.player, DamageInfo.make(5.0, foe, "bullet", raid.player.global_position))
	raid.state_for(raid.player).last_hit_at = raid.clock - raid.world.combat_time - 1.0
	raid.abandon(raid.player)
	await t.frames(2)
	r = results[0] if not results.is_empty() else {}
	t.check(r.get("outcome", "") == "died" and r.get("killed_by", "x") == "",
			"once the fight is over, abandoning credits nobody")
	raid.queue_free()
	await t.frames(2)


static func _abandon_where(t: Node) -> void:
	print("Abandon: only where gear is at stake, and never for a body left standing")
	var raid := await _raid(t, 504)
	var p := raid.player
	var world := raid.world
	world.safe_zone = true
	t.check(not raid.can_abandon(p) and not raid.abandon(p) and not p.is_dead
			and Hud.abandon_slot(raid, p).empty, "a safe zone has nothing to abandon, and the watch shows it empty")
	world.safe_zone = false
	world.gear_at_risk = false
	t.check(not raid.can_abandon(p), "nor anywhere nothing is at stake (the arena, a race)")
	world.gear_at_risk = true
	var slot := Hud.abandon_slot(raid, p)
	t.check(not slot.empty and str(slot.detail).begins_with("Hold to abandon") and "worth" in str(slot.detail),
			"out in the world the icon says to hold it, and what it costs: %s" % slot.detail)
	t.check(Hud.abandon_slot(raid, p, 0.5).progress == 0.5 and Hud.abandon_slot(raid, p, 0.5).alert,
			"while held it shows the hold's progress")
	t.check("abandon" in Hud.Wrist.SLOTS and "abandon" in Hud.Wrist.TAB_SLOTS.mission
			and Hud.Wrist.tab_of("abandon") == "mission", "it sits on the watch's Mission tab beside Sign out")
	raid.remove_player(p)
	t.check(not raid.can_abandon(p) and not raid.abandon(p),
			"a body left standing by a quit cannot be abandoned (its owner is gone)")
	raid.queue_free()
	await t.frames(2)
	var home := Hud.base_watch_slots("Home base", {})
	t.check(home.size() == Hud.Wrist.SLOTS.size() and home[Hud.Wrist.SLOTS.find("abandon")].empty,
			"at home the icon is an empty socket")


static func _watch_hold(t: Node) -> void:
	print("Abandon: held on the watch for a few seconds, never a stray click")
	var raid := await _raid(t, 505)
	var p := raid.player
	var controller := PlayerController.new()
	controller.setup(p)
	raid.add_child(controller)
	var asked := [0]
	controller.abandon_requested.connect(func() -> void: asked[0] += 1)
	controller.wrist_raised = true
	controller.watch_focus_moved = true
	controller.watch_focus = Hud.Wrist.SLOTS.find("abandon")
	t.check(controller.is_on_abandon() and controller.watch_takes_fire(),
			"on the Abandon icon fire works the watch, never the gun")
	controller.tick_abandon(5.0, true)
	t.check(asked[0] == 0, "holding fire without a click that began on the icon does nothing")
	t.check(controller.click_watch() and controller.abandon_progress() == 0.0, "a click on it starts the hold")
	controller.tick_abandon(controller.abandon_hold * 0.5, true)
	controller.tick_abandon(0.1, false)
	t.check(asked[0] == 0 and controller.abandon_progress() < 0.0, "letting go early calls it off")
	controller.click_watch()
	controller.tick_abandon(controller.abandon_hold * 0.6, true)
	t.check(asked[0] == 0 and controller.abandon_progress() > 0.5, "half-way it is only progress")
	controller.tick_abandon(controller.abandon_hold * 0.5, true)
	t.check(asked[0] == 1 and not controller.wrist_raised, "held to the end it asks to abandon and lowers the watch")
	controller.queue_free()
	raid.queue_free()
	await t.frames(2)


static func _phone_two_taps(t: Node) -> void:
	print("Quitting: the phone's power button, two taps from any page")
	var phone: CanvasLayer = PhoneScript.new()
	t.add_child(phone)
	await t.frames(1)
	var quits := [0]
	phone.quit_requested.connect(func() -> void: quits[0] += 1)
	phone.quit_note_for = func() -> String: return "Your body stands for 15 s first."
	phone.toggle()
	phone.open_app("news")
	await t.frames(1)
	var power := phone.find_child("Power", true, false)
	t.check(power != null and power.is_visible_in_tree(), "the status bar shows a power button inside an app")
	power.tapped.emit()
	t.check(quits[0] == 0 and phone.quit_armed(), "the first tap only arms it")
	t.check("15 s" in phone.quit_note(), "and says what quitting does to your gear here")
	power.tapped.emit()
	t.check(quits[0] == 1 and not phone.quit_armed(), "the second tap quits")
	phone.quit_note_for = Callable()
	t.check(phone.quit_note() != "", "with nothing at stake it still says so")
	phone._quit_armed_until = Time.get_ticks_msec() - 1
	phone.ask_quit()
	t.check(quits[0] == 1, "a second tap that comes too late only arms it again")
	phone.queue_free()
	await t.frames(1)


static func _quit_body_goes_home(t: Node) -> void:
	print("Quitting solo: the body stands its countdown, then the gear goes home")
	var raid := await _raid(t, 506)
	var world := raid.world
	var was := world.sign_out_time
	world.sign_out_time = 0.5
	var results: Array[Dictionary] = []
	raid.player_finished.connect(func(_a: Actor, r: Dictionary) -> void: results.append(r))
	raid.player.inventory.add_item("scrap_metal")
	raid.remove_player(raid.player)
	t.check(raid.sign_out_progress(raid.player) >= 0.0 and raid.is_unguarded(raid.player),
			"quitting leaves the body standing, counting down")
	await t._wait_until(func() -> bool: return not results.is_empty(), 120)
	var r: Dictionary = results[0] if not results.is_empty() else {}
	t.check(r.get("outcome", "") == "left" and "scrap_metal" in r.get("brought_home", [])
			and "rifle_carbine" in r.get("brought_home", []),
			"a body that survives its countdown takes everything home")
	world.sign_out_time = was
	raid.queue_free()
	await t.frames(2)
