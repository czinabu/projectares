extends Node
## Entry point. Switches between your home base, the plaza and a raid, solo
## or online.
##
## The game opens in your home base, never on a menu screen. Its stations open
## what the menu used to hold (`Hub`): loadout, mastery, wardrobe, records,
## and trader. Going online is the phone's Servers app. The watch opens squad
## portals out.
## Joining a server puts you in its plaza; a world's lobby on that server is
## your home base again, showing the stash that server keeps for you.
##
## A stay in a world is a string of lives. Dying keeps you in the world: the
## HUD shows what it cost and Enter drops you back in with whatever your
## loadout can still supply. You go home by signing out (L).
##
## Run with `-- --server [--world <id>] [--port <n>] [--bots <n>] [--squad-spawn]
## [--accounts <folder>] [--no-rewind] [--no-plaza] [--health-log <secs>]` for a dedicated server: no hub, no
## window needed. It runs the plaza (the social safe zone) on the port, and
## each raid world on the ports after it; `--world` runs just that one world,
## and `--no-plaza` runs it alone on the port. Player stashes are saved in the
## accounts folder (`user://accounts` unless given) and shared by all of them.
## The arena runs too, on `--arena-port` (the port plus `ARENA_PORT_OFFSET`
## unless given); `--no-arena` leaves it out.

const JOIN_TIMEOUT := 12.0
## After a dropped connection the game tries to get back in on its own for
## this long (a body left standing waits out the sign-out time, 30 s after a
## fight, from when the server notices), each try given `RECONNECT_TIMEOUT`.
var reconnect_window := 30.0
## The seed a solo world starts from; -1 (always, in play) for a random one.
## A bench sets it to compare builds on the same battle.
var raid_seed := -1
const RECONNECT_TIMEOUT := 5.0
## A server started here runs every world, and needs a while before it listens.
## An encrypted connection to a port nothing listens on yet fails at once, so
## the tries come about a second apart: enough of them to reach the deadline.
const HOST_JOIN_ATTEMPTS := 45
## However many attempts are left, a server of your own that has not let you
## in by then is given up on (and started once more, `HOST_RESTARTS`), so the
## travel screen never waits forever.
const HOST_JOIN_DEADLINE := 45.0
const HOST_RESTARTS := 1
## Signed in, asked to walk in (a plaza, a gate, the arena): the server has
## this long to put you there before the trip counts as failed.
const DEPLOY_TIMEOUT := 20.0
## A server of your own moves up by this many ports when its own are taken
## (by a server an earlier game left running), at most `HOST_PORT_TRIES` times.
const HOST_PORT_STEP := 100
const HOST_PORT_TRIES := 5
## While a server of your own runs, this game touches this file every
## `HEARTBEAT_EVERY` seconds; the server stops once it is `HEARTBEAT_STALE`
## seconds old (long enough for a slow load to never stop it mid-play).
const HOST_HEARTBEAT := "user://host_heartbeat"
const HEARTBEAT_EVERY := 1.0
const HEARTBEAT_STALE := 60
## The solo player's renown key in a raid, so it carries across their lives.
## A cluster's worlds stop this many seconds after the program that started
## them stops touching their heartbeat, and a world that stopped by itself
## is started again once it has been this long since its last start.
const CLUSTER_HEARTBEAT_STALE := 15
const CLUSTER_RESTART_AFTER := 5.0
const LOCAL_OWNER := "local"
const StashRules := preload("res://core/account/stash_rules.gd")
const AccountService := preload("res://core/account/account_service.gd")
const AccountLink := preload("res://core/account/account_link.gd")
const ServerTrust := preload("res://core/net/server_trust.gd")
const NameplatesScript := preload("res://core/ui/nameplates.gd")
const ScoreboardScript := preload("res://core/ui/scoreboard.gd")
const PhoneScript := preload("res://core/phone/phone.gd")
const BugReportScript := preload("res://core/report/bug_report.gd")
const MirrorScript := preload("res://core/visual/mirror.gd")
const GameSettings := preload("res://core/settings/game_settings.gd")
const BaseHudScript := preload("res://core/ui/base_hud.gd")
const BenchViewScript := preload("res://core/ui/bench_view.gd")
const ArenaHudScript := preload("res://core/arena/arena_hud.gd")
## The arena listens this many ports above the raid server.
const ARENA_PORT_OFFSET := 10
const PlazaViewScript := preload("res://core/social/plaza_view.gd")
const WarRoomPanel := preload("res://core/social/war_room_panel.gd")
const ClanPanel := preload("res://core/social/clan_panel.gd")
const ContractPanel := preload("res://core/economy/contract_panel.gd")
const MarketPanel := preload("res://core/economy/market_panel.gd")
const TerminalStyle := preload("res://core/ui/terminal_style.gd")
const Contracts := preload("res://core/economy/contracts.gd")
## The plaza holds more people than a raid.
const PLAZA_PLAYERS := 32
const SHOP_PANEL := "res://core/economy/shop_panel.gd"
const Economy := preload("res://core/economy/economy.gd")
const SafetyNets := preload("res://core/economy/safety_nets.gd")
## Who the phone hears salvage and insurance news from (`_safety_net_news`).
const CLAIMS_ID := "claims"
const CLAIMS_NAME := "Claims Office"
const BaseUpgrades := preload("res://core/base/base_upgrades.gd")
## DEV MODE: temporary, see `core/dev/dev_mode.gd`.
const DevMode := preload("res://core/dev/dev_mode.gd")
const DevToolsScript := preload("res://core/dev/dev_tools.gd")  # DEV MODE
const DevConsole := preload("res://core/dev/dev_console.gd")  # DEV MODE
## The new player's tour: the handler on the phone (see "new player's tour").
const Onboarding := preload("res://core/progression/onboarding.gd")
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
## On a race track: the local racer's view of the race (lights, splits,
## board and ghost).
var race_view: RaceView
var net: NetSession
## The phone every player carries: the game's menu, in the hub and in a raid.
var phone: CanvasLayer
## The Mirror app's light in front of the player (`_make_dressing_light`),
## how bright it is, and how far (radians) a pixel's drag turns the dressing
## room's view.
var _dressing_light: OmniLight3D
var dressing_light_energy := 0.8
var dressing_turn_per_pixel := 0.008
## The mirror standing in front of the player while the phone's Mirror app is
## up, else null.
var mirror: Node3D
## The wardrobe's glass while the Mirror app was opened from it
## (`_use_wardrobe`): first person looks into it instead of a mirror of its
## own. It belongs to the base and is never freed here.
var _wardrobe_glass: Node3D
## How far (radians) the view turns right of the wardrobe's glass.
var wardrobe_turn := 0.2
## The home base while the player is walking around it, else null.
var base: HomeBase
var base_hud: CanvasLayer
## The view at the gunsmith bench while the player works it, else null.
var bench_view: Node3D
var plaza_view: CanvasLayer
## The shop screen while trading at a plaza storefront, else null.
var shop_view: ShopView
## Sends what the phone's Report app writes (`BugReport`).
var bug_report: Node
var dev_tools: Node  # DEV MODE
## The storefront terminal's live screen showing `shop_view`, else null.
var shop_screen: WorldScreen
var _shop_viewport: SubViewport
## Server: every session it runs (the plaza first, then the raid worlds).
var sessions: Array[NetSession] = []
## Server: the line to the account service, on a server that shares its
## accounts (`--account-url`); null on one that keeps its own.
var account_link: AccountLink
## Server: the programs a cluster started (`_run_cluster`), each {"id",
## "port", "args", "pid", "started"}.
var _cluster: Array[Dictionary] = []
## Client: the sign-in token each server address last handed out
## (`NetSession.ticket`), shown instead of the secret on the next trip there.
var _tickets := {}
## A recovery code typed in the phone's Servers app (`Phone.recover_account`),
## sent with the next sign-in only (`NetSession.recovery`), then forgotten.
var _recovery_code := ""
## Client: where this server's plaza is, once you have been in it. Leaving a
## world's lobby or finishing a run leads back there. Port -1 means no plaza.
var _plaza_address := ""
var _plaza_port := -1
var _server_pid := -1
## The `Profile` save the server we host was handed (the dev save in dev
## mode). Its snapshots go back into that save only, so a dev server never
## writes into the real profile, nor a real server into the dev one.
var _hosted_save := ""
var _join_attempts := 0
## A trip to a server of your own: when it is given up on (msec ticks, 0 for
## no limit), how many more times the server may be started again, and the
## world it runs.
var _join_deadline := 0
var _beat_left := 0.0
var _host_restarts_left := 0
var _host_world := ""
var _join_address := ""
var _join_port := NetSession.DEFAULT_PORT
## Reconnecting after a drop: when it is given up on (msec ticks, 0 when not
## reconnecting), what to say then, and whether a body was left out in a world.
var _reconnect_until := 0
var _reconnect_note := ""
var _reconnect_body := false
## Word for the player about a reconnect, shown where the trip lands them.
var _back_notice := ""
## Online: the raid lobby's port, while visiting that server's arena.
var _lobby_port := -1
var _lobby_address := ""
## Heading out by the base's door to a remembered server: if it cannot be
## reached, a server of your own is started instead.
var _door_fallback := false
## Where a server started from here listens, and anything more to start it
## with (a test keeps its accounts apart this way).
var host_port := NetSession.DEFAULT_PORT
var host_args := PackedStringArray()
## The address typed in the phone's Servers app, kept as the door's destination once the
## server has let you in.
var _remember_address := ""
## Through a plaza gate into a world: deploy straight in on arrival rather
## than stopping in that world's lobby.
var _gate_deploy := false
## Where you are coming back to the plaza from (a doorway's destination:
## "home", "arena", "world:<id>"), so you arrive in front of that door.
var _arrive_from := ""
## The session connected ahead of a trip (see "travel ahead"), where it
## leads, and how long it has gone unused.
var _ahead: NetSession
var _ahead_host := ""
var _ahead_port := -1
var _ahead_unused := 0.0
var _ahead_check := 0.0
var _ahead_retry := {}   # "host:port" -> msec before which it is not tried again
var _prepared := {}      # world id -> true once its ground was worked out ahead
## How near a plaza doorway (in metres) the game connects ahead to where it
## leads, how long an unused connection is kept once you walk away, and how
## long a server that would not take one is left alone.
var ahead_range := 16.0
var ahead_linger := 20.0
var ahead_retry := 30.0
## Seconds a trip stays dark before the travel screen says what is taking
## so long, and how long the new place takes to fade in.
var travel_quiet := 1.2
var arrival_fade := 0.4
var _cover: ColorRect
var _travelling := false
var _travel_began := 0
## Where the hand-off of your profile to a server you host waits for it.
const HOST_PROFILE := "user://host_profile.json"
## The local player's last life, while they are down.
var _death_result := {}
## Joining a world's session through a squad portal: `_gate_deploy` drops
## you in as soon as signed in, and this lands you at its outpost.
var _portal_deploy := false
## Time.get_ticks_msec() from which a dead player may drop back in.
var _redeploy_at := 0
## How many items the server's account held at the last snapshot, so the
## tour can tell a depot banking (the stash grows mid-life). -1 unknown.
var _tour_stash_size := -1
## The tour's light over the next thing to use (`TourGuide`), in the place
## you are; null while there is nothing to point at.
var _tour_guide: TourGuide
## Seconds to the next look for what the guide points at.
var _tour_guide_look := 0.0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	# Enemies on or off in every world this program runs (`Raid.enemies`).
	Raid.enemies = Raid.enemies_wanted(args)
	Raid.enemy_cap = Raid.enemy_cap_wanted(args)
	# The near cap is part of the same budget: no enemy cap, no near cap.
	Raid.near_full_cap = maxi(int(ProjectSettings.get_setting("ares/stability/enemies_full_detail", 0)), 0) \
			if Raid.enemy_cap > 0 else 0
	# Every life a raid here finishes goes in the life log (`LifeLog`), to
	# tune the worlds from: `--life-log <dir>` puts it elsewhere.
	var log_at := args.find("--life-log")
	LifeLog.directory = args[log_at + 1] if log_at >= 0 and log_at + 1 < args.size() else "user://life_log"
	if "--account-service" in args:
		_run_account_service(args)
		return
	if "--server" in args:
		if "--cluster" in args:
			_run_cluster(args)
		else:
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
	# The fade through a portal: dark the moment you step in, the new place
	# fading in when you stand in it.
	var fade := CanvasLayer.new()
	fade.name = "TravelFade"
	fade.layer = 90
	_cover = ColorRect.new()
	_cover.color = Color(0.0, 0.0, 0.0, 0.0)
	_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fade.add_child(_cover)
	add_child(fade)
	hub.closed.connect(_on_station_closed)
	hub.online_equip_requested.connect(func(slot: String, item_id: String) -> void:
		if net:
			net.equip(slot, item_id))
	hub.online_pick_requested.connect(func(track: String, variant_id: String) -> void:
		if net:
			net.pick_mastery(track, variant_id))
	hub.online_buy_requested.connect(func(shop_id: String, item_id: String) -> void:
		if net:
			net.buy(shop_id, item_id))
	hub.online_sell_requested.connect(func(item_id: String, count: int) -> void:
		if net:
			net.sell(item_id, count))
	hub.online_craft_requested.connect(func(item_id: String) -> void:
		if net:
			net.craft(item_id))
	hub.online_insure_requested.connect(func(action: String, item_id: String) -> void:
		if net:
			net.insure(action, item_id))
	_setup_phone()
	hub.look_changed.connect(func(appearance: Dictionary) -> void:
		Profile.set_appearance(appearance, hub.character.owned)
		_wear_look()
		if base != null and not base.read_only:
			base.show_paints(_my_look().get("paints", {}))
			base.show_trail(_my_look().get("trail", ""))
		if net != null:
			net.send_look(Profile.appearance))
	# The game opens in the world: your home base.
	go_home()
	_tour_start()


## Between places the hub's travel screen fills the window; anywhere else it
## is only ever seen on a station's screen.
func _process(delta: float) -> void:
	if controller != null and is_instance_valid(controller) and phone != null:
		controller.mirror_focus = 1.0 if phone.mirror_on_face() else 0.0
	if _server_pid > 0:
		_beat_left -= delta
		if _beat_left <= 0.0:
			_beat()
			_watch_host_trip()
	if _travel != null:
		_travel.visible = hub.visible and hub.station == ""
		_fade_travel(_travel.visible, delta)
		_ahead_check -= delta
		if _ahead_check <= 0.0:
			_ahead_check = 0.5
			_tick_ahead(0.5)
	if controller != null and is_instance_valid(controller) and controller.wrist_raised:
		_tour_event("watch")
	if phone != null:
		# Between places nobody sees a pop-up: it keeps its time for after.
		phone.notices_paused = _cover != null and _cover.color.a > 0.5
	_tour_guide_tick(delta)
	_keep_mirror_view()


