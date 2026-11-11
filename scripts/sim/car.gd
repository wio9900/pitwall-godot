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
var garage := 0.0         # 개러지 수리 시간 (다음 피트에 더해짐)
var repairs := 0
var damage_now := ""
var wec_req: Variant = null
var drv_laps: Array = [0, 0, 0] # 드라이버별 완주 랩 (최소 주행 규정 확인용)
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
var wing := 3.0
var press := "std"
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
