extends RefCounted
## 기록실: 서킷별 최고 순위·최고 랩·우승·포디움, 전체 누적, 최근 레이스 기록 (user://records.json).
## 퀵 레이스·커리어 모두 집계한다. 화면은 scripts/ui/records_view.gd.

const PATH := "user://records.json"
const LOG_MAX := 40

static var data := {}
static var _loaded := false


static func ensure() -> void:
	if _loaded:
		return
	_loaded = true
	data = {"circuits": {}, "totals": {"races": 0, "wins": 0, "podiums": 0, "points": 0, "dnf": 0}, "log": []}
	if not FileAccess.file_exists(PATH):
		return
	var f = FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return
	var d = JSON.parse_string(f.get_as_text())
	if typeof(d) == TYPE_DICTIONARY:
		for k in data:
			if d.has(k):
				data[k] = d[k]


static func save() -> void:
	var f = FileAccess.open(PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data))


## 레이스 결과 기록. 내 차 중 가장 좋은 순위를 대표로 남긴다.
## mode = "quick" / "career", tag = "스프린트" 등 부가 설명
static func record_race(sim, mode: String, tag: String = "") -> Dictionary:
	ensure()
	var res: Array = sim.results()
	var best_pos := 999
	var best_car: Variant = null
	var pts := 0
	var dnfs := 0
	for r in res:
		var c = r["car"]
		if not c.mine:
			continue
		pts += int(r["points"])
		if c.dnf != "":
			dnfs += 1
			continue
		if int(r["pos"]) < best_pos:
			best_pos = int(r["pos"])
			best_car = c
	var my_best_lap := INF
	var lap_by := ""
	for c in sim.my_cars():
		if c.best < my_best_lap:
			my_best_lap = c.best
			lap_by = c.name
	var key: String = sim.circ_key
	var cr: Dictionary = data["circuits"].get(key, {"name": sim.CIRC.get("name", key), "series": sim.series, "races": 0, "wins": 0, "podiums": 0, "best_pos": 0, "best_lap": 0.0, "best_lap_by": ""})
	var new_marks: Array = []
	cr["races"] = int(cr["races"]) + 1
	if best_car != null:
		if int(cr["best_pos"]) == 0 or best_pos < int(cr["best_pos"]):
			if int(cr["best_pos"]) != 0:
				new_marks.append("서킷 최고 순위 P%d" % best_pos)
			cr["best_pos"] = best_pos
		if best_pos == 1:
			cr["wins"] = int(cr["wins"]) + 1
		if best_pos <= 3:
			cr["podiums"] = int(cr["podiums"]) + 1
	if my_best_lap < INF and (float(cr["best_lap"]) <= 0.0 or my_best_lap < float(cr["best_lap"])):
		if float(cr["best_lap"]) > 0.0:
			new_marks.append("서킷 최고 랩 %s" % fmt_lap(my_best_lap))
		cr["best_lap"] = my_best_lap
		cr["best_lap_by"] = lap_by
	data["circuits"][key] = cr
	var tot: Dictionary = data["totals"]
	tot["races"] = int(tot["races"]) + 1
	tot["points"] = int(tot["points"]) + pts
	tot["dnf"] = int(tot["dnf"]) + dnfs
	if best_pos == 1:
		tot["wins"] = int(tot["wins"]) + 1
	if best_pos <= 3:
		tot["podiums"] = int(tot["podiums"]) + 1
	var team := ""
	if best_car != null:
		team = best_car.team
	elif not sim.my_cars().is_empty():
		team = sim.my_cars()[0].team
	data["log"].push_front({"date": Time.get_date_string_from_system(), "circ": cr["name"], "series": sim.series, "mode": mode, "tag": tag,
		"team": team, "pos": best_pos if best_car != null else 0, "pts": pts, "laps": sim.laps})
	if data["log"].size() > LOG_MAX:
		data["log"].resize(LOG_MAX)
	save()
	return {"marks": new_marks}


static func fmt_lap(t: float) -> String:
	if t <= 0.0 or t == INF:
		return "-"
	return "%d:%06.3f" % [int(t) / 60, fmod(t, 60.0)]