## Between places the view goes dark at once and the next place fades in
## (the fade through a portal). Only a trip that drags on shows the travel
## screen, which says what it is waiting for.
func _fade_travel(travelling: bool, delta: float) -> void:
	if _cover == null:
		return
	if travelling and not _travelling:
		_travel_began = Time.get_ticks_msec()
		_cover.color.a = 1.0
	elif travelling:
		if (Time.get_ticks_msec() - _travel_began) / 1000.0 > travel_quiet:
			_cover.color.a = move_toward(_cover.color.a, 0.0, delta / 0.2)
	elif _travelling:
		_cover.color.a = 1.0
	else:
		_cover.color.a = move_toward(_cover.color.a, 0.0, delta / maxf(arrival_fade, 0.01))
	_travelling = travelling


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		_stop_local_server()
		for program in _cluster:
			if int(program.get("pid", -1)) > 0:
				OS.kill(int(program.pid))
		_cluster.clear()


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
		_open_base(hub.stash_items(), hub.current_loadout(), "", hub.base_upgrades(), hub.base_plan())
	else:
		_refresh_base()
	_update_door()
	if not result.is_empty() and base_hud and hub.result_text() != "":
		base_hud.show_notice(hub.result_text(), 8.0)
	# Home again: an update still waiting is told once more.
	if phone != null:
		phone.remind_update()


## Opens your own base. Kept for callers that want the base by name.
func enter_base() -> void:
	go_home()


## Opens someone else's base to look around. Nothing in it can be equipped.
## `stash`, `loadout` and `upgrades` (their base's upgrades, so you see the
## base they have built) are that player's, as their server reports them.
func visit_base(owner_name: String, stash: Array, loadout: Dictionary, upgrades: Array = [], plan := {}) -> void:
	_open_base(stash, loadout, owner_name if owner_name != "" else "Raider", upgrades, plan)
	_update_door()


func _open_base(stash: Array, loadout: Dictionary, owner_name: String, upgrades: Array = [], plan := {}) -> void:
	if base != null or raid != null:
		return
	hub.close()
	base = HomeBase.new()
	base.name = "HomeBase"
	base.owner_name = owner_name
	base.read_only = owner_name != ""
	if not base.read_only:
		base.paints = _my_look().get("paints", {})
		base.trail = RigTrail.clean(_my_look().get("trail", ""))
	base.show_gear(stash, loadout, upgrades, plan)
	if not base.read_only:
		base.set_scrip(hub.scrip())
	add_child(base)
	base.equip_requested.connect(_on_base_equip)
	base.upgrade_requested.connect(_on_base_upgrade)
	base.room_placed.connect(_on_base_room_placed)
	base.paint_requested.connect(_on_base_paint)
	base.trail_requested.connect(_on_base_trail)
	base.leave_requested.connect(_on_base_door)
	base.station_requested.connect(open_station)
	base.bench_used.connect(open_bench)
	base.plan_used.connect(open_bench.bind("plan"))
	base.portal_entered.connect(func(destination: String) -> void: go_through_portal.call_deferred(destination))
	base.player_replaced.connect(func(_actor: Actor) -> void: _attach_base_view())
	if not base.read_only:
		base.target_hit.connect(_tour_event.bind("target"))
	_attach_base_view()
	base_hud = BaseHudScript.new()
	base_hud.name = "BaseHud"
	base_hud.setup(base, controller)
	base_hud.contracts = _held_contracts()
	base.add_child(base_hud)
	_apply_settings()
	_tour_check()
	_tour_show()
	_tour_remind()


## Gives the base's player a camera and controls. Called again whenever
## their loadout changes, which makes them a new actor wearing it.
func _attach_base_view() -> void:
	if base == null:
		return
	var view_third := false
	if controller != null and is_instance_valid(controller):
		view_third = controller.is_third_person()
		controller.get_parent().remove_child(controller)
		controller.queue_free()
	Look.set_appearance(base.player, _my_look())
	controller = PlayerController.new()
	controller.phone_out = phone != null and phone.held()
	controller.setup(base.player)
	controller.portal_requested.connect(_on_portal_requested)
	controller.race_requested.connect(_on_race_requested)
	if race_view != null and is_instance_valid(race_view):
		controller.ghost_pick = race_view.ghost_pick
	if phone != null:
		# The phone is held by this body's own hand, in every view.
		phone.set_holder(controller.actor)
	# The watch's summon works at home too: vehicles unpack in the base and
	# a weapon picked is equipped.
	controller.toy_throw_requested.connect(_on_toy_throw_requested)
	controller.toy_hold_requested.connect(_on_toy_hold_requested)
	controller.pack_requested.connect(_on_pack_requested)
	controller.summon_requested.connect(_on_summon_requested)
	controller.store_requested.connect(_on_store_requested)
	base.add_child(controller)
	if base.wall_mirror != null:
		base.wall_mirror.setup(controller.actor, controller.camera)
	# The view is the player's choice: a change of gear keeps it.
	if view_third != controller.is_third_person():
		controller.toggle_view()


## Closes the base, whatever comes next.
func leave_base() -> void:
	if base == null:
		return
	hub.close()
	_unmount_station_screen()
	base.queue_free()
	base = null
	base_hud = null
	bench_view = null
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
		base.door_text = "Head out to %s" % _outside_name()


## The door: home from a visit, out of a server's lobby, or out into the
## plaza from your own base.
func _on_base_door() -> void:
	if base == null:
		return
	if base.read_only:
		leave_base()
		go_home()
	elif hub.in_lobby():
		leave_server()
	else:
		head_out()


## What is outside the base's door: the social world, by its own name.
func _outside_name() -> String:
	var plaza := Worlds.social_world()
	return plaza.display_name if plaza != null else "the server"


## Out of your own base by its door, with no screen in the way: to the server
## the door remembers (`Profile.home_server`, set by a join from the phone's
## Servers app), else to a
## server of your own. Worlds are chosen out there, at its gates.
func head_out() -> void:
	if raid != null or net != null or base == null or base.read_only:
		return
	_show_travel("Heading out to %s..." % _outside_name())
	_arrive_from = "home"
	if Profile.home_server != "":
		_door_fallback = true
		join_online(Profile.home_server, false)
	else:
		host_and_join()
	if net == null and raid == null:
		# It never got going (no server could start): back to the base, with
		# the reason on the travel line.
		_arrive_from = ""
		var reason := hub.online_status()
		go_home()
		if base_hud and reason != "":
			base_hud.show_notice(reason)


## The phone's Servers app: host a server here (`address` "") or join one,
## heading out of the base the way the door does. Only from home: a solo
## run has to end first.
func _go_online_from_phone(address: String) -> void:
	if net != null:
		return
	if raid != null:
		phone.show_notice("Go home first: you go online from your base.")
		return
	phone.close()
	_arrive_from = "home"
	if address == "":
		_show_travel("Starting a server...")
		host_and_join()
	else:
		_show_travel("Connecting to %s..." % address)
		join_online(address)
	if net == null and raid == null:
		# It never got going (no server could start): back to the base,
		# with the reason on the phone.
		_arrive_from = ""
		go_home()


## The phone's Servers app: off the server altogether, home to your solo
## base. Not from out in a world, where leaving goes through a sign-out.
func _leave_from_phone() -> void:
	if net == null:
		return
	if raid is Arena:
		phone.show_notice("Step out of the arena first, then leave the server.")
		return
	if raid != null and not raid.world.safe_zone:
		phone.show_notice("Sign out from your watch first, then leave the server.")
		return
	phone.close()
	if raid != null:
		_leave_raid()
	_plaza_port = -1
	leave_server()


## The phone's Servers app asked to restart into a downloaded update while
## online: off the server first (as leaving it from the phone would be,
## never from out in a world), then the game restarts into the new build.
func _restart_for_update() -> void:
	if Updater.state != "ready":
		return
	if net != null:
		if _away_from_quiet():
			phone.show_notice("Leave this place first (sign out from your watch out in a world), then restart for the update.")
			return
		_leave_from_phone()
		if net != null:
			return
	Profile.save()
	Updater.restart_now()


## Out in a world, the arena or a race, where a pop-up about an update could
## cost a fight: the phone keeps the news until the player is home or in the
## plaza (`Phone.update_hold`, `remind_update`).
func _away_from_quiet() -> bool:
	return raid != null and is_instance_valid(raid) and not raid.world.safe_zone


## The gunsmith bench (or with `target` "plan", the plan table) was taken
## up: the view moves in to it and the mouse works it until the player steps
## away (`BenchView`).
func open_bench(target := "bench") -> void:
	if base == null or base.read_only or bench_view != null:
		return
	bench_view = BenchViewScript.new()
	bench_view.name = "BenchView"
	bench_view.base = base
	bench_view.target = target
	bench_view.closed.connect(_on_bench_closed)
	base.add_child(bench_view)
	bench_view.focus()
	if base_hud:
		base_hud.visible = false
	if controller != null and is_instance_valid(controller):
		controller.input_blocked = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Stepped away from the bench: the room takes the mouse back.
func _on_bench_closed() -> void:
	bench_view = null
	if base_hud:
		base_hud.visible = true
	if controller != null and is_instance_valid(controller) and not phone.is_open:
		controller.input_blocked = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## A station in your base opens its screen over the room.
func open_station(id: String) -> void:
	if base == null or base.read_only:
		return
	var console := base.station(id)
	if console == null:
		return
	if id == "wardrobe":
		_use_wardrobe()
		return
	hub.open_station(id, base.also_shows(id))
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


## The wardrobe is a mirror: you turn to it and the phone comes up on its
## Mirror app, with this glass as the mirror in first person (the dressing
## room in third, as anywhere). No screen and no flat customizer.
func _use_wardrobe() -> void:
	var glass: Node3D = base.wardrobe_mirror
	var me := _my_actor()
	if glass == null or not is_instance_valid(glass) or me == null or controller == null \
			or not is_instance_valid(controller):
		return
	_wardrobe_glass = glass
	var to := glass.global_position - me.global_position
	to.y = 0.0
	if to.length() > 0.05:
		# Square to the glass, turned a touch right so it stands clear of the
		# phone held on the right.
		controller.yaw = atan2(-to.x, -to.z) - wardrobe_turn
	controller.pitch = 0.0
	if phone.mirror_open():
		_on_mirror_changed(true)
	else:
		phone.open("mirror")


## Takes the live screen off its console and gives the view back.
func _unmount_station_screen() -> void:
	if station_screen != null and is_instance_valid(station_screen):
		station_screen.unfocus()
		station_screen.queue_free()
	station_screen = null


## Stepped away from a station: the room takes the mouse back.
func _on_station_closed() -> void:
	_unmount_station_screen()
	# The trader or the fabricator may have changed the stash and what you
	# can afford: the room shows the same stash the screen did.
	_refresh_base()
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


## An upgrade confirmed at its bulkhead in the base: bought from the profile
## solo, asked of the server online (which answers with a fresh account).
func _on_base_upgrade(upgrade_id: String) -> void:
	if base == null or base.read_only:
		return
	if hub.in_lobby():
		if net:
			net.buy_upgrade(upgrade_id)
		return
	var result := Profile.buy_upgrade(upgrade_id)
	if base_hud:
		base_hud.show_notice("%s is yours." % BaseUpgrades.title(upgrade_id) if result.ok else str(result.get("error", "")))
	_refresh_base()


## A change picked at the base's plan table (a room moved, a hub shape, a
## room style; `BasePlan.change`): kept in the profile solo, asked of the
## server online (which answers with a fresh account).
func _on_base_room_placed(key: String, value: String) -> void:
	if base == null or base.read_only:
		return
	if hub.in_lobby():
		if net:
			net.place_room(key, value)
		return
	var result := Profile.place_room(key, value)
	if not result.ok and base_hud:
		base_hud.show_notice(str(result.get("error", "")))
	_refresh_base()


## An armor paint picked at a stand's swatch: it goes in the look (the
## paints are cosmetic, like clothing, and travel and are checked with it),
## so the body, the stands and, online, everyone else see it.
func _on_base_paint(frame_look: String, paint: String) -> void:
	if base == null or base.read_only:
		return
	var next := Profile.appearance.duplicate(true)
	var paints: Dictionary = next.get("paints", {}).duplicate()
	if paint == "":
		paints.erase(frame_look)
	else:
		paints[frame_look] = paint
	next["paints"] = paints
	var owned := Economy.unlocked_outfits(hub.stash_items())
	Profile.set_appearance(next, owned)
	hub.character.owned = owned
	hub.character.set_appearance(Profile.appearance)
	_wear_look()
	if net != null:
		net.send_look(Profile.appearance)
	_refresh_base()


## A thruster trail picked at a rig stand's swatch: it goes in the look,
## like an armor paint (`_on_base_paint`).
func _on_base_trail(trail: String) -> void:
	if base == null or base.read_only:
		return
	var next := Profile.appearance.duplicate(true)
	if trail == "":
		next.erase("trail")
	else:
		next["trail"] = trail
	var owned := Economy.unlocked_outfits(hub.stash_items())
	Profile.set_appearance(next, owned)
	hub.character.owned = owned
	hub.character.set_appearance(Profile.appearance)
	_wear_look()
	if net != null:
		net.send_look(Profile.appearance)
	_refresh_base()


## Shows the base whatever the hub would show now.
func _refresh_base() -> void:
	if base and not base.read_only:
		base.show_paints(_my_look().get("paints", {}))
		base.show_trail(_my_look().get("trail", ""))
		base.set_scrip(hub.scrip())
		base.show_gear(hub.stash_items(), hub.current_loadout(), hub.base_upgrades(), hub.base_plan())
		_tour_check()


# ----------------------------------------------------------------- arena ----

