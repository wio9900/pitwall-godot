extends RefCounted
## F1 커리어: 팀 본부(HQ)·경제(코스트캡·ATR)·R&D·설비·인력·드라이버·스폰서·시즌 흐름.
## 원본 HTML(v16.1)의 HQ / ECON / DEV 로직을 옮기고, 스폰서는 새 설계(오퍼·계약·의무·사전 약속 미션)로 바꿨다.
## 상태는 전부 hq 딕셔너리 하나에 담아 JSON 으로 저장한다. 화면과 무관(헤드리스 테스트 가능).

const DB = preload("res://scripts/data/game_db.gd")
const RS = preload("res://scripts/sim/race_sim.gd")

const SAVE_PATH := "user://career_f1.json"
const SAVE_VER := 1
const DEV_AREAS := ["aero", "engine", "chassis", "rel"]
const FAC_KEYS := ["wind", "bench", "rig", "sim", "factory", "pit"]
const ENGINE_CHOICES := ["Mercedes", "Ferrari", "Red Bull Ford", "Honda"]
const POINTS := [25, 18, 15, 12, 10, 8, 6, 4, 2, 1]
const SPRINT_POINTS := [10, 8, 6, 5, 4, 3, 2, 1]
const CE0 := {"aero": 0.006, "eng": 0.006, "tyre": 0.007, "rel": 0.006}
const MISSION_PEN := {"both_finish": 0.01, "double_p8": 0.02, "podium_one": 0.03}

# ── 스폰서 (새 설계) ──
# 카테고리별 기준 금액(시즌·1부 기준, HTML 원본 스폰서 금액과 같은 규모)과 자격 조건, 의무(연습 랩 감소)
const SPON_CATS := {
	"title": {"ko": "타이틀", "base": 5.5, "bonus": 1.5, "pop": 0.0, "rank": 99, "duty": 2},
	"tech": {"ko": "기술 파트너", "base": 2.2, "bonus": 0.8, "pop": 0.0, "rank": 99, "duty": 0},
	"global": {"ko": "글로벌 브랜드", "base": 3.5, "bonus": 1.2, "pop": 0.55, "rank": 6, "duty": 1},
	"premium": {"ko": "프리미엄 파트너", "base": 6.0, "bonus": 2.5, "pop": 0.72, "rank": 3, "duty": 2},
}
const SPON_NAMES := {
	"title": ["Nordwind Energy", "Helix Telecom", "Aurora Bank", "Vantage Oil", "Kestrel Mobile", "Orion Airways"],
	"tech": ["Brakeline Systems", "Corvex Composites", "Tessera Cloud", "Ferrox Alloys", "Lumen Sensors", "Quanta Chips"],
	"global": ["Meridian Watches", "Solace Apparel", "Polaris Drinks", "Atlas Logistics", "Zenith Cameras", "Cobalt Games"],
	"premium": ["Valkyr Motors", "Sterling Private", "Monarch Luxury", "Equinox Aerospace"],
}
# 팀 기대 순위별 레이스당 예상 포인트 (성과연동형 단가 계산용). tests/calib.gd 로 AI만 달린 96판 실측값.
const EXP_PTS := [21.0, 15.5, 14.0, 13.0, 9.0, 7.0, 6.0, 5.0, 4.5, 3.5, 2.6, 2.0]

var D: Dictionary = {}   # data/career_f1.json
var hq: Dictionary = {}
var rng := RandomNumberGenerator.new()


func _init() -> void:
	DB.load_all()
	D = DB.career


## 커리어 시리즈: "f1" / "wec"
func ser() -> String:
	return String(hq.get("series", "f1"))


func is_wec() -> bool:
	return ser() == "wec"


## 시리즈별 데이터 (WEC 는 data/wec.json)
func SD() -> Dictionary:
	return DB.wec if is_wec() else D


# ═════════ 난수 ═════════
func rnd() -> float:
	return rng.randf()


func uni(a: float, b: float) -> float:
	return a + (b - a) * rng.randf()


func gauss(s: float) -> float:
	return rng.randfn(0.0, 1.0) * s


func r2(x: float) -> float:
	return snappedf(x, 0.01)


# ═════════ 새 커리어 ═════════
## entry: "select"(기존 팀) / "create"(신규 팀). opts(create): name, color, rim, engine, region, tier
func new_career(entry: String, team_idx: int, opts: Dictionary = {}, seed_value: int = 0) -> void:
	if seed_value != 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	var HD: Dictionary = D["hq_default"]
	var series: String = opts.get("series", "f1")
	hq = {
		"series": series, "jokers": int(D["econ"]["jokersPerCycle"]), "wec_bop": 0.0,
		"ver": SAVE_VER, "season": 1, "race_count": 0, "cash": 8.5, "pop": 0.45,
		"entry": entry, "tier": 3, "promo_qualified": false, "news": [],
		"team_name": "", "team_color": "#00d2be", "team_rim": "#ffffff",
		"engine_supplier": "Mercedes", "team_pts": {}, "rnd_branch": "balanced", "region": "uk",
		"spent_cap": 0.0, "cost_cap_limit": 18.0,
		"base": {"wind": 1, "bench": 1, "rig": 1, "sim": 1, "pit": 1, "factory": 1},
		"juniors": HD["juniors"].duplicate(true),
		"reserve": HD["reserveDriver"].duplicate(true),
		"chief": HD["chiefEngineers"].duplicate(true),
		"eng_pool": HD["engineerPool"].duplicate(true),
		"market": HD["marketPool"].duplicate(true),
		"salaries": {},
		"mission": "double_p8",
		"contracts": [], "offers": [], "pay_pool": [], "pay_drivers": {},
		"politics": {},
		"laps": 15,
		"difficulty": clampi(int(opts.get("difficulty", 1)), 0, 3),
	}
	# 팀·엔진은 커리어마다 복사해서 바꿔 쓴다 (AI 개발·드라이버 교체가 원본 데이터를 건드리지 않게)
	if series == "wec":
		hq["teams"] = DB.wec["hy"].duplicate(true)
		hq["engines"] = {}
		hq["field"] = DB.wec["field"]["hy"].duplicate(true)
		hq["laps"] = 0
	else:
		hq["teams"] = DB.teams.duplicate(true)
		hq["engines"] = DB.engines.duplicate(true)
	# 드라이버 나이는 teams_f1.json 의 age (HTML 원본 driverAges 는 이름과 순서가 어긋나 있어 실제 나이로 교정)
	for t in hq["teams"]:
		for d in t.get("drivers", []):
			d["age"] = int(d.get("age", 26))
	_reset_econ()
	if entry == "create":
		hq["tier"] = int(opts.get("tier", 1))
		hq["team_name"] = opts.get("name", "Korea GP Racing")
		hq["team_color"] = opts.get("color", "#00d2be")
		hq["team_rim"] = opts.get("rim", "#ffffff")
		hq["engine_supplier"] = opts.get("engine", "Mercedes")
		hq["region"] = opts.get("region", "uk")
		if series == "wec":
			_create_wec_team(opts)
	if entry == "create" and series != "wec":
		hq["teams"].append({
			"name": hq["team_name"], "color": hq["team_color"], "rim": hq["team_rim"], "engine": hq["engine_supplier"],
			"aero": 0.72, "chassis": 0.72, "rel": 0.81,
			"drivers": [
				{"name": "K. Seo", "speed": 0.76, "cons": 0.78, "tyreMgmt": 0.75, "aggr": 0.58, "def": 0.72, "wet": 0.74, "age": 22},
				{"name": "H. Park", "speed": 0.73, "cons": 0.75, "tyreMgmt": 0.73, "aggr": 0.52, "def": 0.70, "wet": 0.72, "age": 24},
			],
		})
	if entry == "create":
		hq["my_team"] = hq["teams"].size() - 1
		var seed_cash := 4.6 if hq["tier"] == 0 else (5.2 if hq["tier"] == 1 else (6.0 if hq["tier"] == 2 else 6.5))
		hq["cash"] = snappedf(seed_cash * (0.96 if series == "wec" else 1.0), 0.1)
		hq["pop"] = 0.25 if hq["tier"] == 0 else (0.28 if hq["tier"] == 1 else (0.32 if hq["tier"] == 2 else 0.35))
	else:
		hq["my_team"] = team_idx
		var t: Dictionary = hq["teams"][team_idx]
		hq["team_name"] = t["name"]
		hq["team_color"] = t["color"]
		hq["team_rim"] = t["rim"]
		hq["engine_supplier"] = t["engine"]
		var ib: Array = SD()["init_budget"].get(t["name"], [9.0, 0.70] if series == "wec" else [8.5, 0.60])
		hq["cash"] = float(ib[0])
		hq["pop"] = float(ib[1])
	hq["cost_cap_limit"] = cap_limit_now()
	_pay_owner([])
	evaluate_engine_politics()
	_starting_sponsors()
	_refresh_offers()
	_refresh_pay_pool()
	news("시즌 1 개막! %s 본부에 오신 걸 환영합니다." % hq["team_name"])


const WEC_PKGS := {
	"Ferrari F163 3.0L V6 Twin-Turbo Hybrid": "Ferrari 499P 커스터머",
	"Cadillac LMC55R 5.5L V8 NA Hybrid": "Cadillac V-Series.R",
	"BMW P66/3 4.0L V8 Twin-Turbo Hybrid": "BMW M Hybrid V8",
	"Genesis GMR 3.2L V8 Twin-Turbo Hybrid": "독자 워크스 (GMR V8)",
}
# 하위 리그 라인업 등급 · 최소 주행 규정 (LMGT3 브론즈 25%, LMP2 실버 20%)
const WEC_TIER_GRADES := {"0": ["G", "S", "B"], "1": ["G", "S", "B"], "2": ["G", "G", "S"], "3": ["P", "P", "G"]}
const WEC_MIN_DRIVE := {"0": {"grade": "B", "pct": 0.25}, "1": {"grade": "B", "pct": 0.25}, "2": {"grade": "S", "pct": 0.20}}
## 하위 리그 → 클래스 (0 아시안 르망 LMP3 · 1 LMGT3 · 2 LMP2)
const WEC_TIER_CLS := {0: "P3", 1: "GT", 2: "P2"}
const GRADE_RANGE := {"P": [0.86, 0.93], "G": [0.80, 0.87], "S": [0.70, 0.78], "B": [0.56, 0.66]}


func _create_wec_team(opts: Dictionary) -> void:
	var pkg: String = opts.get("engine", "Ferrari F163 3.0L V6 Twin-Turbo Hybrid")
	if not WEC_PKGS.has(pkg):
		pkg = "Ferrari F163 3.0L V6 Twin-Turbo Hybrid"
	hq["engine_supplier"] = pkg
	hq["teams"].append({"name": hq["team_name"], "color": hq["team_color"], "cars": 2, "perf": 0.48, "rel": 0.84, "crew": 0.78, "strategy": 0.76, "rim": hq["team_rim"], "engine": pkg})
	var ti: int = hq["teams"].size() - 1
	var names := [["K. Seo", "J. Holm", "D. Kim"], ["H. Park", "M. Vance", "L. Jung"]]
	var grades := ["G", "S", "B"]
	var spd := {"G": 0.78, "S": 0.73, "B": 0.64}
	for k in 2:
		var crew: Array = []
		for i in 3:
			var g: String = grades[i]
			crew.append({"name": names[k][i], "grade": g, "speed": spd[g] - 0.01 * k, "cons": 0.76, "tyreMgmt": 0.75, "aggr": 0.52, "def": 0.72, "wet": 0.74})
		hq["field"].append({"ti": ti, "k": k, "crew": crew})


## WEC 내 차 크루 [3명] (slot 0/1)
func my_crew(slot: int) -> Array:
	for e in hq.get("field", []):
		if int(e["ti"]) == my_team() and int(e["k"]) == slot:
			for d in e["crew"]:
				if not d.has("age"):
					d["age"] = 22 + int(16.0 * _hash01(String(d["name"]), 7))
			return e["crew"]
	return []


func my_team() -> int:
	return int(hq["my_team"])


func my_team_dict() -> Dictionary:
	return hq["teams"][my_team()]


func news(msg: String) -> void:
	hq["news"].push_front("[S%d] %s" % [int(hq["season"]), msg])
	if hq["news"].size() > 30:
		hq["news"].pop_back()


# ═════════ 기본 정보 ═════════
func tier() -> int:
	# 르망 초청 경기 중에는 LMP2(2부) 규정·출전 명단으로 달린다
	if hq.get("special", "") == "lemans":
		return 2
	return int(hq["tier"])


func tier_meta(t: int = -1) -> Dictionary:
	var tt := tier() if t < 0 else t
	return SD()["tiers"][str(tt)]


func tier_scale() -> float:
	return float(tier_meta()["cap"]) / float(D["econ"]["topCap"][ser()])


func calendar() -> Array:
	return tier_meta().get("calendar", SD()["calendar"])


