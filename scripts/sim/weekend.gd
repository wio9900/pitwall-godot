extends RefCounted
## 레이스 주말: 셋업 → 연습 주행 → 예선(Q1·Q2·Q3) → 결승 그리드.
## 원본 HTML(v16.1) practiceLaps / qLap / runAiQualiForStage / qOrder / finishQuali 를 옮겼다.
## 레이스 시뮬레이션(race_sim)을 먼저 만든 뒤 그 차들을 가지고 연습·예선을 돌린다. 화면과 무관.

const RS = preload("res://scripts/sim/race_sim.gd")
const NS := 6
const STINT := 5
## 예선 한 랩의 컴파운드 차이 (레이스용 COMP 보다 작다: 실제 예선에서 소프트-미디엄 약 0.5초).
## 헌 세트 벌점 0.45초와 비슷하게 맞춰, '쓴 소프트 ≈ 새 미디엄'이 되도록 → 새 소프트를 어느 세션에 쓸지 고민하게
const QCOMP := {"S": -0.55, "M": 0.0, "H": 0.45}
const QPUSH := {"safe": [0.85, 0.5, 0.0], "std": [1.0, 1.0, 0.012], "limit": [1.15, 2.0, 0.07]}
const QPUSH_KO := {"safe": "안전하게", "std": "표준", "limit": "한계까지"}
const QTRAFFIC := {"early": [0.05, 0.12, "즉시 출주"], "clean": [-0.12, 0.04, "클린 에어 대기"], "late": [-0.28, 0.28, "막판 릴리즈"]}
## 예선 세션 시계 (분). 출발 시각을 직접 고른다: 늦을수록 노면이 좋아지지만(트랙 에볼루션)
## 막판엔 다들 나와서 트래픽·사고(어택 중단) 위험이 커지고, 중단되면 다시 나갈 시간이 없다.
const QLEN_F1 := [0.0, 18.0, 15.0, 12.0]
const QLEN_WEC := [0.0, 15.0, 12.0]
const RUN_MIN := 3.0   # 아웃랩 + 어택 랩 (분, 화면 막대 눈금용)
const OUT_MIN := 1.6   # 아웃랩 (분): 체커기 전에 어택 랩을 시작해야 하므로 마지막 출발 = 세션 길이 - 1.6분
const IN_MIN := 1.4    # 인랩 (분)
const RED_MIN := 2.5   # 레드 플래그로 멈추는 시간 (세션 시계는 멈춘다)
const PRESS_KO := {"low": "낮게", "std": "표준", "high": "높게"}
const FUEL_LOAD_KO := {"light": "가볍게", "std": "표준", "heavy": "넉넉하게"}
const PRACTICE_LAPS := 16

var sim                      # race_sim.gd
var sets: Array = []         # 내 차별 '새' 타이어 세트 [{S, M, H}, {…}] (연습·예선·결승 공용 할당)
var used_sets: Array = []    # 내 차별 '쓴' 세트 수 (연습·예선에서 한 번이라도 달린 세트)
## 주말 타이어 할당: 연습부터 결승까지 이 안에서 해결한다 (실제 F1 의 주말 13세트를 이 게임 길이에 맞춰 축소)
const ALLOC_F1 := {"S": 3, "M": 3, "H": 2}
const ALLOC_WEC := {"S": 2, "M": 3, "H": 2}  # WEC 결승은 별도 레이스 할당(race_sim wec_sets)을 쓴다
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
	var al: Dictionary = ALLOC_WEC if sim.is_wec() else ALLOC_F1
	if sim.is_wec():
		# 이번 대회에 쓸 수 있는 컴파운드만 (2종이면 3세트씩, 르망 3종은 S2·M3·H2)
		var ok: Array = sim.wec_comps(main_cls())
		if ok.size() < 3:
			al = {"S": 0, "M": 0, "H": 0}
			for k in ok:
				al[k] = 3
	sets = [al.duplicate(), al.duplicate()]
	used_sets = [{"S": 0, "M": 0, "H": 0}, {"S": 0, "M": 0, "H": 0}]
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
	return {"HY": 0, "P2": 1, "P3": 2, "GT": 3}.get(c, 0)


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
	c.fuel = sim.laps * RS.FPL * (1.0 + float(RS.FUEL_LOAD[f])) * c.fuel_burn_rate


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
## 세트 꺼내기. 연습은 쓴 세트를 먼저(없으면 새 세트를 하나 연다), 예선은 새 세트를 먼저.
## 돌려주는 값: "new" / "used" / "" (그 컴파운드는 남은 세트가 없음)
func take_set(slot: int, comp: String, prefer_new: bool) -> String:
	var nw: Dictionary = sets[slot]
	var us: Dictionary = used_sets[slot]
	if not nw.has(comp):
		return "new" # 인터·웻은 할당 밖
	if prefer_new and int(nw[comp]) > 0 or (not prefer_new and int(us[comp]) == 0 and int(nw[comp]) > 0):
		nw[comp] = int(nw[comp]) - 1
		us[comp] = int(us[comp]) + 1
		return "new"
	if int(us[comp]) > 0:
		return "used"
	return ""


