class_name Weapon
extends Node
## Base class for anything an Actor can hold and use.

var actor: Actor
var item_id := ""
var display_name := "Weapon"
## The held model, created by `build_visual` and parented to the actor's hand.
var visual: Node3D


## Called every physics tick, even while holstered (cooldowns, reloads).
func tick(_delta: float) -> void:
	pass


## Called every physics tick while this is the active weapon.
func handle_input(_cmd: ActorCommand, _delta: float) -> void:
	pass


func on_holster() -> void:
	pass


## Lets the weapon in hand block or parry a hit before it lands.
## Change `info.amount` and set `info.blocked` or `info.parried`.
func modify_incoming(_info: DamageInfo) -> void:
	pass


## Builds the greybox model shown in the actor's hand, or null for none.
func build_visual() -> Node3D:
	return null


## True while aiming down sights. The camera zooms in.
func is_aiming() -> bool:
	return false


## One line telling the player how to use this weapon.
func controls_hint() -> String:
	return ""


static func make_part(size: Vector3, at: Vector3, color: Color, glow := false) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	if glow:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 1.2
	mesh.material = mat
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.position = at
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return part


func status_text() -> String:
	return display_name
