extends RefCounted
## F1 레이스 시뮬레이션 코어. 화면과 완전히 분리되어 있어 헤드리스 테스트로도 돌릴 수 있다.
## 원본 HTML 버전(v16.1)의 계산식을 그대로 옮겼다 — 밸런스 검증 결과를 유지하기 위해서.
##
## 시간 모델: 차는 섹터(한 바퀴 6개) 단위로 움직인다. 섹터 진입 시 그 섹터의 소요 시간을 계산해
## sec_end에 예약하고, advance()가 가장 먼저 끝나는 차부터 순서대로 처리한다(이벤트 큐 방식).

const CarS = preload("res://scripts/sim/car.gd")
const BLog = preload("res://scripts/sim/blog.gd")
const DB = preload("res://scripts/data/game_db.gd")
const TraitsS = preload("res://scripts/sim/traits.gd")

const NS := 6
const FPL := 1.6
const WEAR_SCALE := 60.0
const H_CLIFF := 0.62
const SPEED_BASE := 4.0 # 화면 1× = 시뮬레이션 4배속

const COMP := {"S": [-1.05, 0.048, 4.0], "M": [0.0, 0.032, 3.3], "H": [0.50, 0.027, 2.6], "I": [0.0, 0.038, 3.3], "W": [0.0, 0.032, 3.1]}
## WEC 하이퍼카(미쉐린) 전용: 컴파운드 사이 속도·마모 차이는 작고, 노면 온도 창이 고르는 기준 (수정 24).
## F1 표를 그대로 쓰면 소프트가 미디엄보다 1.5배 닳아 더블 스틴트도 못 버팀 — 실제 르망은 밤에 소프트 트리플 스틴트(미쉐린 2025).
## 미디엄은 F1 표와 같음 → LMGT3·LMP2(미디엄 한 종류) 결과는 그대로
## 수정 31 역할 나누기: 소프트 = 추운 날 한 스틴트(마모 0.034 → 0.037, 더블이면 70% 로 절벽), 미디엄 = 더블, 하드 = 더운 날·트리플.
## 하드 = 트리플 스틴트 타이어 (수정 31): 마모 0.029 → 0.024, 절벽 0.62 → WEC_H_CLIFF. 트리플(15랩) 끝 약 68% 로 절벽 전
## (예전엔 미디엄보다 먼저 절벽이라 하드 장점이 온도 창 하나뿐이었음). 속도 +0.30 · 워머 금지 손해는 그대로
const WEC_COMP := {"S": [-0.25, 0.037, 3.6], "M": [0.0, 0.032, 3.3], "H": [0.30, 0.024, 3.0], "I": [0.0, 0.038, 3.3], "W": [0.0, 0.032, 3.1]}
const WEC_H_CLIFF := 0.75
const WIN_BASE := 0.15 # 온도 창을 벗어나는 순간 타이어 온도 목표가 과열·저온 경계까지 이동
const AWD_WET := 0.12   # 사륜 구간 비율 1 일 때 비 오는 날 그립 손해를 이만큼 덜 (르망 흠뻑 젖음 ≈ 랩당 0.8초)
const HY_VMAX := 340.0  # 하이퍼카 최고 속도 km/h — 트랙 상대 속도(T.spd 1 = 최고)를 km/h 로 어림
const DAY_AMP := 5.0   # 낮 동안 노면 온도 오르내림 (°C, 오후 최고 − 하루 평균 ≈ +2.5)
const WET_COOL := 12.0 # 흠뻑 젖은 노면은 이만큼 차갑다 (°C, 젖음 비례 — 마르면 다시 데워짐)
const WIN_K := 0.03    # 그 뒤 1°C 마다 더 (뜨거우면 과열·마모, 차가우면 그립·실수 — 기존 타이어 온도 식이 계산)
const SLICK := {"S": true, "M": true, "H": true}
const TYRE_KO := {"S": "소프트", "M": "미디엄", "H": "하드", "I": "인터", "W": "웻"}
const TYRE_HEX := {"S": "#ef4444", "M": "#facc15", "H": "#f1f5f9", "I": "#22c55e", "W": "#3b82f6"}
const PACE := {"attack": [1.2, 1.35, 1.6, 0.78], "standard": [1.0, 1.0, 1.0, 0.62], "save": [0.7, 0.75, 0.6, 0.52]}
const PACE_FUEL := {"attack": 1.06, "standard": 1.0, "save": 0.93} # 페이스별 연료 소모 배율
const PACE_KO := {"attack": "공격", "standard": "표준", "save": "세이브"}
const ERS := {"harvest": [0.40, 0.30], "balance": [0.0, 0.02], "deploy": [-0.60, -0.35]}
const ERS_KO := {"harvest": "충전", "balance": "밸런스", "deploy": "오버테이크"}
const FUEL := {"lean": [0.50, 0.90], "std": [0.0, 1.0], "rich": [-0.25, 1.08]}
# 타이어 공기압 (psi): 슬라이더 = 넣을 때(차가운/출발) 공기압, 달리면 노면 온도·스틴트 길이만큼 오른다.
# 최소값은 타이어 회사 규정(서킷 데이터 psiMin, 피렐리 프리뷰 '최소 출발 공기압' 앞바퀴 기준).
const PSI_SPAN := 5.0  # 슬라이더 = 최소 ~ 최소 + 5 psi
const PSI_U := 1.5     # 데워진 공기압이 최적에서 1.5 psi 벗어남 = 한 칸 (예전 낮게/높게 정도)
const DIRTY_WEAR := 0.12  # 더티 에어 바짝(0초) 붙으면 마모 +12% (다운포스 많은 서킷일수록 큼) — 따라가기만 하면 타이어가 먼저 죽음
const DIRTY_TT := 0.06    # 더티 에어 타이어 온도 목표 +0.06 (과열 0.80 넘기 쉬워짐)
const K := {"car_scale": 0.92, "drv_k": 0.022, "noise": 0.28, "fail": 0.0045, "crash": 0.005, "overtake_scale": 0.21, "victim": 0.25, "dirty": 1.0, "ot_gap": 0.3}
const POINTS := [25, 18, 15, 12, 10, 8, 6, 4, 2, 1]
# WEC 규칙 (HTML 원본과 동일)
const STINT := 5                 # 스틴트 5랩 (연료 세이브면 6랩)
const TANK := 5.45 * 1.6         # 연료 탱크 = 5.45랩 분량
const GT3_PACE := 1.12
const CLASS_PACE := {"HY": 1.0, "P2": 1.06, "P3": 1.10, "GT": 1.12} # 클래스 기본 페이스 배율 (LMP2는 하이퍼카와 GT3 사이, LMP3 는 GT3 보다 조금 빠름)
const CLS_TAG := {"HY": "HY", "P2": "LMP2", "P3": "LMP3", "GT": "LMGT3"}
const GRADE_KO := {"P": "플래티넘", "G": "골드", "S": "실버", "B": "브론즈"}
const BOP_K := 0.006
const WEC_WEAR := 1.9            # 미디엄 1스틴트 ≈ 32%, 더블 스틴트 끝 ≈ 63% (2026 세트 제한 → 더블 스틴트가 기본)
## WEC 2026 타이어 규정: 레이스용 새 드라이 세트 = 스틴트 수 × 비율 (출발 세트 포함). LMGT3 는 추가 타이어를 받아 조금 더 많다
const WEC_SET_RATIO := {"HY": 0.6, "P2": 0.6, "P3": 0.75, "GT": 0.75}
const WEC_COLD_TT := {"S": 0.30, "M": 0.24, "H": 0.17, "I": 0.30, "W": 0.32} # 워머 금지: 피트 직후 타이어 온도
const WPIT := {"lane": 30.0, "fuel": 30.0, "tyres": 12.0, "driver": 3.0}
# 급유 시간 = 고정(호스 연결) 20% + 넣는 양에 비례 80%. FUEL_REF = 예전 '항상 가득' 시절 평균 주유량(탱크 대비, 5서킷 3105회 측정 0.90) → 평균 정차 시간이 예전과 같게
const FUEL_FIX := 0.2
# 연료 무게 → 랩타임 (연료 1단위당 초/랩). F1 은 원작 0.03. WEC 는 가득 찬 탱크가 랩당 약 +1.0초가 되게 (실제 ~0.03초/kg/랩, 스틴트 연료 수십 kg)
# — 예전 0.03 이면 가득 vs 빈 탱크 0.26초라 급유량 선택이 체감되지 않았다
const FUEL_K_WEC := 1.0 / (5.45 * 1.6)
const FUEL_REF := 0.90
const WEC_FUEL_KO := {"lean": "세이브", "std": "표준", "rich": "리치"}
const STRAT_STYLES := ["aggressive", "balanced", "conservative", "reactive"]
const STRAT_KO := {"aggressive": "공격형", "balanced": "균형형", "conservative": "보수형", "reactive": "반응형"}

var rng := RandomNumberGenerator.new()
var wx_rng := RandomNumberGenerator.new() # 날씨(섹터·예보) 전용 → 마른 레이스 결과는 예전과 같게
var T: Variant            # 트랙 (track.gd)
var CIRC: Dictionary = {}
var circ_key := ""
var series := "f1"
var min_drive: Variant = null
## 시리즈 규칙: two_compounds(드라이 레이스 두 컴파운드 의무) · wear_mult(타이어 마모 배율, F3·스프린트는 작게)
var rules := {"two_compounds": true, "wear_mult": 1.0} # 하위 클래스 최소 주행 규정 {grade, pct} (예: 브론즈 25%)
var laps := 15
# WEC 시간제: 정해진 시간이 지나면 선두가 결승선을 지날 때 체커기. laps 는 '예상 총 랩'으로 선두 랩마다 다시 계산한다
# (나머지 계산 — 피트 판단·연료·주행 시간 규정 — 은 그대로 laps 를 쓴다)
const TIME_K := 1.025       # 선두 한 바퀴 평균(피트 포함) ≈ 기본 랩타임 × 1.025 (6개 서킷·짧게/표준·4시드 측정, SC 없는 레이스 1.00~1.03)
var timed := false
var time_limit := 0.0       # 시간 한도 (시뮬 초)
var laps_nom := 0           # 처음 정한 랩 수 (시간 한도 계산 기준)
var time_up := false
var _fuel_stat := [0.0, 0]  # 넣은 연료 합(탱크 대비) · 횟수 — 밸런스 측정용        # 시간 종료 — 선두가 다음에 결승선을 지나면 체커기
var my_team := -1
var cars: Array = []
## 난이도: 0 쉬움 · 1 보통(원작 밸런스) · 2 어려움 · 3 전설. AI 차 랩타임 배율.
const DIFF_PACE := [1.0065, 1.0, 0.994, 0.99]
const DIFF_STRAT := [-0.12, 0.0, 0.05, 0.09]
const DIFF_KO := ["쉬움", "보통", "어려움", "전설"]
var difficulty: int = 1
var true_mult: Dictionary = {"S": 1.0, "M": 1.0, "H": 1.0}
var plan_mult: Dictionary = {}  # 내 팀이 연습 롱런으로 알아낸 컴파운드별 마모 배율 추정 (없으면 1.0 = 모름, weekend 가 채움)

# 레이스 상태
var clock := 0.0
var wet := 0.0
var track_evo := 0.15
var rain: Variant = null # {start, end, level}
var fc: Variant = null   # 예보 {lo, hi, p} — 비가 안 오는 날의 '헛예보'에만 쓴다 (비 오는 날은 rain + 팀 오차)
# 섹터별 노면: wet = 섹터 평균(랩타임 비중), 기존 판단 코드는 이 평균을 본다
var sec_wet: Array = []  # 섹터별 레이싱 라인 젖음 0~1 (차가 실제로 달리는 곳)
var off_wet: Array = []  # 섹터별 라인 밖 젖음 — 마를 때 라인이 먼저 마르고 밖은 늦게 (추월·실수에 영향)
var wx_k: Array = []     # 섹터별 비 세기 배율 (한쪽만 더 쏟아짐)
var wx_dry: Array = []   # 섹터별 마르는 속도 배율 (그늘·나무 = 느림)
var wx_lag: Array = []   # 섹터별 비가 늦게 닿고 늦게 그치는 랩 수 (비구름이 한쪽에서 들어옴)
var _fcw: Dictionary = {} # fc_window 캐시 (저장 안 해도 됨)
var fc_err: Dictionary = {} # 팀 이름 → 예보 오차 {st, en, lv} (랩마다 레이더처럼 갱신, 전략 능력이 높을수록 작음)
var sc := false
var sc_kind := ""
var sc_end_lap := 0
var start_tyres_taken := false # 주말 모드: 출발 타이어 세트를 이미 꺼냄 (weekend.commit_start_tyres)
var first_cross := -1        # 체커기를 처음 받은 차 id (페널티로 우승이 바뀌면 알림)
var wave_clear_lap := -1     # WEC 웨이브 바이 후 리스타트 랩: 빠른 클래스 앞에 느린 클래스가 없음
var pit_closed_until := -1   # 이 선두 랩 전까지 피트레인 폐쇄 (피트 입구 근처 사고로 SC 가 나온 직후 1랩)
var wet_start := false       # 폭우 속 세이프티카 선도 스타트 (전 차량 풀 웻 의무)
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
var track_t := 35.0      # 오늘 노면 온도 (°C) — 높을수록 공기압이 많이 오른다
var track_now := 35.0    # 지금 노면 온도 (°C) — WEC 는 밤에 식는다 (track_temp_at, 선두 랩마다)
var psi_min := 22.0      # 최소 출발 공기압 (규정)
var psi_hot_opt := 24.0  # 숨은 최적 '주행(데워진)' 공기압 — 연습 피드백·엔지니어 추천으로 찾는다
var psi_eng_err := 0.0   # 퀵 레이스 내 팀 엔지니어 추천의 치우침
var n_stalls := 11
var radio_log: Array = [] # {lap, who, color, msg, kind}
var team_order := "free"   # 팀 오더: free 자유 경쟁 / hold 순서 유지
var swap_req := false      # 팀 오더: 다음 기회에 앞 팀메이트가 양보
var team_swap_lap := {}    # AI 팀 오더를 마지막으로 낸 랩 (팀별) — 같은 두 대가 순서를 주고받지 않게
var active_radio: Variant = null  # 엔지니어 제안 {slot, title, msg, opts:[{label, act, comp}]}
var radio_seq := 0         # 새 제안이 뜰 때마다 +1 (UI가 감속·표시에 사용)
var sc_laps: Array = []    # SC·VSC·FCY 가 걸린 선두 랩 (복기 차트용)
var team_split := {}       # 팀 → 첫 차의 계획 스톱 수 (두 번째 차는 다른 전략으로 나누기도)
var tally := {}            # 레이스 중 AI 전술·실수 횟수 (테스트·밸런스 확인용)
var iradio_done := {}      # "차id:종류" → true (같은 제안은 한 번만)
var prompts_enabled := true  # 설정에서 끄면 엔지니어 제안 창을 띄우지 않음

var _oc: Array = []          # order_ui 캐시
var _oc_clock := -1.0


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
	return maxi(1, int(ceil(stints * wec_set_ratio(cls)))) - 1


## 스틴트당 새 드라이 세트 비율 (출발 세트 포함). 2026 규정 할당(data/wec.json tyreAlloc: 타이어 개수, 시간별)을
## 실제 스틴트 수(시간 × stintsPerHour)로 나눠 압축된 레이스에 옮긴다. 표에 없는 클래스·시간은 예전 비율(WEC_SET_RATIO)
func wec_set_ratio(cls: String) -> float:
	var tab: Dictionary = DB.wec.get("tyreAlloc", {}).get(cls, {})
	var hk: String = str(int(round(wec_hours())))
	if tab.has(hk):
		return float(tab[hk]) / 4.0 / (wec_hours() * float(DB.wec.get("stintsPerHour", 1.25)))
	return float(WEC_SET_RATIO.get(cls, 0.6))


## WEC 드라이버 주행 시간 규정 (르망 규정 기준, 레이스 길이에 비례):
## 어떤 6시간 구간에서도 4시간 초과 금지 · 르망은 한 명 최대 14시간·최소 6시간. 랩 수로 바꿔 쓴다
func wec_hours() -> float:
	return float(CIRC.get("wecHours", 6.0))


func drive_limits() -> Dictionary:
	var h: float = wec_hours()
	# 시간제에선 예상 총 랩이 레이스 중에 바뀐다 → 한도(최대)는 처음 기준으로 고정(중간에 바뀌면 AI·플레이어 계획이 뒤늦게 위반이 됨),
	# 의무(최소)는 늘지 않게 (SC 로 랩이 줄면 그만큼 덜 타도 됨)
	var laps_hi: int = laps_nom if timed else laps
	var laps_lo: int = mini(laps, laps_nom) if timed else laps
	var win: int = maxi(1, int(round(laps_hi * minf(1.0, 6.0 / h))))
	# 압축된 레이스에서도 연비 주행 한 스틴트(최대 약 STINT+2랩)는 한 명이 탈 수 있게
	# 랩 단위로 바꿀 때 2랩 여유 (압축된 르망 60랩에선 4시간 ≈ 10랩 = 더블 스틴트라, 연료가 조금 남아 한 랩 더 돌면 억울한 위반이 됐다)
	var max_win: int = maxi(STINT + 2, int(round(laps_hi * minf(1.0, 4.0 / h))) + 2)
	var max_total: int = maxi(STINT + 2, int(floor(laps_hi * 14.0 / 24.0))) if h >= 24.0 else laps_hi
	var min_each: int = int(ceil(laps_lo * 6.0 / 24.0)) if h >= 24.0 else 0
	return {"win": win, "max_win": max_win, "max_total": max_total, "min_each": min_each}


## 르망 드라이버별 최소 주행(24시간 중 6시간)을 차의 클래스 기준 랩으로.
## 규정은 '시간'이라 느린 클래스는 그만큼 적은 랩이면 된다 (예전엔 전체 랩 기준이라 GT3 가 거의 다 위반).
## 압축된 레이스는 랩 단위가 거칠어서 반올림 대신 내림.
## 시간제: 계획(AI 교대·화면)은 처음 기준 랩으로 — 예상 랩이 오르내려도 목표가 흔들리지 않게(조금 엄격),
## 체커 판정(for_check)은 실제 랩과 처음 기준 중 작은 쪽으로 (SC 로 랩이 줄면 덜 타도 됨)
func min_each(c, for_check: bool = false) -> int:
	if wec_hours() < 24.0:
		return 0
	var base_l: int = laps
	if timed:
		base_l = mini(laps, laps_nom) if for_check else laps_nom
	var est: float = float(base_l) / float(CLASS_PACE.get(c.cls, 1.0))
	return maxi(1, int(floor(est * 6.0 / 24.0)))


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
	_calc_sec_kinds()
	CIRC = DB.circuits[circ_key]
	series = CIRC.get("series", "f1")
	min_drive = opts.get("min_drive", null)
	difficulty = clampi(int(opts.get("difficulty", 1)), 0, DIFF_PACE.size() - 1)
	rules = {"two_compounds": true, "wear_mult": 1.0}
	if opts.has("rules"):
		for k in opts["rules"]:
			rules[k] = opts["rules"][k]
	laps = laps_
	laps_nom = laps_
	timed = series == "wec" and bool(opts.get("timed", true))
	time_limit = float(laps_) * float(CIRC["base"]) * TIME_K if timed else 0.0
	time_up = false
	my_team = my_team_
	true_mult = {"S": uni(0.88, 1.14), "M": uni(0.88, 1.14), "H": uni(0.88, 1.14)}
	plan_mult = {}
	if opts.has("true_mult"):
		true_mult = opts["true_mult"]
	cars.clear()
	radio_log.clear()
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
	_init_tyre_press()
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
				c.psi = setup_psi({})
				if k < setups.size():
					var su: Dictionary = setups[k]
					c.wing = float(su.get("wing", c.wing))
					c.psi = setup_psi(su)
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
	# 파워유닛·기어박스가 낡을수록 신뢰성 하락 (커리어 F1)
	if opts.has("pu_rel"):
		var pr: Array = opts["pu_rel"]
		for c in cars:
			if c.mine and c.slot < pr.size():
				c.rel = clampf(c.rel - float(pr[c.slot]), 0.5, 0.99)
			elif not c.mine and not opts.has("ai_grid_pen") and rnd() < 0.04:
				c.grid_pen = 10 if rnd() < 0.5 else 5 # (예전 저장 호환) AI 도 가끔 할당을 넘겨 부품 교체
	# AI 부품 강등 (커리어가 AI 부품 재고를 같은 규칙으로 계산해서 넘김)
	if opts.has("ai_grid_pen"):
		var ag: Dictionary = opts["ai_grid_pen"]
		for c in cars:
			if not c.mine and ag.has(c.team):
				var arr: Array = ag[c.team]
				c.grid_pen = int(arr[c.slot]) if c.slot < arr.size() else 0
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
	wet_start = false
	pit_closed_until = -1
	wave_clear_lap = -1
	if want_rain:
		var st = maxi(2, int(round(uni(0.2, 0.55) * laps)))
		rain = {"start": st, "end": mini(laps + 1, st + int(round(uni(0.3, 0.55) * laps))), "level": uni(0.8, 1.0) if rnd() < 0.4 else uni(0.4, 0.6)}
		# F1: 가끔은 출발부터 폭우 → 세이프티카 선도 스타트, 전 차량 풀 웻 의무 (실제 규정)
		if not is_wec() and rnd() < 0.18:
			rain = {"start": 0, "end": mini(laps + 1, int(round(uni(0.25, 0.5) * laps))), "level": uni(0.85, 1.0)}
			wet = float(rain["level"]) * 0.9
			ever_wet = true
			wet_start = true
	_wx_init()
	if rain != null:
		fc = null # 비 오는 날 예보는 팀마다 rain + 오차 (forecast_*)
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
		if not c.mine:
			c.psi = psi_snap(psi_rec("race") + gauss(0.2 + 0.8 * (1.0 - team_eng_q(c))))
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
	c.traits = TraitsS.of(d)
	if c.traits.has("saver"):
		c.tyre_deg_rate *= 0.93
	c.fuel_burn_rate = clampf(1.0 + (c.aggr - 0.60) * 0.22 + (0.82 - c.cons) * 0.18 - (c.tyre_mgmt - 0.78) * 0.12, 0.88, 1.14)
	c.name = d["name"]
	var parts: PackedStringArray = String(d["name"]).strip_edges().split(" ", false)
	var last: String = parts[parts.size() - 1] if parts.size() > 0 else c.name
	var letters = ""
	for ch in last:
		if ch.to_upper() != ch.to_lower():
			letters += ch
	c.code = _unique_code(c, letters.to_upper(), parts[0].substr(0, 1).to_upper() if parts.size() > 1 else "")


