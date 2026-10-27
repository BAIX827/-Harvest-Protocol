extends RefCounted
## Validate teaching evidence rather than trusting a "completed" flag.

const Farm = preload("res://scripts/simulation/farm_state.gd")
const SensorSnapshot = preload("res://scripts/engineering/sensor_snapshot.gd")
const Controller = preload("res://scripts/progression/learning_controller.gd")


static func number(value: Variant, low: float, high: float) -> bool:
	return SensorSnapshot._number(value, low, high)


static func whole(value: Variant, low: int, high: int) -> bool:
	return SensorSnapshot._whole(value, low, high)


static func _points(value: Variant, cup: Farm, now: int, revision: int) -> Array:
	var points: Array = []
	if not value is Array or value.size() > 2: return []
	for row in value:
		var normalized := SensorSnapshot._row(row, cup, now, revision)
		if normalized.is_empty() or not normalized.valid or not normalized.connected or normalized.fault != "none" or normalized.cell != [10, 8]: return []
		if normalized.slope != 1.0 or normalized.offset != 0.0: return []
		points.append(normalized)
	if points.size() == 2:
		if not Controller.solve(points).ok or points[1].serial <= points[0].serial or points[1].revision <= points[0].revision: return []
	return points


static func validate(value: Variant, farm: Farm, now: int) -> Dictionary:
	var bad := {"ok": false, "code": "invalid_learning", "message": "实验、校准或故障教学证据无效。"}
	if not value is Dictionary: return bad
	for field in ["lab", "experiment", "fault"]:
		if not value.get(field) is Dictionary: return bad
	var state: Dictionary = value.duplicate(true)
	var lab: Dictionary = state.lab
	if not number(lab.get("truth"), 0, 60) or not lab.get("sensor") is Dictionary: return bad
	var cup := Farm.new()
	var validated := SensorSnapshot.validate(lab.sensor, cup, now)
	if not validated.ok: return bad
	lab.sensor = validated.state
	if lab.sensor.cell != [10, 8] or not lab.sensor.connected or lab.sensor.fault != "none": return bad
	if lab.sensor.installed != (lab.sensor.sample_count > 0): return bad
	if lab.sensor.installed and lab.sensor.latest.truth != lab.truth: return bad
	if not lab.get("points") is Array or lab.points.size() > 2: return bad
	var points := _points(lab.points, cup, now, int(lab.sensor.revision))
	if points.size() != lab.points.size(): return bad
	for point in points:
		if point.soil != lab.sensor.soil or point.mount != lab.sensor.mount or point.serial > lab.sensor.sample_count: return bad
	lab.points = points
	if not lab.get("verification") is Dictionary: return bad
	if not lab.verification.is_empty():
		var row := SensorSnapshot._row(lab.verification, cup, now, int(lab.sensor.revision))
		if row.is_empty() or points.size() != 2 or row.serial > lab.sensor.sample_count: return bad
		var solution := Controller.solve(points)
		if row.soil != points[0].soil or row.mount != points[0].mount or absf(float(row.truth) - (float(points[0].truth) + float(points[1].truth)) / 2) > 0.000001: return bad
		if absf(float(row.slope) - float(solution.slope)) > 0.000000001 or absf(float(row.offset) - float(solution.offset)) > 0.000000001: return bad
		lab.verification = row
	var experiment: Dictionary = state.experiment
	if not experiment.is_empty():
		if not whole(experiment.get("applied_minute"), 480, now) or not whole(experiment.get("farm_revision"), 1, int(farm.sensor.revision)): return bad
		var proof_points := _points(experiment.get("points"), cup, now, int(lab.sensor.revision))
		var proof_row := SensorSnapshot._row(experiment.get("verification"), cup, now, int(lab.sensor.revision))
		if proof_points.size() != 2 or not Controller.verified(proof_points, proof_row) or proof_row.minute > experiment.applied_minute or proof_row.serial > lab.sensor.sample_count: return bad
		experiment.points = proof_points
		experiment.verification = proof_row
		experiment.applied_minute = int(experiment.applied_minute)
		experiment.farm_revision = int(experiment.farm_revision)
	var task: Dictionary = state.fault
	if task.get("stage") not in ["idle", "observe", "diagnose", "repair", "complete"]: return bad
	for field in ["baseline", "observed", "resume", "repair"]:
		if not task.get(field) is Dictionary: return bad
	if not task.get("diagnosis") is String: return bad
	if task.stage == "idle":
		if not task.baseline.is_empty() or not task.observed.is_empty() or not task.resume.is_empty() or not task.repair.is_empty() or not task.diagnosis.is_empty(): return bad
		return {"ok": true, "state": state}
	if experiment.is_empty(): return bad
	var base: Dictionary = task.baseline
	if not whole(base.get("minute"), 480, now) or not whole(base.get("serial"), 1, int(farm.sensor.sample_count)): return bad
	if not number(base.get("delivered_l"), 0, float(farm.engineering.delivered_l)) or not number(base.get("used_wh"), 0, float(farm.engineering.used_wh)): return bad
	var base_row := SensorSnapshot._row(base.get("sample"), farm, now, int(farm.sensor.revision))
	if base_row.is_empty() or not base_row.valid or base_row.serial != int(base.serial) or base_row.minute > base.minute: return bad
	for field in ["cell", "soil", "mount", "slope", "offset"]:
		if base.get(field) != base.sample.get(field): return bad
	if base.get("reading") != base_row.reading or base.get("output") != true or base.get("control_code") not in ["below", "hold_on"]: return bad
	base.cell = base_row.cell.duplicate()
	base.sample = base_row
	base.minute = int(base.minute)
	base.serial = int(base.serial)
	if task.stage == "observe":
		if not task.observed.is_empty() or not task.resume.is_empty() or not task.repair.is_empty() or task.diagnosis != "": return bad
		return {"ok": true, "state": state}
	var observed: Dictionary = task.observed
	if not whole(observed.get("minute"), int(base.minute), now) or not whole(observed.get("serial"), int(base.serial) + 1, int(farm.sensor.sample_count)): return bad
	if observed.get("sensor_code") != "disconnected" or observed.get("control_code") != "sensor_invalid" or observed.get("output") != false or observed.get("delivered_l") != base.delivered_l: return bad
	var observed_row := SensorSnapshot._row(observed.get("sample"), farm, now, int(farm.sensor.revision))
	if observed_row.is_empty() or observed_row.code != "disconnected" or observed_row.serial != int(observed.serial) or observed_row.minute > observed.minute: return bad
	observed.sample = observed_row
	observed.minute = int(observed.minute)
	observed.serial = int(observed.serial)
	if task.stage == "diagnose":
		if task.diagnosis != "" or not task.resume.is_empty() or not task.repair.is_empty(): return bad
		return {"ok": true, "state": state}
	if task.diagnosis != "signal": return bad
	var resume: Dictionary = task.resume
	if not resume.is_empty():
		if not whole(resume.get("minute"), int(observed.minute), now) or not whole(resume.get("serial"), int(observed.serial) + 1, int(farm.sensor.sample_count)): return bad
		if not number(resume.get("delivered_l"), float(base.delivered_l), float(farm.engineering.delivered_l)) or not number(resume.get("used_wh"), float(base.used_wh), float(farm.engineering.used_wh)): return bad
		var resume_row := SensorSnapshot._row(resume.get("sample"), farm, now, int(farm.sensor.revision))
		if resume_row.is_empty() or not resume_row.valid or resume_row.serial != int(resume.serial) or resume_row.minute > resume.minute: return bad
		for field in ["cell", "soil", "mount", "slope", "offset"]:
			if resume_row[field] != base_row[field]: return bad
		resume.sample = resume_row
		resume.minute = int(resume.minute)
		resume.serial = int(resume.serial)
	if task.stage == "repair":
		if not task.repair.is_empty() or (not resume.is_empty() and farm.automation.mode != "auto"): return bad
		if not resume.is_empty():
			if not SensorSnapshot.Model.new(farm).current(now).valid: return bad
			for field in ["cell", "soil", "mount", "slope", "offset"]:
				if farm.sensor[field] != base[field]: return bad
		return {"ok": true, "state": state}
	if resume.is_empty(): return bad
	var repair: Dictionary = task.repair
	if not whole(repair.get("minute"), int(resume.minute), now) or not whole(repair.get("serial"), int(resume.serial) + 1, int(farm.sensor.sample_count)): return bad
	if not number(repair.get("delivered_l"), float(resume.delivered_l) + 0.000001, float(farm.engineering.delivered_l)) or not number(repair.get("used_wh"), float(resume.used_wh) + 0.000001, float(farm.engineering.used_wh)): return bad
	var repaired_row := SensorSnapshot._row(repair.get("sample"), farm, now, int(farm.sensor.revision))
	if repaired_row.is_empty() or not repaired_row.valid or repaired_row.serial != int(repair.serial) or repaired_row.minute > repair.minute or repaired_row.reading != repair.get("reading"): return bad
	for field in ["cell", "soil", "mount", "slope", "offset"]:
		if repaired_row[field] != base_row[field]: return bad
	if repair.get("control_code") not in ["below", "hold_on", "stop"]: return bad
	repair.sample = repaired_row
	repair.minute = int(repair.minute)
	repair.serial = int(repair.serial)
	return {"ok": true, "state": state}
