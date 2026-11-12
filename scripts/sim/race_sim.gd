extends RefCounted
## F1 레이스 시뮬레이션 코어. 화면과 완전히 분리되어 있어 헤드리스 테스트로도 돌릴 수 있다.
## 원본 HTML 버전(v16.1)의 계산식을 그대로 옮겼다 — 밸런스 검증 결과를 유지하기 위해서.
##
## 시간 모델: 차는 섹터(한 바퀴 6개) 단위로 움직인다. 섹터 진입 시 그 섹터의 소요 시간을 계산해
## sec_end에 예약하고, advance()가 가장 먼저 끝나는 차부터 순서대로 처리한다(이벤트 큐 방식).

const CarS = preload("res://scripts/sim/car.gd")
const DB = preload("res://scripts/data/game_db.gd")

const NS := 6
const FPL := 1.6
const WEAR_SCALE := 60.0
const H_CLIFF := 0.62
const SPEED_BASE := 4.0 # 화면 1× = 시뮬레이션 4배속

const COMP := {"S": [-1.05, 0.048, 4.0], "M": [0.0, 0.032, 3.3], "H": [0.50, 0.027, 2.6], "I": [0.0, 0.038, 3.3], "W": [0.0, 0.032, 3.1]}
const SLICK := {"S": true, "M": true, "H": true}
const TYRE_KO := {"S": "소프트", "M": "미디엄", "H": "하드", "I": "인터", "W": "웻"}
const TYRE_HEX := {"S": "#ef4444", "M": "#facc15", "H": "#f1f5f9", "I": "#22c55e", "W": "#3b82f6"}
const PACE := {"attack": [1.2, 1.35, 1.6, 0.78], "standard": [1.0, 1.0, 1.0, 0.62], "save": [0.7, 0.75, 0.6, 0.52]}
const PACE_KO := {"attack": "공격", "standard": "표준", "save": "세이브"}
const ERS := {"harvest": [0.40, 0.30], "balance": [0.0, 0.02], "deploy": [-0.60, -0.35]}
const ERS_KO := {"harvest": "충전", "balance": "밸런스", "deploy": "오버테이크"}
const FUEL := {"lean": [0.50, 0.90], "std": [0.0, 1.0], "rich": [-0.25, 1.08]}
const PRESS := {"low": [-0.15, 1.12, 0.05], "std": [0.0, 1.0, 0.0], "high": [0.15, 0.88, -0.05]}
const PRESS_FX := {
	"low": {"straight": 0.10, "warm": 1.5, "heat": 1.35, "kerb": 0.82},
	"std": {"straight": 0.0, "warm": 1.0, "heat": 1.0, "kerb": 1.0},
	"high": {"straight": -0.12, "warm": 0.65, "heat": 0.72, "kerb": 1.28},
}
const K := {"car_scale": 0.92, "drv_k": 0.022, "noise": 0.28, "fail": 0.0045, "crash": 0.005, "overtake_scale": 0.21, "victim": 0.25, "dirty": 1.0, "ot_gap": 0.3}
const POINTS := [25, 18, 15, 12, 10, 8, 6, 4, 2, 1]
# WEC 규칙 (HTML 원본과 동일)
const STINT := 5                 # 스틴트 5랩 (연료 세이브면 6랩)
const TANK := 5.45 * 1.6         # 연료 탱크 = 5.45랩 분량
const GT3_PACE := 1.12
const CLASS_PACE := {"HY": 1.0, "P2": 1.06, "GT": 1.12} # 클래스 기본 페이스 배율 (LMP2는 하이퍼카와 GT3 사이)
const GRADE_KO := {"P": "플래티넘", "G": "골드", "S": "실버", "B": "브론즈"}
const BOP_K := 0.006
const WEC_WEAR := 1.9            # 미디엄 1스틴트 ≈ 32%, 더블 스틴트 끝 ≈ 63% (2026 세트 제한 → 더블 스틴트가 기본)
## WEC 2026 타이어 규정: 레이스용 새 드라이 세트 = 스틴트 수 × 비율 (출발 세트 포함). LMGT3 는 추가 타이어를 받아 조금 더 많다
const WEC_SET_RATIO := {"HY": 0.6, "P2": 0.6, "GT": 0.75}
const WEC_COLD_TT := {"S": 0.30, "M": 0.24, "H": 0.17, "I": 0.30, "W": 0.32} # 워머 금지: 피트 직후 타이어 온도
const WPIT := {"lane": 30.0, "fuel": 30.0, "tyres": 12.0, "driver": 3.0}
const WEC_FUEL_KO := {"lean": "세이브", "std": "표준", "rich": "리치"}
const STRAT_STYLES := ["aggressive", "balanced", "conservative", "reactive"]
const STRAT_KO := {"aggressive": "공격형", "balanced": "균형형", "conservative": "보수형", "reactive": "반응형"}

var rng := RandomNumberGenerator.new()
var T: Variant            # 트랙 (track.gd)
var CIRC: Dictionary = {}
var circ_key := ""
var series := "f1"
var min_drive: Variant = null
## 시리즈 규칙: two_compounds(드라이 레이스 두 컴파운드 의무) · wear_mult(타이어 마모 배율, F3·스프린트는 작게)
var rules := {"two_compounds": true, "wear_mult": 1.0} # 하위 클래스 최소 주행 규정 {grade, pct} (예: 브론즈 25%)
var laps := 15
var my_team := -1
var cars: Array = []
## 난이도: 0 쉬움 · 1 보통(원작 밸런스) · 2 어려움 · 3 전설. AI 차 랩타임 배율.
const DIFF_PACE := [1.0065, 1.0, 0.994, 0.99]
const DIFF_STRAT := [-0.12, 0.0, 0.05, 0.09]
const DIFF_KO := ["쉬움", "보통", "어려움", "전설"]
var difficulty: int = 1
var true_mult: Dictionary = {"S": 1.0, "M": 1.0, "H": 1.0}

# 레이스 상태
var clock := 0.0
var wet := 0.0
var track_evo := 0.15
var rain: Variant = null # {start, end, level}
var fc: Variant = null   # 예보 {lo, hi, p}
var sc := false
var sc_kind := ""
var sc_end_lap := 0
var sc_dist := -1.0
var sc_wait := false       # SC가 피트 출구에서 나와 선두를 기다리는 중
var yellow := {}           # 국지 옐로: 섹터 번호 → 해제 시각(clock)
var sc_in_notified := false
var sc_in_pit_lane := false
var sc_pit_prog := 0.0
var restart := false
var leader_lap := 0
var fastest_t := INF
var fastest_id := -1
var done := false
var finishing := false
var ever_wet := false
var night := false
var n_stalls := 11
var radio_log: Array = [] # {lap, who, color, msg, kind}
var team_order := "free"   # 팀 오더: free 자유 경쟁 / hold 순서 유지
var swap_req := false      # 팀 오더: 다음 기회에 앞 팀메이트가 양보
var active_radio: Variant = null  # 엔지니어 제안 {slot, title, msg, opts:[{label, act, comp}]}
var radio_seq := 0         # 새 제안이 뜰 때마다 +1 (UI가 감속·표시에 사용)
var sc_laps: Array = []    # SC·VSC·FCY 가 걸린 선두 랩 (복기 차트용)
var team_split := {}       # 팀 → 첫 차의 계획 스톱 수 (두 번째 차는 다른 전략으로 나누기도)
var tally := {}            # 레이스 중 AI 전술·실수 횟수 (테스트·밸런스 확인용)
var iradio_done := {}      # "차id:종류" → true (같은 제안은 한 번만)
var prompts_enabled := true  # 설정에서 끄면 엔지니어 제안 창을 띄우지 않음

var _cuts_cache: Dictionary = {}


func is_wec() -> bool:
	return series == "wec"


## WEC 는 랩이 길어서(르망 207초) 초 단위 페널티를 서킷 길이에 비례시킨다
func wsc() -> float:
	return float(CIRC["base"]) / 90.0 if is_wec() else 1.0


## WEC 타이어 규정: 하이퍼카는 대회마다 드라이 2종(르망 3종), LMGT3·LMP2 는 미디엄 한 종류
func wec_comps(cls: String) -> Array:
	if cls != "HY":
		return ["M"]
	return CIRC.get("wecComps", ["S", "M", "H"])


## 규정에 없는 컴파운드를 고르면 가장 가까운 허용 컴파운드로
func wec_fit_comp(cls: String, want: String) -> String:
	if not SLICK.has(want):
		return want
	var al: Array = wec_comps(cls)
	if al.has(want):
		return want
	var order := ["S", "M", "H"]
	var best: String = al[0]
	for a in al:
		if absi(order.find(a) - order.find(want)) < absi(order.find(best) - order.find(want)):
			best = a
	return best


## 레이스 동안 쓸 수 있는 새 드라이 세트 수 (출발 세트 제외)
func wec_race_sets(cls: String) -> int:
	var stints: int = int(ceil(float(laps) / STINT))
	return maxi(1, int(ceil(stints * float(WEC_SET_RATIO.get(cls, 0.6))))) - 1


## WEC 드라이버 주행 시간 규정 (르망 규정 기준, 레이스 길이에 비례):
## 어떤 6시간 구간에서도 4시간 초과 금지 · 르망은 한 명 최대 14시간·최소 6시간. 랩 수로 바꿔 쓴다
func wec_hours() -> float:
	return float(CIRC.get("wecHours", 6.0))


func drive_limits() -> Dictionary:
	var h: float = wec_hours()
	var win: int = maxi(1, int(round(laps * minf(1.0, 6.0 / h))))
	# 압축된 레이스에서도 연비 주행 한 스틴트(최대 약 STINT+2랩)는 한 명이 탈 수 있게
	var max_win: int = maxi(STINT + 2, int(floor(laps * minf(1.0, 4.0 / h))))
	var max_total: int = maxi(STINT + 2, int(floor(laps * 14.0 / 24.0))) if h >= 24.0 else laps
	var min_each: int = int(ceil(laps * 6.0 / 24.0)) if h >= 24.0 else 0
	return {"win": win, "max_win": max_win, "max_total": max_total, "min_each": min_each}


## 최근 6시간 구간(랩)에 드라이버 d 가 달린 랩 수
func drive_in_window(c, d: int) -> int:
	var w: int = int(drive_limits()["win"])
	var n := 0
	var lg: Array = c.drv_log
	for i in range(maxi(0, lg.size() - w), lg.size()):
		if int(lg[i]) == d:
			n += 1
	return n


## 지금 드라이버가 한 스틴트 더 달리면 규정 위반인가
func must_swap(c) -> bool:
	if not is_wec() or c.drivers.size() < 2:
		return false
	var lim: Dictionary = drive_limits()
	var tot: int = int(c.drv_laps[c.drv]) if c.drv < c.drv_laps.size() else 0
	# 피트 판단은 랩 도중에 하므로 지금 달리는 랩(1)과 다음 스틴트(연비 주행이면 STINT+1)를 더해서 본다
	var more: int = 1 + STINT + 1
	return drive_in_window(c, c.drv) + more > int(lim["max_win"]) or tot + more > int(lim["max_total"])


## 드라이버 피로 (0~1): 운전하면 쌓이고(밤엔 더 빨리) 쉬면 풀린다
func fatigue(c, d: int = -1) -> float:
	var i: int = c.drv if d < 0 else d
	if i >= c.drivers.size():
		return 0.0
	return float(c.drivers[i].get("fat", 0.0))


func poisson(lam: float) -> int:
	var l := exp(-lam)
	var k := 0
	var p := 1.0
	while true:
		p *= rnd()
		if p <= l:
			break
		k += 1
		if k > 30:
			break
	return k


# ═════════ 난수 ═════════
func rnd() -> float:
	return rng.randf()


func uni(a: float, b: float) -> float:
	return a + (b - a) * rng.randf()


func gauss(s: float) -> float:
	return rng.randfn(0.0, 1.0) * s


# ═════════ 레이스 생성 ═════════
## start_comps: 내 차 2대의 출발 타이어 ["M", "H"] 등. my_team_ = -1이면 AI만 달린다(테스트용).
## opts(선택): 커리어·주말 모드에서 쓰는 설정
##   teams: 팀 목록(기본 DB.teams) · engines: 엔진 성능표 · my_mods: 내 차 보정 {aero, engine, chassis, rel, crew}
##   setup: 내 차 셋업 [{wing, press, fuel_load}] · sets: 내 차 주말 타이어 세트 [{S,M,H}] · true_mult: 실제 마모 배율
const FUEL_LOAD := {"light": -0.03, "std": 0.02, "heavy": 0.06}


func new_race(circ_key_: String, my_team_: int, laps_: int, wx_opt: String, start_comps: Array = ["M", "M"], seed_value: int = 0, opts: Dictionary = {}) -> void:
	DB.load_all()
	if seed_value != 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	circ_key = circ_key_
	T = DB.track(circ_key)
	CIRC = DB.circuits[circ_key]
	series = CIRC.get("series", "f1")
	min_drive = opts.get("min_drive", null)
	difficulty = clampi(int(opts.get("difficulty", 1)), 0, DIFF_PACE.size() - 1)
	rules = {"two_compounds": true, "wear_mult": 1.0}
	if opts.has("rules"):
		for k in opts["rules"]:
			rules[k] = opts["rules"][k]
	laps = laps_
	my_team = my_team_
	true_mult = {"S": uni(0.88, 1.14), "M": uni(0.88, 1.14), "H": uni(0.88, 1.14)}
	if opts.has("true_mult"):
		true_mult = opts["true_mult"]
	cars.clear()
	radio_log.clear()
	_cuts_cache.clear()
	# 레이스 상태 초기화 (AI 전략 계산 전에 맑음·그린 상태로)
	clock = 0.0
	wet = 0.0
	track_evo = 0.15
	sc = false
	sc_kind = ""
	sc_end_lap = 0
	sc_dist = -1.0
	sc_wait = false
	yellow = {}
	sc_in_notified = false
	sc_in_pit_lane = false
	sc_pit_prog = 0.0
	restart = false
	leader_lap = 0
	fastest_t = INF
	fastest_id = -1
	done = false
	finishing = false
	ever_wet = false
	night = false
	var teams: Array = opts.get("teams", DB.teams)
	var engines: Dictionary = opts.get("engines", DB.engines)
	var setups: Array = opts.get("setup", [])
	var sets: Array = opts.get("sets", [])
	n_stalls = teams.size()
	if is_wec():
		_build_wec_field(opts, start_comps)
		teams = []
	for ti in teams.size():
		var t: Dictionary = teams[ti]
		for k in 2:
			var d: Dictionary = t["drivers"][k]
			var c = CarS.new()
			c.id = cars.size()
			c.team = t["name"]
			c.team_idx = ti
			c.stall_idx = ti
			c.color = Color(t["color"])
			c.rim = Color(t["rim"])
			c.mine = ti == my_team
			c.slot = k
			c.aero = t["aero"]
			c.chassis = t["chassis"]
			c.rel = t["rel"]
			c.engine = float(t["engine_val"]) if t.has("engine_val") else float(engines.get(t["engine"], 0.86))
			c.strategy = clampf(0.70 + 0.22 * (((c.aero + c.chassis) / 2.0 - 0.76) / 0.19), 0.66, 0.93) + DIFF_STRAT[difficulty]
			c.drivers = [d.duplicate()]
			c.nerve = uni(0.5, 1.6)
			apply_driver(c)
			if c.mine:
				var sc_ = String(start_comps[k]) if k < start_comps.size() else "M"
				c.plan = {"start": sc_, "stops": []}
				c.fuel = laps * FPL * 1.02 * c.fuel_burn_rate # 드라이버 연비에 맞춰 싣는다
				c.wing = snappedf(float(CIRC.get("wingOpt", 3.0)), 0.1)
				c.press = "std"
				if k < setups.size():
					var su: Dictionary = setups[k]
					c.wing = float(su.get("wing", c.wing))
					c.press = su.get("press", "std")
					c.fuel_load = su.get("fuel_load", "std")
					c.fuel = laps * FPL * (1.0 + float(FUEL_LOAD[c.fuel_load])) * c.fuel_burn_rate
				if k < sets.size():
					c.tyre_sets = sets[k]
				c.sc_early = false
				c.comp = sc_
			else:
				c.sc_early = rnd() < 0.7
				c.sc_stay = rnd() < (0.3 if team_style(c.team) == "aggressive" else 0.12)
				c.sc_miss = rnd() < 0.3
				c.fuel = laps * FPL * (1.0 + uni(0.0, 0.04))
				c.wing = snappedf(clampf(float(CIRC["wingOpt"]) + gauss(0.35), 1.0, 5.0), 0.1)
				c.press = "low" if rnd() < 0.2 else ("high" if rnd() < 0.2 else "std")
				c.comp = "M"
			c.used = {c.comp: true}
			cars.append(c)
	# 커리어: 본부(HQ) 개발·설비·인력 보정을 내 차에 적용
	if opts.has("my_mods"):
		var mm: Dictionary = opts["my_mods"]
		for c in cars:
			if c.mine:
				c.aero = minf(0.99, c.aero + float(mm.get("aero", 0.0)))
				c.engine = minf(0.99, c.engine + float(mm.get("engine", 0.0)))
				c.chassis = minf(0.99, c.chassis + float(mm.get("chassis", 0.0)))
				c.rel = minf(0.99, c.rel + float(mm.get("rel", 0.0)))
				c.crew = minf(0.99, c.crew + float(mm.get("crew", 0.0)))
	if is_wec() and opts.has("my_mods"):
		var mw: Dictionary = opts["my_mods"]
		for c in cars:
			if c.mine:
				c.perf = minf(0.99, c.perf + float(mw.get("perf", 0.0)))
				c.rel = minf(0.99, c.rel + float(mw.get("rel", 0.0)))
				c.crew = minf(0.99, c.crew + float(mw.get("crew", 0.0)))
				c.bop += float(mw.get("bop", 0.0))
	# 커리어 이벤트 효과 (다음 레이스 한정): 집중력·신뢰성·그리드 강등
	if opts.has("event_mods"):
		var em: Dictionary = opts["event_mods"]
		for c in cars:
			if c.mine:
				var fl: Array = em.get("focus", [0, 0])
				c.focus = clampf(c.focus + float(fl[c.slot] if c.slot < fl.size() else 0), 30.0, 100.0)
				c.rel = clampf(c.rel + float(em.get("rel", 0.0)), 0.5, 0.99)
				var gl: Array = em.get("grid_pen", [0, 0])
				c.grid_pen = int(gl[c.slot]) if c.slot < gl.size() else 0
	# 그리드: 예선 페이스 순
	var qp = {}
	for c in cars:
		qp[c.id] = car_factor(c) * (1.0 - c.speed * K["drv_k"]) + gauss(0.004)
	cars.sort_custom(func(a, b): return qp[a.id] < qp[b.id])
	for i in cars.size():
		cars[i].grid = i
		cars[i].start_t = i * 0.22
	team_split = {}
	tally = {}
	for c in cars:
		if not c.mine and not is_wec():
			plan_ai_strategy(c, "")
	# 날씨
	rain = null
	team_order = "free"
	swap_req = false
	sc_laps = []
	active_radio = null
	iradio_done = {}
	var want_rain: bool = wx_opt == "rain" or (wx_opt == "auto" and rnd() < float(CIRC["rain"]))
	if want_rain:
		var st = maxi(2, int(round(uni(0.2, 0.55) * laps)))
		rain = {"start": st, "end": mini(laps + 1, st + int(round(uni(0.3, 0.55) * laps))), "level": uni(0.8, 1.0) if rnd() < 0.4 else uni(0.4, 0.6)}
	if rain != null:
		fc = {"lo": maxi(1, rain["start"] - 2), "hi": rain["start"] + 2, "p": int(round(uni(50, 80)))}
	elif rnd() < 0.3:
		fc = {"lo": int(round(laps * 0.4)), "hi": int(round(laps * 0.7)), "p": int(round(uni(15, 35)))}
	else:
		fc = null
	if CIRC.has("night") and CIRC["night"] != null:
		night = float(CIRC["night"][0]) <= 0.0
	_ai_setups()


