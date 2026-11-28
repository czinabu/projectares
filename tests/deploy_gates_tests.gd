extends RefCounted
## The `deploy_gates` checks: the Concourse's gate terrace. Each open gate
## carries only its name, its risk and (from the server) how its world is
## doing, the full write-up stands on a console beside it, sealed gates are
## kept for worlds to come, and the gates' glimpses and panels are read from
## each world's planet. The test runner finds this file by itself.

const PlazaView := preload("res://core/social/plaza_view.gd")
const GateLook := preload("res://core/visual/gate_look.gd")
const PlazaMap := preload("res://worlds/plaza/map.gd")


static func run(t: Node) -> void:
	print("Deploy gates")
	var plaza := Worlds.social_world()
	if plaza == null:
		t.check(false, "the registry finds the plaza")
		return

	# What a gate says about risk comes from the world's rules alone.
	var war := WorldDef.new()
	war.death_drops_scrip = true
	var war_stakes: Array = PlazaMap.gate_stakes(war)
	t.check(str(war_stakes[0]) == "HIGH RISK  ·  PVP  ·  LOSE YOUR KIT" and (war_stakes[1] as Color).r > 0.9,
			"a PvP world where the fallen lose their kit reads high risk, in red: %s" % war_stakes[0])
	var loot := WorldDef.new()
	t.check(str(PlazaMap.gate_stakes(loot)[0]).ends_with("FULL LOOT"), "a plain PvP world is full loot")
	var gentle := WorldDef.new()
	gentle.players_allied = true
	gentle.keep_gear_on_death = true
	var gentle_stakes: Array = PlazaMap.gate_stakes(gentle)
	t.check(str(gentle_stakes[0]) == "LOW RISK  ·  CO-OP  ·  KEEP GEAR" and (gentle_stakes[1] as Color).b > 0.9,
			"a co-op world that keeps your gear reads low risk, in blue: %s" % gentle_stakes[0])
	var race := WorldDef.new()
	race.weapons_free = false
	t.check(str(PlazaMap.gate_stakes(race)[0]).begins_with("NO RISK"), "a world where nobody fights reads no risk")

	# The terrace: an arch per raid world, the rest sealed.
	var raid := Raid.new()
	t.add_child(raid)
	raid.mode = Raid.Mode.SERVER
	raid.start_server(plaza, 5)
	await t.frames(2)
	var worlds := Worlds.raid_worlds()
	var bays: Array[Dictionary] = raid.map.gate_bays()
	t.check(bays.size() == maxi(PlazaMap.GATE_ARCHES, worlds.size()), "a bay for every arch (%d)" % bays.size())
	var open_ok := true
	for i in bays.size():
		var bay := bays[i]
		var open := i < worlds.size()
		if open != (bay.portal != null) or (open and str(bay.world_id) != worlds[i].id) \
				or (bay.fins as Array).size() != 2:
			open_ok = false
	t.check(open_ok, "the worlds fill the first arches, the rest stand sealed, each between two lit fins")
	t.check(bays.all(func(bay: Dictionary) -> bool: return bay.glimpse == null and (bay.meters as Array).is_empty()),
			"no glimpse or panels where nothing is drawn")

	# The long write-up moved off the arch onto a console beside it.
	var labels := raid.map.find_children("*", "Label3D", true, false)
	var on_arch := labels.any(func(label: Label3D) -> bool:
		return worlds.any(func(world: WorldDef) -> bool: return label.text == world.description))
	t.check(not on_arch, "no gate carries its world's whole write-up")
	var consoles := raid.get_tree().get_nodes_in_group("gate_console").filter(func(n: Node) -> bool:
		return raid.map.is_ancestor_of(n))
	t.check(consoles.size() == worlds.size(), "a console beside every open gate (%d)" % consoles.size())
	var read_ok := true
	for node: Node in consoles:
		var console := node as Node3D
		var id := str(console.get_meta("world_id", ""))
		var screen := console.get_node_or_null("Screen") as Label3D
		var bay: Dictionary = {}
		for one in bays:
			if one.world_id == id:
				bay = one
		var world := Worlds.get_world(id)
		if screen == null or world == null or bay.is_empty() or not screen.text.contains(world.description) \
				or screen.visibility_range_end <= 0.0 or screen.visibility_range_end > 25.0 \
				or console.global_position.distance_to(bay.at) > 12.0:
			read_ok = false
	t.check(read_ok, "each console carries its world's write-up, is near its gate and is drawn only up close")

	# The live line sits flat on the gate's face, readable from across the plaza.
	var status := {}
	var routes := {}
	for world in worlds:
		status[world.id] = {"players": 3, "war": 0.4, "level": "Skirmish"}
		routes[world.id] = 1
	var view: CanvasLayer = PlazaView.new()
	view.setup(raid, routes, status)
	t.add_child(view)
	await t.frames(1)
	var first: Dictionary = bays[0]
	var sign: Label3D = view.heat_signs.get(str(first.world_id))
	var portal: Node3D = first.portal
	t.check(sign != null and sign.billboard == BaseMaterial3D.BILLBOARD_DISABLED and sign.text.begins_with("SKIRMISH")
			and sign.text.contains("3 PLAYERS") and absf(sign.global_position.y - portal.global_position.y - 10.25) < 0.05
			and sign.global_position.z < portal.global_position.z and sign.pixel_size * sign.font_size >= 0.4,
			"the gate's live line reads big and flat across the top of its doorway: %s" % (sign.text if sign else "none"))
	view.queue_free()

	# How full a world is, for its panels.
	t.check(PlazaView.gate_fill({}, 32, 24) == 0.0 and PlazaView.gate_fill({"players": 0}, 32, 24) == 0.0,
			"an empty or unknown world lights no slat")
	t.check(is_equal_approx(PlazaView.gate_fill({"players": 1}, 32, 24), 1.0 / 24.0),
			"one player lights one slat")
	t.check(is_equal_approx(PlazaView.gate_fill({"players": 16}, 32, 24), 0.5)
			and PlazaView.gate_fill({"players": 40}, 32, 24) == 1.0, "a world fills its panel as it fills up")

	# The glimpse is read from the world's planet, with nothing named.
	var ash := GateLook.window_params(PlanetTypes.get_type("ashland"))
	t.check(int(ash.air) == GateLook.WEATHER["embers"] and int(ash.storm) == GateLook.WEATHER["ash"]
			and float(ash.glow_amount) > 0.0, "an ash planet's gate shows embers, ash and glowing cracks")
	var ice := GateLook.window_params(PlanetTypes.get_type("glacier"))
	t.check(int(ice.storm) == GateLook.WEATHER["snow"] and float(ice.get("cap_amount", 0.0)) > 0.0
			and float(ice.glow_amount) == 0.0, "a glacier's gate shows snow on snow-capped ridges")
	var glimpse := GateLook.window(PlanetTypes.get_type("glacier"), Vector2(8.2, 11.8), Color.ORANGE)
	t.check(glimpse.name == "Glimpse" and glimpse.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			and (glimpse.material_override as ShaderMaterial).shader == GateLook.WINDOW_SHADER,
			"a glimpse is one shadowless sheet with the window shader")
	glimpse.free()
	var one := GateLook.meter(Vector2(3, 10), Color.ORANGE, 24)
	var two := GateLook.meter(Vector2(3, 10), Color.ORANGE, 24)
	t.check(one.material_override == two.material_override, "panels of one kind share a material")
	one.free()
	two.free()
	raid.queue_free()
	await t.frames(2)
