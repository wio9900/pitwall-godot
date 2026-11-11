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

const COMP := {"S": [-1.05, 0.048, 4.0], "M": [0.0, 0.032, 3.3], "H": [0.50, 0.025, 2.6], "I": [0.0, 0.038, 3.3], "W": [0.0, 0.032, 3.1]}
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
const STRAT_STYLES := ["aggressive", "balanced", "conservative", "reactive"]
const STRAT_KO := {"aggressive": "공격형", "balanced": "균형형", "conservative": "보수형", "reactive": "반응형"}

var rng := RandomNumberGenerator.new()
var T: Variant            # 트랙 (track.gd)
var CIRC: Dictionary = {}
var circ_key := ""
var laps := 15
var my_team := -1
var cars: Array = []
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

var _cuts_cache: Dictionary = {}


# ═════════ 난수 ═════════
func rnd() -> float:
	return rng.randf()


func uni(a: float, b: float) -> float:
	return a + (b - a) * rng.randf()


func gauss(s: float) -> float:
	return rng.randfn(0.0, 1.0) * s


# ═════════ 레이스 생성 ═════════
## start_comps: 내 차 2대의 출발 타이어 ["M", "H"] 등. my_team_ = -1이면 AI만 달린다(테스트용).
func new_race(circ_key_: String, my_team_: int, laps_: int, wx_opt: String, start_comps: Array = ["M", "M"], seed_value: int = 0) -> void:
	DB.load_all()
	if seed_value != 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	circ_key = circ_key_
	T = DB.track(circ_key)
	CIRC = DB.circuits[circ_key]
	laps = laps_
	my_team = my_team_
	true_mult = {"S": uni(0.88, 1.14), "M": uni(0.88, 1.14), "H": uni(0.88, 1.14)}
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
	var teams: Array = DB.teams
	n_stalls = teams.size()
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
			c.engine = DB.engines.get(t["engine"], 0.86)
			c.strategy = clampf(0.70 + 0.22 * (((c.aero + c.chassis) / 2.0 - 0.76) / 0.19), 0.66, 0.93)
			c.drivers = [d.duplicate()]
			c.nerve = uni(0.5, 1.6)
			apply_driver(c)
			if c.mine:
				var sc_ = String(start_comps[k]) if k < start_comps.size() else "M"
				c.plan = {"start": sc_, "stops": []}
				c.fuel = laps * FPL * 1.02
				c.wing = snappedf(float(CIRC.get("wingOpt", 3.0)), 0.1)
				c.press = "std"
				c.sc_early = false
				c.comp = sc_
			else:
				c.sc_early = rnd() < 0.7
				c.fuel = laps * FPL * (1.0 + uni(0.0, 0.04))
				c.wing = snappedf(clampf(float(CIRC["wingOpt"]) + gauss(0.35), 1.0, 5.0), 0.1)
				c.press = "low" if rnd() < 0.2 else ("high" if rnd() < 0.2 else "std")
				c.comp = "M"
			c.used = {c.comp: true}
			cars.append(c)
	# 그리드: 예선 페이스 순
	var qp = {}
	for c in cars:
		qp[c.id] = car_factor(c) * (1.0 - c.speed * K["drv_k"]) + gauss(0.004)
	cars.sort_custom(func(a, b): return qp[a.id] < qp[b.id])
	for i in cars.size():
		cars[i].grid = i
		cars[i].start_t = i * 0.22
	for c in cars:
		if not c.mine:
			plan_ai_strategy(c, "")
	# 날씨
	rain = null
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
	return 1.0 - K["car_scale"] * (c.aero * float(CIRC["wA"]) + c.engine * float(CIRC["wE"]) + c.chassis * float(CIRC["wC"]))


func ideal_tyre(w: float) -> String:
	if w >= 0.65:
		return "W"
	if w >= 0.22:
		return "I"
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
	return float(COMP[comp][1]) * float(true_mult.get(comp, 1.0))


func drv_wing_pref(c) -> float:
	var d: Dictionary = c.drivers[c.drv]
	return snappedf((d["aggr"] - 0.58) * 1.1 + (d["wet"] - 0.82) * 0.6 - (d["tyreMgmt"] - 0.82) * 0.8, 0.01)


func wing_opt(w: float, c) -> float:
	return clampf(float(CIRC["wingOpt"]) + drv_wing_pref(c) + (1.0 if w > 0.25 else 0.0), 1.0, 5.0)


func setup_pen(c, w: float) -> float:
	var d: float = c.wing - wing_opt(w, c)
	return 0.15 * d * d


