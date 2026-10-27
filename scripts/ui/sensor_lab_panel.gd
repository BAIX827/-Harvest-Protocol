extends Control
const CTheme = preload("res://scripts/ui/c_theme.gd")
const Presentation = preload("res://scripts/ui/system_presentation.gd")
## Reference controls affect the cup only; task badges follow stored real evidence.

signal opened
signal closed
signal navigation_requested(destination: String)
const Controller = preload("res://scripts/progression/learning_controller.gd")
const Catalog = preload("res://scripts/progression/learning_catalog.gd")
const SensorCatalog = preload("res://scripts/engineering/sensor_catalog.gd")
const Sensor = preload("res://scripts/engineering/sensor_model.gd")
var controller: Controller
var _frame: Panel
var tabs: TabContainer
var truth_input: SpinBox
var soil_choice: OptionButton
var mount_choice: OptionButton
var conditions_button: Button
var point_a_button: Button
var point_b_button: Button
var calibrate_button: Button
var apply_button: Button
var sample_button: Button
var start_button: Button
var observe_button: Button
var diagnose_button: Button
var diagnosis_choice: OptionButton
var verify_button: Button
var cancel_button: Button
var pause_button: Button
var speed_button: Button
var experiment_label: RichTextLabel
var task_label: RichTextLabel
var status_label: Label
var receipt_label: Label
var preset_a: Button
var preset_b: Button


func setup(shared_controller: Controller) -> void:
	controller = shared_controller
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	controller.farm.learning_changed.connect(_refresh)
	controller.simulation.updated.connect(_refresh)
	controller.simulation.clock.controls_changed.connect(_refresh)
	visible = false


func _ready() -> void:
	resized.connect(_layout)
	_layout()


func _layout() -> void:
	_frame.size = Vector2(minf(1320, size.x - 48), minf(920, size.y - 48))
	_frame.position = ((size - _frame.size) / 2).floor()


func open_panel() -> void:
	if visible: return
	_sync_inputs()
	tabs.current_tab = 0 if controller.farm.learning.experiment.is_empty() else 1
	show()
	_layout()
	_refresh()
	opened.emit()


func close_panel() -> void:
	if not visible: return
	hide()
	closed.emit()


func _label(value: String, font_size: int = 17) -> Label:
	var result := Label.new()
	result.text = value
	result.add_theme_font_size_override("font_size", font_size)
	return result


func _paragraph(value: String) -> Label:
	var result := _label(value)
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return result


func _button(value: String, action: Callable) -> Button:
	var result := Button.new()
	result.text = value
	result.focus_mode = Control.FOCUS_NONE
	result.add_theme_font_size_override("font_size", 16)
	result.pressed.connect(action)
	return result


func _choice(values: Dictionary) -> OptionButton:
	var result := OptionButton.new()
	result.add_theme_font_size_override("font_size", 16)
	for key in values:
		result.add_item(str(values[key]))
		result.set_item_metadata(result.item_count - 1, key)
	return result


func _selected(choice: OptionButton) -> String:
	return str(choice.get_item_metadata(choice.selected))


