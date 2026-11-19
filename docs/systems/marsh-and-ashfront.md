# The Spore Marsh and Ashfront's scenery

Rules for the Spore Marsh's wildlife, fouling and spores, and Ashfront's scenery army and low sky. These are part of the rules in `CLAUDE.md` that must not be
broken: read this file before changing anything it covers, and keep it up to
date in the same PR.

- The Spore Marsh (DESIGN.md "The Spore Marsh", `worlds/marsh/`): a co-op
  PvE world whose enemy is wildlife, each kind a faction of its own
  (stalker, shellback, bloater) that hunts the others and never its own.
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
  view. Check by eye with `visual_check.tscn -- <dir> --marsh-only`.
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