func press_straight(pr: String) -> float:
	return float(PRESS_FX[pr]["straight"]) * (float(CIRC["wE"]) / 0.05)


func press_kerb(pr: String) -> float:
	var k: float = PRESS_FX[pr]["kerb"]
	return 1.0 + (k - 1.0) * (float(CIRC["wC"]) / 0.045)


func drs_on() -> bool:
	return leader_lap >= 2 and not sc and wet < 0.25


func sc_mult() -> float:
	if not sc:
		return 1.0
	return 0.72 if sc_kind == "SC" else 0.80


func pit_loss() -> float:
	return float(CIRC["pitLoss"]) * sc_mult()


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
	t += (float(COMP[c.comp][0]) + c.wear * c.wear * float(COMP[c.comp][2]) + cliff_pen(c.comp, c.wear) + c.fuel * 0.03 + evo_bonus) * sh
	t += (setup_pen(c, w) + float(PRESS[c.press][0]) + press_straight(c.press)) * sh
	var wp = weather_pen(c.comp, w)
	t += (wp + w * 6.0 + w * (0.8 - c.wet) * 4.0) * sh
	if gap_ahead != null and gap_ahead < K["dirty"] and c.instr != "hold":
		t += (0.2 + 0.3 * float(CIRC["wA"]) / 0.06 + 0.3 * w) * (1.0 - gap_ahead) * sh
	var em: String = c.ers_mode
	if em == "deploy" and c.ers <= 0.02:
		em = "balance"
	t += float(ERS[em][0]) * sh
	c.ers = clampf(c.ers + float(ERS[em][1]) * sh, 0.0, 1.0)
	var fm: Array = FUEL[c.fuel_mode]
	t += float(fm[0]) * sh
	if c.fuel <= 0.0:
		t += 2.5 * sh
	if c.instr == "defend" and gap_behind != null and gap_behind < 1.0:
		t += 0.3 * sh
	if night:
		t += base * sh * 0.008 * (1.2 - c.cons)
	# 타이어 온도
	var target = tt_target + (0.05 if c.instr == "attack" else 0.0) + (0.02 if c.ers_mode == "deploy" else 0.0) + float(PRESS[c.press][2]) - (0.05 if night else 0.0)
	if SLICK.has(c.comp) and w > 0.25:
		target -= 0.25
	if not SLICK.has(c.comp) and w < 0.2:
		target += 0.3
	c.tt = clampf(c.tt + (target - c.tt) * minf(0.9, 0.35 * float(PRESS_FX[c.press]["warm"])), 0.0, 1.0)
	var cold = maxf(0.0, 0.42 - c.tt)
	var hot = maxf(0.0, c.tt - 0.80)
	t += (cold * 4.0 + hot * 3.0 * float(PRESS_FX[c.press]["heat"])) * sh
	var cons: float = c.cons - (0.08 if night else 0.0)
	var is_launch: bool = c.lap == 0 and c.sec == 0
	var noise_scale = 0.18 if is_launch else 1.0
	t += gauss((K["noise"] - cons * 0.4 + 0.3 * w) * sqrt(sh) * noise_scale)
	var pressure = 1.5 if (not is_launch and gap_ahead != null and gap_ahead < 0.5) else 1.0
	var p_err = 0.0
	if not is_launch:
		p_err = 0.036 * sh * err_m * press_kerb(c.press) * pressure * (1.2 - cons) * (1.0 + 3.0 * w * (1.3 - c.wet)) * (1.0 + wp / 5.0) * (1.5 if is_restart else 1.0) * (1.0 + cold * 5.0) * (1.2 if c.instr == "attack" else 1.0) * (1.5 if night else 1.0)
	var crash = ""
	if rnd() < p_err:
		t += uni(1.0, 4.0) + w * 3.0
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
		if c.mech_trouble != "":
			t += (0.85 + c.mech_stress * 0.6) * sh
	if crash != "":
		c.focus = clampf(c.focus - 14.0, 30.0, 100.0)
	elif c.pace == "standard" and c.focus < 75.0:
		c.focus = clampf(c.focus + 1.5 * sh, 30.0, 100.0)
	# 마모·연료
	var over = 2.0 if (not SLICK.has(c.comp) and w < 0.2) else 1.0
	var wear_rate = true_wear_rate(c.comp) * float(CIRC["wear"]) * (WEAR_SCALE / laps)
	var lift_wear = 0.80 if c.instr == "lift" else (0.92 if c.instr == "hold" else 1.0)
	var lift_fuel = 0.86 if c.instr == "lift" else 1.0
	c.wear = minf(1.0, c.wear + wear_rate * wear_m * over * (1.0 + hot * 5.0 * float(PRESS_FX[c.press]["heat"])) * lift_wear * float(PRESS[c.press][1]) * (1.0 - (c.wing - 3.0) * 0.04) * c.tyre_deg_rate * (0.85 if night else 1.0) * sh)
	c.fuel -= FPL * sh * float(fm[1]) * c.fuel_burn_rate * lift_fuel * (1.06 if c.pace == "attack" else (0.93 if c.pace == "save" else 1.0))
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
	event("%s %s → 리타이어" % [name_of(c), why], "bad")
	if c.mine:
		say(c, "%s 발생으로 리타이어합니다." % why)
	if not sc and leader_lap < laps - 1:
		var r = rnd()
		var p_sc = 0.10 if why == "고장" else (0.75 if why == "스핀" else 0.60)
		var p_v = 0.35 if why == "고장" else (0.15 if why == "스핀" else 0.25)
		if r < p_sc:
			deploy("SC")
		elif r < p_sc + p_v:
			deploy("VSC")


