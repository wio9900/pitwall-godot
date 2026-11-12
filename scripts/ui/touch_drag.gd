extends Node
## 손가락 드래그로 스크롤 (폰에서 버튼·슬라이더·글자 위를 끌어도 화면이 움직이게).
## ScrollContainer 나 RichTextLabel 의 자식으로 붙인다: Kit.drag_scroll(control).
## 세로로 14px 넘게 끌면 스크롤로 판단하고, 눌렀던 버튼은 취소한다 (가로로 끄는 슬라이더 조작은 그대로).

const TH := 14.0
const FAR := Vector2(-99999, -99999)

var target: Control
var _track := false
var _drag := false
var _p0 := Vector2.ZERO
var _s0 := 0.0


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


func _input(ev: InputEvent) -> void:
	if target == null or not target.is_visible_in_tree():
		_track = false
		return
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		if ev.position.x < -50000.0:
			return # 아래에서 만든 취소용 가짜 이벤트
		if ev.pressed:
			var gp: Vector2 = target.get_global_mouse_position()
			_track = target.get_global_rect().has_point(gp) and _hover_ok()
			_drag = false
			_p0 = gp
			_s0 = _get_scroll()
		else:
			if _drag:
				get_viewport().set_input_as_handled()
			_track = false
			_drag = false
	elif ev is InputEventMouseMotion and _track:
		var d: Vector2 = target.get_global_mouse_position() - _p0
		if not _drag:
			if absf(d.y) > TH and absf(d.y) > absf(d.x) * 1.2:
				_drag = true
				_cancel_press()
			else:
				return
		_set_scroll(_s0 - d.y)
		get_viewport().set_input_as_handled()


## 위에 다른 창(도움말·설정 등)이 덮여 있으면 아래 화면은 스크롤하지 않는다
func _hover_ok() -> bool:
	var vp = get_viewport()
	if vp == null or not vp.has_method("gui_get_hovered_control"):
		return true
	var hc: Control = vp.gui_get_hovered_control()
	return hc == null or hc == target or target.is_ancestor_of(hc)


## 처음 누른 버튼이 손을 뗄 때 눌리지 않도록, 화면 밖에서 손을 뗀 것처럼 알려준다
func _cancel_press() -> void:
	var e = InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = false
	e.position = FAR
	e.global_position = FAR
	Input.parse_input_event(e)