func _tab(name_value: String) -> HBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = name_value
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(scroll)
	var body := HBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 28)
	scroll.add_child(body)
	return body


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.04, 0.05, 0.85)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	_frame = Panel.new()
	_frame.add_theme_stylebox_override("panel", CTheme.panel_style())
	add_child(_frame)
	var column := VBoxContainer.new()
	_frame.add_child(column)
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.offset_left = 24
	column.offset_top = 20
	column.offset_right = -24
	column.offset_bottom = -20
	column.add_theme_constant_override("separation", 12)
	var header := HBoxContainer.new()
	column.add_child(header)
	var title := _label("参考实验与故障教学", 26)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	header.add_child(_button("返回农场 [L / Esc]", close_panel))
	column.add_child(_paragraph("样杯与农场隔离，含水量控件不会给农田加水。校准需明确同步；故障任务在真实农场进行。保持原时间设置，可用空格暂停。"))
	var time_row := HBoxContainer.new()
	column.add_child(time_row)
	pause_button = _button("", func() -> void: controller.simulation.clock.toggle_paused())
	speed_button = _button("12× 继续", func() -> void:
		controller.simulation.clock.set_speed(12)
		controller.simulation.clock.set_paused(false))
	time_row.add_child(pause_button)
	time_row.add_child(speed_button)
	for key in ["E", "I", "T"]:
		time_row.add_child(_button({"E": "设备 [E]", "I": "探头 [I]", "T": "控制 [T]"}[key], func() -> void: navigation_requested.emit(key)))
	status_label = _paragraph("")
	column.add_child(status_label)
	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(tabs)
	var experiment := _tab("参考实验")
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 500
	left.add_theme_constant_override("separation", 10)
	experiment.add_child(left)
	left.add_child(_label("独立参考样杯", 20))
	var row := HBoxContainer.new()
	left.add_child(row)
	row.add_child(_label("已知体积含水量 %"))
	truth_input = SpinBox.new()
	truth_input.max_value = 60
	truth_input.step = 0.1
	truth_input.custom_minimum_size.x = 120
	row.add_child(truth_input)
	var config := SensorCatalog.config()
	var soils: Dictionary = {}
	var mounts: Dictionary = {}
	for key in config.soils: soils[key] = config.soils[key].name
	for key in config.mounts: mounts[key] = config.mounts[key].name
	var options := HBoxContainer.new()
	left.add_child(options)
	soil_choice = _choice(soils)
	mount_choice = _choice(mounts)
	options.add_child(soil_choice)
	options.add_child(mount_choice)
	conditions_button = _button("应用样杯条件并采样", _conditions)
	left.add_child(conditions_button)
	var presets := HBoxContainer.new()
	left.add_child(presets)
	preset_a = _button("20% 样杯", _preset.bind(20.0))
	preset_b = _button("40% 样杯", _preset.bind(40.0))
	presets.add_child(preset_a)
	presets.add_child(preset_b)
	var points := HBoxContainer.new()
	left.add_child(points)
	point_a_button = _button("记录参考 A", _record.bind(0))
	point_b_button = _button("记录参考 B", _record.bind(1))
	points.add_child(point_a_button)
	points.add_child(point_b_button)
	sample_button = _button("重新采样当前样杯", func() -> void: _result(controller.sample_now()))
	left.add_child(sample_button)
	calibrate_button = _button("两点校准 + 中点新采样复核", func() -> void:
		_result(controller.calibrate())
		_sync_inputs())
	left.add_child(calibrate_button)
	apply_button = _button("同步条件与系数到农场探头", func() -> void: _result(controller.apply_to_farm()))
	left.add_child(apply_button)
	left.add_child(_paragraph("A / B 至少相隔 10 个百分点。单换已知水分保留参考点；换土壤 / 安装响应会清除参考点。中点复核使用独立的新噪声样本。"))
	left.add_child(_paragraph("同步会改变农场探头的响应条件和校准系数，保留探头位置和真实水分。当前仅为游戏简化模型，不是实际仪器标定。"))
	experiment_label = RichTextLabel.new()
	experiment_label.custom_minimum_size = Vector2(620, 530)
	experiment_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	experiment_label.add_theme_font_size_override("normal_font_size", 19)
	experiment.add_child(experiment_label)
	var fault := _tab("故障教学")
	var actions := VBoxContainer.new()
	actions.custom_minimum_size.x = 520
	actions.add_theme_constant_override("separation", 12)
	fault.add_child(actions)
	actions.add_child(_paragraph("开始会明确断开一次真实探头信号。先完成实验，再准备已连线、可供水的自动系统；先观察诊断，再修复。"))
	start_button = _button("开始真实故障演练", func() -> void: _result(controller.start_fault()))
	observe_button = _button("记录当前故障观察", func() -> void: _result(controller.observe_fault()))
	actions.add_child(start_button)
	actions.add_child(observe_button)
	diagnosis_choice = _choice({"signal": "探头信号线断开", "water": "水箱没水", "pipe": "输水管断开", "power": "电源断开"})
	actions.add_child(diagnosis_choice)
	diagnose_button = _button("提交基于证据的诊断", func() -> void: _result(controller.diagnose(_selected(diagnosis_choice))))
	actions.add_child(diagnose_button)
	actions.add_child(_button("去测量台接通信号 [I]", func() -> void: navigation_requested.emit("I")))
	verify_button = _button("复核真实恢复状态", func() -> void:
		controller.review()
		_result({"message": controller.hint()}))
	actions.add_child(verify_button)
	cancel_button = _button("取消演练并接通信号", func() -> void: _result(controller.cancel_fault()))
	actions.add_child(cancel_button)
	actions.add_child(_paragraph("接通信号后还要自动出水并消耗新的电量，才完成任务。手动供水、重复点确认、改变样杯水分都不能代替真实恢复。"))
	task_label = RichTextLabel.new()
	task_label.custom_minimum_size = Vector2(600, 500)
	task_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	task_label.add_theme_font_size_override("normal_font_size", 19)
	fault.add_child(task_label)
	receipt_label = _paragraph("建议选黏土响应，依次记录 20% / 40% 样杯，再校准复核并同步。")
	column.add_child(receipt_label)


