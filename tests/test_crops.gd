extends SceneTree
## Complete growth/harvest scenarios and water-stress recovery, not fabricated maturity.

const FarmState = preload("res://scripts/simulation/farm_state.gd")
const Simulation = preload("res://scripts/simulation/farm_simulation.gd")
const CropModel = preload("res://scripts/simulation/crop_model.gd")
const Catalog = preload("res://scripts/simulation/crop_catalog.gd")
const Tools = preload("res://scripts/world/tool_controller.gd")

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("CROP TEST FAILED: " + message)


func _run() -> void:
	_test_water_and_night()
	_test_complete_cycles()
	_test_speed_and_replay()
	await _test_live_farm()
	if failures == 0:
		print("FIELDWORKS_CROP_TESTS_OK ", checks, " checks")
	else:
		print("FIELDWORKS_CROP_TESTS_FAILED ", failures, "/", checks)
	quit(0 if failures == 0 else 1)


func _test_water_and_night() -> void:
	var model := CropModel.new()
	var results: Dictionary = {}
	for setting in [{"id": "normal", "water": 30.0, "day": true}, {"id": "dry", "water": 12.0, "day": true},
		{"id": "wet", "water": 48.0, "day": true}, {"id": "night", "water": 30.0, "day": false},
		{"id": "stopped_dry", "water": 8.0, "day": true}, {"id": "stopped_wet", "water": 55.0, "day": true}]:
		var plot := {"tilled": true, "moisture": setting.water, "crop": CropModel.new_crop("lettuce")}
		for _tick in range(24):
			model.advance(plot, 5, setting.day)
		results[setting.id] = plot
	_expect(results.normal.crop.growth > results.dry.crop.growth and results.dry.crop.growth > 0.0, "Low water slows growth without destroying the crop.")
	_expect(results.normal.crop.growth > results.wet.crop.growth and results.wet.crop.growth > 0.0, "Excess water slows growth.")
	_expect(results.normal.crop.growth > results.night.crop.growth and results.night.crop.growth > 0.0, "Night grows more slowly than daylight.")
	for key in ["stopped_dry", "stopped_wet"]:
		var plot: Dictionary = results[key]
		_expect(plot.crop.growth == 0.0 and model.describe(plot, true).reason.contains("暂停"), "Severe water stress stops growth and is explained: " + key)
		plot.moisture = 30.0
		model.advance(plot, 5, true)
		_expect(plot.crop.growth > 0.0, "Correcting water stress resumes the same crop: " + key)
	var tiny := {"tilled": true, "moisture": 30.0, "crop": CropModel.new_crop("tomato")}
	var before_use := model.transpiration_mm_h(tiny, true)
	for _tick in range(20):
		model.advance(tiny, 5, true)
	_expect(model.transpiration_mm_h(tiny, true) > before_use, "A growing crop uses more water than its seed stage.")
	var base_rates: Array[float] = []
	for id in Catalog.ids():
		var plot := {"tilled": true, "moisture": 30.0, "crop": CropModel.new_crop(id)}
		model.advance(plot, 60, true)
		base_rates.append(plot.crop.growth)
	_expect(base_rates[0] > base_rates[1] and base_rates[1] > base_rates[2], "Configured crop types have distinct growth periods.")