## 팀 엔지니어 실력 (0~1): 커리어는 수석 엔지니어 등급, 그 밖에는 팀 전략 능력
func team_eng_q(c) -> float:
	return clampf((c.strategy - 0.6) / 0.35, 0.0, 1.0)


## AI 팀 세부 셋업: 전략·엔지니어 실력과 난이도만큼 최적값에 가깝게
func _ai_setups() -> void:
	for c in cars:
		if c.mine:
			continue
		var q: float = clampf(team_eng_q(c) + 0.2 + (difficulty - 1) * 0.15, 0.0, 1.0)
		engineer_setup(c, q)


func apply_driver(c) -> void:
	var d: Dictionary = c.drivers[c.drv]
	c.speed = d["speed"]
	c.cons = d["cons"]
	c.tyre_mgmt = d["tyreMgmt"]
	c.aggr = d["aggr"]
	c.def_ = d["def"]
	c.wet = d["wet"]
	c.tyre_deg_rate = clampf(1.0 + (0.80 - c.tyre_mgmt) * 0.65 + (c.aggr - 0.60) * 0.30, 0.78, 1.28)
	c.fuel_burn_rate = clampf(1.0 + (c.aggr - 0.60) * 0.22 + (0.82 - c.cons) * 0.18 - (c.tyre_mgmt - 0.78) * 0.12, 0.88, 1.14)
	c.name = d["name"]
	var parts: PackedStringArray = String(d["name"]).strip_edges().split(" ", false)
	var last: String = parts[parts.size() - 1] if parts.size() > 0 else c.name
	var letters = ""
	for ch in last:
		if ch.to_upper() != ch.to_lower():
			letters += ch
	c.code = letters.substr(0, 3).to_upper() if letters != "" else "DRV"


# ═════════ 성능 모델 ═════════
func car_factor(c) -> float:
	var dm: float = 1.0 if c.mine else float(DIFF_PACE[difficulty])
	if c.cls == "F1":
		return dm * (1.0 - K["car_scale"] * (c.aero * float(CIRC["wA"]) + c.engine * float(CIRC["wE"]) + c.chassis * float(CIRC["wC"])))
	return dm * float(CLASS_PACE.get(c.cls, 1.0)) * (1.0 - c.perf * BOP_K + c.bop)


func ideal_tyre(w: float) -> String:
	if w >= 0.65:
		return "W"
	if w >= (0.27 if is_wec() else 0.22):
		return "W" if is_wec() else "I"
	return "slick"


func kind_of(comp: String) -> String:
	return "slick" if SLICK.has(comp) else comp


func weather_pen(comp: String, w: float) -> float:
	if SLICK.has(comp):
		if w <= 0.03:
			return 0.0
		return 7.5 * (w - 0.03) + 28.0 * pow(maxf(0.0, w - 0.12), 1.6)
	if comp == "I":
		if w < 0.42:
			return 0.8 + 3.7 * pow((0.42 - w) / 0.42, 1.35)
		return 0.8 + 11.5 * pow(w - 0.42, 1.45)
	if is_wec():
		if w >= 0.65:
			return 0.0
		return 6.2 * pow((0.65 - w) / 0.65, 1.28)
	if w >= 0.85:
		return 0.4
	return 0.4 + 7.4 * pow((0.85 - w) / 0.85, 1.25)


func cliff_pen(comp: String, w: float) -> float:
	if comp == "S" and w > 0.60:
		return 1.6 + 2.6 * minf(1.0, (w - 0.60) / 0.40)
	if comp == "M" and w > 0.65:
		return 1.5 + 2.5 * minf(1.0, (w - 0.65) / 0.35)
	if comp == "H" and w > H_CLIFF:
		return 2.0 + 2.8 * minf(1.0, (w - H_CLIFF) / (1.0 - H_CLIFF))
	return 0.0


func true_wear_rate(comp: String) -> float:
	return float(COMP[comp][1]) * float(true_mult.get(comp, 1.0)) * float(rules.get("wear_mult", 1.0))


## 두 컴파운드 의무가 지금 적용되는지 (드라이 레이스 + 규칙)
func need_two() -> bool:
	return bool(rules.get("two_compounds", true)) and not is_wec() and not ever_wet


func drv_wing_pref(c) -> float:
	var d: Dictionary = c.drivers[c.drv]
	return snappedf((d["aggr"] - 0.58) * 1.1 + (d["wet"] - 0.82) * 0.6 - (d["tyreMgmt"] - 0.82) * 0.8, 0.01)


func wing_opt(w: float, c) -> float:
	return clampf(float(CIRC["wingOpt"]) + drv_wing_pref(c) + (1.0 if w > 0.25 else 0.0), 1.0, 5.0)


func setup_pen(c, w: float) -> float:
	var d: float = c.wing - wing_opt(w, c)
	return 0.15 * d * d * wsc()


## 세부 셋업 (서스펜션·브레이크 밸런스·디퍼렌셜) — 슬라이더 값과 숨은 최적값의 거리로 랩타임이 정해진다.
## 최적값은 서킷 성격(연석·저속 vs 고속, 트랙션 vs 직선) + 드라이버 성향 + 서킷·드라이버별 고정 편차.
## 각 항목: 딱 맞으면 랩당 -0.09초, 범위의 30% 이상 벗어나면 손해(최대 +0.045초).
const SETUP_RANGE := {"susp": [1.0, 10.0], "bbias": [52.0, 62.0], "diff": [20.0, 80.0]}
const SETUP_KO := {"wing": "윙", "susp": "서스펜션", "bbias": "브레이크 밸런스", "diff": "디퍼렌셜"}
const SETUP_K := 0.09


## 서킷 성격 점수: bump(+ = 저속·연석 많음 / - = 고속·매끈), trac(+ = 탈출 트랙션 중요 / - = 고속 직선 위주)
func circ_traits() -> Dictionary:
	var wa: float = float(CIRC.get("wA", 0.045))
	var wc: float = float(CIRC.get("wC", 0.045))
	var we: float = float(CIRC.get("wE", 0.04))
	return {"bump": clampf((wc - 0.045) / 0.02 - (wa - 0.045) / 0.04, -1.0, 1.0), "trac": clampf((wc - we) / 0.03, -1.0, 1.0)}


func _h01(sv: String) -> float:
	var h := 2166136261
	for ch in sv:
		h = ((h ^ ch.unicode_at(0)) * 16777619) & 0x7fffffff
	return float(h % 10000) / 10000.0


## 숨은 최적값 (서킷·드라이버마다 고정)
func setup_opt(c) -> Dictionary:
	if not c.setup_opt.is_empty():
		return c.setup_opt
	var ct := circ_traits()
	var ag: float = clampf((c.aggr - 0.6) / 0.15, -1.0, 1.0)
	var tm: float = clampf((c.tyre_mgmt - 0.8) / 0.08, -1.0, 1.0)
	var key: String = circ_key + "|" + c.name
	var o := {}
	o["susp"] = clampf(5.5 - 3.0 * ct["bump"] + 0.6 * ag + (_h01(key + "s") - 0.5) * 2.4, 1.0, 10.0)
	o["bbias"] = clampf(57.0 - 2.2 * ag + 0.8 * ct["bump"] + (_h01(key + "b") - 0.5) * 3.0, 52.0, 62.0)
	o["diff"] = clampf(50.0 + 18.0 * ct["trac"] - 6.0 * tm + (_h01(key + "d") - 0.5) * 16.0, 20.0, 80.0)
	c.setup_opt = o
	return o


## 항목별 정규화 오차 (값 - 최적) / 범위폭. 부호: + = 값이 최적보다 큼
func setup_err(c) -> Dictionary:
	var o := setup_opt(c)
	var out := {}
	for k in SETUP_RANGE:
		var r: Array = SETUP_RANGE[k]
		out[k] = (float(c.get(k)) - float(o[k])) / (float(r[1]) - float(r[0]))
	return out


## {dt: 초/랩, wear: 배율, err: 실수 배율}
func setup_extra(c) -> Dictionary:
	var e := setup_err(c)
	var dt := 0.0
	for k in e:
		var q: float = clampf(1.0 - absf(float(e[k])) / 0.3, -0.5, 1.0)
		dt -= SETUP_K * q
	# 물리적 대가 (최적과 무관): 단단할수록·잠글수록 마모↑, 브레이크를 뒤로 보낼수록 잠김 실수↑
	var wear: float = (1.0 + (c.susp - 5.5) * 0.01) * (1.0 + (c.diff - 50.0) * 0.0012)
	var err: float = 1.0 + (57.0 - c.bbias) * 0.025
	return {"dt": dt * (1.0 - 0.5 * wet) * wsc(), "wear": wear, "err": maxf(0.7, err)}


## 드라이버 피드백: 가장 많이 벗어난 항목의 방향을 말해 준다
func setup_tip(c) -> String:
	var e := setup_err(c)
	var worst := ""
	var wv := 0.0
	for k in e:
		if absf(float(e[k])) > absf(wv):
			wv = float(e[k])
			worst = k
	if absf(wv) < 0.05:
		return "세부 셋업은 거의 완벽해요"
	var strong: bool = absf(wv) > 0.18
	match worst:
		"susp":
			if wv > 0.0:
				return "연석에서 차가 튀어요. 서스펜션을 %s 부드럽게" % ("많이" if strong else "조금")
			return "고속 코너에서 차가 출렁여요. 서스펜션을 %s 단단하게" % ("많이" if strong else "조금")
		"bbias":
			if wv > 0.0:
				return "브레이킹 때 앞이 밀려요. 밸런스를 %s 뒤로" % ("많이" if strong else "조금")
			return "브레이킹 때 뒤가 불안해요. 밸런스를 %s 앞으로" % ("많이" if strong else "조금")
		_:
			if wv > 0.0:
				return "코너 중간에 차가 안 돌아요. 디퍼렌셜을 %s 풀어주세요" % ("많이" if strong else "조금")
			return "탈출에서 뒷바퀴가 헛돌아요. 디퍼렌셜을 %s 잠가주세요" % ("많이" if strong else "조금")


## 엔지니어 실력(q 0~1)만큼 최적값 근처로 맞춘 셋업 (AI 팀, 주말 없이 바로 레이스할 때 내 차)
func engineer_setup(c, q: float) -> void:
	var o := setup_opt(c)
	var sd: float = 0.04 + 0.16 * (1.0 - clampf(q, 0.0, 1.0))
	for k in SETUP_RANGE:
		var r: Array = SETUP_RANGE[k]
		var span: float = float(r[1]) - float(r[0])
		c.set(k, clampf(float(o[k]) + gauss(sd) * span, float(r[0]), float(r[1])))


func press_straight(pr: String) -> float:
	var k: float = float(CIRC["wE"]) / 0.05 if CIRC.has("wE") else (1.3 if float(CIRC["wingOpt"]) <= 2.0 else 0.9)
	return float(PRESS_FX[pr]["straight"]) * k * wsc()


func press_kerb(pr: String) -> float:
	var k: float = PRESS_FX[pr]["kerb"]
	return 1.0 + (k - 1.0) * (float(CIRC["wC"]) / 0.045 if CIRC.has("wC") else 1.0)


func drs_on() -> bool:
	return not is_wec() and leader_lap >= 2 and not sc and wet < 0.25


var _force_green := false  # 복기용: SC가 아니었다면의 피트 손실 계산


func sc_mult() -> float:
	if not sc or _force_green:
		return 1.0
	return 0.72 if sc_kind == "SC" else 0.80


func pit_loss() -> float:
	if is_wec():
		return float(CIRC.get("wecLaneLoss", WPIT["lane"])) * maxf(0.52, pit_scale()) * sc_mult()
	return float(CIRC["pitLoss"]) * sc_mult()


func pit_scale() -> float:
	return STINT / (3000.0 / float(CIRC["base"]))


## WEC 정차 시간: 피트레인 + 급유·타이어·드라이버 교대 작업 (실제 초를 레이스 압축률로 줄임)
func wec_stop_time(c, tyres: bool, driver: bool, fuel: bool = true) -> float:
	var lane_loss: float = float(CIRC.get("wecLaneLoss", WPIT["lane"])) * maxf(0.52, pit_scale())
	var fuel_work: float = WPIT["fuel"] * (1.05 - 0.2 * c.crew) if fuel else 0.0
	var tyre_work: float = WPIT["tyres"] * (1.15 - 0.35 * c.crew) if tyres else 0.0
	var drv_work: float = WPIT["driver"] if driver else 0.0
	var work: float = (fuel_work + tyre_work + drv_work) * maxf(0.32, pit_scale())
	var scf := 1.0
	if sc and not _force_green:
		scf = 0.62 if sc_kind == "SC" else 0.78
	return (lane_loss + work) * scf


func real_laps() -> float:
	return float(CIRC.get("hours", 6)) * 3600.0 / float(CIRC["base"])


func lap_base(c) -> float:
	return float(CIRC["base"]) * car_factor(c)


func next_stop(c) -> Variant:
	var stops: Array = c.plan["stops"]
	if c.stops_done < stops.size():
		return stops[c.stops_done]
	return null


