extends RefCounted
## Validate a complete action before changing authoritative farm data.

signal selection_changed
signal action_completed(result: Dictionary)

const FarmState = preload("res://scripts/simulation/farm_state.gd")
const CropModel = preload("res://scripts/simulation/crop_model.gd")
const Economy = preload("res://scripts/simulation/economy_model.gd")
const REACH: float = 1.6
const WATER_INCREMENT: float = 12.0

enum Tool { INSPECT, HOE, SOW, WATER, HARVEST }

const TOOL_NAMES := ["检查", "锄地", "播种", "浇水", "收获"]
const TOOL_IDS := ["inspect", "hoe", "sow", "water", "harvest"]
const HINTS := [
	"检查：点击任何地块查看状态。",
	"锄地：靠近草地或裸土后点击，已播种地块不能再翻。",
	"播种：选好种子后，点击附近已翻土的空地。",
	"浇水：点击附近已翻土地块；靠近池塘点击水面可以补水。",
	"收获：成熟时靠近地块点击，收成计入库存。",
]

var farm: FarmState
var active_tool: int = Tool.INSPECT
var selected_seed: String = "lettuce"
var economy: Economy


func _init(state: FarmState, shared_economy: Economy = null) -> void:
	farm = state
	economy = shared_economy if shared_economy != null else Economy.new(farm)


func select_tool(tool: int) -> void:
	if tool < Tool.INSPECT or tool > Tool.HARVEST:
		return
	active_tool = tool
	selection_changed.emit()


func select_seed(seed_id: String) -> void:
	if not FarmState.SEED_NAMES.has(seed_id):
		return
	selected_seed = seed_id
	active_tool = Tool.SOW
	selection_changed.emit()


func cycle_seed() -> void:
	var index := FarmState.SEED_ORDER.find(selected_seed)
	select_seed(FarmState.SEED_ORDER[(index + 1) % FarmState.SEED_ORDER.size()])


func can_reach(cell: Vector2i, actor: Vector2) -> bool:
	var target := Vector2(cell) + Vector2.ONE * 0.5
	if not farm.contains(cell) or actor.distance_to(target) > REACH:
		return false
	# Test intermediate cells, but allow the target itself to be water for refilling.
	var steps := maxi(1, ceili(actor.distance_to(target) / 0.1))
	for index in range(1, steps):
		var point := actor.lerp(target, float(index) / float(steps))
		var intermediate := Vector2i(floori(point.x), floori(point.y))
		if intermediate != cell and not farm.is_walkable(intermediate):
			return false
	return true


func use(cell: Vector2i, actor: Vector2) -> Dictionary:
	if not farm.contains(cell):
		return _result(false, false, cell, "outside", "请选择地图内的地块。")
	if active_tool == Tool.INSPECT:
		return _result(true, false, cell, "inspect", "已检查地块 (%02d, %02d)：%s。" % [cell.x + 1, cell.y + 1, farm.describe(cell).name])
	if actor.distance_to(Vector2(cell) + Vector2.ONE * 0.5) > REACH:
		return _result(false, false, cell, "too_far", "距离太远，请走近目标地块再使用工具。")
	if not can_reach(cell, actor):
		return _result(false, false, cell, "blocked", "目标前有障碍，请绕到可以接近的一侧再操作。")
	if active_tool == Tool.WATER and farm.terrain_at(cell) == FarmState.Terrain.WATER:
		if farm.watering_charges >= FarmState.CAN_CAPACITY:
			return _result(false, false, cell, "can_full", "水壶已经装满了。")
		var fee := int(economy.settings.water_refill_cost)
		var payment := economy.refill_can()
		if not payment.ok:
			return _result(false, false, cell, payment.code, payment.message)
		farm.journey.manual.refill += 1
		farm.journey_changed.emit()
		return _result(true, true, cell, "refill", "已补满水壶，可以浇水 %d 次，费用 %d 币。" % [FarmState.CAN_CAPACITY, fee])
	if not farm.is_arable(cell):
		return _result(false, false, cell, "not_arable", "%s不能耕作，请选择草地或裸土。" % farm.describe(cell).name)
	var plot := farm.plot_at(cell)
	var harvest_note: String = ""
	var water_before: float = plot.moisture
	match active_tool:
		Tool.HOE:
			if not plot.crop.is_empty():
				return _result(false, false, cell, "occupied", "这里已经播种，不能再次翻土。")
			if plot.tilled:
				return _result(false, false, cell, "already_tilled", "这块地已经翻过土了，可以播种或浇水。")
			plot.tilled = true
		Tool.SOW:
			if not plot.tilled:
				return _result(false, false, cell, "untilled", "先用锄头翻土，再播种。")
			if not plot.crop.is_empty():
				return _result(false, false, cell, "occupied", "这块地已经有作物，不能重复播种。")
			if int(farm.seed_stock.get(selected_seed, 0)) <= 0:
				return _result(false, false, cell, "no_seed", "%s种子用完了，请换一种种子。" % FarmState.SEED_NAMES[selected_seed])
			farm.seed_stock[selected_seed] -= 1
			plot.crop = CropModel.new_crop(selected_seed)
		Tool.WATER:
			if not plot.tilled:
				return _result(false, false, cell, "untilled", "先用锄头翻土，再浇水。")
			if float(plot.moisture) >= FarmState.MAX_MOISTURE:
				return _result(false, false, cell, "wet_enough", "这块地已达到原型水分上限，暂时不用再浇水。")
			if farm.watering_charges <= 0:
				return _result(false, false, cell, "can_empty", "水壶空了。走到池塘边，点击水面补水。")
			plot.moisture = minf(FarmState.MAX_MOISTURE, float(plot.moisture) + WATER_INCREMENT)
			farm.watering_charges -= 1
		Tool.HARVEST:
			if plot.crop.is_empty():
				return _result(false, false, cell, "no_crop", "这里没有可收获的作物。")
			if not CropModel.is_mature(plot.crop):
				return _result(false, false, cell, "not_mature", "作物尚未成熟，请检查水分并等待生长。")
			var crop_id: String = plot.crop.id
			var count := int(FarmState.CropCatalog.definition(crop_id).get("harvest_count", 1))
			farm.produce_stock[crop_id] = int(farm.produce_stock.get(crop_id, 0)) + count
			harvest_note = "已收获%s ×%d，放入农产品库存。" % [FarmState.SEED_NAMES[crop_id], count]
			plot.crop = {}
	farm.journey.manual[TOOL_IDS[active_tool]] += 1
	if active_tool == Tool.WATER:
		farm.journey.manual_water_l += (float(plot.moisture) - water_before) * float(Economy.ModuleCatalog.config().liters_per_moisture_point)
	farm.journey_changed.emit()
	farm.plot_changed.emit(cell)
	farm.supplies_changed.emit()
	var messages := {
		Tool.HOE: "翻土完成，可以选择种子播种。",
		Tool.SOW: "已播下%s，消耗 1 份种子。" % FarmState.SEED_NAMES[selected_seed],
		Tool.WATER: "浇水完成，土壤水分为 %.0f%%。" % float(plot.moisture),
		Tool.HARVEST: harvest_note,
	}
	return _result(true, true, cell, TOOL_IDS[active_tool], messages[active_tool])


func _result(ok: bool, changed: bool, cell: Vector2i, code: String, message: String) -> Dictionary:
	var result := {"ok": ok, "changed": changed, "cell": cell, "code": code, "message": message}
	action_completed.emit(result)
	return result
