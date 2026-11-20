class_name Emotes
extends RefCounted
## The emotes (DESIGN.md "Emotes"): what each is called and how long it
## plays. Picked on the emote key's quick wheel (`PlayerController.open_emote_wheel`), played by
## the controller as the held `ActorCommand.emote` (its number here, counting
## from 1), and posed on the one body by `Locomotion.emote_pose` from
## `ActionPose.emote`, so every view and every machine shows the same one.
## View only: nothing in the simulation reads an emote.

## Every emote, in the order the watch turns through them.
const IDS: Array[String] = ["wave", "salute", "point", "cheer", "sit", "lean", "dance", "taunt"]

## What the watch calls each.
const NAMES := {"wave": "Wave", "salute": "Salute", "point": "Point", "cheer": "Cheer",
	"sit": "Sit down", "lean": "Lean back", "dance": "Dance", "taunt": "Taunt"}

## Seconds an emote plays before it ends on its own; 0 holds it until you
## move (a sit, a lean, a dance).
const SECONDS := {"wave": 2.6, "salute": 2.2, "point": 2.4, "cheer": 2.8,
	"sit": 0.0, "lean": 0.0, "dance": 0.0, "taunt": 2.6}


## The emote's number as `ActorCommand.emote` carries it (0 for none).
static func number_of(id: String) -> int:
	return IDS.find(id) + 1


## The emote with that number, or "" for none (or one this game lacks).
static func id_of(number: int) -> String:
	return IDS[number - 1] if number >= 1 and number <= IDS.size() else ""


static func name_of(id: String) -> String:
	return NAMES.get(id, id.capitalize())


## How long emote `id` plays (0: until you move).
static func seconds_of(id: String) -> float:
	return float(SECONDS.get(id, 0.0))


## Which way slice `i` of the quick emote wheel lies from its middle, on a
## screen (y down): the first at the top, then round clockwise
## (`PlayerController.wheel_slice` reads a pull the same way).
static func slice_dir(i: int) -> Vector2:
	var turn := TAU * float(i) / float(IDS.size())
	return Vector2(sin(turn), -cos(turn))
