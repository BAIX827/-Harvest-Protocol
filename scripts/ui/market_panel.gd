extends Control
## A modal market reads the same inventory as the farm and restores pause on close.

signal opened
signal closed
signal comparison_requested

const Economy = preload("res://scripts/simulation/economy_model.gd")
const Clock = preload("res://scripts/simulation/simulation_clock.gd")
const PAGE_SIZE: int = 30

var economy: Economy
var clock: Clock
var buy_one: Dictionary = {}
var buy_five: Dictionary = {}
var sell_one: Dictionary = {}
var sell_type: Dictionary = {}
var sell_all_button: Button
var comparison_button: Button
var close_button: Button
var receipt_label: Label
var balance_label: Label
var summary_label: Label
var _seed_labels: Dictionary = {}
var _produce_labels: Dictionary = {}
var _frame: PanelContainer
var _ledger_grid: GridContainer
var _newer: Button
var _older: Button
var _page_label: Label
var _page: int = 0
var _previous_pause: bool = false


func setup(shared_economy: Economy, shared_clock: Clock) -> void:
	economy = shared_economy
	clock = shared_clock
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	economy.farm.supplies_changed.connect(_refresh)
	economy.farm.economy_changed.connect(_refresh)
	economy.transaction_completed.connect(_on_transaction)
	visible = false


func _ready() -> void:
	resized.connect(_layout_frame)
	_layout_frame()


func open_market() -> void:
	if visible:
		return
	_previous_pause = clock.paused
	clock.set_paused(true)
	_page = 0
	show()
	_layout_frame()
	_refresh()
	opened.emit()


func close_market() -> void:
	if not visible:
		return
	hide()
	clock.set_paused(_previous_pause)
	closed.emit()


func _layout_frame() -> void:
	_frame.size = Vector2(minf(1240, size.x - 48), minf(860, size.y - 48))
	_frame.position = ((size - _frame.size) / 2.0).floor()


func _label(value: String, font_size: int = 17, color: Color = Color("e0e7e4")) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _button(value: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = value
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 17)
	button.pressed.connect(callback)
	return button


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.04, 0.05, 0.82)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	_frame = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("1a2a33")
	style.border_color = Color("586b71")
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 24
	style.content_margin_right = 24
	style.content_margin_top = 20
	style.content_margin_bottom = 20
	_frame.add_theme_stylebox_override("panel", style)
	add_child(_frame)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	_frame.add_child(column)
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 16)
	column.add_child(heading)
	var title := _label("集市与账本", 26)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	balance_label = _label("", 22, Color("a9c18b"))
	heading.add_child(balance_label)
	comparison_button = _button("经营对照 [H]", func() -> void: comparison_requested.emit())
	heading.add_child(comparison_button)
	close_button = _button("返回农场  [B / Esc]", close_market)
	heading.add_child(close_button)
	summary_label = _label("")
	summary_label.tooltip_text = "初始资金不计入销售收入。种子在购买时记支出，播种只消耗库存，不再次扣款。"
	column.add_child(summary_label)
	var grid := GridContainer.new()
	grid.columns = 7
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	column.add_child(grid)
	for header in ["作物", "种子库存 / 进价", "购买 1 份", "购买 5 份", "收成库存 / 售价", "出售 1 份", "出售该类全部"]:
		grid.add_child(_label(header, 16, Color("9fafaf")))
	for id in economy.farm.SEED_ORDER:
		var name_label := _label(economy.farm.SEED_NAMES[id], 19)
		name_label.custom_minimum_size.x = 82
		grid.add_child(name_label)
		var seed_label := _label("")
		seed_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(seed_label)
		_seed_labels[id] = seed_label
		var one := _button("买 1", _buy.bind(id, 1))
		grid.add_child(one)
		buy_one[id] = one
		var five := _button("买 5", _buy.bind(id, 5))
		grid.add_child(five)
		buy_five[id] = five
		var produce_label := _label("")
		produce_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(produce_label)
		_produce_labels[id] = produce_label
		var sale_one := _button("卖 1", _sell.bind(id, false))
		grid.add_child(sale_one)
		sell_one[id] = sale_one
		var sale_type := _button("卖全部", _sell.bind(id, true))
		grid.add_child(sale_type)
		sell_type[id] = sale_type
	column.add_child(HSeparator.new())
	var trade_row := HBoxContainer.new()
	trade_row.add_theme_constant_override("separation", 20)
	column.add_child(trade_row)
	sell_all_button = _button("", func() -> void: economy.sell_all())
	trade_row.add_child(sell_all_button)
	receipt_label = _label("选择买入或出售，结算明细会显示在这里。")
	receipt_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	receipt_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	trade_row.add_child(receipt_label)
	var ledger_heading := HBoxContainer.new()
	ledger_heading.add_theme_constant_override("separation", 10)
	column.add_child(ledger_heading)
	var ledger_title := _label("资金账 · 打开集市时暂停自然模拟", 18)
	ledger_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ledger_heading.add_child(ledger_title)
	_newer = _button("较新", _change_page.bind(-1))
	ledger_heading.add_child(_newer)
	_page_label = _label("")
	ledger_heading.add_child(_page_label)
	_older = _button("较早", _change_page.bind(1))
	ledger_heading.add_child(_older)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_ledger_grid = GridContainer.new()
	_ledger_grid.columns = 4
	_ledger_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ledger_grid.add_theme_constant_override("h_separation", 18)
	_ledger_grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(_ledger_grid)


