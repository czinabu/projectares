extends RefCounted
## `--panels-only`, a mode `visual_check.gd` finds by itself.
## `-- <output_dir> --panels-only` shoots the station screens with their
## item cards (the trader, the locker, the fabricator, the records board)
## flat and as seen in the room, and a Concourse storefront's screen.


## Each station screen with its item card on a picked item: the screen's
## own picture full size, then the room's view of it.
static func shoot(v: Node, out_dir: String, _args: PackedStringArray) -> void:
	Profile.persist = false
	Profile.reset()
	Profile.welcome_granted = true
	Profile.scrip = 1200
	Profile.add_to_stash(["rifle_carbine", "dmr_longshot", "frame_trooper", "helm_seeker", "boots_thruster",
			"bike_scrapper", "optic_scope", "chip_blink", "bp_jetpack", "bp_dmr_longshot", "upgrade_data",
			"upgrade_data", "power_cell", "power_cell", "alloy_ingot", "scrap_metal", "scrap_metal", "medkit",
			"reactor_core", "artifact_cloak"])
	Profile.equip("primary", "rifle_carbine")
	Profile.equip("frame", "frame_trooper")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	v.add_child(main)
	await v._settle(30)
	var hub: Hub = main.hub
	var shots := [["trader", "shop", "armory", "smg_stinger"], ["trader", "shop", "outfitter", "frame_runner"],
			["trader", "shop", "garage", "bike_scrapper"], ["trader", "shop", "sell", "reactor_core"],
			["locker", "locker", "", "dmr_longshot"], ["locker", "locker", "", "helm_seeker"],
			[HomeBase.CRAFT_ID, "craft", "", "jetpack_mk2"], ["records", "records", "", "artifact_cloak"]]
	for shot: Array in shots:
		main.open_station(shot[0])
		if not hub.visible:
			# A starter base shares a console between stations.
			hub.open_station(shot[0])
		await v._settle(10)
		var card: Node = null
		match shot[1]:
			"shop":
				hub._shop.open_tab(shot[2])
				card = hub._shop.card
			"locker":
				card = hub._locker_card
			"craft":
				card = hub._craft.card
			"records":
				card = hub._stash_card
		card.show_item(shot[3])
		await v._settle(20)
		var tag := "%s_%s" % [shot[0], shot[3]]
		main.hub_screen.get_texture().get_image().save_png(out_dir.path_join("panel_%s.png" % tag))
		print("saved panel_%s.png" % tag)
		if shot[3] == "smg_stinger":
			await v._shot(out_dir.path_join("panel_in_room.png"))
		hub.close()
		await v._settle(4)
	main.queue_free()
	await v._settle(2)
	# A Concourse storefront's screen, as its terminal shows it.
	var screen_view := SubViewport.new()
	screen_view.size = Vector2i(1280, 720)
	screen_view.disable_3d = true
	screen_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var view: Control = (load("res://core/main.gd") as GDScript).ShopView.new()
	view.panel = load("res://core/economy/shop_panel.gd").new()
	view.panel.set("shop_filter", "armory")
	screen_view.add_child(view)
	v.add_child(screen_view)
	await v._settle(10)
	view.panel.get("card").show_item("hammer_breaker")
	await v._settle(20)
	screen_view.get_texture().get_image().save_png(out_dir.path_join("panel_storefront.png"))
	print("saved panel_storefront.png")
	screen_view.queue_free()
