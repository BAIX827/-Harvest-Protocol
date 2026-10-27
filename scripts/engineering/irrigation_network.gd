extends RefCounted
## Underground pipe connectivity and resource-limited, fixed-step irrigation.

const Farm = preload("res://scripts/simulation/farm_state.gd")
const Catalog = preload("res://scripts/engineering/module_catalog.gd")
const PUMP := Vector2i(9, 6)
const OUTLET := Vector2i(11, 8)
const TANK := Vector2i(8, 6)
const POWER := Vector2i(10, 6)
const SITE := Rect2i(8, 6, 7, 6)
const COVERAGE := Rect2i(10, 8, 3, 2)
const STARTER_ROUTE := [Vector2i(9, 7), Vector2i(10, 7), Vector2i(11, 7)]
const DIRECTIONS := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
const EPSILON: float = 0.000000001

var farm: Farm


func _init(state: Farm) -> void:
	farm = state


static func key(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]


static func cell(value: String) -> Vector2i:
	var pair := value.split(",")
	if pair.size() != 2 or not pair[0].is_valid_int() or not pair[1].is_valid_int(): return Farm.INVALID_CELL
	var result := Vector2i(int(pair[0]), int(pair[1]))
	return result if key(result) == value else Farm.INVALID_CELL


static func can_pipe(point: Vector2i) -> bool:
	return SITE.has_point(point) and point not in [TANK, PUMP, POWER, OUTLET]


func connected() -> bool:
	var nodes: Dictionary = {key(PUMP): true, key(OUTLET): true}
	for pipe in farm.engineering.pipes: nodes[pipe] = true
	var queue: Array[Vector2i] = [PUMP]
	var visited: Dictionary = {key(PUMP): true}
	while not queue.is_empty():
		var point: Vector2i = queue.pop_front()
		if point == OUTLET: return true
		for direction in DIRECTIONS:
			var next: Vector2i = point + direction
			if nodes.has(key(next)) and not visited.has(key(next)):
				visited[key(next)] = true
				queue.append(next)
	return false


func capacity(kind: String) -> float:
	return float(Catalog.definition(str(farm.engineering[kind])).get("capacity", 0))


func targets() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for y in range(COVERAGE.position.y, COVERAGE.end.y):
		for x in range(COVERAGE.position.x, COVERAGE.end.x):
			var point := Vector2i(x, y)
			if farm.is_arable(point) and farm.plot_at(point).tilled and float(farm.plot_at(point).moisture) < Farm.MAX_MOISTURE - EPSILON:
				result.append(point)
	return result


func status() -> Dictionary:
	var state: Dictionary = farm.engineering
	var code: String = "running"
	var reason: String = "供水、管路和供电正常"
	if not state.enabled:
		code = "off"
		reason = "手动开关已关闭"
	elif state.tank.is_empty() or state.pump.is_empty() or state.power.is_empty():
		code = "missing_module"
		reason = "请安装水箱、水泵和电池"
	elif not connected():
		code = "disconnected"
		reason = "管路断开：泵出口未接到滴灌口"
	elif not state.power_connected:
		code = "power_disconnected"
		reason = "电源已断开，请接通供电"
	elif float(state.water_l) <= EPSILON:
		code = "no_water"
		reason = "水箱缺水，请补水"
	elif float(state.energy_wh) <= EPSILON:
		code = "no_energy"
		reason = "电池电量耗尽，请充电"
	elif targets().is_empty():
		code = "no_demand"
		reason = "覆盖区没有可浇的翻土地块，或地块已达水分上限"
	var pump := Catalog.definition(state.pump)
	return {"code": code, "reason": reason, "connected": connected(), "running": code == "running",
		"flow_l_h": float(pump.get("flow_l_h", 0)) if code == "running" else 0.0,
		"power_w": float(pump.get("power_w", 0)) if code == "running" else 0.0}


func advance(minutes: int) -> bool:
	if minutes <= 0 or not status().running: return false
	var state: Dictionary = farm.engineering
	var pump := Catalog.definition(state.pump)
	var demand := targets()
	var liters_per_point := float(Catalog.config().liters_per_moisture_point)
	var requested := float(pump.flow_l_h) * float(minutes) / 60.0
	var need: float = 0.0
	for point in demand: need += (Farm.MAX_MOISTURE - float(farm.plot_at(point).moisture)) * liters_per_point
	var energy_per_liter := float(pump.power_w) / float(pump.flow_l_h)
	var amount := minf(minf(requested, need), minf(float(state.water_l), float(state.energy_wh) / energy_per_liter))
	if amount <= EPSILON: return false
	var remaining := amount
	# Equal distribution; any full plot returns its share to the others.
	while not demand.is_empty() and remaining > EPSILON:
		var share := remaining / demand.size()
		var next: Array[Vector2i] = []
		for point in demand:
			var plot := farm.plot_at(point)
			var supplied := minf(share, (Farm.MAX_MOISTURE - float(plot.moisture)) * liters_per_point)
			plot.moisture = minf(Farm.MAX_MOISTURE, float(plot.moisture) + supplied / liters_per_point)
			remaining -= supplied
			if float(plot.moisture) < Farm.MAX_MOISTURE - EPSILON: next.append(point)
		demand = next
	var delivered := amount - maxf(0.0, remaining)
	var used := delivered * energy_per_liter
	state.water_l = maxf(0.0, float(state.water_l) - delivered)
	state.energy_wh = maxf(0.0, float(state.energy_wh) - used)
	if float(state.water_l) < EPSILON: state.water_l = 0.0
	if float(state.energy_wh) < EPSILON: state.energy_wh = 0.0
	state.delivered_l += delivered
	state.used_wh += used
	return true


func preview_rate(point: Vector2i) -> float:
	if not status().running: return 0.0
	var demand := targets()
	if point not in demand: return 0.0
	var state: Dictionary = farm.engineering
	var pump := Catalog.definition(state.pump)
	var liters_per_point := float(Catalog.config().liters_per_moisture_point)
	var amount := minf(float(pump.flow_l_h) / 12.0, minf(float(state.water_l), float(state.energy_wh) * float(pump.flow_l_h) / float(pump.power_w)))
	var share := minf(amount / demand.size(), (Farm.MAX_MOISTURE - float(farm.plot_at(point).moisture)) * liters_per_point)
	return share * 12.0 / liters_per_point
