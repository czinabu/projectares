extends Node
## Entry point. Switches between your home base, the plaza and a raid, solo
## or online.
##
## The game opens in your home base, never on a menu screen. Its stations open
## what the menu used to hold (`Hub`): loadout, mastery, wardrobe, records,
## trader, the launch pad that deploys and the uplink that goes online.
## Joining a server puts you in its plaza; a world's lobby on that server is
## your home base again, showing the stash that server keeps for you.
##
## A stay in a world is a string of lives. Dying keeps you in the world: the
## HUD shows what it cost and Enter drops you back in with whatever your
## loadout can still supply. You go home by signing out (L).
##
## Run with `-- --server [--world <id>] [--port <n>] [--bots <n>] [--squad-spawn]
## [--accounts <folder>] [--no-rewind] [--no-plaza]` for a dedicated server: no hub, no
## window needed. It runs the plaza (the social safe zone) on the port, and
## each raid world on the ports after it; `--world` runs just that one world,
## and `--no-plaza` runs it alone on the port. Player stashes are saved in the
## accounts folder (`user://accounts` unless given) and shared by all of them.
## The arena runs too, on `--arena-port` (the port plus `ARENA_PORT_OFFSET`
## unless given); `--no-arena` leaves it out.

const JOIN_TIMEOUT := 12.0
## The solo player's renown key in a raid, so it carries across their lives.
const LOCAL_OWNER := "local"
const StashRules := preload("res://core/account/stash_rules.gd")
const NameplatesScript := preload("res://core/ui/nameplates.gd")
const ScoreboardScript := preload("res://core/ui/scoreboard.gd")
const PhoneScript := preload("res://core/phone/phone.gd")
const MirrorScript := preload("res://core/visual/mirror.gd")
const GameSettings := preload("res://core/settings/game_settings.gd")
const BaseHudScript := preload("res://core/ui/base_hud.gd")
const ArenaHudScript := preload("res://core/arena/arena_hud.gd")
## The arena listens this many ports above the raid server.
const ARENA_PORT_OFFSET := 10
const PlazaViewScript := preload("res://core/social/plaza_view.gd")
const ClanPanel := preload("res://core/social/clan_panel.gd")
## The plaza holds more people than a raid.
const PLAZA_PLAYERS := 32
const SHOP_PANEL := "res://core/economy/shop_panel.gd"
const Economy := preload("res://core/economy/economy.gd")
## DEV MODE: temporary, see `core/dev/dev_mode.gd`.
const DevMode := preload("res://core/dev/dev_mode.gd")
## DEV MODE: where a dev server keeps its accounts, apart from real ones.
const DEV_ACCOUNTS := "user://accounts_dev"

var hub: Hub
## The 2D viewport the hub lives in. Its picture goes on the screen of the
## station you are using (`_station_screen`), or fills the window while
## travelling between places (`_travel`).
var hub_screen: SubViewport
## The live screen on the station in use, else null.
var station_screen: WorldScreen
var _travel: CanvasLayer
var raid: Raid
var controller: PlayerController
var hud: Hud
var nameplates: CanvasLayer
var scoreboard: CanvasLayer
var net: NetSession
## The phone every player carries: the game's menu, in the hub and in a raid.
var phone: CanvasLayer
## The mirror standing in front of the player while the phone's Mirror app is
## up, else null.
var mirror: Node3D
## The home base while the player is walking around it, else null.
var base: HomeBase
var base_hud: CanvasLayer
var plaza_view: CanvasLayer
## The shop screen while trading at a plaza storefront, else null.
var shop_view: ShopView
## The storefront terminal's live screen showing `shop_view`, else null.
var shop_screen: WorldScreen
var _shop_viewport: SubViewport
## Server: every session it runs (the plaza first, then the raid worlds).
var sessions: Array[NetSession] = []
## Client: where this server's plaza is, once you have been in it. Leaving a
## world's lobby or finishing a run leads back there. Port -1 means no plaza.
var _plaza_address := ""
var _plaza_port := -1
var _server_pid := -1
var _join_attempts := 0
var _join_address := ""
var _join_port := NetSession.DEFAULT_PORT
## Online: the raid lobby's port, while visiting that server's arena.
var _lobby_port := -1
## The local player's last life, while they are down.
var _death_result := {}
## Time.get_ticks_msec() from which a dead player may drop back in.
var _redeploy_at := 0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if "--server" in args:
		_run_dedicated_server(args)
		return
	hub_screen = SubViewport.new()
	hub_screen.name = "HubScreen"
	hub_screen.size = Vector2i(1280, 720)
	hub_screen.disable_3d = true
	hub_screen.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(hub_screen)
	hub = Hub.new()
	hub.name = "Hub"
	hub_screen.add_child(hub)
	_travel = CanvasLayer.new()
	_travel.name = "Travel"
	var picture := TextureRect.new()
	picture.texture = hub_screen.get_texture()
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_travel.add_child(picture)
	_travel.visible = false
	add_child(_travel)
	hub.closed.connect(_on_station_closed)
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
	hub.online_buy_requested.connect(func(shop_id: String, item_id: String) -> void:
		if net:
			net.buy(shop_id, item_id))
	hub.online_sell_requested.connect(func(item_id: String, count: int) -> void:
		if net:
			net.sell(item_id, count))
	hub.online_leave_requested.connect(leave_server)
	_setup_phone()
	hub.look_changed.connect(func(appearance: Dictionary) -> void:
		Profile.set_appearance(appearance, hub.character.owned)
		_wear_look()
		if net != null:
			net.send_look(Profile.appearance))
	# The game opens in the world: your home base.
	go_home()


