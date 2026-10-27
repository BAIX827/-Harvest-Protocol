extends RefCounted
## Decode into independent objects. No live farm is touched during validation.

const Farm = preload("res://scripts/simulation/farm_state.gd")
const Simulation = preload("res://scripts/simulation/farm_simulation.gd")
const Player = preload("res://scripts/world/player.gd")
const Tools = preload("res://scripts/world/tool_controller.gd")
const Economy = preload("res://scripts/simulation/economy_model.gd")
const ModuleCatalog = preload("res://scripts/engineering/module_catalog.gd")
const EngineeringSnapshot = preload("res://scripts/engineering/engineering_snapshot.gd")
const SensorSnapshot = preload("res://scripts/engineering/sensor_snapshot.gd")
const AutomationSnapshot = preload("res://scripts/engineering/automation_snapshot.gd")
const LearningSnapshot = preload("res://scripts/progression/learning_snapshot.gd")
const MAX_MINUTES: int = 525600000
const MAX_CASH: int = 1000000000000


static func capture(view: Control, pause_override: Variant = null) -> Dictionary:
	var farm: Farm = view.farm
	var runtime: Dictionary = view.simulation.export_runtime()
	if pause_override is bool:
		runtime.clock.paused = pause_override
	return {
		"farm": {"width": Farm.WIDTH, "height": Farm.HEIGHT, "tiles": Array(farm.tiles), "plots": farm.plots.duplicate(true),
			"seeds": farm.seed_stock.duplicate(true), "produce": farm.produce_stock.duplicate(true), "parts": farm.parts_stock.duplicate(true),
			"cash": farm.cash, "water": farm.watering_charges, "ledger": farm.ledger.duplicate(true), "next_transaction_id": farm.next_transaction_id},
		"runtime": runtime, "engineering": farm.engineering.duplicate(true), "sensor": farm.sensor.duplicate(true), "automation": farm.automation.duplicate(true), "learning": farm.learning.duplicate(true),
		"player": {"position": [view.player.position.x, view.player.position.y], "facing": [view.player.facing.x, view.player.facing.y], "walk_distance": view.player.walk_distance},
		"view": {"selected_cell": [view.selected_cell.x, view.selected_cell.y], "show_grid": view.show_grid,
			"tool": view.tools.active_tool, "seed": view.tools.selected_seed},
	}


static func number(value: Variant, low: float, high: float) -> bool:
	return (value is float or value is int) and is_finite(float(value)) and float(value) >= low and float(value) <= high


static func whole(value: Variant, low: int, high: int) -> bool:
	return number(value, float(low), float(high)) and float(value) == float(int(value))


static func _pair(value: Variant) -> bool:
	return value is Array and value.size() == 2 and number(value[0], -MAX_MINUTES, MAX_MINUTES) and number(value[1], -MAX_MINUTES, MAX_MINUTES)


static func _inventory(value: Variant) -> bool:
	if not value is Dictionary or value.size() != Farm.SEED_ORDER.size():
		return false
	for id in Farm.SEED_ORDER:
		if not whole(value.get(id), 0, Economy.MAX_STOCK):
			return false
	return true


static func _bad(message: String) -> Dictionary:
	return {"ok": false, "code": "invalid_state", "message": message}


