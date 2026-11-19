extends RefCounted
## The `plaza_online` checks. The test runner finds this file by itself and calls
## `run(t)`.

const RaidRoster := preload("res://core/ui/raid_roster.gd")
const NET_ACCOUNTS := "user://test_accounts_net"


static func run(t: Node) -> void:
	print("Plaza online: a shared safe zone beside the warzone")
	const PlazaView := preload("res://core/social/plaza_view.gd")
	var port := 24861
	t._wipe_dir(NET_ACCOUNTS)
	var pid: int = t._start_server(port, ["--plaza", "--bots", "0"])
	var ada: NetSession = await t._join("Pia", port, {"primary": "rifle_carbine"})
	t.check(ada != null, "a client walks into the server's plaza")
	if ada == null:
		OS.kill(pid)
		return
	t.check(ada.world_id == "plaza" and ada.raid.world.safe_zone, "the server's front door is the plaza")
	t.check(ada.routes.get("ashfront", -1) == port + 1, "the plaza says where the warzone runs")
	await t._wait_until(func() -> bool: return ada.world_status.has("ashfront"), 240)
	var quiet: Dictionary = ada.world_status.get("ashfront", {})
	t.check(quiet.get("players", -1) == 0 and quiet.get("level", "") == "Quiet" and not ada.world_status.has("plaza"),
			"the plaza hears how the warzone is doing: %s" % PlazaView.heat_text(quiet))
	var me := ada.raid.player
	t.check("rifle_carbine" in me.gear_items and me.weapons_locked, "you wear your loadout, with weapons locked")
	await t.frames(30)
	t.check(not ada.account.deployed and "rifle_carbine" in ada.account.stash,
			"wearing gear in the plaza takes nothing out of the stash")

	var bo: NetSession = await t._join("Pax", port, {"primary": "smg_stinger"} if "smg_stinger" in ada.account.stash else {})
	t.check(bo != null, "a second player joins the plaza")
	if bo != null:
		await t._wait_until(func() -> bool: return RaidRoster.players_in(ada.raid).size() == 2, 240)
		var seen: Array[Actor] = RaidRoster.players_in(ada.raid).filter(func(a: Actor) -> bool: return a != me)
		t.check(seen.size() == 1 and seen[0].display_name == "Pax", "players see each other by name")
		if seen.size() == 1:
			var bo_seen := seen[0]
			var card := PlazaView.gear_lines(bo_seen)
			var bo_gear: Array = bo.raid.player.gear_items
			t.check(not card.is_empty() and card.all(func(line: Dictionary) -> bool: return line.id in bo_gear),
					"you can read what another player is wearing (%d pieces)" % card.size())
			# Bo walks; Ada sees it.
			var from := bo_seen.global_position
			bo.raid.player.cmd.move = Vector2(0, 1)
			await t.frames(60)
			bo.raid.player.cmd.move = Vector2.ZERO
			t.check(bo_seen.global_position.distance_to(from) > 2.0, "movement is shared (%.1f m)" % bo_seen.global_position.distance_to(from))
			# Ada aims at Bo and holds the trigger. Nothing happens.
			var aim := (bo_seen.global_position + Vector3(0, 1.1, 0) - me.get_eye_position()).normalized()
			me.cmd.yaw = atan2(-aim.x, -aim.z)
			me.cmd.aim_dir = aim
			me.cmd.primary = true
			me.cmd.primary_pressed = true
			await t.frames(60)
			me.cmd.primary = false
			var bo_me := bo.raid.player
			t.check(bo_me.health.health == bo_me.health.max_health and not bo_me.is_dead, "nobody can be shot in the plaza")
			# Aim again where Bo is now: the view of him can still settle after he stops.
			aim = (bo_seen.global_position + Vector3(0, 1.1, 0) - me.get_eye_position()).normalized()
			var looking := PlazaView.inspect_target(ada.raid, me, me.get_eye_position(), aim, 60.0, 9.0)
			t.check(looking == bo_seen, "looking at a player picks them for the gear card")
			t.check(PlazaView.gear_tag(bo_seen).begins_with(bo_seen.display_name.to_upper()) and "Kit worth" in PlazaView.gear_tag(bo_seen),
					"their gear is written on a tag over their head")

	# The contract board: taking a job is the server's call, and the answer
	# comes back in the account.
	var job: String = ada.account.get("contracts", {}).get("offers", [""])[0]
	ada.contract_ask("take", job)
	await t._wait_until(func() -> bool: return ada.account.get("contracts", {}).get("active", []).size() == 1, 240)
	t.check(job != "" and ada.account.contracts.active[0].id == job, "the plaza's contract board takes a job on the server")
	# The player market: Pia lists a medkit at the Exchange, Pax buys it.
	const Market := preload("res://core/economy/market.gd")
	var medkits: int = ada.account.stash.count("medkit")
	var price := Market.board_value("medkit")
	ada.market_ask("view")
	ada.market_ask("list", "medkit", 1, price)
	await t._wait_until(func() -> bool: return ada.market_state.get("listings", []).size() == 1, 240)
	var listing: Dictionary = ada.market_state.get("listings", [{}])[0]
	t.check(listing.get("item", "") == "medkit" and listing.get("mine", false), "the Exchange lists an item on the server")
	await t._wait_until(func() -> bool: return ada.account.stash.count("medkit") == medkits - 1, 240)
	t.check(ada.account.stash.count("medkit") == medkits - 1, "a listed item leaves the seller's stash")
	if bo != null:
		var bo_scrip := int(bo.account.get("scrip", 0))
		var bo_medkits: int = bo.account.get("stash", []).count("medkit")
		var ada_scrip := int(ada.account.get("scrip", 0))
		bo.market_ask("view")
		await t._wait_until(func() -> bool: return bo.market_state.get("listings", []).size() == 1, 240)
		var seen_listing: Dictionary = bo.market_state.get("listings", [{}])[0]
		t.check(seen_listing.get("seller", "") == "Pia" and not seen_listing.get("mine", true),
				"another player sees it, by the seller's name")
		bo.market_ask("buy", "", int(seen_listing.get("id", 0)), 1)
		await t._wait_until(func() -> bool: return bo.account.get("stash", []).count("medkit") == bo_medkits + 1 \
				and int(ada.account.get("scrip", 0)) > ada_scrip, 240)
		t.check(bo.account.stash.count("medkit") == bo_medkits + 1 and int(bo.account.scrip) == bo_scrip - price and int(ada.account.scrip) == ada_scrip + Market.seller_gets(price),
				"the buyer pays, gets the item, and the seller is paid at once (%d, %d)" % [bo.account.scrip, ada.account.scrip])
		await t._wait_until(func() -> bool: return ada.market_state.get("listings", []).is_empty(), 240)
		t.check(ada.market_state.get("listings", [1]).is_empty(), "the board updates for everyone with the kiosk open")
	# The clan hall: Pia founds a clan, Pax joins it, and both wear its tag.
	ada.clan_ask("create", "Night Shift", "ns")
	await t._wait_until(func() -> bool: return not ada.clan_state.get("clan", {}).is_empty(), 240)
	t.check(ada.clan_state.get("clan", {}).get("tag", "") == "NS" and ada.clan_state.clan.is_leader,
			"founding a clan at the hall makes you its leader")
	await t._wait_until(func() -> bool: return me.clan_tag == "NS", 240)
	t.check(me.clan_tag == "NS" and me.clan == "", "you wear the tag at once, and the plaza stays a safe zone")
	if bo != null:
		await t._wait_until(func() -> bool: return bo.clan_state.get("clans", []).size() == 1, 240)
		t.check(bo.clan_state.get("clans", []).size() == 1 and bo.clan_state.clan.is_empty(),
				"everyone in the plaza sees the new clan listed")
		bo.clan_ask("join", str(ada.clan_state.clan.id))
		await t._wait_until(func() -> bool: return ada.clan_state.clan.get("members", []).size() == 2, 240)
		t.check(ada.clan_state.clan.get("members", []) == ["Pia", "Pax"], "a second player joins it: %s" % [ada.clan_state.clan.get("members", [])])
		var pax_seen: Array[Actor] = RaidRoster.players_in(ada.raid).filter(func(a: Actor) -> bool: return a != me)
		await t._wait_until(func() -> bool: return pax_seen.size() == 1 and pax_seen[0].clan_tag == "NS", 240)
		t.check(pax_seen.size() == 1 and PlazaView.gear_tag(pax_seen[0]).begins_with("[NS] PAX"),
				"and the tag is on the card over their head")
		ada.clan_ask("create", "Second", "SEC")
		await t.frames(30)
		t.check(ada.clan_state.clan.get("tag", "") == "NS", "you cannot found a second clan while in one")
		await t._plaza_portal(ada, bo)

	# Through the gate: the same account, now in the warzone's lobby.
	var war_port: int = ada.routes.get("ashfront", -1)
	await t._leave(ada)
	if bo != null:
		await t._wait_until(func() -> bool: return RaidRoster.players_in(bo.raid).size() == 1, 240)
		t.check(RaidRoster.players_in(bo.raid).size() == 1, "a player who leaves is gone from the plaza")
		t.check(bo.containers().is_empty(), "and leaves no bag behind")
	var ada_war: NetSession = await t._sign_in("Pia", war_port)
	t.check(ada_war != null and ada_war.world_id == "ashfront", "the gate leads to the warzone on the next port")
	if ada_war != null:
		t.check(ada_war.account.loadout.get("primary", "") == "rifle_carbine" and "rifle_carbine" in ada_war.account.stash,
				"the account is the same one: loadout and stash carry over")
		ada_war.deploy()
		await t._wait_until(func() -> bool: return ada_war.raid != null and ada_war.raid.player != null, 240)
		await t._wait_until(func() -> bool: return ada_war.account.deployed, 120)
		t.check(ada_war.raid != null and not ada_war.raid.world.safe_zone and ada_war.account.deployed
				and not ada_war.raid.player.weapons_locked, "deploying there is a real raid with gear at stake")
		t.check(ada_war.clan_state.get("clan", {}).get("tag", "") == "NS" and ada_war.raid.player.clan_tag == "NS"
				and ada_war.raid.player.clan != "", "the clan follows you into the warzone, where it is your side")
		ada_war.clan_ask("leave")
		await t.frames(30)
		t.check(ada_war.clan_state.get("clan", {}).get("tag", "") == "NS", "nobody changes sides in the field")
		if bo != null:
			await t._wait_until(func() -> bool: return bo.world_status.get("ashfront", {}).get("players", 0) == 1, 600)
			t.check(bo.world_status.get("ashfront", {}).get("players", 0) == 1,
					"someone still in the plaza sees the warzone fill up")
		await t._leave(ada_war)
	await t._leave(bo)

	# The whole trip through the game's own flow.
	var main: Node = load("res://scenes/main.tscn").instantiate()
	t.add_child(main)
	await t.frames(2)
	Profile.player_name = "Quill"
	# Joined the way a player does: from the phone's Servers app.
	main.phone.open("servers")
	main.phone.join_server("127.0.0.1:%d" % port)
	t.check(not main.phone.is_open and main.base == null and main.net != null,
			"joining from the phone puts it away and heads out of the base")
	await t._wait_until(func() -> bool: return main.raid != null and main.raid.player != null, 600)
	t.check(main.raid != null and main.raid.world.safe_zone and main.plaza_view != null and not main.hub.visible,
			"joining a server puts you in its plaza")
	if main.raid != null:
		var gate: Node3D = null
		for node in t.get_tree().get_nodes_in_group("portal"):
			if main.raid.map.is_ancestor_of(node) and node.get_meta("destination", "") == "world:ashfront":
				gate = node
		t.check(gate != null and PlazaView.portal_at(main.raid, gate.global_position) == gate
				and PlazaView.portal_at(main.raid, Vector3(0, 0, 20)) == null, "standing in a gate offers the trip")
		t.check(gate != null and PlazaView.prompt_for(gate, main.net.routes).begins_with("[F]")
				and PlazaView.prompt_for(gate, {}).contains("closed"), "a gate to a world the server lacks is closed")
		var heat: Label3D = main.plaza_view.heat_signs.get("ashfront")
		await t._wait_until(func() -> bool: return heat != null and heat.visible, 240)
		t.check(heat != null and heat.visible and heat.text.begins_with("QUIET") and gate != null
				and heat.global_position.y > gate.global_position.y + 3.0,
				"the sign over the gate says how that world is doing")
		main.use_portal("clans")
		await t.frames(3)
		t.check(main.shop_view != null and main.shop_screen != null and main.shop_view.panel.has_signal("asked"),
				"the clan hall door opens its terminal")
		main.close_shop()
		await t.frames(2)
		var shops: Array = main.raid.map.shops()
		if not shops.is_empty():
			var shop_id: String = shops[0].id
			var stall: Node3D = null
			for front: Node in main.raid.get_tree().get_nodes_in_group("shop_front"):
				if front.get_meta("shop_id", "") == shop_id and main.raid.map.is_ancestor_of(front):
					stall = front
			main.raid.player.global_position = stall.global_position + Vector3(0, 0.1, 0)
			main.use_portal("shop:" + shop_id)
			await t.frames(3)
			t.check(main.shop_view != null and main.shop_view.panel.shop_filter == shop_id
					and main.controller.input_blocked and main.raid != null,
					"a storefront opens that shop's screen without leaving the plaza")
			t.check(main.shop_screen != null and main.shop_screen.get_parent() == stall.get_node("Screen")
					and main.shop_screen.focused and main.get_viewport().get_camera_3d() != main.controller.camera
					and main.hud != null and not main.hud.visible and not main.plaza_view.visible,
					"the shop comes up on the terminal on its counter and the view moves in to it")
			var panel: Control = main.shop_view.panel
			var before: int = panel.scrip()
			var stock: Array = panel.find_children("*", "Button", true, false).filter(func(b: Node) -> bool:
				return (b as Button).text.begins_with("Buy") and not (b as Button).disabled)
			t.check(not stock.is_empty() and before > 0, "the stall shows stock and your scrip on this server (%d)" % before)
			if not stock.is_empty():
				(stock[0] as Button).pressed.emit()
				await t._wait_until(func() -> bool:
					return main.shop_view != null and main.shop_view.panel.scrip() < before, 240)
				t.check(main.shop_view.panel.scrip() < before, "buying at the stall goes through the server")
			main.close_shop()
			await t.frames(2)
			t.check(main.shop_view == null and main.shop_screen == null and not main.controller.input_blocked
					and main.get_viewport().get_camera_3d() == main.controller.camera and main.hud.visible,
					"stepping away gives control, the view and the HUD back")
		main.use_portal("world:ashfront")
		await t._wait_until(func() -> bool:
			return main.raid != null and main.raid.player != null and main.raid.world.id == "ashfront", 600)
		t.check(main.raid != null and main.raid.world.id == "ashfront" and main.base == null and not main.hub.visible
				and main.net != null and main.net.world_id == "ashfront",
				"using a gate deploys you straight into that world, not into a lobby")
		# Back by signing out: a body left standing would be yours again on
		# the next sign-in to this world (a reconnect), so it must come home.
		main.net.sign_out()
		await t._wait_until(func() -> bool: return main.raid != null and main.raid.player != null and main.raid.world.safe_zone,
				int(Worlds.get_world("ashfront").sign_out_time * 60.0) + 600)
		t.check(main.raid != null and main.raid.world.safe_zone, "leaving the world leads back to the plaza")
		if main.raid != null and main.raid.player != null:
			var back_gate: Node3D = null
			for node in t.get_tree().get_nodes_in_group("portal"):
				if main.raid.map.is_ancestor_of(node) and node.get_meta("destination", "") == "world:ashfront":
					back_gate = node
			var off: Vector3 = main.raid.player.global_position - back_gate.global_position
			t.check(Vector2(off.x, off.z).length() < float(back_gate.get_meta("radius", 2.0)) + 4.0,
					"and you arrive in front of that world's gate (%.1f m)" % Vector2(off.x, off.z).length())
		main.use_portal("home")
		await t._wait_until(func() -> bool: return main.base != null, 600)
		t.check(main.base != null and main.raid == null and main.hub.in_lobby(),
				"the quarters door opens your home base on the server's stash")
		t.check(main.base != null and main.base.door.get_prompt().contains("Back to"),
				"the base's door leads back to the plaza")
		# Out the way the door goes, through a squad portal to the plaza.
		t.check(Portal.PLAZA in main.controller.portal_choices(), "the watch offers a portal to the plaza too")
		main.go_through_portal(Portal.PLAZA)
		await t._wait_until(func() -> bool: return main.raid != null and main.raid.player != null, 600)
		t.check(main.base == null and main.raid != null and main.raid.world.safe_zone,
				"a portal to the plaza leads back to the plaza")
		main.use_portal("leave")
		await t.frames(5)
		t.check(main.net == null and main.raid == null and main.base != null and not main.hub.in_lobby(),
				"the exit leaves the server and takes you home")
		t.check(Profile.home_server == "127.0.0.1:%d" % port, "the door remembers the server you joined from the phone")
		# Straight out of the door: no screen, back in that server's plaza.
		main.base.leave_requested.emit()
		t.check(main.hub.station == "" and main.station_screen == null, "the door opens no screen")
		await t._wait_until(func() -> bool: return main.raid != null and main.raid.player != null, 600)
		t.check(main.raid != null and main.raid.world.safe_zone and main.net != null and main._server_pid <= 0,
				"the door of your own base leads straight to the plaza of the server it remembers")
		main.phone.open("servers")
		await t.frames(1)
		t.check(main.phone._body.find_children("*", "Label", true, false).any(
				func(label: Label) -> bool: return label.text == "Connected as Quill"),
				"online, the phone's Servers app says who you are on the server")
		main.phone.leave_server()
		await t.frames(5)
		t.check(main.net == null and main.raid == null and main.base != null and not main.hub.in_lobby()
				and not main.phone.is_open, "the phone's Servers app leaves the server and takes you home")
	OS.kill(pid)
	await t.frames(30)
	# The remembered server is gone: the door starts a server of your own,
	# with every world behind the plaza's gates.
	main.host_port = port + 20
	main.host_args = PackedStringArray(["--accounts", NET_ACCOUNTS, "--bots", "0"])
	if main.base != null:
		main.base.leave_requested.emit()
		await t._wait_until(func() -> bool: return main.raid != null and main.raid.player != null, 3600)
		t.check(main.raid != null and main.raid.world.safe_zone and main._server_pid > 0,
				"with that server gone the door starts one of your own and walks you into its plaza")
		var open_gates := 0
		for world in Worlds.raid_worlds():
			open_gates += 1 if main.net != null and main.net.routes.has(world.id) else 0
		t.check(open_gates == Worlds.raid_worlds().size() and open_gates > 0,
				"a server of your own runs every world, so the gates are where you choose (%d open)" % open_gates)
		t.check(Profile.home_server == "127.0.0.1:%d" % port, "the door still remembers the server it could not reach")
		if main.raid != null:
			main.use_portal("leave")
			await t.frames(5)
		t.check(main._server_pid <= 0 and main.base != null, "leaving stops your own server and takes you home")
	Profile.home_server = ""
	main._stop_local_server()
	main.queue_free()
	await t.frames(30)
