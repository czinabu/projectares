extends CanvasLayer
## What you see over your home base: a crosshair, the prompt for whatever you
## are looking at, the odd notice, and the holographic watch on your wrist
## (`wrist`, raised with X as in a raid; its card says what each icon holds
## for the next deploy, `Hud.base_watch_slots`), and a worn helmet's glass
## (`visor`, the same `VisorHud` as out in a world, set up with
## `setup_base`). Everything else is in the room: the
## base's name and how it works hang on the banner, and the gear you look at
## gets a tag in the world saying what it is (`tag`).
##
## Load with `preload("res://core/ui/base_hud.gd")`.

var base: HomeBase
## Whose keys move the player; found under the base when not given.
var controller: PlayerController
## The watch, as in a raid (`Hud.Wrist`).
var wrist: Hud.Wrist
## The worn helmet's glass, as in a raid: a helmet shows its display
## wherever it is worn.
var visor: VisorHud
## The contracts held, for the watch's contract icon (set by `main.gd`).
var contracts: Array[Dictionary] = []
## The new player's tour objective, a small line on the watch card (set by
## `main.gd`, "" for none).
var objective := ""

## Rarity, worth and description of the gear you look at, floating over it.
var tag: Label3D

var _prompt: Label
var _notice: Label
var _notice_left := 0.0
## The aiming cross in the middle of the screen.
var crosshair: Label


func setup(p_base: HomeBase, p_controller: PlayerController = null) -> void:
	base = p_base
	controller = p_controller


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	visor = VisorHud.new()
	visor.name = "Visor"
	visor.setup_base(base, controller)
	visor.hud = self
	root.add_child(visor)
	crosshair = _label(root, "+", 22, Color.WHITE)
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
	wrist = Hud.Wrist.new()
	wrist.name = "Wrist"
	add_child(wrist)


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
	# On a vehicle, F gets you off, so nothing else is offered (as in `Hud`).
	var target := base.player.find_interactable() if base.player.vehicle == null else null
	var lines := describe(target)
	_prompt.text = lines[0]
	_show_tag(target as HomeBase.Display, lines[1])
	_update_wrist(delta)
	if _notice_left > 0.0:
		_notice_left -= delta
		if _notice_left <= 0.0:
			_notice.text = ""


## Raises and fills the watch, as the raid's HUD does.
func _update_wrist(delta: float) -> void:
	# The watch rides on the player, so suiting up (a new actor in place of
	# the old, freed with everything on it) takes it away: put on a new one.
	if wrist == null or not is_instance_valid(wrist) or wrist.is_queued_for_deletion():
		wrist = Hud.Wrist.new()
		wrist.name = "Wrist"
		add_child(wrist)
	if controller == null or not is_instance_valid(controller) or controller.actor != base.player:
		# The one whose keys drive the player now (`main.gd` hands its own on
		# to a suited-up player; elsewhere, look under the base).
		controller = null
		for child in base.get_children():
			if child is PlayerController and not child.is_queued_for_deletion() and child.actor == base.player:
				controller = child
	if visor != null:
		visor.controller = controller
	var p := base.player
	wrist.raised = controller != null and controller.wrist_raised
	wrist.mount(p, controller, visible, delta)
	var slots := Hud.base_watch_slots("Home base" if base.owner_name == "" else "%s's base" % base.owner_name, base.loadout,
			contracts, controller.portal_pick if controller != null else 0)
	var focus := Hud.default_focus(slots)
	if controller != null:
		if controller.watch_focus_moved:
			focus = clampi(controller.watch_focus, 0, slots.size() - 1)
		else:
			controller.watch_focus = focus
	# The Summon tab is live at home: every weapon and vehicle you own.
	var toys := base.watch_vehicles()
	var weapons: Array[Dictionary] = controller.watch_weapons() if controller != null else ([] as Array[Dictionary])
	var weapon_pick := clampi(controller.weapon_pick if controller != null else 0, 0, maxi(weapons.size() - 1, 0))
	var toy_pick := clampi(controller.watch_index if controller != null else 0, 0, maxi(toys.size() - 1, 0))
	slots[Hud.Wrist.SLOTS.find("weapon")] = Hud.base_weapon_slot(p, weapons, weapon_pick)
	slots[Hud.Wrist.SLOTS.find("vehicle")] = Hud.base_vehicle_slot(toys, toy_pick, controller != null and controller.pack_target() != null)
	Hud.mark_open(slots, controller.watch_open if controller != null else "")
	wrist.objective = objective
	wrist.show_card(slots, focus, "", p.health.health / maxf(p.health.max_health, 1.0), [] as Array[float])
	var picking_toys := controller != null and controller.is_picking_toys()
	var picking_weapons := controller != null and controller.is_picking_weapons()
	wrist.show_toys(toys if picking_toys else ([] as Array[String]), toy_pick, true, delta)
	var weapon_ids: Array[String] = []
	if picking_weapons:
		for entry in weapons:
			weapon_ids.append(entry.id)
	wrist.show_weapons(weapon_ids, weapon_pick, true, delta)


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
	if wrist != null and is_instance_valid(wrist):
		wrist.take_off()
		wrist.queue_free()


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


## Shows or hides the cross in the middle of the screen, which would sit on
## your face in the phone's mirror.
func show_aim(on: bool) -> void:
	if crosshair:
		crosshair.visible = on
