extends Control
## Step 12: a continuous route through farming, engineering and measured decisions.

const FarmView = preload("res://scripts/world/farm_view.gd")
const ToolBar = preload("res://scripts/ui/tool_bar.gd")
const TimeBar = preload("res://scripts/ui/time_bar.gd")
const MarketPanel = preload("res://scripts/ui/market_panel.gd")
const WorkbenchPanel = preload("res://scripts/ui/workbench_panel.gd")
const SensorPanel = preload("res://scripts/ui/sensor_panel.gd")
const AutomationPanel = preload("res://scripts/ui/automation_panel.gd")
const SensorLabPanel = preload("res://scripts/ui/sensor_lab_panel.gd")
const TutorialPanel = preload("res://scripts/ui/tutorial_panel.gd")
const SaveService = preload("res://scripts/persistence/save_service.gd")

const BACKGROUND := Color("101b22")
const PANEL := Color("1a2a33")
const BORDER := Color("344953")
const TEXT := Color("e0e7e4")
const MUTED := Color("9fafaF")
const ACCENT := Color("a9c18b")

var _qa_frames: int = 0
var _smoke_test: bool = false
var _capture_path: String = ""
var farm_view: FarmView
var tool_bar: ToolBar
var time_bar: TimeBar
var market_panel: MarketPanel
var workbench_panel: WorkbenchPanel
var sensor_panel: SensorPanel
var automation_panel: AutomationPanel
var lab_panel: SensorLabPanel
var lab_button: LinkButton
var tutorial_panel: TutorialPanel
var tutorial_button: LinkButton
var _guide_label: Label
var sensor_button: Button
var _engineering_label: Label
var _selected_title: Label
var _selected_coords: Label
var _tile_description: Label
var _terrain_properties: Label
var _player_label: Label
var _hover_label: Label
var _feedback_label: Label
var _grid_button: Button
var _plot_details: Label
var _growth_bar: ProgressBar
var _produce_label: Label
var _cash_label: Label
var _market_button: Button
var save_service: SaveService
var save_button: Button
var load_button: Button
var save_status: Label
var load_dialog: ConfirmationDialog
var quit_dialog: ConfirmationDialog
var _dirty: bool = true
var _has_progress: bool = false
var _restoring: bool = false
var _saved_minute: int = -1
var _saved_controls: Dictionary = {"speed": 1, "paused": false}
var _previous_actor_cell := Vector2i(6, 13)
var _loaded_backup: bool = false
var _loaded_legacy: bool = false
var _pending_backup: bool = false
var _dialog_active: bool = false
var _dialog_was_paused: bool = false
var _dialog_effective_pause: bool = false
var _dialog_interaction: bool = true


func _ready() -> void:
	save_service = SaveService.new(str(get_meta("save_path", SaveService.DEFAULT_PATH)))
	for argument in OS.get_cmdline_user_args():
		if argument == "--smoke-test":
			_smoke_test = true
		elif argument.begins_with("--capture="):
			_capture_path = argument.trim_prefix("--capture=")
	_setup_theme()
	_build_interface()
	_setup_save_ui()
	get_tree().set_auto_accept_quit(false)


func _setup_theme() -> void:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei", "PingFang SC", "Noto Sans CJK SC", "sans-serif"])
	var ui_theme := Theme.new()
	ui_theme.default_font = font
	ui_theme.default_font_size = 18
	ui_theme.set_color("font_color", "Label", TEXT)
	ui_theme.set_color("font_color", "Button", TEXT)
	ui_theme.set_stylebox("normal", "Button", _style(Color("293e47")))
	ui_theme.set_stylebox("hover", "Button", _style(Color("354d55")))
	ui_theme.set_stylebox("pressed", "Button", _style(Color("415b59")))
	ui_theme.set_stylebox("focus", "Button", _style(Color.TRANSPARENT, ACCENT))
	theme = ui_theme


func _style(fill: Color, outline: Color = BORDER) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = outline
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	return style


func _label(text_value: String, font_size: int = 18, color: Color = TEXT) -> Label:
	var result := Label.new()
	result.text = text_value
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", color)
	return result


func _paragraph(text_value: String, font_size: int = 18, color: Color = MUTED) -> Label:
	var result := _label(text_value, font_size, color)
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return result


func _space(height: float) -> Control:
	var result := Control.new()
	result.custom_minimum_size.y = height
	return result


func _panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style(PANEL))
	return panel


