extends Node
## Autoload `Look`: the art layer.
##
## Gameplay scripts build plain greybox shapes and know nothing about art. This
## node watches the scene tree and dresses what appears: actors get animated
## models, held weapons get gun models, caches get crates. Maps ask it for
## surfaces, atmosphere and props. On a headless server it does nothing, so
## the simulation never depends on it.
##
## Nothing here names a world. Worlds pick from the generic kits below:
##   - surfaces by kind ("concrete", "asphalt", "metal", ...), see `SURFACES`
##   - skins by name, set with `actor.set_meta("look", "<skin>")`, see `SKINS`
##   - an atmosphere described by a dictionary, see `atmosphere`

const SURFACE_SHADER := preload("res://assets/shaders/surface.gdshader")
const SKY_SHADER := preload("res://assets/shaders/sky.gdshader")
const STORM_COLUMN_SHADER := preload("res://assets/shaders/storm_column.gdshader")
const GEAR_SHADER := preload("res://assets/shaders/gear.gdshader")
const MELEE_SHADER := preload("res://assets/shaders/melee.gdshader")
const ActorSkin := preload("res://core/visual/actor_skin.gd")
const Human := preload("res://core/visual/human.gd")
const CHARACTER_SHADER := preload("res://assets/shaders/character.gdshader")
const EDGE_INK_SHADER := preload("res://assets/shaders/edge_ink.gdshader")
const SKYLINE_SHADER := preload("res://assets/shaders/skyline.gdshader")
const HORIZON_GLOW_SHADER := preload("res://assets/shaders/horizon_glow.gdshader")
const HAZE_BEAM_SHADER := preload("res://assets/shaders/haze_beam.gdshader")
const LAVA_SHADER := preload("res://assets/shaders/lava.gdshader")
const GameSettings := preload("res://core/settings/game_settings.gd")
const Vfx := preload("res://core/visual/vfx.gd")
const GateLook := preload("res://core/visual/gate_look.gd")
const RigModel := preload("res://core/visual/rig_model.gd")
const UiTheme := preload("res://core/visual/ui_theme.gd")
const VEHICLE_SCRIPT := "res://core/vehicle/vehicle.gd"

const TEXTURES := "res://assets/textures/"
const PROPS := "res://assets/props/"
const WEAPONS := "res://assets/weapons/"
const CHARACTERS := "res://assets/characters/"

## Texture sets. `scale` is tiles per meter.
const SURFACES := {
	"concrete": {"tex": "Concrete012", "scale": 0.22},
	"asphalt": {"tex": "Asphalt021", "scale": 0.3},
	"road": {"tex": "Road001", "scale": 0.2},
	"brick": {"tex": "Bricks066", "scale": 0.35},
	"metal": {"tex": "Metal063", "scale": 0.4, "metal": 0.85},
	"panels": {"tex": "MetalPlates015A", "scale": 0.18, "metal": 0.6},
	"ground": {"tex": "Ground037", "scale": 0.25},
}

## Character models. `height` is how tall the model stands in meters.
## `anims` maps what the actor is doing to an animation in the file.
## Walk and run clips are measured from their feet (`feet`, default
## Foot.L and Foot.R) so they play at the speed the actor moves; `run_back`,
## `run_left` and `run_right` are optional (see `locomotion.gd`).
## A skin lists one or more `scenes`; each actor wearing it gets one of them,
## so a squad is not a row of clones. A skin of `people` is built from parts
## instead (see `human.gd`): the actor's chosen appearance if it has one
## (`set_appearance`), otherwise a random mix of the outfits listed, per
## build. `saturation`, `brightness`, `metal` and
## `rough` are optional and tune the character shader: people keep their
## colors, machines are pulled toward worn metal.
## `idle` is a relaxed stand with the hands empty (on people the upright
## stand `build_rig.gd` makes, "Idle_Stand"), `idle_gun` holds a gun low
## and `aim_gun` raises it to shoot from a stand (see `actor_skin.gd`).
## `stand_legs` is where the legs stand while a gun is held low. `fist` is
## the clip whose first frame closes the hands round a grip (`WeaponArm`
## learns its fist from it): the pack's own, whose fingers curl at the
## knuckles. `knock_fall` and `knock_rise` are a knockdown's: thrown onto
## the back, and up again from lying there.
const HUMAN_ANIMS := {"idle": "Idle_Stand", "idle_gun": "Idle_Gun", "aim_gun": "Idle_Gun_Pointing",
	"stand_legs": "Idle_Neutral", "walk": "Walk", "run": "Run", "death": "Death",
	"idle_melee": "Idle_Sword", "attack": "Sword_Slash", "move_gun": "Run_Shoot",
	"run_back": "Run_Back", "run_left": "Run_Left", "run_right": "Run_Right", "roll": "Roll",
	"kick": "Kick_Right", "slide": "Slide_L", "slide_start": "Slide_Start_L",
	"slide_exit": "Slide_Exit_L", "air_legs": "Jump", "fist": "Sword_Idle",
	"knock_fall": "Hit_Knockback", "knock_rise": "LayToIdle"}
const HUMAN_ARM := ["UpperArm.R", "LowerArm.R", "Wrist.R"]
const HUMAN_OFF_ARM := ["UpperArm.L", "LowerArm.L", "Wrist.L"]
const HUMAN_FEET := ["Foot.L", "Foot.R"]
const HUMAN_SPINE := ["Abdomen", "Torso", "Chest"]
## Thigh, shin and foot of the leg that reaches forward in a slide, and of the
## one that folds under.
const HUMAN_LEAD_LEG := ["UpperLeg.L", "LowerLeg.L", "Foot.L"]
const HUMAN_TRAIL_LEG := ["UpperLeg.R", "LowerLeg.R", "Foot.R"]
const SKINS := {
	"raider": {
		"people": {"m": ["Swat", "Spacesuit", "Adventurer"], "f": ["Soldier", "SciFi", "Adventurer"]},
		"height": 1.8, "tint": Color(0.8, 0.82, 0.86), "grip_bone": "Middle1.R", "arm": HUMAN_ARM, "off_arm": HUMAN_OFF_ARM,
		"spine": HUMAN_SPINE, "neck": "Neck", "lead_leg": HUMAN_LEAD_LEG, "trail_leg": HUMAN_TRAIL_LEG,
		"back_bone": "Chest", "hip_bone": "Hips", "feet": HUMAN_FEET,
		"saturation": 0.75, "brightness": 0.85, "metal": 0.0, "rough": 0.85,
		"anims": HUMAN_ANIMS,
	},
	"scavenger": {
		"people": {"m": ["Punk", "Casual_Hoodie", "Casual_2", "Farmer", "Beach"], "f": ["Punk", "Worker", "Casual", "Medieval"]},
		"height": 1.76, "tint": Color(0.86, 0.76, 0.68), "grip_bone": "Middle1.R", "arm": HUMAN_ARM, "off_arm": HUMAN_OFF_ARM,
		"spine": HUMAN_SPINE, "neck": "Neck", "lead_leg": HUMAN_LEAD_LEG, "trail_leg": HUMAN_TRAIL_LEG,
		"back_bone": "Chest", "hip_bone": "Hips", "feet": HUMAN_FEET,
		"saturation": 0.7, "brightness": 0.75, "metal": 0.0, "rough": 0.9,
		"anims": HUMAN_ANIMS,
	},
	# Frostline's station automata (Caleb's call: machines only where the
	# story has machines): a body built in code ("chassis": "android",
	# `ActorSkin._build_android`) round the walking skeleton of the scene,
	# whose own mesh is hidden. Pale ceramic shells over a graphite frame,
	# seams and a visor lit in the body's colour, and the weapon built into
	# the right forearm ("bare": no model held in the hand; a gun's barrel
	# comes up along the aim, `ActorSkin._aim_arm`).
	"sentinel": {
		"scenes": ["Stan.glb"], "height": 2.2, "hide": ["Stan"], "chassis": "android", "bare": true,
		"anims": {"idle": "Idle", "walk": "Walk", "run": "Run", "death": "Death", "attack": "SwordSlash"},
	},
	# Ashfront's Legion riflemen: people in the army's uniform kit.
	"legionary": {
		"people": {"m": ["Swat", "Spacesuit"], "f": ["Soldier", "SciFi"]},
		"height": 1.8, "tint": Color(0.62, 0.68, 0.8), "grip_bone": "Middle1.R", "arm": HUMAN_ARM, "off_arm": HUMAN_OFF_ARM,
		"spine": HUMAN_SPINE, "neck": "Neck", "lead_leg": HUMAN_LEAD_LEG, "trail_leg": HUMAN_TRAIL_LEG,
		"back_bone": "Chest", "hip_bone": "Hips", "feet": HUMAN_FEET,
		"saturation": 0.55, "brightness": 0.78, "metal": 0.0, "rough": 0.85,
		"anims": HUMAN_ANIMS,
	},
	# Ashfront's Tide riflemen: a rougher militia, still dressed for war.
	"tide": {
		"people": {"m": ["Adventurer", "Swat"], "f": ["Adventurer", "Soldier"]},
		"height": 1.78, "tint": Color(0.86, 0.72, 0.6), "grip_bone": "Middle1.R", "arm": HUMAN_ARM, "off_arm": HUMAN_OFF_ARM,
		"spine": HUMAN_SPINE, "neck": "Neck", "lead_leg": HUMAN_LEAD_LEG, "trail_leg": HUMAN_TRAIL_LEG,
		"back_bone": "Chest", "hip_bone": "Hips", "feet": HUMAN_FEET,
		"saturation": 0.6, "brightness": 0.75, "metal": 0.0, "rough": 0.9,
		"anims": HUMAN_ANIMS,
	},
	# Plain fighters with touches of their own ("gear", `ActorSkin._build_gear`),
	# so a marksman or a runner reads apart from the rifleman beside it. A
	# Legion Marksman: the Legion's kit under a hood and mantle.
	"legion_marksman": {
		"people": {"m": ["Swat", "Spacesuit"], "f": ["Soldier", "SciFi"]},
		"height": 1.8, "tint": Color(0.62, 0.68, 0.8), "grip_bone": "Middle1.R", "arm": HUMAN_ARM, "off_arm": HUMAN_OFF_ARM,
		"spine": HUMAN_SPINE, "neck": "Neck", "lead_leg": HUMAN_LEAD_LEG, "trail_leg": HUMAN_TRAIL_LEG,
		"back_bone": "Chest", "hip_bone": "Hips", "feet": HUMAN_FEET,
		"saturation": 0.55, "brightness": 0.78, "metal": 0.0, "rough": 0.85,
		"anims": HUMAN_ANIMS, "gear": "hood",
	},
	# A Tide Runner: the militia's clothes stripped light, a scarf flying.
	"tide_runner": {
		"people": {"m": ["Adventurer", "Punk"], "f": ["Adventurer", "Punk"]},
		"height": 1.76, "tint": Color(0.86, 0.72, 0.6), "grip_bone": "Middle1.R", "arm": HUMAN_ARM, "off_arm": HUMAN_OFF_ARM,
		"spine": HUMAN_SPINE, "neck": "Neck", "lead_leg": HUMAN_LEAD_LEG, "trail_leg": HUMAN_TRAIL_LEG,
		"back_bone": "Chest", "hip_bone": "Hips", "feet": HUMAN_FEET,
		"saturation": 0.6, "brightness": 0.75, "metal": 0.0, "rough": 0.9,
		"anims": HUMAN_ANIMS, "gear": "scarf",
	},
	# The Dune Sea's raiders are desert nomads (Caleb's call): a Sand Raider
	# in light scrap plate sanded to the desert, a wrap, a scarf mask and
	# goggles; a Dune Marksman in a long duster and a hood.
	"sand_raider": {
		"people": {"m": ["Punk", "Casual_Hoodie", "Farmer"], "f": ["Punk", "Worker", "Medieval"]},
		"height": 1.76, "tint": Color(0.88, 0.78, 0.66), "grip_bone": "Middle1.R", "arm": HUMAN_ARM, "off_arm": HUMAN_OFF_ARM,
		"spine": HUMAN_SPINE, "neck": "Neck", "lead_leg": HUMAN_LEAD_LEG, "trail_leg": HUMAN_TRAIL_LEG,
		"back_bone": "Chest", "hip_bone": "Hips", "feet": HUMAN_FEET,
		"saturation": 0.6, "brightness": 0.75, "metal": 0.0, "rough": 0.9,
		"anims": HUMAN_ANIMS, "frame": "light:scrap", "paint": "desert", "gear": "nomad",
	},
	"dune_marksman": {
		"people": {"m": ["Adventurer", "Farmer"], "f": ["Adventurer", "Medieval"]},
		"height": 1.78, "tint": Color(0.88, 0.78, 0.66), "grip_bone": "Middle1.R", "arm": HUMAN_ARM, "off_arm": HUMAN_OFF_ARM,
		"spine": HUMAN_SPINE, "neck": "Neck", "lead_leg": HUMAN_LEAD_LEG, "trail_leg": HUMAN_TRAIL_LEG,
		"back_bone": "Chest", "hip_bone": "Hips", "feet": HUMAN_FEET,
		"saturation": 0.6, "brightness": 0.75, "metal": 0.0, "rough": 0.9,
		"anims": HUMAN_ANIMS, "gear": "duster",
	},
	# Heavies and bosses are people too (Caleb's call): big fighters in
	# full plate, each army's or world's own. A skin's own armor ("frame")
	# names its weight and, after a colon, the frame look it is built in
	# (`ActorSkin.FRAME_STYLES`), worn in the armor paint "paint"; its own
	# helmet ("helmet") takes the plates' colours. The Legion Vanguard:
	# gunmetal plate in the Legion's cobalt under a Warden helm.
	"vanguard": {
		"people": {"m": ["Swat"], "f": ["Soldier"]},
		"height": 1.95, "tint": Color(0.62, 0.68, 0.8), "grip_bone": "Middle1.R", "arm": HUMAN_ARM, "off_arm": HUMAN_OFF_ARM,
		"spine": HUMAN_SPINE, "neck": "Neck", "lead_leg": HUMAN_LEAD_LEG, "trail_leg": HUMAN_TRAIL_LEG,
		"back_bone": "Chest", "hip_bone": "Hips", "feet": HUMAN_FEET,
		"saturation": 0.55, "brightness": 0.78, "metal": 0.0, "rough": 0.85,
		"anims": HUMAN_ANIMS, "frame": "heavy:bulwark", "paint": "cobalt", "helmet": "threat",
	},
	# The Tide Brute: a militia bruiser in rusted scrap plate and a
	# riveted bucket helm.
	"tide_brute": {
		"people": {"m": ["Punk", "Adventurer"], "f": ["Punk", "Medieval"]},
		"height": 1.95, "tint": Color(0.86, 0.72, 0.6), "grip_bone": "Middle1.R", "arm": HUMAN_ARM, "off_arm": HUMAN_OFF_ARM,
		"spine": HUMAN_SPINE, "neck": "Neck", "lead_leg": HUMAN_LEAD_LEG, "trail_leg": HUMAN_TRAIL_LEG,
		"back_bone": "Chest", "hip_bone": "Hips", "feet": HUMAN_FEET,
		"saturation": 0.6, "brightness": 0.75, "metal": 0.0, "rough": 0.9,
		"anims": HUMAN_ANIMS, "frame": "heavy:scrap", "paint": "crimson", "helmet": "scrap",
	},
	# The Dune Sea's Scrap Brute: scrap plate sanded to the desert's colour.
	"scrap_brute": {
		"people": {"m": ["Farmer", "Punk"], "f": ["Worker", "Punk"]},
		"height": 1.95, "tint": Color(0.88, 0.78, 0.66), "grip_bone": "Middle1.R", "arm": HUMAN_ARM, "off_arm": HUMAN_OFF_ARM,
		"spine": HUMAN_SPINE, "neck": "Neck", "lead_leg": HUMAN_LEAD_LEG, "trail_leg": HUMAN_TRAIL_LEG,
		"back_bone": "Chest", "hip_bone": "Hips", "feet": HUMAN_FEET,
		"saturation": 0.65, "brightness": 0.78, "metal": 0.0, "rough": 0.9,
		"anims": HUMAN_ANIMS, "frame": "heavy:scrap", "paint": "desert", "helmet": "scrap",
	},
	# The Basalt Rift's Slag Brute: heavy plate that runs hot (lit vents),
	# blackened by the lava, under a ceramic Ember helm.
	"slag_brute": {
		"people": {"m": ["Punk", "Adventurer"], "f": ["Punk", "Medieval"]},
		"height": 1.95, "tint": Color(0.84, 0.74, 0.68), "grip_bone": "Middle1.R", "arm": HUMAN_ARM, "off_arm": HUMAN_OFF_ARM,
		"spine": HUMAN_SPINE, "neck": "Neck", "lead_leg": HUMAN_LEAD_LEG, "trail_leg": HUMAN_TRAIL_LEG,
		"back_bone": "Chest", "hip_bone": "Hips", "feet": HUMAN_FEET,
		"saturation": 0.6, "brightness": 0.72, "metal": 0.0, "rough": 0.9,
		"anims": HUMAN_ANIMS, "frame": "heavy:bulwark", "paint": "ashen", "helmet": "thermal",
	},
	# The Basalt Rift's cult of the Crown: the Lord of the Crown's own, in
	# the Crown's crimson. A Crown Zealot: light plate and a ceramic Ember
	# helm, quick and close.
	"zealot": {
		"people": {"m": ["Punk", "Adventurer", "Casual_Hoodie"], "f": ["Punk", "Medieval", "Worker"]},
		"height": 1.8, "tint": Color(0.84, 0.74, 0.68), "grip_bone": "Middle1.R", "arm": HUMAN_ARM, "off_arm": HUMAN_OFF_ARM,
		"spine": HUMAN_SPINE, "neck": "Neck", "lead_leg": HUMAN_LEAD_LEG, "trail_leg": HUMAN_TRAIL_LEG,
		"back_bone": "Chest", "hip_bone": "Hips", "feet": HUMAN_FEET,
		"saturation": 0.6, "brightness": 0.75, "metal": 0.0, "rough": 0.9,
		"anims": HUMAN_ANIMS, "frame": "light:scrap", "paint": "crimson", "helmet": "thermal",
	},
	# A Crown Sharpshooter: the cult's long rifles in quilted heat-plate,
	# soot-grey, bare-headed to sight down the barrel.
	"sharpshooter": {
		"people": {"m": ["Swat", "Adventurer"], "f": ["Soldier", "Adventurer"]},
		"height": 1.8, "tint": Color(0.84, 0.74, 0.68), "grip_bone": "Middle1.R", "arm": HUMAN_ARM, "off_arm": HUMAN_OFF_ARM,
		"spine": HUMAN_SPINE, "neck": "Neck", "lead_leg": HUMAN_LEAD_LEG, "trail_leg": HUMAN_TRAIL_LEG,
		"back_bone": "Chest", "hip_bone": "Hips", "feet": HUMAN_FEET,
		"saturation": 0.6, "brightness": 0.75, "metal": 0.0, "rough": 0.9,
		"anims": HUMAN_ANIMS, "frame": "medium:thermal", "paint": "ashen",
	},
	# The Dune Sea's Salvage Runner: light runner's plate sanded to the
	# desert's colour, bare-headed, a knife in hand.
	"salvage_runner": {
		"people": {"m": ["Punk", "Casual_2", "Beach"], "f": ["Punk", "Casual", "Worker"]},
		"height": 1.76, "tint": Color(0.88, 0.78, 0.66), "grip_bone": "Middle1.R", "arm": HUMAN_ARM, "off_arm": HUMAN_OFF_ARM,
		"spine": HUMAN_SPINE, "neck": "Neck", "lead_leg": HUMAN_LEAD_LEG, "trail_leg": HUMAN_TRAIL_LEG,
		"back_bone": "Chest", "hip_bone": "Hips", "feet": HUMAN_FEET,
		"saturation": 0.65, "brightness": 0.78, "metal": 0.0, "rough": 0.9,
		"anims": HUMAN_ANIMS, "frame": "light:runner", "paint": "desert",
	},
	# Bosses: a body of their own, not a heavy with more health. Each is the
	# tallest person on the field in full plate, with "regalia" built in
	# code (`ActorSkin._build_regalia`). Ashfront's Warlord: black and gold
	# plate, a long cloak and a banner on its back in its army's colour.
	"warlord": {
		"people": {"m": ["King"], "f": ["Medieval"]},
		"height": 2.05, "tint": Color(0.82, 0.8, 0.78), "grip_bone": "Middle1.R", "arm": HUMAN_ARM, "off_arm": HUMAN_OFF_ARM,
		"spine": HUMAN_SPINE, "neck": "Neck", "lead_leg": HUMAN_LEAD_LEG, "trail_leg": HUMAN_TRAIL_LEG,
		"back_bone": "Chest", "hip_bone": "Hips", "feet": HUMAN_FEET,
		"saturation": 0.6, "brightness": 0.78, "metal": 0.0, "rough": 0.85,
		"anims": HUMAN_ANIMS, "frame": "heavy:bulwark", "paint": "warlord", "helmet": "threat", "regalia": "warlord",
	},
	# The Dune Sea's Wreck Baron: hazard-striped scrap plate, a sand-torn
	# cloak and exhaust stacks off a salvaged engine block on its back.
	"baron": {
		"people": {"m": ["Punk"], "f": ["Punk"]},
		"height": 2.05, "tint": Color(0.88, 0.78, 0.66), "grip_bone": "Middle1.R", "arm": HUMAN_ARM, "off_arm": HUMAN_OFF_ARM,
		"spine": HUMAN_SPINE, "neck": "Neck", "lead_leg": HUMAN_LEAD_LEG, "trail_leg": HUMAN_TRAIL_LEG,
		"back_bone": "Chest", "hip_bone": "Hips", "feet": HUMAN_FEET,
		"saturation": 0.65, "brightness": 0.78, "metal": 0.0, "rough": 0.9,
		"anims": HUMAN_ANIMS, "frame": "heavy:scrap", "paint": "hazard", "helmet": "scrap", "regalia": "baron",
	},
	# The Basalt Rift's Lord of the Crown: crimson plate that runs hot, a
	# crown of basalt spikes lit with lava, and a cloak with a burning hem.
	"crown_lord": {
		"people": {"m": ["King"], "f": ["Medieval"]},
		"height": 2.05, "tint": Color(0.84, 0.74, 0.68), "grip_bone": "Middle1.R", "arm": HUMAN_ARM, "off_arm": HUMAN_OFF_ARM,
		"spine": HUMAN_SPINE, "neck": "Neck", "lead_leg": HUMAN_LEAD_LEG, "trail_leg": HUMAN_TRAIL_LEG,
		"back_bone": "Chest", "hip_bone": "Hips", "feet": HUMAN_FEET,
		"saturation": 0.6, "brightness": 0.72, "metal": 0.0, "rough": 0.9,
		"anims": HUMAN_ANIMS, "frame": "heavy:bulwark", "paint": "crimson", "helmet": "thermal", "regalia": "crown",
	},
	# An exo trooper: an ordinary soldier strapped into a mechanical
	# exoskeleton. The person stays person-sized; the bulk is the suit
	# ("suit": `ActorSkin._build_exo_suit`: struts down the outside of each
	# limb, joints, actuators, a spine and shoulder yoke with a roll cage
	# over the head, a power pack), plus a chest rig ("frame") and a closed
	# helmet with a visor slit ("helmet") lit in the army's colour.
	"exo": {
		"people": {"m": ["Swat"], "f": ["Soldier"]},
		"height": 1.8, "tint": Color(0.5, 0.52, 0.55), "grip_bone": "Middle1.R", "arm": HUMAN_ARM, "off_arm": HUMAN_OFF_ARM,
		"spine": HUMAN_SPINE, "neck": "Neck", "lead_leg": HUMAN_LEAD_LEG, "trail_leg": HUMAN_TRAIL_LEG,
		"back_bone": "Chest", "hip_bone": "Hips", "feet": HUMAN_FEET,
		"saturation": 0.45, "brightness": 0.72, "metal": 0.0, "rough": 0.8,
		"anims": HUMAN_ANIMS, "frame": "light", "helmet": "slit", "suit": true,
	},
	# The Kiln Walker: a war machine of its own, built in code
	# ("chassis": `ActorSkin._build_walker`: a low, wide hull with the cannon
	# in its glacis and the heat vent, the weak spot, in its rear armor, on
	# two heavy legs) round the scene's walking skeleton, whose own mesh is
	# hidden ("hide"). Its cannon draws a tracking beam while it aims ("beam").
	"walker": {
		"scenes": ["Leela.glb"], "height": 2.75, "hide": ["Leela"],
		"chassis": "walker", "beam": true,
		"anims": {"idle": "Idle", "walk": "Walk", "run": "Run", "death": "Death", "attack": "Shoot"},
	},
	# A colossus: the automaton built nearly four metres tall, a heavy guard
	# machine ("heavy_chassis": broader shells, a reactor on its back and a
	# missile pod on the left shoulder, a lance for a forearm). Its weapon
	# draws a tracking beam while it aims ("beam", in "beam_color").
	"colossus": {
		"scenes": ["Stan.glb"], "height": 3.9, "hide": ["Stan"], "chassis": "android", "heavy_chassis": true,
		"bare": true, "beam": true, "beam_color": Color(0.25, 0.95, 0.9),
		"anims": {"idle": "Idle", "walk": "Walk", "run": "Run", "death": "Death", "attack": "Punch"},
	},
	# A core colossus: the same machine as the deepest guard, in dark plate,
	# its core bared in a cage of ribs on its chest, a crown of lit vents
	# behind its head, horns and a third layer of shoulder plate
	# ("core_chassis", `ActorSkin._build_android`).
	"core_colossus": {
		"scenes": ["Stan.glb"], "height": 3.9, "hide": ["Stan"], "chassis": "android", "heavy_chassis": true,
		"core_chassis": true, "bare": true, "beam": true, "beam_color": Color(0.35, 0.8, 1.0),
		"anims": {"idle": "Idle", "walk": "Walk", "run": "Run", "death": "Death", "attack": "Punch"},
	},
	# Wildlife (DESIGN.md "Spore Marsh"): beasts of their own, built in code
	# like the walker ("creature": `ActorSkin._build_creature`) round the
	# scene's walking skeleton, whose mesh is hidden. They carry no weapon
	# you can see ("bare": the claws and the bash are the body's own).
	# A marsh stalker: a lean, low raptor with a long jaw, hooked foreclaws,
	# a spined back and a long tail, its eyes lit.
	"marsh_stalker": {
		"scenes": ["Leela.glb"], "height": 1.6, "hide": ["Leela"], "creature": "stalker", "bare": true,
		"anims": {"idle": "Idle", "walk": "Walk", "run": "Run", "death": "Death", "attack": "Punch"},
	},
	# A shellback: a broad, low grazer under a plated dome, its soft rear
	# (the weak spot) a pale, glowing hide between the shell's back plates.
	"shellback": {
		"scenes": ["Leela.glb"], "height": 1.6, "hide": ["Leela"], "creature": "shellback", "bare": true,
		"anims": {"idle": "Idle", "walk": "Walk", "run": "Run", "death": "Death", "attack": "Punch"},
	},
	# A lurker: a long, flat ambusher with a lit lure over its snout, which
	# lies under the black water ("lurks": how far the body sinks while it
	# lies low, `ActorSkin._update_lurk`).
	"lurker": {
		"scenes": ["Leela.glb"], "height": 1.4, "hide": ["Leela"], "creature": "lurker", "bare": true, "lurks": 0.75,
		"anims": {"idle": "Idle", "walk": "Walk", "run": "Run", "death": "Death", "attack": "Punch"},
	},
	# A brood keeper: a hunched giant of the stalkers' kind with its egg
	# sacs lit on its back, and the broodlings it spills, little stalkers.
	"brood_keeper": {
		"scenes": ["Leela.glb"], "height": 2.4, "hide": ["Leela"], "creature": "keeper", "bare": true,
		"anims": {"idle": "Idle", "walk": "Walk", "run": "Run", "death": "Death", "attack": "Punch"},
	},
	# A brood mother: a brood keeper grown old and huge, dragging a swollen
	# abdomen of lit eggs, roots grown out of her back.
	"brood_mother": {
		"scenes": ["Leela.glb"], "height": 3.4, "hide": ["Leela"], "creature": "brood_mother", "bare": true,
		"anims": {"idle": "Idle", "walk": "Walk", "run": "Run", "death": "Death", "attack": "Punch"},
	},
	# A shellback elder: a shellback grown huge and old, a ram of horn on
	# its brow, great horns, a garden of fungus on its back.
	"shellback_elder": {
		"scenes": ["Leela.glb"], "height": 3.2, "hide": ["Leela"], "creature": "elder", "bare": true,
		"anims": {"idle": "Idle", "walk": "Walk", "run": "Run", "death": "Death", "attack": "Punch"},
	},
	# A drowned lurker: a lurker grown huge in the deep, crowned with lures,
	# weed-bearded, roots stuck through its back. It lies right under
	# ("lurks" its whole height) until it rises.
	"drowned_lurker": {
		"scenes": ["Leela.glb"], "height": 2.6, "hide": ["Leela"], "creature": "drowned", "bare": true, "lurks": 3.0,
		"anims": {"idle": "Idle", "walk": "Walk", "run": "Run", "death": "Death", "attack": "Punch"},
	},
	"broodling": {
		"scenes": ["Leela.glb"], "height": 0.9, "hide": ["Leela"], "creature": "broodling", "bare": true,
		"anims": {"idle": "Idle", "walk": "Walk", "run": "Run", "death": "Death", "attack": "Punch"},
	},
	# Frostline's Feral Stalker: a lean pack beast of the ice, built like a
	# marsh stalker but furred against the cold, a mane of frost-lit ice
	# spines down its back and hooked foreclaws for its blades.
	"feral": {
		"scenes": ["Leela.glb"], "height": 1.6, "hide": ["Leela"], "creature": "feral", "bare": true,
		"anims": {"idle": "Idle", "walk": "Walk", "run": "Run", "death": "Death", "attack": "Punch"},
	},
	# The Basalt Rift's lava beasts, kept by the Crown's cult: lit by the
	# lava ("creature" kinds of the planet's heat, `ActorSkin.LAVA_GLOW`).
	# A Cinder Hound: the stalker's lean body under basalt plates, lava
	# showing in the cracks between them, a jaw that glows inside.
	"cinder_hound": {
		"scenes": ["Leela.glb"], "height": 1.6, "hide": ["Leela"], "creature": "hound", "bare": true,
		"anims": {"idle": "Idle", "walk": "Walk", "run": "Run", "death": "Death", "attack": "Punch"},
	},
	# A Magma Crawler: a shellback's build under a dome of cooling basalt,
	# lava running in its seams and dripping from its belly, a soft rear
	# that glows white-hot.
	"magma_crawler": {
		"scenes": ["Leela.glb"], "height": 1.6, "hide": ["Leela"], "creature": "crawler", "bare": true,
		"anims": {"idle": "Idle", "walk": "Walk", "run": "Run", "death": "Death", "attack": "Punch"},
	},
	# The Dune Sea's Dune Burrower: a lurker's long, flat body in a sand
	# hide, no lure, a ridge of digging spades down its back and a shovel
	# snout; it lies under the sand ("lurks") until it comes up.
	"dune_burrower": {
		"scenes": ["Leela.glb"], "height": 1.4, "hide": ["Leela"], "creature": "burrower", "bare": true, "lurks": 0.9,
		"anims": {"idle": "Idle", "walk": "Walk", "run": "Run", "death": "Death", "attack": "Punch"},
	},
	# A bloater: a swollen sac of spores on stubby legs, studded with lit
	# pustules and trailing tendrils.
	"bloater": {
		"scenes": ["Leela.glb"], "height": 2.1, "hide": ["Leela"], "creature": "bloater", "bare": true,
		"anims": {"idle": "Idle", "walk": "Walk", "run": "Run", "death": "Death", "attack": "Punch"},
	},
	# A machine's weak spot riding on it (an airship's engine pod, say): the
	# machine's own model is its body, so nothing of the bot shows, nor
	# its weapon.
	"ship_part": {
		"scenes": ["Leela.glb"], "height": 1.8, "hide": ["Leela"], "bare": true,
		"anims": {"idle": "Idle", "walk": "Walk", "run": "Run", "death": "Death", "attack": "Punch"},
	},
}
const DEFAULT_SKIN := "raider"

