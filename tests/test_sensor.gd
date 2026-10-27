extends SceneTree

const Farm = preload("res://scripts/simulation/farm_state.gd")
const Simulation = preload("res://scripts/simulation/farm_simulation.gd")
const Economy = preload("res://scripts/simulation/economy_model.gd")
const Controller = preload("res://scripts/engineering/sensor_controller.gd")
const Model = preload("res://scripts/engineering/sensor_model.gd")
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
		push_error("SENSOR TEST FAILED: " + message)


func _fixture() -> Dictionary:
	var farm := Farm.new()
	var sim := Simulation.new(farm)
	var economy := Economy.new(farm, sim.clock)
	return {"farm": farm, "sim": sim, "economy": economy, "model": sim.sensor, "controller": Controller.new(economy, sim.sensor)}


func _snapshot(f: Dictionary) -> String:
	return JSON.stringify({"plots": f.farm.plots, "cash": f.farm.cash, "parts": f.farm.parts_stock, "ledger": f.farm.ledger, "sensor": f.farm.sensor}, "", true, true)


func _install(f: Dictionary) -> void:
	_expect(f.economy.buy_modules({"sensor_basic": 1}).ok and f.controller.install().ok, "A paid probe installs and takes a real sample.")


func _run() -> void:
	directory = "res://tmp/qa/sensor-%d-%d" % [OS.get_process_id(), Time.get_ticks_msec()]
	DirAccess.make_dir_recursive_absolute(directory)
	_test_measurement()
	_test_faults()
	_test_time()
	await _test_live()
	if failures == 0: print("FIELDWORKS_SENSOR_TESTS_OK ", checks, " checks")
	else: print("FIELDWORKS_SENSOR_TESTS_FAILED ", failures, "/", checks)
	quit(0 if failures == 0 else 1)


func _test_measurement() -> void:
	var f := _fixture()
	var original := _snapshot(f)
	_expect(not f.model.control_reading(480).valid and f.model.control_reading(480).value == null, "An absent sensor supplies no control number.")
	_expect(not f.controller.install().ok and _snapshot(f) == original, "A probe cannot be installed without buying it.")
	_install(f)
	_expect(f.farm.cash == 560 and f.farm.parts_stock.sensor_basic == 0 and f.farm.ledger.size() == 2, "The 40 coin probe is charged once and consumed into the active channel.")
	var installed := _snapshot(f)
	_expect(not f.controller.install().ok and _snapshot(f) == installed, "Repeated install changes neither inventory nor calibration.")
	var measured: Dictionary = f.model.current(480)
	_expect(measured.valid and measured.raw_adc > 0 and measured.raw_adc < 4095 and absf(float(measured.reading) - 19.5) < 0.25, "Raw signal and quantized factory reading expose the designed bias.")
	_expect(f.farm.plot_at(Vector2i(10, 8)).moisture == 18.0 and f.farm.engineering.water_l == 0, "Measurement neither changes soil truth nor creates irrigation resources.")
	f.farm.plot_at(Vector2i(10, 8)).moisture = 30.0
	f.controller.sample_now()
	var baseline: float = f.model.current(480).reading
	f.controller.configure(Vector2i(10, 8), "sand", "seated")
	var sandy: float = f.model.current(480).reading
	f.controller.configure(Vector2i(10, 8), "clay", "seated")
	var clay: float = f.model.current(480).reading
	_expect(sandy < baseline - 2 and clay > baseline + 6 and f.model.truth() == 30.0, "Different soil response changes the signal while the same true moisture stays fixed.")
	f.controller.configure(Vector2i(10, 8), "loam", "loose")
	var loose: float = f.model.current(480).reading
	f.controller.configure(Vector2i(10, 8), "loam", "shallow")
	var shallow: float = f.model.current(480).reading
	_expect(loose < baseline - 3 and shallow > baseline + 2, "Contact and insertion conditions have distinct signed error sources.")
	f.controller.configure(Vector2i(10, 8), "clay", "seated")
	var before_error: float = absf(float(f.model.current(480).reading) - 30.0)
	var old_history := JSON.stringify(f.farm.sensor.history, "", true, true)
	var count: int = f.farm.sensor.history.size()
	_expect(f.controller.calibrate(30.0).ok and absf(float(f.model.current(480).reading) - 30.0) < 0.45 and before_error > 6, "A known single point reference improves the real measurement chain.")
	_expect(JSON.stringify(f.farm.sensor.history.slice(0, count), "", true, true) == old_history, "Calibration does not rewrite previous samples.")
	_expect(f.farm.sensor.latest.revision > f.farm.sensor.history[count - 1].revision, "Calibration starts a new curve segment.")
	var unchanged := _snapshot(f)
	for bad in [NAN, INF, -1, 61, true, "30"]:
		_expect(not f.controller.calibrate(bad).ok and _snapshot(f) == unchanged, "Invalid calibration references cannot mutate any farm state.")
	for coefficients in [[0.0, 0.0], [2.0, 0.0], [1.0, 21.0], [1.0, NAN], [true, 0.0]]:
		_expect(not f.controller.set_calibration(coefficients[0], coefficients[1]).ok and _snapshot(f) == unchanged, "Out of range or nonnumeric calibration coefficients are rejected.")
	_expect(not f.controller.configure(Vector2i(18, 5), "loam", "seated").ok and not f.controller.configure(Vector2i(10, 8), "unknown", "seated").ok and _snapshot(f) == unchanged, "Nonsoil and unsupported measurement conditions are rejected.")
	f.farm.plot_at(Vector2i(11, 8)).moisture = 40.0
	f.controller.configure(Vector2i(11, 8), "loam", "seated")
	f.controller.set_calibration(1.0, 0.0)
	_expect(f.model.truth() == 40.0 and f.model.current(480).reading > 41.0 and f.farm.sensor.latest.cell == [11, 8], "Moving the channel samples the selected real farm plot.")
	_expect(f.controller.remove().ok and f.farm.parts_stock.sensor_basic == 1 and not f.model.current(480).valid, "Removing a probe returns it to inventory and invalidates the active channel.")
	_expect(f.controller.install().ok and f.farm.cash == 560, "Reinstalling an owned probe incurs no new purchase cost.")
	var observed: Array = []
	var callback := func() -> void: observed.append(f.controller.remove().ok)
	f.farm.sensor_changed.connect(callback)
	f.controller.sample_now()
	_expect(observed == [false] and f.farm.sensor.installed, "Sample notifications cannot reenter installation changes.")
	f.farm.sensor_changed.disconnect(callback)


