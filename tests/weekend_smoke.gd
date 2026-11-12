extends SceneTree
## 헤드리스 주말 테스트: 연습 → 예선 → 결승을 여러 서킷에서 돌린다.
## 실행: godot --headless --path . --script res://tests/weekend_smoke.gd

const RaceSimS = preload("res://scripts/sim/race_sim.gd")
const WeekendS = preload("res://scripts/sim/weekend.gd")


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
	print("주말 테스트 실패 %d" % fails)
	quit(1 if fails > 0 else 0)