## Between places the hub's travel screen fills the window; anywhere else it
## is only ever seen on a station's screen.
func _process(_delta: float) -> void:
	if _travel != null:
		_travel.visible = hub.visible and hub.station == ""


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		_stop_local_server()


# ------------------------------------------------------------- home base ----

## Takes you home: your own base, showing the stash the hub keeps on show
## (the local profile's, or the server's while in a lobby). Already there, it
## just shows the gear again. `result` is how the last life ended, if any.
func go_home(result := {}) -> void:
	if raid != null:
		return
	# DEV MODE: refill the dev stash after a run (or swap saves if it changed).
	Profile.apply_dev_mode()
	hub.close()
	if base != null and base.read_only:
		leave_base()
	if base == null:
		_open_base(hub.stash_items(), hub.current_loadout(), "")
	else:
		_refresh_base()
	_update_door()
	if not result.is_empty() and base_hud and hub.result_text() != "":
		base_hud.show_notice(hub.result_text(), 8.0)


## Opens your own base. Kept for callers that want the base by name.
func enter_base() -> void:
	go_home()


## Opens someone else's base to look around. Nothing in it can be equipped.
## `stash` and `loadout` are that player's, as their server reports them.
func visit_base(owner_name: String, stash: Array, loadout: Dictionary) -> void:
	_open_base(stash, loadout, owner_name if owner_name != "" else "Raider")
	_update_door()


func _open_base(stash: Array, loadout: Dictionary, owner_name: String) -> void:
	if base != null or raid != null:
		return
	hub.close()
	base = HomeBase.new()
	base.name = "HomeBase"
	base.owner_name = owner_name
	base.read_only = owner_name != ""
	base.show_gear(stash, loadout)
	add_child(base)
	base.equip_requested.connect(_on_base_equip)
	base.leave_requested.connect(_on_base_door)
	base.station_requested.connect(open_station)
	Look.set_appearance(base.player, _my_look())
	controller = PlayerController.new()
	controller.phone_out = phone != null and phone.is_open
	if phone != null:
		phone.set_holder(controller.actor)
	controller.setup(base.player)
	base.add_child(controller)
	base_hud = BaseHudScript.new()
	base_hud.name = "BaseHud"
	base_hud.setup(base)
	base.add_child(base_hud)
	_apply_settings()


## Closes the base, whatever comes next.
func leave_base() -> void:
	if base == null:
		return
	hub.close()
	_unmount_station_screen()
	base.queue_free()
	base = null
	base_hud = null
	controller = null


## Where the base's door leads from here.
func _update_door() -> void:
	if base == null:
		return
	if base.read_only:
		base.door_text = "Back to your base"
	elif hub.in_lobby():
		base.door_text = hub.leave_text()
	else:
		base.door_text = "Head out: play online"


