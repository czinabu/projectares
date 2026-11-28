# Gear: flight, artifacts, helmets, armor and backpacks

Rules for flight rigs and their thruster trails, artifacts, visors and helmets, armor frames and paints, and backpacks. These are part of the rules in `CLAUDE.md` that must not be
broken: read this file before changing anything it covers, and keep it up to
date in the same PR.

- Artifacts (DESIGN.md section 6) are data too: items tagged "artifact" in
  the optional `artifact` loadout slot, run by the one `Artifact` class
  (`core/abilities/artifact.gd`, `Actor.artifact`) whose `effect` stat picks
  what it does ("rewind", "cloak", "overclock", "bloom"), with `charges` per
  outing (0 for no limit) and a `cooldown`. One per outing: `Loadout.equip`
  attunes the first and a second is only carried as loot. It is used from
  the watch (a click on the artifact icon, `PlayerController.is_on_artifact`)
  through `ActorCommand.artifact_pressed`, so it is simulated from the
  command on every machine like an ability. It is gear (`gear_items`), so it
  drops in the bag and goes home like the rest. Every effect must be seen or
  felt by the people it touches, and in the world, never on the screen: the
  rewind trail and bloom ring are `Fx`, the cloak fades the whole body in
  `ActorSkin._update_cloak` (the same body in both views). A cloak is read
  with `Actor.is_cloaked()` by bots, nameplates and the sign-out countdown.
  A jammed rig (`FlightRig.jam`, `working()`) and an overclocked one
  (`heat_free`, `lock_up`) are rig states, not new rig types. Artifacts
  drop from world events (`WorldDef.roll_artifact`, `warlord_artifact_chance`,
  `pod_artifact_chance`), the Heart Warden's vault and the Blade
  Tournament's weekly prize (`Arena.blade_prize_artifact`) and, most of all,
  the Spore Marsh (Caleb's call: its Grey Matriarch, pods, hollows, caps
  and den).
