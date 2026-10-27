extends RefCounted
## Explicit CLI acceptance mode: production scene/resources, isolated disk slot only.

const Codec = preload("res://scripts/persistence/save_codec.gd")
const Tools = preload("res://scripts/world/tool_controller.gd")
const Network = preload("res://scripts/engineering/irrigation_network.gd")
var app: Control
var directory: String
var checks: int = 0
var failures: int = 0
var exit_action_seen: bool = false


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("RELEASE ACCEPTANCE FAILED: " + message)


func _state() -> String:
	return JSON.stringify(Codec.capture(app.farm_view), "", true, true)


func _write_json(name: String, value: Variant) -> void:
	var file := FileAccess.open(directory.path_join(name), FileAccess.WRITE)
	_expect(file != null, "Open isolated verification output: " + name)
	if file != null:
		file.store_string(JSON.stringify(value, "", true, true))
		file.close()


func _tap(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
	await app.get_tree().process_frame
	await app.get_tree().process_frame


func _press_now(button: Control) -> void:
	var point := button.get_global_transform_with_canvas() * (button.size / 2)
	if button.get_viewport() is Window and button.get_viewport() != app.get_tree().root:
		point += Vector2((button.get_viewport() as Window).position)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		app.get_tree().root.push_input(event, true)


func _button(button: Control) -> void:
	await app.get_tree().process_frame
	await app.get_tree().process_frame
	_press_now(button)
	await app.get_tree().process_frame
	await app.get_tree().process_frame


func _use(point: Vector2i, tool: int) -> void:
	var view: Control = app.farm_view
	view.player.position = Vector2(point) + Vector2.ONE * 0.5
	view.tools.select_tool(tool)
	_expect(view.tools.use(point, view.player.position).changed, "Successful legal tool operation at " + str(point))


func _advance_until(condition: Callable, limit: int = 1800) -> void:
	var view: Control = app.farm_view
	view.simulation.clock.set_speed(12)
	view.simulation.clock.set_paused(false)
	var count: int = 0
	while not condition.call() and count < limit:
		view.simulation.advance(0.05)
		count += 1
	view.simulation.clock.set_paused(true)
	_expect(condition.call(), "Actual fixed steps reach the required crop / supply / teaching state.")


func _capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await app.get_tree().process_frame
	await RenderingServer.frame_post_draw
	_expect(app.get_viewport().get_texture().get_image().save_png(directory.path_join(name + ".png")) == OK, "Native release screenshot: " + name)


func run(application: Control, target: String, phase: String) -> void:
	app = application
	directory = target
	app.farm_view.simulation.clock.set_paused(true)
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		push_error("Cannot create isolated release verification directory.")
		app.get_tree().quit(1)
		return
	await app.get_tree().process_frame
	await app.get_tree().process_frame
	_expect(app.save_service.path == directory.path_join("farm-v6.json"), "Verification never uses the player's default slot.")
	if phase == "write": await _write_route()
	elif phase == "read": await _read_route()
	else: await _exit_route(phase)
	_write_json("result-" + phase + ".json", {"phase": phase, "checks": checks + 1, "failures": failures, "engine": Engine.get_version_info().string, "render": DisplayServer.get_name()})
	if failures == 0: print("FIELDWORKS_RELEASE_", phase.to_upper().replace("-", "_"), "_OK ", checks, " checks")
	app.get_tree().quit(0 if failures == 0 else 1)


func _write_route() -> void:
	if app.save_service.exists():
		_expect(false, "Writer requires a fresh isolated slot; refuse to overwrite.")
		return
	var view: Control = app.farm_view
	for name in ["automation", "crops", "economy", "learning_tasks", "modules", "sensor", "tutorial"]:
		_expect(JSON.parse_string(FileAccess.get_file_as_string("res://data/" + name + ".json")) is Dictionary, "Pack contains JSON configuration: " + name)
	_expect(ResourceLoader.exists("res://assets/icon.svg"), "Imported icon is present in the exported pack.")
	if not OS.has_feature("editor"):
		_expect(not FileAccess.file_exists("res://tests/test_tutorial.gd") and not FileAccess.file_exists("res://田野工程师_Fieldworks_项目总结.pdf"), "Developer tests and source PDF are excluded from the game pack.")
	var font: Font = app.theme.default_font
	_expect(font.has_char("田".unicode_at(0)) and font.has_char("灌".unicode_at(0)), "Chinese UI font has actual glyph coverage on this Windows host.")
	_use(Vector2i(7, 12), Tools.Tool.HOE)
	_use(Vector2i(7, 12), Tools.Tool.SOW)
	_use(Vector2i(7, 12), Tools.Tool.WATER)
	_advance_until(func() -> bool: return view.simulation.crops.is_mature(view.farm.plot_at(Vector2i(7, 12)).crop))
	_use(Vector2i(7, 12), Tools.Tool.HARVEST)
	await _tap(KEY_B)
	await _button(app.market_panel.sell_one.lettuce)
	await _button(app.market_panel.buy_one.lettuce)
	_expect(view.farm.cash == 612 and app.market_panel.visible, "Actual market buttons complete the 18-coin sale and 6-coin restock.")
	await _tap(KEY_ESCAPE)
	_expect(view.economy.buy_modules({"tank_300": 1, "pump_eco": 1, "battery_180": 1, "pipe": 5, "sensor_basic": 1, "controller_basic": 1}).ok, "Purchase real engineering stock.")
	for id in ["tank_300", "pump_eco", "battery_180"]: _expect(view.engineering.install(id).ok, "Install purchased device: " + id)
	for point in Network.STARTER_ROUTE: _expect(view.engineering.pipe(point).ok, "Place a connected pipe.")
	_expect(view.engineering.refill("tank").ok and view.engineering.refill("power").ok, "Pay for water and energy.")
	_use(Vector2i(10, 8), Tools.Tool.HOE)
	view.engineering.set_enabled(true)
	_advance_until(func() -> bool: return view.farm.journey.modes.manual.liters > 0, 30)
	view.engineering.set_enabled(false)
	_expect(view.sensor_controller.install().ok and view.simulation.automation.install().ok, "Install purchased probe and controller.")
	view.learning.set_conditions(20.0, "clay", "seated")
	_expect(view.learning.record_point(0).ok, "Record known 20 percent reference.")
	view.learning.set_conditions(40.0, "clay", "seated")
	_expect(view.learning.record_point(1).ok and view.learning.calibrate().ok and view.learning.apply_to_farm().ok, "Calibrate and explicitly sync the verified real probe.")
	for pair in [["sensor", "decision"], ["decision", "pump"]]:
		_expect(view.simulation.automation.set_connection(pair[0], 0, pair[1], 0, true).ok, "Connect actual automatic graph.")
	view.simulation.automation.set_mode("auto")
	_advance_until(func() -> bool: return view.farm.journey.modes.auto.liters > 0, 50)
	_expect(view.farm.cash == 119, "Trade and complete 493-coin kit reconcile in the release build.")
	_expect(view.learning.start_fault().ok and not view.simulation.irrigation.status().running, "Real signal failure protects the pump.")
	_expect(view.learning.observe_fault().ok and view.learning.diagnose("signal").ok, "Observe and diagnose from actual fault evidence.")
	view.sensor_controller.set_connected(true)
	_advance_until(func() -> bool: return view.farm.learning.fault.stage == "complete", 50)
	_expect(view.tutorial.begin_improvement().ok, "Begin independent adjustment after verified recovery.")
	var reading: float = view.simulation.sensor.current(view.simulation.clock.total_minutes).reading
	view.simulation.automation.set_thresholds(reading + 0.5, reading + 5)
	_advance_until(func() -> bool: return not view.farm.journey.improvement.proof.is_empty(), 50)
	_expect(view.tutorial.current().id == "complete", "All nine evidence-backed route objectives complete in the exported game.")
	for pair in [[KEY_E, app.workbench_panel], [KEY_I, app.sensor_panel], [KEY_T, app.automation_panel], [KEY_L, app.lab_panel], [KEY_H, app.tutorial_panel]]:
		await _tap(pair[0])
		_expect(pair[1].visible, "Exported UI opens actual panel: " + str(pair[0]))
		await _tap(KEY_ESCAPE)
	await _tap(KEY_H)
	await _capture("release-route-1440x900")
	app.get_window().size = Vector2i(1152, 720)
	await _capture("release-route-1152x720")
	await _tap(KEY_ESCAPE)
	app.get_window().size = Vector2i(1440, 900)
	await _tap(KEY_F)
	await _capture("release-farm-1440x900")
	_expect(view.farm.automation.output and view.farm.automation.latch and view.simulation.irrigation.status().running, "Save an actually running automatic latch, not just an installed idle system.")
	_expect(app._save_game().ok, "Save completed route from the production UI.")
	_write_json("expected.json", {"before": _state()})
	app._request_quit()
	_expect(not app.quit_dialog.visible, "A just-saved paused farm exits without a false dirty prompt.")


func _read_route() -> void:
	var file := directory.path_join("expected.json")
	if not FileAccess.file_exists(file):
		_expect(false, "Reader requires the writer's verification evidence.")
		return
	var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(file))
	app._perform_load(false)
	_expect(_state() == expected.before, "Every persistent field survives a new release process.")
	var view: Control = app.farm_view
	_expect(view.tutorial.current().id == "complete" and view.farm.learning.fault.stage == "complete", "Teaching and independent adjustment remain complete.")
	_expect(view.farm.automation.output and view.farm.automation.latch and view.simulation.irrigation.status().running, "Running automatic latch and physical supply survive a new release process.")
	var delivered: float = view.farm.engineering.delivered_l
	_advance_until(func() -> bool: return view.farm.engineering.delivered_l > delivered, 30)
	_expect(view.farm.journey.modes.auto.wh > 0 and view.simulation.sensor.current(view.simulation.clock.total_minutes).valid, "Actual automatic water, energy and valid sensing continue after restart.")
	app._request_quit()
	_expect(app.quit_dialog.visible, "Unsaved continued play opens the exit confirmation.")
	await _button(app.quit_dialog.get_cancel_button())
	_expect(not app.quit_dialog.visible and view.interaction_enabled, "Actual Cancel returns to the farm.")
	await _capture("release-resumed-1440x900")


