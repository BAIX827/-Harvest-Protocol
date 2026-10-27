extends RefCounted
## Isolated reference experiment; fault completion requires real farm evidence.

signal action_completed(result: Dictionary)
const Farm = preload("res://scripts/simulation/farm_state.gd")
const Sensor = preload("res://scripts/engineering/sensor_model.gd")
const SensorController = preload("res://scripts/engineering/sensor_controller.gd")
const Simulation = preload("res://scripts/simulation/farm_simulation.gd")
const Catalog = preload("res://scripts/progression/learning_catalog.gd")
var farm: Farm
var sensor_controller: SensorController
var simulation: Simulation
var _cup := Farm.new()
var _model := Sensor.new(_cup)


func _init(state: Farm, controller: SensorController, shared_simulation: Simulation) -> void:
	farm = state
	sensor_controller = controller
	simulation = shared_simulation
	for signal_name in ["sensor_changed", "engineering_changed", "automation_changed"]: farm.connect(signal_name, review)
	simulation.updated.connect(review)


func _bind() -> void:
	_cup.sensor = farm.learning.lab.sensor
	_cup.plot_at(Vector2i(10, 8)).moisture = float(farm.learning.lab.truth)


func current() -> Dictionary:
	_bind()
	return _model.current(simulation.clock.total_minutes)


func _take() -> Dictionary:
	_bind()
	_cup.sensor.installed = true
	_model.sample(simulation.clock.total_minutes)
	return _cup.sensor.latest.duplicate(true)


func _fail(message: String) -> Dictionary:
	return {"ok": false, "changed": false, "message": message}


func _finish(message: String) -> Dictionary:
	var result := {"ok": true, "changed": true, "message": message}
	farm.learning_changed.emit()
	action_completed.emit(result)
	farm.trade_in_progress = false
	return result


func set_conditions(truth: Variant, soil: String, mount: String) -> Dictionary:
	if farm.trade_in_progress: return _fail("上一项操作正在完成。")
	var config := Farm.SensorCatalog.config()
	if not SensorController._number(truth, 0, 60) or not config.soils.has(soil) or not config.mounts.has(mount): return _fail("请选择 0～60% 有限参考值和有效样杯条件。")
	farm.trade_in_progress = true
	var lab: Dictionary = farm.learning.lab
	if lab.sensor.soil != soil or lab.sensor.mount != mount:
		lab.points.clear()
		lab.verification = {}
		lab.sensor.slope = 1.0
		lab.sensor.offset = 0.0
	lab.truth = float(truth)
	lab.sensor.soil = soil
	lab.sensor.mount = mount
	lab.sensor.revision += 1
	_take()
	return _finish("已更新独立样杯并采样，农场真实水分未改变；变更响应条件会清除当前参考点。")


func sample_now() -> Dictionary:
	if farm.trade_in_progress: return _fail("上一项操作正在完成。")
	farm.trade_in_progress = true
	_take()
	return _finish("已采样独立样杯，不推进游戏时间。")


func record_point(slot: int) -> Dictionary:
	if farm.trade_in_progress: return _fail("上一项操作正在完成。")
	if slot not in [0, 1]: return _fail("参考点编号无效。")
	var lab: Dictionary = farm.learning.lab
	if slot == 1:
		if lab.points.is_empty(): return _fail("请先记录 A 点。")
		if lab.points[0].soil != lab.sensor.soil or lab.points[0].mount != lab.sensor.mount: return _fail("两个参考点须保持相同响应条件。")
		if absf(float(lab.truth) - float(lab.points[0].truth)) < float(Catalog.config().reference_gap_min): return _fail("两个参考值至少相隔 10 个百分点。")
	farm.trade_in_progress = true
	lab.sensor.slope = 1.0
	lab.sensor.offset = 0.0
	lab.sensor.revision += 1
	var row := _take()
	if not row.valid:
		farm.trade_in_progress = false
		farm.learning_changed.emit()
		return _fail("样杯信号无效，未记录参考点，请选择有效范围。")
	if slot == 0: lab.points = [row]
	elif lab.points.size() == 1: lab.points.append(row)
	else: lab.points[1] = row
	lab.verification = {}
	return _finish("已记录参考点 %s，保留真实参考值及原始信号。" % ("A" if slot == 0 else "B"))


