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


var events := {}


func _bot_round(cr) -> void:
	var ev: Variant = cr.hq.get("event")
	if ev != null:
		events[ev["kind"]] = int(events.get(ev["kind"], 0)) + 1
		cr.resolve_event(randi() % (ev["opts"] as Array).size())
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


const WeekendS2 = preload("res://scripts/sim/weekend.gd")
const RaceSimS2 = preload("res://scripts/sim/race_sim.gd")
func _init() -> void:
	for st in [[0, 4242], [1, 4242], [1, 77]]:
		var cr = CareerS.new()
		cr.new_career("create", 0, {"tier": st[0], "name": "T", "series": "wec"}, st[1])
		for s in 2:
			_bot_preseason(cr)
			for r in cr.cal_len():
				_bot_round(cr)
				if s == 1:
					var sim = RaceSimS2.new()
					sim.new_race(cr.next_circuit(), cr.race_my_index(), cr.race_laps(), "auto", ["M", "M"], 3, cr.race_opts())
					var wk = WeekendS2.new()
					wk.setup(sim, cr.duty_laps(), cr.eng_quality())
					wk.auto_practice()
					wk.start_quali()
					var g := 0
					while not wk.Q.get("stage_over", false) and not wk.done_quali and g < 5000:
						wk.q_advance(5.0)
						g += 1
					var n2 := 0
					for c in sim.cars:
						if wk._participant(c, 2):
							n2 += 1
					var cls := {}
					for c in sim.cars:
						cls[c.cls] = int(cls.get(c.cls, 0)) + 1
					print("start T", st[0], " S2 T", cr.tier(), " ", cr.next_circuit(), " special=", cr.hq.get("special", ""), " main=", wk.main_cls(), " cls=", cls, " st2=", n2, " mine=", wk.my_cars().size())
				_run_race(cr)
	quit()
