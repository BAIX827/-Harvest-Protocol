extends Control
## A live route and measured accounting, without running actions on the player's behalf.

signal opened
signal closed
signal navigation_requested(destination: String)
const Controller = preload("res://scripts/progression/tutorial_controller.gd")
const Catalog = preload("res://scripts/engineering/module_catalog.gd")
var controller: Controller
var _frame: Panel
var tabs: TabContainer
var route_label: RichTextLabel
var hint_label: Label
var metrics_label: RichTextLabel
var budget_label: Label
var recovery_label: Label
var receipt_label: Label
var navigate_button: Button
var locate_button: Button
var trial_button: Button
var pause_button: Button
var speed_button: Button
var refund_button: Button
var recovery_button: Button
var module_choice: OptionButton
var quantity_input: SpinBox


func setup(shared_controller: Controller) -> void:
	controller = shared_controller
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	for key in ["journey_changed", "learning_changed", "engineering_changed", "sensor_changed", "automation_changed", "economy_changed", "supplies_changed"]:
		controller.farm.connect(key, _refresh)
	controller.simulation.updated.connect(_refresh)
	controller.simulation.clock.controls_changed.connect(_refresh)
	visible = false


func _ready() -> void:
	resized.connect(_layout)
	_layout()


func _layout() -> void:
	_frame.size = Vector2(minf(1320, size.x - 48), minf(920, size.y - 48))
	_frame.position = ((size - _frame.size) / 2).floor()


func open_panel(tab: int = 0) -> void:
	tabs.current_tab = tab
	show()
	_layout()
	_refresh()
	opened.emit()


func close_panel() -> void:
	if not visible: return
	hide()
	closed.emit()


func _label(value: String, font_size: int = 18) -> Label:
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
	result.add_theme_font_size_override("font_size", 17)
	result.pressed.connect(action)
	return result


func _tab(title: String) -> HBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
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
	var style := StyleBoxFlat.new()
	style.bg_color = Color("1a2a33")
	style.border_color = Color("586b71")
	style.set_border_width_all(1)
	_frame.add_theme_stylebox_override("panel", style)
	add_child(_frame)
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.offset_left = 24
	column.offset_right = -24
	column.offset_top = 20
	column.offset_bottom = -20
	column.add_theme_constant_override("separation", 14)
	_frame.add_child(column)
	var heading := HBoxContainer.new()
	column.add_child(heading)
	var title := _label("试玩路线与经营对照", 26)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	heading.add_child(_button("返回农场 [H / Esc]", close_panel))
	column.add_child(_paragraph("目标根据真实作业、收成、交易、供水和教学证据更新。允许提前完成，所有功能随时可用；阅读或打开面板不会完成任务。"))
	var controls := HBoxContainer.new()
	column.add_child(controls)
	pause_button = _button("", func() -> void: controller.simulation.clock.toggle_paused())
	speed_button = _button("12× 继续", func() -> void:
		controller.simulation.clock.set_speed(12)
		controller.simulation.clock.set_paused(false))
	controls.add_child(pause_button)
	controls.add_child(speed_button)
	for key in ["B", "E", "I", "T", "L"]:
		controls.add_child(_button({"B": "集市 B", "E": "设备 E", "I": "探头 I", "T": "控制 T", "L": "实验 L"}[key], func() -> void: navigation_requested.emit(key)))
	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(tabs)
	var route := _tab("连续试玩")
	route_label = RichTextLabel.new()
	route_label.custom_minimum_size = Vector2(560, 550)
	route_label.add_theme_font_size_override("normal_font_size", 21)
	route.add_child(route_label)
	var actions := VBoxContainer.new()
	actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_theme_constant_override("separation", 16)
	route.add_child(actions)
	hint_label = _paragraph("")
	actions.add_child(hint_label)
	navigate_button = _button("", func() -> void: navigation_requested.emit(str(controller.current().destination)))
	actions.add_child(navigate_button)
	locate_button = _button("定位目标地块并返回农场", func() -> void: navigation_requested.emit("locate"))
	actions.add_child(locate_button)
	trial_button = _button("开始 / 重记自主调整试验", func() -> void: _result(controller.begin_improvement()))
	actions.add_child(trial_button)
	actions.add_child(_paragraph("建议先做一份生菜收成（18 币）、补购一份种子（6 币），再考虑设备。手动开泵需要自己监看；校准、自动阈值和故障日志能帮助解释运行。"))
	actions.add_child(_paragraph("自主调整在完成故障教学后开始。记录起点、亲自改 T 阈值、让新规则实际出水。这验证新规则可运行；是否更合适仍需结合水分、资源和收成判断。"))
	var comparison := _tab("经营对照与周转")
	metrics_label = RichTextLabel.new()
	metrics_label.custom_minimum_size = Vector2(620, 590)
	metrics_label.add_theme_font_size_override("normal_font_size", 19)
	comparison.add_child(metrics_label)
	var operations := VBoxContainer.new()
	operations.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	operations.add_theme_constant_override("separation", 14)
	comparison.add_child(operations)
	budget_label = _paragraph("")
	operations.add_child(budget_label)
	operations.add_child(_paragraph("只退备用库存，原价退款；已装或已铺的零件不能直接退。取回探头 / 控制器或拆管后可退。水电消耗不退款，设备更换按 E 原规则处理。"))
	module_choice = OptionButton.new()
	for id in Catalog.ids():
		module_choice.add_item(Catalog.definition(id).name)
		module_choice.set_item_metadata(module_choice.item_count - 1, id)
	module_choice.item_selected.connect(func(_index: int) -> void: _refresh())
	operations.add_child(module_choice)
	var amount := HBoxContainer.new()
	operations.add_child(amount)
	amount.add_child(_label("退货数量"))
	quantity_input = SpinBox.new()
	quantity_input.min_value = 1
	quantity_input.max_value = 1000
	quantity_input.value = 1
	quantity_input.value_changed.connect(func(_value: float) -> void: _refresh())
	amount.add_child(quantity_input)
	refund_button = _button("", func() -> void: _result(controller.economy.return_module(str(module_choice.get_item_metadata(module_choice.selected)), int(quantity_input.value))))
	operations.add_child(refund_button)
	recovery_label = _paragraph("")
	operations.add_child(recovery_label)
	recovery_button = _button("领取应急生菜 ×1 + 补水备用金 2 币", func() -> void: _result(controller.economy.recover()))
	operations.add_child(recovery_button)
	operations.add_child(_paragraph("应急领取需无种子、无在田作物、无收成且买不起最低价种子。只在明确点击后记账；持有或种下该种子后不能重复领取。"))
	receipt_label = _paragraph("H 保持实际时间；可用空格暂停后查看经营记录。")
	column.add_child(receipt_label)