## 레이스 형식: f1 / f2(스프린트+피처, 피처는 의무 피트) / f3(피트 없이 한 경기, 드라이버 육성) / wec
func race_format() -> String:
	if is_wec():
		return "wec"
	if not is_spec_tier():
		return "f1"
	return "f3" if tier() == 1 else "f2"


func has_sprint() -> bool:
	return race_format() == "f2"


## 형식별 규칙: F3 는 타이어가 한 경기를 버티고(피트 불필요), F2 스프린트는 의무 피트 없음, 피처는 두 컴파운드 의무
func race_rules(sprint: bool = false) -> Dictionary:
	match race_format():
		"f3":
			return {"two_compounds": false, "wear_mult": 0.3, "no_pits": true}
		"f2":
			return {"two_compounds": false, "wear_mult": 0.5, "no_pits": true, "points": SPRINT_POINTS} if sprint else {"two_compounds": true, "wear_mult": 1.0}
	return {}


## 이번 레이스 랩 수 (F1 15랩, F2 피처 15·스프린트 10, F3 12, WEC 는 서킷별 '짧게')
func race_laps(sprint: bool = false) -> int:
	if is_wec():
		return int(DB.circuits[next_circuit()]["lapsOpt"]["short"])
	match race_format():
		"f3":
			return 12
		"f2":
			return 10 if sprint else 15
	return int(hq["laps"])


func cal_len() -> int:
	return calendar().size()


## 이번 시즌 몇 번째 라운드인가 (0부터). 리그마다 일정 길이가 달라서(아시안 르망 6경기) 시즌 시작 시점 기준으로 센다
func round_idx() -> int:
	return (int(hq["race_count"]) - int(hq.get("season_base", 0))) % cal_len()


func is_preseason() -> bool:
	return round_idx() == 0


func next_circuit() -> String:
	if hq.get("special", "") == "lemans":
		return "lemans"
	return calendar()[round_idx()]


func is_spec_tier() -> bool:
	return hq["entry"] == "create" and tier() < 3


func is_works() -> bool:
	if is_wec():
		return true
	if hq["entry"] == "create":
		return false
	return D["works"].has(my_team_dict()["name"])


func book(k: String, v: float) -> void:
	hq["ledger"][k] = snappedf(float(hq["ledger"].get(k, 0.0)) + v, 0.001)


func _new_ledger() -> Dictionary:
	return {"owner": 0.0, "spon": 0.0, "pay": 0.0, "prize": 0.0, "mission": 0.0, "ops": 0.0, "overhead": 0.0, "salary": 0.0, "repair": 0.0, "rnd": 0.0, "fac": 0.0, "staff": 0.0}


func _reset_econ() -> void:
	hq["dev"] = {"aero": 0.0, "engine": 0.0, "chassis": 0.0, "rel": 0.0}
	hq["dev_next"] = {"aero": 0.0, "engine": 0.0, "chassis": 0.0, "rel": 0.0}
	hq["proj"] = {"aero": null, "engine": null, "chassis": null, "rel": null}
	hq["pkg_n"] = {"aero": 0, "engine": 0, "chassis": 0, "rel": 0}
	hq["pkg_n_next"] = {"aero": 0, "engine": 0, "chassis": 0, "rel": 0}
	hq["depr"] = []
	hq["cap_adj"] = 0.0
	hq["atr_pen"] = 0.0
	hq["dev_target"] = "cur"
	hq["last_rank"] = 0
	hq["owner_season"] = 0
	hq["ledger"] = _new_ledger()
	hq["last_ledger"] = {}
	hq["season_log"] = []


func owner_funding() -> float:
	if hq["entry"] != "create":
		return 0.0
	var arr: Array = D["econ"]["owner"]
	var n := int(hq["owner_season"])
	if n >= arr.size():
		return 0.0
	return r2(float(arr[n]) * tier_scale())


func _pay_owner(notes: Array) -> void:
	var f := owner_funding()
	hq["owner_season"] = int(hq["owner_season"]) + 1
	if f <= 0.0:
		return
	hq["cash"] = r2(hq["cash"] + f)
	book("owner", f)
	var last: bool = int(hq["owner_season"]) >= D["econ"]["owner"].size()
	var msg := "🏦 오너 그룹 시즌 %d 운영 자본 투입 +%.2fM%s" % [int(hq["season"]), f, " (마지막 지원 — 다음 시즌부터 자립)" if last else ""]
	news(msg)
	notes.append(msg)


func races_left() -> int:
	return cal_len() - round_idx()


func projected_spend() -> float:
	return r2(hq["spent_cap"] + float(D["econ"]["ops"][ser()]) * tier_scale() * races_left())


func cap_limit_now() -> float:
	return r2(float(tier_meta()["cap"]) + float(hq["cap_adj"]))


func reg_year() -> int:
	return (int(hq["season"]) - 1) % int(D["econ"]["regCycle"]) + 1


# ═════════ 순위 ═════════
## 현재 리그의 팀 목록 [{name, color, idx, pts, mine}] 포인트 순 (동점이면 내 팀이 뒤)
func standings() -> Array:
	var rows: Array = []
	for t in race_teams():
		if t.get("traffic", false):
			continue
		var nm: String = t["name"]
		rows.append({"name": nm, "color": t["color"], "pts": int(hq["team_pts"].get(nm, 0)), "mine": nm == hq["team_name"]})
	rows.sort_custom(func(a, b): return a["pts"] > b["pts"] if a["pts"] != b["pts"] else (not a["mine"] and b["mine"]))
	return rows


func my_rank_now() -> int:
	var st := standings()
	for i in st.size():
		if st[i]["mine"]:
			return i + 1
	return st.size()


func initial_rank() -> int:
	var arr: Array = []
	var teams: Array = hq["teams"]
	for i in teams.size():
		if is_wec():
			arr.append([i, float(teams[i]["perf"])])
		else:
			arr.append([i, float(teams[i]["aero"]) + float(teams[i]["chassis"])])
	arr.sort_custom(func(a, b): return a[1] > b[1])
	for i in arr.size():
		if arr[i][0] == my_team():
			return i + 1
	return arr.size()


func pre_rank() -> int:
	if int(hq["last_rank"]) > 0:
		return int(hq["last_rank"])
	if is_spec_tier():
		return 6
	return 5 if is_wec() else initial_rank()


func atr_rank() -> int:
	if round_idx() >= int(ceil(cal_len() / 2.0)):
		return my_rank_now()
	return int(hq["last_rank"]) if int(hq["last_rank"]) > 0 else initial_rank()


func atr_pct(rank: int) -> float:
	return minf(1.15, 0.70 + 0.05 * (rank - 1))


func atr_mult() -> float:
	if is_spec_tier() or is_wec():
		return 1.0
	return atr_pct(atr_rank()) * (1.0 - float(hq["atr_pen"]))


func mission_expect() -> float:
	return clampf(0.35 + 0.12 * (pre_rank() - 1), 0.35, 1.5)


func mission_reward(k: String) -> float:
	if not D["hq_default"]["missions"].has(k):
		return 0.0
	return r2(float(D["hq_default"]["missions"][k]["reward"]) * (10.0 / cal_len()) * tier_scale() * mission_expect())


func prize_for(rank: int) -> float:
	var t: Array = D["econ"]["prize"][ser()]
	var v: float = t[clampi(rank - 1, 0, t.size() - 1)]
	return r2(v * float(tier_meta()["prizeM"]) * tier_scale())


# ═════════ 성능 보너스 (설비·개발·인력·지역·철학) ═════════
func hq_bonus(stat: String) -> float:
	var ce: Dictionary = hq["chief"]
	var all_high := true
	var s_aero := 0.0
	var s_eng := 0.0
	var s_tyre := 0.0
	var s_rel := 0.0
	for k in ce:
		var e: Dictionary = ce[k]
		if e["tier"] != "S급" and e["tier"] != "A급":
			all_high = false
		s_aero += float(e.get("aeroMod", 0.0))
		s_eng += float(e.get("engMod", 0.0))
		s_tyre += float(e.get("tyreMod", 0.0))
		s_rel += float(e.get("relMod", 0.0))
	var syn := 0.005 if all_high else 0.0
	var b: Dictionary = hq["base"]
	var dv: Dictionary = hq["dev"].duplicate()
	if is_wec():
		# WEC: BoP 가 성능 개발 이점의 40%를 상쇄 (신뢰성은 제외)
		for k in ["aero", "engine", "chassis"]:
			dv[k] = float(dv[k]) * (1.0 - float(D["econ"]["bopAbsorb"]))
	match stat:
		"aero":
			return float(dv["aero"]) + (int(b["wind"]) - 1) * 0.006 + s_aero + syn - CE0["aero"]
		"engine":
			return float(dv["engine"]) + (int(b["bench"]) - 1) * 0.006 + s_eng + syn - CE0["eng"]
		"chassis":
			return float(dv["chassis"]) + (int(b["rig"]) - 1) * 0.006 + s_tyre + syn - CE0["tyre"]
		"rel":
			return float(dv["rel"]) + (int(b["bench"]) - 1) * 0.003 + s_rel + syn - CE0["rel"]
		"crew":
			return (int(b["pit"]) - 1) * 0.025
	return 0.0


func hq_extra() -> Dictionary:
	var r: Array = D["region_fx"].get(hq["region"], [0, 0, 0, 0])
	var b: Array = D["branch_fx"].get(hq["rnd_branch"], [0, 0, 0])
	return {"aero": float(r[0]) + float(b[0]), "engine": float(r[1]) + float(b[1]), "chassis": float(r[2]) + float(b[2]), "rel": float(r[3])}


## 레이스 시뮬레이션에 넘길 내 차 보정치
func my_mods() -> Dictionary:
	var ex := hq_extra()
	if is_wec():
		var perf: float = (hq_bonus("aero") + hq_bonus("engine") + hq_bonus("chassis") + ex["aero"] + ex["engine"] + ex["chassis"]) * 0.45
		return {"perf": perf, "rel": hq_bonus("rel") + ex["rel"], "crew": hq_bonus("crew"), "bop": float(hq.get("wec_bop", 0.0))}
	return {
		"aero": hq_bonus("aero") + ex["aero"], "engine": hq_bonus("engine") + ex["engine"],
		"chassis": hq_bonus("chassis") + ex["chassis"], "rel": hq_bonus("rel") + ex["rel"], "crew": hq_bonus("crew"),
	}


func spec_engine() -> float:
	return 0.78 if tier() == 1 else 0.84


## 이번 리그에서 달리는 팀 목록 (스펙 하위 리그면 실제 F2/F3 팀 + 내 팀)
func race_teams() -> Array:
	if is_wec():
		return _wec_race_teams()
	if not is_spec_tier():
		return hq["teams"]
	var out: Array = []
	for r in D["rosters"][str(tier())]:
		var t: Dictionary = r.duplicate(true)
		t["engine_val"] = spec_engine()
		for d in t["drivers"]:
			# 실제 로스터는 속도·안정성만 있어서 나머지 능력치를 이름 기반 고정 난수로 채운다 (평균은 기존 기본값과 같게)
			var nm: String = d["name"]
			d["tyreMgmt"] = d.get("tyreMgmt", 0.72 + 0.16 * _hash01(nm, 2))
			d["aggr"] = d.get("aggr", 0.45 + 0.30 * _hash01(nm, 3))
			d["def"] = d.get("def", 0.70 + 0.16 * _hash01(nm, 4))
			d["wet"] = d.get("wet", 0.70 + 0.20 * _hash01(nm, 5))
			d["age"] = d.get("age", 18 + int(5.0 * _hash01(nm, 6)) + (2 if tier() == 2 else 0))
		out.append(t)
	var me: Dictionary = my_team_dict().duplicate(true)
	me["engine_val"] = spec_engine()
	out.append(me)
	return out


## WEC 리그 팀 목록 (순위표용). 하위 리그는 실제 LMGT3/LMP2 팀 + 내 팀, LMP2 는 GT3 를 트래픽으로 같이 달린다.
func _wec_race_teams() -> Array:
	if not is_spec_tier():
		var out0: Array = []
		for t in hq["teams"]:
			out0.append(t)
		return out0
	var out: Array = []
	for r in DB.wec["rosters"][str(tier())]:
		out.append({"name": r["name"], "color": r["color"], "rim": "#ffffff", "perf": r["perf"], "rel": r["rel"], "crew": 0.82, "strategy": 0.8, "crew_names": r["crew_names"]})
	out.append(my_team_dict())
	return out


func _hash01(sv: String, i: int) -> float:
	var h := 2166136261
	for ch in (sv + str(i)):
		h = ((h ^ ch.unicode_at(0)) * 16777619) & 0x7fffffff
	return float(h % 10000) / 10000.0


## 하위 리그 로스터 크루를 등급제로 만든다 (이름 기반 고정 난수라 매번 같은 실력)
func _roster_crew(names: Array) -> Array:
	var grades: Array = WEC_TIER_GRADES[str(tier())]
	var out: Array = []
	for i in 3:
		var g: String = grades[i]
		var nm: String = names[i] if i < names.size() else "M. Brundle"
		var rg: Array = GRADE_RANGE[g]
		out.append({"name": nm, "grade": g, "speed": rg[0] + (rg[1] - rg[0]) * _hash01(nm, 0), "cons": 0.66 + 0.26 * _hash01(nm, 1), "tyreMgmt": 0.7 + 0.2 * _hash01(nm, 2), "aggr": 0.3 + 0.5 * _hash01(nm, 3), "def": 0.6 + 0.25 * _hash01(nm, 4), "wet": 0.55 + 0.4 * _hash01(nm, 5)})
	return out