# ═════════ 섹터 시간 ═════════
func sector_time(c, gap_ahead, gap_behind, is_restart: bool) -> Dictionary:
	var sh: float = T.share[c.sec]
	var w = wet
	var base = float(CIRC["base"])
	var pc: Array = PACE[c.pace]
	var spd: float = pc[0]
	var wear_m: float = pc[1]
	var err_m: float = pc[2]
	var tt_target: float = pc[3]
	var t = base * sh * car_factor(c) * (1.0 - c.speed * K["drv_k"] * spd)
	var evo_bonus = -0.65 * track_evo * (1.0 - w)
	var ws := wsc()
	t += (float(COMP[c.comp][0]) + c.used_set_pen + c.wear * c.wear * float(COMP[c.comp][2]) + cliff_pen(c.comp, c.wear) + c.fuel * 0.03 + evo_bonus) * sh * ws
	t += (setup_pen(c, w) + float(PRESS[c.press][0]) + press_straight(c.press)) * sh
	var sx: Dictionary = setup_extra(c)
	t += float(sx["dt"]) * sh
	if is_yellow(c.sec):
		t += 0.45 * sh * ws # 옐로 구간 감속
	var wp = weather_pen(c.comp, w)
	t += (wp + w * 6.0 + w * (0.8 - c.wet) * 4.0) * sh * ws
	if not is_wec():
		if gap_ahead != null and gap_ahead < K["dirty"] and c.instr != "hold":
			t += (0.2 + 0.3 * float(CIRC["wA"]) / 0.06 + 0.3 * w) * (1.0 - gap_ahead) * sh
		var em: String = c.ers_mode
		if em == "deploy" and c.ers <= 0.02:
			em = "balance"
		t += float(ERS[em][0]) * sh
		c.ers = clampf(c.ers + float(ERS[em][1]) * sh, 0.0, 1.0)
	var fm: Array = FUEL[c.fuel_mode]
	t += float(fm[0]) * sh * ws
	if c.fuel <= 0.0:
		t += 2.5 * sh * ws
	if c.instr == "defend" and gap_behind != null and gap_behind < 1.0:
		t += 0.3 * sh
	if night:
		t += base * sh * 0.008 * (1.2 - c.cons)
	# 멀티클래스 트래픽 (WEC): 하이퍼카는 GT3를 추월하며 시간 손실·접촉 위험, GT3는 비켜주며 소폭 손실
	# (HTML 은 HY↔GT 두 클래스뿐 → 클래스 페이스 차이로 일반화: HY·GT 만 있으면 원본과 같은 값)
	if is_wec():
		var my_p: float = CLASS_PACE.get(c.cls, 1.0)
		var lam_slow := 0.0
		var lam_fast := 0.0
		for o in cars:
			if o.is_running() and o.cls != c.cls:
				var op: float = CLASS_PACE.get(o.cls, 1.0)
				if op > my_p:
					lam_slow += op - my_p
				else:
					lam_fast += my_p - op
		for i in poisson(lam_slow * sh):
			t += uni(0.3, 1.6) * (1.3 - c.cons) * (1.4 if night else 1.0) * (1.0 + w)
			if rnd() < 0.0005 * (1.0 + c.aggr) * (1.5 if night else 1.0) * (1.0 + fatigue(c)):
				c.damage_now = "느린 클래스 차량과 접촉"
				_traffic_victim(c)
				break
		for i in poisson(lam_fast * sh):
			t += uni(0.15, 0.6)
	# 타이어 온도
	var target = tt_target + (0.05 if c.instr == "attack" else 0.0) + (0.02 if (c.ers_mode == "deploy" and not is_wec()) else 0.0) + float(PRESS[c.press][2]) - (0.05 if night else 0.0)
	if SLICK.has(c.comp) and w > 0.25:
		target -= 0.25
	if not SLICK.has(c.comp) and w < 0.2:
		target += 0.3
	c.tt = clampf(c.tt + (target - c.tt) * minf(0.9, 0.35 * float(PRESS_FX[c.press]["warm"])), 0.0, 1.0)
	var cold = maxf(0.0, 0.42 - c.tt)
	var hot = maxf(0.0, c.tt - 0.80)
	t += (cold * 4.0 + hot * 3.0 * float(PRESS_FX[c.press]["heat"])) * sh * ws
	var fat: float = (maxf(0.0, c.stint_drv - 1) * 0.04 + fatigue(c) * 0.3) if is_wec() else 0.0
	var cons: float = c.cons - fat - (0.08 if night else 0.0)
	var is_launch: bool = c.lap == 0 and c.sec == 0
	var noise_scale = 0.18 if is_launch else 1.0
	t += gauss((K["noise"] - cons * 0.4 + 0.3 * w) * sqrt(sh) * noise_scale * sqrt(ws))
	var pressure = 1.5 if (not is_launch and gap_ahead != null and gap_ahead < 0.5) else 1.0
	var p_err = 0.0
	if not is_launch:
		p_err = 0.036 * sh * err_m * press_kerb(c.press) * pressure * (1.2 - cons) * (1.0 + 3.0 * w * (1.3 - c.wet)) * (1.0 + wp / 5.0) * (1.5 if is_restart else 1.0) * (1.0 + cold * 5.0) * (1.2 if c.instr == "attack" else 1.0) * (1.5 if night else 1.0) * (1.5 if c.drivers[c.drv].get("grade", "") == "B" else 1.0) * float(sx["err"])
	# 트랙 리밋: 연석 공략이 과하면 경고, 세 번째부터 5초 페널티 (F1, 그린 상황에서만)
	if not is_wec() and not sc and not is_launch and rnd() < 0.012 * sh * err_m * (0.6 + c.aggr) * press_kerb(c.press) * (1.3 if c.instr == "attack" else 1.0) * (1.0 + maxf(0.0, c.susp - 7.0) * 0.08):
		c.tl_warn += 1
		if c.tl_warn >= 3:
			add_penalty(c, 5.0, "트랙 리밋 위반 %d회" % c.tl_warn)
		elif c.mine:
			say(c, "트랙 리밋 경고 (%d/2). 한 번 더 넘으면 페널티예요" % c.tl_warn)
	var crash = ""
	if rnd() < p_err:
		t += uni(1.0, 4.0) + w * 3.0
		if not sc and rnd() < 0.35:
			flag_yellow(c.sec, float(CIRC["base"]) * 0.25, "%s 코스 이탈" % name_of(c))
		if c.mine:
			say(c, "타이어가 차가워서 미끄러졌어요" if cold > 0.05 else "실수! 코너에서 밀렸어요")
		if w > 0.2 and rnd() < 0.25 * w:
			crash = "스핀"
	# 집중력·기계 스트레스
	var focus_delta: float = (c.focus - 75.0) / 25.0
	t -= focus_delta * 0.28 * sh
	if c.instr == "lift":
		t += 0.32 * sh
		c.tt = clampf(c.tt - 0.04, 0.0, 1.0)
		c.mech_stress = maxf(0.0, c.mech_stress - 0.14 * sh)
		if c.mech_trouble != "" and c.mech_stress < 0.28:
			if c.mine:
				say(c, "%s 온도가 안정됐어요. 정상 주행 가능해요" % c.mech_trouble)
			c.mech_trouble = ""
	else:
		var gain = (0.065 if c.pace == "attack" else (-0.02 if c.pace == "save" else 0.018)) * (1.25 - c.rel) * (1.5 if hot > 0.0 else 1.0)
		c.mech_stress = clampf(c.mech_stress + gain * sh, 0.0, 1.0)
		if c.mech_trouble == "" and c.mech_stress > 0.62 and rnd() < 0.18 * sh:
			c.mech_trouble = "브레이크 과열" if rnd() < 0.5 else "기어박스 유압 경고"
			if c.mine:
				say(c, "엔지니어 경고: %s! 페이스를 '세이브'로 낮춰 식혀주세요" % c.mech_trouble)
				trigger_radio(c, "MECH")
		if c.mech_trouble != "":
			t += (0.85 + c.mech_stress * 0.6) * sh
	if crash != "":
		c.focus = clampf(c.focus - 14.0, 30.0, 100.0)
	elif c.pace == "standard" and c.focus < 75.0:
		c.focus = clampf(c.focus + 1.5 * sh, 30.0, 100.0)
	# 마모·연료
	var over = 2.0 if (not SLICK.has(c.comp) and w < 0.2) else 1.0
	var wear_rate = true_wear_rate(c.comp) * float(CIRC["wear"]) * (WEC_WEAR if is_wec() else WEAR_SCALE / laps)
	var lift_wear = 0.80 if c.instr == "lift" else (0.92 if c.instr == "hold" else 1.0)
	var lift_fuel = 0.86 if c.instr == "lift" else 1.0
	c.wear = minf(1.0, c.wear + wear_rate * wear_m * over * (1.0 + hot * 5.0 * float(PRESS_FX[c.press]["heat"])) * lift_wear * float(PRESS[c.press][1]) * (1.0 - (c.wing - 3.0) * 0.04) * c.tyre_deg_rate * (0.85 if night else 1.0) * float(sx["wear"]) * sh)
	c.fuel -= FPL * sh * float(fm[1]) * c.fuel_burn_rate * lift_fuel * (2.0 - c.eng_eff) * (1.06 if c.pace == "attack" else (0.93 if c.pace == "save" else 1.0))
	return {"t": t, "crash": crash}


# ═════════ 무전·이벤트 ═════════
func say(c, msg: String) -> void:
	c.radio = msg
	c.radio_t = clock
	_push_log("L%d" % mini(laps, c.lap + 1), c.code, c.color, msg, "driver")


func event(msg: String, kind: String = "") -> void:
	_push_log("L%d" % mini(laps, leader_lap + 1), "RACE CTRL", Color("#ffc53d"), msg, kind if kind != "" else "ctrl")


func _push_log(lap_tag: String, who: String, col: Color, msg: String, kind: String) -> void:
	radio_log.push_front({"lap": lap_tag, "who": who, "color": col, "msg": msg, "kind": kind, "t": clock})
	if radio_log.size() > 80:
		radio_log.pop_back()


func name_of(c) -> String:
	if is_wec():
		return c.label if c.label != "" else c.team
	return "%s (%s)" % [c.code, c.team]


func alive() -> Array:
	var out = []
	for c in cars:
		if c.is_running():
			out.append(c)
	return out


func retire(c, why: String) -> void:
	c.dnf = why
	c.boxing = null
	c.pit_phase = 0
	c.pit_req = ""
	c.pending_crash = ""
	c.pending_victim = false
	c.sec_end = INF
	var tag := ""
	if is_wec():
		tag = "[HY] " if c.cls == "HY" else "[LMGT3] "
	event("%s%s %s → 리타이어" % [tag, name_of(c), why], "bad")
	if c.mine:
		say(c, "%s 발생으로 리타이어합니다." % why)
	if not sc and leader_lap < laps - 1:
		# 멈춘 차가 위험한 곳에 있을 때만 SC·VSC. 대부분은 그 섹터 국지 옐로로 처리 (원작보다 SC 빈도를 낮춤)
		var r = rnd()
		var p_sc = 0.06 if why == "고장" else (0.40 if why == "스핀" else 0.32)
		var p_v = 0.22 if why == "고장" else (0.15 if why == "스핀" else 0.22)
		if is_wec():
			p_sc *= 0.45 # 긴 서킷 + 많은 차: 대부분 슬로우 존·옐로로
			p_v *= 0.6
		if r < p_sc:
			deploy("SC")
		elif r < p_sc + p_v:
			deploy("FCY" if is_wec() else "VSC")
		else:
			flag_yellow(c.sec, float(CIRC["base"]) * 0.9, "%s 정지 차량" % name_of(c))


## WEC: 수리 가능한 손상 (60% 개러지 수리, 40% 리타이어)
func damage(c, why: String) -> void:
	if rnd() < 0.6:
		var lost: float = uni(1.5, 8.0) * float(CIRC["base"]) * laps / real_laps()
		c.garage += lost
		c.repairs += 1
		event("%s %s → 개러지 수리 (약 %d초 손실)" % [name_of(c), why, int(round(lost))], "bad")
		if c.mine:
			say(c, "%s. 피트로 들어가 수리합니다" % why)
		if c.boxing == null:
			c.boxing = {"comp": c.comp, "tyres": false, "driver": false, "fuel": false, "forced": true}
			c.pit_total = WPIT["lane"] * pit_scale()
		if not sc and rnd() < 0.04:
			deploy("FCY")
		elif not sc:
			flag_yellow(c.sec, float(CIRC["base"]) * 0.5, "%s 접촉" % name_of(c))
	else:
		retire(c, why)


## 클래스 간 트래픽 사고: 부딪힌 느린 차도 손상될 수 있고, 그 구간에 옐로
func _traffic_victim(c) -> void:
	var my_p: float = CLASS_PACE.get(c.cls, 1.0)
	var pool: Array = []
	for o in cars:
		if o.is_running() and o != c and float(CLASS_PACE.get(o.cls, 1.0)) > my_p and not is_pitting(o):
			pool.append(o)
	_tally("traffic_contact")
	if not pool.is_empty() and rnd() < 0.45:
		var o = pool[rng.randi_range(0, pool.size() - 1)]
		o.damage_now = "%s 와(과) 접촉" % c.label
	flag_yellow(c.sec, 40.0 * wsc(), "트래픽 접촉")


## 국지 옐로 플래그: 그 섹터는 추월 금지·감속
func flag_yellow(sec: int, dur: float, why: String) -> void:
	if sc or is_wec() and dur < 1.0:
		return
	var was: bool = is_yellow(sec)
	yellow[sec] = maxf(float(yellow.get(sec, 0.0)), clock + dur)
	if not was:
		event("🟨 S%d 옐로 플래그 (%s) · 추월 금지" % [sec + 1, why], "yellow")


func is_yellow(sec: int) -> bool:
	return yellow.has(sec) and float(yellow[sec]) > clock


func yellow_secs() -> Array:
	var out: Array = []
	for k in yellow:
		if float(yellow[k]) > clock:
			out.append(int(k))
	return out


func deploy(kind: String) -> void:
	if sc:
		return
	sc = true
	sc_kind = kind
	yellow = {}
	sc_in_notified = false
	sc_in_pit_lane = false
	sc_pit_prog = 0.0
	var n = int(round(uni(3, 4))) if kind == "SC" else 2
	if is_wec():
		n = maxi(2, int(round(laps * uni(0.08, 0.14)))) if kind == "SC" else 1
	sc_end_lap = leader_lap + n
	if kind == "SC":
		# 세이프티카는 피트 출구에서 나와 선두가 올 때까지 천천히 달리며 기다린다 (순간이동 없음)
		var lead: Variant = leader_car()
		var ld: float = car_dist(lead) if lead != null else 0.0
		var exit_d: float = float(T.cum[T.pit_out])
		var base_lap: float = floor(ld / T.L) * T.L
		var pe: float = base_lap + exit_d
		if pe < ld + T.L * 0.02:
			pe += T.L
		sc_dist = pe
		sc_wait = true
		event("세이프티카 출동! 대열이 압축됩니다 (%d랩 종료 예정)" % sc_end_lap, "sc")
	else:
		event("%s 발령! 간격 유지, 피트 손실 감소" % ("풀 코스 옐로" if kind == "FCY" else "버추얼 세이프티카"), "sc")
	if leader_lap >= 2:
		for mc in my_cars():
			if mc.is_running() and mc.wear >= 0.32 and mc.boxing == null and mc.pit_req == "" and not mc.auto_plan:
				trigger_radio(mc, "SC")
				break


# ═════════ AI 전략가 ═════════
## 서킷 마모·남은 랩·피트 손실로 전 경우의 수를 계산하고, 근소한 후보 중 팀 성향·그리드·전략 능력으로 고른다.
## 스틴트 3랩째마다 실측 마모로 남은 계획을 다시 짠다.
func team_style(team_name: String) -> String:
	var h = 0
	for i in team_name.length():
		h = (h * 31 + team_name.unicode_at(i)) & 0xFFFFFFFF
	if h >= 0x80000000:
		h -= 0x100000000
	return STRAT_STYLES[absi(h) % 4]


func ai_nom_rate(k: String, c) -> float:
	return true_wear_rate(k) * float(CIRC["wear"]) * (WEAR_SCALE / laps) * 0.85 * c.tyre_deg_rate


func ai_lim(k: String) -> float:
	return 0.80 if k == "S" else 0.85 # 마모 자체로 고장은 없음 → 랩타임 손실과 절벽만 비용


func ai_stint_cost(k: String, n: int, w0: float, r: float) -> float:
	var t = 0.0
	var w = w0
	for i in n:
		var wm = w + r / 2.0
		t += float(COMP[k][0]) + wm * wm * float(COMP[k][2]) + cliff_pen(k, wm)
		w += r
	if w > ai_lim(k) + 0.08:
		return t + 30.0 + (w - ai_lim(k)) * 60.0
	return t


func _cuts(ns: int, l: int) -> Array:
	var key = "%d:%d" % [ns, l]
	if _cuts_cache.has(key):
		return _cuts_cache[key]
	var out = []
	if ns == 0:
		out.append([])
	else:
		_rec_cuts(2, ns, l, [], out)
	_cuts_cache[key] = out
	return out


func _rec_cuts(from: int, ns: int, l: int, arr: Array, out: Array) -> void:
	if arr.size() == ns:
		out.append(arr.duplicate())
		return
	for x in range(from, l - 1):
		arr.append(x)
		_rec_cuts(x + 2, ns, l, arr, out)
		arr.pop_back()


## 남은 L랩에 대한 모든 전략(스톱 0~max_stops, 컴파운드 순서, 피트 랩)의 예상 손실 시간을 계산해 정렬.
func ai_optimize(l: int, start_comp: String, start_wear: float, rates: Dictionary, pit_cost: float, used: Dictionary, sets: Dictionary, max_stops: int) -> Array:
	var C = ["S", "M", "H"]
	# 스틴트 비용표 (길이 0~l) — 계산량을 줄이기 위해 미리 만들어 둔다
	var table = {}
	for k in C:
		var row = []
		for n in l + 1:
			row.append(ai_stint_cost(k, n, 0.0, rates[k]))
		table[k] = row
	var first_table = {}
	for k in C:
		if start_comp != "" and k != start_comp:
			continue
		var row = []
		for n in l + 1:
			row.append(ai_stint_cost(k, n, start_wear, rates[k]))
		first_table[k] = row
	var out = []
	var firsts: Array = [start_comp] if start_comp != "" else C
	for ns in max_stops + 1:
		var seqs: Array = []
		for f in firsts:
			seqs.append([f])
		for _i in ns:
			var nxt = []
			for s in seqs:
				for k in C:
					var s2: Array = s.duplicate()
					s2.append(k)
					nxt.append(s2)
			seqs = nxt
		var cuts = _cuts(ns, l)
		if cuts.is_empty():
			continue
		for seq in seqs:
			var all = used.duplicate()
			for k in seq:
				all[k] = true
			var n_slick = 0
			for k in C:
				if all.has(k):
					n_slick += 1
			if need_two() and n_slick < 2:
				continue
			var cnt = {"S": 0, "M": 0, "H": 0}
			for i in range(1, seq.size()):
				cnt[seq[i]] += 1
			if cnt["S"] > sets["S"] or cnt["M"] > sets["M"] or cnt["H"] > sets["H"]:
				continue
			var best_cost = INF
			var best_cut: Variant = null
			for cu in cuts:
				var t = ns * pit_cost
				var prev = 0
				for i in ns + 1:
					var nxt_b: int = cu[i] if i < ns else l
					var n_laps = nxt_b - prev
					t += (first_table[seq[0]][n_laps] if i == 0 else table[seq[i]][n_laps])
					prev = nxt_b
				if t < best_cost:
					best_cost = t
					best_cut = cu
			if best_cut != null:
				out.append({"cost": best_cost, "seq": seq, "cuts": best_cut})
	out.sort_custom(func(a, b): return a["cost"] < b["cost"])
	return out


func ai_choose(c, cands: Array, is_start: bool) -> Variant:
	if cands.is_empty():
		return null
	var st: String = c.strat_style
	var best: float = cands[0]["cost"]
	var min_stops = 99
	for x in cands:
		min_stops = mini(min_stops, x["cuts"].size())
	var tol: float = 3.0 + (1.0 - c.strategy) * 6.0
	var back: bool = is_start and c.grid >= 12
	var front: bool = is_start and c.grid <= 3
	var main_start: String = cands[0]["seq"][0]
	var pick: Variant = null
	var pv = INF
	for x in cands:
		if x["cost"] > best + tol:
			break
		var extra: int = x["cuts"].size() - min_stops
		var v: float = x["cost"] + gauss(0.8 + (1.0 - c.strategy) * 3.5)
		if st == "aggressive":
			v -= extra * 1.6 + (0.8 if x["seq"][0] == "S" else 0.0)
		if st == "conservative":
			v += extra * 1.6 - (0.6 if x["seq"][0] == "H" else 0.0)
		if back and x["seq"][0] != main_start:
			v -= 2.2 # 후미 그리드: 오프셋 전략으로 도박
		if front and x["seq"][0] == main_start:
			v -= 1.0 # 선두권: 정석 전략으로 리스크 관리
		if v < pv:
			pv = v
			pick = x
	return pick


