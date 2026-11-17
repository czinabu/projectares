class_name HealthComponent
extends Node
## Health plus a degrading armor layer.
## Armor soaks a share of each hit and is used up doing so.

signal damaged(info: DamageInfo)
signal died(info: DamageInfo)

var max_health := 100.0
var health := 100.0
var max_armor := 0.0
var armor := 0.0
## Share of each hit that armor absorbs while it lasts.
var armor_absorb := 0.6
var is_dead := false
## Health never drops below this. Zero means hits can kill. The arena sets it
## while a fight is on, so a beaten fighter yields instead of dying.
var min_health := 0.0


## Applies a hit and returns the health actually lost.
func apply_damage(info: DamageInfo) -> float:
	if is_dead or info.amount <= 0.0:
		return 0.0
	var absorbed := minf(armor, info.amount * armor_absorb * (1.0 - clampf(info.armor_pierce, 0.0, 1.0)))
	armor -= absorbed
	armor = maxf(0.0, armor - info.amount * info.armor_break)
	var lost := minf(health - minf(min_health, health), info.amount - absorbed)
	health -= lost
	damaged.emit(info)
	if health <= 0.0:
		is_dead = true
		died.emit(info)
	return lost


func heal(amount: float) -> void:
	if not is_dead:
		health = minf(max_health, health + amount)


func set_armor(amount: float) -> void:
	max_armor = amount
	armor = amount
