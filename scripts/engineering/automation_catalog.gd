extends RefCounted

const EDGES := ["sensor>decision", "decision>pump"]
const REASONS := {"manual": "手动模式", "below": "低于启动值，开泵", "stop": "达到停止值，停泵", "hold_on": "阈值之间，保持开泵", "hold_off": "阈值之间，保持停泵",
	"controller_missing": "控制器未安装", "graph_open": "节点链未接通", "sensor_invalid": "探头无有效读数", "sensor_outside": "探头不在出口覆盖的翻土地中",
	"missing_module": "水箱、水泵或电池未安装", "disconnected": "管路未连通", "power_disconnected": "电源断开", "no_water": "水箱缺水", "no_energy": "电量耗尽", "no_demand": "覆盖区无可浇地块"}


static func config() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/automation.json"))


static func initial_state() -> Dictionary:
	var data := config()
	return {"installed": false, "mode": "manual", "start": float(data.start), "stop": float(data.stop), "edges": [], "positions": data.positions.duplicate(true),
		"latch": false, "output": false, "code": "manual", "detail": REASONS.manual, "last_value": null, "last_minute": 480, "sensor_revision": -1, "logs": [], "next_log_id": 1}
