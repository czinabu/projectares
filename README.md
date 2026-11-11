# Project Ares

A full-loot PvPvE extraction game with plug-in worlds, built in Godot 4.
Drop into a world with gear you are willing to lose, fight and loot, and reach
an exit before the storm closes. Die and everything you carried stays behind.

This is the **Phase 0 prototype**: a greybox raid against bots that proves the
core loop and lays the foundation for online play and more worlds.

## Play it

1. Install [Godot 4.4 or newer](https://godotengine.org/download) (standard build).
2. Open `project.godot` in Godot.
3. Press **F5**.

| Action | Key |
| --- | --- |
| Move / sprint | WASD / Shift |
| Jump, hold to fly with the jetpack | Space |
| Dash | Q |
| Fire, or light attack | Left mouse |
| Aim down sights, or heavy attack (dive slam in the air) | Right mouse |
| Switch to rifle / blade | 1 / 2 |
| Reload | R |
| Use a medkit | H |
| Loot | E |
| Camera: auto, first-person, third-person | V |
| Free the mouse | Esc |

The jetpack runs on heat. Overheat it and you fall until it cools. Rooftop
caches hold the best loot, and only the jetpack gets you there.

## What is in the prototype

- First-person and third-person camera. Auto mode uses first-person with guns
  and third-person for melee and flight. Aiming always snaps to first-person.
- Hitscan rifle with reloads and aim down sights.
- Blade with a three-hit combo, a heavy lunge, and a dive slam from the air.
- Health with a degrading armor layer, medkits, and a dash.
- Jetpack flight limited by heat.
- Scavenger bots that patrol, chase and shoot, and drop loot bags.
- Loot caches with five rarity tiers, a backpack, and a stash that persists.
- Two exits, a raid timer, and full loot on death.

## How the code is organized

```
core/            Shared by every world. Never names a specific world.
  actor/         Actor (the character) and ActorCommand (one tick of intent)
  combat/        Health, damage, guns, melee
  flight/        Flight rigs
  items/         Item database, inventory, loadouts
  interact/      Loot containers
  raid/          Raid flow and extraction zones
  world/         The world contract (WorldDef) and the world registry
  ai/            Bot brain
  player/        Local input and camera
  ui/            HUD and hub
  profile/       Stash and stats that persist between raids
worlds/
  ashfront/      The first world: rules, loot tables, and its map
tests/           Headless test suite and a screenshot tool
```

Three rules keep the foundation solid:

1. **Worlds are plug-ins.** Core code talks to a world only through `WorldDef`.
2. **Actors are driven only by commands.** The player, bots, and later remote
   players all fill in an `ActorCommand`. The simulation never reads the
   keyboard, so it can run on a dedicated server.
3. **All damage goes through `Combat.deal`**, which asks the world whether the
   hit is allowed. PvP rules live in the world, not in weapons.

## Add a world

1. Copy `worlds/ashfront` to `worlds/<your_world>`.
2. In `world.gd`, change the id, name, loot tables and rules.
3. Build a map that provides the markers listed at the top of
   `core/world/world_def.gd`.

The hub finds it automatically and adds a deploy button.

## Run the tests

```
godot --headless --path . --import
godot --headless --path . res://tests/test_runner.tscn
```

The suite plays real raids without a window: movement, flight, shooting, melee,
looting, extraction, death, the storm timer, and bot behavior.
