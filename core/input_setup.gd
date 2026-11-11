extends Node
## Registers the input actions in code so the bindings live in one readable place.
## Rebinding UI can later edit InputMap at runtime without touching project.godot.

const KEY_ACTIONS := {
	"move_forward": KEY_W,
	"move_back": KEY_S,
	"move_left": KEY_A,
	"move_right": KEY_D,
	"jump": KEY_SPACE,
	"sprint": KEY_SHIFT,
	"dash": KEY_Q,
	"interact": KEY_E,
	"reload": KEY_R,
	"heal": KEY_H,
	"heavy": KEY_F,
	"ability": KEY_G,
	"toggle_view": KEY_V,
	"melee_control": KEY_B,
	"weapon_1": KEY_1,
	"weapon_2": KEY_2,
	"scoreboard": KEY_TAB,
}

const MOUSE_ACTIONS := {
	"fire": MOUSE_BUTTON_LEFT,
	"alt_fire": MOUSE_BUTTON_RIGHT,
}


func _ready() -> void:
	for action: String in KEY_ACTIONS:
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_ACTIONS[action]
		_bind(action, ev)
	for action: String in MOUSE_ACTIONS:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_ACTIONS[action]
		_bind(action, ev)


func _bind(action: String, event: InputEvent) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	InputMap.action_add_event(action, event)