# ═════════ 파워유닛·기어박스 마일리지 (F1) ═════════
## 시즌 할당량(게임 기준)과 부품 수명(몇 경기). 할당을 넘겨 새 부품을 넣으면 그리드 강등(처음 10, 이후 5)
const PU_ALLOC := {"ice": 4, "ers": 3, "gb": 4}
const PU_LIFE := {"ice": 6.0, "ers": 7.0, "gb": 5.0}
const PU_KO := {"ice": "엔진(ICE)", "ers": "ERS", "gb": "기어박스"}


func pu_on() -> bool:
	return not is_wec() and not is_spec_tier()


func pu_state(slot: int) -> Dictionary:
	if not hq.has("pu") or (hq["pu"] as Array).size() < 2:
		hq["pu"] = [_pu_fresh(), _pu_fresh()]
	return hq["pu"][slot]


func _pu_fresh() -> Dictionary:
	return {"ice": {"n": 1, "wear": 0.0, "pen": 0}, "ers": {"n": 1, "wear": 0.0, "pen": 0}, "gb": {"n": 1, "wear": 0.0, "pen": 0}}


## 낡은 부품일수록 신뢰성 하락 (수명 70% 넘으면 급격히)
func pu_rel_pen(slot: int) -> float:
	if not pu_on():
		return 0.0
	var p := 0.0
	var st := pu_state(slot)
	for k in PU_ALLOC:
		p += maxf(0.0, float(st[k]["wear"]) - 0.7) * 0.12
	return p


## 새 부품 투입. 할당 초과면 다음 레이스 그리드 강등. 돌려주는 값 = 강등 칸 수
func pu_replace(slot: int, k: String, forced: bool = false) -> int:
	var st := pu_state(slot)
	var e: Dictionary = st[k]
	e["n"] = int(e["n"]) + 1
	e["wear"] = 0.0
	var pen := 0
	if int(e["n"]) > int(PU_ALLOC[k]):
		pen = 10 if int(e.get("pen", 0)) == 0 else 5
		e["pen"] = int(e.get("pen", 0)) + 1
		_add_mod("grid_pen", slot, pen)
	news("🔧 %s %s 새 부품 (%d/%d)%s%s" % [_slot_name(slot), PU_KO[k], int(e["n"]), int(PU_ALLOC[k]), (" — 할당 초과, 그리드 %d계단 강등" % pen) if pen > 0 else "", " (수명 다해 교체)" if forced else ""])
	save()
	return pen


func _pu_after_race(notes: Array) -> void:
	if not pu_on():
		return
	var old_practice: bool = bool(hq.get("pu_old_practice", true))
	for slot in 2:
		var st := pu_state(slot)
		for k in PU_ALLOC:
			# 레이스 거리 + (연습에 새 부품을 쓰면) 연습 거리
			st[k]["wear"] = snappedf(float(st[k]["wear"]) + (1.0 + (0.0 if old_practice else 0.25)) / float(PU_LIFE[k]), 0.001)
			if float(st[k]["wear"]) >= 1.0:
				var pen := pu_replace(slot, k, true)
				notes.append("🔧 %s %s 수명 다해 교체%s" % [_slot_name(slot), PU_KO[k], (" · 그리드 -%d" % pen) if pen > 0 else ""])


## 레이스 시뮬레이션에 넘길 옵션 (팀·엔진·내 차 보정·WEC 엔트리)
func race_opts(sprint: bool = false) -> Dictionary:
	var o: Dictionary = _race_opts(sprint)
	if pu_on():
		o["pu_rel"] = [pu_rel_pen(0), pu_rel_pen(1)]
	o["difficulty"] = int(hq.get("difficulty", 1))
	var em: Dictionary = hq.get("next_mods", {})
	if not em.is_empty():
		var e2: Dictionary = em.duplicate(true)
		if sprint:
			e2.erase("grid_pen") # 그리드 강등은 피처(본선)에만
		o["event_mods"] = e2
	return o


# ═════════ 커리어 이벤트 (레이스 사이 선택) ═════════
## hq["event"] = {kind, title, msg, opts:[{label, fx}]} · fx 는 resolve_event 에서 적용.
## 효과 중 다음 레이스에만 걸리는 것은 hq["next_mods"] {focus:[#1,#2], rel, grid_pen:[#1,#2], practice} 에 쌓는다.
func _slot_name(slot: int) -> String:
	if is_wec():
		var cr: Array = my_crew(slot)
		return "#%d 차 %s" % [slot + 1, cr[0]["name"] if not cr.is_empty() else ""]
	return "#%d %s" % [slot + 1, my_driver(slot)["name"]]


func _maybe_event() -> void:
	if hq.has("event") and hq["event"] != null:
		return
	if rnd() > 0.38:
		return
	var kinds: Array = ["unhappy", "rumor", "sponsor", "media", "test"]
	if not is_wec() and not is_spec_tier():
		kinds.append("pu")
	var k: String = kinds[int(rnd() * kinds.size()) % kinds.size()]
	var slot: int = 0 if rnd() < 0.5 else 1
	var who := _slot_name(slot)
	var ev := {}
	match k:
		"unhappy":
			ev = {"title": "😠 %s 불만" % who, "msg": "“차가 생각만큼 안 따라와요. 팀이 저를 믿고 있는지 모르겠어요.” 드라이버가 면담을 요청했어요.",
				"opts": [{"label": "면담 + 사기 보너스 (0.30M)", "fx": {"cash": -0.30, "focus": [slot, 10]}}, {"label": "결과로 보여달라고 한다", "fx": {"focus": [slot, -10], "pop": -0.01}}]}
		"rumor":
			ev = {"title": "📰 이적 루머: %s" % who, "msg": "라이벌 팀이 우리 드라이버에게 관심을 보인다는 기사가 났어요. 드라이버도 흔들리는 눈치예요.",
				"opts": [{"label": "공개 신임 + 보너스 (0.50M)", "fx": {"cash": -0.50, "focus": [slot, 6], "pop": 0.01}}, {"label": "무시한다", "fx": {"focus": [slot, -6], "speed": [slot, -0.004]}}]}
		"sponsor":
			ev = {"title": "🤝 스폰서 추가 홍보 요청", "msg": "메인 스폰서가 다음 주말에 팬 행사를 하자고 해요. 돈은 되지만 연습 시간이 줄어요.",
				"opts": [{"label": "수락 (+0.45M, 연습 2랩 감소)", "fx": {"cash": 0.45, "practice": 2}}, {"label": "정중히 거절 (평판 -1%)", "fx": {"pop": -0.01}}]}
		"media":
			ev = {"title": "🎤 언론 인터뷰", "msg": "다음 레이스 전 기자회견. 목표를 어떻게 말할까요?",
				"opts": [{"label": "\"우승을 노린다\" (평판 +3%, 압박에 집중력 -5)", "fx": {"pop": 0.03, "focus": [-1, -5]}}, {"label": "\"한 경기씩 차분히\" (집중력 +4)", "fx": {"focus": [-1, 4]}}]}
		"test":
			ev = {"title": "🧪 타이어 공급사 테스트 초청", "msg": "공급사가 개발 테스트에 차를 빌려달라고 해요. 데이터와 돈을 주지만 정비 부담이 생겨요.",
				"opts": [{"label": "참가 (+0.35M, 다음 레이스 신뢰성 소폭 하락)", "fx": {"cash": 0.35, "rel": -0.02}}, {"label": "거절", "fx": {}}]}
		"pu":
			ev = {"title": "⚙️ 파워유닛 이상 징후 (%s)" % who, "msg": "텔레메트리에서 엔진 진동이 커졌어요. 새 파워유닛으로 바꾸면 그리드 5계단 강등, 그대로 쓰면 고장 위험이 올라가요.",
				"opts": [{"label": "새 PU 교체 (그리드 -5)", "fx": {"grid_pen": [slot, 5]}}, {"label": "그대로 달린다 (신뢰성 크게 하락)", "fx": {"rel": -0.08}}]}
	ev["kind"] = k
	hq["event"] = ev
	news("이벤트: %s" % ev["title"])


func _add_mod(key: String, slot: int, v: float) -> void:
	if not hq.has("next_mods"):
		hq["next_mods"] = {}
	var nm: Dictionary = hq["next_mods"]
	if key == "focus" or key == "grid_pen":
		var arr: Array = nm.get(key, [0, 0])
		for s in [0, 1]:
			if slot < 0 or s == slot:
				arr[s] = arr[s] + v
		nm[key] = arr
	else:
		nm[key] = float(nm.get(key, 0.0)) + v


func resolve_event(i: int) -> String:
	var ev: Variant = hq.get("event")
	if ev == null:
		return ""
	var opts: Array = ev["opts"]
	i = clampi(i, 0, opts.size() - 1)
	var fx: Dictionary = opts[i]["fx"]
	if fx.has("cash"):
		var cv: float = float(fx["cash"])
		hq["cash"] = r2(float(hq["cash"]) + cv)
		if cv < 0.0:
			book("staff", -cv)
		else:
			book("spon", cv)
	if fx.has("pop"):
		hq["pop"] = clampf(r2(float(hq["pop"]) + float(fx["pop"])), 0.15, 0.98)
	if fx.has("focus"):
		_add_mod("focus", int(fx["focus"][0]), float(fx["focus"][1]))
	if fx.has("grid_pen"):
		_add_mod("grid_pen", int(fx["grid_pen"][0]), float(fx["grid_pen"][1]))
	if fx.has("rel"):
		_add_mod("rel", -1, float(fx["rel"]))
	if fx.has("practice"):
		_add_mod("practice", -1, float(fx["practice"]))
	if fx.has("speed") and not is_wec():
		var d := my_driver(int(fx["speed"][0]))
		d["speed"] = maxf(0.6, float(d["speed"]) + float(fx["speed"][1]))
	var lab: String = opts[i]["label"]
	news("%s → %s" % [ev["title"], lab])
	hq["event"] = null
	save()
	return lab


## 주말 시작까지 고르지 않으면 마지막(무난한) 선택지로 처리
func resolve_event_default() -> void:
	var ev: Variant = hq.get("event")
	if ev != null:
		resolve_event((ev["opts"] as Array).size() - 1)


func _race_opts(sprint: bool) -> Dictionary:
	if not is_wec():
		return {"teams": race_teams(), "engines": hq["engines"], "my_mods": my_mods(), "rules": race_rules(sprint)}
	if not is_spec_tier():
		return {"wec_hy": hq["teams"], "wec_field": {"hy": hq["field"], "gt": DB.wec["field"]["gt"]}, "my_mods": my_mods(), "bop_ai": hq.get("bop_ai", {})}
	var cls: String = WEC_TIER_CLS.get(tier(), "P2")
	var entries: Array = []
	var rs: Array = DB.wec["rosters"][str(tier())]
	for ri in rs.size():
		var r: Dictionary = rs[ri]
		var team := {"name": r["name"], "color": r["color"], "rim": "#ffffff", "perf": r["perf"], "rel": r["rel"], "crew": 0.82, "strategy": 0.8}
		var names: Array = r["crew_names"]
		for k in 2:
			# 2번 차는 크루 순서를 돌려서 다른 라인업으로
			var nm2: Array = [names[(0 + k) % 3], names[(1 + k) % 3], names[(2 + k) % 3]]
			entries.append({"cls": cls, "team": team, "k": k, "ti": ri, "crew": _roster_crew(nm2), "mine": false})
	var me: Dictionary = my_team_dict()
	var eng: Dictionary = DB.wec["engines"].get(me.get("engine", ""), {"pwr": 0.88, "eff": 1.0, "relMod": 0.0})
	var my_t := {"name": me["name"], "color": me["color"], "rim": me.get("rim", "#ffffff"), "perf": float(me["perf"]), "rel": clampf(float(me["rel"]) + float(eng["relMod"]), 0.75, 0.98), "crew": float(me["crew"]), "strategy": float(me["strategy"]), "eng_eff": float(eng["eff"])}
	for k in 2:
		entries.append({"cls": cls, "team": my_t, "k": k, "ti": 99, "crew": my_crew(k), "mine": true})
	if tier() == 2:
		# 유러피언 LMP2 시리즈: LMGT3 가 함께 달리는 멀티클래스
		var gt: Array = DB.wec["gt"]
		for e in DB.wec["field"]["gt"]:
			var t2: Dictionary = gt[int(e["ti"])]
			entries.append({"cls": "GT", "team": {"name": t2["name"], "color": t2["color"], "perf": t2["perf"], "rel": t2["rel"], "crew": t2["crew"], "strategy": t2["strategy"]}, "k": int(e["k"]), "ti": 100 + int(e["ti"]), "crew": e["crew"], "mine": false})
	return {"wec_entries": entries, "my_mods": my_mods(), "min_drive": WEC_MIN_DRIVE[str(tier())]}


