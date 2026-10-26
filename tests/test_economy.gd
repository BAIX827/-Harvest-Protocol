extends SceneTree
## Reconcile every balance and play through crop revenue funding another purchase.

const Farm = preload("res://scripts/simulation/farm_state.gd")
const Economy = preload("res://scripts/simulation/economy_model.gd")
const Simulation = preload("res://scripts/simulation/farm_simulation.gd")
const Tools = preload("res://scripts/world/tool_controller.gd")
const Crops = preload("res://scripts/simulation/crop_model.gd")

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("ECONOMY TEST FAILED: " + message)


func _snapshot(farm: Farm) -> String:
	return JSON.stringify({"cash": farm.cash, "seeds": farm.seed_stock, "produce": farm.produce_stock,
		"parts": farm.parts_stock, "water": farm.watering_charges, "ledger": farm.ledger, "next_id": farm.next_transaction_id})


func _balanced(farm: Farm) -> bool:
	var running: int = 0
	var expected_id: int = 1
	for entry in farm.ledger:
		running += int(entry.amount)
		if int(entry.id) != expected_id or int(entry.balance) != running:
			return false
		expected_id += 1
	return running == farm.cash and expected_id == farm.next_transaction_id and not farm.trade_in_progress


func _reject(model: Economy, action: Callable, code: String) -> void:
	var before := _snapshot(model.farm)
	var result: Dictionary = action.call()
	_expect(not result.ok and result.code == code, "Rejected transaction explains its reason: " + code)
	_expect(_snapshot(model.farm) == before, "Rejected transaction preserves cash, every inventory and the ledger: " + code)


func _run() -> void:
	_test_orders_and_balance()
	_test_rejections_and_refill()
	_test_reentrancy()
	await _test_live_market()
	if failures == 0:
		print("FIELDWORKS_ECONOMY_TESTS_OK ", checks, " checks")
	else:
		print("FIELDWORKS_ECONOMY_TESTS_FAILED ", failures, "/", checks)
	quit(0 if failures == 0 else 1)


func _test_orders_and_balance() -> void:
	var farm := Farm.new()
	var simulation := Simulation.new(farm)
	var model := Economy.new(farm, simulation.clock)
	_expect(farm.cash == 600 and _balanced(farm) and model.totals().sales == 0, "Opening funds reconcile without becoming sales income.")
	for id in Farm.SEED_ORDER:
		var before_cash := farm.cash
		var before_stock: int = farm.seed_stock[id]
		var result := model.buy_seeds(id, 5)
		_expect(result.ok and farm.cash == before_cash - int(model.settings.crops[id].seed_price) * 5 and farm.seed_stock[id] == before_stock + 5, "A seed order charges once and delivers its full quantity: " + id)
	var tools := Tools.new(farm, model)
	tools.select_tool(Tools.Tool.HOE)
	tools.use(Vector2i(7, 12), Vector2(7.5, 12.5))
	tools.select_seed("lettuce")
	var paid_cash := farm.cash
	var paid_ledger := farm.ledger.size()
	tools.use(Vector2i(7, 12), Vector2(7.5, 12.5))
	_expect(farm.cash == paid_cash and farm.ledger.size() == paid_ledger and farm.seed_stock.lettuce == 16, "Sowing consumes a purchased seed without charging its price again.")
	# Unit fixtures isolate cash settlement; the live scenario below grows real produce.
	farm.produce_stock = {"lettuce": 3, "carrot": 2, "tomato": 1}
	_expect(model.sell_produce("lettuce", 1).ok and farm.produce_stock.lettuce == 2 and farm.cash == 468, "A partial sale deducts only the sold quantity.")
	_expect(model.sell_all().ok and farm.cash == 610 and model.sale_value() == 0, "A mixed basket settles all items exactly once.")
	var totals := model.totals()
	_expect(totals.sales == 160 and totals.seed_purchase == 150 and totals.net == 10 and farm.cash == int(model.settings.starting_cash) + int(totals.net), "Cash flow and grouped totals reconcile to actual funds.")
	_expect(_balanced(farm), "Every intermediate ledger balance and transaction ID reconciles.")
	_reject(model, model.sell_all, "empty_stock")
	_reject(model, model.sell_produce.bind("lettuce", 1), "insufficient_stock")
	simulation.advance(0.5)
	model.buy_seeds("lettuce", 1)
	_expect(farm.ledger[-1].minute == simulation.clock.total_minutes, "Transactions use the shared game clock.")


