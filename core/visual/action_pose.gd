class_name ActionPose
extends Node
## One actor's animation state for the weapon hand, which the body is posed
## from. First and third person differ only in where the camera is (Caleb's
## rule): both look at the same body, so `WeaponArm` and `ActorSkin` reaching
## the model's arm from this state is all there is to it. Nothing here feeds
## back into the simulation: it is read from the actor and its command, and
## only views read it. It is a child of the actor named `NODE_NAME`, made by
## the first view that asks (`ActionPose.of`), so a headless server never has
## one.
##
## Offsets are in the aim frame: the actor's facing turned by its pitch, with
## x to the actor's right, y up and z back, applied from the model's hand (or
## `Actor.HAND_REST` for melee).

const NODE_NAME := "ActionPose"

## Holding a one-handed weapon ready (standing, moving, between attacks) the
## hand is out in front, low on the right of the view, with the weapon
## standing in the fist (Caleb's references). Each model picks its hold
## (`Look.ready_hold`, the last field of `Look.MELEE_MODELS`): where the hand
## goes (an offset from `Actor.HAND_REST`, aim frame), which way the blade
## points (aim frame: x right, y up, z back), what the off hand does
## (`ready_off`) and whether the blade comes out of the little-finger side
## of the fist (a reverse grip, `ready_reversed`). A swing starts from the
## hold and eases back to it; a reverse grip turns over in the hand as it
## goes. Two-handed weapons are carried across the body instead
## (`WeaponArm.carry_point`).
var ready_holds := {
	# A straight sword (or an axe): the elbow bent and the fist low in front
	# of the right hip, the point up and forward toward the foe's face and
	# leaning in a little, the empty hand up as a guard (the old upright
	# hold had the arm locked out at shoulder height, as if showing it off).
	"upright": [Vector3(-0.04, -0.03, 0.06), Vector3(-0.15, 0.8, -0.6), "guard", false],
	# A katana in both hands, the off hand under the weapon hand: the point
	# forward and leaning in toward the middle of the view.
	"katana": [Vector3(0.04, 0.08, -0.2), Vector3(-0.38, 1.0, -0.35), "hilt", false],
	# A knife in a reverse grip: lying flat, the point out to the right and
	# ahead, the pommel over the thumb, the empty hand up low as a guard.
	"knife": [Vector3(-0.1, 0.18, -0.2), Vector3(0.85, -0.1, -0.5), "guard", true],
}
## Where the empty hand is held as a guard beside a one-handed weapon
## (`ready_holds`): up in front of the chest, left of the middle, the elbow
## bent and down, in the actor's frame.
var off_guard := Vector3(-0.14, 1.32, -0.36)
## The weapon shoulder, in the actor's frame like `Actor.HAND_REST`: a
## thrown toy's arc turns about it.
var shoulder := Vector3(0.2, 1.45, -0.05)
## How far the weapon is in its ready hold (0..1), eased.
var held_ready := 0.0
## Where the weapon elbow points (a pole, actor frame) with the arm cocked
## for a windup and with it thrown through at the end of a swing. Both views
## blend between them by `elbow_raise`.
var elbow_cocked := Vector3(0.9, 1.6, 0.35)
var elbow_thrown := Vector3(0.6, 0.5, 0.2)
## How long the follow-through is held after the swing lands, in seconds.
var follow_hold := 0.2
## A windup keeps drawing back as it goes on, by up to this share of its
## reach and turn (`MeleeWeapon.windup_coil`), so it never freezes.
var windup_coil := 0.18
## A two-handed weapon turns the shoulders this much further: its weight
## comes from the body, not the wrist.
var two_hand_turn := 1.3
## The back strike: the hand drops back past the hip and thrusts behind,
## the shoulders turning to look back.
var arm_back := Vector3(0.12, -0.3, 0.38)
var turn_back := Vector2(-0.7, 0.1)
## A dash-strike leans the body forward (radians) as it closes in.
var dash_lean := 0.35
## Thrown off balance (`Actor.stagger_left`: a parried swing, a broken
## guard, an interrupt): the weapon hand is knocked out wide and back
## (`reel_reach`, in the arm's offset frame) and the chest twists away and
## rocks back (`reel_turn`), opening the body for the riposte. It comes in
## at `reel_in` a second and eases out over the stagger's last `reel_ease`
## seconds. View only, the same body in both views.
var reel_reach := Vector3(0.38, 0.24, 0.42)
var reel_turn := Vector2(0.45, 0.4)
var reel_in := 14.0
var reel_ease := 0.35
## How far into the reel the body is shown (0 to 1).
var reel := 0.0
## Footwork (Caleb's ask: melee with good footwork): how far the feet move
## the body along its facing, in metres, under the fighting stance
## (`Locomotion._fight_pose`): the weight settles back through a windup
## (`step_windup`), the lead foot drives in with the strike (`step_light`,
## `step_heavy`, held into the recovery and eased back), a guard sits back
## a little (`step_guard`) and a reel steps the trailing foot back
## (`step_reel`). Followed on a spring (`step_rate`). View only.
var step_windup := -0.06
var step_light := 0.12
var step_heavy := 0.24
var step_guard := -0.04
var step_reel := -0.22
var step_rate := 16.0
var footwork := 0.0
## Blades meet at one point (Caleb's call, so a guarded strike reads
## clean): a strike met by a guard sets `bind` on both fighters, and for
## `BIND_TIME` each blade turns in the fist to point at `bind_at`
## (`bind_turn`, `WeaponArm.hold_weapon`) and the arm is pulled so the point
## `bind_share` up it lands there, then lets go. View only.
const BIND_TIME := 0.16
var bind_share := 0.7
var bind_at := Vector3.ZERO
var bind_left := 0.0
## How far the blade is turned onto `bind_at`: in fast, out slower.
var bind_turn := 0.0
var bind_turn_in := 30.0
var bind_turn_out := 7.0
var _bind_fix := Vector3.ZERO
## Each weapon fights its own way (Caleb's call: every attack and guard
## matches how the weapon is really used). A technique (`technique`, picked
## from the swing style, the hold and whether it is two-handed) is a table
## of keys in the aim frame, for each side a swing comes from
## (`MeleeWeapon.Dir`) and, where it has one, "heavy" (the heavy from the
## middle stance):
##   "swings"  three keys each, the windup, the moment of contact and the
##             end of the follow-through, each [hand, blade]: the weapon
##             hand as an offset from `Actor.HAND_REST` and the way the
##             blade (or head, or point) goes from the fist. The hand passes
##             through the contact key on a curve and the blade turns
##             through it, its edge leading the way it turns, so a cut
##             sweeps out in front of the body, in view from the eyes.
##   "turns"   the shoulder turn and lean (x toward the actor's left, y
##             backward) at the windup and at the end, the hips driving it.
##   "guards"  for each side a guard covers, [hand, blade, edge]: the
##             weapon held across that side in front of the body, where
##             the eyes see it.
##   "both"    true when both hands stay on the handle (the katana's cuts;
##             a two-handed weapon's off hand follows its haft anyway).
## The techniques:
##   "slash"   a one-handed sword: diagonal forehand and backhand cuts from
##             the shoulder through the line to the far hip, a vertical cut
##             from over the head, and a heavy lunging thrust.
##   "chop"    a one-handed axe: raised high behind the shoulder and brought
##             down through a steep diagonal, the head leading.
##   "knife"   a knife: it turns over out of its reverse-grip ready hold
##             into a forward grip for short, quick slashes in front of the
##             chest, and a guard held up by the face.
##   "stab"    a knife's heavy: driven straight in at the ribs from the hip.
##   "chop2"   a two-handed hammer: hauled up over the shoulder with both
##             hands and brought down through the body.
##   "thrust2" a spear: rear hand at the hip driving the point straight
##             out along the aim, the front hand guiding the shaft.
##   "cut"     the katana's kenjutsu cuts in both hands (the off hand under
##             the weapon hand: the left hand drives, the right steers):
##             RIGHT kesa-giri from hasso by the right shoulder down to the
##             left hip, LEFT gyaku-kesa, the mirror, OVERHEAD shomen from
##             jodan down the middle, stopped at the chest, and "heavy" a
##             tsuki from the middle stance.
const D_OVERHEAD := MeleeWeapon.Dir.OVERHEAD
const D_LEFT := MeleeWeapon.Dir.LEFT
const D_RIGHT := MeleeWeapon.Dir.RIGHT
var techniques := {
	"slash": {
		"swings": {
			D_RIGHT: [
				[Vector3(0.0, 0.38, 0.22), Vector3(0.35, 0.65, 0.68)],
				[Vector3(-0.27, 0.06, -0.3), Vector3(-0.6, 0.2, -0.78)],
				[Vector3(-0.5, -0.24, -0.02), Vector3(-0.75, -0.5, 0.42)],
			],
			D_LEFT: [
				[Vector3(-0.42, 0.3, 0.12), Vector3(-0.45, 0.6, 0.66)],
				[Vector3(-0.17, 0.06, -0.3), Vector3(0.6, 0.2, -0.78)],
				[Vector3(0.12, -0.2, -0.05), Vector3(0.8, -0.45, 0.4)],
			],
			D_OVERHEAD: [
				[Vector3(-0.12, 0.55, 0.15), Vector3(0.05, 0.45, 0.89)],
				[Vector3(-0.2, 0.16, -0.34), Vector3(0.0, 0.3, -0.95)],
				[Vector3(-0.22, -0.2, -0.22), Vector3(0.0, -0.55, -0.83)],
			],
			"heavy": [
				[Vector3(0.02, -0.02, 0.24), Vector3(-0.08, 0.12, -0.99)],
				[Vector3(-0.2, 0.14, -0.4), Vector3(-0.02, 0.04, -1.0)],
				[Vector3(-0.22, 0.14, -0.44), Vector3(0.0, 0.0, -1.0)],
			],
		},
		"turns": {
			D_RIGHT: [Vector2(-0.45, 0.05), Vector2(0.45, -0.12)],
			D_LEFT: [Vector2(0.45, 0.05), Vector2(-0.45, -0.12)],
			D_OVERHEAD: [Vector2(-0.1, 0.18), Vector2(0.05, -0.3)],
			"heavy": [Vector2(-0.35, 0.05), Vector2(0.15, -0.35)],
		},
		"guards": {
			D_RIGHT: [Vector3(-0.1, 0.16, -0.16), Vector3(0.12, 1.0, -0.2), Vector3.RIGHT],
			D_LEFT: [Vector3(-0.46, 0.16, -0.12), Vector3(-0.25, 1.0, -0.15), Vector3.LEFT],
			D_OVERHEAD: [Vector3(-0.02, 0.48, -0.08), Vector3(-1.0, 0.18, -0.25), Vector3.UP],
		},
	},
	"chop": {
		"swings": {
			D_RIGHT: [
				[Vector3(0.04, 0.48, 0.2), Vector3(0.3, 0.55, 0.78)],
				[Vector3(-0.25, 0.06, -0.33), Vector3(-0.45, 0.35, -0.82)],
				[Vector3(-0.45, -0.3, -0.05), Vector3(-0.55, -0.7, 0.45)],
			],
			D_LEFT: [
				[Vector3(-0.4, 0.42, 0.15), Vector3(-0.35, 0.55, 0.76)],
				[Vector3(-0.16, 0.06, -0.33), Vector3(0.45, 0.35, -0.82)],
				[Vector3(0.12, -0.28, -0.05), Vector3(0.55, -0.7, 0.45)],
			],
			D_OVERHEAD: [
				[Vector3(-0.08, 0.6, 0.2), Vector3(0.05, 0.35, 0.94)],
				[Vector3(-0.2, 0.12, -0.36), Vector3(0.0, 0.4, -0.92)],
				[Vector3(-0.22, -0.3, -0.18), Vector3(0.0, -0.75, -0.66)],
			],
		},
		"turns": {
			D_RIGHT: [Vector2(-0.5, 0.15), Vector2(0.45, -0.25)],
			D_LEFT: [Vector2(0.45, 0.15), Vector2(-0.45, -0.25)],
			D_OVERHEAD: [Vector2(-0.1, 0.25), Vector2(0.05, -0.4)],
		},
		"guards": {
			D_RIGHT: [Vector3(-0.1, 0.16, -0.16), Vector3(0.1, 1.0, -0.2), Vector3.RIGHT],
			D_LEFT: [Vector3(-0.46, 0.16, -0.12), Vector3(-0.2, 1.0, -0.2), Vector3.LEFT],
			D_OVERHEAD: [Vector3(-0.02, 0.48, -0.08), Vector3(-1.0, 0.15, -0.2), Vector3.UP],
		},
	},
	"knife": {
		"swings": {
			D_RIGHT: [
				[Vector3(0.0, 0.26, 0.08), Vector3(0.45, 0.55, 0.7)],
				[Vector3(-0.24, 0.12, -0.32), Vector3(-0.55, 0.15, -0.82)],
				[Vector3(-0.44, -0.04, -0.14), Vector3(-0.8, -0.3, 0.5)],
			],
			D_LEFT: [
				[Vector3(-0.4, 0.24, 0.02), Vector3(-0.5, 0.5, 0.7)],
				[Vector3(-0.16, 0.12, -0.34), Vector3(0.55, 0.15, -0.82)],
				[Vector3(0.08, -0.02, -0.16), Vector3(0.8, -0.3, 0.5)],
			],
			D_OVERHEAD: [
				[Vector3(-0.1, 0.4, 0.06), Vector3(0.05, 0.6, 0.8)],
				[Vector3(-0.2, 0.14, -0.36), Vector3(0.0, 0.2, -0.98)],
				[Vector3(-0.22, -0.06, -0.26), Vector3(0.0, -0.5, -0.87)],
			],
		},
		"turns": {
			D_RIGHT: [Vector2(-0.35, 0.0), Vector2(0.35, -0.1)],
			D_LEFT: [Vector2(0.35, 0.0), Vector2(-0.35, -0.1)],
			D_OVERHEAD: [Vector2(-0.15, 0.1), Vector2(0.1, -0.3)],
		},
		"guards": {
			# Short: the knife up in front of the face on that side, point
			# up and out, to catch and turn a blow.
			D_RIGHT: [Vector3(-0.12, 0.3, -0.22), Vector3(0.3, 0.9, -0.3), Vector3.RIGHT],
			D_LEFT: [Vector3(-0.44, 0.3, -0.2), Vector3(-0.35, 0.88, -0.3), Vector3.LEFT],
			D_OVERHEAD: [Vector3(-0.18, 0.48, -0.18), Vector3(-0.95, 0.2, -0.25), Vector3.UP],
		},
	},
	"stab": {
		# Driven straight in at the ribs from the hip, a short lunge.
		"swings": {
			D_RIGHT: [
				[Vector3(0.04, -0.04, 0.2), Vector3(-0.15, 0.05, -0.99)],
				[Vector3(-0.18, 0.08, -0.4), Vector3(-0.1, 0.05, -0.99)],
				[Vector3(-0.2, 0.08, -0.44), Vector3(-0.08, 0.04, -1.0)],
			],
			D_LEFT: [
				[Vector3(-0.1, -0.04, 0.18), Vector3(0.1, 0.05, -0.99)],
				[Vector3(-0.22, 0.08, -0.4), Vector3(0.05, 0.05, -0.99)],
				[Vector3(-0.24, 0.08, -0.44), Vector3(0.04, 0.04, -1.0)],
			],
			D_OVERHEAD: [
				[Vector3(0.0, -0.04, 0.2), Vector3(-0.05, 0.1, -0.99)],
				[Vector3(-0.2, 0.1, -0.4), Vector3(0.0, 0.05, -1.0)],
				[Vector3(-0.22, 0.1, -0.44), Vector3(0.0, 0.03, -1.0)],
			],
		},
		"turns": {
			D_RIGHT: [Vector2(-0.35, 0.05), Vector2(0.25, -0.3)],
			D_LEFT: [Vector2(-0.2, 0.05), Vector2(0.3, -0.3)],
			D_OVERHEAD: [Vector2(-0.3, 0.05), Vector2(0.25, -0.3)],
		},
	},
	"chop2": {
		"swings": {
			D_RIGHT: [
				[Vector3(-0.08, 0.42, 0.26), Vector3(0.3, 0.6, 0.74)],
				[Vector3(-0.34, 0.04, -0.3), Vector3(-0.35, 0.3, -0.89)],
				[Vector3(-0.5, -0.36, -0.05), Vector3(-0.5, -0.75, -0.43)],
			],
			D_LEFT: [
				[Vector3(-0.55, 0.38, 0.18), Vector3(-0.4, 0.6, 0.69)],
				[Vector3(-0.3, 0.04, -0.3), Vector3(0.35, 0.3, -0.89)],
				[Vector3(-0.06, -0.36, -0.05), Vector3(0.5, -0.75, -0.43)],
			],
			D_OVERHEAD: [
				[Vector3(-0.3, 0.6, 0.22), Vector3(0.0, 0.35, 0.94)],
				[Vector3(-0.32, 0.1, -0.36), Vector3(0.0, 0.3, -0.95)],
				[Vector3(-0.32, -0.38, -0.2), Vector3(0.0, -0.8, -0.6)],
			],
		},
		"turns": {
			D_RIGHT: [Vector2(-0.45, 0.15), Vector2(0.4, -0.25)],
			D_LEFT: [Vector2(0.4, 0.15), Vector2(-0.45, -0.25)],
			D_OVERHEAD: [Vector2(-0.05, 0.3), Vector2(0.0, -0.45)],
		},
		"guards": {
			# The haft held up across the side, both hands on it.
			D_RIGHT: [Vector3(-0.14, 0.12, -0.18), Vector3(0.18, 1.0, -0.12), Vector3.RIGHT],
			D_LEFT: [Vector3(-0.42, 0.12, -0.12), Vector3(-0.25, 1.0, -0.1), Vector3.LEFT],
			D_OVERHEAD: [Vector3(-0.08, 0.4, -0.22), Vector3(-1.0, 0.12, -0.15), Vector3.UP],
		},
	},
	"thrust2": {
		"swings": {
			D_RIGHT: [
				[Vector3(0.06, -0.06, 0.26), Vector3(-0.28, 0.12, -0.95)],
				[Vector3(-0.14, 0.04, -0.3), Vector3(-0.15, 0.05, -0.99)],
				[Vector3(-0.18, 0.04, -0.4), Vector3(-0.1, 0.02, -0.99)],
			],
			D_LEFT: [
				[Vector3(-0.18, -0.06, 0.22), Vector3(0.28, 0.12, -0.95)],
				[Vector3(-0.24, 0.04, -0.3), Vector3(0.12, 0.05, -0.99)],
				[Vector3(-0.27, 0.04, -0.4), Vector3(0.08, 0.02, -0.99)],
			],
			D_OVERHEAD: [
				[Vector3(-0.04, 0.32, 0.22), Vector3(0.0, -0.12, -0.99)],
				[Vector3(-0.18, 0.28, -0.3), Vector3(0.0, -0.18, -0.98)],
				[Vector3(-0.2, 0.24, -0.42), Vector3(0.0, -0.2, -0.98)],
			],
			"heavy": [
				[Vector3(0.06, -0.1, 0.34), Vector3(-0.05, 0.1, -0.99)],
				[Vector3(-0.18, 0.04, -0.44), Vector3(0.0, 0.03, -1.0)],
				[Vector3(-0.2, 0.04, -0.5), Vector3(0.0, 0.0, -1.0)],
			],
		},
		"turns": {
			D_RIGHT: [Vector2(-0.35, 0.05), Vector2(0.25, -0.15)],
			D_LEFT: [Vector2(-0.15, 0.05), Vector2(0.35, -0.15)],
			D_OVERHEAD: [Vector2(-0.25, 0.1), Vector2(0.2, -0.2)],
			"heavy": [Vector2(-0.45, 0.08), Vector2(0.35, -0.35)],
		},
		"guards": {
			# The shaft held across the threatened side.
			D_RIGHT: [Vector3(-0.02, 0.0, -0.12), Vector3(0.4, 0.85, -0.35), Vector3.RIGHT],
			D_LEFT: [Vector3(-0.36, 0.0, -0.08), Vector3(-0.45, 0.82, -0.35), Vector3.LEFT],
			D_OVERHEAD: [Vector3(-0.08, 0.34, -0.22), Vector3(-0.95, 0.2, -0.22), Vector3.UP],
		},
	},
	"cut": {
		"both": true,
		"swings": {
			D_RIGHT: [
				[Vector3(-0.16, 0.37, 0.2), Vector3(0.25, 0.8, 0.55)],
				[Vector3(-0.28, 0.07, -0.33), Vector3(-0.55, 0.3, -0.8)],
				[Vector3(-0.48, -0.23, -0.1), Vector3(-0.8, -0.35, 0.3)],
			],
			D_LEFT: [
				[Vector3(-0.6, 0.37, 0.2), Vector3(-0.25, 0.8, 0.55)],
				[Vector3(-0.26, 0.05, -0.33), Vector3(0.55, 0.3, -0.8)],
				[Vector3(0.04, -0.23, -0.03), Vector3(0.8, -0.35, 0.3)],
			],
			D_OVERHEAD: [
				[Vector3(-0.26, 0.6, 0.2), Vector3(0.0, 0.55, 0.85)],
				[Vector3(-0.26, 0.25, -0.35), Vector3(0.0, 0.3, -0.95)],
				[Vector3(-0.26, -0.1, -0.23), Vector3(0.0, -0.35, -0.95)],
			],
			"heavy": [
				[Vector3(-0.2, -0.1, 0.13), Vector3(-0.05, 0.15, -1.0)],
				[Vector3(-0.26, 0.05, -0.33), Vector3(0.0, 0.05, -1.0)],
				[Vector3(-0.26, 0.05, -0.37), Vector3(0.0, 0.0, -1.0)],
			],
		},
		"turns": {
			D_RIGHT: [Vector2(-0.35, 0.05), Vector2(0.4, -0.15)],
			D_LEFT: [Vector2(0.35, 0.05), Vector2(-0.4, -0.15)],
			D_OVERHEAD: [Vector2(0.0, 0.18), Vector2(0.0, -0.3)],
			"heavy": [Vector2(-0.2, 0.05), Vector2(0.05, -0.35)],
		},
		"guards": {
			# Both hands on the handle: the blade up across that side, or
			# over the head edge up.
			D_RIGHT: [Vector3(-0.1, 0.15, -0.18), Vector3(0.15, 1.0, -0.2), Vector3.FORWARD],
			D_LEFT: [Vector3(-0.32, 0.15, -0.1), Vector3(-0.3, 1.0, -0.15), Vector3.FORWARD],
			D_OVERHEAD: [Vector3(-0.3, 0.42, -0.2), Vector3(1.0, 0.15, -0.2), Vector3.UP],
		},
	},
}
## A heavy from a side is raised higher and further back, and the hips
## coil more.
var cut_heavy_raise := Vector3(0.0, 0.06, 0.06)
var cut_heavy_coil := 1.25
## Where the weapon elbow points through a two-handed technique (actor
## frame), cocked and thrown: down and out, never winged up, since both
## hands share the handle.
var cut_elbow_cocked := Vector3(0.75, 1.25, 0.2)
var cut_elbow_thrown := Vector3(0.55, 0.7, 0.0)
## The middle of the swings (a hand offset, aim frame): in front of the
## chest, where the contact keys are. A small weapon's swing is drawn in
## toward it.
var swing_centre := Vector3(-0.22, 0.08, -0.32)
## How far a guard turns the guarded side's shoulder forward (radians).
var guard_turn := 0.15
## Which way the blade's edge faces in the weapon's own frame (the blade
## runs along +Y): a cut leads with it.
var cut_edge := Vector3(0.0, 0.0, -1.0)
## How far the current weapon is held in both hands for its technique
## (0..1, `techniques` "both").
var cut_grip := 0.0
var _two_hands := 0.0
## A reload: at its deepest the gun is brought in toward the middle of the
## chest, where the off hand works the magazine and the eyes can see it
## (`reload_reach`; it used to drop out of view from the eyes), and tipped
## (`reload_tilt`: pitch, yaw, roll in radians, roll positive to the left)
## to bring the magazine well round.
## `reload_ease` is the share of the reload spent going in and coming out.
var reload_reach := Vector3(-0.12, 0.02, -0.02)
## Where the gun wrist comes to at the deepest of a reload, from the eyes
## along the aim (metres right, up, back), whatever the clip held it at, so
## the reload is worked in front of the chest in view of the eyes.
var reload_from_eyes := Vector3(0.06, -0.3, -0.4)
var reload_tilt := Vector3(0.3, 0.15, 0.75)
var reload_ease := 0.22
## Standing still out of a fight a gun is held low (the `idle_gun` clip):
## how fast it is raised and lowered, per second.
var raise_rate := 9.0
var lower_rate := 2.5
## How fast the phone comes up and goes away (per second).
var phone_rate := 5.0
## A toy vehicle off the watch (`Actor.toy_in_hand`) is held up in the right
## hand, and thrown overarm: the hand draws back over the shoulder, whips
## forward and lets go at `toy_release` (the `Raid` lets it fly after the
## same wait, `Raid.toy_windup`), and follows through down across the body.
## Points are in the actor's frame (x right, y up, z back) and turn with the
## aim's pitch by `toy_pitch_share` about the shoulder.
var toy_hold := Vector3(0.24, 1.3, -0.46)
var toy_cocked := Vector3(0.3, 1.62, 0.12)
var toy_let_go := Vector3(0.18, 1.56, -0.5)
var toy_follow := Vector3(0.04, 1.05, -0.36)
var toy_pitch_share := 0.5
## The throw's timing, in seconds from its start: drawn back by
## `toy_cocked_at`, let go at `toy_release`, followed through by
## `toy_follow_at`, and handed back to the usual hold by `toy_throw_time`.
var toy_cocked_at := 0.2
var toy_release := 0.3
var toy_follow_at := 0.42
var toy_throw_time := 0.62
## How fast the hand comes up to hold a toy and goes back (per second).
var toy_rate := 6.0
## The shoulders' turn and lean (as `turn`) drawn back and thrown through.
var toy_turn_cocked := Vector2(-0.45, 0.06)
var toy_turn_thrown := Vector2(0.3, -0.12)
## Where the throwing elbow points, cocked (actor frame).
var toy_elbow := Vector3(0.9, 1.75, 0.3)
## Aiming down sights: the gun is brought up until its sight line runs
## through the eyes, the stock in the shoulder and the off hand on the fore
## end, the same body in both views. `ads_rate` is how fast it comes up and
## goes down (per second; `PlayerController` moves an optic's eye to the
## camera at the same pace). A sidearm is held out with its sight
## `sidearm_relief` in front of the eyes. A long gun is shouldered: the eye
## sits `stock_ahead` forward of the butt (a cheek on the stock), so its
## plain sights come `relief_for` in front of it, at least `min_relief`.
## An optic's eye point is its own relief.
var ads_rate := 7.0
var sidearm_relief := 0.5
var stock_ahead := 0.17
var min_relief := 0.06
## Guns with any of these tags are braced at the hip, never shouldered
## (a spinning cannon is too heavy to bring to the eye).
var ads_hip_tags: Array[String] = ["minigun"]
## Where the off hand's fist closes round a sidearm's grip, wrapped over
## the gun hand's fingers from the off side: from the grip spot
## (`hold_local`), in the gun's space.
var ads_cup := Vector3(-0.03, -0.035, -0.01)
## The stance that goes with aiming down sights, as a shoulder turn and lean
## (like `turn`: x toward the actor's left, y backward): a long gun blades
## the body so the off shoulder comes forward to the fore end, a sidearm
## squares up and leans in so the arms reach out.
var ads_stance_long := Vector2(-0.35, -0.06)
var ads_stance_sidearm := Vector2(0.3, -0.06)
## Inspecting what is in the hand (`ActorCommand.inspect`, the inspect key):
## the hand brings it in closer, a little up and toward the middle of the
## body, and turns it through `INSPECT_TURNS` so each side shows, then it
## goes back to the ready hold. The same body in both views, and everyone
## sees it, since the flag travels with the held keys. Offsets are in the
## aim frame like the rest, so it comes up wherever you look.
## `inspect_from_eyes` is where the wrist comes to (metres right, up and
## ahead of the eyes along the aim, the pitch clamped to `inspect_pitch`),
## whatever is in hand; `inspect_rate` is how fast it comes up and goes
## back (per second).
var inspect_from_eyes := Vector3(0.05, -0.18, -0.45)
var inspect_pitch := Vector2(-0.7, 0.5)
var inspect_rate := 3.5
## How long a look over takes, in seconds. The controller holds the flag
## this long (`PlayerController.inspect_left`); every view times the turns
## from when it saw the flag go on.
const INSPECT_SECONDS := 3.4
## The turns the item goes through, as [seconds in, Vector3(pitch, yaw,
## roll)] in radians, eased from one to the next (yaw positive to the left,
## roll about the item's own length): a gun's muzzle swung left across the
## body to show its right side, then out to the right and rolled to show
## its left side and top, then tipped up, and back.
const INSPECT_TURNS := [
	[0.0, Vector3.ZERO],
	[0.55, Vector3(0.15, 1.15, 0.35)],
	[1.25, Vector3(0.15, 1.25, 0.45)],
	[1.95, Vector3(-0.1, -0.35, -1.1)],
	[2.5, Vector3(-0.1, -0.45, -1.2)],
	[3.0, Vector3(0.55, 0.3, 0.0)],
	[3.4, Vector3.ZERO],
]

