# Worlds and the war

Rules for death rules per world, renown, the war director, weather, the planet kit, terrain, collision, strongpoints, drops, world heat, shelling, world events, the life log and risk zones. These are part of the rules in `CLAUDE.md` that must not be
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
  whiteouts, "rain" for the Spore Marsh's rain storms, "sand" for the Dune Sea's
  sandstorms, which also bury salvage fields, see `dunes.md`) has storms crossing its map one at a time, a `Weather` cell
  (`Raid.weather`) on `weather_path`, tuned by `WorldDef.weather_*`. Only
  the authority ticks it; a client is sent the cell
  (`NetSession._weather`) and only carries it on (`Weather.advance`).
  Anything a storm changes asks the cell where it happens, never a flag:
  bot sight (`BotBrain._find_target`, `sight_between`), scan reach
  (`Visor`), how far shots and footsteps carry (`Gun.shot_carry`,
  `BotBrain._find_target`), how fast guns foul (`Gun.foul_rate`,
  `fouling_at`, `weather_fouling`), gusts on a flying rig
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
  air round the camera and the wind. The wall is a front with no hard
  edge: two layers of a steep dome (`WeatherView.dome_mesh`,
  `storm_wall.gdshader`) that fade where seen edge on, are gone over the
  crown, go soft against the ground (the depth buffer) and thin from 80 m
  to 20 m from the camera, plus one draw of billows heaped round its
  shoulder and crown (`storm_billow.gdshader`, laid out with their own
  RNG). It stands at `WALL_REACH` (0.8) of the radius, inside the cell's
  soft edge, so the storm's haze has begun by the time the wall thins
  away; and it keeps out of the world fog (fading out from 700 m on its
  own) so a coming storm reads as a dark mass, never washed out. Check it
  by eye with `--storm-front-only` (`--cost` prints its GPU time). It
  also sets the map's "weather_here" meta, which blends `Look.atmosphere`'s storm mood in and lowers the fog floor
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
  `GameSettings.ground_smoke`. A map's far ring (`Planet.horizon`) is
  built from the same `PlanetTerrain` as the map's own ground (its `field`
  and all), or it stands over the map's edge; `smooth` blurs it for a
  ground of short, sharp features (dunes, terraces). Check by eye with
  `planet_check.tscn -- <dir> [type ids]`.
- Open ground is a `Terrain` (`core/world/terrain.gd`): a heightfield with
  collision and a mesh that knows nothing about any world. A map on one
  offers `ground_height(x, z)` and the `Raid` stands spawning actors on it
  (`Raid._stand`). A heightfield is a surface, not a solid: anything that
  moves an actor by setting its position (a blink, a teleport) must put the
  feet back on the ground, or the actor falls through. A map can leave
  rectangles of it open (`Terrain.holes`, on the sample lines, set before
  `collision_data` and `build`): no ground is drawn or stood on there,
  while `height_at` still answers as if it were whole (the marsh's
  Rootways go down through them). Ashfront's map
  (`worlds/ashfront/map.gd`) works its ground and navigation mesh out once
  per run and shares them between copies (`_shared`), so a new copy is cheap.
