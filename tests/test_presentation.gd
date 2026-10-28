extends SceneTree

const Presentation = preload("res://scripts/ui/system_presentation.gd")
const CTheme = preload("res://scripts/ui/c_theme.gd")
const Codec = preload("res://scripts/persistence/save_codec.gd")
const Tools = preload("res://scripts/world/tool_controller.gd")
const View = preload("res://scripts/world/farm_view.gd")
var checks: int = 0
var failures: int = 0
var directory: String
var capture_dir: String = ""


func _initialize() -> void:
	_run.call_deferred()


func _expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("PRESENTATION TEST FAILED: " + message)


func _json(value: Variant) -> String:
	return JSON.stringify(value, "", true, true)


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


func _click(point: Vector2) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event, true)
	await process_frame
	await process_frame


func _button(button: Control) -> void:
	await _click(button.get_global_transform_with_canvas() * (button.size / 2))


func _kit(view: Control) -> void:
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
			view.tools.select_seed(["lettuce", "carrot", "tomato"][x - 10])
			view.tools.use(Vector2i(x, y), view.player.position)
	view.sensor_controller.install()
	view.sensor_controller.calibrate(18.0)
	view.simulation.automation.install()
	for pair in [["sensor", "decision"], ["decision", "pump"]]: view.simulation.automation.set_connection(pair[0], 0, pair[1], 0, true)
	view.tools.select_tool(Tools.Tool.INSPECT)


func _run() -> void:
	directory = "res://tmp/qa/presentation-%d-%d" % [OS.get_process_id(), Time.get_ticks_msec()]
	DirAccess.make_dir_recursive_absolute(directory)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="): capture_dir = argument.trim_prefix("--capture-dir=")
	_test_status_priority()
	await _test_native()
	if failures == 0: print("FIELDWORKS_PRESENTATION_TESTS_OK ", checks, " checks")
	else: print("FIELDWORKS_PRESENTATION_TESTS_FAILED ", failures, "/", checks)
	quit(0 if failures == 0 else 1)


func _test_status_priority() -> void:
	var view := View.new()
	view.simulation.clock.set_paused(true)
	_expect(Presentation.describe(view.simulation.irrigation, view.simulation.clock).kind == "idle", "An unbuilt farm does not show a running machine.")
	_kit(view)
	view.engineering.set_enabled(true)
	_expect(Presentation.describe(view.simulation.irrigation, view.simulation.clock).kind == "paused" and Presentation.describe(view.simulation.irrigation, view.simulation.clock).flow_l_h == 0, "A ready manual command while paused displays no actual flow.")
	view.simulation.clock.set_paused(false)
	_expect(Presentation.describe(view.simulation.irrigation, view.simulation.clock).kind == "running", "A physically ready unpaused command displays supply.")
	view.engineering.set_enabled(false)
	_expect(Presentation.describe(view.simulation.irrigation, view.simulation.clock).kind == "stopped", "A healthy explicit stop is neutral rather than a fault.")
	view.engineering.set_enabled(true)
	view.simulation.clock.set_paused(true)
	view.engineering.pipe(Vector2i(10, 7))
	_expect(Presentation.describe(view.simulation.irrigation, view.simulation.clock).kind == "fault", "A real disconnected pipe remains visible as a fault even during pause.")
	view.engineering.pipe(Vector2i(10, 7))
	view.engineering.set_power(false)
	_expect(Presentation.describe(view.simulation.irrigation, view.simulation.clock).kind == "fault", "A real power disconnection uses the same fault language.")
	view.engineering.set_power(true)
	# Isolated display fixtures only; production resource conservation remains unchanged.
	var normal: Dictionary = view.farm.engineering.duplicate(true)
	for field in ["water_l", "energy_wh"]:
		view.farm.engineering[field] = 0.0
		var before := _json(Codec.capture(view))
		var row := Presentation.describe(view.simulation.irrigation, view.simulation.clock)
		_expect(row.kind == "warning" and row.flow_l_h == 0 and row.paused and _json(Codec.capture(view)) == before, "Missing resources are amber and display queries do not mutate physics: " + field)
		view.farm.engineering = normal.duplicate(true)
	view.simulation.automation.set_mode("auto")
	view.sensor_controller.set_connected(false)
	_expect(Presentation.describe(view.simulation.irrigation, view.simulation.clock).kind == "fault", "Invalid automatic measurement overrides normal pause presentation.")
	view.free()


