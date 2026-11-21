extends SceneTree
## 헤드리스 주말 테스트: 연습 → 예선 → 결승을 여러 서킷에서 돌린다.
## 실행: godot --headless --path . --script res://tests/weekend_smoke.gd

const RaceSimS = preload("res://scripts/sim/race_sim.gd")
const WeekendS = preload("res://scripts/sim/weekend.gd")
const BLogT = preload("res://scripts/sim/blog.gd")


func _init() -> void:
	var fails = 0
	for key in ["monza", "monaco", "suzuka"]:
		for n in 2:
			var sim = RaceSimS.new()
			sim.new_race(key, 6, 15, "dry", ["M", "M"], 500 + n)
			var wk = WeekendS.new()
			wk.setup(sim, 2)
			wk.set_wing(0, 2.0)
			var r0: Dictionary = wk.practice_run(0, "long")
			var r1: Dictionary = wk.practice_run(1, "short")
			wk.auto_practice()
			wk.start_quali()
			if n == 1:
				# 라이브 예선: 내 1번 차를 초반에 내보내고 5분 진행 → 기록이 생기는지, AI 도 스스로 나갔는지
				var err: String = wk.player_depart(0, "M", "std")
				wk.q_advance(5.0)
				var my_res: Variant = wk.Q["res"].get(wk.my_cars()[0].id)
				var ai_runs := 0
				for id in wk.Q["runs"]:
					ai_runs += int(wk.Q["runs"][id])
				print("   라이브 예선: 출발=%s · 5분 뒤 내 기록 %s · 트랙 위 %d대 · 지금까지 들어온 횟수 %d · 노면 %+.2f · 소식 %s" % ["OK" if err == "" else err, ("%.3f" % float(my_res["total"])) if my_res != null else "없음", wk.Q["run"].size(), ai_runs, float(wk.q_now()["evo"]), wk.Q["log"].slice(0, 2)])
				if err != "" or my_res == null:
					fails += 1
			wk.auto_quali()
			if not wk.done_quali:
				print("   ! 예선이 끝나지 않음")
				fails += 1
			sim.prepare_start()
			var guard = 0
			while not sim.done and guard < 200000:
				sim.advance(2.0)
				guard += 1
			var mine: Array = sim.my_cars()
			var pole = sim.cars[0]
			var res: Array = sim.results()
			var ok: bool = sim.done and wk.done_quali and r0.has("best") and r1.has("best")
			if not ok:
				fails += 1
			var mtxt = ""
			for c in mine:
				mtxt += "%s 그리드P%d→%s 세트%s pen%.2f / " % [c.code, c.grid + 1, "DNF" if c.dnf != "" else "완주", c.tyre_sets, c.used_set_pen]
			print("%-8s #%d | 완주=%s 폴=%s 우승=%s | 롱런 %.2f 오차±%d%% 연습남음%s | %s" % [key, n, ok, pole.code, res[0]["car"].code, r0.get("best", 0.0), int(wk.wear_est["err"] * 100), wk.practice_left, mtxt])
	# WEC 예선: Q1 뒤 내 클래스 상위 8대만 하이퍼폴 (작업목록 #9), 이상 감지 기록(⚠)이 없어야 함
	for key in ["spa", "lemans"]:
		var ws = RaceSimS.new()
		ws.new_race(key, 0, 20, "dry", ["M", "M"], 31)
		var wkw = WeekendS.new()
		wkw.setup(ws, 2)
		wkw.auto_practice()
		var warn0 := 0
		for l in BLogT.lines:
			if l.contains("⚠"):
				warn0 += 1
		wkw.start_quali()
		var gq := 0
		while not wkw.Q.get("stage_over", false) and not wkw.done_quali and gq < 5000:
			wkw.q_advance(5.0)
			gq += 1
		var n2 := 0
		for c in ws.cars:
			if wkw._participant(c, 2):
				n2 += 1
		var warn1 := 0
		for l in BLogT.lines:
			if l.contains("⚠"):
				warn1 += 1
		print("   WEC 예선 %s: 하이퍼폴 진출 %d대 · 이상 감지 %d건" % [key, n2, warn1 - warn0])
		if n2 != 8 or warn1 != warn0:
			fails += 1
	# 수정 15: 쓴 세트마다 마모 기록 → 예선 손해 · 결승 출발 마모
	var su = RaceSimS.new()
	su.new_race("bahrain", 6, 15, "dry", ["M", "M"], 77)
	var wu = WeekendS.new()
	wu.setup(su, 0)
	wu.practice_run(0, "long", "M")   # 새 M 세트 열고 5랩
	wu.practice_run(0, "short", "M")  # 같은 세트 3랩 더
	wu.practice_run(0, "short", "S")  # 새 S 세트 열고 3랩
	var m_set: Dictionary = wu.used_sets[0]["M"][0]
	var lw: float = su.set_lap_wear("M") # 공기압 마모 배율은 1 이상 (창 안이 가장 적게 닮)
	var one_run: float = wu.q_used_pen("S", su.set_lap_wear("S") * WeekendS.Q_RUN_LAPS)
	var more: float = wu.q_used_pen("S", float(wu.used_sets[0]["S"][0]["w"]))
	# 결승 출발: 새 M 이 없으면 가장 덜 쓴 M 세트의 마모에서 출발
	wu.sets[0]["M"] = 0
	var c0 = su.my_cars()[0]
	c0.comp = "M"
	wu.start_pref[0] = "used"
	wu.commit_start_tyres()
	# 공기압 psi (D①): 공짜 쪽 없음 · 더운 날은 최소에 걸림 · 예선용이 결승용보다 높거나 같음 · 드라이버 말은 방향이 맞음
	var fo: Array = RaceSimS.press_fx(1.0)
	var fl: Array = RaceSimS.press_fx(-1.0)
	var f0: Array = RaceSimS.press_fx(0.0)
	var psi_ok: bool = float(f0[0]) == 0.0 and float(fo[0]) > 0.0 and float(fl[0]) > 0.0 \
		and float(fo[6]) < 0.0 and float(fo[5]) > 1.0 and float(fo[4]) > 1.0 \
		and float(fl[6]) > 0.0 and float(fl[5]) < 1.0 and float(fl[3]) < 1.0
	psi_ok = psi_ok and su.psi_rec("q") >= su.psi_rec("race") and su.my_cars()[0].psi >= su.psi_min
	var keep_t: float = su.track_t
	su.track_t = float(su.CIRC["trackT"]) + 40.0
	psi_ok = psi_ok and su.psi_rec("race") == su.psi_min
	su.track_t = keep_t
	var cp = su.my_cars()[0]
	var keep_p: float = cp.psi
	cp.psi = su.psi_min + RaceSimS.PSI_SPAN
	var fb_hi: String = wu.feedback(cp, "race")
	cp.psi = keep_p
	psi_ok = psi_ok and fb_hi.contains("튀")
	print("   공기압: 최소 %.1f · 노면 %.0f°C · 추천 예선 %.1f / 결승 %.1f · 최고로 넣으면 \"%s\" %s" % [su.psi_min, su.track_t, su.psi_rec("q"), su.psi_rec("race"), fb_hi, "OK" if psi_ok else "실패"])
	if not psi_ok:
		fails += 1
	# 셋업 개편 (D②): 서킷마다 최적이 다름 · 결승 최적은 마모 쪽 · 공짜 방향 없음 · 취향은 실수만 · 낮은 등급 엔지니어는 틀릴 수 있음
	var so_ok := true
	var opt_by := {}
	for ck in ["monaco", "silverstone", "monza"]:
		var ss = RaceSimS.new()
		ss.new_race(ck, 6, 15, "dry", ["M", "M"], 5)
		var sc0 = ss.my_cars()[0]
		opt_by[ck] = ss.setup_opt(sc0)["susp"]
		var qo: Dictionary = ss.setup_opt(sc0)
		var ro: Dictionary = ss.setup_opt(sc0, true)
		so_ok = so_ok and float(ro["susp"]) < float(qo["susp"]) and float(ro["diff"]) < float(qo["diff"])
		for k in RaceSimS.SETUP_RANGE:
			sc0.set(k, RaceSimS.setup_v(k, 1.0))
			var chs: Array = ss.setup_channels(sc0, k)["ch"]
			so_ok = so_ok and float(chs[0][1]) < 0.0 and float(chs[1][1]) > 0.0
		var pr: Dictionary = ss.setup_pref(sc0)
		for k in pr:
			sc0.set(k, RaceSimS.setup_v(k, float(pr[k])))
		var e_near: float = ss.setup_extra(sc0, "q")["err"]
		for k in pr:
			sc0.set(k, RaceSimS.setup_v(k, -1.0 if float(pr[k]) > 0.0 else 1.0))
		sc0.bbias = RaceSimS.setup_v("bbias", float(pr["bbias"]))
		var e_far: float = ss.setup_extra(sc0, "q")["err"]
		so_ok = so_ok and e_far > e_near
	so_ok = so_ok and float(opt_by["monaco"]) < float(opt_by["silverstone"])
	var wrong := {"S": 0, "D": 0}
	for g in [["S", 0.95], ["D", 0.05]]:
		for sd in 40:
			var se = RaceSimS.new()
			se.new_race("bahrain", 6, 15, "dry", ["M", "M"], 900 + sd)
			var we = WeekendS.new()
			we.setup(se, 0, float(g[1]))
			for k in ["susp", "bbias", "diff"]:
				if we.bands[0][k].get("wrong", false):
					wrong[g[0]] += 1
	so_ok = so_ok and int(wrong["S"]) == 0 and int(wrong["D"]) > 20 and int(wrong["D"]) < 80
	print("   셋업 타협: 서스펜션 최적 모나코 %.1f < 실버스톤 %.1f · 몬자 %.1f · 틀린 추천 S급 %d / D급 %d (120칸 중) %s" % [float(opt_by["monaco"]), float(opt_by["silverstone"]), float(opt_by["monza"]), int(wrong["S"]), int(wrong["D"]), "OK" if so_ok else "실패"])
	if not so_ok:
		fails += 1
	var ok15: bool = wu.used_n(0, "M") == 1 and int(m_set["h"]) == 3 and absf(float(c0.wear) - float(m_set["w"])) < 0.001 \
		and float(m_set["w"]) > lw * 7.0 and absf(one_run - 0.45) < 0.01 and more > one_run and absf(c0.used_set_pen - RaceSimS.HEAT_PEN * 2.0) < 0.001
	print("   쓴 세트 마모: M 세트 %.0f%% (달군 %d) → 출발 마모 %.0f%% · 열 사이클 +%.2f초/랩 · 예선 손해 런1 %.2f / 숏런 세트 %.2f %s" % [float(m_set["w"]) * 100.0, int(m_set["h"]), c0.wear * 100.0, c0.used_set_pen, one_run, more, "OK" if ok15 else "실패"])
	if not ok15:
		fails += 1
	print("주말 테스트 실패 %d" % fails)
	quit(1 if fails > 0 else 0)
