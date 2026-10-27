extends SceneTree

const Farm = preload("res://scripts/simulation/farm_state.gd")
const Simulation = preload("res://scripts/simulation/farm_simulation.gd")
const Economy = preload("res://scripts/simulation/economy_model.gd")
const Controller = preload("res://scripts/engineering/engineering_controller.gd")
const Network = preload("res://scripts/engineering/irrigation_network.gd")
const Codec = preload("res://scripts/persistence/save_codec.gd")
const Service = preload("res://scripts/persistence/save_service.gd")
var checks: int = 0
var failures: int = 0
var directory: String


func _initialize() -> void:
	_run.call_deferred()


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("IRRIGATION TEST FAILED: " + message)


func _snapshot(farm: Farm) -> String:
	return JSON.stringify({"cash": farm.cash, "parts": farm.parts_stock, "state": farm.engineering, "ledger": farm.ledger}, "", true, true)


func _fixture() -> Dictionary:
	var farm := Farm.new()
	var simulation := Simulation.new(farm)
	var economy := Economy.new(farm, simulation.clock)
	var controller := Controller.new(economy, simulation.irrigation)
	return {"farm": farm, "sim": simulation, "economy": economy, "controller": controller, "network": simulation.irrigation}


func _assemble(f: Dictionary) -> void:
	_expect(f.economy.buy_modules({"tank_120": 1, "pump_eco": 1, "battery_60": 1, "pipe": 5}).ok, "Modules and pipes are bought in one priced transaction.")
	for id in ["tank_120", "pump_eco", "battery_60"]:
		_expect(f.controller.install(id).ok, "Purchased module installs: " + id)
	for point in Network.STARTER_ROUTE: _expect(f.controller.pipe(point).ok, "Install a route segment.")
	_expect(f.controller.refill("tank").ok and f.controller.refill("power").ok, "Water and energy are purchased into the installed reservoirs.")
	for y in range(8, 10):
		for x in range(10, 13): f.farm.plot_at(Vector2i(x, y)).tilled = true
	f.controller.set_enabled(true)


func _run() -> void:
	directory = "res://tmp/qa/irrigation-%d-%d" % [OS.get_process_id(), Time.get_ticks_msec()]
	DirAccess.make_dir_recursive_absolute(directory)
	_test_trades()
	_test_resources()
	_test_determinism()
	await _test_live()
	if failures == 0: print("FIELDWORKS_IRRIGATION_TESTS_OK ", checks, " checks")
	else: print("FIELDWORKS_IRRIGATION_TESTS_FAILED ", failures, "/", checks)
	quit(0 if failures == 0 else 1)


