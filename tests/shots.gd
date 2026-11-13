extends SceneTree
## 화면 캡처 테스트 (CI 전용, 실제 렌더링 필요). 장면별 스크린샷을 base64 로 로그에 찍는다.
## 실행: xvfb-run godot --path . --rendering-method gl_compatibility --script res://tests/shots.gd

const DB = preload("res://scripts/data/game_db.gd")

var main
var frames := 0
var step := 0
var wait := 0
var shot_n := 0
var help_btn


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	root.size = Vector2i(1280, 720)
	Engine.max_fps = 30


func _shot(name: String) -> void:
	var img: Image = root.get_texture().get_image()
	var buf: PackedByteArray = img.save_jpg_to_buffer(0.82)
	print("SHOT-BEGIN %s" % name)
	print(Marshalls.raw_to_base64(buf))
	print("SHOT-END")
	shot_n += 1


func _race(circ: String, wx: String, w: int, h: int, series: String = "f1") -> void:
	root.size = Vector2i(w, h)
	main._on_resize()
	main._on_series(series)
	main.opt_circuit.select(main.quick_keys.find(circ))
	main._on_circ_pick(0)
	main.opt_weather.select(2 if wx == "rain" else 1)
	main._on_start()


func _my0():
	return main.sim.my_cars()[0]


