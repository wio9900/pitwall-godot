extends RefCounted
## 레이스 주말: 셋업 → 연습 주행 → 예선(Q1·Q2·Q3) → 결승 그리드.
## 원본 HTML(v16.1) practiceLaps / qLap / runAiQualiForStage / qOrder / finishQuali 를 옮겼다.
## 레이스 시뮬레이션(race_sim)을 먼저 만든 뒤 그 차들을 가지고 연습·예선을 돌린다. 화면과 무관.

const RS = preload("res://scripts/sim/race_sim.gd")
const NS := 6
const STINT := 5
const QPUSH := {"safe": [0.85, 0.5, 0.0], "std": [1.0, 1.0, 0.012], "limit": [1.15, 2.0, 0.07]}
const QPUSH_KO := {"safe": "안전하게", "std": "표준", "limit": "한계까지"}
const QTRAFFIC := {"early": [0.05, 0.12, "즉시 출주"], "clean": [-0.12, 0.04, "클린 에어 대기"], "late": [-0.28, 0.28, "막판 릴리즈"]}
const PRESS_KO := {"low": "낮게", "std": "표준", "high": "높게"}
const FUEL_LOAD_KO := {"light": "가볍게", "std": "표준", "heavy": "넉넉하게"}
const PRACTICE_LAPS := 16

var sim                      # race_sim.gd
var sets: Array = []         # 내 차별 주말 타이어 세트 [{S, M, H}, {…}] (예선·레이스 공유)
var setups: Array = []       # 내 차별 셋업 [{wing, press, fuel_load}]
var wear_est := {}           # {err, runs, bias}
var practice_left: Array = [PRACTICE_LAPS, PRACTICE_LAPS]
var practice_runs: Array = []
var last_feedback := ""
var eng_q := 0.5             # 엔지니어 실력 0~1 (추천 범위 폭)
var bands: Array = []        # 내 차별 엔지니어 추천 범위 {key: {c: 중심, hw: 반폭}}
var Q := {}                  # 예선 상태
var done_quali := false
var _q_soft_used := {}


## sim 은 new_race 까지 끝난 상태여야 한다. obligation_laps: 스폰서 행사로 줄어드는 연습 랩 수.
func setup(sim_, obligation_laps: int = 0, eng_quality: float = -1.0) -> void:
	sim = sim_
	# 주말 타이어: F1 S2·M2·H1 / WEC S1·M2·H2 (예선 세션이 2개라 새 소프트가 1세트뿐)
	if sim.is_wec():
		sets = [{"S": 1, "M": 2, "H": 2}, {"S": 1, "M": 2, "H": 2}]
	else:
		sets = [{"S": 2, "M": 2, "H": 1}, {"S": 2, "M": 2, "H": 1}]
	setups = []
	bands = []
	for c in my_cars():
		setups.append({"wing": c.wing, "press": c.press, "fuel_load": c.fuel_load})
		c.tyre_sets = sets[c.slot]
		eng_q = eng_quality if eng_quality >= 0.0 else sim.team_eng_q(c)
		bands.append(_make_band(c))
	var bias := {}
	for k in ["S", "M", "H"]:
		bias[k] = sim.uni(-0.24, 0.24)
	wear_est = {"err": 0.35, "runs": 0, "bias": bias}
	var lp = maxi(3, PRACTICE_LAPS - obligation_laps)
	practice_left = [lp, lp]
	practice_runs = []
	done_quali = false
	Q = {}


func my_cars() -> Array:
	return sim.my_cars()


## 내 차가 속한 클래스 (WEC 하위 리그면 LMP2·LMGT3). 하이퍼폴은 이 클래스만
func main_cls() -> String:
	var mc: Array = my_cars()
	return mc[0].cls if not mc.is_empty() else "HY"


func _cls_rank(c: String) -> int:
	return {"HY": 0, "P2": 1, "GT": 2}.get(c, 0)


## 셋업 변경은 연습 중에만 (예선부터는 파크 페르메로 윙 고정)
func set_wing(slot: int, w: float) -> void:
	var c = my_cars()[slot]
	c.wing = snappedf(clampf(w, 1.0, 5.0), 0.1)
	setups[slot]["wing"] = c.wing


func set_press(slot: int, p: String) -> void:
	var c = my_cars()[slot]
	c.press = p
	setups[slot]["press"] = p