## Gun models picked by item tag, first match wins. Tags, never ids. An
## optional third value is the length in meters (default `GUN_LENGTH`).
const GUN_MODELS := [
	["hand_cannon", "Pistol_1.glb", 0.32],
	["machine_pistol", "SMG_2.glb", 0.34],
	["sidearm", "Pistol_1.glb", 0.24],
	["smg", "SMG_1.glb"],
	["marksman", "Sniper_2.glb"],
	["shotgun", "AR_6.glb"],
	["starter", "AR_5.glb"],
	["rifle", "AR_2.glb"],
]
const DEFAULT_GUN := "AR_3.glb"
## Where attachments sit on each gun model. The optic sits on top of the gun
## and the muzzle device on the end of the barrel, both found from the mesh;
## this gives how far along the gun the optic goes (0 at the stock, 1 at the
## muzzle), and the grip and magazine mounts as [along, up from the bottom].
const GUN_MOUNTS := {
	"AR_5.glb": {"optic": 0.55, "grip": [0.82, 0.32], "magazine": [0.36, 0.3]},
	"AR_2.glb": {"optic": 0.5, "grip": [0.82, 0.62], "magazine": [0.6, 0.5]},
	"SMG_1.glb": {"optic": 0.62, "grip": [0.66, 0.62], "magazine": [0.84, 0.55]},
	"Sniper_2.glb": {"optic": 0.5, "grip": [0.72, 0.4], "magazine": [0.45, 0.32]},
	"AR_6.glb": {"optic": 0.45, "grip": [0.8, 0.35], "magazine": [0.4, 0.3]},
	"AR_3.glb": {"optic": 0.5, "grip": [0.8, 0.5], "magazine": [0.55, 0.45]},
}
## Energy colour for a gun's glowing parts, picked by item tag, first match
## wins. The warm (wood and leather) parts of the pack's models become glowing
## cells and coils in this colour, and a glowing emitter ring sits on the muzzle.
const GUN_GLOW := [
	["hand_cannon", Color(0.8, 0.35, 1.0)],
	["machine_pistol", Color(1.0, 0.55, 0.15)],
	["sidearm", Color(0.3, 0.85, 1.0)],
	# Primaries, matching the cyan lit details on their attachments.
	["smg", Color(1.0, 0.55, 0.15)],
	["marksman", Color(0.8, 0.35, 1.0)],
	["shotgun", Color(1.0, 0.3, 0.25)],
	["rifle", Color(0.25, 0.9, 1.0)],
]
## Melee models picked by item tag, first match wins: file, length in meters,
## how far up from the pommel the hand grips it, and how it folds away when holstered (see `set_extend`): "blade" draws the
## blade into the hilt, "telescope" slides the shaft into itself, "" keeps
## its shape, and how it is held ready in one hand (a key of
## `ActionPose.ready_holds`; two-handed weapons are carried instead), and
## the way its striking face (an axe's bit, a hammer's face, a blade's edge)
## points in the pack model's own space, across its length. No file means
## the model is built in code (see `_spear_model`). The model is turned so
## that face points along `STRIKE_FACE`, the way every technique leads with
## (`ActionPose.cut_edge`); a pack model may face any way across, so the
## face is read from the model, never assumed (assuming it held the axe and
## hammer sideways through their swings). `melee_orientation_tests.gd`
## checks each face against the model's shape.
const MELEE_MODELS := [
	["hammer", "Hammer.glb", 1.15, 0.3, "", "upright", Vector3(1, 0, 0)],
	["knife", "Knife.glb", 0.5, 0.1, "blade", "knife", Vector3(-1, 0, 0)],
	["axe", "Axe.glb", 0.85, 0.12, "", "upright", Vector3(-1, 0, 0)],
	["spear", "", 2.1, 0.75, "telescope", "upright", Vector3(1, 0, 0)],
	["starter", "Sword.glb", 0.7, 0.085, "blade", "upright", Vector3(1, 0, 0)],
	["hookblade", "Sword.glb", 0.9, 0.1, "blade", "upright", Vector3(1, 0, 0)],
	["blade", "Katana.glb", 1.2, 0.14, "blade", "katana", Vector3(0, 0, 1)],
]
const DEFAULT_MELEE := ["", "Sword.glb", 1.15, 0.13, "blade", "upright", Vector3(1, 0, 0)]
## Which way a melee model's striking face points once it is built (its
## holder's space; the length runs along +Y).
const STRIKE_FACE := Vector3(0, 0, -1)
const GUN_LENGTH := 0.72

## False on a headless server: nothing is dressed and no art is loaded.
var enabled := DisplayServer.get_name() != "headless"

## Storm readability. A hot war may close the horizon in; it must not turn
## the fight into a brown wall. Depth fog (a mood that sets `fog_depth_end`)
## cannot start closer than `storm_fog_begin_min` and cannot be solid closer
## than `storm_fog_solid_min`. Godot multiplies that 0–1 curve by
## `fog_density`, which `storm_depth_amount_cap` keeps under a full wipe.
## An exponential war mood, which hazes every distance at once, is capped
## at `storm_fog_density_cap`. Height fog stays a layer on the ground.
## Distances are meters. Tuned in DESIGN.md, "The war's storm".
var storm_follow := 0.22
var storm_fog_begin_min := 28.0
var storm_fog_solid_min := 110.0
var storm_depth_amount_cap := 0.9
var storm_fog_density_cap := 0.0055
var storm_fog_height_max := 1.6
var storm_height_density_cap := 0.2
## Actors keep `actor_fog_min` of the fog inside `actor_fog_clear`, and the
## world's full fog by `actor_fog_full`. A near fight stays readable and a
## far figure still disappears, so this is not a wallhack. The faction rim
## is strongest between those two distances.
var actor_fog_clear := 16.0
var actor_fog_full := 72.0
var actor_fog_min := 0.2
var actor_rim_strength := 0.75
## Smoke over a fight fades out this close to the camera. The cards are
## `column_card` metres across; there are `column_particles` of them.
var column_clear_near := 14.0
var column_clear_far := 36.0
var column_particles := 80
var column_card := 12.0
var column_glow := 1.8

var _storm_globals_ready := false
## A storm crossing the map (DESIGN.md "Weather: ash storms") lowers those
## floors while the camera is in it, by `weather_cover` (0 clear air, 1 the
## thick of it): at the heart depth fog may start at `weather_fog_begin_min`
## and be solid by `weather_fog_solid_min`, about 70 m gone (Caleb's pick).
## The map's storm mood eases in at `weather_follow` a second.
var weather_fog_begin_min := 4.0
var weather_fog_solid_min := 50.0
var weather_depth_amount_cap := 0.985
var weather_follow := 0.35
var weather_cover := 0.0
## How far into close air the view is (a planet's `close` mood, the map's
## "close_here" meta), 0 to 1: like `weather_cover` it brings the depth fog's
## floor down, so a forest can shut the view in (Caleb's call: close
## quarters read smoky).
var close_cover := 0.0
var close_follow := 0.5
## The far skyline's haze (`skyline_haze`): how much it wears at a far fog
## of `skyline_haze_from` or less, rising to all of it at `skyline_haze_gone`.
var skyline_haze_clear := 0.42
var skyline_haze_from := 0.66
var skyline_haze_gone := 0.98

var _materials := {}
var _noise: NoiseTexture2D
var _gear_materials := {}
## Mesh surface and placement -> how far up the model it runs (`_surface_span`).
var _spans := {}
## A foldable melee material's id -> a weak reference to its folded copy
## (see `set_extend`, `_folded_copy`). Weak, so a storm-lit copy made for
## one soldier (`_pop_storm`) goes when the soldier does.
var _folded := {}
var _prop_sizes := {}
## Gun model file -> attachment slot -> mount point (see `mount_attachments`).
var _gun_mounts := {}
## Map props are drawn out to this many metres for each metre of their size
## (`_limit_draw_distance`), never nearer than `draw_distance_min`; one that
## would reach `draw_distance_cap` is drawn as far as the camera sees.
var draw_distance_per_metre := 70.0
var draw_distance_min := 40.0
var draw_distance_cap := 380.0
## Map props smaller than this (metres, their longest side) cast no sun
## shadow (`_limit_draw_distance`).
var shadow_min_size := 0.6
## Iron sights (`_iron_sights`) are drawn out to this many metres: further
## the widest of them is about two pixels at 1080p, so on someone else's gun
## they are not drawn at all (your own are always within reach).
var iron_sight_reach := 15.0


func _ready() -> void:
	_add_storm_globals()
	get_tree().node_added.connect(_on_node_added)
	if enabled:
		UiTheme.apply()


## A dark backdrop with a warm glow low in the frame, for menu screens.
func backdrop() -> Texture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.2, 0.11, 0.06))
	gradient.set_color(1, Color(0.035, 0.035, 0.04))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 1.05)
	texture.fill_to = Vector2(0.5, 0.0)
	texture.width = 256
	texture.height = 256
	return texture


func _on_node_added(node: Node) -> void:
	if not enabled:
		return
	var dress := Callable()
	if node.has_meta("display_item"):
		dress = _dress_display
	elif node is Actor:
		dress = _dress_actor
	elif node is LootContainer:
		dress = _dress_cache
	elif node is SalvageCrate:
		dress = _dress_salvage_crate
	elif node is Depot:
		dress = _dress_depot
	elif node is CharacterBody3D and node.get_script() != null \
			and node.get_script().resource_path == VEHICLE_SCRIPT:
		dress = _dress_vehicle
	elif node.name == "Map" and node.get_parent() is Raid:
		dress = _limit_draw_distance
	if dress.is_valid():
		_dress_when_ready.call_deferred(dress, node.get_instance_id())


## Dresses a node once the frame it entered is done, if it is still there:
## one freed in that frame cannot be handed to a typed argument.
func _dress_when_ready(dress: Callable, id: int) -> void:
	var node := instance_from_id(id)
	if node != null:
		dress.call(node)


## Map props are drawn only as far as their size lets anyone make them
## out: each mesh fades out at `draw_distance_per_metre` times its size, so
## a crate goes long before a building does. Big open maps draw hundreds of
## small props (and their shadows) otherwise. A mesh (or a multimesh) that
## already has a visibility range keeps it as its own. Either is then
## scaled by the View distance setting (`fit_draw_distance`), so each mesh
## keeps what it was made with in `DRAW_BASE`: 0 for one drawn as far as
## the camera sees.
func _limit_draw_distance(map: Node3D) -> void:
	if not is_instance_valid(map):
		return
	for node in map.find_children("*", "GeometryInstance3D", true, false):
		var shape := node as GeometryInstance3D
		if not (shape is MeshInstance3D or shape is MultiMeshInstance3D) or shape.has_meta(DRAW_BASE):
			continue
		var base := shape.visibility_range_end
		if base <= 0.0:
			var mesh := shape as MeshInstance3D
			if mesh == null or mesh.mesh == null:
				continue
			var size := (mesh.global_transform * mesh.get_aabb()).size
			# A prop smaller than `shadow_min_size` casts no sun shadow: a
			# pebble's shadow is a few pixels, but it is drawn again in every
			# shadow split (on Ashfront the sun's shadows were nine draws in
			# ten).
			if maxf(size.x, maxf(size.y, size.z)) < shadow_min_size \
					and mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON:
				mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var reach := maxf(size.x, maxf(size.y, size.z)) * draw_distance_per_metre
			base = maxf(reach, draw_distance_min) if reach < draw_distance_cap else 0.0
		shape.set_meta(DRAW_BASE, base)
	map.add_to_group(GameSettings.DRAWN_MAP_GROUP)
	fit_draw_distance(map)


## The meta `_limit_draw_distance` keeps a mesh's own draw distance in.
const DRAW_BASE := "draw_base"


## Fits a dressed map's draw distances to the View distance setting
## (`GameSettings.detail_reach`, `big_reach`).
func fit_draw_distance(map: Node3D) -> void:
	if not is_instance_valid(map):
		return
	var detail := GameSettings.detail_reach()
	var big := GameSettings.big_reach()
	for node in map.find_children("*", "GeometryInstance3D", true, false):
		var shape := node as GeometryInstance3D
		if not shape.has_meta(DRAW_BASE):
			continue
		var base: float = shape.get_meta(DRAW_BASE)
		var end := base * detail if base > 0.0 else big
		if big > 0.0:
			end = minf(end, big)
		shape.visibility_range_end = end
		shape.visibility_range_end_margin = end * 0.15
		if end > 0.0:
			shape.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF


## Merges the plain pieces standing right under `root` (a model built from
## boxes and shells that never move apart: a helmet, armor plates, a cooling
## pack, iron sights) into one mesh per material, so a model of thirty
## pieces costs a handful of draws in every pass, shadows included, and
## looks exactly the same. Only a piece with no children, no skin, no
## override or overlay, default layers and nothing faded or hidden is
## taken; anything else, and any node under a child that is not a piece
## (a cannon that turns), is left as it is. Pieces that differ in shadow
## casting or vertex format never share a mesh. With `keep_named`, a piece
## given a name of its own (a vehicle's "Thruster1", found by name and
## moved) is left out too. With `alike`, pieces whose plain materials
## (`StandardMaterial3D`) are set the same share a mesh even when each was
## given its own copy (a gun attachment's parts, `Gun.build_attachment`).
## With `lods`, a merged mesh of more than `LOD_FROM` triangles is given
## levels of detail (`_with_lods`), for a big model seen from far off (a
## vehicle). View only.
static func merge_pieces(root: Node3D, keep_named := false, alike := false, lods := false) -> void:
	if root == null:
		return
	var groups := {}
	var order: Array[String] = []
	for child in root.get_children():
		var piece := child as MeshInstance3D
		if piece == null or not _mergeable(piece):
			continue
		if keep_named and not str(piece.name).begins_with("@"):
			continue
		var mat := _piece_material(piece)
		var layout := _layout(piece.mesh.surface_get_arrays(0))
		if mat == null or layout == "":
			continue
		var key := "%s:%d:%s" % [_material_key(mat) if alike else str(mat.get_instance_id()), piece.cast_shadow, layout]
		if not groups.has(key):
			groups[key] = []
			order.append(key)
		(groups[key] as Array).append(piece)
	for key in order:
		var pieces: Array = groups[key]
		if pieces.size() < 2:
			continue
		var first: MeshInstance3D = pieces[0]
		var mesh := _merged_mesh(pieces, _piece_material(first))
		if mesh == null:
			continue
		if lods:
			mesh = _with_lods(mesh)
		var merged := MeshInstance3D.new()
		merged.name = "Merged%d" % order.find(key)
		merged.mesh = mesh
		merged.cast_shadow = first.cast_shadow
		root.add_child(merged)
		for piece: MeshInstance3D in pieces:
			root.remove_child(piece)
			piece.free()


## Skinned parts on one skeleton merged into one surface with one skin, for
## a body's shadow (`ActorSkin._update_shadow_body`): [mesh, skin, the parts
## used], or [] when fewer than two surfaces would be saved. Only positions,
## normals, bones and weights are kept: a shadow needs nothing else. Made
## once for each set of part meshes and shared by every body wearing them.
var _shadow_bodies := {}


func shadow_body(parts: Array[MeshInstance3D]) -> Array:
	var used: Array[MeshInstance3D] = []
	var surfaces := 0
	for part in parts:
		if part.skin != null and part.transform.is_equal_approx(parts[0].transform):
			used.append(part)
			surfaces += part.mesh.get_surface_count()
	if surfaces < 2:
		return []
	var skeleton := used[0].get_node_or_null(used[0].skeleton) as Skeleton3D
	if skeleton == null:
		return []
	var key := []
	for part in used:
		key.append_array([part.mesh.get_rid().get_id(), part.skin.get_instance_id()])
	key.append(skeleton.get_bone_count())
	var cached: Variant = _shadow_bodies.get(hash(key))
	if cached != null:
		return [cached[0], cached[1], used]
	var skin := Skin.new()
	var binds := {}
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	var indices := PackedInt32Array()
	var eight := false
	for part in used:
		for i in part.mesh.get_surface_count():
			if part.mesh.surface_get_format(i) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS:
				eight = true
	var per := 8 if eight else 4
	for part in used:
		var own := part.skin
		var remap := PackedInt32Array()
		for b in own.get_bind_count():
			var bind_name := own.get_bind_name(b)
			var bone := own.get_bind_bone(b)
			var pose := own.get_bind_pose(b)
			var bind_key := "%s|%d|%s" % [bind_name, bone, pose]
			if not binds.has(bind_key):
				binds[bind_key] = skin.get_bind_count()
				if bind_name != &"":
					skin.add_named_bind(bind_name, pose)
				else:
					skin.add_bind(bone, pose)
			remap.append(binds[bind_key])
		for i in part.mesh.get_surface_count():
			var arrays := part.mesh.surface_get_arrays(i)
			var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			if arrays[Mesh.ARRAY_BONES] == null or arrays[Mesh.ARRAY_WEIGHTS] == null or points.is_empty():
				continue
			var base := verts.size()
			verts.append_array(points)
			if arrays[Mesh.ARRAY_NORMAL] != null:
				normals.append_array(arrays[Mesh.ARRAY_NORMAL])
			else:
				normals.resize(verts.size())
			var own_bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var own_weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var own_per := own_bones.size() / points.size()
			for v in points.size():
				for k in per:
					if k < own_per:
						var bind := own_bones[v * own_per + k]
						bones.append(remap[bind] if bind < remap.size() else 0)
						weights.append(own_weights[v * own_per + k])
					else:
						bones.append(0)
						weights.append(0.0)
			var own_index: Variant = arrays[Mesh.ARRAY_INDEX]
			if own_index == null:
				for v in points.size():
					indices.append(base + v)
			else:
				for v: int in own_index:
					indices.append(base + v)
	if verts.is_empty():
		return []
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = verts
	out[Mesh.ARRAY_NORMAL] = normals
	out[Mesh.ARRAY_BONES] = bones
	out[Mesh.ARRAY_WEIGHTS] = weights
	out[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out, [], {},
			Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS if eight else 0)
	_shadow_bodies[hash(key)] = [mesh, skin]
	return [mesh, skin, used]