## 내 차가 속한 클래스
func my_class() -> String:
	if not is_wec():
		return "F1"
	if not is_spec_tier():
		return "HY"
	return WEC_TIER_CLS.get(tier(), "P2")


func race_my_index() -> int:
	return race_teams().size() - 1 if is_spec_tier() else my_team()


## 화면용 차량 능력치 [이름, 값(0~99), 보너스]
func car_stats() -> Dictionary:
	var t := my_team_dict()
	var ex := hq_extra()
	if is_wec():
		var eng: Dictionary = DB.wec["engines"].get(t.get("engine", ""), {"pwr": 0.88, "eff": 1.0, "relMod": 0.0})
		var pf: float = float(t["perf"])
		var rows_w := [
			["에어로(공력)", 0.76 + pf * 0.16, hq_bonus("aero") + ex["aero"]],
			["파워트레인", float(eng["pwr"]), hq_bonus("engine") + ex["engine"]],
			["섀시·그립", 0.77 + pf * 0.16, hq_bonus("chassis") + ex["chassis"]],
			["신뢰도", float(t["rel"]) + float(eng["relMod"]), hq_bonus("rel") + ex["rel"]],
			["피트 크루", float(t["crew"]), hq_bonus("crew")],
		]
		var out_w: Array = []
		var ovr_w := 0.0
		for i in rows_w.size():
			var v := mini(99, int(round((float(rows_w[i][1]) + float(rows_w[i][2])) * 100.0)))
			out_w.append([rows_w[i][0], v, int(round(float(rows_w[i][2]) * 100.0))])
			if i < 4:
				ovr_w += v
		return {"rows": out_w, "ovr": int(round(ovr_w / 4.0))}
	var eng_base: float = spec_engine() if is_spec_tier() else float(hq["engines"].get(t["engine"], 0.88))
	var rows := [
		["에어로(공력)", float(t["aero"]), hq_bonus("aero") + ex["aero"]],
		["파워트레인", eng_base, hq_bonus("engine") + ex["engine"]],
		["섀시·그립", float(t["chassis"]), hq_bonus("chassis") + ex["chassis"]],
		["신뢰도", float(t["rel"]), hq_bonus("rel") + ex["rel"]],
		["피트 크루", 0.85, hq_bonus("crew")],
	]
	var out: Array = []
	var ovr := 0.0
	for i in rows.size():
		var v := mini(99, int(round((float(rows[i][1]) + float(rows[i][2])) * 100.0)))
		out.append([rows[i][0], v, int(round(float(rows[i][2]) * 100.0))])
		if i < 4:
			ovr += v
	return {"rows": out, "ovr": int(round(ovr / 4.0))}


# ═════════ R&D 개발 프로젝트 ═════════
func proj_lock(k: String) -> String:
	if is_spec_tier() and (k == "aero" or k == "engine"):
		return "스펙 시리즈 (공통 섀시·엔진)"
	if is_wec() and not is_spec_tier() and k != "rel" and hq["dev_target"] != "next" and int(hq.get("jokers", 0)) <= 0:
		return "EVO 조커 소진 (다음 호몰로게이션까지 성능 개발 불가)"
	return ""


func dev_cost(sz: String) -> float:
	return r2(float(D["dev"][sz]["cost"]) * tier_scale())


func dev_lead(sz: String) -> int:
	var f := int(hq["base"]["factory"])
	return maxi(1, int(D["dev"][sz]["lead"]) - (1 if f >= 3 else 0) - (1 if f >= 5 else 0))


func frontier_gap(k: String) -> float:
	if is_wec() or is_spec_tier() or k == "rel" or k == "engine":
		return 0.0
	var col := "aero" if k == "aero" else "chassis"
	var top := 0.0
	for t in hq["teams"]:
		top = maxf(top, float(t[col]))
	return maxf(0.0, top - (float(my_team_dict()[col]) + hq_bonus(k)))


func catch_up_mult(gap: float) -> float:
	return minf(1.8, 1.0 + 3.5 * gap)


func gain_mult(k: String) -> float:
	var m := catch_up_mult(frontier_gap(k))
	if k == "aero":
		m *= atr_mult()
	if k == "engine" and not is_works():
		m *= 0.4
	var ce: Variant = hq["chief"].get(D["dev"]["dept"][k])
	if ce != null:
		if ce["tier"] == "S급":
			m *= 1.12
		elif ce["tier"] == "A급":
			m *= 1.06
	return m


func corr_mean(k: String) -> float:
	var f := int(hq["base"][D["dev"]["fac"][k]])
	var sm := int(hq["base"]["sim"])
	return 0.62 + 0.07 * (f - 1) + 0.025 * (sm - 1)


func corr_spread(k: String, sz: String) -> float:
	var f := int(hq["base"][D["dev"]["fac"][k]])
	return float(D["dev"][sz]["sd"]) * (1.15 - 0.15 * (f - 1))


func _pkg_count(k: String, next: bool) -> int:
	return int(hq["pkg_n_next"][k]) if next else int(hq["pkg_n"][k])


## 예상 효과 범위 [최소, 최대] (비율, 0.01 = 1%)
func dev_range(k: String, sz: String) -> Array:
	var n := _pkg_count(k, hq["dev_target"] == "next")
	var g: float = float(D["dev"][sz]["gain"]) * gain_mult(k) * pow(float(D["dev"]["decay"]), n)
	var m := corr_mean(k)
	var sp := corr_spread(k, sz)
	return [g * maxf(0.15, m - sp), g * minf(1.45, m + sp)]


func can_start_project(k: String, sz: String) -> bool:
	return hq["proj"][k] == null and proj_lock(k) == "" and float(hq["cash"]) >= dev_cost(sz)


func start_project(k: String, sz: String) -> bool:
	if not can_start_project(k, sz):
		return false
	var cost := dev_cost(sz)
	var next: bool = hq["dev_target"] == "next"
	hq["cash"] = r2(hq["cash"] - cost)
	hq["spent_cap"] = r2(hq["spent_cap"] + cost)
	book("rnd", cost)
	if is_wec() and not is_spec_tier() and k != "rel" and not next:
		hq["jokers"] = int(hq.get("jokers", 0)) - 1
	hq["proj"][k] = {"size": sz, "due": int(hq["race_count"]) + dev_lead(sz), "next": next}
	news("🛠 %s %s%s 개발 착수 — %d경기 후 투입 (%.2fM)" % [D["dev_ko"][k], D["dev"][sz]["ko"], " (차세대)" if next else "", dev_lead(sz), cost])
	return true


func _complete_projects(notes: Array) -> void:
	for k in DEV_AREAS:
		var pj: Variant = hq["proj"][k]
		if pj == null or int(hq["race_count"]) < int(pj["due"]):
			continue
		var d: Dictionary = D["dev"][pj["size"]]
		var next: bool = pj["next"]
		var corr := clampf(corr_mean(k) + gauss(corr_spread(k, pj["size"])), 0.15, 1.45)
		var g := snappedf(float(d["gain"]) * corr * pow(float(D["dev"]["decay"]), _pkg_count(k, next)) * gain_mult(k), 0.0001)
		if next:
			hq["pkg_n_next"][k] = int(hq["pkg_n_next"][k]) + 1
			hq["dev_next"][k] = snappedf(float(hq["dev_next"][k]) + g, 0.0001)
		else:
			hq["pkg_n"][k] = int(hq["pkg_n"][k]) + 1
			hq["dev"][k] = snappedf(float(hq["dev"][k]) + g, 0.0001)
		var tag := "⚠ 상관관계 실패" if corr < 0.45 else ("🎯 기대 이상" if corr > 1.1 else "✅ 투입")
		var msg := "%s: %s %s%s 성능 +%.2f%% (%s 상관도 %d%%)" % [tag, D["dev_ko"][k], d["ko"], " (차세대)" if next else "", g * 100.0, D["fac_ko"][D["dev"]["fac"][k]], int(round(corr * 100.0))]
		news(msg)
		notes.append(msg)
		hq["proj"][k] = null


# ═════════ 설비 ═════════
func fac_cost(k: String) -> float:
	return snappedf(float(D["fac_cost"][k]) * int(hq["base"][k]), 0.1)


func build_facility(k: String) -> bool:
	var lv := int(hq["base"][k])
	var cost := fac_cost(k)
	if lv >= 5 or float(hq["cash"]) < cost:
		return false
	var ds := int(D["econ"]["deprSeasons"])
	var per := snappedf(cost / ds, 0.001)
	hq["cash"] = r2(hq["cash"] - cost)
	hq["depr"].append({"k": k, "per": per, "left": ds - 1})
	hq["spent_cap"] = r2(hq["spent_cap"] + per)
	book("fac", per)
	hq["base"][k] = lv + 1
	news("🏗 %s Lv.%d 완공 (%.1fM · 코스트캡 %.2fM × %d시즌 감가상각)" % [D["fac_ko"][k], lv + 1, cost, per, ds])
	return true


# ═════════ AI 팀 개발·규정 변경 ═════════
func budget_of_team(name: String) -> float:
	var ib: Array = SD()["init_budget"].get(name, [9.0, 0.6])
	return float(ib[0])


func _ai_develop(frac: float) -> void:
	if is_spec_tier():
		return
	if is_wec():
		for ti in hq["teams"].size():
			if ti == my_team():
				continue
			var tw: Dictionary = hq["teams"][ti]
			tw["perf"] = minf(0.95, snappedf(float(tw["perf"]) + 0.003 * frac, 0.0001))
			tw["rel"] = minf(0.97, snappedf(float(tw["rel"]) + 0.004 * frac, 0.0001))
		return
	var st := standings()
	var teams: Array = hq["teams"]
	for ti in teams.size():
		if ti == my_team():
			continue
		var t: Dictionary = teams[ti]
		var r := 8
		for i in st.size():
			if st[i]["name"] == t["name"]:
				r = i + 1
		var res := clampf(budget_of_team(t["name"]) / 13.0, 0.55, 1.05)
		var g := (0.024 * atr_pct(r) * res + uni(-0.004, 0.006)) * frac
		t["aero"] = minf(0.985, snappedf(float(t["aero"]) + g, 0.0001))
		t["chassis"] = minf(0.985, snappedf(float(t["chassis"]) + g * 0.8, 0.0001))
		t["rel"] = minf(0.98, snappedf(float(t["rel"]) + 0.004 * frac, 0.0001))
	for e in hq["engines"]:
		hq["engines"][e] = minf(0.95, snappedf(float(hq["engines"][e]) + uni(0.002, 0.006) * frac, 0.0001))


func _regulation_reset(notes: Array) -> void:
	for k in DEV_AREAS:
		hq["dev"][k] = snappedf(float(hq["dev"][k]) * 0.3 + float(hq["dev_next"][k]), 0.0001)
		hq["dev_next"][k] = 0.0
		hq["pkg_n"][k] = int(hq["pkg_n_next"][k])
		hq["pkg_n_next"][k] = 0
		if hq["proj"][k] != null and hq["proj"][k]["next"]:
			hq["proj"][k]["next"] = false
	hq["dev_target"] = "cur"
	hq["jokers"] = int(D["econ"]["jokersPerCycle"])
	if is_wec():
		var mw := "📜 신규 호몰로게이션 주기 (시즌 %d): 현행 개발 30%% 승계, 차세대 100%% 반영 · EVO 조커 재지급" % int(hq["season"])
		news(mw)
		notes.append(mw)
		return
	var b: Dictionary = hq["base"]
	var my_infra := (int(b["wind"]) + int(b["bench"]) + int(b["rig"]) + int(b["sim"]) + int(b["factory"])) / 5.0
	var teams: Array = hq["teams"]
	for ti in teams.size():
		var t: Dictionary = teams[ti]
		var infra := (my_infra - 2.0) * 0.012 if ti == my_team() else (clampf(budget_of_team(t["name"]) / 13.0, 0.55, 1.05) - 0.8) * 0.05
		t["aero"] = snappedf(0.86 + (float(t["aero"]) - 0.86) * 0.55 + infra + uni(-0.015, 0.015), 0.0001)
		t["chassis"] = snappedf(0.86 + (float(t["chassis"]) - 0.86) * 0.55 + infra + uni(-0.015, 0.015), 0.0001)
	for e in hq["engines"]:
		hq["engines"][e] = snappedf(0.88 + (float(hq["engines"][e]) - 0.88) * 0.5 + uni(-0.015, 0.015), 0.0001)
	var msg := "📜 신규 기술 규정 발효 (시즌 %d): 전 팀 격차 축소 · 설비 수준이 새 차 출발점에 반영 · 현행 개발 30%%만 승계, 차세대 선행 개발 100%% 반영" % int(hq["season"])
	news(msg)
	notes.append(msg)