func _process(_delta: float) -> bool:
	frames += 1
	if wait > 0:
		wait -= 1
		return false
	match step:
		0:
			if frames > 5:
				_shot("menu_landscape")
				_race("monza", "dry", 1280, 720)
				main._update_start(3.2)
				wait = 4
				step = 1
		1:
			_shot("start_lights")
			main._update_start(10.0)
			step = 2
		2:
			main.sim.advance(1.5)
			if main.sim.leader_lap >= 3:
				main._refresh_ui()
				wait = 3
				step = 3
		3:
			_shot("race_full")
			main.race_panel._on_tab("pit")
			main.sim.trigger_radio(_my0(), "WORN")
			main._refresh_ui()
			wait = 3
			step = 44
		44:
			_shot("race_tab_pit")
			main.sim.resolve_radio(1)
			main.race_panel._on_tab("power")
			main._on_gap_mode()
			main._refresh_ui()
			wait = 3
			step = 45
		45:
			_shot("race_tab_power")
			main.race_panel._on_tab("laps")
			main._on_gap_mode()
			main._refresh_ui()
			wait = 3
			step = 46
		46:
			_shot("race_tab_laps")
			main._on_tower_click(str(main.sim.order()[0].id))
			wait = 3
			step = 48
		48:
			_shot("rival_card")
			main.rival.close_card()
			main.race_panel._on_tab("drive")
			main._on_gap_mode()
			main.race_view._rain_t = main.race_view._now - 0.5
			main.race_view._celebrate(1)
			wait = 20
			step = 40
		40:
			_shot("fx_rain_win")
			help_btn = main.KitS.help("레이스", main.HT.RACE)
			main.add_child(help_btn)
			help_btn.open()
			wait = 4
			step = 41
		41:
			_shot("help_race")
			help_btn.close_help()
			help_btn.queue_free()
			main._on_box("H", 0)
			main._set_cam(0)
			step = 4
		4:
			main.sim.advance(0.25)
			if main.race_view._stop_t.has(_my0().id) and main.sim.clock - main.race_view._stop_t[_my0().id] > 0.9:
				main._refresh_ui()
				main._set_speed(0)
				wait = 45
				step = 5
			elif main.sim.done:
				step = 6
		5:
			_shot("pit_stop_follow")
			main._set_cam(-1)
			main._set_speed(4)
			step = 6
		6:
			main.sim.advance(3.0)
			if main.sim.finishing:
				wait = 3
				step = 7
		7:
			_shot("checkered")
			step = 8
		8:
			main.sim.advance(3.0)
			if main.sim.done:
				main._refresh_ui()
				main._show_result()
				wait = 3
				step = 9
		9:
			_shot("result")
			main._open_debrief()
			wait = 4
			step = 47
		47:
			_shot("debrief")
			main.debrief._on_close()
			_race("singapore", "rain", 720, 1280)
			main._update_start(10.0)
			step = 10
		10:
			main.sim.advance(1.5)
			if main.sim.leader_lap >= 4:
				main._refresh_ui()
				wait = 3
				step = 11
		11:
			_shot("portrait_rain_night")
			main.race_panel._on_tab("laps")
			wait = 4
			step = 112
		112:
			_shot("portrait_laps")
			root.size = Vector2i(1100, 1200) # 폴드 펼친 화면 비율
			main._on_resize()
			main.race_panel._on_tab("drive")
			main._refresh_ui()
			wait = 5
			step = 113
		113:
			_shot("fold_race")
			main._autosave() # 메뉴에 '이어하기' 버튼이 보이도록
			root.size = Vector2i(1280, 720)
			main._on_resize()
			main._show_menu()
			wait = 3
			step = 60
		60:
			_shot("menu_home")
			main._on_mode("career")
			wait = 3
			step = 12
		12:
			_shot("menu_career")
			main._open_settings()
			wait = 3
			step = 49
		49:
			_shot("settings")
			main.settings_view._on_close()
			main._open_records()
			wait = 3
			step = 50
		50:
			_shot("records")
			main.records_view.visible = false
			main.new_entry = "create"
			main._open_new_career(main.new_slot)
			wait = 3
			step = 13
		13:
			_shot("menu_career_create")
			main.new_entry = "select"
			main._new_career()
			wait = 3
			step = 14
		14:
			_shot("hq_home")
			root.size = Vector2i(1100, 1200)
			main._on_resize()
			main._open_hq()
			wait = 4
			step = 114
		114:
			_shot("fold_hq_home")
			root.size = Vector2i(720, 1140) # 폴드 바깥·세로 폰
			main._on_resize()
			main._open_hq()
			wait = 4
			step = 115
		115:
			_shot("portrait_hq_home")
			root.size = Vector2i(1280, 720)
			main._on_resize()
			main._open_hq()
			main.hq_view._on_tab("rnd")
			wait = 3
			step = 15
		15:
			_shot("hq_rnd")
			main.hq_view._on_tab("staff")
			wait = 3
			step = 16
		16:
			_shot("hq_staff")
			main.hq_view._on_tab("spon")
			wait = 3
			step = 17
		17:
			_shot("hq_spon")
			main._start_weekend_career()
			wait = 3
			step = 18
		18:
			_shot("wk_practice")
			main.wk_view._run_practice("long")
			wait = 50
			step = 19
		19:
			_shot("wk_practice_run")
			wait = 60
			step = 20
		20:
			main.wk_view._on_to_quali()
			main.wk.q_advance(13.0) # 막판: 다들 트랙 위
			main.wk_view._on_q_go(0)
			main.wk_view.q_speed = 10
			wait = 120
			step = 21
		21:
			_shot("wk_quali_lap")
			main.wk_view._on_auto_quali()
			wait = 3
			step = 22
		22:
			_shot("wk_grid")
			main.wk_view._on_start_race()
			main._update_start(10.0)
			step = 23
		23:
			main.sim.advance(4.0)
			if main.sim.done:
				main._refresh_ui()
				main._show_result()
				wait = 3
				step = 24
		24:
			_shot("career_result")
			main._open_hq()
			wait = 3
			step = 25
		25:
			_shot("hq_after")
			main.career._season_summary(1, 4.2)
			main.career.hq["last_season"]["notes"] = ["💰 시즌 1 컨스트럭터 챔피언십 P1 상금 +4.20M (캡처 테스트용 가짜 결산)"]
			main._open_season()
			wait = 6
			step = 42
		42:
			_shot("season_end")
			main.new_series = "wec"
			main.new_entry = "select"
			main.new_team = 0
			main._new_career()
			main.hq_view._on_tab("staff")
			wait = 3
			step = 43
		43:
			_shot("hq_wec_staff")
			# WEC 하위 리그(LMP2) 레이스: 내 클래스만 자세한 모델, 다른 클래스는 간단 모델
			main._on_new_series("wec")
			main.new_entry = "create"
			main.new_opts["tier"] = 2
			main._new_career()
			main._start_weekend_career()
			main.wk.auto_practice()
			main.wk.start_quali()
			main.wk.auto_quali()
			main._begin_race()
			main._update_start(10.0)
			step = 70
		70:
			main.sim.advance(3.0)
			if main.sim.leader_lap >= 3:
				main._refresh_ui()
				main._set_cam(0)
				wait = 40
				step = 71
		71:
			_shot("wec_lmp2")
			main._set_cam(-1)
			main._show_menu()
			main._on_mode("quick")
			_race("lemans", "dry", 1280, 720, "wec")
			main._update_start(10.0)
			step = 26
		26:
			main.sim.advance(3.0)
			if main.sim.leader_lap >= 4:
				main._refresh_ui()
				wait = 4
				step = 27
		27:
			_shot("wec_race")
			main.race_panel._on_tab("power")
			main._set_cam(0)
			main._set_speed(0)
			wait = 40
			step = 28
		28:
			_shot("wec_follow")
			main.race_panel._on_tab("laps")
			main._refresh_ui()
			wait = 4
			step = 72
		72:
			_shot("wec_laps")
			root.size = Vector2i(1100, 1200)
			main._on_resize()
			main._refresh_ui()
			wait = 5
			step = 73
		73:
			_shot("fold_wec_race")
			root.size = Vector2i(1280, 720)
			main._on_resize()
			main.race_panel._on_tab("drive")
			main._set_speed(4)
			main._set_cam(-1)
			step = 29
		29:
			main.sim.advance(4.0)
			if main.sim.done:
				main._refresh_ui()
				main._show_result()
				wait = 3
				step = 30
		30:
			_shot("wec_result")
			root.size = Vector2i(904, 2316)
			main._on_resize()
			main._show_menu()
			wait = 4
			step = 31
		31:
			_shot("menu_fold_cover")
			main._start_weekend_quick()
			wait = 4
			step = 32
		32:
			_shot("wk_fold_cover")
			print("SHOTS DONE %d" % shot_n)
			return true
	return frames > 40000
