extends SceneTree
## 화면 캡처 테스트 (CI 전용, 실제 렌더링 필요). 장면별 스크린샷을 base64 로 로그에 찍는다.
## 실행: xvfb-run godot --path . --rendering-method gl_compatibility --script res://tests/shots.gd

const DB = preload("res://scripts/data/game_db.gd")

var main
var frames := 0
var step := 0
var wait := 0
var shot_n := 0


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


func _race(circ: String, wx: String, w: int, h: int) -> void:
	root.size = Vector2i(w, h)
	main._on_resize()
	main.opt_circuit.select(DB.circuit_keys.find(circ))
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
			print("SHOTS DONE %d" % shot_n)
			return true
	return frames > 20000
