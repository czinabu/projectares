# Project Ares: game design

This is the plan every thread builds against. It describes the game we are
aiming for, not only what exists today. What is built and what is still
missing is tracked in [design-gaps.md](design-gaps.md).

How to use it:

- Before building a feature, read its section here. If the code and this doc
  disagree, the code describes today and this doc describes the target.
- The rules in `CLAUDE.md` still apply to how anything is built. When a
  feature here changes one of those rules (for example power weapons becoming
  storable), update the rule in `CLAUDE.md` in the same PR that builds it.
- When Caleb makes a design call, record it here in the same PR.
- Section 12 lists the decisions still open. Do not settle them silently.

Sources: Caleb's design conversation (November 2026), the review of it in
the project chat, and the aerial rig proposal "Aerial gadgets: identities and
balance" (https://claude.ai/artifact/5oqEMAXpKisXTojV9w47pv).

## 1. The pitch

A full-loot PvPvE war game in the spirit of Planet Doom: you drop into an
endless warzone with gear you are willing to lose, fly, ride and fight
through it, and get your loot home. Worlds are plug-ins, so new planets can
be added later without touching the core.

Two standing rules shape every feature:

- **Immersion.** Interfaces work through the world: a console you walk up
  to, a screen on a wall, the phone, or the watch. Flat menus and
  screen-space overlays are a last resort, and Caleb is asked before one is
  built (accessibility, a critical error, or something that cannot work
  in-world).
- **Watch vs phone.** The holographic wrist watch is for gameplay: vitals,
  pack, ammo, heat, landing choices, vehicles, the heavy weapon and anything
  else used in action. The phone is for settings, friends and players, and
  information.

## 2. The places

The game has five kinds of place. Each world is a `WorldDef` plug-in, so a
new planet is a new folder under `worlds/`.

| Place | Today | Role in the loop |
| --- | --- | --- |
| Main hub | The Concourse (`worlds/plaza`) | Social space. Show off cosmetics, rigs and watch skins. Doors to every world, the shops, the clan hall and the arena. Nobody can be hurt. |
| Home base | `core/base` | Your private staging ground. The armory wall, the garage, the trophy shelf and the consoles. Loadouts are prepared here. |
| PvE world | Frostline (partly) | Exploration, quests, dungeons and bosses. Learn the game, test builds, earn basic gear and materials. Gentle death. |
| PvP world | Ashfront | The high-stakes warzone. Full loot, the only source of heavy weapons and the best loot, bank spots, sign-out tension. |
| Gladiator arena | The Pit (`core/arena`) | Duels, bouts and tournaments. Loadouts are locked once a fight begins. Nobody loses gear. |

### Main hub

- A safe zone: weapons locked, nobody can be hurt (`WorldDef.safe_zone`).
- A place to be seen: other players' gear, rigs, outfits and watch skins
  are on show, with tags you read by looking at someone.
- Vehicles are limited to harmless fun so the hub does not clutter: a toy
  bike can be thrown down to ride, but nothing in the hub can damage or
  block anyone, and parked vehicles pack themselves away after a short time.
- Loadouts can be changed freely here (it is out of the fight).

### Home base

- The stash on show: guns on the armory wall, blades, armor stands, rigs,
  ability chips, bikes in the garage, loot on shelves, trophies.
- **Heavy weapons banked from the PvP world hang on the armory wall** and can
  be stacked there (see section 6).
- Consoles do what menus would: launch pad, locker, gunsmith bench, mastery
  bench, wardrobe, records, trader, uplink, arena gate.
- Loadouts can be changed freely here.

### PvE world

- Open-world exploration with quests, dungeons and boss fights, where players
  earn loot and try out builds without other players hunting them.
- Gentle death (`keep_gear_on_death`): you drop your pack, not your kit. In
  return, loot is basic gear and materials; rare gear stays in the PvP world.
- **Deferred.** Quests, dungeons and bosses are a large amount of work, so they
  wait until after the friends playtest. Until then Frostline stands in as the
  PvE world (no PvP, gentle death, basic loot).

### PvP world

- The endless warzone (see `CLAUDE.md`): armies, strongpoints, war intensity,
  events, renown and bounties.
- Full loot on death.
- The only place heavy weapons are found.
- Mid-map bank spots and sign-out create the extraction tension (section 7).

### Gladiator arena

- Tight, competitive duels and matches, with wagers and tournaments.
- You fight with your own loadout, locked once the bout starts. No healing
  items, no vehicles, no heavy weapons.
- Nobody loses gear; a beaten fighter yields.

## 3. The watch

The wrist-mounted holographic watch is the central in-action interface.
Raised with X; it comes up by itself when you go down.

