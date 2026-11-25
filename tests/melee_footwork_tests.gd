extends RefCounted
## Each melee technique moves the feet its own way (`ActionPose.technique_steps`):
## a knife steps short and quick, a hammer hauls back and drives in slowly,
## a spear lunges the furthest.


static func run(t: Node) -> void:
	print("Melee footwork per weapon")
	var pose := ActionPose.new()
	for tech: String in pose.techniques:
		t.check(pose.technique_steps.has(tech), "the %s technique has its own footwork" % tech)
	var strike := func(tech: String) -> float: return float(pose.technique_steps[tech][1])
	var windup := func(tech: String) -> float: return float(pose.technique_steps[tech][0])
	var rate := func(tech: String) -> float: return float(pose.technique_steps[tech][2])
	t.check(strike.call("knife") < strike.call("slash") and rate.call("knife") > rate.call("slash"),
			"a knife steps in shorter and quicker than a sword")
	t.check(windup.call("chop2") > windup.call("slash") and strike.call("chop2") > strike.call("slash")
			and rate.call("chop2") < rate.call("slash"), "a hammer hauls back further and drives in further, slower")
	var longest := ""
	for tech: String in pose.technique_steps:
		if longest == "" or strike.call(tech) > strike.call(longest):
			longest = tech
	t.check(longest == "thrust2", "a spear lunges the furthest (%s)" % longest)
	pose.free()