## One mesh of `pieces` (one surface each, the same format), each placed by
## its transform under the shared parent: positions moved, normals by the
## inverse transpose (so a stretched cylinder stays lit as it was) and
## tangents turned with the piece.
static func _merged_mesh(pieces: Array, mat: Material) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var tangents := PackedFloat32Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var first: Array = (pieces[0] as MeshInstance3D).mesh.surface_get_arrays(0)
	var has_normal: bool = first[Mesh.ARRAY_NORMAL] != null
	var has_tangent: bool = first[Mesh.ARRAY_TANGENT] != null
	var has_uv: bool = first[Mesh.ARRAY_TEX_UV] != null
	var has_uv2: bool = first[Mesh.ARRAY_TEX_UV2] != null
	var has_color: bool = first[Mesh.ARRAY_COLOR] != null
	for piece: MeshInstance3D in pieces:
		var arrays: Array = piece.mesh.surface_get_arrays(0)
		var xform := piece.transform
		var turn := xform.basis.inverse().transposed()
		var base := verts.size()
		var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for v in points:
			verts.append(xform * v)
		if has_normal:
			for n: Vector3 in arrays[Mesh.ARRAY_NORMAL]:
				normals.append((turn * n).normalized())
		if has_tangent:
			var t: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
			for i in range(0, t.size(), 4):
				var along := (xform.basis * Vector3(t[i], t[i + 1], t[i + 2])).normalized()
				tangents.append_array(PackedFloat32Array([along.x, along.y, along.z, t[i + 3]]))
		if has_uv:
			uvs.append_array(arrays[Mesh.ARRAY_TEX_UV])
		if has_uv2:
			uv2s.append_array(arrays[Mesh.ARRAY_TEX_UV2])
		if has_color:
			colors.append_array(arrays[Mesh.ARRAY_COLOR])
		var own: Variant = arrays[Mesh.ARRAY_INDEX]
		if own == null:
			for i in points.size():
				indices.append(base + i)
		else:
			for i: int in own:
				indices.append(base + i)
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = verts
	out[Mesh.ARRAY_INDEX] = indices
	if has_normal:
		out[Mesh.ARRAY_NORMAL] = normals
	if has_tangent:
		out[Mesh.ARRAY_TANGENT] = tangents
	if has_uv:
		out[Mesh.ARRAY_TEX_UV] = uvs
	if has_uv2:
		out[Mesh.ARRAY_TEX_UV2] = uv2s
	if has_color:
		out[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
	mesh.surface_set_material(0, mat)
	return mesh


## What a one-surface piece is drawn in: its override, else its surface's.
## A merged mesh needs more triangles than this to be given levels of
## detail: a few boxes gain nothing from them.
const LOD_FROM := 400
## Merged meshes given levels of detail, by their points and material, so
## every vehicle of a kind shares one and makes it once.
static var _lod_meshes := {}


## `mesh` (one surface) with levels of detail made for it, as Godot's import
## makes them, or `mesh` itself when it is small. The same shape is made
## once (`_lod_meshes`).
static func _with_lods(mesh: ArrayMesh) -> ArrayMesh:
	var arrays := mesh.surface_get_arrays(0)
	var index: Variant = arrays[Mesh.ARRAY_INDEX]
	if index == null or (index as PackedInt32Array).size() / 3 <= LOD_FROM:
		return mesh
	var mat := mesh.surface_get_material(0)
	var key := hash([arrays[Mesh.ARRAY_VERTEX], index, mat.get_instance_id() if mat != null else 0])
	if _lod_meshes.has(key):
		return _lod_meshes[key]
	var made := ImporterMesh.new()
	made.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, mat, "", mesh.surface_get_format(0))
	made.generate_lods(25.0, 0.0, [])
	var out := made.get_mesh()
	_lod_meshes[key] = out
	return out


## A plain material by what it is set to (every stored property), so two
## copies set alike give the same key; any other material by itself.
static func _material_key(mat: Material) -> String:
	if not mat is StandardMaterial3D:
		return str(mat.get_instance_id())
	var parts := PackedStringArray()
	for prop: Dictionary in mat.get_property_list():
		if int(prop["usage"]) & PROPERTY_USAGE_STORAGE and prop["name"] != "resource_name":
			parts.append(var_to_str(mat.get(prop["name"])))
	return "|".join(parts)


static func _piece_material(piece: MeshInstance3D) -> Material:
	if piece.material_override != null:
		return piece.material_override
	var mat := piece.get_surface_override_material(0)
	return mat if mat != null else piece.mesh.surface_get_material(0)


## Which arrays a surface carries, as a key; "" for one that cannot be
## merged (skinned, or with custom channels `_merged_mesh` does not carry).
static func _layout(arrays: Array) -> String:
	for skip in [Mesh.ARRAY_BONES, Mesh.ARRAY_WEIGHTS, Mesh.ARRAY_CUSTOM0, Mesh.ARRAY_CUSTOM1,
			Mesh.ARRAY_CUSTOM2, Mesh.ARRAY_CUSTOM3]:
		if arrays[skip] != null:
			return ""
	var key := ""
	for kind in [Mesh.ARRAY_NORMAL, Mesh.ARRAY_TANGENT, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2, Mesh.ARRAY_COLOR]:
		key += "1" if arrays[kind] != null else "0"
	return key


static func _mergeable(piece: MeshInstance3D) -> bool:
	return piece.mesh != null and piece.mesh.get_surface_count() == 1 \
			and (piece.mesh is PrimitiveMesh or (piece.mesh is ArrayMesh
				and (piece.mesh as ArrayMesh).surface_get_primitive_type(0) == Mesh.PRIMITIVE_TRIANGLES)) \
			and piece.transform.basis.determinant() > 0.0 \
			and piece.visible and piece.get_child_count() == 0 and piece.skin == null \
			and piece.material_overlay == null \
			and piece.transparency == 0.0 and piece.layers == 1 and piece.visibility_range_end == 0.0 \
			and (not piece.mesh is ArrayMesh or (piece.mesh as ArrayMesh).get_blend_shape_count() == 0) \
			and piece.get_script() == null


# --- Surfaces -----------------------------------------------------------------

## A world-space PBR material. `opts` may set: tint (Color), scale (float),
## blend (surface kind to mix in), blend_amount, wetness, snow, snow_patchy,
## grime, saturation, metal (overrides the kind's metalness),
## rough_mult, lit_windows (chance 0..1), window_glow (Color).
func surface(kind: String, opts := {}) -> Material:
	var key := kind + str(opts)
	if _materials.has(key):
		return _materials[key]
	var def: Dictionary = SURFACES.get(kind, SURFACES["concrete"])
	var tint: Color = opts.get("tint", Color.WHITE)
	var mat: Material
	if not enabled:
		var plain := StandardMaterial3D.new()
		plain.albedo_color = tint * 0.5
		mat = plain
	else:
		var sm := ShaderMaterial.new()
		sm.shader = SURFACE_SHADER
		_set_textures(sm, "", def["tex"])
		sm.set_shader_parameter("noise_tex", _noise_texture())
		sm.set_shader_parameter("tint", tint)
		sm.set_shader_parameter("tex_scale", opts.get("scale", def["scale"]))
		sm.set_shader_parameter("metal", opts.get("metal", def.get("metal", 0.0)))
		sm.set_shader_parameter("rough_mult", opts.get("rough_mult", 1.0))
		sm.set_shader_parameter("wetness", opts.get("wetness", 0.0))
		sm.set_shader_parameter("snow", opts.get("snow", 0.0))
		sm.set_shader_parameter("grime", opts.get("grime", 0.4))
		sm.set_shader_parameter("snow_patchy", opts.get("snow_patchy", 0.0))
		sm.set_shader_parameter("saturation", opts.get("saturation", 0.8))
		sm.set_shader_parameter("window_lit_chance", opts.get("lit_windows", 0.05))
		sm.set_shader_parameter("window_glow", opts.get("window_glow", Color(1.0, 0.62, 0.3)))
		if opts.has("blend"):
			var other: Dictionary = SURFACES.get(opts["blend"], def)
			_set_textures(sm, "blend_", other["tex"])
			sm.set_shader_parameter("blend_amount", opts.get("blend_amount", 0.5))
		mat = sm
	_materials[key] = mat
	return mat


## Turns a box mesh into a building face: windows are laid out from its size.
func make_building(mesh_node: MeshInstance3D, size: Vector3, seed_value: float) -> void:
	if not enabled:
		return
	mesh_node.set_instance_shader_parameter("box_size", size)
	mesh_node.set_instance_shader_parameter("seed", seed_value)


func _set_textures(mat: ShaderMaterial, prefix: String, tex: String) -> void:
	var dir := TEXTURES + tex + "/"
	mat.set_shader_parameter(prefix + "albedo_tex", load(dir + "Color.jpg"))
	mat.set_shader_parameter(prefix + "normal_tex", load(dir + "NormalGL.jpg"))
	if prefix == "":
		mat.set_shader_parameter("rough_tex", load(dir + "Roughness.jpg"))


func _noise_texture() -> NoiseTexture2D:
	if _noise == null:
		var noise := FastNoiseLite.new()
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		noise.frequency = 0.012
		noise.fractal_octaves = 4
		_noise = NoiseTexture2D.new()
		_noise.width = 512
		_noise.height = 512
		_noise.seamless = true
		_noise.noise = noise
	return _noise


# --- Atmosphere ---------------------------------------------------------------

## Sky, fog, sun and post-processing for a map. Keys, all optional:
##   sky (hdr file name), sky_tint, sky_energy, sky_saturation, sky_rotation,
##   fog_color, fog_density, fog_depth_begin, fog_depth_end, fog_depth_curve,
##   fog_height, fog_height_density, haze_height,
##   sun_color, sun_energy, sun_angles (degrees),
##   ambient_color, ambient_energy, exposure, saturation, contrast, glow.
## `fog_depth_end` above `fog_depth_begin` selects depth fog: nothing until
## the begin distance, solid (times `fog_density`) at the end. Godot
## multiplies that curve by `fog_density`, so in depth mode density is an
## opacity at the far end (about 0.6 to 0.9), not the small exponential
## number. Without a depth range, `fog_density` is exponential. Height fog
## is a ground layer under `fog_height` and never replaces the depth falloff
## above it. The war end of a blend is passed through `soften_storm`, so a
## mood cannot ask for a whiteout.
## `war` holds the same keys for the same place in the middle of a battle.
## When it is given, the mood blends from `p` towards it as the map's
## "war_intensity" meta climbs from 0 to 1, and a column of smoke stands over
## its "war_centre" meta. Whoever runs the world sets those metas; nothing
## here knows who.
## `storm` holds the same keys for the thick of a storm crossing the map
## (DESIGN.md "Weather: ash storms"). The mood blends towards it by the
## map's "weather_here" meta (set by `WeatherView`: how far into a storm the
## camera is), through `soften_weather`, which lets it close in to about
## 70 m but no closer.
## On a headless server this only adds a plain sun, which nothing sees.
func atmosphere(parent: Node3D, p := {}, war := {}, storm := {}, close := {}) -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = p.get("sun_angles", Vector3(-45, 30, 0))
	sun.light_color = p.get("sun_color", Color.WHITE)
	sun.light_energy = p.get("sun_energy", 1.0)
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 140.0
	sun.add_to_group(GameSettings.SUN_GROUP)
	GameSettings.fit_sun(sun, 140.0)
	sun.shadow_blur = 1.5
	parent.add_child(sun)
	if not enabled:
		return

	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = SKY_SHADER
	sky_mat.set_shader_parameter("panorama", load("res://assets/sky/" + p.get("sky", "kloppenheim_06_puresky_2k.hdr")))
	sky_mat.set_shader_parameter("rotation", p.get("sky_rotation", 0.0))
	sky_mat.set_shader_parameter("haze_height", p.get("haze_height", 0.22))
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_128

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_sky_contribution = 0.5
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 6.0
	env.fog_enabled = true
	env.fog_sky_affect = 0.0
	env.fog_aerial_perspective = 0.0
	env.fog_sun_scatter = p.get("sun_scatter", 0.15)
	env.fog_height = p.get("fog_height", 30.0)
	env.fog_height_density = p.get("fog_height_density", 0.0)
	env.ssao_enabled = true
	env.ssao_radius = 1.6
	env.ssao_intensity = 2.6
	env.ssao_power = 1.6
	env.glow_enabled = true
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.adjustment_enabled = true
	var world_env := WorldEnvironment.new()
	world_env.name = "Atmosphere"
	world_env.environment = env
	world_env.add_to_group(GameSettings.ATMOSPHERE_GROUP)
	GameSettings.fit_atmosphere(world_env)
	parent.add_child(world_env)
	parent.add_child(edge_ink())
	var calm := mood_values(p)
	weather_cover = 0.0
	close_cover = 0.0
	apply_mood(calm, env, sky_mat, sun)
	if war.is_empty() and storm.is_empty() and close.is_empty():
		return
	var mood := WarMood.new()
	mood.name = "WarMood"
	mood.follow = storm_follow
	mood.calm = calm
	mood.war = soften_storm(mood_values(war, calm)) if not war.is_empty() else calm
	mood.storm = soften_weather(mood_values(storm, calm)) if not storm.is_empty() else {}
	mood.close = mood_values(close, calm) if not close.is_empty() else {}
	mood.env = env
	mood.sky_mat = sky_mat
	mood.sun = sun
	mood.ink = parent.get_node_or_null("EdgeInk") as MeshInstance3D
	parent.add_child(mood)
	if not war.is_empty():
		mood.column = _war_column()
		mood.add_child(mood.column)


## The edge ink over an outdoor map (`assets/shaders/edge_ink.gdshader`): a
## quad the shader stretches over whatever camera draws it, so every view of
## the map gets the same outlines on far shapes. It is in the group
## "edge_ink", shown while `GameSettings.ink_shown()`. Drawn first of the
## see-through things, so glass, holograms and effects stay on top of it.
func edge_ink() -> MeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	var mat := ShaderMaterial.new()
	mat.shader = EDGE_INK_SHADER
	mat.render_priority = Material.RENDER_PRIORITY_MIN
	quad.material = mat
	quad.custom_aabb = AABB(Vector3(-1.0, -1.0, -1.0) * 1.0e5, Vector3.ONE * 2.0e5)
	var ink := MeshInstance3D.new()
	ink.name = "EdgeInk"
	ink.mesh = quad
	ink.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ink.extra_cull_margin = 16384.0
	ink.add_to_group("edge_ink")
	ink.visible = GameSettings.ink_shown()
	return ink


## The part of an atmosphere that can shift while a world runs, with every
## key filled in. Keys missing from `p` come from `fallback`, or from the
## defaults when there is none.
func mood_values(p: Dictionary, fallback := {}) -> Dictionary:
	var fog: Color = p.get("fog_color", fallback.get("fog_color", Color(0.5, 0.5, 0.5)))
	var base := {
		"sky_tint": Color.WHITE, "sky_energy": 1.0, "sky_saturation": 1.0,
		"fog_color": fog, "fog_density": 0.01,
		"fog_depth_begin": 0.0, "fog_depth_end": 0.0, "fog_depth_curve": 1.0,
		"fog_height": 0.0, "fog_height_density": 0.0, "haze_height": 0.22,
		"sun_color": Color.WHITE, "sun_energy": 1.0,
		"ambient_color": fog.lerp(Color.WHITE, 0.4), "ambient_energy": 1.0,
		"exposure": 1.0, "saturation": 0.9, "contrast": 1.08, "glow": 0.7,
	}
	var out := {}
	for key: String in base:
		out[key] = p.get(key, fallback.get(key, base[key]))
	return out


## A mood part of the way from `a` to `b`.
func blend_moods(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	var out := {}
	for key: String in a:
		out[key] = lerp(a[key], b.get(key, a[key]), clampf(t, 0.0, 1.0))
	return out


func apply_mood(m: Dictionary, env: Environment, sky_mat: ShaderMaterial, sun: DirectionalLight3D) -> void:
	sky_mat.set_shader_parameter("tint", m.sky_tint)
	sky_mat.set_shader_parameter("energy", m.sky_energy)
	sky_mat.set_shader_parameter("saturation", m.sky_saturation)
	sky_mat.set_shader_parameter("haze_color", m.fog_color)
	sky_mat.set_shader_parameter("haze_height", m.haze_height)
	apply_fog(env, m)
	env.ambient_light_color = m.ambient_color
	env.ambient_light_energy = m.ambient_energy
	env.tonemap_exposure = m.exposure
	env.glow_intensity = m.glow
	env.adjustment_saturation = m.saturation
	env.adjustment_contrast = m.contrast
	sun.light_color = m.sun_color
	sun.light_energy = m.sun_energy
	for key: String in ["trim:distant", "trim:distant_lit"]:
		if _materials.has(key):
			var skyline := _materials[key] as ShaderMaterial
			skyline.set_shader_parameter("haze", m.fog_color)
			skyline.set_shader_parameter("haze_amount", skyline_haze(float(m.fog_density)))


## How much haze the far skyline wears for a mood's far fog: a veil on a
## clear day, more as war closes the horizon in, gone in the thick of a storm.
func skyline_haze(fog_density: float) -> float:
	var t := clampf(inverse_lerp(skyline_haze_from, skyline_haze_gone, fog_density), 0.0, 1.0)
	return lerpf(skyline_haze_clear, 1.0, t * t)


## Pulls a war mood back inside the readability caps. Depth fog cannot start
## inside engagement range or turn solid there, and its far opacity stays a
## veil. Exponential fog, which tints near and far together, is held to a
## thin haze. Height fog cannot rise over a standing head.
func soften_storm(m: Dictionary) -> Dictionary:
	var out := m.duplicate()
	if float(out.fog_depth_end) > float(out.fog_depth_begin) + 1.0:
		out.fog_depth_begin = maxf(out.fog_depth_begin, storm_fog_begin_min)
		out.fog_depth_end = maxf(out.fog_depth_end, storm_fog_solid_min)
		out.fog_depth_curve = maxf(out.fog_depth_curve, 0.75)
		out.fog_density = clampf(out.fog_density, 0.0, storm_depth_amount_cap)
	else:
		out.fog_density = minf(out.fog_density, storm_fog_density_cap)
	if absf(out.fog_height_density) > 0.0001:
		out.fog_height_density = clampf(out.fog_height_density, 0.0, storm_height_density_cap)
		out.fog_height = minf(out.fog_height, storm_fog_height_max)
	return out


## Pulls a storm mood back inside its own floor: depth fog may close in
## further than the war's (`weather_fog_begin_min`, `weather_fog_solid_min`)
## but never into the face, and never to a full wipe.
func soften_weather(m: Dictionary) -> Dictionary:
	var out := m.duplicate()
	if float(out.fog_depth_end) > float(out.fog_depth_begin) + 1.0:
		out.fog_depth_begin = maxf(out.fog_depth_begin, weather_fog_begin_min)
		out.fog_depth_end = maxf(out.fog_depth_end, weather_fog_solid_min)
		out.fog_depth_curve = maxf(out.fog_depth_curve, 0.75)
		out.fog_density = clampf(out.fog_density, 0.0, weather_depth_amount_cap)
	else:
		out.fog_density = minf(out.fog_density, storm_fog_density_cap * 4.0)
	if absf(out.fog_height_density) > 0.0001:
		out.fog_height_density = clampf(out.fog_height_density, 0.0, storm_height_density_cap)
		out.fog_height = minf(out.fog_height, storm_fog_height_max)
	return out


## Writes `m` onto `env`'s fog and onto the globals the character, gear and
## melee shaders read (they replace the engine fog, so they need the same
## numbers). Depth mode when the range is real; otherwise exponential.
func apply_fog(env: Environment, m: Dictionary) -> void:
	var density: float = m.fog_density
	var begin: float = m.fog_depth_begin
	var end: float = m.fog_depth_end
	var curve: float = m.fog_depth_curve
	var height: float = m.fog_height
	var height_density: float = m.fog_height_density
	var use_depth := end > begin + 1.0
	if use_depth:
		# In a storm, or close air, the floor comes down with how far in
		# the camera is.
		var cover := clampf(maxf(weather_cover, close_cover), 0.0, 1.0)
		begin = maxf(begin, lerpf(storm_fog_begin_min, weather_fog_begin_min, cover))
		end = maxf(end, lerpf(storm_fog_solid_min, weather_fog_solid_min, cover))
		curve = maxf(curve, 0.75)
		density = clampf(density, 0.0, lerpf(storm_depth_amount_cap, weather_depth_amount_cap, cover))
		env.fog_mode = Environment.FOG_MODE_DEPTH
		env.fog_depth_begin = begin
		env.fog_depth_end = end
		env.fog_depth_curve = curve
	else:
		env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	if absf(height_density) > 0.0001:
		height_density = clampf(height_density, 0.0, storm_height_density_cap)
		height = minf(height, storm_fog_height_max)
	env.fog_light_color = m.fog_color
	env.fog_density = density
	env.fog_height = height
	env.fog_height_density = height_density
	_push_storm_fog(use_depth, m.fog_color, density, begin, end, curve, height, height_density)


## How thick the fog is at `distance` metres from the camera and `world_y`
## metres up. The same curve as Godot's fog and as the actor shaders, so a
## test can say what a player would see without a GPU.
func fog_amount_at(distance: float, world_y: float, density: float, depth_begin: float, depth_end: float,
		curve: float, use_depth: bool, height: float, height_density: float) -> float:
	var amount := 0.0
	if use_depth:
		var t := smoothstep(depth_begin, depth_end, distance)
		amount = pow(maxf(t, 0.0), maxf(curve, 0.001)) * density
	else:
		amount = 1.0 - exp(-distance * maxf(density, 0.0))
	if absf(height_density) >= 0.0001:
		var y_dist := world_y - height
		var vfog := 1.0 - exp(minf(0.0, y_dist * height_density))
		amount = maxf(amount, vfog)
	return clampf(amount, 0.0, 1.0)


## Share of the world fog an actor keeps at `distance` metres. 1 is the
## world's own fog. Near the camera it drops to `actor_fog_min`.
func actor_fog_keep(distance: float) -> float:
	var span := maxf(actor_fog_full - actor_fog_clear, 0.001)
	var far := clampf((distance - actor_fog_clear) / span, 0.0, 1.0)
	return lerpf(actor_fog_min, 1.0, far)


## A faction paint (`Actor.body_color`) pushed into the teal / pink energy
## glow the guns already use, so a figure separates from orange storm air.
## Cool paint leans teal, warm paint leans pink. Nothing here names a world.
func storm_accent(body: Color) -> Color:
	var accent := body
	accent.s = clampf(maxf(accent.s, 0.75), 0.0, 1.0)
	accent.v = clampf(maxf(accent.v, 0.9), 0.0, 1.0)
	if accent.r > accent.b:
		accent = accent.lerp(Color(1.0, 0.32, 0.78), 0.55)
	else:
		accent = accent.lerp(Color(0.25, 0.9, 1.0), 0.45)
	accent.s = clampf(maxf(accent.s, 0.7), 0.0, 1.0)
	accent.v = 1.0
	return accent


## Marks meshes under `root` so they keep less fog up close and take a faction
## rim. A material shared with props (storm_pop still 0) is copied first, so
## a crate is not pulled out of the fog with the soldier. No per-instance
## shader parameters: a battle's worth of props would overflow that buffer.
func mark_storm_readable(root: Node, accent: Color) -> void:
	if root == null or not enabled:
		return
	var meshes: Array[MeshInstance3D] = []
	if root is MeshInstance3D:
		meshes.append(root)
	for node in root.find_children("*", "MeshInstance3D", true, false):
		meshes.append(node)
	for mesh in meshes:
		if mesh.mesh:
			for i in mesh.mesh.get_surface_count():
				var mat := mesh.get_surface_override_material(i) as ShaderMaterial
				if mat == null:
					mat = mesh.mesh.surface_get_material(i) as ShaderMaterial
				var popped := _pop_storm(mat, accent)
				if popped != null and popped != mat:
					mesh.set_surface_override_material(i, popped)
		var over := mesh.material_override as ShaderMaterial
		var popped_over := _pop_storm(over, accent)
		if popped_over != null and popped_over != over:
			mesh.material_override = popped_over


## The material to draw, or null when `mat` has no storm uniforms. Copies a
## shared material the first time so props keep `storm_pop` at 0.
func _pop_storm(mat: ShaderMaterial, accent: Color) -> ShaderMaterial:
	if mat == null:
		return null
	var pop: Variant = mat.get_shader_parameter("storm_pop")
	if pop == null:
		return null
	if mat.has_meta("tech_full"):
		# A folding blade worn folded or half drawn: light its drawn-out
		# material and fold that copy the same way, so `set_extend` swaps
		# between lit copies and never back to the unlit pair.
		var lit := _pop_storm(mat.get_meta("tech_full"), accent)
		var extend := float(mat.get_shader_parameter("extend"))
		if extend >= 1.0:
			return lit
		if extend <= 0.0:
			return _folded_copy(lit)
		var part := lit.duplicate() as ShaderMaterial
		part.set_meta("tech_full", lit)
		part.set_shader_parameter("extend", extend)
		return part
	var use := mat
	if float(pop) < 0.5:
		use = mat.duplicate() as ShaderMaterial
		use.set_shader_parameter("storm_pop", 1.0)
	use.set_shader_parameter("storm_rim", Vector3(accent.r, accent.g, accent.b))
	_bind_storm(use)
	if use.has_meta("tech_fold"):
		# A folding blade's drawn-out material: its folded copy is lit the
		# same (a fresh copy gets one made from it, already lit).
		var folded := _folded_copy(use)
		folded.set_shader_parameter("storm_pop", 1.0)
		folded.set_shader_parameter("storm_rim", Vector3(accent.r, accent.g, accent.b))
		_bind_storm(folded)
	return use


func _bind_storm(mat: ShaderMaterial) -> void:
	mat.set_shader_parameter("storm_clear", actor_fog_clear)
	mat.set_shader_parameter("storm_full", actor_fog_full)
	mat.set_shader_parameter("storm_keep_near", actor_fog_min)
	mat.set_shader_parameter("storm_rim_strength", actor_rim_strength)


func _add_storm_globals() -> void:
	if _storm_globals_ready:
		return
	# Added once, before any storm material compiles. Listing the globals
	# back (`global_shader_parameter_get_list`) is an editor call and hangs
	# a running game, so this does not check first.
	var specs: Array = [
		["storm_fog_active", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.0],
		["storm_fog_color", RenderingServer.GLOBAL_VAR_TYPE_VEC3, Vector3(0.5, 0.5, 0.5)],
		["storm_fog_density", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.01],
		["storm_fog_depth", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.0],
		["storm_fog_begin", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.0],
		["storm_fog_end", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.0],
		["storm_fog_curve", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 1.0],
		["storm_fog_height", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.0],
		["storm_fog_height_density", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.0],
	]
	for spec: Array in specs:
		RenderingServer.global_shader_parameter_add(spec[0], spec[1], spec[2])
	_storm_globals_ready = true


func _push_storm_fog(use_depth: bool, color: Color, density: float, begin: float, end: float, curve: float,
		height: float, height_density: float) -> void:
	if not _storm_globals_ready:
		return
	RenderingServer.global_shader_parameter_set("storm_fog_active", 1.0)
	RenderingServer.global_shader_parameter_set("storm_fog_color", Vector3(color.r, color.g, color.b))
	RenderingServer.global_shader_parameter_set("storm_fog_density", density)
	RenderingServer.global_shader_parameter_set("storm_fog_depth", 1.0 if use_depth else 0.0)
	RenderingServer.global_shader_parameter_set("storm_fog_begin", begin)
	RenderingServer.global_shader_parameter_set("storm_fog_end", end)
	RenderingServer.global_shader_parameter_set("storm_fog_curve", curve)
	RenderingServer.global_shader_parameter_set("storm_fog_height", height)
	RenderingServer.global_shader_parameter_set("storm_fog_height_density", height_density)


func _clear_storm_fog() -> void:
	if _storm_globals_ready:
		RenderingServer.global_shader_parameter_set("storm_fog_active", 0.0)


## Smoke, ash and red light standing over the heaviest fighting.
func _war_column() -> Node3D:
	var column := Node3D.new()
	column.name = "WarColumn"
	var smoke := GPUParticles3D.new()
	smoke.name = "Smoke"
	# Rises above head height. The dense part of the column is overhead,
	# not a wall at eye level.
	smoke.position.y = 16.0
	smoke.amount = column_particles
	smoke.lifetime = 14.0
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 8.0
	mat.direction = Vector3(0.15, 1, 0.05)
	mat.spread = 12.0
	mat.gravity = Vector3(0.4, 0.2, 0.15)
	mat.initial_velocity_min = 4.0
	mat.initial_velocity_max = 7.0
	mat.scale_min = 0.45
	mat.scale_max = 1.15
	mat.turbulence_enabled = true
	mat.turbulence_noise_scale = 3.0
	mat.turbulence_influence_min = 0.02
	mat.turbulence_influence_max = 0.08
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.35))
	grow.add_point(Vector2(1.0, 1.0))
	var grow_tex := CurveTexture.new()
	grow_tex.curve = grow
	mat.scale_curve = grow_tex
	var fade := Gradient.new()
	fade.set_color(0, Color(0.55, 0.22, 0.08, 0.0))
	fade.add_point(0.12, Color(0.42, 0.18, 0.08, 0.22))
	fade.add_point(0.5, Color(0.14, 0.09, 0.07, 0.16))
	fade.set_color(fade.get_point_count() - 1, Color(0.06, 0.05, 0.05, 0.0))
	var fade_tex := GradientTexture1D.new()
	fade_tex.gradient = fade
	mat.color_ramp = fade_tex
	var quad := QuadMesh.new()
	quad.size = Vector2(column_card, column_card)
	var draw := ShaderMaterial.new()
	draw.shader = STORM_COLUMN_SHADER
	draw.set_shader_parameter("soft_tex", _soft_dot())
	draw.set_shader_parameter("clear_near", column_clear_near)
	draw.set_shader_parameter("clear_far", column_clear_far)
	quad.material = draw
	smoke.process_material = mat
	smoke.draw_pass_1 = quad
	smoke.visibility_aabb = AABB(Vector3(-50, -20, -50), Vector3(100, 160, 100))
	smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	smoke.emitting = false
	column.add_child(smoke)
	var glow := OmniLight3D.new()
	glow.name = "Glow"
	glow.light_color = Color(1.0, 0.35, 0.15)
	glow.omni_range = 36.0
	glow.light_energy = 0.0
	glow.position.y = 22.0
	column.add_child(glow)
	return column


