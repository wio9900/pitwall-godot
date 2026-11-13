extends RefCounted
## 레이스 중 차량 한 대의 상태. 로직은 race_sim.gd 에 있고 여기는 데이터만 담는다.

# 정체성
var id := 0
var cls := "F1"
var team := ""
var team_idx := 0
var color := Color.WHITE
var rim := Color.WHITE
var mine := false
var slot := 0

# 차량 성능
var aero := 0.0
var engine := 0.0
var chassis := 0.0
var rel := 0.0
var crew := 0.85
var strategy := 0.8
# WEC 전용
var label := ""           # "Toyota Gazoo Racing #1"
var perf := 0.0           # 하이퍼카·GT3 종합 성능 (BoP 후)
var bop := 0.0            # BoP 보정 (+ 느림)
var eng_eff := 1.0        # 연비 효율
var tyre_every := 2       # 몇 스틴트마다 타이어 교체
var driver_every := 2     # 몇 스틴트마다 드라이버 교대
var stint_tyre := 0
var stint_drv := 0
var wec_style := "std"    # AI 연비 성향 push / std / save
var pen_log: Array = []   # 페널티 기록 [{lap, why, secs}]
var dnf_detail := ""      # 리타이어 자세한 사유 (어디서·어떻게·상황)
var lamp_out := false     # WEC 야간 접촉으로 헤드라이트 파손 (밤에 느려지고 2랩 안에 수리 지시)
var lamp_lap := 0
var garage := 0.0         # 개러지 수리 시간 (다음 피트에 더해짐)
var repairs := 0
var damage_now := ""
var wec_req: Variant = null
var drv_laps: Array = [0, 0, 0] # 드라이버별 완주 랩 (최소 주행 규정 확인용)
var auto_swap := true       # WEC 내 차: 피트 설정의 드라이버 '교대' 선택 (자동 박스·빠른 박스도 이걸 따른다)
var wec_sets := -1          # WEC: 레이스에서 쓸 수 있는 남은 새 드라이 세트
var drv_log: Array = []     # WEC: 랩마다 운전한 드라이버 번호 (주행 시간 규정)
var drive_warned := -1      # WEC: 주행 시간 경고·위반 표시 (같은 경고 반복 방지)
var min_drive_fail := false # 내 차 WEC 피트 지시 {tyres, fuel, driver}

# 드라이버
var drivers: Array = []
var drv := 0
var name := ""
var code := ""
var speed := 0.0
var cons := 0.0
var tyre_mgmt := 0.0
var aggr := 0.0
var traits: Array = []   # 드라이버 특성 태그 (traits.gd)
var def_ := 0.0
var wet := 0.0
var tyre_deg_rate := 1.0
var fuel_burn_rate := 1.0

# 운영 상태
var plan: Dictionary = {"start": "M", "stops": []}
var stops_done := 0
var plans: Dictionary = {}   # 내 차 전략 계획 {"A": {stops, cost}, "B": ...}
var active_plan := "A"
var auto_plan := false       # 자동 전략: 계획 랩에 알아서 박스
var plans_at := -1
var sc_early := false
var sc_stay := false      # SC 때 트랙 포지션 도박 (안 들어감)
var sc_miss := false      # 전술 감각이 낮으면 SC 기회를 놓침
var undercut_try := -1    # 스톱별로 한 번만 시도
var overcut_try := -1
var traffic_try := -1
var wing := 3.0
var press := "std"
var susp := 5.5        # 서스펜션 강성 1(부드럽게)~10(단단하게)
var bbias := 57.0      # 브레이크 밸런스 앞쪽 % 52~62
var diff := 50.0       # 디퍼렌셜 잠김 % 20~80
var setup_opt: Dictionary = {}  # 이 서킷·드라이버의 숨은 최적값 (race_sim.setup_opt 이 채움)
var custom_plans := false  # 플레이어가 직접 짠 전략 (자동 재계산 안 함)
var pace := "standard"
var instr := "free"
var ers_mode := "balance"
var fuel_mode := "std"
var ers := 0.8
var tt := 0.55          # 타이어 온도 (0~1)
var wear := 0.0
var comp := "M"
var used: Dictionary = {}
var used_set_pen := 0.0   # 헌 타이어 세트 페널티 (초/랩)
var tyre_sets: Variant = null # 내 차: 주말 타이어 세트 {S, M, H} (주말 모드에서만)
var q3_locked := false     # 예선 최종 세션 타이어로 출발 고정
var fuel_load := "std"
var fuel := 0.0

# 타이밍
var cross: Array = []   # 섹터 경계 통과 시각 기록
var lap := 0
var sec := 0
var sec_start := 0.0
var sec_end := 0.0
var sec_base := 0.0
var started := false
var start_t := 0.0
var grid := 0
var stall_idx := 0

# 피트
var pits := 0
var pit_req := ""       # 플레이어 박스 지시 (원하는 컴파운드), "" = 없음
var boxing: Variant = null       # 피트 진입 확정: {comp, tyres}
var pit_phase := 0
var pit_total := 0.0
var pit_lap := false
var crew_out := false
var crew_cooldown := 0
var weather_pit := false
var covering := false
var ai_sets: Dictionary = {"S": 1, "M": 2, "H": 1}
var strat_style := "balanced"
var est_err := 1.0
var stint_start_lap := 0
var stint_start_wear := 0.0
var replan_at := -1
var stint_laps := 0

# 결과·상태
var dnf := ""
var finished := false
var finish_t := 0.0
var penalty := 0.0
var time_pen := 0.0   # 레이스 중 받은 시간 페널티 (체커기 때 더함)
var tl_warn := 0
var grid_pen := 0     # 그리드 강등 칸 수 (커리어 이벤트)      # 트랙 리밋 경고 횟수
var overtakes := 0
var best := INF
var lap_start_t := 0.0
var last_lap_t := 0.0
var drs := false
var focus := 75.0
var mech_stress := 0.0
var mech_trouble := ""
var nerve := 1.0
var radio := ""
var radio_t := -99.0
var pending_crash := ""
var pending_victim := false
var lap_hist: Array = []
var pos_hist: Array = []    # 랩별 클래스 순위 [{lap, pos}] (복기용, 잘리지 않음)
var lap_times: Array = []   # 랩별 랩타임 [{lap, t, comp, pit, cliff}] (복기용)
var pit_log: Array = []     # 피트 기록 [{lap, pos, from, to, sc}]
var cur_sec_times: Array = []
var last_sec_times: Array = []


func used_slicks() -> int:
	var n = 0
	for k in ["S", "M", "H"]:
		if used.has(k):
			n += 1
	return n


func is_running() -> bool:
	return dnf == "" and not finished
