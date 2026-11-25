# The home base

Rules for the modular base, its rooms, the plan table, the bench, the range and course, and upgrades. These are part of the rules in `CLAUDE.md` that must not be
broken: read this file before changing anything it covers, and keep it up to
date in the same PR.

- The home base (`core/base/`) is a view of a stash, never a second store.
  `HomeBase.show_gear(stash, loadout)` rebuilds the room from plain data, so
  it shows the local `Profile` solo and the server's account snapshot in a
  lobby. `core/base/base_layout.gd` decides what goes where from item tags.
  Whatever is worn is always on show (`BaseLayout.plan` gives it a spot
  even when better gear fills its section), so anything can be taken off
  in the room.
  While the launch scope holds them back (`docs/systems/launch-scope.md`),
  the lounge's doorway is sealed (`BasePlan.held`) and the trophy shelf and
  artifact case have no spots.
  The base is modular (Caleb's call, DESIGN.md "Home base"): a hub with seven
  doorways of one size (`BasePlan.SOCKETS`, `HomeBase.socket_transform`)
  and seven rooms standing in them, one each (`BasePlan.ROOMS`: armory,
  workshop, garage, ops, gear hall, stores, lounge). The seventh socket,
  "F1", is in the hub's front wall left of the door in the hall and the
  courtyard, and off the corridor's left wall in the spine and the ring,
  whose hub walls are full (`HomeBase.corridor_socket`,
  `CORRIDOR_SOCKET_FROM`); there the corridor runs longer to clear it, so
  ask `range_from`/`shape_range_from`, never a fixed length. The lounge's
  pieces are built by `_furnish_lounge` under a "LoungePieces" node and
  merged (`Look.merge_pieces`), with collision as separate boxes
  (`_lounge_solid`); its window view is one shader
  (`assets/shaders/lounge_view.gdshader`) only when `Look` is on, never a
  second world or camera. Which room stands where is the
  account's plan (`core/base/base_plan.gd`, static rules like
  `BaseUpgrades`; `Profile.base_plan` solo, the account's online, in the
  snapshot and in `StashRules.CARRIED`), always passed through
  `BasePlan.clean`. `HomeBase.show_gear` takes it as its fourth argument.
  Everything in a room is laid out in the room's own space
  (`HomeBase.room_spot`, `STATIONS`' "room", `BENCH_AT`) and placed through
  `room_transform`, so it moves with its room; a display kind's room is
  `HomeBase.KIND_ROOMS`. Ask where something is with `room_at` (and
  `in_armory`, `in_workshop`, `in_garage`), never with coordinates. The
  plan also picks the hub's shape (`BasePlan.SHAPES`: hall, ring, spine,
  courtyard; `HomeBase.HUB_SIZES`, `shape_socket`, `in_hub`, `range_from`,
  `front_half`, `mirror_at`, `deploy_span`, so ask those, never the hall's
  numbers) and each room's style (`BasePlan.STYLES`, three a room: where
  its displays, stations and bench stand, `_style_spot`,
  `style_station_spot`, and what furnishes it, `_furnish_style`; every
  style lays out every spot its room has, whole and small) and the finish
  the hub and each room wear (`BasePlan.FINISHES`, the plan's "finishes":
  steel free, then gunmetal, ceramic, brass, blackout), built through the
  shell's builders (`HomeBase.FINISH_LOOKS`: `_shell`'s surfaces, the
  seams, ribs, kick plates, ceiling light and lamps, `_lit`, set per area
  by `_finish`), never by a second set of builders. A shape or hub finish
  change rebuilds the shell (`_build_static`; the wall mirror only moves).
  The first shape, each room's first style and steel are free; any other
  (a finish bought once goes on any room) is a design
  unlock (`BaseUpgrades` track "Designs", `is_design`, never counted by
  `needs_count`), bought once with scrip and free to switch after (Caleb's
  call). The plan table in the middle of the hub (`HomeBase.PlanTable`) is
  the one place to change the plan: using it emits `plan_used` and
  `main.gd` brings the view in with the bench's view (`BenchView.target`
  "plan"), which mounts the customizer (`core/ui/plan_panel.gd`, a view)
  on the lectern's screen as a `WorldScreen` (`HomeBase.plan_screen`,
  forwarded with `WorldScreen.forward_mouse`; a change rebuilds the table,
  so the view puts the screen back each frame, but never once it has left:
  a screen left on the lectern shows the freed viewport, solid white,
  checked in `tests/plan_screen_tests.gd`): tabs for the layout, the
  rooms, the styles and the finishes, with whatever it points at shown on the hologram
  over the table (`plan_preview`, `plan_mark`). Only a pick asks for a
  change (`plan_change`, `room_placed`; `BasePlan.change` with a socket,
  "shape", "style:<room>" or "finish:<hub or room>"): `Profile.place_room` solo,
  `NetSession.place_room` online, decided by `StashService.place_room`,
  which checks the unlock is owned. An unlock is bought from the screen
  with a confirming click (`plan_buy`, `upgrade_requested`) and put in use
  once owned. A change is free, moves nothing in or out of the stash and is
  allowed while deployed. A new room
  needs a socket for it, not a spot in the hub. Room names are a plate over
  each doorway (`_name_plate`); the base has no banner and no other signs.
  Helmets sit on the helmet shelf over the armor stands in the gear hall.
  Every weapon goes on the one armory rack (`BaseLayout.ARMORY`, Caleb's
  call): its sections hang on the armory's walls (`HomeBase.in_armory`).
  Each weapon hangs on a lit mount (`HomeBase._build_mount`). The gunsmith
  bench and the fabricator beside it stand in the workshop
  (`in_workshop`), a room of their own, in the starter bunker too. The
  locker stands in the hub by the way out. The bench holds one gun at a
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
  only while its viewer is in front of it; it shows plain glass until its
  view has drawn, never the noise of an empty one). The hub keeps the deploy
  area (the wall mirror, with room in front to open a portal) along the
  front wall right of the exit (`HomeBase.deploy_span`), the plan table in
  the middle (Caleb's pick) and the rest of the floor clear. The shell is
  steel, never bare rock: plated floors, ribbed wall panels and a ceiling
  grid (`HomeBase._floor`, `_wall`, `_ceiling`; a trim stands off a wall's
  face, never on it, or the two shimmer), so a new space builds with
  those. Bikes park in the garage (`HomeBase.in_garage`). Down the corridor
  behind the hub, between the back rooms (`in_corridor`, `range_from`), is
  the firing range (`HomeBase.in_range`), which the plan never moves: the player's weapons unlock only there and
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
  `in_course`): a tall lit hangar, walled and roofed so nobody flies out
  (Caleb's call), its roof over every rig's ceiling and past
  `Actor.roof_reach` of it, so it never flies as indoors, with a climb tower (and a ramp for wings), a gap to a second
  tower and a sprint, timed by `_tick_course` from the player's position
  alone and written on its board, never on the screen.
  The base grows with the account's upgrades (`core/base/base_upgrades.gd`,
  static rules like `Economy`): a list of owned upgrade ids kept beside the
  stash and scrip (`Profile.base_upgrades` solo, the account's online, sent
  in the snapshot), never in the stash. `HomeBase.show_gear` takes it as its
  third argument; none is the starter bunker. `BaseLayout.spots(kind,
  upgrades)` is how many spots a display kind has. Every room stands from
  the start in its small form (`small_depth`, behind a sealed wall) and
  its upgrade (`BasePlan.ROOMS[room]["opens"]`, `room_open`, `room_depth`)
  opens the rest of it wherever it stands; `HomeBase` offers what is not
  owned (`_build_gates`: a post in each small room, the range's slab at the
  test lane's end, tags on the bench) as a `Bulkhead` with its price on it
  in the room.
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

- The wardrobe is a standing mirror, not a console (`HomeBase._dress_wardrobe`,
  `wardrobe_mirror`): using it turns you to the glass and brings the phone
  up on its Mirror app, which looks into that glass in first person and
  swings to the dressing room in third (`Main._use_wardrobe`). It shares
  nothing: until the ops consoles, the mastery bench and the records both
  share the trader's console (`HomeBase.MERGED`).