- Flight is simulated in `Actor` from the command, like a dash, so it
  predicts and replicates: jets lit only while aim is held in the air
  (`Actor._wants_hover`, Caleb's call: never a hover that stays on by
  itself; `FlightRig.is_hovering`, flown by `Actor._simulate_hover`; the
  server repeats it in each state as `ActorCommand.STATE_HOVERING`), a
  boost started by a sprint press in the air and held on sprint, no hover
  needed (`Actor._wants_boost`), that speeds you up along the look
  direction while the skin lays the body out prone as the speed builds, and a glide whose speed is energy
  (`Actor._glide_velocity`). Every rig cruises on held sprint in the air
  (Caleb's call, DESIGN.md "Cruising"): the jetpack's boost is its cruise;
  boots skate (`Actor._wants_skate`, `_skate_velocity`,
  `_simulate_skate`, `FlightRig.is_skating`: `skate_height` over whatever
  the ray finds below, within `skate_reach`, at `skate_speed`, for
  nothing; a skate that touches down lifts straight off again, back brakes
  out); wings soar (`FlightRig.is_soaring`, `soar_accel`, `soar_climb`:
  held sprint keeps a glide going with jump let go, level at glide speed,
  on glide stamina). All three are read from the command, so clients
  predict them like the rest. The skin poses the skate as a skater, not
  the boots' flying pose (`ActorSkin.skate_legs`, `_skate_tilt`, leaning
  into the carve from the heading's swing), and keeps the glide and prone
  boost poses for the other two. Touching down out of a glide or a boost
  at speed is a run-out (`ActorSkin._run_out`): the body leans back
  against the skid (`run_out_lean`) with a shallow squat (`run_out_squat`)
  until it slows, never pitched forward onto the ground, and the legs brace
  in a skid on the feet (`Locomotion.skid`, `_skid_pose`: the lead leg out
  ahead nearly straight, the trailing leg bent under, the back straightened),
  shown in place of the slide when a wings landing slides. Check by eye with
  `--flight-only` (run with `--fixed-fps 60`; it waits out each tick's step
  so a press on any tick lands; `wings_glide_side` and `jetpack_land_side`
  see the run-outs square from the side). Each rig has one job and one weakness
  (Caleb's balance pass, DESIGN.md section 5; the Mk1 numbers are
  `ItemDB.JETPACK_MK1`, `BOOTS_MK1` and `WINGS_MK1`, measured by
  `tests/rig_balance_tests.gd`): the jetpack is height and hover (8 s on a
  full bar, climbing 1.3x the heat, a 40 m ceiling, steady aim), its prone
  boost its cruise (Caleb's call: 16 m/s at 0.18x, about 45 s and 720 m a
  bar, a climb in it costs the climb's heat) paid for in the fight, not in heat: aim or
  the trigger held brings you upright into a hover (`Actor._wants_boost`,
  `_boost_flare`, the jets held while the trigger is) and a gun waits out
  `sprint_out_time` as out of a sprint, and free look (E) holds the boost's
  heading (`_boost_yaw`) like the wings'; it is loud and clumsy under a roof;
  the boots are ground agility and stealth: no heat, `max_charges` pay for
  kicks and dashes, a short skim (`skim_time`), a free skate, faster on foot
  (`ground_speed_mult`), no fall damage, a graze window on every dash
  (`Actor.graze_left`, checked in `Actor.modify_incoming`), but a 10 m
  ceiling; the wings are distance and speed: a launch, a fast glide on glide
  stamina (`glide_heat`, refilled on the ground only), a level soar on it
  and two boosts a flight, but no hover and only a slow climb in a soar, poor aim, sidearm only, and
  no use indoors. A rig's `scan_range` is how far scans and thermal pick
  its wearer up (`Visor.reach_to`), `indoor_mult` how well it flies with a
  roof overhead (`FlightRig.indoors`, probed by `Actor._measure_indoors`),
  `flight_aim` its air spread in its own flight (`Actor.air_aim`) and
  `fall_damage_mult` its share of fall damage (`Actor._hurt_by_fall`, out
  in a world only, through `Combat.deal`). Rigs come in tiers (Caleb's
  call): Mk1 to Mk3 of each, made with `ItemDB._rig_tier`, which scales
  only the stats in the rig's `ItemDB.RIG_STRENGTH` list by
  `RIG_TIER_STEP` (about 15% a tier, a charge a tier for boots): a tier
  improves the rig's strength, never its weakness, and the heat bar stays
  100. A rig's `ceiling` is measured
  from the world's ground, never a roof (`Actor.ground_level`: the map's
  `ground_height`, else its origin; the home base is its own ground),
  unless the world has that rig count from the floor its wearer last stood
  on (`WorldDef.rig_ceiling_from_floor`: the Basalt Rift's boots), and
  only limits lift: the climb eases
  off under it (`FlightRig.climb_room`) and a kick, launch or boost is cut
  to top out on it (`lift_cap`), or refused. A world's updrafts
  (`WorldDef.updraft_at`, the Basalt Rift's vents) carry a body up on top
  of whatever its rig does, past the ceiling (`Actor._ride_updraft`), and
  wings spend no glide stamina in one (`FlightRig.in_updraft`); see
  docs/systems/rift.md. Only Mk1 drops or
  is sold: Mk2 and up are crafted from blueprints (DESIGN.md section 10),
  so no loot table may list them.
  The keys fly every rig and the mouse only looks and aims
  (Caleb's call), with one exception: wings fly where you look, like a
  bird's (Caleb's call, so you never fly sideways to your view). They bank
  round onto the view's heading (`Actor.glide_steer`), the strafe keys roll
  a harder turn, and forward and back dive or pull up (`Actor.glide_trim`),
  never the view's pitch. Holding free look (E, `ActorCommand.free_look`,
  Caleb's call) the wings fly straight on and the view looks and aims
  anywhere; let go and they come round onto the view. In free look the
  body twists round its length to face the view, so looking behind lays it
  on its back, a backstroke, to shoot behind (`ActorSkin._look_roll`, view
  only; check with `visual_check.tscn -- <dir> --flight-only`). A glide flies like a wing (`Actor._glide_velocity`):
  speed is momentum, a turn costs speed, a bank sinks faster, pulling up in a
  turn tightens it, and below the stall speed the wings stall
  (`Actor.glide_stalled`: they barely turn and drop at `stall_sink` until the
  nose drops and the speed comes back). Gliding, Shift is a wing boost
  instead of a dash (`FlightRig.glide_boost`): it thrusts you the way you
  face and the glide keeps that speed, and Shift + S boosts upward
  (`glide_boost_climb`); wings never dash sideways. The glide's attitude is
  held in the world while the view turns, so spinning the camera never
  drags the body round (`ActorSkin._update_glide`). And a jetpack boost
  runs along the view's heading, climbing only on jump and descend, never
  on the view's pitch.
  Every rig air dashes on Shift + a move key (`ActorCommand.sprint_pressed`,
  `Actor._air_dash`, tuned by the rig's `air_dash_*` stats): the dash is
  added on top of the rig's own flight and taken back off, so a glide or a
  cruise carries on after it. Q and E fly nothing (Caleb's call); E holds free look and Q is the melee weapon's ability.
  The body's attitude in the air (flat, banked, leaning, barrel rolled by a
  sideways air dash) is the skin's job (`ActorSkin._update_glide`; a boost's
  prone pose eases in and out by `boost_ease`, so coming upright into a
  hover never snaps, Caleb's feedback), read
  from velocity and the simulated actor only, so remote players match. Boots
  show their thrust (`ActorSkin._update_boot_thrust`): the body leans into
  the push (gravity, drag and speeding up), the legs and swivelling flames
  fire down the exhaust, and flying forward lies the body out near flat with
  the legs dropped so the heel jets fire down and back (never fully flat,
  or nothing would hold you up). Off the
  ground (`ActorSkin.is_airborne`, from `Actor.airborne_time`) the legs
  never play a gait: a stand plays under an air pose (leap, fall, or
  hanging from lit jets: legs nearly straight under the body, toes
  pointed, one a little behind the other, `hang_legs`). Leaving the ground starts with a short push-off
  and a running jump leans into it; a touchdown (`Actor.landed`) bends the
  knees by how hard it was (`Locomotion.squat`). All of it is view only. A boost keeps the arms down at the sides, never
  reaching ahead (Caleb's call). Check it by eye:
  `visual_check.tscn -- <dir> --flight-only` (or `--takeoff-only`), or
  quicker while tuning, `--air-only`: one sheet of the hover, a drift, a
  boost, a glide, boots and a fall, taking `name=value` overrides of the
  skin's tuning vars (`air_toes=0.9`) and `only=hover,glide`.
- Helmets are items tagged `helmet` in the `helmet` loadout slot, and data
  like abilities: `Visor` (`core/abilities/visor.gd`, `Actor.visor`) is one
  class whose `mode` stat picks what the visor does ("" plain, "zoom"
  binoculars, "scan" pulse, "threat" tactical, "thermal"). It is driven by
  `ActorCommand.visor_pressed` (a press: scan, Threat Sense) and
  `ActorCommand.visor_level` (held: the zoom level, thermal on).
  What a visor reveals is decided by the authority only and never goes to
  everyone: `NetSession` sends a scan's snapshots to the scanner, the ping to
  each player caught, a tag to the tagger's side, and a tactical visor's
  hit direction and Threat Sense list to its wearer. Reveals must stay fair:
  a scan is a snapshot, never live tracking, Threat Sense only shows people
  aiming at the wearer, thermal never sees through walls, and every reveal
  is felt by its target (the ping, the "Sensed" notice, the lens glint, the
  ember of a thermal visor), except where nobody can be fought
  (`Visor.peaceful`: a safe zone or the home base), where the ping and the
  "Sensed" notice are left out as noise. How warm someone looks on thermal is
  `Visor.heat_of`: `Actor.heat_signature` (frames set it with a
  `heat_signature` stat) plus flight rig heat. The picture is `VisorHud`
  (`core/ui/visor_hud.gd`), a view: its glass is drawn in first person only
  and only while a helmet is worn, wherever it is worn: worlds, the plaza,
  the arena and the home base (`BaseHud.visor`, `VisorHud.setup_base`;
  Caleb's call) (Caleb agreed a visor counts as in-world,
  since you look through it); what a visor shows out in the world (snapshots,
  tag markers, pulse rings, glints) is there in either view. The glass is thin
  projected light, never a frame, a tint or a mask over the view (playtest
  feedback: the first visors were in the way): it rests dim, trails the
  head, wakes on trouble (`VisorHud.alert`) and closes on what is aimed at
  (`VisorHud.lock`). Neither view is better informed (Caleb's call): in
  third person the glass itself (its rim, a scrap visor's cracks, the trail
  behind your turns) is gone, but every readout it carries is drawn flat
  in the same places (`VisorHud.flat_shown`), thermal included, and the helmet wears
  its health strip and system light on the back of the head
  (`ActorSkin._update_vitals`, `helmet_light`), where a pack or a slung gun
  never covers them. The glass hugs
  its rim and keeps the middle clear (Caleb's redesign, from a reference he
  liked, made our own: never copy any one game's look). It carries your
  always-in-view readings as a row of hex cells along the lower left curve,
  each filling like a gauge with its number over it (health, armor,
  stamina, with a flight rig its heat and cue, the ability;
  `VisorHud.vital_cells`), and under the middle of the lower rim the
  landing warning (`Hud.landing_warning`: the rig about to cut out while a
  fall from there would hurt; `VisorHud._draw_landing`, and the pack
  screen's word turns to LAND, DESIGN.md section 5). Every working helmet also has a heading tape across
  the top, bowed with the glass, that marks only what the wearer is already
  told (`VisorHud.compass_marks`): squadmates (`VisorHud.squadmate`: a player in
  the same clan, or everyone where `WorldDef.players_allied`; never a bot or
  an enemy), the side's pings and the nearest depot, plus each helmet's own
  finds (Spotter tags, Seeker scan snapshots, Warden the war's hot zone).
  The same marks are plotted round you on a small contact scope top left
  (`scope_points`; never ground or walls, it is not a map), with the
  helmet's name, role and system beside it; the contracts held and the
  tour's step are an objective block top right (`objective_lines`, from
  `hud.contracts` and `hud.objective`); faint pitch ticks run up both edges.
  Loot is read off the glass too (Caleb's call, DESIGN.md "Loot at a
  glance"): the container you look at gets a tag listing every item inside,
  with rarity and whether it beats what you wear (`VisorHud._draw_crate`,
  `loot_rows`, `versus_worn`), and what you pick up runs up a fading feed
  over the weapon readout (`_draw_pickups`), fed by `Actor.looted`, which
  only the authority emits and `NetSession._looted` repeats to the owner.
  Bottom right, mirroring the vitals, a quiet weapon readout (Caleb's pick):
  the weapon in hand, the mag over a tick a round and the pack's rounds,
  resting dim and lit only on a reload, a low mag or just after a switch
  (`VisorHud.weapon_awake`); ammo is still read off the gun's own counter.
  Each helmet has a role it names as it comes on (`role_name`) and its own
  reticle; an Ember also reads its wearer's own heat signature. A scrap
  visor manages only a bearing. Do not put the map or standing there, they
  stay on the watch. Mk2
  helmets are never sold or dropped: like rigs, they are crafted from
  blueprints (DESIGN.md section 10), so no loot table may list them. Check the glass by eye with
  `visual_check.tscn -- <dir> --visors-only`.
  A worn helmet can come off onto the hip (Caleb's call, DESIGN.md
  "Helmet off"): its own key
  (K, the "helmet" action, Caleb's ask; it is no longer on the watch) toggles the held
  `ActorCommand.helmet_off` (`PlayerController.toggle_helmet`), which
  `Actor.helmet_stow` follows (`_simulate_helmet`), so it predicts and
  everyone sees it. Off the face the visor does nothing
  (`Visor.stowed`; ask `Visor.working()`, never `enabled`, for whether a
  visor shows or senses), but the helmet stays worn gear. The skin moves
  the one model from the head to the off hand to its clip at the back of
  the left hip (`ActorSkin._place_helmet`, `helmet_clip`) and the off arm
  reaches for it (`ActionPose.helmet_hand`, `WeaponArm._off_goal`), with
  the weapon hand helping it off the head (`ActionPose.helmet_both`; it
  takes both hands, so `toggle_helmet` puts a drawn weapon away first), the
  same in both views; the face shows while it is off. It goes back on by
  itself when a new helmet goes on and on stepping out where people fight
  (`PlayerController._keep_helmet`). Check by eye with
  `visual_check.tscn -- <dir> --helmet-off-only`.
  Every worn helmet has a lamp on the right of its brow (Caleb's ask): its
  own key (J, the "lamp" action) toggles the held `ActorCommand.lamp`
  (`PlayerController.toggle_lamp`), so the server relays it and everyone
  sees the beam. `Actor.lamp_lit` says when it shines: switched on, the
  helmet on the head and its wearer alive. Clipped to the hip it goes dark
  but stays switched on, and lights again when the helmet goes back on;
  bare-headed there is nothing to switch. The barrel and lens are on the
  one helmet model (`ActorSkin._build_lamp`); the beam is a spot light kept
  off the skeleton, so first person never leaves it out, aimed along
  `Actor.get_aim_dir` from just ahead of the lens (`_update_lamp`, view
  only, tuned by `lamp_*`), fading out for far viewers. Check by eye with
  `visual_check.tscn -- <dir> --helmet-lamp-only`.
  A helmet is worn gear, not a flag: `Loadout.wear_helmet` is the one way
  one goes on or comes off (it resets the visor, keeps `gear_items` right
  and emits `Actor.helmet_changed`). Mid-raid, helmets in the pack
  are put on from the watch's pack list (`PlayerController.take_picked_from_pack`),
  and a click on one goes through the summon
  (`Raid.summon`, online `NetSession.summon`) to `Raid.swap_worn`
  (authority only, at once, then a short watch rest): it goes on and the
  worn one goes in the pack; `_worn_changed` tells every client. The skin wears it on the
  head (`ActorSkin._update_helmet`, `build_helmet`), hiding the head under it; it
  hangs off the "Head" bone, so first person leaves it out with the head.
  Each helmet looks like what it does and is its own original design
  (Caleb's call: sci-fi soldier and cyberpunk, tall rather than flat or
  wide; `helmet_model.gd`): a dark hood under a shell with a real outline
  (a superellipsoid, never a ball), sized to the head per axis
  (`ActorSkin.helmet_size`). The scrap visor ("Junker") is a riveted
  bucket with a gas mask, filter cans and one cracked round goggle; the
  Spotter a sleek visor with a side rangefinder, ear pods and antennas;
  the Seeker a faceted face with three lit slits, ribbed ear plates and a
  crown emitter; the Warden an angular prow with a chevron visor, sensor
  eyes, swept blades and neck lames; the Ember a tall ceramic shell with
  one thermal eye, a snout with hoses, fins and heat sinks. Glass is dark
  and reflective, never a glowing panel; a Mk2 (`Visor.tier`) wears a lit
  seam over the crown. Worn with an armor frame, every helmet but the
  scrap visor takes the frame's plate, trim and fabric colours in its
  paint (`ActorSkin.helmet_colors`), so helmet and plates read as one kit.
  Every helmet and armor piece is built from
  `GearShapes` (`core/visual/gear_shapes.gd`), merged into one mesh per
  material (`GearShapes.merge`: "Gear", and "Glass" with no shadow; the
  parts it was made of in its "parts" meta, `has_part`) and built once
  per kind, then shared (`GearShapes.cached`). Keep
  the back of the head clear for the vitals strip. Goggles will be the
  same glass and fitting on a strap, no shell. Check by eye with
  `visual_check.tscn -- <dir> --helmets-only` (helmet_closeups.png).
  Armor frames are worn gear the same way: `Loadout.wear_frame` puts one on
  or off (`Actor.frame_id`), undoing the old frame's thermal signature
  before applying the new one (how a frame slows you and heats your rig is
  its weight, `docs/systems/carry-weight.md`), and emits `Actor.frame_changed`. One frame is
  worn; another in a kit is carried. A frame in the pack is put on from the
  pack list too and goes through `Raid.swap_worn`. Both go on at once and
  then the watch rests (`Loadout.SUMMON_TIMES` "helmet", short, and
  "armor", long), and a frame taken off keeps its armor left in
  `Actor.stowed_armor`, so spare plates are no instant refill. The skin
  wears the whole kit (`ActorSkin._update_frame`, `armor_model.gd`): a
  plate carrier on the chest (`build_frame`), a battle belt on the hips
  (`build_belt`) and on each side a segmented shoulder pad (`build_pad`),
  an elbow pad and bracer (`build_bracer`), a thigh plate (`build_tasset`,
  a drop-leg pouch on the right) and a knee pad and shin guard
  (`build_shin`), each on the bone it moves with (`_hang_limb` turns a
  limb piece along its limb), the same body in both views, over the
  undersuit, and on the base's armor stands (`HomeBase._build_armor`).
  Plates are fitted, never boxes (Caleb's call): each piece is laid over
  the measured body (`GearShapes.sheet` over `body_fit.gd`'s reach), so
  it follows that build ("m" or "f") with no gap and no clipping. Each
  `Human.BUILDS` body is measured by `tools/body_fit` into
  `body_fit_data.gd`: the trunk in every stance a person stands in, put
  back where the bone its piece hangs on stands at rest (the widest of
  them, its hollows bridged), and each limb along its bone at rest. Run it
  again whenever the bodies change. Pieces are built in the rig's own
  metres and scaled with the body (`ActorSkin._body_scale`), and cached
  per build. Straps and collars go over the tops of the shoulders by a
  ray cast (`Trunk.cast`), a shoulder cap lifts off the trunk in every
  stance its arm hangs in (`Limb.wrap` `clear`), a shoulder pad on an
  arm slimmer than Build A's stands off it by the difference
  (`ArmorModel.arm_shortfall`), so it is as broad on every build instead
  of shrinking to a slim shoulder (Caleb: Build B's read a third
  smaller), and starts that much further out, clear of the collar.
  Proportions by weight (Caleb's pass: the shoulders carry the
  silhouette): a medium pad stands off further than a light one, thigh
  plates stay narrower than the leg is round on light and medium, and
  heavy is more armor, not more width (Caleb: wide caps over bare limbs
  read disproportionate). A heavy pad stands no further off than
  medium's, but its rerebrace runs from under the lames to the elbow,
  flared at the top to meet them, and its vambrace starts at the elbow
  cop, so each arm reads plated its whole length; its cuirass sits as
  close as a medium frame's plates; a piece reaching past a
  knee or elbow goes over the limb above it, and plates layer in a fixed
  order (carrier, then straps, then plates, then what is mounted on
  them) so none cuts through another. `tools/armor_fit/clip_check.tscn`
  tests every piece against every other piece, against the body and
  plate against plate within a piece, on both builds in every stance,
  and must report 0 clashes after any change to the armor or the bodies.
  An arm meeting the armor in a stance is the stance's to keep clear, so
  it is counted apart (`--arms`). Everything else worn goes over the body
  and the armor as they are (`ActorSkin._fit_worn`, `worn_fit.gd`): a
  back rig is moved back until it sits snug over the back or the armor,
  with its shoulder straps laid over whatever is there in place of the
  rig model's own ("Straps"), then a backpack, then the weapons slung on
  the back, each pushed back over what came before; a weapon clamped to
  a rig's rail moves with the rig, and a sidearm, a hip blade and a
  clipped helmet are pushed out to their side. Worked out once per kit
  and build from the body at rest, so a new piece of gear or a new place
  for one needs no numbers of its own. Rigs and packs are read as points
  over the boxes round their meshes, weapons and armor over their faces
  (`WornFit.cloud`, thinned and kept per model), and the body and the
  body in each frame are measured once each; a new kit costs a few tens
  of milliseconds once, at most one a frame. `tools/armor_fit/gear_check.tscn`
  wears every frame (and none) with every kind of rig, the weapons put
  away, a backpack and a helmet on the belt on both builds, tests every
  piece of gear against the armor, the body and the other gear, and must
  report 0 clashes after any change to gear, armor or where gear is worn
  (a hand or the weapon in it is counted apart, `--arms`). It needs a
  display or xvfb: headless no body is dressed, and it exits 1 rather
  than report an empty 0; see it with
  `visual_check.tscn -- <dir> --gear-only`. The kit: a fabric carrier with straps,
  webbing and pouches under curved, bevelled plates, a padded battle belt
  under a webbing belt on every frame, and a cloth seat over the backside
  that spans the cleft instead of hugging it (no plates on the backside,
  Caleb's call). Weight reads at a glance: the frame's weight tag
  picks its coverage (`ActorSkin.FRAME_BULK`), light a slim carrier,
  caps and knee pads, medium the full kit with a cummerbund and an upper
  arm plate, heavy layered plate with abdominal lames, a gorget, faulds
  and greaves that widens the shoulders, so a frame moved to another
  weight tier changes bulk with it. Each frame also has a look of its own
  that fits what it does (`FRAME_LOOKS` to `FRAME_STYLES`: plate,
  carrier, strap, undersuit, accent and metal colours, and details such
  as the Runner's cool back panel, the Trooper's radio and hydration
  carrier or the Bulwark's hot back vents); a new frame gets a
  `FRAME_LOOKS` entry (a test checks it). Frames can be painted
  (DESIGN.md "Armor paints", Caleb's call): `ArmorPaint`
  (`core/visual/armor_paint.gd`) is a row of the colour keys only, held in
  a safe range (`ArmorPaint.SAFE`), laid over a look by `frame_style`, so a
  paint never changes stats, shape, metal, details or glow strength. A
  paint is a cosmetic item tagged "paint" (the Tailor sells the plain
  ones; earned ones are Relic loot from `WorldDef.warlord_paint` and a
  world's own tables, never sold or traded), unlocked as "paint:<id>" by
  `Economy.unlocked_outfits`, and the choice (frame look to paint) rides in
  the appearance's "paints", so `Human.player_look` checks it like clothing
  and it travels wherever a look does. It is picked at the base's armor
  stands (`HomeBase.PaintSwatch`, `paint_requested`, `show_paints`).
  Check by eye with
  `visual_check.tscn -- <dir> --armor-only`.
- Flight rig models (`core/visual/rig_model.gd`) are one size for both
  builds, hung snug by the fitter above. The plate a back rig rests on
  (`RigModel.HARNESS`) is a mid grey, never the pack's dark trim: dark, it
  reads as a gap between the back and the pack in a side view. Check by
  eye with `GEAR_BUILD=m` and `f` on `--gear-only`, and run
  `tools/armor_fit/gear_check.tscn` (0 clashes) after a rig model change.
- Thruster trails (DESIGN.md "Thruster trails"): `RigTrail`
  (`core/visual/rig_trail.gd`) colours the flames of every rig worn, a
  glow and a core held in a safe range (`RigTrail.SAFE`), and never a stat
  or the flame's size. `Vfx.nozzle_flame` takes the trail and
  `ActorSkin._wear_rig` passes the body's (`rig_trail`); "" is the factory
  blue, and a chosen trail burns `TRAIL_DIM` as bright so its colour
  reads. A trail is a cosmetic item tagged "trail" (the Tailor sells the
  plain ones; the earned ones are Relic loot, never sold or traded),
  unlocked as "trail:<id>" by `Economy.unlocked_outfits`; the choice (one
  id) rides in the appearance's "trail", checked by `Human.player_look`.
  It is picked at the base's rig stands (`HomeBase.TrailSwatch`,
  `trail_requested`, `show_trail`), whose nozzles glow in it. Check with
  `tests/rig_trail_tests.gd` and by eye with `--trails-only`.
- Backpacks (DESIGN.md "Backpacks") are data: items tagged "backpack" in the
  optional `pack` loadout slot, with `capacity`, `weight` and
  `pack_size` stats. `Loadout.wear_pack` sets `Actor.pack_id` and the
  inventory's capacity (`Loadout.FIELD_PACK`, 12, with none); it scales no
  speed of its own: the pack and what is in it count toward the carry
  weight (`docs/systems/carry-weight.md`). `equip` wears the first and only
  carries a second; `refit` follows the kit at home. A smaller pack never
  throws items out: a pack over its capacity just takes no more. The pack
  is gear (`gear_items`), so it drops with you. It is not put on from the
  watch's pack list mid-life. The worn model is `ActorSkin.build_backpack`
  hung on the hips (`_update_pack`, `pack_offset`, lower under a back rig
  by `pack_rig_shift`, and back over whatever is there by `_fit_worn`), merged like other worn pieces and
  shadowless when far; the gear room hangs the same model on hooks
  (`BaseLayout` kind `pack_hooks`). Sold by the Outfitter (`ShopDB`).
