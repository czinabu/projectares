# Audio

Rules for the game's sound: footsteps, engines, each world's ambience and
the music. These are part of the rules in `CLAUDE.md` that must not be
broken; change this file in the same PR as the code. (Gun sounds are in
`guns-and-feel.md`.)

- All sound is view only. `Sfx` (`core/fx/sfx.gd`) does nothing on a
  headless server, and nothing here ever changes the simulation. Sound reads
  only what every client already has (positions, speeds, who rides what),
  so everyone hears the same thing.
- Files. The world's sounds live in `assets/sounds/world/` and are made by
  `make_world_sounds.py` there: footsteps and engine loops cut from Kenney's
  CC0 packs, the cold wind and the plaza's music made from code (CC0). Each
  is optional in code: a checkout without one goes without it. A new file is
  recorded in `assets/LICENSES.md` (CC0, or a royalty-free license that
  needs no credit, Caleb's call). The Sonniss clips of `assets/sounds/`
  stay out of the public repository (`assets/sounds/README.md`).
- Footsteps (`Footsteps`, `core/fx/footsteps.gd`). `Sfx` hangs one on every
  `Actor` as it enters the tree (`Sfx._on_node_added`), so nothing in
  `Actor`, `ActorSkin` or `Look` knows about it. A step comes from how far
  the body really moved on the ground (`step_length` by speed), never from
  its animation, so remote players, thinned far bots and your own body step
  alike. No steps in the air, sliding, riding or dead; a landing after
  `land_after` seconds in the air is a heavier step.
- The ground a step sounds like (`Footsteps.ground_for`): a collider with a
  "footstep" meta is that (one of `Sfx.STEP_GROUNDS`: hard, dirt, snow,
  soft, wood); the open ground (`Terrain`) is `WorldDef.footstep_ground`,
  which is "hard" where the ground is ice (`surface_grip` under half), else
  the world's `footsteps`, else its planet's (`PlanetType.footsteps`);
  anything else built is "hard". A map that wants metal or wood decks to
  sound so sets the meta on the body; `core/` never names a world.
- Engines (`EngineSound`, `core/fx/engine_sound.gd`). `Sfx` hangs one on
  every vehicle the same way, so `vehicle.gd` has no sound code. It runs
  only while the machine has a rider, pitched and louder with `speed`
  against `max_speed` (`voice`), one loop per kind (`kind_of`: "ground",
  "hover", "air"; an airship's deep and far). An empty machine is silent.
- Ambience is a `Soundscape` (`core/fx/soundscape.gd`) a map adds where
  `Look` is on, tuned by its vars: the rumble and wind loops it plays
  (`rumble_sound`, `wind_sound`), far gunfire, booms, `accents` (sounds of
  the place now and then, such as Frostline's ice groaning) and `shelter`
  (under cover the wind drops and the rumble rises). Ashfront's is the war
  past the rim; Frostline's is the cold wind, the Engine's hum (louder
  inside the Engine) and the ice.
- Music. `Sfx.music(track)` fades to `music_<track>.ogg` (or out, for "")
  on its own bus (`GameSettings.MUSIC_BUS`, made by `music_bus`), turned by
  the phone's Music setting (`music_volume`) under the main Volume. The same
  track again plays on where it is. A world picks its track with
  `WorldDef.music` (the Concourse "plaza"; the war worlds none, so the war
  is what you hear), `Raid._setup` asks for it, and the start screen and
  the home base play "plaza".
- Kept light on a laptop. `Sfx.sound_detail` is the War scenery setting's
  share (the Low and Lowest presets turn it down). Past a body's `reach` or
  an engine's, nothing is done but one distance check. The bodies in
  earshot share `Sfx.STEPS_A_SECOND` steps a second (`Sfx.take_step`; your
  own never ask), at most `Sfx.engines_at_once` engines run together (yours
  always does), and both reaches, far gunfire and accents shrink with the
  detail. A new per-body sound needs the same treatment.
- Checks: `tests/audio_tests.gd`.
