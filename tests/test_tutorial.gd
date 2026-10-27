extends SceneTree
## Real first-sale route, measured supply, independent change, recovery and saved evidence.

const Codec = preload("res://scripts/persistence/save_codec.gd")
const Tools = preload("res://scripts/world/tool_controller.gd")
var checks: int = 0
var failures: int = 0
var directory: String


func _initialize() -> void:
	_run.call_deferred()


func _expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("TUTORIAL TEST FAILED: " + message)


func _json(value: Variant) -> String:
	return JSON.stringify(value, "", true, true)


func _app(name: String) -> Control:
	var app := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	app.set_meta("save_path", directory.path_join(name + ".json"))
	root.add_child(app)
	app.farm_view.simulation.clock.set_paused(true)
	await process_frame
	await process_frame
	return app


func _tap(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
	await process_frame
	await process_frame


func _button(button: Control) -> void:
	var point := button.get_global_transform_with_canvas() * (button.size / 2)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event, true)
	await process_frame
	await process_frame


func _choose(choice: OptionButton, id: String) -> void:
	for index in range(choice.item_count):
		if str(choice.get_item_metadata(index)) == id:
			choice.select(index)
			choice.item_selected.emit(index)


func _use(view: Control, point: Vector2i, tool: int) -> void:
	view.player.position = Vector2(point) + Vector2.ONE * 0.5
	view.tools.select_tool(tool)
	view.tools.use(point, view.player.position)


func _advance(view: Control, condition: Callable, limit: int = 1000, live: bool = false) -> void:
	view.simulation.clock.set_speed(12)
	view.simulation.clock.set_paused(false)
	var attempts: int = 0
	while not condition.call() and attempts < limit:
		if live and DisplayServer.get_name() != "headless": await create_timer(0.02).timeout
		else: view.simulation.advance(0.05)
		attempts += 1
	view.simulation.clock.set_paused(true)
	_expect(condition.call(), "Real fixed steps reach the requested physical state.")


func _run() -> void:
	directory = "res://tmp/qa/tutorial-%d-%d" % [OS.get_process_id(), Time.get_ticks_msec()]
	DirAccess.make_dir_recursive_absolute(directory)
	_test_measurement()
	await _route()
	await _returns_and_recovery()
	if failures == 0: print("FIELDWORKS_TUTORIAL_TESTS_OK ", checks, " checks")
	else: print("FIELDWORKS_TUTORIAL_TESTS_FAILED ", failures, "/", checks)
	quit(0 if failures == 0 else 1)


func _test_measurement() -> void:
	var View = preload("res://scripts/world/farm_view.gd")
	var a := View.new()
	var b := View.new()
	for view in [a, b]:
		view.economy.buy_modules({"tank_300": 1, "pump_eco": 1, "battery_180": 1, "pipe": 3, "sensor_basic": 1, "controller_basic": 1})
		for id in ["tank_300", "pump_eco", "battery_180"]: view.engineering.install(id)
		for point in [Vector2i(9, 7), Vector2i(10, 7), Vector2i(11, 7)]: view.engineering.pipe(point)
		view.engineering.refill("tank")
		view.engineering.refill("power")
		_use(view, Vector2i(10, 8), Tools.Tool.HOE)
		view.sensor_controller.install()
		view.simulation.automation.install()
		for pair in [["sensor", "decision"], ["decision", "pump"]]: view.simulation.automation.set_connection(pair[0], 0, pair[1], 0, true)
		view.simulation.automation.set_mode("auto")
	a.simulation.clock.set_speed(1)
	b.simulation.clock.set_speed(12)
	for _index in range(360): a.simulation.advance(1.0 / 30)
	for _index in range(144): b.simulation.advance(1.0 / 144)
	_expect(_json(a.farm.journey) == _json(b.farm.journey) and _json(a.farm.engineering) == _json(b.farm.engineering), "Same game time at different speeds and FPS gives identical measured modes and conserved resources.")
	a.simulation.clock.set_paused(true)
	var before := _json(a.farm.journey)
	a.simulation.advance(100)
	_expect(_json(a.farm.journey) == before, "Pause cannot increase work, observation minutes or delivered resources.")
	a.farm.plot_at(Vector2i(7, 12)).moisture = 59.0
	_use(a, Vector2i(7, 12), Tools.Tool.HOE)
	_use(a, Vector2i(7, 12), Tools.Tool.WATER)
	_expect(a.farm.journey.manual_water_l == 2.0 and a.farm.journey.manual.water == 1, "A capped one-point addition records two liters, not the nominal full watering amount.")
	a.free()
	b.free()