## Carrying a gun on the move (Caleb's "running with a weapon" pass). Out of
## a fight a gun is carried, not pointed: jogging it sits at a low ready
## (stock in under the shoulder, muzzle down ahead of the feet, both hands
## on it), sprinting a long gun goes across the chest at port (muzzle up and
## to the off side, the off hand on the fore end) and a sidearm is tucked in
## to the chest muzzle down in one hand while the other arm pumps. Shooting,
## aiming or reloading takes it straight back up (`carry_out_rate` is quick,
## the way a sprint-to-fire is). Each pose is where the gun hand's wrist goes
## from the chest, in the actor's frame (x right, y up, z back), and how the
## gun turns from straight ahead (pitch up, yaw toward the off side, roll
## toward the off side, radians). The chest carries it, so the run's own lean
## and bounce move the gun with the body.
var carry_low_long := Vector3(0.15, 1.2, -0.25)
var carry_low_long_turn := Vector3(-0.3, 0.15, 0.08)
var carry_port_long := Vector3(0.13, 1.16, -0.24)
var carry_port_long_turn := Vector3(0.75, 1.0, 0.6)
var carry_low_sidearm := Vector3(0.05, 1.24, -0.3)
var carry_low_sidearm_turn := Vector3(-0.5, 0.1, 0.0)
var carry_port_sidearm := Vector3(0.17, 1.16, -0.2)
var carry_port_sidearm_turn := Vector3(-1.0, 0.15, 0.15)
## How much the off hand holds the gun in each carry: both hands at a low
## ready, a long gun at port; a sprinting sidearm leaves the off arm free.
var carry_support_low := 1.0
var carry_support_port_long := 1.0
var carry_support_port_sidearm := 0.0
## How fast the gun goes into its carry and comes back up out of it, and
## how fast it moves between the low ready and the sprint carry (per second).
var carry_in_rate := 3.5
var carry_out_rate := 9.0
var sprint_rate := 4.0
## The share of the chest's lean (a sprint's, a slide's) the carried gun
## follows: most, so it rides the body, but it stays steadier than the chest.
var carry_body_follow := 0.8
## The bob of a carried gun with each stride: the run's footfalls drop it
## twice a cycle and it swings side to side once, metres at a jog and at a
## sprint, and a little tip of the muzzle with the drop (radians).
var bob_drop := Vector2(0.004, 0.008)
var bob_swing := Vector2(0.006, 0.015)
var bob_tip := 0.006
## Inertia: a carried gun lags behind the body as it speeds up, stops or
## turns, on a damped spring. `sway_gain` is metres per m/s² of the body's
## change of speed, `sway_turn` metres per radian a second of turning,
## `sway_limit` the most it lags, and the spring's stiffness and damping.
var sway_gain := 0.004
var sway_turn := 0.012
var sway_limit := 0.05
var sway_stiffness := 120.0
var sway_damping := 18.0

