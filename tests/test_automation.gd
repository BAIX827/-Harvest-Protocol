extends SceneTree

const Farm = preload("res://scripts/simulation/farm_state.gd")
const Simulation = preload("res://scripts/simulation/farm_simulation.gd")
const Economy = preload("res://scripts/simulation/economy_model.gd")
const Sensor = preload("res://scripts/engineering/sensor_model.gd")
const Automation = preload("res://scripts/engineering/automation_controller.gd")
const Engineer = preload("res://scripts/engineering/engineering_controller.gd")
const Codec = preload("res://scripts/persistence/save_codec.gd")
const Weather = preload("res://scripts/simulation/weather_model.gd")
var checks: int = 0
var failures: int = 0
var directory: String

class ExactSensor extends Sensor:
	var value: float = 20.0
	var valid: bool = true
	func control_reading(minute: int) -> Dictionary:
		return {"valid": valid, "value": value if valid else null, "reason": "exact boundary fixture", "minute": minute}

class DryWeather extends Weather:
	func ensure_period(minute: int) -> void:
		super.ensure_period(minute)
		kind = Kind.CLEAR


func _initialize() -> void:
	_run.call_deferred()


func _expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("AUTOMATION TEST FAILED: " + message)


func _state(farm: Farm) -> String:
	return JSON.stringify({"auto": farm.automation, "cash": farm.cash, "parts": farm.parts_stock, "engineering": farm.engineering}, "", true, true)


func _fixture() -> Dictionary:
	var farm := Farm.new()
	var simulation := Simulation.new(farm)
	var economy := Economy.new(farm, simulation.clock)
	var engineer := Engineer.new(economy, simulation.irrigation)
	economy.buy_modules({"tank_300": 1, "pump_eco": 1, "battery_180": 1, "pipe": 3, "sensor_basic": 1, "controller_basic": 1})
	for id in ["tank_300", "pump_eco", "battery_180"]: engineer.install(id)
	for point in [Vector2i(9, 7), Vector2i(10, 7), Vector2i(11, 7)]: engineer.pipe(point)
	engineer.refill("tank")
	engineer.refill("power")
	for y in range(8, 10):
		for x in range(10, 13): farm.plot_at(Vector2i(x, y)).tilled = true
	var sensor := ExactSensor.new(farm)
	var control := Automation.new(farm, simulation.irrigation, sensor, simulation.clock, false)
	control.install()
	control.set_connection("sensor", 0, "decision", 0, true)
	control.set_connection("decision", 0, "pump", 0, true)
	control.set_mode("auto")
	return {"farm": farm, "sim": simulation, "sensor": sensor, "control": control, "engineer": engineer}


func _run() -> void:
	directory = "res://tmp/qa/automation-%d-%d" % [OS.get_process_id(), Time.get_ticks_msec()]
	DirAccess.make_dir_recursive_absolute(directory)
	_test_rules()
	_test_faults()
	_test_time_and_cycles()
	await _test_live()
	if failures == 0: print("FIELDWORKS_AUTOMATION_TESTS_OK ", checks, " checks")
	else: print("FIELDWORKS_AUTOMATION_TESTS_FAILED ", failures, "/", checks)
	quit(0 if failures == 0 else 1)


func _test_rules() -> void:
	var f := _fixture()
	_expect(f.farm.automation.output and not f.farm.engineering.enabled, "Only the automatic command opens a ready system in auto mode.")
	for item in [[25.0, true], [30.0, true], [35.0, false], [30.0, false], [25.0, false], [24.999, true], [35.001, false]]:
		f.sensor.value = item[0]
		f.control.evaluate(480)
		_expect(f.farm.automation.output == item[1], "Exact threshold and hysteresis boundary: %.3f -> %s" % [item[0], item[1]])
	var before := _state(f.farm)
	for values in [[25, 25], [40, 20], [-1, 35], [25, 61], [NAN, 35], [25, INF], [true, 35], ["25", 35]]:
		_expect(not f.control.set_thresholds(values[0], values[1]).ok and _state(f.farm) == before, "Invalid thresholds leave the complete control state untouched.")
	_expect(not f.control.set_connection("sensor", 0, "pump", 0, true).ok and not f.control.set_connection("pump", 0, "decision", 0, true).ok and not f.control.set_connection("sensor", 1, "decision", 0, true).ok and _state(f.farm) == before, "Wrong direction, type and port are rejected without mutation.")
	_expect(not f.control.set_position("unknown", Vector2.ZERO).ok and not f.control.set_position("sensor", Vector2(NAN, 0)).ok and _state(f.farm) == before, "Unknown or nonfinite node positions are rejected.")
	_expect(not f.engineer.set_enabled(true).ok and _state(f.farm) == before, "Manual pump operations cannot bypass automatic control.")
	f.control.set_mode("manual")
	_expect(not f.farm.automation.output and not f.farm.engineering.enabled and f.engineer.set_enabled(true).ok, "Changing to manual stops first and permits an explicit manual start.")
	f.control.set_mode("auto")
	_expect(not f.farm.engineering.enabled, "Changing back to auto clears the old manual intent.")
	for index in range(140):
		f.sensor.value = 20.0 if index % 2 == 0 else 40.0
		f.control.evaluate(480)
	_expect(f.farm.automation.logs.size() == 120 and f.farm.automation.logs[0].id == f.farm.automation.next_log_id - 120, "Transition log is bounded with contiguous IDs.")
	f.control.remove()
	_expect(f.farm.automation.mode == "manual" and not f.farm.automation.installed and f.farm.parts_stock.controller_basic == 1 and not f.farm.engineering.enabled, "Removing a controller returns inventory and safely stops the pump.")


