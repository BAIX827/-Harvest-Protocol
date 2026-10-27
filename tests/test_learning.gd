extends SceneTree
## Exercise real teaching state, physical signals, persistence and native controls.

const Farm = preload("res://scripts/simulation/farm_state.gd")
const Simulation = preload("res://scripts/simulation/farm_simulation.gd")
const Economy = preload("res://scripts/simulation/economy_model.gd")
const Engineer = preload("res://scripts/engineering/engineering_controller.gd")
const Probe = preload("res://scripts/engineering/sensor_controller.gd")
const Learning = preload("res://scripts/progression/learning_controller.gd")
const Snapshot = preload("res://scripts/progression/learning_snapshot.gd")
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
		push_error("LEARNING TEST FAILED: " + message)


func _json(value: Variant) -> String:
	return JSON.stringify(value, "", true, true)


func _fixture(ready: bool = false) -> Dictionary:
	var farm := Farm.new()
	var sim := Simulation.new(farm)
	var economy := Economy.new(farm, sim.clock)
	var engineer := Engineer.new(economy, sim.irrigation)
	var probe := Probe.new(economy, sim.sensor)
	var learning := Learning.new(farm, probe, sim)
	if ready:
		economy.buy_modules({"tank_300": 1, "pump_eco": 1, "battery_180": 1, "pipe": 3, "sensor_basic": 1, "controller_basic": 1})
		for id in ["tank_300", "pump_eco", "battery_180"]: engineer.install(id)
		for point in [Vector2i(9, 7), Vector2i(10, 7), Vector2i(11, 7)]: engineer.pipe(point)
		engineer.refill("tank")
		engineer.refill("power")
		for y in range(8, 10):
			for x in range(10, 13): farm.plot_at(Vector2i(x, y)).tilled = true
		probe.install()
		_experiment(learning)
		learning.apply_to_farm()
		sim.automation.install()
		for pair in [["sensor", "decision"], ["decision", "pump"]]: sim.automation.set_connection(pair[0], 0, pair[1], 0, true)
		sim.automation.set_mode("auto")
	sim.clock.set_paused(true)
	return {"farm": farm, "sim": sim, "economy": economy, "engineer": engineer, "probe": probe, "learning": learning}


func _experiment(learning: Learning) -> void:
	learning.set_conditions(20.0, "clay", "seated")
	learning.record_point(0)
	learning.set_conditions(40.0, "clay", "seated")
	learning.record_point(1)
	learning.calibrate()


func _step(fixture: Dictionary) -> void:
	fixture.sim.clock.set_paused(false)
	fixture.sim.advance(0.5)
	fixture.sim.clock.set_paused(true)


func _begin_repair(fixture: Dictionary) -> void:
	_expect(fixture.learning.start_fault().ok, "Start from a physically ready automatic system.")
	_expect(fixture.learning.observe_fault().ok, "Record the actual disconnected signal and protected stop.")
	_expect(fixture.learning.diagnose("signal").ok, "Diagnosis follows the observed evidence.")


func _run() -> void:
	directory = "res://tmp/qa/learning-%d-%d" % [OS.get_process_id(), Time.get_ticks_msec()]
	DirAccess.make_dir_recursive_absolute(directory)
	_test_experiment()
	_test_fault()
	await _test_live()
	if failures == 0: print("FIELDWORKS_LEARNING_TESTS_OK ", checks, " checks")
	else: print("FIELDWORKS_LEARNING_TESTS_FAILED ", failures, "/", checks)
	quit(0 if failures == 0 else 1)