| Feature | What it does |
| --- | --- |
| Vitals and loadout | Health, armor, stamina, flight heat, ammo, pack, standing, strongpoints. |
| Rig readout | One extra readout per flight rig (section 5). |
| Vehicle carousel | The permanent garage: swipe through your vehicles, take one as a toy in your hand, throw it to unpack the full-size vehicle. Packs vehicles back up. |
| Heavy weapon chamber | Holds one heavy weapon (section 6). |
| Landing choices | Where to drop back in after dying. |
| Sign-out | Starting a sign-out and its countdown (section 7). |

Watch skins are cosmetics, shown off in the hub.

### Loadout swapping rules

| Where | Swapping |
| --- | --- |
| Main hub, home base | Free. |
| PvE world | Allowed when out of combat, from the watch, drawing on your stash. (Built with the PvE world.) |
| PvP world | Locked from deployment until you sign out or die. |
| Arena | Locked once a bout begins. |

## 4. The loadout

Every player brings a modular loadout. Five slots define the combat role:

1. **Primary weapon.** Rifles, carbines, SMGs, shotguns, marksman and sniper
   rifles. Takes attachments (optic, muzzle, grip, magazine).
2. **Sidearm.** A quick-draw backup, and the gun you can fire while gliding.
3. **Melee weapon.** Close quarters, directional, parryable. Every melee
   weapon has a short **magnetic air-lunge** for mid-air duels (below).
4. **Flight rig.** The player's movement identity (section 5).
5. **Gadget** (the `ability` slot in code). A tactical tool that complements
   the rig (below).

Alongside those five: an armor frame, a helmet (visor), a vehicle on the
watch, and the heavy weapon chamber, which is filled in the field.

### Melee air-lunge

- With a melee weapon drawn in the air and an airborne enemy within about
  6 m inside the aim cone, the heavy attack becomes a lunge that pulls you
  to them and strikes.
- It keeps a full visible windup and can be blocked or parried like any
  melee attack, and costs stamina. A whiff leaves you drifting.
- On the ground the heavy is unchanged (heavy lunge, dive slam from the air
  onto someone below).
- Stats on `MeleeWeapon`, so each weapon can tune range and pull.

### Gadgets

The slot exists with three chips (Phase Step, Kinetic Barrier, Shock Pulse).
More gadgets need an agreed list before any are built. Starting ideas, each
picked to pair with a rig or to answer one:

| Idea | What it does | Pairs with |
| --- | --- | --- |
| Flare | Drops hot decoys that break a heat-seeker lock | Jetpack (it is the heat-seeker target) |
| Grapple line | Hooks a surface or wreck and swings you on it | Wings (re-gain speed without diving) |
| Smoke canister | A cloud that blocks sight but not thermal | Boots (push through streets) |
| Harpoon tether | Hooks a flier and drags them down for a few seconds | Ground fighters, anti-air |
| Sonar spike | Planted; pings movement around it once | Any, holding ground |
| Field patch | Slow heal over time for you and a squadmate nearby | Any, squads |

Every gadget is data on the one `Ability` class, with a cooldown, a visible
effect and a counter.

## 5. Flight

Follow the aerial rig proposal for the details and numbers:
"Aerial gadgets: identities and balance"
(https://claude.ai/artifact/5oqEMAXpKisXTojV9w47pv). Do not redesign it in a
feature thread; changes go through Caleb. The core of it:

- **One cruise speed.** Holding forward caps every rig at 15 m/s (a sprint is
  9.5), so a mixed squad stays together with no squad abilities. Each rig has
  a burst above cruise that costs heat or height.
- **Same 100 heat bar, different loops.** Flown its own way, a rig sustains
  for minutes. Flown against type, it burns out in seconds. Flight is
  sustained, not literally endless, so heat seekers, thermal and ground
  fighters stay relevant.
- **Overheat cuts the rig out** until heat falls back to 35.
- **Air aim penalty**, except in each rig's steady state (hovering jetpack,
  skimming boots).

| Rig | Flies at | Stays up by | Edge | Trade-off |
| --- | --- | --- | --- | --- |
| Jetpack "Skyhold" | High, 20 to 40 m | Cruise on jets, coast down to vent heat | Stops dead and hovers; steadiest gun platform; best for heavy armor and heavy weapons | Wide turns; loud, bright, heat-seeker bait |
| Glide Wings "Longreach" | Middle, 8 to 30 m, in arcs | Gliding, diving for speed, wing pulses to climb | Fastest dives, tightest turns, silent and cold | Can never stop; sidearm only while the wings are out |
| Thruster Boots "Skirmisher" | Low, under 8 m | Skimming near surfaces, where the boots cool | Instant air dashes, no aim penalty while skimming, works indoors | Climbing high burns heat fast; no high ground |

In a squad the layers become roles: the jetpack holds the high angle, the
wings flank and dive in, the boots push through streets and buildings.

Rig readouts go on the watch and on the rig itself (heat screen, wingtip
lights, boot pips), never on a screen overlay.

## 6. Heavy weapons

