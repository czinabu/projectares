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
  Caleb's pick so the screen reads; not with the mirror up).
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
  Melee bots fight like people (DESIGN.md "Melee bots"): held heavies,
  feints (a charge that switches side and lets go as a light) and
  dash-strikes by ring (`BotBrain.RING_HEAVY`, `RING_FEINT`, `RING_DASH`),
  and a strike into any opening; they press the same buttons a player
  does (`_start_attack`, `_carry_charge`). A blade in reach beats a rifle
  (Caleb's call): an army gunner cut by a blade flinches
  (`BotBrain.melee_flinch`, its aim and trigger only, never a player's)
  and gives ground from one (`blade_backoff`). Measure with the duel
  bench's `--melee <blade id>`.
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
  Each weapon swings its own way, from item stats (view only):
  `swing_style` "slash" (swords' arcs), "thrust" (straight out along the
  aim: the spear), "chop" (down from over the shoulder: the axe, the
  hammer), "cut" (the katana's two-handed kenjutsu cuts, `ActionPose.cuts`:
  kesa-giri, gyaku-kesa and shomen through a contact key in front of the
  body, a tsuki for the heavy from the middle stance, the off hand on the
  handle throughout and the edge leading, `ActionPose.cut_blade`; view
  only, so the katana keeps its one-handed stats), `heavy_style` for a heavy of its own (the knife's stab) and
  `swing_scale` for its size. `ActionPose.windup_reach`/`follow_reach` and
  `MeleeWeapon._animate` read `style_now()`. The shown swing starts
  `SWING_LEAD` before the strike and speeds into it, half its arc at the
  hit, then eases out (`MeleeWeapon.swing_arc`; both views read it); a
  windup keeps coiling back (`windup_coil`); two-handers swing slower and
  turn the body more. A new melee weapon picks a style; check it by eye with
  `visual_check.tscn -- <dir> --swing-only` (run with `--fixed-fps 60`),
  which films each move frame by frame. Every melee
  model is dressed as tech by `Look._tech_melee` (`assets/shaders/melee.gdshader`):
  bare metal becomes alloy with an energy edge in the weapon's rarity color,
  wood and wraps black polymer with glowing seams. The scrap kit's blade
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
- Melee is directional. The stance travels in `ActorCommand.stance` (picked
  by default from the movement keys, Jedi Academy style, Caleb's call; B
  switches to the mouse flick), attacks
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
  run. In a fight the run-and-shoot arms come back and the gun points where
  it shoots; a shot, aim or reload takes it out of the carry at once
  (`carry_out_rate`). All of it is read from velocity and the command, so
  remote players match, and it is the same body in both views.
  Check leg changes by eye: `visual_check.tscn -- <dir> --gait-only`, the
  stand with `--idle-only`, and a rifle and a pistol carried on the move
  with `--carry-only`.
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
  the melee reach and shoulder turn, the reload motion, the low ready, the
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
  last field of `Look.MELEE_MODELS`): a straight sword upright, a katana
  leaning in with the off hand under the weapon hand, a knife lying flat in
  a reverse grip with the empty hand up as a guard. Attacks start from the
  hold and ease back into it (`ActionPose.held_ready`). A blade lies along the closed fist
  and a gun held low turns with the wrist (`WeaponArm`); swings turn the
  arm about the shoulder (`ActionPose.swing_reach`, `elbow_pole`). Shots
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
  `--aa` and `--ink`.
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
  type, not equip order: 1 primary, 2 sidearm, 3 melee, and 4 the heavy weapon
  in the watch's chamber (`Actor.slot_order`, `weapon_for_key`,
  `Loadout.power_index`); the
  mouse wheel cycles the same order. Sidearms are firearms also tagged "sidearm";
  `Loadout.fits(slot, id)` decides what goes in a slot (a sidearm never fits
  the primary slot), and `Weapon.is_sidearm` marks one once equipped. Running
  the primary dry with the trigger held draws a loaded sidearm instead of
  reloading (`Actor._simulate_weapons`). Headshots come from
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
  and that death counts it as lost. `StashRules.storable` accepts them: a
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
  (`heat_free`, `lock_up`) are rig states, not new rig types. Until PvE
  dungeons and arena tournaments exist, artifacts drop from world events
  (`WorldDef.roll_artifact`, `warlord_artifact_chance`, `pod_artifact_chance`).
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
  full bar, climbing 1.5x and boosting 2.5x the heat, a 40 m ceiling,
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
  Feedback is view only (DESIGN.md "Feedback"): each kind of gun has its own
  voice (the item's `shot_sound`) heard out to `Gun.SHOT_REACH`, a round
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
  `VisorHud.vital_cells`; the landing warning is still to come, per
  DESIGN.md section 5). Every working helmet also has a heading tape across
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
  head (`ActorSkin._update_helmet`, `build_helmet`: a shell, glass in the
  visor's colour and a fitting per `mode`), hiding the head under it; it
  hangs off the "Head" bone, so first person leaves it out with the head.
  Check by eye with `visual_check.tscn -- <dir> --helmets-only`.
  Armor frames are worn gear the same way: `Loadout.wear_frame` puts one on
  or off (`Actor.frame_id`), undoing the old frame's speed and heat scaling
  before applying the new one, and emits `Actor.frame_changed`. One frame is
  worn; another in a kit is carried. A frame in the pack is on the summon
  carousel too and goes through `Raid.swap_worn`. Both go on at once and
  then the watch rests (`Loadout.SUMMON_TIMES` "helmet", short, and
  "armor", long), and a frame taken off keeps its armor left in
  `Actor.stowed_armor`, so spare plates are no instant refill. The skin wears its plates
  (`ActorSkin._update_frame`, `build_frame`, `build_pad`, by `frame_weight`)
  on the chest and upper arm bones, the same body in both views. Plates are
  fitted, never boxes (Caleb's call): thin curved shells (`_shell`) a
  finger's width off the torso, bevelled at the edges, and the tier shows
  in coverage, not bulk: light a breastplate, medium wrapped round the ribs
  with a belly lame and shoulder caps, heavy a cuirass with a back plate,
  two lames, double caps and a low collar.
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
  `model` stat picks the greybox body ("bike", "rover", "mech", "jet"),
  `body_size` its collision box, `pivot_turn` lets a walker turn on the
  spot, `jump_speed` gives it a jump-jet hop, the "hover" tag floats it on
  a cushion ("hoverbike", the Raider: it drifts through turns by `slip`,
  which travels in the ride state and is corrected like `speed`, holds
  level over a gap for `hang_time` and hugs the ground off a ramp, never
  flying), `passenger_seat` adds a pillion seat behind the rider
  (`Vehicle.passenger`, `mount(actor, true)`; the seat's interact puts a
  second player there; a passenger is seated by the same riding pose from
  the pillion anchors, `Vehicle.ride_anchor`, makes it heavier, the
  `laden_*` shares, and only the server decides who sits there, sent in the
  ride state; check anything that asks whether a vehicle is free with
  `is_occupied`, never `rider` alone), and the "aircraft" tag flies
  it (`Vehicle._fly`: takes off past `takeoff_speed` with jump, never
  hovers, drops below `stall_speed` or with nobody at the stick, climbs no
  higher than `ceiling` over the world's ground). Every vehicle, the jet
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
  blends every correction over several ticks. Keep `Actor` movement
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
  never reach the service. `SocialService` and `ClanService` are still each
  game server's own.
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
  Whatever is worn is always on show (`BaseLayout.plan` gives it a spot
  even when better gear fills its section), so anything can be taken off
  in the room. Helmets sit on the helmet shelf over the armor stands.
  Every weapon goes on the one armory rack (`BaseLayout.ARMORY`, Caleb's
  call): its sections hang on the walls of the armory alcove
  (`HomeBase.in_armory`), with the locker at the way in. Each weapon hangs
  on a lit mount (`HomeBase._build_mount`). The gunsmith bench has a corner
  of its own, the workshop (`HomeBase.WORKSHOP_X/Z`, `in_workshop`), a
  recess off the armory's left-hand wall just inside the way in, where it
  stands with the fabricator beside it, clear of the rack and the walk in
  (Caleb's call), in the starter bunker too. The bench holds one gun at a
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
  only while its viewer is in front of it). The room has one job per wall: the deploy area
  (the wall mirror, with room in front to open a portal) along the front wall
  right of the exit (`HomeBase.DEPLOY_FROM_X`), the storage wall's shelves
  (supplies, chips, trophies, `STORAGE_ROWS`) left of it, and gear bays
  for armor and rig stands along the back wall; the middle of the floor
  stays clear. The shell is steel, never bare rock: plated floors, ribbed
  wall panels and a ceiling grid (`HomeBase._floor`, `_wall`, `_ceiling`),
  so a new space builds with those. Bikes park in the garage off the right wall
  (`HomeBase.in_garage`). Behind the back wall is the firing range
  (`HomeBase.in_range`): the player's weapons unlock only there and
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
  `in_course`): an open-topped yard whose walls stand over every rig's
  ceiling, with a climb tower (and a ramp for wings), a gap to a second
  tower and a sprint, timed by `_tick_course` from the player's position
  alone and written on its board, never on the screen.
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
  list of what is carried with each item's worth. An opened icon's list or
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
  the eyes along the aim (`WeaponArm.watch_point`), so it is in view in
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
  `StashService.craft` decides. Blueprints and upgrade data come from the
  PvP world only (`WorldDef.roll_crafting_loot` and its chances, 0 by
  default; a world's own loot tables). A new craftable is a recipe row and,
  if it needs one, a `_blueprint` item. Costs are placeholders.
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

- The race world (`worlds/meridian`, DESIGN.md section 9) is run by `Race`
  (`core/race/race.gd`, a `Raid` subclass from `WorldDef.new_raid`), on a
  map that offers `race_track()` (a `RaceTrack`: the centre line, gates,
  start slots, `keep_to` lines). Nothing is at stake there:
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
  that, and asks with `NetSession.race_request`. The lights, splits, board
  text and ghosts are `RaceView`, a view (ghosts on disk in
  `RaceView.GHOST_PATH` only while `Profile.persist`). In a race world the
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
  `OS.add_logger` counter; fix the cause of anything it catches, never
  silence it. A spring stepped by `delta` is stepped in short slices (a
  long frame throws it off), and a deferred call or timer that outlives
  the node it acts on is bound to that node (`node.queue_free`, an
  instance id), never a lambda capturing it.

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
