class_name Hud
extends CanvasLayer
## In-raid HUD, built in code so there is no scene file to keep in sync yet.

var raid: Raid
var controller: PlayerController

var _timer: Label
var _vitals: Label
var _health_bar: ProgressBar
var _armor_bar: ProgressBar
var _stamina_bar: ProgressBar
var _hit_marker: HitMarker
var _hurt_flash: ColorRect
var _heat_bar: ProgressBar
var _heat_label: Label
var _weapon: Label
var _backpack: Label
var _prompt: Label
var _view: Label
var _feed: Label
var _extract_bar: ProgressBar
var _messages: Array[Dictionary] = []


func setup(p_raid: Raid, p_controller: PlayerController) -> void:
	raid = p_raid
	controller = p_controller


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_hurt_flash = ColorRect.new()
	_hurt_flash.color = Color(0.8, 0.05, 0.02, 0.0)
	_hurt_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hurt_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_hurt_flash)

	_hit_marker = HitMarker.new()
	_hit_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_hit_marker)
	_place(_hit_marker, 0.5, 0.5, Vector2(-20, -20), Vector2(40, 40))

	var crosshair := _label(root, "+", 22)
	_place(crosshair, 0.5, 0.5, Vector2(-7, -17), Vector2(14, 30))

	_timer = _label(root, "", 26)
	_timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place(_timer, 0.5, 0.0, Vector2(-200, 14), Vector2(400, 36))

	_view = _label(root, "", 14)
	_place(_view, 0.0, 0.0, Vector2(18, 14), Vector2(900, 80))

	_feed = _label(root, "", 16)
	_feed.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_place(_feed, 1.0, 0.0, Vector2(-520, 14), Vector2(500, 200))

	_prompt = _label(root, "", 18)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place(_prompt, 0.5, 0.5, Vector2(-300, 40), Vector2(600, 30))

	_extract_bar = _bar(root, Color(0.25, 1.0, 0.55))
	_place(_extract_bar, 0.5, 0.5, Vector2(-150, 76), Vector2(300, 14))

	_vitals = _label(root, "", 16)
	_place(_vitals, 0.0, 1.0, Vector2(18, -108), Vector2(500, 24))
	_health_bar = _bar(root, Color(0.85, 0.25, 0.25))
	_place(_health_bar, 0.0, 1.0, Vector2(18, -80), Vector2(280, 16))
	_armor_bar = _bar(root, Color(0.35, 0.6, 1.0))
	_place(_armor_bar, 0.0, 1.0, Vector2(18, -58), Vector2(280, 10))
	_stamina_bar = _bar(root, Color(0.95, 0.85, 0.3))
	_place(_stamina_bar, 0.0, 1.0, Vector2(18, -42), Vector2(280, 10))

	_heat_label = _label(root, "", 14)
	_heat_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place(_heat_label, 0.5, 1.0, Vector2(-150, -66), Vector2(300, 20))
	_heat_bar = _bar(root, Color(1.0, 0.6, 0.15))
	_place(_heat_bar, 0.5, 1.0, Vector2(-150, -42), Vector2(300, 12))

	_weapon = _label(root, "", 20)
	_weapon.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_weapon.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_place(_weapon, 1.0, 1.0, Vector2(-520, -192), Vector2(500, 126))
	_backpack = _label(root, "", 16)
	_backpack.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_place(_backpack, 1.0, 1.0, Vector2(-520, -60), Vector2(500, 24))

	raid.player.notice.connect(_on_notice)
	raid.player.hit_confirmed.connect(_on_hit_confirmed)
	raid.player.health.damaged.connect(_on_player_damaged)
	var names: Array[String] = []
	for i in raid.player.weapons.size():
		names.append("[%d] %s" % [i + 1, raid.player.weapons[i].display_name])
	if not names.is_empty():
		_on_notice("You carry: " + "   ".join(names))


