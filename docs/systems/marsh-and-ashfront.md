# The Spore Marsh and Ashfront's scenery

Rules for the Spore Marsh's wildlife, fouling, spores and Rootways, and Ashfront's scenery army and low sky. These are part of the rules in `CLAUDE.md` that must not be
broken: read this file before changing anything it covers, and keep it up to
date in the same PR.

- The Spore Marsh (DESIGN.md "The Spore Marsh", `worlds/marsh/`): a co-op
  PvE world whose enemy is wildlife, each kind a faction of its own
  (stalker, shellback, bloater) that hunts the others and never its own.
  It keeps to its ground as encounter pockets (`pocket_wake` 90 m, a
  budget of 12; the map's `_bot_spot` names each one's pocket): a forest's
  pack with its hive keeper, a station's pair, the den's stalkers, a
  hummock's lone beast, a lurker's pool and each Rootway's gallery.
  Guns foul there (Caleb's call): with `WorldDef.gun_fouling` over 0 each
  shot adds to `Gun.fouling`, which widens the spread, clears once the
  trigger rests and at full jams the gun (`Gun.jammed`) until a reload; it
  is simulated in `Gun` from the command like the bloom, never touches a
  heavy weapon, and every other world leaves it at 0. A world's
  `death_burst(bot)` leaves a cloud where a bot dies (the bloaters'
  spores): only the authority keeps it (`Raid.burst_cloud`,
  `_tick_clouds`) and hurts everyone in it but its own faction through
  `Combat.deal`; clients hear of it through `NetSession._cloud` and draw
  it from `Raid.cloud_burst`. A beast's body is built in code like the
  walker's (`Look.SKINS` "creature", `ActorSkin._build_creature`), and a
  skin marked "bare" shows nothing in the hand. A world makes a kind
  feint more than its ring with the bot's "feint_chance" meta. Kinds that
  are one family (a brood keeper and its broodlings) share a kind through
  the world's `KIN`, which `can_damage` compares. A bot with the meta
  "lies_low" (the lurkers) sits crouched at its post until it sees
  someone, and a skin's "lurks" share sinks a crouched body (view only;
  the crouch is what replicates). A "spawn_guard" marker's "brood" metas
  make its guard spill extra bots near a player (`Raid._tick_brood`,
  authority only, counted in `is_guard`), and a cache marker's "hive"
  meta keeps that cache sealed while the guard with the same "hive" stands
  (`Raid._seal_hives`, `LootContainer.sealed`). The forests' close air is
  a planet's `close` mood the map blends in by its "close_here" meta
  (`Look.close_cover` brings the depth fog's floor down like a storm's),
  view only; what a bot sees there is `WorldDef.sight_at`, never the
  view. Rain storms are the shared weather with `weather_kind` "rain"
  (`RAIN_*` in `worlds/marsh/world.gd`): sight, shot and footstep reach
  and fouling all come from the cell where it happens, and down a
  Rootway is out of it (`sheltered_at`). Their look and sound are the
  "rain" weather kit (`Look.WEATHER_KITS`, its "sound" a synthesized
  `Sfx` loop), view only. Its scale and floor are view only (`worlds/marsh/flora.gd`,
  built by the map where `Look` is on): far giants drawn in the haze
  (`giant_haze.gdshader`, standing at `Flora.giant_spots`, veiled under
  the caps and in a storm by `Flora.set_veil`) and the forest floor's
  plants, one MultiMesh a kind on dry ground clear of the stalks, from
  their own seed. A beast's hide is `creature.gdshader`
  (`ActorSkin._creature_hide`, freckled by `CREATURE_FRECKLES`, which
  every "creature" kind needs an entry in), patterned in the piece's own
  space so it stays on the body. Check by eye with
  `visual_check.tscn -- <dir> --marsh-only`.
- The Rootways (DESIGN.md "The Spore Marsh (the Rootways)",
  `worlds/marsh/rootway.gd`): the marsh's dungeons, part of the one
  running world, laid out alike in each one's own frame (`Rootway.frame`:
  x across, z inward from the mouth, y the world's height) from
  `Rootway.ROOTWAYS`, whose mouths sit on whole even metres so the cut
  lies on the ground's samples. The cut is a hole in the ground
  (`Rootway.holes`, set on the `Terrain` before its collision and mesh are
  made, also off the main thread in `prepare_shared`), the black water is
  drawn round it (`water_pieces`), and nothing of the floor's dressing
  grows in it (the map's `in_cut`). Everything under the ground stays
  under the deepest pool's bed (`ROOF` plus its thickness). Each Rootway
  is its own `NavigationRegion3D` holding only what is walked on and round
  (floors, the pillar's foot, the knots); its walls and roof sit beside it
  so no mesh is baked over their tops (baking them with the open ground
  tangles the layers), and a `NavigationLink3D` joins the ground at the
  mouth to the ramp. Inside (`Rootway.inside`) is sheltered and in close
  air for the view (the map's "close_here") and for bots (`sight_at`). Its
  keeper runs on the `Raid`'s keeper machinery (see `frostline.md`): its
  sockets, vents and vault are markers named by its kind in "keeper", the
  world builds it in `make_warlord` from the "boss" meta, `roll_vault`
  pays its shares, and the map draws the vents (`show_purge`, indexes
  in "purge" marker order) and lights the chamber from the "keepers" meta
  (`Rootway.animate`), view only. The passage and chamber sit `BEND` across
  from the line of the mouth; `Rootway.inside` and `way_at` know it, so
  anything placed past the gallery adds it. Every gap in it is 9 m or more.
  Each entry in `ROOTWAYS` names its keeper's kind, the faction it is made
  from, what it calls out of its sockets ("" for no sockets) and whether
  its chamber stands snags (`SNAGS`, "boss_snag" markers, solid trunks in
  the floors' body so bots path round them) instead of the low knots. A
  way's vents are `VENTS.size()` "purge" indexes from `index *
  VENTS.size()`. The Shellback Elder's charge is a dash-strike with
  `MeleeWeapon.dash_through`, started by its brain as any dash-strike is
  ("dash" 1.0, "dash_every" by phase through `WorldDef.on_keeper_phase`),
  and its snags stagger it through `Raid._check_snags` on the authority,
  so the stun reaches clients with the actor's state. A way with "pools"
  floods its chamber (`FLOOD`, view only) and places "boss_pool" markers
  (`POOLS`); its keeper dives on the Raid's keeper machinery, and the map
  stirs a pool's ring while that keeper's body is down at it
  (`Rootway.animate` with the bodies the map finds by their "boss" meta,
  at most once a second while one is missing): its crouch, which every
  machine has from its commands, is what says it is down. Check by eye with
  `visual_check.tscn -- <dir> --rootway-only [--way N]`.
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
  `--fixed-fps 60`). The busy low sky over it is view only too
  (`worlds/ashfront/lowsky.gd`, the map's `make_low_sky`): gunships rake
  only scenery fights (`may_rake`: as far from everyone as a fight is
  placed) and wrecks come down only past the rim; check with
  `--sky-only`.
