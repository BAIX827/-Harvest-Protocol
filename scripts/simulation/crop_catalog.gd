extends RefCounted
## Shared crop definitions; seed choices, growth and harvest read the same resource.

static var _data: Dictionary = {}


static func _ensure_loaded() -> void:
	if not _data.is_empty():
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/crops.json"))
	if not parsed is Dictionary or not _valid(parsed):
		push_error("Invalid crop definitions in res://data/crops.json")
		return
	_data = parsed


static func _valid(data: Dictionary) -> bool:
	if data.get("version") != 1 or not data.get("order") is Array or not data.get("crops") is Dictionary:
		return false
	if data.order.is_empty():
		return false
	var seen: Dictionary = {}
	for id in data.order:
		if not id is String or seen.has(id) or not data.crops.get(id) is Dictionary:
			return false
		seen[id] = true
		var crop: Dictionary = data.crops[id]
		if not crop.get("name") is String or String(crop.name).is_empty():
			return false
		for key in ["growth_minutes", "dry_stop", "optimal_min", "optimal_max", "wet_stop", "night_factor", "transpiration_mm_h", "harvest_count"]:
			if not (crop.get(key) is float or crop.get(key) is int) or not is_finite(float(crop[key])):
				return false
		if crop.growth_minutes <= 0 or crop.dry_stop < 0 or crop.dry_stop >= crop.optimal_min or crop.optimal_min >= crop.optimal_max or crop.optimal_max >= crop.wet_stop or crop.wet_stop > 100:
			return false
		if crop.night_factor <= 0 or crop.night_factor > 1 or crop.transpiration_mm_h < 0 or crop.harvest_count < 1 or float(crop.harvest_count) != float(int(crop.harvest_count)):
			return false
	return true


static func ids() -> Array[String]:
	_ensure_loaded()
	var result: Array[String] = []
	for id in _data.get("order", []):
		result.append(id)
	return result


static func names() -> Dictionary:
	_ensure_loaded()
	var result: Dictionary = {}
	for id in _data.get("order", []):
		result[id] = _data.crops[id].name
	return result


static func definition(id: String) -> Dictionary:
	_ensure_loaded()
	return _data.get("crops", {}).get(id, {}).duplicate(true)
