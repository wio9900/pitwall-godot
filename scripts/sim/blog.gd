extends RefCounted
## 버그 기록장: 중요한 사건만 짧게 남기고(최근 MAX줄), 이상하면 "⚠" + 그 순간 상태를 같이 남긴다.
## 설정의 "🐞 버그 기록 복사"로 클립보드에 담아 AI 에게 붙여넣는다. 매 프레임 기록 금지 (사건 때만).

const MAX := 300
const PATH := "user://bug_log.txt"

static var lines: PackedStringArray = []
static var dirty := false
static var loaded := false


static func add(msg: String) -> void:
	if not loaded:
		load_prev()
	var ts: String = Time.get_datetime_string_from_system().substr(5).replace("T", " ")
	lines.append("%s %s" % [ts, msg])
	if lines.size() > MAX:
		lines = lines.slice(lines.size() - MAX)
	dirty = true


## 이상 감지: 바로 파일에도 쓴다 (앱이 꺼져도 남게)
static func warn(msg: String) -> void:
	add("⚠ " + msg)
	save()


static func save() -> void:
	if not dirty:
		return
	var f = FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string("\n".join(lines))
	dirty = false


## 앱을 다시 켜도 이전 기록을 이어서 (시작할 때 한 번)
static func load_prev() -> void:
	loaded = true
	if not FileAccess.file_exists(PATH):
		return
	var f = FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return
	var old: PackedStringArray = f.get_as_text().split("\n", false)
	old.append_array(lines)
	lines = old.slice(maxi(0, old.size() - MAX))


## 복사용 글: 머리말(버전·기기·화면) + ⚠ 요약 + 전체 기록 + Godot 오류 로그 끝부분
static func text() -> String:
	if not loaded:
		load_prev()
	var ver: String = str(ProjectSettings.get_setting("application/config/version", "?"))
	var head: String = "Pit Wall 버그 기록 · 버전 %s · %s %s · 화면 %s\n" % [ver, OS.get_name(), OS.get_model_name(), str(DisplayServer.window_get_size())]
	var warns: PackedStringArray = []
	for l in lines:
		if l.contains("⚠"):
			warns.append(l)
	var out: String = head + "── 이상 감지 %d건 ──\n%s\n── 전체 기록 (%d줄) ──\n%s\n" % [warns.size(), "\n".join(warns), lines.size(), "\n".join(lines)]
	var gl: String = "user://logs/godot.log"
	if FileAccess.file_exists(gl):
		var f = FileAccess.open(gl, FileAccess.READ)
		if f != null:
			var ll: PackedStringArray = f.get_as_text().split("\n", false)
			var err: PackedStringArray = []
			for l in ll:
				if l.contains("ERROR") or l.contains("SCRIPT") or l.contains("at:"):
					err.append(l)
			if not err.is_empty():
				out += "── Godot 오류 (마지막 %d줄) ──\n%s\n" % [mini(40, err.size()), "\n".join(err.slice(maxi(0, err.size() - 40)))]
	return out


static func clear() -> void:
	lines = []
	dirty = true
	save()
