extends SceneTree
## 밸런스 점검: 같은 팀을 AI가 몰 때와 봇(내 차)이 몰 때 평균 순위 비교 + 팀 강도 순위별 레이스당 포인트
## 실행: godot --headless --path . --script res://tests/calib.gd

const RaceSimS = preload("res://scripts/sim/race_sim.gd")
const WeekendS = preload("res://scripts/sim/weekend.gd")
const DB = preload("res://scripts/data/game_db.gd")
var pen_n := 0
var dnf_n := 0
const CIRCS = ["melbourne", "bahrain", "monaco", "silverstone", "monza", "suzuka", "singapore", "interlagos"]


func _race(team: int, mode: String, key: String, seed_v: int, diff: int = 1) -> Dictionary:
	var sim = RaceSimS.new()
	sim.new_race(key, team if mode != "ai" else -1, 15, "auto", ["M", "M"], seed_v, {"difficulty": diff})
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
	for c0 in sim.cars:
		if c0.time_pen > 0.0:
			pen_n += 1
		if c0.dnf != "" and not c0.mine:
			dnf_n += 1
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
	# 난이도별: 윌리엄스 봇(주말 포함) 평균 순위
	for diff in RaceSimS.DIFF_KO.size():
		var tp = 0.0
		var nn = 0
		pen_n = 0
		dnf_n = 0
		for ci in CIRCS.size():
			for s in 6:
				var r2 = _race(6, "bot_wk", CIRCS[ci], 9500 + ci * 10 + s, diff)
				tp += r2["pos"].get(6, 22.0)
				nn += 1
		print("난이도 %s: 윌리엄스 봇(주말) 평균 순위 %.1f (%d판) · 레이스당 페널티 %.2f건 · AI 리타이어 %.2f대" % [RaceSimS.DIFF_KO[diff], tp / nn, nn, pen_n / float(nn), dnf_n / float(nn)])
	# 타이어 수명: AI 차 스틴트 길이·끝 마모 (마른 레이스, 15랩) + 컴파운드별 랩당 마모
	var st_len := {"S": [], "M": [], "H": []}
	var st_wear := {"S": [], "M": [], "H": []}
	var lap_w := {"S": [], "M": [], "H": []}
	for ci in CIRCS.size():
		for s3 in 2:
			var sim = RaceSimS.new()
			sim.new_race(CIRCS[ci], -1, 15, "dry", ["M", "M"], 8100 + ci * 10 + s3)
			sim.prepare_start()
			var prev_w := {}
			var guard = 0
			while not sim.done and guard < 300000:
				sim.advance(2.0)
				guard += 1
				for c in sim.cars:
					if c.dnf != "" or not RaceSimS.SLICK.has(c.comp):
						continue
					var key: String = "%d|%d" % [c.id, c.pits]
					if c.stint_laps >= 1 and not prev_w.has(key + "|" + str(c.stint_laps)):
						prev_w[key + "|" + str(c.stint_laps)] = true
						if c.stint_laps >= 2:
							lap_w[c.comp].append(c.wear / float(c.stint_laps))
			for c in sim.cars:
				if c.dnf != "":
					continue
				var runs: Array = []
				var cur_c := ""
				var n := 0
				for r in c.lap_times:
					if r["comp"] != cur_c:
						if cur_c != "" and RaceSimS.SLICK.has(cur_c):
							runs.append([cur_c, n])
						cur_c = r["comp"]
						n = 0
					n += 1
				if cur_c != "" and RaceSimS.SLICK.has(cur_c):
					runs.append([cur_c, n])
				for ru in runs:
					st_len[ru[0]].append(ru[1])
				if RaceSimS.SLICK.has(c.comp):
					st_wear[c.comp].append(c.wear)
	var tt := ""
	for k in ["S", "M", "H"]:
		var a: Array = st_len[k]
		var b: Array = lap_w[k]
		var e: Array = st_wear[k]
		var sa := 0.0
		for x in a:
			sa += float(x)
		var sb := 0.0
		for x in b:
			sb += float(x)
		var se := 0.0
		for x in e:
			se += float(x)
		tt += "%s 스틴트 평균 %.1f랩(%d개) · 랩당 마모 %.1f%% · 완주 시 마모 %.0f%%(%d대) / " % [k, sa / maxf(1.0, a.size()), a.size(), sb / maxf(1.0, b.size()) * 100.0, se / maxf(1.0, e.size()) * 100.0, e.size()]
	print("타이어 수명 (15랩 마른 레이스, AI): " + tt)
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