func set_detail(slot: int, key: String, v: float) -> void:
	var c = my_cars()[slot]
	var r: Array = RS.SETUP_RANGE[key]
	var val: float = snappedf(clampf(v, float(r[0]), float(r[1])), 0.1 if key == "susp" else (0.5 if key == "bbias" else 1.0))
	c.set(key, val)
	setups[slot][key] = val


func set_fuel_load(slot: int, f: String) -> void:
	var c = my_cars()[slot]
	c.fuel_load = f
	setups[slot]["fuel_load"] = f
	c.fuel = sim.laps * RS.FPL * (1.0 + float(RS.FUEL_LOAD[f]))


# ═════════ 세부 셋업 · 엔지니어 추천 범위 ═════════
const WING_RANGE := [1.0, 5.0]


func _span(key: String) -> Array:
	return WING_RANGE if key == "wing" else RS.SETUP_RANGE[key]


func _opt(c, key: String) -> float:
	return sim.wing_opt(0.0, c) if key == "wing" else float(sim.setup_opt(c)[key])


## 엔지니어 실력이 좋을수록 좁고 정확한 범위. 정답은 범위 안 어딘가 (가운데가 정답은 아님)
func _make_band(c) -> Dictionary:
	var b := {}
	for key in ["wing", "susp", "bbias", "diff"]:
		var r: Array = _span(key)
		var span: float = float(r[1]) - float(r[0])
		var hw: float = (0.08 + 0.22 * (1.0 - eng_q)) * span
		var ctr: float = _opt(c, key) + sim.uni(-0.6, 0.6) * hw
		b[key] = {"c": ctr, "hw": hw}
	return b


func band_lohi(slot: int, key: String) -> Array:
	var bd: Dictionary = bands[slot][key]
	var r: Array = _span(key)
	return [maxf(float(r[0]), float(bd["c"]) - float(bd["hw"])), minf(float(r[1]), float(bd["c"]) + float(bd["hw"]))]


## 테스트 주행 데이터가 쌓이면 범위가 좁아지고 정답 쪽으로 다가간다
func _refine_band(slot: int, laps_run: int) -> void:
	var c = my_cars()[slot]
	var k: float = pow(0.9, laps_run / 3.0)
	for key in bands[slot]:
		var bd: Dictionary = bands[slot][key]
		var r: Array = _span(key)
		var span: float = float(r[1]) - float(r[0])
		var o := _opt(c, key)
		bd["hw"] = maxf(0.03 * span, float(bd["hw"]) * k)
		bd["c"] = o + (float(bd["c"]) - o) * k
		# 범위가 정답을 벗어나지 않게
		if absf(float(bd["c"]) - o) > float(bd["hw"]) * 0.8:
			bd["c"] = o + signf(float(bd["c"]) - o) * float(bd["hw"]) * 0.8


## 엔지니어에게 맡기기: 추천 범위 한가운데로
func engineer_apply(slot: int) -> void:
	for key in ["wing", "susp", "bbias", "diff"]:
		var v: float = float(bands[slot][key]["c"])
		if key == "wing":
			set_wing(slot, v)
		else:
			set_detail(slot, key, v)


# ═════════ 타이어 마모 추정 (연습 롱런으로 오차가 줄어든다) ═════════
func est_wear_rate(comp: String) -> float:
	var tv: float = sim.true_wear_rate(comp)
	return maxf(0.010, tv * (1.0 + float(wear_est["bias"][comp]) * (float(wear_est["err"]) / 0.35)))


func est_range_text(comp: String) -> String:
	var est := est_wear_rate(comp)
	var err: float = wear_est["err"]
	var lo := maxf(0.008, est * (1.0 - err))
	var hi := est * (1.0 + err)
	# 화면에는 '한 바퀴 마모 %' 로 보여준다 (서킷 마모·레이스 길이 반영)
	var k: float = float(sim.CIRC["wear"]) * (RS.WEC_WEAR if sim.is_wec() else RS.WEAR_SCALE / sim.laps) * 100.0
	return "%.1f~%.1f%%/랩" % [lo * k, hi * k]


