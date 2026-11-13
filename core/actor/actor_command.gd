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
## Pressed this tick: drop into a slide (only from a run, see `Actor`).
var slide := false
## Held: sink while hovering with a jetpack (the slide key).
var descend := false
## Pressed this tick: the sprint key went down. In the air with a flight rig
## that is a dash the way the move keys point (`FlightRig.air_dash_speed`).
var sprint_pressed := false

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
## Pressed this tick: use the helmet's visor (a scan pulse).
var visor_pressed := false
## Held: the zoom level asked of a helmet with binoculars, 0 for off.
var visor_level := 0
## Index of the weapon to switch to, -1 to keep the current one, or
## `HOLSTER` to put the weapon in hand away.
var switch_weapon := -1

const HOLSTER := -2


## Clears everything that should only last a single tick.
func clear_one_shots() -> void:
	jump_pressed = false
	sprint_pressed = false
	dash = false
	slide = false
	primary_pressed = false
	secondary_pressed = false
	tertiary_pressed = false
	reload_pressed = false
	interact_pressed = false
	heal_pressed = false
	ability_pressed = false
	visor_pressed = false
	switch_weapon = -1


# --- Network form -----------------------------------------------------------
# A command travels as a small array so the server and clients can exchange it.

const ARRAY_SIZE := 10
const FLAGS_INDEX := 7
const STANCE_INDEX := 8
const SWITCH_INDEX := 9

const FLAG_SPRINT := 1
const FLAG_JUMP := 2
const FLAG_PRIMARY := 4
const FLAG_SECONDARY := 8
const FLAG_JUMP_PRESSED := 16
const FLAG_DASH := 32
const FLAG_PRIMARY_PRESSED := 64
const FLAG_SECONDARY_PRESSED := 128
const FLAG_TERTIARY_PRESSED := 256
const FLAG_RELOAD_PRESSED := 512
const FLAG_INTERACT_PRESSED := 1024
const FLAG_HEAL_PRESSED := 2048
const FLAG_ABILITY_PRESSED := 4096
const FLAG_SLIDE := 8192
const FLAG_VISOR_PRESSED := 16384
## The visor's zoom level, two bits wide.
const VISOR_LEVEL_SHIFT := 15
const VISOR_LEVEL_MASK := 3 << VISOR_LEVEL_SHIFT
const FLAG_DESCEND := 131072
const FLAG_SPRINT_PRESSED := 262144
## Not an input: the server sets this bit in the commands it sends back with
## each state, to say the actor's jets are lit (`FlightRig.is_hovering`).
const STATE_HOVERING := 1048576
## Flags that describe a held key, and flags that last a single tick.
const HELD_MASK := FLAG_SPRINT | FLAG_JUMP | FLAG_PRIMARY | FLAG_SECONDARY | VISOR_LEVEL_MASK \
		| FLAG_DESCEND
const ONE_SHOT_MASK := FLAG_JUMP_PRESSED | FLAG_DASH | FLAG_PRIMARY_PRESSED | FLAG_SECONDARY_PRESSED \
		| FLAG_TERTIARY_PRESSED | FLAG_RELOAD_PRESSED | FLAG_INTERACT_PRESSED | FLAG_HEAL_PRESSED \
		| FLAG_ABILITY_PRESSED | FLAG_SLIDE | FLAG_VISOR_PRESSED | FLAG_SPRINT_PRESSED


## Every button, held or pressed, packed into one integer.
func flags() -> int:
	var out := 0
	if sprint: out |= FLAG_SPRINT
	if jump: out |= FLAG_JUMP
	if primary: out |= FLAG_PRIMARY
	if secondary: out |= FLAG_SECONDARY
	if jump_pressed: out |= FLAG_JUMP_PRESSED
	if dash: out |= FLAG_DASH
	if primary_pressed: out |= FLAG_PRIMARY_PRESSED
	if secondary_pressed: out |= FLAG_SECONDARY_PRESSED
	if tertiary_pressed: out |= FLAG_TERTIARY_PRESSED
	if reload_pressed: out |= FLAG_RELOAD_PRESSED
	if interact_pressed: out |= FLAG_INTERACT_PRESSED
	if heal_pressed: out |= FLAG_HEAL_PRESSED
	if ability_pressed: out |= FLAG_ABILITY_PRESSED
	if slide: out |= FLAG_SLIDE
	if descend: out |= FLAG_DESCEND
	if sprint_pressed: out |= FLAG_SPRINT_PRESSED
	if visor_pressed: out |= FLAG_VISOR_PRESSED
	out |= clampi(visor_level, 0, 3) << VISOR_LEVEL_SHIFT
	return out


func to_array() -> Array:
	return [move.x, move.y, yaw, pitch, aim_dir.x, aim_dir.y, aim_dir.z, flags(), stance, switch_weapon]


## Fills this command from `to_array` output. Values are clamped, because on a
## server the array comes from another machine.
func apply_array(data: Array) -> void:
	if data.size() != ARRAY_SIZE:
		return
	move = Vector2(_number(data[0]), _number(data[1])).limit_length(1.0)
	yaw = _number(data[2])
	pitch = clampf(_number(data[3]), -1.5, 1.5)
	var aim := Vector3(_number(data[4]), _number(data[5]), _number(data[6]))
	aim_dir = aim.normalized() if aim.length() > 0.01 else Vector3.ZERO
	var bits := int(_number(data[FLAGS_INDEX]))
	sprint = bits & FLAG_SPRINT != 0
	jump = bits & FLAG_JUMP != 0
	primary = bits & FLAG_PRIMARY != 0
	secondary = bits & FLAG_SECONDARY != 0
	jump_pressed = bits & FLAG_JUMP_PRESSED != 0
	dash = bits & FLAG_DASH != 0
	primary_pressed = bits & FLAG_PRIMARY_PRESSED != 0
	secondary_pressed = bits & FLAG_SECONDARY_PRESSED != 0
	tertiary_pressed = bits & FLAG_TERTIARY_PRESSED != 0
	reload_pressed = bits & FLAG_RELOAD_PRESSED != 0
	interact_pressed = bits & FLAG_INTERACT_PRESSED != 0
	heal_pressed = bits & FLAG_HEAL_PRESSED != 0
	ability_pressed = bits & FLAG_ABILITY_PRESSED != 0
	slide = bits & FLAG_SLIDE != 0
	descend = bits & FLAG_DESCEND != 0
	sprint_pressed = bits & FLAG_SPRINT_PRESSED != 0
	visor_pressed = bits & FLAG_VISOR_PRESSED != 0
	visor_level = (bits & VISOR_LEVEL_MASK) >> VISOR_LEVEL_SHIFT
	stance = clampi(int(_number(data[STANCE_INDEX])), 0, 2)
	switch_weapon = clampi(int(_number(data[SWITCH_INDEX])), HOLSTER, 8)


static func _number(value: Variant) -> float:
	if typeof(value) in [TYPE_FLOAT, TYPE_INT]:
		var number := float(value)
		return number if is_finite(number) else 0.0
	return 0.0