var actor: Actor

## Set by the skin: true while it holds the gun low (the `idle_gun` stand).
var low_wanted := false
## How far the watch is raised to read (0 lowered, 1 up), eased, from the
## actor's command (`ActorCommand.watch_up`), so remote players raise it too.
var watch := 0.0
## Seconds the watch takes to come up or go down (as `Hud.Wrist.raise_time`).
var watch_time := 0.18
var _watch_raise := 0.0
## How far the phone is up in the right hand (0..1), from the actor's
## command (`ActorCommand.phone`), so everyone who sees them agrees.
var phone := 0.0
## The helmet coming off onto the hip or going back on, as shown: the
## simulated `Actor.helmet_stow` (0 on the head, 1 on the hip) followed
## smoothly between ticks. `helmet_hand`, `helmet_carry` and `helmet_place`
## read the off hand's reach, the helmet's way down and where it hangs.
var helmet := 0.0
## How far the hand is up holding a toy or throwing it (0..1), eased.
var toy := 0.0
## Seconds into the toy throw being shown, or below zero when none is.
var toy_throw_t := -1.0
## Set by the skin: false while the hand is still putting a weapon away, so
## the toy comes up only into an empty hand. True with no skin (checks).
var toy_hand_free := true
var _toy_throws_seen := -1
var _toy_thrown := ""
## How far the item in hand is brought in to be looked over (0..1, eased),
## and how long this look has been going (seconds), from
## `ActorCommand.inspect`.
var inspect := 0.0
var inspect_clock := 0.0
## The emote shown (`ActorCommand.emote`, `Emotes`): which one, how far it
## has come in (0 to 1, eased) and seconds since this view saw it start, so
## a remote player's wave is timed from when it was seen, like the inspect.
## The last one stays named while it eases out.
var emote := 0.0
var emote_id := ""
var emote_clock := 0.0
## How fast an emote comes in and goes out (a share a second).
var emote_rate := 3.0
var _emote_raise := 0.0
var _inspect_raise := 0.0
var _inspect_was := false

