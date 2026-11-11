extends CanvasLayer
## What you see over your home base: a crosshair, the prompt for whatever you
## are looking at, and the odd notice. Everything else is in the room: the
## base's name and how it works hang on the banner, and the gear you look at
## gets a tag in the world saying what it is (`tag`).
##
## Load with `preload("res://core/ui/base_hud.gd")`.

var base: HomeBase

## Rarity, worth and description of the gear you look at, floating over it.
var tag: Label3D

var _prompt: Label
var _notice: Label
var _notice_left := 0.0


func setup(p_base: HomeBase) -> void:
	base = p_base


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var crosshair := _label(root, "+", 22, Color.WHITE)
	_place(crosshair, 0.5, 0.5, Vector2(-7, -17), Vector2(14, 30))
	_prompt = _label(root, "", 20, Color.WHITE)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place(_prompt, 0.5, 0.5, Vector2(-350, 40), Vector2(700, 30))
	tag = Label3D.new()
	tag.name = "GearTag"
	tag.modulate = Color(0.88, 0.86, 0.82)
	tag.font_size = 40
	tag.pixel_size = 0.0022
	tag.outline_size = 10
	tag.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	tag.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tag.width = 420.0
	tag.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	tag.no_depth_test = true
	tag.visible = false
	tag.top_level = true
	if base:
		base.add_child.call_deferred(tag)
	_notice = _label(root, "", 18, Color(1.0, 0.8, 0.4))
	_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notice.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_place(_notice, 0.5, 1.0, Vector2(-420, -150), Vector2(840, 110))


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
	var target := base.player.find_interactable()
	var lines := describe(target)
	_prompt.text = lines[0]
	_show_tag(target as HomeBase.Display, lines[1])
	if _notice_left > 0.0:
		_notice_left -= delta
		if _notice_left <= 0.0:
			_notice.text = ""


## Hangs the tag over the display you look at, or puts it away.
func _show_tag(display: HomeBase.Display, text: String) -> void:
	if tag == null or not is_instance_valid(tag) or not tag.is_inside_tree():
		return
	if display == null or text == "" or not visible:
		tag.visible = false
		return
	var plate := display.get_node_or_null("Plate") as Node3D
	tag.global_position = display.to_global((plate.position if plate else Vector3(0, 1.0, 0)) + Vector3(0, 0.22, 0))
	tag.text = text
	tag.visible = true


func _exit_tree() -> void:
	if tag != null and is_instance_valid(tag):
		tag.queue_free()


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
