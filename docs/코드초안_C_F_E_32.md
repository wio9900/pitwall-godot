# 코드 초안 모음 (C · F · E · #32 · WEC 페널티)

> 기준 브랜치: `feat/career-depth` (`c10a1d0`, 2026-11-21)  
> 실제 소스(`car.gd` · `race_sim.gd` · `track.gd` · `race_view.gd` · `career.gd`)의 실제 변수명·함수명과 대조해 수정한 초안입니다.  
> **아직 게임 소스에는 적용되지 않았습니다.** 실제 반영 시 `docs/작업목록.md`의 순서와 `tests/*_smoke.gd` 테스트를 함께 확인해 주세요.

---

## 1. 묶음 C · 커리어 경영 (`scripts/sim/career.gd`)

### C-1. 경제 밸런스 (점진적 오너 목표 + 조건부 투자)
- 함께 볼 것: `data/hq_default.json`의 `econ.owner` 배열 축소 + 다시즌 자금 곡선 검증

```gdscript
## 오너 목표 순위: 1년 차 무조건 통과, 2년 차 하위권 탈출(85%), 이후 중위권(65%) 또는 전 시즌보다 순위 상승
func _owner_target_met() -> bool:
	var n := int(hq["owner_season"])
	if n == 0:
		return true
	var rank: int = int(hq.get("last_rank", 99))
	var prev: int = int(hq.get("prev_rank", 99))
	var cut: float = 0.85 if n == 1 else 0.65
	var tgt: int = maxi(1, int(ceil(hq["teams"].size() * cut)))
	return rank <= tgt or rank < prev


func owner_funding() -> float:
	if hq["entry"] != "create":
		return 0.0
	var arr: Array = D["econ"]["owner"]
	var n := int(hq["owner_season"])
	if n >= arr.size():
		return 0.0
	var base: float = float(arr[n]) * tier_scale()
	return r2(base if _owner_target_met() else base * 0.6)


func _pay_owner(notes: Array) -> void:
	var met := _owner_target_met()
	var f := owner_funding()
	hq["prev_rank"] = int(hq.get("last_rank", 99))
	hq["owner_season"] = int(hq["owner_season"]) + 1
	if f <= 0.0:
		return
	hq["cash"] = r2(float(hq["cash"]) + f)
	book("owner", f)
	if not met:
		pop_add(-0.02, "오너 목표 미달", 0.15, true)
	var tag := "목표 달성 전액" if met else "목표 미달 60%% 감액"
	var msg := "🏦 오너 그룹 시즌 %d 투자 +%.2fM (%s)" % [int(hq["season"]), f, tag]
	news(msg)
	notes.append(msg)
```

### C-2. 스폰서 개편 + 타이틀 스폰서 (팀 ID 분리 전제)
- 전제 작업: `hq["team_pts"]`·`standings()`·`records.gd`에서 팀 이름 대신 고정 `team_id`를 키로 사용, `hq["team_name"]`은 원래 이름 유지.

```gdscript
## 옛 저장 파일 → 팀 고정 ID 마이그레이션 (load_save·new_career 에서 1회 호출)
func _migrate_team_ids() -> void:
	for i in hq["teams"].size():
		var t: Dictionary = hq["teams"][i]
		if not t.has("id"):
			t["id"] = "player" if i == my_team() else ("t_%d_%s" % [i, String(t["name"]).to_lower().replace(" ", "_")])
	if not hq.has("team_id"):
		hq["team_id"] = String(hq["teams"][my_team()]["id"])
	if not hq.has("title_brand"):
		hq["title_brand"] = ""


## 화면 표시용 팀 이름 (저장·포인트 집계·team_region 조회는 항상 원래 id/name 유지)
func team_display_name(tid: String, short_mode: bool = false) -> String:
	for t in hq["teams"]:
		if String(t.get("id", "")) != tid:
			continue
		var base: String = String(t["name"])
		var brand: String = String(hq["title_brand"]) if tid == String(hq["team_id"]) else String(t.get("title_brand", ""))
		if brand == "":
			return base
		return ("%s %s" % [brand.split(" ")[0], base]) if short_mode else ("%s %s" % [brand, base])
	return tid


func has_sponsor_sector(sector: String) -> bool:
	if sector == "":
		return false
	for c in hq.get("contracts", []):
		if String(c.get("sector", "")) == sector:
			return true
	return false


func sign_offer_v2(i: int) -> bool:
	var o: Dictionary = hq["offers"][i]
	if contract_of(o["cat"]) != null or has_sponsor_sector(String(o.get("sector", ""))):
		return false
	var c := o.duplicate(true)
	c["seasons_left"] = int(c["seasons"])
	hq["contracts"].append(c)
	if String(c["cat"]) == "title":
		hq["title_brand"] = String(c["name"])
		news("🏷 %s, 새 타이틀 스폰서 — 팀명 '%s'" % [c["name"], team_display_name(String(hq["team_id"]))])
	var rest: Array = []
	for x in hq["offers"]:
		if x["cat"] != o["cat"] and String(x.get("sector", "")) != String(c.get("sector", "")):
			rest.append(x)
	hq["offers"] = rest
	return true


## 시즌 말 스폰서 만료 처리(_sponsor_season_end 내부)
func _clear_expired_title() -> void:
	if contract_of("title") == null and String(hq.get("title_brand", "")) != "":
		hq["title_brand"] = ""
		news("🏷 타이틀 스폰서 만료 — 원래 팀명 '%s'(으)로 복귀" % hq["team_name"])
```