## Opens the arena: the server's while online (from its lobby, or from inside
## a world such as the plaza through its arena gate), or a solo one against
## bot gladiators.
func open_arena() -> void:
	if raid is Arena or (base != null and base.read_only) or LaunchScope.holds("arena"):
		return
	if net != null:
		if raid == null and not hub.in_lobby():
			return
		leave_base()
		# Leave the lobby (or the plaza or world you are in) for the arena
		# session on the same server. Leaving the arena comes back here.
		var arena := _route(Arena.ArenaVenue.ID)
		if arena.is_empty():
			arena = [_join_address, _join_port + ARENA_PORT_OFFSET]
		_lobby_port = _join_port
		_lobby_address = _join_address
		if raid != null:
			_leave_raid()
		else:
			net.queue_free()
			net = null
		_show_travel("Entering the arena...")
		_begin_join(arena[0], arena[1], 3)
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
		_join_address = _lobby_address
		_lobby_port = -1
		_show_travel("Leaving the arena...")
		if _at_plaza():
			_arrive_from = Arena.ArenaVenue.ID
		_begin_join(_join_address, _join_port, 3)
		return
	go_home()


# ------------------------------------------------------------------ solo ----

func start_raid(world_id: String, drop := "") -> void:
	var world := Worlds.get_world(world_id)
	if world == null or raid != null or net != null or _tour_refuses(world):
		return
	# Through a squad portal: out of the base and into the world.
	leave_base()
	hub.close()
	raid = world.new_raid()
	raid.name = "Raid"
	add_child(raid)
	# DEV MODE
	Profile.apply_dev_mode()
	raid.dev_cheats = DevMode.raid_cheats()
	var kit := Profile.checkout_loadout(world)
	raid.start(world, raid_seed, kit, Profile.mastery.active_picks(),
			LOCAL_OWNER, Profile.renown, drop, Profile.insured_in(kit))
	_attach_player_view()
	raid.player_finished.connect(_on_solo_finished)
	raid.player_banked.connect(func(actor: Actor, _items: Array) -> void:
		if raid != null and actor == raid.player:
			_tour_event("banked"))
	_tour_check()


## The contracts the account holds, for the watch. They live on the
## server's account, so there are none solo.
func _held_contracts() -> Array[Dictionary]:
	return Contracts.held(net.account.get("contracts")) if net != null else ([] as Array[Dictionary])


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
	controller.phone_out = phone != null and phone.held()
	controller.setup(raid.player)
	if phone != null:
		# The phone is held by this body's own hand, in every view.
		phone.set_holder(controller.actor)
	controller.sign_out_requested.connect(func() -> void: _on_sign_out_requested.call_deferred())
	controller.redeploy_requested.connect(func() -> void: _on_redeploy_requested.call_deferred())
	controller.drop_requested.connect(func(index: int) -> void: _on_drop_requested.call_deferred(index))
	controller.toy_throw_requested.connect(_on_toy_throw_requested)
	controller.toy_hold_requested.connect(_on_toy_hold_requested)
	controller.pack_requested.connect(_on_pack_requested)
	controller.summon_requested.connect(_on_summon_requested)
	controller.store_requested.connect(_on_store_requested)
	controller.pack_drop_requested.connect(_on_pack_drop_requested)
	controller.ping_requested.connect(_on_ping_requested)
	controller.portal_requested.connect(_on_portal_requested)
	raid.add_child(controller)
	hud = Hud.new()
	hud.setup(raid, controller)
	hud.contracts = _held_contracts()
	# War news buzzes the phone instead of scrolling over the screen.
	if phone != null:
		hud.notice_sink = phone.show_notice
	raid.add_child(hud)
	_tour_show()
	_tour_remind()
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
	if raid is Race:
		# Solo, the league is the local profile's (online it is the server's).
		if raid.mode == Raid.Mode.SOLO and (raid as Race).league_bank == null:
			(raid as Race).league_bank = Race.ProfileLeagueBank.new()
		race_view = RaceView.new()
		race_view.setup(raid)
		race_view.watching_changed.connect(_on_race_watching)
		race_view.league_source = phone.racing
		raid.add_child(race_view)


## Watching a race from its desk: the character stands still and the HUD
## steps aside while the race view's chase camera follows the racers.
func _on_race_watching(on: bool) -> void:
	_show_overlays(not on)
	if controller != null and is_instance_valid(controller):
		controller.input_blocked = on or phone.is_open


## A pick on the race icon: the ghost is this view's own, the rest are
## asked of the race (the server's, online).
func _on_race_requested(action: String) -> void:
	if not raid is Race:
		return
	if action == "ghost":
		# Turns through your best, a friend's, the board leader's and none.
		var at := Race.GHOST_PICKS.find(controller.ghost_pick)
		controller.ghost_pick = Race.GHOST_PICKS[(at + 1) % Race.GHOST_PICKS.size()]
		if race_view != null and is_instance_valid(race_view):
			race_view.ghost_pick = controller.ghost_pick
		return
	(raid as Race).ask(action)


## Took up or put down a bookmaker's booth in the arena: like a station, the
## character stops, the mouse is free and the HUD steps aside.
func _on_booth_changed(open: bool) -> void:
	_show_overlays(not open)
	if controller != null and is_instance_valid(controller):
		controller.input_blocked = open or phone.is_open
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if open or phone.is_open else Input.MOUSE_MODE_CAPTURED


## One solo life ended. A death keeps you in the world; leaving goes home.
func _on_solo_finished(_actor: Actor, result: Dictionary) -> void:
	_tour_life_ended(result)
	_safety_net_news(result)
	if result.get("outcome", "") == "died":
		_show_death(result)
		return
	# Leave a beat so the player sees what happened before going home.
	await get_tree().create_timer(1.0).timeout
	_show_hub(result)
	# Through a portal out of the world to somewhere else: the gear is home,
	# and the trip goes on from the base as if through a portal opened there.
	var door := str(result.get("door", ""))
	if Portal.goes_on(door):
		go_through_portal.call_deferred(door)


## The claims office (`SafetyNets`) messages the phone with what a death's
## salvage and insurance sent home, so there is a record of it.
func _safety_net_news(result: Dictionary) -> void:
	if phone == null:
		return
	var lines: Array[String] = []
	var recalled := str(result.get("recalled", ""))
	if recalled != "":
		lines.append("Your insured %s was recalled home. The policy is spent; a new one is ready in %s."
				% [ItemDB.item_name(recalled), SafetyNets.wait_text(SafetyNets.COOLDOWN)])
	var salvaged: Array = result.get("salvaged", [])
	if not salvaged.is_empty():
		lines.append("Salvage from your %s: %s, in your stash." % [ItemDB.summarize(salvaged),
				SafetyNets.describe(result.get("salvage", []))])
	if not lines.is_empty():
		phone.add_local_message(CLAIMS_ID, CLAIMS_NAME, " ".join(lines))


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
	var kit := Profile.checkout_loadout(raid.world)
	raid.add_player(kit, Profile.mastery.active_picks(), "You",
			LOCAL_OWNER, Profile.renown, drop, Profile.insured_in(kit))
	_attach_player_view()


## The player threw the toy vehicle in their hand. The world decides the rest.
func _on_toy_throw_requested(item_id: String) -> void:
	if base != null and raid == null:
		base.throw_toy(base.player, item_id)
		return
	if raid == null or raid.player == null or not is_instance_valid(raid.player):
		return
	if net:
		net.throw_toy(item_id)
	else:
		raid.throw_toy(raid.player, item_id)


## The player took a toy into their hand or put it back. The world shows it.
func _on_toy_hold_requested(item_id: String) -> void:
	if base != null and raid == null:
		base.hold_toy(base.player, item_id)
		return
	if raid == null or raid.player == null or not is_instance_valid(raid.player):
		return
	if net:
		net.hold_toy(item_id)
	else:
		raid.hold_toy(raid.player, item_id)


## The player picked a weapon in their pack on the watch. The world decides
## whether it materializes.
func _on_summon_requested(item_id: String) -> void:
	if base != null and raid == null:
		if not base.read_only and Loadout.summonable(item_id):
			_on_base_equip(Loadout.weapon_slot(item_id), item_id)
		return
	if raid == null or raid.player == null or not is_instance_valid(raid.player):
		return
	if net:
		net.summon(item_id)
	else:
		raid.summon(raid.player, item_id)


## The watch's store: the weapon in hand goes back into the pack. At home
## that takes it off the loadout, back onto its rack.
func _on_store_requested(item_id: String) -> void:
	if base != null and raid == null:
		if not base.read_only and Loadout.summonable(item_id):
			_on_base_equip(Loadout.weapon_slot(item_id), "")
		return
	if raid == null or raid.player == null or not is_instance_valid(raid.player):
		return
	if net:
		net.store(item_id)
	else:
		raid.store(raid.player, item_id)


## The pack list's drop: the world puts the item on the ground, or refuses.
func _on_pack_drop_requested(item_id: String) -> void:
	if raid == null or raid.player == null or not is_instance_valid(raid.player):
		return
	if net:
		net.drop(item_id)
	else:
		raid.drop_item(raid.player, item_id)


## The player pinged where they are looking, from the watch.
func _on_ping_requested() -> void:
	if raid == null or raid.player == null or not is_instance_valid(raid.player):
		return
	if net:
		net.ping()
	else:
		raid.ping(raid.player)


## The player picked a destination on the watch's portal icon: a squad
## portal opens in front of them, if this is a safe space. In your base the
## base opens it; in a world the world's authority does.
func _on_portal_requested(destination: String) -> void:
	var why := ""
	if _tour_refuses(Worlds.get_world(destination)):
		return
	if raid == null and base != null:
		why = base.open_portal(destination)
		if base_hud:
			base_hud.show_notice(why if why != "" else "Portal to %s open. Walk through it." % Portal.title_of(destination))
		return
	if raid == null or raid.player == null or not is_instance_valid(raid.player):
		return
	if net:
		net.open_portal(destination)
	else:
		why = raid.open_portal(raid.player, destination)
		if why != "":
			raid.player.notice.emit(why)


## Walked through a squad portal: off to `destination` (a world id or the
## arena's), landing at its gate outpost (`Raid.PORTAL_DROP`). From your own
## base solo that starts the world here; online it deploys on the server,
## by way of that world's session when it is another one. `Portal.PLAZA`
## goes out of your base the way its door does, and `Portal.HOME` from the
## plaza goes home the way its quarters door does. (A portal home out in a
## world is a sign-out, which ends in `_return_to_lobby`.)
func go_through_portal(destination: String) -> void:
	if destination == Portal.PLAZA:
		if raid == null and base != null and not base.read_only:
			_on_base_door()
		return
	if destination == Portal.HOME:
		if net != null and raid != null and raid.world.safe_zone:
			open_home_base()
		return
	if destination == Arena.ArenaVenue.ID:
		open_arena()
		return
	var world := Worlds.get_world(destination)
	if world == null or world.safe_zone or _tour_refuses(world):
		return
	if net == null:
		if raid == null and base != null and not base.read_only:
			start_raid(destination, Raid.PORTAL_DROP)
		return
	if raid == null and hub.in_lobby() and net.world_id == destination:
		hub.set_online_status("Deploying...")
		net.deploy(Raid.PORTAL_DROP)
		return
	var way := _route(destination)
	if way.is_empty():
		var why := "%s is not running on this server." % world.display_name
		if base_hud:
			base_hud.show_notice(why)
		elif plaza_view:
			plaza_view.show_notice(why)
		return
	_gate_deploy = true
	_portal_deploy = true
	if raid != null:
		_leave_raid()
	else:
		net.queue_free()
		net = null
	_show_travel("Travelling to %s..." % world.display_name)
	_begin_join(way[0], way[1], 3)


## The player asked to pack the vehicle they are looking at onto their watch.
func _on_pack_requested() -> void:
	if base != null and raid == null:
		base.pack_vehicle(base.player)
		return
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
	phone.dressing_dragged.connect(_on_dressing_dragged)
	phone.held_changed.connect(_on_phone_held)
	phone.preview_changed.connect(_on_phone_preview)
	phone.tour_requested.connect(_on_tour_requested)
	phone.host_requested.connect(_go_online_from_phone.bind(""))
	phone.join_requested.connect(_go_online_from_phone)
	phone.recover_requested.connect(func(address: String, code: String) -> void:
		_recovery_code = code
		_go_online_from_phone(address)
		if net == null:
			_recovery_code = "")
	phone.join_world_requested.connect(join_world)
	phone.leave_server_requested.connect(_leave_from_phone)
	phone.update_restart_requested.connect(_restart_for_update)
	phone.update_hold = _away_from_quiet
	hub.online_status_changed.connect(phone.set_link_status)
	bug_report = BugReportScript.new()
	bug_report.name = "BugReport"
	add_child(bug_report)
	bug_report.finished.connect(func(ok: bool, note: String) -> void: phone.set_report_status(note, ok))
	phone.report_requested.connect(func(text: String) -> void: bug_report.send(text, report_context()))
	# DEV MODE: the dev tools' keys (performance capture, bug snapshot).
	dev_tools = DevToolsScript.new()  # DEV MODE
	dev_tools.name = "DevTools"  # DEV MODE
	dev_tools.context_source = report_context  # DEV MODE
	dev_tools.body_source = func() -> Variant: return controller.actor if controller != null and is_instance_valid(controller) else null  # DEV MODE
	dev_tools.notice.connect(_dev_notice)  # DEV MODE
	add_child(dev_tools)  # DEV MODE
	phone.console_command.connect(_run_console)  # DEV MODE


## DEV MODE: a command typed on the phone's Console app.
func _run_console(line: String) -> void:
	var body: Actor = controller.actor if controller != null and is_instance_valid(controller) else null
	phone.add_console_lines(DevConsole.run(line, raid, body, net != null))


## DEV MODE: a dev tool's line, on whichever HUD is up.
func _dev_notice(text: String) -> void:
	if raid != null and hud != null and is_instance_valid(hud):
		hud.notify(text)
	elif base_hud != null and is_instance_valid(base_hud):
		base_hud.show_notice(text, 8.0)
	print(text)


## What a bug report says about where the player is and what they were
## doing (`BugReport`): plain values, never anything secret.
func report_context() -> Dictionary:
	var context := {}
	if raid != null and raid.world != null:
		context["place"] = "%s (%s)" % [raid.world.display_name, raid.world.id]
	elif base != null:
		context["place"] = "someone else's base" if base.read_only else "home base"
	else:
		context["place"] = "travelling"
	context["online"] = ("on " + phone.link_where) if net != null and phone.link_where != "" \
			else ("online" if net != null else "solo")
	var body: Actor = controller.actor if controller != null and is_instance_valid(controller) else null
	if body != null and is_instance_valid(body):
		var at := body.global_position
		context["position"] = "%.1f, %.1f, %.1f" % [at.x, at.y, at.z]
		context["view"] = "third person" if controller.is_third_person() else "first person"
		context["health"] = "%d / %d" % [int(body.health.health), int(body.health.max_health)]
	context["fps"] = "%d" % int(Engine.get_frames_per_second())
	if raid != null and raid.war != null:
		context["war"] = "%.2f" % raid.war.intensity
	if raid != null and raid.weather != null and raid.weather.active() and body != null and is_instance_valid(body):
		context["storm"] = "%s, %.2f here" % [raid.weather.kind, raid.weather.strength_at(body.global_position)]
	var life := _last_life_line()
	if life != "":
		context["last_life"] = life
	return context