func _test_complete_cycles() -> void:
	for id in Catalog.ids():
		var farm := FarmState.new()
		var simulation := Simulation.new(farm)
		var tools := Tools.new(farm)
		var cell := Vector2i(7, 12)
		var actor := Vector2(7.5, 12.5)
		tools.select_tool(Tools.Tool.HOE)
		tools.use(cell, actor)
		tools.select_seed(id)
		var initial_seeds: int = farm.seed_stock[id]
		_expect(tools.use(cell, actor).ok and farm.seed_stock[id] == initial_seeds - 1, "The complete cycle starts by consuming one seed: " + id)
		tools.select_tool(Tools.Tool.HARVEST)
		_expect(not tools.use(cell, actor).ok and farm.produce_stock[id] == 0, "Premature harvesting cannot produce stock: " + id)
		tools.select_tool(Tools.Tool.WATER)
		tools.use(cell, actor)
		var notifications: Array = []
		simulation.crops_matured.connect(func(cells: Array) -> void: notifications.append_array(cells))
		var seen: Dictionary = {0: true}
		var ticks: int = 0
		while not CropModel.is_mature(farm.plot_at(cell).crop) and ticks < 2304:
			if float(farm.plot_at(cell).moisture) < float(Catalog.definition(id).optimal_min) + 1.0:
				tools.select_tool(Tools.Tool.WATER)
				if farm.watering_charges == 0:
					tools.use(Vector2i(16, 5), Vector2(15.5, 5.5))
				tools.use(cell, actor)
			simulation.advance(0.5)
			seen[CropModel.stage(farm.plot_at(cell).crop)] = true
			ticks += 1
		_expect(CropModel.is_mature(farm.plot_at(cell).crop) and seen.size() == 5, "Natural fixed-step growth passes every stage and matures: " + id)
		_expect(notifications.size() == 1 and notifications[0].crop_id == id, "Maturity is notified once per crop: " + id)
		for _tick in range(24):
			simulation.advance(0.5)
		_expect(farm.plot_at(cell).crop.growth == 1.0 and notifications.size() == 1, "A mature crop remains ready without repeated events: " + id)
		var water_before: float = farm.plot_at(cell).moisture
		tools.select_tool(Tools.Tool.HARVEST)
		_expect(tools.use(cell, actor).ok and farm.produce_stock[id] == int(Catalog.definition(id).harvest_count), "Natural maturity can be harvested into inventory: " + id)
		_expect(farm.plot_at(cell).crop.is_empty() and farm.plot_at(cell).tilled and farm.plot_at(cell).moisture == water_before, "Harvest preserves prepared soil and moisture: " + id)
		var stock: int = farm.produce_stock[id]
		_expect(not tools.use(cell, actor).ok and farm.produce_stock[id] == stock, "Repeated harvesting cannot duplicate produce: " + id)
		tools.select_seed(id)
		_expect(tools.use(cell, actor).ok and farm.plot_at(cell).crop.growth == 0.0, "The harvested plot can start another planting cycle: " + id)


func _planted() -> Simulation:
	var farm := FarmState.new()
	for index in range(3):
		var plot := farm.plot_at(Vector2i(7 + index, 12))
		plot.tilled = true
		plot.moisture = 30.0
		plot.crop = CropModel.new_crop(Catalog.ids()[index])
	return Simulation.new(farm)


func _drain(simulation: Simulation) -> void:
	while simulation.clock.accumulator + simulation.clock.EPSILON >= simulation.clock.REAL_SECONDS_PER_STEP:
		if simulation.advance(0.0) == 0:
			break


func _same_crops(a: FarmState, b: FarmState) -> bool:
	for index in range(a.plots.size()):
		var ca: Dictionary = a.plots[index].crop
		var cb: Dictionary = b.plots[index].crop
		if ca.is_empty() != cb.is_empty(): return false
		if not ca.is_empty() and (ca.id != cb.id or absf(float(ca.growth) - float(cb.growth)) > 0.00000001 or absf(float(ca.age_minutes) - float(cb.age_minutes)) > 0.00000001):
			return false
		if absf(float(a.plots[index].moisture) - float(b.plots[index].moisture)) > 0.00000001:
			return false
	return true


func _test_speed_and_replay() -> void:
	var slow := _planted()
	for _frame in range(720):
		slow.advance(1.0 / 30.0)
	var fast := _planted()
	fast.clock.set_speed(12)
	for _frame in range(288):
		fast.advance(1.0 / 144.0)
	_expect(_same_crops(slow.farm, fast.farm), "The same game time produces identical crop growth and water at 1x/30 FPS and 12x/144 FPS.")
	slow.clock.set_paused(true)
	var paused_snapshot := JSON.stringify(slow.farm.plots)
	slow.advance(1000.0)
	_expect(JSON.stringify(slow.farm.plots) == paused_snapshot, "Pausing freezes crop progress as well as natural water.")
	slow.clock.set_paused(false)
	var restored := _planted()
	restored.farm.plots.assign(JSON.parse_string(JSON.stringify(slow.farm.plots)))
	_expect(restored.restore_runtime(JSON.parse_string(JSON.stringify(slow.export_runtime()))), "A partially grown farm can restore the matching environment runtime.")
	slow.advance(47.25)
	restored.advance(47.25)
	_drain(slow)
	_drain(restored)
	_expect(_same_crops(slow.farm, restored.farm), "Crop state continues identically after a JSON state round trip.")


func _click(point: Vector2) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.pressed = pressed
		root.push_input(event, true)
	await process_frame


