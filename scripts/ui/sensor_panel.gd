extends Control
## Live measurement desk. Time keeps its setting; edits never change soil truth.

signal opened
signal closed

const Controller = preload("res://scripts/engineering/sensor_controller.gd")
const Catalog = preload("res://scripts/engineering/sensor_catalog.gd")
const Model = preload("res://scripts/engineering/sensor_model.gd")
const Modules = preload("res://scripts/engineering/module_catalog.gd")
const Chart = preload("res://scripts/ui/history_chart.gd")
var controller: Controller
var _frame: Panel
var buy_button: Button
var install_button: Button
var remove_button: Button
var close_button: Button
var apply_button: Button
var sample_button: Button
var connection_button: Button
var calibrate_button: Button
var reset_button: Button
var coefficients_button: Button
var pause_button: Button
var speed_button: Button
var fault_button: Button
var x_input: SpinBox
var y_input: SpinBox
var soil_choice: OptionButton
var mount_choice: OptionButton
var fault_choice: OptionButton
var gain_input: SpinBox
var offset_input: SpinBox
var reference_input: SpinBox
var chart: Chart
var status_label: Label
var truth_label: Label
var raw_label: Label
var converted_label: Label
var configuration_label: Label
var history_label: Label
var balance_label: Label
var receipt_label: Label


func setup(shared_controller: Controller) -> void:
	controller = shared_controller
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	controller.economy.farm.sensor_changed.connect(_refresh)
	controller.economy.farm.economy_changed.connect(_refresh)
	controller.economy.farm.supplies_changed.connect(_refresh)
	controller.economy.farm.plot_changed.connect(func(_point: Vector2i) -> void: _refresh())
	controller.economy.clock.controls_changed.connect(_refresh)
	visible = false


func _ready() -> void:
	resized.connect(_layout_frame)
	_layout_frame()


func open_panel() -> void:
	if visible: return
	_sync_inputs()
	show()
	_layout_frame()
	_refresh()
	opened.emit()


func close_panel() -> void:
	if not visible: return
	hide()
	closed.emit()


func _layout_frame() -> void:
	_frame.size = Vector2(minf(1320, size.x - 48), minf(920, size.y - 48))
	_frame.position = ((size - _frame.size) / 2).floor()


func _label(text_value: String, font_size: int = 17) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", font_size)
	return label


func _paragraph(text_value: String) -> Label:
	var label := _label(text_value)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _button(text_value: String, callback: Callable) -> Button:
	var result := Button.new()
	result.text = text_value
	result.focus_mode = Control.FOCUS_NONE
	result.add_theme_font_size_override("font_size", 16)
	result.pressed.connect(callback)
	return result


func _spin(low: float, high: float, step: float, value: float) -> SpinBox:
	var result := SpinBox.new()
	result.min_value = low
	result.max_value = high
	result.step = step
	result.value = value
	result.custom_minimum_size.x = 112
	result.add_theme_font_size_override("font_size", 16)
	return result