## The door: home from a visit, out of a server's lobby, or online from your
## own base (the uplink).
func _on_base_door() -> void:
	if base == null:
		return
	if base.read_only:
		leave_base()
		go_home()
	elif hub.in_lobby():
		leave_server()
	else:
		open_station("uplink")


## A station in your base opens its screen over the room.
func open_station(id: String) -> void:
	if base == null or base.read_only:
		return
	if id == "arena":
		# The arena gate is a way out, not a screen.
		open_arena()
		return
	var console := base.station(id)
	if console == null:
		return
	hub.open_station(id)
	if not hub.visible:
		return
	# The screen comes up on the console itself and the view moves in to it.
	_unmount_station_screen()
	station_screen = WorldScreen.new()
	station_screen.name = "LiveScreen"
	station_screen.size = HomeBase.SCREEN_SIZE
	station_screen.viewport = hub_screen
	console.screen.add_child(station_screen)
	station_screen.focus()
	if base_hud:
		base_hud.visible = false
	if controller != null and is_instance_valid(controller):
		controller.input_blocked = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Takes the live screen off its console and gives the view back.
func _unmount_station_screen() -> void:
	if station_screen != null and is_instance_valid(station_screen):
		station_screen.unfocus()
		station_screen.queue_free()
	station_screen = null


## Stepped away from a station: the room takes the mouse back.
func _on_station_closed() -> void:
	_unmount_station_screen()
	if base_hud:
		base_hud.visible = true
	if controller != null and is_instance_valid(controller) and not phone.is_open:
		controller.input_blocked = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Between places (connecting, travelling): no world, just the travel screen.
func _show_travel(text: String) -> void:
	leave_base()
	hub.set_online_status(text)
	hub.show_travel()


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


# ----------------------------------------------------------------- arena ----

## Opens the arena: the server's while online (from its lobby, or from inside
## a world such as the plaza through its arena gate), or a solo one against
## bot gladiators.
func open_arena() -> void:
	if raid is Arena or (base != null and base.read_only):
		return
	if net != null:
		if raid == null and not hub.in_lobby():
			return
		leave_base()
		# Leave the lobby (or the plaza or world you are in) for the arena
		# session on the same server. Leaving the arena comes back here.
		var arena_port: int = net.routes.get(Arena.ArenaVenue.ID, _join_port + ARENA_PORT_OFFSET)
		_lobby_port = _join_port
		if raid != null:
			_leave_raid()
		else:
			net.queue_free()
			net = null
		_show_travel("Entering the arena...")
		_begin_join(_join_address, arena_port, 3)
		return
	if raid != null:
		_leave_raid()
	leave_base()
	hub.close()
	var arena := Arena.new()
	arena.name = "Raid"
	raid = arena
	add_child(arena)
	# Your own loadout, but nothing leaves the stash: no gear is at risk here.
	var kit := StashRules.checkout(Profile.stash.duplicate(), Profile.loadout.duplicate(), Arena.ArenaVenue.new())
	arena.start_solo(kit, Profile.mastery.active_picks())
	_attach_player_view()


func leave_arena() -> void:
	if not raid is Arena:
		return
	var back_online := net != null and _lobby_port > 0
	_leave_raid()
	hub.refresh_gear()
	if back_online:
		_join_port = _lobby_port
		_lobby_port = -1
		_show_travel("Leaving the arena...")
		_begin_join(_join_address, _join_port, 3)
		return
	go_home()


# ------------------------------------------------------------------ solo ----

func start_raid(world_id: String) -> void:
	var world := Worlds.get_world(world_id)
	if world == null or raid != null or net != null:
		return
	# The launch pad: out of the base and into the world.
	leave_base()
	hub.close()
	raid = Raid.new()
	raid.name = "Raid"
	add_child(raid)
	# DEV MODE
	Profile.apply_dev_mode()
	raid.dev_cheats = DevMode.raid_cheats()
	raid.start(world, -1, Profile.checkout_loadout(world), Profile.mastery.active_picks(),
			LOCAL_OWNER, Profile.renown)
	_attach_player_view()
	raid.player_finished.connect(_on_solo_finished)


