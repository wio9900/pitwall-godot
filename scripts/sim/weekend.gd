extends RefCounted
## 레이스 주말: 셋업 → 연습 주행 → 예선(Q1·Q2·Q3) → 결승 그리드.
## 원본 HTML(v16.1) practiceLaps / qLap / runAiQualiForStage / qOrder / finishQuali 를 옮겼다.
## 레이스 시뮬레이션(race_sim)을 먼저 만든 뒤 그 차들을 가지고 연습·예선을 돌린다. 화면과 무관.

const RS = preload("res://scripts/sim/race_sim.gd")
const BLog = preload("res://scripts/sim/blog.gd")
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
const FUEL_LOAD_KO := {"light": "가볍게", "std": "표준", "heavy": "넉넉하게"}
const PRACTICE_LAPS := 16

var sim                      # race_sim.gd
var sets: Array = []         # 내 차별 '새' 타이어 세트 [{S, M, H}, {…}] (연습·예선·결승 공용 할당)
var used_sets: Array = []    # 내 차별 '쓴' 세트 {S: [{w: 마모, h: 달군 횟수}…]} (연습·예선에서 한 번이라도 달린 세트)
var last_set: Variant = null  # take_set_mode 가 마지막으로 꺼낸 세트 (마모를 쌓을 곳)
const Q_RUN_LAPS := 2.0      # 예선 런 한 번(아웃랩·어택·인랩)이 세트에 남기는 마모 = 연습 2랩분
## 주말 타이어 할당: 연습부터 결승까지 이 안에서 해결한다 (실제 F1 의 주말 13세트를 이 게임 길이에 맞춰 축소)
const ALLOC_F1 := {"S": 3, "M": 3, "H": 2}
## F2: 무른 쪽(옵션) 2 + 단단한 쪽(프라임) 3 · F3: 드라이 1종 4세트 (실제 주말 할당 그대로)
const ALLOC_F2 := {"S": 2, "M": 3, "H": 0}
const ALLOC_F3 := {"S": 0, "M": 4, "H": 0}
const QLEN_SINGLE := 30.0   # F2·F3 예선: 탈락 없는 30분 단일 세션
const ALLOC_WEC := {"S": 2, "M": 3, "H": 2}  # WEC 결승은 별도 레이스 할당(race_sim wec_sets)을 쓴다
var setups: Array = []       # 내 차별 셋업 [{wing, press, fuel_load}]
var wear_est := {}           # {err: {S,M,H}, runs: {S,M,H}} — 컴파운드마다 따로: 롱런을 달린 컴파운드만 정확해진다
var rivals: Array = []       # 다른 팀 연습 기록 [{id, code, team, cls, s_best, s_comp, l_avg, l_comp}] (연료량은 모름)
var practice_left: Array = [PRACTICE_LAPS, PRACTICE_LAPS]
var practice_runs: Array = []
var last_feedback: Array = ["", ""]  # 차별 마지막 드라이버 멘트
var setup_dirty: Array = [false, false]  # 멘트 뒤 셋업을 바꿨나 (다시 달려야 확인)
var fb_lap: Array = [0, 0]  # 멘트가 나온 연습 랩 (몇 랩째 주행 기준인지)
var eng_q := 0.5             # 엔지니어 실력 0~1 (추천 범위 폭)
var bands: Array = []        # 내 차별 엔지니어 추천 범위 {key: {c: 중심, hw: 반폭}}
var Q := {}                  # 예선 상태
var done_quali := false
var _q_soft_used := {}
var _ai_sets := {}           # AI 차별 {new: {S,M,H}, used: {S,M,H}}
var start_pref: Array = ["auto", "auto"]  # 내 차 결승 출발 세트: auto(새 것 먼저) / new / used
var start_idx: Array = [-1, -1]  # used 일 때 고른 쓴 세트 번호 (-1 = 가장 덜 쓴 것)


## 주말 형식: f1 / f2 / f3 / wec (커리어 하위 리그는 rules.fmt 로 넘어옴)
func fmt() -> String:
	if sim.is_wec():
		return "wec"
	return String(sim.rules.get("fmt", "f1"))


## 단일 예선(탈락 없음): F2·F3
func single_quali() -> bool:
	return fmt() == "f2" or fmt() == "f3"


## 이 주말에 쓸 수 있는 드라이 컴파운드
func dry_comps(c) -> Array:
	if sim.is_wec():
		return sim.wec_comps(c.cls)
	var out: Array = []
	for k in ["S", "M", "H"]:
		if int(sets[c.slot if c.mine else 0].get(k, 0)) > 0 or used_n(c.slot if c.mine else 0, k) > 0:
			out.append(k)
	return out


