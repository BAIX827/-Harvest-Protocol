extends Control
## GraphEdit connections write the actual controller, never a decorative copy.

signal opened
signal closed
const Controller = preload("res://scripts/engineering/automation_controller.gd")
const Catalog = preload("res://scripts/engineering/automation_catalog.gd")
const Modules = preload("res://scripts/engineering/module_catalog.gd")
const Chart = preload("res://scripts/ui/history_chart.gd")
var controller: Controller
var economy: RefCounted
var _frame: Panel
var graph: GraphEdit
var nodes: Dictionary = {}
var node_labels: Dictionary = {}
var start_input: SpinBox
var stop_input: SpinBox
var buy_button: Button
var install_button: Button
var remove_button: Button
var mode_button: Button
var apply_button: Button
var pause_button: Button
var speed_button: Button
var connect_button: Button
var break_button: Button
var status_label: Label
var receipt_label: Label
var log_label: RichTextLabel
var chart: Chart


func setup(shared_controller: Controller, shared_economy: RefCounted) -> void:
	controller = shared_controller
	economy = shared_economy
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	for signal_name in ["automation_changed", "engineering_changed", "sensor_changed", "economy_changed"]:
		economy.farm.connect(signal_name, _refresh)
	economy.clock.controls_changed.connect(_refresh)
	visible = false


func _ready() -> void:
	resized.connect(_layout)
	_layout()


func _layout() -> void:
	_frame.size = Vector2(minf(1380, size.x - 48), minf(930, size.y - 48))
	_frame.position = ((size - _frame.size) / 2).floor()


func open_panel() -> void:
	if visible: return
	start_input.value = economy.farm.automation.start
	stop_input.value = economy.farm.automation.stop
	for id in nodes:
		var point: Array = economy.farm.automation.positions[id]
		nodes[id].position_offset = Vector2(point[0], point[1])
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


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.04, 0.05, 0.85)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	_frame = Panel.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("1a2a33")
	style.set_border_width_all(1)
	style.border_color = Color("586b71")
	_frame.add_theme_stylebox_override("panel", style)
	add_child(_frame)
	var column := VBoxContainer.new()
	_frame.add_child(column)
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.offset_left = 24
	column.offset_top = 20
	column.offset_right = -24
	column.offset_bottom = -20
	column.add_theme_constant_override("separation", 8)
	var header := HBoxContainer.new()
	column.add_child(header)
	var title := _label("自动灌溉 · 双阈值控制", 25)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	header.add_child(_button("返回农场 [T / Esc]", close_panel))
	column.add_child(_paragraph("拖动端口连接：探头 → 判断 → 水泵；可从输入端拆线。节点拖动位置会保存。自动模式只用有效读数，保护停机优先。"))
	var hardware := HBoxContainer.new()
	column.add_child(hardware)
	buy_button = _button("采购控制器", func() -> void: _result(economy.buy_modules({"controller_basic": 1})))
	install_button = _button("安装库存", func() -> void: _result(controller.install()))
	remove_button = _button("拆回库存", func() -> void: _result(controller.remove()))
	mode_button = _button("", func() -> void: _result(controller.set_mode("auto" if economy.farm.automation.mode == "manual" else "manual")))
	for button in [buy_button, install_button, remove_button, mode_button]: hardware.add_child(button)
	var rules := HBoxContainer.new()
	column.add_child(rules)
	rules.add_child(_label("启动 <"))
	start_input = SpinBox.new()
	start_input.max_value = 60
	start_input.step = 0.1
	start_input.custom_minimum_size.x = 110
	rules.add_child(start_input)
	rules.add_child(_label("%　停止 ≥"))
	stop_input = SpinBox.new()
	stop_input.max_value = 60
	stop_input.step = 0.1
	stop_input.custom_minimum_size.x = 110
	rules.add_child(stop_input)
	rules.add_child(_label("%"))
	apply_button = _button("应用阈值", func() -> void: _result(controller.set_thresholds(start_input.value, stop_input.value)))
	rules.add_child(apply_button)
	pause_button = _button("", func() -> void: economy.clock.toggle_paused())
	speed_button = _button("12× 继续", func() -> void:
		economy.clock.set_speed(12)
		economy.clock.set_paused(false))
	rules.add_child(pause_button)
	rules.add_child(speed_button)
	graph = GraphEdit.new()
	graph.custom_minimum_size.y = 210
	graph.size_flags_vertical = Control.SIZE_EXPAND_FILL
	graph.right_disconnects = true
	graph.add_valid_connection_type(0, 0)
	graph.add_valid_connection_type(1, 1)
	graph.connection_request.connect(func(from: StringName, fp: int, to: StringName, tp: int) -> void: _result(controller.set_connection(str(from), fp, str(to), tp, true)))
	graph.disconnection_request.connect(func(from: StringName, fp: int, to: StringName, tp: int) -> void: _result(controller.set_connection(str(from), fp, str(to), tp, false)))
	column.add_child(graph)
	for id in ["sensor", "decision", "pump"]:
		var node := GraphNode.new()
		node.name = id
		node.title = {"sensor": "土壤水分探头", "decision": "双阈值判断", "pump": "灌溉水泵"}[id]
		node.custom_minimum_size.x = 230
		var label := _label("", 16)
		label.custom_minimum_size = Vector2(210, 70)
		node.add_child(label)
		node.set_slot(0, id != "sensor", 0 if id == "decision" else 1, Color("a9c18b"), id != "pump", 0 if id == "sensor" else 1, Color("cab889"))
		node.dragged.connect(func(_from: Vector2, to: Vector2) -> void: _result(controller.set_position(id, to)))
		graph.add_child(node)
		nodes[id] = node
		node_labels[id] = label
	var wiring := HBoxContainer.new()
	column.add_child(wiring)
	connect_button = _button("接通两条标准连线", _connect_all)
	break_button = _button("断开判断→泵", func() -> void: _result(controller.set_connection("decision", 0, "pump", 0, false)))
	wiring.add_child(connect_button)
	wiring.add_child(break_button)
	status_label = _paragraph("")
	column.add_child(status_label)
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 20)
	column.add_child(bottom)
	chart = Chart.new()
	chart.custom_minimum_size = Vector2(560, 190)
	chart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(chart)
	log_label = RichTextLabel.new()
	log_label.custom_minimum_size = Vector2(620, 190)
	log_label.add_theme_font_size_override("normal_font_size", 16)
	bottom.add_child(log_label)
	receipt_label = _paragraph("保持当前时间设置，空格暂停；切换模式先停泵。修复故障后，中间区间保持停泵，低于启动值才重新开泵。")
	column.add_child(receipt_label)