### C-3. 인력·스카우트 개편 + 팀 궁합 + AI 경쟁
- 실제 키 반영: `DB.names["region_nat"]`, `D["branch_fx"]`, `hq["rnd_branch"]`, `SD().get("team_region", {})`
- 기존 `staff_refresh_pool()`의 `deptKo`·`role`·`aeroMod`/`engMod`/`tyreMod`/`relMod`/`eqMod`/`crewMod`·`cost`·`rival` 필드 구조를 유지하면서 `nat`·`age`·`style`·`contract`를 추가합니다.
- UI(`hq_view.gd`)는 모바일 성능을 위해 등급 탭(S~D)별로 4~6명만 생성·표시 권장.

```gdscript
const STAFF_DIST := {
	0: [["S", 0.0], ["A", 0.05], ["B", 0.25], ["C", 0.40], ["D", 0.30]], # 하위(4부)
	1: [["S", 0.0], ["A", 0.10], ["B", 0.30], ["C", 0.40], ["D", 0.20]], # 3부
	2: [["S", 0.05], ["A", 0.20], ["B", 0.35], ["C", 0.30], ["D", 0.10]], # 2부
	3: [["S", 0.15], ["A", 0.30], ["B", 0.35], ["C", 0.15], ["D", 0.05]], # 1부
}
const SYNERGY_CAP := 0.02 # 지역·철학·엔지니어 성능 보너스 합계 상한 (+2%)


func _pick_tier_by_dist(rows: Array) -> String:
	var r := rnd()
	var acc := 0.0
	for row in rows:
		acc += float(row[1])
		if r <= acc:
			return String(row[0])
	return "C"


func is_same_region(reg: String, nat: String) -> bool:
	var nats: Array = DB.names.get("region_nat", {}).get(reg, [])
	return nats.has(nat)


## staff_refresh_pool() 확장: 기존 스탯 생성 블록은 유지하고 이름·국적·성향·계약 필드 추가
func _fill_staff_meta(e: Dictionary, taken: Dictionary) -> void:
	var gp: Array = gen_person(taken)
	var branches: Array = D["branch_fx"].keys()
	e["name"] = String(gp[0])
	e["nat"] = String(gp[1])
	e["age"] = rng.randi_range(26, 58)
	e["style"] = String(branches[rng.randi_range(0, branches.size() - 1)])
	e["contract"] = rng.randi_range(1, 3)


## 팀 궁합: 같은 지역 계약금 -20% / 먼 지역 이주비 +15%, 철학 일치 시 개발 속도 +5% (성능 보너스는 SYNERGY_CAP 제한)
func staff_synergy(e: Dictionary, team_reg: String = "", team_branch: String = "") -> Dictionary:
	var reg := team_reg if team_reg != "" else String(hq["region"])
	var br := team_branch if team_branch != "" else String(hq["rnd_branch"])
	var same_reg := is_same_region(reg, String(e.get("nat", "")))
	var cost_m: float = 0.80 if same_reg else 1.15
	if String(e.get("trait", "")) == "cheap":
		cost_m *= 0.80
	var same_style: bool = String(e.get("style", "")) == br
	var dev_speed: float = 0.05 if same_style else 0.0
	return {"cost_mult": cost_m, "dev_speed": dev_speed, "perf_cap": SYNERGY_CAP, "same_reg": same_reg, "same_style": same_style}


## AI 스카우트도 자기 본부 지역(SD()["team_region"])에 맞는 후보 우선 영입 (원칙 9)
func _ai_staff_scout_v2(notes: Array) -> void:
	var tr_map: Dictionary = SD().get("team_region", {})
	for ti in hq["teams"].size():
		if ti == my_team() or rnd() > 0.25:
			continue
		var t: Dictionary = hq["teams"][ti]
		var treg: String = String(tr_map.get(t["name"], "uk"))
		var best_e: Variant = null
		var best_s := -1.0
		for e in hq.get("eng_pool", []):
			if e["hired"] or e.get("gone", false):
				continue
			var sc: float = (1.0 if String(e["tier"]).begins_with("S") else 0.6) + (0.35 if is_same_region(treg, String(e.get("nat", ""))) else 0.0)
			if sc > best_s:
				best_s = sc
				best_e = e
		if best_e != null:
			best_e["gone"] = true
			notes.append("📋 %s, %s(%s) 영입" % [t["name"], best_e["name"], best_e["tier"]])
```

### C-4. 이적시장 깊이 (내 팀 보호 · 종합 평가 · F1/WEC 분기)
- 실제 키 반영: F1 시장(`hq["market"]`)은 `"tyre"`, 팀 로스터 드라이버는 `"tyreMgmt"` / WEC `hq["field"]`의 팀 인덱스 키는 `"ti"`.

