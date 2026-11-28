extends Node
## Registers the input actions in code so the bindings live in one readable place.
## These are the defaults: the phone's Settings › Input rebinds a key
## (`GameSettings.rebind`), which keeps only what differs from them.

const KEY_ACTIONS := {
	"move_forward": KEY_W,
	"move_back": KEY_S,
	"move_left": KEY_A,
	"move_right": KEY_D,
	"jump": KEY_SPACE,
	"sprint": KEY_SHIFT,
	"dash": KEY_ALT,
	"crouch": KEY_C,
	"kick": KEY_V,
	"weapon_ability": KEY_Q,
	"interact": KEY_F,
	"reload": KEY_R,
	"heal": KEY_H,
	"ability": KEY_G,
	"visor": KEY_T,
	"toggle_view": KEY_TAB,
	"weapon_1": KEY_1,
	"weapon_2": KEY_2,
	"weapon_3": KEY_3,
	"weapon_4": KEY_4,
	"holster": KEY_Z,
	"scoreboard": KEY_O,
	"sign_out": KEY_L,
	"redeploy": KEY_ENTER,
	"phone": KEY_P,
	"check_wrist": KEY_X,
	"free_look": KEY_E,
	"inspect": KEY_I,
	"helmet": KEY_K,
	"lamp": KEY_J,
	# Shortcuts (Caleb's ask): straight to a watch icon or a phone app.
	"emote_wheel": KEY_B,
	"quick_emote": KEY_N,
	"watch_map": KEY_M,
	"squad_chat": KEY_Y,
	"friends": KEY_U,
}

const MOUSE_ACTIONS := {
	"fire": MOUSE_BUTTON_LEFT,
	"alt_fire": MOUSE_BUTTON_RIGHT,
	"ping": MOUSE_BUTTON_MIDDLE,
	# The thumb button too, for a mouse that has one.
	"weapon_ability": MOUSE_BUTTON_XBUTTON1,
}


func _ready() -> void:
	for action: String in actions():
		for ev: InputEvent in default_events(action):
			_bind(action, ev)


## Every action set up here, keys first.
static func actions() -> Array[String]:
	var out: Array[String] = []
	for action: String in KEY_ACTIONS.keys() + MOUSE_ACTIONS.keys():
		if action not in out:
			out.append(action)
	return out


## What `action` is bound to out of the box.
static func default_events(action: String) -> Array[InputEvent]:
	var out: Array[InputEvent] = []
	if KEY_ACTIONS.has(action):
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_ACTIONS[action]
		out.append(ev)
	if MOUSE_ACTIONS.has(action):
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_ACTIONS[action]
		out.append(ev)
	return out


static func _bind(action: String, event: InputEvent) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	InputMap.action_add_event(action, event)
