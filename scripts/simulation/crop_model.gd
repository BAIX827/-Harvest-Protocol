extends RefCounted
## Water-limited growth with recoverable stress. All units are prototype values.

const Catalog = preload("res://scripts/simulation/crop_catalog.gd")
const STAGE_NAMES := ["播种", "发芽", "生长", "接近成熟", "成熟"]


static func new_crop(id: String) -> Dictionary:
	return {"id": id, "growth": 0.0, "age_minutes": 0.0}


static func is_mature(crop: Dictionary) -> bool:
	var growth := float(crop.get("growth", 0.0))
	return not crop.is_empty() and is_finite(growth) and growth >= 1.0


static func stage(crop: Dictionary) -> int:
	var growth := float(crop.get("growth", 0.0))
	if growth >= 1.0: return 4
	if growth >= 0.7: return 3
	if growth >= 0.35: return 2
	if growth >= 0.12: return 1
	return 0


func water_factor(plot: Dictionary) -> float:
	if plot.crop.is_empty():
		return 0.0
	var definition := Catalog.definition(plot.crop.id)
	if definition.is_empty():
		return 0.0
	var water := float(plot.moisture)
	if water <= float(definition.dry_stop) or water >= float(definition.wet_stop):
		return 0.0
	if water < float(definition.optimal_min):
		return (water - float(definition.dry_stop)) / (float(definition.optimal_min) - float(definition.dry_stop))
	if water > float(definition.optimal_max):
		return (float(definition.wet_stop) - water) / (float(definition.wet_stop) - float(definition.optimal_max))
	return 1.0


func advance(plot: Dictionary, minutes: int, daylight: bool) -> bool:
	if plot.crop.is_empty() or is_mature(plot.crop) or minutes <= 0:
		return false
	var definition := Catalog.definition(plot.crop.id)
	if definition.is_empty():
		return false
	var rate := water_factor(plot) * (1.0 if daylight else float(definition.night_factor))
	plot.crop.age_minutes = float(plot.crop.get("age_minutes", 0.0)) + float(minutes)
	plot.crop.growth = clampf(float(plot.crop.growth) + float(minutes) * rate / float(definition.growth_minutes), 0.0, 1.0)
	return is_mature(plot.crop)


func transpiration_mm_h(plot: Dictionary, daylight: bool) -> float:
	if plot.crop.is_empty() or is_mature(plot.crop):
		return 0.0
	var definition := Catalog.definition(plot.crop.id)
	if definition.is_empty():
		return 0.0
	var size_factor := lerpf(0.2, 1.0, clampf(float(plot.crop.growth), 0.0, 1.0))
	return float(definition.transpiration_mm_h) * size_factor * water_factor(plot) * (1.0 if daylight else 0.22)


func describe(plot: Dictionary, daylight: bool) -> Dictionary:
	if plot.crop.is_empty():
		return {}
	var definition := Catalog.definition(plot.crop.id)
	if definition.is_empty():
		return {}
	var ready := is_mature(plot.crop)
	var factor := water_factor(plot)
	var rate := factor * (1.0 if daylight else float(definition.night_factor))
	if ready:
		rate = 0.0
	var water := float(plot.moisture)
	var reason: String = "生长正常"
	if ready:
		reason = "已经成熟，可以收获"
	elif water <= float(definition.dry_stop):
		reason = "缺水，暂停生长"
	elif water >= float(definition.wet_stop):
		reason = "过湿，暂停生长"
	elif water < float(definition.optimal_min):
		reason = "水分偏低，生长减慢"
	elif water > float(definition.optimal_max):
		reason = "水分偏高，生长减慢"
	elif not daylight:
		reason = "夜间，生长较慢"
	var help_text := "适宜水分 %.0f–%.0f%%；缺水可浇水，过湿时等待排水。" % [definition.optimal_min, definition.optimal_max]
	if ready:
		help_text = "按 5 后靠近点击收获，翻土和水分会保留，可以再次播种。"
	return {"stage": STAGE_NAMES[stage(plot.crop)], "progress": clampf(float(plot.crop.growth), 0.0, 1.0) * 100.0,
		"ready": ready, "rate": rate, "reason": reason, "help": help_text,
		"age_hours": float(plot.crop.get("age_minutes", 0.0)) / 60.0,
		"base_hours": float(definition.growth_minutes) / 60.0}
