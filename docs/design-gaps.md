# Design gaps: what DESIGN.md asks for vs what is built

Checked against `main` on 2026-11-17. Update a row in the same PR that
closes it. "Built" means it is in the code today; "Partly" says what is
missing; "Missing" is not started.

Order of work follows the roadmap in [DESIGN.md](DESIGN.md#12-roadmap):
rows marked **pre-playtest** come before the friends playtest.

## Places

| Item | State | Notes |
| --- | --- | --- |
| Main hub as a safe social space | Built | The Concourse: safe zone, gates, shops, clan hall, arena gate, look tags. |
| Hub vehicles limited to harmless fun | Partly | Bikes can be ridden in the plaza and nobody can be hurt. An abandoned one does not pack itself away: a safe zone returns before `Raid._tick_vehicles`, so a thrown vehicle there is never removed. |
| Watch skins shown off in the hub | Missing | No watch skin items yet. |
| Expand the main hub | Built | Built: an open district about 280 m across on a deck with no wall, a beacon spire, a kiosk arcade, eight towers with landing decks and skybridges at 15 m (boot reach), a gate terrace with spare arches, a bike loop, a big-screen amphitheatre and a clear pad for the RC arena. Sci-fi look: dark glass towers with lit seams, a glass arcade canopy, holo signs over the kiosks, holo-ads and light planters, a tiled floor. Still code-built greybox art; hand-made models can replace it later. |
| Hub spectating screens and bounty board | Partly | Heat signs over the world gates already show war level, players, top bounty and events (`world_status`). Missing: a most-wanted board, arena results, live arena video (later). First hub activity. |
| Hub ring races and time trials, with per-rig and bike leaderboards | Missing | Second hub activity, after the hub is expanded. |
| Hub toy RC arena | Missing | Later; a separate little game. |
| Home base with armory wall, garage, trophies | Built | `core/base`: one armory rack for every weapon (long guns, sidearms, melee) in an alcove with the locker and a gunsmith workshop off it, your loadout always worn (equip puts it on at once), a wall mirror, a garage off the room, trophy shelf, consoles. |
| Heavy weapons stacked on the armory wall | Built | `StashRules.storable` accepts `power`. The `heavy_wall` upgrade (needs the armory alcove) hangs them above the long guns, copies sharing a spot with a count. The base does not put one in your hands; a PvP deploy does. |
| Home base upgrades: a starter bunker that grows, bought with scrip at sealed bulkheads | Partly | `core/base/base_upgrades.gd`: 12 upgrades in five tracks, owned ids kept on the account (`Profile` solo, `StashService` online, server-checked `buy_upgrade`), `BaseLayout.spots` and `HomeBase` follow them, dev mode keeps a full base. The heavy weapon wall is built and can be bought. Missing: the lounge is shown sealed until its room is built; the starter room is not yet smaller than the full one; the gear and trophy halls add spots in the main room, not rooms of their own; prices are placeholders. |
| Base firing range and flight tunnel (target drones, endless heavy-weapon ammo, nothing lost) | Partly | `HomeBase`: a 50 m range (12 m wide) behind the back wall, a clear lobby before the firing line, standing, sliding and flying targets out to 40 m, a score board, endless ammo past the firing line, no damage and no mastery. Before that range is bought, the starter bunker has a small test lane (`HomeBase._build_test_lane`: three plates, not real damage). Banked heavies hang on the wall but are not worn in the base, so the range still has no endless heavy-weapon ammo. Missing: that, and a proper flight tunnel. |
| Squad portals from the watch (replace the launch pad, arena gate and teleporter pad) | Built | `Portal` (`core/world/portal.gd`): the watch's Mission tab opens one where `Portal.choices_for` allows: from the base to any world, the arena or the plaza (`HomeBase.open_portal`); from the plaza to any world, the arena or home (`Raid.open_portal`, server-decided online); out in a world only home, as a sign-out with a door at the sign-out's own time (gate, ground or air), folding away if it is cancelled, and landing in your base online. Open about 15 s for your squad (`Raid.squad_of`, your clan online), landing at the world's "outpost" marker (`Raid.PORTAL_DROP`); squadmates who step into a portal home start their own sign-out. |
| Squad visits: squadmates in your base together | Partly | A phone invite already lets a friend visit your base, but alone and read-only (`base_visit_requested`). Needs shared online base visits first. |
| Trophies and blueprint pedestals from PvE bosses and arena brackets | Partly | A trophy shelf and a Trophy Case furniture item exist; earned trophies need PvE bosses and arena brackets. Later. |
| PvE world: quests, dungeons, bosses | Missing, deferred | Until after the friends playtest. Frostline stands in (no PvP, gentle death, basic loot). |
| Frostline: the valley map (DESIGN.md section 2, "Frostline") | Built | `worlds/frostline/map.gd`: river mouth to glacier head, zones along it, shelf and rim, ramps, heater huts, three strongpoints, the Stilled Engine's outside. |
| Frostline: body heat, heaters and vents | Missing | Planned step 2. |
| Frostline: crafting parts and its own blueprints | Missing | Planned step 3. Mk2 and Mk3 recipes will need a Frostline part. |
| Frostline: warm beacon sign-out | Missing | Planned step 4, through `begin_sign_out`. |
| Frostline: whiteouts, tracks, louder gunshots, thin ice, the defence grid | Missing | Planned steps 5 to 7. Whiteouts wait for the Ashfront weather work. |
| Frostline: inside the Stilled Engine | Missing | Planned with the PvE dungeons. |
| PvP world | Built | Ashfront: armies, strongpoints, war intensity, events, renown, full loot. The war's storm is a distance haze (depth fog, capped so 30–50 m stays readable) with actors, gear and shots kept visible; see DESIGN.md "The war's storm". |
| PvP risk zones and gate outposts | Partly | Ashfront: outer ring, middle and a burning core held by a boss; loot and soldiers by zone; four weapons-locked gate outposts where players arrive, with the entry rules and protection on the way out; the zone named on the watch; the Works, a factory district in the middle ring for close quarters and flight rigs. Missing: more hotspots (volcano, storm core), a drawn watch map, squad regrouping at the gates. |
| New player tour | Partly | `core/progression/onboarding.gd`: on a new player's first spawn a handler messages them on the phone (offline too), one step at a time: put on gear, raise the watch, hit a plate on the test lane, head out to the plaza, take a contract, go to the gentle world, bank at a depot, then a full-loot warning for the PvP world. Each step finishes on the action; the objective is a small line on the watch card and the visor. Settings (System) skips or replays it; dev mode never runs it. Missing: the full-loot world is not actually locked until the tour ends (the warning only), and online the tour lives in the local profile, so it does not follow you to another computer. |
| Heavy weapons only in the PvP world | Built | `power_weapon_rate` is 0 in Frostline and the arena. |
| Arena with loadouts locked in a bout | Built | The Pit: own loadout, no healing or vehicles, nobody loses gear. A 40 m floor with cover for blades, guns and flight (pillars, platforms, rising barriers), fighters' tunnels with doors, a ceiling at 16 m, a ring of screens over the floor, and a navigation mesh for bots. Its own warm sci-fi night look: gunmetal and amber lit edges, red and blue sides, a holographic crowd, stadium floodlight towers and banners. |
| Heavy units in Ashfront: exo troopers and the Kiln Walker in place of the spider walkers | Built | `worlds/ashfront/world.gd` (`EXO_*`, `WALKER_*`, `bot_allowed`): spawn mix by ring, one walker per landmark, the walker's back vent (`Actor.rear_damage_mult`), slow turn and one-second beam lock (`BotBrain.lock_time`), its 3 m body (`Actor.set_stand_height`). Looks: `Look.SKINS` "exo", "walker", "legionary", "tide"; the suit, the walker's own body (`ActorSkin._build_walker`: hull, cannon, vent, legs, on the stock mech's walking skeleton) and the beam in `ActorSkin`. |
| Group fights: bots take turns, use cover and flank | Built | DESIGN.md "Group fights". `BotBrain.attack_slots` by ring (`take_slot`), return fire and point blank skip the queue, waiting bots crouch in cover (`_find_cover`) or flank, slower spotting far off and crouched (`notice_mult`), a raised gun and a bark before the first shot (`ActorSkin._update_bark`). Measured with the duel bench's `--group`. Missing: bots using real map cover marked by level design, grenades to flush a camper, squads that call out a flank. |
| Rival raiders: bots that play like players (drop in geared, loot, fly, sign out, drop a full bag) | Partly | MVP built: `Raid._tick_raiders`, `spawn_raider`, `WorldDef.raider_count` (4 in Ashfront), `raider_kit`; jetpack, boots and wings wearers lift off when stuck, jetpacks hover in gunfights; they aim like seasoned players, heal, reload, swap to the sidearm and the blade; the war feed follows them. Missing: rooftop caches, banking at depots, renown and bounties, picking up bags, flight across the map. |
| World events: supply pods and warlords | Built | `Raid.event`, one at a time, sped up by the war. |
| Supply meteor event (hot crater, contested 20 s core channel, heavy weapon, artifact chance, vehicle blueprint) | Missing | First new event, after the friends playtest. Vehicle blueprints already drop from warlords and supply pods; this event is not one of their sources yet. |
| Sky Leviathan event (airship with weak spots at three heights, drops loot along its path) | Missing | Later. The Kestrel jet is drivable; the event itself is not started, and it still wants the PvE world's boss work. |

## Watch

| Item | State | Notes |
| --- | --- | --- |
| Watch card in three tabs: Summon (weapons, vehicles, artifacts, with the pack's line), Status (map, standing), Mission (contract, ping, sign-out/banking) | Built | `Hud.Wrist.TABS` and `Hud.watch_slots`: a card-sized hologram over the wrist; the mouse wheel steps across the icons tab after tab (`PlayerController.watch_focus`), turning through the weapons, toys and artifacts carried on their icons, and the open one shows its line. Contextual pop-ups only while they matter: the death report and landing choices when down, the rig's cue while flying (where the visor is not showing it), a brief notice. |
| Summon in every world and at home | Built | Jets are thrown in every world (no `open_skies` gate) and summons work in the plaza. At home the carousel lists every weapon and vehicle owned (`HomeBase.watch_weapons`, `watch_vehicles`): vehicles unpack to be ridden in the base (`HomeBase.throw_toy`, `pack_vehicle`), a weapon picked is equipped. |
| Summon carousel: weapons materialize out of the pack | Built | MVP. `Raid.summon` (server only, `NetSession.summon`) swaps a gun or melee weapon from the pack into the hand in place of the one worn in its slot, which goes into the pack with its rounds. Only what is carried, never the stash. `Loadout.summon_time` (heavier is slower; the weapon cannot be used until it is solid) and a watch rest of `Loadout.summon_cooldown`. The weapon digitizes in on the one body (`ActorSkin._update_materialize`), so both views and everyone see it. Storing is the reverse: a click on the weapon in hand (`Raid.store`, `NetSession.store`) dematerializes it back into the pack over `Loadout.store_time`, with its rounds, leaving the slot empty; no watch rest. At home it takes the weapon off the loadout. A helmet or armor frame in the pack goes on from the same carousel (`Raid.swap_worn`); the worn piece goes back in the pack. Its own sound: a rising sweep as a weapon materializes, falling as one is stored (`ActorSkin._update_materialize`, heard by everyone near). Every swap, helmets included, rests the watch; while it rests the face breathes amber, the carousel shows the rest running out, a refused click buzzes and a chime says it is ready. Missing: swapping a flight rig. |
| Standing and pack pages on the watch | Built | Standing opens as "This run" (`Hud.STANDING_PAGES`: at stake, safe, this life) and the pack is an icon on the Summon tab that opens as a list with each item's worth (`Hud.pack_slot`), both drawn as a panel on the card (`Card._draw_panel`). |
| Contract tracker on the watch | Built | On the Mission tab (`Hud.contract_slot`): the job nearest done, with this life's progress on top. |
| Vitals, heat and ammo always in view, off the watch | Built | With a helmet, in either view and everywhere one is worn (the home base too): health, armor, stamina, rig heat and the ability as hex cells along the visor's lower left curve (`VisorHud.vital_cells`). First person draws them on the glass; third person draws the same readouts flat (`VisorHud.flat_shown`). A quiet weapon readout sits bottom right, lit on a reload, a low mag or a switch (`VisorHud.weapon_awake`). Ammo is still on the gun's own counter, and the helmet wears a health strip and system light on the back of the head. A jetpack or wing pack also shows a heat percent on its back screen. With no helmet the watch card carries the vitals as a thin strip. |
| Map and pings page | Built | Squad ping: a click on the ping icon marks where you look for your side (`Raid.ping`, sent only to the pinger's side by `NetSession`, drawn as a column of light by `Hud.ping_mark`). Map: reading the Status tab's Map icon draws a small holographic map beside it (`Hud.map_marks`, `Card._draw_map`): you and where you face, strongpoints (filled where your side holds one, warm while contested), depots, gate outposts, the war's hot zone, the risk zones as faint cells and your side's pings, north up; never other people. Its line still names the world, zone and war level. A click opens it (Caleb's call): a tabletop hologram with the ground's relief rises over the card (`Wrist.show_table`), the wheel turns through the nearest depot, gate outpost, strongpoint, the hot zone, the event and pings (`Hud.map_targets`), and a click sets a waypoint only you see (`Hud.waypoint`). Missing: others seeing the tabletop over your wrist (they see the raised arm). |
| Banking readout on the watch | Built | The Sign out icon carries what this life has sent home through depots: its worth as the icon's number and "home: N items, worth W, S scrip" on its line (`Actor.banked_count`, `banked_value`, `banked_scrip`, set by `Raid._on_actor_banked`, sent to the owner only by `NetSession._banked`). The icon and the crosshair ring show the upload's progress while it runs. |
| Landing choices | Built | Picked on the watch's death report: the wheel moves the pointer (`PlayerController.drop_pick`) and a click drops in there (`click_landing`); number keys and Enter still work. |
| Vehicle carousel (toys) | Built | Pick, throw, unpack, pack back; holds two. The toy digitizes into the hand, is thrown overarm (windup, release, follow-through) and flips once in the air before coming down level to unpack, the same body for everyone (`ActionPose.toy_hand_point`, `Actor.toy_in_hand`). |
| Heavy weapon chamber | Partly | A heavy weapon is scanned into the watch and drawn from its weapon carousel or with key 4; picked on the watch in hand, it goes back into the chamber. A depot or a sign-out banks it. Missing: dropping it inside the bag (a death still leaves it on a rack beside the bag; see Heavy weapons below). |
| Per-rig readouts (stall line, boosts left, dash charges) | Partly | The visor's rig cue (`Hud.rig_text`) shows the wings' airspeed, stall and boosts and the boots' charges and skim, in both views (flat in third person). The jetpack and wing pack also show a heat percent on the back screen. Missing: those cues on the rig itself, and any readout when you hit the ceiling (part of the flight HUD, see Flight). **Pre-playtest.** |
| Sign-out from the watch, with its countdown | Built | A click on the Mission tab's Sign out icon starts a sign-out, and a click while it runs cancels it (`PlayerController.is_on_sign_out`), as the L key does. The icon shows the countdown, and a ring on the crosshair shows the same progress (`Hud.ProgressRing`), and banking too. |
| Loadout swapping from the watch in the PvE world | Missing, deferred | With the PvE world. Today loadouts change only in a lobby or base. |
| Raising the watch with the character's own left arm, first and third person | Built | The left arm lifts the wrist up in front of the eyes along the aim (`WeaponArm.watch_point`, from `ActionPose.watch`, which `ActorCommand.watch_up` drives so others see it too) and the forearm rolls so the watch face, worn on the back of the wrist (`Hud.Wrist.FACE_AXIS`), looks at the eyes (`WeaponArm._face_watch`). A two-handed hold lets the off hand go to the watch. The watch and its card work in the home base too (`BaseHud.wrist`, `Hud.base_watch_slots`). Both views use that one body: first person is the eyes, and the card opens just over the real watch face. DESIGN.md's separate first-person arm was not built; the camera rule forbids a first-person-only copy. |

## Loadout

| Item | State | Notes |
| --- | --- | --- |
| Primary with attachments | Built | Four attachment slots, fitted at the gunsmith bench: one gun on the bench, the wheel turns through guns and each slot's attachments. |
| Sidearm | Built | Key 2, drawn automatically when the primary runs dry. |
| Melee weapon | Built | Six types, directional, block and parry. |
| Melee against guns: dash-strike, back strike, timed bullet deflect, armor-piercing blades, silent kills, one/two-handed classes | Built | `MeleeWeapon` (`dash_range`, `back_strike_mult`, `deflect_window`, `guard_rearm`, `armor_pierce`, the hold tags), `Combat.noise`. Still to come: interiors that favour blades, more gun ammo pressure. |
| Melee bots: heavies, feints, dash-strikes, openings; cut soldiers flinch | Built | DESIGN.md "Melee bots". `BotBrain` (`RING_HEAVY`, `RING_FEINT`, `RING_DASH`, `_start_attack`, `_carry_charge`, `_try_dash_strike`, `melee_flinch`, `blade_backoff`); Ashfront heavies' slower heavy. Measured with the duel bench's `--melee <blade>`. |
| Melee pass on stances and animations | Missing | Caleb asked for it: how the stances read and how each swing, guard and heavy is animated, both views. View work, after the recoil pass. |
| Learnable recoil patterns, bots included | Built | DESIGN.md "Recoil". `Gun.recoil_pattern`, `recoil_for`, `spray_shot`, `recoil_jitter`; `PlayerController._on_gun_fired`; `BotBrain._take_recoil`. Measured with `gun_bench.tscn -- --recoil`. Missing: a pattern readout on the range board, attachments that change a pattern's shape (today they scale its size). |
| Melee magnetic air-lunge | Built | A heavy in the air at an airborne foe within `air_lunge_range` and the aim cone homes on them through its windup; otherwise the dive slam. Ground heavies lunge to striking distance too. |
| Flight rig | Built | Three rigs with their own jobs and weaknesses (next section). |
| Gadget slot | Partly | The `ability` slot exists with Phase Step, Kinetic Barrier and Shock Pulse. The gadget list (DESIGN.md section 4) needs Caleb's pick before more are built. |
| Goggles: helmet-slot visor with no protection, lighter, more fragile glass | Missing | Shows the customizer's face and hair. Needs the weight system for its trade. |
| Weight tiers (light, medium, heavy) from headgear, frame and heavy weapon | Partly | The tier table is not in: nothing computes light, medium or heavy, and the watch and the base locker do not show one. Armor frames already carry `speed_mult` and `heat_mult`, which the tiers would replace. Crouch and slide are in (C toggles a crouch; from a sprint it slides), but nothing shortens or lengthens the slide by weight. |

## Flight (DESIGN.md section 5)

| Item | State | Notes |
| --- | --- | --- |
| Each rig has one job and one weakness, tuned to the Mk1 table (DESIGN.md section 5) | Built | Caleb's balance pass: `ItemDB.JETPACK_MK1`, `BOOTS_MK1`, `WINGS_MK1`, measured by `tests/rig_balance_tests.gd` (hover, heat, glide stamina, cross-map times). Unplaytested. |
| Jetpack cruise and coast loop, hover 1x, climb 1.5x, boost 2.5x heat | Built | `FlightRig.hover_heat_mult`, `climb_heat_mult`, `boost_heat_mult`. |
| Wings: glide stamina, two boosts a flight, stall, barrel roll, sidearm-only while spread, slide landing | Built | `glide_heat` refilled on the ground only, boosts on `max_charges`. Pulses are gone: wings cannot climb on their own. |
| Boots: charges for kicks and dashes, a short skim, +15% ground speed, no fall damage, a graze window on every dash | Built | `max_charges`, `skim_time`, `ground_speed_mult`, `graze_window`. |
| Air aim penalty by rig | Built | `Actor.air_aim` and `FlightRig.flight_aim`: +10% jetpack, none for boots mid-dash, +50% wings. |
| Scan and thermal reach by rig, indoor limits, fall damage | Built | Simple first versions: `Visor.reach_to`, `FlightRig.indoor_mult` with a roof probe (`Actor.roof_reach`), `Actor._hurt_by_fall`. Missing: rig noise for bots to hear (only guns make noise today). |
| Rig tiers Mk1 to Mk3, each about 15% stronger in the rig's strength only | Built | `ItemDB.RIG_STRENGTH`, `_rig_tier`. Ceilings per rig: jetpack 40, 46, 52.9 m; boots 10 m at every tier; wings 40 m (they only reach it by launching off something high). Boots gain a charge a tier instead of 15% of four. Only Mk1 drops; Mk2 and Mk3 are crafted. No readout yet when you reach the ceiling. |
| Flight course in the base: timed climb, gap and sprint | Built | `HomeBase._build_course`, past the far end of the range, with a board of stage times and each rig's best. |
| Ring races with a leaderboard per tier as well as per rig | Missing | With the hub's ring courses. |
| Overheat cuts the rig out until heat is back to 35 | Built | `recover_heat` 35. |
| Flight HUD, first person: heat gauge, rig cue, squad markers and landing warning at the visor edges | Partly | Heat gauge and rig cue (a vitals cell, `VisorHud.vital_cells`) and squad markers on the visor's heading strip (`VisorHud.compass_marks`, clan or all-allied world) are built. Landing warning is missing. **Pre-playtest.** |
| Flight HUD, third person: heat and cue on the pack screen, glowing vents, landing warning pulse | Partly | A heat gauge (a percent, green to red) is drawn in the jetpack and wing-pack screen bays (`Hud._update_heat_display`), seen in third person and by others. The visor's heat, rig cue and squad marks are also drawn flat in third person (`VisorHud.flat_shown`). Missing: the rig cue on the pack (stall, boosts, dash charges), boot pips, vents that brighten with heat, and the landing-warning pulse. |

## Heavy weapons and artifacts

| Item | State | Notes |
| --- | --- | --- |
| Heavy weapons as data, splash through `Combat.deal` | Built | Rail Lance, Helion, Arc Mortar, Storm Cannon. |
| Found at strongpoints, by pods, more as the war heats | Built | `PowerArmory`. Today they sit on swap racks. |
| Scanned into the watch chamber instead of swapped at a rack | Partly | Using the spot where one lies scans it into the chamber (`LootContainer._rack_swap` with `Loadout.set_power(..., draw = false)`); a second swaps, leaving the old one there with its shots. Missing: the spot still looks like a rack. |
| Summon without dropping the primary; auto-return when spent | Built | Drawn from the watch's weapon carousel or key 4, materializing over `Loadout.summon_time` like any summon. While it is out the primary waits in the watch (`Actor.primary_in_watch`) and materializes again when it next comes to hand. A spent one is thrown away, and your own weapon comes back. |
| Banked by depot or sign-out to the armory wall | Built | A depot upload and a finished sign-out put the chambered heavy in the stash (`Depot.bankable`, `Raid._finish_player`). Copies stack on the heavy weapon wall. |
| Deploy with one from the wall (one per outing) | Built | Optional `power` loadout slot. `StashRules.checkout` takes it only when `WorldDef.carries_power_weapons` (Ashfront). Frostline, the arena and safe zones leave it on the wall. It deploys into the chamber, not the hand. |
| Dropped with your bag on death | Partly | A dead player's heavy is left on a rack beside the bag, with the shots it had, and the death counts it as lost. It is not packed into the bag, because a heavy is scanned into a chamber and never sits in a pack. |
| Artifacts: one per outing on the watch, dropped on death in PvP, banked with the pack, taken home on sign-out | Partly | MVP built (`Artifact`, `core/abilities/artifact.gd`): four of the eleven (Time Rewind, Phase Cloak, Overclock Core, Static Bloom), an optional `artifact` loadout slot, used by a click on the watch's artifact icon, shown in the base's artifact case. Until PvE dungeons and arena tournaments exist they drop from world events (`WorldDef.warlord_artifact_chance`, `pod_artifact_chance`; off in Frostline). Missing: the other seven, attuning one found mid-outing, their own art and sounds. |
| Gravity Well gadget | Missing | A normal gadget, not an artifact. |

## Banking and leaving

| Item | State | Notes |
| --- | --- | --- |
| Bank spots with a short upload | Built | Depots: 4 s in Ashfront, 6 s in Frostline. Bank pack, scrip and the chambered heavy. |
| Depots bank the chambered heavy weapon | Built | `Depot.bankable` includes the chamber. The upload takes it off the actor and into the stash. You keep playing. |
| Sign-out anywhere | Built | 15 s on the ground (`WorldDef.sign_out_time`); a hit cancels it. A gate outpost stays at `outpost_sign_out_time` (3 s). |
| 15 s on the ground | Built | `WorldDef.sign_out_time` is 15. The plaza keeps its 1 s sign-out. |
| Longer sign-out in the air, with a visible beacon column | Built | 25 s in the air (`sign_out_air_time`). Progress is kept when you land or lift off, so the seconds left follow the rate you are on. The server raises a column on the actor (`sign_out_beacon`, state bit `STATE_SIGN_OUT_BEACON`) with a sound bots hear. A disconnect and a gate sign-out do not. A cloak pauses the countdown and does not hide the column. |

## Vehicles

| Item | State | Notes |
| --- | --- | --- |
| Motorbikes on the watch, no heat cost | Built | Scrapper motorbike 22 m/s (boost 29). The Raider is now a two-seat hoverbike: 26 m/s (boost 35), drifts in turns, holds level over gaps for 0.45 s, hugs the ground off ramps, no slopes over 30 degrees, slower two up (DESIGN.md section 8). |
| Clearly faster than flight | Partly | The Scrapper (22 m/s, boost 29) and the Raider hoverbike (26, boost 35) beat the jetpack's 14 m/s cruise, but the jetpack boost (18), the wing glide (22) and dive (30) match or beat the Scrapper, and the dive matches the hoverbike's cruise. The Kestrel jet (45, boost 60) is clearly faster; this row is the bikes. Check on real terrain. **Pre-playtest.** |
| Throw a toy from mid-air onto the road below | Partly | Throwing works off the ground in code; not checked as a planned move (throw, fall, land on the bike). |
| Eject upward off a speeding bike into flight | Partly | Getting off in mid-air keeps the bike's speed and the rig takes over; there is no upward eject. |
| Passenger seats | Partly | The Raider hoverbike has a pillion seat (`passenger_seat`): a second player sits behind the rider, can shoot, and gets off with F; online the server decides who sits there. Missing: the Scrapper's rear seat and the rover's four. |
| Mounted firepower | Missing | Rover turret, mech cannons, jet missiles. After the playtest. |
| Cargo space while riding | Missing | After the playtest. |
| Mobile cover | Missing | Rover and mech; the bike gives none by design. |
| Per-vehicle watch recharge (heavier is slower) | Built | `Raid.toy_recharge` reads the item's `watch_recharge`, or `toy_cooldown` (12 s) when it has none. Scrapper 12 s, Raider hoverbike 10 s, Warden Rover 30 s, Bulwark Mech 60 s, Kestrel Jet 60 s. |
| Rover, mech and jet | Partly | Drivable first versions on the one `Vehicle` class: Warden Rover (23 m/s, slow to turn, driver's seat on the left), Bulwark Mech (9 m/s, turns on the spot, jump-jet hop) and Kestrel Jet (takes off past 24 m/s, cannot hover, 120 m ceiling, thrown in any world). Greybox models. Missing: their weapons, passengers, armor and weak spots, vehicle health, The rover can be found parked at Ashfront's strongpoints (parked vehicles are tiered by risk: Scrappers at the rim and camps, a chance of a Raider by the ramps, the best odds at strongpoints, which refill slower); the mech and the jet are built at the fabricator from their blueprints, which warlords and supply pods carry. |

## Racing

| Item | State | Notes |
| --- | --- | --- |
| Race world with a Street circuit and time trials | Built | Meridian (`worlds/meridian`), run by `Race` (`core/race/`): the Coilrun circuit, pit bays of stock Scrapper and Raider machines on race profiles, a grid with five lights, checkpoint arches with splits, a lap that leaves the track not counted, a reset out of the Spillway channel, the pit board, best-lap ghosts saved per machine, the race icon on the watch and the lap on the visor. Solo and online. |
| Time-trial bench (3% class rule) | Built | `tests/race_bench.tscn`; Street is Scrapper +1.05%, Raider −1.05% of the class average on Coilrun. |
| Live races: several racers on one grid, positions on the watch | Missing | Next step for the race world. |
| Ranked races with scrip and cosmetic rewards | Missing | Stock machines only. With live races. |
| Rough ground that slows wheels (the Capacitor Yard's inside line) | Missing | The rubble there is only scattered dressing for now. |
| More race classes (rovers, mechs) and more tracks | Missing | |
| Racing mode: mixed bike-and-flight races, sky ring races, our own hazards and secrets | Missing | A later mode, after the friends playtest (DESIGN.md section 9). |

## Economy

| Item | State | Notes |
| --- | --- | --- |
| One everyday currency named scrip | Built | The banked balance and the scrip you carry are both scrip (`Economy`, `Profile.scrip`). Old saves with a "credits" field still load. |
| Hub cosmetics for scrip: skins, thruster trail colours, watch faces | Partly | The Tailor sells clothing; trail colours and watch faces are missing. |
| Blueprints and tech cores, earned through risk, dropped on PvP death until banked | Partly | Blueprints are items tagged `blueprint`, at stake until home, then learned onto the account (`Crafting.learn`, `Profile.blueprints`, the account's online). Vehicle blueprints build the mech and the jet. Missing: tech cores, and the meteor, PvE dungeons and arena as sources. |
| Mk1 blueprints for weapons and rigs as PvP drops, kept for good once extracted | Partly | Three rig blueprints and two gun blueprints in Ashfront's rooftop caches, and any blueprint from a warlord or supply pod. Missing: blueprints for the other weapons and for helmets. |
| Upgrade data from hot zones, elites, players, contracts and bounties, kept only on extract | Partly | The item `upgrade_data`: rooftop caches, warlords and supply pods in Ashfront, and whatever a killed player carried. Missing: contracts and bounties as sources. |
| Crafting Mk2 and Mk3 at the gunsmith bench, with a mastery gate on Mk2 | Partly | `core/progression/crafting.gd` and the fabricator console on the bench (`HomeBase.CraftConsole`, `craft_panel.gd`), server-checked online (`StashService.craft`). Mk2 and Mk3 rigs, two guns at base level, the mech and the jet. Costs had a first balance pass (DESIGN.md section 10) and are still unplaytested. Missing: the mastery gate, Mk2 and Mk3 weapons, Mk2 helmets, salvage on loss. |
| All drops base level (Mk1), better loot in the PvP world | Partly | Shops already sell only base level, and no loot table lists a rig or helmet above Mk1 (`tests/rig_tier_tests.gd` checks every world's tables). Mk2 and Mk3 rigs are crafted; Mk2 helmets still have no source. |
| Mastery unlocks attachments and mods | Partly | Mastery unlocks sidegrade variants today; attachments and fire modes as unlocks are missing. |
| Contracts: daily, weekly and rare high-risk, from a board in the hub, tracked on the watch and visor, counted on extract | Partly | Built: the board beside the big screen (3 dailies and a weekly by date, hold 3, one reroll a day), counters from `Raid._count` and what came home, counted only on a sign-out, paid at once (scrip, upgrade data, a weekly blueprint once they exist), a contract icon on the watch. The visor's objective block top right lists every job held, nearest done first, with progress bars (`VisorHud.objective_lines`). Missing: high-risk jobs, per-world and per-rig jobs, contracts in solo runs, tuned payouts. |
| Bounties on hot players, paid on extract, tied to the most-wanted board | Partly | Renown, bounties and the Marked exist in the PvP world; payouts in upgrade data and the board are missing. |
| Safety nets: free Mk1 kit, one insured item, salvage on loss | Partly | The free `starter` scrap kit exists. Insurance and salvage are missing. |
| Prestige vehicles and rigs from hard feats | Missing | List TBD. |
| Two worlds, one loop: Frostline as the source of parts and blueprints, Ashfront for upgrade data and rare gear | Missing | Proposed in DESIGN.md section 10. Table moves go through the Frostline world thread. |
| Player marketplace (plaza kiosk, server-side, fees, price bands, daily cap) | Partly | The Exchange booth in the plaza (`core/economy/market.gd`, `market_service.gd`, `market_panel.gd`): list, buy one, take down, expiry, fees, price band, daily cap, server-decided and shared by a server's worlds. Missing: buying several at once, search, price history, the shared account service across official servers. |
| Weapon Mk gains (handling only, about +10% at Mk3) | Missing | Lands after the combat balance work. |
| Expedition standing and a profile page (no player level) | Missing | A read-out beside renown rank and mastery. |
| World-tagged contracts (expedition and warzone) | Missing | After Frostline's sites exist. |

## Online and servers (DESIGN.md section 14)

| Item | State | Notes |
| --- | --- | --- |
| Authoritative server, input-only clients, prediction, lag compensation | Built | `NetSession`, `ActorCommand.apply_array` clamps every input. |
| Sign-in and version check before a player gets in | Built | `SceneMultiplayer.auth_callback` (`NetSession._server_auth`): an old game or a wrong secret never connects, and both sides name the version, so an older game gets the update button in the phone's Servers app. |
| Hardening: relay off, request limits, safe saves, backups | Built | `server_relay` off; `NetSession.RequestLimits` on every request call (a flood is dropped); every save goes through `SafeFile`; rolling backups at start and hourly (`StashService.backup_if_due`, docs/hosting.md "Backups"). |
| Reconnect to your body after a drop | Built | The game retries on its own for 30 s (`Main._on_online_disconnected`); a sign-in to the account finds the body still standing and the server puts the player back in it (`NetSession._back`, `Raid.reclaim_player`), with no deploy. A sign-out started before the drop carries on. Too late, the game says how that life ended. |
| Whole-server bench and health log | Missing | `battle_bench` measures one world; nothing measures the plaza, worlds and arena together. **pre-playtest** |
| Encrypted connections | Built | ENet DTLS on every connection (`NetSession.host`/`join`, `core/net/server_trust.gd`). Each server makes its own certificate on first start (`server_identity/` beside the accounts) and a game remembers it per address the first time it joins; a different one later is "This server changed" on the phone's Servers app, with both codes and a choice to trust it. Your own computer's server is encrypted but never pinned. `ServerTrust.OFFICIAL_HOSTS` (empty) is where official servers with real certificates go, never warned about. A game from before encryption cannot reach a new server at all (it reports no answer); a new game finds an old server over an unencrypted fallback that sends no secret and says it is out of date. |
| Accounts on SQLite with all-or-nothing changes | Built | `AccountStore` keeps accounts in `accounts.sqlite` (godot-sqlite, `addons/godot-sqlite`), one transaction per save; `StashService.transaction` runs the market's ledger calls as one all-or-nothing change. Old account files are imported once and renamed `.json.imported`. Builds without the library (only Windows, macOS and Linux x86_64 ship one) fall back to JSON files. |
| Account service as its own program | Missing | `StashService`, `SocialService` and `ClanService` live in the server's memory, shared by sessions in one process. |
| One program per world, routes with an address | Partly | `--world` runs one world alone, but routes carry only a port and world status is gathered in memory (`NetSession._gather_status`). |
| Official versus friends' servers | Missing | Every server keeps its own accounts; your own server takes on your solo profile. |
| Steam login | Missing | Name plus a secret the game makes. |
| Matchmaker, plaza shards, hiding unseen enemies | Missing | Later, when numbers call for it. |
| Official servers before Steam: recovery code, one-time Steam link | Missing | Accounts are tied to the computer whose game made the secret. |
| Smooth travel: auto-reconnect, official servers by default, account shown, no full-world dead end, update link on a version mismatch | Partly | Auto-reconnect and the update link on a version mismatch (the phone's Servers app) are built; the rest is missing. See DESIGN.md section 14, "Smooth for the player". |
