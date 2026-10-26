extends RefCounted
## Seeded six-hour weather blocks. RNG state is kept independently of frame rate.

const PERIOD_MINUTES: int = 360
const DEFAULT_SEED: int = 20261027
enum Kind { CLEAR, CLOUDY, RAIN, SHOWERS }
const DEFINITIONS := [
	{"name": "晴", "rain_mm_h": 0.0, "evap_mm_h": 1.6},
	{"name": "多云", "rain_mm_h": 0.0, "evap_mm_h": 0.8},
	{"name": "小雨", "rain_mm_h": 4.8, "evap_mm_h": 0.25},
	{"name": "阵雨", "rain_mm_h": 8.0, "evap_mm_h": 0.12},
]

var kind: int = Kind.CLEAR
var period_index: int = -1
var _seed: int = DEFAULT_SEED
var _rng := RandomNumberGenerator.new()


func _init(seed_value: int = DEFAULT_SEED, start_minutes: int = 480) -> void:
	_seed = seed_value
	_rng.seed = _seed
	ensure_period(start_minutes)


func ensure_period(total_minutes: int) -> void:
	var target := floori(float(total_minutes) / float(PERIOD_MINUTES))
	while period_index < target:
		period_index += 1
		var roll := _rng.randi_range(0, 99)
		kind = Kind.CLEAR if roll < 45 else Kind.CLOUDY if roll < 73 else Kind.RAIN if roll < 92 else Kind.SHOWERS
		# Every block consumes a draw; the first morning and noon are a teaching setup.
		if period_index <= 1:
			kind = Kind.CLEAR
		elif period_index == 2:
			kind = Kind.RAIN


func current() -> Dictionary:
	return DEFINITIONS[kind].duplicate(true)


func is_raining() -> bool:
	return float(DEFINITIONS[kind].rain_mm_h) > 0.0


func export_state() -> Dictionary:
	# Strings preserve every bit of the 64-bit random state through JSON.
	return {"seed": str(_seed), "rng_state": str(_rng.state), "kind": kind, "period_index": period_index}


func can_restore(data: Dictionary) -> bool:
	for key in ["seed", "rng_state"]:
		if not data.get(key) is String or not String(data[key]).is_valid_int():
			return false
	for key in ["kind", "period_index"]:
		if not (data.get(key) is int or data.get(key) is float):
			return false
		if not is_finite(float(data[key])) or float(data[key]) != float(int(data[key])):
			return false
	return int(data.kind) >= Kind.CLEAR and int(data.kind) <= Kind.SHOWERS and int(data.period_index) >= 0


func restore_state(data: Dictionary) -> bool:
	if not can_restore(data):
		return false
	_seed = int(data.seed)
	_rng.seed = _seed
	_rng.state = int(data.rng_state)
	kind = int(data.kind)
	period_index = int(data.period_index)
	return true