func _choice(items: Dictionary) -> OptionButton:
	var result := OptionButton.new()
	result.add_theme_font_size_override("font_size", 16)
	for id in items:
		result.add_item(str(items[id]))
		result.set_item_metadata(result.item_count - 1, id)
	return result


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.04, 0.05, 0.85)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	_frame = Panel.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("1a2a33")
	style.border_color = Color("586b71")
	style.set_border_width_all(1)
	_frame.add_theme_stylebox_override("panel", style)
	add_child(_frame)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	_frame.add_child(column)
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.offset_left = 24
	column.offset_top = 20
	column.offset_right = -24
	column.offset_bottom = -20
	var header := HBoxContainer.new()
	column.add_child(header)
	var title := _label("土壤水分测量台", 26)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	balance_label = _label("", 19)
	header.add_child(balance_label)
	close_button = _button("返回农场 [I / Esc]", close_panel)
	header.add_child(close_button)
	column.add_child(_paragraph("真实值是教学对照，控制只能使用有效读数。测量台保持原来的时间设置；空格可暂停，12× 可观察采样历史。"))
	var time_row := HBoxContainer.new()
	column.add_child(time_row)
	pause_button = _button("", func() -> void: controller.economy.clock.toggle_paused())
	speed_button = _button("12× 继续", func() -> void:
		controller.economy.clock.set_speed(12)
		controller.economy.clock.set_paused(false))
	time_row.add_child(pause_button)
	time_row.add_child(speed_button)
	sample_button = _button("立即采样", func() -> void: _result(controller.sample_now()))
	time_row.add_child(sample_button)
	status_label = _label("", 18)
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	time_row.add_child(status_label)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var body := HBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 28)
	scroll.add_child(body)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 490
	left.add_theme_constant_override("separation", 10)
	body.add_child(left)
	var trade := HBoxContainer.new()
	left.add_child(trade)
	buy_button = _button("采购探头", _buy)
	install_button = _button("安装库存", func() -> void: _result(controller.install()))
	remove_button = _button("拆回库存", func() -> void: _result(controller.remove()))
	trade.add_child(buy_button)
	trade.add_child(install_button)
	trade.add_child(remove_button)
	left.add_child(_label("测量位置与条件", 19))
	var location := HBoxContainer.new()
	left.add_child(location)
	location.add_child(_label("X / Y"))
	x_input = _spin(1, 24, 1, 11)
	y_input = _spin(1, 24, 1, 9)
	location.add_child(x_input)
	location.add_child(y_input)
	var options := HBoxContainer.new()
	left.add_child(options)
	var config := Catalog.config()
	var soils: Dictionary = {}
	var mounts: Dictionary = {}
	for id in config.soils: soils[id] = config.soils[id].name
	for id in config.mounts: mounts[id] = config.mounts[id].name
	soil_choice = _choice(soils)
	mount_choice = _choice(mounts)
	options.add_child(soil_choice)
	options.add_child(mount_choice)
	apply_button = _button("应用位置与条件", _configure)
	left.add_child(apply_button)
	left.add_child(_paragraph("土壤响应和接触条件只改变探头信号，不修改农田水分。换位置或条件后，已有校准不一定适用。"))
	var fault_row := HBoxContainer.new()
	left.add_child(fault_row)
	connection_button = _button("", func() -> void: _result(controller.set_connected(not controller.economy.farm.sensor.connected)))
	fault_row.add_child(connection_button)
	fault_choice = _choice({"none": "正常", "open": "开路", "short": "短路", "stuck": "卡住"})
	fault_row.add_child(fault_choice)
	fault_button = _button("设置故障", func() -> void: _result(controller.set_fault(_selected(fault_choice))))
	fault_row.add_child(fault_button)
	left.add_child(HSeparator.new())
	left.add_child(_label("校准 · 作用于同一测量链", 19))
	left.add_child(_label("增益（无量纲） / 偏移（百分点）", 16))
	var coefficients := HBoxContainer.new()
	left.add_child(coefficients)
	gain_input = _spin(0.5, 1.5, 0.001, 1)
	offset_input = _spin(-20, 20, 0.001, 0)
	coefficients.add_child(gain_input)
	coefficients.add_child(offset_input)
	coefficients_button = _button("应用系数", _coefficients)
	coefficients.add_child(coefficients_button)
	var reference := HBoxContainer.new()
	left.add_child(_label("单点参考值（体积含水量 %）", 16))
	left.add_child(reference)
	reference_input = _spin(0, 60, 0.1, 18)
	reference.add_child(reference_input)
	calibrate_button = _button("按参考值校准", _calibrate)
	reference.add_child(calibrate_button)
	reset_button = _button("复位出厂系数", func() -> void:
		_result(controller.set_calibration(1.0, 0.0))
		_sync_inputs())
	left.add_child(reset_button)
	configuration_label = _paragraph("")
	left.add_child(configuration_label)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.custom_minimum_size.x = 620
	right.add_theme_constant_override("separation", 10)
	body.add_child(right)
	truth_label = _label("", 21)
	right.add_child(truth_label)
	raw_label = _label("")
	right.add_child(raw_label)
	converted_label = _label("", 21)
	right.add_child(converted_label)
	right.add_child(_paragraph("绿色：采样真实值　浅黄：有效读数　轴下红叉：无效采样\n单位为体积含水量 %；横轴为游戏时间，悬停查看位置和明细。"))
	chart = Chart.new()
	chart.custom_minimum_size = Vector2(580, 300)
	right.add_child(chart)
	history_label = _paragraph("")
	right.add_child(history_label)
	right.add_child(_paragraph("信号来源：水分响应 + 土壤响应差异 + 安装偏移 + 固定器件偏差 + 独立噪声，再经 ADC 量化。校准只影响之后的换算，不会改写旧曲线。此处为游戏模型。"))
	receipt_label = _paragraph("采购并安装探头后，先对照真实值，再尝试不同安装方式和校准。自动水泵控制在下一步加入。")
	column.add_child(receipt_label)


