extends RefCounted
## Reject impossible samples and stale configuration before mutating the live farm.

const Catalog = preload("res://scripts/engineering/sensor_catalog.gd")
const Model = preload("res://scripts/engineering/sensor_model.gd")


static func _number(value: Variant, low: float, high: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= low and float(value) <= high


static func _whole(value: Variant, low: int, high: int) -> bool:
	return _number(value, low, high) and float(value) == floor(float(value))


static func _point(value: Variant, farm: RefCounted) -> bool:
	return value is Array and value.size() == 2 and _whole(value[0], 0, 23) and _whole(value[1], 0, 23) and farm.is_arable(Vector2i(value[0], value[1]))


static func _row(value: Variant, farm: RefCounted, now: int, revision: int) -> Dictionary:
	if not value is Dictionary: return {}
	for field in ["serial", "minute", "revision", "cell", "soil", "mount", "slope", "offset", "connected", "fault", "truth", "raw_adc", "volts", "factory", "reading", "valid", "code"]:
		if not value.has(field): return {}
	var config := Catalog.config()
	for field in ["serial", "minute", "revision"]:
		if not _whole(value.get(field), 0, 1000000000): return {}
	if int(value.serial) < 1 or int(value.minute) < 480 or int(value.minute) > now or int(value.minute) % 5 != 0 or int(value.revision) > revision: return {}
	if not _point(value.get("cell"), farm) or not config.soils.has(value.get("soil")) or not config.mounts.has(value.get("mount")): return {}
	if not value.get("connected") is bool or value.get("fault") not in Model.FAULTS or not value.get("valid") is bool: return {}
	if not _number(value.get("slope"), 0.5, 1.5) or not _number(value.get("offset"), -20, 20) or not _number(value.get("truth"), 0, 60): return {}
	var adc: Variant = value.get("raw_adc")
	var converted: Variant = null
	if value.connected:
		if not _whole(adc, 0, int(config.adc_max)): return {}
		if not _number(value.get("volts"), 0, float(config.reference_v)) or not _number(value.get("factory"), -100, 100): return {}
		if absf(float(value.volts) - Model.voltage(int(adc))) > 0.000000001 or absf(float(value.factory) - Model.factory_value(int(adc))) > 0.000000001: return {}
		converted = float(value.factory) * float(value.slope) + float(value.offset)
		if value.fault == "open" and int(adc) != int(config.adc_max): return {}
		if value.fault == "short" and int(adc) != 0: return {}
		if value.fault == "none":
			var soil: Dictionary = config.soils[value.soil]
			var ideal := (float(config.dry_v) + float(value.truth) * float(config.volts_per_point)) * float(soil.gain) + float(soil.offset_v) + float(config.mounts[value.mount].offset_v) + float(config.hardware_bias_v)
			if absf(float(value.volts) - clampf(ideal, 0, float(config.reference_v))) > float(config.noise_v) + float(config.reference_v) / float(config.adc_max) * 0.500001: return {}
	elif adc != null or value.get("volts") != null or value.get("factory") != null: return {}
	var code := Model.classify(value.connected, value.fault, adc, converted)
	if value.get("code") != code or value.valid != (code == "ok"): return {}
	if value.valid:
		if not _number(value.get("reading"), 0, 60) or absf(float(value.reading) - float(converted)) > 0.000000001: return {}
	elif value.get("reading") != null: return {}
	var normalized: Dictionary = value.duplicate(true)
	for field in ["serial", "minute", "revision"]: normalized[field] = int(value[field])
	normalized.cell = [int(value.cell[0]), int(value.cell[1])]
	if adc != null: normalized.raw_adc = int(adc)
	return normalized


static func validate(value: Variant, farm: RefCounted, now: int) -> Dictionary:
	var bad := {"ok": false, "code": "invalid_sensor", "message": "传感器配置、采样数据或历史记录无效。"}
	if not value is Dictionary: return bad
	var config := Catalog.config()
	if value.get("instance_id") != "soil-probe-01" or not value.get("installed") is bool or not value.get("connected") is bool: return bad
	if not _point(value.get("cell"), farm) or not config.soils.has(value.get("soil")) or not config.mounts.has(value.get("mount")) or value.get("fault") not in Model.FAULTS: return bad
	if not _number(value.get("slope"), 0.5, 1.5) or not _number(value.get("offset"), -20, 20): return bad
	if not _whole(value.get("revision"), 0, 1000000000) or not _whole(value.get("sample_count"), 0, 1000000000): return bad
	for field in ["rng_seed", "rng_state"]:
		var encoded: Variant = value.get(field)
		if not encoded is String or encoded.length() > 20 or not encoded.is_valid_int() or str(int(encoded)) != encoded: return bad
	if value.rng_seed != config.seed: return bad
	if not value.get("history") is Array or value.history.size() > int(config.history_limit) or value.history.size() != mini(int(value.sample_count), int(config.history_limit)) or not value.get("latest") is Dictionary: return bad
	var history: Array = []
	var minute: int = 480
	var revision: int = 0
	var serial: int = int(value.sample_count) - value.history.size()
	for entry in value.history:
		var normalized := _row(entry, farm, now, int(value.revision))
		if normalized.is_empty() or int(normalized.serial) != serial + 1 or int(normalized.minute) < minute or int(normalized.revision) < revision: return bad
		serial += 1
		minute = int(normalized.minute)
		revision = int(normalized.revision)
		history.append(normalized)
	var latest: Dictionary = {}
	if not history.is_empty():
		latest = _row(value.latest, farm, now, int(value.revision))
		if JSON.stringify(latest, "", true, true) != JSON.stringify(history.back(), "", true, true): return bad
	elif not value.latest.is_empty() or value.installed: return bad
	if value.installed:
		if latest.cell != [int(value.cell[0]), int(value.cell[1])]: return bad
		for field in ["revision", "soil", "mount", "slope", "offset", "connected", "fault"]:
			if latest.get(field) != value.get(field): return bad
	var state: Dictionary = value.duplicate(true)
	state.cell = [int(value.cell[0]), int(value.cell[1])]
	state.revision = int(value.revision)
	state.sample_count = int(value.sample_count)
	state.latest = latest
	state.history = history
	return {"ok": true, "state": state}