func _on_tier_change() -> void:
	for k in DEV_AREAS:
		hq["dev"][k] = snappedf(float(hq["dev"][k]) * 0.25, 0.0001)
		hq["dev_next"][k] = 0.0
		hq["pkg_n"][k] = 0
		hq["pkg_n_next"][k] = 0
		hq["proj"][k] = null
	hq["cap_adj"] = 0.0
	hq["cost_cap_limit"] = cap_limit_now()
	hq["team_pts"] = {}
	_refresh_pay_pool()


func _cost_cap_audit(notes: Array) -> void:
	var lim: float = hq["cost_cap_limit"]
	var over := r2(float(hq["spent_cap"]) - lim)
	hq["atr_pen"] = 0.0
	if over > 0.0:
		var pct := over / lim
		if pct < float(D["econ"]["minorPct"]):
			var fine := r2(over * 2.0)
			hq["cash"] = r2(hq["cash"] - fine)
			hq["cap_adj"] = 0.0
			var msg := "⚖ 코스트캡 경미한 위반 (%.2fM · %.1f%% 초과): 벌금 %.2fM" % [over, pct * 100.0, fine]
			news(msg)
			notes.append(msg)
		else:
			var fine2 := r2(over * 3.0)
			hq["cash"] = r2(hq["cash"] - fine2)
			hq["cap_adj"] = -over
			hq["atr_pen"] = 0.10
			hq["pop"] = maxf(0.15, r2(hq["pop"] - 0.05))
			var msg2 := "🚨 코스트캡 중대한 위반 (%.2fM · %.1f%% 초과): 벌금 %.2fM, 다음 시즌 캡 -%.2fM, 풍동 시간 10%% 삭감, 평판 -5%%" % [over, pct * 100.0, fine2, over]
			news(msg2)
			notes.append(msg2)
	else:
		hq["cap_adj"] = r2(minf(-over, float(tier_meta()["cap"]) * float(D["econ"]["carryPct"])))


# ═════════ 엔진 공급 (정치) ═════════
func evaluate_engine_politics() -> void:
	if is_wec():
		hq["politics"] = {}
		return
	_evaluate_engine_politics_f1()


## WEC 신규 팀: 시즌 전에 하이퍼카 패키지 교체
func change_package(pkg: String) -> bool:
	if not is_wec() or hq["entry"] != "create" or not is_preseason() or not WEC_PKGS.has(pkg):
		return false
	hq["engine_supplier"] = pkg
	my_team_dict()["engine"] = pkg
	news("🔧 하이퍼카 패키지 계약: %s" % WEC_PKGS[pkg])
	return true


func _evaluate_engine_politics_f1() -> void:
	var pol := {
		"Mercedes": {"blocked": false, "reason": "공급 가능 (1.2M)", "fee": 1.2},
		"Ferrari": {"blocked": false, "reason": "공급 가능 (1.5M)", "fee": 1.5},
		"Red Bull Ford": {"blocked": false, "reason": "공급 가능 (1.1M)", "fee": 1.1},
		"Honda": {"blocked": false, "reason": "공급 가능 (1.0M)", "fee": 1.0},
	}
	hq["politics"] = pol
	if is_works():
		var own: String = D["works"][my_team_dict()["name"]]
		for k in pol:
			pol[k] = {"blocked": k != own, "reason": "자사 워크스 파워유닛" if k == own else "워크스 규정 (타사 엔진 사용 불가)", "fee": 0.0}
		return
	var rank := my_rank_now()
	var pts := 0
	for r in standings():
		if r["mine"]:
			pts = r["pts"]
	var sup: String = hq["engine_supplier"]
	if pts >= 30 and rank <= 2:
		for k in ["Ferrari", "Mercedes"]:
			if sup != k:
				pol[k]["blocked"] = true
				pol[k]["reason"] = "타이틀 경쟁 라이벌 견제 (보드진 공급 거부)"
	if float(hq["pop"]) < 0.42 and sup != "Ferrari":
		pol["Ferrari"]["blocked"] = true
		pol["Ferrari"]["reason"] = "팀 평판 부족 (필요 42%% / 현재 %d%%)" % int(round(float(hq["pop"]) * 100.0))
	if float(hq["pop"]) < 0.38 and hq["region"] == "uk" and sup != "Honda":
		pol["Honda"]["blocked"] = true
		pol["Honda"]["reason"] = "기존 독점 계약 우선 (평판 38% 이상 필요)"


func change_engine(e: String) -> bool:
	if not is_preseason() or e == hq["engine_supplier"]:
		return false
	var p: Variant = hq["politics"].get(e)
	if p == null or p["blocked"]:
		return false
	var fee: float = p["fee"]
	if float(hq["cash"]) < fee or float(hq["spent_cap"]) + fee * 0.5 > float(hq["cost_cap_limit"]) + 0.000001:
		return false
	hq["cash"] = r2(hq["cash"] - fee)
	hq["spent_cap"] = r2(hq["spent_cap"] + fee * 0.5)
	hq["engine_supplier"] = e
	my_team_dict()["engine"] = e
	news("🔧 %s 파워유닛 공급 계약 체결 (%.1fM)" % [e, fee])
	return true


# ═════════ 인력: 수석 엔지니어 ═════════
func can_hire_engineer(i: int) -> bool:
	var en: Dictionary = hq["eng_pool"][i]
	return is_preseason() and not en["hired"] and float(hq["pop"]) >= float(en["reqPop"]) and float(hq["cash"]) >= float(en["cost"])


func hire_engineer(i: int) -> bool:
	if not can_hire_engineer(i):
		return false
	var en: Dictionary = hq["eng_pool"][i]
	hq["cash"] = r2(hq["cash"] - float(en["cost"]))
	book("staff", float(en["cost"]))
	for x in hq["eng_pool"]:
		if x["dept"] == en["dept"]:
			x["hired"] = false
	en["hired"] = true
	hq["chief"][en["dept"]] = en.duplicate(true)
	news("[%s] 수석 엔지니어 %s 영입 완료!" % [en["deptKo"], en["name"]])
	return true


# ═════════ 드라이버 ═════════
func my_driver(slot: int) -> Dictionary:
	return my_team_dict()["drivers"][slot]


func drv_req_pop(m: Dictionary) -> float:
	return clampf(snappedf((float(m["speed"]) - 0.80) * 4.0, 0.01), 0.0, 0.9)


func can_hire_driver(i: int) -> bool:
	var m: Dictionary = hq["market"][i]
	return is_preseason() and float(hq["cash"]) >= float(m["buyout"]) and float(hq["pop"]) >= drv_req_pop(m)


func _set_driver(slot: int, d: Dictionary) -> void:
	my_team_dict()["drivers"][slot] = d
	hq["pay_drivers"].erase(str(slot))


func hire_driver(i: int, slot: int) -> bool:
	if not can_hire_driver(i):
		return false
	var m: Dictionary = hq["market"][i]
	hq["cash"] = r2(hq["cash"] - float(m["buyout"]))
	book("staff", float(m["buyout"]))
	hq["market"].remove_at(i)
	hq["salaries"][m["name"]] = m["salary"]
	_set_driver(slot, {"name": m["name"], "speed": m["speed"], "cons": m["cons"], "tyreMgmt": m["tyre"], "aggr": 0.65, "def": 0.82, "wet": m["wet"], "age": int(m.get("age", 24))})
	news("FA 드라이버 %s(%d세) 영입 완료 (#%d 시트)." % [m["name"], int(m.get("age", 24)), slot + 1])
	return true


func swap_reserve(slot: int) -> bool:
	var rv: Dictionary = hq["reserve"]
	var cur := my_driver(slot)
	hq["reserve"] = {"name": cur["name"], "age": cur.get("age", 25), "speed": cur["speed"], "cons": cur["cons"], "tyre": cur["tyreMgmt"], "aggr": cur["aggr"], "def": cur["def"], "wet": cur["wet"]}
	_set_driver(slot, {"name": String(rv["name"]).replace(" (리저브)", ""), "speed": rv["speed"], "cons": rv["cons"], "tyreMgmt": rv["tyre"], "aggr": rv.get("aggr", 0.60), "def": rv.get("def", 0.76), "wet": rv.get("wet", 0.80), "age": int(rv.get("age", 22))})
	return true


func junior_value(j: Dictionary) -> float:
	return snappedf(maxf(0.3, (float(j["cur"]) - 0.70) * 12.0 + (float(j["pot"]) - 0.85) * 8.0 + (0.4 if int(j["age"]) <= 19 else 0.0)), 0.1)


func scout_junior() -> bool:
	if float(hq["cash"]) < 1.2 or hq["juniors"].size() >= 4:
		return false
	hq["cash"] = r2(hq["cash"] - 1.2)
	book("staff", 1.2)
	var sn: Array = D["surnames"]
	var nj := {"name": "%s. %s" % [char(65 + rng.randi_range(0, 25)), sn[rng.randi_range(0, sn.size() - 1)]], "age": rng.randi_range(17, 19), "pot": snappedf(uni(0.86, 0.96), 0.01), "cur": snappedf(uni(0.72, 0.80), 0.01), "value": 0.0}
	nj["value"] = junior_value(nj)
	hq["juniors"].append(nj)
	news("🔎 유망주 %s(%d세) 아카데미 입단" % [nj["name"], nj["age"]])
	return true


func can_train_junior(i: int) -> bool:
	var j: Dictionary = hq["juniors"][i]
	return float(hq["cash"]) >= 0.8 and float(j["cur"]) < float(j["pot"]) and int(j.get("last_train", -1)) != int(hq["race_count"])


func train_junior(i: int) -> bool:
	if not can_train_junior(i):
		return false
	var j: Dictionary = hq["juniors"][i]
	hq["cash"] = r2(hq["cash"] - 0.8)
	book("staff", 0.8)
	j["last_train"] = int(hq["race_count"])
	var gain := snappedf(0.04 * (1.0 + (int(hq["base"]["sim"]) - 1) * 0.25), 0.001)
	j["cur"] = minf(float(j["pot"]), snappedf(float(j["cur"]) + gain, 0.01))
	j["value"] = junior_value(j)
	return true


func _junior_driver(j: Dictionary) -> Dictionary:
	var nm := String(j["name"]).replace(" (F2 유망주)", "").replace(" (유망주)", "")
	return {"name": nm, "speed": j["cur"], "cons": j["cur"], "tyreMgmt": j["cur"], "aggr": 0.64, "def": 0.78, "wet": j["cur"], "age": int(j["age"])}


func promote_junior(i: int, slot: int) -> bool:
	var j: Dictionary = hq["juniors"][i]
	var old := my_driver(slot)
	hq["reserve"] = {"name": old["name"], "age": old.get("age", 26), "speed": old["speed"], "cons": old["cons"], "tyre": old["tyreMgmt"], "aggr": old["aggr"], "def": old["def"], "wet": old["wet"]}
	var nd := _junior_driver(j)
	_set_driver(slot, nd)
	hq["juniors"].remove_at(i)
	news("🌟 아카데미 유망주 %s(%d세), #%d 주전으로 승격!" % [nd["name"], nd["age"], slot + 1])
	return true


func junior_to_reserve(i: int) -> bool:
	var j: Dictionary = hq["juniors"][i]
	var nd := _junior_driver(j)
	hq["reserve"] = {"name": nd["name"], "age": nd["age"], "speed": nd["speed"], "cons": nd["cons"], "tyre": nd["tyreMgmt"], "aggr": 0.62, "def": 0.78, "wet": nd["wet"]}
	hq["juniors"].remove_at(i)
	news("유망주 %s를 리저브 드라이버로 등록했습니다." % nd["name"])
	return true


func sell_junior(i: int) -> bool:
	var j: Dictionary = hq["juniors"][i]
	hq["cash"] = r2(hq["cash"] + float(j["value"]))
	news("유망주 %s 이적료 +%.1fM 수령." % [j["name"], float(j["value"])])
	hq["juniors"].remove_at(i)
	return true


# ── 페이 드라이버 (새 기능): 실력은 낮지만 시즌 후원금을 들고 온다. 하위 리그·약팀 중심 ──
func _refresh_pay_pool() -> void:
	var pool: Array = []
	if is_wec():
		hq["pay_pool"] = pool
		return
	var n := 2 if (tier() < 3 or pre_rank() >= 8) else 1
	var sn: Array = D["surnames"]
	for i in n:
		var spd := snappedf(uni(0.73, 0.80), 0.01)
		pool.append({
			"name": "%s. %s" % [char(65 + rng.randi_range(0, 25)), sn[rng.randi_range(0, sn.size() - 1)]],
			"age": rng.randi_range(19, 24), "speed": spd, "cons": snappedf(spd - uni(0.0, 0.03), 0.01), "tyre": snappedf(uni(0.72, 0.80), 0.01),
			"wet": snappedf(uni(0.70, 0.80), 0.01), "money": snappedf(uni(1.2, 2.6) * (0.82 - spd) * 10.0 * 0.5 + uni(0.6, 1.0), 0.01),
		})
	hq["pay_pool"] = pool


func pay_driver_money(p: Dictionary) -> float:
	return r2(float(p["money"]) * tier_scale())


