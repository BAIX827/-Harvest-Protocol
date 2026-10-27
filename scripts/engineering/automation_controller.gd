extends RefCounted
## One shared control model. It never reads teaching truth to decide a command.

signal action_completed(result: Dictionary)
const Farm = preload("res://scripts/simulation/farm_state.gd")
const Network = preload("res://scripts/engineering/irrigation_network.gd")
const Sensor = preload("res://scripts/engineering/sensor_model.gd")
const Clock = preload("res://scripts/simulation/simulation_clock.gd")
const Catalog = preload("res://scripts/engineering/automation_catalog.gd")
var farm: Farm
var network: Network
var sensor: Sensor
var clock: Clock


func _init(state: Farm, shared_network: Network, shared_sensor: Sensor, shared_clock: Clock, watch: bool = true) -> void:
	farm = state
	network = shared_network
	sensor = shared_sensor
	clock = shared_clock
	if watch:
		farm.engineering_changed.connect(reconcile)
		farm.sensor_changed.connect(reconcile)


func reconcile() -> void:
	if evaluate(clock.total_minutes): farm.automation_changed.emit()


func evaluate(minute: int) -> bool:
	var state: Dictionary = farm.automation
	if state.mode == "manual": return false
	var before := JSON.stringify(state, "", true, true)
	var measured := sensor.control_reading(minute)
	var revision: int = int(farm.sensor.revision)
	if revision != int(state.sensor_revision): state.latch = false
	state.sensor_revision = revision
	var code: String = ""
	if not state.installed: code = "controller_missing"
	elif not Catalog.EDGES.all(func(edge: String) -> bool: return edge in state.edges): code = "graph_open"
	elif not measured.valid: code = "sensor_invalid"
	elif not Network.COVERAGE.has_point(sensor.point()) or not farm.plot_at(sensor.point()).tilled: code = "sensor_outside"
	else: code = str(network.precondition().code)
	if code != "running":
		state.latch = false
	elif float(measured.value) < float(state.start):
		state.latch = true
		code = "below"
	elif float(measured.value) >= float(state.stop):
		state.latch = false
		code = "stop"
	else:
		code = "hold_on" if state.latch else "hold_off"
	var detail: String = measured.reason if code == "sensor_invalid" else Catalog.REASONS[code]
	var changed: bool = state.code != code or state.output != state.latch or state.detail != detail
	state.code = code
	state.detail = detail
	state.output = state.latch
	state.last_value = measured.value if measured.valid else null
	state.last_minute = minute
	if changed: _record(minute)
	return JSON.stringify(state, "", true, true) != before


func _record(minute: int) -> void:
	var state: Dictionary = farm.automation
	state.logs.append({"id": state.next_log_id, "minute": minute, "code": state.code, "detail": state.detail, "mode": state.mode, "output": state.output, "value": state.last_value, "start": state.start, "stop": state.stop})
	state.next_log_id += 1
	while state.logs.size() > int(Catalog.config().log_limit): state.logs.pop_front()


func _fail(message: String) -> Dictionary:
	return {"ok": false, "changed": false, "message": message}


func _finish(message: String, record_edit: bool = false) -> Dictionary:
	evaluate(clock.total_minutes)
	if record_edit: _record(clock.total_minutes)
	farm.automation_changed.emit()
	farm.supplies_changed.emit()
	var result := {"ok": true, "changed": true, "message": message}
	action_completed.emit(result)
	farm.trade_in_progress = false
	return result


func install() -> Dictionary:
	if farm.trade_in_progress: return _fail("上一项操作正在完成。")
	if farm.automation.installed or int(farm.parts_stock.get("controller_basic", 0)) < 1: return _fail("请先采购控制器；已安装时不重复消耗。")
	farm.trade_in_progress = true
	farm.parts_stock.controller_basic -= 1
	farm.automation.installed = true
	return _finish("控制器已安装，请连接节点并选择自动模式。")


func remove() -> Dictionary:
	if farm.trade_in_progress: return _fail("上一项操作正在完成。")
	if not farm.automation.installed or int(farm.parts_stock.get("controller_basic", 0)) >= 1000: return _fail("没有可拆控制器，或库存已满。")
	farm.trade_in_progress = true
	farm.automation.installed = false
	farm.parts_stock.controller_basic = int(farm.parts_stock.get("controller_basic", 0)) + 1
	_manual()
	return _finish("控制器已退回库存，已停泵并返回手动模式。")


func _manual() -> void:
	var state: Dictionary = farm.automation
	state.mode = "manual"
	state.latch = false
	state.output = false
	state.code = "manual"
	state.detail = Catalog.REASONS.manual
	state.last_value = null
	state.last_minute = clock.total_minutes
	farm.engineering.enabled = false
	_record(clock.total_minutes)


func set_mode(mode: String) -> Dictionary:
	if farm.trade_in_progress: return _fail("上一项操作正在完成。")
	if mode not in ["manual", "auto"] or mode == farm.automation.mode: return _fail("模式无效或未改变。")
	if mode == "auto" and not farm.automation.installed: return _fail("请先安装控制器。")
	farm.trade_in_progress = true
	_manual()
	farm.automation.mode = mode
	return _finish("已切换%s模式；切换时先停泵，自动模式根据有效链重新判断。" % ("自动" if mode == "auto" else "手动"))


func set_thresholds(start: Variant, stop: Variant) -> Dictionary:
	if farm.trade_in_progress: return _fail("上一项操作正在完成。")
	if not valid_thresholds(start, stop): return _fail("需要 0 ≤ 启动值 < 停止值 ≤ 60%，且为有限数值。")
	if farm.automation.start == start and farm.automation.stop == stop: return _fail("阈值未改变。")
	farm.trade_in_progress = true
	farm.automation.start = float(start)
	farm.automation.stop = float(stop)
	farm.automation.latch = false
	return _finish("阈值已更新，已清除旧开泵前态。", true)


static func valid_thresholds(start: Variant, stop: Variant) -> bool:
	return (start is int or start is float) and (stop is int or stop is float) and is_finite(float(start)) and is_finite(float(stop)) and float(start) >= 0 and float(start) < float(stop) and float(stop) <= 60


func set_connection(from_node: String, from_port: int, to_node: String, to_port: int, connected: bool) -> Dictionary:
	if farm.trade_in_progress: return _fail("上一项操作正在完成。")
	var edge := from_node + ">" + to_node
	if from_port != 0 or to_port != 0 or edge not in Catalog.EDGES: return _fail("端口类型或方向无效，只能连接探头→判断→水泵。")
	if (edge in farm.automation.edges) == connected: return _fail("连接未改变。")
	farm.trade_in_progress = true
	if connected: farm.automation.edges.append(edge)
	else: farm.automation.edges.erase(edge)
	farm.automation.edges.sort()
	return _finish("节点连接已%s。" % ("接通" if connected else "断开"))


func set_position(node: String, position: Vector2) -> Dictionary:
	if farm.trade_in_progress: return _fail("上一项操作正在完成。")
	if node not in ["sensor", "decision", "pump"] or not position.is_finite() or absf(position.x) > 4000 or absf(position.y) > 4000: return _fail("节点位置无效。")
	farm.trade_in_progress = true
	farm.automation.positions[node] = [float(position.x), float(position.y)]
	return _finish("节点位置已记录。")