## The player's chosen look, limited to the clothing they own where they are:
## the local stash solo, the server's stash in a lobby.
func _my_look() -> Dictionary:
	return Look.clean_appearance(Profile.appearance, Economy.unlocked_outfits(hub.stash_items()))


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
		Look.set_appearance(raid.player, _my_look())
	controller = PlayerController.new()
	controller.phone_out = phone != null and phone.is_open
	if phone != null:
		phone.set_holder(controller.actor)
	controller.setup(raid.player)
	controller.sign_out_requested.connect(func() -> void: _on_sign_out_requested.call_deferred())
	controller.redeploy_requested.connect(func() -> void: _on_redeploy_requested.call_deferred())
	controller.drop_requested.connect(func(index: int) -> void: _on_drop_requested.call_deferred(index))
	controller.toy_throw_requested.connect(_on_toy_throw_requested)
	controller.pack_requested.connect(_on_pack_requested)
	raid.add_child(controller)
	hud = Hud.new()
	hud.setup(raid, controller)
	# War news buzzes the phone instead of scrolling over the screen.
	if phone != null:
		hud.notice_sink = phone.show_notice
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
	if raid is Arena:
		var arena_hud := ArenaHudScript.new()
		arena_hud.name = "ArenaHud"
		arena_hud.setup(raid)
		arena_hud.leave_requested.connect(leave_arena)
		arena_hud.booth_changed.connect(_on_booth_changed)
		raid.add_child(arena_hud)


## Took up or put down a bookmaker's booth in the arena: like a station, the
## character stops, the mouse is free and the HUD steps aside.
func _on_booth_changed(open: bool) -> void:
	_show_overlays(not open)
	if controller != null and is_instance_valid(controller):
		controller.input_blocked = open or phone.is_open
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if open or phone.is_open else Input.MOUSE_MODE_CAPTURED


## One solo life ended. A death keeps you in the world; leaving goes home.
func _on_solo_finished(_actor: Actor, result: Dictionary) -> void:
	if result.get("outcome", "") == "died":
		_show_death(result)
		return
	# Leave a beat so the player sees what happened before going home.
	await get_tree().create_timer(1.0).timeout
	_show_hub(result)


func _show_death(result: Dictionary) -> void:
	_death_result = result
	_redeploy_at = Time.get_ticks_msec() + int(raid.world.redeploy_delay * 1000.0)
	if hud != null and is_instance_valid(hud):
		hud.show_death(result, raid.world.redeploy_delay)


func _is_down() -> bool:
	return raid != null and not _death_result.is_empty()


## A number key, while down: drop back in at the place with that number.
func _on_drop_requested(index: int) -> void:
	if not _is_down():
		return
	var choices := raid.drop_choices("" if net else LOCAL_OWNER)
	if index < choices.size():
		_on_redeploy_requested(choices[index].id)


## Enter, while down: drop back into the same world. `drop` is where to land
## (an id from `Raid.drop_choices`); left empty, the world picks.
func _on_redeploy_requested(drop := "") -> void:
	if not _is_down() or Time.get_ticks_msec() < _redeploy_at:
		return
	if net:
		# `joined` follows and attaches the view to the new actor.
		net.deploy(drop)
		return
	Profile.apply_dev_mode()  # DEV MODE
	raid.add_player(Profile.checkout_loadout(raid.world), Profile.mastery.active_picks(), "You",
			LOCAL_OWNER, Profile.renown, drop)
	_attach_player_view()


## The player threw the toy vehicle in their hand. The world decides the rest.
func _on_toy_throw_requested(item_id: String) -> void:
	if raid == null or raid.player == null or not is_instance_valid(raid.player):
		return
	if net:
		net.throw_toy(item_id)
	else:
		raid.throw_toy(raid.player, item_id)


## The player asked to pack the vehicle they are looking at onto their watch.
func _on_pack_requested() -> void:
	if raid == null or raid.player == null or not is_instance_valid(raid.player):
		return
	if net:
		net.pack_vehicle()
	else:
		raid.pack_vehicle(raid.player)


## L: alive, start or cancel a sign-out. Down, go home.
func _on_sign_out_requested() -> void:
	if raid == null or raid.player == null or not is_instance_valid(raid.player):
		return
	if raid is Arena:
		leave_arena()
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
	go_home(result)


func _leave_raid() -> void:
	close_shop()
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
	phone.opened_changed.connect(_on_phone_opened)
	phone.settings_changed.connect(_apply_settings)
	phone.dev_mode_changed.connect(_on_dev_mode_changed)  # DEV MODE
	phone.quit_requested.connect(func() -> void: get_tree().quit())
	phone.set_wardrobe(hub.character)
	phone.mirror_changed.connect(_on_mirror_changed)