func _test_trades() -> void:
	var f := _fixture()
	var original := _snapshot(f.farm)
	for request in [{"pipe": -1}, {"pipe": 0}, {"pipe": 1.0}, {"pipe": true}, {"unknown": 1}, {"controller_basic": 1}, {"tank_300": 100}]:
		_expect(not f.economy.buy_modules(request).ok and _snapshot(f.farm) == original, "Invalid or unaffordable purchases change no assets.")
	_expect(not f.controller.install("pump_eco").ok and _snapshot(f.farm) == original, "Unowned modules cannot be installed.")
	_assemble(f)
	_expect(f.farm.cash == 348 and f.farm.ledger.size() == 4, "Initial modules cost 240, water 6 and energy 6, all recorded once.")
	var equipped := _snapshot(f.farm)
	_expect(not f.controller.install("pump_eco").ok and _snapshot(f.farm) == equipped, "Repeated install never charges or consumes another module.")
	_expect(not f.controller.refill("tank").ok and not f.controller.refill("power").ok and _snapshot(f.farm) == equipped, "Full reservoirs reject repeat charges.")
	f.controller.pipe(Network.STARTER_ROUTE[1])
	_expect(not f.network.connected() and f.farm.parts_stock.pipe == 3, "Removing a bridge breaks connectivity and returns exactly one pipe.")
	f.controller.pipe(Network.STARTER_ROUTE[1])
	_expect(f.network.connected() and f.farm.parts_stock.pipe == 2 and f.farm.cash == 348, "Reusing a pipe costs no additional money.")
	var before := _snapshot(f.farm)
	_expect(not f.controller.pipe(Network.PUMP).ok and not f.controller.pipe(Vector2i(0, 0)).ok and _snapshot(f.farm) == before, "Fixed equipment and outside cells reject pipe edits.")
	f.controller.buy("pump_fast")
	f.controller.install("pump_fast")
	_expect(f.farm.cash == 198 and f.farm.parts_stock.pump_eco == 1 and f.farm.parts_stock.pump_fast == 0, "Swapping a pump returns the old unit and does not charge twice.")
	f.controller.install("pump_eco")
	_expect(f.farm.cash == 198 and f.farm.parts_stock.pump_fast == 1, "A previously owned pump can be installed again for free.")
	# Observers see completed resource/cash/ledger updates and cannot reenter.
	var observed: Array = []
	var callback := func() -> void:
		observed.append(f.controller.install("pump_fast").ok)
	f.farm.engineering_changed.connect(callback)
	f.controller.set_power(false)
	_expect(observed == [false] and f.farm.engineering.pump == "pump_eco", "Reentrant edits during notifications are rejected.")
	f.farm.engineering_changed.disconnect(callback)
	var water_before: float = f.farm.engineering.water_l
	f.controller.buy("tank_300")
	f.controller.install("tank_300")
	_expect(f.farm.engineering.water_l == water_before, "Buying or installing a bigger reservoir creates no water.")
	f.controller.refill("tank")
	f.controller.install("tank_120")
	_expect(f.farm.engineering.water_l == 120.0 and f.farm.engineering.discarded_water_l == 180.0, "Capacity reduction discards and accounts for overflow.")


func _test_resources() -> void:
	var f := _fixture()
	_assemble(f)
	_expect(f.network.status().running and f.network.connected(), "Complete powered route can supply the cultivated coverage.")
	var before: float = f.farm.plot_at(Vector2i(10, 8)).moisture
	_expect(f.network.advance(5), "A fixed step delivers water.")
	_expect(is_equal_approx(f.farm.engineering.water_l, 116.0) and is_equal_approx(f.farm.engineering.energy_wh, 58.0), "48 L/h and 24 W consume exactly 4 L and 2 Wh in five minutes.")
	_expect(is_equal_approx(f.farm.plot_at(Vector2i(10, 8)).moisture - before, 1.0 / 3.0), "Four liters shared across six 1 m² plots raise each moisture by one third point.")
	_expect(f.farm.plot_at(Vector2i(13, 8)).moisture == 18.0, "Plots outside the outlet coverage receive no irrigation.")
	for fault in ["off", "disconnected", "power_disconnected", "no_water", "no_energy"]:
		var state: Dictionary = f.farm.engineering.duplicate(true)
		if fault == "off": f.controller.set_enabled(false)
		elif fault == "disconnected": f.controller.pipe(Network.STARTER_ROUTE[1])
		elif fault == "power_disconnected": f.controller.set_power(false)
		elif fault == "no_water": f.farm.engineering.water_l = 0.0
		elif fault == "no_energy": f.farm.engineering.energy_wh = 0.0
		var frozen := _snapshot(f.farm)
		_expect(f.network.status().code == fault and not f.network.advance(5) and _snapshot(f.farm) == frozen, "Fault blocks supply and resource consumption: " + fault)
		f.farm.engineering = state
	f.farm.engineering.energy_wh = 0.5
	f.network.advance(5)
	_expect(is_equal_approx(f.farm.engineering.water_l, 115.0) and f.farm.engineering.energy_wh == 0.0, "Insufficient battery powers a proportionally limited final dose.")
	f.farm.engineering.energy_wh = 60.0
	f.farm.engineering.water_l = 0.25
	var delivered_before: float = f.farm.engineering.delivered_l
	f.network.advance(5)
	_expect(f.farm.engineering.water_l == 0.0 and is_equal_approx(f.farm.engineering.delivered_l - delivered_before, 0.25), "Insufficient tank releases only its remaining water.")
	var empty := _fixture()
	_assemble(empty)
	for point in empty.network.targets(): empty.farm.plot_at(point).moisture = 60.0
	var full := _snapshot(empty.farm)
	_expect(empty.network.status().code == "no_demand" and not empty.network.advance(5) and _snapshot(empty.farm) == full, "Saturated soil does not consume water or electricity.")
	var fast := _fixture()
	_assemble(fast)
	fast.controller.buy("pump_fast")
	fast.controller.install("pump_fast")
	fast.network.advance(5)
	_expect(fast.farm.engineering.water_l == 112.0 and fast.farm.engineering.energy_wh == 55.0, "High flow pump changes the actual dose and energy use to 8 L / 5 Wh per step.")
	# Uneven near-saturation must return spare shares instead of losing water.
	var uneven := _fixture()
	_assemble(uneven)
	uneven.farm.plot_at(Vector2i(10, 8)).moisture = 59.99
	var moisture_sum: float = 0.0
	for point in uneven.network.targets(): moisture_sum += uneven.farm.plot_at(point).moisture
	uneven.network.advance(5)
	var after_sum: float = 0.0
	for y in range(8, 10):
		for x in range(10, 13): after_sum += uneven.farm.plot_at(Vector2i(x, y)).moisture
	_expect(is_equal_approx(after_sum - moisture_sum, 2.0) and uneven.farm.plot_at(Vector2i(10, 8)).moisture == 60.0, "Full plots return excess allocation; delivered water equals soil increase.")


