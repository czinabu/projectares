# Project Ares: notes for AI sessions

Full-loot PvPvE war game in Godot 4 (GDScript). Each world is an endless
warzone, not a timed raid (see the endless warzone rule below). See README.md for the
layout and how to play. The roadmap is: Phase 0 bot-only prototype (done),
Phase 1 vertical slice (hub, loadouts, abilities, motorbike), Phase 2 online
PvPvE on a dedicated server, Phase 3 full Ashfront, Phase 4 a second world.

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
  and getting off restores the on-foot view.
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
- Mastery pays for using gear, never for leaving alive, or signing out over
  and over would farm it.
- Blocking and parrying happen in `Weapon.modify_incoming`, which `Combat.deal`
  calls for every hit. Every melee attack keeps a visible windup so it can be parried.
- Melee is directional. The stance travels in `ActorCommand.stance`, attacks
  set `DamageInfo.direction`, and `MeleeWeapon.guard_covers` decides whether a
  guard stops a hit. Windup and guard poses must show their side.
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
  gun or two-handed weapon slung across the back, outside a worn back rig, a
  sidearm muzzle down on the right hip, and a one-handed blade on the left
  hip. These are view-only copies; the weapon's own node stays on the hand.
  A switch is shown as the hand putting one away and drawing the next
  (`ActorSkin._update_switch`, reaching through `WeaponArm.override_point`),
  but only the view waits: the actor switches at once. The holster key (Z)
  sends `switch_weapon = ActorCommand.HOLSTER` and draws `Actor.last_drawn`
  again; it is an index, never a toggle, so it replicates safely. Check with
  `--holster-only`.
- People are built from parts (`core/visual/human.gd`): an "appearance" names
  a build, four parts and colours. It is cosmetic only and never trusted:
  always pass one through `Look.clean_appearance` / `Look.set_appearance`,
  which is safe on a headless server. Online it travels in the spawn data as
  `data["look"]`; the server keeps what each signed-in player sent
  (`NetSession.look_for_peer`). `Raid` and gameplay never read it.
  A look changed while in a world (the phone's Mirror app) is checked by the
  server in `_request_look` and passed to everyone there with `_look_changed`.
  The mirror itself (`core/visual/mirror.gd`) is a client-side view: no
  collision, and nothing in `Raid` reads it. In first person the body is drawn on
  `Mirror.BODY_LAYER`, which their own camera leaves out
  (`PlayerController.body_layer`), so only the mirror shows it.
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
- Flight rigs and abilities are data too. `FlightRig` and `Ability` are single
  classes whose item stats pick the behavior. Abilities fire from
  `ActorCommand.ability_pressed`.
- Helmets are items tagged `helmet` in the `helmet` loadout slot, and data
  like abilities: `Visor` (`core/abilities/visor.gd`, `Actor.visor`) is one
  class whose `mode` stat picks what the visor does ("" plain, "zoom"
  binoculars, "scan" pulse). It is driven by `ActorCommand.visor_pressed`
  (a press: scan) and `ActorCommand.visor_level` (held: the zoom level).
  What a visor reveals is decided by the authority only and never goes to
  everyone: `NetSession` sends a scan's snapshots to the scanner, the ping to
  each player caught, and a tag to the tagger's side. Reveals must stay fair:
  a scan is a snapshot, never live tracking, and every reveal is felt by its
  target (the ping, the lens glint). The picture is `VisorHud`
  (`core/ui/visor_hud.gd`), a view: its glass is drawn in first person only
  and only while a helmet is worn (Caleb agreed a visor counts as in-world,
  since you look through it); what a visor shows out in the world (snapshots,
  tag markers, pulse rings, glints) is there in either view. Apart from the
  thin health arc, do not repeat the wrist on the glass (ammo, the map,
  standing): the wrist shows you, the visor shows what is around you. Mk2
  helmets are loot only. Check the glass by eye with
  `visual_check.tscn -- <dir> --visors-only`.
- Vehicles are items tagged `vehicle`, tuned by their stats, and spawned by
  `Raid` (never carried). `core/vehicle/vehicle.gd` reads its rider's
  `ActorCommand` and moves the rider; `Actor` skips its own movement while
  `Actor.vehicle` is set. The script has no `class_name`; preload it.
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
- Online movement: a client numbers every input and sends the last few in
  each packet; the server plays them in order, one per tick, and each state
  entry carries the input number it had reached. The client corrects its own
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
  a name in `SocialService.PLACE_NAMES`. Settings live in
  `core/settings/game_settings.gd` (its own save file); a server never reads them.
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
  Using a display only emits `equip_requested`; `main.gd` applies it through
  `Profile` or `NetSession.equip`. Like `Raid`, `HomeBase` has no camera, HUD
  or input code, and its displays are greybox shapes that `Look` dresses
  (any node with the meta `display_item`).
- The game opens in the world, never on a menu screen. Solo it boots into the
  home base; online, joining a server puts you in its plaza, and a world's
  lobby is the home base again on the server's stash. `Hub` (`core/ui/hub.gd`)
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
- The watch and the phone split the job (Caleb's rule). The holographic
  watch (`Hud.Wrist`, raised with X) is for gameplay: vitals, pack, ammo,
  heat, standing and strongpoints, landing choices, and future in-raid
  actions such as calling something in. The phone is for settings, talking
  to friends and players, and information (news, the war feed). A new
  in-raid action goes on the watch; a new social or info feature is a
  phone app.
- Money (`core/economy/`): the rules live once, in `economy.gd` (static, like
  `StashRules`), shared by `Profile` and `StashService`. Online, `credits`
  lives on the server's account and only changes there: through
  `StashService.buy` / `sell`, the payout in `settle`, or `change_credits`
  for other server systems. A client never sends a price or an amount.
  Shops are tag-driven: an item is stocked if it has the `vendor` tag and one
  of the shop's tags (`shop_db.gd`), and `Economy.is_shop_item` refuses
  anything above Uncommon, so rare gear stays loot-only. Keep every sell
  price below its buy price, and keep run payouts small next to loot: credits
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
  sends. Credits change only through `StashService.change_credits` online and
  `Profile.change_credits` solo.

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
```

To see it rendered (needs a display or xvfb):

```
godot --path . res://tests/visual_check.tscn -- /some/output/dir
```
