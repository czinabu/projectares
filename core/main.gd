extends Node
## Entry point. Switches between the hub and a raid, solo or online.
##
## A stay in a world is a string of lives. Dying keeps you in the world: the
## HUD shows what it cost and Enter drops you back in with whatever your
## loadout can still supply. You return to the hub by signing out (L).
##
## Run with `-- --server [--world <id>] [--port <n>] [--bots <n>] [--squad-spawn]
## [--accounts <folder>] [--no-rewind] [--no-plaza]` for a dedicated server: no hub, no
## window needed. It runs the plaza (the social safe zone) on the port, and
## each raid world on the ports after it; `--world` runs just that one world,
## and `--no-plaza` runs it alone on the port. Player stashes are saved in the
## accounts folder (`user://accounts` unless given) and shared by all of them.

const JOIN_TIMEOUT := 12.0
const NameplatesScript := preload("res://core/ui/nameplates.gd")
const ScoreboardScript := preload("res://core/ui/scoreboard.gd")
const PhoneScript := preload("res://core/phone/phone.gd")
const GameSettings := preload("res://core/settings/game_settings.gd")
const BaseHudScript := preload("res://core/ui/base_hud.gd")
const PlazaViewScript := preload("res://core/social/plaza_view.gd")
## The plaza holds more people than a raid.
const PLAZA_PLAYERS := 32
const SHOP_PANEL := "res://core/economy/shop_panel.gd"

var hub: Hub
var raid: Raid
var controller: PlayerController
var hud: Hud
var nameplates: CanvasLayer
var scoreboard: CanvasLayer
var net: NetSession
## The phone every player carries: the game's menu, in the hub and in a raid.
var phone: CanvasLayer
## The home base while the player is walking around it, else null.
var base: HomeBase
var base_hud: CanvasLayer
var plaza_view: CanvasLayer
## The shop screen while trading at a plaza storefront, else null.
var shop_view: ShopView
## Server: every session it runs (the plaza first, then the raid worlds).
var sessions: Array[NetSession] = []
## Client: where this server's plaza is, once you have been in it. Leaving a
## world's lobby or finishing a run leads back there. Port -1 means no plaza.
var _plaza_address := ""
var _plaza_port := -1
## Client: on the way from the plaza to the home base, or in it.
var _base_from_plaza := false
var _server_pid := -1
var _join_attempts := 0
var _join_address := ""
var _join_port := NetSession.DEFAULT_PORT
## The local player's last life, while they are down.
var _death_result := {}
## Time.get_ticks_msec() from which a dead player may drop back in.
var _redeploy_at := 0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if "--server" in args:
		_run_dedicated_server(args)
		return
	hub = Hub.new()
	add_child(hub)
	hub.deploy_requested.connect(start_raid)
	hub.host_requested.connect(host_and_join)
	hub.join_requested.connect(join_online)
	hub.online_equip_requested.connect(func(slot: String, item_id: String) -> void:
		if net:
			net.equip(slot, item_id))
	hub.online_pick_requested.connect(func(track: String, variant_id: String) -> void:
		if net:
			net.pick_mastery(track, variant_id))
	hub.online_deploy_requested.connect(func() -> void:
		if net and raid == null:
			hub.set_online_status("Deploying...")
			net.deploy())
	hub.online_leave_requested.connect(leave_server)
	_setup_phone()
	hub.base_requested.connect(enter_base)
	hub.look_changed.connect(func(appearance: Dictionary) -> void:
		Profile.set_appearance(appearance)
		if net != null:
			net.send_look(Profile.appearance))


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		_stop_local_server()


# ------------------------------------------------------------- home base ----

## Leaves the hub screen for the home base, which shows the stash the hub
## was showing: the local profile's, or the server's while in a lobby.
func enter_base() -> void:
	_open_base(hub.stash_items(), hub.current_loadout(), "")


## Opens someone else's base to look around. Nothing in it can be equipped.
## `stash` and `loadout` are that player's, as their server reports them.
func visit_base(owner_name: String, stash: Array, loadout: Dictionary) -> void:
	_open_base(stash, loadout, owner_name if owner_name != "" else "Raider")