func _exit_route(phase: String) -> void:
	var view: Control = app.farm_view
	if phase == "quit-save":
		if app.save_service.exists():
			_expect(false, "Save-and-quit requires a fresh isolated slot.")
			return
		_use(Vector2i(7, 12), Tools.Tool.HOE)
		_write_json("expected-exit.json", {"before": _state()})
		app._request_quit()
		_expect(app.quit_dialog.visible, "Dirty farm prompts before save-and-quit.")
		await app.get_tree().process_frame
		await app.get_tree().process_frame
		app.quit_dialog.confirmed.connect(func() -> void: exit_action_seen = true)
		_press_now(app.quit_dialog.get_ok_button())
		_expect(exit_action_seen, "Actual Save-and-quit button emits its confirmation action.")
		_expect(app.save_service.exists(), "Actual Save-and-quit button writes a valid slot.")
	else:
		app._perform_load(false)
		var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("expected-exit.json")))
		_expect(_state() == expected.before, "Save-and-quit round-trip preserves the farm exactly.")
		var original := FileAccess.get_file_as_bytes(app.save_service.path)
		_use(Vector2i(8, 12), Tools.Tool.HOE)
		app._request_quit()
		await app.get_tree().process_frame
		await app.get_tree().process_frame
		var discard: Button
		for child in app.quit_dialog.find_children("*", "Button", true, false):
			if child.text == "不保存退出": discard = child
		_expect(discard != null, "Explicit discard exit action exists.")
		app.quit_dialog.custom_action.connect(func(action: StringName) -> void: exit_action_seen = action == &"discard")
		if discard != null: _press_now(discard)
		_expect(exit_action_seen, "Actual Discard button emits the explicit discard action.")
		_expect(FileAccess.get_file_as_bytes(app.save_service.path) == original, "Actual discard does not overwrite the saved farm.")
