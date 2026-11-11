class_name Hud
extends CanvasLayer
## In-raid HUD, built in code so there is no scene file to keep in sync yet.

const RenownLedger := preload("res://core/progression/renown_ledger.gd")

var raid: Raid
var controller: PlayerController

var _timer: Label
var _vitals: Label
var _health_bar: ProgressBar
var _armor_bar: ProgressBar
var _stamina_bar: ProgressBar
var _hit_marker: HitMarker
var _hurt_flash: ColorRect
var _stance: StanceIndicator
var _heat_bar: ProgressBar
var _heat_label: Label
var _weapon: Label
var _backpack: Label
var _prompt: Label
var _view: Label
var _feed: Label
var _hold_bar: ProgressBar
var _death: Label
var _standing: Label
var _messages: Array[Dictionary] = []
## The local player's last life, shown while they are down (see `show_death`).
var _death_result := {}
var _redeploy_wait := 0.0


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

	_stance = StanceIndicator.new()
	_stance.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_stance)
	_place(_stance, 0.5, 0.5, Vector2(-70, -70), Vector2(140, 140))

	var crosshair := _label(root, "+", 22)
	_place(crosshair, 0.5, 0.5, Vector2(-7, -17), Vector2(14, 30))

	_timer = _label(root, "", 26)
	_timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place(_timer, 0.5, 0.0, Vector2(-200, 14), Vector2(400, 36))

	_standing = _label(root, "", 15)
	_standing.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place(_standing, 0.5, 0.0, Vector2(-300, 48), Vector2(600, 22))

	_view = _label(root, "", 13)
	_view.modulate.a = 0.6
	_place(_view, 0.0, 0.0, Vector2(18, 14), Vector2(900, 80))

	_feed = _label(root, "", 16)
	_feed.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_place(_feed, 1.0, 0.0, Vector2(-520, 14), Vector2(500, 200))

	_prompt = _label(root, "", 18)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place(_prompt, 0.5, 0.5, Vector2(-300, 40), Vector2(600, 30))

	_hold_bar = _bar(root, Color(0.25, 1.0, 0.55))
	_place(_hold_bar, 0.5, 0.5, Vector2(-150, 76), Vector2(300, 14))

	_death = _label(root, "", 24)
	_death.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_death.visible = false
	_place(_death, 0.5, 0.5, Vector2(-450, -190), Vector2(900, 200))

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
	raid.war_feed.connect(_on_war_feed)
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
	_timer.text = raid.world.display_name if raid.war.intensity < 0.2 \
			else "%s   %s" % [raid.world.display_name, raid.war.level_name()]
	_standing.text = standing_text(p)
	_redeploy_wait = maxf(0.0, _redeploy_wait - delta)
	_death.visible = p.is_dead and not _death_result.is_empty()
	if _death.visible:
		_death.text = death_text(_death_result, _redeploy_wait)

	_vitals.text = "Health %d   Armor %d (%s)   Stamina %d" % [
		ceili(p.health.health), ceili(p.health.armor), p.frame_name, floori(p.stamina)]
	_stamina_bar.value = p.stamina / p.max_stamina * 100.0
	_hurt_flash.color.a = maxf(0.0, _hurt_flash.color.a - delta * 0.9)
	_health_bar.value = p.health.health / p.health.max_health * 100.0
	_armor_bar.value = (p.health.armor / p.health.max_armor * 100.0) if p.health.max_armor > 0.0 else 0.0

	_heat_bar.visible = p.flight.enabled
	_heat_label.visible = p.flight.enabled
	_heat_bar.value = p.flight.heat_fraction() * 100.0
	_heat_label.text = "OVERHEATED" if p.flight.overheated else "%s heat%s" % [
		p.flight.display_name, "   gliding" if p.flight.is_gliding else ""]
	_heat_label.modulate = Color(1, 0.35, 0.25) if p.flight.overheated else Color.WHITE

	var weapon := p.get_active_weapon()
	var blade := weapon as MeleeWeapon
	_stance.stance = blade.stance if blade else -1
	_stance.guarding = blade != null and blade.is_blocking()
	_stance.threat = incoming_side(p)
	# Every carried weapon is listed with its key, the one in hand marked.
	var slots: Array[String] = []
	for i in p.weapons.size():
		var w := p.weapons[i]
		slots.append("%s [%d] %s" % [">" if w == weapon else " ", i + 1, w.status_text()])
	if p.ability.enabled:
		slots.append("  [G] %s" % p.ability.status_text())
	_weapon.text = "\n".join(slots) if not slots.is_empty() else "Unarmed"
	_backpack.text = "Backpack %d/%d   worth %d   Heals %d" % [
		p.inventory.items.size(), p.inventory.capacity, p.inventory.total_value(),
		p.inventory.count_with_tag("heal")]

	_view.text = "Camera: %s   press V to switch\nWASD move   Shift sprint   %s   Q dash   H heal   E loot%s   L sign out\n1 / 2 or mouse wheel: switch weapon   %s" % [
		PlayerController.VIEW_NAMES[controller.active_view()],
		p.flight.controls_hint(),
		"   G ability" if p.ability.enabled else "",
		weapon.controls_hint() if weapon else ""]
	if blade:
		_view.text += "\nMelee side: %s, %s   press B to switch" % [
			PlayerController.STANCE_CONTROL_NAMES[controller.stance_control],
			PlayerController.STANCE_CONTROL_HINTS[controller.stance_control]]
	if p.vehicle != null:
		var kmh := absf(float(p.vehicle.get("speed"))) * 3.6
		_view.text += "\nRiding %s   %d km/h   W throttle   S brake   A / D steer   Shift boost   E get off" % [
			p.vehicle.get("display_name"), roundi(kmh)]

	var banking := raid.bank_progress()
	var leaving := raid.sign_out_progress(p)
	_hold_bar.visible = (banking > 0.0 or leaving >= 0.0) and not p.is_dead
	_hold_bar.value = (leaving if leaving >= 0.0 else banking) * 100.0
	if p.is_dead:
		_prompt.text = ""
	elif leaving >= 0.0:
		_prompt.text = "Signing out...   L to cancel"
	elif banking > 0.0:
		_prompt.text = "Banking your backpack..."
	elif p.heal_time_left > 0.0:
		_prompt.text = "Healing %.1f" % p.heal_time_left
	else:
		# On a vehicle, E gets you off, so nothing else is offered.
		var target := p.find_interactable() if p.vehicle == null else null
		_prompt.text = target.get_prompt() if target else ""

	for m in _messages:
		m.time -= delta
	_messages = _messages.filter(func(m: Dictionary) -> bool: return m.time > 0.0)
	var lines: Array[String] = []
	for m in _messages:
		lines.append(m.text)
	_feed.text = "\n".join(lines)


