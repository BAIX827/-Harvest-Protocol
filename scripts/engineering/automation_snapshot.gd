extends RefCounted

const Catalog = preload("res://scripts/engineering/automation_catalog.gd")
const Controller = preload("res://scripts/engineering/automation_controller.gd")
const Network = preload("res://scripts/engineering/irrigation_network.gd")
const Sensor = preload("res://scripts/engineering/sensor_model.gd")
const Clock = preload("res://scripts/simulation/simulation_clock.gd")


static func number(value: Variant, low: float, high: float) -> bool:
	return (value is float or value is int) and is_finite(float(value)) and float(value) >= low and float(value) <= high


static func whole(value: Variant, low: int, high: int) -> bool:
	return number(value, low, high) and float(value) == floor(float(value))


static func validate(value: Variant, farm: RefCounted, now: int) -> Dictionary:
	var bad := {"ok": false, "code": "invalid_automation", "message": "自动规则、节点连接、输出或日志状态无效。"}
	if not value is Dictionary: return bad
	for field in Catalog.initial_state():
		if not value.has(field): return bad
	if not value.installed is bool or value.mode not in ["manual", "auto"] or not value.latch is bool or not value.output is bool: return bad
	if not Controller.valid_thresholds(value.start, value.stop) or not Catalog.REASONS.has(value.code): return bad
	if not value.detail is String or value.detail.length() > 256: return bad
	if not whole(value.last_minute, 480, now) or not whole(value.sensor_revision, -1, int(farm.sensor.revision)): return bad
	if value.last_value != null and not number(value.last_value, 0, 60): return bad
	if not value.edges is Array or value.edges.size() > 2: return bad
	var seen: Dictionary = {}
	for edge in value.edges:
		if edge not in Catalog.EDGES or seen.has(edge): return bad
		seen[edge] = true
	if not value.positions is Dictionary or value.positions.size() != 3: return bad
	for node in ["sensor", "decision", "pump"]:
		var point: Variant = value.positions.get(node)
		if not point is Array or point.size() != 2 or not number(point[0], -4000, 4000) or not number(point[1], -4000, 4000): return bad
	if not value.logs is Array or value.logs.size() > int(Catalog.config().log_limit) or not whole(value.next_log_id, 1, 1000000000) or value.logs.size() != mini(int(value.next_log_id) - 1, int(Catalog.config().log_limit)): return bad
	var id: int = int(value.next_log_id) - value.logs.size()
	var logs: Array = []
	var last_minute: int = 480
	for row in value.logs:
		if not row is Dictionary or not whole(row.get("id"), id, id) or not whole(row.get("minute"), last_minute, now): return bad
		if not Catalog.REASONS.has(row.get("code")) or row.get("mode") not in ["manual", "auto"] or not row.get("output") is bool: return bad
		if not row.get("detail") is String or row.detail.length() > 256: return bad
		if (row.mode == "manual") != (row.code == "manual"): return bad
		if not row.has("value") or (row.value != null and not number(row.value, 0, 60)) or not Controller.valid_thresholds(row.get("start"), row.get("stop")): return bad
		if row.code in ["below", "hold_on"]:
			if not row.output or row.value == null: return bad
		elif row.output: return bad
		if row.code == "below" and float(row.value) >= float(row.start): return bad
		if row.code == "stop" and (row.value == null or float(row.value) < float(row.stop)): return bad
		if row.code in ["hold_on", "hold_off"] and (row.value == null or float(row.value) < float(row.start) or float(row.value) >= float(row.stop)): return bad
		last_minute = int(row.minute)
		var normalized: Dictionary = row.duplicate(true)
		normalized.id = int(row.id)
		normalized.minute = int(row.minute)
		logs.append(normalized)
		id += 1
	var state: Dictionary = value.duplicate(true)
	state.edges.sort()
	state.logs = logs
	for field in ["last_minute", "sensor_revision", "next_log_id"]: state[field] = int(state[field])
	if value.mode == "manual":
		if value.output or value.latch or value.code != "manual" or value.detail != Catalog.REASONS.manual: return bad
	else:
		if not value.installed or farm.engineering.enabled: return bad
		farm.automation = state.duplicate(true)
		var clock := Clock.new()
		clock.total_minutes = now
		var control := Controller.new(farm, Network.new(farm), Sensor.new(farm), clock, false)
		control.evaluate(now)
		for field in ["code", "detail", "output", "latch", "last_value", "last_minute", "sensor_revision"]:
			if farm.automation[field] != state[field]: return bad
	return {"ok": true, "state": state}