func _button(control: Control) -> void:
	await _click(control.get_global_transform_with_canvas() * (control.size / 2.0))


func _cell(view: Control, target: Vector2i) -> void:
	await _click(view.get_global_transform_with_canvas() * view.cell_center(target))


func _test_live_farm() -> void:
	var app := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(app)
	var view: Control = app.farm_view
	view.simulation.clock.set_paused(true)
	await process_frame
	await process_frame
	view.player.position = Vector2(10.5, 9.5)
	for y in range(8, 11):
		for x in range(9, 12):
			var id: String = Catalog.ids()[x - 9]
			await _button(app.tool_bar.tool_buttons[Tools.Tool.HOE])
			await _cell(view, Vector2i(x, y))
			await _button(app.tool_bar.seed_buttons[id])
			await _cell(view, Vector2i(x, y))
			await _button(app.tool_bar.tool_buttons[Tools.Tool.WATER])
			if view.farm.watering_charges == 0:
				view.player.position = Vector2(15.5, 5.5)
				await _cell(view, Vector2i(16, 5))
				view.player.position = Vector2(10.5, 9.5)
			await _cell(view, Vector2i(x, y))
	_expect(view.farm.seed_stock.lettuce == 9 and view.farm.seed_stock.carrot == 5 and view.farm.seed_stock.tomato == 3, "Live planting consumes three seeds of each type.")
	view.selected_cell = Vector2i(11, 9)
	view.simulation.clock.set_speed(12)
	view.simulation.clock.set_paused(false)
	var native: bool = DisplayServer.get_name() != "headless"
	var growing_captured: bool = false
	var capture_directory: String = ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			capture_directory = argument.trim_prefix("--capture-dir=")
	var started := Time.get_ticks_msec()
	var iterations: int = 0
	while not _all_ready(view.farm) and iterations < 700:
		if native:
			if Time.get_ticks_msec() - started > 30000:
				break
			await create_timer(0.03).timeout
		else:
			view.simulation.advance(0.1)
		iterations += 1
		if native and not capture_directory.is_empty() and not growing_captured and float(view.farm.plot_at(Vector2i(9, 9)).crop.growth) >= 0.5:
			await _capture(app, capture_directory.path_join("step-05-growing.png"), Vector2i(1440, 900))
			growing_captured = true
	view.simulation.clock.set_paused(true)
	_expect(_all_ready(view.farm), "All three crops mature through the running farm's natural simulation.")
	_expect(app._growth_bar.visible and app._growth_bar.value == 100.0 and app._selected_title.text.contains("成熟"), "The inspector shows actual maturity and 100 percent progress.")
	if native and not capture_directory.is_empty():
		await _capture(app, capture_directory.path_join("step-05-mature-1440x900.png"), Vector2i(1440, 900))
		await _capture(app, capture_directory.path_join("step-05-mature-1152x720.png"), Vector2i(1152, 720))
	view.player.position = Vector2(10.5, 9.5)
	await _button(app.tool_bar.tool_buttons[Tools.Tool.HARVEST])
	for x in range(9, 12):
		var id: String = Catalog.ids()[x - 9]
		await _cell(view, Vector2i(x, 9))
		_expect(view.farm.produce_stock[id] == 1 and view.farm.plot_at(Vector2i(x, 9)).crop.is_empty(), "Mouse harvest collects a naturally matured crop: " + id)
		await _cell(view, Vector2i(x, 9))
		_expect(view.farm.produce_stock[id] == 1, "Repeated live harvest cannot duplicate stock: " + id)
	_expect(app._produce_label.text.contains("生菜 ×1") and app._produce_label.text.contains("胡萝卜 ×1") and app._produce_label.text.contains("番茄 ×1"), "Visible produce counts match all three successful harvests.")
	if native and not capture_directory.is_empty():
		await _capture(app, capture_directory.path_join("step-05-harvest.png"), Vector2i(1440, 900))
	app.queue_free()
	await process_frame


func _all_ready(farm: FarmState) -> bool:
	for y in range(8, 11):
		for x in range(9, 12):
			if not CropModel.is_mature(farm.plot_at(Vector2i(x, y)).crop):
				return false
	return true


func _capture(_app: Control, path: String, window_size: Vector2i) -> void:
	root.size = window_size
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	_expect(root.get_texture().get_image().save_png(path) == OK, "Crop window capture saved: " + path)
	print("FIELDWORKS_CROP_CAPTURE_OK ", path)