func ai_rates(c, scale: float) -> Dictionary:
	return {"S": ai_nom_rate("S", c) * c.est_err * scale, "M": ai_nom_rate("M", c) * c.est_err * scale, "H": ai_nom_rate("H", c) * c.est_err * scale}


func plan_ai_strategy(c, fixed_start: String) -> void:
	if c.mine:
		return
	c.strat_style = team_style(c.team)
	c.est_err = clampf(1.0 + gauss((1.0 - c.strategy) * 0.45), 0.7, 1.35)
	var max_st := 0 if rules.get("no_pits", false) else (3 if laps >= 12 else 2)
	var cands = ai_optimize(laps, fixed_start, c.wear, ai_rates(c, 1.0), pit_loss() + 3.0, {}, {"S": 1, "M": 2, "H": 1}, max_st)
	var pk: Variant = ai_choose(c, cands, true)
	if pk == null:
		return
	# 두 대 전략 나누기: 반응형·공격형 팀과 일부 균형형 팀은 두 번째 차를 다른 스톱 수로 (근소한 후보가 있을 때만)
	if team_split.has(c.team) and int(team_split[c.team]) == pk["cuts"].size():
		var split_k: float = 0.75 if c.strat_style in ["reactive", "aggressive"] else (0.35 if c.strat_style == "balanced" else 0.1)
		if rnd() < split_k:
			_tally("전략분리")
			for x in cands:
				if x["cuts"].size() != pk["cuts"].size() and float(x["cost"]) <= float(cands[0]["cost"]) + 4.0 + (1.0 - c.strategy) * 4.0:
					pk = x
					break
	if not team_split.has(c.team):
		team_split[c.team] = pk["cuts"].size()
	var stops = []
	for i in pk["cuts"].size():
		var jit = int(round(gauss(0.5 + (1.0 - c.strategy) * 1.2)))
		stops.append({"lap": clampi(pk["cuts"][i] + jit, 2, laps - 1), "comp": pk["seq"][i + 1]})
	c.plan = {"start": pk["seq"][0], "stops": stops}
	c.stops_done = 0
	c.comp = pk["seq"][0]
	c.used = {c.comp: true}
	c.stint_start_lap = 0
	c.stint_start_wear = c.wear
	c.replan_at = -1


func ai_replan(c) -> void:
	if c.mine or wet > 0.05 or ever_wet:
		return
	var cur: int = c.lap + 1
	var done_laps: int = cur - c.stint_start_lap
	if done_laps < 3 or c.replan_at == c.pits:
		return
	c.replan_at = c.pits
	var nom = ai_nom_rate(c.comp, c)
	var obs: float = (c.wear - c.stint_start_wear) / maxf(1.0, done_laps)
	var scale = clampf(obs / maxf(1e-4, nom * c.est_err), 0.6, 1.7)
	var left: int = laps - c.lap
	if left < 2:
		return
	var cands = ai_optimize(left, c.comp, c.wear, ai_rates(c, scale), pit_loss() + 3.0, c.used, c.ai_sets, 2)
	var pk: Variant = ai_choose(c, cands, false)
	if pk == null:
		return
	var base: int = c.lap
	var keep: Array = c.plan["stops"].slice(0, c.stops_done)
	for i in pk["cuts"].size():
		keep.append({"lap": clampi(base + pk["cuts"][i], cur, laps - 1), "comp": pk["seq"][i + 1]})
	c.plan["stops"] = keep


func _pick_ai_slick(c, pref: String, rem_laps: int) -> String:
	var need_diff: bool = need_two() and c.used_slicks() < 2
	var cands: Array = ["S", "M", "H"] if rem_laps <= 5 else (["M", "H", "S"] if rem_laps <= 9 else ["H", "M", "S"])
	if SLICK.has(pref):
		var re = [pref]
		for x in cands:
			if x != pref:
				re.append(x)
		cands = re
	if need_diff:
		for x in cands:
			if not c.used.has(x) and c.ai_sets[x] > 0:
				c.ai_sets[x] -= 1
				return x
	var chosen = ""
	for x in cands:
		if c.ai_sets[x] > 0:
			chosen = x
			break
	if chosen == "":
		chosen = _alt_slick(c.comp) if need_diff else String(cands[0])
	if c.ai_sets[chosen] > 0:
		c.ai_sets[chosen] -= 1
	return chosen


## 마지막 스틴트에 가장 빠른 컴파운드 (끝까지 버틸 수 있는 것 중 예상 시간 최소). 없으면 ""
func _best_final(c, rem: int) -> String:
	var need_diff: bool = need_two() and c.used_slicks() < 2
	var best := ""
	var best_t := INF
	for k in ["S", "M", "H"]:
		if need_diff and c.used.has(k):
			continue
		var r: float = ai_nom_rate(k, c) * c.est_err
		if rem * r > ai_lim(k) - 0.03:
			continue
		var tt: float = rem * float(COMP[k][0]) + float(COMP[k][2]) * r * r * rem * rem * rem / 3.0
		if tt < best_t:
			best_t = tt
			best = k
	return best


## 전략 감각이 좋은 팀은 마지막 스틴트 타이어를 계산해서 고른다
func _pick_smart(c, pref: String, rem: int, tact: float) -> String:
	if tact >= 0.7 and c.stops_done >= c.plan["stops"].size():
		var b: String = _best_final(c, rem)
		if b != "" and int(c.ai_sets.get(b, 0)) > 0:
			if b != pref:
				_tally("타이어재선택")
			c.ai_sets[b] -= 1
			return b
	return _pick_ai_slick(c, pref, rem)


func _alt_slick(comp: String) -> String:
	if comp == "S":
		return "M"
	if comp == "M":
		return "H"
	return "M"


## 피트 판단: 마지막 섹터에 들어설 때(피트 입구 전) 호출. 플레이어 차는 박스 지시가 있을 때만 들어온다.
func pit_decision(c) -> Variant:
	var cur: int = c.lap + 1
	var left: int = laps - cur
	var want = ideal_tyre(wet)
	if left < 1 or c.crew_cooldown > 0:
		return null
	if is_wec():
		return wec_decision(c, cur, left, want)
	if c.pit_req != "":
		var comp: String = c.pit_req
		c.pit_req = ""
		c.crew_out = true
		var ns0: Variant = next_stop(c)
		if ns0 != null:
			c.stops_done += 1
			_shift_custom(c, cur - int(ns0["lap"]))
		return {"comp": comp, "tyres": true}
	if c.mine:
		if not c.custom_plans and c.plans_at != c.pits and c.lap - c.stint_start_lap >= 4 and SLICK.has(c.comp):
			c.plans_at = c.pits
			make_plans(c)
		return _my_auto_decision(c, cur, left, want) if c.auto_plan else null
	if rules.get("no_pits", false) and kind_of(c.comp) == want:
		return null # F3·스프린트: 날씨가 바뀔 때만 피트
	ai_replan(c)
	var ns: Variant = next_stop(c)
	var have = kind_of(c.comp)
	var tact: float = clampf(c.strategy + (difficulty - 1) * 0.08, 0.3, 1.1)
	if want != have:
		var nw = ("M" if left > 8 else "S") if want == "slick" else want
		var lose = weather_pen(c.comp, wet) - weather_pen(nw, wet)
		var horizon: float = minf(left, uni(2, 9))
		if tact >= 0.7:
			# 예보를 읽는 팀: 실제로 맞지 않는 타이어로 달릴 랩 수를 센다 (곧 그치거나 마르면 버틴다)
			var n_wrong := 0
			for l in range(cur, mini(laps, cur + 8) + 1):
				if ideal_tyre(forecast_wet_at(l)) != have:
					n_wrong += 1
				else:
					break
			horizon = minf(float(left), float(n_wrong) * uni(0.85, 1.15) + 0.5)
		if lose * horizon > pit_loss() * c.nerve:
			c.weather_pit = true
			c.crew_out = true
			return {"comp": nw, "tyres": true}
		return null
	# 예보 선제 대응: 다음 랩에 노면이 바뀌고 어차피 2랩 안에 피트할 계획이면 지금 맞는 타이어로 (스톱 하나 절약)
	if tact >= 0.8 and ns != null and int(ns["lap"]) - cur <= 2 and not sc and left > 2:
		var want_next: String = ideal_tyre(forecast_wet_at(cur + 1))
		if want_next != have:
			_tally("예보선제")
			c.stops_done += 1
			c.weather_pit = true
			c.crew_out = true
			return {"comp": ("M" if left > 8 else "S") if want_next == "slick" else want_next, "tyres": true}
	# 커버 피트: 바로 앞뒤 차가 피트 준비를 하면 전략 능력에 비례해 대응
	if not sc and c.wear >= 0.26 and left > 3:
		var ord = []
		for o in order():
			if o.dnf == "":
				ord.append(o)
		var idx = ord.find(c)
		var k: int = c.cross.size() - 1
		var behind: Variant = ord[idx + 1] if idx + 1 < ord.size() else null
		var ahead: Variant = ord[idx - 1] if idx >= 1 else null
		var gap_b = 99.0
		var gap_a = 99.0
		if behind != null and k >= 0 and behind.cross.size() > k:
			gap_b = absf(behind.cross[k] - c.cross[k])
		if ahead != null and k >= 0 and ahead.cross.size() > k:
			gap_a = absf(c.cross[k] - ahead.cross[k])
		var threat_b: bool = behind != null and gap_b <= 2.2 and not behind.covering and (behind.crew_out or behind.pit_phase == 2)
		var threat_a: bool = ahead != null and gap_a <= 2.0 and ahead.crew_out and not ahead.covering
		var fin_comp: String = ns["comp"] if ns != null else ("H" if left > 8 else "M")
		var stop_soon: bool = ns != null and ns["lap"] - cur <= 4 and c.stops_done == c.plan["stops"].size() - 1
		var can_finish: bool = left * ai_nom_rate(fin_comp, c) <= ai_lim(fin_comp)
		var style_m = 1.25 if c.strat_style == "reactive" else (0.8 if c.strat_style == "conservative" else 1.0)
		if (threat_b or threat_a) and (stop_soon or can_finish or (ns != null and ns["lap"] - cur <= 2)) and rnd() < c.strategy * 0.78 * style_m:
			if ns != null:
				c.stops_done += 1
			c.crew_out = true
			c.covering = true
			return {"comp": fin_comp, "tyres": true}
	if not c.weather_pit and ns != null and not sc and left > 4 and SLICK.has(c.comp):
		var to_stop: int = int(ns["lap"]) - cur
		var front: Variant = _front_same_class(c)
		var gf: float = gap_seconds(c, front) if front != null else 99.0
		# 언더컷: 앞차가 1.8초 안이고 계획 스톱이 3랩 안이면 먼저 들어가서 새 타이어로 앞지르기
		if front != null and gf < 1.8 and to_stop >= 1 and to_stop <= 3 and front.pit_phase == 0 and not front.crew_out and c.wear > 0.3 and c.undercut_try != c.stops_done:
			c.undercut_try = c.stops_done
			var um: float = 1.3 if c.strat_style == "aggressive" else (0.6 if c.strat_style == "conservative" else 1.0)
			# 마지막 스톱이면 새 타이어로 끝까지 갈 수 있을 때만 (괜히 스톱이 늘지 않게)
			var nc: String = ns["comp"]
			var last_stop: bool = c.stops_done >= c.plan["stops"].size() - 1
			var ok_fin: bool = not last_stop or left * ai_nom_rate(nc, c) <= ai_lim(nc) - 0.03
			if ok_fin and rnd() < tact * 0.3 * um:
				_tally("언더컷")
				c.stops_done += 1
				c.crew_out = true
				return {"comp": _pick_ai_slick(c, ns["comp"], left), "tyres": true}
		# 오버컷: 앞차가 방금 피트했고 내 타이어가 버티면 1~2랩 더 끌어서 깨끗한 공기에서 시간 벌기
		if front != null and to_stop <= 0 and (front.pit_lap or front.pit_phase == 2) and c.wear < ai_lim(c.comp) - 0.15 and c.overcut_try != c.stops_done:
			c.overcut_try = c.stops_done
			if rnd() < tact * 0.4:
				var ext: int = 1 + int(rnd() < 0.5)
				_tally("오버컷")
				ns["lap"] = mini(laps - 1, int(ns["lap"]) + ext)
				return null
		# 트래픽 판단: 감각 좋은 팀은 복귀 지점에 차가 몰려 있으면 한 랩 미룬다 (낮은 팀은 그냥 들어감)
		if to_stop <= 0 and tact >= 0.82 and c.wear < ai_lim(c.comp) - 0.1 and c.traffic_try != c.stops_done:
			c.traffic_try = c.stops_done
			var pr: Variant = predict_pit(c)
			if pr != null and pr["ahead"] != null and float(pr["ahead"][1]) < 1.0:
				_tally("트래픽회피")
				ns["lap"] = mini(laps - 1, int(ns["lap"]) + 1)
				return null
	if not c.weather_pit and ns != null:
		if not sc and (cur >= ns["lap"] or c.wear >= 0.80):
			c.stops_done += 1
			c.crew_out = true
			return {"comp": _pick_smart(c, ns["comp"], left, tact) if want == "slick" else want, "tyres": true}
		# SC: 대부분 들어가지만, 일부는 트랙 포지션 도박(스테이 아웃), 감각 낮은 팀은 기회를 놓치기도
		var sc_skip: bool = (c.sc_stay and c.wear < 0.55) or (tact < 0.7 and c.sc_miss)
		if sc and not sc_skip and cur > 2 and c.wear >= 0.35 and (cur >= ns["lap"] or (c.sc_early and ns["lap"] - cur <= 4) or c.wear >= 0.50) and left > 2:
			c.stops_done += 1
			c.crew_out = true
			return {"comp": _pick_smart(c, ns["comp"], left, tact) if want == "slick" else want, "tyres": true}
		# SC 찬스: 마지막 스톱이 남았고 새 타이어로 끝까지 갈 수 있으면 계획보다 일찍이라도 싸게 들어간다
		if sc and not sc_skip and tact >= 0.62 and want == "slick" and left > 3 and c.wear >= 0.18 and c.stops_done == c.plan["stops"].size() - 1:
			var fin: String = _best_final(c, left)
			if fin != "":
				_tally("SC찬스")
				c.stops_done += 1
				c.crew_out = true
				if c.ai_sets.get(fin, 0) > 0:
					c.ai_sets[fin] -= 1
				return {"comp": fin, "tyres": true}
	# 계획에 없던 피트: 남은 랩 동안 잃을 시간이 피트 손실보다 클 때만
	var pen_now: float = c.wear * c.wear * float(COMP[c.comp][2]) + cliff_pen(c.comp, c.wear)
	var fresh = "H" if left > 7 else ("M" if left > 4 else "S")
	var fresh_gap: float = float(COMP[fresh][0]) - float(COMP[c.comp][0])
	if left >= 2 and ((pen_now - fresh_gap) * left * 0.75 > pit_loss() + 3.0 or c.wear >= 0.92):
		if ns != null:
			c.stops_done += 1
		c.crew_out = true
		return {"comp": _pick_ai_slick(c, fresh, left) if want == "slick" else want, "tyres": true}
	if need_two() and left <= 3 and c.used_slicks() < 2:
		c.crew_out = true
		return {"comp": _alt_slick(c.comp), "tyres": true}
	return null


## 피트 크루 실수: 느린 정차(휠건·잭 문제)와 드물게 휠너트 문제. 크루 실력이 낮을수록 잦다.
func _tally(k: String) -> void:
	tally[k] = int(tally.get(k, 0)) + 1


func _crew_error(c) -> float:
	var skill: float = clampf(1.3 - c.crew, 0.3, 0.8)
	if rnd() < 0.012 * skill:
		event("%s 휠너트 문제! 정차가 크게 늦어졌어요" % name_of(c), "bad")
		_tally("휠너트")
		return uni(7.0, 14.0)
	if rnd() < 0.08 * skill:
		_tally("느린정차")
		if c.mine:
			say(c, "피트 크루 실수, 정차가 늦었어요")
		return uni(1.5, 4.5)
	return 0.0


## 바로 앞 차 (같은 클래스): 방금 지난 경계를 나보다 먼저, 가장 늦게 지난 차
## (order() 는 경계를 막 지난 순간 정렬이 어긋나서 쓰지 않는다)
## 스틴트별 타이어 목록 (출발 타이어 + 타이어를 간 피트마다)
func tyre_seq(c) -> Array:
	var first: String = c.lap_times[0]["comp"] if not c.lap_times.is_empty() else c.comp
	var out: Array = [first]
	for pl in c.pit_log:
		if pl.get("tyres", pl["to"] != pl["from"]):
			out.append(pl["to"])
	return out


func _front_same_class(c) -> Variant:
	var k: int = c.cross.size() - 1
	if k < 0:
		return null
	var best: Variant = null
	var bt := -INF
	for o in cars:
		if o == c or o.cls != c.cls or o.dnf != "" or o.cross.size() <= k:
			continue
		var ot: float = float(o.cross[k])
		if ot < float(c.cross[k]) and ot > bt:
			bt = ot
			best = o
	return best


func _wec_burn(c, m: String) -> float:
	return FPL * float(FUEL[m][1]) * c.fuel_burn_rate * (2.0 - c.eng_eff)