func _test_faults() -> void:
	for fault in ["graph_open", "sensor_invalid", "sensor_outside", "disconnected", "power_disconnected", "no_water", "no_energy", "missing_module"]:
		var f := _fixture()
		if fault == "graph_open": f.control.set_connection("decision", 0, "pump", 0, false)
		elif fault == "sensor_invalid": f.sensor.valid = false
		elif fault == "sensor_outside": f.farm.sensor.cell = [7, 12]
		elif fault == "disconnected": f.farm.engineering.pipes.erase("10,7")
		elif fault == "power_disconnected": f.farm.engineering.power_connected = false
		elif fault == "no_water": f.farm.engineering.water_l = 0.0
		elif fault == "no_energy": f.farm.engineering.energy_wh = 0.0
		elif fault == "missing_module": f.farm.engineering.pump = ""
		f.control.evaluate(480)
		_expect(f.farm.automation.code == fault and not f.farm.automation.output and not f.sim.irrigation.advance(5), "Protection blocks all supply: " + fault)
		if fault == "sensor_invalid":
			f.sensor.valid = true
			f.sensor.value = 30
			f.control.evaluate(480)
			_expect(not f.farm.automation.output and f.farm.automation.code == "hold_off", "Repair in the hysteresis band keeps the pump stopped.")
			f.sensor.value = 24
			f.control.evaluate(480)
			_expect(f.farm.automation.output, "After protection, only crossing the start threshold restarts supply.")


func _real_fixture() -> Dictionary:
	var farm := Farm.new()
	var sim := Simulation.new(farm)
	var economy := Economy.new(farm, sim.clock)
	var engineer := Engineer.new(economy, sim.irrigation)
	economy.buy_modules({"tank_300": 1, "pump_eco": 1, "battery_180": 1, "pipe": 3, "sensor_basic": 1, "controller_basic": 1})
	for id in ["tank_300", "pump_eco", "battery_180"]: engineer.install(id)
	for point in [Vector2i(9, 7), Vector2i(10, 7), Vector2i(11, 7)]: engineer.pipe(point)
	engineer.refill("tank")
	engineer.refill("power")
	for y in range(8, 10):
		for x in range(10, 13): farm.plot_at(Vector2i(x, y)).tilled = true
	var sensor_controller := preload("res://scripts/engineering/sensor_controller.gd").new(economy, sim.sensor)
	sensor_controller.install()
	sensor_controller.calibrate(18.0)
	sim.automation.install()
	for pair in [["sensor", "decision"], ["decision", "pump"]]: sim.automation.set_connection(pair[0], 0, pair[1], 0, true)
	sim.automation.set_mode("auto")
	return {"farm": farm, "sim": sim, "engineer": engineer, "sensor": sensor_controller}


