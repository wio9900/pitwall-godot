extends Control
## 상세 순위 (랩타임 탭 아래): 화면 폭을 꽉 채우는 직접 그린 표.
## 순위 · 팀 색 · 팀/차 번호 · 드라이버 · 간격 · 최근 랩 · 타이어(랩 수) · 피트 횟수.
## 줄을 누르면 라이벌 분석, 머리줄을 누르면 간격 보기 전환.

signal car_clicked(id: int)
signal head_clicked

const RED := Color("#e10600")
const DIM := Color("#8b98a5")
const BG_A := Color("#181b22")
const BG_B := Color("#111319")
const MINE_BG := Color("#2a2410")
const ROW_H := 40.0
const HEAD_H := 34.0
const CLS_H := 30.0
const CLS_NAME := {"HY": "HYPERCAR", "P2": "LMP2", "GT": "LMGT3"}

var sim
var gap_mode := 0
var _rows: Array = []   # [y0, y1, id]
var _press_at := Vector2(-1, -1)


func _init() -> void:
	# PASS: 끌어서 스크롤은 바깥 스크롤이 받고, 제자리에서 톡 누른 것만 여기서 처리
	mouse_filter = Control.MOUSE_FILTER_PASS
	size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _short_team(n: String) -> String:
	for w in [" Racing", " Team", " Endurance", " TotalEnergies", " Hertz", " Gazoo", " THOR", " JOTA", " WRT", " Competition", " Autosports", " Oreca", " LMP2", " Magma"]:
		n = n.replace(w, "")
	return n


static func lap_short(t: float) -> String:
	if t <= 0.0:
		return "-"
	return "%d:%06.3f" % [int(t) / 60, fmod(t, 60.0)]


## 그릴 줄 목록: [종류, 값] — "cls" 클래스 머리 / "car" 차
func _lines() -> Array:
	var ord: Array = sim.order_ui()
	var out: Array = []
	if not sim.is_wec():
		for c in ord:
			out.append(["car", c])
		return out
	for k in ["HY", "P2", "GT"]:
		var first := true
		for c in ord:
			if c.cls != k:
				continue
			if first:
				out.append(["cls", k])
				first = false
			out.append(["car", c])
	return out


