class_name NetSession
extends Node
## One end of an online raid: the server that runs it, or a client that plays in it.
##
## The server is the authority. It runs a `Raid` in SERVER mode, feeds each
## connected player's `ActorCommand` into their actor, and sends everyone the
## state of every actor many times a second.
##
## A client runs a `Raid` in CLIENT mode. Every actor in it simulates locally
## from commands: your own from your input, so it responds at once, and
## everyone else's from the commands the server relays, so their swings, shots
## and flight play out between updates. The server's positions, health and
## deaths then correct the local guess. Damage is never decided on a client
## (`Combat.authoritative` is false there).
##
## Every input a client sends is numbered and the server plays them in order,
## one per tick, with no queue building up behind a lost packet (see
## `InputBuffer`). Its answer says which input it had reached, so the client
## compares the server's position with its own prediction for that same
## input and blends away only the real difference. Your own movement stays
## smooth however slow the connection is. A vehicle you ride is predicted
## and corrected the same way, so it steers the moment you do.
##
## Shots are lag compensated. Each input also says which server tick the
## client's view of everyone else had reached, and the server keeps a short
## history of where every actor was. When a player attacks, the server tests
## the hit against where the targets were on that player's screen
## (`Combat.rewind`), so nobody has to lead their shots by their ping.
##
## Connecting puts a client in the lobby: it signs in with a name and a secret,
## and the server answers with that account's stash and loadout from its
## `StashService`. Loadout changes are requests the server checks. `deploy`
## drops you into the world with the kit the server took out of the stash, and
## the server settles each life into the stash when it ends. After a death the
## client stays connected and `deploy` drops it in again. A client never sends
## a kit.
##
## The server's raid never ends or restarts. A client that disconnects leaves
## its body behind for a while (`Raid.remove_player`), and the server settles
## that life when the body is killed or its sign-out runs out.
##
## Each session owns its own multiplayer API rooted at itself, so it works
## anywhere in the scene tree and several can live in one process.

## Client: the server accepted your name. `account` is your stash, loadout,
## mastery and record as the server holds them. You are now in the lobby.
signal signed_in(account: Dictionary)
## Client: the server sent a fresh copy of your account (after any change).
signal account_changed(account: Dictionary)
## Client: the server turned down a lobby request (equip, pick, deploy), or
## asked you to slow down.
signal lobby_error(reason: String)
## Client: the raid view exists and your actor is in it. Fires again every
## time you drop back in after a death.
signal joined(raid: Raid)
## Client: one life ended. `result.outcome` is "died" (you are still connected
## and `deploy` drops you in again) or "left" (your sign-out finished).
signal run_finished(result: Dictionary)
## Client: could not connect, or the server refused.
signal failed(reason: String)
## Client: the connection dropped after joining.
signal disconnected
## Client: the server said which port each of its worlds runs on.
## Client: your clan, or the list of clans, changed (`clan_state`).
signal clan_changed(state: Dictionary)
## Client: the player market's board, as the server last sent it (`market_state`).
signal market_changed(state: Dictionary)
signal routes_changed(routes: Dictionary)
## Client: the server's news of its other worlds changed (`world_status`).
signal world_status_changed(status: Dictionary)
## Client: the phone's contacts, messages, invites and news changed (see
## `SocialService.snapshot`).
signal social_changed(social: Dictionary)
## Client: the server turned down a phone request (message, invite, contact).
signal social_error(reason: String)
## Client: something happened on the phone worth a pop-up ("Bo accepted").
signal social_notice(text: String)
## Client: you accepted an invite to the raid on this server.
signal world_invite_accepted(invite: Dictionary)
## Client: you accepted an invite to someone's home base. The owner's stash
## and loadout come from the server, so a base can be shown read-only.
signal base_visit_requested(owner_name: String, stash: Array, loadout: Dictionary, upgrades: Array, plan: Dictionary)
## Client: you walked through a squad portal your side may use; go to
## `destination` (a world id or the arena's). The server decided.
signal portal_travel(destination: String)

const DEFAULT_PORT := 24565
## The sign-in handshake's own version, and nothing else's. It changes only
## when the handshake itself changes shape (what `_hello` and the server's
## answer are), which is rare. What the game says once signed in is not
## versioned here: every message declares itself and `NetManifest`
## (`core/net/net_manifest.gd`) works out whether two builds agree, so a new
## or changed message never touches this line.
##   - A new, removed or changed `@rpc` method is seen by itself.
##   - A change to what an existing message carries (a new bit in the actor
##     state, another field in a packed array) raises the `WIRE_` constant
##     beside the code that packs it, or adds one there.
## Up to 59 this number was raised for every online change (the list below
## is that history); 60 is the handshake that carries the manifest.
const PROTOCOL := 60
const NetManifest := preload("res://core/net/net_manifest.gd")
## Where the release workflow stamps a build's number (as `Updater` reads
## it): how two builds whose manifests differ tell which is the older.
const BUILD_SETTING := "ares/build/number"
## Every packet is compressed, both ways. State updates are mostly repeated
## numbers, and a big battle sends a player hundreds of them a second. Server
## and client must agree before a word is understood, so a change here needs
## a new PROTOCOL and a release note: the two sides cannot even say why.
## 30: a sign-out tells the client the countdown's full span, and actor state
## carries the airborne sign-out beacon bit.
## 31: a squad portal carries how long it unfolds (a portal home out in a
## world unfolds over its opener's sign-out).
## 32: a depot banking tells its owner what this life has sent home
## (`_banked`), for the watch's banking readout.
## 33: the version check and sign-in moved into the connection handshake
## (`SceneMultiplayer.auth_callback`, see "Signing in" below); the old
## `_hello`, `_sign_in` and `_refused` calls are gone.
## 34: hit feedback says whether it was a head, plates soaked it, or it
## broke them, for the hit marker.
## 35: connections are encrypted (ENet DTLS, `ServerTrust`), and the server's
## sign-in answer carries its certificate.
## 36: reconnecting to your body after a drop (`_back`, `_rearm`), and a
## connection let go for a newer sign-in is told so (`_replaced`).
## 37: the account service (`AccountService`).
## 38: the cold: body heat goes to its owner (`_body_heat`) and actor state
## carries the shivering bit.
## 39: what a player picks up is told to them item by item (`_looted`), for
## the visor's pickup feed.
## 40: warm beacons: a sign-out carries the rate its countdown runs at
## (`_sign_out`'s `rate`: 0 while away from the beacon, faster with company).
## 41: tracks: footprints and wheel tracks near a player (`_tracks`).
## 42: thin ice: cracks (`_ice_crack`) and the open holes (`_ice_holes`).
## 43: a core boss's kind in a bot's spawn data ("boss") and a linked
## faction's call for help (`_grid_call`).
## 45: the weather: a storm cell crossing the map (`_weather`).
## 47: the home base's plan: `_request_place_room`, and a visited base's
## plan in `_base_visit`.
## 48: a vehicle's ride state lists who sits on each passenger seat (the
## rover seats four).
## 50: a lift powered or run down (`_lift`).
## 51: a keeper's phase (`_keeper`) and its purge lanes (`_purge`).
## 54: the war's artillery: a salvo called, with where and when each shell
## lands (`_shells`).
## 57: an army hunting you for a grudge is told to you (`_hunted`).
## Where an out-of-date game gets the latest build: the rolling "latest"
## release the Windows client workflow publishes (docs/hosting.md).
const UPDATE_URL := "https://github.com/czinabu/projectares/releases/tag/latest"
## What `_back` says when the server is putting you back in your body.
const BACK_IN_BODY := "body"
## Seconds a connection may take to sign in before it is dropped.
const AUTH_TIMEOUT := 10.0
## The most bytes a sign-in or its answer may be. Read before anything else.
const MAX_AUTH_BYTES := 4096
## The most bytes a server's answer may be: one that turns a game away for
## its version carries the server's whole manifest.
const MAX_ANSWER_BYTES := 32768
## What a game turned away for its version is told.
const NEWER_SERVER := "This server runs a newer version of the game. Get the update from the Servers app on your phone."
const OLDER_SERVER := "This server runs an older version of the game. Its host needs to update it to the latest build."
const COMPRESSION := ENetConnection.COMPRESS_RANGE_CODER
const StashService := preload("res://core/account/stash_service.gd")
const ServerTrust := preload("res://core/net/server_trust.gd")
const Economy := preload("res://core/economy/economy.gd")
const Human := preload("res://core/visual/human.gd")
const SocialService := preload("res://core/social/social_service.gd")
const MarketService := preload("res://core/economy/market_service.gd")
const ArenaVenue := preload("res://core/arena/arena_venue.gd")
## Server physics ticks between asking the stash whether a backup is due.
const BACKUP_CHECK_TICKS := 600
## Server physics ticks between arena board updates when nothing changed.
const BOARD_RESEND_TICKS := 60
## Server physics ticks between state updates (2 = 30 a second).
const TICKS_PER_SNAPSHOT := 2
## Actors per state packet, to keep each one under the network's packet size.
const ACTORS_PER_PACKET := 5
## Vehicles per ride state packet, for the same reason (a race world's
## bays and AI racers came to over the MTU in one), and how often a parked
## vehicle nobody rides is sent again (snapshots).
const VEHICLES_PER_PACKET := 12
const PARKED_EVERY := 15
## Interest: a player hears about what is near them in every state update,
## and about the rest of a big field less often. Actors within NEAR_RANGE
## metres are sent every update, within MID_RANGE every DETAIL_EVERY[1]
## updates, and further off every DETAIL_EVERY[2]. Between updates a client
## keeps simulating an actor from the last command it heard.
const NEAR_RANGE := 90.0
const MID_RANGE := 220.0
const DETAIL_EVERY: Array[int] = [1, 4, 12]
## A client simulates actors far from its own player in longer steps
## (`Actor.thin`): every tick within this range, every second tick within
## THIN_FAR_RANGE, every fourth beyond.
const THIN_NEAR_RANGE := 70.0
const THIN_FAR_RANGE := 160.0
## Position errors beyond this are fixed at once instead of blended.
const SNAP_DISTANCE := 5.0
## Each input packet repeats every tick the server has not yet answered for,
## up to this many (a quarter of a second), so a key press survives a run of
## lost packets and not only a single one. On a good connection that is the
## three or four ticks still in flight.
const MAX_INPUTS_PER_PACKET := 16
## Bytes one input takes in a packet (`pack_inputs`). A full packet must fit
## in one datagram: split in two, it is lost when either half is, which
## makes loss worse just when it is bad.
const INPUT_BYTES := 43
## The server holds at most this many unplayed inputs per player. More means
## the player's packets arrived in a burst, and the oldest are folded together.
const MAX_QUEUED_INPUTS := 6
## A tick with no input to play is played as a guess (the held keys carry on)
## and counted as the next input, so the real one is skipped when it turns up
## late and the player's inputs never queue up behind a lost packet. The
## server guesses at most this many inputs past the newest it has received;
## a longer silence is a stall, and the count waits.
const MAX_GUESSED_INPUTS := 8
## An input the server always has to spare is a tick of delay for nothing.
## Every this many ticks, half of what was spare throughout (at least one
## input) is folded away.
const INPUT_TRIM_TICKS := 20
## The furthest back the server rewinds a target for an attacker's ping
## (30 = half a second). A slower connection has to lead by the rest.
const MAX_REWIND_TICKS := 30
## How many ticks of your own predicted positions a client remembers.
const HISTORY_TICKS := 180
## The share of a position error that is corrected each tick.
const CORRECTION_RATE := 0.2
## The furthest a client's view runs ahead of an update that comes late, in
## ticks (30 = half a second, all a `Trail` remembers). An update later than
## that starts the view again from it.
const MAX_VIEW_LEAD := 30
## A view that was ahead of every update for this many ticks is ahead for
## nothing (the connection got slower for good): half of what was spare
## throughout, at least one tick, is folded away.
const VIEW_SETTLE_TICKS := 60
## Notices the server passes on to a player. Others are produced locally.
const FORWARDED_NOTICES := ["Parry!", "Wrong side", "Guard broken", "Staggered", "Killed ", "Looted ",
		"Backpack full", "Someone is riding it", "Banked ", "Signing out", "Sign-out cancelled",
		"You cannot sign out", "No room there", "Watch recharging", "Your watch is full",
		"Look at a vehicle", "Packed ", "Get off first", "Not while signing out", "Vehicles stay on the watch",
		"Scanned", "Sensed", "Back in your body"]

var is_server := false
var raid: Raid
var world_id := ""
## Server options, set before `host`: a bot count override (below zero keeps
## the world's own) and whether players spawn together.
var bot_count := -1
var squad_spawn := false
## Server, set before `host`: the raid gets a 3D world of its own, so several
## sessions (a plaza and a warzone) can run in one process without their maps
## colliding.
var isolated := false
## Where to find the other worlds of this server: world id -> where it
## listens, a port on the address you are already on (an int) or
## "host:port" when that world runs on another machine. A server that runs
## every world in one program fills this in before `host`; one that runs a
## single world reads it from the account service's directory
## (`AccountLink.worlds`). Clients receive it when they sign in and whenever
## it changes, so a gate or a portal knows where to send you.
var routes := {}
## Server, set before `host`: the address players reach this world at, when
## it is not the one the other worlds of this server are on ("" for the same).
var public_host := ""
## Server: how many connections a world keeps free on top of its players,
## for games signed in and not in the world: a lobby (your base on this
## server), and a game that connected ahead of its trip here.
var lobby_room := 24
## How the other worlds on this server are doing: world id -> `Raid.status()`.
## The safe zone's session gathers it and sends it to everyone standing
## there, so a doorway can say what is on the other side.
var world_status := {}
## Server: how many ticks between looks at the other worlds.
var status_every := 60
## Client: called with the server's world, returns the kit to deploy with.
## Server: owns every player's stash, loadout and mastery. Set its
## `save_dir` or `persist` before `host`. A server that keeps its own
## accounts (a friends' server) holds a `StashService`; an official server
## holds an `AccountLink` to the shared account service instead
## (`core/account/account_link.gd`), which offers the same calls but may take
## a moment to answer. So every call that asks the accounts for something
## is made with `await`, and whatever follows it checks that the player it
## was for is still there.
var stash: Object = StashService.new()
## Server: presence, contacts, messages, invites and news for the phone. Its
## files live in a `social` folder inside the stash's `save_dir`.
var social := SocialService.new()
## Server: who is in which clan. Shared between the sessions of one server,
## and saved beside the accounts.
var clans := ClanService.new()
## Server: the player market's board. Shared between the sessions of one
## server, and saved beside the accounts.
var market := MarketService.new()
## Client: the market board as the server last sent it: {"listings",
## "trades_left", "listed"}. See `MarketService.snapshot`.
var market_state := {}
## Client: what the server last said about clans: {"clan": yours or {},
## "clans": every clan there is}. See `ClanService.snapshot`.
var clan_state := {}
## Client: the phone's view as the server last sent it. Empty until signed in.
var social_state := {}
## Client: the name to sign in with, and the secret that proves the account
## is yours (see `StashService.new_secret`).
var player_name := "Raider"
## Client, set before `join`: this connection is made ahead of a trip, while
## the player is still somewhere else (`Main._connect_ahead`). The server
## signs it in and leaves everything else until `deploy`.
var ahead := false
## Client: the sign-in token the server handed out (`_server_auth`). Set it
## before `join` to sign in with it instead of the secret; it is only for
## the servers that share the accounts of the one that gave it.
var ticket := ""
## Client: how this player's character looks, sent once signed in.
var look := {}
var secret := ""
## Client: your account as the server last sent it. Empty until signed in.
var account := {}
## Client: the server answered and said no, so trying again will not help.
var refused := false
## Client: why the versions did not match, if they did not: "client" (this
## game is older than the server, get the update at UPDATE_URL) or "server"
## (the server is older; its host must update it), or "either" (they differ
## and a build without a number is in it, an editor run, so nobody can say
## which is older). "" when they match.
var outdated := ""
## Client: what this game and the server that turned it away disagree on
## (`NetManifest.differences`), for the log and a bug report.
var differs := PackedStringArray()
## This build's number (0 in the editor and in tests).
var build := int(ProjectSettings.get_setting(BUILD_SETTING, 0))
## Client: the server showed a different certificate from the one this game
## remembered for it ("this server changed", see `ServerTrust`): {"host",
## "was", "now" (fingerprints), "certificate" (the new one, PEM)}. The join
## gives up without signing in; trusting it is the player's call, on the
## phone's Servers app. Empty otherwise.
var identity_changed := {}
## Client: the id of your own actor, and the kit you joined with.
var my_actor_id := -1
## Client, for testing how the game feels on a bad connection: seconds of delay
## added in each direction, and the share of input packets thrown away (0 to 1).
var simulated_lag := 0.0
var simulated_loss := 0.0
## Seconds of extra, uneven delay on the server's updates (client, for tests
## and `--jitter`): each is held back by up to this much more, in order, so
## they arrive late and then several at once, as on a bad connection.
var simulated_jitter := 0.0
## Client: the largest gap seen between where the server put you and where
## this game had predicted you would be at that same moment.
var max_correction := 0.0
## Server: test hits against where the attacker saw their targets. Off only
## to compare with how it plays without (`--no-rewind`).
var lag_compensation := true

var _api: SceneMultiplayer
var _actors := {}        # id -> Actor
var _ids := {}           # Actor -> id
var _next_id := 1
var _peer_actor := {}    # peer id -> Actor (server)
var _actor_peer := {}    # Actor -> peer id (server)
var _joined_peers: Array[int] = []
var _peer_account := {}  # peer id -> account id (server)
var _peer_look := {}  # peer id -> appearance (server). Cosmetic only.
var _market_viewers: Array[int] = [] # peers with the market kiosk open (server)
var _signing_in := {}    # peer id -> true while the accounts are asked who they are (server)
var _deploying := {}     # peer id -> true while the accounts are asked for their kit (server)
var _joining_look := {}  # the look of the player being added right now (server)
var _actor_account := {} # Actor -> account id, until the run is settled (server)
var _inputs := {}        # peer id -> InputBuffer: their inputs not yet played (server)
var _applied_seq := {}   # actor id -> input number the actor last simulated (server)
var _seen_tick := {}     # Actor -> server tick the player was looking at (server)
var _past := {}          # server tick -> {Actor: position} after that tick (server)
var _seq := 0            # number of the input sent this tick (client)
var _history := {}       # input number -> own predicted position after it (client)
var _recent_inputs: Array = [] # [seq, command array, view tick] sent and not yet answered for (client)
var _acked_seq := 0      # newest input number the server says it has played (client)
var _newest_tick := 0    # server tick of the newest state received (client)
var _fresh_state := false # a newer state arrived since the last tick (client)
var _view_tick := 0      # server tick the actors on screen show (client)
var _clock := 0          # ticks this client has run in this world (client)
var _least_lead := -1    # least ticks the view was ahead of an update as it arrived, this window; -1 none yet (client)
var _lead_window := 0    # ticks into the window `_least_lead` is measured over (client)
var _trails := {}        # actor id -> Trail: where this client showed them, tick by tick (client)
var _latest_tick := {}   # actor id -> server tick of their entry in `_latest` (client)
var _corrections := {}   # actor id -> position error still to blend away (client)
var _delayed_out: Array = [] # [due msec, inputs] held back by simulated_lag
var _delayed_in: Array = []  # [due msec, Callable] updates held back by simulated_lag
var _one_shots: Array[Dictionary] = [{}, {}, {}] # per detail tier: actor id -> one-shot flags since that tier's last update (server)
var _switches: Array[Dictionary] = [{}, {}, {}]  # per detail tier: actor id -> last weapon switch since then (server)
var _view_at := {}       # peer id -> where their player is, or last was (server)
## How many state entries have gone out (server) or come in (client), and on
## a client how many for each actor id. For checks and tuning.
var entries_sent := 0
var entries_received := {}
var _dead_kind := {}     # actor id -> damage kind that killed them
var _latest := {}        # actor id -> newest state entry (client)
var _containers := {}    # container id -> LootContainer
var _container_ids := {} # LootContainer -> id
var _vehicles := {}      # vehicle id -> vehicle node
## Vehicle id -> whether it was parked, nobody aboard, when last sent.
var _vehicle_parked := {}
var _vehicle_ids := {}   # vehicle node -> id
var _crates := {}        # crate id -> SalvageCrate
var _crate_ids := {}     # SalvageCrate -> id
var _vehicle_targets := {} # vehicle id -> newest state entry (client)
var _ride_history := {}  # input number -> [position, heading, speed] of the ride after it (client)
var _ride_fix := Vector3.ZERO # position error of your ride still to blend away (client)
var _ride_turn := 0.0    # heading error of your ride still to blend away (client)
var _ride_entry: Array = [] # the server's last answer about your ride, once compared (client)
var _sent_kills := {}    # actor id -> kill count last sent (server)
var _board_sent := {}    # peer id -> [board text, tick sent] (server, arena)
var _board_dirty := false
var _sent_standing := {} # actor id -> public renown standing last sent (server)
var _sent_war := -1.0    # war intensity last sent (server)
var _sent_weather := ""   # the storm kind last sent (server), "" for none
var _sent_points := {}   # peer id -> strongpoint states last sent to them (server)
var _sent_heat := {}     # peer id -> [body heat, warming] last sent to them (server)
var _sent_hunted := {}   # peer id -> the army hunting them last sent (server)
var _sent_tracks := {}   # peer id -> { track cell: last mark id sent } (server)
## Tracks: how far round a player new marks are sent, how often, and at most
## how many in one message (the rest follow next time).
const TRACK_RANGE := 60.0
const TRACK_SEND_EVERY := 20
const TRACK_BATCH := 500
var _tick := 0
var _sent_status := {}   # world status last sent (server)
var _sent_routes := {}   # routes last sent (server)
var _told_status := {}   # this world's status as last told to the account service (server)
var _port := 0           # the port this server listens on
var _max_players := 0    # how many players this world takes (server)
var _ahead := {}         # peer id -> true: signed in ahead of a trip here, not here yet (server)
var _leaving := 0        # the peer whose leaving is being handled (server)
var _limits := RequestLimits.new() # how many requests each player may still make (server)
var _gave_up := false    # client: `failed` was emitted for this connection
var _certificate := ""   # server: this server's certificate (PEM), sent with every sign-in answer
var _join_host := ""     # client: the address joined
var _join_port := 0
var _join_modes: Array[String] = [] # client: connection modes still to try (`ServerTrust.attempts_for`)
var _join_mode := ""     # client: the mode of the connection being made
## Every session hosting in this process, so a safe zone can ask the others.
static var _hosting: Array[NetSession] = []
var _died_at := {}       # peer id -> msec when their last life ended in a death (server)
var _missed := {}        # account id -> outcome of a life that ended while they were away (server)
## Client: back after a dropped connection, the server is putting you in the
## body you left standing (`_back`); `joined` follows without a `deploy`.
var resuming := false
## Client: how the life you were away from ended ("left" or "died"), when
## the body was gone by the time you signed in again, else "".
var missed_outcome := ""
## Client: the server let this connection go because the account signed in
## from another game. Not worth reconnecting.
var replaced := false
var _finished := false   # client: signed out, so the server closing the connection is expected
var _can_redeploy := false # client: dead and still connected
var _space: SubViewport  # the raid's own 3D world when `isolated` (server)


func _enter_tree() -> void:
	_api = SceneMultiplayer.new()
	_api.root_path = get_path()
	get_tree().set_multiplayer(_api, get_path())
	process_physics_priority = -20
	var late := LateTick.new()
	late.name = "LateTick"
	late.session = self
	add_child(late)


func _exit_tree() -> void:
	if is_server and is_instance_valid(stash):
		# A server that stops mid-raid hands everyone's gear back.
		stash.cancel_all_deploys()
	_hosting.erase(self)
	close()
	if not is_server and my_actor_id >= 0:
		# Only a game that was in a world took the authority away; one that
		# was only signed in (ahead of a trip) leaves it alone.
		Combat.authoritative = true
	elif Combat.rewind == _seen_positions:
		Combat.rewind = Callable()


# ---------------------------------------------------------------- server ----