func _conditions() -> void:
	_result(controller.set_conditions(truth_input.value, _selected(soil_choice), _selected(mount_choice)))


func _preset(value: float) -> void:
	truth_input.value = value
	_conditions()


func _record(slot: int) -> void:
	var result := controller.set_conditions(truth_input.value, _selected(soil_choice), _selected(mount_choice))
	_result(controller.record_point(slot) if result.ok else result)


func _sync_inputs() -> void:
	var lab: Dictionary = controller.farm.learning.lab
	truth_input.value = lab.truth
	for choice in [soil_choice, mount_choice]:
		var id: String = lab.sensor.soil if choice == soil_choice else lab.sensor.mount
		for index in range(choice.item_count):
			if str(choice.get_item_metadata(index)) == id: choice.select(index)


func _result(result: Dictionary) -> void:
	receipt_label.text = result.message
	_refresh()


func _row_text(row: Dictionary) -> String:
	if row.is_empty() or row.get("code") == "missing": return "尚未采样，请设置样杯并记录参考点。"
	return "参考 %.2f%% · %.4f V · ADC %d\n出厂换算 %.2f%% · 读数 %s" % [row.truth, row.volts, row.raw_adc, row.factory, "%.2f%%" % row.reading if row.valid else "无效"] if row.raw_adc != null else "信号无效"


func _refresh() -> void:
	if tabs == null: return
	var state: Dictionary = controller.farm.learning
	var lab: Dictionary = state.lab
	var task: Dictionary = state.fault
	var config := Catalog.config()
	pause_button.text = "继续 [空格]" if controller.simulation.clock.paused else "暂停 [空格]"
	status_label.text = "实验：%s　故障：%s" % ["已同步完成" if not state.experiment.is_empty() else "待完成", {"idle": "待开始", "observe": "待观察", "diagnose": "待诊断", "repair": "待真实恢复", "complete": "已验证完成"}[task.stage]]
	CTheme.status(status_label, "running" if task.stage == "complete" else ("warning" if task.stage in ["observe", "diagnose", "repair"] else "stopped"))
	var lines := PackedStringArray(["当前样杯（独立于农场）", _row_text(controller.current()), ""])
	for index in range(lab.points.size()): lines.append("参考 %s\n%s\n" % ["A" if index == 0 else "B", _row_text(lab.points[index])])
	if not lab.verification.is_empty():
		var row: Dictionary = lab.verification
		lines.append("中点复核\n%s\n未校准误差 %+.3f 个百分点\n校准后误差 %s\n系数 %.5f / %+.5f\n%s" % [_row_text(row), float(row.factory) - float(row.truth), "%+.3f 个百分点" % (float(row.reading) - float(row.truth)) if row.valid else "无效", row.slope, row.offset, "复核达标" if Controller.verified(lab.points, row) else "复核未达标"])
	lines.append("\n容差 ≤%.2f 个百分点，改善 ≥%.2f 个百分点。\n已有农场校准任务：%s" % [config.verification_tolerance, config.improvement_min, "完成" if not state.experiment.is_empty() else "未同步"])
	experiment_label.text = "\n".join(lines)
	apply_button.disabled = not Controller.verified(lab.points, lab.verification)
	calibrate_button.disabled = not Controller.solve(lab.points).ok
	start_button.disabled = state.experiment.is_empty() or task.stage != "idle"
	observe_button.disabled = task.stage != "observe"
	diagnose_button.disabled = task.stage != "diagnose"
	verify_button.disabled = task.stage != "repair"
	cancel_button.disabled = task.stage not in ["observe", "diagnose", "repair"]
	var measured := controller.simulation.sensor.current(controller.simulation.clock.total_minutes)
	var details := PackedStringArray([config.signal_fault.title, "", controller.hint(), "", "当前真实系统", "探头：" + Sensor.REASONS[measured.code], "自动控制：" + controller.farm.automation.detail,
		"累计出水 %.3f L · 用电 %.3f Wh" % [controller.farm.engineering.delivered_l, controller.farm.engineering.used_wh]])
	for key in ["baseline", "observed", "resume", "repair"]:
		if not task[key].is_empty(): details.append("\n%s：采样 #%d · 游戏分钟 %d" % [{"baseline": "故障前正常状态", "observed": "已记录停泵观察", "resume": "恢复有效测量检查点", "repair": "实际自动出水证据"}[key], task[key].serial, task[key].minute])
	task_label.text = "\n".join(details)