## 같은 레이스에 같은 약칭이 있으면 다른 글자 조합으로 (Hanafin·Hanses 둘 다 HAN 이던 것 → HAN · HNS)
func _unique_code(c, L: String, ini: String) -> String:
	if L == "":
		return "DRV"
	var cands: Array = [L.substr(0, 3)]
	if L.length() >= 3:
		cands.append(L.substr(0, 2) + L.substr(L.length() - 1, 1))
		for i in range(2, L.length()):
			cands.append(L.substr(0, 1) + L.substr(1, 1) + L.substr(i, 1))
		for i in range(1, L.length()):
			for j in range(i + 1, L.length()):
				cands.append(L.substr(0, 1) + L.substr(i, 1) + L.substr(j, 1))
	if ini != "":
		cands.append(ini + L.substr(0, 2))
	for cd in cands:
		var used := false
		for o in cars:
			if o != c and o.code == cd:
				used = true
				break
		if not used:
			return cd
	return cands[0]


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


## 컴파운드 값 [속도, 마모, 마모 손해 계수]: WEC 는 WEC_COMP
func cpv(k: String) -> Array:
	return WEC_COMP[k] if is_wec() else COMP[k]


## 이 컴파운드의 절벽이 시작되는 마모 (cliff_pen 과 같은 경계)
func cliff_at(comp: String) -> float:
	if comp == "H":
		return WEC_H_CLIFF if is_wec() else H_CLIFF
	if comp == "S" and not is_wec():
		return 0.60
	return 0.65


func cliff_pen(comp: String, w: float) -> float:
	if comp == "S" and is_wec() and w > 0.65: # WEC 소프트는 미디엄처럼 오래 감 (WEC_COMP)
		return 1.5 + 2.5 * minf(1.0, (w - 0.65) / 0.35)
	if comp == "S" and w > 0.60:
		return 1.6 + 2.6 * minf(1.0, (w - 0.60) / 0.40)
	if comp == "M" and w > 0.65:
		return 1.5 + 2.5 * minf(1.0, (w - 0.65) / 0.35)
	if comp == "H":
		var hc: float = cliff_at("H")
		if w > hc:
			return 2.0 + 2.8 * minf(1.0, (w - hc) / (1.0 - hc))
	return 0.0


## 기계 고장 (레이스 압축 보정): 랩당 확률 × (실제 랩 ÷ 게임 랩) × FAIL_SCALE.
## 그중 FAULT_SHARE 는 '반쯤 고장'(출력 저하·기어 문제 — 달리면서 버티거나 피트에서 고침), 나머지는 리타이어(WEC 는 손상)
const FAIL_SCALE := 2.8      # F1·F2·F3: 레이스 고장 리타이어 한 대당 약 4% (예전 0.5% — 압축 레이스에 랩당 확률을 그대로 둬서 너무 적었음)
const FAIL_SCALE_WEC := 1.0  # WEC
const FAULT_SHARE := 0.5
const FAULTS := [
	{"kind": "출력 저하", "dt": [0.5, 1.2], "fix": [12.0, 22.0], "esc": 0.006},
	{"kind": "기어 변속 문제", "dt": [0.35, 0.9], "fix": [18.0, 32.0], "esc": 0.02},
]
func fail_p(c) -> float:
	var real_n: float = real_laps() if is_wec() else 5400.0 / float(CIRC["base"])
	return (1.0 - c.rel) * K["fail"] * (real_n / maxf(1.0, float(laps))) * (FAIL_SCALE_WEC if is_wec() else FAIL_SCALE) * (1.3 if c.pace == "attack" else 1.0) * (1.2 if night else 1.0)


## 반쯤 고장 발생: 남은 랩 동안 잃을 시간 vs 수리 시간으로 판단 (AI 는 팀 감각만큼 오차, 내 차는 무전으로 선택)
func _start_fault(c) -> void:
	var f: Dictionary = FAULTS[0] if rnd() < 0.5 else FAULTS[1]
	c.fault = {"kind": f["kind"], "dt": uni(f["dt"][0], f["dt"][1]), "fix": uni(f["fix"][0], f["fix"][1]), "esc": f["esc"], "repair": false, "now": false}
	_tally("반쯤고장")
	event("🔧 %s %s — 랩당 약 +%.1f초" % [name_of(c), c.fault["kind"], c.fault["dt"]], "bad")
	if c.mine:
		BLog.add("반쯤 고장 %s (내 차) %s 랩%d 랩당 +%.1f초 수리 %.0f초" % [name_of(c), c.fault["kind"], c.lap + 1, c.fault["dt"], c.fault["fix"]])
		say(c, "%s 생겼어요! 랩당 %.1f초씩 느려요. 피트에서 고치면 약 %d초 걸려요" % [c.fault["kind"], c.fault["dt"], int(round(c.fault["fix"]))])
		c.fault["repair"] = true # 기본: 다음 피트 때 수리 (안 건드려도 합리적, 원칙 6)
		trigger_radio(c, "FAULT")
		return
	_fault_decide(c)


## AI: 버티면 잃을 시간 > 수리 시간(+계획 정차가 없으면 피트 한 번 값)이면 고친다
func _fault_decide(c) -> void:
	var left: int = laps - (c.lap + 1)
	var tact: float = c.strategy
	var stay_cost: float = (float(c.fault["dt"]) + gauss((1.0 - tact) * 0.3)) * left
	var stops_left: bool = next_stop(c) != null
	if stay_cost > float(c.fault["fix"]) + (0.0 if stops_left else stop_cost()):
		c.fault["repair"] = true
		c.fault["now"] = not stops_left


## 전략 계산용 피트 한 번의 값: 피트 손실 + 여유 3초 + 트랙 포지션 값.
## 추월이 어려운 서킷(모나코·싱가포르·잔트보르트)은 피트로 잃은 자리를 되찾기 힘들어 스톱을 아낀다
const TRACK_POS_K := 8.0
func stop_cost() -> float:
	return pit_loss() + 3.0 + TRACK_POS_K * clampf((0.30 - float(CIRC.get("overtake", 0.3))) / 0.26, 0.0, 1.0)


func true_wear_rate(comp: String) -> float:
	return float(cpv(comp)[1]) * float(true_mult.get(comp, 1.0)) * float(rules.get("wear_mult", 1.0))


# ── 쓴 타이어 세트 (수정 15): 세트마다 {"w": 쌓인 마모(이 레이스 랩 단위 0~1), "h": 달군 횟수} ──
const SET_LAP_EQ := 0.35   # 연습·예선 1랩 = 결승 1랩 마모의 0.35배 (결승 랩은 실제 레이스를 압축한 것)
const HEAT_PEN := 0.15     # 달군 횟수(최대 3회)당 결승 랩당 손해 (초) — 고무가 굳는 열 사이클.
                           # 예선 런 1~2번 쓴 소프트로 출발할 때 손해가 예전 고정(+0.45초·마모 0.10)과 평균이 같게 맞춤
const USED_W_OLD := 0.10   # 세트 기록이 없을 때(옛 저장) 쓴 세트 기본 마모


## 연습·예선 1랩에 그 세트에 쌓이는 마모 (mult = 공기압·윙·셋업·드라이버 마모 배율)
func set_lap_wear(comp: String, mult: float = 1.0) -> float:
	var per: float = (WEC_WEAR if is_wec() else WEAR_SCALE / maxf(1.0, float(laps)) * 0.85)
	return true_wear_rate(comp) * float(CIRC["wear"]) * per * SET_LAP_EQ * mult


## 가장 덜 쓴 세트 번호 (없으면 -1)
static func least_worn(arr: Array) -> int:
	var bi := -1
	for i in arr.size():
		if bi < 0 or float(arr[i]["w"]) < float(arr[bi]["w"]):
			bi = i
	return bi


## 쓴 세트를 끼우고 출발: 그 세트 마모에서 시작 + 열 사이클 손해 (스틴트 동안)
func fit_used(c, st: Variant) -> void:
	if st == null:
		c.wear = maxf(c.wear, USED_W_OLD)
		c.used_set_pen = HEAT_PEN
		return
	c.wear = clampf(float(st["w"]), 0.0, 0.9)
	c.used_set_pen = HEAT_PEN * float(mini(3, int(st["h"])))
	st["h"] = int(st["h"]) + 1
	c.set_h = int(st["h"])


## WEC 새 세트가 바닥났을 때 (수정 32): 빼 둔 세트 중 다음 n 랩을 가장 빨리 달릴 것과, 지금 세트로 버틸 때보다 얼마나 빠른지.
## cost = 그 세트로 바꾸는 데 드는 시간(급유 정차에 얹으면 타이어 교체 시간, 타이어만 바꾸러 들어오면 정차 전체).
## 돌려줌: {"comp", "gain"} (gain > 0 이면 바꾸는 게 이득) 또는 null (보관 세트 없음).
## 예전엔 "다 닳음"이면 무조건 쓴 세트로 바꿨는데, 소프트 더블 뒤 보관 세트가 57~65% 라 끼우자마자 또 다 닳음 → 마지막 몇 랩 매 랩 피트
func wec_reuse_gain(c, n: int, cost: float) -> Variant:
	var temp: float = run_temp(maxi(1, n))
	var stay: float = comp_run_time(c, c.comp, n, temp, c.wear, c.used_set_pen) if SLICK.has(c.comp) else INF
	var best: Variant = null
	for k in wec_comps(c.cls):
		var pool: Array = c.wec_pool.get(k, [])
		if pool.is_empty():
			continue
		var st: Dictionary = pool[least_worn(pool)]
		var t: float = comp_run_time(c, String(k), n, temp, float(st["w"]), HEAT_PEN * float(mini(3, int(st["h"]))))
		var g: float = stay - t - cost
		if best == null or g > float(best["gain"]):
			best = {"comp": String(k), "gain": g}
	return best


## 내 차 결승 피트: 새 세트가 없으면 주말에 쓴 세트 중 가장 덜 쓴 것 (쓴 세트 목록이 없으면 옛 방식 기본값)
func _fit_used_from_pool(c) -> void:
	var pool: Variant = c.used_tyres.get(c.comp) if c.used_tyres != null else null
	if pool != null and not (pool as Array).is_empty():
		fit_used(c, pool[least_worn(pool)])
	else:
		fit_used(c, null)


## 두 컴파운드 의무가 지금 적용되는지 (드라이 레이스 + 규칙)
func need_two() -> bool:
	return bool(rules.get("two_compounds", true)) and not is_wec() and not ever_wet


func drv_wing_pref(c) -> float:
	var d: Dictionary = c.drivers[c.drv]
	return snappedf((d["aggr"] - 0.58) * 1.1 + (d["wet"] - 0.82) * 0.6 - (d["tyreMgmt"] - 0.82) * 0.8, 0.01)


func wing_opt(w: float, c) -> float:
	return clampf(float(CIRC["wingOpt"]) + drv_wing_pref(c) + (1.0 if w > 0.25 else 0.0), 1.0, 5.0)


## 섹터 성격: 0 = 고속(직선 위주) ~ 1 = 저속(코너 위주). 샘플 속도 평균으로 섹터끼리 상대 비교
var sec_slow: Array = []
var _w_slow: Array = []   # 섹터별 '저속 가중치' (랩 전체 합 = 1이 되도록 정규화)
var _w_fast: Array = []


func _calc_sec_kinds() -> void:
	var avg: Array = []
	for i in NS:
		var a: int = int(T.sec_idx[i])
		var b: int = int(T.sec_idx[i + 1])
		var sm := 0.0
		var n := 0
		var j: int = a
		while j != b and n < T.m:
			sm += float(T.spd[j % T.spd.size()])
			n += 1
			j = (j + 1) % T.m
		avg.append(sm / maxf(1.0, n))
	var lo: float = avg.min()
	var hi: float = avg.max()
	sec_slow = []
	_sw = {}
	for v in avg:
		sec_slow.append(clampf((hi - float(v)) / maxf(0.001, hi - lo), 0.0, 1.0))
	var ss := 0.0
	var sf := 0.0
	for i in NS:
		ss += float(T.share[i]) * (0.25 + float(sec_slow[i]))
		sf += float(T.share[i]) * (1.25 - float(sec_slow[i]))
	_w_slow = []
	_w_fast = []
	for i in NS:
		_w_slow.append((0.25 + float(sec_slow[i])) / maxf(0.001, ss))
		_w_fast.append((1.25 - float(sec_slow[i])) / maxf(0.001, sf))


## 섹터 하나에서 셋업이 만드는 시간 (랩 전체 합은 예전과 같음, 어디서 잃는지만 섹터 성격을 따름):
## 윙이 모자라면 저속 코너에서, 많으면 직선에서 잃는다. 타이어 압력의 직선 효과는 고속 섹터에.
func setup_sec(c, sec: int, w: float) -> float:
	var sh: float = T.share[sec]
	var ws_: float = _w_slow[sec] if c.wing < wing_opt(w, c) else _w_fast[sec]
	var pu: float = press_u(c, "live")
	return setup_pen(c, w) * sh * ws_ + float(press_fx(pu)[0]) * sh + press_straight(pu) * sh * _w_fast[sec]


## 연습용 섹터별 예상 시간 (새 미디엄 · 가벼운 연료 · 깨끗한 랩)
func est_sectors(c) -> Array:
	var out: Array = []
	var dt: float = float(setup_extra(c, "q")["dt"])
	for i in NS:
		var sh: float = T.share[i]
		out.append(float(CIRC["base"]) * sh * car_factor(c) * (1.0 - c.speed * K["drv_k"]) + setup_sec(c, i, 0.0) + dt * sh)
	return out


func setup_pen(c, w: float) -> float:
	var d: float = c.wing - wing_opt(w, c)
	return 0.15 * d * d * wsc()


## 세부 셋업 (서스펜션·브레이크 밸런스·디퍼렌셜) = 타협 (D②, 2026-11-21). 슬라이더를 x = -1~+1(범위 가운데 0)로 보고,
## 항목마다 두 갈래 득실(SETUP_CH, x=+1 일 때 초/랩) × 서킷 비중(setup_w) → 서킷마다 다른 최적점.
## 랩타임 = 항목마다 -0.09 + Q·(x - 최적)² (최대 +0.045) — 이득 크기는 예전(숨은 정답과의 거리)과 같다.
## 마모(SETUP_WEAR)는 결승에서만 아파서 예선 최적(빠름)과 결승 최적(타이어)이 갈린다. 엔지니어 추천은 결승 쪽 타협안.
## 드라이버 취향(숨은 선호)은 속도가 아니라 실수에만: 맞으면 실수↓. 서스펜션은 공기압과 엮인다(높은 공기압 = 더 단단한 스프링).
const SETUP_RANGE := {"susp": [1.0, 10.0], "bbias": [52.0, 62.0], "diff": [20.0, 80.0]}
const SETUP_KO := {"wing": "윙", "susp": "서스펜션", "bbias": "브레이크 밸런스", "diff": "디퍼렌셜"}
const SETUP_K := 0.09
const SETUP_Q := 0.25
const SETUP_CH := {
	"susp": [["fast", -0.40], ["kerb", 0.40]],   # 단단하게: 고속 코너 안정 / 연석·요철에서 튐
	"bbias": [["brake", -0.40], ["slow", 0.40]], # 앞으로: 직선 끝 강한 브레이킹 안정 / 저속 코너에서 안 돌아감
	"diff": [["trac", -0.40], ["fast", 0.40]],   # 잠그게: 저속 탈출 트랙션 / 고속 코너 진입·중간 회전 부족
}
const SETUP_WEAR := {"susp": 0.08, "bbias": 0.0, "diff": 0.06} # x = +1 이면 마모 +8% (단단할수록·잠글수록)
const CH_KO := {"fast": "고속 코너", "kerb": "연석·요철", "brake": "브레이킹", "slow": "저속 코너", "trac": "탈출 트랙션"}
const PSI_SUSP := 0.25 # 공기압이 최적보다 1칸 높으면 서스펜션 +0.25 만큼 단단한 느낌
var _sw: Dictionary = {}
var _sw_raw: Dictionary = {}
const SETUP_RAW_MEAN := {"fast": 0.666, "kerb": 1.295, "brake": 0.918, "slow": 1.383, "trac": 1.339} # 전 서킷(F1·WEC 29곳) 평균 — 보통 서킷 = 가운데


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


## 서킷 채널 비중 (항목마다 두 갈래 합 = 1): 공력 코너 wA · 연석 wC · 직선 wE · 섹터 속도로 본 저속 비율
func setup_w() -> Dictionary:
	if not _sw.is_empty() and _sw.get("circ", "") == circ_key:
		return _sw
	var sl := 0.5
	if sec_slow.size() == NS:
		sl = 0.0
		for i in NS:
			sl += float(T.share[i]) * float(sec_slow[i])
	# 공력(wA)과 연석(wC)은 서킷끼리 같이 움직이는 편이라(모나코는 둘 다 큼) 섹터 속도로 고속/저속을 나눠 준다
	var raw := {"fast": float(CIRC.get("wA", 0.045)) / 0.045 * (1.3 - sl), "kerb": float(CIRC.get("wC", 0.045)) / 0.045 * (0.7 + sl), "brake": float(CIRC.get("wE", 0.04)) / 0.045, "slow": (0.6 + sl) * 1.1}
	var bump: float = circ_traits()["bump"] # 요철·연석 많은 시가지(모나코·싱가포르)는 부드럽게
	raw["fast"] = float(raw["fast"]) * (1.0 - 0.3 * bump)
	raw["kerb"] = float(raw["kerb"]) * (1.0 + 0.3 * bump)
	raw["trac"] = (raw["slow"] + raw["kerb"]) * 0.5
	_sw_raw = raw.duplicate()
	for ch in SETUP_RAW_MEAN:
		raw[ch] = float(raw[ch]) / float(SETUP_RAW_MEAN[ch]) # 서킷 전체 평균 = 1 → 보통 서킷은 가운데가 맞음
	var out := {"circ": circ_key}
	for k in SETUP_CH:
		var a: Array = SETUP_CH[k][0]
		var b: Array = SETUP_CH[k][1]
		# 대비를 키운다(4제곱): 두 갈래 비중이 58:42 면 78:22 — 서킷 성격이 최적점을 분명히 움직이게
		var pa: float = pow(maxf(0.01, float(raw[a[0]])), 4.0)
		var pb: float = pow(maxf(0.01, float(raw[b[0]])), 4.0)
		out[k] = {a[0]: pa / (pa + pb), b[0]: pb / (pa + pb)}
	_sw = out
	return out


