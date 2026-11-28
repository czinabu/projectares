# Guns, loadouts and feel

Rules for loadout slots and keys, attachments, power weapons, recoil, handling, feel benches and feedback. These are part of the rules in `CLAUDE.md` that must not be
broken: read this file before changing anything it covers, and keep it up to
date in the same PR.

- A loadout carries one primary, one melee weapon and one sidearm. Keys are by
  type, not equip order: 1 primary, 2 sidearm, 3 melee, and 4 the heavy weapon
  in the watch's chamber (`Actor.slot_order`, `weapon_for_key`,
  `Loadout.power_index`); the
  mouse wheel cycles the same order. Sidearms are firearms also tagged "sidearm";
  `Loadout.fits(slot, id)` decides what goes in a slot (a sidearm never fits
  the primary slot), and `Weapon.is_sidearm` marks one once equipped. A gun
  never switches itself (Caleb's call): run dry in hand it stays there and
  never reloads on its own; the prompt under the crosshair asks for one
  (`Hud.reload_prompt`, on with or without a helmet, in both views) and a
  pull on the empty gun starts it too, and with nothing left to load a pull
  only clicks ("Out of ammo"). A reload press the gun cannot
  take yet (drawing, healing) is kept for `Actor.reload_buffer`. Only the
  player, or a bot's brain pressing the same key (`BotBrain._tend_kit`),
  changes weapons. A player arrives unarmed (Caleb's call): every life in
  every world starts with the weapons put away and key 1's weapon ready to
  draw (`Loadout.arrive_unarmed`, in `Raid.add_player` and the client's
  copy in `NetSession`), and comes out only by choice: a number key, Z, the
  wheel, or a pull of the trigger with empty hands, which only draws. While
  `Actor.weapons_locked` (a safe zone, a gate outpost, the base off the
  range) a weapon in hand is put away and nothing can be drawn
  (`Actor._simulate_weapons`). Headshots come from
  `Combat.is_headshot` on a `Combat.trace` hit; a gun's `headshot_mult` scales them.
  Every gun has a range and a target it wins against (DESIGN.md "Gun
  roles"): each sets its own `headshot_mult` (more than 1 on every gun but
  a shotgun), close-range guns fall off with distance (`falloff_start`,
  `falloff_end`, `falloff_min`, `Gun.range_mult`) and marksman rounds go
  partly past armor (`Gun.armor_pierce`). Measure a change with
  `godot --headless --path . res://tests/gun_bench.tscn`, which prints
  every gun's time to kill by range and armor.
- Attachments are items tagged "attachment" plus their slot tag ("optic",
  "muzzle", "grip", "magazine"), each an optional loadout slot
  (`Loadout.ATTACHMENT_SLOTS`). They fit every primary and never a sidearm
  or a power weapon (tag "power", see `Loadout.is_primary`).
  `Loadout.equip` fits them with `Gun.fit` before the gun is equipped: their
  stats are data ("mult" scales the gun's tuning vars, "zoom" sets
  `Gun.ads_zoom`, "quiet" suppresses, "model" picks the shape). They go in
  `gear_items`, so they drop and come home with the gun. `Gun.build_attachment`
  builds each shape with its origin at the mount; `Look.mount_attachments`
  moves them onto the real model (`Look.GUN_MOUNTS`) and merges each
  attachment's unnamed parts that are set alike into one mesh per look
  (`merge_pieces` with `alike`: an optic was some thirty draws on every
  gun in the world); named parts (the scope's "Lens") and markers stay. An optic's "Sight"
  marker is the eye point: aiming brings it up to the model's eyes in both
  views, first person looks through it, and zooms by `Weapon.aim_zoom()`. Scopes are
  real geometry you look down, never a screen overlay, and picture in
  picture (Caleb's call: never a blacked-out screen): a scope's item has
  `"lens": true` (`Gun.scope_lens`), its "Sight" sits a real eye relief
  behind the eyepiece so the scope is a picture in the middle of the view,
  the aimed view keeps `ads_fov`, and `PlayerController._update_scope`
  renders the magnified view from the eye onto the eyepiece's "Lens" glass
  (`assets/shaders/scope_lens.gdshader` draws the reticle there). Fitting happens at
  the home base's gunsmith bench (`BaseLayout` kind "gunsmith", which is
  kept at the bench, never hung on show: `BaseLayout.is_at_bench`).
- Power weapons are items tagged "power" (Rail Lance, Helion launcher, Arc
  Mortar, Storm Cannon), still plain `Gun` data: stats such as
  `charge_time`, `pierce`, `projectile` ("rocket"/"grenade", flown by
  `Gun.Round`), `splash_radius`, `heat_seek_cone` and `spin_up` pick the
  behavior, and `Gun.splash` sends every blast through `Combat.deal`. They
  are found in a PvP world, not bought: `PowerArmory` (`core/war/power_armory.gd`,
  `Raid.armory`, authority only) puts them on power racks (a `LootContainer`
  labelled `LootContainer.RACK_LABEL`) at strongpoints, beside supply pods
  and sometimes beside a refilled cache, more often as `Raid.war` heats up,
  scaled by `WorldDef.power_weapon_rate` (0 in Frostline and the arena).
  Using a rack scans its weapon into the watch's heavy chamber, a fourth
  weapon slot filled through `Loadout.set_power` with `draw` false; one
  already carried goes on the rack with its shots. Key 4 draws it, as does
  the watch's weapon carousel (Caleb's call after a playtest, replacing
  "from the watch only"), and the wheel skips it (`Actor.slot_order`); it
  materializes over `Loadout.summon_time` (`Actor._draw_weapon`). Picked on
  the watch while in hand it goes back into the chamber, never the pack
  (`PlayerController.take_picked_weapon`). It takes the primary's place
  (Caleb's call): while it is out the primary waits in the watch
  (`Actor.primary_in_watch`) and materializes again whenever it next comes
  into the hand, by any path (`Actor._swap_primary_and_heavy`); the sidearm
  and blade stay instant. A spent one is thrown
  away. A dead player's is left on a rack beside the bag (never in the pack),
  and that death counts it as lost; where deaths drop scrip piles it is
  sold into the pile instead. `StashRules.storable` accepts them: a
  depot upload or a sign-out puts the chambered one in the stash, and it
  hangs on the home base's heavy weapon wall (`BaseLayout` kind `heavy_wall`,
  the `heavy_wall` upgrade) where copies stack. One may be equipped in the
  optional `power` loadout slot and is taken from the stash only when
  `WorldDef.carries_power_weapons` (a PvP world); the arena, Frostline and
  safe zones leave the chamber empty. They sell back at the trader for 40%
  and are never shop stock. Online the swap
  reaches clients as `Actor.power_changed` through `NetSession`. Their art is
  `Look._power_model` and `_dress_power_rack`; check by eye with
  `visual_check.tscn -- <dir> --power-only`.
- Feel is measured, not guessed: `godot --headless --fixed-fps 60 --path .
  res://tests/feel_bench.tscn` flies every rig through set moves and prints
  how long each takes to answer and the hardest jolt (velocity change in one
  tick, as m/s²). Movement eases: nothing but a jump, burst, pulse or dash
  may change an actor's velocity by more than its own accelerations in one
  tick (wings catch a fall at `FlightRig.glide_catch_accel` and roll into a
  bank at `glide_bank_rate`; never clamp a velocity straight to its target).
  Recoil is a pattern you can learn (Caleb's call, DESIGN.md "Recoil"):
  each gun's `recoil_pattern` ("climb", "climb_right", "climb_left",
  "sway", "kick") and a kick that builds through a spray
  (`Gun.recoil_for`, `spray_shot`, counted in `Gun._fire`, so simulated),
  with only `recoil_jitter` of the side kick left to chance; a new gun
  names a pattern in its stats. Bots take the same kick into their aim
  and pull against a share of it by skill (`BotBrain._take_recoil`,
  `RECOIL_CONTROL`); measure with `gun_bench.tscn -- --recoil`.
  What only the player sees is the controller's job and view only: recoil
  reaching the view over a few frames and settling back
  (`PlayerController._update_recoil`), the view widening with speed
  (`speed_fov`) and dipping on a landing (`land_dip`). A semi-auto keeps a
  pull made just before it is ready (`Gun.press_buffer`); that is simulated,
  so it is in `Gun`, from the command. Handling is simulated the same way
  (DESIGN.md "Handling"): moving widens a gun's spread by its
  `move_spread_deg` times the share of sprint speed on the ground
  (`Gun.move_share`), aiming tightens it over the gun's `ads_time`
  (`Gun.aim_in`), not at once, and you never shoot while sprinting: a held
  trigger or aim slows you to a walk, and a gun fires only
  `Actor.sprint_out_time` after the sprint ends (`Actor.sprint_recover`),
  keeping a pull made meanwhile. Light guns are quick and steady on the
  move; a DMR is slow to aim and wild on the run.
  Feedback is view only (DESIGN.md "Feedback"): every gun has a voice of
  its own (the item's `shot_sound`, one of `Sfx.GUN_VOICES`, never shared;
  a test checks it) that fits what it is: the everyday guns are ballistic
  (a crack, the action, a low punch, the cycle), the heavy weapons energy
  (a charged snap, a zap or plasma, crackle). They are made from code by
  `assets/sounds/weapons/make_weapon_sounds.py` (ours, no credit needed;
  short rings and short echoes, Caleb's feedback: never a bell, never a
  long echo), takes for the open, under a roof and far off.
  `Sfx.shot` plays your own the tick it fires, flat, and anyone else's
  where it went off: under a roof (`Sfx.roof_over`) the indoor take, past
  `Sfx.FAR_FROM` giving way to the far take after the sound's travel time.
  A rail's charge and a rotary gun's spin are heard from the gun's state
  (`ActorSkin._update_weapon_hum`), a draw as the hand takes the weapon,
  all heard out to `Gun.SHOT_REACH`, a round
  passing close is heard going by (`Sfx.pass_by`), a round leaves a puff
  and a wall a mark for a few seconds (`Fx.impact`, at most `Fx.MAX_MARKS`;
  `Combat.trace` gives the face's `normal`), the hit marker and its sound
  tell a head, plates soaking it (`DamageInfo.armored`, set by
  `HealthComponent`), plates breaking (`armor_broke`) and a kill apart
  (`Hud.HitMarker.kind_of`; online they ride `NetSession._hit_feedback`),
  and a round jolts the view (`PlayerController.bullet_flinch`), never the
  aim. Who shot you is not shown: that is the tactical visor's job.
  Check by eye with `visual_check.tscn -- <dir> --impacts-only`.
  The hit marker is four tapered blades that snap in at the diagonals:
  pale cyan for flesh, steel blue for plates soaking it, bright cyan with
  shards flying off for plates breaking, amber with a diamond round the
  middle for a head, and red for a kill, white-hot for a moment, with a
  diamond frame thrown outward.
- The crosshair (`core/ui/crosshair.gd`, on `Hud` and the base's HUD) is
  the same in first and third person (Caleb's call), in the systems palette
  (cyan `#4DD9FF`, amber `#FF9E38` for key marks only, red `#FF4A3A` for
  hostile) and angular: a small diamond and four tapered blades whose tips
  sit at the gun's real spread (`Gun.current_spread_deg` in pixels at the
  camera's field of view), kicked out and flared a little per shot, so
  moving, jumping, spraying and aiming open and close it by what they do to
  the shots. It turns red with corner brackets over an enemy in range, goes
  dim with each blade broken when what is under it is past `max_range` or
  `falloff_end`, dim red with a hollow diamond when the magazine is out or
  jammed, and becomes a ring of eight segments lighting in turn during a
  reload (amber for a charge or a spin-up); a melee weapon gets the diamond
  alone. It fades out when the sight is up in first person; in third
  person aiming only closes it. It is view only: one ray along the aim
  every `probe_interval`, nothing in the simulation. Never put text on it,
  and every line on it must say something.
