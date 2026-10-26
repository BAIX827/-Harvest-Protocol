extends SceneTree
## Time partitioning, ordered weather boundaries and replay are behaviour contracts.

const FarmState = preload("res://scripts/simulation/farm_state.gd")
const Clock = preload("res://scripts/simulation/simulation_clock.gd")
const Weather = preload("res://scripts/simulation/weather_model.gd")
const Simulation = preload("res://scripts/simulation/farm_simulation.gd")

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("SIMULATION TEST FAILED: " + message)


func _run() -> void:
	_test_clock()
	_test_equivalent_time()
	_test_weather_and_water()
	_test_runtime_replay()
	await _test_live_controls()
	if failures == 0:
		print("FIELDWORKS_SIMULATION_TESTS_OK ", checks, " checks")
	else:
		print("FIELDWORKS_SIMULATION_TESTS_FAILED ", failures, "/", checks)
	quit(0 if failures == 0 else 1)


func _drain(simulation: Simulation) -> void:
	while simulation.clock.accumulator + Clock.EPSILON >= Clock.REAL_SECONDS_PER_STEP:
		if simulation.advance(0.0) == 0:
			break


func _same_water(a: FarmState, b: FarmState) -> bool:
	for index in range(a.plots.size()):
		if absf(float(a.plots[index].moisture) - float(b.plots[index].moisture)) > 0.00000001:
			return false
	return true


func _at(minutes: int, kind: int) -> Simulation:
	var simulation := Simulation.new(FarmState.new())
	var weather := Weather.new(Weather.DEFAULT_SEED, minutes)
	weather.kind = kind
	var snapshot := simulation.export_runtime()
	snapshot.clock.total_minutes = minutes
	snapshot.weather = weather.export_state()
	simulation.restore_runtime(snapshot)
	return simulation


func _test_clock() -> void:
	var clock := Clock.new()
	_expect(clock.advance(0.49) == 0 and clock.total_minutes == 480, "A partial step does not advance the calendar.")
	_expect(clock.advance(0.01) == 1 and clock.total_minutes == 485, "One full fixed step advances exactly five minutes.")
	clock.advance(0.25)
	clock.set_paused(true)
	var snapshot := clock.export_state()
	_expect(clock.advance(100.0) == 0 and clock.export_state() == snapshot, "Pause preserves time and the existing fractional step.")
	clock.set_paused(false)
	_expect(clock.advance(0.25) == 1, "Resume completes the preserved fraction without including paused time.")
	var before := clock.export_state()
	for invalid in [-1.0, INF, NAN]:
		_expect(clock.advance(invalid) == 0 and clock.export_state() == before, "Invalid real-time input is ignored.")
	clock.set_speed(0)
	_expect(clock.speed == 1, "Only supported positive speeds are accepted.")
	var capped := Clock.new()
	var events: Array[int] = []
	capped.stepped.connect(func(_minutes: int, end_minutes: int) -> void: events.append(end_minutes))
	_expect(capped.advance(100.0) == Clock.MAX_STEPS_PER_FRAME and capped.accumulator > 0.0, "A long frame retains work beyond its per-frame budget.")
	while capped.accumulator + Clock.EPSILON >= Clock.REAL_SECONDS_PER_STEP:
		capped.advance(0.0)
	_expect(capped.tick_count == 200 and capped.total_minutes == 1480, "Draining a long frame loses no simulation steps.")
	_expect(events.size() == 200 and events[0] == 485 and events[-1] == 1480, "Every drained fixed step emits its ordered timestamp.")
	var next_day := _at(1435, Weather.Kind.CLEAR)
	next_day.advance(0.5)
	_expect(next_day.clock.day() == 2 and next_day.clock.time_text() == "00:00", "Midnight rolls the day and clock over exactly.")
	_expect(next_day.clock.period_name() == "夜间" and next_day.night_opacity() > 0.0, "Night presentation follows simulation time.")


func _test_equivalent_time() -> void:
	var baseline := Simulation.new(FarmState.new())
	for _frame in range(720):
		baseline.advance(1.0 / 30.0)
	_expect(baseline.clock.total_minutes == 720, "Twenty-four real seconds at 1x reach the first noon.")
	for configuration in [{"speed": 1, "fps": 144, "seconds": 24}, {"speed": 4, "fps": 30, "seconds": 6}, {"speed": 12, "fps": 60, "seconds": 2}]:
		var candidate := Simulation.new(FarmState.new())
		candidate.clock.set_speed(configuration.speed)
		for _frame in range(configuration.fps * configuration.seconds):
			candidate.advance(1.0 / float(configuration.fps))
		_drain(candidate)
		_expect(candidate.clock.total_minutes == baseline.clock.total_minutes and candidate.clock.tick_count == baseline.clock.tick_count, "Speed/frame partition gives the same fixed-step count: %s" % configuration)
		_expect(candidate.weather.export_state() == baseline.weather.export_state() and _same_water(candidate.farm, baseline.farm), "Speed/frame partition gives identical weather and soil: %s" % configuration)


