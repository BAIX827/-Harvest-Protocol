extends RefCounted
## Real time only fills a queue. Every consumer receives the same fixed-size steps.

signal stepped(minutes: int, end_minutes: int)
signal controls_changed

const STEP_MINUTES: int = 5
const REAL_SECONDS_PER_STEP: float = 0.5
const SPEEDS := [1, 4, 12]
const MAX_STEPS_PER_FRAME: int = 64
const EPSILON: float = 0.000000001

var total_minutes: int = 480
var tick_count: int = 0
var speed: int = 1
var paused: bool = false
var accumulator: float = 0.0


func advance(real_seconds: float) -> int:
	if paused or not is_finite(real_seconds) or real_seconds < 0.0:
		return 0
	accumulator += real_seconds * float(speed)
	var count: int = 0
	while not paused and accumulator + EPSILON >= REAL_SECONDS_PER_STEP and count < MAX_STEPS_PER_FRAME:
		accumulator = maxf(0.0, accumulator - REAL_SECONDS_PER_STEP)
		total_minutes += STEP_MINUTES
		tick_count += 1
		count += 1
		stepped.emit(STEP_MINUTES, total_minutes)
	# Remaining time is retained for the next frame, never discarded by the work cap.
	return count


func set_paused(value: bool) -> void:
	if paused == value:
		return
	paused = value
	controls_changed.emit()


func toggle_paused() -> void:
	set_paused(not paused)


func set_speed(value: int) -> void:
	if value not in SPEEDS or speed == value:
		return
	speed = value
	controls_changed.emit()


func day() -> int:
	return floori(float(total_minutes) / 1440.0) + 1


func time_text() -> String:
	var minute_of_day: int = total_minutes % 1440
	return "%02d:%02d" % [minute_of_day / 60, minute_of_day % 60]


func period_name() -> String:
	var minute: int = total_minutes % 1440
	if minute < 240 or minute >= 1200:
		return "夜间"
	if minute < 360:
		return "黎明"
	if minute >= 1080:
		return "暮色"
	return "白昼"


func is_daylight_at(minutes: int) -> bool:
	var minute: int = minutes % 1440
	return minute >= 360 and minute < 1080


func export_state() -> Dictionary:
	return {"total_minutes": total_minutes, "tick_count": tick_count, "speed": speed, "paused": paused, "accumulator": accumulator}


func can_restore(data: Dictionary) -> bool:
	for key in ["total_minutes", "tick_count", "speed"]:
		if not data.has(key) or not (data[key] is int or data[key] is float):
			return false
		if not is_finite(float(data[key])) or float(data[key]) != float(int(data[key])):
			return false
	if int(data.total_minutes) < 0 or int(data.total_minutes) % STEP_MINUTES != 0 or int(data.tick_count) < 0:
		return false
	if int(data.speed) not in SPEEDS or not data.get("paused") is bool:
		return false
	if not (data.get("accumulator") is float or data.get("accumulator") is int):
		return false
	return is_finite(float(data.accumulator)) and float(data.accumulator) >= 0.0


func restore_state(data: Dictionary) -> bool:
	if not can_restore(data):
		return false
	total_minutes = int(data.total_minutes)
	tick_count = int(data.tick_count)
	speed = int(data.speed)
	paused = data.paused
	accumulator = float(data.accumulator)
	controls_changed.emit()
	return true