## sim 은 new_race 까지 끝난 상태여야 한다. obligation_laps: 스폰서 행사로 줄어드는 연습 랩 수.
func setup(sim_, obligation_laps: int = 0, eng_quality: float = -1.0) -> void:
	sim = sim_
	var al: Dictionary = ALLOC_WEC if sim.is_wec() else ({"f2": ALLOC_F2, "f3": ALLOC_F3}.get(fmt(), ALLOC_F1))
	if sim.is_wec():
		# 이번 대회에 쓸 수 있는 컴파운드만 (2종이면 3세트씩, 르망 3종은 S2·M3·H2)
		var ok: Array = sim.wec_comps(main_cls())
		if ok.size() < 3:
			al = {"S": 0, "M": 0, "H": 0}
			for k in ok:
				al[k] = 3
	sets = [al.duplicate(), al.duplicate()]
	used_sets = [{"S": [], "M": [], "H": []}, {"S": [], "M": [], "H": []}]
	# AI 도 같은 할당에서 꺼내 쓴다 (연습에서 가장 단단한 컴파운드 한 세트를 연 상태로 예선 시작)
	_ai_sets = {}
	for c in sim.cars:
		if c.mine:
			continue
		var nw: Dictionary = al.duplicate()
		var us := {"S": [], "M": [], "H": []}
		for k in ["H", "M", "S"]:
			if int(nw.get(k, 0)) > 0:
				nw[k] = int(nw[k]) - 1
				us[k] = [{"w": sim.set_lap_wear(k) * 5.0, "h": 2}] # 연습 롱런 한 번 + 셋업 확인분
				break
		_ai_sets[c.id] = {"new": nw, "used": us}
	setups = []
	bands = []
	for c in my_cars():
		c.tyre_sets = sets[c.slot]
		c.used_tyres = used_sets[c.slot]
		eng_q = eng_quality if eng_quality >= 0.0 else sim.team_eng_q(c)
		bands.append(_make_band(c))
		c.psi = sim.psi_snap(float(bands[c.slot]["psi"]["c"])) # 연습·예선 기본 = 엔지니어 추천 (짧은 런 기준)
		setups.append({"wing": c.wing, "psi": c.psi, "fuel_load": c.fuel_load})
	wear_est = {"err": {"S": WEAR_ERR0, "M": WEAR_ERR0, "H": WEAR_ERR0}, "runs": {"S": 0, "M": 0, "H": 0}}
	sim.plan_mult = {}
	_make_rivals()
	var lp = maxi(3, PRACTICE_LAPS - obligation_laps)
	practice_left = [lp, lp]
	practice_runs = []
	last_feedback = ["", ""]
	setup_dirty = [false, false]
	fb_lap = [0, 0]
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
	_mark_dirty(slot)


func set_psi(slot: int, v: float) -> void:
	var c = my_cars()[slot]
	c.psi = sim.psi_snap(v)
	setups[slot]["psi"] = c.psi
	_mark_dirty(slot)


## 엔지니어 추천 공기압 범위 [낮음, 높음]: kind "q" = 짧은 런(연습 테스트·예선), "race" = 결승 (오래 달려 더 오르니 그만큼 낮게)
func psi_band(slot: int, kind: String) -> Array:
	var lh: Array = band_lohi(slot, "psi")
	var sh: float = sim.psi_rec(kind) - sim.psi_rec("q")
	return [sim.psi_snap(float(lh[0]) + sh), sim.psi_snap(float(lh[1]) + sh)]


func set_detail(slot: int, key: String, v: float) -> void:
	var c = my_cars()[slot]
	var r: Array = RS.SETUP_RANGE[key]
	var val: float = snappedf(clampf(v, float(r[0]), float(r[1])), 0.1 if key == "susp" else (0.5 if key == "bbias" else 1.0))
	c.set(key, val)
	setups[slot][key] = val
	_mark_dirty(slot)


func set_fuel_load(slot: int, f: String) -> void:
	var c = my_cars()[slot]
	# WEC 는 급유 레이스라 '레이스 전체 연료 탑재' 개념이 없다 (출발은 늘 가득 = TANK) — F1 식 계산을 하면 탱크의 몇 배가 실렸다
	if sim.is_wec():
		return
	c.fuel_load = f
	setups[slot]["fuel_load"] = f
	c.fuel = sim.laps * RS.FPL * (1.0 + float(RS.FUEL_LOAD[f])) * c.fuel_burn_rate
	_mark_dirty(slot)


## 멘트를 들은 뒤 셋업을 바꾸면 "다시 달려야 확인" 표시
func _mark_dirty(slot: int) -> void:
	if String(last_feedback[slot]) != "":
		setup_dirty[slot] = true


# ═════════ 세부 셋업 · 엔지니어 추천 범위 ═════════
const WING_RANGE := [1.0, 5.0]


func _span(key: String) -> Array:
	if key == "psi":
		return [sim.psi_min, sim.psi_min + RS.PSI_SPAN]
	return WING_RANGE if key == "wing" else RS.SETUP_RANGE[key]


func _opt(c, key: String) -> float:
	if key == "psi":
		return sim.psi_rec("q")
	return sim.wing_opt(0.0, c) if key == "wing" else float(sim.setup_opt(c, true)[key]) # 세부 셋업 = 결승 쪽 안전한 타협안


## 엔지니어 등급: S ≥0.9 · A ≥0.65 · B ≥0.4 · C ≥0.2 · D. 세부 셋업 추천이 정답을 벗어날 확률 (S·A 0 · B 10% · C 25% · D 40%)
func eng_grade() -> String:
	return "S" if eng_q >= 0.9 else ("A" if eng_q >= 0.65 else ("B" if eng_q >= 0.4 else ("C" if eng_q >= 0.2 else "D")))