static func setup_x(k: String, v: float) -> float:
	var r: Array = SETUP_RANGE[k]
	return (v - (float(r[0]) + float(r[1])) * 0.5) / ((float(r[1]) - float(r[0])) * 0.5)


static func setup_v(k: String, x: float) -> float:
	var r: Array = SETUP_RANGE[k]
	return clampf((float(r[0]) + float(r[1])) * 0.5 + x * (float(r[1]) - float(r[0])) * 0.5, float(r[0]), float(r[1]))


## 서킷 채널로 정해지는 기울기 (초/랩 per x)
func _setup_slope(k: String) -> float:
	var w: Dictionary = setup_w()[k]
	var l := 0.0
	for ch in SETUP_CH[k]:
		l += float(ch[1]) * float(w[ch[0]])
	return l


## 최적값 (슬라이더 단위). race = 결승 쪽 타협(마모 고려). 드라이버 감각 차이만큼 조금 치우침(서킷·드라이버마다 고정)
func setup_opt(c, race: bool = false) -> Dictionary:
	var o := {}
	for k in SETUP_RANGE:
		var x: float = -_setup_slope(k) / (2.0 * SETUP_Q) + (_h01(circ_key + "|" + c.name + k) - 0.5) * 0.2
		if race:
			x -= float(SETUP_WEAR[k]) * 1.5 # 마모 +8% ≈ 스틴트 평균 랩당 약 0.1초어치
		o[k] = setup_v(k, clampf(x, -0.9, 0.9))
	return o


## 드라이버 취향 (x 단위, 숨은 값): 맞을수록 실수가 적다 — 속도와는 무관
func setup_pref(c) -> Dictionary:
	if c.setup_opt.has("pref") and c.setup_opt.get("who", "") == c.name:
		return c.setup_opt["pref"]
	var pr := {}
	for k in SETUP_RANGE:
		pr[k] = (_h01(c.name + "|pref|" + k) - 0.5) * 1.2
	c.setup_opt = {"pref": pr, "who": c.name}
	return pr


## 항목별 효과 x (서스펜션은 공기압만큼 단단함이 더해짐). kind = 공기압 상황 ("q" 연습·예선 / "live" 레이스)
func setup_xs(c, kind: String = "live") -> Dictionary:
	var xs := {}
	for k in SETUP_RANGE:
		xs[k] = setup_x(k, float(c.get(k)))
	xs["susp"] = float(xs["susp"]) + PSI_SUSP * press_u(c, kind)
	return xs


## 항목별 정규화 오차 (효과 x - 예선 최적 x) / 2 = 범위 대비. 부호: + = 값이 최적보다 큼 (드라이버 피드백용)
func setup_err(c, kind: String = "live") -> Dictionary:
	var o := setup_opt(c)
	var xs := setup_xs(c, kind)
	var out := {}
	for k in SETUP_RANGE:
		out[k] = (float(xs[k]) - setup_x(k, float(o[k]))) * 0.5
	return out


## {dt: 초/랩, wear: 배율, err: 실수 배율}
func setup_extra(c, kind: String = "live") -> Dictionary:
	var o := setup_opt(c)
	var xs := setup_xs(c, kind)
	var pr := setup_pref(c)
	var dt := 0.0
	var wear := 1.0
	var miss := 0.0
	for k in SETUP_RANGE:
		var x: float = xs[k]
		var d: float = x - setup_x(k, float(o[k]))
		dt += -SETUP_K + minf(SETUP_K * 1.5, SETUP_Q * d * d)
		wear *= 1.0 + float(SETUP_WEAR[k]) * clampf(x, -1.0, 1.0)
		miss += absf(clampf(x, -1.0, 1.0) - float(pr[k]))
	# 브레이크를 뒤로 보낼수록 잠김 실수↑ (최적과 무관한 물리), 드라이버 취향에서 멀수록 실수↑
	var err: float = (1.0 - 0.125 * setup_x("bbias", c.bbias)) * (0.88 + 0.3 * miss / 3.0)
	return {"dt": dt * (1.0 - 0.5 * wet) * wsc(), "wear": wear, "err": maxf(0.7, err)}


## 화면용: 지금 값이 범위 가운데보다 어디서 얻고 잃는지 [[채널 이름, 초/랩]…], 합계(한계 손해 포함), 마모 %
func setup_channels(c, k: String) -> Dictionary:
	var x: float = setup_x(k, float(c.get(k)))
	var w: Dictionary = setup_w()[k]
	var chs: Array = []
	for ch in SETUP_CH[k]:
		chs.append([CH_KO[ch[0]], x * float(ch[1]) * float(w[ch[0]]) * wsc()])
	var o: float = setup_x(k, float(setup_opt(c)[k]))
	var tot: float = (minf(SETUP_K * 1.5, SETUP_Q * (x - o) * (x - o)) - minf(SETUP_K * 1.5, SETUP_Q * o * o)) * wsc()
	return {"ch": chs, "tot": tot, "wear": float(SETUP_WEAR[k]) * x * 100.0}


## 드라이버 피드백: 가장 많이 벗어난 항목의 방향을 말해 준다
func setup_tip(c, kind: String = "live") -> String:
	var e := setup_err(c, kind)
	var worst := ""
	var wv := 0.0
	for k in e:
		if absf(float(e[k])) > absf(wv):
			wv = float(e[k])
			worst = k
	if absf(wv) < 0.05:
		return "세부 셋업은 거의 완벽해요" + _pref_tip(c)
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


## 드라이버 취향과 많이 다른 항목 한 마디 (속도는 그대로, 실수만 늘어남)
func _pref_tip(c) -> String:
	var pr := setup_pref(c)
	var worst := ""
	var wv := 0.0
	for k in SETUP_RANGE:
		var d: float = setup_x(k, float(c.get(k))) - float(pr[k])
		if absf(d) > absf(wv):
			wv = d
			worst = k
	if absf(wv) < 0.7:
		return ""
	return ". 그런데 %s가 제 스타일보다 %s 편이라 실수가 날 것 같아요" % [SETUP_KO[worst], "높은" if wv > 0.0 else "낮은"]


## 엔지니어 실력(q 0~1)만큼 결승 쪽 타협안 근처로 맞춘 셋업 (AI 팀, 주말 없이 바로 레이스할 때 내 차)
func engineer_setup(c, q: float) -> void:
	var o := setup_opt(c, true)
	var sd: float = 0.04 + 0.16 * (1.0 - clampf(q, 0.0, 1.0))
	for k in SETUP_RANGE:
		var r: Array = SETUP_RANGE[k]
		var span: float = float(r[1]) - float(r[0])
		c.set(k, clampf(float(o[k]) + gauss(sd) * span, float(r[0]), float(r[1])))


## 공기압 직선 효과 (초/랩): 높으면 구름 저항이 줄어 직선이 빠르다 — 직선 비중 큰 서킷일수록
func press_straight(u: float) -> float:
	var k: float = float(CIRC["wE"]) / 0.05 if CIRC.has("wE") else (1.3 if float(CIRC["wingOpt"]) <= 2.0 else 0.9)
	return float(press_fx(u)[6]) * k * wsc()


## 공기압 연석 실수 배율: 높으면 튀고 낮으면 잘 먹는다 — 연석 많은 서킷일수록
func press_kerb(u: float) -> float:
	var k: float = press_fx(u)[5]
	return 1.0 + (k - 1.0) * (float(CIRC["wC"]) / 0.045 if CIRC.has("wC") else 1.0)


## 노면 온도·최적 공기압 정하기 (레이스마다). 최적 주행 공기압 = 최소 + 서킷 보통 온도에서 오르는 양 + 숨은 치우침
## → 오늘이 더우면 최적 출발 공기압이 최소 아래로 내려가 '최소 + 과열 감수'(현실 F1), 서늘하면 최소보다 높게 넣어야 창에 들어온다
func _init_tyre_press() -> void:
	psi_min = float(CIRC.get("psiMin", 21.0 if is_wec() else 23.0))
	var t0: float = float(CIRC.get("trackT", 35.0))
	track_t = t0 + gauss(5.0)
	psi_hot_opt = psi_min + press_rise("race", t0) + uni(-0.6, 0.8)
	psi_eng_err = gauss(0.4)
	track_now = track_temp_at(0.0) - WET_COOL * wet


## 노면 온도 (°C), p = 레이스 진행(0~1). WEC 는 낮에도 시각 따라(오후 2시 반 최고 · 아침 최저, ±DAY_AMP),
## 서킷 현지 시각 "HH:MM" (출발 시각 startH 가 있는 WEC 만, 없으면 ""). 시간제는 레이스 시계로 계속 흐름
## (선두 랩 기준이면 르망은 한 랩 = 약 24분씩 뚝뚝 넘어감), 랩 수 레이스는 선두 랩 진행률
func local_clock() -> String:
	if not is_wec() or not CIRC.has("startH"):
		return ""
	var p: float = clampf(clock / time_limit, 0.0, 1.0) if (timed and time_limit > 0.0) else float(leader_lap) / maxf(1.0, float(laps))
	var h: float = fposmod(float(CIRC["startH"]) + p * wec_hours(), 24.0)
	return "%02d:%02d" % [int(h), int(fmod(h, 1.0) * 60.0)]


## 밤이 있는 서킷은 해가 지면 nightDrop 만큼 식고 해질녘·새벽(진행 6% 구간)에 서서히 바뀐다. 비는 따로(track_now 에서 젖음만큼)
func track_temp_at(p: float) -> float:
	var day: float = track_t
	if is_wec() and CIRC.has("startH"):
		var h: float = float(CIRC["startH"]) + p * wec_hours()
		day += DAY_AMP * (cos((h - 14.5) / 24.0 * TAU) - 0.5)
	var nt = CIRC.get("night")
	if nt == null:
		return day
	var n0: float = float(nt[0])
	var n1: float = float(nt[1])
	var f := 1.0
	if n0 > 0.0:
		f = clampf((p - n0 + 0.03) / 0.06, 0.0, 1.0)
	if n1 < 1.0:
		f *= 1.0 - clampf((p - n1 + 0.03) / 0.06, 0.0, 1.0)
	return lerpf(day, track_t - float(CIRC.get("nightDrop", DB.wec.get("nightDrop", 14.0))), f)


## 이 서킷에서 kph 이상으로 달리는 거리 비율 (0~1) — LMH 사륜이 작동하는 구간.
## 서킷 데이터 fast190(190km/h 이상 비율)에서 속도 기준에 비례해 늘리고 줄임
# shortcut: fast190 은 서킷 길이·최고 속도로 어림한 값(텔레메트리 아님), 트랙 그림의 상대 속도(T.spd)는 서킷마다 축척이 달라 못 씀
func awd_share(kph: float) -> float:
	var f: float = float(CIRC.get("fast190", 0.45))
	return clampf(f * (HY_VMAX - kph) / (HY_VMAX - 190.0), 0.0, 1.0)


## 컴파운드 노면 온도 창 [낮음, 높음] °C (data/wec.json tyreWin — 미쉐린 하이퍼카)
func tyre_win(k: String) -> Array:
	return DB.wec.get("tyreWin", {}).get(k, [-99.0, 99.0])


## 온도 창 밖 정도 (°C): + 뜨거움 · − 차가움 · 0 = 창 안. 하이퍼카 슬릭만 (LMGT3·LMP2 는 한 종류라 해당 없음)
func win_off(cls: String, k: String, temp: float) -> float:
	if not is_wec() or cls != "HY" or not SLICK.has(k):
		return 0.0
	var w: Array = tyre_win(k)
	if temp > float(w[1]):
		return temp - float(w[1])
	if temp < float(w[0]):
		return temp - float(w[0])
	return 0.0


## 온도 창 밖이면 타이어 온도 목표를 얼마나 옮기나 (+ 과열 쪽 · − 저온 쪽)
func win_tt(cls: String, k: String, temp: float) -> float:
	var o: float = win_off(cls, k, temp)
	if o == 0.0:
		return 0.0
	return signf(o) * (WIN_BASE + WIN_K * absf(o))


## WEC 컴파운드 고르기: 새 타이어로 달릴 n 랩 동안 예상 노면 온도(구간 가운데)로 각 컴파운드의 시간을 어림해 가장 빠른 것.
## 팀 전략 능력만큼 온도를 잘못 읽고, 공격형은 무른 쪽·아끼는 팀은 단단한 쪽으로 조금 치우친다. 플레이어 자동 박스·피트 탭 표시도 같은 식
func wec_pick_comp(c, n: int, noisy: bool = true) -> String:
	var al: Array = wec_comps(c.cls)
	if al.size() == 1:
		return String(al[0])
	n = maxi(1, n)
	var real_t: float = run_temp(n)
	var temp: float = real_t + (gauss(maxf(0.5, (1.0 - c.strategy) * 10.0)) if noisy else 0.0)
	var best := String(al[0])
	var best_t := INF
	var tl: PackedStringArray = []
	for k in al:
		var t: float = comp_run_time(c, String(k), n, temp)
		if c.wec_style == "push" and k == "S":
			t -= 0.1 * wsc() * n
		elif c.wec_style == "save" and k == "H":
			t -= 0.1 * wsc() * n
		tl.append("%s %.0f" % [k, t])
		if t < best_t:
			best_t = t
			best = String(k)
	# shortcut: 수정 25 진단 — 폰에서만 AI 타이어가 섞이는 원인 확인용. 출발(0랩)은 전부, 그 뒤는 하드를 고르거나 온도를 3°C 넘게 잘못 읽었을 때만. 원인 확정 후 지움
	if noisy and not c.mine and (leader_lap == 0 or best == "H" or absf(temp - real_t) > 3.0):
		BLog.add("타이어 L%d %s → %s (읽음 %.0f° 실제 %.0f° · %d랩 · %s · %s)" % [leader_lap, name_of(c), best, temp, real_t, n, " ".join(tl), c.wec_style])
	return best


## 새 세트 하나가 모자라면 잃는 시간 (수정 32): 그 스틴트를 더블 스틴트 끝(보관 세트 마모)부터 한 번 더 탄 시간 − 새 세트로 탄 시간.
## 예전엔 고정값 SET_VAL(쓴 세트 약 30% 가정 → 스틴트당 약 3초)이었는데, 실제 보관 세트는 55~65% 라 스틴트당 15~20초 →
## AI 가 출발부터 소프트 싱글을 고르고 세트가 바닥나 마지막을 닳은 세트로 달리던 원인
func set_short_cost(c, k: String, temp: float) -> float:
	var w_used: float = minf(0.85, true_wear_rate(k) * float(CIRC["wear"]) * WEC_WEAR * STINT * 2.0)
	return comp_run_time(c, k, STINT, temp, w_used, HEAT_PEN) - comp_run_time(c, k, STINT, temp)


## AI 새 세트 고르기 (수정 31): 컴파운드 × 이 세트로 탈 스틴트 수(팀 습관 m, 한 스틴트 더 m+1, 최대 3)를 같이 고른다.
## 랩당 비용 = (달리는 시간 + 타이어 교체 시간 + 세트가 모자라면 세트 값) ÷ 랩 → "하드 트리플로 교체·세트 아끼기 vs 미디엄 더블로 빠르게".
## 결과 스틴트 수는 c.set_plan (wec_decision 의 tyre_due), 컴파운드를 돌려준다. 온도 읽기 오차·성향은 wec_pick_comp 와 같다
func wec_pick_set(c, left: int, noisy: bool = true) -> String:
	var al: Array = wec_comps(c.cls)
	var habit: int = maxi(1, c.tyre_every)
	c.set_plan = habit
	if left <= STINT + 1:
		return wec_pick_comp(c, left, noisy) if al.size() > 1 else String(al[0])
	var tyre_cost: float = wec_stop_time(c, true, false) - wec_stop_time(c, false, false)
	# 세트 사정: 이 세트로 m 스틴트 탄 뒤 남은 스틴트를 더블로 채울 새 세트가 모자라면, 모자란 세트마다
	# 쓴 세트를 다시 끼거나 스틴트를 늘려 잃는 시간(set_short_cost) — 세트가 빠듯한 르망에서 싱글 스틴트를 남발하지 않게
	var spare: int = c.wec_sets - (1 if c.lap > 0 else 0) # 출발 세트는 wec_sets 에 안 들어 있음
	var err: float = gauss(maxf(0.5, (1.0 - c.strategy) * 10.0)) if noisy else 0.0
	var best := String(al[0])
	var best_m := habit
	var best_v := INF
	var tl: PackedStringArray = []
	# 세트가 모자라 한 스틴트를 쓴 세트로 더 탈 때 잃는 시간: 가장 싸게 메우는 컴파운드 기준 (하드 트리플 등)
	var short_cost := INF
	for k2 in al:
		short_cost = minf(short_cost, set_short_cost(c, String(k2), run_temp(STINT) + err))
	# 마지막 새 세트면 이 세트로 끝까지 가야 한다 (수정 32): 예전엔 1~2 스틴트로만 따져서 남은 11~12랩을 소프트로 버티다 100% 까지 닳음
	var last_set: bool = spare <= 0
	var opts: Array = [int(ceil(float(left) / STINT))] if last_set else [habit, habit + 1]
	for m in opts:
		if m > 3 and not last_set:
			continue
		var n: int = left if last_set else mini(left, m * STINT)
		var fin: bool = n >= left
		var real_t: float = run_temp(n)
		for k in al:
			var t: float = comp_run_time(c, String(k), n, real_t + err)
			if c.wec_style == "push" and k == "S":
				t -= 0.1 * wsc() * n
			elif c.wec_style == "save" and k == "H":
				t -= 0.1 * wsc() * n
			# 남은 세트를 더블로 써도 못 채우는 랩 (랩 단위 — 스틴트로 올림하면 1랩 모자라도 세트 하나로 셈)
			var short_st: float = maxf(0.0, float(left - n - spare * 2 * STINT)) / STINT
			var v: float = (t + (0.0 if fin else tyre_cost + short_st * short_cost)) / n
			tl.append("%s%d %.2f" % [k, m, v])
			if v < best_v:
				best_v = v
				best = String(k)
				best_m = m
	c.set_plan = best_m
	if best_m > habit:
		_tally("세트 스틴트 늘림 %s" % best)
	if noisy and not c.mine and (leader_lap == 0 or best == "H" or absf(err) > 3.0):
		BLog.add("타이어 L%d %s → %s×%d (오차 %+.0f° · %s · %s)" % [leader_lap, name_of(c), best, best_m, err, " ".join(tl), c.wec_style]) # shortcut: 수정 25 진단
	return best


## 지금부터 n 랩 구간 가운데의 예상 노면 온도 (°C). 젖은 노면은 차가워서, 지금 젖음이 그때까지 마른다고 보고(랩당 ×0.85) 그만큼 뺀다
func run_temp(n: int) -> float:
	var p_mid: float = (float(leader_lap) + n * 0.5) / maxf(1.0, float(laps))
	return track_temp_at(p_mid) - WET_COOL * wet * pow(0.85, n * 0.5)


## 컴파운드 k 로 노면 temp°C 에서 n 랩 달리는 시간 어림 (초, 기준 대비): 속도 + 마모 손해 + 절벽 + 온도 창 밖 손해
func comp_run_time(c, k: String, n: int, temp: float, w0: float = 0.0, heat: float = 0.0) -> float:
	var ws: float = wsc()
	var ttg: float = float(PACE[c.pace][3]) + win_tt(c.cls, k, temp)
	var hot: float = maxf(0.0, ttg - 0.80)
	var cold: float = maxf(0.0, 0.42 - ttg)
	var r: float = true_wear_rate(k) * float(CIRC["wear"]) * WEC_WEAR * (1.0 + hot * 5.0)
	var t := 0.0
	var w := w0
	for i in n:
		t += (float(cpv(k)[0]) + heat + w * w * float(cpv(k)[2]) + cliff_pen(k, w) + cold * 4.0 + hot * 3.0) * ws
		w += r
	return t