func _route() -> void:
	var app := await _app("route")
	var view: Control = app.farm_view
	var guide: Control = app.tutorial_panel
	_expect(view.tutorial.current().id == "plant" and app._guide_label.text.contains("第一块田") and view.tutorial.budget().total == 493, "A fresh game shows the real first objective and an affordable 493 coin plan.")
	await _button(app.tutorial_button)
	_expect(guide.visible and not view.interaction_enabled and view.simulation.clock.paused, "Native H entry opens the route without advancing or pausing on its own.")
	var unchanged := _json(Codec.capture(view))
	await _button(guide.trial_button)
	_expect(guide.trial_button.disabled and _json(Codec.capture(view)) == unchanged, "Independent improvement cannot be awarded before the real fault lesson.")
	await _button(guide.locate_button)
	_expect(not guide.visible and view.selected_cell == Vector2i(7, 12) and view.player.position == Codec.Farm.SPAWN, "Locate selects the target without teleporting or performing work.")
	_use(view, Vector2i(7, 12), Tools.Tool.WATER)
	_expect(view.farm.journey.manual.water == 0, "Rejected watering does not count as work.")
	_use(view, Vector2i(7, 12), Tools.Tool.HOE)
	view.tools.select_seed("lettuce")
	view.tools.use(Vector2i(7, 12), view.player.position)
	_use(view, Vector2i(7, 12), Tools.Tool.WATER)
	_expect(view.farm.journey.manual.hoe == 1 and view.farm.journey.manual.sow == 1 and view.farm.journey.manual.water == 1 and view.farm.journey.manual_water_l == 24, "Successful first-field work and actual 12-point water addition are measured once.")
	_expect(view.tutorial.current().id == "harvest", "A planted and manually watered field advances to real care and harvest.")
	await _advance(view, func() -> bool: return view.simulation.crops.is_mature(view.farm.plot_at(Vector2i(7, 12)).crop), 1800, true)
	_use(view, Vector2i(7, 12), Tools.Tool.HARVEST)
	_expect(view.tutorial.current().id == "sell" and view.farm.journey.manual.harvest == 1, "Only an actual mature harvest reaches the sale objective.")
	await _tap(KEY_H)
	await _button(guide.navigate_button)
	_expect(app.market_panel.visible and not guide.visible, "The current route button navigates to the actual market.")
	await _button(app.market_panel.sell_one.lettuce)
	_expect(view.tutorial.current().id == "restock" and view.farm.cash == 618, "The first normal lettuce sale earns 18 coins.")
	await _button(app.market_panel.buy_one.lettuce)
	_expect(view.tutorial.current().id == "manual" and view.farm.cash == 612, "A real six-coin seed purchase completes the first trading loop.")
	await _button(app.market_panel.comparison_button)
	_expect(guide.visible and guide.tabs.current_tab == 1 and not app.market_panel.visible and view.simulation.clock.paused, "The market links to the measured comparison and restores its previous pause state.")
	await _tap(KEY_ESCAPE)
	_use(view, Vector2i(10, 8), Tools.Tool.HOE)
	await _tap(KEY_E)
	var bench: Control = app.workbench_panel
	for item in [["tank", "tank_300"], ["pump", "pump_eco"], ["power", "battery_180"]]:
		_choose(bench.choices[item[0]], item[1])
		await _button(bench.buy_buttons[item[0]])
		await _button(bench.install_buttons[item[0]])
	await _button(bench.buy_pipe_button)
	for point in [Vector2i(9, 7), Vector2i(10, 7), Vector2i(11, 7)]: await _button(bench.pipe_buttons[point])
	await _button(bench.water_button)
	await _button(bench.energy_button)
	await _button(bench.switch_button)
	await _tap(KEY_ESCAPE)
	await _advance(view, func() -> bool: return view.farm.journey.modes.manual.liters >= 4, 30, true)
	view.engineering.set_enabled(false)
	_expect(view.tutorial.current().id == "experiment" and view.farm.journey.modes.manual.wh > 0, "Manual equipment supply is real and introduces the calibration objective.")
	await _tap(KEY_I)
	await _button(app.sensor_panel.buy_button)
	await _button(app.sensor_panel.install_button)
	await _tap(KEY_L)
	var lab: Control = app.lab_panel
	_choose(lab.soil_choice, "clay")
	await _button(lab.preset_a)
	await _button(lab.point_a_button)
	await _button(lab.preset_b)
	await _button(lab.point_b_button)
	await _button(lab.calibrate_button)
	await _button(lab.apply_button)
	_expect(view.tutorial.current().id == "auto", "Verified lab evidence and explicit field sync advance the route.")
	await _tap(KEY_T)
	var auto: Control = app.automation_panel
	await _button(auto.buy_button)
	await _button(auto.install_button)
	await _button(auto.connect_button)
	await _button(auto.mode_button)
	_expect(view.farm.cash == 119, "First sale and restocking leave 119 coins after the complete 493 coin kit.")
	await _tap(KEY_ESCAPE)
	await _advance(view, func() -> bool: return view.farm.journey.modes.auto.liters > 0, 50, true)
	_expect(view.tutorial.current().id == "fault", "Actual automatic consumption leads to fault observation and logs.")
	await _tap(KEY_L)
	await _button(lab.start_button)
	await _button(lab.observe_button)
	await _button(lab.diagnose_button)
	await _tap(KEY_I)
	await _button(app.sensor_panel.connection_button)
	await _tap(KEY_ESCAPE)
	await _advance(view, func() -> bool: return view.farm.learning.fault.stage == "complete", 50, true)
	_expect(view.tutorial.current().id == "improve", "A real completed fault chain unlocks independent adjustment.")
	await _tap(KEY_H)
	await _button(guide.trial_button)
	_expect(not view.farm.journey.improvement.baseline.is_empty() and view.farm.journey.improvement.proof.is_empty(), "Starting a trial records its origin without marking improvement done.")
	_expect(app._save_game().ok, "A pending trial with no edit is savable.")
	await _button(guide.navigate_button)
	var measured: float = view.simulation.sensor.current(view.simulation.clock.total_minutes).reading
	auto.start_input.value = measured + 1
	auto.stop_input.value = measured + 5
	await _button(auto.apply_button)
	_expect(not view.farm.journey.improvement.change.is_empty() and view.farm.journey.improvement.proof.is_empty(), "Native player-selected thresholds create a new checkpoint, not completion.")
	var checkpoint := _json(Codec.capture(view))
	_expect(app._save_game().ok, "A real changed-rule checkpoint passes disk validation.")
	app._perform_load(false)
	_expect(_json(Codec.capture(view)) == checkpoint, "A changed-rule trial restores exactly and retains its actual start.")
	view.simulation.automation.set_mode("manual")
	_expect(view.farm.journey.improvement.change.is_empty(), "Switching out of auto invalidates an unfinished new-rule checkpoint.")
	view.engineering.set_enabled(true)
	var manual_before: float = view.farm.engineering.delivered_l
	await _advance(view, func() -> bool: return view.farm.engineering.delivered_l > manual_before, 40, true)
	_expect(view.farm.journey.improvement.proof.is_empty(), "Actual manual delivery does not satisfy an independent automatic-rule trial.")
	view.simulation.automation.set_mode("auto")
	measured = view.simulation.sensor.current(view.simulation.clock.total_minutes).reading
	view.simulation.automation.set_thresholds(measured + 1, measured + 5)
	_expect(view.farm.journey.improvement.change.delivered_l == view.farm.engineering.delivered_l, "A fresh automatic checkpoint starts after already consumed manual resources.")
	await _advance(view, func() -> bool: return not view.farm.journey.improvement.proof.is_empty(), 40, true)
	_expect(view.tutorial.current().id == "complete", "All real objectives including new-rule automatic supply complete the route.")
	await _tap(KEY_H)
	_expect(guide.route_label.text.count("✓") == 9 and guide.metrics_label.text.contains("人工入土水量"), "The native route shows nine evidence-backed goals and measured accounting.")
	_expect(app._save_game().ok, "Completed route, accounting and rule proof save together.")
	var snapshot := Codec.capture(view)
	for key in ["water", "minutes", "counter", "proof", "threshold", "origin", "energy_split"]:
		var invalid: Dictionary = snapshot.duplicate(true)
		match key:
			"water": invalid.journey.modes.auto.liters += 1
			"minutes": invalid.journey.modes.manual.minutes += 5
			"counter": invalid.journey.manual.harvest = 10000
			"proof": invalid.journey.improvement.proof.sample = {}
			"threshold": invalid.journey.improvement.change.start = invalid.journey.improvement.baseline.start
			"origin": invalid.journey.baseline_wh = -1
			"energy_split":
				invalid.journey.modes.manual.wh += invalid.journey.modes.auto.wh
				invalid.journey.modes.auto.wh = 0
		if key == "threshold": invalid.journey.improvement.change.stop = invalid.journey.improvement.baseline.stop
		_expect(not Codec.validate(invalid).ok and _json(Codec.capture(view)) == _json(snapshot), "Reject inconsistent saved route evidence before mutation: " + key)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir=") and DisplayServer.get_name() != "headless": await _capture(guide, argument.trim_prefix("--capture-dir="))
	await _tap(KEY_ESCAPE)
	_expect(view.interaction_enabled and view.simulation.clock.paused, "Closing the guide preserves pause and returns farm input.")
	app.queue_free()
	await process_frame


