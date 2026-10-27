extends RefCounted
## Stable module IDs and prototype units shared by trading, simulation and saves.

static var _data: Dictionary = {}


static func config() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/modules.json"))
		assert(parsed is Dictionary and parsed.get("modules") is Dictionary, "Invalid module catalog")
		for key in ["water_liters_per_coin", "energy_wh_per_coin", "liters_per_moisture_point"]:
			assert(parsed.get(key) is float and parsed[key] > 0, "Invalid engineering conversion")
		for id in parsed.modules:
			var item: Dictionary = parsed.modules[id]
			assert(item.get("name") is String and item.get("kind") in ["tank", "pump", "power", "pipe", "sensor", "controller"])
			assert(item.get("available") is bool and item.get("price") is float and item.price > 0 and item.price == floor(item.price))
			if item.kind in ["tank", "power"]: assert(item.get("capacity") is float and item.capacity > 0)
			if item.kind == "pump": assert(item.get("flow_l_h") is float and item.flow_l_h > 0 and item.get("power_w") is float and item.power_w > 0)
		_data = parsed
	return _data.duplicate(true)


static func definition(id: String) -> Dictionary:
	return config().modules.get(id, {}).duplicate(true)


static func ids(kind: String = "") -> Array[String]:
	var result: Array[String] = []
	for id in config().modules:
		if kind.is_empty() or definition(id).kind == kind: result.append(id)
	return result
