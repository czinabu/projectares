extends Node
## Entry point. Switches between the hub and a raid, solo or online.
##
## A stay in a world is a string of lives. Dying keeps you in the world: the
## HUD shows what it cost and Enter drops you back in with whatever your
## loadout can still supply. You return to the hub by signing out (L).
##
## Run with `-- --server [--world <id>] [--port <n>] [--bots <n>] [--squad-spawn]
## [--accounts <folder>] [--no-rewind]` for a dedicated server: no hub, no window needed,
## just a raid that players join. Player stashes are saved in the accounts
## folder (`user://accounts` unless given).

const JOIN_TIMEOUT := 12.0
const NameplatesScript := preload("res://core/ui/nameplates.gd")
const ScoreboardScript := preload("res://core/ui/scoreboard.gd")
const PhoneScript := preload("res://core/phone/phone.gd")
const GameSettings := preload("res://core/settings/game_settings.gd")
const BaseHudScript := preload("res://core/ui/base_hud.gd")

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
	var world_id := _arg(args, "--world", "")
	if Worlds.get_world(world_id) == null:
		world_id = Worlds.all()[0].id
	var port := int(_arg(args, "--port", str(NetSession.DEFAULT_PORT)))
	net = NetSession.new()
	net.name = "Net"
	net.bot_count = int(_arg(args, "--bots", "-1"))
	net.squad_spawn = "--squad-spawn" in args
	net.lag_compensation = "--no-rewind" not in args
	var accounts := _arg(args, "--accounts", "")
	if accounts != "":
		net.stash.save_dir = accounts
	add_child(net)
	var err := net.host(world_id, port)
	if err != OK:
		push_error("Server: could not listen on port %d (%s)" % [port, error_string(err)])
		get_tree().quit(1)
		return
	print("Server: running %s on port %d" % [world_id, port])


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
	hub.set_online_status("")
	hub.enter_lobby(account, Worlds.get_world(net.world_id))


func _on_online_account_changed(account: Dictionary) -> void:
	if raid == null:
		hub.update_account(account)
		_refresh_base()


func _on_online_joined(p_raid: Raid) -> void:
	raid = p_raid
	hub.visible = false
	hub.set_online_status("")
	_attach_player_view()


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
	hub.leave_lobby()
	hub.set_online_status(reason)
	# A base open on the server's stash falls back to the local one.
	_refresh_base()
	if base_hud:
		base_hud.show_notice(reason)


## The connection dropped while in the world. Your body stays there for a
## short while. If nobody kills it, what you carried goes back to your stash.
func _on_online_disconnected() -> void:
	_leave_raid()
	_stop_local_server()
	hub.leave_lobby()
	hub.refresh({})
	hub.set_online_status("Lost the connection to the server. Your body stays in the world for a moment. "
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
	_leave_raid()
	hub.update_account(account)
	hub.refresh(result)
	hub.visible = true
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
	_stop_local_server()
	hub.leave_lobby()
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