## Starts a server running `p_world_id`. Returns OK or an error.
func host(p_world_id: String, port := DEFAULT_PORT, max_players := 8) -> Error:
	if world_for(p_world_id) == null:
		return ERR_DOES_NOT_EXIST
	var peer := ENetMultiplayerPeer.new()
	# Room for the players and for games that are only signed in (`lobby_room`).
	var err := peer.create_server(port, max_players + lobby_room)
	if err != OK:
		return err
	_port = port
	_max_players = max_players
	# Every connection is encrypted with this server's own certificate, made
	# on its first start and kept beside the accounts (`ServerTrust`).
	var identity_dir: String = str(stash.save_dir).trim_suffix("/").path_join("server_identity")
	err = peer.host.dtls_server_setup(ServerTrust.server_options(identity_dir, stash.persist))
	if err != OK:
		peer.close()
		return err
	_certificate = ServerTrust.pem_of(ServerTrust.identity(identity_dir, stash.persist)[1])
	peer.host.compress(COMPRESSION)
	is_server = true
	world_id = p_world_id
	if stash.is_remote():
		# The account service runs the market and tells this server when an
		# account or the board changes from somewhere else. It keeps the
		# clans (this server reads a copy), the phone's records and the
		# directory of worlds too, since each world is a program of its own.
		clans = stash.clans
		stash.account_changed.connect(_on_account_changed)
		stash.market_changed.connect(_on_market_changed)
		stash.clans_changed.connect(_on_clans_changed)
		stash.social_changed.connect(_send_social_to)
		stash.social_noticed.connect(_on_social_noticed)
		stash.worlds_changed.connect(_share_worlds)
		stash.linked.connect(_on_linked)
	else:
		clans.open(stash.save_dir, stash.persist)
		market.open(stash.save_dir, stash.persist)
		social.persist = stash.persist
		social.save_dir = stash.save_dir.path_join("social")
		social.load_server_news(stash.save_dir.path_join("news.json"))
	Combat.authoritative = true
	# A peer signs in during the handshake, before it counts as connected:
	# an old game or a wrong secret never gets in, and nothing it sends
	# meanwhile reaches the session. Clients only ever talk to the server, so
	# it never passes their calls on to each other.
	_api.auth_callback = _server_auth
	_api.auth_timeout = AUTH_TIMEOUT
	_api.server_relay = false
	_api.multiplayer_peer = peer
	_api.peer_connected.connect(_on_peer_connected)
	_api.peer_disconnected.connect(_on_peer_disconnected)
	_api.peer_authentication_failed.connect(_on_server_auth_failed)
	stash.backup_if_due()
	if lag_compensation:
		Combat.rewind = _seen_positions
	_start_server_raid()
	_hosting.append(self)
	_announce()
	return OK


## Server: how the other worlds of this server are doing, world id ->
## `Raid.status()`: asked of the sessions in this process, or read off the
## account service's directory when each world is its own program.
func _gather_status() -> Dictionary:
	var out := {}
	if stash.is_remote():
		for id: String in stash.worlds:
			if id != world_id:
				out[id] = stash.worlds[id].get("status", {})
		return out
	for session in _hosting:
		if session == self or not is_instance_valid(session) or session.raid == null:
			continue
		if routes.has(session.world_id):
			out[session.world_id] = session.raid.status()
	return out


## Server: where the other worlds of this server are, as clients are told
## (see `routes`).
func _routes_out() -> Dictionary:
	var out := {}
	if stash.is_remote():
		for id: String in stash.worlds:
			if id == world_id:
				continue
			var host := str(stash.worlds[id].get("host", ""))
			var port := int(stash.worlds[id].get("port", 0))
			out[id] = port if host == "" or host == public_host else "%s:%d" % [host, port]
		return out
	for id: String in routes:
		if id != world_id:
			out[id] = routes[id]
	return out


## Server: puts this world on the account service's directory, with how it
## is doing now. Nothing to do on a server that runs every world itself.
func _announce() -> void:
	if not stash.is_remote() or raid == null:
		return
	_told_status = raid.status()
	stash.announce({"world": world_id, "host": public_host, "port": _port, "max": _max_players,
			"status": _told_status})


## Server: keeps the directory current and tells everyone signed in here
## when a route or another world's news changed.
func _share_worlds() -> void:
	if not is_server or raid == null:
		return
	if stash.is_remote() and raid.status() != _told_status:
		_announce()
	if _peer_account.is_empty():
		return
	var peers := _api.get_peers()
	var out := _routes_out()
	if out != _sent_routes:
		_sent_routes = out
		for peer: int in _peer_account:
			if peer in peers:
				_routes.rpc_id(peer, out)
	var status := _gather_status()
	if status != _sent_status:
		_sent_status = status
		for peer: int in _peer_account:
			if peer in peers:
				_world_status.rpc_id(peer, status)


## Server: the link to the account service is up (again). It forgot this
## server when the link dropped, so everyone here is signed on with it again.
func _on_linked() -> void:
	_announce()
	for peer: int in _peer_account:
		if _here(peer):
			_social_do("online", _peer_account[peer], [stash.name_of(_peer_account[peer]),
					_place_of(peer), world_id])


func close() -> void:
	if _api and _api.multiplayer_peer and not _api.multiplayer_peer is OfflineMultiplayerPeer:
		_api.multiplayer_peer.close()
		_api.multiplayer_peer = OfflineMultiplayerPeer.new()


func _start_server_raid() -> void:
	_clear_tables()
	var world := world_for(world_id)
	raid = world.new_raid()
	raid.name = "Raid"
	if isolated:
		if _space == null:
			_space = SubViewport.new()
			_space.name = "Space"
			_space.own_world_3d = true
			_space.render_target_update_mode = SubViewport.UPDATE_DISABLED
			add_child(_space)
		_space.add_child(raid)
	else:
		add_child(raid)
	raid.actor_spawned.connect(_on_server_actor_spawned)
	raid.actor_removed.connect(_on_server_actor_removed)
	raid.player_finished.connect(_on_server_player_finished)
	raid.player_banked.connect(_on_server_player_banked)
	raid.war_feed.connect(func(text: String) -> void:
		for peer in _joined_peers:
			_war_feed.rpc_id(peer, text))
	raid.sign_out_changed.connect(_on_server_sign_out_changed)
	raid.container_spawned.connect(_on_server_container_spawned)
	raid.vehicle_spawned.connect(_on_server_vehicle_spawned)
	raid.vehicle_removed.connect(_on_server_vehicle_removed)
	raid.crate_spawned.connect(_on_server_crate_spawned)
	raid.field_changed.connect(_on_server_field_changed)
	raid.watch_changed.connect(_send_watch)
	raid.tally_changed.connect(_send_tally)
	raid.banked_changed.connect(_send_banked)
	raid.toy_thrown.connect(func(actor: Actor, item_id: String, from: Vector3, toy_velocity: Vector3) -> void:
		var thrower: int = _ids.get(actor, -1)
		for peer in _joined_peers:
			_toy.rpc_id(peer, thrower, item_id, from, toy_velocity, actor.cmd.yaw))
	raid.toy_hand_changed.connect(_on_server_toy_hand)
	raid.ice_cracked.connect(func(at: Vector3, stage: int) -> void:
		for peer in _joined_peers:
			_ice_crack.rpc_id(peer, at, stage))
	raid.ice_changed.connect(func() -> void:
		var holes := raid.pack_ice_holes()
		for peer in _joined_peers:
			_ice_holes.rpc_id(peer, holes))
	raid.grid_called.connect(_on_server_grid_called)
	raid.cloud_burst.connect(func(at: Vector3, radius: float, seconds: float, kind: String) -> void:
		for peer in _joined_peers:
			var viewer: Actor = _peer_actor.get(peer)
			if viewer != null and is_instance_valid(viewer) and viewer.global_position.distance_to(at) <= CLOUD_RANGE:
				_cloud.rpc_id(peer, at, radius, seconds, kind))
	raid.shells_called.connect(func(points: PackedVector3Array, lands_in: PackedFloat32Array) -> void:
		for peer in _joined_peers:
			_shells.rpc_id(peer, points, lands_in))
	raid.lift_changed.connect(func(id: String, left: float) -> void:
		for peer in _joined_peers:
			_lift.rpc_id(peer, id, left))
	raid.keeper_changed.connect(func(kind: String, phase: int) -> void:
		for peer in _joined_peers:
			_keeper.rpc_id(peer, kind, phase))
	raid.purge_changed.connect(func(index: int, state: int) -> void:
		for peer in _joined_peers:
			_purge.rpc_id(peer, index, state))
	raid.army_pushed.connect(func(site: int, from: Vector3, title: String, loud: bool) -> void:
		for peer in _joined_peers:
			_army_push.rpc_id(peer, site, from, title, loud))
	raid.pinged.connect(_on_server_pinged)
	raid.portal_opened.connect(func(portal: Portal) -> void:
		for peer in _joined_peers:
			_send_portal(peer, portal))
	raid.portal_closed.connect(func(portal: Portal) -> void:
		for peer in _joined_peers:
			_portal_closed.rpc_id(peer, portal.get_instance_id()))
	raid.portal_entered.connect(func(actor: Actor, destination: String) -> void:
		var peer: int = _actor_peer.get(actor, 0)
		if peer != 0:
			_portal_travel.rpc_id(peer, destination))
	raid.squad_spawn = squad_spawn
	if lag_compensation:
		raid.rewind = _seen_positions
	if bot_count >= 0:
		world.bot_count = bot_count
		# No bots asked for: no pockets either.
		if bot_count == 0:
			world.pocket_wake = 0.0
	var arena := raid as Arena
	if arena != null:
		# The arena pays wagers from the accounts this server keeps.
		arena.bank = Arena.StashBank.new(stash)
		arena.board_changed.connect(func() -> void: _board_dirty = true)
		arena.told.connect(func(actor: Actor, text: String) -> void:
			var peer: int = _actor_peer.get(actor, 0)
			if peer in _api.get_peers():
				_notice.rpc_id(peer, text))
	var race := raid as Race
	if race != null:
		# Each racer is sent their own run; everyone gets the board.
		race.run_changed.connect(_on_race_run_changed)
		race.board_changed.connect(_send_race_board)
		race.heat_changed.connect(_send_race_heats)
		# The league is kept on the accounts; the rivals' radio goes to the
		# one racer it is said to.
		race.league_bank = Race.StashLeagueBank.new(stash)
		race.radio.connect(_on_race_radio)
		race.league_changed.connect(_on_race_league_changed)
		# Kept ghosts go back to their racer, and friends' times to everyone.
		race.ghost_kept.connect(_on_race_ghost_kept)
		race.bests_changed.connect(_send_friend_bests_all)
	raid.start_server(world)


func _clear_tables() -> void:
	_actors.clear()
	_ids.clear()
	_peer_actor.clear()
	_actor_peer.clear()
	_joined_peers.clear()
	_inputs.clear()
	_applied_seq.clear()
	_seen_tick.clear()
	_past.clear()
	_newest_tick = 0
	_fresh_state = false
	_view_tick = 0
	_clock = 0
	_least_lead = -1
	_lead_window = 0
	_trails.clear()
	_latest_tick.clear()
	_seq = 0
	_acked_seq = 0
	_history.clear()
	_recent_inputs.clear()
	_corrections.clear()
	_delayed_out.clear()
	_delayed_in.clear()
	for tier in DETAIL_EVERY.size():
		_one_shots[tier].clear()
		_switches[tier].clear()
	_view_at.clear()
	entries_sent = 0
	entries_received.clear()
	_dead_kind.clear()
	_latest.clear()
	_containers.clear()
	_container_ids.clear()
	_vehicles.clear()
	_vehicle_ids.clear()
	_vehicle_targets.clear()
	_crates.clear()
	_crate_ids.clear()
	_ride_history.clear()
	_ride_fix = Vector3.ZERO
	_ride_turn = 0.0
	_ride_entry = []
	_sent_kills.clear()
	_sent_standing.clear()
	_sent_war = -1.0
	_sent_points.clear()
	_sent_heat.clear()
	_sent_hunted.clear()
	_sent_tracks.clear()
	_actor_account.clear()
	_board_sent.clear()


func _register(actor: Actor) -> int:
	var id := _next_id
	_next_id += 1
	_actors[id] = actor
	_ids[actor] = id
	return id


## Signing in. A new connection is held in Godot's handshake
## (`SceneMultiplayer.auth_callback`) until it has signed in, and only then
## counts as connected. The client sends one Dictionary (`var_to_bytes`):
## {"protocol", "manifest", "build", "name", "secret"}, or the same with
## "token" (the token an earlier sign-in gave it, below) in place of
## "secret", or {"protocol", "probe": true} to only fetch the certificate
## (`ServerTrust`); the server answers with one: {"ok": true, "protocol",
## "world", "certificate", "token"} or {"ok": false, "protocol", "error",
## "certificate"}. Both always carry "protocol", in every version to come,
## so any two versions can tell each other apart and say which one needs
## the update. Keep that shape whatever else changes.
##
## "manifest" is the digest of what this build says once signed in
## (`NetManifest.own_digest`), and the server lets in only a game whose
## digest is its own. One that differs is answered {"ok": false, "outdated",
## "build", "manifest"}: the server's build number and its whole manifest,
## so the game can say which side is older (`NetManifest.older`; "either"
## when a build carries no number) and name what differs in its log.
##
## The token stands for the sign-in (`StashService.sign_in_with`): the game
## shows it to the next server it travels to instead of its secret, and
## every server of one account service accepts it. A token that has run out
## is answered {"ok": false, "again": "secret"} and the connection is kept,
## for the game to sign in with its secret on it.
func _server_auth(peer: int, data: PackedByteArray) -> void:
	if _peer_account.has(peer) or _signing_in.has(peer):
		return
	var hello: Variant = bytes_to_var(data) if data.size() <= MAX_AUTH_BYTES else null
	if typeof(hello) != TYPE_DICTIONARY:
		_refuse(peer, "That is not a Verge game.")
		return
	var protocol := _protocol_in(hello)
	if protocol != PROTOCOL:
		_refuse(peer, "Versions differ.", "client" if protocol < PROTOCOL else "server")
		return
	if hello.get("probe", false):
		# Only asking which certificate this server shows (it changed).
		_refuse(peer, "Certificate only.")
		return
	if str(hello.get("manifest", "")) != NetManifest.own_digest():
		# The same handshake, but what is said after it differs.
		var their_build: Variant = hello.get("build")
		var side := NetManifest.older(build, int(their_build) if typeof(their_build) == TYPE_INT else 0)
		_refuse(peer, "Versions differ.", {"mine": "server", "theirs": "client"}.get(side, "either"),
				{"build": build, "manifest": NetManifest.own()})
		return
	var token := str(hello.get("token", "")).left(256)
	var credentials := {"method": "token", "token": token} if token != "" else \
			{"method": "secret", "name": str(hello.get("name", "")).left(64), "secret": str(hello.get("secret", "")).left(256)}
	_signing_in[peer] = true
	var result: Dictionary = await stash.sign_in_with(credentials)
	_signing_in.erase(peer)
	if not is_inside_tree() or _api.multiplayer_peer == null or peer not in _api.get_authenticating_peers():
		# Gone while the accounts were asked.
		if result.get("ok", false):
			_release_if_unused(str(result.account_id))
		return
	if not result.ok:
		if result.get("expired", false):
			_api.send_auth(peer, var_to_bytes({"ok": false, "protocol": PROTOCOL, "again": "secret",
					"certificate": _certificate}))
			return
		_refuse(peer, result.error)
		return
	_peer_account[peer] = result.account_id
	if hello.get("ahead", false):
		_ahead[peer] = true
	# The newest sign-in wins. An older connection for the same account (a
	# crashed game, one whose connection dropped and that the server has not
	# noticed yet, or another game signing in) is let go: its body is left
	# standing like any dropped player's, so this sign-in can take it back
	# (`_on_peer_connected`). It is told why first, so a game that is still
	# running does not try to reconnect and push this one out in turn.
	for other: int in _peer_account.keys():
		if other == peer or _peer_account[other] != result.account_id:
			continue
		if other in _api.get_peers():
			_on_peer_disconnected(other)
			_replaced.rpc_id(other)
			get_tree().create_timer(0.5).timeout.connect(func() -> void:
				if _api.multiplayer_peer != null and other in _api.get_peers():
					_api.disconnect_peer(other))
		else:
			_api.disconnect_peer(other)
		_peer_account.erase(other)
	var welcome := {"ok": true, "protocol": PROTOCOL, "world": world_id, "certificate": _certificate}
	if result.has("token"):
		welcome["token"] = result.token
	_api.send_auth(peer, var_to_bytes(welcome))
	_api.complete_auth(peer)


## Server: turns a connection away during the handshake with a reason its
## game can show, then drops it once the answer has had time to arrive.
## `outdated_side` is "client" or "server" when the versions differ
## ("either" when nobody can say which is older), and `more` goes in the
## answer as it is.
func _refuse(peer: int, reason: String, outdated_side := "", more := {}) -> void:
	var answer := {"ok": false, "protocol": PROTOCOL, "error": reason, "certificate": _certificate}
	answer.merge(more)
	if outdated_side != "":
		answer["outdated"] = outdated_side
	_api.send_auth(peer, var_to_bytes(answer))
	get_tree().create_timer(1.0).timeout.connect(func() -> void:
		if _api.multiplayer_peer != null and peer in _api.get_authenticating_peers():
			_api.disconnect_peer(peer))


static func _protocol_in(message: Dictionary) -> int:
	var value: Variant = message.get("protocol")
	return int(value) if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT else -1


## Server: whether the player who sent the call being handled may make
## another request of this `kind` now (see `RequestLimits`). A refused one
## is dropped; a player told to slow down hears it at most now and then; a
## connection that floods the server is dropped.
func _allow(kind: String) -> bool:
	if not is_server:
		return true
	var peer := _api.get_remote_sender_id()
	if _limits.allow(peer, kind, _tick):
		return true
	if _limits.flooding(peer):
		print("Server: dropped peer %d for flooding requests" % peer)
		_limits.forget(peer)
		_api.disconnect_peer(peer)
	elif kind != "input" and _limits.may_warn(peer, _tick) and peer in _api.get_peers():
		var text := "Too many requests. Slow down a moment."
		if kind == "social":
			_social_error.rpc_id(peer, text)
		elif _peer_actor.has(peer):
			_notice.rpc_id(peer, text)
		else:
			_lobby_error.rpc_id(peer, text)
	return false


## Server: a connection left before it finished signing in.
func _on_server_auth_failed(peer: int) -> void:
	var left: String = _peer_account.get(peer, "")
	_peer_account.erase(peer)
	_ahead.erase(peer)
	_limits.forget(peer)
	_release_if_unused(left)


## Server: tells the accounts when nobody on this server is signed in to
## `account_id` any more (an `AccountLink` then stops keeping it up to date).
func _release_if_unused(account_id: String) -> void:
	if account_id == "" or not is_instance_valid(stash):
		return
	for session in _hosting:
		if account_id in session._peer_account.values():
			return
	stash.release(account_id)


## Server: whether `peer` is still connected and signed in, for whatever
## follows a call to the accounts that may have taken a moment.
func _here(peer: int) -> bool:
	return _peer_account.has(peer) and _api.multiplayer_peer != null and peer in _api.get_peers()


## Server: an account changed from somewhere else (`AccountLink.account_changed`).
func _on_account_changed(account_id: String) -> void:
	for peer: int in _peer_account:
		if _peer_account[peer] == account_id:
			_send_account(peer)


## Server: the market's board changed (`AccountLink.market_changed`).
func _on_market_changed() -> void:
	for viewer in _market_viewers.duplicate():
		_send_market(viewer)


## A peer that signed in is now connected: it is in the lobby.
func _on_peer_connected(peer: int) -> void:
	if not _peer_account.has(peer):
		_api.disconnect_peer(peer)
		return
	var out := _routes_out()
	if not out.is_empty():
		_routes.rpc_id(peer, out)
		_world_status.rpc_id(peer, _gather_status())
	# Back after a dropped connection: to the body still standing, or with
	# word of how the life ended while they were away. Said before the
	# account, so the game knows not to deploy again. A game that only
	# connected ahead of a trip here is not here yet: its body waits until
	# it asks to come in (`_request_join`).
	var account_id: String = _peer_account[peer]
	var body: Actor = null if _ahead.has(peer) else _unguarded_body(account_id)
	if body != null:
		_back.rpc_id(peer, BACK_IN_BODY)
	elif _missed.has(account_id):
		_back.rpc_id(peer, str(_missed[account_id]))
	_missed.erase(account_id)
	_send_account(peer)
	_send_clans(peer)
	_social_joined(peer)
	if body != null:
		_reclaim(peer, body)


## Server: the body an account's dropped connection left standing, if it is
## still there to come back to, else null.
func _unguarded_body(account_id: String) -> Actor:
	if raid == null:
		return null
	# Untyped: a body freed meanwhile cannot be assigned to an `Actor`.
	for actor: Variant in _actor_account:
		if _actor_account[actor] == account_id and is_instance_valid(actor) and not _actor_peer.has(actor) \
				and raid.is_unguarded(actor):
			return actor as Actor
	return null


## Server: puts a player who reconnected back into the body they left
## standing (`Raid.reclaim_player`), and tells their fresh game everything a
## new arrival hears, plus what only the owner knows (pack, watch, counters).
func _reclaim(peer: int, actor: Actor) -> void:
	if not raid.reclaim_player(actor):
		return
	_peer_actor[peer] = actor
	_actor_peer[actor] = peer
	# The new game numbers its inputs from the start again.
	_applied_seq[_ids[actor]] = 0
	_seen_tick.erase(actor)
	_joined_peers.append(peer)
	_social_moved(peer, "hub" if raid.world.safe_zone else "raid")
	_welcome.rpc_id(peer, _ids[actor])
	_send_world(peer)
	var id: int = _ids[actor]
	if actor.visor.item_id != "":
		_worn_changed.rpc_id(peer, id, "helmet", actor.visor.item_id)
	if actor.frame_id != "":
		_worn_changed.rpc_id(peer, id, "armor", actor.frame_id)
	# A rig or chip swapped from the pack since the deploy.
	_worn_changed.rpc_id(peer, id, "flight_rig", actor.flight.item_id if actor.flight.enabled else "")
	_worn_changed.rpc_id(peer, id, "ability", actor.ability.item_id if actor.ability.enabled else "")
	var arms: Array = []
	for weapon in actor.weapons:
		var gun := weapon as Gun
		if gun == null or not ItemDB.has_tag(gun.item_id, "power"):
			arms.append([weapon.item_id, gun.ammo_in_mag if gun else -1, gun.reserve_ammo if gun else -1])
	_rearm.rpc_id(peer, arms, actor.active_weapon_index)
	_inventory.rpc_id(peer, actor.inventory.items)
	_send_watch(actor)
	_send_tally(actor)
	_send_banked(actor)
	var state := raid.state_for(actor)
	if state != null and state.sign_out_left >= 0.0:
		_sign_out.rpc_id(peer, state.sign_out_left, state.sign_out_total, state.count_rate)


func _on_peer_disconnected(peer: int) -> void:
	_joined_peers.erase(peer)
	_limits.forget(peer)
	_ahead.erase(peer)
	_leaving = peer
	_social_left(peer)
	_leaving = 0
	var left: String = _peer_account.get(peer, "")
	_peer_account.erase(peer)
	_signing_in.erase(peer)
	_deploying.erase(peer)
	_release_if_unused(left)
	_market_viewers.erase(peer)
	_peer_look.erase(peer)
	_inputs.erase(peer)
	_died_at.erase(peer)
	# Their body stays in the world for a while. The run is settled into the
	# account when it is killed or its sign-out runs out.
	var actor: Actor = _peer_actor.get(peer)
	_peer_actor.erase(peer)
	if actor != null and _actor_peer.get(actor, 0) == peer:
		# Nobody plays it now; a new sign-in to the account may take it back.
		_actor_peer.erase(actor)
	if actor != null and is_instance_valid(actor) and raid != null:
		raid.remove_player(actor)


