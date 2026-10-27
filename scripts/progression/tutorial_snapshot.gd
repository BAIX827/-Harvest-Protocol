extends RefCounted

const Numbers = preload("res://scripts/engineering/sensor_snapshot.gd")
const Automation = preload("res://scripts/engineering/automation_controller.gd")


static func validate(value: Variant, farm: RefCounted, now: int) -> Dictionary:
	var bad := {"ok": false, "code": "invalid_journey", "message": "引导统计、计量起点或自主调整证据无效。"}
	if not value is Dictionary or not Numbers._whole(value.get("since"), 480, now) or int(value.since) % 5 != 0: return bad
	for field in ["manual", "modes", "improvement"]:
		if not value.get(field) is Dictionary: return bad
	var state: Dictionary = value.duplicate(true)
	state.since = int(state.since)
	for field in ["baseline_l", "baseline_wh", "manual_water_l"]:
		if not Numbers._number(state.get(field), 0, 1000000000000): return bad
	if state.manual.size() != 5 or state.modes.size() != 2: return bad
	for key in ["hoe", "sow", "water", "harvest", "refill"]:
		if not Numbers._whole(state.manual.get(key), 0, 1000000000): return bad
		state.manual[key] = int(state.manual[key])
	if state.manual_water_l > float(state.manual.water) * 24.0 + 0.000001 or (state.manual.water == 0 and state.manual_water_l != 0): return bad
	var tilled: int = 0
	var planted: int = 0
	var harvested: int = 0
	var refills: int = 0
	for plot in farm.plots:
		if plot.tilled: tilled += 1
		if not plot.crop.is_empty(): planted += 1
	for id in farm.SEED_ORDER: harvested += int(farm.produce_stock[id])
	for entry in farm.ledger:
		if entry.category == "produce_sale":
			for item in entry.items: harvested += int(item.quantity)
		if entry.category == "water" and entry.description == "水壶补水": refills += 1
	if state.manual.hoe > tilled or state.manual.harvest > harvested or state.manual.sow > planted + harvested or state.manual.refill > refills: return bad
	var liters: float = state.baseline_l
	var energy: float = state.baseline_wh
	var minutes: int = 0
	for mode in ["manual", "auto"]:
		if not state.modes.get(mode) is Dictionary: return bad
		var row: Dictionary = state.modes[mode]
		if not Numbers._number(row.get("liters"), 0, 1000000000000) or not Numbers._number(row.get("wh"), 0, 1000000000000) or not Numbers._whole(row.get("minutes"), 0, now - state.since) or int(row.minutes) % 5 != 0: return bad
		row.minutes = int(row.minutes)
		if row.liters > 0 and row.minutes == 0: return bad
		if float(row.wh) < float(row.liters) * 0.5 - 0.000001 or float(row.wh) > float(row.liters) * 0.625 + 0.000001: return bad
		liters += float(row.liters)
		energy += float(row.wh)
		minutes += row.minutes
	if absf(liters - float(farm.engineering.delivered_l)) > 0.000001 or absf(energy - float(farm.engineering.used_wh)) > 0.000001 or minutes != now - state.since: return bad
	var trial: Dictionary = state.improvement
	for key in ["baseline", "change", "proof"]:
		if not trial.get(key) is Dictionary: return bad
	if trial.baseline.is_empty():
		if not trial.change.is_empty() or not trial.proof.is_empty(): return bad
		return {"ok": true, "state": state}
	if farm.learning.fault.stage != "complete": return bad
	var previous: Dictionary = {}
	for key in ["baseline", "change", "proof"]:
		var row: Dictionary = trial[key]
		if row.is_empty():
			if key == "change" and not trial.proof.is_empty(): return bad
			continue
		if not Numbers._whole(row.get("minute"), maxi(state.since, int(farm.learning.fault.repair.minute)), now) or not Numbers._whole(row.get("serial"), 1, farm.sensor.sample_count): return bad
		if not Automation.valid_thresholds(row.get("start"), row.get("stop")) or not Numbers._number(row.get("delivered_l"), 0, farm.engineering.delivered_l) or not Numbers._number(row.get("used_wh"), 0, farm.engineering.used_wh): return bad
		row.minute = int(row.minute)
		row.serial = int(row.serial)
		if not previous.is_empty() and (row.minute < previous.minute or row.serial < previous.serial or row.delivered_l < previous.delivered_l or row.used_wh < previous.used_wh): return bad
		if key == "change" and row.start == trial.baseline.start and row.stop == trial.baseline.stop: return bad
		previous = row
	if not trial.proof.is_empty():
		var proof: Dictionary = trial.proof
		var changed: Dictionary = trial.change
		if proof.start != changed.start or proof.stop != changed.stop or proof.serial <= changed.serial or proof.delivered_l <= changed.delivered_l or proof.used_wh <= changed.used_wh or proof.get("code") not in ["below", "hold_on", "stop"]: return bad
		var sample := Numbers._row(proof.get("sample"), farm, now, farm.sensor.revision)
		if sample.is_empty() or not sample.valid or sample.serial != proof.serial or sample.minute != proof.minute: return bad
		proof.sample = sample
	elif not trial.change.is_empty():
		if farm.automation.mode != "auto" or farm.automation.start != trial.change.start or farm.automation.stop != trial.change.stop or not Numbers.Model.new(farm).current(now).valid: return bad
	return {"ok": true, "state": state}
