extends SceneTree
## 헤드리스 시뮬레이션 테스트 (화면 없이 레이스를 여러 판 돌려 완주·전략 분포를 확인)
## 실행: godot --headless --path . --script res://tests/sim_smoke.gd

const RaceSimS = preload("res://scripts/sim/race_sim.gd")


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
	print("총 %dms, 실패 %d" % [Time.get_ticks_msec() - t0, fails])
	quit(1 if fails > 0 else 0)
