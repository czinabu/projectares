# Project Ares

A full-loot PvPvE war game with plug-in worlds, built in Godot 4. Each world
is a warzone that never ends. Drop in with gear you are willing to lose, fight
and loot for as long as you like, and bank what you find at a depot. Die and
everything you carried stays behind, and you drop back in seconds later.

You start in your home base, which is the menu: the stash is on show, and
you gear up where you stand. Online, the door leads to the Concourse, a
safe plaza shared by everyone on the server, with gates into the raid
worlds, shops, a clan hall and the arena. Three fighting worlds plug in today.
Ashfront is the full-loot war, one open battlefield where two bot armies
fight over the landmarks. Frostline is the gentler co-op world, a frozen
valley: players cannot hurt each other there, and dying drops only your
backpack. The Spore Marsh is co-op too, a drowned basin of fungus forests
where the enemy is wildlife, guns foul and blades shine. You fly a jetpack, thruster boots or glide wings, and you throw
vehicles off your watch: a motorbike, a two-seat hoverbike, a rover, a
mech and a jet. Shops, mastery and crafting are in, and on a server the
contract board pays you for work you sign out with. Online play is an
early dedicated server. It decides every hit, death and pickup, and it
owns your stash.

Gameplay shapes are still mostly built in code. A first art pass dresses
them with real surfaces, skies, animated models and effects (see "How it
looks" below).

## Play it

1. Install [Godot 4.7 or newer](https://godotengine.org/download) (standard build).
2. Open `project.godot` in Godot.
3. Press **F5**.

| Action | Key |
| --- | --- |
| Move / sprint | WASD / Shift |
| Jump. In the air: hold to climb (jetpack); press to kick the way you steer, hold to skim low (thruster boots); press to launch, hold while falling to glide (glide wings) | Space |
| Jetpack: hold right mouse (aim) in the air to hover; let go and you fall. Hovering, cruise with the move keys, Space climbs, C coasts down to cool. Shift in the air boosts: it speeds you up head first into a prone pose, and holding it keeps boosting. The keys fly every rig; the mouse only looks and aims | |
| Air dash with any rig: Shift + a move key dashes that way (Shift alone dashes forward). A jetpack pays heat for it; boots and wings do not. Sideways while boosting it barrel rolls. Gliding, Shift is a wing boost: it thrusts you the way you face and you keep the speed, and Shift + S boosts upward | Shift + WASD |
| Gliding: the wings fly where you look, like a bird. A / D bank round harder, W dives for speed, S pulls up to climb on it. Turns cost speed, and pulling up hard in a turn stalls you. Hold E to free look while the wings fly straight on: the body twists to face where you look, and looking behind flips you onto your back to shoot behind you | |
| Use your ability | G |
| Use your helmet's visor (zoom or scan) | T |
| Dash (stamina) | Left Alt |
| Crouch / stand up (toggle) | C |
| Slide (while sprinting) | C |
| Fire, or melee: tap for the combo, hold for a heavy (dive slam in the air) | Left mouse |
| Aim down sights, or block with the blade (tap just before a hit to parry) | Right mouse |
| Pick a melee side: left, right or overhead | Flick the mouse that way, or hold A, D or W |
| Switch how the melee side is picked (mouse flick or movement keys) | B |
| Switch to primary / sidearm / melee / power weapon | 1 / 2 / 3 / 4, or mouse wheel (watch down) |
| Reload | R |
| Inspect what is in your hand (the weapon, or a toy vehicle): it comes up close and turns. Anything else you do stops it | I |
| Use a medkit | H |
| Melee weapon's ability: the hammer's ground pound, the knife's shadow step, the sword's counter stance, the axe's guard hook, the spear's vault, the hook blade's trip | Q, or the mouse's thumb button |
| Loot, or get on and off a vehicle | F |
| Ride: throttle, brake or reverse, steer, boost | W, S, A / D, Shift |
| Switch camera: first-person or third-person | Tab |
| Scoreboard: who is fighting, who is down, kills | Hold O |
| Sign out and go home with what you carry (10 seconds, out of a fight) | L |
| After dying: drop back in, or go home | Enter, or L |
| Open your phone: players, messages, invites, news, servers, mirror, every control (Keys), settings | P |
| Raise or lower the holographic watch on your wrist | X |
| Move across the watch's icons (watch up) | Mouse wheel |
| Use your artifact (watch up, on the artifact icon) | Click |
| Phone at Settings (also frees the mouse); Esc again closes it | Esc |

The jetpack runs on heat. Overheat it and you fall until it cools to 35. Rooftop caches hold the best loot, and only a flight rig gets
you there. A Mk1 jetpack climbs to a 40 m ceiling, thruster boots to 10 m,
and glide wings to 40 m only by launching from somewhere high. Mk2 and Mk3
are crafted from blueprints. A tier improves what that rig is already good
at, about 15% a step, and never fixes its weakness. They are not one
ladder of height that every rig shares.

Almost nothing is drawn over the screen in a raid: the crosshair, hit marks,
what E will do, and a ring while you are signing out or banking. Everything
else is on your gear. With a helmet on, the visor carries health, armor,
stamina, flight heat and your ability. First person draws them on the
glass; third person draws the same readouts flat. Each gun counts its own
rounds, and the visor repeats the weapon and its ammo, lit when it matters.
A jetpack or a wing pack shows its heat on a screen in its back plate. With
no helmet, the watch card carries the vitals instead.

You wear a holographic watch on your left wrist. Press **X** and it opens
a card of icons in three tabs. Summon is weapons, vehicles and artifacts,
with your pack under it. Status is where you are and your standing.
Mission is the portal, your contract, a squad ping, and sign-out. It comes
up by itself when you go down. War news arrives on your phone.

## Your home base is the menu

The game opens in your home base, not on a menu screen. Everything in your
stash is on show, and the consoles in the room do what the old menu did.
Walk up to one and press **E**: your view moves in to its screen and you
click on the screen itself. **Esc** steps back. Look at a piece of gear and
a tag over it says what it is and what it is worth.

| Console | What it opens |
| --- | --- |
| Locker | Your loadout, slot by slot (or press F on gear on show) |
| Mastery bench | Mastery levels and variant picks |
| Wardrobe | The character customizer |
| Records | Your stash, kills, rank, and how your last life went |
| Trader | The shops: buy and sell |

Every weapon you own hangs on one rack in the **armory**, the alcove off the
left of the room: long guns on its back wall, sidearms on one side and melee
on the other. The locker stands at its way in. The gunsmith bench has its
own workshop corner just inside, on the left, with the fabricator beside it.
It holds one gun at a time: press **F** on it and the view moves in. Scroll
to turn through your guns and click to pick one, then scroll between its
attachment slots, click one, scroll through what you own for it (shown on
the gun as you go) and click to fit it. Right click steps back, **Esc**
leaves. The card behind the gun lists what the fitted kit changes.

You start in a **starter bunker** and the base grows as you spend scrip on
it. What you do not own yet is sealed, with a panel in the room that names
it, what it adds and its price: the armory starts as a nook with a short
rack, the garage has one bay behind a shutter, the firing range's door is
shut, and the mastery bench and records share the trader's and wardrobe's
consoles. Look at a panel and press **E** twice to buy it. Upgrades never
make you stronger and never hold gear: anything that does not fit on show is
still yours at the locker.

To leave for a world, raise your watch (**X**), scroll to the **portal**
icon on the Mission tab, scroll through the worlds and the arena on it and
click. A portal unfolds in front of you and stays open about 15 seconds:
walk through it. Online, in the plaza, your clanmates can walk through a
portal you open too, and you all land at the world's gate outpost. Portals
only open in safe places (your base and the plaza), never in a fight:
coming back still means signing out. Inside a world's gate outpost the
portal icon offers one portal, home: opening it signs you out, the ring
unfolds over the countdown, and squadmates who step into it sign out and
follow.

In your own base you always wear your loadout: equip something and it is on
you at once, and you come home still wearing it. A **mirror** hangs on the
wall by the door so you can see what you are taking out.

Your bikes are parked in the **garage** off the right of the room. Through the
door in the back wall is the **firing range**: your weapons
work past its firing line with endless ammo, targets stand, slide and fly at
set distances, and a board keeps your score. Nothing there is lost or earned.

The door behind you leads straight out to the plaza, online (no screen in
between). Signing out of a
world, or dying and pressing L, brings you back here.

After you pull new code, the first launch may show "Updating the project" for a
few seconds and restart on its own. That is Godot learning about new scripts.

The Windows build is installed once with `ProjectAres-Setup.exe` from the
"latest" release (or the zip, unzipped anywhere you can write to). The installer
puts the game in `%LOCALAPPDATA%\Programs\Project Ares`, where Windows keeps
per-user games, with no admin prompt, adds desktop and Start menu shortcuts, and
lists it in Settings > Apps to uninstall. It keeps itself up to date: at launch it checks for a newer build, downloads it in the
background and restarts into it. The start screen's corner and the phone's
Servers app say which build you run. Only a new Godot version needs a fresh
download. Pass `-- --no-update` to stop it.

## Play online (early test)

Walk out of your home base's **door** and you are in the plaza. The first time,
that starts a server on your computer in the background, running every world,
and joins it; you choose a world at the plaza's gates. It stops when you leave.

Your phone's **Servers** app (press **P**) is for the other cases. It also
holds your player name:

- **Join** connects to someone else's server. On the
  same network, that is the host's local address, for example `192.168.1.20`.
  The door remembers it: from then on it leads to that server, and falls back
  to a server of your own if that one does not answer.
- **Host here and head out** starts a server of your own and points the door back at a server of your own.
- Joining a server puts you in its plaza, the Concourse (see below). On a
  server your own door started you are the same player as at home: you
  arrive in the loadout you left your base with, and what you do there is in
  your base when you come back. **Someone else's server** keeps a stash and
  loadout of its own, separate from yours at home; the Quarters door there
  is your base on that stash, where you pick your gear. Dying keeps you in
  the world: press Enter to drop back in. Signing out (L) brings you back to
  the Concourse (or to the lobby base on a server without one).
- The server knows you by your name plus a private key your game creates the
  first time. Everyone on a server needs a different name. A new name starts
  the way a new solo profile does: nothing equipped, with the welcome crate
  and the free scrap pieces waiting in the base.
- Losing your connection leaves your body standing in the world for 10
  seconds, or 30 if you were in a fight. If nobody kills it, what you carried
  goes back to your stash on that server.
- To try it alone, run two copies of the game. In the Godot editor use
  Debug, Customize Run Instances, and enable two instances. Host in one window
  and join `127.0.0.1` in the other.

### Your phone

Every player carries a phone. Press **P** to open it anywhere: in your base,
the plaza or a raid. While it is out
your character stands still and the mouse is free.

- **People**: everyone signed in to the same server, and where they are (lobby
  or raid). Message them, invite them to the raid or to your home base, save
  them as a contact, or block them. Saved contacts can be messaged while
  offline; they see it at their next sign-in on that server.
- **Servers**: go online. Set your name, host a server on this computer, join
  a friend's by its address, and see where your base's door leads. Online it
  shows which server you are on and has **Leave the server** (from your base or
  the plaza; out in a world, sign out first).
- **Chat**: your conversations. New messages also pop up at the top of the screen.
- **Invites**: accept or decline. A raid invite deploys you into that server's
  raid from the lobby. Invites run out after two minutes.
- **News**: game news, plus anything the server adds. A server operator drops a
  `news.json` (a list of `{"date", "title", "body"}`) in the accounts folder.
- **Keys**: every control, filled in from the keys you actually have bound.
- **Mirror**: change how you look, wherever you are. A tall mirror rises in
  front of you and the phone lists your build, each part (head, torso, legs,
  shoes) and each colour. Scroll through them with the arrows, the mouse wheel
  over a row, or the keys (up and down pick a row, left and right scroll it).
  Only starter clothes and outfits you own are offered: buy more at the
  Tailor. Changes save as you go, and online everyone around you sees the new
  look at once. It works in first person too: the mirror shows your body even
  though your own camera does not.
- **Settings**: mouse sensitivity, invert mouse, melee side control, field of
  view, volume, fullscreen and nameplates. Saved in `user://settings.json`.

Players, chat and invites need a server; news, servers, the mirror, keys and settings work solo too.

A server can also run on its own, with no window:

```
godot --headless --path . -- --server --world ashfront --port 24565
```

That runs the plaza on port 24565 and Ashfront on 24566. Leave out `--world`
to run every raid world, or add `--no-plaza` for one world alone on the port.

### The Concourse

Joining a server puts you in its plaza, the Concourse: an open district on a
high deck around a lit beacon spire, with a balcony over the city below. It is
a safe zone shared by everyone on that server. Weapons are locked and nobody can be hurt.
You appear wearing your equipped loadout, and it never leaves your stash, so
nothing is at risk there. Look at another player and a tag over their head lists what they are wearing.
A bike in your loadout rides on your watch as a toy: throw it down to ride around.

Walk into a glowing pad and press **E** to use it:

- **World gates** (north): each drops you straight into that world in the
  loadout you are wearing. After a run you are back in the Concourse, in
  front of the gate you took (coming back from your base or the arena, in
  front of their doors). A sign over each gate says how that world is doing
  right now: its war level, how many players are in it, the biggest bounty
  on anyone's head and any event running. It reddens as the war heats up.
- **Quarters** (west): the door to your home base. Its door leads back here.
- **Kiosks** (under the arcade ring round the spire): one for every shop. Step up to the counter
  and press F to use its terminal: buy and sell on the screen without leaving
  the plaza.
- **The skyline**: slim towers ring the arcade, each with a landing deck and
  a skybridge to the next at 15 m, in reach of the thruster boots. The arcade
  roof (8 m) and the quarters and clan hall roofs (12 m) are steps on the way
  up. The tower tops are for wings and jetpacks.
- **Clan hall** (east): the terminal by the door founds a clan (a name and
  a short tag), joins one or leaves yours. Clanmates wear the tag by their
  name. In a warzone a clan is one side: you cannot hurt each other, you
  hold strongpoints together, and you can drop in on ground your clan holds.
  You cannot change clans while your gear is in the field.
- **Arena** (south-east): the gate to the arena.
- **Exit** (south): leaves the server.

Add `--accounts <folder>` to choose where the server saves player stashes (an
SQLite database, `accounts.sqlite`, plus the clan and phone records).

To feel what a bad connection is like without leaving your desk, start the
game (not the server) with `-- --lag 120 --loss 10`. That adds 120 ms of delay
each way and drops 10 percent of your input packets. Add `--jitter 60` to make
the server's updates arrive unevenly, up to 60 ms late and then several at
once: other players should still move evenly. Your own movement should
still feel immediate, and so should riding a bike. Shots are lag compensated:
aim straight at what you see and the server checks the hit against where the
target was on your screen. Start a server with `--no-rewind` to feel the
difference.

What works online so far: seeing and fighting other players and bots, looting
caches and bags, riding vehicles, banking at depots, dropping back in after a
death and signing out, with the server deciding every hit, death and pickup.
The server also owns your online stash: your game never tells it what gear
you have.

## What is in the game

- First-person and third-person camera that you switch with Tab. Third person
  is a close view over the shoulder; the phone's settings set how far back it
  sits. It never changes
  on its own. Weapons are visible in your hand in both views.
- Renown. Kills raise it, a streak makes each kill pay more, and dying hands
  a tenth of it to your killer. Your lifetime total never drops and sets your
  rank, which others see on your nameplate. Three player kills in one life put
  a bounty on you, five show you to everyone through walls, and the player
  with the most renown is the Marked, the richest kill in the world. Killing
  someone in the free scrap kit pays almost nothing. Player kills, bounties
  and the Marked are announced to everyone.
- Ashfront is one open battlefield about 600 metres across: scorched ground
  cut by craters and trench lines, strewn with the wrecks of war machines,
  some the size of tower blocks. Five landmarks stand on it (the Foundry in
  the middle, Signal Hill, Rustfall, the Breach and Carrier Grave), each with
  a depot, a garrison and loot, and the best loot sits on roofs and wrecks
  that only a flight rig reaches. You drop in at the rim, where a bike is
  never far, and ride or fly inward.
- Two armies. The Legion holds the west of Ashfront and the Tide the east,
  two landmarks each, with the Foundry between them. Each keeps a garrison
  on what it holds and sends the rest of its soldiers against the nearest
  site it does not, so they meet in the middle and fight each other as well
  as you. Their fighting keeps the war simmering on its own, and the hotter
  the war gets the more reinforcements both sides bring in from their camps
  at the rim, up to twice the usual number: 60 soldiers on a quiet field,
  120 at the height of a war.
- Big battles. An Ashfront server takes 32 players. Soldiers nobody is near
  are simulated in longer steps, and each player is sent every update only
  about what is around them, with the far side of the field a few times a
  second, so a full war fits in a server tick and in a home connection.
- War intensity. Ashfront keeps a meter of how much fighting is going on.
  Kills and hostile players closing on each other raise it, and it cools when
  things calm down; a full server that is not fighting stays quiet. As it
  climbs the sky darkens from a hazy afternoon to a dull red dusk, a column
  of smoke stands over the heaviest fighting, and kills pay up to half as
  much renown again. Frostline stays quiet.
- Strongpoints. Sites marked by a tall beacon that you take by standing in
  them alone for 20 seconds; more of you is faster, and an enemy inside
  freezes it. Taking one pays renown, and a site your side holds is where you
  drop in next. Bots hold them to begin with and push to take them back.
  On Ashfront each of the five landmarks is one: the Legion starts with the
  two in the west, the Tide the two in the east, and the Foundry in the
  middle starts unheld. Frostline has three, shared by all players, held by
  the Wardens to begin with.
- Choosing where you land. When you are down, the death screen lists where
  you can drop back in and a number key picks one: a quiet drop away from
  everyone, a strongpoint your side holds, or, once a battle is on, right
  beside the heaviest fighting. Enter still lets the world pick for you.
- Scrip. Kills, warlords and strongpoints pay scrip that you carry. It joins
  your banked balance, which is safe, only when you bank it at a depot or sign out
  alive. Die with it and it lies in your bag for whoever gets there first.
- World events. Every few minutes, and more often as the war heats up, either
  a supply pod lands with a better haul than any cache, or a warlord marches
  in with an escort. He has three times the health, carries good loot, and
  pays 300 renown. Everyone is told where on the war feed. Caches that refill
  during a war also hold rarer loot.
- Hitscan rifle with reloads and aim down sights.
- Recoil that kicks your view and widens the spread under sustained fire. The
  kick settles back when you pause, so paced shots return to your aim point;
  what you pull down against stays where you put it.
- Blade with a three-hit combo, a heavy lunge, and a dive slam from the air.
- Directional melee. Flick the mouse left, right or up to pick a side. Attacks
  come from that side and a guard only covers the side it was raised on. Read
  the enemy's windup, or the yellow mark by the crosshair, and guard that side.
- Block and parry with the blade. A parry staggers the attacker and powers up
  your next hit. Attacks, blocking and dashing cost stamina.
- Hit markers, damage flashes, and placeholder sounds generated in code.
- Health with a degrading armor layer, medkits, and a dash.
- Flight limited by heat on a jetpack, by charges on the boots, and by glide
  stamina on the wings.
- Bots drop loot bags. On Ashfront each army's soldiers shoot, and a share
  of them are heavies that rush you with a blade. Exo troopers (soldiers in
  mechanical suits) march with them, and toward the core the rare Kiln
  Walker paints you with a tracking beam before its cannon fires; its weak
  spot is the glowing vent on its back. Frostline's Wardens shoot
  and call each other to a fight, the Engine Sentinel guards the hatch,
  and its Feral stalkers rush. Rival raiders drop in with a real kit, loot,
  and sign out.
- Loot caches with five rarity tiers, a backpack, and a stash that persists.
- A home base you walk around in, where the game opens. Everything in your
  stash is on show: every weapon on one rack in the armory, armor on stands,
  flight rigs, ability chips, bikes parked in the garage, loot on shelves.
  Look at a piece of gear and press F to put it on. In your own base it goes
  on at once.
- Loadouts picked in your base from your stash: a primary, a sidearm, a melee
  weapon, a flight rig, an armor frame, a helmet and an artifact. Equipped
  gear is at risk. Sign out alive and it
  comes home, die and it drops. The scrap kit is free: one of each piece
  hangs in your base to equip like any other, costs nothing to lose, and is
  what takes the place of gear you lose. Any slot can be left empty, down to
  going fully bare.
- Three flight rigs, each with one job and one weakness, on the same keys.
  The jetpack is height and hover: a Mk1 climbs to 40 m, cruises at 14 m/s
  and boosts at 18, and a full bar hovers for about 8 seconds. Climbing
  burns 1.5 times the heat and boosting 2.5 times. It aims steadily in the
  air, carries heavy armor without running hotter, and is slow across the
  map. Glide wings are distance and speed: one launch, then a 22 m/s glide
  that dives to 30, on stamina that only refills on the ground, and two
  boosts a flight. They cannot hover or climb on their own, a turn costs
  speed, and only a sidearm fires while they are spread. Thruster boots are
  ground agility and have no heat: four charges pay for kicks and dashes up
  to a 10 m ceiling, a short skim, faster movement on foot, no fall damage,
  and a brief graze window on every dash. Shooting from the air spreads
  wider, except from a hover or a boots dash. Mk2 and Mk3 strengthen what
  that rig is already good at, about 15% a tier. Only Mk1 is found or sold.
- An ability slot. Phase Step blinks you forward, Kinetic Barrier cuts damage
  for a few seconds, Shock Pulse staggers everyone near you. Each has a cooldown.
- Attachments for your primary, in four slots: optic, muzzle, grip and
  magazine. Each one shows on the gun and trades one stat for another: a holo
  reflex sight or 4x and 8x scopes (you look down the scope itself when you
  aim in first person, no overlay), a compensator, booster or suppressor,
  vertical or angled grips, and extended, quick or drum mags. Fit them at the
  gunsmith bench in your base. They ride with the gun, so they are lost with
  it. Basic ones are sold at the Armory; scopes, the suppressor and the drum
  mag are loot only.
- A helmet slot. The visor is your display in first person, and what it
  shows depends on the helmet: the Spotter has binoculars (4x and 8x), a
  compass and a range finder, and fire while zoomed tags a target for your
  side; the Seeker sends a scan pulse that shows where everyone nearby stood.
  The Warden shows where a hit came from, the health of whoever you aim
  at, what nearby loot holds and the way to the nearest depot, and its
  Threat Sense outlines anyone aiming at you for five seconds. The Ember
  switches to thermal sight on a battery: warm bodies stand out through
  smoke and storm, never through walls, and a hot jetpack shines.
  All of them give you away: a zoomed lens glints, a scan is seen, heard and
  felt by everyone it catches, Threat Sense tells whoever it shows, and a
  thermal visor glows up close. With no helmet the view is bare.
  Every working visor has a curved heading strip across the top marking your
  squad, pings and the nearest depot, plus its own finds (Spotter tags, Seeker
  contacts, the Warden's hot zone), and a small tracker for your contract.
  A helmet is worn on your head, each type its own shape, and seen the same
  by everyone. Loot one and put it on mid-raid from the watch's weapon
  carousel, like summoning a weapon (the old one goes in your pack). Armor
  frames work the same way: worn as plates on your body (bigger the heavier
  the frame), put on from the carousel with your old frame going into the
  pack with whatever armor it had left; worn or carried, it drops when you die.
- Six melee weapons, each with its own job. The Gutter Knife is quick and short
  and cuts from behind for more than double. The Splitter Axe drains a guard
  so fast that three chops break it. The Lancer Spear (rooftop loot) has the
  longest reach, pokes fliers overhead, and staggers with a heavy thrust, but
  hits half as hard up close.
- More gear to find: carbine, SMG, marksman rifle, shotgun, arc blade, breaker
  hammer, and armor frames from light to heavy. Better flight rigs are
  crafted, not found.
- Vehicles ride on your watch as toys, never in the pack. The watch holds
  two. Raise it (X), turn the wheel to the vehicle icon and on through the
  toys, and click to take one in your hand, then click again to throw it.
  It grows into the full-size vehicle where it lands (right click puts it
  back). It needs clear ground, or it jumps back to your watch. How long
  the watch waits depends on the vehicle: 12 seconds for the Scrapper bike,
  10 for the Raider hoverbike, 30 for the Warden Rover, 60 for the Bulwark
  Mech and the Kestrel jet. To pack one back, look at one nobody is riding,
  raise the watch and click. Toys on your watch go home when you sign out.
  Press E on any vehicle nobody is riding to take it, including someone
  else's. Sign out riding one and it goes to your stash; die or leave it
  behind and it is gone. The Scrapper is a motorbike (24 m/s, boost 32).
  The Raider is a two-seat hoverbike (26 m/s, boost 35): it drifts through
  turns and holds level over a short gap, and a passenger sits behind you.
  The rover, the mech and the jet are drivable too, still without their
  weapons or their own armor. The rover can be found parked on Ashfront;
  the mech and the jet are crafted. Abandoned bikes wait at the rim, the
  landmarks and the jump ramps of the battlefield. Riding uses the
  third-person camera (Tab still switches), and pressing E in mid-air bails
  out with the vehicle's speed.
- Mastery for every weapon type, ability and armor frame. Using gear earns XP
  for its type, levels unlock variants that trade one strength for another
  (never raw power), and you pick them at the mastery bench in your base. Mastery is kept when you die.
- Worlds that never end. There is no timer and no exit. Dead bots are
  replaced, emptied caches refill, and bikes come back to their parking spots.
- Depots, marked by green beacons. Stand in one for a few seconds to send
  your backpack to your stash without leaving the fight. Healing stays on you.
- Full loot on death, then straight back in. Dying drops everything you carry
  in a bag where you fell. Press Enter to drop in again, away from the
  fighting and protected for a few seconds, with whatever your loadout can
  still supply from the stash, with free scrap in place of what you lost.
- Signing out. Press L, stay out of trouble for 10 seconds, and you go home
  with everything on you. A hit, given or taken, cancels it. Quitting or
  losing your connection online leaves your body standing in the world for
  the same time (30 seconds if you were in a fight), so nobody escapes a
  fight by closing the game.
- Scrip and shops. The trader in your base has five shops: the Armory (weapons and attachments), Outfitter
  (armor, flight rigs, medkits), Garage (bikes), Furnisher (furniture and
  decorations for your home base) and Tailor (clothing). See "Scrip and
  shops" below.

## Scrip and shops

- **Loot is the money.** You earn scrip mostly by selling the loot you get
  home, by banking it at a depot or signing out with it, so nothing is earned
  until it survives. Loot sells for its full value.
- **Kills pay a small bounty**: 10 scrip each, carried like all scrip, so it
  is only yours if you bank it or sign out alive. It is small on purpose, so
  running in with the free scrap kit never beats risking real gear.
- **Banked scrip is safe, gear is not.** Your balance is never lost on death. But
  scrip only becomes power as gear, and bought gear drops like any other.
- **Shops sell base-level gear only** (Common and Uncommon). Rare gear and
  better can only be found.
- **Selling gear back pays 40%** of its value, so trading with a shop can
  never make money.
- A new player starts with 500 scrip. Online, the server keeps your balance
  next to your stash and decides every price; your game only asks.

## The arena

A portal to the arena from your watch (or the arena gate in the plaza) takes you to
the Pit, a colosseum where you watch from the stands. The big board over the
pit shows the bout, both fighters' health and the wager pools. To take part,
walk up to one of the bookmakers' booths in the stands and press **E** (Esc
steps back). Its screen is where you:

- **Bet** on the bout being called. Backers of the winner split the losing
  side's pool by stake, less a 10% house cut. Draws refund every wager.
- **Challenge** another player to a duel, with an optional stake that both of
  you put up and the winner takes. Or **practice** against a bot gladiator.
- **Start or join a tournament.** It costs an entry fee, fills empty slots with
  bot gladiators, and the champion takes the pot.

Nobody loses gear in the arena. You fight with your own loadout (no healing
items or vehicles), a beaten fighter yields at 1 health instead of dying, and
nothing is dropped. Only the two fighters in a bout can hurt each other. When
nothing is queued, bot gladiators put on exhibition bouts for the crowd.

Online, the dedicated server runs the arena on the server port plus 10 (24575 by default, next to the plaza and raid worlds), sharing
the same accounts. The server decides every result and pays every wager.

## How the code is organized

```
core/            Shared by every world. Never names a specific world.
  abilities/     Visor, ability chips, artifacts
  actor/         Actor (the character) and ActorCommand (one tick of intent)
  ai/            Bot brain
  account/       Server-owned stashes, and the shared gear rules
  arena/         The arena venue, its bouts and wagers
  base/          The home base: a room that puts the stash on show
  combat/        Health, damage, guns, melee
  dev/           Temporary dev mode, editor and debug runs only
  economy/       Scrip, shops, contracts
  fx/            Sounds and effects; no-ops on a headless server
  flight/        Flight rigs
  items/         Item database, inventory, loadouts
  interact/      Loot containers
  net/           Online play: the server and client ends of a session
  phone/         The handheld phone and its apps
  player/        Local input and camera
  profile/       Stash and stats that persist between raids (local play)
  progression/   Mastery, crafting, renown, the new-player tour
  raid/          The running world (Raid) and depots
  settings/      Local settings; a server never reads them
  social/        Clans, and presence, contacts and messages on a server
  ui/            HUD, visor glass, station screens and the travel screen
  vehicle/       Rideable vehicles
  visual/        The art layer (`Look`): surfaces, atmosphere, models, effects
  war/           Strongpoints, war intensity, power weapons
  world/         The world contract (WorldDef), portals, terrain, the registry
worlds/
  plaza/         The Concourse: the social safe zone
  ashfront/      The PvP warzone: rules, loot tables, and its map
  frostline/     A smaller PvE world that proves the plug-in contract
  marsh/         The Spore Marsh: a co-op hunt against the wildlife
assets/          Models, textures, sky, font and shaders, with LICENSES.md
tests/           Headless test suite and a screenshot tool
```

Three rules keep the foundation solid:

1. **Worlds are plug-ins.** Core code talks to a world only through `WorldDef`.
2. **Actors are driven only by commands.** The player, bots and remote
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

The models, textures, sky and font in `assets/` are CC0 or OFL. Sources and
licenses are in `assets/LICENSES.md`. Shaders written for this project, and
the rest of the game's own work, are not under those terms (see License).

## Add a world

One command starts it:

```
godot --headless --path . res://tools/new_world/new_world.tscn -- --id ember --name "Ember Reach" --planet basalt
```

It writes `worlds/<id>/world.gd` (planet, rules, an enemy roster as data,
loot tables, zones, contracts), `worlds/<id>/map.gd` (open ground with every
marker the map contract asks for), `tests/<id>_tests.gd`,
`tests/visual/<id>.gd` (`--<id>-only`) and `docs/systems/<id>.md`, adds that
file to CLAUDE.md's index, and prints what is left to do by hand. It never
overwrites anything; `--dry` lists what it would write. Then:

1. In `world.gd`, change the description, roster, loot tables and rules.
2. Items that only exist in your world go in `register_items()`. Prefix their
   ids with the world id. Once stashed they work in every world.
3. Replace the map's greybox with the world's own places, keeping the
   markers listed at the top of `core/world/world_def.gd`. Give it a mood
   with its planet type and surfaces from `Look.surface`.

The watch's portal icon finds it automatically and offers it, and the
"Every world plugs in" tests run a raid in it. No core code changes.

### Frostline

A frozen river valley where the war ended long ago, the co-op expedition
world (DESIGN.md section 2). It runs about 600 m from the river mouth, where
you arrive, through the Narrows and across a frozen lake to the glacier head,
where the Stilled Engine lies half buried: the terraforming drum that once kept
the world warm, with one teal light still blinking over its hatch. Its zones
run up the valley (river mouth, mid-valley, glacier head). Both walls step up
in two tiers: a shelf about 14 m up, reached by ramps, with heater huts and
the three strongpoints, and a rim about 40 m up that only flight reaches, with
old listening posts and the rooftop caches. The richest cache is on the
Engine's back. Two enemy factions share the ice and fight each other as well
as you: Wardens (slow, armored, long-range rifles), who hold the posts, the
rims and the Engine, and Feral stalkers (fast, fragile, melee) denning on the
floor. It is co-op: players cannot hurt each other there. It is also the
gentle one. Dying there only drops your backpack; the gear you deployed with
goes home with you (`WorldDef.keep_gear_on_death`). In return its caches hold
basic gear and materials, and the rare and powerful gear is only found on
Ashfront. Depots take longer to hold. It adds three items of its own: Cryo
Cell, Signal Core and the Ice Axe. It is cold: out in the open your body
heat (a snowflake cell on the visor) drains, faster up the valley and up in
the wind, and once it is gone the cold hurts. Heater huts, the warm vents on
the floor, the camp fire at the river mouth and any running vehicle warm you
again. You see your breath, and a chilled body shivers. It is where the
parts for better gear come from: every Mk2 craft needs a Cryo Core and every
Mk3 Glacial Alloy and an Engine Coil (the coils only on the Engine's back),
and its own blueprints make new options: the Thermal Frame, which keeps out
some of the cold, and the Glacier Grip. You leave the valley only at one
of its four warm beacons: start the sign-out inside a beacon's ring of
light and stay there while it powers up (20 seconds, quicker with others
powering it beside you). The snow keeps a trail: everyone on foot leaves
footprints and every ground vehicle wheel tracks, which fade after a few
minutes, so you can follow someone (or something) across the valley. In
the still, cold air a gunshot carries twice as far, to people and to the
bots alike. The middle of the frozen lake is thin, darker ice: on foot or
on a bike it holds, but a rover or a mech that lingers on it cracks it
(you hear it twice) and goes through, and whoever rode it lands in the
freezing water (your watch pulls the vehicle back out). The Wardens are
the Engine's defence grid, still running: one you hurt and leave standing
calls every Warden within 60 m (a teal ring runs out from its feet with a
chirp), so a clean kill in one blow stays quiet. At the Engine's hatch
stands the grid's boss, the Engine Sentinel: a Warden three metres tall
whose lance holds a teal tracking beam on you before it fires (break the
line to reset it) and whose back takes double damage. It is made for one
player and grows tougher with each other player near it, comes back a
few minutes after it falls, and like any Frostline warlord now and then
carries one of the war's blueprints, as the relay on the Engine's back
rarely does. The contract board has Frostline jobs of its own, one daily
and one weekly, all doable alone (search the relay, break Warden patrols,
bring down the Sentinel), that count only from a life there; the weeklies
pay a blueprint. Whiteouts blow through now and then, mostly down the
valley: sight closes in, the cold bites twice as hard, tracks are wiped and
gunshots die in the wind. Snow is driven past in gusts, spindrift streams
off the rims, everyone leans into it, and flying is a fight. Past the Sentinel the
Engine is hollow: the hatch opens on the Drum Hall, a hall big enough for a
squad to fight across with catwalks up both walls, and in its east end the
Shaft goes 26 m down two wide ramps to the Coil Galleries, a loop of wide
halls with a raised walkway round dead Engine Coils with a channel of bitter coolant down one
side, and on to the Descent, three switchback ramps 40 m down. Wardens stand
guard inside, the caches there pay Engine Coils, no storm or trail gets in,
it gets colder the deeper you go and there is a heater on each level. At the
Descent's foot stand the cable lift (fight off its guards, hold its switch and it runs for
everyone for ten minutes, back up to the hall in seconds) and the open
door to the Heart: a round chamber 68 m across round a frozen core, with a
balcony, four coolant pylons and its keeper, the Heart Warden. It calls
Wardens out of the walls while it is strong; below half health the core
thaws and the pylons vent coolant across the floor (each lane flashes
first). Hit its back. When it falls, everyone who fought it gets a share of
its vault of their own (the best parts, Mk3 materials, upgrade data, maybe
a blueprint, rarely an artifact), the deep beacon lights to sign out by,
and ten minutes later it wakes again.

## Run the tests

```
godot --headless --path . --import
godot --headless --path . res://tests/test_runner.tscn
```

The suite plays real raids without a window: movement, flight, shooting, melee,
looting, banking, death and dropping back in, signing out, respawns, and bot
behavior.

## Host a server online

To run a dedicated server on a cheap cloud machine so friends can join, follow
[docs/hosting.md](docs/hosting.md). It uses the `Dockerfile` and `compose.yaml`
in this folder and the **Linux Server** export preset.

## License

The game's own code and original content are proprietary, all rights reserved.
See [LICENSE](LICENSE). Third-party assets keep the licenses listed in
[assets/LICENSES.md](assets/LICENSES.md).