func _test_faults() -> void:
	var f := _fixture()
	_install(f)
	var rng_before: String = f.farm.sensor.rng_state
	f.controller.set_connected(false)
	var measured: Dictionary = f.model.current(480)
	_expect(not measured.valid and measured.reading == null and measured.raw_adc == null and measured.code == "disconnected", "An unplugged signal is a missing measurement, never zero or truth.")
	_expect(f.farm.sensor.rng_state == rng_before and not f.model.control_reading(480).valid, "A disconnected probe consumes no noise draw and supplies no control value.")
	var failed := _snapshot(f)
	_expect(not f.controller.calibrate(18.0).ok and _snapshot(f) == failed, "Invalid measurements cannot be calibrated into valid control values.")
	f.controller.set_connected(true)
	for fault in ["open", "short", "stuck"]:
		var held: int = f.farm.sensor.latest.raw_adc
		f.controller.set_fault(fault)
		measured = f.model.current(480)
		_expect(not measured.valid and measured.reading == null and measured.code == fault and f.model.control_reading(480).value == null, "Fault cannot masquerade as a usable control measurement: " + fault)
		if fault == "open": _expect(measured.raw_adc == 4095, "Open circuit displays the high raw signal.")
		elif fault == "short": _expect(measured.raw_adc == 0, "Short circuit displays zero raw voltage without treating it as zero moisture.")
		else:
			f.farm.plot_at(Vector2i(10, 8)).moisture = 35.0
			f.controller.sample_now()
			_expect(f.farm.sensor.latest.raw_adc == held and f.farm.sensor.latest.truth == 35.0, "A stuck signal can remain fixed while actual soil changes.")
		f.controller.set_fault("none")
		_expect(f.model.current(480).valid, "Repairing a fault resumes the same measurement channel.")
	f.controller.set_calibration(1.5, 20.0)
	_expect(not f.model.current(480).valid and f.model.current(480).code == "out_of_range", "Implausible converted values are invalidated instead of clipped into a plausible range.")
	f.controller.set_calibration(1.0, 0.0)
	f.farm.plot_at(Vector2i(10, 8)).moisture = 60.0
	f.controller.configure(Vector2i(10, 8), "clay", "seated")
	_expect(f.model.current(480).code == "saturated" and not f.model.control_reading(480).valid, "Physical ADC saturation cannot provide a normal control number.")
	_expect(not f.model.current(495).valid and f.model.current(495).code == "stale", "A measurement older than two sample intervals is unusable.")