func _open_base(stash: Array, loadout: Dictionary, owner_name: String) -> void:
	if base != null or raid != null:
		return
	hub.visible = false
	base = HomeBase.new()
	base.name = "HomeBase"
	base.owner_name = owner_name
	base.read_only = owner_name != ""
	base.show_gear(stash, loadout)
	add_child(base)
	base.equip_requested.connect(_on_base_equip)
	base.leave_requested.connect(leave_base)
	Look.set_appearance(base.player, Profile.appearance)
	controller = PlayerController.new()
	controller.setup(base.player)
	base.add_child(controller)
	base_hud = BaseHudScript.new()
	base_hud.name = "BaseHud"
	base_hud.setup(base)
	base.add_child(base_hud)
	_apply_settings()


func leave_base() -> void:
	if base == null:
		return
	base.queue_free()
	base = null
	base_hud = null
	controller = null
	hub.refresh_gear()
	hub.visible = true
	if _base_from_plaza:
		# They came in through the plaza's door, so that is where they go back.
		_base_from_plaza = false
		leave_server()


## Gear used in the base changes the loadout the same way the hub's pickers
## do: straight into the profile solo, as a request to the server online.
func _on_base_equip(slot: String, item_id: String) -> void:
	if hub.in_lobby():
		if net:
			net.equip(slot, item_id)
		return
	if item_id == "":
		Profile.unequip(slot)
	else:
		Profile.equip(slot, item_id)
	_refresh_base()


## Shows the base whatever the hub would show now.
func _refresh_base() -> void:
	if base and not base.read_only:
		base.show_gear(hub.stash_items(), hub.current_loadout())


# ------------------------------------------------------------------ solo ----

func start_raid(world_id: String) -> void:
	var world := Worlds.get_world(world_id)
	if world == null or raid != null or net != null or base != null:
		return
	hub.visible = false
	raid = Raid.new()
	raid.name = "Raid"
	add_child(raid)
	raid.start(world, -1, Profile.checkout_loadout(world), Profile.mastery.active_picks())
	_attach_player_view()
	raid.player_finished.connect(_on_solo_finished)


## Gives the local player's current actor a camera, controls and a HUD. Called
## again every time they drop back in, because each life is a new actor.
func _attach_player_view() -> void:
	_death_result = {}
	for old: Node in [controller, hud]:
		if old != null and is_instance_valid(old):
			old.get_parent().remove_child(old)
			old.queue_free()
	if net == null:
		# Solo: every new life wears the chosen look. Online the server sends it.
		Look.set_appearance(raid.player, Profile.appearance)
	controller = PlayerController.new()
	controller.setup(raid.player)
	controller.sign_out_requested.connect(func() -> void: _on_sign_out_requested.call_deferred())
	controller.redeploy_requested.connect(func() -> void: _on_redeploy_requested.call_deferred())
	raid.add_child(controller)
	hud = Hud.new()
	hud.setup(raid, controller)
	raid.add_child(hud)
	if nameplates != null and is_instance_valid(nameplates):
		# The same world, a new life: they only need to know who you are now.
		nameplates.viewer = raid.player
		scoreboard.roster.set_me(raid.player)
		return
	nameplates = NameplatesScript.new()
	nameplates.name = "Nameplates"
	nameplates.setup(raid)
	raid.add_child(nameplates)
	scoreboard = ScoreboardScript.new()
	scoreboard.name = "Scoreboard"
	scoreboard.setup(raid)
	raid.add_child(scoreboard)
	_apply_settings()
	if phone != null and phone.is_open:
		phone.close()


## One solo life ended. A death keeps you in the world; leaving goes home.
func _on_solo_finished(_actor: Actor, result: Dictionary) -> void:
	if result.get("outcome", "") == "died":
		_show_death(result)
		return
	# Leave a beat so the player sees what happened before the hub appears.
	await get_tree().create_timer(1.0).timeout
	_show_hub(result)


func _show_death(result: Dictionary) -> void:
	_death_result = result
	_redeploy_at = Time.get_ticks_msec() + int(raid.world.redeploy_delay * 1000.0)
	if hud != null and is_instance_valid(hud):
		hud.show_death(result, raid.world.redeploy_delay)


func _is_down() -> bool:
	return raid != null and not _death_result.is_empty()


## Enter, while down: drop back into the same world.
func _on_redeploy_requested() -> void:
	if not _is_down() or Time.get_ticks_msec() < _redeploy_at:
		return
	if net:
		# `joined` follows and attaches the view to the new actor.
		net.deploy()
		return
	raid.add_player(Profile.checkout_loadout(raid.world), Profile.mastery.active_picks(), "You")
	_attach_player_view()