## The side a nearby enemy swing is coming at the player, as the player sees
## it (the side to guard), or -1 when nothing is winding up in front of them.
static func incoming_side(p: Actor) -> int:
	if p.is_dead or not p.is_inside_tree():
		return -1
	var forward := p.get_aim_dir()
	forward.y = 0.0
	var best := -1
	var best_dist := INF
	for node in p.get_tree().get_nodes_in_group("actors"):
		var other := node as Actor
		if other == null or other == p or other.is_dead:
			continue
		var blade := other.get_active_weapon() as MeleeWeapon
		if blade == null or not blade.is_winding_up():
			continue
		var to := other.global_position - p.global_position
		to.y = 0.0
		var dist := to.length()
		if dist > blade.reach * 2.5 or dist >= best_dist:
			continue
		if dist > 0.5 and forward.length() > 0.01 and forward.normalized().dot(to.normalized()) < 0.2:
			continue
		best = MeleeWeapon.mirror(blade.attack_dir)
		best_dist = dist
	return best


func _on_hit_confirmed(_target: Actor, info: DamageInfo, lethal: bool) -> void:
	if lethal:
		_hit_marker.flash(Color(1.0, 0.25, 0.2), 0.35)
	elif info.parried or info.blocked:
		_hit_marker.flash(Color(0.6, 0.75, 1.0), 0.15)
	else:
		_hit_marker.flash(Color.WHITE, 0.15)


