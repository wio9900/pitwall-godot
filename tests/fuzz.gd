extends SceneTree
## 버그 찾기용 무작위 테스트: 커리어 하위 리그까지 여러 판을 '아무렇게나 조작하는 플레이어'로 돌리며
## 라이브 예선 무작위 출발·포기, 레이스 중 무작위 지시·피트, 중간 저장→이어하기를 섞고 규칙 위반을 찾는다.
## 실행: godot --headless --path . --script res://tests/fuzz.gd

const RaceSimS = preload("res://scripts/sim/race_sim.gd")
const WeekendS = preload("res://scripts/sim/weekend.gd")
const CareerS = preload("res://scripts/sim/career.gd")
const RaceSaveS = preload("res://scripts/sim/race_save.gd")
const RecS = preload("res://scripts/sim/records.gd")

var fails := 0
var rng := RandomNumberGenerator.new()
var stats := {}


func _bad(msg: String) -> void:
	fails += 1
	if fails <= 40:
		print("  ! " + msg)


func _stat(k: String, n: int = 1) -> void:
	stats[k] = int(stats.get(k, 0)) + n


func _pick(a: Array):
	return a[rng.randi_range(0, a.size() - 1)]


## 주말 타이어 수가 음수가 되지 않았나
func _check_sets(wk, tag: String) -> void:
	for slot in wk.sets.size():
		for k in ["S", "M", "H"]:
			if int(wk.sets[slot][k]) < 0 or int(wk.used_sets[slot][k]) < 0:
				_bad("%s 주말 타이어 음수 %s %s" % [tag, wk.sets[slot], wk.used_sets[slot]])


## 아무렇게나 하는 플레이어의 라이브 예선
func _live_quali(wk, tag: String) -> void:
	wk.start_quali()
	var guard := 0
	while not wk.done_quali and guard < 6000:
		guard += 1
		if wk.Q["stage_over"]:
			wk.next_stage()
			continue
		for slot in wk.my_cars().size():
			if rng.randf() < 0.04:
				var err: String = wk.player_depart(slot, _pick(["S", "M", "H"]), _pick(["safe", "std", "limit"]))
				_stat("예선 출발" if err == "" else "예선 출발 거절")
			if rng.randf() < 0.01:
				wk.player_abort(slot)
		wk.q_advance(rng.randf_range(0.05, 0.6))
	if not wk.done_quali:
		_bad("%s 예선이 끝나지 않음 (stage %d, t %.1f, run %d)" % [tag, int(wk.Q["stage"]), float(wk.Q["t"]), wk.Q["run"].size()])
	_stat("레드 플래그", 1 if wk.Q.get("red_done", false) else 0)
	_check_sets(wk, tag)
	# 그리드: 모든 차가 고유한 자리
	var seen := {}
	for c in wk.sim.cars:
		if seen.has(c.grid):
			_bad("%s 그리드 중복 P%d" % [tag, c.grid + 1])
		seen[c.grid] = true


## 아무렇게나 지시하는 레이스. 중간에 저장→불러와서 이어 달린다. 끝난 sim 을 돌려준다
func _race(sim, tag: String):
	var wec: bool = sim.is_wec()
	var save_lap: int = rng.randi_range(2, maxi(3, sim.laps - 2))
	var saved := false
	var guard := 0
	while not sim.done and guard < 400000:
		guard += 1
		sim.advance(rng.randf_range(0.5, 4.0))
		if not saved and sim.leader_lap >= save_lap:
			saved = true
			sim = RaceSaveS.unpack(RaceSaveS.pack(sim))
			_stat("중간 저장·복원")
		if sim.active_radio != null and rng.randf() < 0.3:
			sim.resolve_radio(rng.randi_range(0, 1))
		for c in sim.my_cars():
			if not c.is_running():
				continue
			var r := rng.randf()
			if r < 0.004:
				sim.set_pace(c, _pick(["attack", "standard", "save"]))
			elif r < 0.006:
				sim.set_instr(c, _pick(["free", "attack", "defend", "hold", "lift"]))
			elif r < 0.010:
				sim.set_fuel_mode(c, _pick(["lean", "std", "rich"]))
			elif r < 0.013 and c.boxing == null and c.pit_req == "":
				if wec:
					sim.request_pit_wec(c, _pick(["S", "M", "H", "W"]), rng.randf() < 0.7, rng.randf() < 0.9, rng.randf() < 0.7)
				else:
					sim.request_pit(c, _pick(["S", "M", "H", "I", "W"]))
				_stat("무작위 피트 요청")
			elif r < 0.014 and c.pit_req != "":
				sim.cancel_pit(c)
		if not wec and rng.randf() < 0.001:
			sim.set_team_order(_pick(["free", "hold"]))
	if not sim.done:
		_bad("%s 레이스가 끝나지 않음 (L%d/%d)" % [tag, sim.leader_lap, sim.laps])
	_check_sim(sim, tag)
	return sim


