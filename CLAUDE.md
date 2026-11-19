# Project Ares: notes for AI sessions

Full-loot PvPvE war game in Godot 4 (GDScript). Each world is an endless
warzone, not a timed raid (see the endless warzone rule below). See README.md for the
layout and how to play. The roadmap is: Phase 0 bot-only prototype (done),
Phase 1 vertical slice (hub, loadouts, abilities, motorbike), Phase 2 online
PvPvE on a dedicated server, Phase 3 full Ashfront, Phase 4 a second world.

## The design doc

`docs/DESIGN.md` is the game design every thread builds against: the places,
the watch, the loadout, flight, heavy weapons, banking and sign-out, and
vehicles. `docs/design-gaps.md` lists what is built and what is missing.
Before building a feature, read its section. Where a rule below describes
today's code and the design doc describes a different target (for example
heavy weapons on the watch instead of racks), build toward the doc and
rewrite the rule here in the same PR. Do not settle the doc's open decisions
without Caleb, and update the gap list when a PR closes a row.

## Rules that must not be broken

- `core/` never references a specific world. Anything world-specific goes
  through `WorldDef` (`core/world/world_def.gd`). If a world needs something
  the contract lacks, extend the contract.
- Actors are driven only through `ActorCommand`. Never read `Input` inside
  `Actor`, weapons, or anything else that must run on a server. Input lives in
  `core/player/player_controller.gd`.
- All damage goes through `Combat.deal`. Never call `HealthComponent.apply_damage`
  directly for gameplay damage, or world PvP rules are bypassed.
