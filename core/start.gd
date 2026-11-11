extends Node
## The project's main scene. Shows the start screen, then hands over to the
## game. A dedicated server has no screen to show, so it goes straight in.

const GAME_SCENE := "res://scenes/main.tscn"


func _ready() -> void:
	if "--server" in OS.get_cmdline_user_args():
		get_tree().change_scene_to_file.call_deferred(GAME_SCENE)
		return
	var layer := CanvasLayer.new()
	add_child(layer)
	var screen := StartScreen.new()
	layer.add_child(screen)
	screen.start_pressed.connect(func() -> void:
		get_tree().change_scene_to_file.call_deferred(GAME_SCENE))