```gdscript
func _drv_rating(d: Dictionary) -> float:
	var age_pen: float = maxf(0.0, float(int(d.get("age", 26)) - 34) * 0.015)
	var tm: float = float(d.get("tyreMgmt", d.get("tyre", 0.7)))
	return float(d.get("speed", 0.5)) * 0.55 + float(d.get("cons", 0.7)) * 0.25 + tm * 0.20 - age_pen


## 시즌 종료 시 AI 드라이버 계약 만료 및 이적 (내 팀은 절대 건드리지 않음)
func _ai_driver_transfers(notes: Array) -> void:
	if is_wec():
		_ai_wec_transfers(notes)
		return
	var fa: Array = hq.get("market", []).duplicate()
	var openings: Array = []
	for ti in hq["teams"].size():
		if ti == my_team():
			continue
		var dlist: Array = hq["teams"][ti].get("drivers", [])
		for si in dlist.size():
			var d: Dictionary = dlist[si]
			d["contract"] = int(d.get("contract", 1)) - 1
			if int(d["contract"]) <= 0:
				openings.append({"ti": ti, "slot": si, "old": d})
				fa.append(d)
	fa.sort_custom(func(a, b): return _drv_rating(a) > _drv_rating(b))
	for op in openings:
		if fa.is_empty():
			break
		var t: Dictionary = hq["teams"][int(op["ti"])]
		var top: bool = float(t.get("aero", 0.8)) + float(t.get("chassis", 0.8)) >= 1.72
		var idx: int = 0 if top else mini(fa.size() - 1, rng.randi_range(0, mini(4, fa.size() - 1)))
		var pick: Dictionary = fa.pop_at(idx)
		pick["contract"] = rng.randi_range(1, 3)
		t["drivers"][int(op["slot"])] = pick
		if String(pick["name"]) != String(op["old"]["name"]):
			var msg := "🔄 이적: %s, %s 합류 (%d년)" % [pick["name"], t["name"], int(pick["contract"])]
			news(msg)
			notes.append(msg)
	hq["market"] = fa


## WEC AI 이적: hq["field"] 의 팀 키는 "ti". 등급 의무가 깨지지 않게 같은 등급(P/G/S/B) FA 끼리만 교체
func _ai_wec_transfers(notes: Array) -> void:
	var fa: Array = wec_market()
	for entry in hq.get("field", []):
		if int(entry.get("ti", -1)) == my_team():
			continue
		var crew: Array = entry.get("crew", [])
		for ci in crew.size():
			var d: Dictionary = crew[ci]
			d["contract"] = int(d.get("contract", 2)) - 1
			if int(d["contract"]) > 0 or rnd() > 0.4:
				continue
			var g: String = String(d.get("grade", "G"))
			for fi in fa.size():
				if String(fa[fi].get("grade", "")) == g:
					var pick: Dictionary = fa.pop_at(fi)
					pick["contract"] = rng.randi_range(1, 3)
					crew[ci] = pick
					fa.append(d)
					notes.append("🔄 WEC 이적: %s (%s급) 크루 합류" % [pick["name"], g])
					break
```

---

## 2. 묶음 F · 차종 선택 (쇼룸 제외)

### 2-1. 데이터 (`data/wec.json` `"carModels"` 섹션)

```json
"carModels": {
  "GT": {
    "porsche_911": { "name": "911 GT3 R", "aero": 0.008, "wear": 0.96, "fuel": 0.99, "rel": 0.015, "brake": 0.92, "buy": 1.4, "maint": 0.16 },
    "ferrari_296": { "name": "296 GT3", "aero": 0.005, "wear": 0.98, "fuel": 0.98, "rel": 0.005, "brake": 0.96, "buy": 1.5, "maint": 0.18 },
    "bmw_m4":      { "name": "M4 GT3", "aero": -0.006, "wear": 0.95, "fuel": 0.97, "rel": 0.010, "brake": 0.98, "buy": 1.3, "maint": 0.15 },
    "corvette_z06":{ "name": "Corvette Z06 GT3.R", "aero": -0.008, "wear": 1.02, "fuel": 1.03, "rel": 0.005, "brake": 1.00, "buy": 1.2, "maint": 0.13 },
    "aston_vantage":{ "name": "Vantage GT3", "aero": -0.003, "wear": 1.00, "fuel": 1.00, "rel": 0.000, "brake": 0.98, "buy": 1.15, "maint": 0.13 },
    "mclaren_720s":{ "name": "720S GT3 Evo", "aero": 0.010, "wear": 1.04, "fuel": 1.01, "rel": -0.015, "brake": 0.95, "buy": 1.35, "maint": 0.17 },
    "ford_mustang":{ "name": "Mustang GT3", "aero": -0.010, "wear": 1.01, "fuel": 1.04, "rel": 0.000, "brake": 1.04, "buy": 1.05, "maint": 0.12 },
    "lexus_rcf":   { "name": "RC F GT3", "aero": -0.004, "wear": 0.99, "fuel": 1.01, "rel": 0.020, "brake": 0.97, "buy": 0.95, "maint": 0.11 },
    "merc_amg":    { "name": "AMG GT3 Evo", "aero": 0.002, "wear": 0.97, "fuel": 1.02, "rel": 0.015, "brake": 0.94, "buy": 1.25, "maint": 0.14 }
  },
  "P3": {
    "ligier_p320":   { "name": "Ligier JS P320", "aero": 0.006, "wear": 0.97, "fuel": 1.00, "rel": 0.010, "brake": 0.96, "buy": 0.65, "maint": 0.08 },
    "duqueine_d08":  { "name": "Duqueine D08", "aero": -0.006, "wear": 1.02, "fuel": 0.98, "rel": -0.005, "brake": 1.03, "buy": 0.55, "maint": 0.07 }
  }
}
```

### 2-2. 커리어 관리 · 비용 · 차종 BoP (`scripts/sim/career.gd`)
- `race_opts()` 반환 딕셔너리(1037행)에 `"model_bop": hq.get("model_bop", {})` 추가, 내 팀 `my_t["model"] = my_car_model().get("id", "")` 연결.

