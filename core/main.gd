extends Node
## Entry point. Switches between the hub and a raid.

var hub: Hub
var raid: Raid
var controller: PlayerController
var hud: Hud


func _ready() -> void:
	hub = Hub.new()
	add_child(hub)
	hub.deploy_requested.connect(start_raid)


func start_raid(world_id: String) -> void:
	var world := Worlds.get_world(world_id)
	if world == null or raid != null:
		return
	hub.visible = false
	raid = Raid.new()
	raid.name = "Raid"
	add_child(raid)
	raid.start(world, -1, Profile.checkout_loadout(world), Profile.mastery.active_picks())
	controller = PlayerController.new()
	controller.setup(raid.player)
	raid.add_child(controller)
	hud = Hud.new()
	hud.setup(raid, controller)
	raid.add_child(hud)
	raid.ended.connect(_on_raid_ended)


func _on_raid_ended(result: Dictionary) -> void:
	# Leave a beat so the player sees what happened before the hub appears.
	await get_tree().create_timer(1.5).timeout
	if raid:
		raid.queue_free()
		raid = null
	hub.refresh(result)
	hub.visible = true
