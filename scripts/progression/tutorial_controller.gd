extends RefCounted
## Guidance is derived from real work, trades, supply and teaching evidence.

const Farm = preload("res://scripts/simulation/farm_state.gd")
const Simulation = preload("res://scripts/simulation/farm_simulation.gd")
const Economy = preload("res://scripts/simulation/economy_model.gd")
const Catalog = preload("res://scripts/progression/tutorial_catalog.gd")
const Tools = preload("res://scripts/world/tool_controller.gd")
const Network = preload("res://scripts/engineering/irrigation_network.gd")
const Sensor = preload("res://scripts/engineering/sensor_model.gd")
var farm: Farm
var simulation: Simulation
var economy: Economy


func _init(state: Farm, sim: Simulation, shared_economy: Economy) -> void:
	farm = state
	simulation = sim
	economy = shared_economy
	farm.automation_changed.connect(_review_trial)
	farm.sensor_changed.connect(_review_trial)
	simulation.step_completed.connect(_step)


func rows() -> Array:
	var harvests: int = 0
	var standing: int = 0
	for id in Farm.SEED_ORDER: harvests += int(farm.produce_stock[id])
	for plot in farm.plots:
		if not plot.crop.is_empty(): standing += 1
	var sales: int = 0
	var purchases: int = 0
	for entry in farm.ledger:
		if entry.category == "produce_sale":
			sales += 1
			for item in entry.items: harvests += int(item.quantity)
		if entry.category == "seed_purchase": purchases += 1
	var state: Dictionary = farm.journey
	var conditions := {"plant": (standing > 0 or harvests > 0) and state.manual.water > 0,
		"harvest": harvests > 0, "sell": sales > 0, "restock": purchases > 0,
		"manual": state.modes.manual.liters > 0, "experiment": not farm.learning.experiment.is_empty(),
		"auto": state.modes.auto.liters > 0 or farm.learning.fault.stage == "complete",
		"fault": farm.learning.fault.stage == "complete", "improve": not state.improvement.proof.is_empty()}
	var result: Array = []
	for row in Catalog.config().steps:
		row.done = conditions[row.id]
		result.append(row)
	return result


func current() -> Dictionary:
	for row in rows():
		if not row.done: return row
	return {"id": "complete", "title": "连续试玩闭环完成", "destination": "H", "done": true}


func target() -> Vector2i:
	if current().id in ["plant", "harvest"]:
		var first := Farm.INVALID_CELL
		for index in range(farm.plots.size()):
			if not farm.plots[index].crop.is_empty():
				var point := Vector2i(index % Farm.WIDTH, index / Farm.WIDTH)
				if simulation.crops.is_mature(farm.plots[index].crop): return point
				if first == Farm.INVALID_CELL: first = point
		if first != Farm.INVALID_CELL: return first
	return Vector2i(7, 12) if current().id in ["plant", "harvest"] else Vector2i(10, 8)


