class_name Inventory
extends Node
## A backpack: a capped list of item ids. Everything in it is at risk in a raid.

signal changed

var capacity := 12
var items: Array[String] = []


func add_item(id: String) -> bool:
	if is_full():
		return false
	items.append(id)
	changed.emit()
	return true


func remove_item(id: String) -> bool:
	var index := items.find(id)
	if index < 0:
		return false
	items.remove_at(index)
	changed.emit()
	return true


func has_item(id: String) -> bool:
	return id in items


## The first carried item with this tag, or "" if there is none.
func first_with_tag(tag: String) -> String:
	for id in items:
		if ItemDB.has_tag(id, tag):
			return id
	return ""


func count_with_tag(tag: String) -> int:
	var count := 0
	for id in items:
		if ItemDB.has_tag(id, tag):
			count += 1
	return count


func is_full() -> bool:
	return items.size() >= capacity


func total_value() -> int:
	return ItemDB.total_value(items)
