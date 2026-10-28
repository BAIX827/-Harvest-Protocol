extends SceneTree
## Regression scenarios from the actual player report; all saves are isolated.

const Tools = preload("res://scripts/world/tool_controller.gd")
const Codec = preload("res://scripts/persistence/save_codec.gd")
const Network = preload("res://scripts/engineering/irrigation_network.gd")
var checks: int = 0
var failures: int = 0
var capture_dir: String = ""
var directory: String

func _initialize() -> void:
	_run.call_deferred()

func _expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("PLAYTEST FEEDBACK FAILED: " + message)

func _tap(logical: Key, physical: Key = KEY_TAB) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = logical
		event.physical_keycode = physical
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
	await process_frame
	await process_frame

func _button(button: Control) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = button.get_global_transform_with_canvas() * (button.size / 2)
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event, true)
	await process_frame
	await process_frame

func _run() -> void:
	directory = "res://tmp/qa/feedback-%d-%d" % [OS.get_process_id(), Time.get_ticks_msec()]
	DirAccess.make_dir_recursive_absolute(directory)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="): capture_dir = argument.trim_prefix("--capture-dir=")
	var app: Control = load("res://scenes/main.tscn").instantiate()
	app.set_meta("save_path", directory.path_join("farm.json"))
	root.add_child(app)
	var view: Control = app.farm_view
	view.simulation.clock.set_paused(true)
	await process_frame
	await process_frame
	_expect(view.zoom_level == 2 and view.selected_cell == Vector2i(7, 12), "A fresh farm opens near the reachable entrance plot.")
	_expect(not app._milestone_label.visible, "Opening a fresh farm does not announce an achievement.")
	await _capture("entrance")
	await _tap(KEY_F)
	_expect(view.zoom_level == 1, "Logical F with the captured wrong physical Tab code toggles once.")
	await _tap(KEY_F, KEY_NONE)
	_expect(view.zoom_level == 2, "A logical-only key also works.")
	await _tap(KEY_2)
	_expect(view.tools.active_tool == Tools.Tool.HOE, "Logical tool selection works with a mismatched physical code.")
	await _tap(KEY_3, KEY_3)
	_expect(view.tools.active_tool == Tools.Tool.SOW, "Normal physical and logical keys still select tools.")
	await _tap(KEY_NONE, KEY_2)
	_expect(view.tools.active_tool == Tools.Tool.HOE, "A physical-only event retains the original fallback.")
	for code in [KEY_W, KEY_UP]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = KEY_TAB
		event.pressed = true
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		_expect(Input.get_vector("farm_left", "farm_right", "farm_up", "farm_down").y < 0, "Logical movement reaches the actual InputMap for " + str(code))
		var released := event.duplicate() as InputEventKey
		released.pressed = false
		Input.parse_input_event(released)
		Input.flush_buffered_events()
		_expect(Input.get_vector("farm_left", "farm_right", "farm_up", "farm_down").is_zero_approx(), "Movement releases without sticking.")
	await _tap(KEY_SPACE)
	_expect(not view.simulation.clock.paused, "Logical Space resumes the clock.")
	await _tap(KEY_SPACE)
	_expect(view.simulation.clock.paused, "Logical Space pauses once.")
	if DisplayServer.get_name() != "headless":
		root.grab_focus()
		await create_timer(0.1).timeout
		var initial: Vector2 = view.player.position
		var held := InputEventKey.new()
		held.keycode = KEY_UP
		held.physical_keycode = KEY_TAB
		held.pressed = true
		Input.parse_input_event(held)
		await create_timer(0.3).timeout
		_expect(view.player.position.y < initial.y - 0.2, "A sustained logical Up with wrong physical code moves the live character.")
		var released := held.duplicate() as InputEventKey
		released.pressed = false
		Input.parse_input_event(released)
		await process_frame
		view.reset_player()
	var point := Vector2i(7, 12)
	view.tools.select_tool(Tools.Tool.HOE)
	_expect(view.tools.use(point, view.player.position).ok, "The entrance plot remains reachable in near view.")
	_expect(view.tutorial.hint().contains("播种"), "After tilling, the next step is sowing.")
	view.tools.select_seed("lettuce")
	view.tools.use(point, view.player.position)
	var plot: Dictionary = view.farm.plot_at(point)
	# Explicit moisture fixtures reproduce dry, reported wet, rain-soaked conditions.
	for moisture in [18.0, 37.1, 49.0]:
		plot.moisture = moisture
		var before := JSON.stringify(Codec.capture(view))
		var hint: String = view.tutorial.hint()
		_expect(hint.contains("浇一次") if moisture == 18 else hint.contains("现在不用浇水") and hint.contains("≤26%"), "Care guidance matches actual moisture " + str(moisture))
		_expect(JSON.stringify(Codec.capture(view)) == before, "Reading guidance never waters or awards progress.")
	plot.moisture = 37.1
	view.farm.plot_changed.emit(point)
	app._refresh_guidance()
	await _capture("wet-care")
	plot.moisture = 18.0
	view.tools.select_tool(Tools.Tool.WATER)
	view.tools.use(point, view.player.position)
	_expect(plot.moisture == 30.0 and view.farm.watering_charges == 7, "A real dry-start watering reaches the suitable range and consumes one charge.")
	_expect(app._milestone_label.visible and app._milestone_label.text.contains("第一块田"), "Actual work displays its stage completion.")
	view.simulation.clock.set_speed(12)
	view.simulation.clock.set_paused(false)
	for _index in range(1500):
		if view.simulation.crops.is_mature(plot.crop): break
		view.simulation.advance(0.05)
	view.simulation.clock.set_paused(true)
	_expect(view.simulation.crops.is_mature(plot.crop), "The first crop matures through the production simulation.")
	view.tools.select_tool(Tools.Tool.HARVEST)
	view.tools.use(point, view.player.position)
	_expect(app._milestone_label.text.contains("收获") and view.farm.produce_stock.lettuce == 1, "Harvest feedback accompanies a real inventory increase.")
	view.economy.sell_produce("lettuce", 1)
	view.economy.buy_seeds("lettuce", 1)
	_expect(view.farm.cash == 612, "The first-sale budget is unchanged.")
	_expect(view.tutorial.current().id == "manual" and view.tutorial.hint().contains("水箱"), "The engineering stage starts with one missing module.")
	view.engineering.buy("tank_120")
	_expect(view.tutorial.hint().contains("安装库存"), "Owned equipment is installed before buying more.")
	view.engineering.install("tank_120")
	_expect(view.tutorial.hint().contains("水泵"), "After tank installation, the next missing module is the pump.")
	for id in ["pump_eco", "battery_60"]:
		view.engineering.buy(id)
		view.engineering.install(id)
	_expect(view.tutorial.hint().contains("采购 5 段"), "Missing pipes are shown after the modules.")
	view.engineering.buy("pipe", 5)
	for cell in Network.STARTER_ROUTE:
		_expect(view.tutorial.hint().contains("(%d,%d)" % [cell.x + 1, cell.y + 1]), "Each missing route cell is identified.")
		view.engineering.pipe(cell)
	_expect(view.tutorial.hint().contains("补满水箱"), "A connected dry system asks for water.")
	view.engineering.refill("tank")
	_expect(view.tutorial.hint().contains("充满电池"), "Water is followed by missing energy.")
	view.engineering.refill("power")
	_expect(view.tutorial.hint().contains("翻一块地"), "No-demand protection sends the player back to a real field.")
	await _tap(KEY_E)
	_expect(app.workbench_panel.visible and app.workbench_panel.next_label.text.contains("翻一块地"), "The workbench repeats the actual missing prerequisite.")
	_expect(not app.workbench_panel.plan_label.visible and app.workbench_panel.status_label.visible, "Principle details collapse while real status remains visible.")
	await _capture("assembly")
	await _button(app.workbench_panel.details_button)
	_expect(app.workbench_panel.plan_label.visible, "Players can expand equipment performance details.")
	await _tap(KEY_L)
	_expect(app.lab_panel.visible and app.lab_panel.next_label.text.contains("参考 A"), "The experiment starts at one reference step.")
	_expect(not app.lab_panel.experiment_label.text.contains("ADC"), "Raw signals are initially collapsed.")
	await _capture("lab")
	await _button(app.lab_panel.details_button)
	_expect(app.lab_panel.details_button.text.begins_with("收起"), "The raw-signal disclosure opens by mouse.")
	view.learning.set_conditions(20.0, "clay", "seated")
	view.learning.record_point(0)
	_expect(app.lab_panel.next_label.text.contains("参考 B"), "Reference A advances guidance to reference B.")
	view.learning.set_conditions(40.0, "clay", "seated")
	view.learning.record_point(1)
	_expect(app.lab_panel.next_label.text.contains("中点"), "Two references advance guidance to midpoint verification.")
	view.learning.calibrate()
	_expect(app.lab_panel.next_label.text.contains("安装真实探头"), "Verified cups still require an installed real probe.")
	view.engineering.buy("sensor_basic")
	view.sensor_controller.install()
	_expect(app.lab_panel.next_label.text.contains("同步条件"), "An installed probe allows explicit synchronization.")
	view.learning.apply_to_farm()
	_expect(not view.farm.learning.experiment.is_empty(), "The calibration target still requires real synchronization.")
	await _tap(KEY_T)
	_expect(app.automation_panel.next_label.text.contains("采购控制器"), "The automatic panel starts with its missing controller.")
	view.engineering.buy("controller_basic")
	view.simulation.automation.install()
	_expect(app.automation_panel.next_label.text.contains("探头 → 判断"), "Automatic wiring guidance identifies the first missing edge.")
	view.simulation.automation.set_connection("sensor", 0, "decision", 0, true)
	_expect(app.automation_panel.next_label.text.contains("判断 → 水泵"), "Automatic wiring advances to the second missing edge.")
	view.simulation.automation.set_connection("decision", 0, "pump", 0, true)
	_expect(app.automation_panel.next_label.text.contains("翻土地"), "A wired graph still explains the actual uncovered probe.")
	await _capture("automatic")
	var probe: Vector2i = view.simulation.sensor.point()
	view.tools.select_tool(Tools.Tool.HOE)
	view.tools.use(probe, Vector2(probe) + Vector2.ONE * 0.5)
	view.sensor_controller.set_connected(false)
	_expect(app.automation_panel.next_label.text.contains("信号"), "An invalid live probe retains its specific signal cause in guidance.")
	view.sensor_controller.set_connected(true)
	_expect(app.automation_panel.next_label.text.contains("选择自动模式"), "A ready live system explains the remaining mode switch.")
	view.farm.plot_at(probe).moisture = 60.0
	_expect(view.tutorial.manual_hint().contains("已达水分上限"), "Already saturated tilled land is allowed to drain instead of being told to till it again.")
	await _tap(KEY_I)
	app.sensor_panel.x_input.get_line_edit().grab_focus()
	await _tap(KEY_T)
	_expect(app.sensor_panel.visible and not app.automation_panel.visible, "Logical shortcuts cannot escape a numerical editor.")
	await _tap(KEY_ESCAPE)
	_expect(app.sensor_panel.visible, "First Escape only releases editing.")
	await _button(app.sensor_panel.soil_choice)
	await _tap(KEY_SPACE)
	_expect(view.simulation.clock.paused, "Space inside a dropdown cannot resume simulation behind it.")
	await _tap(KEY_ESCAPE)
	_expect(app.sensor_panel.visible, "Dropdown Escape does not also close its panel.")
	await _tap(KEY_ESCAPE)
	view.set_zoom(2)
	_expect(app._save_game().ok, "Updated UI saves to an isolated v6 slot.")
	app._perform_load(false)
	_expect(view.zoom_level == 2 and not app._milestone_label.visible, "Loading preserves near view and never reannounces saved achievements.")
	view.set_zoom(1)
	app._perform_load(false)
	_expect(view.zoom_level == 1, "A player's full-map session choice also survives loading.")
	await _tap(KEY_H)
	await _capture("route")
	app.queue_free()
	await process_frame
	print("FIELDWORKS_PLAYTEST_FEEDBACK_%s %d checks" % ["OK" if failures == 0 else "FAILED", checks])
	quit(0 if failures == 0 else 1)

func _capture(label: String) -> void:
	if capture_dir.is_empty() or DisplayServer.get_name() == "headless": return
	for window_size in [Vector2i(1440, 900), Vector2i(1152, 720)]:
		root.size = window_size
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		_expect(root.get_texture().get_image().save_png(capture_dir.path_join("feedback-%s-%dx%d.png" % [label, window_size.x, window_size.y])) == OK, "Native screenshot saved: " + label)
