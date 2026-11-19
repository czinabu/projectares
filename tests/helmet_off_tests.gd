extends RefCounted
## Checks for taking the helmet off and clipping it to the hip (DESIGN.md
## "Helmet off"): the held `ActorCommand.helmet_off`, `Actor.helmet_stow`,
## the visor that stops working off the face, the watch's helmet icon and
## the helmet going back on where people fight. Called from the test runner
## (`-- --only helmet_off` runs just these).

const SCRAP: Array[String] = ["rifle_scrap", "blade_scrap", "pistol_service", "plate_light"]


static func run(t: Node) -> void:
	print("Helmet off")
	_command(t)
	_shown(t)
	await _simulated(t)
	await _watch(t)
	await _back_on_out_there(t)
	await _off_in_safe_zones(t)


static func _kit(helmet: String) -> Array[String]:
	var kit := SCRAP.duplicate()
	if helmet != "":
		kit.append(helmet)
	return kit


## It travels as a held key, so the server plays it and everyone sees it.
static func _command(t: Node) -> void:
	var cmd := ActorCommand.new()
	cmd.helmet_off = true
	var back := ActorCommand.new()
	back.apply_array(cmd.to_array())
	t.check(back.helmet_off, "the helmet off flag survives the trip over the network")
	t.check(ActorCommand.HELD_MASK & ActorCommand.FLAG_HELMET_OFF != 0
			and ActorCommand.ONE_SHOT_MASK & ActorCommand.FLAG_HELMET_OFF == 0,
			"and is a held key, sent to everyone with the state")
	var others := ActorCommand.STATE_HOVERING | ActorCommand.STATE_SHELTERED | ActorCommand.STATE_SIGN_OUT_BEACON \
			| ActorCommand.STATE_CHILLED | ActorCommand.ONE_SHOT_MASK | (ActorCommand.HELD_MASK & ~ActorCommand.FLAG_HELMET_OFF)
	t.check(others & ActorCommand.FLAG_HELMET_OFF == 0, "its bit is its own, apart from every other key and state bit")


## The shown take off: the hand comes up before the helmet leaves the head,
## holds it all the way down, and lets go once it is clipped on.
static func _shown(t: Node) -> void:
	t.check(ActionPose.helmet_place(0.0) == "head" and ActionPose.helmet_place(0.5) == "hand"
			and ActionPose.helmet_place(1.0) == "hip", "on the head, then in the hand, then on the hip")
	t.check(ActionPose.helmet_hand(0.0) == 0.0 and ActionPose.helmet_hand(1.0) == 0.0
			and ActionPose.helmet_hand(Actor.HELMET_LIFTED) > 0.99 and ActionPose.helmet_hand(0.6) > 0.99,
			"the hand is on the helmet from before it leaves the head until it is clipped")
	t.check(ActionPose.helmet_both(Actor.HELMET_LIFTED) > 0.99 and ActionPose.helmet_both(0.0) == 0.0
			and ActionPose.helmet_both(ActionPose.HELMET_CLIPPED) == 0.0,
			"both hands lift it off the head, and the weapon hand lets go on the way down")
	t.check(ActionPose.helmet_carry(Actor.HELMET_LIFTED) == 0.0 and ActionPose.helmet_carry(ActionPose.HELMET_CLIPPED) == 1.0,
			"it is carried from the head's place to the clip's with no jump")


## Simulated from the command: the visor stops once the helmet leaves the
## face and works again once it is back on.
static func _simulated(t: Node) -> void:
	var raid: Raid = await t._kit_raid(371, _kit("helm_seeker"))
	var p := raid.player
	t.check(p.helmet_on_head() and p.visor.levels() == 0 and p.helmet_stow == 0.0, "a helmet starts on the head")
	p.cmd.helmet_off = true
	await t.frames(6)
	t.check(p.helmet_stow > 0.0 and p.helmet_stow < 1.0 and p.helmet_on_head(),
			"taking it off takes time: the hand has it, still on the head")
	await t.frames(ceili(p.helmet_stow_time * 60.0) + 6)
	t.check(p.helmet_stow == 1.0 and p.visor.stowed and not p.helmet_on_head(), "then it is clipped to the hip")
	t.check(p.visor.enabled and p.visor.item_id in p.gear_items, "still worn gear: it drops and goes home with you")
	t.check(not p.visor.scan(), "a visor on the hip scans nothing")
	p.cmd.visor_pressed = true
	await t.frames(1)
	p.cmd.visor_pressed = false
	t.check(p.visor.cooldown_left == 0.0, "and the visor key does nothing")
	p.cmd.helmet_off = false
	await t.frames(ceili(p.helmet_stow_time * 60.0) + 6)
	t.check(p.helmet_stow == 0.0 and p.helmet_on_head() and p.visor.scan(), "put back on, it works again")
	# Bare-headed there is nothing to take off.
	Loadout.wear_helmet(p, "")
	p.cmd.helmet_off = true
	await t.frames(10)
	t.check(p.helmet_stow == 0.0 and not p.visor.stowed, "bare-headed the key does nothing")
	raid.queue_free()
	await t.frames(2)


