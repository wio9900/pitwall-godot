extends Control
## F1 중계식 순위 띠: 순위 · 팀 색 막대 · 이니셜 3글자 · 간격 · 타이어 한 글자.
## 직접 그려서 가볍고 크게 보인다. 줄을 누르면 그 차의 라이벌 분석, 머리글을 누르면 간격 보기 전환,
## WEC 는 '내 클래스 / 전체' 전환.

signal car_clicked(id: int)
signal mode_clicked

const RED := Color("#e10600")
const DIM := Color("#9aa1ad")
const BG_A := Color("#15181f")
const BG_B := Color("#0f1116")
const MINE_BG := Color("#2b2410")

var sim
var gap_mode := 0            # 0 앞차 간격 / 1 선두와 차이 / 2 직전 랩타임
var all_classes := false     # WEC: false = 내 클래스만
var _rows: Array = []        # 그린 줄 [y0, y1, car_id]
var _head_h := 54.0
var _cls_btn := Rect2()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true


func _my_cls() -> String:
	for c in sim.cars:
		if c.mine:
			return c.cls
	return ""


func _list() -> Array:
	var ord: Array = sim.order_ui()
	if not sim.is_wec():
		return ord
	if all_classes:
		var out: Array = []
		for k in ["HY", "P2", "P3", "GT"]:
			for c in ord:
				if c.cls == k:
					out.append(c)
		return out
	var mc := _my_cls()
	return ord.filter(func(c): return c.cls == mc)


