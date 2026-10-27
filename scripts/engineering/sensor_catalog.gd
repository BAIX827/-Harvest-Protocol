extends RefCounted
## These are explainable game parameters, not a real instrument specification.

static var _data: Dictionary = {}


static func config() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/sensor.json"))
		assert(parsed is Dictionary and parsed.get("soils") is Dictionary and parsed.get("mounts") is Dictionary)
		for key in ["sample_minutes", "history_limit", "adc_max", "reference_v", "dry_v", "volts_per_point", "noise_v"]:
			assert(parsed.get(key) is float and is_finite(parsed[key]) and parsed[key] > 0)
		assert(parsed.sample_minutes == 5 and parsed.history_limit == 180 and parsed.adc_max == 4095)
		assert(parsed.get("hardware_bias_v") is float and is_finite(parsed.hardware_bias_v))
		assert(parsed.get("seed") is String and parsed.seed.is_valid_int())
		for id in parsed.soils:
			assert(parsed.soils[id].get("name") is String and parsed.soils[id].get("gain") is float and parsed.soils[id].gain > 0 and parsed.soils[id].get("offset_v") is float)
		for id in parsed.mounts:
			assert(parsed.mounts[id].get("name") is String and parsed.mounts[id].get("offset_v") is float)
		_data = parsed
	return _data.duplicate(true)


static func initial_state() -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(config().seed)
	return {"instance_id": "soil-probe-01", "installed": false, "cell": [10, 8], "connected": true,
		"fault": "none", "soil": "loam", "mount": "seated", "slope": 1.0, "offset": 0.0,
		"revision": 0, "sample_count": 0, "rng_seed": str(rng.seed), "rng_state": str(rng.state), "latest": {}, "history": []}
