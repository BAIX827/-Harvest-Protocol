extends SceneTree
## Verify resource preservation on rejected actions and the real toolbar/map route.

const FarmState = preload("res://scripts/simulation/farm_state.gd")
const ToolController = preload("res://scripts/world/tool_controller.gd")

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("TOOLS TEST FAILED: " + message)


func _snapshot(farm: FarmState) -> String:
	return JSON.stringify({"plots": farm.plots, "seeds": farm.seed_stock, "produce": farm.produce_stock, "water": farm.watering_charges})


func _reject(tools: ToolController, target: Vector2i, actor: Vector2, code: String) -> void:
	var before := _snapshot(tools.farm)
	var result := tools.use(target, actor)
	_expect(not result.ok and not result.changed and result.code == code, "Rejected action explains its reason: " + code)
	_expect(_snapshot(tools.farm) == before, "A rejected action preserves all plots and supplies: " + code)


func _run() -> void:
	_test_cultivation_contract()
	_test_water_and_invalid_targets()
	await _test_scene_interaction()
	if failures == 0:
		print("FIELDWORKS_TOOLS_TESTS_OK ", checks, " checks")
	else:
		print("FIELDWORKS_TOOLS_TESTS_FAILED ", failures, "/", checks)
	quit(0 if failures == 0 else 1)


func _test_cultivation_contract() -> void:
	var farm := FarmState.new()
	var tools := ToolController.new(farm)
	var cell := Vector2i(7, 12)
	var actor := Vector2(7.5, 12.5)
	tools.select_seed("lettuce")
	_reject(tools, cell, actor, "untilled")
	tools.select_tool(ToolController.Tool.HOE)
	_expect(tools.use(cell, actor).ok and farm.plot_at(cell).tilled, "Hoeing prepares an arable plot.")
	_reject(tools, cell, actor, "already_tilled")
	tools.select_seed("lettuce")
	_expect(tools.use(cell, actor).ok, "Sowing succeeds on a prepared empty plot.")
	_expect(farm.plot_at(cell).crop.id == "lettuce" and farm.seed_stock.lettuce == 11, "A planted seed and exactly one seed deduction are committed together.")
	_expect(farm.plot_at(cell).crop.growth == 0.0, "Sowing does not fabricate a grown crop.")
	_reject(tools, cell, actor, "occupied")
	tools.select_tool(ToolController.Tool.HOE)
	_reject(tools, cell, actor, "occupied")
	tools.select_tool(ToolController.Tool.WATER)
	_expect(tools.use(cell, actor).ok, "A prepared crop can be watered.")
	_expect(farm.plot_at(cell).moisture == 30.0 and farm.watering_charges == 7, "Watering changes actual moisture and spends one can charge.")
	for _index in range(3):
		tools.use(cell, actor)
	_expect(farm.plot_at(cell).moisture == FarmState.MAX_MOISTURE, "Manual watering clamps at the model's moisture ceiling.")
	_reject(tools, cell, actor, "wet_enough")
	tools.select_tool(ToolController.Tool.HARVEST)
	_reject(tools, cell, actor, "not_mature")
	# A future growth-system fixture verifies the harvest interface, not a playable growth feature.
	farm.plot_at(cell).crop.growth = 1.0
	_expect(tools.use(cell, actor).ok and farm.produce_stock.lettuce == 1, "A mature-state fixture is collected into authoritative produce storage.")
	_expect(farm.plot_at(cell).crop.is_empty() and farm.plot_at(cell).tilled and farm.plot_at(cell).moisture == 60.0, "Harvest clears only the crop and preserves prepared soil and water.")
	_reject(tools, cell, actor, "no_crop")
	for crop_id in ["carrot", "tomato"]:
		tools.select_seed(crop_id)
		var initial: int = farm.seed_stock[crop_id]
		_expect(tools.use(cell, actor).ok and farm.plot_at(cell).crop.id == crop_id and farm.seed_stock[crop_id] == initial - 1, "Seed selection plants the chosen crop: " + crop_id)
		farm.plot_at(cell).crop = {}
	farm.seed_stock.lettuce = 0
	tools.select_seed("lettuce")
	_reject(tools, cell, actor, "no_seed")


func _test_water_and_invalid_targets() -> void:
	var farm := FarmState.new()
	var tools := ToolController.new(farm)
	var near := Vector2(7.5, 12.5)
	for tool in [ToolController.Tool.HOE, ToolController.Tool.SOW, ToolController.Tool.WATER, ToolController.Tool.HARVEST]:
		tools.select_tool(tool)
		_reject(tools, Vector2i(-1, 12), near, "outside")
		_reject(tools, Vector2i(20, 20), near, "too_far")
		_reject(tools, Vector2i(6, 13), near, "not_arable")
	tools.select_tool(ToolController.Tool.HOE)
	_reject(tools, Vector2i(5, 4), Vector2(6.5, 4.5), "not_arable")
	_reject(tools, Vector2i(16, 5), Vector2(15.5, 5.5), "not_arable")
	_reject(tools, Vector2i(4, 8), Vector2(3.5, 7.75), "blocked")
	tools.select_tool(ToolController.Tool.WATER)
	_reject(tools, Vector2i(7, 12), near, "untilled")
	farm.plot_at(Vector2i(7, 12)).tilled = true
	farm.watering_charges = 0
	_reject(tools, Vector2i(7, 12), near, "can_empty")
	_reject(tools, Vector2i(16, 5), near, "too_far")
	_expect(tools.use(Vector2i(16, 5), Vector2(15.5, 5.5)).ok and farm.watering_charges == FarmState.CAN_CAPACITY, "Refilling at an accessible pond edge restores the can.")
	_reject(tools, Vector2i(16, 5), Vector2(15.5, 5.5), "can_full")
	tools.select_tool(ToolController.Tool.INSPECT)
	var before := _snapshot(farm)
	_expect(tools.use(Vector2i(18, 5), near).ok and _snapshot(farm) == before, "Inspection works remotely without changing the farm.")


