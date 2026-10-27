extends RefCounted
## One measurement channel with independent noise and an explicit validity contract.

const Farm = preload("res://scripts/simulation/farm_state.gd")
const Catalog = preload("res://scripts/engineering/sensor_catalog.gd")
const FAULTS := ["none", "open", "short", "stuck"]
const REASONS := {"ok": "有效测量", "missing": "探头未安装", "pending": "等待采样", "disconnected": "探头信号线断开",
	"open": "开路故障：信号接近高电平", "short": "短路故障：信号接近零电平", "stuck": "读数卡住：保留的原始信号无效",
	"saturated": "原始信号超出测量范围", "out_of_range": "换算读数超出 0～60%", "stale": "测量已过期或配置已改变"}
var farm: Farm


func _init(state: Farm) -> void:
	farm = state


func point() -> Vector2i:
	return Vector2i(farm.sensor.cell[0], farm.sensor.cell[1])


func truth() -> float:
	return float(farm.plot_at(point()).moisture)


static func voltage(adc: int) -> float:
	var config := Catalog.config()
	return float(adc) * float(config.reference_v) / float(config.adc_max)


static func factory_value(adc: int) -> float:
	var config := Catalog.config()
	return (voltage(adc) - float(config.dry_v)) / float(config.volts_per_point)


static func classify(connected: bool, fault: String, adc: Variant, reading: Variant) -> String:
	if not connected: return "disconnected"
	if fault != "none": return fault
	if adc == 0 or adc == int(Catalog.config().adc_max): return "saturated"
	if not (reading is float or reading is int) or not is_finite(float(reading)) or float(reading) < 0 or float(reading) > Farm.MAX_MOISTURE: return "out_of_range"
	return "ok"


func sample(minute: int) -> bool:
	var state: Dictionary = farm.sensor
	if not state.installed: return false
	var config := Catalog.config()
	var adc: Variant = null
	if state.connected:
		if state.fault == "open": adc = int(config.adc_max)
		elif state.fault == "short": adc = 0
		elif state.fault == "stuck": adc = state.latest.get("raw_adc", 2048) if state.latest.get("raw_adc") != null else 2048
		else:
			var rng := RandomNumberGenerator.new()
			rng.seed = int(state.rng_seed)
			rng.state = int(state.rng_state)
			var soil: Dictionary = config.soils[state.soil]
			var mount: Dictionary = config.mounts[state.mount]
			var signal_v := (float(config.dry_v) + truth() * float(config.volts_per_point)) * float(soil.gain) + float(soil.offset_v) + float(mount.offset_v) + float(config.hardware_bias_v) + rng.randf_range(-float(config.noise_v), float(config.noise_v))
			state.rng_state = str(rng.state)
			adc = clampi(roundi(signal_v / float(config.reference_v) * float(config.adc_max)), 0, int(config.adc_max))
	var factory: Variant = factory_value(int(adc)) if adc != null else null
	var converted: Variant = float(factory) * float(state.slope) + float(state.offset) if factory != null else null
	var code := classify(state.connected, state.fault, adc, converted)
	state.sample_count += 1
	var row := {"serial": state.sample_count, "minute": minute, "revision": state.revision, "cell": state.cell.duplicate(),
		"soil": state.soil, "mount": state.mount, "slope": state.slope, "offset": state.offset,
		"connected": state.connected, "fault": state.fault, "truth": truth(), "raw_adc": adc,
		"volts": voltage(int(adc)) if adc != null else null, "factory": factory,
		"reading": converted if code == "ok" else null, "valid": code == "ok", "code": code}
	state.latest = row.duplicate(true)
	state.history.append(row)
	while state.history.size() > int(config.history_limit): state.history.pop_front()
	return true


func current(minute: int) -> Dictionary:
	var state: Dictionary = farm.sensor
	var code: String = "missing" if not state.installed else ("pending" if state.latest.is_empty() else "ok")
	if code == "ok":
		if int(state.latest.revision) != int(state.revision) or minute - int(state.latest.minute) > int(Catalog.config().sample_minutes) * 2:
			code = "stale"
		else:
			return state.latest.duplicate(true)
	return {"valid": false, "reading": null, "code": code, "minute": minute, "raw_adc": null, "volts": null, "factory": null, "truth": null}


func control_reading(minute: int) -> Dictionary:
	var measured := current(minute)
	return {"valid": measured.valid, "value": measured.reading if measured.valid else null, "reason": REASONS[measured.code], "minute": measured.minute}
