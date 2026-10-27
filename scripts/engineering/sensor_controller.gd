extends RefCounted
## All edits use the real farm channel and publish after the new sample is complete.

signal action_completed(result: Dictionary)

const Economy = preload("res://scripts/simulation/economy_model.gd")
const Model = preload("res://scripts/engineering/sensor_model.gd")
const Catalog = preload("res://scripts/engineering/sensor_catalog.gd")
var economy: Economy
var model: Model


func _init(shared_economy: Economy, shared_model: Model) -> void:
	economy = shared_economy
	model = shared_model


func _reject(message: String) -> Dictionary:
	return {"ok": false, "changed": false, "message": message}


func _busy() -> bool:
	return economy.farm.trade_in_progress


func _finish(message: String, resample: bool = true) -> Dictionary:
	if resample: model.sample(economy.clock.total_minutes)
	var result := {"ok": true, "changed": true, "message": message}
	economy.farm.sensor_changed.emit()
	economy.farm.supplies_changed.emit()
	action_completed.emit(result)
	economy.farm.trade_in_progress = false
	return result


func install() -> Dictionary:
	var farm := economy.farm
	if _busy(): return _reject("上一项操作正在完成。")
	if farm.sensor.installed: return _reject("该测量通道已安装探头，不会重复消耗库存。")
	if int(farm.parts_stock.get("sensor_basic", 0)) < 1: return _reject("请先采购土壤水分探头。")
	farm.trade_in_progress = true
	farm.parts_stock.sensor_basic -= 1
	farm.sensor.installed = true
	farm.sensor.revision += 1
	return _finish("探头已安装并采样；每 5 个游戏分钟更新一次。")


func remove() -> Dictionary:
	var farm := economy.farm
	if _busy(): return _reject("上一项操作正在完成。")
	if not farm.sensor.installed or int(farm.parts_stock.get("sensor_basic", 0)) >= 1000: return _reject("没有可拆回的探头，或备用库存已满。")
	farm.trade_in_progress = true
	farm.sensor.installed = false
	farm.sensor.revision += 1
	farm.parts_stock.sensor_basic = int(farm.parts_stock.get("sensor_basic", 0)) + 1
	return _finish("探头已退回库存，历史保留；当前测量无效。", false)


func configure(point: Vector2i, soil: String, mount: String) -> Dictionary:
	if _busy(): return _reject("上一项操作正在完成。")
	var config := Catalog.config()
	if not economy.farm.is_arable(point) or not config.soils.has(soil) or not config.mounts.has(mount): return _reject("请选择可耕地及有效的土壤响应和安装方式。")
	var state: Dictionary = economy.farm.sensor
	if state.cell == [point.x, point.y] and state.soil == soil and state.mount == mount: return _reject("位置和安装条件未改变；可点击立即采样。")
	economy.farm.trade_in_progress = true
	state.cell = [point.x, point.y]
	state.soil = soil
	state.mount = mount
	state.revision += 1
	return _finish("测量位置 / 条件已更新。校准系数保留，请核对是否仍然适用。")


func set_connected(connected: bool) -> Dictionary:
	if _busy(): return _reject("上一项操作正在完成。")
	if economy.farm.sensor.connected == connected: return _reject("信号连接没有改变。")
	economy.farm.trade_in_progress = true
	economy.farm.sensor.connected = connected
	economy.farm.sensor.revision += 1
	return _finish("信号线已接通。" if connected else "信号线已断开；无效测量不能作为正常控制输入。")


func set_fault(fault: String) -> Dictionary:
	if _busy(): return _reject("上一项操作正在完成。")
	if fault not in Model.FAULTS: return _reject("未知故障类型。")
	if economy.farm.sensor.fault == fault: return _reject("故障条件未改变。")
	economy.farm.trade_in_progress = true
	economy.farm.sensor.fault = fault
	economy.farm.sensor.revision += 1
	return _finish("已设置故障：%s。" % {"none": "正常", "open": "开路", "short": "短路", "stuck": "卡住"}[fault])


static func _number(value: Variant, low: float, high: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= low and float(value) <= high


func set_calibration(slope: Variant, offset: Variant) -> Dictionary:
	if _busy(): return _reject("上一项操作正在完成。")
	if not _number(slope, 0.5, 1.5) or not _number(offset, -20, 20): return _reject("增益须在 0.5～1.5，偏移须在 -20～20 个百分点内。")
	if is_equal_approx(float(economy.farm.sensor.slope), float(slope)) and is_equal_approx(float(economy.farm.sensor.offset), float(offset)): return _reject("校准系数未改变。")
	economy.farm.trade_in_progress = true
	economy.farm.sensor.slope = float(slope)
	economy.farm.sensor.offset = float(offset)
	economy.farm.sensor.revision += 1
	return _finish("已应用校准：读数 = 出厂换算值 × %.3f %+.3f；旧历史不会重算。" % [slope, offset])


func calibrate(reference: Variant) -> Dictionary:
	if _busy(): return _reject("上一项操作正在完成。")
	if not _number(reference, 0, 60): return _reject("参考值必须为 0～60% 的有限数值。")
	var reading := model.current(economy.clock.total_minutes)
	if not reading.valid: return _reject("没有有效采样，不能校准。请先排除故障并采样。")
	if not is_equal_approx(float(reading.truth), model.truth()): return _reject("采样后地块已变化，请先立即采样再校准。")
	var offset := float(reference) - float(reading.factory) * float(economy.farm.sensor.slope)
	return set_calibration(economy.farm.sensor.slope, offset)


func sample_now() -> Dictionary:
	if _busy(): return _reject("上一项操作正在完成。")
	if not economy.farm.sensor.installed: return _reject("请先安装探头。")
	economy.farm.trade_in_progress = true
	return _finish("已完成一次即时采样；暂停时只更新测量，不推进农场时间。")


func apply_profile_calibration(soil: String, mount: String, slope: Variant, offset: Variant) -> Dictionary:
	if _busy(): return _reject("上一项操作正在完成。")
	var state: Dictionary = economy.farm.sensor
	var config := Catalog.config()
	if not state.installed or not state.connected or state.fault != "none": return _reject("请先安装、接通并修复农场探头。")
	if not config.soils.has(soil) or not config.mounts.has(mount) or not _number(slope, 0.5, 1.5) or not _number(offset, -20, 20): return _reject("实验条件或校准系数无效。")
	economy.farm.trade_in_progress = true
	state.soil = soil
	state.mount = mount
	state.slope = float(slope)
	state.offset = float(offset)
	state.revision += 1
	return _finish("实验条件和系数已同步到农场探头；位置与真实土壤水分保留。")