## L: alive, start or cancel a sign-out. Down, go back to the hub.
func _on_sign_out_requested() -> void:
	if raid == null or raid.player == null or not is_instance_valid(raid.player):
		return
	if _is_down():
		if net:
			_return_to_lobby(_death_result)
		else:
			_show_hub(_death_result)
		return
	var signing_out := raid.sign_out_progress(raid.player) >= 0.0
	if net:
		net.sign_out(not signing_out)
	elif signing_out:
		raid.cancel_sign_out(raid.player)
	else:
		raid.begin_sign_out(raid.player)


func _show_hub(result: Dictionary) -> void:
	_leave_raid()
	hub.refresh(result)
	hub.visible = true


func _leave_raid() -> void:
	_death_result = {}
	controller = null
	hud = null
	nameplates = null
	scoreboard = null
	if net:
		net.queue_free()
		net = null
		raid = null
	elif raid:
		raid.queue_free()
		raid = null


# ----------------------------------------------------------------- phone ----

func _setup_phone() -> void:
	GameSettings.ensure_loaded()
	phone = PhoneScript.new()
	phone.name = "Phone"
	add_child(phone)
	hub.phone_requested.connect(func() -> void: phone.open())
	phone.opened_changed.connect(_on_phone_opened)
	phone.settings_changed.connect(_apply_settings)
	phone.quit_requested.connect(func() -> void: get_tree().quit())


## Hands on the phone: the character stops and the mouse is free. Putting it
## away in a raid takes the mouse back.
func _on_phone_opened(open: bool) -> void:
	if controller != null and is_instance_valid(controller):
		controller.input_blocked = open
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if open else Input.MOUSE_MODE_CAPTURED


## Pushes the phone's settings into the raid view, if there is one.
func _apply_settings() -> void:
	if controller != null and is_instance_valid(controller):
		controller.mouse_sensitivity = GameSettings.mouse_sensitivity
		controller.invert_y = GameSettings.invert_y
		controller.base_fov = GameSettings.field_of_view
		controller.stance_control = PlayerController.StanceControl.MOVE if Profile.melee_control == "move" \
				else PlayerController.StanceControl.MOUSE
	if nameplates != null and is_instance_valid(nameplates):
		nameplates.visible = GameSettings.show_nameplates


## Accepted an invite to this server's raid: deploy from the lobby.
func _on_world_invite_accepted(_invite: Dictionary) -> void:
	if net == null or raid != null:
		phone.show_notice("Finish this run first, then deploy from the lobby.")
		return
	phone.close()
	hub.set_online_status("Deploying...")
	net.deploy()


## Accepted an invite to someone's home base.
func _on_base_visit_requested(owner_name: String, owner_stash: Array, owner_loadout: Dictionary) -> void:
	if raid != null:
		phone.show_notice("Finish this run first, then visit %s's base." % owner_name)
		return
	# Already in a base (yours or someone else's): walk out and into theirs.
	leave_base()
	phone.close()
	visit_base(owner_name, owner_stash, owner_loadout)


# ---------------------------------------------------------------- online ----

func _run_dedicated_server(args: PackedStringArray) -> void:
	var port := int(_arg(args, "--port", str(NetSession.DEFAULT_PORT)))
	var err := start_server(_arg(args, "--world", ""), port, "--no-plaza" not in args,
			int(_arg(args, "--bots", "-1")), "--squad-spawn" in args, _arg(args, "--accounts", ""),
			"--no-rewind" not in args)
	if err != OK:
		push_error("Server: could not listen from port %d (%s)" % [port, error_string(err)])
		get_tree().quit(1)