## 달리면서 오르는 공기압 (psi). F1 은 워머(70°C)로 데운 뒤 재는 출발 공기압이라 조금, WEC 는 워머 금지라 차가운 데서 많이.
## kind: "q" 짧은 런(예선·셋업 테스트) / "race" 긴 런 평균. 실제 피렐리 '예상 주행 공기압' = 출발 + 약 0.5~2.5 psi
func press_rise(kind: String, temp: float = -999.0) -> float:
	var tc: float = track_t if temp < -900.0 else temp
	var r: float = (3.0 + 0.07 * (tc - 30.0)) if is_wec() else (1.6 + 0.05 * (tc - 35.0))
	return maxf(0.4, r) * (0.6 if kind == "q" else 1.0)


## 그 런에 딱 맞는 출발 공기압 (최소 아래로는 못 내림)
func psi_rec(kind: String) -> float:
	return maxf(psi_min, psi_hot_opt - press_rise(kind))


func psi_snap(v: float) -> float:
	return clampf(snappedf(v, 0.5), psi_min, psi_min + PSI_SPAN)


## 저장된 셋업의 공기압. 예전 저장(낮게/표준/높게)은 엔지니어 추천 ±1.5 psi 로
func setup_psi(su: Dictionary) -> float:
	if su.has("psi"):
		return psi_snap(float(su["psi"]))
	var old: float = {"low": -1.5, "high": 1.5}.get(String(su.get("press", "std")), 0.0)
	return psi_snap(psi_rec("race") + psi_eng_err + old)


## 데워진 공기압이 최적에서 벗어난 정도 (칸, + = 높음). kind: "q" / "race" / "live"(레이스 중: 타이어 온도만큼 오름)
## AI 는 예선 때 예선용으로 다시 맞춘다 (내 차는 플레이어가 연습·출발 화면에서 직접)
func press_u(c, kind: String = "race") -> float:
	if c.psi <= 0.0: # 예전 중간 저장
		c.psi = psi_snap(psi_rec("race"))
	var p: float = c.psi
	if kind == "q" and not c.mine:
		p = psi_snap(p + psi_rec("q") - psi_rec("race"))
	var r: float = press_rise("q" if kind == "q" else "race")
	if kind == "live":
		r *= clampf(c.tt / 0.69, 0.4, 1.4) # 0.69 = 그린 레이스 중 평균 타이어 온도 (측정) → 평균적으로 결승 추천값 그대로
	return clampf((p + r - psi_hot_opt) / PSI_U, -2.5, 2.5)


## 공기압 효과 [랩타임 +초, 마모 ×, 온도 목표 +, 예열 ×, 과열 손해 ×, 연석 원값 ×, 직선 원값 초]
## 창 안이 그립 최고. 높으면: 접지 좁아짐 · 과열·가운데 마모 · 연석에서 튐 / 직선 조금 빠름.
## 낮으면: 미끄럼 · 잘 안 데워짐 · 어깨 마모 / 연석은 잘 먹음. 어느 쪽도 공짜 아님
static func press_fx(u: float) -> Array:
	var o: float = maxf(u, 0.0)
	var d: float = maxf(-u, 0.0)
	return [0.18 * u * u, 1.0 + 0.10 * o + 0.05 * d, 0.04 * o, maxf(0.4, 1.0 - 0.30 * d), 1.0 + 0.35 * o, 1.0 + 0.28 * o - 0.15 * d, -0.11 * u]


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
func wec_stop_time(c, tyres: bool, driver: bool, fuel: bool = true, fill: float = 1.0) -> float:
	var lane_loss: float = float(CIRC.get("wecLaneLoss", WPIT["lane"])) * maxf(0.52, pit_scale())
	var add: float = fuel_add(c, fill) if fuel else 0.0
	var fuel_work: float = WPIT["fuel"] * (1.05 - 0.2 * c.crew) * (FUEL_FIX + (1.0 - FUEL_FIX) * minf(1.25, add / (TANK * FUEL_REF))) if add > 0.0 else 0.0
	var tyre_work: float = WPIT["tyres"] * (1.15 - 0.35 * c.crew) if tyres else 0.0
	var drv_work: float = WPIT["driver"] if driver else 0.0
	# 규정: 급유 중엔 타이어를 못 바꾼다(급유 → 타이어 순서로 합산). 드라이버 교대는 급유하는 동안 같이 할 수 있다
	var work: float = (maxf(fuel_work, drv_work) + tyre_work) * maxf(0.32, pit_scale())
	var scf := 1.0
	if sc and not _force_green:
		scf = 0.62 if sc_kind == "SC" else 0.78
	return (lane_loss + work) * scf


func fuel_k() -> float:
	return FUEL_K_WEC if is_wec() else 0.03


## 이번 피트에서 넣을 연료 (목표 = 탱크 × fill, 이미 그보다 많으면 0)
func fuel_add(c, fill: float) -> float:
	return maxf(0.0, TANK * clampf(fill, 0.0, 1.0) - maxf(0.0, c.fuel))


## 이 차가 체커까지 더 돌 랩 (피트 아웃 랩 포함). 시간제는 남은 시간 ÷ 내 랩타임 + 체커 랩 1
func laps_to_go(c) -> float:
	if timed and not time_up:
		var lt: float = lap_base(c) * TIME_K
		return maxf(1.0, (time_limit - clock) / maxf(1.0, lt) + 1.0)
	return maxf(1.0, float(laps - c.lap))


## 완주에 필요한 만큼만 넣는 목표(탱크 대비). margin = 여유 랩
func fill_to_finish(c, margin: float = 0.4) -> float:
	return clampf((laps_to_go(c) + margin) * _wec_burn(c, c.fuel_mode) / TANK, 0.05, 1.0)


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
	var w: float = sec_w(c.sec) # 이 섹터 레이싱 라인 노면
	var base = float(CIRC["base"])
	var pc: Array = PACE[c.pace]
	var spd: float = pc[0]
	var wear_m: float = pc[1]
	var err_m: float = pc[2]
	var tt_target: float = pc[3]
	var t = base * sh * car_factor(c) * (1.0 - c.speed * K["drv_k"] * spd)
	var evo_bonus = -0.65 * track_evo * (1.0 - w)
	var ws := wsc()
	t += (float(cpv(c.comp)[0]) + c.used_set_pen + c.wear * c.wear * float(cpv(c.comp)[2]) + cliff_pen(c.comp, c.wear) + c.fuel * fuel_k() + evo_bonus) * sh * ws
	t += setup_sec(c, c.sec, w)
	var sx: Dictionary = setup_extra(c)
	t += float(sx["dt"]) * sh
	if is_yellow(c.sec):
		t += 0.45 * sh * ws # 옐로 구간 감속
	if c.lamp_out and night:
		t *= 1.05 # 헤드라이트 없이 밤 주행
	if c.limp > 0.0:
		t *= 1.0 + c.limp # 손상 후 피트까지 감속
	if c.fault != null:
		t += float(c.fault["dt"]) * sh # 반쯤 고장
	# 드라이버 특성
	if not c.traits.is_empty():
		if c.traits.has("saver") and c.stint_laps < 2:
			t += 0.12 * sh * ws # 타이어를 아끼느라 스틴트 초반 조심
		if c.traits.has("rain") and w > 0.3:
			t -= 0.25 * w * sh * ws
		if c.traits.has("closer") and laps > 0 and float(c.lap) >= float(laps) * 0.85:
			t -= 0.12 * sh * ws
	# 지시는 조건이 맞을 때만 효과·대가가 함께 붙는다 (공짜 선택 없음): 추월 = 앞차 1초 안, 유지 = 앞차 1.5초 안
	var att_on: bool = c.instr == "attack" and gap_ahead != null and gap_ahead < 1.0
	var hold_on: bool = c.instr == "hold" and gap_ahead != null and gap_ahead < 1.5
	var wp = weather_pen(c.comp, w)
	# LMH 사륜(앞바퀴 모터): 젖은 노면에서 그 속도를 넘는 구간의 트랙션 손해가 줄어든다. 마른 노면은 BoP 로 같게
	var grip_loss: float = (w * 6.0 + w * (0.8 - c.wet) * 4.0) * ((1.0 - AWD_WET * awd_share(c.awd_kph)) if c.awd_kph > 0.0 else 1.0)
	t += (wp + grip_loss) * sh * ws
	var dirty_f := 0.0 # 더티 에어 세기 0~1 (앞차 1초 안, 가까울수록 큼): 다운포스를 잃어 미끄러짐 → 타이어 온도·마모↑
	if not is_wec():
		if gap_ahead != null and gap_ahead < K["dirty"]:
			if c.instr == "hold":
				t += (K["dirty"] - gap_ahead) * 0.6 * sh # 유지: 더티 에어를 피해 1초 간격까지 물러나는 만큼 손해
			else:
				dirty_f = clampf(1.0 - gap_ahead, 0.0, 1.0) * float(CIRC["wA"]) / 0.06
				t += (0.2 + 0.3 * float(CIRC["wA"]) / 0.06 + 0.3 * w) * (1.0 - gap_ahead) * sh
		if has_ers():
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
		if wave_clear_lap >= 0 and c.lap + 1 == wave_clear_lap:
			lam_slow = 0.0 # 웨이브 바이로 리스타트 랩 앞이 깨끗하다
		for i in poisson(lam_slow * sh):
			t += uni(0.3, 1.6) * (1.3 - c.cons) * (1.4 if night else 1.0) * (1.0 + w)
			if rnd() < 0.0005 * (1.0 + c.aggr) * (1.5 if night else 1.0) * (1.0 + fatigue(c)):
				c.damage_now = "느린 클래스 차량과 접촉"
				_traffic_victim(c)
				break
		for i in poisson(lam_fast * sh):
			t += uni(0.15, 0.6)
	# 타이어 온도
	var pu: float = press_u(c, "live")
	var pf: Array = press_fx(pu)
	var target = tt_target + (0.05 if att_on else 0.0) + DIRTY_TT * dirty_f + (0.02 if (c.ers_mode == "deploy" and has_ers()) else 0.0) + float(pf[2]) - (0.05 if night else 0.0) + win_tt(c.cls, c.comp, track_now)
	if SLICK.has(c.comp) and w > 0.25:
		target -= 0.25
	if not SLICK.has(c.comp) and w < 0.2:
		target += 0.3
	c.tt = clampf(c.tt + (target - c.tt) * minf(0.9, 0.35 * float(pf[3])), 0.0, 1.0)
	var cold = maxf(0.0, 0.42 - c.tt)
	var hot = maxf(0.0, c.tt - 0.80)
	t += (cold * 4.0 + hot * 3.0 * float(pf[4])) * sh * ws
	var fat: float = (maxf(0.0, c.stint_drv - 1) * 0.04 + fatigue(c) * 0.3) if is_wec() else 0.0
	var cons: float = c.cons - fat - (0.08 if night else 0.0)
	var is_launch: bool = c.lap == 0 and c.sec == 0
	var noise_scale = 0.18 if is_launch else 1.0
	t += gauss((K["noise"] - cons * 0.4 + 0.3 * w) * sqrt(sh) * noise_scale * sqrt(ws))
	var pressure = 1.5 if (not is_launch and gap_ahead != null and gap_ahead < 0.5) else 1.0
	var p_err = 0.0
	if not is_launch:
		p_err = 0.036 * sh * err_m * press_kerb(pu) * pressure * (1.2 - cons) * (1.0 + 3.0 * w * (1.3 - c.wet) * (0.7 if c.traits.has("rain") else 1.0)) * (1.0 + wp / 5.0) * (1.5 if is_restart else 1.0) * (1.0 + cold * 5.0) * (1.2 if att_on else 1.0) * ((1.15 if c.traits.has("night") else 1.5) if night else 1.0) * (1.5 if c.drivers[c.drv].get("grade", "") == "B" else 1.0) * float(sx["err"])
	# 트랙 리밋: 연석 공략이 과하면 경고, 세 번째부터 5초 페널티 (F1, 그린 상황에서만)
	if not is_wec() and not sc and not is_launch and rnd() < 0.012 * sh * err_m * (0.6 + c.aggr) * press_kerb(pu) * (1.3 if att_on else 1.0) * (1.0 + maxf(0.0, c.susp - 7.0) * 0.08):
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
	var lift_wear = 0.80 if c.instr == "lift" else (0.92 if hold_on else 1.0)
	var lift_fuel = 0.86 if c.instr == "lift" else 1.0
	# 연료 무게: 탱크가 가득한 초반엔 타이어가 더 닳고(×1.08) 가벼워질수록 덜 닳는다(×0.92). 레이스 평균은 거의 ×1.0
	var fuel_full: float = TANK if is_wec() else laps * FPL
	var fuel_wear: float = 0.92 + 0.16 * clampf(c.fuel / maxf(1.0, fuel_full), 0.0, 1.0)
	c.wear = minf(1.0, c.wear + wear_rate * wear_m * over * fuel_wear * (1.0 + hot * 5.0 * float(pf[4])) * lift_wear * (1.0 + DIRTY_WEAR * dirty_f) * float(pf[1]) * (1.0 - (c.wing - 3.0) * 0.04) * c.tyre_deg_rate * (0.85 if night else 1.0) * float(sx["wear"]) * sh)
	if is_wec():
		c.fuel -= FPL * sh * wec_fuel_mult(c) * lift_fuel
	else:
		c.fuel -= FPL * sh * float(fm[1]) * c.fuel_burn_rate * lift_fuel * (2.0 - c.eng_eff) * float(PACE_FUEL[c.pace])
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


## 리타이어 자세한 사유: 어디서(코너·섹터) · 어떻게 · 그때 상황(랩·타이어·노면)
func _dnf_detail(c, why: String) -> String:
	var where := "S%d" % (c.sec + 1)
	var labels: Array = T.C.get("labels", [])
	if not labels.is_empty():
		var my_d: float = fposmod(car_dist(c), T.L)
		var best := INF
		for lb in labels:
			var si: int = (int(lb[0]) * T.SPC) % T.m
			var ld: float = float(T.cum[si])
			var dd: float = absf(wrapf(ld - my_d, -T.L * 0.5, T.L * 0.5))
			if dd < best and dd < T.L * 0.12:
				best = dd
				where = "%s 부근" % String(lb[1])
	var how := why
	match why:
		"스핀":
			how = "스핀 후 방호벽에 부딪힘"
			if wet > 0.3:
				how += " (젖은 노면, 수막 %.1fmm)" % wet_mm(wet)
			elif c.tt < 0.3:
				how += " (타이어가 식어 그립 부족)"
		"충돌":
			how = ("%s 와(과) 경합 중 접촉해 손상" % c.crash_with) if c.crash_with != "" else "경합 중 접촉해 손상"
		"고장":
			var kinds := ["엔진", "기어박스", "유압 계통", "전기 계통", "냉각 계통", "서스펜션", "브레이크"]
			if c.mech_trouble.find("브레이크") >= 0:
				how = "브레이크 과열로 고장"
			elif c.mech_trouble.find("기어박스") >= 0:
				how = "기어박스 유압 문제로 고장"
			else:
				how = "%s 고장" % kinds[rng.randi_range(0, kinds.size() - 1)]
	var tyre: String = "%s %d%%" % [TYRE_KO.get(c.comp, c.comp), int(round(c.wear * 100))] if SLICK.has(c.comp) else TYRE_KO.get(c.comp, c.comp)
	return "%s · %s · L%d · 타이어 %s" % [where, how, c.lap + 1, tyre]


func retire(c, why: String) -> void:
	if c.mine or (c.started and class_pos(c) <= 5):
		BLog.add("리타이어 %s%s 클래스 P%d 랩%d · %s" % [name_of(c), " (내 차)" if c.mine else "", class_pos(c), c.lap + 1, why])
	c.dnf_detail = _dnf_detail(c, why)
	c.dnf = why
	c.boxing = null
	c.pit_phase = 0
	c.pit_req = ""
	c.pending_crash = ""
	c.pending_victim = false
	c.sec_end = INF
	var tag := ""
	if is_wec():
		tag = "[%s] " % CLS_TAG.get(c.cls, c.cls)
	event("%s%s 리타이어 — %s" % [tag, name_of(c), c.dnf_detail], "bad")
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
			# 피트 입구 부근(마지막 섹터) 사고면 SC 직후 1랩 피트레인 폐쇄 (F1)
			if not is_wec() and c.sec >= NS - 1:
				pit_closed_until = leader_lap + 1
				event("⛔ 피트 입구 부근 사고 — 피트레인 폐쇄 (L%d 까지). 들어가면 스톱 앤 고 10초" % (leader_lap + 1), "bad")
		elif r < p_sc + p_v:
			deploy("FCY" if is_wec() else "VSC")
		else:
			flag_yellow(c.sec, float(CIRC["base"]) * 0.9, "%s 정지 차량" % name_of(c))


## WEC: 수리 가능한 손상 (60% 개러지 수리, 40% 리타이어)
func damage(c, why: String) -> void:
	# 밤에 접촉하면 헤드라이트만 깨지는 경우: 시야가 나빠 느려지고, 레이스 컨트롤이 2랩 안에 수리를 지시
	if is_wec() and night and not c.lamp_out and why.find("접촉") >= 0 and rnd() < 0.35:
		c.lamp_out = true
		c.lamp_lap = c.lap
		_tally("헤드라이트")
		event("💡 %s 헤드라이트 파손 — 어둠 속 랩타임 급락, 수리 필요" % name_of(c), "bad")
		if c.mine:
			say(c, "헤드라이트가 깨졌어요! 앞이 잘 안 보여요. 2랩 안에 박스해서 고쳐야 해요")
		return
	if rnd() < 0.6:
		var sev: float = uni(1.5, 8.0)
		var lost: float = sev * float(CIRC["base"]) * laps / real_laps()
		c.garage += lost
		c.repairs += 1
		# 부서진 차는 피트까지 절뚝이며 간다: 손상이 클수록(수리 시간이 길수록) 느리게, 피트에서 0
		c.limp = maxf(c.limp, 0.15 + 0.25 * (sev - 1.5) / 6.5)
		event("%s %s → 절뚝이며 피트로, 개러지 수리 (약 %d초 손실)" % [name_of(c), why, int(round(lost))], "bad")
		c.limp_pos = class_pos(c)
		if c.mine or c.limp_pos <= 5:
			BLog.add("손상 %s%s 클래스 P%d 랩%d 섹터%d 수리 %.0f초 감속 +%d%%" % [name_of(c), " (내 차)" if c.mine else "", c.limp_pos, c.lap + 1, c.sec + 1, lost, int(round(c.limp * 100.0))])
		if c.mine:
			say(c, "%s. 차가 망가져서 천천히 피트로 들어가 수리합니다 (랩타임 +%d%%)" % [why, int(round(c.limp * 100.0))])
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
		t += float(cpv(k)[0]) + wm * wm * float(cpv(k)[2]) + cliff_pen(k, wm)
		w += r
	if w > ai_lim(k) + 0.08:
		return t + 30.0 + (w - ai_lim(k)) * 60.0
	return t


func ai_optimize(l: int, start_comp: String, start_wear: float, rates: Dictionary, pit_cost: float, used: Dictionary, sets: Dictionary, max_stops: int) -> Array:
	var C: Array = rules.get("dry", ["S", "M", "H"])
	# 스틴트 비용표 (길이 0~l) — 계산량을 줄이기 위해 미리 만들어 둔다
	# (지금 끼운 타이어가 이번 대회 허용 목록 밖이어도 첫 스틴트는 계산되게 비용표는 세 종류 모두)
	var table = {}
	for k in ["S", "M", "H"]:
		var row = []
		for n in l + 1:
			row.append(ai_stint_cost(k, n, 0.0, rates[k]))
		table[k] = row
	var first_table = {}
	for k in ["S", "M", "H"]:
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
		if ns > 0 and l < 2 * (ns + 1):
			continue # 스틴트마다 최소 2랩이 안 나온다
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
			var best: Array = _best_cuts(seq, ns, l, ns * pit_cost, first_table[seq[0]], table)
			var best_cost: float = best[0]
			var best_cut: Variant = best[1]
			if best_cut != null:
				out.append({"cost": best_cost, "seq": seq, "cuts": best_cut})
	out.sort_custom(func(a, b): return a["cost"] < b["cost"])
	return out


