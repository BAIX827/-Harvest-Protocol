extends Control
## The same geometry drives drawing, mouse picking and the player projection.

signal tile_selected(cell: Vector2i)
signal hovered_cell_changed(cell: Vector2i)
signal player_moved(cell: Vector2i)
signal feedback(message: String)
signal presentation_changed
signal player_position_changed
signal view_controls_changed

const FarmState = preload("res://scripts/simulation/farm_state.gd")
const Player = preload("res://scripts/world/player.gd")
const ToolController = preload("res://scripts/world/tool_controller.gd")
const FarmSimulation = preload("res://scripts/simulation/farm_simulation.gd")
const Economy = preload("res://scripts/simulation/economy_model.gd")
const Engineering = preload("res://scripts/engineering/engineering_controller.gd")
const SensorController = preload("res://scripts/engineering/sensor_controller.gd")
const LearningController = preload("res://scripts/progression/learning_controller.gd")
const TutorialController = preload("res://scripts/progression/tutorial_controller.gd")
const ActionAudio = preload("res://scripts/ui/action_audio.gd")
const Presentation = preload("res://scripts/ui/system_presentation.gd")
const CTheme = preload("res://scripts/ui/c_theme.gd")
const TILE: float = 32.0

var farm := FarmState.new()
var player := Player.new(FarmState.SPAWN)
var simulation := FarmSimulation.new(farm)
var economy := Economy.new(farm, simulation.clock)
var tools := ToolController.new(farm, economy)
var engineering := Engineering.new(economy, simulation.irrigation)
var sensor_controller := SensorController.new(economy, simulation.sensor)
var learning := LearningController.new(farm, sensor_controller, simulation)
var tutorial := TutorialController.new(farm, simulation, economy)
var action_audio := ActionAudio.new()
var zoom_level: int = 1
var interaction_enabled: bool = true
var selected_cell := Vector2i(8, 8)
var hovered_cell := FarmState.INVALID_CELL
var show_grid: bool = false
var _last_player_cell := FarmState.INVALID_CELL
var _blocked_cooldown: float = 0.0
var _action_flash_remaining: float = 0.0
var _action_cell := FarmState.INVALID_CELL
var _action_ok: bool = false
var _rain_animation: float = 0.0
var _flow_phase: float = 0.0
var _recent_supply: float = 0.0
var _action_code: String = ""


func _init() -> void:
	add_child(action_audio)


func _ready() -> void:
	clip_contents = true
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(_on_resized)
	mouse_exited.connect(_clear_hover)
	_register_input()
	farm.plot_changed.connect(_on_plot_changed)
	tools.action_completed.connect(_on_action_completed)
	tools.selection_changed.connect(_on_tool_changed)
	simulation.updated.connect(_on_environment_changed)
	simulation.crops_matured.connect(_on_crops_matured)
	simulation.clock.controls_changed.connect(func() -> void:
		if simulation.clock.paused: _recent_supply = 0.0
		queue_redraw())
	simulation.step_completed.connect(func(context: Dictionary) -> void:
		if float(context.supplied_l) > 0.0: _recent_supply = 0.7)
	farm.engineering_changed.connect(_refresh_machine_visual)
	farm.sensor_changed.connect(_refresh_machine_visual)
	farm.automation_changed.connect(_refresh_machine_visual)
	queue_redraw()


func _refresh_machine_visual() -> void:
	if simulation.clock.paused or not simulation.irrigation.status().running: _recent_supply = 0.0
	queue_redraw()


func _register_input() -> void:
	var bindings := {
		"farm_left": [KEY_A, KEY_LEFT], "farm_right": [KEY_D, KEY_RIGHT],
		"farm_up": [KEY_W, KEY_UP], "farm_down": [KEY_S, KEY_DOWN],
	}
	for action in bindings:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for code in bindings[action]:
			var key := InputEventKey.new()
			key.physical_keycode = code
			InputMap.action_add_event(action, key)


func geometry() -> Rect2:
	var cell_size := maxf(1.0, floorf(minf(size.x - 32.0, size.y - 32.0) / 24.0)) * zoom_level
	var extent := Vector2.ONE * cell_size * 24.0
	var origin := ((size - extent) / 2.0).floor()
	if zoom_level > 1:
		var centered := size / 2.0 - player.position * cell_size
		origin.x = clampf(centered.x, size.x - extent.x - 16, 16) if extent.x > size.x - 32 else origin.x
		origin.y = clampf(centered.y, size.y - extent.y - 16, 16) if extent.y > size.y - 32 else origin.y
	return Rect2(origin.floor(), extent)


