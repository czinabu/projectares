extends RefCounted
## Checks for the phone's squads and friends (DESIGN.md "Squads"): squad
## invites, the squad and its chat, leaving, who sees which world you are in
## (friends and squadmates only), and the key a `Raid` keeps for a squad's
## portals. Kept in its own file and called from the test runner.

const SocialService := preload("res://core/social/social_service.gd")
const PhoneScript := preload("res://core/phone/phone.gd")


static func run(t: Node) -> void:
	_squads(t)
	_friends(t)
	_phone(t)
	_portal_key(t)


static func _service() -> SocialService:
	var social := SocialService.new()
	social.persist = false
	for id in ["ana", "ben", "cy", "dee", "eve"]:
		social.player_online(id, id.capitalize(), "hub", "plaza")
	return social


static func _squads(t: Node) -> void:
	print("Squads: invites, chat and leaving")
	var social := _service()
	var asked := social.run("invite", "ana", ["ben", "squad", "plaza"])
	t.check(asked.ok and "ben" in asked.tell and SocialService.invite_text(asked.invite).contains("squad"),
			"a squad invite reaches whoever it is for")
	var answer := social.run("answer", "ben", [int(asked.invite.id), true])
	t.check(answer.ok and social.squad_of("ana") != "" and social.squad_of("ana") == social.squad_of("ben"),
			"accepting puts both in one squad")
	t.check(Array(social.squad_members("ben")) == ["ana", "ben"], "the one who asked leads it")
	var snap := social.snapshot("ben")
	t.check(snap.squad.members.size() == 2 and snap.squad.members[0].leader,
			"the phone shows the squad, its leader first")
	t.check(not social.run("invite", "ana", ["ben", "squad", "plaza"]).ok, "someone already in your squad is not asked again")
	for id in ["cy", "dee"]:
		var more := social.run("invite", "ben", [id, "squad", "plaza"])
		social.run("answer", id, [int(more.invite.id), true])
	t.check(social.squad_members("ana").size() == SocialService.MAX_SQUAD, "a squad takes four")
	t.check(not social.run("invite", "ana", ["eve", "squad", "plaza"]).ok, "and no more")
	var said := social.run("message", "cy", [SocialService.SQUAD_CHAT, "on me"])
	var heard: Array = social.snapshot("ana").messages.filter(func(m: Dictionary) -> bool: return m.get("squad", false))
	t.check(said.ok and "ana" in said.tell and "dee" in said.tell and said.notices.has("ana")
			and heard.size() == 1 and heard[0].text == "on me", "squad chat reaches the whole squad")
	t.check(not social.run("message", "eve", [SocialService.SQUAD_CHAT, "hi"]).ok, "squad chat needs a squad")
	var gone := social.run("squad", "dee", ["leave"])
	t.check(gone.ok and social.squad_of("dee") == "" and social.squad_members("ana").size() == 3 and "ana" in gone.tell,
			"leaving takes you out and tells the rest")
	social.player_offline("cy", "plaza")
	social.run("squad", "ana", ["leave"])
	t.check(social.squad_of("ben") == "" and social.squad_of("ana") == "",
			"a squad of one ends, and going offline leaves it")
	t.check(not social.run("squad", "ana", ["leave"]).ok, "leaving no squad says so")


static func _friends(t: Node) -> void:
	print("Squads: friends and where they are")
	var social := _service()
	social.set_where("ben", "raid", "ashfront")
	social.player_offline("ben", "plaza")
	t.check(social.world_of("ben") == "ashfront", "where a player is comes from their seat")
	var on_service := SocialService.new()
	on_service.persist = false
	on_service.player_online("ana", "Ana", "raid", "eu-1/frostline")
	t.check(on_service.world_of("ana") == "frostline", "an account service's seat names the world after the server")
	t.check(_entry(social, "ana", "ben").world == "", "a stranger's world is not shown")
	social.add_contact("ana", "ben")
	t.check(_entry(social, "ana", "ben").world == "" and not _entry(social, "ana", "ben").friend,
			"saving someone is not enough: they must save you back")
	social.add_contact("ben", "ana")
	t.check(_entry(social, "ana", "ben").world == "ashfront" and _entry(social, "ana", "ben").friend,
			"friends see which world the other is in, to join them")
	var asked := social.run("invite", "cy", ["ana", "squad", "plaza"])
	social.run("answer", "ana", [int(asked.invite.id), true])
	social.set_where("cy", "raid", "frostline")
	t.check(_entry(social, "ana", "cy").world == "frostline" and _entry(social, "ana", "cy").squad
			and _entry(social, "dee", "cy").world == "", "so do squadmates, and nobody else")


static func _entry(social: SocialService, viewer: String, other: String) -> Dictionary:
	for entry: Dictionary in social.snapshot(viewer).contacts:
		if entry.id == other:
			return entry
	return {}


static func _phone(t: Node) -> void:
	print("Squads: the phone's chat threads")
	var phone = PhoneScript.new()
	var net := NetSession.new()
	phone.net = net
	net.social_state = {"account_id": "ana", "messages": [
		{"id": 1, "from": "ben", "from_name": "Ben", "to": "ana", "to_name": "Ana", "text": "hi", "time": 1.0},
		{"id": 2, "from": "ben", "from_name": "Ben", "to": "squad", "to_name": "Squad", "text": "go", "time": 2.0, "squad": true},
		{"id": 3, "from": "ana", "from_name": "Ana", "to": "squad", "to_name": "Squad", "text": "ok", "time": 3.0, "squad": true},
	], "contacts": [], "invites": [], "squad": {"id": "s1", "members": []}}
	var threads: Array[String] = phone.conversations()
	t.check(threads.size() == 2 and threads[0] == SocialService.SQUAD_CHAT and "ben" in threads,
			"squad messages are one conversation, apart from direct ones")
	t.check(phone.conversation_with("ben").size() == 1 and phone.conversation_with(SocialService.SQUAD_CHAT).size() == 2,
			"a squadmate's squad message is not in your chat with them")
	t.check(phone.unread_from(SocialService.SQUAD_CHAT) == 1, "your own squad messages are never unread")
	phone.free()
	net.free()


static func _portal_key(t: Node) -> void:
	print("Squads: who walks through your portals")
	var net := NetSession.new()
	net.social = _service()
	net.social.persist = false
	net.raid = Raid.new()
	var asked: Dictionary = net.social.run("invite", "ana", ["ben", "squad", "plaza"])
	net.social.run("answer", "ben", [int(asked.invite.id), true])
	net._set_squad_key("ana", net._social_squad("ana"))
	net._set_squad_key("ben", net._social_squad("ben"))
	t.check(net.raid.squads.get("ana", "") != "" and net.raid.squads.get("ana") == net.raid.squads.get("ben"),
			"a squad made on the phone is one squad for the world's portals")
	net.social.run("squad", "ben", ["leave"])
	net._set_squad_key("ana", net._social_squad("ana"))
	t.check(not net.raid.squads.has("ana"), "once it ends it is gone (a clan would stand in)")
	net.raid.free()
	net.free()