## WEC 피트 판단 (HTML wecDecision). 내 차는 지시가 있을 때만, 단 연료가 1랩도 안 남으면 자동 급유
func wec_decision(c, cur: int, left: int, want: String) -> Variant:
	var want_kind := "slick" if want == "slick" else "W"
	if c.mine:
		if c.pit_req == "":
			var fm_m: float = float(FUEL[c.fuel_mode][1]) * c.fuel_burn_rate * (1.06 if c.pace == "attack" else (0.93 if c.pace == "save" else 1.0)) * (2.0 - c.eng_eff)
			var one_lap: float = FPL * fm_m
			var fuel_line: float = c.fuel - one_lap * T.share[NS - 1]
			if left >= 1 and fuel_line < one_lap * 0.90:
				var d_t: bool = c.wear > 0.45 or kind_of(c.comp) != want_kind
				var comp0: String = (wec_fit_comp(c.cls, "M") if want == "slick" else "W") if d_t else c.comp
				say(c, "연료 부족! 다음 랩 완주 불가 → 자동 박스 (급유%s)" % ((" + " + TYRE_KO[comp0]) if d_t else ""))
				return {"comp": comp0, "tyres": d_t, "driver": false, "fuel": true}
			return null
		var req: Dictionary = c.wec_req if c.wec_req != null else {"tyres": true, "fuel": true, "driver": false}
		var comp1: String = wec_fit_comp(c.cls, c.pit_req)
		c.pit_req = ""
		c.wec_req = null
		c.crew_out = true
		return {"comp": comp1, "tyres": bool(req.get("tyres", true)), "driver": bool(req.get("driver", false)), "fuel": bool(req.get("fuel", true))}
	var fm: float = float(FUEL[c.fuel_mode][1]) * c.fuel_burn_rate
	var fuel_at_line: float = c.fuel - FPL * T.share[NS - 1] * fm
	var need_fuel: bool = fuel_at_line < FPL * fm * 0.92 and left >= 1
	var worn_out: bool = c.wear >= 0.62 and left >= 2
	var early: bool = c.sc_early and sc and cur > 2 and c.wear >= 0.38 and (fuel_at_line < FPL * fm * 2.2 or c.wear >= 0.50) and left > 2
	var wrong: bool = kind_of(c.comp) != want_kind
	var weather := false
	if wrong:
		var nw := "M" if want == "slick" else "W"
		var lose: float = weather_pen(c.comp, wet) - weather_pen(nw, wet)
		weather = lose * uni(1.8, 4.5) > wec_stop_time(c, true, false) * 0.75
	if not need_fuel and not worn_out and not early and not weather:
		return null
	var tyre_due: bool = c.stint_tyre + 1 >= c.tyre_every or c.wear >= 0.52 or worn_out
	# 세트 제한: 남은 스틴트에 비해 새 세트가 모자라면 마모가 심하지 않은 한 한 스틴트 더 탄다
	if tyre_due and not wrong and want == "slick":
		var stints_after: int = int(ceil(float(left) / STINT))
		var short_sets: bool = c.wec_sets < int(ceil(stints_after / 2.0))
		if c.wec_sets <= 0 and not worn_out:
			tyre_due = false
		elif short_sets and c.wear < 0.45 and not worn_out:
			tyre_due = false
	var tyres: bool = tyre_due or wrong
	var driver: bool = c.stint_drv + 1 >= c.driver_every or must_swap(c)
	var comp: String = (c.comp if SLICK.has(c.comp) else "M") if want == "slick" else "W"
	if want == "slick" and tyres:
		# 컴파운드 선택: 마지막 한 스틴트·서늘한 밤·공격형 팀은 소프트, 남은 게 길고 아끼는 팀은 하드
		var one_stint: bool = left <= STINT + 1 or c.tyre_every <= 1
		if one_stint and (left <= STINT + 1 or night or c.wec_style == "push") and rnd() < (0.75 if left <= STINT + 1 else 0.45):
			comp = "S"
		elif c.wec_style == "save" and left > STINT * 2 and rnd() < 0.5:
			comp = "H"
		elif comp == "S" and not one_stint:
			comp = "M"
	if not tyres:
		comp = c.comp
	comp = wec_fit_comp(c.cls, comp)
	c.crew_out = true
	return {"comp": comp, "tyres": tyres, "driver": driver, "fuel": true}


## 랩마다: 드라이버 기록 · 피로 · 주행 시간 규정 확인 (내 차는 경고 후 위반 시 60초)
func _drive_lap(c) -> void:
	c.drv_log.append(c.drv)
	var hpl: float = wec_hours() / maxf(1.0, float(laps))
	for i in c.drivers.size():
		var f: float = float(c.drivers[i].get("fat", 0.0))
		if i == c.drv:
			f += 0.06 * hpl * (1.7 if night else 1.0)
		else:
			f -= 0.09 * hpl
		c.drivers[i]["fat"] = clampf(f, 0.0, 1.0)
	if c.drivers.size() < 2:
		return
	var lim: Dictionary = drive_limits()
	var inw: int = drive_in_window(c, c.drv)
	var tot: int = int(c.drv_laps[c.drv]) if c.drv < c.drv_laps.size() else 0
	var over: bool = inw > int(lim["max_win"]) or tot > int(lim["max_total"])
	if over and c.drive_warned != c.drv + 100:
		c.drive_warned = c.drv + 100
		c.time_pen += 60.0
		_tally("drive_viol")
		if c.mine:
			say(c, "주행 시간 규정 위반 (%s) → 60초 페널티" % c.name)
		event("%s %s 주행 시간 초과 → 60초 페널티" % [name_of(c), c.name], "bad")
	elif c.mine and not over and c.drive_warned != c.drv and (inw + 1 >= int(lim["max_win"]) or tot + 1 >= int(lim["max_total"])):
		c.drive_warned = c.drv
		say(c, "%s 주행 시간 한도 임박! 다음 피트에서 드라이버 교대하세요" % c.name)


func ai_control(c, gap_ahead, gap_behind) -> void:
	if c.mine:
		return
	if is_wec():
		# 팀 성향별 연비 전략 + 막판 연비 주행으로 마지막 스톱 생략 시도
		var left: int = laps - c.lap
		var st: String = c.wec_style
		var std_m := "rich" if st == "push" else "std"
		var need_lean := maxi(0, int(ceil((left * _wec_burn(c, "lean") - c.fuel) / TANK - 0.000001)))
		var need_std := maxi(0, int(ceil((left * _wec_burn(c, std_m) - c.fuel) / TANK - 0.000001)))
		if left <= 14 and need_lean < need_std:
			c.fuel_mode = "lean"
		else:
			c.fuel_mode = "rich" if st == "push" else ("lean" if st == "save" else "std")
		_ai_tactics(c, gap_ahead, gap_behind)
		return
	_ai_tactics(c, gap_ahead, gap_behind)
	if c.ers < 0.2:
		c.ers_mode = "harvest"
	elif gap_ahead != null and gap_ahead < 1.0 and c.ers > 0.35:
		c.ers_mode = "deploy"
	elif gap_behind != null and gap_behind < 0.8 and c.ers > 0.3:
		c.ers_mode = "deploy"
	else:
		c.ers_mode = "balance"
	c.fuel_mode = "lean" if c.fuel < (laps - c.lap) * FPL * 0.97 else "std"


## AI 주행 전술: 페이스(공격·표준·세이브)와 상황 지시(추월·방어·연비)를 상황에 맞게.
## 전술 감각 = 팀 전략 능력 + 난이도. 감각이 낮은 팀은 기계 과열·타이어 관리 대응이 늦고 공격 타이밍도 무디다.
func _ai_tactics(c, gap_ahead, gap_behind) -> void:
	if sc or not c.started:
		c.pace = "standard"
		c.instr = "free"
		return
	var tact: float = clampf(c.strategy + (difficulty - 1) * 0.08, 0.3, 1.1)
	var st: String = c.strat_style
	var left: int = laps - c.lap
	var ns: Variant = next_stop(c)
	var to_stop: int = (int(ns["lap"]) - (c.lap + 1)) if ns != null else left
	var lim: float = ai_lim(c.comp) if SLICK.has(c.comp) else 0.9
	# 1) 기계 과열: 감각이 좋을수록 일찍 식힌다
	if c.mech_trouble != "" or c.mech_stress > 0.5 + (1.0 - tact) * 0.35:
		c.instr = "lift"
		c.pace = "save"
		return
	if c.instr == "lift" and c.mech_stress > 0.3:
		return
	var pace := "standard"
	var instr := "free"
	# 2) 페이스: 피트 직전 인랩·직후 아웃랩은 푸시(언더컷), 타이어가 한계에 가까운데 스톱이 멀면 세이브
	var in_lap: bool = c.crew_out or (ns != null and to_stop <= 0)
	var out_lap: bool = c.stint_laps <= 1 and c.pits > 0
	if tact >= 0.62 and (in_lap or out_lap) and c.wear < lim and wet < 0.15:
		pace = "attack"
	elif SLICK.has(c.comp) and c.wear > lim - 0.12 and to_stop > 1:
		pace = "save"
	elif st == "conservative" and to_stop > 4 and c.wear > 0.35:
		pace = "save"
	elif left <= 2 and c.wear < lim - 0.05 and wet < 0.2:
		pace = "attack" # 막판 스퍼트
	# 3) 지시: 바로 앞차가 1초 안이면 추월 시도(공격적인 드라이버·팀일수록), 뒤에 붙으면 방어
	var push_k: float = c.aggr + (0.12 if st == "aggressive" else (-0.1 if st == "conservative" else 0.0))
	if gap_ahead != null and float(gap_ahead) < 0.6 and c.wear < lim - 0.05 and push_k > 0.62 and wet < 0.2:
		instr = "attack"
	elif gap_behind != null and float(gap_behind) < 0.5 and c.def_ > 0.8:
		instr = "defend"
	elif pace == "save" and tact >= 0.7 and c.wear > lim - 0.08:
		instr = "hold"
	if is_wec():
		pace = "standard" # WEC 는 연료 모드로 페이스를 조절 (공격 페이스는 연비 계산을 흐트러뜨림)
	c.pace = pace
	c.instr = instr


# ═════════ 결승선·섹터 경계 통과 ═════════
func on_cross(c, t: float) -> void:
	if not c.is_running():
		return
	if c.started:
		while c.cur_sec_times.size() <= c.sec:
			c.cur_sec_times.append(0.0)
		c.cur_sec_times[c.sec] = t - c.sec_start
	else:
		c.lap_start_t = t
		c.cur_sec_times = []
	c.cross.append(t)
	if c.started and c.sec == NS - 1:
		var lt: float = t - c.lap_start_t
		c.lap += 1
		c.last_sec_times = c.cur_sec_times.duplicate()
		c.cur_sec_times = []
		if not c.pit_lap:
			c.last_lap_t = lt
			if lt < c.best:
				c.best = lt
			if lt < fastest_t:
				fastest_t = lt
				fastest_id = c.id
		c.stint_laps += 1
		if c.drv < c.drv_laps.size():
			c.drv_laps[c.drv] += 1
		if is_wec():
			_drive_lap(c)
		c.lap_hist.push_front({"lap": c.lap, "t": lt, "comp": c.comp, "pit": c.pit_lap})
		c.pos_hist.append({"lap": c.lap, "pos": pos_at_line(c)})
		c.lap_times.append({"lap": c.lap, "t": lt, "comp": c.comp, "pit": c.pit_lap, "cliff": SLICK.has(c.comp) and c.wear > ai_lim(c.comp)})
		if c.lap_hist.size() > 45:
			c.lap_hist.pop_back()
		if c.crew_cooldown > 0:
			c.crew_cooldown -= 1
		if not c.mine and c.boxing == null:
			var ns: Variant = next_stop(c)
			c.crew_out = (ns != null and c.lap + 1 == ns["lap"]) or c.wear > 0.78
		c.pit_lap = false
		c.lap_start_t = t
		if c.lap > leader_lap:
			leader_lap = c.lap
			on_leader_lap()
		if c.lap >= laps or finishing:
			c.finished = true
			c.finish_t = t
			c.boxing = null
			c.pit_phase = 0
			if c.time_pen > 0.0:
				c.penalty += c.time_pen
				c.finish_t += c.time_pen
			if need_two() and c.used_slicks() < 2:
				c.penalty += 30.0
				c.finish_t += 30.0
			if is_wec() and int(drive_limits()["min_each"]) > 0 and c.drivers.size() >= 2:
				for di in c.drivers.size():
					if di < c.drv_laps.size() and int(c.drv_laps[di]) < int(drive_limits()["min_each"]):
						c.penalty += 60.0
						c.finish_t += 60.0
						event("%s %s 최소 주행 시간(르망 6시간) 미달 → 60초 페널티" % [name_of(c), c.drivers[di]["name"]], "bad")
			if min_drive != null and min_drive_short(c) > 0:
				c.min_drive_fail = true
				c.penalty += 60.0
				c.finish_t += 60.0
				event("%s %s 최소 주행 시간 미달 → 60초 페널티" % [name_of(c), GRADE_KO.get(min_drive["grade"], "")], "bad")
			if not finishing:
				finishing = true
				event("체커기! %s 우승" % (c.label if is_wec() else c.code))
			return
		c.sec = 0
		if c.boxing != null:
			apply_pit(c)
		else:
			c.pit_phase = 0
		if rnd() < (1.0 - c.rel) * K["fail"] * (1.3 if c.pace == "attack" else 1.0) * (1.2 if night else 1.0):
			if is_wec():
				damage(c, "고장")
				if c.dnf != "":
					return
			else:
				retire(c, "고장")
				return
	elif c.started:
		c.sec += 1
		c.pit_phase = 0
		if c.sec == NS - 1 and c.boxing == null:
			var d: Variant = pit_decision(c)
			if d != null:
				c.boxing = d
				# 피트 크루 숙련도(기본 0.85, 훈련센터 Lv당 +0.025): Lv5면 정차 약 0.8초 단축
				if is_wec():
					c.pit_total = wec_stop_time(c, d["tyres"], d.get("driver", false), d.get("fuel", true))
				else:
					c.pit_total = pit_loss() + gauss(0.6) - (c.crew - 0.85) * 8.0
					c.pit_total += _crew_error(c)
	c.started = true
	schedule_next(c, t)


func apply_pit(c) -> void:
	if c.boxing != null and not c.boxing.get("forced", false):
		# 피트레인 과속 · 언세이프 릴리스 (드물게, 크루 실력이 낮을수록)
		if rnd() < 0.004:
			add_penalty(c, 5.0, "피트레인 과속")
		else:
			var busy := false
			for o in cars:
				if o != c and o.pit_phase == 2 and o.is_running():
					busy = true
					break
			if busy and rnd() < 0.02 * (1.25 - c.crew):
				add_penalty(c, 5.0, "언세이프 릴리스")
		var pr: Variant = predict_pit(c)
		var pr_green: int = int(pr["pos"]) if pr != null else class_pos(c)
		if sc and pr != null:
			_force_green = true
			var pg: Variant = predict_pit(c)
			_force_green = false
			if pg != null:
				pr_green = int(pg["pos"])
		c.pit_log.append({"lap": c.lap + 1, "pos": class_pos(c), "from": c.comp, "to": c.boxing["comp"] if c.boxing["tyres"] else c.comp, "tyres": bool(c.boxing["tyres"]), "sc": sc_kind if sc else "",
			"pred": int(pr["pos"]) if pr != null else class_pos(c), "pred_green": pr_green})
	c.covering = false
	c.stint_start_lap = c.lap + 1
	c.stint_start_wear = 0.0
	var d: Dictionary = c.boxing
	c.boxing = null
	c.pit_phase = 2
	c.pit_lap = true
	c.pits += 1
	c.pit_req = ""
	c.crew_out = false
	c.pit_total += c.garage
	c.garage = 0.0
	if d["tyres"]:
		c.comp = d["comp"]
		c.used[c.comp] = true
		c.wear = 0.0
		c.used_set_pen = 0.0
		if c.mine and c.tyre_sets != null and SLICK.has(c.comp) and not is_wec():
			if c.tyre_sets[c.comp] > 0:
				c.tyre_sets[c.comp] -= 1
			else:
				c.used_set_pen = 0.45
		c.tt = 0.35
		if is_wec():
			# 타이어 워머 금지: 차가운 새 타이어로 나간다 (하드일수록·밤일수록 더 차갑다)
			c.tt = float(WEC_COLD_TT.get(c.comp, 0.3)) - (0.04 if night else 0.0)
			if SLICK.has(c.comp):
				if c.wec_sets > 0:
					c.wec_sets -= 1
				else:
					c.wear = 0.34 # 새 세트가 없으면 이전에 쓴 세트를 다시 낀다
					if c.mine:
						say(c, "새 드라이 세트가 없어 쓰던 세트를 다시 끼웠어요")
		c.stint_laps = 0
		c.stint_tyre = 0
	elif not d.get("forced", false):
		c.stint_tyre += 1
	var acts: Array = []
	if d["tyres"]:
		acts.append(TYRE_KO[c.comp] + " 장착")
	if is_wec() and not d.get("forced", false):
		if d.get("fuel", true):
			c.fuel = TANK
			acts.append("연료 급유")
		if d.get("driver", false):
			c.drv = (c.drv + 1) % c.drivers.size()
			apply_driver(c)
			c.stint_drv = 0
			c.drive_warned = -1
			acts.append(c.name + " 교대")
		else:
			c.stint_drv += 1
	if c.mine and d["tyres"]:
		make_plans(c)
	if c.mine:
		if d.get("forced", false):
			say(c, "수리 끝. 다시 나갑니다")
		else:
			say(c, "박스 완료 (%s)" % (" · ".join(acts) if not acts.is_empty() else "점검"))


func _same_class_ahead(c, k: int, t: float) -> Array:
	var ahead: Variant = null
	var ahead_t = -INF
	for o in cars:
		if o == c or o.dnf != "" or o.cls != c.cls:
			continue
		if o.cross.size() > k:
			var ot: float = o.cross[k]
			if ot <= t and ot > ahead_t:
				ahead_t = ot
				ahead = o
	return [ahead, ahead_t]


func is_pitting(c) -> bool:
	return c.pit_phase == 2 or (c.boxing != null and c.sec == NS - 1)


