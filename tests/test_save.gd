extends SceneTree
## Every fixture uses a test slot under tmp; the player's user:// slot is untouched.

const Service = preload("res://scripts/persistence/save_service.gd")
const Codec = preload("res://scripts/persistence/save_codec.gd")
const Tools = preload("res://scripts/world/tool_controller.gd")
var checks: int = 0
var failures: int = 0
var directory: String


class RefusePromotion extends Service:
	func _promote_file(from_path: String, to_path: String) -> Error:
		return ERR_CANT_CREATE if to_path == path else super._promote_file(from_path, to_path)


func _initialize() -> void:
	_run.call_deferred()


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("SAVE TEST FAILED: " + message)


func _state(view: Control) -> String:
	return JSON.stringify(Codec.capture(view), "", true, true)


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _new_app(slot: String) -> Control:
	var app := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	app.set_meta("save_path", slot)
	root.add_child(app)
	app.farm_view.simulation.clock.set_paused(true)
	await process_frame
	await process_frame
	return app


func _prepare(view: Control) -> void:
	view.economy.buy_seeds("carrot", 2)
	view.player.position = Vector2(7.6, 12.5)
	view.player.facing = Vector2.RIGHT
	view.player.walk_distance = 3.75
	view.tools.select_tool(Tools.Tool.HOE)
	view.tools.use(Vector2i(7, 12), view.player.position)
	view.tools.select_seed("carrot")
	view.tools.use(Vector2i(7, 12), view.player.position)
	view.tools.select_tool(Tools.Tool.WATER)
	view.tools.use(Vector2i(7, 12), view.player.position)
	view.simulation.clock.set_speed(4)
	view.simulation.clock.set_paused(false)
	view.simulation.advance(1.1875)
	view.simulation.clock.set_paused(true)
	view.tools.select_seed("tomato")
	view.show_grid = true
	view.selected_cell = Vector2i(7, 12)


func _run() -> void:
	directory = "res://tmp/qa/save-%d-%d" % [OS.get_process_id(), Time.get_ticks_msec()]
	DirAccess.make_dir_recursive_absolute(directory)
	var app: Control = await _new_app(directory.path_join("farm.json"))
	_prepare(app.farm_view)
	var original := _state(app.farm_view)
	_expect(app.save_service.save(app.farm_view).ok, "A complete live farm passes validation and saves to disk.")
	_expect(app.save_service.read().ok, "The written file can be read and independently validated.")
	app.farm_view.economy.buy_seeds("lettuce", 1)
	var second := _state(app.farm_view)
	_expect(app.save_service.save(app.farm_view).ok and app.save_service.read(true).ok, "A second save preserves a valid previous version.")
	app.farm_view.economy.buy_seeds("tomato", 1)
	_expect(app.save_service.load_into(app.farm_view).ok and _state(app.farm_view) == second, "Loading restores crops, money, ledger, player, view and clock exactly.")
	_expect(app.save_service.load_into(app.farm_view, true).ok and _state(app.farm_view) == original, "The backup restores the exact previous farm.")
	var saved_reference: Dictionary = app.save_service.read(true)
	var twin: Control = await _new_app(directory.path_join("twin.json"))
	app.save_service.apply_read(twin.farm_view, saved_reference)
	for view in [app.farm_view, twin.farm_view]:
		view.simulation.clock.set_paused(false)
		view.simulation.clock.set_speed(12)
		for _tick in range(120): view.simulation.advance(0.1)
	_expect(_state(app.farm_view) == _state(twin.farm_view), "Restored state continues with identical future weather, crop growth and moisture.")
	app.queue_free()
	twin.queue_free()
	await process_frame
	await _test_rejections()
	await _test_ui()
	if failures == 0: print("FIELDWORKS_SAVE_TESTS_OK ", checks, " checks")
	else: print("FIELDWORKS_SAVE_TESTS_FAILED ", failures, "/", checks)
	quit(0 if failures == 0 else 1)