func _test_time() -> void:
	var a := _fixture()
	var b := _fixture()
	_install(a)
	_install(b)
	a.sim.clock.set_speed(1)
	b.sim.clock.set_speed(12)
	for _index in range(180): a.sim.advance(1.0 / 30.0)
	for _index in range(72): b.sim.advance(1.0 / 144.0)
	_expect(a.sim.clock.total_minutes == 540 and JSON.stringify(a.farm.sensor, "", true, true) == JSON.stringify(b.farm.sensor, "", true, true), "The same game duration at different speed and frame rate gives identical samples and noise state.")
	var before := _snapshot(a)
	a.sim.clock.set_paused(true)
	a.sim.advance(10)
	_expect(_snapshot(a) == before, "Paused game time produces no periodic sensor samples.")
	var minute: int = a.sim.clock.total_minutes
	a.controller.sample_now()
	_expect(a.sim.clock.total_minutes == minute and a.farm.sensor.sample_count == b.farm.sensor.sample_count + 1, "An explicit sample while paused adds one measurement without advancing time.")
	for _index in range(40): b.controller.sample_now()
	a.sim.clock.set_paused(false)
	for _index in range(400):
		a.sim.advance(0.5)
		b.sim.advance(1.0 / 24.0)
	_expect(JSON.stringify(a.sim.weather.export_state()) == JSON.stringify(b.sim.weather.export_state()) and JSON.stringify(a.farm.plots) == JSON.stringify(b.farm.plots), "Sensor noise and manual sample frequency do not change weather or soil simulation.")
	_expect(a.farm.sensor.history.size() == 180 and int(a.farm.sensor.history[0].serial) == int(a.farm.sensor.sample_count) - 179, "History is bounded and preserves serial continuity after trimming.")


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


func _select(choice: OptionButton, id: String) -> void:
	for index in range(choice.item_count):
		if str(choice.get_item_metadata(index)) == id: choice.select(index)