## The newest line the life log wrote here (solo lives only: online the
## server keeps them), or "".
func _last_life_line() -> String:
	var dir := LifeLog.directory
	if dir == "" or not DirAccess.dir_exists_absolute(dir):
		return ""
	var newest := ""
	for name in DirAccess.get_files_at(dir):
		var path := dir.path_join(name)
		if newest == "" or FileAccess.get_modified_time(path) > FileAccess.get_modified_time(newest):
			newest = path
	if newest == "":
		return ""
	var lines := FileAccess.get_file_as_string(newest).strip_edges().split("\n")
	return lines[lines.size() - 1] if not lines.is_empty() else ""


## Hands on the phone: the character stops, raises it (everyone sees) and the
## mouse is free. Putting it away in a raid takes the mouse back.
func _on_phone_opened(open: bool) -> void:
	if controller != null and is_instance_valid(controller):
		# A station screen still open behind the phone keeps the mouse.
		var arena_hud := raid.get_node_or_null("ArenaHud") if raid != null else null
		var screen_open: bool = hub.station != "" or shop_view != null or bench_view != null \
				or (arena_hud != null and arena_hud.booth_open)
		controller.input_blocked = open or screen_open
		controller.phone_out = phone.held() if phone != null else open
		if phone != null:
			phone.set_holder(controller.actor)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if open or screen_open else Input.MOUSE_MODE_CAPTURED


## The phone went down to look in the mirror, or came back up: the hand
## follows (`ActorCommand.phone`, so everyone sees it); the phone stays
## open, so the character still stands and the mouse stays free.
func _on_phone_held(held: bool) -> void:
	if controller != null and is_instance_valid(controller):
		controller.phone_out = held


## A view setting's slider is dragged on the phone: the view shows itself
## as it really is meanwhile, so the change is seen live.
func _on_phone_preview(on: bool) -> void:
	if controller != null and is_instance_valid(controller):
		controller.phone_preview = on


# ---------------------------------------------------- new player's tour ----
# A handler messages a new player step by step on the phone (`Onboarding`),
# and the step's objective sits on the watch card and the visor. Each step
# finishes on the action itself; this section reports the actions
# (`_tour_event`) and what is already true (`_tour_check`). It is only a
# view of the player's progress and never changes a rule of the game. Dev
# mode never runs it.

## The key the tour's pop-ups go under on the phone (`Phone.show_notice`).
const TOUR_NOTICE := "tour"


## True while the tour runs here (never in dev mode).
func _tour_running() -> bool:
	return Onboarding.is_active(Profile.onboarding) and not DevMode.active()  # DEV MODE


func _tour_names() -> Dictionary:
	return Onboarding.names(PhoneScript.key_name("check_wrist"), PhoneScript.key_name("weapon_1"))


func _tour_has_messages() -> bool:
	return phone != null and phone.local_messages.any(func(m: Dictionary) -> bool:
		return m.from == Onboarding.HANDLER_ID)


## Puts the handler's messages so far on the phone (they are not saved, only
## how far the tour got) and buzzes the current objective. Does nothing if
## they are there already or the tour is not running.
func _tour_start() -> void:
	if phone == null or not _tour_running() or _tour_has_messages():
		return
	var names := _tour_names()
	var texts := Onboarding.messages(Profile.onboarding, names)
	for text in texts:
		phone.add_local_message(Onboarding.HANDLER_ID, Onboarding.HANDLER_NAME, text, "", true)
	# Only the newest is unread.
	phone.read_upto[Onboarding.HANDLER_ID] = texts.size() - 1
	phone.refresh(false)
	_tour_remind()


## The player did `event` (see `Onboarding.notify`).
func _tour_event(event: String) -> void:
	if _tour_running() and Onboarding.notify(Profile.onboarding, event):
		_tour_settle()
		_tour_moved()


## Passes every step whose action is already done: gear on, standing in the
## plaza, a contract held, out in a world. A later step already done passes
## the ones before it too (`Onboarding.catch_up`), so leaving the base before
## the test lane never leaves its step stuck on the visor.
func _tour_check() -> void:
	if _tour_running() and _tour_settle():
		_tour_moved()


## Feeds the tour what is true now until it stops moving. True if it moved.
func _tour_settle() -> bool:
	var moved := false
	var again := true
	while again and _tour_running():
		again = false
		for fact in _tour_facts():
			if Onboarding.catch_up(Profile.onboarding, fact):
				moved = true
				again = true
	return moved


func _tour_facts() -> Array[String]:
	var facts: Array[String] = []
	var kit := hub.current_loadout()
	for slot: String in ["primary", "sidearm", "melee"]:
		if str(kit.get(slot, "")) != "":
			facts.append("equipped")
			break
	if raid != null and is_instance_valid(raid) and raid.world != null and raid.world.safe_zone:
		facts.append("plaza")
	if not _held_contracts().is_empty():
		facts.append("contract")
	if _out_in_a_world():
		facts.append("deployed")
	return facts


## True while in a world where gear is at risk (not the plaza or the arena).
func _out_in_a_world() -> bool:
	return raid != null and is_instance_valid(raid) and raid.world != null and not raid.world.safe_zone \
			and raid.world.gear_at_risk and not (raid is Arena)


## The tour moved on: saved, the handler sends the next step (or the
## goodbye) and the objective changes.
func _tour_moved() -> void:
	Profile.save()
	var names := _tour_names()
	if Onboarding.is_active(Profile.onboarding):
		if not _tour_has_messages():
			_tour_start()
		else:
			phone.add_local_message(Onboarding.HANDLER_ID, Onboarding.HANDLER_NAME,
					Onboarding.fill(Onboarding.current(Profile.onboarding).message, names), "", true)
			_tour_remind()
	elif Profile.onboarding.get("state", "") == Onboarding.DONE and phone != null:
		phone.add_local_message(Onboarding.HANDLER_ID, Onboarding.HANDLER_NAME,
				Onboarding.fill(Onboarding.DONE_MESSAGE, names), "", true)
		phone.show_notice("%s: %s" % [Onboarding.HANDLER_NAME, Onboarding.fill(Onboarding.DONE_TITLE, names)],
				-1.0, TOUR_NOTICE, true)
	_tour_show()


## Pops up the step the tour is on ("Handler: <objective>"), ahead of other
## news, in place of the step before it if that was still up or waiting
## (`Phone.show_notice`'s key): a step already done is never told.
func _tour_remind() -> void:
	if phone == null:
		return
	if not _tour_running():
		phone.drop_notice(TOUR_NOTICE)
		return
	Sfx.play("phone_buzz")
	phone.show_notice("%s: %s" % [Onboarding.HANDLER_NAME, Onboarding.objective(Profile.onboarding, _tour_names())],
			-1.0, TOUR_NOTICE, true)


## A life ended: a sign-out from a world counts as getting loot home.
func _tour_life_ended(result: Dictionary) -> void:
	if result.get("outcome", "") == "left" and _out_in_a_world():
		_tour_event("banked")


## The objective on whichever HUD is up, what to press for a step with
## nothing to walk to (on the line under the crosshair), the guide's light
## and the phone's Settings button.
func _tour_show() -> void:
	var names := _tour_names()
	var line := Onboarding.objective(Profile.onboarding, names) if _tour_running() else ""
	var hint := Onboarding.hint(Profile.onboarding, names) if _tour_running() else ""
	if hud != null and is_instance_valid(hud):
		hud.objective = line
		hud.tour_hint = hint
	if base_hud != null and is_instance_valid(base_hud):
		base_hud.objective = line
		base_hud.tour_hint = hint
	if phone != null:
		phone.tour_running = _tour_running()
	if plaza_view != null and is_instance_valid(plaza_view):
		var closed: Array = []
		if _tour_running():
			for world in Worlds.raid_worlds():
				if Onboarding.locks(Profile.onboarding, world):
					closed.append(world.id)
		plaza_view.tour_closed = closed
	# Look again for what the guide points at.
	_tour_guide_look = 0.0


## Where the player is now: the base or the world, or null between places.
func _tour_place() -> Node3D:
	if raid != null and is_instance_valid(raid):
		return raid
	if base != null and is_instance_valid(base) and not base.read_only:
		return base
	return null


## True (and the handler says why, on the phone) if the tour keeps `world`
## closed: a full-loot world before the tour is finished or skipped
## (`Onboarding.locks`). Dev mode never runs the tour, so never locks.
func _tour_refuses(world: WorldDef) -> bool:
	if world == null or not _tour_running() or not Onboarding.locks(Profile.onboarding, world):
		return false
	if phone != null:
		Sfx.play("phone_buzz")
		phone.show_notice("%s: %s" % [Onboarding.HANDLER_NAME, Onboarding.fill(Onboarding.LOCKED_MESSAGE, _tour_names())],
				-1.0, "tour_locked", true)
	return true


## The player's own body where they are, or null.
func _tour_body() -> Actor:
	var place := _tour_place()
	if place == raid and place != null:
		return raid.player
	if place == base and place != null:
		return base.player
	return null


## Keeps the guide's light over what the current step points at
## (`Onboarding.mark`), looked for again every `TourGuide.LOOK_EVERY`, and
## takes it away when there is nothing (no tour, nothing to walk to, or the
## thing is not in this place).
func _tour_guide_tick(delta: float) -> void:
	var place := _tour_place()
	var body := _tour_body()
	var running := _tour_running() and place != null and body != null and is_instance_valid(body)
	if not running:
		_drop_tour_guide()
		return
	_tour_guide_look -= delta
	if _tour_guide_look <= 0.0 or _tour_guide == null or not is_instance_valid(_tour_guide):
		_tour_guide_look = TourGuide.LOOK_EVERY
		var route := _tour_route(Onboarding.mark(Profile.onboarding, _tour_names()), place)
		var at: Variant = _tour_mark_at(route[0], place, body)
		if at == null:
			_drop_tour_guide()
			return
		if _tour_guide == null or not is_instance_valid(_tour_guide) or _tour_guide.get_parent() != place:
			_drop_tour_guide()
			_tour_guide = TourGuide.new()
			_tour_guide.name = "TourGuide"
			place.add_child(_tour_guide)
		_tour_guide.target = at
		_tour_guide.text = route[1]
	_tour_guide.follow(body.global_position, delta)


func _drop_tour_guide() -> void:
	if _tour_guide != null and is_instance_valid(_tour_guide):
		_tour_guide.queue_free()
	_tour_guide = null


## Where the guide goes for `mark` from `place`, and what it says:
## [mark, words]. A step done out in a world, seen from where that world is
## not, leads the way there: from the base to its way out, and from a safe
## zone to the gentle world's gate (a save left on "bank" at home, Caleb's
## "the markers don't show"), with the step and that leg written over it.
func _tour_route(mark: String, place: Node3D) -> Array:
	var names := _tour_names()
	var objective := Onboarding.objective(Profile.onboarding, names)
	var out_there := mark == "depot" or mark.begins_with("portal:")
	if place == base and out_there:
		return ["door", "%s\nOut to %s first" % [objective, names.plaza]]
	var safe := place == raid and raid != null and raid.world != null and raid.world.safe_zone
	if safe and mark == "depot" and str(names.gentle_id) != "":
		return ["portal:world:%s" % names.gentle_id, "%s\nThrough the gate to %s" % [objective, names.gentle]]
	return [mark, objective]


## Where in `place` the step's `mark` is (see `Onboarding.STEPS`), or null
## when it is not there: a weapon on show not on yet, the test lane's
## plates, the base's way out, a safe zone's portal by destination, or the
## depot or gate outpost nearest `body`.
func _tour_mark_at(mark: String, place: Node3D, body: Actor) -> Variant:
	if mark == "":
		return null
	if place == base:
		match mark:
			"gear":
				# Gear the player owns first (the welcome crate's rifle the
				# handler names), else any weapon on show.
				var owned := hub.stash_items()
				var fallback: Variant = null
				for display in base.displays:
					if is_instance_valid(display) and not display.equipped \
							and display.slot in ["primary", "sidearm", "melee"]:
						if display.item_id in owned:
							return display.global_position
						if fallback == null:
							fallback = display.global_position
				return fallback
			"lane":
				var plates: Array = base.lane_targets.filter(func(target: Variant) -> bool:
					return is_instance_valid(target))
				if not plates.is_empty():
					return (plates[plates.size() / 2] as Node3D).global_position
			"door":
				if base.door != null and is_instance_valid(base.door):
					return base.door.global_position
		return null
	if mark.begins_with("portal:"):
		var destination := mark.trim_prefix("portal:")
		for node in get_tree().get_nodes_in_group("portal"):
			if node is Node3D and place.is_ancestor_of(node) and str(node.get_meta("destination", "")) == destination:
				return (node as Node3D).global_position
		return null
	if mark == "depot":
		var best: Variant = null
		var best_d := INF
		for group: String in ["depot", "outpost"]:
			for node in get_tree().get_nodes_in_group(group):
				if node is Node3D and place.is_ancestor_of(node):
					var d := body.global_position.distance_squared_to((node as Node3D).global_position)
					if d < best_d:
						best_d = d
						best = (node as Node3D).global_position
		return best
	return null


## The phone's Settings asked to skip the tour or play it again.
func _on_tour_requested(action: String) -> void:
	match action:
		"skip":
			if not Onboarding.is_active(Profile.onboarding):
				return
			Onboarding.skip(Profile.onboarding)
			Profile.save()
			phone.add_local_message(Onboarding.HANDLER_ID, Onboarding.HANDLER_NAME, Onboarding.SKIP_MESSAGE)
		"replay":
			Onboarding.restart(Profile.onboarding)
			Profile.save()
			phone.clear_local_messages(Onboarding.HANDLER_ID)
			_tour_start()
			_tour_check()
	_tour_show()


# ---------------------------------------------------------------- mirror ----

## The local player's character wherever they stand: a world, or the home base.
func _my_actor() -> Actor:
	if raid != null and is_instance_valid(raid) and raid.player != null and is_instance_valid(raid.player):
		return raid.player
	if base != null and is_instance_valid(base) and base.player != null and is_instance_valid(base.player):
		return base.player
	return null