## 다음 섹터 통과 시각을 예약한다 (추월·DRS·세이프티카 포함).
func schedule_next(c, t: float) -> void:
	var k: int = c.cross.size() - 1
	var r0 = _same_class_ahead(c, k, t)
	var ahead = r0[0]
	var ahead_t: float = r0[1]
	var behind_gap: Variant = null
	if k > 0:
		for o in cars:
			if o == c or o.dnf != "" or o.cls != c.cls or o.cross.size() <= k - 1:
				continue
			var g: float = o.cross[k - 1] - c.cross[k - 1]
			if g > 0 and (behind_gap == null or g < behind_gap):
				behind_gap = g
	var gap: Variant = (t - ahead_t) if ahead != null else null
	ai_control(c, gap, behind_gap)
	c.drs = false
	var dur = 0.0
	var pitting = is_pitting(c)
	if sc:
		var sh: float = T.share[c.sec]
		var car_in_front: Variant = null
		var best_cross = -INF
		var best_next = -INF
		for o in cars:
			if o == c or not o.is_running() or not o.started or is_pitting(o):
				continue
			if o.cross.size() <= k:
				continue
			var ot: float = o.cross[k]
			if ot < t or (ot == t and o.sec_end > t):
				var nx_t: float = o.cross[k + 1] if o.cross.size() > k + 1 else o.sec_end
				if ot > best_cross or (ot == best_cross and nx_t > best_next):
					best_cross = ot
					best_next = nx_t
					car_in_front = o
		if sc_kind == "SC":
			var lead_pace = float(CIRC["base"]) * sh * 1.58
			# SC 중엔 모든 클래스가 감속 구간 속도 이하로만 대열을 따라잡는다 (GT3 포함)
			var catchup = float(CIRC["base"]) * float(CLASS_PACE.get(c.cls, 1.0)) * sh * 1.22
			if car_in_front == null:
				dur = lead_pace
			else:
				var fx: float = car_in_front.cross[k + 1] if car_in_front.cross.size() > k + 1 else car_in_front.sec_end
				dur = maxf(catchup, fx + 0.35 - t)
		else:
			dur = lap_base(c) * sh * 1.35 + gauss(0.02)
			if car_in_front != null:
				var fx2: float = car_in_front.cross[k + 1] if car_in_front.cross.size() > k + 1 else car_in_front.sec_end
				dur = maxf(dur, fx2 + 0.35 - t)
		c.wear = minf(1.0, c.wear + float(COMP[c.comp][1]) * 0.25 * c.tyre_deg_rate * sh)
		c.fuel -= FPL * 0.55 * c.fuel_burn_rate * sh
		c.ers = clampf(c.ers + 0.3 * sh, 0.0, 1.0)
		c.tt = clampf(c.tt + (0.35 - c.tt) * 0.3, 0.0, 1.0)
	else:
		var rs: bool = restart and c.sec == 0
		var r = sector_time(c, gap, behind_gap, rs)
		dur = r["t"]
		if r["crash"] != "":
			c.sec_start = t
			c.sec_end = t + dur * 0.5
			c.sec_base = c.sec_end - t
			c.pending_crash = r["crash"]
			return
		if c.damage_now != "":
			var why: String = c.damage_now
			c.damage_now = ""
			damage(c, why)
			if c.dnf != "":
				c.sec_start = t
				c.sec_end = t + 0.1
				c.sec_base = 0.1
				return
		if drs_on() and T.drs_secs.has(c.sec) and gap != null and gap < 1.0 and not pitting:
			dur -= 0.45
			c.drs = true
		var ahead_pitting: bool = ahead != null and is_pitting(ahead)
		if ahead != null and ahead.cross.size() == k + 1 and not ahead.finished and not ahead_pitting and not pitting:
			var ahead_dur: float = ahead.sec_end - ahead_t
			var diff: float = ahead_dur - dur
			var mate: bool = ahead.team == c.team and ahead.cls == c.cls
			var hold_mate: bool = mate and c.mine and team_order == "hold"
			var ai_swap: bool = mate and not c.mine and not ahead.mine and gap != null and gap < 1.2 and diff > 0.25 and c.strat_style != "aggressive" and laps - c.lap > 2 and rnd() < 0.35 * c.strategy
			if ai_swap:
				_tally("팀오더")
				dur = maxf(0.4, ahead.sec_end - t - 0.1)
				ahead.sec_end += 0.6
				event("팀 오더: %s → %s 순서 교체" % [ahead.code if not is_wec() else ahead.label, c.code if not is_wec() else c.label])
			elif mate and c.mine and swap_req and gap != null and gap < 2.5:
				swap_req = false
				dur = maxf(0.4, ahead.sec_end - t - 0.1)
				ahead.sec_end += 0.9
				say(c, "%s이(가) 길을 비켜줬어요" % ahead.code)
				say(ahead, "팀 오더 확인, %s에게 양보했어요" % c.code)
				event("팀 오더: %s → %s 순서 교체" % [ahead.code, c.code])
			elif c.instr == "hold" or hold_mate or is_yellow(c.sec):
				dur = maxf(dur, (ahead.sec_end - t) + (0.5 if hold_mate else 1.0))
			elif gap - diff < K["ot_gap"] and diff > 0:
				var p: float = float(CIRC["overtake"]) + diff * 0.8 + (c.aggr - ahead.aggr) * 0.1 + 0.08 - ahead.def_ * 0.15 + (c.wet - ahead.wet) * 0.3 * wet + (0.1 if rs else 0.0) \
					+ (0.15 if c.drs else 0.0) + (0.06 if (not is_wec() and c.ers_mode == "deploy" and c.ers > 0.02) else 0.0) + (0.08 if c.instr == "attack" else 0.0) + (ahead.wing - c.wing) * 0.02 \
					- (0.12 if ahead.instr == "defend" else 0.0) - (0.04 if (not is_wec() and ahead.ers_mode == "deploy" and ahead.ers > 0.02) else 0.0)
				p = clampf(p, 0.02, 0.9) * K["overtake_scale"]
				if rnd() < p:
					dur = maxf(0.4, (ahead.sec_end - t) - 0.15)
					c.overtakes += 1
					c.focus = clampf(c.focus + 8.0, 30.0, 100.0)
					ahead.focus = clampf(ahead.focus - 5.0, 30.0, 100.0)
					if c.mine:
						say(c, "%s 추월 성공!%s" % [ahead.code, " (DRS)" if c.drs else ""])
					if ahead.mine:
						say(ahead, "%s에게 추월당했어요" % c.code)
				elif rnd() < K["crash"] * c.aggr * float(PACE[c.pace][2]) * (1.0 + 2.0 * wet) * (1.6 if c.instr == "attack" else 1.0) * (1.3 if ahead.instr == "defend" else 1.0):
					if is_wec():
						damage(c, "경합 중 접촉")
						if c.dnf != "":
							c.sec_start = t
							c.sec_end = t + 0.1
							c.sec_base = 0.1
							return
						dur = maxf(dur, (ahead.sec_end - t) + K["ot_gap"])
						dur = maxf(0.5, dur)
						c.sec_base = dur
						if c.boxing != null and c.sec == NS - 1:
							dur += c.pit_total * 0.35
						if c.pit_phase == 2:
							dur += c.pit_total * 0.65
						c.sec_start = t
						c.sec_end = t + dur
						return
					c.sec_start = t
					c.sec_end = t + dur * 0.5
					c.sec_base = c.sec_end - t
					c.pending_crash = "충돌"
					if rnd() < K["victim"]:
						ahead.pending_victim = true
					return
				else:
					dur = maxf(dur, (ahead.sec_end - t) + K["ot_gap"])
	dur = maxf(0.5, dur)
	c.sec_base = dur
	# 피트 시간: 입구까지는 마지막 섹터, 나머지는 다음 랩 첫 섹터에 분배
	if c.boxing != null and c.sec == NS - 1:
		dur += c.pit_total * 0.35
	if c.pit_phase == 2:
		dur += c.pit_total * 0.65
	c.sec_start = t
	c.sec_end = t + dur


func leader_car() -> Variant:
	for c in order():
		if c.is_running() and c.started and c.pit_phase == 0 and not (c.boxing != null and c.sec == NS - 1):
			return c
	return null


func car_frac(c) -> float:
	return clampf((clock - c.sec_start) / maxf(0.01, c.sec_end - c.sec_start), 0.0, 1.0)


func car_dist(c) -> float:
	return c.lap * T.L + T.dist_at(c.sec, car_frac(c))


func on_leader_lap() -> void:
	var l = leader_lap
	if sc:
		sc_laps.append(l)
	var tgt = 0.0
	if rain != null and l >= rain["start"] and l < rain["end"]:
		tgt = rain["level"]
	var prev_kind = ideal_tyre(wet)
	wet = clampf(wet + (tgt - wet) * (0.35 if tgt > wet else 0.15), 0.0, 1.0)
	if wet >= 0.25:
		ever_wet = true
	if wet > 0.15:
		track_evo = maxf(0.05, track_evo - wet * 0.25)
	else:
		track_evo = minf(1.0, track_evo + (1.0 / maxf(8.0, laps)) * 0.85)
	if rain != null and l == rain["start"]:
		event("비가 내리기 시작했어요. 노면이 젖고 있습니다", "wet")
	var nk = ideal_tyre(wet)
	if nk != prev_kind:
		event("노면 변화: 이제 %s 타이어가 맞아요" % ("슬릭" if nk == "slick" else TYRE_KO[nk]), "wet")
	if wet > 0.85 and not sc and rnd() < 0.25:
		deploy("SC")
	if CIRC.has("night") and CIRC["night"] != null:
		var prog = float(l) / laps
		var n: bool = prog >= float(CIRC["night"][0]) and prog < float(CIRC["night"][1])
		if n != night:
			night = n
			event("해가 졌습니다. 야간 주행 시작" if n else "날이 밝았습니다")
	restart = false
	if sc and l == sc_end_lap - 1 and not sc_in_notified:
		sc_in_notified = true
		event("[%s 종료 예고] 이번 랩 끝에 세이프티카가 들어갑니다!" % sc_kind, "sc")
		for c in cars:
			if c.mine and c.is_running():
				say(c, "이번 랩 끝에 SC 들어갑니다! 리스타트 준비!")
	if sc and l >= sc_end_lap:
		var prev_k = sc_kind
		sc = false
		sc_dist = -1.0
		sc_in_notified = false
		sc_in_pit_lane = false
		sc_pit_prog = 0.0
		restart = true
		# 현재 위치는 그대로 두고 남은 구간 속도만 레이스 속도로 전환 (순간이동 없는 롤링 리스타트)
		var base_t = clock
		var prev_end = -INF
		var prev_sec = -1
		var prev_lap = -1
		for car in order():
			if not car.is_running() or not car.started or is_pitting(car):
				continue
			var f = clampf(car_frac(car), 0.0, 0.95)
			var normal = maxf(1.0, lap_base(car) * T.share[car.sec])
			var rem = maxf(0.4, (1.0 - f) * normal)
			var new_end = base_t + rem
			if car.lap == prev_lap and car.sec == prev_sec and new_end < prev_end + 0.28:
				new_end = prev_end + 0.28
			car.sec_start = new_end - normal
			car.sec_end = new_end
			car.sec_base = normal
			prev_end = new_end
			prev_sec = car.sec
			prev_lap = car.lap
		event("%s 종료 · 그린 플래그! 레이스 재개" % prev_k, "green")
	# 내 차 무전
	for c in cars:
		if not c.mine or not c.is_running():
			continue
		var left: int = laps - c.lap
		var it = ideal_tyre(wet)
		if kind_of(c.comp) != (it if it != "slick" else "slick"):
			say(c, "라인이 말랐어요. 슬릭으로 바꿔야 해요" if it == "slick" else "노면이 젖었어요. %s 필요해요" % TYRE_KO[it])
			if not c.auto_plan:
				trigger_radio(c, "WET")
		elif not is_wec() and left > 0 and c.lap >= 2 and c.fuel < left * FPL * float(FUEL[c.fuel_mode][1]) * c.fuel_burn_rate - FPL * 0.3:
			# 드라이버 연비까지 반영해 계산. 연비 모드로도 못 버티면 강하게, 아니면 얼마나 모자란지 알려준다
			var short_std: float = (left * FPL * float(FUEL[c.fuel_mode][1]) * c.fuel_burn_rate - c.fuel) / (FPL * c.fuel_burn_rate)
			var short_lean: float = (left * FPL * float(FUEL["lean"][1]) * c.fuel_burn_rate - c.fuel) / (FPL * c.fuel_burn_rate)
			if short_lean > 0.1:
				say(c, "연료가 %.1f랩분 모자라요! 연비 모드에 리프트 앤 코스트까지 써야 해요" % short_std)
			elif c.fuel_mode != "lean":
				say(c, "지금 페이스면 연료가 %.1f랩분 모자라요. 'ERS·연료' 탭에서 세이브로 바꿔주세요" % short_std)
		elif c.wear > 0.7 or (c.comp == "H" and c.wear > H_CLIFF):
			say(c, "타이어가 다 됐어요 (%d%%)" % int(round(c.wear * 100)))
			if not c.auto_plan and c.pit_req == "" and c.boxing == null:
				trigger_radio(c, "WORN")
		elif c.tt > 0.82:
			say(c, "타이어가 과열됐어요. 페이스 좀 낮출게요?")
		elif is_wec() and c.stint_drv >= 2:
			say(c, "%s: 세 번째 스틴트라 집중력이 떨어져요" % c.name)
		elif not is_wec() and c.ers < 0.1 and c.ers_mode == "deploy":
			say(c, "배터리가 바닥이에요")
		elif need_two() and left <= 4 and c.used_slicks() < 2:
			say(c, "아직 두 번째 컴파운드를 안 썼어요! 안 바꾸면 30초 페널티예요")


# ═════════ 시뮬레이션 진행 ═════════
## 시뮬레이션 시간을 dt초 진행한다. 이 구간에 끝나는 섹터들을 시간 순서대로 처리한다.
func advance(dt: float) -> void:
	if done:
		return
	var target = clock + dt
	for _guard in 2000:
		var next: Variant = null
		var nt = INF
		for c in cars:
			if not c.is_running():
				continue
			var tt: float = c.sec_end if c.started else c.start_t
			if tt < nt:
				nt = tt
				next = c
		if next == null or nt > target:
			break
		clock = maxf(clock, nt)
		if next.pending_crash != "":
			var why: String = next.pending_crash
			next.pending_crash = ""
			retire(next, why)
			continue
		if next.pending_victim:
			next.pending_victim = false
			retire(next, "충돌")
			continue
		on_cross(next, clock)
	clock = target
	# 시간 역행·정체 방지
	for c in cars:
		if c.is_running() and c.started and c.sec_end < clock:
			var d = maxf(0.4, c.sec_base if c.sec_base > 0 else 1.0)
			c.sec_start = clock
			c.sec_end = clock + d
	# 세이프티카 위치: 항상 선두차 바로 앞에서 대열을 이끈다
	if sc and sc_kind == "SC" and sc_dist >= 0.0:
		var lead: Variant = leader_car()
		var v_sc: float = T.L / (float(CIRC["base"]) * 1.56)
		if lead != null:
			var target_d: float = car_dist(lead) + T.L * 0.022
			if sc_wait:
				# 피트 출구에서 나와 느리게 달리며 선두를 기다림
				if sc_dist - target_d <= T.L * 0.004:
					sc_wait = false
				else:
					sc_dist += dt * v_sc * 0.45
			if not sc_wait:
				if sc_dist < target_d:
					sc_dist = minf(target_d, sc_dist + dt * v_sc * 1.6)
				else:
					sc_dist = maxf(target_d, sc_dist + dt * v_sc * 0.85 + (target_d - sc_dist) * minf(1.0, dt * 3.5))
			if sc_in_notified and lead.sec == NS - 1:
				var lf = car_frac(lead)
				if lf >= T.entry_frac * 0.75:
					sc_in_pit_lane = true
					sc_pit_prog = clampf((lf - T.entry_frac * 0.75) / maxf(0.05, 1.0 - T.entry_frac * 0.75), 0.0, 1.0)
				else:
					sc_in_pit_lane = false
			else:
				sc_in_pit_lane = false
		else:
			sc_dist += dt * v_sc
	if finishing and alive().is_empty():
		done = true


func _cmp(a, b) -> int:
	var ad: bool = a.dnf != ""
	var bd: bool = b.dnf != ""
	if ad != bd:
		return 1 if ad else -1
	if ad and bd:
		return b.cross.size() - a.cross.size()
	if a.finished and b.finished:
		if b.lap != a.lap:
			return b.lap - a.lap
		return -1 if a.finish_t < b.finish_t else (1 if a.finish_t > b.finish_t else 0)
	if a.finished != b.finished:
		var f = a if a.finished else b
		var o = b if a.finished else a
		var r = -1 if f.lap >= o.lap else 1
		return r if a.finished else -r
	if b.cross.size() != a.cross.size():
		return b.cross.size() - a.cross.size()
	var na: float = a.sec_end if a.started else a.start_t
	var nb: float = b.sec_end if b.started else b.start_t
	if na != nb:
		return -1 if na < nb else 1
	return a.grid - b.grid


## 현재 순위 (실제 시뮬레이션 기준: 더 많은 경계를 지났고, 같다면 다음 경계에 먼저 도착할 차가 앞)
func order() -> Array:
	var arr = cars.duplicate()
	arr.sort_custom(func(a, b): return _cmp(a, b) < 0)
	return arr


func gap_to(c, ref) -> String:
	var ci: int = c.cross.size() - 1
	var ri: int = ref.cross.size() - 1
	if ci < 0 or ri < 0:
		return ""
	var lb = int(floor(float(ri - ci) / NS))
	if lb >= 1:
		return "+%dL" % lb
	if ci >= ref.cross.size():
		return ""
	var d = maxf(0.0, c.cross[ci] - ref.cross[ci])
	return "+%.1f" % d


func gap_seconds(c, ref) -> float:
	var ci: int = c.cross.size() - 1
	if ci < 0 or ref.cross.size() <= ci:
		return 0.0
	return maxf(0.0, c.cross[ci] - ref.cross[ci])


# ═════════ 플레이어 지시 ═════════
func request_pit(c, comp: String) -> void:
	if not c.is_running():
		return
	if c.boxing != null:
		return # 이미 피트 진입 확정 (마지막 섹터)
	c.pit_req = comp
	say(c, "박스 지시 확인: %s 준비" % TYRE_KO[comp])


func cancel_pit(c) -> void:
	if c.pit_req != "" and c.boxing == null:
		c.pit_req = ""
		say(c, "박스 취소 확인")


func set_pace(c, p: String) -> void:
	c.pace = p