func _selected(choice: OptionButton) -> String:
	return str(choice.get_item_metadata(choice.selected))


func _select(choice: OptionButton, id: String) -> void:
	for index in range(choice.item_count):
		if str(choice.get_item_metadata(index)) == id: choice.select(index)


func _sync_inputs() -> void:
	var state: Dictionary = controller.economy.farm.sensor
	x_input.value = int(state.cell[0]) + 1
	y_input.value = int(state.cell[1]) + 1
	_select(soil_choice, state.soil)
	_select(mount_choice, state.mount)
	_select(fault_choice, state.fault)
	gain_input.value = state.slope
	offset_input.value = state.offset


func _buy() -> void:
	_result(controller.economy.buy_modules({"sensor_basic": 1}))


func _configure() -> void:
	_result(controller.configure(Vector2i(int(x_input.value) - 1, int(y_input.value) - 1), _selected(soil_choice), _selected(mount_choice)))


func _coefficients() -> void:
	_result(controller.set_calibration(gain_input.value, offset_input.value))
	_sync_inputs()


func _calibrate() -> void:
	_result(controller.calibrate(reference_input.value))
	_sync_inputs()


func _result(result: Dictionary) -> void:
	receipt_label.text = result.message
	_refresh()


func _refresh() -> void:
	if chart == null: return
	var farm := controller.economy.farm
	var clock := controller.economy.clock
	var state: Dictionary = farm.sensor
	var measured := controller.model.current(clock.total_minutes)
	var model = Model
	var price := int(Modules.definition("sensor_basic").price)
	balance_label.text = "资金 %d 币 · 备用探头 %d　" % [farm.cash, farm.parts_stock.get("sensor_basic", 0)]
	buy_button.text = "采购探头 · %d 币" % price
	buy_button.disabled = farm.cash < price or int(farm.parts_stock.get("sensor_basic", 0)) >= 1000
	install_button.disabled = state.installed or int(farm.parts_stock.get("sensor_basic", 0)) < 1
	remove_button.disabled = not state.installed
	sample_button.disabled = not state.installed
	calibrate_button.disabled = not measured.valid
	pause_button.text = "继续 [空格]" if clock.paused else "暂停 [空格]"
	status_label.text = "%s · %s" % [Chart.stamp(clock.total_minutes), model.REASONS[measured.code]]
	connection_button.text = "断开信号" if state.connected else "接通信号"
	truth_label.text = "地块 (%d,%d) · 当前真实值 %.2f%%" % [int(state.cell[0]) + 1, int(state.cell[1]) + 1, controller.model.truth()]
	if measured.raw_adc != null:
		raw_label.text = "原始信号 %.4f V · ADC %d / 4095\n出厂换算 %.2f%% · 采样 %s" % [measured.volts, measured.raw_adc, measured.factory, Chart.stamp(int(measured.minute))]
	else:
		raw_label.text = "原始信号 — · 出厂换算 —\n%s" % model.REASONS[measured.code]
	converted_label.text = "有效读数 %.2f%% · 采样误差 %+.2f 百分点" % [measured.reading, float(measured.reading) - float(measured.truth)] if measured.valid else "测量无效 · 不提供控制数值"
	converted_label.add_theme_color_override("font_color", Color("cab889") if measured.valid else Color("d49579"))
	configuration_label.text = "通道 %s · 配置版本 %d\n当前系数：增益 %.3f，偏移 %+.3f" % [state.instance_id, state.revision, state.slope, state.offset]
	chart.set_records(state.history)
	history_label.text = "每 5 游戏分钟采样 · 最近 %d / 180 次 · 累计 %d 次。移动探头或更改配置时断开相应曲线段。" % [state.history.size(), state.sample_count]