func sign_pay_driver(i: int, slot: int) -> bool:
	if not is_preseason():
		return false
	var p: Dictionary = hq["pay_pool"][i]
	_set_driver(slot, {"name": p["name"], "speed": p["speed"], "cons": p["cons"], "tyreMgmt": p["tyre"], "aggr": 0.58, "def": 0.74, "wet": p["wet"], "age": int(p["age"])})
	hq["pay_drivers"][str(slot)] = pay_driver_money(p)
	hq["salaries"][p["name"]] = 0.0
	hq["pay_pool"].remove_at(i)
	news("💼 페이 드라이버 %s 영입 (시즌 후원금 %.2fM, 경기마다 분할 입금)" % [p["name"], pay_driver_money(p)])
	return true


# ═════════ 스폰서 (새 설계) ═════════
func _prestige() -> float:
	return clampf(0.75 + 0.45 * float(hq["pop"]), 0.8, 1.2)


func _exp_pts_race(rank: int) -> float:
	return EXP_PTS[clampi(rank - 1, 0, EXP_PTS.size() - 1)]


func _spon_name(cat: String) -> String:
	var used := {}
	for c in hq["contracts"]:
		used[c["name"]] = true
	var arr: Array = SPON_NAMES[cat]
	for i in 12:
		var nm: String = arr[rng.randi_range(0, arr.size() - 1)]
		if not used.has(nm):
			return nm
	return arr[0]


## kind: stable(안정형) / perf(성과연동형) / short(단기 고액)
func _make_offer(cat: String, kind: String, name: String = "") -> Dictionary:
	var cd: Dictionary = SPON_CATS[cat]
	var b: float = float(cd["base"]) * _prestige()
	var pr := pre_rank()
	var o := {"cat": cat, "kind": kind, "name": name if name != "" else _spon_name(cat), "sat": 0.6, "reduced": false, "duty": int(cd["duty"])}
	match kind:
		"stable":
			o["base"] = r2(b * uni(0.95, 1.05))
			o["bonus"] = r2(float(cd["bonus"]) * _prestige())
			o["rate"] = 0.0
			o["seasons"] = rng.randi_range(2, 3)
			o["kpi"] = mini(pr + 2, 12)
		"perf":
			o["base"] = r2(b * 0.55)
			o["bonus"] = 0.0
			o["rate"] = snappedf(b * 0.65 / (_exp_pts_race(pr) * cal_len()), 0.0001)
			o["seasons"] = rng.randi_range(1, 2)
			o["kpi"] = pr
		_:
			o["base"] = r2(b * 1.08)
			o["bonus"] = r2(float(cd["bonus"]) * _prestige() * 0.5)
			o["rate"] = 0.0
			o["seasons"] = 1
			o["kpi"] = 0
			o["duty"] = int(cd["duty"]) + 1
	return o


func spon_eligible(cat: String) -> bool:
	var cd: Dictionary = SPON_CATS[cat]
	return float(hq["pop"]) >= float(cd["pop"]) and pre_rank() <= int(cd["rank"])


func contract_of(cat: String) -> Variant:
	for c in hq["contracts"]:
		if c["cat"] == cat:
			return c
	return null


## 팀별 시작 스폰서: 평판(명성)에 따라 금액과 개수가 다르다
func _starting_sponsors() -> void:
	hq["contracts"] = []
	var cats := ["title", "tech"]
	if float(hq["pop"]) >= 0.70:
		cats.append("global")
	for cat in cats:
		var o := _make_offer(cat, "stable")
		o["seasons"] = rng.randi_range(1, 3)
		o["seasons_left"] = o["seasons"]
		o["sat"] = 0.65
		hq["contracts"].append(o)


func _refresh_offers() -> void:
	var offers: Array = []
	for cat in SPON_CATS:
		if contract_of(cat) != null or not spon_eligible(cat):
			continue
		for kind in ["stable", "perf", "short"]:
			offers.append(_make_offer(cat, kind))
	# 만료 후 갱신 제안 (만족도 높았던 스폰서)
	for r in hq.get("renewals", []):
		if contract_of(r["cat"]) == null:
			var o := _make_offer(r["cat"], "stable", r["name"])
			o["base"] = r2(float(o["base"]) * (1.0 + (float(r["sat"]) - 0.5) * 0.2))
			o["renewal"] = true
			offers.push_front(o)
	hq["renewals"] = []
	hq["offers"] = offers


func sign_offer(i: int) -> bool:
	var o: Dictionary = hq["offers"][i]
	if contract_of(o["cat"]) != null:
		return false
	var c := o.duplicate(true)
	c["seasons_left"] = int(c["seasons"])
	hq["contracts"].append(c)
	var rest: Array = []
	for x in hq["offers"]:
		if x["cat"] != o["cat"]:
			rest.append(x)
	hq["offers"] = rest
	news("✍ [%s] %s 계약 체결 (%s · %d시즌)" % [SPON_CATS[c["cat"]]["ko"], c["name"], kind_ko(c["kind"]), int(c["seasons"])])
	return true


func kind_ko(k: String) -> String:
	return {"stable": "안정형", "perf": "성과연동형", "short": "단기 고액"}.get(k, k)


func terminate_contract(cat: String) -> bool:
	var c: Variant = contract_of(cat)
	if c == null or float(hq["cash"]) < 1.0:
		return false
	hq["cash"] = r2(hq["cash"] - 1.0)
	hq["contracts"].erase(c)
	hq["pop"] = maxf(0.15, r2(hq["pop"] - 0.02))
	news("📝 %s 계약 해지 (위약금 1.0M, 평판 -2%%)" % c["name"])
	if is_preseason() and spon_eligible(cat):
		for kind in ["stable", "perf", "short"]:
			hq["offers"].append(_make_offer(cat, kind))
	return true


## 스폰서 의무(드라이버 홍보 행사)로 줄어드는 연습 랩 수 (차당)
## 수석 엔지니어 실력 0~1 (S급 1 · A급 0.75 · B급 0.5 · C급 0.25 평균) → 연습 셋업 추천 범위 폭
func eng_quality() -> float:
	var tot := 0.0
	var n := 0
	for k in ["aero", "power", "chassis"]:
		var ce: Dictionary = hq.get("chief", {}).get(k, {})
		var t: String = String(ce.get("tier", "B급"))
		tot += {"S": 1.0, "A": 0.75, "B": 0.5, "C": 0.25}.get(t.substr(0, 1), 0.5)
		n += 1
	return tot / maxf(1.0, n)


func duty_laps() -> int:
	var n := 0
	for c in hq["contracts"]:
		n += int(c.get("duty", 0))
	n += int(float(hq.get("next_mods", {}).get("practice", 0.0)))
	return mini(5, n)


func season_sponsor_value(c: Dictionary) -> float:
	return float(c["base"]) * (0.7 if c["reduced"] else 1.0) * tier_scale()


func _sponsor_race_income(podium: bool, race_pts: int) -> float:
	var ts := tier_scale()
	var cl := cal_len()
	var tot := 0.0
	for c in hq["contracts"]:
		var b: float = float(c["base"]) * (0.7 if c["reduced"] else 1.0)
		tot += (b / cl + (float(c["bonus"]) / cl if podium else 0.0) + float(c["rate"]) * race_pts) * ts
	return tot


func _sponsor_season_end(rank: int, notes: Array) -> void:
	var keep: Array = []
	var renew: Array = []
	for c in hq["contracts"]:
		var kpi := int(c.get("kpi", 0))
		var failed := kpi > 0 and rank > kpi
		if failed:
			c["sat"] = maxf(0.0, float(c["sat"]) - 0.25)
			if c["kind"] == "perf":
				var m := "📉 %s: 성과 조항(P%d 이내) 미달로 계약 해지" % [c["name"], kpi]
				news(m)
				notes.append(m)
				continue
			if not c["reduced"]:
				c["reduced"] = true
				var m2 := "📉 %s: 성과 조항(P%d 이내) 미달 → 다음 시즌 후원금 30%% 삭감" % [c["name"], kpi]
				news(m2)
				notes.append(m2)
		elif kpi > 0:
			c["sat"] = minf(1.0, float(c["sat"]) + 0.1)
			c["reduced"] = false
		c["seasons_left"] = int(c["seasons_left"]) - 1
		if int(c["seasons_left"]) <= 0:
			var m3 := "📄 %s 계약 만료" % c["name"]
			if float(c["sat"]) >= 0.5:
				renew.append({"cat": c["cat"], "name": c["name"], "sat": c["sat"]})
				m3 += " — 갱신 제안이 들어왔어요"
			news(m3)
			notes.append(m3)
			continue
		keep.append(c)
	hq["contracts"] = keep
	hq["renewals"] = renew


## 사전 약속형 미션: 레이스 전에 목표를 고른다. 달성하면 보너스, 실패하면 평판·스폰서 만족도 하락.
func set_mission(k: String) -> void:
	hq["mission"] = k


func _mission_ok(k: String, mine: Array, classified: Array) -> bool:
	match k:
		"double_p8":
			for c in mine:
				var p := classified.find(c)
				if c.dnf != "" or p < 0 or p >= 8:
					return false
			return true
		"podium_one":
			for c in mine:
				var p2 := classified.find(c)
				if c.dnf == "" and p2 >= 0 and p2 < 3:
					return true
			return false
		"both_finish":
			for c in mine:
				if c.dnf != "":
					return false
			return true
	return false


# ═════════ 레이스 정산 (HTML finish() 커리어 부분) ═════════
## 내 드라이버 (F1: 팀 드라이버 / WEC: 각 차의 첫 번째 크루)
func salary_driver(slot: int) -> Dictionary:
	if is_wec():
		# 크루 중 연봉이 가장 높은 드라이버 기준 (영입한 플래티넘이 있으면 그만큼 비싸진다)
		var best: Dictionary = {"name": "-", "speed": 0.8}
		var bs := -1.0
		for d in my_crew(slot):
			var sv := driver_salary(d)
			if sv > bs:
				bs = sv
				best = d
		return best
	return my_driver(slot)


# ═════════ WEC 드라이버 시장 · 라인업 ═════════
const WEC_FA_NAMES := ["R. Rast", "F. Habsburg", "P. Hanson", "M. Jensen", "L. Delétraz", "R. De Wilde", "Y. Ye", "R. Andrade", "J. Aitken", "S. Bird",
	"T. Blomqvist", "D. Juncadella", "C. Ledogar", "J. Gounon", "A. Fuoco", "N. Nato", "M. Kvamme", "S. Saucy", "T. Vautier", "B. Hartley",
	"E. Cheever", "J. Hanley", "F. Scherer", "O. Rasmussen", "M. Wainwright", "T. Kimber-Smith", "G. Roda", "C. Ried", "A. Pierburg", "K. Hirakawa"]
const WEC_FA_COST := {"P": 1.6, "G": 0.9, "S": 0.45, "B": 0.2}
const WEC_FA_SAL := {"P": 1.5, "G": 0.85, "S": 0.4, "B": 0.0}
const WEC_FA_POP := {"P": 0.5, "G": 0.3, "S": 0.0, "B": 0.0}
const GRADE_KO := {"P": "플래티넘", "G": "골드", "S": "실버", "B": "브론즈"}


func _wec_taken_names() -> Dictionary:
	var out := {}
	for e in hq.get("field", []):
		for d in e["crew"]:
			out[d["name"]] = true
	for t in DB.wec["rosters"]:
		for r in DB.wec["rosters"][t]:
			for nm in r["crew_names"]:
				out[nm] = true
	return out


## 자유 계약(FA) 드라이버 목록. 없으면 만든다 (시즌마다 새로 고침).
func wec_market() -> Array:
	if not hq.has("wec_market"):
		_refresh_wec_market()
	return hq["wec_market"]


func _refresh_wec_market() -> void:
	var taken := _wec_taken_names()
	var pool: Array = []
	for nm in WEC_FA_NAMES:
		if not taken.has(nm):
			pool.append(nm)
	var out: Array = []
	for g in ["P", "G", "G", "S", "S", "B", "B"]:
		if pool.is_empty():
			break
		var nm: String = pool.pop_at(int(rnd() * pool.size()) % pool.size())
		var rg: Array = GRADE_RANGE[g]
		out.append({"name": nm, "grade": g, "speed": uni(rg[0], rg[1]), "cons": uni(0.66, 0.9), "tyreMgmt": uni(0.68, 0.9), "aggr": uni(0.3, 0.8), "def": uni(0.6, 0.85), "wet": uni(0.55, 0.92),
			"cost": r2(WEC_FA_COST[g] * (0.85 + 0.3 * rnd())), "salary": WEC_FA_SAL[g], "age": 21 + int(rnd() * 16)})
	hq["wec_market"] = out


