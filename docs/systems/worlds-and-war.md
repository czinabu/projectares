# Worlds and the war

Rules for death rules per world, renown, the war director, weather, the planet kit, terrain, strongpoints, drops, world heat, shelling, world events, the life log and risk zones. These are part of the rules in `CLAUDE.md` that must not be
broken: read this file before changing anything it covers, and keep it up to
date in the same PR.

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
- World events (`Raid.event`, `start_event`, `end_event`): one at a time, on
  a timer the war speeds up, tuned by `WorldDef.event_interval`,
  `event_lifetime` and `warlord_escort`. A supply pod is an ordinary
  `LootContainer`; a warlord is an ordinary bot passed through
  `WorldDef.make_warlord` (clients build the same one from `Raid.warlords`,
  so keep that hook free of randomness). Event bots are extra and are never
  respawned. Loot that should follow the war comes from
  `WorldDef.roll_war_loot(source, rng, intensity)`, not `roll_loot`.
- The life log (DESIGN.md "Challenge and balance data"): the authority's
  `Raid` records every finished life (`Raid._log_life`, `LifeLog`): where,
  how, what killed them and how many bots were after them, to JSON lines
  under `LifeLog.directory` (`main.gd` sets it; empty writes nothing, as in
  the tests). It is read only by `tests/life_report.tscn`, never in play.
  A new thing worth tuning by is a new field there, not a second log.
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
