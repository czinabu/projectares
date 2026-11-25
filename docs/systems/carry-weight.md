# Carry weight

Rules for what items weigh and what a load does to moving (DESIGN.md
section 4, "Weight"). These are part of the rules in `CLAUDE.md` that must
not be broken; change this file in the same PR as the code.

- `CarryLoad` (`core/items/carry_load.gd`) is the whole rule set, all
  static: `weight_of(id)` (an item's `weight` stat, else the first of its
  tags in `TAG_WEIGHTS`, else `OTHER_KG`), `total`, `of_actor` (the body's
  `get_drop_items`: worn gear, the heavy weapon in the chamber and the
  pack's contents), `tier` ("light" under `LIGHT_KG`, "heavy" from
  `HEAVY_KG`), and the multiples `speed_mult`, `accel_mult`, `heat_mult`
  (with `heavy_lift`, a jetpack, taking `HEAVY_LIFT_SHARE` of the extra)
  and `jump_mult` (only over `HEAVY_KG`). A medium load is exactly 1.0 in
  all of them, so tuning elsewhere stays true for an ordinary kit.
- Never a hard limit: nothing is refused for its weight, and every multiple
  has a floor (`MIN_SPEED`, `MIN_ACCEL`, `MIN_JUMP`) or cap (`MAX_HEAT`).
  A rig's top flight speed is never scaled.
- Weight is data. A new item gets a weight from its tags; give it a
  `weight` stat only when it differs from its kind. `Loadout._apply_stats`
  skips "weight" (it is not a property of the weapon or rig). Vehicles keep
  their own `weight` stat in tonnes for thin ice; `weight_of` gives them 0.
  Frames and packs have no `speed_mult`, `heat_mult` or `sprint_mult` any
  more (a test checks none come back): what they cost is their weight.
- `Actor` keeps the load: `carry_kg()`, and `carry_speed`, `carry_accel`
  and `carry_jump`, worked out lazily by `refresh_carry` at the start of a
  movement step when `mark_carry` has flagged a change. Anything that
  changes what a body carries without going through `Inventory.add_item`
  / `remove_item` (which emit `changed`), `equip_weapon`, `replace_weapon`,
  `remove_weapon` or `Loadout.equip` / `wear_*` calls `mark_carry`
  itself. `refresh_carry` also sets `FlightRig.load_heat`, which
  `FlightRig._heat` multiplies every bit of heat by; `Loadout.wear_rig`
  resets the rig, so it marks the load too. Loads are snapped to
  `STEP_KG`.
- Where it is used: the ground and air speed (after the held weapon's and
  the rig's own multiples), `ground_accel` and `air_accel`, the rig's
  cruise acceleration and turn rate, the slide's start speed, the jump's
  take-off speed, and the skin's gait pace (`ActorSkin`, so legs keep up
  with a slower body).
- Online: a client never sees anyone else's pack, so the server sends the
  load itself. `Actor.carry_changed` (emitted by `refresh_carry` when the
  number changes) is passed on to every joined peer as
  `NetSession._carry(id, kg)`, and `_send_spawn` sends it after each spawn.
  On a client the body uses `Actor.carry_sent` once it has one, its own
  guess from what it can see until then, so prediction matches the server.
- Shown on the watch: `Hud.pack_text` (the pack's line under Summon) reads
  "Pack 10/16 · Medium 24 kg · worth ..." via `CarryLoad.label`. Item cards
  (`ItemCard.facts`) end with "Weighs N kg". No flat overlay.
- Check with `tests/carry_weight_tests.gd` (weights, the curves, a load
  worn into a world, and a light, medium and heavy kit run and jumped on
  flat ground) and the carry check in `tests/online_movement_tests.gd`.
