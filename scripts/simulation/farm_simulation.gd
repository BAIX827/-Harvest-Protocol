extends RefCounted
## Ordered environment updates shared by rendering and future crop/device models.

signal updated
signal step_completed(context: Dictionary)

const FarmState = preload("res://scripts/simulation/farm_state.gd")
const SimulationClock = preload("res://scripts/simulation/simulation_clock.gd")
const WeatherModel = preload("res://scripts/simulation/weather_model.gd")

const ROOT_ZONE_MM: float = 200.0
const INFILTRATION: float = 0.85
const FIELD_CAPACITY: float = 35.0
const DRAINAGE_PER_HOUR: float = 0.18

var farm: FarmState
var clock := SimulationClock.new()
var weather := WeatherModel.new()


func _init(state: FarmState) -> void:
	farm = state
	clock.stepped.connect(_simulate_step)


func advance(real_seconds: float) -> int:
	var steps := clock.advance(real_seconds)
	if steps > 0:
		updated.emit()
	return steps


func _simulate_step(minutes: int, end_minutes: int) -> void:
	var start_minutes := end_minutes - minutes
	weather.ensure_period(start_minutes)
	var definition := weather.current()
	var interval_kind := weather.kind
	var daylight := clock.is_daylight_at(start_minutes)
	for y in range(FarmState.HEIGHT):
		for x in range(FarmState.WIDTH):
			var cell := Vector2i(x, y)
			if not farm.is_arable(cell):
				continue
			var plot := farm.plot_at(cell)
			var balance := _water_rates(plot, definition, daylight)
			plot.moisture = clampf(float(plot.moisture) + float(balance.net) * float(minutes) / 60.0, 0.0, FarmState.MAX_MOISTURE)
	# Apply [start, end) with its original weather, then expose the next block to UI.
	weather.ensure_period(end_minutes)
	step_completed.emit({"minutes": minutes, "start_minutes": start_minutes, "end_minutes": end_minutes,
		"weather_kind": interval_kind, "weather": definition, "daylight": daylight})


func _water_rates(plot: Dictionary, definition: Dictionary, daylight: bool) -> Dictionary:
	var rain := float(definition.rain_mm_h) * INFILTRATION * 100.0 / ROOT_ZONE_MM
	var cover: float = 1.0 if plot.tilled else 0.7
	var evaporation := float(definition.evap_mm_h) * 100.0 / ROOT_ZONE_MM * cover * (1.0 if daylight else 0.22)
	var drainage := maxf(0.0, float(plot.moisture) - FIELD_CAPACITY) * DRAINAGE_PER_HOUR
	return {"rain": rain, "evaporation": evaporation, "drainage": drainage, "net": rain - evaporation - drainage}


func water_rates_at(cell: Vector2i) -> Dictionary:
	if not farm.is_arable(cell):
		return {"rain": 0.0, "evaporation": 0.0, "drainage": 0.0, "net": 0.0}
	return _water_rates(farm.plot_at(cell), weather.current(), clock.is_daylight_at(clock.total_minutes))


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