```gdscript
func model_cls() -> String:
	if not is_wec():
		return ""
	return "P3" if tier() == 0 else ("GT" if tier() == 1 else "")


func available_models() -> Dictionary:
	var mc := model_cls()
	if mc == "":
		return {}
	return DB.wec.get("carModels", {}).get(mc, {})


func my_car_model() -> Dictionary:
	var mods := available_models()
	if mods.is_empty():
		return {}
	var mid: String = String(hq.get("car_model", ""))
	if not mods.has(mid):
		mid = String(mods.keys()[0])
	var out: Dictionary = mods[mid].duplicate()
	out["id"] = mid
	return out


func set_car_model(mid: String) -> bool:
	var mods := available_models()
	if not is_preseason() or not mods.has(mid) or mid == String(hq.get("car_model", "")):
		return false
	var m: Dictionary = mods[mid]
	var cost: float = r2(float(m["buy"]) * tier_scale())
	if float(hq["cash"]) < cost:
		return false
	hq["cash"] = r2(float(hq["cash"]) - cost)
	hq["car_model"] = mid
	book("ops", cost)
	news("🚗 새 차종 도입: %s (구입비 %.2fM · 경기당 정비 %.2fM)" % [m["name"], cost, float(m["maint"])])
	save()
	return true


func model_maint_cost() -> float:
	var m := my_car_model()
	return r2(float(m.get("maint", 0.0))) if not m.is_empty() else 0.0


func _update_model_bop(classified: Array) -> void:
	var mc := model_cls()
	if mc == "":
		return
	var bop: Dictionary = hq.get("model_bop", {})
	var sums := {}
	var cnts := {}
	var cls_rank := 0
	for c in classified:
		if c.cls != mc or c.dnf != "":
			continue
		cls_rank += 1
		var mid: String = String(c.car_model)
		if mid == "":
			continue
		sums[mid] = float(sums.get(mid, 0.0)) + float(cls_rank)
		cnts[mid] = int(cnts.get(mid, 0)) + 1
	var mid_rank: float = maxf(1.0, float(cls_rank) * 0.5)
	for mid in sums:
		var avg_r: float = float(sums[mid]) / float(cnts[mid])
		var adj: float = clampf((mid_rank - avg_r) * 0.0008, -0.0025, 0.0025)
		bop[mid] = clampf(snappedf(float(bop.get(mid, 0.0)) * 0.75 + adj, 0.0001), -0.008, 0.008)
	hq["model_bop"] = bop
```

### 2-3. 시뮬레이션 반영 (`scripts/sim/car.gd` · `scripts/sim/race_sim.gd`)

```gdscript
## car.gd 에 추가:
##   var car_model := ""
##   var model_spec: Dictionary = {}
##
## race_sim.gd 멤버 변수 추가:
##   var model_bop: Dictionary = {}
##
## race_sim.gd setup(opts) 안:
##   model_bop = opts.get("model_bop", {})
##
## race_sim.gd _build_wec_entries 안 (4515행 부근):
##   c.car_model = String(t.get("model", ""))
##   c.model_spec = DB.wec.get("carModels", {}).get(c.cls, {}).get(c.car_model, {})
##   c.rel = clampf(c.rel + float(c.model_spec.get("rel", 0.0)), 0.5, 0.99)

## 서킷 상성 + 차종 BoP (car_factor 의 `c.bop` 에 더해 사용)
func _model_pace_delta(c) -> float:
	if c.model_spec.is_empty():
		return 0.0
	var wing_bias: float = (float(CIRC.get("wingOpt", 3.0)) - 3.0) / 2.0
	var aero: float = float(c.model_spec.get("aero", 0.0))
	var bop_m: float = float(model_bop.get(c.car_model, 0.0))
	return -wing_bias * aero + bop_m

## 적용 위치:
##   car_factor(c) 567행: return dm * float(CLASS_PACE.get(c.cls, 1.0)) * (1.0 - c.perf * BOP_K + c.bop + _model_pace_delta(c))
##   sector_time 1402행: wear_rate *= float(c.model_spec.get("wear", 1.0))
##   wec_fuel_mult 2207행: 반환값 *= float(c.model_spec.get("fuel", 1.0))
##   sector_time 1387행 (gain > 0 일 때): gain *= float(c.model_spec.get("brake", 1.0))
```

---

## 3. 묶음 E · 피트레인 연출 (모든 서킷 · 모든 클래스)

### 3-1. 서킷별 피트레인 모양·방향 + 사선 정차 좌표 (`scripts/sim/track.gd`)
- **주의**: `pit_lane_point(u)`의 인자 `u`는 **`0.0 ~ pit_pts.size() - 1` (실수 샘플 인덱스)**입니다. 아래 함수들은 이 단위에 맞춰 작성했습니다.