## Hands on the phone: the character stops, raises it (everyone sees) and the
## mouse is free. Putting it away in a raid takes the mouse back.
func _on_phone_opened(open: bool) -> void:
	if controller != null and is_instance_valid(controller):
		# A station screen still open behind the phone keeps the mouse.
		var arena_hud := raid.get_node_or_null("ArenaHud") if raid != null else null
		var screen_open: bool = hub.station != "" or shop_view != null or (arena_hud != null and arena_hud.booth_open)
		controller.input_blocked = open or screen_open
		controller.phone_out = open
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if open or screen_open else Input.MOUSE_MODE_CAPTURED


# ---------------------------------------------------------------- mirror ----

## The local player's character wherever they stand: a world, or the home base.
func _my_actor() -> Actor:
	if raid != null and is_instance_valid(raid) and raid.player != null and is_instance_valid(raid.player):
		return raid.player
	if base != null and is_instance_valid(base) and base.player != null and is_instance_valid(base.player):
		return base.player
	return null


## The phone's Mirror app came up or went away. Up, a mirror stands in front
## of the player, wherever they are; it goes when the app or the phone does.
func _on_mirror_changed(up: bool) -> void:
	_put_away_mirror()
	var me := _my_actor()
	if not up or me == null or me.is_dead or controller == null or not is_instance_valid(controller) \
			or controller.actor != me:
		phone.set_mirror_up(false)
		return
	# Level the gaze so the glass is in view. The camera mode stays as it is.
	controller.pitch = clampf(controller.pitch, -0.15, 0.05)
	_show_aim(false)
	mirror = MirrorScript.new()
	mirror.name = "Mirror"
	mirror.setup(me, controller.camera)
	me.get_parent().add_child(mirror)
	controller.body_layer = MirrorScript.BODY_LAYER
	phone.set_mirror_up(true)


func _put_away_mirror() -> void:
	if mirror != null and is_instance_valid(mirror):
		mirror.queue_free()
	mirror = null
	if controller != null and is_instance_valid(controller):
		controller.body_layer = 0
	_show_aim(true)


## The crosshair (and the melee marks round it) on whichever HUD is up.
func _show_aim(on: bool) -> void:
	for overlay: Node in [hud, base_hud]:
		if overlay != null and is_instance_valid(overlay) and overlay.has_method("show_aim"):
			overlay.show_aim(on)


## DEV MODE: dev mode or one of its cheats was switched on the phone. The
## stash swaps at once in the base; in a solo world the cheats change at once
## and the stash follows on the next drop or the trip home.
func _on_dev_mode_changed() -> void:
	if net != null:
		phone.show_notice("Online, dev mode comes with a server you host from here. Leave and host again to pick this up.")
	if raid != null:
		if net == null:
			raid.set_dev_cheats(DevMode.raid_cheats())
		return
	Profile.apply_dev_mode()
	hub.refresh_gear()
	_refresh_base()


## Puts a new look on the player's character at once, wherever they are.
## Online the server checks it and shows it to everyone (`NetSession.send_look`).
func _wear_look() -> void:
	var me := _my_actor()
	if me != null and not me.is_dead:
		Look.set_appearance(me, _my_look())


## Pushes the phone's settings into the raid view, if there is one.
func _apply_settings() -> void:
	if controller != null and is_instance_valid(controller):
		controller.mouse_sensitivity = GameSettings.mouse_sensitivity
		controller.invert_y = GameSettings.invert_y
		controller.base_fov = GameSettings.field_of_view
		controller.base_fov_third = GameSettings.field_of_view_third
		controller.third_person_distance = GameSettings.camera_distance
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
	# In a base (yours or someone else's): walk out and into theirs.
	leave_base()
	phone.close()
	visit_base(owner_name, owner_stash, owner_loadout)


# ---------------------------------------------------------------- online ----