func _test_rejections() -> void:
	var app: Control = await _new_app(directory.path_join("rejections.json"))
	_prepare(app.farm_view)
	var payload := Codec.capture(app.farm_view)
	var unchanged := _state(app.farm_view)
	var bad := Service.new(directory.path_join("corrupt.json"))
	_expect(not bad.load_into(app.farm_view).ok and _state(app.farm_view) == unchanged, "Missing saves cannot change the farm.")
	_write(bad.path, "{broken")
	_expect(not bad.load_into(app.farm_view).ok and _state(app.farm_view) == unchanged, "Malformed JSON cannot change the farm.")
	var changes: Array[Callable] = [
		func(p: Dictionary) -> void: p.farm.cash += 1,
		func(p: Dictionary) -> void: p.farm.seeds.carrot += 1,
		func(p: Dictionary) -> void: p.farm.produce.lettuce += 1,
		func(p: Dictionary) -> void: p.farm.next_transaction_id = 99,
		func(p: Dictionary) -> void: p.farm.ledger[1].amount = -1,
		func(p: Dictionary) -> void: p.farm.plots[0].tilled = true,
		func(p: Dictionary) -> void: p.farm.plots[295].moisture = -1,
		func(p: Dictionary) -> void: p.farm.plots[295].crop.growth = 1.5,
		func(p: Dictionary) -> void: p.runtime.clock.total_minutes += 5,
		func(p: Dictionary) -> void: p.runtime.clock.accumulator = -1,
		func(p: Dictionary) -> void: p.runtime.weather.period_index = 99,
		func(p: Dictionary) -> void: p.runtime.weather.rng_state = "not-a-state",
		func(p: Dictionary) -> void: p.player.position = [3.5, 4.5],
		func(p: Dictionary) -> void: p.player.facing = [0, 0],
		func(p: Dictionary) -> void: p.view.selected_cell = [24, 24],
		func(p: Dictionary) -> void: p.farm.parts = {"unsupported": 1},
	]
	for index in range(changes.size()):
		var invalid: Dictionary = payload.duplicate(true)
		changes[index].call(invalid)
		_write(bad.path, JSON.stringify(bad.envelope(invalid)))
		_expect(not bad.load_into(app.farm_view).ok and _state(app.farm_view) == unchanged, "Structurally invalid save is rejected before mutation: %d" % index)
	for field in ["version", "rules_revision", "engine", "float_encoding", "config_hash", "sha256"]:
		var wrapper := bad.envelope(payload)
		wrapper[field] = 999 if field in ["version", "rules_revision"] else "incompatible"
		_write(bad.path, JSON.stringify(wrapper))
		_expect(not bad.load_into(app.farm_view).ok and _state(app.farm_view) == unchanged, "Incompatible or checksum-invalid save is rejected: " + field)
	for encoded in ["-000000000000000", "000000000000f87f", "000000000000f07f"]:
		var wrapper := bad.envelope(payload)
		var packed: Dictionary = JSON.parse_string(wrapper.payload_json)
		packed.farm.plots[295].moisture = {"_float64": encoded}
		wrapper.payload_json = JSON.stringify(packed)
		wrapper.sha256 = wrapper.payload_json.sha256_text()
		_write(bad.path, JSON.stringify(wrapper))
		_expect(not bad.load_into(app.farm_view).ok and _state(app.farm_view) == unchanged, "Invalid hexadecimal, NaN and infinity cannot enter a farm: " + encoded)
	var slot: RefCounted = app.save_service
	_expect(slot.save(app.farm_view).ok, "A valid state still saves after invalid-file tests.")
	var previous := FileAccess.get_file_as_string(slot.path)
	app.farm_view.economy.buy_seeds("lettuce", 1)
	var refusal := RefusePromotion.new(slot.path)
	_expect(not refusal.save(app.farm_view).ok and FileAccess.get_file_as_string(slot.path) == previous, "A replacement failure preserves the last committed primary file.")
	_expect(slot.read().ok and slot.read(true).ok, "Primary and valid backup survive replacement failure.")
	app.farm_view.farm.trade_in_progress = true
	_expect(not slot.save(app.farm_view).ok, "An in-progress trade cannot be serialized halfway through.")
	app.farm_view.farm.trade_in_progress = false
	app.queue_free()
	await process_frame


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


func _button(control: Control) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = control.get_global_transform_with_canvas() * (control.size / 2.0)
		event.pressed = pressed
		if control.get_viewport() is Window and control.get_viewport() != root:
			event.position += Vector2((control.get_viewport() as Window).position)
		root.push_input(event, true)
	await process_frame
	await process_frame


