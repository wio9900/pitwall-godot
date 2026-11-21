extends SceneTree
## 하이퍼카 타이어 밸런스 측정 (CI 에서 안 돌림 — 밸런스 바꿀 때 손으로 실행)
## 실행: godot --headless --path . --script res://tests/tyre_bal.gd -- table
##       godot --headless --path . --script res://tests/tyre_bal.gd -- race lemans 30 16
## table: 노면 온도 × 스틴트 수(1·2·3) 칸마다 컴파운드별 시간(타이어 교체 시간 나눠 포함)과 이기는 타이어
## race : 서킷·랩·판 수만큼 AI 만 돌려 하이퍼카 컴파운드 랩 비율 · 세트당 스틴트 · 주 컴파운드별 평균 순위

const RaceSimS = preload("res://scripts/sim/race_sim.gd")
const DB = preload("res://scripts/data/game_db.gd")


func _init() -> void:
	DB.load_all()
	var a: PackedStringArray = OS.get_cmdline_user_args()
	var mode: String = a[0] if a.size() > 0 else "table"
	if mode == "table":
		_table(a[1] if a.size() > 1 else "lemans")
	else:
		_races(a[1] if a.size() > 1 else "lemans", int(a[2]) if a.size() > 2 else 30, int(a[3]) if a.size() > 3 else 16)
	quit(0)


func _table(key: String) -> void:
	var sim = RaceSimS.new()
	sim.new_race(key, -1, 60, "dry", ["M", "M"], 99)
	sim.true_mult = {"S": 1.0, "M": 1.0, "H": 1.0}
	var c = null
	for o in sim.cars:
		if o.cls == "HY":
			c = o
			break
	c.pace = "standard"
	c.crew = 0.75
	var tyre_cost: float = sim.wec_stop_time(c, true, false) - sim.wec_stop_time(c, false, false)
	print("%s · 타이어 교체 시간 %.1f초 · 컴파운드 %s · 칸 = 30랩 기준 (타이어 교체 포함) 초, 기준 = 가장 빠른 것" % [key, tyre_cost, sim.wec_comps("HY")])
	var hdr := "온도 |"
	for m in [1, 2, 3]:
		hdr += "      %d스틴트(%d랩)        |" % [m, m * RaceSimS.STINT]
	print(hdr)
	hdr += " 전체 최선 (다른 컴파운드 최선과 차이)"
	for temp in range(18, 41):
		var line := "%3d° |" % temp
		var plan := {}
		for m in [1, 2, 3]:
			var n: int = m * RaceSimS.STINT
			var best := ""
			var best_t := INF
			var cell := {}
			for k in sim.wec_comps("HY"):
				# 30랩 = 같은 스틴트 길이를 30/n 번: 달리는 시간 + 타이어 교체
				var t: float = (sim.comp_run_time(c, String(k), n, float(temp)) + tyre_cost) * 30.0 / n
				cell[k] = t
				if not plan.has(k) or t < float(plan[k][0]):
					plan[k] = [t, m]
				if t < best_t:
					best_t = t
					best = String(k)
			var s := " %s " % best
			for k in sim.wec_comps("HY"):
				s += "%s%+5.0f " % [k, float(cell[k]) - best_t] if k != best else ""
			line += "%-24s|" % s
		var pk: Array = plan.keys()
		pk.sort_custom(func(x, y): return float(plan[x][0]) < float(plan[y][0]))
		line += " %s×%d" % [pk[0], plan[pk[0]][1]]
		for i in range(1, pk.size()):
			line += " · %s×%d %+.0f" % [pk[i], plan[pk[i]][1], float(plan[pk[i]][0]) - float(plan[pk[0]][0])]
		print(line)
	# 끝 마모 (공칭)
	var wl := "끝 마모: "
	for k in sim.wec_comps("HY"):
		var r: float = sim.true_wear_rate(k) * float(sim.CIRC["wear"]) * RaceSimS.WEC_WEAR
		wl += "%s 1·2·3스틴트 %.0f·%.0f·%.0f%% (절벽 %.0f%%)  " % [k, r * 5 * 100, r * 10 * 100, r * 15 * 100, sim.cliff_at(k) * 100]
	print(wl)


func _races(key: String, laps: int, n: int) -> void:
	var lap_cnt := {}
	var main_pos := {}
	var main_n := {}
	var spset := {}
	var hy_n := 0
	var sets_out := 0
	var cliff_laps := 0
	var hy_laps := 0
	var t0 := Time.get_ticks_msec()
	var dbg := {}
	for s in n:
		var sim = RaceSimS.new()
		sim.new_race(key, -1, laps, "dry", ["M", "M"], 5000 + s * 37)
		sim.prepare_start()
		var per := {}
		var last_lap := {}
		var set_st := {}
		var guard := 0
		while not sim.done and guard < 400000:
			sim.advance(3.0)
			guard += 1
			for c in sim.cars:
				if c.cls != "HY" or c.dnf != "":
					continue
				if int(last_lap.get(c.id, 0)) != c.lap:
					last_lap[c.id] = c.lap
					if not per.has(c.id):
						per[c.id] = {}
					per[c.id][c.comp] = int(per[c.id].get(c.comp, 0)) + 1
					hy_laps += 1
					if sim.cliff_pen(c.comp, c.wear) > 0.0:
						cliff_laps += 1
		for tk in sim.tally:
			if String(tk).begins_with("DBG") or String(tk).begins_with("세트"):
				dbg[tk] = int(dbg.get(tk, 0)) + int(sim.tally[tk])
		for c in sim.cars:
			if c.cls != "HY":
				continue
			hy_n += 1
			if c.wec_sets <= 0:
				sets_out += 1
			var p: Dictionary = per.get(c.id, {})
			var mk := "-"
			var mv := -1
			for k in p:
				lap_cnt[k] = int(lap_cnt.get(k, 0)) + int(p[k])
				if int(p[k]) > mv:
					mv = int(p[k])
					mk = String(k)
			if c.dnf == "":
				main_pos[mk] = float(main_pos.get(mk, 0.0)) + sim.class_pos(c)
				main_n[mk] = int(main_n.get(mk, 0)) + 1
			# 세트당 스틴트 수: 타이어 바꾼 정차 사이 스틴트 수
			var st := 1
			for pl in c.pit_log:
				if bool(pl.get("tyres", true)):
					spset[st] = int(spset.get(st, 0)) + 1
					st = 1
				else:
					st += 1
	var tot := 0
	for k in lap_cnt:
		tot += int(lap_cnt[k])
	var share := ""
	for k in ["S", "M", "H"]:
		share += "%s %d%% · " % [k, int(round(100.0 * int(lap_cnt.get(k, 0)) / maxf(1.0, tot)))]
	var pos := ""
	for k in ["S", "M", "H"]:
		if main_n.has(k):
			pos += "%s 위주 %d대 평균 %.1f위 · " % [k, main_n[k], float(main_pos[k]) / main_n[k]]
	if OS.get_environment("TB_DBG") != "":
		var dk: Array = dbg.keys()
		dk.sort_custom(func(x, y): return int(dbg[x]) > int(dbg[y]))
		for k in dk.slice(0, 40):
			print("   %5d  %s" % [dbg[k], k])
	print("%s %d랩 × %d판 (%.0f초) | 랩 비율 %s| %s| 세트당 스틴트 %s | 절벽 랩 %.1f%% | 세트 바닥 %d/%d" % [key, laps, n, (Time.get_ticks_msec() - t0) / 1000.0, share, pos, spset, 100.0 * cliff_laps / maxf(1.0, hy_laps), sets_out, hy_n])