func local_to_cell(point: Vector2) -> Vector2i:
	if not Rect2(Vector2.ZERO, size).has_point(point): return FarmState.INVALID_CELL
	var rect := geometry()
	if not rect.has_point(point):
		return FarmState.INVALID_CELL
	var local := (point - rect.position) / (rect.size.x / 24.0)
	var result := Vector2i(floori(local.x), floori(local.y))
	return result if farm.contains(result) else FarmState.INVALID_CELL


func cell_center(cell: Vector2i) -> Vector2:
	var rect := geometry()
	return rect.position + (Vector2(cell) + Vector2.ONE * 0.5) * rect.size.x / 24.0


func _gui_input(event: InputEvent) -> void:
	if not interaction_enabled:
		accept_event()
		return
	if event is InputEventMouseMotion:
		_update_hover(event.position)
	elif event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		set_zoom(2 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1)
		accept_event()
	elif event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT] and event.pressed:
		var cell := local_to_cell(event.position)
		if farm.contains(cell):
			selected_cell = cell
			presentation_changed.emit()
			grab_focus()
			tile_selected.emit(cell)
			if event.button_index == MOUSE_BUTTON_LEFT:
				tools.use(cell, player.position)
			queue_redraw()
		accept_event()


func _unhandled_key_input(event: InputEvent) -> void:
	if not interaction_enabled:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode >= KEY_1 and event.physical_keycode <= KEY_5:
			tools.select_tool(event.physical_keycode - KEY_1)
			get_viewport().set_input_as_handled()
		elif event.physical_keycode == KEY_Q:
			tools.cycle_seed()
			get_viewport().set_input_as_handled()
		elif event.physical_keycode == KEY_G:
			toggle_grid()
			get_viewport().set_input_as_handled()
		elif event.physical_keycode == KEY_R:
			reset_player()
			get_viewport().set_input_as_handled()
		elif event.physical_keycode == KEY_F:
			toggle_zoom()
			get_viewport().set_input_as_handled()
		elif event.physical_keycode == KEY_M:
			toggle_sound()
			get_viewport().set_input_as_handled()


func set_zoom(value: int) -> void:
	if value not in [1, 2] or value == zoom_level: return
	zoom_level = value
	_clear_hover()
	queue_redraw()
	view_controls_changed.emit()


func toggle_zoom() -> void:
	set_zoom(2 if zoom_level == 1 else 1)


func toggle_sound() -> void:
	action_audio.toggle()
	view_controls_changed.emit()


func toggle_grid() -> void:
	show_grid = not show_grid
	presentation_changed.emit()
	feedback.emit("地块网格已%s。" % ("显示" if show_grid else "隐藏"))
	queue_redraw()


func reset_player() -> void:
	player.position = FarmState.SPAWN
	player.moving = false
	player.facing = Vector2.DOWN
	player_position_changed.emit()
	player_moved.emit(player.cell())
	feedback.emit("已回到农场入口。")
	queue_redraw()


func reset_transient_state() -> void:
	zoom_level = 1
	_recent_supply = 0.0
	view_controls_changed.emit()
	hovered_cell = FarmState.INVALID_CELL
	_last_player_cell = player.cell()
	_blocked_cooldown = 0.0
	_action_flash_remaining = 0.0
	_action_cell = FarmState.INVALID_CELL
	_rain_animation = 0.0
	simulation._matured_this_batch.clear()
	hovered_cell_changed.emit(hovered_cell)


func _process(delta: float) -> void:
	simulation.advance(delta)
	if simulation.clock.paused or not simulation.irrigation.status().running:
		if _recent_supply > 0.0:
			_recent_supply = 0.0
			queue_redraw()
	elif _recent_supply > 0.0 and simulation.irrigation.status().running:
		_flow_phase = fposmod(_flow_phase + delta * 32.0, 32.0)
		_recent_supply = maxf(0.0, _recent_supply - delta)
		queue_redraw()
	if simulation.weather.is_raining() and not simulation.clock.paused:
		_rain_animation += delta
		queue_redraw()
	if _action_flash_remaining > 0.0:
		_action_flash_remaining = maxf(0.0, _action_flash_remaining - delta)
		queue_redraw()
	_blocked_cooldown = maxf(0.0, _blocked_cooldown - delta)
	var direction := Vector2.ZERO
	if interaction_enabled and get_window().has_focus():
		direction = Input.get_vector("farm_left", "farm_right", "farm_up", "farm_down")
	var was_moving := player.moving
	var moved := player.advance(direction, delta, farm)
	if moved:
		player_position_changed.emit()
	if moved or was_moving:
		if zoom_level > 1 and interaction_enabled: _update_hover(get_local_mouse_position())
		queue_redraw()
	if player.blocked and not player.moving and _blocked_cooldown <= 0.0:
		feedback.emit("前方有障碍，请沿道路绕行。")
		_blocked_cooldown = 1.5
	if player.cell() != _last_player_cell:
		_last_player_cell = player.cell()
		player_moved.emit(_last_player_cell)


