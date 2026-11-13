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
  phone is out, the camera eases in over the shoulder to read its holo
  (`PlayerController._read_phone`, Caleb's call) and eases back after; the
  view stays third person.
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
- Drop-in protection is `Actor.protected_left`, checked in `Combat.deal`.
- How harsh death is belongs to the world, not to `Raid`. With
  `WorldDef.keep_gear_on_death` a dead player drops only the backpack and the
  equipped gear returns in the result's `kept`. A gentle world pays for that
  with basic loot tables; rare gear stays in the full-loot PvP world.
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
- Where a player lands is the `Raid`'s call. `Raid.drop_choices(owner)` lists
  what is on offer (quiet, a held strongpoint, beside the fighting) and the
  chosen id goes into `add_player`'s `p_drop`, which falls back to a quiet
  drop if the choice is no longer on offer. Online the client only sends the
  id with `NetSession.deploy(drop)`; a client lists its choices from what the
  server already told it (`Strongpoint.viewer_holds`, war intensity).
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
  (players, war level, top bounty, the event running) and never says who or
  where anyone is. The safe zone's `NetSession` gathers it from the other
  sessions in the process and sends it to everyone standing there
  (`NetSession.world_status`); `PlazaView` writes it on a sign over each
  world doorway (`heat_signs`). Anything else that advertises a world reads
  `world_status`, not a second channel.
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
  `WorldDef.bots_contest_sites` is on, `Raid._tick_orders` gives each faction
  its orders through `BotBrain.post_to`: a garrison on every site it holds,
  everyone else against the nearest site it does not. Reinforcements follow
  the war: `Raid.bot_target()` is `bot_count` plus a share of
  `WorldDef.war_reinforcements` by `war.intensity`, new bots join the faction
  with the fewest alive, and extra bots are not replaced once it cools. Bots
  killing bots only simmer the meter (`WarDirector.report_battle`, capped at
  `battle_ceiling`); only players take it higher. World-event bots
  (`Raid._event_bots`) are outside all of this.
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
  fighting; `--probe` shows what the draw calls go to). What keeps the
  frame affordable, all view only: a far body is posed every few frames
  (`ActorSkin.detail_step`, scaled by the camera's zoom, which steps its
  animation and skeleton by hand while it is far) and its weapons cast no
  shadow; open ground is drawn in tiles (`Terrain.tile_cells`) so only the
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
  data plus a `Look.MELEE_MODELS` entry, not as a new class. Every melee
  model is dressed as tech by `Look._tech_melee` (`assets/shaders/melee.gdshader`):
  bare metal becomes alloy with an energy edge in the weapon's rarity color,
  wood and wraps black polymer with glowing seams. A holstered blade is worn
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
- Melee is directional. The stance travels in `ActorCommand.stance`, attacks
  set `DamageInfo.direction`, and `MeleeWeapon.guard_covers` decides whether a
  guard stops a hit. A swing goes toward its stance (Caleb's call): a left
  swing starts on the right and ends on the left, so `attack_dir` (the side
  it comes from) is `MeleeWeapon.swing_from(stance)`. A guard covers its
  stance's side, so a left swing meets a left guard. Windup and guard poses
  must show their side; `threat_dir()` is what a defender reads.
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
  faster: that is the sprint. A slide (`Actor.slide_left`, `Actor.crouch`)
  is simulated from `ActorCommand.slide` like a dash, so it predicts and
  replicates; the skin bends the model into a slide pose from `crouch`.
  Standing still is a relaxed stand (`idle`); a gun is held low (`idle_gun`)
  over the relaxed stand's legs and raised (`aim_gun`) only while shooting
  or aiming and briefly after.
  Check leg changes by eye: `visual_check.tscn -- <dir> --gait-only`, and
  the stand with `--idle-only`.
  Holstered weapons are worn, not hidden (`ActorSkin.stow_place`): a primary
  gun or two-handed weapon slung across the back, outside a worn back rig
  (on a jetpack or wing pack, clamped to the weapon rail down its side
  instead, gun right and long blade left, leaning out in a slight V, so the
  heat gauge on its back stays in view; a wing pack's rails stand behind
  its wing slots: the rig model's "MountL/R" markers, and the
  skin rests the weapon's near side on the clamps), a
  sidearm muzzle down on the right hip, and a one-handed blade on the left
  hip. These are view-only copies; the weapon's own node stays on the hand.
  A switch is shown as the hand putting one away and drawing the next
  (`ActorSkin._update_switch`, reaching through `WeaponArm.override_point`),
  but only the view waits: the actor switches at once. The holster key (Z)
  sends `switch_weapon = ActorCommand.HOLSTER` and draws `Actor.last_drawn`
  again; it is an index, never a toggle, so it replicates safely. Check with
  `--holster-only`.
- First and third person differ only in where the camera is (Caleb's rule).
  Both look at the one real body, posed by the same code and holding the
  same weapon in the same hand: first person puts the camera at the eyes
  (`ActorSkin.eye_point`, pulled back level by `GameSettings.eye_pullback`,
  which eases off as the view tips down while the eyes lean ahead,
  `PlayerController.look_down_lean`, so looking down sees the chest, never
  the shoulders from behind)
  and leaves out only the head (`ActorSkin.hide_head` moves it and what is
  worn on it to `Mirror.HEAD_LAYER`, which that camera culls; shadows and
  a mirror still see it). Never build a first-person-only copy of the arms,
  a weapon or a prop, and never move anything in front of the camera for
  first person. Aiming down sights is a body animation, the same in both
  views (`ActionPose.ads`, eased by `ads_rate`): `WeaponArm._reach_sight`
  reaches the gun hand so the sight (`ActionPose.sight_local`: an optic's
  "Sight" marker, else the model's "IronSight", else the top of the model)
  sits on the line out of the model's eyes, `ActionPose.relief_for` in front
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
  to the camera. A view that follows the gun reads it where it was drawn
  (`ActionPose.sight_shown`, the hand's "shown_local" meta), never the hand
  node a physics tick parked (that was the range's ADS stutter). A weapon
  that takes no input on a tick stops aiming (`Weapon.drop_aim`). Each
  actor has one `ActionPose`
  (`core/visual/action_pose.gd`, a view-only child made by `ActionPose.of`):
  the melee reach and shoulder turn, the reload motion, the low ready, the
  drawing back of a held heavy and the easing back of a recovering blade,
  the gun brought up to the eye,
  the watch raise (from `ActorCommand.watch_up`) and the phone hold
  (`ActionPose.phone`, from `ActorCommand.phone`, which `Locomotion` poses
  the body from). `WeaponArm` and `ActorSkin` pose the model from it; a new
  hand or weapon animation goes there. Weapons are held, not floated
  (Caleb's call): the hand carries them, each by its own grip (Caleb's
  call), found on the model rather than tuned by hand. `Look._measure_hold`
  reads a gun's side outline for its trigger guard, the pistol grip behind
  it (its rake) and the fore end ("Grip", "Trigger", "ForeGrip" markers;
  a power weapon marks its grip in `_power_grip`); the fist's middle closes
  on the grip level with the trigger and the wrist bends to its rake
  (`WeaponArm._held_wrist`, `_bend_to_grip`), the off hand's fist on the
  fore end. `Look._fit_hands` finds a melee handle (up to its guard or
  head), puts it through the fist and gives a two-handed weapon
  (`Look.is_two_handed`) its off hand's place: a hand below on a short
  handle, up the haft of a long one, which rests carried across the body
  (`WeaponArm.carry_point`). Check by eye with
  `visual_check.tscn -- <dir> --hands-only`. A blade lies along the closed fist
  and a gun held low turns with the wrist (`WeaponArm`); swings turn the
  arm about the shoulder (`ActionPose.swing_reach`, `elbow_pole`). Shots
  are judged from the eyes but drawn from the gun's "Muzzle" marker as it
  is shown (`Gun.muzzle_point`). Compare by eye with
  `visual_check.tscn -- <dir> --views-only [rows]` (`VIEW_MELEE=<item id>`
  picks the melee weapon), which also saves each shot full size under
  `views/`.
- People are built from parts (`core/visual/human.gd`): an "appearance" names
  a build, four parts and colours. It is cosmetic only and never trusted:
  always pass one through `Look.clean_appearance` / `Look.set_appearance`,
  which is safe on a headless server. Online it travels in the spawn data as
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
- Only CC0 or similarly permissive assets, each recorded in `assets/LICENSES.md`.
- Load assets that need importing (models, textures, fonts) with `load()` at
  runtime, not `preload`: a preload fails to parse on a fresh checkout before
  Godot has imported the file.
- Items are ids defined in `ItemDB` with tags. Use tags, not id checks, to
  decide what an item does.
- Gear behavior comes from the item's `stats` in `ItemDB`, applied by
  `Loadout.equip`. Add a new gun or frame as data, not as a new class.
- A loadout carries one primary, one melee weapon and one sidearm. Keys are by
  type, not equip order: 1 primary, 2 sidearm, 3 melee, 4 power or special
  weapon (`Actor.slot_order`, `weapon_for_key`); the mouse wheel cycles the
  same order. Sidearms are firearms also tagged "sidearm";
  `Loadout.fits(slot, id)` decides what goes in a slot (a sidearm never fits
  the primary slot), and `Weapon.is_sidearm` marks one once equipped. Running
  the primary dry with the trigger held draws a loaded sidearm instead of
  reloading (`Actor._simulate_weapons`). Headshots come from
  `Combat.is_headshot` on a `Combat.trace` hit; a gun's `headshot_mult` scales them.
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
  real geometry you look down, never a screen overlay. Fitting happens at
  the home base's gunsmith bench (`BaseLayout` kind "gunsmith").
- Power weapons are items tagged "power" (Rail Lance, Helion launcher, Arc
  Mortar, Storm Cannon), still plain `Gun` data: stats such as
  `charge_time`, `pierce`, `projectile` ("rocket"/"grenade", flown by
  `Gun.Round`), `splash_radius`, `heat_seek_cone` and `spin_up` pick the
  behavior, and `Gun.splash` sends every blast through `Combat.deal`. They
  are found, never equipped: `PowerArmory` (`core/war/power_armory.gd`,
  `Raid.armory`, authority only) puts them on power racks (a `LootContainer`
  labelled `LootContainer.RACK_LABEL`) at strongpoints, beside supply pods
  and sometimes beside a refilled cache, more often as `Raid.war` heats up,
  scaled by `WorldDef.power_weapon_rate` (0 in Frostline and the arena).
  Taking one fills a fourth weapon slot (key 4) through `Loadout.set_power`;
  one already carried goes on the rack with its shots. A spent one is thrown
  away, a dead player's is left on a rack, and `StashRules.storable` refuses
  them, so they never reach a stash, a bag or a result. Online the swap
  reaches clients as `Actor.power_changed` through `NetSession`. Their art is
  `Look._power_model` and `_dress_power_rack`; check by eye with
  `visual_check.tscn -- <dir> --power-only`.
- Flight rigs and abilities are data too. `FlightRig` and `Ability` are single
  classes whose item stats pick the behavior. Abilities fire from
  `ActorCommand.ability_pressed`.
- Flight is simulated in `Actor` from the command, like a dash, so it
  predicts and replicates: jets lit only while aim is held in the air
  (`Actor._wants_hover`, Caleb's call: never a hover that stays on by
  itself; `FlightRig.is_hovering`, flown by `Actor._simulate_hover`; the
  server repeats it in each state as `ActorCommand.STATE_HOVERING`), a
  boost started by a sprint press in the air and held on sprint, no hover
  needed (`Actor._wants_boost`), that speeds you up along the look
  direction while the skin lays the body out prone as the speed builds, and a glide whose speed is energy
  (`Actor._glide_velocity`). Every rig cruises at the same
  `FlightRig.CRUISE_SPEED` so a squad on mixed rigs keeps together (Caleb's
  call), and each stays up its own way and has its own edge: the jetpack
  flies high in swoops (cruise, then coast down with the jets idle to cool),
  stops dead and hovers to shoot steady, and carries heavy armor, but turns
  wide and is loud and hot; wings glide and pulse to hold height, with the
  fastest dives and tightest turns, silent and cold, but never
  stop and fire only a sidearm while spread; boots skim low (`FlightRig.skim`),
  cooling near a surface and burning out high up, kick up, dash furthest and
  aim steady while low. Their kicks top a rooftop (three reach a 15 m roof,
  Caleb's call) and a roof under the feet is a surface they cool over, but
  in open air they never cool (`FlightRig.aloft`), so they hold no open sky. Flown its
  own way a rig stays up for minutes, against type it overheats in seconds.
  Shooting from the air spreads wider (`Actor.air_aim`) except in a rig's
  steady state. Rigs come in tiers (Caleb's call): Mk1 to Mk3 of each, a tier
  made with `ItemDB._rig_tier` from a lower tier's stats. A tier sets `FlightRig.tier`
  and `ceiling` (`ItemDB.RIG_CEILINGS`: 25, 60, 100 m) and may only make the
  rig run cooler, never faster: cruise and dash speeds stay the same on
  every tier, a boost is never faster than the Mk2 jetpack's, and the heat
  bar stays 100. The ceiling is measured
  from the world's ground, never a roof (`Actor.ground_level`: the map's
  `ground_height`, else its origin), and only limits lift: the climb eases
  off under it (`FlightRig.climb_room`) and a kick, pulse or launch is cut
  to top out on it (`lift_cap`), or refused without heat. Only Mk1 drops or
  is sold: Mk2 and up are crafted from blueprints (DESIGN.md section 10),
  so no loot table may list them.
  The keys fly every rig and the mouse only looks and aims
  (Caleb's call), with one exception: wings fly where you look, like a
  bird's (Caleb's call, so you never fly sideways to your view). They bank
  round onto the view's heading (`Actor.glide_steer`), the strafe keys roll
  a harder turn, and forward and back dive or pull up (`Actor.glide_trim`),
  never the view's pitch. Holding free look (V, `ActorCommand.free_look`,
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
  cruise carries on after it. Q and E fly nothing (Caleb's call).
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
  What only the player sees is the controller's job and view only: recoil
  reaching the view over a few frames and settling back
  (`PlayerController._update_recoil`), the view widening with speed
  (`speed_fov`) and dipping on a landing (`land_dip`). A semi-auto keeps a
  pull made just before it is ready (`Gun.press_buffer`); that is simulated,
  so it is in `Gun`, from the command.
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
  ember of a thermal visor). How warm someone looks on thermal is
  `Visor.heat_of`: `Actor.heat_signature` (frames set it with a
  `heat_signature` stat) plus flight rig heat. The picture is `VisorHud`
  (`core/ui/visor_hud.gd`), a view: its glass is drawn in first person only
  and only while a helmet is worn (Caleb agreed a visor counts as in-world,
  since you look through it); what a visor shows out in the world (snapshots,
  tag markers, pulse rings, glints) is there in either view. The glass is thin
  projected light, never a frame, a tint or a mask over the view (playtest
  feedback: the first visors were in the way): it rests dim, trails the
  head, wakes on trouble (`VisorHud.alert`) and closes on what is aimed at
  (`VisorHud.lock`). In third person the glass is gone but the ring and
  the lock brackets stay (`VisorHud.reticle_shown`), and the helmet wears
  its health strip and system light on the back of the head
  (`ActorSkin._update_vitals`, `helmet_light`), where a pack or a slung gun
  never covers them. The glass carries
  only your always-in-view readings (the health arc with armor and stamina
  inside it and the ability's state under it, and with a flight rig the
  heat gauge and rig cue high on the right, `VisorHud._draw_vitals` and
  `_draw_heat`; squad markers and the landing warning are still to come,
  per DESIGN.md sections 3 and 5); do not put the map or standing there, they
  stay on the watch. Mk2
  helmets are never sold or dropped: like rigs, they are crafted from
  blueprints (DESIGN.md section 10), so no loot table may list them. Check the glass by eye with
  `visual_check.tscn -- <dir> --visors-only`.
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
  clamped to a back rig's rails stay in their clamps. A new
  vehicle type sets those anchor points for its model. Check by eye:
  `visual_check.tscn -- <dir> --ride-only`.
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
  and `_toy` (a toy to draw in flight). The toy in the hand and the picker on
  the watch (`PlayerController.held_toy`, `Hud.Wrist.show_toys`) are views.
  A new vehicle is a new `vehicle` item; its toy is `toy_model(id)`.
- Mastery (`core/progression/`) is keyed by gear type tags ("rifle", "blink",
  "frame_heavy"), never by item id. Variants are sidegrades: every one trades a
  strength for a weakness, and death never takes mastery away. Variant picks go
  into `Raid.start` alongside the kit; `Raid` never reads them from `Profile`.
- `starter`-tagged items are the free scrap kit. They never enter the stash.
- `Raid` never touches `Profile` to build a kit. The kit is passed into
  `Raid.start`, so a server can supply it later.

- Online play: the server is the authority (`Raid.Mode.SERVER`, `NetSession`).
  Clients simulate actors from commands for responsiveness, but
  `Combat.authoritative` is false there, so a client never deals damage, loots,
  or decides an outcome. Anything that changes a result must run on the server
  and reach clients through `NetSession`.
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
  blends every correction over several ticks. Keep `Actor` movement
  deterministic from its `ActorCommand` so prediction keeps matching.
- Lag compensation: each input also carries the server tick the client's view
  had reached, and the server keeps half a second of past positions. Attacks
  judge targets at `Combat.positions_seen_by(attacker)` (shots via
  `Combat.trace`), never by reading other actors' `global_position` directly,
  so a lagging player hits what was on their screen. A vehicle the local
  player rides is predicted and corrected against `NetSession._ride_history`
  like the player's own actor.
- Online, the server owns each player's stash, loadout and mastery
  (`core/account/stash_service.gd`). A client's kit or picks are never trusted;
  the server gets them from `StashService.deploy` and applies results with
  `StashService.settle`. `NetSession` does both. A client only signs in
  (name plus `Profile.online_secret`) and sends requests (equip, pick, deploy)
  from the lobby; it never sends a kit, and online play never reads or writes
  the local `Profile` stash. The hub shows the server's account snapshot while
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
  show lit glass. The device also projects a holo of its screen
  (`Handheld.holo_of`) for reading from outside: it sits on
  `Mirror.HEAD_LAYER`, so your own first-person camera leaves it out like the
  head and reads the screen in the hand, while third person reads and clicks
  the holo (Caleb's call). A new app is an entry in `Phone.APPS` with a line glyph in
  `Phone.AppIcon`; Settings are grouped in `Phone.SETTINGS_TABS`, and the dev
  switches live only on the Dev tab.
  Settings live in
  `core/settings/game_settings.gd` (its own save file); a server never reads them.
- Dev mode is TEMPORARY (Caleb's call, to come out once the game is further
  along): `core/dev/dev_mode.gd`, switched in the phone's Settings app and
  only in a debug or editor run (`DevMode.available`), never in an exported
  game. Solo, it puts `Profile` on a separate save
  (`Profile.DEV_SAVE_PATH`) kept topped up with all gear and max scrip, and
  hands a solo `Raid` its cheats (`Raid.dev_cheats`: god mode, endless heat
  and ammo, no cooldowns); a server or client raid ignores them. Online, only
  a server hosted from the editor in dev mode (`main.gd host_and_join`
  passes `--dev-host <name>`) tops that one account up
  (`StashService.dev_accounts`), and such a server keeps its accounts in
  `Main.DEV_ACCOUNTS`, apart from real ones. No cheats online. Every line
  it touches is marked "DEV MODE". Never build a feature on it; to remove it,
  delete `core/dev/` and every "DEV MODE" line or block, plus
  `_test_dev_mode` in the tests.
- Safe zones: a world with `WorldDef.safe_zone` (the plaza, `worlds/plaza`)
  is a social space run by the same `Raid` and `NetSession`. `Combat.deal`
  refuses every hit there, `Actor.weapons_locked` stops attacks, abilities
  and healing, and `NetSession` shows the loadout with `StashService.showcase`
  instead of `deploy`, so nothing leaves the stash and nothing is settled.
  Doorways are "portal" markers (see `WorldDef`); `core/social/plaza_view.gd`
  offers them and `main.gd use_portal` decides where each destination leads.
  Use `Worlds.raid_worlds()` for anything you deploy into.
- A server runs several `NetSession`s in one process (plaza on the port, raid
  worlds after it, `main.gd start_server`), each raid in its own 3D world
  (`NetSession.isolated`) and all sharing one `StashService`. Never use
  `Worlds.current` for rules: ask `Worlds.of(node)` or `Raid.of(node)`, and
  filter any scan of the "actors" group with `Raid.together`.
- `Raid` never writes to `Profile` on a server. Results travel in the
  `player_finished` dictionary. Online the server settles them into the
  account; `Raid.apply_result` is only for the local solo profile.
- The home base (`core/base/`) is a view of a stash, never a second store.
  `HomeBase.show_gear(stash, loadout)` rebuilds the room from plain data, so
  it shows the local `Profile` solo and the server's account snapshot in a
  lobby. `core/base/base_layout.gd` decides what goes where from item tags.
  Every weapon goes on the one armory rack (`BaseLayout.ARMORY`, Caleb's
  call): its sections hang on the walls of the armory alcove
  (`HomeBase.in_armory`), with the gunsmith bench in the middle and the
  locker at the way in. Each weapon hangs on a lit mount
  (`HomeBase._build_mount`). The bench's vise holds the primary (its rack
  pegs stand empty); using the vise puts the next gun from the rack in it
  (`HomeBase.Vise`, `next_bench_gun`) through the same `equip_requested`,
  so any gun can be fitted out there. A new kind of weapon gets a rack
  section there, not a display of its own elsewhere in the room. The base is where you suit
  up (Caleb's call): the suit-up bay beside the launch pad
  (`HomeBase.suit_up`) replaces the player with a new actor wearing
  `suit_kit()`, weapons locked, and emits `player_replaced` so `main.gd`
  hands it the controller; changing the loadout only changes what the
  bay puts on next. The room has one job per wall: the deploy area
  (suit-up bay, launch pad, the teleporter's place) along the front wall
  right of the exit (`HomeBase.DEPLOY_FROM_X`), the storage wall's shelves
  (supplies, chips, trophies, `STORAGE_ROWS`) left of it, and gear bays
  for armor and rig stands along the back wall; the middle of the floor
  stays clear. The shell is steel, never bare rock: plated floors, ribbed
  wall panels and a ceiling grid (`HomeBase._floor`, `_wall`, `_ceiling`),
  so a new space builds with those. Bikes park in the garage off the right wall
  (`HomeBase.in_garage`). Behind the back wall is the firing range
  (`HomeBase.in_range`): a suited player's weapons unlock only there and
  never run dry, and `HomeBase` scores shots from each gun's `fired` signal
  against its `RangeTarget`s, which stop shots like walls; the score is
  written on a board hung over the lane, never on the screen. Nothing on the
  range goes through `Combat.deal` or pays mastery, because nothing there is
  real damage; never add an Actor target that takes some.
  The base grows with the account's upgrades (`core/base/base_upgrades.gd`,
  static rules like `Economy`): a list of owned upgrade ids kept beside the
  stash and scrip (`Profile.base_upgrades` solo, the account's online, sent
  in the snapshot), never in the stash. `HomeBase.show_gear` takes it as its
  third argument; none is the starter bunker. `BaseLayout.spots(kind,
  upgrades)` is how many spots a display kind has, and `HomeBase` seals what
  is not owned (`_build_gates`: the armory nook's wall, the garage shutter,
  the range door) behind a `Bulkhead` with its price on it in the room.
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
- The game opens in the world, never on a menu screen. Solo it boots into the
  home base; online, joining a server puts you in its plaza, and a world's
  lobby is the home base again on the server's stash. The base's door goes
  straight out to the plaza with no screen (`main.gd head_out`): it joins the
  server it remembers (`Profile.home_server`, set by a join at the uplink) or
  starts one here that runs every world, since worlds are chosen at the
  plaza's gates, never before going online. `Hub` (`core/ui/hub.gd`)
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
- The watch and the phone split the job (Caleb's rule, revised: the watch no
  longer carries vitals, heat and ammo; see DESIGN.md section 3). Vitals,
  flight heat and ammo are always in view on the visor and the gear (health
  arc, gun display, pack screen), so no key is needed to see them. The
  holographic watch (`Hud.Wrist`, raised with X) is for the things you choose
  to do in action: vehicles, the heavy weapon, artifacts, sign-out, banking,
  the map and pings, landing choices and the pack. The phone is for
  settings, talking to friends and players, and information (news, the war
  feed). A new in-raid action goes on the watch; a new social or info
  feature is a phone app. The watch is a card-sized hologram of icons, one
  per thing it holds (`Hud.watch_slots`, `Hud.Wrist.SLOTS`): the open icon
  shows one short line, and controls are glyphs (wheel, click, key cap),
  never words. The mouse wheel moves across the card
  (`PlayerController.watch_focus`, `step_watch`; Caleb's call), turning
  through the toys on the vehicle icon before stepping on, and the mouse
  only looks. While the watch is up the wheel never switches weapons. A new
  watch feature is a new slot, not a new line of text. In third person the
  card rises off the worn watch with a glow on the arm; it is never hung in
  front of the camera. Vitals go on the card only where the visor cannot
  show them (no helmet, or third person). The watch works in the home base
  too (`BaseHud.wrist`), its card saying what each icon holds for the next
  deploy (`Hud.base_watch_slots`). Raised, the wrist comes up in front of
  the eyes along the aim (`WeaponArm.watch_point`), so it is in view in
  first person wherever you look, and the forearm rolls so the face, worn
  on the back of the wrist (`Hud.Wrist.FACE_AXIS`), looks at the eyes
  (`WeaponArm._face_watch`). From the eyes the card opens just over the
  face, sized to read like a card at arm's length (`fp_card_reads_at`). Check it by eye with
  `visual_check.tscn -- <dir> --watch-only` (`--base-watch-only` for just
  the base).
- Money (`core/economy/`): the rules live once, in `economy.gd` (static, like
  `StashRules`), shared by `Profile` and `StashService`. Online, `scrip`
  lives on the server's account and only changes there: through
  `StashService.buy` / `sell`, the payout in `settle`, or `change_scrip`
  for other server systems. A client never sends a price or an amount.
  Shops are tag-driven: an item is stocked if it has the `vendor` tag and one
  of the shop's tags (`shop_db.gd`), and `Economy.is_shop_item` refuses
  anything above Uncommon, so rare gear stays loot-only. Keep every sell
  price below its buy price, and keep run payouts small next to loot: scrip
  must come from getting loot home, so full loot stays the stake.
- Scrip is what a life pays, and it is at stake. The `Raid` pays it
  (`_pay_scrip`, amounts in `Economy`) into `PlayerState.scrip`, copied to
  `Actor.scrip` for views. A death moves it into the bag
  (`LootContainer.scrip`); a depot moves it to `scrip_banked`. It reaches an
  account only through the result (`scrip`, `scrip_banked`) and
  `Economy.payout`, never directly, and nothing is paid for kills alone.
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

## Verify before committing

The project targets Godot 4.7 (what Caleb runs, and what CI uses).

```
godot --headless --path . --import
godot --headless --path . res://tests/test_runner.tscn   # must exit 0
godot --headless --path . res://tests/test_runner.tscn -- --only online   # one group
godot --headless --fixed-fps 60 --path . res://tests/test_runner.tscn -- --tier offline   # fast, ~1 min
godot --headless --path . res://tests/test_runner.tscn -- --tier net --shard 1/3   # a third of the online groups
godot --headless --path . res://tests/battle_bench.tscn -- --bots 150 --players 32   # server cost of a big battle
godot --headless --fixed-fps 60 --path . res://tests/feel_bench.tscn   # how each rig answers, in numbers
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
