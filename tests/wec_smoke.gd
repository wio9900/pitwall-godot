extends SceneTree
## 헤드리스 WEC 테스트: 멀티클래스 레이스를 서킷마다 돌려 완주·피트·교대·클래스별 우승을 확인한다.
## 실행: godot --headless --path . --script res://tests/wec_smoke.gd

const RaceSimS = preload("res://scripts/sim/race_sim.gd")
const DB = preload("res://scripts/data/game_db.gd")


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
	print("WEC 테스트 %dms 실패 %d" % [Time.get_ticks_msec() - t0, fails])
	quit(1 if fails > 0 else 0)