func _on_plot_changed(cell: Vector2i) -> void:
	if cell == selected_cell:
		tile_selected.emit(cell)
	queue_redraw()


func _on_environment_changed() -> void:
	tile_selected.emit(selected_cell)
	queue_redraw()


func _on_crops_matured(cells: Array) -> void:
	if cells.size() == 1:
		var item: Dictionary = cells[0]
		feedback.emit("地块 (%02d, %02d) 的%s已成熟，按 5 后靠近点击收获。" % [item.cell.x + 1, item.cell.y + 1, FarmState.SEED_NAMES[item.crop_id]])
	else:
		feedback.emit("有 %d 块作物已经成熟，按 5 后靠近点击收获。" % cells.size())


func _on_action_completed(result: Dictionary) -> void:
	feedback.emit(result.message)
	action_audio.action(result)
	_action_code = result.code if result.changed else ""
	if result.changed or not result.ok:
		_action_flash_remaining = 0.35
		_action_cell = result.cell
		_action_ok = result.ok
	queue_redraw()


func _on_tool_changed() -> void:
	feedback.emit("当前工具：%s。%s" % [ToolController.TOOL_NAMES[tools.active_tool], ToolController.HINTS[tools.active_tool]])
	queue_redraw()


func _on_resized() -> void:
	_clear_hover()
	queue_redraw()


func _update_hover(point: Vector2) -> void:
	var cell := local_to_cell(point)
	if cell != hovered_cell:
		hovered_cell = cell
		hovered_cell_changed.emit(cell)
		queue_redraw()


func _clear_hover() -> void:
	if hovered_cell != FarmState.INVALID_CELL:
		hovered_cell = FarmState.INVALID_CELL
		hovered_cell_changed.emit(hovered_cell)
		queue_redraw()


func _draw() -> void:
	var rect := geometry()
	var scale_value := rect.size.x / (24.0 * TILE)
	draw_set_transform(rect.position, 0, Vector2.ONE * scale_value)
	for y in range(FarmState.HEIGHT):
		for x in range(FarmState.WIDTH):
			_draw_ground(Vector2i(x, y))
			_draw_crop(Vector2i(x, y))
	_draw_engineering()
	_draw_sensor()
	# Sort upright objects by their footprint, so the character can pass behind them.
	for y in range(FarmState.HEIGHT):
		for x in range(FarmState.WIDTH):
			var cell := Vector2i(x, y)
			match farm.terrain_at(cell):
				FarmState.Terrain.TREE: _draw_tree(cell)
				FarmState.Terrain.ROCK: _draw_rock(cell)
				FarmState.Terrain.FENCE: _draw_fence(cell)
		if y == 5:
			_draw_house()
		if player.cell().y == y:
			_draw_player()
	var map_extent := Rect2(Vector2.ZERO, Vector2.ONE * 24.0 * TILE)
	var night := simulation.night_opacity()
	if night > 0.0:
		draw_rect(map_extent, Color(0.04, 0.09, 0.18, night))
	if simulation.weather.is_raining():
		for index in range(70):
			var rx: float = fposmod(float(index * 97) + _rain_animation * 32.0, 760.0) + 4.0
			var ry: float = fposmod(float(index * 61) + _rain_animation * 180.0, 758.0) + 4.0
			draw_line(Vector2(rx, ry), Vector2(rx - 2, ry + 6), Color(0.75, 0.85, 0.86, 0.34), 1.0)
	if farm.contains(hovered_cell) and hovered_cell != selected_cell:
		var hover_color := Color("cccfac")
		if tools.active_tool != ToolController.Tool.INSPECT: hover_color = CTheme.RUNNING if tools.can_reach(hovered_cell, player.position) else CTheme.FAULT
		_draw_marker(hovered_cell, hover_color, 1.0)
	if farm.contains(selected_cell):
		_draw_marker(selected_cell, Color("f3dfaa"), 2.0)
	if _action_flash_remaining > 0.0 and farm.contains(_action_cell):
		var color := CTheme.RUNNING if _action_ok else CTheme.FAULT
		color.a = minf(1.0, _action_flash_remaining / 0.2)
		draw_rect(Rect2(Vector2(_action_cell) * TILE + Vector2.ONE * 2, Vector2.ONE * (TILE - 4)), color, false, 2.0)
		if not _action_code.is_empty():
			var center := (Vector2(_action_cell) + Vector2.ONE * 0.5) * TILE
			var progress := 1.0 - _action_flash_remaining / 0.35
			for index in range(5):
				var offset := Vector2((index - 2) * (2.0 + progress * 5.0), -3.0 - sin(progress * PI) * (6 + index % 3 * 3))
				var tint := Color("91b6bf") if _action_code in ["water", "refill"] else color
				draw_rect(Rect2((center + offset).floor(), Vector2(2, 3)), tint)
	draw_rect(Rect2(Vector2.ZERO, Vector2.ONE * 24.0 * TILE), Color("566854"), false, 2.0)
	draw_set_transform(Vector2.ZERO)


