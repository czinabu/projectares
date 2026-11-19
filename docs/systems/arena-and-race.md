# The arena and the race world

Rules for the arena venue and its rules, and Meridian's races, league, ghosts and tuning. These are part of the rules in `CLAUDE.md` that must not be
broken: read this file before changing anything it covers, and keep it up to
date in the same PR.

- The arena (`core/arena/`) is a venue, not a raid world: `ArenaVenue` is a
  `WorldDef` that is never in the registry, has `gear_at_risk` off, and
  returns `Arena` (a `Raid` subclass) from `new_raid()`. Nobody loses gear
  there: `StashService.deploy` hands out the kit without taking it, nothing is
  settled, nothing drops, and fighters yield at `HealthComponent.min_health`
  instead of dying. Only the two fighters of a running bout may hurt each
  other (`Arena.may_hurt`). Results, wagers, stakes and tournament pots are
  decided only by the authority's `Arena` and paid through `Arena.bank`;
  a client only sends `Arena.ask` requests and shows the board the server
  sends. Scrip changes only through `StashService.change_scrip` online and
  `Profile.change_scrip` solo. The Pit's moving parts (the tunnel doors and
  the rising barriers) are worked out from the bout's phase and fight clock
  alone (`ArenaVenue.doors_open`, `barrier_raise`), which the `Arena` hands
  the map every tick (`set_stage`) on every machine, so they need no messages
  of their own. Static venue boxes are merged into one mesh per material.
  Every bout and tournament has rules (`Arena.RULES`, DESIGN.md "Gladiator
  arena"): "open", "blades" or "blades_boots". `Arena._apply_rules` holds
  them on the fighters every tick on every machine, from the bout on the
  authority and the board's "rules" and "nodes" on a client: no gun is
  drawn (`Actor.guns_locked`, which puts one in hand away for the blade)
  and a barred rig stays jammed (`FlightRig.jam`, renewed by `RIG_HOLD`).
  A gladiator for a blades bout is picked by its seed
  (`ArenaVenue.gladiator_has_blade`), so clients build the same one. A
  tournament under blade rules is the Blade Tournament: its champion's
  weekly prize (the `trophy_blade_champion` item and a chance at an
  artifact) goes through `Arena.Bank.prize`, once a week per account
  (`arena_prize_week`): `Profile.arena_prize` solo, the sure
  `StashService.arena_prize` online, which checks the week again.
- The race world (`worlds/meridian`, DESIGN.md section 9) is run by `Race`
  (`core/race/race.gd`, a `Raid` subclass from `WorldDef.new_raid`), on a
  map that offers `race_track()` (a `RaceTrack`: the centre line, gates,
  start slots, `keep_to` lines; a map with several offers `race_tracks()`
  too, read into `Race.circuits`, and a run is on the one nearest the
  machine got on, `Race.track_near`, with its own grid and gates; each
  board row carries its "track", and a second track's gantry, arches and
  board carry the meta "track"). Nothing is at stake there:
  `WorldDef.gear_at_risk` off clears every result's loot and kit lists
  (`Raid._finish_player`) and `Profile.checkout_loadout` takes nothing,
  `weapons_free` off locks weapons and makes `can_damage` refuse, and
  `portal_home` keeps the portal home on offer. Racers bring no vehicle:
  the machines wait in the pit bays and race on their race profile
  (`Vehicle.race`, `apply_race_profile`, `ItemDB.RACE_*`), never their
  combat tuning. Only the authority judges a run (grid, lights,
  `Vehicle.held`, gates by `RaceTrack.cross`, laps, the off-track rule, the
  board); a client gets its own run (`NetSession._race_run`,
  `Race.remote_run`) and the board, holds its machine for the lights from
  that, and asks with `NetSession.race_request`. Live races are the
  track's `Race.heats` (authority only; clients get `heat_view` through
  `NetSession._race_heats`): asked for with the race icon's "race" pick,
  formed for `FORM_TIME` (`ALL_IN_FORM` once everyone here is on it) with
  AI racers on the grid from the start (`_fill_grid`, a person who joins
  takes one's place, `_bump_ai`), filled to `GRID_SIZE`. While anyone is
  in the world a track nobody rides runs an AI-only race (`Heat.ambient`,
  `_tick_ambient`, `AMBIENT_FIELD`; Caleb's ask, so the world is never
  dead), which moves no league; asking to race there calls its field to
  the grid (`_call_to_grid`), and an empty world runs none. A person who
  gets off out on the track is set down on pit row (`_off_machine`).
  Prompts name the interact key from the `InputMap` (`RaceView.key`).
  An AI racer is a bot (meta "race_ai") on a machine of its own, driven
  only through its `ActorCommand` by a `RaceDriver`, which is also the
  bench's driver; never give one speed, grip or a rule a player lacks, and
  never put its laps on the board. The league (`core/race/race_league.gd`,
  static rules like `Contracts`) is kept on the account (`Profile.racing`,
  `Account.racing`, in the snapshot and `StashRules.CARRIED`) and moved
  only by a live race's close: the authority's `Race` sends each person's
  finish to its `league_bank` (`StashLeagueBank` online, a sure
  `record_race` call; `ProfileLeagueBank` solo), where `RaceLeague.apply`
  moves the rating and pays the capped scrip. A grid's AI are the named
  rivals of its best rider's league; their radio lines go only to the
  racer they are said to (`Race.radio`, `NetSession._race_radio`) and are
  drawn on the visor (`Hud.comms`, `VisorHud._draw_comms`). Ghosts are the
  authority's too: `Race` records each person's lap (`Run.recording`) and
  a counted lap faster than their best there goes to the same bank
  (`keep_ghost`: online `StashService.keep_ghost`, a sure call, kept in a
  file beside the account with only the time in `RaceLeague`'s "bests";
  solo `Race.GHOST_PATH`). Which ghost a racer chases is the race icon's
  pick (`Race.GHOST_PICKS`), asked with `Race.want_ghost` (online
  `NetSession._race_ghost_ask`, where the server finds a friend's among
  the phone's saved contacts, `_friend_ids`) and played by `RaceView`;
  friends' best times reach the pit boards the same way
  (`Race.friend_bests`, `NetSession._send_friend_bests`). Race control's
  desks (map markers "race_desk", metas "track" and "machine") sign a
  person onto the next race on a fresh machine (`Race.sign_up`, asked as
  "signup:<track>:<machine>", which the authority decides, standing within
  `DESK_REACH`); a desk with no machine is a watch desk, `RaceView.watch`,
  a camera only. A done run is guided to the track's `RaceTrack.pit`
  (`Hud._guide_to_pits`) and the authority sets the racer down there
  (`Race.set_down`, within `PIT_RADIUS` or after `PIT_TIME`); a machine a
  desk made goes when its racer gets off. Tuning kits
  (`RaceLeague.KITS`, kept per machine in the league state's "tunes",
  unlocked by league) are fitted at a pit bench (map markers "race_tune",
  `Race.tune`, asked as "tune:<machine>"; online the sure
  `StashService.tune_race`) and put on a person's machine for their run
  only (`Race.fit` at `start_run`, stock again at `retire`); a client fits
  the kit its run view names so it predicts the same. Every kit must keep
  its machine inside the class's 3% on every track
  (`race_bench.tscn -- --tunes`). Where a road runs over
  another (Skyhook), `RaceTrack.locate`'s full search counts height and a
  gate is passed only within `GATE_HEIGHT` of it. The stands, crowd
  (`Crowd`, `assets/shaders/crowd.gdshader`), skyline and works are
  decoration (`worlds/meridian/stands.gd`, `skyline.gd`, `works.gd`),
  merged into one mesh per material (the works per material per block,
  every lit and painted shape in one vertex-coloured material each). The
  works fill the salt out to the dunes (`GROUND_HALF`) and keep off the
  roads (`track_dist`; `race_tests.gd` checks every road point at any
  height) and what `WORKS_KEEP_OUT` lists, and the view draws out to the
  map's `VIEW_FAR` (its "view_far" meta); a new stand or set piece goes
  in that list. The lights, splits, board
  text and the ghost being chased are `RaceView`, a view. In a race world the
  watch's contract icon is the race icon (`Hud.race_slot`, `glyph`).
  Every machine in a class stays within 3% of the class average round
  every track: check with
  `godot --headless --fixed-fps 60 --path . res://tests/race_bench.tscn`
  and tune the race profiles, never the combat stats.