func _on_player_damaged(info: DamageInfo) -> void:
	_hurt_flash.color.a = clampf(_hurt_flash.color.a + 0.12 + info.amount * 0.012, 0.0, 0.45)


## Shows what the local player's death cost them and how to carry on.
## `wait` is how many seconds until they may drop back in.
func show_death(result: Dictionary, wait: float) -> void:
	_death_result = result
	_redeploy_wait = wait


## The words on the death screen.
static func death_text(result: Dictionary, wait: float) -> String:
	var by: String = result.get("killed_by", "")
	var lost: Array = result.get("lost", [])
	var lines: Array[String] = ["Killed by %s" % by if by != "" else "You died"]
	lines.append("Lost: %s" % ItemDB.summarize(lost) if not lost.is_empty() else "Nothing lost")
	if int(result.get("renown_lost", 0)) > 0:
		lines.append("Renown lost: %d" % int(result.renown_lost))
	var kept: Array = result.get("kept_gear", [])
	if not kept.is_empty():
		lines.append("Kept: %s" % ItemDB.summarize(kept))
	var banked: Array = result.get("banked", [])
	if not banked.is_empty():
		lines.append("Banked before you fell: worth %d" % int(result.get("banked_value", 0)))
	lines.append("")
	if wait > 0.0:
		lines.append("Drop back in in %d..." % ceili(wait))
	else:
		lines.append("Enter: drop back in      L: return to the hub")
	return "\n".join(lines)


## The local player's standing: rank, session renown, streak, and whether
## they are being hunted.
static func standing_text(p: Actor) -> String:
	var text := "%s   Renown %d" % [RenownLedger.rank_name(p.rank), p.renown]
	if p.streak > 1:
		text += "   Streak %d" % p.streak
	if p.bounty > 0:
		text += "   BOUNTY %d" % p.bounty
	if p.exposed:
		text += "   EXPOSED"
	if p.marked:
		text += "   THE MARKED"
	return text


## News for everyone in the world stays up a little longer than a notice.
func _on_war_feed(text: String) -> void:
	_messages.append({"text": text, "time": 7.0})
	if _messages.size() > 6:
		_messages.pop_front()


## Puts a line in the message feed.
func notify(text: String) -> void:
	_on_notice(text)


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

## Three marks around the crosshair for directional melee: which side you are
## set to attack or guard, and which side an enemy swing is coming at.
## Kept as an inner class so the HUD never depends on the editor's class cache.
class StanceIndicator:
	extends Control

	const OFFSETS := [Vector2(0, -1), Vector2(-1, 0), Vector2(1, 0)]

	## The player's `MeleeWeapon.Dir`, or -1 to hide the stance marks.
	var stance := -1
	var guarding := false
	## The side of the screen an enemy swing is coming at, or -1 for none.
	var threat := -1

	var radius := 34.0
	var threat_radius := 48.0
	var mark_length := 22.0


	func _process(_delta: float) -> void:
		queue_redraw()


	func _draw() -> void:
		var center := size * 0.5
		for dir in OFFSETS.size():
			var out: Vector2 = OFFSETS[dir]
			var along := Vector2(-out.y, out.x) * mark_length * 0.5
			if stance >= 0:
				var active := dir == stance
				var color := Color(1, 1, 1, 0.22)
				if active:
					color = Color(0.45, 0.75, 1.0) if guarding else Color.WHITE
				var at := center + out * radius
				draw_line(at - along, at + along, color, 4.0 if active else 2.0)
			if dir == threat:
				var at := center + out * threat_radius
				# Yellow on a dark outline, so it shows against red enemies and sky.
				draw_line(at - along * 1.6, at + along * 1.6, Color(0, 0, 0, 0.85), 12.0)
				draw_line(at - along * 1.5, at + along * 1.5, Color(1.0, 0.9, 0.15), 7.0)