const ENG_MISS := {"S": 0.0, "A": 0.0, "B": 0.10, "C": 0.25, "D": 0.40}


## 엔지니어 실력이 좋을수록 좁고 정확한 범위. 정답은 범위 안 어딘가 (가운데가 정답은 아님).
## 세부 셋업(서스펜션·브레이크·디퍼렌셜)은 엔지니어마다 치우침(팀별 고정)이 있고, 낮은 등급은 범위 밖을 가리킬 수 있다(wrong).
## nz = 득실 막대 숫자 오차 (엔지니어 계산이 정확하지 않음)
func _make_band(c) -> Dictionary:
	var b := {}
	for key in ["wing", "susp", "bbias", "diff", "psi"]:
		var r: Array = _span(key)
		var span: float = float(r[1]) - float(r[0])
		var hw: float = (0.08 + 0.22 * (1.0 - eng_q)) * span
		var ctr: float = _opt(c, key) + sim.uni(-0.6, 0.6) * hw
		var bd := {"c": ctr, "hw": hw}
		if RS.SETUP_RANGE.has(key):
			# shortcut: 치우침은 팀 이름으로 고정 (커리어 수석 엔지니어가 바뀌어도 같음) — 엔지니어 이름이 주말에 넘어오면 그걸로
			var lean: float = (sim._h01(c.team + "|eng|" + key) - 0.5) * hw
			bd["c"] = _opt(c, key) + clampf(sim.uni(-0.5, 0.5) * hw + lean, -0.8 * hw, 0.8 * hw)
			if sim.rnd() < float(ENG_MISS[eng_grade()]):
				bd["c"] = _opt(c, key) + (1.0 if sim.rnd() < 0.5 else -1.0) * hw * sim.uni(1.15, 1.5)
				bd["wrong"] = true
			bd["nz"] = sim.gauss(0.08 + 0.45 * (1.0 - eng_q))
			bd["laps"] = 0
		b[key] = bd
	return b


## 화면용 세부 셋업 득실 (엔지니어 계산 — 등급만큼 오차): {ch: [[이름, 초]…], tot: 엔지니어가 보는 합계, wear: %, grade}
func setup_view(slot: int, key: String) -> Dictionary:
	var c = my_cars()[slot]
	var bd: Dictionary = bands[slot][key]
	var v: Dictionary = sim.setup_channels(c, key)
	var k: float = 1.0 + float(bd.get("nz", 0.0))
	var chs: Array = []
	for ch in v["ch"]:
		chs.append([ch[0], float(ch[1]) * k])
	# 합계는 엔지니어가 생각하는 최적(추천 띠 가운데) 기준 → 엔지니어가 틀리면 합계도 틀린다
	var x: float = RS.setup_x(key, float(c.get(key)))
	var xc: float = RS.setup_x(key, float(bd["c"]))
	var q: float = RS.SETUP_Q
	var tot: float = (minf(RS.SETUP_K * 1.5, q * (x - xc) * (x - xc)) - minf(RS.SETUP_K * 1.5, q * xc * xc)) * sim.wsc()
	return {"ch": chs, "tot": tot, "wear": float(v["wear"]), "grade": eng_grade()}


func band_lohi(slot: int, key: String) -> Array:
	var bd: Dictionary = bands[slot][key]
	var r: Array = _span(key)
	return [maxf(float(r[0]), float(bd["c"]) - float(bd["hw"])), minf(float(r[1]), float(bd["c"]) + float(bd["hw"]))]


## 테스트 주행 데이터가 쌓이면 범위가 좁아지고 정답 쪽으로 다가간다.
## 숏런(한 랩 느낌) = 윙·공기압이 빨리, 롱런(타이어가 어떻게 닳나) = 세부 셋업(마모 대가)이 빨리 좁혀진다
const ONE_LAP_KEYS := ["wing", "psi"]


func _refine_band(slot: int, laps_run: int, kind: String = "short") -> void:
	var c = my_cars()[slot]
	for key in bands[slot]:
		var fast: bool = ONE_LAP_KEYS.has(key) == (kind != "long")
		var k: float = pow(0.9 if fast else 0.95, laps_run / 3.0)
		var bd: Dictionary = bands[slot][key]
		var r: Array = _span(key)
		var span: float = float(r[1]) - float(r[0])
		var o := _opt(c, key)
		bd["hw"] = maxf(0.03 * span, float(bd["hw"]) * k)
		bd["c"] = o + (float(bd["c"]) - o) * k
		if bd.has("nz"):
			bd["nz"] = float(bd["nz"]) * k
			bd["laps"] = int(bd["laps"]) + laps_run
			if bd.get("wrong", false) and int(bd["laps"]) >= 6: # 테스트를 충분히 달리면 틀린 추천도 바로잡힌다
				bd["wrong"] = false
		# 범위가 정답을 벗어나지 않게 (틀린 엔지니어는 테스트 6랩 전까지 그대로)
		if not bd.get("wrong", false) and absf(float(bd["c"]) - o) > float(bd["hw"]) * 0.8:
			bd["c"] = o + signf(float(bd["c"]) - o) * float(bd["hw"]) * 0.8


