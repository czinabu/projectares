# Bodies and animation

Rules for legs, gait, crouch, slide, carries, holsters, and people built from parts. These are part of the rules in `CLAUDE.md` that must not be
broken: read this file before changing anything it covers, and keep it up to
date in the same PR.

- Legs follow the actor's velocity, never its input (`core/visual/locomotion.gd`):
  walk and run clips are measured from their feet and played at actual speed
  over clip speed, the clip nearest the direction of travel is picked, and the
  lower body turns the rest of the way while the spine keeps the chest on the
  aim. Remote players work the same way from their replicated velocity.
  Past a relaxed cadence a run lengthens its stride (feet stretched about
  their average spot, legs solved to reach them) rather than only spinning
  faster: that is the sprint. A slide (`Actor.slide_left`, `Actor.slide_low`)
  is simulated from `ActorCommand.slide` like a dash, so it predicts and
  replicates; the skin lays the pack's feet-first slide, mirrored to lead with the left leg ("Slide_L",
  `HUMAN_ANIMS["slide"]`) over the hips, legs and spine up to the chest
  by `slide_low` (`Locomotion._slide_clip`, before the legs turn to
  travel, so it slides the way the body moves); the shoulders, arms and
  head stay the stand's, so a weapon keeps its hold. A body without a
  slide clip is bent into a slide pose instead (`_slide_pose`).
  The crouch key (C) slides from a sprint and otherwise toggles the crouch
  (`PlayerController.crouch_key`), sent as the held `ActorCommand.crouch` so
  it predicts and every view sees it. `Actor.crouched` follows it but stays
  down while `room_to_stand` finds no headroom (a slide that ends under
  something low ends crouched); crouched you walk at `crouch_speed`, the
  eyes drop `crouch_eye_drop`, guns spread less (`aim_steadiness`) and bots
  sense you behind them only closer in (`crouch_sense_mult`). The body is
  `Actor.body_height()` tall (`CROUCH_HEIGHT` crouched or sliding): the
  collision capsule, `Combat.capsule_entry`, headshots and anything aiming
  at a chest use it, so low cover hides a crouched body. The skin sinks the
  model onto bent knees from `Actor.crouch` (`Locomotion._crouch_pose`, the
  landing squat's `_sink`, heels up onto the balls of the feet, a short step,
  the chest leant in) under the stand or walk, so gun carries, ADS and
  melee holds come down with the chest, in both views.
  Standing still is a relaxed stand (`idle`); a gun is held low (`idle_gun`)
  over the relaxed stand's legs and raised (`aim_gun`) only while shooting
  or aiming and briefly after.
  On the move a gun is carried, not pointed (Caleb's running pass, after
  real carries and well-liked shooters): out of a fight (`ActorSkin.in_fight`:
  shooting, aiming or reloading now, or within `aim_hold`) it sits at a
  compressed low ready at a jog, strafe or slide, both hands on a rifle,
  goes across the chest at port in a sprint (a pistol tucked muzzle down in
  one hand while the other arm pumps), bobs with the stride and lags on a
  spring as the body speeds up, stops or turns (`ActionPose.carry`,
  `sprint`, `carry_point`, `carry_turn`, `sway`; placed by
  `WeaponArm._reach_carry` from level with the eyes and in line with the
  shoulders, `_carry_anchor`, in the upright body's frame, so the gun
  keeps its place in the first-person view and both arms reach it on any
  body), and the legs run the plain run. The arms take up the run's bounce (playtest feedback: the gun
  bobbed all over the first-person view): the carry moves with the eyes
  as they are steadied (`ActorSkin.eye_steadying`, `carry_steady`) and
  follows the chest's rocking with a lag, so every carry pose must keep
  the wrist inside the arm's reach through a stride, or the gun bounces
  with the shoulder; `camera_tests.gd` (`_check_steady_on_the_run`)
  measures it. In a fight the run-and-shoot arms come back and the gun points where
  it shoots; a shot, aim or reload takes it out of the carry at once
  (`carry_out_rate`). A tap of aim is not a fight: let go without a shot,
  the gun goes back to its carry after `ActorSkin.aim_release_hold`, not
  `aim_hold` (Caleb's in-between wobble). Held up at the hip, standing or
  on the move, the gun is the anchor and the hands follow it, as in true
  first-person shooters: the wrist goes to a spot set from the steadied
  eyes along the aim (`ActionPose.hip_from_eyes`, `WeaponArm.hip_point`),
  the body blades part way into its aiming stance (`hip_stance_share`;
  a long gun's low ready by `carry_stance_share`), so the off hand reaches
  the fore end, the gun shows low in the view and the clip's arm swing
  never reaches it (the clips' own hold put the gun out past the new
  body's reach). A gun braced at the hip (`shoulders_never`, the Storm
  Cannon) is held the same way, low at the hips the way a heavy gunner
  hangs one from a sling (`hip_from_eyes_braced`), both hands on it, and
  carried low there too (`carry_low_braced`); a heavy weapon (`heavy_tags`, the power weapons) is carried level
  across the hips and never thrown up to port (`carry_low_heavy`,
  `carry_port_heavy`). A gun held on a vehicle keeps the clip's wrist
  averaged over a stride.
  `_check_hip_after_aim_tap` measures the steadiness, and
  `gun_hold_tests.gd` the off hand on the gun, the gun on the aim and the
  gun in the first-person frame through every way of moving.
  The gun has weight in the hands, all view only and the same body in both
  views: the carry's sway spring (`ActionPose._update_sway`) also takes
  the view's pitch (`sway_pitch`) and the body's rise and fall
  (`sway_vertical`, a landing throws it down by `land_dip`), and moves the
  gun held up at the hip as well as carried; a shot (`ActorSkin._on_fired`
  calls `ActionPose.kick`) drives it back and tips the muzzle up on its own
  spring (`tip`), scaled by `Gun.model_kick`, never in the sights, where
  the view has its own recoil. A wall in front of the muzzle of a gun up
  at the hip draws it in and tips it up instead of letting it through
  (`WeaponArm._check_wall`, one ray against the world every other pose
  step, only for a body being posed with its gun up; `ActionPose.blocked`,
  `wall_back`, `wall_tip`). Skins exist only where `Look` runs, so none of
  it costs a server anything. All of it is read from velocity and the command, so
  remote players match, and it is the same body in both views.
  Keeping guns out of the body: the long guns' grip sits about half a
  metre ahead of the butt, more than the body's whole arm, so the hold
  moves the body to the gun. In the sights a long gun takes a cheek weld:
  the eyes come down and over onto the stock (`ActionPose.cheek_eye`, the body bladed further, `ads_stance_long`, so the off hand still reaches a scoped gun,
  added in `ActorSkin.eye_point`, so the sights and the first-person
  camera stay on them) and the head tips with them at the neck
  (`cheek_long`, `WeaponArm.cheek`), so the butt meets the shoulder
  instead of the neck; far enough over (`cheek_eye.x`) that the butt
  sits in the shoulder pocket outside the collar. A launcher
  (`shoulder_fired_tags`, the Helion) takes no cheek weld: its tube rests
  on top of the gun shoulder beside the head, its sight
  `ActionPose.shoulder_fired` from the eyes (`sight_aside`, used by
  `WeaponArm.sight_target` and the first-person camera alike), and the
  eye looks along its side. Stood at ease out of a fight a gun is held at the
  low ready in both hands (`WeaponArm` takes `low` as a carry), lower and
  tipped further down than on the move (`carry_rest`, `ActionPose.at_ease`),
  never hung from one hand by the clip, which ran it through the arm.
  `tests/visual/clip.gd` (`--clip-only`) shoots the upper body close up
  with each hold (`CLIP_AIM_ONLY` closer on the shoulder in the sights,
  `CLIP_WIDE` the whole body), and `tests/visual/gun_moves.gd` (`--gun-moves-only`)
  films a gun through the holds as frames for a GIF, from outside and
  from the eyes. A summoned weapon's bounds (`ActionPose.model_box`) are
  measured again once it has come together (`ActorSkin._update_materialize`):
  measured while its parts flew in, every aim after a summon was off the eye.
  Check leg changes by eye: `visual_check.tscn -- <dir> --gait-only`, the
  stand with `--idle-only`, and a rifle and a pistol carried on the move
  with `--carry-only`.
  Holstered weapons are worn, not hidden (`ActorSkin.stow_place`): a primary
  gun or two-handed weapon slung across the back, outside a worn back rig
  (on a jetpack or wing pack, clamped to the flush mag-lock rail on the
  pack's back corner instead, gun right and long blade left, turned back
  behind the shoulder blade so it never covers the arm (Caleb's call:
  mounts smooth and out of the way), leaning out in a slight V, so the
  heat gauge on its back stays in view; a wing pack's rails stand on
  fairings behind its wing slots: the rig model's "MountL/R" markers, and
  the skin rests the weapon's near side on the rail; an empty rail has
  nothing sticking out), a
  sidearm muzzle down on the right hip, and a one-handed blade on the left
  hip, each moved to sit snug over the body, armor and other gear under it
  (`ActorSkin._fit_worn`, see gear.md). These are view-only copies; the weapon's own node stays on the hand.
  A switch is shown as the hand putting one away and drawing the next
  (`ActorSkin._update_switch`, reaching through `WeaponArm.override_point`),
  but only the view waits: the actor switches at once. The holster key (Z)
  sends `switch_weapon = ActorCommand.HOLSTER` and draws `Actor.last_drawn`
  again; it is an index, never a toggle, so it replicates safely. Check with
  `--holster-only`.
- People are built from parts (`core/visual/human.gd`): an "appearance" names
  a build, four parts and colours. It is cosmetic only and never trusted:
  always pass one through `Look.clean_appearance` / `Look.set_appearance`,
  which is safe on a headless server. Every person is one of two
  detailed bodies, `body_m.glb` and `body_f.glb` (Quaternius's Universal
  Base Characters), built offline by `tools/human_rig` (see the top of
  `build_rig.gd` for the command): the body cut into the four parts
  (`PartHead`, `PartBody`, `PartLegs`, `PartFeet`) on the game's bone
  names, the pack's hairstyles on the same skeleton, each vertex's rest
  place and hand share in CUSTOM0 (so `character.gdshader` draws patterns
  that stay on the body as it moves), and the clips. Never edit the
  `.glb` by hand: change the tool and build again. The clips come from the
  Universal Animation Library packs where they fit (`build_rig.gd`
  `CLIPS`; both libraries are the bought Source tiers: UAL1 with the
  8-way jog, crouch and crawl sets, UAL2 with the 8-way walk, the sword
  light and heavy combos, aerial sword, unarmed combos, vaults, wall runs,
  double jumps and the thrown-in-the-air set; every clip is in the bodies
  under its own name, ready for later passes). The empty-handed stand stands straight up (Caleb's call:
  every pack idle is a fighting stance with the feet staggered), so the tool
  builds it, "Idle_Stand" (`_stand`): the pack's A-pose, straight legs and
  feet under the hips, with the arms let down to the sides, the hands
  half closed and a slow breath in the chest. The run, the run back and
  the strafes are the pack's jog set (`JOGS`), calmed for the
  first-person view (`_calm`): the hips keep `JOG_BOUNCE` of their rise
  and fall (from 24 cm to 8 cm, about the gun run's) with the legs bent
  again to reach where the clip put the feet, the trunk keeps `JOG_SWAY`
  of its roll about the cycle's average (the hips' shift side to side
  too: the view swayed with it), and the cycle is slowed by
  `JOG_STRETCH` so a sprint lengthens the stride (the jog covers twice
  the ground a step of the old trot did). It is narrowed too (Caleb found
  it too wide): each foot lands `JOG_NARROW` nearer the middle (15 cm
  apart, not 23) and the arms swing `JOG_ARMS_IN` closer to the sides.
  The strafe right is the strafe
  left mirrored (`_mirror`): the pack's own steps shorter and measured at
  a third of the speed. The clips the game's gun poses are tuned on (the
  relaxed stand under a gun, the gun holds and the run with the gun up,
  the sword) are the old bodies' own, carried across from `rig_m.glb` and
  `rig_f.glb` (`_retarget`); the pack has no rifle clips. The old hands
  have a metacarpal bone the new ones lack, so the old `Index2` (the
  knuckle) drives the new `Index1` and so on out (`_old_bone`), and a
  finger tip with no old bone holds its rest. Those old
  stands spread the new bodies' feet wide and bow the knees, so a gun held
  low and a blade out stand on the relaxed stand's legs
  (`ActorSkin.LEGS_FROM_STAND`); the blade's ready stance is the fighting
  pose's stagger on top (`Locomotion.fight_*`). A gun raised to shoot
  keeps its clip's stance: the sights' relief is tuned on it. Worn armor
  gets room: `Locomotion.arm_clear` (meters, 0 bare; set by whoever
  dresses the body in a frame) swings each upper arm out so the elbow
  clears the plates and pouches by that much, before the weapon arm
  reaches for its grip (`_clear_arms`). The cleft between the
  glutes is filled most of the way out in the mesh (`_fill_cleft`, Caleb's
  call), so the armor is fitted to the filled body. A
  body is sized in its relaxed stand (`stand_legs`), never in an idle that
  bends the knees or spreads the feet, or the whole body grows. A glide lays the
  body out over the relaxed stand too: the pack's idles turn the chest,
  and the wings hang from it. Carrying a clip
  across keeps each bone's turn; limbs are bent to point the old way, the
  trunk and collarbones are not (bent, the chest tips and the long
  collarbone shrugs the shoulder up), and a collarbone's turn is scaled by
  how much longer it is. A foot is placed relative to how it stands in the
  old idle (the old feet are IK bones that lie differently), and a finger
  takes only how far the old one curls, about its own curl axis from the
  pack's closed hand (turned over whole, the fingers splay into a claw). An outfit no longer swaps meshes: it picks the
  hair (`Human.HAIR`) and the suit's colours (`Human.SUITS`), and the
  shader draws every surface below the head as a fitted tactical suit
  (`suit`, `suit_color`, `suit_trim`, gloves and a lit cuff;
  `Human.surface_kind` says which surfaces it covers) over the body's own
  normal and roughness maps. An armor frame recolours the same suit in its
  "suit" and "accent" colours (`ActorSkin._wear_undersuit`, view only, the
  outfit's colours given back when it comes off, the appearance
  untouched). Check by eye with `body_check.tscn -- <dir> [--suit]`.
  Online it travels in the spawn data as
  `data["look"]`; the server keeps what each signed-in player sent
  (`NetSession.look_for_peer`). `Raid` and gameplay never read it.
  A look changed while in a world (the phone's Mirror app) is checked by the
  server in `_request_look` and passed to everyone there with `_look_changed`.
  The mirror itself (`core/visual/mirror.gd`) is a client-side view: no
  collision, and nothing in `Raid` reads it. Its camera sees the head that
  your own first-person camera leaves out (`Mirror.HEAD_LAYER`).
  Players may only wear `Human.STARTER` clothes plus outfits they own:
  `Human.player_look(raw, owned)` enforces it on the profile, in the
  customizer and on the server. Better outfits are bought or earned, never
  added to the starter list. Bots use `Human.sanitize` and can wear anything.