func _pixel(x: float, y: float, width: float, height: float, color: String) -> void:
	if width <= 0 or height <= 0: return
	draw_rect(Rect2(floorf(x), floorf(y), maxf(1, floorf(width)), maxf(1, floorf(height))), Color(color))


func _draw_engineering() -> void:
	var state: Dictionary = farm.engineering
	var network := simulation.irrigation
	var model = Engineering.Network
	if state.tank.is_empty() and state.pump.is_empty() and state.power.is_empty() and state.pipes.is_empty(): return
	var visual := Presentation.describe(network, simulation.clock)
	var active: bool = visual.kind == "running" and _recent_supply > 0.0
	var pipe_color := Color("91b6bf") if active else Color("657f89")
	var nodes: Dictionary = {model.key(model.PUMP): true, model.key(model.OUTLET): true}
	for pipe in state.pipes: nodes[pipe] = true
	for pipe in nodes:
		var point: Vector2i = model.cell(pipe)
		var center := (Vector2(point) + Vector2.ONE * 0.5) * TILE
		for direction in model.DIRECTIONS:
			if nodes.has(model.key(point + direction)):
				draw_line(center, center + Vector2(direction) * TILE * 0.5, Color("344953"), 7)
				draw_line(center, center + Vector2(direction) * TILE * 0.5, pipe_color, 3)
		draw_rect(Rect2(center - Vector2.ONE * 3, Vector2.ONE * 6), pipe_color)
		_pixel(center.x - 2, center.y - 2, 4, 2, "b0c0bf")
		if active: _pixel(center.x - 1, center.y - 12 + int(_flow_phase) % 24, 2, 3, "c3dbd6")
	var coverage := Rect2(Vector2(model.COVERAGE.position) * TILE, Vector2(model.COVERAGE.size) * TILE)
	draw_rect(coverage, Color(0.67, 0.76, 0.66, 0.5), false, 1)
	if not state.tank.is_empty():
		var p := Vector2(model.TANK) * TILE
		_pixel(p.x + 4, p.y + 3, 24, 26, "344953")
		_pixel(p.x + 6, p.y + 5, 20, 22, "78969f")
		var height := 18.0 * float(state.water_l) / network.capacity("tank")
		_pixel(p.x + 8, p.y + 25 - height, 16, height, "486e85")
		_pixel(p.x + 7, p.y + 4, 18, 3, "a6bbc0")
		_pixel(p.x + 4, p.y + 11, 2, 10, "b6c6c6")
		_pixel(p.x + 26, p.y + 9, 2, 16, "48616f")
		_pixel(p.x + 10, p.y + 1, 12, 3, "b6c6c6")
		for mark in range(4): _pixel(p.x + 19, p.y + 10 + mark * 4, 4, 1, "cbd8d2")
	if not state.pump.is_empty():
		var p := Vector2(model.PUMP) * TILE
		_pixel(p.x + 4, p.y + 9, 24, 16, "344953")
		_pixel(p.x + 7, p.y + 7, 18, 14, "78969f")
		_pixel(p.x + 10, p.y + 10, 10, 8, "344953")
		_pixel(p.x + 11, p.y + 11, 8, 6, CTheme.color(visual.kind).to_html(false))
		_pixel(p.x + 3, p.y + 22, 26, 4, "48616f")
		for bolt in [7, 23]: _pixel(p.x + bolt, p.y + 23, 2, 2, "b0c0bf")
		_pixel(p.x + 22, p.y + 12, 5, 7, "a6bbc0")
		if farm.automation.installed:
			_pixel(p.x + 6, p.y + 2, 20, 5, "344953")
			_pixel(p.x + 8, p.y + 3, 8, 2, "a6bbc0")
			_pixel(p.x + 20, p.y + 3, 3, 2, CTheme.color(visual.kind).to_html(false))
	if not state.power.is_empty():
		var p := Vector2(model.POWER) * TILE
		_pixel(p.x + 4, p.y + 8, 24, 18, "344953")
		_pixel(p.x + 6, p.y + 10, 20, 14, "78969f")
		_pixel(p.x + 8, p.y + 12, 16.0 * float(state.energy_wh) / network.capacity("power"), 10, "cab889")
		_pixel(p.x + 12, p.y + 5, 8, 3, "a6bbc0")
		_pixel(p.x + 7, p.y + 11, 2, 11, "b6c6c6")
		_pixel(p.x + 22, p.y + 11, 2, 11, "48616f")
		for mark in range(3): _pixel(p.x + 12 + mark * 4, p.y + 14, 1, 5, "344953")
		if not state.pump.is_empty():
			draw_line(p + Vector2(4, 26), p + Vector2(-8, 26), CTheme.MUTED if state.power_connected else CTheme.FAULT, 2)
	var outlet := (Vector2(model.OUTLET) + Vector2.ONE * 0.5) * TILE
	draw_circle(outlet, 5, Color("a6bbc0"))
	if active:
		for index in range(4):
			var offset := Vector2(-12 + index * 8, -6 + index % 2 * 12)
			draw_line(outlet, outlet + offset, Color("91b6bf"), 1)


