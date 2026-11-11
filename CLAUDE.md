# Project Ares: notes for AI sessions

Full-loot PvPvE extraction game in Godot 4 (GDScript). See README.md for the
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
- Blocking and parrying happen in `Weapon.modify_incoming`, which `Combat.deal`
  calls for every hit. Every melee attack keeps a visible windup so it can be parried.
- Melee is directional. The stance travels in `ActorCommand.stance`, attacks
  set `DamageInfo.direction`, and `MeleeWeapon.guard_covers` decides whether a
  guard stops a hit. Windup and guard poses must show their side.
- Sound and visual effects (`Sfx`, `Fx`) must stay no-ops on a headless server.
- Items are ids defined in `ItemDB` with tags. Use tags, not id checks, to
  decide what an item does.
- Gear behavior comes from the item's `stats` in `ItemDB`, applied by
  `Loadout.equip`. Add a new gun or frame as data, not as a new class.
- Flight rigs and abilities are data too. `FlightRig` and `Ability` are single
  classes whose item stats pick the behavior. Abilities fire from
  `ActorCommand.ability_pressed`.
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

## Conventions

- A helper used by a single script is an inner class of that script, not a new
  `class_name` file.
- New `class_name` scripts only resolve after Godot rescans the project. The
  `Boot` autoload (`core/boot.gd`) detects a stale class list, runs the import
  step and restarts once. Keep `Boot` first in the autoload list and free of
  any project class.
- Typed GDScript, tabs, `class_name` for anything reused. Tuning values are
  plain `var`s at the top of the class.
- Greybox visuals are built in code for now. Hand-built `.tscn` scenes are
  fine once real art arrives; keep the map contract.
- Every gameplay feature gets checks in `tests/test_runner.gd`.

## Verify before committing

The project targets Godot 4.7 (what Caleb runs, and what CI uses).

```
godot --headless --path . --import
godot --headless --path . res://tests/test_runner.tscn   # must exit 0
```

To see it rendered (needs a display or xvfb):

```
godot --path . res://tests/visual_check.tscn -- /some/output/dir
```
