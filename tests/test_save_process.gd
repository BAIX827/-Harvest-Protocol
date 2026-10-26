extends SceneTree
## Run writer and reader in separate Godot processes; no live objects survive.

const Service = preload("res://scripts/persistence/save_service.gd")
const Codec = preload("res://scripts/persistence/save_codec.gd")
const Tools = preload("res://scripts/world/tool_controller.gd")
var failures: int = 0
var checks: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("SAVE PROCESS TEST FAILED: " + message)


func _state(view: Control) -> String:
	return JSON.stringify(Codec.capture(view), "", true, true)


func _future(view: Control) -> void:
	view.simulation.clock.set_speed(12)
	view.simulation.clock.set_paused(false)
	for _index in range(100): view.simulation.advance(0.1)
	view.simulation.clock.set_paused(true)


func _run() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.size() != 2 or arguments[0] not in ["write", "read"]:
		push_error("Expected: -- write|read isolated-directory")
		quit(1)
		return
	var directory: String = arguments[1]
	var app := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	app.set_meta("save_path", directory.path_join("farm.json"))
	root.add_child(app)
	var view: Control = app.farm_view
	view.simulation.clock.set_paused(true)
	var service := Service.new(directory.path_join("farm.json"))
	var expected_path := directory.path_join("expected.json")
	if arguments[0] == "write":
		_expect(view.economy.buy_seeds("lettuce", 5).ok, "Buy seeds before planting.")
		view.player.position = Vector2(8.5, 12.5)
		for index in range(3):
			var cell := Vector2i(7 + index, 12)
			view.tools.select_tool(Tools.Tool.HOE)
			view.tools.use(cell, view.player.position)
			view.tools.select_seed(["lettuce", "carrot", "tomato"][index])
			view.tools.use(cell, view.player.position)
			view.tools.select_tool(Tools.Tool.WATER)
			_expect(view.tools.use(cell, view.player.position).changed, "Legitimate planting and watering.")
		view.simulation.clock.set_speed(12)
		view.simulation.clock.set_paused(false)
		var iterations: int = 0
		while not view.simulation.crops.is_mature(view.farm.plot_at(Vector2i(7, 12)).crop) and iterations < 600:
			view.simulation.advance(0.1)
			iterations += 1
		view.simulation.clock.set_paused(true)
		view.tools.select_tool(Tools.Tool.HARVEST)
		_expect(view.tools.use(Vector2i(7, 12), view.player.position).changed, "Harvest naturally matured lettuce.")
		_expect(view.economy.sell_produce("lettuce", 1).ok, "Sell the harvested crop.")
		view.player.position = Vector2(15.7, 5.5)
		view.tools.select_tool(Tools.Tool.WATER)
		_expect(view.tools.use(Vector2i(16, 5), view.player.position).changed, "Refill the can and record its cost.")
		view.player.position = Vector2(8.5, 12.5)
		view.selected_cell = Vector2i(8, 12)
		view.show_grid = true
		_expect(service.save(view).ok, "Write the complete farming and trading history.")
		var expected := {"before": _state(view)}
		_future(view)
		expected.after = _state(view)
		var file := FileAccess.open(expected_path, FileAccess.WRITE)
		file.store_string(JSON.stringify(expected))
		file.close()
	else:
		var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(expected_path))
		_expect(service.load_into(view).ok, "Load after a new operating-system process starts.")
		_expect(_state(view) == expected.before, "All persisted fields match the terminated writer.")
		_expect(view.farm.ledger.size() == 4 and view.farm.cash == 586 and view.farm.watering_charges == 8, "Purchase, sale and refill history remain reconciled.")
		_expect(not view.farm.plot_at(Vector2i(8, 12)).crop.is_empty() and not view.farm.plot_at(Vector2i(9, 12)).crop.is_empty(), "Unharvested crops remain in the field.")
		_future(view)
		_expect(_state(view) == expected.after, "Future weather, growth and moisture match the terminated writer.")
	if failures == 0: print("FIELDWORKS_SAVE_PROCESS_", arguments[0].to_upper(), "_OK ", checks, " checks")
	app.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