## The phone's Mirror app came up or went away. Up, first person gets a
## mirror standing in front of the player, wherever they are, and third
## person a dressing room (Caleb's pick): the camera swings round in front
## of the character (`PlayerController.dressing_room`) with the phone's
## hologram beside them. Either way a soft light stands in front so the
## outfit is seen whatever the sun is doing (`dressing_light`). It goes
## when the app or the phone does.
func _on_mirror_changed(up: bool) -> void:
	_put_away_mirror()
	if not up:
		_wardrobe_glass = null
	var me := _my_actor()
	if not up or me == null or me.is_dead or controller == null or not is_instance_valid(controller) \
			or controller.actor != me:
		phone.set_mirror_up(false)
		return
	_show_aim(false)
	_dressing_light = _make_dressing_light(me)
	if controller.active_view() == PlayerController.ViewMode.THIRD:
		controller.dressing_room = true
		controller.dressing_turn = 0.0
		phone.dressing = true
		phone.set_mirror_up(false)
		phone.refresh()
		return
	# Level the gaze so the glass is in view. The camera mode stays as it is.
	controller.pitch = clampf(controller.pitch, -0.15, 0.05)
	if _wardrobe_glass != null and is_instance_valid(_wardrobe_glass) and _wardrobe_glass.is_inside_tree() \
			and _wardrobe_glass.global_position.distance_to(me.global_position) < 4.0:
		controller.phone_mirror = _wardrobe_glass
		phone.set_mirror_up(true)
		return
	mirror = MirrorScript.new()
	mirror.name = "Mirror"
	mirror.setup(me, controller.camera)
	me.get_parent().add_child(mirror)
	controller.phone_mirror = mirror
	phone.set_mirror_up(true)


func _put_away_mirror() -> void:
	if mirror != null and is_instance_valid(mirror):
		mirror.queue_free()
	mirror = null
	if _dressing_light != null and is_instance_valid(_dressing_light):
		_dressing_light.queue_free()
	_dressing_light = null
	if phone != null:
		phone.dressing = false
	if controller != null and is_instance_valid(controller):
		controller.phone_mirror = null
		controller.dressing_room = false
	_show_aim(true)


## Switching view with the Mirror app up swaps the mirror for the dressing
## room or back.
func _keep_mirror_view() -> void:
	if phone == null or not phone.mirror_open() or controller == null or not is_instance_valid(controller):
		return
	var third := controller.active_view() == PlayerController.ViewMode.THIRD
	var glass_up := mirror != null or (controller.phone_mirror != null and is_instance_valid(controller.phone_mirror))
	if (glass_up or phone.dressing) and third != phone.dressing:
		_on_mirror_changed(true)


## A drag beside the phone in the dressing room turns the view round you.
func _on_dressing_dragged(pixels: float) -> void:
	if controller != null and is_instance_valid(controller):
		controller.dressing_turn = wrapf(controller.dressing_turn - pixels * dressing_turn_per_pixel, -PI, PI)


## A soft light in front of the character at chest height, view only, so
## the Mirror app shows the outfit lit even with the sun behind them.
func _make_dressing_light(me: Actor) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.name = "DressingLight"
	light.light_energy = dressing_light_energy
	light.omni_range = 4.0
	light.shadow_enabled = false
	var ahead := Basis(Vector3.UP, controller.yaw) * Vector3.FORWARD
	me.get_parent().add_child(light)
	light.global_position = me.global_position + Vector3.UP * 1.6 + ahead * 1.3
	return light


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
		# The save swaps once you are home, never while a server you host is
		# still sending your account back (that is how dev gear would leak).
		phone.show_notice("Online, dev mode comes with a server you host from here. Leave and host again to pick this up.")
		return
	if raid != null:
		if net == null:
			raid.set_dev_cheats(DevMode.raid_cheats())
		return
	Profile.apply_dev_mode()
	hub.refresh_gear()
	_refresh_base()
	# The tour pauses in dev mode and picks up again after it.
	_tour_start()
	_tour_show()


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
		controller.eye_pullback = GameSettings.eye_pullback
	if nameplates != null and is_instance_valid(nameplates):
		nameplates.visible = GameSettings.show_nameplates


## Accepted an invite to this server's raid: deploy from the lobby.
func _on_world_invite_accepted(invite: Dictionary) -> void:
	join_world(str(invite.get("world_id", "")))


## Goes to the world `world_id` on this server, where a friend or squadmate
## is (the phone's Join, or an accepted world invite): from the plaza, the
## arena or your base the way a squad portal goes (`go_through_portal`),
## landing with your squad at the gate outpost; to the plaza through the
## base's door. Out in a world where gear is at stake you sign out first,
## because there is no way out of a world but a sign-out.
func join_world(world_id: String) -> void:
	var world := Worlds.get_world(world_id)
	if _tour_refuses(world):
		return
	if net == null:
		phone.show_notice("Join a server first, from the Servers app.")
		return
	if world == null:
		phone.show_notice("That world is not running on this server.")
		return
	if raid != null and raid.world.id == world_id:
		phone.show_notice("You are already in %s." % world.display_name)
		return
	if raid != null and raid.world.gear_at_risk and not raid.world.safe_zone and not (raid is Arena):
		phone.show_notice("Sign out first, then join them in %s." % world.display_name)
		return
	phone.close()
	if world.safe_zone:
		if raid == null and base != null and not base.read_only:
			_on_base_door()
		elif raid is Arena:
			leave_arena()
		else:
			phone.show_notice("Head out to %s from your base's door." % world.display_name)
		return
	go_through_portal(world_id)


## Accepted an invite to someone's home base.
func _on_base_visit_requested(owner_name: String, owner_stash: Array, owner_loadout: Dictionary,
		owner_upgrades: Array = [], owner_plan := {}) -> void:
	if raid != null:
		phone.show_notice("Finish this run first, then visit %s's base." % owner_name)
		return
	# In a base (yours or someone else's): walk out and into theirs.
	leave_base()
	phone.close()
	visit_base(owner_name, owner_stash, owner_loadout, owner_upgrades, owner_plan)


# ---------------------------------------------------------------- online ----

func _run_dedicated_server(args: PackedStringArray) -> void:
	var port := int(_arg(args, "--port", str(NetSession.DEFAULT_PORT)))
	# DEV MODE: `--dev-host` gives the host (whoever claims `--host-profile`
	# with its secret) the dev stash, only on a server run from the editor,
	# and keeps this server's accounts apart.
	var dev_host := "--dev-host" in args and DevMode.available()
	var accounts := _arg(args, "--accounts", DEV_ACCOUNTS if dev_host else "")
	# `--no-zone-rules`: no gate shelter and no hazards (the test suite's servers).
	if "--no-zone-rules" in args:
		Raid.zone_rules = false
	# An official server keeps no accounts of its own: `--account-url` names
	# the account service it shares them through (DESIGN.md section 14).
	var service_url := _arg(args, "--account-url", "")
	if service_url != "":
		var folder := accounts if accounts != "" else "user://accounts"
		account_link = AccountLink.new()
		account_link.name = "AccountLink"
		account_link.url = service_url
		account_link.save_dir = folder
		account_link.server_id = _arg(args, "--server-id", _arg(args, "--only", "server-%d" % port))
		account_link.key = AccountService.load_key(_arg(args, "--service-key", folder.path_join(AccountService.KEY_FILE)))
		if account_link.key == "":
			push_error("Server: no service key for the account service (set %s or pass --service-key <file>)"
					% AccountService.KEY_ENV)
			get_tree().quit(1)
			return
		add_child(account_link)
		print("Server: accounts are kept by the account service at %s (this server is %s)"
				% [service_url, account_link.server_id])
	var err: Error
	var only := _arg(args, "--only", "")
	if only != "":
		# One world and nothing else in this program (DESIGN.md section 14,
		# "Scaling"): the plaza, a raid world or the arena, by its id.
		err = start_one(only, port, int(_arg(args, "--bots", "-1")), "--squad-spawn" in args, accounts,
				"--no-rewind" not in args, _arg(args, "--public-host", ""))
	else:
		err = start_server(_arg(args, "--world", ""), port, "--no-plaza" not in args,
				int(_arg(args, "--bots", "-1")), "--squad-spawn" in args, accounts,
				"--no-rewind" not in args,
				-1 if "--no-arena" in args else int(_arg(args, "--arena-port", str(port + ARENA_PORT_OFFSET))))
	if err != OK:
		push_error("Server: could not listen from port %d (%s)" % [port, error_string(err)])
		get_tree().quit(1)
		return
	var health_every := float(_arg(args, "--health-log", "60"))
	if health_every > 0.0:
		var health := ServerHealth.new()
		health.interval = health_every
		health.sessions = sessions
		add_child(health)
	# A server started by a game (`host_and_join`) stops with that game, so a
	# game stopped from the editor or crashed never leaves one holding the
	# ports for the next: the game keeps touching its heartbeat file, and once
	# that goes stale the server quits.
	var heartbeat := _arg(args, "--heartbeat", "")
	if heartbeat != "":
		var watch := Timer.new()
		watch.name = "HeartbeatWatch"
		watch.wait_time = 2.0
		watch.autostart = true
		var stale_after := float(_arg(args, "--heartbeat-stale", str(HEARTBEAT_STALE)))
		watch.timeout.connect(func() -> void:
			if heartbeat_stale(heartbeat, -1.0, stale_after):
				print("Server: the game that started this server is gone; stopping")
				get_tree().quit())
		add_child(watch)
	var handed := _arg(args, "--host-profile", "")
	if handed != "" and FileAccess.file_exists(handed):
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(handed))
		DirAccess.remove_absolute(handed)
		# Only a server with accounts of its own takes on its host's profile:
		# the shared accounts are never fed from a local save.
		if data is Dictionary and not net.stash.is_remote():
			net.stash.host_profile = data
	if dev_host and not net.stash.is_remote() and not net.stash.host_profile.is_empty():  # DEV MODE
		net.stash.dev_host = true
		print("Server: dev mode for the host (accounts in %s)" % accounts)


## Runs the account service, the program official servers share their
## accounts through (`core/account/account_service.gd`): `-- --account-service`
## with `--port`, `--accounts <folder>` and `--bind <address>` ("*" to listen
## beyond this computer). No world runs here and no player connects.
func _run_account_service(args: PackedStringArray) -> void:
	var service := AccountService.new()
	service.name = "AccountService"
	var folder := _arg(args, "--accounts", "")
	if folder != "":
		service.stash.save_dir = folder
	service.bind = _arg(args, "--bind", service.bind)
	var key_file := _arg(args, "--service-key", "")
	if key_file != "":
		service.key = AccountService.load_key(key_file, true)
	add_child(service)
	var port := int(_arg(args, "--port", str(AccountService.DEFAULT_PORT)))
	var err := service.start(port)
	if err != OK:
		push_error("AccountService: could not start on port %d (%s)" % [port, error_string(err)])
		get_tree().quit(1)
		return
	var store: RefCounted = service.stash.store()
	print("AccountService: listening on %s:%d, accounts in %s (%s)" % [service.bind, port,
			ProjectSettings.globalize_path(service.stash.save_dir), store.kind if store != null else "not saved"])
	print("AccountService: game servers need the key in %s" % ProjectSettings.globalize_path(
			key_file if key_file != "" else service.stash.save_dir.path_join(AccountService.KEY_FILE)))


## Starts every session of a server. With a plaza it listens on `port`, and
## the raid worlds follow on the next ports; without one, a single world runs
## on `port`. `world_id` "" runs every raid world (the first one only when
## there is no plaza to reach the others from). All sessions share one stash
## service, so an account is the same wherever it shows up. The arena runs on
## `arena_port` (below zero: no arena). Every session knows the way to the
## others (`NetSession.routes`), so a portal opened anywhere can lead on.
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
		session.routes = routes
		if sessions.is_empty():
			if account_link != null:
				session.stash = account_link
			elif accounts != "":
				session.stash.save_dir = accounts
		else:
			session.stash = sessions[0].stash
			session.social = sessions[0].social
			session.clans = sessions[0].clans
			session.market = sessions[0].market
		add_child(session)
		var err := session.host(world.id, next_port, world.max_players)
		if err != OK:
			return err
		print("Server: running %s on port %d" % [world.id, next_port])
		routes[world.id] = next_port
		sessions.append(session)
		next_port += 1
	net = sessions[0]
	# Open the accounts now (importing old account files once), not at the
	# first sign-in, so the log says where they are kept.
	var store: RefCounted = net.stash.store()
	if store != null:
		print("Server: accounts in %s (%s)" % [ProjectSettings.globalize_path(store.dir), store.kind])
	# The launch holds the Pit back (`LaunchScope`): no arena session at all.
	if arena_port >= 0 and not LaunchScope.holds("arena"):
		var arena := NetSession.new()
		arena.name = "Net_%s" % Arena.ArenaVenue.ID
		arena.isolated = true
		arena.stash = net.stash
		arena.social = net.social
		arena.clans = net.clans
		arena.market = net.market
		arena.lag_compensation = rewind
		arena.routes = routes
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
		session.market = net.market
		session.routes = routes
		add_child(session)
		var err := session.host(plaza.id, port, PLAZA_PLAYERS)
		if err != OK:
			return err
		print("Server: running %s on port %d" % [plaza.id, port])
		routes[plaza.id] = port
		sessions.push_front(session)
	return OK


## Starts the one session of a program that runs a single world: the plaza,
## a raid world or the arena, by its id, on `port`. With an account service
## (`--account-url`) it finds the other worlds through the service's
## directory and they find it, each a program of its own; without one it is
## a world alone. `public_host` is the address players reach it at when
## that is not the one the other worlds are on.
func start_one(world_id: String, port: int, bots := -1, squad := false, accounts := "", rewind := true,
		public_host := "") -> Error:
	var world := NetSession.world_for(world_id)
	if world == null:
		push_error("Server: there is no world called %s" % world_id)
		return ERR_DOES_NOT_EXIST
	var session := NetSession.new()
	session.name = "Net"
	session.bot_count = bots
	session.squad_spawn = squad
	session.lag_compensation = rewind
	session.public_host = public_host
	if account_link != null:
		session.stash = account_link
	elif accounts != "":
		session.stash.save_dir = accounts
	add_child(session)
	var err := session.host(world.id, port, PLAZA_PLAYERS if world.safe_zone else world.max_players)
	if err != OK:
		return err
	print("Server: running %s on port %d" % [world.id, port])
	sessions.append(session)
	net = session
	var store: RefCounted = net.stash.store()
	if store != null:
		print("Server: accounts in %s (%s)" % [ProjectSettings.globalize_path(store.dir), store.kind])
	return OK