## The watch's helmet icon on the Summon tab takes it off and puts it on.
static func _watch(t: Node) -> void:
	t.check(Hud.Wrist.TAB_SLOTS["summon"].has("helmet") and Hud.Wrist.SLOTS.has("helmet")
			and Hud.Wrist.tab_of("helmet") == "summon", "the helmet icon is on the watch's Summon tab")
	var home := Hud.base_watch_slots("Home base", {})
	t.check(home.size() == Hud.Wrist.SLOTS.size() and home[Hud.Wrist.SLOTS.find("helmet")].id == "helmet",
			"at home too")
	var raid: Raid = await t._kit_raid(372, _kit("helm_warden"))
	var p := raid.player
	var controller := PlayerController.new()
	controller.setup(p)
	raid.add_child(controller)
	await t.frames(2)
	var slots := Hud.watch_slots(raid, p)
	var icon: Dictionary = slots[Hud.Wrist.SLOTS.find("helmet")]
	t.check(icon.id == "helmet" and not icon.empty and "click" in icon.hints, "worn, a click takes it off")
	controller.wrist_raised = true
	controller.watch_focus = Hud.Wrist.SLOTS.find("helmet")
	controller.watch_focus_moved = true
	t.check(controller.watch_takes_fire(), "fire works the icon, not the gun")
	p._draw_weapon(p.weapon_for_key(1))
	await t.frames(2)
	t.check(p.get_active_weapon() != null, "with a weapon drawn")
	t.check(controller.click_watch() and controller.helmet_off and not controller.wrist_raised,
			"a click sets it off, and the watch goes down for the hand")
	await t.frames(3)
	t.check(p.get_active_weapon() == null, "it takes both hands, so the weapon is put away first")
	t.check(p.cmd.helmet_off, "the controller sends it as the held key")
	icon = Hud.watch_slots(raid, p)[Hud.Wrist.SLOTS.find("helmet")]
	t.check("put on" in str(icon.detail), "the icon then offers to put it back on")
	Loadout.wear_helmet(p, "helm_seeker")
	await t.frames(3)
	t.check(not controller.helmet_off and not p.cmd.helmet_off, "a new helmet goes on the head")
	Loadout.wear_helmet(p, "")
	icon = Hud.watch_slots(raid, p)[Hud.Wrist.SLOTS.find("helmet")]
	t.check(icon.empty, "bare-headed the icon is empty")
	raid.queue_free()
	await t.frames(2)


## Where people fight, it goes back on as you step out into it (leaving a
## gate outpost), and only stays off out there by choice.
static func _back_on_out_there(t: Node) -> void:
	Raid.zone_rules = true
	var raid: Raid = await t._kit_raid(373, _kit("helm_warden"))
	var p := raid.player
	var controller := PlayerController.new()
	controller.setup(p)
	raid.add_child(controller)
	var gate: Node3D = raid.outposts[0]
	p.global_position = raid._stand(gate.global_position)
	p.velocity = Vector3.ZERO
	await t.frames(10)
	t.check(p.weapons_locked, "in a gate outpost, weapons are locked")
	controller.toggle_helmet()
	await t.frames(5)
	t.check(controller.helmet_off and p.cmd.helmet_off, "the helmet comes off in the outpost")
	var at := Vector2.from_angle(TAU * 0.5 / 12.0) * 248.0
	p.global_position = raid._stand(Vector3(at.x, raid.map.call("ground_height", at.x, at.y), at.y))
	p.velocity = Vector3.ZERO
	await t.frames(70)
	t.check(not p.weapons_locked and not controller.helmet_off and not p.cmd.helmet_off,
			"stepping out where people fight puts it back on")
	controller.toggle_helmet()
	await t.frames(5)
	t.check(controller.helmet_off and p.cmd.helmet_off, "out there it comes off by choice and stays off")
	Raid.zone_rules = false
	raid.queue_free()
	await t.frames(2)


## In a safe zone it stays off: the face is what people meet there.
static func _off_in_safe_zones(t: Node) -> void:
	var raid := Raid.new()
	t.add_child(raid)
	raid.start(Worlds.get_world("plaza"), 374, _kit("helm_spotter"))
	await t.frames(20)
	var p := raid.player
	var controller := PlayerController.new()
	controller.setup(p)
	raid.add_child(controller)
	await t.frames(2)
	controller.toggle_helmet()
	await t.frames(ceili(p.helmet_stow_time * 60.0) + 10)
	t.check(controller.helmet_off and p.helmet_stow == 1.0 and not p.helmet_on_head(),
			"in a safe zone the helmet stays on the hip")
	raid.queue_free()
	await t.frames(2)
