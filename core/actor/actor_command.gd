class_name ActorCommand
extends RefCounted
## One tick of intent for an Actor.
##
## This is the seam that keeps the game netcode-ready: the local player, bots,
## and (later) remote clients all drive an Actor only by filling in a command.
## The Actor simulation never reads the keyboard or mouse directly, so the same
## simulation can run on a dedicated server.

## x = strafe right, y = forward. Each in -1..1, relative to yaw.
var move := Vector2.ZERO
## Look angles in radians. Yaw turns the body, pitch only affects aiming.
var yaw := 0.0
var pitch := 0.0
## World-space aim direction. If zero, the Actor derives it from yaw and pitch.
var aim_dir := Vector3.ZERO

var sprint := false
## Held: thrust with the flight rig while airborne.
var jump := false
## Pressed this tick: jump off the ground.
var jump_pressed := false
var dash := false

## Primary and secondary weapon actions (fire / aim, light / heavy attack).
var primary := false
var primary_pressed := false
var secondary := false
var secondary_pressed := false
## A weapon's special action (heavy attack for melee).
var tertiary_pressed := false
var reload_pressed := false
## Melee stance, a `MeleeWeapon.Dir`: 0 overhead, 1 left, 2 right. Attacks and
## guards take the stance they start in. It stays until changed.
var stance := 0

var interact_pressed := false
var heal_pressed := false
## Pressed this tick: use the equipped ability.
var ability_pressed := false
## Index of the weapon to switch to, or -1 to keep the current one.
var switch_weapon := -1


## Clears everything that should only last a single tick.
func clear_one_shots() -> void:
	jump_pressed = false
	dash = false
	primary_pressed = false
	secondary_pressed = false
	tertiary_pressed = false
	reload_pressed = false
	interact_pressed = false
	heal_pressed = false
	ability_pressed = false
	switch_weapon = -1
