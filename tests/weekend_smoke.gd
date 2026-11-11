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
			wk.auto_quali()
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
