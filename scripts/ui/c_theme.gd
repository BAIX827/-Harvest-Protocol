extends RefCounted
## C: natural field colors, blue-gray machines and readable dark engineering panels.

const BACKGROUND := Color("101b22")
const PANEL := Color("1a2a33")
const INSET := Color("14232c")
const BORDER := Color("47616f")
const TEXT := Color("e0e7e4")
const MUTED := Color("a6b7ba")
const RUNNING := Color("a9c18b")
const WARNING := Color("d3b67d")
const FAULT := Color("db9583")
const PAUSED := Color("a6b9c8")
const MACHINE := Color("78969f")


static func box(fill: Color, border: Color = BORDER, horizontal: int = 14, vertical: int = 10) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.content_margin_left = horizontal
	style.content_margin_right = horizontal
	style.content_margin_top = vertical
	style.content_margin_bottom = vertical
	return style


static func panel_style() -> StyleBoxFlat:
	return box(PANEL, BORDER, 24, 20)


static func color(kind: String) -> Color:
	return {"running": RUNNING, "valid": RUNNING, "warning": WARNING, "fault": FAULT, "paused": PAUSED, "stopped": MUTED, "idle": MUTED}.get(kind, TEXT)


static func status(label: Label, kind: String) -> void:
	label.add_theme_color_override("font_color", color(kind))


static func create() -> Theme:
	var result := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei", "PingFang SC", "Noto Sans CJK SC", "sans-serif"])
	result.default_font = font
	result.default_font_size = 18
	for type in ["Label", "RichTextLabel", "Button", "OptionButton", "MenuButton", "CheckButton", "CheckBox", "LineEdit", "SpinBox", "PopupMenu", "LinkButton"]:
		result.set_color("font_color", type, TEXT)
		result.set_color("font_disabled_color", type, Color("70838c"))
		result.set_color("font_hover_color", type, Color("f2f1d7"))
		result.set_color("font_focus_color", type, Color("f2f1d7"))
	var surfaces := {"normal": box(Color("293e47")), "hover": box(Color("354d55"), MACHINE),
		"pressed": box(Color("394e49"), RUNNING), "disabled": box(Color("1c2d35"), Color("2e434d")),
		"focus": box(Color.TRANSPARENT, WARNING)}
	for type in ["Button", "OptionButton", "MenuButton"]:
		for key in surfaces: result.set_stylebox(key, type, surfaces[key])
		result.set_color("font_pressed_color", type, TEXT)
		result.set_color("font_hover_pressed_color", type, TEXT)
	for key in ["normal", "hover", "pressed", "disabled"]: result.set_stylebox(key + "_mirrored", "OptionButton", surfaces[key])
	result.set_stylebox("normal", "LineEdit", box(INSET, BORDER, 10, 8))
	result.set_stylebox("read_only", "LineEdit", box(PANEL, Color("2e434d"), 10, 8))
	result.set_stylebox("focus", "LineEdit", box(Color.TRANSPARENT, WARNING, 10, 8))
	result.set_color("selection_color", "LineEdit", Color("49696f"))
	result.set_color("caret_color", "LineEdit", TEXT)
	for type in ["TabBar", "TabContainer"]:
		result.set_stylebox("tab_selected", type, box(Color("2e454e"), MACHINE, 14, 8))
		result.set_stylebox("tab_unselected", type, box(INSET, Color("2e434d"), 14, 8))
		result.set_stylebox("tab_hovered", type, box(Color("354d55"), MACHINE, 14, 8))
		result.set_stylebox("tab_focus", type, box(Color.TRANSPARENT, WARNING, 14, 8))
		result.set_color("font_selected_color", type, TEXT)
		result.set_color("font_unselected_color", type, MUTED)
	result.set_stylebox("panel", "TabContainer", box(INSET, BORDER, 8, 10))
	result.set_stylebox("panel", "PopupMenu", box(INSET, BORDER, 8, 8))
	result.set_stylebox("hover", "PopupMenu", box(Color("354d55"), MACHINE, 8, 8))
	result.set_color("font_accelerator_color", "PopupMenu", MUTED)
	result.set_stylebox("normal", "RichTextLabel", box(INSET, Color("2e434d"), 12, 10))
	for type in ["VScrollBar", "HScrollBar"]:
		result.set_stylebox("scroll", type, box(INSET, INSET, 4, 4))
		result.set_stylebox("grabber", type, box(Color("56717b"), MACHINE, 4, 4))
		result.set_stylebox("grabber_highlight", type, box(MACHINE, MACHINE, 4, 4))
		result.set_stylebox("grabber_pressed", type, box(RUNNING, RUNNING, 4, 4))
	result.set_stylebox("panel", "GraphEdit", box(INSET, BORDER, 8, 8))
	result.set_stylebox("menu_panel", "GraphEdit", box(PANEL, BORDER, 4, 4))
	result.set_color("grid_minor", "GraphEdit", Color("203640"))
	result.set_color("grid_major", "GraphEdit", Color("304852"))
	result.set_stylebox("panel", "GraphNode", box(PANEL, BORDER, 12, 10))
	result.set_stylebox("panel_selected", "GraphNode", box(Color("253c45"), WARNING, 12, 10))
	result.set_stylebox("titlebar", "GraphNode", box(Color("344f5d"), MACHINE, 12, 8))
	result.set_stylebox("titlebar_selected", "GraphNode", box(Color("405d65"), WARNING, 12, 8))
	result.set_stylebox("panel", "TooltipPanel", box(INSET, MACHINE, 12, 10))
	result.set_color("font_color", "TooltipLabel", TEXT)
	result.set_font_size("font_size", "TooltipLabel", 16)
	return result


static func navigation(panel: Control, current: String, navigate: Callable) -> MenuButton:
	var column: VBoxContainer = panel._frame.get_child(0)
	var header: HBoxContainer = column.get_child(0)
	var close: Button = header.get_child(header.get_child_count() - 1)
	close.text = "返回农场 [%s / Esc]" % current
	var policy := Label.new()
	policy.text = "编辑暂停" if current in ["B", "E"] else "实时观察"
	policy.add_theme_font_size_override("font_size", 14)
	policy.add_theme_color_override("font_color", MUTED)
	policy.tooltip_text = "关闭后恢复进入前的时间设置。" if current in ["B", "E"] else "保持当前游戏时间，可用空格控制。"
	header.add_child(policy)
	header.move_child(policy, close.get_index())
	var menu := MenuButton.new()
	menu.text = "切换界面"
	menu.focus_mode = Control.FOCUS_NONE
	menu.add_theme_font_size_override("font_size", 16)
	var choices := {"B": "集市与账本", "E": "灌溉工作台", "I": "探头测量", "T": "自动控制", "L": "实验与故障", "H": "试玩与经营"}
	for key in choices:
		if key != current: menu.get_popup().add_item("%s [%s]" % [choices[key], key], key.unicode_at(0))
	menu.get_popup().id_pressed.connect(func(id: int) -> void: navigate.call(String.chr(id)))
	header.add_child(menu)
	header.move_child(menu, close.get_index())
	header.add_theme_constant_override("separation", 12)
	return menu