func feedback(c) -> String:
	var d_w: float = c.wing - sim.wing_opt(0.0, c)
	var a := "밸런스 좋아요"
	if d_w <= -1.0:
		a = "코너에서 차가 불안해요, 다운포스가 부족해요"
	elif d_w >= 1.5:
		a = "직선에서 느려요, 날개가 너무 서 있어요"
	elif d_w >= 0.75:
		a = "조금 무거운 느낌이에요"
	elif d_w <= -0.75:
		a = "약간 가볍지만 나쁘지 않아요"
	var b := ""
	if c.press == "low":
		b = "그립과 예열은 좋은데 직선이 무겁고, 롱런에선 과열이 걱정돼요"
	elif c.press == "high":
		b = "직선은 잘 뻗지만 예열이 느리고 연석에서 튀어요"
	var tip: String = sim.setup_tip(c)
	return a + (". " + b if b != "" else "") + (". " + tip if tip != "" else "")


# ═════════ 연습 주행 ═════════
## kind: "short"(셋업 테스트 3랩) / "long"(롱런 5랩, 마모 추정 오차 절반)
func practice_run(slot: int, kind: String) -> Dictionary:
	var c = my_cars()[slot]
	var n := 5 if kind == "long" else 3
	if practice_left[slot] < n:
		return {}
	var comp := "M"
	var wear := 0.0
	var fuel: float = STINT * RS.FPL if kind == "long" else RS.FPL * 2.0
	var CIRC: Dictionary = sim.CIRC
	var ws: float = sim.wsc()
	var wr: float = sim.true_wear_rate(comp) * float(CIRC["wear"]) * (RS.WEC_WEAR if sim.is_wec() else RS.WEAR_SCALE / 15.0) * float(RS.PRESS[c.press][1]) * (1.0 - (c.wing - 3.0) * 0.04) * c.tyre_deg_rate * float(sim.setup_extra(c)["wear"])
	var res: Array = []
	for i in n:
		var t: float = float(CIRC["base"]) * sim.car_factor(c) * (1.0 - c.speed * float(RS.K["drv_k"])) + sim.setup_pen(c, 0.0) + float(RS.PRESS[c.press][0]) + sim.press_straight(c.press) + float(sim.setup_extra(c)["dt"])
		t += (wear * wear * float(RS.COMP[comp][2]) + sim.cliff_pen(comp, wear) + fuel * 0.03) * ws + sim.gauss(0.25)
		if c.press == "low" and wear > 0.5:
			t += 0.3 * float(RS.PRESS_FX["low"]["heat"])
		res.append(t)
		wear += wr
		fuel -= RS.FPL
	var best: float = res.min()
	var tot := 0.0
	for x in res:
		tot += x
	practice_left[slot] -= n
	_refine_band(slot, n)
	if kind == "long":
		wear_est["runs"] = int(wear_est["runs"]) + 1
		wear_est["err"] = snappedf(float(wear_est["err"]) * 0.5, 0.001)
	var r := {"code": c.code, "laps": res, "best": best, "avg": tot / n, "wear_lap": (wr * 100.0) if sim.is_wec() else (wr * 15.0 / sim.laps * 100.0), "kind": kind, "wing": c.wing, "press": c.press, "detail": "S%.1f B%.1f D%d" % [c.susp, c.bbias, int(c.diff)]}
	practice_runs.push_front(r)
	last_feedback = "%s: %s" % [c.name, feedback(c)]
	if kind == "long":
		last_feedback += " (마모 추정 오차 ±%d%%로 축소)" % int(round(float(wear_est["err"]) * 100.0))
	return r


## 남은 연습을 자동으로: 롱런 1회 + 셋업 테스트
func auto_practice() -> void:
	for slot in my_cars().size():
		engineer_apply(slot)
		if practice_left[slot] >= 5:
			practice_run(slot, "long")
		while practice_left[slot] >= 3:
			practice_run(slot, "short")
		engineer_apply(slot)


# ═════════ 예선 (원랩 어택, Q1→Q2→Q3) ═════════
func start_quali() -> void:
	Q = {"res": {}, "stage": 1, "max_stage": 2 if sim.is_wec() else 3, "eliminated": {}, "idx": 0, "done": false}
	_q_soft_used.clear()
	for c in my_cars():
		c.q3_locked = false
	_run_ai_stage(1)
	_skip_eliminated()


