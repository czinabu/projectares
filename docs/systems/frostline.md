# Frostline

Rules for the cold, warm beacons, tracks, thin ice, the defence grid and the Engine's inside. These are part of the rules in `CLAUDE.md` that must not be
broken: read this file before changing anything it covers, and keep it up to
date in the same PR.

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
  lanes, each warning before it hurts through `Combat.deal`
  (`WorldDef.on_keeper_phase` lets a world change how it fights at each
  turn). A keeper caught in a dash-strike against one of its "boss_snag"
  markers is staggered (`_check_snags`, `keeper_snag_news`). A keeper with
  "boss_pool" markers dives (`_tick_dive`, `WorldDef.keeper_dive_*`): its
  brain holds it under (`BotBrain.held_under`, a crouch every machine
  sees), `Actor.submerged` turns every hit away in `Combat.deal`, and it is
  set down at the pool nearest one of the players in its arena to rise
  (`held_still`) before it fights again. It carries
  nothing; when it falls (`_keeper_fell`) everyone who hurt it or stood in
  its arena gets a share from its "vault" (`WorldDef.roll_vault`), a
  `LootContainer` only its owner may loot (`reserved`), cleared when it
  wakes again, and markers that wait on it (a "beacon" or "warmth" with
  its kind as meta "keeper", `Raid.waits_on_keeper`) light. Clients get
  the phase (`Raid.keepers`, `NetSession._keeper`, the map's "keepers"
  meta) and the lanes (`Raid.purge_changed`, `NetSession._purge`, drawn
  by the map's `show_purge`). Check by eye with `visual_check.tscn -- <dir> --engine-only`.