func _draw_sensor() -> void:
	if not farm.sensor.installed: return
	var point := simulation.sensor.point()
	var p := Vector2(point) * TILE
	_pixel(p.x + 23, p.y + 12, 3, 15, "344953")
	_pixel(p.x + 20, p.y + 6, 8, 9, "78969f")
	_pixel(p.x + 22, p.y + 8, 4, 4, (CTheme.RUNNING if simulation.sensor.current(simulation.clock.total_minutes).valid else CTheme.FAULT).to_html(false))
	_pixel(p.x + 21, p.y + 14, 6, 2, "b0c0bf")
	_pixel(p.x + 24, p.y + 20, 1, 6, "b6c6c6")


func _draw_ground(cell: Vector2i) -> void:
	var p := Vector2(cell) * TILE
	var terrain := farm.terrain_at(cell)
	var noise_value := absi(cell.x * 73856093 ^ cell.y * 19349663)
	var patch := absi(int(cell.x / 3) * 137 ^ int(cell.y / 3) * 61)
	var colors := ["667c4e", "6d8251", "718651", "6a8051"]
	_pixel(p.x, p.y, TILE, TILE, colors[patch % colors.size()])
	var plot := farm.plot_at(cell)
	if farm.is_arable(cell) and plot.tilled:
		var wet: bool = float(plot.moisture) >= 30.0
		_pixel(p.x, p.y, TILE, TILE, "664a39" if wet else "876348")
		for i in range(4):
			_pixel(p.x + 2, p.y + 4 + i * 7, 28, 3, "513e32" if wet else "705038")
			_pixel(p.x + 2, p.y + 3 + i * 7, 28, 1, "846047" if wet else "a07853")
		if wet:
			_pixel(p.x + 25, p.y + 23, 3, 4, "7c9aa0")
			_pixel(p.x + 26, p.y + 21, 1, 2, "7c9aa0")
	elif terrain == FarmState.Terrain.PATH:
		_pixel(p.x, p.y, TILE, TILE, "aa9872")
		if farm.terrain_at(cell + Vector2i.LEFT) != FarmState.Terrain.PATH: _pixel(p.x, p.y, 2, TILE, "8d805d")
		if farm.terrain_at(cell + Vector2i.UP) != FarmState.Terrain.PATH: _pixel(p.x, p.y, TILE, 2, "bbae85")
		for i in range(4):
			var offset := Vector2((noise_value + i * 7) % 27 + 2, (noise_value / 7 + i * 11) % 27 + 2)
			_pixel(p.x + offset.x, p.y + offset.y, 3, 2, "b8a581")
	elif terrain == FarmState.Terrain.SOIL:
		_pixel(p.x, p.y, TILE, TILE, "876348" if noise_value % 2 == 0 else "8d684c")
		_pixel(p.x + 5, p.y + 12, 9, 1, "78583f")
		_pixel(p.x + noise_value % 22 + 3, p.y + noise_value % 19 + 5, 2, 2, "a57b57")
	elif terrain == FarmState.Terrain.WATER:
		_pixel(p.x, p.y, TILE, TILE, "527c89")
		_pixel(p.x + 4, p.y + 9, 12, 2, "6e9aa0")
		_pixel(p.x + 19, p.y + 23, 9, 2, "658e96")
		for direction in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			if farm.terrain_at(cell + direction) != FarmState.Terrain.WATER:
				if direction.x == -1: _pixel(p.x, p.y, 3, TILE, "b5ac7e")
				if direction.x == 1: _pixel(p.x + 29, p.y, 3, TILE, "b5ac7e")
				if direction.y == -1: _pixel(p.x, p.y, TILE, 3, "b5ac7e")
				if direction.y == 1: _pixel(p.x, p.y + 29, TILE, 3, "b5ac7e")
				if direction.y == -1:
					_pixel(p.x + 4, p.y + 2, 2, 8, "365443")
					_pixel(p.x + 3, p.y + 2, 4, 3, "8eaa6c")
	else:
		for i in range(6):
			var ox := (noise_value + i * 11) % 27 + 2
			var oy := (noise_value / 11 + i * 7) % 24 + 4
			_pixel(p.x + ox, p.y + oy, 1, 4, "87985f")
			_pixel(p.x + ox - 1, p.y + oy + 3, 3, 1, "5c734a")
		if noise_value % 3 == 0:
			_pixel(p.x + 11, p.y + 24, 2, 1, "b6ae7d")
			_pixel(p.x + 23, p.y + 8, 1, 1, "b6ae7d")
		if noise_value % 17 == 0 and terrain == FarmState.Terrain.GRASS:
			_pixel(p.x + 20, p.y + 12, 2, 5, "536d49")
			_pixel(p.x + 18, p.y + 10, 5, 3, "d6c58a")
	if show_grid:
		draw_rect(Rect2(p, Vector2.ONE * TILE), Color(0.1, 0.15, 0.12, 0.25), false, 1.0)