func _test_ui() -> void:
	var slot := directory.path_join("ui.json")
	var app: Control = await _new_app(slot)
	_prepare(app.farm_view)
	await process_frame
	await process_frame
	await _tap(KEY_F5)
	_expect(app.save_service.read().ok and app.save_status.text.begins_with("已保存"), "F5 writes a real save and updates the status.")
	var saved := _state(app.farm_view)
	app.farm_view.economy.buy_seeds("lettuce", 1)
	await _tap(KEY_F9)
	_expect(app.load_dialog.visible and not app.farm_view.interaction_enabled, "F9 asks before replacing unsaved progress.")
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir=") and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			var capture_path := argument.trim_prefix("--capture-dir=").path_join("step-07-load-confirmation.png")
			_expect(root.get_texture().get_image().save_png(capture_path) == OK, "Load confirmation capture saved.")
	await _button(app.load_dialog.get_cancel_button())
	_expect(not app.load_dialog.visible and _state(app.farm_view) != saved, "Cancel keeps unsaved purchases and the current farm.")
	await _tap(KEY_F9)
	await _button(app.load_dialog.get_ok_button())
	_expect(_state(app.farm_view) == saved and app._cash_label.text.contains("580") and app._growth_bar.visible, "Confirmed load restores the saved farm and refreshes every panel.")
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir=") and DisplayServer.get_name() != "headless":
			await _capture(app, argument.trim_prefix("--capture-dir="))
	app.farm_view.economy.buy_seeds("lettuce", 1)
	await _tap(KEY_F5)
	_write(app.save_service.path, "{damaged primary")
	await _tap(KEY_F9)
	_expect(app.load_dialog.visible and app.load_dialog.dialog_text.contains("备份"), "A damaged primary offers the validated backup explicitly.")
	await _button(app.load_dialog.get_ok_button())
	_expect(_state(app.farm_view) == saved and app._loaded_backup and app.save_status.text.contains("备份"), "Confirmed backup recovery restores the old state without silently rewriting the slot.")
	await _tap(KEY_F5)
	_expect(app.save_service.read().ok and app.save_service.read(true).ok and not app._loaded_backup, "Saving recovered progress repairs the primary while retaining a good backup.")
	app.farm_view.economy.buy_seeds("lettuce", 1)
	app._request_quit()
	await process_frame
	_expect(app.quit_dialog.visible and app.quit_dialog.dialog_text.contains("未保存"), "Leaving a changed farm offers save, discard or cancel.")
	await _button(app.quit_dialog.get_cancel_button())
	_expect(not app.quit_dialog.visible and app.farm_view.interaction_enabled, "Canceling exit returns control to the farm.")
	# A file can disappear or become damaged while the confirmation is open.
	await _tap(KEY_F9)
	var before_failed_load := _state(app.farm_view)
	_write(app.save_service.path, "{changed during confirmation")
	await _button(app.load_dialog.get_ok_button())
	_expect(_state(app.farm_view) == before_failed_load and app.farm_view.interaction_enabled and app._feedback_label.text.contains("读取失败"), "A load rechecks the file at confirmation and preserves live progress on failure.")
	await _tap(KEY_F5)
	# Saving inside the market persists the player's pause setting, not its modal pause.
	app.farm_view.simulation.clock.set_paused(false)
	await _tap(KEY_B)
	await _tap(KEY_F5)
	var market_save: Dictionary = app.save_service.read()
	_expect(market_save.ok and not market_save.candidate.runtime.clock.paused and app.farm_view.simulation.clock.paused, "Saving from the market retains the pre-market running state.")
	await _tap(KEY_ESCAPE)
	_expect(not app.market_panel.visible and not app.farm_view.simulation.clock.paused, "Closing the market after saving resumes its previous running state.")
	app.farm_view.simulation.clock.set_paused(true)
	# Restore the known fixture for the scene-reopen check.
	app.save_service.apply_read(app.farm_view, market_save)
	app.farm_view.simulation.clock.set_paused(true)
	app._save_game()
	saved = _state(app.farm_view)
	app.queue_free()
	await process_frame
	var reopened: Control = await _new_app(slot)
	_expect(reopened.save_status.text.contains("已有存档") and reopened.farm_view.farm.cash == 600, "Reopening offers the existing save without silently loading or overwriting it.")
	await _tap(KEY_F9)
	_expect(_state(reopened.farm_view) == saved, "A fresh scene can continue the disk save without a stale in-memory farm.")
	reopened.queue_free()
	await process_frame


func _capture(_app: Control, target: String) -> void:
	for window_size in [Vector2i(1440, 900), Vector2i(1152, 720)]:
		root.size = window_size
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var file := target.path_join("step-07-loaded-%dx%d.png" % [window_size.x, window_size.y])
		_expect(root.get_texture().get_image().save_png(file) == OK, "Loaded-farm capture saved: " + file)
		print("FIELDWORKS_SAVE_CAPTURE_OK ", file)