- Shots and melee originate from the actor (eyes, body), never from the camera.
- The camera never changes view on its own. First/third-person switches only
  when the player presses the toggle (playtest feedback). The one exception:
  getting on a vehicle uses a separate riding view (third-person by default),
  and getting off restores the on-foot view. And in third person, while the
  phone is out, the camera eases in beside the head, square onto the
  phone's screen and tipped with it so its lines read level, to read the
  phone in the hand (`PlayerController._read_phone`, Caleb's call; over the
  shoulder with the Mirror app's mirror up) and eases back after; the view
  stays third person. In both views the eyes drop to the phone while it is
  out (`phone_view_pitch`, less with the mirror up), the view only: `pitch`
  and the aim stay put, and the view zooms in on it like aiming down sights
  until the phone stands `phone_zoom` of the view's height, whatever the
  field of view setting, with all of it kept in frame (`phone_fit_fov`,
  Caleb's pick so the screen reads; not with the mirror up). While a
  view setting's slider is dragged on the phone (`Phone.PREVIEW_KEYS`)
  all of that lets go (`PlayerController.phone_preview`) so the change is
  seen live, and the slider follows the mouse's motion. The Mirror app
  lowers the phone (`Phone.mirror_lowered`, `held`, Caleb's call) so the
  mirror shows the whole kit; a click, right click or Esc brings it up.
  The third-person camera stands over the right shoulder
  (`PlayerController.shoulder`) and, aiming, moves in and further out
  over it (`shoulder_aim`), so the head never sits on the sight line;
  both fade in as it leaves the eyes, so a view switch glides. Walls stop
  it as a swept ball (`camera_radius`, `_third_person_offset`): in at
  once, back out at `wall_return`. Riding frames a bigger vehicle from
  further back (`ride_scale`). Check with
  `visual_check.tscn -- <dir> --camera-only`.
- The head looks where its owner aims (Caleb's call, so others see where
  you look): `Locomotion._look_pose` turns the neck and head onto
  `Actor.get_aim_dir()` from whatever pose the body is in, no further than
  `look_reach` side to side from the chest and `look_up` back or
  `look_down` down from it (measured in the chest's frame, so a body laid
  out in flight lifts its head rather than folding it back), and gives
  way to the phone. View only, the
  same body in both views; first person's eyes simply ride the turned head.
- Bodies are shown between physics ticks (Caleb plays at 144 Hz):
  `ShownMotion` (`core/visual/shown_motion.gd`, added by `Look` to every
  actor and vehicle it dresses, so a server has none) puts its parent
  where it is between its last two ticks for each drawn frame and back
  before the next tick (`SceneTree.physics_frame`), so the simulation
  never sees it; a jump (`JUMP`) is shown at once and a thinned body is
  left alone. The player's own body turns with the mouse every frame
  (`PlayerController.LiveAim`, `ShownMotion.live_yaw`). A check of what
  is drawn reads it late in the frame or inside `skeleton_updated`, not
  after the next tick.
- `Raid` has no camera, HUD, or input code. It must keep working headless.
- The endless warzone. A `Raid` is one running world and it never ends: no
  timer, no exits, no restart. It keeps itself alive (`_tick_bots`,
  `_tick_caches`, `_tick_vehicles`, tuned by `WorldDef`). A player's stay is
  a string of lives: `add_player` starts one and `player_finished` ends it
  with outcome "died" (everything carried drops in a bag) or "left" (a
  finished sign-out: everything carried goes home). After "died" the owner of
  the stash (`Main` solo, `NetSession` online) calls `add_player` again in the
  same raid. Loot reaches the stash mid-life only through a `Depot`
  (`player_banked`). Never add a way to leave that skips `begin_sign_out`:
  a disconnect goes through `remove_player`, which leaves the body standing.
  A player whose connection dropped gets that body back if they sign in
  before its countdown ends: `NetSession._on_peer_connected` finds it
  (`Raid.is_unguarded`) and `Raid.reclaim_player` hands it over, with no
  deploy; the game reconnects on its own (`Main._on_online_disconnected`,
  `reconnect_window`). Anything the server sends a body's owner asks
  `NetSession._owner_peer(actor)`, never a peer id kept from the deploy,
  because a body outlives the connection that deployed it.
- Drop-in protection is `Actor.protected_left`, checked in `Combat.deal`.
- The cold (DESIGN.md "Frostline"): a world with `WorldDef.cold` over 0
  drains each player's `Actor.body_heat` by `WorldDef.cold_at` out in the
  open; warmth fills it again (map markers in group "warmth" with metas
  "radius" and "warmth", and any occupied vehicle's engine,
  `WorldDef.engine_warmth`), and once it is empty the cold hurts through
  `Combat.deal`. Only the authority runs it (`Raid._tick_cold`, which
  respects `Raid.zone_rules`); the owner hears the number
  (`NetSession._body_heat`) and every client the shivering bit
  (`ActorCommand.STATE_CHILLED`, `Actor.shivering`). What it shows is view
  only and the same in both views: the visor's body heat cell and the
  watch card's bar (`Hud.feels_cold`), breath (`ActorSkin._update_breath`,
  never from a cloaked body), the shivering hunch (`Locomotion._shiver_pose`,
  the neck taking the tremor back so the eyes stay steady) and frost on the
  visor glass (`VisorHud._draw_frost`, glass only, the middle kept clear).
- Warm beacons (DESIGN.md "Frostline"): a world with
  `WorldDef.sign_out_at_beacons` lets `begin_sign_out` start only inside a
  "beacon" marker's radius (`Raid.beacon_at`; the portal home is a sign-out,
  so it follows), and the count runs at `Raid._beacon_rate`: nothing while
  its player is out of the ring, faster for each other player powering the
  same beacon (`beacon_join_bonus`, `beacon_join_cap`), so a solo player can
  always get out. It is still the one sign-out, so a fight cancels it and a
  dropped connection counts down where the body stands. Authority only,
  respecting `Raid.zone_rules`; the owner gets the pace with the countdown
  (`NetSession._sign_out`'s rate).
- Tracks (DESIGN.md "Frostline"): with `WorldDef.tracks` the authority's
  `Raid._tick_tracks` lays footprints (alternate feet) and ground vehicles'
  wheel tracks into `Raid.tracks` (a `Tracks` store in cells), only on open
  ground (`ground_height`, never a roof or a floor), and lets them go after
  `track_lifetime`. A mark is laid behind someone, never where they are, so
  it is a trail, not tracking. A client is sent only marks near its player
  (`NetSession._send_tracks`, by the last id sent per cell, within
  `TRACK_RANGE`) and draws them with `TrackView` (view only, added by the
  `Raid` only where `Look` is on). A world's air carrying shots further is
  `WorldDef.shot_carry`, which scales both `Gun.noise_reach` (bots) and
  the shot's sound.
- Thin ice (DESIGN.md "Frostline"): with `WorldDef.thin_ice` the ground
  where `thin_ice_at` says so bears a ground vehicle up to `ice_holds`
  tonnes (its `weight` stat; hovering never counts). Only the authority's
  `Raid._tick_ice` strains it, cracks it (`Raid.ice_cracked`, stages 1 and
  2 a warning, 3 the break), sinks the vehicle through `remove_vehicle`
  (with `ice_keeps_vehicle`, Frostline's, back onto the thrower's or the
  driver's watch as a toy) and opens a hole (`Raid.ice_holes`) that takes the body heat of anyone in
  it, sinks anything driven into it and freezes over after
  `ice_refreeze`. Clients get the cracks and holes from `NetSession`
  (`_ice_crack`, `_ice_holes`) and draw them with `IceView` (view only).
- The defence grid (DESIGN.md "Frostline"): a world's
  `WorldDef.linked_factions` (faction to metres) makes a bot of that
  faction that is hurt and lives call the rest of it within range, through
  `Actor.heard` like a gunshot (`Raid._on_linked_hurt`, authority only, at
  most every `LINK_EVERY`); a blow that kills calls nobody. Everyone near
  sees the call (`Raid.grid_called`, `NetSession._grid_call`, drawn by
  `Raid._show_grid_call` where `Look` is on). A "spawn_boss" marker's meta
  "boss" names a world's own boss kind: the `Raid` sets it on the bot
  before `equip_bot` and `make_warlord` and `NetSession` sends it, so
  `make_warlord` builds the same machine everywhere (Frostline's Engine
  Sentinel). Where `WorldDef.boss_party_scale` is over 0 a boss is made
  for one player and the authority raises its `Actor.toughness` for each
  other player within `boss_party_range` (`Raid._scale_boss`); hits are
  divided by it in `Actor.modify_incoming`.
- The Engine's inside (DESIGN.md "The Engine's inside"): Frostline's
  dungeon is part of the one running world, never an instance (Caleb's
  call), built in the map's drum frame (`engine_frame`, `engine_local`) on
  a levelled bed whose ground drops away under the Shaft (`_engine_ground`,
  kept under the hall's floor). Its parts are drawn merged, one mesh per
  material (`_part`, `_flush_parts`). A dungeon's garrison is "spawn_guard"
  markers: the `Raid` keeps a bot of the marker's faction posted there
  (`_spawn_guards`, `_tick_guards`, `is_guard`), outside the armies like a
  boss, back after `WorldDef.guard_respawn_time`. Inside is sheltered
  (`WorldDef.sheltered_at`): `Weather.strength_at` is 0 there, so nothing
  a storm changes reaches in, and `Raid._track_mark` lays no trail; the
  world's own `cold_at` sets its cold. Squads need room (Caleb's ask): no
  way narrower than 9 m. A solo player must get through: nothing needs two
  people. Its levels sit under the valley floor; the heightfield's
  collision is cut open over the Shaft (`_cut_holes`: NaN heights inside
  `ENGINE_HOLE`, collision only), and the world lowers `WorldDef.void_y`
  (where `Actor` counts a body fallen out) below them. It gets colder by `engine_depth`, and the
  coolant channel (`on_coolant`) is bitter. Its cable lift is a map's
  "lift_stop" pair and "lift_power" switch (`Raid.lifts`, authority
  only): one player holding the switch for `WorldDef.lift_power_time`
  powers it for everyone for `lift_powered_for`, and a player who stands
  `lift_wait` in one stop is set down in the other; clients hear the power
  (`Raid.lift_changed`, `NetSession._lift`) and the map lights it from the
  "lift_power" meta. Its last fight is a keeper (the Heart Warden): a
  "spawn_boss" marker with the meta "keeper" (and "arena", "respawn"),
  run by the authority's `Raid._tick_keeper` from `WorldDef.keeper_*`:
  above `keeper_split` it calls its faction out of the map's "boss_socket"
  markers (outside the armies, `_is_extra`), below it vents the "purge"
  lanes, each warning before it hurts through `Combat.deal`. It carries
  nothing; when it falls (`_keeper_fell`) everyone who hurt it or stood in
  its arena gets a share from its "vault" (`WorldDef.roll_vault`), a
  `LootContainer` only its owner may loot (`reserved`), cleared when it
  wakes again, and markers that wait on it (a "beacon" or "warmth" with
  its kind as meta "keeper", `Raid.waits_on_keeper`) light. Clients get
  the phase (`Raid.keepers`, `NetSession._keeper`, the map's "keepers"
  meta) and the lanes (`Raid.purge_changed`, `NetSession._purge`, drawn
  by the map's `show_purge`). Check by eye with `visual_check.tscn -- <dir> --engine-only`.
- How harsh death is belongs to the world, not to `Raid`. With
  `WorldDef.keep_gear_on_death` a dead player drops only the backpack and the
  equipped gear returns in the result's `kept`. A gentle world pays for that
  with basic loot tables; rare gear stays in the PvP world. With
  `WorldDef.death_drops_scrip` (Ashfront, DESIGN.md "Scrip piles", Caleb's
  call) a death drops no gear: the authority's `Raid._drop_pile` leaves a
  scrip pile (a `LootContainer` with `pile`) worth what a trader pays for
  everything lost (`Economy.sell_price`; a bot's by `bot_pile_share`,
  growing with `war.intensity` by `pile_war_bonus`), plus the carried scrip
  and any bounty, beside one bonus item from the pack (`Raid.pile_bonus`,
  never worn gear) and any artifact, which drops as itself. Any player
  grabs it by running over it (`Raid._tick_piles`); `NetSession` sends a
  pile's scrip and bounty with the container. Visors mark piles near you
  (`VisorHud.nearby_piles`). The insured item is recalled before the pile
  is counted.
- Renown (`core/progression/renown_ledger.gd`) is decided by the `Raid`'s
  ledger and nowhere else. It is kept per owner key (`add_player`'s
  `p_owner`: the account id online), never per name, so it carries across a
  player's lives. Session renown is at stake on death; lifetime renown only
  grows, sets the rank, and travels home in the result's `renown`. The
  public part (rank, streak, bounty, exposed, marked) is copied onto the
  `Actor` for views to read, and news for everyone goes out on
  `Raid.war_feed`. Tune it with the ledger's vars.
- The war director (`core/war/war_director.gd`, `Raid.war`) is the server's
  read on the fighting: war intensity from 0 to 1 and where its centre is.
  Only the server ticks it; clients get the values from `NetSession`. The
  `Raid` passes them to the map as the metas `war_intensity` and
  `war_centre`, and that is all `Look` knows: a map that hands
  `Look.atmosphere` a second, war mood has its sky blend towards it. A world
  scales the meter with `WorldDef.war_scale` (0 keeps it quiet). New stakes
  that follow the war (reinforcements, events, loot) read `Raid.war`.
- Weather (DESIGN.md "Weather: ash storms"): a world with
  `WorldDef.weather_kind` ("ash" Ashfront, "snow" for Frostline's
  whiteouts) has storms crossing its map one at a time, a `Weather` cell
  (`Raid.weather`) on `weather_path`, tuned by `WorldDef.weather_*`. Only
  the authority ticks it; a client is sent the cell
  (`NetSession._weather`) and only carries it on (`Weather.advance`).
  Anything a storm changes asks the cell where it happens, never a flag:
  bot sight (`BotBrain._find_target`, `sight_between`), scan reach
  (`Visor`), how far shots carry (`Gun.shot_carry`), gusts on a flying rig
  (`Actor._take_gusts`, the rig's `gust_mult`, a function of position only
  so it predicts), the cold (`cold_at`), tracks (`weather_wipes_tracks`)
  and army pushes (`Raid._army_target`, `weather_pushes`). Frostline's
  whiteouts (`weather_kind` "snow") add the blizzard: the driven air
  comes in gusts (`WeatherView.gust_now`, view only), a map that offers
  `weather_ridges` gets spindrift off those edges where the storm is
  (`WeatherView._place_drifts`, a kit with "drift"), and bodies on the
  ground lean into the wind (`Locomotion._wind_pose`). Thermal already
  ignores fog, so it sees through a storm. What it looks like is
  `WeatherView` (view only, the same in both views): the wall, the driven
  air round the camera and the wind, and the map's "weather_here" meta,
  which blends `Look.atmosphere`'s storm mood in and lowers the fog floor
  (`Look.weather_cover`, `soften_weather`: gone by about 70 m at the heart,
  Caleb's pick); an ash storm also settles ash on the visor glass
  (`VisorHud._draw_ash`, `ash_settling`: glass only, the middle kept clear). Told in the world only: the visor's heading tape
  ("storm"), the watch map's ring and zone line, the plaza's heat signs.
- The planet kit (DESIGN.md "Planet kit", `core/world/planet/`): a
  `PlanetType` is a kind of planet as data (sky, calm and storm light,
  ground shape and surface, horizon, weather, props) and never names a
  world. A world stands on one with `WorldDef.take_planet(id)` first in
  its `_init`, which sets `WorldDef.planet` and the type's rule defaults
  (`PlanetType.rules`: `cold`, `shot_carry`, `planet_grip`, which
  `surface_grip` falls back to); only those and the ground's shape
  (`PlanetTerrain`, thread safe) reach the simulation, the rest is view
  only through `Planet` and a no-op headless. Each ground layer wears a
  CC0 scan named in `PlanetType.surfaces` (detail only: the recipe's
  colours keep the hue). A type's `smoke` lays low battle smoke over the
  ground (`Planet.GroundSmoke`, a volumetric fog box that follows the
  camera, thicker with the war and in a storm), off with
  `GameSettings.ground_smoke`. Check by eye with `planet_check.tscn --
  <dir> [type ids]`.
- Open ground is a `Terrain` (`core/world/terrain.gd`): a heightfield with
  collision and a mesh that knows nothing about any world. A map on one
  offers `ground_height(x, z)` and the `Raid` stands spawning actors on it
  (`Raid._stand`). A heightfield is a surface, not a solid: anything that
  moves an actor by setting its position (a blink, a teleport) must put the
  feet back on the ground, or the actor falls through. Ashfront's map
  (`worlds/ashfront/map.gd`) works its ground and navigation mesh out once
  per run and shares them between copies (`_shared`), so a new copy is cheap.
- Strongpoints (`core/war/strongpoint.gd`, `Raid.strongpoints`): a map only
  marks where they are (Marker3D nodes in the group "strongpoint", see the
  map contract in `WorldDef`); the `Raid` runs them. A side is a string key
  from `Raid.side_of`: one per bot faction, one per player, or one for all
  players where `WorldDef.players_allied`. Only the authority decides who
  holds a site; clients get it from `NetSession`, including whether a site is
  theirs (`Strongpoint.viewer_holds`), and never see another player's key.
  Send bots somewhere with `BotBrain.post_to`, not a second mechanism.
  An army turning for a new site is a push and is told before it lands
  (`Raid._note_army_target`: a horn and ring at the site and a war feed
  line at most every `PUSH_EVERY`, an arrow on the watch map from
  `Raid.pushes`); clients hear of it through `NetSession._army_push`.
- Where a player lands is the `Raid`'s call. `Raid.drop_choices(owner)` lists
  what is on offer (quiet, a held strongpoint, beside the fighting) and the
  chosen id goes into `add_player`'s `p_drop`, which falls back to a quiet
  drop if the choice is no longer on offer. Online the client only sends the
  id with `NetSession.deploy(drop)`; a client lists its choices from what the
  server already told it (`Strongpoint.viewer_holds`, war intensity).
  An arrival with no choice lands at the spawn furthest from everyone,
  and a fresh player (`WorldDef.fresh_gear_value`) furthest from strong
  ones (`strong_gear_value`, `Raid._safest_spawn`).
  Arriving in a safe zone is just as fixed: a `p_drop` of
  "from:<destination>" ("home", "arena", "world:<id>") lands you just
  outside the plaza doorway that leads there (`Raid.arrival_point`), the
  same spot every time, and `main.gd` sends it (`_arrive_from`) whenever you
  come back that way. A plaza gate deploys you straight into its world
  (`_gate_deploy`); the world's lobby is only where a refused deploy waits.
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
- World heat: `Raid.status()` is what a world shows of itself from outside
  (players, war level, top bounty, the event running) and never says where
  anyone is. The one "who" it carries is `wanted` (Caleb's call, for the
  most-wanted board): up to `Raid.WANTED_SHOWN` players with a bounty or the
  Marked, by name, clan tag and bounty only, checked again on the client
  (`NetSession._clean_wanted`). The safe zone's `NetSession` gathers it from the other
  sessions in the process and sends it to everyone standing there
  (`NetSession.world_status`); `PlazaView` writes it on a sign over each
  world doorway (`heat_signs`) and the wanted on the most-wanted board
  (`wanted_text`, the map's "wanted_board" label). Anything else that
  advertises a world reads `world_status`, not a second channel.
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
- A player's bounty pays its killer in scrip (`Economy.bounty_scrip`, one
  for one, Caleb's call) into the life's carried scrip, so it is at stake
  until banked or carried out, like the kill's own pay. Where deaths drop
  scrip piles it goes into the dead player's pile instead (a bounty pile,
  `LootContainer.bounty`), for whoever grabs it.
- Shelling (DESIGN.md "Shelling", Caleb's call): a world with
  `WorldDef.shelling` over 0 has the war's artillery, `Raid.shelling`
  (`core/war/shelling.gd`), run by the authority only and where
  `Raid.zone_rules` hold. A salvo is a line of shells near an army soldier
  near `war.centre`, sooner the hotter the war; each spot is marked first
  (`Raid.shells_called`, sent to every client by `NetSession._shells`), a
  `Shelling.Marker` in `Gun.live_rounds` so bots run from it, then lands
  through `Gun.splash` with no source (kind "shell", only that raid's
  actors). Never near a gate outpost, a player spawn or a protected
  arrival (`Shelling.clear`). What it looks and sounds like is `ShellView`
  (view only, added by the `Raid` only where `Look` is on), timed from what
  it was told; the jolt is `PlayerController.feel_blast`. Check by eye with
  `visual_check.tscn -- <dir> --shells-only` (with `--fixed-fps 60`).
- The scenery army (DESIGN.md "The scenery army", Caleb's call): Ashfront's
  far fights are view only (`worlds/ashfront/battle.gd`, added by the map's
  `make_battle` only where `Look` is on): no collision, no `Combat.deal`,
  nothing sent online, and never nearer a player or the camera than
  `keep_off`, so up close every soldier is a real bot. Its soldiers are far
  copies of the armies' own riflemen (the world's `dress_extra`), baked
  once per run in a world of their own (`_Baker`) into one mesh per pose
  and drawn one MultiMesh per pose (`extras.gdshader`, dithered fade). A
  round from the local player's gun or a shell drops one on that screen
  only. Check by eye with `visual_check.tscn -- <dir> --battle-only` (with
  `--fixed-fps 60`).
- World events (`Raid.event`, `start_event`, `end_event`): one at a time, on
  a timer the war speeds up, tuned by `WorldDef.event_interval`,
  `event_lifetime` and `warlord_escort`. A supply pod is an ordinary
  `LootContainer`; a warlord is an ordinary bot passed through
  `WorldDef.make_warlord` (clients build the same one from `Raid.warlords`,
  so keep that hook free of randomness). Event bots are extra and are never
  respawned. Loot that should follow the war comes from
  `WorldDef.roll_war_loot(source, rng, intensity)`, not `roll_loot`.
- Bot armies. A "spawn_bot" marker may name a faction (meta "faction");
  the `Raid` sets it on the bot before `WorldDef.equip_bot`, and `NetSession`
  sends it so a client builds the same soldier. Where
  `WorldDef.bots_contest_sites` is on, `Raid._tick_orders` has each
  faction's commander (`WarCommander`, DESIGN.md "Army commanders") give its
  orders through `BotBrain.post_to`: a garrison on every site it holds and
  fireteams (`BotBrain.team`) spread over the objectives worth most, never
  all one way and never a player. Reinforcements follow
  the war: `Raid.bot_target()` is `bot_count` plus a share of
  `WorldDef.war_reinforcements` by `war.intensity`, new bots join the faction
  with the fewest alive, and extra bots are not replaced once it cools.
  A world caps rare kinds with `WorldDef.bot_allowed` (authority only: the
  `Raid` rolls a turned-away bot again from a new seed, so clients only hear
  of the kept seed). Ashfront's kinds (meta "kind": soldier, heavy, exo,
  walker; DESIGN.md "Heavy units") come from the seed in `equip_bot`; a big
  body is `Actor.set_stand_height` (capsule, hit tests and eyes follow
  `body_height()`), a weak spot `Actor.rear_damage_mult`, and a gun that
  must hold a lock first `BotBrain.lock_time` (meta "lock_time"), whose
  tracking beam every view draws from the held aim (`ActorSkin._update_beam`). Bots
  killing bots only simmer the meter (`WarDirector.report_battle`, capped at
  `battle_ceiling`); only players take it higher. World-event bots
  (`Raid._event_bots`) are outside all of this, and so are rival raiders
  (`Raid.raiders`, `WorldDef.raider_count`, DESIGN.md "Rival raiders"):
  bots that play like players, each a side of its own ("raider:<name>"),
  wearing a real kit from `WorldDef.raider_kit` put on with `Loadout.equip`
  (never `equip_bot`). A client builds one from that kit (`spawn_bot`'s
  `kit`), not from the seed. The `Raid` sends them on errands
  (`BotBrain.go_to`) and signs them out; armies never order them.
  Group fights take turns (Caleb's call, DESIGN.md "Group fights"): only
  `BotBrain.attack_slots` army bots shoot or swing at one person at a time
  (`BotBrain.RING_SLOTS`: 1 outer, 2 middle, 3 core; `take_slot`, keyed by
  the target, held `token_hold` and passed on after `token_beat`). A bot
  without a slot keeps its gun on the target and holds fire, crouched in
  cover from the target's eyes (`_find_cover`, a few ray probes every
  1.5 s) or, past the outer ring, working round a flank. Return fire
  (`return_fire_time`) and anything inside `point_blank` skip the queue,
  and bots fighting bots are never rationed (`BotBrain.is_person`). Spotting
  takes longer far off and against a crouch (`notice_mult`), and the gun
  comes up halfway through the reaction with a bark heard nearby
  (`ActorSkin._update_bark`) before the first shot. Measure with the duel
  bench's `--group 2,3,5` (and `--slots off` to compare).
  Bots react only to what they sense (DESIGN.md "Enemy senses and squads",
  Caleb's "everyone converges on me"): sight, a person's noise (shots,
  `Combat.noise`, told nearest first; footsteps, jets and engines,
  `BotBrain.noise_of`), a hit and a squadmate's callout (`_call_out`, a
  snapshot when the spotter raises its gun). What they learn is a place,
  never live tracking: a lost contact is searched for (`_lost`) and let go.
  Only a few act on it, through `SquadBoard` claims (static, with an
  expiry, like the slots): `noise_lookers` go to look at one person's
  noise, `RING_HUNTERS` army bots may leave their ground to hunt one person
  (`_may_close`), one bot flanks them, and no two take the same cover. A
  chase never goes past `leash` beyond a bot's post. A new way to send a bot
  after a person goes through `_sensed`, never by setting its state.
  Cover is chosen by the attacker's angle (`_find_cover`), bots peek and
  move up cover to cover (`_advance`), the slot holder pins a person who
  ducks (`_suppress`), a badly hurt soldier falls back (`_fall_back`), and
  a bot runs from a round about to burst (`Gun.live_rounds`, `_think_danger`).
  Melee bots fight like people (DESIGN.md "Melee bots"): held heavies,
  feints (a charge that switches side and lets go as a light) and
  dash-strikes by ring (`BotBrain.RING_HEAVY`, `RING_FEINT`, `RING_DASH`),
  and a strike into any opening; they press the same buttons a player
  does (`_start_attack`, `_carry_charge`). A blade in reach beats a rifle
  (Caleb's call): an army gunner cut by a blade flinches
  (`BotBrain.melee_flinch`, its aim and trigger only, never a player's)
  and gives ground from one (`blade_backoff`). Measure with the duel
  bench's `--melee <blade id>`.
- The life log (DESIGN.md "Challenge and balance data"): the authority's
  `Raid` records every finished life (`Raid._log_life`, `LifeLog`): where,
  how, what killed them and how many bots were after them, to JSON lines
  under `LifeLog.directory` (`main.gd` sets it; empty writes nothing, as in
  the tests). It is read only by `tests/life_report.tscn`, never in play.
  A new thing worth tuning by is a new field there, not a second log.
- Big battles must stay affordable; measure with
  `godot --headless --path . res://tests/battle_bench.tscn -- --bots 150 --players 32`
  (processor time a tick, against the 16.7 ms budget). Three things keep
  them so. Bots nobody is near are thinned: `Raid._tick_detail` calls
  `Actor.thin`, and the actor and its brain then take one longer step every
  few ticks, so anything that drives an actor tick by tick must ask
  `Actor.ticks_now()` first, and a press set from outside can be missed
  unless the actor is at `thin(1)`. A bot asks for a new path only when its
  goal has moved or its path ran out (`BotBrain._move_toward`); never set
  `NavigationAgent3D.target_position` on a timer. Interest: `NetSession`
  sends a player every state update only for actors within `NEAR_RANGE`,
  the rest in turn (`detail_tier`, `detail_due`), and keeps presses per tier
  so a far viewer still gets them; a client thins far actors the same way.
  A new per-tick cost that grows with the number of actors (a scan of the
  "actors" group, something sent to every peer) needs the same treatment.
  A world sets how many players it takes with `WorldDef.max_players`.
  The player's frame rate is measured with
  `godot --path . res://tests/frame_bench.tscn -- --mode solo --bots 120`
  (or `--mode online`, which starts a server and drops in beside the
  fighting; `--probe` shows what the draw calls go to). To compare two
  builds, run it headless with `--fixed-fps 60 --look --seed 7`: the same
  battle each time, with the bodies dressed and posed. What keeps the
  frame affordable, all view only: a far body is posed every few frames
  (`ActorSkin.detail_step`, scaled by the camera's zoom, which steps its
  animation and skeleton by hand while it is far), a body out of frame
  every `offscreen_step` frames (posed at once when it comes into view),
  its arm placed only with its poses (`WeaponArm.step`), and its weapons,
  helmet and plates cast no shadow; a body's sun shadow is one
  shadow-only copy of its showing parts on the same skeleton
  (`ActorSkin._update_shadow_body`, `Look.shadow_body`), never a draw per
  part and surface; worn models built of still pieces (a helmet, plates,
  exo parts, iron sights) are merged one mesh per material as they are
  hung (`Look.merge_pieces`), so a new worn model built from boxes costs a
  few draws, and a piece that must move on its own goes under a child
  node, which is left alone; open ground is drawn in tiles (`Terrain.tile_cells`) so only the
  ones in view and in shadow range are drawn; small map props fade out
  with distance by their size (`Look._limit_draw_distance`); a parked
  vehicle nobody rides rests instead of moving every tick. Every ENet
  packet is compressed (`NetSession.COMPRESSION`); changing it needs a new
  `PROTOCOL`.
- Mastery pays for using gear, never for leaving alive, or signing out over
  and over would farm it.
- Blocking and parrying happen in `Weapon.modify_incoming`, which `Combat.deal`
  calls for every hit. Every melee attack keeps a visible windup so it can be parried.
- Melee types differ only by item stats on the one `MeleeWeapon` class:
  `backstab_mult` (knife), `guard_crush` (axe, carried on
  `DamageInfo.guard_mult`), `vertical_reach`, `close_range`/`close_mult` and
  `heavy_stagger` (spear). Their defaults change nothing. Add a melee type as
  data plus a `Look.MELEE_MODELS` entry, not as a new class. Every melee item
  carries exactly one hold tag, "one_handed" or "two_handed"
  (`MeleeWeapon.is_two_handed_id`): it sets the walk speed with it in hand,
  makes a two-hander's heavies stagger and break armor, and is what
  `Look.is_two_handed` (the one place views ask) answers for the grip.
  Melee is made to answer guns (DESIGN.md "Melee against guns"): blades go
  past armor (`DamageInfo.armor_pierce`), a heavy started sprinting is a
  dash-strike (`dash_range`), a light while moving back at a foe behind is a
  back strike, and a fresh guard deflects small-arms rounds for
  `deflect_window`, rearming after `guard_rearm`; a gun's round carries its
  `DamageInfo.weapon_id` and `undeflectable_tags` (marksman, power) go
  through any guard. Noise is `Combat.noise`, which only guns call (a person's
  shot, at most every `Gun.noise_every`): patrolling bots hear it through
  `Actor.heard`. Never make a blade call it; melee kills are silent.
  Each weapon fights its own way (Caleb's call: every attack and guard
  matches how the weapon is really used; view only). Its `swing_style`
  ("slash", "thrust", "chop", "cut"), `heavy_style`, hold and hands pick a
  technique (`ActionPose.technique`): a table in `ActionPose.techniques` of
  keyed swings per side (and a heavy from the middle) and a guard per side.
  Each swing is three keys, windup, contact and follow-through, each the
  weapon hand and the way the blade goes, so the blade turns through the
  cut edge first (`technique_blade`, `keyed_reach`) and every strike meets
  the foe in front of the chest where the eyes see it; each guard holds the
  weapon across its side in front of the body. The sword cuts diagonally
  and thrusts for its heavy, the axe chops from high behind the shoulder,
  the knife slashes short in a forward grip and stabs for its heavy, the
  hammer is hauled over in both hands, the spear thrusts from the hip, and
  the katana keeps its kenjutsu cuts (kesa-giri, gyaku-kesa, shomen and a
  tsuki, both hands on the handle; view only, so the katana keeps its
  one-handed stats). `swing_scale` draws a small weapon's keys in toward
  the middle (`swing_centre`). A new melee weapon picks a style, or a new
  technique gets a table; `view_match_tests.gd` (`_check_techniques`)
  checks that every weapon's strikes are in view and its guards show their
  side. `ActionPose.windup_reach`/`follow_reach` and
  `MeleeWeapon._animate` read `style_now()`. The shown swing starts
  `SWING_LEAD` before the strike and speeds into it, half its arc at the
  hit, then eases out (`MeleeWeapon.swing_arc`; both views read it); a
  windup keeps coiling back (`windup_coil`); two-handers swing slower and
  turn the body more. A new melee weapon picks a style; check it by eye with
  `visual_check.tscn -- <dir> --swing-only` (run with `--fixed-fps 60`),
  which films each move frame by frame, or quicker, one weapon's stance,
  swings and guards from the front, the side and the eyes at once with
  `--technique-only <item id>`. Every melee
  model is dressed as tech by `Look._tech_melee` (`assets/shaders/melee.gdshader`):
  bare metal becomes alloy with an energy edge in the weapon's rarity color,
  wood and wraps black polymer with glowing seams. The edge runs across the
  length the mesh actually lies along (`Look.blade_axes`, `_up_axis`; a
  pack mesh may lie along Z), the flat of a blade stays alloy, and a hammer
  has no edge. Guns wear the same house finish (the weapon pass, to sit with
  the sci-fi armor, helmets and vehicles): `Look._dress_gun` turns a pack
  model's dark parts graphite (`GUN_FRAME`), its light parts ceramic
  (`GUN_SHELL`; worn tan on the scrap rifle) and its warm parts the gun's
  `GUN_GLOW` colour, lit softly, never a whole part aglow; each gun then
  wears its own kit (`Look._gun_kit`: coils, cells, a drum, a shell carrier),
  under a "Kit" node that `_measure_mounts` skips, so a kit never moves a
  grip, a sight or the muzzle. Power weapons are built in the same finish
  (`_power_model`). Compare every weapon side on with
  `visual_check.tscn -- <dir> --arsenal-only` (`ARSENAL_IDS` picks rows). The scrap kit's blade
  (`starter`) is a sword made from scrap (Caleb's call): `Look._scrap_bits`
  welds crooked patch plates and rivets on the blade, winds wire round the
  grip and threads a nut on for a pommel, and it runs dim and worn
  (`scrap_energy`, `scrap_wear`). A holstered blade is worn
  folded away (the last field of its `MELEE_MODELS` entry: "blade" draws the
  blade into the hilt, "telescope" slides a spear shaft into itself) and
  slides out once drawn (`Look.set_extend`, timed by `ActorSkin._update_fold`).
  Folding is done in the shader's vertex step, so it is view-only.
- Melee attacks share one button (Caleb's call): a tap of `ActorCommand.primary`
  is a light attack, released before `MeleeWeapon.hold_time`; holding past it
  starts the heavy (a dive slam in the air) with its full visible windup. A bare
  `primary_pressed` with no hold is a light (how bots swing), and
  `tertiary_pressed` still asks for a heavy outright, but no key binds it.
  A press made while the blade is busy is kept (`press_buffer`) and plays
  once it is free, and the time a tap was held counts toward its windup (down
  to `light_windup_floor`). A heavy lunges at the foe in front and stops at
  striking distance (`heavy_lunge` is its speed through the windup); in the
  air, at an airborne foe in the aim cone, it is the magnetic air-lunge
  (`air_lunge_range`) instead of a slam. Lunges are held by
  `MeleeWeapon._carry_lunge` from the command and the foe's position as the
  attacker saw it (`Combat.positions_seen_by`), so they predict online.
  A strike that reaches someone emits `MeleeWeapon.contact` on every machine
  it is simulated on, with a local guess at the guard; the attacker's view
  answers that (sound, `PlayerController.kick_view`, a hitstop of the blade's
  pose) at once, and the server's `hit_confirmed` only drives the hit marker.
- Melee is timing, not sides (Caleb's call, DESIGN.md "Melee duels"): the
  blade picks its own sides (`MeleeWeapon.next_stance`: a light combo runs
  right, left, over the top; a heavy comes over the top, or from the side
  straight off a light), and a guard turns to meet whatever comes from the
  front (`_guard_toward`, `guard_dir` set by the hit), so nothing matches a
  side and `ActorCommand.stance` is unused. A swing still goes toward its
  stance (`attack_dir` is `swing_from(stance)`), and windup and guard poses
  must show their side; `threat_dir()` is what a defender reads. What a
  guard does is timing: a parry in `parry_window`, a timed block in
  `timed_window` for `timed_block_cost` of the stamina, and a guard held
  longer drains (`_drain_held_guard`); a guard raised straight after one
  that met nothing is not timed (`guard_rearm`), one that met its hit in
  time rearms at once (`_guard_paid`). A blow landing on a windup
  interrupts it (`interrupt_stagger`); strikes landing together clash
  (`clashes_with`); the kick (`ActorCommand.kick_pressed`, V,
  `MeleeWeapon.kick`) goes through a guard and breaks it open but loses to
  a swing; aim early in a heavy's windup feints it (`_try_feint`). The
  dodge is the dash (Alt, `Actor.dodge_style`: a roll with no rig, the
  rig's own dodge otherwise): swings pass through it (`evade_left`), rounds
  do not, and the weapon waits out `dodge_recover`. What a guarded strike,
  a reel and the feet look like is view only: `ActionPose.bind` (both
  blades meet at `ActorSkin.bind_point`), `reel`, `footwork`; check with
  `visual_check.tscn -- <dir> --bind-only`.
- The game updates itself (`core/update/updater.gd`, the `Updater`
  autoload, second after `Boot` and, like it, free of project classes). The
  Windows client keeps its pack beside the exe (`embed_pck` off); the
  release workflow stamps each build's number into `ares/build/number` and
  publishes the pack and `update.json` (build, engine, size, SHA-256) on the
  rolling "latest" release. An exported, stamped game reads it at launch,
  downloads a newer pack to `user://updates`, checks it and swaps it in
  beside the exe (on Windows a batch script does it once the game has
  closed, since an open pack cannot be replaced; release builds refuse
  `--main-pack`), then restarts. It never runs in the editor, a test, a
  server or headless, and anything that changes the engine or a native
  library needs a fresh install. Release builds also refuse `--path`, so a
  game starts its own server with `Main.server_process_args`, which leaves
  it out of an exported game. Its state shows on the start screen's
  corner and the phone's Servers app (online too, with a restart that
  leaves the server first, `Main._restart_for_update`). An update waiting
  on the player (`Phone.update_waiting`: downloaded, or needing a fresh
  install) is told (Caleb's feedback): the phone buzzes with a pop-up and
  the Servers app wears a badge, held back out in a world, the arena or a
  race (`Phone.update_hold`) until the player is home or in the plaza,
  and told again each time they get home (`Phone.remind_update`). The installer
  (`.github/installer/ProjectAres.nsi`, NSIS, built by the same workflow as
  `ProjectAres-Setup.exe`) installs per user into
  `%LOCALAPPDATA%\Programs\Project Ares`, never Program Files, so the game
  can write its own pack, and adds desktop and Start menu shortcuts. The
  logo is a placeholder in `assets/branding` (the window, exe and installer
  icon and the boot splash), made by its `make_logo.py`.
- Sound and visual effects (`Sfx`, `Fx`) must stay no-ops on a headless server.
- Art lives in the `Look` autoload (`core/visual/`), not in gameplay scripts.
  Gameplay scripts keep building plain greybox shapes; `Look` dresses them
  when they enter the tree and does nothing when headless. It never adds
  collision or changes the simulation, and it never names a world: worlds
  pick surfaces, an atmosphere and bot skins (`set_meta("look", ...)`) from
  its generic kits. Decoration in a map uses its own RNG so it cannot shift
  the gameplay layout.
- Legs follow the actor's velocity, never its input (`core/visual/locomotion.gd`):
  walk and run clips are measured from their feet and played at actual speed
  over clip speed, the clip nearest the direction of travel is picked, and the
  lower body turns the rest of the way while the spine keeps the chest on the
  aim. Remote players work the same way from their replicated velocity.
  Past a relaxed cadence a run lengthens its stride (feet stretched about
  their average spot, legs solved to reach them) rather than only spinning
  faster: that is the sprint. A slide (`Actor.slide_left`, `Actor.slide_low`)
  is simulated from `ActorCommand.slide` like a dash, so it predicts and
  replicates; the skin bends the model into a slide pose from `slide_low`.
  The crouch key (C) slides from a sprint and otherwise toggles the crouch
  (`PlayerController.crouch_key`), sent as the held `ActorCommand.crouch` so
  it predicts and every view sees it. `Actor.crouched` follows it but stays
  down while `room_to_stand` finds no headroom (a slide that ends under
  something low ends crouched); crouched you walk at `crouch_speed`, the
  eyes drop `crouch_eye_drop`, guns spread less (`aim_steadiness`) and bots
  sense you behind them only closer in (`crouch_sense_mult`). The body is
  `Actor.body_height()` tall (`CROUCH_HEIGHT` crouched or sliding): the
  collision capsule, `Combat.capsule_entry`, headshots and anything aiming
  at a chest use it, so low cover hides a crouched body. The skin sinks the
  model onto bent knees from `Actor.crouch` (`Locomotion._crouch_pose`, the
  landing squat's `_sink`, heels up onto the balls of the feet, a short step,
  the chest leant in) under the stand or walk, so gun carries, ADS and
  melee holds come down with the chest, in both views.
  Standing still is a relaxed stand (`idle`); a gun is held low (`idle_gun`)
  over the relaxed stand's legs and raised (`aim_gun`) only while shooting
  or aiming and briefly after.
  On the move a gun is carried, not pointed (Caleb's running pass, after
  real carries and well-liked shooters): out of a fight (`ActorSkin.in_fight`:
  shooting, aiming or reloading now, or within `aim_hold`) it sits at a
  compressed low ready at a jog, strafe or slide, both hands on a rifle,
  goes across the chest at port in a sprint (a pistol tucked muzzle down in
  one hand while the other arm pumps), bobs with the stride and lags on a
  spring as the body speeds up, stops or turns (`ActionPose.carry`,
  `sprint`, `carry_point`, `carry_turn`, `sway`; placed from the chest by
  `WeaponArm._reach_carry` and `carry_frame`), and the legs run the plain
  run. The arms take up the run's bounce (playtest feedback: the gun
  bobbed all over the first-person view): the carry moves with the eyes
  as they are steadied (`ActorSkin.eye_steadying`, `carry_steady`) and
  follows the chest's rocking with a lag, so every carry pose must keep
  the wrist inside the arm's reach through a stride, or the gun bounces
  with the shoulder; `camera_tests.gd` (`_check_steady_on_the_run`)
  measures it. In a fight the run-and-shoot arms come back and the gun points where
  it shoots; a shot, aim or reload takes it out of the carry at once
  (`carry_out_rate`). A tap of aim is not a fight: let go without a shot,
  the gun goes back to its carry after `ActorSkin.aim_release_hold`, not
  `aim_hold` (Caleb's in-between wobble). Held up at the hip on the move,
  the gun rides the same steadied frame as the carry at the clip's wrist
  averaged over a stride, turned to the aim (`WeaponArm._hold_at_hip`), so
  the clip's arm swing never reaches it; `_check_hip_after_aim_tap`
  measures it. All of it is read from velocity and the command, so
  remote players match, and it is the same body in both views.
  Check leg changes by eye: `visual_check.tscn -- <dir> --gait-only`, the
  stand with `--idle-only`, and a rifle and a pistol carried on the move
  with `--carry-only`.
  Holstered weapons are worn, not hidden (`ActorSkin.stow_place`): a primary
  gun or two-handed weapon slung across the back, outside a worn back rig
  (on a jetpack or wing pack, clamped to the flush mag-lock rail on the
  pack's back corner instead, gun right and long blade left, turned back
  behind the shoulder blade so it never covers the arm (Caleb's call:
  mounts smooth and out of the way), leaning out in a slight V, so the
  heat gauge on its back stays in view; a wing pack's rails stand on
  fairings behind its wing slots: the rig model's "MountL/R" markers, and
  the skin rests the weapon's near side on the rail; an empty rail has
  nothing sticking out), a
  sidearm muzzle down on the right hip, and a one-handed blade on the left
  hip. These are view-only copies; the weapon's own node stays on the hand.
  A switch is shown as the hand putting one away and drawing the next
  (`ActorSkin._update_switch`, reaching through `WeaponArm.override_point`),
  but only the view waits: the actor switches at once. The holster key (Z)
  sends `switch_weapon = ActorCommand.HOLSTER` and draws `Actor.last_drawn`
  again; it is an index, never a toggle, so it replicates safely. Check with
  `--holster-only`.
- First and third person differ only in where the camera is (Caleb's rule).
  Third person never shows more than the eyes see (Caleb's call): out in a
  world where gear is at stake, a hostile body the eyes have no line to
  (head, chest, hips or either side) fades out of the third-person view
  (`PlayerController.PeekFade`, `peek_rule_applies`), so peeking round a
  corner from over the shoulder gives nothing first person lacks. View only;
  squadmates and the dead are never faded.
  Both look at the one real body, posed by the same code and holding the
  same weapon in the same hand: first person puts the camera at the eyes
  (`ActorSkin.eye_point`, pulled back level by `GameSettings.eye_pullback`,
  which eases off as the view tips down while the eyes lean ahead,
  `PlayerController.look_down_lean`, so looking down sees the chest, never
  the shoulders from behind)
  from the head as drawn, in every pose (`ActorSkin._head_local`, the
  posed head; its steadying trails it by at most `eye_steady_reach`, the
  controller's easing by at most `eye_lag_reach`, and `head_posed` carries
  it on with the head posed after the camera was placed; no landing dip on
  top of the body's own squat), so the eyes never trail into the neck or
  the armor's collar (`camera_tests.gd`, `_check_eyes_stay_in_the_head`),
  and leaves out only the head (`ActorSkin.hide_head` moves it and what is
  worn on it to `Mirror.HEAD_LAYER`, which that camera culls; shadows and
  a mirror still see it). A station's own view (the bench's, a
  `WorldScreen`'s) stands about where the head is, so it leaves the head
  out the same way in either view (`PlayerController.screen_view_up`, its
  camera's `SCREEN_VIEW` meta; Caleb's feedback: it blocked the bench). Never build a first-person-only copy of the arms,
  a weapon or a prop, and never move anything in front of the camera for
  first person. Aiming down sights is a body animation, the same in both
  views (`ActionPose.ads`, eased by `ads_rate`): `WeaponArm._reach_sight`
  reaches the gun hand so the sight (`ActionPose.sight_local`: an optic's
  "Sight" marker, else the model's "IronSight", else the top of the model;
  a gun with no optic wears iron sights there, a rear notch and a lit
  front post, `Look._iron_sights`) sits on the line out of the model's eyes, `ActionPose.relief_for` in front
  of them (a sidearm out at arm's length, a long gun shouldered), and the
  off hand takes the "ForeGrip" (or cups a sidearm), sliding back along
  the gun where the arm cannot reach. A sight out of the gun arm's reach
  comes back toward the eye (`ActionPose.relief_now`, which first person
  follows). Both wrists turn as the `aim_gun` clip holds the gun, turned
  with the aim (`WeaponArm._turn_to_aim`), so neither twists round it, and
  the shoulders take a stance (`ActionPose.ads_stance`: a long gun bladed,
  a sidearm squared up). Bone poses are only final inside the skeleton's
  `skeleton_updated`; a check of a posed bone reads it there. Guns tagged in
  `ads_hip_tags` (the minigun) stay at the hip. First person then only
  settles the camera on the sight line as it comes up; never move the gun
  to the camera. Aimed on the move the body holds the gun still rather
  than the view being steadied (playtest feedback: the sight bounced):
  you walk at `Gun.ads_move_mult` and never sprint, the spine, shoulders
  and head follow the gait with a lag (`Locomotion.aim_still_time`), and the
  eyes the gun is brought to are steadied (`ActorSkin.eye_steady`, fully
  while aimed); measured in `ads_tests.gd` (`_check_on_the_move`). A view that follows the gun reads it where it was drawn
  (`ActionPose.sight_shown`, the hand's "shown_local" meta), never the hand
  node a physics tick parked (that was the range's ADS stutter). A weapon
  that takes no input on a tick stops aiming (`Weapon.drop_aim`). Each
  actor has one `ActionPose`
  (`core/visual/action_pose.gd`, a view-only child made by `ActionPose.of`):
  the melee reach and shoulder turn, the reload motion (brought in to the
  middle, where the eyes see it, `reload_reach`), the low ready, the
  drawing back of a held heavy and the easing back of a recovering blade,
  the gun brought up to the eye,
  the watch raise (from `ActorCommand.watch_up`), the phone hold
  (`ActionPose.phone`, from `ActorCommand.phone`, which `Locomotion` poses
  the body from) and the inspect key's look over (`ActionPose.inspect`,
  from the held flag `ActorCommand.inspect`: the wrist comes to
  `inspect_point` and turns the item through `INSPECT_TURNS`, timed by each
  view from when it saw the flag; check with `visual_check.tscn -- <dir>
  --inspect-only`). `WeaponArm` and `ActorSkin` pose the model from it; a new
  hand or weapon animation goes there. Weapons are held, not floated
  (Caleb's call): the hand carries them, each by its own grip (Caleb's
  call), found on the model rather than tuned by hand. `Look._measure_hold`
  reads a gun's side outline for its trigger guard, the pistol grip behind
  it (its rake) and the fore end ("Grip", "Trigger", "ForeGrip" markers;
  a power weapon marks its grip in `_power_grip`); the fist's middle closes
  on the grip level with the trigger and the wrist bends to its rake
  (`WeaponArm._held_wrist`, `_bend_to_grip`). Whenever a gun is raised
  (aiming or shooting, not held low or reloading) the off hand supports it
  as in a real FPS hold (Caleb's references): under a long gun's fore end
  palm up, fingers up its side ("ForeGrip", found just under the fore end,
  `Look.FORE_CUP`), and wrapped round the shooting hand on a sidearm
  (`ActionPose.ads_cup`), thumb forward with the wrist in line with the
  forearm, the pistol held out in both hands; its wrist is turned by
  `WeaponArm._support_turn`.
  `Look._fit_hands` finds a melee handle (up to its guard or
  head), puts it through the fist and gives a two-handed weapon
  (`Look.is_two_handed`) its off hand's place: a hand below on a short
  handle, up the haft of a long one, which rests carried across the body
  (`WeaponArm.carry_point`). Check by eye with
  `visual_check.tscn -- <dir> --hands-only`. A one-handed weapon at rest is
  held ready, not left to the idle clip (Caleb's references): the arm
  reaches the hand to the lower right of the view and the weapon stands in
  the fist the way its hold says (`ActionPose.ready_holds`, picked by the
  last field of `Look.MELEE_MODELS`): a straight sword with the elbow bent,
  the fist by the hip and the point up toward a foe's face, a katana
  leaning in with the off hand under the weapon hand, a knife lying flat in
  a reverse grip. An empty off hand stays up as a guard
  (`ActionPose.off_guard`) through every swing and guard, and on the ground
  the legs take a fighting stance while a blade is out (`Locomotion.fight`:
  knees bent, feet staggered standing still). Attacks start from the
  hold and ease back into it (`ActionPose.held_ready`). A blade lies along the closed fist
  and a gun held low turns with the wrist (`WeaponArm`); swings turn the
  arm through the technique's keys (`ActionPose.keyed_reach`, `elbow_pole`). Shots
  are judged from the eyes but drawn from the gun's "Muzzle" marker as it
  is shown (`Gun.muzzle_point`). Compare by eye with
  `visual_check.tscn -- <dir> --views-only [rows]` (`VIEW_MELEE=<item id>`
  picks the melee weapon), which also saves each shot full size under
  `views/`.
- Picture quality is settings and light shaders, never new art: edge
  smoothing is `GameSettings.anti_aliasing` (SMAA by default, MSAA on top
  as an option; never TAA, it smears motion), set on the main view by
  `GameSettings.apply_graphics`; world textures keep mipmaps (a test checks
  their `.import` files) and are filtered 16x. Far shapes out in a world get
  a thin outline from the depth buffer (`Look.edge_ink`,
  `assets/shaders/edge_ink.gdshader`, a quad the shader stretches over the
  camera, the same in both views), which MSAA leaves no depth for, so it is
  off in those modes (`GameSettings.ink_shown`). Both are on the phone's
  Settings, View tab. Compare by eye with `visual_check.tscn -- <dir>
  --graphics-only [--aa 0-4] [--ink 0|1]` and measure with the frame bench's
  `--aa` and `--ink`. For a slower graphics card the same tab offers
  Shadows (`GameSettings.SHADOWS`: High is the world as made), Render
  scale (FSR 1) and Ambient occlusion; a world's sun and atmosphere take
  them through `GameSettings.fit_sun(sun, reach)` and `fit_atmosphere`,
  so set a sun's shadow reach only through `fit_sun`.
- People are built from parts (`core/visual/human.gd`): an "appearance" names
  a build, four parts and colours. It is cosmetic only and never trusted:
  always pass one through `Look.clean_appearance` / `Look.set_appearance`,
  which is safe on a headless server. The pack meshes are worn as
  `Human.shaped` copies (made once per mesh, view only): smooth shading
  where faces meet gently, the head drawn in to `HEAD_SCALE` about its
  bone (the bone, the eyes and anything worn on it stay put), and each
  vertex's rest place and hand share in CUSTOM0, so `character.gdshader`
  draws patterns that stay on the body as it moves. Never change a
  vertex count, bone or weight there: a body must pose and cost the same.
  Under an armor frame a person wears a fitted undersuit (Caleb's
  tactical pass): the body, legs and boots of their build's
  `ActorSkin.SUIT_OUTFITS` go on in place of their clothes
  (`_wear_undersuit`, view only, the clothes given back when the frame
  comes off, the appearance untouched), and the shader draws every
  surface below the head as the suit in the frame's "suit" colour, with
  gloves and a cuff lit in its accent (`suit`, `suit_color`,
  `suit_trim`; `Human.surface_kind` says which surfaces it covers). Check
  by eye with `body_check.tscn -- <dir> [--suit] [--before]`.
  Online it travels in the spawn data as
  `data["look"]`; the server keeps what each signed-in player sent
  (`NetSession.look_for_peer`). `Raid` and gameplay never read it.
  A look changed while in a world (the phone's Mirror app) is checked by the
  server in `_request_look` and passed to everyone there with `_look_changed`.
  The mirror itself (`core/visual/mirror.gd`) is a client-side view: no
  collision, and nothing in `Raid` reads it. Its camera sees the head that
  your own first-person camera leaves out (`Mirror.HEAD_LAYER`).
  Players may only wear `Human.STARTER` clothes plus outfits they own:
  `Human.player_look(raw, owned)` enforces it on the profile, in the
  customizer and on the server. Better outfits are bought or earned, never
  added to the starter list. Bots use `Human.sanitize` and can wear anything.
- Only assets that are free, may be used in a game that makes money, and need
  no credit (Caleb's call): CC0, or a royalty-free license like Sonniss's
  GDC bundles (shipped inside the game, never as loose files). Nothing that
  needs attribution (CC BY) or forbids selling. Each one recorded in
  `assets/LICENSES.md`.
- Load assets that need importing (models, textures, fonts) with `load()` at
  runtime, not `preload`: a preload fails to parse on a fresh checkout before
  Godot has imported the file.
- Items are ids defined in `ItemDB` with tags. Use tags, not id checks, to
  decide what an item does.
- Gear behavior comes from the item's `stats` in `ItemDB`, applied by
  `Loadout.equip`. Add a new gun or frame as data, not as a new class.
- A loadout carries one primary, one melee weapon and one sidearm. Keys are by
  type, not equip order: 1 primary, 2 sidearm, 3 melee, and 4 the heavy weapon
  in the watch's chamber (`Actor.slot_order`, `weapon_for_key`,
  `Loadout.power_index`); the
  mouse wheel cycles the same order. Sidearms are firearms also tagged "sidearm";
  `Loadout.fits(slot, id)` decides what goes in a slot (a sidearm never fits
  the primary slot), and `Weapon.is_sidearm` marks one once equipped. A gun
  never switches itself (Caleb's call): run dry in hand it stays there and
  never reloads on its own; the prompt under the crosshair asks for one
  (`Hud.reload_prompt`, on with or without a helmet, in both views) and a
  pull on the empty gun starts it too, and with nothing left to load a pull
  only clicks ("Out of ammo"). A reload press the gun cannot
  take yet (drawing, healing) is kept for `Actor.reload_buffer`. Only the
  player, or a bot's brain pressing the same key (`BotBrain._tend_kit`),
  changes weapons. A player arrives unarmed (Caleb's call): every life in
  every world starts with the weapons put away and key 1's weapon ready to
  draw (`Loadout.arrive_unarmed`, in `Raid.add_player` and the client's
  copy in `NetSession`), and comes out only by choice: a number key, Z, the
  wheel, or a pull of the trigger with empty hands, which only draws. While
  `Actor.weapons_locked` (a safe zone, a gate outpost, the base off the
  range) a weapon in hand is put away and nothing can be drawn
  (`Actor._simulate_weapons`). Headshots come from
  `Combat.is_headshot` on a `Combat.trace` hit; a gun's `headshot_mult` scales them.
  Every gun has a range and a target it wins against (DESIGN.md "Gun
  roles"): each sets its own `headshot_mult` (more than 1 on every gun but
  a shotgun), close-range guns fall off with distance (`falloff_start`,
  `falloff_end`, `falloff_min`, `Gun.range_mult`) and marksman rounds go
  partly past armor (`Gun.armor_pierce`). Measure a change with
  `godot --headless --path . res://tests/gun_bench.tscn`, which prints
  every gun's time to kill by range and armor.
- Attachments are items tagged "attachment" plus their slot tag ("optic",
  "muzzle", "grip", "magazine"), each an optional loadout slot
  (`Loadout.ATTACHMENT_SLOTS`). They fit every primary and never a sidearm
  or a power weapon (tag "power", see `Loadout.is_primary`).
  `Loadout.equip` fits them with `Gun.fit` before the gun is equipped: their
  stats are data ("mult" scales the gun's tuning vars, "zoom" sets
  `Gun.ads_zoom`, "quiet" suppresses, "model" picks the shape). They go in
  `gear_items`, so they drop and come home with the gun. `Gun.build_attachment`
  builds each shape with its origin at the mount; `Look.mount_attachments`
  moves them onto the real model (`Look.GUN_MOUNTS`). An optic's "Sight"
  marker is the eye point: aiming brings it up to the model's eyes in both
  views, first person looks through it, and zooms by `Weapon.aim_zoom()`. Scopes are
  real geometry you look down, never a screen overlay, and picture in
  picture (Caleb's call: never a blacked-out screen): a scope's item has
  `"lens": true` (`Gun.scope_lens`), its "Sight" sits a real eye relief
  behind the eyepiece so the scope is a picture in the middle of the view,
  the aimed view keeps `ads_fov`, and `PlayerController._update_scope`
  renders the magnified view from the eye onto the eyepiece's "Lens" glass
  (`assets/shaders/scope_lens.gdshader` draws the reticle there). Fitting happens at
  the home base's gunsmith bench (`BaseLayout` kind "gunsmith", which is
  kept at the bench, never hung on show: `BaseLayout.is_at_bench`).
- Power weapons are items tagged "power" (Rail Lance, Helion launcher, Arc
  Mortar, Storm Cannon), still plain `Gun` data: stats such as
  `charge_time`, `pierce`, `projectile` ("rocket"/"grenade", flown by
  `Gun.Round`), `splash_radius`, `heat_seek_cone` and `spin_up` pick the
  behavior, and `Gun.splash` sends every blast through `Combat.deal`. They
  are found in a PvP world, not bought: `PowerArmory` (`core/war/power_armory.gd`,
  `Raid.armory`, authority only) puts them on power racks (a `LootContainer`
  labelled `LootContainer.RACK_LABEL`) at strongpoints, beside supply pods
  and sometimes beside a refilled cache, more often as `Raid.war` heats up,
  scaled by `WorldDef.power_weapon_rate` (0 in Frostline and the arena).
  Using a rack scans its weapon into the watch's heavy chamber, a fourth
  weapon slot filled through `Loadout.set_power` with `draw` false; one
  already carried goes on the rack with its shots. Key 4 draws it, as does
  the watch's weapon carousel (Caleb's call after a playtest, replacing
  "from the watch only"), and the wheel skips it (`Actor.slot_order`); it
  materializes over `Loadout.summon_time` (`Actor._draw_weapon`). Picked on
  the watch while in hand it goes back into the chamber, never the pack
  (`PlayerController.take_picked_weapon`). It takes the primary's place
  (Caleb's call): while it is out the primary waits in the watch
  (`Actor.primary_in_watch`) and materializes again whenever it next comes
  into the hand, by any path (`Actor._swap_primary_and_heavy`); the sidearm
  and blade stay instant. A spent one is thrown
  away. A dead player's is left on a rack beside the bag (never in the pack),
  and that death counts it as lost; where deaths drop scrip piles it is
  sold into the pile instead. `StashRules.storable` accepts them: a
  depot upload or a sign-out puts the chambered one in the stash, and it
  hangs on the home base's heavy weapon wall (`BaseLayout` kind `heavy_wall`,
  the `heavy_wall` upgrade) where copies stack. One may be equipped in the
  optional `power` loadout slot and is taken from the stash only when
  `WorldDef.carries_power_weapons` (a PvP world); the arena, Frostline and
  safe zones leave the chamber empty. They sell back at the trader for 40%
  and are never shop stock. Online the swap
  reaches clients as `Actor.power_changed` through `NetSession`. Their art is
  `Look._power_model` and `_dress_power_rack`; check by eye with
  `visual_check.tscn -- <dir> --power-only`.
- Flight rigs and abilities are data too. `FlightRig` and `Ability` are single
  classes whose item stats pick the behavior. Abilities fire from
  `ActorCommand.ability_pressed`.
- Artifacts (DESIGN.md section 6) are data too: items tagged "artifact" in
  the optional `artifact` loadout slot, run by the one `Artifact` class
  (`core/abilities/artifact.gd`, `Actor.artifact`) whose `effect` stat picks
  what it does ("rewind", "cloak", "overclock", "bloom"), with `charges` per
  outing (0 for no limit) and a `cooldown`. One per outing: `Loadout.equip`
  attunes the first and a second is only carried as loot. It is used from
  the watch (a click on the artifact icon, `PlayerController.is_on_artifact`)
  through `ActorCommand.artifact_pressed`, so it is simulated from the
  command on every machine like an ability. It is gear (`gear_items`), so it
  drops in the bag and goes home like the rest. Every effect must be seen or
  felt by the people it touches, and in the world, never on the screen: the
  rewind trail and bloom ring are `Fx`, the cloak fades the whole body in
  `ActorSkin._update_cloak` (the same body in both views). A cloak is read
  with `Actor.is_cloaked()` by bots, nameplates and the sign-out countdown.
  A jammed rig (`FlightRig.jam`, `working()`) and an overclocked one
  (`heat_free`, `lock_up`) are rig states, not new rig types. Artifacts
  drop from world events (`WorldDef.roll_artifact`, `warlord_artifact_chance`,
  `pod_artifact_chance`), the Heart Warden's vault and the Blade
  Tournament's weekly prize (`Arena.blade_prize_artifact`) until the Spore
  Marsh's dungeons become their main source.
- Flight is simulated in `Actor` from the command, like a dash, so it
  predicts and replicates: jets lit only while aim is held in the air
  (`Actor._wants_hover`, Caleb's call: never a hover that stays on by
  itself; `FlightRig.is_hovering`, flown by `Actor._simulate_hover`; the
  server repeats it in each state as `ActorCommand.STATE_HOVERING`), a
  boost started by a sprint press in the air and held on sprint, no hover
  needed (`Actor._wants_boost`), that speeds you up along the look
  direction while the skin lays the body out prone as the speed builds, and a glide whose speed is energy
  (`Actor._glide_velocity`). Each rig has one job and one weakness
  (Caleb's balance pass, DESIGN.md section 5; the Mk1 numbers are
  `ItemDB.JETPACK_MK1`, `BOOTS_MK1` and `WINGS_MK1`, measured by
  `tests/rig_balance_tests.gd`): the jetpack is height and hover (8 s on a
  full bar, climbing 1.3x and boosting 2.5x the heat, a 40 m ceiling,
  steady aim), but slow across the map, loud and clumsy under a roof;
  the boots are ground agility and stealth: no heat, `max_charges` pay for
  kicks and dashes, a short skim (`skim_time`), faster on foot
  (`ground_speed_mult`), no fall damage, a graze window on every dash
  (`Actor.graze_left`, checked in `Actor.modify_incoming`), but a 10 m
  ceiling; the wings are distance and speed: a launch, a fast glide on glide
  stamina (`glide_heat`, refilled on the ground only) and two boosts a
  flight, but no hover or climb of their own, poor aim, sidearm only, and
  no use indoors. A rig's `scan_range` is how far scans and thermal pick
  its wearer up (`Visor.reach_to`), `indoor_mult` how well it flies with a
  roof overhead (`FlightRig.indoors`, probed by `Actor._measure_indoors`),
  `flight_aim` its air spread in its own flight (`Actor.air_aim`) and
  `fall_damage_mult` its share of fall damage (`Actor._hurt_by_fall`, out
  in a world only, through `Combat.deal`). Rigs come in tiers (Caleb's
  call): Mk1 to Mk3 of each, made with `ItemDB._rig_tier`, which scales
  only the stats in the rig's `ItemDB.RIG_STRENGTH` list by
  `RIG_TIER_STEP` (about 15% a tier, a charge a tier for boots): a tier
  improves the rig's strength, never its weakness, and the heat bar stays
  100. A rig's `ceiling` is measured
  from the world's ground, never a roof (`Actor.ground_level`: the map's
  `ground_height`, else its origin; the home base is its own ground), and
  only limits lift: the climb eases
  off under it (`FlightRig.climb_room`) and a kick, launch or boost is cut
  to top out on it (`lift_cap`), or refused. Only Mk1 drops or
  is sold: Mk2 and up are crafted from blueprints (DESIGN.md section 10),
  so no loot table may list them.
  The keys fly every rig and the mouse only looks and aims
  (Caleb's call), with one exception: wings fly where you look, like a
  bird's (Caleb's call, so you never fly sideways to your view). They bank
  round onto the view's heading (`Actor.glide_steer`), the strafe keys roll
  a harder turn, and forward and back dive or pull up (`Actor.glide_trim`),
  never the view's pitch. Holding free look (E, `ActorCommand.free_look`,
  Caleb's call) the wings fly straight on and the view looks and aims
  anywhere; let go and they come round onto the view. In free look the
  body twists round its length to face the view, so looking behind lays it
  on its back, a backstroke, to shoot behind (`ActorSkin._look_roll`, view
  only; check with `visual_check.tscn -- <dir> --flight-only`). A glide flies like a wing (`Actor._glide_velocity`):
  speed is momentum, a turn costs speed, a bank sinks faster, pulling up in a
  turn tightens it, and below the stall speed the wings stall
  (`Actor.glide_stalled`: they barely turn and drop at `stall_sink` until the
  nose drops and the speed comes back). Gliding, Shift is a wing boost
  instead of a dash (`FlightRig.glide_boost`): it thrusts you the way you
  face and the glide keeps that speed, and Shift + S boosts upward
  (`glide_boost_climb`); wings never dash sideways. The glide's attitude is
  held in the world while the view turns, so spinning the camera never
  drags the body round (`ActorSkin._update_glide`). And a jetpack boost
  runs along the view's heading, climbing only on jump and descend, never
  on the view's pitch.
  Every rig air dashes on Shift + a move key (`ActorCommand.sprint_pressed`,
  `Actor._air_dash`, tuned by the rig's `air_dash_*` stats): the dash is
  added on top of the rig's own flight and taken back off, so a glide or a
  cruise carries on after it. Q and E fly nothing (Caleb's call); E holds free look.
  The body's attitude in the air (flat, banked, leaning, barrel rolled by a
  sideways air dash) is the skin's job (`ActorSkin._update_glide`), read
  from velocity and the simulated actor only, so remote players match. Boots
  show their thrust (`ActorSkin._update_boot_thrust`): the body leans into
  the push (gravity, drag and speeding up), the legs and swivelling flames
  fire down the exhaust, and flying forward lies the body out near flat with
  the legs dropped so the heel jets fire down and back (never fully flat,
  or nothing would hold you up). Off the
  ground (`ActorSkin.is_airborne`, from `Actor.airborne_time`) the legs
  never play a gait: a stand plays under an air pose (leap, fall, or
  hanging from lit jets). Leaving the ground starts with a short push-off
  and a running jump leans into it; a touchdown (`Actor.landed`) bends the
  knees by how hard it was (`Locomotion.squat`). All of it is view only. A boost keeps the arms down at the sides, never
  reaching ahead (Caleb's call). Check it by eye:
  `visual_check.tscn -- <dir> --flight-only` (or `--takeoff-only`).
- Feel is measured, not guessed: `godot --headless --fixed-fps 60 --path .
  res://tests/feel_bench.tscn` flies every rig through set moves and prints
  how long each takes to answer and the hardest jolt (velocity change in one
  tick, as m/s²). Movement eases: nothing but a jump, burst, pulse or dash
  may change an actor's velocity by more than its own accelerations in one
  tick (wings catch a fall at `FlightRig.glide_catch_accel` and roll into a
  bank at `glide_bank_rate`; never clamp a velocity straight to its target).
  Recoil is a pattern you can learn (Caleb's call, DESIGN.md "Recoil"):
  each gun's `recoil_pattern` ("climb", "climb_right", "climb_left",
  "sway", "kick") and a kick that builds through a spray
  (`Gun.recoil_for`, `spray_shot`, counted in `Gun._fire`, so simulated),
  with only `recoil_jitter` of the side kick left to chance; a new gun
  names a pattern in its stats. Bots take the same kick into their aim
  and pull against a share of it by skill (`BotBrain._take_recoil`,
  `RECOIL_CONTROL`); measure with `gun_bench.tscn -- --recoil`.
  What only the player sees is the controller's job and view only: recoil
  reaching the view over a few frames and settling back
  (`PlayerController._update_recoil`), the view widening with speed
  (`speed_fov`) and dipping on a landing (`land_dip`). A semi-auto keeps a
  pull made just before it is ready (`Gun.press_buffer`); that is simulated,
  so it is in `Gun`, from the command. Handling is simulated the same way
  (DESIGN.md "Handling"): moving widens a gun's spread by its
  `move_spread_deg` times the share of sprint speed on the ground
  (`Gun.move_share`), aiming tightens it over the gun's `ads_time`
  (`Gun.aim_in`), not at once, and you never shoot while sprinting: a held
  trigger or aim slows you to a walk, and a gun fires only
  `Actor.sprint_out_time` after the sprint ends (`Actor.sprint_recover`),
  keeping a pull made meanwhile. Light guns are quick and steady on the
  move; a DMR is slow to aim and wild on the run.
  Feedback is view only (DESIGN.md "Feedback"): every gun has a voice of
  its own (the item's `shot_sound`, one of `Sfx.GUN_VOICES`, never shared;
  a test checks it) that fits what it is: the everyday guns are ballistic
  (a crack, the action, a low punch, the cycle), the heavy weapons energy
  (a charged snap, a zap or plasma, crackle). They are made from code by
  `assets/sounds/weapons/make_weapon_sounds.py` (ours, no credit needed;
  short rings and short echoes, Caleb's feedback: never a bell, never a
  long echo), takes for the open, under a roof and far off.
  `Sfx.shot` plays your own the tick it fires, flat, and anyone else's
  where it went off: under a roof (`Sfx.roof_over`) the indoor take, past
  `Sfx.FAR_FROM` giving way to the far take after the sound's travel time.
  A rail's charge and a rotary gun's spin are heard from the gun's state
  (`ActorSkin._update_weapon_hum`), a draw as the hand takes the weapon,
  all heard out to `Gun.SHOT_REACH`, a round
  passing close is heard going by (`Sfx.pass_by`), a round leaves a puff
  and a wall a mark for a few seconds (`Fx.impact`, at most `Fx.MAX_MARKS`;
  `Combat.trace` gives the face's `normal`), the hit marker and its sound
  tell a head, plates soaking it (`DamageInfo.armored`, set by
  `HealthComponent`), plates breaking (`armor_broke`) and a kill apart
  (`Hud.HitMarker.kind_of`; online they ride `NetSession._hit_feedback`),
  and a round jolts the view (`PlayerController.bullet_flinch`), never the
  aim. Who shot you is not shown: that is the tactical visor's job.
  Check by eye with `visual_check.tscn -- <dir> --impacts-only`.
- Helmets are items tagged `helmet` in the `helmet` loadout slot, and data
  like abilities: `Visor` (`core/abilities/visor.gd`, `Actor.visor`) is one
  class whose `mode` stat picks what the visor does ("" plain, "zoom"
  binoculars, "scan" pulse, "threat" tactical, "thermal"). It is driven by
  `ActorCommand.visor_pressed` (a press: scan, Threat Sense) and
  `ActorCommand.visor_level` (held: the zoom level, thermal on).
  What a visor reveals is decided by the authority only and never goes to
  everyone: `NetSession` sends a scan's snapshots to the scanner, the ping to
  each player caught, a tag to the tagger's side, and a tactical visor's
  hit direction and Threat Sense list to its wearer. Reveals must stay fair:
  a scan is a snapshot, never live tracking, Threat Sense only shows people
  aiming at the wearer, thermal never sees through walls, and every reveal
  is felt by its target (the ping, the "Sensed" notice, the lens glint, the
  ember of a thermal visor), except where nobody can be fought
  (`Visor.peaceful`: a safe zone or the home base), where the ping and the
  "Sensed" notice are left out as noise. How warm someone looks on thermal is
  `Visor.heat_of`: `Actor.heat_signature` (frames set it with a
  `heat_signature` stat) plus flight rig heat. The picture is `VisorHud`
  (`core/ui/visor_hud.gd`), a view: its glass is drawn in first person only
  and only while a helmet is worn, wherever it is worn: worlds, the plaza,
  the arena and the home base (`BaseHud.visor`, `VisorHud.setup_base`;
  Caleb's call) (Caleb agreed a visor counts as in-world,
  since you look through it); what a visor shows out in the world (snapshots,
  tag markers, pulse rings, glints) is there in either view. The glass is thin
  projected light, never a frame, a tint or a mask over the view (playtest
  feedback: the first visors were in the way): it rests dim, trails the
  head, wakes on trouble (`VisorHud.alert`) and closes on what is aimed at
  (`VisorHud.lock`). Neither view is better informed (Caleb's call): in
  third person the glass itself (its rim, a scrap visor's cracks, the trail
  behind your turns) is gone, but every readout it carries is drawn flat
  in the same places (`VisorHud.flat_shown`), thermal included, and the helmet wears
  its health strip and system light on the back of the head
  (`ActorSkin._update_vitals`, `helmet_light`), where a pack or a slung gun
  never covers them. The glass hugs
  its rim and keeps the middle clear (Caleb's redesign, from a reference he
  liked, made our own: never copy any one game's look). It carries your
  always-in-view readings as a row of hex cells along the lower left curve,
  each filling like a gauge with its number over it (health, armor,
  stamina, with a flight rig its heat and cue, the ability;
  `VisorHud.vital_cells`), and under the middle of the lower rim the
  landing warning (`Hud.landing_warning`: the rig about to cut out while a
  fall from there would hurt; `VisorHud._draw_landing`, and the pack
  screen's word turns to LAND, DESIGN.md section 5). Every working helmet also has a heading tape across
  the top, bowed with the glass, that marks only what the wearer is already
  told (`VisorHud.compass_marks`): squadmates (`VisorHud.squadmate`: a player in
  the same clan, or everyone where `WorldDef.players_allied`; never a bot or
  an enemy), the side's pings and the nearest depot, plus each helmet's own
  finds (Spotter tags, Seeker scan snapshots, Warden the war's hot zone).
  The same marks are plotted round you on a small contact scope top left
  (`scope_points`; never ground or walls, it is not a map), with the
  helmet's name, role and system beside it; the contracts held and the
  tour's step are an objective block top right (`objective_lines`, from
  `hud.contracts` and `hud.objective`); faint pitch ticks run up both edges.
  Loot is read off the glass too (Caleb's call, DESIGN.md "Loot at a
  glance"): the container you look at gets a tag listing every item inside,
  with rarity and whether it beats what you wear (`VisorHud._draw_crate`,
  `loot_rows`, `versus_worn`), and what you pick up runs up a fading feed
  over the weapon readout (`_draw_pickups`), fed by `Actor.looted`, which
  only the authority emits and `NetSession._looted` repeats to the owner.
  Bottom right, mirroring the vitals, a quiet weapon readout (Caleb's pick):
  the weapon in hand, the mag over a tick a round and the pack's rounds,
  resting dim and lit only on a reload, a low mag or just after a switch
  (`VisorHud.weapon_awake`); ammo is still read off the gun's own counter.
  Each helmet has a role it names as it comes on (`role_name`) and its own
  reticle; an Ember also reads its wearer's own heat signature. A scrap
  visor manages only a bearing. Do not put the map or standing there, they
  stay on the watch. Mk2
  helmets are never sold or dropped: like rigs, they are crafted from
  blueprints (DESIGN.md section 10), so no loot table may list them. Check the glass by eye with
  `visual_check.tscn -- <dir> --visors-only`.
  A helmet is worn gear, not a flag: `Loadout.wear_helmet` is the one way
  one goes on or comes off (it resets the visor, keeps `gear_items` right
  and emits `Actor.helmet_changed`). Mid-raid, helmets in the pack
  ride the watch's weapon carousel (`Hud.weapon_entries`, shown as their
  own model), and a click on one goes through the summon
  (`Raid.summon`, online `NetSession.summon`) to `Raid.swap_worn`
  (authority only, at once, then a short watch rest): it goes on and the
  worn one goes in the pack; `_worn_changed` tells every client. The skin wears it on the
  head (`ActorSkin._update_helmet`, `build_helmet`), hiding the head under it; it
  hangs off the "Head" bone, so first person leaves it out with the head.
  Each helmet looks like what it does (Caleb's call, and his tactical
  pass: grounded military sci-fi; `helmet_model.gd`): a dark hood, a
  shell with a real outline (a superellipsoid, never a ball) with a brow,
  a rim and the mode's own cut (the Spotter high-cut for a headset with a
  flip-down rangefinder, the Seeker full-cut with a jaw guard and crown
  emitter, the Warden a faceplate with a lit slit and sensor eyes all
  round, the Ember a broad ceramic shell over its heat sinks, the scrap
  visor a patched pot with cracked goggles), framed glass that is dark
  and reflective, never a glowing panel; a Mk2 (`Visor.tier`) wears a lit
  seam over the crown. Every helmet and armor piece is built from
  `GearShapes` (`core/visual/gear_shapes.gd`), merged into one mesh per
  material (`GearShapes.merge`: "Gear", and "Glass" with no shadow; the
  parts it was made of in its "parts" meta, `has_part`) and built once
  per kind, then shared (`GearShapes.cached`). Keep
  the back of the head clear for the vitals strip. Goggles will be the
  same glass and fitting on a strap, no shell. Check by eye with
  `visual_check.tscn -- <dir> --helmets-only` (helmet_closeups.png).
  Armor frames are worn gear the same way: `Loadout.wear_frame` puts one on
  or off (`Actor.frame_id`), undoing the old frame's speed and heat scaling
  before applying the new one, and emits `Actor.frame_changed`. One frame is
  worn; another in a kit is carried. A frame in the pack is on the summon
  carousel too and goes through `Raid.swap_worn`. Both go on at once and
  then the watch rests (`Loadout.SUMMON_TIMES` "helmet", short, and
  "armor", long), and a frame taken off keeps its armor left in
  `Actor.stowed_armor`, so spare plates are no instant refill. The skin
  wears the whole kit (`ActorSkin._update_frame`, `armor_model.gd`): a
  plate carrier on the chest (`build_frame`), a battle belt on the hips
  (`build_belt`) and on each side a segmented shoulder pad (`build_pad`),
  an elbow pad and bracer (`build_bracer`), a thigh plate (`build_tasset`,
  a drop-leg pouch on the right) and a knee pad and shin guard
  (`build_shin`), each on the bone it moves with (`_hang_limb` turns a
  limb piece along its limb), the same body in both views, over the
  undersuit, and on the base's armor stands (`HomeBase._build_armor`).
  Plates are fitted, never boxes (Caleb's call): curved shells off the
  torso, bevelled at the edges, over a fabric carrier with straps,
  webbing and pouches. Weight reads at a glance: the frame's weight tag
  picks its coverage (`ActorSkin.FRAME_BULK`), light a slim carrier,
  caps and knee pads, medium the full kit with a cummerbund and an upper
  arm plate, heavy layered plate with abdominal lames, a gorget, faulds
  and greaves that widens the shoulders, so a frame moved to another
  weight tier changes bulk with it. Each frame also has a look of its own
  that fits what it does (`FRAME_LOOKS` to `FRAME_STYLES`: plate,
  carrier, strap, undersuit, accent and metal colours, and details such
  as the Runner's cool back panel, the Trooper's radio and hydration
  carrier or the Bulwark's hot back vents); a new frame gets a
  `FRAME_LOOKS` entry (a test checks it). Frames can be painted
  (DESIGN.md "Armor paints", Caleb's call): `ArmorPaint`
  (`core/visual/armor_paint.gd`) is a row of the colour keys only, held in
  a safe range (`ArmorPaint.SAFE`), laid over a look by `frame_style`, so a
  paint never changes stats, shape, metal, details or glow strength. A
  paint is a cosmetic item tagged "paint" (the Tailor sells the plain
  ones; earned ones are Relic loot from `WorldDef.warlord_paint` and a
  world's own tables, never sold or traded), unlocked as "paint:<id>" by
  `Economy.unlocked_outfits`, and the choice (frame look to paint) rides in
  the appearance's "paints", so `Human.player_look` checks it like clothing
  and it travels wherever a look does. It is picked at the base's armor
  stands (`HomeBase.PaintSwatch`, `paint_requested`, `show_paints`).
  Check by eye with
  `visual_check.tscn -- <dir> --armor-only`.
- Vehicles are items tagged `vehicle`, tuned by their stats, and spawned by
  `Raid` (never carried). `core/vehicle/vehicle.gd` reads its rider's
  `ActorCommand` and moves the rider; `Actor` skips its own movement while
  `Actor.vehicle` is set. The script has no `class_name`; preload it.
  A rider sits, never stands: the vehicle carries the actor low at
  `seat_offset` (so the eyes and head hitbox are a seated rider's), and the
  skin seats the model from the vehicle's `seat_point`, `grip_points` and
  `peg_points` (`Locomotion._ride_pose`): hips on the seat, leaning forward,
  feet on the pegs, hands on the grips, the whole body tipped with the
  bike's lean (`ActorSkin.ride_frame`). The left hand keeps its grip; the
  right takes its grip only with nothing in it, holds a gun out toward the
  aim, and leaves a blade to its usual hold, so melee windups still show.
  Back-slung weapons ride higher up the back (`ride_sling_lift`); weapons
  clamped to a back rig's rails stay in their clamps. Riding, the
  first-person eyes follow the seated head as posed (`ActorSkin._note_head`,
  since the ride pose exists only inside the skeleton's update), so a new
  vehicle's `seat_offset` keeps the actor's eyes (aim, head hitbox) near that
  head, and anything the rider looks through is see-through glass
  (`Vehicle._clear_glass`, a material override `Look` leaves alone). A new
  vehicle type sets those anchor points for its model. Check by eye:
  `visual_check.tscn -- <dir> --ride-only` (`RIDE_VEHICLE=<item id>` for
  another vehicle). Every vehicle is that one class, picked by data: the
  `model` stat picks the body ("bike", "hoverbike", "rover", "mech",
  "jet"), built by `core/vehicle/vehicle_model.gd` in the sci-fi style the
  rigs wear (bevelled shells cut into panels, lit seams in the rarity
  colour, cyan thrusters; glass and glows are material overrides `Look`
  leaves alone, a lamp a surface glow it hangs a beam on) round the
  item's own anchors, so a restyle never moves a seat or a hitbox; check
  them side by side with `visual_check.tscn -- <dir> --vehicles-only`,
  `body_size` its collision box, `pivot_turn` lets a walker turn on the
  spot, `jump_speed` gives it a jump-jet hop, the "hover" tag floats it on
  a cushion ("hoverbike", the Raider: it drifts through turns by `slip`,
  which travels in the ride state and is corrected like `speed`, holds
  level over a gap for `hang_time` and hugs the ground off a ramp, never
  flying), `passenger_seat` adds passenger seats
  (`Vehicle.seats`, by default one pillion behind the rider from the
  `pillion_*` vars; the rover lists three, so it seats four, Caleb's call;
  `Vehicle.passengers`, `mount(actor, true)`, which takes the free seat
  nearest them; the seat's interact puts the next player there; a
  passenger is seated by the same riding pose from their seat's anchors,
  `Vehicle.ride_anchor`, each makes it heavier, the `laden_*` shares, and
  only the server decides who sits where, sent in the ride state; check anything that asks whether a vehicle is free with
  `is_occupied`, never `rider` alone), and the "aircraft" tag flies
  it (`Vehicle._fly`: takes off past `takeoff_speed` with jump, never
  hovers, drops below `stall_speed` or with nobody at the stick, climbs no
  higher than `ceiling` over the world's ground). Jump is the handbrake
  (`handbrake`, off for the mech and the jet, whose jump key is theirs):
  at speed it is a drift (`Vehicle.drifting`, the same `slip` a hover
  keeps, `drift_*` stats) whose clean exit on the throttle is a short
  burst (`drift_charge`, `_drift_exit`), and a world's slick ground
  (`WorldDef.surface_grip`, Frostline's snow and ice) lets wheels slide
  on their own; a hover ignores it. Every vehicle, the jet
  included, can be thrown in every world (Caleb's call), except a race
  world (`WorldDef.vehicle_toys` off), which races its own stock machines. A vehicle's `watch_recharge` and `footprint` stats
  set the watch's wait after a throw and the room it needs to unpack.
- Toy vehicles: a vehicle a player owns in a world rides on their watch as
  a toy (`Raid.PlayerState.stowed`, read with `Raid.stowed_for`), never in
  the inventory. `Raid.throw_toy` throws one from the actor along their aim;
  the `Raid` flies it (`_tick_toys`) and unpacks it into the vehicle where it
  lands, if `has_room_to_unpack`, else it goes back on the watch.
  `Raid.pack_vehicle` packs the vehicle being looked at back onto the watch
  (a click with the watch raised: it has no key of its own).
  Limits are the `Raid`'s vars (`toy_cooldown`, `watch_capacity`) and
  `WorldDef.vehicle_toys`. Only the authority throws, lands and packs: a
  client sends `NetSession.throw_toy` / `pack_vehicle`, the server reads the
  aim from the actor it simulates, and clients get `_watch` (their own watch)
  and `_toy` (a toy to draw in flight, with who threw it). The toy in the
  hand is the one body's, seen by everyone (Caleb's call): taking one off
  the watch is `Raid.hold_toy` (online `NetSession.hold_toy`, the home base
  `HomeBase.hold_toy`), which sets `Actor.toy_in_hand`, and a throw bumps
  `Actor.toy_throws`; `NetSession._toy_hand` copies both to everyone else
  (the thrower's own game shows its hand at once). Nothing in the simulation
  reads them. The throw winds up before the toy flies: the `Raid` keeps it
  in `toys` with a `windup` (`Raid.toy_windup`, the same as
  `ActionPose.toy_release`) and lets it go along the aim as it is then; cut
  short (on a vehicle, dead) it goes back on the watch. The shown hold and
  overarm throw are `ActionPose.toy_hand_point` / `toy_turn`, reached by
  `WeaponArm`; the skin puts the weapon away meanwhile, digitizes the toy
  into the hand (`ActorSkin._update_toy`) and lets it go at the release. In
  the air a toy turns one flip and comes down level facing the way it
  unpacks (`Vehicle.toy_flight_basis`), so the vehicle grows out of it
  without a jump, with a ring of light (`Vehicle.unpack`). Check by eye with
  `visual_check.tscn -- <dir> --toys-only`. The picker on the watch
  (`PlayerController.held_toy`, `Hud.Wrist.show_toys`) is a view.
  A new vehicle is a new `vehicle` item; its toy is `toy_model(id)`.
- Mastery (`core/progression/`) is keyed by gear type tags ("rifle", "blink",
  "frame_heavy"), never by item id. Variants are sidegrades: every one trades a
  strength for a weakness, and death never takes mastery away. Variant picks go
  into `Raid.start` alongside the kit; `Raid` never reads them from `Profile`.
- `starter`-tagged items are the free scrap kit. They never enter the stash:
  every player owns one of each piece that goes in a slot
  (`StashRules.free_items`, `equippable`), equipped like any other gear and
  shown in their own base. An empty loadout slot is bare (Caleb's call:
  you can go fully bare, clothes aside): nothing fills it on a deploy, in
  the base or in the arena, and a kit of nothing is `[Loadout.BARE]`,
  because an empty kit still means the world's scrap kit to
  `Raid.add_player`. Only lost gear falls back to its scrap piece
  (`StashRules.validate_loadout`). A new player starts with nothing
  equipped (`StashRules.new_player_loadout`, Caleb's call): no weapons,
  armor or helmet, and puts everything on by hand the first time (the
  welcome crate and the scrap pieces wait in the base). A save without
  `StashRules.BARE_KEY` is from before the bare rule and gets its empty
  slots filled once with the scrap kit (`StashRules.starter_loadout`).
- Safety nets (`core/economy/safety_nets.gd`, static rules like `Economy`,
  DESIGN.md "Safety nets"): salvage and one insured item, decided by the
  authority's `Raid` at a death and nowhere else. `add_player`'s
  `p_insured` (from `StashService.deploy`'s "insured", or
  `Profile.insured_in` solo, and only if the kit carries it) is recalled
  from the body before the bag drops (`Raid._recall_insured`), never
  copied: the killer simply does not get it. Salvage is paid only for
  crafted gear from the stash lost with the body. Both travel in the
  result ("recalled", in `brought_home` too, "salvaged", "salvage") and are
  settled by `StashService.settle` online and `Raid.apply_result` solo; a
  policy is kept on the account (`Account.insurance`, in the snapshot and
  `StashRules.CARRIED`) and changed only by `StashService.insure`.
- `Raid` never touches `Profile` to build a kit. The kit is passed into
  `Raid.start`, so a server can supply it later.

- Online play: the server is the authority (`Raid.Mode.SERVER`, `NetSession`).
  Clients simulate actors from commands for responsiveness, but
  `Combat.authoritative` is false there, so a client never deals damage, loots,
  or decides an outcome. Anything that changes a result must run on the server
  and reach clients through `NetSession`.
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
  "secret"` on the same connection. A store login (Steam) is a new method
  there that ends in an account id, never a second path into a session. Both sides' messages always carry "protocol", so any two
  versions can say which one needs the update; an older game is pointed at
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
  full packet fits in one datagram), so a press survives a run of lost
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
- The phone (`core/phone/phone.gd`) is the game's menu and only a view. Online,
  presence, contacts, messages, invites and news live on the server in
  `SocialService` (`core/social/social_service.gd`), keyed by the account id
  the peer signed in with, never by anything the client claims. `NetSession`
  turns phone requests into service calls and pushes each affected player a
  fresh `social_state` snapshot. A feature that adds a new place a player can be
  (base, social hub) reports it with `NetSession._set_presence(peer, where)` and
  a name in `SocialService.PLACE_NAMES`. The phone's Controls app lists
  every key from `Phone.CONTROLS`, whose `{action}` names are filled in from
  the live `InputMap`; a new input action needs a row there (a test fails
  otherwise), and a changed control needs its row's wording updated. The phone
  is a thing in the hand, never an overlay, and every view shows the same
  one: a rugged handheld with a pistol grip (`core/phone/handheld.gd`, its
  origin at the grip) that the character's own right hand closes round with
  the gun-grip fist (`ActorSkin._update_phone`, `Locomotion.phone_pose`,
  driven by `ActorCommand.phone`, a held flag, so everyone sees it). Your own
  phone puts its screen, a `SubViewport` drawn with the device's frame and
  chin keys, on that handheld's face (`Phone.set_holder`,
  `ActorSkin.set_phone_screen`) and clicks are cast onto it; other players'
  show lit glass. Nothing floats off the device (Caleb's call, replacing the
  old holo panel): it is held at the chest, a forearm out and right of the
  middle, below the face (`Locomotion.phone_wrist`), so others and a mirror
  see a person reading a phone, and every view reads and clicks that same
  face: first person from the eyes, third person from beside the head,
  framed off the crosshair (`PlayerController.phone_read_offset`), and over
  the shoulder, widened, to keep the Mirror app's mirror in frame
  (`phone_mirror`). That mirror
  stands square in front of the body, never along the camera. The Mirror
  app's wheel works like a watch icon: it moves between rows, a click opens
  one for the wheel to turn, a right click closes it (`Phone._mirror_mouse`),
  and the page scrolls to keep the chosen row in view (`Phone._keep_in_view`,
  once the redrawn rows are laid out). The device and its text are sized to
  be read at that hold (`Handheld.HEIGHT`, `Phone.text_scale`, and the
  view's `PlayerController.phone_zoom`, Caleb's feedback); make it readable
  by size and zoom, never by bringing it to the face.
  The other hand hangs at the side while the phone is out
  (`Locomotion.phone_rest`). A new app is an entry in `Phone.APPS` with a line glyph in
  `Phone.AppIcon`. Going online is the Servers app (Caleb's call: no Uplink
  console in the base): it asks `Main` to host, join by address or leave
  (`host_requested`, `join_requested`, `leave_server_requested`) and shows
  `Hub.set_online_status`'s line (`Phone.set_link_status`). Settings are grouped in `Phone.SETTINGS_TABS`, and the dev
  switches live only on the Dev tab.
  Settings live in
  `core/settings/game_settings.gd` (its own save file); a server never reads them.
- Bug reports (the must-work checklist's "Bug reporting with logs"): the
  phone's Report app (`Phone.report_requested`) hands `Main` a line of
  text, and `core/report/bug_report.gd` (`Main.bug_report`, view and
  client only) bundles it with the build, the machine, where the player is
  (`Main.report_context`, plain values, never a secret) and the game's
  log from this run and the run before (a crashed run's log is found on
  the next launch). It posts that to a Discord webhook as a message with
  the logs attached, at most one every `report_every`, and always keeps a
  copy under `BugReport.SAVE_DIR`. The webhook is never in the code: the
  Windows build of main stamps it into `ares/report/webhook` from the
  repository secret `BUG_REPORT_WEBHOOK` (`windows-client.yml`), and any
  other build only keeps the copy. A new fact worth having in a report is
  a key in `report_context`.
- Dev mode is TEMPORARY (Caleb's call, to come out once the game is further
  along): `core/dev/dev_mode.gd`, switched in the phone's Settings app and
  only in a debug or editor run (`DevMode.available`), never in an exported
  game. Solo, it puts `Profile` on a separate save
  (`Profile.DEV_SAVE_PATH`) kept topped up with all gear and max scrip, and
  hands a solo `Raid` its cheats (`Raid.dev_cheats`: god mode, endless heat
  and ammo, no cooldowns); a server or client raid ignores them. Online, only
  a server hosted from the editor in dev mode (`main.gd host_and_join`
  passes `--dev-host`) tops up one account: the one that claims the handed
  profile with the host's secret (`StashService.dev_host`, `dev_accounts`),
  never anyone just using the host's name. Such a server keeps its accounts
  in `Main.DEV_ACCOUNTS`, apart from real ones, and its snapshots only go
  back into the save it was hosted from (`Main._hosted_save`), so dev gear
  never leaks into the real profile; the save never swaps while online.
  Free test gear is never handed to every player (`Profile.GEAR_CRATES`
  stays empty): new gear to try comes from dev mode. `Profile.FRESH_START`
  sets an older real save back to a fresh player once, keeping who you
  are. No cheats online. Every line
  it touches is marked "DEV MODE". Never build a feature on it; to remove it,
  delete `core/dev/` and every "DEV MODE" line or block, plus
  `_test_dev_mode` in the tests. Dev mode also knows every blueprint
  (`DevMode.top_up_blueprints`).
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
  can lead depends on where you are (Caleb's call: home and other places
  too): from your base every world, the arena and the plaza
  (`Portal.from_base`, `Portal.PLAZA` goes the way the base's door does);
  from a safe-zone world every world, the arena and `Portal.HOME` (the way
  the quarters door goes); out in a world where gear is at stake only
  `Portal.HOME`; none in the arena. A squad is `Raid.squad_of`: the key
  `Raid.set_squad` gave the owner (`NetSession` sets the clan, in every
  world), else their side. Only the authority opens one in a world
  (`Raid.open_portal`, `may_open_portal`) and decides who walks through
  (`portal_entered`); online `NetSession` shows each portal to everyone
  (`_portal`, with whether the viewer's squad may use it and how long it
  unfolds; the squad key never leaves the server) and tells the walker
  (`portal_travel`). `main.gd go_through_portal` takes the trip, and arrival
  in a world is `add_player`'s drop `Raid.PORTAL_DROP`: the same "outpost"
  marker for a whole squad, else a quiet drop. Out in a world the portal
  home is a sign-out with a door, never a way round one (`Portal.signs_out`):
  opening it is `begin_sign_out` (so a fight or a bounty refuses it, and it
  takes the sign-out's own time: the gate's in an outpost, 15 s on the
  ground, 25 s and a beacon in the air), the ring unfolds over that
  countdown where everyone can see it and folds away if it is cancelled
  (`Raid._keep_sign_out_portal`), a squadmate stepping in starts their own
  sign-out (`_tick_portals`), and everyone leaves through `_leave` as "left"
  with the result's "door" set to "home", which online takes you to your
  base rather than the plaza (`main.gd _return_to_lobby`). It never emits
  `portal_entered`, and no portal leads from one world into another.
- Risk zones (DESIGN.md section 2): a world tiers its map with
  `WorldDef.zone_at` (0 outer, 1 middle, 2 core) and burns with
  `hazard_at`, which `Raid._tick_hazards` deals through `Combat.deal` once a
  second. The `Raid` marks each bot with the zone it spawned in (meta
  "zone", sent to clients so they build the same bot) before `equip_bot`.
  Bosses stand at "spawn_boss" markers (warlords, `Raid._bosses`, outside
  the armies like event bots, `Raid._is_extra`). Gate outposts are
  "outpost" markers inside a PvP world, not safe-zone worlds: only the
  authority shelters a player (`Raid._tick_outposts`: weapons locked and
  `protected_left` held up), turns away anyone in a fight or with a bounty,
  and gives `spawn_protection` on the way out, which firing ends. Clients
  get the lock from `ActorCommand.STATE_SHELTERED` in the state. Hazards
  and zones are shown in the world and on the watch (`Raid.zone_label`),
  never as an overlay.
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
  `_trip_ahead` says where a doorway, an open portal or a sign-out leads)
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
- `Raid` never writes to `Profile` on a server. Results travel in the
  `player_finished` dictionary. Online the server settles them into the
  account; `Raid.apply_result` is only for the local solo profile.
- The home base (`core/base/`) is a view of a stash, never a second store.
  `HomeBase.show_gear(stash, loadout)` rebuilds the room from plain data, so
  it shows the local `Profile` solo and the server's account snapshot in a
  lobby. `core/base/base_layout.gd` decides what goes where from item tags.
  Whatever is worn is always on show (`BaseLayout.plan` gives it a spot
  even when better gear fills its section), so anything can be taken off
  in the room.
  The base is modular (Caleb's call, DESIGN.md "Home base"): a hub with six
  doorways of one size (`BasePlan.SOCKETS`, `HomeBase.socket_transform`)
  and six rooms standing in them, one each (`BasePlan.ROOMS`: armory,
  workshop, garage, ops, gear hall, stores). Which room stands where is the
  account's plan (`core/base/base_plan.gd`, static rules like
  `BaseUpgrades`; `Profile.base_plan` solo, the account's online, in the
  snapshot and in `StashRules.CARRIED`), always passed through
  `BasePlan.clean`. `HomeBase.show_gear` takes it as its fourth argument.
  Everything in a room is laid out in the room's own space
  (`HomeBase.room_spot`, `STATIONS`' "room", `BENCH_AT`) and placed through
  `room_transform`, so it moves with its room; a display kind's room is
  `HomeBase.KIND_ROOMS`. Ask where something is with `room_at` (and
  `in_armory`, `in_workshop`, `in_garage`), never with coordinates. The
  plan also picks the hub's shape (`BasePlan.SHAPES`: hall, ring, spine,
  courtyard; `HomeBase.HUB_SIZES`, `shape_socket`, `in_hub`, `range_from`,
  `front_half`, `mirror_at`, `deploy_span`, so ask those, never the hall's
  numbers) and each room's style (`BasePlan.STYLES`, three a room: where
  its displays, stations and bench stand, `_style_spot`,
  `style_station_spot`, and what furnishes it, `_furnish_style`; every
  style lays out every spot its room has, whole and small) and the finish
  the hub and each room wear (`BasePlan.FINISHES`, the plan's "finishes":
  steel free, then gunmetal, ceramic, brass, blackout), built through the
  shell's builders (`HomeBase.FINISH_LOOKS`: `_shell`'s surfaces, the
  seams, ribs, kick plates, ceiling light and lamps, `_lit`, set per area
  by `_finish`), never by a second set of builders. A shape or hub finish
  change rebuilds the shell (`_build_static`; the wall mirror only moves).
  The first shape, each room's first style and steel are free; any other
  (a finish bought once goes on any room) is a design
  unlock (`BaseUpgrades` track "Designs", `is_design`, never counted by
  `needs_count`), bought once with scrip and free to switch after (Caleb's
  call). The plan table in the middle of the hub (`HomeBase.PlanTable`) is
  the one place to change the plan: using it emits `plan_used` and
  `main.gd` brings the view in with the bench's view (`BenchView.target`
  "plan"), which mounts the customizer (`core/ui/plan_panel.gd`, a view)
  on the lectern's screen as a `WorldScreen` (`HomeBase.plan_screen`,
  forwarded with `WorldScreen.forward_mouse`): tabs for the layout, the
  rooms, the styles and the finishes, with whatever it points at shown on the hologram
  over the table (`plan_preview`, `plan_mark`). Only a pick asks for a
  change (`plan_change`, `room_placed`; `BasePlan.change` with a socket,
  "shape", "style:<room>" or "finish:<hub or room>"): `Profile.place_room` solo,
  `NetSession.place_room` online, decided by `StashService.place_room`,
  which checks the unlock is owned. An unlock is bought from the screen
  with a confirming click (`plan_buy`, `upgrade_requested`) and put in use
  once owned. A change is free, moves nothing in or out of the stash and is
  allowed while deployed. A new room
  needs a socket for it, not a spot in the hub. Room names are a plate over
  each doorway (`_name_plate`); the base has no banner and no other signs.
  Helmets sit on the helmet shelf over the armor stands in the gear hall.
  Every weapon goes on the one armory rack (`BaseLayout.ARMORY`, Caleb's
  call): its sections hang on the armory's walls (`HomeBase.in_armory`).
  Each weapon hangs on a lit mount (`HomeBase._build_mount`). The gunsmith
  bench and the fabricator beside it stand in the workshop
  (`in_workshop`), a room of their own, in the starter bunker too. The
  locker stands in the hub by the way out. The bench holds one gun at a
  time and nothing else is on show there (Caleb's call: no pegboard of
  attachments). At rest it is the primary (its rack pegs stand empty) with
  its attachments on; using it (`HomeBase.Bench`) emits `bench_used`, and
  `main.gd` brings the view in to it (`core/ui/bench_view.gd`, a camera and
  input like `WorldScreen`, no overlay): the wheel turns through your guns
  and then each attachment slot's choices, each shown on the gun and the
  bench card at once, a click picks, a right click steps back, Esc leaves.
  The bench state (`bench_row`, `bench_picking`, `bench_choice`) is view
  only; only a pick asks for a change, through the same `equip_requested`.
  A new kind of weapon gets a rack
  section there, not a display of its own elsewhere in the room. In your own base
  you always wear your loadout, and what you equip goes straight on (Caleb's
  call: no suit-up step): `HomeBase.suit_up`, run when the base opens and
  whenever `show_gear` brings a changed `suit_kit()`, dresses the player
  where they stand with `Loadout.refit`, weapons locked: the same actor,
  only the changed pieces swapped, so they keep moving (a new actor on every
  equip was Caleb's equip stutter). Only with no player standing does it
  make a new actor and emit `player_replaced` for `main.gd` to hand it the
  controller. Likewise `show_gear` rebuilds only the displays whose plan
  changed (`HomeBase._rebuild`'s `plan_key`), never every model in the
  room; measure with `equip_bench.tscn`. A visited base
  never dresses you. Every base has a mirror on its wall
  (`HomeBase.wall_mirror`, the phone's `Mirror` with `wall_mounted`, drawn
  only while its viewer is in front of it; it shows plain glass until its
  view has drawn, never the noise of an empty one). The hub keeps the deploy
  area (the wall mirror, with room in front to open a portal) along the
  front wall right of the exit (`HomeBase.deploy_span`), the plan table in
  the middle (Caleb's pick) and the rest of the floor clear. The shell is
  steel, never bare rock: plated floors, ribbed wall panels and a ceiling
  grid (`HomeBase._floor`, `_wall`, `_ceiling`; a trim stands off a wall's
  face, never on it, or the two shimmer), so a new space builds with
  those. Bikes park in the garage (`HomeBase.in_garage`). Down the corridor
  behind the hub, between the back rooms (`in_corridor`, `range_from`), is
  the firing range (`HomeBase.in_range`), which the plan never moves: the player's weapons unlock only there and
  never run dry, and `HomeBase` scores shots from each gun's `fired` signal
  against its `RangeTarget`s, which stop shots like walls; the score is
  written on a board hung over the lane, never on the screen. Nothing on the
  range goes through `Combat.deal` or pays mastery, because nothing there is
  real damage; never add an Actor target that takes some.
  The starter bunker has no range: the same door opens on a small test
  lane (`HomeBase._build_test_lane`, `in_lane`), 3 m by 15 m, a counter and
  three plates at 4, 8 and 12 m that drop and pop back up, a hit counter on
  its end wall, sealed at the far end by the firing range's bulkhead.
  Buying the range removes the lane. Nothing there is real damage either.
  Past the range's far end is the flight course (`HomeBase._build_course`,
  `in_course`): a tall lit hangar, walled and roofed so nobody flies out
  (Caleb's call), its roof over every rig's ceiling and past
  `Actor.roof_reach` of it, so it never flies as indoors, with a climb tower (and a ramp for wings), a gap to a second
  tower and a sprint, timed by `_tick_course` from the player's position
  alone and written on its board, never on the screen.
  The base grows with the account's upgrades (`core/base/base_upgrades.gd`,
  static rules like `Economy`): a list of owned upgrade ids kept beside the
  stash and scrip (`Profile.base_upgrades` solo, the account's online, sent
  in the snapshot), never in the stash. `HomeBase.show_gear` takes it as its
  third argument; none is the starter bunker. `BaseLayout.spots(kind,
  upgrades)` is how many spots a display kind has. Every room stands from
  the start in its small form (`small_depth`, behind a sealed wall) and
  its upgrade (`BasePlan.ROOMS[room]["opens"]`, `room_open`, `room_depth`)
  opens the rest of it wherever it stands; `HomeBase` offers what is not
  owned (`_build_gates`: a post in each small room, the range's slab at the
  test lane's end, tags on the bench) as a `Bulkhead` with its price on it
  in the room.
  Using one twice emits `upgrade_requested`; `main.gd` buys through
  `Profile.buy_upgrade` or `NetSession.buy_upgrade`, and only the server
  decides online (`StashService.buy_upgrade`). An upgrade never adds combat
  power or storage. A new room or feature for the base goes behind an entry
  in `BaseUpgrades.UPGRADES` ("ready": false until it is built) and is gated
  in `_build_gates`, not built for everyone. Dev mode keeps the base full.
  Using a display only emits `equip_requested`; `main.gd` applies it through
  `Profile` or `NetSession.equip`. Like `Raid`, `HomeBase` has no camera, HUD
  or input code, and its displays are greybox shapes that `Look` dresses
  (any node with the meta `display_item`).
- The new player's tour (`core/progression/onboarding.gd`, static rules on
  a small dictionary in `Profile.onboarding`, run by `main.gd`'s "new
  player's tour" section): a handler contact messages a new player on the
  phone (`Phone.add_local_message`, kept on the phone only, so it works
  offline), one step at a time, and the step's objective is a small line on
  the watch card (`Hud.Wrist.objective`) and the visor glass (`Hud.objective`,
  drawn by `VisorHud._draw_objectives`), never an overlay. Steps finish on the
  action itself, reported by `main.gd` as events (`_tour_event`) and as what
  is already true (`_tour_check`), never on a button. It is a view of the
  player's own progress: it never locks, unlocks or hands out anything, and
  a server never reads it. It names worlds by what they are (`Onboarding.names`),
  never by id. A save from before it starts it only if nothing was played or
  equipped. Settings' System tab skips or replays it, and dev mode never
  runs it. A new step is an entry in `Onboarding.STEPS` and an event reported
  where the action happens.
- The game opens in the world, never on a menu screen. Solo it boots into the
  home base; online, joining a server puts you in its plaza, and a world's
  lobby is the home base again on the server's stash. The base's door goes
  straight out to the plaza with no screen (`main.gd head_out`): it joins the
  server it remembers (`Profile.home_server`, set by a join from the phone's
  Servers app) or
  starts one here that runs every world, since worlds are chosen at the
  plaza's gates, never before going online. Travel never strands you on
  the travel screen: a server of your own moves to free ports when an old
  one still holds them (`Main.free_host_port`), stops itself once the game
  that started it stops touching its heartbeat file (`--heartbeat`,
  `HEARTBEAT_STALE`), and is given `HOST_JOIN_DEADLINE` to let you in
  (watched every second, a stopped server noticed at once) before it is
  started once more and then given up on; a deploy that never arrives
  fails after `DEPLOY_TIMEOUT`. Every failed trip ends in `go_home` with
  the reason. `Hub` (`core/ui/hub.gd`)
  is never a main screen: it holds the screens that the base's stations
  (`HomeBase.STATIONS`, sections in `Hub.STATIONS`) show, and the travel
  screen shown while connecting. A new menu feature gets a station (or a
  phone app), not a button on a front screen. `main.gd go_home` is where
  every "back to the menu" path ends.
- Menus live in the world (Caleb's rule: as few flat menus as possible). A
  screen you use goes on a `WorldScreen` (`core/ui/world_screen.gd`): a panel
  in the room that shows a `SubViewport` and forwards the mouse and keys to
  it, with the view moving in to face it while in use. `Main` keeps the hub
  in `hub_screen` and mounts it on the used station's `Station.screen`. Do not
  add full-screen panels or overlays; information about a thing goes on or
  next to the thing (a `Label3D` tag, a sign) or into the phone. The HUD is
  for the crosshair, prompts, hit feedback and brief notices.
  A screen that lists items (the trader and the Concourse's storefronts,
  the locker, the fabricator, insurance, the market kiosk, the records
  board's stash) puts an `ItemCard` (`core/ui/item_card.gd`, view only)
  beside its list: the item pointed at, its model in a small lit window
  that stays still until dragged (`ItemCard.Preview`), its kind, what it
  is for in plain words (`about_text`), its numbers read off its stats
  (`facts`) and the screen's own notes (price, what you are short of).
  A new list hands each row over with `card.track(row, id)`; a new kind
  of item gets a line in `ItemCard.KINDS` and its facts. Check by eye with
  `visual_check.tscn -- <dir> --panels-only`. Those screens wear the
  terminal style (`core/ui/terminal_style.gd`, view only): the station
  screens (`Hub`) and the Concourse's terminals (`Main.ShopView`) set its
  `theme()` on their root, stand on its `Backdrop` (a lit terminal's
  glass: grid, scanlines, a slow sweep, amber corner brackets) and call
  `dress(root)` once built, which lights every title as a heading. Plates
  have cut corners (`TerminalStyle.plate`), amber where you can act, cyan
  where something is shown; a new screen of this kind uses them, never
  plain boxes.
- The watch and the phone split the job (Caleb's rule, revised: the watch no
  longer carries vitals, heat and ammo; see DESIGN.md section 3). Vitals,
  flight heat and ammo are always in view on the visor and the gear (health
  arc, gun display, pack screen), so no key is needed to see them. The
  holographic watch (`Hud.Wrist`, raised with X) is for the things you choose
  to do in action: vehicles, the heavy weapon, artifacts, sign-out, banking,
  the map and pings, landing choices and the pack. The phone is for
  settings, talking to friends and players, and information (news, the war
  feed). A new in-raid action goes on the watch; a new social or info
  feature is a phone app. The watch is a card-sized hologram of icons in
  three tabs (`Hud.Wrist.TABS`, `TAB_SLOTS`, `SLOTS`; DESIGN.md section 3):
  Summon (weapons, vehicles, artifacts, the pack, with the pack's line under it),
  Status (map, standing) and Mission (portal, contract, ping, sign-out).
  The map icon, while read, draws a small holographic map beside it
  (`Hud.map_marks`, `Card._draw_map`): only what the player is told, never
  other people. The Status icons open with a click like a carousel (Caleb's
  call): the map rises over the card as a tabletop hologram with the
  ground's relief (`Wrist.show_table`, `Hud.map_relief`), the wheel turns
  through the nearest depot, gate outpost and strongpoint, the hot zone,
  the event and the pings (`Hud.map_targets`), and a click sets the picked
  one as a waypoint only you see (`Hud.waypoint`: a column of light, a mark
  on the visor's strip and scope, cleared on arrival); Standing turns
  through three pages (`Hud.STANDING_PAGES`: at stake, safe, this life).
  The pack is an icon on the Summon tab (`Hud.pack_slot`) that opens as a
  list of what is carried with each item's worth; a click on gear in it
  puts it on through the same summon (`PlayerController.take_picked_from_pack`,
  `Loadout.wearable_from_pack`: weapons, helmets, frames, flight rigs and
  ability chips, never an artifact or attachment). `Raid.swap_worn` puts
  on a rig (`Loadout.wear_rig`, on the ground only, keeping the old rig's
  heat, the frame's scaling put back round it) or a chip
  (`Loadout.wear_ability`, starting on its cooldown) as it does a helmet,
  and clients follow through `NetSession._worn_changed`. An opened icon's list or
  page takes the card's right side (`Card._draw_panel`). A click on Sign out starts or cancels it like L
  (`PlayerController.is_on_sign_out`), and its icon carries what this life
  has banked (`Actor.banked_*`, sent to the owner only, `NetSession._banked`).
  Down, the death report's landing choices are picked with the wheel and a
  click (`drop_pick`, `click_landing`); the number keys and Enter still work. The open
  icon shows one short line, and controls are glyphs (wheel, click, key
  cap), never words. The mouse wheel moves across the card tab after tab
  (`PlayerController.watch_focus`, `step_watch`; Caleb's call) over the
  main icons only. Two levels (Caleb's call): a click on an icon that holds
  several things (weapons, toys, artifacts, portal places: `watch_entries`)
  opens it (`PlayerController.watch_open`), the wheel then turns through
  them and stops at the list's ends, a click acts and a right click backs
  out (`close_watch_icon`); a closed icon shows the click glyph instead of
  the wheel (`Hud.mark_open`). The mouse only looks. While the watch is up the
  wheel never switches weapons. A new watch feature is a new slot on a
  tab, not a new line of text; something that only matters now and then is
  a pop-up line (`Wrist.show_card`'s `popup`), not a slot. The summon
  carousel (Caleb's call) shows only what is carried, never the stash:
  `Hud.weapon_entries` is the weapons worn then in the pack, and picking
  one in the pack asks the authority's `Raid.summon` (`NetSession.summon`
  online), which swaps it with the one worn in its slot through
  `Loadout.swap_weapon` (the old one goes in the pack with its rounds,
  `Actor.stowed_rounds`; clients copy it from `Actor.weapon_swapped`). It
  takes `Loadout.summon_time` by weight, during which the weapon cannot be
  used (`Actor.materialize_left`) and is drawn digitizing in on the one
  body (`ActorSkin._update_materialize`), then the watch rests
  (`Loadout.summon_cooldown`). A materialize is heard (`Sfx` "summon" and
  "store", played by `ActorSkin._update_materialize`); while the watch
  rests its face breathes amber (`Wrist.resting`), a refused pick buzzes
  and a chime says it is ready. Storing is the summon in reverse: a click
  on the weapon in hand asks `Raid.store` (`NetSession.store` online),
  which puts it in the pack with its rounds at once and starts
  `Loadout.store_weapon` (clients copy it from `Actor.weapon_stored`): the
  weapon fades out of the hand over `Loadout.store_time`
  (`Actor.dematerialize_left`, the same `_update_materialize` light run
  backwards), unusable and with no switching, then `Actor._tick_store`
  takes it off and leaves the hands empty. It needs room in the pack,
  never stores a heavy weapon, and does not rest the watch. At home it
  unequips the slot. The squad ping (`Raid.ping`, `pinged`) goes
  only to the pinger's side, like a visor tag. In third person the
  card rises off the worn watch with a glow on the arm (Caleb's feedback):
  it stands just past the character (`Wrist.tp_depth`, `tp_behind`), so the
  body passes in front of it and it reads as coming from the watch, beside
  the head clear of the crosshair, a third of the view tall, backed but still see-through (a hologram, Caleb's call)
  (`_tp_spot`, `_tp_size`, `tp_backing`); the arm and its
  pose stay the same, only where the light lands differs. It stays close to the body
  (Caleb's feedback): its lower edge sits just over the watch as the camera
  sees it (`_over_wrist`, `tp_over_wrist`), level with the shoulder, and
  only its bare right margin may tuck behind the head (`tp_tuck`), never
  its text, so the light rises from the wrist up into the card,
  with bands running out along it (`Wrist.BEAM_SHADER`, `_draw_beam`),
  never slanting down into it (Caleb's feedback). The weapon and toy
  holograms over the card are drawn at `tp_rows` of their first-person size
  and lifted by as little, smaller still where the top of the view is near
  (`_tp_row_scale`), so they stay in frame while the card keeps its size
  (Caleb's feedback). Vitals go on the card only where there is no visor
  to show them (no helmet). The watch works in the home base
  too (`BaseHud.wrist`), its card saying what each icon holds for the next
  deploy (`Hud.base_watch_slots`), and there its Summon tab is the whole
  collection (Caleb's call): every weapon and vehicle owned
  (`HomeBase.watch_weapons`, `watch_vehicles`). A vehicle thrown at home
  unpacks to be ridden in the base (`HomeBase.throw_toy`, `pack_vehicle`;
  `Vehicle.local_only`, since no server runs it) and a weapon picked is
  equipped through `equip_requested`. Out in a world summons work
  everywhere, the plaza included. Raised, the wrist comes up in front of
  the model's eyes as the camera has them (`WeaponArm.watch_point`, from
  `ActorSkin.eye_point`, so it stays put on the run and in view crouched),
  close enough to stay in the arm's reach, so it is in view in
  first person wherever you look, and the forearm rolls so the face, worn
  on the back of the wrist (`Hud.Wrist.FACE_AXIS`, out on the skin by
  `wrist_skin` and depth tested like anything worn, so a gun or hand in
  front of it hides it), looks at the eyes
  (`WeaponArm._face_watch`). From the eyes the card opens just over the
  face, sized to read like a card at arm's length (`fp_card_reads_at`). Check it by eye with
  `visual_check.tscn -- <dir> --watch-only` (`--base-watch-only` for just
  the base).
- Blueprints and crafting (`core/progression/crafting.gd`, static rules like
  `Economy`, DESIGN.md section 10). A blueprint is an item tagged
  "blueprint": loot while carried, learned when it reaches a stash
  (`Crafting.learn` moves it to the account's known list:
  `Profile.blueprints` solo, the account's online, in the snapshot), and
  never lost after that; a spare copy stays in the stash as a trade good.
  Anything that hands an account items must go through
  `Profile.add_to_stash` or `StashService.Account.add_items`, never append
  to a stash, or a blueprint is stored instead of learned. A recipe
  (`Crafting.RECIPES`) makes one item from a known blueprint for scrip,
  parts and, for a higher Mk, the item `upgrade_data`; what it makes is
  ordinary gear. Crafting is done at the fabricator on the gunsmith bench
  (`HomeBase.CraftConsole`, the hub's "craft" section, `craft_panel.gd`):
  `Profile.craft` solo, `NetSession.craft` online, where only
  `StashService.craft` decides. Each world has its own job (DESIGN.md
  "Frostline"): the war's blueprints and most upgrade data come from the PvP
  world (`WorldDef.roll_crafting_loot` and its chances, 0 by default; a
  world's own loot tables), while the expedition world pays the parts every
  Mk2 and Mk3 needs (`Crafting.MK2_PARTS`, `MK3_PARTS`: Cryo Core, Glacial
  Alloy, Engine Coil), a trickle of upgrade data and its own blueprints,
  tagged "expedition", which make new options only, never a higher Mk, and
  which `roll_crafting_loot` never hands out. Its slow route to the war's
  blueprints (Caleb's call) is rare: the relay's `roll_crafting_loot` at a
  low chance, its warlords' `warlord_blueprint_chance` and the expedition
  weeklies' blueprint. Cold-weather gear is data: a
  frame's "insulation" stat keeps out that share of the cold
  (`Raid.insulation_of`). A new craftable is a recipe row and, if it needs
  one, a `_blueprint` item. Costs are placeholders.
- Money (`core/economy/`): the rules live once, in `economy.gd` (static, like
  `StashRules`), shared by `Profile` and `StashService`. Online, `scrip`
  lives on the server's account and only changes there: through
  `StashService.buy` / `sell`, the payout in `settle`, or `change_scrip`
  for other server systems. A client never sends a price or an amount.
  Shops are tag-driven: an item is stocked if it has the `vendor` tag and one
  of the shop's tags (`shop_db.gd`), and `Economy.is_shop_item` refuses
  anything above Uncommon, so rare gear stays loot-only. The one exception
  is the plaza's back room (`Economy.BLACK_MARKET`, a shop with "stall" in
  `ShopDB`, built down an alley by the plaza map's `_build_stall`): two
  Rare pieces a day by the date (`black_market_stock`) at
  `BLACK_MARKET_MARKUP` times their value; every price a shop charges is
  `Economy.price_in(shop_id, id)`. Keep every sell
  price below its buy price, and keep run payouts small next to loot: scrip
  must come from getting loot home, so full loot stays the stake.
- Scrip is what a life pays, and it is at stake. The `Raid` pays it
  (`_pay_scrip`, amounts in `Economy`) into `PlayerState.scrip`, copied to
  `Actor.scrip` for views. A death moves it into the bag
  (`LootContainer.scrip`); a depot moves it to `scrip_banked`. It reaches an
  account only through the result (`scrip`, `scrip_banked`) and
  `Economy.payout`, never directly, and nothing is paid for kills alone.
- Contracts (`core/economy/contracts.gd`, static rules like `Economy`): the
  board's jobs are data in `Contracts.JOBS`, offered by the date so every
  machine agrees, and held on the online account (`Account.contracts`, in the
  snapshot); only the server takes, drops, rerolls (`StashService.contract`,
  asked with `NetSession.contract_ask`) and pays them, in `settle`. A life's
  counters are the `Raid`'s (`_count`, authority only, never in a safe zone
  or where gear is not at stake) and travel in the result's `tally`; the
  owner's copy for the watch is `Actor.tally`. Only a sign-out counts, and no
  job may count player kills or reward signing straight out. A new job is a
  `JOBS` entry; a new stat is a `_count` call where the event happens.
  A world adds jobs of its own with `WorldDef.contract_jobs` under its
  `WorldDef.contract_tag` (Frostline's "expedition"): every lookup goes
  through `Contracts.jobs()`, never `JOBS` alone, the board offers one daily
  and one weekly per tag beside the general ones, and a tagged job counts
  only a result whose "contract_tag" matches (`Contracts.counts_in`). Stats
  include `item:<id>` (brought home), `kills:<faction>`, `bosses`,
  `cache:<source>` (once per fill, `LootContainer.looted_by`), `banks` and
  `hold_seconds` (stood in a site your side holds, `Raid._count_holding`;
  Ashfront's "warzone" jobs).
- The player market (DESIGN.md section 10, "Two worlds, one loop"): rules
  once in `core/economy/market.gd` (static, like `Economy`: what trades, the
  price band, fees, the daily cap; Mk3, heavy weapons, artifacts and relics
  never trade), the board in `core/economy/market_service.gd`, shared by
  every session of a server like the `ClanService` (`NetSession.market`).
  It moves goods only through six ledger calls on the `StashService`
  (`count_of`, `scrip_of`, `take_items`, `give_items`, `change_scrip`, and
  `transaction`, which every listing charge and every sale goes through so
  no trade is half done); it never writes an account itself. On official
  servers the board runs inside the account service, beside those accounts
  (`AccountService.market`), and a session only passes the request on. Listed items are held by the
  board, its file is written before the accounts' transaction so a crash
  can lose a listing but never copy one, and
  a client only asks (`NetSession.market_ask`) from the Exchange kiosk in
  the plaza and shows `market_state`. Trading needs a safe zone and no
  deploy; there is no solo market.
- Furniture (`furniture`, small pieces also `decor`) and clothing
  (`cosmetic`, with an `outfits` stat of customizer outfit ids) are ordinary
  stash items that fit no loadout slot, so they never go on a raid.
  `Economy.unlocked_outfits(stash)` lists the outfits a stash unlocks.

- The arena (`core/arena/`) is a venue, not a raid world: `ArenaVenue` is a
  `WorldDef` that is never in the registry, has `gear_at_risk` off, and
  returns `Arena` (a `Raid` subclass) from `new_raid()`. Nobody loses gear
  there: `StashService.deploy` hands out the kit without taking it, nothing is
  settled, nothing drops, and fighters yield at `HealthComponent.min_health`
  instead of dying. Only the two fighters of a running bout may hurt each
  other (`Arena.may_hurt`). Results, wagers, stakes and tournament pots are
  decided only by the authority's `Arena` and paid through `Arena.bank`;
  a client only sends `Arena.ask` requests and shows the board the server
  sends. Scrip changes only through `StashService.change_scrip` online and
  `Profile.change_scrip` solo. The Pit's moving parts (the tunnel doors and
  the rising barriers) are worked out from the bout's phase and fight clock
  alone (`ArenaVenue.doors_open`, `barrier_raise`), which the `Arena` hands
  the map every tick (`set_stage`) on every machine, so they need no messages
  of their own. Static venue boxes are merged into one mesh per material.
  Every bout and tournament has rules (`Arena.RULES`, DESIGN.md "Gladiator
  arena"): "open", "blades" or "blades_boots". `Arena._apply_rules` holds
  them on the fighters every tick on every machine, from the bout on the
  authority and the board's "rules" and "nodes" on a client: no gun is
  drawn (`Actor.guns_locked`, which puts one in hand away for the blade)
  and a barred rig stays jammed (`FlightRig.jam`, renewed by `RIG_HOLD`).
  A gladiator for a blades bout is picked by its seed
  (`ArenaVenue.gladiator_has_blade`), so clients build the same one. A
  tournament under blade rules is the Blade Tournament: its champion's
  weekly prize (the `trophy_blade_champion` item and a chance at an
  artifact) goes through `Arena.Bank.prize`, once a week per account
  (`arena_prize_week`): `Profile.arena_prize` solo, the sure
  `StashService.arena_prize` online, which checks the week again.

- The race world (`worlds/meridian`, DESIGN.md section 9) is run by `Race`
  (`core/race/race.gd`, a `Raid` subclass from `WorldDef.new_raid`), on a
  map that offers `race_track()` (a `RaceTrack`: the centre line, gates,
  start slots, `keep_to` lines; a map with several offers `race_tracks()`
  too, read into `Race.circuits`, and a run is on the one nearest the
  machine got on, `Race.track_near`, with its own grid and gates; each
  board row carries its "track", and a second track's gantry, arches and
  board carry the meta "track"). Nothing is at stake there:
  `WorldDef.gear_at_risk` off clears every result's loot and kit lists
  (`Raid._finish_player`) and `Profile.checkout_loadout` takes nothing,
  `weapons_free` off locks weapons and makes `can_damage` refuse, and
  `portal_home` keeps the portal home on offer. Racers bring no vehicle:
  the machines wait in the pit bays and race on their race profile
  (`Vehicle.race`, `apply_race_profile`, `ItemDB.RACE_*`), never their
  combat tuning. Only the authority judges a run (grid, lights,
  `Vehicle.held`, gates by `RaceTrack.cross`, laps, the off-track rule, the
  board); a client gets its own run (`NetSession._race_run`,
  `Race.remote_run`) and the board, holds its machine for the lights from
  that, and asks with `NetSession.race_request`. Live races are the
  track's `Race.heats` (authority only; clients get `heat_view` through
  `NetSession._race_heats`): asked for with the race icon's "race" pick,
  formed for `FORM_TIME` (`ALL_IN_FORM` once everyone here is on it) with
  AI racers on the grid from the start (`_fill_grid`, a person who joins
  takes one's place, `_bump_ai`), filled to `GRID_SIZE`. While anyone is
  in the world a track nobody rides runs an AI-only race (`Heat.ambient`,
  `_tick_ambient`, `AMBIENT_FIELD`; Caleb's ask, so the world is never
  dead), which moves no league; asking to race there calls its field to
  the grid (`_call_to_grid`), and an empty world runs none. A person who
  gets off out on the track is set down on pit row (`_off_machine`).
  Prompts name the interact key from the `InputMap` (`RaceView.key`).
  An AI racer is a bot (meta "race_ai") on a machine of its own, driven
  only through its `ActorCommand` by a `RaceDriver`, which is also the
  bench's driver; never give one speed, grip or a rule a player lacks, and
  never put its laps on the board. The league (`core/race/race_league.gd`,
  static rules like `Contracts`) is kept on the account (`Profile.racing`,
  `Account.racing`, in the snapshot and `StashRules.CARRIED`) and moved
  only by a live race's close: the authority's `Race` sends each person's
  finish to its `league_bank` (`StashLeagueBank` online, a sure
  `record_race` call; `ProfileLeagueBank` solo), where `RaceLeague.apply`
  moves the rating and pays the capped scrip. A grid's AI are the named
  rivals of its best rider's league; their radio lines go only to the
  racer they are said to (`Race.radio`, `NetSession._race_radio`) and are
  drawn on the visor (`Hud.comms`, `VisorHud._draw_comms`). Ghosts are the
  authority's too: `Race` records each person's lap (`Run.recording`) and
  a counted lap faster than their best there goes to the same bank
  (`keep_ghost`: online `StashService.keep_ghost`, a sure call, kept in a
  file beside the account with only the time in `RaceLeague`'s "bests";
  solo `Race.GHOST_PATH`). Which ghost a racer chases is the race icon's
  pick (`Race.GHOST_PICKS`), asked with `Race.want_ghost` (online
  `NetSession._race_ghost_ask`, where the server finds a friend's among
  the phone's saved contacts, `_friend_ids`) and played by `RaceView`;
  friends' best times reach the pit boards the same way
  (`Race.friend_bests`, `NetSession._send_friend_bests`). Race control's
  desks (map markers "race_desk", metas "track" and "machine") sign a
  person onto the next race on a fresh machine (`Race.sign_up`, asked as
  "signup:<track>:<machine>", which the authority decides, standing within
  `DESK_REACH`); a desk with no machine is a watch desk, `RaceView.watch`,
  a camera only. A done run is guided to the track's `RaceTrack.pit`
  (`Hud._guide_to_pits`) and the authority sets the racer down there
  (`Race.set_down`, within `PIT_RADIUS` or after `PIT_TIME`); a machine a
  desk made goes when its racer gets off. Tuning kits
  (`RaceLeague.KITS`, kept per machine in the league state's "tunes",
  unlocked by league) are fitted at a pit bench (map markers "race_tune",
  `Race.tune`, asked as "tune:<machine>"; online the sure
  `StashService.tune_race`) and put on a person's machine for their run
  only (`Race.fit` at `start_run`, stock again at `retire`); a client fits
  the kit its run view names so it predicts the same. Every kit must keep
  its machine inside the class's 3% on every track
  (`race_bench.tscn -- --tunes`). Where a road runs over
  another (Skyhook), `RaceTrack.locate`'s full search counts height and a
  gate is passed only within `GATE_HEIGHT` of it. The stands, crowd
  (`Crowd`, `assets/shaders/crowd.gdshader`), skyline and works are
  decoration (`worlds/meridian/stands.gd`, `skyline.gd`, `works.gd`),
  merged into one mesh per material (the works per material per block,
  every lit and painted shape in one vertex-coloured material each). The
  works fill the salt out to the dunes (`GROUND_HALF`) and keep off the
  roads and what `WORKS_KEEP_OUT` lists; a new stand or set piece goes
  in that list. The lights, splits, board
  text and the ghost being chased are `RaceView`, a view. In a race world the
  watch's contract icon is the race icon (`Hud.race_slot`, `glyph`).
  Every machine in a class stays within 3% of the class average round
  every track: check with
  `godot --headless --fixed-fps 60 --path . res://tests/race_bench.tscn`
  and tune the race profiles, never the combat stats.

## Conventions

- A helper used by a single script is an inner class of that script, not a new
  `class_name` file.
- New `class_name` scripts only resolve after Godot rescans the project. The
  `Boot` autoload (`core/boot.gd`) detects a stale class list, runs the import
  step and restarts once. Keep `Boot` first in the autoload list and free of
  any project class.
- Typed GDScript, tabs, `class_name` for anything reused. Tuning values are
  plain `var`s at the top of the class.
- Gameplay shapes are built in code and dressed by `Look`. Hand-built `.tscn`
  scenes are fine later; keep the map contract.
- Every gameplay feature gets checks in `tests/test_runner.gd`.
- A running game logs no errors: one a frame is enough to sink the frame
  rate. `tests/error_spam_tests.gd` watches an Ashfront session with an
  `OS.add_logger` counter, and `tests/screen_sweep_tests.gd` does the same
  in the base and every world while opening every phone app, settings tab,
  watch icon, station, the bench and the plan table; fix the cause of
  anything they catch, never silence it. A spring stepped by `delta` is stepped in short slices (a
  long frame throws it off), and a deferred call or timer that outlives
  the node it acts on is bound to that node (`node.queue_free`, an
  instance id), never a lambda capturing it A loop over a
  dictionary or list that can still hold a freed node (bodies a view
  tracks, bots given orders) types its variable `Variant` and checks
  `is_instance_valid` first: assigning a freed node to a typed variable is
  an error that stops the game in the editor's debugger (the third-person
  peek fade's "freeze").

## Verify before committing

The project targets Godot 4.7 (what Caleb runs, and what CI uses).

```
godot --headless --path . --import
godot --headless --path . res://tests/test_runner.tscn   # must exit 0
godot --headless --path . res://tests/test_runner.tscn -- --only online   # one group
godot --headless --fixed-fps 60 --path . res://tests/test_runner.tscn -- --tier offline   # fast, ~1 min
godot --headless --path . res://tests/test_runner.tscn -- --tier net --shard 1/3   # a third of the online groups
godot --headless --path . res://tests/battle_bench.tscn -- --bots 150 --players 32   # server cost of a big battle; exits 1 over the 16.7 ms budget
godot --headless --fixed-fps 60 --path . res://tests/frame_bench.tscn -- --look --seed 7 --save main.json   # then the same with --against main.json on a change (fails past --tolerance, 0.15), --max-hitches for frames over 50 ms
godot --headless --path . res://tests/server_bench.tscn -- --plaza 10 --per-world 7 --arena 4   # the whole server at once: tick time per session, travel against 3 s
godot --headless --path . res://tests/server_bench.tscn -- --cluster --plaza 10 --per-world 7 --arena 4   # the same with one program per world; times a trip made on a connection opened ahead
godot --headless --fixed-fps 60 --path . res://tests/feel_bench.tscn   # how each rig answers, in numbers
godot --headless --fixed-fps 60 --path . res://tests/duel_bench.tscn   # how each enemy type fights a reference player (DESIGN.md "Enemy balance")
godot --headless --path . res://tests/gun_bench.tscn   # every gun's time to kill by range and armor (DESIGN.md "Gun roles")
godot --path . res://tests/equip_bench.tscn -- --walk   # what an equip costs in the base, and whether you keep moving
godot --headless --fixed-fps 60 --path . res://tests/race_bench.tscn   # lap times per race machine, flags any 3% off its class
```

CI (`.github/workflows/tests.yml`) runs the suite in two tiers. The offline
tier (every group that never starts a server) runs on every push with
`--fixed-fps 60`, which skips the real-time waits. The online tier (groups
that start a server, found automatically, see "Picking groups for CI" in
`tests/test_runner.gd`) needs real time and runs in 3 parallel shards, but
only on main, on PRs that are ready for review, and on draft PRs with the
`full-ci` label. So before marking a PR ready: merge the latest main, add the
`full-ci` label, and wait for "Tests passed" to report the full suite (its
summary says "Full suite passed"; on a draft without the label it says only
the offline tier ran). A group that starts a server must still pass when run
alone (`-- --groups name`), since shards split the groups up. After adding a
slow group, refresh `tests/group_times.json` with `-- --tier net --times-out`
so the shards stay balanced; a missing entry just counts as an average group.

To see it rendered (needs a display or xvfb):

```
godot --path . res://tests/visual_check.tscn -- /some/output/dir
```