## The melee hand offset, smoothed, and how much it has the arm (0..1).
var reach := Vector3.ZERO
var reach_weight := 0.0
## The shoulder turn and lean that go with `reach`, smoothed.
var turn := Vector2.ZERO
## How cocked the weapon elbow is (1 wound up, 0 thrown through), smoothed.
var elbow_raise := 0.0
## How deep into its reload motion the gun is (0..1), and how low it is held.
var reload := 0.0
var low := 0.0
## How far the gun is up at the eye (0 at the hold, 1 sighted), eased.
var ads := 0.0
## How far in front of the eyes the sight sits now (`relief_for`, drawn in
## to what the model's arm reaches). Set by the skin's arm; a view puts its
## eye this far behind the sight.
var relief_now := -1.0
var _ads_raise := 0.0

## Set by the skin each frame: whether the gun in hand should be carried
## (moving out of a fight), how much of a sprint it is (0..1), and where the
## stride is (`stride_phase`, 0..1 through the gait clip) and how hard the
## body is moving (`stride_amount`, 0 standing to 1 at a sprint).
var carry_wanted := false
var sprint_wanted := 0.0
var stride_phase := 0.0
var stride_amount := 0.0
## How far into its carry the gun is (0 raised, 1 carried), and how far the
## carry is from the low ready toward the sprint carry, eased.
var carry := 0.0
var sprint := 0.0
## How far the carried gun lags behind the body, in the actor's frame, and
## the spring's speed.
var sway := Vector3.ZERO
var _sway_speed := Vector3.ZERO
var _last_velocity := Vector3.ZERO
var _last_yaw := 0.0
var _sway_primed := false

var _follow_left := 0.0
var _follow_dir := MeleeWeapon.Dir.OVERHEAD
var _frame := -1


## The pose node of `actor`, made on first use.
static func of(p_actor: Actor) -> ActionPose:
	var pose := p_actor.get_node_or_null(NODE_NAME) as ActionPose
	if pose == null:
		pose = ActionPose.new()
		pose.name = NODE_NAME
		pose.actor = p_actor
		p_actor.add_child(pose)
	return pose


func _ready() -> void:
	set_process(false)


## Moves the pose on to this frame. Every reader calls it before reading;
## only the first call in a frame does anything.
func advance(delta: float) -> void:
	var frame := Engine.get_process_frames()
	if frame == _frame:
		return
	_frame = frame
	if actor == null or not is_instance_valid(actor):
		return
	var inspect_wanted := actor.cmd != null and actor.cmd.inspect and not actor.is_dead \
			and actor.vehicle == null and not actor.cmd.phone
	if inspect_wanted and not _inspect_was:
		inspect_clock = 0.0
	_inspect_was = inspect_wanted
	if inspect_wanted or _inspect_raise > 0.0:
		inspect_clock += delta
	else:
		inspect_clock = 0.0
	_inspect_raise = move_toward(_inspect_raise, 1.0 if inspect_wanted else 0.0, inspect_rate * delta)
	inspect = smoothstep(0.0, 1.0, _inspect_raise)
	advance_emote(delta)

	var weapon := actor.get_active_weapon()
	var melee := weapon as MeleeWeapon
	var holding := melee != null and melee.visual != null and not actor.is_dead
	var reel_wanted := clampf(actor.stagger_left / maxf(reel_ease, 0.01), 0.0, 1.0) if not actor.is_dead else 0.0
	reel = move_toward(reel, reel_wanted, delta * reel_in) if reel_wanted > reel else reel_wanted
	if holding and melee._swing_left > 0.0 and not melee.is_winding_up():
		_follow_left = follow_hold
		_follow_dir = melee.attack_dir
	elif _follow_left > 0.0:
		_follow_left -= delta
		if not holding or melee.is_winding_up() or melee.is_blocking():
			_follow_left = 0.0

	footwork = lerpf(footwork, footwork_wanted(melee) if holding else 0.0, 1.0 - exp(-step_rate * delta))
	var wanted: Variant = arm_reach(melee) if holding else null
	_update_bind(melee if holding else null, delta)
	if wanted != null:
		wanted += _bind_fix
	reach_weight = move_toward(reach_weight, 0.0 if wanted == null else 1.0, delta * 9.0)
	# A swing is over in a few frames, so it is followed much more tightly.
	var tight := holding and (melee.swing_arc() >= 0.0 or bind_left > 0.0)
	var follow := 1.0 - exp(-(70.0 if tight else 26.0) * delta)
	if wanted != null:
		reach = wanted if reach_weight < 0.15 else reach.lerp(wanted, follow)
	turn = turn.lerp(body_turn(melee) if holding else Vector2.ZERO, follow)
	held_ready = lerpf(held_ready, ready_amount(melee) if holding else 0.0, follow)
	elbow_raise = lerpf(elbow_raise, elbow_wanted(melee) if holding else 0.0, follow)
	var both := holding and both_hands(melee) and not melee.showing_back_strike()
	cut_grip = move_toward(cut_grip, 1.0 if both else 0.0, delta * 8.0)
	_two_hands = move_toward(_two_hands, 1.0 if holding and melee.is_two_handed() else 0.0, delta * 8.0)

	var watch_wanted := actor.cmd != null and actor.cmd.watch_up and not actor.is_dead
	_watch_raise = move_toward(_watch_raise, 1.0 if watch_wanted else 0.0, delta / maxf(watch_time, 0.001))
	watch = ease(_watch_raise, -2.0)
	var phone_wanted := actor.cmd != null and actor.cmd.phone and not actor.is_dead and actor.vehicle == null
	phone = move_toward(phone, 1.0 if phone_wanted else 0.0, phone_rate * delta)
	if actor.visor.enabled:
		helmet = move_toward(helmet, actor.helmet_stow, 1.5 * delta / maxf(actor.helmet_stow_time, 0.01))
	else:
		helmet = 0.0
	advance_toy(delta)

	var gun := weapon as Gun
	reload = reload_depth(gun) if gun != null and not actor.is_dead else 0.0
	var lowered := low_wanted and gun != null and not gun.is_aiming() and reload <= 0.0 \
			and inspecting() != "gun"
	low = move_toward(low, 1.0 if lowered else 0.0, delta * (lower_rate if lowered else raise_rate))
	_ads_raise = move_toward(_ads_raise, 1.0 if ads_wanted(gun) else 0.0, delta * ads_rate)
	ads = ease(_ads_raise, -2.0)
	var carried := carry_wanted and gun != null and not actor.is_dead and reload <= 0.0 and not gun.is_aiming() \
			and inspecting() != "gun"
	carry = move_toward(carry, 1.0 if carried else 0.0, delta * (carry_in_rate if carried else carry_out_rate))
	sprint = move_toward(sprint, clampf(sprint_wanted, 0.0, 1.0), delta * sprint_rate)
	_update_sway(delta)


