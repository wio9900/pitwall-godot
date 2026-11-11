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
		while not sim.done and guard < 400000:
			sim.advance(3.0)
			guard += 1
			for c in sim.my_cars():
				if c.is_running() and c.boxing == null and c.pit_req == "" and sim.fuel_laps(c) < 1.6 and c.lap < sim.laps - 1:
					sim.request_pit_wec(c, "M", c.wear > 0.4, true, c.stint_drv >= 1)
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
	print("WEC 테스트 %dms 실패 %d" % [Time.get_ticks_msec() - t0, fails])
	quit(1 if fails > 0 else 0)
