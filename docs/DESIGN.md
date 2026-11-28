# Verge: game design

This is the plan every thread builds against. It describes the game we are
aiming for, not only what exists today. What is built and what is still
missing is tracked in [design-gaps.md](design-gaps.md).

How to use it:

- Before building a feature, read its section here. If the code and this doc
  disagree, the code describes today and this doc describes the target.
- The rules in `CLAUDE.md` and `docs/systems/` still apply to how anything
  is built. When a feature here changes one of those rules (for example
  power weapons becoming storable), update the rule where it lives in the
  same PR that builds it.
- When Caleb makes a design call, record it here in the same PR.
- Section 13 lists the decisions still open. Do not settle them silently.

Sources: Caleb's design conversation (November 2026), the review of it in
the project chat, and the aerial rig proposal "Aerial gadgets: identities and
balance" (https://claude.ai/artifact/5oqEMAXpKisXTojV9w47pv).

## 1. The pitch

A full-loot PvPvE war game across the Verge, a ring of war-torn worlds:
you drop into an endless warzone with gear you are willing to lose, fly,
ride and fight through it, and get your loot home. Every world is hand-built by the team,
and new ones are added over time without touching the core (each is a
`WorldDef` plug-in in the code). The game is not a platform for
player-made worlds, and it is never marketed as one (Caleb's call).

Two standing rules shape every feature:

- **Immersion.** Interfaces work through the world: a console you walk up
  to, a screen on a wall, the phone, or the watch. Flat menus and
  screen-space overlays are a last resort, and Caleb is asked before one is
  built (accessibility, a critical error, or something that cannot work
  in-world).
- **Watch vs phone.** Your vitals, flight heat and ammo are always in
  view on the visor and the gear itself (section 3), so staying alive never
  needs the watch. The holographic wrist watch is for the things you choose
  to do in action: vehicles, the heavy weapon, artifacts, sign-out, banking,
  the map and pings, landing, and the pack. The phone is for settings,
  friends and players, and information.

## 2. The places

The game has five kinds of place. Each world is a `WorldDef` plug-in, so a
new planet is a new folder under `worlds/`.

| Place | Today | Role in the loop |
| --- | --- | --- |
| Main hub | The Concourse (`worlds/plaza`) | Social space. Show off cosmetics, rigs and watch skins. Doors to every world, the shops, the clan hall and the arena. Nobody can be hurt. |
| Home base | `core/base` | Your private staging ground. The armory wall, the garage, the trophy shelf and the consoles. Loadouts are prepared here. |
| PvE world | Frostline (partly) | The co-op expedition world: cold, whiteouts and tracking instead of a war. Learn the game, test builds, earn basic gear and the crafting parts every Mk2 and Mk3 needs (planned). No PvP, gentle death. |
| PvP world | Ashfront | The high-stakes warzone. The fallen drop scrip piles, not their gear (see "Scrip piles"), so the best gear comes from its caches; the only source of heavy weapons, bank spots, sign-out tension. |
| Gladiator arena | The Pit (`core/arena`) | Duels, bouts and tournaments, open or blades only. Loadouts are locked once a fight begins. Nobody loses gear. |

### Main hub

- A safe zone: weapons locked, nobody can be hurt (`WorldDef.safe_zone`).
- A place to be seen: other players' gear, rigs, outfits and watch skins
  are on show, with tags you read by looking at someone.
- Vehicles are limited to harmless fun so the hub does not clutter: a toy
  bike can be thrown down to ride, but nothing in the hub can damage or
  block anyone, and parked vehicles pack themselves away after a short time.
- Loadouts can be changed freely here (it is out of the fight).

**Hub activities**, all in-world, in this order:

1. **Spectating screens and a bounty board.** Screens around the hub show
   what is happening in the worlds: a "most wanted" board of the top
   bounties and the Marked, war levels, arena results. Start with stats
   (the plaza's heat signs already get `world_status`); live video of arena
   bouts comes later. The contract board, where you take contracts
   (section 10), stands next to it.
   *Built:* the most-wanted board stands across the big screen from the
   contract board: a red lit wall listing the biggest bounties out in the
   worlds and the Marked, by name, clan tag and world, never where they are
   (`Raid.wanted` rides in each world's `world_status`). Kade, the bounty
   broker, stands at it. Arena results and live video are still to come.
   *Built:* the big screen is the War Room, a live feed of the worlds that
   the tiers face. It turns through each world's front (the map split by
   who holds each landmark, so where two colours meet is the front line,
   with a landmark under attack pulsing), the race world's track camera
   (its AI races cut between a chase, an overhead and a trackside shot,
   with the order; exhibition laps, labelled as such, while no race runs)
   and the worlds at a glance, with big moments (a warlord or boss brought
   down, a landmark changing hands, the Colossus falling) and who the
   armies are hunting down the side and each world's news along the
   bottom. A console in front of it picks a world: its map comes up on
   the console and on the big screen for you, and you deploy from there.
2. **Ring races and time trials.** Courses of rings through the hub's
   skyline, one per rig plus a bike course. A cheap, small version of the
   racing mode (section 9) and a place for new players to practise each rig.
   Leaderboards per rig and for bikes on a screen at the start gate.
3. **Toy RC arena** (later). Fight or race with toy vehicles from the watch.
   It is really a separate little game with its own controls and balance, so
   it waits.

**Expanding the hub comes first.** The Concourse was a walled courtyard with
no room for these. It is now an open deck 480 m across with no wall
(Caleb's call: grand, open and sci-fi, not industrial), laid out in
districts round a lit beacon spire, each a place with one job and its name
on the building that holds it (Caleb's call, the layout pass: no signs that
do not match where they stand, no glowing pads, no floating ads):

- **Spire plaza** in the middle, where you arrive: stages, benches, Dusk.
- **Gate Terrace** to the north: an arch for each world, lit while you
  stand in it, showing a live glimpse of its world, its risk and how busy
  it is, with the full write-up on a console beside it; sealed arches tease
  the worlds to come. Marlo the dispatcher sits at a desk and reads out how
  each world is doing.
- **Market Row** to the south: a covered street of real shopfronts facing
  each other (armory, outfitter, garage, tailor, furnisher, exchange), each
  fitted out for its trade with its goods on show and a keeper behind the
  counter who greets you when you trade. Transit (leaving the server)
  stands at its far end.
- **Civic square** to the east: the clan hall with its clerk, the contract
  board with Rook, the most-wanted board with Kade, and the big screen with
  its tiers.
- **Residences** to the west: the way home, with Wren the concierge.
- **The arena** to the southeast with Sola the promoter, and the shuttered
  RC yard to the southwest, kept for the toy arena.
- **The boulevards** between them are somewhere to stop, never only a
  walk: halfway out to each district, off the lane, a stop that serves the
  people going that way. A food court on the way to the civic square (a
  noodle cart and a grill facing each other across the lane, standing
  tables), a fountain square on the way to the gates (benches round the
  water, a coffee kiosk with its tables at the water's edge), and by the
  residences a tea cart and the residents' bike bay. The diagonals are
  lined with trees and benches, with a pair of light sculptures where each
  leaves the plaza. No signs: a cart says what it is by what is on it.
- Gardens on the diagonals, slim towers with landing decks and skybridges at
  15 m (boot reach; the tops are for wings and jetpacks), rim lookouts and
  the bike loop round the edge, there to roam.

The spire to the gates is about 180 m and to the far shops about 140 m:
about 25 seconds on foot, the price of the space. It looks sci-fi, not
industrial: dark glass and metal with lit seams, a glass canopy over the
street, a tiled floor.

### Locals

The Concourse is lived in (Caleb's call): about ninety people go about their
day there, strolling the rings round the spire, window shopping down Market
Row (along the street, crossing at the doors), watching the big screen from
the tiers, standing about in small
groups and wandering out to the boards and the gates. Nothing about them is
even: who walks with whom, where they stand and how long they stay are all
rolled from one seed. They look at you as you pass and step out of your way.
They are a view only: every game makes the same crowd and moves it by the
clock, so the server spends nothing on them and everyone sees much the same
people.

Some of them you can talk to. Walk up and press the interact key, and they
answer in a short line on a card over their head, never a menu. Every
counter has someone behind it (the shop keepers, the clan hall's clerk) who
greets you as you trade. A keeper talks about what is really on the
shelves and what you really have: today's piece (the same for everyone all
day), something on sale that beats what you wear in a slot and that you can
pay for, and what your salvage would fetch. Every cart on the boulevards
has a cook, and its customers queue, order, eat at the tables and walk on,
taking turns so nobody stands in anyone's place. There are Marlo at the gates, Wren at the
residences and Sola at the arena, besides:

- **Kade**, the bounty broker at the most-wanted board: how bounties work
  and who is worth most right now.
- **Dusk**, in the spire plaza, who hears things: rumours made from the worlds'
  real news (the war, the event running, a big bounty), never more than the
  plaza's own signs know.
- **Rook**, the fixer at the contract board: one small favour a day, a contract job
  of his own (`Contracts.favor_for`) paid a little under a daily. Talk to him
  again to take it; it is held and paid like any contract.

### Home base

- **A hub with rooms off it, laid out by the player** (Caleb's call, the
  modular base). The hub is a plain steel hall with six doorways of one
  size: two in each side wall and two in the back wall either side of a
  corridor that runs back to the firing range and flight course. Six rooms
  stand in them, one each: the **Armory** (every weapon on one rack: long
  guns, sidearms, melee, and the heavy weapon wall), the **Workshop**
  (gunsmith bench and fabricator), the **Garage** (your vehicles), **Ops**
  (the wardrobe, a standing mirror; records, mastery bench, trader), the **Gear hall** (armor
  stands, helmets, rigs, chips) and the **Stores** (supplies and trophies).
  A plate over each doorway names its room; there are no other signs.
- **The lounge**, a seventh room, is somewhere to sit between lives: warm
  planks, a slatted ceiling and lamps instead of steel, and a window out
  over a dusk ridge with fires on it (one painted view, never a world).
  Its doorway is the seventh: in the front wall left of the door in the
  hall and the courtyard, and off the corridor to the range in the spine
  and the ring (their hub walls are full). Like any room it can be moved
  on the plan table. It starts small (a sofa and a lamp before a sealed
  wall) and the Lounge upgrade opens the whole room and its window. Three
  styles: the **Den** (free: two sofas round a rug and a low table, a
  floor lamp and plants), the **Bar** (a counter with stools and lit
  shelves, and a booth under the window) and the **Quarters** (a curtained
  bunk, a desk and a small sofa). It holds no gear and changes nothing in
  a fight; sitting, a radio and trophies on its walls come later.
- **Designs** (Caleb's call): beyond moving rooms, the hub itself comes in
  four shapes, each with the same seven doorways: the **Hall** (the square
  hall above, free), the **Ring** (an eight-sided rotunda, every room
  opening onto the table), the **Spine** (a long gallery, three rooms down
  each side) and the **Courtyard** (a big court under a skylight, with
  planters). Each room has three styles that lay out what it holds
  differently: the armory's wall rack, vault (an island rack) or gallery
  (long guns in lit cases); the workshop's back bench, island or pit; the
  garage's bays, showroom (a turntable) or lift rack; ops' consoles, war
  table or bridge; the gear hall's stands, ring (round a dais) or lockers;
  the stores' shelves, plinths or cargo. The first of each is free; any
  other is bought once with scrip at the plan table and is then free to
  switch to and back. The hub and every room also wear a **finish**, the
  material of their floors, walls, ceilings and trim, each picked on its
  own: **Steel** (free), **Gunmetal** (dark blued steel, cold light),
  **Ceramic** (clean white lab panels), **Brass** (bronzed steel with brass
  trim) and **Blackout** (matte black with lit strips). A finish is bought
  once and then goes on any room. Designs change how the base looks, never
  what it holds.
- **The plan table** stands in the middle of the hub: a round table with
  the base in miniature over it as a hologram and a screen on a lectern at
  its near edge. Walk up and use it and the view moves in over the screen,
  the hologram beyond it: four tabs, **Layout** (the four shapes with
  their floor plans), **Rooms** (the hub's plan: click a doorway, then the
  room to stand there; the room that stood there takes its old place) and
  **Styles** (each room's three styles, sketched from above) and
  **Finishes** (the hub and each room with the finish it wears, every
  finish as a swatch, and a button to put one on every room at once). Whatever the
  mouse points at shows on the hologram at once; a click picks it, and a
  locked one shows its price and asks once more to confirm before it is
  bought and put in use. Moving rooms is free and moves nothing in or out
  of the stash; everything on show goes with its room. The plan is kept on
  the account beside the upgrades, and a visited base stands as its owner
  laid it out.
- **Heavy weapons banked from the PvP world hang on the armory wall** and can
  be stacked there (see section 6).
- Consoles do what menus would: locker, gunsmith bench (crafting from
  blueprints, section 10), mastery bench, wardrobe, records, trader. Going
  online (host, join by address, leave) is the phone's Servers app, not a
  console.
- **No launch pad, gate screens or portal frames** (Caleb's call: they
  cluttered the room). You leave for a world through a squad portal opened
  from the watch (section 3, Mission tab).
- The gunsmith bench holds one gun at a time. Walk up and use it and the view
  moves in to the bench: the mouse wheel turns through the guns you own, a
  click picks one, then the wheel moves between its attachment slots and
  turns through what you own for each, every change shown on the gun on the
  bench before you pick it. A card on the bench behind the gun lists the
  slots and what the attachments change. Attachments are not hung on show.
- Loadouts can be changed freely here, and only here: the base is where you
  suit up. Whatever you equip goes straight on you (Caleb's call: no
  suit-up step), and you come home still wearing it. A mirror hangs on the
  wall in the deploy area.
- You are one player everywhere you go: the loadout you leave the base with
  is what you wear in the hub, a world and the arena, and coming back to the
  hub through a door puts you in front of that door.
- The firing range and the flight course are always down the corridor
  behind the hub, never moved by the plan.

**The base grows with you.** A new player starts in a starter bunker with
everything it takes to play (deploy, change loadout, trade, mastery picks,
fit attachments, go online) and little on show. Every room stands from the
start in its small form, its front half closed off by a sealed wall: a
short weapon rack in the armory (4 long guns, 2 sidearms, 2 melee), one
garage bay, one armor stand and one rig stand, a small supplies shelf, the
whole workshop, and in Ops the mastery bench and records sharing the
trader's console beside the wardrobe's mirror. A room's upgrade opens the rest of
it, wherever it stands (Armory alcove, Full garage, Ops consoles, Gear
hall, Trophy hall for the stores). Each
upgrade is a one-off scrip purchase kept on the account (never in the stash,
never lost), bought in the room at the sealed bulkhead it opens: look at it
and press F twice. Upgrades never add combat power or storage, only room to
show gear, convenience, places to practise and places to show off; gear
that does not fit on show is still owned and equippable at the locker.
Scrip is the only currency. Visiting a base shows the upgrades its owner
has. Prices are placeholders until a playtest measures scrip per life.

| Track | Upgrade | Scrip | Needs | Adds |
| --- | --- | --- | --- | --- |
| Armory | Armory alcove | 1,200 | | The full rack: 12 long guns, 8 sidearms, 6 melee |
| Armory | Heavy weapon wall | 4,000 | Armory alcove | Banked heavy weapons hang above the long guns (section 6) |
| Garage | Second bay | 600 | | 2 vehicles on show |
| Garage | Full garage | 2,000 | Second bay | 4 bays and a lift that turns the first bike |
| Gunsmith | Workshop bench | 3,000 | Armory alcove | A bigger bench: a parts cabinet and a second lamp (looks only) |
| Gunsmith | Master bench | 8,000 | Workshop bench | Looks only |
| Halls | Gear hall | 1,000 | | 6 armor stands, 4 rig stands, the chip case |
| Halls | Trophy hall | 1,500 | | The trophy shelf and a full supplies shelf |
| Halls | Lounge | 800 | | The whole lounge: more to sit on, warm lamps and the window out |
| Headquarters | Ops consoles | 500 | | The mastery bench and records get their own consoles |
| Headquarters | Firing range | 2,500 | | The range below |
| Headquarters | Finish | 1,500 | Any 4 upgrades | Lit trim and light columns |

Crafting tiers are not gated by the bench upgrades: any bench crafts Mk2 and
Mk3 for a small scrip fee per craft (section 10). The crafting console, the
fabricator, stands beside the bench in the workshop.

The bigger upgrades, which turn the base from a display room into a
headquarters, in the order they are built:

1. **Firing range and flight tunnel** (first). A private test room attached
   to the base, with moving aerial target drones, where you try gear before
   risking it in PvP: every rig, your guns, and the heavy weapons on your
   armory wall with endless ammo. Nothing is spent or lost in it, and it
   gives no mastery XP (mastery pays for real use).
2. **Squad visits** (was the squad teleporter pad, now replaced by squad
   portals from the watch). Your squadmates (up to three) visit your base
   together and look over your armory wall and garage, then leave through a
   portal one of you opens. Needs online base visits where everyone is in
   the same base at once.
3. **Trophies and blueprint pedestals** (later). Beating PvE bosses and
   winning arena brackets earns miniature statues and holographic boss
   trophies to place around the base. They come with those bosses and
   brackets.

### PvE world

- Open-world exploration with quests, dungeons and boss fights, where players
  earn loot and try out builds without other players hunting them.
- Gentle death (`keep_gear_on_death`): you drop your pack, not your kit. In
  return, loot is basic gear and materials; rare gear stays in the PvP world.
- **Deferred.** Quests, dungeons and bosses are a large amount of work, so they
  wait until after the friends playtest. Until then Frostline stands in as the
  PvE world (no PvP, gentle death, basic loot).

### Frostline (Caleb's call)

Frostline is Ashfront's opposite on every axis, so each world has its own
job in the loop, not just its own palette. Ashfront is where rare gear, gear
blueprints, upgrade data and heavy weapons come from; Frostline is where the
parts that make gear better come from, so a hardcore player needs both
worlds and a casual or solo one has a steady home.

- **Co-op, no PvP (Caleb's call).** Many players dislike PvP but still want
  to meet and work with others, so Frostline is where that happens:
  everyone is on one side, and the world rewards working together (shared
  warmth, joining someone's beacon, warming up a downed stranger, following
  each other's tracks).
- **Solo works too (Caleb's call).** Everything can be done alone; company
  makes it easier, never possible. Beacons can be held alone, fights at the
  core scale to the players near them, contracts never need a group.
- **The place.** One long frozen river valley, about 600 m, climbing from
  the river mouth (where you arrive) through the Narrows and across a
  frozen lake to the glacier head, where the Stilled Engine lies half
  buried: the terraforming drum that once kept the world warm. When it
  froze, the war here stopped. The walls step up to a shelf (14 m, reached
  by ramps) and a rim (40 m, flight only), so fights are about holding the
  high side. Cold and quiet: a low sun, blue shadows, the only warm colours
  are heaters, beacons and the Engine's one teal light.
- **Threats.** Body heat as a vital, drained in the open and refilled at
  heater huts, vents and vehicle engines, hurting through `Combat.deal`
  when empty (built, step 2). Whiteouts (built, step 5) cut sight to about
  30 m and wipe tracks, and feel like a real blizzard (Caleb's call): wind
  you see and hear, snow driven sideways in gusts, drifts streaming off the
  rims, bodies leaning into it and the wind pushing flight rigs off course
  (see "Whiteouts" below). Built
  (step 6): footprints and vehicle tracks the server keeps and sends only
  nearby, and gunshots that carry twice as far. Built (step 7): thin ice in
  the lake's middle that breaks under heavy vehicles, and the Wardens as
  the Engine's defence grid, still running, with its boss at the hatch.
- **What you bring home.** New parts (Cryo Core, Glacial Alloy,
  Engine Coil) that Mk2 and Mk3 recipes need, and Frostline blueprints for
  new options only (attachments, cold-weather gear), never a higher Mk of
  existing gear (built, step 3, see below). The inside of the Engine is
  its deep-loot dungeon (step 8, see "The Engine's inside" below; its
  first two parts built), and its vault the PvE home of the artifacts. Expedition
  contracts (built, step 7c): the board keeps one Frostline daily and one
  Frostline weekly beside the general jobs (search the relay, clear the
  rim posts, break Warden patrols, bring home Cryo Cores; bring down the
  Sentinel twice, bring home Engine Coils), counted only on a sign-out from
  Frostline. Every one can be done alone, and the weeklies pay upgrade data
  and a blueprint, the war's included, the slowest route to them.
- **Getting out (built, step 4).** Sign-out only at warm beacons, held while they
  power up (still `begin_sign_out`). Depots stay for banking.

**Order of work**, one PR each: (1) the valley map, (2) the cold, (3) the
loot role and recipes, (4) warm beacons, (5) whiteouts, after the Ashfront
weather work, (6) tracks and louder gunshots, (7) thin ice, the defence
grid and expedition contracts (in three PRs: thin ice, then the grid, then
contracts), (8) the Engine's inside, in three PRs: the Drum Hall
and the Shaft (built), the Coil Galleries and the Descent (built), then the Heart (built). Every number is a placeholder for the playtest.

**Whiteouts (built, step 5).** Frostline's storms are the shared weather
(see "Weather: ash storms") with `weather_kind` "snow". They follow the
valley: most come down it from the Engine's end toward the mouth (three in
four, `WHITEOUT_DOWN`), the rest up it, a cell 240 m across that fills the
valley wall to wall at a slow walk (3.5 m/s), building over 45 s, with a
5 to 10 minute calm between. At the heart sight is cut to half for bots and
scans and the fog takes bodies by about 30 m, shots carry 40% as far, the
cold drains twice as fast and tracks are wiped. It is told as a blizzard,
not only fog: the driven snow comes in gusts (`WeatherView.gust_now`, a
flurry every few seconds on top of the cell's own push), faster, veering
across the wind and louder while one passes; spindrift streams off the
shelf and rim edges nearest you (`weather_ridges` from the map); every body
on the ground leans into the wind from the bottom of the spine with the head
ducked, buffeted in the gusts (`Locomotion._wind_pose`, the same in both
views); and gusts push flight rigs off course (`weather_gust` 8). Check by
eye: `visual_check.tscn -- <dir> --whiteout-only`. Numbers are placeholders.

**What is built.** The valley (step 1): `worlds/frostline/map.gd`, a
`Terrain` shared between copies like Ashfront's, with the zones running up
the valley (`zone_at`: river mouth, mid-valley, glacier head; no hazard
yet), two-tier walls with ramps to the shelf, six heater huts (the heaters
warm you, see below), three strongpoints held by the Wardens (Echo Post and
Vigil Post on the shelves, Drift Post at the lake's north shore), six rim
listening posts with the rooftop caches, the Stilled Engine with the relay
cache on its back and the core's caches at its hatch, and Feral dens on the
floor. Bot markers name their faction, and `equip_bot` follows them.

The cold (step 2): `Actor.body_heat` (of 100) drains out in the open by
`WorldDef.cold_at`, 0.7 a second at the river mouth, 1.0 mid-valley and
1.4 at the glacier head, half as fast again up on a rim or in the air, so
a full bar lasts about two and a half minutes at the mouth and a minute
and a quarter at the head. Warmth fills it again: the map's "warmth"
markers (a heater in every hut, six vents on the floor, the camp fire at
the river mouth and the Engine's hatch) and any running vehicle's engine,
for its riders and anyone within 4 m. Empty, the cold hurts 4 a second
through `Combat.deal`, past armor. Only the authority decides it
(`Raid._tick_cold`); the owner is sent the number and everyone sees who
shivers (`ActorCommand.STATE_CHILLED`). It shows as a body heat cell on the
visor (and a bar on the watch card without a helmet), the watch's zone
line saying "warm" in warmth, frost creeping over the visor glass, breath
fogging out of every mouth and a shivering hunch below a third of the bar.
The numbers are placeholders for the playtest.

Shelter (Caleb's call): the cold hurts only out in the open, so players
push between buildings, warm up and fight over the warm rooms. Indoors it
never hurts. A heated room (every hut) warms you anywhere inside at 5 a
second, gentler than standing at its heater, so the frost wears off over a
few seconds. Unheated ruins (four broken shacks on the shelves, a cache in
each) still chill you at a quarter of the open cold. A fire or heater
stops it completely. In a whiteout the storm's extra cold leaks in through
doorways and broken walls (half of it into an open-fronted hut, 60% into a
ruin), slowing even a heater. The visor's body heat cell says "SHELTER"
and the watch's zone line "shelter". The Engine's inside keeps its own
cold. Numbers are placeholders.

The loot role (step 3): three new parts, Cryo Core (on the floor and from
Wardens), Glacial Alloy (the rims, the glacier head and the relay) and
Engine Coil (only the relay on the Engine's back). Every Mk2 craft needs a
Cryo Core and every Mk3 two Glacial Alloy and an Engine Coil, beside the
war's parts and upgrade data, so a player who only fights in Ashfront
trades for them at the Exchange. Frostline's own blueprints (tag
"expedition", found on the rims and the relay, never handed out by
Ashfront's warlords or pods) make new options only: the Thermal Frame, a
medium frame (65 armor) whose liner keeps out 40% of the cold but glows on
thermal, and the Glacier Grip, much steadier on the move and slower to
aim. The rims and the relay also pay a trickle of upgrade data, so a
player who stays in Frostline reaches Mk2 slowly; there is no hard cap on
it yet. Numbers are placeholders.

Warm beacons (step 4): the only way out of the valley. Four masts stand on
the floor (the Mouth, Narrows, Lakeshore and Glacier beacons, one in every
zone), each a "beacon" marker with a name and a 6 m radius, a heat lamp and
a ring of light on the snow round it, and warm like a vent. With
`WorldDef.sign_out_at_beacons` a sign-out (L, the watch, or the portal
home, which opens one) is refused away from a beacon. At one it takes
`beacon_sign_out_time` (20 s) and counts only while you stand in the ring:
step out and it waits, step back and it carries on, so it is never lost to
a short dash for cover. Every other player powering the same beacon adds
`beacon_join_bonus` (half again) to the pace, up to `beacon_join_cap`
(twice), so company makes it quicker but one player can do it alone. A
fight still cancels it, and a body left by a dropped connection counts
down where it stands as anywhere. Only the authority decides it
(`Raid._beacon_rate`); the owner is sent the pace with the countdown
(`NetSession._sign_out`), so the client's numbers keep step. The watch's
zone line names the beacon you stand at. Numbers are placeholders.

Tracks and gunshots (step 6): with `WorldDef.tracks` every body on foot
leaves footprints, left and right in turn about every 0.8 m, and every
ground vehicle wheel tracks (a hoverbike and an aircraft leave none). Only
open ground takes a print: a body more than half a metre off the map's
`ground_height` (a roof, a hut floor, a ledge) leaves nothing. The
authority lays them down (`Raid._tick_tracks`, ten times a second) in a
`Tracks` store kept in 24 m cells, each capped so a trampled spot never
grows, and lets them go after `track_lifetime` (four minutes). Online a
player is sent only the new marks within 60 m of them, a few times a
second, by the last mark id sent for each cell (`NetSession._send_tracks`),
so tracks are a trail laid behind people, never a live position, and far
ones never leave the server. The snow shows them (`TrackView`, view only):
pressed-in prints and pairs of wheel lines that fade as they age, drawn
within 55 m. Whiteouts wipe them. A shot carries
`WorldDef.shot_carry` (twice) as far: bots hear it twice as far off
(`Gun.noise_reach`) and people hear it twice as far too. Numbers are
placeholders.

Thin ice (step 7, the first part): with `WorldDef.thin_ice` the ground
where `thin_ice_at` says so (Frostline: the middle of the lake, within 70%
of its radius, drawn as darker, clearer ice) bears a ground vehicle up to
`ice_holds` tonnes, its `weight` stat. People on foot, a bike (0.3 t) and
anything that hovers or flies cross freely. A heavier one strains it by its
weight over that a second while it stands or drives there: a rover (3 t)
goes through after about three and a half seconds, a mech (6 t) after under
two, so a rover can cross the middle at speed but never stop on it. The ice
cracks out loud twice on the way (at 40% and 70%), white cracks spreading
under the wheels, and strain eases off again on sound ice. When it gives
way the vehicle sinks and its riders are in the water. In Frostline the
vehicle is not lost (Caleb's call, `ice_keeps_vehicle`): the watch of
whoever threw it, else its driver's, pulls it back out as a toy, so the
price is the soaking and the walk. The hole is open water 3.5 m across,
ringed with broken plates, that takes all the body heat of anyone standing in it and sinks
anything driven into it, until it freezes over after `ice_refreeze` (two
and a half minutes). Only the authority decides it (`Raid._tick_ice`);
clients are sent the cracks and the open holes (`NetSession._ice_crack`,
`_ice_holes`) and draw them with `IceView` (view only). Numbers are
placeholders.

The defence grid (step 7, the second part): the Wardens are the Engine's
defence grid, still running. They are a linked faction
(`WorldDef.linked_factions`): a Warden hurt in a fight it survives calls
every Warden within 60 m to where the hit came from, the way a gunshot is
heard, at most every second and a half, so a drawn-out fight brings the
rest and a kill in one blow (a backstab, a headshot) calls nobody. The call
is seen and heard by everyone near (a teal ring running out from its feet
and a rising chirp; `Raid.grid_called`, online `NetSession._grid_call`).
The grid's boss is the Engine Sentinel, which stands guard at the hatch (the
map's "spawn_boss" marker, meta "boss" = "sentinel", sent to clients with
the spawn so they build the same machine). It is a Warden built three
metres tall (480 health, 40 armor) whose Grid Lance must hold a teal
tracking beam on you for 1.2 s before it fires (30 a shot), so breaking the
line is the answer, and whose back, its heat vent, takes double. It is made
for one player (Caleb's call: solo works too): each other player within 45 m
of it makes it 60% tougher (`WorldDef.boss_party_scale`, `Actor.toughness`,
counted every second by the authority), so a group finishes it quicker but
not trivially. Like Ashfront's core warlords it comes back
`boss_respawn_time` after it falls. Any Frostline warlord (the Sentinel or an
event's) carries a piece of upgrade data and, about one time in seven, one
of the war's blueprints: the first half of the slow route (section 10).
Numbers are placeholders.

**The Engine's inside (step 8, Caleb's calls; built).** The
Stilled Engine is hollow: through its hatch is Frostline's deep-loot
dungeon, worked down tier by tier to its frozen Heart. It is part of the one
running world, not an instance (Caleb's call): squads meet down there, and
like everywhere in Frostline they are allies. It is built for squads to
fight in (Caleb's ask): no way narrower than 9 m, two arena-sized rooms and
loops to flank round. A solo player can get all the way through: nothing
needs two people, warm pockets on the way down refill body heat, and the
boss is made for one and scales with company. Its tiers:

- **The Drum Hall (built).** The drum's inside, 41 m across and 76 m long,
  floored over the bed it lies on, with catwalks 8 m up both walls and a
  ramp up at each end, the stator rings' frozen vanes overhead, fallen
  vanes, crates and coolant tanks for cover, the engine bay's heater and
  two caches (one up on a catwalk). The hatch is a doorway 9 m wide and
  7.6 m high on the valley side; the Engine Sentinel still guards it
  outside.
- **The Shaft (built).** A well in the hall's east end, 22 m across and
  26 m deep: one 9 m ramp down along the back wall to a landing, a second
  back along the front wall to its foot, which runs on under the hall's
  floor. Its foot has a heater, a cache (another on the landing), and its
  east wall opens on the Coil Galleries.
- **The Coil Galleries (built).** On the Shaft's floor, under the valley:
  two long halls 14 m wide and 72 m long joined by three cross halls 12 m
  across, a loop to fight round and flank through, with crates and fallen
  coil housings for cover, and a raised walkway 4.5 m up along the north
  hall's outer wall (a ramp at each end), the galleries' high ground like
  the hall's catwalks. Off each long hall's outer wall two alcoves hold
  a pair of dead Engine Coils, glowing at their bands, with a cache in each
  (and one by the way on). Down the south hall runs a channel of frozen
  coolant: it is not slick, it is bitter (2.6 a second against the
  galleries' 1.1), so the dry walk beside it is worth keeping to. A heater
  in the middle cross hall, and seven Wardens, one up on the walkway. The
  halls are dressed as the machine's inside: ribbed walls, roof beams,
  pipes and cable trays, hung lamps, frosted coil caps and mist over the
  coolant.
- **The Descent (built).** A well 22 m across and 40 m deep at the
  galleries' east end: three 10 m ramps switch back down it from landing to
  landing to its foot, each ramp railed on its open side, the last solid
  underneath. At its foot a heater, a cache (another on the middle landing),
  cover, five Wardens and the door to the Heart, 10 m wide, its seal
  drawn back.
- **The cable lift (built).** A cage at the Descent's foot and another in
  the Drum Hall beside the Shaft. It starts dead: one player standing at
  the switch by the lower cage for four seconds powers it (two Wardens
  keep the switch, so powering it is a fight), and then it runs
  for ten minutes for every player in the world (told on the war feed).
  While it runs, whoever stands two and a half seconds in one cage is
  carried to the other: the way home after a delve, and a quick way back
  down for everyone after. Its lights show red dead, teal running.
- **The Heart (built).** A round chamber 68 m across and 34 m high past a
  short way on from the Descent's door (with a heater), the frozen core
  hung in the middle, a balcony 9 m up round the wall reached by a ramp up
  each side, four coolant pylons floor to roof round the middle, cover off
  it and the vault's round door in the far wall.
  Its keeper is the Heart Warden (Caleb's call): in its first phase it
  calls Wardens out of sockets in the walls, so a squad splits between it
  and them; below half health the core thaws and the pylons vent coolant
  purges across the floor, each flashing before it fires; its back is the
  weak spot (a squad flanks it, a solo player dashes round the pylons).
  Phase one calls a Warden every 14 s from the next of four sockets, up to
  three at once and one more for each other player there; phase two vents
  two lanes every 5.5 s, the two diagonals (an X over the middle) then the
  two rows either side, each flashing 1.6 s before it hurts whoever stands
  in it. It is 4.2 m tall, made for one player and tougher with company
  like the Sentinel, carries nothing itself, and comes back ten minutes
  after it falls (the vault closes again then). Everyone who helped (who
  hurt it, or was in the Heart when it fell) gets their own share, kept for
  them alone, from the vault (Caleb's call: nobody takes anyone's loot and nobody arrives
  too late). The vault pays the best parts, Mk3 materials and upgrade
  data, a chance at an expedition blueprint and, rarely, an artifact
  (Caleb's call: below Ashfront's rate, so the war stays the faster
  route: 5% a share). A deep warm beacon lights there once the keeper
  falls, the way out after the fight (or the lift back up). Heart cold is
  1.5 a second.

Inside is out of the weather: no storm reaches it and no trail is laid
(`WorldDef.sheltered_at`), and the cold is its own (gentler in the hall
than at the glacier head outside, colder at the Shaft's foot and the
galleries, colder again down the Descent, bitter on the coolant). Its garrison is
Wardens at the map's "spawn_guard" markers, outside the valley's armies and
back four minutes after they fall; they are on the defence grid like any
Warden. Its caches pay the "engine" table: Engine Coils most of all, then
Glacial Alloy and Cryo Cores, a little upgrade data and the expedition
blueprints. A new expedition daily: loot two caches inside the Engine.

### PvP world

- The endless warzone (see `CLAUDE.md`): armies, strongpoints, war intensity,
  events, renown and bounties.
- **The war's storm stays readable.** Intensity still closes the horizon in
  (deeper colour, a lower sun, smoke over the fighting) but it must not
  white out a fight. Depth fog does not start inside engagement range and
  is not solid there; figures and their gear keep less of that fog up close
  and take the full fog once they are far, with a faction rim in the same
  teal / pink energy glow as the guns. Shots ignore the fog so a tracer
  still shows who fired. The knobs live on `Look` (`storm_fog_begin_min`,
  `storm_fog_solid_min`, `storm_depth_amount_cap`, `storm_fog_density_cap`,
  `storm_fog_height_max`, `storm_height_density_cap`, `storm_follow`,
  `actor_fog_clear`, `actor_fog_full`, `actor_fog_min`, `actor_rim_strength`,
  `column_clear_near`, `column_clear_far`). Ashfront's own calm and war
  moods set the distances; `Look.soften_storm` enforces the floor.
- **Scale you can see (Caleb's go-ahead, concepts in `ares/ashfront-grand/`
  in the project files).** Something huge is always in view and the war goes
  on past the rim without you, all view only and timed from what every
  client already gets. Built: the far skyline is drawn dark against the sky
  with its own haze (`Look.trim("distant")`, `skyline.gdshader`, the haze
  set from the mood by `Look.skyline_haze`, so a storm still swallows it),
  fires glow behind it (`horizon_glow.gdshader`, brighter with the war,
  hidden by a storm), and the map's "view_far" meta lets the player's view
  draw that far (`PlayerController._view_far`). The distant war is heard
  (`Soundscape`, made by the map where `Look` is on): a rumble that rises
  with the war, far gunfire from the way the fighting is, each horizon
  flash's boom arriving after it by its distance, and a quiet wind; all of
  it ducks under a storm's wind; recorded clips (Sonniss, kept out of the
  public repository, `assets/sounds/README.md`) replace the made-up wind,
  rumble and booms where the files are there (`Sfx.recorded`). The giants
  (`worlds/ashfront/giants.gd`, view only, timed by the wall clock so
  everyone sees them in one place): the Colossus, a hunched four-legged walker
  near 270 m tall, its legs arching over its back, striding round 750 m out
  with a searchlight sweeping ahead and smoke off its vents, each footfall
  heard after its delay; a capital ship riding at anchor 400 m up over the
  west; and from it a wing of dropships every 75 s (more the hotter the
  war) diving over where the fighting is (`war_centre`) and away. Flak in
  the sky (`worlds/ashfront/skyfire.gd`, view only): guns past the rim
  hosing tracer up into the smoke, more of them firing the hotter the war,
  shells bursting high and leaving puffs hanging, and bursts chasing a
  dropship wing but never hitting it; a storm hides it all. Sunlight
  breaking through the smoke (`worlds/ashfront/sunshafts.gd`, view only,
  timed by the wall clock): a few great soft shafts slanting down along
  the sun, each opening where the smoke parts, standing a minute or so and
  closing again somewhere else, dimmer the hotter the war and hidden by a
  storm. The war's shared moment comes round on the same clock, once every
  25 minutes (`giants.gd`, `since_lance`): a red targeting line finds the
  Colossus, an orbital lance comes down on it out of the sky with a blinding
  flash, and it buckles and falls where it stood, its eye and searchlight
  dying; it lies burning for about nine minutes, fades into the smoke, and
  the next one walks out of it. Out in an ash storm, ash settles on the
  visor glass (`VisorHud._draw_ash`, the glass only, like frost): grains in
  clumps from the rim inward, darkest in the corners, the middle always
  clear, more the deeper in the storm, and it blows off slowly after.
- **The battle around you (Caleb's go-ahead, concepts in `ares/epic-battle/`
  in the project files).** The war should happen *to* you, as in Helldivers,
  not only behind you. Three parts, built in this order:
  shelling (below), a scenery army fighting in the mid distance, and a busy
  low sky (gunships strafing, return fire, a dropship going down burning).
  The scenery army is view only and cannot be shot (Caleb's call), so it
  costs about what one real bot does. To keep the illusion it wears the
  same soldier bodies and armor as the real bots and fights only where no
  player can go (Caleb's call, 26 Nov: an army that vanished as you walked
  up to it broke the spell), on the battle shelves past the rim; on the
  field every soldier is a real bot.
- **Shelling (Caleb's call: real, and marked before it lands).** Every so
  often, sooner the hotter the war (`Shelling.every`, over
  `WorldDef.shelling`), a salvo is called down near the fighting: a line of
  three to six shells walking across the ground past an army soldier near
  the war's centre. Each spot is marked for 4 s with a red column of light
  and a ring round where it hurts, pulsing faster as it comes, and a
  falling whistle gives the last second away. A shell hurts everyone within
  9 m with nothing between (95 at the heart, a third at the edge, through
  `Combat.deal`), roof or ground, whoever they are; nobody owns it, so it
  pays no kill, renown or bounty. Bots who see a mark run from it. Never at
  a gate outpost, a player spawn or beside someone still under drop-in
  protection. The server decides it all and tells every client where and
  when; the blast is a flash that lights the ground, a fireball throwing a
  fan of dirt and a column of smoke left drifting, heard and felt (the view
  jolts) once its sound arrives. Ashfront only for now.
- **The scenery army (Caleb's call: view only, cannot be shot, and only
  where no one can go).** Past the rim on three sides (east, west and
  north, between the skyline's set pieces) the far land climbs in three
  broad steps, 62, 79 and 97 m up, high enough to be seen over the rim
  from the field: the battle shelves (the map's `SHELVES`, `FarLand`, the
  far land's mountains kept off them). Squads of both armies fight each
  other on the shelves' flats, two to five fights at once by how hot the
  war is, each two squads of 10 to 16 facing each other along a shelf,
  placed toward the war's centre (`worlds/ashfront/battle.gd`, the map's
  `make_battle`). They run up in hops, kneel or stand to fire (orange
  Legion and cyan Tide tracers and muzzle flashes, heard as far gunfire
  once the sound arrives), fall, lie a while and fade, and fresh ones come
  up from behind. They are the armies' own riflemen: once per run of the
  game a dressed soldier of each army is posed in a world of its own (a
  run cycle, aiming, kneeling, fallen) and each pose is baked into a far
  copy of under 900 triangles, drawn one MultiMesh per pose; out there
  each is grown to stay a few pixels tall and darkens to a silhouette
  against the lit land, and its tracers stay a pixel or two thick
  (`extras.gdshader`, `tracer_streak.gdshader`). The shelves are past the
  map's edge walls, so no player ever reaches one; `keep_off` (48 m) still
  dissolves an extra a flier gets near, as a last guard. Behind the fights
  the shelves are crowded with the horde (`worlds/ashfront/horde.gd`): 2,400
  far figures of both armies massed toward a line on each flat, surging
  and firing in their army's colour with now and then a shell's blast,
  all of it worked out on the graphics card (`horde.gdshader`,
  `horde_fire.gdshader`), two draws and nothing a frame on the processor.
  A smoke column stands over each shelf. A round from the player's own gun
  through an extra, or a shell landing by it, drops it, on that screen only
  and for nothing. View only: no collision, no `Combat.deal`, nothing sent
  online, none on a server. An ash storm hides all of it.
- **Far battle scenery follows the graphics setting.** The phone's "Far
  battle scenery" row (`GameSettings.WAR_SCENERY`, `war_share`: Full,
  Thinned 60%, Light 35%) thins the scenery army's fights and squads, the
  horde, the flak batteries and bursts, the low sky's runs and the flares;
  High and Medium keep Full, Low (laptops) picks Thinned and Lowest picks
  Light. All of it keeps happening, only less at once.
- **The ruined city has life in it.** The skyline's city blocks
  (`Look.trim("distant_lit")`) keep a scattering of lit windows and a few
  floors still burning, flickering, drawn in the skyline shader with no
  lights and no extra draws; the haze takes them as it takes the blocks.
- **Flares over the real fighting.** Where soldiers within 35 to 240 m of
  the camera are trading fire, now and then one sends up an illumination
  flare (`worlds/ashfront/flares.gd`): it bursts 55 to 75 m over the fight
  and swings down under its chute for about 20 s, lighting the ground in a
  flickering glare. Every 45 s in a quiet war down to every 12 s in
  all-out war, at most two up at once (each one quad and one shadowless
  light), none in a storm. View only: each screen sends up its own, from
  what it already sees (`Gun.shots_fired`).
- **The busy low sky (Caleb's call: view only).** Under the flak past the
  rim, the war is overhead too (`worlds/ashfront/lowsky.gd`, the map's
  `make_low_sky`). A gunship runs in 60 to 95 m up over one of the scenery
  army's fights and rakes it with its chin gun in its army's colour,
  dropping extras where its rounds land, while the fight's tracer comes
  back up at it in the other army's colour, always missing; it flies on
  and away. Fighters streak over in pairs, 120 to 200 m up, passing near
  the war's centre with a roar that swells and tears away. Now and then a
  dropship is hit over the field and falls burning, trailing smoke, to
  crash past the rim, where it lies burning a while. A run every 75 s in
  a quiet war down to every 16 s in all-out war (two at once past 0.6),
  fighters every 60 s down to 12 s, a falling dropship every 4 minutes
  down to about one a minute, and none of it starts while a storm hides
  the sky. A strafe only lands as far from every player and the camera as
  a scenery fight is placed, and a wreck only comes down past the rim, so
  none of it is near anyone. View only, like the scenery army.
- Everything lost on death, but the body drops a scrip pile worth it, not
  the gear itself (section 10, "Scrip piles").
- The only place heavy weapons are found.
- Mid-map bank spots and sign-out create the extraction tension (section 7).

### Weather: ash storms (Caleb's call)

Ashfront has storms of ash that cross the map, one at a time, so the war
has a rhythm you can read and play: you see a storm coming, and you choose
to fight in it, wait it out or use it. The same system gives Frostline its
whiteouts (Frostline step 5), and any later world can turn it on. Concept
shots: `ares/ash-storms/concept/` in the project files.

- **A storm is a moving cell.** It is about 300 m across (`WorldDef.weather_radius`). It
  comes in from the rim on the wind side, crosses the field at walking pace
  and leaves on the far side, building up over its first 40 s and dying
  away over its last 40 s. A quiet spell of 6 to 12 minutes comes between
  storms. Its edge is soft, about the outer 40% of its radius, so you can
  walk out of the thick of it. From outside it is a towering wall of
  dust, seen across the map, so nobody is caught by surprise.
- **Sight (Caleb's pick: 70 m gone).** At the heart of a storm a body
  is a shape at 30 m, faint at 45 m and gone by 70 m. Close fights stay
  readable: bodies keep less of the fog up close, as in the war's storm.
  Outside storms, the war's haze keeps its floor.
- **Spotting and scans.** Bots see half as far in the thick of it
  (`WorldDef.weather_sight`, measured where the bot and its target stand,
  the worse of the two). A visor's scan pulse also reaches half as far for
  anyone inside a storm. Thermal sees through ash (it already ignores
  fog), which gives the Ember its storm job. Thermal still never sees
  through walls.
- **Sound.** Shots carry less inside a storm (`weather_carry`, 60%): bots
  and people hear them nearer. The wind howls around you while you are in
  it.
- **Rough flying.** Gusts push anyone flying a rig, along the wind and
  across it, rising and falling as you move through the storm. Wings get it
  worst (`gust_mult` 1), the jetpack less (0.6) and boots barely (0.25).
  A gust is an acceleration, never a jolt: it stays inside the feel rule.
  It depends only on where you are in the storm, so it predicts online.
- **Cover for a push.** While a storm covers a strongpoint the armies go
  for it (`weather_pushes`): a faction picks a storm-covered site it does
  not hold over a nearer clear one, unless the clear one is much nearer.
- **Told in the world, never on the screen.** The wall is seen, and the
  wind is heard. Every working helmet's heading tape marks the storm's
  centre (`VisorHud.compass_marks`, kind "storm"). The watch map draws the
  cell as a ring, and the zone line adds "ash storm" while you are in it.
  The plaza's heat signs say when a world has a storm on.
- **Authority.** Only the server runs the weather (`Raid.weather`, a
  `Weather`). Clients are sent the cell (where it is, how it moves, how big
  and how strong it is) a few times a second (`NetSession._weather`), and
  they move it on between updates. What it looks like is `WeatherView`
  (view only): the wall, the driven ash around the camera and the fog,
  which deepens with how far into the storm the camera is. Both views are
  the same. The wall is a billowing front, not a shape: a steep dome of
  churning ash or snow with no hard outline or top rim anywhere, heaped
  with rolling billows that break the skyline, soft where it meets the
  ground, and thinning as you walk up to it while the storm's own haze
  closes in, so going in only ever thickens.
- **Per world.** A world turns storms on with `WorldDef.weather_kind`
  ("ash", "snow"), names them (`weather_name`) and tunes them with
  `weather_*` (gap, radius, speed, sight, carry, gust, cold). It picks their
  path with `weather_path`. Frostline adds `weather_cold` (body heat
  drains faster in a whiteout) and `weather_wipes_tracks`. The map hands
  `Look.atmosphere` a storm mood beside its war mood, and `Look` dresses
  the storm from its kit of that kind. Every number is a placeholder for
  the playtest.
- **Checks.** By eye: `visual_check.tscn -- <dir> --weather-only`. Its
  cost: the frame bench's `--storm` puts the player in the thick of one.

### Risk zones (Caleb's call)

The PvP world is split into rings of risk, so every outing is a choice of
how far in to go. The best rewards are only in the middle, which pulls
players into each other.

| Zone | Enemies | Loot | Ways out |
| --- | --- | --- | --- |
| Outer ring | Basic soldiers, few heavies | Common: mostly materials, now and then a piece of gear | Many: the gate outposts, sign-out anywhere |
| Middle | Tougher patrols, the landmarks' garrisons, warlords | Better crates (today's cache table) and rooftops | Depots at each landmark |
| Core hotspots (a volcano, a storm core) | A boss on guard, the armies fighting over it | Top tier: the rooftop table on the ground, blueprints, artifacts from the boss | Few: one depot, and the ground drains you while you wait |

- **Hazards drain you over time** in a core, so the best loot is on a
  timer. They are seen in the world, never shown as an overlay: molten
  slag, glow, smoke and a scorched line where the core begins.
- **The watch's map** names the zone you are in (and says when you are
  burning), on the Status page.
- **Gate outposts** stand on the edge of the world. They are small safe
  zones where you arrive, regroup with your squad, and bank or sign out at
  a depot (a gate sign-out is quick). Weapons are locked inside and nobody
  can be hurt there. Two rules keep them honest:
  - **No camping at the gates.** The safe bubble ends at the gate wall.
    Walking out gives a brief protection that ends the moment you fire.
  - **No hiding mid-fight.** The gate turns you away while you are in a
    fight or carrying a bounty.

**What is built (MVP, Ashfront).** The zones are rings around the middle
(`WorldDef.zone_at`, `hazard_at`): the Foundry is the core, molten and
burning (2 damage a second, past armor, through `Combat.deal`) and held
by a warlord who comes back 6 minutes after he dies (`spawn_boss`
markers); the middle reaches past the four landmarks; the rest is the
outer ring. Caches pay by zone (`cache_outer`, `cache`, `cache_core`), and
soldiers arriving further in are more often heavies and tougher. Four gate
outposts on the rim (`outpost` markers, run by `Raid._tick_outposts`) are
where players drop in, each with a depot. In the middle ring, south of the
Forge, stands the Works: a ruined factory district built for close quarters
(one street of halls and open sheds pointing at the Forge, a cross street,
catwalks and gantries 6 m up, roofs left to flight rigs, so a jetpack or
boots do well there and wings do not). Still to come: more hotspots (a
volcano, a storm core), a drawn map on the watch with the rings on it,
squad regrouping at the gates, and tuning.

### Rival raiders (Caleb's call)

Caleb mostly plays solo, so the warzone has to feel full of people even
when he is the only one there. Rival raiders are bots that play the way a
player does, so full loot, bounties and the war feed mean something solo
and the field never feels like it is only soldiers.

- **They come in like players.** Each drops in at a player spawn (the
  gate outposts in Ashfront) with a real kit: a primary, a sidearm, a
  blade, a flight rig, a frame and often a helmet, all base level. They
  look like people, not soldiers, and go by a name nobody else in the
  world is using.
- **They want the loot.** A raider goes from cache to cache and loots each
  one the way a player does.
- **They fight everyone.** Each is a side of its own: the armies, the
  players and the other raiders are all fair game.
- **They fly.** A raider uses its rig: it lifts off over whatever it is
  stuck on, and a jetpack wearer takes to the air in a gunfight, hovering
  on held aim. This settles "should bots fly?" for raiders only; the armies
  stay on foot.
- **They look after their kit.** A raider aims from `raider_skill`. On
  Ashfront that sits a little under a mid kit: the real guns, the plates and
  the jetpack hop already make the duel even, and a veteran's aim on top of
  that won most of them. A raider runs a dry primary onto its sidearm and
  goes back to the primary and a fresh mag between fights; draws its blade
  once every gun is dry; and heals from its pack when hurt and clear of
  trouble.
- **They get out, or die trying.** After a few minutes, or with a full
  pack, a raider stops and signs out, and a fight starts the countdown
  over. Killed, it drops its whole kit and haul in a bag, like a player.
- **Everyone hears about them.** The war feed says when one drops in, who
  killed it, and when one gets out with its haul.

**What is built (MVP).** `WorldDef.raider_count` (4 in Ashfront, 0
elsewhere), `raider_gap`, `raider_stay`, `raider_kit` and `raider_names`;
`Raid._tick_raiders`, `spawn_raider` and `raiders`; the brain's errands,
hold, flight and kit care (`BotBrain.go_to`, `holding`, `flies`, `uses_kit`). Clients build each
raider from its kit (`spawn_bot`'s `kit`). Still to come: rooftop caches
(only ground caches today), banking at depots, renown and bounties of
their own, picking up bags, flight across the map (wings and long
jetpack trips), and a grudge against whoever killed them.

### Heavy units (Caleb's call)

Ashfront is a war of machines, but most fights stay against people. The
armies' spider walkers are gone; two original heavy units take their place,
both in the game's own low-poly style, neither a copy of any film's machine.

- **Exo Trooper.** An ordinary soldier strapped into a mechanical
  exoskeleton, not an enhanced super-soldier (Caleb's call): the person is
  normal size and the suit gives the bulk, a gunmetal frame down the
  outside of each limb with drums at the hips, knees, shoulders and
  elbows, actuator housings and rams, armored boots, a spine and shoulder
  yoke with a roll cage over the head, and a power pack. The shoulder
  guards, cage bar and the slit of the closed helmet carry the army's
  colour, so it reads apart from a soldier at 50 m in a storm. Armor
  45-70 by ring, more health, a little slower, a support rifle and no
  blade. One in eight carries a spare Trooper or Bulwark frame.
- **Kiln Walker.** A rare 3 m war machine on two legs, a body of its own
  built in code: a low, wide armored hull carried level on two heavy
  reverse-jointed legs with broad splayed feet, the cannon built into its
  glacis, the heat vent let into its rear armor, gunmetal with the army's
  paint on its hip sponsons, thighs and gun mantlet, and a sensor slit lit
  in the army's colour. Slow on its feet and slow to turn (its aim comes round at 70
  degrees a second, a soldier's at 200), but its hitscan cannon leads
  fliers well. Its tell is a thin tracking beam: the cannon fires only
  after the beam has held a target in sight for a second, so a flier who
  sees it can break the line. Its heat vent glows the Foundry's molten
  orange on its back, and hits from behind or from steeply above do double.
  Beaten by circling it, going over the top, or two players. Middle ring
  and core only, at most one at each landmark (`WorldDef.bot_allowed`),
  never a warlord. It drops power cells and alloy, and a core walker has
  a 15% chance of upgrade data.

Spawn mix by ring (outer, middle, core): exo troopers 9%, 18%, 22%;
walkers 0%, 4%, 8%; the rest the armies' people, soldiers and blade heavies
as before. A client builds the same kind from the bot's seed.

### Enemy balance (targets proposed, for Caleb to confirm)

Every enemy type has a role, and a target for how often a player in a mid
kit wins a straight duel with it. The duel bench measures it
(`tests/duel_bench.tscn`): a reference player (a bot with a carbine, a
sidearm, a knife, a medium frame and a medkit, aiming at 0.5) fights each
type many times on open ground and the bench prints the win rate, time to
kill and health left beside the target. Tune the world's numbers (health,
damage, aim skill) until each type sits in its band, then check by playing.

| Enemy | Role | Reference player wins |
| --- | --- | --- |
| Outer soldier | Fodder: teaches the basics | 85-97% |
| Core soldier | Pressure, deadly in numbers | 65-85% |
| Outer heavy | Parry practice | 75-95% |
| Core heavy | Punishes panic | 55-80% |
| Rival raider | An equal | 40-60% |
| Warlord | A squad fight | 10-35% |
| Outer exo trooper | The tougher soldier | 70-90% |
| Core exo trooper | Armor that needs a plan | 45-70% |
| Middle walker | A fight for two players | 15-40% |
| Core walker | A fight for two players | 10-30% |

A bot at 0.5 is not a person: a good player aims better, uses cover and
parries on purpose. The reference skill should be set so the bench agrees
with how fights feel in play, and the bands moved only on Caleb's call.
Duels simulate every tick, the same as a fight a player is standing in.

**First measurement (40 duels each, 12 m and 25 m).** Every army type
lost every duel (soldiers in 7-10 s, heavies in 4-6 s, the reference
keeping about 90% health); warlords lost about 90%; raiders won about 70%.
Time to kill was long all round.

The army rifle was the cause for the soldiers and the warlord. It dealt 6
damage into 85 armor, so a connect took about 2 health, and a soldier died
having landed one or two shots. A warlord was that same rifle with triple
health, so the carbine still finished first. Both
sides also hipfired while strafing, and the aim wandered by more than a body
is wide at rifle range, which is why a handful of carbine hits took 7-10 s.
Heavies died on the way in, before the slow swings could land. Raiders stacked
a higher aim roll, a real kit and a jetpack hop, so they won most duels
against an equal gun.

The pass does not inflate anyone into a different creature. Gun bots aim
down sights while they are on the ground, and settled aim is a little
tighter, so skill still decides who hits and fodder dies in about 5 s.
Army rifles hit at 28, hard enough to matter through plates, with health and
aim skill rising toward the core. Heavies have the health to arrive and a
swing that nearly drops a mid kit in two hits. Raiders aim a little under the
reference. A warlord carries a kept gun or a cleaver, 280 health and 48
armor, not a worn rifle with a health multiplier.

**After the pass (40 duels, seed 1, 12 m and 25 m).** Reference-player win
rate, time to kill on a win, and health left. Every row is inside its band.

| Enemy | 12 m | 25 m | Health left |
| --- | --- | --- | --- |
| Outer soldier | 90% in 5.2 s | 88% in 5.8 s | 74-76% |
| Core soldier | 75% in 5.1 s | 68% in 5.7 s | 64-72% |
| Outer heavy | 85% in 4.9 s | 80% in 5.4 s | 36-58% |
| Core heavy | 70% in 5.2 s | 72% in 6.6 s | 28-44% |
| Rival raider | 52% in 10.2 s | 50% in 14.3 s | 63-66% |
| Warlord | 20% in 5.8 s | 32% in 7.1 s | 32-36% |

**Heavy units (120 duels, seed 7, 12 m and 25 m).** A solo reference
player stands in front of a walker and trades shots, so these rows are the
worst case: circling it or hitting the vent from behind does better.

| Enemy | 12 m | 25 m | Health left |
| --- | --- | --- | --- |
| Outer exo trooper | 82% in 6.2 s | 74% in 8.5 s | 58-61% |
| Core exo trooper | 57% in 6.6 s | 51% in 8.1 s | 54-58% |
| Middle walker | 28% in 8.1 s | 32% in 10.0 s | 56-59% |
| Core walker | 15% in 6.8 s | 13% in 9.1 s | 45-65% |

At 40 duels these rows swing by about ten points either way, so they were
tuned at 120.

Raider fights run longer than the others because both sides wear plates and
stop to use a medkit. A warlord's loss, when the player does win, takes
about 6-7 s and leaves the player around a third health.

**Outer ring retune (19 Nov, 60 duels on each of seeds 1 to 3).** The
first enemies a new player meets had drifted to the hard edge: the outer
heavy won 30% at 12 m (the reference 70%, under its band), and the outer
soldier averaged 84% at 25 m, just under. The outer heavy now has 225
health (was 250) and the outer soldier 115 (was 125); middle and core are
unchanged. Spread, aim skill and range falloff were tried first and barely
moved the 25 m number, since the reference's own misses at that range
decide it.

| Enemy | 12 m before | 12 m after | 25 m before | 25 m after |
| --- | --- | --- | --- | --- |
| Outer soldier | 93% | 95% | 84% | 86% |
| Outer heavy | 70% (seed 1) | 81% | 83% (seed 1) | 87% |

**The other worlds, first measurement (25 Nov, 30 duels a row, seed 1).**
The duel bench now covers the Spore Marsh, the Dune Sea, the Basalt Rift
(which fields the Dune Sea's roster, so it shares its rows) and Frostline's
two bosses: `--world marsh|dunes|rift`. A boss row is built as its
"spawn_boss" marker builds it. The bands are proposed (for Caleb to
confirm), by role as on Ashfront: fodder 85-100%, standard 65-85%, tough
55-80%, a hive guard 35-65%, a boss 5-35%. Nothing is tuned yet.

| Enemy | 12 m | 25 m | Band | Verdict |
| --- | --- | --- | --- | --- |
| Marsh stalker | 97% | 100% | 85-100% | ok |
| Bloater | 100% | 100% | 85-100% | ok |
| Broodling | 100% | 87% | 95-100% | edge |
| Lurker | 100% | 100% | 65-85% | too easy (the bench starts it standing, not lying low) |
| Shellback | 93% | 90% | 55-80% | too easy |
| Brood keeper | 43% | 50% | 35-65% | ok |
| Grey Matriarch | 7% | 17% | 10-35% | edge |
| Rootmother | 20% | 27% | 10-35% | ok |
| Shellback Elder | 37% | 30% | 5-30% | edge |
| Drowned Lurker | 17% | 40% | 5-30% | edge |
| Dune/Rift grunt, outer | 100% | 100% | 85-97% | too easy |
| Dune/Rift grunt, core | 100% | 100% | 65-85% | too easy (11 a hit, the pre-pass army number) |
| Dune/Rift marksman | 97-100% | 90-100% | 75-100% | ok |
| Dune/Rift brute, outer | 83% | 93% | 75-95% | ok |
| Dune/Rift brute, core | 43% | 27% | 55-80% | too hard |
| Wreck Baron / Lord of the Crown | 3-7% | 10% | 10-35% | too hard |
| Engine Sentinel | 0% | 0% | 10-35% | too hard |
| Heart Warden | 0% | 0% | 5-30% | too hard |

Groups at 20 m (`--group 2,3,5`): Dune grunts lose every outer pair and
win 17% of outer threes and 83% of outer fives, against Ashfront's
outer pair at about a third; a Marsh stalker pack of five loses 70% of
the time, so a pack is not yet the danger it is meant to be; broodlings
win 37% of pairs and 77% of fives.

**The other worlds tuned (25 Nov, Caleb's call: tune enemies up to the
bands).** The Dune Sea and the Rift now use Ashfront's tuned numbers
for the same roles: an army rifle at 28 a hit (the Rift's zealots a
quicker carbine at 22), aim skill by ring (`BOT_SKILL`), health growing
by ring on Ashfront's soldier curve (`ZONE_TOUGH`), brutes and runners
as Ashfront's heavies and runners, and warlords at Ashfront's 280 health
and 48 armor. The Magma Crawler keeps one shell in every ring
("flat_armor") and its own health curve, since a melee beast already
sharpens a lot further in (it feints, dashes and kicks in the core). The
Lord of the Crown is never a crawler (`bot_allowed`). The duel field
drops "edge_guard" (no mesa, no navmesh), which had kept the Rift's melee
kinds from taking a step. Frostline's Engine Sentinel is 480 health (was
650) and the Heart Warden 620 health and 21 a shot (was 1400 and 24);
the Grey Matriarch 520 (was 900), the Drowned Lurker 1400 (was 1800);
the Shellback bashes for 36 (was 24) and moves a little quicker; a
Cinder Hound bites for 20, so a den of three is a fight. 30-40 duels a
row, seed 1:

| Enemy | 12 m | 25 m | Band |
| --- | --- | --- | --- |
| Dune grunt, outer / core | 93% / 67% | 83% / 77% | 85-97% / 65-85% |
| Dune marksman, outer / core | 100% / 90% | 100% / 87% | 85-100% / 75-100% |
| Dune brute, outer / core | 77% / 83% | 83% / 50% | 75-95% / 55-80% |
| Salvage Runner, outer / core | 77% / 80% | 100% / 63% | 85-97% / 65-85% |
| Wreck Baron | 40% | 17% | 10-35% |
| Crown Zealot, outer / core | 97% / 73% | 93% / 77% | 85-97% / 65-85% |
| Crown Sharpshooter, outer / core | 100% / 97% | 100% / 93% | 85-100% / 75-100% |
| Slag Brute, outer / core | 80% / 70% | 80% / 67% | 75-95% / 55-80% |
| Magma Crawler, outer / core | 75% / 52% | 95% / 52% | 60-85% / 50-75% |
| Cinder Hound (three: 47% / 73%) | 100% | 100% | 90-100% |
| Lord of the Crown | 27% | 20% | 10-35% |
| Engine Sentinel | 25% | 25% | 10-35% |
| Heart Warden | 20% | 15% | 5-30% |
| Grey Matriarch | 20% | 12% | 10-35% |
| Shellback | 72% | 78% | 55-80% |

At 30 duels a row swings about ten points either way, so the rows a few
points out (the runner, the outer Dune grunt at 25 m, the core brute at
25 m, the Baron at 12 m) are inside the noise, as Ashfront's runner is. A
crawler is slow, so at 25 m a player who keeps back wins nearly always:
that is its role. The ambushers (the Lurker, the Dune Burrower) cannot be
read here: the bench starts them standing in the open, so they lose every
duel; their danger is the ambush, which only play shows. Groups now read
as Ashfront's: two core grunts beat the reference 80-87% of the time,
three or five every time.

### Group fights (Caleb's call)

One soldier is a fair fight; five that all open up at once is a wall of
damage nobody can read. Group fights take turns, the way good shooters
stage them, so numbers mean pressure, not a stun-lock:

- Only so many army bots shoot (or swing) at one person at a time: one in
  the outer ring, two in the middle, three in the core (`BotBrain.RING_SLOTS`).
- A turn lasts 2.5-4 s, then passes to the next bot after a half-second
  beat, and the bot that let go rests a little before asking again.
- A bot waiting its turn keeps its gun on you but holds fire. It gets into
  cover from your eyes and crouches there; past the outer ring, with no
  cover near, it works round your flank instead.
- A bot you shoot always shoots back for two seconds, and a bot within
  7 m always fights, so nobody can stand next to one that is "waiting".
- Bots fighting other bots, and rival raiders, are never rationed: they
  play like people.
- Spotting takes longer far away (up to 1.6x at the edge of sight) and
  against a crouched body (1.3x), and quicker against someone who just
  shot you.
- Before its first shot a soldier raises its gun (halfway through its
  reaction) and barks a short radio call, heard about 45 m away, so the
  shot never comes out of nowhere.

**Measured (group bench, outer soldiers, 40 runs, 20 m).** The reference
player stands in the open and does not use cover, so these are the worst
case; a person who breaks line of sight does much better.

| Fight | Every bot shoots | Taking turns |
| --- | --- | --- |
| You against 2 | 28% win, dead in 7.4 s | 35% win, dead in 8.7 s |
| You against 3 | 0% win, dead in 5.9 s | 2% win, dead in 8.1 s |
| You against 5 | 0% win, dead in 3.8 s | 0% win, dead in 6.8 s |

Taking turns buys between one and three seconds against a group, which is the time to
reach cover, heal or leave. Targets (Caleb confirmed): an
outer pair is winnable in the open (about a third), three or more need
cover or a plan, and five should take at least six seconds to kill
someone standing still. The duel rows above stay in their bands with this
on (one attacker always has a slot).

### Enemy layout (Caleb's call: pockets in every world but Ashfront)

The aim: a player meets one readable group at a time, picks the moment to
engage, and wins when they play it well, while the frame rate stays high.
The rules proposed (the enemy gallery's plan, 25 Nov), on trial in
Frostline before any other world moves over:

- Encounter pockets. Enemies live in pockets of 1 to 5 at a named place,
  never spread evenly, far enough apart that you can't pull two at once
  (about 80 m, 100 m where a long gun stands). The ground between is quiet
  travel.
- Pockets wake near players (Caleb's call, 25 Nov). A pocket stands only
  while a player is within its wake range (past the sight of anything in
  it) and sleeps when nobody has been near for a while, so the enemy cap
  (8 today) counts only the pockets near players, and a world can hold
  far more pockets than the cap.
- Cleared stays cleared for a while: a killed enemy comes back only
  after its world's respawn time (4 minutes in Frostline), and never in a
  player's sight.

Frostline's trial (`WorldDef.pocket_wake`): no army walks the valley. Its
pockets are the three posts (2 Wardens each), three rim lookouts (1
Warden), four Feral dens (3 each, now at least 85 m from each other and
from any Warden pocket; two of the old five sat 30 and 45 m apart), the
core at the Engine's foot (2 Wardens), and the Engine's garrison by
section, which wakes at 50 m because its walls hide it. Still to decide
after the trial: whether bosses sleep too (they stand all the time today
and take 2 of Frostline's 8).

Every world but Ashfront (Caleb's call, 25 Nov: "Pockets, Ashfront keeps
its war"). Each has no army and its own enemy budget of 12
(`WorldDef.enemy_cap`, in place of the project's 8):

- **The Marsh** wakes at 90 m (a small basin, close forests): a pack in
  each forest (3 stalkers and a bloater, with the hive's keeper where
  there is one), a shellback and a bloater at each survey station, two
  stalkers before the Matriarch's den, a lone beast on six hummocks, a
  lurker in each deep pool, and each Rootway's gallery as one garrison
  under the ground. The forests and stations stand at least 74 m apart.
- **The Dune Sea** wakes at 180 m (past a marksman's 70 m, and vehicles
  are quick): three raiders at each salvage yard and two to four at each
  wreck field, the burrower in every other field among them. At least
  279 m between them.
- **The Rift** wakes at 110 m (a small world, most of it near): the cult
  holds each mesa, three on the Anvil, two on each outer stack with its
  hound pack (five, one fight). The mesas are 85 m apart; the perches
  stay empty, for events.
- **Ashfront keeps its war**: its armies roam and fight as before, under
  a budget of its own of 24, so a battle in view has both sides in it.
- Frostline keeps the project's 8 for now.

### Own rosters for the Dune Sea and the Rift (Caleb's call)

The Dune Sea and the Rift fielded the same three raiders under different
names. Caleb chose a roster of their own for each:

- **The Rift is the Crown's cult**, the Lord of the Crown's own: Crown
  Zealots (light crimson plate under Ember helms, a fast carbine, and they
  close in), Crown Sharpshooters (the long rifles, 90 m of sight) and the
  Slag Brutes. The cult keeps lava beasts:
  - **Cinder Hounds**: lean beasts under basalt plates with lava in the
    cracks, run in packs of three from a den on each outer stack. Fast and
    fragile (80 health), they feint and dart in to bite, and keep to their
    mesa.
  - **Magma Crawlers**: slow, armored shell beasts (320 health, 60 armor)
    with a soft, white-hot rear; a heavy bash from the front, and the
    ground they cross burns the other side for six seconds.
- **The Dune Sea keeps its raiders** (Sand Raiders, Dune Marksmen, Scrap
  Brutes) and adds:
  - **Salvage Runners**: light, quick raiders who come in on a flank with
    a knife while the rifles keep you down.
  - **Dune Burrowers**: ambushers under the sand in every other wreck
    field. Each lies low at its lair, feels only what comes within 9 m,
    and comes up with a lunge and a heavy bite. In a sandstorm it feels
    and follows further (up to two and a half times), where everyone
    else sees less. Burrowers and raiders leave each other be.

Their numbers are tuned to the duel bench bands ("Enemy balance", the
other worlds tuned).

### Enemy bodies (Caleb's call: no stock robots in every world)

The three stock robot models stood in every world as heavies, bosses and
Ferals. Caleb chose a mix instead:

- **People** for the armies, raiders, brutes and bosses. A heavy is a big
  fighter in full plate of its world's own: the Legion Vanguard in cobalt
  gunmetal under a Warden helm, the Tide Brute in rusted crimson scrap,
  the Dune Sea's Scrap Brute in sanded scrap, the Rift's Slag Brute in
  plate that runs hot under an Ember helm.
- **A body of its own for every boss**, never a heavy with more health:
  Ashfront's Warlord in black and gold plate with a cloak and its army's
  banner, the Wreck Baron in hazard-striped scrap with a torn cloak and an
  engine on its back, the Lord of the Crown in crimson plate under a crown
  of lava-lit basalt.
- **Beasts** for the wild: Frostline's Feral Stalker is a furred pack
  beast with a mane of ice spines and hooked ice spurs; the Rift's lava
  beasts and the Dune Sea's burrower are below ("Own rosters").
- **Machines only where the story has machines**: Frostline's Wardens, the
  Engine Sentinel and the Heart Warden are the station's automata, built
  in code as sleek androids (pale ceramic shells, lit seams and visor),
  their weapon built into the right forearm, a gun arm that comes up along
  the aim or a blade. The colossus is broader, with a reactor and a
  missile pod, and a lance for a forearm.
- **Armies are told apart by uniform, never by people.** Both of
  Ashfront's armies draw from every skin tone; the Legion wears navy and
  grey, the Tide rust and tan, and a faction's tint dresses clothes and
  gear but never skin.
- **Every plain fighter has a look of its own.** A marksman or a runner
  is not its army's rifleman: the Legion Marksman wears a hood and
  mantle and carries a long scope, the Tide Runner goes light with a
  scarf flying. The Dune Sea's raiders are desert nomads (Caleb's call):
  Sand Raiders in sand wraps, scarf masks and goggles over light scrap
  plate in desert paint, Dune Marksmen in long dusters with a hood.

How it is built is in `docs/systems/bodies-and-animation.md` ("Enemy
bodies").

### Enemy senses and squads (Caleb's call)

Playtest: "sometimes it seems like every AI converges on me like I'm the
biggest bounty on the planet." It did: every shot a player fired reached
every patrolling bot of both armies within earshot, each one left its post
and came, nothing capped how many followed one person, and bot battles made
no noise, so a player was the only thing on the map that pulled bots about.
Bots now react only to what they sense, and only a few act on it:

- **Senses.** A bot sees (shorter in a storm, `sight_between`), hears a
  person's shots (`Combat.noise`, carried further by a world's air and
  muffled by a storm), a sprint up to 16 m and a jog up to 7 m, through
  walls (walking, crouching and gliding are silent), a flight rig's jets
  (30 m) and an engine (40 m) (`BotBrain.noise_of`), feels a hit, and hears
  a squadmate's callout. A heard place is rough (off by up to a tenth of the
  distance); a hit or a callout is exact. Nothing is live tracking.
- **Only a few act.** Only the nearest three go to look at one person's
  noise (`noise_lookers`, `SquadBoard.look`); the rest turn to face it with
  the gun up for a few seconds. Only three to five army bots, by ring, may
  leave their ground to hunt one person (`RING_HUNTERS`, `SquadBoard.hunt`);
  the rest fight from where they stand. Every chase is leashed: nobody
  follows anything past 35 m beyond its patrol (`leash`).
- **An army fights the other army first.** A person at the same distance as
  an enemy soldier is the second choice (`person_bias`).
- **Search.** Losing sight is not knowing: a bot hurries to where it last
  saw you, carried on the way you were going, looks round a few points
  ahead of your course, then gives up and goes back to its ground.
- **Callouts.** A soldier who spots a person and brings its gun up (the
  bark everyone hears) tells its faction within 30 m, and its own fireteam
  within 60 m, where the person is at that moment, at most every four
  seconds. Those who may come do; the rest face that way.
- **Squad tactics.** When a person ducks into cover, the bot whose turn it
  was keeps shooting at that cover for a couple of seconds to pin them, one
  bot (only ever one, `SquadBoard.flank`, so a solo player is never boxed
  in) works round the flank, and the rest search. A soldier below a third of
  its health falls back to its post and fights only when pressed; heavies,
  exos, walkers and bosses stand their ground.
- **Smart cover.** Cover is picked by the angle the person is attacking
  from, preferring spots where the bot can stand up and see them again
  (to peek), never on top of a squadmate's (`SquadBoard.cover_free`). In
  cover a bot ducks between bursts and stands to shoot; closing in, it
  moves from cover to cover (`_advance`). It runs from a grenade or rocket
  about to burst beside it, if it notices (45% to 90% by skill).

Group fights keep taking turns (the attack slots above are unchanged).
**Measured.** A lone player firing every half second beside a site, three
seeds, 90 s: bots within 30 m fell from 8.0, 14.7 and 9.2 on average to
7.0, 6.3 and 6.8, and the most targeting them at once from 8, 13 and 10 to
4, 8 and 6 (much of what is left is the site's own garrison). Duels stay in
their bands (100 duels a row). Outer-ring groups kill as fast as before
(five take 5.8 s at 12 m and 7.0 s at 25 m); groups of core soldiers, who
now react together after a callout, kill about a second faster at 25 m,
which is still "three or more need cover or a plan". The battle bench is
7% cheaper (12.1 ms a tick against 13.0), since fewer bots run about.

### The enemy AI pass: each world fights its own way (Caleb's call)

Audit (19 Nov): the AI is smart but every world ran the same bot with
different numbers. Every kind saw 38 m whatever it was, the Legion and the
Tide were mirror images, Frostline's enemies ignored the snow, smoke hid
nobody from bots, and armies never remembered a player. Caleb approved a
plan in five steps (the plan doc, "Enemy AI pass: a plan per world"):

1. **Foundations (built).** A world gives a kind its own senses through
   metas `equip_bot` sets and `BotBrain` reads: "sight" (metres), "fov"
   (degrees), "reach" (how far it fights from) and "far_notice" (how much
   slower it notices someone at the edge of its sight), so a long eye still
   gives a scope the first shot. Smoke hides people from bots as it hides
   them from eyes: `Smoke` (`Raid.smoke`, authority only) keeps every cloud
   a player cannot see through as a column of air, and a line of sight
   through one sees nothing past it unless the two are within
   `see_through` (5 m). A shell leaves one (`Shelling.smoke_*`, timed to
   `ShellView`'s column); new smoke is one more `Smoke.add`. The battle
   bench counts stuck bots (pressing to move for five seconds and getting
   nowhere) and prints where; the duel bench measures Frostline's Wardens
   and Ferals (`WORLD_TARGETS`, bands proposed, `--world frostline`).
2. **Frostline's enemies (built).** Wardens are the machine you sneak past: long
   sight with a slow, visible sweep and a short lock before the first shot,
   lone sentries at the mouth rising to grid posts of three at the glacier
   head. Ferals hunt in packs of 3 to 5 that follow tracks, grow bolder
   against someone shivering or alone, and never enter a heater's or a
   beacon's ring. About 18 to 24 bots, packs a little bigger against a group.
3. **Ashfront's armies fight differently (built).** The Legion holds ground
   (rifles from cover at 30 to 60 m, a marksman per fireteam, more exos);
   the Tide swarms (blades and runners, closes to 10 to 25 m, pincers,
   breaks off when it loses a third). Two new kinds: the Legion marksman
   and the Tide runner. Both stay inside the existing bands.
4. **Ashfront's battles follow the ground (built).** Quiet patrols at the rim,
   fireteams meeting in the open field, standing skirmish lines along the
   front lines, sieges at the landmarks, close quarters in the Works, and
   both armies' elites at the Foundry only when the war runs hot.
5. **Players and the armies (built).** Each army keeps a grudge against each
   player for one life: damage to it raises it, time lets it fade, death
   clears it. A high grudge sends that army's hunters (inside the existing
   hunter, slot and leash limits) and names you in its callouts; the other
   army does not change. A small visor tag says when an army is after you.

**Baseline before the pass (19 Nov, 30 duels a row).** 16 of 20 Ashfront
rows in their bands, the other four on the edge (outer soldier 100% at
12 m and 83% at 25 m, outer exo 90% at 12 m, core walker 10% at 25 m). The
battle bench: 12.7 ms a tick of 16.7 with 150 bots and 32 players (12.8 with
step 1's smoke and senses). The first stuck count: 38 bot-windows in 30 s,
all in the middle ring, most at the Breach (9).

**Frostline before step 2 (40 duels, 30 for groups).** One Warden or Feral
alone is no fight: the reference won every duel, at the mouth and the
glacier head alike, with 80-98% health left. Groups are where it bites, and
unevenly: a glacier-head pack of three wins 43-60%, of five 23-33%; two or
three Wardens still lose to one player, five win 73-87% of the time after
25 s or more. So step 2 makes the single enemy matter and the grid less of
a wall of health.

**Frostline after step 2 (30 duels a row).** Everything sits in
`worlds/frostline/world.gd`'s `WARDEN_*` and `FERAL_*` tables, by zone. A
Warden sees 70 m in a 100 degree cone, notices the far edge 2.4 times
slower, holds its beam 0.5 s before it fires ("lock_time", the beam now
drawn for any gun with one), fires long bursts ("burst") and lets one of a
post shoot at a time ("slots" 1). A Feral follows fresh tracks within
26 m ("tracker", `BotBrain._sniff`: to where the mark was laid, never to
the person), counts a shivering target as nearer ("preys_on_cold") and
never targets or walks into a heater's or beacon's ring ("shuns_warmth").
Every den now holds a pack of three, and the valley 22 bots. One enemy
alone is a stray, and the reference wins 90-100% of those duels
(the bands). The danger is the group: a pack of three at the mouth wins 3%
of the time, of five 7-13%; at the glacier head two win 17-40%, three
53-67% and five 73-93%. Two Wardens at the head win 70-80% and a post of
three wins every fight in the open, so the grid is something you go round,
take apart one at a time from cover, or cross with a squad. The battle
bench on Frostline (60 bots, 16 players): 5.2 ms a tick, and 76 stuck
bot-windows against 107 before step 2, most of them up the glacier head.

**The glacier-head post softened (Caleb's pick, 19 Nov, 30 duels a row).**
A staggered lock (each Warden after the first waiting 0.2 s longer) moved
nothing: a fight lasts long enough that the post still shot together,
because a Warden that is hit fired back out of turn. Now a Warden holds its
turn even when hit ("holds_turn"; point blank still skips the queue) and
the glacier head's hit for 21 a shot, not 30. A solo player in the open
beats a post of three 17-23% of the time, two Wardens 70-83%, and one alone
every time, with health and the other zones unchanged.

**Ashfront after step 3 (30 duels a row).** Each army's way of fighting is
`DOCTRINE` in `worlds/ashfront/world.gd`, set on its bots as metas. Legion
riflemen keep 30 m off and see 48 m, one rifleman in eight to five is a
**Legion Marksman** (a 50-54 damage rifle firing single aimed rounds out
to 70 m, plain soldier health), and the Legion fields a third more exos
and fewer blades. Tide riflemen close to 10 m, two of the Tide work round
a person at once from both sides (a pincer, `SquadBoard.flank`'s cap and
`flank_side`), one more of it may hunt a person, and a fireteam that loses
a third of itself breaks off for 12 s (`BotBrain.set_team`, `ally_down`,
told by `Raid._tell_team`). The Tide fields a third more blades and its
**Tide Runner**, one rifleman in seven to four: fast (10.5 m/s), 150-175
health and a quick hooked knife that dash-strikes the last metres. A
warlord drops its army's doctrine. 23 of 28 rows sit in their bands; the
four edge rows of the baseline are still on the edge, plus a core runner
at 12 m (90%, band 65-85) and a core soldier at 12 m (87%, where a Legion
rifleman now steps back). A marksman is easy up close (83-97%) and wins
about half its duels at 50 m. The battle bench: 9.8 ms a tick, 46 stuck
bot-windows.

**Battles by ground (step 4).** Each place fights its own way, set by the
`Raid` with every round of orders and authority only: `WorldDef.ground_at`
names the ground a soldier stands on and `ground_styles` lays a style over
the soldier's own numbers (`BotBrain.set_ground`: the distance it keeps,
how many may hunt one person, how far it chases, how quick it is to
notice). On Ashfront (`GROUND_STYLES`) the rim's patrols chase little and
one fewer hunts a person; the open field is where fireteams meet, as they
did; a fifth of each army (`line_share`, never its elites) stands in the
front's trenches on its own half of the field, on the map's "line_post"
markers on each trench's fire step, a standing skirmish line that keeps
its post (8 m leash) and fights from 1.4 times its range; a team sent at a
site the other army holds with two or more near it first rings it from
22 m past its edge, on the side it came from, for 40 s (`siege_time`,
`Raid._besieging`, `_siege_spot`) before it storms it; a landmark's
defenders keep to it; the Works is close quarters (half the range, a
quicker eye); and the Foundry (`Strongpoint.hot_at`, the marker's
"hot_at", 0.5) draws no teams until the war runs hot, then only each
army's elites (`WorldDef.elite_kinds`: exos and walkers), who go there
first (`WarCommander.plan`'s `hot_weight`) and hunt one more a person.
Long marches showed bots stranded in craters and trench bottoms, pressing
at a lip they could not climb; a bot on foot that covers less than a metre
in 1.6 s now jumps and steps aside (`BotBrain._climb_out`, the keys a
player presses). The battle bench: 11.7 ms a tick against 13.2 before
the step, and 7 stuck bot-windows against 41.

**Grudges (step 5).** Ashfront's two armies each keep a grudge against each
player for one life (`WorldDef.grudge_factions`, `Raid.grudges`): a point
for each point of damage to its bots (an overkill counts as one body), 60
for a kill, fading 3 a second, cleared by death, at most 700. Over 300,
two or three kills of one army in a minute or two, that army sends its two
nearest bots within 120 m to where the player roughly is every 12 s, as if
they had heard them (`BotBrain.hunt_grudge`), so the hunter, slot and
leash limits still hold and the other army does not change. The player's
visor says "THE LEGION IS HUNTING YOU" under the heading tape while it
lasts (`VisorHud.hunted_text`, owner only, `NetSession._hunted`).

### Army commanders

Each army in a world where `bots_contest_sites` is on has a commander
(`WarCommander`, run by `Raid._tick_orders` every 8 s on the authority). It
keeps a garrison on every site its army holds, splits the rest into
fireteams of about five that stand together, and sends each team at the
objective worth most: one of its own sites being taken (2.5 times), open
ground (1.5 times), then the other army's, less for each soldier holding
it, twice as much under a storm, and a fifth as much where its soldiers are
outnumbered more than two to one, so a losing fight stops drawing teams and
they go elsewhere. No objective takes more than 60% of the teams, so the
war has more than one front. Players are never an objective: an army
fights the other army for ground and a player meets it on the way. A
fireteam is also a squad for callouts (`BotBrain.team`).

### World events

The warzone already runs one event at a time (supply pods and warlords,
`Raid.event`). Two bigger events are planned, each built so every rig and
vehicle has a job:

**Supply meteor** (first, after the friends playtest)

- A streak across the war sky, then an alert on the watch with the impact
  zone.
- The crater burns hot for 30 seconds: fliers arrive first but cannot land
  yet, and bikes and rovers catch up.
- Cracking the core is a 20 second channel that anyone can contest.
- Inside: a heavy weapon, a chance at an artifact, and a vehicle blueprint
  (unlocks a vehicle for the watch).

**Sky Leviathan** (built in the Basalt Rift: "The Basalt Rift (part two,
built: the Sky Leviathan)")

- An armoured airship that drifts across the map, with weak spots at three
  heights: engine pods low (boots and bikes), the spine at mid height (wing
  dives), and turrets on top (jetpacks and the jet).
- When damaged it drops loot along its path, so ground players can follow
  it.

### Gladiator arena

- Tight, competitive duels and matches, with wagers and tournaments.
- You fight with your own loadout, locked once the bout starts. No healing
  items, no vehicles, no heavy weapons.
- Nobody loses gear; a beaten fighter yields.
- **The Pit** is a 40 m floor sunk below tiered stands, laid out for blades,
  guns and flight alike and mirrored so neither side has an edge: a low dais
  in the middle, four tall pillars with perches, a high platform per side, a
  wall in front of each door, low barriers, and two pairs of rising barriers
  that take turns coming up during a fight. An unseen ceiling at 16 m keeps
  flight over the floor. Each fighter waits in a tunnel lit in their colour
  under the stands, and the door sinks open as the fight starts. A ring of
  screens over the middle shows the bout to every seat. Its look is its own
  warm sci-fi night (Caleb's call): dark gunmetal, amber lit edges and red
  against blue, next to the hub's cool twilight, with a holographic crowd in
  the stands and a ring of stadium floodlight towers (Caleb's call) whose
  white beams spread out over the floor to its edges, never meeting at one
  point, so the fighters stand out.
- **Rules per bout** (`Arena.RULES`): every bout and tournament is
  **open** (anything the loadout carries), **blades** (melee only: guns stay
  locked and every flight rig is off) or **blades and boots** (melee, and
  thruster boots may fly, for air lunges and dash duels). Pure footwork is
  the default blade rule (Caleb's call). Whoever asks for the bout picks:
  the challenger, the player asking for practice, the first entrant of a
  tournament. A blades bout needs a melee weapon on both fighters, and a
  gladiator brought to one carries a blade. Every other exhibition the
  house puts on is fought with blades.
- **The Blade Tournament** is a tournament under blade rules. Its champion
  takes the pot like any other and, once a week per account, the weekly
  prize: the Blade Champion trophy for the base's trophy shelf (never sold
  or traded) and a 35% chance at an artifact, the design's arena source of
  both. The week is the contract board's (Monday to Sunday, UTC). Bots
  fill an empty bracket as usual, so a solo player can win it too.

### Planet kit (proposed, Caleb to confirm)

Worlds are built on planet types. A `PlanetType`
(`core/world/planet/`) is one kind of planet as data: its sky (worked out,
not photographed: gradient, sun, moons, a ringed giant, clouds, stars), its
calm and storm light (the moods `Look.atmosphere` already takes), its
ground's shape (`PlanetTerrain`, a thread-safe height recipe a map builds
its `Terrain` from and stamps its own layout on), its ground's surface (one
material, `planet_ground.gdshader`, whose base, rock, cap and patch layers
are picked by slope, height and noise), the far horizon ring, its weather
and the rocks and growth scattered on it (`PlanetProps`, made in code, one
`MultiMesh` per variant). A world names a type and keeps its own places and
rules; two worlds on one type look like one planet. Only the ground's
shape and a type's rule defaults (cold, grip, shot carry) reach the
simulation; the rest is view only. A world stands on one with
`WorldDef.take_planet(id)` at the top of its `_init`, which names it
(`WorldDef.planet`) and gives the world the type's rule defaults (`cold`,
`shot_carry`, and the ground's grip, `planet_grip`, which a world's own
`surface_grip` falls back to); whatever the world sets after that is its
own. Six types are drafted: Ashland
(Ashfront), Glacier (Frostline), Salt Flat (Meridian), and three new ones,
Basalt Rift, Dune Sea and Spore Marsh. Check by eye with
`planet_check.tscn -- <dir> [type ids]`. Meridian stands on the Salt Flat:
its sky, light, salt pan, horizon and rocks (kept clear of the circuits),
with the pan's grip set back to full, since the race profiles are tuned on
it. Frostline stands on the Glacier: its sky and light (the whiteout is the
type's storm mood), snow, blue ice and banded rock on the valley's ground
and rocks, and the Glacier's land and peaks past the walls to the horizon
(raised at the map's edge to meet its mountains; the planet's boulders and
shards only up past the rim, out of the fight). The cold, the still air's
carry and the snow and ice grip stay Frostline's own. Ashfront stands on
the Ashland: its sky, light and ash-storm mood (the war mood is Ashfront's
own), the Ashland's burnt ground and glowing cracks on the field, and its
land and mountains past the rim to the horizon, kept low near the map so
the skyline, the giants and the burning ring stand on it; the planet's
rocks only on the rim's slope and past it, out of the fight. The Ashland's
air is ash grey and its light neutral (Caleb's look pass, after his
references: grey smoke with hot lights burning through it), so the red
lives in the sky's glow, the fires, the cracks and the tracers, and stands
out. Low battle smoke lies over its ground (`PlanetType.smoke`, drawn by
`Planet.GroundSmoke`), thicker as the war heats up and in a storm, and
switched off with the "Battle smoke" graphics setting.

### More worlds (planned, Caleb's picks)

Four kinds of play have no home yet: melee as the natural choice, fighting
things that are not soldiers, vehicles at the centre, and flight at the
centre. Three new worlds and a Pit ruleset fill them, each on a planet type
from the kit below, and each pays something no other place does. They are
built in this order, cheapest and most connected first:

1. **Blades in the Pit** (built, above): blade bouts and the weekly Blade
   Tournament, the first arena source of trophies and artifacts.
2. **Spore Marsh, the hunt.** A co-op PvE world (no PvP; player melee lives
   in the Pit, Caleb's call) where blades are the natural choice and the
   enemy is wildlife: stalker packs that circle and feint, shellbacks with
   a soft rear, bloaters that burst into spore clouds, lurkers under the
   black water and brood keepers guarding the hives. Mist and fungus
   forests keep fights short, gunshots wake the marsh while melee kills stay
   silent, and guns foul gently under sustained fire (Caleb's call): spread
   grows and a long burst can jam until a reload, a world rule that leaves
   Ashfront's guns alone. The Rootways are its dungeons, part of the one
   running world like the Engine, each worked down to a keeper. Gentle
   death (keep what you wear, drop the pack). It is the main source of
   artifacts (Caleb's call), plus trophies, melee blueprints (new options,
   never a higher Mk) and marsh cosmetics.
   Part one is built (below, "The Spore Marsh"): the world, its map, three
   of the five kinds of wildlife, fouling, spore clouds and its loot. Part
   two is built too: the lurkers, the brood keepers and their hives, and
   the forests' close air. Part three (atmosphere and scale) is built, and
   all three Rootways, under the Westwood, the Gillwood and the Rotwood
   (below, "The Spore Marsh (the Rootways)").
3. **Dune Sea, the haul.** A PvPvE world built round vehicles and cargo: a
   map several times Ashfront's width, salvage crates too big for a pack
   that ride in a vehicle's cargo space, sandstorms that bury and uncover
   wreck fields, armed AI convoys as a world event, and mounted guns.
   You keep what you wear on death; the pack and every crate in your
   vehicle drop (Caleb's call). It pays vehicle blueprints and parts,
   mounted weapons and the most scrip a trip. Built in three parts
   (Caleb's call: the haul first, then sandstorms over the wreck fields,
   then armed convoys and mounted guns); all three are built (below,
   "The Dune Sea (part one, built: the haul)", "(part two, built:
   sandstorms)" and "(part three, built: convoys and roof guns)").
4. **Basalt Rift, the sky fight.** Last, and only once there are players
   enough for three PvP worlds: a small vertical world over lava where
   flight rigs decide every fight, with updrafts, the Sky Leviathan and
   Ashfront's death rule. It pays rig upgrade data and rig cosmetics.
   Built in three parts (Caleb's call: the world and its updrafts first,
   then the Sky Leviathan, then the rig rewards); all three are built
   (below, "The Basalt Rift (part one, built: the world and updrafts)",
   "(part two, built: the Sky Leviathan)" and "(part three, built: the rig
   rewards)").

The Early Access launch is narrower (Caleb's call, 25 November 2026): the
home base, the Concourse, Ashfront and Frostline, with Ashfront capped at 24
players a copy and Frostline at 8, on official servers in one US region. It
ships what is built for those places and holds back the player market, the
rover, mech and jet, artifacts, the trophy shelf, the base lounge and squad
base visits until each has a real purpose; the hub's arena door and race
feed are shuttered. The Spore Marsh and the Pit come first after launch,
then the Dune Sea, the Basalt Rift and Meridian. The full plan is in the
pitch doc (https://claude.ai/artifact/GBtminDmWRUmERSaecvihH). When the Marsh
goes in, artifacts mostly come from it; a carried artifact still drops as
itself under Ashfront's scrip-pile rule, so they keep changing hands in
the war.

### The Spore Marsh (part one, built)

`worlds/marsh/`, on the marsh planet type. A drowned basin about 400 m
across inside low hills: players come in on the dry southern shore (the
outer zone), the drowned middle is hummocks between pools of black water
(the pools are dug under one dark sheet of water at the waterline, view
only), and the core in the north is the Grey Matriarch's forest. Five
fungus forests stand in it, each twenty to thirty giant stalks a few
metres apart under caps big enough to stand on, so sight lines close in
and a fight is short. The planet's mist lies low over everything (its
"smoke", thicker in a storm) and spores drift round the viewer.

- **The wildlife.** Three kinds, each a faction of its own, so they hunt
  each other as well as you and nobody hurts its own kind. Stalkers are
  quick, fragile pack hunters with hooked claws; a pack dens round each
  forest's heart, and they circle out of reach and feint more than an
  army's blades do (the bot's "feint_chance"). Shellbacks are slow grazers
  under a plated dome, 80 armor, with a heavy bash from the front and a
  soft rear: hits from behind do three times as much. Bloaters are slow
  sacs of spores with a weak slap. Each wears a beast's own body built in
  code on the walker's skeleton (`ActorSkin._build_creature`), with nothing
  in its hand: the claws and the bash are its own.
- **Spore clouds.** A bloater bursts where it dies (`WorldDef.death_burst`)
  into a cloud 4.5 m across that hangs eight seconds and hurts everyone in
  it but other bloaters, players and beasts alike, 9 a second past armor
  (`Raid.burst_cloud`, `_tick_clouds`, through `Combat.deal`, authority
  only; clients are told with `NetSession._cloud` and draw it). So a blade
  kill is a step back after the cut, and a shot from range is a noise.
- **Gunshots wake the marsh.** Shots carry 1.6 times as far as still air
  (`WorldDef.shot_carry`, which every bot's hearing scales by); melee kills
  stay silent, as everywhere.
- **Fouling** (Caleb's call). With `WorldDef.gun_fouling` over 0 every shot
  fouls the gun a little (`Gun.fouling`, 4% a shot here): the spread grows
  with it, up to 1.8 times, it clears on its own once the trigger rests,
  and at full the gun jams (`Gun.jammed`): it only clicks until a reload,
  which a pull on the trigger starts and which clears it all. About 25
  shots without a pause jam a gun, so bursts are fine and a full mag held
  down is not. Heavy weapons never foul (there are none here anyway), and
  every other world's guns are untouched. Bots clear their own jams.
- **The Grey Matriarch.** The core's boss, at her den in the north forest:
  a stalker 2.9 m tall, 520 health, quick for her size and feinting most of
  the time, made for one player and tougher for each other player near her
  (`boss_party_scale`). She carries what a warlord carries, an artifact
  more often than not, sometimes her trophy (the Matriarch's Fang, a
  keepsake never traded or sold) and now and then the Spore paint, a Relic
  armor paint earned nowhere else.
- **What it pays.** It is the main source of artifacts: the Matriarch
  (0.6), world events' pods (0.15), the den's cache, and now and then a
  forest's hollow (the cache among the roots at its heart) or a cap (the
  cache on its two tallest caps, reached by flight). Its own goods are
  Stalker Fangs, Shellback Chitin, Spore Sacs and Glowcaps, and its own
  blueprints, the Hookblade and the Reed Spear: melee options made from
  them, never a higher Mk. Gear in its caches stays the basic tier, as in
  every gentle world. The survey stations (a hut and a depot each) hold
  what the expeditions left behind.
- **Contracts.** Its own, tagged "marsh": hollows, caps, stalkers,
  shellbacks and Spore Sacs as dailies; the Matriarch twice and three
  Glowcaps as weeklies, which pay a blueprint like every weekly.

### The Spore Marsh (part two, built)

- **Lurkers.** Seven lie at the deepest spots of the pools, well apart and
  out of the forests (found by a fixed sweep of the map, no dice), each a
  "spawn_guard" that never leaves its pool (meta "leash", 5 m). A lurker
  lies low (the bot's "lies_low" meta: it sits crouched at its post until
  it sees someone), and the skin sinks a lying body under the water by its
  skin's "lurks" share, so all that shows is the faint glow of its lure.
  It sees only 8 m, but all round, and lunges with a dash and heavy jaws
  (30 a bite, 20 armor, 130 health). A pool is a place to cross quickly,
  or round.
- **Brood keepers and hives.** Each forest but the Matriarch's has a hive
  on dry ground near its heart, and a brood keeper (2.4 m, 520 health,
  40 armor, hooked arms) posted beside it. While the keeper lives the hive
  is sealed (`LootContainer.sealed`: it opens for nobody and says why) and
  spills broodlings, small quick biters, every 7 s while a player is near,
  up to four at a time (the guard marker's "brood" metas, run by
  `Raid._tick_brood`). Keepers and broodlings are one kind (the world's
  `KIN`), so they never fight each other. Kill the keeper and the hive
  opens; it pays the marsh's goods and now and then an artifact. The
  keeper comes back after the guard respawn time and seals it again.
- **Close air** (Caleb's call: close quarters read smoky). Under a
  forest's caps the mist shuts in to about 40 m and the light goes a deep
  blue-green dark the gills glow through; out on the water the haze is
  warm and wide (the planet's `close` mood, blended by how far under the
  caps the camera is, the map's "close_here"). The low mist drifts in
  banks someone can step out of in front of you (`PlanetType.smoke`'s
  "banks", Forward+ only, like all volumetric fog). Bots see no further
  than the mist lets a player (`WorldDef.sight_at`: 38 m deep in a
  forest), so it is fair both ways.
- **Rain storms** (Caleb's call: cover and quiet). Now and then a rain
  storm crosses the marsh, on the same weather as Ashfront's ash storms
  (`weather_kind` "rain"). In its thick sight drops to 60%, the rain
  drowns shots and footsteps to 40% of their reach (wildlife hears a
  gunshot at about 29 m instead of 72 m), and it washes the spores out
  of the air, so guns foul at 40% of the usual rate. Gusts are light.
  It is a time to move and fight: sneak past a pack, or open up without
  waking the whole marsh. Down a Rootway is out of it. It looks like long
  grey streaks falling past and a grey-green wall coming over the water,
  and sounds like a steady hiss (all view only).

### The Spore Marsh (part three, built: atmosphere and scale)

Caleb's references were for mood, scale and detail, not colour: a warm,
wide haze over open water, dark blue-green close forests, and things far
bigger than you. The marsh keeps its own palette (mauve flesh, jade glow,
olive moss, black water, ochre as the warm accent). All of it is view only
(`worlds/marsh/flora.gd`, built by the map only where `Look` is on).

- **Far giants.** Twelve shapes stand 430 to 900 m out round the basin,
  far past anything you can reach: seven elder fungi (clusters of stalks
  230 to 420 m tall under their caps) and five root arches rising out of
  the ground and plunging back in. They are drawn in the haze
  (`giant_haze.gdshader`: fading into the horizon's colour toward their
  feet and with distance, their gills faintly lit), so they loom rather
  than show. Under the caps or in a storm they are veiled away
  (`Flora.set_veil`, from the map's "close_here" and "weather_here").
  Where they stand is `Flora.giant_spots`, the same on every machine.
- **The forest floor.** Under the caps the ground is grown over:
  fiddlehead ferns, ribbed spires of stacked plates, ochre fronds that fork
  and droop at their tips, and trumpet caps whose throats glow jade. Each
  kind is one MultiMesh, scattered in clumps on dry ground inside the
  forests and clear of the stalks, from its own seed.
- **The beasts' bodies.** Every beast wears a hide of its own
  (`creature.gdshader`: mottled patches over a speckle, a paler belly, a
  wet sheen and lit freckles that breathe, more on a bloater, few on a
  shellback; `ActorSkin.CREATURE_FRECKLES`), worked out in each piece's
  own space so it stays on the body. Legs carry them: a haunch at the hip,
  a thick thigh and a calf. Stalkers flare lit gill fans behind the skull
  and carry spines down the tail; broodlings still wear shards of egg on
  their backs and have eyes too big for their heads; shellbacks grow moss
  and small lit caps on old shells and have a hooked beak; lurkers trail
  barbels from the jaw and lie on fins; a keeper's eggs glow softly under
  a skin of hide, with tendrils trailing under it; a bloater has lit spore
  vents round its crown and veins of glow down its sac.

### The Spore Marsh (the Rootways)

Caleb's call: three short Rootways, one under each of three forests, each
with its own keeper, built one at a time. They are the marsh's dungeons,
part of the one running world like the Engine, never an instance. All
three are built: the Westwood Rootway, entered from the western shore, the
gentlest zone, so it is the first a new player finds; the Gillwood
Rootway, entered from a dry hummock in the drowned middle south of the
Gillwood; and the Rotwood Rootway, entered from a hummock west of the
Rotwood on the edge of the core, its chamber under the forest. Each
keeper is harder than the last (Caleb's picks for the second and third).
Each is laid out alike; each keeper fights in its own way.

- **Down, not along.** A Rootway is cut into the ground: its mouth is an
  open cut on dry ground, a ramp 12 m wide falling 36 m between root walls
  to 10 m under the marsh, open to the sky (the ground there is a hole,
  `Terrain.holes`, and the black water is not drawn over it). At its foot
  the way runs on under the ground and the pools' beds, roofed: a throat,
  a gallery that loops round a root pillar (two ways round, so a fight
  there can be flanked), a passage that bends aside round the pillar's
  far side, so the chamber is not in sight from the gallery, and the
  keeper's round chamber, 32 m across and 8 m high. No way is narrower than 9 m (Caleb's squad
  rule), and nothing needs two people.
- **Inside.** Out of the weather (`WorldDef.sheltered_at`) and in the
  forests' close air all the way, the mist and dark at their deepest; bots
  see no further than in a forest (`sight_at`). Roots hang from the roof
  and climb the walls, glowcaps grow along the walls' feet and jade lights
  glow in the dark. The walls read as a burrow, not a corridor: thick roots
  run along them, root ribs arch over the throat and the passage, arches
  ring the gallery and buttresses and bands hold up the chamber's wall. A garrison of the marsh's beasts stands in the throat
  and the gallery (stalkers and a bloater), and the gallery holds two
  caches of the marsh's goods ("rootway").
- **The Rootmother.** The Westwood Rootway's keeper: the brood's mother, a
  brood keeper grown to 3.4 m, 1,200 health, 45 armor, slow, her hooks on
  a long windup you can parry, and the egg sacs on her back her weak spot
  (twice the damage from behind). Made for one player, she grows tougher
  with company like every boss. She has a body of her own (Look's
  "brood_mother"), not a scaled brood keeper: a swollen abdomen of lit
  eggs, six woody roots arching from her back to the ground, and a crown
  of root horns. Her fight runs on the Engine's keeper
  machinery: while she is above half health broodlings come out of four
  root sockets in her chamber's wall, a few at a time; below half the
  floor's four spore vents open, two at a time, each glowing ochre before
  it gushes (22 damage to anyone standing in it). She carries nothing.
  When she falls her vault opens a share for everyone who hurt her or
  stood in her chamber: the marsh's goods, upgrade data, often one of its
  blueprints, now and then an artifact (15%) or the Spore paint. She comes
  back after 10 minutes, her vault closed.
- **The Shellback Elder** (Caleb's pick). The Gillwood Rootway's keeper:
  the oldest grazer, a shellback grown to 3.2 m, 1,600 health and 120
  armor, its dome a battering ram, its soft rear its weak spot (2.5 times
  the damage from behind). Its fight is positioning, not adds: it calls
  nothing out of the walls. It charges: from a sprint it lowers its ram and
  runs 16 m on a 1.1 s windup at whoever it hunts, and runs its whole
  length whether they are still there or not, so a player who steps aside
  lets it run on past (one who stands is caught, 48 damage). Four snags,
  knots of old roots from floor to roof, stand in its chamber: one it
  rams holds it stuck for 4.5 seconds, its face in the roots and its soft
  rear turned to the room, and everyone in the chamber is told to get
  behind it. So the fight is to stand in front of a snag, wait for the
  charge and step aside. Below half health it charges more often (every
  3.5 s, not 6) and the floor's spore vents open as in the Rootmother's
  chamber. It has a body of its own (Look's "shellback_elder"): a ram of
  pale horn over its brow, two great horns swept forward, a ridge of
  plates down its dome, a garden of fungus on its back and moss hanging
  from its skirt. Its vault, a heap of shed plates, pays as hers does, and
  it comes back after 10 minutes.
- **The Drowned Lurker** (Caleb's pick). The Rotwood Rootway's keeper: a
  lurker grown huge in the deep, 1,800 health and 70 armor, in a chamber
  flooded with black water over five pools (one in the middle, four round
  it). Its fight is reading where it comes up: it is up and fighting for
  6 seconds, then dives, and while it is under nothing hurts it. After 2.5
  seconds it rises out of the pool nearest one of the players in its
  chamber, never the one it went down in. That pool's ring stirs and glows
  as it comes up (1.4 seconds, still unhurtable), and it goes straight
  for whoever it rose by, with a lunge on a long windup. It has no weak
  side; the window is the time it is up. Below half health it stays up
  only 4 seconds and the floor's spore vents open, the water boiling. It
  sees the whole chamber and follows anyone in it, unlike the marsh's
  lurkers, which wait at their posts. It has a body of its own (Look's
  "drowned_lurker"): a lurker's long flat body and jaw, a crown of three
  more lures over its skull, a ridge of bony plates, weed in beards,
  glowcaps grown on it like barnacles and old roots stuck through its
  back; it sinks out of sight under the floor when it dives. Its vault
  pays as the others do, and it comes back after 10 minutes.

### The Dune Sea (part one, built: the haul)

`worlds/dunes/`, on the dunes planet type. About 1.8 km of wind-built
dunes, three times Ashfront's width, walled round by the planet's rim.
Players land at the south edge inside the Dune Sea Gate, with two depots
and a row of parked vehicles, rovers mostly. Across the sand lie eight
wreck fields, buried haulers half sunk in the dunes, richer and more
crowded further north; four salvage yards (strongpoints, each with a
depot) are where a haul is banked out in the field; the Wreck Baron holds
the deep sea in the north. Its raiders (Sand Raiders, Dune Marksmen,
Salvage Runners and Scrap Brutes) pick over the wrecks and hold the
yards, and Dune Burrowers lie under the sand of every other wreck field.

- **Salvage crates** (Caleb's call: carried by hand, hauled by vehicle).
  A crate stands at each of the wreck fields' spots, too big for a pack:
  you lift it in both hands (interact), which puts your weapon away and
  slows you to a walk (60%, no sprint) and no flight rig takes the
  weight. Interact again to set it down, or, looking at a vehicle, to
  load it into its cargo: a rover holds four (two on the tail deck, one
  on each flank rack), a bike one, the mech and the jet none. A crate can
  be lifted back out of the cargo. A vehicle with cargo cannot be packed
  onto the watch.
- **Banking.** A crate goes home only through a depot: stand in one
  carrying it, or drive in with it in your cargo, and hold, and its
  contents are banked with your pack. A crate holds four to six items
  from the Dune Sea's salvage table, worth several caches together:
  Salvaged Gearboxes and Drive Coils (vehicle parts), alloy, cells and
  boards, and now and then a reactor core or a vehicle blueprint (the
  Bulwark Mech's or the Kestrel Jet's). What is inside is only seen once
  it is banked.
- **Death.** You keep what you wear; the pack drops in a bag, and every
  crate you haul falls to the sand where you die, the one in your hands
  and all the cargo of the vehicle you drive, for whoever gets there
  first. Signing out leaves them behind the same way, and so does a
  vehicle cleared away for standing idle.
- **The endless world.** A wreck field's emptied spot gets a new crate
  after 4 minutes (`WorldDef.crate_respawn_time`), and a crate left lying
  anywhere else is cleared after 10 (`crate_lifetime`).

### The Dune Sea (part two, built: sandstorms)

Sandstorms cross the Dune Sea one at a time (Caleb's call: shifting
fields). Each comes in off the sand from any side, aimed through one of
the wreck fields, about 400 m across and quicker than other worlds'
storms. In its thick, sight drops to about a third, shots and footsteps
carry half as far, the wind throws flight rigs about and the sand wipes
out tracks; it looks like an ochre wall of driven grit.

- **Burying.** Three of the eight wreck fields start buried, their hulks
  under the sand and nothing on their spots. A storm in full cry buries
  every open wreck field its heart passes over: the hulks sink, and the
  crates lying there are gone, though not the one in someone's hands or a
  vehicle's cargo. A buried field's spots stay empty.
- **Uncovering.** For each field it buries, the storm uncovers a buried
  field out of its reach (one it has already passed if it can), with a
  fresh crate on every spot at once. The war feed tells everyone what the
  storm buried and uncovered and roughly where, so a storm starts a race
  to the new field.

### The Dune Sea (part three, built: convoys and roof guns)

Caleb's call: a hauler convoy, and roof guns on the rovers.

- **Convoys.** Now and then, in place of a warlord or a supply pod, a
  convoy sets out from one salvage yard for another along a road across
  the sand, passing wreck fields on the way, and the war feed says where.
  In front, a rover hauling four salvage crates; behind it a second rover
  and a raider bike riding escort. Raiders drive them, a gunner stands at
  each rover's roof gun, and a rider sits behind on the bike. The convoy
  keeps its spacing, slows into turns, and the hauler waits for its
  escort if it falls far behind.
- **Stopping it.** Drop the hauler's driver and its four crates spill on
  the sand; every raider aboard gets off and fights for them on foot, and
  the rovers and the bike stay where they stopped, anyone's to drive off
  in. A convoy that gets through, or is not caught in time, is gone with
  its crates.
- **Roof guns.** Every Warden rover's front passenger seat is now a roof
  gun: whoever climbs up stands through the roof, head and shoulders out,
  on a heavy belt-fed gun (120 rounds a belt, no reserve to run out of,
  long range). It is the seat's, never yours: get off and it stays on the
  rover, your own weapon back in hand. A raider on a roof gun watches all
  round, opens fire from farther out than its kind would, and never waits
  its turn in a group fight.
- **Still to come.** Shooting out a rover's wheels (vehicles take no
  damage yet), and the gun swung on a mount rather than held.

### The Basalt Rift (part one, built: the world and updrafts)

`worlds/rift/`, on the Basalt Rift planet type. Caleb's call: built in
parts, the world and its updrafts first, then the Sky Leviathan, then the
rig rewards. A small, tall PvP world, about 300 m across between cliffs,
where nothing stands on the floor: a sea of lava covers it, and everything
you fight on is basalt rising out of it. Ashfront's death rule: the fallen
drop scrip, not gear. The starter kit carries the Mk1 jetpack, since a rig
is the point here.

- **The places.** Players land on the Gate Shelf, a ledge on the south
  cliff 24 m over the lava with the gate outpost and two depots. Three
  mesas hold the strongpoints: the West and East Stacks (18 m) and the
  Anvil in the middle (30 m), each a broad six-sided column with lower
  columns round its sides and blocks of cover on top. Iron bridges join
  the Shelf and the three mesas, the only ways about for the rift's
  soldiers and for anyone without a rig. Two dozen perches, single columns
  from 6 m to over 50 m, stand about the rift, higher to the north; some
  hold a cache and some a soldier, and only a flyer gets there. The
  Crown, the warlord's mesa in the north, stands 62 m high with the best
  caches on it, and no bridge reaches it. Walls stand at the cliffs' foot,
  so nobody leaves the rift or lands on the cliff tops.
- **The lava.** Whoever's feet go into it burns, player or soldier, fast
  enough to kill anyone in about half a second, armor or not. What someone
  drops dying over it comes down on top of the lava, never in it, so a
  jetpack hovering just over the crust can still grab a scrip pile that
  fell from a fight in the air.
- **Updrafts.** Six vents in the lava send up columns of hot air you can
  see from across the rift (a glow on the lava, heat haze and embers
  rising). Anyone in the air over one is carried up at up to 9 m/s on top
  of whatever they are doing, easing off just under the column's top
  (55 to 92 m): a jetpack hovering in one rises with it, wings climb in it
  instead of sinking and spend no glide stamina there, and a fall through
  one is only slowed. The air pays no heed to a rig's ceiling, which
  still counts from the lava's floor, so every rig tops out well under the
  Crown and the high perches: the updrafts are how you get up there. Two
  of them rise beside the Crown, one beside the Shelf for a first ride,
  and the watch says "updraft" while you are in one.
- **Since built.** The rig rewards, upgrade data and rig cosmetics (part
  three, below).

### The Basalt Rift (part two, built: the Sky Leviathan)

Caleb's call: a world event that fights and falls. Now and then an
armoured airship drifts across the rift, its turrets shooting at flyers.
Breaking its weak spots drops salvage along its path; break them all and it
crashes with a big haul.

- **Its way across.** It comes in high over the east or west cliff, sinks
  to about 38 m over the lava and drifts across the rift at 5 m/s, north
  of the Anvil or between the Stacks and the Shelf, then climbs out over
  the far cliff, turns and comes back: three crossings, then it drifts off.
  The war feed says where it comes in. No perch stands up into its way,
  and its way crosses updrafts, so you can ride one up past it.
- **Weak spots at three heights.** Four engine pods hang under its keel,
  low enough that a Mk1 jetpack held at its ceiling over the lava can look
  one in the eye; two armoured spine plates sit on its back, soft to a
  dive from above (two and a half times the damage); two turrets stand on
  its bridge tower above them. The plates and turrets are above every
  rig's ceiling: you get to them by riding an updraft up past the ship, or
  diving off the Crown. Each weak spot glows hot so you can pick it out
  from a mesa. The design's first sketch had the pods for boots and bikes;
  in the rift the pods are for jetpacks and for guns from the mesas and
  bridges.
- **Boots in the rift** (Caleb's call): thruster boots count their 10 m
  ceiling from the floor you last stood on, a mesa's top or a perch's, so
  a kick lifts off anything you stand on. Every other rig still counts
  from the lava's floor, so the Crown stays an updraft climb.
- **The turrets fight.** Each turret is a gunner on a heavy mounted gun
  that sees 90 m all round and shoots at anyone in reach; up there that
  is mostly flyers. The pods and plates only take hits.
- **Loot along its path.** A broken weak spot shows wrecked on the ship and
  drops its salvage straight under it, on whatever is below or floating on
  the lava (alloy, power cells, circuit boards, now and then a reactor
  core), so players on the mesas and bridges can follow it.
- **It falls.** With every weak spot broken it noses down and falls,
  drifting on, and crashes on whatever is under it or on the lava. Its
  hold lands where it came down: the best haul of any event, a supply
  pod's war loot and more (reactor cores, targeting chips, rigs, gear),
  and a chance at an artifact.
- **Online.** It is a vehicle the server moves and every client draws; its
  weak spots are bots the server seats on it, built the same on every
  machine from their kind, and a client shows a piece wrecked once the
  server empties its seat.

### The Basalt Rift (part three, built: the rig rewards)

The rift is where a rig is stepped up and shown off. It pays upgrade data
and rig blueprints, the two things a Mk2 or Mk3 rig is crafted from
(section 10), and the earned thruster trails (below, "Thruster trails").

- **Only rig blueprints.** Every blueprint the rift hands out is a flight
  rig's (jetpack, thruster boots, glide wings); the war's gun and vehicle
  blueprints stay in Ashfront.
- **The Crown's caches.** The three caches on the Crown, the mesa only an
  updraft reaches, are the rift's best: upgrade data more often than not,
  now and then a rig blueprint, reactor cores and targeting chips. The
  rift's other caches hold no upgrade data.
- **The Lord of the Crown** carries two upgrade data, a rig blueprint half
  the time, and now and then the earned Magma trail.
- **The Sky Leviathan.** A broken weak spot sometimes drops upgrade data
  with its salvage. The downed ship's hold always holds two, a rig
  blueprint about half the time, and now and then the earned Leviathan
  trail.

## 3. The watch

The wrist-mounted holographic watch is the interface for the things you do
in action. Raised with X; it comes up by itself when you go down.

> **This replaces the earlier "watch for gameplay" rule**, which put vitals,
> heat and ammo on the watch. Those now live on the visor and the gear, so
> you never press X just to see how you are doing. The watch keeps the
> actions and the things you manage.

### Always in view: vitals, heat and ammo

| Reading | First person | Third person |
| --- | --- | --- |
| Health, armor, stamina | A thin arc at the visor edge (the existing health arc, widened to cover armor and stamina). | The strip and system light on the back of the helmet (already built). |
| Flight heat | A gauge at the visor edge, only while a flight rig is worn (section 5). | The screen on the back of the pack and glowing vents on the rig (section 5). |
| Ammo | On the gun's own display, where you already look down the sight. | The same display on the gun, seen on the model. |

These follow the visor rules: thin projected light that rests dim and never
frames or tints the view, and the same readings with no helmet worn appear
on the gear alone (the gun and the pack). They show only your own state,
never an enemy's.

### Loot at a glance (Caleb's call)

What you are about to pick up and what you just picked up are on the visor,
so the watch is only needed to manage the pack:

- **Looking at a container** (a cache, a bag, a supply pod, a rack: the one
  F would loot), the visor tags it beside the container, clear of the
  crosshair: its name, how many things and their worth, then every item
  inside on its own row (never just the best one), stacked by kind, rarest
  first. Each row has the item's name (the Mk is part of it), its rarity in
  its colour, and a mark for whether it beats what you wear in that slot
  (better, worse or the same; nothing for materials and heals). A long list
  runs on into a second column rather than being cut short. Scrip in a bag
  is a row too.
- **Picking something up** adds a line at the visor's lower right edge, over
  the weapon readout ("+ ARC BLADE MK3"), in its rarity's colour, marked
  where it beats what you wear. More of the same counts up on its line.
  Lines fade after a few seconds.

Every working helmet shows both, the scrap visor included, in both views
(drawn flat in third person, like the rest of the visor). With no helmet
there is no glass to show them on; the prompt and the watch still say what
was looted.

### The summon carousel (Caleb's call)

Raising the watch opens a holo carousel, like pulling gear out of thin air:
scroll through what you carry and pick it, and it materializes. The pack is
the storage behind it.

- **Only what you carry.** The weapon carousel shows the weapons you wear
  and the pack's list what you carry (Caleb's call: one place to swap gear
  in), never the stash. Whatever you can summon is still what you drop when you
  die, so the extraction stakes stay. The pack's capacity still applies: a
  summoned weapon swaps places with the one worn in its slot, which goes into
  the pack with the rounds it had. The weapon in your hand can be stored
  the same way in reverse: a click on it dematerializes it back into the
  pack, leaving its slot empty and your hands free, if the pack has room.
- **Dropping (Caleb's call).** On the pack's list the interact key drops
  the picked item where you stand, in a bag anyone may loot. Never in a
  safe zone or where nothing is at stake.
- **Three levels (Caleb's call).** Raised, the watch is on its tab row:
  the mouse wheel turns between the three tabs and a click goes into one.
  In a tab the wheel moves across that tab's icons only. A click on an
  icon that holds several things (weapons, vehicles, artifacts, portal
  places) opens its list, and only then does the wheel turn through what
  it holds; a click picks. A right click always backs out one level: a
  list to its tab, a tab to the tab row, and the tab row lowers the watch.
  Turning back to a tab lands on the icon last looked at there.
- **Three tabs**, turned with the mouse wheel on the tab row:
  - **Summon:** weapons (only the ones worn: drawn with a click, the one in
    hand stored back into the pack), vehicles (the toy carousel) and the
    artifact (one click uses the attuned one; others carried are loot in
    the pack, one per outing). The pack's fill, worth, heals and scrip sit under
    the tab, and the pack's own icon opens (a click) as a list of what you
    carry, each with its worth, that the wheel turns through. Gear in it
    says the slot it goes in, and a click puts it on (Caleb's call: loot a
    rig or a gun and wear it straight away): a weapon materializes, a
    helmet, frame, flight rig or ability chip goes on, and the worn piece
    goes into the pack in its place. A rig changes only on the ground and
    keeps the old one's heat; a chip starts on its cooldown. Artifacts stay
    loot (one per outing) and attachments wait for the gunsmith bench.
  - **Status (Caleb's call: its icons open with a click):** the map and
    where the war is, and your standing and the hunted warning.
    - **The map** shows a small map on the card. Opened, a tabletop
      hologram of the ground rises off the wrist with its relief, the
      wheel turns through the nearest depot, gate outpost (safe zone) and
      strongpoint, the war's hot zone, the world event and your squad's
      pings, each with a line from you, its distance and direction, and a
      click sets the picked one as your waypoint: a column of light and a
      mark on the visor's heading strip that only you see, gone once you
      get there. It shows only what you are already told, never people.
    - **Standing** opens as "This run", three pages the wheel turns
      through: at stake (the pack and its worth, scrip carried, session
      renown, any bounty: what dying now would cost), safe (what this life
      has banked, lifetime rank) and this life (time alive, kills, streak,
      the contract nearest done).
  - **Mission:** the squad portal, the contract tracker, and
    sign-out and banking.
- **Pop-ups only while they matter:** the death report and landing choices
  when you go down, the flight rig's status while flying, and a brief notice.
- **Balance:** a weapon takes time to materialize by weight (a sidearm about
  half a second, a rifle about a second, two-handers and marksman rifles
  longer) and cannot be used until it is solid; then the watch rests for a
  few seconds before the next. A helmet or armor frame from the pack goes
  on at once, and the watch rests after it too: briefly for a helmet,
  longer for a frame. While it rests the face breathes amber, the carousel
  shows the rest running out, a click on the pack is refused with a low
  buzz, and a soft chime says it is ready. Vehicles keep their own
  recharge. So nobody swaps for free mid-gunfight.
- **The same in both views:** a weapon digitizes into the one real hand
  under a shimmer of light, with a rising digital sweep everyone near
  hears (falling as one is stored), and the carried weapons stand over the card as
  small holograms of their real models.
- **Everywhere (Caleb's call).** Every vehicle, the jet included, can be
  thrown in every world, the plaza too, and a weapon in the pack can be
  summoned there (in the plaza it stays locked like every weapon).
- **At home it is the whole collection.** In the home base nothing is at
  stake, so the carousel turns through every weapon and vehicle you own: a
  vehicle thrown there unpacks to ride round the base and packs back onto
  the watch, and a weapon picked is equipped. Out in a world it is only what
  you carry.
- **The heavy chamber.** A heavy weapon found in the world is scanned into
  the watch and summoned from the weapon carousel, or drawn with key 4
  (Caleb's call after a playtest); either way it materializes like any
  summon (section 6).

### Squad portals (Caleb's call)

The watch opens portals to the other places: the way out of your base and
the plaza, replacing the base's launch pad, arena gate and teleporter pad,
and a way anywhere from anywhere (Caleb's call: portals to your home base
and other places, not only to the worlds, and from out in a world to any
other place too, by way of a sign-out).

- **Where they lead, by where you are:**
  - **Your home base:** every world, the arena, and the plaza (the same
    trip as the base's door).
  - **The plaza (a safe zone):** every world, the arena, and home (the same
    trip as the quarters door).
  - **Out in a world:** home first, then every other world, the arena and
    the plaza. Every one of them is a sign-out (below): your gear goes home
    first and the trip goes on from your base, so nothing carried goes from
    one world straight into another.
  - **The arena:** none; leaving it has its own way.
- **Out of a world a portal is a sign-out with a door, never an escape
  hatch**, wherever it leads.
  Opening it starts your sign-out and takes the sign-out's own time: quick
  at a gate outpost, 15 seconds on the ground, 25 seconds and the beacon
  column in the air. A fight or a bounty still refuses it, and a hit
  cancels it, folding the ring away. The ring unfolds over the countdown
  where everyone in the world can see it, so it marks you as clearly as the
  beacon does. When it ends everything you carry goes home like any
  sign-out. A portal home then lands you in your base (online too, rather
  than the plaza); a portal to somewhere else carries straight on from
  there, with the loadout as it now stands at home, landing at the other
  world's gate outpost, in the arena or in the plaza. Carried gear never
  travels along (Caleb's call): it banks home first, which keeps each
  world's stakes and kit rules its own. A squadmate who
  steps into the ring starts their own sign-out through the same door and
  follows.
- **Opening one:** raise the watch, go to the portal icon on the Mission
  tab, click to open its list, wheel through the places, click. A portal unfolds in
  front of you and stays open about 15 seconds, then folds away.
- **Who goes through:** you and your squad (your clan, online). Others see
  it but cannot use it.
- **Arrival:** at that world's gate outpost, the whole squad together; home
  and the plaza arrive the way their doors do.
- **The same in both views:** the portal is a ring of light in the world,
  never a screen.

### What the watch holds

| Feature | What it does |
| --- | --- |
| Weapon carousel | The weapons worn: draw one, or store the one in hand. Weapons in the pack materialize from the pack's list (above). |
| Vehicle carousel | The permanent garage: swipe through your vehicles, take one as a toy in your hand, throw it to unpack the full-size vehicle. Packs vehicles back up. |
| Heavy weapon chamber | Holds one heavy weapon (section 6). |
| Artifact | Holds and uses your one artifact for the outing (section 6). |
| Sign-out | Starting or cancelling a sign-out with a click on its icon (or L), and its countdown (section 7). |
| Banking | Banking at a depot, and what this life has sent home so far, on the sign-out icon (section 7). |
| Map and pings | A small holographic map on the Status tab (you and where you face, strongpoints and who holds them, depots, gate outposts, the war's hot zone, the risk zones and your side's pings; never other people), standing, and pings to your squad (the ping marks where you look, for your side only). |
| Contract tracker | Your active contracts, on the Mission tab (section 10). |
| Landing choices | Where to drop back in after dying: the wheel picks one on the death report and a click drops in (number keys and Enter still work). |
| Squad portal | Opens a portal to a world, the arena, the plaza or home from anywhere: straight there from your base and the plaza, and as a sign-out from out in a world (above). |
| Pack | What you carry, folded into the Summon tab: its fill, worth, heals and scrip, and later your weight tier (section 4). |

Watch skins are cosmetics, shown off in the hub.

### Raising the watch with your own arm

Raising the watch is a real movement of your character, not a panel that
appears. Your left arm comes up, the forearm turns so the face points at
your eyes, and the hologram opens off the watch on your actual wrist.

- **Third person.** The character's left arm lifts the wrist in front of the
  chest (the rig's left-arm IK, the one two-handed blades already use), and
  the watch stays strapped to the real wrist bone. The hologram opens from
  that wrist instead of floating towards the camera. A two-handed hold lets
  go with the left hand while the watch is up.
- **First person.** The same arm of the same body, seen from the eyes: the
  wrist comes up in front of them along the aim, so the watch is in view
  wherever you look, and the card opens just over its face. There is no
  first-person copy of the arm (the camera rule: first and third person
  differ only in where the camera is).
- Other players see your arm come up too, so a raised watch is a tell that
  you are looking at it.
- The pose is view only: it never changes aim, movement or anything the
  server decides.

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
3. **Melee weapon.** Close quarters, timing-based, parryable. Every melee
   weapon has a short **magnetic air-lunge** for mid-air duels (below).
4. **Flight rig.** The player's movement identity (section 5).
5. **Gadget** (the `ability` slot in code). A tactical tool that complements
   the rig (below).

Alongside those five: an armor frame, headgear (a helmet or goggles, each
with a visor), a vehicle on the watch, and the heavy weapon chamber, which is
filled in the field.

**Backpacks (Caleb's call).** A backpack is a progression item in its own
optional slot. With none worn you carry the 12-slot field pack. The
Outfitter sells three bigger ones for scrip: the Rucksack (16 slots), the
Hauler Pack (20) and the Mule Frame (24). A bigger pack carries more home
and puts more at stake when you die, and the pack itself is gear that drops
with you. A pack costs only its own weight (1.5, 2.5 and 4 kg); what slows
you is what you fill it with (section 4, "Weight"). Each size looks bigger on your back,
and at home they hang on hooks in the gear room.

### Gun roles

Every gun has a range and a target it wins against, so the pick is a
choice and not one best gun. Headshots pay on every gun, close-range guns
lose damage past their reach, and marksman rounds punch partly through
plates. The gun bench (`tests/gun_bench.tscn`) prints each gun's time to
kill by range and armor with every round landing. Against a mid kit
(Trooper Frame, 85 armor):

| Gun | Role | Body | All head | Falls off |
| --- | --- | --- | --- | --- |
| Ashfront Carbine | The all-rounder | 8 rounds, 0.70 s | 6, 0.50 s | 50 to 100 m, to 80% |
| Scrap Rifle | Starter all-rounder | 10, 0.99 s | 7, 0.66 s | 40 to 90 m, to 75% |
| Stinger SMG | Wins inside about 15 m | 10, 0.58 s | 8, 0.46 s | 12 to 30 m, to 55% |
| Longshot DMR | Precision at any range, through plates | 3, 0.84 s | 2, 0.42 s | Never |
| Breacher Shotgun | Two blasts at blade range | 2, 0.75 s | (pellets) | 8 to 22 m, to 35% |
| Service Pistol | Accurate backup | 9, 1.28 s | 5, 0.64 s | 25 to 60 m, to 70% |
| Hornet Machine Pistol | Close spray backup | 19, 0.99 s | 15, 0.77 s | 10 to 28 m, to 50% |
| Warden Hand Cannon | Head and any second hit drops a bare target | 4, 1.65 s | 2, 0.55 s | 35 to 80 m, to 75% |

Army soldiers aim at the chest and get no headshot bonus, so the enemy
balance bands above hold (re-measured after this pass: every row still in
band).

### Handling

How a gun handles is the second half of its role. Every gun pays for
moving, but not the same amount, and every gun takes a moment to come up
to the eye:

- Spread grows with speed on the ground, by the gun's `move_spread_deg` at
  a full sprint (rifles 2 degrees, the DMR 3, pistols and the SMG about 1).
  Standing still or crouched is how you shoot straight.
- Aiming down sights tightens spread over the gun's `ads_time` (pistols and
  the SMG about 0.16 s, rifles 0.25 s, the DMR 0.35 s), so a snap aim is
  not yet a steady one.
- You cannot shoot while sprinting. Pulling the trigger or aiming drops you
  to a walk, and the gun fires 0.2 s after the sprint ends. A click made
  in that moment is kept, so it never feels eaten.

Re-measured on the duel bench over three seeds: every enemy type wins and
loses about as often as before (all rows within the bench's noise).

### Recoil (Caleb's call: learnable patterns)

Recoil rewards learning a gun. Each gun climbs and drifts its own fixed way,
so holding a spray on target is a skill you can practise on the range, and
only a little is left to chance.

- **The kick builds through a spray.** Shots no more than 0.3 s apart are one
  spray. Its first shot kicks 65% of the gun's kick, rising to 125% by the
  ninth, so a short burst is tight and a long one climbs.
- **Each gun drifts its own way** (`recoil_pattern` in its stats): the
  carbine climbs and pulls right after a few rounds, the machine pistol
  pulls left, the scrap rifle and the SMG sway side to side, and every
  single-shot gun (pistol, hand cannon, DMR, shotgun, power weapons) kicks the
  same jump every shot. The Storm Cannon climbs straight.
- **A little chance on top.** 30% of a gun's side kick is random each shot.
- **Aimed is gentler.** Aiming down sights takes 60% of the kick, as before.
- **Same in both views.** The aim moves, not the camera; the gun model
  already jumps in the hand.
- **Bots feel it too.** The kick goes into their aim and they pull against
  55% (rookie) to 90% (veteran) of it, settling once they stop firing, so a
  rookie's long burst climbs off you and a veteran's holds. Their short
  bursts keep the enemy duel rows in their bands.

`gun_bench.tscn -- --recoil` prints each gun's pattern: the kick of the
1st, 5th and 10th shot, and how far a 5- and 10-round spray climbs and
drifts from the hip with no pull against it. With the starting numbers, a
carbine's 10 rounds climb 5.4 degrees and drift 1.8 degrees right (about
2 m off at 20 m); an SMG's climb 2.9 degrees, swaying; a hand cannon jumps
2.6 degrees a shot.

### Feedback

A fight should be read by ear and at a glance, the same in both views:

- Every kind of gun has its own voice: a sharp pistol crack, a fast light
  SMG, a deep shotgun boom, a long marksman report and the hand cannon's
  thump. Gunfire carries about 220 m, a suppressed gun about 45 m, and far
  shots sound duller.
- A round that passes within a couple of metres of you is heard hissing
  by, so you know you are being shot at even when it misses.
- Rounds kick up a puff where they land, a hot spark off a body, and leave
  a mark on a wall for a few seconds.
- The hit marker says what the hit did: white for flesh, steel blue when
  plates soaked it, a wide cyan when the plates broke, gold for a head and
  red for a kill, each with its own sound.
- Being shot jolts your view a little, more for a harder round. The aim
  stays put, so it never costs you a shot.

Who is shooting you is not marked on screen: reading that is the tactical
visor's strength (section on helmets), so plain helmets get only the sound
of the shots and their whizz.

### Helmet off (Caleb's call)

A worn helmet can come off and be clipped to the hip, so faces show where
people meet (the Concourse, a base) and a helmet is still to hand.

- **From its key.** Its own key, K (Caleb's ask), takes it off or puts it
  back on. It was a Summon tab icon on the watch until it had the key, and
  left the watch then (Caleb's call).
- **Shown, not swapped.** Both hands lift the helmet off (Caleb's call),
  so a weapon in hand is put away first. The weapon hand lets go as it
  comes down, and the off hand carries it round the body and clips it to the back of the left hip
  (about a second, `Actor.helmet_stow_time`), and the same backwards to put
  it on. The one body and the one helmet model in every view: in first
  person you see it come forward off the face and down out of the view.
- **Still worn gear.** It stays in the helmet slot: it drops with the body
  and goes home like any worn helmet. It is simply not on the face.
- **Off, it does nothing.** Once it leaves the face the visor shows and
  senses nothing (no glass, no readouts, no scan, zoom, Threat Sense or
  thermal), and the vitals go to the watch card as with no helmet. Helmets
  give no head armor today, so there is nothing else to lose; if they ever
  do, it goes with the visor.
- **Back on where people fight.** Stepping out where weapons work outside a
  safe zone or the base (leaving a gate outpost, a new life in a world) puts
  it back on by itself. Out there it only stays off by choice.
- **Everyone sees it.** It travels as a held key
  (`ActorCommand.helmet_off`), simulated like a crouch, so it predicts
  online and every view shows the same hand and clip.

### Goggles

Goggles are the light alternative to a helmet in the same `helmet` slot, and
they show the player's face and hair from the customizer.

- **Same visor.** Every visor mode a helmet has (zoom, scan, threat, thermal)
  comes in goggles too, with the same glass display in first person.
- **No protection.** Goggles take nothing off a head hit.
- **Their trade is weight.** Goggles count as light headgear, a helmet as
  heavier, so goggles move a loadout toward the light tier (below).
- **Fragile glass.** When visor glass can crack (a helmet follow-up),
  goggles crack sooner than a helmet.

### Armor paints (Caleb's call)

Every armor frame can be painted. A paint is a colour scheme, never a stat:
it recolours the plates, the carrier, the straps, the undersuit and the lit
accent, and leaves the frame's armor, speed, shape, metal, details and glow
strength alone (`core/visual/armor_paint.gd`, `ArmorPaint`).

- **Bought or earned, owned for good.** A paint is a cosmetic stash item
  like clothing, so it never goes on a raid and a full-loot death never
  takes it. The Tailor sells the plain ones (Ashen, Desert, Woodland, Night
  Ops, Arctic, Cobalt, Crimson, Hazard). A few are earned only (Caleb's
  call: the hardest content): Warlord, which Ashfront's warlords sometimes
  carry, and Heart Warden, in the Heart Warden's vault deep in the Engine.
  They are Relic items, so no shop sells them and the market never lists
  them, and they are carried loot until they reach the stash.
- **Picked at the armor stands.** Each stand in the gear hall has a paint
  swatch beside it: using it turns that frame's look through the paints
  owned and back to its own colours. No menu.
- **Per frame look.** The choice is kept per look (Runner, Trooper,
  Thermal, Bulwark, scrap), so each frame can wear its own paint.
- **Part of the look.** The choice rides in the appearance, so it is checked
  where clothing is (only paints the stash holds) and everyone sees it, in
  both views and on the base's stands.
- **Always readable.** Every colour is held in a safe range: plates never
  near black or white, an accent always a clear lit colour, never neon.

### Thruster trails

The flame every flight rig's nozzles burn in can be coloured. A trail is a
colour, never a stat: it changes no thrust, speed, heat or how long or wide
the flame is (`core/visual/rig_trail.gd`, `RigTrail`). It is the "thruster
trail colours" the hub sells for scrip (section 10, "Currency: scrip").

- **Bought or earned, owned for good.** Like a paint, a trail is a
  cosmetic stash item that never goes on a raid. The Tailor sells Ember,
  Toxic, Violet and Redline. Two are earned only, in the Basalt Rift: Magma
  from the Lord of the Crown and Leviathan from the Sky Leviathan's hold.
- **One for every rig.** The choice is one trail, worn on whatever rig you
  fly. With none, rigs burn the factory blue.
- **Picked at the rig stands.** Each rig stand in the gear hall has a trail
  swatch beside it, and the stand's nozzles glow in the trail worn: using
  the swatch turns through the trails owned and back to the factory flame.
- **Part of the look.** The choice rides in the appearance, checked like
  clothing, so everyone sees your flames.
- **Always readable.** The glow is always a clear colour and the hot core a
  pale one, and a chosen trail burns a little less bright than the factory
  flame so its colour reads instead of blooming white.

### Weight

A loadout has one of three weight tiers: **light, medium or heavy**. It is
worked out from everything you carry, in kilograms: the headgear (goggles or
helmet), the armor frame, the rig, the weapons worn, a heavy weapon carried
in the chamber or the hands, the backpack, and what is in the pack (Caleb's
call: keep it light, no hard limits). Nothing is ever refused for being
heavy and there is no menu juggling: a heavier load just moves a little
worse, more the heavier it gets, so a big haul home is a real choice. It
changes how you move, never a rig's top flight speed (section 5).

| Weight changes | Lighter | Heavier |
| --- | --- | --- |
| Acceleration and turning, on foot and in the air | Quicker, nimble | Slower, planted |
| Flight heat | Less heat for the same flying | More heat, so heavy loadouts cool off more often |
| Ground speed, sprint and slide | A little faster, a little longer | A little slower, a little shorter |
| Jump | Unchanged (about 1.2 m) | Lower, never under about 1 m |
| Top flight speed | Unchanged | Unchanged |

- A medium load moves exactly as the game is tuned. Light is under 14 kg (a
  runner's frame, boots, an SMG and a knife), and its bonus grows the
  lighter you go, to about 6% faster at 8 kg. Heavy is 32 kg and up (a
  Bulwark with a rifle and rig, or a trooper's kit with a full pack), and
  each kilogram over slows you a little more, to a floor of 80% speed.
- What things weigh, roughly: a sidearm 1.2 kg, a rifle 4, a marksman rifle
  6, the Breaker Hammer 9 (the heaviest melee weapon), heavy weapons 13 to
  20; frames 4 to 22 (Runner 5, Trooper 11, Bulwark 22); a helmet 1.5; a
  jetpack 6, wings 4, boots 2; loot about 1 kg apiece.
- The tier and weight show on the watch's pack line, under the Summon tab
  ("Medium 24 kg"), and every item card says what the item weighs. The base
  locker's screen will show it next to the loadout it comes from.
- The jetpack's existing allowance for heavy armor (it ignores the armor
  heat penalty, per the aerial proposal) folds into this: the jetpack takes
  half of the heavy tier's extra heat, the other rigs all of it.
- Weight is data: an item's `weight` stat, or a weight for its kind, and the
  tier thresholds are tuning values (`CarryLoad`).

### Melee air-lunge

- With a melee weapon drawn in the air and an airborne enemy within about
  6 m inside the aim cone, the heavy attack becomes a lunge that pulls you
  to them and strikes.
- It keeps a full visible windup and can be blocked or parried like any
  melee attack, and costs stamina. A whiff leaves you drifting.
- On the ground the heavy is unchanged (heavy lunge, dive slam from the air
  onto someone below).
- Stats on `MeleeWeapon`, so each weapon can tune range and pull.

### Melee against guns

A world full of guns needs melee to be the best answer in some moments, not a
backup (Caleb's call). A tap is a light, a hold is a heavy, and
move-and-attack combinations are the special moves. How a fight between
blades is won is the next section.

- **Dash-strike.** A heavy started while sprinting closes up to about 9 m on
  the foe in front within the heavy's windup, for extra stamina. It keeps the
  full visible windup, so it can still be parried.
- **Back strike.** Moving back with a foe right behind you, a light is a
  reverse stab behind you for extra damage.
- **Timed bullet deflect.** A guard raised just in time (about 0.3 s) deflects
  every small-arms round from the front, each one costing stamina, so sustained
  fire breaks it. A guard raised again straight after the last gets no
  deflect (a short cooldown), so it is timed, not held up as a shield. After
  the window a held guard only turns aside half of each round. Marksman
  rounds, power weapons and blasts are never deflected or blocked (Caleb's
  call: small arms only).
- **Blades ignore armor.** Melee hits go straight past armor plates.
- **Silent kills.** Gunfire is heard by patrolling bots within earshot (much
  less with a suppressor), and they come to look. Blades make no noise, so a
  melee kill does not bring the next patrol.
- **One-handed and two-handed.** Every melee weapon is one or the other (an
  item tag, which the hands' grip also reads). One-handers (swords, blades,
  knives, axes) move faster than empty hands, the knife fastest. Two-handers
  (the hammer, the spear, the katana: Caleb's call) move slower, and their heavies stagger and tear
  armor off, which the next gun shots benefit from.
- **Hands on the weapon.** A one-hander sits in the weapon hand, a two-hander
  takes the off hand on the handle, identical in first and third person. The
  grip points come from each model (the aim-down-sights grip work).
- **Each weapon moves its own way.** Swords slash in arcs, the spear
  thrusts straight out, the axe and hammer chop down from over the
  shoulder, and the knife makes tight slashes with a stab for its heavy.
  Every swing speeds up into the hit and eases through its follow-through,
  windups keep drawing back instead of freezing, two-handers swing slower
  and turn the whole body, a dash-strike leans in, and a back strike turns
  the blade back past the hip. Same motion in first and third person.
- **Later:** tight interiors and corners in the worlds where guns are clumsy,
  and more ammo and reload pressure on guns.

### Melee bots (Caleb's call: a blade in reach beats a rifle)

The balance is one rule: range belongs to the gun, reach to the blade, and
the ground between is won by skill (cover, corners, the dash-strike, a timed
deflect). Bots fight to that rule, and like people:

- **Heavies.** A share of a melee bot's attacks are held heavies, with the
  charge and windup on show: 5% in the outer ring, 20% in the middle, 30% in
  the core (`BotBrain.RING_HEAVY`), and 60% into a raised guard or a
  stagger. An Ashfront heavy's own heavy winds up for 0.9 s and hits a
  quarter harder, so it is the easiest swing of all to read.
- **Feints.** In the middle and core rings (15% and 30% of swings,
  `RING_FEINT`), a bot hangs on a charge to draw an early guard and lets go
  as a light; as many of its heavies again are feinted into a guard part way
  (`RING_HEAVY_FEINT`).
- **Kicks and dodges.** A bot facing a raised guard kicks it open (25% in
  the middle ring, 40% in the core, `RING_KICK`), and one that reads a heavy
  coming may dodge it instead of guarding (`RING_DODGE`). Its guard comes up
  only against a swing it reads (`guard_skill`), so it pays for timing like
  a person rather than turtling.
- **Dash-strikes.** A bot sprinting in from out of reach opens with one
  (never in the outer ring; 40% of chances in the middle, 70% in the core,
  at most one try every 3 s, `RING_DASH`).
- **Openings.** A bot strikes at once into a foe's recovery, a stagger, or
  its own riposte after a parry, rather than waiting out its tempo.
- **Cut soldiers flinch.** An army gunner cut by a blade has its gun knocked
  about 14 degrees off and holds fire for 0.4 s (`BotBrain.melee_flinch`).
  That is what a cut at arm's length does, and it is what lets a blade win
  once it arrives. Bots only: a player's aim is never moved, and rival
  raiders, who play like players, never flinch.
- **Soldiers give ground.** An army gunner with a blade inside 9 m drops its
  sights and backs off at a walk, angling away, so reaching it is the
  challenge.

**Measured (melee bench, `duel_bench.tscn -- --melee blade_scrap`, 40
fights, seed 11).** The reference fights with the scrap blade only: a
three-hit combo then a breath, its guard up while it closes on a gunner, and
the same heavies, feints and dash-strikes. It parries only by reading
swings at 40%, so a person who parries on purpose does better against the
heavies.

| Scrap blade against | Start 3 m away | Start 12 m away |
| --- | --- | --- |
| Outer soldier | 100% win in 2.7 s | 80% win in 4.3 s |
| Core soldier | 78% win in 3.4 s | 52% win in 5.1 s |
| Outer heavy | 45% win | 38% win |
| Rival raider (gun, no flinch) | 38% win | 22% win |

After the timing pass (the table above): the reference times its guard as
a person does, raising it `BotBrain.guard_lead` before a swing it read
lands rather than holding it through a heavy's windup, answers a kick it
reads with a swing, and keeps its guard up between swings only against a
gun (no held drain there). Against the core heavy at 12 and 25 m it now
wins about a quarter of its duels (2-10% before), since a bot no longer
holds a free guard.

Before the pass a blade won none of these against soldiers, even from 3 m:
a rifle killed in 2.6 s while the bot reference swung about once a second.
The gun duel rows stay in their bands; the outer heavy at 12 m now sits at
the bottom of its band (72% over 120 duels), the price of its occasional
heavy.

**Later:** a melee pass on the stances and animations (Caleb), and bands
for the melee bench once it has been played.

### Melee duels: timing, not sides (Caleb's calls, the melee pass)

Melee is defence-heavy and rewards timing (Caleb's call). It used to be
directional (a Jedi Academy style side picked with the movement keys or a
mouse flick, and a guard had to match it); that is gone (Caleb's pick):
reading two things at once in a split second was too much, and the
movement keys are for moving and dodging.

- **Sides are the blade's own.** A light combo runs right, left, then over
  the top on its own, each swing starting where the last ended, so the
  string flows; a heavy comes over the top. A guard turns to meet whatever
  comes from the front. A guard never covers the back.
- **Three ways to meet a swing.** A guard raised in the last moment before
  a hit is a **parry** (free; the attacker reels open and the defender's
  next strike is a riposte, half again as hard). A guard raised a little
  earlier, inside about 0.4 s (`timed_window`), is a **timed block**: it
  stops the hit for a sliver of the stamina (`timed_block_cost`). A guard
  held up longer is a **held block**: it drains stamina every second it
  stays up, faster the longer it is held (`hold_drain`, `hold_drain_ramp`),
  and pays full price for every hit. A guard raised again straight after
  one that met nothing gets no parry or timed block (`guard_rearm`), so
  mashing is not timing; one that met its hit in time is rearmed at once.
- **Readable swings.** Every light shows about 0.2 s more windup than
  before (`light_tell`), so it can be seen and timed.
- **Interrupts.** A blow that lands on someone winding up or charging a
  swing cuts it off and holds them a moment (`interrupt_stagger`): the
  quicker blade wins a trade. A blow on someone standing ready never holds
  them, so a landed light never locks anyone up.
- **Clashes.** Two strikes about to land together clash: neither cuts,
  both are knocked back and the blades meet.
- **The kick (V).** Unblockable and breaks a held guard open, but its
  windup is slower than a light's, so a swing beats it, and a missed kick
  leaves its kicker open. Attack beats kick, kick beats guard, guard beats
  attack.
- **Feints.** Aim pressed early in a heavy's windup lets it go and raises
  the guard, for stamina (`feint_stamina`), to bait an early parry.
- **Strings.** A heavy thrown straight off a light comes quicker and from
  the side the next cut would (`combo_heavy_speed`).
- **The dodge (Alt).** Each rig dodges its own way: with no rig a roll
  along the ground (the pack's Roll clip), boots a jet sidestep (still with
  its graze window against rounds), a jetpack a thrust burst, wings a flap
  hop. Swings pass through a dodging body; rounds do not (except the boots'
  graze), so melee players do not shrug off gunfire. A short recovery after
  it keeps the weapon quiet (`dodge_recover`), and it draws on the same
  stamina as the guard, so defence is a stamina game won by timing.
- **It looks like a fight** (Caleb's ask, view only, the same in both
  views): a guarded strike holds a moment while both blades meet at one
  point between the fighters, chest high on the swing's side, with the
  spark struck there (`ActionPose.bind`, `ActorSkin.bind_point`); a
  parried or kicked-open fighter reels, the weapon arm knocked out wide and
  the chest twisted open (`ActionPose.reel`); the feet settle back through
  a windup, drive in with the strike and step back in a reel
  (`ActionPose.footwork`); a cut already asked for flows from where the
  last one ended. Check with `visual_check.tscn -- <dir> --bind-only` and
  `--technique-only <item id>`.

### Melee technique (Caleb's call: each weapon is used the way it really is)

Every attack and guard matches how its weapon is really used, and it reads
as well from the eyes as from behind: one body, both views.

- **Ready.** A one-handed weapon is held with the elbow bent and the fist
  low in front of the hip, the point up toward the foe's face, never with
  the arm locked out at shoulder height. The empty off hand stays up in
  front of the chest as a guard through every swing and block. A katana is
  held in both hands; a hammer and a spear rest across the body.
- **Swings.** Each weapon has its own technique, keyed at the windup, the
  moment of contact and the end of the follow-through: the hand and the
  way the blade points, so the blade turns through the cut edge first and
  the strike lands in front of the chest, where the eyes see it.
  - Sword: diagonal forehand and backhand cuts from the shoulder to the far
    hip, a vertical cut from overhead, and a lunging thrust for its heavy.
  - Axe: raised high behind the shoulder and chopped down steeply, head
    first.
  - Knife: it turns over from its reverse-grip rest into a forward grip
    for short, quick slashes across the chest, and stabs at the ribs from
    the hip for its heavy.
  - Hammer: hauled up over the shoulder in both hands and brought down
    through the body.
  - Spear: thrusts from the hip along the aim, the front hand guiding the
    shaft, and a long lunging thrust for its heavy.
  - Katana: kenjutsu cuts in both hands (kesa-giri, gyaku-kesa, shomen) and
    a tsuki for its heavy.
- **Guards.** Each side has its own guard: the weapon held up across that
  side in front of the body (a spear's or hammer's shaft across it, a
  knife up by the face), overhead held level above the head. A guard
  always shows which side it covers, and it is in view from the eyes.

- **Stance.** With a melee weapon out on the ground the legs take a
  fighting stance: knees bent, the body leant in, and standing still the
  feet staggered, lead foot forward (`Locomotion.fight`).

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
| Gravity Well | A thrown field that drags fliers and vehicles inside it down and slows them | Anti-air and anti-vehicle; the counter to jetpacks, bikes and the jet |

Every gadget is data on the one `Ability` class, with a cooldown, a visible
effect and a counter.

## 5. Flight

Each rig has one clear job and one clear weakness (Caleb's balance pass,
which replaced the earlier aerial rig proposal and its shared cruise speed).
Tune against the table below; the numbers live in `ItemDB` as
`JETPACK_MK1`, `BOOTS_MK1` and `WINGS_MK1`, and `tests/rig_balance_tests.gd`
measures them.

- **Jetpack: height and hover.** The best at climbing, holding a position
  and aiming in the air. It burns heat fast holding still, so it takes
  rooftops and fights from above; its cruise is the slowest of the three.
- **Thruster boots: ground agility and stealth.** Short bursts (kicks, air
  dashes, a brief skim) low to the ground, the quickest recovery and the
  lowest ceiling. Always on: faster on foot, no fall damage, a dodge on every
  dash, quiet and dim. The duelist's rig, best in close fights, stealth and
  interiors.
- **Wings: distance and speed.** The fastest across the map, gliding and
  diving, but no hover, no climb of their own and poor aim. For travel,
  flanking and escapes.

### Mk1 targets

| | Jetpack | Boots | Wings |
|---|---|---|---|
| **Role** | Height and hover | Agility and stealth | Distance and speed |
| Ground speed | 100% | 115% (sprint and slide too) | 95% |
| Cruise (held Shift) | 16 m/s rocket cruise, level | 18 m/s skate, 1.6 m over the ground | 22 m/s soar, level |
| Top air speed | 14 m/s hover drift, 16 m/s cruise | 18 m/s skate, 14 m/s dash on top | 22 m/s glide, 30 m/s dive |
| Climb | 8 m/s | kicks (about 6 m/s on average) | none of their own |
| Max height | 40 m | 10 m | their launch height |
| Hover | 8 s | 1.5 s skim per jump | none |
| Fuel | Heat: hover 1x (12.5 a second), climb 1.3x, cruise 0.18x (about 45 s, 720 m a bar) | 4 charges for kicks and dashes; the skate is free | about 62 s of glide stamina (gliding or soaring) |
| Recharge | 4 s on the ground (coasting cools too) | 1 charge per 1.5 s, anywhere | 5 s, on the ground only |
| Cross Ashfront (550 m) | about 36 s cruising (measured 35) | about 32 s skating (measured 31) | about 25 s from a 30 m perch (measured 26) |
| Air aim spread | +10% with the jets lit | +0% mid-dash or skimming low | +50% gliding |
| Dodge | none | 0.2 s graze window per dash: rounds do 25% | none |
| Fall damage | half | none | none out of a glide |
| Noise and glow | loud, bright: bots hear it 60 m off | quiet, dim: heard 12 m off | medium, wing trails: heard 30 m off |
| Thermal and scan range | 120 m | 30 m | 80 m |
| Indoors (a roof within 8 m) | clumsy: half speed and climb | full use | cannot open |

The wings keep their boost (Caleb's call): two a flight, each +8 m/s ahead
or a small lift (Shift + S), refilled only on the ground. That launches them
off flat ground or saves a dying glide, but it never climbs for long, so the
jetpack keeps vertical play. A launch is free, once per time in the air.

### Flying style (Caleb's call, the style pass)

Each rig flies with a character of its own, seen, heard and felt:

- **Jetpack, a heavy gunship.** You see the weight and the thrust: the
  flames grow and shrink with the throttle and the nozzles swivel to push,
  the body tips into a drift and flares back to stop like a helicopter,
  and a boost lighting kicks the flames and jolts the view. Looks only:
  its handling is unchanged, so it stays the steady place to aim from.
  The loudest rig, its roar heard 60 m away by players and bots alike.
- **Boots, a skater and free-runner.** The skate pumps in strides, a kick
  off a skate spins you once round, an air dash tucks the knees, and jump
  in the air beside a wall kicks you up and away from it, free, once a
  time in the air (still capped at the 10 m ceiling). Quiet: a hum and a
  pop on each kick, heard 12 m away.
- **Wings, a bird of prey.** All about energy: past the glide's speed the
  wings sweep back and the arms tuck, the tips bend up in a hard turn, a
  stall shudders them, and the wingtips stream vapor when fast or pulling
  hard. Pulled up out of a dive, the speed past 22 m/s buys height back (a
  swoop): a 30 m/s dive pulls back up about 20 m, never above where the
  dive began, so the jetpack still owns height. A rush of air heard 30 m
  away.

On every rig the flyer leads and the rig answers (Caleb's ask): the
moment you steer, the head looks into the turn, the chest turns and
leans, the inside arm drops and the outside lifts, the arms reach the
way you push, the hands tip like ailerons and the legs swing to balance,
before the flight itself bends; then the arms and legs swing on with
each change of speed and settle. Wind rushes past your ears at speed on every rig. In first person the view
rolls with a third of the wings' bank and a little with a skate's carve,
and rumbles in a boost; the phone's "Camera motion in flight" turns it
down or off. The vapor is off on the Low and Lowest graphics.

### Cruising (Caleb's call)

Every rig has its own sustained forward flight, held on Shift in the air,
and each feels different:

- **Jetpack: rocket cruise.** The prone boost is the cruise: you lie out
  flat and fly straight and level along the view at 16 m/s, Space and C
  to climb and sink. The steadiest and easiest to point, and aim or the
  trigger stops it dead into a hover. It costs 0.18x the hover's heat, so
  a cool bar carries you about 45 s and 720 m; climbing first costs what a
  climb does.
- **Boots: ground skate.** Held Shift within 4 m of whatever is below (a
  sprinting jump is the way in) skates you 1.6 m over it at 18 m/s, rising
  and sinking with the ground, up a step or a slope and on, carving after
  the view and the strafe keys, leaning into the turn like a skater. It
  costs nothing, so it lasts as long as you like, and it is as steady to
  aim from as a dash. A kick hops you off it over a wall or a car, and back
  down in reach you skate on. Back brakes out of it. It works indoors.
- **Wings: powered soar.** In a glide, held Shift keeps the wings level at
  22 m/s instead of sinking, thrust making up what turns cost, with Space
  let go. Pulled up (S) they climb at up to 4 m/s, so a launch off flat
  ground and a soar gets you up without a perch. It spends glide stamina,
  about 62 s a bar, refilled on the ground. The Shift press is still the
  wing boost. The fastest of the three, with wide sweeping turns.

So the jetpack's cruise is steady and controlled, the boots' low and
nimble, and the wings' fast and sweeping. Across the map the wings are
fastest, then the boots, then the jetpack; the jetpack still owns height
and holding still.

Strengths and weaknesses:

- **Jetpack:** the best high ground and air fights, with an 8 s hover and
  steady aim. Its prone boost is its cruise (Caleb's calls): about 45 s and
  720 m a bar (the Shift press is also an air dash), but no shooting from
  it. Aim or the trigger brings you upright into a hover first, and the
  gun waits out the same beat as coming out of a sprint, so a boost is
  never a fighting stance. Free look (E) holds the boost's heading while
  you look round, like the wings. It is loud, shows on scans at 120 m and
  is the slowest cruise of the three.
- **Boots:** the fastest on foot, the only rig with a dodge, quiet, and they
  work anywhere, the Foundry's buildings included; their skate cruises low
  for as long as you like. But they top out at 10 m, so jetpacks shoot down
  at them and wings outrun them.
- **Wings:** the fastest across the map, great for flanking and escaping.
  But they cannot hover, they climb only slowly in a soar, aim is poor in
  flight, only a sidearm fires with them spread, and they are useless
  indoors.

Fall damage is new with this pass: landing faster than 16 m/s (about a 6 m
drop) costs 4 health per m/s over, scaled by the rig, through `Combat.deal`,
and only out in a world (the home base and safe zones cost nothing). Scan
and thermal reach is the rig's: a Seeker's pulse or a thermal visor picks up
someone wearing a rig from the rig's range above, in place of the visor's
own. Overheat still cuts the jetpack and the wings out until heat falls back
to 35.

**Rig tiers (Caleb's call).** Every rig comes in tiers, Mk1 to Mk3. Each
tier adds about 15% to the rig's **strength only**, never its weakness
(`ItemDB.RIG_STRENGTH`, `_rig_tier`):

| Rig | Mk2 | Mk3 |
| --- | --- | --- |
| Jetpack | 15% longer hover (heat), faster cooling, 46 m ceiling | 32% longer hover, 53 m ceiling |
| Boots | 5 charges, one back every 1.3 s | 6 charges, one back every 1.13 s |
| Wings | 15% longer glide, a 9.2 m/s boost | 32% longer glide, a 10.6 m/s boost |

Wings never glide faster by tier (Caleb's call): every tier cruises at 22 m/s
and dives at 30, so a bike stays faster over a long run, and only a Mk3's
boost (22 + 10.6) keeps pace with the Scrapper's for a moment.

The ceiling is measured from the world's ground (a roof under you does not
count, so roof-hopping never stacks it): the jets stop climbing there, and a
kick, launch or boost tops out on it. It only limits lift: dropping off
something higher is fine. Every rig drops at Mk1; Mk2 and Mk3 are crafted
from the rig's blueprint and upgrade data (section 10), and once crafted
they are ordinary gear, at stake in the PvP world. Mastery never hands out
a tier.

Measured from the street (`feel_bench.tscn`): the jetpack reaches its
ceiling in one climb from cool (Mk1 about 6 s, Mk2 about 6 s, Mk3 about
7 s; held on the ceiling the jets cost only the hover's heat); boots kick
to their 10 m ceiling in about 2 s; wings launch to about 5 m and go no
higher on their own, and the first spread after a launch bites in about
1 s at every tier.

**The flight course.** Past the far end of the base's firing range is an
open-topped yard (`HomeBase._build_course`) to time any rig on a climb (an
8 m tower, with a ramp up its side for wings), a gap (14 m of open air to a
second tower: touch the floor and the run ends) and a 40 m sprint to the
finish. A board at the start shows each stage's time and every rig's best.
Flown by the tests' pilots: jetpack 8.6 s (climb 3.3, gap 2.2, sprint 3.2),
wings 9.8 s (4.4, 2.7, 2.7), boots 13.5 s (4.1, 5.4 with a wait for charges,
3.9).

Flying controls (Caleb's call): the keys fly every rig and the mouse only
looks and aims. Space climbs, kicks, launches or glides (by rig), C sinks or
coasts, and held Shift in the air cruises (above, "Cruising"). Shift + a move key is an air dash that way on every rig, for a little
heat (Shift alone dashes forward). A jetpack hovers only while aim (right
mouse) is held (Caleb's call: no hover that stays on by itself); let go and
you fall, or climb on held Space. Pressing Shift in the air on a jetpack
with a boost (Shift or Shift + W) boosts with no hover first: it speeds you
up head first along the view's heading and the body lies out prone as the
speed builds, the same body in first and third person; holding Shift keeps
boosting, and holding E keeps its heading while you look round. Aim or the
trigger ends it: the body eases up out of prone into a hover over about
half a second (never a snap). Wings are the exception to the mouse only looking: they fly
where you look, like a bird, with momentum (hold E to free look while
they fly straight on). Turns cost speed and pulling up
hard in a turn stalls them. Gliding, Shift is a wing boost that thrusts you
the way you face and keeps the speed, and Shift + S boosts upward; wings
never dash sideways. Q and E fly nothing (E holds free look). Every rig dashes, so the dash is not an
edge by itself: boots dash furthest (14 m/s for 0.3 s, on a charge, with
the graze window), jetpacks middling (16 m/s for 0.25 s, 15 heat), wings
shortest (12 m/s for 0.25 s, on a boost charge, a barrel roll sideways).
The stamina dash (Alt) is unchanged, and in boots it opens the graze window
too.

In a squad the layers become roles: the jetpack holds the high angle, the
wings flank and dive in, the boots push through streets and buildings.

Rig readouts go on the visor edge and on the rig itself (heat screen,
wingtip lights, boot pips), never on a screen overlay. The next section says
where each one sits.

### Flight HUD

Four readings make up the flight HUD. Like the vitals in section 3 they are
always in view, and the watch is not needed for any of them.

| Reading | What it shows |
| --- | --- |
| Heat gauge | The 100 heat bar, with the 35 recovery mark. It warns before the overheat cut-out. |
| Rig cue | One cue per rig: the jetpack's coast-and-vent window, the wings' stall line and boosts left, the boots' dash charges and skim time. |
| Squad markers | Where your squad is, at the visor edge toward them. Squad only; never shows an enemy. |
| Landing warning | Ground coming up while heat is high, or while the rig is about to cut out, so you can land or pulse before you fall. Built: from 75% heat up, overheated, jammed or with a skim's last 0.6 s, and only while a fall from where you are would hurt (so boots, which take no fall damage, never warn). |

- **First person.** The readings sit at the visor edges, as thin projected
  light that rests dim and brightens when it matters (the visor rule in
  `CLAUDE.md`). Nothing sits in the middle of the view.
- **Third person.** The visor glass is gone, so the readings move onto the
  gear. Heat and the rig cue show on the screen on the back of the pack
  (a rig with no pack screen uses its own: wingtip lights, boot pips), the
  rig's vents glow with heat so others can read it too, and the landing
  warning pulses the vents and the pack screen.
- **Fair to read.** Glowing vents are a visible cost of flying hot, in line
  with the thermal rule: the jetpack is the brightest and heat-seekers can
  use it. Squad markers show friends only.

## 6. Heavy weapons and artifacts

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
- **Summoning** it from the watch's weapon carousel, or key 4, materialises it
  in your hands (key 4 added after Caleb's playtest; it was watch only).
  Picking it on the watch while in hand puts it back into the chamber.
- **It takes the primary's place** (Caleb's call): while it is out the
  primary waits in the watch, and getting it back (a key, the watch, or the
  heavy running dry) materializes it over its summon time. The sidearm and
  blade stay instant, so a bad moment to swap still has an answer.
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
  the chamber. That still counts as your one per outing. Decided: yes, one
  from the wall may be taken in. It is a loadout slot, and it leaves the
  stash only for a world that carries heavy weapons. The arena, the PvE
  world and safe zones leave the chamber empty and the weapon on the wall.
- Heavy weapons can only be used in the PvP world. The arena and the PvE
  world leave the chamber empty.
- Death drops it like the rest of your gear: it lies with your bag for
  whoever gets there first. In the game that is a rack beside the bag, so
  the finder scans it into their chamber; a heavy never sits in a pack.
  Where deaths drop scrip piles (Ashfront, "Scrip piles") it is sold into
  the pile with the rest instead, so heavies come only from racks.
- Never sold in shops. Can be sold back at the trader at the usual 40%.
  No price was set for that, so each heavy is valued at 2,500 scrip (sells
  back for 1,000) until a playtest prices them.

### Rig synergy

- Jetpack: fires steadily from a high hover (no air aim penalty).
- Glide wings: high-speed strafing runs. Wings out means sidearm only, so a
  heavy is fired by folding the wings, or from a dive's end.
- Thruster boots: dash-peek around cover.

### Artifacts

Artifacts are rare, powerful one-off items: the long chase for players. All
of them are our own designs. To keep them from making veterans unbeatable
they follow the heavy weapon's rules:

- **One artifact per outing**, carried on the watch.
- **Earned, not bought:** from PvE dungeons and bosses and from arena
  tournaments (so they arrive with those modes).
- **Dropped on death in the PvP world**, for whoever takes it. Where deaths
  drop scrip piles (Ashfront) an artifact still drops as itself beside the
  pile, attuned or in the pack, never sold into it (Caleb's call), so
  artifacts keep changing hands.
- **Banked at bank spots** or by signing out, to the home base.
- Every artifact's effect is visible or felt by the people it touches, like
  visor reveals, and has a counter.

| Artifact | What it does | Limit and counter |
| --- | --- | --- |
| Tether Anchor | Plant a beacon; later snap back to it once | One snap. Good for escapes and holding a bank spot; the beacon can be seen and destroyed |
| Overclock Core | For 10 s your rig makes no heat | Then it locks up and you glide down, helpless in the air |
| Mirror Plate | A wrist shield that sends the next missile or railgun shot back at the shooter | One shot; the plate glows while armed, so a shooter can wait it out |
| Static Bloom | A pulse that shuts off every rig nearby for 3 s, yours included | Everyone drops, you too |
| Ghost Uplink | Bank your loot from anywhere, once | Puts a marker on you for everyone while it uploads |
| Squad Link | Your squad shares one heat pool for 15 s, so one can burn hard while others cool | Squad only; when it ends, the pool splits as it stands |
| Echo Recorder | Replays the last 10 s of nearby enemy movement as ghost trails | A replay, never live tracking (the visor rule) |
| Scrap Forge | Turns a downed vehicle into a toy you can throw once | One throw; the vehicle must be wrecked first |
| Holo-Decoys | Throws copies of you that run and fly off | Shots pass through them; they also draw missile lock-ons |
| Time Rewind | Snaps you back to where you were and how healthy you were a few seconds ago | One use per outing; leaves a visible rewind trail so the shooter knows |
| Phase Cloak | Near-invisibility for a few seconds, with any rig | A sign-out cannot run while cloaked (the timer pauses), so it never hides the beacon; firing breaks it |

Gravity Well, first proposed as an artifact, is a normal gadget (section 4):
it is too useful against fliers to be rare.

**The first artifacts (built, MVP).** Four of the table are in the game,
basic and unpolished, so the loop can be played before the rest:

- **Time Rewind**: once an outing, back 4 s to where you were and how
  healthy you were (never less healthy than now). It leaves a glowing trail
  from where you were to where you landed, and a ghost where you land.
- **Phase Cloak**: 6 s of near-invisibility, every 90 s. The whole body and
  its gear fade, the same in first and third person; nameplates hide. Firing
  or swinging breaks it, bots still notice you within 4 m, and a sign-out
  countdown waits while it runs.
- **Overclock Core**: 10 s of flying with no heat, every 90 s; then the rig
  burns out and locks up overheated wherever you are.
- **Static Bloom**: a ring that shuts off every flight rig within 14 m for
  3 s, yours included. Everyone drops. Every 75 s.

How they work for now:

- **Equipping.** An optional `artifact` loadout slot, chosen at the locker
  like the rest of the loadout. The base shows owned artifacts in a lit case
  at the end of the chip shelf (the starter bunker has room for one).
- **Using.** From the watch: raise it (X), wheel to the artifact icon and
  click. The icon shows uses left or a countdown ring, and goes dim when
  spent. There is no hotkey yet.
- **One per outing.** Only the artifact you deploy with can be used. One
  found in the world rides in your pack as loot until you get it home.
- **Finding them.** The Blade Tournament's weekly prize carries a chance
  at one (section 2, "Gladiator arena"), and the Heart Warden's vault a
  small one. The Spore Marsh is their main source (Caleb's call): the Grey
  Matriarch carries one more often than not, its pods sometimes, and its
  forests' hollows, caps and the den now and then (section 2, "The Spore
  Marsh"). World events stand in elsewhere: a warlord carries one half the
  time and a supply pod holds one now and then (`WorldDef` sets the chances
  per world). They are off in Frostline.
- **Losing and keeping them.** The equipped one is gear: it drops in your bag
  on death in the PvP world and goes home on sign-out. One in the pack banks
  at a depot like any loot. Never sold in shops.

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
  (30 seconds after a fight), as today. That wait does not grow for being
  in the air, and it raises no beacon. Nobody plays the body meanwhile: it
  stands still, a hit does not end the countdown, and it can be killed.
- After a dropped connection the game reconnects on its own. Back before the
  body's countdown runs out, you are in it again where it stands, with no
  deploy: the forced countdown ends, and a sign-out you had started yourself
  carries on with the time it has left (the gap counts), unless the body was
  in a fight meanwhile. Too late, and the game says how that life ended (home
  or killed).
- A gate outpost keeps its short sign-out. It does not switch to the air time.

Decided: the airborne sign-out is 25 seconds and a beacon column, not a rule
that you must land. Time already spent is progress. The countdown fills at
1/15 a second on the ground and 1/25 in the air, and landing or lifting off
keeps that progress, so the seconds left are whatever the rate you are on
still needs. A hop shorter than the air grace stays on the ground rate. The
ground time and the air time are tuning values on `WorldDef` (`sign_out_time`,
`sign_out_air_time`). The beacon is the server's decision and is carried on
the actor state, so every client draws the same column. Its sound is loud
enough that a bot on patrol comes to look. A Phase Cloak pauses the countdown
and does not hide the column.

## 8. Vehicles and flight

Vehicles must earn their place next to sustained flight.

- **Clearly faster.** A bike's top speed on ground is well above flight
  cruise (target: at least 1.5 times the jetpack's 14 m/s cruise, so 22 m/s
  or more), and its boost beats every rig's burst on open ground. Wings
  glide as fast as a bike's top speed, but only downhill from a perch and
  for 25 s at a time. Bikes cost no heat. Today the Scrapper runs 24 m/s and boosts to 32 (raised from 22/29 so its boost clears the wings' 30 m/s dive), and the Raider 26/35.
- **Tactical utility.** Mobile cover, mounted firepower, passenger seats for
  squadmates, heavy cargo (more pack space while riding).
- **Seamless transitions.** Throw a toy vehicle from mid-air onto the road
  below and land on it; eject upward off a speeding vehicle straight into
  flight.
- Vehicles live on the watch (section 3). The motorbike is first; more types
  are new `vehicle` items.
- Roads, trails and jump ramps on the maps give bikes routes where they beat
  flying.

### The roster (agreed with Caleb)

Four vehicles with clear roles. This replaces the older six-vehicle plan
(hoverbike, skiff buggy, hover fighter, strider mech, gunship, siege tank):
the rover takes the buggy's place, the mech covers the tank, and the jet
covers the fighter and the gunship.

| Vehicle | Crew | Terrain | Role |
| --- | --- | --- | --- |
| Motorbike (starter) | 1 to 2 (driver and a rear passenger) | Roads, dirt trails, jump ramps | High-speed street racing, tight drifting, launching off ramps into flight |
| Hoverbike (the Raider) | 2 (driver and a passenger behind) | Rough ground, rubble, short gaps | The bike's upgrade: floats over broken ground and gaps a wheel would drop into, drifts through turns, carries a squadmate |
| Armored squad rover | 4 (a full squad) | Rough off-road, canyons, open battlefields | Mobile squad gunship: a roof turret, two passenger firing seats, extra loot storage |
| Compact mech / walker | 1 | Urban streets, boss arenas, bank spots | Heavy frontline tank: thick armor, twin cannons, short hydraulic jump-jets |
| Fighter jet / starfighter | 1 to 2 (pilot and co-pilot) | High-altitude open skies | Fast cross-map travel, aerial dogfighting, heavy air-to-ground missile strikes |

Every vehicle has a clear weakness and a counter (Caleb's call), so none of
them simply wins:

| Vehicle | Weakness | Counter |
| --- | --- | --- |
| Motorbike | No cover: the rider is fully exposed, and it is loud | Shoot the rider; a dive or a melee air-lunge knocks them off |
| Hoverbike | As the motorbike, with two exposed riders; it drifts wide, brakes late, cannot climb steep banks and barely leaves the ground off a ramp | Shoot either rider; catch it on a slope or in a tight turn |
| Rover | Big and slow to turn, needs open ground; the turret gunner's head shows | Heavy weapons, flanking fliers above its turret's arc, and its wheels can be disabled |
| Mech | A rear power unit that takes extra damage, slow turning, and a long watch recharge | Get behind it: boots and wings outmanoeuvre it, and a heavy weapon in the back breaks it |
| Jet | Fragile and cannot hover; its missiles lock on with a warning the target feels | Flares (section 4) break locks, heavy weapons and a hovering jetpack can hit it on its strafing pass |

More on each:

- **Motorbike:** the starter. Ramp launches hand straight over to the
  flight rig.
- **Hoverbike (Caleb's call, replacing the Raider's motorbike):** the
  Scrapper's rare upgrade, built on the same class (the "hover" tag, model
  "hoverbike", `passenger_seat`). Hover vehicles in well-liked games tend to
  share a shape: faster than a wheeled vehicle and smooth over rough ground,
  paid for with lower grip (a drift you have to manage), weaker braking,
  little armor and no real climbing or flight, often with a short float
  over gaps and the ability to turn slowly on the spot. The numbers follow
  that, sized against the bike and flight:
  - Speed 26 m/s, boost 35 (Scrapper 24/32, rover 23/28). A step up from
    the Scrapper, not a new class: the old Raider was 27/37, and the
    hoverbike gave a little of that back for its terrain tricks. Still well
    over the jetpack's 14 m/s cruise.
  - Handling: acceleration 16 (Scrapper 14), turn 2.4 rad/s, but the course
    trails the nose by up to 0.45 rad and grips back at 4 a second, so hard
    turns drift wide and scrub a little speed. It turns slowly on the spot
    (0.8 rad/s), coasts on (2.5 m/s² against 5) and brakes worse (22 against
    32).
  - Ground: rides a 0.45 m cushion, so kerbs and rubble pass under it.
    Off a level edge at 10 m/s or more it holds level for 0.45 s, about a
    12 m gap at top speed and 15 m on boost; off a ramp it keeps 60% of its
    climb and falls 1.6 times as fast while rising, so it barely leaves the
    ground. It cannot drive up slopes over 30 degrees (wheels manage 40).
  - Two up: 92% top speed, 85% acceleration and turn rate, and 60% of the
    gap float, back to full the moment the passenger gets off.
  - Rare, 1,400 scrip, loot only, 10 s watch recharge (the solo bike 8 s).
    Durability waits for vehicle health, which no vehicle has yet.
- **Rover:** the squad vehicle. Passengers who can shoot are the reason to
  ride together instead of flying.
- **Mech:** without a weak spot and a long recharge, a mech parked on a bank
  spot would make it impossible to contest.
- **Jet:** the one most likely to ruin fights for people on foot, which is
  why it is limited to open skies and its strikes can always be seen coming.
- **Watch recharge scales with weight.** Heavier vehicles take longer to
  recharge after one is thrown, so mechs and jets stay rare. Today one
  `toy_cooldown` covers every vehicle; it becomes a stat per vehicle.
- Every vehicle stays a `vehicle` item tuned by its stats, with a toy on the
  watch. The bike, rover and jet must stay clearly faster than flight cruise
  on their own terrain; the mech trades speed for armor and firepower.
- **Handbrake drifting (Caleb's call).** Every wheeled machine and the
  hoverbike have a handbrake on the jump key (the mech's jump key stays its
  jump-jets, the jet's its climb). Held at speed (8 m/s or more) it locks
  the back end: the throttle stops pushing and the speed bleeds off slowly
  (5 m/s² against a brake's 22 to 32), the nose swings round 1.6 times as
  fast and the course trails it, so the machine slides round a corner nose
  first, up to about 50 degrees sideways. Held wide for 0.8 s it banks a
  full charge; letting go on the throttle without hitting anything is a
  clean exit, a burst of up to 4 m/s over 0.3 s, never past boost speed.
  Let go on the brake or into a wall and the charge is lost. Slow, the
  handbrake only brakes. The hoverbike drifts through every turn anyway;
  its handbrake throws it about twice as wide and earns the same burst.
  Tyres smoke and a hover throws up spray while they slide, the same seen
  from the saddle and from across the street. All simulated from the
  command, so it predicts online. On Coilrun the race profiles turn so
  tightly at speed that few corners need braking, so a drift is a style
  there more than a faster line (the race bench's `--drift` run measures
  it); making corners demand it is a grip limit and a smarter bench driver,
  still to come.
- **Slick ground.** A world sets how much grip its ground gives wheels
  (`WorldDef.surface_grip`, 1 on dry ground). Frostline's packed snow gives
  75%, and the frozen river, the lake and the frozen sea give 35%: wheels
  pull away and brake on that share, break loose and slide wide in a plain
  turn, and grip back slower. A hover's cushion does not care.

## 9. Racing (a later mode)

A racing mode, built after the friends playtest. It uses what the game
already has (bikes, rigs, toy vehicles) and stays our own: no monsters,
cars, layouts or tricks taken from any film's race. Hazards and secret
shortcuts are invented for our tracks.

- **Mixed races.** Ride a bike through a course and bail off into flight
  mid-course where it pays off (a ramp, a gap, a shortcut over the roofs),
  then throw the bike back down from your watch to keep riding.
- **Sky races.** Rig-only races through rings in the air, where each rig's
  identity matters: jetpack lines, wing dives, boots skimming low.
- **Hazards and secrets.** Our own: things like collapsing wrecks, storm
  gusts, turret lines or closing gates, with hidden routes for those who
  find them.
- Entered from an in-world place (a gate in the hub or a starting line), not
  a menu, like the arena. Nobody loses gear racing.
- Weakness-and-counter applies here too: no rig or vehicle should win every
  course.

### The race world: Meridian (Caleb's go-ahead)

Racing's first home is a world of its own, Meridian: salt flats round an old
power station, reached through the plaza's gates and portals like any world.
Nothing is at stake there (`gear_at_risk` and `weapons_free` off): you bring
nothing of your own and take nothing home, and nobody can hurt anybody.

- **Classes.** Every track names a class, and only that class's machines
  race it. The first is Street: the Scrapper Bike and the Raider Hoverbike.
  Rovers and mechs, and sky courses for rigs, are classes still to come.
- **Stock machines, race profiles.** The machines are the track's, waiting
  in the pit bays, never the rider's own (toys stay on the watch here). Each
  vehicle item carries a race profile (`ItemDB.RACE_*`, its `race` stat)
  that replaces its combat tuning on the track, so changing a bike for the
  warzone never moves a lap time. League races use these same machines,
  with the rider's tuning kit fitted (below): kits are sidegrades held to
  the bench, so a race is still decided by the rider.
- **Balance is measured.** The time-trial bench (`tests/race_bench.tscn`)
  drives every machine of a class round every track at its limits and
  flags any whose best lap is more than 3% off the class average. Each
  machine keeps its character inside that: the Scrapper corners and brakes
  harder and must take the Spillway's ramp, the Raider is quicker flat out,
  drifts, and can float over the gap.
- **Time trials first.** Getting on a bay machine puts you on the grid under
  five lights; three laps through the checkpoint arches, a lap that leaves
  the track is timed but not counted, and a machine that falls into the
  channel is put back at the last checkpoint. Your split is written on each
  arch, the best laps on the pit board, and your best lap on each machine
  runs beside you as a ghost of hard light. The watch's contract icon is the
  race icon here (race, restart, which ghost, stop), and the visor's
  objective line carries the lap.
- **Live races (Caleb's go-ahead).** The race icon's first pick is Race:
  it puts you on the grid of the track's next race, and anyone who gets on
  a machine there while it forms joins it. AI racers take every slot left
  on the grid at once (Caleb's report: starting a race looked like nothing
  happened), and each person who joins later takes one's place, so a grid
  of 8 always goes. A race forms for 30 s, 10 s once everyone in the world
  is on its grid and 8 s once the grid is full of people, and everyone
  starts under one set of lights. The
  watch and the visor carry your place ("P3/8"), the pit board the next
  race's countdown and then the results. Once the winner is home the rest
  have 20 s to cross the line, and a lap off the track costs 3 s on the
  finish. Restart takes you out of the race and back to a time trial.
- **AI racers are fair (Caleb's ask: real racing lines).** An AI racer
  (`RaceDriver`) is a bot on a stock machine of the track's class, on its
  race profile, pressing the same keys a player does: no extra speed, no
  catching up, no cutting the track. It follows the racing line, brakes by
  the machine's own turn rate, drifts if it is good enough, moves off the
  line to get past and can be passed. One skill number sets how near the
  limit it brakes, how tidy its line is, how quick it is off the lights
  and how often it makes a mistake; the best drives exactly like the
  bench, so none ever beats a perfect run (`race_bench.tscn -- --ai`
  checks it). Their laps never go on the board.
- **League and rivals (Caleb's go-ahead).** Every account has a racing
  rating that only live races move (`RaceLeague`, kept on the account
  beside renown, never per name): each racer you beat to the line is +3,
  each who beats you -1, and not finishing counts last. It sets your
  league: Rookie, Club (60), Pro (160), Elite (300) and Champion (480),
  with no relegation. Each league has three named rivals with a manner of
  their own (cocky, clean, a hard blocker who stays inside the rules, a
  veteran, a joker) and a machine they favour; they fill the grid of a race
  whose best rider is in their league, ahead of nameless AI racers at that
  league's skill. The last of each is the league's top rival: to move up,
  your rating must reach the next league and you must have beaten them in
  a race, or it waits at the gate; one league at a time.
- **The race radio.** Rivals talk to each person racing them: at the
  lights, when you pass them or they pass you, when you leave the track,
  and at the finish (the one you beat, or the winner). It is the visor's
  radio lines under the objectives, with a burst of static, or a line on
  the watch with no helmet. A rival you are three wins up on changes their
  tune. Never more than a line every 5 s, or from one rival every 20 s.
- **Rewards are small.** A race pays 30, 20 and 12 scrip for the podium
  and 5 for any other finish, at most 120 a day, so racing never out-earns
  the warzone. The phone's Racing app shows your league, rating and what
  stands between you and the next, your record against each rival, the
  day's pay and your last five races.
- **Ghosts on the server, and friends'.** The server records every
  person's lap as it is driven, and a clean lap faster than your best on
  that track and machine is kept with your account (a few KB, beside the
  account rather than in it), whether it was a time trial's or a race's.
  The race icon's ghost pick turns through your own best, the fastest of
  your friends' (the phone's saved contacts) on that machine, the board
  leader's best lap, and none. The pit board lists your friends' best
  times on that track under its own. Solo, the ghosts stay on this
  computer.
- **Tuning (Caleb's calls: allowed in league races, unlocked by league).**
  Each machine's pit bench (one per machine, behind its bays) fits a
  tuning kit to that machine for you, kept on your account; pressing E
  turns to the next kit you have unlocked, and a machine waiting on the
  grid takes it at once. Club opens Short and Tall gearing, Pro Grip
  tyres, Elite Bite brakes and Champion the Light frame. Every kit trades
  one feel for another (out of corners against top speed, turn against
  drag, braking against getting going) and the time-trial bench drives
  every kit on every machine and track, holding each inside the class's
  3% (`race_bench.tscn -- --tunes`, `--sweep` for what one stat is
  worth), so a kit never buys speed. AI racers run stock.
- **Easy in, easy out (Caleb's ask).** Race control has a desk for each
  track and machine ("Coilrun · Raider") that shows the next race's
  countdown and how many riders are on its grid; using one puts you on a
  fresh machine of that kind, straight onto that grid (forming one if none
  is). While a race is on it tells you when the next forms. Each track
  also has a watch desk: a chase camera on the racers with their name,
  place and lap, the wheel to pick another, the interact key or Esc to
  come back. Once your run is done, a race or a time trial, the watch and
  visor say "head to the pits" and a column of light marks pit row;
  driving into it sets you down there and the machine goes, and if you
  ride on you are set down anyway 40 s after the finish. A machine a desk
  made goes when you get off it. Getting off out on the track, or
  stopping a run from the watch there, sets you down on pit row too
  (Caleb's report) and the machine goes; in the pits nothing moves. The
  desks' prompts name the interact key as it is bound.
- **The tracks are never empty (Caleb's ask).** While anyone is in the
  world, a track with no race and nobody riding it gets an AI race of its
  own: six AI racers, the first a few seconds after someone arrives and
  the next 20 s after one's results come down, at the league of the best
  person there. It is shown on the pit board and the desks like any race
  and moves nobody's league. Asking to race there, at a desk or from the
  watch, calls its field back to the grid to race you; a time trial just
  shares the track with them. With nobody in the world none run, so an
  empty server pays nothing.

The first track is Coilrun, a Street circuit of about 1.6 km: the long
straight past the pits, the Crest, the Capacitor Yard's esses, the
Spillway gap and the sweep round the cooling tower.

The second is Skyhook (Caleb's pick), a Street figure of eight on stilts
north of Coilrun's pits, about 1.2 km: off the line it climbs onto the
deck, turns back over its own start straight on the Flyover, winds a turn
and a half down the Corkscrew round a lit pylon and dives through a ring
back onto the flats. The deck has low walls and banks a little into its
bends; the race only reads the centre line. Each track keeps its own pit
bays, grid, gantry, arches and board, and a racer picks one by walking from
race control to its pit row: a run is on the track nearest the machine
they got on. The Scrapper is quicker round Skyhook's tight turns, the
Raider down Coilrun's straights.

**The spectacle (Caleb's go-ahead: grand and epic).** A race is an event,
so the world round the tracks is packed, all of it decoration: the
two-tier Meridian Grandstand along the Rail with sky boxes, a lit canopy
and floodlights, stands round Breech Hairpin, at the Spillway's landing and
by Skyhook's line, terraces round the cooling tower, a footbridge of people
over the run to the chicane, viewing barges hanging over the infield, and
race control's tower with a big screen of the best laps. The crowd is solid
low-poly figures (`Crowd`, one multimesh a block) who sway, hold up light
sticks and jump as a racer goes past. Round it all, eroded mesas, the dead
launch works on the skyline (leaning launch towers with holo-ads, gantry
cranes, a crashed booster stage, power pylons), searchlights sweeping the
haze and camera drones pacing the racers.

**No bare salt (Caleb's call: too much open space).** The works fill the
pan between the tracks and the dunes, which close in to about 900 m out
(`works.gd`). A belt of districts runs all round, each a slice of the
ring: tank farm, hangar row, container port, cooling plant and launch
field. Each district has one landmark to steer by (fuel spheres, the
vehicle assembly hall, a portal crane, twin cooling towers, a rocket still
on its pad). Buildings stand low near the road and grow taller toward the
dunes, so every view from the track ends on a skyline. Lit service roads
run out into the works. Fans' car parks and tent camps sit just outside
the tracks, and the infield holds a festival with a stage, a big wheel and
a street of food stalls. Catch fences, hoardings and tyre walls line both
roads. It is all decoration, merged into a block of meshes per material,
and nothing stands on a road (`race_tests.gd`, `_test_works`).

## 10. Economy and progression

### The core rule (Caleb's call)

**Skill decides fights, grind decides options, and loot decides how much is
at stake.** Nothing you grind should let you beat a better player, and
nothing you lose should wipe out your progress. Three layers each reward
something different:

| Layer | Rewards | What it is | Lost on death? |
| --- | --- | --- | --- |
| Gear | Skill and nerve | Weapons, rigs, armor and their Mk tiers, found or crafted | Yes, in the PvP world |
| Progress you keep | Time and variety | Mastery, blueprints, banked upgrade data | Never |
| Status | Both | Cosmetics, watch skins, leaderboards, the most-wanted board | Never |

**Tier gaps stay small.** A higher Mk is a real step up but never a big one,
so a skilled player in Mk1 can still beat a Mk3. Rigs gain about 15% a
tier in their own strength only (section 5): jetpacks hover and climb
further, boots get a charge, wings boost harder and glide longer. What a weapon
gains per Mk is TBD (section 13), and kept small either way.

### Currency: scrip

**Scrip, earned everywhere.** The everyday money, used in the hub for
cosmetic skins, thruster trail colours, watch faces and basic gear. We keep
the name scrip, not credits. There is one currency:
what you carry in the field is at stake, and what you have banked is safe.

- Loot is the money; scrip comes mainly from getting loot home.
- Shops sell only base-level gear.

### Loot: base level, better in PvP

Most weapons and gear are found as loot, and **everything that drops is
base level (Mk1)**. Where you look decides how good the find is, not its
tier: the PvP world has the better weapons and the rarer drops, the PvE
world has basic gear and materials. Stronger versions are crafted from
blueprints (below), not found.

### Scrip piles (Caleb's call, 19 November 2026)

On Ashfront a death drops no gear. Everything the body carried is gone, and
where it fell lies a glowing pile of scrip worth what a trader would pay for
it (`Economy.sell_price`: gear at 40%, loot at full value), with the scrip
they were carrying. Gear then comes only from caches, supply pods and racks,
so a strong player cannot kill you and walk off with your best gun, while a
kill still pays and the pile is still a risk to grab.

- **Grabbed by running over it** (`Raid._tick_piles`, within
  `WorldDef.pile_reach`), by any player, not only the killer. The scrip is
  carried scrip, at stake until banked or carried out.
- **One bonus item** beside it from the pack, never what was worn or held
  (`Raid.pile_bonus`): usually something small (a consumable, a material,
  an attachment), and with `pile_found_chance` (15%) a piece of gear they
  found that life instead. Never the scrap kit, gear brought from the stash
  in the pack, or a heavy weapon.
- **Artifacts drop as themselves**, attuned or in the pack, and are not
  sold into the pile (Caleb's call), so artifacts keep changing hands.
- **The insured item** is recalled home first and is not in the pile; salvage
  is paid as before. Insurance stays one item (Caleb agreed): paying out a
  kit's worth would turn dying into selling, and keeping everything would
  take the stakes away.
- **Bounties go in the pile.** Killing a wanted player drops their bounty in
  their pile instead of the killer's scrip: a bigger, redder pile with a
  taller column of light, a line on the war feed, for whoever gets there.
- **Visors mark piles near you** (`WorldDef.pile_seen_range`, 80 m): a coin
  on the heading tape and the contact scope, a bounty's marked apart, so a
  fresh kill draws third parties.
- **Bots drop piles too**, at `bot_pile_share` (half) of what their pack
  sells for, growing by up to `pile_war_bonus` (half again) as the war heats
  up, so the war's dead do not flood the world with scrip and the big fights
  pay best. Players' piles never grow.
- A pile lies for `bag_lifetime` like a bag. Frostline and the arena keep
  their own death rules (`WorldDef.death_drops_scrip` off).

**The back room** gives scrip a top-end use without making rare gear easy:
a stall down the alley off Market Row (the fence, Sable) sells two Rare
pieces a day, picked by the date like a shop's featured piece, at three
times their value (`Economy.BLACK_MARKET`, `black_market_stock`,
`price_in`). Rare gear only: never a heavy weapon, an artifact, a vehicle,
loot or a crafted Mk2 or Mk3. Numbers to tune by play.

### Two worlds, one loop (proposed, Caleb to confirm the numbers)

Players who avoid PvP and players who love it should both feel rewarded,
without either being forced into the other's world. The split:

| | Frostline (expedition, PvE, no PvP) | Ashfront (warzone, PvPvE) |
| --- | --- | --- |
| Death | Keep equipped gear, lose the pack | Lose it all; it drops as a scrip pile |
| Exclusive rewards | Crafting parts, blueprints, Frostline cosmetics and trophies | Rare and Epic gear, heavy weapons, artifacts, most upgrade data, bounties |
| Shared rewards | Scrip, contracts, mastery, a capped share of upgrade data | Scrip, contracts, mastery, renown |

**Frostline decides what you can make. Ashfront decides what you can carry
out that nobody can make.** Frostline has no PvP (Caleb's call): players there
are allies and the interaction is co-op and trade.

**What each axis means.** Rarity (Common to Relic) is how hard something is
to find and what it sells for, never raw power. Mk tier is how much was
invested in it. Mastery is how well you know a gear type (sidegrades only).
Relic is reserved for prestige items from hard feats in either world.

**Weapon Mk cap.** A Mk2 or Mk3 weapon gains handling, never raw damage:
magazine, recoil, range and reload speed, about +10% effective in total at
Mk3 over Mk1. Rigs keep their 15% a tier, in strength only.

**Loot split.** Blueprints and most parts come from Frostline. Ashfront keeps
a light trickle of common parts and pays scrip, upgrade data, rare gear,
heavy weapons and artifacts. Frostline's deepest sites pay a capped trickle of
upgrade data: enough for Mk2 comfortably and Mk3 slowly (about a third to a
half of the total, about three times the time).

**Player marketplace** (a kiosk in the plaza, server-side only). Tradeable:
parts, upgrade data, spare blueprint copies, Mk1 and Mk2 gear. Never
tradeable: Mk3 gear, heavy weapons, artifacts, prestige items, learned
blueprints. A listing fee and a sale fee drain scrip; price bands and a daily
trade cap per account guard against dumping and farming. It must ship before
parts leave Ashfront, or PvP crafters are starved.

What is built (first version): the Exchange, a booth in the plaza's
arcade with the rules above (5% to list, 10% of each sale, a price band of
half to three times an item's value, 10 listings and 20 trades a day per
account, listings home after 7 days). Server-only, shared by every world on
a server, with the board saved beside the accounts. It moves goods through
the ledger calls of the accounts store, a listing's charge and each sale as
one all-or-nothing transaction, so it can move onto the shared account
service later.
Missing: buying more than one at a time from the screen, search and
filters, price history, and the shared account service itself.

**Status without a level.** There is no player level. Renown rank (PvP) stays;
an expedition standing (surveys, sites cleared, bosses) is added beside it,
with titles and cosmetics. A profile page shows both beside total mastery and
gates nothing.

**Safety nets.** Salvage pays back 40% of a lost crafted item's parts, and
one insured item comes back after a death (see "Safety nets" below for what
is built).

**Contracts** gain a world tag: expedition and warzone versions of dailies and
weeklies. The existing rules stay (only a sign-out counts, no player kills).
Built for the expedition (a world's `contract_jobs`, tagged by its
`contract_tag`); warzone-only jobs are still to come.

### Blueprints and upgrade data

> **This replaces the earlier rule** that a blueprint "opens up a new
> option, never a stronger version of one you have." Blueprints now also
> craft stronger Mk versions of gear you already use. New players are kept
> in the game by small tier gaps, the free Mk1 and the safety nets below
> instead.

**Blueprints drop at Mk1, in the PvP world.** A weapon's or rig's blueprint
is found in the warzone at its base level. The expedition world (Frostline)
has blueprints of its own, for new options only (cold-weather gear and
attachments), never a higher Mk of existing gear, and pays the parts every
Mk2 and Mk3 needs (section 2, "Frostline"). Like everything you carry, it is
at stake until you extract (bank it or sign out). Once home it is yours for
good: a blueprint is knowledge, never lost on death.

**Upgrade data steps a blueprint up**, Mk1 to Mk2 to Mk3. It drops from:

- the hot zones (the most contested strongpoints and events),
- elite enemies (warlords and other named bots),
- other players, when you kill them,
- contracts and bounties (below).

You only keep upgrade data you extract with, which rewards PvP skill and
nerve. Contracts give players who avoid PvP a slower, steadier path.

**A mastery gate.** You can only upgrade a blueprint to Mk2 once you have
some mastery in that gear type. Grinding a gun still feeds its upgrade
without mastery handing the upgrade out. Whether Mk3 has a higher gate is
TBD.

**Crafting** happens at the gunsmith bench in your base (any bench, whatever
its base upgrade): blueprint, plus upgrade data, plus a small scrip fee per
craft. A crafted Mk2 or Mk3 is
ordinary gear: it goes in the stash and is at stake in the PvP world like
anything else. The blueprint stays, so you can craft it again.

**What is built (first version).** Rules in `core/progression/crafting.gd`,
shared by solo and online play like the money rules.

- A blueprint is an item you carry out. The moment it reaches your stash
  (banked at a depot, or carried out alive) it is learned: it leaves the
  stash for a list of known blueprints kept on the account, which nothing
  takes away. A second copy of one you know stays as loot to sell.
- Upgrade data is an item too. It is at stake while carried and sits in the
  stash once home. No shop buys it, so it cannot be sold by mistake.
- Each craft also takes parts: the materials already found as loot (scrap
  metal, circuit boards, power cells, alloy ingots, reactor cores). Loot is
  now worth keeping as well as selling.
- You craft at the fabricator, a console beside the bench. Its
  screen lists every recipe with what it costs against what you hold;
  recipes whose blueprint you have not found are listed dim, so you know
  what is out there.
- Where they come from today: Frostline's own blueprints, its parts and a
  trickle of upgrade data on its rims and the relay; in Ashfront, rig and
  gun blueprints and upgrade data in rooftop caches; any blueprint, vehicles included, from a
  warlord (1 in 2) or a supply pod (1 in 4), each with upgrade data
  (2 and 1). Players carry what they found, so killing one pays it too.
  Expedition contracts pay upgrade data, and their weeklies a blueprint.
- Decided (Caleb's call): the war's blueprints stay mainly in Ashfront, but
  Frostline gets a slow route to them too, so a player who never fights
  other players can still reach Mk2 alone: a rare drop at its hardest
  spots (the relay on the Engine, the defence grid's boss) and from long
  expedition contracts, rarer than in Ashfront. Built for the boss (a
  Frostline warlord's `warlord_blueprint_chance`, 0.15 against Ashfront's
  0.5), the relay (a 6% chance of a war blueprint with upgrade data) and
  the expedition weeklies (a blueprint you do not know). Mk3 stays the war's: a rig's
  one blueprint makes both Mks, so Mk3 is held back by its 8 upgrade data,
  which comes mostly from Ashfront, and Frostline players can buy the rest
  at the Exchange. Planned with step 7 of Frostline.

| Recipe | Blueprint | Upgrade data | Parts | Scrip |
| --- | --- | --- | --- | --- |
| Mk2 jetpack, boots or wings | That rig's | 3 | 2 power cells, 1 alloy ingot, 1 cryo core | 400 |
| Mk3 jetpack, boots or wings | That rig's (the same one) | 8 | 2 alloy ingots, 1 reactor core, 2 glacial alloy, 1 engine coil | 1,200 |
| Longshot DMR | Its own | none | 1 alloy ingot, 2 circuit boards | 300 |
| Breacher Shotgun | Its own | none | 1 alloy ingot, 3 scrap metal | 300 |
| Bulwark Mech | Its own | none | 1 reactor core, 3 alloy ingots, 2 power cells | 2,000 |
| Kestrel Jet | Its own | none | 1 reactor core, 2 alloy ingots, 4 circuit boards | 2,000 |
| Thermal Frame | Its own (Frostline) | none | 1 glacial alloy, 1 cryo core, 2 scrap metal | 350 |
| Glacier Grip | Its own (Frostline) | none | 1 glacial alloy, 1 circuit board | 250 |

Every number in the table and every drop chance is a placeholder until the
playtest. Not built yet: the mastery gate (rigs have no mastery track to
gate on yet), Mk2 and Mk3 weapons (what a weapon gains per Mk is still
open, so the two guns are crafted at base level), Mk2 helmets, salvage and
insurance.

**Rig tiers (Caleb's call, moved to crafting).** The rig tiers in section 5
(Mk1 to Mk3, each with a higher ceiling and cooler running, never faster)
come from blueprints here. Only Mk1 rigs and rig blueprints drop as loot; Mk2 and
Mk3 are crafted. Mk2 helmets follow the same rule, but have no blueprints
yet, so nothing hands out a helmet above Mk1.

**Vehicle blueprints** still unlock new vehicles, such as the mech and the
jet (the supply meteor carries them; until it exists, warlords and supply
pods do). The mech and the jet are built at the fabricator and are then
ordinary vehicles in the garage. Tech cores craft high-tier gadgets.

**Prestige gear from hard feats.** Some vehicles and rigs (or rig variants)
only come from the hardest or longest jobs: a rare contract chain, a world
boss, an arena bracket, a long achievement. They should be impressive to
own and show off, but sit inside the same small tier gaps as everything
else. The list is TBD.

### Mastery: how you play the gear

Mastery says "I know this gun." Using gear levels up its type (keyed by
type, never by item id, as today), and levels unlock **attachments and
mods**: optics, grips, magazines, muzzles, fire modes and the sidegrade
variants that exist today. You pick them at the mastery bench in your base.

**Trade-offs only, no flat boosts (Caleb's call).** Every attachment or mod
boosts one stat and costs another, for example:

| Attachment or mod | Gains | Costs |
| --- | --- | --- |
| Long barrel | Range and accuracy | Slower aiming |
| Extended magazine | More rounds | Slower reloads |
| Foregrip | Less recoil | Slower handling |
| Fire-mode mod | Burst instead of auto, or the reverse | The other mode's strengths |

A mastered gun plays better for you because it is tuned to your style, but
it is never stronger overall than someone else's. Raw power comes only from
the Mk tier. Mastery can never be lost, so it must never beat skill.

- Mastery pays for real use, never for extracting, and the firing range
  gives none (section 2).
- Never lost on death.
- It does not hand out Mk tiers; it only gates them (above).

Put simply: **mastery is how you play the gun, extraction is how strong it
gets, and contracts are the safety valve.**

### Contracts and bounties

Two kinds of job, kept apart by name:

**Contracts** are the main source of upgrade data and blueprints. You take
them at a contract board in the hub, a wall you walk up to. Active
contracts show on the watch, with a small tracker on the visor. You hold up
to 3 at a time.

| Kind | How many | Examples | Pays |
| --- | --- | --- | --- |
| Daily | 3 to pick from | Extract with 2 rig parts from Ashfront; win 3 fights in the air; finish a ring race | Scrip and a little upgrade data |
| Weekly | 1 or 2 | Extract 10 times from Frostline; take a blueprint home | More upgrade data, sometimes a Mk1 blueprint |
| High-risk (rare) | When offered | Carry a package out of the hot zone; hold a point for 3 minutes. You are marked on the map until you extract | The best upgrade data |

- **Progress counts only when you extract**, so risk still matters.
- **One reroll a day.**
- Contracts **push variety**: different rigs, weapons, worlds and zones.
  None should reward camping or farming new players.
- Most are counters on events the game already tracks (kills, extractions,
  pickups, race times), which keeps them cheap to build.
- Later, high-risk contracts can grow into real missions.

**What is built (MVP).** The board stands beside the big screen in the
Concourse: a lit wall listing today's jobs, and a terminal in front of it to
take, drop and reroll them (`core/economy/contracts.gd` holds the rules,
`contract_panel.gd` the screen). It offers 3 dailies and 1 weekly from small
pools, picked by the date (UTC) so everyone sees the same board; a reroll
changes only your own dailies. Jobs live on the online account, so the board
is the server's; solo launch-pad runs count nothing yet. A life counts kills,
warlords, strongpoints taken, vehicles ridden (each once) and artifact uses
(`Raid._count`), plus the loot value and items by tag that came home; only a
sign-out counts them, and an "extract" needs at least 100 scrip of loot home
so signing straight out farms nothing. Nothing counts player kills. A finished
job pays at once into the account: scrip, upgrade data where it exists, and
on weeklies a blueprint you do not know yet once blueprints exist. The watch
has a contract icon showing the job nearest done, with this life's progress
on top; the phone buzzes when a job is paid. A world can add its own jobs
(`WorldDef.contract_jobs`, tagged by `contract_tag`): the board then also
offers one daily and one weekly per tag, and they count only from a life in
that world (the result's "contract_tag"). Frostline's are built; their new
counters are an item by id brought home, kills by faction, bosses and caches
searched by kind. Still to come: warzone jobs, per-rig jobs, ring-race jobs, the visor tracker, high-risk jobs, and the
balance of payouts (placeholders today).

**Bounties** are about hunting players, and tie into the most-wanted board
(section 2) and the renown and Marked rules already in the PvP world. When a
player gets hot, a bounty goes up on them; whoever takes them down and
extracts gets paid. *Built:* the bounty (50 per player kill in the streak,
from three kills) pays its killer the same in scrip (Caleb's call), into
the scrip they carry, so it only counts once banked at a depot or carried
out alive. Upgrade data on top is still open.

### Safety nets

Losses should sting without making people quit:

- **Mk1 is always free.** A base-level kit of every slot is always there,
  so nobody is ever locked out of a raid.
- **One insured item.** Each player can insure one item; if it is lost it
  comes back. Caleb's picks (18 November 2026), numbers to tune by play:
  any gear that goes in a loadout slot can be insured, Mk1 to Mk3, but not
  the free scrap kit, heavy weapons, artifacts or vehicles; a policy costs
  25% of the item's value, paid up front; one is held at a time. An insured
  item on the body at a death is recalled home instead of dropping in the
  bag, so the killer never loots it and the server never makes a second
  copy of anything (no feeding the market by dying to a friend). A claim
  spends the policy and the next one waits 12 hours. Selling or trading the
  item, or losing it some other way, lets the policy lapse. It is taken out
  on the fabricator's screen in the base, beside the crafting.
- **Salvage on loss.** Losing crafted gear pays back 40% of its recipe's
  parts (rounded, at least one, rarest parts first) toward crafting it
  again, and the blueprint itself is never lost. Never the scrip fee or the
  upgrade data, and only for gear from your stash lost with the body: not
  what you dropped or threw first, nor anything picked up in the world.

  What is built: `core/economy/safety_nets.gd` (the rules), decided by the
  authority's `Raid` at a death (the result's "recalled", "salvaged" and
  "salvage") and settled by `StashService.settle` online and
  `Raid.apply_result` solo. The watch's death report and a Claims Office
  message on the phone say what came home. Still to come: the recall's
  light on the body for everyone near, a seal on the insured item's display
  in the base, and its mark on the watch's pack list.

### Status

Status rewards both skill and grind, and being seen is what the hub is for:
cosmetics, watch skins and thruster trails (bought with scrip or earned),
race leaderboards, arena results, the most-wanted board, and prestige gear
shown off in the hub.

### Still at stake

- In the PvP world, unbanked blueprints, upgrade data and gear drop on death
  like the rest of what you carry.
- Renown, ranks, bounties and the Marked in the PvP world stay as they are.

### Balance pass 1 (no playtest data yet)

The first pass over the MVP's placeholder numbers, reasoned from design
intent: a fair extraction loop where loot brought home is the money, the
core pays best but is dangerous, Mk tiers and artifacts are a long chase,
and melee stays the answer up close without hard-countering guns. Every
value is still a plain var or table entry, easy to retune after a playtest.

| System | Value | Was | Now | Why |
| --- | --- | --- | --- | --- |
| Crafting | Mk3 upgrade data / scrip | 6 / 900 | 8 / 1,200 | A core warlord drops 2 data and comes back every 6 min, so Mk3 came in about 5 boss kills. Mk3 should be the long chase; Mk2 (3 data) stays quick |
| Blueprints | Supply pod blueprint chance (Ashfront) | 0.35 | 0.25 | Pods come every few minutes and anyone can loot them; the contested warlord (0.5) should be the better source |
| Artifacts | Warlord / supply pod artifact chance | 0.5 / 0.1 | 0.25 / 0.05 | Artifacts are meant to be rare; at 1 in 2 a warlord farm handed one out every couple of kills |
| Artifacts | Phase Cloak / Static Bloom cooldown | 60 s / 60 s | 90 s / 75 s | Unlimited uses: 6 s of invisibility every minute decided too many fights. Bloom grounds everyone, so it stays a bit more frequent |
| Scrip | Bot kill bounty | 20 | 10 | A soldier carries one to three common materials; a 20 bounty on top paid nearly as much again, so farming bots rivalled hauling loot. Kill pay stays small next to loot |
| Scrip | Strongpoint taken | 50 | 75 | Pays the objective, which pulls players into each other, over farming kills |
| Contracts | "Take 2 strongpoints" daily | 200 scrip | 200 scrip + 1 upgrade data | Gives a steadier path to upgrade data that is not a warlord kill |
| Melee | Bullet deflect stamina per round | 3 | 4 | An SMG burst inside the 0.3 s window cost about 14 stamina; sustained fire should break a guard sooner |
| Bots | Gun aim skill (Ashfront) | 0.25 to 0.75 everywhere | outer 0.15 to 0.45, middle 0.3 to 0.65, core 0.5 to 0.85; warlords 0.7 to 0.9 | The outer ring is where new players learn; the core's armies should be its veterans (`WorldDef.bot_skill_range`) |
| Vehicles | Watch recharge after a throw: bikes / rover / mech / jet | 8 / 20 / 45 / 40 s | 12 / 30 / 60 / 60 s | A wrecked vehicle could be replaced too fast to be a loss; the mech and jet are the strongest, so they wait longest |
| Armor | Runner Frame speed | +12% | +8% | Stacks with a one-hander (+8%) or knife (+15%); a light frame should not outrun everyone |
| Armor | Bulwark Frame armor | 140 | 125 | About 2.4x a starter's effective health against guns; 125 keeps it the tank without being a wall |
| Risk zones | Foundry burn (Ashfront core) | 1.5 a second | 2 a second | 50 s from full on a starter instead of 67 s: the best loot is meant to be on a timer |

Looked at and left alone: Mk2 rig cost (3 data, 400 scrip), gun and vehicle
crafts, warlord blueprint chance (0.5), other contract payouts (dailies 120
to 300 scrip, weeklies 700 to 900, kept small next to loot), heavy weapon
summon (1.6 s to materialize, then about 10 s of watch rest), helmets (all
utility, no armor), deflect window (0.3 s), two-handed stagger, lunge and
dash-strike range, player kill scrip (60), sell-back rate (40%).

### Challenge and balance data

Ashfront should be engaging and a challenge but always possible to work
through (Caleb, 18 November 2026). Players choose their own risk: the quiet
rim, the landmarks or the burning core; danger warns before it lands; there
is always a way out; fresh players are kept from strong squads; every
level of player has a goal; and the numbers are tuned from what happens in
play, not guessed.

The last of those is the life log. The authority's `Raid` writes one line
for every life a player finishes, died or signed out (`LifeLog`,
`core/raid/life_log.gd`): the world, the spot and its risk zone, the cause
and what did the killing (a player, a raider, a warlord, a boss, or an army
bot as faction and kind), how many bots had the player as their target at
the end (being converged on), how long the life ran, what was brought,
carried and banked, the war's intensity, the storm and the bounty. It goes
to one JSON-lines file a world a day under `user://life_log` (or
`--life-log <dir>`), never into a save and never back into play. Safe zones
and clients keep none.

Goals at every level are the warzone's own contracts (`WorldDef.contract_jobs`
under the tag "warzone", counted only from Ashfront): dailies from grab and
go (loot three caches in the outer ring) through the landmarks' caches,
banking at a depot and a Foundry cache, to holding the line (stand in a
strongpoint your side holds for three minutes, `hold_seconds`); weeklies
pay upgrade data for fifteen minutes holding sites or five Foundry caches.

Danger warns before it lands. Storms are a wall you see coming, a walker's
beam locks before it fires and soldiers bark before their first shot. An
army's push does the same: when a faction's army turns for a new site
(`Raid._note_army_target`, from its orders), a war horn sounds at the site,
carried across the field, a ring of light marks it, the war feed says
"The Legion is pushing on Signal Hill" (`WorldDef.faction_title`), and the
watch map draws an arrow from the army to the site for a minute
(`Raid.pushes`, `Hud.map_marks`' "pushes"). A push is told loudly at most
every 30 s an army (`PUSH_EVERY`); a change in between only moves the
arrow. Only the server decides; clients are told (`NetSession._army_push`).

Fresh players are kept from strong ones without a matchmaker yet: someone
who brought less than `WorldDef.fresh_gear_value` of gear (1,500 in
Ashfront: the scrap kit and a piece or two) arrives at the gate furthest
from anyone who brought `strong_gear_value` or more (4,500: crafted Mk2
gear), each of whom counts three times as near (`strong_player_wariness`,
`Raid._safest_spawn`). Separate lobbies or shards by gear are a later call
for Caleb, once the life log shows how often fresh players die to people.

`tests/life_report.tscn` reads a folder of them and prints, by zone, how
many lives end there, how many die, how long they last and what they carry;
what does the killing; how many deaths came with three or more bots after
the player; and deaths by the gear brought (and how many of those were to
people, the measure for keeping fresh players from strong squads). `--png`
draws the deaths in red and sign-outs in green over the map.

Targets to read it against (proposed, for Caleb to confirm after the
playtest): the outer ring gets most people out with something; the core
kills more than it lets out but pays for those who make it; nobody dies
with three or more bots on them often; and someone in scrap gear dies to
players far less than to bots.

## 11. Social

- The phone: people, chat, invites, news, mirror, settings.
- Clans: one side in a warzone, a tag by the name.
- Squads of three are the design target for flight pacing.

### Emotes

Eight to start (Caleb's go-ahead, 19 November 2026): wave, salute, point,
cheer, sit down, lean back (arms folded), dance and a taunt (a beckon, the
other hand on the hip). They are picked on the emote key's quick wheel
(below). They were an icon on the watch's Status tab until the wheel came,
and left the watch then (Caleb's call): the watch keeps to what you do in
action.

- **One body, every view.** An emote is a pose on the one body
  (`Locomotion.emote_pose`, `_emote_body`), the same in first and third
  person and to everyone else; first person sits when you sit, because the
  eyes ride the posed head. Point reaches along where you look.
- **Synced as a held key.** The emote playing rides in the command
  (`ActorCommand.emote`), so it predicts, replicates and costs nothing new
  online; each view times it from when it saw it start, like the inspect.
- **Ends when you act.** A wave, salute, point, cheer or taunt plays a few
  seconds; sit, lean and dance hold. Moving, jumping, sprinting, firing,
  drawing, the phone, the watch, a vehicle or leaving the ground ends one.
  Starting one puts the weapon in hand away. View only: nothing in the
  simulation reads an emote, so it never changes a fight.
- **Later:** emotes earned or bought as cosmetics, emotes for two (a high
  five), and a voice line or sound for each.

### Quick emote wheel

Caleb's call (19 November 2026): the emote key brings a wheel up at once,
without raising the watch. With a working helmet it is drawn on the visor
glass like the other readouts (flat in third person, as they are); with no
helmet, or one taken off onto the hip, the watch throws it up as a small
hologram in front of the chest, below the eyes, with a thin beam from the
wrist. Either way it is the same in both views. While it is up the mouse
points at a slice instead of turning the view (the wheel steps round it
too) and clicks never shoot. Held, letting go plays the slice pointed at
(nothing if the mouse never moved); tapped, it stays up until a click
plays a slice, a right click or the key again puts it away. It closes on
the watch, the phone, a vehicle or a death.

### Shortcut keys

Caleb's ask (19 November 2026): keys that go straight to the watch icon or
phone app you want, so the social tools are a press away. They only raise
the same watch or take out the same phone, in the hand, never a menu of
their own; each is an input action, so the Controls app names whatever it
is bound to. B brings up the quick emote wheel (below) and N plays the
emote last picked (again to stop it); M raises it onto the map; the middle
mouse button pings where you look with the watch down; Y takes the phone
out at the squad's chat (Messages with no squad) and U at Contacts (friends,
the squad and its invites). Each pressed again puts it away. The game has
no rebinding screen yet; when it gets one these come with the rest.

### Squads and friends

- **Squads.** A squad is who you play with now: a squad invite from the
  phone's Contacts, and accepting it puts you both in one (up to four; the
  one who asked leads). It is kept by the server's `SocialService` in memory
  like invites, so it follows you from world to world and ends when you
  leave it or go offline. Out in the worlds it is your squad for portals
  (`Raid.set_squad`), in place of your clan; it is not a side, so it does
  not stop friendly fire or share strongpoints (clans still do that).
- **Squad chat.** One conversation for the whole squad in Messages.
- **Friends** are contacts who saved each other. Only friends and
  squadmates see which world the other is in (`SocialService.world_of`),
  and get a Join on Contacts that takes you there the way a squad portal
  does: from the plaza, the arena or your base, landing at the gate outpost.
  Out in a world where gear is at stake you sign out first. An accepted
  world invite goes the same way.
- **Pings** are their own key (the middle mouse button), marking where you
  look for your side. They left the watch (Caleb's call), where the icon
  only did what the key does.
- **Later:** squadmates marked on the visor and watch map (today that is
  your clan), a say-nearby line over the head, voice.

## 12. Roadmap

1. **Before the friends playtest:** the aerial rig rework (two PRs, per the
   proposal), the heavy weapon chamber and banking, the sign-out rework, and
   bike tuning against the new cruise speed.
2. **Friends playtest** on a hosted server (`docs/hosting.md`).
3. **After the playtest:** the base's firing range and flight tunnel,
   expanding the hub, then its spectating screens
   and bounty board and ring courses, the supply meteor event, the melee air-lunge, the gadget list and the first
   new gadgets, vehicle utility on the bike (passenger, cargo), loadout
   swapping in the PvE world, then the rest of the vehicle roster (rover,
   mech, jet), and the racing mode (section 9).
   Artifacts arrive with arena tournaments (the Blade Tournament, built)
   and PvE dungeons, and the Sky
   Leviathan in the Basalt Rift (built). The hub's toy RC arena comes
   last. Squad visits to a base follow online base visits together;
   trophies follow PvE bosses and arena brackets; blueprints and tech cores
   arrive with the meteor, the PvE world and the arena. The progression
   model (section 10) lands in steps: contracts and bounties first (mostly
   counters on events the game already tracks), then Mk1 blueprints and
   upgrade data as drops, then crafting at the gunsmith bench, which is when
   rig tiers move from loot to crafting. A first version of blueprints,
   upgrade data and crafting is built (section 10).
4. **The PvE world:** quests, dungeons and bosses.
5. **More worlds** as plug-ins.

The online and server work runs alongside this, in its own order (section 14):
hardening and reconnecting before the friends playtest, encryption before
strangers play, accounts on SQLite before the marketplace, and official
servers after that.

## 13. Open decisions

Caleb's calls, still open:

- Are the balance pass's Mk1 numbers (section 5) right? To tune by feel in
  the playtest, on the base's flight course.
- Should the armies' bots fly? (Rival raiders do, section 2.)
- Which gadgets to build first from the list in section 4.
- Progression numbers (section 10), all TBD:
  - What a weapon gains per Mk, and how small the gap must stay. Rigs gain
    height and range, never speed; should weapons gain any damage at all, or
    only handling, range and magazine?
  - How much upgrade data each step costs, and the materials or scrip on
    top. (Placeholders are in: 3 and 6 data, 400 and 900 scrip, see the
    table in section 10.)
  - How often blueprints and upgrade data drop, and from what.
  - The mastery level that gates Mk2, and whether Mk3 has a higher gate.
  - Contract and bounty payouts, and how a bounty's size grows.
  - Which prestige vehicles and rigs come from which feats.
- Two worlds, one loop (section 10), proposed numbers to confirm:
  - Should Ashfront drop any parts at all, or only scrip and upgrade data?
  - What share of Mk3's upgrade data may Frostline supply?
  - Marketplace fees, price bands and the daily trade cap.
  - Whether expedition standing earns titles only, or cosmetics too.

## 14. Online and servers

Caleb's calls (17 November 2026), after a review of the online code. The
model stays as it is: one authoritative Godot server per world on ENet,
clients sending only their input, the server deciding every result. What
changes is what goes around it.

**Two kinds of server.**

- **Official servers** share one account per player: stash, progression,
  contracts, clans and the marketplace are the same in every world and every
  instance. Accounts there are never fed from a local save: the solo profile
  and an account on your own server stay apart from your official account,
  because anyone can edit a local file.
- **Friends' servers** (the Docker server in `docs/hosting.md`, and the one
  the base's door starts) keep their own accounts, as today. Nothing moves
  between them and official servers. They keep running every world in one
  program.

**Accounts.** One account service, written in Godot: a headless Godot
program that runs the same GDScript rules as today (`StashRules`, `Economy`,
`Crafting`, `Contracts`, `StashService`), so every rule exists once and solo
play keeps sharing it. It keeps accounts in SQLite (the godot-sqlite plugin,
MIT), where every stash change and every trade is all or nothing, so items
are never duplicated or lost. Postgres only if one machine stops being
enough. Not a ready-made backend such as Nakama: it would need a second copy
of the rules in another language.

Built (accounts and the market): the service is `-- --account-service`
(`core/account/account_service.gd`) and a game server started with
`--account-url` reaches it through an `AccountLink`
(`core/account/account_link.gd`), which offers the `StashService` calls, so
a session does not know which it holds. A game server proves a shared key
to the service and players never reach it. Each request carries an id and
the service writes its receipt in the same transaction as its changes, so a
request sent again after a lost answer is answered, not done twice. What a
server alone knows (a finished life, banked loot, a wager paid) is kept and
sent until answered; what a player is waiting on (equip, buy, deploy) gives
up after 5 s, and a deploy that was never answered is undone by name. The
server reads the accounts of the players it has from its own copy, which
the service keeps fresh. Clans, the phone's records (contacts, messages,
invites) and who is where are kept by the service too once servers share
it, so they are the same in every world's program: a server asks
(`AccountLink.clan`, `social`), keeps a copy of the clans to read at once,
and is pushed the phone snapshots of its own players. A player signed in
to two worlds for a moment (travel) is one presence with two seats
(`SocialService.player_online`'s `seat`).

**Sign-in tokens.** Signing in with the name and secret hands the game a
token, good for 12 hours, that stands for that sign-in. The game shows the
token, not the secret, to the next server it travels to, and every server
of one account service accepts it by asking the service. One token per
account: a new sign-in with the secret replaces it. A token that has run
out falls back to the secret on the same connection. This is what lets each
world run as its own program without the secret going to every one.

**Sign-in.** Official servers move to Steam (or Epic) login through
GodotSteam (MIT), checked on the server with the store's web service. That
brings account recovery, bans and protection against stolen accounts.
Friends' servers can keep the name and secret. A store login is one more
"method" of `StashService.sign_in_with` that ends in an account id; nothing
past that call changes, and the token above is handed out the same way.

Official servers open before the game is on Steam (Caleb's call), once
connections are encrypted, signing in with the name and secret. A recovery
code on the phone (Settings) moves an account to another computer. When
Steam login arrives, the game ties the account it already holds to the
player's Steam account once, so nobody loses progress.

**Scaling.** On official servers each world runs as its own program, since
Godot runs a game loop on one thread and separate programs are how a server
uses more cores, and one crash then takes down one world. Routes name an
address as well as a port.

Built: `-- --server --only <world id>` runs one world's program (the
plaza, a raid world or the arena), and `-- --server --cluster` runs the
whole set on one machine: the account service, then one program a world,
each started again if it stops (`Main._run_cluster`). Each program tells
the account service where it is and how it is doing
(`AccountLink.announce`), and the service keeps the directory of worlds
(`AccountService.directory`) that every program is pushed: a gate's route
(`NetSession.routes`, a port on the same host or "host:port") and the
signs over the plaza's doorways (`world_status`) come from it, so a world
that stops is off the gates within a second and back on them when it
returns. `compose.official.yaml` is the same set as one container a world.
The home-base lobby of a world still rides in that world's program. Not
built: a sign-in on one server pushing out the same account's connection
on another.

Growth goes by measurement: one bigger machine
first, a matchmaker and plaza shards when worlds or the plaza fill, a hosting
service such as Edgegap only when several machines are needed. Server
meshing (one world split across servers) is not planned.

**Built with Godot's own tools.** Sign-in and the version check happen in
`SceneMultiplayer.auth_callback`, before a player counts as connected.
`server_relay` is off. Connections are encrypted with ENet's DTLS: a
server makes its own certificate on first start and the game remembers it
per address, warning if it changes (as ssh does), so no domain or paid
certificate is needed. Game servers talk to the account service over
`WebSocketPeer`. Our own snapshots with prediction stay; Godot's
`MultiplayerSynchronizer` and `MultiplayerSpawner` are not a fit for fast
PvP.

**Order of work.**

1. Before the friends playtest: a hardening pass (sign-in in
   `auth_callback`, relay off, per-player request limits, safe clan saves,
   account backups), reconnecting to your body after a drop, and a bench of
   the whole server with a health line in its log.
2. Before strangers play: encrypted connections.
3. Before the marketplace: accounts on SQLite, still in one program. The
   marketplace builds on this and does not wait for official servers. It
   keeps the `StashService` calls the market uses (`count_of`, `scrip_of`,
   `take_items`, `give_items`, `change_scrip`) and adds one that runs several
   of them as a single all-or-nothing transaction, which wraps each trade.
4. Official servers: the account service as its own program (the deploy,
   bank and settle calls must cope with an answer that comes late or never),
   one program per world, and one Docker Compose setup for all of it. Steam
   login once the game is on Steam.
5. Only when the numbers call for it: a matchmaker, plaza shards, a hosting
   service, and not sending players enemies they cannot see.

**Smooth for the player.** Every step is held to these:

- **Reconnect on its own.** After a drop the game quietly reconnects and
  puts you back in your body; no button (part of reconnecting, step 1).
  Built: the game retries the same server for 30 s, a sign-in finds the body
  left standing, and a connection pushed out by a newer sign-in is told so
  and does not reconnect (section 7, "Sign-out").
- **Official servers by default.** The base's door and the Servers app go to
  them with no address to type; an address is only for a friend's server.
- **Always say which account you are on.** The phone and the base name it
  (solo, a friend's server, official), so separate stashes never look like
  lost gear.
- **No dead end when a world is full.** Send the player to another instance,
  or say how long the wait is.
- **A version mismatch points to the update**, not just an error.
- **Install once.** The game updates itself: at launch it reads the newest
  build's manifest from the "latest" release, downloads the new game data in
  the background and restarts into it (on the start screen at once, during
  play on the next start or from the Servers app). Only a new engine version
  asks for a fresh install. Built: `core/update/updater.gd`.
- **Certificate warnings never show on official servers**; they use a real
  certificate.
- **Travel between worlds within about 3 s**, measured by the whole-server
  bench.
- **Travel that hides its wait.** The whole-server bench measures the
  network and server part of a trip (connect, sign in, deploy): about 0.3 s
  lightly loaded and 2.1 s with 31 players on a shared 4-core box. Two steps
  hide it, in this order. First, connect early: the client starts connecting
  and signing in to the destination while the gate's ring opens (about 15 s),
  so arriving only waits for the deploy. Second, preload the map: the client
  builds the destination world's map and art in the background so arrival does
  not hitch. A short fade through the portal covers what is left. A handoff
  with no loading screen at all (two live connections, swapping which world is
  drawn) is not planned: it breaks the client's one-session assumption,
  prediction and lag compensation, and is the riskiest part where gear is at
  stake. Revisit only if the first two are not enough.
  Built: the game opens a second connection ahead (`NetSession.ahead`,
  `Main._tick_ahead`) and signs in while you stand near a plaza doorway,
  while a portal your squad may use is open, or while a sign-out counts
  down, and the trip carries on with that connection (`Main._take_ahead`);
  one that is never used is dropped after 20 s, and one that cannot get in
  costs nothing. A server keeps room for these beside its players
  (`NetSession.lobby_room`) and says "full" only at the deploy. Meanwhile
  the destination's ground is worked out on a background thread
  (`WorldDef.prepare_map`: the heights and collision, the slow part of a
  map). The rest of the map and its art are still built on arrival, under
  the fade: building them ahead would freeze the place you are leaving.
  The view goes dark at once and fades back in over 0.4 s when the world
  stands (`Main._fade_travel`); the travel screen's text shows only if a
  trip takes longer than 1.2 s. The bench's `--cluster` times it.
- **A taken name asks for another one** on the phone, never just a refusal.
