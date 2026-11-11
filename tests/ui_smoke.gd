extends SceneTree
## 헤드리스 UI 테스트: 메인 화면을 띄워 레이스를 끝까지 돌리고 결과 화면까지 간다.
## 실행: godot --headless --path . --script res://tests/ui_smoke.gd

const DB = preload("res://scripts/data/game_db.gd")

var main
var frames := 0
var races := 0
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
		if frames % 40 == 0:
			main._refresh_ui()
		if frames % 300 == 0:
			if main.sim.is_wec():
				main._on_wec_box("M", 0)
				main._on_wec_box("keep", 1)
			else:
				main._on_box("H", 0)
		return frames > 60000
	main._refresh_ui()
	main._show_result()
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
	main.CareerS.delete_save()
	print("UI 테스트 통과 (%d프레임)" % frames)
	return true