func _returns_and_recovery() -> void:
	var app := await _app("recovery")
	var view: Control = app.farm_view
	var economy: RefCounted = view.economy
	_expect(not economy.recover().ok, "A normally supplied new farm cannot claim emergency resources.")
	economy.buy_modules({"controller_basic": 1, "pipe": 5})
	view.simulation.automation.install()
	var before := _json(Codec.capture(view))
	_expect(not economy.return_module("controller_basic", 1).ok and _json(Codec.capture(view)) == before, "An installed controller cannot be sold as spare inventory.")
	for amount in [0, -1, true, 1.5, "1", 1001]:
		_expect(not economy.return_module("pipe", amount).ok and _json(Codec.capture(view)) == before, "Invalid return quantity preserves the entire farm.")
	await _tap(KEY_H)
	var panel: Control = app.tutorial_panel
	panel.tabs.current_tab = 1
	_choose(panel.module_choice, "pipe")
	panel.quantity_input.value = 5
	await process_frame
	await process_frame
	await _button(panel.refund_button)
	_expect(view.farm.cash == 540 and view.farm.parts_stock.pipe == 0 and economy.totals().refunds == 20 and economy.totals().sales == 0, "Native spare returns refund their exact purchase price without becoming crop sales.")
	_expect(app._save_game().ok, "Net acquired modules, installed ownership and refund ledger reconcile on disk.")
	before = _json(Codec.capture(view))
	_expect(not economy.return_module("pipe", 1).ok and _json(Codec.capture(view)) == before, "An already returned spare cannot be refunded twice.")
	await _tap(KEY_ESCAPE)
	# Extreme but legitimate growth/harvest/sale history, followed by an explicit cost fixture.
	var planted: Array[Vector2i] = []
	for index in range(view.farm.plots.size()):
		var point := Vector2i(index % 24, index / 24)
		if not view.farm.is_arable(point): continue
		var selected: String = ""
		for id in view.farm.SEED_ORDER:
			if int(view.farm.seed_stock[id]) > 0:
				selected = id
				break
		if selected.is_empty(): break
		_use(view, point, Tools.Tool.HOE)
		view.tools.select_seed(selected)
		view.tools.use(point, view.player.position)
		planted.append(point)
	await _advance(view, func() -> bool: return planted.all(func(point: Vector2i) -> bool: return view.simulation.crops.is_mature(view.farm.plot_at(point).crop)), 12000)
	for point in planted: _use(view, point, Tools.Tool.HARVEST)
	economy.sell_all()
	economy.charge_cost("maintenance", view.farm.cash, "极端费用测试夹具")
	_expect(economy.can_recover() and app._save_game().ok, "A reconciled exhausted farm remains savable and eligible for recovery.")
	_expect(view.tutorial.hint().contains("应急种子"), "An exhausted farm receives an actionable recovery hint on the current objective.")
	await _tap(KEY_H)
	panel.tabs.current_tab = 1
	await _button(panel.recovery_button)
	_expect(view.farm.seed_stock.lettuce == 1 and view.farm.cash == 2 and economy.totals().recovery == 2 and panel.recovery_button.disabled, "An explicit native claim delivers one seed and two coins, then blocks repeated claims.")
	before = _json(Codec.capture(view))
	_expect(not economy.recover().ok and _json(Codec.capture(view)) == before, "Repeated emergency claims cannot generate extra seed or money.")
	_expect(app._save_game().ok and app.save_service.read().ok, "Recovery entries participate in cash and seed conservation.")
	var recovered := Codec.capture(view)
	for field in ["quantity", "unit_price"]:
		var invalid: Dictionary = recovered.duplicate(true)
		invalid.farm.ledger[-1].items[0][field] = 2
		_expect(not Codec.validate(invalid).ok, "Forged emergency quantities or prices are rejected: " + field)
	app._perform_load(false)
	_expect(not economy.can_recover() and view.farm.seed_stock.lettuce == 1, "Reloading cannot reset emergency eligibility.")
	_use(view, Vector2i(7, 12), Tools.Tool.HOE)
	view.tools.select_seed("lettuce")
	view.tools.use(Vector2i(7, 12), view.player.position)
	_expect(not economy.can_recover(), "Planting the emergency seed keeps another claim unavailable.")
	app.queue_free()
	await process_frame


func _capture(panel: Control, target: String) -> void:
	for tab in [0, 1]:
		panel.tabs.current_tab = tab
		for window_size in [Vector2i(1440, 900), Vector2i(1152, 720)]:
			root.size = window_size
			await process_frame
			await process_frame
			await RenderingServer.frame_post_draw
			var path := target.path_join("step-12-%s-%dx%d.png" % ["route" if tab == 0 else "comparison", window_size.x, window_size.y])
			_expect(root.get_texture().get_image().save_png(path) == OK, "Capture saved: " + path)
			print("FIELDWORKS_TUTORIAL_CAPTURE_OK ", path)