## 엔지니어에게 맡기기: 추천 범위 한가운데로
func engineer_apply(slot: int) -> void:
	set_psi(slot, float(bands[slot]["psi"]["c"]))
	for key in ["wing", "susp", "bbias", "diff"]:
		var v: float = float(bands[slot][key]["c"])
		if key == "wing":
			set_wing(slot, v)
		else:
			set_detail(slot, key, v)


# ═════════ 타이어 마모 추정 (연습 롱런으로 오차가 줄어든다) ═════════
## 모를 땐 '보통 타이어'(배율 1.0)로 보고, 그 컴파운드로 롱런할 때마다 실제 배율 쪽으로 다가가며 오차가 절반.
## 실제 배율은 0.88~1.14 라 늘 범위 안. 이 추정이 결승 전략 계획(sim.plan_mult → my_rates)에 그대로 쓰인다.
const WEAR_ERR0 := 0.35


func wear_err(comp: String) -> float:
	return float(wear_est["err"].get(comp, WEAR_ERR0))


func est_mult(comp: String) -> float:
	var know: float = 1.0 - wear_err(comp) / WEAR_ERR0
	return lerpf(1.0, float(sim.true_mult.get(comp, 1.0)), know)


func est_wear_rate(comp: String) -> float:
	return maxf(0.010, float(RS.COMP[comp][1]) * est_mult(comp) * float(sim.rules.get("wear_mult", 1.0)))


func est_range_text(comp: String) -> String:
	var est := est_wear_rate(comp)
	var err: float = wear_err(comp)
	var lo := maxf(0.008, est * (1.0 - err))
	var hi := est * (1.0 + err)
	# 화면에는 '한 바퀴 마모 %' 로 보여준다 (서킷 마모·레이스 길이 반영)
	var k: float = float(sim.CIRC["wear"]) * (RS.WEC_WEAR if sim.is_wec() else RS.WEAR_SCALE / sim.laps) * 100.0
	return "%.1f~%.1f%%/랩" % [lo * k, hi * k]


func feedback(c, kind: String = "q") -> String:
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
	var pu: float = sim.press_u(c, kind)
	if pu >= 0.9:
		b = "타이어가 딱딱하게 튀고 금방 뜨거워져요, 공기압이 너무 높아요"
	elif pu >= 0.4:
		b = "타이어가 조금 튀고 뒤로 갈수록 뜨거워져요"
	elif pu <= -0.9:
		b = "타이어가 잘 안 데워지고 미끄러워요, 공기압이 너무 낮아요"
	elif pu <= -0.4:
		b = "타이어 데워지는 게 조금 느리고 살짝 미끄러워요"
	var tip: String = sim.setup_tip(c, kind)
	return a + (". " + b if b != "" else "") + (". " + tip if tip != "" else "")


# ═════════ 연습 주행 ═════════
## kind: "short"(셋업 테스트 3랩) / "long"(롱런 5랩, 마모 추정 오차 절반)
## 세트 꺼내기. 연습은 쓴 세트를 먼저(없으면 새 세트를 하나 연다), 예선은 새 세트를 먼저.
## 돌려주는 값: "new" / "used" / "" (그 컴파운드는 남은 세트가 없음)
func take_set(slot: int, comp: String, prefer_new: bool) -> String:
	return take_set_mode(slot, comp, "auto_new" if prefer_new else "auto_used")


## 세트 꺼내기. mode: new(새 것만) / used(쓴 것만) / auto_new(새 것 먼저) / auto_used(쓴 것 먼저)
## 쓴 세트는 idx(used_sets 안 번호)로 직접 고를 수 있고, 아니면 가장 덜 쓴 것. 꺼낸 세트는 last_set.
## 돌려주는 값: "new" / "used" / "" (없음)
func take_set_mode(slot: int, comp: String, mode: String, idx: int = -1) -> String:
	var nw: Dictionary = sets[slot]
	var us: Dictionary = used_sets[slot]
	last_set = null
	if not nw.has(comp):
		return "new" # 인터·웻은 할당 밖
	var arr: Array = us[comp]
	var can_new: bool = int(nw[comp]) > 0
	var can_used: bool = not arr.is_empty()
	var pick := ""
	match mode:
		"new":
			pick = "new" if can_new else ""
		"used":
			pick = "used" if can_used else ""
		"auto_used":
			pick = "used" if can_used else ("new" if can_new else "")
		_:
			pick = "new" if can_new else ("used" if can_used else "")
	if pick == "new":
		nw[comp] = int(nw[comp]) - 1
		last_set = {"w": 0.0, "h": 0}
		arr.append(last_set)
	elif pick == "used":
		last_set = arr[idx] if (idx >= 0 and idx < arr.size()) else arr[RS.least_worn(arr)]
	return pick


## 쓴 세트 개수
func used_n(slot: int, comp: String) -> int:
	return (used_sets[slot].get(comp, []) as Array).size()


