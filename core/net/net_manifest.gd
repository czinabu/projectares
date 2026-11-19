extends RefCounted
## What a build says over the wire, read off the code itself, so that two
## builds can tell whether they speak the same language without anyone
## keeping a version number by hand.
##
## A manifest is one entry per thing both sides must agree on:
##   - every `@rpc` method of a part's script, by its name, its arguments'
##     types and how it is sent. Adding, removing or changing a message
##     changes the manifest with no other line touched.
##   - every int constant of a part's script whose name starts with
##     `WIRE_`. That is how a system says the *contents* of something it
##     sends changed shape while its name and arguments stayed the same (a
##     new bit in the actor state, a new field packed into the inputs): it
##     keeps a `const WIRE_<WHAT> := n` beside the code that packs it and
##     raises it there. Each lives next to what it describes, so two changes
##     to different systems never touch the same line.
##   - a part whose constants *are* the wire format (the bits of a packed
##     command) names their prefixes once in a `const WIRE_ALSO := [...]`,
##     and every int constant that starts with one is in the manifest too,
##     so a new bit is seen by itself.
##
## `NetSession` sends the manifest's digest when it signs in and the server
## lets in only a game whose digest is its own (`NetSession._server_auth`).
## A game turned away is sent the server's whole manifest, so its log can
## name the messages that differ (`differences`).
##
## Godot numbers a node's RPCs by their sorted names and refuses a node
## whose list differs from the other side's, so two builds with different
## messages cannot share a session whatever is done here; the manifest only
## finds that out at the door, where it can be explained.


## Constants with this prefix are part of the manifest (see above).
const PREFIX := "WIRE_"
## A part's own list of further prefixes (see above).
const ALSO := "WIRE_ALSO"
## The scripts whose messages and `WIRE_` constants make up the manifest. A
## script with `@rpc` methods of its own, or one that packs something the
## other side unpacks, goes here once; after that its own file says the rest.
const PARTS: Array[String] = [
	"res://core/net/net_session.gd",
	"res://core/actor/actor_command.gd",
]

static var _own := {}
static var _own_digest := ""


## This build's manifest: entry name to a number that changes when the
## entry does. Worked out once.
static func own() -> Dictionary:
	if _own.is_empty():
		var scripts: Array[Script] = []
		for path in PARTS:
			scripts.append(load(path) as Script)
		_own = of(scripts)
		_own_digest = digest(_own)
	return _own


## This build's digest: what a game shows at the door.
static func own_digest() -> String:
	own()
	return _own_digest


## The manifest of `scripts` (see the top of the file).
static func of(scripts: Array[Script]) -> Dictionary:
	var manifest := {}
	for script in scripts:
		if script == null:
			continue
		var part := script.resource_path.get_file().get_basename()
		var methods := {}
		for method: Dictionary in script.get_script_method_list():
			methods[str(method.get("name", ""))] = method
		var rpcs: Variant = script.get_rpc_config()
		if rpcs is Dictionary:
			for method: Variant in rpcs:
				manifest["%s.%s" % [part, method]] = _number(
						_how_sent(rpcs[method]) + _arguments(methods.get(str(method), {})))
		var constants := script.get_script_constant_map()
		var prefixes: Array = [PREFIX]
		if constants.get(ALSO) is Array:
			prefixes.append_array(constants[ALSO])
		for constant: String in constants:
			if typeof(constants[constant]) != TYPE_INT:
				continue
			for prefix: Variant in prefixes:
				if constant.begins_with(str(prefix)):
					manifest["%s.%s" % [part, constant]] = int(constants[constant])
					break
	return manifest


## One short string for a whole manifest, the same on every machine.
static func digest(manifest: Dictionary) -> String:
	var names := manifest.keys()
	names.sort()
	var text := ""
	for entry: Variant in names:
		text += "%s=%d\n" % [entry, int(manifest[entry])]
	return text.md5_text()


## The entries two manifests disagree on, sorted, each said the way a log
## wants it: "name (changed)", "name (only here)", "name (only there)".
static func differences(mine: Dictionary, theirs: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for entry: Variant in mine:
		if not theirs.has(entry):
			out.append("%s (only here)" % entry)
		elif int(mine[entry]) != int(theirs[entry]):
			out.append("%s (changed)" % entry)
	for entry: Variant in theirs:
		if not mine.has(entry):
			out.append("%s (only there)" % entry)
	out.sort()
	return out


## A manifest as it arrived from the other side: only short names and
## numbers, and only so many of them.
static func clean(raw: Variant, most := 1024) -> Dictionary:
	var out := {}
	if not raw is Dictionary:
		return out
	for entry: Variant in raw:
		if out.size() >= most:
			break
		var value: Variant = raw[entry]
		if typeof(entry) == TYPE_STRING and typeof(value) == TYPE_INT:
			out[(entry as String).left(96)] = value
	return out


## Which side should update when two builds' manifests differ, from the
## build numbers the release workflow stamps: "mine", "theirs", or "" when
## either build has none (an editor or test run), where nobody can say.
static func older(my_build: int, their_build: int) -> String:
	if my_build <= 0 or their_build <= 0 or my_build == their_build:
		return ""
	return "mine" if my_build < their_build else "theirs"


## How an RPC is sent, as text: every key of its config in a fixed order.
static func _how_sent(config: Variant) -> String:
	if not config is Dictionary:
		return str(config)
	var keys: Array = (config as Dictionary).keys()
	keys.sort()
	var text := ""
	for key: Variant in keys:
		text += "%s:%s," % [key, config[key]]
	return text


## A method's arguments as text: each one's type (never its name, which
## never goes over the wire) and how many may be left out.
static func _arguments(method: Dictionary) -> String:
	var text := "("
	for argument: Dictionary in method.get("args", []):
		text += "%d%s," % [int(argument.get("type", 0)), str(argument.get("class_name", ""))]
	return text + ")%d" % (method.get("default_args", []) as Array).size()


## A number for a piece of text, the same on every machine and build.
static func _number(text: String) -> int:
	return text.md5_text().left(8).hex_to_int()