func _process(delta: float) -> void:
	if raid == null or raid.player == null or not is_instance_valid(raid.player):
		return
	var p := raid.player
	var secs := int(maxf(raid.time_left, 0.0))
	_timer.text = "%s   %02d:%02d" % [raid.world.display_name, secs / 60, secs % 60]
	_timer.modulate = Color(1, 0.4, 0.3) if secs < 120 else Color.WHITE

	_vitals.text = "Health %d   Armor %d (%s)   Stamina %d" % [
		ceili(p.health.health), ceili(p.health.armor), p.frame_name, floori(p.stamina)]
	_stamina_bar.value = p.stamina / p.max_stamina * 100.0
	_hurt_flash.color.a = maxf(0.0, _hurt_flash.color.a - delta * 0.9)
	_health_bar.value = p.health.health / p.health.max_health * 100.0
	_armor_bar.value = (p.health.armor / p.health.max_armor * 100.0) if p.health.max_armor > 0.0 else 0.0

	_heat_bar.visible = p.flight.enabled
	_heat_label.visible = p.flight.enabled
	_heat_bar.value = p.flight.heat_fraction() * 100.0
	_heat_label.text = "OVERHEATED" if p.flight.overheated else "%s heat" % p.flight.display_name
	_heat_label.modulate = Color(1, 0.35, 0.25) if p.flight.overheated else Color.WHITE

	var weapon := p.get_active_weapon()
	# Every carried weapon is listed with its key, the one in hand marked.
	var slots: Array[String] = []
	for i in p.weapons.size():
		var w := p.weapons[i]
		slots.append("%s [%d] %s" % [">" if w == weapon else " ", i + 1, w.status_text()])
	_weapon.text = "\n".join(slots) if not slots.is_empty() else "Unarmed"
	_backpack.text = "Backpack %d/%d   worth %d   Heals %d" % [
		p.inventory.items.size(), p.inventory.capacity, p.inventory.total_value(),
		p.inventory.count_with_tag("heal")]

	_view.text = "Camera: %s   press V to switch\nWASD move   Shift sprint   Space jump, hold to fly   Q dash   H heal   E loot\n1 / 2 or mouse wheel: switch weapon   %s" % [
		PlayerController.VIEW_NAMES[controller.view_mode],
		weapon.controls_hint() if weapon else ""]

	var progress := raid.extract_progress()
	_extract_bar.visible = progress > 0.0
	_extract_bar.value = progress * 100.0
	if progress > 0.0:
		_prompt.text = "Extracting..."
	elif p.heal_time_left > 0.0:
		_prompt.text = "Healing %.1f" % p.heal_time_left
	else:
		var target := p.find_interactable()
		_prompt.text = target.get_prompt() if target else ""

	for m in _messages:
		m.time -= delta
	_messages = _messages.filter(func(m: Dictionary) -> bool: return m.time > 0.0)
	var lines: Array[String] = []
	for m in _messages:
		lines.append(m.text)
	_feed.text = "\n".join(lines)


func _on_hit_confirmed(_target: Actor, info: DamageInfo, lethal: bool) -> void:
	if lethal:
		_hit_marker.flash(Color(1.0, 0.25, 0.2), 0.35)
	elif info.parried or info.blocked:
		_hit_marker.flash(Color(0.6, 0.75, 1.0), 0.15)
	else:
		_hit_marker.flash(Color.WHITE, 0.15)


func _on_player_damaged(info: DamageInfo) -> void:
	_hurt_flash.color.a = clampf(_hurt_flash.color.a + 0.12 + info.amount * 0.012, 0.0, 0.45)


func _on_notice(text: String) -> void:
	_messages.append({"text": text, "time": 4.0})
	if _messages.size() > 6:
		_messages.pop_front()


func _label(parent: Control, text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 5)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


func _bar(parent: Control, color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.max_value = 100.0
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0, 0, 0, 0.55)
	bar.add_theme_stylebox_override("fill", fill)
	bar.add_theme_stylebox_override("background", back)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(bar)
	return bar


## Anchors a control to a point of the screen (0..1) with a pixel offset and size.
func _place(control: Control, ax: float, ay: float, offset: Vector2, size: Vector2) -> void:
	control.anchor_left = ax
	control.anchor_right = ax
	control.anchor_top = ay
	control.anchor_bottom = ay
	control.offset_left = offset.x
	control.offset_top = offset.y
	control.offset_right = offset.x + size.x
	control.offset_bottom = offset.y + size.y


## Four diagonal ticks around the crosshair that flash when your attack lands.
class HitMarker:
	extends Control

	var _left := 0.0
	var _duration := 0.15
	var _color := Color.WHITE

	func flash(color: Color, duration: float) -> void:
		_color = color
		_duration = duration
		_left = duration
		queue_redraw()

	func _process(delta: float) -> void:
		if _left > 0.0:
			_left -= delta
			queue_redraw()

	func _draw() -> void:
		if _left <= 0.0:
			return
		var c := size * 0.5
		var color := _color
		color.a = clampf(_left / _duration, 0.0, 1.0)
		for dir: Vector2 in [Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1), Vector2(-1, -1)]:
			draw_line(c + dir * 7.0, c + dir * 15.0, color, 2.5)