func _result(result: Dictionary) -> void:
	receipt_label.text = result.message
	_refresh()


func _refresh() -> void:
	if tabs == null: return
	var farm := controller.farm
	var state: Dictionary = farm.journey
	var lines := PackedStringArray()
	var current := controller.current()
	for row in controller.rows(): lines.append("%s %s\n" % ["✓" if row.done else ("→" if row.id == current.id else "○"), row.title])
	route_label.text = "\n".join(lines)
	hint_label.text = current.title + "\n\n" + controller.hint()
	navigate_button.text = "返回农场继续操作" if current.destination == "farm" else "打开目标面板 [%s]" % current.destination
	navigate_button.disabled = current.id == "complete"
	locate_button.visible = current.id in ["plant", "harvest", "manual", "auto"]
	trial_button.disabled = farm.learning.fault.stage != "complete" or not state.improvement.proof.is_empty()
	pause_button.text = "继续 [空格]" if controller.simulation.clock.paused else "暂停 [空格]"
	var totals := controller.economy.totals()
	var manual: Dictionary = state.manual
	var m: Dictionary = state.modes.manual
	var a: Dictionary = state.modes.auto
	metrics_label.text = "计量起点：第%d天 %02d:%02d\n人工成功作业：翻土 %d / 播种 %d / 浇水 %d / 收获 %d\n水壶补满 %d 次 · 人工入土水量 %.2f L（模型折算）\n\n设备实际用量\n手动：%.2f L / %.2f Wh · 模式观察 %d 分钟\n自动：%.2f L / %.2f Wh · 模式观察 %d 分钟\n导入前未分类：%.2f L / %.2f Wh\n\n经营账（累计）\n收成销售 %d 币 · 种子采购 %d 币\n设备采购 %d 币 · 备用退货 %d 币\n补水费用 %d 币 · 电费 %d 币\n其他费用 %d 币 · 应急周转 %d 币\n净现金流 %s%d 币 · 当前余额 %d 币\n\n人工量按真实水分增量折算；设备量是实际配水。\n观察时长含未出水时间，地块、天气和运行时长可能不同，不能直接据此宣称节水率。\n初始资金不计销售；退款和应急金分别列出。" % [state.since / 1440 + 1, state.since % 1440 / 60, state.since % 60, manual.hoe, manual.sow, manual.water, manual.harvest, manual.refill, state.manual_water_l, m.liters, m.wh, m.minutes, a.liters, a.wh, a.minutes, state.baseline_l, state.baseline_wh, totals.sales, totals.seed_purchase, totals.equipment, totals.refunds, totals.water, totals.energy, totals.maintenance, totals.recovery, "+" if totals.net >= 0 else "", totals.net, farm.cash]
	var budget := controller.budget()
	budget_label.text = "大容量参考套装\n300 L 箱、节能泵、180 Wh 电池、5 管、探头、控制器与满水电，空库存时 493 币。\n\n按已持有模块和资源估算还需 %d 币（设备 %d / 水 %d / 电 %d）。这是采购计划，不自动安装或扣钱。" % [budget.total, budget.equipment, budget.water, budget.energy]
	var id: String = str(module_choice.get_item_metadata(module_choice.selected))
	var stock: int = int(farm.parts_stock.get(id, 0))
	refund_button.text = "库存 %d · 退回 %d 币" % [stock, int(quantity_input.value) * int(Catalog.definition(id).price)]
	refund_button.disabled = stock < int(quantity_input.value)
	recovery_button.disabled = not controller.economy.can_recover()
	recovery_label.text = "符合应急领取条件，可从一份生菜重新经营。" if not recovery_button.disabled else "当前仍有可经营资源，或余额可以买种子；先出售收成、照料在田作物或退回备用模块。"
