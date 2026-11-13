# Design gaps: what DESIGN.md asks for vs what is built

Checked against `main` on 2026-11-12. Update a row in the same PR that
closes it. "Built" means it is in the code today; "Partly" says what is
missing; "Missing" is not started.

Order of work follows the roadmap in [DESIGN.md](DESIGN.md#12-roadmap):
rows marked **pre-playtest** come before the friends playtest.

## Places

| Item | State | Notes |
| --- | --- | --- |
| Main hub as a safe social space | Built | The Concourse: safe zone, gates, shops, clan hall, arena gate, look tags. |
| Hub vehicles limited to harmless fun | Partly | Bikes can be ridden in the plaza and nobody can be hurt. Not checked: whether parked bikes pack themselves away so the hub stays clear. |
| Watch skins shown off in the hub | Missing | No watch skin items yet. |
| Expand the main hub | Built | Built: an open district about 280 m across on a deck with no wall, a beacon spire, a kiosk arcade, eight towers with landing decks and skybridges at 15 m (boot reach), a gate terrace with spare arches, a bike loop, a big-screen amphitheatre and a clear pad for the RC arena. Sci-fi look: dark glass towers with lit seams, a glass arcade canopy, holo signs over the kiosks, holo-ads and light planters, a tiled floor. Still code-built greybox art; hand-made models can replace it later. |
| Hub spectating screens and bounty board | Partly | Heat signs over the world gates already show war level, players, top bounty and events (`world_status`). Missing: a most-wanted board, arena results, live arena video (later). First hub activity. |
| Hub ring races and time trials, with per-rig and bike leaderboards | Missing | Second hub activity, after the hub is expanded. |
| Hub toy RC arena | Missing | Later; a separate little game. |
| Home base with armory wall, garage, trophies | Built | `core/base`: one armory rack for every weapon (long guns, sidearms, melee) in an alcove with the locker and a gunsmith workshop off it, your loadout always worn (equip puts it on at once), a wall mirror, a garage off the room, trophy shelf, consoles. |
| Heavy weapons stacked on the armory wall | Missing | Power weapons cannot be stored (`StashRules.storable` refuses the `power` tag). **Pre-playtest**, with the heavy chamber. |
| Home base upgrades: a starter bunker that grows, bought with scrip at sealed bulkheads | Partly | `core/base/base_upgrades.gd`: 12 upgrades in five tracks, owned ids kept on the account (`Profile` solo, `StashService` online, server-checked `buy_upgrade`), `BaseLayout.spots` and `HomeBase` follow them, dev mode keeps a full base. Missing: the heavy weapon wall and lounge are shown sealed until their rooms are built; the starter room is not yet smaller than the full one; the gear and trophy halls add spots in the main room, not rooms of their own; prices are placeholders. |
| Base firing range and flight tunnel (target drones, endless heavy-weapon ammo, nothing lost) | Partly | `HomeBase`: a 50 m range (12 m wide) behind the back wall, a clear lobby before the firing line, standing, sliding and flying targets out to 40 m, a score board, endless ammo past the firing line, no damage and no mastery. Missing: heavy weapons (they never reach the base yet) and a proper flight tunnel. |
| Squad portals from the watch (replace the launch pad, arena gate and teleporter pad) | Built | `Portal` (`core/world/portal.gd`): the watch's Mission tab opens one to any world or the arena, in the base (`HomeBase.open_portal`) and the plaza (`Raid.open_portal`, server-decided online), open about 15 s for your squad (`Raid.squad_of`, your clan online), landing at the world's "outpost" marker (`Raid.PORTAL_DROP`). Missing: opening one at a gate outpost (needs a rule for leaving that still counts as a sign-out). |
| Squad visits: squadmates in your base together | Partly | A phone invite already lets a friend visit your base, but alone and read-only (`base_visit_requested`). Needs shared online base visits first. |
| Trophies and blueprint pedestals from PvE bosses and arena brackets | Partly | A trophy shelf and a Trophy Case furniture item exist; earned trophies need PvE bosses and arena brackets. Later. |
| PvE world: quests, dungeons, bosses | Missing, deferred | Until after the friends playtest. Frostline stands in (no PvP, gentle death, basic loot). |
| PvP world | Built | Ashfront: armies, strongpoints, war intensity, events, renown, full loot. |
| PvP risk zones and gate outposts | Partly | Ashfront: outer ring, middle and a burning core held by a boss; loot and soldiers by zone; four weapons-locked gate outposts where players arrive, with the entry rules and protection on the way out; the zone named on the watch. Missing: more hotspots (volcano, storm core), a drawn watch map, squad regrouping at the gates. |
| Heavy weapons only in the PvP world | Built | `power_weapon_rate` is 0 in Frostline and the arena. |
| Arena with loadouts locked in a bout | Built | The Pit: own loadout, no healing or vehicles, nobody loses gear. A 40 m floor with cover for blades, guns and flight (pillars, platforms, rising barriers), fighters' tunnels with doors, a ceiling at 16 m, a ring of screens over the floor, and a navigation mesh for bots. Its own warm sci-fi night look: gunmetal and amber lit edges, red and blue sides, a holographic crowd, stadium floodlight towers and banners. |
| World events: supply pods and warlords | Built | `Raid.event`, one at a time, sped up by the war. |
| Supply meteor event (hot crater, contested 20 s core channel, heavy weapon, artifact chance, vehicle blueprint) | Missing | First new event, after the friends playtest. Vehicle blueprints are new too. |
| Sky Leviathan event (airship with weak spots at three heights, drops loot along its path) | Missing | Later: needs the jet and the PvE world's boss work. |

## Watch

| Item | State | Notes |
| --- | --- | --- |
| Watch card in three tabs: Summon (weapons, vehicles, artifacts, with the pack's line), Status (map, standing), Mission (contract, ping, sign-out/banking) | Built | `Hud.Wrist.TABS` and `Hud.watch_slots`: a card-sized hologram over the wrist; the mouse wheel steps across the icons tab after tab (`PlayerController.watch_focus`), turning through the weapons, toys and artifacts carried on their icons, and the open one shows its line. Contextual pop-ups only while they matter: the death report and landing choices when down, the rig's cue while flying (where the visor is not showing it), a brief notice. |
| Summon in every world and at home | Built | Jets are thrown in every world (no `open_skies` gate) and summons work in the plaza. At home the carousel lists every weapon and vehicle owned (`HomeBase.watch_weapons`, `watch_vehicles`): vehicles unpack to be ridden in the base (`HomeBase.throw_toy`, `pack_vehicle`), a weapon picked is equipped. |
| Summon carousel: weapons materialize out of the pack | Built | MVP. `Raid.summon` (server only, `NetSession.summon`) swaps a gun or melee weapon from the pack into the hand in place of the one worn in its slot, which goes into the pack with its rounds. Only what is carried, never the stash. `Loadout.summon_time` (heavier is slower; the weapon cannot be used until it is solid) and a watch rest of `Loadout.summon_cooldown`. The weapon digitizes in on the one body (`ActorSkin._update_materialize`), so both views and everyone see it. Missing: its own sound, armor or rig swaps. |
| Contract tracker on the watch | Built | On the Mission tab (`Hud.contract_slot`): the job nearest done, with this life's progress on top. |
| Vitals, heat and ammo always in view, off the watch | Built | First person with a helmet: health, armor and stamina arcs, heat gauge and the ability's state at the visor edges (`VisorHud._draw_vitals`, `_draw_heat`). Ammo is on the gun's counter. With no helmet, or in third person, the watch card carries the vitals as a thin strip. |
| Map and pings page | Partly | Squad ping built: a click on the ping icon marks where you look for your side (`Raid.ping`, sent only to the pinger's side by `NetSession`, drawn as a column of light by `Hud.ping_mark`). The map is still a line of text on the Status tab. |
| Banking readout on the watch | Missing | Banking happens at depots; the watch should show what is banked. Comes with banking. |
| Landing choices | Built | |
| Vehicle carousel (toys) | Built | Pick, throw, unpack, pack back; holds two. |
| Heavy weapon chamber | Partly | A heavy weapon is scanned into the watch and summoned from its weapon carousel; key 4 is gone. Missing: banking it and dropping it in the bag (see Heavy weapons below). |
| Per-rig readouts (stall line, boosts left, dash charges) | Partly | The visor's rig cue (`Hud.rig_text`) shows the wings' airspeed, stall and boosts and the boots' charges and skim. Missing on the rig itself (part of the flight HUD, see Flight). **Pre-playtest.** |
| Sign-out from the watch, with its countdown | Partly | Sign-out exists on L; not on the watch. |
| Loadout swapping from the watch in the PvE world | Missing, deferred | With the PvE world. Today loadouts change only in a lobby or base. |
| Raising the watch with the character's own left arm, first and third person | Partly | The left arm lifts the wrist up in front of the eyes along the aim (`WeaponArm.watch_point`, from `ActionPose.watch`, which `ActorCommand.watch_up` drives so others see it too) and the forearm rolls so the watch face, worn on the back of the wrist (`Hud.Wrist.FACE_AXIS`), looks at the eyes (`WeaponArm._face_watch`). The watch and its card work in the home base too (`BaseHud.wrist`, `Hud.base_watch_slots`). First person is the same body seen from the eyes, and the card opens just over the real watch face there. |

## Loadout

| Item | State | Notes |
| --- | --- | --- |
| Primary with attachments | Built | Four attachment slots, fitted at the gunsmith bench: one gun on the bench, the wheel turns through guns and each slot's attachments. |
| Sidearm | Built | Key 2, drawn automatically when the primary runs dry. |
| Melee weapon | Built | Six types, directional, block and parry. |
| Melee against guns: dash-strike, back strike, timed bullet deflect, armor-piercing blades, silent kills, one/two-handed classes | Built | `MeleeWeapon` (`dash_range`, `back_strike_mult`, `deflect_window`, `guard_rearm`, `armor_pierce`, the hold tags), `Combat.noise`. Still to come: interiors that favour blades, more gun ammo pressure, bots using the dash-strike. |
| Melee magnetic air-lunge | Built | A heavy in the air at an airborne foe within `air_lunge_range` and the aim cone homes on them through its windup; otherwise the dive slam. Ground heavies lunge to striking distance too. |
| Flight rig | Built | Three rigs with their own jobs and weaknesses (next section). |
| Gadget slot | Partly | The `ability` slot exists with Phase Step, Kinetic Barrier and Shock Pulse. The gadget list (DESIGN.md section 4) needs Caleb's pick before more are built. |
| Goggles: helmet-slot visor with no protection, lighter, more fragile glass | Missing | Shows the customizer's face and hair. Needs the weight system for its trade. |
| Weight tiers (light, medium, heavy) from headgear, frame and heavy weapon | Partly | Changes acceleration, turning, flight heat and a little ground speed, never top flight speed. Shown on the watch and the base locker. Partly there already: armor frames carry `speed_mult` and `heat_mult` stats, which the tiers would replace. |

## Flight (DESIGN.md section 5)

| Item | State | Notes |
| --- | --- | --- |
| Each rig has one job and one weakness, tuned to the Mk1 table (DESIGN.md section 5) | Built | Caleb's balance pass: `ItemDB.JETPACK_MK1`, `BOOTS_MK1`, `WINGS_MK1`, measured by `tests/rig_balance_tests.gd` (hover, heat, glide stamina, cross-map times). Unplaytested. |
| Jetpack cruise and coast loop, hover 1x, climb 1.5x, boost 2.5x heat | Built | `FlightRig.hover_heat_mult`, `climb_heat_mult`, `boost_heat_mult`. |
| Wings: glide stamina, two boosts a flight, stall, barrel roll, sidearm-only while spread, slide landing | Built | `glide_heat` refilled on the ground only, boosts on `max_charges`. Pulses are gone: wings cannot climb on their own. |
| Boots: charges for kicks and dashes, a short skim, +15% ground speed, no fall damage, a graze window on every dash | Built | `max_charges`, `skim_time`, `ground_speed_mult`, `graze_window`. |
| Air aim penalty by rig | Built | `Actor.air_aim` and `FlightRig.flight_aim`: +10% jetpack, none for boots mid-dash, +50% wings. |
| Scan and thermal reach by rig, indoor limits, fall damage | Built | Simple first versions: `Visor.reach_to`, `FlightRig.indoor_mult` with a roof probe (`Actor.roof_reach`), `Actor._hurt_by_fall`. Missing: rig noise for bots to hear (only guns make noise today). |
| Rig tiers Mk1 to Mk3, each about 15% stronger in the rig's strength only | Built | `ItemDB.RIG_STRENGTH`, `_rig_tier`. Ceilings per rig: jetpack 40, 46, 53 m; boots 10 m; wings 40 m (they only reach it by launching off something high). Only Mk1 drops; Mk2 and Mk3 are crafted. No readout yet when you reach the ceiling. |
| Flight course in the base: timed climb, gap and sprint | Built | `HomeBase._build_course`, past the far end of the range, with a board of stage times and each rig's best. |
| Ring races with a leaderboard per tier as well as per rig | Missing | With the hub's ring courses. |
| Overheat cuts the rig out until heat is back to 35 | Built | `recover_heat` 35. |
| Flight HUD, first person: heat gauge, rig cue, squad markers and landing warning at the visor edges | Partly | Heat gauge, rig cue (`VisorHud._draw_heat`) and squad markers on the visor's heading strip (`VisorHud.compass_marks`, clan or all-allied world) built; landing warning missing. | New in DESIGN.md section 5. Extends `VisorHud`; the squad markers use the clan or team side. **Pre-playtest**, with the rig rework. |
| Flight HUD, third person: heat and cue on the pack screen, glowing vents, landing warning pulse | Missing | The pack already carries a screen (`ActorSkin.stow_place` keeps it clear); vents are new rig art. With the row above. |

## Heavy weapons and artifacts

| Item | State | Notes |
| --- | --- | --- |
| Heavy weapons as data, splash through `Combat.deal` | Built | Rail Lance, Helion, Arc Mortar, Storm Cannon. |
| Found at strongpoints, by pods, more as the war heats | Built | `PowerArmory`. Today they sit on swap racks. |
| Scanned into the watch chamber instead of swapped at a rack | Partly | Using the spot where one lies scans it into the chamber (`LootContainer._rack_swap` with `Loadout.set_power(..., draw = false)`); a second swaps, leaving the old one there with its shots. Missing: the spot still looks like a rack. |
| Summon without dropping the primary; auto-return when spent | Built | Drawn only from the watch's weapon carousel (no key 4), materializing over `Loadout.summon_time` like any summon; the primary is kept, and a spent one is thrown away with your own weapon back in hand. |
| Banked by depot or sign-out to the armory wall | Missing | Needs `StashRules.storable` to accept `power`, and the `CLAUDE.md` power weapon rule rewritten. **Pre-playtest.** |
| Deploy with one from the wall (one per outing) | Missing | **Pre-playtest.** Open decision in DESIGN.md section 13. |
| Dropped with your bag on death | Partly | Today a dead player's power weapon is left on a rack. |
| Artifacts: one per outing on the watch, dropped on death in PvP, banked with the pack, taken home on sign-out | Partly | MVP built (`Artifact`, `core/abilities/artifact.gd`): four of the eleven (Time Rewind, Phase Cloak, Overclock Core, Static Bloom), an optional `artifact` loadout slot, used by a click on the watch's artifact icon, shown in the base's artifact case. Until PvE dungeons and arena tournaments exist they drop from world events (`WorldDef.warlord_artifact_chance`, `pod_artifact_chance`; off in Frostline). Missing: the other seven, attuning one found mid-outing, their own art and sounds. |
| Gravity Well gadget | Missing | A normal gadget, not an artifact. |

## Banking and leaving

| Item | State | Notes |
| --- | --- | --- |
| Bank spots with a short upload | Built | Depots: 4 s in Ashfront, 6 s in Frostline. Bank pack and scrip. |
| Depots bank the chambered heavy weapon | Missing | With the chamber. |
| Sign-out anywhere | Built | 10 s today (`WorldDef.sign_out_time`); a hit cancels it. |
| 15 s on the ground | Missing | A tuning change. **Pre-playtest.** |
| Longer sign-out in the air, with a visible beacon column | Missing | **Pre-playtest.** Open decision on the exact rule. |

## Vehicles

| Item | State | Notes |
| --- | --- | --- |
| Motorbikes on the watch, no heat cost | Built | Scrapper 22 m/s (boost 29), Raider 27 m/s (boost 37). |
| Clearly faster than flight | Partly | On paper both bikes beat the jetpack's 14 m/s cruise, but the jetpack boost (18), the wing glide (22) and dive (30) match or beat the Scrapper. Tune after the rig rework, and check on real terrain. **Pre-playtest.** |
| Throw a toy from mid-air onto the road below | Partly | Throwing works off the ground in code; not checked as a planned move (throw, fall, land on the bike). |
| Eject upward off a speeding bike into flight | Partly | Getting off in mid-air keeps the bike's speed and the rig takes over; there is no upward eject. |
| Passenger seats | Missing | Bike rear seat, rover's four. After the playtest. |
| Mounted firepower | Missing | Rover turret, mech cannons, jet missiles. After the playtest. |
| Cargo space while riding | Missing | After the playtest. |
| Mobile cover | Missing | Rover and mech; the bike gives none by design. |
| Per-vehicle watch recharge (heavier is slower) | Built | A `watch_recharge` stat (`Raid.toy_recharge`): bike 8 s, rover 20 s, jet 40 s, mech 45 s. |
| Rover, mech and jet | Partly | Drivable first versions on the one `Vehicle` class: Warden Rover (23 m/s, slow to turn, driver's seat on the left), Bulwark Mech (9 m/s, turns on the spot, jump-jet hop) and Kestrel Jet (takes off past 24 m/s, cannot hover, 120 m ceiling, thrown in any world). Greybox models. Missing: their weapons, passengers, armor and weak spots, vehicle health, The rover can be found parked in Ashfront; the mech and the jet are built at the fabricator from their blueprints, which warlords and supply pods carry. |

## Racing

| Item | State | Notes |
| --- | --- | --- |
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
| Contracts: daily, weekly and rare high-risk, from a board in the hub, tracked on the watch and visor, counted on extract | Partly | Built: the board beside the big screen (3 dailies and a weekly by date, hold 3, one reroll a day), counters from `Raid._count` and what came home, counted only on a sign-out, paid at once (scrip, upgrade data, a weekly blueprint once they exist), a contract icon on the watch. The visor tracker shows the job nearest done (`VisorHud._draw_tracker`). Missing: high-risk jobs, per-world and per-rig jobs, contracts in solo runs, tuned payouts. |
| Bounties on hot players, paid on extract, tied to the most-wanted board | Partly | Renown, bounties and the Marked exist in the PvP world; payouts in upgrade data and the board are missing. |
| Safety nets: free Mk1 kit, one insured item, salvage on loss | Partly | The free `starter` scrap kit exists. Insurance and salvage are missing. |
| Prestige vehicles and rigs from hard feats | Missing | List TBD. |