func has_any(slot: int, comp: String) -> bool:
	return int(sets[slot].get(comp, 0)) > 0 or int(used_sets[slot].get(comp, 0)) > 0


func practice_run(slot: int, kind: String, comp: String = "M") -> Dictionary:
	var c = my_cars()[slot]
	var n := 5 if kind == "long" else 3
	if practice_left[slot] < n:
		return {}
	if sim.is_wec():
		comp = sim.wec_fit_comp(c.cls, comp)
	if take_set(slot, comp, false) == "":
		return {}
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
	var r := {"code": c.code, "comp": comp, "laps": res, "best": best, "avg": tot / n, "wear_lap": (wr * 100.0) if sim.is_wec() else (wr * 15.0 / sim.laps * 100.0), "kind": kind, "wing": c.wing, "press": c.press, "detail": "S%.1f B%.1f D%d" % [c.susp, c.bbias, int(c.diff)]}
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
			practice_run(slot, "long", "M")
		while practice_left[slot] >= 3:
			if practice_run(slot, "short", "M").is_empty():
				break
		engineer_apply(slot)


# ═════════ 예선 (원랩 어택, Q1→Q2→Q3) ═════════
func start_quali() -> void:
	Q = {"res": {}, "stage": 1, "max_stage": 2 if sim.is_wec() else 3, "eliminated": {}, "done": false, "auto": false, "ver": 0, "reds": 0}
	_q_soft_used.clear()
	for c in my_cars():
		c.q3_locked = false
	_start_stage(1)


## 세션 길이(분)
func q_len(stage: int = -1) -> float:
	var st: int = int(Q.get("stage", 1)) if stage < 0 else stage
	var arr: Array = QLEN_WEC if sim.is_wec() else QLEN_F1
	# 랩이 긴 서킷(르망 3분 반)은 세션도 비례해서 길게: 아웃랩·어택·인랩 한 번에 랩 3바퀴 남짓 걸리므로
	return float(arr[clampi(st, 1, arr.size() - 1)]) * maxf(1.0, lap_min() / 1.7)


## 이 서킷 기준 랩 (분)
func lap_min() -> float:
	return float(sim.CIRC.get("base", 90.0)) / 60.0


## 아웃랩·인랩 (분): 서킷 랩타임에 비례 (어택 랩보다 조금 느리게 한 바퀴)
func out_min() -> float:
	return maxf(OUT_MIN, lap_min() * 1.2)


func in_min() -> float:
	return maxf(IN_MIN, lap_min() * 1.15)


## 마지막으로 피트를 나갈 수 있는 시각: 아웃랩을 마치고 체커기 전에 어택 랩을 시작해야 한다
func q_last_dep(stage: int = -1) -> float:
	return q_len(stage) - out_min()


## 지금 노면·트래픽 {evo 초, risk 트래픽 확률}: 노면은 달린 랩 수와 시간으로 좋아지고, 트래픽은 트랙 위 차 수로 정해진다
func q_now() -> Dictionary:
	var n_part: int = maxi(1, int(Q.get("n_part", 20)))
	var laps_f: float = clampf(float(Q.get("laps_done", 0)) / (n_part * 1.3), 0.0, 1.0)
	var t_f: float = clampf(float(Q.get("t", 0.0)) / q_len(), 0.0, 1.0)
	var on: int = Q.get("run", {}).size()
	return {"evo": 0.10 - 0.30 * laps_f - 0.08 * t_f, "risk": 0.02 + 0.03 * minf(10.0, float(on)), "on": on}