func _connect_all() -> void:
	for edge in Catalog.EDGES:
		var pair: PackedStringArray = edge.split(">")
		if edge not in economy.farm.automation.edges: controller.set_connection(pair[0], 0, pair[1], 0, true)
	_result({"message": "标准测量链已接通；也可拖动端口手动连接。"})


func _result(result: Dictionary) -> void:
	receipt_label.text = result.message
	_refresh()


func _refresh() -> void:
	if graph == null: return
	var state: Dictionary = economy.farm.automation
	var price := int(Modules.definition("controller_basic").price)
	buy_button.text = "采购控制器 · %d币（库存%d）" % [price, economy.farm.parts_stock.get("controller_basic", 0)]
	buy_button.disabled = economy.farm.cash < price or int(economy.farm.parts_stock.get("controller_basic", 0)) >= 1000
	install_button.disabled = state.installed or int(economy.farm.parts_stock.get("controller_basic", 0)) < 1
	remove_button.disabled = not state.installed
	mode_button.text = "切换手动（当前自动）" if state.mode == "auto" else "切换自动（当前手动）"
	mode_button.disabled = not state.installed
	pause_button.text = "继续 [空格]" if economy.clock.paused else "暂停 [空格]"
	graph.clear_connections()
	for edge in state.edges:
		var pair: PackedStringArray = edge.split(">")
		graph.connect_node(pair[0], 0, pair[1], 0)
	var measured := controller.sensor.control_reading(economy.clock.total_minutes)
	node_labels.sensor.text = "有效读数 %.2f%%\n地块 (%d,%d)" % [measured.value, controller.sensor.point().x + 1, controller.sensor.point().y + 1] if measured.valid else "无效测量\n" + measured.reason
	node_labels.decision.text = "< %.1f%% 启动\n≥ %.1f%% 停止\n中间保持前态" % [state.start, state.stop]
	var status := controller.network.status()
	node_labels.pump.text = "%s\n水 %.1f L / 电 %.1f Wh" % ["实际供水" if status.running and not economy.clock.paused else "当前未出水", economy.farm.engineering.water_l, economy.farm.engineering.energy_wh]
	status_label.text = "%s · %s · %s\n水泵：%s" % [Chart.stamp(economy.clock.total_minutes), "自动" if state.mode == "auto" else "手动", state.detail, status.reason]
	chart.set_records(economy.farm.sensor.history)
	var lines := PackedStringArray(["运行日志 · 最近 %d / 120 次状态 / 参数事件" % state.logs.size()])
	for index in range(state.logs.size() - 1, -1, -1):
		var row: Dictionary = state.logs[index]
		lines.append("#%d %s · %s\n读数 %s · 阈值 %.1f / %.1f · %s" % [row.id, Chart.stamp(int(row.minute)), row.detail, "%.2f%%" % row.value if row.value != null else "无效/无值", row.start, row.stop, "开泵指令" if row.output else "停泵指令"])
	log_label.text = "\n".join(lines)