func _test_time_and_cycles() -> void:
	var a := _real_fixture()
	var b := _real_fixture()
	a.sim.clock.set_speed(1)
	b.sim.clock.set_speed(12)
	for _index in range(540): a.sim.advance(1.0 / 30)
	for _index in range(216): b.sim.advance(1.0 / 144)
	_expect(JSON.stringify(a.farm.automation, "", true, true) == JSON.stringify(b.farm.automation, "", true, true) and JSON.stringify(a.farm.plots) == JSON.stringify(b.farm.plots) and JSON.stringify(a.farm.engineering) == JSON.stringify(b.farm.engineering), "Identical game time at different speed and FPS preserves decisions, logs and resources.")
	a.sim.clock.set_paused(true)
	var before := _state(a.farm)
	a.sim.advance(40)
	_expect(_state(a.farm) == before, "Pause does not run control steps or spend resources.")
	a.sensor.set_connected(false)
	_expect(not a.farm.automation.output and a.farm.automation.code == "sensor_invalid", "A real sensor operation immediately triggers protection while paused.")
	a.sensor.set_connected(true)
	a.sensor.set_fault("stuck")
	_expect(not a.farm.automation.output and a.farm.automation.code == "sensor_invalid" and a.farm.automation.logs.back().detail.contains("卡住"), "A real stuck probe never falls back to teaching truth and leaves the specific fault in the log.")
	a.sensor.set_fault("none")
	a.engineer.set_power(false)
	_expect(not a.farm.automation.output and a.farm.automation.code == "power_disconnected", "A real power operation immediately triggers protection while paused.")
	var stale := _real_fixture()
	stale.sim.automation.evaluate(stale.sim.clock.total_minutes + 15)
	_expect(not stale.farm.automation.output and stale.farm.automation.code == "sensor_invalid", "An actually stale sensor API result blocks the automatic command.")
	var cycle := _real_fixture()
	# A dry-weather fixture guarantees evaporation can reach the start threshold.
	# Seeded production rain can correctly keep soil wet for the whole observation.
	cycle.sim.weather = DryWeather.new()
	cycle.sim.automation.set_thresholds(20.0, 22.0)
	var starts: int = 0
	var stops: int = 0
	var output: bool = cycle.farm.automation.output
	for _index in range(1500):
		cycle.sim.advance(0.5)
		var next: bool = cycle.farm.automation.output
		if next and not output: starts += 1
		if not next and output and cycle.farm.automation.code == "stop": stops += 1
		output = next
		if starts >= 2 and stops >= 2: break
	_expect(starts >= 2 and stops >= 2 and cycle.farm.engineering.delivered_l > 0, "Real soil, weather, probe noise and hysteresis complete repeated wet/dry restart cycles.")


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