func _test_determinism() -> void:
	var a := _fixture()
	var b := _fixture()
	_assemble(a)
	_assemble(b)
	a.sim.clock.set_speed(1)
	b.sim.clock.set_speed(12)
	for _index in range(180): a.sim.advance(1.0 / 30.0)
	for _index in range(72): b.sim.advance(1.0 / 144.0)
	_expect(a.sim.clock.total_minutes == b.sim.clock.total_minutes and _snapshot(a.farm) == _snapshot(b.farm) and JSON.stringify(a.farm.plots) == JSON.stringify(b.farm.plots), "Equal game time at different frame rates and speeds gives identical water, energy and soil.")
	var before := _snapshot(a.farm)
	a.sim.clock.set_paused(true)
	a.sim.advance(20)
	_expect(_snapshot(a.farm) == before, "Pausing freezes irrigation as well as natural simulation.")


func _key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _tap(code: Key) -> void:
	_key(code, true)
	_key(code, false)
	await process_frame
	await process_frame


func _button(button: Control) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = button.get_global_transform_with_canvas() * (button.size / 2.0)
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event, true)
	await process_frame
	await process_frame


func _test_live() -> void:
	var app := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	app.set_meta("save_path", directory.path_join("farm.json"))
	root.add_child(app)
	var view: Control = app.farm_view
	view.simulation.clock.set_paused(true)
	await process_frame
	await process_frame
	await _tap(KEY_E)
	var panel: Control = app.workbench_panel
	_expect(panel.visible and view.simulation.clock.paused and not view.interaction_enabled, "E opens a paused workbench that blocks farm interaction.")
	var position: Vector2 = view.player.position
	_key(KEY_W, true)
	await create_timer(0.05).timeout
	_key(KEY_W, false)
	_expect(view.player.position == position, "Movement keys cannot move the player behind the workbench.")
	for kind in ["tank", "pump", "power"]:
		await _button(panel.buy_buttons[kind])
		await _button(panel.install_buttons[kind])
	await _button(panel.buy_pipe_button)
	for point in Network.STARTER_ROUTE: await _button(panel.pipe_buttons[point])
	await _button(panel.water_button)
	await _button(panel.energy_button)
	# Cultivate and sow all six covered cells using the ordinary tools.
	view.player.position = Vector2(11.5, 9.5)
	for y in range(8, 10):
		for x in range(10, 13):
			var point := Vector2i(x, y)
			view.tools.select_tool(1)
			view.tools.use(point, view.player.position)
			view.tools.select_seed("lettuce")
			view.tools.use(point, view.player.position)
	view.selected_cell = Vector2i(10, 8)
	view.tile_selected.emit(view.selected_cell)
	await _button(panel.switch_button)
	_expect(view.farm.cash == 348 and view.simulation.irrigation.status().running and panel.status_label.text.contains("运行就绪"), "Real button clicks assemble and refill a working irrigation kit for 252 coins.")
	await _tap(KEY_F5)
	_expect(app.save_service.read().ok, "The assembled kit and engineering purchases pass the complete save validator.")
	var saved := JSON.stringify(Codec.capture(view), "", true, true)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir=") and DisplayServer.get_name() != "headless":
			await _capture(argument.trim_prefix("--capture-dir="), "workbench")
	await _tap(KEY_E)
	_expect(not panel.visible and view.interaction_enabled and view.simulation.clock.paused, "Closing restores the previously paused farm.")
	view.simulation.clock.set_paused(false)
	view.simulation.clock.set_speed(12)
	var water_before: float = view.farm.engineering.water_l
	if DisplayServer.get_name() != "headless":
		var end_minute: int = view.simulation.clock.total_minutes + 60
		var started := Time.get_ticks_msec()
		while view.simulation.clock.total_minutes < end_minute and Time.get_ticks_msec() - started < 5000:
			await create_timer(0.03).timeout
	else:
		view.simulation.advance(0.5)
	view.simulation.clock.set_paused(true)
	_expect(view.farm.engineering.water_l < water_before and view.farm.plot_at(Vector2i(10, 8)).moisture > 18.0 and app._engineering_label.text.contains("L"), "The main farm shows irrigation that actually increases soil moisture.")
	var pumped := Service.new(directory.path_join("pumped.json"))
	_expect(pumped.save(view).ok and pumped.read().ok, "Already delivered water and consumed electricity remain conserved in a real disk save.")
	_expect(view.simulation.water_rates_at(Vector2i(10, 8)).irrigation > 0.0 and view.simulation.water_rates_at(Vector2i(10, 8)).net > 0.0, "The inspector trend includes the same engineering supply that changes soil moisture.")
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir=") and DisplayServer.get_name() != "headless":
			await _capture(argument.trim_prefix("--capture-dir="), "farm")
	app._perform_load(false)
	_expect(JSON.stringify(Codec.capture(view), "", true, true) == saved, "Loading returns every device, resource and pipe field to the saved snapshot.")
	var payload := Codec.capture(view)
	for field in ["water_l", "energy_wh", "water_loaded_l", "delivered_l", "used_wh"]:
		var invalid: Dictionary = payload.duplicate(true)
		invalid.engineering[field] += 1
		_expect(not Codec.validate(invalid).ok, "Inconsistent engineering resources are rejected before loading: " + field)
	var invalid: Dictionary = payload.duplicate(true)
	invalid.engineering.pipes.append(Network.key(Network.STARTER_ROUTE[0]))
	_expect(not Codec.validate(invalid).ok, "Duplicate pipe ownership cannot enter a save.")
	invalid = payload.duplicate(true)
	invalid.farm.parts.pipe += 1
	_expect(not Codec.validate(invalid).ok, "Unpurchased spare parts cannot enter a save.")
	await _tap(KEY_E)
	await _button(panel.pipe_buttons[Network.STARTER_ROUTE[1]])
	_expect(panel.status_label.text.contains("管路断开") and not view.simulation.irrigation.status().running, "Removing the bridge from the UI reports the actual supply fault.")
	await _button(panel.pipe_buttons[Network.STARTER_ROUTE[1]])
	await _button(panel.power_button)
	_expect(panel.status_label.text.contains("电源已断开"), "Disconnecting the real power link explains why water stops.")
	await _button(panel.power_button)
	view.simulation.clock.set_paused(true)
	await _tap(KEY_ESCAPE)
	app.queue_free()
	await process_frame


func _capture(target: String, label: String) -> void:
	for window_size in [Vector2i(1440, 900), Vector2i(1152, 720)]:
		root.size = window_size
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var file := target.path_join("step-08-%s-%dx%d.png" % [label, window_size.x, window_size.y])
		_expect(root.get_texture().get_image().save_png(file) == OK, "Irrigation capture saved: " + file)
		print("FIELDWORKS_IRRIGATION_CAPTURE_OK ", file)