func _draw_crop(cell: Vector2i) -> void:
	var plot := farm.plot_at(cell)
	var crop: Dictionary = plot.crop
	if crop.is_empty():
		return
	var p := Vector2(cell) * TILE
	var tag_colors := {"lettuce": "a9c18b", "carrot": "d4a36b", "tomato": "ba8172"}
	var stage := simulation.CropModel.stage(crop)
	var stressed: bool = simulation.crops.water_factor(plot) < 0.6 and stage < 4
	var leaf: String = "9d985f" if stressed else "719c57"
	var light_leaf: String = "b2a570" if stressed else "a7bd69"
	var dark_leaf: String = "736d47" if stressed else "436c45"
	if stage == 0:
		for offset in [Vector2(8, 10), Vector2(20, 17), Vector2(9, 25)]:
			_pixel(p.x + offset.x, p.y + offset.y, 3, 2, "c5b18a")
	elif stage == 1:
		for offset in [Vector2(9, 14), Vector2(20, 23)]:
			_pixel(p.x + offset.x, p.y + offset.y - 3, 2, 6, dark_leaf)
			_pixel(p.x + offset.x - 3, p.y + offset.y - 4, 4, 3, leaf)
			_pixel(p.x + offset.x + 1, p.y + offset.y - 6, 4, 3, light_leaf)
	elif stage == 2:
		_pixel(p.x + 10, p.y + 24, 14, 3, "443e2d")
		if crop.id == "lettuce":
			_pixel(p.x + 9, p.y + 15, 15, 8, dark_leaf)
			_pixel(p.x + 12, p.y + 12, 9, 13, leaf)
			_pixel(p.x + 15, p.y + 14, 5, 6, light_leaf)
		elif crop.id == "carrot":
			for offset in [Vector2(11, 18), Vector2(22, 24)]:
				_pixel(p.x + offset.x, p.y + offset.y - 9, 2, 10, dark_leaf)
				_pixel(p.x + offset.x - 4, p.y + offset.y - 7, 4, 3, leaf)
				_pixel(p.x + offset.x + 1, p.y + offset.y - 10, 4, 3, light_leaf)
		else:
			_pixel(p.x + 17, p.y + 9, 2, 17, "af9668")
			_pixel(p.x + 13, p.y + 13, 2, 13, dark_leaf)
			_pixel(p.x + 8, p.y + 16, 14, 3, leaf)
			_pixel(p.x + 10, p.y + 11, 10, 3, light_leaf)
	else:
		var large: bool = stage >= 3
		match crop.id:
			"lettuce":
				_pixel(p.x + 6, p.y + 23, 21, 4, "443e2d")
				_pixel(p.x + 5, p.y + 13, 23, 9, dark_leaf)
				_pixel(p.x + 9, p.y + 8, 15, 18, leaf)
				_pixel(p.x + 6, p.y + 15, 19, 8, leaf)
				_pixel(p.x + 13, p.y + 10, 8, 11, light_leaf)
				if large:
					_pixel(p.x + 10, p.y + 4, 12, 6, light_leaf)
					_pixel(p.x + 7, p.y + 12, 4, 7, light_leaf)
			"carrot":
				for offset in [Vector2(11, 16), Vector2(22, 23)]:
					if large:
						_pixel(p.x + offset.x - 3, p.y + offset.y, 7, 4, "db9b50" if stage == 4 else "b8844e")
						_pixel(p.x + offset.x - 1, p.y + offset.y + 4, 3, 4, "c67b40")
					_pixel(p.x + offset.x, p.y + offset.y - 10, 2, 12, dark_leaf)
					_pixel(p.x + offset.x - 6, p.y + offset.y - 8, 6, 3, leaf)
					_pixel(p.x + offset.x + 1, p.y + offset.y - 12, 5, 3, light_leaf)
					_pixel(p.x + offset.x - 3, p.y + offset.y - 4, 8, 3, leaf)
			"tomato":
				_pixel(p.x + 18, p.y + 5, 2, 24, "af9668")
				_pixel(p.x + 13, p.y + 9, 3, 19, dark_leaf)
				_pixel(p.x + 6, p.y + 12, 18, 4, leaf)
				_pixel(p.x + 9, p.y + 7, 12, 4, light_leaf)
				_pixel(p.x + 8, p.y + 20, 17, 4, leaf)
				if large:
					var fruit: String = "d27055" if stage == 4 else "b4b36a"
					_pixel(p.x + 6, p.y + 16, 5, 5, fruit)
					_pixel(p.x + 18, p.y + 12, 5, 5, fruit)
					_pixel(p.x + 16, p.y + 24, 5, 5, fruit)
	_pixel(p.x + 25, p.y + 3, 1, 9, "b1a27d")
	_pixel(p.x + 23, p.y + 2, 6, 4, tag_colors.get(crop.id, "c5b18a"))
	if stage == 4:
		_pixel(p.x + 2, p.y + 2, 3, 5, "e5ce87")
		_pixel(p.x + 2, p.y + 9, 3, 2, "e5ce87")


