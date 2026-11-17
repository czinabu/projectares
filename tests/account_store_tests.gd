extends RefCounted
## Checks for accounts on SQLite (DESIGN.md section 14, step 3): the store
## saves and reloads accounts, the market's five ledger calls, the
## all-or-nothing `transaction` (a refused step or a failed save changes
## nothing, in memory or on disk), the one-time import of old account files,
## and the JSON fallback. Called from the test runner
## (`-- --groups AccountStoreTests` runs just these).

const Accounts := preload("res://core/account/stash_service.gd")
const AccountStore := preload("res://core/account/account_store.gd")


static func run(t: Node) -> void:
	print("Accounts on SQLite")
	t.check(AccountStore.sqlite_available(), "the SQLite extension loads in this build")
	_store_basics(t)
	_ledger_and_transactions(t)
	_import(t)
	_json_fallback(t)


static func _dir(tag: String) -> String:
	return "user://test_store_%s_%d" % [tag, Time.get_ticks_usec()]


static func _wipe(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for sub in DirAccess.get_directories_at(dir):
		_wipe(dir.path_join(sub))
	for file in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(file))
	DirAccess.remove_absolute(dir)


static func _service(dir: String) -> Accounts:
	var service := Accounts.new()
	service.save_dir = dir
	return service


static func _store_basics(t: Node) -> void:
	var dir := _dir("basics")
	var service := _service(dir)
	var secret := Accounts.new_secret()
	var id: String = service.sign_in("Store Rat", secret).account_id
	t.check(service.store() != null and service.store().kind == "sqlite"
			and FileAccess.file_exists(dir.path_join(AccountStore.FILE_NAME))
			and not FileAccess.file_exists(dir.path_join(id + ".json")),
			"a new account is saved in the database, not as a file")
	service.change_scrip(id, 77)
	var scrip := service.scrip_of(id)
	var restarted := _service(dir)
	t.check(restarted.scrip_of(id) == scrip and restarted.sign_in("Store Rat", secret).ok
			and not restarted.sign_in("Store Rat", Accounts.new_secret()).ok,
			"an account reloads from the database after a restart, secret and all")
	t.check(restarted.store().ids() == [id], "the store lists the accounts it holds")

	# A backup is a consistent copy that opens as a store of its own.
	var backup := dir + "_backup"
	t.check(restarted.store().backup_to(backup), "the database backs up while open")
	var from_backup := _service(backup)
	t.check(from_backup.scrip_of(id) == scrip, "a backup holds the accounts")
	from_backup.close()
	service.close()
	restarted.close()
	_wipe(backup)
	_wipe(dir)


static func _ledger_and_transactions(t: Node) -> void:
	var dir := _dir("trade")
	var service := _service(dir)
	var seller: String = service.sign_in("Seller", Accounts.new_secret()).account_id
	var buyer: String = service.sign_in("Buyer", Accounts.new_secret()).account_id
	service.give_items(seller, ["alloy_ingot", "alloy_ingot", "alloy_ingot"])
	t.check(service.count_of(seller, "alloy_ingot") == 3 and service.count_of("nobody", "alloy_ingot") == 0,
			"count_of reads the stash")
	t.check(not service.take_items(seller, "alloy_ingot", 4) and service.count_of(seller, "alloy_ingot") == 3,
			"take_items refuses more than there is and changes nothing")
	var seller_scrip := service.scrip_of(seller)
	var buyer_scrip := service.scrip_of(buyer)
	var price := 40

	# A trade: the seller's goods to the buyer, the buyer's money to the seller.
	var trade := [
		["change_scrip", buyer, -price],
		["take_items", seller, "alloy_ingot", 2],
		["give_items", buyer, ["alloy_ingot", "alloy_ingot"]],
		["change_scrip", seller, price],
	]
	t.check(service.transaction(trade).ok, "a trade goes through as one transaction")
	t.check(service.count_of(seller, "alloy_ingot") == 1 and service.count_of(buyer, "alloy_ingot") == 2
			and service.scrip_of(seller) == seller_scrip + price and service.scrip_of(buyer) == buyer_scrip - price,
			"every step of the trade happened")
	var reread := _service(dir)
	t.check(reread.count_of(buyer, "alloy_ingot") == 2 and reread.scrip_of(seller) == seller_scrip + price,
			"the whole trade is on disk")
	reread.close()

	# A step that refuses undoes the ones before it, in memory and on disk.
	var before_seller := service.snapshot(seller)
	var before_buyer := service.snapshot(buyer)
	var bad := service.transaction([
		["change_scrip", buyer, -price],
		["give_items", buyer, ["alloy_ingot"]],
		["take_items", seller, "alloy_ingot", 5],
		["change_scrip", seller, price],
	])
	t.check(not bad.ok and bad.get("step", -9) == 2, "a refused step fails the whole trade and names the step")
	t.check(service.snapshot(seller) == before_seller and service.snapshot(buyer) == before_buyer,
			"a failed trade leaves both accounts as they were")
	var after_bad := _service(dir)
	t.check(after_bad.scrip_of(buyer) == buyer_scrip - price and after_bad.count_of(buyer, "alloy_ingot") == 2,
			"nothing of a failed trade reached the disk")
	after_bad.close()
	t.check(not service.transaction([["change_scrip", buyer, -99999999]]).ok
			and service.scrip_of(buyer) == buyer_scrip - price, "a trade cannot overdraw an account")
	t.check(not service.transaction([["no_such_call", buyer, 1]]).ok
			and not service.transaction([["give_items", "nobody_here", ["alloy_ingot"]]]).ok
			and not service.transaction([["take_items", seller, "alloy_ingot", 1.5]]).ok,
			"an unknown call, a missing account or a bad argument refuses")

	# A save that fails (the database is gone) rolls the trade back too.
	service.store().close()
	var swapped: RefCounted = service._store
	var broken_store := BrokenStore.new()
	broken_store.dir = dir
	service._store = broken_store
	var unsaved := service.transaction([["change_scrip", seller, 5], ["change_scrip", buyer, -5]])
	t.check(not unsaved.ok and service.scrip_of(seller) == seller_scrip + price and service.scrip_of(buyer) == buyer_scrip - price,
			"a trade that cannot be saved is undone")
	service._store = swapped

	# A deployed account cannot sell what it has out in a raid.
	service.deploy(seller, Worlds.get_world("ashfront"))
	t.check(not service.transaction([["take_items", seller, "alloy_ingot", 1]]).ok, "a deployed account cannot be traded from")
	service.cancel_deploy(seller)
	service.close()
	_wipe(dir)


