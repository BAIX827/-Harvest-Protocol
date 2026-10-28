extends SceneTree
## Behavioural checks: solids, movement and picking through the real viewport.

const FarmState = preload("res://scripts/simulation/farm_state.gd")
const Player = preload("res://scripts/world/player.gd")

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("WORLD TEST FAILED: " + message)


func _run() -> void:
	var farm := FarmState.new()
	_expect(farm.tiles.size() == 576, "The farm contains 24 by 24 cells.")
	_expect(farm.is_walkable(Vector2i(6, 13)), "The farm entrance is walkable.")
	_expect(farm.is_arable(Vector2i(8, 8)), "The trial field is arable.")
	_expect(not farm.is_arable(Vector2i(6, 13)), "A road is not arable.")
	for point in [Vector2i(-1, 12), Vector2i(24, 12), Vector2i(12, -1), Vector2i(12, 24),
		Vector2i(0, 12), Vector2i(23, 12), Vector2i(12, 0), Vector2i(12, 23),
		Vector2i(3, 4), Vector2i(18, 5), Vector2i(3, 8), Vector2i(2, 10)]:
		_expect(not farm.is_walkable(point), "Solid or outside cell is not walkable: %s" % point)
	_test_movement(farm)
	await _test_viewport_picking()
	if failures == 0:
		print("FIELDWORKS_WORLD_TESTS_OK ", checks, " checks")
	else:
		print("FIELDWORKS_WORLD_TESTS_FAILED ", failures, "/", checks)
	quit(0 if failures == 0 else 1)


func _test_movement(farm: FarmState) -> void:
	var straight := Player.new(Vector2(10.5, 13.5))
	var diagonal := Player.new(Vector2(10.5, 13.5))
	straight.advance(Vector2.RIGHT, 0.1, farm)
	diagonal.advance(Vector2.ONE, 0.1, farm)
	_expect(is_equal_approx(straight.position.distance_to(Vector2(10.5, 13.5)), diagonal.position.distance_to(Vector2(10.5, 13.5))), "Diagonal travel does not increase speed.")
	var idle := straight.position
	straight.advance(Vector2.ZERO, 1.0, farm)
	_expect(straight.position == idle and not straight.moving, "Releasing movement stops the character.")
	var walker := Player.new(Vector2(6.25, 4.5))
	for _step in range(120):
		walker.advance(Vector2.LEFT, 1.0 / 60.0, farm)
	_expect(walker.position.x >= 6.22 and walker.position.x < 6.3, "The player footprint stops at the farmhouse wall.")
	_expect(walker.can_stand_at(walker.position, farm), "Wall collision leaves the player in a legal position.")
	var before_slide := walker.position
	for _step in range(10):
		walker.advance(Vector2(-1, 1), 1.0 / 60.0, farm)
	_expect(walker.position.y > before_slide.y and walker.position.x >= 6.22, "Diagonal movement slides along the house wall.")
	var pond_walker := Player.new(Vector2(15.5, 5.5))
	for _step in range(120):
		pond_walker.advance(Vector2.RIGHT, 1.0 / 60.0, farm)
	_expect(pond_walker.position.x < 16.0 and pond_walker.can_stand_at(pond_walker.position, farm), "The pond blocks the entire player footprint.")
	for direction in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		var edge_walker := Player.new(Vector2(6.5, 13.5))
		for _step in range(300):
			edge_walker.advance(direction, 0.25, farm)
		_expect(edge_walker.can_stand_at(edge_walker.position, farm), "Continuous movement cannot cross a map boundary: %s" % direction)
	var stalled := Player.new(Vector2(6.25, 4.5))
	stalled.advance(Vector2.LEFT, 10.0, farm)
	_expect(stalled.position.x >= 6.22, "A long frame cannot tunnel through a building.")


func _test_viewport_picking() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var app := scene.instantiate()
	root.add_child(app)
	app.farm_view.simulation.clock.set_paused(true)
	await process_frame
	await process_frame
	var view: Control = app.farm_view
	if DisplayServer.get_name() != "headless":
		await _test_keyboard_routing(app)
	# This scenario clicks every corner of the farm; near-view picking is covered separately.
	view.set_zoom(1)
	for viewport_size in [Vector2i(1600, 1000), Vector2i(1280, 800), Vector2i(1152, 720)]:
		root.size = viewport_size
		await process_frame
		await process_frame
		for target in [Vector2i(8, 8), Vector2i(3, 4), Vector2i(18, 5), Vector2i(23, 23)]:
			var point: Vector2 = view.get_global_transform_with_canvas() * view.cell_center(target)
			var press := InputEventMouseButton.new()
			press.button_index = MOUSE_BUTTON_LEFT
			press.pressed = true
			press.position = point
			root.push_input(press, true)
			var release := InputEventMouseButton.new()
			release.button_index = MOUSE_BUTTON_LEFT
			release.pressed = false
			release.position = point
			root.push_input(release, true)
			await process_frame
			_expect(view.selected_cell == target, "Viewport click selects the intended tile at %s: %s" % [viewport_size, target])
			_expect(app._selected_title.text == view.farm.describe(target).name, "The inspector follows the selected terrain.")
		var previous: Vector2i = view.selected_cell
		var outside := InputEventMouseButton.new()
		outside.button_index = MOUSE_BUTTON_LEFT
		outside.pressed = true
		outside.position = view.get_global_transform_with_canvas() * Vector2(1, 1)
		root.push_input(outside, true)
		_expect(view.selected_cell == previous, "Letterbox padding is not a farm cell.")
		outside.pressed = false
		root.push_input(outside, true)
	view.reset_player()
	_expect(view.player.position == FarmState.SPAWN, "Return to entrance restores a safe position.")
	app.queue_free()
	await process_frame


func _send_key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _test_keyboard_routing(app: Control) -> void:
	Engine.max_fps = 60
	root.grab_focus()
	await create_timer(0.1).timeout
	_expect(root.has_focus(), "The graphical window has input focus.")
	var view: Control = app.farm_view
	view.reset_player()
	view.grab_focus()
	var initial: Vector2 = view.player.position
	_send_key(KEY_D, true)
	await create_timer(0.3).timeout
	_expect(Input.is_action_pressed("farm_right"), "The physical D key reaches the right-movement action.")
	_expect(view.player.position.x > initial.x + 0.3, "The physical D key moves the character through the running scene.")
	_send_key(KEY_D, false)
	await process_frame
	var stopped: Vector2 = view.player.position
	await create_timer(0.1).timeout
	_expect(view.player.position.is_equal_approx(stopped), "Releasing D stops movement in the live scene.")
	_send_key(KEY_UP, true)
	await create_timer(0.2).timeout
	_send_key(KEY_UP, false)
	_expect(view.player.position.y < stopped.y - 0.2, "The up arrow also moves the live character.")
	var grid_before: bool = view.show_grid
	_send_key(KEY_G, true)
	_send_key(KEY_G, false)
	await process_frame
	_expect(view.show_grid != grid_before, "G toggles the grid while the map has focus.")
	_send_key(KEY_R, true)
	_send_key(KEY_R, false)
	await process_frame
	_expect(view.player.position == FarmState.SPAWN, "R returns the live character to the entrance.")
	view.player.position = Vector2(6.25, 4.5)
	_send_key(KEY_A, true)
	await create_timer(0.2).timeout
	_send_key(KEY_A, false)
	_expect(view.player.position.x >= 6.22, "Keyboard movement in the live scene cannot pass through the house.")
	view.reset_player()
	print("FIELDWORKS_NATIVE_INPUT_OK")
