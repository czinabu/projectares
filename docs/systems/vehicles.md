# Vehicles

Rules for vehicles, riding, seats, aircraft, drifting and toy vehicles on the watch. These are part of the rules in `CLAUDE.md` that must not be
broken: read this file before changing anything it covers, and keep it up to
date in the same PR.

- Vehicles are items tagged `vehicle`, tuned by their stats, and spawned by
  `Raid` (never carried). `core/vehicle/vehicle.gd` reads its rider's
  `ActorCommand` and moves the rider; `Actor` skips its own movement while
  `Actor.vehicle` is set. The script has no `class_name`; preload it.
  Vehicles are on `Actor.LAYER_VEHICLES` (`Vehicle.LAYER_VEHICLES` is the
  same layer), which every actor's mask includes, so people bump into a
  vehicle instead of walking through it; a rider and its machine keep
  collision exceptions with each other.
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
  `model` stat picks the body ("bike", "hoverbike", "rover", "mech",
  "jet"), built by `core/vehicle/vehicle_model.gd` in the sci-fi style the
  rigs wear (bevelled shells cut into panels, lit seams in the rarity
  colour, cyan thrusters; glass and glows are material overrides `Look`
  leaves alone, a lamp a surface glow it hangs a beam on) round the
  item's own anchors, so a restyle never moves a seat or a hitbox; check
  them side by side with `visual_check.tscn -- <dir> --vehicles-only`,
  `body_size` its collision box, `pivot_turn` lets a walker turn on the
  spot, `jump_speed` gives it a jump-jet hop, the "hover" tag floats it on
  a cushion ("hoverbike", the Raider: it drifts through turns by `slip`,
  which travels in the ride state and is corrected like `speed`, holds
  level over a gap for `hang_time` and hugs the ground off a ramp, never
  flying), `passenger_seat` adds passenger seats
  (`Vehicle.seats`, by default one pillion behind the rider from the
  `pillion_*` vars; the rover lists three, so it seats four, Caleb's call;
  `Vehicle.passengers`, `mount(actor, true)`, which takes the free seat
  nearest them; the seat's interact puts the next player there; a
  passenger is seated by the same riding pose from their seat's anchors,
  `Vehicle.ride_anchor`, each makes it heavier, the `laden_*` shares, and
  only the server decides who sits where, sent in the ride state; check anything that asks whether a vehicle is free with
  `is_occupied`, never `rider` alone), `cargo_points` gives it cargo
  space for salvage crates, one a point (`Vehicle.cargo`; the rover four,
  the bikes one; see `docs/systems/dunes.md`), and the "aircraft" tag flies
  it (`Vehicle._fly`: takes off past `takeoff_speed` with jump, never
  hovers, drops below `stall_speed` or with nobody at the stick, climbs no
  higher than `ceiling` over the world's ground). Jump is the handbrake
  (`handbrake`, off for the mech and the jet, whose jump key is theirs):
  at speed it is a drift (`Vehicle.drifting`, the same `slip` a hover
  keeps, `drift_*` stats) whose clean exit on the throttle is a short
  burst (`drift_charge`, `_drift_exit`), and a world's slick ground
  (`WorldDef.surface_grip`, Frostline's snow and ice) lets wheels slide
  on their own; a hover ignores it. Every vehicle, the jet
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