## Shifts a map's mood with the war. Reads the metas "war_intensity" and
## "war_centre" from the node it was added to, and eases towards them so the
## sky never snaps. View only.
class WarMood:
	extends Node

	## How fast the mood follows the meter, per second.
	var follow := 0.12
	## The column of smoke shows above this intensity.
	var column_from := 0.3
	var calm := {}
	var war := {}
	## The thick of a storm (`Look.atmosphere`'s `storm`), or empty.
	var storm := {}
	## Close air (`Look.atmosphere`'s `close`), or empty.
	var close := {}
	## How far into close air the view is shown to be, 0 to 1.
	var close_shown := 0.0
	var env: Environment
	var sky_mat: ShaderMaterial
	var sun: DirectionalLight3D
	var column: Node3D
	## The map's edge ink, which a storm fades out: outlines would draw the
	## shapes the ash hides.
	var ink: MeshInstance3D
	## The intensity shown right now.
	var shown := 0.0
	## How far into a storm the view is shown to be, 0 to 1.
	var storm_shown := 0.0
	var _ink_strength := -1.0
	## The (war, storm, close air) shown when the mood was last written.
	var _applied := Vector3(-1.0, -1.0, -1.0)
	## The smallest change in the mood worth redrawing the sky for: a blend
	## step this small is not seen.
	const MOOD_STEP := 0.004

	func _process(delta: float) -> void:
		var parent := get_parent()
		var target := clampf(float(parent.get_meta("war_intensity", 0.0)), 0.0, 1.0)
		shown = move_toward(shown, target, follow * delta)
		if not storm.is_empty():
			var here := clampf(float(parent.get_meta("weather_here", 0.0)), 0.0, 1.0)
			storm_shown = move_toward(storm_shown, here, Look.weather_follow * delta)
		if not close.is_empty():
			var shut := clampf(float(parent.get_meta("close_here", 0.0)), 0.0, 1.0)
			close_shown = move_toward(close_shown, shut, Look.close_follow * delta)
		var centre: Vector3 = parent.get_meta("war_centre", Vector3.ZERO)
		# The mood is written only when it has moved a visible step (or
		# reached where it was going): any write to the sky's material, even
		# of the same value, has the renderer redraw the sky's light map
		# (radiance) that frame, a real cost on built-in graphics.
		if not mood_moved(_applied, Vector3(shown, storm_shown, close_shown)):
			_move_column(shown, centre)
			return
		show_intensity(shown, centre)

	## Whether a mood shown at `now` (war, storm, close air) is worth writing
	## over the one written at `was`: a step of `MOOD_STEP` or more on any of
	## them, or any change that lands on 0 or 1 (calm and full war are shown
	## exactly).
	static func mood_moved(was: Vector3, now: Vector3) -> bool:
		for i: int in 3:
			var step := absf(now[i] - was[i])
			if step >= MOOD_STEP or (step > 0.0 and (now[i] == 0.0 or now[i] == 1.0)):
				return true
		return false

	## Sets the mood for an intensity at once. `_process` calls this with the eased value.
	func show_intensity(value: float, centre: Vector3) -> void:
		shown = value
		_applied = Vector3(shown, storm_shown, close_shown)
		var mood := Look.blend_moods(calm, war, value)
		if not close.is_empty():
			mood = Look.blend_moods(mood, close, close_shown)
		Look.close_cover = close_shown if not close.is_empty() else 0.0
		if not storm.is_empty():
			mood = Look.blend_moods(mood, storm, storm_shown)
		Look.weather_cover = storm_shown if not storm.is_empty() else 0.0
		Look.apply_mood(mood, env, sky_mat, sun)
		# In a storm, or close air, the air hides the sky too, and outlines
		# fade with it.
		env.fog_sky_affect = maxf(Look.weather_cover, Look.close_cover)
		if ink != null and is_instance_valid(ink):
			var mat := (ink.mesh as QuadMesh).material as ShaderMaterial if ink.mesh is QuadMesh else null
			if mat != null:
				if _ink_strength < 0.0:
					var base: Variant = mat.get_shader_parameter("strength")
					_ink_strength = float(base) if base != null else 0.8
				mat.set_shader_parameter("strength", _ink_strength * (1.0 - maxf(Look.weather_cover, Look.close_cover)))
		_move_column(value, centre)

	## The war's smoke column: as strong as the war, drifting to its centre.
	func _move_column(value: float, centre: Vector3) -> void:
		if column == null:
			return
		var smoke: GPUParticles3D = column.get_node("Smoke")
		var glow: OmniLight3D = column.get_node("Glow")
		var strength := clampf((value - column_from) / maxf(1.0 - column_from, 0.001), 0.0, 1.0)
		smoke.emitting = strength > 0.0
		smoke.amount_ratio = strength
		glow.light_energy = strength * Look.column_glow
		if strength > 0.0:
			column.global_position = column.global_position.lerp(centre, 0.02) \
					if column.global_position.distance_to(centre) < 120.0 else centre


## How each kind of storm looks (`WeatherView`): the wall's dark and lit
## colour, the driven streaks and the billows around the viewer, and how
## steeply the streaks fall. A world picks a kind; nothing here names one.
const WEATHER_KITS := {
	"ash": {
		"wall_tint": Color(0.15, 0.075, 0.055), "wall_lit": Color(0.44, 0.23, 0.15),
		"streak": Color(0.55, 0.32, 0.22, 0.55), "streak_size": Vector2(0.025, 0.55),
		"billow": Color(0.42, 0.24, 0.17, 0.22), "fall": -0.06, "wall_height": 95.0,
	},
	"snow": {
		"wall_tint": Color(0.6, 0.66, 0.75), "wall_lit": Color(0.95, 0.97, 1.0),
		"streak": Color(1.0, 1.0, 1.0, 0.8), "streak_size": Vector2(0.04, 0.4),
		"billow": Color(0.92, 0.94, 0.98, 0.28), "fall": -0.22, "wall_height": 70.0,
		# Spindrift off the edges a map offers (`WeatherView`).
		"drift": true,
	},
	# Rain: long thin streaks falling steeply, a grey-green wall of it.
	"rain": {
		"wall_tint": Color(0.2, 0.25, 0.25), "wall_lit": Color(0.5, 0.58, 0.58),
		"streak": Color(0.75, 0.85, 0.85, 0.35), "streak_size": Vector2(0.012, 0.9),
		"billow": Color(0.45, 0.52, 0.52, 0.16), "fall": -2.2, "wall_height": 80.0,
		# What the storm sounds like round you (`Sfx`; "wind" by default).
		"sound": "rain",
		# Rain falls out of the air round the camera fast: more streaks,
		# each shorter lived.
		"streaks": 6000, "streak_life": 1.6,
	},
	# Sand: a tall ochre wall, the grit driven flat and low along the wind.
	"sand": {
		"wall_tint": Color(0.36, 0.24, 0.13), "wall_lit": Color(0.82, 0.6, 0.36),
		"streak": Color(0.86, 0.66, 0.42, 0.5), "streak_size": Vector2(0.02, 0.45),
		"billow": Color(0.74, 0.54, 0.33, 0.26), "fall": -0.02, "wall_height": 120.0,
	},
}


func weather_kit(kind: String) -> Dictionary:
	return WEATHER_KITS.get(kind, WEATHER_KITS["ash"])


## Drifting particles that fill the air over the whole map: "embers", "snow"
## or "ash". Purely visual.
func weather(parent: Node3D, kind: String, extent: float, height := 26.0) -> void:
	if not enabled:
		return
	var particles := GPUParticles3D.new()
	particles.name = "Weather"
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(extent, height * 0.5, extent)
	mat.turbulence_enabled = true
	mat.turbulence_noise_scale = 6.0
	var quad := QuadMesh.new()
	var draw := StandardMaterial3D.new()
	draw.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	draw.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	draw.vertex_color_use_as_albedo = true
	draw.albedo_texture = _soft_dot()
	match kind:
		"embers":
			particles.amount = 900
			particles.lifetime = 9.0
			mat.gravity = Vector3(0.6, 0.5, 0.2)
			mat.initial_velocity_min = 0.3
			mat.initial_velocity_max = 1.6
			mat.direction = Vector3(0.4, 1, 0.1)
			mat.spread = 60.0
			mat.turbulence_influence_min = 0.05
			mat.turbulence_influence_max = 0.2
			mat.color = Color(3.2, 1.1, 0.25)
			mat.scale_min = 0.5
			mat.scale_max = 1.4
			quad.size = Vector2(0.05, 0.05)
			draw.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		"snow":
			particles.amount = 2600
			particles.lifetime = 8.0
			mat.gravity = Vector3(-1.6, -1.8, 0.7)
			mat.initial_velocity_min = 0.5
			mat.initial_velocity_max = 2.5
			mat.direction = Vector3(-1, -0.4, 0.3)
			mat.spread = 35.0
			mat.turbulence_influence_min = 0.05
			mat.turbulence_influence_max = 0.15
			mat.color = Color(0.95, 0.97, 1.0, 0.85)
			mat.scale_min = 0.5
			mat.scale_max = 1.5
			quad.size = Vector2(0.07, 0.07)
		_:
			particles.amount = 700
			particles.lifetime = 12.0
			mat.gravity = Vector3(0.4, -0.35, 0.2)
			mat.initial_velocity_max = 0.6
			mat.turbulence_influence_min = 0.05
			mat.turbulence_influence_max = 0.2
			mat.color = Color(0.3, 0.28, 0.27, 0.7)
			mat.scale_min = 0.5
			mat.scale_max = 1.6
			quad.size = Vector2(0.06, 0.06)
	quad.material = draw
	particles.process_material = mat
	particles.draw_pass_1 = quad
	particles.preprocess = particles.lifetime
	particles.position.y = height * 0.5
	particles.visibility_aabb = AABB(Vector3(-extent, -height, -extent), Vector3(extent, height, extent) * 2.0)
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(particles)


var _dot: GradientTexture2D

func _soft_dot() -> GradientTexture2D:
	if _dot == null:
		var gradient := Gradient.new()
		gradient.set_color(0, Color(1, 1, 1, 1))
		gradient.set_color(1, Color(1, 1, 1, 0))
		_dot = GradientTexture2D.new()
		_dot.gradient = gradient
		_dot.fill = GradientTexture2D.FILL_RADIAL
		_dot.fill_from = Vector2(0.5, 0.5)
		_dot.fill_to = Vector2(1.0, 0.5)
		_dot.width = 32
		_dot.height = 32
	return _dot


# --- Props --------------------------------------------------------------------

## A prop model from assets/props, scaled so its longest side is `size` meters
## and resting on the ground. No collision: props never change gameplay.
## Returns null on a headless server.
func prop(file: String, size: float, wear := 0.6) -> Node3D:
	if not enabled:
		return null
	var holder := Node3D.new()
	var model := _instance(PROPS + file)
	if model == null:
		return holder
	holder.add_child(model)
	_fit(model, PROPS + file, size, false)
	_weather_model(model, wear, 0.3)
	return holder


## Lighting for a closed room: a flat ambient fill and a dark backdrop, so an
## interior is readable without a sun. Does nothing on a headless server.
func interior(parent: Node3D, ambient: Color, energy: float) -> void:
	if not enabled:
		return
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.02, 0.025)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = ambient
	env.ambient_light_energy = energy
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.ssao_enabled = true
	var world_env := WorldEnvironment.new()
	world_env.name = "Interior"
	world_env.environment = env
	world_env.add_to_group(GameSettings.ATMOSPHERE_GROUP)
	GameSettings.fit_atmosphere(world_env)
	parent.add_child(world_env)
	# An interior has no storm. Characters must not keep the last raid's fog.
	_clear_storm_fog()


## The trim every built thing in a warzone shares, so a map's pieces read as
## one kit instead of loose props: "teal" running lights, "band" (a teal
## strip turned down low enough to keep its colour on a lit wall), "orange" furnace
## light, "beacon" (a red light that cuts through the haze, never fogged),
## "slag" (molten metal), "lava" (a sea of it, crust and drifting seams), "crack" (a dimmer glow for cracks in the ground),
## "scorch" (charred ground), "track" (a packed gravel road), "rut" (a dark wheel rut), "hazard" (orange and black stripes),
## "sandbag", "halo" (a glow round a far light), "flash" (a far blast),
## "beam" (a searchlight), "lance" (an orbital strike's column), "distant" (skyline silhouettes), "distant_lit" (the same with lit windows and burning floors) and
## "horizon_glow" (fires past the rim, on a ring). Cached, so every piece
## shares one material.
func trim(kind: String) -> Material:
	var key := "trim:" + kind
	if _materials.has(key):
		return _materials[key]
	if kind == "sun_shaft" or kind == "beam":
		# Light in the smoke with no hard sides or ends (`haze_beam.gdshader`):
		# sunlight through a break, each shaft faded by its instance "fade",
		# or a searchlight's pale beam, lit from its lamp at the top.
		var shaft := ShaderMaterial.new()
		shaft.shader = HAZE_BEAM_SHADER
		if kind == "beam":
			shaft.set_shader_parameter("tint", Color(0.9, 0.85, 0.72))
			shaft.set_shader_parameter("strength", 0.09)
			shaft.set_shader_parameter("top_fade", 0.04)
			shaft.set_shader_parameter("foot", 0.0)
			shaft.set_shader_parameter("near_fade", 40.0)
		_materials[key] = shaft
		return shaft
	if kind == "lava":
		# A sea of lava (`lava.gdshader`): crust broken by drifting seams.
		var lava := ShaderMaterial.new()
		lava.shader = LAVA_SHADER
		lava.set_shader_parameter("noise_tex", _noise_texture())
		_materials[key] = lava
		return lava
	if kind == "distant" or kind == "distant_lit" or kind == "horizon_glow":
		# Shaded by hand, so they hold their own against the haze:
		# `apply_mood` sets the silhouettes' haze from the mood.
		# "distant_lit" is the same with a far city's life in it: scattered
		# lit windows and burning floors, drawn in the shader, no lights.
		var shaded := ShaderMaterial.new()
		shaded.shader = HORIZON_GLOW_SHADER if kind == "horizon_glow" else SKYLINE_SHADER
		if kind == "distant_lit":
			shaded.set_shader_parameter("lit", 1.0)
		_materials[key] = shaded
		return shaded
	var mat := StandardMaterial3D.new()
	match kind:
		"teal", "band", "orange", "beacon", "slag", "crack":
			var glow: Color = {"teal": Color(0.3, 0.95, 0.88), "band": Color(0.18, 0.85, 0.78), "orange": Color(1.0, 0.42, 0.1),
					"beacon": Color(1.0, 0.1, 0.06), "slag": Color(1.0, 0.36, 0.08), "crack": Color(1.0, 0.3, 0.05)}[kind]
			mat.albedo_color = glow * 0.25 if kind in ["teal", "band", "orange", "beacon"] else Color(0.25, 0.06, 0.02)
			mat.emission_enabled = true
			mat.emission = glow
			mat.emission_energy_multiplier = {"teal": 1.6, "band": 0.55, "orange": 2.4, "beacon": 7.0, "slag": 2.6, "crack": 1.1}[kind]
			mat.roughness = 0.4
			if kind == "beacon":
				mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				mat.albedo_color = glow
				mat.disable_fog = true
		"scorch":
			mat.albedo_color = Color(0.06, 0.045, 0.04)
			mat.roughness = 1.0
		"track":
			# Packed gravel: paler and greyer than any dirt, so a road reads.
			mat.albedo_color = Color(0.2, 0.19, 0.18)
			mat.roughness = 1.0
		"rut":
			mat.albedo_color = Color(0.075, 0.062, 0.055)
			mat.roughness = 1.0
		"halo":
			# A soft glow round a far light, drawn over the haze.
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			mat.albedo_texture = _soft_dot()
			mat.albedo_color = Color(1.0, 0.16, 0.08, 0.9)
			mat.disable_fog = true
		"flash":
			# A far gun flash or blast on the horizon: a bright soft glow the
			# haze never hides. Fade it with the instance's transparency.
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			mat.albedo_texture = _soft_dot()
			mat.albedo_color = Color(1.0, 0.62, 0.3)
			mat.disable_fog = true
			# Sized by the instance's scale, which a billboard drops otherwise.
			mat.billboard_keep_scale = true
		"tracer":
			# A far tracer round: a bright streak the haze never hides,
			# coloured and faded by its instance colour (a MultiMesh's).
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			mat.vertex_color_use_as_albedo = true
			mat.albedo_color = Color(1.0, 0.55, 0.22)
			mat.disable_fog = true
		"lance":
			# An orbital lance: a white-hot column from the sky that the haze
			# never hides. Fade it with the instance's transparency.
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			mat.albedo_color = Color(0.82, 0.9, 1.0, 0.85)
			mat.disable_fog = true
		"flak_smoke":
			# The puff a flak shell leaves hanging, lit by the fires below: haze softens it like
			# any far smoke. Fade it with the instance's transparency.
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.albedo_texture = _soft_dot()
			mat.albedo_color = Color(0.3, 0.22, 0.18, 0.7)
			mat.billboard_keep_scale = true
		"hazard":
			var stripes := Image.create(32, 32, false, Image.FORMAT_RGB8)
			for y in 32:
				for x in 32:
					stripes.set_pixel(x, y, Color(0.85, 0.42, 0.1) if (x + y) % 32 < 16 else Color(0.07, 0.06, 0.06))
			stripes.generate_mipmaps()
			mat.albedo_texture = ImageTexture.create_from_image(stripes)
			mat.uv1_triplanar = true
			mat.uv1_world_triplanar = true
			mat.uv1_scale = Vector3(0.9, 0.9, 0.9)
			mat.roughness = 0.7
			mat.metallic = 0.3
		"sandbag":
			return surface("ground", {"tint": Color(0.62, 0.52, 0.4), "grime": 0.7, "saturation": 0.5, "scale": 0.9})
		_:
			mat.albedo_color = Color(0.3, 0.28, 0.27)
	_materials[key] = mat
	return mat


## A small light with no shadow, for lamps and fires.
## A deploy gate's glimpse of the world it leads to, from that world's
## planet (`GateLook.window`): a sheet `size` metres facing +Z.
func gate_window(type: PlanetType, size: Vector2, rim: Color, seed := 0.0) -> MeshInstance3D:
	return GateLook.window(type, size, rim, seed)


## The colour a world's gate glows in, from its planet (`GateLook.world_color`).
## Pure data: callable headless, where the map still builds its trims.
func gate_color(type: PlanetType) -> Color:
	return GateLook.world_color(type)


## A world's emblem for its gate (`GateLook.crest`).
func gate_crest(type: PlanetType, size: float, color: Color) -> MeshInstance3D:
	return GateLook.crest(type, size, color)


## A sealed gate's frosted shutter with a hologram on it (`GateLook.teaser`).
func gate_teaser(size: Vector2, rim: Color) -> MeshInstance3D:
	return GateLook.teaser(size, rim)


