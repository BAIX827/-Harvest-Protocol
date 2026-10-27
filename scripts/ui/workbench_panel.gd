extends Control
## Paused editing, live shared inventory, and a clickable underground pipe plan.

signal opened
signal closed

const Controller = preload("res://scripts/engineering/engineering_controller.gd")
const Network = preload("res://scripts/engineering/irrigation_network.gd")
const Catalog = preload("res://scripts/engineering/module_catalog.gd")
const Clock = preload("res://scripts/simulation/simulation_clock.gd")
var engineering: Controller
var clock: Clock
var _previous_pause: bool = false
var _frame: Panel
var choices: Dictionary = {}
var buy_buttons: Dictionary = {}
var install_buttons: Dictionary = {}
var installed_labels: Dictionary = {}
var pipe_buttons: Dictionary = {}
var close_button: Button
var water_button: Button
var energy_button: Button
var switch_button: Button
var power_button: Button
var buy_pipe_button: Button
var receipt_label: Label
var status_label: Label
var resources_label: Label
var balance_label: Label
var plan_label: Label


func setup(controller: Controller, shared_clock: Clock) -> void:
	engineering = controller
	clock = shared_clock
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	engineering.economy.farm.engineering_changed.connect(_refresh)
	engineering.economy.farm.economy_changed.connect(_refresh)
	engineering.economy.farm.supplies_changed.connect(_refresh)
	engineering.action_completed.connect(func(result: Dictionary) -> void: receipt_label.text = result.message)
	clock.controls_changed.connect(_refresh)
	visible = false


func _ready() -> void:
	resized.connect(_layout_frame)
	_layout_frame()


func open_workbench() -> void:
	if visible: return
	_previous_pause = clock.paused
	clock.set_paused(true)
	show()
	_layout_frame()
	_refresh()
	opened.emit()


func close_workbench() -> void:
	if not visible: return
	hide()
	clock.set_paused(_previous_pause)
	closed.emit()


func _layout_frame() -> void:
	_frame.size = Vector2(minf(1280, size.x - 48), minf(900, size.y - 48))
	_frame.position = ((size - _frame.size) / 2.0).floor()


func _label(text_value: String, font_size: int = 17) -> Label:
	var result := Label.new()
	result.text = text_value
	result.add_theme_font_size_override("font_size", font_size)
	return result


func _paragraph(text_value: String) -> Label:
	var result := _label(text_value)
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return result


func _button(text_value: String, callback: Callable) -> Button:
	var result := Button.new()
	result.text = text_value
	result.focus_mode = Control.FOCUS_NONE
	result.add_theme_font_size_override("font_size", 16)
	result.pressed.connect(callback)
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
	for edge in ["left", "right", "top", "bottom"]: style.set("content_margin_" + edge, 24.0)
	_frame.add_theme_stylebox_override("panel", style)
	add_child(_frame)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	_frame.add_child(column)
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.offset_left = 24
	column.offset_top = 24
	column.offset_right = -24
	column.offset_bottom = -24
	var header := HBoxContainer.new()
	column.add_child(header)
	var title := _label("灌溉组装工作台", 26)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	balance_label = _label("", 21)
	header.add_child(balance_label)
	close_button = _button("返回农场  [E / Esc]", close_workbench)
	header.add_child(close_button)
	column.add_child(_paragraph("编辑时暂停模拟；关闭工作台后恢复原速度。先采购并安装三种模块，再连接管路、补水充电并打开手动开关。"))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var body := HBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 32)
	scroll.add_child(body)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.custom_minimum_size.x = 480
	left.add_theme_constant_override("separation", 12)
	body.add_child(left)
	for kind in ["tank", "pump", "power"]:
		installed_labels[kind] = _label("", 18)
		left.add_child(installed_labels[kind])
		var row := HBoxContainer.new()
		left.add_child(row)
		var choice := OptionButton.new()
		choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		choice.add_theme_font_size_override("font_size", 16)
		for id in Catalog.ids(kind):
			choice.add_item(Catalog.definition(id).name)
			choice.set_item_metadata(choice.item_count - 1, id)
		choice.item_selected.connect(func(_index: int) -> void: _refresh())
		choices[kind] = choice
		row.add_child(choice)
		buy_buttons[kind] = _button("采购", _buy.bind(kind))
		row.add_child(buy_buttons[kind])
		install_buttons[kind] = _button("安装库存", _install.bind(kind))
		row.add_child(install_buttons[kind])
	left.add_child(HSeparator.new())
	plan_label = _paragraph("")
	left.add_child(plan_label)
	resources_label = _label("")
	left.add_child(resources_label)
	var refill_row := HBoxContainer.new()
	left.add_child(refill_row)
	water_button = _button("补水", _refill.bind("tank"))
	energy_button = _button("充电", _refill.bind("power"))
	refill_row.add_child(water_button)
	refill_row.add_child(energy_button)
	var switches := HBoxContainer.new()
	left.add_child(switches)
	switch_button = _button("", func() -> void: _result(engineering.set_enabled(not engineering.economy.farm.engineering.enabled)))
	power_button = _button("", func() -> void: _result(engineering.set_power(not engineering.economy.farm.engineering.power_connected)))
	switches.add_child(switch_button)
	switches.add_child(power_button)
	status_label = _paragraph("")
	left.add_child(status_label)
	left.add_child(_paragraph("更换不再收费，旧件退回库存；新水箱与电池为空。缩小容量会丢弃超出部分。传感器与自动控制尚未开放。"))
	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 560
	right.add_theme_constant_override("separation", 10)
	body.add_child(right)
	right.add_child(_label("管路平面 · 上方试验田", 20))
	right.add_child(_paragraph("点击格子铺管，再点拆回。四向连接；地下管路不阻挡角色或耕作。格子坐标与农场相同。"))
	var grid := GridContainer.new()
	grid.columns = 7
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	right.add_child(grid)
	for y in range(Network.SITE.position.y, Network.SITE.end.y):
		for x in range(Network.SITE.position.x, Network.SITE.end.x):
			var point := Vector2i(x, y)
			var button := _button("", _pipe.bind(point))
			button.custom_minimum_size = Vector2(74, 54)
			var compact := StyleBoxFlat.new()
			compact.bg_color = Color("293e47")
			compact.content_margin_left = 4
			compact.content_margin_right = 4
			button.add_theme_stylebox_override("normal", compact)
			button.add_theme_font_size_override("font_size", 14)
			pipe_buttons[point] = button
			grid.add_child(button)
	buy_pipe_button = _button("", func() -> void: _result(engineering.buy("pipe", 5)))
	right.add_child(buy_pipe_button)
	right.add_child(_paragraph("最短示例：泵 (10,7) → 管 (10,8) → (11,8) → (12,8) → 出口 (12,9)。覆盖 (11～13,9～10) 的六块翻土地。"))
	right.add_child(_paragraph("1 L 水按 1 m² 地块、200 mm 等效土层换算为 0.5 个含水量百分点；均分到覆盖区需要水的翻土地。泵实际出水才耗能，缺水或断路不空耗。均为游戏原型参数。"))
	receipt_label = _paragraph("选择模块可以预览价格和性能。采购入库后，点击安装库存。")
	column.add_child(receipt_label)