func _on_server_actor_spawned(actor: Actor) -> void:
	# A joining player's look is put on before anyone is told about them.
	if not _joining_look.is_empty() and raid.state_for(actor) != null:
		Look.set_appearance(actor, _joining_look)
		_joining_look = {}
	var id := _register(actor)
	actor.died.connect(func(_a: Actor, info: DamageInfo) -> void: _dead_kind[id] = info.kind)
	# A power weapon taken off a rack, swapped or spent is shown to all.
	actor.power_changed.connect(func(item_id: String, mag: int, reserve: int) -> void:
		for peer in _joined_peers:
			_power_changed.rpc_id(peer, id, item_id, mag, reserve))
	# A helmet or armor frame put on is seen by everyone, and its wearer's
	# visor and frame follow.
	actor.helmet_changed.connect(func(item_id: String) -> void:
		for peer in _joined_peers:
			_worn_changed.rpc_id(peer, id, "helmet", item_id))
	actor.frame_changed.connect(func(item_id: String) -> void:
		for peer in _joined_peers:
			_worn_changed.rpc_id(peer, id, "armor", item_id))
	# So is a flight rig or ability chip swapped in from the pack.
	actor.rig_changed.connect(func(item_id: String) -> void:
		for peer in _joined_peers:
			_worn_changed.rpc_id(peer, id, "flight_rig", item_id))
	actor.ability_changed.connect(func(item_id: String) -> void:
		for peer in _joined_peers:
			_worn_changed.rpc_id(peer, id, "ability", item_id))
	# What a body carries weighs on how it moves (`CarryLoad`), and a client
	# never sees anyone else's pack, so the load itself is sent: only when it
	# changes, which is when gear or the pack does.
	actor.carry_changed.connect(func(kg: float) -> void:
		for peer in _joined_peers:
			_carry.rpc_id(peer, id, kg))
	# A weapon summoned from the watch is shown to all.
	actor.weapon_swapped.connect(func(item_id: String, mag: int, reserve: int) -> void:
		for peer in _joined_peers:
			_weapon_swapped.rpc_id(peer, id, item_id, mag, reserve))
	# So is one stored back into the pack.
	actor.weapon_stored.connect(func(item_id: String, _mag: int, _reserve: int) -> void:
		for peer in _joined_peers:
			_weapon_stored.rpc_id(peer, id, item_id))
	for peer in _joined_peers:
		_send_spawn(peer, actor)


func _on_server_actor_removed(actor: Actor) -> void:
	if not _ids.has(actor):
		return
	var id: int = _ids[actor]
	for peer in _joined_peers:
		_despawn.rpc_id(peer, id)
	_ids.erase(actor)
	_actors.erase(id)
	_seen_tick.erase(actor)
	for tick: int in _past:
		_past[tick].erase(actor)
	for tier in DETAIL_EVERY.size():
		_one_shots[tier].erase(id)
		_switches[tier].erase(id)
	_dead_kind.erase(id)
	_sent_kills.erase(id)
	_sent_standing.erase(id)
	var peer: int = _actor_peer.get(actor, 0)
	_actor_peer.erase(actor)
	if peer != 0 and _peer_actor.get(peer) == actor:
		_peer_actor.erase(peer)


func _on_server_container_spawned(container: LootContainer) -> void:
	var id := _next_id
	_next_id += 1
	_containers[id] = container
	_container_ids[container] = id
	container.changed.connect(func() -> void:
		for peer in _joined_peers:
			_container_items.rpc_id(peer, id, container.items, container.scrip))
	container.tree_exited.connect(func() -> void:
		if not _containers.has(id):
			return
		_containers.erase(id)
		_container_ids.erase(container)
		for peer in _joined_peers:
			_container_gone.rpc_id(peer, id))
	for peer in _joined_peers:
		_send_container(peer, id)


func _send_container(peer: int, id: int) -> void:
	var container: LootContainer = _containers[id]
	_container.rpc_id(peer, id, container.items, container.is_bag, container.label, container.global_position,
			container.scrip if container.pile else -1, container.bounty)


func _on_server_vehicle_spawned(vehicle: Node3D) -> void:
	var id := _next_id
	_next_id += 1
	_vehicles[id] = vehicle
	_vehicle_ids[vehicle] = id
	for peer in _joined_peers:
		_send_vehicle(peer, id)


func _on_server_vehicle_removed(vehicle: Node3D) -> void:
	if not _vehicle_ids.has(vehicle):
		return
	var id: int = _vehicle_ids[vehicle]
	_vehicle_ids.erase(vehicle)
	_vehicles.erase(id)
	_vehicle_parked.erase(id)
	for peer in _joined_peers:
		_vehicle_gone.rpc_id(peer, id)


## Server: a salvage crate (`SalvageCrate`) is told to everyone, and where
## it is each time it moves: on the ground, in someone's hands or in a
## vehicle's cargo. Its contents stay on the server until it is banked.
func _on_server_crate_spawned(crate: SalvageCrate) -> void:
	var id := _next_id
	_next_id += 1
	_crates[id] = crate
	_crate_ids[crate] = id
	crate.moved.connect(func() -> void:
		var where := _crate_where(crate)
		for peer in _joined_peers:
			_crate_moved.rpc_id(peer, id, where))
	crate.tree_exited.connect(func() -> void:
		if not _crates.has(id):
			return
		_crates.erase(id)
		_crate_ids.erase(crate)
		for peer in _joined_peers:
			_crate_gone.rpc_id(peer, id))
	for peer in _joined_peers:
		_send_crate(peer, id)


func _send_crate(peer: int, id: int) -> void:
	_crate.rpc_id(peer, id, _crate_where(_crates[id]))


## Where a crate is, as sent: [position, holder kind (0 the ground, 1 an
## actor, 2 a vehicle), the holder's id, cargo slot].
func _crate_where(crate: SalvageCrate) -> Array:
	var holder := crate.holder
	if holder is Actor and _ids.has(holder):
		return [crate.global_position, 1, int(_ids[holder]), -1]
	if holder != null and _vehicle_ids.has(holder):
		return [crate.global_position, 2, int(_vehicle_ids[holder]), crate.slot]
	return [crate.global_position, 0, -1, -1]


@rpc("authority", "call_remote", "reliable")
func _crate(id: int, where: Array) -> void:
	if raid == null or _crates.has(id):
		return
	var crate := raid.spawn_crate([], where[0] if where.size() > 0 and where[0] is Vector3 else Vector3.ZERO)
	_crates[id] = crate
	_crate_ids[crate] = id
	_crate_moved(id, where)


@rpc("authority", "call_remote", "reliable")
func _crate_moved(id: int, where: Array) -> void:
	var crate: SalvageCrate = _crates.get(id)
	if crate == null or not is_instance_valid(crate) or where.size() < 4 or not where[0] is Vector3:
		return
	# Let go of wherever it was.
	if crate.holder is Actor and is_instance_valid(crate.holder) and (crate.holder as Actor).crate == crate:
		(crate.holder as Actor).crate = null
	elif crate.holder != null and is_instance_valid(crate.holder) and crate.holder.get("cargo") is Array:
		var cargo: Array = crate.holder.get("cargo")
		var was := cargo.find(crate)
		if was >= 0:
			cargo[was] = null
	var kind := int(where[1])
	var holder_id := int(where[2])
	if kind == 1 and _actors.has(holder_id) and is_instance_valid(_actors[holder_id]):
		var actor: Actor = _actors[holder_id]
		actor.crate = crate
		crate.place(actor)
	elif kind == 2 and _vehicles.has(holder_id) and is_instance_valid(_vehicles[holder_id]):
		var vehicle: Node3D = _vehicles[holder_id]
		var slot := int(where[3])
		var cargo: Array = vehicle.get("cargo")
		if slot >= 0 and slot < cargo.size():
			cargo[slot] = crate
		crate.place(vehicle, slot)
	else:
		crate.global_position = where[0]
		crate.place(null)


func _on_server_field_changed(_index: int, _buried: bool) -> void:
	var packed := raid.pack_fields()
	for peer in _joined_peers:
		_fields.rpc_id(peer, packed)


## Which salvage fields a storm has buried (`Raid.pack_fields`): the client
## sinks or raises their scenery to match.
@rpc("authority", "call_remote", "reliable")
func _fields(buried: Array) -> void:
	if raid == null:
		return
	for i in mini(buried.size(), raid.fields.size()):
		if typeof(buried[i]) == TYPE_BOOL:
			raid.set_field_buried(i, buried[i])


@rpc("authority", "call_remote", "reliable")
func _crate_gone(id: int) -> void:
	var crate: SalvageCrate = _crates.get(id)
	_crates.erase(id)
	if crate == null or not is_instance_valid(crate):
		return
	_crate_ids.erase(crate)
	if crate.holder is Actor and is_instance_valid(crate.holder) and (crate.holder as Actor).crate == crate:
		(crate.holder as Actor).crate = null
	crate.queue_free()


func _send_vehicle(peer: int, id: int) -> void:
	var vehicle: Node3D = _vehicles[id]
	_vehicle.rpc_id(peer, id, vehicle.get("item_id"), vehicle.global_position, vehicle.get("heading"),
			float(vehicle.get("unpack_left")) > 0.0)


## Tells a player what is on their watch and how long until the next throw.
func _send_watch(actor: Actor) -> void:
	var peer: int = _actor_peer.get(actor, 0)
	if peer != 0 and peer in _joined_peers and raid != null:
		var state := raid.state_for(actor)
		_watch.rpc_id(peer, raid.stowed_for(actor), raid.toy_wait(actor), raid.summon_wait(actor),
				state.summon_wait_total if state != null else 0.0)


## Tells a player their contract counters for this life. Only the owner
## hears them.
func _send_tally(actor: Actor) -> void:
	var peer: int = _actor_peer.get(actor, 0)
	if peer != 0 and peer in _joined_peers and raid != null:
		_tally.rpc_id(peer, actor.tally)


## Tells a player what this life has sent home through depots, for the
## watch's banking readout. Only the owner hears it.
func _send_banked(actor: Actor) -> void:
	var peer: int = _actor_peer.get(actor, 0)
	if peer != 0 and peer in _joined_peers:
		_banked.rpc_id(peer, actor.banked_count, actor.banked_value, actor.banked_scrip)


func _on_server_player_finished(actor: Actor, result: Dictionary) -> void:
	var peer: int = _actor_peer.get(actor, 0)
	var online := peer != 0 and peer in _api.get_peers()
	# The stash only ever changes from the server's own result.
	var account_id: String = _actor_account.get(actor, "")
	var at_risk := raid.world.gear_at_risk
	_actor_account.erase(actor)
	# The session's own books first: settling may take a moment where the
	# accounts are a service away, and the player is free to drop in again
	# meanwhile (that deploy is asked after this settle, so it sees it).
	if _peer_actor.get(peer) == actor:
		# Free to drop in again, after a short wait if they died.
		_peer_actor.erase(peer)
		if _inputs.has(peer):
			(_inputs[peer] as InputBuffer).rest()
		if result.get("outcome", "") == "died":
			_died_at[peer] = Time.get_ticks_msec()
	if not online and account_id != "" and not raid.world.safe_zone:
		# Ended while they were away (a body left by a dropped connection):
		# they hear how when they sign in again.
		_missed[account_id] = str(result.get("outcome", ""))
		# A dead player is still in the world, about to drop back in.
		if result.get("outcome", "") != "died":
			_social_moved(peer, "lobby")
	if account_id != "":
		# Nothing to settle where no gear was at risk (the arena).
		if at_risk:
			var settled: Dictionary = await stash.settle(account_id, result)
			# Contracts this life finished, for the player's own report.
			var paid: Dictionary = settled.get("contracts", {})
			if not paid.get("finished", []).is_empty():
				result["contracts_finished"] = paid.finished
				result["contract_scrip"] = paid.scrip
		# Everyone signed in to the account hears, including a player back in
		# the lobby whose old body just finished its sign-out.
		for other: int in _peer_account:
			if _peer_account[other] == account_id and _here(other):
				_account.rpc_id(other, stash.snapshot(account_id))
	if online and _api.multiplayer_peer != null and peer in _api.get_peers():
		_run_finished.rpc_id(peer, result)


## Banked loot goes straight into the account's stash.
func _on_server_player_banked(actor: Actor, items: Array) -> void:
	var account_id: String = _actor_account.get(actor, "")
	if account_id == "":
		return
	var peer: int = _actor_peer.get(actor, 0)
	await stash.bank(account_id, items)
	if peer != 0 and _here(peer) and _peer_account[peer] == account_id:
		_account.rpc_id(peer, stash.snapshot(account_id))


func _on_server_sign_out_changed(actor: Actor, seconds_left: float) -> void:
	var peer: int = _actor_peer.get(actor, 0)
	var state := raid.state_for(actor) if raid != null else null
	if peer != 0 and peer in _api.get_peers():
		var total := state.sign_out_total if state != null else maxf(seconds_left, 0.0)
		_sign_out.rpc_id(peer, seconds_left, total, state.count_rate if state != null else 1.0)
	# A portal home unfolds over its opener's countdown: when that changes
	# (lifting off or landing), everyone sees the ring in step again.
	if state != null and seconds_left >= 0.0:
		for portal in raid.portals:
			if is_instance_valid(portal) and portal.signs_out and portal.opener == state.owner:
				for other in _joined_peers:
					_send_portal(other, portal)


func _send_account(peer: int) -> void:
	if _here(peer):
		_account.rpc_id(peer, stash.snapshot(_peer_account[peer]))


## Server: answers a lobby request: why it was refused, if it was, and the
## account as it now stands.
func _lobby_answer(peer: int, result: Dictionary) -> void:
	if not _here(peer):
		return
	if not result.get("ok", false):
		_lobby_error.rpc_id(peer, str(result.get("error", "That did not work.")))
	_send_account(peer)


func _send_clans(peer: int) -> void:
	_clan.rpc_id(peer, clans.snapshot(_peer_account[peer], stash.name_of))


## The clan hall: found a clan ("create", name, tag), join one ("join", clan
## id) or leave yours ("leave"). Refused while your body is in a world where
## gear is at stake, so nobody changes sides in the middle of a fight.
@rpc("any_peer", "call_remote", "reliable")
func _request_clan(action: String, a := "", b := "") -> void:
	if not _allow("social"):
		return
	var peer := _api.get_remote_sender_id()
	if not is_server or not _peer_account.has(peer):
		return
	var account_id: String = _peer_account[peer]
	if action not in ["create", "join", "leave"]:
		return
	var result: Dictionary
	if stash.snapshot(account_id).get("deployed", false):
		result = {"ok": false, "error": "Not while you are in the field."}
	elif stash.is_remote():
		# The account service keeps the clans; every server hears the change
		# (`_on_clans_changed`), this one before the answer is back.
		result = await stash.clan(action, account_id, a.left(64), b.left(16))
		if not _here(peer):
			return
	else:
		result = clans.ask(action, account_id, a.left(64), b.left(16))
		if result.ok:
			for session in _hosting:
				if is_instance_valid(session) and session.clans == clans:
					session._on_clans_changed()
	if not result.ok:
		_lobby_error.rpc_id(peer, str(result.get("error", "That did not work.")))


## Server: the clans changed (here, in another session of this server, or
## on another server of the same account service). Everyone signed in here
## sees the new list, and the tag over a player's head changes for everyone
## standing with them.
func _on_clans_changed() -> void:
	if not is_server or raid == null:
		return
	for peer: int in _peer_account:
		if _here(peer):
			_send_clans(peer)
	for peer: int in _peer_actor:
		var actor: Actor = _peer_actor[peer]
		if not is_instance_valid(actor) or not _peer_account.has(peer) or not _ids.has(actor):
			continue
		var before := [actor.clan, actor.clan_tag]
		_wear_clan(actor, _peer_account[peer])
		if before != [actor.clan, actor.clan_tag]:
			for other in _joined_peers:
				_clan_tag.rpc_id(other, _ids[actor], actor.clan, actor.clan_tag)


## Server: marks an actor with its account's clan. Only where gear is at
## stake do clanmates become one side; anywhere else the tag is worn and the
## clan is a squad (`Raid.set_squad`), for squad portals.
func _wear_clan(actor: Actor, account_id: String) -> void:
	var clan_id := clans.clan_of(account_id)
	actor.clan_tag = clans.tag_of(clan_id)
	actor.clan = clan_id if _clans_fight_together() else ""
	# A clan is also a squad, everywhere: who may use a portal it opens,
	# unless the player is in a squad of their own making (the phone's).
	_set_squad_key(account_id, _social_squad(account_id))


## Server: the squad key the `Raid` keeps for `account_id`: the phone's
## squad (`SocialService.squad_of`) if they are in one, else their clan.
func _set_squad_key(account_id: String, squad: String) -> void:
	if raid == null:
		return
	if squad != "":
		raid.set_squad(account_id, "party:" + squad)
	else:
		raid.set_squad(account_id, clans.clan_of(account_id))


## Server: the phone's squad `account_id` is in, or "".
func _social_squad(account_id: String) -> String:
	if stash.is_remote():
		return str(stash.social_snapshot(account_id).get("squad", {}).get("id", ""))
	return social.squad_of(account_id) if social != null else ""


func _clans_fight_together() -> bool:
	return raid != null and raid.world.gear_at_risk and not raid.world.safe_zone


## Lobby: put a stash item in a loadout slot, or "" to empty the slot.
@rpc("any_peer", "call_remote", "reliable")
func _request_equip(slot: String, item_id: String) -> void:
	if not _allow("lobby"):
		return
	var peer := _api.get_remote_sender_id()
	if not is_server or not _peer_account.has(peer):
		return
	var account_id: String = _peer_account[peer]
	var result: Dictionary = await stash.unequip(account_id, slot) if item_id == "" \
			else await stash.equip(account_id, slot, item_id)
	_lobby_answer(peer, result)


## Lobby: pick a mastery variant, or "" for stock.
@rpc("any_peer", "call_remote", "reliable")
func _request_pick(track: String, variant_id: String) -> void:
	if not _allow("lobby"):
		return
	var peer := _api.get_remote_sender_id()
	if not is_server or not _peer_account.has(peer):
		return
	var result: Dictionary = await stash.pick_mastery(_peer_account[peer], track, variant_id)
	_lobby_answer(peer, result)


## Lobby: buy one item from a hub shop. The server sets the price.
@rpc("any_peer", "call_remote", "reliable")
func _request_buy(shop_id: String, item_id: String) -> void:
	if not _allow("lobby"):
		return
	var peer := _api.get_remote_sender_id()
	if not is_server or not _peer_account.has(peer):
		return
	var result: Dictionary = await stash.buy(_peer_account[peer], shop_id, item_id)
	_lobby_answer(peer, result)


## Lobby: the contract board. Take or drop a job, or reroll the offers. The
## server decides; the answer is a fresh account snapshot.
@rpc("any_peer", "call_remote", "reliable")
func _request_contract(action: String, job_id: String) -> void:
	if not _allow("lobby"):
		return
	var peer := _api.get_remote_sender_id()
	if not is_server or not _peer_account.has(peer):
		return
	var result: Dictionary = await stash.contract(_peer_account[peer], action.left(16), job_id.left(32))
	_lobby_answer(peer, result)


## Lobby: buy a home base upgrade. The server checks what it needs and sets
## the price.
@rpc("any_peer", "call_remote", "reliable")
func _request_buy_upgrade(upgrade_id: String) -> void:
	if not _allow("lobby"):
		return
	var peer := _api.get_remote_sender_id()
	if not is_server or not _peer_account.has(peer):
		return
	var result: Dictionary = await stash.buy_upgrade(_peer_account[peer], upgrade_id.left(64))
	_lobby_answer(peer, result)


## Lobby: change your home base's plan (`BasePlan.change`): move a room into
## a socket, or with "shape" or "style:<room>" pick a hub shape or a room
## style your upgrades unlock. Free, and the server keeps the plan with the
## account.
@rpc("any_peer", "call_remote", "reliable")
func _request_place_room(socket: String, room: String) -> void:
	if not _allow("lobby"):
		return
	var peer := _api.get_remote_sender_id()
	if not is_server or not _peer_account.has(peer):
		return
	var result: Dictionary = await stash.place_room(_peer_account[peer], socket.left(24), room.left(32))
	_lobby_answer(peer, result)


## The market kiosk: "view" opens the board (and keeps it fresh while
## open), "close" stops that, "list" puts `count` of `item_id` up at `price`
## each, "buy" takes `count` from listing `listing_id`, "cancel" takes your
## own listing down. Only in a safe zone and never while deployed; the
## board's rules (`Market`) and the server decide everything else.
@rpc("any_peer", "call_remote", "reliable")
func _request_market(action: String, item_id: String, a: int, b: int) -> void:
	var peer := _api.get_remote_sender_id()
	if not is_server or not _peer_account.has(peer):
		return
	var account_id: String = _peer_account[peer]
	var result := {"ok": true}
	if LaunchScope.holds("market"):
		# The launch holds the player market back (`LaunchScope`).
		return
	match action:
		"view":
			if peer not in _market_viewers:
				_market_viewers.append(peer)
		"close":
			_market_viewers.erase(peer)
			return
		"list", "buy", "cancel":
			if raid == null or not raid.world.safe_zone:
				result = {"ok": false, "error": "Trade at the market kiosk in the plaza."}
			elif stash.is_deployed(account_id):
				result = {"ok": false, "error": "Not while you are in the field."}
			elif stash.is_remote():
				# The board is the account service's: one request, sent once.
				var asked: Dictionary = await stash.market(action, account_id, item_id.left(64), a, b)
				result = asked.result if asked.get("ok", false) else asked
				if not _here(peer):
					return
			elif action == "list":
				result = market.list(stash, account_id, item_id.left(64), a, b)
			elif action == "buy":
				result = market.buy(stash, account_id, a, b)
			else:
				result = market.cancel(stash, account_id, a)
		_:
			return
	if not result.ok:
		_lobby_error.rpc_id(peer, result.error)
	if action != "view":
		_send_account(peer)
		# The seller is paid wherever they are on this server.
		if result.ok and action == "buy":
			_resend_account(str(result.seller))
		# Everyone with the kiosk open sees the board change (the account
		# service says so itself, to every server).
		if not stash.is_remote():
			for viewer in _market_viewers:
				if viewer != peer:
					_send_market(viewer)
	_send_market(peer)


func _send_market(peer: int) -> void:
	if not _peer_account.has(peer):
		return
	if stash.is_remote():
		var board: Dictionary = await stash.board(_peer_account[peer])
		if not board.is_empty() and _here(peer):
			_market.rpc_id(peer, board)
		return
	market.expire(stash)
	_market.rpc_id(peer, market.snapshot(_peer_account[peer], stash.name_of))


## Server: sends a fresh account snapshot to whoever is signed in as
## `account_id` in any session of this server.
func _resend_account(account_id: String) -> void:
	for session in _hosting:
		for peer: int in session._peer_account:
			if session._peer_account[peer] == account_id:
				session._send_account(peer)


## Lobby: craft one item at the gunsmith bench. The server checks the
## blueprint and takes the parts and the fee.
@rpc("any_peer", "call_remote", "reliable")
func _request_craft(item_id: String) -> void:
	if not _allow("lobby"):
		return
	var peer := _api.get_remote_sender_id()
	if not is_server or not _peer_account.has(peer):
		return
	var result: Dictionary = await stash.craft(_peer_account[peer], item_id.left(64))
	_lobby_answer(peer, result)


## Lobby: "insure" one stash item or "cancel" the policy at the fabricator
## (`StashService.insure`). The server decides what it costs.
@rpc("any_peer", "call_remote", "reliable")
func _request_insure(action: String, item_id: String) -> void:
	if not _allow("lobby"):
		return
	var peer := _api.get_remote_sender_id()
	if not is_server or not _peer_account.has(peer):
		return
	var result: Dictionary = await stash.insure(_peer_account[peer], action.left(16), item_id.left(64))
	_lobby_answer(peer, result)


## Lobby: sell stash items for scrip. An empty `item_id` sells all loot.
@rpc("any_peer", "call_remote", "reliable")
func _request_sell(item_id: String, count: int) -> void:
	if not _allow("lobby"):
		return
	var peer := _api.get_remote_sender_id()
	if not is_server or not _peer_account.has(peer):
		return
	var result: Dictionary = await stash.sell(_peer_account[peer], item_id, count)
	_lobby_answer(peer, result)


## Lobby: how the player's character looks. Looks are cosmetic, so this is
## the one thing a client gets to choose; it is still checked, and a look can
## only name parts and colours that exist.
@rpc("any_peer", "call_remote", "reliable")
func _request_look(p_look: Dictionary) -> void:
	if not _allow("lobby"):
		return
	var peer := _api.get_remote_sender_id()
	if not is_server or not _peer_account.has(peer):
		return
	# Only clothing the account owns: the stash decides, not the client.
	var owned := Economy.unlocked_outfits(stash.snapshot(_peer_account[peer]).get("stash", []))
	var cleaned := Look.clean_appearance(p_look, owned)
	_peer_look[peer] = cleaned
	# Already in this world (changed in front of the phone's mirror): everyone
	# here sees it now, the player included, so their game shows what passed.
	var actor: Actor = _peer_actor.get(peer)
	if actor == null or not is_instance_valid(actor) or not _ids.has(actor) \
			or actor.get_meta("appearance", {}) == cleaned:
		return
	Look.set_appearance(actor, cleaned)
	for other in _joined_peers:
		if other in _api.get_peers():
			_look_changed.rpc_id(other, _ids[actor], cleaned)