## (예전 방식 호환) 시각만으로 대략의 조건
func q_cond(stage: int, minute: float) -> Dictionary:
	var T: float = q_len(stage)
	var f: float = clampf(minute / maxf(1.0, T), 0.0, 1.0)
	return {"evo": 0.10 - 0.38 * f, "risk": 0.04 + 0.2 * f, "abort": 0.03}


func q_lap(c, push: String, traffic: Variant, stage: int, comp: String, used_set: bool) -> Dictionary:
	var pv: Array = QPUSH[push]
	var tv: Array = [0.0, 0.0]
	if traffic is Dictionary:
		tv = [float(traffic["evo"]), float(traffic["risk"])]
	else:
		tv = QTRAFFIC.get(traffic, QTRAFFIC["clean"])
	var spd: float = pv[0]
	var err: float = pv[1]
	var lim: float = pv[2]
	var evo_bonus: float = tv[0]
	var trf_risk: float = tv[1]
	var stage_evo := (stage - 1) * -0.18
	var ws: float = sim.wsc()
	var comp_delta: float = float(QCOMP.get(comp, RS.COMP[comp][0])) * ws
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


# ═════════ 라이브 예선: 시계가 흐르고 AI 가 각자 판단으로 나가고 들어온다 ═════════
## Q["run"][id] = {phase: out/push/in, t0, dur, comp, push, used, res}
## 내 차는 player_depart / player_abort 로 직접, AI 는 Q["plan"][id] (출발 시각 목록)과 _ai_react 로 스스로 판단

func _participant(c, st: int) -> bool:
	if Q["eliminated"].has(c.id):
		return false
	if sim.is_wec() and st > 1 and c.cls != main_cls():
		return false # 하이퍼폴은 하이퍼카만
	return true


func _start_stage(st: int) -> void:
	Q["stage"] = st
	Q["t"] = 0.0
	Q["red_left"] = 0.0
	Q["red_done"] = false
	Q["laps_done"] = 0
	Q["run"] = {}
	Q["plan"] = {}
	Q["runs"] = {}
	Q["log"] = []
	Q["stage_over"] = false
	var n := 0
	for c in sim.cars:
		if not _participant(c, st):
			continue
		n += 1
		Q["runs"][c.id] = 0
		if not c.mine or Q["auto"]:
			Q["plan"][c.id] = _ai_plan(c, st)
	Q["n_part"] = n
	Q["ver"] = int(Q["ver"]) + 1
	_log("Q%d 시작 · %d분" % [st, int(q_len(st))] if not sim.is_wec() else ("%s 시작 · %d분" % ["예선" if st == 1 else "하이퍼폴", int(q_len(st))]))


## AI 출발 계획: 55%는 초반에 기록을 하나 만들어 두고(뱅커), 모두 막판에 한 번 더
func _ai_plan(c, st: int) -> Array:
	var T: float = q_len(st)
	var plan: Array = []
	if c.mine:
		plan.append(sim.uni(T - out_min() - 3.4, T - out_min() - 0.5))
		return plan
	if sim.rnd() < 0.55:
		plan.append(sim.uni(0.3, T * 0.35))
	plan.append(sim.uni(T - out_min() - 4.4, T - out_min() - 0.3))
	return plan


func _log(msg: String) -> void:
	Q["log"].push_front("[%s] %s" % [q_clock_txt(), msg])
	if Q["log"].size() > 8:
		Q["log"].resize(8)


## 남은 세션 시간 "mm:ss"
func q_clock_txt() -> String:
	var rem: float = maxf(0.0, q_len() - float(Q.get("t", 0.0)))
	var sec: int = int(round(rem * 60.0))
	return "%d:%02d" % [sec / 60, sec % 60]


func q_on_track(c) -> bool:
	return Q.get("run", {}).has(c.id)


func q_phase(c) -> String:
	var r: Variant = Q.get("run", {}).get(c.id)
	return "" if r == null else String(r["phase"])