func _test_experiment() -> void:
	var f := _fixture()
	_expect(not f.learning.start_fault().ok and not f.learning.apply_to_farm().ok and not f.learning.calibrate().ok, "No task or calibration is awarded without its prerequisites.")
	var initial := _json(f.farm.learning)
	for value in [NAN, INF, -1, 61, true, "20"]:
		_expect(not f.learning.set_conditions(value, "clay", "seated").ok and _json(f.farm.learning) == initial, "Invalid known reference leaves the entire lab unchanged.")
	_expect(not f.learning.set_conditions(20, "unknown", "seated").ok and not f.learning.set_conditions(20, "clay", "unknown").ok and _json(f.farm.learning) == initial, "Unknown response conditions cannot enter the model.")
	var farm_before := _json({"plots": f.farm.plots, "sensor": f.farm.sensor, "cash": f.farm.cash, "engineering": f.farm.engineering, "parts": f.farm.parts_stock, "runtime": f.sim.export_runtime(), "ledger": f.farm.ledger})
	_expect(not f.learning.record_point(1).ok and not f.learning.record_point(2).ok, "B requires A and unknown reference slots are rejected.")
	f.learning.set_conditions(20, "clay", "seated")
	_expect(f.learning.record_point(0).ok, "A records a real raw sensor sample.")
	f.learning.set_conditions(25, "clay", "seated")
	_expect(not f.learning.record_point(1).ok and f.farm.learning.lab.points.size() == 1, "Closely spaced references cannot define the teaching calibration.")
	f.learning.set_conditions(40, "clay", "seated")
	_expect(f.learning.record_point(1).ok and f.learning.calibrate().ok, "Two references solve the calibration and trigger a new midpoint measurement.")
	var lab: Dictionary = f.farm.learning.lab
	_expect(Learning.verified(lab.points, lab.verification) and lab.verification.serial > lab.points[1].serial and lab.verification.truth == 30, "The holdout is a fresh midpoint sample with measurable error improvement.")
	_expect(absf(float(lab.verification.reading) - 30) <= 0.75 and absf(float(lab.verification.factory) - 30) > 4, "Real clay response bias is reduced below the declared tolerance.")
	_expect(_json({"plots": f.farm.plots, "sensor": f.farm.sensor, "cash": f.farm.cash, "engineering": f.farm.engineering, "parts": f.farm.parts_stock, "runtime": f.sim.export_runtime(), "ledger": f.farm.ledger}) == farm_before, "Lab conditions, references and sampling do not affect live water, inventory, cash, weather, time or sensor RNG.")
	_expect(not f.learning.apply_to_farm().ok and f.farm.learning.experiment.is_empty(), "A virtual lab probe does not grant ownership of a field probe.")
	f.economy.buy_modules({"sensor_basic": 1})
	f.probe.install()
	var original_water: float = f.farm.plot_at(Vector2i(10, 8)).moisture
	var sample_count: int = f.farm.sensor.sample_count
	_expect(f.learning.apply_to_farm().ok and f.farm.sensor.sample_count == sample_count + 1 and f.farm.cash == 560, "Explicit sync applies profile and coefficients atomically with one real sample and no free equipment.")
	_expect(f.farm.sensor.cell == [10, 8] and f.farm.sensor.soil == "clay" and f.farm.plot_at(Vector2i(10, 8)).moisture == original_water, "Sync preserves live probe position and actual soil moisture.")
	_expect(Snapshot.validate(f.farm.learning, f.farm, 480).ok, "Experimental proof validates against the shared physical sample format.")
	var proof := _json(f.farm.learning.experiment)
	f.learning.set_conditions(20, "sand", "loose")
	_expect(f.farm.learning.lab.points.is_empty() and f.farm.learning.lab.verification.is_empty() and _json(f.farm.learning.experiment) == proof and Snapshot.validate(f.farm.learning, f.farm, 480).ok, "New response conditions reset current references while preserving completed historical evidence.")
	var events: Array = []
	var callback := func() -> void: events.append(f.learning.sample_now().ok)
	f.farm.learning_changed.connect(callback)
	f.learning.sample_now()
	f.farm.learning_changed.disconnect(callback)
	_expect(events == [false], "Lab edits publish under the shared transaction guard.")


