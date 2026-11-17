extends CanvasLayer
## Hold Q in a raid to see everyone playing: who is fighting, who is down,
## who has left, kills across all their lives, and their renown and bounty. Plain themed controls so the UI theme styles it.

const RaidRoster := preload("res://core/ui/raid_roster.gd")
const RenownLedger := preload("res://core/progression/renown_ledger.gd")
const COLUMNS := 4

## How often the roster is checked, and the table rebuilt while open, in seconds.
var refresh_interval := 0.25

var raid: Raid
var roster: RaidRoster
var _panel: PanelContainer
var _title: Label
var _grid: GridContainer
var _refresh_left := 0.0
var _forced := false


func setup(p_raid: Raid, p_me: Actor = null) -> void:
	raid = p_raid
	roster = RaidRoster.new(p_raid, p_me if p_me != null else p_raid.player)
	roster.refresh()


func _ready() -> void:
	layer = 5
	var root := CenterContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.custom_minimum_size = Vector2(680, 0)
	root.add_child(_panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	_panel.add_child(margin)
	var box := VBoxContainer.new()
	margin.add_child(box)
	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title)
	box.add_child(HSeparator.new())
	_grid = GridContainer.new()
	_grid.columns = COLUMNS
	box.add_child(_grid)
	visible = false


func _process(delta: float) -> void:
	if raid == null or not is_instance_valid(raid):
		return
	var want := _forced or Input.is_action_pressed("scoreboard")
	if want != visible:
		visible = want
		_refresh_left = 0.0
	_refresh_left -= delta
	if _refresh_left > 0.0:
		return
	_refresh_left = refresh_interval
	# The roster keeps watching while the board is closed, so someone who
	# joins and leaves between looks is still listed.
	if visible:
		rebuild()
	else:
		roster.refresh()


## Keeps the board open without the key, for tests and screenshots.
func show_board(on: bool) -> void:
	_forced = on
	visible = on
	if on:
		rebuild()


func rebuild() -> void:
	if roster == null:
		return
	roster.refresh()
	_title.text = "%s   Bots %d" % [
		raid.world.display_name if raid.world else "Raid", roster.bots_alive()]
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	_cell("Player", true)
	_cell("Status", true)
	_cell("Kills", true)
	_cell("Renown", true)
	for entry in roster.entries:
		_cell(("%s (you)" % entry.name) if entry.is_me else String(entry.name))
		_cell(entry.status)
		_cell(str(entry.kills) if roster.kills_known(entry) else "-")
		_cell(renown_cell(entry))


## Rank and session renown, with the price on their head if there is one.
static func renown_cell(entry: Dictionary) -> String:
	var text := "%s  %d" % [RenownLedger.rank_name(entry.get("rank", 0)), entry.get("renown", 0)]
	if entry.get("marked", false):
		text += "  MARKED"
	if entry.get("bounty", 0) > 0:
		text += "  Bounty %d" % entry.bounty
	return text


## The text in each row, for tests: [[name, status, kills, renown], ...].
func rows() -> Array:
	var out := []
	var cells := _grid.get_children()
	for i in range(COLUMNS, cells.size(), COLUMNS):
		out.append([cells[i].text, cells[i + 1].text, cells[i + 2].text, cells[i + 3].text])
	return out


func _cell(text: String, header := false) -> void:
	var label := Label.new()
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if header:
		label.theme_type_variation = &"HeaderSmall"
	_grid.add_child(label)