## Client: someone in this world changed how they look. The server checked it.
@rpc("authority", "call_remote", "reliable")
func _look_changed(id: int, p_look: Dictionary) -> void:
	var actor: Actor = _actors.get(id)
	if actor == null or not is_instance_valid(actor):
		return
	var cleaned := Human.sanitize(p_look)
	if actor.get_meta("appearance", {}) != cleaned:
		Look.set_appearance(actor, cleaned)


## Server: the look a signed-in player chose, or {} if they sent none.
func look_for_peer(peer: int) -> Dictionary:
	return _peer_look.get(peer, {})


## Client: tells the server how this player looks. It is used from the next
## deploy, and if the player is already in a world everyone there sees it now.
func send_look(p_look: Dictionary) -> void:
	look = p_look
	if not is_server and not account.is_empty():
		_request_look.rpc_id(1, look)


func _send_spawn(peer: int, actor: Actor) -> void:
	var state := raid.state_for(actor)
	var data := {}
	if state != null:
		data = {"kit": state.kit, "picks": state.picks}
		var power := Loadout.power_index(actor)
		if power >= 0:
			var gun := actor.weapons[power] as Gun
			data["power"] = [gun.item_id, gun.ammo_in_mag, gun.reserve_ammo]
		if actor.has_meta("appearance"):
			data["look"] = actor.get_meta("appearance")
		if actor.clan_tag != "":
			data["clan"] = [actor.clan, actor.clan_tag]
	else:
		data = {"seed": raid.bot_seeds.get(actor, 0), "warlord": raid.warlords.has(actor),
				"faction": actor.faction, "zone": int(actor.get_meta("zone", -1))}
		if actor.has_meta("boss"):
			data["boss"] = String(actor.get_meta("boss"))
		# A rival raider wears a player's kit and look, so a client builds the
		# same person rather than a soldier from the seed.
		if actor.has_meta("raider_kit"):
			data["kit"] = actor.get_meta("raider_kit")
			if actor.has_meta("appearance"):
				data["look"] = actor.get_meta("appearance")
	_spawn.rpc_id(peer, _ids[actor], "player" if state != null else "bot", actor.display_name,
			String(actor.name), actor.global_position, actor.cmd.yaw, data)
	_carry.rpc_id(peer, _ids[actor], actor.carry_kg())


## Drop into the running world with the account's loadout: from the lobby,
## or again after a death. The kit and picks come from the server's stash,
## never from the client.
@rpc("any_peer", "call_remote", "reliable")
func _request_join(drop := "") -> void:
	if not _allow("world"):
		return
	if not is_server or raid == null:
		return
	var peer := _api.get_remote_sender_id()
	if _peer_actor.has(peer) or not _peer_account.has(peer):
		return
	if Time.get_ticks_msec() - int(_died_at.get(peer, -1000000)) < raid.world.redeploy_delay * 1000.0:
		_lobby_error.rpc_id(peer, "Not yet. You can drop in again in a moment.")
		return
	var account_id: String = _peer_account[peer]
	_ahead.erase(peer)
	# The body they left standing here when their connection dropped: back
	# into it, not a second life (a game that connected ahead of its trip
	# was not put in it when it signed in).
	var body := _unguarded_body(account_id)
	if body != null:
		_back.rpc_id(peer, BACK_IN_BODY)
		_reclaim(peer, body)
		return
	# In a safe zone the loadout is worn, not risked: it never leaves the
	# stash, and there is no run to settle afterwards.
	var safe := raid.world.safe_zone
	if _deploying.has(peer):
		return
	if _max_players > 0 and _peer_actor.size() + _deploying.size() >= _max_players:
		_lobby_error.rpc_id(peer, "%s is full right now. Try again in a moment." % raid.world.display_name)
		return
	_deploying[peer] = true
	var into := raid.world
	var deployed: Dictionary = stash.showcase(account_id, into) if safe else await stash.deploy(account_id, into)
	_deploying.erase(peer)
	if raid == null or raid.world != into or not _here(peer) or _peer_account[peer] != account_id \
			or _peer_actor.has(peer):
		# Gone while the accounts were asked for the kit: it goes back.
		if deployed.get("ok", false) and not safe and into.gear_at_risk and is_instance_valid(stash):
			stash.cancel_deploy(account_id)
		return
	if not deployed.ok:
		_lobby_error.rpc_id(peer, deployed.error)
		return
	# A peer that is dropping back in already knows the world. It must hear
	# which actor is its own before it hears that the actor exists.
	var returning := peer in _joined_peers
	_joined_peers.erase(peer)
	_joining_look = look_for_peer(peer)
	var who: Dictionary = stash.snapshot(account_id)
	var clan_id := clans.clan_of(account_id)
	raid.set_team(account_id, clan_id if _clans_fight_together() else "", clans.name_of(clan_id))
	# Renown is kept under the account, never under a name the client chose.
	var actor := raid.add_player(deployed.kit, deployed.picks, who.name, account_id, int(who.get("renown", 0)),
			drop.left(48), str(deployed.get("insured", "")))
	_joining_look = {}
	_wear_clan(actor, account_id)
	if not safe:
		_actor_account[actor] = account_id
	if raid is Arena:
		raid.set_key(actor, account_id)
	_send_account(peer)
	_peer_actor[peer] = actor
	_actor_peer[actor] = peer
	_wire_player(actor)
	_joined_peers.append(peer)
	_social_moved(peer, "hub" if safe else "raid")
	_welcome.rpc_id(peer, _ids[actor])
	if returning:
		_send_spawn(peer, actor)
		_send_watch(actor)
		return
	_send_world(peer)
	_send_watch(actor)


## Server: everything in the world a player who has just arrived must hear
## about: every actor, container, vehicle and portal, and the war.
func _send_world(peer: int) -> void:
	for other: Actor in _ids:
		if not other.is_dead:
			_send_spawn(peer, other)
	for id: int in _containers:
		_send_container(peer, id)
	for id: int in _vehicles:
		_send_vehicle(peer, id)
	for id: int in _crates:
		_send_crate(peer, id)
	if not raid.fields.is_empty():
		_fields.rpc_id(peer, raid.pack_fields())
	for id: int in _sent_kills:
		_kills.rpc_id(peer, id, _sent_kills[id])
	for id: int in _sent_standing:
		_standing.rpc_id(peer, id, _sent_standing[id])
	_war.rpc_id(peer, raid.war.intensity, raid.war.centre)
	if raid.world.weather_kind != "":
		_weather.rpc_id(peer, raid.weather.pack())
	for portal in raid.portals:
		_send_portal(peer, portal)
	_sent_points.erase(peer)
	_sent_heat.erase(peer)
	_sent_hunted.erase(peer)
	_sent_tracks.erase(peer)
	if not raid.ice_holes.is_empty():
		_ice_holes.rpc_id(peer, raid.pack_ice_holes())
	for id: String in raid.lifts:
		if raid.lift_left(id) > 0.0:
			_lift.rpc_id(peer, id, raid.lift_left(id))
	for kind: String in raid.keepers:
		if int(raid.keepers[kind]) != 1:
			_keeper.rpc_id(peer, kind, int(raid.keepers[kind]))
	if raid is Race:
		_race_board.rpc_id(peer, (raid as Race).public_board())
		_race_heats.rpc_id(peer, (raid as Race).public_heats())
		_send_friend_bests(peer)


## Server: whichever connection plays `actor` now, if it is online, else 0.
## A body outlives the connection that deployed it (it can be reclaimed by a
## new one), so anything sent to its owner asks this, never a peer id kept
## from when it was deployed.
func _owner_peer(actor: Actor) -> int:
	var peer: int = _actor_peer.get(actor, 0)
	return peer if peer != 0 and peer in _api.get_peers() else 0


## Server: hooks up what a player's own actor tells only its owner.
func _wire_player(actor: Actor) -> void:
	actor.hit_confirmed.connect(func(target: Actor, info: DamageInfo, lethal: bool) -> void:
		var peer := _owner_peer(actor)
		if peer != 0:
			_on_server_hit_confirmed(target, info, lethal, peer))
	actor.health.damaged.connect(func(info: DamageInfo) -> void:
		var peer := _owner_peer(actor)
		if peer != 0:
			_hurt.rpc_id(peer, info.amount, info.kind))
	actor.notice.connect(func(text: String) -> void:
		var peer := _owner_peer(actor)
		if peer == 0:
			return
		for prefix: String in FORWARDED_NOTICES:
			if text.begins_with(prefix):
				_notice.rpc_id(peer, text)
				return)
	actor.inventory.changed.connect(func() -> void:
		var peer := _owner_peer(actor)
		if peer != 0:
			_inventory.rpc_id(peer, actor.inventory.items))
	actor.looted.connect(func(ids: Array[String]) -> void:
		var peer := _owner_peer(actor)
		if peer != 0:
			_looted.rpc_id(peer, ids))
	# What a helmet reveals goes only to the players allowed to know it.
	actor.visor.revealed.connect(func(found: Array) -> void:
		var peer := _owner_peer(actor)
		if peer != 0:
			_visor_ghosts.rpc_id(peer, found))
	actor.visor.felt_scan.connect(func(origin: Vector3) -> void:
		var peer := _owner_peer(actor)
		if peer != 0:
			_visor_felt.rpc_id(peer, origin))
	actor.visor.tagged.connect(_on_server_tagged.bind(actor))
	actor.visor.threatened.connect(func(origin: Vector3) -> void:
		var peer := _owner_peer(actor)
		if peer != 0:
			_visor_threatened.rpc_id(peer, origin))
	actor.visor.threats_changed.connect(func(found: Array) -> void:
		var peer := _owner_peer(actor)
		if peer == 0:
			return
		var ids: Array[int] = []
		for other: Actor in found:
			if _ids.has(other):
				ids.append(_ids[other])
		_visor_threats.rpc_id(peer, ids))


## Arena: a player in it asks for something (challenge, accept, bet...).
## The server's own `Arena.request` decides, for the sender's own actor.
@rpc("any_peer", "call_remote", "reliable")
func _arena_request(action: String, args: Dictionary) -> void:
	if not _allow("world"):
		return
	var peer := _api.get_remote_sender_id()
	var arena := raid as Arena
	if not is_server or arena == null or not _peer_actor.has(peer) or action.length() > 32 or args.size() > 4:
		return
	var result := arena.request(_peer_actor[peer], action, args)
	if not result.ok and peer in _api.get_peers():
		_notice.rpc_id(peer, result.error)
	_board_dirty = true


## Race: a racer asks to race, signs up at a race control desk
## ("signup:<track>:<machine>"), tunes at a pit bench ("tune:<machine>"), asks for a restart or to stop their run. The server's own
## `Race.request` decides, for the sender's own actor.
@rpc("any_peer", "call_remote", "reliable")
func _race_request(action: String) -> void:
	if not _allow("world"):
		return
	var peer := _api.get_remote_sender_id()
	var race := raid as Race
	if not is_server or race == null or not _peer_actor.has(peer) or action.length() > 80 \
			or not (action in ["race", "restart", "retire"] or action.begins_with("signup:") \
					or action.begins_with("tune:")):
		return
	var result := race.request(_peer_actor[peer], action)
	if not result.ok and peer in _api.get_peers():
		_notice.rpc_id(peer, result.error)


## Race: a racer asks for the ghost they picked (`Race.GHOST_PICKS`) on a
## track and machine. Their own best and the board leader's are the race's
## to name; a friend's is the fastest among their saved contacts.
@rpc("any_peer", "call_remote", "reliable")
func _race_ghost_ask(pick: String, track_id: String, machine: String) -> void:
	if not _allow("social"):
		return
	var peer := _api.get_remote_sender_id()
	var race := raid as Race
	if not is_server or race == null or not _here(peer) or not _peer_actor.has(peer) or pick not in Race.GHOST_PICKS:
		return
	track_id = track_id.left(32)
	machine = machine.left(32)
	var owners := race.ghost_owners(pick, _peer_actor[peer], track_id, machine)
	var keys: Array = owners.keys
	if pick == "friend":
		keys = _friend_ids(_peer_account[peer])
	var answer: Dictionary = {"ok": false}
	if not keys.is_empty():
		answer = await stash.race_ghost(keys, track_id, str(owners.machine))
	if _here(peer):
		_race_ghost.rpc_id(peer, pick, track_id, machine, _ghost_out(answer))


## A ghost as a racer is sent it: no account id.
static func _ghost_out(answer: Dictionary) -> Dictionary:
	if not answer.get("ok", false):
		return {"ok": false}
	return {"ok": true, "name": str(answer.get("name", "?")), "machine": str(answer.get("machine", "")),
			"lap": float(answer.get("lap", -1.0)), "ghost": str(answer.get("ghost", ""))}


## The account ids a player keeps as friends: saved contacts they have not
## blocked (the phone's records).
func _friend_ids(account_id: String) -> Array:
	var phone: Dictionary = stash.social_snapshot(account_id) if stash.is_remote() else social.snapshot(account_id)
	var ids: Array = []
	for contact: Variant in phone.get("contacts", []):
		if contact is Dictionary and contact.get("saved", false) and not contact.get("blocked", false):
			ids.append(str(contact.get("id", "")))
	return ids


## A racer's new best lap goes straight back to them as their own ghost.
func _on_race_ghost_kept(actor: Actor, track_id: String, machine: String, ghost: RaceGhost) -> void:
	var peer := _owner_peer(actor)
	if peer in _api.get_peers():
		_race_ghost.rpc_id(peer, "mine", track_id, machine, {"ok": true, "name": actor.display_name,
				"machine": machine, "lap": ghost.lap_time, "ghost": ghost.to_packed()})


## Sends one racer their friends' best laps, for the pit boards.
func _send_friend_bests(peer: int) -> void:
	if not _here(peer):
		return
	var ids := _friend_ids(_peer_account[peer])
	var rows: Array = []
	if not ids.is_empty():
		rows = await stash.race_bests(ids)
	if _here(peer) and raid is Race:
		_race_friends.rpc_id(peer, rows)


## Someone kept a best lap: everyone's friends' times are sent again.
func _send_friend_bests_all() -> void:
	for peer: int in _peer_actor.keys():
		if peer in _joined_peers:
			_send_friend_bests(peer)


func _on_race_run_changed(actor: Actor) -> void:
	var peer: int = _actor_peer.get(actor, 0)
	if peer in _api.get_peers():
		_race_run.rpc_id(peer, (raid as Race).run_view(actor))


## A rival's line goes to the racer it was said to.
func _on_race_radio(actor: Actor, from: String, text: String) -> void:
	var peer: int = _actor_peer.get(actor, 0)
	if peer in _api.get_peers():
		_race_radio.rpc_id(peer, from, text)


## A race moved a racer's league standing: their account snapshot says so
## (an official server's link hears it from the service instead).
func _on_race_league_changed(actor: Actor) -> void:
	var peer: int = _actor_peer.get(actor, 0)
	if peer != 0 and not stash.is_remote():
		_send_account(peer)


## Every track's live race goes to everyone here: the boards show it.
func _send_race_heats() -> void:
	var race := raid as Race
	if race == null:
		return
	var rows := race.public_heats()
	for peer: int in _joined_peers:
		if peer in _api.get_peers():
			_race_heats.rpc_id(peer, rows)


func _send_race_board() -> void:
	var race := raid as Race
	if race == null:
		return
	var rows := race.public_board()
	for peer: int in _peer_actor:
		if peer in _joined_peers and peer in _api.get_peers():
			_race_board.rpc_id(peer, rows)


## Sends each player in the arena their own view of the board, when it
## changed and now and then anyway.
func _send_boards() -> void:
	var arena := raid as Arena
	if arena == null:
		return
	var due := _board_dirty or _tick % 15 == 0
	_board_dirty = false
	if not due:
		return
	for peer: int in _peer_actor:
		if peer not in _joined_peers:
			continue
		var b := arena.board_for(_peer_actor[peer])
		var text := JSON.stringify(b)
		var sent: Array = _board_sent.get(peer, ["", -BOARD_RESEND_TICKS])
		if text == sent[0] and _tick - int(sent[1]) < BOARD_RESEND_TICKS:
			continue
		_board_sent[peer] = [text, _tick]
		_arena_board.rpc_id(peer, b)


func _on_server_hit_confirmed(target: Actor, info: DamageInfo, lethal: bool, peer: int) -> void:
	if peer in _api.get_peers() and _ids.has(target):
		_hit_feedback.rpc_id(peer, _ids[target], info.amount, info.kind, lethal, info.blocked, info.parried,
				info.headshot, info.armored, info.armor_broke)


## In the world: start signing out, or call it off.
@rpc("any_peer", "call_remote", "reliable")
func _request_sign_out(start: bool) -> void:
	if not _allow("world"):
		return
	if not is_server or raid == null:
		return
	var actor: Actor = _peer_actor.get(_api.get_remote_sender_id())
	if actor == null or not is_instance_valid(actor):
		return
	if start:
		raid.begin_sign_out(actor)
	else:
		raid.cancel_sign_out(actor)


## In the world: give this life up where you stand (`Raid.abandon`).
@rpc("any_peer", "call_remote", "reliable")
func _request_abandon() -> void:
	if not _allow("world"):
		return
	if not is_server or raid == null:
		return
	var actor: Actor = _peer_actor.get(_api.get_remote_sender_id())
	if actor != null and is_instance_valid(actor):
		raid.abandon(actor)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _send_input(packet: PackedByteArray) -> void:
	if not _allow("input"):
		return
	if not is_server or packet.size() > MAX_INPUTS_PER_PACKET * INPUT_BYTES:
		return
	var peer := _api.get_remote_sender_id()
	if not _peer_actor.has(peer):
		return
	var inputs := unpack_inputs(packet)
	if inputs.is_empty():
		return
	if not _inputs.has(peer):
		_inputs[peer] = InputBuffer.new()
	(_inputs[peer] as InputBuffer).receive(inputs)


## Raise it when the bytes of a packed input change (`NetManifest`).
const WIRE_INPUTS := 2


## Inputs ([number, command array, view tick], see `ActorCommand.to_array`)
## as the bytes of one packet: `INPUT_BYTES` each, so sixteen fit in a
## datagram with room to spare.
static func pack_inputs(inputs: Array) -> PackedByteArray:
	var packet := PackedByteArray()
	packet.resize(inputs.size() * INPUT_BYTES)
	var at := 0
	for input: Array in inputs:
		var cmd: Array = input[1]
		packet.encode_u32(at, int(input[0]))
		packet.encode_u32(at + 4, int(input[2]))
		for i in ActorCommand.FLAGS_INDEX:
			packet.encode_float(at + 8 + i * 4, cmd[i])
		# The flags take 40 bits: the low 32, then the byte above them.
		var flags := int(cmd[ActorCommand.FLAGS_INDEX])
		packet.encode_u32(at + 36, flags & 0xFFFFFFFF)
		packet.encode_s8(at + 40, int(cmd[ActorCommand.STANCE_INDEX]))
		packet.encode_s8(at + 41, int(cmd[ActorCommand.SWITCH_INDEX]))
		packet.encode_u8(at + 42, (flags >> 32) & 0xFF)
		at += INPUT_BYTES
	return packet


## The inputs in a packet from `pack_inputs`, or none if it is not one.
static func unpack_inputs(packet: PackedByteArray) -> Array:
	var inputs: Array = []
	if packet.size() % INPUT_BYTES != 0:
		return inputs
	for at in range(0, packet.size(), INPUT_BYTES):
		var cmd: Array = []
		for i in ActorCommand.FLAGS_INDEX:
			cmd.append(packet.decode_float(at + 8 + i * 4))
		cmd.append(packet.decode_u32(at + 36) | (packet.decode_u8(at + 42) << 32))
		cmd.append(packet.decode_s8(at + 40))
		cmd.append(packet.decode_s8(at + 41))
		inputs.append([packet.decode_u32(at), cmd, packet.decode_u32(at + 4)])
	return inputs


func _server_early_tick() -> void:
	if raid == null:
		return
	for peer: int in _peer_actor:
		var actor: Actor = _peer_actor[peer]
		if not is_instance_valid(actor) or actor.is_dead:
			continue
		# With nothing new to play, held keys carry on and presses do not repeat.
		actor.cmd.clear_one_shots()
		var buffer: InputBuffer = _inputs.get(peer)
		if buffer == null:
			continue
		var input := buffer.next()
		if not input.is_empty():
			actor.cmd.apply_array(input[1])
			# Never later than now: a client cannot see the future.
			_seen_tick[actor] = mini(input[2], _tick)
		elif _seen_tick.has(actor):
			# A held trigger keeps firing at what the player is watching move on.
			_seen_tick[actor] = mini(int(_seen_tick[actor]) + 1, _tick)
		if buffer.live:
			_applied_seq[_ids[actor]] = buffer.played


## `Combat.rewind` on a server: where everyone else was on `attacker`'s screen
## when their current input was made.
func _seen_positions(attacker: Actor) -> Dictionary:
	if not _seen_tick.has(attacker):
		return {}
	var tick := maxi(int(_seen_tick[attacker]), _tick - MAX_REWIND_TICKS)
	if tick >= _tick:
		return {}
	return _past.get(tick, {})


func _server_late_tick(_delta: float) -> void:
	if raid == null:
		return
	for id: int in _actors:
		var actor: Actor = _actors[id]
		var pressed := actor.cmd.flags() & ActorCommand.ONE_SHOT_MASK
		for tier in DETAIL_EVERY.size():
			if pressed != 0:
				_one_shots[tier][id] = int(_one_shots[tier].get(id, 0)) | pressed
			if actor.cmd.switch_weapon != -1:
				_switches[tier][id] = actor.cmd.switch_weapon
	_tick += 1
	if _tick % BACKUP_CHECK_TICKS == 0:
		stash.backup_if_due()
	if lag_compensation:
		var now := {}
		for actor: Actor in _ids:
			if not actor.is_dead:
				now[actor] = actor.global_position
		_past[_tick] = now
		_past.erase(_tick - MAX_REWIND_TICKS - 1)
	if _tick % TICKS_PER_SNAPSHOT == 0 and not _joined_peers.is_empty():
		_send_states()
		if not _vehicles.is_empty():
			var rides: Array = []
			var snapshot := _tick / TICKS_PER_SNAPSHOT
			for id: int in _vehicles:
				var vehicle: Node3D = _vehicles[id]
				var rider: Actor = vehicle.get("rider")
				var rider_id: int = _ids.get(rider, -1) if rider != null else -1
				# Who sits on each passenger seat, in seat order (-1 for empty).
				var aboard: Array = []
				var anyone := rider_id >= 0
				for passenger in vehicle.get("passengers"):
					aboard.append(_ids.get(passenger, -1) if passenger != null else -1)
					anyone = anyone or passenger != null
				# A parked vehicle nobody rides is sent now and then, in turn
				# (at once when someone just got off it).
				var parked := not anyone and absf(float(vehicle.get("speed"))) < 0.05
				if parked and _vehicle_parked.get(id, false) and (snapshot + id) % PARKED_EVERY != 0:
					continue
				_vehicle_parked[id] = parked
				rides.append([id, vehicle.global_position, vehicle.get("heading"), vehicle.get("speed"),
						rider_id, _applied_seq.get(rider_id, 0), aboard, vehicle.get("slip")])
			for at in range(0, rides.size(), VEHICLES_PER_PACKET):
				var part := rides.slice(at, at + VEHICLES_PER_PACKET)
				for peer in _joined_peers:
					_vehicle_state.rpc_id(peer, part)
	_send_boards()
	for state in raid.players:
		var id: int = _ids.get(state.actor, -1)
		if id >= 0 and int(_sent_kills.get(id, 0)) != state.kills:
			_sent_kills[id] = state.kills
			for peer in _joined_peers:
				_kills.rpc_id(peer, id, state.kills)
		var actor := state.actor
		if not is_instance_valid(actor):
			continue
		var standing := [actor.renown, actor.rank, actor.streak, actor.bounty, actor.exposed, actor.marked,
				actor.scrip]
		if id >= 0 and _sent_standing.get(id, []) != standing:
			_sent_standing[id] = standing
			for peer in _joined_peers:
				_standing.rpc_id(peer, id, standing)
	# Everyone signed in hears where the other worlds are and how they are doing.
	if _tick % status_every == 0:
		_share_worlds()
	# The meter moves slowly, so a few times a second is plenty.
	if _tick % 20 == 0 and not is_equal_approx(_sent_war, raid.war.intensity):
		_sent_war = raid.war.intensity
		for peer in _joined_peers:
			_war.rpc_id(peer, raid.war.intensity, raid.war.centre)
	# The weather: a running storm a few times a second (a client carries the
	# cell on in between), and once more when it ends.
	if _tick % 20 == 0 and raid.world.weather_kind != "" \
			and (raid.weather.kind != "" or _sent_weather != ""):
		_sent_weather = raid.weather.kind
		var cell := raid.weather.pack()
		for peer in _joined_peers:
			_weather.rpc_id(peer, cell)
	# Body heat moves slowly too: its owner hears it a few times a second.
	if _tick % 15 == 0 and raid.world.cold > 0.0:
		for state in raid.players:
			if not is_instance_valid(state.actor):
				continue
			var peer := _owner_peer(state.actor)
			if peer == 0 or peer not in _joined_peers:
				continue
			var heat := [snappedf(state.actor.body_heat, 0.1), state.actor.warming]
			if _sent_heat.get(peer, []) != heat:
				_sent_heat[peer] = heat
				_body_heat.rpc_id(peer, heat[0], heat[1])
	# Grudges: a player hears which army is hunting them, and nothing more.
	if _tick % 30 == 0 and not raid.world.grudge_factions.is_empty():
		for state in raid.players:
			if not is_instance_valid(state.actor):
				continue
			var peer := _owner_peer(state.actor)
			if peer == 0 or peer not in _joined_peers:
				continue
			if str(_sent_hunted.get(peer, "")) != state.actor.hunted_by:
				_sent_hunted[peer] = state.actor.hunted_by
				_hunted.rpc_id(peer, state.actor.hunted_by)
	# Tracks: each player is sent the new marks near them, never the whole
	# world's, a few times a second.
	if _tick % TRACK_SEND_EVERY == 0 and raid.world.tracks:
		_send_tracks()
	# Strongpoints: each player hears who holds what, and which are theirs.
	if _tick % 10 == 0 and not raid.strongpoints.is_empty():
		for peer in _joined_peers:
			var viewer: Actor = _peer_actor.get(peer)
			var states := []
			for point in raid.strongpoints:
				states.append([point.holder_name, point.holder_is_player, point.taker_name,
						floori(point.progress * 100.0), point.contested,
						viewer != null and is_instance_valid(viewer) and raid.holds(viewer, point)])
			if _sent_points.get(peer, []) != states:
				_sent_points[peer] = states
				_strongpoints.rpc_id(peer, states)


