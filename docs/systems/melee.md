# Melee

Rules for melee types, techniques, the one button, timing, guards, feints, the kick and the dodge. These are part of the rules in `CLAUDE.md` that must not be
broken: read this file before changing anything it covers, and keep it up to
date in the same PR.

- Melee types differ only by item stats on the one `MeleeWeapon` class:
  `backstab_mult` (knife), `guard_crush` (axe, carried on
  `DamageInfo.guard_mult`), `vertical_reach`, `close_range`/`close_mult` and
  `heavy_stagger` (spear). Their defaults change nothing. Add a melee type as
  data plus a `Look.MELEE_MODELS` entry, not as a new class. Every melee item
  carries exactly one hold tag, "one_handed" or "two_handed"
  (`MeleeWeapon.is_two_handed_id`): it sets the walk speed with it in hand,
  makes a two-hander's heavies stagger and break armor, and is what
  `Look.is_two_handed` (the one place views ask) answers for the grip.
  Every melee weapon spends one budget its own way (Caleb's calls: weapons
  differ in damage, and rarity buys a more unusual trait, never more power;
  DESIGN.md "What each axis means"). The slower the type, the harder each
  hit (hammer, axe, sword, knife), and the hammer swings widest; a slow,
  readable windup lands less often, so it pays for the damage. The score is
  damage a second, times how often a swing lands, times reach, area (arc)
  and traits (`melee_balance_tests.gd`, its weights a first guess for
  playtesting), and every melee item, world ones too, scores within `BAND`
  of the scrap blade; no heavy kills an unarmored person in one blow. A swing
  hits everyone in its arc and reach at full damage, so the arc is the area
  stat. A new or retuned weapon must fit the band; how a bot fights with each
  one: `duel_bench.tscn -- --melee <id>`. A weapon ability counts in the
  traits too (`ABILITY_WEIGHTS`).
