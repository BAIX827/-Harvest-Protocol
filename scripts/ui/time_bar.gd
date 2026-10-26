extends HBoxContainer

const FarmSimulation = preload("res://scripts/simulation/farm_simulation.gd")

var simulation: FarmSimulation
var pause_button: Button
var speed_buttons: Dictionary = {}
var clock_label: Label
var weather_label: Label


func setup(value: FarmSimulation) -> void:
	simulation = value
	add_theme_constant_override("separation", 8)
	clock_label = Label.new()
	clock_label.add_theme_font_size_override("font_size", 18)
	clock_label.custom_minimum_size.x = 185
	add_child(clock_label)
	weather_label = Label.new()
	weather_label.add_theme_font_size_override("font_size", 17)
	weather_label.custom_minimum_size.x = 148
	weather_label.tooltip_text = "当前天气与降雨强度。雨水增加土壤水分，晴天和白昼蒸发更快。"
	add_child(weather_label)
	pause_button = Button.new()
	pause_button.focus_mode = Control.FOCUS_NONE
	pause_button.tooltip_text = "暂停时间、天气与自然水分变化，仍可移动和使用工具。选择速度可继续模拟。"
	pause_button.pressed.connect(simulation.clock.toggle_paused)
	add_child(pause_button)
	var group := ButtonGroup.new()
	for speed in simulation.clock.SPEEDS:
		var button := Button.new()
		button.text = "%d×" % speed
		button.toggle_mode = true
		button.button_group = group
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_size_override("font_size", 17)
		button.pressed.connect(_choose_speed.bind(speed))
		button.tooltip_text = "每秒推进 %d 个游戏分钟" % (speed * 10)
		speed_buttons[speed] = button
		add_child(button)
	simulation.updated.connect(_refresh)
	simulation.clock.controls_changed.connect(_refresh)
	_refresh()


func _choose_speed(value: int) -> void:
	simulation.clock.set_speed(value)
	simulation.clock.set_paused(false)


func _refresh() -> void:
	clock_label.text = "第 %d 天  %s  %s" % [simulation.clock.day(), simulation.clock.time_text(), simulation.clock.period_name()]
	var current := simulation.weather.current()
	weather_label.text = "%s · %.1f mm/h" % [current.name, float(current.rain_mm_h)]
	pause_button.text = "继续 [空格]" if simulation.clock.paused else "暂停 [空格]"
	for speed in speed_buttons:
		speed_buttons[speed].set_pressed_no_signal(speed == simulation.clock.speed)
