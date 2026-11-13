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
		# 레이스 중간 저장 → 나가기 → 이어하기 (퀵 1번째 · 커리어 레이스 각각 한 번)
		var rk: String = main.mode + str(races)
		if main.sim.leader_lap >= 3 and not resumed.has(rk) and (races == 0 or main.mode == "career"):
			resumed[rk] = true
			var lap0: int = main.sim.leader_lap
			main._exit_race()
			if main.sim != null or not main.RaceSaveS.has_save():
				print("  ! 나가기 후 저장 없음")
				quit(1)
				return true
			if main.mode == "career":
				# 커리어: 나가면 본부(HQ)로 → '레이스 주말' 버튼을 눌러도 주말을 새로 시작하지 않고 그 랩부터 이어야 한다
				if not main.hq_view.visible:
					print("  ! 커리어 레이스 나가기 후 본부가 안 보임")
					quit(1)
					return true
				main._start_weekend_career()
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
		main.wk.auto_practice()
		main.wk.start_quali()
		main.wk.auto_quali()
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
	print("UI 테스트 통과 (%d프레임)" % frames)
	return true