func deploy(kind: String) -> void:
	if sc:
		return
	sc = true
	sc_kind = kind
	sc_in_notified = false
	sc_in_pit_lane = false
	sc_pit_prog = 0.0
	var n = int(round(uni(3, 4))) if kind == "SC" else 2
	sc_end_lap = leader_lap + n
	if kind == "SC":
		var lead: Variant = leader_car()
		sc_dist = (car_dist(lead) + T.L * 0.035) if lead != null else 0.0
		event("세이프티카 출동! 대열이 압축됩니다 (%d랩 종료 예정)" % sc_end_lap, "sc")
	else:
		event("버추얼 세이프티카 발령! 간격 유지, 피트 손실 감소", "sc")


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
			if not ever_wet and n_slick < 2:
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
	var cands = ai_optimize(laps, fixed_start, c.wear, ai_rates(c, 1.0), pit_loss() + 3.0, {}, {"S": 1, "M": 2, "H": 1}, 3 if laps >= 12 else 2)
	var pk: Variant = ai_choose(c, cands, true)
	if pk == null:
		return
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
	var need_diff: bool = not ever_wet and c.used_slicks() < 2
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
	if c.pit_req != "":
		var comp: String = c.pit_req
		c.pit_req = ""
		c.crew_out = true
		var ns0: Variant = next_stop(c)
		if ns0 != null:
			c.stops_done += 1
		return {"comp": comp, "tyres": true}
	if c.mine:
		return null
	ai_replan(c)
	var ns: Variant = next_stop(c)
	var have = kind_of(c.comp)
	if want != have:
		var nw = ("M" if left > 8 else "S") if want == "slick" else want
		var lose = weather_pen(c.comp, wet) - weather_pen(nw, wet)
		if lose * minf(left, uni(2, 9)) > pit_loss() * c.nerve:
			c.weather_pit = true
			c.crew_out = true
			return {"comp": nw, "tyres": true}
		return null
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
	if not c.weather_pit and ns != null:
		if not sc and (cur >= ns["lap"] or c.wear >= 0.80):
			c.stops_done += 1
			c.crew_out = true
			return {"comp": _pick_ai_slick(c, ns["comp"], left) if want == "slick" else want, "tyres": true}
		if sc and cur > 2 and c.wear >= 0.35 and (cur >= ns["lap"] or (c.sc_early and ns["lap"] - cur <= 4) or c.wear >= 0.50) and left > 2:
			c.stops_done += 1
			c.crew_out = true
			return {"comp": _pick_ai_slick(c, ns["comp"], left) if want == "slick" else want, "tyres": true}
	# 계획에 없던 피트: 남은 랩 동안 잃을 시간이 피트 손실보다 클 때만
	var pen_now: float = c.wear * c.wear * float(COMP[c.comp][2]) + cliff_pen(c.comp, c.wear)
	var fresh = "H" if left > 7 else ("M" if left > 4 else "S")
	var fresh_gap: float = float(COMP[fresh][0]) - float(COMP[c.comp][0])
	if left >= 2 and ((pen_now - fresh_gap) * left * 0.75 > pit_loss() + 3.0 or c.wear >= 0.92):
		if ns != null:
			c.stops_done += 1
		c.crew_out = true
		return {"comp": _pick_ai_slick(c, fresh, left) if want == "slick" else want, "tyres": true}
	if not ever_wet and left <= 3 and c.used_slicks() < 2:
		c.crew_out = true
		return {"comp": _alt_slick(c.comp), "tyres": true}
	return null


