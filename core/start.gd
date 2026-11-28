extends Node
## The project's main scene. Shows the start screen over the lane between
## worlds, then jumps into the game. A dedicated server has no screen to
## show, so it goes straight in.

const GAME_SCENE := "res://scenes/main.tscn"
const GameSettings := preload("res://core/settings/game_settings.gd")

var backdrop: TitleBackdrop
var screen: StartScreen


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if "--server" in args or "--account-service" in args:
		get_tree().change_scene_to_file.call_deferred(GAME_SCENE)
		return
	# The project is named Verge (the window title follows it), and
	# `custom_user_dir_name` keeps the save folder under app_userdata at its
	# prototype name ("Project Ares") so it never moves.
	# The volume settings first, then the plaza's track under the title
	# (it plays on into the base and the plaza, `Sfx.music`).
	GameSettings.ensure_loaded()
	Sfx.music("plaza")
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
	# The game updates itself (`core/update/updater.gd`): its state shows in
	# the corner, and a build that finishes downloading while this screen is
	# up goes in at once.
	Updater.on_start_screen = true
	Updater.changed.connect(_show_update)
	_show_update()


func _show_update() -> void:
	screen.set_status(Updater.status_line())


func _go() -> void:
	Updater.on_start_screen = false
	Updater.changed.disconnect(_show_update)
	backdrop.jump()
	await screen.leave()
	get_tree().change_scene_to_file.call_deferred(GAME_SCENE)