## 컴파운드 순서(seq)가 정해졌을 때 가장 싼 피트 랩 조합 — 동적계획법 (예전 전수조사와 같은 답).
## 스틴트마다 최소 2랩, 앞에서부터 더해 가며(예전과 같은 덧셈 순서) 같은 비용이면 피트 랩이 이른 쪽.
## 돌려주는 값: [비용, 피트 랩 배열 또는 null]
func _best_cuts(seq: Array, ns: int, l: int, base: float, first_row: Array, table: Dictionary) -> Array:
	if ns == 0:
		return [base + float(first_row[l]), []]
	# val[x] = 첫 i+1 스틴트를 x랩에서 끝냈을 때 최소 비용, pre[x] = 그때의 피트 랩들
	var val: Array = []
	var pre: Array = []
	val.resize(l + 1)
	pre.resize(l + 1)
	val.fill(INF)
	for x in range(2, l - 1):
		val[x] = base + float(first_row[x])
		pre[x] = [x]
	for i in range(1, ns):
		var row: Array = table[seq[i]]
		var nv: Array = []
		var np: Array = []
		nv.resize(l + 1)
		np.resize(l + 1)
		nv.fill(INF)
		var lo: int = 2 * (i + 1)
		for y in range(lo, l - 1):
			var bv: float = INF
			var bp: Variant = null
			for x in range(lo - 2, y - 1):
				var v0: float = val[x]
				if v0 == INF:
					continue
				var v: float = v0 + float(row[y - x])
				if v < bv or (v == bv and bp != null and _lex_less(pre[x], bp)):
					bv = v
					bp = pre[x]
			if bp != null:
				nv[y] = bv
				var arr: Array = bp.duplicate()
				arr.append(y)
				np[y] = arr
		val = nv
		pre = np
	var last_row: Array = table[seq[ns]]
	var best_cost: float = INF
	var best_cut: Variant = null
	for x in range(2 * ns, l - 1):
		var v0: float = val[x]
		if v0 == INF:
			continue
		var v: float = v0 + float(last_row[l - x])
		if v < best_cost or (v == best_cost and best_cut != null and _lex_less(pre[x], best_cut)):
			best_cost = v
			best_cut = pre[x]
	return [best_cost, best_cut]


func _lex_less(a: Array, b: Array) -> bool:
	for i in mini(a.size(), b.size()):
		if a[i] != b[i]:
			return a[i] < b[i]
	return a.size() < b.size()


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
	var cands = ai_optimize(laps, fixed_start, c.wear, ai_rates(c, 1.0), stop_cost(), {}, {"S": 1, "M": 2, "H": 1}, max_st)
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
	var cands = ai_optimize(left, c.comp, c.wear, ai_rates(c, scale), stop_cost(), c.used, c.ai_sets, 2)
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
	var dl: Array = dry_list()
	cands = cands.filter(func(x): return dl.has(x))
	if SLICK.has(pref) and dl.has(pref):
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
	for k in dry_list():
		if need_diff and c.used.has(k):
			continue
		var r: float = ai_nom_rate(k, c) * c.est_err
		if rem * r > ai_lim(k) - 0.03:
			continue
		var tt: float = rem * float(cpv(k)[0]) + float(cpv(k)[2]) * r * r * rem * rem * rem / 3.0
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


## 차 c 의 팀 예보로, 지금 타이어 종류(have)가 맞지 않는 랩이 cur 부터 몇 랩 이어지나 (최대 8랩)
func _wrong_laps(c, cur: int, have: String) -> int:
	var n := 0
	for l in range(cur, mini(laps, cur + 8) + 1):
		if ideal_tyre(forecast_wet_at(l, c)) != have:
			n += 1
		else:
			break
	return n


## 피트 판단: 마지막 섹터에 들어설 때(피트 입구 전) 호출. 플레이어 차는 박스 지시가 있을 때만 들어온다.
func pit_decision(c) -> Variant:
	var cur: int = c.lap + 1
	var left: int = laps - cur
	var want = ideal_tyre(wet)
	if left < 1 or c.crew_cooldown > 0:
		return null
	# 반쯤 고장: 남은 계획 정차가 없고 버티는 손해가 더 크면 지금 들어가 고친다 (AI 판단 · 내 차 '지금 박스' 선택)
	if c.fault != null and bool(c.fault["now"]) and c.pit_req == "":
		c.fault["now"] = false
		c.crew_out = true
		if is_wec():
			return {"comp": c.comp, "tyres": false, "driver": false, "fuel": true, "fill": 1.0}
		var fresh_f: String = "H" if left > 7 else ("M" if left > 4 else "S")
		return {"comp": _pick_ai_slick(c, fresh_f, left) if want == "slick" else want, "tyres": true}
	if is_wec():
		return wec_decision(c, cur, left, want)
	if pit_closed() and (c.pit_req == "" or not c.mine):
		return null # 피트레인 폐쇄: AI·자동 피트는 한 랩 기다린다
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
		var lose = wx_pen_track(c.comp) - wx_pen_track(nw)
		var horizon: float = minf(left, uni(2, 9))
		if tact >= 0.7:
			# 예보를 읽는 팀: 자기 팀 예보(오차 포함)로 맞지 않는 타이어로 달릴 랩 수를 센다 (곧 그치거나 마르면 버틴다)
			horizon = minf(float(left), float(_wrong_laps(c, cur, have)) * uni(0.85, 1.15) + 0.5)
		if lose * horizon > pit_loss() * c.nerve:
			c.weather_pit = true
			c.crew_out = true
			return {"comp": nw, "tyres": true}
		return null
	# 예보 선제 대응: 다음 랩에 노면이 바뀌고 어차피 2랩 안에 피트할 계획이면 지금 맞는 타이어로 (스톱 하나 절약)
	if tact >= 0.8 and ns != null and int(ns["lap"]) - cur <= 2 and not sc and left > 2:
		var want_next: String = ideal_tyre(forecast_wet_at(cur + 1, c))
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
			# A-7.4: 확률 대신 계산 — 전략 뷰와 같은 undercut_net(순이득 초)을 팀 감각만큼 오차로 읽고,
			# 복귀 지점이 트래픽(앞차 1초 안)이면 깨끗한 공기가 아니라서 포기
			var un: Variant = undercut_net(c, front) if ok_fin else null
			var go_uc: bool = un != null and float(un["net"]) + gauss((1.0 - tact) * 1.5) > 0.5 / um
			if go_uc:
				var pr_uc: Variant = predict_pit(c)
				go_uc = pr_uc == null or pr_uc["ahead"] == null or float(pr_uc["ahead"][1]) >= 1.0
			if go_uc:
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
		var free_pit := false
		if sc and want == "slick" and left > 2:
			var cp: int = class_pos(c)
			# A-7.5 막판 상위권: 타이어가 버티면 트랙 포지션을 지킨다 (뒤차들이 새 타이어로 와도 SC 뒤 짧은 스프린트)
			if cp <= 3 and left <= maxi(3, int(laps * 0.2)) and c.wear < ai_lim(c.comp) - 0.08:
				sc_skip = true
			# A-7.5 공짜 피트: 들어갔다 나와도 1계단 이하로 잃으면 계획보다 이르더라도 들어간다 (감각 있는 팀만)
			elif not sc_skip and tact >= 0.6 and c.wear >= 0.25 and c.free_pit_try != c.pits:
				c.free_pit_try = c.pits
				var pr_sc: Variant = predict_pit(c)
				free_pit = pr_sc != null and int(pr_sc["pos"]) - cp <= 1
				if free_pit:
					_tally("SC공짜피트")
		if sc and not sc_skip and cur > 2 and (free_pit or (c.wear >= 0.35 and (cur >= ns["lap"] or (c.sc_early and ns["lap"] - cur <= 4) or c.wear >= 0.50))) and left > 2:
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
	var pen_now: float = c.wear * c.wear * float(cpv(c.comp)[2]) + cliff_pen(c.comp, c.wear)
	var fresh = "H" if left > 7 else ("M" if left > 4 else "S")
	var fresh_gap: float = float(cpv(fresh)[0]) - float(cpv(c.comp)[0])
	if left >= 2 and ((pen_now - fresh_gap) * left * 0.75 > stop_cost() or c.wear >= 0.92):
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


## 같은 클래스 바로 앞차와의 간격(초), 없으면 INF (화면 '대기' 표시용)
func _ahead_same_class(c) -> float:
	var f: Variant = _front_same_class(c)
	var k: int = c.cross.size() - 1
	if f == null or k < 0 or is_pitting(f):
		return INF
	return float(c.cross[k]) - float(f.cross[k])


func _behind_same_class(c) -> float:
	var k: int = c.cross.size() - 1
	if k <= 0:
		return INF
	var bg := INF
	for o in cars:
		if o == c or o.cls != c.cls or o.dnf != "" or o.cross.size() <= k - 1:
			continue
		var g: float = float(o.cross[k - 1]) - float(c.cross[k - 1])
		if g > 0.0 and g < bg:
			bg = g
	return bg


func _wec_burn(c, m: String) -> float:
	return FPL * wec_fuel_mult(c, m)


## WEC 랩당 연료 배율. 실제 WEC 는 BoP 로 스틴트당 에너지(가상 에너지 탱크)가 정해져
## 같은 차끼리 스틴트 길이가 거의 같다 → 드라이버 연비·엔진 효율 차이는 F1 의 35% 만 반영.
## 주행 페이스(공격 +6% · 세이브 -7%)는 그대로. 화면 표시·AI 판단·실제 소모가 모두 이 값을 쓴다
func wec_fuel_mult(c, m: String = "") -> float:
	var mode: String = c.fuel_mode if m == "" else m
	var pace_m: float = float(PACE_FUEL[c.pace])
	return float(FUEL[mode][1]) * (1.0 + (c.fuel_burn_rate - 1.0) * 0.35) * (1.0 + (1.0 - c.eng_eff) * 0.35) * pace_m


## WEC 피트 판단 (HTML wecDecision). 내 차는 지시가 있을 때만, 단 연료가 1랩도 안 남으면 자동 급유
func wec_decision(c, cur: int, left: int, want: String) -> Variant:
	var want_kind := "slick" if want == "slick" else "W"
	if c.mine:
		if c.pit_req == "":
			var fm_m: float = wec_fuel_mult(c)
			var one_lap: float = FPL * fm_m
			var fuel_line: float = c.fuel - one_lap * T.share[NS - 1]
			if left >= 1 and fuel_line < one_lap * 0.90:
				var d_t: bool = c.wear > cliff_at(c.comp) - 0.20 or kind_of(c.comp) != want_kind
				if d_t and kind_of(c.comp) == want_kind and c.wec_sets <= 0:
					# 새 세트가 없으면 보관 세트가 타이어 교체 시간보다 이득일 때만 (수정 32)
					var rg: Variant = wec_reuse_gain(c, mini(left, STINT), wec_stop_time(c, true, false) - wec_stop_time(c, false, false))
					d_t = rg != null and float(rg["gain"]) > 0.0
				var comp0: String = (wec_pick_comp(c, wec_tyre_run(c, left), false) if want == "slick" else "W") if d_t else c.comp
				say(c, "연료 부족! 다음 랩 완주 불가 → 자동 박스 (급유%s)" % ((" + " + TYRE_KO[comp0]) if d_t else ""))
				var d_d: bool = c.auto_swap or must_swap(c)
				return {"comp": comp0, "tyres": d_t, "driver": d_d, "fuel": true, "fill": _auto_fill(c)}
			return null
		var req: Dictionary = c.wec_req if c.wec_req != null else {"tyres": true, "fuel": true, "driver": c.auto_swap}
		var comp1: String = wec_fit_comp(c.cls, c.pit_req)
		c.pit_req = ""
		c.wec_req = null
		c.crew_out = true
		return {"comp": comp1, "tyres": bool(req.get("tyres", true)), "driver": bool(req.get("driver", false)), "fuel": bool(req.get("fuel", true)), "drv": int(req.get("drv", -1)), "fill": float(req.get("fill", 1.0))}
	var fm: float = wec_fuel_mult(c)
	var fuel_at_line: float = c.fuel - FPL * T.share[NS - 1] * fm
	var need_fuel: bool = fuel_at_line < FPL * fm * 0.92 and left >= 1
	var cl: float = cliff_at(c.comp) if SLICK.has(c.comp) else 0.65 # 미디엄·소프트 0.65(예전 고정값 기준), WEC 하드 0.75
	var worn_out: bool = c.wear >= cl - 0.03 and left >= 2
	# 새 세트가 없으면 "다 닳음"만으로 들어오지 않는다: 보관 세트로 다음 스틴트를 달리는 게 정차 전체 시간보다 이득일 때만 (수정 32)
	var reuse: Variant = null
	var no_sets: bool = c.wec_sets <= 0 and want == "slick" and kind_of(c.comp) == want_kind
	if no_sets and worn_out:
		var n_r: int = mini(left, STINT)
		reuse = wec_reuse_gain(c, n_r, wec_stop_time(c, true, false, false))
		if reuse == null or float(reuse["gain"]) <= 0.0:
			worn_out = false
	var early: bool = c.sc_early and sc and cur > 2 and c.wear >= 0.38 and (fuel_at_line < FPL * fm * 2.2 or c.wear >= 0.50) and left > 2
	var wrong: bool = kind_of(c.comp) != want_kind
	var weather := false
	if wrong:
		var nw := "M" if want == "slick" else "W"
		var lose: float = wx_pen_track(c.comp) - wx_pen_track(nw)
		var hz: float = uni(1.8, 4.5)
		if clampf(c.strategy + (difficulty - 1) * 0.08, 0.3, 1.1) >= 0.7:
			hz = minf(float(left), float(_wrong_laps(c, cur, kind_of(c.comp))) * uni(0.85, 1.15) + 0.5) # 예보를 읽는 팀
		weather = lose * hz > wec_stop_time(c, true, false) * 0.75
	# 주행 한도 직전(이번 랩을 마치면 한도): 연료가 남아도 들어와서 교대 — SC 로 스틴트가 길어지면 생기던 1랩 초과(AI 2%) 방지
	var drv_due := false
	if c.drivers.size() >= 2 and left >= 1:
		var lim_c: Dictionary = drive_limits()
		var tot_c: int = int(c.drv_laps[c.drv]) if c.drv < c.drv_laps.size() else 0
		drv_due = drive_in_window(c, c.drv) + 1 >= int(lim_c["max_win"]) or tot_c + 1 >= int(lim_c["max_total"])
	if not need_fuel and not worn_out and not early and not weather and not drv_due:
		return null
	var tyre_due: bool = c.stint_tyre + 1 >= c.set_plan or c.wear >= cl - 0.13 or worn_out
	# 세트 제한: 남은 스틴트에 비해 새 세트가 모자라면 마모가 심하지 않은 한 한 스틴트 더 탄다
	if tyre_due and not wrong and want == "slick":
		var stints_after: int = int(ceil(float(left) / STINT))
		var short_sets: bool = c.wec_sets < int(ceil(stints_after / 2.0))
		if c.wec_sets <= 0:
			# 급유 정차에 얹어 바꿀지: 타이어 교체 시간만큼 이득이 있어야 (다 닳음으로 들어온 정차는 위에서 이미 확인)
			if reuse == null:
				var tyre_cost: float = wec_stop_time(c, true, false) - wec_stop_time(c, false, false)
				reuse = wec_reuse_gain(c, mini(left, STINT), tyre_cost)
			tyre_due = reuse != null and float(reuse["gain"]) > 0.0
		elif short_sets and c.wear < cl - 0.20 and not worn_out:
			tyre_due = false
	var tyres: bool = tyre_due or wrong
	var driver: bool = c.stint_drv + 1 >= c.driver_every or must_swap(c) or drv_due
	# 하위 클래스 최소 주행(브론즈 등): 모자라면 늦지 않게 그 드라이버로 바꾸고, 채울 때까지 내리지 않는다
	# (예전엔 순서대로만 돌려서 짧은 레이스에서 AI 가 거의 다 60초 페널티를 받았음)
	# 르망의 드라이버별 최소 주행(각자 6시간 분량)도 같이: 다른 드라이버들이 채워야 할 랩이 남은 랩에 가까워지면 교대
	if _oth_short_due(c):
		driver = true
	elif drv_short(c, c.drv) > 0:
		driver = must_swap(c)
	var comp: String = (c.comp if SLICK.has(c.comp) else "M") if want == "slick" else "W"
	if want == "slick" and tyres and c.wec_sets <= 0 and reuse != null and not wrong:
		comp = String(reuse["comp"]) # 보관 세트 중 가장 이득인 것 (apply_pit 이 그 컴파운드에서 가장 덜 닳은 세트를 낀다)
	elif want == "slick" and tyres:
		# 컴파운드·이 세트로 탈 스틴트 수: 예상 노면 온도 · 타이어 교체 시간 · 세트 사정으로 (수정 24 · 31)
		comp = wec_pick_set(c, left)
	if not tyres:
		comp = c.comp
	comp = wec_fit_comp(c.cls, comp)
	c.crew_out = true
	return {"comp": comp, "tyres": tyres, "driver": driver, "fuel": true, "fill": _auto_fill(c)}


## 다른 드라이버들이 최소 주행을 채우려면 지금 교대해야 하나 (AI 교대 판단 · 화면 "추천(의무)" 공용)
func _oth_short_due(c) -> bool:
	var oth_short := 0
	for di in c.drivers.size():
		if di != c.drv:
			oth_short += drv_short(c, di)
	if oth_short <= 0:
		return false
	# 남은 거리는 내 차 기준 (느린 클래스는 선두보다 랩을 덜 돈다 — 전체 남은 랩으로 보면 교대가 늦어짐)
	# 모자란 랩이 6시간 구간 한도(max_win)를 넘으면 한 번에 못 채우고 쉬었다 다시 타야 하니 그만큼 일찍 시작한다
	var span: float = float(oth_short + STINT * 2 + 2)
	var lim_d: Dictionary = drive_limits()
	if oth_short >= int(lim_d["max_win"]):
		span += float(int(lim_d["win"]) - int(lim_d["max_win"]) + STINT)
	return laps_to_go(c) <= span


## 지금 꼭 교대해야 하나: 지금 드라이버가 한도에 닿거나, 다른 드라이버 최소 주행을 채울 시간이 빠듯함
func swap_due(c) -> bool:
	return must_swap(c) or _oth_short_due(c)

## 새 타이어로 달릴 랩 수 어림: 남은 게 한 스틴트 남짓이면 끝까지, 아니면 타이어 교체 주기(더블 스틴트 등)
func wec_tyre_run(c, left: int) -> int:
	if left <= STINT + 1:
		return left
	return mini(left, STINT * maxi(1, c.set_plan))


