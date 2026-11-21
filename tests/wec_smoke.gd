extends SceneTree
## 헤드리스 WEC 테스트: 멀티클래스 레이스를 서킷마다 돌려 완주·피트·교대·클래스별 우승을 확인한다.
## 실행: godot --headless --path . --script res://tests/wec_smoke.gd

const RaceSimS = preload("res://scripts/sim/race_sim.gd")
const DB = preload("res://scripts/data/game_db.gd")
const CareerS = preload("res://scripts/sim/career.gd")


func _init() -> void:
	DB.load_all()
	var fails = 0
	var t0 = Time.get_ticks_msec()
	for key in DB.wec_keys:
		var circ: Dictionary = DB.circuits[key]
		var laps: int = int(circ["lapsOpt"]["short"])
		var sim = RaceSimS.new()
		sim.new_race(key, 0, laps, "auto", ["M", "M"], 300 + key.length())
		sim.prepare_start()
		var guard = 0
		var t_sim := 0
		while not sim.done and guard < 400000:
			var u0 := Time.get_ticks_usec()
			sim.advance(3.0)
			t_sim += Time.get_ticks_usec() - u0
			guard += 1
			for c in sim.my_cars():
				if c.is_running() and c.boxing == null and c.pit_req == "" and sim.fuel_laps(c) < 1.6 and c.lap < sim.laps - 1:
					sim.request_pit_wec(c, "M", c.wear > 0.4, true, c.stint_drv >= 1 or sim.must_swap(c))
		var res: Array = sim.results()
		var win := {}
		var stops := {}
		var dnf := 0
		var swaps := 0
		for r in res:
			var c = r["car"]
			if r["pos"] == 1 and not win.has(c.cls):
				win[c.cls] = c.label
			if c.cls == "HY":
				stops[c.pits] = stops.get(c.pits, 0) + 1
			if c.dnf != "":
				dnf += 1
			if c.drv != 0:
				swaps += 1
		var mine = ""
		for c in sim.my_cars():
			mine += "#%d P%d(%s) 스톱%d 교대 %s / " % [c.slot + 1, sim.class_pos(c), "DNF" if c.dnf != "" else "완주", c.pits, c.name]
		var ok: bool = sim.done
		if not ok:
			fails += 1
		print("%-14s %d랩 완주=%s | HY %s · GT %s | HY 스톱 %s DNF %d 교대중 %d | 내 팀 %s" % [key, laps, ok, win.get("HY", "-"), win.get("GT", "-"), stops, dnf, swaps, mine])
		# 2026 타이어 규정 · 주행 시간 규정 확인
		var comps := {}
		var gt_bad := 0
		var sets_neg := 0
		for c in sim.cars:
			for k in sim.tyre_seq(c):
				comps[k] = int(comps.get(k, 0)) + 1
				if c.cls != "HY" and RaceSimS.SLICK.has(k) and k != "M":
					gt_bad += 1
				if c.cls == "HY" and RaceSimS.SLICK.has(k) and not sim.wec_comps("HY").has(k):
					gt_bad += 1
			if c.wec_sets < 0:
				sets_neg += 1
		var ai_viol: int = int(sim.tally.get("drive_viol", 0))
		print("   타이어 %s · 규정 밖 컴파운드 %d · 세트 초과 %d · 주행시간 위반 %d · 트래픽 접촉 %d · 시뮬 %.2fms/스텝(3초)" % [comps, gt_bad, sets_neg, ai_viol, int(sim.tally.get("traffic_contact", 0)), float(t_sim) / 1000.0 / maxf(1.0, guard)])
		if ai_viol > 0:
			var shown := 0
			for c in sim.cars:
				if c.time_pen >= 60.0 and shown < 3:
					shown += 1
					print("     위반 의심 %s%s cls=%s 드라이버%d명 로그 %s 피트 %s" % [c.label, " (내 차)" if c.mine else "", c.cls, c.drivers.size(), c.drv_log, c.pit_log.map(func(e): return int(e["lap"]))])
		if gt_bad > 0 or sets_neg > 0 or ai_viol > 2:
			fails += 1
	# 르망 60랩: AI 가 드라이버별 최소 주행(각자 6시간 분량)을 지키는가
	var lm = RaceSimS.new()
	lm.new_race("lemans", 0, 60, "dry", ["M", "M"], 3131)
	lm.prepare_start()
	# 부분 급유는 가득보다 정차가 짧아야 (무전·복기 "가득보다 −N초"의 근거)
	var lc = lm.my_cars()[0]
	var fuel0: float = lc.fuel
	lc.fuel = lm.TANK * 0.1
	var fsave: float = lm.wec_stop_time(lc, true, false, true, 1.0) - lm.wec_stop_time(lc, true, false, true, 0.4)
	lc.fuel = fuel0
	print("   부분 급유(탱크 30%%분) 정차 절약 %.1f초" % fsave)
	if fsave <= 0.0:
		fails += 1
	var gl := 0
	while not lm.done and gl < 200000:
		lm.advance(20.0)
		gl += 1
	var lm_fail := 0
	var lm_ai := 0
	for c in lm.cars:
		if c.mine:
			continue
		lm_ai += 1
		for pe in c.pen_log:
			if String(pe["why"]).find("최소 주행") >= 0:
				lm_fail += 1
	print("   르망 60랩 AI 최소 주행 위반 %d / %d" % [lm_fail, lm_ai])
	if lm_fail * 20 > lm_ai:
		fails += 1
	# 하위 리그 최소 주행(브론즈·실버) 규정: AI 가 짧은 커리어 레이스에서도 지키는가
	for tier in [0, 1, 2]:
		var cr = CareerS.new()
		cr.new_career("create", 0, {"tier": tier, "name": "MD", "series": "wec"}, 4400 + tier)
		var fail_n := 0
		var ai_n := 0
		for r in 3:
			var sim2 = RaceSimS.new()
			sim2.new_race(cr.calendar()[r], cr.race_my_index(), cr.race_laps(), "auto", ["M", "M"], 77 + r * 13 + tier, cr.race_opts())
			sim2.prepare_start()
			var g2 := 0
			while not sim2.done and g2 < 400000:
				sim2.advance(3.0)
				g2 += 1
				for c in sim2.my_cars():
					if c.is_running() and c.boxing == null and c.pit_req == "" and sim2.fuel_laps(c) < 1.6 and c.lap < sim2.laps - 1:
						sim2.request_pit_wec(c, "M", c.wear > 0.4, true, true)
			for c in sim2.cars:
				if not c.mine and c.dnf == "":
					ai_n += 1
					if c.min_drive_fail:
						fail_n += 1
		print("   하위 리그 T%d 최소 주행 위반 AI %d / %d" % [tier, fail_n, ai_n])
		CareerS.delete_save()
		if fail_n * 10 > ai_n:
			fails += 1
	# 수정 13: 손상 → 피트까지 절뚝이며(랩타임 +15~40%), 피트에서 감속 해제
	var dm = RaceSimS.new()
	dm.new_race("lemans", 0, 54, "dry", ["M", "M"], 4242)
	dm.prepare_start()
	while dm.leader_lap < 4:
		dm.advance(1.0)
	var hurt = null
	for o in dm.cars:
		if o.is_running() and o.boxing == null and o.pit_phase == 0 and not o.mine:
			var tries := 0
			while o.garage <= 0.0 and o.dnf == "" and tries < 20:
				dm.damage(o, "테스트 접촉")
				tries += 1
			if o.garage > 0.0:
				hurt = o
				break
	var limp0: float = hurt.limp if hurt != null else 0.0
	var lap0: int = hurt.lap if hurt != null else 0
	var guard2 := 0
	while hurt != null and hurt.limp > 0.0 and not dm.done and guard2 < 5000:
		dm.advance(0.5)
		guard2 += 1
	var limp_ok: bool = hurt != null and limp0 >= 0.15 and limp0 <= 0.40 and hurt.limp == 0.0 and hurt.pits >= 1 and hurt.lap <= lap0 + 1
	print("   손상 절뚝이기: 감속 +%d%% → 피트 후 %.2f (피트 %d) %s" % [int(limp0 * 100.0), hurt.limp if hurt != null else -1.0, hurt.pits if hurt != null else -1, "OK" if limp_ok else "실패"])
	if not limp_ok:
		fails += 1
	# 수정 24: 하이퍼카 컴파운드 온도 창 — 르망 낮 35°C 는 미디엄, 밤(약 21°C)은 소프트, 하드는 밤에 차가움
	var tw = RaceSimS.new()
	tw.new_race("lemans", 0, 54, "dry", ["M", "M"], 4343)
	tw.track_t = 35.0
	var hy = null
	for o in tw.cars:
		if o.cls == "HY" and not o.mine:
			hy = o
			break
	hy.pace = "standard"
	hy.wec_style = "std"
	var t_day: float = tw.track_temp_at(0.1)
	var t_night: float = tw.track_temp_at(0.4)
	tw.leader_lap = 0
	var pick_day: String = tw.wec_pick_comp(hy, 10, false)
	tw.leader_lap = int(tw.laps * 0.35)
	var pick_night: String = tw.wec_pick_comp(hy, 10, false)
	var win_ok: bool = t_night < t_day - 10.0 and tw.win_off("HY", "S", 35.0) > 0.0 and tw.win_off("HY", "H", t_night) < 0.0 and tw.win_off("HY", "M", 25.0) == 0.0 and tw.win_off("GT", "M", 50.0) == 0.0
	print("   온도 창: 낮 %.0f°C → %s · 밤 %.0f°C → %s %s" % [t_day, pick_day, t_night, pick_night, "OK" if (win_ok and pick_day == "M" and pick_night == "S") else "실패"])
	if not (win_ok and pick_day == "M" and pick_night == "S"):
		fails += 1
	print("WEC 테스트 %dms 실패 %d" % [Time.get_ticks_msec() - t0, fails])
	quit(1 if fails > 0 else 0)
