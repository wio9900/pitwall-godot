extends Control
## 설정 창 (메뉴·레이스 화면의 ⚙ 버튼). 바꾸는 즉시 저장된다.

signal changed

const K = preload("res://scripts/ui/kit.gd")
const RS = preload("res://scripts/sim/race_sim.gd")
const ST = preload("res://scripts/ui/settings.gd")

var _box: VBoxContainer
var _panel: PanelContainer
var _scroll: ScrollContainer


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	add_to_group("modal")
	var dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var cc = CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(cc)
	_panel = PanelContainer.new()
	var sb = StyleBoxFlat.new()
	sb.bg_color = K.PANEL
	sb.border_color = K.AMBER
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(2)
	sb.set_content_margin_all(16)
	_panel.add_theme_stylebox_override("panel", sb)
	cc.add_child(_panel)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(_scroll)
	K.drag_scroll(_scroll)
	_box = K.vbox(10)
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_box)


func open() -> void:
	var vs: Vector2 = get_viewport_rect().size
	_panel.custom_minimum_size = Vector2(minf(620.0, vs.x - 32.0), 0)
	_scroll.custom_minimum_size = Vector2(0, minf(640.0, vs.y - 70.0))
	visible = true
	_render()


func _render() -> void:
	K.clear(_box)
	_box.add_child(K.label("⚙ 설정", 24, K.AMBER))
	var vol: float = float(ST.get_v("volume"))
	var vl = K.label("소리 크기  %d%%" % int(round(vol * 100)), 15, K.DIM)
	_box.add_child(vl)
	_box.add_child(K.slider(0.0, 1.0, 0.05, vol, _on_vol.bind(vl)))
	_box.add_child(K.label("엔진 소리 (배경 웅웅거림)", 15, K.DIM))
	K.seg(_box, [["on", "켜기"], ["off", "끄기"]], "on" if ST.get_v("engine") else "off", _on_engine, 15)
	_box.add_child(K.label("난이도 (AI 차의 속도·전략 판단) — 퀵 레이스와 진행 중인 커리어에 함께 적용", 15, K.DIM))
	var d_items: Array = []
	for di in RS.DIFF_KO.size():
		d_items.append([str(di), RS.DIFF_KO[di]])
	K.seg(_box, d_items, str(int(ST.get_v("difficulty"))), _on_diff, 15)
	_box.add_child(K.label("레이스 시작 배속", 15, K.DIM))
	var items: Array = []
	for s in ST.SPEEDS:
		items.append([str(s), "%d×" % s])
	K.seg(_box, items, str(int(ST.get_v("speed"))), _on_speed, 15)
	_box.add_child(K.label("엔지니어 제안 창 (SC 피트 찬스·타이어 한계 등)", 15, K.DIM))
	K.seg(_box, [["on", "보이기"], ["off", "끄기 (무전으로만)"]], "on" if ST.get_v("prompts") else "off", _on_prompts, 15)
	K.seg(_box, [["on", "제안이 뜨면 1×로 감속"], ["off", "배속 유지"]], "on" if ST.get_v("prompt_slow") else "off", _on_slow, 15)
	_box.add_child(K.label("배터리 절약 (화면 30fps · 계단 현상 보정 끔)", 15, K.DIM))
	K.seg(_box, [["off", "끔 (부드럽게)"], ["on", "켬 (오래가게)"]], "on" if ST.get_v("battery") else "off", _on_battery, 15)
	_box.add_child(K.label("성능 표시 (오른쪽 위 FPS · 처리 시간) — 끊김·발열 확인용", 15, K.DIM))
	K.seg(_box, [["off", "숨기기"], ["on", "보이기"]], "on" if ST.get_v("show_fps") else "off", _on_fps, 15)
	_box.add_child(K.label("글씨·버튼 크기", 15, K.DIM))
	K.seg(_box, [["0.9", "작게"], ["1.0", "보통"], ["1.1", "크게"], ["1.2", "아주 크게"]], "%.1f" % float(ST.get_v("ui_scale")), _on_scale, 15)
	var close = K.btn("닫기", 18, _on_close)
	close.custom_minimum_size = Vector2(0, 46)
	_box.add_child(close)


func _on_vol(v: float, vl: Label) -> void:
	ST.set_v("volume", v)
	vl.text = "소리 크기  %d%%" % int(round(v * 100))


func _on_engine(v) -> void:
	ST.set_v("engine", v == "on")
	changed.emit()


func _on_diff(v) -> void:
	ST.set_v("difficulty", int(v))
	changed.emit()


func _on_speed(v) -> void:
	ST.set_v("speed", int(v))


func _on_prompts(v) -> void:
	ST.set_v("prompts", v == "on")
	changed.emit()


func _on_slow(v) -> void:
	ST.set_v("prompt_slow", v == "on")


func _on_fps(v) -> void:
	ST.set_v("show_fps", v == "on")


func _on_battery(v) -> void:
	ST.set_v("battery", v == "on")


func _on_scale(v) -> void:
	ST.set_v("ui_scale", float(v))
	changed.emit()


func _on_close() -> void:
	visible = false