func _run_dedicated_server(args: PackedStringArray) -> void:
	var port := int(_arg(args, "--port", str(NetSession.DEFAULT_PORT)))
	# DEV MODE: `--dev-host <name>` gives that player the dev stash, only on a
	# server run from the editor, and keeps this server's accounts apart.
	var dev_host := _arg(args, "--dev-host", "") if DevMode.available() else ""
	var accounts := _arg(args, "--accounts", DEV_ACCOUNTS if dev_host != "" else "")
	var err := start_server(_arg(args, "--world", ""), port, "--no-plaza" not in args,
			int(_arg(args, "--bots", "-1")), "--squad-spawn" in args, accounts,
			"--no-rewind" not in args,
			-1 if "--no-arena" in args else int(_arg(args, "--arena-port", str(port + ARENA_PORT_OFFSET))))
	if err != OK:
		push_error("Server: could not listen from port %d (%s)" % [port, error_string(err)])
		get_tree().quit(1)
		return
	if dev_host != "":  # DEV MODE
		net.stash.dev_accounts.append(net.stash.id_for_name(dev_host))
		print("Server: dev mode for %s (accounts in %s)" % [dev_host, accounts])


## Starts every session of a server. With a plaza it listens on `port`, and
## the raid worlds follow on the next ports; without one, a single world runs
## on `port`. `world_id` "" runs every raid world (the first one only when
## there is no plaza to reach the others from). All sessions share one stash
## service, so an account is the same wherever it shows up. The arena runs on
## `arena_port` (below zero: no arena), listed in the plaza's routes.
func start_server(world_id: String, port: int, with_plaza := true, bots := -1, squad := false,
		accounts := "", rewind := true, arena_port := -1) -> Error:
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
			session.clans = sessions[0].clans
		add_child(session)
		var err := session.host(world.id, next_port, world.max_players)
		if err != OK:
			return err
		print("Server: running %s on port %d" % [world.id, next_port])
		routes[world.id] = next_port
		sessions.append(session)
		next_port += 1
	net = sessions[0]
	if arena_port >= 0:
		var arena := NetSession.new()
		arena.name = "Net_%s" % Arena.ArenaVenue.ID
		arena.isolated = true
		arena.stash = net.stash
		arena.social = net.social
		arena.clans = net.clans
		arena.lag_compensation = rewind
		add_child(arena)
		if arena.host(Arena.ArenaVenue.ID, arena_port) == OK:
			print("Server: running the arena on port %d" % arena_port)
			routes[Arena.ArenaVenue.ID] = arena_port
			sessions.append(arena)
		else:
			# The raid worlds matter more than the arena: carry on without it.
			push_warning("Server: no arena, port %d is taken" % arena_port)
			arena.queue_free()
	if plaza != null:
		var session := NetSession.new()
		session.name = "Net_%s" % plaza.id
		session.isolated = true
		session.stash = net.stash
		session.social = net.social
		session.clans = net.clans
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
	if DevMode.active():  # DEV MODE: your account gets everything on your own server
		args.append_array(["--dev-host", Profile.player_name])
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
	if _lobby_port > 0:
		# Signed in to the arena: walk straight into the stands.
		hub.update_account(account)
		net.deploy()
		return
	var world := Worlds.get_world(net.world_id)
	if world.safe_zone:
		# The server's front door is its plaza: walk straight in.
		_plaza_address = _join_address
		_plaza_port = _join_port
		hub.set_online_status("Entering %s..." % world.display_name)
		net.deploy()
		return
	# A world's lobby is your home base, showing what this server keeps for
	# you. Its launch pad deploys into this world; its door leads back.
	hub.set_online_status("")
	hub.enter_lobby(account, world)
	hub.set_leave_text("Back to %s" % Worlds.social_world().display_name if _plaza_port >= 0 else "Leave the server")
	go_home()
	if base_hud:
		base_hud.show_notice("Connected to %s. The launch pad deploys you there." % world.display_name, 6.0)


func _on_online_account_changed(account: Dictionary) -> void:
	if shop_view != null and is_instance_valid(shop_view):
		shop_view.panel.set("account", account)
		shop_view.panel.call("refresh")
	if raid == null:
		hub.update_account(account)
		_refresh_base()
		# Buying or selling clothing changes what the server lets you wear.
		if net != null:
			net.send_look(Profile.appearance)


