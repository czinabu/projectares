class_name CarryLoad
extends RefCounted
## Carry weight (DESIGN.md section 4, "Weight"): what everything a body
## carries weighs, the tier that puts it in (light, medium or heavy), and what
## that does to how it moves. Never a hard limit: nothing is refused for being
## heavy, a heavier load only moves a little slower.
##
## Everything carried counts: the gear worn (weapons, the heavy weapon in the
## chamber, rig, frame, helmet, backpack) and the pack's contents, so a big
## haul home slows you as much as a big frame does. An item weighs its
## `weight` stat (kilograms) if it has one, otherwise what its first tag in
## `TAG_WEIGHTS` says, otherwise `OTHER_KG`.
##
## A medium load moves as the rules are tuned. Lighter than `LIGHT_KG` the
## body speeds up a little, more the lighter it is, down to `FEATHER_KG`;
## heavier than `HEAVY_KG` it slows a little more every kilogram, to a floor.
## The load scales ground speed, sprint and slide (`speed_mult`),
## acceleration and turning on foot and in the air (`accel_mult`), the heat a
## flight rig builds (`heat_mult`, a jetpack taking half of a heavy load's
## extra) and, only over `HEAVY_KG`, the jump (`jump_mult`). A rig's top
## flight speed never changes.
##
## `Actor` keeps the numbers (`Actor.carry_kg`, refreshed when what it
## carries changes); a client is sent each body's load by the server
## (`NetSession._carry`), since it never sees someone else's pack.

## A load under this is light; at `HEAVY_KG` and over it is heavy.
const LIGHT_KG := 14.0
const HEAVY_KG := 32.0
## As light as the light tier's bonus goes: at this or under, it is whole.
const FEATHER_KG := 8.0
## Loads are kept to this step, so the server and a client sent the number
## work from exactly the same value.
const STEP_KG := 0.1

## The light tier at its lightest (`FEATHER_KG`): this much faster on the
## ground, quicker to accelerate and turn, and this much less rig heat.
const LIGHT_SPEED := 0.06
const LIGHT_ACCEL := 0.15
const LIGHT_HEAT := 0.2
## Every kilogram over `HEAVY_KG`: this much slower, slower to accelerate,
## more rig heat, and a lower jump, each to its floor (or cap).
const HEAVY_SPEED_PER_KG := 0.006
const HEAVY_ACCEL_PER_KG := 0.012
const HEAVY_HEAT_PER_KG := 0.015
const HEAVY_JUMP_PER_KG := 0.008
const MIN_SPEED := 0.8
const MIN_ACCEL := 0.65
const MAX_HEAT := 1.45
## The jump's floor, as a share of the take-off speed: about 1 m of the
## usual 1.2 m, so a heavy load still clears what a normal jump does most of.
const MIN_JUMP := 0.92
## A jetpack carries heavy loads: it takes this share of the extra heat.
const HEAVY_LIFT_SHARE := 0.5

## Weight by tag (kilograms), the first tag an item has in this order. An
## item's own `weight` stat comes first. Tags for kinds of weapon come before
## the general ones.
const TAG_WEIGHTS := [
	["minigun", 20.0], ["power", 13.0], ["hammer", 9.0], ["marksman", 6.0], ["shotgun", 4.5],
	["rifle", 4.0], ["smg", 2.5], ["sidearm", 1.2], ["spear", 3.5], ["axe", 2.5], ["blade", 2.0],
	["knife", 0.3], ["firearm", 4.0], ["melee", 2.0], ["frame_heavy", 22.0], ["frame_medium", 11.0],
	["frame_light", 5.0], ["armor", 11.0], ["visor_plain", 1.0], ["helmet", 1.5], ["flight_rig", 5.0],
	["backpack", 2.0], ["attachment", 0.3], ["ability", 0.2], ["artifact", 1.0], ["heal", 0.5],
	["consumable", 0.5], ["material", 1.0], ["relic", 1.0], ["trophy", 2.0], ["augment", 0.2],
	["blueprint", 0.0], ["upgrade_data", 0.0], ["vehicle", 0.0], ["cosmetic", 0.0], ["mounted", 0.0],
	["airship", 0.0], ["furniture", 0.0], ["paint", 0.0], ["trail", 0.0],
]
## What anything else weighs.
const OTHER_KG := 0.5


## What item `id` weighs, in kilograms.
static func weight_of(id: String) -> float:
	var stats := ItemDB.item_stats(id)
	if stats.has("weight") and not ItemDB.has_tag(id, "vehicle"):
		return float(stats["weight"])
	for entry: Array in TAG_WEIGHTS:
		if ItemDB.has_tag(id, entry[0]):
			return entry[1]
	return OTHER_KG


## What all of `ids` weigh together, kept to `STEP_KG`.
static func total(ids: Array) -> float:
	var kg := 0.0
	for id: String in ids:
		kg += weight_of(id)
	return snappedf(kg, STEP_KG)


## What `actor` carries: its worn gear and its pack, the same list it
## would drop (`Actor.get_drop_items`).
static func of_actor(actor: Actor) -> float:
	return total(actor.get_drop_items())


## "light", "medium" or "heavy" for a load of `kg`.
static func tier(kg: float) -> String:
	if kg < LIGHT_KG:
		return "light"
	if kg >= HEAVY_KG:
		return "heavy"
	return "medium"


## How far into the light tier's bonus a load of `kg` is, 0 to 1.
static func lightness(kg: float) -> float:
	return clampf((LIGHT_KG - kg) / (LIGHT_KG - FEATHER_KG), 0.0, 1.0)


## Kilograms over `HEAVY_KG`, 0 for a light or medium load.
static func over(kg: float) -> float:
	return maxf(0.0, kg - HEAVY_KG)


## Ground speed, sprint and slide for a load of `kg`, as a multiple.
static func speed_mult(kg: float) -> float:
	return maxf(MIN_SPEED, 1.0 + LIGHT_SPEED * lightness(kg) - HEAVY_SPEED_PER_KG * over(kg))


## Acceleration and turning, on foot and in the air, as a multiple.
static func accel_mult(kg: float) -> float:
	return maxf(MIN_ACCEL, 1.0 + LIGHT_ACCEL * lightness(kg) - HEAVY_ACCEL_PER_KG * over(kg))


## A flight rig's heat for a load of `kg`, as a multiple. A jetpack
## (`heavy_lift`) takes only part of a heavy load's extra.
static func heat_mult(kg: float, heavy_lift := false) -> float:
	var mult := minf(MAX_HEAT, 1.0 - LIGHT_HEAT * lightness(kg) + HEAVY_HEAT_PER_KG * over(kg))
	if heavy_lift and mult > 1.0:
		mult = 1.0 + (mult - 1.0) * HEAVY_LIFT_SHARE
	return mult


## The jump's take-off speed for a load of `kg`, as a multiple: whole until
## the load is heavy.
static func jump_mult(kg: float) -> float:
	return maxf(MIN_JUMP, 1.0 - HEAVY_JUMP_PER_KG * over(kg))


## The watch's words for a load: "Medium 22 kg".
static func label(kg: float) -> String:
	return "%s %d kg" % [tier(kg).capitalize(), roundi(kg)]
