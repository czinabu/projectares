extends VBoxContainer
## The clan hall's screen: your clan and who is in it, or the clans there are
## to join and a form to found one. Only a view: it shows `state` (what the
## server sent, see `ClanService.snapshot`) and asks with `asked`.
##
## Load with `preload("res://core/social/clan_panel.gd")`.

const TITLE_COLOR := Color(0.85, 0.6, 1.0)

## "create" (name, tag), "join" (clan id) or "leave".
signal asked(action: String, a: String, b: String)

## The server's word on clans: {"clan": yours or {}, "clans": [...]}.
var state := {}

var _rows: VBoxContainer
var _message: Label
var _name: LineEdit
var _tag: LineEdit


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	add_child(_label("CLAN HALL", 22, TITLE_COLOR))
	add_child(_label("Clanmates are one side out there: you cannot hurt each other, you hold strongpoints "
			+ "together, and you can drop in on ground your clan holds.", 14, Color(0.65, 0.65, 0.65), true))
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


## The lines the screen shows, as text. What `refresh` builds from, and what
## tests read.
static func lines(p_state: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var mine: Dictionary = p_state.get("clan", {})
	if not mine.is_empty():
		out.append("[%s] %s" % [mine.get("tag", ""), mine.get("name", "")])
		for member: Variant in mine.get("members", []):
			out.append("%s%s" % [member, "  (leader)" if member == mine.get("leader", "") else ""])
		return out
	for clan: Variant in p_state.get("clans", []):
		if typeof(clan) == TYPE_DICTIONARY:
			out.append("[%s] %s  %d members" % [clan.get("tag", ""), clan.get("name", ""), int(clan.get("members", 0))])
	if out.is_empty():
		out.append("No clans yet. Found the first.")
	return out


func refresh() -> void:
	if _rows == null:
		return
	for child in _rows.get_children():
		child.queue_free()
	var mine: Dictionary = state.get("clan", {})
	var text := lines(state)
	if not mine.is_empty():
		_rows.add_child(_label(text[0], 20, Color.WHITE))
		for i in range(1, text.size()):
			_rows.add_child(_label(text[i], 16, Color(0.85, 0.85, 0.85)))
		_rows.add_child(_button("Leave the clan", func() -> void: asked.emit("leave", "", "")))
		return
	var listed: Array = state.get("clans", [])
	for i in text.size():
		var row := HBoxContainer.new()
		var name := _label(text[i], 16, Color(0.9, 0.9, 0.9))
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name)
		if i < listed.size() and typeof(listed[i]) == TYPE_DICTIONARY:
			var clan: Dictionary = listed[i]
			var join := _button("Full" if clan.get("full", false) else "Join", func() -> void:
				asked.emit("join", str(clan.get("id", "")), ""))
			join.disabled = clan.get("full", false)
			row.add_child(join)
		_rows.add_child(row)
	_rows.add_child(_label("FOUND A CLAN", 16, TITLE_COLOR))
	var form := HBoxContainer.new()
	form.add_theme_constant_override("separation", 6)
	_name = LineEdit.new()
	_name.placeholder_text = "Clan name"
	_name.max_length = ClanService.NAME_MAX
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_child(_name)
	_tag = LineEdit.new()
	_tag.placeholder_text = "TAG"
	_tag.max_length = ClanService.TAG_MAX
	_tag.custom_minimum_size = Vector2(110, 0)
	form.add_child(_tag)
	form.add_child(_button("Found", func() -> void: asked.emit("create", _name.text, _tag.text)))
	_rows.add_child(form)


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
