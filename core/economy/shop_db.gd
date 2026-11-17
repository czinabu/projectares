extends RefCounted
## The shops in the player hub. A shop is a name plus the item tags it deals
## in; what it actually stocks is every vendor item with one of those tags
## (see `Economy.for_sale`). A world can add stock by registering a
## base-level item with the "vendor" tag.
##
## Load with `const ShopDB := preload("res://core/economy/shop_db.gd")`.

const SHOPS := [
	{"id": "armory", "name": "Armory", "tags": ["weapon", "attachment"],
		"blurb": "Dependable guns, blades and attachments. Nothing fancy: the good stuff is out there."},
	{"id": "outfitter", "name": "Outfitter", "tags": ["armor", "helmet", "flight_rig", "consumable"],
		"blurb": "Armor frames, helmets, flight rigs and medical supplies."},
	{"id": "garage", "name": "Garage", "tags": ["vehicle"],
		"blurb": "Something to ride in on. Bring it back in one piece."},
	{"id": "furnisher", "name": "Furnisher", "tags": ["furniture"],
		"blurb": "Furniture and decorations for your home base."},
	{"id": "tailor", "name": "Tailor", "tags": ["cosmetic"],
		"blurb": "Clothing that changes how you look and nothing else. Once bought it is yours for good."},
]


static func ids() -> Array[String]:
	var out: Array[String] = []
	for entry: Dictionary in SHOPS:
		out.append(entry.id)
	return out


## The shop's entry, or {} if there is no such shop.
static func shop(shop_id: String) -> Dictionary:
	for entry: Dictionary in SHOPS:
		if entry.id == shop_id:
			return entry
	return {}


static func shop_name(shop_id: String) -> String:
	return shop(shop_id).get("name", shop_id)