func _mouse(position: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = position
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	root.push_input(event, true)


func _button(button: Control) -> void:
	var point := button.get_global_transform_with_canvas() * (button.size / 2)
	_mouse(point, true)
	_mouse(point, false)
	await process_frame
	await process_frame


func _drag(from: Vector2, to: Vector2) -> void:
	_mouse(from, true)
	await process_frame
	for index in range(1, 9):
		var motion := InputEventMouseMotion.new()
		motion.position = from.lerp(to, float(index) / 8)
		motion.relative = (to - from) / 8
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(motion, true)
		await process_frame
	_mouse(to, false)
	await process_frame
	await process_frame


func _port(node: GraphNode, output: bool) -> Vector2:
	return node.get_global_transform_with_canvas() * (node.get_output_port_position(0) if output else node.get_input_port_position(0))


func _test_live() -> void:
	var app := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	app.set_meta("save_path", directory.path_join("farm.json"))
	root.add_child(app)
	var view: Control = app.farm_view
	view.simulation.clock.set_paused(true)
	view.economy.buy_modules({"tank_300": 1, "pump_eco": 1, "battery_180": 1, "pipe": 3, "sensor_basic": 1})
	for id in ["tank_300", "pump_eco", "battery_180"]: view.engineering.install(id)
	for point in [Vector2i(9, 7), Vector2i(10, 7), Vector2i(11, 7)]: view.engineering.pipe(point)
	view.engineering.refill("tank")
	view.engineering.refill("power")
	view.player.position = Vector2(11.5, 9.5)
	for y in range(8, 10):
		for x in range(10, 13):
			view.tools.select_tool(1)
			view.tools.use(Vector2i(x, y), view.player.position)
			view.tools.select_seed("lettuce")
			view.tools.use(Vector2i(x, y), view.player.position)
	view.sensor_controller.install()
	view.sensor_controller.calibrate(18.0)
	await process_frame
	await _tap(KEY_T)
	var panel: Control = app.automation_panel
	_expect(panel.visible and panel.graph is GraphEdit and not view.interaction_enabled, "T opens a real editable control graph and blocks farm input.")
	await _button(panel.buy_button)
	await _button(panel.install_button)
	_expect(view.farm.cash == 115 and view.farm.automation.installed, "The real control panel purchases and installs the 60 coin controller.")
	await _drag(_port(panel.nodes.sensor, true), _port(panel.nodes.decision, false))
	await _drag(_port(panel.nodes.decision, true), _port(panel.nodes.pump, false))
	_expect(view.farm.automation.edges.size() == 2 and panel.graph.get_connection_list().size() == 2, "Dragging actual GraphEdit ports creates the real measurement chain.")
	var position_before: Vector2 = panel.nodes.sensor.position_offset
	var header: Vector2 = panel.nodes.sensor.get_global_transform_with_canvas() * Vector2(90, 12)
	await _drag(header, header + Vector2(0, 30))
	_expect(panel.nodes.sensor.position_offset != position_before and Vector2(view.farm.automation.positions.sensor[0], view.farm.automation.positions.sensor[1]) == panel.nodes.sensor.position_offset, "Dragging a graph node updates the persisted layout.")
	await _button(panel.mode_button)
	_expect(view.farm.automation.output and panel.status_label.text.contains("低于启动"), "The connected calibrated probe opens the real automatic system.")
	var input_port := _port(panel.nodes.pump, false)
	await _drag(input_port, input_port + Vector2(0, 100))
	_expect(view.farm.automation.edges.size() == 1 and not view.farm.automation.output, "Dragging a real input port off its wire disconnects the control chain.")
	await _button(panel.connect_button)
	await _tap(KEY_F5)
	_expect(app.save_service.read().ok, "A running controller, graph, latch and log pass real disk validation.")
	var original := JSON.stringify(Codec.capture(view), "", true, true)
	await _button(panel.break_button)
	_expect(not view.farm.automation.output and view.farm.automation.code == "graph_open", "Disconnecting the actual graph immediately stops the pump.")
	app._perform_load(false)
	_expect(JSON.stringify(Codec.capture(view), "", true, true) == original, "Loading preserves the running controller and every layout, latch and log field exactly.")
	await _tap(KEY_T)
	await _button(panel.speed_button)
	var band_iterations: int = 0
	while float(view.simulation.sensor.current(view.simulation.clock.total_minutes).reading) < 30 and band_iterations < 800:
		if DisplayServer.get_name() == "headless": view.simulation.advance(0.1)
		else: await create_timer(0.02).timeout
		band_iterations += 1
	view.simulation.clock.set_paused(true)
	_expect(view.farm.automation.output and view.farm.automation.code == "hold_on" and app._save_game().ok, "The open hysteresis-band latch is saved with an actual between-threshold reading.")
	var band := JSON.stringify(Codec.capture(view), "", true, true)
	view.simulation.clock.set_paused(false)
	var iterations: int = 0
	while view.farm.automation.output and iterations < 1500:
		if DisplayServer.get_name() == "headless": view.simulation.advance(0.1)
		else: await create_timer(0.02).timeout
		iterations += 1
	view.simulation.clock.set_paused(true)
	_expect(not view.farm.automation.output and view.farm.automation.code == "stop" and view.farm.engineering.delivered_l > 100, "Normal calibrated feedback waters until the stop threshold and shuts off before tank exhaustion.")
	_expect(view.simulation.sensor.current(view.simulation.clock.total_minutes).reading >= 35 and view.farm.engineering.water_l > 0 and view.farm.engineering.energy_wh > 0, "Automatic stop is caused by the measured threshold, not lack of resources.")
	_expect(app._save_game().ok, "Threshold stop with consumed resources remains savable.")
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir=") and DisplayServer.get_name() != "headless": await _capture(argument.trim_prefix("--capture-dir="))
	var snapshot := Codec.capture(view)
	for field in ["output", "latch"]:
		var invalid: Dictionary = snapshot.duplicate(true)
		invalid.automation[field] = true
		_expect(not Codec.validate(invalid).ok, "A forged running latch/output cannot bypass the saved stop condition.")
	var invalid: Dictionary = snapshot.duplicate(true)
	invalid.automation.edges.append("pump>sensor")
	_expect(not Codec.validate(invalid).ok, "An invalid graph cannot enter a save.")
	invalid = snapshot.duplicate(true)
	invalid.automation.installed = false
	_expect(not Codec.validate(invalid).ok, "Controller ownership cannot disappear from a save.")
	# Restore the earlier running band using a separately validated candidate.
	var band_payload: Dictionary = JSON.parse_string(band)
	var validated := Codec.validate(band_payload)
	_expect(validated.ok and validated.farm.automation.latch, "An actual open latch in the middle band remains valid on reload.")
	var observe: Array = []
	var callback := func() -> void: observe.append(view.simulation.automation.set_mode("manual").ok)
	view.farm.automation_changed.connect(callback)
	view.simulation.automation.set_thresholds(24.0, 34.0)
	_expect(observe == [false], "Control edits commit under the shared reentry guard.")
	view.farm.automation_changed.disconnect(callback)
	await _tap(KEY_ESCAPE)
	_expect(not panel.visible and view.interaction_enabled and view.simulation.clock.paused, "Closing the panel preserves the user's pause setting.")
	app.queue_free()
	await process_frame


func _capture(target: String) -> void:
	for window_size in [Vector2i(1440, 900), Vector2i(1152, 720)]:
		root.size = window_size
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var file := target.path_join("step-10-automation-%dx%d.png" % [window_size.x, window_size.y])
		_expect(root.get_texture().get_image().save_png(file) == OK, "Automation capture saved: " + file)
		print("FIELDWORKS_AUTOMATION_CAPTURE_OK ", file)
