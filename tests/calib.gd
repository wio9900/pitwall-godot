extends SceneTree
## 밸런스 점검: 같은 팀을 AI가 몰 때와 봇(내 차)이 몰 때 평균 순위 비교 + 팀 강도 순위별 레이스당 포인트
## 실행: godot --headless --path . --script res://tests/calib.gd

const RaceSimS = preload("res://scripts/sim/race_sim.gd")
const WeekendS = preload("res://scripts/sim/weekend.gd")
const DB = preload("res://scripts/data/game_db.gd")
const CIRCS = ["melbourne", "bahrain", "monaco", "silverstone", "monza", "suzuka", "singapore", "interlagos"]


func _race(team: int, mode: String, key: String, seed_v: int) -> Dictionary:
	var sim = RaceSimS.new()
	sim.new_race(key, team if mode != "ai" else -1, 15, "auto", ["M", "M"], seed_v)
	if mode == "bot_wk":
		var wk = WeekendS.new()
		wk.setup(sim, 0)
		wk.auto_practice()
		wk.start_quali()
		wk.auto_quali()
	sim.prepare_start()
	var guard = 0
	while not sim.done and guard < 300000:
		sim.advance(2.0)
		guard += 1
		if mode != "ai":
			for c in sim.my_cars():
				if c.is_running() and c.boxing == null and c.pit_req == "" and sim.wet < 0.2 and c.wear > 0.58 and c.lap < sim.laps - 2:
					sim.request_pit(c, "H" if c.comp != "H" else "M")
	var ord: Array = sim.order()
	var pts := {}
	var pos := {}
	var cls = 0
	for c in ord:
		if c.dnf == "":
			cls += 1
			if cls <= 10:
				pts[c.team_idx] = pts.get(c.team_idx, 0) + RaceSimS.POINTS[cls - 1]
		pos[c.team_idx] = pos.get(c.team_idx, 0.0) + (ord.find(c) + 1) / 2.0
	return {"pts": pts, "pos": pos}


func _init() -> void:
	DB.load_all()
	var n_t: int = DB.teams.size()
	for team in [8, 6]:
		for mode in ["ai", "bot", "bot_wk"]:
			var tot_pos = 0.0
			var tot_pts = 0.0
			var n = 0
			for ci in CIRCS.size():
				for s in 3:
					var r = _race(team, mode, CIRCS[ci], 9000 + ci * 10 + s)
					tot_pos += r["pos"].get(team, 22.0)
					tot_pts += r["pts"].get(team, 0)
					n += 1
			print("%s %s: 평균 순위 %.1f · 레이스당 포인트 %.1f (%d판)" % [DB.teams[team]["name"], mode, tot_pos / n, tot_pts / n, n])
	# 팀별 레이스당 포인트 (AI만)
	var agg := {}
	var n2 = 0
	for ci in CIRCS.size():
		for s in 4:
			var r = _race(0, "ai", CIRCS[ci], 7000 + ci * 10 + s)
			for k in r["pts"]:
				agg[k] = agg.get(k, 0) + r["pts"][k]
			n2 += 1
	var rows = []
	for i in n_t:
		rows.append([DB.teams[i]["name"], agg.get(i, 0) / float(n2)])
	rows.sort_custom(func(a, b): return a[1] > b[1])
	var txt = ""
	for r in rows:
		txt += "%s %.1f / " % [r[0], r[1]]
	print("순위별 레이스당 포인트: " + txt)
	quit()