## A slatted panel showing how full a world is (`GateLook.meter`).
func gate_meter(size: Vector2, color: Color, slats: int) -> MeshInstance3D:
	return GateLook.meter(size, color, slats)


## A strip of gate trim that a pulse can run up (`GateLook.trim`).
func gate_trim(strip: MeshInstance3D, color: Color, height: float) -> void:
	GateLook.trim(strip, color, height)


func lamp(color: Color, energy: float, reach: float) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = energy
	light.omni_range = reach
	light.omni_attenuation = 1.4
	light.shadow_enabled = false
	return light


func _instance(path: String) -> Node3D:
	var scene := load(path) as PackedScene
	if scene == null:
		push_warning("Look: missing model %s" % path)
		return null
	return scene.instantiate() as Node3D


## Scales `model` so it measures `target` meters (tallest side if `by_height`,
## else longest side), centers it on X and Z, and rests it on y = 0.
func _fit(model: Node3D, key: String, target: float, by_height: bool) -> void:
	var box: AABB
	if _prop_sizes.has(key):
		box = _prop_sizes[key]
	else:
		box = model_bounds(model)
		_prop_sizes[key] = box
	var measure := box.size.y if by_height else maxf(box.size.x, maxf(box.size.y, box.size.z))
	if measure <= 0.0001:
		return
	var s := target / measure
	model.scale *= s
	var center := box.get_center()
	model.position -= Vector3(center.x, box.position.y, center.z) * s