func _draw_tree(cell: Vector2i) -> void:
	var p := Vector2(cell) * TILE
	_pixel(p.x + 4, p.y + 25, 26, 5, "536647")
	_pixel(p.x + 14, p.y + 17, 6, 12, "786047")
	_pixel(p.x + 16, p.y + 19, 2, 8, "967750")
	_pixel(p.x + 5, p.y + 3, 25, 17, "365443")
	_pixel(p.x + 1, p.y + 9, 32, 11, "3d5d46")
	_pixel(p.x + 8, p.y - 3, 17, 23, "486b49")
	_pixel(p.x + 7, p.y + 2, 13, 10, "57794e")
	_pixel(p.x + 3, p.y + 10, 9, 5, "648454")
	_pixel(p.x + 23, p.y + 9, 5, 7, "4e714c")
	var noise_value := absi(cell.x * 73 ^ cell.y * 137)
	for index in range(7):
		var ox := (noise_value + index * 7) % 24 + 3
		var oy := (noise_value / 5 + index * 11) % 15 + 2
		_pixel(p.x + ox, p.y + oy, 3, 2, "63864f" if index % 2 == 0 else "2f4b3d")
	_pixel(p.x + 19, p.y + 20, 2, 7, "5c4938")


func _draw_rock(cell: Vector2i) -> void:
	var p := Vector2(cell) * TILE
	_pixel(p.x + 4, p.y + 23, 25, 5, "536647")
	_pixel(p.x + 5, p.y + 11, 23, 13, "747f7d")
	_pixel(p.x + 9, p.y + 6, 14, 20, "89938c")
	_pixel(p.x + 9, p.y + 8, 12, 4, "a1aba0")
	_pixel(p.x + 22, p.y + 14, 6, 9, "626f70")


func _draw_fence(cell: Vector2i) -> void:
	var p := Vector2(cell) * TILE
	if cell.x == 0 or cell.x == 23:
		_pixel(p.x + 12, p.y, 4, 32, "b2a07c")
		_pixel(p.x + 20, p.y, 3, 32, "8b795c")
		_pixel(p.x + 10, p.y + 12, 15, 7, "c4b38a")
	else:
		_pixel(p.x, p.y + 13, 32, 3, "b2a07c")
		_pixel(p.x, p.y + 22, 32, 3, "8b795c")
		_pixel(p.x + 12, p.y + 8, 6, 21, "c4b38a")


