extends SceneTree
## 헤드리스 커리어 테스트: 간단한 봇이 여러 시즌을 운영한다 (경제·개발·스폰서·승강·저장 확인).
## 실행: godot --headless --path . --script res://tests/career_smoke.gd

const RaceSimS = preload("res://scripts/sim/race_sim.gd")
const WeekendS = preload("res://scripts/sim/weekend.gd")
const CareerS = preload("res://scripts/sim/career.gd")

var team_pts_by_rank := {}
var sprint_pts := 0
var sprint_stops := 0
var sprint_n := 0
var f3_stops := 0
var f3_n := 0


func _bot_preseason(cr) -> void:
	# 스폰서: 카테고리마다 안정형 우선
	for cat in ["title", "tech", "global", "premium"]:
		if cr.contract_of(cat) != null:
			continue
		for i in cr.hq["offers"].size():
			var o: Dictionary = cr.hq["offers"][i]
			if o["cat"] == cat and o["kind"] == "stable":
				cr.sign_offer(i)
				break
	for i in cr.hq["eng_pool"].size():
		if cr.can_hire_engineer(i) and float(cr.hq["cash"]) > float(cr.hq["eng_pool"][i]["cost"]) + 6.0:
			cr.hire_engineer(i)
	if cr.can_tier_up():
		cr.tier_up()
	# WEC: FA 시장에서 한 명 영입 시도 + 라인업 조정
	if cr.is_wec():
		var mk: Array = cr.wec_market()
		var done := false
		for i in mk.size():
			for idx in 3:
				if not done and cr.wec_hire_block(i, 1, idx) == "" and float(cr.hq["cash"]) > float(mk[i]["cost"]) + 4.0:
					var nm: String = mk[i]["name"]
					if cr.hire_wec(i, 1, idx):
						print("  WEC FA 영입: %s → #2 차 %d번" % [nm, idx + 1])
						done = true
		cr.wec_swap_cars(0)
		cr.wec_swap_cars(0)
		cr.wec_set_starter(0, 1)
		cr.wec_set_starter(0, 1)


func _bot_round(cr) -> void:
	var cash: float = cr.hq["cash"]
	for k in ["wind", "rig", "bench", "factory", "sim", "pit"]:
		if cash > 7.0 and cr.projected_spend() + cr.fac_cost(k) / 4.0 < float(cr.hq["cost_cap_limit"]) - 1.0:
			if cr.build_facility(k):
				cash = cr.hq["cash"]
	for k in ["aero", "chassis", "engine", "rel"]:
		for sz in ["l", "s"]:
			if cr.can_start_project(k, sz) and cash > cr.dev_cost(sz) + 2.5 and cr.projected_spend() + cr.dev_cost(sz) < float(cr.hq["cost_cap_limit"]) - 0.3:
				cr.start_project(k, sz)
				cash = cr.hq["cash"]
	cr.set_mission("double_p8" if cr.pre_rank() <= 6 else "both_finish")


func _run_race(cr) -> Dictionary:
	var sim = RaceSimS.new()
	var opts: Dictionary = cr.race_opts()
	sim.new_race(cr.next_circuit(), cr.race_my_index(), cr.race_laps(), "auto", ["M", "M"], 0, opts)
	var wk = WeekendS.new()
	wk.setup(sim, cr.duty_laps())
	wk.auto_practice()
	wk.start_quali()
	wk.auto_quali()
	if cr.has_sprint():
		var sp = RaceSimS.new()
		sp.new_race(cr.next_circuit(), cr.race_my_index(), cr.race_laps(true), "auto", ["M", "M"], 0, cr.race_opts(true))
		var keys: Array = sim.grid_keys()
		var top: Array = keys.slice(0, 10)
		top.reverse()
		sp.apply_grid(top + keys.slice(10))
		sp.prepare_start()
		_drive(sp)
		var spr: Dictionary = cr.after_sprint(sp)
		sprint_pts += int(spr["total"])
		sprint_stops += _total_stops(sp)
		sprint_n += 1
	sim.prepare_start()
	_drive(sim)
	if cr.race_format() == "f3":
		f3_stops += _total_stops(sim)
		f3_n += 1
	return cr.after_race(sim)