## 고를 수 있는지 (화면 버튼용): mode = new / used
func can_take(slot: int, comp: String, mode: String) -> bool:
	if mode == "new":
		return int(sets[slot].get(comp, 0)) > 0
	if mode == "used":
		return used_n(slot, comp) > 0
	return has_any(slot, comp)


func has_any(slot: int, comp: String) -> bool:
	return int(sets[slot].get(comp, 0)) > 0 or used_n(slot, comp) > 0


func practice_run(slot: int, kind: String, comp: String = "M", set_mode: String = "auto", idx: int = -1) -> Dictionary:
	var c = my_cars()[slot]
	var n := 5 if kind == "long" else 3
	if practice_left[slot] < n:
		return {}
	if sim.is_wec():
		comp = sim.wec_fit_comp(c.cls, comp)
	if take_set_mode(slot, comp, "auto_used" if set_mode == "auto" else set_mode, idx) == "":
		return {}
	var fuel: float = STINT * RS.FPL if kind == "long" else RS.FPL * 2.0
	var run := _run_laps(c, kind, comp, fuel, n, func(): return sim.gauss(0.25))
	var res: Array = run["laps"]
	var st: Variant = last_set
	if st != null:
		st["w"] = float(st["w"]) + sim.set_lap_wear(comp, float(run["wmult"])) * n # 이 런이 세트에 남긴 마모 (결승 랩 단위)
		st["h"] = int(st["h"]) + 1
	var best: float = res.min()
	var tot := 0.0
	for x in res:
		tot += x
	practice_left[slot] -= n
	_refine_band(slot, n, kind)
	if kind == "long":
		wear_est["runs"][comp] = int(wear_est["runs"].get(comp, 0)) + 1
		wear_est["err"][comp] = snappedf(wear_err(comp) * 0.5, 0.001)
		sim.plan_mult[comp] = est_mult(comp) # 결승 전략 계획이 이 추정을 쓴다
	var wr: float = float(run["wr"])
	var r := {"code": c.code, "comp": comp, "laps": res, "best": best, "avg": tot / n, "fc_avg": (tot - float(run["fuel_t"])) / n, "q_est": best + q_equiv(comp, float(run["fuel_t"]) / n), "wear_lap": (wr * 100.0) if sim.is_wec() else (wr * 15.0 / sim.laps * 100.0), "kind": kind, "wing": c.wing, "psi": c.psi, "detail": "S%.1f B%.1f D%d" % [c.susp, c.bbias, int(c.diff)]}
	practice_runs.push_front(r)
	var fb := "%s: %s" % [c.name, feedback(c, "race" if kind == "long" else "q")]
	if kind == "long":
		fb += " (%s 마모 추정 오차 ±%d%%로 축소 · 연료 보정 평균 %s)" % [RS.TYRE_KO[comp], int(round(wear_err(comp) * 100.0)), _fmt(float(r["fc_avg"]))]
	else:
		fb += " (예선 환산 %s)" % _fmt(float(r["q_est"]))
	last_feedback[slot] = fb
	setup_dirty[slot] = false
	var ran := 0
	for pr in practice_runs:
		if pr["code"] == c.code:
			ran += (pr["laps"] as Array).size()
	fb_lap[slot] = ran
	return r


## 연습 런 랩타임 (내 차·AI 공용). noise = 랩마다 더할 잡음 함수.
## 돌려주는 값: laps(초 배열) · wr(랩당 마모) · wmult(마모 배율) · fuel_t(연료 무게로 잃은 초 합계 — 연료 보정용)
func _run_laps(c, kind: String, comp: String, fuel: float, n: int, noise: Callable) -> Dictionary:
	var rk: String = "race" if kind == "long" else "q" # 롱런 = 결승처럼 많이 오름, 테스트 = 예선처럼 조금
	var CIRC: Dictionary = sim.CIRC
	var ws: float = sim.wsc()
	var pu: float = sim.press_u(c, rk)
	var pf: Array = RS.press_fx(pu)
	var sx: Dictionary = sim.setup_extra(c, rk)
	var wmult: float = float(pf[1]) * (1.0 - (c.wing - 3.0) * 0.04) * c.tyre_deg_rate * float(sx["wear"])
	var wr: float = sim.true_wear_rate(comp) * float(CIRC["wear"]) * (RS.WEC_WEAR if sim.is_wec() else RS.WEAR_SCALE / 15.0) * wmult
	var base: float = float(CIRC["base"]) * sim.car_factor(c) * (1.0 - c.speed * float(RS.K["drv_k"])) + sim.setup_pen(c, 0.0) + float(pf[0]) + sim.press_straight(pu) + float(sx["dt"])
	var wear := 0.0
	var fuel_t := 0.0
	var res: Array = []
	for i in n:
		var ft: float = fuel * sim.fuel_k() * ws
		var t: float = base + (wear * wear * float(RS.COMP[comp][2]) + sim.cliff_pen(comp, wear)) * ws + ft + float(noise.call())
		if pu > 0.0 and wear > 0.5:
			t += 0.3 * pu # 공기압이 높으면 런 후반 과열
		res.append(t)
		fuel_t += ft
		wear += wr
		fuel -= RS.FPL
	return {"laps": res, "wr": wr, "wmult": wmult, "fuel_t": fuel_t}