func _navigate_menu(app: Control, source: String, target: String) -> void:
	await _button(app.panel_menus[source])
	var popup: PopupMenu = app.panel_menus[source].get_popup()
	_expect(popup.visible, "The real panel navigation menu opens: " + source)
	for index in range(popup.item_count):
		if popup.get_item_id(index) == target.unicode_at(0): popup.set_focused_item(index)
	await _tap(KEY_ENTER)
	_expect(app._panels()[target].visible and app._panels().values().filter(func(panel: Control) -> bool: return panel.visible).size() == 1, "Native popup activation opens exactly one actual panel: " + target)


func _test_native() -> void:
	var app := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	app.set_meta("save_path", directory.path_join("farm.json"))
	root.add_child(app)
	var view: Control = app.farm_view
	view.simulation.clock.set_paused(true)
	_kit(view)
	await process_frame
	await process_frame
	_expect(not view.action_audio.enabled and view.action_audio.play_count == 0, "Action sound defaults off with no idle playback.")
	view.set_zoom(1)
	var persistent := _json(Codec.capture(view))
	await _button(app.zoom_button)
	await _button(app.sound_button)
	_expect(view.zoom_level == 2 and view.action_audio.enabled and _json(Codec.capture(view)) == persistent, "Zoom and opt-in sound do not change any persisted game field.")
	for window_size in [Vector2i(1440, 900), Vector2i(1152, 720)]:
		root.size = window_size
		await process_frame
		await process_frame
		for zoom in [1, 2]:
			view.set_zoom(zoom)
			for point in [Vector2i(10, 8), Vector2i(12, 9)]:
				await _click(view.get_global_transform_with_canvas() * view.cell_center(point))
				_expect(view.selected_cell == point, "Actual map clicks retain correct coordinates at both zoom levels and window sizes.")
		_expect(view.local_to_cell(Vector2(-1, -1)) == Vector2i(-1, -1), "Clipped space outside the farm cannot select a zoomed tile.")
	view.set_zoom(2)
	view.tools.select_tool(Tools.Tool.HOE)
	var far := Vector2i(14, 9)
	var water_before: float = view.farm.plot_at(far).moisture
	await _click(view.get_global_transform_with_canvas() * view.cell_center(far))
	_expect(not view.farm.plot_at(far).tilled and view.action_audio.play_count == 0 and view.farm.plot_at(far).moisture == water_before, "Zoom never extends tool reach; a failed action has no resource or sound effect.")
	view.tools.use(Vector2i(11, 10), view.player.position)
	_expect(view.action_audio.play_count == 1 and not view.action_audio.clips.hoe.data.is_empty(), "A successful enabled action triggers the real generated audio cue.")
	view.tools.use(Vector2i(11, 10), view.player.position)
	_expect(view.action_audio.play_count == 1, "A rejected repeated hoe action produces no success cue.")
	await _button(app.sound_button)
	view.tools.select_seed("lettuce")
	view.tools.use(Vector2i(11, 10), view.player.position)
	_expect(view.action_audio.play_count == 1 and not view.action_audio.enabled, "Disabling action audio prevents later successful cues.")
	view.engineering.set_enabled(true)
	_expect(view._recent_supply == 0, "A command alone has no observed-flow animation evidence.")
	view.simulation.clock.set_paused(false)
	view.simulation.advance(0.5)
	_expect(view._recent_supply > 0 and view.farm.engineering.delivered_l > 0, "Actual fixed-step delivery triggers the pipe and outlet animation evidence.")
	await _capture("running")
	view.engineering.set_power(false)
	_expect(view._recent_supply == 0, "A real supply fault immediately clears old delivery animation evidence.")
	view.engineering.set_power(true)
	_expect(view._recent_supply == 0, "Repairing a fault cannot reuse a delivery pulse from before the fault.")
	view.simulation.advance(0.5)
	view.simulation.clock.set_paused(true)
	await process_frame
	_expect(view._recent_supply == 0, "Pause immediately removes active water animation evidence.")
	view.simulation.automation.set_mode("auto")
	view.simulation.clock.set_speed(12)
	view.simulation.clock.set_paused(false)
	var attempts: int = 0
	while not view.simulation.crops.is_mature(view.farm.plot_at(Vector2i(10, 8)).crop) and attempts < 1000:
		if DisplayServer.get_name() == "headless": view.simulation.advance(0.05)
		else: await create_timer(0.02).timeout
		attempts += 1
	_expect(view.simulation.crops.is_mature(view.farm.plot_at(Vector2i(10, 8)).crop), "The visual farm includes a naturally matured crop beside slower growing species.")
	view.simulation.clock.set_paused(true)
	await process_frame
	view.tools.select_tool(Tools.Tool.INSPECT)
	await _click(view.get_global_transform_with_canvas() * view.cell_center(Vector2i(10, 8)))
	await _capture("near")
	view.set_zoom(1)
	await _capture("farm")
	view.simulation.clock.set_paused(false)
	await _tap(KEY_E)
	_expect(app.workbench_panel.visible and view.simulation.clock.paused and app.workbench_panel.status_label.text.contains("已暂停"), "The actual workbench shows its temporary pause rather than fake flow.")
	await _capture("workbench")
	await _navigate_menu(app, "E", "I")
	_expect(not view.simulation.clock.paused and not view.interaction_enabled, "Navigating from an editor restores its running state before opening a live observer.")
	await _navigate_menu(app, "I", "B")
	_expect(view.simulation.clock.paused, "The market consistently applies its temporary pause.")
	await _capture("market")
	await _navigate_menu(app, "B", "T")
	_expect(not view.simulation.clock.paused, "Leaving the market for live monitoring restores the original running clock.")
	view.simulation.clock.set_paused(true)
	view.sensor_controller.set_connected(false)
	_expect(app.automation_panel.status_label.get_theme_color("font_color") == CTheme.FAULT and app._engineering_label.get_theme_color("font_color") == CTheme.FAULT, "Main and automatic panels share real fault colors while preserving cause text.")
	await _capture("automation-fault")
	await _tap(KEY_I)
	_expect(app.sensor_panel.visible and app.sensor_panel.converted_label.text.contains("无效"), "The common shortcut opens the actual invalid-measurement panel.")
	await _capture("sensor-fault")
	app.sensor_panel.x_input.get_line_edit().grab_focus()
	await _tap(KEY_T)
	_expect(app.sensor_panel.visible and not app.automation_panel.visible, "Typing in a numerical editor does not invoke unrelated letter navigation.")
	await _tap(KEY_ESCAPE)
	_expect(app.sensor_panel.visible, "First Esc releases numerical editing without closing the panel.")
	await _button(app.sensor_panel.soil_choice)
	_expect(app.sensor_panel.soil_choice.get_popup().visible, "The real soil dropdown opens.")
	var pause_before: bool = view.simulation.clock.paused
	await _tap(KEY_SPACE)
	_expect(view.simulation.clock.paused == pause_before and app.sensor_panel.visible, "An open dropdown cannot pass Space to the farm clock behind it.")
	if not app.sensor_panel.soil_choice.get_popup().visible: await _button(app.sensor_panel.soil_choice)
	await _tap(KEY_ESCAPE)
	_expect(app.sensor_panel.visible and not app.sensor_panel.soil_choice.get_popup().visible, "Esc dismisses the dropdown without also closing the panel behind it.")
	view.sensor_controller.set_connected(true)
	await _tap(KEY_L)
	await _capture("lab")
	await _tap(KEY_H)
	await _capture("route")
	await _tap(KEY_ESCAPE)
	view.set_zoom(2)
	_expect(app._save_game().ok and app.save_service.read().ok, "The unchanged v6 format still saves the complete game after presentation changes.")
	app._perform_load(false)
	_expect(view.zoom_level == 2 and view.interaction_enabled, "Loading preserves the current near view without changing the game save format.")
	app.queue_free()
	await process_frame


func _capture(label: String) -> void:
	if capture_dir.is_empty() or DisplayServer.get_name() == "headless": return
	for window_size in [Vector2i(1440, 900), Vector2i(1152, 720)]:
		root.size = window_size
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var path := capture_dir.path_join("step-13-%s-%dx%d.png" % [label, window_size.x, window_size.y])
		_expect(root.get_texture().get_image().save_png(path) == OK, "Presentation capture saved: " + path)
		print("FIELDWORKS_PRESENTATION_CAPTURE_OK ", path)