## Starts every session of a server. With a plaza it listens on `port`, and
## the raid worlds follow on the next ports; without one, a single world runs
## on `port`. `world_id` "" runs every raid world (the first one only when
## there is no plaza to reach the others from). All sessions share one stash
## service, so an account is the same wherever it shows up.
func start_server(world_id: String, port: int, with_plaza := true, bots := -1, squad := false,
		accounts := "", rewind := true) -> Error:
	var plaza := Worlds.social_world() if with_plaza else null
	var worlds: Array[WorldDef] = []
	if Worlds.get_world(world_id) != null and not Worlds.get_world(world_id).safe_zone:
		worlds.append(Worlds.get_world(world_id))
	elif plaza != null:
		worlds = Worlds.raid_worlds()
	else:
		worlds.append(Worlds.raid_worlds()[0])
	var routes := {}
	var next_port := port + 1 if plaza != null else port
	for world in worlds:
		var session := NetSession.new()
		session.name = "Net" if sessions.is_empty() else "Net_%s" % world.id
		session.bot_count = bots
		session.squad_spawn = squad
		session.lag_compensation = rewind
		session.isolated = plaza != null or worlds.size() > 1
		if sessions.is_empty():
			if accounts != "":
				session.stash.save_dir = accounts
		else:
			session.stash = sessions[0].stash
			session.social = sessions[0].social
		add_child(session)
		var err := session.host(world.id, next_port)
		if err != OK:
			return err
		print("Server: running %s on port %d" % [world.id, next_port])
		routes[world.id] = next_port
		sessions.append(session)
		next_port += 1
	net = sessions[0]
	if plaza != null:
		var session := NetSession.new()
		session.name = "Net_%s" % plaza.id
		session.isolated = true
		session.stash = net.stash
		session.social = net.social
		session.routes = routes
		add_child(session)
		var err := session.host(plaza.id, port, PLAZA_PLAYERS)
		if err != OK:
			return err
		print("Server: running %s on port %d" % [plaza.id, port])
		sessions.push_front(session)
	return OK


## Starts a server on this machine as a second process, then joins it.
func host_and_join(world_id: String) -> void:
	if raid != null or net != null:
		return
	_stop_local_server()
	var args := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"),
			"--", "--server", "--world", world_id])
	_server_pid = OS.create_process(OS.get_executable_path(), args)
	if _server_pid <= 0:
		hub.set_online_status("Could not start a server on this computer.")
		return
	hub.set_online_status("Starting a server...")
	_begin_join("127.0.0.1", NetSession.DEFAULT_PORT, 8)


## `address` is "host" or "host:port".
func join_online(address: String) -> void:
	if raid != null or net != null:
		return
	var host := address.strip_edges()
	var port := NetSession.DEFAULT_PORT
	if ":" in host:
		port = int(host.get_slice(":", 1))
		host = host.get_slice(":", 0)
	if host == "":
		hub.set_online_status("Type the server's address first.")
		return
	hub.set_online_status("Connecting to %s..." % host)
	_begin_join(host, port, 1)


func _begin_join(host: String, port: int, attempts: int) -> void:
	_join_address = host
	_join_port = port
	_join_attempts = attempts
	_try_join()


func _try_join() -> void:
	_join_attempts -= 1
	net = NetSession.new()
	net.name = "Net"
	net.player_name = Profile.player_name
	net.secret = Profile.get_online_secret()
	net.look = Profile.appearance
	# `-- --lag 120 --loss 10` fakes a bad connection: milliseconds of delay
	# each way, and the percent of input packets lost.
	var args := OS.get_cmdline_user_args()
	net.simulated_lag = float(_arg(args, "--lag", "0")) / 1000.0
	net.simulated_loss = float(_arg(args, "--loss", "0")) / 100.0
	add_child(net)
	net.signed_in.connect(_on_online_signed_in)
	net.account_changed.connect(_on_online_account_changed)
	net.lobby_error.connect(func(reason: String) -> void:
		hub.set_online_status(reason)
		if base_hud:
			base_hud.show_notice(reason)
		if raid != null and hud != null and is_instance_valid(hud):
			hud.notify(reason))
	net.joined.connect(_on_online_joined)
	net.failed.connect(_on_online_failed)
	net.disconnected.connect(_on_online_disconnected)
	net.run_finished.connect(_on_online_finished)
	net.world_invite_accepted.connect(_on_world_invite_accepted)
	net.base_visit_requested.connect(_on_base_visit_requested)
	phone.set_session(net)
	var err := net.join(_join_address, _join_port)
	if err != OK:
		_on_online_failed("Could not open a connection (%s)." % error_string(err))
		return
	# A server that never answers should not leave the hub waiting forever.
	var session := net
	get_tree().create_timer(JOIN_TIMEOUT).timeout.connect(func() -> void:
		if net == session and net.account.is_empty():
			_on_online_failed("The server did not answer."))