## `-- --server --cluster`: every world as a program of its own on this
## machine (DESIGN.md section 14, "Scaling"), so each uses a processor core
## of its own and a crash takes down one world, not all of them. This
## program is the account service (accounts, clans, phone records, the
## market and the directory of worlds) and starts the rest: the plaza on
## `--port`, each raid world on the ports after it and the arena ten above,
## the same ports a server that runs everything in one program uses. A world
## that stops is started again. `--world <id>` runs only that raid world
## behind the plaza; `--bots`, `--squad-spawn`, `--no-zone-rules`,
## `--no-rewind`, `--health-log`, `--public-host` and `--no-arena` go to the
## worlds. The service listens on `--account-port`, on this machine only.
func _run_cluster(args: PackedStringArray) -> void:
	var port := int(_arg(args, "--port", str(NetSession.DEFAULT_PORT)))
	var folder := _arg(args, "--accounts", "user://accounts")
	var service_port := int(_arg(args, "--account-port", str(AccountService.DEFAULT_PORT)))
	var service := AccountService.new()
	service.name = "AccountService"
	service.stash.save_dir = folder
	add_child(service)
	var err := service.start(service_port)
	if err != OK:
		push_error("Cluster: the account service could not start on port %d (%s)" % [service_port, error_string(err)])
		get_tree().quit(1)
		return
	print("Cluster: account service on port %d, accounts in %s" % [service_port,
			ProjectSettings.globalize_path(folder)])
	# The worlds share one certificate, made here before any of them starts,
	# so a game that travels between them meets the server it remembers.
	var servers := ProjectSettings.globalize_path(folder.path_join("servers"))
	DirAccess.make_dir_recursive_absolute(servers)
	ServerTrust.identity(servers.path_join("server_identity"))
	var heartbeat := servers.path_join("cluster_heartbeat")
	var shared := PackedStringArray(["--accounts", servers,
			"--account-url", "ws://127.0.0.1:%d" % service_port,
			"--service-key", ProjectSettings.globalize_path(folder.path_join(AccountService.KEY_FILE)),
			"--heartbeat", heartbeat, "--heartbeat-stale", str(CLUSTER_HEARTBEAT_STALE)])
	for flag in ["--squad-spawn", "--no-zone-rules", "--no-rewind"]:
		if flag in args:
			shared.append(flag)
	for flag in ["--health-log", "--public-host"]:
		if _arg(args, flag, "") != "":
			shared.append_array([flag, _arg(args, flag, "")])
	var plaza := Worlds.social_world()
	var worlds: Array[WorldDef] = []
	var named := Worlds.get_world(_arg(args, "--world", ""))
	if named != null and not named.safe_zone:
		worlds.append(named)
	else:
		worlds = Worlds.raid_worlds()
	var programs: Array[Dictionary] = []
	if plaza != null:
		programs.append({"id": plaza.id, "port": port, "args": shared})
	var next_port := port + 1
	for world in worlds:
		var world_args := shared.duplicate()
		if _arg(args, "--bots", "") != "":
			world_args.append_array(["--bots", _arg(args, "--bots", "")])
		programs.append({"id": world.id, "port": next_port, "args": world_args})
		next_port += 1
	if "--no-arena" not in args and not LaunchScope.holds("arena"):
		programs.append({"id": Arena.ArenaVenue.ID, "port": int(_arg(args, "--arena-port",
				str(port + ARENA_PORT_OFFSET))), "args": shared})
	var beat := func() -> void:
		var file := FileAccess.open(heartbeat, FileAccess.WRITE)
		if file != null:
			file.store_string(str(Time.get_unix_time_from_system()))
			file.close()
	beat.call()
	for program in programs:
		_cluster_start(program)
	# The worlds stop when this program does (their heartbeat), and one that
	# stops by itself is started again.
	var watch := Timer.new()
	watch.name = "ClusterWatch"
	watch.wait_time = 1.0
	watch.autostart = true
	watch.timeout.connect(func() -> void:
		beat.call()
		for program in programs:
			if (int(program.pid) <= 0 or not OS.is_process_running(int(program.pid))) \
					and Time.get_ticks_msec() - int(program.started) > CLUSTER_RESTART_AFTER * 1000.0:
				print("Cluster: %s stopped; starting it again" % program.id)
				_cluster_start(program))
	add_child(watch)
	_cluster = programs


## Starts (again) one world's program of a cluster.
func _cluster_start(program: Dictionary) -> void:
	var args := server_process_args(PackedStringArray(["--server", "--only", str(program.id),
			"--port", str(program.port), "--server-id", str(program.id)]))
	args.append_array(program.args)
	program["pid"] = OS.create_process(OS.get_executable_path(), args)
	program["started"] = Time.get_ticks_msec()
	print("Cluster: %s on port %d (process %d)" % [program.id, program.port, program.pid])


## The command line that starts this program again as a headless server
## with the game's own arguments `user_args`. From the editor or a checkout
## it names the project with `--path`; an exported game never does, because
## release templates refuse `--path` and stop at once (the installed game's
## "server stopped before it was ready"), and it finds its pack beside the
## exe without one.
static func server_process_args(user_args: PackedStringArray, exported := OS.has_feature("template")) -> PackedStringArray:
	var args := PackedStringArray(["--headless"])
	if not exported:
		args.append_array(["--path", ProjectSettings.globalize_path("res://")])
	args.append("--")
	args.append_array(user_args)
	return args


## Starts a server on this machine as a second process, then joins it.
## `world_id` "" runs every world behind the plaza's gates, which is what the
## base's door and the phone's Servers app ask for; naming one runs only that world.
func host_and_join(world_id := "") -> void:
	if raid != null or net != null:
		return
	_door_fallback = false
	_remember_address = ""
	_host_restarts_left = HOST_RESTARTS
	_start_local_server(world_id)


## Starts the server for `host_and_join` (again, on a retry) and joins it.
func _start_local_server(world_id: String) -> void:
	_host_world = world_id
	_stop_local_server()
	# A server an earlier game left running (stopped from the editor, or a
	# crash) may still hold the ports: joining it would wait on a server that
	# is not ours, so this one moves to free ports instead.
	var port := free_host_port(host_port, _ports_needed(world_id))
	if port < 0:
		hub.set_online_status("Could not start a server: its ports are in use on this computer.")
		return
	var args := server_process_args(PackedStringArray(["--server", "--port", str(port),
			# The server stops when this game does, however this game ends.
			"--heartbeat", ProjectSettings.globalize_path(HOST_HEARTBEAT)]))
	_beat()
	args.append_array(host_args)
	if world_id != "":
		args.append_array(["--world", world_id])
	if DevMode.active():  # DEV MODE: your account gets everything on your own server
		args.append("--dev-host")
	# The save this server's snapshots may go back into (see `_keep_profile_in_step`).
	_hosted_save = Profile.save_path
	# On your own server you are the player you are at home: it takes on your
	# profile (loadout, stash, scrip...), and hands it back as you play.
	Profile.get_online_secret()
	var handoff := FileAccess.open(HOST_PROFILE, FileAccess.WRITE)
	if handoff != null:
		handoff.store_string(JSON.stringify(Profile.to_dict()))
		handoff.close()
		args.append_array(["--host-profile", ProjectSettings.globalize_path(HOST_PROFILE)])
	_server_pid = OS.create_process(OS.get_executable_path(), args)
	if _server_pid <= 0:
		hub.set_online_status("Could not start a server on this computer.")
		return
	hub.set_online_status("Starting a server...")
	_join_deadline = Time.get_ticks_msec() + int(HOST_JOIN_DEADLINE * 1000.0)
	_begin_join("127.0.0.1", port, HOST_JOIN_ATTEMPTS)


## The ports a server of your own listens on from `port`: the plaza, every
## raid world after it (just one with `world_id`) and the arena.
func _ports_needed(world_id: String) -> Array[int]:
	var count := 1 if world_id != "" else Worlds.raid_worlds().size()
	var offsets: Array[int] = []
	for i in count + 1:
		offsets.append(i)
	offsets.append(ARENA_PORT_OFFSET)
	return offsets


## The first base port from `port`, stepping by `HOST_PORT_STEP`, whose
## `offsets` are all free to listen on here; -1 if none is.
static func free_host_port(port: int, offsets: Array[int]) -> int:
	for attempt in HOST_PORT_TRIES:
		var base := port + attempt * HOST_PORT_STEP
		var free := true
		for offset in offsets:
			if not port_free(base + offset):
				free = false
				break
		if free:
			return base
	return -1


## Whether a server could listen on this UDP port here.
static func port_free(port: int) -> bool:
	var udp := PacketPeerUDP.new()
	var ok := udp.bind(port) == OK
	udp.close()
	return ok


## `address` is "host" or "host:port". With `remember` the base's door leads
## there from now on, once the server has let you in.
func join_online(address: String, remember := true) -> void:
	if raid != null or net != null:
		return
	_door_fallback = _door_fallback and not remember
	_remember_address = address.strip_edges() if remember else ""
	var host := address.strip_edges()
	var port := NetSession.DEFAULT_PORT
	if ":" in host:
		port = int(host.get_slice(":", 1))
		host = host.get_slice(":", 0)
	if host == "":
		hub.set_online_status("Type the server's address first.")
		return
	hub.set_online_status("Connecting to %s..." % host)
	_join_deadline = 0
	_begin_join(host, port, 1)


func _begin_join(host: String, port: int, attempts: int) -> void:
	phone.link_where = "your own server" if host == "127.0.0.1" and _server_pid > 0 \
			else (_plaza_address if _plaza_port >= 0 and _plaza_address != "" else host)
	_join_address = host
	_join_port = port
	_join_attempts = attempts
	_try_join()


func _try_join() -> void:
	_join_attempts -= 1
	# Already connected ahead of this trip (`_connect_ahead`): that session
	# carries on as this one, signed in or about to be.
	var ahead := _take_ahead(_join_address, _join_port)
	net = ahead if ahead != null else _new_session(_join_address)
	if ahead == null:
		add_child(net)
	net.signed_in.connect(_on_online_signed_in)
	net.account_changed.connect(_on_online_account_changed)
	net.lobby_error.connect(func(reason: String) -> void:
		hub.set_online_status(reason)
		if _gate_deploy and raid == null:
			# The gate could not drop you in: wait in that world's lobby.
			_gate_deploy = false
			_portal_deploy = false
			go_home()
		if base_hud:
			base_hud.show_notice(reason)
		if shop_view != null and is_instance_valid(shop_view) and shop_view.panel.has_method("show_message"):
			shop_view.panel.call("show_message", reason)
		if raid != null and hud != null and is_instance_valid(hud):
			hud.notify(reason))
	net.joined.connect(_on_online_joined)
	net.failed.connect(_on_online_failed)
	net.disconnected.connect(_on_online_disconnected)
	net.run_finished.connect(_on_online_finished)
	net.world_invite_accepted.connect(_on_world_invite_accepted)
	net.base_visit_requested.connect(_on_base_visit_requested)
	net.portal_travel.connect(func(destination: String) -> void: go_through_portal.call_deferred(destination))
	phone.set_session(net)
	if ahead == null:
		var err := net.join(_join_address, _join_port)
		if err != OK:
			_on_online_failed("Could not open a connection (%s)." % error_string(err))
			return
	elif not net.account.is_empty():
		# It signed in while you were still on your way.
		_on_online_signed_in.call_deferred(net.account)
	# A server that never answers should not leave the hub waiting forever.
	# By id: the session may be gone by then (a trip through a gate frees it).
	var session := net.get_instance_id()
	get_tree().create_timer(RECONNECT_TIMEOUT if _reconnect_until > 0 else JOIN_TIMEOUT).timeout.connect(func() -> void:
		if net != null and net.get_instance_id() == session and net.account.is_empty():
			_on_online_failed("The server did not answer."))


## A session for the server at `host`, signing in as this player. Not in
## the tree and not connecting yet.
func _new_session(host: String) -> NetSession:
	var session := NetSession.new()
	session.name = "Net"
	session.player_name = Profile.player_name
	session.secret = Profile.get_online_secret()
	# Travelling on within the same servers: the token the last one gave.
	session.ticket = str(_tickets.get(host, ""))
	session.recovery = _recovery_code
	session.look = Profile.appearance
	# `-- --lag 120 --loss 10 --jitter 60` fakes a bad connection:
	# milliseconds of delay each way, the percent of input packets lost, and
	# up to that many more milliseconds, unevenly, on the server's updates.
	var args := OS.get_cmdline_user_args()
	session.simulated_lag = float(_arg(args, "--lag", "0")) / 1000.0
	session.simulated_loss = float(_arg(args, "--loss", "0")) / 100.0
	session.simulated_jitter = float(_arg(args, "--jitter", "0")) / 1000.0
	return session


# ------------------------------------------------------- travel ahead ----
# Travel that hides its wait (DESIGN.md section 14). While you stand at a
# gate, or a portal you may use is open, or your sign-out is counting down,
# the game already connects and signs in to where that leads, on a second
# session that does nothing else, and has the destination's ground worked
# out on another thread. Stepping through then only waits for the deploy,
# behind a short fade. The session is dropped again if you never go.

## Where the player looks about to travel: [host, port, world id], or [].
func _trip_ahead() -> Array:
	if net == null or net.account.is_empty() or _reconnect_until > 0 or _join_attempts > 0:
		return []
	var destination := ""
	if raid != null and raid.player != null and is_instance_valid(raid.player) and not raid.player.is_dead:
		var me := raid.player
		for portal in raid.portals:
			if is_instance_valid(portal) and portal.usable and portal.is_open() and not portal.signs_out \
					and portal.global_position.distance_to(me.global_position) < ahead_range * 2.0:
				destination = portal.destination
		if destination == "" and raid.world.safe_zone:
			# The nearest doorway that leads to another server (not a shop).
			var nearest := ahead_range
			for node in get_tree().get_nodes_in_group("portal"):
				var gate := node as Node3D
				if gate == null or raid.map == null or not raid.map.is_ancestor_of(gate):
					continue
				var gap := gate.global_position.distance_to(me.global_position)
				var leads := str(gate.get_meta("destination", ""))
				if gap < nearest and not _where_leads(leads).is_empty():
					nearest = gap
					destination = leads
		var state := raid.state_for(me)
		if destination == "" and state != null and state.sign_out_left >= 0.0 and not raid.world.safe_zone \
				and not raid is Arena:
			# Signing out: back to the plaza, unless a portal out of the world
			# you are signing out through (the nearest open one of your side)
			# leads on somewhere else.
			destination = Portal.PLAZA
			var nearest := ahead_range
			for portal in raid.portals:
				if is_instance_valid(portal) and portal.usable and portal.signs_out \
						and portal.global_position.distance_to(me.global_position) < nearest:
					nearest = portal.global_position.distance_to(me.global_position)
					destination = portal.destination
	elif raid == null and base != null and hub.in_lobby() and base.portal != null and is_instance_valid(base.portal):
		destination = base.portal.destination
	return _where_leads(destination)


