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
				if c.penalty > 0 and c.dnf == "" and not sim.ever_wet:
					print("  ! 자동 전략인데 두 컴파운드 페널티")
					fails += 1
			if not sim.done:
				fails += 1
			print("자동전략 %-11s 난이도%d | 계획 %s | %s" % [key, n * 2, plan0, txt])
	print("총 %dms, 실패 %d" % [Time.get_ticks_msec() - t0, fails])
	quit(1 if fails > 0 else 0)