## 띠가 좁아서 랩타임은 소수 첫째 자리까지 (1:23.4)
func _fmt_lap(t: float) -> String:
	if t <= 0.0:
		return "-"
	return "%d:%04.1f" % [int(t) / 60, fmod(t, 60.0)]


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BG_B)
	if sim == null or sim.cars.is_empty():
		return
	var font: Font = get_theme_default_font()
	var bold: Font = font
	var w: float = size.x
	# 머리글: 빨간 띠 + LAP · 보기 방식
	var wec: bool = sim.is_wec()
	_head_h = 58.0 if wec else 46.0
	draw_rect(Rect2(0, 0, w, 4), RED)
	var lap_now: int = mini(sim.laps, sim.leader_lap + 1)
	draw_string(bold, Vector2(10, 26), "LAP %d/%d" % [lap_now, sim.laps], HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color.WHITE)
	var mode_t: String = ["간격: 앞차 ⇄", "간격: 선두 ⇄", "직전 랩 ⇄"][gap_mode]
	draw_string(font, Vector2(10, 42), mode_t, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, DIM)
	if wec:
		var t: String = "전체 클래스 ⇄" if all_classes else "내 클래스만 ⇄"
		_cls_btn = Rect2(w * 0.5, 30, w * 0.5 - 6, 24)
		draw_string(font, Vector2(w - 8, 42), t, HORIZONTAL_ALIGNMENT_RIGHT, w * 0.5, 13, Color("#ffc53d"))
	else:
		_cls_btn = Rect2()
	# 줄
	var lst: Array = _list()
	var n: int = lst.size()
	var extra := 0
	if wec and all_classes:
		extra = 3
	var row_h: float = clampf((size.y - _head_h - 4) / maxf(1.0, float(n + extra)), 18.0, 34.0)
	var fs: int = int(clampf(row_h * 0.6, 12.0, 19.0))
	var y: float = _head_h
	_rows.clear()
	var lead: Variant = null
	var prev: Variant = null
	var last_cls := ""
	var pos := 0
	for i in n:
		var c = lst[i]
		if c.cls != last_cls:
			last_cls = c.cls
			lead = null
			prev = null
			pos = 0
			if wec and all_classes:
				draw_rect(Rect2(0, y, w, row_h * 0.8), RED.darkened(0.35))
				draw_string(bold, Vector2(8, y + row_h * 0.6), {"HY": "HYPERCAR", "P2": "LMP2", "P3": "LMP3", "GT": "LMGT3"}.get(c.cls, c.cls), HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs * 0.8), Color.WHITE)
				y += row_h * 0.8
		pos += 1
		if lead == null:
			lead = c
		if y > size.y:
			break
		var bg: Color = MINE_BG if c.mine else (BG_A if pos % 2 == 1 else BG_B)
		draw_rect(Rect2(0, y, w, row_h), bg)
		var base_y: float = y + row_h * 0.5 + fs * 0.36
		var out: bool = c.dnf != ""
		var ink: Color = Color("#5d6674") if out else (Color("#ffc53d") if c.mine else Color.WHITE)
		# 순위
		draw_string(bold, Vector2(4, base_y), str(pos), HORIZONTAL_ALIGNMENT_RIGHT, 26, fs, DIM if out else Color.WHITE)
		# 팀 색 막대
		draw_rect(Rect2(36, y + row_h * 0.18, 5, row_h * 0.64), c.color if not out else c.color.darkened(0.6))
		# 이니셜 (WEC 는 차 번호까지)
		var code: String = c.code
		draw_string(bold, Vector2(48, base_y), code, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)
		var name_end: float = 48.0 + font.get_string_size(code, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 4.0
		# 페널티는 이름 바로 뒤 작은 빨간 글씨 (간격 칸과 겹치지 않게)
		if c.time_pen > 0.0 and not out:
			var pt: String = "+%d" % int(c.time_pen)
			var pfs: int = int(fs * 0.62)
			draw_string(font, Vector2(name_end, base_y), pt, HORIZONTAL_ALIGNMENT_LEFT, -1, pfs, Color("#ef4444"))
			name_end += font.get_string_size(pt, HORIZONTAL_ALIGNMENT_LEFT, -1, pfs).x + 4.0
		name_end += 2.0
		# 간격
		var g := ""
		var gcol := Color("#e6edf3")
		if out:
			g = "OUT"
			gcol = Color("#5d6674")
		elif sim.is_pitting(c) or c.boxing != null:
			g = "PIT"
			gcol = Color("#ffc53d")
		elif gap_mode == 2:
			g = _fmt_lap(c.last_lap_t)
			if c.id == sim.fastest_id:
				gcol = Color("#a855f7")
		elif c == lead:
			g = "LEADER" if not wec else "선두"
		elif gap_mode == 0 and prev != null:
			g = sim.gap_to(c, prev)
		else:
			g = sim.gap_to(c, lead)
		var tyre_w: float = fs * 1.1
		# 간격 글자가 이름과 겹치지 않게: 남은 칸에 맞춰 글자를 줄인다
		var g_right: float = w - tyre_w - 8.0
		var room: float = maxf(12.0, g_right - name_end)
		var gfs: int = fs
		while gfs > 10 and font.get_string_size(g, HORIZONTAL_ALIGNMENT_LEFT, -1, gfs).x > room:
			gfs -= 1
		draw_string(font, Vector2(name_end, base_y), g, HORIZONTAL_ALIGNMENT_RIGHT, room, gfs, gcol)
		# 타이어 한 글자
		if not out:
			draw_string(bold, Vector2(w - tyre_w - 4, base_y), c.comp, HORIZONTAL_ALIGNMENT_CENTER, tyre_w, fs, Color(sim.TYRE_HEX[c.comp]))
		_rows.append([y, y + row_h, c.id])
		prev = c
		y += row_h


func _gui_input(ev: InputEvent) -> void:
	if not (ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT):
		return
	var p: Vector2 = ev.position
	if p.y < _head_h:
		if _cls_btn.size.x > 0.0 and _cls_btn.has_point(p):
			all_classes = not all_classes
		else:
			mode_clicked.emit()
		queue_redraw()
		accept_event()
		return
	for r in _rows:
		if p.y >= float(r[0]) and p.y < float(r[1]):
			car_clicked.emit(int(r[2]))
			accept_event()
			return
