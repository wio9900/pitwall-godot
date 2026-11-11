extends RefCounted
## 게임 설정 (user://settings.json). 화면이 아닌 값 보관·저장만 한다.

const PATH := "user://settings.json"
const SPEEDS := [1, 2, 4, 8, 16]

static var data := {"volume": 0.8, "engine": true, "speed": 4, "prompts": true, "prompt_slow": true, "ui_scale": 1.0}
static var _loaded := false


static func ensure() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(PATH):
		return
	var f = FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return
	var d = JSON.parse_string(f.get_as_text())
	if typeof(d) == TYPE_DICTIONARY:
		for k in d:
			if data.has(k):
				data[k] = d[k]


static func save() -> void:
	var f = FileAccess.open(PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data))


static func get_v(k: String) -> Variant:
	ensure()
	return data.get(k)


static func set_v(k: String, v) -> void:
	ensure()
	data[k] = v
	save()
	apply_audio()


static func apply_audio() -> void:
	var v: float = clampf(float(data["volume"]), 0.0, 1.0)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(v, 0.0001)))
	AudioServer.set_bus_mute(0, v <= 0.001)