## How closely a viewer at `eye` follows an actor at `at`: 0 near (every
## update), 1 in between, 2 far off.
static func detail_tier(eye: Vector3, at: Vector3) -> int:
	var apart := eye.distance_squared_to(at)
	if apart <= NEAR_RANGE * NEAR_RANGE:
		return 0
	return 1 if apart <= MID_RANGE * MID_RANGE else 2


## Whether actor `id` goes out to viewers of `tier` in update number `update`.
## Ids take turns, so the far-off actors do not all go out in one burst.
static func detail_due(update: int, id: int, tier: int) -> bool:
	return (update + id) % DETAIL_EVERY[tier] == 0


## Sends every player the state of the actors they are due to hear about:
## their own and those near them now, the rest in turn (see NEAR_RANGE).
func _send_states() -> void:
	var update := _tick / TICKS_PER_SNAPSHOT
	var ids: Array = _actors.keys()
	var places := {}
	for id: int in ids:
		places[id] = (_actors[id] as Actor).global_position
	var built: Array[Dictionary] = [{}, {}, {}]
	for peer in _joined_peers:
		var viewer: Actor = _peer_actor.get(peer)
		if viewer != null and is_instance_valid(viewer):
			_view_at[peer] = viewer.global_position
		var own: int = _ids.get(viewer, -1) if viewer != null else -1
		var eye: Vector3 = _view_at.get(peer, Vector3.ZERO)
		var chunk: Array = []
		for id: int in ids:
			var tier := 0 if id == own else detail_tier(eye, places[id])
			if not detail_due(update, id, tier):
				continue
			if not built[tier].has(id):
				built[tier][id] = _state_entry(id, tier)
			if id == own and _inputs.has(peer):
				# Your own entry also says which inputs have arrived, so you
				# stop repeating those. A guessed tick is played but has not
				# arrived: its input is still wanted, for its presses.
				var mine: Array = built[tier][id].duplicate()
				mine.append((_inputs[peer] as InputBuffer).newest)
				chunk.append(mine)
			else:
				chunk.append(built[tier][id])
			if chunk.size() == ACTORS_PER_PACKET:
				_state.rpc_id(peer, _tick, chunk)
				entries_sent += chunk.size()
				chunk = []
		if not chunk.is_empty():
			_state.rpc_id(peer, _tick, chunk)
			entries_sent += chunk.size()
	# Presses are kept for each tier until that tier has had its turn.
	_one_shots[0].clear()
	_switches[0].clear()
	for tier in range(1, DETAIL_EVERY.size()):
		for id: int in ids:
			if detail_due(update, id, tier):
				_one_shots[tier].erase(id)
				_switches[tier].erase(id)


## Raise it when what a state entry carries changes (`NetManifest`).
const WIRE_ACTOR_STATE := 1


## One actor's state as it goes out to viewers of `tier`, with the presses
## made since that tier last heard.
func _state_entry(id: int, tier: int) -> Array:
	var actor: Actor = _actors[id]
	var cmd := actor.cmd.to_array()
	cmd[ActorCommand.FLAGS_INDEX] = (int(cmd[ActorCommand.FLAGS_INDEX]) & ActorCommand.HELD_MASK) \
			| int(_one_shots[tier].get(id, 0)) | (ActorCommand.STATE_HOVERING if actor.flight.is_hovering else 0) \
			| (ActorCommand.STATE_SHELTERED if actor.weapons_locked else 0) \
			| (ActorCommand.STATE_SIGN_OUT_BEACON if actor.sign_out_beacon else 0) \
			| (ActorCommand.STATE_CHILLED if actor.shivering else 0) \
			| (ActorCommand.STATE_KNOCKED_DOWN if actor.knocked_left > 0.0 else 0)
	cmd[ActorCommand.SWITCH_INDEX] = _switches[tier].get(id, -1)
	return [id, actor.global_position, actor.velocity, cmd, actor.health.health,
			actor.health.armor, actor.stagger_left, _dead_kind.get(id, ""), _applied_seq.get(id, 0)]


# ---------------------------------------------------------------- client ----

## Connects to a server and signs in. `signed_in` or `failed` follows; then
## `deploy` enters the raid. The connection is encrypted; `ServerTrust` says
## how the server's certificate is checked, and the ways tried in turn.
func join(address: String, port := DEFAULT_PORT) -> Error:
	is_server = false
	_join_host = address
	_join_port = port
	_join_modes = ServerTrust.attempts_for(address)
	_api.auth_callback = _client_auth
	_api.auth_timeout = AUTH_TIMEOUT
	_api.peer_authenticating.connect(func(id: int) -> void:
		if id != 1:
			return
		_api.send_auth(1, var_to_bytes(_hello())))
	_api.peer_authentication_failed.connect(func(id: int) -> void:
		if id == 1:
			# Dropped without an answer: most likely a server from before
			# the sign-in moved into the handshake.
			_give_up("The server did not let you in. It may run an older version of the game; ask its host to update it."))
	_api.connection_failed.connect(_on_connection_failed)
	_api.server_disconnected.connect(_on_server_disconnected)
	return _open_connection()


## "host:port" as [host, port], or [] if it is not one.
static func split_address(address: String) -> Array:
	var at := address.rfind(":")
	if at <= 0:
		return []
	var port := address.substr(at + 1)
	if not port.is_valid_int() or int(port) <= 0 or int(port) > 65535:
		return []
	return [address.left(at), int(port)]


## Client: what this game says to sign in (see `_server_auth`).
func _hello() -> Dictionary:
	var hello := {"protocol": PROTOCOL, "manifest": NetManifest.own_digest(), "build": build}
	if ahead:
		hello["ahead"] = true
	if _join_mode == "probe":
		hello["probe"] = true
	elif _join_mode != "plain":
		# The secret and the token only ever go over an encrypted connection.
		hello["name"] = player_name
		if ticket != "":
			hello["token"] = ticket
		else:
			hello["secret"] = secret
	return hello


## Client: opens the next connection `join` tries (`_join_modes`).
func _open_connection() -> Error:
	_join_mode = _join_modes.pop_front()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(_join_host, _join_port)
	if err != OK:
		return err
	err = ServerTrust.setup_client(peer, _join_host, _join_mode)
	if err != OK:
		peer.close()
		return err
	peer.host.compress(COMPRESSION)
	_api.multiplayer_peer = peer
	return OK


## Client: a connection could not be made (or its handshake failed). The
## next way in `_join_modes` is tried; when none is left, the join fails.
func _on_connection_failed() -> void:
	if _gave_up:
		return
	if _join_modes.is_empty():
		_give_up("Could not reach the server.")
		return
	_api.multiplayer_peer = OfflineMultiplayerPeer.new()
	if _open_connection() != OK:
		_give_up("Could not reach the server.")


## Client: the server's answer to signing in (see `_server_auth`).
func _client_auth(id: int, data: PackedByteArray) -> void:
	if id != 1 or _gave_up:
		return
	var answer: Variant = bytes_to_var(data) if data.size() <= MAX_ANSWER_BYTES else null
	if typeof(answer) != TYPE_DICTIONARY:
		_give_up("That server is not a Verge server.")
		return
	var protocol := _protocol_in(answer)
	var certificate := str(answer.get("certificate", "")).left(MAX_AUTH_BYTES)
	if _join_mode == "probe" and protocol == PROTOCOL:
		# The remembered certificate failed: see which one it shows now.
		var was := ServerTrust.known(_join_host)
		refused = true
		if certificate == "" or certificate == was:
			_give_up("Could not make a secure connection to the server.")
			return
		identity_changed = {"host": _join_host, "was": ServerTrust.fingerprint(was),
				"now": ServerTrust.fingerprint(certificate), "certificate": certificate}
		_give_up("This server's identity changed since you last joined it. "
				+ "Check with its host before trusting it (Servers app).")
		return
	if _join_mode == "plain" and protocol == PROTOCOL:
		# Only a server from before encryption answers unencrypted.
		refused = true
		_give_up("Could not make a secure connection to the server.")
		return
	if protocol == PROTOCOL and not answer.get("ok", false) and answer.has("manifest"):
		# The same handshake, but what is said after it differs. The build
		# numbers say which side is older, where both builds carry one.
		refused = true
		var theirs := NetManifest.clean(answer.manifest)
		differs = NetManifest.differences(NetManifest.own(), theirs)
		var their_build: Variant = answer.get("build")
		outdated = {"mine": "client", "theirs": "server"}.get(
				NetManifest.older(build, int(their_build) if typeof(their_build) == TYPE_INT else 0), "either")
		print("The server speaks a different version (its build %s, this one %d). Differs in: %s" % [
				their_build, build, ", ".join(differs) if not differs.is_empty() else "nothing it named"])
		_give_up({"client": NEWER_SERVER, "server": OLDER_SERVER}.get(outdated,
				"This server runs a different version of the game. Both need the same build to play together."))
		return
	if protocol != PROTOCOL or str(answer.get("outdated", "")) != "":
		refused = true
		outdated = "client" if protocol > PROTOCOL else "server"
		_give_up(NEWER_SERVER if outdated == "client" else OLDER_SERVER)
		return
	if not answer.get("ok", false) and str(answer.get("again", "")) == "secret" and ticket != "":
		# The token ran out: sign in with the secret, on this same connection.
		ticket = ""
		_api.send_auth(1, var_to_bytes(_hello()))
		return
	if not answer.get("ok", false):
		refused = true
		_give_up(str(answer.get("error", "The server refused.")).left(200))
		return
	if answer.has("token"):
		ticket = str(answer.token).left(256)
	var p_world_id := str(answer.get("world", ""))
	if world_for(p_world_id) == null:
		refused = true
		_give_up("The server runs a world this game does not have: %s." % p_world_id.left(32))
		return
	world_id = p_world_id
	if _join_mode == "first":
		# Trust on first use: from now on this server must show the same one.
		ServerTrust.remember(_join_host, certificate)
	_api.complete_auth(1)


## Client: connecting, or connected, and not given up on.
func is_live() -> bool:
	return not is_server and not _gave_up and not _finished and _is_connected_or_connecting()


func _is_connected_or_connecting() -> bool:
	var peer := _api.multiplayer_peer if _api != null else null
	return peer != null and not peer is OfflineMultiplayerPeer \
			and peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED


## Client: this connection failed. Says why once, and closes it.
func _give_up(reason: String) -> void:
	if _gave_up:
		return
	_gave_up = true
	failed.emit(reason)
	close()


func _on_server_disconnected() -> void:
	if _finished:
		return
	if account.is_empty():
		_give_up("The server closed the connection.")
	else:
		# Signed in (in a lobby or out in a world): the game reconnects on
		# its own (`Main._on_online_disconnected`) unless `replaced`.
		_gave_up = true
		disconnected.emit()


## Client: back after a drop. `what` is `BACK_IN_BODY` when the server is
## putting you in the body you left standing, else how the life you were
## away from ended ("left" or "died"). Comes before the account.
@rpc("authority", "call_remote", "reliable")
func _back(what: String) -> void:
	if what == BACK_IN_BODY:
		resuming = true
	elif what in ["left", "died"]:
		missed_outcome = what


## Client: this connection is being let go because your account signed in
## from somewhere else.
@rpc("authority", "call_remote", "reliable")
func _replaced() -> void:
	replaced = true


## Client: back in your body after a drop, the weapons you held there as the
## server has them ([item id, rounds in the mag, rounds in reserve] each, the
## heavy weapon left out: the spawn carries it) and which is in hand. Your
## spawn only knows the kit you deployed with.
@rpc("authority", "call_remote", "reliable")
func _rearm(arms: Array, drawn: int) -> void:
	var me: Actor = _actors.get(my_actor_id)
	if me == null or not is_instance_valid(me) or arms.size() > 8:
		return
	for entry: Variant in arms:
		if typeof(entry) != TYPE_ARRAY or entry.size() != 3 or typeof(entry[0]) != TYPE_STRING:
			continue
		var id: String = entry[0]
		if not Loadout.summonable(id):
			continue
		var index := -1
		for i in me.weapons.size():
			if me.weapons[i].item_id == id:
				index = i
		if index < 0:
			Loadout.swap_weapon(me, id, int(entry[1]), int(entry[2]))
			me.materialize_left = 0.0
			continue
		var gun := me.weapons[index] as Gun
		if gun != null and int(entry[1]) >= 0:
			gun.ammo_in_mag = clampi(int(entry[1]), 0, gun.mag_size)
			gun.reserve_ammo = maxi(0, int(entry[2]))
	if drawn >= 0 and drawn < me.weapons.size():
		me.draw_weapon(drawn)


@rpc("authority", "call_remote", "reliable")
func _account(snapshot: Dictionary) -> void:
	var first := account.is_empty()
	account = snapshot
	if first:
		if not look.is_empty():
			_request_look.rpc_id(1, look)
		signed_in.emit(account)
	account_changed.emit(account)


@rpc("authority", "call_remote", "reliable")
func _routes(p_routes: Dictionary) -> void:
	routes.clear()
	for id: Variant in p_routes:
		var where: Variant = p_routes[id]
		if typeof(id) != TYPE_STRING or id.length() > 32:
			continue
		if typeof(where) == TYPE_INT and where > 0 and where < 65536:
			routes[id] = where
		elif typeof(where) == TYPE_STRING and where.length() <= 262 and not split_address(where).is_empty():
			routes[id] = where
	routes_changed.emit(routes)


@rpc("authority", "call_remote", "reliable")
func _world_status(p_status: Dictionary) -> void:
	world_status.clear()
	for id: Variant in p_status:
		var entry: Variant = p_status[id]
		if typeof(id) != TYPE_STRING or typeof(entry) != TYPE_DICTIONARY:
			continue
		world_status[id] = {"players": maxi(0, int(entry.get("players", 0))),
				"war": clampf(float(entry.get("war", 0.0)), 0.0, 1.0),
				"level": str(entry.get("level", "")).left(24),
				"bounty": maxi(0, int(entry.get("bounty", 0))),
				"event": str(entry.get("event", "")).left(40),
				"storm": str(entry.get("storm", "")).left(24),
				"wanted": _clean_wanted(entry.get("wanted", [])),
				"front": clean_front(entry.get("front", [])),
				"moments": clean_moments(entry.get("moments", [])),
				"hunted": clean_hunted(entry.get("hunted", [])),
				"race": clean_race(entry.get("race", {}))}
	world_status_changed.emit(world_status)