## Signed in: the hub becomes that server's lobby.
func _on_online_signed_in(account: Dictionary) -> void:
	_join_attempts = 0
	var world := Worlds.get_world(net.world_id)
	if world.safe_zone:
		# The server's front door is its plaza: walk straight in.
		_plaza_address = _join_address
		_plaza_port = _join_port
		hub.set_online_status("Entering %s..." % world.display_name)
		net.deploy()
		return
	hub.set_online_status("")
	hub.enter_lobby(account, world)
	hub.set_leave_text("Back to %s" % Worlds.social_world().display_name if _plaza_port >= 0 else "Leave the server")
	if _base_from_plaza:
		enter_base()


func _on_online_account_changed(account: Dictionary) -> void:
	if shop_view != null and is_instance_valid(shop_view):
		shop_view.panel.set("account", account)
		shop_view.panel.call("refresh")
	if raid == null:
		hub.update_account(account)
		_refresh_base()


func _on_online_joined(p_raid: Raid) -> void:
	raid = p_raid
	hub.visible = false
	hub.set_online_status("")
	_attach_player_view()
	if raid.world.safe_zone:
		plaza_view = PlazaViewScript.new()
		plaza_view.name = "PlazaView"
		plaza_view.setup(raid, net.routes)
		raid.add_child(plaza_view)
		plaza_view.portal_used.connect(use_portal)


## A player in the plaza stepped into a portal and asked to go.
func use_portal(destination: String) -> void:
	if net == null or raid == null or not raid.world.safe_zone:
		return
	if destination.begins_with("world:"):
		var world := Worlds.get_world(destination.trim_prefix("world:"))
		var port: int = net.routes.get(destination.trim_prefix("world:"), -1)
		if world == null or port < 0:
			plaza_view.show_notice("That world is not running on this server.")
			return
		_leave_raid()
		hub.visible = true
		hub.set_online_status("Travelling to %s..." % world.display_name)
		_begin_join(_plaza_address, port, 3)
	elif destination.begins_with("shop:"):
		open_shop(destination.trim_prefix("shop:"))
	elif destination == "home":
		open_home_base()
		return
	elif destination == "leave":
		_leave_raid()
		hub.visible = true
		leave_server()
	else:
		plaza_view.show_notice("Opening soon.")


## A storefront in the plaza: the shop screen for that one shop, trading with
## the stash this server keeps for you. The shop screen belongs to the
## economy and is loaded by path, so a game without one just says so.
func open_shop(shop_id: String) -> void:
	if net == null or raid == null or shop_view != null:
		return
	if not ResourceLoader.exists(SHOP_PANEL):
		plaza_view.show_notice("Opening soon.")
		return
	var panel: Control = (load(SHOP_PANEL) as Script).new()
	panel.set("shop_filter", shop_id)
	panel.set("account", net.account)
	panel.connect("buy_requested", func(shop: String, item_id: String) -> void:
		if net:
			net.buy(shop, item_id))
	panel.connect("sell_requested", func(item_id: String, count: int) -> void:
		if net:
			net.sell(item_id, count))
	shop_view = ShopView.new()
	shop_view.name = "ShopView"
	shop_view.panel = panel
	shop_view.closed.connect(close_shop)
	# Nothing changes here until the server answers; a refusal says why.
	net.lobby_error.connect(func(reason: String) -> void:
		if shop_view != null and is_instance_valid(shop_view) and shop_view.panel.has_method("show_message"):
			shop_view.panel.call("show_message", reason))
	raid.add_child(shop_view)
	if controller != null and is_instance_valid(controller):
		controller.input_blocked = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close_shop() -> void:
	if shop_view == null:
		return
	if is_instance_valid(shop_view):
		shop_view.queue_free()
	shop_view = null
	if controller != null and is_instance_valid(controller) and raid != null:
		controller.input_blocked = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## The plaza's door to your home base. The base shows the stash this server
## keeps for you, which a world's lobby has at hand, so the trip goes by way
## of the first world's lobby; the base's own door leads back to the plaza.
func open_home_base() -> void:
	if net == null or raid == null or net.routes.is_empty():
		return
	var port: int = net.routes.values()[0]
	_leave_raid()
	hub.visible = true
	hub.set_online_status("Going home...")
	_base_from_plaza = true
	_begin_join(_plaza_address, port, 3)


