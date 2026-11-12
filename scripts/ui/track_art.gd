extends Control
## 서킷 그림: 메뉴 배경(bg) · 서킷 미리보기(thumb).
## bg  = 어두운 그라데이션 + 흐르는 빛줄기 + 크게 비치는 서킷 윤곽 + 서킷을 도는 빛나는 점
## thumb = 패널 안 서킷 지도 (섹터 색·DRS·출발선)

const DB = preload("res://scripts/data/game_db.gd")

var mode := "thumb"
var key := ""
var _T = null
var _t := 0.0
var _lap_t := 0.0

const SEC_COLS := [Color("#ef4444"), Color("#38bdf8"), Color("#facc15")]


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_track(k: String) -> void:
	if k == key:
		return
	key = k
	_T = DB.track(k) if k != "" else null
	queue_redraw()


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_t += delta
	_lap_t = fmod(_lap_t + delta / 14.0, 1.0)
	queue_redraw()


func _fit(r: Rect2) -> Array:
	var bb: Rect2 = _T.bbox
	var sc: float = minf(r.size.x / maxf(1.0, bb.size.x), r.size.y / maxf(1.0, bb.size.y))
	var off: Vector2 = r.position + (r.size - bb.size * sc) * 0.5 - bb.position * sc
	return [sc, off]


func _path(sc: float, off: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in _T.pts:
		out.append(p * sc + off)
	out.append(_T.pts[0] * sc + off)
	return out


func _draw() -> void:
	if mode == "bg":
		_draw_bg()
	else:
		_draw_thumb()


func _draw_bg() -> void:
	var w: float = size.x
	var h: float = size.y
	# 그라데이션
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, h), Vector2(0, h)]),
		PackedColorArray([Color("#111a28"), Color("#0d1320"), Color("#06080c"), Color("#080b10")]))
	# 흐르는 빛줄기 (사선)
	for i in 9:
		var ph: float = fmod(_t * (0.05 + 0.02 * (i % 3)) + i * 0.137, 1.0)
		var x: float = -w * 0.3 + ph * w * 1.6
		var y: float = h * (0.1 + 0.09 * i)
		draw_line(Vector2(x, y), Vector2(x + w * 0.22, y - w * 0.06), Color(1.0, 0.77, 0.24, 0.035 + 0.02 * (i % 2)), 2.0, true)
	if _T == null:
		return
	# 서킷 윤곽: 가로 화면은 오른쪽, 세로 화면은 아래쪽에 크게
	var r: Rect2
	if w > h:
		r = Rect2(w * 0.5, h * 0.08, w * 0.47, h * 0.84)
	else:
		r = Rect2(w * 0.08, h * 0.55, w * 0.84, h * 0.4)
	var f: Array = _fit(r)
	var sc: float = f[0]
	var off: Vector2 = f[1]
	var path := _path(sc, off)
	var lw: float = clampf(sc * 11.0, 4.0, 18.0)
	draw_polyline(path, Color(1, 1, 1, 0.025), lw * 3.2, true)
	draw_polyline(path, Color(1, 1, 1, 0.06), lw, true)
	draw_polyline(path, Color(1.0, 0.77, 0.24, 0.12), 1.5, true)
	# 빛나는 점 + 꼬리
	var L: float = _T.L
	for k in 18:
		var d: float = fposmod(_lap_t * L - k * L * 0.006, L)
		var p: Vector2 = _T.point_at_dist(d) * sc + off
		var a: float = 0.55 * (1.0 - k / 18.0)
		draw_circle(p, lw * 0.35 * (1.0 - k / 24.0), Color(1.0, 0.77, 0.24, a))
	var head: Vector2 = _T.point_at_dist(_lap_t * L) * sc + off
	draw_circle(head, lw * 0.9, Color(1.0, 0.77, 0.24, 0.18))
	# 비네트
	draw_rect(Rect2(0, h * 0.85, w, h * 0.15), Color(0, 0, 0, 0.25))


func _draw_thumb() -> void:
	var w: float = size.x
	var h: float = size.y
	draw_rect(Rect2(Vector2.ZERO, size), Color("#0f141b"))
	if _T == null:
		return
	var f: Array = _fit(Rect2(14, 12, w - 28, h - 24))
	var sc: float = f[0]
	var off: Vector2 = f[1]
	var lw: float = clampf(sc * 11.0, 3.0, 10.0)
	var path := _path(sc, off)
	draw_polyline(path, Color("#1d2530"), lw * 2.4, true)
	draw_polyline(path, Color("#d7dde5"), lw * 1.15, true)
	draw_polyline(path, Color("#3a4250"), lw, true)
	# 섹터 색 띠 (2섹터씩 묶어 S1·S2·S3)
	var si: Array = _T.sec_idx
	for s3 in 3:
		var a: int = int(si[s3 * 2])
		var b: int = int(si[mini(si.size() - 1, s3 * 2 + 2)])
		var seg := PackedVector2Array()
		for i in range(a, b + 1):
			seg.append(_T.pts[i % _T.m] * sc + off)
		if seg.size() >= 2:
			draw_polyline(seg, Color(SEC_COLS[s3], 0.85), maxf(1.5, lw * 0.28), true)
	# DRS
	for z in _T.drs:
		var seg2 := PackedVector2Array()
		var j: int = z["ia"]
		var guard := 0
		while guard < _T.m:
			seg2.append(_T.pts[j] * sc + off)
			if j == z["ib"]:
				break
			j = (j + 1) % _T.m
			guard += 1
		if seg2.size() >= 2:
			draw_polyline(seg2, Color("#22c55e"), maxf(1.0, lw * 0.18), true)
	# 출발선 + 진행 방향 점
	var p0: Vector2 = _T.pts[0] * sc + off
	var n0: Vector2 = _T.nrm[0]
	draw_line(p0 - n0 * lw, p0 + n0 * lw, Color.WHITE, 2.5)
	var head: Vector2 = _T.point_at_dist(_lap_t * _T.L) * sc + off
	draw_circle(head, maxf(3.0, lw * 0.45), Color(1.0, 0.77, 0.24))
	var font: Font = get_theme_default_font()
	draw_string(font, Vector2(10, h - 8), "S1", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, SEC_COLS[0])
	draw_string(font, Vector2(32, h - 8), "S2", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, SEC_COLS[1])
	draw_string(font, Vector2(54, h - 8), "S3", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, SEC_COLS[2])
	draw_string(font, Vector2(78, h - 8), "DRS", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#22c55e"))
