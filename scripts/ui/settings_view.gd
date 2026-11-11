extends Control
## 설정 창 (메뉴·레이스 화면의 ⚙ 버튼). 바꾸는 즉시 저장된다.

signal changed

const K = preload("res://scripts/ui/kit.gd")
const ST = preload("res://scripts/ui/settings.gd")

var _box: VBoxContainer
var _panel: PanelContainer


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
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
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(16)
	_panel.add_theme_stylebox_override("panel", sb)
	cc.add_child(_panel)
	_box = K.vbox(10)
	_panel.add_child(_box)


func open() -> void:
	_panel.custom_minimum_size = Vector2(minf(620.0, get_viewport_rect().size.x - 32.0), 0)
	visible = true
	_render()


func _render() -> void:
	K.clear(_box)
	_box.add_child(K.label("⚙ 설정", 24, K.AMBER))
	var vol: float = float(ST.get_v("volume"))
	var vl = K.label("소리 크기  %d%%" % int(round(vol * 100)), 15, K.DIM)
	_box.add_child(vl)
	var sl = HSlider.new()
	sl.min_value = 0.0
	sl.max_value = 1.0
	sl.step = 0.05
	sl.value = vol
	sl.custom_minimum_size = Vector2(0, 30)
	sl.value_changed.connect(_on_vol.bind(vl))
	_box.add_child(sl)
	_box.add_child(K.label("엔진 소리 (배경 웅웅거림)", 15, K.DIM))
	K.seg(_box, [["on", "켜기"], ["off", "끄기"]], "on" if ST.get_v("engine") else "off", _on_engine, 15)
	_box.add_child(K.label("레이스 시작 배속", 15, K.DIM))
	var items: Array = []
	for s in ST.SPEEDS:
		items.append([str(s), "%d×" % s])
	K.seg(_box, items, str(int(ST.get_v("speed"))), _on_speed, 15)
	_box.add_child(K.label("엔지니어 제안 창 (SC 피트 찬스·타이어 한계 등)", 15, K.DIM))
	K.seg(_box, [["on", "보이기"], ["off", "끄기 (무전으로만)"]], "on" if ST.get_v("prompts") else "off", _on_prompts, 15)
	K.seg(_box, [["on", "제안이 뜨면 1×로 감속"], ["off", "배속 유지"]], "on" if ST.get_v("prompt_slow") else "off", _on_slow, 15)
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


func _on_speed(v) -> void:
	ST.set_v("speed", int(v))


func _on_prompts(v) -> void:
	ST.set_v("prompts", v == "on")
	changed.emit()


func _on_slow(v) -> void:
	ST.set_v("prompt_slow", v == "on")


func _on_scale(v) -> void:
	ST.set_v("ui_scale", float(v))
	changed.emit()


func _on_close() -> void:
	visible = false
