# Online play

Rules for sign-in, encryption, input and movement netcode, lag compensation, the account service, server stashes, several sessions in one process, one program per world and travel. These are part of the rules in `CLAUDE.md` that must not be
broken: read this file before changing anything it covers, and keep it up to
date in the same PR.

- Signing in is part of the connection (DESIGN.md section 14): a client
  sends its version and sign-in through `SceneMultiplayer.auth_callback`
  (`NetSession._server_auth`, `_client_auth`) and counts as connected only
  once the server accepts, so an old game or a wrong secret never reaches
  the session. Who a player is gets decided in one place,
  `StashService.sign_in_with(credentials)`, by "method": the name and
  secret, or a token. A sign-in with the secret hands back a token
  (`NetSession.ticket`, kept per address by `main.gd`) that the game shows
  the next server instead of the secret, and that every server of one
  account service accepts; one that has run out is answered `"again":
  "secret"` on the same connection. The third method is "recovery": the
  name, the account's recovery code and the new computer's secret, which
  the account takes on (the old secret and any token stop working, the
  code is used up). A code comes from `StashService.make_recovery_code`,
  asked for in the phone's Servers app (`NetSession.request_recovery_code`)
  and shown there once; the account keeps only its hash, and a new code
  cancels the last. Typed into the Servers app's "Move your account here"
  card, it rides the next sign-in only (`NetSession.recovery`,
  `Main._recovery_code`). A store login (Steam) is a new method
  there that ends in an account id, never a second path into a session. Both sides' messages always carry "protocol", so any two
  versions can say which one needs the update. `NetSession.PROTOCOL` is
  the handshake's own version and nothing else's: never raise it for a new
  or changed message. What a build says once signed in is its manifest
  (`core/net/net_manifest.gd`, `NetManifest`), read off the code: every
  `@rpc` method by name, argument types and how it is sent, plus every
  `WIRE_` constant. A game shows its manifest's digest as it signs in and
  the server lets in only its own; one turned away is sent the server's
  manifest and build number, so it says which side is older
  (`NetSession.outdated`, "either" between builds with no number) and its
  log names what differs. So a new, removed or changed RPC needs nothing
  else; a change to what an existing message carries raises (or adds) the
  `const WIRE_<WHAT>` beside the code that packs it; a script whose
  constants are the format lists their prefixes in `WIRE_ALSO`
  (`ActorCommand`'s flag bits); and a script with RPCs or packing of its
  own goes in `NetManifest.PARTS` once. An older game is pointed at
  `NetSession.UPDATE_URL` from the phone's Servers app. Every connection is
  encrypted with ENet DTLS (`core/net/server_trust.gd`): a server makes its
  own certificate on first start, kept beside the accounts, and a game
  remembers it per address on first use and warns on the Servers app if it
  changes (never for this computer's own server, nor for official hosts in
  `ServerTrust.OFFICIAL_HOSTS`, which use real certificates). The secret is
  only ever sent encrypted; the checks that send none (`probe`, `plain`)
  are how a game learns a server changed or is from before encryption. `server_relay` is
  off: clients only talk to the server. Every `any_peer` RPC starts with
  `_allow(kind)` (`NetSession.RequestLimits`, per player, refilled by server
  tick), and a new one must too. Server saves that are files (clans, phone
  records, the JSON fallback) go through `core/account/safe_file.gd`
  (written whole, then swapped in); accounts are in SQLite (below). The
  `StashService` keeps rolling backups of the whole save folder
  (`backup_if_due`, `backup_dir`), the database copied with
  `AccountStore.backup_to`, never as the live file. An account that cannot
  be read is never replaced by a new account.
- Online movement: a client numbers every input and each packet repeats
  every input the server has not received yet (up to
  `NetSession.MAX_INPUTS_PER_PACKET`, packed small by `pack_inputs` so a
  full packet fits in one datagram; the command's flags take 40 bits, the
  low 32 and then a byte of their own, so a new press past bit 31 needs no
  new layout), so a press survives a run of lost
  packets. The server plays them in order, one per tick, as soon as it has
  them (`NetSession.InputBuffer`): nothing is held back to smooth a bad
  connection, because a held input is input delay. A tick with nothing to
  play is a guess (the held keys carry on) that counts as the next input,
  and the real one is skipped when it arrives late, keeping its presses
  and any held key that went down in it (a one-tick tap of the trigger is a
  shot, see `InputBuffer._late_taps`); inputs that stay spare are trimmed. Each state entry carries the input
  number the actor had been simulated up to (guesses included), and a
  player's own entry also carries the newest input received, which is the
  answer that stops the resending. The client corrects its own
  actor by comparing the server's position with its remembered prediction for
  that input (`NetSession._history`), never with its current position, and
  blends every correction over several ticks. Everyone else is corrected
  the same way: the view runs on the client's own clock
  (`NetSession._advance_view`), never on when updates arrive, and an update
  is compared with where the client showed that body at the update's
  server tick (`NetSession.Trail`, `_note_shown`), never with where it is
  now, so a late update moves nobody (that was the uneven stepping on a
  jittery connection; feel it with `--jitter`). Nothing is held back to
  smooth them either. Keep `Actor` movement
  deterministic from its `ActorCommand` so prediction keeps matching.
- Lag compensation: each input also carries the server tick the client's view
  had reached, and the server keeps half a second of past positions. Attacks
  judge targets at `Combat.positions_seen_by(attacker)` (shots via
  `Combat.trace`), never by reading other actors' `global_position` directly,
  so a lagging player hits what was on their screen. A vehicle the local
  player rides is predicted and corrected against `NetSession._ride_history`
  like the player's own actor.
- The account service (DESIGN.md section 14): official servers share one
  set of accounts, kept by one headless program, `-- --account-service`
  (`core/account/account_service.gd`: the same `StashService` on SQLite,
  with the market's board beside it). A game server started with
  `--account-url` holds an `AccountLink` (`core/account/account_link.gd`) in
  `NetSession.stash` instead of a `StashService`; any other server keeps
  its own accounts and nothing moves between the two kinds. The link offers
  the `StashService` calls, so a session never asks which it holds: every
  call that asks the accounts for something is made with `await` (free on
  a `StashService`, which answers at once), and what follows an `await`
  checks the player is still there (`NetSession._here`). Never read
  `_api.get_remote_sender_id()` after one. A new account call goes in
  `StashService`, `AccountLink` and `AccountService.CALLS` together. The
  link has three kinds of call: read at once from its copy of the accounts
  signed in on that server (`snapshot`, `scrip_of`, `showcase`; the service
  keeps the copy fresh and `account_changed` says when); awaited, giving up
  as "unanswered" after `ANSWER_TIMEOUT` (sign-in, equip, buy, deploy); and
  sure, kept and sent again until answered, for what the server alone
  knows (`bank`, `settle`, `cancel_deploy`, `change_scrip`, `record_arena`).
  The service does every request once: its receipt is written in the same
  transaction as its changes (`StashService.begin_hold` / `end_hold`,
  `AccountStore.write`'s `receipt`), so a new call that changes an account
  goes in `AccountService.HELD`. The market is the exception (the board has
  its own file), so a market request is sent once and never again. A
  deploy belongs to the server that made it (`Account.deployed_by`): only
  that server banks into it or settles it, a deploy never answered is
  undone by its own request id (`undo_deploy`), and a game server that
  starts afresh has its deploys returned. The service never returns a
  deploy just because it restarted (`returns_lost_deploys` off). Game
  servers prove the service key (`AccountService.load_key`) and players
  never reach the service. Where servers share the service it also keeps
  the clans, the phone's records and presence, so every world's program
  agrees: `NetSession` asks through `AccountLink.clan` and `social` (the
  service runs `ClanService.ask` and `SocialService.run`), reads clans
  from the link's copy (`AccountLink.clans`, a `ClanService` loaded with
  `load_state`, never written there) and is pushed its own players' phone
  snapshots. A server with its own accounts keeps its own `ClanService`
  and `SocialService` and makes the same two calls on them, so a new clan
  or phone request is a new action in `ClanService.ask` or
  `SocialService.run`, never a branch in `NetSession`. Presence is by
  seat (`SocialService.player_online`'s `seat`): travel signs a player in
  to two worlds for a moment, and they go offline only when the last seat
  goes.
- Online, the server owns each player's stash, loadout and mastery
  (`core/account/stash_service.gd`). A client's kit or picks are never trusted;
  the server gets them from `StashService.deploy` and applies results with
  `StashService.settle`. `NetSession` does both. A client only signs in
  (name plus `Profile.online_secret`) and sends requests (equip, pick, deploy)
  from the lobby; it never sends a kit, and online play never reads or writes
  the local `Profile` stash, with one exception: one player state.
  The service keeps accounts in SQLite (`core/account/account_store.gd`,
  `accounts.sqlite` in its `save_dir`, through `addons/godot-sqlite`): every
  `_save` is one transaction, and changes to several accounts that must
  happen together (a trade) go through `StashService.transaction`, never one
  ledger call after another. Never read or write account files directly;
  old ones are imported once by `AccountStore.open`. A build without the
  library falls back to JSON files. On a
  server you host yourself (`main.gd host_and_join`, the base's door) you
  are the player you are at home: the client hands the server your profile
  (`--host-profile`, read once into `StashService.host_profile`, claimed only
  with your own name and secret), and every account snapshot that comes back
  while you are not deployed becomes your profile again
  (`Main._keep_profile_in_step`, `Profile.adopt_account`). What is handed is
  `StashRules.CARRIED`, whole, never merged. Anyone else's server keeps a
  stash of its own. The hub shows the server's account snapshot while
  in a lobby (`Hub.enter_lobby`). Stash rules live once, in `core/account/stash_rules.gd`,
  shared by `Profile` and the service.
- A friends' server runs several `NetSession`s in one process (plaza on
  the port, raid worlds after it, `main.gd start_server`), each raid in its
  own 3D world (`NetSession.isolated`) and all sharing one `StashService`.
  Never use `Worlds.current` for rules: ask `Worlds.of(node)` or
  `Raid.of(node)`, and filter any scan of the "actors" group with
  `Raid.together`.
- One program per world (DESIGN.md section 14, "Scaling"): on servers that
  share an account service each world is its own program, `--server --only
  <world id>` (`main.gd start_one`), and `--server --cluster` runs the set
  on one machine, starting again any that stops (`Main._run_cluster`). So
  nothing may assume the other worlds are in the same process: a program
  tells the service where it is and how it is doing
  (`NetSession._announce`, `AccountLink.announce`) and learns the others
  from the service's directory (`AccountLink.worlds`, `worlds_changed`).
  Routes (`NetSession.routes`: world id to a port on the same host, or
  "host:port"; read on a client with `Main._route`) and `world_status`
  both come from that directory, or from the sessions in the process on a
  friends' server (`NetSession._gather_status`, `_routes_out`); anything
  else one world needs to know of another goes the same way, never
  through a reference to its session. Every program of a set shares one
  certificate (`ServerTrust.identity`, made once, safely when several
  start together), so a game trusts them all after the first.
- Travel hides its wait (DESIGN.md section 14): the game connects and
  signs in ahead with a second `NetSession` (`ahead`, `Main._tick_ahead`,
  `_trip_ahead` says where a doorway, an open portal or a sign-out leads;
  a sign-out through a portal out of a world leads where that portal does)
  and the trip adopts it (`Main._take_ahead` in `_try_join`). A session
  that is ahead never shows anything, never deploys and is never given a
  body: the server reclaims a body left standing only at the join
  (`NetSession._request_join`), keeps `lobby_room` connections spare for
  them and refuses a full world there, by name. A world whose ground is
  slow to work out offers `WorldDef.prepare_map`, run on a worker thread:
  it may only compute plain data kept under a lock (heights, collision),
  never touch the scene tree. The view goes dark at once and fades in
  when the world stands (`Main._fade_travel`, the one cover allowed over
  the view); the travel screen's text is only for a trip slower than
  `travel_quiet`.
- A sign-out through a portal to another place (`Portal.goes_on`) settles
  like any sign-out first: the server sends `run_finished` only after
  `stash.settle`, so the gear is home before the game goes on.
  `Main._return_to_lobby` then joins the destination's session straight
  away (`_onward_route`, worked out before the old session is freed),
  deploying with `Raid.PORTAL_DROP` for a world; no server sends anyone
  from one world's session to another, and the result's "door" is checked
  with `Portal.is_place` like anything else a client is told.