func _draw_house() -> void:
	var x: float = 2 * TILE
	var y: float = 3 * TILE
	_pixel(x + 2, y + 84, 126, 12, "536647")
	_pixel(x + 5, y + 31, 117, 61, "c2b38c")
	_pixel(x + 5, y + 36, 117, 4, "9e8d70")
	for i in range(5):
		_pixel(x + 6, y + 45 + i * 9, 114, 1, "ac9c79")
	_pixel(x, y + 10, 128, 28, "526c76")
	_pixel(x + 8, y + 3, 112, 9, "657e85")
	_pixel(x + 15, y, 98, 5, "7b9295")
	for i in range(8):
		_pixel(x + 4 + i * 16, y + 12, 2, 23, "405b68")
	_pixel(x, y + 34, 128, 5, "354b55")
	_pixel(x + 14, y + 50, 28, 26, "6d756c")
	_pixel(x + 17, y + 53, 22, 20, "86a6a4")
	_pixel(x + 27, y + 53, 2, 20, "d6c7a1")
	_pixel(x + 17, y + 62, 22, 2, "d6c7a1")
	_pixel(x + 56, y + 49, 24, 43, "594f40")
	_pixel(x + 59, y + 52, 18, 39, "7e6b50")
	_pixel(x + 73, y + 70, 2, 3, "d5c28e")
	_pixel(x + 91, y + 50, 21, 25, "6d756c")
	_pixel(x + 94, y + 53, 15, 19, "86a6a4")
	_pixel(x + 52, y + 89, 32, 5, "968e79")
	_pixel(x + 100, y - 6, 10, 19, "9b9d8c")
	_pixel(x + 4, y + 80, 118, 12, "7c8275")
	for index in range(10):
		_pixel(x + 7 + index * 11, y + 82, 8, 3, "a6aa91")
	for band in range(3):
		_pixel(x + 5 + band * 3, y + 15 + band * 6, 119 - band * 6, 1, "789198")
	_pixel(x + 45, y + 44, 41, 5, "344953")
	_pixel(x + 49, y + 45, 8, 2, "a9c18b")
	_pixel(x + 62, y + 45, 18, 2, "a6bbc0")
	_pixel(x + 11, y + 48, 3, 28, "657e85")
	_pixel(x + 42, y + 48, 3, 28, "657e85")


func _draw_player() -> void:
	var p := (player.position * TILE).floor()
	var stride: int = 2 if player.moving and int(player.walk_distance * 5) % 2 == 0 else 0
	_pixel(p.x - 8, p.y - 1, 17, 5, "485d43")
	_pixel(p.x - 5, p.y - 9, 4, 9 - stride, "304b60")
	_pixel(p.x + 1, p.y - 9, 4, 7 + stride, "304b60")
	_pixel(p.x - 6, p.y - 3 - stride, 5, 3, "4e433c")
	_pixel(p.x + 1, p.y - 3 + stride, 5, 3, "4e433c")
	_pixel(p.x - 6, p.y - 18, 12, 11, "859baa")
	_pixel(p.x - 4, p.y - 17, 8, 10, "486e82")
	_pixel(p.x - 9, p.y - 16, 3, 8, "d1ab7b")
	_pixel(p.x + 6, p.y - 16, 3, 8, "d1ab7b")
	_pixel(p.x - 5, p.y - 26, 10, 10, "d9b783")
	_pixel(p.x - 5, p.y - 26, 10, 3, "66513f")
	if player.facing.y < 0:
		_pixel(p.x - 5, p.y - 23, 10, 6, "66513f")
	else:
		var eye_offset: float = 2.0 * player.facing.x
		_pixel(p.x - 3 + eye_offset, p.y - 21, 1, 2, "433d36")
		_pixel(p.x + 2 + eye_offset, p.y - 21, 1, 2, "433d36")
	_pixel(p.x - 7, p.y - 28, 14, 4, "d9bd7c")
	_pixel(p.x - 10, p.y - 25, 20, 3, "e5cc8d")
	_pixel(p.x - 6, p.y - 15, 2, 6, "b0c0bf")
	_pixel(p.x + 3, p.y - 14, 2, 5, "b0c0bf")
	if tools.active_tool == ToolController.Tool.WATER:
		_pixel(p.x + 8, p.y - 11, 7, 7, "78969f")
		_pixel(p.x + 14, p.y - 10, 4, 2, "b0c0bf")
	elif tools.active_tool == ToolController.Tool.HOE:
		_pixel(p.x + 9, p.y - 17, 2, 17, "af9668")
		_pixel(p.x + 5, p.y - 17, 9, 3, "78969f")
	elif tools.active_tool == ToolController.Tool.SOW:
		_pixel(p.x + 8, p.y - 9, 6, 7, "b5a17a")
		_pixel(p.x + 10, p.y - 7, 2, 2, "a9c18b")
	elif tools.active_tool == ToolController.Tool.HARVEST:
		_pixel(p.x + 7, p.y - 7, 9, 6, "af9668")
		_pixel(p.x + 8, p.y - 5, 7, 1, "786047")


func _draw_marker(cell: Vector2i, color: Color, width: float) -> void:
	var p := Vector2(cell) * TILE + Vector2.ONE * 1.5
	var extent: float = TILE - 3.0
	var arm: float = 7.0
	for corner in [Vector2.ZERO, Vector2(extent, 0), Vector2(0, extent), Vector2.ONE * extent]:
		var sx: float = 1.0 if corner.x == 0 else -1.0
		var sy: float = 1.0 if corner.y == 0 else -1.0
		draw_line(p + corner, p + corner + Vector2(arm * sx, 0), color, width)
		draw_line(p + corner, p + corner + Vector2(0, arm * sy), color, width)
