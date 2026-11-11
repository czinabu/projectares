extends VBoxContainer
## The shop screen: your credits, a tab for every hub shop, and a tab for
## selling. Self-contained, so the hub menu and any vendor stall can show it.
##
## Solo it trades with the local `Profile`. Online, set `account` to the
## server's snapshot: the panel then only asks (`buy_requested`,
## `sell_requested`) and shows whatever the server sends back.
##
## Load with `const ShopPanel := preload("res://core/economy/shop_panel.gd")`.

const Economy := preload("res://core/economy/economy.gd")
const ShopDB := preload("res://core/economy/shop_db.gd")

const SELL_TAB := "sell"
const TITLE_COLOR := Color(1.0, 0.55, 0.25)
const CREDIT_COLOR := Color(1.0, 0.85, 0.4)

## Online: the server decides, so nothing changes until `account` is updated.
signal buy_requested(shop_id: String, item_id: String)
## An empty `item_id` asks to sell all loot.
signal sell_requested(item_id: String, count: int)
## Solo: the local profile's stash or credits changed.
signal changed

## Online: the server's account snapshot. Null means the local profile.
var account: Variant = null
## Show only this shop (for a vendor stall). Empty shows every shop.
var shop_filter := ""
## The tab being shown: a shop id, or SELL_TAB.
var current := ""

var _credits: Label
var _tabs: HBoxContainer
var _blurb: Label
var _rows: VBoxContainer
var _message: Label


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	var head := HBoxContainer.new()
	var title := _label("SHOPS", 20, TITLE_COLOR)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_credits = _label("", 18, CREDIT_COLOR)
	head.add_child(_credits)
	add_child(head)
	add_child(_label(
		"Shops sell base-level gear only. Anything better has to be found out there. "
		+ "Sell the loot you bring home to earn credits. Bought gear is lost like any other if you die with it.",
		13, Color(0.65, 0.65, 0.65), true))
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 6)
	add_child(_tabs)
	_blurb = _label("", 13, Color(0.65, 0.65, 0.65), true)
	add_child(_blurb)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 3)
	add_child(_rows)
	_message = _label("", 14, Color(1.0, 0.8, 0.4))
	_message.visible = false
	add_child(_message)
	refresh()


func credits() -> int:
	return int(account.get("credits", 0)) if account != null else Profile.credits


func stash_items() -> Array:
	return account.get("stash", []) if account != null else Profile.stash


## The tabs on show: the shops (or just the filtered one), then selling.
func tabs() -> Array[String]:
	var out: Array[String] = []
	for shop_id in ShopDB.ids():
		if shop_filter == "" or shop_filter == shop_id:
			out.append(shop_id)
	out.append(SELL_TAB)
	return out


func open_tab(tab: String) -> void:
	current = tab
	show_message("")
	refresh()


## Item ids in the stash that can be sold, most valuable first, no duplicates.
func sellable() -> Array[String]:
	var out: Array[String] = []
	for id: Variant in stash_items():
		if typeof(id) == TYPE_STRING and id not in out and Economy.sell_price(id) > 0:
			out.append(id)
	out.sort_custom(func(a: String, b: String) -> bool:
		return Economy.sell_price(a) > Economy.sell_price(b) if Economy.sell_price(a) != Economy.sell_price(b) else a < b)
	return out


## Buys one item: asks the server online, trades with the profile solo.
func buy(shop_id: String, item_id: String) -> void:
	if account != null:
		buy_requested.emit(shop_id, item_id)
		return
	_done(Profile.buy(shop_id, item_id), "Bought %s." % ItemDB.item_name(item_id))


## Sells `count` of an item, or all loot when `item_id` is empty.
func sell(item_id: String, count: int = 1) -> void:
	if account != null:
		sell_requested.emit(item_id, count)
		return
	var result: Dictionary = Profile.sell_loot() if item_id == "" else Profile.sell(item_id, count)
	_done(result, "Sold for %d credits." % result.get("earned", 0))


func show_message(text: String) -> void:
	if _message:
		_message.text = text
		_message.visible = text != ""


func refresh() -> void:
	if _rows == null:
		return
	if current not in tabs():
		current = tabs()[0]
	_credits.text = "%d credits" % credits()
	for child in _tabs.get_children():
		child.queue_free()
	for tab in tabs():
		var button := Button.new()
		button.text = "Sell" if tab == SELL_TAB else ShopDB.shop_name(tab)
		button.toggle_mode = true
		button.button_pressed = tab == current
		button.custom_minimum_size = Vector2(120, 34)
		button.pressed.connect(open_tab.bind(tab))
		_tabs.add_child(button)
	for child in _rows.get_children():
		child.queue_free()
	if current == SELL_TAB:
		_fill_sell()
	else:
		_fill_shop(current)


func _fill_shop(shop_id: String) -> void:
	_blurb.text = ShopDB.shop(shop_id).get("blurb", "")
	for id in Economy.stock(shop_id):
		var price := Economy.buy_price(id)
		var owned := stash_items().count(id)
		var button := _row(id, "%s%s" % [ItemDB.item_description(id), "  (you own %d)" % owned if owned > 0 else ""],
				"Buy  %d" % price)
		button.disabled = credits() < price
		button.pressed.connect(buy.bind(shop_id, id))


func _fill_sell() -> void:
	_blurb.text = "Loot sells for its full value. Gear and furniture sell back for %d%% of theirs." % int(
			Economy.SELL_BACK_RATE * 100)
	var loot := Economy.loot_value(stash_items())
	var all := Button.new()
	all.text = "Sell all loot  +%d" % loot
	all.tooltip_text = "Sells materials and other loot. Never sells gear or furniture."
	all.custom_minimum_size = Vector2(0, 38)
	all.disabled = loot <= 0
	all.pressed.connect(sell.bind("", 1))
	_rows.add_child(all)
	for id in sellable():
		var count := stash_items().count(id)
		var kind := "Loot" if Economy.is_trade_good(id) else "Gear"
		var button := _row(id, "%s  x%d" % [kind, count], "Sell 1  +%d" % Economy.sell_price(id))
		button.pressed.connect(sell.bind(id, 1))


## Adds one item row and returns its button.
func _row(id: String, detail: String, action: String) -> Button:
	var row := HBoxContainer.new()
	var name_label := _label(ItemDB.item_name(id), 15, ItemDB.RARITY_COLORS[ItemDB.item_rarity(id)])
	name_label.custom_minimum_size = Vector2(190, 0)
	row.add_child(name_label)
	var detail_label := _label(detail, 13, Color(0.7, 0.7, 0.7), true)
	detail_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(detail_label)
	var button := Button.new()
	button.text = action
	button.custom_minimum_size = Vector2(130, 0)
	row.add_child(button)
	_rows.add_child(row)
	return button


func _done(result: Dictionary, success: String) -> void:
	show_message(success if result.ok else result.get("error", ""))
	refresh()
	if result.ok:
		changed.emit()


func _label(text: String, font_size: int, color: Color, wrap := false) -> Label:
	var label := Label.new()
	label.text = text
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label
