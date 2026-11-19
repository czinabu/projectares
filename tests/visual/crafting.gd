extends RefCounted
## `--crafting-only`, a mode `visual_check.gd` finds by itself.
## `-- <output_dir> --crafting-only` shoots the fabricator on the gunsmith
## bench: in the starter bunker, in the armory, and its screen in use.

const BaseUpgrades := preload("res://core/base/base_upgrades.gd")


## The fabricator beside the bench, and the craft screen on it.
static func shoot(v: Node, out_dir: String, _args: PackedStringArray) -> void:
	for full: bool in [false, true]:
		var base := HomeBase.new()
		base.show_gear(["rifle_carbine", "optic_reflex", "jetpack_mk2", "mech_bulwark"], {"primary": "rifle_carbine"},
				BaseUpgrades.full() if full else [])
		v.add_child(base)
		var camera := Camera3D.new()
		camera.fov = 55.0
		base.add_child(camera)
		camera.make_current()
		base.player.global_position = Vector3(0, 0.1, 6)
		await v._settle(20)
		var bench := base.bench_transform()
		camera.look_at_from_position(bench * Vector3(-0.3, 1.9, 1.7), bench * Vector3(2.0, 1.4, 0.8))
		await v._settle(4)
		await v._shot(out_dir.path_join("fabricator_%s.png" % ("full" if full else "bunker")))
		var craft := base.station(HomeBase.CRAFT_ID).transform
		camera.look_at_from_position(craft * Vector3(0, 1.7, 2.2), craft * Vector3(0, 1.1, 0))
		await v._settle(4)
		await v._shot(out_dir.path_join("fabricator_%s_front.png" % ("full" if full else "bunker")))
		base.queue_free()
		await v._settle(2)
	# The screen in use, as the player sees it, with one recipe ready.
	Profile.persist = false
	Profile.reset()
	Profile.welcome_granted = true
	Profile.scrip = 1000
	Profile.add_to_stash(["bp_jetpack", "bp_dmr_longshot", "upgrade_data", "upgrade_data", "upgrade_data",
			"power_cell", "power_cell", "alloy_ingot", "circuit_board"])
	var main: Node = load("res://scenes/main.tscn").instantiate()
	v.add_child(main)
	await v._settle(30)
	main.open_station(HomeBase.CRAFT_ID)
	await v._settle(60)
	await v._shot(out_dir.path_join("fabricator_screen.png"))
	main.queue_free()
	await v._settle(2)
