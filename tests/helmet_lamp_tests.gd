extends RefCounted
## Checks for the lamp on a worn helmet (Caleb's ask): the held
## `ActorCommand.lamp`, its key (J), `Actor.lamp_lit`, dark with the helmet
## on the hip and lit again when it goes back on. The beam itself is view
## only (`ActorSkin._update_lamp`). Called from the test runner
## (`-- --only helmet_lamp` runs just these).

const KIT: Array[String] = ["rifle_scrap", "blade_scrap", "pistol_service", "plate_light", "helm_warden"]


static func run(t: Node) -> void:
	print("Helmet lamp")
	_command(t)
	await _key_and_hip(t)


## It travels as a held key, so the server relays it and everyone sees it.
static func _command(t: Node) -> void:
	var cmd := ActorCommand.new()
	cmd.lamp = true
	var back := ActorCommand.new()
	back.apply_array(cmd.to_array())
	t.check(back.lamp, "the lamp flag survives the trip over the network")
	var packed: Array = NetSession.unpack_inputs(NetSession.pack_inputs([[1, cmd.to_array(), 0]]))
	back = ActorCommand.new()
	back.apply_array(packed[0][1])
	t.check(back.lamp, "and through a packed input")
	t.check(ActorCommand.HELD_MASK & ActorCommand.FLAG_LAMP != 0
			and ActorCommand.ONE_SHOT_MASK & ActorCommand.FLAG_LAMP == 0,
			"and is a held key, sent to everyone with the state")
	var others := ActorCommand.STATE_HOVERING | ActorCommand.STATE_SHELTERED | ActorCommand.STATE_SIGN_OUT_BEACON \
			| ActorCommand.STATE_CHILLED | ActorCommand.ONE_SHOT_MASK | (ActorCommand.HELD_MASK & ~ActorCommand.FLAG_LAMP)
	t.check(others & ActorCommand.FLAG_LAMP == 0, "its bit is its own, apart from every other key and state bit")


## J switches it, shared with no other action; it goes dark on the hip and
## lights again with the helmet back on; bare-headed there is nothing to
## switch.
static func _key_and_hip(t: Node) -> void:
	var setup: GDScript = preload("res://core/input_setup.gd")
	var keys: Dictionary = setup.KEY_ACTIONS
	t.check(keys.get("lamp", 0) == KEY_J, "the lamp key is J")
	var sharing: Array[String] = []
	for action: String in keys:
		if action != "lamp" and keys[action] == keys.get("lamp", 0):
			sharing.append(action)
	t.check(sharing.is_empty(), "no other action shares the lamp key (%s)" % ", ".join(sharing))
	var raid: Raid = await t._kit_raid(381, KIT)
	var p := raid.player
	var controller := PlayerController.new()
	controller.setup(p)
	raid.add_child(controller)
	await t.frames(2)
	t.check(not p.lamp_lit(), "a helmet's lamp starts off")
	var press := InputEventKey.new()
	press.physical_keycode = KEY_J
	press.pressed = true
	controller._unhandled_input(press)
	await t.frames(3)
	t.check(controller.lamp_on and p.cmd.lamp and p.lamp_lit(), "pressing it switches the lamp on")
	controller.toggle_helmet()
	await t.frames(ceili(p.helmet_stow_time * 60.0) + 6)
	t.check(not p.helmet_on_head() and p.cmd.lamp and not p.lamp_lit(), "on the hip it goes dark, still switched on")
	controller.toggle_helmet()
	await t.frames(ceili(p.helmet_stow_time * 60.0) + 6)
	t.check(p.helmet_on_head() and p.lamp_lit(), "back on the head it lights again")
	controller._unhandled_input(press)
	await t.frames(3)
	t.check(not controller.lamp_on and not p.cmd.lamp and not p.lamp_lit(), "and the key switches it off")
	Loadout.wear_helmet(p, "")
	await t.frames(2)
	controller._unhandled_input(press)
	await t.frames(3)
	t.check(not controller.lamp_on and not p.lamp_lit(), "bare-headed there is no lamp to switch")
	raid.queue_free()
	await t.frames(2)
