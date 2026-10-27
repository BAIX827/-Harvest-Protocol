extends RefCounted
## Display priority only; never modifies commands, resources or simulation time.

static func describe(network: RefCounted, clock: RefCounted) -> Dictionary:
	var farm: RefCounted = network.farm
	var physical: Dictionary = network.precondition()
	var status: Dictionary = network.status()
	var kind: String = "stopped"
	var title: String = "停止"
	var detail: String = status.reason
	var code: String = physical.code
	if farm.engineering.tank == "" and farm.engineering.pump == "" and farm.engineering.power == "":
		kind = "idle"
		title = "尚未组装"
	elif farm.automation.mode == "auto" and farm.automation.code in ["graph_open", "sensor_invalid", "sensor_outside", "controller_missing"]:
		kind = "fault" if farm.automation.code in ["graph_open", "sensor_invalid"] else "warning"
		title = "保护停机"
		detail = farm.automation.detail
	elif code in ["disconnected", "power_disconnected"]:
		kind = "fault"
		title = "连接故障"
		detail = physical.reason
	elif code in ["no_water", "no_energy", "missing_module"]:
		kind = "warning"
		title = "缺少资源" if code != "missing_module" else "设备未齐"
		detail = physical.reason
	elif clock.paused:
		kind = "paused"
		title = "已暂停"
	elif status.running:
		kind = "running"
		title = "供水中"
	return {"kind": kind, "title": title, "detail": detail, "text": title + " · " + detail,
		"flow_l_h": float(status.flow_l_h) if kind == "running" else 0.0, "paused": clock.paused}
