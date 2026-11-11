class_name Weapon
extends Node
## Base class for anything an Actor can hold and use.

var actor: Actor
var item_id := ""
var display_name := "Weapon"


## Called every physics tick, even while holstered (cooldowns, reloads).
func tick(_delta: float) -> void:
	pass


## Called every physics tick while this is the active weapon.
func handle_input(_cmd: ActorCommand, _delta: float) -> void:
	pass


func on_holster() -> void:
	pass


## Melee reads better from behind, so the camera uses this as a hint.
func prefers_third_person() -> bool:
	return false


## True while aiming down sights. Forces the first-person camera.
func is_aiming() -> bool:
	return false


func status_text() -> String:
	return display_name
