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

**Hub activities**, all in-world, in this order:

1. **Spectating screens and a bounty board.** Screens around the hub show
   what is happening in the worlds: a "most wanted" board of the top
   bounties and the Marked, war levels, arena results. Start with stats
   (the plaza's heat signs already get `world_status`); live video of arena
   bouts comes later. The contract board, where you take contracts
   (section 10), stands next to it.
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

### Home base

- The stash on show: every weapon (long guns, sidearms, melee) on one rack
  in the armory, an alcove off the main room with the locker at its way in
  and the gunsmith bench in a workshop corner of its own off to the side;
  armor stands, rigs, ability chips,
  bikes in the garage, loot on shelves and trophies in the main room.
- **Heavy weapons banked from the PvP world hang on the armory wall** and can
  be stacked there (see section 6).
- Consoles do what menus would: locker, gunsmith bench (crafting from
  blueprints, section 10), mastery bench, wardrobe, records, trader, uplink.
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
| Armory | Heavy weapon wall | 4,000 | Armory alcove | Banked heavy weapons (section 6). Not built yet |
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

### PvP world

- The endless warzone (see `CLAUDE.md`): armies, strongpoints, war intensity,
  events, renown and bounties.
- Full loot on death.
- The only place heavy weapons are found.
- Mid-map bank spots and sign-out create the extraction tension (section 7).

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
where players drop in, each with a depot. Still to come: more hotspots (a
volcano, a storm core), a drawn map on the watch with the rings on it,
squad regrouping at the gates, and tuning.

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

### The summon carousel (Caleb's call)

Raising the watch opens a holo carousel, like pulling gear out of thin air:
scroll through what you carry and pick it, and it materializes. The pack is
the storage behind it.

- **Only what you carry.** The carousel shows your loadout and your pack,
  never the stash. Whatever you can summon is still what you drop when you
  die, so the extraction stakes stay. The pack's capacity still applies: a
  summoned weapon swaps places with the one worn in its slot, which goes into
  the pack with the rounds it had.
- **Three tabs**, stepped through with the mouse wheel:
  - **Summon:** weapons (worn ones are drawn with a click, ones in the pack
    are materialized into your hand), vehicles (the toy carousel) and
    artifacts (the attuned one is used; others carried are shown but stay
    loot, one per outing). The pack's fill, worth, heals and scrip sit under
    the tab, so there is no separate pack page.
  - **Status:** the map and where the war is, your standing and the hunted
    warning, under the vitals strip where the visor cannot show it.
  - **Mission:** the squad portal, the contract tracker, a squad ping, and
    sign-out and banking.
- **Pop-ups only while they matter:** the death report and landing choices
  when you go down, the flight rig's status while flying, and a brief notice.
- **Balance:** a weapon takes time to materialize by weight (a sidearm about
  half a second, a rifle about a second, two-handers and marksman rifles
  longer) and cannot be used until it is solid; then the watch rests for a
  few seconds before the next. Vehicles keep their own recharge. So nobody
  swaps for free mid-gunfight.
- **The same in both views:** a weapon digitizes into the one real hand
  under a shimmer of light, and the carried weapons stand over the card as
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
  the watch and summoned from the weapon carousel, never drawn by a key
  (section 6).

### Squad portals (Caleb's call)

The watch opens portals to the other places: the way out of your base and
the plaza, replacing the base's launch pad, arena gate and teleporter pad.

- **Where:** only in safe spaces: your home base, the hub and a world's
  gate outposts. So a portal is a deploy tool, never an escape hatch out of
  a fight. Coming home still means signing out.
- **At a gate outpost (Caleb's call):** the only portal leads home, and
  opening it is the gate's sign-out with a door. It starts your sign-out
  countdown (so a fight or a bounty still keeps you out of the outpost and
  the portal), the ring unfolds over it, and when it ends you go home with
  your gear like any sign-out. A squadmate who steps into the ring starts
  their own countdown and follows. No portal leads from one world straight
  into another.
- **Opening one:** raise the watch, go to the portal icon on the Mission
  tab, wheel through the worlds and the arena, click. A portal unfolds in
  front of you and stays open about 15 seconds, then folds away.
- **Who goes through:** you and your squad (your clan, online). Others see
  it but cannot use it.
- **Arrival:** at that world's gate outpost, the whole squad together.
- **The same in both views:** the portal is a ring of light in the world,
  never a screen.

### What the watch holds

| Feature | What it does |
| --- | --- |
| Weapon carousel | The weapons worn and in the pack: draw one worn, or materialize one from the pack (above). |
| Vehicle carousel | The permanent garage: swipe through your vehicles, take one as a toy in your hand, throw it to unpack the full-size vehicle. Packs vehicles back up. |
| Heavy weapon chamber | Holds one heavy weapon (section 6). |
| Artifact | Holds and uses your one artifact for the outing (section 6). |
| Sign-out | Starting a sign-out and its countdown (section 7). |
| Banking | Banking at a depot and what is banked so far (section 7). |
| Map and pings | The map, standing, strongpoints, and pings to your squad (the ping marks where you look, for your side only). |
| Contract tracker | Your active contracts, on the Mission tab (section 10). |
| Landing choices | Where to drop back in after dying. |
| Squad portal | Opens a portal to a world or the arena in safe spaces, or home from a gate outpost as a sign-out (above). |
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
- **First person.** Your own left arm, in your outfit and skin tone, comes
  up into the bottom of the view in the same pose, replacing today's grey
  box forearm. The body is not drawn in first person, so this is a copy of
  just the character's left arm.
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
how fast you cruise, so a mixed squad still keeps pace (section 5).

| Weight changes | Lighter | Heavier |
| --- | --- | --- |
| Acceleration and turning, on foot and in the air | Quicker, nimble | Slower, planted |
| Flight heat | Less heat for the same flying | More heat, so heavy loadouts cool off more often |
| Ground speed, sprint and slide | A little faster, a little longer | A little slower, a little shorter |
| Top flight cruise speed | Unchanged | Unchanged |

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
  and more ammo and reload pressure on guns. Melee bots using the dash-strike.

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
| Jetpack "Skyhold" | High, 20 to 40 m (up to its tier's ceiling) | Cruise on jets, coast down to vent heat | Stops dead and hovers; steadiest gun platform; best for heavy armor and heavy weapons | Wide turns; loud, bright, heat-seeker bait |
| Glide Wings "Longreach" | Middle, 8 to 30 m, in arcs | Gliding, diving for speed, wing pulses to climb | Fastest dives, tightest turns, silent and cold | Can never stop; sidearm only while the wings are out |
| Thruster Boots "Skirmisher" | Low, within 6 m of a surface, rooftops included | Skimming near surfaces, where the boots cool | Instant air dashes, no aim penalty while skimming, works indoors; a set of kicks tops a 15 m roof | Only cool near a surface, so a climb is a visit: high in the open they burn out in seconds |

The boots reach rooftops (Caleb's call after playtesting: "I should be able
to reach the top of buildings, or at least make it up top for a bit before
having to go lower to refuel"). Three kicks carry them onto a 15 m roof with
heat to spare and a fourth is the ceiling, about 20 m. A roof under the feet
is a surface like the street, so they cool up there; in open air above 6 m
they never cool, so the open sky stays with the jetpack and the wings.

**Rig tiers (Caleb's call).** Every rig comes in tiers, Mk1 to Mk3. The
base level does not let you fly over the whole city; a higher tier gives
more height and distance. Each
tier has a **ceiling**, measured from the world's ground (a roof under you
does not count, so roof-hopping never stacks it): the jets stop climbing
there, and a kick, pulse or launch tops out on it. A ceiling only limits
lift: dropping off something higher is fine, and the rig still holds or
glides you there.

| Tier | Ceiling | Reaches | Where it comes from |
| --- | --- | --- | --- |
| Mk1 | 25 m | Rooftops and the 15 m decks and skybridges | The starter jetpack, the boots in shops, wings and boots as loot |
| Mk2 | 60 m | The tower tops (40 m and up) and the high race rings | Crafted from a blueprint with upgrade data (section 10) |
| Mk3 | 100 m | Over the highest towers and the spire | Crafted, a further step of upgrade data |

Up a tier the rig also runs cooler (cheaper kicks, pulses and climbing,
faster cooling), so it flies further. What never changes:

- **The cruise speed.** Every tier cruises and dashes at the same speed,
  and none boosts faster than the Mk2 jetpack, so a mixed squad still keeps
  together.
- **The 100 heat bar and each rig's loop.** Boots still only cool near a
  surface, so a high climb is still a visit; wings still never stop; the
  jetpack is still loud and hot.
- **Higher tiers follow the progression model (section 10).** Every rig
  drops at Mk1; Mk2 and Mk3 are crafted from the rig's blueprint and upgrade
  data, and once crafted they are ordinary gear, at stake in the PvP world.
  Mastery never hands out a tier. Nothing drops a Mk2 or Mk3: the
  fabricator on the gunsmith bench is the only way to one.

Measured from the street (`feel_bench.tscn`): the Mk1 jetpack reaches its
ceiling in about 7 s, Mk2 13 s, Mk3 19 s; boots kick to about 25 m, 46 m and
100 m; wings climb on pulses and upward boosts to their ceilings in about
8 s (Mk1), 36 s (Mk2) and 29 s (Mk3), or launch off something high.

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
where you look, like a bird, with momentum (hold V to free look while
they fly straight on). Turns cost speed and pulling up
hard in a turn stalls them. Gliding, Shift is a wing boost that thrusts you
the way you face and keeps the speed, and Shift + S boosts upward; wings
never dash sideways. Q and E fly nothing. Every rig dashes, so the dash is not an
edge by itself: boots dash furthest (20 m/s for 0.3 s, 20 heat), jetpacks
middling (16 m/s for 0.25 s, 15 heat), wings shortest but cheapest (12 m/s
for 0.25 s, 10 heat, a barrel roll sideways). The stamina dash (Alt) is
unchanged.

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
| Rig cue | One cue per rig: the jetpack's coast-and-vent window, the wings' stall line, the boots' height band and dash pips. |
| Squad markers | Where your squad is, at the visor edge toward them. Squad only; never shows an enemy. |
| Landing warning | Ground coming up while heat is high, or while the rig is about to cut out, so you can land or pulse before you fall. |

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
- **Summoning** it from the watch's weapon carousel materialises it in your
  hands (no key draws it, Caleb's call).
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

### The roster (agreed with Caleb)

Four vehicles with clear roles. This replaces the older six-vehicle plan
(hoverbike, skiff buggy, hover fighter, strider mech, gunship, siege tank):
the rover takes the buggy's place, the mech covers the tank, and the jet
covers the fighter and the gunship.

| Vehicle | Crew | Terrain | Role |
| --- | --- | --- | --- |
| Motorbike (starter) | 1 to 2 (driver and a rear passenger) | Roads, dirt trails, jump ramps | High-speed street racing, tight drifting, launching off ramps into flight |
| Armored squad rover | 4 (a full squad) | Rough off-road, canyons, open battlefields | Mobile squad gunship: a roof turret, two passenger firing seats, extra loot storage |
| Compact mech / walker | 1 | Urban streets, boss arenas, bank spots | Heavy frontline tank: thick armor, twin cannons, short hydraulic jump-jets |
| Fighter jet / starfighter | 1 to 2 (pilot and co-pilot) | High-altitude open skies | Fast cross-map travel, aerial dogfighting, heavy air-to-ground missile strikes |

Every vehicle has a clear weakness and a counter (Caleb's call), so none of
them simply wins:

| Vehicle | Weakness | Counter |
| --- | --- | --- |
| Motorbike | No cover: the rider is fully exposed, and it is loud | Shoot the rider; a dive or a melee air-lunge knocks them off |
| Rover | Big and slow to turn, needs open ground; the turret gunner's head shows | Heavy weapons, flanking fliers above its turret's arc, and its wheels can be disabled |
| Mech | A rear power unit that takes extra damage, slow turning, and a long watch recharge | Get behind it: boots and wings outmanoeuvre it, and a heavy weapon in the back breaks it |
| Jet | Fragile and cannot hover; its missiles lock on with a warning the target feels | Flares (section 4) break locks, heavy weapons and a hovering jetpack can hit it on its strafing pass |

More on each:

- **Motorbike:** the starter. Ramp launches hand straight over to the
  flight rig.
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
so a skilled player in Mk1 can still beat a Mk3. Rigs gain height and range
(section 5), never speed: cruise is the same on every tier. What a weapon
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

### Blueprints and upgrade data

> **This replaces the earlier rule** that a blueprint "opens up a new
> option, never a stronger version of one you have." Blueprints now also
> craft stronger Mk versions of gear you already use. New players are kept
> in the game by small tier gaps, the free Mk1 and the safety nets below
> instead.

**Blueprints drop at Mk1, in the PvP world.** A weapon's or rig's blueprint
is found in the warzone at its base level. Like everything you carry, it is
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
- Where they come from today, in Ashfront only: rig and gun blueprints and
  upgrade data in rooftop caches; any blueprint, vehicles included, from a
  warlord (1 in 2) or a supply pod (1 in 4), each with upgrade data
  (2 and 1). Players carry what they found, so killing one pays it too.
  Contracts are the next source.

| Recipe | Blueprint | Upgrade data | Parts | Scrip |
| --- | --- | --- | --- | --- |
| Mk2 jetpack, boots or wings | That rig's | 3 | 2 power cells, 1 alloy ingot | 400 |
| Mk3 jetpack, boots or wings | That rig's (the same one) | 8 | 2 alloy ingots, 1 reactor core | 1,200 |
| Longshot DMR | Its own | none | 1 alloy ingot, 2 circuit boards | 300 |
| Breacher Shotgun | Its own | none | 1 alloy ingot, 3 scrap metal | 300 |
| Bulwark Mech | Its own | none | 1 reactor core, 3 alloy ingots, 2 power cells | 2,000 |
| Kestrel Jet | Its own | none | 1 reactor core, 2 alloy ingots, 4 circuit boards | 2,000 |

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
on top; the phone buzzes when a job is paid. Still to come: per-world and
per-rig jobs, ring-race jobs, the visor tracker, high-risk jobs, and the
balance of payouts (placeholders today).

**Bounties** are about hunting players, and tie into the most-wanted board
(section 2) and the renown and Marked rules already in the PvP world. When a
player gets hot, a bounty goes up on them; whoever takes them down and
extracts gets paid (scrip and upgrade data, amounts TBD).

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

## 13. Open decisions

Caleb's calls, still open:

- Is 15 m/s the right cruise speed? To tune by feel in the playtest.
- Should bots fly?
- The airborne sign-out: 25 seconds and a beacon column, or must you land?
- Which gadgets to build first from the list in section 4.
- Can a heavy weapon from the armory wall be taken into the PvP world, or
  only ones found there in the same outing? (This doc assumes yes, one per
  outing.)
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
