extends RefCounted
## Validate device ownership and water/energy conservation before loading.

const Catalog = preload("res://scripts/engineering/module_catalog.gd")
const Network = preload("res://scripts/engineering/irrigation_network.gd")


static func _number(value: Variant, low: float, high: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= low and float(value) <= high


static func validate(data: Variant, parts: Dictionary, acquired: Dictionary, ledger: Array, sensor_installed: bool = false) -> Dictionary:
	var bad := {"ok": false, "code": "invalid_engineering", "message": "工程模块、库存或水电资源记录不一致。"}
	if not data is Dictionary or not data.get("enabled") is bool or not data.get("power_connected") is bool: return bad
	var counts: Dictionary = {}
	for id in Catalog.ids(): counts[id] = 0
	for id in parts:
		var item := Catalog.definition(str(id))
		if not id is String or item.is_empty() or not item.available or not _number(parts[id], 0, 1000) or float(parts[id]) != floor(float(parts[id])): return bad
		counts[id] += int(parts[id])
	for kind in ["tank", "pump", "power"]:
		if not data.get(kind) is String: return bad
		var id: String = data[kind]
		if id.is_empty(): continue
		var item := Catalog.definition(id)
		if item.is_empty() or item.kind != kind or not item.available: return bad
		counts[id] += 1
	if not data.get("pipes") is Array or data.pipes.size() > 38: return bad
	var seen: Dictionary = {}
	for pipe in data.pipes:
		if not pipe is String or not Network.can_pipe(Network.cell(pipe)) or seen.has(pipe): return bad
		seen[pipe] = true
	counts.pipe += data.pipes.size()
	if sensor_installed: counts.sensor_basic += 1
	for id in counts:
		if int(counts[id]) != int(acquired.get(id, 0)): return bad
	for field in ["water_l", "energy_wh", "water_loaded_l", "energy_loaded_wh", "delivered_l", "used_wh", "discarded_water_l", "discarded_energy_wh"]:
		if not _number(data.get(field), 0, 1000000000000): return bad
	var water_capacity := float(Catalog.definition(data.tank).get("capacity", 0))
	var energy_capacity := float(Catalog.definition(data.power).get("capacity", 0))
	if float(data.water_l) > water_capacity or float(data.energy_wh) > energy_capacity: return bad
	if absf(float(data.water_loaded_l) - float(data.delivered_l) - float(data.discarded_water_l) - float(data.water_l)) > 0.000001: return bad
	if absf(float(data.energy_loaded_wh) - float(data.used_wh) - float(data.discarded_energy_wh) - float(data.energy_wh)) > 0.000001: return bad
	var water_fees: int = 0
	var energy_fees: int = 0
	for entry in ledger:
		if entry.category == "water": water_fees -= int(entry.amount)
		if entry.category == "energy": energy_fees -= int(entry.amount)
	var config := Catalog.config()
	if float(data.water_loaded_l) > water_fees * float(config.water_liters_per_coin) + 0.000001: return bad
	if float(data.energy_loaded_wh) > energy_fees * float(config.energy_wh_per_coin) + 0.000001: return bad
	var normalized: Dictionary = data.duplicate(true)
	normalized.pipes.sort()
	return {"ok": true, "state": normalized}