func _on_online_joined(p_raid: Raid) -> void:
	leave_base()
	hub.close()
	raid = p_raid
	hub.set_online_status("")
	_attach_player_view()
	if raid.world.safe_zone:
		plaza_view = PlazaViewScript.new()
		plaza_view.name = "PlazaView"
		plaza_view.setup(raid, net.routes, net.world_status)
		raid.add_child(plaza_view)
		net.world_status_changed.connect(plaza_view.refresh_heat.unbind(1))
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
		_show_travel("Travelling to %s..." % world.display_name)
		_begin_join(_plaza_address, port, 3)
	elif destination.begins_with("shop:"):
		open_shop(destination.trim_prefix("shop:"))
	elif destination == Arena.ArenaVenue.ID:
		open_arena()
	elif destination == "home":
		open_home_base()
		return
	elif destination == "leave":
		_leave_raid()
		leave_server()
	elif destination == "clans":
		open_clans()
	else:
		plaza_view.show_notice("Opening soon.")


## The clan hall's terminal: found, join or leave a clan. The server decides;
## the screen shows what it sends back.
func open_clans() -> void:
	if net == null or raid == null or shop_view != null:
		return
	var panel: Control = ClanPanel.new()
	panel.state = net.clan_state
	panel.asked.connect(func(action: String, a: String, b: String) -> void:
		if net:
			panel.show_message("")
			net.clan_ask(action, a, b))
	var session := net
	var on_change := func(state: Dictionary) -> void:
		if is_instance_valid(panel):
			panel.state = state
			panel.refresh()
	session.clan_changed.connect(on_change)
	panel.tree_exited.connect(func() -> void:
		if is_instance_valid(session) and session.clan_changed.is_connected(on_change):
			session.clan_changed.disconnect(on_change))
	_open_terminal(panel)


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
	_open_terminal(panel)


## Brings a panel up on the terminal of the doorway you stand in (its
## "Screen" node), or on a screen held up in front of you where there is none.
func _open_terminal(panel: Control) -> void:
	shop_view = ShopView.new()
	shop_view.name = "ShopView"
	shop_view.panel = panel
	shop_view.closed.connect(close_shop)
	# The shop comes up on the storefront's terminal, or on a screen held up
	# in front of you where a storefront has none.
	_shop_viewport = SubViewport.new()
	_shop_viewport.name = "ShopScreen"
	_shop_viewport.size = Vector2i(1280, 720)
	_shop_viewport.disable_3d = true
	_shop_viewport.add_child(shop_view)
	raid.add_child(_shop_viewport)
	shop_screen = WorldScreen.new()
	shop_screen.name = "LiveScreen"
	shop_screen.viewport = _shop_viewport
	var stall := PlazaViewScript.portal_at(raid, raid.player.global_position) if raid.player else null
	var mount := stall.get_node_or_null("Screen") as Node3D if stall else null
	if mount:
		mount.add_child(shop_screen)
	else:
		raid.add_child(shop_screen)
		var me := raid.player
		var ahead := Vector3(me.get_aim_dir().x, 0, me.get_aim_dir().z).normalized() if me else Vector3.FORWARD
		var at := (me.get_eye_position() if me else Vector3.ZERO) + ahead * 1.4
		shop_screen.global_transform = Transform3D(Basis.looking_at(ahead), at)
	shop_screen.focus()
	_show_overlays(false)
	# Nothing changes here until the server answers; a refusal says why.
	net.lobby_error.connect(func(reason: String) -> void:
		if shop_view != null and is_instance_valid(shop_view) and shop_view.panel.has_method("show_message"):
			shop_view.panel.call("show_message", reason))
	if controller != null and is_instance_valid(controller):
		controller.input_blocked = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## The HUD, nameplates, plaza prompts and the weapon in your hand step aside
## while a screen in the world is in use, so nothing is drawn over it.
func _show_overlays(on: bool) -> void:
	for layer: CanvasLayer in [hud, nameplates, plaza_view]:
		if layer != null and is_instance_valid(layer):
			layer.visible = on and (layer != nameplates or GameSettings.show_nameplates)
	# The weapon in your hand stays with your own camera; keep it out of the
	# screen's way.
	if controller != null and is_instance_valid(controller) and controller.actor != null \
			and is_instance_valid(controller.actor):
		controller.actor.hand.visible = on and not controller.actor.is_dead


