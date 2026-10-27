extends RefCounted
## One fixed-step ordering for control, irrigation, soil, crops and measurement.

signal updated
signal step_completed(context: Dictionary)
signal crops_matured(cells: Array)

const FarmState = preload("res://scripts/simulation/farm_state.gd")
const SimulationClock = preload("res://scripts/simulation/simulation_clock.gd")
const WeatherModel = preload("res://scripts/simulation/weather_model.gd")
const CropModel = preload("res://scripts/simulation/crop_model.gd")
const Irrigation = preload("res://scripts/engineering/irrigation_network.gd")
const Sensor = preload("res://scripts/engineering/sensor_model.gd")
const Automation = preload("res://scripts/engineering/automation_controller.gd")

const ROOT_ZONE_MM: float = 200.0
const INFILTRATION: float = 0.85
const FIELD_CAPACITY: float = 35.0
const DRAINAGE_PER_HOUR: float = 0.18

var farm: FarmState
var clock := SimulationClock.new()
var weather := WeatherModel.new()
var crops := CropModel.new()
var irrigation: Irrigation
var sensor: Sensor
var automation: Automation
var _matured_this_batch: Array[Dictionary] = []
var _irrigation_changed: bool = false
var _sensor_changed: bool = false
var _automation_changed: bool = false


func _init(state: FarmState) -> void:
	farm = state
	irrigation = Irrigation.new(farm)
	sensor = Sensor.new(farm)
	automation = Automation.new(farm, irrigation, sensor, clock)
	clock.stepped.connect(_simulate_step)


func advance(real_seconds: float) -> int:
	_matured_this_batch.clear()
	_irrigation_changed = false
	_sensor_changed = false
	_automation_changed = false
	var steps := clock.advance(real_seconds)
	if steps > 0:
		updated.emit()
		if _irrigation_changed: farm.engineering_changed.emit()
		if _sensor_changed: farm.sensor_changed.emit()
		if _automation_changed: farm.automation_changed.emit()
		if not _matured_this_batch.is_empty():
			crops_matured.emit(_matured_this_batch.duplicate(true))
	return steps


func _simulate_step(minutes: int, end_minutes: int) -> void:
	var start_minutes := end_minutes - minutes
	weather.ensure_period(start_minutes)
	var definition := weather.current()
	var interval_kind := weather.kind
	var daylight := clock.is_daylight_at(start_minutes)
	if automation.evaluate(start_minutes): _automation_changed = true
	if irrigation.advance(minutes): _irrigation_changed = true
	for y in range(FarmState.HEIGHT):
		for x in range(FarmState.WIDTH):
			var cell := Vector2i(x, y)
			if not farm.is_arable(cell):
				continue
			var plot := farm.plot_at(cell)
			var balance := _water_rates(plot, definition, daylight)
			plot.moisture = clampf(float(plot.moisture) + float(balance.net) * float(minutes) / 60.0, 0.0, FarmState.MAX_MOISTURE)
			if crops.advance(plot, minutes, daylight):
				_matured_this_batch.append({"cell": cell, "crop_id": plot.crop.id})
	# Apply [start, end) with its original weather, then expose the next block to UI.
	weather.ensure_period(end_minutes)
	if sensor.sample(end_minutes): _sensor_changed = true
	if automation.evaluate(end_minutes): _automation_changed = true
	step_completed.emit({"minutes": minutes, "start_minutes": start_minutes, "end_minutes": end_minutes,
		"weather_kind": interval_kind, "weather": definition, "daylight": daylight})


func _water_rates(plot: Dictionary, definition: Dictionary, daylight: bool) -> Dictionary:
	var rain := float(definition.rain_mm_h) * INFILTRATION * 100.0 / ROOT_ZONE_MM
	var cover: float = 1.0 if plot.tilled else 0.7
	var evaporation := float(definition.evap_mm_h) * 100.0 / ROOT_ZONE_MM * cover * (1.0 if daylight else 0.22)
	var drainage := maxf(0.0, float(plot.moisture) - FIELD_CAPACITY) * DRAINAGE_PER_HOUR
	var transpiration := crops.transpiration_mm_h(plot, daylight) * 100.0 / ROOT_ZONE_MM
	return {"rain": rain, "evaporation": evaporation, "drainage": drainage, "transpiration": transpiration, "net": rain - evaporation - drainage - transpiration}


func water_rates_at(cell: Vector2i) -> Dictionary:
	if not farm.is_arable(cell):
		return {"rain": 0.0, "irrigation": 0.0, "evaporation": 0.0, "drainage": 0.0, "transpiration": 0.0, "net": 0.0}
	var rates := _water_rates(farm.plot_at(cell), weather.current(), clock.is_daylight_at(clock.total_minutes))
	rates.irrigation = irrigation.preview_rate(cell)
	rates.net += rates.irrigation
	return rates


func night_opacity() -> float:
	var minute: int = clock.total_minutes % 1440
	if minute < 240 or minute >= 1200:
		return 0.24
	if minute < 360:
		return 0.24 * (1.0 - float(minute - 240) / 120.0)
	if minute >= 1080:
		return 0.24 * float(minute - 1080) / 120.0
	return 0.0


func export_runtime() -> Dictionary:
	return {"clock": clock.export_state(), "weather": weather.export_state()}


func restore_runtime(data: Dictionary) -> bool:
	if not data.get("clock") is Dictionary or not data.get("weather") is Dictionary:
		return false
	if not clock.can_restore(data.clock) or not weather.can_restore(data.weather):
		return false
	if int(data.weather.period_index) != floori(float(data.clock.total_minutes) / WeatherModel.PERIOD_MINUTES):
		return false
	weather.restore_state(data.weather)
	clock.restore_state(data.clock)
	updated.emit()
	return true
