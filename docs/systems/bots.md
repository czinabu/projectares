# Bots and armies

Rules for armies, commanders, kinds, doctrine, group fights, senses, grudges, cover and melee bots. These are part of the rules in `CLAUDE.md` that must not be
broken: read this file before changing anything it covers, and keep it up to
date in the same PR.

- The enemies switch (`Raid.enemies`, the stability pass). One flag turns
  every world's enemies off: the army (`Raid.army_size()` is 0, so
  `bot_target`, bosses and guards see an empty world, as with `--bots 0`),
  respawns and reinforcements, rival raiders, and the events that bring
  bots (warlord, convoy, airship and its Sky Leviathan). Caches, vehicles,
  weather and supply pods carry on. `Main` reads it at boot
  (`Raid.enemies_wanted`): `--enemies` / `--no-enemies`, then
  `ARES_ENEMIES`, then a `--bots` count over 0, then the project setting
  `ares/stability/enemies` (false during the stability pass). The test
  runner and the benches keep enemies on and set `ARES_ENEMIES` for the
  servers they start. In a solo world the dev console's `enemies on|off`
  flips it live. Never delete an enemy system to get a quiet world: gate it
  on `Raid.enemies`. The arena's gladiators and the race's AI riders are
  that venue's rules and are not switched.
