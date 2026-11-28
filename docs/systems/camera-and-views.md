# Camera and views

Rules for the camera, first and third person, the head and eyes, what is drawn between ticks, picture quality settings. These are part of the rules in `CLAUDE.md` that must not be
broken: read this file before changing anything it covers, and keep it up to
date in the same PR.

- The camera never changes view on its own. First/third-person switches only
  when the player presses the toggle (playtest feedback). The one exception:
  getting on a vehicle uses a separate riding view (third-person by default),
  and getting off restores the on-foot view. The phone never moves the
  third-person camera (Caleb's call, replacing the old reading view and
  zoom): its screen rises beside the character as a hologram
  (`Phone.HoloScreen`, see `ui-phone-watch.md`), so the world stays in view.
  The one time it moves for the phone is the Mirror app's dressing room
  (`PlayerController.dressing_room`): it swings round in front of the
  character, turned by a drag, and back when the app goes.
  In first person the eyes drop to the phone while it is out
  (`phone_view_pitch`, less with the mirror up), the view only: `pitch`
  and the aim stay put, and the view zooms in on it like aiming down sights
  until the phone stands `phone_zoom` of the view's height, whatever the
  field of view setting, with all of it kept in frame (`phone_fit_fov`,
  Caleb's pick so the screen reads; not with the mirror up). While a
  view setting's slider is dragged on the phone (`GameSettings.SCHEMA`'s "preview")
  all of that lets go (`PlayerController.phone_preview`) so the change is
  seen live, and the slider follows the mouse's motion. The Mirror app
  keeps the phone up, its screen thrown beside your reflection as the
  third-person dressing room has it (Caleb's comparison of the two views);
  its "Put the phone down" button lowers it (`Phone.mirror_lowered`, `held`)
  so the mirror shows the whole kit, and a click, right click or Esc brings
  it up.
  The third-person camera stands over the right shoulder
  (`PlayerController.shoulder`) and, aiming, moves in and further out
  over it (`shoulder_aim`), so the head never sits on the sight line;
  both fade in as it leaves the eyes, so a view switch glides. Walls stop
  it as a swept ball (`camera_radius`, `_third_person_offset`): in at
  once, back out at `wall_return`. Riding frames a bigger vehicle from
  further back (`ride_scale`). Check with
  `visual_check.tscn -- <dir> --camera-only`.
- The head looks where its owner aims (Caleb's call, so others see where
  you look): `Locomotion._look_pose` turns the neck and head onto
  `Actor.get_aim_dir()` from whatever pose the body is in, no further than
  `look_reach` side to side from the chest and `look_up` back or
  `look_down` down from it (measured in the chest's frame, so a body laid
  out in flight lifts its head rather than folding it back), and gives
  way to the phone. View only, the
  same body in both views; first person's eyes simply ride the turned head.
- Flight moves the first-person camera a little (the rigs' style pass,
  Caleb's call): the view rolls with a third of the wings' bank and a
  quarter of a skate's carve, sways with the skate's strides, jolts as a
  jetpack boost lights and rumbles while it runs
  (`PlayerController._update_flight_motion`, `flight_bank_roll`,
  `skate_carve_roll`, `boost_rumble_deg`), read from the skin
  (`ActorSkin.flight_bank`, `skate_carve`, `stride_phase`, `boost_push`).
  Camera only and first person only (`_eyes_weight`): the body is the same
  in both views and third person sees it roll. The phone's "Camera motion
  in flight" slider (`GameSettings.flight_camera_motion`) scales it, down
  to none.
- Bodies are shown between physics ticks (Caleb plays at 144 Hz):
  `ShownMotion` (`core/visual/shown_motion.gd`, added by `Look` to every
  actor and vehicle it dresses, so a server has none) puts its parent
  where it is between its last two ticks for each drawn frame and back
  before the next tick (`SceneTree.physics_frame`), so the simulation
  never sees it; a jump (`JUMP`) is shown at once and a thinned body is
  left alone. The player's own body turns with the mouse every frame
  (`PlayerController.LiveAim`, `ShownMotion.live_yaw`). A check of what
  is drawn reads it late in the frame or inside `skeleton_updated`, not
  after the next tick.
- First and third person differ only in where the camera is (Caleb's rule).
  Third person never shows more than the eyes see (Caleb's call): out in a
  world where gear is at stake, a hostile body the eyes have no line to
  (head, chest, hips or either side) fades out of the third-person view
  (`PlayerController.PeekFade`, `peek_rule_applies`), so peeking round a
  corner from over the shoulder gives nothing first person lacks. View only;
  squadmates and the dead are never faded.
  Both look at the one real body, posed by the same code and holding the
  same weapon in the same hand: first person puts the camera at the eyes
  (`ActorSkin.eye_point`, pulled back level by `GameSettings.eye_pullback`,
  which eases off as the view tips down while the eyes lean ahead,
  `PlayerController.look_down_lean`, so looking down sees the chest, never
  the shoulders from behind)
  from the head as drawn, in every pose (`ActorSkin._head_local`, the
  posed head; its steadying trails it by at most `eye_steady_reach`, the
  controller's easing by at most `eye_lag_reach`, and `head_posed` carries
  it on with the head posed after the camera was placed; no landing dip on
  top of the body's own squat), so the eyes never trail into the neck or
  the armor's collar (`camera_tests.gd`, `_check_eyes_stay_in_the_head`),
  and leaves out only the head (`ActorSkin.hide_head` moves it and what is
  worn on it to `Mirror.HEAD_LAYER`, which that camera culls; shadows and
  a mirror still see it). A station's own view (the bench's, a
  `WorldScreen`'s) stands about where the head is, so it leaves the head
  out the same way in either view (`PlayerController.screen_view_up`, its
  camera's `SCREEN_VIEW` meta; Caleb's feedback: it blocked the bench). Never build a first-person-only copy of the arms,
  a weapon or a prop, and never move anything in front of the camera for
  first person. Aiming down sights is a body animation, the same in both
  views (`ActionPose.ads`, eased by `ads_rate`): `WeaponArm._reach_sight`
  reaches the gun hand so the sight (`ActionPose.sight_local`: an optic's
  "Sight" marker, else the model's "IronSight", else the top of the model;
  a gun with no optic wears iron sights there, a rear notch and a lit
  front post, `Look._iron_sights`) sits on the line out of the model's eyes, `ActionPose.relief_for` in front
  of them (a sidearm out at arm's length, a long gun shouldered), and the
  off hand takes the "ForeGrip" (or cups a sidearm), sliding back along
  the gun where the arm cannot reach. A sight out of the gun arm's reach
  comes back toward the eye (`ActionPose.relief_now`, which first person
  follows). Both wrists turn as the `aim_gun` clip holds the gun, turned
  with the aim (`WeaponArm._turn_to_aim`), so neither twists round it, and
  the shoulders take a stance (`ActionPose.ads_stance`: a long gun bladed,
  a sidearm squared up). Bone poses are only final inside the skeleton's
  `skeleton_updated`; a check of a posed bone reads it there. Guns tagged in
  `ads_hip_tags` (the minigun) stay at the hip. First person then only
  settles the camera on the sight line as it comes up; never move the gun
  to the camera. Aimed on the move the body holds the gun still rather
  than the view being steadied (playtest feedback: the sight bounced):
  you walk at `Gun.ads_move_mult` and never sprint, the spine, shoulders
  and head follow the gait with a lag (`Locomotion.aim_still_time`), and the
  eyes the gun is brought to are steadied (`ActorSkin.eye_steady`, fully
  while aimed); measured in `ads_tests.gd` (`_check_on_the_move`). A view that follows the gun reads it where it was drawn
  (`ActionPose.sight_shown`, the hand's "shown_local" meta), never the hand
  node a physics tick parked (that was the range's ADS stutter). A weapon
  that takes no input on a tick stops aiming (`Weapon.drop_aim`). Each
  actor has one `ActionPose`
  (`core/visual/action_pose.gd`, a view-only child made by `ActionPose.of`):
  the melee reach and shoulder turn, the reload motion (brought in to the
  middle, where the eyes see it, `reload_reach`), the low ready, the
  drawing back of a held heavy and the easing back of a recovering blade,
  the gun brought up to the eye,
  the watch raise (from `ActorCommand.watch_up`), the phone hold
  (`ActionPose.phone`, from `ActorCommand.phone`, which `Locomotion` poses
  the body from) and the inspect key's look over (`ActionPose.inspect`,
  from the held flag `ActorCommand.inspect`: the wrist comes to
  `inspect_point` and turns the item through `INSPECT_TURNS`, timed by each
  view from when it saw the flag; check with `visual_check.tscn -- <dir>
  --inspect-only`). `WeaponArm` and `ActorSkin` pose the model from it; a new
  hand or weapon animation goes there. Weapons are held, not floated
  (Caleb's call): the hand carries them, each by its own grip (Caleb's
  call), found on the model rather than tuned by hand. `Look._measure_hold`
  reads a gun's side outline for its trigger guard, the pistol grip behind
  it (its rake) and the fore end ("Grip", "Trigger", "ForeGrip" markers;
  a power weapon marks its grip in `_power_grip`); the fist's middle closes
  on the grip level with the trigger and the wrist bends to its rake
  (`WeaponArm._held_wrist`, `_bend_to_grip`). Whenever a gun is raised
  (aiming or shooting, not held low or reloading) the off hand supports it
  as in a real FPS hold (Caleb's references): under a long gun's fore end
  palm up, fingers up its side ("ForeGrip", found just under the fore end,
  `Look.FORE_CUP`), and wrapped round the shooting hand on a sidearm
  (`ActionPose.ads_cup`), thumb forward with the wrist in line with the
  forearm, the pistol held out in both hands; its wrist is turned by
  `WeaponArm._support_turn`.
  `Look._fit_hands` finds a melee handle (up to its guard or
  head), puts it through the fist and gives a two-handed weapon
  (`Look.is_two_handed`) its off hand's place: a hand below on a short
  handle, up the haft of a long one, which rests carried across the body
  (`WeaponArm.carry_point`). Check by eye with
  `visual_check.tscn -- <dir> --hands-only`. A one-handed weapon at rest is
  held ready, not left to the idle clip (Caleb's references): the arm
  reaches the hand to the lower right of the view and the weapon stands in
  the fist the way its hold says (`ActionPose.ready_holds`, picked by the
  last field of `Look.MELEE_MODELS`): a straight sword with the elbow bent,
  the fist by the hip and the point up toward a foe's face, a katana
  leaning in with the off hand under the weapon hand, a knife lying flat in
  a reverse grip. An empty off hand stays up as a guard
  (`ActionPose.off_guard`) through every swing and guard, and on the ground
  the legs take a fighting stance while a blade is out (`Locomotion.fight`:
  knees bent, feet staggered standing still). Attacks start from the
  hold and ease back into it (`ActionPose.held_ready`). A blade lies along the closed fist
  and a gun held low turns with the wrist (`WeaponArm`); swings turn the
  arm through the technique's keys (`ActionPose.keyed_reach`, `elbow_pole`). Shots
  are judged from the eyes but drawn from the gun's "Muzzle" marker as it
  is shown (`Gun.muzzle_point`). Compare by eye with
  `visual_check.tscn -- <dir> --views-only [rows]` (`VIEW_MELEE=<item id>`
  picks the melee weapon), which also saves each shot full size under
  `views/`.
- Picture quality is settings and light shaders, never new art: edge
  smoothing is `GameSettings.anti_aliasing` (SMAA by default, MSAA on top
  as an option; never TAA, it smears motion), set on the main view by
  `GameSettings.apply_graphics`; world textures keep mipmaps (a test checks
  their `.import` files) and are filtered 16x. Far shapes out in a world get
  a thin outline from the depth buffer (`Look.edge_ink`,
  `assets/shaders/edge_ink.gdshader`, a quad the shader stretches over the
  camera, the same in both views), which MSAA leaves no depth for, so it is
  off in those modes (`GameSettings.ink_shown`). Both are on the phone's
  Settings, View tab. Compare by eye with `visual_check.tscn -- <dir>
  --graphics-only [--aa 0-4] [--ink 0|1]` and measure with the frame bench's
  `--aa` and `--ink`. For a slower graphics card the same tab offers
  Shadows (`GameSettings.SHADOWS`: High is the world as made), Render
  scale (FSR 1) and Ambient occlusion; a world's sun and atmosphere take
  them through `GameSettings.fit_sun(sun, reach)` and `fit_atmosphere`,
  so set a sun's shadow reach only through `fit_sun`. View distance
  (`GameSettings.VIEW_DISTANCE`, Caleb's ask: a short view spoils it;
  High is each world as made, Ultra and Medium and Low either side) sets
  how far the player's camera reaches (`PlayerController._view_far`: the
  map's "view_far" meta or its planet's far land ring, "horizon_far" from
  `Planet.atmosphere`, by `view_far_for`), how far map props are drawn
  (`Look._limit_draw_distance` keeps each mesh's own reach in
  `Look.DRAW_BASE` and `fit_draw_distance` scales it, live) and mesh
  detail (`mesh_lod_threshold`). A map gives something a far reach of its
  own with a visibility range, which the setting scales too; compare by
  eye with `visual_check.tscn -- <dir> --sightlines-only [levels]`, which
  writes each shot's draw calls beside it.
- Laptops and low-end machines: one pick, Graphics quality
  (`GameSettings.GRAPHICS`: High, Medium, Low for laptops, Lowest), sets
  every performance row and the edge smoothing at once; changing one of
  them by hand reads Custom (`graphics_matching`), and the phone shows a
  pick's rows at once (`Phone._sync_setting_controls`, no redraw). High is
  the defaults. On the first launch on a graphics card
  (`GameSettings.detect_graphics`, once per card, kept in `graphics_card`)
  a laptop's built-in graphics starts on Low (the strongest of them on
  Medium), a software renderer on Lowest and the OpenGL fallback on Low
  (`graphics_for`); it only lowers untouched defaults, never settings the
  player chose. A saved pick (not Custom) takes the pick's rows as they are
  now when the settings load (`use_saved`), so a change to a pick reaches
  players already on it. Low's render scale is Auto (`RENDER_SCALE_AUTO`):
  `GameSettings.AutoScale` times the graphics card on the main view and
  every 1.5 s moves the scale a step between 100% and 50%
  (`AUTO_SCALES`, `AutoScale.next_step`) to keep it under `AUTO_TARGET_MS`,
  waiting 2 s after each change (it rebuilds the view's buffers); with no
  timing from the card (the OpenGL fallback) it stays on 67%. The glow
  around bright things (`bloom`, the atmosphere's glow) is a row of its
  own, off on Low and Lowest: about a seventh of a laptop-class frame.
  "Far battle scenery" (`war_scenery`, `WAR_SCENERY`) is one too: how
  much of a world's far, view-only war is shown (`war_share`: Full,
  Thinned on Low, Light on Lowest), read by each piece of it as it
  decides how much to show, so a change takes at once; see
  `marsh-and-ashfront.md`.
  A world's war mood (`Look.WarMood`) writes the sky only when it moved a
  visible step (`mood_moved`): any write to a sky material, even of the
  same value, has Godot redraw the sky's light map that frame. Every
  body part keeps levels of detail for far away (the bodies' import makes
  them; `SuitShape` makes them again for the suit it reshapes, and
  `laptop_frame_tests` checks the baked parts have them): without them a
  far body draws all its triangles, about a fifth of Ashfront's at Low.
  `HeadShape` makes them again for each face shape and haircut it builds
  (a few ms, once per cut and face). A merged vehicle (`Look.merge_pieces`
  with `lods`, over `LOD_FROM` triangles) gets them too, made once per
  shape (`_with_lods`): Ashfront's 21 parked vehicles went from about 330k
  triangles a frame to 23k. A window
  bigger than the screen it opens on is shrunk to
  fit (`fit_window_to_screen`). These are view only: a server, the
  simulation and first or third person are untouched. Compare the picks by
  eye and graphics card time with `visual_check.tscn -- <dir>
  --graphics-presets-only [world ...]`. The "Linux Client" export preset
  is the playtest build for Linux, built beside the Windows one.
