extends RefCounted
## The `renown` checks. The test runner finds this file by itself and calls
## `run(t)`.

const RaidRoster := preload("res://core/ui/raid_roster.gd")
const NameplatesScript := preload("res://core/ui/nameplates.gd")
const ScoreboardScript := preload("res://core/ui/scoreboard.gd")
const RenownLedger := preload("res://core/progression/renown_ledger.gd")


static func run(t: Node) -> void:
	print("Renown and bounties")
	# The ledger on its own: plain arithmetic.
	var book := RenownLedger.new()
	book.enter("ana", "Ana", 190)
	book.enter("ben", "Ben")
	t.check(book.bot_killed("ana") == 10 and book.bot_killed("ana") == 11,
			"a bot kill pays renown, and each kill in a streak pays a little more")
	var ana := book.get_standing("ana")
	t.check(ana.renown == 21 and ana.lifetime == 211 and RenownLedger.rank_for(ana.lifetime) == 1
			and RenownLedger.rank_name(1) == "Raider", "lifetime renown raises your rank")
	t.check(RenownLedger.to_next_rank(211) == 589 and RenownLedger.to_next_rank(999999) == 0,
			"the next rank says how far away it is")
	book.get_standing("ben").renown = 400
	t.check(book.marked() == "ben", "the living player with the most renown is the Marked")
	var paid := book.player_died("ben", "ana")
	t.check(paid.lost == 40 and paid.stolen == 40 and paid.marked and book.get_standing("ben").renown == 360,
			"dying costs a tenth of your session renown")
	t.check(paid.gain == 120 + 40 + book.marked_bonus and ana.renown == 21 + paid.gain,
			"the killer gets the kill, the stolen share and the bonus for the Marked")
	t.check(book.marked() == "ana", "a dead player is not the Marked")
	book.enter("ben", "Ben")
	t.check(book.get_standing("ben").renown == 360, "session renown carries into the next life")
	var before := ana.renown
	t.check(book.player_died("ben", "ana", true).gain == roundi(10 * 1.3) + 36,
			"killing someone in the scrap kit pays almost nothing for the kill")
	t.check(book.bounty_of("ana") == 0, "two player kills are not a bounty yet")
	book.enter("ben", "Ben")
	book.player_died("ben", "ana", true)
	t.check(book.bounty_of("ana") == 150 and not book.is_exposed("ana"), "three player kills in one life put a price on you")
	for i in 2:
		book.enter("ben", "Ben")
		book.player_died("ben", "ana", true)
	t.check(book.bounty_of("ana") == 250 and book.is_exposed("ana"), "five show you to everyone")
	book.enter("cy", "Cy")
	var claim := book.player_died("ana", "cy")
	t.check(claim.bounty == 250 and claim.gain >= 250 + 100 and book.bounty_of("ana") == 0
			and ana.player_streak == 0, "the killer collects the bounty and the streak ends")
	t.check(ana.lifetime > before + 190, "death never takes lifetime renown")
	book.leave("ana")
	t.check(book.get_standing("ana") == null, "leaving the world ends the session")

	# In a running world.
	var raid := Raid.new()
	t.add_child(raid)
	raid.apply_to_profile = false
	raid.start_server(Worlds.get_world("ashfront"), 91)
	# Keep the war quiet here, so kills pay their plain value.
	raid.war.scale = 0.0
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
	var feed: Array[String] = []
	raid.war_feed.connect(func(text: String) -> void: feed.append(text))
	var results := {}
	raid.player_finished.connect(func(actor: Actor, result: Dictionary) -> void:
		results[actor.display_name] = result)
	var kit: Array[String] = ["rifle_carbine", "frame_trooper"]
	var hunter := raid.add_player(kit, {}, "Hunter", "acct-hunter", 900)
	var prey := raid.add_player(kit, {}, "Prey", "acct-prey", 0)
	await t.frames(3)
	t.check(hunter.rank == 2 and prey.rank == 0 and hunter.renown == 0, "a player arrives with their rank and no session renown")
	var notices: Array[String] = []
	hunter.notice.connect(func(text: String) -> void: notices.append(text))
	raid.bots[0].kill("bullet", hunter)
	t.check(hunter.renown == 10 and hunter.streak == 1 and notices.size() == 1
			and notices[0].begins_with("Killed ") and notices[0].ends_with("+10 renown"),
			"killing a bot pays renown and says so")
	t.check(feed.is_empty(), "bot kills stay out of the world feed")
	raid.renown.get_standing("acct-prey").renown = 500
	prey.kill("bullet", hunter)
	await t.frames(2)
	t.check(results.has("Prey") and results.Prey.renown_lost == 50 and results.Prey.renown_now == 450,
			"a death reports the renown it cost")
	t.check(hunter.renown == 10 + 110 + 50 + raid.renown.marked_bonus,
			"the killer is paid for the kill, the share and the Marked (%d)" % hunter.renown)
	t.check(feed.has("Hunter [Veteran] killed Prey [Recruit], the Marked"), "a player kill is announced with ranks (%s)" % " / ".join(feed))
	t.check(hunter.marked and feed.has("Hunter is now the Marked"), "the new Marked is announced")
	t.check("Renown lost: 50" in Hud.death_text(results.Prey, 0.0), "the death screen shows the renown lost")
	for i in 2:
		prey = raid.add_player(kit, {}, "Prey", "acct-prey", 0)
		await t.frames(1)
		prey.kill("bullet", hunter)
		await t.frames(1)
	t.check(hunter.bounty == 150 and feed.has("Hunter has a bounty of 150"), "three player kills announce a bounty")
	t.check(Hud.standing_text(hunter).begins_with("Veteran   Renown ") and "BOUNTY 150" in Hud.standing_text(hunter)
			and "THE MARKED" in Hud.standing_text(hunter), "the HUD shows your rank, renown and bounty")
	t.check(NameplatesScript.plate_text(hunter) == "Hunter  Veteran  MARKED  Bounty 150", "a nameplate shows rank, the Marked and the bounty")
	var roster := RaidRoster.new(raid, prey)
	roster.refresh()
	var row: Dictionary = roster.entries.filter(func(e: Dictionary) -> bool: return e.name == "Hunter")[0]
	t.check(ScoreboardScript.renown_cell(row) == "Veteran  %d  MARKED  Bounty 150" % hunter.renown, "the scoreboard lists renown and bounties")
	for i in 2:
		prey = raid.add_player(kit, {}, "Prey", "acct-prey", 0)
		await t.frames(1)
		prey.kill("bullet", hunter)
		await t.frames(1)
	t.check(hunter.exposed and feed.any(func(text: String) -> bool: return text.begins_with("Hunter is exposed")),
			"five player kills expose you to everyone")

	# A hunted player's plate shows through a wall and at any distance.
	var far := raid.add_player(kit, {}, "Far", "acct-far", 0)
	var camera := Camera3D.new()
	raid.add_child(camera)
	camera.make_current()
	var plates := NameplatesScript.new()
	plates.setup(raid, far)
	raid.add_child(plates)
	hunter.global_position = Vector3(0, 300, -200)
	far.global_position = Vector3(0, 300, 0)
	camera.global_position = Vector3(0, 301.6, 0)
	camera.look_at(Vector3(0, 301.6, -200))
	await t.frames(2)
	plates.update_plates()
	t.check(plates.plates().has(hunter.get_instance_id()), "an exposed player's nameplate shows from across the map")
	hunter.exposed = false
	hunter.marked = false
	plates.update_plates()
	t.check(not plates.plates().has(hunter.get_instance_id()), "an ordinary player's does not")
	plates.queue_free()
	camera.queue_free()

	# The bounty is paid out, and renown reaches the account.
	var earned_before := hunter.renown
	var avenger := raid.add_player(kit, {}, "Avenger", "acct-avenger", 0)
	await t.frames(1)
	hunter.kill("bullet", avenger)
	await t.frames(2)
	t.check(avenger.renown >= 250 + 100 and feed.any(func(text: String) -> bool:
			return text.begins_with("Avenger [") and text.ends_with("and claimed a bounty of 250")),
			"killing a hunted player pays their bounty")
	t.check(results.Hunter.renown >= 0 and results.Hunter.renown_lost == int(floor(earned_before * 0.1)),
			"the hunted player's last life reports its renown")
	var avenger_renown := avenger.renown
	raid.clock += 1000.0
	raid.begin_sign_out(avenger)
	for i in int(raid.world.sign_out_time * 60.0) + 40:
		if results.has("Avenger"):
			break
		await t.frames(1)
	t.check(results.has("Avenger") and results.Avenger.outcome == "left" and results.Avenger.renown == avenger_renown
			and raid.renown.get_standing("acct-avenger") == null,
			"signing out keeps the renown you earned and ends the session")
	var was_persist := Profile.persist
	Profile.persist = false
	var had := Profile.renown
	Profile.record_raid({"outcome": "died", "renown": 75})
	t.check(Profile.renown == had + 75, "lifetime renown is saved with the profile")
	Profile.renown = had
	Profile.raids_played -= 1
	Profile.persist = was_persist
	t.check(Hub.renown_text(250) == "Rank Raider   Renown 250   (550 to Veteran)", "the hub shows your rank and what the next one takes")
	await t._end_raid(raid)