## Where the feet want the body this frame (see `footwork`).
func footwork_wanted(melee: MeleeWeapon) -> float:
	if melee.is_kicking():
		return 0.0
	if reel > 0.0:
		return step_reel * reel
	if melee.is_blocking():
		return step_guard
	var strike := step_heavy if melee._shown_kind == "heavy" or melee._dashing else step_light
	if melee.is_winding_up():
		var heavy := melee._windup_kind == "heavy"
		return step_windup * (1.6 if heavy else 1.0)
	var arc := melee.swing_arc()
	if arc >= 0.0:
		return strike * smoothstep(0.0, 0.6, arc)
	if _follow_left > 0.0:
		return strike
	var back := recover_left(melee)
	if back > 0.0:
		return strike * back
	var charge := charge_amount(melee)
	if charge > 0.0:
		return step_windup * charge
	return 0.0


## True while the body rolls (`Actor.dodge_style` "roll"): the clip has the
## arms, the weapon rides the hand.
func rolling() -> bool:
	return actor.dodge_left > 0.0 and actor.dodge_shown == "roll"


## Starts a bind: this fighter's blade meets the other's at `at` (world).
func bind(at: Vector3) -> void:
	bind_at = at
	bind_left = BIND_TIME


## Pulls the hand so the blade's bind point closes on `bind_at` while a
## bind lasts (an offset in the aim frame, like `arm_reach`), and eases it
## off after.
func _update_bind(melee: MeleeWeapon, delta: float) -> void:
	var binding := melee != null and bind_left > 0.0
	bind_turn = move_toward(bind_turn, 1.0 if binding else 0.0, delta * (bind_turn_in if binding else bind_turn_out))
	if not binding:
		bind_left = 0.0
		_bind_fix = _bind_fix.lerp(Vector3.ZERO, 1.0 - exp(-10.0 * delta))
		return
	bind_left -= delta
	var point: Variant = blade_point(melee, bind_share)
	if point == null:
		return
	var aim := actor.global_basis.orthonormalized() * Basis(Vector3.RIGHT, actor.cmd.pitch)
	var miss: Vector3 = aim.inverse() * (bind_at - (point as Vector3))
	_bind_fix = (_bind_fix + miss * clampf(delta * 30.0, 0.0, 1.0)).limit_length(0.45)


## The point `share` of the way up `melee`'s model from the grip, as it is
## drawn, or null before it is dressed.
static func blade_point(melee: MeleeWeapon, share: float) -> Variant:
	if melee == null or melee.visual == null or not melee.visual.is_inside_tree():
		return null
	if not melee.visual.has_meta("blade_top"):
		var top := 0.0
		for node in melee.visual.find_children("*", "MeshInstance3D", true, false):
			var mesh_node := node as MeshInstance3D
			if mesh_node.mesh == null:
				continue
			var to_visual := melee.visual.global_transform.affine_inverse() * mesh_node.global_transform
			var box := to_visual * mesh_node.mesh.get_aabb()
			top = maxf(top, box.end.y)
		if top <= 0.0:
			return null
		melee.visual.set_meta("blade_top", top)
	# As drawn, never where a physics tick parked the hand (`shown_global`).
	var point := melee.visual.global_transform * Vector3(0.0, float(melee.visual.get_meta("blade_top")) * share, 0.0)
	return shown_global(melee, Transform3D(Basis.IDENTITY, point)).origin


## The carried gun's lag behind the body: a damped spring pulled by how the
## body's speed and heading change, so it trails a start, swings on through
## a stop and lags round a turn. View only, read from the actor's velocity
## and facing, so a remote player's gun sways the same.
func _update_sway(delta: float) -> void:
	var basis := actor.global_basis.orthonormalized()
	var local := basis.inverse() * actor.velocity
	local.y = 0.0
	var yaw := actor.global_rotation.y
	if not _sway_primed or delta <= 0.0:
		_sway_primed = true
		_last_velocity = local
		_last_yaw = yaw
		return
	var accel := (local - _last_velocity) / delta
	var turning := wrapf(yaw - _last_yaw, -PI, PI) / delta
	_last_velocity = local
	_last_yaw = yaw
	# A start pulls the gun back, a stop throws it on, a turn left leaves it
	# out to the right.
	var pull := (-accel * sway_gain + Vector3(turning * sway_turn, 0.0, 0.0)).limit_length(sway_limit * 2.0)
	var step := minf(delta, 1.0 / 30.0)
	var steps := ceili(delta / step)
	for i in steps:
		var force := (pull - sway) * sway_stiffness - _sway_speed * sway_damping
		_sway_speed += force * step
		sway += _sway_speed * step
	sway = sway.limit_length(sway_limit)


## Where the gun hand's wrist goes in the carry now, from the chest, and how
## the gun turns from straight ahead (pitch, yaw, roll), for `gun`: the low
## ready blended toward the sprint carry, plus the stride's bob and the sway.
func carry_point(gun: Gun) -> Vector3:
	var side := gun != null and gun.is_sidearm
	var low_at := carry_low_sidearm if side else carry_low_long
	var port_at := carry_port_sidearm if side else carry_port_long
	return low_at.lerp(port_at, sprint) + carry_bob() + sway


func carry_turn(gun: Gun) -> Vector3:
	var side := gun != null and gun.is_sidearm
	var low_turn := carry_low_sidearm_turn if side else carry_low_long_turn
	var port_turn := carry_port_sidearm_turn if side else carry_port_long_turn
	var drop := cos(TAU * 2.0 * stride_phase) * stride_amount
	return low_turn.lerp(port_turn, sprint) + Vector3(-bob_tip * drop, 0.0, 0.0)


## A turn given as pitch (up), yaw (toward the off side) and roll (top
## toward the off side), in radians, from straight ahead.
static func turn_basis(turn: Vector3) -> Basis:
	return Basis(Vector3.UP, turn.y) * Basis(Vector3.RIGHT, turn.x) * Basis(Vector3.BACK, turn.z)


## How much the off hand holds the carried gun (0..1).
func carry_support(gun: Gun) -> float:
	var side := gun != null and gun.is_sidearm
	return lerpf(carry_support_low, carry_support_port_sidearm if side else carry_support_port_long, sprint)


## The stride's bob of a carried gun, in the actor's frame: down at each
## footfall, side to side once a cycle, bigger the harder the body moves.
func carry_bob() -> Vector3:
	if stride_amount <= 0.0:
		return Vector3.ZERO
	var drop := lerpf(bob_drop.x, bob_drop.y, sprint) * stride_amount
	var swing := lerpf(bob_swing.x, bob_swing.y, sprint) * stride_amount
	return Vector3(swing * sin(TAU * stride_phase), -drop * cos(TAU * 2.0 * stride_phase), 0.0)


## Moves the toy hold and throw on by `delta` seconds. A throw starts when
## `Actor.toy_throws` goes up (not for the count first seen: a body that
## comes into view mid-game does not replay an old throw).
## Eases the emote in and out from the held `ActorCommand.emote`. None
## shows while down, riding, in the air or with the phone out, whatever the
## command says, so a late packet never sits a body on a bike.
func advance_emote(delta: float) -> void:
	var wanted := Emotes.id_of(actor.cmd.emote) if actor.cmd != null else ""
	if actor.is_dead or actor.vehicle != null or actor.airborne_time > 0.15 or (actor.cmd != null and actor.cmd.phone):
		wanted = ""
	if wanted != "" and wanted != emote_id:
		# A new one: it starts again from its first beat (from the last
		# one's pose, which it blends out of as it comes in).
		emote_id = wanted
		emote_clock = 0.0
		_emote_raise = minf(_emote_raise, 0.5)
	if emote_id != "":
		emote_clock += delta
	_emote_raise = move_toward(_emote_raise, 1.0 if wanted != "" else 0.0, emote_rate * delta)
	emote = smoothstep(0.0, 1.0, _emote_raise)
	if emote <= 0.0 and wanted == "":
		emote_id = ""
		emote_clock = 0.0


func advance_toy(delta: float) -> void:
	if _toy_throws_seen < 0:
		_toy_throws_seen = actor.toy_throws
	if actor.toy_throws != _toy_throws_seen:
		_toy_throws_seen = actor.toy_throws
		toy_throw_t = 0.0 if not actor.is_dead else -1.0
		_toy_thrown = actor.toy_in_hand
	elif toy_throw_t >= 0.0:
		toy_throw_t += delta
		if toy_throw_t >= toy_throw_time or actor.is_dead:
			toy_throw_t = -1.0
	# The toy thrown may stay in the hand's record a moment after it has
	# flown (online, until the server says so): it is gone all the same.
	if actor.toy_in_hand != _toy_thrown:
		_toy_thrown = ""
	var holding := held_toy() != "" and toy_hand_free
	if toy_throw_t >= 0.0:
		# A throw takes the hand at once and hands it back as it ends.
		var going := smoothstep(toy_follow_at, toy_throw_time, toy_throw_t) if not holding else 0.0
		toy = minf(maxf(toy, smoothstep(0.0, 0.08, toy_throw_t)), 1.0 - going)
	else:
		toy = move_toward(toy, 1.0 if holding else 0.0, toy_rate * delta)