func _buy(id: String, amount: int) -> void:
	economy.buy_seeds(id, amount)


func _sell(id: String, all_of_type: bool) -> void:
	economy.sell_produce(id, int(economy.farm.produce_stock[id]) if all_of_type else 1)


func _change_page(direction: int) -> void:
	_page = maxi(0, _page + direction)
	_refresh_ledger()


func _refresh() -> void:
	if not visible:
		return
	balance_label.text = "余额 %d 币" % economy.farm.cash
	var totals := economy.totals()
	summary_label.text = "累计销售 %d 币　累计支出 %d 币　净现金流 %s%d 币\n种子 %d · 补水 %d · 电费 %d · 设备 %d · 退款 %d · 应急 %d 币" % [totals.sales, totals.expenses, "+" if totals.net >= 0 else "", totals.net, totals.seed_purchase, totals.water, totals.energy, totals.equipment, totals.refunds, totals.recovery]
	for id in economy.farm.SEED_ORDER:
		var prices: Dictionary = economy.settings.crops[id]
		_seed_labels[id].text = "持有 %d 份\n%d 币 / 份" % [int(economy.farm.seed_stock[id]), int(prices.seed_price)]
		_produce_labels[id].text = "持有 %d 份\n%d 币 / 份" % [int(economy.farm.produce_stock[id]), int(prices.produce_price)]
		buy_one[id].disabled = economy.farm.cash < int(prices.seed_price) or int(economy.farm.seed_stock[id]) >= Economy.MAX_STOCK
		buy_five[id].disabled = economy.farm.cash < int(prices.seed_price) * 5 or int(economy.farm.seed_stock[id]) + 5 > Economy.MAX_STOCK
		buy_one[id].tooltip_text = "购买 1 份，共 %d 币" % int(prices.seed_price)
		buy_five[id].tooltip_text = "购买 5 份，共 %d 币" % (int(prices.seed_price) * 5)
		sell_one[id].disabled = int(economy.farm.produce_stock[id]) <= 0
		sell_type[id].disabled = int(economy.farm.produce_stock[id]) <= 0
	var estimate := economy.sale_value()
	sell_all_button.disabled = estimate <= 0
	sell_all_button.text = "出售所有收成 · +%d 币" % estimate if estimate > 0 else "暂无可出售收成"
	_refresh_ledger()


func _refresh_ledger() -> void:
	for child in _ledger_grid.get_children():
		_ledger_grid.remove_child(child)
		child.queue_free()
	var total: int = economy.farm.ledger.size()
	var pages := maxi(1, ceili(float(total) / PAGE_SIZE))
	_page = mini(_page, pages - 1)
	_newer.disabled = _page == 0
	_older.disabled = _page >= pages - 1
	_page_label.text = "%d / %d" % [_page + 1, pages]
	for title in ["时间", "事项", "收支", "余额"]:
		_ledger_grid.add_child(_label(title, 16, Color("9fafaf")))
	for offset in range(_page * PAGE_SIZE, mini((_page + 1) * PAGE_SIZE, total)):
		var entry: Dictionary = economy.farm.ledger[total - 1 - offset]
		var minute := int(entry.minute)
		var stamp := "初始" if entry.category == "opening" else "第%d天 %02d:%02d" % [minute / 1440 + 1, minute % 1440 / 60, minute % 60]
		var time_label := _label(stamp, 16)
		time_label.custom_minimum_size.x = 150
		_ledger_grid.add_child(time_label)
		var text := _label("#%d  %s" % [entry.id, entry.description], 16)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var details := PackedStringArray()
		for item in entry.items:
			details.append("%s ×%d，单价 %d 币" % [item.name, item.quantity, item.unit_price])
		text.tooltip_text = "；".join(details)
		_ledger_grid.add_child(text)
		_ledger_grid.add_child(_label("%s%d" % ["+" if entry.amount >= 0 else "", entry.amount], 16, Color("a9c18b") if entry.amount >= 0 else Color("d5a48d")))
		_ledger_grid.add_child(_label("%d 币" % entry.balance, 16))


func _on_transaction(result: Dictionary) -> void:
	if not visible:
		return
	_page = 0
	var details := PackedStringArray()
	for item in result.get("items", []):
		details.append("%s ×%d" % [item.name, item.quantity])
	receipt_label.text = result.message + ("\n" + "、".join(details) if not details.is_empty() else "")
	receipt_label.add_theme_color_override("font_color", Color("a9c18b") if result.ok else Color("d5a48d"))
	_refresh()