## 영입 가능 여부. 가능하면 "" , 아니면 이유.
func wec_hire_block(i: int, slot: int, idx: int) -> String:
	var m: Array = wec_market()
	if i < 0 or i >= m.size():
		return "없음"
	var fa: Dictionary = m[i]
	var crew := my_crew(slot)
	if idx < 0 or idx >= crew.size():
		return "자리 없음"
	if float(hq["cash"]) < float(fa["cost"]):
		return "자금 부족"
	if float(hq["pop"]) < float(WEC_FA_POP[fa["grade"]]):
		return "평판 %d%% 필요" % int(WEC_FA_POP[fa["grade"]] * 100)
	var md: Variant = WEC_MIN_DRIVE.get(str(tier())) if is_spec_tier() else null
	if md != null and String(crew[idx].get("grade", "")) == md["grade"] and fa["grade"] != md["grade"]:
		var left := 0
		for d in crew:
			if String(d.get("grade", "")) == md["grade"]:
				left += 1
		if left <= 1:
			return "%s 자리는 %s만" % [GRADE_KO[md["grade"]], GRADE_KO[md["grade"]]]
	return ""


func hire_wec(i: int, slot: int, idx: int) -> bool:
	if wec_hire_block(i, slot, idx) != "":
		return false
	var fa: Dictionary = hq["wec_market"][i]
	var crew := my_crew(slot)
	var old: Dictionary = crew[idx]
	hq["cash"] = r2(float(hq["cash"]) - float(fa["cost"]))
	book("staff", float(fa["cost"]))
	hq["salaries"][fa["name"]] = fa["salary"]
	crew[idx] = {"name": fa["name"], "grade": fa["grade"], "speed": fa["speed"], "cons": fa["cons"], "tyreMgmt": fa["tyreMgmt"], "aggr": fa["aggr"], "def": fa["def"], "wet": fa["wet"], "age": fa["age"]}
	hq["wec_market"].remove_at(i)
	# 내보낸 드라이버는 FA 시장으로
	var g0: String = old.get("grade", "S")
	hq["wec_market"].append({"name": old["name"], "grade": g0, "speed": old["speed"], "cons": old.get("cons", 0.76), "tyreMgmt": old.get("tyreMgmt", 0.75), "aggr": old.get("aggr", 0.5), "def": old.get("def", 0.72), "wet": old.get("wet", 0.74),
		"cost": r2(WEC_FA_COST.get(g0, 0.4) * 0.8), "salary": WEC_FA_SAL.get(g0, 0.4), "age": int(old.get("age", 28))})
	news("%s 드라이버 %s 영입 (#%d 차 · %s 대신)." % [GRADE_KO[fa["grade"]], fa["name"], slot + 1, old["name"]])
	return true


## 두 차 사이에서 같은 순번 드라이버를 맞바꾼다
func wec_swap_cars(idx: int) -> bool:
	var a := my_crew(0)
	var b := my_crew(1)
	if idx >= a.size() or idx >= b.size():
		return false
	var t: Dictionary = a[idx]
	a[idx] = b[idx]
	b[idx] = t
	return true


## 선발 드라이버 지정 (크루 맨 앞으로)
func wec_set_starter(slot: int, idx: int) -> bool:
	var crew := my_crew(slot)
	if idx <= 0 or idx >= crew.size():
		return false
	var d: Dictionary = crew[idx]
	crew.remove_at(idx)
	crew.push_front(d)
	return true


func driver_salary(d: Dictionary) -> float:
	var nm: String = d["name"]
	if hq["salaries"].has(nm):
		return float(hq["salaries"][nm])
	var sp: float = d["speed"]
	return 2.6 if sp >= 0.92 else (1.4 if sp >= 0.88 else (0.8 if sp >= 0.84 else 0.4))


## 레이스가 끝난 sim 을 받아 포인트·경제·성장·시즌 전환을 처리한다. 화면용 요약을 돌려준다.
## 르망 초청 경기 시작 (초청장이 있을 때만)
func start_invite() -> bool:
	if not hq.get("lemans_invite", false):
		return false
	hq["special"] = "lemans"
	save()
	return true


func in_invite() -> bool:
	return hq.get("special", "") == "lemans"


## 르망 초청 경기 정산: 포인트·라운드는 그대로, 클래스 순위로 상금·평판만
func after_invite(sim) -> Dictionary:
	var best := 99
	var mcls := my_class()
	var cls_ord: Array = []
	for c in sim.order():
		if c.cls == mcls and c.dnf == "":
			cls_ord.append(c)
	for c in sim.my_cars():
		var p := cls_ord.find(c)
		if p >= 0:
			best = mini(best, p + 1)
	var cash := 1.5 if best == 1 else (0.8 if best <= 3 else (0.3 if best < 99 else 0.0))
	var pop := 0.12 if best == 1 else (0.06 if best <= 3 else (0.02 if best < 99 else -0.02))
	hq["cash"] = r2(float(hq["cash"]) + cash)
	hq["pop"] = clampf(r2(float(hq["pop"]) + pop), 0.15, 0.98)
	hq["lemans_invite"] = false
	hq.erase("special")
	var m := "🎟 르망 24시 초청 출전 결과: LMP2 클래스 %s · 상금 +%.1fM · 평판 %+d%%" % [("P%d" % best) if best < 99 else "완주 실패", cash, int(round(pop * 100))]
	news(m)
	save()
	return {"best": best, "cash": cash, "pop": pop, "text": m}


func after_race(sim) -> Dictionary:
	var notes: Array = []
	hq["next_mods"] = {}
	var ord: Array = sim.order()
	var classified: Array = []
	var mcls := my_class()
	for c in ord:
		if c.dnf == "" and c.cls == mcls:
			classified.append(c)
	var mine: Array = sim.my_cars()
	var total := 0
	var mult := 2 if (is_wec() and sim.circ_key == "lemans") else 1
	for i in classified.size():
		var c = classified[i]
		var pv: int = (POINTS[i] if i < POINTS.size() else 0) * mult + (1 if (not is_wec() and sim.fastest_id == c.id and i < 10) else 0)
		if pv > 0:
			hq["team_pts"][c.team] = int(hq["team_pts"].get(c.team, 0)) + pv
			if c.mine:
				total += pv
	_track_season(classified, mine, POINTS, mult, sim)
	var ec := _settle(mine, classified, total)
	hq["race_count"] = int(hq["race_count"]) + 1
	_pu_after_race(notes)
	_complete_projects(notes)
	var cl := cal_len()
	var ri := round_idx()
	var step := int(ceil(cl / 3.0))
	if ri != 0 and ri % step == 0:
		_ai_develop(1.0 / 3.0)
	if is_wec():
		# WEC BoP: 성적이 좋으면 다음 경기 핸디캡, 부진하면 완화
		var best := 99
		for c in mine:
			var p := classified.find(c)
			if c.dnf == "" and p >= 0:
				best = mini(best, p + 1)
		var adj := 0.0025 if best == 1 else (0.0012 if best <= 3 else (-0.0012 if best >= 6 else 0.0))
		hq["wec_bop"] = clampf(snappedf(float(hq.get("wec_bop", 0.0)) * 0.8 + adj, 0.0001), -0.006, 0.008)
		if not is_spec_tier():
			_ai_bop(sim, classified, notes)
	# 드라이버 성장(25세 이하) · 노화(33세 이상) — F1. 하위 리그는 육성 중심이라 성장이 빠르다 (F3 ×2, F2 ×1.5)
	var gm := 2.0 if race_format() == "f3" else (1.5 if race_format() == "f2" else 1.0)
	for slot in (0 if is_wec() else 2):
		var d := my_driver(slot)
		var age := int(d.get("age", 25))
		var dnf: bool = slot < mine.size() and mine[slot].dnf != ""
		if age <= 25 and not dnf:
			d["speed"] = minf(0.96, snappedf(float(d["speed"]) + 0.025 * gm / cl, 0.0001))
			d["cons"] = minf(0.95, snappedf(float(d["cons"]) + 0.02 * gm / cl, 0.0001))
		elif age >= 33:
			d["speed"] = maxf(0.72, snappedf(float(d["speed"]) - 0.003, 0.001))
	var rep := 0.08 if total >= 25 else (0.04 if total >= 10 else (0.02 if total > 0 else -0.02))
	hq["pop"] = clampf(r2(hq["pop"] + rep), 0.15, 0.98)
	if ri == 0:
		_season_end(notes)
		hq["last_season"]["notes"] = notes.duplicate()
		ec["season_end"] = true
	else:
		_maybe_event()
	ec["notes"] = notes
	ec["total"] = total
	save()
	return ec


# ═════════ 시즌 기록 (드라이버 챔피언십 · 내 팀 통계 · 트로피) ═════════
func _drv_key(c) -> String:
	if is_wec():
		return "%s #%d" % [c.team, c.slot + 1]
	return c.name


func _track_season(classified: Array, mine: Array, pts_table: Array, mult: int, sim) -> void:
	if not hq.has("drv_pts"):
		hq["drv_pts"] = {}
	if not hq.has("season_stats"):
		hq["season_stats"] = {"races": 0, "wins": 0, "podiums": 0, "dnf": 0, "best": 99}
	var dp: Dictionary = hq["drv_pts"]
	for i in classified.size():
		var c = classified[i]
		var pv: int = (int(pts_table[i]) if i < pts_table.size() else 0) * mult
		if sim != null and pts_table == POINTS and not is_wec() and sim.fastest_id == c.id and i < 10:
			pv += 1
		var k := _drv_key(c)
		if not dp.has(k):
			dp[k] = {"name": k, "team": c.team, "color": "#" + c.color.to_html(false), "pts": 0, "wins": 0, "mine": c.mine}
		dp[k]["pts"] = int(dp[k]["pts"]) + pv
		dp[k]["team"] = c.team
		if i == 0 and pts_table == POINTS:
			dp[k]["wins"] = int(dp[k]["wins"]) + 1
	if pts_table != POINTS:
		return
	var st: Dictionary = hq["season_stats"]
	st["races"] = int(st["races"]) + 1
	for c in mine:
		var p := classified.find(c)
		if c.dnf != "" or p < 0:
			st["dnf"] = int(st["dnf"]) + 1
			continue
		if p == 0:
			st["wins"] = int(st["wins"]) + 1
		if p <= 2:
			st["podiums"] = int(st["podiums"]) + 1
		st["best"] = mini(int(st["best"]), p + 1)


func driver_standings() -> Array:
	var rows: Array = []
	for k in hq.get("drv_pts", {}):
		rows.append(hq["drv_pts"][k])
	rows.sort_custom(func(a, b): return int(a["pts"]) > int(b["pts"]) if int(a["pts"]) != int(b["pts"]) else int(a["wins"]) > int(b["wins"]))
	return rows


## 시즌 종료 요약을 hq["last_season"] 에 남기고, 3위 안이면 트로피를 쌓는다
func _season_summary(rank: int, prize: float) -> void:
	var cons: Array = standings()
	var drv: Array = driver_standings()
	var my_drv := 0
	for i in drv.size():
		if drv[i]["mine"]:
			my_drv = i + 1
			break
	var st: Dictionary = hq.get("season_stats", {"races": 0, "wins": 0, "podiums": 0, "dnf": 0, "best": 99})
	var my_pts := 0
	for r in cons:
		if r["mine"]:
			my_pts = int(r["pts"])
	var tname: String = tier_meta()["short"]
	hq["last_season"] = {"season": int(hq["season"]), "tier": tier(), "tier_name": tname, "series": ser(), "rank": rank, "pts": my_pts, "prize": prize,
		"cons": cons.slice(0, 12), "drivers": drv.slice(0, 12), "my_drv": my_drv, "stats": st.duplicate(),
		"champ": cons[0]["name"] if not cons.is_empty() else "-", "drv_champ": drv[0]["name"] if not drv.is_empty() else "-", "notes": []}
	if not hq.has("trophies"):
		hq["trophies"] = []
	if rank <= 3:
		hq["trophies"].append({"season": int(hq["season"]), "tier_name": tname, "rank": rank})
	if my_drv == 1:
		hq["trophies"].append({"season": int(hq["season"]), "tier_name": tname, "rank": 1, "driver": drv[0]["name"]})


## F2 스프린트: 포인트(8위까지 10-8-6-5-4-3-2-1)와 평판만 반영. 돈 정산은 피처 레이스 뒤에 한 번.
func after_sprint(sim) -> Dictionary:
	var classified: Array = []
	for c in sim.order():
		if c.dnf == "":
			classified.append(c)
	var total := 0
	for i in mini(classified.size(), SPRINT_POINTS.size()):
		var c = classified[i]
		var pv: int = SPRINT_POINTS[i]
		hq["team_pts"][c.team] = int(hq["team_pts"].get(c.team, 0)) + pv
		if c.mine:
			total += pv
	_track_season(classified, sim.my_cars(), SPRINT_POINTS, 1, sim)
	if total > 0:
		hq["pop"] = clampf(r2(hq["pop"] + (0.02 if total >= 10 else 0.01)), 0.15, 0.98)
	save()
	return {"total": total}