func _ai_comp(c, st: int, run_i: int, plan_left: int) -> Array:
	var comp := "S"
	if sim.is_wec():
		comp = "M" if st >= 2 else sim.wec_fit_comp(c.cls, "S")
	elif st == 1 and plan_left > 0 and c.speed > 0.80:
		comp = "M" # 빠른 차는 Q1 뱅커를 미디엄으로
	var used_n: int = _q_soft_used.get(c.id, 0)
	var used: bool = comp == "S" and used_n >= (1 if sim.is_wec() else 2)
	if comp == "S" and not used:
		_q_soft_used[c.id] = used_n + 1
	return [comp, used]


func _depart(c, comp: String, push: String, used: bool) -> void:
	Q["run"][c.id] = {"phase": "out", "t0": float(Q["t"]), "dur": out_min(), "d0": 0.0, "comp": comp, "push": push, "used": used, "res": null}
	if c.mine:
		Q["ver"] = int(Q["ver"]) + 1


## 내 차 출발. 실패하면 이유 문자열, 성공하면 ""
func player_depart(slot: int, comp: String, push: String) -> String:
	if Q.is_empty() or Q["done"] or Q["stage_over"]:
		return "세션이 끝났어요"
	var c = my_cars()[slot]
	if not _participant(c, Q["stage"]):
		return "이번 세션에 나갈 수 없어요"
	if q_on_track(c):
		return "이미 트랙에 있어요"
	if float(Q["red_left"]) > 0.0:
		return "레드 플래그 중이에요"
	if float(Q["t"]) > q_last_dep():
		return "체커기 전에 어택을 시작할 수 없어요"
	if sim.is_wec():
		comp = "M" if Q["stage"] >= 2 else sim.wec_fit_comp(c.cls, comp)
	if not has_any(slot, comp):
		return "%s 세트가 없어요" % RS.TYRE_KO[comp]
	var used: bool = take_set(slot, comp, true) != "new"
	_depart(c, comp, push, used)
	return ""


## 내 차가 아웃랩 중이면 어택을 포기하고 들어온다 (타이어는 이미 썼다)
func player_abort(slot: int) -> void:
	var c = my_cars()[slot]
	var r: Variant = Q["run"].get(c.id)
	if r != null and r["phase"] == "out":
		# 지금 위치에서 남은 바퀴만 돌아 피트로 (화면에서 끊기지 않게)
		var f: float = clampf((float(Q["t"]) - float(r["t0"])) / maxf(0.01, float(r["dur"])), 0.0, 1.0)
		r["phase"] = "in"
		r["t0"] = float(Q["t"])
		r["d0"] = f
		r["dur"] = maxf(0.05, in_min() * (1.0 - f))
		Q["ver"] = int(Q["ver"]) + 1


## 세션을 dt 분만큼 진행 (레드 플래그 동안은 시계가 멈춘다)
func q_advance(dt: float) -> void:
	if Q.is_empty() or Q["done"] or Q["stage_over"]:
		return
	var steps: int = maxi(1, int(ceil(dt / 0.05)))
	for i in steps:
		_q_step(dt / steps)
		if Q["done"] or Q["stage_over"]:
			return