func _test_fault() -> void:
	var f := _fixture(true)
	_expect(f.farm.cash == 115 and f.farm.automation.output, "Real first-game resources cover a complete calibrated automatic kit.")
	_expect(f.learning.start_fault().ok and not f.farm.sensor.connected and not f.farm.automation.output and f.farm.automation.code == "sensor_invalid", "Starting the lesson physically disconnects the probe and triggers protection immediately while paused.")
	_expect(not f.learning.diagnose("signal").ok and not f.learning.start_fault().ok, "Diagnosis cannot skip observation and duplicate starts are rejected.")
	f.sim.clock.set_paused(false)
	f.sim.advance(1)
	f.sim.clock.set_paused(true)
	_expect(f.farm.engineering.delivered_l == 0 and f.learning.observe_fault().ok, "The real fault supplies no water while time advances, and can be observed.")
	_expect(not f.learning.diagnose("water").ok and f.farm.learning.fault.stage == "diagnose", "A water shortage guess cannot satisfy a signal-loss diagnosis.")
	_expect(f.learning.diagnose("signal").ok, "Matching diagnosis unlocks the repair stage.")
	f.probe.set_connected(true)
	_expect(not f.farm.learning.fault.resume.is_empty() and f.farm.learning.fault.stage == "repair", "A new healthy field measurement establishes a restoration checkpoint without completing the task.")
	for _index in range(3):
		f.learning.review()
		f.probe.sample_now()
	_expect(f.farm.learning.fault.stage == "repair", "Repeated checks and paused samples cannot replace physical automatic delivery.")
	f.sim.automation.set_mode("manual")
	_expect(f.farm.learning.fault.resume.is_empty(), "Switching to manual clears the automatic restoration checkpoint.")
	f.engineer.set_enabled(true)
	_step(f)
	var manual_delivery: float = f.farm.engineering.delivered_l
	_expect(manual_delivery > 0 and f.farm.learning.fault.stage == "repair", "Actual manual delivery does not complete automatic recovery.")
	f.sim.automation.set_mode("auto")
	_expect(f.farm.learning.fault.resume.delivered_l == manual_delivery and f.farm.learning.fault.stage == "repair", "Returning to auto starts after the already-consumed manual resources.")
	f.probe.set_connected(false)
	_expect(f.farm.learning.fault.resume.is_empty(), "A second signal failure invalidates restoration evidence.")
	f.probe.set_connected(true)
	f.probe.configure(Vector2i(10, 8), "sand", "seated")
	_expect(f.farm.learning.fault.resume.is_empty(), "Changing response conditions cannot continue an old restoration checkpoint.")
	var base: Dictionary = f.farm.learning.fault.baseline
	f.probe.apply_profile_calibration(base.soil, base.mount, base.slope, base.offset)
	_expect(not f.farm.learning.fault.resume.is_empty() and Snapshot.validate(f.farm.learning, f.farm, f.sim.clock.total_minutes).ok, "Restoring the exact original profile creates a savable fresh checkpoint.")
	_step(f)
	_expect(f.farm.learning.fault.stage == "complete" and f.farm.learning.fault.repair.delivered_l > manual_delivery and f.farm.learning.fault.repair.used_wh > f.farm.learning.fault.resume.used_wh, "A later automatic step with a fresh valid sample and newly consumed water and energy completes recovery.")
	_expect(Snapshot.validate(f.farm.learning, f.farm, f.sim.clock.total_minutes).ok and not f.learning.cancel_fault().ok, "Complete evidence validates and cannot be silently reset as an unfinished lesson.")
	var cancelled := _fixture(true)
	_begin_repair(cancelled)
	_expect(cancelled.learning.cancel_fault().ok and cancelled.farm.sensor.connected and cancelled.farm.learning.fault.stage == "idle" and cancelled.farm.learning.fault.repair.is_empty(), "Cancelling restores signal without awarding task completion.")
	_expect(cancelled.learning.start_fault().ok, "A cancelled unfinished exercise can be attempted again.")
	cancelled.probe.set_connected(true)
	_expect(not cancelled.learning.observe_fault().ok, "Fixing first cannot fabricate a past disconnected observation.")


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