static func solve(points: Array) -> Dictionary:
	if points.size() != 2: return {"ok": false}
	var a: Dictionary = points[0]
	var b: Dictionary = points[1]
	if not a.valid or not b.valid or a.soil != b.soil or a.mount != b.mount or absf(float(a.truth) - float(b.truth)) < float(Catalog.config().reference_gap_min): return {"ok": false}
	var denominator := float(b.factory) - float(a.factory)
	if absf(denominator) < 0.000001: return {"ok": false}
	var slope := (float(b.truth) - float(a.truth)) / denominator
	var offset := float(a.truth) - slope * float(a.factory)
	return {"ok": SensorController._number(slope, 0.5, 1.5) and SensorController._number(offset, -20, 20), "slope": slope, "offset": offset}


static func verified(points: Array, row: Dictionary) -> bool:
	var solution := solve(points)
	if not solution.ok or row.is_empty() or not row.get("valid", false): return false
	if int(row.serial) <= maxi(int(points[0].serial), int(points[1].serial)) or int(row.revision) <= maxi(int(points[0].revision), int(points[1].revision)): return false
	if row.soil != points[0].soil or row.mount != points[0].mount: return false
	if absf(float(row.truth) - (float(points[0].truth) + float(points[1].truth)) / 2) > 0.000001: return false
	if absf(float(row.slope) - float(solution.slope)) > 0.000000001 or absf(float(row.offset) - float(solution.offset)) > 0.000000001: return false
	var error := absf(float(row.reading) - float(row.truth))
	return error <= float(Catalog.config().verification_tolerance) and absf(float(row.factory) - float(row.truth)) - error >= float(Catalog.config().improvement_min)


func calibrate() -> Dictionary:
	if farm.trade_in_progress: return _fail("上一项操作正在完成。")
	var lab: Dictionary = farm.learning.lab
	var solution := solve(lab.points)
	if not solution.ok: return _fail("需要两个有效、同条件且相隔至少 10 个百分点的参考样本。")
	farm.trade_in_progress = true
	lab.sensor.slope = solution.slope
	lab.sensor.offset = solution.offset
	lab.truth = (float(lab.points[0].truth) + float(lab.points[1].truth)) / 2
	lab.sensor.revision += 1
	lab.verification = _take()
	return _finish("已按两点求系数，并用中点的新采样复核：%s。" % ("误差与改善幅度达标" if verified(lab.points, lab.verification) else "尚未达标，请检查响应与样本"))


func apply_to_farm() -> Dictionary:
	if farm.trade_in_progress: return _fail("上一项操作正在完成。")
	var lab: Dictionary = farm.learning.lab
	if not verified(lab.points, lab.verification): return _fail("请先完成有效的参考实验和中点复核。")
	var row: Dictionary = lab.verification
	var result := sensor_controller.apply_profile_calibration(row.soil, row.mount, row.slope, row.offset)
	if not result.ok: return result
	farm.trade_in_progress = true
	farm.learning.experiment = {"points": lab.points.duplicate(true), "verification": row.duplicate(true), "applied_minute": simulation.clock.total_minutes, "farm_revision": farm.sensor.revision}
	return _finish("实验完成：响应条件和系数已用于农场探头，真实水分及位置保留。可继续故障教学。")


func start_fault() -> Dictionary:
	if farm.trade_in_progress: return _fail("上一项操作正在完成。")
	if farm.learning.experiment.is_empty(): return _fail("请先完成实验并同步到农场探头。")
	if farm.learning.fault.stage != "idle": return _fail("本轮故障教学已开始或完成。")
	var measured := simulation.sensor.current(simulation.clock.total_minutes)
	if farm.automation.mode != "auto" or not farm.automation.output or not simulation.irrigation.status().running or not measured.valid: return _fail("先使真实自动系统处于可供水状态，再开始演练；按 E / I / T 检查设备、测量和控制。")
	var baseline := {"minute": simulation.clock.total_minutes, "serial": farm.sensor.sample_count, "cell": farm.sensor.cell.duplicate(), "soil": farm.sensor.soil, "mount": farm.sensor.mount,
		"slope": farm.sensor.slope, "offset": farm.sensor.offset, "reading": measured.reading, "delivered_l": farm.engineering.delivered_l, "used_wh": farm.engineering.used_wh,
		"control_code": farm.automation.code, "output": true, "sample": farm.sensor.latest.duplicate(true)}
	var result := sensor_controller.set_connected(false)
	if not result.ok: return result
	farm.trade_in_progress = true
	farm.learning.fault = {"stage": "observe", "baseline": baseline, "observed": {}, "diagnosis": "", "resume": {}, "repair": {}}
	return _finish("已在真实系统设置一次信号故障。请观察原始信号和停泵日志，再记录观察。")