static func validate(payload: Variant) -> Dictionary:
	if not payload is Dictionary:
		return _bad("存档主体不是有效对象。")
	for key in ["farm", "runtime", "player", "view"]:
		if not payload.get(key) is Dictionary:
			return _bad("存档缺少 %s 状态。" % key)
	var data: Dictionary = payload.farm
	var runtime: Dictionary = payload.runtime
	if not runtime.get("clock") is Dictionary or not runtime.get("weather") is Dictionary:
		return _bad("时钟或天气状态不完整。")
	var clock: Dictionary = runtime.clock
	if not whole(clock.get("total_minutes"), 480, MAX_MINUTES) or not whole(clock.get("tick_count"), 0, MAX_MINUTES):
		return _bad("游戏时间或步数无效。")
	if int(clock.total_minutes) != 480 + int(clock.tick_count) * 5 or not number(clock.get("accumulator"), 0, 86400):
		return _bad("游戏时间与模拟步数不一致。")
	for key in ["seed", "rng_state"]:
		var value: Variant = runtime.weather.get(key)
		if not value is String or value.length() > 20 or not value.is_valid_int() or str(int(value)) != value:
			return _bad("天气随机状态无效。")
	var farm := Farm.new()
	var simulation := Simulation.new(farm)
	if not simulation.restore_runtime(runtime):
		return _bad("时钟与天气区段不一致，或控制参数无效。")
	if data.get("width") != Farm.WIDTH or data.get("height") != Farm.HEIGHT or not data.get("tiles") is Array or data.tiles.size() != farm.tiles.size():
		return _bad("地图尺寸不匹配。")
	for index in range(farm.tiles.size()):
		if not whole(data.tiles[index], 0, Farm.Terrain.FENCE) or int(data.tiles[index]) != farm.tiles[index]:
			return _bad("地图地形与当前版本不匹配。")
	if not data.get("plots") is Array or data.plots.size() != farm.plots.size():
		return _bad("地块数量无效。")
	var standing: Dictionary = {}
	for id in Farm.SEED_ORDER:
		standing[id] = 0
	for index in range(farm.plots.size()):
		var plot: Variant = data.plots[index]
		if not plot is Dictionary or not plot.get("tilled") is bool or not number(plot.get("moisture"), 0, Farm.MAX_MOISTURE) or not plot.get("crop") is Dictionary:
			return _bad("地块 %d 的耕作或水分状态无效。" % (index + 1))
		var cell := Vector2i(index % Farm.WIDTH, index / Farm.WIDTH)
		if not farm.is_arable(cell) and (plot.tilled or not plot.crop.is_empty()):
			return _bad("不可耕地上存在耕作或作物状态。")
		var normalized_crop: Dictionary = {}
		if not plot.crop.is_empty():
			var crop: Dictionary = plot.crop
			if not plot.tilled or not crop.get("id") is String or not Farm.SEED_NAMES.has(crop.id):
				return _bad("作物类型或种植地块无效。")
			if not number(crop.get("growth"), 0, 1) or not number(crop.get("age_minutes"), 0, int(clock.total_minutes) - 480):
				return _bad("作物生长进度或历时无效。")
			var definition := Farm.CropCatalog.definition(crop.id)
			if float(crop.growth) > float(crop.age_minutes) / float(definition.growth_minutes) + 0.0000001:
				return _bad("作物进度超过其种植历时。")
			normalized_crop = {"id": crop.id, "growth": float(crop.growth), "age_minutes": float(crop.age_minutes)}
			standing[crop.id] += 1
		farm.plots[index] = {"tilled": plot.tilled, "moisture": float(plot.moisture), "crop": normalized_crop}
	if not _inventory(data.get("seeds")) or not _inventory(data.get("produce")) or not data.get("parts") is Dictionary:
		return _bad("库存无效，或包含当前版本不支持的零件。")
	if not whole(data.get("cash"), 0, MAX_CASH) or not whole(data.get("water"), 0, Farm.CAN_CAPACITY):
		return _bad("资金或水壶余量无效。")
	var ledger_result := _ledger(data.get("ledger"), data.get("next_transaction_id"), int(data.cash), int(clock.total_minutes))
	if not ledger_result.ok:
		return ledger_result
	var sensor_result := SensorSnapshot.validate(payload.get("sensor"), farm, int(clock.total_minutes))
	if not sensor_result.ok: return sensor_result
	farm.sensor = sensor_result.state
	var automatic: Variant = payload.get("automation")
	if not automatic is Dictionary or not automatic.get("installed") is bool: return _bad("缺少控制器状态。")
	var engineering_result := EngineeringSnapshot.validate(payload.get("engineering"), data.parts, ledger_result.acquired, ledger_result.entries, farm.sensor.installed, automatic.installed)
	if not engineering_result.ok: return engineering_result
	farm.engineering = engineering_result.state
	var automatic_result := AutomationSnapshot.validate(automatic, farm, int(clock.total_minutes))
	if not automatic_result.ok: return automatic_result
	farm.automation = automatic_result.state
	var learning_result := LearningSnapshot.validate(payload.get("learning"), farm, int(clock.total_minutes))
	if not learning_result.ok: return learning_result
	farm.learning = learning_result.state
	for id in data.parts: farm.parts_stock[id] = int(data.parts[id])
	for id in Farm.SEED_ORDER:
		var yield_count := int(Farm.CropCatalog.definition(id).harvest_count)
		var produced := int(data.produce[id]) + int(ledger_result.sold[id])
		var used_seeds := int(Farm.EconomyCatalog.config().starting_seeds[id]) + int(ledger_result.bought[id]) - int(data.seeds[id])
		if produced % yield_count != 0 or used_seeds != int(standing[id]) + produced / yield_count:
			return _bad("%s的种子、在田作物、库存与销售记录不一致。" % Farm.SEED_NAMES[id])
		farm.seed_stock[id] = int(data.seeds[id])
		farm.produce_stock[id] = int(data.produce[id])
	farm.cash = int(data.cash)
	farm.watering_charges = int(data.water)
	farm.ledger.assign(ledger_result.entries)
	farm.next_transaction_id = int(data.next_transaction_id)
	var actor: Dictionary = payload.player
	if not _pair(actor.get("position")) or not _pair(actor.get("facing")) or not number(actor.get("walk_distance"), 0, MAX_CASH):
		return _bad("角色坐标或朝向无效。")
	var position := Vector2(actor.position[0], actor.position[1])
	var facing := Vector2(actor.facing[0], actor.facing[1])
	if not Player.new().can_stand_at(position, farm) or facing not in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		return _bad("角色位于障碍中、地图外或朝向无效。")
	var view: Dictionary = payload.view
	if not _pair(view.get("selected_cell")) or not whole(view.selected_cell[0], 0, Farm.WIDTH - 1) or not whole(view.selected_cell[1], 0, Farm.HEIGHT - 1):
		return _bad("选中地块无效。")
	if not view.get("show_grid") is bool or not whole(view.get("tool"), Tools.Tool.INSPECT, Tools.Tool.HARVEST) or not view.get("seed") is String or not Farm.SEED_NAMES.has(view.seed):
		return _bad("工具、种子选择或网格设置无效。")
	return {"ok": true, "farm": farm, "runtime": simulation.export_runtime(), "player": {"position": position, "facing": facing, "walk_distance": float(actor.walk_distance)},
		"view": {"selected_cell": Vector2i(view.selected_cell[0], view.selected_cell[1]), "tool": int(view.tool), "seed": view.seed, "show_grid": view.show_grid}}


