# Project Ares

A full-loot PvPvE extraction game with plug-in worlds, built in Godot 4.
Drop into a world with gear you are willing to lose, fight and loot, and reach
an exit before the storm closes. Die and everything you carried stays behind.

This is the **Phase 0 prototype**: a raid against bots that proves the core
loop and lays the foundation for online play and more worlds. Gameplay shapes
are still simple boxes; a first art pass dresses them with real surfaces,
skies, animated models and effects (see "How it looks" below).

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
| Scoreboard: who is still in, who got out, kills | Hold Tab |
| Open your phone: players, messages, invites, news, settings | P |
| Free the mouse | Esc |

The jetpack runs on heat. Overheat it and you fall until it cools. Rooftop
caches hold the best loot, and only the jetpack gets you there.

After you pull new code, the first launch may show "Updating the project" for a
few seconds and restart on its own. That is Godot learning about new scripts.

## Play online (early test)

The hub has an **Online** section.

- **Host a raid and join it** starts a server on your computer and connects you to it.
- **Join a raid at this address** connects to someone else's server. On the same
  network, that is the host's local address, for example `192.168.1.20`.
- Connecting puts you in that server's lobby. The hub now shows the stash and
  loadout **the server keeps for you**, which is separate from your solo stash.
  Pick your gear and press **Deploy online**. After a raid you come back to the
  lobby.
- The server knows you by your name plus a private key your game creates the
  first time. Everyone on a server needs a different name. A new name starts
  with the same starter crates as a solo profile.
- Losing your connection in the middle of a raid counts as a death.
- To try it alone, run two copies of the game. In the Godot editor use
  Debug, Customize Run Instances, and enable two instances. Host in one window
  and join `127.0.0.1` in the other.

### Your phone

Every player carries a phone, and it is the game's menu. Press **P** (or the
phone button in the hub) to open it, in the hub or in a raid. While it is out
your character stands still and the mouse is free.

- **People**: everyone signed in to the same server, and where they are (lobby
  or raid). Message them, invite them to the raid or to your home base, save
  them as a contact, or block them. Saved contacts can be messaged while
  offline; they see it at their next sign-in on that server.
- **Chat**: your conversations. New messages also pop up at the top of the screen.
- **Invites**: accept or decline. A raid invite deploys you into that server's
  raid from the lobby. Invites run out after two minutes.
- **News**: game news, plus anything the server adds. A server operator drops a
  `news.json` (a list of `{"date", "title", "body"}`) in the accounts folder.
- **Settings**: mouse sensitivity, invert mouse, melee side control, field of
  view, volume, fullscreen and nameplates. Saved in `user://settings.json`.

Players, chat and invites need a server; news and settings work solo too.

A server can also run on its own, with no window:

```
godot --headless --path . -- --server --world ashfront --port 24565
```

That runs the plaza on port 24565 and Ashfront on 24566. Leave out `--world`
to run every raid world, or add `--no-plaza` for one world alone on the port.

### The Concourse

Joining a server puts you in its plaza, the Concourse: a walled safe zone
shared by everyone on that server. Weapons are locked and nobody can be hurt.
You appear wearing your equipped loadout, and it never leaves your stash, so
nothing is at risk there. Look at another player to see what they are wearing.
A bike in your loadout is parked beside you to ride around.

Walk into a glowing pad and press **E** to use it:

- **World gates** (north): each leads to that world's lobby, where you set
  your loadout and deploy. After a run, or when you leave the lobby, you are
  back in the Concourse.
- **Quarters** (west): the door to your home base. Its door leads back here.
- **Storefronts** (the corners): one for every shop. Step up to the counter
  to buy and sell without leaving the plaza.
- **Arena** and **Clan hall**: built, and closed until those features arrive.
- **Exit** (south): leaves the server.

Add `--accounts <folder>` to choose where the server saves player stashes.

To feel what a bad connection is like without leaving your desk, start the
game (not the server) with `-- --lag 120 --loss 10`. That adds 120 ms of delay
each way and drops 10 percent of your input packets. Your own movement should
still feel immediate, and so should riding a bike. Shots are lag compensated:
aim straight at what you see and the server checks the hit against where the
target was on your screen. Start a server with `--no-rewind` to feel the
difference.

What works online so far: seeing and fighting other players and bots, looting
caches and bags, and riding vehicles, with the server deciding every hit,
death, pickup and extraction. The server also owns your online stash: your
game never tells it what gear you have.

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
- A home base you walk around in, reached from the hub. Everything in your
  stash is on show: guns on a rack, blades on the wall, armor on stands,
  flight rigs, ability chips, bikes parked in the garage, loot on shelves.
  Look at a piece of gear and press E to equip it for your next run.
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
  visual/        The art layer (`Look`): surfaces, atmosphere, models, effects, UI theme
  profile/       Stash and stats that persist between raids (local play)
  base/          The home base: a room that puts the stash on show
  account/       Server-owned stashes for online play, and the shared gear rules
  progression/   Mastery: tracks and variants, XP tracking in a raid, hub panel
  net/           Online play: the server and client ends of a raid
worlds/
  plaza/         The Concourse: the social safe zone (a world with safe_zone set)
  ashfront/      The first world: rules, loot tables, and its map
  frostline/     A second, smaller world that proves the plug-in contract
assets/          Models, textures, sky, font and shaders, with LICENSES.md
tests/           Headless test suite and a screenshot tool
```

Three rules keep the foundation solid:

1. **Worlds are plug-ins.** Core code talks to a world only through `WorldDef`.
2. **Actors are driven only by commands.** The player, bots, and later remote
   players all fill in an `ActorCommand`. The simulation never reads the
   keyboard, so it can run on a dedicated server.
3. **All damage goes through `Combat.deal`**, which asks the world whether the
   hit is allowed. PvP rules live in the world, not in weapons.

## How it looks

The look is gritty sci-fi: worn concrete and rusted metal, a photographed sky,
haze, and weathered machines. All of it lives in one layer, the `Look`
autoload in `core/visual/`, so gameplay code stays plain:

- Maps build boxes and ask `Look.surface("concrete", {...})` for a material.
  Surfaces are world-space, so a box of any size tiles correctly. Options add
  windows, grime, puddles and snow.
- `Look.atmosphere(map, {...})` sets the sky, sun, fog and color grade, and
  `Look.weather` fills the air with embers, snow or ash.
- `Look` watches the scene tree and dresses what the game spawns: actors get
  animated models, guns get models picked by item tag, caches become crates.
  A world picks a bot's model with `bot.set_meta("look", "<skin>")`.
- On a headless server `Look` does nothing, so the simulation never depends
  on art.

Every asset is CC0 or OFL. Sources and licenses are in `assets/LICENSES.md`.

## Add a world

1. Copy `worlds/frostline` (the smaller example) to `worlds/<your_world>`.
2. In `world.gd`, change the id, name, loot tables and rules.
3. Items that only exist in your world go in `register_items()`. Prefix their
   ids with the world id. Once stashed they work in every world.
4. Build a map that provides the markers listed at the top of
   `core/world/world_def.gd`. Give it a mood with `Look.atmosphere` and
   surfaces from `Look.surface`.

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

## Host a server online

To run a dedicated server on a cheap cloud machine so friends can join, follow
[docs/hosting.md](docs/hosting.md). It uses the `Dockerfile` and `compose.yaml`
in this folder and the **Linux Server** export preset.