## Bounds of every mesh under `root`, in `root`'s parent space. Works before
## the node is in the tree.
static func model_bounds(root: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		var xform := mesh_node.transform
		var up := mesh_node.get_parent()
		while up != null and up != root.get_parent():
			if up is Node3D:
				xform = (up as Node3D).transform * xform
			up = up.get_parent()
		var box := xform * mesh_node.get_aabb()
		out = box if first else out.merge(box)
		first = false
	return out


## Swaps a model's clean pack materials for worn ones that keep its colors.
func _weather_model(model: Node3D, wear: float, metal: float) -> void:
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh == null:
			continue
		for i in mesh_node.mesh.get_surface_count():
			var source := mesh_node.get_active_material(i) as BaseMaterial3D
			if source == null:
				continue
			mesh_node.set_surface_override_material(i, _worn(source, wear, metal))


func _worn(source: BaseMaterial3D, wear: float, metal: float) -> ShaderMaterial:
	var key := "%d/%.2f/%.2f" % [source.get_instance_id(), wear, metal]
	if _gear_materials.has(key):
		return _gear_materials[key]
	var mat := ShaderMaterial.new()
	mat.shader = GEAR_SHADER
	if source.albedo_texture:
		mat.set_shader_parameter("base_tex", source.albedo_texture)
	mat.set_shader_parameter("base_color", source.albedo_color)
	if source.emission_enabled:
		mat.set_shader_parameter("emission_color", source.emission * source.emission_energy_multiplier)
	var dir := TEXTURES + "Metal063/"
	mat.set_shader_parameter("grime_albedo", load(dir + "Color.jpg"))
	mat.set_shader_parameter("grime_rough", load(dir + "Roughness.jpg"))
	mat.set_shader_parameter("wear", wear)
	mat.set_shader_parameter("metal", metal)
	_bind_storm(mat)
	_gear_materials[key] = mat
	return mat


# --- Dressing what the game spawns -----------------------------------------------

func _dress_actor(actor: Actor) -> void:
	if not is_instance_valid(actor) or actor.has_node("Skin"):
		return
	var skin := ActorSkin.new()
	skin.name = "Skin"
	skin.look = self
	skin.actor = actor
	actor.add_child(skin)
	_show_between_ticks(actor)


## Shows `body` smoothly between physics ticks (`ShownMotion`).
func _show_between_ticks(body: Node3D) -> void:
	if is_instance_valid(body) and not body.has_node("ShownMotion"):
		var motion := ShownMotion.new()
		motion.name = "ShownMotion"
		body.add_child(motion)


## Gives an actor a chosen appearance (see `human.gd`), now or before it is
## dressed. Cosmetic only, and safe on a headless server, where it just
## records the choice so it can be sent on to clients.
func set_appearance(actor: Actor, appearance: Variant) -> void:
	actor.set_meta("appearance", Human.sanitize(appearance))
	var old := actor.get_node_or_null("Skin")
	if not enabled or old == null:
		return
	old.name = "OldSkin"
	old.queue_free()
	_dress_actor(actor)


## The model a skin wears, with its materials made: {"model": Node3D,
## "materials": Array[ShaderMaterial], "chosen": the person's appearance (empty
## for a skin that is not a person)}, or {} when the art is missing.
## `appearance` only matters for skins of people; `who` picks a steady random
## look for anyone who has not chosen one, dressed in `uniform` ("top" and
## "bottom" `Human.CLOTH_COLORS` indices, an army's) when one is given.
func character(skin_name: String, appearance: Dictionary = {}, who := "", uniform: Dictionary = {}) -> Dictionary:
	var def: Dictionary = SKINS.get(skin_name, SKINS[DEFAULT_SKIN])
	var model: Node3D
	var chosen := {}
	if def.has("people"):
		if not appearance.is_empty():
			chosen = Human.sanitize(appearance)
		else:
			chosen = Human.for_name(who, def["people"])
			if not uniform.is_empty():
				chosen.merge(uniform, true)
				chosen = Human.sanitize(chosen)
		model = Human.build(self, chosen)
	else:
		var scenes: Array = def["scenes"]
		model = _instance(CHARACTERS + scenes[hash(who) % scenes.size()])
	if model == null:
		return {}
	for hidden: String in def.get("hide", []):
		var node := model.find_child(hidden, true, false) as Node3D
		if node:
			node.visible = false
	var materials: Array[ShaderMaterial] = []
	for node in model.find_children("*", "MeshInstance3D", true, false):
		materials.append_array(dress_surfaces(node as MeshInstance3D, def, chosen))
	return {"model": model, "materials": materials, "chosen": chosen}


## Gives each surface of a character's `mesh_node` its own
## `character.gdshader` material, made from the surface's pack material, and
## returns them. `def` is the skin's entry in `SKINS`; `chosen`, a person's
## appearance (empty for a skin that is not a person).
func dress_surfaces(mesh_node: MeshInstance3D, def: Dictionary, chosen: Dictionary) -> Array[ShaderMaterial]:
	var materials: Array[ShaderMaterial] = []
	var tint: Color = def.get("tint", Color.WHITE)
	for i in mesh_node.mesh.get_surface_count():
		var source := mesh_node.get_active_material(i) as BaseMaterial3D
		if source == null:
			continue
		var mat := ShaderMaterial.new()
		mat.shader = CHARACTER_SHADER
		if source.albedo_texture:
			mat.set_shader_parameter("base_tex", source.albedo_texture)
		mat.set_shader_parameter("base_color", source.albedo_color)
		mat.set_shader_parameter("tint", tint)
		for param: String in ["saturation", "brightness", "metal", "rough"]:
			if def.has(param):
				mat.set_shader_parameter(param, def[param])
		if source.emission_enabled:
			mat.set_shader_parameter("emission_color", source.emission * 2.5)
		_bind_storm(mat)
		if not chosen.is_empty():
			var slot: String = mesh_node.get_meta("slot", "")
			if source.normal_enabled and source.normal_texture:
				mat.set_shader_parameter("normal_tex", source.normal_texture)
				mat.set_shader_parameter("normal_amount", 1.0)
			if source.roughness_texture:
				mat.set_shader_parameter("rough_tex", source.roughness_texture)
				mat.set_shader_parameter("rough_from_tex", 1.0)
			mat.set_shader_parameter("has_rest", 1.0)
			var kind := Human.surface_kind(slot, source.resource_name)
			mat.set_shader_parameter("surface_kind", kind)
			var pick := Human.color_for(chosen, slot, source.resource_name)
			if pick.has("color"):
				mat.set_shader_parameter("recolor", pick["color"])
				mat.set_shader_parameter("recolor_amount", 1.0)
				mat.set_shader_parameter("recolor_shading", 1.0 if pick["keep_shading"] else 0.0)
			var iris: Variant = Human.iris_for(chosen)
			if kind == 3 and iris != null:
				mat.set_shader_parameter("iris_color", iris)
				mat.set_shader_parameter("iris_amount", 1.0)
			var suit := Human.suit_for(chosen, slot)
			if kind == 2 and not suit.is_empty():
				# The tactical suit: `ActorSkin._wear_undersuit` recolours it
				# under a frame and gives this back.
				mat.set_meta("own_suit", suit)
				mat.set_meta("suit_slot", slot)
				mat.set_shader_parameter("suit", 1.0)
				mat.set_shader_parameter("suit_color", suit["color"])
				mat.set_shader_parameter("suit_trim", suit["trim"])
				mat.set_shader_parameter("suit_pattern", suit.get("pattern", 0))
		mesh_node.set_surface_override_material(i, mat)
		materials.append(mat)
	return materials


## Scales a character model to `height` meters and puts its feet at the
## origin of `holder`, the node it sits under, going by where the skeleton's
## bones are in the current pose. Mesh bounds are no use here: skinned meshes
## report their unposed size.
func stand_model(holder: Node3D, model: Node3D, height: float) -> void:
	var skeleton := model.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		_fit(model, "skin:" + model.name, height, true)
		return
	var to_holder := holder.global_transform.affine_inverse() * skeleton.global_transform
	var low := INF
	var high := -INF
	for i in skeleton.get_bone_count():
		var y := (to_holder * skeleton.get_bone_global_pose(i).origin).y
		low = minf(low, y)
		high = maxf(high, y)
	if high - low < 0.001:
		return
	# Bones stop at the ankle and the base of the head; allow for both ends.
	var s := height / ((high - low) * 1.22)
	model.scale *= s
	model.position.y = -low * s + height * 0.06


## A valid appearance from anything a save file or a client hands over.
func clean_appearance(raw: Variant, owned: Array = []) -> Dictionary:
	return Human.player_look(raw, owned)


## Power weapons are sci-fi through and through: dark armoured bodies
## with glowing coils, cells and vents in the weapon's own colour
## (`Gun.tracer_color`). Built from shapes, picked by tag, pointing along -Z.
func _power_model(gun: Gun) -> Node3D:
	# The house finish the guns share (`_dress_gun`): graphite frames,
	# ceramic shells and the weapon's own light in coils and cells.
	var glow: Color = gun.tracer_color
	var body := _power_mat(GUN_FRAME, 0.55, 0.4)
	var shell := _power_mat(GUN_SHELL.darkened(0.08), 0.1, 0.45)
	var trim := _power_mat(Color(0.42, 0.45, 0.5), 0.75, 0.3)
	var lit := _power_mat(glow, 0.0, 0.4, glow, 1.4)
	var holder := Node3D.new()
	holder.name = "Model"
	var tags: Array = ItemDB.get_item(gun.item_id).get("tags", [])
	if "railgun" in tags:
		# Rail Lance: a ceramic-shelled receiver, a capacitor bank on top,
		# and two long rails with charge coils and a lit spine between them.
		_power_box(holder, Vector3(0.09, 0.12, 0.5), Vector3(0, -0.02, 0.0), body)
		_power_box(holder, Vector3(0.1, 0.05, 0.4), Vector3(0, 0.055, -0.02), shell)
		_power_box(holder, Vector3(0.06, 0.1, 0.2), Vector3(0, -0.03, 0.33), body)
		_power_box(holder, Vector3(0.064, 0.04, 0.16), Vector3(0, 0.03, 0.33), shell)
		for i in 3:
			_power_box(holder, Vector3(0.03, 0.022, 0.05), Vector3(0, 0.09, -0.12 + i * 0.07), lit)
		for side in [-1.0, 1.0]:
			_power_box(holder, Vector3(0.025, 0.06, 0.85), Vector3(0.045 * side, 0.02, -0.55), trim)
			_power_box(holder, Vector3(0.028, 0.02, 0.8), Vector3(0.045 * side, 0.058, -0.53), shell)
			_power_box(holder, Vector3(0.03, 0.03, 0.04), Vector3(0.045 * side, 0.02, -0.99), lit)
			_power_box(holder, Vector3(0.004, 0.012, 0.3), Vector3(0.052 * side, -0.01, 0.02), lit)
		for i in 6:
			_power_box(holder, Vector3(0.07, 0.07, 0.022), Vector3(0, 0.02, -0.28 - i * 0.12), lit)
		_power_cyl(holder, 0.008, 0.72, Vector3(0, 0.02, -0.6), lit)
		_power_grip(holder, Vector3(0.05, 0.14, 0.08), Vector3(0, -0.14, 0.08), body, Vector3(0, -0.075, -0.2))
		_power_box(holder, Vector3(0.05, 0.03, 0.14), Vector3(0, -0.095, -0.2), shell)
	elif "launcher" in tags:
		# Helion: a ceramic plasma tube banded in graphite, a lit vent at the
		# mouth and the exhaust, a sight box and a battery along its side.
		_power_cyl(holder, 0.085, 0.85, Vector3(0, 0.02, -0.25), shell)
		for z: float in [-0.6, -0.25, 0.1]:
			_power_cyl(holder, 0.092, 0.05, Vector3(0, 0.02, z), body)
		_power_cyl(holder, 0.075, 0.03, Vector3(0, 0.02, -0.675), lit)
		_power_cyl(holder, 0.07, 0.03, Vector3(0, 0.02, 0.17), lit)
		_power_box(holder, Vector3(0.05, 0.05, 0.14), Vector3(-0.06, 0.12, -0.05), body)
		_power_box(holder, Vector3(0.03, 0.02, 0.02), Vector3(-0.06, 0.12, -0.125), lit)
		_power_box(holder, Vector3(0.03, 0.06, 0.4), Vector3(0.095, 0.0, -0.25), body)
		_power_box(holder, Vector3(0.006, 0.02, 0.34), Vector3(0.112, 0.0, -0.25), lit)
		_power_grip(holder, Vector3(0.05, 0.14, 0.07), Vector3(0, -0.12, -0.05), body, Vector3(0, -0.06, -0.38))
		_power_box(holder, Vector3(0.04, 0.09, 0.05), Vector3(0, -0.09, -0.38), body)
	elif "grenade_launcher" in tags:
		# Arc Mortar: a short fat barrel ringed with coils over a lit drum of
		# arc charges half sheathed in ceramic, and a stub stock.
		_power_box(holder, Vector3(0.08, 0.1, 0.45), Vector3(0, 0.0, -0.15), body)
		_power_box(holder, Vector3(0.09, 0.04, 0.32), Vector3(0, 0.06, -0.1), shell)
		_power_cyl(holder, 0.05, 0.35, Vector3(0, 0.05, -0.45), trim)
		_power_cyl(holder, 0.06, 0.04, Vector3(0, 0.05, -0.62), body)
		for i in 3:
			_power_cyl(holder, 0.056, 0.012, Vector3(0, 0.05, -0.36 - i * 0.07), lit)
		var drum := _power_cyl(holder, 0.1, 0.12, Vector3(0, -0.06, -0.12), _power_mat(glow.darkened(0.3), 0.0, 0.4, glow, 0.7))
		drum.rotation = Vector3(0, 0, PI / 2.0)
		for side in [-1.0, 1.0]:
			var cover := _power_cyl(holder, 0.075, 0.01, Vector3(0.062 * side, -0.06, -0.12), shell)
			cover.rotation = Vector3(0, 0, PI / 2.0)
		_power_box(holder, Vector3(0.06, 0.08, 0.16), Vector3(0, -0.01, 0.15), body)
		_power_box(holder, Vector3(0.065, 0.03, 0.12), Vector3(0, 0.04, 0.16), shell)
		_power_grip(holder, Vector3(0.05, 0.14, 0.07), Vector3(0, -0.13, 0.08), body, Vector3(0, -0.045, -0.3))
	else:
		# Storm Cannon: a ring of barrels round a lit core, clamped by
		# ceramic collars, a motor housing behind and a cell on its side.
		_power_box(holder, Vector3(0.16, 0.16, 0.36), Vector3(0, 0, 0.0), body)
		_power_box(holder, Vector3(0.17, 0.08, 0.3), Vector3(0, 0.05, 0.02), shell)
		for i in 6:
			var a := TAU * i / 6.0
			_power_cyl(holder, 0.022, 0.7, Vector3(cos(a) * 0.065, sin(a) * 0.065, -0.5), trim)
		_power_cyl(holder, 0.03, 0.72, Vector3(0, 0, -0.5), lit)
		_power_cyl(holder, 0.11, 0.05, Vector3(0, 0, -0.25), lit)
		_power_cyl(holder, 0.105, 0.04, Vector3(0, 0, -0.55), shell)
		_power_cyl(holder, 0.1, 0.03, Vector3(0, 0, -0.84), body)
		_power_box(holder, Vector3(0.18, 0.06, 0.2), Vector3(0, 0.12, 0.05), trim)
		_power_box(holder, Vector3(0.06, 0.12, 0.16), Vector3(0.11, -0.02, 0.0), body)
		_power_box(holder, Vector3(0.006, 0.08, 0.12), Vector3(0.143, -0.02, 0.0), lit)
		_power_grip(holder, Vector3(0.05, 0.14, 0.07), Vector3(0, -0.14, 0.1), body, Vector3(0, -0.085, -0.12))
	return holder


## A power weapon's hand grip, a box hanging under it, and the "Grip" and
## "Trigger" markers where the gun hand closes on it (see `_measure_hold`),
## and the "ForeGrip" marker at `fore`, where the off hand holds it.
func _power_grip(holder: Node3D, size: Vector3, at: Vector3, mat: Material, fore: Vector3) -> void:
	_power_box(holder, size, at, mat)
	var support := Marker3D.new()
	support.name = "ForeGrip"
	support.position = fore
	holder.add_child(support)
	var hold := Marker3D.new()
	hold.name = "Grip"
	hold.position = at + Vector3(0.0, size.y * 0.5 - 0.035, 0.0)
	hold.set_meta("up", Vector3.UP)
	holder.add_child(hold)
	var trigger := Marker3D.new()
	trigger.name = "Trigger"
	trigger.position = hold.position + Vector3(0.0, 0.0, -size.z * 0.5 - 0.015)
	holder.add_child(trigger)


func _power_mat(color: Color, metal: float, rough: float, glow := Color.BLACK,
		glow_energy := 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metal
	mat.roughness = rough
	if glow_energy > 0.0:
		mat.emission_enabled = true
		mat.emission = glow
		mat.emission_energy_multiplier = glow_energy
		# The coils stay readable through a storm. The dark body still fogs.
		mat.disable_fog = true
	return mat


func _power_box(parent: Node3D, size: Vector3, at: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = mat
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.position = at
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(part)
	return part


## A cylinder lying along -Z (the barrel direction).
func _power_cyl(parent: Node3D, radius: float, length: float, at: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = 12
	mesh.material = mat
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.position = at
	part.rotation = Vector3(PI / 2.0, 0, 0)
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(part)
	return part


## The model for a held weapon, or null to keep the greybox one.
func weapon_model(weapon: Weapon) -> Node3D:
	if weapon is MeleeWeapon:
		return _melee_model(weapon)
	if not weapon is Gun:
		return null
	if weapon.item_id != "" and ItemDB.has_tag(weapon.item_id, "power"):
		return _power_model(weapon as Gun)
	var file := DEFAULT_GUN
	var length := GUN_LENGTH
	for entry: Array in GUN_MODELS:
		if weapon.item_id != "" and ItemDB.has_tag(weapon.item_id, entry[0]):
			file = entry[1]
			length = entry[2] if entry.size() > 2 else GUN_LENGTH
			break
	var model := _instance(WEAPONS + file)
	if model == null:
		return null
	var holder := Node3D.new()
	holder.name = "Model"
	holder.add_child(model)
	_fit(model, WEAPONS + file, length, false)
	for entry: Array in GUN_GLOW:
		if weapon.item_id != "" and ItemDB.has_tag(weapon.item_id, entry[0]):
			var scrap := ItemDB.has_tag(weapon.item_id, "starter") and not ItemDB.has_tag(weapon.item_id, "sidearm")
			_dress_gun(model, entry[1], scrap)
			_energize(model, holder, entry[1])
			_gun_kit(holder, model, weapon.item_id, entry[1], scrap)
			break
	_weather_model(model, 0.8 if weapon.item_id == "" else 0.5, 0.75)
	# The packs point guns along +X. Hands hold them pointing along -Z.
	holder.rotation.y = PI / 2.0
	holder.position = Vector3(0, -0.1, -0.08)
	holder.set_meta("gun_file", file)
	holder.set_meta("gun_length", length)
	return holder


## Moves a gun's attachments (the "Attachments" child of `visual`, see
## `Gun.build_attachment`) from the greybox mounts onto its real model (the
## "Model" child that `weapon_model` built). Safe to call more than once.
func mount_attachments(visual: Node3D) -> void:
	var fitted := visual.get_node_or_null("Attachments") as Node3D
	var model := visual.get_node_or_null("Model") as Node3D
	if model == null or not model.has_meta("gun_file"):
		return
	var file: String = model.get_meta("gun_file")
	# One model is used at more than one size (two pistols), so it is
	# measured once per size.
	var key := "%s@%.3f" % [file, float(model.get_meta("gun_length", GUN_LENGTH))]
	if not _gun_mounts.has(key):
		_gun_mounts[key] = _measure_mounts(model, GUN_MOUNTS.get(file, GUN_MOUNTS[DEFAULT_GUN]))
	var mounts: Dictionary = _gun_mounts[key]
	if fitted != null:
		for part in fitted.get_children():
			if part is Node3D and mounts.has(part.name):
				(part as Node3D).position = mounts[part.name]
				part.set_meta("mounted", true)
	_place_muzzle(visual, fitted, mounts)
	if fitted == null:
		return
	# An optic raised to see over the front sight stands on a riser.
	var optic := fitted.get_node_or_null("optic") as Node3D
	if optic and mounts.has("rail") and not optic.has_node("Riser"):
		var rise: float = optic.position.y - float(mounts["rail"])
		if rise > 0.003:
			var riser := Weapon.make_part(Vector3(0.026, rise, 0.07), Vector3(0, -rise * 0.5, 0), Color(0.1, 0.11, 0.13))
			riser.name = "Riser"
			optic.add_child(riser)
	# Each attachment's plain parts as one mesh per look: an optic is some
	# thirty boxes, a draw each in every pass for every gun in the world.
	# Named parts (its "Lens") and markers are left as they are.
	for part in fitted.get_children():
		if part is Node3D:
			merge_pieces(part as Node3D, true, true)


## Puts a "Muzzle" marker on the gun's visual where shots leave it: the front
## of the barrel, or of a fitted muzzle device. Muzzle flashes and tracers
## start there in both views (`Gun.muzzle_point`). A "ForeGrip" marker shows
## where the off hand holds it, and an "IronSight" marker where the eye looks
## along it.
func _place_muzzle(visual: Node3D, fitted: Node3D, mounts: Dictionary) -> void:
	if not mounts.has("muzzle"):
		return
	var at: Vector3 = mounts["muzzle"]
	var device := fitted.get_node_or_null("muzzle") as Node3D if fitted != null else null
	if device != null:
		var box := model_bounds(device)
		if box.size != Vector3.ZERO:
			at = fitted.transform * Vector3(box.get_center().x, box.get_center().y, box.position.z)
	_marker(visual, "Muzzle").position = at
	# The rear of the plain sights, where an eye looks along the gun when
	# aiming without an optic (`ActionPose.sight_local`): just over whatever
	# stands highest along the top, a little behind the optic's spot.
	if mounts.has("optic"):
		_marker(visual, "IronSight").position = (mounts["optic"] as Vector3) + Vector3(0.0, 0.012, 0.06)
		var optic := fitted.get_node_or_null("optic") as Node3D if fitted != null else null
		_iron_sights(visual, optic == null, _marker(visual, "IronSight").position, at)
	# Where the off hand holds the fore end, first person (the fore grip
	# mount, or a fitted grip).
	if mounts.has("grip"):
		var grip := fitted.get_node_or_null("grip") as Node3D if fitted != null else null
		_marker(visual, "ForeGrip").position = grip.position if grip != null else mounts.get("fore", mounts["grip"])
	# Where the gun hand closes on the pistol grip and which way the grip
	# runs, and the trigger, found from the model (`_measure_hold`).
	if mounts.has("hold"):
		var hold := _marker(visual, "Grip")
		hold.position = mounts["hold"]
		hold.set_meta("up", mounts["hold_up"])
		_marker(visual, "Trigger").position = mounts["trigger"]


## Plain sights on a long gun with no optic (playtest pass: aimed without
## one there was nothing to line up, only the top of the gun): a rear notch
## at the "IronSight" marker and a front post near the muzzle standing up to
## the same line, with a glowing dot on its tip, so aiming lays the dot in
## the notch on what you look at, in both views. An optic folds them away
## (real flip-up sights do the same).
func _iron_sights(visual: Node3D, shown: bool, rear: Vector3, muzzle: Vector3) -> void:
	var old := visual.get_node_or_null("IronSights")
	if old != null:
		old.free()
	if not shown:
		return
	var sights := Node3D.new()
	sights.name = "IronSights"
	visual.add_child(sights)
	var dark := Color(0.08, 0.09, 0.1)
	var parts: Array[MeshInstance3D] = []
	# The rear: two ears either side of the sight line over a base.
	for side in [-1.0, 1.0]:
		parts.append(Weapon.make_part(Vector3(0.006, 0.02, 0.01), rear + Vector3(side * 0.0095, -0.004, 0.0), dark))
	parts.append(Weapon.make_part(Vector3(0.026, 0.008, 0.012), rear + Vector3(0.0, -0.016, 0.0), dark))
	# The front post, a little behind the muzzle, from the barrel up to the
	# line, with its dot just under the top.
	var front_z := lerpf(muzzle.z, rear.z, 0.08)
	var low := minf(muzzle.y, rear.y - 0.03)
	var height := rear.y - low
	parts.append(Weapon.make_part(Vector3(0.004, height, 0.008), Vector3(0.0, low + height * 0.5, front_z), dark))
	# The dark parts share one material, so they draw as one mesh.
	var shared: Material = (parts[0].mesh as PrimitiveMesh).material
	for part in parts:
		(part.mesh as PrimitiveMesh).material = shared
	parts.append(Weapon.make_part(Vector3(0.004, 0.004, 0.004), Vector3(0.0, rear.y - 0.003, front_z - 0.005), GUN_GLOW[GUN_GLOW.size() - 1][1], true))
	for part in parts:
		sights.add_child(part)
	merge_pieces(sights)
	# A few millimetres of metal: past `iron_sight_reach` they are not drawn.
	for node in sights.get_children():
		var shape := node as GeometryInstance3D
		if shape != null:
			shape.visibility_range_end = iron_sight_reach


func _marker(visual: Node3D, marker_name: String) -> Marker3D:
	var marker := visual.get_node_or_null(marker_name) as Marker3D
	if marker == null:
		marker = Marker3D.new()
		marker.name = marker_name
		visual.add_child(marker)
	return marker


## Finds the attachment mounts on a gun model, in the space of its parent.
func _measure_mounts(model: Node3D, along: Dictionary) -> Dictionary:
	var points := PackedVector3Array()
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh == null or mesh_node.get_parent().name == "Kit":
			continue
		var xform := mesh_node.transform
		var up := mesh_node.get_parent()
		while up != null and up != model.get_parent():
			if up is Node3D:
				xform = (up as Node3D).transform * xform
			up = up.get_parent()
		for v in mesh_node.mesh.get_faces():
			points.append(xform * v)
	if points.is_empty():
		return {}
	var low := points[0]
	var high := points[0]
	for p in points:
		low = low.min(p)
		high = high.max(p)
	var length := high.z - low.z
	var height := high.y - low.y
	var mid_x := (low.x + high.x) * 0.5
	# The optic sits on whatever is highest around its spot.
	var optic_z := high.z - float(along.get("optic", 0.5)) * length
	var top := -INF
	# Sights further forward (a front post) must not block the optic's view.
	var ahead := -INF
	# The muzzle device goes on the middle of whatever is at the very front.
	var front_low := INF
	var front_high := -INF
	for p in points:
		if absf(p.z - optic_z) < length * 0.08:
			top = maxf(top, p.y)
		elif p.z < optic_z:
			ahead = maxf(ahead, p.y)
		if p.z < low.z + length * 0.03:
			front_low = minf(front_low, p.y)
			front_high = maxf(front_high, p.y)
	var out := {
		"optic": Vector3(mid_x, maxf(top if top > -INF else high.y, ahead + 0.004), optic_z),
		"rail": top if top > -INF else high.y,
		"muzzle": Vector3(mid_x, (front_low + front_high) * 0.5 if front_high > -INF else low.y + height * 0.7, low.z),
	}
	for slot: String in ["grip", "magazine"]:
		var spot: Array = along.get(slot, [0.6, 0.4])
		out[slot] = Vector3(mid_x, low.y + float(spot[1]) * height, high.z - float(spot[0]) * length)
	_measure_hold(points, low, high, out)
	return out


## Where the hands go on a gun model, read off its side outline (the mesh
## seen from the side, in squares a 160th of its length): the trigger guard is the
## hole low in the outline, the pistol grip the solid just behind it running
## down, and the fore end the underside some way ahead of the guard. Adds to
## `out` (all in the gun's visual space) "hold" (the grip's middle, level
## with the trigger, where the fist closes), "hold_up" (up along the grip),
## "trigger", and "fore" (where the off hand cups the fore end). Adds none
## when the outline has no trigger guard.
## How far ahead of the trigger the off hand reaches along a long gun, and
## how far under the fore end's underside the middle of its fist is.
const FORE_REACH := 0.26
const FORE_CUP := 0.015


func _measure_hold(points: PackedVector3Array, low: Vector3, high: Vector3, out: Dictionary) -> void:
	var size_cell := maxf((high.z - low.z) / 160.0, 0.0015)
	var nz := int((high.z - low.z) / size_cell) + 2
	var ny := int((high.y - low.y) / size_cell) + 2
	var cells := func(metres: float) -> int:
		return maxi(int(round(metres / size_cell)), 1)
	var solid := PackedByteArray()
	solid.resize(nz * ny)
	var cell := func(q: Vector3) -> Vector2:
		return Vector2((q.z - low.z) / size_cell, (q.y - low.y) / size_cell)
	for i in range(0, points.size() - 2, 3):
		var a: Vector2 = cell.call(points[i])
		var b: Vector2 = cell.call(points[i + 1])
		var c: Vector2 = cell.call(points[i + 2])
		var area := (b - a).cross(c - a)
		for corner: Vector2 in [a, b, c]:
			solid[clampi(int(corner.x), 0, nz - 1) * ny + clampi(int(corner.y), 0, ny - 1)] = 1
		if absf(area) < 0.0001:
			continue
		for z in range(maxi(int(minf(a.x, minf(b.x, c.x))), 0), mini(int(maxf(a.x, maxf(b.x, c.x))) + 1, nz)):
			for y in range(maxi(int(minf(a.y, minf(b.y, c.y))), 0), mini(int(maxf(a.y, maxf(b.y, c.y))) + 1, ny)):
				var q := Vector2(z + 0.5, y + 0.5)
				var u := (b - q).cross(c - q) / area
				var v := (c - q).cross(a - q) / area
				if u >= -0.02 and v >= -0.02 and 1.0 - u - v >= -0.02:
					solid[z * ny + y] = 1
	# Everything empty that the outside cannot reach is a hole.
	var mark := PackedInt32Array()
	mark.resize(nz * ny)
	var todo: Array[int] = []
	for z in nz:
		todo.append(z * ny)
		todo.append(z * ny + ny - 1)
	for y in ny:
		todo.append(y)
		todo.append((nz - 1) * ny + y)
	_flood(solid, mark, todo, nz, ny, -1)
	var holes: Array[Dictionary] = []
	for start in nz * ny:
		if solid[start] == 0 and mark[start] == 0:
			holes.append(_flood(solid, mark, [start], nz, ny, holes.size() + 1))
	# The guard: the front-most finger-sized hole low in the outline with a
	# grip behind it (on a bullpup the thumbhole behind the grip is a hole
	# too, and a bigger one).
	holes.sort_custom(func(p: Dictionary, q: Dictionary) -> bool: return p["front"] < q["front"])
	var mid_x: float = (out["muzzle"] as Vector3).x
	var to_space := func(z: float, yy: float) -> Vector3:
		return Vector3(mid_x, low.y + (yy + 0.5) * size_cell, low.z + (z + 0.5) * size_cell)
	var bore := int(((out["muzzle"] as Vector3).y - low.y) / size_cell)
	for guard in holes:
		var size: Vector2i = guard["size"]
		if size.x < cells.call(0.009) or size.y < cells.call(0.008) or size.x > cells.call(0.1) \
				or size.y > cells.call(0.07) or float(guard["top"]) > ny * 0.75:
			continue
		var grip := _trace_grip(solid, guard, nz, ny, cells)
		if grip.is_empty():
			continue
		var level: float = float(guard["top"] + guard["bottom"]) * 0.5
		# The fist closes behind the guard, never in it.
		var hold_z := maxf(grip["k"] * level + grip["m"], float(guard["back"]) + cells.call(0.012))
		out["hold"] = to_space.call(hold_z, level)
		out["hold_up"] = Vector3(0.0, 1.0, grip["k"]).normalized()
		out["trigger"] = to_space.call(float(guard["front"] + guard["back"]) * 0.5, level)
		# The fore end: the underside FORE_REACH ahead of the trigger, or
		# the front of the gun where it is shorter, the palm under the
		# barrel's own part of the outline (not a magazine hanging below).
		var fore_z := maxi(int(guard["front"]) - cells.call(FORE_REACH), cells.call(0.03))
		var under := clampi(bore, 0, ny - 1)
		# Down from the bore to the barrel or fore end's top, then to its
		# underside.
		while under > 0 and solid[fore_z * ny + under] == 0 and bore - under < cells.call(0.04):
			under -= 1
		if solid[fore_z * ny + under] == 1:
			while under > 0 and solid[fore_z * ny + under - 1] == 1 and bore - under < cells.call(0.08):
				under -= 1
			# The palm cups the underside, the fist's middle just under it.
			out["fore"] = to_space.call(fore_z, under - 0.5) + Vector3(0.0, -FORE_CUP, 0.0)
		return


## The pistol grip behind a trigger guard (a hole in the outline, see
## `_flood`), read row by row from the guard's top down: the line down its
## middle as z = k * y + m in cells, or empty where nothing runs down. Where
## the solid behind the guard runs on back (a stock's wrist, as on a pump
## gun), the hand closes just behind the guard and the grip leans back
## along the wrist's underside.
func _trace_grip(solid: PackedByteArray, guard: Dictionary, nz: int, ny: int, cells: Callable) -> Dictionary:
	var mids := PackedVector2Array()
	var unders := PackedVector2Array()
	var widest: int = cells.call(0.055)
	var from: int = int(guard["back"]) - cells.call(0.01)
	var last_back := -1
	var long := false
	for y in range(int(guard["top"]), maxi(int(guard["top"]) - cells.call(0.13), -1), -1):
		var z := from
		while z < nz - 1 and z <= from + cells.call(0.05) and solid[z * ny + y] == 0:
			z += 1
		if solid[z * ny + y] == 0:
			break
		var front := z
		while z < nz and solid[z * ny + y] == 1:
			z += 1
		if z - front > widest:
			long = true
			if y <= int(guard["bottom"]):
				unders.append(Vector2(front, y))
			from = front - cells.call(0.01)
			continue
		# Where the back edge jumps the grip has ended (or run into a stock).
		if last_back >= 0 and absi(z - last_back) > cells.call(0.02):
			break
		mids.append(Vector2((front + z) * 0.5, y))
		from = front - cells.call(0.01)
		last_back = z
	if long and mids.size() < 4 or mids.size() < 2:
		# A stock's wrist: the hand behind the guard, the grip leaning back
		# as the front of the solid behind the guard does below it.
		var k := -1.0
		if unders.size() >= 2:
			k = minf((unders[unders.size() - 1].x - unders[0].x) / minf(unders[unders.size() - 1].y - unders[0].y, -1.0), -0.3)
		var back: float = float(guard["back"]) + cells.call(0.022)
		return {"k": k, "m": back - k * float(guard["top"] + guard["bottom"]) * 0.5}
	# A line through the middles, by least squares.
	var sy := 0.0
	var sz := 0.0
	var syy := 0.0
	var syz := 0.0
	for r in mids:
		sy += r.y
		sz += r.x
		syy += r.y * r.y
		syz += r.y * r.x
	var count := float(mids.size())
	var k := (count * syz - sy * sz) / maxf(count * syy - sy * sy, 0.0001)
	# Grips rake back, from upright to about 40 degrees.
	k = clampf(k, -0.85, 0.0)
	return {"k": k, "m": (sz - k * sy) / count}


## Fills the connected empty cells from `todo` with `id` and returns the
## region's extent in cells.
func _flood(solid: PackedByteArray, mark: PackedInt32Array, todo: Array, nz: int, ny: int, id: int) -> Dictionary:
	var region := {"front": nz, "back": -1, "top": -1, "bottom": ny, "cells": 0}
	while not todo.is_empty():
		var at: int = todo.pop_back()
		if solid[at] == 1 or mark[at] != 0:
			continue
		mark[at] = id
		var z := at / ny
		var y := at % ny
		region["cells"] += 1
		region["front"] = mini(region["front"], z)
		region["back"] = maxi(region["back"], z)
		region["bottom"] = mini(region["bottom"], y)
		region["top"] = maxi(region["top"], y)
		if z > 0: todo.append(at - ny)
		if z < nz - 1: todo.append(at + ny)
		if y > 0: todo.append(at - 1)
		if y < ny - 1: todo.append(at + 1)
	region["size"] = Vector2i(region["back"] - region["front"] + 1, region["top"] - region["bottom"] + 1)
	return region


## The glowing emitter ring in `glow` on a gun's muzzle. `holder` is the
## model's parent; guns point along +X in it.
func _energize(model: Node3D, holder: Node3D, glow: Color) -> void:
	var box := model_bounds(model)
	var ring := MeshInstance3D.new()
	var tube := CylinderMesh.new()
	var radius := box.size.y * 0.07
	tube.top_radius = radius
	tube.bottom_radius = radius
	tube.height = box.size.x * 0.035
	tube.material = _gun_lit(glow, 1.6)
	ring.mesh = tube
	ring.name = "Emitter"
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.rotation.z = PI / 2.0
	ring.position = Vector3(box.end.x, box.position.y + box.size.y * 0.78, box.get_center().z)
	holder.add_child(ring)


## The house finish every gun shares (the weapon pass, to sit with the
## sci-fi armor, helmets and vehicles): a graphite frame, light ceramic
## shells over it, and the gun's role colour only in lit accent panels and
## trim, never a whole surface aglow. The scrap rifle's shells are worn tan
## and its light runs dim.
const GUN_FRAME := Color(0.1, 0.11, 0.125)
const GUN_SHELL := Color(0.92, 0.93, 0.9)
const SCRAP_SHELL := Color(0.47, 0.41, 0.33)
var gun_accent_glow := 0.5
var _gun_finishes := {}
var _gun_slices := {}


func _dress_gun(model: Node3D, glow: Color, scrap: bool) -> void:
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh == null:
			continue
		for i in mesh_node.mesh.get_surface_count():
			var source := mesh_node.get_active_material(i) as BaseMaterial3D
			if source == null:
				continue
			var key := "%d/%s/%s" % [source.get_instance_id(), glow.to_html(), scrap]
			if not _gun_finishes.has(key):
				_gun_finishes[key] = _gun_finish(source, glow, scrap)
			mesh_node.set_surface_override_material(i, _gun_finishes[key])


func _gun_finish(source: BaseMaterial3D, glow: Color, scrap: bool) -> BaseMaterial3D:
	var c := source.albedo_color
	var mat := source.duplicate() as BaseMaterial3D
	if c.r - c.b > 0.08 and c.r > 0.15:
		mat.albedo_color = glow.darkened(0.6 if scrap else 0.35)
		mat.emission_enabled = true
		mat.emission = glow
		mat.emission_energy_multiplier = gun_accent_glow * (0.3 if scrap else 1.0)
	elif c.get_luminance() > 0.4:
		mat.albedo_color = SCRAP_SHELL if scrap else GUN_SHELL
	else:
		mat.albedo_color = GUN_FRAME.lerp(c, 0.3)
	return mat


## A lit trim material in `glow`, kept readable through a storm.
func _gun_lit(glow: Color, energy: float) -> StandardMaterial3D:
	var key := "lit/%s/%.2f" % [glow.to_html(), energy]
	if not _gun_finishes.has(key):
		_gun_finishes[key] = _power_mat(glow.darkened(0.2), 0.0, 0.4, glow, energy)
	return _gun_finishes[key]


func _gun_plain(color: Color, metal: float, rough: float) -> StandardMaterial3D:
	var key := "plain/%s/%.2f/%.2f" % [color.to_html(), metal, rough]
	if not _gun_finishes.has(key):
		_gun_finishes[key] = _power_mat(color, metal, rough)
	return _gun_finishes[key]


## The gun's outline sliced along its length (in the holder's space, the gun
## lying along +X): for each of 40 slices the bottom, top, and the widest
## reach either side, read off its triangles. Kit parts stand on it.
func _gun_outline(model: Node3D, key: String) -> Array:
	if _gun_slices.has(key):
		return _gun_slices[key]
	var box := model_bounds(model)
	var n := 40
	var out := []
	for i in n:
		out.append(Vector4(INF, -INF, INF, -INF))
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh == null:
			continue
		var xform := mesh_node.transform
		var up := mesh_node.get_parent()
		while up != null and up != model.get_parent():
			if up is Node3D:
				xform = (up as Node3D).transform * xform
			up = up.get_parent()
		var faces := mesh_node.mesh.get_faces()
		for f in range(0, faces.size(), 3):
			var a := xform * faces[f]
			var b := xform * faces[f + 1]
			var c := xform * faces[f + 2]
			var lo := mini(n - 1, maxi(0, int((minf(a.x, minf(b.x, c.x)) - box.position.x) / box.size.x * n)))
			var hi := mini(n - 1, maxi(0, int((maxf(a.x, maxf(b.x, c.x)) - box.position.x) / box.size.x * n)))
			for s in range(lo, hi + 1):
				var v: Vector4 = out[s]
				out[s] = Vector4(minf(v.x, minf(a.y, minf(b.y, c.y))), maxf(v.y, maxf(a.y, maxf(b.y, c.y))),
						minf(v.z, minf(a.z, minf(b.z, c.z))), maxf(v.w, maxf(a.z, maxf(b.z, c.z))))
	_gun_slices[key] = out
	return out


## What makes each gun its own on top of the finish: parts that hang under a
## "Kit" node, which measuring skips (`_measure_mounts`), so they never move
## a grip, a sight or the muzzle. Placed on the gun's outline
## (`_gun_outline`) by how far along it they go, 0 at the stock and 1 at the
## muzzle. View only.
func _gun_kit(holder: Node3D, model: Node3D, item_id: String, glow: Color, scrap: bool) -> void:
	var kit := Node3D.new()
	kit.name = "Kit"
	holder.add_child(kit)
	var box := model_bounds(model)
	var outline := _gun_outline(model, "%s@%.3f" % [model.scene_file_path, box.size.x])
	var length := box.size.x
	var x_at := func(along: float) -> float:
		return box.position.x + length * along
	var slice := func(along: float) -> Vector4:
		return outline[clampi(int(along * outline.size()), 0, outline.size() - 1)]
	var frame := _gun_plain(GUN_FRAME, 0.6, 0.4)
	var shell := _gun_plain(SCRAP_SHELL if scrap else GUN_SHELL, 0.1, 0.5)
	var lit := _gun_lit(glow, 0.3 if scrap else 1.5)
	var tags: Array = ItemDB.get_item(item_id).get("tags", [])
	var mid_z := box.get_center().z
	# The barrel's line, from the front slice.
	var front: Vector4 = slice.call(0.99)
	var bore := Vector3(box.end.x, (front.x + front.y) * 0.5, (front.z + front.w) * 0.5)
	var bore_r := maxf((front.y - front.x) * 0.5, 0.006)
	if scrap:
		# Scrap: tape wound round the fore end and a patch plate riveted on
		# the side, the same make-do as the scrap blade.
		var tape := _gun_plain(Color(0.16, 0.15, 0.13), 0.0, 0.9)
		for along: float in [0.66, 0.7]:
			var s: Vector4 = slice.call(along)
			_power_box(kit, Vector3(0.012, s.y - s.x + 0.004, s.w - s.z + 0.004),
					Vector3(x_at.call(along), (s.x + s.y) * 0.5, (s.z + s.w) * 0.5), tape)
		var s2: Vector4 = slice.call(0.45)
		var patch := _power_box(kit, Vector3(0.07, (s2.y - s2.x) * 0.35, 0.004),
				Vector3(x_at.call(0.45), s2.x + (s2.y - s2.x) * 0.62, s2.w + 0.002), _gun_plain(Color(0.5, 0.5, 0.52), 0.7, 0.6))
		patch.rotation.z = 0.12
		for dx: float in [-0.026, 0.026]:
			_power_box(kit, Vector3(0.007, 0.007, 0.004), patch.position + Vector3(dx, dx * 0.12, 0.003), frame)
		return
	if "shotgun" in tags:
		# Breacher: a wide choke round the bore with a lit ring inside, and a
		# side carrier of four lit shells.
		_kit_cyl(kit, bore_r * 1.5, 0.03, bore + Vector3(-0.02, 0, 0), frame)
		_kit_cyl(kit, bore_r * 1.18, 0.032, bore + Vector3(-0.02, 0, 0), lit)
		var s: Vector4 = slice.call(0.42)
		for i in 4:
			var shell_at := Vector3(x_at.call(0.36) + i * 0.028, s.x + (s.y - s.x) * 0.55, s.w + 0.009)
			var round_part := _kit_cyl(kit, 0.009, 0.05, shell_at, lit)
			round_part.rotation = Vector3(0, 0, 0)
		_power_box(kit, Vector3(0.13, 0.016, 0.006), Vector3(x_at.call(0.36) + 0.042, s.x + (s.y - s.x) * 0.55 - 0.03, s.w + 0.004), shell)
	elif "marksman" in tags:
		# Longshot: charge coils round the barrel ahead of the fore end.
		for i in 4:
			_kit_cyl(kit, bore_r + 0.006, 0.008, bore - Vector3(length * (0.07 + i * 0.03), 0, 0), lit)
	elif "smg" in tags:
		# Stinger: a vented shroud over the barrel, lit through its slots.
		_kit_cyl(kit, bore_r + 0.01, length * 0.1, bore - Vector3(length * 0.08, 0, 0), frame)
		for i in 3:
			_kit_cyl(kit, bore_r + 0.012, 0.006, bore - Vector3(length * (0.05 + i * 0.025), 0, 0), lit)
	elif "hand_cannon" in tags:
		# Warden: a heavy cell drum in the frame and a lit slot down the
		# barrel's top.
		var s: Vector4 = slice.call(0.5)
		var drum_at := Vector3(x_at.call(0.5), s.x + (s.y - s.x) * 0.7, mid_z)
		var drum := _kit_cyl(kit, (s.y - s.x) * 0.24, 0.05, drum_at, frame)
		drum.rotation = Vector3.ZERO
		drum.rotation.x = PI / 2.0
		for side in [-1.0, 1.0]:
			var face := _kit_cyl(kit, (s.y - s.x) * 0.15, 0.004, drum_at + Vector3(0, 0, side * 0.026), lit)
			face.rotation = Vector3(PI / 2.0, 0, 0)
		var t: Vector4 = slice.call(0.8)
		_power_box(kit, Vector3(length * 0.3, 0.004, 0.012), Vector3(x_at.call(0.78), t.y + 0.001, mid_z), lit)
	elif "machine_pistol" in tags:
		_kit_cyl(kit, bore_r + 0.006, 0.008, bore - Vector3(length * 0.06, 0, 0), lit)
	elif "rifle" in tags:
		# Carbine: a lit power cell set in a ceramic housing on each side.
		var s: Vector4 = slice.call(0.6)
		for side in [-1.0, 1.0]:
			var face := s.w if side > 0.0 else s.z
			var y := s.x + (s.y - s.x) * 0.55
			_power_box(kit, Vector3(length * 0.16, (s.y - s.x) * 0.26, 0.006), Vector3(x_at.call(0.6), y, face + side * 0.002), shell)
			_power_box(kit, Vector3(length * 0.12, 0.007, 0.008), Vector3(x_at.call(0.6), y, face + side * 0.003), lit)
	elif "sidearm" in tags:
		# Service pistol: a lit status strip on each side of the slide.
		var s: Vector4 = slice.call(0.7)
		for side in [-1.0, 1.0]:
			var face := s.w if side > 0.0 else s.z
			_power_box(kit, Vector3(length * 0.25, 0.004, 0.003), Vector3(x_at.call(0.7), s.y - (s.y - s.x) * 0.25, face + side * 0.001), lit)


## A cylinder lying along the gun (+X in the holder's space).
func _kit_cyl(parent: Node3D, radius: float, length: float, at: Vector3, mat: Material) -> MeshInstance3D:
	var part := _power_cyl(parent, radius, length, at, mat)
	part.rotation = Vector3(0, 0, PI / 2.0)
	return part


## Melee models stand along +Y with the handle down, the way the greybox
## blade is built, so the weapon's own windup, swing and guard poses carry over.
func _melee_model(weapon: Weapon) -> Node3D:
	var pick := _melee_pick(weapon)
	if pick[1] == "":
		var spear := _spear_model(pick[2], pick[3], energy_color(weapon.item_id), energy_strength(weapon.item_id))
		var head := spear.get_node("Spear") as Node3D
		head.transform = Transform3D(strike_turn(pick[6]), Vector3.ZERO) * head.transform
		# Its grip is wrapped where the weapon hand goes, so it keeps that spot.
		_fit_hands(spear, "spear@%.2f" % pick[2], is_two_handed(weapon), pick[3])
		return spear
	var model := _instance(WEAPONS + pick[1])
	if model == null:
		return null
	var holder := Node3D.new()
	holder.name = "Model"
	holder.add_child(model)
	_fit(model, WEAPONS + pick[1], pick[2], true)
	# Turned about its length so its striking face leads every swing.
	var turn := strike_turn(pick[6])
	model.transform = Transform3D(turn, Vector3.ZERO) * model.transform
	holder.position.y = -pick[3]
	var key := "%s@%.2f" % [pick[1], pick[2]]
	_fit_hands(holder, key, is_two_handed(weapon))
	if is_two_handed(weapon) and not holder.has_meta("off_grip"):
		# No handle read off the shape (the katana's runs into its blade with
		# no guard to mark it): the off hand closes a hand's width under the
		# table grip, which sits `pick[3]` above the pommel.
		holder.set_meta("off_grip", -minf(HAND_WIDTH, pick[3] - HAND_WIDTH * 0.3))
	var scrap := ItemDB.has_tag(weapon.item_id, "starter")
	if scrap:
		_scrap_bits(holder, _handles.get(key, {}), turn)
	if ItemDB.has_tag(weapon.item_id, "hookblade"):
		_hook_bits(holder, _handles.get(key, {}), turn, pick[2])
	# Scrap runs dim and worn: a faint edge on beaten metal.
	_tech_melee(holder, energy_color(weapon.item_id), energy_strength(weapon.item_id) * (scrap_energy if scrap else 1.0),
			scrap_wear if scrap else (0.7 if weapon.item_id == "" else 0.3), {"mode": pick[4]},
			not ItemDB.has_tag(weapon.item_id, "hammer"))
	return holder


## How a melee model is turned about its length (+Y) so the striking face
## it has in its own space (`face`, the last field of `MELEE_MODELS`) points
## along `STRIKE_FACE`.
static func strike_turn(face: Vector3) -> Basis:
	var across := Vector3(face.x, 0.0, face.z)
	if across.length() < 0.001:
		return Basis.IDENTITY
	var angle := Vector2(across.x, across.z).angle_to(Vector2(STRIKE_FACE.x, STRIKE_FACE.z))
	# A turn of the XZ plane by `angle` is a turn about +Y the other way.
	return Basis(Vector3.UP, -angle)


## The scrap kit's blade is a sword made from scrap (Caleb's call): welded
## patch plates and rivets on the blade, wire wound round the grip, tape on
## the guard and a hex nut for a pommel, on the plain sword model. Built
## after the hands are fitted, so the bits never move the grip, and before
## it is dressed, so they fold away with the blade and take its finish.
## `handle` is the model's measured handle (`_measure_handle`); with none
## found the model is left plain.
var scrap_blade_width := 0.04
var scrap_blade_thick := 0.008
var scrap_grip_radius := 0.016
var scrap_energy := 0.4
var scrap_wear := 0.95

func _scrap_bits(holder: Node3D, handle: Dictionary, turn := Basis.IDENTITY) -> void:
	if handle.is_empty():
		return
	var bits := Node3D.new()
	bits.name = "Scrap"
	holder.add_child(bits)
	# Built across the pack model's own flat, then turned with it.
	bits.basis = turn
	var flat := turn.inverse() * Vector3(handle["centre"].x, 0.0, handle["centre"].y)
	var centre := Vector2(flat.x, flat.z)
	var guard: float = handle["top"]
	var bottom: float = handle["bottom"]
	var at := func(y: float, x := 0.0) -> Vector3:
		return Vector3(centre.x + x, y, centre.y)
	var plate := StandardMaterial3D.new()
	plate.albedo_color = Color(0.55, 0.55, 0.57)
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.62, 0.62, 0.64)
	var wire := StandardMaterial3D.new()
	wire.albedo_color = Color(0.14, 0.13, 0.12)
	var w := scrap_blade_width
	var t := scrap_blade_thick
	# Patch plates welded on crooked, each held by a pair of rivets.
	# (height up the blade, tilt, height of the plate, shift across)
	for patch: Array in [[0.08, 0.3, 0.04, 0.25], [0.24, -0.25, 0.03, -0.28], [0.37, 0.2, 0.026, 0.2]]:
		var y: float = guard + patch[0]
		var shift: float = w * patch[3]
		var piece := _scrap_box(bits, Vector3(w * 0.6, patch[2], t * 1.8), at.call(y, shift), plate)
		piece.rotation.z = patch[1]
		for side in [-1.0, 1.0]:
			var off := Vector3(side * w * 0.2, 0.0, 0.0).rotated(Vector3.BACK, patch[1])
			_scrap_box(bits, Vector3(0.007, 0.007, t * 2.4), at.call(y + off.y, shift + off.x), steel)
	# Wire wound round the grip, and tape over one arm of the guard.
	var span := guard - bottom
	for i in 4:
		var ring := MeshInstance3D.new()
		var mesh := _cylinder(scrap_grip_radius, 0.006)
		mesh.material = wire
		ring.mesh = mesh
		ring.position = at.call(bottom + span * (0.2 + 0.2 * i))
		ring.rotation.z = 0.15 if i % 2 == 0 else -0.15
		bits.add_child(ring)
	_scrap_box(bits, Vector3(0.03, 0.02, t * 3.0), at.call(guard - 0.005, w * 0.8), wire)
	# A hex nut threaded on for a pommel.
	var nut := MeshInstance3D.new()
	var hex := _cylinder(scrap_grip_radius * 1.2, 0.018)
	hex.radial_segments = 6
	hex.material = steel
	nut.mesh = hex
	nut.position = at.call(bottom - 0.004)
	bits.add_child(nut)


## The Marsh Hookblade is a one-handed sword whose point curls back over
## the spine into a hook (what its trip catches an ankle with), built on the
## plain sword model like the scrap blade's bits: after the hands are fitted
## and before it is dressed, so it takes the blade's finish. `length` is the
## model's length up from the pommel; `hook_radius` sizes the curl and
## `hook_barb` how far its end hangs back down beside the blade.
var hook_radius := 0.055
var hook_barb := 0.05
var hook_width := 0.02
var hook_thick := 0.008

func _hook_bits(holder: Node3D, handle: Dictionary, turn: Basis, length: float) -> void:
	if handle.is_empty():
		return
	var bits := Node3D.new()
	bits.name = "Hook"
	holder.add_child(bits)
	bits.basis = turn
	var flat := turn.inverse() * Vector3(handle["centre"].x, 0.0, handle["centre"].y)
	var tip: float = handle["bottom"] + length
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.6, 0.6, 0.62)
	# The edge faces +X in the model's own space and the spine -X: from just
	# under the point the steel arcs up and over to the spine side, then
	# hangs down as a barb.
	var centre := Vector2(flat.x - hook_radius * 0.6, tip - hook_radius * 0.6)
	var steps := 7
	var last := Vector2.ZERO
	for i in steps + 1:
		var angle := lerpf(-0.3, PI, float(i) / steps)
		var at := centre + Vector2(cos(angle), sin(angle)) * hook_radius
		if i > 0:
			_hook_piece(bits, last, at, flat.z, steel)
		last = at
	_hook_piece(bits, last, last + Vector2(0.012, -hook_barb), flat.z, steel)


## One straight piece of the hook from `a` to `b` (across, up) at depth `z`.
func _hook_piece(parent: Node3D, a: Vector2, b: Vector2, z: float, mat: Material) -> void:
	var span := b - a
	var piece := _scrap_box(parent, Vector3(hook_width, span.length() + hook_width * 0.5, hook_thick),
			Vector3((a.x + b.x) * 0.5, (a.y + b.y) * 0.5, z), mat)
	piece.rotation.z = atan2(-span.x, span.y)


func _scrap_box(parent: Node3D, size: Vector3, at: Vector3, mat: Material) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = mat
	part.mesh = mesh
	part.position = at
	parent.add_child(part)
	return part


## Where the hands go on a melee model, read off its shape: sliced along its
## length (pommel at the bottom), the handle runs up to the first slice
## clearly wider than the rest below (a guard or a head). The weapon hand
## closes just under the guard on a short handle and near the end of a long
## haft; the holder
## moves so that spot, on the handle's middle line, is the visual's origin
## (where the fist is). A two-handed weapon also gets an "off_grip" meta:
## where the off hand closes, from the weapon hand along the handle: a
## hand's width below on a short handle (a long sword's two-hand grip), up
## the haft on a long one, which is carried across the body
## (`WeaponArm.carry_point`) with the weapon hand low near its end. A
## model with no handle found keeps `holder`'s place. `key` caches the
## measuring per model.
const HAND_WIDTH := 0.095
## How far up a long haft the off hand closes above the weapon hand.
const HAND_CARRY := 0.3
## How much wider than the handle below it a guard or head is.
const HANDLE_GUARD := 1.15
var _handles := {}


func _fit_hands(holder: Node3D, key: String, two_handed: bool, fixed_grip := -1.0) -> void:
	var at := holder.position
	holder.position = Vector3.ZERO
	if not _handles.has(key):
		_handles[key] = _measure_handle(holder)
	var handle: Dictionary = _handles[key]
	holder.position = at
	if handle.is_empty():
		return
	var bottom: float = handle["bottom"]
	var top: float = handle["top"]
	var span := top - bottom
	var grip := top - HAND_WIDTH * 0.55
	if span >= 0.35:
		grip = bottom + HAND_WIDTH
	if fixed_grip >= 0.0:
		grip = fixed_grip
	grip = clampf(grip, bottom + HAND_WIDTH * 0.4, maxf(top - HAND_WIDTH * 0.4, bottom + HAND_WIDTH * 0.4))
	var centre: Vector2 = handle["centre"]
	holder.position = Vector3(-centre.x, -grip, -centre.y)
	if two_handed:
		if span < 0.35:
			holder.set_meta("off_grip", -maxf(minf(HAND_WIDTH, grip - bottom - HAND_WIDTH * 0.3), HAND_WIDTH * 0.8))
		else:
			holder.set_meta("off_grip", maxf(minf(HAND_CARRY, top - grip - HAND_WIDTH * 0.5), HAND_WIDTH * 0.8))


## A melee model's handle in its holder's space: {"bottom", "top"} up its
## length and "centre" (x, z) across it, or empty when nothing marks where
## it ends (a knife all one width keeps its table grip).
func _measure_handle(holder: Node3D) -> Dictionary:
	var points := PackedVector3Array()
	for node in holder.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh == null:
			continue
		var xform := mesh_node.transform
		var up := mesh_node.get_parent()
		while up != null and up != holder:
			if up is Node3D:
				xform = (up as Node3D).transform * xform
			up = up.get_parent()
		for v in mesh_node.mesh.get_faces():
			points.append(xform * v)
	if points.size() < 3:
		return {}
	var low := points[0]
	var high := points[0]
	for q in points:
		low = low.min(q)
		high = high.max(q)
	var slice := maxf((high.y - low.y) / 120.0, 0.004)
	var count := int((high.y - low.y) / slice) + 1
	var lows: Array[Vector3] = []
	var highs: Array[Vector3] = []
	for i in count:
		lows.append(Vector3.INF)
		highs.append(-Vector3.INF)
	# Every triangle, sampled finer than a slice, so long faces count too.
	for i in range(0, points.size() - 2, 3):
		var a := points[i]
		var b := points[i + 1]
		var c := points[i + 2]
		var steps := mini(int(maxf(absf(a.y - b.y), maxf(absf(b.y - c.y), absf(a.y - c.y))) / (slice * 0.5)) + 1, 400)
		for u in steps + 1:
			for v in steps + 1 - u:
				var q := a + (b - a) * (float(u) / steps) + (c - a) * (float(v) / steps)
				var row := clampi(int((q.y - low.y) / slice), 0, count - 1)
				lows[row] = lows[row].min(q)
				highs[row] = highs[row].max(q)
	# The handle runs up from the bottom to the guard, cross-guard or head:
	# the first slice clearly wider than anything below it (a pommel too).
	var widest := 0.0
	var guard := -1
	for row in count:
		if lows[row] == Vector3.INF:
			continue
		var size := highs[row] - lows[row]
		var width := maxf(size.x, size.z)
		if row * slice > HAND_WIDTH and width > widest * HANDLE_GUARD:
			guard = row
			break
		widest = maxf(widest, width)
	if guard < 0:
		return {}
	var best := Vector2i(0, guard)
	var centre := Vector2.ZERO
	for row in range(best.x, best.y):
		centre += Vector2(lows[row].x + highs[row].x, lows[row].z + highs[row].z) * 0.5
	centre /= best.y - best.x
	return {"bottom": low.y + best.x * slice, "top": low.y + best.y * slice, "centre": centre}


## The glow a melee weapon's energy edge takes: its rarity color, with plain
## Common gear in the cyan of the scrap kit.
func energy_color(item_id: String) -> Color:
	var rarity := ItemDB.item_rarity(item_id) if item_id != "" else ItemDB.Rarity.COMMON
	if rarity == ItemDB.Rarity.COMMON:
		return Color(0.3, 0.85, 1.0)
	return ItemDB.RARITY_COLORS[rarity]


## Rarer weapons burn brighter.
func energy_strength(item_id: String) -> float:
	return 1.0 + 0.2 * (ItemDB.item_rarity(item_id) if item_id != "" else 0)


## Restyles a melee model as tech (see assets/shaders/melee.gdshader): light
## parts become alloy with an energy edge in `glow` (`strength` times as
## bright), dark parts black polymer with glowing seams. `root` is the holder,
## so seams are spaced in meters. `fold` says how the model folds away when
## holstered: {"mode": "blade"} finds the blade (the parts that start highest
## up the model) and draws it into the hilt; {"hilt", "slide", "keep"} in
## meters up the model slides `slide` meters above `hilt` down to `keep` of
## its length, and carries everything above along with it. `edged` false
## (a hammer) gives no part a cutting edge.
func _tech_melee(root: Node3D, glow: Color, strength: float, wear: float, fold := {}, edged := true) -> void:
	var surfaces: Array[Dictionary] = []
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh == null:
			continue
		var xform := mesh_node.transform
		var up := mesh_node.get_parent()
		while up != null and up != root:
			if up is Node3D:
				xform = (up as Node3D).transform * xform
			up = up.get_parent()
		for i in mesh_node.mesh.get_surface_count():
			var source := mesh_node.get_active_material(i) as BaseMaterial3D
			if source == null:
				continue
			var span := _surface_span(mesh_node.mesh, i, xform)
			surfaces.append({"node": mesh_node, "index": i, "source": source, "xform": xform,
				"low": span.x, "high": span.y})
	# Where the model folds, in meters up the model, and which parts move.
	var hilt := INF
	var slide := 0.0
	var keep := 1.0
	var mode: String = fold.get("mode", "")
	if mode == "blade" and not surfaces.is_empty():
		var top: Dictionary = surfaces[0]
		for s in surfaces:
			if s["high"] > top["high"]:
				top = s
		var length: float = top["high"]
		var start: float = top["low"]
		hilt = start
		for s in surfaces:
			if s["low"] >= start - 0.1 * length:
				hilt = minf(hilt, s["low"])
		slide = length
		keep = 0.0
	elif fold.has("hilt"):
		hilt = fold["hilt"]
		slide = fold["slide"]
		keep = fold["keep"]
	for s in surfaces:
		var mesh_node: MeshInstance3D = s["node"]
		var xform: Transform3D = s["xform"]
		var retract := {}
		# A blade folds only the parts that start at the hilt, so a guard
		# or pommel cast in one piece with the hilt keeps its shape.
		if hilt < INF and (mode != "blade" or s["low"] >= hilt - 0.001):
			var inv := xform.affine_inverse()
			var axis := inv.basis * Vector3.UP
			retract = {"origin": inv * Vector3(0, hilt, 0), "axis": axis.normalized(),
				"slide": slide * axis.length(), "keep": keep}
		mesh_node.set_surface_override_material(s["index"],
				_tech_material(s["source"], glow, strength, wear, xform.basis.get_scale()[_up_axis(xform)],
					_surface_box(mesh_node.mesh, s["index"]) if edged else AABB(), retract, _up_axis(xform)))
	if hilt < INF:
		root.set_meta("fold", {"hilt": hilt, "slide": slide, "keep": keep})


## Which of a mesh's own axes stands up the weapon once placed by `xform`.
static func _up_axis(xform: Transform3D) -> int:
	var up := xform.basis.inverse() * Vector3.UP
	var best := 0
	for a in 3:
		if absf(up[a]) > absf(up[best]):
			best = a
	return best


## How high up a melee model a point `y` meters from its pommel sits once
## folded away (`fold` as `_tech_melee` stores it on the holder).
static func fold_height(y: float, fold: Dictionary) -> float:
	var d: float = y - fold["hilt"]
	if d <= 0.0:
		return y
	var slide: float = fold["slide"]
	var keep: float = fold["keep"]
	return fold["hilt"] + (d * keep if d < slide else d - slide * (1.0 - keep))


## `model_bounds` of a melee model as it is worn, folded away.
static func folded_bounds(model: Node3D) -> AABB:
	var box := model_bounds(model)
	if not model.has_meta("fold"):
		return box
	var top := fold_height(box.end.y - model.position.y, model.get_meta("fold")) + model.position.y
	box.size.y = maxf(top - box.position.y, 0.0)
	return box


## How far up the model (its +Y, in the holder) one surface of a mesh runs.
func _surface_span(mesh: Mesh, surface: int, xform: Transform3D) -> Vector2:
	var key := "%d/%d/%s" % [mesh.get_instance_id(), surface, xform]
	if _spans.has(key):
		return _spans[key]
	var span := Vector2(INF, -INF)
	var verts: PackedVector3Array = mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
	for v in verts:
		var y := (xform * v).y
		span = Vector2(minf(span.x, y), maxf(span.y, y))
	_spans[key] = span
	return span


## Folds a melee model away (`extend` 0, how it is worn holstered) or out
## (1, how it is held), or anywhere between while it is drawn or put away.
## Only models built by `weapon_model` fold; anything else is left alone.
## Fully out or folded share materials between every copy; in between, the
## model gets its own until it settles.
func set_extend(model: Node3D, extend: float) -> void:
	if model == null:
		return
	extend = clampf(extend, 0.0, 1.0)
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh == null:
			continue
		for i in mesh_node.mesh.get_surface_count():
			var mat := mesh_node.get_surface_override_material(i) as ShaderMaterial
			if mat == null:
				continue
			var full: ShaderMaterial = mat.get_meta("tech_full") if mat.has_meta("tech_full") \
					else (mat if mat.has_meta("tech_fold") else null)
			if full == null:
				continue
			var folded := _folded_copy(full)
			var pick: ShaderMaterial
			if extend >= 1.0:
				pick = full
			elif extend <= 0.0:
				pick = folded
			else:
				pick = mat if mat != full and mat != folded else full.duplicate() as ShaderMaterial
				pick.set_meta("tech_full", full)
				pick.set_shader_parameter("extend", extend)
			if pick != mat:
				mesh_node.set_surface_override_material(i, pick)


## Which part of a melee model a pack color is: 1 for bare light metal (an
## edge or head), 0.5 for mid grey metal (a guard or fitting), 0 for anything
## colored or dark (wood, leather, wraps).
static func tech_part(color: Color) -> float:
	var saturation := maxf(color.r, maxf(color.g, color.b)) - minf(color.r, minf(color.g, color.b))
	var light := color.r * 0.299 + color.g * 0.587 + color.b * 0.114
	if saturation > 0.12 or light < 0.3:
		return 0.0
	return 1.0 if light > 0.45 else 0.5


## Which axis a flat blade is wide along (0 for X, 2 for Z), or -1 when the
## part is not flat enough to have a cutting edge.
static func edge_axis(box: AABB, length_axis := 1) -> int:
	return blade_axes(box, length_axis).x


## A flat part's axes in its mesh's own space, given the axis its length
## runs along (the one that stands up the weapon): x the axis it is wide
## along, where its cutting edges are, and y the thin one, the flat's
## normal; both -1 when it is not flat enough to have an edge. A pack model
## may lie along any axis in its own mesh, so the length is asked for, never
## assumed (assuming Y lit the whole flat of a blade lying along Z).
static func blade_axes(box: AABB, length_axis := 1) -> Vector2i:
	var across: Array[int] = []
	for a in 3:
		if a != length_axis:
			across.append(a)
	var wide := across[0] if box.size[across[0]] >= box.size[across[1]] else across[1]
	var thin := across[1] if wide == across[0] else across[0]
	if box.size[wide] <= 0.0 or box.size[thin] > box.size[wide] * 0.5:
		return Vector2i(-1, -1)
	return Vector2i(wide, thin)


## The bounds of one surface of `mesh`, in the mesh's own space.
func _surface_box(mesh: Mesh, surface: int) -> AABB:
	var key := "box/%d/%d" % [mesh.get_instance_id(), surface]
	if _spans.has(key):
		return _spans[key]
	var verts: PackedVector3Array = mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
	var box := AABB(verts[0], Vector3.ZERO) if not verts.is_empty() else mesh.get_aabb()
	for v in verts:
		box = box.expand(v)
	_spans[key] = box
	return box


func _tech_material(source: BaseMaterial3D, glow: Color, strength: float, wear: float, meters: float,
		box: AABB, retract := {}, length_axis := 1) -> ShaderMaterial:
	var key := "tech/%d/%s/%.2f/%.2f/%.4f/%s/%s/%d" % [source.get_instance_id(), glow.to_html(), strength, wear, meters,
		box, retract, length_axis]
	if _gear_materials.has(key):
		return _gear_materials[key]
	var mat := ShaderMaterial.new()
	mat.shader = MELEE_SHADER
	if source.albedo_texture:
		mat.set_shader_parameter("base_tex", source.albedo_texture)
	mat.set_shader_parameter("base_color", source.albedo_color)
	mat.set_shader_parameter("energy_color", glow)
	mat.set_shader_parameter("energy", strength)
	mat.set_shader_parameter("box_min", box.position)
	mat.set_shader_parameter("box_max", box.end)
	var axes := blade_axes(box, length_axis)
	mat.set_shader_parameter("edge_axis", axes.x)
	mat.set_shader_parameter("flat_axis", axes.y)
	mat.set_shader_parameter("length_axis", length_axis)
	mat.set_shader_parameter("seam_scale", 6.0 * meters)
	mat.set_shader_parameter("part", tech_part(source.albedo_color))
	var dir := TEXTURES + "Metal063/"
	mat.set_shader_parameter("grime_albedo", load(dir + "Color.jpg"))
	mat.set_shader_parameter("grime_rough", load(dir + "Roughness.jpg"))
	mat.set_shader_parameter("wear", wear)
	_bind_storm(mat)
	if not retract.is_empty():
		mat.set_shader_parameter("fold_origin", retract["origin"])
		mat.set_shader_parameter("fold_axis", retract["axis"])
		mat.set_shader_parameter("fold_slide", retract["slide"])
		mat.set_shader_parameter("fold_keep", retract["keep"])
		mat.set_shader_parameter("extend", 1.0)
		# The copy worn holstered, folded away; `set_extend` swaps between them.
		mat.set_meta("tech_fold", true)
		_folded_copy(mat)
	_gear_materials[key] = mat
	return mat


## The folded copy of the drawn-out material `full` (one marked "tech_fold"),
## made the first time it is asked for. Every drawn-out material has one,
## including copies of it (a storm-lit one, `_pop_storm`), so `set_extend`
## can always fold what it is given.
func _folded_copy(full: ShaderMaterial) -> ShaderMaterial:
	var id := full.get_instance_id()
	var known: WeakRef = _folded.get(id)
	var folded: ShaderMaterial = known.get_ref() if known != null else null
	if folded == null:
		folded = full.duplicate() as ShaderMaterial
		folded.set_shader_parameter("extend", 0.0)
		folded.set_meta("tech_full", full)
		_folded[id] = weakref(folded)
	return folded


## No pack has a spear, so it is built here: a dark shaft, alloy collars
## and a long leaf head, standing along +Y like the pack models.
func _spear_model(length: float, grip: float, glow: Color, strength: float) -> Node3D:
	var holder := Node3D.new()
	holder.name = "Model"
	var model := Node3D.new()
	model.name = "Spear"
	holder.add_child(model)
	var shaft := StandardMaterial3D.new()
	shaft.albedo_color = Color(0.2, 0.2, 0.22)
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.62, 0.63, 0.66)
	steel.metallic = 0.9
	steel.roughness = 0.35
	var wrap := StandardMaterial3D.new()
	wrap.albedo_color = Color(0.12, 0.11, 0.1)
	wrap.roughness = 0.95
	var head_len := 0.34
	var shaft_len := length - head_len
	_spear_part(model, _cylinder(0.018, shaft_len), Vector3(0, shaft_len * 0.5, 0), shaft)
	_spear_part(model, _cylinder(0.024, 0.3), Vector3(0, grip, 0), wrap)
	_spear_part(model, _cylinder(0.022, 0.06), Vector3(0, 0.03, 0), steel)
	_spear_part(model, _cylinder(0.026, 0.07), Vector3(0, shaft_len - 0.02, 0), steel)
	# The head: a flattened double cone, widest a third of the way up.
	var lower := CylinderMesh.new()
	lower.top_radius = 0.055
	lower.bottom_radius = 0.02
	lower.height = head_len * 0.3
	_spear_part(model, lower, Vector3(0, shaft_len + head_len * 0.15, 0), steel, Vector3(1, 1, 0.3))
	var upper := CylinderMesh.new()
	upper.top_radius = 0.0
	upper.bottom_radius = 0.055
	upper.height = head_len * 0.7
	_spear_part(model, upper, Vector3(0, shaft_len + head_len * 0.65, 0), steel, Vector3(1, 1, 0.3))
	# Holstered, the shaft above the butt collar slides into itself and
	# carries the head down with it.
	_tech_melee(holder, glow, strength, 0.3, {"hilt": 0.2, "slide": shaft_len - 0.3, "keep": 0.2})
	holder.position.y = -grip
	return holder


func _cylinder(radius: float, height: float) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 10
	mesh.rings = 1
	return mesh


func _spear_part(model: Node3D, mesh: PrimitiveMesh, at: Vector3, mat: Material, scale := Vector3.ONE) -> void:
	var part := MeshInstance3D.new()
	mesh.material = mat
	part.mesh = mesh
	part.position = at
	part.scale = scale
	model.add_child(part)


## How far a melee weapon reaches past the hand that grips it, in meters.
func blade_reach(weapon: Weapon) -> float:
	var pick := _melee_pick(weapon)
	return maxf(float(pick[2]) - float(pick[3]), 0.1)


## How `weapon` is held ready in one hand (see `MELEE_MODELS`).
func ready_hold(weapon: Weapon) -> String:
	return _melee_pick(weapon)[5]


func _melee_pick(weapon: Weapon) -> Array:
	for entry: Array in MELEE_MODELS:
		if weapon.item_id != "" and ItemDB.has_tag(weapon.item_id, entry[0]):
			return entry
	return DEFAULT_MELEE


## True when the weapon is held with both hands: the item's "two_handed"
## tag (`MeleeWeapon.is_two_handed_id`), the same flag gameplay reads.
## The one place a view asks; the grip and the sling follow it.
func is_two_handed(weapon: Weapon) -> bool:
	return weapon is MeleeWeapon and MeleeWeapon.is_two_handed_id(weapon.item_id)


## True when a two-handed weapon is carried across the body (a hammer, a
## spear, an axe in both hands): every two-hander but one held at the hilt
## like a katana (`MELEE_MODELS` hold "katana"), which keeps its own ready
## hold and cuts with the off hand under the weapon hand.
func is_carried(weapon: Weapon) -> bool:
	return is_two_handed(weapon) and ready_hold(weapon) != "katana"


## Fallback when a melee model is missing: greybox parts keep their shape and get metal and a hot edge.
func restyle_melee(visual: Node3D) -> void:
	for node in visual.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		var source := mesh_node.mesh.surface_get_material(0) as StandardMaterial3D if mesh_node.mesh else null
		if source == null:
			continue
		var mat := source.duplicate() as StandardMaterial3D
		if mat.emission_enabled:
			mat.emission_energy_multiplier = 1.5
			mat.albedo_color = mat.albedo_color * 0.25
		else:
			mat.metallic = 0.9
			mat.roughness = 0.35
			mat.albedo_color = mat.albedo_color * 0.7
		mesh_node.material_override = mat


func _dress_cache(cache: LootContainer) -> void:
	if not is_instance_valid(cache) or cache.has_node("Crate"):
		return
	var marker: MeshInstance3D = null
	for child in cache.get_children():
		if child is MeshInstance3D:
			marker = child
			break
	if marker == null:
		return
	var box := marker.mesh as BoxMesh
	var size := box.size if box else Vector3(1, 0.8, 0.8)
	if cache.is_rack():
		_dress_power_rack(cache, marker, size)
		return
	if cache.pile:
		_dress_pile(cache, marker, size)
		return
	var crate := prop("Backpack.glb" if cache.is_bag else "Lootbox.glb", maxf(size.x, size.z) * (0.9 if cache.is_bag else 1.15), 0.7)
	crate.name = "Crate"
	cache.add_child(crate)
	# The game colors the marker mesh by the best item inside. Keep that signal
	# as a glowing band around the crate rather than a whole glowing box.
	var band := BoxMesh.new()
	band.size = Vector3(size.x * 1.08, 0.05, size.z * 1.08)
	marker.mesh = band
	marker.position.y = size.y * (0.2 if cache.is_bag else 0.55)
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## A salvage crate (`SalvageCrate`, DESIGN.md "The Dune Sea"): a dented
## sand-coloured freight box with dark steel corner posts and bands and an
## ochre stripe, so it reads apart from a cache. Built of still pieces, one
## mesh a material (`merge_pieces`). View only.
func _dress_salvage_crate(crate: SalvageCrate) -> void:
	if not is_instance_valid(crate) or crate.has_node("Freight"):
		return
	var body := crate.get_node_or_null("Body") as MeshInstance3D
	if body == null:
		return
	var size := SalvageCrate.SIZE
	var shell := surface("metal", {"tint": Color(0.72, 0.62, 0.46), "grime": 0.8, "scale": 0.6})
	var steel := surface("metal", {"tint": Color(0.25, 0.25, 0.26), "grime": 0.6, "scale": 0.6})
	var stripe := StandardMaterial3D.new()
	stripe.albedo_color = Color(0.85, 0.55, 0.15)
	stripe.roughness = 0.7
	(body.mesh as BoxMesh).material = shell
	var freight := Node3D.new()
	freight.name = "Freight"
	var pieces: Array = []
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			pieces.append([Vector3(0.07, size.y + 0.02, 0.07), Vector3(sx * (size.x * 0.5 - 0.02), 0, sz * (size.z * 0.5 - 0.02)), steel])
	for bx: float in [-0.28, 0.28]:
		pieces.append([Vector3(0.06, size.y + 0.015, size.z + 0.015), Vector3(bx, 0, 0), steel])
	pieces.append([Vector3(size.x * 0.5, 0.07, size.z + 0.012), Vector3(0, size.y * 0.18, 0), stripe])
	pieces.append([Vector3(0.3, 0.05, 0.08), Vector3(0, size.y * 0.5 + 0.03, 0), steel])
	for piece: Array in pieces:
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = piece[0]
		box.material = piece[2]
		mesh.mesh = box
		mesh.position = piece[1]
		freight.add_child(mesh)
	crate.add_child(freight)
	merge_pieces(freight)


## A scrip pile (DESIGN.md "Scrip piles"): a heap of glowing amber chits
## with a short column of light over it, so a fresh kill draws eyes; a
## bounty's heap is bigger, redder and taller. The game's marker stays as a
## band round it in the bonus item's rarity. View only.
func _dress_pile(pile: LootContainer, marker: MeshInstance3D, size: Vector3) -> void:
	var heap := Node3D.new()
	heap.name = "Crate"
	pile.add_child(heap)
	var hot := pile.bounty > 0
	var color := LootContainer.PILE_BOUNTY_COLOR if hot else LootContainer.PILE_COLOR
	var chit := StandardMaterial3D.new()
	chit.albedo_color = color
	chit.metallic = 0.8
	chit.roughness = 0.3
	chit.emission_enabled = true
	chit.emission = color
	chit.emission_energy_multiplier = 1.4 if hot else 0.8
	var dice := RandomNumberGenerator.new()
	dice.seed = hash(pile.label)
	var count := 22 if hot else 14
	var spread := size.x * (0.6 if hot else 0.45)
	for k in count:
		var coin := MeshInstance3D.new()
		var disc := CylinderMesh.new()
		disc.top_radius = 0.07
		disc.bottom_radius = 0.07
		disc.height = 0.02
		disc.radial_segments = 10
		disc.rings = 1
		disc.material = chit
		coin.mesh = disc
		var reach := spread * sqrt(dice.randf())
		var turn := dice.randf() * TAU
		coin.position = Vector3(cos(turn) * reach, 0.02 + (1.0 - reach / spread) * 0.16 + dice.randf() * 0.03,
				sin(turn) * reach)
		coin.rotation = Vector3(dice.randf_range(-0.5, 0.5), dice.randf() * TAU, dice.randf_range(-0.5, 0.5))
		coin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		heap.add_child(coin)
	var column := MeshInstance3D.new()
	var beam := CylinderMesh.new()
	beam.top_radius = 0.03
	beam.bottom_radius = 0.09 if hot else 0.06
	beam.height = 6.0 if hot else 3.5
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow.albedo_color = Color(color.r, color.g, color.b, 0.4 if hot else 0.28)
	beam.material = glow
	column.mesh = beam
	column.position.y = 0.2 + beam.height * 0.5
	column.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	heap.add_child(column)
	if hot:
		# Only a bounty's heap casts light: the war leaves many piles, and a
		# lamp each would cost the frame.
		var light := lamp(color, 1.6, 4.0)
		light.position.y = 0.6
		heap.add_child(light)
	heap.visible = pile.scrip > 0
	var band := BoxMesh.new()
	band.size = Vector3(size.x * 0.5, 0.04, size.z * 0.5)
	marker.mesh = band
	marker.position.y = 0.03
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## A power rack: an armoured weapon stand with glowing clamps and a thin
## light column, so a power weapon can be spotted across the field. The
## game's marker (coloured by what is inside) stays as the glowing cradle.
func _dress_power_rack(rack: LootContainer, marker: MeshInstance3D, size: Vector3) -> void:
	var frame := Node3D.new()
	frame.name = "Crate"
	rack.add_child(frame)
	var steel := _power_mat(Color(0.24, 0.26, 0.31), 0.5, 0.45)
	var cyan := Color(0.35, 0.95, 1.0)
	var lit := _power_mat(cyan, 0.0, 0.4, cyan, 1.6)
	_power_box(frame, Vector3(size.x * 1.2, 0.12, size.z * 1.0), Vector3(0, 0.06, 0), steel)
	for side in [-1.0, 1.0]:
		_power_box(frame, Vector3(0.1, 1.3, 0.1), Vector3(size.x * 0.5 * side, 0.7, 0), steel)
		_power_box(frame, Vector3(0.14, 0.06, 0.3), Vector3(size.x * 0.5 * side, 1.05, 0), lit)
	_power_box(frame, Vector3(size.x * 1.05, 0.06, 0.06), Vector3(0, 1.36, 0), lit)
	var column := MeshInstance3D.new()
	var beam := CylinderMesh.new()
	beam.top_radius = 0.04
	beam.bottom_radius = 0.04
	beam.height = 9.0
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow.albedo_color = Color(cyan.r, cyan.g, cyan.b, 0.35)
	beam.material = glow
	column.mesh = beam
	column.position.y = 1.4 + beam.height * 0.5
	column.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	frame.add_child(column)
	var light := lamp(cyan, 1.5, 6.0)
	light.position.y = 1.2
	frame.add_child(light)
	# The marker becomes the cradle the weapon rests in.
	var cradle := BoxMesh.new()
	cradle.size = Vector3(size.x * 0.9, 0.08, 0.22)
	marker.mesh = cradle
	marker.position.y = 0.9
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## A depot as an uplink station: a plated pad with a lit green rim (the bank
## area, so you can see where to stand), lamp posts at its corners, a
## terminal at the back with a lit screen that says what it does, and a mast
## with a slow green beacon and a faint uplink beam you find it by from far.
func _dress_depot(zone: Depot) -> void:
	if not is_instance_valid(zone) or zone.has_meta("dressed"):
		return
	zone.set_meta("dressed", true)
	var green := Color(0.3, 1.0, 0.55)
	var floor_y := -zone.size.y * 0.5
	var pad := zone.get_node_or_null("Pad") as MeshInstance3D
	if pad != null:
		pad.material_override = surface("panels", {"tint": Color(0.42, 0.44, 0.43), "scale": 0.35, "grime": 0.5})
	var rim := StandardMaterial3D.new()
	rim.albedo_color = green * 0.3
	rim.emission_enabled = true
	rim.emission = green
	rim.emission_energy_multiplier = 0.9
	var steel := surface("metal", {"tint": Color(0.36, 0.38, 0.37), "scale": 0.5, "grime": 0.6})
	var station := Node3D.new()
	station.name = "Station"
	station.set_meta("walk_through", "the pad's lit rim and slim corner lamps")
	zone.add_child(station)
	# The rim: a lit strip just inside each edge of the pad, so the bank
	# area's edge reads from any side.
	var half := Vector2(zone.size.x, zone.size.z) * 0.5 - Vector2(0.25, 0.25)
	for edge in 4:
		var along_x := edge < 2
		var strip := MeshInstance3D.new()
		var bar := BoxMesh.new()
		bar.size = Vector3(half.x * 2.0, 0.04, 0.16) if along_x else Vector3(0.16, 0.04, half.y * 2.0)
		bar.material = rim
		strip.mesh = bar
		var side := 1.0 if edge % 2 == 0 else -1.0
		strip.position = Vector3(0, floor_y + 0.12, side * half.y) if along_x else Vector3(side * half.x, floor_y + 0.12, 0)
		strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		station.add_child(strip)
	# Short posts at the corners, each with a green lamp on top.
	for corner in 4:
		var at := Vector3((1.0 if corner % 2 == 0 else -1.0) * half.x, floor_y, (1.0 if corner < 2 else -1.0) * half.y)
		var post := MeshInstance3D.new()
		var pole := BoxMesh.new()
		pole.size = Vector3(0.22, 1.0, 0.22)
		pole.material = trim("hazard")
		post.mesh = pole
		post.position = at + Vector3(0, 0.5, 0)
		station.add_child(post)
		var cap := MeshInstance3D.new()
		var lens := BoxMesh.new()
		lens.size = Vector3(0.26, 0.14, 0.26)
		lens.material = rim
		cap.mesh = lens
		cap.position = at + Vector3(0, 1.07, 0)
		cap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		station.add_child(cap)
	var light := lamp(green, 0.7, 8.0)
	light.position.y = floor_y + 3.0
	station.add_child(light)

	var terminal := zone.get_node_or_null("Terminal") as Node3D
	if terminal == null:
		merge_pieces(station, true)
		return
	var body := terminal.get_node_or_null("Body") as MeshInstance3D
	var size := Depot.TERMINAL_SIZE
	if body != null:
		body.material_override = steel
	# A hazard band round its foot, and a hood over the screen.
	var band := MeshInstance3D.new()
	var foot := BoxMesh.new()
	foot.size = Vector3(size.x + 0.06, 0.22, size.z + 0.06)
	foot.material = trim("hazard")
	band.mesh = foot
	band.position.y = 0.11
	terminal.add_child(band)
	# The screen leans back on the face toward the pad (local -Z).
	var screen_at := Vector3(0, size.y * 0.72, -size.z * 0.5 - 0.02)
	var screen := MeshInstance3D.new()
	var glass := BoxMesh.new()
	glass.size = Vector3(size.x * 0.82, 0.62, 0.05)
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(0.02, 0.08, 0.05)
	glow.emission_enabled = true
	glow.emission = green * 0.55
	glow.emission_energy_multiplier = 1.2
	glow.roughness = 0.15
	glass.material = glow
	screen.mesh = glass
	screen.position = screen_at
	screen.rotation.x = deg_to_rad(-14.0)
	screen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	terminal.add_child(screen)
	var hood := MeshInstance3D.new()
	var lid := BoxMesh.new()
	lid.size = Vector3(size.x * 0.92, 0.06, 0.32)
	lid.material = steel
	hood.mesh = lid
	hood.position = Vector3(0, size.y * 0.72 + 0.36, -size.z * 0.5 - 0.12)
	terminal.add_child(hood)
	# The words sit on the glass, so they lean with it.
	var label := Label3D.new()
	label.text = "DEPOT UPLINK\nstand on the pad to send\nyour pack home"
	label.font_size = 30
	label.pixel_size = 0.004
	label.outline_size = 0
	label.modulate = Color(0.75, 1.0, 0.82)
	label.double_sided = false
	label.position = Vector3(0, 0, -0.035)
	label.rotation.y = PI
	screen.add_child(label)
	# A row of status lamps under the screen, and vents down each side.
	for k in 4:
		var led := MeshInstance3D.new()
		var dot := BoxMesh.new()
		dot.size = Vector3(0.1, 0.06, 0.03)
		dot.material = rim if k < 3 else trim("orange")
		led.mesh = dot
		led.position = Vector3(-0.3 + k * 0.2, size.y * 0.42, -size.z * 0.5 - 0.015)
		led.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		terminal.add_child(led)
	for side: float in [-1.0, 1.0]:
		for k in 4:
			var vent := MeshInstance3D.new()
			var slat := BoxMesh.new()
			slat.size = Vector3(0.03, 0.05, size.z * 0.7)
			slat.material = trim("rut")
			vent.mesh = slat
			vent.position = Vector3(side * (size.x * 0.5 + 0.015), 0.5 + k * 0.12, 0)
			terminal.add_child(vent)
	# The mast's beacon, pulsing slowly, and a faint beam up from it.
	var mast := terminal.get_node_or_null("Mast") as MeshInstance3D
	if mast == null:
		merge_pieces(station, true)
		merge_pieces(terminal, true)
		return
	mast.material_override = steel
	var top := mast.position + Vector3(0, Depot.MAST_HEIGHT * 0.5, 0)
	for rung in 3:
		var dish := MeshInstance3D.new()
		var arm := BoxMesh.new()
		arm.size = Vector3(0.7 - rung * 0.15, 0.06, 0.06)
		arm.material = steel
		dish.mesh = arm
		dish.position = top - Vector3(0, 1.0 + rung * 0.9, 0)
		dish.rotation.y = rung * 0.9
		terminal.add_child(dish)
	var beacon := MeshInstance3D.new()
	var bulb := SphereMesh.new()
	bulb.radius = 0.22
	bulb.height = 0.44
	var bright := StandardMaterial3D.new()
	bright.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bright.albedo_color = Color(0.6, 1.0, 0.75)
	bright.disable_fog = true
	bulb.material = bright
	beacon.mesh = bulb
	beacon.position = top + Vector3(0, 0.15, 0)
	beacon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	terminal.add_child(beacon)
	var beacon_light := lamp(green, 2.0, 12.0)
	beacon_light.position = beacon.position
	terminal.add_child(beacon_light)
	var pulse := beacon_light.create_tween().set_loops()
	pulse.tween_property(beacon_light, "light_energy", 0.4, 1.1).set_trans(Tween.TRANS_SINE)
	pulse.tween_property(beacon_light, "light_energy", 2.0, 1.1).set_trans(Tween.TRANS_SINE)
	var beam := MeshInstance3D.new()
	var column := CylinderMesh.new()
	column.top_radius = 0.05
	column.bottom_radius = 0.12
	column.height = 60.0
	column.radial_segments = 8
	column.rings = 1
	var faint := StandardMaterial3D.new()
	faint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	faint.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	faint.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	faint.albedo_color = Color(0.3, 1.0, 0.55, 0.22)
	faint.cull_mode = BaseMaterial3D.CULL_DISABLED
	column.material = faint
	beam.mesh = column
	beam.position = beacon.position + Vector3(0, column.height * 0.5 + 0.2, 0)
	beam.set_meta("walk_through", "a beam of light")
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	terminal.add_child(beam)
	# Thirty-odd boxes a depot: one mesh per material (the named body and
	# mast, the screen with its words and the lights stay apart).
	merge_pieces(station, true)
	merge_pieces(terminal, true)


## Something on show (a home base display): a node with the meta
## "display_item" (an item id) and a "Model" child holding its greybox shape.
## Weapons get their real model, laid out the way the greybox one was;
## vehicles get the worn paint they have in a raid.
func _dress_display(display: Node3D) -> void:
	if not is_instance_valid(display):
		return
	var model := display.get_node_or_null("Model") as Node3D
	if model == null or model.has_meta("dressed"):
		return
	var id: String = display.get_meta("display_item")
	var weapon: Weapon = null
	if ItemDB.has_tag(id, "firearm"):
		weapon = Gun.new()
	elif ItemDB.has_tag(id, "melee"):
		weapon = MeleeWeapon.new()
	if weapon == null:
		# `_dress_vehicle` marks the model itself, and leaves other shapes alone.
		if ItemDB.has_tag(id, "vehicle"):
			_dress_vehicle(display)
		elif ItemDB.has_tag(id, "flight_rig"):
			_dress_rig_stand(model, id)
		return
	model.set_meta("dressed", true)
	weapon.item_id = id
	var real := weapon_model(weapon)
	weapon.free()
	var grey := model.get_child(0) as Node3D if model.get_child_count() > 0 else null
	if real == null or grey == null:
		return
	# The real model sits where the hand would hold it, inside the greybox
	# shape's own turn and scale.
	var holder := Node3D.new()
	holder.transform = grey.transform
	holder.add_child(real)
	# Attachments fitted to a gun on show move across onto the real model.
	var fitted := grey.get_node_or_null("Attachments")
	if fitted:
		grey.remove_child(fitted)
		holder.add_child(fitted)
		mount_attachments(holder)
	model.remove_child(grey)
	grey.queue_free()
	model.add_child(holder)


## A flight rig on show: its real model on a faceless mannequin, which stands
## with its back to the room so a back-worn rig faces you. Boots stand on
## the base.
func _dress_rig_stand(model: Node3D, id: String) -> void:
	model.set_meta("dressed", true)
	for child in model.get_children():
		model.remove_child(child)
		child.queue_free()
	var dummy := StandardMaterial3D.new()
	dummy.albedo_color = Color(0.22, 0.22, 0.24)
	var stand := Node3D.new()
	stand.name = "Mannequin"
	for piece: Array in [[Vector3(0.7, 0.08, 0.7), Vector3(0, 0.04, 0)], [Vector3(0.1, 0.9, 0.1), Vector3(0, 0.5, 0)],
			[Vector3(0.42, 0.6, 0.24), Vector3(0, 1.25, 0)], [Vector3(0.24, 0.26, 0.24), Vector3(0, 1.72, 0)]]:
		var box := BoxMesh.new()
		box.size = piece[0]
		box.material = dummy
		var part := MeshInstance3D.new()
		part.mesh = box
		part.position = piece[1]
		stand.add_child(part)
	model.add_child(stand)
	var back := RigModel.build_back(id)
	if back:
		back.position = Vector3(0, 1.36, 0.12)
		if back.has_node("WingL"):
			RigModel.set_wing_spread(back, 0.55)
		_weather_model(back, 0.5, 0.6)
		model.add_child(back)
	for side: float in [-1.0, 1.0]:
		var boot := RigModel.build_boot(id, side)
		if boot:
			# Set down on the base either side of the pole, heel to the room.
			boot.position = Vector3(side * 0.16, 0.15, 0.05)
			_weather_model(boot, 0.5, 0.6)
			model.add_child(boot)


func _dress_vehicle(vehicle: Node3D) -> void:
	if not is_instance_valid(vehicle):
		return
	var model := vehicle.get_node_or_null("Model") as Node3D
	if model == null or model.has_meta("dressed"):
		return
	model.set_meta("dressed", true)
	_show_between_ticks(vehicle)
	# How grimy the model asks to be (`VehicleModel.WEAR`).
	var wear := float(model.get_meta("wear", 0.7))
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		var source := mesh_node.mesh.surface_get_material(0) as StandardMaterial3D if mesh_node.mesh else null
		if source == null:
			continue
		if source.emission_enabled:
			var lit := source.duplicate() as StandardMaterial3D
			lit.emission_energy_multiplier = 4.0
			mesh_node.material_override = lit
			var beam := SpotLight3D.new()
			beam.light_color = Color(1.0, 0.9, 0.7)
			beam.light_energy = 6.0
			beam.spot_range = 26.0
			beam.spot_angle = 28.0
			beam.shadow_enabled = false
			beam.position = mesh_node.position + Vector3(0, 0, -0.1)
			model.add_child(beam)
		else:
			mesh_node.material_override = _worn(source, wear, 0.7)
	# A parked vehicle was a draw for every panel, strut and bolt (about fifty
	# a bike): its still pieces are one mesh per material now. Named pieces
	# (thrusters, engines, the canopy) and anything under a moving part (a
	# walker's legs, an airship's weak spots) stay as they are.
	merge_pieces(model, true, false, true)
	# A wheel or a steering pivot turns as one: its own pieces are merged
	# among themselves ("merge", `VehicleModel._wheel_set`, `_pivot`).
	var turning := model.find_children("*", "Node3D", true, false).filter(
			func(part: Node) -> bool: return part.get_meta("merge", false))
	for part: Node3D in turning:
		merge_pieces(part, true, false, true)
