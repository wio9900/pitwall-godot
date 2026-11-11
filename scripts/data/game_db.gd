extends RefCounted
## 게임 데이터 저장소 (팀·드라이버·엔진·서킷). data/*.json 에서 한 번만 읽어 정적 변수에 보관한다.
## 데이터를 바꾸려면 코드가 아니라 JSON 파일을 수정하면 된다.

const TrackS = preload("res://scripts/sim/track.gd")

static var loaded := false
static var engines: Dictionary = {}
static var teams: Array = []
static var circuits: Dictionary = {}
static var circuit_keys: Array = []
static var career: Dictionary = {}
static var _tracks: Dictionary = {}


static func load_all() -> void:
	if loaded:
		return
	var t = _read_json("res://data/teams_f1.json")
	engines = t["engines"]
	teams = t["teams"]
	circuits = _read_json("res://data/circuits_f1.json")
	circuit_keys = circuits.keys()
	career = _read_json("res://data/career_f1.json")
	loaded = true


static func _read_json(path: String) -> Variant:
	var f = FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("데이터 파일을 열 수 없음: " + path)
		return {}
	var data = JSON.parse_string(f.get_as_text())
	if data == null:
		push_error("JSON 파싱 실패: " + path)
		return {}
	return data


static func track(key: String) -> Variant:
	if not _tracks.has(key):
		var tr = TrackS.new()
		tr.build(key, circuits[key])
		_tracks[key] = tr
	return _tracks[key]
