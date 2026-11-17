extends VBoxContainer
## The contract board's screen in the hub: today's jobs to take, the ones you
## hold with their progress, and the daily reroll. Only a view: it shows the
## `contracts` of `account` (the server's snapshot, see `Contracts`) and asks
## with `asked`.
##
## Load with `preload("res://core/economy/contract_panel.gd")`.

const Contracts := preload("res://core/economy/contracts.gd")
const TITLE_COLOR := Color(1.0, 0.75, 0.3)

## "take" or "drop" a job, or "reroll" the offers.
signal asked(action: String, job_id: String)

## The account snapshot from the server; only its "contracts" are read.
var account := {}

var _rows: VBoxContainer
var _message: Label


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	add_child(_label("CONTRACT BOARD", 22, TITLE_COLOR))
	add_child(_label("Hold up to %d jobs. Progress counts only when you sign out alive, and a finished job pays "
			% Contracts.MAX_ACTIVE + "at once. Dailies end at midnight (UTC), weeklies on Monday.", 14,
			Color(0.65, 0.65, 0.65), true))
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 5)
	add_child(_rows)
	_message = _label("", 15, Color(1.0, 0.8, 0.4))
	_message.visible = false
	add_child(_message)
	refresh()


func show_message(text: String) -> void:
	if _message:
		_message.text = text
		_message.visible = text != ""


## The board's lines, as text: what `refresh` builds from, and what tests
## read. Each is {"text", "action" ("take", "drop" or ""), "id", "enabled"}.
static func rows(state: Variant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if typeof(state) != TYPE_DICTIONARY:
		out.append({"text": "The board is offline.", "action": "", "id": "", "enabled": false})
		return out
	var held := Contracts.held(state)
	out.append({"text": "HELD  %d/%d" % [held.size(), Contracts.MAX_ACTIVE], "action": "", "id": "", "enabled": false})
	if held.is_empty():
		out.append({"text": "Nothing yet. Take a job below.", "action": "", "id": "", "enabled": false})
	for entry in held:
		out.append({"text": "%s   %d/%d" % [entry.title, entry.have, entry.goal], "action": "drop", "id": entry.id,
				"enabled": true})
	for kind: String in ["daily", "weekly"]:
		out.append({"text": kind.to_upper(), "action": "", "id": "", "enabled": false})
		for id: Variant in state.get("offers", []):
			if typeof(id) != TYPE_STRING or Contracts.job(id).get("kind", "") != kind:
				continue
			var holding := held.any(func(entry: Dictionary) -> bool: return entry.id == id)
			var done: bool = id in state.get("done", [])
			var text := "%s   (%s)" % [Contracts.job(id).title, Contracts.reward_text(id)]
			if done:
				text += "   done"
			out.append({"text": text, "action": "take", "id": id,
					"enabled": not holding and not done and held.size() < Contracts.MAX_ACTIVE})
	return out


func refresh() -> void:
	if _rows == null:
		return
	for child in _rows.get_children():
		child.queue_free()
	var state: Variant = account.get("contracts")
	for row in rows(state):
		var line := HBoxContainer.new()
		var heading: bool = row.action == "" and row.text == row.text.to_upper()
		var text := _label(row.text, 18 if heading else 16, TITLE_COLOR if heading else Color(0.9, 0.9, 0.9))
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(text)
		if row.action != "":
			var id: String = row.id
			var action: String = row.action
			var button := _button("Take" if action == "take" else "Drop", func() -> void:
				show_message("")
				asked.emit(action, id))
			button.disabled = not row.enabled
			line.add_child(button)
		_rows.add_child(line)
	if typeof(state) == TYPE_DICTIONARY:
		var reroll := _button("Reroll the dailies (once a day)", func() -> void:
			show_message("")
			asked.emit("reroll", ""))
		reroll.disabled = bool(state.get("rerolled", false))
		_rows.add_child(reroll)


func _button(text: String, pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(120, 36)
	button.pressed.connect(pressed)
	return button


func _label(text: String, font_size: int, color: Color, wrap := false) -> Label:
	var label := Label.new()
	label.text = text
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label
