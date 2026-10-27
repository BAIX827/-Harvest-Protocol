extends RefCounted

static var _data: Dictionary = {}


static func config() -> Dictionary:
	if _data.is_empty():
		_data = JSON.parse_string(FileAccess.get_file_as_string("res://data/tutorial.json"))
		assert(_data.steps.size() == 9 and _data.recovery_cash == 2)
	return _data.duplicate(true)


static func initial_state(minute: int = 480, delivered: float = 0.0, used: float = 0.0) -> Dictionary:
	return {"since": minute, "baseline_l": delivered, "baseline_wh": used,
		"manual": {"hoe": 0, "sow": 0, "water": 0, "harvest": 0, "refill": 0}, "manual_water_l": 0.0,
		"modes": {"manual": {"liters": 0.0, "wh": 0.0, "minutes": 0}, "auto": {"liters": 0.0, "wh": 0.0, "minutes": 0}},
		"improvement": {"baseline": {}, "change": {}, "proof": {}}}
