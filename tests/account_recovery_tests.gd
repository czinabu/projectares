extends RefCounted
## Checks for account recovery codes (DESIGN.md section 14, "Sign-in"): an
## account tied to the secret one computer's game made can be moved to
## another computer with a one-time code the server makes
## (`StashService.make_recovery_code`, `recover`, the "recovery" sign-in).
##
## First the rules on a `StashService` alone, then for real: a server, a
## player who asks for a code through the phone's request, and a second
## computer (another secret) that signs in with it.
## Starts a server, so it runs in the online tier.
## `-- --groups AccountRecoveryTests` runs just these.

const PORT := 25725
const Accounts := preload("res://core/account/stash_service.gd")


static func run(t: Node) -> void:
	print("Account recovery: a one-time code moves an account to another computer")
	_rules(t)
	await _for_real(t)


static func _rules(t: Node) -> void:
	var stash := Accounts.new()
	stash.persist = false
	var old_secret := Accounts.new_secret()
	var new_secret := Accounts.new_secret()
	var signed: Dictionary = stash.sign_in_with({"method": "secret", "name": "Tova Reyes", "secret": old_secret})
	var id: String = signed.account_id

	var none: Dictionary = stash.sign_in_with({"method": "recovery", "name": "Tova Reyes",
			"code": "ABCD-EFGH-JKMN-PQRS", "secret": new_secret})
	t.check(not none.ok, "an account that never made a code cannot be recovered")

	var made := stash.make_recovery_code(id)
	var code: String = made.get("code", "")
	t.check(made.ok and code.length() == 19 and code.count("-") == 3
			and Accounts.clean_recovery_code(code).length() == Accounts.RECOVERY_LENGTH,
			"a code is 16 letters and digits in groups of four (%s)" % code)
	t.check(code not in str(stash.load_account(id).to_dict()), "the account keeps only the code's hash, never the code")
	var clean := Accounts.clean_recovery_code(code)
	t.check(Accounts.clean_recovery_code(code.to_lower().replace("-", " ")) == clean,
			"a code typed in lower case or with spaces reads the same")
	for c in clean:
		t.check(c not in "01OIL", "a code never holds letters that look alike (%s)" % c)
		if c in "01OIL":
			break

	var wrong: Dictionary = stash.sign_in_with({"method": "recovery", "name": "Tova Reyes",
			"code": "ABCD-EFGH-JKMN-PQRS", "secret": new_secret})
	t.check(not wrong.ok, "the wrong code is refused")
	var other: Dictionary = stash.sign_in_with({"method": "recovery", "name": "Somebody Else",
			"code": code, "secret": new_secret})
	t.check(not other.ok, "the right code with another name is refused")

	var replaced := stash.make_recovery_code(id)
	var stale: Dictionary = stash.sign_in_with({"method": "recovery", "name": "Tova Reyes",
			"code": code, "secret": new_secret})
	t.check(not stale.ok, "making a new code cancels the last one")
	code = replaced.code

	var token: String = signed.token
	var moved: Dictionary = stash.sign_in_with({"method": "recovery", "name": "Tova Reyes",
			"code": code.to_lower(), "secret": new_secret})
	t.check(moved.ok and moved.account_id == id and moved.get("recovered", false) and moved.has("token"),
			"the name and the code move the account, and hand out a token like any sign-in")
	t.check(not stash.sign_in_with({"method": "secret", "name": "Tova Reyes", "secret": old_secret}).ok,
			"the old computer's secret no longer signs in")
	t.check(stash.sign_in_with({"method": "secret", "name": "Tova Reyes", "secret": new_secret}).ok,
			"the new computer's secret does")
	t.check(not stash.verify(token).ok, "a token the old computer held is dropped")
	var again: Dictionary = stash.sign_in_with({"method": "recovery", "name": "Tova Reyes",
			"code": code, "secret": Accounts.new_secret()})
	t.check(not again.ok, "a code works only once")


static func _for_real(t: Node) -> void:
	var pid: int = t._start_server(PORT, ["--bots", "0"] as Array[String])
	var first: NetSession = await t._sign_in("Rena Cole", PORT)
	t.check(first != null, "a player signs in on the first computer")
	if first == null:
		OS.kill(pid)
		return
	var got := {"code": "", "error": ""}
	first.recovery_code_received.connect(func(code: String, error: String) -> void:
		got.code = code
		got.error = error)
	first.request_recovery_code()
	await t._wait_until(func() -> bool: return got.code != "" or got.error != "", 240)
	t.check(got.code != "" and got.error == "", "asking the server for a code brings one back (%s)" % got.error)
	await t._leave(first)

	# The second computer: the same name, its own secret, and the code.
	var second: NetSession = t._new_client("Rena Cole", Accounts.new_secret())
	second.recovery = got.code
	var state := {"failed": ""}
	second.failed.connect(func(reason: String) -> void: state.failed = reason)
	second.join("127.0.0.1", PORT)
	await t._wait_until(func() -> bool: return state.failed != "" or not second.account.is_empty(), 240)
	t.check(not second.account.is_empty() and second.recovered and second.recovery == "",
			"the second computer signs in with the code and is told the account moved (%s)" % state.failed)
	await t._leave(second)

	# The first computer's secret (the one `_new_client` keeps for the name)
	# is turned away now.
	var stale: NetSession = t._new_client("Rena Cole")
	var stale_state := {"failed": ""}
	stale.failed.connect(func(reason: String) -> void: stale_state.failed = reason)
	stale.join("127.0.0.1", PORT)
	await t._wait_until(func() -> bool: return stale_state.failed != "" or not stale.account.is_empty(), 240)
	t.check(stale.account.is_empty() and stale_state.failed != "", "the first computer can no longer sign in")
	await t._leave(stale)
	OS.kill(pid)