## AI·자동 박스 급유량: 남은 거리가 한 탱크 안이면 완주에 필요한 만큼만(스플래시) → 정차가 짧다. 아니면 가득
func _auto_fill(c) -> float:
	var f: float = fill_to_finish(c, 0.6)
	if f < 0.97:
		_tally("스플래시 급유")
	return f


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
		_tally("drive_viol")
		# 페널티 기록(pen_log)에 남겨야 차 정보 창·결과·복기에 사유가 나온다
		var why: String = ("%s 6시간 구간 주행 초과 (%d/%d랩)" % [c.name, inw, int(lim["max_win"])]) if inw > int(lim["max_win"]) else ("%s 총 주행 초과 (%d/%d랩)" % [c.name, tot, int(lim["max_total"])])
		add_penalty(c, 60.0, why)
		if c.mine:
			say(c, "주행 시간 규정 위반 (%s) → 60초 페널티" % c.name)
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
	if not has_ers():
		c.ers_mode = "balance"
	elif c.ers < 0.2:
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
		c.lap_times.append({"lap": c.lap, "t": lt, "comp": c.comp, "pit": c.pit_lap, "cliff": SLICK.has(c.comp) and c.wear > ai_lim(c.comp), "drv": c.drv, "fuel": snappedf(c.fuel, 0.1)})
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
		if timed and not time_up and t >= time_limit:
			time_up = true
			event("⏱ 시간 종료! 선두가 결승선을 지나면 체커기")
		if timed and time_up and not finishing and c == _overall_leader():
			laps = c.lap # 선두의 최종 랩
		if (not timed and c.lap >= laps) or finishing or (timed and time_up and c.lap >= laps):
			c.finished = true
			c.finish_t = t
			c.boxing = null
			c.pit_phase = 0
			if c.time_pen > 0.0:
				c.penalty += c.time_pen
				c.finish_t += c.time_pen
			if need_two() and c.used_slicks() < 2:
				_end_pen(c, 30.0, "드라이 2종 의무 미사용")
			if is_wec() and min_each(c) > 0 and c.drivers.size() >= 2:
				for di in c.drivers.size():
					if di < c.drv_laps.size() and int(c.drv_laps[di]) < min_each(c, true):
						_end_pen(c, 60.0, "%s 최소 주행 미달 (%d/%d랩)" % [c.drivers[di]["name"], int(c.drv_laps[di]), min_each(c, true)])
						event("%s %s 최소 주행 시간(르망 6시간) 미달 → 60초 페널티" % [name_of(c), c.drivers[di]["name"]], "bad")
			if min_drive != null and min_drive_short(c, true) > 0:
				c.min_drive_fail = true
				_end_pen(c, 60.0, "%s 드라이버 최소 주행 미달" % GRADE_KO.get(min_drive["grade"], ""))
				event("%s %s 최소 주행 시간 미달 → 60초 페널티" % [name_of(c), GRADE_KO.get(min_drive["grade"], "")], "bad")
			if not finishing:
				finishing = true
				first_cross = c.id
				if c.penalty > 0.0:
					event("체커기! %s 1위로 통과 — 페널티 +%.0f초 반영 후 최종 순위 확정" % [c.label if is_wec() else c.code, c.penalty])
				else:
					event("체커기! %s 우승" % (c.label if is_wec() else c.code))
			return
		c.sec = 0
		if c.boxing != null:
			apply_pit(c)
		else:
			c.pit_phase = 0
			# 헤드라이트 파손 2랩 지나도 안 고치면 레이스 컨트롤 수리 지시 (블랙·오렌지 플래그) → 다음 랩 강제 피트
			if c.lamp_out and c.lap - c.lamp_lap >= 2:
				c.boxing = {"comp": c.comp, "tyres": false, "driver": false, "fuel": false, "forced": true}
				c.pit_total = WPIT["lane"] * pit_scale()
				event("🏴 %s 블랙·오렌지 플래그 — 헤드라이트 수리 지시" % name_of(c), "bad")
		var fault_esc: bool = c.fault != null and rnd() < float(c.fault["esc"])
		var fp: float = fail_p(c)
		if not fault_esc and c.fault == null and rnd() < fp * FAULT_SHARE:
			_start_fault(c)
		elif fault_esc or rnd() < fp * (1.0 - FAULT_SHARE):
			if fault_esc:
				event("%s %s 악화" % [name_of(c), c.fault["kind"]], "bad")
				c.fault = null
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
			var manual: bool = c.mine and c.pit_req != ""
			var d: Variant = pit_decision(c)
			if d != null:
				if pit_closed() and manual and not is_wec():
					d["closed"] = true # 플레이어가 폐쇄 중에 직접 넣은 피트만 스톱 앤 고
				c.boxing = d
				# 피트 크루 숙련도(기본 0.85, 훈련센터 Lv당 +0.025): Lv5면 정차 약 0.8초 단축
				if is_wec():
					c.pit_total = wec_stop_time(c, d["tyres"], d.get("driver", false), d.get("fuel", true), float(d.get("fill", 1.0)))
				else:
					c.pit_total = pit_loss() + gauss(0.6) - (c.crew - 0.85) * 8.0
					c.pit_total += _crew_error(c)
	c.started = true
	schedule_next(c, t)


## 피트레인이 닫혀 있나 (피트 입구 근처 사고 직후 1랩)
func pit_closed() -> bool:
	return pit_closed_until >= 0 and leader_lap < pit_closed_until


func apply_pit(c) -> void:
	if c.lamp_out:
		c.lamp_out = false
		c.garage += 0.3 * float(CIRC["base"]) * laps / real_laps() # 헤드라이트 교체
		event("%s 헤드라이트 수리" % name_of(c))
	# 시간 페널티 해소 (F1 스포팅 규정 54조·WEC 같음): 받은 뒤 첫 정차에서 작업 전에 그 시간만큼 서 있는다.
	# 강제 정차(레이스 컨트롤 수리 지시)는 제외. 이번 정차에서 새로 받는 페널티(릴리스 등)는 다음 정차에
	if c.boxing != null and not c.boxing.get("forced", false) and c.time_pen > 0.0:
		var held: float = c.time_pen
		c.time_pen = 0.0
		c.pit_total += held
		c.pen_served += held
		_tally("페널티 정차 해소")
		if c.mine:
			say(c, "이번 정차에서 %d초 페널티 해소 (작업 전 대기)" % int(held))
		c.boxing["pen_held"] = held
	# 새 드라이 세트가 바닥났으면 쓰던 세트를 다시 낀다 → 한 번도 안 쓴 컴파운드의 "쓴 세트"는 없다 (수정 25)
	if is_wec() and c.boxing != null and bool(c.boxing.get("tyres", false)) and SLICK.has(String(c.boxing["comp"])) and c.wec_sets <= 0:
		c.boxing["reuse"] = true
		# 다시 낄 수 있는 건 빼 둔 세트(wec_pool)와 지금 끼운 세트뿐
		var want_k: String = String(c.boxing["comp"])
		if want_k != c.comp and Array(c.wec_pool.get(want_k, [])).is_empty():
			var alt := ""
			if SLICK.has(c.comp):
				alt = c.comp
			else:
				for k in ["M", "H", "S"]:
					if not Array(c.wec_pool.get(k, [])).is_empty() and wec_comps(c.cls).has(k):
						alt = k
						break
			if alt != "":
				if c.mine:
					say(c, "%s 새 세트가 없어 쓰던 %s 세트를 다시 껴요" % [TYRE_KO[c.boxing["comp"]], TYRE_KO[alt]])
				c.boxing["comp"] = alt
	if c.boxing != null and c.boxing.get("closed", false):
		# 폐쇄 중 진입: 스톱 앤 고 10초 (정차 + 피트레인 한 번 더 통과에 해당하는 시간)
		add_penalty(c, 10.0 + pit_loss(), "피트레인 폐쇄 중 진입 · 스톱 앤 고")
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
		c.pit_log.append({"lap": c.lap + 1, "pos": class_pos(c), "from": c.comp, "to": c.boxing["comp"] if c.boxing["tyres"] else c.comp, "tyres": bool(c.boxing["tyres"]), "sc": sc_kind if sc else "", "pen_held": float(c.boxing.get("pen_held", 0.0)), "reuse": bool(c.boxing.get("reuse", false)),
			"pred": int(pr["pos"]) if pr != null else class_pos(c), "pred_green": pr_green,
			"ahead_ids": pr["ahead_ids"] if pr != null else []})
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
	if c.limp_pos > 0:
		# 수정 13 감시: 부서진 차가 피트에 닿기 전에 순위가 올랐다면 그 순간 앞차들 상태와 함께 ⚠
		var now_p: int = class_pos(c)
		if now_p < c.limp_pos:
			var st: Array = []
			var n := 0
			for o in order():
				if o.cls != c.cls:
					continue
				n += 1
				if n > c.limp_pos + 1:
					break
				st.append("P%d %s%s" % [n, o.code, " 피트" if is_pitting(o) else (" 수리중" if o.boxing != null else (" OUT" if o.dnf != "" else ""))])
			BLog.warn("손상 차 %s 피트 가는 동안 P%d→P%d (SC %s) | %s" % [name_of(c), c.limp_pos, now_p, sc_kind if sc else "-", ", ".join(st)])
		c.limp_pos = 0
	if c.fault != null and bool(c.fault["repair"]):
		c.garage += float(c.fault["fix"])
		event("%s %s 수리 (+%d초)" % [name_of(c), c.fault["kind"], int(round(c.fault["fix"]))])
		if not c.pit_log.is_empty() and int(c.pit_log[-1]["lap"]) == c.lap + 1:
			c.pit_log[-1]["fix"] = c.fault["kind"]
		c.fault = null
	if c.mine:
		BLog.add("피트 %s%s 클래스 P%d 랩%d%s" % [name_of(c), " (내 차)" if c.mine else "", class_pos(c), c.lap + 1, " 수리 %.0f초" % c.garage if c.garage > 0.0 else ""])
	c.pit_total += c.garage
	c.garage = 0.0
	c.limp = 0.0
	if not c.pit_log.is_empty() and int(c.pit_log[-1]["lap"]) == c.lap + 1:
		c.pit_log[-1]["loss"] = snappedf(c.pit_total, 0.1) # 복기: 피트로 잃은 시간(레인+정차)
	if d["tyres"]:
		# WEC: 뺀 드라이 세트는 그 마모 그대로 보관 → 새 세트가 바닥나면 여기서 다시 낀다 (수정 31-1)
		if is_wec() and SLICK.has(c.comp):
			var pl0: Array = c.wec_pool.get(c.comp, [])
			pl0.append({"w": c.wear, "h": maxi(1, c.set_h)}) # 다시 낀 세트는 달군 횟수가 쌓인다 (예전엔 늘 1로 돌아감)
			c.wec_pool[c.comp] = pl0
		c.comp = d["comp"]
		c.used[c.comp] = true
		c.wear = 0.0
		c.used_set_pen = 0.0
		c.set_h = 1
		if c.mine and c.tyre_sets != null and SLICK.has(c.comp) and not is_wec():
			if c.tyre_sets[c.comp] > 0:
				c.tyre_sets[c.comp] -= 1
			else:
				_fit_used_from_pool(c)
		c.tt = 0.35
		if is_wec():
			# 타이어 워머 금지: 차가운 새 타이어로 나간다 (하드일수록·밤일수록 더 차갑다)
			c.tt = float(WEC_COLD_TT.get(c.comp, 0.3)) - (0.04 if night else 0.0)
			if SLICK.has(c.comp):
				if c.wec_sets > 0:
					c.wec_sets -= 1
				else:
					# 새 세트가 없으면 빼 둔 세트 중 가장 덜 닳은 것 (그 마모 + 열 사이클 손해). 예전엔 늘 34% 로 무한 회복되던 허점
					var pool: Array = c.wec_pool.get(c.comp, [])
					if pool.is_empty():
						fit_used(c, null) # shortcut: 보관 세트가 없을 일은 없지만(apply_pit 이 쓴 컴파운드로 바꿈) 만약을 위해 옛 기본값
					else:
						var bi: int = least_worn(pool)
						fit_used(c, pool[bi])
						pool.remove_at(bi)
					if c.mine:
						say(c, "새 드라이 세트가 없어 쓰던 세트(마모 %d%%)를 다시 끼웠어요" % int(round(c.wear * 100.0)))
		c.stint_laps = 0
		c.stint_tyre = 0
	elif not d.get("forced", false):
		c.stint_tyre += 1
	var acts: Array = []
	if d["tyres"]:
		acts.append(TYRE_KO[c.comp] + " 장착")
	if is_wec() and not d.get("forced", false):
		if d.get("fuel", true):
			var fill: float = float(d.get("fill", 1.0))
			var add: float = fuel_add(c, fill)
			# 결과 확인: 부분 급유로 아낀 정차 시간 (같은 조건 가득 대비) → 무전·복기
			var fuel_save: float = 0.0
			if fill < 0.98 and add > 0.0:
				fuel_save = wec_stop_time(c, d["tyres"], d.get("driver", false), true, 1.0) - wec_stop_time(c, d["tyres"], d.get("driver", false), true, fill)
				if not c.pit_log.is_empty() and int(c.pit_log[-1]["lap"]) == c.lap + 1:
					c.pit_log[-1]["fuel_save"] = snappedf(fuel_save, 0.1)
			if add > 0.0:
				c.fuel += add
				_fuel_stat[0] += add / TANK
				_fuel_stat[1] += 1
				acts.append(("급유 +%.1f랩 · 가득보다 −%.1f초" % [add / maxf(0.01, _wec_burn(c, c.fuel_mode)), fuel_save]) if fill < 0.98 else "연료 급유")
		if d.get("driver", false):
			var pick_d: int = int(d.get("drv", -1))
			c.drv = pick_d if (pick_d >= 0 and pick_d < c.drivers.size() and pick_d != c.drv) else next_driver(c)
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
		c.wear = minf(1.0, c.wear + float(cpv(c.comp)[1]) * 0.25 * c.tyre_deg_rate * sh)
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
			# AI 팀 오더: 한 섹터가 아니라 직전 랩이 확실히 빨라야, 3랩 이후, 팀당 6랩에 한 번
			var ai_swap: bool = mate and not c.mine and not ahead.mine and gap != null and gap < 1.2 and diff > 0.25 and c.strat_style != "aggressive" and laps - c.lap > 2 \
				and c.lap >= 3 and c.last_lap_t > 0.0 and ahead.last_lap_t > 0.0 and c.last_lap_t < ahead.last_lap_t - 0.3 * wsc() \
				and c.lap - int(team_swap_lap.get(c.team, -99)) >= 6 and rnd() < 0.35 * c.strategy
			if ai_swap:
				_tally("팀오더")
				team_swap_lap[c.team] = c.lap
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
				var p: float = float(CIRC["overtake"]) + diff * 0.8 + (c.aggr - ahead.aggr) * 0.1 + 0.08 - ahead.def_ * 0.15 + (c.wet - ahead.wet) * 0.3 * sec_w(c.sec) - off_gap(c.sec) * 0.6 + (0.1 if rs else 0.0) \
					+ ((0.15 if has_ers() else 0.19) if c.drs else 0.0) + (0.06 if (has_ers() and c.ers_mode == "deploy" and c.ers > 0.02) else 0.0) + (0.08 if c.instr == "attack" else 0.0) + (ahead.wing - c.wing) * 0.02 \
					- (0.12 if ahead.instr == "defend" else 0.0) - (0.04 if (has_ers() and ahead.ers_mode == "deploy" and ahead.ers > 0.02) else 0.0)
				p += (0.06 if c.traits.has("dive") else 0.0) - (0.06 if ahead.traits.has("wall") else 0.0)
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
				elif rnd() < K["crash"] * c.aggr * float(PACE[c.pace][2]) * (1.0 + 2.0 * sec_w(c.sec) + 3.0 * off_gap(c.sec)) * (1.6 if c.instr == "attack" else 1.0) * (1.3 if ahead.instr == "defend" else 1.0) * (1.35 if c.traits.has("dive") else 1.0):
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
					c.crash_with = ahead.code
					if rnd() < K["victim"]:
						ahead.pending_victim = true
						ahead.crash_with = c.code
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


## 시간제: 지금까지 선두 평균 랩 페이스로 남은 시간에 몇 랩 더 돌지 → 예상 총 랩.
## 체커는 시간이 끝난 뒤 선두가 결승선을 지날 때라서 남은 시간을 올림한다
func _update_timed_laps() -> void:
	if not timed or time_up or leader_lap <= 0:
		return
	var avg: float = clock / float(leader_lap)
	var rest: float = maxf(0.0, time_limit - clock)
	laps = maxi(leader_lap + 1, leader_lap + int(ceil(rest / maxf(1.0, avg))))


## 시간제 체커 대상: 가장 많은 랩을 돈 차 (같은 랩이면 먼저 지난 차). 피트에 있어도 선두는 선두
func _overall_leader() -> Variant:
	var best: Variant = null
	for o in cars:
		if o.dnf != "" or o.finished:
			continue
		if best == null or o.cross.size() > best.cross.size() or (o.cross.size() == best.cross.size() and o.cross.size() > 0 and o.cross[-1] < best.cross[-1]):
			best = o
	return best


## 시간제 남은 시간을 실제 레이스 시간(시간 단위)으로: 화면 표시용
func time_left_real() -> float:
	if not timed or time_limit <= 0.0:
		return 0.0
	return maxf(0.0, time_limit - clock) / time_limit * wec_hours()


## "5:42" (시:분) — 시간제 남은 시간. 시간 종료 후엔 "마지막 랩"
func time_left_txt() -> String:
	if time_up:
		return "마지막 랩"
	var m: int = int(round(time_left_real() * 60.0))
	return "%d:%02d" % [m / 60, m % 60]


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
	_update_timed_laps()
	if sc:
		sc_laps.append(l)
	var prev_kind = ideal_tyre(wet)
	_wx_step(l)
	_fc_refresh()
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
	track_now = track_temp_at(float(l) / maxf(1.0, float(laps))) - WET_COOL * wet
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
		if is_wec() and sc_kind == "SC":
			# 웨이브 바이: 클래스 선두 앞에 끼어 있던 하위 클래스·백마커를 SC 를 지나 대열 뒤로 보낸다
			# → 리스타트 랩엔 빠른 클래스가 느린 차에 막히지 않고 같은 클래스끼리 붙는다
			wave_clear_lap = l + 1
			event("🏁 웨이브 바이: 하위 클래스·백마커가 세이프티카를 지나 대열 뒤로 — 클래스별로 정렬된 리스타트", "sc")
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
		if ever_wet or wet > 0.05:
			_xo_radio(c, left)
		# 이미 박스 지시(예약)가 있거나 피트에 들어가는 중이면 피트 요청 무전은 하지 않는다
		var booked: bool = c.pit_req != "" or c.boxing != null or is_pitting(c)
		var want_k: String = it if it != "slick" else "slick"
		if kind_of(c.comp) != want_k:
			if booked and c.pit_req != "" and kind_of(c.pit_req) != want_k:
				say(c, "예약한 %s는 지금 노면에 안 맞아요. 타이어를 다시 골라주세요" % TYRE_KO.get(c.pit_req, c.pit_req))
			elif not booked:
				say(c, "라인이 말랐어요. 슬릭으로 바꿔야 해요" if it == "slick" else "노면이 젖었어요. %s 필요해요" % TYRE_KO[it])
				if not c.auto_plan and left >= 2:
					trigger_radio(c, "WET")
		elif not is_wec() and left > 0 and c.lap >= 2 and c.fuel < left * FPL * float(FUEL[c.fuel_mode][1]) * c.fuel_burn_rate - FPL * 0.3:
			# 드라이버 연비까지 반영해 계산. 연비 모드로도 못 버티면 강하게, 아니면 얼마나 모자란지 알려준다
			var short_std: float = (left * FPL * float(FUEL[c.fuel_mode][1]) * c.fuel_burn_rate - c.fuel) / (FPL * c.fuel_burn_rate)
			var short_lean: float = (left * FPL * float(FUEL["lean"][1]) * c.fuel_burn_rate - c.fuel) / (FPL * c.fuel_burn_rate)
			if short_lean > 0.1:
				say(c, "연료가 %.1f랩분 모자라요! 연비 모드에 리프트 앤 코스트까지 써야 해요" % short_std)
			elif c.fuel_mode != "lean":
				say(c, "지금 페이스면 연료가 %.1f랩분 모자라요. 'ERS·연료' 탭에서 세이브로 바꿔주세요" % short_std)
		elif (c.wear > maxf(0.7, cliff_at(c.comp)) or (c.comp == "H" and c.wear > cliff_at("H"))) and not booked:
			# 막판(3랩 이하)엔 피트 손실이 남은 랩에서 잃는 시간보다 커서 버티는 게 정답
			if left <= 3:
				say(c, "타이어가 다 됐지만 %d랩 남았어요. 끝까지 버틸게요" % left)
			else:
				say(c, "타이어가 다 됐어요 (%d%%)" % int(round(c.wear * 100)))
				if not c.auto_plan:
					trigger_radio(c, "WORN")
		elif c.tt > 0.82:
			say(c, "타이어가 과열됐어요. 페이스 좀 낮출게요?")
		elif is_wec() and c.stint_drv >= 2:
			say(c, "%s: 세 번째 스틴트라 집중력이 떨어져요" % c.name)
		elif has_ers() and c.ers < 0.1 and c.ers_mode == "deploy":
			say(c, "배터리가 바닥이에요")
		elif need_two() and left <= 4 and c.used_slicks() < 2 and not (booked and SLICK.has(c.pit_req) and c.pit_req != c.comp):
			say(c, "아직 두 번째 컴파운드를 안 썼어요! 안 바꾸면 30초 페널티예요")


# ═════════ 시뮬레이션 진행 ═════════
## 시뮬레이션 시간을 dt초 진행한다. 이 구간에 끝나는 섹터들을 시간 순서대로 처리한다.
func advance(dt: float) -> void:
	if done:
		return
	var target = clock + dt
	var caught_up := false
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
			caught_up = true
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
	# 한 프레임에 사건이 너무 많으면(아주 높은 배속·앱 복귀) 처리한 곳에서 멈추고 다음 프레임에 이어서 —
	# 예전엔 시계를 목표로 건너뛰어 남은 섹터를 잘라냈다 (시간제 체커·순위가 배속에 따라 달라질 수 있었음)
	if caught_up:
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
		var ord_f: Array = order()
		if not ord_f.is_empty() and ord_f[0].id != first_cross:
			event("최종 결과: 페널티 반영으로 %s 우승" % (ord_f[0].label if is_wec() else ord_f[0].code))


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
		# 아직 달리는 차가 같은 랩 수로 들어올 차면(한 랩 덜 돈 상태) 결승선 도착 예상 시각으로 비교한다.
		# 완주 순간 페널티(예: 최소 주행 60초)가 붙은 차가 도로 순위로 잠깐 위에 떴다가 뒤로 밀리던 것 방지
		var r := 1
		if f.lap > o.lap + 1:
			r = -1
		elif f.lap == o.lap + 1:
			r = -1 if f.finish_t <= _line_eta(o) else 1
		return r if a.finished else -r
	if b.cross.size() != a.cross.size():
		return b.cross.size() - a.cross.size()
	var na: float = a.sec_end if a.started else a.start_t
	var nb: float = b.sec_end if b.started else b.start_t
	if na != nb:
		return -1 if na < nb else 1
	return a.grid - b.grid