func _test_rejections_and_refill() -> void:
	var farm := Farm.new()
	var model := Economy.new(farm)
	for quantity in [0, -1, 1.5, "2", true, 100]:
		_reject(model, model.buy_seeds.bind("lettuce", quantity), "invalid_quantity")
	_reject(model, model.buy_seeds.bind("unknown", 1), "unknown_item")
	_reject(model, model.sell_produce.bind("lettuce", 0), "invalid_quantity")
	model.buy_seeds("lettuce", 99)
	model.buy_seeds("lettuce", 1)
	_expect(farm.cash == 0 and _balanced(farm), "Valid purchases may spend exactly the remaining balance.")
	_reject(model, model.buy_seeds.bind("tomato", 1), "insufficient_cash")
	farm.watering_charges = 0
	_reject(model, model.refill_can, "insufficient_cash")
	_reject(model, model.charge_cost.bind("energy", 1, "测试能源费"), "insufficient_cash")
	_reject(model, model.charge_cost.bind("unknown", 1, "无效类别"), "invalid_cost")
	var supplied := Farm.new()
	var operating := Economy.new(supplied)
	supplied.watering_charges = 0
	var observed: Array = []
	var observer := func() -> void: observed.append({"cash": supplied.cash, "water": supplied.watering_charges, "balance": supplied.ledger[-1].balance})
	supplied.economy_changed.connect(observer)
	_expect(operating.refill_can().ok and supplied.cash == 598 and supplied.watering_charges == 8, "Refill atomically charges the fee and fills the can.")
	_expect(observed.size() == 1 and observed[0].cash == 598 and observed[0].water == 8 and observed[0].balance == 598, "Observers never see a paid but still empty water can.")
	_reject(operating, operating.refill_can, "can_full")
	_expect(operating.totals().water == 2 and _balanced(supplied), "Actual refill cost appears in the water category and ledger.")
	supplied.economy_changed.disconnect(observer)


func _test_reentrancy() -> void:
	var farm := Farm.new()
	var model := Economy.new(farm)
	var callbacks: Array = []
	var callback := func() -> void: callbacks.append(model.buy_seeds("lettuce", 1))
	farm.economy_changed.connect(callback)
	model.buy_seeds("lettuce", 1)
	_expect(callbacks.size() == 1 and callbacks[0].code == "busy" and farm.cash == 594 and farm.seed_stock.lettuce == 13, "A notification callback cannot reenter and duplicate a transaction.")
	_expect(farm.ledger.size() == 2 and _balanced(farm), "Rejected reentrancy consumes no ledger ID or funds.")
	var attempts: Array = []
	var failure_callback := func(result: Dictionary) -> void:
		if not result.ok:
			attempts.append(model.sell_all())
	model.transaction_completed.connect(failure_callback)
	model.sell_all()
	_expect(attempts.size() == 1 and attempts[0].code == "busy" and _balanced(farm), "Failure notification callbacks cannot recurse into more failed trades.")
	model.transaction_completed.disconnect(failure_callback)
	farm.economy_changed.disconnect(callback)


func _key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _tap(code: Key) -> void:
	_key(code, true)
	_key(code, false)
	await process_frame


func _click(point: Vector2) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event, true)
	await process_frame


func _button(control: Control) -> void:
	await _click(control.get_global_transform_with_canvas() * (control.size / 2.0))


func _cell(view: Control, point: Vector2i) -> void:
	await _click(view.get_global_transform_with_canvas() * view.cell_center(point))