func ai_control(c, gap_ahead, gap_behind) -> void:
	if c.mine:
		return
	if c.ers < 0.2:
		c.ers_mode = "harvest"
	elif gap_ahead != null and gap_ahead < 1.0 and c.ers > 0.35:
		c.ers_mode = "deploy"
	elif gap_behind != null and gap_behind < 0.8 and c.ers > 0.3:
		c.ers_mode = "deploy"
	else:
		c.ers_mode = "balance"
	c.fuel_mode = "lean" if c.fuel < (laps - c.lap) * FPL * 0.97 else "std"


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
		c.lap_hist.push_front({"lap": c.lap, "t": lt, "comp": c.comp, "pit": c.pit_lap})
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
			if not ever_wet and c.used_slicks() < 2:
				c.penalty = 30.0
				c.finish_t += 30.0
			if not finishing:
				finishing = true
				event("체커기! %s 우승" % c.code)
			return
		c.sec = 0
		if c.boxing != null:
			apply_pit(c)
		else:
			c.pit_phase = 0
		if rnd() < (1.0 - c.rel) * K["fail"] * (1.3 if c.pace == "attack" else 1.0) * (1.2 if night else 1.0):
			retire(c, "고장")
			return
	elif c.started:
		c.sec += 1
		c.pit_phase = 0
		if c.sec == NS - 1 and c.boxing == null:
			var d: Variant = pit_decision(c)
			if d != null:
				c.boxing = d
				c.pit_total = pit_loss() + gauss(0.6)
	c.started = true
	schedule_next(c, t)


func apply_pit(c) -> void:
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
	if d["tyres"]:
		c.comp = d["comp"]
		c.used[c.comp] = true
		c.wear = 0.0
		c.tt = 0.35
		c.stint_laps = 0
	if c.mine:
		say(c, "박스 완료 (%s 장착)" % TYRE_KO[c.comp])


func _same_class_ahead(c, k: int, t: float) -> Array:
	var ahead: Variant = null
	var ahead_t = -INF
	for o in cars:
		if o == c or o.dnf != "":
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
			if o == c or o.dnf != "" or o.cross.size() <= k - 1:
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
			var catchup = float(CIRC["base"]) * sh * 1.08
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
		if drs_on() and T.drs_secs.has(c.sec) and gap != null and gap < 1.0 and not pitting:
			dur -= 0.45
			c.drs = true
		var ahead_pitting: bool = ahead != null and is_pitting(ahead)
		if ahead != null and ahead.cross.size() == k + 1 and not ahead.finished and not ahead_pitting and not pitting:
			var ahead_dur: float = ahead.sec_end - ahead_t
			var diff: float = ahead_dur - dur
			if c.instr == "hold":
				dur = maxf(dur, (ahead.sec_end - t) + 1.0)
			elif gap - diff < K["ot_gap"] and diff > 0:
				var p: float = float(CIRC["overtake"]) + diff * 0.8 + (c.aggr - ahead.aggr) * 0.1 + 0.08 - ahead.def_ * 0.15 + (c.wet - ahead.wet) * 0.3 * wet + (0.1 if rs else 0.0) \
					+ (0.15 if c.drs else 0.0) + (0.06 if (c.ers_mode == "deploy" and c.ers > 0.02) else 0.0) + (0.08 if c.instr == "attack" else 0.0) + (ahead.wing - c.wing) * 0.02 \
					- (0.12 if ahead.instr == "defend" else 0.0) - (0.04 if (ahead.ers_mode == "deploy" and ahead.ers > 0.02) else 0.0)
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
		elif c.fuel < left * FPL * float(FUEL[c.fuel_mode][1]) - FPL * 0.2 and left > 0:
			say(c, "연료가 부족해요. 세이브 필요")
		elif c.wear > 0.7 or (c.comp == "H" and c.wear > H_CLIFF):
			say(c, "타이어가 다 됐어요 (%d%%)" % int(round(c.wear * 100)))
		elif c.tt > 0.82:
			say(c, "타이어가 과열됐어요. 페이스 좀 낮출게요?")
		elif c.ers < 0.1 and c.ers_mode == "deploy":
			say(c, "배터리가 바닥이에요")
		elif not ever_wet and left <= 4 and c.used_slicks() < 2:
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
			if sc_dist < target_d:
				sc_dist = target_d
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
		var grid_d = -(c.grid + 1) * T.L * 0.0048
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
func results() -> Array:
	var out = []
	var ord = order()
	var winner = ord[0]
	var pos = 0
	for c in ord:
		pos += 1
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
		if c.dnf == "" and pos <= POINTS.size():
			pts = POINTS[pos - 1]
		out.append({"pos": pos, "car": c, "gap": gap, "points": pts})
	return out