func _test_weather_and_water() -> void:
	var cell := Vector2i(8, 8)
	var boundary := _at(715, Weather.Kind.CLEAR)
	boundary.farm.plot_at(cell).tilled = true
	var contexts: Array[Dictionary] = []
	boundary.step_completed.connect(func(context: Dictionary) -> void: contexts.append(context))
	boundary.advance(0.5)
	var after_sun: float = boundary.farm.plot_at(cell).moisture
	_expect(after_sun < 18.0 and boundary.weather.kind == Weather.Kind.RAIN, "11:55 to 12:00 uses the old sun, then exposes noon rain.")
	boundary.advance(0.5)
	_expect(float(boundary.farm.plot_at(cell).moisture) > after_sun, "The next interval receives actual rain infiltration.")
	_expect(contexts.size() == 2 and contexts[0].weather_kind == Weather.Kind.CLEAR and contexts[1].weather_kind == Weather.Kind.RAIN, "Step subscribers receive the weather of each applied interval.")
	var day := _at(480, Weather.Kind.CLEAR)
	var night := _at(1320, Weather.Kind.CLEAR)
	day.advance(0.5)
	night.advance(0.5)
	_expect(float(night.farm.plot_at(cell).moisture) > float(day.farm.plot_at(cell).moisture), "Clear nights evaporate less water than clear days.")
	var covered := _at(480, Weather.Kind.CLEAR)
	covered.farm.plot_at(cell).tilled = true
	covered.advance(0.5)
	_expect(float(covered.farm.plot_at(cell).moisture) < float(covered.farm.plot_at(Vector2i(9, 8)).moisture), "Exposed tilled soil dries faster than covered soil.")
	var wet := _at(480, Weather.Kind.RAIN)
	wet.farm.plot_at(cell).moisture = 60.0
	_expect(float(wet.water_rates_at(cell).drainage) > 0.0, "Water above field capacity produces drainage.")
	wet.advance(0.5)
	_expect(float(wet.farm.plot_at(cell).moisture) <= FarmState.MAX_MOISTURE, "Rain cannot raise moisture beyond the model ceiling.")
	var dry := _at(480, Weather.Kind.CLEAR)
	dry.farm.plot_at(cell).moisture = 0.001
	dry.advance(0.5)
	_expect(dry.farm.plot_at(cell).moisture == 0.0, "Evaporation cannot make moisture negative.")
	_expect(dry.farm.plot_at(Vector2i(6, 13)).moisture == 18.0, "Non-arable terrain does not acquire simulated soil changes.")
	var paused := Simulation.new(FarmState.new())
	paused.clock.set_paused(true)
	var before := JSON.stringify({"runtime": paused.export_runtime(), "plots": paused.farm.plots})
	paused.advance(999.0)
	_expect(JSON.stringify({"runtime": paused.export_runtime(), "plots": paused.farm.plots}) == before, "An idle paused farm preserves weather and every soil cell.")
	var weather_a := Weather.new(123456)
	var weather_b := Weather.new(123456)
	for block in range(3, 20):
		weather_a.ensure_period(block * 360)
		weather_b.ensure_period(block * 360)
	_expect(weather_a.export_state() == weather_b.export_state(), "Equal seeds reproduce the weather stream.")
	var weather_c := Weather.new(654321)
	weather_c.ensure_period(19 * 360)
	_expect(weather_c.export_state().rng_state != weather_a.export_state().rng_state, "Different seeds retain independent random streams.")


