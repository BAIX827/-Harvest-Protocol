extends Control
## Step 1: a runnable, honest engineering baseline. Gameplay starts at step 2.

const BACKGROUND := Color("101b22")
const PANEL := Color("1a2a33")
const BORDER := Color("344953")
const TEXT := Color("e0e7e4")
const MUTED := Color("9fafaF")
const ACCENT := Color("a9c18b")

var _qa_frames: int = 0
var _smoke_test: bool = false
var _capture_path: String = ""


class GridPreview extends Control:

	func _draw() -> void:
		var cell: float = floorf(minf(size.x, size.y) / 24.0)
		var origin := ((size - Vector2.ONE * cell * 24.0) / 2.0).floor()
		for y in range(24):
			for x in range(24):
				var color := Color("30483b") if (x + y) % 2 == 0 else Color("334c3e")
				if x == 5 or y == 13:
					color = Color("82765b")
				if x >= 7 and x <= 12 and y >= 7 and y <= 10:
					color = Color("775c43")
				var rect := Rect2(origin + Vector2(x, y) * cell, Vector2.ONE * cell)
				draw_rect(rect, color)
				draw_rect(rect, Color(0, 0, 0, 0.12), false, 1.0)
		var grid_rect := Rect2(origin, Vector2.ONE * cell * 24.0)
		draw_rect(grid_rect, Color("687c6b"), false, 2.0)

	func _ready() -> void:
		resized.connect(queue_redraw)
		mouse_filter = Control.MOUSE_FILTER_IGNORE


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
	header.add_child(_label("原型开发 · 第 1 步", 18, ACCENT))
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
	preview_column.add_child(_label("24 × 24 网格 · 工程显示验证", 16, MUTED))
	var grid := GridPreview.new()
	grid.name = "GridPreview"
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.custom_minimum_size = Vector2(500, 500)
	preview_column.add_child(grid)
	preview_column.add_child(_paragraph("这是运行基础预览。角色、地块交互和种植将按开发流程逐步实现。", 16))
	var progress_panel := _panel()
	progress_panel.custom_minimum_size.x = 370
	body.add_child(progress_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	progress_panel.add_child(column)
	column.add_child(_label("工程已就绪", 24, ACCENT))
	column.add_child(_paragraph("开发按步骤推进，每一步实现后验证，再更新进度。"))
	column.add_child(_space(12))
	column.add_child(_label("当前基础", 19))
	column.add_child(_paragraph("Godot 4.7.2 · GDScript\nCompatibility 渲染\n中文界面与窗口缩放\n本地启动与运行检查", 18, TEXT))
	column.add_child(_space(12))
	column.add_child(_label("接下来的步骤", 19))
	column.add_child(_paragraph("2  地图、角色与基本操作\n3  地块、工具与交互反馈\n4  时间、天气与水分\n5  作物生命周期\n6  库存、出售与资金", 18))
	var filler := Control.new()
	filler.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(filler)
	var open_plan := Button.new()
	open_plan.text = "打开开发流程文档"
	open_plan.pressed.connect(func() -> void: OS.shell_open(ProjectSettings.globalize_path("res://开发流程与任务拆解.md")))
	column.add_child(open_plan)
	var close_button := Button.new()
	close_button.text = "退出预览"
	close_button.pressed.connect(func() -> void: get_tree().quit())
	column.add_child(close_button)
	root.add_child(_label("第一版目标：手工种植经营 → 模块化灌溉 → 传感反馈控制 → 实验与故障诊断", 17, MUTED))


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
