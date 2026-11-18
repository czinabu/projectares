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
- Section 13 lists the decisions still open. Do not settle them silently.

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
2. **Ring races and time trials.** Courses of rings through the hub's
   skyline, one per rig plus a bike course. A cheap, small version of the
   racing mode (section 9) and a place for new players to practise each rig.
   Leaderboards per rig and for bikes on a screen at the start gate.
3. **Toy RC arena** (later). Fight or race with toy vehicles from the watch.
   It is really a separate little game with its own controls and balance, so
   it waits.

**Expanding the hub comes first.** The Concourse was a walled courtyard with
no room for these. It is now an open district on a high deck with no wall
(Caleb's call: grand, open and sci-fi, not industrial): a lit beacon spire
at the centre, a kiosk arcade round it, slim towers with landing decks and
skybridges at 15 m so the boots can hop the skyline while the tower tops are
for wings and jetpacks, a gate terrace with spare arches for new worlds, a
bike loop round the edge, a big-screen amphitheatre to gather and watch, and
a pad kept clear for the RC arena. Everything is within about 25 seconds'
walk of the arrival pad. It looks sci-fi, not industrial: dark glass and
metal with lit seams instead of brick and punched windows, a glass arcade
canopy, holo signs over every kiosk and floating holo-ads.

### Locals

The Concourse is lived in (Caleb's call): about thirty people go about their
day there, strolling the rings round the spire, browsing the kiosks under
the arcade, watching the big screen from the tiers, standing about in small
groups and wandering out to the boards and the gates. Nothing about them is
even: who walks with whom, where they stand and how long they stay are all
rolled from one seed. They look at you as you pass and step out of your way.
They are a view only: every game makes the same crowd and moves it by the
clock, so the server spends nothing on them and everyone sees much the same
people.

Three of them you can talk to. Walk up and press the interact key, and they
answer in a short line on a card over their head, never a menu:

- **Kade**, the bounty broker at the most-wanted board: how bounties work
  and who is worth most right now.
- **Dusk**, by the spire, who hears things: rumours made from the worlds'
  real news (the war, the event running, a big bounty), never more than the
  plaza's own signs know.
- **Rook**, the fixer by the gates: one small favour a day, a contract job
  of his own (`Contracts.favor_for`) paid a little under a daily. Talk to him
  again to take it; it is held and paid like any contract.

### Home base

- The stash on show: every weapon (long guns, sidearms, melee) on one rack
  in the armory, an alcove off the main room with the locker at its way in
  and the gunsmith bench in a workshop corner of its own off to the side;
  armor stands, rigs, ability chips,
  bikes in the garage, loot on shelves and trophies in the main room.
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
- A garage off the room for the bikes you own, and a firing range behind the
  back wall (the first of the upgrades below, built early as a greybox).

**The base grows with you.** A new player starts in a starter bunker with
everything it takes to play (deploy, change loadout, trade, mastery picks,
fit attachments, go online) and little on show: a short weapon rack in an
armory nook (4 long guns, 2 sidearms, 2 melee), one garage bay, one armor
stand and one rig stand, a small supplies shelf, the gunsmith's workshop, and the mastery
bench and records sharing the trader's and the wardrobe's consoles. Each
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
| Halls | Lounge | 800 | | Room for furniture and decor. Not built yet |
| Headquarters | Ops consoles | 500 | | The mastery bench and records get their own consoles |
| Headquarters | Firing range | 2,500 | | The range below |
| Headquarters | Finish | 1,500 | Any 4 upgrades | Lit trim and light columns |

Crafting tiers are not gated by the bench upgrades: any bench crafts Mk2 and
Mk3 for a small scrip fee per craft (section 10). The crafting console, the
fabricator, stands beside the bench in the gunsmith's workshop.

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
  when empty (built, step 2). Planned: whiteouts that cut sight to about 30 m and wipe
  tracks, and feel like a real blizzard (Caleb's call): wind you see and
  hear, snow driven sideways in gusts, drifts streaming off the rims, bodies
  leaning into it and the wind pushing flight rigs off course. Built
  (step 6): footprints and vehicle tracks the server keeps and sends only
  nearby, and gunshots that carry twice as far. Built (step 7): thin ice in
  the lake's middle that breaks under heavy vehicles, and the Wardens as
  the Engine's defence grid, still running, with its boss at the hatch.
- **What you bring home.** New parts (Cryo Core, Glacial Alloy,
  Engine Coil) that Mk2 and Mk3 recipes need, and Frostline blueprints for
  new options only (attachments, cold-weather gear), never a higher Mk of
  existing gear (built, step 3, see below). Later the inside of the Engine is
  its deep-loot dungeon and the home of the missing artifacts. Expedition
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
contracts), (8) later, with the PvE dungeons, the
Engine's inside. Every number is a placeholder for the playtest.

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
within 55 m. Whiteouts (step 5) will wipe them. A shot carries
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
metres tall (650 health, 40 armor) whose Grid Lance must hold a teal
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
- Full loot on death.
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
  the same.
- **Per world.** A world turns storms on with `WorldDef.weather_kind`
  ("ash", "snow"), names them (`weather_name`) and tunes them with
  `weather_*` (gap, radius, speed, sight, carry, gust, cold). It picks their
  path with `weather_path`. Frostline will add `weather_cold` (body heat
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

**Sky Leviathan** (later; needs the jet and the PvE world's boss work)

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

- **Only what you carry.** The carousel shows your loadout and your pack,
  never the stash. Whatever you can summon is still what you drop when you
  die, so the extraction stakes stay. The pack's capacity still applies: a
  summoned weapon swaps places with the one worn in its slot, which goes into
  the pack with the rounds it had. The weapon in your hand can be stored
  the same way in reverse: a click on it dematerializes it back into the
  pack, leaving its slot empty and your hands free, if the pack has room.
- **Two levels (Caleb's call).** The mouse wheel steps only across the main
  icons, tab after tab. A click on an icon that holds several things
  (weapons, vehicles, artifacts, portal places) opens its list, and only
  then does the wheel turn through what it holds; a click picks, and a
  right click closes the list and goes back to the icons.
- **Three tabs**, stepped through with the mouse wheel:
  - **Summon:** weapons (worn ones are drawn with a click, the one in hand
    is stored back into the pack, ones in the pack are materialized into
    your hand), vehicles (the toy carousel) and
    artifacts (the attuned one is used; others carried are shown but stay
    loot, one per outing). The pack's fill, worth, heals and scrip sit under
    the tab, and the pack's own icon opens (a click) as a list of what you
    carry, each with its worth, that the wheel turns through.
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
  - **Mission:** the squad portal, the contract tracker, a squad ping, and
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
and the way home from anywhere (Caleb's call: portals to your home base and
other places, not only to the worlds).

- **Where they lead, by where you are:**
  - **Your home base:** every world, the arena, and the plaza (the same
    trip as the base's door).
  - **The plaza (a safe zone):** every world, the arena, and home (the same
    trip as the quarters door).
  - **Out in a world:** home only. No portal leads from one world straight
    into another.
  - **The arena:** none; leaving it has its own way.
- **Home from a world is a sign-out with a door, never an escape hatch.**
  Opening it starts your sign-out and takes the sign-out's own time: quick
  at a gate outpost, 15 seconds on the ground, 25 seconds and the beacon
  column in the air. A fight or a bounty still refuses it, and a hit
  cancels it, folding the ring away. The ring unfolds over the countdown
  where everyone in the world can see it, so it marks you as clearly as the
  beacon does. When it ends you go home with your gear like any sign-out,
  and online it lands you in your base rather than the plaza. A squadmate
  who steps into the ring starts their own sign-out and follows.
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
| Weapon carousel | The weapons worn and in the pack: draw one worn, or materialize one from the pack (above). |
| Vehicle carousel | The permanent garage: swipe through your vehicles, take one as a toy in your hand, throw it to unpack the full-size vehicle. Packs vehicles back up. |
| Heavy weapon chamber | Holds one heavy weapon (section 6). |
| Artifact | Holds and uses your one artifact for the outing (section 6). |
| Sign-out | Starting or cancelling a sign-out with a click on its icon (or L), and its countdown (section 7). |
| Banking | Banking at a depot, and what this life has sent home so far, on the sign-out icon (section 7). |
| Map and pings | A small holographic map on the Status tab (you and where you face, strongpoints and who holds them, depots, gate outposts, the war's hot zone, the risk zones and your side's pings; never other people), standing, and pings to your squad (the ping marks where you look, for your side only). |
| Contract tracker | Your active contracts, on the Mission tab (section 10). |
| Landing choices | Where to drop back in after dying: the wheel picks one on the death report and a click drops in (number keys and Enter still work). |
| Squad portal | Opens a portal to a world, the arena, the plaza or home from your base and the plaza, or home from anywhere in a world as a sign-out (above). |
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
3. **Melee weapon.** Close quarters, directional, parryable. Every melee
   weapon has a short **magnetic air-lunge** for mid-air duels (below).
4. **Flight rig.** The player's movement identity (section 5).
5. **Gadget** (the `ability` slot in code). A tactical tool that complements
   the rig (below).

Alongside those five: an armor frame, headgear (a helmet or goggles, each
with a visor), a vehicle on the watch, and the heavy weapon chamber, which is
filled in the field.

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

### Weight

A loadout has one of three weight tiers: **light, medium or heavy**. It is
worked out from the headgear (goggles or helmet), the armor frame and a heavy
weapon carried in the chamber or the hands. It changes how you move, never
a rig's top flight speed (section 5).

| Weight changes | Lighter | Heavier |
| --- | --- | --- |
| Acceleration and turning, on foot and in the air | Quicker, nimble | Slower, planted |
| Flight heat | Less heat for the same flying | More heat, so heavy loadouts cool off more often |
| Ground speed, sprint and slide | A little faster, a little longer | A little slower, a little shorter |
| Top flight speed | Unchanged | Unchanged |

- The tier shows on the watch's pack page and on the base locker's screen, next to the
  loadout it comes from.
- The jetpack's existing allowance for heavy armor (it ignores the armor
  heat penalty, per the aerial proposal) folds into this: the jetpack takes
  less of the heavy tier's heat cost than the other rigs.
- Weight is data: each headgear, frame and heavy weapon item has a weight
  stat, and the tier thresholds are tuning values.

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
backup (Caleb's call). Controls follow a Jedi Academy style baseline (Caleb's
call, mechanics only): the movement keys pick the swing's side by default
(strafe left or right for a side swing, forward for overhead; B switches to
the mouse flick), a tap is a light, a hold is a heavy, and move-and-attack
combinations are the special moves.

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
  (the hammer, the spear) move slower, and their heavies stagger and tear
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
  `RING_FEINT`), a bot starts a charge showing one side, switches, and lets
  go as a quick light from another.
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
| Outer soldier | 90% win in 2.9 s | 78% win in 4.4 s |
| Core soldier | 68% win in 3.3 s | 57% win in 4.4 s |
| Outer heavy | 35% win | 55% win |
| Rival raider (gun, no flinch) | 32% win | 20% win |

Before the pass a blade won none of these against soldiers, even from 3 m:
a rifle killed in 2.6 s while the bot reference swung about once a second.
The gun duel rows stay in their bands; the outer heavy at 12 m now sits at
the bottom of its band (72% over 120 duels), the price of its occasional
heavy.

**Later:** a melee pass on the stances and animations (Caleb), and bands
for the melee bench once it has been played.

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
  and aiming in the air. Slow across the map and it burns heat fast, so it
  takes rooftops and fights from above; it is not for travel.
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
| Top air speed | 14 m/s cruise, 18 m/s boost | 14 m/s dash | 22 m/s glide, 30 m/s dive |
| Climb | 8 m/s | kicks (about 6 m/s on average) | none of their own |
| Max height | 40 m | 10 m | their launch height |
| Hover | 8 s | 1.5 s skim per jump | none |
| Fuel | Heat: hover 1x (12.5 a second), climb 1.3x, boost 2.5x | 4 charges for kicks and dashes | 25 s of glide stamina |
| Recharge | 4 s on the ground (coasting cools too) | 1 charge per 1.5 s, anywhere | 5 s, on the ground only |
| Cross Ashfront (550 m) | about 45 s (measured 40) | about 60 s (measured 51) | about 25 s from a 30 m perch (measured 26) |
| Air aim spread | +10% with the jets lit | +0% mid-dash or skimming low | +50% gliding |
| Dodge | none | 0.2 s graze window per dash: rounds do 25% | none |
| Fall damage | half | none | none out of a glide |
| Noise and glow | loud, bright | quiet, dim | medium, wing trails |
| Thermal and scan range | 120 m | 30 m | 80 m |
| Indoors (a roof within 8 m) | clumsy: half speed and climb | full use | cannot open |

The wings keep their boost (Caleb's call): two a flight, each +8 m/s ahead
or a small lift (Shift + S), refilled only on the ground. That launches them
off flat ground or saves a dying glide, but it never climbs for long, so the
jetpack keeps vertical play. A launch is free, once per time in the air.

Strengths and weaknesses:

- **Jetpack:** the best high ground and air fights, with an 8 s hover and
  steady aim. But it is loud, shows on scans at 120 m, only middling for
  travel, and a held boost overheats it in about 3 s (the Shift press is
  also an air dash).
- **Boots:** the fastest on foot, the only rig with a dodge, quiet, and they
  work anywhere, the Foundry's buildings included. But they top out at
  10 m and are slow over open ground, so jetpacks shoot down at them and
  wings outrun them.
- **Wings:** twice as fast across the map as the others, great for flanking
  and escaping. But they cannot hover or climb on their own, aim is poor in
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
coasts. Shift + a move key is an air dash that way on every rig, for a little
heat (Shift alone dashes forward). A jetpack hovers only while aim (right
mouse) is held (Caleb's call: no hover that stays on by itself); let go and
you fall, or climb on held Space. Pressing Shift in the air on a jetpack
with a boost (Shift or Shift + W) boosts with no hover first: it speeds you
up head first along the view's heading and the body lies out prone as the
speed builds, the same body in first and third person; holding Shift keeps
boosting. Wings are the exception to the mouse only looking: they fly
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
- **Dropped on death in the PvP world**, with your bag, for whoever takes it.
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
- **Finding them.** Until PvE dungeons, bosses and arena tournaments exist,
  world events stand in: a warlord carries one half the time and a supply
  pod holds one now and then (`WorldDef` sets the chances per world). They
  are off in Frostline for now, under the rule that rare gear stays in the
  full-loot war worlds; the PvE source in this section is Caleb's call to
  turn on when it exists.
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
  warzone never moves a lap time. Ranked racing will use these same stock
  machines, so a race is decided by the rider.
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
  race icon here (restart, ghost on or off, stop), and the visor's
  objective line carries the lap.
- **Rewards are cosmetic.** For now only the board's times. Scrip and
  cosmetic rewards come with live races.

The first track is Coilrun, a Street circuit of about 1.6 km: the long
straight past the pits, the Crest, the Capacitor Yard's esses, the
Spillway gap and the sweep round the cooling tower.

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

### Two worlds, one loop (proposed, Caleb to confirm the numbers)

Players who avoid PvP and players who love it should both feel rewarded,
without either being forced into the other's world. The split:

| | Frostline (expedition, PvE, no PvP) | Ashfront (warzone, PvPvE) |
| --- | --- | --- |
| Death | Keep equipped gear, lose the pack | Full loot |
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

**Safety nets.** Salvage pays back about 30 to 50% of a lost crafted item's
parts, and one insured item comes back after a death in Ashfront (cost and
cooldown open).

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
  comes back. Details TBD (cost, cooldown, which items qualify).
- **Salvage on loss.** Losing crafted gear pays back salvage toward
  crafting it again (amount TBD), and the blueprint itself is never lost.

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

## 11. Social

- The phone: people, chat, invites, news, mirror, settings.
- Clans: one side in a warzone, a tag by the name.
- Squads of three are the design target for flight pacing.

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
   Artifacts arrive with arena tournaments and PvE dungeons, and the Sky
   Leviathan with the jet and the PvE world. The hub's toy RC arena comes
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
  - Insurance: its cost, cooldown, and which items can be insured.
  - How much salvage a lost crafted item pays back.
  - Contract and bounty payouts, and how a bounty's size grows.
  - Which prestige vehicles and rigs come from which feats.
- Two worlds, one loop (section 10), proposed numbers to confirm:
  - Should Ashfront drop any parts at all, or only scrip and upgrade data?
  - What share of Mk3's upgrade data may Frostline supply?
  - Marketplace fees, price bands and the daily trade cap.
  - Insurance cost and the salvage share.
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
