extends RefCounted
## DEV MODE: `--console-only`, a mode `visual_check.gd` finds by itself.
## `-- <output_dir> --console-only` shows the phone's Console app held up
## after a few commands (a storm called in, bots and a vehicle spawned).
## Delete this file with dev mode.

const DevMode := preload("res://core/dev/dev_mode.gd")
const DevConsole := preload("res://core/dev/dev_console.gd")


static func shoot(v: Node, out_dir: String, _args: PackedStringArray) -> void:
	var was := DevMode.enabled
	var persisted := DevMode.persist
	DevMode.persist = false
	DevMode.enabled = true
	var raid := Raid.new()
	v.add_child(raid)
	raid.start(Worlds.get_world("ashfront"), 42)
	v._armed(raid)
	var controller := PlayerController.new()
	controller.setup(raid.player)
	raid.add_child(controller)
	var hud := Hud.new()
	hud.setup(raid, controller)
	raid.add_child(hud)
	var phone: CanvasLayer = load("res://core/phone/phone.gd").new()
	v.add_child(phone)
	phone.console_command.connect(func(line: String) -> void:
		phone.add_console_lines(DevConsole.run(line, raid, raid.player, false)))
	await v._settle(60)
	for bot in raid.bots:
		bot.set_physics_process(false)
		for child in bot.get_children():
			if child is BotBrain:
				child.set_physics_process(false)
	phone.open()
	controller.input_blocked = true
	controller.phone_out = true
	phone.set_holder(raid.player)
	phone.open_app("console")
	for line in ["where", "war 0.9", "storm here", "bots 3", "vehicle bike_scrapper"]:
		phone.run_console(line)
	await v._settle(40)
	await v._shot(out_dir.path_join("console_first.png"))
	phone._screen.get_texture().get_image().save_png(out_dir.path_join("console_screen.png"))
	phone.close()
	DevMode.enabled = was
	DevMode.persist = persisted