## Where a doorway's or a portal's `destination` is served: [host, port,
## world id], or [] when it leads nowhere else (a shop, the world you are
## already signed in to).
func _where_leads(destination: String) -> Array:
	var way: Array = []
	var world_id := destination.trim_prefix("world:")
	if destination == "":
		return []
	elif destination == Portal.PLAZA:
		if _plaza_port >= 0 and not _at_plaza():
			way = [_plaza_address, _plaza_port]
			world_id = Worlds.social_world().id if Worlds.social_world() != null else ""
	elif destination == Portal.HOME or destination == "home":
		way = _home_route()
		world_id = ""
	elif world_id == Arena.ArenaVenue.ID or (Worlds.get_world(world_id) != null and world_id != net.world_id):
		way = _route(world_id)
	if way.is_empty() or (way[0] == _join_address and way[1] == _join_port):
		return []
	return [way[0], way[1], world_id]


func _tick_ahead(delta: float) -> void:
	var want := _trip_ahead()
	if _ahead != null:
		if not is_instance_valid(_ahead):
			_ahead = null
		elif not want.is_empty() and want[0] == _ahead_host and want[1] == _ahead_port:
			_ahead_unused = 0.0
		else:
			_ahead_unused += delta
			if not want.is_empty() or _ahead_unused > ahead_linger:
				_drop_ahead()
	if _ahead == null and not want.is_empty():
		_connect_ahead(want[0], want[1], want[2])


## Connects and signs in to `host`:`port` without going there, and has the
## ground of `world_id` worked out meanwhile.
func _connect_ahead(host: String, port: int, world_id := "") -> void:
	var world := Worlds.get_world(world_id)
	if world != null and not _prepared.has(world_id):
		_prepared[world_id] = true
		WorkerThreadPool.add_task(world.prepare_map, false, "Preparing %s" % world_id)
	var key := "%s:%d" % [host, port]
	if Time.get_ticks_msec() < int(_ahead_retry.get(key, 0)):
		return
	var session := _new_session(host)
	session.name = "NetAhead"
	session.ahead = true
	add_child(session)
	session.failed.connect(_on_ahead_lost.bind(session.get_instance_id()))
	session.disconnected.connect(_on_ahead_lost.bind("", session.get_instance_id()))
	_ahead = session
	_ahead_host = host
	_ahead_port = port
	_ahead_unused = 0.0
	if session.join(host, port) != OK:
		_on_ahead_lost("", session.get_instance_id())


## The session connected ahead could not get in, or lost its connection:
## nothing is shown, the trip is made the plain way if it comes to it, and
## that server is left alone for a while.
func _on_ahead_lost(_reason: String, session: int) -> void:
	if _ahead == null or not is_instance_valid(_ahead) or _ahead.get_instance_id() != session:
		return
	_ahead_retry["%s:%d" % [_ahead_host, _ahead_port]] = Time.get_ticks_msec() + int(ahead_retry * 1000.0)
	_drop_ahead()


func _drop_ahead() -> void:
	if _ahead != null and is_instance_valid(_ahead):
		_ahead.queue_free()
	_ahead = null
	_ahead_port = -1


## The session connected ahead to `host`:`port`, handed over to become the
## game's own; null if there is none there that is still good.
func _take_ahead(host: String, port: int) -> NetSession:
	if _ahead == null or not is_instance_valid(_ahead):
		_ahead = null
		return null
	if _ahead_host != host or _ahead_port != port or not _ahead.is_live():
		_drop_ahead()
		return null
	var session := _ahead
	_ahead = null
	_ahead_port = -1
	for handler: Dictionary in session.failed.get_connections() + session.disconnected.get_connections():
		(handler["signal"] as Signal).disconnect(handler["callable"])
	session.ahead = false
	return session


## Signed in: the hub becomes that server's lobby.
func _on_online_signed_in(account: Dictionary) -> void:
	if net.ticket != "":
		_tickets[_join_address] = net.ticket
	_recovery_code = ""
	if net.recovered:
		net.recovered = false
		phone.show_notice("Your account is on this computer now. Make a new recovery code in the Servers app.")
	phone.set_update_needed(false)
	phone.set_server_changed({})
	_tour_stash_size = (account.get("stash", []) as Array).size()
	_join_attempts = 0
	_join_deadline = 0
	_host_restarts_left = 0
	_door_fallback = false
	var back_notice := _reconnected_notice()
	_keep_profile_in_step(account)
	if _remember_address != "":
		Profile.home_server = _remember_address
		Profile.save()
		_remember_address = ""
	if net.resuming:
		# Back after a drop to the body still standing: the server puts you
		# in it (`joined` follows), so nothing is deployed.
		var resumed := Worlds.get_world(net.world_id)
		if resumed != null and not resumed.safe_zone and _lobby_port < 0:
			hub.enter_lobby(account, resumed)
			hub.set_leave_text("Back to %s" % Worlds.social_world().display_name if _plaza_port >= 0 else "Leave the server")
		hub.set_online_status("Back in your body...")
		_expect_arrival()
		return
	_back_notice = back_notice
	if _lobby_port > 0:
		# Signed in to the arena: walk straight into the stands.
		hub.update_account(account)
		net.deploy()
		_expect_arrival()
		return
	var world := Worlds.get_world(net.world_id)
	if world.safe_zone:
		# The server's front door is its plaza: walk straight in.
		_plaza_address = _join_address
		_plaza_port = _join_port
		hub.set_online_status("Entering %s..." % world.display_name)
		# Back through a doorway: you arrive in front of it.
		net.deploy("from:" + _arrive_from if _arrive_from != "" else "")
		_arrive_from = ""
		_expect_arrival()
		return
	# A world's lobby is your home base, showing what this server keeps for
	# you. A portal from the watch deploys into this world; its door leads back.
	hub.set_online_status("")
	hub.enter_lobby(account, world)
	hub.set_leave_text("Back to %s" % Worlds.social_world().display_name if _plaza_port >= 0 else "Leave the server")
	if _gate_deploy:
		# Through a plaza gate, or a squad portal (landing at its outpost):
		# straight into the world.
		hub.set_online_status("Deploying to %s..." % world.display_name)
		net.deploy(Raid.PORTAL_DROP if _portal_deploy else "")
		_portal_deploy = false
		_expect_arrival()
		return
	go_home()
	if base_hud:
		var text := _back_notice if _back_notice != "" else \
				"Connected to %s. Open a portal from your watch to deploy." % world.display_name
		base_hud.show_notice(text, 8.0 if _back_notice != "" else 6.0)
	_back_notice = ""


## Asked to walk in: a server that never puts you there should not leave
## the travel screen up forever. By id, like the join timeout.
func _expect_arrival() -> void:
	var session := net.get_instance_id()
	get_tree().create_timer(DEPLOY_TIMEOUT).timeout.connect(func() -> void:
		if net != null and net.get_instance_id() == session and raid == null and base == null:
			_on_online_failed("The server did not let you in."))


func _on_online_account_changed(account: Dictionary) -> void:
	_keep_profile_in_step(account)
	# The server sends the account mid-life when a depot banks into it: the
	# stash grows while the player is alive out in a world.
	var stash_size := (account.get("stash", []) as Array).size()
	if _tour_stash_size >= 0 and stash_size > _tour_stash_size and _out_in_a_world() \
			and raid.player != null and is_instance_valid(raid.player) and not raid.player.is_dead:
		_tour_event("banked")
	_tour_stash_size = stash_size
	_tour_check()
	if shop_view != null and is_instance_valid(shop_view):
		shop_view.panel.set("account", account)
		shop_view.panel.call("refresh")
	if plaza_view != null and is_instance_valid(plaza_view):
		plaza_view.account = account
	if raid == null:
		hub.update_account(account)
		_refresh_base()
		# Buying or selling clothing changes what the server lets you wear.
		if net != null:
			net.send_look(Profile.appearance)


func _on_online_joined(p_raid: Raid) -> void:
	_gate_deploy = false
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
		plaza_view.account = net.account
		_tour_show()
		plaza_view.contract_asked.connect(func(action: String, job_id: String) -> void:
			if net:
				net.contract_ask(action, job_id))
	if _back_notice != "" and hud != null and is_instance_valid(hud):
		hud.notify(_back_notice)
	_back_notice = ""
	_tour_check()
	# Somewhere quiet: news of an update held back out in a world is told now.
	if raid.world.safe_zone and phone != null and phone.update_owed():
		phone.remind_update()


## A player in the plaza stepped into a portal and asked to go.
func use_portal(destination: String) -> void:
	if net == null or raid == null or not raid.world.safe_zone:
		return
	if destination.begins_with("world:"):
		var world := Worlds.get_world(destination.trim_prefix("world:"))
		var way := _route(destination.trim_prefix("world:"))
		if world == null or way.is_empty():
			plaza_view.show_notice("That world is not running on this server.")
			return
		if _tour_refuses(world):
			return
		_leave_raid()
		_show_travel("Travelling to %s..." % world.display_name)
		_gate_deploy = true
		_begin_join(way[0], way[1], 3)
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
	elif destination == "contracts":
		open_contracts()
	elif destination == "war_room":
		open_war_room()
	elif destination == "market":
		open_market()
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


## The contract board by the big screen: take, drop or reroll jobs. The
## server decides; a new account snapshot redraws it
## (`_on_online_account_changed`).
func open_contracts() -> void:
	if net == null or raid == null or shop_view != null:
		return
	var panel: Control = ContractPanel.new()
	panel.account = net.account
	panel.asked.connect(func(action: String, job_id: String) -> void:
		if net:
			net.contract_ask(action, job_id))
	_open_terminal(panel)


## The War Room console before the plaza's big screen: pick a world to see
## its map on the console and on the big screen (for you only), and deploy
## to it as its gate would (`use_portal`).
func open_war_room() -> void:
	if net == null or raid == null or shop_view != null:
		return
	var panel: Control = WarRoomPanel.new()
	panel.world_status = net.world_status
	panel.routes = net.routes
	var room: Node = plaza_view.war_room if plaza_view != null and is_instance_valid(plaza_view) else null
	var session := net
	var on_news := func(_status: Dictionary) -> void:
		if is_instance_valid(panel):
			panel.refresh()
	session.world_status_changed.connect(on_news)
	panel.picked.connect(func(world_id: String) -> void:
		if room != null and is_instance_valid(room):
			room.focus = world_id)
	panel.deploy_asked.connect(func(world_id: String) -> void:
		close_shop()
		use_portal("world:" + world_id))
	panel.tree_exited.connect(func() -> void:
		if room != null and is_instance_valid(room):
			room.focus = ""
		if is_instance_valid(session) and session.world_status_changed.is_connected(on_news):
			session.world_status_changed.disconnect(on_news))
	_open_terminal(panel)
	if room != null and is_instance_valid(room):
		room.focus = panel.chosen


## The player market's kiosk in the plaza: buy what other players listed,
## and list your own stash items. The server keeps the board and decides
## every trade; the screen shows what it sends (`market_state`) and your
## account, and is kept fresh while open.
func open_market() -> void:
	if net == null or raid == null or shop_view != null or LaunchScope.holds("market"):
		return
	var panel: Control = MarketPanel.new()
	panel.account = net.account
	panel.state = net.market_state
	panel.asked.connect(func(action: String, item_id: String, a: int, b: int) -> void:
		if net:
			panel.show_message("")
			net.market_ask(action, item_id, a, b))
	var session := net
	var on_change := func(state: Dictionary) -> void:
		if is_instance_valid(panel):
			panel.state = state
			panel.refresh()
	session.market_changed.connect(on_change)
	panel.tree_exited.connect(func() -> void:
		if is_instance_valid(session):
			session.market_ask("close")
			if session.market_changed.is_connected(on_change):
				session.market_changed.disconnect(on_change))
	session.market_ask("view")
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
	if net == null or raid == null:
		return
	var way := _home_route()
	if way.is_empty():
		return
	_leave_raid()
	_show_travel("Going home...")
	_begin_join(way[0], way[1], 3)


## Where the world `id` (or the arena) runs, as the server you are on told
## it: [host, port], or [] if it does not run there. A route on another
## machine belongs to the same servers, so the sign-in token goes with you.
func _route(id: String) -> Array:
	if net == null:
		return []
	var where: Variant = net.routes.get(id)
	if typeof(where) == TYPE_INT:
		return [_join_address, where]
	if typeof(where) == TYPE_STRING:
		var way := NetSession.split_address(where)
		if not way.is_empty() and not _tickets.has(way[0]) and _tickets.has(_join_address):
			_tickets[way[0]] = _tickets[_join_address]
		return way
	return []


## Where your base on this server is kept: the lobby of its first raid world.
func _home_route() -> Array:
	for world in Worlds.raid_worlds():
		var way := _route(world.id)
		if not way.is_empty():
			return way
	return []


## Whether the server you are on (or were last on) is the plaza's.
func _at_plaza() -> bool:
	return _plaza_port >= 0 and _join_port == _plaza_port and _join_address == _plaza_address