func hint() -> String:
	if economy.can_recover(): return "已无种子、在田作物和收成，且买不起最低价种子。按 H → 经营对照与周转，明确领取应急种子与补水备用金；有备用模块也可先退货。"
	var id: String = current().id
	if id == "plant":
		var point := target()
		var plot := farm.plot_at(point)
		if not plot.crop.is_empty(): return care_hint(point, true)
		if not plot.tilled: return "下一步：走近入口右上 (8,13)，按 2 点击翻土。完成后这里会提示播种；WASD / 方向键移动。"
		return "下一步：按 3，点击 (8,13) 播种生菜，消耗 1 份种子。播种后先看水分，湿润时可以等待。"
	if id == "harvest":
		var plot := farm.plot_at(target())
		if not plot.crop.is_empty() and simulation.crops.is_mature(plot.crop): return "目标作物已成熟。按 5，走近后点击收获，收成先进入库存。"
		return care_hint(target()) if not plot.crop.is_empty() else "收成已入库。按 H 查看路线，或再种一份作物。"
	if id == "sell": return "按 B 出售已收获作物。第一份生菜售价 18 币；初始资金、模块退款和应急金都不算销售。"
	if id == "restock": return "按 B 买 1 份生菜种子（6 币），让一轮收成支持下一轮种植。已提前购买也会认可。"
	if id == "manual": return manual_hint()
	if id == "experiment": return "下一步：按 L，按顶部提示逐项完成参考实验。手动泵需自己关闭；实验同步后才完成目标。"
	if id == "auto": return automatic_hint(farm, simulation.irrigation, simulation.sensor.current(simulation.clock.total_minutes), simulation.sensor.point(), simulation.clock.paused)
	if id == "fault": return "按 L 进行真实断线、观察、诊断、I 接线和自动恢复；T 日志可核对原因。先暂停再开始，修复中间区间仍可能停泵。"
	if id == "improve":
		if farm.journey.improvement.baseline.is_empty(): return "在 H 点击开始自主调整，记录当前规则；然后去 T 亲自改一组合理阈值，继续观察新规则实际自动出水。"
		if farm.journey.improvement.change.is_empty(): return "去 T 修改不同于试验起点的阈值并应用。保持有效测量和自动模式；可根据当前读数选择启动值，避免中间区间一直停泵。"
		return "新阈值已记录。继续模拟并排除缺水断电，只有新规则下实际自动出水、耗电和有效采样才完成验证。"
	return "已经完成种植销售、补购、手动供水、校准、自动化、故障恢复与自主调整。H 可看真实经营对照，继续种植或调整方案。"


func care_hint(point: Vector2i, first_water: bool = false) -> String:
	var plot := farm.plot_at(point)
	var crop := Farm.CropCatalog.definition(plot.crop.id)
	var moisture: float = plot.moisture
	var safe_at := float(crop.optimal_max) - Tools.WATER_INCREMENT
	var prefix := "(%d,%d) %s水分 %.1f%%，适宜 %.0f～%.0f%%。" % [point.x + 1, point.y + 1, crop.name, moisture, crop.optimal_min, crop.optimal_max]
	if simulation.crops.is_mature(plot.crop):
		return prefix + "已成熟，先按 5 收获；人工浇水练习可留到下一轮，无需为了目标浇成熟作物。"
	if moisture > safe_at:
		return prefix + "现在不用浇水；一次 +%.0f 个百分点会超过适宜上限。可选 12× 等到 ≤%.0f%% 再浇。%s" % [Tools.WATER_INCREMENT, safe_at, "首项目标仍需一次成功人工浇水，等待不会扣种子。" if first_water else "雨后同样先等水分回落。"]
	if farm.watering_charges <= 0: return prefix + "水壶空了，先靠近池塘，选 4 点击水面补满（2 币）。"
	return prefix + "下一步：走近后按 4 点击浇一次，预计到 %.1f%%；再等生长，避免连续浇。%s" % [minf(Farm.MAX_MOISTURE, moisture + Tools.WATER_INCREMENT), "成功人工浇水才完成首项目标。" if first_water else "成熟后按 5 收获。"]