static func _ledger(value: Variant, next_id: Variant, cash: int, now: int) -> Dictionary:
	if not value is Array or value.is_empty() or value.size() > 50000 or not whole(next_id, 2, 50001) or int(next_id) != value.size() + 1:
		return _bad("账本长度或下一个交易编号无效。")
	var config := Farm.EconomyCatalog.config()
	var balance: int = 0
	var last_minute: int = 480
	var entries: Array[Dictionary] = []
	var bought: Dictionary = {}
	var sold: Dictionary = {}
	var acquired: Dictionary = {}
	for id in Farm.SEED_ORDER:
		bought[id] = 0
		sold[id] = 0
	for index in range(value.size()):
		var entry: Variant = value[index]
		if not entry is Dictionary or not whole(entry.get("id"), 1, 50000) or int(entry.id) != index + 1 or not whole(entry.get("minute"), last_minute, now):
			return _bad("账本编号或时间顺序无效。")
		if not whole(entry.get("amount"), -MAX_CASH, MAX_CASH) or not whole(entry.get("balance"), 0, MAX_CASH) or not entry.get("description") is String or entry.description.length() > 256 or not entry.get("items") is Array:
			return _bad("交易金额、说明或明细无效。")
		var category: Variant = entry.get("category")
		var amount := int(entry.amount)
		if index == 0:
			if category != "opening" or amount != int(config.starting_cash) or int(entry.minute) != 480 or not entry.items.is_empty():
				return _bad("开场资金记录不匹配。")
		elif category not in ["seed_purchase", "produce_sale", "water", "energy", "equipment", "maintenance"]:
			return _bad("交易类别无效。")
		var items: Array = []
		if category in ["seed_purchase", "produce_sale", "equipment"]:
			if entry.items.is_empty() or entry.items.size() > (9 if category == "equipment" else Farm.SEED_ORDER.size()) or (category == "seed_purchase" and entry.items.size() != 1):
				return _bad("交易商品明细无效。")
			var total: int = 0
			var seen: Dictionary = {}
			for item in entry.items:
				if not item is Dictionary or not item.get("id") is String or seen.has(item.id):
					return _bad("账本商品类型重复或无效。")
				var module := ModuleCatalog.definition(item.id) if category == "equipment" else {}
				if category == "equipment":
					if module.is_empty() or not module.available or item.get("name") != module.name: return _bad("账本模块类型无效。")
				elif not Farm.SEED_NAMES.has(item.id) or item.get("name") != Farm.SEED_NAMES[item.id]: return _bad("账本农产品无效。")
				if not whole(item.get("quantity"), 1, Economy.MAX_STOCK) or not whole(item.get("unit_price"), 1, 1000000):
					return _bad("账本商品数量或单价无效。")
				var expected_price: int = int(module.price) if category == "equipment" else int(config.crops[item.id].seed_price if category == "seed_purchase" else config.crops[item.id].produce_price)
				if int(item.unit_price) != expected_price:
					return _bad("账本单价与当前规则不匹配。")
				seen[item.id] = true
				total += int(item.quantity) * expected_price
				if category == "equipment": acquired[item.id] = int(acquired.get(item.id, 0)) + int(item.quantity)
				elif category == "seed_purchase": bought[item.id] += int(item.quantity)
				else: sold[item.id] += int(item.quantity)
				items.append({"id": item.id, "name": item.name, "quantity": int(item.quantity), "unit_price": expected_price})
			if amount != (total if category == "produce_sale" else -total):
				return _bad("商品明细与结算金额不一致。")
		elif index > 0 and (amount > 0 or not entry.items.is_empty()):
			return _bad("费用记录方向或明细无效。")
		balance += amount
		if balance != int(entry.balance) or balance < 0 or balance > MAX_CASH:
			return _bad("逐笔结余无法核对。")
		last_minute = int(entry.minute)
		entries.append({"id": index + 1, "minute": last_minute, "category": category, "description": entry.description, "amount": amount, "balance": balance, "items": items})
	if balance != cash:
		return _bad("当前资金与账本余额不一致。")
	return {"ok": true, "entries": entries, "bought": bought, "sold": sold, "acquired": acquired}


