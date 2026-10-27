extends RefCounted

const SensorCatalog = preload("res://scripts/engineering/sensor_catalog.gd")
static var _config: Dictionary = {}


static func config() -> Dictionary:
	if _config.is_empty():
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/learning_tasks.json"))
		assert(data is Dictionary)
		for key in ["reference_gap_min", "verification_tolerance", "improvement_min"]:
			assert(data.get(key) is float and data[key] > 0 and is_finite(data[key]))
		for key in ["calibration", "signal_fault"]: assert(data.get(key) is Dictionary and data[key].get("steps") is Array)
		_config = data
	return _config.duplicate(true)


static func empty_fault() -> Dictionary:
	return {"stage": "idle", "baseline": {}, "observed": {}, "diagnosis": "", "resume": {}, "repair": {}}


static func initial_state() -> Dictionary:
	return {"lab": {"truth": 30.0, "sensor": SensorCatalog.initial_state(), "points": [], "verification": {}}, "experiment": {}, "fault": empty_fault()}
