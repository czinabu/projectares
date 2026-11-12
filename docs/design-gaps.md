# Design gaps: what DESIGN.md asks for vs what is built

Checked against `main` on 2026-11-12. Update a row in the same PR that
closes it. "Built" means it is in the code today; "Partly" says what is
missing; "Missing" is not started.

Order of work follows the roadmap in [DESIGN.md](DESIGN.md#11-roadmap):
rows marked **pre-playtest** come before the friends playtest.

## Places

| Item | State | Notes |
| --- | --- | --- |
| Main hub as a safe social space | Built | The Concourse: safe zone, gates, shops, clan hall, arena gate, look tags. |
| Hub vehicles limited to harmless fun | Partly | Bikes can be ridden in the plaza and nobody can be hurt. Not checked: whether parked bikes pack themselves away so the hub stays clear. |
| Watch skins shown off in the hub | Missing | No watch skin items yet. |
| Home base with armory wall, garage, trophies | Built | `core/base`: gun rack, blade wall, garage, trophy shelf, consoles. |
| Heavy weapons stacked on the armory wall | Missing | Power weapons cannot be stored (`StashRules.storable` refuses the `power` tag). **Pre-playtest**, with the heavy chamber. |
| PvE world: quests, dungeons, bosses | Missing, deferred | Until after the friends playtest. Frostline stands in (no PvP, gentle death, basic loot). |
| PvP world | Built | Ashfront: armies, strongpoints, war intensity, events, renown, full loot. |
| Heavy weapons only in the PvP world | Built | `power_weapon_rate` is 0 in Frostline and the arena. |
| Arena with loadouts locked in a bout | Built | The Pit: own loadout, no healing or vehicles, nobody loses gear. |

## Watch

| Item | State | Notes |
| --- | --- | --- |
| Vitals, pack, ammo, heat, standing, strongpoints | Built | `Hud.Wrist`. |
| Landing choices | Built | |
| Vehicle carousel (toys) | Built | Pick, throw, unpack, pack back; holds two. |
| Heavy weapon chamber | Missing | Today a power weapon fills key 4 from a rack. **Pre-playtest.** |
| Per-rig readouts (stall line, height band, dash pips) | Missing | Comes with the aerial rig rework. **Pre-playtest.** |
| Sign-out from the watch, with its countdown | Partly | Sign-out exists on L; not on the watch. |
| Loadout swapping from the watch in the PvE world | Missing, deferred | With the PvE world. Today loadouts change only in a lobby or base. |

## Loadout

| Item | State | Notes |
| --- | --- | --- |
| Primary with attachments | Built | Four attachment slots, gunsmith bench. |
| Sidearm | Built | Key 2, drawn automatically when the primary runs dry. |
| Melee weapon | Built | Six types, directional, block and parry. |
| Melee magnetic air-lunge | Missing | There is a ground heavy lunge and a dive slam onto targets below, but no lunge to an airborne enemy. After the playtest. |
| Flight rig | Partly | Three rigs exist, but not the agreed identities (next section). |
| Gadget slot | Partly | The `ability` slot exists with Phase Step, Kinetic Barrier and Shock Pulse. The gadget list (DESIGN.md section 4) needs Caleb's pick before more are built. |

## Flight (see the aerial rig proposal)

| Item | State | Notes |
| --- | --- | --- |
| One 15 m/s cruise for every rig | Missing | Jetpack hovers at 10 m/s and boosts at 22; wings glide at 16; boots have no sustained flight. **Pre-playtest**, PR 1 of the proposal. |
| Jetpack cruise and coast loop | Missing | PR 1. |
| Wings: pulse, stall, barrel roll, sidearm-only while spread, slide landing | Missing | PR 1. Q/E only tilts today. |
| Boots as a skimming rig with height bands and air dashes | Missing | Today three quick kicks. PR 2. |
| Air aim penalty, waived in each rig's steady state | Missing | No airborne spread in `Gun`. PR 1. |
| Overheat cuts the rig out until heat is back to 35 | Built | `recover_heat` 35. |

## Heavy weapons

| Item | State | Notes |
| --- | --- | --- |
| Heavy weapons as data, splash through `Combat.deal` | Built | Rail Lance, Helion, Arc Mortar, Storm Cannon. |
| Found at strongpoints, by pods, more as the war heats | Built | `PowerArmory`. Today they sit on swap racks. |
| Scanned into the watch chamber instead of swapped at a rack | Missing | **Pre-playtest.** |
| Summon without dropping the primary; auto-return when spent | Partly | Key 4 switches to it and the primary is kept. Check that a spent one returns the previous weapon by itself. |
| Banked by depot or sign-out to the armory wall | Missing | Needs `StashRules.storable` to accept `power`, and the `CLAUDE.md` power weapon rule rewritten. **Pre-playtest.** |
| Deploy with one from the wall (one per outing) | Missing | **Pre-playtest.** Open decision in DESIGN.md section 12. |
| Dropped with your bag on death | Partly | Today a dead player's power weapon is left on a rack. |

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
| Clearly faster than flight | Partly | On paper both bikes beat the 15 m/s cruise, but the jetpack boost (22) and the wing dive (26) match or beat the Scrapper. Tune after the rig rework, and check on real terrain. **Pre-playtest.** |
| Throw a toy from mid-air onto the road below | Partly | Throwing works off the ground in code; not checked as a planned move (throw, fall, land on the bike). |
| Eject upward off a speeding bike into flight | Partly | Getting off in mid-air keeps the bike's speed and the rig takes over; there is no upward eject. |
| Passenger seats | Missing | Bike rear seat, rover's four. After the playtest. |
| Mounted firepower | Missing | Rover turret, mech cannons, jet missiles. After the playtest. |
| Cargo space while riding | Missing | After the playtest. |
| Mobile cover | Missing | Rover and mech; the bike gives none by design. |
| Per-vehicle watch recharge (heavier is slower) | Missing | One `Raid.toy_cooldown` for all vehicles today. |
| Rover, mech and jet | Missing | Agreed roster, each with a weakness and counter (DESIGN.md section 8). After the playtest. |