func _check_sim(sim, tag: String) -> void:
	var res: Array = sim.results()
	if res.size() != sim.cars.size():
		_bad("%s 결과 수 %d ≠ 차 수 %d" % [tag, res.size(), sim.cars.size()])
	var pos_seen := {}
	for r in res:
		var c = r["car"]
		var key: String = "%s%d" % [c.cls, int(r["pos"])]
		if pos_seen.has(key):
			_bad("%s 같은 클래스 순위 중복 %s" % [tag, key])
		pos_seen[key] = true
		if c.dnf == "" and (is_nan(c.finish_t) or c.finish_t <= 0.0 or c.finish_t == INF):
			_bad("%s %s 완주했는데 기록 이상 %s" % [tag, c.code, c.finish_t])
		if is_nan(c.fuel) or is_nan(c.wear) or c.wear < -0.001 or c.wear > 1.001:
			_bad("%s %s 연료/마모 이상 fuel %s wear %s" % [tag, c.code, c.fuel, c.wear])
		if sim.is_wec() and c.wec_sets < 0:
			_bad("%s %s WEC 세트 음수" % [tag, c.code])
		if c.time_pen < 0.0 or c.pits < 0:
			_bad("%s %s 페널티/피트 음수" % [tag, c.code])
	for c in sim.my_cars():
		_stat("내 차 리타이어", 1 if c.dnf != "" else 0)
		_stat("내 차 레이스", 1)


func _career(series: String, tier: int, seasons_rounds: int, seed_v: int) -> void:
	var tag := "%s T%d" % [series, tier]
	var cr = CareerS.new()
	cr.new_career("create", 0, {"tier": tier, "name": "Fuzz " + tag, "series": series}, seed_v)
	for r in seasons_rounds:
		var t0 := Time.get_ticks_msec()
		var sim = RaceSimS.new()
		sim.new_race(cr.next_circuit(), cr.race_my_index(), cr.race_laps(), "auto", ["M", "M"], seed_v + r, cr.race_opts())
		var wk = WeekendS.new()
		wk.setup(sim, cr.duty_laps())
		# 연습: 무작위 컴파운드로 무작위 런
		for i in 6:
			wk.practice_run(rng.randi_range(0, 1), _pick(["short", "long"]), _pick(["S", "M", "H"]))
		_check_sets(wk, tag + " 연습")
		_live_quali(wk, "%s R%d" % [tag, r + 1])
		for slot in wk.my_cars().size():
			wk.set_start_comp(slot, _pick(["S", "M", "H"]))
		wk.commit_start_tyres()
		_check_sets(wk, tag + " 출발")
		if cr.has_sprint():
			var sp = RaceSimS.new()
			sp.new_race(cr.next_circuit(), cr.race_my_index(), cr.race_laps(true), "auto", ["M", "M"], seed_v + 100 + r, cr.race_opts(true))
			var keys: Array = sim.grid_keys()
			var top: Array = keys.slice(0, 10)
			top.reverse()
			sp.apply_grid(top + keys.slice(10))
			sp.prepare_start()
			sp = _race(sp, "%s R%d 스프린트" % [tag, r + 1])
			cr.after_sprint(sp)
		sim.prepare_start()
		sim = _race(sim, "%s R%d %s" % [tag, r + 1, sim.circ_key])
		RecS.record_race(sim, "career")
		cr.after_race(sim)
		print("%-8s R%d %-14s %d랩 %dms · 내 차 %s" % [tag, r + 1, sim.circ_key, sim.laps, Time.get_ticks_msec() - t0, ", ".join(sim.my_cars().map(func(c): return "%s P%d%s" % [c.code, sim.class_pos(c), " DNF" if c.dnf != "" else ""]))])


func _init() -> void:
	rng.seed = 20261112
	var t0 := Time.get_ticks_msec()
	# 커리어: F1 3개 리그 + WEC 3개 리그 (LMGT3 · LMP2 · 하이퍼카), 리그마다 3라운드
	for series in ["f1", "wec"]:
		for tier in [1, 2, 3]:
			_career(series, tier, 3, 9000 + tier * 31 + (500 if series == "wec" else 0))
	# 퀵 레이스: 모든 서킷(F1 + WEC) 날씨 무작위 + 무작위 조작
	var DB = load("res://scripts/data/game_db.gd")
	DB.load_all()
	var keys: Array = DB.circuit_keys + DB.wec_keys
	for i in keys.size():
		var k: String = keys[i]
		var wec: bool = DB.wec_keys.has(k)
		var sim = RaceSimS.new()
		sim.new_race(k, 0 if wec else rng.randi_range(0, 9), 12 if wec else 10, _pick(["rain", "dry", "auto"]), [_pick(["S", "M", "H"]), _pick(["S", "M", "H"])], 700 + i, {"difficulty": rng.randi_range(0, 3)})
		sim.prepare_start()
		_race(sim, "퀵 " + k)
	CareerS.delete_save()
	print("무작위 통계: %s" % stats)
	print("버그 찾기 테스트 %dms · 실패 %d" % [Time.get_ticks_msec() - t0, fails])
	quit(1 if fails > 0 else 0)