- The enemy budget (with enemies on). `Raid.enemy_cap` is the most
  enemies a world holds at once, all counted (`bots`): the army takes
  `army_size()` (its `bot_count` up to the cap, leaving room for the map's
  bosses and guards but never under half the cap), and reinforcements,
  respawns, broods, keeper adds, raiders and the bot events wait for
  `enemy_room()`. `Raid.near_full_cap` lets only that many of the bots in
  full-detail range of a player run every tick (`_tick_detail`); the rest
  there take every second tick. `Main` reads `ares/stability/enemy_cap`
  (8, from the frame bench on an RTX 5070: Ashfront holds about 58 fps at 8 bots and 30 at 60) and `ares/stability/enemies_full_detail` (12), or `--enemy-cap <n>`
  / `ARES_ENEMY_CAP`; 0 is no cap, and with no enemy cap there is no near
  cap either. A world may hold its own budget in place of the project's
  (`WorldDef.enemy_cap`, read through `Raid.enemy_budget()`, only while
  the project's cap is on): 24 on Ashfront, 12 in the Marsh, Dune Sea and
  Rift. The tests and benches run without a budget unless a bench is
  given `--enemy-cap`. Raise the cap only with a frame bench showing the
  frame steady at the new count.
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
  walker, and each army's own, the Legion marksman and the Tide runner;
  DESIGN.md "Heavy units", "The enemy AI pass") come from the seed in
  `equip_bot`, and each army fights its own way (`DOCTRINE`, as metas:
  "range" the distance it keeps, "fall_back", "hunters" added to the
  ring's, "flankers" 2 for a pincer from both sides, `SquadBoard.flank`'s
  cap, and "breaks_at", the share of its fireteam lost before the rest
  break off, counted by `BotBrain.set_team` and `ally_down`, which the
  `Raid` calls on a death, `_tell_team`); a big
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
  (`return_fire_time`, not for a kind with the meta "holds_turn",
  Frostline's Wardens) and anything inside `point_blank` skip the queue,
  and bots fighting bots are never rationed (`BotBrain.is_person`); nor is a
  bot on a vehicle's mounted gun (a weapon marked "mounted"), which fires
  out to `MOUNTED_REACH` whatever its kind's own reach, keeps that gun in
  hand (`_primary_index`) and, riding, watches all round. Spotting
  takes longer far off and against a crouch (`notice_mult`), and the gun
  comes up halfway through the reaction with a bark heard nearby
  (`ActorSkin._update_bark`) before the first shot. Measure with the duel
  bench's `--group 2,3,5` (and `--slots off` to compare).
  Bots react only to what they sense (DESIGN.md "Enemy senses and squads",
  Caleb's "everyone converges on me"): sight, a person's noise (shots,
  `Combat.noise`, told nearest first; footsteps, engines and a flight
  rig at work as far as it carries, `BotBrain.noise_of`,
  `FlightRig.noise`), a hit and a squadmate's callout (`_call_out`, a
  snapshot when the spotter raises its gun). What they learn is a place,
  never live tracking: a lost contact is searched for (`_lost`) and let go.
  A world gives a kind its own senses with metas set in `equip_bot`
  ("sight", "fov", "reach", "far_notice"; how it fires, "burst" and
  "slots"; and how it hunts, "tracker", "preys_on_cold", "shuns_warmth",
  "storm_bold"; DESIGN.md "The enemy AI pass"), never a second brain. A
  storm-bold kind (the Dune Sea's burrowers) is the one a storm helps: its
  sight and leash grow by that share of the storm's strength where it
  stands (`BotBrain.storm_boost`), and the storm never cuts its sight. A
  "trail" meta makes the Raid leave a hurting cloud where the bot walks
  (`Raid._tick_trails`, the Rift's Magma Crawlers). A tracker follows
  the freshest mark in `Raid.tracks` near it to where the mark was laid,
  never to the person (`BotBrain._sniff`, through `_sensed`), and a bot
  that shuns warmth neither targets anyone in a "warmth" ring nor walks
  into one (`BotBrain.in_warmth`, `_outside_warmth`). Any gun with a
  "lock_time" meta draws its tracking beam. Smoke hides people from bots as it hides them from
  eyes: anything a player cannot see through is a cloud in `Raid.smoke`
  (`Smoke.add`, authority only; a shell leaves one), and bot sight asks
  `Smoke.blocks`, never a view. An army remembers a player for one life
  (`WorldDef.grudge_factions`, `Raid.grudges`, authority only): hurting
  its bots raises its grudge, time fades it, death clears it, and over
  `grudge_hunt` the `Raid` sends its nearest few after where that player
  roughly is (`BotBrain.hunt_grudge`, through `_sensed`, so the hunter and
  leash limits hold). The player is told only which army
  (`Actor.hunted_by`, `NetSession._hunted`, the visor's tag
  `VisorHud.hunted_text`).
  Battles follow the ground (DESIGN.md "The enemy AI pass", step 4): with
  its orders the `Raid` sets each soldier's style from
  `WorldDef.ground_at` and `ground_styles` (`BotBrain.set_ground`, always
  laid over the bot's own numbers), keeps `line_share` of an army on its
  "line_post" markers (`_man_lines`, "line"), has a team ring a manned
  enemy site for `siege_time` before storming it (`_besieging`,
  `_siege_spot`, "siege"), and a strongpoint marker's "hot_at"
  (`Strongpoint.hot_at`) keeps every team off it until the war is that
  hot, then sends only `WorldDef.elite_kinds` (`WarCommander.plan`). A
  bot on foot that gets nowhere jumps and steps aside
  (`BotBrain._climb_out`). Once a walking bot's path has run out it
  heads for the path's real end and stops within `ARRIVE_STOP`, never
  straight on at a goal past a drop. A bot with the meta "edge_guard" (a
  world with deadly drops sets it) also has its goal and patrol points
  moved onto the navmesh (`_onto_nav`), and checks each step stays on
  it (`_keep_on_ground`, one closest-point query a step), sliding along
  the edge instead. Godot's path and closest-point queries cost in
  proportion to the whole navmesh, not the distance (about 4 ms each on
  the Dune Sea's 84,000 polygons, 1-2 ms on Ashfront's 25,000), so only
  edge-guarded bots pay for `_onto_nav`, only a world with a small
  navmesh may set "edge_guard", and every bot in the process shares
  `PATHS_PER_TICK` new paths a physics tick (`_path_allowed`): one over
  the budget asks again next tick and walks straight meanwhile. A bigger
  map's navmesh should be baked as coarse as its ground allows.
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
  does (`_start_attack`, `_carry_charge`), the weapon ability too
  (`_wants_ability`: a hammer pounds a crowd, a sword counters a swing
  coming, an axe hooks a raised guard, a knife steps behind and a hook
  blade trips now and then; no bot vaults). A blade in reach beats a rifle
  (Caleb's call): an army gunner cut by a blade flinches
  (`BotBrain.melee_flinch`, its aim and trigger only, never a player's)
  and gives ground from one (`blade_backoff`). Measure with the duel
  bench's `--melee <blade id>`.
