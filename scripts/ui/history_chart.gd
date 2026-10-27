extends Control
## Plot measured history only. Invalid readings are gaps, never zeros or truth substitutes.

const Sensor = preload("res://scripts/engineering/sensor_model.gd")
var records: Array = []
var _hover: int = -1


func _ready() -> void:
	custom_minimum_size = Vector2(400, 300)
	mouse_filter = Control.MOUSE_FILTER_PASS
	resized.connect(queue_redraw)
	mouse_exited.connect(func() -> void:
		_hover = -1
		queue_redraw())


func set_records(history: Array) -> void:
	records = history.duplicate(true)
	_hover = mini(_hover, records.size() - 1)
	queue_redraw()


func _plot() -> Rect2:
	return Rect2(50, 16, maxf(1, size.x - 70), maxf(1, size.y - 52))


func _point(index: int, field: String) -> Vector2:
	var plot := _plot()
	var start: float = minf(float(records[0].minute), float(records.back().minute) - 5.0)
	var span: float = maxf(5.0, float(records.back().minute) - start)
	return Vector2(plot.position.x + (float(records[index].minute) - start) / span * plot.size.x, plot.end.y - float(records[index][field]) / 60.0 * plot.size.y)


static func stamp(minute: int) -> String:
	return "D%d %02d:%02d" % [minute / 1440 + 1, minute % 1440 / 60, minute % 60]


func _draw() -> void:
	var font := get_theme_default_font()
	var plot := _plot()
	draw_rect(plot, Color("15242c"))
	for value in [0, 20, 40, 60]:
		var y := plot.end.y - float(value) / 60.0 * plot.size.y
		draw_line(Vector2(plot.position.x, y), Vector2(plot.end.x, y), Color("344953"), 1)
		draw_string(font, Vector2(3, y + 5), "%d%%" % value, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("9fafaf"))
	if records.is_empty():
		draw_string(font, plot.position + Vector2(24, plot.size.y / 2.0), "尚无采样数据，请采购并安装探头。", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color("9fafaf"))
		return
	for index in range(records.size()):
		var row: Dictionary = records[index]
		if index > 0 and records[index - 1].cell == row.cell:
			draw_line(_point(index - 1, "truth"), _point(index, "truth"), Color("a9c18b"), 2)
			if row.valid and records[index - 1].valid and row.revision == records[index - 1].revision:
				draw_line(_point(index - 1, "reading"), _point(index, "reading"), Color("cab889"), 2)
		draw_circle(_point(index, "truth"), 1.5, Color("a9c18b"))
		if row.valid:
			draw_circle(_point(index, "reading"), 1.8, Color("cab889"))
		else:
			var p := Vector2(_point(index, "truth").x, plot.end.y + 7)
			draw_line(p - Vector2(3, 3), p + Vector2(3, 3), Color("d49579"), 1)
			draw_line(p - Vector2(3, -3), p + Vector2(3, -3), Color("d49579"), 1)
	draw_string(font, Vector2(plot.position.x, plot.end.y + 25), stamp(int(records[0].minute)), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("9fafaf"))
	draw_string(font, Vector2(plot.end.x - 100, plot.end.y + 25), stamp(int(records.back().minute)), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("9fafaf"))
	if _hover >= 0 and _hover < records.size():
		var x := _point(_hover, "truth").x
		draw_line(Vector2(x, plot.position.y), Vector2(x, plot.end.y), Color("9fafaf"), 1)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and not records.is_empty():
		_hover = _nearest(event.position.x)
		queue_redraw()


func _nearest(x: float) -> int:
	var nearest: int = -1
	var distance: float = INF
	for index in range(records.size()):
		var candidate := absf(_point(index, "truth").x - x)
		if candidate <= distance:
			distance = candidate
			nearest = index
	return nearest


func _get_tooltip(at_position: Vector2) -> String:
	if records.is_empty(): return "无采样数据。"
	var row: Dictionary = records[_nearest(at_position.x)]
	return "#%d · %s · 地块 (%d,%d)\n采样真实值 %.2f%%\n读数 %s\n%s\n配置版本 %d：位置或系数变化后不跨段连线。" % [row.serial, stamp(int(row.minute)), int(row.cell[0]) + 1, int(row.cell[1]) + 1, row.truth, "%.2f%%" % row.reading if row.valid else "无效", Sensor.REASONS[row.code], row.revision]
