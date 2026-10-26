extends Control
## Step 3: tools and supply counts act on the same state as the map and inspector.

const FarmView = preload("res://scripts/world/farm_view.gd")
const ToolBar = preload("res://scripts/ui/tool_bar.gd")

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
var _selected_title: Label
var _selected_coords: Label
var _tile_description: Label
var _terrain_properties: Label
var _player_label: Label
var _hover_label: Label
var _feedback_label: Label
var _grid_button: Button
var _plot_details: Label


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument == "--smoke-test":
			_smoke_test = true
		elif argument.begins_with("--capture="):
			_capture_path = argument.trim_prefix("--capture=")
	_setup_theme()
	_build_interface()


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
	header.add_child(_label("第 3 步 · 地块与工具", 18, ACCENT))
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
	preview_column.add_child(_label("农场试验区", 22))
	preview_column.add_child(_label("24 × 24 地块 · 走近目标，选择工具后左键操作", 16, MUTED))
	farm_view = FarmView.new()
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
	column.add_theme_constant_override("separation", 10)
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
	_tile_description = _paragraph("", 18)
	column.add_child(_tile_description)
	column.add_child(HSeparator.new())
	_player_label = _label("", 18)
	column.add_child(_player_label)
	column.add_child(_paragraph("WASD / 方向键 移动\n1–5 选工具 · Q 选种子\n左键使用工具 · 右键仅检查", 17))
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
	column.add_child(_label("当前进度", 18))
	column.add_child(_paragraph("已开放锄地、播种与浇水。\n当前作物暂不生长；时间与天气将在下一阶段加入。", 17))
	var filler := Control.new()
	filler.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(filler)
	var footer_row := HBoxContainer.new()
	footer_row.add_theme_constant_override("separation", 8)
	var plan_button := _button("开发流程", func() -> void: OS.shell_open(ProjectSettings.globalize_path("res://开发流程与任务拆解.md")))
	plan_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer_row.add_child(plan_button)
	var quit_button := _button("退出", func() -> void: get_tree().quit())
	quit_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer_row.add_child(quit_button)
	column.add_child(footer_row)
	_feedback_label = _label("先走到附近的草地，按 2 锄地，再按 3 播种、按 4 浇水。", 17, MUTED)
	root.add_child(_feedback_label)
	_refresh_inspector(farm_view.selected_cell)
	_refresh_player(farm_view.player.cell())


func _refresh_inspector(cell: Vector2i) -> void:
	var info := farm_view.farm.describe(cell)
	_selected_coords.text = "地块坐标  (%02d, %02d)" % [cell.x + 1, cell.y + 1]
	_selected_title.text = info.name
	_terrain_properties.text = "%s · %s" % ["可通行" if info.walkable else "不可通行", "可耕地" if info.arable else "不可耕作"]
	_tile_description.text = info.description
	if info.arable:
		var plot := farm_view.farm.plot_at(cell)
		var crop_name: String = "空地" if plot.crop.is_empty() else FarmView.FarmState.SEED_NAMES[plot.crop.id] + "（已播种）"
		_plot_details.text = "耕作：%s\n体积含水量：%.0f%%\n作物：%s" % ["已翻土" if plot.tilled else "未翻土", float(plot.moisture), crop_name]
		if not plot.crop.is_empty():
			_selected_title.text = FarmView.FarmState.SEED_NAMES[plot.crop.id] + "种植地"
			_tile_description.text = "已播种，可以用水壶浇水。当前种植原型暂不推进生长。"
		elif plot.tilled:
			_selected_title.text = "已翻土"
			_tile_description.text = "翻土完成，可以选择种子播种，也可以先浇水。"
	else:
		_plot_details.text = "该地块不能耕作。"


func _refresh_player(cell: Vector2i) -> void:
	_player_label.text = "角色位置  (%02d, %02d)" % [cell.x + 1, cell.y + 1]


func _refresh_hover(cell: Vector2i) -> void:
	if farm_view.farm.contains(cell):
		_hover_label.text = "悬停地块  (%02d, %02d) · %s" % [cell.x + 1, cell.y + 1, farm_view.farm.describe(cell).name]
	else:
		_hover_label.text = "鼠标移入农场可以查看地块位置。"


func _show_feedback(message: String) -> void:
	_feedback_label.text = message
	_grid_button.text = "%s网格 [G]" % ("隐藏" if farm_view.show_grid else "显示")


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