## 숏런 최고 랩 → 예선 환산: 연료 빼고, 가장 무른 컴파운드로 바꾼 만큼 (예선 랩과 같은 QCOMP)
func q_equiv(comp: String, fuel_lap: float) -> float:
	var ws: float = sim.wsc()
	var soft: String = "S"
	for k in ["S", "M", "H"]:
		if sim.is_wec() and not sim.wec_comps(main_cls()).has(k):
			continue
		soft = k
		break
	return (float(QCOMP[soft]) - float(QCOMP.get(comp, 0.0))) * ws - fuel_lap


## 다른 팀 연습 기록 (금요일 데이터): AI 도 숏런(가장 무른 타이어)·롱런(가운데 타이어)을 달린다.
## 연료를 얼마나 실었는지는 모른다 — 팀마다 다르고, 일부 팀은 숏런에도 연료를 많이 싣는다(샌드배깅).
## 레이스 난수와 따로 (별도 rng) → 이 표 때문에 결승 결과가 바뀌지 않는다
func _make_rivals() -> void:
	rivals = []
	var r := RandomNumberGenerator.new()
	r.seed = hash("%s|%d" % [sim.circ_key, sim.rng.seed])
	var noise := func(): return r.randfn(0.0, 0.25)
	for c in sim.cars:
		if c.mine:
			continue
		var comps: Array = sim.wec_comps(c.cls) if sim.is_wec() else dry_comps(c)
		if comps.is_empty():
			continue
		var sc: String = comps[0]
		var lc: String = comps[comps.size() / 2]
		var bag: bool = absi(hash(c.team)) % 4 == 0 # 샌드배깅 팀: 숏런에도 연료를 넉넉히
		var sf: float = RS.FPL * (r.randf_range(4.0, 8.0) if bag else r.randf_range(1.0, 3.0))
		var lf: float = STINT * RS.FPL * r.randf_range(0.7, 1.8)
		var s: Array = _run_laps(c, "short", sc, sf, 3, noise)["laps"]
		var l: Array = _run_laps(c, "long", lc, lf, 5, noise)["laps"]
		var lt := 0.0
		for x in l:
			lt += x
		rivals.append({"id": c.id, "code": c.code, "team": c.team, "cls": c.cls, "s_best": s.min(), "s_comp": sc, "l_avg": lt / l.size(), "l_comp": lc})


## 연습 기록표: 내 차(가장 빠른 숏런·롱런)를 넣어 클래스 안에서 순위. kind = "s" / "l"
## 돌려주는 값: [{code, t, comp, mine}] 빠른 순
func practice_table(kind: String) -> Array:
	var cls: String = main_cls()
	var out: Array = []
	for x in rivals:
		if x["cls"] == cls:
			out.append({"code": x["code"], "t": float(x[kind + "_best" if kind == "s" else kind + "_avg"]), "comp": x[kind + "_comp"], "mine": false})
	var mine := {}
	for pr in practice_runs:
		if (kind == "s") != (pr["kind"] == "short"):
			continue
		var t: float = float(pr["best"] if kind == "s" else pr["avg"])
		if not mine.has(pr["code"]) or t < float(mine[pr["code"]]["t"]):
			mine[pr["code"]] = {"code": pr["code"], "t": t, "comp": pr["comp"], "mine": true}
	out.append_array(mine.values())
	out.sort_custom(func(a, b): return float(a["t"]) < float(b["t"]))
	return out


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
	Q = {"res": {}, "stage": 1, "max_stage": 2 if sim.is_wec() else (1 if single_quali() else 3), "eliminated": {}, "done": false, "auto": false, "ver": 0, "reds": 0}
	BLog.add("예선 시작 · %s" % _q_snapshot())
	_q_soft_used.clear()
	for c in my_cars():
		c.q3_locked = false
	_start_stage(1)


## 세션 길이(분)
func q_len(stage: int = -1) -> float:
	var st: int = int(Q.get("stage", 1)) if stage < 0 else stage
	if single_quali():
		return QLEN_SINGLE * maxf(1.0, lap_min() / 1.7)
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


## 쓴 세트 예선 손해: 런 한 번 쓴 세트 = 0.45초(예전 고정값), 더 많이 쓸수록 커짐 (최대 1초)
func q_used_pen(comp: String, set_w: float) -> float:
	var ref: float = maxf(0.001, sim.set_lap_wear(comp) * Q_RUN_LAPS)
	return minf(1.0, 0.25 + 0.20 * set_w / ref)