## The toy held up in the hand (not one already thrown), or "".
func held_toy() -> String:
	if actor.is_dead or actor.vehicle != null or actor.toy_in_hand == _toy_thrown:
		return ""
	return actor.toy_in_hand


## The toy the hand shows: held, or thrown and not yet let go. "" for none.
func toy_shown() -> String:
	if actor.is_dead or actor.vehicle != null:
		return ""
	if toy_throw_t >= 0.0:
		return _toy_thrown if toy_throw_t < toy_release else ""
	return held_toy()


## True while the hand is busy with a toy (held up or mid-throw): the weapon
## stays put away.
func toy_busy() -> bool:
	return toy > 0.0 or toy_throw_t >= 0.0 or held_toy() != ""


## Where the throwing hand goes now, in the actor's frame: up holding the toy,
## or along the throw (back over the shoulder, through the release, down
## across the body).
func toy_hand_point() -> Vector3:
	var at := toy_hold
	var t := toy_throw_t
	if t >= 0.0:
		if t < toy_cocked_at:
			at = toy_hold.lerp(toy_cocked, smoothstep(0.0, toy_cocked_at, t))
		elif t < toy_release:
			# The whip: slow out of the cock, fastest at the release.
			var u := (t - toy_cocked_at) / maxf(toy_release - toy_cocked_at, 0.001)
			at = _toy_arc(toy_cocked, toy_let_go, u * u)
		else:
			var u := clampf((t - toy_release) / maxf(toy_follow_at - toy_release, 0.001), 0.0, 1.0)
			at = toy_let_go.lerp(toy_follow, 1.0 - (1.0 - u) * (1.0 - u))
	var pitch := clampf(actor.cmd.pitch if actor.cmd != null else 0.0, -1.2, 1.2) * toy_pitch_share
	return shoulder + Basis(Vector3.RIGHT, pitch) * (at - shoulder)


## From `from` to `to` over the top of the shoulder, not straight through it.
func _toy_arc(from: Vector3, to: Vector3, u: float) -> Vector3:
	return from.lerp(to, u) + Vector3(0.0, 0.12, 0.0) * sin(u * PI)


## The shoulder turn and lean of the throw (as `turn`), 0 outside one.
func toy_turn() -> Vector2:
	var t := toy_throw_t
	if t < 0.0:
		return Vector2.ZERO
	if t < toy_cocked_at:
		return toy_turn_cocked * smoothstep(0.0, toy_cocked_at, t)
	if t < toy_release:
		return toy_turn_cocked.lerp(toy_turn_thrown, smoothstep(toy_cocked_at, toy_release, t))
	return toy_turn_thrown * (1.0 - smoothstep(toy_release, toy_throw_time, t))


## How cocked the throwing elbow is (0 to 1): up and back through the draw,
## dropping as the arm comes through.
func toy_elbow_raise() -> float:
	var t := toy_throw_t
	if t < 0.0:
		return 0.0
	return smoothstep(0.0, toy_cocked_at, t) * (1.0 - smoothstep(toy_cocked_at, toy_follow_at, t))


## True while `gun` should be up at the eye: aimed, in hand, shown, not
## mid-reload, on foot or riding, and not one that is braced at the hip.
func ads_wanted(gun: Gun) -> bool:
	if gun == null or actor.is_dead or not gun.is_aiming() or reload > 0.0:
		return false
	if gun.visual == null or not gun.visual.visible:
		return false
	return not shoulders_never(gun)


## The aiming stance for `gun` (see `ads_stance_long`).
func ads_stance(gun: Gun) -> Vector2:
	if gun == null:
		return Vector2.ZERO
	return ads_stance_sidearm if gun.is_sidearm else ads_stance_long


## True for a gun that is aimed from the hip (`ads_hip_tags`).
func shoulders_never(gun: Gun) -> bool:
	for tag in ads_hip_tags:
		if ItemDB.has_tag(gun.item_id, tag):
			return true
	return false


## How far in front of the eyes the sight of `gun` sits when sighted.
## An optic's "Sight" marker is already its eye point, so it needs none.
func relief_for(gun: Gun) -> float:
	if optic_sight(gun) != null:
		return 0.0
	if gun.is_sidearm or ItemDB.has_tag(gun.item_id, "sidearm"):
		return sidearm_relief
	var box := model_box(gun)
	if box.size == Vector3.ZERO:
		return min_relief
	return maxf(box.end.z - stock_ahead - sight_local(gun).z, min_relief)


## The bounds of the gun as drawn, in the space of its visual (worked out
## once it has a model, and kept). Empty with nothing drawn.
static func model_box(gun: Gun) -> AABB:
	if gun.visual.has_meta("model_box"):
		return gun.visual.get_meta("model_box")
	var box := AABB()
	var first := true
	var to_visual := gun.visual.global_transform.affine_inverse()
	for node in gun.visual.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null or not mesh.visible:
			continue
		var part: AABB = (to_visual * mesh.global_transform) * mesh.get_aabb()
		box = part if first else box.merge(part)
		first = false
	if not first and gun.visual.has_node("Model"):
		gun.visual.set_meta("model_box", box)
	return box


## The fitted optic's eye point, or null for plain sights.
static func optic_sight(gun: Gun) -> Node3D:
	if gun == null or gun.visual == null:
		return null
	return gun.visual.get_node_or_null("Attachments/optic/Sight") as Node3D


## Where you look along `gun` from, in the space of its visual: an optic's
## eye point, else the rear of the plain sights, the top of the model a
## little way in from its back end (worked out once and kept).
static func sight_local(gun: Gun) -> Vector3:
	var optic := optic_sight(gun)
	if optic != null:
		return gun.visual.global_transform.affine_inverse() * optic.global_position
	var iron := gun.visual.get_node_or_null("IronSight") as Node3D
	if iron != null:
		return iron.position
	var box := model_box(gun)
	if box.size == Vector3.ZERO:
		return Vector3(0.0, 0.08, 0.0)
	return Vector3(box.get_center().x, box.end.y, box.end.z - box.size.z * 0.25)


## Where the gun hand holds `gun`, in the space of its visual: the origin
## where the fist closes on the pistol grip, level with the trigger, and
## the basis's y up along the grip (the "Grip" marker that `Look` finds on
## the model, see `Look._measure_hold`). Null on a model without one.
static func hold_local(gun: Gun) -> Variant:
	if gun == null or gun.visual == null:
		return null
	var mark := gun.visual.get_node_or_null("Grip") as Node3D
	if mark == null:
		mark = gun.visual.get_node_or_null("Model/Grip") as Node3D
	if mark == null:
		return null
	# Read through how the model sits in the hand, not where a draw or
	# holster is carrying it this frame (`ActorSkin._carry_moving`).
	var at := mark.transform
	var up_node := mark.get_parent_node_3d()
	while up_node != null and up_node != gun.visual:
		at = (up_node.get_meta("held_at", up_node.transform) as Transform3D) * at
		up_node = up_node.get_parent_node_3d()
	var up := (at.basis * (mark.get_meta("up", Vector3.UP) as Vector3)).normalized()
	var side := Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD
	var back := side.cross(up).normalized()
	return Transform3D(Basis(up.cross(back).normalized(), up, back), at.origin)


## Where the sight of `gun` is drawn, wherever the physics tick left the
## hand node: the hand as the skin last showed it, kept from the actor
## ("shown_local", set by `WeaponArm.hold_weapon`) and carried along to
## where the actor is now, the way the eyes are. A view that follows the
## sight then never sees the tick's resting hand or a frame's lag behind the
## body (both showed as a stutter while aiming).
static func sight_shown(gun: Gun) -> Vector3:
	return shown_global(gun, Transform3D(Basis.IDENTITY, gun.visual.global_transform * sight_local(gun))).origin


## Where something carried on `gun` (given by its global transform as the
## node stands) is drawn this frame, read the same way as the sight: from
## the hand as it was posed, never where a physics tick parked it.
static func shown_global(gun: Weapon, global: Transform3D) -> Transform3D:
	var hand := gun.visual.get_parent() as Node3D
	if hand == null or not hand.has_meta("shown_local"):
		return global
	var holder := hand.get_parent() as Node3D
	var shown: Transform3D = holder.global_transform * (hand.get_meta("shown_local") as Transform3D)
	return shown * (hand.global_transform.affine_inverse() * global)


## The hand offset the current melee state asks for, or null when the
## animation should have the hand.
func arm_reach(melee: MeleeWeapon) -> Variant:
	if melee == null or actor.is_dead or rolling():
		return null
	var normal: Variant = _arm_reach(melee)
	if reel <= 0.0:
		return normal
	var from: Vector3 = normal if normal != null else Vector3.ZERO
	return from.lerp(reel_reach, ease(reel, -1.8))


