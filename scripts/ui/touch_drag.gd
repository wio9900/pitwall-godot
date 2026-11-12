extends Node
## 손가락 드래그로 스크롤 (폰에서 버튼·슬라이더·글자 위를 끌어도 화면이 움직이게).
## ScrollContainer 나 RichTextLabel 의 자식으로 붙인다: Kit.drag_scroll(control).
## 세로로 14px 넘게 끌면 스크롤로 판단하고, 눌렀던 버튼은 취소한다 (가로로 끄는 슬라이더 조작은 그대로).
## 폰은 터치 이벤트(ScreenTouch/ScreenDrag)를, PC는 마우스 이벤트를 쓴다.
## 위에 모달 창(그룹 "modal")이 떠 있고 그 안이 아니면 스크롤하지 않는다.
## 슬라이더 위에서 시작한 손가락이 세로 스크롤로 판정되면, 그 사이 슬라이더가 바뀐 값을 원래대로 되돌린다
## (셋업 슬라이더를 만진 뒤 화면을 내리다 값이 바뀌던 문제).

const TH := 14.0
const FAR := Vector2(-99999, -99999)

var target: Control
var _track := false
var _drag := false
var _p0 := Vector2.ZERO
var _s0 := 0.0
var _touch := false
var _snap: Array = []   # 누른 순간의 슬라이더 값 [[slider, value], …]


func _ready() -> void:
	_touch = DisplayServer.is_touchscreen_available()


func _get_scroll() -> float:
	if target is ScrollContainer:
		return float(target.scroll_vertical)
	if target is RichTextLabel:
		return float(target.get_v_scroll_bar().value)
	return 0.0


func _set_scroll(v: float) -> void:
	if target is ScrollContainer:
		target.scroll_vertical = int(v)
	elif target is RichTextLabel:
		target.get_v_scroll_bar().value = v


## 이벤트 위치를 target 기준 좌표로 (화면 배율 변환은 Godot 가 처리)
func _local(ev: InputEvent) -> Vector2:
	var le: InputEvent = target.make_input_local(ev)
	return le.position


func _blocked_by_modal() -> bool:
	for m in get_tree().get_nodes_in_group("modal"):
		if m is CanvasItem and m.is_visible_in_tree() and m != target and not m.is_ancestor_of(target):
			return true
	return false


func _begin(ev: InputEvent) -> void:
	var lp := _local(ev)
	_track = Rect2(Vector2.ZERO, target.size).has_point(lp) and not _blocked_by_modal()
	_drag = false
	_p0 = lp
	_s0 = _get_scroll()
	_snap.clear()
	if _track:
		for sl in target.find_children("*", "HSlider", true, false):
			if sl.is_visible_in_tree():
				_snap.append([sl, sl.value])


func _move(ev: InputEvent) -> void:
	# 스크롤해도 target 자체는 움직이지 않으므로 로컬 좌표 차이 = 손가락 이동량
	var d: Vector2 = _local(ev) - _p0
	if not _drag:
		if absf(d.y) > TH and absf(d.y) > absf(d.x) * 1.2:
			_drag = true
			_cancel_press()
			_restore_sliders()
		else:
			return
	_set_scroll(_s0 - d.y)
	get_viewport().set_input_as_handled()


func _end() -> void:
	if _drag:
		get_viewport().set_input_as_handled()
	_track = false
	_drag = false


func _input(ev: InputEvent) -> void:
	if target == null or not target.is_visible_in_tree():
		_track = false
		return
	if _touch:
		if ev is InputEventScreenTouch and ev.index == 0:
			if ev.pressed:
				_begin(ev)
			else:
				_end()
		elif ev is InputEventScreenDrag and ev.index == 0 and _track:
			_move(ev)
		elif _drag and (ev is InputEventMouseMotion or (ev is InputEventMouseButton and ev.position.x > -50000.0)):
			get_viewport().set_input_as_handled() # 끄는 동안 흉내 마우스 이벤트가 버튼·슬라이더로 가지 않게
		return
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		if ev.position.x < -50000.0:
			return # 아래에서 만든 취소용 가짜 이벤트
		if ev.pressed:
			_begin(ev)
		else:
			_end()
	elif ev is InputEventMouseMotion and _track:
		_move(ev)


## 스크롤로 판정됐으면 슬라이더를 누르기 전 값으로 (값이 바뀌었을 때만 → 연결된 설정도 함께 되돌아간다)
func _restore_sliders() -> void:
	for e in _snap:
		var sl = e[0]
		if is_instance_valid(sl) and not is_equal_approx(sl.value, float(e[1])):
			sl.value = float(e[1])
	_snap.clear()


## 처음 누른 버튼이 손을 뗄 때 눌리지 않도록, 화면 밖에서 손을 뗀 것처럼 알려준다
func _cancel_press() -> void:
	var e = InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = false
	e.position = FAR
	e.global_position = FAR
	Input.parse_input_event(e)
