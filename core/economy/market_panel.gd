extends VBoxContainer
## The player market's screen, on the kiosk in the plaza: what other players
## have listed, your own listings, and your stash's tradeable items to list.
## Only a view: it shows `state` (the server's board, see
## `MarketService.snapshot`) and `account` (your snapshot), and asks with
## `asked`. Prices and fees shown are `Market`'s, but the server decides.
##
## Load with `const MarketPanel := preload("res://core/economy/market_panel.gd")`.

const Market := preload("res://core/economy/market.gd")

const TITLE_COLOR := Color(0.45, 0.9, 0.85)
const SCRIP_COLOR := Color(1.0, 0.85, 0.4)
const BUY_TAB := "buy"
const SELL_TAB := "sell"

## "buy" (`a` listing id, `b` how many), "cancel" (`a` listing id) or "list"
## (`item_id`, `a` how many, `b` the price each).
signal asked(action: String, item_id: String, a: int, b: int)

## The account snapshot from the server: its "stash" and "scrip" are read.
var account := {}
## The board from the server: {"listings", "trades_left", "listed"}.
var state := {}
## The tab on show.
var current := BUY_TAB

var _scrip: Label
var _tabs: HBoxContainer
var _rows: VBoxContainer
var _message: Label


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	var head := HBoxContainer.new()
	var title := _label("PLAYER MARKET", 20, TITLE_COLOR)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_scrip = _label("", 18, SCRIP_COLOR)
	head.add_child(_scrip)
	add_child(head)
	add_child(_label("Buy what other players found, or list your own. Listing costs %d%% of the price, the board "
			% roundi(Market.LISTING_FEE_RATE * 100) + "keeps %d%% of each sale, and unsold items come home after %d days. "
			% [roundi(Market.SALE_FEE_RATE * 100), Market.LISTING_DAYS]
			+ "Mk3 gear, heavy weapons and artifacts never trade.", 13, Color(0.65, 0.65, 0.65), true))
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 6)
	add_child(_tabs)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 3)
	add_child(_rows)
	_message = _label("", 14, Color(1.0, 0.8, 0.4))
	_message.visible = false
	add_child(_message)
	refresh()


func show_message(text: String) -> void:
	if _message:
		_message.text = text
		_message.visible = text != ""


## Your stash's tradeable items: [{"id", "have"}], by name.
static func sellable(stash: Variant) -> Array[Dictionary]:
	var counts := {}
	if typeof(stash) == TYPE_ARRAY:
		for id: Variant in stash:
			if typeof(id) == TYPE_STRING and Market.tradeable(id):
				counts[id] = int(counts.get(id, 0)) + 1
	var out: Array[Dictionary] = []
	for id: String in counts:
		out.append({"id": id, "have": counts[id]})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return ItemDB.item_name(a.id) < ItemDB.item_name(b.id))
	return out


## The board's lines as text, what `refresh` builds from and tests read:
## {"text", "action" ("buy", "cancel" or ""), "id", "enabled"}.
static func listing_rows(p_state: Variant, scrip: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if typeof(p_state) != TYPE_DICTIONARY or not p_state.has("listings"):
		out.append({"text": "Connecting to the board...", "action": "", "id": 0, "enabled": false})
		return out
	var trades_left := int(p_state.get("trades_left", 0))
	out.append({"text": "%d TRADES LEFT TODAY" % trades_left, "action": "", "id": 0, "enabled": false})
	var listings: Array = p_state.get("listings", [])
	if listings.is_empty():
		out.append({"text": "Nothing is listed yet.", "action": "", "id": 0, "enabled": false})
	for entry: Dictionary in listings:
		var text := "%s x%d   %d each   %s" % [ItemDB.item_name(entry.item), entry.count, entry.price,
				"yours, %d days left" % entry.days_left if entry.mine else "from " + str(entry.seller)]
		if entry.mine:
			out.append({"text": text, "action": "cancel", "id": entry.id, "enabled": true})
		else:
			out.append({"text": text, "action": "buy", "id": entry.id,
					"enabled": trades_left > 0 and scrip >= int(entry.price)})
	return out


func refresh() -> void:
	if _rows == null:
		return
	_scrip.text = "%d scrip" % int(account.get("scrip", 0))
	for child in _tabs.get_children():
		child.queue_free()
	for tab: String in [BUY_TAB, SELL_TAB]:
		var button := _button("Buy" if tab == BUY_TAB else "Sell", func() -> void:
			current = tab
			show_message("")
			refresh())
		button.disabled = tab == current
		_tabs.add_child(button)
	for child in _rows.get_children():
		child.queue_free()
	if current == BUY_TAB:
		_show_board()
	else:
		_show_stash()


func _show_board() -> void:
	for row in listing_rows(state, int(account.get("scrip", 0))):
		var line := HBoxContainer.new()
		var text := _label(row.text, 15 if row.action != "" else 16,
				Color(0.9, 0.9, 0.9) if row.action != "" else TITLE_COLOR)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(text)
		if row.action != "":
			var id: int = row.id
			var action: String = row.action
			var button := _button("Buy one" if action == "buy" else "Take down", func() -> void:
				show_message("")
				asked.emit(action, "", id, 1))
			button.disabled = not row.enabled
			line.add_child(button)
		_rows.add_child(line)


func _show_stash() -> void:
	var listed := int(state.get("listed", 0))
	_rows.add_child(_label("YOUR LISTINGS  %d/%d" % [listed, Market.MAX_LISTINGS], 16, TITLE_COLOR))
	var items := sellable(account.get("stash", []))
	if items.is_empty():
		_rows.add_child(_label("Nothing in your stash can be traded.", 15, Color(0.7, 0.7, 0.7)))
	for entry in items:
		var id: String = entry.id
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 6)
		var text := _label("%s x%d" % [ItemDB.item_name(id), entry.have], 15, Color(0.9, 0.9, 0.9))
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(text)
		var count := _spin(1, mini(int(entry.have), Market.MAX_STACK), 1)
		line.add_child(count)
		var price := _spin(Market.min_price(id), Market.max_price(id), Market.board_value(id))
		price.suffix = "each"
		line.add_child(price)
		var button := _button("", func() -> void:
			show_message("")
			asked.emit("list", id, int(count.value), int(price.value)))
		var label_fee := func(_v: float = 0.0) -> void:
			button.text = "List (fee %d)" % Market.listing_fee(int(price.value), int(count.value))
		label_fee.call()
		count.value_changed.connect(label_fee)
		price.value_changed.connect(label_fee)
		button.disabled = listed >= Market.MAX_LISTINGS or int(state.get("trades_left", 0)) <= 0
		line.add_child(button)
		_rows.add_child(line)


func _spin(low: int, high: int, start: int) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = low
	spin.max_value = maxi(low, high)
	spin.step = 1
	spin.rounded = true
	spin.value = clampi(start, low, maxi(low, high))
	spin.custom_minimum_size = Vector2(110, 32)
	return spin


func _button(text: String, pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(120, 34)
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