```gdscript
var pit_side := 1.0 # 1.0 = 트랙 안쪽, -1.0 = 트랙 바깥쪽 (circuits*.json 의 pitSide 로 지정, 기본 inward)


func _build_custom_pit(raw: Array) -> void:
	pit_pts.clear()
	var n: int = raw.size()
	if n < 2:
		return
	var ctrl: Array = []
	for p in raw:
		ctrl.append(Vector2(float(p[0]), float(p[1])))
	for i in n - 1:
		var p0: Vector2 = ctrl[maxi(0, i - 1)]
		var p1: Vector2 = ctrl[i]
		var p2: Vector2 = ctrl[i + 1]
		var p3: Vector2 = ctrl[mini(n - 1, i + 2)]
		for s in 8:
			var t: float = float(s) / 8.0
			var t2: float = t * t
			var t3: float = t2 * t
			var pt: Vector2 = 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)
			pit_pts.append(pt)
	pit_pts.append(ctrl[-1])


## 모든 서킷·클래스 공용 박스 사선 진입·정차·이탈 좌표/각도
## stall_u: sim._stall_u(idx) 값(0 ~ pit_pts.size()-1), k: -1(진입) → 0(정차) → +1(이탈)
func pit_box_pose(stall_u: float, k: float, garage: bool = false) -> Array:
	var n_max: float = maxf(1.0, float(pit_pts.size() - 1))
	var base: Array = pit_lane_point(clampf(stall_u + k * n_max * 0.04, 0.0, n_max))
	var pos: Vector2 = base[0]
	var ang: float = float(base[1])
	var norm: Vector2 = Vector2(-sin(ang), cos(ang)) * pit_side
	var depth: float = 9.0 if garage else 5.2
	var pull: float = 1.0 - smoothstep(0.0, 1.0, absf(k))
	var yaw: float = -signf(k) * sin(clampf(absf(k), 0.0, 1.0) * PI) * 0.34 * pit_side
	return [pos + norm * (depth * pull), ang + yaw]
```

### 3-2. 피트 시설 + 클래스별 정차 크루 연출 (`scripts/ui/race_view.gd`)
- 실제 코드 반영: 정차 여부는 기존 **`_stop_t.has(c.id)`**, 경과 시간은 **`sim.clock - float(_stop_t[c.id])`** 를 사용합니다.
- `apply_pit(c)`에서 `c.boxing = null`로 비우므로, `car.gd`에 `var last_pit: Dictionary = {}` 한 줄을 두고 `apply_pit`에서 `c.last_pit = d`로 남겨두면 정차 중 작업 종류(급유·타이어·교대·강제 수리)를 바로 읽을 수 있습니다.

```gdscript
func _draw_pit_complex(T, night: bool) -> void:
	var n_max: float = float(T.pit_pts.size() - 1)
	if n_max < 3.0:
		return
	var w: float = TRACK_W * _s
	# 속도 제한 입구·출구 흰색 횡단선
	for frac in [0.12, 0.88]:
		var bp: Array = T.pit_lane_point(frac * n_max)
		var p: Vector2 = _X(bp[0])
		var a: float = float(bp[1])
		var n: Vector2 = Vector2(-sin(a), cos(a)) * (w * 0.35)
		_ci.draw_line(p - n, p + n, Color("#e9edf2"), maxf(1.5, _s * 0.6))
	# 피트 월
	var wall: PackedVector2Array = PackedVector2Array()
	for i in range(int(n_max * 0.12), int(n_max * 0.88)):
		var bp2: Array = T.pit_lane_point(float(i))
		var a2: float = float(bp2[1])
		var out_n: Vector2 = Vector2(-sin(a2), cos(a2)) * (-T.pit_side * 3.2)
		wall.append(_X(bp2[0] + out_n))
	if wall.size() >= 2:
		_ci.draw_polyline(wall, Color("#64748b") if not night else Color("#334155"), maxf(1.5, _s * 0.45), true)
	# 팀별 피트 박스 + 개러지 실루엣 (sim._stall_u 재사용)
	for si in maxi(1, sim.n_stalls):
		var bp3: Array = T.pit_box_pose(sim._stall_u(si), 0.0)
		var p3: Vector2 = _X(bp3[0])
		var a3: float = float(bp3[1])
		var sc: float = _car_scale(false)
		_ci.draw_set_transform(p3, a3, Vector2(sc, sc))
		_ci.draw_rect(Rect2(-8.2, -5.8, 16.4, 11.6), Color(AMBER, 0.45), false, 0.8)
		var g_y: float = 7.5 * T.pit_side
		_ci.draw_rect(Rect2(-9.0, g_y - 3.5, 18.0, 7.0), Color("#1e293b") if not night else Color("#0f172a"))
		_ci.draw_set_transform_matrix(Transform2D.IDENTITY)


## 기존 _draw_crews() 확장: _stop_t 와 c.last_pit 기반, F1·F2·F3·WEC 전 클래스 대응
func _draw_crews_all() -> void:
	var wec: bool = sim.is_wec()
	var fmt: String = String(sim.rules.get("fmt", "f1"))
	var side: float = float(sim.T.pit_side)
	for c in sim.cars:
		if not _stop_t.has(c.id) or not _smooth.has(c.id):
			continue
		var sp: Dictionary = _smooth[c.id]
		var sc: float = _car_scale(c.mine)
		var e: float = sim.clock - float(_stop_t[c.id])
		var dur: float = maxf(2.1, c.pit_total * 0.5) # _lane_u 정차 구간 비율(0.5) 기준
		var prog: float = clampf(e / dur, 0.0, 1.0)
		var lp: Dictionary = c.last_pit
		var forced: bool = bool(lp.get("forced", false))
		var do_tyres: bool = bool(lp.get("tyres", true))
		var do_fuel: bool = wec and not forced and bool(lp.get("fuel", true))
		var do_drv: bool = wec and bool(lp.get("driver", false))
		var pulse: float = 0.5 + 0.5 * sin(_now * (22.0 if fmt == "f1" else 14.0))
		var suit: Color = c.rim
		var fuel_on: bool = do_fuel and (prog < 0.60 or not do_tyres)
		var tyre_k: float = 0.0
		if do_tyres and not forced:
			tyre_k = sin(clampf((prog - 0.60) / 0.40, 0.0, 1.0) * PI) if (wec and do_fuel) else sin(prog * PI)
		_ci.draw_set_transform(_X(sp["p"]), float(sp["a"]), Vector2(sc, sc))
		if not forced:
			_ci.draw_circle(Vector2(10.5, 0.0), 1.4, suit)
			_ci.draw_circle(Vector2(-10.5, 0.0), 1.4, suit)
		if do_tyres and not forced:
			var per_wheel: int = 2 if (not wec and fmt == "f1") else 1
			for wpos in [Vector2(4.2, -7.6), Vector2(4.2, 7.6), Vector2(-4.0, -7.8), Vector2(-4.0, 7.8)]:
				var off_y: float = signf(wpos.y) * (2.6 * (1.0 - tyre_k) + (pulse * 0.35 if tyre_k > 0.2 else 0.0))
				for mi in per_wheel:
					var mx: float = (float(mi) - 0.5) * 2.2 if per_wheel == 2 else 0.0
					var mp := wpos + Vector2(mx, off_y)
					_ci.draw_circle(mp, 1.4, suit)
					_ci.draw_circle(mp, 0.55, Color("#e2e8f0"))
		if fuel_on:
			_ci.draw_line(Vector2(-1.0, 3.8 * side), Vector2(-2.5, 10.5 * side), Color("#f59e0b"), 1.3)
		if do_drv and prog < 0.55:
			_ci.draw_circle(Vector2(0.5, 5.2 * side), 1.3, Color("#38bdf8"))
		if forced:
			_ci.draw_circle(Vector2(5.5, 4.5 * side), 1.4, suit)
			if pulse > 0.65:
				_ci.draw_circle(Vector2(4.5, 1.5 * side), 1.1, Color("#fde047"))
		if prog >= 0.90:
			_ci.draw_circle(Vector2(12.0, 0.0), 1.2, GREEN)
		_ci.draw_set_transform_matrix(Transform2D.IDENTITY)
```

