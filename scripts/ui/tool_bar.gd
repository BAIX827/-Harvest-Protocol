extends VBoxContainer
## Tool selection and supply counts share the controller used by map clicks.

const ToolController = preload("res://scripts/world/tool_controller.gd")
const FarmState = preload("res://scripts/simulation/farm_state.gd")
const CTheme = preload("res://scripts/ui/c_theme.gd")

var controller: ToolController
var tool_buttons: Array[Button] = []
var seed_buttons: Dictionary = {}
var _water_label: Label
var _hint_label: Label


func setup(value: ToolController) -> void:
	controller = value
	add_theme_constant_override("separation", 8)
	var tool_group := ButtonGroup.new()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	add_child(row)
	for tool in range(ToolController.TOOL_NAMES.size()):
		var button := _choice_button("%d  %s" % [tool + 1, ToolController.TOOL_NAMES[tool]])
		button.button_group = tool_group
		button.pressed.connect(controller.select_tool.bind(tool))
		tool_buttons.append(button)
		row.add_child(button)
	var seed_row := HBoxContainer.new()
	seed_row.add_theme_constant_override("separation", 8)
	add_child(seed_row)
	var seed_label := Label.new()
	seed_label.text = "种子 [Q]"
	seed_label.add_theme_font_size_override("font_size", 16)
	seed_row.add_child(seed_label)
	var seed_group := ButtonGroup.new()
	for seed_id in FarmState.SEED_ORDER:
		var button := _choice_button("")
		button.button_group = seed_group
		button.pressed.connect(controller.select_seed.bind(seed_id))
		seed_buttons[seed_id] = button
		var definition := FarmState.CropCatalog.definition(seed_id)
		button.tooltip_text = "基准生长期 %.0f 游戏小时；适宜水分 %.0f–%.0f%%。夜间、缺水或过湿会减慢生长。" % [float(definition.growth_minutes) / 60.0, definition.optimal_min, definition.optimal_max]
		seed_row.add_child(button)
	_water_label = Label.new()
	_water_label.add_theme_font_size_override("font_size", 16)
	seed_row.add_child(_water_label)
	_hint_label = Label.new()
	_hint_label.add_theme_font_size_override("font_size", 16)
	_hint_label.add_theme_color_override("font_color", Color("aebdb6"))
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_hint_label)
	controller.selection_changed.connect(_refresh)
	controller.farm.supplies_changed.connect(_refresh)
	_refresh()


func _choice_button(text_value: String) -> Button:
	var button := Button.new()
	button.text = text_value
	button.toggle_mode = true
	button.focus_mode = Control.FOCUS_NONE
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 17)
	var selected := CTheme.box(Color("394e41"), CTheme.RUNNING, 12, 10)
	button.add_theme_stylebox_override("pressed", selected)
	return button


func _refresh() -> void:
	for index in range(tool_buttons.size()):
		tool_buttons[index].set_pressed_no_signal(index == controller.active_tool)
	for seed_id in seed_buttons:
		var button: Button = seed_buttons[seed_id]
		button.text = "%s ×%d" % [FarmState.SEED_NAMES[seed_id], int(controller.farm.seed_stock[seed_id])]
		button.set_pressed_no_signal(seed_id == controller.selected_seed)
	_water_label.text = "水壶 %d/%d" % [controller.farm.watering_charges, FarmState.CAN_CAPACITY]
	_water_label.tooltip_text = "补满水壶固定 %d 币，无论当前剩余次数。" % int(controller.economy.settings.water_refill_cost)
	_hint_label.text = ToolController.HINTS[controller.active_tool]
	if controller.active_tool == ToolController.Tool.WATER:
		_hint_label.text += "（补满 %d 币）" % int(controller.economy.settings.water_refill_cost)