## 달리는 차가 결승선(랩 끝)에 닿을 예상 시각
func _line_eta(o) -> float:
	if not o.started or o.dnf != "":
		return INF
	var per: float = (o.last_lap_t if o.last_lap_t > 0.0 else 120.0) / float(NS)
	return o.sec_end + float(NS - 1 - o.sec) * per


## 현재 순위 (실제 시뮬레이션 기준: 더 많은 경계를 지났고, 같다면 다음 경계에 먼저 도착할 차가 앞)
func order() -> Array:
	var arr = cars.duplicate()
	arr.sort_custom(func(a, b): return _cmp(a, b) < 0)
	return arr


## 화면용 순위: 같은 시각(clock)이면 한 번만 정렬해 재사용 (화면은 매 프레임 여러 번 순위를 읽는다).
## 시뮬레이션 내부 계산에는 쓰지 않는다 — 같은 시각에도 상태가 바뀔 수 있어서.
func order_ui() -> Array:
	if _oc_clock != clock or _oc.size() != cars.size():
		_oc = order()
		_oc_clock = clock
	return _oc


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
	c.ers_mode = m if has_ers() else "balance"


## 이 레이스에서 쓸 수 있는 드라이 컴파운드 (F2 옵션·프라임 2종, F3 1종, WEC 는 클래스·대회별)
func dry_list(c = null) -> Array:
	if is_wec() and c != null:
		return wec_comps(c.cls)
	return rules.get("dry", ["S", "M", "H"])


## ERS(하이브리드)가 있는 레이스인지: F1 만. WEC 는 별도 하이브리드 모델, F2·F3 는 실제로 ERS 없음
func has_ers() -> bool:
	return not is_wec() and not bool(rules.get("no_ers", false))


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
		# 출구에서 섹터 끝까지 남은 구간을 실제 달리는 속도로: SC·VSC 중엔 대열 속도(느림)라 피트레인에 더 오래 있다가
		# 천천히 합류해야 대열 앞으로 튀어나갔다가 뒤로 밀리는 것처럼 보이지 않는다
		var slow: float = 1.6 if sc else 1.0
		var lane: float = maxf(total * 0.3, total - (base - t_out) * slow)
		if e < lane:
			return T.pit_lane_point(_lane_u(0.35 + 0.65 * (e / maxf(0.01, lane)), stall))
		var f_out: float = T.exit_frac + (1.0 - T.exit_frac) * clampf((e - lane) / maxf(0.01, total - lane), 0.0, 1.0)
		var d_out: float = T.dist_at(0, f_out)
		# 세 번째 값 = 본 트랙 위 누적 거리 (화면이 앞차를 넘지 않게 맞출 때 씀)
		return [T.point_at(0, f_out), T.head_at_dist(d_out), c.lap * T.L + d_out]
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
func request_pit_wec(c, comp: String, tyres: bool, fuel: bool, driver: bool, drv_idx: int = -1, fill: float = 1.0) -> void:
	if not c.is_running() or c.boxing != null:
		return
	if not tyres and not fuel and not driver:
		say(c, "타이어·급유·교대 중 하나는 골라주세요")
		return
	comp = wec_fit_comp(c.cls, comp)
	c.pit_req = comp if tyres else c.comp
	if driver and drv_idx >= 0 and (drv_idx == c.drv or drv_idx >= c.drivers.size() or drv_block(c, drv_idx) != ""):
		drv_idx = -1
	fill = clampf(fill, 0.0, 1.0)
	if fuel and fuel_add(c, fill) <= 0.0:
		fuel = false # 목표가 지금 연료보다 적으면 급유하지 않는다
	c.wec_req = {"tyres": tyres, "fuel": fuel, "driver": driver, "drv": drv_idx if driver else -1, "fill": fill}
	var parts: Array = []
	parts.append(TYRE_KO[comp] + " 교체" if tyres else "타이어 유지")
	parts.append(("급유 (%.1f랩까지)" % (TANK * fill / maxf(0.01, _wec_burn(c, c.fuel_mode)))) if (fuel and fill < 0.98) else ("급유" if fuel else "급유 생략"))
	if driver:
		parts.append("%s로 교대" % c.drivers[drv_idx]["name"] if drv_idx >= 0 else "드라이버 교대")
	say(c, "박스 지시 확인: " + " + ".join(parts))


func set_fuel_mode(c, m: String) -> void:
	c.fuel_mode = m
	say(c, "연료 %s 모드" % WEC_FUEL_KO[m])


## 최소 주행 규정 대상 드라이버 번호 (없으면 -1)
func min_drive_idx(c) -> int:
	if min_drive == null:
		return -1
	for i in c.drivers.size():
		if c.drivers[i].get("grade", "") == min_drive["grade"]:
			return i
	return -1


## 교대할 다음 드라이버: 최소 주행이 모자란 드라이버가 있으면 그 사람, 아니면 순서대로
func next_driver(c) -> int:
	var n: int = c.drivers.size()
	if n < 2:
		return c.drv
	var best := -1
	var bs := 0
	for di in n:
		if di == c.drv:
			continue
		var sh: int = drv_short(c, di)
		# 모자란 랩이 같으면(르망 초반엔 다들 같음) 빠르고 덜 지친 드라이버
		if sh > bs or (sh > 0 and sh == bs and _drv_score(c, di) > _drv_score(c, best)):
			bs = sh
			best = di
	if best >= 0:
		return best
	# 모자란 드라이버가 없으면 실제 팀처럼: 최대 주행 한도에 안 걸리는 드라이버 중 가장 빠른 사람 (피로가 쌓였으면 그만큼 감점).
	# 의무 시간(브론즈 등)은 위에서 먼저 채우고, 나머지는 빠른 드라이버에게 몰아준다
	var lim: Dictionary = drive_limits()
	var more: int = STINT + 1
	var pick := -1
	var ps := -INF
	for pass_i in 2:
		for di in n:
			if di == c.drv:
				continue
			var tot: int = int(c.drv_laps[di]) if di < c.drv_laps.size() else 0
			if pass_i == 0 and (drive_in_window(c, di) + more > int(lim["max_win"]) or tot + more > int(lim["max_total"])):
				continue
			var sc_d: float = _drv_score(c, di)
			if sc_d > ps:
				ps = sc_d
				pick = di
		if pick >= 0:
			return pick
	return (c.drv + 1) % n



## 교대 후보 점수: 속도 − 피로. 밤엔 실수 적은(안정성) 드라이버, 비가 오면 웻에 강한 드라이버를 더 쳐준다
func _drv_score(c, di: int) -> float:
	var dd: Dictionary = c.drivers[di]
	var sc_d: float = float(dd.get("speed", 0.8)) - 0.05 * fatigue(c, di)
	if night:
		sc_d += (float(dd.get("cons", 0.8)) - 0.8) * 0.3
	if wet > 0.2:
		sc_d += (float(dd.get("wet", 0.8)) - 0.8) * 0.5 * wet
	return sc_d

## 드라이버 di 를 다음 스틴트에 태울 수 없는 이유 ("" = 가능): 6시간 구간·총 주행 한도
func drv_block(c, di: int) -> String:
	if not is_wec() or di < 0 or di >= c.drivers.size():
		return ""
	var lim: Dictionary = drive_limits()
	var more: int = STINT + 1
	if drive_in_window(c, di) + more > int(lim["max_win"]):
		return "6시간 구간 주행 한도"
	var tot: int = int(c.drv_laps[di]) if di < c.drv_laps.size() else 0
	if tot + more > int(lim["max_total"]):
		return "총 주행 한도"
	return ""


## 드라이버 di 가 규정(르망 각자 최소 주행 · 하위 클래스 등급 최소 주행)을 채우려면 더 달려야 하는 랩
func drv_short(c, di: int) -> int:
	var done: int = int(c.drv_laps[di]) if di < c.drv_laps.size() else 0
	var need := 0
	if is_wec():
		need = min_each(c)
	if min_drive != null and di == min_drive_idx(c):
		need = maxi(need, min_drive_need(c))
	return maxi(0, need - done)


## 최소 주행 규정: 해당 등급 드라이버가 더 달려야 하는 랩 수 (0이면 충족)
## 등급 최소 주행(브론즈 25% · 실버 20%)에 필요한 랩: 규정은 '주행 시간' 비율이라 차의 클래스 기준 랩으로
## (예전엔 전체(하이퍼카) 랩 기준이라 느린 클래스가 실제보다 12% 안팎 더 달려야 했음)
func min_drive_need(c, for_check: bool = false) -> int:
	if min_drive == null:
		return 0
	var base_l: int = laps
	if timed:
		base_l = mini(laps, laps_nom) if for_check else laps_nom # min_each 와 같은 원칙
	return int(ceil(float(min_drive["pct"]) * float(base_l) / float(CLASS_PACE.get(c.cls, 1.0))))


## 그 등급 드라이버들이 지금까지 달린 랩 (-1 = 그 등급 드라이버가 없음)
func min_drive_done(c) -> int:
	if min_drive == null:
		return -1
	var done_l := 0
	var has := false
	for i in c.drivers.size():
		if c.drivers[i].get("grade", "") == min_drive["grade"]:
			has = true
			if i < c.drv_laps.size():
				done_l += int(c.drv_laps[i])
	return done_l if has else -1


func min_drive_short(c, for_check: bool = false) -> int:
	var d := min_drive_done(c)
	if d < 0:
		return 0
	return maxi(0, min_drive_need(c, for_check) - d)


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


## id 로 차 찾기 (없으면 null)
func car_by_id(id: int) -> Variant:
	for o in cars:
		if o.id == id:
			return o
	return null


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
	BLog.add("레이스 시작 · %s · %s · %d랩%s · %d대 · 날씨 %.2f" % [CIRC.get("name", "?"), "WEC" if is_wec() else str(rules.get("fmt", "f1")), laps, (" (시간제 %.0f분)" % (time_limit / 60.0)) if timed else "", cars.size(), wet])
	# WEC 는 늘 가득(한 탱크)으로 출발 — 어떤 경로로든 탱크보다 많이 실리지 않게
	if is_wec():
		for c in cars:
			c.fuel = minf(c.fuel, TANK)
	# 그리드 강등 페널티 (파워유닛 교체 등)
	# 강등 차를 모두 빼고, 목표 칸(원래 칸 + 강등) 앞쪽부터 다시 넣는다 → 여러 대가 동시에 강등돼도 서로 밀어주지 않는다
	var pen_cars: Array = []
	for i in cars.size():
		if cars[i].grid_pen > 0:
			pen_cars.append([i + int(cars[i].grid_pen), i, cars[i]])
	if not pen_cars.is_empty():
		pen_cars.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
		for pc in pen_cars:
			cars.erase(pc[2])
		for pc in pen_cars:
			var c = pc[2]
			var ni: int = mini(cars.size(), int(pc[0]))
			cars.insert(ni, c)
			event("%s 그리드 %d계단 강등 (파워유닛 교체)%s" % [name_of(c), c.grid_pen, " → 맨 뒤 출발" if ni >= cars.size() - 1 else ""], "bad")
			c.grid_pen = 0
	for i in cars.size():
		var c = cars[i]
		c.grid = i
		var react = clampf(0.06 - (c.speed * 0.025 + c.aggr * 0.02) - (0.007 if c.traits.has("rocket") else 0.0) + gauss(0.012), 0.01, 0.09)
		if not is_wec() and react <= 0.011 and rnd() < 0.08:
			add_penalty(c, 5.0, "부정 출발 (신호 전에 움직임)")
			event("%s 부정 출발 — 불이 꺼지기 전에 움직여 5초 페널티" % name_of(c), "bad")
			if c.mine:
				say(c, "죄송해요, 출발 반응이 너무 빨랐어요. 신호 전에 움직여서 5초 페널티예요")
		c.start_t = i * (0.42 if is_wec() else 0.25) + react
		c.used[c.comp] = true
		# 주말 모드면 weekend.commit_start_tyres 가 이미 세트를 꺼냈다 (두 번 빼지 않는다)
		if c.mine and c.tyre_sets != null and not c.q3_locked and SLICK.has(c.comp) and not start_tyres_taken:
			if c.tyre_sets[c.comp] > 0:
				c.tyre_sets[c.comp] -= 1
				c.used_set_pen = 0.0
			else:
				_fit_used_from_pool(c)
	if wet_start:
		for c in cars:
			c.comp = "W"
			c.used["W"] = true
			c.used_set_pen = 0.0
		event("🌧 폭우: 세이프티카 선도 스타트 — 규정상 전 차량 풀 웻 타이어로 출발", "wet")
		deploy("SC")
	for c in my_cars():
		make_plans(c)


# ═════════ 내 차 전략 계획 (A/B 플랜 · 자동 피트) ═════════
## 플레이어가 아는 마모율: 공칭값 (실제 배율은 모름). 스틴트를 3랩 이상 달렸으면 관측 마모로 보정.
func my_rates(c) -> Dictionary:
	var out := {}
	for k in SLICK:
		out[k] = float(cpv(k)[1]) * float(plan_mult.get(k, 1.0)) * float(rules.get("wear_mult", 1.0)) * float(CIRC["wear"]) * (WEAR_SCALE / laps) * 0.85 * c.tyre_deg_rate
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
	var cands: Array = ai_optimize(left, c.comp, c.wear, my_rates(c), stop_cost(), c.used, sets, max_st)
	if cands.is_empty():
		cands = ai_optimize(left, c.comp, c.wear, my_rates(c), stop_cost(), c.used, {"S": 9, "M": 9, "H": 9}, max_st)
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
		cost += stop_cost()
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
				warn.append("새 %s 세트 부족 (쓴 세트 — 마모만큼 일찍 닳음)" % TYRE_KO[k])
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


## 조건부 지시가 지금 실제로 작동 중인지 확인 (false 면 화면에 '대기 중' 표시)
func instr_active(c, key: String = "") -> bool:
	var k: String = c.instr if key == "" else key
	if not c.started or not c.is_running() or sc:
		return k == "free"
	match k:
		"attack":
			return _ahead_same_class(c) < 1.0 and not is_pitting(c)
		"hold":
			return _ahead_same_class(c) < 1.5
		"defend":
			return _behind_same_class(c) < 1.0
	return true


## 페이스(kind="pace") · 주행 지시(kind="instr")의 표준 대비 효과 요약 (UI 표시용)
## shortcut: 지시 효과 글(마모 -8%·+0.32초 등)은 sector_time·schedule_next 식을 옮겨 적은 것, 그 식을 바꾸면 여기도 같이
func mode_effects(c, kind: String, key: String) -> Dictionary:
	var pros: Array = []
	var cons: Array = []
	var active := true
	var wait_reason := ""
	if kind == "pace":
		var pc: Array = PACE.get(key, PACE["standard"])
		var spd: float = float(pc[0])
		var wear_m: float = float(pc[1])
		var err_m: float = float(pc[2])
		var dt: float = lap_base(c) * c.speed * float(K["drv_k"]) * (1.0 - spd)
		var wear_pct: int = int(round((wear_m - 1.0) * 100.0))
		var err_pct: int = int(round((err_m - 1.0) * 100.0))
		var fuel_m: float = float(PACE_FUEL.get(key, 1.0))
		var fuel_pct: int = int(round((fuel_m - 1.0) * 100.0))
		if dt < -0.005:
			pros.append("랩당 %.2f초" % dt)
		elif dt > 0.005:
			cons.append("랩당 +%.2f초" % dt)
		if wear_pct < 0:
			pros.append("마모 %d%%" % wear_pct)
		elif wear_pct > 0:
			cons.append("마모 +%d%%" % wear_pct)
		if err_pct < 0:
			pros.append("실수·사고 %d%%" % err_pct)
		elif err_pct > 0:
			cons.append("실수·사고 +%d%%" % err_pct)
		if fuel_pct < 0:
			pros.append("연료 %d%%" % fuel_pct)
		elif fuel_pct > 0:
			cons.append("연료 +%d%%" % fuel_pct)
		if key == "attack":
			cons.append("기계부하 ×3.6 · 고장 +30%")
		elif key == "save":
			pros.append("기계부하 감소")
		else:
			pros.append("집중력 회복(75% 미만 시 +1.5/랩)")
	elif kind == "instr":
		active = instr_active(c, key)
		match key:
			"free":
				pros.append("상황 제약 없는 기본 주행")
			"attack":
				var ot_add: float = 0.08 * float(K["overtake_scale"]) * 100.0
				pros.append("추월 확률 +%.1f%%p" % ot_add)
				pros.append("타이어 목표 온도 +5%")
				cons.append("실수 +20%")
				cons.append("경합 접촉 +60%")
				if not is_wec():
					cons.append("트랙 리밋 +30%")
				cons.append("(앞차 1초 안일 때만)")
				if not active:
					wait_reason = "앞차 1초 밖"
			"defend":
				var def_sub: float = 0.12 * float(K["overtake_scale"]) * 100.0
				pros.append("상대 추월 확률 -%.1f%%p" % def_sub)
				cons.append("랩당 +0.30초 (뒤차 1초 이내)")
				cons.append("피추월 접촉 위험 +30%")
				if not active:
					wait_reason = "뒤차 1초 밖"
			"hold":
				pros.append("마모 -8% (앞차 1.5초 안일 때)")
				if not is_wec():
					var dirty_max: float = 0.2 + 0.3 * float(CIRC["wA"]) / 0.06 + 0.3 * wet
					pros.append("더티 에어(바짝 붙으면 랩당 +%.2f초) 피함" % dirty_max)
					cons.append("1초 간격까지 물러나며 랩당 최대 +%.2f초" % (float(K["dirty"]) * 0.6))
				cons.append("추월 시도 안 함")
				if not active:
					wait_reason = "앞차 1.5초 밖"
			"lift":
				pros.append("마모 -20%")
				pros.append("연료 -14%")
				pros.append("기계부하 -14%/랩 · 타이어 냉각")
				cons.append("랩당 +0.32초 → 뒤차가 따라붙기 쉬움")
	if not active and wait_reason != "" and sc:
		wait_reason = "SC·VSC 중"
	return {"pros": pros, "cons": cons, "active": active, "wait_reason": wait_reason}


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
		var lose: float = wx_pen_track(c.comp) - wx_pen_track(nw)
		# 자동 = 내 팀 엔지니어: 내 팀 예보로 맞지 않는 랩 수만큼 (곧 그칠 비면 버틴다)
		if lose * minf(float(left), float(_wrong_laps(c, cur, have)) + 0.5) > pit_loss():
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
	elif kind == "FAULT" and c.fault != null:
		var fl: int = laps - (c.lap + 1)
		pr = {"title": "📻 [%s 긴급 무전] %s" % [who, c.fault["kind"]], "msg": "“랩당 %.1f초씩 잃어요 (남은 %d랩이면 약 %d초). 고치는 데 약 %d초예요.”" % [c.fault["dt"], fl, int(round(c.fault["dt"] * fl)), int(round(c.fault["fix"]))],
			"opts": [{"label": "다음 피트 때 수리", "act": "FIX_NEXT"}, {"label": "지금 박스해서 수리", "act": "FIX_NOW"}, {"label": "고치지 말고 버티기", "act": "FIX_NO"}]}
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
		"FIX_NEXT", "FIX_NOW", "FIX_NO":
			if c.fault != null:
				var a: String = String(o["act"])
				c.fault["repair"] = a != "FIX_NO"
				c.fault["now"] = a == "FIX_NOW"
				say(c, "카피, %s" % {"FIX_NEXT": "다음 피트 때 고칠게요", "FIX_NOW": "이번 랩에 들어가서 고칠게요", "FIX_NO": "고치지 않고 버틸게요"}[a])
		_:
			say(c, "카피, 지금 상태 그대로 갈게요")


