# Verge (formerly Project Ares): notes for AI sessions

Full-loot PvPvE war game in Godot 4 (GDScript). Each world is an endless
warzone, not a timed raid (see the endless warzone rule below). See README.md for the
layout and how to play. The roadmap is: Phase 0 bot-only prototype (done),
Phase 1 vertical slice (hub, loadouts, abilities, motorbike), Phase 2 online
PvPvE on a dedicated server, Phase 3 full Ashfront, Phase 4 a second world.

## The design doc

`docs/DESIGN.md` is the game design every thread builds against: the places,
the watch, the loadout, flight, heavy weapons, banking and sign-out, and
vehicles. `docs/design-gaps.md` lists what is built and what is missing.
Before building a feature, read its section. Where a rule (here or in
`docs/systems/`) describes today's code and the design doc describes a
different target (for example heavy weapons on the watch instead of racks),
build toward the doc and rewrite the rule where it lives in the same PR. Do
not settle the doc's open decisions without Caleb, and update the gap list
when a PR closes a row.

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
- `Raid` has no camera, HUD, or input code. It must keep working headless.
- The endless warzone. A `Raid` is one running world and it never ends: no
  timer, no exits, no restart. It keeps itself alive (`_tick_bots`,
  `_tick_caches`, `_tick_vehicles`, tuned by `WorldDef`). A player's stay is
  a string of lives: `add_player` starts one and `player_finished` ends it
  with outcome "died" (everything carried drops in a bag) or "left" (a
  finished sign-out: everything carried goes home). After "died" the owner of
  the stash (`Main` solo, `NetSession` online) calls `add_player` again in the
  same raid. Loot reaches the stash mid-life only through a `Depot`
  (`player_banked`). The watch's Abandon (`Raid.abandon`) is a death,
  never a leave: it goes home only as "died". Never add a way to leave that skips `begin_sign_out`:
  a disconnect goes through `remove_player`, which leaves the body standing.
  A player whose connection dropped gets that body back if they sign in
  before its countdown ends: `NetSession._on_peer_connected` finds it
  (`Raid.is_unguarded`) and `Raid.reclaim_player` hands it over, with no
  deploy; the game reconnects on its own (`Main._on_online_disconnected`,
  `reconnect_window`). Anything the server sends a body's owner asks
  `NetSession._owner_peer(actor)`, never a peer id kept from the deploy,
  because a body outlives the connection that deployed it.
- Drop-in protection is `Actor.protected_left`, checked in `Combat.deal`.
- Big battles must stay affordable; measure with
  `godot --headless --path . res://tests/battle_bench.tscn -- --bots 150 --players 32`
  (processor time a tick, against the 16.7 ms budget). Three things keep
  them so. Bots nobody is near are thinned: `Raid._tick_detail` calls
  `Actor.thin`, and the actor and its brain then take one longer step every
  few ticks, so anything that drives an actor tick by tick must ask
  `Actor.ticks_now()` first, and a press set from outside can be missed
  unless the actor is at `thin(1)`. A bot asks for a new path only when its
  goal has moved or its path ran out (`BotBrain._move_toward`), and all
  bots share `PATHS_PER_TICK` new paths a tick (a query costs in
  proportion to the whole navmesh); never set
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
- Sound and visual effects (`Sfx`, `Fx`) must stay no-ops on a headless server.
- Art lives in the `Look` autoload (`core/visual/`), not in gameplay scripts.
  Gameplay scripts keep building plain greybox shapes; `Look` dresses them
  when they enter the tree and does nothing when headless. It never adds
  collision or changes the simulation, and it never names a world: worlds
  pick surfaces, an atmosphere and bot skins (`set_meta("look", ...)`) from
  its generic kits. Decoration in a map uses its own RNG so it cannot shift
  the gameplay layout.
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
- Flight rigs and abilities are data too. `FlightRig` and `Ability` are single
  classes whose item stats pick the behavior. Abilities fire from
  `ActorCommand.ability_pressed`.
- `Raid` never touches `Profile` to build a kit. The kit is passed into
  `Raid.start`, so a server can supply it later.
- Online play: the server is the authority (`Raid.Mode.SERVER`, `NetSession`).
  Clients simulate actors from commands for responsiveness, but
  `Combat.authoritative` is false there, so a client never deals damage, loots,
  or decides an outcome. Anything that changes a result must run on the server
  and reach clients through `NetSession`.
- `Raid` never writes to `Profile` on a server. Results travel in the
  `player_finished` dictionary. Online the server settles them into the
  account; `Raid.apply_result` is only for the local solo profile.

