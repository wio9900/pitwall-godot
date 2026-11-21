extends SceneTree
## 헤드리스 UI 테스트: 메인 화면을 띄워 레이스를 끝까지 돌리고 결과 화면까지 간다.
## 실행: godot --headless --path . --script res://tests/ui_smoke.gd

const DB = preload("res://scripts/data/game_db.gd")

var main
var frames := 0
var races := 0
var resumed := {}
var configs := [["monza", "dry", 1280, 720, "f1"], ["singapore", "rain", 720, 1280, "f1"], ["lemans", "auto", 1280, 720, "wec"]]


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)


func _start(i: int) -> void:
	var cfg: Array = configs[i]
	root.size = Vector2i(cfg[2], cfg[3])
	main._on_resize()
	main._on_series(cfg[4])
	main.opt_circuit.select(main.quick_keys.find(cfg[0]))
	main._on_circ_pick(0)
	main.opt_weather.select(2 if cfg[1] == "rain" else (0 if cfg[1] == "auto" else 1))
	main._on_start()
	# 박스 버튼·지시 버튼 경로도 한 번씩 지나가게
	main._on_pace("attack", 0)
	main._on_ers("deploy", 1)
	main._on_instr("defend", 0)
	main._on_plan("B", 1)
	main._on_auto(true, 1)
	print("레이스 시작: %s %s (%dx%d) %s" % cfg)


