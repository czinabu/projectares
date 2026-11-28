# Social spaces

Rules for clans, the Concourse's megacity and people, the War Room, squads and friends, safe zones and squad portals. These are part of the rules in `CLAUDE.md` that must not be
broken: read this file before changing anything it covers, and keep it up to
date in the same PR.

- Clans (`core/social/clan_service.gd`, `NetSession.clans`): the server keeps
  who is in which clan, keyed by account id, in one service shared by every
  session like the `StashService`. A client only asks (`NetSession.clan_ask`)
  and shows `clan_state`; the clan hall's terminal in the plaza is the view
  (`core/social/clan_panel.gd`). The `Raid` never asks about clans: before
  `add_player`, `NetSession` calls `Raid.set_team(owner, team, title)`, and
  a team is simply a shared side key, so strongpoints, drops and visor tags
  follow with no second mechanism. `Actor.clan` (set by the authority only
  where gear is at stake) stops friendly fire in `Combat.deal`;
  `Actor.clan_tag` is for views and is worn everywhere. Nobody changes clan
  while deployed.
- The Concourse's megacity (Caleb's "tall and grand"): the deck is one
  terrace part way up a city, not its roof. `worlds/plaza/megacity.gd`
  (view only, built by the map only where `Look` is on, its own RNG) stands
  rings of towers from a canyon floor far below (`FLOOR_Y`) to over a
  kilometre above, landmark spires, skyways (the near ring tied out past
  the rail, `_ties`), a monorail ring, lit signs and air traffic.
  Windows are never geometry: `megacity.gdshader` lights them floor by floor
  from the world position (the near ring wears it too, `material_for(true)`)
  and does its own haze; the traffic is one MultiMesh flown by
  `sky_traffic.gdshader` (the monorail's trains too). All of it is a handful of meshes, so a new tower
  is a box in the same batch, never a node. The map asks the view to draw
  out to `VIEW_FAR` (its "view_far" meta). Check by eye with
  `visual_check.tscn -- <dir> --hub-only`.
- The gate terrace (`worlds/plaza/map.gd` `_build_gates`, Caleb's yes to
  "make the gates show their worlds"): an open arch carries only what reads
  from across the plaza: its world's name, its risk (`gate_stakes`, read
  from the world's rules alone: `weapons_free`, `players_allied`,
  `keep_gear_on_death`, `gear_at_risk`, `death_drops_scrip`, so a new
  world's gate needs no line) and the server's live line
  (`PlazaView.heat_signs`, flat across the top of the doorway). The full
  write-up is on a console beside each open gate (group "gate_console"),
  drawn only up close. Each arch has a stepped frame (`_build_gate_frame`: flanges, a crown,
  a lit threshold) lit in its world's colour (`Look.gate_color`, from the
  planet's storm, so it is right headless too), with the world's crest on
  both pillars (`GateLook.crest`, an emblem picked from the planet's
  weather); a sealed arch is barred with clamped beams over blast doors
  (`_build_sealed_doors`). Where `Look` draws, the doorway shows a glimpse of
  the world (`GateLook.window`, `gate_window.gdshader`): one unshaded sheet
  that traces the eye's ray into a made-up scene from the world's
  `PlanetType` (sky, ridges, ground, its air and storm drifting), so it
  shifts like a window and never renders the world itself. A sealed arch
  shows a hologram of an unknown planet (`GateLook.teaser`) and never
  names a world held back (`LaunchScope`). The wall either side of every
  arch carries a slatted panel (`GateLook.meter`) that `PlazaView` fills
  from `world_status` (`gate_fill`) and pulses, with the fins' trims, when
  someone steps into the gate (`_tick_gates`, a few looks a second over
  the players, view only). Everything moving is in shaders and instance
  uniforms, so the terrace costs a few dozen draws and no per-frame
  script work beyond a running pulse. Check by eye with
  `visual_check.tscn -- <dir> --gates-only [--playtest] [--low]`.
  You walk into an open world gate to deploy (Caleb's call): standing in
  it counts down `PlazaView.gate_walk_in_time` (1.2 s) on the gate's face,
  stepping out cancels, [F] goes at once, and a gate that took you waits
  for you to step out (`step_walk_in`). A gate to a world the server
  lacks, or one the tour keeps closed (`tour_closed`), never counts;
  every other door still waits for [F]. The greybox's lit sheet is freed
  where a glimpse is drawn, so the world shows while you stand in it.
- The War Room (DESIGN.md section 2, "Spectating screens"): the plaza's
  big screen is `WarRoom` (`core/social/war_room.gd`, view only, made by
  `PlazaView` only where `Look` is on, drawn into a `SubViewport` on the
  map's "screen_wall"). It reads only `world_status`: each world's
  landmarks and who holds them (`Raid.front`: an army's faction,
  "players" or "", never a side key), its big moments (`Raid.note_moment`,
  authority only, a warlord or boss brought down and a landmark changing
  hands; `live_moments`; a world's wall-clock set pieces are
  `WorldDef.clock_moments`, Ashfront's Colossus), who its armies hunt
  (`Raid.hunted`, from the grudges where a world keeps them: who and by
  which army, never where) and a race world's AI-only race (`Race.race_feed`,
  shot by the screen's `TrackCam` from `WorldDef.feed_tracks`; with no race
  on it shows exhibition laps and says so). A client checks all of it
  (`NetSession.clean_front`, `clean_moments`, `clean_hunted`,
  `clean_race`). Segments turn on the wall clock (`SEGMENT_TIME`) so every
  watcher sees the same one; a side's colour is `WorldDef.faction_color`.
  The console before it (the "war_room" portal, `WarRoomPanel`,
  `main.gd open_war_room`) puts a picked world on the screen for that
  viewer only (`WarRoom.focus`) and deploys through `use_portal`, the way
  its gate does. Check by eye with `visual_check.tscn -- <dir> --war-room-only`.
- The Concourse's people (DESIGN.md section 2, "Locals"):
  `core/social/plaza_locals.gd`, made by `PlazaView` only where `Look` is
  on, so a server runs none and sends nothing for them. Every client makes
  the same crowd from the map's `locals_layout()` and `CROWD_SEED`, scattered
  in uneven groups (Caleb's call: never spaced evenly), and walks each local
  along a `Routine` timed by the wall clock. A local is an ordinary `Actor`
  driven only through its command, but out of the world: taken out of the
  "actors" group, no collision with people, never a child of the `Raid`
  (so `RaidRoster` never lists one), thinned when far. They look at people
  near them and step out of their way. The people you talk to stand at the
  map's "talker" markers; "talk:<id>" portals make them answer in a speech
  card over their head (`SpeechPanel`, in the world, never on the screen).
  Every counter (a shop, the clan hall) has a keeper, a talker the
  counter's portal names in its "keeper" meta, who greets whoever uses it
  (`PlazaLocals.greet`); a talker's own lines are the marker's "lines" meta
  (or "reads" "worlds", the dispatcher reading `world_status`); a keeper's
  marker names its shop ("shop" meta), and the keeper talks about its real
  stock and the player's own snapshot (`PlazaLocals.stock_lines`: today's
  piece by the date, an upgrade they can pay for, their salvage), never a
  price the shop does not charge. The boulevards between the plaza and
  the districts are places to stop, off the lane (`_build_boulevards`, no
  signs): their carts are the layout's "stops", each with a cook and
  customers who keep to one beat (`PlazaLocals.snack`, `SNACK_BEAT`), so
  no two stand in the same place in the queue or at a table. Nothing
  marks a portal on the floor (Caleb's call: no glowing pads, no floating
  ads or signs that do not match where they stand): an arch lights its
  "Lit" child while you stand in it (`PlazaView._light_arch`), and each
  district names itself on the building that holds it.
  What they say comes only from what the client already knows:
  `world_status` (Dusk's rumours, Kade on the board) and the account's
  contracts (Rook). Rook's favours are contract jobs of kind "favor"
  (`Contracts.favor_for`, one a day, never rerolled, left off the board's
  own lists), taken through the same `NetSession.contract_ask`.
- Squads and friends (DESIGN.md "Squads and friends"): a squad is the
  server's `SocialService` (made by a "squad" invite, kept in memory, left
  with "squad" ["leave"] or by going offline, `MAX_SQUAD`), and it is the
  key `Raid.set_squad` keeps for portals in place of the clan
  (`NetSession._set_squad_key`, refreshed with every phone snapshot), never
  a side. Squad chat is a message "to" `SocialService.SQUAD_CHAT`. Which
  world someone is in (`world_of`) is shown only to friends (contacts who
  saved each other) and squadmates, and the phone's Join goes there through
  `Main.join_world` (the squad portal's way), never from a world where gear
  is at stake.
- Safe zones: a world with `WorldDef.safe_zone` (the plaza, `worlds/plaza`)
  is a social space run by the same `Raid` and `NetSession`. `Combat.deal`
  refuses every hit there, `Actor.weapons_locked` stops attacks, abilities
  and healing (not helmets: a visor works everywhere, Caleb's call), and `NetSession` shows the loadout with `StashService.showcase`
  instead of `deploy`, so nothing leaves the stash and nothing is settled.
  Doorways are "portal" markers (see `WorldDef`); `core/social/plaza_view.gd`
  offers them and `main.gd use_portal` decides where each destination leads.
  Use `Worlds.raid_worlds()` for anything you deploy into.
- Squad portals (Caleb's call) replace the base's launch pad, arena gate and
  teleporter pad: no station deploys you. The watch's portal icon (first on
  the Mission tab, `Hud.portal_slot`, a carousel of `Portal.choices_for`)
  opens a `Portal` (`core/world/portal.gd`) in front of you, open
  `Portal.open_time` (about 15 s) for your squad to walk through. Where it
  can lead depends on where you are (Caleb's call: anywhere from
  anywhere): from your base every world, the arena and the plaza
  (`Portal.from_base`, `Portal.PLAZA` goes the way the base's door does);
  from a safe-zone world every world, the arena and `Portal.HOME` (the way
  the quarters door goes); out in a world where gear is at stake
  `Portal.HOME` first, then every other world, the arena and the plaza
  (`Portal.from_world`), each a sign-out; none in the arena. A squad is `Raid.squad_of`: the key
  `Raid.set_squad` gave the owner (`NetSession` sets the clan, in every
  world), else their side. Only the authority opens one in a world
  (`Raid.open_portal`, `may_open_portal`) and decides who walks through
  (`portal_entered`); online `NetSession` shows each portal to everyone
  (`_portal`, with whether the viewer's squad may use it and how long it
  unfolds; the squad key never leaves the server) and tells the walker
  (`portal_travel`). `main.gd go_through_portal` takes the trip, and arrival
  in a world is `add_player`'s drop `Raid.PORTAL_DROP`: the same "outpost"
  marker for a whole squad, else a quiet drop. Out in a world every portal
  is a sign-out with a door, never a way round one (`Portal.signs_out`):
  opening it is `begin_sign_out` (so a fight or a bounty refuses it, and it
  takes the sign-out's own time: the gate's in an outpost, 15 s on the
  ground, 25 s and a beacon in the air), the ring unfolds over that
  countdown where everyone can see it and folds away if it is cancelled
  (`Raid._keep_sign_out_portal`), a squadmate stepping in starts their own
  sign-out through the same door (`_tick_portals`, `PlayerState.sign_out_door`),
  and everyone leaves through `_leave` as "left" with the result's "door"
  set to where the ring led. Everything carried goes home with that, as
  with any sign-out. "home" then lands you in your base rather than the
  plaza online (`main.gd _return_to_lobby`); anything else
  (`Portal.goes_on`) carries on from home: solo `_on_solo_finished` goes
  home and then `go_through_portal`, online `_return_to_lobby` joins the
  other world's session with a portal drop (`_onward_route`), the arena's,
  or the plaza's. It never emits `portal_entered`, and no gear goes from
  one world straight into another (Caleb's call: it banks home first).
- The launch scope (`docs/systems/launch-scope.md`) shutters the arena gate
  and the Exchange (`_shutter`, a solid front with "OPENING SOON"), leaves
  the held worlds off the gate terrace and the War Room, and holds back base
  visits; a talker whose lines are about something held says
  `HELD_LINES` instead.