## Could not connect or sign in, or the connection dropped in the lobby.
func _on_online_failed(reason: String) -> void:
	if net:
		if net.refused:
			_join_attempts = 0
		net.queue_free()
		net = null
	if _join_attempts > 0:
		# A server we just started needs a moment before it listens.
		await get_tree().create_timer(1.0).timeout
		if net == null and raid == null:
			_try_join()
		return
	_stop_local_server()
	_plaza_port = -1
	_base_from_plaza = false
	hub.leave_lobby()
	hub.set_online_status(reason)
	# A base open on the server's stash falls back to the local one.
	_refresh_base()
	if base_hud:
		base_hud.show_notice(reason)


## The connection dropped while in the world. Your body stays there for a
## short while. If nobody kills it, what you carried goes back to your stash.
func _on_online_disconnected() -> void:
	var was_safe := raid != null and raid.world.safe_zone
	_leave_raid()
	_stop_local_server()
	_plaza_port = -1
	hub.leave_lobby()
	hub.refresh({})
	hub.set_online_status("Lost the connection to the server." if was_safe
			else "Lost the connection to the server. Your body stays in the world for a moment. "
			+ "If it survives, what you carried goes back to your stash there.")
	hub.visible = true


## One online life ended. The server has already settled it into your account
## there, and nothing is written to the local profile. A death keeps you in
## the world; a finished sign-out goes back to the lobby.
func _on_online_finished(result: Dictionary) -> void:
	if result.get("outcome", "") == "died":
		_show_death(result)
		return
	await get_tree().create_timer(1.0).timeout
	_return_to_lobby(result)


func _return_to_lobby(result: Dictionary) -> void:
	if net == null:
		return
	var account := net.account
	var was_safe := raid != null and raid.world.safe_zone
	_leave_raid()
	hub.update_account(account)
	hub.refresh(result)
	hub.visible = true
	if was_safe:
		# Signing out of the plaza itself leaves the server.
		leave_server()
		return
	# Back to the plaza if the server has one, else to the lobby.
	if _plaza_port >= 0:
		hub.set_online_status("Returning to %s..." % Worlds.social_world().display_name)
		_begin_join(_plaza_address, _plaza_port, 3)
		return
	hub.set_online_status("Returning to the lobby...")
	_begin_join(_join_address, _join_port, 3)


## Disconnects from the lobby and shows the solo hub again.
func leave_server() -> void:
	if raid != null:
		return
	_join_attempts = 0
	if net:
		net.queue_free()
		net = null
	hub.leave_lobby()
	if _plaza_port >= 0 and _join_port != _plaza_port:
		# Leaving a world's lobby leads back to the plaza, not off the server.
		hub.set_online_status("Returning to %s..." % Worlds.social_world().display_name)
		_begin_join(_plaza_address, _plaza_port, 3)
		return
	_plaza_port = -1
	_stop_local_server()
	hub.set_online_status("")


func _stop_local_server() -> void:
	if _server_pid > 0:
		OS.kill(_server_pid)
		_server_pid = -1


static func _arg(args: PackedStringArray, flag: String, fallback: String) -> String:
	var index := args.find(flag)
	if index >= 0 and index + 1 < args.size():
		return args[index + 1]
	return fallback


## The frame round the shop screen at a storefront: a dimmed plaza behind, the
## panel in the middle, and a way out (the button or Esc).
class ShopView:
	extends CanvasLayer

	signal closed

	var panel: Control

	func _ready() -> void:
		layer = 5
		var shade := ColorRect.new()
		shade.color = Color(0, 0, 0, 0.55)
		shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(shade)
		var frame := PanelContainer.new()
		frame.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		frame.custom_minimum_size = Vector2(760, 560)
		frame.offset_left = -380
		frame.offset_right = 380
		frame.offset_top = -280
		frame.offset_bottom = 280
		add_child(frame)
		var margin := MarginContainer.new()
		for side: String in ["left", "right", "top", "bottom"]:
			margin.add_theme_constant_override("margin_" + side, 18)
		frame.add_child(margin)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 10)
		margin.add_child(box)
		var scroll := ScrollContainer.new()
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		box.add_child(scroll)
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(panel)
		var leave := Button.new()
		leave.text = "Step away  (Esc)"
		leave.pressed.connect(func() -> void: closed.emit())
		box.add_child(leave)

	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			closed.emit()
