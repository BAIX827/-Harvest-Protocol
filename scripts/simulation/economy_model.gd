extends RefCounted
## Integer cash and inventory commit before observers receive either change.

signal transaction_completed(result: Dictionary)

const FarmState = preload("res://scripts/simulation/farm_state.gd")
const Clock = preload("res://scripts/simulation/simulation_clock.gd")
const Catalog = preload("res://scripts/simulation/economy_catalog.gd")
const MAX_STOCK: int = 1000000
const COST_CATEGORIES := ["water", "energy", "equipment", "maintenance"]

var farm: FarmState
var clock: Clock
var settings: Dictionary


func _init(state: FarmState, shared_clock: Clock = null) -> void:
	farm = state
	clock = shared_clock
	settings = Catalog.config()


func buy_seeds(id: String, quantity: Variant = 1) -> Dictionary:
	if farm.trade_in_progress:
		return _fail("busy", "上一笔交易正在完成，请稍后再试。")
	if not settings.crops.has(id):
		return _fail("unknown_item", "没有这种种子。")
	if not quantity is int or quantity < 1 or quantity > int(settings.max_buy_quantity):
		return _fail("invalid_quantity", "购买数量必须是 1～%d 的整数。" % int(settings.max_buy_quantity))
	var cost: int = int(settings.crops[id].seed_price) * int(quantity)
	if farm.cash < cost:
		return _fail("insufficient_cash", "余额不足：需要 %d 币，目前只有 %d 币。" % [cost, farm.cash])
	if int(farm.seed_stock.get(id, 0)) + int(quantity) > MAX_STOCK:
		return _fail("stock_limit", "种子库存已达到上限。")
	farm.trade_in_progress = true
	farm.cash -= cost
	farm.seed_stock[id] = int(farm.seed_stock.get(id, 0)) + int(quantity)
	var items: Array = [{"id": id, "name": FarmState.SEED_NAMES[id], "quantity": int(quantity), "unit_price": int(settings.crops[id].seed_price)}]
	return _commit("seed_purchase", "购买%s种子 ×%d" % [FarmState.SEED_NAMES[id], quantity], -cost, items)


func sell_produce(id: String, quantity: Variant = 1) -> Dictionary:
	if farm.trade_in_progress:
		return _fail("busy", "上一笔交易正在完成，请稍后再试。")
	if not settings.crops.has(id):
		return _fail("unknown_item", "没有这种农产品。")
	if not quantity is int or quantity < 1 or quantity > MAX_STOCK:
		return _fail("invalid_quantity", "出售数量必须是有效的正整数。")
	return _sell({id: int(quantity)})


func sell_all() -> Dictionary:
	if farm.trade_in_progress:
		return _fail("busy", "上一笔交易正在完成，请稍后再试。")
	var amounts: Dictionary = {}
	for id in FarmState.SEED_ORDER:
		if int(farm.produce_stock.get(id, 0)) > 0:
			amounts[id] = int(farm.produce_stock[id])
	return _sell(amounts)


func _sell(amounts: Dictionary) -> Dictionary:
	if amounts.is_empty():
		return _fail("empty_stock", "目前没有可出售的收成。")
	var income: int = 0
	var items: Array = []
	for id in amounts:
		var count: int = amounts[id]
		if count < 1 or count > MAX_STOCK or count > int(farm.produce_stock.get(id, 0)):
			return _fail("insufficient_stock", "%s库存不足，不能重复出售。" % FarmState.SEED_NAMES[id])
		var price := int(settings.crops[id].produce_price)
		income += count * price
		items.append({"id": id, "name": FarmState.SEED_NAMES[id], "quantity": count, "unit_price": price})
	farm.trade_in_progress = true
	for id in amounts:
		farm.produce_stock[id] -= int(amounts[id])
	farm.cash += income
	return _commit("produce_sale", "出售农产品", income, items)


func charge_cost(category: String, amount: Variant, description: String) -> Dictionary:
	if farm.trade_in_progress:
		return _fail("busy", "上一笔交易正在完成，请稍后再试。")
	if category not in COST_CATEGORIES or not amount is int or amount < 0 or amount > MAX_STOCK:
		return _fail("invalid_cost", "费用数据无效。")
	if farm.cash < amount:
		return _fail("insufficient_cash", "余额不足：%s需要 %d 币，目前只有 %d 币。" % [description, amount, farm.cash])
	if amount == 0:
		return {"ok": true, "code": "free", "message": description + "无需费用。", "amount": 0}
	farm.trade_in_progress = true
	farm.cash -= int(amount)
	return _commit(category, description, -int(amount), [])


func refill_can() -> Dictionary:
	if farm.trade_in_progress:
		return _fail("busy", "上一笔交易正在完成，请稍后再试。")
	if farm.watering_charges >= FarmState.CAN_CAPACITY:
		return _fail("can_full", "水壶已经装满了。")
	var fee := int(settings.water_refill_cost)
	if farm.cash < fee:
		return _fail("insufficient_cash", "余额不足：补水需要 %d 币，目前只有 %d 币。" % [fee, farm.cash])
	farm.trade_in_progress = true
	farm.cash -= fee
	farm.watering_charges = FarmState.CAN_CAPACITY
	return _commit("water", "水壶补水", -fee, [])


func sale_value() -> int:
	var value: int = 0
	for id in FarmState.SEED_ORDER:
		value += int(farm.produce_stock.get(id, 0)) * int(settings.crops[id].produce_price)
	return value


func totals() -> Dictionary:
	var result := {"sales": 0, "seed_purchase": 0, "water": 0, "energy": 0, "equipment": 0, "maintenance": 0, "expenses": 0, "net": 0}
	for entry in farm.ledger:
		if entry.category == "opening":
			continue
		if int(entry.amount) > 0:
			result.sales += int(entry.amount)
		else:
			result.expenses -= int(entry.amount)
			if result.has(entry.category):
				result[entry.category] -= int(entry.amount)
	result.net = int(result.sales) - int(result.expenses)
	return result


func _commit(category: String, description: String, amount: int, items: Array) -> Dictionary:
	var entry := {"id": farm.next_transaction_id, "minute": clock.total_minutes if clock != null else 480,
		"category": category, "description": description, "amount": amount, "balance": farm.cash, "items": items.duplicate(true)}
	farm.next_transaction_id += 1
	farm.ledger.append(entry)
	var result := {"ok": true, "code": category, "message": "%s：%s%d 币，余额 %d 币。" % [description, "+" if amount > 0 else "", amount, farm.cash],
		"amount": amount, "transaction_id": entry.id, "items": items.duplicate(true)}
	farm.supplies_changed.emit()
	farm.economy_changed.emit()
	transaction_completed.emit(result)
	farm.trade_in_progress = false
	return result


func _fail(code: String, message: String) -> Dictionary:
	var result := {"ok": false, "code": code, "message": message, "amount": 0}
	# A rejected reentrant call must not recursively notify the callback that caused it.
	if not farm.trade_in_progress:
		farm.trade_in_progress = true
		transaction_completed.emit(result)
		farm.trade_in_progress = false
	return result
