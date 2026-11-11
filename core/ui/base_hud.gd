extends CanvasLayer
## The overlay while you walk around your home base: a crosshair, the prompt
## for whatever you are looking at, and what it is.
##
## Load with `preload("res://core/ui/base_hud.gd")`.

var base: HomeBase

var _prompt: Label
var _detail: Label
var _notice: Label
var _hint: Label
var _notice_left := 0.0


func setup(p_base: HomeBase) -> void:
	base = p_base


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var visiting := base != null and base.read_only
	var title := _label(root, "%s'S BASE" % base.owner_name.to_upper() if visiting else "HOME BASE",
			26, Color(1.0, 0.62, 0.22))
	_place(title, 0.0, 0.0, Vector2(24, 16), Vector2(500, 34))
	_hint = _label(root, "", 14, Color(0.75, 0.73, 0.7))
	_place(_hint, 0.0, 0.0, Vector2(24, 50), Vector2(900, 66))
	var crosshair := _label(root, "+", 22, Color.WHITE)
	_place(crosshair, 0.5, 0.5, Vector2(-7, -17), Vector2(14, 30))
	_prompt = _label(root, "", 20, Color.WHITE)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place(_prompt, 0.5, 0.5, Vector2(-350, 40), Vector2(700, 30))
	_detail = _label(root, "", 15, Color(0.75, 0.73, 0.7))
	_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_place(_detail, 0.5, 0.5, Vector2(-350, 72), Vector2(700, 60))
	_notice = _label(root, "", 18, Color(1.0, 0.8, 0.4))
	_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notice.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_place(_notice, 0.5, 1.0, Vector2(-420, -150), Vector2(840, 110))


## The help line under the title. The door's text can change while you are here.
func hint_text() -> String:
	if base == null:
		return ""
	if base.read_only:
		return "You are visiting. Look around, but the gear stays where it is.\n" \
				+ "WASD move   V camera   Esc free the mouse   The door behind you: %s." % base.door_text.to_lower()
	return "Everything in your stash is on show. Look at gear and press E to equip it. The consoles do the rest:\n" \
			+ "launch pad to deploy, locker, mastery bench, wardrobe, records, trader, uplink to play online.\n" \
			+ "WASD move   V camera   P phone   Esc free the mouse   The door behind you: %s." % base.door_text.to_lower()


## Shows a short message, such as why a server refused a change.
func show_notice(text: String, seconds := 4.0) -> void:
	if _notice:
		_notice.text = text
		_notice_left = seconds


## The two lines shown for what the player is looking at.
func describe(target: Interactable) -> Array[String]:
	if target == null:
		return ["", ""]
	var display := target as HomeBase.Display
	if display == null:
		return [target.get_prompt(), ""]
	var id := display.item_id
	return [display.get_prompt(), "%s   Worth %d\n%s" % [
			ItemDB.rarity_name(id), ItemDB.item_value(id), ItemDB.item_description(id)]]


func _process(delta: float) -> void:
	if base == null or not is_instance_valid(base) or base.player == null:
		return
	_hint.text = hint_text()
	var lines := describe(base.player.find_interactable())
	_prompt.text = lines[0]
	_detail.text = lines[1]
	if _notice_left > 0.0:
		_notice_left -= delta
		if _notice_left <= 0.0:
			_notice.text = ""


func _label(root: Control, text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("outline_size", 4)
	root.add_child(label)
	return label


func _place(node: Control, ax: float, ay: float, offset: Vector2, p_size: Vector2) -> void:
	node.anchor_left = ax
	node.anchor_right = ax
	node.anchor_top = ay
	node.anchor_bottom = ay
	node.offset_left = offset.x
	node.offset_top = offset.y
	node.offset_right = offset.x + p_size.x
	node.offset_bottom = offset.y + p_size.y