# ═════════ 팀 오더 ═════════
## 시간 페널티: 체커기 때 기록에 더한다
## 체커기에서 붙는 페널티 (기록 시간에 바로 더함)
func _end_pen(c, secs: float, why: String) -> void:
	c.penalty += secs
	c.finish_t += secs
	c.pen_log.append({"lap": c.lap, "why": why, "secs": secs, "end": true})


func add_penalty(c, secs: float, why: String) -> void:
	c.time_pen += secs
	c.pen_log.append({"lap": c.lap + 1, "why": why, "secs": secs})
	_tally("페널티")
	BLog.add("페널티 L%d %s %d초 %s (크루 %.2f)" % [c.lap + 1, name_of(c), int(secs), why, c.crew]) # shortcut: 수정 25 진단 (릴리스가 폰에서만 잦음), 원인 확정 후 지움
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
# 비가 오는 날: 실제 비(rain)는 아무도 모른다. 팀마다 레이더 예보 = rain + 오차 (전략 능력이 높을수록, 가까울수록 정확)
const WX_RISE := 0.35    # 비가 올 때 랩마다 목표 쪽으로 다가가는 비율 (예전 전체 노면과 같음)
const WX_DRY := 0.15     # 레이싱 라인이 마르는 비율 (예전 전체 노면과 같음 → 평균 밸런스 유지)
const WX_DRY_OFF := 0.08 # 라인 밖은 차가 안 지나가 늦게 마름
const FC_RADAR := 6.0    # 이 랩 수 안쪽부터 레이더로 오차가 줄어든다


func _wx_init() -> void:
	wx_rng.seed = rng.seed ^ 0x5EED5
	sec_wet = []
	off_wet = []
	wx_k = []
	wx_dry = []
	wx_lag = []
	fc_err = {}
	var front: int = wx_rng.randi() % NS       # 비구름이 먼저 닿는 섹터
	var span: int = wx_rng.randi_range(2, NS - 1) # 같은 랩에 닿는 섹터 수 (나머지는 한 랩 늦게)
	var mk := 0.0
	var md := 0.0
	for s in NS:
		wx_k.append(wx_rng.randf_range(0.8, 1.15))
		wx_dry.append(wx_rng.randf_range(0.75, 1.3))
		wx_lag.append(0 if (wet_start or posmod(s - front, NS) < span) else 1)
		sec_wet.append(wet)
		off_wet.append(wet)
		mk += float(wx_k[s]) * float(T.share[s])
		md += float(wx_dry[s]) * float(T.share[s])
	for s in NS: # 랩 전체 평균은 1 → 평균 노면은 예전과 같고 섹터 차이만 생긴다
		wx_k[s] = float(wx_k[s]) / mk
		wx_dry[s] = float(wx_dry[s]) / md
	_fc_e(null) # 팀 예보 오차를 미리 만들어 둔다 (화면이 먼저 불러도 난수 순서가 같게)
	for c in cars:
		_fc_e(c)


## 예전 저장(섹터 노면 없음) 불러올 때: 전체 노면 값으로 채운다
func wx_fix() -> void:
	if sec_wet.size() == NS:
		return
	sec_wet = []
	off_wet = []
	wx_k = []
	wx_dry = []
	wx_lag = []
	for s in NS:
		sec_wet.append(wet)
		off_wet.append(wet)
		wx_k.append(1.0)
		wx_dry.append(1.0)
		wx_lag.append(0)


## 선두 랩마다: 섹터마다 비 목표로 다가가고, 마를 때는 라인이 먼저 → wet = 랩타임 비중 평균
func _wx_step(l: int) -> void:
	wx_fix()
	var w_sum := 0.0
	for s in NS:
		var tgt := 0.0
		var lag: int = int(wx_lag[s])
		if rain != null and l >= int(rain["start"]) + lag and l < int(rain["end"]) + lag:
			tgt = minf(1.0, float(rain["level"]) * float(wx_k[s]))
		var lw: float = sec_wet[s]
		var ow: float = off_wet[s]
		lw += (tgt - lw) * (WX_RISE if tgt > lw else WX_DRY * float(wx_dry[s]))
		ow += (tgt - ow) * (WX_RISE if tgt > ow else WX_DRY_OFF * float(wx_dry[s]))
		sec_wet[s] = clampf(lw, 0.0, 1.0)
		off_wet[s] = clampf(maxf(ow, lw), 0.0, 1.0) # 라인 밖이 라인보다 먼저 마르지는 않는다
		w_sum += float(sec_wet[s]) * float(T.share[s])
	wet = clampf(w_sum, 0.0, 1.0)


## 섹터 s 레이싱 라인 젖음
func sec_w(s: int) -> float:
	return float(sec_wet[s]) if sec_wet.size() == NS else wet


## 섹터 s 라인 밖이 라인보다 얼마나 더 젖었나 (마르는 중 = 한 줄만 마른 라인 → 추월 어려움)
func off_gap(s: int) -> float:
	return maxf(0.0, float(off_wet[s]) - float(sec_wet[s])) if off_wet.size() == NS else 0.0


## 이 컴파운드의 날씨 손해(초/랩)를 섹터별 노면으로 계산 — 한쪽만 젖어도 그 섹터 비중만큼
func wx_pen_track(comp: String) -> float:
	if sec_wet.size() != NS:
		return weather_pen(comp, wet)
	var t := 0.0
	for s in NS:
		t += weather_pen(comp, float(sec_wet[s])) * float(T.share[s])
	return t


## 팀 예보 정확도 0~1 (팀 전략·엔지니어 능력)
func fc_q(c) -> float:
	return team_eng_q(c) if c != null else 0.5


## 멀리 있을 때 비 시작·끝 랩 오차 크기 (랩)
func _fc_sd(q: float) -> float:
	return maxf(1.0, float(laps) * (0.03 + 0.09 * (1.0 - q)))


func _fc_e(c) -> Dictionary:
	var key: String = String(c.team) if c != null else ""
	if not fc_err.has(key):
		var q: float = fc_q(c)
		var sd: float = _fc_sd(q)
		fc_err[key] = {"q": q, "st": wx_rng.randfn(0.0, sd), "en": wx_rng.randfn(0.0, sd * 1.3), "lv": wx_rng.randfn(0.0, 0.06 + 0.14 * (1.0 - q))}
	return fc_err[key]


## 레이더 갱신: 선두 랩마다 오차가 조금씩 새로 섞인다 (평균 크기는 그대로) → 예보 숫자가 랩마다 움직인다
func _fc_refresh() -> void:
	for key in fc_err:
		var e: Dictionary = fc_err[key]
		var sd: float = _fc_sd(float(e["q"]))
		e["st"] = float(e["st"]) * 0.8 + wx_rng.randfn(0.0, sd * 0.6)
		e["en"] = float(e["en"]) * 0.8 + wx_rng.randfn(0.0, sd * 0.78)
		e["lv"] = float(e["lv"]) * 0.8 + wx_rng.randfn(0.0, (0.06 + 0.14 * (1.0 - float(e["q"]))) * 0.6)


## 이 팀이 믿는 비 {s 시작, e 끝, lv 세기, us·ue 불확실(랩)}: 실제 비 + 오차, 가까울수록 오차가 줄어든다. 비 없는 날 null
func fc_belief(c) -> Variant:
	if rain == null:
		return null
	var e: Dictionary = _fc_e(c)
	var sd: float = _fc_sd(float(e["q"]))
	var st := float(rain["start"])
	var en := float(rain["end"])
	var ls: float = st - float(leader_lap)
	var le: float = en - float(leader_lap)
	var ks: float = clampf(ls / FC_RADAR, 0.15, 1.0) if ls > 0.0 else 0.0 # 이미 내리면 시작은 안다
	var ke: float = clampf(le / FC_RADAR, 0.15, 1.0) if le > 0.0 else 0.0
	var bs: float = st + float(e["st"]) * ks
	var be: float = maxf(bs + 1.0, en + float(e["en"]) * ke)
	var lv: float = clampf(float(rain["level"]) + float(e["lv"]) * (ks if ls > 0.0 else 0.3), 0.2, 1.0)
	return {"s": bs, "e": be, "lv": lv, "us": maxf(0.4, sd * ks), "ue": maxf(0.4, sd * ke)}


## 이 팀 예보로 본 target 랩의 노면 (차 c 의 팀, null = 보통 팀)
func forecast_wet_at(target_lap: int, c = null) -> float:
	var b: Variant = fc_belief(c)
	if b == null:
		return wet
	var w := wet
	for l in range(leader_lap + 1, target_lap + 1):
		var tgt := 0.0
		if float(l) >= float(b["s"]) and float(l) < float(b["e"]):
			tgt = float(b["lv"])
		w = clampf(w + (tgt - w) * (WX_RISE if tgt > w else WX_DRY), 0.0, 1.0)
	return w


static func _sig(x: float) -> float:
	return 1.0 / (1.0 + exp(-1.7 * x))


## 이 팀 예보로 본 target 랩 강수확률 (%)
func forecast_prob_at(target_lap: int, c = null) -> int:
	var b: Variant = fc_belief(c)
	if b != null:
		var t := float(target_lap)
		var p_in: float = _sig((t - float(b["s"]) + 0.5) / float(b["us"])) * _sig((float(b["e"]) - t - 0.5) / float(b["ue"]))
		return clampi(int(round(5.0 + p_in * (50.0 + float(b["lv"]) * 40.0))), 5, 95)
	if fc != null and target_lap >= int(fc["lo"]) and target_lap <= int(fc["hi"]):
		# 헛예보: 가까워지면 레이더에 아무것도 없다 → 좋은 팀은 확률을 내리고, 약한 팀은 계속 믿는다
		var seen: float = clampf(float(int(fc["lo"]) - leader_lap) / FC_RADAR, 0.0, 1.0)
		var q: float = fc_q(c)
		return maxi(5, int(round(float(fc["p"]) * (seen + (1.0 - seen) * (1.0 - q) * 0.7))))
	return 25 if wet > 0.1 else 5


## 이 팀 예보로 앞으로 비가 올 만한 구간 {lo, hi, p} (확률 30% 넘는 첫·끝 랩, 최고 확률) — 없으면 null
func fc_window(c = null) -> Variant:
	var key: String = "%d|%s" % [leader_lap, String(c.team) if c != null else ""]
	if _fcw.has(key): # 화면이 자주 부르니 선두 랩마다 한 번만 계산
		return _fcw[key]
	if _fcw.size() > 8:
		_fcw.clear()
	var lo := -1
	var hi := -1
	var pm := 0
	for l in range(leader_lap + 1, laps + 1):
		var p: int = forecast_prob_at(l, c)
		if p >= 30:
			if lo < 0:
				lo = l
			hi = l
			pm = maxi(pm, p)
		elif lo >= 0:
			break
	_fcw[key] = {"lo": lo, "hi": hi, "p": pm} if lo >= 0 else null
	return _fcw[key]


## 지금 타이어 vs 대안 {alt 종류, comp 대안 컴파운드, now 대안이 랩당 몇 초 빠른가(+ = 대안이 빠름), lap 예보로 뒤집히는 랩(-1 = 12랩 안에 없음)}
func crossover(c) -> Dictionary:
	var have: String = kind_of(c.comp)
	var alt: String = "slick"
	if have == "slick":
		alt = "W" if is_wec() else "I"
	elif have == "W" and not is_wec():
		alt = "I" if wet >= 0.45 else "slick"
	var ac: String = "M" if alt == "slick" else alt
	var now: float = wx_pen_track(c.comp) - wx_pen_track(ac)
	var flip := -1
	for l in range(leader_lap + 1, mini(laps, leader_lap + 12) + 1):
		var fw: float = forecast_wet_at(l, c)
		if (weather_pen(c.comp, fw) - weather_pen(ac, fw) > 0.0) != (now > 0.0):
			flip = l
			break
	return {"alt": alt, "comp": ac, "now": now, "lap": flip}


## 드라이버 체감 무전: 대안 타이어가 빠를 것 같다고 느끼는 순간 (빗길 실력이 낮을수록 체감이 빗나감 → 이르거나 늦다)
func _xo_radio(c, left: int) -> void:
	var xo: Dictionary = crossover(c)
	var feel: float = float(xo["now"]) + wx_rng.randfn(0.0, 0.25 + maxf(0.0, 0.9 - float(c.wet)) * 1.2)
	if feel < -0.1:
		c.xo_feel = ""
		return
	if feel < 0.3 or c.xo_feel == String(xo["alt"]) or left < 2:
		return
	c.xo_feel = String(xo["alt"])
	var ss: PackedStringArray = []
	for s in xo_secs(c, String(xo["comp"])):
		ss.append("S%d" % (int(s) + 1))
	var where: String = ("" if ss.size() >= NS or ss.is_empty() else ("·".join(ss) + " "))
	if xo["alt"] == "slick":
		say(c, "%s라인이 말라가요. 지금 슬릭이 빠를 것 같아요 (체감 랩당 약 %.1f초)" % [where, feel])
	else:
		say(c, "%s그립이 없어요. %s 빠를 것 같아요 (체감 랩당 약 %.1f초)" % [where, "웻이" if xo["alt"] == "W" else "인터가", feel])


## 대안 타이어가 더 나은 섹터 번호들 (드라이버 무전·화면용)
func xo_secs(c, ac: String) -> Array:
	var out: Array = []
	for s in NS:
		if weather_pen(ac, sec_w(s)) < weather_pen(c.comp, sec_w(s)):
			out.append(s)
	return out


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
		var fill := 1.0
		if rq != null:
			tyres = bool(rq.get("tyres", true))
			drv = bool(rq.get("driver", false))
			fuel = bool(rq.get("fuel", true))
			fill = float(rq.get("fill", 1.0))
		loss = wec_stop_time(c, tyres, drv, fuel, fill) + 1.0
	loss += c.time_pen # 받은 시간 페널티는 이번 정차에서 서 있다가 해소 (apply_pit)
	var ord: Array = []
	for o in order():
		if o.dnf == "" and o.cls == c.cls:
			ord.append(o)
	var best_a: Variant = null
	var best_b: Variant = null
	var n_ahead := 0
	var ahead_ids: Array = []
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
			ahead_ids.append(o.id)
			if best_a == null or after < float(best_a[1]):
				best_a = [o, after]
		elif best_b == null or after > float(best_b[1]):
			best_b = [o, after]
	var under: Variant = null
	var i := ord.find(c)
	if i > 0:
		under = undercut_net(c, ord[i - 1])
	return {"pos": n_ahead + 1, "ahead": best_a, "behind": best_b, "loss": loss, "under": under, "ahead_ids": ahead_ids}


## 공개 정보로 본 타이어 마모율(랩당). 남의 차는 실제 마모를 모르니 달린 랩 × 컴파운드 기준값(×0.85)
func est_wear_rate(comp: String) -> float:
	return float(cpv(comp)[1]) * float(rules.get("wear_mult", 1.0)) * float(CIRC["wear"]) * (WEAR_SCALE / laps) * 0.85


func _seen_wear(o) -> float:
	return o.wear if o.mine else minf(1.0, o.stint_laps * est_wear_rate(o.comp))


## 언더컷 계산 (F1 슬릭만): att 가 지금 박스, dfn 은 한 랩 더 → net > 0 이면 att 가 앞에 나올 전망(초).
## 내 차 기회(att = 나)와 위협(dfn = 나)에 같이 쓴다. 남의 차는 공개 정보(달린 랩)로 마모 추정
func undercut_net(att, dfn) -> Variant:
	if is_wec() or sc or wet >= 0.2 or not SLICK.has(att.comp) or not SLICK.has(dfn.comp) or dfn.pit_phase != 0:
		return null # SC·젖은 노면에선 언더컷 계산이 의미 없음 (복귀 예측만)
	var k: int = att.cross.size() - 1
	if k < 0 or dfn.cross.size() <= k:
		return null
	var nc := "M"
	var ns: Variant = next_stop(att)
	if att.mine:
		nc = att.pit_req if att.pit_req != "" else (String(ns["comp"]) if ns != null else "M")
		if not SLICK.has(nc):
			nc = "M"
	elif ns != null:
		nc = String(ns["comp"])
		if not SLICK.has(nc):
			nc = "M"
	var aw: float = _seen_wear(att)
	var dw: float = _seen_wear(dfn)
	var gain_lap: float = aw * aw * float(cpv(att.comp)[2]) + cliff_pen(att.comp, aw) + float(cpv(att.comp)[0]) - float(cpv(nc)[0])
	var dfn_lap: float = dw * dw * float(cpv(dfn.comp)[2])
	var gp: float = float(att.cross[k]) - float(dfn.cross[k])
	return {"code": dfn.code if att.mine else att.code, "net": (gain_lap + dfn_lap * 0.5) * 2.0 - 1.0 - gp}


## 전략 뷰: 지금까지의 스틴트 [[comp, 시작 랩, 끝 랩]] (피트 기록에서)
func stints(o) -> Array:
	var out: Array = []
	var a := 0
	for pl in o.pit_log:
		out.append([String(pl["from"]), a, int(pl["lap"])])
		a = int(pl["lap"])
	out.append([o.comp, a, maxi(a, o.lap)])
	return out


## 전략 뷰: 공개 정보로 추정한 다음 피트 랩 [이르면, 늦으면] (없으면 null).
## F1 = 컴파운드 기준 수명(마모 0.52 근처), WEC = 탱크 한 통 거리(BoP 로 같은 클래스는 거의 같음)
func est_next_pit(o) -> Variant:
	if not o.is_running() or o.pit_phase != 0:
		return null
	var at: float
	if is_wec():
		at = o.stint_start_lap + floor(TANK / FPL)
	elif SLICK.has(o.comp):
		at = o.stint_start_lap + 0.52 / maxf(0.001, est_wear_rate(o.comp))
	else:
		return null
	if at >= laps - 1:
		return null # shortcut: F1 두 컴파운드 규정은 안 봄 — 미사용 차가 막판 피트하면 표시 없이 들어감, 필요하면 used 로 보강
	var lo: int = maxi(o.lap + 1, int(at) - 1)
	return [lo, maxi(lo, int(at) + 1)]

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
		c.awd_kph = float(eng.get("awdKph", 0.0))
		c.crew = float(t["crew"])
		c.strategy = float(t["strategy"]) + DIFF_STRAT[difficulty]
		c.drivers = e["crew"].duplicate(true)
		c.fuel = TANK
		# BoP: 커리어는 제조사(팀)별 성적으로 조정된 값 + 작은 흔들림, 퀵 레이스는 무작위
		var bop_map: Dictionary = opts.get("bop_ai", {})
		c.bop = (float(bop_map[t["name"]]) + uni(-0.0015, 0.0015)) if (not mine and bop_map.has(t["name"])) else uni(-0.004, 0.004)
		c.nerve = uni(0.5, 1.6)
		if mine:
			c.wing = snappedf(float(CIRC.get("wingOpt", 3.0)), 0.1)
			c.psi = setup_psi(setups[k] if k < setups.size() else {})
			c.tyre_every = 2
			c.driver_every = 2
			c.sc_early = false
			c.comp = String(start_comps[k]) if k < start_comps.size() else "M"
			if k < setups.size():
				c.wing = float(setups[k].get("wing", c.wing))
			if k < sets.size():
				c.tyre_sets = sets[k]
		else:
			c.wing = clampf(round(float(CIRC["wingOpt"]) + gauss(0.7)), 1.0, 5.0)
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
	c.wec_sets = wec_race_sets(c.cls)
	c.set_plan = c.tyre_every
	if not c.mine and c.cls == "HY":
		c.comp = wec_pick_set(c, laps) # 출발 노면 온도로 (수정 24 · 31)
	# 세트가 매 정차 새 타이어를 낄 만큼 있으면(2026 LMGT3 등) AI 는 더블 스틴트 대신 매번 교체
	if not c.mine and c.cls != "HY" and c.wec_sets + 1 >= int(ceil(float(laps) / STINT)):
		c.tyre_every = 1
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
		c.awd_kph = float(DB.wec["engines"].get(t.get("engine", ""), {}).get("awdKph", 0.0)) if c.cls == "HY" else 0.0
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
		c.driver_every = 2
		if c.mine:
			c.wing = snappedf(float(CIRC.get("wingOpt", 3.0)), 0.1)
			c.tyre_every = 2
			c.sc_early = false
			c.comp = String(start_comps[k]) if k < start_comps.size() else "M"
			c.psi = setup_psi(setups[k] if k < setups.size() else {})
			if k < setups.size():
				c.wing = float(setups[k].get("wing", c.wing))
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