---

## 4. 수정 #32 · 차량 애니메이션 고무줄 현상 해결 (`scripts/ui/race_view.gd`)

`_update_cars(delta)` 내부 교체 초안:

```gdscript
	# 1) 겹침 밀림 상한(gap_d * 2.5) + 밀린 차 좌우 분산 (269~278행 교체)
	var max_push: float = gap_d * 2.5
	var push_lat := {}
	for sid in slots:
		var cl: String = targets[sid]["cls"]
		var ti: int = int(take.get(cl, 0))
		take[cl] = ti + 1
		var cid = last_by_cls[cl][ti]
		var tg_c: Dictionary = targets[cid]
		var raw_d: float = float(tg_c["raw"])
		var dd: float = float(tg_c["d"])
		if prev_d - dd < T.L * 0.5:
			dd = maxf(raw_d - max_push, minf(dd, prev_d - gap_d))
		if raw_d - dd > gap_d * 0.35:
			push_lat[cid] = TRACK_W * 0.22 * (1.0 if (ti % 2) == 0 else -1.0)
		tg_c["d"] = dd
		prev_d = dd

	# 2) rs <= 0 뒤로 가기 원천 차단 + 보정 속도 폭 0.75~1.25로 축소 (310~332행 교체)
		if tg is Dictionary:
			var td: float = float(tg["d"])
			var lw: float = float(lat_want.get(id, push_lat.get(id, 0.0)))
			var s: Variant = _smooth.get(id)
			var raw: float = float(tg["raw"])
			if s == null or not s.has("d") or absf(wrapf(td - float(s["d"]), -T.L * 0.5, T.L * 0.5)) > snap_dist:
				s = {"d": td, "lat": lw, "raw": raw, "v": 0.0}
				_smooth[id] = s
			else:
				var diff: float = wrapf(td - float(s["d"]), -T.L * 0.5, T.L * 0.5)
				var rs: float = raw - float(s["raw"])
				var step := 0.0
				if rs > 0.0:
					step = clampf(diff * kd, rs * 0.75, rs * 1.25)
					step = lerpf(float(s["v"]), step, kv)
				else:
					step = 0.0
				s["v"] = step
				s["raw"] = raw
				s["d"] = float(s["d"]) + step
				s["lat"] = lerpf(float(s["lat"]), lw, clampf(delta * 4.0, 0.0, 1.0))
			var ha: float = T.head_at_dist(float(s["d"]))
			s["p"] = T.point_at_dist(float(s["d"])) + Vector2(-sin(ha), cos(ha)) * float(s["lat"])
			s["a"] = ha
			continue
```

---

## 5. WEC 페널티 개편 (트랙 리밋·접촉 + 드라이브 스루 / 스톱 앤 고)

> 실제 `race_sim.gd` 함수명(`wec_decision`, `request_pit_wec`, `apply_pit`, `_drive_lap`, `c.pit_req`)에 맞춰 수정했습니다.

### 5-1. 차량 상태 추가 (`scripts/sim/car.gd`)

