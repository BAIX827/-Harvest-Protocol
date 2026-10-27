extends RefCounted
## Verified temporary write + previous valid backup + same-directory replacement.

const Codec = preload("res://scripts/persistence/save_codec.gd")
const DEFAULT_PATH: String = "user://saves/farm-v3.json"
const FORMAT_VERSION: int = 3
const RULES_REVISION: int = 3
const MAX_FILE_BYTES: int = 16 * 1024 * 1024

var path: String
var _busy: bool = false


func _init(slot_path: String = DEFAULT_PATH) -> void:
	path = ProjectSettings.globalize_path(slot_path)


static func _engine_version() -> String:
	var info := Engine.get_version_info()
	return "%d.%d.%d" % [info.major, info.minor, info.patch]


static func _config_hash(legacy: bool = false, legacy_version: int = 1) -> String:
	var content := {
		"crops": JSON.parse_string(FileAccess.get_file_as_string("res://data/crops.json")),
		"economy": JSON.parse_string(FileAccess.get_file_as_string("res://data/economy.json")),
	}
	if not legacy or legacy_version >= 2:
		content.modules = JSON.parse_string(FileAccess.get_file_as_string("res://data/modules.json"))
		if legacy: content.modules.modules.sensor_basic.available = false
	if not legacy: content.sensor = JSON.parse_string(FileAccess.get_file_as_string("res://data/sensor.json"))
	return JSON.stringify(content, "", true, true).sha256_text()


static func _fail(code: String, message: String) -> Dictionary:
	return {"ok": false, "code": code, "message": message}


func exists() -> bool:
	return FileAccess.file_exists(path) or FileAccess.file_exists(path + ".bak") or (not _legacy_path().is_empty() and FileAccess.file_exists(_legacy_path()))


func _legacy_path() -> String:
	if path != ProjectSettings.globalize_path(DEFAULT_PATH): return ""
	for version in [2, 1]:
		var previous := ProjectSettings.globalize_path("user://saves/farm-v%d.json" % version)
		if FileAccess.file_exists(previous): return previous
	return ""


func envelope(payload: Dictionary) -> Dictionary:
	var body := JSON.stringify(_pack_floats(payload), "", true, true)
	return {"format": "fieldworks-save", "version": FORMAT_VERSION, "rules_revision": RULES_REVISION,
		"engine": _engine_version(), "float_encoding": "ieee754-le-hex", "config_hash": _config_hash(), "saved_at": Time.get_datetime_string_from_system(true),
		"payload_json": body, "sha256": body.sha256_text()}


static func _pack_floats(value: Variant) -> Variant:
	# Godot JSON decimal parsing can round by one ULP even with full_precision.
	# Preserve all 64 bits without deserializing objects or executable resources.
	if value is float:
		var bytes := PackedByteArray()
		bytes.resize(8)
		bytes.encode_double(0, value)
		return {"_float64": bytes.hex_encode()}
	if value is Array:
		var result: Array = []
		for item in value: result.append(_pack_floats(item))
		return result
	if value is Dictionary:
		var result: Dictionary = {}
		for key in value: result[key] = _pack_floats(value[key])
		return result
	return value


static func _unpack_floats(value: Variant) -> Variant:
	if value is Array:
		var result: Array = []
		for item in value: result.append(_unpack_floats(item))
		return result
	if value is Dictionary:
		if value.has("_float64"):
			var encoded: Variant = value._float64
			if value.size() != 1 or not encoded is String or encoded.length() != 16:
				return null
			for character in encoded:
				if character not in "0123456789abcdef": return null
			return encoded.hex_decode().decode_double(0)
		var result: Dictionary = {}
		for key in value: result[key] = _unpack_floats(value[key])
		return result
	return value


func read(use_backup: bool = false) -> Dictionary:
	if not use_backup and not FileAccess.file_exists(path) and not FileAccess.file_exists(path + ".bak") and not _legacy_path().is_empty() and FileAccess.file_exists(_legacy_path()):
		return _read_file(_legacy_path(), true)
	return _read_file(path + ".bak" if use_backup else path)