static func assembly_hint(state: Farm, network: Network, paused: bool) -> String:
	for kind in ["tank", "pump", "power"]:
		if not str(state.engineering[kind]).is_empty(): continue
		var stock := ""
		for id in Economy.ModuleCatalog.ids(kind):
			if int(state.parts_stock.get(id, 0)) > 0:
				stock = id
				break
		var name_value: String = {"tank": "水箱", "pump": "水泵", "power": "电池"}[kind]
		if not stock.is_empty(): return "下一步：在%s行选择库存中的%s，点击「安装库存」。安装不会重复扣款。" % [name_value, Economy.ModuleCatalog.definition(stock).name]
		return "下一步：在 E 的%s行选择型号并「采购」，随后「安装库存」。先装好这一件，再看下一步。" % name_value
	if not network.connected():
		for point in Network.STARTER_ROUTE:
			if Network.key(point) in state.engineering.pipes: continue
			if int(state.parts_stock.get("pipe", 0)) == 0: return "下一步：在 E 采购 5 段管道，再按提示逐格连接泵和出口。"
			return "下一步：在 E 管路平面点击 (%d,%d) 铺一段管。连通泵与出口后才会供水。" % [point.x + 1, point.y + 1]
	if not state.engineering.power_connected: return "下一步：在 E 点击「接通电源」，恢复供电连接。"
	if state.engineering.water_l <= 0: return "下一步：在 E 点击「补满水箱」。有水才会实际出水。"
	if state.engineering.energy_wh <= 0: return "下一步：在 E 点击「充满电池」。出水时才消耗电量。"
	if network.targets().is_empty():
		for y in range(Network.COVERAGE.position.y, Network.COVERAGE.end.y):
			for x in range(Network.COVERAGE.position.x, Network.COVERAGE.end.x):
				if state.plot_at(Vector2i(x, y)).tilled: return "覆盖翻土地已达水分上限，暂时不用供水。返回农场等待水分回落，或在覆盖区其他空地翻土；不要反复开泵。"
		return "下一步：返回农场，走到上方覆盖区 (11～13,9～10)，按 2 翻一块地。没有可浇的翻土地时会保护停泵。"
	if state.automation.mode == "auto": return "下一步：在 T 选择手动模式，回 E 打开水泵；本项目标只认真实手动出水。"
	if not state.engineering.enabled: return "下一步：在 E 点击「打开水泵」，然后返回农场继续模拟。观察水分上涨和水电消耗，手动泵需要自己关闭。"
	return "下一步：返回农场%s，观察覆盖区水分与累计出水。实际手动出水才完成目标；达到所需水分后回 E 关闭水泵。" % ["，点击顶部「继续」" if paused else "，保持模拟运行"]


func manual_hint() -> String:
	return assembly_hint(farm, simulation.irrigation, simulation.clock.paused)


static func automatic_hint(state: Farm, network: Network, measured: Dictionary, point: Vector2i, paused: bool) -> String:
	if not state.automation.installed:
		return "下一步：在 T 点击「安装库存」，装上已持有控制器。" if int(state.parts_stock.get("controller_basic", 0)) > 0 else "下一步：在 T 采购控制器，再安装库存。安装后才能接管水泵。"
	for edge in Farm.AutomationCatalog.EDGES:
		if edge not in state.automation.edges: return "下一步：在 T 连接「%s」。拖动输出端口到下一个节点输入端口，也可用「接通两条标准连线」。" % {"sensor>decision": "探头 → 判断", "decision>pump": "判断 → 水泵"}[edge]
	if not state.sensor.installed: return "下一步：按 I 采购并安装土壤探头。节点连线不能代替真实探头。"
	if not Network.COVERAGE.has_point(point) or not state.plot_at(point).tilled: return "下一步：让探头位于覆盖区 (11～13,9～10) 的翻土地。先在农场翻土，再到 I 填对应坐标并应用；未覆盖会保护停泵。"
	if not measured.valid: return "下一步：按 I 检查真实测量：%s。有效采样后才能自动供水。" % Sensor.REASONS[measured.code]
	var safety := network.precondition()
	if not safety.running: return "下一步：按 E 处理「%s」，然后回 T 检查自动控制。" % safety.reason
	if state.automation.mode != "auto": return "下一步：在 T 选择自动模式。当前有效读数 %.1f%%；启动 %.1f%% / 停止 %.1f%%，先核对适宜水分。" % [measured.reading, state.automation.start, state.automation.stop]
	if not state.automation.output: return "当前读数 %.1f%%，启动 %.1f%% / 停止 %.1f%%；%s。可等待水分低于启动值，或在 T 按作物需要调整并应用阈值。实际出水才完成目标。" % [measured.reading, state.automation.start, state.automation.stop, state.automation.detail]
	return "下一步：%s，观察自动出水与耗电。系统将按停止阈值关泵；实际消耗会计入 H。" % ["继续模拟" if paused else "保持模拟运行"]