static func apply(view: Control, candidate: Dictionary) -> void:
	var target: Farm = view.farm
	var source: Farm = candidate.farm
	target.tiles = source.tiles.duplicate()
	target.plots.assign(source.plots.duplicate(true))
	target.seed_stock = source.seed_stock.duplicate(true)
	target.produce_stock = source.produce_stock.duplicate(true)
	target.parts_stock = source.parts_stock.duplicate(true)
	target.engineering = source.engineering.duplicate(true)
	target.sensor = source.sensor.duplicate(true)
	target.automation = source.automation.duplicate(true)
	target.learning = source.learning.duplicate(true)
	target.cash = source.cash
	target.watering_charges = source.watering_charges
	target.ledger.assign(source.ledger.duplicate(true))
	target.next_transaction_id = source.next_transaction_id
	target.trade_in_progress = false
	view.player.position = candidate.player.position
	view.player.facing = candidate.player.facing
	view.player.walk_distance = candidate.player.walk_distance
	view.player.moving = false
	view.player.blocked = false
	view.selected_cell = candidate.view.selected_cell
	view.show_grid = candidate.view.show_grid
	view.tools.active_tool = candidate.view.tool
	view.tools.selected_seed = candidate.view.seed
	view.reset_transient_state()
	view.simulation.restore_runtime(candidate.runtime)
	target.supplies_changed.emit()
	target.economy_changed.emit()
	target.engineering_changed.emit()
	target.sensor_changed.emit()
	target.automation_changed.emit()
	target.learning_changed.emit()
	view.tools.selection_changed.emit()
	view.player_moved.emit(view.player.cell())
	view.tile_selected.emit(view.selected_cell)
	view.queue_redraw()