func _test_live_market() -> void:
	var app := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(app)
	var view: Control = app.farm_view
	view.simulation.clock.set_paused(true)
	await process_frame
	await process_frame
	await _tap(KEY_B)
	var market: Control = app.market_panel
	_expect(market.visible and view.simulation.clock.paused and not view.interaction_enabled, "B opens the modal market and pauses the farm.")
	_expect(market.sell_all_button.disabled, "An empty farm cannot submit a sale from the market.")
	var position_before: Vector2 = view.player.position
	var selection_before: Vector2i = view.selected_cell
	_key(KEY_W, true)
	await create_timer(0.1).timeout
	_key(KEY_W, false)
	await _cell(view, Vector2i(1, 20))
	_expect(view.player.position == position_before and view.selected_cell == selection_before, "The open modal blocks movement and map click-through.")
	await _button(market.buy_five.lettuce)
	_expect(view.farm.cash == 570 and view.farm.seed_stock.lettuce == 17 and app._cash_label.text.contains("570") and app.tool_bar.seed_buttons.lettuce.text.contains("×17"), "One market click charges once and updates both farm displays.")
	await _tap(KEY_ESCAPE)
	_expect(not market.visible and view.simulation.clock.paused and view.interaction_enabled, "Closing the market restores a previously paused farm.")
	view.player.position = Vector2(8.5, 12.5)
	var points := [Vector2i(7, 11), Vector2i(8, 11), Vector2i(9, 11), Vector2i(7, 12), Vector2i(9, 12)]
	for point in points:
		await _button(app.tool_bar.tool_buttons[Tools.Tool.HOE])
		await _cell(view, point)
		await _button(app.tool_bar.seed_buttons.lettuce)
		await _cell(view, point)
		await _button(app.tool_bar.tool_buttons[Tools.Tool.WATER])
		await _cell(view, point)
	_expect(view.farm.cash == 570 and view.farm.seed_stock.lettuce == 12, "Planting the five purchased seeds does not charge again.")
	await _button(app.time_bar.speed_buttons[12])
	var native: bool = DisplayServer.get_name() != "headless"
	var started := Time.get_ticks_msec()
	var iterations: int = 0
	while not _ready(view.farm, points) and iterations < 700:
		if native:
			if Time.get_ticks_msec() - started > 30000: break
			await create_timer(0.03).timeout
		else:
			view.simulation.advance(0.1)
		iterations += 1
	_expect(_ready(view.farm, points), "Purchased seeds mature through the normal simulation.")
	await _button(app.tool_bar.tool_buttons[Tools.Tool.HARVEST])
	for point in points:
		await _cell(view, point)
	_expect(view.farm.produce_stock.lettuce == 5 and view.farm.cash == 570, "Harvest creates inventory, not automatic sales income.")
	await _button(app._market_button)
	_expect(market.visible and view.simulation.clock.paused and market.sell_all_button.text.contains("90"), "The market previews the value of the actual harvest.")
	await _button(market.sell_all_button)
	_expect(view.farm.cash == 660 and view.farm.produce_stock.lettuce == 0 and market.balance_label.text.contains("660"), "Selling the full harvest credits its exact value.")
	var ledger_size: int = view.farm.ledger.size()
	await _button(market.sell_all_button)
	_expect(view.farm.cash == 660 and view.farm.ledger.size() == ledger_size, "Repeated empty-sale clicks do not generate money or ledger entries.")
	await _button(market.buy_five.lettuce)
	_expect(view.farm.cash == 630 and view.farm.seed_stock.lettuce == 17 and _balanced(view.farm), "Harvest proceeds fund the next purchase with a reconciled balance.")
	_expect(market.summary_label.text.contains("90") and market.summary_label.text.contains("60"), "Displayed sales and expenses match the completed farming loop.")
	for argument in OS.get_cmdline_user_args():
		if native and argument.begins_with("--capture-dir="):
			await _capture_market(app, argument.trim_prefix("--capture-dir="))
	for _index in range(35):
		view.economy.buy_seeds("lettuce", 1)
	_expect(not market._older.disabled, "The ledger can page through more than one page of transactions.")
	await _button(market._older)
	_expect(market._page == 1 and not market._newer.disabled, "Older ledger records remain accessible.")
	await _tap(KEY_B)
	_expect(not market.visible and not view.simulation.clock.paused and view.interaction_enabled and view.simulation.clock.speed == 12, "Closing restores a previously running farm and its speed.")
	_expect(_balanced(view.farm), "The full live trade sequence leaves every ledger balance reconciled.")
	app.queue_free()
	await process_frame


func _ready(farm: Farm, points: Array) -> bool:
	for point in points:
		if not Crops.is_mature(farm.plot_at(point).crop): return false
	return true


func _capture_market(app: Control, directory: String) -> void:
	for window_size in [Vector2i(1440, 900), Vector2i(1152, 720)]:
		root.size = window_size
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var path := directory.path_join("step-06-market-%dx%d.png" % [window_size.x, window_size.y])
		_expect(root.get_texture().get_image().save_png(path) == OK, "Market capture saved: " + path)
		print("FIELDWORKS_ECONOMY_CAPTURE_OK ", path)