func _test_live() -> void:
	var app := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	app.set_meta("save_path", directory.path_join("farm.json"))
	root.add_child(app)
	var view: Control = app.farm_view
	view.simulation.clock.set_paused(true)
	await process_frame
	await process_frame
	await _tap(KEY_I)
	var panel: Control = app.sensor_panel
	_expect(panel.visible and not view.interaction_enabled and view.simulation.clock.paused, "I opens the desk without changing a paused clock and blocks farm input.")
	var point: Vector2 = view.player.position
	_key(KEY_W, true)
	await create_timer(0.05).timeout
	_key(KEY_W, false)
	_expect(view.player.position == point, "The measurement desk blocks movement behind the panel.")
	await _button(panel.buy_button)
	await _button(panel.install_button)
	_expect(view.farm.cash == 560 and view.farm.sensor.installed and panel.converted_label.text.contains("有效读数"), "Real buttons purchase, install and display a measured signal.")
	_select(panel.soil_choice, "clay")
	await _button(panel.apply_button)
	var before: float = absf(float(view.farm.sensor.latest.reading) - 18.0)
	panel.reference_input.value = 18.0
	await _button(panel.calibrate_button)
	_expect(before > 5 and absf(float(view.farm.sensor.latest.reading) - 18.0) < 0.45 and view.simulation.sensor.truth() == 18.0, "Reference calibration through the UI improves measurement, not the soil.")
	await _button(panel.speed_button)
	if DisplayServer.get_name() == "headless": view.simulation.advance(1.0)
	else:
		var end_minute: int = view.simulation.clock.total_minutes + 120
		var started := Time.get_ticks_msec()
		while view.simulation.clock.total_minutes < end_minute and Time.get_ticks_msec() - started < 5000:
			await create_timer(0.03).timeout
	await _button(panel.pause_button)
	_expect(view.simulation.clock.paused and view.farm.sensor.history.size() > 20 and panel.chart.records.size() == view.farm.sensor.history.size(), "The live desk advances normal game frames and charts actual samples.")
	await _button(panel.connection_button)
	_expect(not view.simulation.sensor.current(view.simulation.clock.total_minutes).valid and panel.converted_label.text.contains("测量无效") and panel.chart.records.back().reading == null, "Disconnecting from the panel creates a real invalid sample and curve gap.")
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir=") and DisplayServer.get_name() != "headless": await _capture(argument.trim_prefix("--capture-dir="), "disconnected")
	await _button(panel.connection_button)
	_select(panel.fault_choice, "stuck")
	await _button(panel.fault_button)
	_expect(not view.simulation.sensor.control_reading(view.simulation.clock.total_minutes).valid and panel.status_label.text.contains("卡住"), "A stuck fault set through UI is never a valid control input.")
	_select(panel.fault_choice, "none")
	await _button(panel.fault_button)
	await _tap(KEY_F5)
	_expect(app.save_service.read().ok and app.save_status.text.begins_with("已保存"), "The full sensor channel, history and noise state pass disk validation.")
	var saved := JSON.stringify(Codec.capture(view), "", true, true)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir=") and DisplayServer.get_name() != "headless": await _capture(argument.trim_prefix("--capture-dir="), "calibrated")
	await _button(panel.sample_button)
	app._perform_load(false)
	_expect(not panel.visible and view.interaction_enabled and JSON.stringify(Codec.capture(view), "", true, true) == saved, "Loading restores exact samples and closes the desk onto the same live farm.")
	var payload := Codec.capture(view)
	var changes: Array[Callable] = [
		func(p: Dictionary) -> void: p.sensor.cell = [18, 5],
		func(p: Dictionary) -> void: p.sensor.rng_state = "bad",
		func(p: Dictionary) -> void: p.sensor.offset = 99,
		func(p: Dictionary) -> void: p.sensor.sample_count += 1,
		func(p: Dictionary) -> void: p.sensor.latest.reading += 1,
		func(p: Dictionary) -> void: p.sensor.history.back().raw_adc += 1,
		func(p: Dictionary) -> void: p.sensor.history.back().minute += 5,
		func(p: Dictionary) -> void: p.sensor.history[0].valid = false,
		func(p: Dictionary) -> void: p.sensor.installed = false,
		func(p: Dictionary) -> void: p.sensor.history.back().erase("reading"),
		func(p: Dictionary) -> void: p.sensor.latest = {},
	]
	for index in range(changes.size()):
		var invalid: Dictionary = payload.duplicate(true)
		changes[index].call(invalid)
		_expect(not Codec.validate(invalid).ok, "Invalid channel/history/ownership is rejected before mutation: %d" % index)
	await _tap(KEY_I)
	await _button(panel.remove_button)
	_expect(view.farm.parts_stock.sensor_basic == 1 and not view.simulation.sensor.control_reading(view.simulation.clock.total_minutes).valid and app._save_game().ok, "Removing a probe keeps valid ownership and a savable invalid channel.")
	await _tap(KEY_SPACE)
	_expect(not view.simulation.clock.paused, "Space controls game time in the measurement desk.")
	await _tap(KEY_ESCAPE)
	_expect(not panel.visible and not view.simulation.clock.paused and view.interaction_enabled, "Closing the desk preserves the user's running time setting.")
	view.simulation.clock.set_paused(true)
	app.queue_free()
	await process_frame


func _capture(target: String, label: String) -> void:
	for window_size in [Vector2i(1440, 900), Vector2i(1152, 720)]:
		root.size = window_size
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var path := target.path_join("step-09-%s-%dx%d.png" % [label, window_size.x, window_size.y])
		_expect(root.get_texture().get_image().save_png(path) == OK, "Measurement capture saved: " + path)
		print("FIELDWORKS_SENSOR_CAPTURE_OK ", path)