func _send_key(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = code
		event.keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()


func _click(point: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = button
		event.position = point
		event.pressed = pressed
		root.push_input(event, true)
	await process_frame


func _click_cell(view: Control, cell: Vector2i, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	await _click(view.get_global_transform_with_canvas() * view.cell_center(cell), button)


func _click_control(control: Control) -> void:
	await _click(control.get_global_transform_with_canvas() * (control.size / 2.0))


func _test_scene_interaction() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var app := scene.instantiate()
	root.add_child(app)
	app.farm_view.simulation.clock.set_paused(true)
	await process_frame
	await process_frame
	var view: Control = app.farm_view
	var cell := Vector2i(7, 12)
	view.player.position = Vector2(7.5, 12.5)
	view.grab_focus()
	_send_key(KEY_2)
	await _click_cell(view, cell)
	_expect(view.farm.plot_at(cell).tilled and app._plot_details.text.contains("已翻土"), "Keyboard tool selection and map clicks prepare soil and refresh the inspector.")
	await _click_control(app.tool_bar.seed_buttons.carrot)
	_expect(view.tools.active_tool == ToolController.Tool.SOW and view.tools.selected_seed == "carrot", "Clicking a seed choice selects that crop and the sow tool.")
	await _click_cell(view, cell)
	_expect(view.farm.plot_at(cell).crop.id == "carrot" and view.farm.seed_stock.carrot == 7, "The real map route plants the chosen seed exactly once.")
	_expect(app.tool_bar.seed_buttons.carrot.text.contains("×7") and app._plot_details.text.contains("胡萝卜"), "Toolbar stock and inspector agree with the planted crop.")
	var before := _snapshot(view.farm)
	await _click_cell(view, cell)
	_expect(_snapshot(view.farm) == before and app._feedback_label.text.contains("不能重复播种"), "A repeated map click does not consume another seed.")
	await _click_cell(view, Vector2i(8, 12), MOUSE_BUTTON_RIGHT)
	_expect(not view.farm.plot_at(Vector2i(8, 12)).tilled and _snapshot(view.farm) == before, "Right-click inspects without using the active tool.")
	_send_key(KEY_4)
	await _click_cell(view, cell)
	_expect(view.farm.plot_at(cell).moisture == 30.0 and app.tool_bar._water_label.text.contains("7/8"), "Watering through the view updates soil and the can display.")
	_send_key(KEY_5)
	await _click_cell(view, cell)
	_expect(view.farm.plot_at(cell).crop.id == "carrot" and app._feedback_label.text.contains("尚未成熟"), "The harvest tool preserves an immature crop and explains why.")
	_send_key(KEY_1)
	_send_key(KEY_Q)
	_expect(view.tools.selected_seed == "tomato" and view.tools.active_tool == ToolController.Tool.SOW, "Q cycles seeds and selects the sow tool.")
	for index in range(app.tool_bar.tool_buttons.size()):
		await _click_control(app.tool_bar.tool_buttons[index])
		var pressed_count: int = 0
		for button in app.tool_bar.tool_buttons:
			if button.button_pressed:
				pressed_count += 1
		_expect(view.tools.active_tool == index and pressed_count == 1, "Mouse and keyboard selection keep one active tool: %d" % index)
	_send_key(KEY_4)
	view.player.position = Vector2(15.5, 5.5)
	await _click_cell(view, Vector2i(16, 5))
	_expect(view.farm.watering_charges == 8 and app.tool_bar._water_label.text.contains("8/8"), "Refilling through the map updates the visible can amount.")
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir=") and DisplayServer.get_name() != "headless":
			await _capture_cultivation(app, argument.trim_prefix("--capture-dir="))
	app.queue_free()
	await process_frame


func _capture_cultivation(app: Control, directory: String) -> void:
	var view: Control = app.farm_view
	view.player.position = Vector2(8.5, 12.5)
	for index in range(2):
		var target := Vector2i(8 + index, 12)
		view.tools.select_tool(ToolController.Tool.HOE)
		await _click_cell(view, target)
		await _click_control(app.tool_bar.seed_buttons["lettuce" if index == 0 else "tomato"])
		await _click_cell(view, target)
		view.tools.select_tool(ToolController.Tool.WATER)
		await _click_cell(view, target)
	for window_size in [Vector2i(1440, 900), Vector2i(1152, 720)]:
		root.size = window_size
		await process_frame
		await process_frame
		await _click_cell(view, Vector2i(9, 12), MOUSE_BUTTON_RIGHT)
		await RenderingServer.frame_post_draw
		var path := directory.path_join("step-03-%dx%d.png" % [window_size.x, window_size.y])
		_expect(root.get_texture().get_image().save_png(path) == OK, "Graphical cultivation capture is saved: " + path)
		print("FIELDWORKS_TOOLS_CAPTURE_OK ", path)