func _fault_present() -> bool:
	return farm.sensor.installed and not farm.sensor.connected and farm.automation.mode == "auto" and farm.automation.code == "sensor_invalid" and not farm.automation.output and simulation.sensor.current(simulation.clock.total_minutes).code == "disconnected"


func observe_fault() -> Dictionary:
	if farm.trade_in_progress: return _fail("上一项操作正在完成。")
	var task: Dictionary = farm.learning.fault
	if task.stage != "observe" or not _fault_present() or not is_equal_approx(float(farm.engineering.delivered_l), float(task.baseline.delivered_l)): return _fail("需要在真实断线、自动停泵且未继续出水的状态记录观察。")
	farm.trade_in_progress = true
	task.observed = {"minute": simulation.clock.total_minutes, "serial": farm.sensor.sample_count, "sensor_code": "disconnected", "control_code": farm.automation.code, "output": false, "delivered_l": farm.engineering.delivered_l, "sample": farm.sensor.latest.duplicate(true)}
	task.stage = "diagnose"
	return _finish("观察已记录：原始信号缺失且自动保护停泵。请选择与证据相符的原因。")


func diagnose(reason: String) -> Dictionary:
	if farm.trade_in_progress: return _fail("上一项操作正在完成。")
	if farm.learning.fault.stage != "diagnose" or not _fault_present(): return _fail("请先记录仍然存在的真实故障。")
	if reason != "signal": return _fail("与本次证据不符：检查探头原始信号及运行日志，不能只根据不出水就判断水箱或管路。")
	farm.trade_in_progress = true
	farm.learning.fault.diagnosis = reason
	farm.learning.fault.stage = "repair"
	return _finish("诊断与证据一致。按 I 接通信号，再让自动系统实际出水；仅点击修复不会完成任务。")


func review() -> void:
	var task: Dictionary = farm.learning.fault
	if task.stage != "repair": return
	var baseline: Dictionary = task.baseline
	var measured := simulation.sensor.current(simulation.clock.total_minutes)
	var compatible: bool = measured.valid and farm.sensor.connected and farm.sensor.fault == "none" and farm.sensor.sample_count > int(task.observed.serial) and farm.automation.mode == "auto"
	for field in ["cell", "soil", "mount", "slope", "offset"]:
		if farm.sensor[field] != baseline[field]: compatible = false
	if not compatible:
		if not task.resume.is_empty():
			task.resume = {}
			farm.learning_changed.emit()
		return
	if task.resume.is_empty():
		task.resume = {"minute": simulation.clock.total_minutes, "serial": farm.sensor.sample_count, "delivered_l": farm.engineering.delivered_l, "used_wh": farm.engineering.used_wh, "sample": farm.sensor.latest.duplicate(true)}
		farm.learning_changed.emit()
		return
	if farm.automation.code not in ["below", "hold_on", "stop"] or farm.sensor.sample_count <= int(task.resume.serial): return
	if float(farm.engineering.delivered_l) <= float(task.resume.delivered_l) + 0.000001 or float(farm.engineering.used_wh) <= float(task.resume.used_wh) + 0.000001: return
	task.repair = {"minute": simulation.clock.total_minutes, "serial": farm.sensor.sample_count, "reading": measured.reading, "control_code": farm.automation.code, "delivered_l": farm.engineering.delivered_l, "used_wh": farm.engineering.used_wh, "sample": farm.sensor.latest.duplicate(true)}
	task.stage = "complete"
	farm.learning_changed.emit()


func cancel_fault() -> Dictionary:
	if farm.trade_in_progress: return _fail("上一项操作正在完成。")
	if farm.learning.fault.stage not in ["observe", "diagnose", "repair"]: return _fail("没有正在进行的故障演练。")
	if farm.sensor.installed and not farm.sensor.connected: sensor_controller.set_connected(true)
	farm.trade_in_progress = true
	farm.learning.fault = Catalog.empty_fault()
	return _finish("已取消演练并接通信号；没有授予故障任务完成。")


func hint() -> String:
	var stage: String = farm.learning.fault.stage
	if stage == "idle": return "实验同步后，准备 E / I / T 的真实自动供水系统，再开始故障。"
	if stage == "observe": return "查看 I 原始信号与 T 日志，在断线停泵状态记录观察；修复前先留下证据。"
	if stage == "diagnose": return "根据信号缺失和保护日志选择故障原因。"
	if stage == "complete": return "教学完成：已有新有效测量与真实出水 / 用电恢复证据。"
	return "按 I 接通信号并保持原探头条件，再继续游戏。中间区间保持停泵时，等待变干或合理调整 T 阈值；其他故障也需要排除。当前：" + farm.automation.detail