func _arm_reach(melee: MeleeWeapon) -> Variant:
	if melee.is_kicking():
		# A kick keeps the weapon held ready while the leg works.
		return ready_reach(melee)
	if melee._slamming:
		return windup_reach(melee, MeleeWeapon.Dir.OVERHEAD)
	if melee.showing_back_strike():
		return arm_back * (0.4 + 0.6 * maxf(melee.swing_arc(), 0.0))
	var arc := melee.swing_arc()
	if arc >= 0.0:
		return keyed_reach(melee, melee.attack_dir, arc)
	if melee.is_winding_up():
		return windup_reach(melee, melee.attack_dir) * (1.0 + windup_coil * melee.windup_coil())
	if _follow_left > 0.0:
		return follow_reach(melee, _follow_dir)
	if melee.is_blocking():
		return guard_keys(melee, melee.guard_dir)[0]
	var hold: Variant = ready_reach(melee)
	var rest: Vector3 = hold if hold != null else Vector3.ZERO
	var charge := charge_amount(melee)
	if charge > 0.0:
		return rest.lerp(windup_reach(melee, MeleeWeapon.swing_from(melee.stance)), charge)
	var back := recover_left(melee)
	if back > 0.0:
		return rest.lerp(follow_reach(melee, melee.attack_dir), back)
	if inspect_for("melee") > 0.0:
		# The resting hand's offset (from `Actor.HAND_REST`, in the aim
		# frame) that puts it on the inspect point, eased from the hold.
		var aim := actor.global_basis.orthonormalized() * Basis(Vector3.RIGHT, actor.cmd.pitch)
		var at := actor.global_transform * Actor.HAND_REST
		return rest.lerp(aim.inverse() * (inspect_point() - at), inspect)
	return hold


## The ready hold `melee` is held in at rest (an entry of `ready_holds`), or
## an empty array for a two-handed weapon, which is carried instead.
func ready_hold(melee: MeleeWeapon) -> Array:
	if melee == null or melee.is_two_handed():
		return []
	return ready_holds.get(Look.ready_hold(melee), [])


## Where the hand is held ready (`ready_holds`), or null.
func ready_reach(melee: MeleeWeapon) -> Variant:
	var hold := ready_hold(melee)
	return hold[0] if not hold.is_empty() else null


## How the weapon stands in the hand held ready, in the aim frame, as the
## turn of the hand node (the weapon's own rest pitch taken back out), or
## null when it has no ready hold.
func ready_turn(melee: MeleeWeapon) -> Variant:
	var hold := ready_hold(melee)
	if hold.is_empty():
		return null
	var points := (hold[1] as Vector3).normalized()
	return Basis(Quaternion(Vector3.UP, points)) * Basis(Vector3.RIGHT, -MeleeWeapon.REST_POSE)


## True while the blade is held reversed in the fist (`ready_holds`): from
## halfway into the ready hold, so it turns over as an attack starts.
func ready_reversed(melee: MeleeWeapon) -> bool:
	var hold := ready_hold(melee)
	return not hold.is_empty() and hold[3] and held_ready > 0.5


## What the off hand does in the ready hold: "guard" (up empty, low in
## front), "hilt" (on the handle under the weapon hand) or "" (nothing).
func ready_off(melee: MeleeWeapon) -> String:
	var hold := ready_hold(melee)
	return hold[2] if not hold.is_empty() else ""


## How much the ready hold has the weapon (0..1): all of it at rest, none
## through an attack or guard, and part of it while drawing back for a heavy
## or easing back after a strike.
func ready_amount(melee: MeleeWeapon) -> float:
	if melee == null or actor.is_dead or ready_hold(melee).is_empty():
		return 0.0
	if melee._slamming or melee.showing_back_strike() or melee.swing_arc() >= 0.0:
		return 0.0
	if melee.is_kicking():
		return 1.0
	if melee.is_winding_up() or _follow_left > 0.0 or melee.is_blocking():
		return 0.0
	var charge := charge_amount(melee)
	if charge > 0.0:
		return 1.0 - charge
	# Looked over, the weapon turns in the hand as the inspect says.
	return (1.0 - recover_left(melee)) * (1.0 - inspect_for("melee")) * (1.0 - reel)


## The shoulder turn and lean that go with `arm_reach`: heavier for a
## two-hander, leaning in through a dash-strike.
func body_turn(melee: MeleeWeapon) -> Vector2:
	if melee == null or actor.is_dead:
		return Vector2.ZERO
	var turned := _body_turn(melee)
	if melee.is_two_handed():
		turned *= two_hand_turn
	if reel > 0.0:
		turned = turned.lerp(reel_turn, ease(reel, -1.8))
	if melee._dashing and melee.is_lunging():
		turned.y -= dash_lean
	return turned


func _body_turn(melee: MeleeWeapon) -> Vector2:
	if melee.is_kicking():
		return Vector2.ZERO
	if melee._slamming:
		return windup_turn(melee, MeleeWeapon.Dir.OVERHEAD)
	if melee.showing_back_strike():
		return turn_back
	var arc := melee.swing_arc()
	if arc >= 0.0:
		return windup_turn(melee, melee.attack_dir).lerp(follow_turn(melee, melee.attack_dir), arc)
	if melee.is_winding_up():
		return windup_turn(melee, melee.attack_dir) * (1.0 + windup_coil * melee.windup_coil())
	if _follow_left > 0.0:
		return follow_turn(melee, _follow_dir)
	if melee.is_blocking():
		# Squared up behind the guard, the guarded side's shoulder a little
		# forward.
		return Vector2(-MeleeWeapon._side(melee.guard_dir) * guard_turn, -0.04)
	var charge := charge_amount(melee)
	if charge > 0.0:
		return windup_turn(melee, MeleeWeapon.swing_from(melee.stance)) * charge
	var back := recover_left(melee)
	if back > 0.0:
		return follow_turn(melee, melee.attack_dir) * back
	return Vector2.ZERO


## Where the hand is cocked for a swing from `dir`, by the weapon's
## technique, scaled by its `swing_scale` (a knife's swings are small)
## about `swing_centre`, so a small swing still crosses the middle of the
## view.
func windup_reach(melee: MeleeWeapon, dir: int) -> Vector3:
	var key: Variant = technique_key(melee, dir)
	var at: Vector3 = _swing_keys(melee, key)[0][0]
	if key is int and is_heavy(melee):
		at += cut_heavy_raise
	return _scaled(at, melee)


## Where the hand ends a swing from `dir`.
func follow_reach(melee: MeleeWeapon, dir: int) -> Vector3:
	return _scaled(_swing_keys(melee, technique_key(melee, dir))[2][0], melee)


## `at` (a hand offset) drawn in toward `swing_centre` by `swing_scale`.
func _scaled(at: Vector3, melee: MeleeWeapon) -> Vector3:
	return swing_centre + (at - swing_centre) * melee.swing_scale


## The shoulder turn and lean for a windup from `dir`.
func windup_turn(melee: MeleeWeapon, dir: int) -> Vector2:
	var key: Variant = technique_key(melee, dir)
	var turned: Vector2 = _turn_keys(melee, key)[0]
	return turned * (cut_heavy_coil if key is int and is_heavy(melee) else 1.0)


## The shoulder turn and lean at the end of a swing from `dir`.
func follow_turn(melee: MeleeWeapon, dir: int) -> Vector2:
	return _turn_keys(melee, technique_key(melee, dir))[1]


## How cocked the elbow should be for the current melee state (0..1).
func elbow_wanted(melee: MeleeWeapon) -> float:
	if melee == null or actor.is_dead:
		return 0.0
	var arc := melee.swing_arc()
	if arc >= 0.0:
		return 1.0 - arc
	if melee._slamming or melee.is_winding_up():
		return 1.0
	if melee.is_blocking():
		return 0.6
	return maxf(charge_amount(melee), 0.0)


## The weapon elbow's pole in the actor's frame, between cocked and thrown
## (lower through a two-handed technique).
func elbow_pole() -> Vector3:
	var pole := elbow_thrown.lerp(elbow_cocked, elbow_raise)
	var low := maxf(cut_grip, _two_hands)
	return pole.lerp(cut_elbow_thrown.lerp(cut_elbow_cocked, elbow_raise), low)


## Which technique `melee` fights with now (a key of `techniques`): its
## swing style, a knife's own (a reverse grip), and two-handed where it is.
func technique(melee: MeleeWeapon) -> String:
	var style := melee.style_now()
	if style == "cut":
		return "cut"
	if Look.ready_hold(melee) == "knife":
		return "stab" if style == "thrust" else "knife"
	if melee.is_two_handed():
		return "thrust2" if style == "thrust" else "chop2"
	if style == "thrust":
		return "stab"
	return style if techniques.has(style) else "slash"


## The technique's table for `melee` (an entry of `techniques`).
func _technique_of(melee: MeleeWeapon) -> Dictionary:
	return techniques[technique(melee)]


## Which swing `melee` shows from `dir` (a key of its technique's
## "swings"): the side's own, or "heavy" for a heavy from the middle stance
## where the technique has one (the dive slam is still the overhead).
func technique_key(melee: MeleeWeapon, dir: int) -> Variant:
	if dir == MeleeWeapon.Dir.OVERHEAD and not melee._slamming and is_heavy(melee) \
			and (_technique_of(melee)["swings"] as Dictionary).has("heavy"):
		return "heavy"
	return dir


func _swing_keys(melee: MeleeWeapon, key: Variant) -> Array:
	return _technique_of(melee)["swings"][key]


func _turn_keys(melee: MeleeWeapon, key: Variant) -> Array:
	return _technique_of(melee)["turns"][key]


## The guard of `melee` over side `dir`: [hand, blade, edge] (a technique
## without guards of its own, a knife's stab, uses the knife's).
func guard_keys(melee: MeleeWeapon, dir: int) -> Array:
	var tech := _technique_of(melee)
	if not tech.has("guards"):
		tech = techniques["knife"]
	return tech["guards"][dir]


## True while both hands stay on the handle through the technique.
func both_hands(melee: MeleeWeapon) -> bool:
	return _technique_of(melee).get("both", false)


## True while `melee` is showing, winding up or drawing back toward a heavy.
static func is_heavy(melee: MeleeWeapon) -> bool:
	if melee.is_winding_up():
		return melee._windup_kind == "heavy"
	if charge_amount(melee) > 0.0:
		return true
	return melee._shown_kind == "heavy"


## The hand offset `done` (0..1) of the way through the swing from `dir`:
## on a curve from the windup through the contact key (at the hit, half
## way) to the end of the follow-through.
func keyed_reach(melee: MeleeWeapon, dir: int, done: float) -> Vector3:
	var from := windup_reach(melee, dir)
	var to := follow_reach(melee, dir)
	var hit := _scaled(_swing_keys(melee, technique_key(melee, dir))[1][0], melee)
	var bend := hit * 2.0 - (from + to) * 0.5
	var t := clampf(done, 0.0, 1.0)
	return from * (1.0 - t) * (1.0 - t) + bend * 2.0 * t * (1.0 - t) + to * t * t