func set_ers(c, m: String) -> void:
	c.ers_mode = m


func my_cars() -> Array:
	var out = []
	for c in cars:
		if c.mine:
			out.append(c)
	out.sort_custom(func(a, b): return a.slot < b.slot)
	return out


# ═════════ 화면용 위치 계산 ═════════
func _stall_u(idx: int) -> float:
	var n: int = T.pit_idx.size() - 1
	var nn = maxi(1, n_stalls)
	return n * (0.14 + 0.74 * (0.5 if nn <= 1 else float(idx) / (nn - 1)))


func _lane_u(g: float, stall: float) -> float:
	var n: float = T.pit_idx.size() - 1
	var sf = stall / n
	var a = 0.5 * sf
	var b = a + 0.5
	if g < a:
		return stall * (g / maxf(0.001, a))
	if g < b:
		return stall
	return stall + (n - stall) * clampf((g - b) / maxf(0.001, 1.0 - b), 0.0, 1.0)


## 차의 화면 위치 [Vector2, 방향]. 출발 전 그리드, 피트레인 진입·정차·출구를 모두 처리한다.
func car_pos_angle(c) -> Array:
	if not c.started:
		var grid_d = -(c.grid + 1) * T.L * (0.0035 if is_wec() else 0.0048)
		if c.start_t <= 0.0:
			return [T.point_at_dist(grid_d), T.head_at_dist(grid_d)]
		var prog = clampf(clock / maxf(0.01, c.start_t), 0.0, 1.0)
		var dv = grid_d * (1.0 - prog)
		return [T.point_at_dist(dv), T.head_at_dist(dv)]
	var e: float = clock - c.sec_start
	var base = maxf(0.01, c.sec_base)
	var total = maxf(0.01, c.sec_end - c.sec_start)
	var stall = _stall_u(c.stall_idx)
	if c.boxing != null and c.sec == NS - 1:
		var t_entry: float = base * T.entry_frac
		if e <= t_entry:
			var f = e / base
			return [T.point_at(c.sec, f), T.head_at_dist(T.dist_at(c.sec, f))]
		var u = clampf((e - t_entry) / maxf(0.01, total - t_entry), 0.0, 1.0)
		return T.pit_lane_point(_lane_u(0.35 * u, stall))
	if c.pit_phase == 2 and c.sec == 0:
		var t_out: float = base * T.exit_frac
		var lane: float = total - (base - t_out)
		if e < lane:
			return T.pit_lane_point(_lane_u(0.35 + 0.65 * (e / maxf(0.01, lane)), stall))
		var f_out: float = T.exit_frac + (1.0 - T.exit_frac) * clampf((e - lane) / maxf(0.01, base - t_out), 0.0, 1.0)
		return [T.point_at(0, f_out), T.head_at_dist(T.dist_at(0, f_out))]
	var fr = e / total
	return [T.point_at(c.sec, fr), T.head_at_dist(T.dist_at(c.sec, fr))]


## 세이프티카 화면 위치 (없으면 빈 배열)
func sc_pos_angle() -> Array:
	if not sc or sc_kind != "SC" or sc_dist < 0.0:
		return []
	if sc_in_pit_lane:
		return T.pit_lane_point(_lane_u(0.35 * sc_pit_prog, _stall_u(0)))
	return [T.point_at_dist(sc_dist), T.head_at_dist(sc_dist)]


# ═════════ 결과 ═════════
## 결과: 클래스별 순위와 포인트 (F1 은 클래스가 하나). pos = 클래스 내 순위
func results() -> Array:
	var out = []
	var ord = order()
	var cls_pos := {}
	var winners := {}
	for c in ord:
		if not winners.has(c.cls):
			winners[c.cls] = c
	for c in ord:
		cls_pos[c.cls] = int(cls_pos.get(c.cls, 0)) + 1
		var pos: int = cls_pos[c.cls]
		var winner = winners[c.cls]
		var gap = ""
		if c.dnf != "":
			gap = "DNF (%s)" % c.dnf
		elif c == winner:
			gap = "%d:%04.1f" % [int(c.finish_t) / 60, fmod(c.finish_t, 60.0)]
		elif c.lap < winner.lap:
			gap = "+%d랩" % (winner.lap - c.lap)
		else:
			gap = "+%.1f초" % (c.finish_t - winner.finish_t)
		var pts = 0
		var ptab: Array = rules.get("points", POINTS)
		if c.dnf == "" and pos <= ptab.size():
			pts = ptab[pos - 1]
		out.append({"pos": pos, "car": c, "gap": gap, "points": pts, "cls": c.cls})
	return out


## WEC 내 차 박스 지시: 타이어(comp) · 급유 · 드라이버 교대를 고른다
func request_pit_wec(c, comp: String, tyres: bool, fuel: bool, driver: bool) -> void:
	if not c.is_running() or c.boxing != null:
		return
	if not tyres and not fuel and not driver:
		say(c, "타이어·급유·교대 중 하나는 골라주세요")
		return
	comp = wec_fit_comp(c.cls, comp)
	c.pit_req = comp if tyres else c.comp
	c.wec_req = {"tyres": tyres, "fuel": fuel, "driver": driver}
	var parts: Array = []
	parts.append(TYRE_KO[comp] + " 교체" if tyres else "타이어 유지")
	parts.append("급유" if fuel else "급유 생략")
	if driver:
		parts.append("드라이버 교대")
	say(c, "박스 지시 확인: " + " + ".join(parts))


func set_fuel_mode(c, m: String) -> void:
	c.fuel_mode = m
	say(c, "연료 %s 모드" % WEC_FUEL_KO[m])


## 최소 주행 규정: 해당 등급 드라이버가 더 달려야 하는 랩 수 (0이면 충족)
func min_drive_short(c) -> int:
	if min_drive == null:
		return 0
	var need := int(ceil(float(min_drive["pct"]) * laps))
	var done_l := 0
	var has := false
	for i in c.drivers.size():
		if c.drivers[i].get("grade", "") == min_drive["grade"]:
			has = true
			if i < c.drv_laps.size():
				done_l += int(c.drv_laps[i])
	if not has:
		return 0
	return maxi(0, need - done_l)


## 클래스 안에서의 순위 (1부터)
## 방금 통과한 경계 기준 순위: 같은 경계를 먼저 지난 같은 클래스 차 수 + 1 (통과 순간 정렬 오차 없음)
func pos_at_line(c) -> int:
	var k: int = c.cross.size() - 1
	var n := 1
	for o in cars:
		if o == c or o.cls != c.cls or o.dnf != "":
			continue
		if o.cross.size() > k and float(o.cross[k]) < float(c.cross[k]):
			n += 1
	return n


func class_pos(c) -> int:
	var n := 0
	for o in order():
		if o.cls == c.cls:
			n += 1
			if o == c:
				return n
	return n


## WEC 남은 연료로 달릴 수 있는 랩 수
func fuel_laps(c) -> float:
	return maxf(0.0, c.fuel / maxf(0.01, _wec_burn(c, c.fuel_mode)))


## 출발 직전 정리 (HTML start()): 그리드 순서대로 정렬하고 반응 속도를 준다.
## 주말 모드면 내 차 출발 타이어 세트를 소모한다(예선 최종 세션 진출 차는 예선 타이어 그대로).
func prepare_start() -> void:
	cars.sort_custom(func(a, b): return a.grid < b.grid)
	# 그리드 강등 페널티 (파워유닛 교체 등)
	for c in cars.duplicate():
		if c.grid_pen > 0:
			var i: int = cars.find(c)
			cars.remove_at(i)
			cars.insert(mini(cars.size(), i + c.grid_pen), c)
			event("%s 그리드 %d계단 강등 (파워유닛 교체)" % [name_of(c), c.grid_pen], "bad")
			c.grid_pen = 0
	for i in cars.size():
		var c = cars[i]
		c.grid = i
		var react = clampf(0.06 - (c.speed * 0.025 + c.aggr * 0.02) + gauss(0.012), 0.01, 0.09)
		if not is_wec() and react <= 0.011 and rnd() < 0.08:
			add_penalty(c, 5.0, "부정 출발")
		c.start_t = i * (0.42 if is_wec() else 0.25) + react
		c.used[c.comp] = true
		if c.mine and c.tyre_sets != null and not c.q3_locked and SLICK.has(c.comp):
			if c.tyre_sets[c.comp] > 0:
				c.tyre_sets[c.comp] -= 1
				c.used_set_pen = 0.0
			else:
				c.used_set_pen = 0.45
	for c in my_cars():
		make_plans(c)


# ═════════ 내 차 전략 계획 (A/B 플랜 · 자동 피트) ═════════
## 플레이어가 아는 마모율: 공칭값 (실제 배율은 모름). 스틴트를 3랩 이상 달렸으면 관측 마모로 보정.
func my_rates(c) -> Dictionary:
	var out := {}
	for k in SLICK:
		out[k] = float(COMP[k][1]) * float(rules.get("wear_mult", 1.0)) * float(CIRC["wear"]) * (WEAR_SCALE / laps) * 0.85 * c.tyre_deg_rate
	var done_laps: int = c.lap - c.stint_start_lap
	if done_laps >= 3 and SLICK.has(c.comp):
		var obs: float = (c.wear - c.stint_start_wear) / float(done_laps)
		var scl: float = clampf(obs / maxf(1e-4, float(out[c.comp])), 0.6, 1.7)
		for k in out:
			out[k] = float(out[k]) * scl
	return out


## 남은 랩 기준으로 계획 A(최적)와 B(스톱 수가 다른 차선책)를 다시 계산한다.
func make_plans(c) -> void:
	if c.custom_plans:
		_use_plan(c)
		return
	# 지금 고른 계획의 남은 스톱 수 (재계산해도 같은 스톱 수를 유지해서 B가 스톱을 계속 늘리지 않게)
	var keep_n: int = c.plan["stops"].size() - c.stops_done if not c.plans.is_empty() else -1
	var was: String = c.active_plan
	c.plans = {}
	c.plan["stops"] = c.plan["stops"].slice(0, c.stops_done)
	if is_wec() or rules.get("no_pits", false) or wet > 0.05 or not SLICK.has(c.comp):
		return
	var left: int = laps - c.lap
	if left < 3:
		return
	var max_st: int = 3 if left >= 12 else 2
	var sets: Dictionary = {"S": 9, "M": 9, "H": 9}
	if c.tyre_sets != null:
		sets = {"S": int(c.tyre_sets["S"]), "M": int(c.tyre_sets["M"]), "H": int(c.tyre_sets["H"])}
	var cands: Array = ai_optimize(left, c.comp, c.wear, my_rates(c), pit_loss() + 3.0, c.used, sets, max_st)
	if cands.is_empty():
		cands = ai_optimize(left, c.comp, c.wear, my_rates(c), pit_loss() + 3.0, c.used, {"S": 9, "M": 9, "H": 9}, max_st)
	if cands.is_empty():
		return
	var a: Dictionary = cands[0]
	var b: Variant = null
	var keep_b: bool = was == "B" and keep_n >= 0
	if keep_b:
		# B를 쓰는 중이면 남은 스톱 수가 같은 계획 중 A가 아닌 최선 (스톱이 계속 늘지 않게)
		for x in cands:
			if x != a and x["cuts"].size() == keep_n:
				b = x
				break
	if b == null and not keep_b:
		for x in cands:
			if x["cuts"].size() != a["cuts"].size():
				b = x
				break
	if b == null and not keep_b and cands.size() > 1:
		b = cands[1]
	c.plans["A"] = _abs_plan(c, a)
	if b != null:
		c.plans["B"] = _abs_plan(c, b)
	if not c.plans.has(c.active_plan):
		c.active_plan = "A"
	_use_plan(c)


func _abs_plan(c, x: Dictionary) -> Dictionary:
	var stops: Array = []
	for i in x["cuts"].size():
		stops.append({"lap": clampi(c.lap + int(x["cuts"][i]), c.lap + 1, laps - 1), "comp": x["seq"][i + 1]})
	return {"stops": stops, "cost": float(x["cost"])}


func _use_plan(c) -> void:
	var p: Variant = c.plans.get(c.active_plan)
	if p == null:
		return
	if c.custom_plans:
		# 직접 짠 계획은 레이스 전체 기준 랩이라 그대로 쓴다 (stops_done 이 진행 위치)
		c.plan = {"start": c.plan.get("start", c.comp), "stops": p["stops"].duplicate(true)}
		return
	var done: Array = c.plan["stops"].slice(0, c.stops_done)
	c.plan = {"start": c.plan.get("start", c.comp), "stops": done + p["stops"]}


## 직접 짠 계획에서 스톱이 늦어지면 뒤의 스톱도 그만큼 미룬다 (HTML pitDecision 과 같음)
func _shift_custom(c, late: int) -> void:
	if not c.custom_plans or late <= 0:
		return
	for key in c.plans:
		var st: Array = c.plans[key]["stops"]
		for j in range(c.stops_done, st.size()):
			st[j]["lap"] = mini(laps - 1, int(st[j]["lap"]) + late)
	_use_plan(c)


## 계획 평가: 남은 레이스를 이 계획대로 달렸을 때 예상 손실(초)과 스틴트별 끝 마모·경고.
## stops: [{lap, comp}] (레이스 전체 기준 랩). 레이스 전(c.lap = 0)에도 쓸 수 있다.
func eval_plan(c, stops: Array) -> Dictionary:
	var rates := my_rates(c)
	var comp: String = c.comp
	var prev: int = c.lap
	var w0: float = c.wear
	var cost := 0.0
	var stints: Array = []
	var warn: Array = []
	var used := {}
	for k in c.used:
		used[k] = true
	used[comp] = true
	var need := {"S": 0, "M": 0, "H": 0}
	if not c.started and not c.q3_locked and need.has(comp):
		need[comp] = 1 # 출발 타이어도 아직 새 세트 하나를 쓴다
	var seq: Array = stops.duplicate(true)
	seq.append({"lap": laps, "comp": ""})
	for i in seq.size():
		var end_l: int = clampi(int(seq[i]["lap"]), prev + 1, laps)
		var n: int = end_l - prev
		var r: float = float(rates.get(comp, 0.05))
		var ew: float = w0 + r * n
		cost += ai_stint_cost(comp, n, w0, r) if SLICK.has(comp) else 0.0
		stints.append({"comp": comp, "from": prev + 1, "to": end_l, "laps": n, "end_wear": ew, "cliff": ew > ai_lim(comp)})
		if SLICK.has(comp) and ew > ai_lim(comp) + 0.05:
			warn.append("%s 스틴트 끝 마모 %d%% → 절벽 위험" % [TYRE_KO[comp], int(round(ew * 100))])
		if String(seq[i]["comp"]) == "":
			break
		cost += pit_loss() + 3.0
		prev = end_l
		comp = seq[i]["comp"]
		w0 = 0.0
		used[comp] = true
		if need.has(comp):
			need[comp] = int(need[comp]) + 1
	if need_two():
		var n_sl := 0
		for k in ["S", "M", "H"]:
			if used.has(k):
				n_sl += 1
		if n_sl < 2:
			cost += 30.0
			warn.append("슬릭 두 종류 미사용 → 30초 페널티")
	if c.tyre_sets != null:
		for k in ["S", "M", "H"]:
			if int(need[k]) > int(c.tyre_sets[k]):
				warn.append("새 %s 세트 부족 (헌 타이어 +0.45초/랩)" % TYRE_KO[k])
	return {"cost": cost, "stints": stints, "warn": warn}


## 플레이어가 직접 짠 계획 A/B 를 적용 {"A": [stops], "B": [stops]}
func set_custom_plans(c, plans_in: Dictionary) -> void:
	c.plans = {}
	for key in plans_in:
		var st: Array = (plans_in[key] as Array).duplicate(true)
		st.sort_custom(func(a, b): return int(a["lap"]) < int(b["lap"]))
		c.plans[key] = {"stops": st, "cost": float(eval_plan(c, st)["cost"])}
	c.custom_plans = true
	if not c.plans.has(c.active_plan):
		c.active_plan = "A"
	c.stops_done = 0
	_use_plan(c)


## 직접 짠 계획을 버리고 최적 계산으로 되돌린다
func reset_plans(c) -> void:
	c.custom_plans = false
	c.plans = {}
	make_plans(c)


func set_plan(c, key: String) -> void:
	if not c.plans.has(key):
		return
	c.active_plan = key
	_use_plan(c)


func set_auto(c, on: bool) -> void:
	c.auto_plan = on
	if on and c.plans.is_empty():
		make_plans(c)
	say(c, "자동 전략 켬: 계획 %s 대로 박스할게요" % c.active_plan if on else "자동 전략 끔: 박스는 직접 지시해 주세요")


func set_instr(c, v: String) -> void:
	c.instr = v


## 계획 요약 문자열 (UI용): "L9 H → L15 M"
func plan_text(c, key: String) -> String:
	var p: Variant = c.plans.get(key)
	if p == null:
		return ""
	if p["stops"].is_empty():
		return "노스톱"
	var parts: PackedStringArray = []
	for st in p["stops"]:
		parts.append("L%d %s" % [int(st["lap"]), st["comp"]])
	return " → ".join(parts)


func _my_auto_decision(c, cur: int, left: int, want: String) -> Variant:
	if c.pit_req != "" or c.boxing != null:
		return null
	var have = kind_of(c.comp)
	var ns: Variant = next_stop(c)
	if want != have:
		var nw: String = want
		if want == "slick":
			nw = String(ns["comp"]) if ns != null else ("M" if left > 8 else "S")
		var lose: float = weather_pen(c.comp, wet) - weather_pen(nw, wet)
		if lose * minf(left, 5) > pit_loss():
			c.crew_out = true
			say(c, "자동 전략: 노면이 바뀌었어요 → %s 로 박스" % TYRE_KO[nw])
			return {"comp": nw, "tyres": true}
		return null
	if rules.get("no_pits", false) or not SLICK.has(c.comp):
		return null
	if ns == null:
		if need_two() and left <= 3 and c.used_slicks() < 2:
			c.crew_out = true
			var alt := _alt_slick(c.comp)
			say(c, "자동 전략: 두 번째 컴파운드 의무 → %s 로 박스" % TYRE_KO[alt])
			return {"comp": alt, "tyres": true}
		return null
	if cur >= int(ns["lap"]) or (sc and int(ns["lap"]) - cur <= 3 and c.wear >= 0.3):
		c.stops_done += 1
		_shift_custom(c, cur - int(ns["lap"]))
		c.crew_out = true
		say(c, "자동 전략 %s: 박스 → %s%s" % [c.active_plan, TYRE_KO[ns["comp"]], " (SC 활용)" if sc and cur < int(ns["lap"]) else ""])
		return {"comp": ns["comp"], "tyres": true}
	return null