func _button(text_value: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text_value
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(action)
	return button


func _build_interface() -> void:
	var background := ColorRect.new()
	background.color = BACKGROUND
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 32)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 24)
	margin.add_child(root)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	root.add_child(header)
	var icon := TextureRect.new()
	icon.texture = preload("res://assets/icon.svg")
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(48, 48)
	header.add_child(icon)
	var title := _label("田野工程师  Fieldworks", 26)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	# Create state before the time bar so every panel uses the farm view's simulation.
	farm_view = FarmView.new()
	time_bar = TimeBar.new()
	time_bar.setup(farm_view.simulation)
	header.add_child(time_bar)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 24)
	root.add_child(body)
	var preview_panel := _panel()
	preview_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(preview_panel)
	var preview_column := VBoxContainer.new()
	preview_column.add_theme_constant_override("separation", 12)
	preview_panel.add_child(preview_column)
	var preview_heading := HBoxContainer.new()
	preview_heading.add_theme_constant_override("separation", 12)
	preview_column.add_child(preview_heading)
	var preview_title := _label("农场试验区", 22)
	preview_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_heading.add_child(preview_title)
	lab_button = LinkButton.new()
	lab_button.text = "参考实验 / 故障教学 [L]"
	lab_button.focus_mode = Control.FOCUS_NONE
	lab_button.pressed.connect(_open_lab)
	preview_heading.add_child(lab_button)
	tutorial_button = LinkButton.new()
	tutorial_button.text = "试玩引导 [H]"
	tutorial_button.focus_mode = Control.FOCUS_NONE
	tutorial_button.pressed.connect(_open_tutorial)
	preview_heading.add_child(tutorial_button)
	_guide_label = _paragraph("", 16, ACCENT)
	_guide_label.custom_minimum_size.y = 44
	preview_column.add_child(_guide_label)
	farm_view.name = "FarmView"
	farm_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	farm_view.custom_minimum_size = Vector2(480, 440)
	farm_view.tile_selected.connect(_refresh_inspector)
	farm_view.player_moved.connect(_refresh_player)
	farm_view.hovered_cell_changed.connect(_refresh_hover)
	farm_view.feedback.connect(_show_feedback)
	preview_column.add_child(farm_view)
	_hover_label = _label("鼠标移入农场可以查看地块位置。", 16, MUTED)
	preview_column.add_child(_hover_label)
	tool_bar = ToolBar.new()
	tool_bar.name = "ToolBar"
	tool_bar.setup(farm_view.tools)
	preview_column.add_child(tool_bar)
	var progress_panel := _panel()
	progress_panel.custom_minimum_size.x = 370
	body.add_child(progress_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	progress_panel.add_child(column)
	column.add_child(_label("地块检查", 22))
	_selected_coords = _label("", 17, MUTED)
	column.add_child(_selected_coords)
	_selected_title = _label("", 26, ACCENT)
	column.add_child(_selected_title)
	_terrain_properties = _label("", 18)
	column.add_child(_terrain_properties)
	_plot_details = _paragraph("", 17, TEXT)
	_plot_details.custom_minimum_size.y = 70
	column.add_child(_plot_details)
	_growth_bar = ProgressBar.new()
	_growth_bar.custom_minimum_size.y = 20
	_growth_bar.max_value = 100
	_growth_bar.step = 0.1
	_growth_bar.mouse_filter = Control.MOUSE_FILTER_PASS
	var track := StyleBoxFlat.new()
	track.bg_color = Color("2c4148")
	track.set_corner_radius_all(3)
	_growth_bar.add_theme_stylebox_override("background", track)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("839e6e")
	fill.set_corner_radius_all(3)
	_growth_bar.add_theme_stylebox_override("fill", fill)
	_growth_bar.add_theme_font_size_override("font_size", 14)
	column.add_child(_growth_bar)
	_tile_description = _paragraph("", 18)
	column.add_child(_tile_description)
	column.add_child(HSeparator.new())
	_player_label = _label("", 18)
	column.add_child(_player_label)
	column.add_child(_paragraph("WASD 移动 · 右键检查", 16))
	var utility_row := HBoxContainer.new()
	utility_row.add_theme_constant_override("separation", 8)
	_grid_button = _button("网格 [G]", farm_view.toggle_grid)
	_grid_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	utility_row.add_child(_grid_button)
	var reset_button := _button("回到入口 [R]", farm_view.reset_player)
	reset_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	utility_row.add_child(reset_button)
	column.add_child(utility_row)
	column.add_child(HSeparator.new())
	var market_row := HBoxContainer.new()
	market_row.add_theme_constant_override("separation", 8)
	_cash_label = _label("", 20, ACCENT)
	_cash_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	market_row.add_child(_cash_label)
	_market_button = _button("集市 [B]", _open_market)
	market_row.add_child(_market_button)
	column.add_child(market_row)
	_produce_label = _paragraph("", 17, TEXT)
	column.add_child(_produce_label)
	var engineering_row := HBoxContainer.new()
	column.add_child(engineering_row)
	var workbench_button := _button("灌溉 [E]", _open_workbench)
	workbench_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	engineering_row.add_child(workbench_button)
	sensor_button = _button("测量台 [I]", _open_sensor)
	sensor_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	engineering_row.add_child(sensor_button)
	engineering_row.add_child(_button("自动 [T]", _open_automation))
	_engineering_label = _paragraph("尚未组装灌溉装置", 15)
	column.add_child(_engineering_label)
	var filler := Control.new()
	filler.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(filler)
	var footer_row := HBoxContainer.new()
	footer_row.add_theme_constant_override("separation", 8)
	save_button = _button("保存 F5", _save_from_button)
	save_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer_row.add_child(save_button)
	load_button = _button("读取 F9", _request_load)
	load_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer_row.add_child(load_button)
	var quit_button := _button("退出", _request_quit)
	quit_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer_row.add_child(quit_button)
	column.add_child(footer_row)
	save_status = _label("尚未存档", 14, MUTED)
	save_status.tooltip_text = save_service.path
	column.add_child(save_status)
	_feedback_label = _label("先走到附近的草地，按 2 锄地，再按 3 播种、按 4 浇水。", 17, MUTED)
	root.add_child(_feedback_label)
	_refresh_inspector(farm_view.selected_cell)
	_refresh_player(farm_view.player.cell())
	farm_view.farm.supplies_changed.connect(_refresh_produce)
	farm_view.farm.economy_changed.connect(_refresh_cash)
	_refresh_produce()
	_refresh_cash()
	market_panel = MarketPanel.new()
	market_panel.name = "MarketPanel"
	market_panel.setup(farm_view.economy, farm_view.simulation.clock)
	market_panel.opened.connect(func() -> void: farm_view.interaction_enabled = false)
	market_panel.closed.connect(_market_closed)
	add_child(market_panel)
	workbench_panel = WorkbenchPanel.new()
	workbench_panel.name = "WorkbenchPanel"
	workbench_panel.setup(farm_view.engineering, farm_view.simulation.clock)
	workbench_panel.opened.connect(func() -> void: farm_view.interaction_enabled = false)
	workbench_panel.closed.connect(_market_closed)
	add_child(workbench_panel)
	var sensor_link := _button("测量台 [I]", _open_sensor)
	workbench_panel.close_button.get_parent().add_child(sensor_link)
	sensor_panel = SensorPanel.new()
	sensor_panel.name = "SensorPanel"
	sensor_panel.setup(farm_view.sensor_controller)
	sensor_panel.opened.connect(func() -> void: farm_view.interaction_enabled = false)
	sensor_panel.closed.connect(_market_closed)
	add_child(sensor_panel)
	automation_panel = AutomationPanel.new()
	automation_panel.name = "AutomationPanel"
	automation_panel.setup(farm_view.simulation.automation, farm_view.economy)
	automation_panel.opened.connect(func() -> void: farm_view.interaction_enabled = false)
	automation_panel.closed.connect(_market_closed)
	add_child(automation_panel)
	lab_panel = SensorLabPanel.new()
	lab_panel.name = "SensorLabPanel"
	lab_panel.setup(farm_view.learning)
	lab_panel.opened.connect(func() -> void: farm_view.interaction_enabled = false)
	lab_panel.closed.connect(_market_closed)
	lab_panel.navigation_requested.connect(func(destination: String) -> void:
		if destination == "E": _open_workbench()
		elif destination == "I": _open_sensor()
		elif destination == "T": _open_automation())
	add_child(lab_panel)
	tutorial_panel = TutorialPanel.new()
	tutorial_panel.name = "TutorialPanel"
	tutorial_panel.setup(farm_view.tutorial)
	tutorial_panel.opened.connect(func() -> void: farm_view.interaction_enabled = false)
	tutorial_panel.closed.connect(_market_closed)
	tutorial_panel.navigation_requested.connect(_tutorial_navigate)
	add_child(tutorial_panel)
	market_panel.comparison_requested.connect(func() -> void: _open_tutorial(1))
	for key in ["journey_changed", "learning_changed", "economy_changed", "supplies_changed", "engineering_changed", "sensor_changed", "automation_changed"]:
		farm_view.farm.connect(key, _refresh_guidance)
	farm_view.simulation.updated.connect(_refresh_guidance)
	_refresh_guidance()
	farm_view.farm.automation_changed.connect(_refresh_engineering)
	farm_view.farm.sensor_changed.connect(_refresh_sensor_shortcut)
	farm_view.simulation.clock.controls_changed.connect(_refresh_sensor_shortcut)
	farm_view.sensor_controller.action_completed.connect(func(result: Dictionary) -> void: _show_feedback(result.message))
	_refresh_sensor_shortcut()
	farm_view.farm.engineering_changed.connect(_refresh_engineering)
	farm_view.simulation.updated.connect(_refresh_engineering)
	farm_view.simulation.clock.controls_changed.connect(_refresh_engineering)
	farm_view.engineering.action_completed.connect(func(result: Dictionary) -> void: _show_feedback(result.message))
	_refresh_engineering()


func _setup_save_ui() -> void:
	load_dialog = ConfirmationDialog.new()
	load_dialog.title = "读取农场"
	load_dialog.ok_button_text = "读取"
	load_dialog.cancel_button_text = "取消"
	load_dialog.confirmed.connect(_confirm_load)
	load_dialog.canceled.connect(_cancel_dialog)
	add_child(load_dialog)
	quit_dialog = ConfirmationDialog.new()
	quit_dialog.title = "离开农场"
	quit_dialog.ok_button_text = "保存并退出"
	quit_dialog.cancel_button_text = "取消"
	quit_dialog.add_button("不保存退出", true, "discard")
	quit_dialog.confirmed.connect(_save_and_quit)
	quit_dialog.canceled.connect(_cancel_dialog)
	quit_dialog.custom_action.connect(func(action: StringName) -> void:
		if action == &"discard": get_tree().quit())
	add_child(quit_dialog)
	farm_view.simulation.updated.connect(_mark_dirty)
	farm_view.tools.action_completed.connect(func(result: Dictionary) -> void:
		if result.changed: _manual_progress())
	farm_view.farm.economy_changed.connect(_manual_progress)
	farm_view.farm.engineering_changed.connect(_manual_progress)
	farm_view.farm.sensor_changed.connect(_manual_progress)
	farm_view.farm.automation_changed.connect(_manual_progress)
	farm_view.farm.learning_changed.connect(_manual_progress)
	farm_view.farm.journey_changed.connect(_manual_progress)
	farm_view.tools.selection_changed.connect(_mark_dirty)
	farm_view.presentation_changed.connect(_mark_dirty)
	farm_view.player_position_changed.connect(_manual_progress)
	farm_view.simulation.clock.controls_changed.connect(func() -> void: _check_controls_dirty.call_deferred())
	if save_service.exists() and not _smoke_test and _capture_path.is_empty():
		farm_view.simulation.clock.set_paused(true)
		_show_feedback("发现已有存档，按 F9 继续上次农场；当前未自动读取或覆盖。")
	_refresh_save_status()


func _manual_progress() -> void:
	if _restoring: return
	_has_progress = true
	_mark_dirty()


func _mark_dirty() -> void:
	if _restoring or save_status == null: return
	_dirty = true
	_refresh_save_status()


func _effective_pause() -> bool:
	if _dialog_active: return _dialog_effective_pause
	if workbench_panel != null and workbench_panel.visible: return workbench_panel._previous_pause
	return market_panel._previous_pause if market_panel != null and market_panel.visible else farm_view.simulation.clock.paused


func _check_controls_dirty() -> void:
	if not is_inside_tree() or _restoring: return
	if farm_view.simulation.clock.speed != int(_saved_controls.speed) or _effective_pause() != bool(_saved_controls.paused):
		_mark_dirty()


func _refresh_save_status() -> void:
	if save_status == null: return
	load_button.disabled = not save_service.exists()
	if _loaded_backup:
		save_status.text = "备份已恢复 · 请按 F5 保存"
	elif _loaded_legacy:
		save_status.text = "旧版已导入 · 请按 F5 保存"
	elif _saved_minute >= 0:
		save_status.text = "%s · 上次 %s" % ["未保存进度" if _dirty else "已保存", _stamp(_saved_minute)]
	elif save_service.exists() and not _has_progress:
		save_status.text = "已有存档 · 按 F9 继续"
	else:
		save_status.text = "当前进度尚未保存"


func _stamp(minute: int) -> String:
	return "第%d天 %02d:%02d" % [minute / 1440 + 1, minute % 1440 / 60, minute % 60]


func _save_from_button() -> void:
	_save_game()


func _save_game() -> Dictionary:
	var result := save_service.save(farm_view, _effective_pause())
	if result.ok:
		_dirty = false
		_has_progress = true
		_loaded_backup = false
		_loaded_legacy = false
		_saved_minute = farm_view.simulation.clock.total_minutes
		_saved_controls = {"speed": farm_view.simulation.clock.speed, "paused": _effective_pause()}
		_refresh_save_status()
		_post_save_message("已保存农场：%s。" % _stamp(_saved_minute))
	else:
		_post_save_message("保存失败：" + result.message)
	return result


func _post_save_message(message: String) -> void:
	_show_feedback(message)
	if market_panel.visible:
		market_panel.receipt_label.text = message
	if workbench_panel.visible: workbench_panel.receipt_label.text = message
	if sensor_panel.visible: sensor_panel.receipt_label.text = message
	if automation_panel.visible: automation_panel.receipt_label.text = message
	if lab_panel.visible: lab_panel.receipt_label.text = message
	if tutorial_panel.visible: tutorial_panel.receipt_label.text = message


func _request_load() -> void:
	if _dialog_active: return
	_pending_backup = false
	var primary := save_service.read()
	if not primary.ok:
		var backup := save_service.read(true)
		if not backup.ok:
			_post_save_message("读取失败：" + primary.message + " 当前农场保持不变。")
			return
		_pending_backup = true
		_begin_dialog(load_dialog, "主存档无法读取：%s\n发现上一次有效备份（%s）。\n是否读取备份？当前未保存进度将被替换。" % [primary.message, _stamp(backup.game_minutes)])
	elif primary.get("legacy", false):
		_begin_dialog(load_dialog, "发现第 %d 版存档（%s）。\n将保留原文件，导入已有农场进度。\n当前未保存进度会被替换；导入后按 F5 保存到自动化版，是否继续？" % [int(primary.legacy_version), _stamp(primary.game_minutes)])
	elif _has_progress and _dirty:
		_begin_dialog(load_dialog, "将读取 %s 的存档。\n当前未保存进度将被替换，是否继续？" % _stamp(primary.game_minutes))
	else:
		_perform_load(false)


func _begin_dialog(dialog: ConfirmationDialog, message: String) -> void:
	_dialog_was_paused = farm_view.simulation.clock.paused
	_dialog_effective_pause = _effective_pause()
	_dialog_interaction = farm_view.interaction_enabled
	_dialog_active = true
	farm_view.interaction_enabled = false
	farm_view.simulation.clock.set_paused(true)
	dialog.dialog_text = message
	dialog.popup_centered(Vector2i(660, 220))


func _cancel_dialog() -> void:
	load_dialog.hide()
	quit_dialog.hide()
	farm_view.simulation.clock.set_paused(_dialog_was_paused)
	farm_view.interaction_enabled = _dialog_interaction
	_dialog_active = false
	if farm_view.interaction_enabled: farm_view.grab_focus()


func _confirm_load() -> void:
	_perform_load(_pending_backup)


func _perform_load(use_backup: bool) -> void:
	var result := save_service.read(use_backup)
	if not result.ok:
		if _dialog_active: _cancel_dialog()
		_post_save_message("读取失败：" + result.message + " 当前农场保持不变。")
		return
	_restoring = true
	load_dialog.hide()
	quit_dialog.hide()
	_dialog_active = false
	if market_panel.visible: market_panel.close_market()
	if workbench_panel.visible: workbench_panel.close_workbench()
	if sensor_panel.visible: sensor_panel.close_panel()
	if automation_panel.visible: automation_panel.close_panel()
	if lab_panel.visible: lab_panel.close_panel()
	if tutorial_panel.visible: tutorial_panel.close_panel()
	var applied := save_service.apply_read(farm_view, result)
	_restoring = false
	if not applied.ok:
		_post_save_message("读取失败：" + applied.message)
		return
	farm_view.interaction_enabled = true
	_has_progress = true
	_loaded_legacy = result.get("legacy", false)
	_dirty = use_backup or _loaded_legacy
	_loaded_backup = use_backup
	_saved_minute = int(result.game_minutes)
	_saved_controls = {"speed": farm_view.simulation.clock.speed, "paused": farm_view.simulation.clock.paused}
	_previous_actor_cell = farm_view.player.cell()
	_refresh_save_status()
	var prefix: String = "已恢复备份，请按 F5 保存" if use_backup else ("旧版已导入，请按 F5 保存" if _loaded_legacy else "已读取农场")
	_post_save_message("%s：%s。" % [prefix, _stamp(_saved_minute)])
	farm_view.grab_focus()


func _request_quit() -> void:
	if _dialog_active: return
	if _has_progress and _dirty:
		_begin_dialog(quit_dialog, "当前农场有未保存进度。\n保存后退出，或选择不保存退出。")
	else:
		get_tree().quit()


func _save_and_quit() -> void:
	if _save_game().ok:
		get_tree().quit()
	else:
		_cancel_dialog()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and is_node_ready():
		_request_quit()


func _refresh_inspector(cell: Vector2i) -> void:
	var info := farm_view.farm.describe(cell)
	_selected_coords.text = "地块坐标  (%02d, %02d)" % [cell.x + 1, cell.y + 1]
	_selected_title.text = info.name
	_terrain_properties.text = "%s · %s" % ["可通行" if info.walkable else "不可通行", "可耕地" if info.arable else "不可耕作"]
	_tile_description.text = info.description
	_growth_bar.visible = false
	if info.arable:
		var plot := farm_view.farm.plot_at(cell)
		var crop_name: String = "空地" if plot.crop.is_empty() else FarmView.FarmState.SEED_NAMES[plot.crop.id]
		var rates := farm_view.simulation.water_rates_at(cell)
		_plot_details.text = "耕作：%s\n体积含水量：%.1f%%\n水分趋势：%+.1f 百分点/时\n作物：%s" % ["已翻土" if plot.tilled else "未翻土", float(plot.moisture), float(rates.net), crop_name]
		_plot_details.tooltip_text = "每游戏小时：雨水 +%.2f、灌溉预计 +%.2f、蒸发 -%.2f、排水 -%.2f、作物耗水 -%.2f 个百分点。灌溉按下一步可用资源估算；暂停时不推进。" % [rates.rain, rates.irrigation, rates.evaporation, rates.drainage, rates.transpiration]
		if not plot.crop.is_empty():
			var status := farm_view.simulation.crops.describe(plot, farm_view.simulation.clock.is_daylight_at(farm_view.simulation.clock.total_minutes))
			_selected_title.text = crop_name + " · " + status.stage
			_growth_bar.visible = true
			_growth_bar.value = status.progress
			if status.ready:
				_growth_bar.tooltip_text = "基准生长期 %.0f 小时，本次成熟用时 %.1f 小时。" % [status.base_hours, status.age_hours]
			else:
				_growth_bar.tooltip_text = "基准生长期 %.0f 小时，已种植 %.1f 小时。当前速度为基准的 %.0f%%。" % [status.base_hours, status.age_hours, float(status.rate) * 100.0]
			_tile_description.text = status.reason + ("" if status.ready else "（%.0f%% 速度）" % (float(status.rate) * 100.0)) + "\n" + status.help
		elif plot.tilled:
			_selected_title.text = "已翻土"
			_tile_description.text = "翻土完成，可以选择种子播种，也可以先浇水。"
	else:
		_plot_details.text = "该地块不能耕作。"


func _refresh_produce() -> void:
	var items := PackedStringArray()
	for id in FarmView.FarmState.SEED_ORDER:
		items.append("%s ×%d" % [FarmView.FarmState.SEED_NAMES[id], int(farm_view.farm.produce_stock[id])])
	_produce_label.text = "　".join(items)


func _refresh_cash() -> void:
	_cash_label.text = "资金 %d 币" % farm_view.farm.cash


func _open_market() -> void:
	if tutorial_panel.visible: tutorial_panel.close_panel()
	if lab_panel.visible: lab_panel.close_panel()
	if automation_panel.visible: automation_panel.close_panel()
	if workbench_panel.visible: workbench_panel.close_workbench()
	if sensor_panel.visible: sensor_panel.close_panel()
	market_panel.open_market()


func _open_workbench() -> void:
	if tutorial_panel.visible: tutorial_panel.close_panel()
	if lab_panel.visible: lab_panel.close_panel()
	if automation_panel.visible: automation_panel.close_panel()
	if market_panel.visible: market_panel.close_market()
	if sensor_panel.visible: sensor_panel.close_panel()
	workbench_panel.open_workbench()


func _open_sensor() -> void:
	if tutorial_panel.visible: tutorial_panel.close_panel()
	if lab_panel.visible: lab_panel.close_panel()
	if automation_panel.visible: automation_panel.close_panel()
	if market_panel.visible: market_panel.close_market()
	if workbench_panel.visible: workbench_panel.close_workbench()
	sensor_panel.open_panel()


func _open_automation() -> void:
	if tutorial_panel.visible: tutorial_panel.close_panel()
	if lab_panel.visible: lab_panel.close_panel()
	if market_panel.visible: market_panel.close_market()
	if workbench_panel.visible: workbench_panel.close_workbench()
	if sensor_panel.visible: sensor_panel.close_panel()
	automation_panel.open_panel()


func _open_lab() -> void:
	if tutorial_panel.visible: tutorial_panel.close_panel()
	if market_panel.visible: market_panel.close_market()
	if workbench_panel.visible: workbench_panel.close_workbench()
	if sensor_panel.visible: sensor_panel.close_panel()
	if automation_panel.visible: automation_panel.close_panel()
	lab_panel.open_panel()


func _open_tutorial(tab: int = 0) -> void:
	if market_panel.visible: market_panel.close_market()
	if workbench_panel.visible: workbench_panel.close_workbench()
	if sensor_panel.visible: sensor_panel.close_panel()
	if automation_panel.visible: automation_panel.close_panel()
	if lab_panel.visible: lab_panel.close_panel()
	tutorial_panel.open_panel(tab)


func _tutorial_navigate(destination: String) -> void:
	if destination in ["farm", "locate"]:
		tutorial_panel.close_panel()
		if destination == "locate":
			farm_view.selected_cell = farm_view.tutorial.target()
			farm_view.tile_selected.emit(farm_view.selected_cell)
			farm_view.queue_redraw()
			_mark_dirty()
	elif destination == "B": _open_market()
	elif destination == "E": _open_workbench()
	elif destination == "I": _open_sensor()
	elif destination == "T": _open_automation()
	elif destination == "L": _open_lab()


func _refresh_guidance() -> void:
	if _guide_label == null: return
	var row := farm_view.tutorial.current()
	_guide_label.text = "当前目标：%s · H 查看路线\n%s" % [row.title, farm_view.tutorial.hint()]


func _refresh_sensor_shortcut() -> void:
	var measured := farm_view.simulation.sensor.current(farm_view.simulation.clock.total_minutes)
	sensor_button.text = "测量 I · %.1f%%" % measured.reading if measured.valid else ("测量 I · 无效" if farm_view.farm.sensor.installed else "测量台 [I]")
	sensor_button.tooltip_text = FarmView.SensorController.Model.REASONS[measured.code]


func _refresh_engineering() -> void:
	var state: Dictionary = farm_view.farm.engineering
	if state.tank.is_empty() and state.pump.is_empty() and state.power.is_empty():
		_engineering_label.text = "按 E 采购模块并连接上方试验田。"
	else:
		var status := farm_view.simulation.irrigation.status()
		var paused: bool = farm_view.simulation.clock.paused
		_engineering_label.text = "%s%s\n水 %.1f L · 电 %.1f Wh · 出水 %.1f L/h" % ["已暂停 · " if paused else "", status.reason, state.water_l, state.energy_wh, 0.0 if paused else status.flow_l_h]


func _market_closed() -> void:
	farm_view.interaction_enabled = true
	farm_view.grab_focus()


func _input(event: InputEvent) -> void:
	if _dialog_active: return
	if tutorial_panel != null and event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_H:
		if tutorial_panel.visible: tutorial_panel.close_panel()
		else: _open_tutorial()
		get_viewport().set_input_as_handled()
		return
	if tutorial_panel != null and tutorial_panel.visible and event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ESCAPE: tutorial_panel.close_panel()
		elif event.physical_keycode == KEY_B: _open_market()
		elif event.physical_keycode == KEY_E: _open_workbench()
		elif event.physical_keycode == KEY_I: _open_sensor()
		elif event.physical_keycode == KEY_T: _open_automation()
		elif event.physical_keycode == KEY_L: _open_lab()
		elif event.physical_keycode == KEY_SPACE: farm_view.simulation.clock.toggle_paused()
		elif event.physical_keycode == KEY_F5: _save_game()
		elif event.physical_keycode == KEY_F9: _request_load()
		else: return
		get_viewport().set_input_as_handled()
		return
	if lab_panel != null and event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_L:
		if lab_panel.visible: lab_panel.close_panel()
		else: _open_lab()
		get_viewport().set_input_as_handled()
		return
	if lab_panel != null and lab_panel.visible and event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode in [KEY_L, KEY_ESCAPE]: lab_panel.close_panel()
		elif event.physical_keycode == KEY_E: _open_workbench()
		elif event.physical_keycode == KEY_I: _open_sensor()
		elif event.physical_keycode == KEY_T: _open_automation()
		elif event.physical_keycode == KEY_B: _open_market()
		elif event.physical_keycode == KEY_SPACE: farm_view.simulation.clock.toggle_paused()
		elif event.physical_keycode == KEY_F5: _save_game()
		elif event.physical_keycode == KEY_F9: _request_load()
		else: return
		get_viewport().set_input_as_handled()
		return
	if automation_panel != null and automation_panel.visible and event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode in [KEY_T, KEY_ESCAPE]: automation_panel.close_panel()
		elif event.physical_keycode == KEY_E: _open_workbench()
		elif event.physical_keycode == KEY_I: _open_sensor()
		elif event.physical_keycode == KEY_B: _open_market()
		elif event.physical_keycode == KEY_SPACE: farm_view.simulation.clock.toggle_paused()
		elif event.physical_keycode == KEY_F5: _save_game()
		elif event.physical_keycode == KEY_F9: _request_load()
		else: return
		get_viewport().set_input_as_handled()
		return
	if sensor_panel != null and sensor_panel.visible and event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode in [KEY_I, KEY_ESCAPE]: sensor_panel.close_panel()
		elif event.physical_keycode == KEY_E: _open_workbench()
		elif event.physical_keycode == KEY_B: _open_market()
		elif event.physical_keycode == KEY_SPACE: farm_view.simulation.clock.toggle_paused()
		elif event.physical_keycode == KEY_F5: _save_game()
		elif event.physical_keycode == KEY_F9: _request_load()
		else: return
		get_viewport().set_input_as_handled()
		return
	if workbench_panel != null and workbench_panel.visible and event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode in [KEY_E, KEY_ESCAPE]: workbench_panel.close_workbench()
		elif event.physical_keycode == KEY_B: _open_market()
		elif event.physical_keycode == KEY_F5: _save_game()
		elif event.physical_keycode == KEY_F9: _request_load()
		elif event.physical_keycode != KEY_SPACE: return
		get_viewport().set_input_as_handled()
		return
	if market_panel != null and market_panel.visible and event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode in [KEY_B, KEY_ESCAPE]:
			market_panel.close_market()
			get_viewport().set_input_as_handled()
		elif event.physical_keycode == KEY_SPACE:
			get_viewport().set_input_as_handled()
		elif event.physical_keycode == KEY_F5:
			_save_game()
			get_viewport().set_input_as_handled()
		elif event.physical_keycode == KEY_F9:
			_request_load()
			get_viewport().set_input_as_handled()


func _refresh_player(cell: Vector2i) -> void:
	_player_label.text = "角色位置  (%02d, %02d)" % [cell.x + 1, cell.y + 1]
	if cell != _previous_actor_cell:
		_previous_actor_cell = cell
		_manual_progress()


func _refresh_hover(cell: Vector2i) -> void:
	if farm_view.farm.contains(cell):
		_hover_label.text = "悬停地块  (%02d, %02d) · %s" % [cell.x + 1, cell.y + 1, farm_view.farm.describe(cell).name]
	else:
		_hover_label.text = "鼠标移入农场可以查看地块位置。"


func _show_feedback(message: String) -> void:
	_feedback_label.text = message
	_grid_button.text = "%s网格 [G]" % ("隐藏" if farm_view.show_grid else "显示")


func _unhandled_key_input(event: InputEvent) -> void:
	if _dialog_active: return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_L:
			_open_lab()
			get_viewport().set_input_as_handled()
		elif event.physical_keycode == KEY_T:
			_open_automation()
			get_viewport().set_input_as_handled()
		elif event.physical_keycode == KEY_I:
			_open_sensor()
			get_viewport().set_input_as_handled()
		elif event.physical_keycode == KEY_E:
			_open_workbench()
			get_viewport().set_input_as_handled()
		elif event.physical_keycode == KEY_B:
			_open_market()
			get_viewport().set_input_as_handled()
		elif event.physical_keycode == KEY_SPACE:
			farm_view.simulation.clock.toggle_paused()
			get_viewport().set_input_as_handled()
		elif event.physical_keycode == KEY_F5:
			_save_game()
			get_viewport().set_input_as_handled()
		elif event.physical_keycode == KEY_F9:
			_request_load()
			get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if not _smoke_test and _capture_path.is_empty():
		return
	_qa_frames += 1
	if _qa_frames != 8:
		return
	if not _capture_path.is_empty():
		await RenderingServer.frame_post_draw
		var capture := get_viewport().get_texture().get_image()
		var result := capture.save_png(_capture_path)
		if result != OK:
			push_error("Could not save validation capture: %s" % error_string(result))
			get_tree().quit(1)
			return
		print("FIELDWORKS_CAPTURE_OK ", _capture_path)
	print("FIELDWORKS_BOOT_OK ", Engine.get_version_info().string)
	get_tree().quit(0)
