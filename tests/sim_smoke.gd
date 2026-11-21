extends SceneTree
## 헤드리스 시뮬레이션 테스트 (화면 없이 레이스를 여러 판 돌려 완주·전략 분포를 확인)
## 실행: godot --headless --path . --script res://tests/sim_smoke.gd

const RaceSimS = preload("res://scripts/sim/race_sim.gd")
const RaceSaveS = preload("res://scripts/sim/race_save.gd")


func _init() -> void:
	var t0 = Time.get_ticks_msec()
	var fails = 0
	for key in ["monza", "bahrain", "monaco", "silverstone", "singapore"]:
		for n in 3:
			var sim = RaceSimS.new()
			var t_plan = Time.get_ticks_msec()
			sim.new_race(key, -1, 15, "rain" if n == 2 else "dry", ["M", "M"], 1000 + n)
			var plan_ms = Time.get_ticks_msec() - t_plan
			var guard = 0
			while not sim.done and guard < 200000:
				sim.advance(2.0)
				guard += 1
			var stops = {}
			var dnf = 0
			var starts = {}
			for c in sim.cars:
				stops[c.pits] = stops.get(c.pits, 0) + 1
				starts[c.plan["start"]] = starts.get(c.plan["start"], 0) + 1
				if c.dnf != "":
					dnf += 1
			var res: Array = sim.results()
			var winner = res[0]["car"]
			var ok: bool = sim.done
			if not ok:
				fails += 1
			print("%-12s #%d %s | 완주=%s 우승=%s(%s) | 스톱=%s 출발=%s DNF=%d | 계획 %dms" % [key, n, "비" if n == 2 else "맑음", ok, winner.code, winner.team, stops, starts, dnf, plan_ms])
			print("    AI 전술·실수: %s" % sim.tally)
	# 공짜 모드 없음: 표준·자유 외 페이스·지시는 장점과 대가가 둘 다 표시돼야 (F1·WEC)
	for wk in [["monza", false], ["lemans", true]]:
		var fs = RaceSimS.new()
		fs.new_race(wk[0], 0, 12, "dry", ["M", "M"], 77)
		if fs.is_wec() != wk[1]:
			print("  ! %s 시리즈 판정 이상" % wk[0])
			fails += 1
		var fc = fs.my_cars()[0]
		for kk in [["pace", "attack"], ["pace", "save"], ["instr", "attack"], ["instr", "defend"], ["instr", "hold"], ["instr", "lift"]]:
			var fx: Dictionary = fs.mode_effects(fc, kk[0], kk[1])
			if fx["pros"].is_empty() or fx["cons"].is_empty():
				print("  ! %s %s %s: 장점 또는 대가 표시 없음 %s" % [wk[0], kk[0], kk[1], fx])
				fails += 1
	# 전략 뷰: 스틴트가 0랩부터 끊김 없이 이어지고, 예상 피트는 앞으로의 랩, 언더컷은 기회·위협 둘 다 계산
	var sv = RaceSimS.new()
	sv.new_race("monza", 0, 20, "dry", ["M", "M"], 515)
	sv.prepare_start()
	var sg := 0
	while sv.leader_lap < 12 and not sv.done and sg < 100000:
		sv.advance(1.0)
		sg += 1
	var sv_bad := 0
	var cuts := 0
	var sv_ord: Array = sv.order()
	for j in sv_ord.size():
		var o = sv_ord[j]
		var sl: Array = sv.stints(o)
		if int(sl[0][1]) != 0 or int(sl[-1][2]) < o.lap:
			sv_bad += 1
		for q in range(1, sl.size()):
			if int(sl[q][1]) != int(sl[q - 1][2]):
				sv_bad += 1
		var ep: Variant = sv.est_next_pit(o)
		if ep != null and (int(ep[0]) <= o.lap or int(ep[1]) < int(ep[0])):
			sv_bad += 1
		if j > 0 and sv.undercut_net(o, sv_ord[j - 1]) != null:
			cuts += 1
	print("  전략 뷰: 이상 %d · 언더컷 계산된 쌍 %d" % [sv_bad, cuts])
	if sv_bad > 0 or cuts == 0:
		fails += 1
	# 자동 전략: 내 차 두 대를 자동(A·B)에 맡겨 완주 + 컴파운드 규정 위반 없는지
	for key in ["monza", "silverstone", "singapore", "interlagos"]:
		for n in 2:
			var sim = RaceSimS.new()
			sim.new_race(key, 6, 15, "auto", ["M", "M"], 3000 + n, {"difficulty": n * 2})
			sim.prepare_start()
			var mc: Array = sim.my_cars()
			sim.set_plan(mc[1], "B")
			for c in mc:
				sim.set_auto(c, true)
			var plan0 := "%s / %s" % [sim.plan_text(mc[0], "A"), sim.plan_text(mc[1], "B")]
			var guard = 0
			while not sim.done and guard < 200000:
				sim.advance(2.0)
				guard += 1
			var txt := ""
			for c in mc:
				var pos: int = sim.order().find(c) + 1
				txt += "%s P%d 피트%d 페널티%d  " % [c.code, pos, c.pits, int(c.penalty)]
				if c.used_slicks() < 2 and c.dnf == "" and not sim.ever_wet:
					print("  ! 자동 전략인데 두 컴파운드 페널티")
					fails += 1
			if not sim.done:
				fails += 1
			print("자동전략 %-11s 난이도%d | 계획 %s | %s" % [key, n * 2, plan0, txt])
	# 직접 짠 계획 + 세부 셋업: 계획대로 피트하는지
	for key in ["monza", "bahrain"]:
		var sim = RaceSimS.new()
		sim.new_race(key, 6, 15, "dry", ["M", "M"], 4100)
		var mc: Array = sim.my_cars()
		mc[0].susp = 2.0
		mc[0].diff = 75.0
		mc[1].bbias = 53.0
		var ev: Dictionary = sim.eval_plan(mc[0], [{"lap": 5, "comp": "H"}, {"lap": 10, "comp": "S"}])
		sim.set_custom_plans(mc[0], {"A": [{"lap": 5, "comp": "H"}, {"lap": 10, "comp": "S"}], "B": [{"lap": 8, "comp": "H"}]})
		sim.set_custom_plans(mc[1], {"A": [{"lap": 8, "comp": "H"}], "B": []})
		sim.prepare_start()
		for c in mc:
			sim.set_auto(c, true)
		var guard = 0
		while not sim.done and guard < 200000:
			sim.advance(2.0)
			guard += 1
		var x0: Dictionary = sim.setup_extra(mc[0])
		print("직접 계획 %s | 평가 손실 %.1f초 경고 %s | #1 피트%d(계획 2) #2 피트%d(계획 1) | 세부셋업 dt %.3f 마모×%.2f · tip '%s'" % [key, float(ev["cost"]), ev["warn"], mc[0].pits, mc[1].pits, float(x0["dt"]), float(x0["wear"]), sim.setup_tip(mc[1])])
		if not sim.ever_wet and (mc[0].dnf == "" and mc[0].pits != 2 or mc[1].dnf == "" and mc[1].pits != 1):
			print("  ! 직접 계획대로 피트하지 않음")
			fails += 1
	# 레이스 중간 저장 → 불러오기: 이어 달린 결과가 저장 안 한 쪽과 똑같아야 한다 (F1 · WEC)
	for key in ["silverstone", "lemans"]:
		var a = RaceSimS.new()
		a.new_race(key, 0, 12, "rain", ["M", "M"], 5150)
		a.prepare_start()
		var g1 = 0
		while a.leader_lap < 5 and g1 < 200000:
			a.advance(2.0)
			g1 += 1
		var b = RaceSaveS.unpack(RaceSaveS.pack(a))
		for sm in [a, b]:
			var g2 = 0
			while not sm.done and g2 < 400000:
				sm.advance(2.0)
				g2 += 1
		var ra: PackedStringArray = []
		var rb: PackedStringArray = []
		for r in a.results():
			ra.append("%s:%.3f" % [r["car"].code, r["car"].finish_t])
		for r in b.results():
			rb.append("%s:%.3f" % [r["car"].code, r["car"].finish_t])
		var same: bool = ra == rb
		print("저장·이어하기 %s: %s (L5에서 저장, 우승 %s)" % [key, "같음" if same else "다름!", ra[0]])
		if not same or not b.done:
			fails += 1
	# 고장·반쯤 고장·더티 에어·트랙 포지션 (2026-11-21)
	var fx = RaceSimS.new()
	fx.new_race("monaco", 0, 20, "dry", ["M", "M"], 515)
	fx.prepare_start()
	while fx.leader_lap < 3:
		fx.advance(1.0)
	var ai_f = null
	for o in fx.cars:
		if not o.mine and o.is_running() and fx.next_stop(o) != null:
			ai_f = o
			break
	ai_f.fault = null
	fx._start_fault(ai_f)
	ai_f.fault["dt"] = 1.1
	ai_f.fault["fix"] = 12.0
	fx._fault_decide(ai_f)
	var dt_f: float = float(ai_f.fault["dt"])
	var rep_f: bool = bool(ai_f.fault["repair"])
	var pits0: int = ai_f.pits
	var gf := 0
	while ai_f.is_running() and ai_f.pits == pits0 and gf < 20000:
		fx.advance(0.5)
		gf += 1
	var fault_ok: bool = dt_f >= 0.35 and dt_f <= 1.2 and rep_f and (not ai_f.is_running() or ai_f.fault == null)
	var mz = RaceSimS.new()
	mz.new_race("monza", 0, 20, "dry", ["M", "M"], 1)
	var tp_ok: bool = fx.stop_cost() - fx.pit_loss() > mz.stop_cost() - mz.pit_loss() + 6.0
	print("   반쯤 고장: 랩당 +%.2f초 수리=%s → 피트 후 %s · 트랙 포지션 값 모나코 %.1f > 몬자 %.1f %s" % [dt_f, rep_f, "해제" if ai_f.fault == null else "남음", fx.stop_cost(), mz.stop_cost(), "OK" if fault_ok and tp_ok else "실패"])
	if not (fault_ok and tp_ok):
		fails += 1
	print("총 %dms, 실패 %d" % [Time.get_ticks_msec() - t0, fails])
	quit(1 if fails > 0 else 0)
