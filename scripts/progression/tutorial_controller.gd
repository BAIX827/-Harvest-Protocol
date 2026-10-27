extends RefCounted
## Guidance is derived from real work, trades, supply and teaching evidence.

const Farm = preload("res://scripts/simulation/farm_state.gd")
const Simulation = preload("res://scripts/simulation/farm_simulation.gd")
const Economy = preload("res://scripts/simulation/economy_model.gd")
const Catalog = preload("res://scripts/progression/tutorial_catalog.gd")
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
	if current().id == "harvest":
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
	if id == "plant": return "入口右上 (8,13)：走近后 2 翻土、3 生菜播种、4 浇水。已有作物时可对它人工浇一次，成功才计数。"
	if id == "harvest":
		var plot := farm.plot_at(target())
		if not plot.crop.is_empty() and simulation.crops.is_mature(plot.crop): return "目标作物已成熟。按 5，走近后点击收获，收成先进入库存。"
		return "选择 12× 观察生长；地块检查显示缺水或过湿原因，按 4 合理补水。成熟后按 5 收获，等待和照料不花种子。"
	if id == "sell": return "按 B 出售已收获作物。第一份生菜售价 18 币；初始资金、模块退款和应急金都不算销售。"
	if id == "restock": return "按 B 买 1 份生菜种子（6 币），让一轮收成支持下一轮种植。已提前购买也会认可。"
	if id == "manual": return "在 (11,9) 附近翻土；E 采购安装水箱、泵、电池，铺 (10,8)(11,8)(12,8)，补水充电，手动开泵后关闭 E 并继续。"
	if id == "experiment": return "手动泵要自己盯水分。按 L 记录黏土 20% / 40% 样杯、校准复核，再同步到 I 已安装探头；完成后可用测量替代猜测。"
	if id == "auto": return "按 T 安装控制器，接通 探头→判断→泵 并选自动；探头放在覆盖翻土地。先核对读数与阈值，再继续模拟，实际出水才算。"
	if id == "fault": return "按 L 进行真实断线、观察、诊断、I 接线和自动恢复；T 日志可核对原因。先暂停再开始，修复中间区间仍可能停泵。"
	if id == "improve":
		if farm.journey.improvement.baseline.is_empty(): return "在 H 点击开始自主调整，记录当前规则；然后去 T 亲自改一组合理阈值，继续观察新规则实际自动出水。"
		if farm.journey.improvement.change.is_empty(): return "去 T 修改不同于试验起点的阈值并应用。保持有效测量和自动模式；可根据当前读数选择启动值，避免中间区间一直停泵。"
		return "新阈值已记录。继续模拟并排除缺水断电，只有新规则下实际自动出水、耗电和有效采样才完成验证。"
	return "已经完成种植销售、补购、手动供水、校准、自动化、故障恢复与自主调整。H 可看真实经营对照，继续种植或调整方案。"


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
