# Project Ares

A full-loot PvPvE extraction game with plug-in worlds, built in Godot 4.
Drop into a world with gear you are willing to lose, fight and loot, and reach
an exit before the storm closes. Die and everything you carried stays behind.

This is the **Phase 0 prototype**: a greybox raid against bots that proves the
core loop and lays the foundation for online play and more worlds.

## Play it

1. Install [Godot 4.7 or newer](https://godotengine.org/download) (standard build).
2. Open `project.godot` in Godot.
3. Press **F5**.

| Action | Key |
| --- | --- |
| Move / sprint | WASD / Shift |
| Jump. In the air: hold to fly (jetpack), press to boost (thruster boots, glide wings), hold while falling to glide (glide wings) | Space |
| Use your ability | G |
| Dash | Q |
| Fire, or blade combo | Left mouse |
| Aim down sights, or block with the blade (tap just before a hit to parry) | Right mouse |
| Pick a melee side: left, right or overhead | Flick the mouse that way, or hold A, D or W |
| Switch how the melee side is picked (mouse flick or movement keys) | B |
| Heavy lunge with the blade (dive slam in the air) | F |
| Switch to rifle / blade | 1 / 2, or mouse wheel |
| Reload | R |
| Use a medkit | H |
| Loot, or get on and off a bike | E |
| Ride a bike: throttle, brake or reverse, steer, boost | W, S, A / D, Shift |
| Switch camera: first-person or third-person | V |
| Free the mouse | Esc |

The jetpack runs on heat. Overheat it and you fall until it cools. Rooftop
caches hold the best loot, and only the jetpack gets you there.

After you pull new code, the first launch may show "Updating the project" for a
few seconds and restart on its own. That is Godot learning about new scripts.

## What is in the prototype

- First-person and third-person camera that you switch with V. It never changes
  on its own. Weapons are visible in your hand in both views.
- Hitscan rifle with reloads and aim down sights.
- Rifle recoil that kicks your view and widens the spread under sustained fire.
- Blade with a three-hit combo, a heavy lunge, and a dive slam from the air.
- Directional melee. Flick the mouse left, right or up to pick a side. Attacks
  come from that side and a guard only covers the side it was raised on. Read
  the enemy's windup, or the yellow mark by the crosshair, and guard that side.
- Block and parry with the blade. A parry staggers the attacker and powers up
  your next hit. Attacks, blocking and dashing cost stamina.
- Hit markers, damage flashes, and placeholder sounds generated in code.
- Health with a degrading armor layer, medkits, and a dash.
- Jetpack flight limited by heat.
- Scavenger bots that patrol, chase and shoot, plus melee brutes that rush you.
  All of them drop loot bags.
- Loot caches with five rarity tiers, a backpack, and a stash that persists.
- Loadouts picked in the hub from your stash: primary weapon, melee weapon,
  flight rig and armor frame. Equipped gear is at risk. Extract and it comes
  home, die and it drops. Empty slots use a free scrap kit.
- Three kinds of flight rig: jetpacks for sustained lift, thruster boots for
  quick kicks upward, and glide wings that launch once and then soar.
- An ability slot. Phase Step blinks you forward, Kinetic Barrier cuts damage
  for a few seconds, Shock Pulse staggers everyone near you. Each has a cooldown.
- More gear to find: carbine, SMG, marksman rifle, shotgun, arc blade, breaker
  hammer, three armor frames, and a better jetpack.
- Motorbikes, the first vehicle. Put one in the vehicle slot and it is parked
  next to you when you deploy. Press E on any bike nobody is riding to take
  it, including someone else's. Extract riding a bike and it goes to your
  stash; die or leave it behind and it is gone. Abandoned bikes wait by jump
  ramps around the city. Riding uses the third-person camera (V still
  switches), and pressing E in mid-air bails out with the bike's speed.
- Mastery for every weapon type, ability and armor frame. Using gear earns XP
  for its type, levels unlock variants that trade one strength for another
  (never raw power), and you pick them in the hub. Mastery is kept when you die.
- Two exits, a raid timer, and full loot on death.

## How the code is organized

```
core/            Shared by every world. Never names a specific world.
  actor/         Actor (the character) and ActorCommand (one tick of intent)
  combat/        Health, damage, guns, melee
  flight/        Flight rigs
  vehicle/       Rideable vehicles (the motorbike)
  items/         Item database, inventory, loadouts
  interact/      Loot containers
  raid/          Raid flow and extraction zones
  world/         The world contract (WorldDef) and the world registry
  ai/            Bot brain
  player/        Local input and camera
  ui/            HUD and hub
  profile/       Stash and stats that persist between raids
  progression/   Mastery: tracks and variants, XP tracking in a raid, hub panel
worlds/
  ashfront/      The first world: rules, loot tables, and its map
  frostline/     A second, smaller world that proves the plug-in contract
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

1. Copy `worlds/frostline` (the smaller example) to `worlds/<your_world>`.
2. In `world.gd`, change the id, name, loot tables and rules.
3. Items that only exist in your world go in `register_items()`. Prefix their
   ids with the world id. Once stashed they work in every world.
4. Build a map that provides the markers listed at the top of
   `core/world/world_def.gd`.

The hub finds it automatically and adds a deploy button, and the
"Every world plugs in" tests run a raid in it. No core code changes.

### Frostline

A dead listening station on a glacier shelf, in whiteout fog. The layout is
round: a relay mast in the middle (its top cache is the richest on the map and
only flight reaches it), a ring of six outposts, and two rings of ice ridges for
cover. Two enemy factions share the ice and fight each other as well as you:
Wardens (slow, armored, long-range rifles) and Feral stalkers (fast, fragile,
melee). The raid is shorter (10 minutes) and exits take longer to hold. It adds
three items of its own: Cryo Cell, Signal Core and the Ice Axe.

## Run the tests

```
godot --headless --path . --import
godot --headless --path . res://tests/test_runner.tscn
```

The suite plays real raids without a window: movement, flight, shooting, melee,
looting, extraction, death, the storm timer, and bot behavior.