```gdscript
## 별도 피트 진입이 필요한 페널티 (null 또는 {"kind": "dt"|"sg", "secs": float, "due": int, "why": String})
var pending_pen: Variant = null
var last_pit: Dictionary = {} # 마지막 정차 내용 (연출용)
```

### 5-2. 발부 · 기한 관리 · 작업 없는 이행 (`scripts/sim/race_sim.gd`)

```gdscript
## 드라이브 스루("dt") 또는 스톱 앤 고("sg") 발부 — 발부 후 3랩 이내 그린 상태에서 별도 피트 진입 필요
func add_drive_penalty(c, kind: String, secs: float, why: String) -> void:
	var due: int = mini(laps, c.lap + 3)
	if c.pending_pen != null:
		var prev: Dictionary = c.pending_pen
		if kind == "sg" or String(prev["kind"]) == "sg":
			kind = "sg"
		secs += float(prev["secs"])
		due = mini(due, int(prev["due"]))
	c.pending_pen = {"kind": kind, "secs": secs, "due": due, "why": why}
	c.pen_log.append({"lap": c.lap + 1, "why": why, "secs": secs, "kind": kind})
	var label := "드라이브 스루" if kind == "dt" else ("스톱 앤 고 %d초" % int(secs))
	event("🟨 %s %s (%s · L%d까지 작업 없이 이행)" % [name_of(c), label, why, due], "bad")
	if c.mine:
		say(c, "%s 페널티예요(%s). L%d까지 급유·교체 없이 피트 통과해야 해요" % [label, why, due])


## 1) WEC 트랙 리밋 (sector_time 의 F1 트랙 리밋 아래에 추가 — F1 과 별도 카운트·기준)
func _check_wec_track_limit(c, sh: float, err_m: float, att_on: bool) -> void:
	if not is_wec() or sc or rnd() >= 0.006 * sh * err_m * (0.6 + c.aggr) * (1.3 if att_on else 1.0):
		return
	c.tl_warn += 1
	if c.tl_warn == 4:
		add_drive_penalty(c, "dt", 0.0, "트랙 리밋 위반 4회")
	elif c.tl_warn > 4 and (c.tl_warn - 4) % 2 == 0:
		add_drive_penalty(c, "sg", 5.0, "트랙 리밋 누적 %d회" % c.tl_warn)
	elif c.mine and c.tl_warn <= 3:
		say(c, "트랙 리밋 경고 (%d/3). 한 번 더 넘으면 드라이브 스루예요" % c.tl_warn)


## 2) 멀티클래스 트래픽·공격 추월 접촉 책임 (sector_time 1333행 접촉 지점에서 호출)
func _check_contact_penalty(c, severe: bool = false) -> void:
	if not is_wec():
		return
	if severe:
		add_drive_penalty(c, "sg", 10.0, "트래픽 중대 접촉 책임")
	elif rnd() < (0.45 if c.instr == "attack" else 0.20):
		add_drive_penalty(c, "dt", 0.0, "트래픽 접촉 책임")


## 3) 랩 종료 시 기한 체크 (_drive_lap(c) 2453행 직후 호출)
func _tick_pending_pen(c) -> void:
	if c.pending_pen == null:
		return
	if sc:
		c.pending_pen["due"] = mini(laps, int(c.pending_pen["due"]) + 1)
		return
	if c.lap >= int(c.pending_pen["due"]):
		var why: String = String(c.pending_pen["why"])
		c.pending_pen = null
		add_penalty(c, 30.0, "%s 미이행 가중" % why)


## 4) 플레이어 원클릭 이행 예약 (wec_decision 이 c.pit_req != "" 를 보므로 pit_req 도 같이 설정)
func request_serve_pen(c) -> bool:
	if c.pending_pen == null or sc or not c.is_running() or c.boxing != null:
		return false
	c.pit_req = c.comp
	c.wec_req = {"tyres": false, "driver": false, "fuel": false, "drv": -1, "fill": 0.0, "serve_pen": true}
	if c.mine:
		say(c, "이번 랩에 페널티 이행 진입합니다 (급유·타이어 작업 없음)")
	return true


## 5) 연결 지점 3곳 (race_sim.gd 기존 함수 내부):
##   - wec_decision(c, ...) 2230행 반환 딕셔너리에 `"serve_pen": bool(req.get("serve_pen", false))` 추가
##   - wec_decision(c, ...) AI 분기(2231행 아래):
##       if c.pending_pen != null and not sc:
##           var left_due: int = int(c.pending_pen["due"]) - c.lap
##           if left_due <= 1 or c.fuel > _wec_burn(c, c.fuel_mode) * 1.8:
##               return {"comp": c.comp, "tyres": false, "driver": false, "fuel": false, "fill": 0.0, "serve_pen": true}
##   - 피트 시간 계산(2537행):
##       if d.get("serve_pen", false) and c.pending_pen != null:
##           c.pit_total = pit_loss() + float(c.pending_pen["secs"])
##   - apply_pit(c) (2612행 아래):
##       c.last_pit = d
##       if d.get("serve_pen", false) and c.pending_pen != null:
##           c.pen_served += float(c.pending_pen["secs"])
##           c.pending_pen = null
##           return # tyres/fuel/driver 작업 전부 건너뜀
```

### 5-3. 피트 탭 원클릭 이행 버튼 (`scripts/ui/race_panel.gd`)