# ═════════ 엔지니어 제안 (선택형 무전) ═════════
func trigger_radio(c, kind: String) -> void:
	if not prompts_enabled or done or not c.mine or not c.is_running() or active_radio != null:
		return
	var key := "%d:%s" % [c.id, kind]
	if iradio_done.has(key):
		return
	iradio_done[key] = true
	var who: String = ("#%d %s" % [c.slot + 1, c.code]) if is_wec() else c.code
	var it: String = ideal_tyre(wet)
	var rec: String = "M" if it == "slick" else it
	var pr: Variant = null
	if kind == "WET":
		pr = {"title": "📻 [%s 무전] 노면 변화 감지" % who, "msg": "“노면이 급변했어요! 지금 %s 타이어로 박스할까요, 트랙에서 버틸까요?”" % TYRE_KO[rec],
			"opts": [{"label": "이번 랩 %s 박스" % TYRE_KO[rec], "act": "BOX", "comp": rec}, {"label": "세이브하며 버티기", "act": "SAVE"}, {"label": "페이스 강행", "act": "PUSH"}]}
	elif kind == "WORN":
		var rw: String = ("H" if laps - c.lap > 7 else "M") if it == "slick" else it
		pr = {"title": "📻 [%s 무전] 타이어 한계 (%d%%)" % [who, int(round(c.wear * 100))], "msg": "“그립이 거의 다 떨어졌어요! 새 %s로 바꿀까요, 아끼면서 버틸까요?”" % TYRE_KO[rw],
			"opts": [{"label": "이번 랩 %s 박스" % TYRE_KO[rw], "act": "BOX", "comp": rw}, {"label": "타이어 세이브", "act": "SAVE"}, {"label": "그대로 버텨", "act": "IGNORE"}]}
	elif kind == "SC":
		pr = {"title": "📻 [%s 엔지니어 제안] %s 피트 찬스" % [who, sc_kind], "msg": "“%s 중이라 피트 손실이 크게 줄어요! 지금 %s 타이어로 갈아낄까요?”" % [sc_kind, TYRE_KO[rec]],
			"opts": [{"label": "즉시 박스 (%s)" % TYRE_KO[rec], "act": "BOX", "comp": rec}, {"label": "트랙 포지션 유지", "act": "IGNORE"}]}
	elif kind == "MECH":
		pr = {"title": "📻 [%s 긴급 무전] %s" % [who, c.mech_trouble], "msg": "“%s 수치가 위험해요! 리프트 앤 코스트로 식힐까요?”" % c.mech_trouble,
			"opts": [{"label": "리프트 앤 코스트", "act": "LIFT"}, {"label": "페이스 세이브", "act": "SAVE"}, {"label": "무시하고 푸시", "act": "PUSH"}]}
	if pr == null:
		return
	pr["slot"] = c.slot
	pr["car_id"] = c.id
	active_radio = pr
	radio_seq += 1


func resolve_radio(idx: int) -> void:
	if active_radio == null:
		return
	var pr: Dictionary = active_radio
	active_radio = null
	var c: Variant = null
	for m in my_cars():
		if m.id == int(pr["car_id"]):
			c = m
	var opts: Array = pr["opts"]
	if c == null or idx < 0 or idx >= opts.size() or not c.is_running():
		return
	var o: Dictionary = opts[idx]
	match String(o["act"]):
		"BOX":
			var comp: String = o["comp"]
			if c.boxing != null:
				c.boxing["comp"] = comp
				c.boxing["tyres"] = true
				say(c, "이미 박스 예약됨 → 타이어만 %s로 변경" % TYRE_KO[comp])
			elif is_wec():
				request_pit_wec(c, comp, true, true, false)
			else:
				request_pit(c, comp)
			c.focus = clampf(c.focus + 5.0, 30.0, 100.0)
		"SAVE":
			c.pace = "save"
			say(c, "카피, 타이어와 온도를 아끼면서 버텨볼게요")
		"LIFT":
			c.instr = "lift"
			c.pace = "save"
			say(c, "리프트 앤 코스트 시작. 브레이크·변속기 온도를 식힐게요")
		"PUSH":
			c.pace = "attack"
			c.focus = clampf(c.focus + 4.0, 30.0, 100.0)
			say(c, "알겠어요! 끝까지 밀어붙입니다")
		_:
			say(c, "카피, 지금 상태 그대로 갈게요")


# ═════════ 팀 오더 ═════════
## 시간 페널티: 체커기 때 기록에 더한다
func add_penalty(c, secs: float, why: String) -> void:
	c.time_pen += secs
	_tally("페널티")
	event("🟨 %s %d초 페널티 (%s)" % [name_of(c), int(secs), why], "bad")
	if c.mine:
		say(c, "%d초 페널티 받았어요 (%s). 앞차와 간격을 더 벌려야 해요" % [int(secs), why])


func set_team_order(v: String) -> void:
	team_order = v
	event("팀 오더: 서로 싸우지 말고 순서 유지" if v == "hold" else "팀 오더 해제: 자유 경쟁")


func request_swap() -> void:
	swap_req = true
	event("팀 오더: 다음 기회에 앞차가 팀메이트에게 양보")


# ═════════ 기상 예보 · 피트 예측 (UI용) ═════════
func forecast_wet_at(target_lap: int) -> float:
	if rain == null:
		return wet
	var w := wet
	for l in range(leader_lap + 1, target_lap + 1):
		var tgt := 0.0
		if l >= int(rain["start"]) and l < int(rain["end"]):
			tgt = float(rain["level"])
		w = clampf(w + (tgt - w) * (0.35 if tgt > w else 0.15), 0.0, 1.0)
	return w


func forecast_prob_at(target_lap: int) -> int:
	if rain != null and target_lap >= int(rain["start"]) and target_lap < int(rain["end"]):
		return mini(95, int(round(55.0 + float(rain["level"]) * 40.0)))
	if fc != null and target_lap >= int(fc["lo"]) and target_lap <= int(fc["hi"]):
		return int(fc["p"])
	return 25 if wet > 0.1 else 5


## 노면 수막(mm): 0(건조) ~ 1.2(인터 교차) ~ 3.5(웻 교차) ~ 5.5(폭우)
func wet_mm(w: float) -> float:
	return w * 5.5


func surface_ko() -> String:
	return "건조" if wet < 0.05 else ("약간 젖음" if wet < 0.25 else ("젖음" if wet < 0.65 else "흠뻑 젖음"))


## 지금 박스하면 몇 위로 복귀하는지 예측 {pos, ahead:[code, 초], behind:[code, 초], loss, under:{code, net}}
func predict_pit(c) -> Variant:
	if not c.is_running() or not c.started:
		return null
	var k: int = c.cross.size() - 1
	if k < 0:
		return null
	var loss: float = pit_loss() + 1.0
	if is_wec():
		var rq: Variant = c.wec_req if c.wec_req != null else c.boxing
		var tyres := true
		var drv := false
		var fuel := true
		if rq != null:
			tyres = bool(rq.get("tyres", true))
			drv = bool(rq.get("driver", false))
			fuel = bool(rq.get("fuel", true))
		loss = wec_stop_time(c, tyres, drv, fuel) + 1.0
	var ord: Array = []
	for o in order():
		if o.dnf == "" and o.cls == c.cls:
			ord.append(o)
	var best_a: Variant = null
	var best_b: Variant = null
	var n_ahead := 0
	for o in ord:
		if o == c:
			continue
		var d: float
		if o.cross.size() > k and float(o.cross[k]) <= float(c.cross[k]):
			d = float(c.cross[k]) - float(o.cross[k])
		else:
			var j: int = o.cross.size() - 1
			if j < 0 or j >= c.cross.size():
				continue
			d = -(float(o.cross[j]) - float(c.cross[j]))
		var after: float = d + loss
		if after > 0.0:
			n_ahead += 1
			if best_a == null or after < float(best_a[1]):
				best_a = [o, after]
		elif best_b == null or after > float(best_b[1]):
			best_b = [o, after]
	var under: Variant = null
	var i := ord.find(c)
	if not is_wec() and i > 0 and SLICK.has(c.comp):
		var front = ord[i - 1]
		if front.pit_phase == 0 and SLICK.has(front.comp) and front.cross.size() > k:
			var ns: Variant = next_stop(c)
			var nc: String = c.pit_req if c.pit_req != "" else (String(ns["comp"]) if ns != null else "M")
			if not SLICK.has(nc):
				nc = "M"
			var wr: float = float(COMP[front.comp][1]) * float(rules.get("wear_mult", 1.0)) * float(CIRC["wear"]) * (WEAR_SCALE / laps) * 0.85
			var fw: float = minf(1.0, front.stint_laps * wr)
			var gain_lap: float = c.wear * c.wear * float(COMP[c.comp][2]) + cliff_pen(c.comp, c.wear) + float(COMP[c.comp][0]) - float(COMP[nc][0])
			var front_lap: float = fw * fw * float(COMP[front.comp][2])
			var gp: float = float(c.cross[k]) - float(front.cross[k])
			under = {"code": front.code, "net": (gain_lap + front_lap * 0.5) * 2.0 - 1.0 - gp}
	return {"pos": n_ahead + 1, "ahead": best_a, "behind": best_b, "loss": loss, "under": under}


## WEC 엔트리: 하이퍼카(HY) 팀별 1~2대 + LMGT3(GT) 9팀 × 2대. 팀·크루는 data/wec.json (HTML WEC_FIELD 그대로).
## opts.wec_hy / wec_gt / wec_field 로 커리어용 명단을 넘길 수 있다.
func _build_wec_field(opts: Dictionary, start_comps: Array) -> void:
	var W: Dictionary = DB.wec
	if opts.has("wec_entries"):
		_build_wec_entries(opts["wec_entries"], opts, start_comps)
		return
	var hy: Array = opts.get("wec_hy", W["hy"])
	var gt: Array = opts.get("wec_gt", W["gt"])
	var field: Dictionary = opts.get("wec_field", W["field"])
	var engines: Dictionary = W["engines"]
	var setups: Array = opts.get("setup", [])
	var sets: Array = opts.get("sets", [])
	var stall_keys: Array = []
	for e in field["hy"]:
		var t: Dictionary = hy[int(e["ti"])]
		var mine: bool = int(e["ti"]) == my_team
		var k: int = int(e["k"])
		var eng: Dictionary = engines.get(t.get("engine", ""), {"pwr": 0.88, "eff": 1.0, "relMod": 0.0})
		var c = CarS.new()
		c.id = cars.size()
		c.cls = "HY"
		c.team = t["name"]
		c.team_idx = int(e["ti"])
		c.label = ("%s #%d" % [t["name"], k + 1]) if int(t.get("cars", 2)) > 1 else String(t["name"])
		c.color = Color(t["color"])
		c.rim = Color(t.get("rim", "#ffffff"))
		c.mine = mine
		c.slot = k
		c.perf = float(t["perf"]) + (float(eng["pwr"]) - 0.88) * 0.25
		c.eng_eff = float(eng["eff"])
		c.rel = clampf(float(t["rel"]) + float(eng["relMod"]), 0.75, 0.98)
		c.crew = float(t["crew"])
		c.strategy = float(t["strategy"]) + DIFF_STRAT[difficulty]
		c.drivers = e["crew"].duplicate(true)
		c.fuel = TANK
		c.bop = uni(-0.004, 0.004)
		c.nerve = uni(0.5, 1.6)
		if mine:
			c.wing = snappedf(float(CIRC.get("wingOpt", 3.0)), 0.1)
			c.press = "std"
			c.tyre_every = 2
			c.driver_every = 2
			c.sc_early = false
			c.comp = String(start_comps[k]) if k < start_comps.size() else "M"
			if k < setups.size():
				c.wing = float(setups[k].get("wing", c.wing))
				c.press = setups[k].get("press", "std")
			if k < sets.size():
				c.tyre_sets = sets[k]
		else:
			c.wing = clampf(round(float(CIRC["wingOpt"]) + gauss(0.7)), 1.0, 5.0)
			c.press = "std"
			c.tyre_every = 2 if rnd() < float(t["strategy"]) - 0.3 else 1
			c.driver_every = 2
			c.sc_early = rnd() < 0.7
			c.sc_stay = rnd() < 0.15
			c.sc_miss = rnd() < 0.3
			c.wec_style = "push" if rnd() < 0.25 else ("save" if rnd() < 0.33 else "std")
			c.comp = "M" if rnd() < 0.7 else "H"
		_finish_wec_car(c, stall_keys)
	for e in field["gt"]:
		var t2: Dictionary = gt[int(e["ti"])]
		var k2: int = int(e["k"])
		var c2 = CarS.new()
		c2.id = cars.size()
		c2.cls = "GT"
		c2.team = t2["name"]
		c2.team_idx = 100 + int(e["ti"])
		c2.label = "%s #%d" % [t2["name"], k2 + 1]
		c2.color = Color(t2["color"])
		c2.rim = Color(t2.get("rim", "#ffffff"))
		c2.slot = k2
		c2.perf = float(t2["perf"])
		c2.rel = float(t2["rel"])
		c2.crew = float(t2["crew"])
		c2.strategy = float(t2["strategy"]) + DIFF_STRAT[difficulty]
		c2.drivers = e["crew"].duplicate(true)
		c2.fuel = TANK
		c2.bop = uni(-0.004, 0.004)
		c2.nerve = uni(0.5, 1.6)
		c2.wing = clampf(round(float(CIRC["wingOpt"]) + gauss(0.7)), 1.0, 5.0)
		c2.press = "std"
		c2.tyre_every = 2 if rnd() < 0.5 else 1
		c2.driver_every = 2
		c2.sc_early = rnd() < 0.7
		c2.sc_stay = rnd() < 0.15
		c2.sc_miss = rnd() < 0.3
		c2.wec_style = "push" if rnd() < 0.25 else ("save" if rnd() < 0.33 else "std")
		c2.comp = "M" if rnd() < 0.6 else "H"
		_finish_wec_car(c2, stall_keys)
	n_stalls = stall_keys.size()


func _finish_wec_car(c, stall_keys: Array) -> void:
	c.comp = wec_fit_comp(c.cls, c.comp)
	if not c.mine and c.cls == "HY" and wec_comps("HY").has("S") and rnd() < 0.15:
		c.comp = "S"
	c.wec_sets = wec_race_sets(c.cls)
	apply_driver(c)
	c.used = {c.comp: true}
	var key: String = c.cls + ":" + c.team
	if not stall_keys.has(key):
		stall_keys.append(key)
	c.stall_idx = stall_keys.find(key)
	cars.append(c)


## 커리어 하위 리그용 엔트리: [{cls, team:{name,color,rim,perf,rel,crew,strategy,eng_eff}, k, crew:[3명], mine}]
func _build_wec_entries(entries: Array, opts: Dictionary, start_comps: Array) -> void:
	var stall_keys: Array = []
	var setups: Array = opts.get("setup", [])
	var sets: Array = opts.get("sets", [])
	for e in entries:
		var t: Dictionary = e["team"]
		var k: int = int(e["k"])
		var c = CarS.new()
		c.id = cars.size()
		c.cls = e["cls"]
		c.team = t["name"]
		c.team_idx = int(e.get("ti", 0))
		c.label = "%s #%d" % [t["name"], k + 1]
		c.color = Color(t["color"])
		c.rim = Color(t.get("rim", "#ffffff"))
		c.mine = bool(e.get("mine", false))
		c.slot = k
		c.perf = float(t["perf"])
		c.eng_eff = float(t.get("eng_eff", 1.0))
		c.rel = float(t["rel"])
		c.crew = float(t.get("crew", 0.82))
		c.strategy = float(t.get("strategy", 0.8))
		c.drivers = e["crew"].duplicate(true)
		c.fuel = TANK
		c.bop = uni(-0.004, 0.004)
		c.nerve = uni(0.5, 1.6)
		c.press = "std"
		c.driver_every = 2
		if c.mine:
			c.wing = snappedf(float(CIRC.get("wingOpt", 3.0)), 0.1)
			c.tyre_every = 2
			c.sc_early = false
			c.comp = String(start_comps[k]) if k < start_comps.size() else "M"
			if k < setups.size():
				c.wing = float(setups[k].get("wing", c.wing))
				c.press = setups[k].get("press", "std")
			if k < sets.size():
				c.tyre_sets = sets[k]
		else:
			c.wing = clampf(round(float(CIRC["wingOpt"]) + gauss(0.7)), 1.0, 5.0)
			c.tyre_every = 2 if rnd() < c.strategy - 0.3 else 1
			c.sc_early = rnd() < 0.7
			c.sc_stay = rnd() < 0.15
			c.sc_miss = rnd() < 0.3
			c.wec_style = "push" if rnd() < 0.25 else ("save" if rnd() < 0.33 else "std")
			c.comp = "M" if rnd() < 0.65 else "H"
		_finish_wec_car(c, stall_keys)
	n_stalls = stall_keys.size()


## 그리드를 직접 정한다 (F2 스프린트 리버스 그리드 등). keys = ["팀|슬롯", …] 앞에서부터 순서
func apply_grid(keys: Array) -> void:
	var pos := {}
	for i in keys.size():
		pos[keys[i]] = i
	cars.sort_custom(func(a, b): return int(pos.get("%s|%d" % [a.team, a.slot], 999)) < int(pos.get("%s|%d" % [b.team, b.slot], 999)))
	for i in cars.size():
		cars[i].grid = i


func grid_keys() -> Array:
	var out: Array = []
	for c in cars:
		out.append("%s|%d" % [c.team, c.slot])
	return out