## Could not connect or sign in, or the connection dropped in the lobby.
func _on_online_failed(reason: String) -> void:
	_recovery_code = ""
	var was_refused := net != null and (net.refused or net.outdated != "" or not net.identity_changed.is_empty())
	if net:
		if net.refused:
			_join_attempts = 0
		if net.outdated != "":
			# A version mismatch is not a missing server: no starting one of
			# our own instead. An older game is pointed at the update.
			_door_fallback = false
			phone.set_update_needed(net.outdated == "client")
		if not net.identity_changed.is_empty():
			# Not a missing server either: a different one at that address.
			# The phone's Servers app warns, and trusting it is the player's call.
			_door_fallback = false
			var changed := net.identity_changed.duplicate()
			changed["address"] = "%s:%d" % [_join_address, _join_port] \
					if _join_port != NetSession.DEFAULT_PORT else _join_address
			phone.set_server_changed(changed)
		net.queue_free()
		net = null
	if _reconnect_until > 0:
		# Reconnecting after a drop: keep trying until the window closes,
		# unless the server said no or our own server has stopped.
		if not was_refused and Time.get_ticks_msec() < _reconnect_until and not _hosted_server_stopped():
			hub.set_online_status("Connection lost. Reconnecting...")
			await get_tree().create_timer(1.0).timeout
			if net == null and raid == null and _reconnect_until > 0:
				_join_attempts = 1
				_try_join()
			return
		_end_reconnect(reason if was_refused else _reconnect_note)
		return
	if _join_attempts > 0 and _hosted_server_stopped():
		_join_attempts = 0
		reason = "Your server stopped before it was ready."
	if _join_attempts > 0 and _join_deadline > 0 and Time.get_ticks_msec() > _join_deadline:
		_join_attempts = 0
		reason = "Your server took too long to start."
	if _join_attempts > 0:
		# A server we just started needs a moment before it listens.
		await get_tree().create_timer(1.0).timeout
		if net == null and raid == null:
			_try_join()
		return
	_join_deadline = 0
	if _host_restarts_left > 0 and _server_pid > 0 and raid == null and _plaza_port < 0 and _lobby_port < 0:
		# A server of your own that never let you in: start it once more.
		_host_restarts_left -= 1
		_start_local_server(_host_world)
		if net != null:
			hub.set_online_status("%s Starting it again..." % reason)
			return
	_host_restarts_left = 0
	_remember_address = ""
	_portal_deploy = false
	_gate_deploy = false
	if _door_fallback and _lobby_port < 0 and raid == null:
		# The server the door remembers is not there: start your own instead.
		# The address stays remembered for the next time you head out.
		host_and_join()
		if net != null:
			hub.set_online_status("Could not reach %s. Starting a server of your own..." % Profile.home_server)
			return
	_door_fallback = false
	_arrive_from = ""
	_stop_local_server()
	_plaza_port = -1
	hub.leave_lobby()
	if _lobby_port > 0:
		reason = "Could not enter the arena: %s" % reason
		_join_port = _lobby_port
		_join_address = _lobby_address
		_lobby_port = -1
	hub.set_online_status(reason)
	# Back home on the local stash, with a word on what went wrong. A base
	# open on the server's stash falls back to the local one.
	if raid == null:
		go_home()
		_refresh_base()
		_update_door()
	if base_hud:
		base_hud.show_notice(reason)


## The connection dropped after signing in: in a lobby, in the plaza or out
## in a world. The game quietly tries to get back in (DESIGN.md section 14,
## "Reconnect on its own"): the same server, the same sign-in, for
## `reconnect_window`. Out in a world your body stands where you left it for
## its sign-out time (`Raid.remove_player`), and getting back before that
## ends puts you in it again (`NetSession._back`). Only if every try fails
## do you go home, with word of what happens to the body.
func _on_online_disconnected() -> void:
	var in_arena := raid is Arena
	var was_safe := raid != null and raid.world.safe_zone
	var at_stake := raid != null and not was_safe and not in_arena
	var replaced := net != null and net.replaced
	_leave_raid()
	_reconnect_note = ("Lost the connection to the server." if not at_stake
			else "Lost the connection to the server. Your body stays in the world for a moment. "
			+ "If it survives, what you carried goes back to your stash there.")
	if in_arena:
		_reconnect_note = "Lost the connection to the arena. Your gear is safe."
	if replaced:
		_end_reconnect("Your account signed in from another game, so this one left the server.")
		return
	_reconnect_body = at_stake
	_reconnect_until = Time.get_ticks_msec() + int(reconnect_window * 1000.0)
	_show_travel("Connection lost. Reconnecting...")
	_begin_join(_join_address, _join_port, 1)


## Reconnecting failed: home on the local stash, saying why.
func _end_reconnect(reason: String) -> void:
	_reconnect_until = 0
	_reconnect_body = false
	_join_attempts = 0
	_stop_local_server()
	_plaza_port = -1
	if _lobby_port > 0:
		_join_port = _lobby_port
		_join_address = _lobby_address
		_lobby_port = -1
	hub.leave_lobby()
	hub.refresh({})
	hub.set_online_status(reason)
	go_home()
	if base_hud:
		base_hud.show_notice(reason, 8.0)


## Signed in again after a drop: what to tell the player about the body
## they left, if anything. Ends the reconnecting.
func _reconnected_notice() -> String:
	if _reconnect_until <= 0:
		return ""
	var had_body := _reconnect_body
	_reconnect_until = 0
	_reconnect_body = false
	if net == null or net.resuming:
		return ""
	if net.missed_outcome == "left":
		return "Back online. Your body signed out while you were away: what it carried is in your stash."
	if net.missed_outcome == "died":
		return "Back online. Your body was killed while you were away."
	return "Back online." if not had_body else "Back online. Your body was no longer out there."


## One online life ended. The server has already settled it into your account
## there, and nothing is written to the local profile. A death keeps you in
## the world; a finished sign-out goes back to the lobby.
func _on_online_finished(result: Dictionary) -> void:
	_tour_life_ended(result)
	_safety_net_news(result)
	# A finished contract buzzes the phone with what it paid.
	var finished: Array = result.get("contracts_finished", [])
	if not finished.is_empty() and phone != null:
		phone.show_notice("Contract done: %s   +%d scrip" % [", ".join(finished), int(result.get("contract_scrip", 0))])
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
	var came_from := "world:%s" % raid.world.id if raid != null else ""
	# Through a portal out of the world to another world or the arena: the
	# gear went home with the sign-out, and the trip goes on from there
	# (worked out while this session still knows the routes).
	var door := str(result.get("door", ""))
	var onward: Array = _onward_route(door) if not was_safe and Portal.goes_on(door) else []
	_leave_raid()
	hub.update_account(account)
	hub.refresh(result)
	if was_safe:
		# Signing out of the plaza itself leaves the server.
		leave_server()
		return
	if not onward.is_empty():
		if door == Arena.ArenaVenue.ID:
			# Leaving the arena comes back to this server's lobby: your base.
			_lobby_port = _join_port
			_lobby_address = _join_address
			_show_travel("Entering the arena...")
		else:
			_gate_deploy = true
			_portal_deploy = true
			_show_travel("Travelling to %s..." % Portal.title_of(door))
		_begin_join(onward[0], onward[1], 3)
		return
	# Back to the plaza if the server has one, else to the lobby. Through a
	# portal home it is your base: this world's lobby, whose door leads back
	# out to the plaza.
	if _plaza_port >= 0 and result.get("door", "") != Portal.HOME:
		_show_travel("Returning to %s..." % Worlds.social_world().display_name)
		_arrive_from = came_from
		_begin_join(_plaza_address, _plaza_port, 3)
		return
	_show_travel("Going home..." if result.get("door", "") == Portal.HOME else "Returning to your base...")
	_begin_join(_join_address, _join_port, 3)


## Where a sign-out through a portal out of a world goes on to once the gear
## is home (`door`, the result's): [host, port] for another world (landing at
## its gate outpost) or the arena, or [] for home and the plaza, which
## `_return_to_lobby` reaches the usual way, and for a world these servers do
## not run (then it ends where any sign-out does).
func _onward_route(door: String) -> Array:
	if net == null:
		return []
	if door == Arena.ArenaVenue.ID:
		var arena := _route(door)
		return arena if not arena.is_empty() else [_join_address, _join_port + ARENA_PORT_OFFSET]
	var world := Worlds.get_world(door)
	if world == null or world.safe_zone or door == net.world_id:
		return []
	return _route(door)


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
	if _plaza_port >= 0 and not _at_plaza():
		# Leaving a world's lobby (your base on this server) leads back to the
		# plaza, out of the quarters door, not off the server.
		_show_travel("Returning to %s..." % Worlds.social_world().display_name)
		_arrive_from = "home"
		_begin_join(_plaza_address, _plaza_port, 3)
		return
	_plaza_port = -1
	_drop_ahead()
	_stop_local_server()
	hub.set_online_status("")
	go_home()


## On a server you host yourself your account is your profile: every fresh
## copy of it the server sends while you are not out in a world becomes your
## profile too, so going home keeps what you did there. (While deployed the
## account is missing the gear you carry; the profile keeps it until the life
## is settled, as the server would after a crash.) Anyone else's server keeps
## a stash of its own.
func _keep_profile_in_step(account: Dictionary) -> void:
	if _server_pid > 0 and _join_address == "127.0.0.1" and account.get("ok", false) \
			and not account.get("deployed", false) and Profile.save_path == _hosted_save:
		Profile.adopt_account(account)


## Tells a server of our own this game is still here (see `HOST_HEARTBEAT`).
func _beat() -> void:
	_beat_left = HEARTBEAT_EVERY
	var file := FileAccess.open(HOST_HEARTBEAT, FileAccess.WRITE)
	if file != null:
		file.store_string(str(Time.get_unix_time_from_system()))
		file.close()


## Whether the game that started a server has stopped touching `path`.
static func heartbeat_stale(path: String, now := -1.0, stale_after := float(HEARTBEAT_STALE)) -> bool:
	if not FileAccess.file_exists(path):
		return true
	if now < 0.0:
		now = Time.get_unix_time_from_system()
	return now - float(FileAccess.get_modified_time(path)) > stale_after


## On the way to a server of your own, not let in yet: a server that has
## stopped, or the trip's deadline passing, ends this try now rather than
## after the join's own timeout (`_on_online_failed` starts it again once).
func _watch_host_trip() -> void:
	if _join_deadline <= 0 or net == null or not net.account.is_empty():
		return
	var reason := ""
	if _hosted_server_stopped():
		reason = "Your server stopped before it was ready."
	elif Time.get_ticks_msec() > _join_deadline:
		reason = "Your server took too long to start."
	if reason != "":
		_join_attempts = 0
		_on_online_failed(reason)


## The server this game started is no longer running.
func _hosted_server_stopped() -> bool:
	return _server_pid > 0 and _join_address == "127.0.0.1" and not OS.is_process_running(_server_pid)


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
## The new player's tour's guide (`_tour_guide_tick`): a soft amber column
## of light standing on the thing the current step wants you to use, the
## step written over it with how far it is, seen through walls so it leads
## you from anywhere in the place. Only you see it, it is never solid, and
## it fades its column as you get close, leaving the words over the thing.
## View only: it reads the body's position and changes nothing.
class TourGuide:
	extends Node3D

	## Seconds between looks for where the step's thing is (a depot moves
	## nearer as you walk; a rack's weapon goes on).
	const LOOK_EVERY := 0.5
	const INK := Color(1.0, 0.78, 0.36)

	## Where it stands (the thing's own position).
	var target := Vector3.ZERO
	## The step's objective, written over it.
	var text := ""
	## The column's height over the thing, metres.
	var height := 2.4
	## Within this many metres the column fades out; the words stay.
	var near := 3.5
	## How fast it glides to a new spot, per second.
	var glide := 6.0

	var _column: MeshInstance3D
	var _ring: MeshInstance3D
	var _label: Label3D
	var _material: StandardMaterial3D
	var _time := 0.0
	var _placed := false

	func _init() -> void:
		top_level = true
		_material = StandardMaterial3D.new()
		_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_material.no_depth_test = true
		_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_material.albedo_color = Color(INK, 0.5)
		var shaft := CylinderMesh.new()
		shaft.top_radius = 0.015
		shaft.bottom_radius = 0.06
		shaft.height = height
		shaft.radial_segments = 12
		shaft.rings = 1
		shaft.material = _material
		_column = MeshInstance3D.new()
		_column.name = "Column"
		_column.mesh = shaft
		_column.position = Vector3(0.0, height * 0.5, 0.0)
		_column.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_column)
		var torus := TorusMesh.new()
		torus.inner_radius = 0.34
		torus.outer_radius = 0.4
		torus.rings = 24
		torus.ring_segments = 6
		torus.material = _material
		_ring = MeshInstance3D.new()
		_ring.name = "Ring"
		_ring.mesh = torus
		_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_ring)
		_label = Label3D.new()
		_label.name = "Words"
		_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_label.no_depth_test = true
		_label.fixed_size = true
		_label.pixel_size = 0.0013
		_label.font_size = 40
		_label.outline_size = 10
		_label.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
		_label.modulate = INK.lightened(0.35)
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		_label.render_priority = 2
		add_child(_label)

	## Moves it toward `target` and writes the words for a body at `from`.
	func follow(from: Vector3, delta: float) -> void:
		if not _placed:
			global_position = target
			_placed = true
		else:
			global_position = global_position.lerp(target, clampf(glide * delta, 0.0, 1.0))
		_time += delta
		var away := Vector2(from.x - target.x, from.z - target.z).length()
		var lit := clampf((away - near * 0.5) / near, 0.0, 1.0)
		var pulse := 0.5 + 0.5 * sin(_time * 3.0)
		_material.albedo_color = Color(INK, lerpf(0.0, 0.32 + 0.2 * pulse, lit))
		_column.visible = lit > 0.01
		_ring.scale = Vector3.ONE * (1.0 + 0.12 * pulse)
		_ring.visible = lit > 0.01
		var top := height if lit > 0.01 else 0.7
		_label.position = Vector3(0.0, top + 0.25, 0.0)
		_label.text = text if away < near else "%s\n%d m" % [text, roundi(away)]

	## The words over it now (for tests).
	func words() -> String:
		return _label.text


class ShopView:
	extends Control

	signal closed

	var panel: Control

	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		# A lit terminal's glass, in the house style, like the base's stations.
		theme = TerminalStyle.theme()
		add_child(TerminalStyle.Backdrop.new())
		var margin := MarginContainer.new()
		margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		for side: String in ["left", "right"]:
			margin.add_theme_constant_override("margin_" + side, 50)
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
		var kicker := Label.new()
		kicker.text = "THE CONCOURSE  //  TERMINAL"
		kicker.add_theme_font_size_override("font_size", 13)
		kicker.add_theme_color_override("font_color", TerminalStyle.CYAN)
		box.add_child(kicker)
		box.move_child(kicker, 0)
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(panel)
		var leave := Button.new()
		leave.text = "Step away  (Esc)"
		leave.custom_minimum_size = Vector2(0, 44)
		leave.pressed.connect(func() -> void: closed.emit())
		box.add_child(leave)
		TerminalStyle.dress(self)

	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			closed.emit()