func _q_step(h: float) -> void:
	if float(Q["red_left"]) > 0.0:
		Q["red_left"] = float(Q["red_left"]) - h
		if float(Q["red_left"]) <= 0.0:
			_log("그린 플래그 · 세션 재개 (남은 %s)" % q_clock_txt())
			Q["ver"] = int(Q["ver"]) + 1
		return
	Q["t"] = float(Q["t"]) + h
	var t: float = Q["t"]
	var T: float = q_len()
	# AI(와 자동 진행 중인 내 차) 출발
	for c in sim.cars:
		if not Q["plan"].has(c.id) or q_on_track(c):
			continue
		var plan: Array = Q["plan"][c.id]
		if plan.is_empty() or float(plan[0]) > t:
			continue
		plan.pop_front()
		if t > q_last_dep():
			continue
		if c.mine:
			var comp := "S" if has_any(c.slot, "S") else ("M" if has_any(c.slot, "M") else "H")
			player_depart(c.slot, comp, "std")
		else:
			var cu: Array = _ai_comp(c, Q["stage"], int(Q["runs"].get(c.id, 0)), plan.size())
			var push := "std"
			if c.aggr > 0.72:
				push = "limit"
			elif c.aggr < 0.5:
				push = "safe"
			_depart(c, cu[0], push, cu[1])
	# 달리는 차 진행
	for id in Q["run"].keys():
		var r: Dictionary = Q["run"][id]
		var c = _car(id)
		if t < float(r["t0"]) + float(r["dur"]):
			continue
		match String(r["phase"]):
			"out":
				if t > T:
					r["phase"] = "in" # 체커기 전에 어택을 시작하지 못했다 → 천천히 한 바퀴 돌아 피트로
					r["t0"] = t
					r["d0"] = 0.0
					r["dur"] = in_min()
					if c.mine:
						_log("%s 체커기에 걸려 어택 못 함" % c.code)
					continue
				var cond: Dictionary = q_now()
				var res: Dictionary = q_lap(c, r["push"], cond, Q["stage"], r["comp"], r["used"])
				res["t_start"] = t
				r["res"] = res
				r["phase"] = "push"
				r["t0"] = t
				r["dur"] = float(res["total"]) / 60.0
			"push":
				var res2: Dictionary = r["res"]
				Q["laps_done"] = int(Q["laps_done"]) + 1
				if _better(Q["res"].get(id), res2):
					Q["res"][id] = res2
				var pos: int = q_class_order(c).find(c) + 1
				if c.mine or pos <= 3 or res2["deleted"]:
					_log("%s %s · P%d%s" % [c.code, "기록 삭제" if res2["deleted"] else _fmt(float(res2["total"])), pos, (" · " + String(res2["note"])) if String(res2["note"]) != "" and c.mine else ""])
				r["phase"] = "in"
				r["t0"] = t
				r["d0"] = 0.0
				r["dur"] = in_min()
			"in":
				Q["run"].erase(id)
				Q["runs"][id] = int(Q["runs"].get(id, 0)) + 1
				if not c.mine:
					_ai_react(c)
		if c.mine:
			Q["ver"] = int(Q["ver"]) + 1
	# 레드 플래그: 트랙 위 차가 많을수록 잦다 (세션당 한 번까지)
	if not Q["red_done"] and t < T - 0.5:
		var n_on: int = Q["run"].size()
		if n_on > 0 and sim.rnd() < h * (0.002 + 0.0012 * n_on):
			_red_flag()
	if t >= T and Q["run"].is_empty():
		_end_stage()


func _car(id: int):
	for c in sim.cars:
		if c.id == id:
			return c
	return null


func _fmt(t: float) -> String:
	return "%d:%06.3f" % [int(t) / 60, fmod(t, 60.0)]


## 레드 플래그: 어택 중이던 랩은 모두 무효, 모든 차가 피트로. 시계는 멈췄다가 재개 → 재개 직후 다들 몰려나간다
func _red_flag() -> void:
	Q["red_done"] = true
	Q["red_left"] = RED_MIN
	Q["reds"] = int(Q.get("reds", 0)) + 1
	var on: Array = Q["run"].keys()
	var cause = _car(on[sim.rng.randi_range(0, on.size() - 1)])
	_log("🟥 레드 플래그! %s 사고 · 어택 중이던 랩 무효" % cause.code)
	for id in on:
		Q["runs"][id] = int(Q["runs"].get(id, 0)) + 1
	Q["run"] = {}
	# AI: 남은 계획이 없고 시간이 있으면 재개 직후 다시 나간다
	for c in sim.cars:
		if Q["plan"].has(c.id) and not c.mine:
			var plan: Array = Q["plan"][c.id]
			if plan.is_empty():
				_ai_react(c)
	Q["ver"] = int(Q["ver"]) + 1


## AI 가 피트로 돌아왔을 때: 기록이 없거나 컷오프 근처면 시간이 남는 한 한 번 더
func _ai_react(c) -> void:
	var plan: Array = Q["plan"].get(c.id, [])
	if not plan.is_empty():
		return
	var t: float = Q["t"]
	var last: float = q_last_dep() - 0.2
	if t + 0.6 > last:
		return
	var r: Variant = Q["res"].get(c.id)
	var no_time: bool = r == null or int(r["stage"]) != int(Q["stage"]) or r["deleted"]
	var pos: int = q_class_order(c).find(c) + 1
	var cut: int = _cut_n()
	var danger: bool = pos > cut - 3
	if no_time or (danger and sim.rnd() < 0.75) or sim.rnd() < 0.25:
		plan.append(sim.uni(maxf(t + 0.5, last - 4.0), last))
		Q["plan"][c.id] = plan


