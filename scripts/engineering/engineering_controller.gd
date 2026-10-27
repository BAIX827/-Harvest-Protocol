extends RefCounted
## Purchases, swaps and replenishment commit before notifying any observer.

signal action_completed(result: Dictionary)

const Economy = preload("res://scripts/simulation/economy_model.gd")
const Network = preload("res://scripts/engineering/irrigation_network.gd")
const Catalog = preload("res://scripts/engineering/module_catalog.gd")
var economy: Economy
var network: Network


func _init(shared_economy: Economy, shared_network: Network) -> void:
	economy = shared_economy
	network = shared_network


func buy(id: String, quantity: int = 1) -> Dictionary:
	if economy.farm.trade_in_progress: return _reject("上一项操作正在完成。")
	var result := economy.buy_modules({id: quantity})
	economy.farm.trade_in_progress = true
	action_completed.emit(result)
	economy.farm.trade_in_progress = false
	return result


func _reject(message: String) -> Dictionary:
	return {"ok": false, "changed": false, "message": message}


func _done(message: String) -> Dictionary:
	var result := {"ok": true, "changed": true, "message": message}
	economy.farm.engineering_changed.emit()
	economy.farm.supplies_changed.emit()
	action_completed.emit(result)
	economy.farm.trade_in_progress = false
	return result


func install(id: String) -> Dictionary:
	var farm := economy.farm
	if farm.trade_in_progress: return _reject("上一项操作正在完成。")
	var item := Catalog.definition(id)
	if item.is_empty() or item.kind not in ["tank", "pump", "power"]: return _reject("请选择可安装的水箱、水泵或电池。")
	var kind: String = item.kind
	var previous: String = farm.engineering[kind]
	if id == previous: return _reject("该模块已经安装，不会重复消耗库存。")
	if int(farm.parts_stock.get(id, 0)) < 1: return _reject("库存不足，请先采购。")
	if not previous.is_empty() and int(farm.parts_stock.get(previous, 0)) >= 1000: return _reject("旧模块库存已满，暂时无法拆回。")
	farm.trade_in_progress = true
	farm.parts_stock[id] -= 1
	if not previous.is_empty(): farm.parts_stock[previous] = int(farm.parts_stock.get(previous, 0)) + 1
	farm.engineering[kind] = id
	if kind in ["tank", "power"]:
		var resource: String = "water_l" if kind == "tank" else "energy_wh"
		var discarded: String = "discarded_water_l" if kind == "tank" else "discarded_energy_wh"
		var retained := minf(float(farm.engineering[resource]), float(item.capacity))
		farm.engineering[discarded] += float(farm.engineering[resource]) - retained
		farm.engineering[resource] = retained
	return _done("已安装%s；旧模块退回库存。容量缩小时超出部分不保留。" % item.name)


func pipe(point: Vector2i) -> Dictionary:
	var farm := economy.farm
	if farm.trade_in_progress: return _reject("上一项操作正在完成。")
	if not Network.can_pipe(point): return _reject("这里是固定设备台位或超出试验区。")
	var id := Network.key(point)
	var removing: bool = id in farm.engineering.pipes
	if removing and int(farm.parts_stock.get("pipe", 0)) >= 1000: return _reject("管段库存已满，暂时无法拆回。")
	if not removing and int(farm.parts_stock.get("pipe", 0)) < 1: return _reject("管段库存不足，请先采购。")
	farm.trade_in_progress = true
	if removing:
		farm.engineering.pipes.erase(id)
		farm.parts_stock.pipe = int(farm.parts_stock.get("pipe", 0)) + 1
	else:
		farm.engineering.pipes.append(id)
		farm.engineering.pipes.sort()
		farm.parts_stock.pipe -= 1
	return _done("已拆回管段，未退款，可再次铺设。" if removing else "已铺设管段，四邻接连接。")


func set_enabled(enabled: bool) -> Dictionary:
	if economy.farm.trade_in_progress: return _reject("上一项操作正在完成。")
	if economy.farm.engineering.enabled == enabled: return _reject("开关状态未改变。")
	economy.farm.trade_in_progress = true
	economy.farm.engineering.enabled = enabled
	return _done("手动开关已%s。" % ("打开" if enabled else "关闭"))


func set_power(connected: bool) -> Dictionary:
	if economy.farm.trade_in_progress: return _reject("上一项操作正在完成。")
	if economy.farm.engineering.power_connected == connected: return _reject("供电连接未改变。")
	economy.farm.trade_in_progress = true
	economy.farm.engineering.power_connected = connected
	return _done("电源已%s。" % ("接通" if connected else "断开"))


func refill_fee(kind: String) -> int:
	if kind not in ["tank", "power"]: return 0
	var resource: String = "water_l" if kind == "tank" else "energy_wh"
	var rate: float = Catalog.config().water_liters_per_coin if kind == "tank" else Catalog.config().energy_wh_per_coin
	return ceili(maxf(0.0, network.capacity(kind) - float(economy.farm.engineering[resource])) / rate)


func refill(kind: String) -> Dictionary:
	var farm := economy.farm
	if farm.trade_in_progress: return _reject("上一项操作正在完成。")
	if kind not in ["tank", "power"] or network.capacity(kind) <= 0: return _reject("请先安装对应水箱或电池。")
	var fee := refill_fee(kind)
	if fee <= 0: return _reject("当前已经装满，无需付费。")
	if farm.cash < fee: return _reject("余额不足，需要 %d 币。" % fee)
	var resource: String = "water_l" if kind == "tank" else "energy_wh"
	var loaded: String = "water_loaded_l" if kind == "tank" else "energy_loaded_wh"
	var quantity := network.capacity(kind) - float(farm.engineering[resource])
	farm.trade_in_progress = true
	farm.cash -= fee
	farm.engineering[loaded] += quantity
	farm.engineering[resource] = network.capacity(kind)
	var result := economy._commit("water" if kind == "tank" else "energy", "水箱补水 %.2f L" % quantity if kind == "tank" else "电池充电 %.2f Wh" % quantity, -fee, [])
	# Keep the guard through engineering observers, as with ordinary trades.
	farm.trade_in_progress = true
	_done(result.message)
	return result