func _test_runtime_replay() -> void:
	var original := Simulation.new(FarmState.new())
	original.clock.set_speed(4)
	original.advance(36.125)
	_drain(original)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(original.export_runtime()))
	var restored := Simulation.new(FarmState.new())
	restored.farm.plots = original.farm.plots.duplicate(true)
	_expect(restored.restore_runtime(saved), "JSON restores clock fractions and the exact 64-bit weather state.")
	original.advance(23.75)
	restored.advance(23.75)
	_drain(original)
	_drain(restored)
	_expect(original.clock.total_minutes == restored.clock.total_minutes and original.weather.export_state() == restored.weather.export_state(), "Restored runtime continues with the same calendar and future weather.")
	_expect(_same_water(original.farm, restored.farm), "Restored runtime continues with identical moisture in every plot.")
	var before := JSON.stringify(restored.export_runtime())
	var invalid := restored.export_runtime()
	invalid.weather.period_index = 999
	_expect(not restored.restore_runtime(invalid) and JSON.stringify(restored.export_runtime()) == before, "A mismatched calendar/weather snapshot is rejected without mutation.")
	invalid = restored.export_runtime()
	invalid.clock.accumulator = -1.0
	_expect(not restored.restore_runtime(invalid) and JSON.stringify(restored.export_runtime()) == before, "Invalid clock state cannot partially restore the environment.")


func _click(control: Control) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = control.get_global_transform_with_canvas() * (control.size / 2.0)
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event, true)
	await process_frame


func _space() -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = KEY_SPACE
		event.physical_keycode = KEY_SPACE
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()


func _test_live_controls() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var app := scene.instantiate()
	root.add_child(app)
	app.farm_view.simulation.clock.set_paused(true)
	await process_frame
	await process_frame
	var simulation: Simulation = app.farm_view.simulation
	var initial := simulation.clock.total_minutes
	_space()
	await create_timer(0.65).timeout
	_expect(not simulation.clock.paused and simulation.clock.total_minutes > initial, "Space resumes the live farm and normal frames advance time.")
	_space()
	await process_frame
	initial = simulation.clock.total_minutes
	await create_timer(0.55).timeout
	_expect(simulation.clock.paused and simulation.clock.total_minutes == initial and app.time_bar.pause_button.text.contains("继续"), "Space pauses the live farm and updates the button.")
	await _click(app.time_bar.speed_buttons[4])
	_expect(not simulation.clock.paused and simulation.clock.speed == 4, "Clicking 4x resumes simulation at that speed.")
	await create_timer(0.25).timeout
	_expect(simulation.clock.total_minutes > initial and app.time_bar.clock_label.text.contains(simulation.clock.time_text()), "The displayed clock follows the running simulation.")
	await _click(app.time_bar.pause_button)
	_expect(simulation.clock.paused, "The pause button stops natural updates.")
	await _click(app.time_bar.speed_buttons[12])
	_space()
	var active_count: int = 0
	for button in app.time_bar.speed_buttons.values():
		if button.button_pressed:
			active_count += 1
	_expect(simulation.clock.speed == 12 and simulation.clock.paused and active_count == 1, "Speed selection stays synchronized when paused again.")
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir=") and DisplayServer.get_name() != "headless":
			await _capture_weather(app, argument.trim_prefix("--capture-dir="))
	app.queue_free()
	await process_frame


func _capture_weather(app: Control, directory: String) -> void:
	var view: Control = app.farm_view
	var cell := Vector2i(7, 12)
	view.player.position = Vector2(7.5, 12.5)
	view.tools.select_tool(view.ToolController.Tool.HOE)
	view.tools.use(cell, view.player.position)
	view.tools.select_seed("lettuce")
	view.tools.use(cell, view.player.position)
	view.tools.select_tool(view.ToolController.Tool.WATER)
	view.tools.use(cell, view.player.position)
	view.selected_cell = cell
	# Fast-forward through the real environment steps to the teaching rain.
	view.simulation.clock.set_paused(false)
	view.simulation.clock.set_speed(12)
	while view.simulation.clock.total_minutes < 780:
		view.simulation.advance(minf(0.1, float(780 - view.simulation.clock.total_minutes) / 120.0))
	view.simulation.clock.set_paused(true)
	for window_size in [Vector2i(1440, 900), Vector2i(1152, 720)]:
		root.size = window_size
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var path := directory.path_join("step-04-rain-%dx%d.png" % [window_size.x, window_size.y])
		_expect(root.get_texture().get_image().save_png(path) == OK, "Rain capture saved: " + path)
		print("FIELDWORKS_SIMULATION_CAPTURE_OK ", path)
	view.simulation.clock.set_paused(false)
	while view.simulation.clock.total_minutes < 1260:
		view.simulation.advance(minf(0.1, float(1260 - view.simulation.clock.total_minutes) / 120.0))
	view.simulation.clock.set_paused(true)
	root.size = Vector2i(1440, 900)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var night_path := directory.path_join("step-04-night.png")
	_expect(root.get_texture().get_image().save_png(night_path) == OK, "Night capture saved.")
	print("FIELDWORKS_SIMULATION_CAPTURE_OK ", night_path)