func budget() -> Dictionary:
	var missing: Dictionary = {}
	var price: int = 0
	for id in {"tank_300": 1, "pump_eco": 1, "battery_180": 1, "pipe": 5, "sensor_basic": 1, "controller_basic": 1}:
		var owned: int = int(farm.parts_stock.get(id, 0))
		for kind in ["tank", "pump", "power"]:
			if farm.engineering[kind] == id: owned += 1
		if id == "pipe": owned += farm.engineering.pipes.size()
		if id == "sensor_basic" and farm.sensor.installed: owned += 1
		if id == "controller_basic" and farm.automation.installed: owned += 1
		var count := maxi(0, (5 if id == "pipe" else 1) - owned)
		if count > 0: missing[id] = count
		price += count * int(Economy.ModuleCatalog.definition(id).price)
	var config := Economy.ModuleCatalog.config()
	var water_fee := ceili(maxf(0.0, float(Economy.ModuleCatalog.definition("tank_300").capacity) - float(farm.engineering.water_l)) / float(config.water_liters_per_coin))
	var energy_fee := ceili(maxf(0.0, float(Economy.ModuleCatalog.definition("battery_180").capacity) - float(farm.engineering.energy_wh)) / float(config.energy_wh_per_coin))
	return {"missing": missing, "equipment": price, "water": water_fee, "energy": energy_fee, "total": price + water_fee + energy_fee}


func _measurement() -> Dictionary:
	return {"minute": simulation.clock.total_minutes, "start": farm.automation.start, "stop": farm.automation.stop,
		"serial": farm.sensor.sample_count, "delivered_l": farm.engineering.delivered_l, "used_wh": farm.engineering.used_wh}


func begin_improvement() -> Dictionary:
	if farm.trade_in_progress: return {"ok": false, "message": "上一项操作正在完成。"}
	if farm.learning.fault.stage != "complete" or not farm.journey.improvement.proof.is_empty(): return {"ok": false, "message": "先完成真实故障教学；已验证的自主调整记录保留。"}
	farm.trade_in_progress = true
	farm.journey.improvement = {"baseline": _measurement(), "change": {}, "proof": {}}
	farm.journey_changed.emit()
	farm.trade_in_progress = false
	return {"ok": true, "message": "已记录规则起点。请去 T 亲自修改阈值，再让新规则真实自动供水。这只验证新规则可运行，不证明一定更节水。"}


func _review_trial() -> void:
	var trial: Dictionary = farm.journey.improvement
	if trial.baseline.is_empty() or not trial.proof.is_empty(): return
	var healthy: bool = farm.automation.mode == "auto" and simulation.sensor.current(simulation.clock.total_minutes).valid
	var different: bool = farm.automation.start != trial.baseline.start or farm.automation.stop != trial.baseline.stop
	if not healthy or not different:
		if not trial.change.is_empty():
			trial.change = {}
			farm.journey_changed.emit()
		return
	if trial.change.is_empty() or trial.change.start != farm.automation.start or trial.change.stop != farm.automation.stop:
		trial.change = _measurement()
		farm.journey_changed.emit()


func _step(context: Dictionary) -> void:
	_review_trial()
	var trial: Dictionary = farm.journey.improvement
	if trial.change.is_empty() or not trial.proof.is_empty() or context.supply_mode != "auto" or context.supplied_l <= 0 or context.spent_wh <= 0: return
	if farm.sensor.sample_count <= int(trial.change.serial) or farm.automation.code not in ["below", "hold_on", "stop"]: return
	if farm.engineering.delivered_l <= trial.change.delivered_l or farm.engineering.used_wh <= trial.change.used_wh: return
	trial.proof = _measurement()
	trial.proof.sample = farm.sensor.latest.duplicate(true)
	trial.proof.code = farm.automation.code