func _save_roundtrip(app: Control, message: String) -> void:
	var before := _json(Codec.capture(app.farm_view))
	var saved: Dictionary = app._save_game()
	_expect(saved.ok, message + " writes validated evidence to disk: " + saved.message)
	var read: Dictionary = app.save_service.read()
	_expect(read.ok, message + " reads a validated candidate.")
	if read.ok:
		app._perform_load(false)
		_expect(_json(Codec.capture(app.farm_view)) == before, message + " restores every field exactly.")


func _test_live() -> void:
	var app := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	app.set_meta("save_path", directory.path_join("farm.json"))
	root.add_child(app)
	var view: Control = app.farm_view
	view.simulation.clock.set_paused(true)
	view.economy.buy_modules({"tank_300": 1, "pump_eco": 1, "battery_180": 1, "pipe": 5, "sensor_basic": 1, "controller_basic": 1})
	for id in ["tank_300", "pump_eco", "battery_180"]: view.engineering.install(id)
	for point in [Vector2i(9, 7), Vector2i(10, 7), Vector2i(11, 7)]: view.engineering.pipe(point)
	view.engineering.refill("tank")
	view.engineering.refill("power")
	view.player.position = Vector2(11.5, 9.5)
	for y in range(8, 10):
		for x in range(10, 13):
			view.tools.select_tool(Tools.Tool.HOE)
			view.tools.use(Vector2i(x, y), view.player.position)
			view.tools.select_seed("lettuce")
			view.tools.use(Vector2i(x, y), view.player.position)
	view.sensor_controller.install()
	await process_frame
	await _button(app.lab_button)
	var panel: Control = app.lab_panel
	_expect(panel.visible and not view.interaction_enabled and view.simulation.clock.paused, "The native L entry opens teaching, locks farm input and preserves pause.")
	for index in range(panel.soil_choice.item_count):
		if panel.soil_choice.get_item_metadata(index) == "clay": panel.soil_choice.select(index)
	await _button(panel.preset_a)
	await _button(panel.point_a_button)
	await _button(panel.preset_b)
	await _button(panel.point_b_button)
	await _button(panel.calibrate_button)
	_expect(not panel.apply_button.disabled and panel.experiment_label.text.contains("复核达标"), "Native reference buttons create visible raw samples and successful independent verification.")
	await _button(panel.apply_button)
	_expect(not view.farm.learning.experiment.is_empty() and view.farm.cash == 107, "The native sync button applies a paid-for probe without changing the 493 coin kit budget.")
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir=") and DisplayServer.get_name() != "headless": await _capture(panel, 0, argument.trim_prefix("--capture-dir="))
	_save_roundtrip(app, "Completed calibration")
	view.simulation.automation.install()
	for pair in [["sensor", "decision"], ["decision", "pump"]]: view.simulation.automation.set_connection(pair[0], 0, pair[1], 0, true)
	view.simulation.automation.set_mode("auto")
	await _tap(KEY_L)
	panel.tabs.current_tab = 1
	await process_frame
	await _button(panel.start_button)
	_expect(view.farm.learning.fault.stage == "observe" and not view.farm.sensor.connected, "Native start produces the real field fault.")
	_save_roundtrip(app, "Unobserved physical fault")
	await _tap(KEY_L)
	await _button(panel.observe_button)
	_expect(view.farm.learning.fault.stage == "diagnose", "Native observation records real protected shutdown.")
	_save_roundtrip(app, "Observed fault")
	await _tap(KEY_L)
	await _button(panel.diagnose_button)
	await _tap(KEY_I)
	_expect(app.sensor_panel.visible and not panel.visible and not view.interaction_enabled and view.simulation.clock.paused, "I navigates directly from teaching to the existing real probe panel without changing pause.")
	await _button(app.sensor_panel.connection_button)
	_expect(view.farm.learning.fault.stage == "repair" and not view.farm.learning.fault.resume.is_empty(), "Repair through the existing native signal control establishes real restoration evidence.")
	_save_roundtrip(app, "Active restoration checkpoint")
	await _tap(KEY_L)
	await _button(panel.verify_button)
	_expect(view.farm.learning.fault.stage == "repair", "The native verify button alone never completes repair.")
	await _button(panel.speed_button)
	var attempts: int = 0
	while view.farm.learning.fault.stage != "complete" and attempts < 200:
		if DisplayServer.get_name() == "headless": view.simulation.advance(0.05)
		else: await create_timer(0.02).timeout
		attempts += 1
	view.simulation.clock.set_paused(true)
	_expect(view.farm.learning.fault.stage == "complete" and panel.status_label.text.contains("已验证完成"), "Normal live feedback after native resume completes the real teaching chain.")
	_save_roundtrip(app, "Completed physical recovery")
	await _tap(KEY_L)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir=") and DisplayServer.get_name() != "headless": await _capture(panel, 1, argument.trim_prefix("--capture-dir="))
	var snapshot := Codec.capture(view)
	for case in ["missing_sample", "fake_delivery", "same_serial", "wrong_diagnosis", "fake_midpoint", "missing_reference", "future_lab_serial", "cup_truth_mismatch"]:
		var invalid: Dictionary = snapshot.duplicate(true)
		match case:
			"missing_sample": invalid.learning.fault.repair.sample = {}
			"fake_delivery": invalid.learning.fault.repair.delivered_l = invalid.learning.fault.resume.delivered_l
			"same_serial": invalid.learning.fault.repair.serial = invalid.learning.fault.resume.serial
			"wrong_diagnosis": invalid.learning.fault.diagnosis = "water"
			"fake_midpoint": invalid.learning.experiment.verification.truth = 20
			"missing_reference": invalid.learning.experiment.points.pop_back()
			"future_lab_serial": invalid.learning.experiment.verification.serial = invalid.learning.lab.sensor.sample_count + 1
			"cup_truth_mismatch": invalid.learning.lab.truth = 5
		_expect(not Codec.validate(invalid).ok and _json(Codec.capture(view)) == _json(snapshot), "Reject impossible teaching evidence before touching live state: " + case)
	var loaded := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	loaded.set_meta("save_path", directory.path_join("farm.json"))
	root.add_child(loaded)
	_expect(loaded.save_service.load_into(loaded.farm_view).ok and _json(Codec.capture(loaded.farm_view)) == _json(snapshot), "A fresh scene reconstructs every completed teaching field without retained controller objects.")
	view.learning.sample_now()
	loaded.farm_view.learning.sample_now()
	_expect(_json(view.farm.learning.lab) == _json(loaded.farm_view.farm.learning.lab), "Lab RNG and future raw measurements continue exactly after reconstruction.")
	await _tap(KEY_ESCAPE)
	_expect(not panel.visible and view.interaction_enabled and view.simulation.clock.paused, "Closing teaching returns farm input and preserves the current pause setting.")
	loaded.queue_free()
	app.queue_free()
	await process_frame


func _capture(panel: Control, tab: int, target: String) -> void:
	panel.tabs.current_tab = tab
	for window_size in [Vector2i(1440, 900), Vector2i(1152, 720)]:
		root.size = window_size
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var file := target.path_join("step-11-%s-%dx%d.png" % ["experiment" if tab == 0 else "fault", window_size.x, window_size.y])
		_expect(root.get_texture().get_image().save_png(file) == OK, "Teaching capture saved: " + file)
		print("FIELDWORKS_LEARNING_CAPTURE_OK ", file)
