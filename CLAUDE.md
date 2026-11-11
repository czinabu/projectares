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
  when the player presses the toggle (playtest feedback).
- `Raid` has no camera, HUD, or input code. It must keep working headless.
- Blocking and parrying happen in `Weapon.modify_incoming`, which `Combat.deal`
  calls for every hit. Every melee attack keeps a visible windup so it can be parried.
- Sound and visual effects (`Sfx`, `Fx`) must stay no-ops on a headless server.
- Items are ids defined in `ItemDB` with tags. Use tags, not id checks, to
  decide what an item does.

## Conventions

- Typed GDScript, tabs, `class_name` for anything reused. Tuning values are
  plain `var`s at the top of the class.
- Greybox visuals are built in code for now. Hand-built `.tscn` scenes are
  fine once real art arrives; keep the map contract.
- Every gameplay feature gets checks in `tests/test_runner.gd`.

## Verify before committing

```
godot --headless --path . --import
godot --headless --path . res://tests/test_runner.tscn   # must exit 0
```

To see it rendered (needs a display or xvfb):

```
godot --path . res://tests/visual_check.tscn -- /some/output/dir
```