func q_lap(c, push: String, traffic: String, stage: int, comp: String, used_set: bool) -> Dictionary:
	var pv: Array = QPUSH[push]
	var tv: Array = QTRAFFIC.get(traffic, QTRAFFIC["clean"])
	var spd: float = pv[0]
	var err: float = pv[1]
	var lim: float = pv[2]
	var evo_bonus: float = tv[0]
	var trf_risk: float = tv[1]
	var stage_evo := (stage - 1) * -0.18
	var ws: float = sim.wsc()
	var comp_delta: float = float(RS.COMP[comp][0]) * ws
	var used_pen: float = 0.45 * ws if used_set else 0.0
	var note := "헌 타이어 어택 (약 +0.45s)" if used_set else ""
	var deleted := false
	var secs: Array = []
	var CIRC: Dictionary = sim.CIRC
	for s in NS:
		var sh: float = sim.T.share[s]
		var t: float = float(CIRC["base"]) * sh * sim.car_factor(c) * (1.0 - c.speed * float(RS.K["drv_k"]) * spd)
		t += (comp_delta + used_pen + sim.setup_pen(c, 0.0) + float(RS.PRESS[c.press][0]) + sim.press_straight(c.press) + float(sim.setup_extra(c)["dt"]) + evo_bonus + stage_evo) * sh + 5.0 * 0.03 * sh
		t += sim.gauss(0.10 * sqrt(sh) * sqrt(ws))
		if sim.rnd() < trf_risk * sh * 1.6:
			var loss: float = sim.uni(0.22, 0.68)
			t += loss
			note = "섹터 %d 트래픽 +%.2fs" % [s + 1, loss]
		if sim.rnd() < 0.012 * err * sim.press_kerb(c.press) * (1.25 - c.cons) * (1.0 + absf(c.wing - float(CIRC["wingOpt"])) * 0.3):
			t += sim.uni(0.3, 1.5)
			note = "실수로 시간 손실"
		if sim.rnd() < lim * (1.2 - c.cons) * sim.press_kerb(c.press):
			deleted = true
			note = "섹터 %d 트랙 리밋 위반 → Q%d 기록 삭제" % [s + 1, stage]
		secs.append(t)
	var total := 0.0
	for x in secs:
		total += x
	return {"id": c.id, "secs": secs, "total": total, "deleted": deleted, "note": note, "push": push, "stage": stage, "q_comp": comp, "used": used_set}


func _run_ai_stage(st: int) -> void:
	for c in sim.cars:
		if c.mine or Q["eliminated"].has(c.id):
			continue
		if sim.is_wec() and c.cls != main_cls() and st > 1:
			continue # 하이퍼폴은 하이퍼카만
		var r = sim.rnd()
		var trf := "clean"
		if r >= 0.6:
			trf = "early" if sim.rnd() < 0.5 else "late"
		var ai_comp := "M" if (st == 1 and c.speed > 0.86 and sim.rnd() < 0.5) else "S"
		var used_n: int = _q_soft_used.get(c.id, 0)
		var ai_used: bool = ai_comp == "S" and used_n >= (1 if sim.is_wec() else 2)
		if ai_comp == "S":
			_q_soft_used[c.id] = used_n + 1
		var push := "std"
		if c.aggr > 0.72:
			push = "limit"
		elif c.aggr < 0.5:
			push = "safe"
		Q["res"][c.id] = q_lap(c, push, trf, st, ai_comp, ai_used)


func _skip_eliminated() -> void:
	var mine: Array = my_cars()
	while Q["idx"] < mine.size() and Q["eliminated"].has(mine[Q["idx"]].id):
		Q["idx"] += 1


## 지금 어택할 내 차 (없으면 null)
func current_car() -> Variant:
	var mine: Array = my_cars()
	if Q.is_empty() or Q["done"] or Q["idx"] >= mine.size():
		return null
	return mine[Q["idx"]]


## 내 차 어택 랩 계산 (세트 소모). 화면이 섹터 애니메이션을 보여준 뒤 commit_lap 을 부른다.
func my_lap(comp: String, push: String, traffic: String) -> Dictionary:
	var c: Variant = current_car()
	if c == null:
		return {}
	var qs: Dictionary = sets[c.slot]
	var used_set: bool = not (qs[comp] > 0)
	if not used_set:
		qs[comp] -= 1
	return q_lap(c, push, traffic, Q["stage"], comp, used_set)