func q_lap(c, push: String, traffic: Variant, stage: int, comp: String, used_set: bool, set_w: float = -1.0) -> Dictionary:
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
	var used_pen: float = (q_used_pen(comp, set_w) if set_w >= 0.0 else 0.45) * ws if used_set else 0.0
	var note := ("쓴 타이어 어택 (약 +%.2fs)" % used_pen) if used_set else ""
	var deleted := false
	var secs: Array = []
	var pu: float = sim.press_u(c, "q")
	var pf: Array = RS.press_fx(pu)
	var CIRC: Dictionary = sim.CIRC
	for s in NS:
		var sh: float = sim.T.share[s]
		var t: float = float(CIRC["base"]) * sh * sim.car_factor(c) * (1.0 - c.speed * float(RS.K["drv_k"]) * spd)
		t += (comp_delta + used_pen + sim.setup_pen(c, 0.0) + float(pf[0]) + sim.press_straight(pu) + float(sim.setup_extra(c, "q")["dt"]) + evo_bonus + stage_evo) * sh + 5.0 * 0.03 * sh
		t += sim.gauss(0.10 * sqrt(sh) * sqrt(ws))
		if sim.rnd() < trf_risk * sh * 1.6:
			var loss: float = sim.uni(0.22, 0.68)
			t += loss
			note = "섹터 %d 트래픽 +%.2fs" % [s + 1, loss]
		if sim.rnd() < 0.012 * err * sim.press_kerb(pu) * (1.25 - c.cons) * (1.0 + absf(c.wing - float(CIRC["wingOpt"])) * 0.3):
			t += sim.uni(0.3, 1.5)
			note = "실수로 시간 손실"
		if sim.rnd() < lim * (1.2 - c.cons) * sim.press_kerb(pu):
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
	var ins := 0
	for c in sim.cars:
		if _participant(c, st):
			ins += 1
	for c in my_cars():
		if st == 1 and not _participant(c, st):
			BLog.warn("예선 Q1 시작부터 내 차 %s 가 탈락 상태 · %s" % [c.code, _q_snapshot()])
	if ins == 0:
		BLog.warn("예선 Q%d 참가 차 0대 · %s" % [st, _q_snapshot()])
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
	if single_quali():
		_log("예선 시작 · %d분 단일 세션 (탈락 없음)" % int(q_len(st)))
	else:
		_log("Q%d 시작 · %d분" % [st, int(q_len(st))] if not sim.is_wec() else ("%s 시작 · %d분" % ["예선" if st == 1 else "하이퍼폴", int(q_len(st))]))


## AI 출발 계획: 55%는 초반에 기록을 하나 만들어 두고(뱅커), 모두 막판에 한 번 더
func _ai_plan(c, st: int) -> Array:
	var T: float = q_len(st)
	var plan: Array = []
	if c.mine:
		plan.append(sim.uni(T - out_min() - 3.4, T - out_min() - 0.5))
		return plan
	if single_quali():
		# 30분 단일 세션: 초반 기록 하나 + 막판 어택 (일부는 중간에 한 번 더), 출발 시각을 넓게 흩어 트래픽 분산
		plan.append(sim.uni(T * 0.08, T * 0.40))
		if sim.rnd() < 0.4:
			plan.append(sim.uni(T * 0.45, T * 0.65))
		plan.append(sim.uni(T - out_min() - 6.0, T - out_min() - 0.3))
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
	if sim.is_wec():
		# 2026 실제: 하이퍼폴도 대회 허용 컴파운드 안에서 자유 — 대부분 가장 무른 것, 일부 팀(약 15%)은 미디엄으로 (르망: 페라리)
		var wc: String = sim.wec_fit_comp(c.cls, "S")
		var key: Variant = c.id
		if st >= 2:
			key = "hp%d" % c.id
			if not _q_soft_used.has("pick%d" % c.id):
				_q_soft_used["pick%d" % c.id] = sim.wec_fit_comp(c.cls, "M") if sim.rnd() < 0.15 else wc
			wc = _q_soft_used["pick%d" % c.id]
		var used_n: int = _q_soft_used.get(key, 0)
		var wu: bool = used_n >= 1
		_q_soft_used[key] = used_n + 1
		return [wc, wu]
	# F1·F2·F3: 내 차와 같은 주말 할당에서 꺼낸다. 가장 무른 컴파운드로 어택, 새 세트가 없으면 쓴 세트
	var a: Dictionary = _ai_sets.get(c.id, {"new": {"S": 9, "M": 9, "H": 9}, "used": {"S": [], "M": [], "H": []}})
	var nw: Dictionary = a["new"]
	var us: Dictionary = a["used"]
	var order: Array = ["S", "M", "H"]
	# F1 Q1 뱅커: 빠른 차는 미디엄 (원작 그대로)
	if fmt() == "f1" and st == 1 and plan_left > 0 and c.speed > 0.80:
		order = ["M", "S", "H"]
	# 첫 기록용(뱅커) 어택은 쓴 세트로 아끼고 마지막 어택에 새 세트 (새 세트가 남으면)
	var save_new: bool = plan_left > 0
	for k in order:
		var ua: Array = us.get(k, [])
		var hn: bool = int(nw.get(k, 0)) > 0
		var hu: bool = not ua.is_empty()
		if not hn and not hu:
			continue
		if hn and not (save_new and hu and int(nw[k]) <= 1):
			nw[k] = int(nw[k]) - 1
			var ns := {"w": 0.0, "h": 0}
			ua.append(ns)
			us[k] = ua
			return [k, false, ns]
		return [k, true, ua[RS.least_worn(ua)]] # AI 도 가장 덜 쓴 세트 (원칙 9)
	return ["M", true, null]