## Stands in for a store whose writes fail.
class BrokenStore:
	extends RefCounted
	var dir := ""
	var kind := "sqlite"

	func is_open() -> bool:
		return true

	func write(_accounts: Array) -> bool:
		return false

	func read(_id: String) -> Dictionary:
		return {}

	func has(_id: String) -> bool:
		return false


static func _import(t: Node) -> void:
	var dir := _dir("import")
	# Two accounts saved the old way, plus files that are not accounts.
	var old := _service(dir)
	old.force_json = true
	var vex: String = old.sign_in("Vex Runner", Accounts.new_secret()).account_id
	var secret := Accounts.new_secret()
	var ida: String = old.sign_in("Ida Moss", secret).account_id
	old.give_items(ida, ["alloy_ingot"])
	old.change_scrip(ida, 123)
	old.deploy(vex, Worlds.get_world("ashfront"))
	var ida_scrip := old.scrip_of(ida)
	old.close()
	var news := FileAccess.open(dir.path_join("news.json"), FileAccess.WRITE)
	news.store_string("[{\"title\": \"hi\"}]")
	news.close()
	var broken := FileAccess.open(dir.path_join("broken.json"), FileAccess.WRITE)
	broken.store_string("{ not json")
	broken.close()
	t.check(FileAccess.file_exists(dir.path_join(ida + ".json")), "the old accounts start as files")

	var service := _service(dir)
	var store: RefCounted = service.store()
	t.check(store.kind == "sqlite" and store.imported == 2, "opening the database imports the old account files")
	t.check(service.scrip_of(ida) == ida_scrip and service.count_of(ida, "alloy_ingot") == 1
			and service.sign_in("Ida Moss", secret).ok, "an imported account keeps its stash, money and secret")
	t.check(service.snapshot(vex).ok and not service.is_deployed(vex),
			"an account imported mid-raid gets its gear back")
	t.check(not FileAccess.file_exists(dir.path_join(ida + ".json"))
			and FileAccess.file_exists(dir.path_join(ida + ".json" + AccountStore.IMPORTED_SUFFIX)),
			"an imported file is renamed, never deleted")
	t.check(FileAccess.file_exists(dir.path_join("news.json")) and FileAccess.file_exists(dir.path_join("broken.json")),
			"files that are not accounts are left alone")
	service.close()

	# A file left over from a crash between the import and the rename: the
	# database wins and the file is only put aside.
	DirAccess.copy_absolute(dir.path_join(ida + ".json" + AccountStore.IMPORTED_SUFFIX), dir.path_join(ida + ".json"))
	var again := _service(dir)
	again.change_scrip(ida, 1)
	again.close()
	var third := _service(dir)
	t.check(third.store().imported == 0 and third.scrip_of(ida) == ida_scrip + 1
			and not FileAccess.file_exists(dir.path_join(ida + ".json")),
			"an old file for an account already in the database never overwrites it")
	third.close()
	_wipe(dir)


static func _json_fallback(t: Node) -> void:
	var dir := _dir("json")
	var service := _service(dir)
	service.force_json = true
	var id: String = service.sign_in("Json Kid", Accounts.new_secret()).account_id
	service.give_items(id, ["alloy_ingot"])
	t.check(service.store().kind == "json" and FileAccess.file_exists(dir.path_join(id + ".json"))
			and not FileAccess.file_exists(dir.path_join(AccountStore.FILE_NAME)),
			"without SQLite the accounts stay as files")
	t.check(service.transaction([["take_items", id, "alloy_ingot", 1], ["change_scrip", id, 5]]).ok
			and service.count_of(id, "alloy_ingot") == 0, "transactions still run on the fallback")
	var reread := _service(dir)
	reread.force_json = true
	t.check(reread.count_of(id, "alloy_ingot") == 0, "and are saved")
	service.close()
	reread.close()
	_wipe(dir)