## System rules (read before you touch them)

Most of the rules live in `docs/systems/`, one file per system, so parallel
work edits different files. They are rules all the same: before changing a
system, read its file, and update that file (not this one) in the same PR.
A new system gets a new file and a line here.

- `docs/systems/camera-and-views.md`: The camera, first and third person, the head and eyes, what is drawn between ticks, picture quality settings.
- `docs/systems/bodies-and-animation.md`: Legs, gait, crouch, slide, carries, holsters, and people built from parts.
- `docs/systems/worlds-and-war.md`: Death rules per world, renown, the war director, weather, the planet kit, terrain, collision (what is solid, `SolidProp`, the walk-through check), strongpoints, drops, world heat, shelling, world events, the life log and risk zones.
- `docs/systems/frostline.md`: The cold, warm beacons, tracks, thin ice, the defence grid and the Engine's inside.
- `docs/systems/marsh-and-ashfront.md`: The Spore Marsh's wildlife, fouling, spores and Rootways, and Ashfront's scenery army, battle shelves, horde, flares and low sky.
- `docs/systems/bots.md`: Armies, commanders, kinds, doctrine, group fights, senses, grudges, cover and melee bots.
- `docs/systems/melee.md`: Melee types, techniques, the one button, timing, guards, feints, the kick and the dodge.
- `docs/systems/guns-and-feel.md`: Loadout slots and keys, attachments, power weapons, recoil, handling, feel benches and feedback.
- `docs/systems/gear.md`: Flight rigs and thruster trails, artifacts, visors and helmets, armor frames and paints.
- `docs/systems/carry-weight.md`: What items weigh, the light, medium and heavy load, what it does to moving and flying, and how the load reaches clients and the watch.
- `docs/systems/vehicles.md`: Vehicles, riding, seats, aircraft, drifting and toy vehicles on the watch.
- `docs/systems/economy-and-progression.md`: Bounties, mastery, the scrap kit, safety nets, crafting, money, scrip, contracts, the market and cosmetics.
- `docs/systems/online.md`: Sign-in, encryption, input and movement netcode, lag compensation, the account service, server stashes, several sessions in one process, one program per world and travel.
- `docs/systems/social-and-plaza.md`: Clans, the Concourse's megacity and people, the War Room, squads and friends, safe zones and squad portals.
- `docs/systems/ui-phone-watch.md`: The phone and its settings, emotes and shortcut keys, bug reports, the new player's tour, opening in the world, menus in the world and the watch.
- `docs/systems/home-base.md`: The modular base, its rooms, the plan table, the bench, the range and course, and upgrades.
- `docs/systems/arena-and-race.md`: The arena venue and its rules, and Meridian's races, league, ghosts and tuning.
- `docs/systems/updates-and-dev-mode.md`: The self-updater, the installer, the temporary dev mode and its tools (capture and snapshot keys, the phone's console).
- `docs/systems/dunes.md`: The Dune Sea: its map, salvage crates, carrying, cargo, banking a haul and losing it, sandstorms that bury and uncover the wreck fields, and convoys.
- `docs/systems/launch-scope.md`: The first release's scope: the one switch (`LaunchScope`), the launch worlds, and the features and items it holds back.
- `docs/systems/audio.md`: Footsteps, engines, each world's ambience, the music and its volume, and keeping sound light on a laptop.
- `docs/systems/rift.md`: The Basalt Rift: its map of basalt over lava, the lava that burns and what floats on it, updrafts, the Sky Leviathan and its rig rewards.

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
- Every gameplay feature gets checks in a test file of its own,
  `tests/<name>_tests.gd` with a `static func run(t: Node)` (`t.check`,
  `t.frames` and the runner's shared helpers): the runner finds every such
  file by itself, so a new group never edits `tests/test_runner.gd`, which
  keeps only the framework and helpers several groups share.
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
godot --headless --path . res://tools/new_world/new_world.tscn -- --id <id> --name "<Name>" [--planet <type>]   # a new world's folder, map, roster, tests and rules file from the template
```

CI (`.github/workflows/tests.yml`) runs the suite in two tiers. The offline
tier (every group that never starts a server) runs on every push with
`--fixed-fps 60`, which skips the real-time waits. The online tier (groups
that start a server, found automatically, see "Finding and picking groups" in
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

A `--<name>-only` mode is a file of its own, `tests/visual/<name>.gd` with
a `static func shoot(v, out_dir, args)`, found by `visual_check.gd` by
itself; a new mode is a new file there, never an edit to `visual_check.gd`.