- Collision: nothing you can see standing in a world is a ghost you walk
  (or a bot walks, unseen) through. Collision is gameplay, so it is built in
  the map's gameplay pass on the server and the client alike, never by
  `Look` and never from a dressing RNG. A prop model that must be solid is
  placed with `SolidProp.place` (boxes cut to the model in
  `SolidProp.SHAPES`, the model hung inside only where `Look` is on); a
  piece the dressing draws gets its collision alone from `SolidProp.box` or
  a shape of its own, at the same place, worked out by a helper both passes
  share (Ashfront's `_wreck_engines`, Meridian's `_ramp_parts`,
  `skyline.gd`'s `booster_parts` and `SEARCHLIGHTS`). Put it under the
  map's navigation region before the bake, so bots path round it. Simple
  shapes (boxes, cylinders, convex hulls), never a trimesh where one will
  do. Litter you step over (a gas can, a backpack) stays decoration. Loot
  crates and base stations are on `Actor.LAYER_WORLD` as well as the
  interact layer; a dropped bag or scrip pile is not. People collide with
  vehicles (`Actor.LAYER_VEHICLES`). A mesh that is meant to be walked
  through (a zone's glow, a beam, plants, scenery past the rim) carries the meta `"walk_through"`
  on itself or a parent, its value saying why. `tests/collision_tests.gd`
  builds every world from `Worlds`, the arena and the home base with
  `Look` on and flags every mesh big enough to block a person, standing
  where one could walk, with no world collider through it; a new world is
  covered the day it is added. A scatter drawn as a MultiMesh is not
  judged (headless has no instance transforms), so a map whose scatter
  should block builds that collision itself.
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
- Encounter pockets (DESIGN.md "Enemy layout"): a world with
  `WorldDef.pocket_wake` keeps its "spawn_guard" markers asleep until a
  living player comes within range of a marker of the same "pocket"
  (marker meta "wake" overrides the range), checked every `POCKET_EVERY`
  by `Raid._tick_pockets`. A waking pocket stands whole or waits for room
  under `enemy_cap`, nearest first; its guards queue
  (`_pocket_queue`, their room kept by `_pocket_room`) and stand one a
  tick (`_stand_queued`), because a body's first dressed frame is dear on
  a machine that draws it (three in one frame were a 50 ms hitch on
  Caleb's PC). At the start, everyone near stands at once. Short of room,
  awake pockets nobody is fighting that every player is `POCKET_YIELD`
  further from sleep for a waking one, farthest first. A pocket nobody
  has been within range plus `POCKET_SLEEP_MARGIN` of for
  `POCKET_SLEEP_AFTER`, and none of whose guards has a target, sleeps
  (`_sleep_pocket`): its guards and their brood leave through
  `_remove_actor`, with no body, loot or respawn timer, and stand again
  whole. A fallen guard counts down `guard_respawn_time` asleep or awake,
  and in an awake pocket comes back only with nobody within
  `POCKET_REFILL_CLEAR` of its post. Pockets hold no room back from the
  army (`army_size`), and a world of pockets may have no army
  (`_fields_enemies`); `--bots 0` turns pockets off too
  (`NetSession`). Everything stays on the authority: clients see guards
  come and go as actors spawned and removed. Frostline, the Marsh, the
  Dune Sea and the Rift are worlds of pockets (`bot_count` 0); a map
  gives each guard of a group the same "pocket" (a place's name) and
  keeps a "spawn_bot" marker by it for events. `tests/world_pockets_tests.gd`
  holds each to pockets of 1 to 5 standing apart; `TestRunner.stand_pockets`
  stands every pocket for checks that want the whole garrison up.
- World events (`Raid.event`, `start_event`, `end_event`): one at a time, on
  a timer the war speeds up, tuned by `WorldDef.event_interval`,
  `event_lifetime` and `warlord_escort`. A supply pod is an ordinary
  `LootContainer`; a warlord is an ordinary bot passed through
  `WorldDef.make_warlord` (clients build the same one from `Raid.warlords`,
  so keep that hook free of randomness). A convoy (a world with
  `WorldDef.convoy_vehicles` and a map with `convoy_routes`, see
  `dunes.md`) is the third kind, and an airship (a world with
  `WorldDef.airship_vehicle` and a map with `airship_routes`, see
  `rift.md`) the fourth: `Raid.airship`, `_start_airship`,
  `_drive_airship`, its weak spots bots made with `_add_bot(..., p_boss)`
  so `WorldDef.equip_bot` builds them by their `boss` meta, its hold put
  down by `drop_spot_at`. Event bots are extra and are never
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
  second. A sea of lava is `WorldDef.molten_level` instead: anyone whose
  feet are under it, player or bot, burns four times a second whatever the
  zone rules (`Raid._tick_molten`). What anyone drops dying comes to rest
  where `Raid.drop_spot` says: on whatever is under them (they may have
  died in the air), and on top of any lava. Updrafts are
  `WorldDef.updraft_at` (docs/systems/rift.md). The `Raid` marks each bot with the zone it spawned in (meta
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
- Depots and gate outposts look like places, never like zones: no
  see-through boxes. A `Depot` builds its own greybox station (a deep pad
  that is the bank area, a solid uplink terminal at its back edge, local
  +Z, and a mast), which `Look._dress_depot` dresses: a lit rim round the
  pad, lamp posts at its corners, a screen saying what it does, and a
  pulsing beacon with a faint uplink beam on the mast to find it by. The
  pad's middle stays open (players and tests stand at its centre), and a
  map turns a depot with `_add_depot(at, back)` so the terminal backs onto
  a wall or away from a site. The terminal and mast are solid but not in
  the navigation bake (the depot is not under the nav region), so a bot can
  brush it; the pad, its rim and corner lamps are `walk_through`. An outpost's bubble is shown by its own
  walls and, across the open gate, a lit striped threshold laid on the
  bubble's radius between two emitter bollards, so the line is exactly
  where protection ends; the gate's sign hangs from a beam over the posts
  and reads on its front only (the rule outside, "leaving" inside), never
  floating or mirrored. Ashfront dresses its gates in `_dress_outposts`.

## Abandon

- `Raid.abandon` ends a life where it stands, for the watch's Abandon
  icon: a quick way out that is never a way to leave with the loot. It is
  a death in every way (outcome "died", cause "abandon", through
  `Actor.kill`): the world's death rule decides what drops (a bag, a scrip
  pile, or only the loot found where gear is kept on death), the insured
  item is recalled and salvage paid. The result carries "abandoned", and
  the game then goes straight home instead of offering a new life.
- If the player was hurt within `WorldDef.combat_time`, the last attacker
  (`PlayerState.last_hit_by`) is the killer, so abandoning never takes a
  kill, renown or a bounty from anyone.
- Only where `Raid.can_abandon`: out in a world where gear is at stake,
  alive, and playing the body (never a body a dropped connection left
  standing). Authority only; a client asks with `NetSession.abandon`.