func _settle(mine: Array, classified: Array, total: int) -> Dictionary:
	var cl := cal_len()
	var ts := tier_scale()
	var podium := false
	for c in mine:
		var p := classified.find(c)
		if c.dnf == "" and p >= 0 and p < 3:
			podium = true
	var spon := _sponsor_race_income(podium, total)
	var pay := 0.0
	for k in hq["pay_drivers"]:
		pay += float(hq["pay_drivers"][k]) / cl
	var prize := total * 0.008 * float(tier_meta()["prizeM"]) * ts
	var mk: String = hq["mission"]
	var m_ok := false
	var mission := 0.0
	var m_pen := 0.0
	if mk != "none":
		m_ok = _mission_ok(mk, mine, classified)
		if m_ok:
			mission = mission_reward(mk)
			for c in hq["contracts"]:
				c["sat"] = minf(1.0, float(c["sat"]) + 0.04)
		else:
			m_pen = MISSION_PEN.get(mk, 0.02)
			hq["pop"] = maxf(0.15, r2(hq["pop"] - m_pen))
			for c in hq["contracts"]:
				c["sat"] = maxf(0.0, float(c["sat"]) - 0.06)
	var salary := 0.0
	for slot in 2:
		salary += driver_salary(salary_driver(slot)) * (0.15 if is_spec_tier() else 1.0) / cl
	var ops: float = float(D["econ"]["ops"][ser()]) * ts
	var overhead: float = float(D["econ"]["overhead"][ser()]) * ts
	var fac_red := 1.0 - 0.1 * (int(hq["base"]["factory"]) - 1)
	var repair := 0.0
	for c in mine:
		if c.dnf == "":
			continue
		var rr: Array = D["econ"]["repair"]["crash"] if c.dnf.contains("충돌") else D["econ"]["repair"]["mech"]
		repair += uni(float(rr[0]), float(rr[1])) * ts * fac_red
	var net := spon + pay + prize + mission - ops - overhead - salary - repair
	hq["cash"] = r2(hq["cash"] + net)
	hq["spent_cap"] = r2(hq["spent_cap"] + ops + repair)
	book("spon", spon)
	book("pay", pay)
	book("prize", prize)
	book("mission", mission)
	book("ops", ops)
	book("overhead", overhead)
	book("salary", salary)
	book("repair", repair)
	return {"spon": spon, "pay": pay, "prize": prize, "mission": mission, "mission_key": mk, "mission_ok": m_ok, "mission_pen": m_pen, "ops": ops, "overhead": overhead, "salary": salary, "repair": repair, "net": net, "cash": hq["cash"]}


func _season_end(notes: Array) -> void:
	var rank := my_rank_now()
	var pz := prize_for(rank)
	_season_summary(rank, pz)
	hq["cash"] = r2(hq["cash"] + pz)
	book("prize", pz)
	var msg := "💰 시즌 %d 컨스트럭터 챔피언십 P%d 상금 +%.2fM" % [int(hq["season"]), rank, pz]
	news(msg)
	notes.append(msg)
	_ai_develop(1.0 / 3.0)
	_cost_cap_audit(notes)
	var ls: Dictionary = hq["last_season"]
	hq["season_log"].append({"season": hq["season"], "rank": rank, "cash": hq["cash"], "spent": hq["spent_cap"], "cap": hq["cost_cap_limit"], "tier": tier(),
		"pts": ls["pts"], "champ": ls["champ"], "drv_champ": ls["drv_champ"], "wins": int(ls["stats"].get("wins", 0)), "podiums": int(ls["stats"].get("podiums", 0)),
		"tier_name": ls.get("tier_name", ""), "series": ls.get("series", ""), "my_drv": int(ls.get("my_drv", 0)), "team": hq.get("team_name", "")})
	if hq["season_log"].size() > 12:
		hq["season_log"].pop_front()
	if not is_spec_tier():
		hq["last_rank"] = rank
	_sponsor_season_end(rank, notes)
	hq["pay_drivers"] = {}
	for t in hq["teams"]:
		for d in t.get("drivers", []):
			d["age"] = int(d.get("age", 25)) + 1
	# 아시안 르망(LMP3) 챔피언: 르망 24시 초청장 (다음 시즌 동안 본부에서 한 번 출전, 포인트 없음)
	if is_wec() and int(hq["tier"]) == 0 and rank == 1:
		hq["lemans_invite"] = true
		var mi := "🎟 아시안 르망 LMP3 챔피언! 르망 24시 초청장 획득 — 본부에서 LMP2 초청 엔트리로 한 경기 출전할 수 있어요"
		news(mi)
		notes.append(mi)
	_season_lifecycle(rank, notes)
	hq["season"] = int(hq["season"]) + 1
	_season_start(notes)
	evaluate_engine_politics()
	_refresh_offers()
	_refresh_pay_pool()


## 하이퍼카 BoP: 내 팀처럼 AI 제조사도 성적대로 매 경기 조정 (연승하면 무게·출력 제한, 부진하면 완화)
func _ai_bop(sim, classified: Array, notes: Array) -> void:
	var bm: Dictionary = hq.get("bop_ai", {})
	var best := {}
	for i in classified.size():
		var c = classified[i]
		if c.mine or c.cls != "HY" or c.dnf != "":
			continue
		var tn: String = c.team
		if not best.has(tn):
			best[tn] = i + 1
	var moved: Array = []
	for t in hq["teams"]:
		var tn: String = t["name"]
		if tn == hq["team_name"]:
			continue
		var b: int = int(best.get(tn, 99))
		var adj := 0.0025 if b == 1 else (0.0012 if b <= 3 else (-0.0012 if b >= 6 else 0.0))
		var nv: float = clampf(snappedf(float(bm.get(tn, 0.0)) * 0.8 + adj, 0.0001), -0.006, 0.008)
		if absf(nv - float(bm.get(tn, 0.0))) >= 0.002:
			moved.append("%s %s" % [tn, "▲핸디캡" if nv > float(bm.get(tn, 0.0)) else "▼완화"])
		bm[tn] = nv
	hq["bop_ai"] = bm
	if not moved.is_empty():
		var m := "⚖ BoP 조정: " + " · ".join(moved.slice(0, 4))
		news(m)
		notes.append(m)


func _season_start(notes: Array) -> void:
	hq["season_base"] = int(hq["race_count"])
	hq["pu"] = [_pu_fresh(), _pu_fresh()]
	hq["team_pts"] = {}
	hq["drv_pts"] = {}
	hq["season_stats"] = {"races": 0, "wins": 0, "podiums": 0, "dnf": 0, "best": 99}
	hq["last_ledger"] = hq["ledger"]
	hq["ledger"] = _new_ledger()
	var carry := 0.0
	var keep: Array = []
	for d in hq["depr"]:
		if int(d["left"]) > 0:
			carry += float(d["per"])
			d["left"] = int(d["left"]) - 1
		if int(d["left"]) > 0:
			keep.append(d)
	hq["depr"] = keep
	hq["spent_cap"] = r2(carry)
	book("fac", carry)
	hq["cost_cap_limit"] = cap_limit_now()
	_pay_owner(notes)
	if is_wec():
		_refresh_wec_market()
	if not is_spec_tier():
		if int(hq["season"]) > 1 and reg_year() == 1:
			_regulation_reset(notes)
		elif reg_year() == int(D["econ"]["regCycle"]):
			var msg := "📣 FIA 공지: 다음 시즌 신규 기술 규정 발효 예정. R&D에서 차세대 차량 선행 개발을 시작할 수 있어요."
			news(msg)
			notes.append(msg)


func _rookie_name() -> String:
	var sn: Array = D["surnames"]
	return "%s. %s" % [char(65 + rng.randi_range(0, 25)), sn[rng.randi_range(0, sn.size() - 1)]]


func _season_lifecycle(rank: int, notes: Array) -> void:
	var tm := tier_meta()
	var my_pts := 0
	for r in standings():
		if r["mine"]:
			my_pts = r["pts"]
	# 1) 승강 (신규 창단 팀)
	if is_spec_tier():
		if rank <= int(tm["reqRank"]) or my_pts >= int(tm["reqPts"]):
			hq["promo_qualified"] = true
			var nt := tier_meta(tier() + 1)
			if rank == 1:
				hq["tier"] = tier() + 1
				hq["promo_qualified"] = false
				hq["cash"] = r2(hq["cash"] + 2.5)
				_on_tier_change()
				var m := "🏆 디비전 챔피언(P1 · %d점)! 포상금 +2.5M, [%s] 자동 승격!" % [my_pts, nt["name"]]
				news(m)
				notes.append(m)
			else:
				hq["cash"] = r2(hq["cash"] + 1.2)
				var m2 := "🎖 시즌 P%d(%d점)! [%s] 승격 자격 획득 (본부에서 승격 신청 가능)" % [rank, my_pts, nt["short"]]
				news(m2)
				notes.append(m2)
	elif tier() == 3 and rank == standings().size() and my_pts < 4:
		hq["pop"] = maxf(0.18, r2(hq["pop"] - 0.06))
		var m3 := "⚠ 최하위(P%d) 부진으로 보드진 경고, 평판 -6%%" % rank
		news(m3)
		notes.append(m3)
	# 2) 고참 노화·은퇴 → 유망주·루키 세대교체 (F1)
	var teams: Array = hq["teams"] if not is_wec() else []
	for ti in teams.size():
		for k in 2:
			var d: Dictionary = teams[ti]["drivers"][k]
			var age := int(d.get("age", 25))
			if age >= 34:
				d["speed"] = maxf(0.70, snappedf(float(d["speed"]) - 0.008, 0.001))
			var rp := 0.80 if age >= 37 else (0.42 if age == 36 else (0.18 if age == 35 else 0.0))
			if rp <= 0.0 or rnd() >= rp:
				continue
			var old: String = d["name"]
			if ti == my_team():
				if hq["juniors"].size() > 0:
					hq["juniors"].sort_custom(func(a, b): return a["cur"] > b["cur"])
					var j: Dictionary = hq["juniors"].pop_front()
					var nd := _junior_driver(j)
					teams[ti]["drivers"][k] = nd
					var m4 := "🔄 [세대교체] %s(%d세) 은퇴! 유망주 %s(%d세) #%d 콜업" % [old, age, nd["name"], nd["age"], k + 1]
					news(m4)
					notes.append(m4)
				else:
					var rk := _rookie_name()
					teams[ti]["drivers"][k] = {"name": rk, "speed": snappedf(uni(0.79, 0.85), 0.01), "cons": snappedf(uni(0.78, 0.84), 0.01), "tyreMgmt": 0.80, "aggr": 0.62, "def": 0.76, "wet": 0.80, "age": 20}
					var m5 := "🔄 [세대교체] %s(%d세) 은퇴 → 루키 %s #%d 합류" % [old, age, rk, k + 1]
					news(m5)
					notes.append(m5)
			else:
				var rk2 := _rookie_name()
				var nage := rng.randi_range(19, 21)
				teams[ti]["drivers"][k] = {"name": rk2, "speed": snappedf(uni(0.80, 0.89), 0.01), "cons": snappedf(uni(0.79, 0.87), 0.01), "tyreMgmt": 0.81, "aggr": 0.65, "def": 0.78, "wet": 0.82, "age": nage}
				news("📰 %s(%d세) 은퇴, 루키 %s(%d세) 데뷔" % [old, age, rk2, nage])
	for j in hq["juniors"]:
		j["age"] = int(j["age"]) + 1
		j["cur"] = minf(float(j["pot"]), snappedf(float(j["cur"]) + 0.01 + (int(hq["base"]["sim"]) - 1) * 0.005, 0.01))
		j["value"] = junior_value(j)


func can_tier_up() -> bool:
	if not is_spec_tier() or not is_preseason():
		return false
	var q: bool = hq["promo_qualified"] or float(hq["pop"]) >= 0.65
	return q and float(hq["cash"]) >= float(tier_meta()["fee"])


func tier_up() -> bool:
	if not can_tier_up():
		return false
	var fee: float = tier_meta()["fee"]
	hq["cash"] = r2(hq["cash"] - fee)
	hq["tier"] = tier() + 1
	hq["promo_qualified"] = false
	_on_tier_change()
	news("🏆 [%s] 라이선스 취득, 상위 리그 승격! (캡 %.0fM)" % [tier_meta()["name"], float(tier_meta()["cap"])])
	return true


# ═════════ 저장 ═════════
## 저장 슬롯 3개. 1번은 예전 저장 파일 이름을 그대로 써서 기존 저장을 이어 쓴다.
const SLOTS := 3
var save_slot := 1


static func path_for(s: int) -> String:
	return SAVE_PATH if s <= 1 else "user://career_slot%d.json" % s


func save() -> void:
	var f = FileAccess.open(path_for(save_slot), FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(hq))


static func has_save(s: int = 1) -> bool:
	return FileAccess.file_exists(path_for(s))


func load_save(s: int = -1) -> bool:
	if s > 0:
		save_slot = s
	if not has_save(save_slot):
		return false
	var f = FileAccess.open(path_for(save_slot), FileAccess.READ)
	if f == null:
		return false
	var data = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY or int(data.get("ver", 0)) != SAVE_VER:
		return false
	hq = data
	rng.randomize()
	return true


static func delete_save(s: int = 1) -> void:
	if FileAccess.file_exists(path_for(s)):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path_for(s)))