func close_shop() -> void:
	if shop_view == null:
		return
	if shop_screen != null and is_instance_valid(shop_screen):
		shop_screen.unfocus()
		shop_screen.queue_free()
	shop_screen = null
	if _shop_viewport != null and is_instance_valid(_shop_viewport):
		_shop_viewport.queue_free()
	_shop_viewport = null
	shop_view = null
	_show_overlays(true)
	if controller != null and is_instance_valid(controller) and raid != null:
		controller.input_blocked = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## The plaza's door to your home base. The base shows the stash this server
## keeps for you, which a world's lobby has at hand, so the trip goes by way
## of the first world's lobby (every lobby is your base); the base's own door
## leads back to the plaza.
func open_home_base() -> void:
	if net == null or raid == null or net.routes.is_empty():
		return
	var port: int = net.routes.values()[0]
	_leave_raid()
	_show_travel("Going home...")
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
	hub.leave_lobby()
	if _lobby_port > 0:
		reason = "Could not enter the arena: %s" % reason
		_join_port = _lobby_port
		_lobby_port = -1
	hub.set_online_status(reason)
	# Back home on the local stash, with a word on what went wrong. A base
	# open on the server's stash falls back to the local one.
	if raid == null:
		if hub.station != "uplink":
			go_home()
		_refresh_base()
		_update_door()
	if base_hud:
		base_hud.show_notice(reason)


## The connection dropped while in the world. Your body stays there for a
## short while. If nobody kills it, what you carried goes back to your stash.
func _on_online_disconnected() -> void:
	var in_arena := raid is Arena
	var was_safe := raid != null and raid.world.safe_zone
	_leave_raid()
	_stop_local_server()
	_plaza_port = -1
	hub.leave_lobby()
	hub.refresh({})
	var reason := ("Lost the connection to the server." if was_safe
			else "Lost the connection to the server. Your body stays in the world for a moment. "
			+ "If it survives, what you carried goes back to your stash there.")
	if in_arena:
		_lobby_port = -1
		reason = "Lost the connection to the arena. Your gear is safe."
	hub.set_online_status(reason)
	go_home()
	if base_hud:
		base_hud.show_notice(reason, 8.0)


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
	if was_safe:
		# Signing out of the plaza itself leaves the server.
		leave_server()
		return
	# Back to the plaza if the server has one, else to the lobby.
	if _plaza_port >= 0:
		_show_travel("Returning to %s..." % Worlds.social_world().display_name)
		_begin_join(_plaza_address, _plaza_port, 3)
		return
	_show_travel("Returning to your base...")
	_begin_join(_join_address, _join_port, 3)


## Disconnects from the lobby: back to the plaza if the server has one, else
## home to your solo base.
func leave_server() -> void:
	if raid != null:
		return
	_join_attempts = 0
	_lobby_port = -1
	if net:
		net.queue_free()
		net = null
	hub.leave_lobby()
	if _plaza_port >= 0 and _join_port != _plaza_port:
		# Leaving a world's lobby leads back to the plaza, not off the server.
		_show_travel("Returning to %s..." % Worlds.social_world().display_name)
		_begin_join(_plaza_address, _plaza_port, 3)
		return
	_plaza_port = -1
	_stop_local_server()
	hub.set_online_status("")
	go_home()


func _stop_local_server() -> void:
	if _server_pid > 0:
		OS.kill(_server_pid)
		_server_pid = -1


static func _arg(args: PackedStringArray, flag: String, fallback: String) -> String:
	var index := args.find(flag)
	if index >= 0 and index + 1 < args.size():
		return args[index + 1]
	return fallback


## What a storefront's terminal shows: the shop panel on the screen's dark
## glass, and a way out (the button or Esc).
class ShopView:
	extends Control

	signal closed

	var panel: Control

	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var glass := ColorRect.new()
		glass.color = Color(0.025, 0.03, 0.035)
		glass.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(glass)
		var margin := MarginContainer.new()
		margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		for side: String in ["left", "right"]:
			margin.add_theme_constant_override("margin_" + side, 190)
		for side: String in ["top", "bottom"]:
			margin.add_theme_constant_override("margin_" + side, 40)
		add_child(margin)
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
		leave.custom_minimum_size = Vector2(0, 44)
		leave.pressed.connect(func() -> void: closed.emit())
		box.add_child(leave)

	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			closed.emit()