func _read_file(file_path: String, legacy: bool = false) -> Dictionary:
	if not FileAccess.file_exists(file_path):
		return _fail("missing", "尚无可读取的存档。")
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		return _fail("read_failed", "存档无法打开：%s。" % error_string(FileAccess.get_open_error()))
	if file.get_length() <= 0 or file.get_length() > MAX_FILE_BYTES:
		file.close()
		return _fail("file_size", "存档为空或超过当前版本的文件大小上限。")
	var text := file.get_as_text()
	file.close()
	var parser := JSON.new()
	if parser.parse(text) != OK or not parser.data is Dictionary:
		return _fail("invalid_json", "存档文件损坏，无法解析。")
	var wrapper: Dictionary = parser.data
	var legacy_version: int = int(wrapper.get("version", 0)) if wrapper.get("version") is float or wrapper.get("version") is int else 0
	var version_ok: bool = wrapper.get("version") == FORMAT_VERSION and wrapper.get("rules_revision") == RULES_REVISION
	if legacy: version_ok = legacy_version in [1, 2] and wrapper.get("version") == legacy_version and wrapper.get("rules_revision") == legacy_version
	if wrapper.get("format") != "fieldworks-save" or not version_ok or wrapper.get("float_encoding") != "ieee754-le-hex":
		return _fail("incompatible_version", "存档格式或规则版本不兼容。")
	if wrapper.get("engine") != _engine_version() or wrapper.get("config_hash") != _config_hash(legacy, legacy_version):
		return _fail("incompatible_rules", "存档使用了不同的引擎版本或游戏参数。")
	if not wrapper.get("payload_json") is String or not wrapper.get("sha256") is String or wrapper.payload_json.sha256_text() != wrapper.sha256:
		return _fail("checksum", "存档校验失败，内容可能不完整。")
	if not wrapper.get("saved_at") is String or wrapper.saved_at.length() > 64:
		return _fail("invalid_metadata", "存档时间标记无效。")
	var payload_parser := JSON.new()
	if payload_parser.parse(wrapper.payload_json) != OK:
		return _fail("invalid_payload", "存档内容损坏，无法解析。")
	var payload: Variant = _unpack_floats(payload_parser.data)
	if legacy and payload is Dictionary:
		if payload.has("sensor"): return _fail("invalid_legacy", "旧版存档不应包含传感器状态。")
		if legacy_version == 1:
			if payload.has("engineering"): return _fail("invalid_legacy", "原农业版存档不应包含设备状态。")
			payload.engineering = Codec.Farm.new().engineering.duplicate(true)
		payload.sensor = Codec.Farm.SensorCatalog.initial_state()
	var validated := Codec.validate(payload)
	if not validated.ok:
		return validated
	return {"ok": true, "candidate": validated, "saved_at": wrapper.saved_at,
		"game_minutes": int(validated.runtime.clock.total_minutes), "path": file_path, "legacy": legacy, "legacy_version": legacy_version if legacy else 0}


func save(view: Control, pause_override: Variant = null) -> Dictionary:
	if _busy or view.farm.trade_in_progress:
		return _fail("busy", "交易或存档正在完成，请稍后再保存。")
	var payload := Codec.capture(view, pause_override)
	var checked := Codec.validate(payload)
	if not checked.ok:
		return _fail("invalid_live_state", "当前农场未通过保存校验：" + checked.message)
	_busy = true
	var result := _write(envelope(payload))
	_busy = false
	return result


func _write(wrapper: Dictionary) -> Dictionary:
	var directory := path.get_base_dir()
	var code := DirAccess.make_dir_recursive_absolute(directory)
	if code != OK and code != ERR_ALREADY_EXISTS:
		return _fail("write_failed", "无法创建存档目录：%s。" % error_string(code))
	var temporary := path + ".tmp-%d" % OS.get_process_id()
	var output := FileAccess.open(temporary, FileAccess.WRITE)
	if output == null:
		return _fail("write_failed", "无法写入临时存档：%s。" % error_string(FileAccess.get_open_error()))
	output.store_string(JSON.stringify(wrapper, "\t", true, true))
	output.flush()
	code = output.get_error()
	output.close()
	if code != OK or not _read_file(temporary).ok:
		DirAccess.remove_absolute(temporary)
		return _fail("write_failed", "临时存档写入或回读校验失败，原存档未替换。")
	# A corrupt primary must not replace an existing good backup.
	if _read_file(path).ok:
		var backup_temp := temporary + ".backup"
		code = DirAccess.copy_absolute(path, backup_temp)
		if code == OK:
			code = _promote_file(backup_temp, path + ".bak")
		if code != OK:
			DirAccess.remove_absolute(temporary)
			if FileAccess.file_exists(backup_temp): DirAccess.remove_absolute(backup_temp)
			return _fail("backup_failed", "备份失败，已保留原存档：%s。" % error_string(code))
	code = _promote_file(temporary, path)
	if code != OK:
		if FileAccess.file_exists(temporary): DirAccess.remove_absolute(temporary)
		return _fail("replace_failed", "正式存档无法替换，原存档仍保留：%s。" % error_string(code))
	return {"ok": true, "code": "saved", "message": "保存成功。", "saved_at": wrapper.saved_at, "path": path}


func _promote_file(from_path: String, to_path: String) -> Error:
	return DirAccess.rename_absolute(from_path, to_path)


func apply_read(view: Control, result: Dictionary) -> Dictionary:
	if _busy or view.farm.trade_in_progress:
		return _fail("busy", "交易或读取正在完成，请稍后再试。")
	if not result.get("ok", false) or not result.get("candidate") is Dictionary:
		return _fail("invalid_read", "没有经过校验的存档可读取。")
	_busy = true
	Codec.apply(view, result.candidate)
	_busy = false
	return {"ok": true, "code": "loaded", "message": "读取成功。", "saved_at": result.saved_at, "path": result.path}


func load_into(view: Control, use_backup: bool = false) -> Dictionary:
	var result := read(use_backup)
	return apply_read(view, result) if result.ok else result