- Weapon abilities are data: the item's `ability` stat picks one on
  `MeleeWeapon`, fired by its own press (`ActorCommand.weapon_ability_pressed`,
  Q or the mouse's thumb button, `MeleeWeapon.weapon_ability`) and spent for
  `ability_cooldown` from the press. The first is the Breaker Hammer's
  "ground_pound": a windup longer than its heavy, the hammer driven into the
  ground (`swing_arc` reaches the ground at the hit), and a ring
  (`ability_radius`) through everyone on the ground near: a little damage
  through `Combat.deal` as a melee hit, so a guard stops it and a parry
  staggers the pounder, then a knockdown and a shove out and up
  (`ability_knockdown`, `ability_knock`, `ability_lift`). Anyone more than
  `POUND_HEIGHT` above rides over it. A knockdown (`Actor.knock_down`) is a
  stagger that also stops walking; the server sends it in the state
  (`ActorCommand.STATE_KNOCKED_DOWN`, past bit 31, so states only) and
  `ActorSkin._show_knocked_down` plays the death clip's fall, holds it and
  plays it back up, timed by what is left. A bot pounds when the pound is
  ready and a second foe stands in its ring, now and then on one alone
  (`BotBrain._wants_pound`, asked only as a hammer bot picks a swing). Check with
  `visual_check.tscn -- <dir> --moves-only weapon=<id> only=ability`
  (bots stand where the ability needs them; `frames` for a clip).
  Every melee type has one (`MeleeWeapon.ABILITY_NAMES`), each weighted
  alike in the budget so none buys power with it: the knife's
  "shadow_step" (a crouch, then through to just behind the foe in front,
  turned to their back through `Actor.turn_request`, which the player's
  controller takes as the view's yaw; nothing in front, no cost), the
  swords' "counter_stance" (the guard shown for `ability_windup`; a melee
  hit from the front is parried there and answered by a quick riposte,
  `_counter`, ahead of the plain guard in `modify_incoming`; a kick still
  goes through), the axes' "guard_hook" (kind "hook": through any guard,
  tearing a held one open, a pull a step in; a dodge slips it), the
  spears' "vault" (planted, then up and ahead, the heavy from the top a dive
  slam or air-lunge) and the hook blade's "trip" (a blockable low cut that
  knocks down). Bots use all but the vault (`BotBrain._wants_ability`).
  Melee is made to answer guns (DESIGN.md "Melee against guns"): blades go
  past armor (`DamageInfo.armor_pierce`), a heavy started sprinting is a
  dash-strike (`dash_range`; with `dash_through`, a charge that runs its
  whole length past a foe who steps aside), a light while moving back at a foe behind is a
  back strike, and a fresh guard deflects small-arms rounds for
  `deflect_window`, rearming after `guard_rearm`; a gun's round carries its
  `DamageInfo.weapon_id` and `undeflectable_tags` (marksman, power) go
  through any guard. Noise is `Combat.noise`, which only guns call (a person's
  shot, at most every `Gun.noise_every`): patrolling bots hear it through
  `Actor.heard`. Never make a blade call it; melee kills are silent.
  Each weapon fights its own way (Caleb's call: every attack and guard
  matches how the weapon is really used; view only). Its `swing_style`
  ("slash", "thrust", "chop", "cut"), `heavy_style`, hold and hands pick a
  technique (`ActionPose.technique`): a table in `ActionPose.techniques` of
  keyed swings per side (and a heavy from the middle) and a guard per side.
  Each swing is three keys, windup, contact and follow-through, each the
  weapon hand and the way the blade goes, so the blade turns through the
  cut edge first (`technique_blade`, `keyed_reach`) and every strike meets
  the foe in front of the chest where the eyes see it; each guard holds the
  weapon across its side in front of the body. The sword cuts diagonally
  and thrusts for its heavy, the axe chops from high behind the shoulder,
  the knife slashes short in a forward grip and stabs for its heavy, the
  hammer is hauled over in both hands, the spear thrusts from the hip, and
  the katana keeps its kenjutsu cuts (kesa-giri, gyaku-kesa, shomen and a
  tsuki, both hands on the handle). The katana (the Arc Blade) is a
  two-hander in play too (Caleb's call): tagged "two_handed", it walks at
  the two-hand speed and its heavies stagger and break armor. It is the one
  two-hander not carried across the body (`Look.is_carried`): it keeps its
  ready hold, the hilt in front of the body's middle where the off hand
  can close on it, and the off hand never leaves the hilt. With no handle
  read off its shape, its off hand's place is a hand's width under the
  table grip (`Look._melee_model`). The Marsh
  Hookblade is a one-hander with a look of its own ("hookblade" tag, its
  `Look.MELEE_MODELS` row): the plain sword with its point curled back over
  the spine into a hook (`Look._hook_bits`), held and swung like a sword. `swing_scale` draws a small weapon's keys in toward
  the middle (`swing_centre`). A new melee weapon picks a style, or a new
  technique gets a table; `view_match_tests.gd` (`_check_techniques`)
  checks that every weapon's strikes are in view and its guards show their
  side. Every swing leads with the weapon's striking face (an axe's bit, a
  hammer's face, a blade's edge): each model is turned about its length so
  that face points along `Look.STRIKE_FACE`, the way `ActionPose.cut_edge`
  says every technique leads, from the face the model has in its own space
  (the last field of its `MELEE_MODELS` entry; a pack model may face any
  way across, so it is read from the model, never assumed). The edge turns
  toward where the tip actually travels, the hand's path and the blade's
  turn together (`ActionPose._blade_at`). The arm keeps it there: the
  forearm rolls the fist round toward the blade before the wrist bends
  (`WeaponArm.forearm_roll_limit`, keeping the way it last rolled near a
  half turn, `roll_keep`, so a guard held on the move never flips each
  stride, and keeping most of the roll it had while the blade lies nearly
  along the forearm, where the roll is barely defined and could throw the
  hand across mid-swing), and the handle turns in the fist so the face matches the
  technique (`WeaponArm._face_strike`). `melee_orientation_tests.gd` plays
  every swing of every melee weapon and checks the face leads through the
  hit, and `melee_guard_move_tests.gd` that a guard holds steady on the
  move; a new melee model needs its face and an entry in both.
  `ActionPose.windup_reach`/`follow_reach` and
  `MeleeWeapon._animate` read `style_now()`. The shown swing starts
  `SWING_LEAD` before the strike and speeds into it, half its arc at the
  hit, then eases out (`MeleeWeapon.swing_arc`; both views read it); a
  windup keeps coiling back (`windup_coil`); two-handers swing slower and
  turn the body more, hold their follow-through longer (`ActionPose.two_hand_follow`,
  `TWO_HAND_RECOVER_HOLD`: the first part of the recovery stays down in the
  swing's weight before hauling back up) and pause longer on a landed hit
  (`MeleeWeapon.TWO_HAND_HITSTOP`; `melee_weight_tests.gd`). A new melee weapon picks a style; check it by eye with
  `visual_check.tscn -- <dir> --swing-only` (run with `--fixed-fps 60`),
  which films each move frame by frame, or quicker, one weapon's stance,
  swings and guards from the front, the side and the eyes at once with
  `--technique-only <item id>`. Every melee
  model is dressed as tech by `Look._tech_melee` (`assets/shaders/melee.gdshader`):
  bare metal becomes alloy with an energy edge in the weapon's rarity color,
  wood and wraps black polymer with glowing seams. The edge runs across the
  length the mesh actually lies along (`Look.blade_axes`, `_up_axis`; a
  pack mesh may lie along Z), the flat of a blade stays alloy, and a hammer
  has no edge. Guns wear the same house finish (the weapon pass, to sit with
  the sci-fi armor, helmets and vehicles): `Look._dress_gun` turns a pack
  model's dark parts graphite (`GUN_FRAME`), its light parts ceramic
  (`GUN_SHELL`; worn tan on the scrap rifle) and its warm parts the gun's
  `GUN_GLOW` colour, lit softly, never a whole part aglow; each gun then
  wears its own kit (`Look._gun_kit`: coils, cells, a drum, a shell carrier),
  under a "Kit" node that `_measure_mounts` skips, so a kit never moves a
  grip, a sight or the muzzle. Power weapons are built in the same finish
  (`_power_model`). Compare every weapon side on with
  `visual_check.tscn -- <dir> --arsenal-only` (`ARSENAL_IDS` picks rows). The scrap kit's blade
  (`starter`) is a sword made from scrap (Caleb's call): `Look._scrap_bits`
  welds crooked patch plates and rivets on the blade, winds wire round the
  grip and threads a nut on for a pommel, and it runs dim and worn
  (`scrap_energy`, `scrap_wear`). A holstered blade is worn
  folded away (the last field of its `MELEE_MODELS` entry: "blade" draws the
  blade into the hilt, "telescope" slides a spear shaft into itself) and
  slides out once drawn (`Look.set_extend`, timed by `ActorSkin._update_fold`).
  Folding is done in the shader's vertex step, so it is view-only.
- Melee attacks share one button (Caleb's call): a tap of `ActorCommand.primary`
  is a light attack, released before `MeleeWeapon.hold_time`; holding past it
  starts the heavy (a dive slam in the air) with its full visible windup. A bare
  `primary_pressed` with no hold is a light (how bots swing), and
  `tertiary_pressed` still asks for a heavy outright, but no key binds it.
  A press made while the blade is busy is kept (`press_buffer`) and plays
  once it is free, and the time a tap was held counts toward its windup (down
  to `light_windup_floor`). A heavy lunges at the foe in front and stops at
  striking distance (`heavy_lunge` is its speed through the windup); in the
  air, at an airborne foe in the aim cone, it is the magnetic air-lunge
  (`air_lunge_range`) instead of a slam. Lunges are held by
  `MeleeWeapon._carry_lunge` from the command and the foe's position as the
  attacker saw it (`Combat.positions_seen_by`), so they predict online.
  A strike that reaches someone emits `MeleeWeapon.contact` on every machine
  it is simulated on, with a local guess at the guard; the attacker's view
  answers that (sound, `PlayerController.kick_view`, a hitstop of the blade's
  pose) at once, and the server's `hit_confirmed` only drives the hit marker.
- Melee is timing, not sides (Caleb's call, DESIGN.md "Melee duels"): the
  blade picks its own sides (`MeleeWeapon.next_stance`: a light combo runs
  right, left, over the top; a heavy comes over the top, or from the side
  straight off a light), and a guard turns to meet whatever comes from the
  front (`_guard_toward`, `guard_dir` set by the hit), so nothing matches a
  side and `ActorCommand.stance` is unused. A swing still goes toward its
  stance (`attack_dir` is `swing_from(stance)`), and windup and guard poses
  must show their side; `threat_dir()` is what a defender reads. What a
  guard does is timing: a parry in `parry_window`, a timed block in
  `timed_window` for `timed_block_cost` of the stamina, and a guard held
  longer drains (`_drain_held_guard`); a guard raised straight after one
  that met nothing is not timed (`guard_rearm`), one that met its hit in
  time rearms at once (`_guard_paid`). A blow landing on a windup
  interrupts it (`interrupt_stagger`); strikes landing together clash
  (`clashes_with`); the kick (`ActorCommand.kick_pressed`, V,
  `MeleeWeapon.kick`) goes through a guard and breaks it open but loses to
  a swing; aim early in a heavy's windup feints it (`_try_feint`). The
  dodge is the dash (Alt, `Actor.dodge_style`: a roll with no rig, the
  rig's own dodge otherwise): swings pass through it (`evade_left`), rounds
  do not, and the weapon waits out `dodge_recover`. What a guarded strike,
  a reel and the feet look like is view only: `ActionPose.bind` (both
  blades meet at `ActorSkin.bind_point`), `reel`, `footwork`; check with
  `visual_check.tscn -- <dir> --bind-only` (the foe is armed through
  `Loadout.refit`, so its blade has its model). Each technique moves the
  feet its own way (`ActionPose.technique_steps`, [windup, strike, rate]
  as multiples of the `step_*` values): a knife short and quick, a
  one-handed axe settling back further, a hammer hauling right back and
  driving in slowly, a spear lunging furthest, a katana a touch past a
  sword. See a weapon's swings with `--moves-only weapon=<id>`.