func _depart(c, comp: String, push: String, used: bool, st: Variant = null) -> void:
	# 손해는 나가기 전 마모로 계산하고, 이 런의 마모(아웃랩·어택·인랩)는 바로 세트에 쌓는다
	var w0: float = float(st["w"]) if st != null else -1.0
	if st != null:
		st["w"] = w0 + sim.set_lap_wear(comp) * Q_RUN_LAPS
		st["h"] = int(st["h"]) + 1
	Q["run"][c.id] = {"phase": "out", "t0": float(Q["t"]), "dur": out_min(), "d0": 0.0, "comp": comp, "push": push, "used": used, "res": null, "set": st, "w0": w0}
	if c.mine:
		Q["ver"] = int(Q["ver"]) + 1


## 내 차 출발. 실패하면 이유 문자열, 성공하면 ""
func player_depart(slot: int, comp: String, push: String, set_mode: String = "auto", idx: int = -1) -> String:
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
	var got: String = take_set_mode(slot, comp, "auto_new" if set_mode == "auto" else set_mode, idx)
	if got == "":
		return "%s %s 세트가 없어요" % [RS.TYRE_KO[comp], "새" if set_mode == "new" else "쓴"]
	_depart(c, comp, push, got != "new", last_set)
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
			_depart(c, cu[0], push, cu[1], cu[2] if cu.size() > 2 else null)
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
				var res: Dictionary = q_lap(c, r["push"], cond, Q["stage"], r["comp"], r["used"], float(r.get("w0", -1.0)))
				res["t_start"] = t
				if r.get("set") != null:
					res["set"] = r["set"] # Q3 고정 출발: 이 세트로 결승 출발
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
	var nxt := 0
	for c in sim.cars:
		if _participant(c, st + 1):
			nxt += 1
	if nxt == 0 or nxt > cut:
		BLog.warn("예선 Q%d 뒤 다음 세션 진출 %d대 (정상 1~%d) · %s" % [st, nxt, cut, _q_snapshot()])
	else:
		BLog.add("Q%d 종료 · 진출 %d대 · 내 차 %s" % [st, nxt, ", ".join(PackedStringArray(my_cars().map(func(x): return "%s %s" % [x.code, "진출" if _participant(x, st + 1) else "탈락"])))])
	_log("Q%d 종료 · 탈락: %s" % [st, ", ".join(out_names)])
	Q["ver"] = int(Q["ver"]) + 1


## 버그 기록용 예선 상태 한 줄: 서킷·형식·세션·내 클래스·클래스별 대수·탈락 수
func _q_snapshot() -> String:
	var cls := {}
	for c in sim.cars:
		cls[c.cls] = int(cls.get(c.cls, 0)) + 1
	var my: PackedStringArray = []
	for c in my_cars():
		my.append("%s(%s)" % [c.code, c.cls])
	return "%s · 형식 %s · Q%d/%d · 내 클래스 %s · 클래스별 %s · 탈락 %d대 · 내 차 %s" % [sim.CIRC.get("name", "?"), fmt(), int(Q.get("stage", 0)), int(Q.get("max_stage", 0)), main_cls(), str(cls), Q.get("eliminated", {}).size(), ", ".join(my)]


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
	for c in my_cars():
		set_psi(c.slot, c.psi + sim.psi_rec("race") - sim.psi_rec("q"))
	var ord: Array = q_order()
	sim.cars = ord
	for i in ord.size():
		var c = ord[i]
		c.grid = i
		var r: Variant = Q["res"].get(c.id)
		# 파크 페르메: 최종 세션(Q3) 진출 차는 최고 기록을 낸 그 세트로 출발 (세트 마모 그대로 + 열 사이클)
		if r != null and r["stage"] == Q["max_stage"] and not sim.is_wec() and not single_quali(): # WEC 는 결승을 새 타이어로 출발, F2·F3 는 출발 타이어 자유
			c.comp = r["q_comp"]
			c.used = {c.comp: true}
			c.q3_locked = true
			if r.get("set") != null:
				c.wear = 0.0
				sim.fit_used(c, r["set"])
			else:
				c.used_set_pen = 0.45 if r["used"] else 0.0 # shortcut: 세트 정보 없는 예선(WEC AI 등) 옛 값, WEC 세트 기록 때 같이
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


## 결승 출발: Q3 고정이 아닌 내 차는 출발 타이어도 주말 할당에서 꺼낸다 (새 세트가 없으면 가장 덜 쓴 세트 — 그 마모에서 출발)
func commit_start_tyres() -> void:
	if sim.is_wec():
		return
	sim.start_tyres_taken = true
	for c in my_cars():
		if c.q3_locked or not RS.SLICK.has(c.comp):
			continue
		var pref: String = String(start_pref[c.slot]) if c.slot < start_pref.size() else "auto"
		var got: String = take_set_mode(c.slot, c.comp, "auto_new" if pref == "auto" else pref, int(start_idx[c.slot]) if c.slot < start_idx.size() else -1)
		if got == "" and pref != "auto":
			got = take_set_mode(c.slot, c.comp, "auto_new")
		if got == "used":
			sim.fit_used(c, last_set)
		else:
			c.used_set_pen = 0.0


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