Heavy weapons (in code, "power" weapons: Rail Lance, Helion launcher, Arc
Mortar, Storm Cannon; the railgun, rocket launcher, grenade launcher and
minigun roles) are high-impact, limited-ammo weapons found **only in the PvP
world**.

### Carried on the watch, one per outing

- Finding a heavy weapon (at strongpoints, beside supply pods, sometimes by a
  refilled cache, more as the war heats up) **scans it into the watch's heavy
  chamber**. This replaces the swap racks: there is no rack to trade at.
- The chamber holds **one** heavy weapon. Finding another while full offers a
  swap: the old one is left where the new one was.
- **Summoning** it (key 4, or from the watch) materialises it in your hands.
  Your primary is not dropped or deleted; it is put away.
- When its ammo is spent it dissolves and your previous weapon comes back by
  itself. Putting it away early returns it to the chamber with the shots it
  has left.
- One per outing is the anti-spam rule: nobody can carry several heavy
  weapons into one fight.

### Banking and the armory wall

- A heavy weapon in the chamber is banked by a bank spot upload or by signing
  out, and goes to the **home base armory wall**, where extras stack.
- You may deploy into the PvP world with one heavy weapon from the wall in
  the chamber. That still counts as your one per outing.
- Heavy weapons can only be used in the PvP world. The arena and the PvE
  world leave the chamber empty.
- Death drops it like the rest of your gear: it lies with your bag for
  whoever gets there first.
- Never sold in shops. Can be sold back at the trader at the usual 40%.

### Rig synergy

- Jetpack: fires steadily from a high hover (no air aim penalty).
- Glide wings: high-speed strafing runs. Wings out means sidearm only, so a
  heavy is fired by folding the wings, or from a dive's end.
- Thruster boots: dash-peek around cover.

## 7. Banking and leaving

Two complementary ways to secure loot.

### Bank spots (depots)

- Fixed, high-visibility terminals inside the map, marked by beacons.
- A short upload (3 to 5 seconds, standing in it) sends your backpack, your
  carried scrip and the **heavy weapon in your chamber** home, and you keep
  playing.
- Predictable places, so they are ambush points.

### Sign-out

- Start it from anywhere (the watch, or L). After the countdown you go home
  with everything you carry.
- **15 seconds on the ground.** Taking or dealing damage cancels it.
- **Airborne, it is louder and longer**, so a flier cannot climb out of reach
  and wait: in the air the countdown is 25 seconds, and a visible beacon
  column rises from you that everyone in the world can see, with a sound.
  Landing drops the timer back to the ground rate (time already spent counts).
- Quitting or disconnecting leaves your body standing for the sign-out time
  (30 seconds after a fight), as today.

The exact air time is a tuning value on `WorldDef`.

## 8. Vehicles and flight

Vehicles must earn their place next to sustained flight.

- **Clearly faster.** A bike's top speed on ground is well above flight
  cruise (target: at least 1.5 times cruise, so 22 m/s or more against 15),
  and its boost beats every rig's burst on open ground. Bikes cost no heat.
- **Tactical utility.** Mobile cover, mounted firepower, passenger seats for
  squadmates, heavy cargo (more pack space while riding).
- **Seamless transitions.** Throw a toy vehicle from mid-air onto the road
  below and land on it; eject upward off a speeding vehicle straight into
  flight.
- Vehicles live on the watch (section 3). The motorbike is first; more types
  are new `vehicle` items.
- Roads, trails and jump ramps on the maps give bikes routes where they beat
  flying.

## 9. Economy and progression

Unchanged from the current game (see README "Credits and shops"):

- Loot is the money; credits come from getting loot home.
- Shops sell only base-level gear; rare gear is found.
- Mastery for every gear type, sidegrade variants, never lost on death.
- Renown, ranks, bounties and the Marked in the PvP world.

## 10. Social

- The phone: people, chat, invites, news, mirror, settings.
- Clans: one side in a warzone, a tag by the name.
- Squads of three are the design target for flight pacing.

## 11. Roadmap

1. **Before the friends playtest:** the aerial rig rework (two PRs, per the
   proposal), the heavy weapon chamber and banking, the sign-out rework, and
   bike tuning against the new cruise speed.
2. **Friends playtest** on a hosted server (`docs/hosting.md`).
3. **After the playtest:** the melee air-lunge, the gadget list and the first
   new gadgets, vehicle utility (passengers, cargo, mounted guns), loadout
   swapping in the PvE world.
4. **The PvE world:** quests, dungeons and bosses.
5. **More worlds** as plug-ins.

## 12. Open decisions

Caleb's calls, still open:

- Is 15 m/s the right cruise speed? To tune by feel in the playtest.
- Should bots fly?
- The airborne sign-out: 25 seconds and a beacon column, or must you land?
- Which gadgets to build first from the list in section 4.
- Can a heavy weapon from the armory wall be taken into the PvP world, or
  only ones found there in the same outing? (This doc assumes yes, one per
  outing.)
