class_name DamageInfo
extends RefCounted
## Describes one hit. Every damage source (guns, melee, slams, the storm) uses
## this so worlds can filter or modify damage in one place.

var amount := 0.0
## The Actor that caused it, or null for world damage.
var source: Node = null
## "bullet", "melee", "slam", "storm", "void", ...
var kind := "bullet"
var position := Vector3.ZERO
## Set by the target's guard: part of the hit was blocked, or all of it parried.
## For melee: the `MeleeWeapon.Dir` the swing comes from, as the attacker sees
## it. Below zero means the hit has no direction.
var direction := -1
## A guard that stops this hit pays this many times the usual stamina.
var guard_mult := 1.0
var blocked := false
## The hit landed on the target's head.
var headshot := false
var parried := false


static func make(p_amount: float, p_source: Node, p_kind: String, p_position := Vector3.ZERO) -> DamageInfo:
	var info := DamageInfo.new()
	info.amount = p_amount
	info.source = p_source
	info.kind = p_kind
	info.position = p_position
	return info