## A world's landmarks as the server sent them (`Raid.front`), checked: at
## most 16 of {name, x, z, holder, contested}.
static func clean_front(raw: Variant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if typeof(raw) != TYPE_ARRAY:
		return out
	for entry: Variant in raw:
		if out.size() >= 16:
			break
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		out.append({"name": str(entry.get("name", "")).left(24),
				"x": clampi(int(entry.get("x", 0)), -5000, 5000), "z": clampi(int(entry.get("z", 0)), -5000, 5000),
				"holder": str(entry.get("holder", "")).left(16),
				"contested": typeof(entry.get("contested")) == TYPE_BOOL and entry.contested})
	return out


## A world's big moments (`Raid.live_moments`), checked: at most
## `Raid.MOMENTS_KEPT` of {kind, text, at}.
static func clean_moments(raw: Variant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if typeof(raw) != TYPE_ARRAY:
		return out
	for entry: Variant in raw:
		if out.size() >= Raid.MOMENTS_KEPT:
			break
		if typeof(entry) != TYPE_DICTIONARY or str(entry.get("text", "")).strip_edges() == "":
			continue
		out.append({"kind": str(entry.get("kind", "")).left(16), "text": str(entry.text).strip_edges().left(80),
				"at": maxi(0, int(entry.get("at", 0)))})
	return out


## Who a world's armies hunt (`Raid.hunted`), checked: at most
## `Raid.HUNTED_SHOWN` of {name, clan, by}.
static func clean_hunted(raw: Variant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if typeof(raw) != TYPE_ARRAY:
		return out
	for entry: Variant in raw:
		if out.size() >= Raid.HUNTED_SHOWN:
			break
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var name := str(entry.get("name", "")).strip_edges().left(24)
		if name != "":
			out.append({"name": name, "clan": str(entry.get("clan", "")).left(6), "by": str(entry.get("by", "")).left(16)})
	return out


## A race world's feed (`Race.race_feed`), checked.
static func clean_race(raw: Variant) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY or str(raw.get("track", "")) == "":
		return {}
	var out := {"track": str(raw.track).left(24), "name": str(raw.get("name", "")).left(24)}
	if raw.has("phase"):
		out["phase"] = str(raw.phase).left(12)
		out["people"] = clampi(int(raw.get("people", 0)), 0, 64)
		return out
	out["laps"] = clampi(int(raw.get("laps", 1)), 1, 20)
	var racers: Array[Dictionary] = []
	var rows: Variant = raw.get("racers", [])
	if typeof(rows) == TYPE_ARRAY:
		for entry: Variant in rows:
			if racers.size() >= 12:
				break
			if typeof(entry) == TYPE_DICTIONARY:
				racers.append({"name": str(entry.get("name", "")).left(20), "lap": clampi(int(entry.get("lap", 1)), 1, 20),
						"at": clampf(float(entry.get("at", 0.0)), 0.0, 1.0), "place": clampi(int(entry.get("place", 0)), 0, 64)})
	out["racers"] = racers
	return out


## A world's most wanted as the server sent them (`Raid.wanted`), checked:
## at most `Raid.WANTED_SHOWN` entries of {name, clan, bounty, marked}.
static func _clean_wanted(raw: Variant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if typeof(raw) != TYPE_ARRAY:
		return out
	for entry: Variant in raw:
		if out.size() >= Raid.WANTED_SHOWN:
			break
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var name := str(entry.get("name", "")).strip_edges().left(24)
		if name == "":
			continue
		out.append({"name": name, "clan": str(entry.get("clan", "")).left(6),
				"bounty": maxi(0, int(entry.get("bounty", 0))), "marked": typeof(entry.get("marked")) == TYPE_BOOL and entry.marked})
	return out


@rpc("authority", "call_remote", "reliable")
func _clan(state: Dictionary) -> void:
	var mine: Variant = state.get("clan")
	var listed: Variant = state.get("clans")
	clan_state = {"clan": mine if typeof(mine) == TYPE_DICTIONARY else {},
			"clans": listed if typeof(listed) == TYPE_ARRAY else []}
	clan_changed.emit(clan_state)


## A player you can see joined or left a clan.
@rpc("authority", "call_remote", "reliable")
func _clan_tag(id: int, clan_id: String, tag: String) -> void:
	var actor: Actor = _actors.get(id)
	if actor != null and is_instance_valid(actor):
		actor.clan = clan_id.left(16)
		actor.clan_tag = ClanService.clean_tag(tag)


@rpc("authority", "call_remote", "reliable")
func _market(state: Dictionary) -> void:
	var listings: Array[Dictionary] = []
	for raw: Variant in state.get("listings", []):
		if typeof(raw) != TYPE_DICTIONARY or not ItemDB.has_item(str(raw.get("item", ""))):
			continue
		listings.append({"id": int(raw.get("id", 0)), "item": str(raw.item), "count": maxi(1, int(raw.get("count", 1))),
				"price": maxi(0, int(raw.get("price", 0))), "seller": str(raw.get("seller", "?")).left(24),
				"mine": bool(raw.get("mine", false)), "days_left": maxi(0, int(raw.get("days_left", 0)))})
	market_state = {"listings": listings, "trades_left": maxi(0, int(state.get("trades_left", 0))),
			"listed": maxi(0, int(state.get("listed", 0)))}
	market_changed.emit(market_state)


## The market kiosk: "view" (open the board), "close", "list" (`item_id`,
## `a` how many, `b` the price each), "buy" (`a` the listing, `b` how many) or
## "cancel" (`a` your listing). The answer comes back as a new
## `market_state` and account, or as a `lobby_error`.
func market_ask(action: String, item_id := "", a := 0, b := 0) -> void:
	if _is_connected() and not account.is_empty():
		_request_market.rpc_id(1, action, item_id, a, b)


## The clan hall: ask to found a clan ("create", name, tag), join one
## ("join", clan id) or leave yours ("leave"). The answer comes back as a new
## `clan_state`, or as a `lobby_error`.
func clan_ask(action: String, a := "", b := "") -> void:
	if _is_connected() and not account.is_empty():
		_request_clan.rpc_id(1, action, a, b)


@rpc("authority", "call_remote", "reliable")
func _lobby_error(reason: String) -> void:
	lobby_error.emit(reason)


## Lobby: ask the server to put a stash item in a slot ("" empties it).
func equip(slot: String, item_id: String) -> void:
	if _is_connected() and not account.is_empty():
		_request_equip.rpc_id(1, slot, item_id)


## Lobby: ask the server to pick a mastery variant ("" for stock).
func pick_mastery(track: String, variant_id: String) -> void:
	if _is_connected() and not account.is_empty():
		_request_pick.rpc_id(1, track, variant_id)


## Lobby: ask the server to buy one item from a hub shop.
func buy(shop_id: String, item_id: String) -> void:
	if _is_connected() and not account.is_empty():
		_request_buy.rpc_id(1, shop_id, item_id)


## Lobby: ask the server to buy a home base upgrade.
## Asks the server's contract board to "take" or "drop" a job, or "reroll".
func contract_ask(action: String, job_id: String = "") -> void:
	if _is_connected() and not account.is_empty():
		_request_contract.rpc_id(1, action, job_id)


func buy_upgrade(upgrade_id: String) -> void:
	if _is_connected() and not account.is_empty():
		_request_buy_upgrade.rpc_id(1, upgrade_id)


## Lobby: ask the server to change your home base's plan (see
## `_request_place_room`).
func place_room(socket: String, room: String) -> void:
	if _is_connected() and not account.is_empty():
		_request_place_room.rpc_id(1, socket, room)


## Lobby: ask the server to craft one item at the gunsmith bench.
func craft(item_id: String) -> void:
	if _is_connected() and not account.is_empty():
		_request_craft.rpc_id(1, item_id)


## Lobby: ask the server to "insure" a stash item or "cancel" the policy.
func insure(action: String, item_id: String = "") -> void:
	if _is_connected() and not account.is_empty():
		_request_insure.rpc_id(1, action, item_id)


## Lobby: ask the server to sell stash items ("" sells all loot).
func sell(item_id: String, count: int = 1) -> void:
	if _is_connected() and not account.is_empty():
		_request_sell.rpc_id(1, item_id, count)


## In the world: throw a toy vehicle off the watch, or pack up the vehicle
## being looked at. The server reads the aim from the actor it simulates.
@rpc("any_peer", "call_remote", "reliable")
func _request_toy(item_id: String) -> void:
	if not _allow("world"):
		return
	if not is_server or raid == null:
		return
	var actor: Actor = _peer_actor.get(_api.get_remote_sender_id())
	if actor == null or not is_instance_valid(actor):
		return
	if item_id == "":
		raid.pack_vehicle(actor)
	else:
		raid.throw_toy(actor, item_id)


## In the world: take a toy off the watch into the hand to throw, or put it
## back (""). Only the look, so everyone sees what is in the hand.
@rpc("any_peer", "call_remote", "reliable")
func _request_toy_hold(item_id: String) -> void:
	if not _allow("world"):
		return
	if not is_server or raid == null:
		return
	var actor: Actor = _peer_actor.get(_api.get_remote_sender_id())
	if actor != null and is_instance_valid(actor):
		raid.hold_toy(actor, item_id)


## Server: the toy in someone's hand changed, or they started a throw. Tells
## everyone else here; the thrower's own game shows its own hand at once.
func _on_server_toy_hand(actor: Actor) -> void:
	if not _ids.has(actor):
		return
	for peer in _joined_peers:
		if _peer_actor.get(peer) != actor and peer in _api.get_peers():
			_toy_hand.rpc_id(peer, _ids[actor], actor.toy_in_hand, actor.toy_throws)


## Client: what someone else has in their hand, and how many throws they
## have started (a new one plays the throw).
@rpc("authority", "call_remote", "reliable")
func _toy_hand(id: int, item_id: String, throws: int) -> void:
	var actor: Actor = _actors.get(id)
	if actor == null or not is_instance_valid(actor) or id == my_actor_id:
		return
	actor.toy_in_hand = item_id if item_id == "" or ItemDB.has_tag(item_id, "vehicle") else ""
	actor.toy_throws = throws


## In the world: materialize a weapon out of the pack (the watch's summon).
## The server checks the pack it keeps, never anything the client says it has.
@rpc("any_peer", "call_remote", "reliable")
func _request_summon(item_id: String) -> void:
	if not _allow("world"):
		return
	if not is_server or raid == null:
		return
	var actor: Actor = _peer_actor.get(_api.get_remote_sender_id())
	if actor != null and is_instance_valid(actor):
		raid.summon(actor, item_id)


## In the world: store the weapon in hand back into the pack (the watch's
## store). The server checks the hand of the actor it simulates.
@rpc("any_peer", "call_remote", "reliable")
func _request_store(item_id: String) -> void:
	if not _allow("world"):
		return
	if not is_server or raid == null:
		return
	var actor: Actor = _peer_actor.get(_api.get_remote_sender_id())
	if actor != null and is_instance_valid(actor):
		raid.store(actor, item_id)


## In the world: drop an item out of the pack where you stand (the pack
## list's drop). The server checks the pack it keeps (`Raid.drop_item`).
@rpc("any_peer", "call_remote", "reliable")
func _request_drop(item_id: String) -> void:
	if not _allow("world"):
		return
	if not is_server or raid == null:
		return
	var actor: Actor = _peer_actor.get(_api.get_remote_sender_id())
	if actor != null and is_instance_valid(actor):
		raid.drop_item(actor, item_id)


## In the world: ping the spot being looked at for your side. The server
## reads the aim from the actor it simulates.
@rpc("any_peer", "call_remote", "reliable")
func _request_ping() -> void:
	if not _allow("world"):
		return
	if not is_server or raid == null:
		return
	var actor: Actor = _peer_actor.get(_api.get_remote_sender_id())
	if actor != null and is_instance_valid(actor):
		raid.ping(actor)


## A player pinged a spot: they and their side are told, nobody else.
func _on_server_pinged(pinger: Actor, at: Vector3) -> void:
	if not _ids.has(pinger):
		return
	for peer in _joined_peers:
		var viewer: Actor = _peer_actor.get(peer)
		if viewer == null or not is_instance_valid(viewer):
			continue
		if viewer == pinger or Visor.allied(pinger, viewer):
			_ping.rpc_id(peer, _ids[pinger], at)


## In a safe zone: ask the server to open a squad portal to `destination`
## in front of you (the watch's portal icon).
func open_portal(destination: String) -> void:
	if _is_connected() and my_actor_id >= 0 and not _can_redeploy and destination != "":
		_request_portal.rpc_id(1, destination)


@rpc("any_peer", "call_remote", "reliable")
func _request_portal(destination: String) -> void:
	if not _allow("world"):
		return
	if not is_server or raid == null:
		return
	var peer := _api.get_remote_sender_id()
	var actor: Actor = _peer_actor.get(peer)
	if actor == null or not is_instance_valid(actor):
		return
	var why := raid.open_portal(actor, destination.left(32))
	if why != "" and why != "not now":
		_notice.rpc_id(peer, why)


## Server: shows `peer` a portal, saying whether their side may use it. The
## opener's side key never leaves the server.
func _send_portal(peer: int, portal: Portal) -> void:
	if not is_instance_valid(portal):
		return
	var viewer: Actor = _peer_actor.get(peer)
	var usable: bool = portal.side == "" or (viewer != null and is_instance_valid(viewer)
			and raid.squad_of(viewer) == portal.side)
	_portal.rpc_id(peer, portal.get_instance_id(), portal.destination, portal.global_transform, usable,
			portal.age, portal.opener_name, portal.unfold_time if portal.signs_out else -1.0)


## Client: a squad portal is open here (or, sent again, in step again).
@rpc("authority", "call_remote", "reliable")
func _portal(key: int, destination: String, at: Transform3D, usable: bool, age: float, opener_name: String,
		unfold: float) -> void:
	if raid == null or not Portal.is_place(destination) or not at.origin.is_finite() \
			or not is_finite(age) or not is_finite(unfold):
		return
	for old in raid.portals.duplicate():
		if old.get_meta("net_key", -1) == key:
			raid.close_portal(old)
	var shown := raid.show_portal(destination, at, usable, age, opener_name.left(32), minf(unfold, 120.0))
	shown.set_meta("net_key", key)


## Client: a squad portal closed.
@rpc("authority", "call_remote", "reliable")
func _portal_closed(key: int) -> void:
	if raid == null:
		return
	for portal in raid.portals.duplicate():
		if portal.get_meta("net_key", -1) == key:
			raid.close_portal(portal)


## Client: you walked through a portal your side may use.
@rpc("authority", "call_remote", "reliable")
func _portal_travel(destination: String) -> void:
	if Portal.is_place(destination):
		portal_travel.emit(destination)


## Drop into the server's world: from the lobby, or again after a death.
## `joined` follows, or `lobby_error`. `drop` is where to land, an id from
## `Raid.drop_choices`; the server decides whether it is still on offer.
func deploy(drop := "") -> void:
	if _is_connected() and not account.is_empty() and (my_actor_id < 0 or _can_redeploy):
		_request_join.rpc_id(1, drop)


## In the world: ask the server to throw a toy vehicle off your watch. Your
## own hand starts the throw at once; the server lets the toy fly after the
## same windup (`Raid.toy_windup`).
func throw_toy(item_id: String) -> void:
	if _is_connected() and my_actor_id >= 0 and not _can_redeploy and item_id != "":
		_request_toy.rpc_id(1, item_id)
		var me := raid.player if raid != null else null
		if me != null and is_instance_valid(me) and item_id in raid.stowed_for(me) and raid.toy_wait(me) <= 0.0:
			me.toy_in_hand = item_id
			me.toy_throws += 1


## In the world: take a toy off your watch into your hand, or put it back
## (""). Your own hand shows it at once; the server tells everyone else.
func hold_toy(item_id: String) -> void:
	if _is_connected() and my_actor_id >= 0 and not _can_redeploy:
		_request_toy_hold.rpc_id(1, item_id)
		if raid != null and raid.player != null and is_instance_valid(raid.player):
			raid.player.toy_in_hand = item_id


## In the world: ask the server to pack the vehicle you are looking at.
func pack_vehicle() -> void:
	if _is_connected() and my_actor_id >= 0 and not _can_redeploy:
		_request_toy.rpc_id(1, "")


## In the world: ask the server to materialize a weapon out of your pack.
func summon(item_id: String) -> void:
	if _is_connected() and my_actor_id >= 0 and not _can_redeploy and item_id != "":
		_request_summon.rpc_id(1, item_id)


## In the world: ask the server to store the weapon in your hand.
func store(item_id: String) -> void:
	if _is_connected() and my_actor_id >= 0 and not _can_redeploy and item_id != "":
		_request_store.rpc_id(1, item_id)


## In the world: ask the server to drop an item out of your pack.
func drop(item_id: String) -> void:
	if _is_connected() and my_actor_id >= 0 and not _can_redeploy and item_id != "":
		_request_drop.rpc_id(1, item_id)


## In the world: ask the server to ping where you are looking for your side.
func ping() -> void:
	if _is_connected() and my_actor_id >= 0 and not _can_redeploy:
		_request_ping.rpc_id(1)


## In the world: ask the server to start your sign-out, or to call it off.
func sign_out(start := true) -> void:
	if _is_connected() and my_actor_id >= 0 and not _can_redeploy:
		_request_sign_out.rpc_id(1, start)


## Asks the server to end this life where it stands (the watch's Abandon).
func abandon() -> void:
	if _is_connected() and my_actor_id >= 0 and not _can_redeploy:
		_request_abandon.rpc_id(1)


@rpc("authority", "call_remote", "reliable")
func _welcome(actor_id: int) -> void:
	if raid != null:
		# Dropping back in: the world is already here. Only your actor is new.
		_can_redeploy = false
		var corpse: Actor = raid.player
		if corpse != null and is_instance_valid(corpse):
			var state := raid.state_for(corpse)
			if state != null:
				raid.players.erase(state)
			_actors.erase(_ids.get(corpse, -1))
			_ids.erase(corpse)
			corpse.queue_free()
		raid.player = null
		_history.clear()
		_corrections.erase(my_actor_id)
		_latest.erase(my_actor_id)
		_trails.erase(actor_id)
		my_actor_id = actor_id
		return
	_clear_tables()
	my_actor_id = actor_id
	Combat.authoritative = false
	var world := world_for(world_id)
	raid = world.new_raid()
	raid.name = "Raid"
	add_child(raid)
	raid.start_client(world)
	if raid is Arena:
		raid.send_request = arena_request
	elif raid is Race:
		raid.send_request = race_request
		raid.send_ghost_ask = race_ghost_ask


## Client: someone's power weapon slot changed (taken off a rack, swapped,
## or spent). The server decided it; this only makes the copy here match.
@rpc("authority", "call_remote", "reliable")
func _power_changed(id: int, item_id: String, mag: int, reserve: int) -> void:
	var actor: Actor = _actors.get(id)
	if actor == null or not is_instance_valid(actor) or (item_id != "" and not ItemDB.has_tag(item_id, "power")):
		return
	Loadout.set_power(actor, item_id, mag, reserve, false)


## Client: someone put on a helmet, armor frame, flight rig or ability chip
## (`kind` "helmet", "armor", "flight_rig" or "ability"), or took one off.
## The server decided it; armor left follows in the state.
@rpc("authority", "call_remote", "reliable")
func _worn_changed(id: int, kind: String, item_id: String) -> void:
	var actor: Actor = _actors.get(id)
	if actor == null or not is_instance_valid(actor) or kind not in ["helmet", "armor", "flight_rig", "ability"] \
			or (item_id != "" and not ItemDB.has_tag(item_id, kind)):
		return
	if kind == "helmet":
		Loadout.wear_helmet(actor, item_id)
	elif kind == "flight_rig":
		if item_id != (actor.flight.item_id if actor.flight.enabled else ""):
			Loadout.wear_rig(actor, item_id)
	elif kind == "ability":
		if item_id != (actor.ability.item_id if actor.ability.enabled else ""):
			Loadout.wear_ability(actor, item_id)
	elif item_id != actor.frame_id:
		Loadout.wear_frame(actor, item_id)


## Client: what someone carries now weighs `kg` (`CarryLoad`). The server
## worked it out from their gear and pack; the body here moves by it, so its
## prediction matches the server's.
@rpc("authority", "call_remote", "reliable")
func _carry(id: int, kg: float) -> void:
	var actor: Actor = _actors.get(id)
	if actor != null and is_instance_valid(actor) and kg >= 0.0 and kg < 10000.0:
		actor.carry_sent = kg
		actor.mark_carry()


## Client: someone materialized a weapon out of their pack in place of the
## one they wore (the watch's summon). The server decided it and keeps the
## packs; this only makes the weapons here match.
@rpc("authority", "call_remote", "reliable")
func _weapon_swapped(id: int, item_id: String, mag: int, reserve: int) -> void:
	var actor: Actor = _actors.get(id)
	if actor != null and is_instance_valid(actor) and Loadout.summonable(item_id):
		Loadout.swap_weapon(actor, item_id, mag, reserve)


## Client: someone stored the weapon they held back into their pack (the
## watch's store). The server decided it and keeps the packs; this only
## starts the same dematerialize here.
@rpc("authority", "call_remote", "reliable")
func _weapon_stored(id: int, item_id: String) -> void:
	var actor: Actor = _actors.get(id)
	if actor != null and is_instance_valid(actor) and Loadout.summonable(item_id):
		Loadout.store_weapon(actor, item_id)


## Client: someone on your side (or you) pinged a spot.
@rpc("authority", "call_remote", "reliable")
func _ping(id: int, at: Vector3) -> void:
	var actor: Actor = _actors.get(id)
	if raid != null and actor != null and is_instance_valid(actor) and at.is_finite():
		raid.pinged.emit(actor, at)


@rpc("authority", "call_remote", "reliable")
func _spawn(id: int, kind: String, shown_name: String, node_name: String, at: Vector3, yaw: float,
		data: Dictionary) -> void:
	if raid == null or _actors.has(id):
		return
	var actor: Actor
	if kind == "player":
		actor = Actor.new()
		actor.name = node_name
		actor.display_name = shown_name
		actor.is_player = id == my_actor_id
		if data.has("look"):
			Look.set_appearance(actor, data["look"])
		var worn: Variant = data.get("clan")
		if typeof(worn) == TYPE_ARRAY and worn.size() == 2:
			actor.clan = str(worn[0]).left(16)
			actor.clan_tag = ClanService.clean_tag(str(worn[1]))
		raid.add_child(actor)
		actor.global_position = at
		Loadout.equip(actor, data.get("kit", []))
		Loadout.arrive_unarmed(actor)
		var power: Variant = data.get("power")
		if power is Array and power.size() == 3 and ItemDB.has_tag(str(power[0]), "power"):
			Loadout.set_power(actor, power[0], int(power[1]), int(power[2]), false)
		actor.weapons_locked = raid.world.safe_zone or not raid.world.weapons_free
		Raid.MasteryTracker.apply_variants(actor, data.get("picks", {}))
		raid.world.on_spawn(actor)
		# Listed as a player, so the HUD and scoreboard can tell them from bots.
		var state := Raid.PlayerState.new()
		state.actor = actor
		state.kit.assign(data.get("kit", []))
		state.picks = data.get("picks", {})
		raid.players.append(state)
	else:
		var kit: Array = []
		if data.get("kit") is Array:
			kit = (data["kit"] as Array).filter(func(id: Variant) -> bool: return ItemDB.has_item(str(id)))
		actor = raid.spawn_bot(node_name, at, data.get("seed", 0), data.get("warlord", false),
				data.get("faction", ""), clampi(int(data.get("zone", -1)), -1, 2), kit,
				str(data.get("boss", "")).left(32))
		if not kit.is_empty():
			actor.display_name = shown_name
			if data.has("look"):
				Look.set_appearance(actor, data["look"])
		raid.world.on_spawn(actor)
	actor.cmd.yaw = yaw
	_actors[id] = actor
	_ids[actor] = id
	if id == my_actor_id:
		raid.player = actor
		joined.emit(raid)


@rpc("authority", "call_remote", "reliable")
func _despawn(id: int) -> void:
	var actor: Actor = _actors.get(id)
	_actors.erase(id)
	_latest.erase(id)
	_trails.erase(id)
	if actor == null or not is_instance_valid(actor):
		return
	_ids.erase(actor)
	if raid != null:
		raid.bots.erase(actor)
		var state := raid.state_for(actor)
		if state != null and id != my_actor_id:
			raid.players.erase(state)
	if id != my_actor_id:
		actor.queue_free()


@rpc("authority", "call_remote", "reliable")
func _kills(id: int, count: int) -> void:
	var actor: Actor = _actors.get(id)
	if raid == null or actor == null or not is_instance_valid(actor):
		return
	var state := raid.state_for(actor)
	if state != null:
		state.kills = count
	if id == my_actor_id:
		raid.kills = count


@rpc("authority", "call_remote", "unreliable_ordered")
func _state(tick: int, entries: Array) -> void:
	_after_lag(_receive_state.bind(tick, entries))


## Runs `update` now, or after the simulated lag.
func _after_lag(update: Callable) -> void:
	if simulated_lag > 0.0 or simulated_jitter > 0.0:
		var due := Time.get_ticks_msec() + (simulated_lag + randf() * simulated_jitter) * 1000.0
		# Updates stay in the order they were sent, as on the wire.
		if not _delayed_in.is_empty():
			due = maxf(due, _delayed_in[-1][0])
		_delayed_in.append([due, update])
	else:
		update.call()


func _receive_state(tick: int, entries: Array) -> void:
	if raid == null:
		return
	if tick > _newest_tick:
		_newest_tick = tick
		_fresh_state = true
	for entry: Array in entries:
		var id: int = entry[0]
		entries_received[id] = int(entries_received.get(id, 0)) + 1
		# The server has your inputs up to here: stop resending those.
		if id == my_actor_id and entry.size() > 9:
			_acked_seq = maxi(_acked_seq, int(entry[9]))
		# Presses from an update we have not applied yet must not be lost.
		if _latest.has(id):
			var cmd: Array = entry[3]
			var earlier: Array = _latest[id][3]
			cmd[ActorCommand.FLAGS_INDEX] = int(cmd[ActorCommand.FLAGS_INDEX]) \
					| (int(earlier[ActorCommand.FLAGS_INDEX]) & ActorCommand.ONE_SHOT_MASK)
			if int(cmd[ActorCommand.SWITCH_INDEX]) < 0:
				cmd[ActorCommand.SWITCH_INDEX] = earlier[ActorCommand.SWITCH_INDEX]
		_latest[id] = entry
		_latest_tick[id] = tick


@rpc("authority", "call_remote", "reliable")
func _container(id: int, items: Array, is_bag: bool, label: String, at: Vector3, pile_scrip: int,
		pile_bounty: int) -> void:
	if raid == null or _containers.has(id):
		return
	# A scrip pile (`pile_scrip` 0 or more) comes with its scrip and bounty.
	_containers[id] = raid.spawn_container(items, is_bag, label, at, pile_scrip, pile_bounty)


@rpc("authority", "call_remote", "reliable")
func _container_items(id: int, items: Array, scrip: int) -> void:
	var container: LootContainer = _containers.get(id)
	if container != null and is_instance_valid(container):
		container.set_items(items, scrip if container.pile else -1)


@rpc("authority", "call_remote", "reliable")
func _container_gone(id: int) -> void:
	var container: LootContainer = _containers.get(id)
	_containers.erase(id)
	if container != null and is_instance_valid(container):
		container.queue_free()


@rpc("authority", "call_remote", "reliable")
func _inventory(items: Array) -> void:
	var me: Actor = _actors.get(my_actor_id)
	if me != null and is_instance_valid(me):
		me.inventory.items.assign(items)
		me.inventory.changed.emit()


@rpc("authority", "call_remote", "reliable")
func _vehicle(id: int, item_id: String, at: Vector3, heading: float, unpacking: bool) -> void:
	if raid == null or _vehicles.has(id) or not ItemDB.has_item(item_id):
		return
	var vehicle := raid.spawn_vehicle(item_id, at, heading, unpacking)
	# The server drives it. Here it only follows the reported position.
	vehicle.set_physics_process(false)
	_vehicles[id] = vehicle


@rpc("authority", "call_remote", "reliable")
func _vehicle_gone(id: int) -> void:
	var vehicle: Node3D = _vehicles.get(id)
	_vehicles.erase(id)
	_vehicle_targets.erase(id)
	if vehicle == null or not is_instance_valid(vehicle):
		return
	vehicle.call("dismount_all")
	if raid != null:
		raid.vehicles.erase(vehicle)
	vehicle.queue_free()


## Raise it when what a vehicle's entry carries changes (`NetManifest`).
const WIRE_VEHICLE_STATE := 1


@rpc("authority", "call_remote", "unreliable_ordered")
func _vehicle_state(entries: Array) -> void:
	_after_lag(func() -> void:
		for entry: Array in entries:
			_vehicle_targets[entry[0]] = entry)


## Moves each vehicle toward where the server says it is, and keeps its rider
## the same as the server's. The one you ride drives itself from your input
## here, and is only corrected (`_correct_ride`).
func _client_move_vehicles() -> void:
	for id: int in _vehicles:
		var vehicle: Node3D = _vehicles[id]
		if not is_instance_valid(vehicle):
			continue
		var me: Actor = _actors.get(my_actor_id)
		var mine: bool = me != null and vehicle.get("rider") == me
		vehicle.set_physics_process(mine)
		if mine:
			_blend_ride(vehicle)
		if not _vehicle_targets.has(id):
			continue
		var entry: Array = _vehicle_targets[id]
		if mine and int(entry[4]) == my_actor_id:
			# Each answer is compared once. The ride drives itself in between.
			if not is_same(entry, _ride_entry):
				_ride_entry = entry
				_correct_ride(vehicle, entry)
				# Who sits behind is the server's call, like the rider.
				_passengers_from_state(vehicle, entry[6])
			continue
		var at: Vector3 = entry[1]
		if vehicle.global_position.distance_to(at) > SNAP_DISTANCE:
			vehicle.global_position = at
		else:
			vehicle.global_position = vehicle.global_position.lerp(at, 0.35)
		var heading := lerp_angle(vehicle.get("heading"), entry[2], 0.35)
		vehicle.set("heading", heading)
		vehicle.rotation = Vector3(0.0, heading, 0.0)
		vehicle.set("speed", entry[3])
		vehicle.set("slip", entry[7])
		if _seat_from_state(vehicle, "rider", int(entry[4]), false):
			_ride_history.clear()
			_ride_fix = Vector3.ZERO
			_ride_turn = 0.0
		_passengers_from_state(vehicle, entry[6])
		vehicle.call("_place_rider")


## Puts whoever the server says is on `seat` ("rider" or "passenger") there.
## True if that changed who sits there.
func _seat_from_state(vehicle: Node3D, seat: String, actor_id: int, behind: bool) -> bool:
	var want: Actor = _actors.get(actor_id) if actor_id >= 0 else null
	if want != null and not is_instance_valid(want):
		want = null
	var current: Actor = vehicle.get(seat)
	if current == want:
		return false
	if current != null:
		vehicle.call("get_off", current)
	if want != null:
		if want.vehicle != null:
			want.vehicle.call("get_off", want)
		vehicle.call("mount", want, behind)
	return true


## Puts whoever the server says is on each passenger seat there (`ids`, in
## seat order, -1 for an empty seat).
func _passengers_from_state(vehicle: Node3D, ids: Array) -> void:
	var seated: Array = vehicle.get("passengers")
	for i in mini(ids.size(), seated.size()):
		var want: Actor = _actors.get(int(ids[i])) if int(ids[i]) >= 0 else null
		if want != null and not is_instance_valid(want):
			want = null
		var current = seated[i]
		if current == want:
			continue
		if current != null and is_instance_valid(current):
			vehicle.call("get_off", current)
		seated[i] = null
		if want != null:
			if want.vehicle != null:
				want.vehicle.call("get_off", want)
			vehicle.call("mount", want, true, i)


## Compares the server's position for your ride with where this game predicted
## it after the same input, like `_apply_state` does for your own actor.
func _correct_ride(vehicle: Node3D, entry: Array) -> void:
	var seq: int = entry[5]
	if not _ride_history.has(seq):
		# Just got on: nothing predicted to compare with yet.
		if vehicle.global_position.distance_to(entry[1]) > SNAP_DISTANCE:
			_snap_ride(vehicle, entry)
		return
	var then: Array = _ride_history[seq]
	var miss: Vector3 = entry[1] - then[0]
	max_correction = maxf(max_correction, miss.length())
	if miss.length() > SNAP_DISTANCE:
		_snap_ride(vehicle, entry)
		return
	_ride_fix = miss
	_ride_turn = angle_difference(then[1], entry[2])
	# Speed carries straight into the future, so it is fixed at once, and in
	# the remembered rides too so the next answer only sees what is still wrong.
	var speed_miss := float(entry[3]) - float(then[2])
	vehicle.set("speed", float(vehicle.get("speed")) + speed_miss)
	# A hover's drift carries on the same way.
	var slip_miss := float(entry[7]) - float(then[3])
	vehicle.set("slip", float(vehicle.get("slip")) + slip_miss)
	for later: int in _ride_history:
		_ride_history[later][2] += speed_miss
		_ride_history[later][3] += slip_miss


func _snap_ride(vehicle: Node3D, entry: Array) -> void:
	vehicle.global_position = entry[1]
	vehicle.set("heading", entry[2])
	vehicle.rotation = Vector3(0.0, entry[2], 0.0)
	vehicle.set("speed", entry[3])
	vehicle.set("slip", entry[7])
	_ride_history.clear()
	_ride_fix = Vector3.ZERO
	_ride_turn = 0.0


func _blend_ride(vehicle: Node3D) -> void:
	if _ride_fix == Vector3.ZERO and _ride_turn == 0.0:
		return
	var step := _ride_fix * CORRECTION_RATE if _ride_fix.length() > 0.02 else _ride_fix
	var turn := _ride_turn * CORRECTION_RATE if absf(_ride_turn) > 0.002 else _ride_turn
	vehicle.global_position += step
	vehicle.set("heading", float(vehicle.get("heading")) + turn)
	vehicle.rotation = Vector3(0.0, vehicle.get("heading"), 0.0)
	for seq: int in _ride_history:
		_ride_history[seq][0] += step
		_ride_history[seq][1] += turn
	_ride_fix -= step
	_ride_turn -= turn


@rpc("authority", "call_remote", "reliable")
func _hit_feedback(target_id: int, amount: float, kind: String, lethal: bool, blocked: bool,
		parried: bool, headshot: bool, armored: bool, armor_broke: bool) -> void:
	var me: Actor = _actors.get(my_actor_id)
	var target: Actor = _actors.get(target_id)
	if me == null or target == null or not is_instance_valid(target):
		return
	var info := DamageInfo.make(amount, me, kind, target.global_position)
	info.blocked = blocked
	info.parried = parried
	info.headshot = headshot
	info.armored = armored
	info.armor_broke = armor_broke
	me.hit_confirmed.emit(target, info, lethal)


@rpc("authority", "call_remote", "reliable")
func _hurt(amount: float, kind: String) -> void:
	var me: Actor = _actors.get(my_actor_id)
	if me != null and not me.is_dead:
		me.health.damaged.emit(DamageInfo.make(amount, null, kind))


## Every strongpoint, in map order: [holder name, holder is a player,
## taker name, progress percent, contested, yours].
@rpc("authority", "call_remote", "reliable")
func _strongpoints(states: Array) -> void:
	if raid == null:
		return
	for i in mini(states.size(), raid.strongpoints.size()):
		var state: Array = states[i]
		if state.size() < 6:
			continue
		var point := raid.strongpoints[i]
		point.holder_name = str(state[0])
		point.holder = "held" if point.holder_name != "" else ""
		point.holder_is_player = bool(state[1])
		point.taker_name = str(state[2])
		point.taker = "taking" if point.taker_name != "" else ""
		point.progress = clampf(float(state[3]) / 100.0, 0.0, 1.0)
		point.contested = bool(state[4])
		point.viewer_holds = bool(state[5])
		point.refresh_look()


## How hot the war is and where, for the sky and the HUD.
@rpc("authority", "call_remote", "unreliable_ordered")
func _war(intensity: float, centre: Vector3) -> void:
	if raid != null:
		raid.war.intensity = clampf(intensity, 0.0, 1.0)
		raid.war.centre = centre


## The storm crossing the map (`Weather.pack`), for the sky, the visor and
## the gusts a client predicts.
@rpc("authority", "call_remote", "unreliable_ordered")
func _weather(cell: Array) -> void:
	if raid != null and cell.size() == 7 and typeof(cell[0]) == TYPE_STRING:
		raid.weather.unpack(cell)


## A player's public standing: [renown, rank, streak, bounty, exposed, marked,
## scrip carried].
@rpc("authority", "call_remote", "reliable")
func _standing(id: int, standing: Array) -> void:
	var actor: Actor = _actors.get(id)
	if actor == null or not is_instance_valid(actor) or standing.size() < 6:
		return
	actor.renown = int(standing[0])
	actor.rank = int(standing[1])
	actor.streak = int(standing[2])
	actor.bounty = int(standing[3])
	actor.exposed = bool(standing[4])
	actor.marked = bool(standing[5])
	if standing.size() > 6:
		actor.scrip = int(standing[6])


## A player tagged someone: they and their side are told, nobody else.
func _on_server_tagged(target: Actor, tagger: Actor) -> void:
	if not _ids.has(target) or not _ids.has(tagger):
		return
	for peer in _joined_peers:
		var viewer: Actor = _peer_actor.get(peer)
		if viewer == null or not is_instance_valid(viewer):
			continue
		if viewer == tagger or Visor.allied(tagger, viewer):
			_visor_tag.rpc_id(peer, _ids[tagger], _ids[target], float(tagger.visor.tags.get(target, 0.0)))


## The answer to your scan: where everyone it caught was standing.
@rpc("authority", "call_remote", "reliable")
func _visor_ghosts(found: Array) -> void:
	var me: Actor = _actors.get(my_actor_id)
	if me != null and is_instance_valid(me):
		me.visor.show_ghosts(found)


## Someone's scan caught you, from `origin`.
@rpc("authority", "call_remote", "reliable")
func _visor_felt(origin: Vector3) -> void:
	var me: Actor = _actors.get(my_actor_id)
	if me != null and is_instance_valid(me):
		me.visor.felt_scan.emit(origin)


## Your tactical visor: a hit on you came from `origin`.
@rpc("authority", "call_remote", "reliable")
func _visor_threatened(origin: Vector3) -> void:
	var me: Actor = _actors.get(my_actor_id)
	if me != null and is_instance_valid(me):
		me.visor.threatened.emit(origin)


## Your Threat Sense: who is aiming at you right now.
@rpc("authority", "call_remote", "reliable")
func _visor_threats(ids: Array) -> void:
	var me: Actor = _actors.get(my_actor_id)
	if me == null or not is_instance_valid(me):
		return
	var found: Array = []
	for id: Variant in ids:
		if typeof(id) == TYPE_INT and _actors.has(id):
			found.append(_actors[id])
	me.visor.show_threats(found)


## Someone on your side tagged a target.
@rpc("authority", "call_remote", "reliable")
func _visor_tag(tagger_id: int, target_id: int, seconds: float) -> void:
	var tagger: Actor = _actors.get(tagger_id)
	var target: Actor = _actors.get(target_id)
	if tagger != null and is_instance_valid(tagger) and target != null and is_instance_valid(target):
		tagger.visor.add_tag(target, clampf(seconds, 0.0, 30.0))


## An army's push on a strongpoint (`Raid.army_pushed`): public news, so
## every player in the world hears the horn and sees the arrow.
@rpc("authority", "call_remote", "reliable")
func _army_push(site: int, from: Vector3, title: String, loud: bool) -> void:
	if raid != null:
		raid.note_push(site, from, title.left(40), loud)


@rpc("authority", "call_remote", "reliable")
func _war_feed(text: String) -> void:
	if raid != null:
		raid.war_feed.emit(text)


## What you just picked up, item by item, for the visor's pickup feed
## (`Actor.looted`). The pack itself comes with `_inventory`.
@rpc("authority", "call_remote", "reliable")
func _looted(ids: Array) -> void:
	var me: Actor = _actors.get(my_actor_id)
	if me == null or not is_instance_valid(me):
		return
	var taken: Array[String] = []
	for id: Variant in ids:
		if id is String and ItemDB.has_item(id):
			taken.append(id)
	if not taken.is_empty():
		me.looted.emit(taken)


@rpc("authority", "call_remote", "reliable")
func _notice(text: String) -> void:
	var me: Actor = _actors.get(my_actor_id)
	if me != null:
		me.notice.emit(text)
		if text.begins_with("Looted "):
			Sfx.play("loot")


## Arena: ask the server for something (see `Arena.request`). A refusal
## comes back as a notice.
func arena_request(action: String, args := {}) -> void:
	if _is_connected() and my_actor_id >= 0:
		_arena_request.rpc_id(1, action, args)


## Race: ask the server to restart or stop your run (see `Race.request`).
func race_request(action: String) -> void:
	if _is_connected() and my_actor_id >= 0:
		_race_request.rpc_id(1, action)


## Race: ask the server for a ghost to chase (see `Race.want_ghost`).
func race_ghost_ask(pick: String, track_id: String, machine: String) -> void:
	if _is_connected() and my_actor_id >= 0:
		_race_ghost_ask.rpc_id(1, pick, track_id, machine)


## Race: the ghost asked for (or a new best of your own, as "mine").
@rpc("authority", "call_remote", "reliable")
func _race_ghost(pick: String, track_id: String, machine: String, answer: Dictionary) -> void:
	var race := raid as Race
	if race != null and str(answer.get("ghost", "")).length() <= 400_000:
		race.take_ghost(pick, track_id, machine, answer)


## Race: your friends' best laps, for the pit boards.
@rpc("authority", "call_remote", "reliable")
func _race_friends(rows: Array) -> void:
	var race := raid as Race
	if race != null:
		race.set_friend_bests(rows)


## Race: your own run, as the server judged it.
@rpc("authority", "call_remote", "reliable")
func _race_run(view: Dictionary) -> void:
	var race := raid as Race
	if race != null:
		race.set_remote_run(view)


## Race: each track's live race (`Race.heat_view`).
@rpc("authority", "call_remote", "reliable")
func _race_heats(rows: Array) -> void:
	var race := raid as Race
	if race != null:
		race.set_remote_heats(rows)


## Race: a rival's line on this racer's race radio.
@rpc("authority", "call_remote", "reliable")
func _race_radio(from: String, text: String) -> void:
	var race := raid as Race
	if race != null and race.player != null and is_instance_valid(race.player):
		race.radio.emit(race.player, from.left(40), text.left(200))


## Race: the best laps on the board.
@rpc("authority", "call_remote", "reliable")
func _race_board(rows: Array) -> void:
	var race := raid as Race
	if race != null:
		race.set_remote_board(rows)


@rpc("authority", "call_remote", "reliable")
func _arena_board(p_board: Dictionary) -> void:
	_after_lag(_receive_board.bind(p_board))


func _receive_board(p_board: Dictionary) -> void:
	var arena := raid as Arena
	if arena == null:
		return
	var was: String = arena.board.get("phase", "")
	arena.board = p_board
	# A fighter's guns are refilled on the server as the bout starts; do the
	# same to your own copy so the two agree.
	var me: Actor = _actors.get(my_actor_id)
	var bout: Dictionary = p_board.get("bout", {})
	if me != null and p_board.get("phase", "") == "countdown" and was != "countdown" \
			and String(me.name) in bout.get("nodes", []):
		Arena.refresh_fighter(me)


## Your contract counters for this life, for the watch.
@rpc("authority", "call_remote", "reliable")
func _tally(counts: Dictionary) -> void:
	var me: Actor = _actors.get(my_actor_id)
	if me == null:
		return
	var clean := {}
	for stat: Variant in counts:
		if typeof(stat) == TYPE_STRING:
			clean[stat] = maxi(0, int(counts[stat]))
	me.tally = clean


## Sends each player the footprints and wheel tracks laid near them since
## they were last sent that patch of ground (`Tracks.since`, by mark id).
func _send_tracks() -> void:
	for peer in _joined_peers:
		var viewer: Actor = _peer_actor.get(peer)
		if viewer == null or not is_instance_valid(viewer):
			continue
		var sent: Dictionary = _sent_tracks.get(peer, {})
		_sent_tracks[peer] = sent
		var fresh := []
		for cell in raid.tracks.cells_near(viewer.global_position, TRACK_RANGE):
			if fresh.size() >= TRACK_BATCH:
				break
			var marks := raid.tracks.since(cell, int(sent.get(cell, 0)))
			if marks.is_empty():
				continue
			marks = marks.slice(0, TRACK_BATCH - fresh.size())
			sent[cell] = int(marks.back()[0])
			fresh.append_array(marks)
		if not fresh.is_empty():
			_tracks.rpc_id(peer, Tracks.pack(fresh, raid.clock))


## Footprints and wheel tracks near you, for the snow to show.
@rpc("authority", "call_remote", "reliable")
func _tracks(data: PackedFloat32Array) -> void:
	if raid != null and raid.world != null and raid.world.tracks:
		raid.tracks.unpack(data, raid.clock)


## A linked faction's bot called the rest of its faction (`Raid.grid_called`):
## everyone near enough to hear it is told, so the call is seen and heard.
func _on_server_grid_called(bot: Actor, _source: Actor) -> void:
	var id: int = _ids.get(bot, -1)
	if id < 0:
		return
	for peer in _joined_peers:
		var viewer: Actor = _peer_actor.get(peer)
		if viewer != null and is_instance_valid(viewer) \
				and viewer.global_position.distance_to(bot.global_position) <= GRID_CALL_RANGE:
			_grid_call.rpc_id(peer, id)


## How far off a grid call is seen and heard.
const GRID_CALL_RANGE := 90.0


@rpc("authority", "call_remote", "unreliable")
func _grid_call(id: int) -> void:
	var actor: Actor = _actors.get(id)
	if raid != null and actor != null and is_instance_valid(actor):
		raid.grid_called.emit(actor, null)


## A salvo of the war's artillery was called (`Raid.shells_called`): where
## each shell lands and in how many seconds, for the view to mark and show.
## The server alone hurts anyone (`Shelling.land`).
@rpc("authority", "call_remote", "reliable")
func _shells(points: PackedVector3Array, lands_in: PackedFloat32Array) -> void:
	if raid != null and raid.world != null and raid.world.shelling > 0.0 \
			and points.size() == lands_in.size() and points.size() <= 16:
		raid.shells_called.emit(points, lands_in)


## Thin ice cracking (stages 1 and 2) or giving way (3) at `at`, for the
## view to show and sound.
@rpc("authority", "call_remote", "reliable")
func _ice_crack(at: Vector3, stage: int) -> void:
	if raid != null and raid.world != null and raid.world.thin_ice:
		raid.ice_cracked.emit(at, clampi(stage, 1, Raid.ICE_WARNINGS.size() + 1))


## A lift was powered with `left` seconds to run, or ran down (0), for the
## view (`Raid.lifts`).
@rpc("authority", "call_remote", "reliable")
func _lift(id: String, left: float) -> void:
	if raid != null:
		raid.set_lift(id, left)


## A keeper's phase (`Raid.keepers`): 1 standing, 2 below its split, 0
## fallen, for the deep beacon and the view.
@rpc("authority", "call_remote", "reliable")
func _keeper(kind: String, phase: int) -> void:
	if raid != null:
		raid.set_keeper(kind, phase)


## One of a keeper's purge lanes warns (1), vents (2) or goes quiet (0),
## for the view (`Raid.purge_changed`).
@rpc("authority", "call_remote", "reliable")
func _purge(index: int, state: int) -> void:
	if raid != null and index >= 0 and index < raid.purges.size():
		raid.purge_changed.emit(index, clampi(state, 0, 2))


## How far off a death burst's cloud is shown (`Raid.cloud_burst`).
const CLOUD_RANGE := 140.0


## A death burst's cloud (`Raid.cloud_burst`), for the view to show. The
## server alone hurts anyone in it.
@rpc("authority", "call_remote", "reliable")
func _cloud(at: Vector3, radius: float, seconds: float, kind: String) -> void:
	if raid != null and raid.world != null:
		raid.cloud_burst.emit(at, clampf(radius, 0.5, 20.0), clampf(seconds, 0.1, 60.0), kind.left(16))


## The open holes in the ice (`Raid.pack_ice_holes`).
@rpc("authority", "call_remote", "reliable")
func _ice_holes(data: PackedFloat32Array) -> void:
	if raid != null and raid.world != null and raid.world.thin_ice:
		raid.unpack_ice_holes(data)


## The army hunting you for a grudge ("" for none), for the visor's tag.
## Only the owner hears it.
@rpc("authority", "call_remote", "reliable")
func _hunted(faction: String) -> void:
	var me: Actor = _actors.get(my_actor_id)
	if me != null:
		me.hunted_by = faction.left(32)


## Your body heat and whether you stand in warmth, for the visor and the
## watch. Only the owner hears it; everyone else only sees the shivering.
@rpc("authority", "call_remote", "unreliable_ordered")
func _body_heat(heat: float, warming: bool) -> void:
	var me: Actor = _actors.get(my_actor_id)
	if me == null:
		return
	me.body_heat = clampf(heat, 0.0, me.max_body_heat)
	me.warming = warming


## What this life has sent home through depots, for the watch.
@rpc("authority", "call_remote", "reliable")
func _banked(count: int, value: int, scrip: int) -> void:
	var me: Actor = _actors.get(my_actor_id)
	if me == null:
		return
	me.banked_count = maxi(0, count)
	me.banked_value = maxi(0, value)
	me.banked_scrip = maxi(0, scrip)


## What is on your watch, and how long until you can throw again.
@rpc("authority", "call_remote", "reliable")
func _watch(stowed: Array, wait: float, summon_wait := 0.0, summon_total := 0.0) -> void:
	var me: Actor = _actors.get(my_actor_id)
	var state := raid.state_for(me) if raid != null and me != null else null
	if state == null:
		return
	state.stowed.clear()
	for id: Variant in stowed:
		if typeof(id) == TYPE_STRING and ItemDB.has_tag(id, "vehicle"):
			state.stowed.append(id)
	state.toy_ready_at = raid.clock + maxf(wait, 0.0)
	state.summon_ready_at = raid.clock + clampf(summon_wait, 0.0, 120.0)
	state.summon_wait_total = clampf(summon_total, 0.0, 120.0)
	raid.watch_changed.emit(me)


## Someone threw a toy vehicle: it has left their hand, so draw it flying.
## The vehicle itself follows from the server when it lands.
@rpc("authority", "call_remote", "reliable")
func _toy(thrower: int, item_id: String, from: Vector3, toy_velocity: Vector3, heading: float) -> void:
	if raid == null or not ItemDB.has_tag(item_id, "vehicle") or not from.is_finite() \
			or not toy_velocity.is_finite() or not is_finite(heading):
		return
	var actor: Actor = _actors.get(thrower)
	if actor != null and is_instance_valid(actor) and actor.toy_in_hand == item_id:
		actor.toy_in_hand = ""
	raid.fly_toy(item_id, from, toy_velocity, heading)


## Your sign-out started, with this many seconds to go, or stopped (below zero).
## `total` is the span the countdown is using now (ground, air or a gate), so
## the ring keeps its progress when the rate changes. `rate` is how fast it
## counts down now: 0 while away from a warm beacon, more with company there.
@rpc("authority", "call_remote", "reliable")
func _sign_out(seconds_left: float, total := -1.0, rate := 1.0) -> void:
	var me: Actor = _actors.get(my_actor_id)
	var state := raid.state_for(me) if raid != null and me != null else null
	if state != null:
		state.sign_out_left = seconds_left
		state.sign_out_total = total if total > 0.0 else maxf(seconds_left, 0.0)
		state.count_rate = clampf(rate, 0.0, 4.0)


@rpc("authority", "call_remote", "reliable")
func _run_finished(result: Dictionary) -> void:
	if result.get("outcome", "") == "died":
		_can_redeploy = true
	else:
		_finished = true
	run_finished.emit(result)


func _client_early_tick() -> void:
	while not _delayed_in.is_empty() and _delayed_in[0][0] <= Time.get_ticks_msec():
		_delayed_in.pop_front()[1].call()
	if raid == null:
		return
	_clock += 1
	_advance_view()
	for id: int in _actors:
		var actor: Actor = _actors[id]
		if not is_instance_valid(actor):
			continue
		var mine := id == my_actor_id
		if not mine:
			if _view_tick % 15 == id % 15:
				_thin(actor, id)
			# A press stays until the actor has had a step to act on it.
			if actor.stepped():
				actor.cmd.clear_one_shots()
		if not _latest.has(id):
			continue
		var entry: Array = _latest[id]
		_latest.erase(id)
		_apply_state(actor, entry, mine, int(_latest_tick.get(id, _newest_tick)))
	_blend_corrections()
	_client_move_vehicles()


## Moves the view on a tick. Everyone else is shown as a state left them,
## moved on by local simulation, so the screen shows a server tick: the one
## after the newest state when updates come evenly. Attacks made now are
## judged against that tick.
##
## The view runs on the client's own clock, not on when updates happen to
## arrive: an update that comes late finds the view a few ticks ahead of it
## and leaves it there, and `_apply_state` compares it with where the body
## was shown at that update's tick. Following the arrivals instead pulled
## every body back for a late update and pushed it on again for the next,
## which was the uneven stepping on a jittery connection.
func _advance_view() -> void:
	_view_tick += 1
	if _fresh_state:
		_fresh_state = false
		var lead := _view_tick - (_newest_tick + 1)
		if lead < 0:
			# An update from further on than the view: catch up with it.
			_view_tick -= lead
			lead = 0
		elif lead > MAX_VIEW_LEAD:
			_view_tick -= lead
			lead = 0
		_least_lead = lead if _least_lead < 0 else mini(_least_lead, lead)
	_lead_window += 1
	if _lead_window >= VIEW_SETTLE_TICKS:
		if _least_lead > 0:
			@warning_ignore("integer_division")
			_view_tick -= (_least_lead + 1) / 2
		_least_lead = -1
		_lead_window = 0


## Remembers where everyone else stands after this tick, for the next
## updates to be compared with (`Trail`).
func _note_shown() -> void:
	for id: int in _actors:
		if id == my_actor_id:
			continue
		var actor: Actor = _actors[id]
		if not is_instance_valid(actor):
			continue
		var trail: Trail = _trails.get(id)
		if trail == null:
			trail = Trail.new()
			trail.since = _clock
			_trails[id] = trail
		if actor.is_dead or actor.vehicle != null:
			# A rider goes where their vehicle goes: nothing here to compare.
			trail.since = _clock + 1
			continue
		trail.note(_clock, actor.global_position, actor.velocity)


## Far from your own player an actor is simulated in longer steps.
func _thin(actor: Actor, id: int) -> void:
	var me: Actor = _actors.get(my_actor_id)
	if me == null or not is_instance_valid(me):
		actor.thin(1)
		return
	var apart := me.global_position.distance_squared_to(actor.global_position)
	if apart <= THIN_NEAR_RANGE * THIN_NEAR_RANGE:
		actor.thin(1)
	else:
		actor.thin(2 if apart <= THIN_FAR_RANGE * THIN_FAR_RANGE else 4, id)


## Moves each actor a share of the way toward where the server says it
## should be, every tick, so fixes glide in.
func _blend_corrections() -> void:
	for id: int in _corrections.keys():
		var actor: Actor = _actors.get(id)
		if actor == null or not is_instance_valid(actor) or actor.is_dead or actor.vehicle != null:
			_corrections.erase(id)
			continue
		var left: Vector3 = _corrections[id]
		var step := left * CORRECTION_RATE if left.length() > 0.02 else left
		actor.global_position += step
		# Remembered positions move too, so the next comparison only sees
		# what is still wrong.
		if id == my_actor_id:
			for seq: int in _history:
				_history[seq] += step
		elif _trails.has(id):
			_trails[id].moved += step
		if step == left:
			_corrections.erase(id)
		else:
			_corrections[id] = left - step


func _apply_state(actor: Actor, entry: Array, mine: bool, tick: int = 0) -> void:
	var at: Vector3 = entry[1]
	var dead_kind: String = entry[7]
	if dead_kind != "":
		if not actor.is_dead:
			actor.global_position = at
			actor.kill(dead_kind)
		actor.set_sign_out_beacon(false)
		return
	if actor.is_dead:
		return
	actor.set_sign_out_beacon(_beacon_in(entry[3]))
	actor.health.health = entry[4]
	actor.health.armor = entry[5]
	var stagger: float = entry[6]
	if absf(actor.stagger_left - stagger) > 0.15:
		actor.stagger_left = stagger
	# A gate outpost's lock is the server's call (`Raid._tick_outposts`).
	if not raid.world.safe_zone and raid.world.weapons_free:
		actor.weapons_locked = typeof(entry[3]) == TYPE_ARRAY and entry[3].size() == ActorCommand.ARRAY_SIZE \
				and int(ActorCommand._number(entry[3][ActorCommand.FLAGS_INDEX])) & ActorCommand.STATE_SHELTERED != 0
	# So is the cold (`Raid._tick_cold`): everyone sees who shivers.
	actor.shivering = typeof(entry[3]) == TYPE_ARRAY and entry[3].size() == ActorCommand.ARRAY_SIZE \
			and int(ActorCommand._number(entry[3][ActorCommand.FLAGS_INDEX])) & ActorCommand.STATE_CHILLED != 0
	# And a knockdown (`Actor.knock_down`): down for what is left of the
	# stagger it came with.
	var down: bool = typeof(entry[3]) == TYPE_ARRAY and entry[3].size() == ActorCommand.ARRAY_SIZE \
			and int(ActorCommand._number(entry[3][ActorCommand.FLAGS_INDEX])) & ActorCommand.STATE_KNOCKED_DOWN != 0
	if down and actor.knocked_left <= 0.0 and actor.stagger_left > 0.0:
		actor.knocked_left = actor.stagger_left
		actor.knocked_time = actor.stagger_left
	elif not down:
		actor.knocked_left = 0.0
	var id: int = entry[0]
	if actor.vehicle != null:
		# A rider goes where their vehicle goes.
		if not mine:
			actor.cmd.apply_array(entry[3])
			actor.cmd.interact_pressed = false
		return
	if mine:
		# The server's position is from the past: it belongs to an input sent a
		# moment ago. Compare it with where this game predicted you would be
		# after that same input, not with where you are now. Running in a
		# straight line then needs no correction however slow the connection.
		var seq: int = entry[8]
		if not _history.has(seq):
			if actor.global_position.distance_to(at) > SNAP_DISTANCE:
				actor.global_position = at
				actor.velocity = entry[2]
				actor.flight.is_hovering = _hovering_in(entry[3])
			return
		var miss: Vector3 = at - _history[seq]
		max_correction = maxf(max_correction, miss.length())
		if miss.length() > SNAP_DISTANCE:
			actor.global_position += miss
			actor.velocity = entry[2]
			# Far enough out that the two sides may disagree on the jets.
			actor.flight.is_hovering = _hovering_in(entry[3])
			_history.clear()
			_corrections.erase(id)
		elif miss.length() > 0.01:
			_corrections[id] = miss
		else:
			_corrections.erase(id)
		return
	actor.cmd.apply_array(entry[3])
	actor.flight.is_hovering = _hovering_in(entry[3])
	# Looting is decided by the server, never replayed here.
	actor.cmd.interact_pressed = false
	# Like your own position, another player's is from the past when its
	# update was late: it belongs to `tick`, and the view may have moved on.
	# So it is compared with where this game showed them at that tick, not
	# with where they are now, and an update's lateness moves nobody.
	var then := _clock - (_view_tick - tick)
	var trail: Trail = _trails.get(id)
	if trail != null and trail.has(then, _clock):
		var miss := at - trail.place(then)
		if miss.length() > SNAP_DISTANCE:
			actor.global_position += miss
			trail.moved += miss
			_corrections.erase(id)
		else:
			_corrections[id] = miss
		var push: Vector3 = entry[2] - trail.speed(then)
		actor.velocity += push
		trail.pushed += push
		return
	var gap := at - actor.global_position
	if gap.length() > SNAP_DISTANCE:
		actor.global_position = at
		_corrections.erase(id)
	else:
		_corrections[id] = gap
	actor.velocity = entry[2]


## Whether a state's command says this actor's airborne sign-out beacon is up.
static func _beacon_in(cmd: Variant) -> bool:
	return typeof(cmd) == TYPE_ARRAY and cmd.size() == ActorCommand.ARRAY_SIZE \
			and int(ActorCommand._number(cmd[ActorCommand.FLAGS_INDEX])) & ActorCommand.STATE_SIGN_OUT_BEACON != 0


## Whether a state's command says the server has that actor's jets lit.
static func _hovering_in(cmd: Variant) -> bool:
	return typeof(cmd) == TYPE_ARRAY and cmd.size() == ActorCommand.ARRAY_SIZE \
			and int(ActorCommand._number(cmd[ActorCommand.FLAGS_INDEX])) & ActorCommand.STATE_HOVERING != 0


func _client_late_tick() -> void:
	_note_shown()
	var me: Actor = _actors.get(my_actor_id)
	if me == null or not is_instance_valid(me) or me.is_dead or not _is_connected():
		return
	# Number this tick's input and remember where it left you, to compare with
	# the server's answer later.
	_seq += 1
	if me.vehicle != null:
		# A rider goes where their vehicle goes; the ride is what is compared.
		_history.clear()
		_ride_history[_seq] = [me.vehicle.global_position, float(me.vehicle.get("heading")),
				float(me.vehicle.get("speed")), float(me.vehicle.get("slip"))]
		_ride_history.erase(_seq - HISTORY_TICKS)
	else:
		_ride_history.clear()
		_history[_seq] = me.global_position
		_history.erase(_seq - HISTORY_TICKS)
	# Every packet carries the inputs the server has not answered for, so one
	# that arrives makes up for all the packets lost before it.
	while not _recent_inputs.is_empty() and int(_recent_inputs[0][0]) <= _acked_seq:
		_recent_inputs.pop_front()
	_recent_inputs.append([_seq, me.cmd.to_array(), _view_tick])
	if _recent_inputs.size() > MAX_INPUTS_PER_PACKET:
		_recent_inputs.pop_front()
	var now := Time.get_ticks_msec()
	if simulated_loss <= 0.0 or randf() >= simulated_loss:
		_delayed_out.append([now + simulated_lag * 1000.0, _recent_inputs.duplicate()])
	while not _delayed_out.is_empty() and _delayed_out[0][0] <= now:
		_send_input.rpc_id(1, pack_inputs(_delayed_out.pop_front()[1]))


func _is_connected() -> bool:
	return _api.multiplayer_peer != null \
			and _api.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


# ---------------------------------------------------------------- social ----
# The phone: who is online, messages, invites and news. The server keeps it all
# in `social` (`core/social/social_service.gd`) and sends each player a fresh
# snapshot whenever something they can see changes. A client only sends
# requests; the server always knows who sent them from the peer's sign-in.

## Server: one request of the phone's (`SocialService.run`), run by this
## server's own service or by the account service, which then reaches the
## players it concerns wherever they are.
func _social_do(action: String, account_id: String, args: Array = []) -> Dictionary:
	if stash.is_remote():
		return await stash.social(action, account_id, args)
	var result := social.run(action, account_id, args)
	# Every session of this server shares the one service, so someone in the
	# plaza hears from someone out in a world.
	var told := false
	for session in _hosting:
		if is_instance_valid(session) and session.social == social:
			session._social_deliver(result)
			told = told or session == self
	if not told:
		_social_deliver(result)
	return result


## Server: sends the players here what a phone request changed for them.
func _social_deliver(result: Dictionary) -> void:
	var tell: Array = result.get("tell", [])
	if SocialService.EVERYONE in tell:
		_broadcast_social()
	else:
		for account_id: String in tell:
			_send_social_to(account_id)
	var notices: Dictionary = result.get("notices", {})
	for account_id: String in notices:
		for text: Variant in notices[account_id]:
			_on_social_noticed(account_id, str(text))


## Server: a peer finished signing in.
func _social_joined(peer: int) -> void:
	var account_id: String = _peer_account[peer]
	await _social_do("online", account_id, [stash.name_of(account_id), "lobby", world_id])
	if stash.is_remote():
		# The others hear within a moment; their own phone is here now.
		_send_social(peer)


## Server: a signed-in peer is going away.
func _social_left(peer: int) -> void:
	var account_id: String = _peer_account.get(peer, "")
	if account_id == "":
		return
	# Another connection for the same account may still be signed in.
	for other: int in _peer_account:
		if other != peer and _peer_account[other] == account_id:
			return
	_social_do("offline", account_id, [world_id])


## Server: a player moved somewhere else ("lobby", "raid", or a place another
## feature adds, see `SocialService.PLACE_NAMES`).
func _social_moved(peer: int, where: String) -> void:
	_set_presence(peer, where)


func _set_presence(peer: int, where: String) -> void:
	if not _peer_account.has(peer):
		return
	_social_do("where", _peer_account[peer], [where, world_id])


## Server: where a signed-in peer is, for the phone.
func _place_of(peer: int) -> String:
	if not _peer_actor.has(peer) or raid == null:
		return "lobby"
	return "hub" if raid.world.safe_zone else "raid"


## Server: sends every signed-in player their phone snapshot, but for a peer
## that is on its way out.
func _broadcast_social() -> void:
	if _api.multiplayer_peer == null:
		return
	var peers := _api.get_peers()
	for peer: int in _peer_account:
		if peer != _leaving and peer in peers:
			_send_social(peer)


func _send_social(peer: int) -> void:
	if not _peer_account.has(peer) or peer == _leaving or peer not in _api.get_peers():
		return
	var account_id: String = _peer_account[peer]
	var snapshot: Dictionary = stash.social_snapshot(account_id) if stash.is_remote() else social.snapshot(account_id)
	if not snapshot.is_empty():
		_social.rpc_id(peer, snapshot)
		# A squad made or left on the phone is who walks through your portals.
		if _peer_actor.has(peer):
			_set_squad_key(account_id, str(snapshot.get("squad", {}).get("id", "")))


## Server: sends `account_id` their phone snapshot, if they are here.
func _send_social_to(account_id: String) -> void:
	var peer := _peer_for_account(account_id)
	if peer > 0:
		_send_social(peer)


## Server: a line for `account_id` to be shown now, if they are here.
func _on_social_noticed(account_id: String, text: String) -> void:
	var peer := _peer_for_account(account_id)
	if peer > 0 and peer != _leaving:
		_social_notice.rpc_id(peer, text.left(400))


## Server: the peer signed in as `account_id`, or -1.
func _peer_for_account(account_id: String) -> int:
	if _api.multiplayer_peer == null:
		return -1
	for peer: int in _peer_account:
		if _peer_account[peer] == account_id and peer in _api.get_peers():
			return peer
	return -1


## The sender's account id, or "" when the sender has not signed in.
func _social_sender() -> String:
	if not is_server:
		return ""
	return _peer_account.get(_api.get_remote_sender_id(), "")


## Server: what a phone request ends with for whoever asked: the reason it
## failed, and their phone as it now stands.
func _social_answer(peer: int, result: Dictionary) -> bool:
	if not _here(peer):
		return false
	if not result.get("ok", false):
		_social_error.rpc_id(peer, str(result.get("error", "That did not work.")))
	_send_social(peer)
	return result.get("ok", false)


@rpc("any_peer", "call_remote", "reliable")
func _request_message(to: String, text: String) -> void:
	if not _allow("social"):
		return
	var from := _social_sender()
	if from == "":
		return
	var peer := _api.get_remote_sender_id()
	_social_answer(peer, await _social_do("message", from, [to.left(64), text.left(SocialService.MAX_MESSAGE * 2)]))


@rpc("any_peer", "call_remote", "reliable")
func _request_invite(to: String, kind: String) -> void:
	if not _allow("social"):
		return
	var from := _social_sender()
	if from == "":
		return
	var peer := _api.get_remote_sender_id()
	_social_answer(peer, await _social_do("invite", from, [to.left(64), kind.left(16), world_id]))


@rpc("any_peer", "call_remote", "reliable")
func _request_answer_invite(invite_id: int, accept: bool) -> void:
	if not _allow("social"):
		return
	var account_id := _social_sender()
	if account_id == "":
		return
	var peer := _api.get_remote_sender_id()
	var result: Dictionary = await _social_do("answer", account_id, [invite_id, accept])
	if not _social_answer(peer, result) or not accept or typeof(result.get("invite")) != TYPE_DICTIONARY:
		return
	var invite: Dictionary = result.invite
	if invite.get("kind", "") == "base":
		# A base is a view of the owner's gear and upgrades, so send just that.
		var owner: Dictionary = await stash.fetch(str(invite.get("from", "")))
		if not _here(peer):
			return
		_base_visit.rpc_id(peer, str(invite.get("from_name", "")), owner.get("stash", []), owner.get("loadout", {}),
				owner.get("base_upgrades", []), owner.get("base_plan", {}))
	else:
		_world_invite_accepted.rpc_id(peer, invite)


## `action` is "leave" (the only thing done to a squad from the phone; one is
## made by accepting a squad invite).
@rpc("any_peer", "call_remote", "reliable")
func _request_squad(action: String) -> void:
	if not _allow("social"):
		return
	var account_id := _social_sender()
	if account_id == "" or action != "leave":
		return
	var peer := _api.get_remote_sender_id()
	_social_answer(peer, await _social_do("squad", account_id, [action]))


## `action` is "add", "remove", "block" or "unblock".
@rpc("any_peer", "call_remote", "reliable")
func _request_contact(action: String, other: String) -> void:
	if not _allow("social"):
		return
	var account_id := _social_sender()
	if account_id == "":
		return
	if action not in ["add", "remove", "block", "unblock"]:
		return
	var peer := _api.get_remote_sender_id()
	_social_answer(peer, await _social_do("contact", account_id, [action, other.left(64)]))
	if raid is Race and _peer_actor.has(peer):
		# Friends changed: so do the friends' times on the pit boards.
		_send_friend_bests(peer)


@rpc("authority", "call_remote", "reliable")
func _social(snapshot: Dictionary) -> void:
	social_state = snapshot
	social_changed.emit(snapshot)


@rpc("authority", "call_remote", "reliable")
func _social_error(reason: String) -> void:
	social_error.emit(reason)


@rpc("authority", "call_remote", "reliable")
func _social_notice(text: String) -> void:
	social_notice.emit(text)


@rpc("authority", "call_remote", "reliable")
func _world_invite_accepted(invite: Dictionary) -> void:
	world_invite_accepted.emit(invite)


@rpc("authority", "call_remote", "reliable")
func _base_visit(owner_name: String, owner_stash: Array, owner_loadout: Dictionary, owner_upgrades: Array,
		owner_plan: Dictionary) -> void:
	base_visit_requested.emit(owner_name, owner_stash, owner_loadout, owner_upgrades, owner_plan)


## Phone: message a player on this server, or a saved contact.
func send_message(to: String, text: String) -> void:
	if _is_connected() and not account.is_empty():
		_request_message.rpc_id(1, to, text)


## Phone: invite a player online here to this server's raid ("world"), to
## your home base ("base") or to your squad ("squad").
func send_invite(to: String, kind: String) -> void:
	if _is_connected() and not account.is_empty():
		_request_invite.rpc_id(1, to, kind)


func answer_invite(invite_id: int, accept: bool) -> void:
	if _is_connected() and not account.is_empty():
		_request_answer_invite.rpc_id(1, invite_id, accept)


## Phone: leave the squad you are in.
func leave_squad() -> void:
	if _is_connected() and not account.is_empty():
		_request_squad.rpc_id(1, "leave")


## Phone: "add", "remove", "block" or "unblock" a contact.
func change_contact(action: String, other: String) -> void:
	if _is_connected() and not account.is_empty():
		_request_contact.rpc_id(1, action, other)


## Containers and vehicles this session knows about. For tests and tools.
func containers() -> Array:
	return _containers.values()


func vehicles() -> Array:
	return _vehicles.values()


## The world or venue with this id: a world from the registry, or the arena.
static func world_for(id: String) -> WorldDef:
	if id == ArenaVenue.ID:
		return ArenaVenue.new()
	return Worlds.get_world(id)


## The actor for a network id, or null. For tests and tools.
func actor_for(id: int) -> Actor:
	var actor: Actor = _actors.get(id)
	return actor if actor != null and is_instance_valid(actor) else null


func _physics_process(_delta: float) -> void:
	if is_server:
		_server_early_tick()
	else:
		_client_early_tick()


## Runs after every actor has simulated its tick.
class LateTick:
	extends Node

	var session: NetSession

	func _ready() -> void:
		process_physics_priority = 100

	func _physics_process(delta: float) -> void:
		if session.is_server:
			session._server_late_tick(delta)
		else:
			session._client_late_tick()


## Where a client showed another player's body after each of its last few
## ticks, and how fast it was going. An update from the server is about one
## server tick; this is what it is compared with, the way your own position
## is compared with `_history`.
class Trail:
	const TICKS := 32

	## The first client tick remembered here.
	var since := 0
	## Corrections made to the body since: every remembered place and speed
	## counts as moved by them, so a comparison only sees what is still wrong.
	var moved := Vector3.ZERO
	var pushed := Vector3.ZERO
	var _places := PackedVector3Array()
	var _speeds := PackedVector3Array()

	func _init() -> void:
		_places.resize(TICKS)
		_speeds.resize(TICKS)

	func note(clock: int, at: Vector3, velocity: Vector3) -> void:
		_places[clock % TICKS] = at - moved
		_speeds[clock % TICKS] = velocity - pushed

	## Whether the tick `clock` is remembered, on a client now at tick `now`.
	func has(clock: int, now: int) -> bool:
		return clock >= since and clock > now - TICKS and clock < now

	func place(clock: int) -> Vector3:
		return _places[clock % TICKS] + moved

	func speed(clock: int) -> Vector3:
		return _speeds[clock % TICKS] + pushed


## One player's inputs on the server, between arriving and being played.
##
## The server plays one input a tick, in order, as soon as it has it. Nothing
## is held back to smooth over a bad connection, because a held input is
## input delay. So two things can go wrong, and each has its answer:
##
## Nothing to play (a lost or late packet). The tick is played as a guess:
## the held keys carry on, and it counts as the next input (`played` moves
## on). When the real input turns up, its tick has been played already, so it
## is skipped: only its presses are kept, for the next input played, along
## with any held key that went down in it (a trigger tapped for one tick is
## a shot, and must not vanish with the input it was in). The
## server's count of ticks stays in step with the player's, and a guess is
## exactly right whenever the keys had not changed. If the late input is the
## newest there is, the player's inputs are running later than the server
## thought: it is played after all, under the number the guess took.
##
## More than is needed (a burst after a stall, or inputs arriving faster than
## they are played). Inputs that were spare for a whole window are folded
## away, keeping their presses and taps, so the delay does not stay.
class InputBuffer:
	extends RefCounted

	## Held keys a skipped input may hand on as a tap. The visor's zoom level
	## is a number, not a key, so it is left out.
	const TAP_MASK := ActorCommand.HELD_MASK & ~ActorCommand.VISOR_LEVEL_MASK

	## Inputs not yet played, oldest first: [number, command array, view tick].
	var queue: Array = []
	## The newest input number received.
	var newest := 0
	## The input number the actor has been simulated up to. A guess counts.
	var played := 0
	## An input has been played in this life. Before that nothing is guessed.
	var live := false
	## How many ticks were guesses, and how many inputs were skipped or folded.
	var guessed := 0
	var skipped := 0
	## The newest input that arrived after its tick had been guessed, if it
	## has not been dealt with yet, and the presses of every such input.
	var _late: Array = []
	var _late_flags := 0
	var _late_switch := -1
	## Held keys that went down in a skipped or folded input: taps the actor
	## has not seen yet. They ride on the next input played, like a press.
	var _late_taps := 0
	## The held keys of the last input played, which a guess carries on with.
	var _held := 0
	var _spare := 0
	var _window := 0

	## Takes the inputs of one packet: every input the player has not had an
	## answer for, oldest first. Ones seen before are ignored.
	func receive(inputs: Array) -> void:
		for input: Array in inputs:
			var number: int = input[0]
			if number <= newest:
				continue
			newest = number
			if number > played or not live:
				queue.append(input)
			else:
				_keep_presses(input[1])
				_late = input
				skipped += 1
		# A burst after a stall: fold the oldest inputs together to catch up.
		while queue.size() > NetSession.MAX_QUEUED_INPUTS:
			_fold_oldest()

	## The input to play this tick, as [number, command array, view tick], or
	## an empty array when there is none and the held keys carry on.
	func next() -> Array:
		_trim()
		if not queue.is_empty():
			var input: Array = queue.pop_front()
			_spare = mini(_spare, queue.size())
			_add_presses(input[1])
			_late = []
			played = input[0]
			live = true
			return input
		_spare = 0
		if not _late.is_empty():
			# Late, and still the newest there is: play it under the number
			# the guess took.
			var input := _late
			_late = []
			_add_presses(input[1])
			skipped -= 1
			return input
		if live and played - newest < NetSession.MAX_GUESSED_INPUTS:
			played += 1
			guessed += 1
		return []

	## The life this buffer fed has ended: nothing waits for the next one.
	func rest() -> void:
		queue.clear()
		_late = []
		_late_flags = 0
		_late_switch = -1
		_late_taps = 0
		_held = 0
		live = false
		played = newest

	func _trim() -> void:
		_window += 1
		if _window < NetSession.INPUT_TRIM_TICKS:
			return
		for i in mini(ceili(_spare / 2.0), queue.size() - 1):
			_fold_oldest()
		_window = 0
		_spare = queue.size()

	## Drops the oldest input, keeping its presses for the one after it.
	func _fold_oldest() -> void:
		_keep_presses(queue.pop_front()[1])
		skipped += 1

	func _keep_presses(cmd: Array) -> void:
		_late_flags |= int(cmd[ActorCommand.FLAGS_INDEX]) & ActorCommand.ONE_SHOT_MASK
		# A key that was not down in the last input played went down in this
		# one. If it is up again in the next input played, that was a tap the
		# actor never saw: an automatic's single shot, lost with its input.
		_late_taps |= int(cmd[ActorCommand.FLAGS_INDEX]) & TAP_MASK & ~_held
		if int(cmd[ActorCommand.SWITCH_INDEX]) != -1:
			_late_switch = int(cmd[ActorCommand.SWITCH_INDEX])

	## Adds the kept presses and taps of skipped inputs to the command about
	## to be played.
	func _add_presses(cmd: Array) -> void:
		cmd[ActorCommand.FLAGS_INDEX] = int(cmd[ActorCommand.FLAGS_INDEX]) | _late_flags | _late_taps
		_late_taps = 0
		_held = int(cmd[ActorCommand.FLAGS_INDEX]) & TAP_MASK
		if int(cmd[ActorCommand.SWITCH_INDEX]) == -1:
			cmd[ActorCommand.SWITCH_INDEX] = _late_switch
		_late_flags = 0
		_late_switch = -1


## Server: how many requests each player may make, so one connection can
## neither flood the server with work nor fill its saves. Each kind of
## request has a bucket per player that refills at a steady rate (by server
## tick, so it holds at any frame rate) up to a burst. A request with the
## bucket empty is dropped. The limits sit well above what the game itself
## sends: equipping a whole kit at once, a burst of watch clicks, and an
## input packet every tick with room to catch up.
class RequestLimits:
	extends RefCounted

	## kind -> [refill a tick, burst]
	const KINDS := {
		"lobby": [0.25, 60.0],   # 15 a second
		"world": [0.25, 40.0],   # 15 a second
		"social": [0.05, 12.0],  # 3 a second
		"input": [1.5, 120.0],   # 90 a second; a game sends 60
	}
	## Refused requests within KICK_WINDOW ticks that drop the connection.
	const KICK_AFTER := 300
	const KICK_WINDOW := 600
	## Ticks between "slow down" notices to one player.
	const WARN_EVERY := 120

	var _buckets := {}  # peer -> {kind: [tokens, tick last refilled]}
	var _refused := {}  # peer -> [refused in this window, tick it started]
	var _warned := {}   # peer -> tick of the last notice

	func allow(peer: int, kind: String, tick: int) -> bool:
		var spec: Array = KINDS.get(kind, KINDS.world)
		var mine: Dictionary = _buckets.get_or_add(peer, {})
		var bucket: Array = mine.get_or_add(kind, [float(spec[1]), tick])
		bucket[0] = minf(float(spec[1]), float(bucket[0]) + float(spec[0]) * maxi(0, tick - int(bucket[1])))
		bucket[1] = tick
		if bucket[0] >= 1.0:
			bucket[0] -= 1.0
			return true
		var strikes: Array = _refused.get_or_add(peer, [0, tick])
		if tick - int(strikes[1]) > KICK_WINDOW:
			strikes[0] = 0
			strikes[1] = tick
		strikes[0] += 1
		return false

	## True once a player has had so many requests refused that it can only
	## be a flood.
	func flooding(peer: int) -> bool:
		return int(_refused.get(peer, [0, 0])[0]) >= KICK_AFTER

	## True if a player whose request was refused should be told (once in a while).
	func may_warn(peer: int, tick: int) -> bool:
		if tick - int(_warned.get(peer, -WARN_EVERY)) < WARN_EVERY:
			return false
		_warned[peer] = tick
		return true

	func forget(peer: int) -> void:
		_buckets.erase(peer)
		_refused.erase(peer)
		_warned.erase(peer)
