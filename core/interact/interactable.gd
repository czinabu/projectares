class_name Interactable
extends StaticBody3D
## Anything an Actor can look at and use with the interact key.


func _init() -> void:
	collision_layer = Actor.LAYER_INTERACT
	collision_mask = 0


func get_prompt() -> String:
	return "Use"


func interact(_actor: Actor) -> void:
	pass
