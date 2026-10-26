extends RefCounted

const Crops = preload("res://scripts/simulation/crop_catalog.gd")
static var _data: Dictionary = {}


static func config() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/economy.json"))
		if not parsed is Dictionary or not _valid(parsed):
			push_error("Invalid economy configuration in res://data/economy.json")
			return {}
		_data = parsed
	return _data.duplicate(true)


static func _whole(value: Variant, minimum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == float(int(value)) and int(value) >= minimum and int(value) <= 1000000


static func _valid(data: Dictionary) -> bool:
	if data.get("version") != 1 or not _whole(data.get("starting_cash"), 0) or not _whole(data.get("max_buy_quantity"), 1) or not _whole(data.get("water_refill_cost"), 0):
		return false
	if not data.get("starting_seeds") is Dictionary or not data.get("crops") is Dictionary:
		return false
	for id in Crops.ids():
		if not _whole(data.starting_seeds.get(id), 0) or not data.crops.get(id) is Dictionary:
			return false
		if not _whole(data.crops[id].get("seed_price"), 1) or not _whole(data.crops[id].get("produce_price"), 1):
			return false
	return true


static func initial_seeds() -> Dictionary:
	var data := config()
	var seeds: Dictionary = {}
	for id in Crops.ids():
		seeds[id] = int(data.starting_seeds[id])
	return seeds