## 내용 높이에 맞춰 최소 높이를 정한다 (스크롤 안에서 줄이 잘리지 않게)
func refresh(gm: int) -> void:
	gap_mode = gm
	if sim == null:
		return
	var h: float = HEAD_H
	for ln in _lines():
		h += CLS_H if ln[0] == "cls" else ROW_H
	if absf(custom_minimum_size.y - h) > 1.0:
		custom_minimum_size = Vector2(0, h)
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BG_B)
	_rows.clear()
	if sim == null or sim.cars.is_empty():
		return
	var font: Font = get_theme_default_font()
	var w: float = size.x
	var fs := 17
	# 열 위치 (폭에 비례): 순위 | 팀 | 드라이버 | 간격 | 최근 랩 | 타이어 | 피트
	var x_pos := 8.0
	var x_team := 54.0
	# 좁으면(가로 화면 오른쪽 칸) 팀 이름 열을 빼고 드라이버만
	var narrow: bool = w < 640.0
	if narrow:
		fs = 16
	if narrow:
		x_team = 46.0
	var x_pit: float = w - 8.0
	var w_pit: float = 0.0 if narrow else 44.0  # 좁으면 피트 열은 뺀다 (라이벌 카드에 있음)
	var w_tyre: float = 50.0 if narrow else 72.0
	var w_last: float = 78.0 if narrow else clampf(w * 0.16, 92.0, 130.0)
	var w_gap: float = 62.0 if narrow else clampf(w * 0.15, 84.0, 130.0)
	var x_tyre: float = x_pit - w_pit - w_tyre
	var x_last: float = x_tyre - 6.0 - w_last
	var x_gap: float = x_last - 6.0 - w_gap
	var x_drv: float = x_team if narrow else x_team + (x_gap - x_team) * 0.62
	# 머리줄
	draw_rect(Rect2(0, 0, w, HEAD_H), Color("#0b0d12"))
	var hy: float = HEAD_H * 0.5 + 6
	var gap_t: String = ["앞차 ⇄", "선두 ⇄", "앞차 ⇄"][gap_mode] if narrow else ["앞차 간격 ⇄", "선두와 차이 ⇄", "앞차 간격 ⇄"][gap_mode]
	draw_string(font, Vector2(x_pos, hy), "P", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, DIM)
	if not narrow:
		draw_string(font, Vector2(x_team, hy), "팀", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, DIM)
	draw_string(font, Vector2(x_drv, hy), "드라이버", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, DIM)
	draw_string(font, Vector2(x_gap, hy), gap_t, HORIZONTAL_ALIGNMENT_RIGHT, w_gap, 14, Color("#ffc53d"))
	draw_string(font, Vector2(x_last, hy), "최근 랩", HORIZONTAL_ALIGNMENT_RIGHT, w_last, 14, DIM)
	draw_string(font, Vector2(x_tyre, hy), "타이어", HORIZONTAL_ALIGNMENT_CENTER, w_tyre, 14, DIM)
	if not narrow:
		draw_string(font, Vector2(x_pit - w_pit, hy), "피트", HORIZONTAL_ALIGNMENT_RIGHT, w_pit, 14, DIM)
	var y: float = HEAD_H
	var lead: Variant = null
	var prev: Variant = null
	var pos := 0
	for ln in _lines():
		if ln[0] == "cls":
			draw_rect(Rect2(0, y, w, CLS_H), RED)
			draw_string(font, Vector2(x_team, y + CLS_H * 0.5 + 6), CLS_NAME.get(ln[1], ln[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)
			y += CLS_H
			lead = null
			prev = null
			pos = 0
			continue
		var c = ln[1]
		pos += 1
		if lead == null:
			lead = c
		var out: bool = c.dnf != ""
		draw_rect(Rect2(0, y, w, ROW_H), MINE_BG if c.mine else (BG_A if pos % 2 == 1 else BG_B))
		var by: float = y + ROW_H * 0.5 + fs * 0.36
		var ink: Color = Color("#5d6674") if out else (Color("#ffc53d") if c.mine else Color("#e6edf3"))
		draw_string(font, Vector2(x_pos, by), str(pos), HORIZONTAL_ALIGNMENT_RIGHT, x_team - 16.0 - x_pos, fs, Color.WHITE if not out else DIM)
		draw_rect(Rect2(x_team - 10, y + 8, 4, ROW_H - 16), c.color if not out else c.color.darkened(0.6))
		var team: String = _short_team(c.team)
		if sim.is_wec():
			team += " #%d" % (c.slot + 1)
		if not narrow:
			draw_string(font, Vector2(x_team, by), team, HORIZONTAL_ALIGNMENT_LEFT, x_drv - x_team - 8, fs, ink)
		var code: String = c.code if not (narrow and sim.is_wec()) else "%s #%d" % [c.code, c.slot + 1]
		draw_string(font, Vector2(x_drv, by), code, HORIZONTAL_ALIGNMENT_LEFT, maxf(10.0, x_gap - x_drv - 4), fs, ink)
		# 간격
		var g := ""
		var gcol := Color("#e6edf3")
		if out:
			g = "OUT"
			gcol = Color("#ef4444")
		elif c.boxing != null or c.pit_phase == 2:
			g = "PIT"
			gcol = Color("#ffc53d")
		elif c == lead:
			g = "선두"
			gcol = Color("#a855f7")
		elif gap_mode == 1:
			g = sim.gap_to(c, lead)
		elif prev != null:
			g = sim.gap_to(c, prev)
		if c.time_pen > 0.0 and not out:
			g += " +%d" % int(c.time_pen)
		var gfs: int = fs
		while gfs > 11 and font.get_string_size(g, HORIZONTAL_ALIGNMENT_LEFT, -1, gfs).x > w_gap:
			gfs -= 1
		draw_string(font, Vector2(x_gap, by), g, HORIZONTAL_ALIGNMENT_RIGHT, w_gap, gfs, gcol)
		# 최근 랩 (전체 최고는 보라)
		var lcol: Color = Color("#a855f7") if c.id == sim.fastest_id else Color("#cbd5e1")
		draw_string(font, Vector2(x_last, by), lap_short(c.last_lap_t) if not out else "-", HORIZONTAL_ALIGNMENT_RIGHT, w_last, fs, lcol)
		# 타이어 + 그 타이어로 달린 랩
		if not out:
			draw_string(font, Vector2(x_tyre + 6, by), c.comp, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(sim.TYRE_HEX[c.comp]))
			draw_string(font, Vector2(x_tyre + 24, by), "%dL" % c.stint_laps, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, DIM)
		if not narrow:
			draw_string(font, Vector2(x_pit - w_pit, by), str(c.pits), HORIZONTAL_ALIGNMENT_RIGHT, w_pit, fs, DIM)
		_rows.append([y, y + ROW_H, c.id])
		prev = c
		y += ROW_H


func _gui_input(ev: InputEvent) -> void:
	if not (ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT):
		return
	if ev.pressed:
		_press_at = ev.position
		return
	var p: Vector2 = ev.position
	if _press_at.x < 0.0 or p.distance_to(_press_at) > 14.0:
		return # 끌었으면 스크롤이지 누른 게 아님
	_press_at = Vector2(-1, -1)
	if p.y < HEAD_H:
		head_clicked.emit()
		accept_event()
		return
	for r in _rows:
		if p.y >= float(r[0]) and p.y < float(r[1]):
			car_clicked.emit(int(r[2]))
			accept_event()
			return