func _selected(kind: String) -> String:
	return str(choices[kind].get_item_metadata(choices[kind].selected))


func _buy(kind: String) -> void:
	_result(engineering.buy(_selected(kind)))


func _install(kind: String) -> void:
	_result(engineering.install(_selected(kind)))


func _refill(kind: String) -> void:
	_result(engineering.refill(kind))


func _pipe(point: Vector2i) -> void:
	_result(engineering.pipe(point))


func _result(result: Dictionary) -> void:
	receipt_label.text = result.message
	_refresh()


func _refresh() -> void:
	if choices.size() != 3: return
	var farm := engineering.economy.farm
	var state: Dictionary = farm.engineering
	var network := engineering.network
	balance_label.text = "资金 %d 币　" % farm.cash
	var total: int = 0
	for kind in choices:
		var id := _selected(kind)
		var item := Catalog.definition(id)
		total += int(item.price)
		for index in range(choices[kind].item_count):
			var candidate: String = choices[kind].get_item_metadata(index)
			var definition := Catalog.definition(candidate)
			choices[kind].set_item_text(index, "%s · %d币 · 库存%d" % [definition.name, definition.price, farm.parts_stock.get(candidate, 0)])
		var installed := Catalog.definition(state[kind])
		installed_labels[kind].text = "%s：%s" % [{"tank": "水箱", "pump": "水泵", "power": "供电"}[kind], installed.get("name", "未安装")]
		buy_buttons[kind].disabled = farm.cash < int(item.price)
		install_buttons[kind].disabled = int(farm.parts_stock.get(id, 0)) < 1 or state[kind] == id
	var pump := Catalog.definition(_selected("pump"))
	plan_label.text = "所选三件总价 %d 币（另需管段、水和电）\n水箱 %.0f L · 泵 %.0f L/h / %.0f W · 电池 %.0f Wh" % [total, Catalog.definition(_selected("tank")).capacity, pump.flow_l_h, pump.power_w, Catalog.definition(_selected("power")).capacity]
	resources_label.text = "水箱 %.2f / %.0f L　电池 %.2f / %.0f Wh\n累计出水 %.2f L · 用电 %.2f Wh" % [state.water_l, network.capacity("tank"), state.energy_wh, network.capacity("power"), state.delivered_l, state.used_wh]
	water_button.text = "补满水箱 · %d 币" % engineering.refill_fee("tank")
	energy_button.text = "充满电池 · %d 币" % engineering.refill_fee("power")
	water_button.disabled = engineering.refill_fee("tank") == 0 or farm.cash < engineering.refill_fee("tank")
	energy_button.disabled = engineering.refill_fee("power") == 0 or farm.cash < engineering.refill_fee("power")
	switch_button.text = "关闭水泵" if state.enabled else "打开水泵"
	power_button.text = "断开电源" if state.power_connected else "接通电源"
	var status := network.status()
	status_label.text = "%s · %s\n管路%s · %s" % ["运行就绪" if status.running else "停止供水", status.reason, "已连通" if status.connected else "未连通", "编辑中暂停；返回农场后推进" if clock.paused else "随游戏时间推进"]
	buy_pipe_button.text = "采购 5 段管道 · %d 币　（库存 %d 段）" % [int(Catalog.definition("pipe").price) * 5, farm.parts_stock.get("pipe", 0)]
	buy_pipe_button.disabled = farm.cash < int(Catalog.definition("pipe").price) * 5
	for point in pipe_buttons:
		var button: Button = pipe_buttons[point]
		var title: String = {Network.TANK: "水箱", Network.PUMP: "泵", Network.POWER: "电池", Network.OUTLET: "出口"}.get(point, "拆回" if Network.key(point) in state.pipes else "铺管")
		button.text = "(%d,%d)\n%s" % [point.x + 1, point.y + 1, title]
		button.disabled = not Network.can_pipe(point)
		button.add_theme_color_override("font_color", Color("a9c18b") if Network.key(point) in state.pipes else Color("e0e7e4"))