func _process(_delta: float) -> bool:
	frames += 1
	if frames == 3:
		_start(0)
	if frames < 3 or main.sim == null:
		return false
	if main.starting:
		main._update_start(1.0)
		return false
	if not main.sim.done:
		main.sim.advance(6.0)
		# 수정 20: 르망 출발 직후 그림에서 GT 가 하이퍼카 대열 안에 끼지 않아야 (같은 바퀴 안 실제 거리 순서)
		if main.sim.is_wec() and main.sim.leader_lap == 0 and main.sim.clock > 40.0 and not resumed.has("lm_draw"):
			resumed["lm_draw"] = true
			for k in 120: # 그림은 목표 거리를 부드럽게 따라가므로 수렴할 때까지
				main.race_view._update_cars(0.1)
			var hy_min := INF
			var gt_max := -INF
			for c in main.sim.cars:
				if not c.is_running() or not c.started or not main.race_view._smooth.has(c.id) or not main.race_view._smooth[c.id].has("d"):
					continue
				var dd: float = float(main.race_view._smooth[c.id]["d"])
				if c.cls == "HY":
					hy_min = minf(hy_min, dd)
				elif c.cls == "GT":
					gt_max = maxf(gt_max, dd)
			print("르망 출발 그림: 마지막 하이퍼카 %.0f · 맨 앞 GT %.0f" % [hy_min, gt_max])
			if gt_max >= hy_min:
				print("  ! 르망 출발 그림에서 GT 가 하이퍼카 대열 안에 그려짐")
				quit(1)
				return true
		# 레이스 중간 저장 → 나가기 → 이어하기 (퀵 1번째 · 커리어 레이스 각각 한 번)
		var rk: String = main.mode + str(races)
		if main.sim.leader_lap >= 3 and not resumed.has(rk) and (races == 0 or main.mode == "career"):
			resumed[rk] = true
			var lap0: int = main.sim.leader_lap
			# ⏸ 일시정지 창: 멈췄다가 계속하기
			main._open_pause()
			if main.speed_x != 0 or not main.pause_box.visible:
				print("  ! 일시정지가 멈추지 않음")
				quit(1)
				return true
			# 일시정지 중 설정: 설정 창이 일시정지 창보다 위 (#16)
			main._open_settings()
			if main.settings_view.get_index() < main.pause_box.get_index():
				print("  ! 설정 창이 일시정지 창 뒤에 깔림")
				quit(1)
				return true
			main.settings_view._on_close()
			main._close_pause()
			if main.speed_x == 0:
				print("  ! 계속하기 후에도 멈춰 있음")
				quit(1)
				return true
			main._exit_race()
			if main.sim != null or not main.RaceSaveS.has_save():
				print("  ! 나가기 후 저장 없음")
				quit(1)
				return true
			# 나가면 커리어도 메인 메뉴로
			if not main.menu_box.visible:
				print("  ! 레이스 나가기 후 메인 메뉴가 안 보임")
				quit(1)
				return true
			if main.mode == "career":
				# 커리어: 본부를 열려고 해도 본부 대신 그 랩부터 레이스가 이어져야 한다 (다시 하기로 결과 바꾸기 방지)
				main._open_hq()
				if main.hq_view.visible:
					print("  ! 저장된 커리어 레이스가 있는데 본부가 열림")
					quit(1)
					return true
			else:
				main._resume_race()
			if main.sim == null or main.sim.leader_lap != lap0:
				print("  ! 이어하기 실패")
				quit(1)
				return true
			print("이어하기 확인: %s L%d부터 (%s)" % [main.sim.CIRC["name"], lap0, main.mode])
			return false
		if frames % 40 == 0:
			main._refresh_ui()
		if frames % 300 == 0:
			if main.sim.is_wec():
				main._on_wec_box("M", 0)
				main._on_wec_box("keep", 1)
			else:
				main._on_box("H", 0)
			# 지시판 탭·버튼·엔지니어 제안·팀 오더·순위표 모드
			var rp = main.race_panel
			for t in ["drive", "pit", "power", "laps"]:
				rp._on_tab(t)
			rp._on_chip(1)
			rp._on_draft_comp("W")
			rp._on_w_tyres("no")
			rp._on_w_tyres("yes")
			if main.sim.is_wec():
				# 급유 −/+ : 가득에서 − 한 번이면 줄고, + 로 다시 가득 (지금 연료보다 아래로는 안 감)
				rp._on_w_fuel_sl(1.0)
				rp._on_w_fuel_step(-1)
				var f1: float = float(rp.draft[rp.sel]["fill"])
				rp._on_w_fuel_step(1)
				var lo: float = rp.car().fuel / main.sim.TANK
				if not (f1 <= 1.0 and f1 >= lo - 0.001 and float(rp.draft[rp.sel]["fill"]) >= f1):
					print("❌ 급유 −/+ 이상: %.3f → %.3f (하한 %.3f)" % [f1, float(rp.draft[rp.sel]["fill"]), lo])
					quit(1)
					return true
			# #19: 확대하면 차도 트랙 비율로 커진다 (전체 화면 최소 크기 이상)
			var rv = main.race_view
			var s0: float = rv._s
			var k0: float = rv._car_scale(false)
			rv._s = s0 * 8.0
			var k8: float = rv._car_scale(false)
			rv._s = s0
			var real8: float = rv.TRACK_W * s0 * 8.0 / (rv.TRACK_REAL_M * rv.CAR_U_PER_M)
			if k8 < real8 * 0.98 - 0.001 or k8 < k0:
				print("❌ 확대해도 차가 안 커짐: %.2f → %.2f" % [k0, k8])
				quit(1)
				return true
			# 18b ②③: 전체 화면에선 다른 차 이름표 숨김, 그림 차 타이어 점 위치 상수 존재
			if k0 >= rv.OTHER_LABEL_SCALE or not rv.TYRE_DOT.has("F1") or not rv.TYRE_DOT.has("HY"):
				print("❌ 다른 차 이름표 기준 또는 타이어 점 설정 이상: k0=%.2f" % k0)
				quit(1)
				return true
			rp._on_confirm()
			rp._on_cancel()
			rp._on_chip(0)
			rp._on_order("hold")
			rp._on_swap()
			rp._on_order("free")
			main._on_gap_mode()
			var mc = main.sim.my_cars()[0]
			if mc.is_running():
				main.sim.trigger_radio(mc, "WORN")
				rp.refresh()
				rp._on_prompt(1)
			rp._on_tab("pit")
			main._on_tower_click(str(main.sim.order()[1].id))
			main.rival.refresh()
			main.rival.close_card()
		return frames > 60000
	main._refresh_ui()
	main._show_result()
	if main.RaceSaveS.has_save():
		print("  ! 레이스가 끝났는데 저장이 남아 있음")
		quit(1)
		return true
	main._open_debrief()
	main.debrief._on_close()
	races += 1
	if races <= configs.size():
		print("완주: %s 우승 %s" % [main.sim.CIRC["name"], main.sim.results()[0]["car"].code])
	if races < configs.size():
		_start(races)
		return false
	if races == configs.size():
		# 커리어 흐름: 새 커리어 → 주말 → 결승 → 정산 → HQ
		root.size = Vector2i(1280, 720)
		main._on_resize()
		main.new_entry = "create"
		main._new_career()
		main._start_weekend_career()
		# 쓴 세트 칩·직접 고르기 (D-3): 미디엄 새 세트 두 번 → 쓴 세트 2개, 두 번째 세트를 골라 연습하면 그 세트만 마모가 쌓여야 함
		var v = main.wk_view
		# 공기압 −/+ 버튼 (21): 누르면 그 차 공기압이 0.5 psi 바뀌어야 함
		var psi0: Array = main.wk.my_cars().map(func(cc): return float(cc.psi))
		# 이미 최소면 − 는 그대로가 맞으니 + 도 눌러 본다 (둘 다 안 바뀌면 실패)
		var psi1: Array = psi0
		for sign_t in ["−", "+"]:
			for b in v.find_children("*", "Button", true, false):
				if b.text == sign_t and not b.disabled and b.custom_minimum_size.x == 44:
					b.pressed.emit()
					break
			psi1 = main.wk.my_cars().map(func(cc): return float(cc.psi))
			if psi1 != psi0:
				break
		if psi0 == psi1:
			print("  ! 공기압 −/+ 버튼이 값을 안 바꿈: %s" % [psi0])
			quit(1)
		print("공기압 − 버튼: %s → %s" % [psi0, psi1])
		main.wk.practice_run(0, "short", "M", "new")
		main.wk.practice_run(0, "short", "M", "new")
		var ua: Array = main.wk.used_sets[0]["M"]
		var w0: float = float(ua[0]["w"])
		v._on_pcomp("M")
		v._on_pset("used")
		v._on_pidx(1)
		var chip: String = String(v._set_items(0, "M", "")[2][1])
		v._run_practice("short")
		v.anim = null
		if ua.size() != 2 or float(ua[0]["w"]) != w0 or float(ua[1]["w"]) <= w0 or not chip.contains("%"):
			print("  ! 쓴 세트 직접 고르기 실패: %s · %s" % [chip, ua])
			quit(1)
		print("쓴 세트 칩: %s" % chip)
		v._on_pset("auto")
		main.wk.auto_practice()
		main.wk.start_quali()
		main.wk.auto_quali()
		v.refresh()
		var c0 = main.wk.my_cars()[0]
		if not c0.q3_locked and main.wk.used_n(c0.slot, c0.comp) > 0:
			v._on_start_set("used", c0.slot)
			v._on_start_idx(0, c0.slot)
			if int(main.wk.start_idx[c0.slot]) != 0:
				print("  ! 결승 출발 쓴 세트 번호 저장 실패")
				quit(1)
			v._on_start_set("auto", c0.slot)
		main._begin_race()
		print("커리어 레이스 시작: %s (%s)" % [main.sim.CIRC["name"], main.career.tier_meta()["short"]])
		return false
	print("커리어 정산 후 자금 %.2fM · 레이스 %d" % [float(main.career.hq["cash"]), int(main.career.hq["race_count"])])
	main._open_hq()
	for t in ["home", "rnd", "base", "staff", "spon", "league"]:
		main.hq_view._on_tab(t)
	main._open_season()
	main.CareerS.delete_save(main.career.save_slot)
	# WEC 커리어: 인력 탭 FA 영입 · 라인업 버튼
	main.new_series = "wec"
	main.new_entry = "select"
	main.new_team = 0
	main._new_career()
	main.hq_view._on_tab("staff")
	main.hq_view._on_wec_target(1, 0)
	main.hq_view._on_wec_hire(0)
	main.hq_view._on_wec_starter(0, 2)
	main.hq_view._on_wec_swap(1)
	main.hq_view._on_tab("league")
	main.hq_view._on_tab("home")
	main._open_settings()
	main.settings_view._on_diff("2") # 난이도는 설정에서 바꾸면 진행 중인 커리어에도 반영
	main.settings_view._on_close()
	if int(main.career.hq["difficulty"]) != 2:
		push_error("설정 난이도가 커리어에 반영되지 않음")
	var names: Array = []
	for d in main.career.my_crew(0):
		names.append(d["name"])
	print("WEC 인력 탭 · 라인업: #1 차 %s · 난이도 %d" % [names, int(main.career.hq["difficulty"])])
	main.ST.set_v("difficulty", 1)
	main.CareerS.delete_save(main.career.save_slot)
	main._open_settings()
	main.settings_view._on_scale("1.1")
	main.settings_view._on_prompts("off")
	main.settings_view._on_engine("off")
	main.settings_view._on_speed("8")
	main.settings_view._on_scale("1.0")
	main.settings_view._on_prompts("on")
	main.settings_view._on_engine("on")
	main.settings_view._on_speed("4")
	main.settings_view._on_close()
	# 메인 화면 흐름: 홈 → 커리어 슬롯 → 새 커리어 → 뒤로 → 뒤로 → 퀵 레이스
	main._show_menu()
	main._on_mode("career")
	main._open_new_career(3)
	main._on_new_series("wec")
	if main.new_series != "wec":
		print("  ! 새 커리어 WEC 선택 실패")
		quit(1)
		return true
	main._on_new_series("f1")
	main._menu_back()
	if main.menu_page != "slots":
		print("  ! 뒤로 가기가 슬롯 화면으로 가지 않음")
		quit(1)
		return true
	main._menu_back()
	main._on_mode("quick")
	if not main.quick_left.visible or main.home_box.visible:
		print("  ! 퀵 레이스 화면 전환 실패")
		quit(1)
		return true
	main._open_records()
	main.records_view._on_tab("log")
	main.records_view._on_tab("career")
	main.records_view._on_tab("circ")
	main.records_view.visible = false
	main.RecS.ensure()
	print("기록실: 레이스 %d · 서킷 %d곳" % [int(main.RecS.data["totals"]["races"]), main.RecS.data["circuits"].size()])
	if resumed.size() < 2:
		print("  ! 이어하기 테스트가 돌지 않음")
		quit(1)
		return true
	# 수정 18: data/car_art.json 의 차 그림이 전부 있어야 함 (없으면 코드 그림으로 조용히 바뀌어 모름)
	var art: Dictionary = DB.car_art
	var n_art := 0
	for cls in ["F1", "HY"]:
		for team in art.get(cls, {}):
			n_art += 1
			if not ResourceLoader.exists("res://assets/cars/%s.png" % art[cls][team]):
				print("  ! 차 그림 없음: %s %s" % [cls, team])
				quit(1)
				return true
	print("차 그림 연결 %d개 확인" % n_art)
	print("UI 테스트 통과 (%d프레임)" % frames)
	return true