## How the technique has the blade this frame, in the aim frame (the
## weapon's own frame turned so its blade runs the way the keys say and its
## edge leads), or null when none has it (at rest the ready hold does, a
## back strike its own). Both views turn the weapon hand by it
## (`WeaponArm._blade_turn`).
func technique_blade(melee: MeleeWeapon) -> Variant:
	if melee == null or actor.is_dead or melee.showing_back_strike() or melee.is_kicking() or rolling():
		return null
	if melee._slamming:
		return _blade_at(melee, technique_key(melee, MeleeWeapon.Dir.OVERHEAD), 0.0)
	var arc := melee.swing_arc()
	if arc >= 0.0:
		return _blade_at(melee, technique_key(melee, melee.attack_dir), arc)
	if melee.is_winding_up():
		return _blade_at(melee, technique_key(melee, melee.attack_dir), 0.0)
	if _follow_left > 0.0:
		return _blade_at(melee, technique_key(melee, _follow_dir), 1.0)
	if melee.is_blocking():
		var guard := guard_keys(melee, melee.guard_dir)
		return blade_basis(guard[1], guard[2])
	var hold := ready_hold(melee)
	var rest := Basis(Quaternion(Vector3.UP, (hold[1] as Vector3).normalized())) if not hold.is_empty() else Basis.IDENTITY
	var charge := charge_amount(melee)
	if charge > 0.0:
		return _blend(rest, _blade_at(melee, technique_key(melee, MeleeWeapon.swing_from(melee.stance)), 0.0), charge)
	var back := recover_left(melee)
	if back > 0.0:
		return _blend(rest, _blade_at(melee, technique_key(melee, melee.attack_dir), 1.0), back)
	return null


## The blade `done` of the way through the swing `key` of `melee`'s
## technique: turned from the windup through the contact key to the
## follow-through, the edge leading the way it turns (down, for a thrust
## straight out, where it barely turns).
func _blade_at(melee: MeleeWeapon, key: Variant, done: float) -> Basis:
	var keys := _swing_keys(melee, key)
	var a := (keys[0][1] as Vector3).normalized()
	var b := (keys[1][1] as Vector3).normalized()
	var c := (keys[2][1] as Vector3).normalized()
	var t := clampf(done, 0.0, 1.0)
	var dir := a.slerp(b, t * 2.0) if t < 0.5 else b.slerp(c, t * 2.0 - 1.0)
	var lead := b - a if t < 0.5 else c - b
	if lead.length() < 0.25:
		lead = Vector3.DOWN
	return blade_basis(dir, lead)


## The weapon's frame with its blade along `dir` and its edge (`cut_edge`)
## turned as near `edge` as it can face, both in the aim frame.
func blade_basis(dir: Vector3, edge: Vector3) -> Basis:
	var up := dir.normalized()
	var face := edge - up * edge.dot(up)
	if face.length() < 0.05:
		face = Vector3.DOWN - up * up.y
		if face.length() < 0.05:
			face = Vector3.FORWARD
	face = face.normalized()
	var own_face := (cut_edge - Vector3.UP * cut_edge.y).normalized()
	var wanted := Basis(up, face, up.cross(face))
	var own := Basis(Vector3.UP, own_face, Vector3.UP.cross(own_face))
	return (wanted * own.inverse()).orthonormalized()


static func _blend(from: Basis, to: Basis, weight: float) -> Basis:
	return Basis(from.get_rotation_quaternion().slerp(to.get_rotation_quaternion(), clampf(weight, 0.0, 1.0)))


## How far the arm is drawn back while the button is held toward a heavy
## (0..1), toward the side the swing will come from, or -1 when not.
static func charge_amount(melee: MeleeWeapon) -> float:
	var held := -1.0
	if melee._charge >= 0.0:
		held = melee._charge
	elif melee._queued and melee._queued_held >= 0.0:
		held = melee._queued_held
	if held < 0.0:
		return -1.0
	return clampf(held / maxf(melee.hold_time, 0.01), 0.0, 1.0)


## How much of the follow-through the arm still holds while the blade
## recovers after a strike (1 just after, easing to 0 once ready), so the
## wait before the next attack shows in both views.
static func recover_left(melee: MeleeWeapon) -> float:
	var done := melee.recover_progress()
	if done < 0.0:
		return 0.0
	# The next cut already asked for: the arm stays where this one ended and
	# flows straight into its windup, rather than going back to the guard.
	if melee._queued:
		return 1.0
	return 1.0 - smoothstep(0.0, 1.0, done)


## How far through the shown swing (0 to 1), or 0 when none is showing.
static func swing_progress(melee: MeleeWeapon) -> float:
	return maxf(melee.swing_arc(), 0.0)


## How deep into the reload motion `gun` is: 0 outside a reload, easing to 1
## over the first `reload_ease` of it, held, and back to 0 as it ends.
func reload_depth(gun: Gun) -> float:
	if gun == null or not gun.is_reloading() or gun.reload_time <= 0.0:
		return 0.0
	var done := 1.0 - clampf(gun.reload_left() / gun.reload_time, 0.0, 1.0)
	var ease_in := smoothstep(0.0, reload_ease, done)
	var ease_out := 1.0 - smoothstep(1.0 - reload_ease, 1.0, done)
	return minf(ease_in, ease_out)


## The gun's offset from its usual hold, in the aim frame: the reload
## motion, and the gun brought in and turned while it is looked over.
func gun_offset() -> Transform3D:
	var reloading := Transform3D(Basis.from_euler(reload_tilt * reload), reload_reach * reload)
	if inspecting() != "gun":
		return reloading
	return Transform3D(inspect_basis(), Vector3.ZERO) * reloading


## Where the wrist goes to look the item in hand over, in the world: in
## front of the chest, under the eyes along the aim (`inspect_from_eyes`).
func inspect_point() -> Vector3:
	var pitch := clampf(actor.cmd.pitch, inspect_pitch.x, inspect_pitch.y)
	var aim := actor.global_basis.orthonormalized() * Basis(Vector3.RIGHT, pitch)
	return actor.get_eye_position() + aim * inspect_from_eyes


## Where the gun wrist is brought for a reload, in the world: in front of
## the chest, under the eyes along the aim (`reload_from_eyes`).
func reload_point() -> Vector3:
	var pitch := clampf(actor.cmd.pitch, inspect_pitch.x, inspect_pitch.y)
	var aim := actor.global_basis.orthonormalized() * Basis(Vector3.RIGHT, pitch)
	return actor.get_eye_position() + aim * reload_from_eyes


## What is being looked over: "gun", "melee", "hand" (a toy vehicle held
## up, `Actor.toy_in_hand`), or "" when nothing is.
func inspecting() -> String:
	if inspect <= 0.0 or actor == null or actor.is_dead:
		return ""
	if toy_busy():
		return "hand"
	var weapon := actor.get_active_weapon()
	if weapon == null or weapon.visual == null or not weapon.visual.visible:
		return "hand"
	if weapon is Gun:
		return "gun"
	if weapon is MeleeWeapon:
		return "melee"
	return "hand"


## How much of the hand's (or gun's) own reach and turn the look over has,
## for what `inspecting` says is in hand: 0 when something else is.
func inspect_for(what: String) -> float:
	return inspect if inspecting() == what else 0.0


## How the item in hand is turned now while looked over, in the aim frame
## (identity when it is not).
func inspect_basis() -> Basis:
	if inspect <= 0.0:
		return Basis.IDENTITY
	return Basis.from_euler(inspect_turn(inspect_clock) * inspect)


## The turn `seconds` into a look over (`INSPECT_TURNS`), eased between
## the steps, back to none once it is done.
static func inspect_turn(seconds: float) -> Vector3:
	var last: Array = INSPECT_TURNS[INSPECT_TURNS.size() - 1]
	if seconds <= 0.0 or seconds >= float(last[0]):
		return Vector3.ZERO
	for i in range(1, INSPECT_TURNS.size()):
		var to: Array = INSPECT_TURNS[i]
		if seconds <= float(to[0]):
			var from: Array = INSPECT_TURNS[i - 1]
			var done := (seconds - float(from[0])) / maxf(float(to[0]) - float(from[0]), 0.001)
			return (from[1] as Vector3).lerp(to[1], smoothstep(0.0, 1.0, done))
	return Vector3.ZERO


## How far the off hand is on the helmet at `stow` (see `helmet`): it comes
## up to the head before the helmet leaves it (`Actor.HELMET_LIFTED`), stays
## on it all the way down and lets go once it is clipped on, and the same
## backwards to put it on.
static func helmet_hand(stow: float) -> float:
	return smoothstep(0.0, Actor.HELMET_LIFTED - 0.05, stow) * (1.0 - smoothstep(0.8, 1.0, stow))


## How far the weapon hand is on the helmet at `stow`: both hands lift it
## off the head (and set it on), and the weapon hand lets go a little way
## down, leaving the off hand to clip it on. Only with nothing in that hand
## (`PlayerController.toggle_helmet` puts a drawn weapon away first).
static func helmet_both(stow: float) -> float:
	return smoothstep(0.08, Actor.HELMET_LIFTED - 0.03, stow) * (1.0 - smoothstep(0.42, 0.58, stow))


## How far the helmet is on its way from the head (0) to the hip clip (1).
static func helmet_carry(stow: float) -> float:
	return smoothstep(Actor.HELMET_LIFTED, HELMET_CLIPPED, stow)


## Where the helmet hangs at `stow`: "head", "hand" (carried between) or "hip".
static func helmet_place(stow: float) -> String:
	if stow < Actor.HELMET_LIFTED:
		return "head"
	return "hand" if stow < HELMET_CLIPPED else "hip"


## How far into the take off the helmet is on its clip.
const HELMET_CLIPPED := 0.78
