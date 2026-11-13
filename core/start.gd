extends Node
## The project's main scene. Shows the start screen over the lane between
## worlds, then jumps into the game. A dedicated server has no screen to
## show, so it goes straight in.

const GAME_SCENE := "res://scenes/main.tscn"

var backdrop: TitleBackdrop
var screen: StartScreen


func _ready() -> void:
	if "--server" in OS.get_cmdline_user_args():
		get_tree().change_scene_to_file.call_deferred(GAME_SCENE)
		return
	backdrop = TitleBackdrop.new()
	add_child(backdrop)
	var layer := CanvasLayer.new()
	add_child(layer)
	screen = StartScreen.new()
	screen.over_scene = true
	# The jump flares to white as it peaks.
	screen.leave_color = Color(0.86, 0.95, 1.0)
	screen.leave_delay = backdrop.jump_time * 0.55
	screen.leave_time = backdrop.jump_time * 0.45
	layer.add_child(screen)
	screen.start_pressed.connect(_go)


func _go() -> void:
	backdrop.jump()
	await screen.leave()
	get_tree().change_scene_to_file.call_deferred(GAME_SCENE)