func commit_lap(res: Dictionary) -> void:
	Q["res"][res["id"]] = res
	Q["idx"] += 1
	_skip_eliminated()
	var mine: Array = my_cars()
	if Q["idx"] < mine.size():
		return
	# 이 세션의 내 차가 모두 달렸다 → 컷오프 후 다음 세션
	while Q["stage"] < Q["max_stage"]:
		var cut := 15 if Q["stage"] == 1 else 10
		var ord: Array = q_order()
		if sim.is_wec():
			# 하이퍼폴: 하이퍼카 상위 8대만 진출 (GT3는 예선 기록으로 뒤쪽 그리드)
			cut = 8
			var hy: Array = []
			for c in ord:
				if c.cls == main_cls():
					hy.append(c)
				else:
					Q["eliminated"][c.id] = true
			ord = hy
		for i in range(cut, ord.size()):
			Q["eliminated"][ord[i].id] = true
		Q["stage"] += 1
		Q["idx"] = 0
		_skip_eliminated()
		_run_ai_stage(Q["stage"])
		if Q["idx"] < mine.size():
			return
	finish_quali()


## 남은 예선을 자동 진행 (내 차는 기본 선택: 소프트·표준·클린 에어)
func auto_quali() -> void:
	if Q.is_empty():
		start_quali()
	var guard := 0
	while not Q["done"] and guard < 20:
		guard += 1
		var c: Variant = current_car()
		if c == null:
			break
		var comp := "S" if sets[c.slot]["S"] > 0 else "M"
		commit_lap(my_lap(comp, "std", "clean"))


func q_order() -> Array:
	var arr: Array = sim.cars.duplicate()
	arr.sort_custom(_q_cmp)
	return arr


func _q_cmp(x, y) -> bool:
	var res: Dictionary = Q.get("res", {})
	if x.cls != y.cls:
		return _cls_rank(x.cls) < _cls_rank(y.cls)
	var a: Variant = res.get(x.id)
	var b: Variant = res.get(y.id)
	if a == null and b == null:
		return x.grid < y.grid
	if a == null:
		return false
	if b == null:
		return true
	if a["stage"] != b["stage"]:
		return a["stage"] > b["stage"]
	if a["deleted"] != b["deleted"]:
		return not a["deleted"]
	return a["total"] < b["total"]


func pole() -> Variant:
	var p: Variant = null
	for r in Q.get("res", {}).values():
		if not r["deleted"] and r["stage"] == Q["stage"] and (p == null or r["total"] < p["total"]):
			p = r
	if p == null:
		for r in Q.get("res", {}).values():
			if not r["deleted"] and (p == null or r["total"] < p["total"]):
				p = r
	return p


## 섹터별 전체 최고 기록 (보라색 표시용)
func best_secs(exclude_id: int) -> Array:
	var best: Array = []
	for i in NS:
		best.append(INF)
	for id in Q.get("res", {}):
		if id == exclude_id:
			continue
		var r: Dictionary = Q["res"][id]
		for i in NS:
			best[i] = minf(best[i], r["secs"][i])
	return best


func finish_quali() -> void:
	Q["done"] = true
	done_quali = true
	var ord: Array = q_order()
	sim.cars = ord
	for i in ord.size():
		var c = ord[i]
		c.grid = i
		var r: Variant = Q["res"].get(c.id)
		# 파크 페르메: 최종 세션(Q3) 진출 차는 그 세션 타이어로 출발 (어택 1랩 마모 5%, 헌 세트 14%)
		if r != null and r["stage"] == Q["max_stage"]:
			c.comp = r["q_comp"]
			c.used = {c.comp: true}
			c.q3_locked = true
			c.used_set_pen = 0.45 if r["used"] else 0.0
			c.wear = 0.14 if r["used"] else 0.05
	sim.team_split = {}
	for c in sim.cars:
		if not c.mine:
			if not sim.is_wec():
				sim.plan_ai_strategy(c, c.comp if c.q3_locked else "")
	var parts: Array = []
	for c in my_cars():
		parts.append("%s P%d(%s)" % [c.code, c.grid + 1, c.comp])
	sim.event("예선 종료 · 그리드 확정: " + ", ".join(parts))


## Q3 진출 못 한 내 차는 출발 타이어를 고를 수 있다
func set_start_comp(slot: int, comp: String) -> void:
	var c = my_cars()[slot]
	if c.q3_locked:
		return
	c.comp = comp
	c.used = {comp: true}
	c.plan = {"start": comp, "stops": []}


## 예선을 건너뛸 때: 원래 레이스처럼 예선 페이스 순 그리드 (new_race 기본값) 그대로
func skip_weekend() -> void:
	done_quali = true