## 이번 세션에서 다음으로 넘어가는 인원
func _cut_n() -> int:
	if sim.is_wec():
		return 8
	return 15 if int(Q["stage"]) == 1 else 10


## 같은 클래스 안 순위 (이번 세션 참가 차만)
func q_class_order(c) -> Array:
	var out: Array = []
	for o in q_order():
		if o.cls == c.cls and _participant(o, Q["stage"]):
			out.append(o)
	return out


func _better(a: Variant, b: Dictionary) -> bool:
	if a == null:
		return true
	if int(a["stage"]) != int(b["stage"]):
		return true
	if a["deleted"] != b["deleted"]:
		return not b["deleted"]
	return float(b["total"]) < float(a["total"])


## 세션 종료: 컷오프 → 다음 세션 대기(화면에서 '다음 세션' 버튼) 또는 예선 끝
func _end_stage() -> void:
	var st: int = Q["stage"]
	if st >= int(Q["max_stage"]):
		_log("예선 종료")
		finish_quali()
		Q["ver"] = int(Q["ver"]) + 1
		return
	var cut: int = _cut_n()
	var ord: Array = q_order()
	if sim.is_wec():
		var hy: Array = []
		for c in ord:
			if c.cls == main_cls():
				hy.append(c)
			else:
				Q["eliminated"][c.id] = true
		ord = hy
	var out_names: PackedStringArray = []
	for i in range(cut, ord.size()):
		if not Q["eliminated"].has(ord[i].id):
			out_names.append(ord[i].code)
		Q["eliminated"][ord[i].id] = true
	Q["stage_over"] = true
	Q["cut_names"] = out_names
	_log("Q%d 종료 · 탈락: %s" % [st, ", ".join(out_names)])
	Q["ver"] = int(Q["ver"]) + 1


## 다음 세션 시작
func next_stage() -> void:
	if Q.is_empty() or not Q["stage_over"]:
		return
	_start_stage(int(Q["stage"]) + 1)


## 남은 예선을 자동으로 (내 차도 AI 처럼 막판에 한 번: 소프트 우선)
func auto_quali() -> void:
	if Q.is_empty():
		start_quali()
	Q["auto"] = true
	for c in my_cars():
		if _participant(c, Q["stage"]) and not q_on_track(c) and not Q["plan"].has(c.id):
			var t: float = Q["t"]
			if t + 0.3 < q_last_dep():
				Q["plan"][c.id] = [sim.uni(maxf(t + 0.2, q_last_dep() - 4.0), q_last_dep() - 0.2)]
	var guard := 0
	while not Q["done"] and guard < 2000:
		guard += 1
		if Q["stage_over"]:
			next_stage()
		else:
			q_advance(0.5)
	if not Q["done"]:
		finish_quali()


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
		if r != null and r["stage"] == Q["max_stage"] and not sim.is_wec(): # WEC 는 결승을 새 타이어로 출발
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


## 결승 출발: Q3 고정이 아닌 내 차는 출발 타이어도 주말 할당에서 꺼낸다 (새 세트가 없으면 헌 세트 +0.45초)
func commit_start_tyres() -> void:
	if sim.is_wec():
		return
	for c in my_cars():
		if c.q3_locked or not RS.SLICK.has(c.comp):
			continue
		if take_set(c.slot, c.comp, true) != "new":
			c.used_set_pen = 0.45
			c.wear = 0.10


## Q3 진출 못 한 내 차는 출발 타이어를 고를 수 있다
func set_start_comp(slot: int, comp: String) -> void:
	var c = my_cars()[slot]
	if c.q3_locked:
		return
	if sim.is_wec():
		comp = sim.wec_fit_comp(c.cls, comp)
	c.comp = comp
	c.used = {comp: true}
	c.plan = {"start": comp, "stops": []}


## 예선을 건너뛸 때: 원래 레이스처럼 예선 페이스 순 그리드 (new_race 기본값) 그대로
func skip_weekend() -> void:
	done_quali = true