func _total_stops(sim) -> int:
	var n := 0
	for c in sim.cars:
		n += c.pits
	return n


func _drive(sim) -> void:
	var guard = 0
	while not sim.done and guard < 300000:
		sim.advance(2.0)
		guard += 1
		for c in sim.my_cars():
			if sim.is_wec():
				if c.is_running() and c.boxing == null and c.pit_req == "" and sim.fuel_laps(c) < 1.6 and c.lap < sim.laps - 1:
					sim.request_pit_wec(c, "M" if sim.wet < 0.27 else "W", c.wear > 0.4, true, c.stint_drv >= 1)
			elif c.is_running() and c.boxing == null and c.pit_req == "" and sim.wet < 0.2 and c.wear > 0.58 and c.lap < sim.laps - 2:
				sim.request_pit(c, "H" if c.comp != "H" else "M")


func _init() -> void:
	var fails = 0
	var scenarios = [["select", 6, {}, "Williams"], ["create", 0, {"tier": 1, "name": "Test GP"}, "신규 F3"], ["create", 0, {"tier": 2, "name": "Test F2"}, "신규 F2"], ["select", 3, {"series": "wec"}, "WEC Peugeot"], ["create", 0, {"tier": 1, "name": "Test WEC", "series": "wec"}, "WEC 신규 LMGT3"]]
	for sc in scenarios:
		var cr = CareerS.new()
		cr.new_career(sc[0], sc[1], sc[2], 4242)
		var seasons = 4 if sc[2].get("series", "f1") == "f1" else 3
		if sc[3] == "신규 F2":
			seasons = 1
		var t0 = Time.get_ticks_msec()
		for s in seasons:
			_bot_preseason(cr)
			for r in cr.cal_len():
				_bot_round(cr)
				var ec: Dictionary = _run_race(cr)
				if r == cr.cal_len() - 1:
					pass
			var lg: Dictionary = cr.hq["season_log"][-1]
			var ld: Dictionary = cr.hq["last_ledger"]
			print("%s S%d T%d: P%d · 자금 %.1fM · 캡 %.1f/%.1f · 평판 %d%% · 스폰서 %.1f 페이 %.1f 상금 %.1f 미션 %.1f / 운영 %.1f 연봉 %.1f 수리 %.1f R&D %.1f 설비 %.1f 인력 %.1f · 계약 %d · dev %s · 설비 %s" % [
				sc[3], int(lg["season"]), int(lg["tier"]), int(lg["rank"]), float(lg["cash"]), float(lg["spent"]), float(lg["cap"]), int(cr.hq["pop"] * 100),
				ld["spon"], ld["pay"], ld["prize"], ld["mission"], ld["ops"], ld["salary"], ld["repair"], ld["rnd"], ld["fac"], ld["staff"], cr.hq["contracts"].size(), cr.hq["dev"], cr.hq["base"]])
		print("  %d시즌 %dms · 뉴스: %s" % [seasons, Time.get_ticks_msec() - t0, cr.hq["news"].slice(0, 3)])
		# 저장·불러오기
		var cr2 = CareerS.new()
		if not cr2.load_save() or int(cr2.hq["race_count"]) != int(cr.hq["race_count"]):
			print("저장/불러오기 실패")
			fails += 1
		if float(cr.hq["cash"]) != float(cr.hq["cash"]):
			fails += 1
	CareerS.delete_save()
	print("F2 스프린트 %d회: 내 팀 %d점, 전체 피트 %.1f회/경기 · F3 %d경기: 전체 피트 %.1f회/경기" % [sprint_n, sprint_pts, sprint_stops / maxf(1.0, sprint_n), f3_n, f3_stops / maxf(1.0, f3_n)])
	print("커리어 테스트 실패 %d" % fails)
	quit(1 if fails > 0 else 0)
