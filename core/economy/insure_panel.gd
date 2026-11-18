extends VBoxContainer
## The insurance screen on the fabricator (DESIGN.md section 10, "Safety
## nets"): the policy you hold, the wait after a claim, and every item you
## own that can be insured with what it costs. One policy at a time.
##
## Solo it insures with the local `Profile`. Online, set `account` to the
## server's snapshot: the panel then only asks (`insure_requested`) and shows
## whatever the server sends back.
##
## Load with `const InsurePanel := preload("res://core/economy/insure_panel.gd")`.

const SafetyNets := preload("res://core/economy/safety_nets.gd")

const TITLE_COLOR := Color(0.45, 0.85, 1.0)
const SCRIP_COLOR := Color(1.0, 0.85, 0.4)

## Online: the server decides, so nothing changes until `account` is updated.
## `action` is "insure" or "cancel".
signal insure_requested(action: String, item_id: String)
## Solo: the local profile's scrip or policy changed.
signal changed

## Online: the server's account snapshot. Null means the local profile.
var account: Variant = null

var _policy: Label
var _cancel: Button
var _rows: VBoxContainer
var _message: Label


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	add_child(_label("INSURANCE", 20, TITLE_COLOR))
	add_child(_label(
		"Insure one item. If it is on your body when you die it is recalled home instead of dropping "
		+ "in your bag. A claim ends the policy and the next one waits %d hours. Crafted gear that is lost "
		% roundi(SafetyNets.COOLDOWN / 3600.0)
		+ "uninsured still pays back %d%% of its parts as salvage." % roundi(SafetyNets.SALVAGE_SHARE * 100.0),
		13, Color(0.65, 0.65, 0.65), true))
	var head := HBoxContainer.new()
	_policy = _label("", 15, Color(0.85, 0.85, 0.85), true)
	_policy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_policy)
	_cancel = Button.new()
	_cancel.name = "CancelPolicy"
	_cancel.text = "Cancel policy"
	_cancel.custom_minimum_size = Vector2(130, 0)
	_cancel.pressed.connect(cancel)
	head.add_child(_cancel)
	add_child(head)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 3)
	add_child(_rows)
	_message = _label("", 14, Color(1.0, 0.8, 0.4))
	_message.visible = false
	add_child(_message)
	refresh()


func scrip() -> int:
	return int(account.get("scrip", 0)) if account != null else Profile.scrip


func stash_items() -> Array:
	return account.get("stash", []) if account != null else Profile.stash


## The policy: the server's account's, or the profile's.
func policy() -> Dictionary:
	if account != null:
		return SafetyNets.clean(account.get("insurance", {}))
	return Profile.insurance_policy()


func now() -> float:
	return Time.get_unix_time_from_system()


## The items that could be insured, each once, dearest first.
func choices() -> Array[String]:
	var out: Array[String] = []
	for id: Variant in stash_items():
		if typeof(id) == TYPE_STRING and id not in out and SafetyNets.insurable(id):
			out.append(id)
	out.sort_custom(func(a: String, b: String) -> bool:
		var va := ItemDB.item_value(a)
		var vb := ItemDB.item_value(b)
		return va > vb if va != vb else a < b)
	return out


## Why `item_id` cannot be insured right now, or "".
func blocked(item_id: String) -> String:
	return SafetyNets.blocked(policy(), stash_items(), scrip(), item_id, now())


func insure(item_id: String) -> void:
	if account != null:
		insure_requested.emit("insure", item_id)
		return
	var result := Profile.insure(item_id)
	show_message("%s is insured." % ItemDB.item_name(item_id) if result.ok else str(result.get("error", "")))
	refresh()
	if result.ok:
		changed.emit()


func cancel() -> void:
	if account != null:
		insure_requested.emit("cancel", "")
		return
	var result := Profile.cancel_insurance()
	show_message("Policy cancelled." if result.ok else str(result.get("error", "")))
	refresh()
	if result.ok:
		changed.emit()


func show_message(text: String) -> void:
	if _message:
		_message.text = text
		_message.visible = text != ""


## What the policy line says.
func policy_text() -> String:
	var held := policy()
	var item := str(held.get("item", ""))
	if item != "":
		return "Insured: %s." % ItemDB.item_name(item)
	var wait := SafetyNets.wait_left(held, now())
	if wait > 0.0:
		return "No policy. A new one is ready in %s." % SafetyNets.wait_text(wait)
	return "No policy held."


func refresh() -> void:
	if _rows == null:
		return
	var held := policy()
	_policy.text = "%s   %d scrip" % [policy_text(), scrip()]
	_cancel.visible = str(held.get("item", "")) != ""
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	for id in choices():
		var why := blocked(id)
		var row := HBoxContainer.new()
		row.name = "Insure_%s" % id
		var name_label := _label(ItemDB.item_name(id), 15, ItemDB.RARITY_COLORS[ItemDB.item_rarity(id)])
		name_label.custom_minimum_size = Vector2(190, 0)
		row.add_child(name_label)
		var detail := _label("%d scrip" % SafetyNets.premium(id), 13, Color(0.7, 0.7, 0.7))
		detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(detail)
		var button := Button.new()
		button.name = "Insure"
		button.text = "Insured" if str(held.get("item", "")) == id else "Insure"
		button.tooltip_text = why
		button.disabled = why != ""
		button.custom_minimum_size = Vector2(130, 0)
		button.pressed.connect(insure.bind(id))
		row.add_child(button)
		_rows.add_child(row)


func _label(text: String, font_size: int, color: Color, wrap := false) -> Label:
	var label := Label.new()
	label.text = text
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label