```gdscript
## _refresh_pit(c) 안: c.pending_pen != null 일 때만 경고 배너 + 원클릭 버튼 표시
##   _pen_serve_btn.visible = c.pending_pen != null
##   if c.pending_pen != null:
##       var kind_s := "드라이브 스루" if String(c.pending_pen["kind"]) == "dt" else ("스톱 앤 고 %d초" % int(c.pending_pen["secs"]))
##       _pen_serve_btn.text = "🟨 %s 이행 (L%d까지 · 작업 불가)" % [kind_s, int(c.pending_pen["due"])]
##       _pen_serve_btn.disabled = sim.sc
##   # 버튼 누르면 sim.request_serve_pen(c) 호출
```

---

## 6. 옛 저장 파일 호환 테스트 (`tests/save_compat.gd`)

> 커리어(`career.gd`)·레이스 중간 저장(`race_save.gd`)에 새 필드가 추가돼도, **예전 버전 저장 파일을 불러왔을 때 깨지지 않는지** CI 에서 자동 확인하는 헤드리스 테스트 초안입니다.  
> 실행: `godot --headless --path . --script res://tests/save_compat.gd`

```gdscript
extends SceneTree
## 옛 저장 파일 호환 테스트: 새 필드가 빠진 구버전 커리어·레이스 저장을 불러와 오류 없이 동작하는지 확인

const CareerS = preload("res://scripts/sim/career.gd")
const RaceSimS = preload("res://scripts/sim/race_sim.gd")
const RaceSaveS = preload("res://scripts/sim/race_save.gd")


func _initialize() -> void:
	_test_old_career("f1")
	_test_old_career("wec")
	_test_old_race_save()
	print("PASS save_compat")
	quit(0)


## 새 필드(staff_v2, chief.strategy/pit, wec_bop, team_id, car_model 등)가 없던 구버전 커리어 저장 복원
func _test_old_career(ser: String) -> void:
	var c = CareerS.new()
	c.save_slot = 3
	c.series = ser
	c.new_career("create", 0, {"name": "Old Save Team"}, 12345)
	# 구버전처럼 최신 필드들을 일부러 삭제한 뒤 저장 → 다시 불러오기
	for k in ["staff_v2", "wec_bop", "team_id", "title_brand", "car_model", "model_bop", "prev_rank"]:
		c.hq.erase(k)
	c.hq["chief"].erase("strategy")
	c.hq["chief"].erase("pit")
	c.save()

	var c2 = CareerS.new()
	c2.series = ser
	if not c2.load_save(3):
		push_error("구버전 %s 커리어 불러오기 실패" % ser)
		quit(1)
		return
	if not c2.hq["chief"].has("strategy") or not c2.hq["chief"].has("pit"):
		push_error("구버전 %s 커리어 스태프 마이그레이션 누락" % ser)
		quit(1)
		return
	# 불러온 뒤 핵심 조회 함수들이 오류 없이 도는지 확인
	var _st: Array = c2.standings()
	var _mods: Dictionary = c2.my_mods()
	var _eq: float = c2.eng_quality()
	c2.delete_save(3)


## 새 필드(used_tyres, pending_pen, car_model 등)가 없던 구버전 레이스 중간 저장 복원
func _test_old_race_save() -> void:
	var sim = RaceSimS.new()
	sim.setup("monza", "f1", "dry", 0, {"laps": 10}, 777)
	sim.advance(30.0)
	var packed: Dictionary = RaceSaveS.pack(sim)
	for cd in packed.get("cars", []):
		for k in ["used_tyres", "pending_pen", "car_model", "model_spec", "last_pit"]:
			cd.erase(k)
	var sim2 = RaceSaveS.unpack(packed)
	if sim2 == null or sim2.cars.size() != sim.cars.size():
		push_error("구버전 레이스 중간 저장 복원 실패")
		quit(1)
		return
	sim2.advance(15.0)
```

---

## 7. 보통 난이도 AI 전략 보강 의견 (설계 메모)

- **현재 상황**: `AGENTS.md` 및 `tests/calib.gd` 기준 보통 난이도(`DIFF_PACE = 1.0`, `DIFF_STRAT = 0.0`)에서 아무 조작 없이 기본 전략만 따르는 단순 봇이 AI보다 평균 약 2계단(예선 포함 3.5계단) 앞섬.
- **문제**: 플레이어가 전략을 조금만 신경 써도 보통 난이도가 너무 쉽게 느껴질 수 있음.
- **권장 방향 (원칙 9 준수 — 속도 치트 금지)**:
  - `DIFF_PACE`로 AI 차 속도를 억지로 빠르게 하지 말고, AI의 전략 판단 빈틈을 줄이는 방향으로 조정.
  - 우선 점검 대상:
    1. **SC·VSC 피트 찬스 놓침 빈도(`sc_miss`)**: 보통 난이도에서 상위권·중위권 AI가 명백한 SC 공짜 피트를 과하게 놓치지 않도록 비율 재점검.
    2. **언더컷 대응(`undercut_net` 재사용)**: 뒤차가 언더컷으로 들어갔을 때 커버링(`covering`) 반응 속도·기준 보강.
    3. **예선 전략·타이어 선택**: 주말 모드 봇 격차(3.5계단)가 예선 셋업/타이어 선택 차이에서 커지는지 `calib.gd`로 원인 분리 후 보정.
- **목표 검증**: `tests/calib.gd` 보통 난이도에서 단순 봇 vs AI 격차를 약 0.5~1.0계단 수준으로 줄이고, 직접 전략을 짠 플레이어가 이길 수 있게 균형 유지.
