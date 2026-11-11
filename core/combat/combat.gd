class_name Combat
extends RefCounted
## The single entry point for dealing damage.
## It asks the current world whether the hit is allowed, so PvP rules,
## friendly fire and safe zones are decided by the world, not by weapons.


static func deal(target: Object, info: DamageInfo) -> bool:
	var actor := target as Actor
	if actor == null or actor.is_dead:
		return false
	var world: WorldDef = Worlds.current
	if world and not world.can_damage(info.source, actor, info):
		return false
	actor.health.apply_damage(info)
	return true
