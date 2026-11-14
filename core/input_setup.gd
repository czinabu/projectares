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
	"dash": KEY_ALT,
	"slide": KEY_C,
	"interact": KEY_F,
	"reload": KEY_R,
	"heal": KEY_H,
	"ability": KEY_G,
	"visor": KEY_T,
	"toggle_view": KEY_TAB,
	"melee_control": KEY_B,
	"weapon_1": KEY_1,
	"weapon_2": KEY_2,
	"weapon_3": KEY_3,
	"holster": KEY_Z,
	"scoreboard": KEY_Q,
	"sign_out": KEY_L,
	"redeploy": KEY_ENTER,
	"phone": KEY_P,
	"check_wrist": KEY_X,
	"free_look": KEY_V,
	"inspect": KEY_I,
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
