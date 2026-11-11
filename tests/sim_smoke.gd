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
	print("총 %dms, 실패 %d" % [Time.get_ticks_msec() - t0, fails])
	quit(1 if fails > 0 else 0)
