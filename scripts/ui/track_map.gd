extends Control
## 서킷 미니 지도 (HQ 다음 레이스 카드 등): 레이스 라인 · 출발선 · 섹터 경계 · DRS 구간을 단순하게 그린다.

const DB = preload("res://scripts/data/game_db.gd")

var key := ""
var T


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(0, 260)


func set_circuit(k: String) -> void:
	key = k
	T = DB.track(k)
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("#0f141b"))
	if T == null or T.pts.size() < 3:
		return
	var bb: Rect2 = T.bbox
	var pad := 18.0
	var s: float = minf((size.x - pad * 2) / maxf(1.0, bb.size.x), (size.y - pad * 2) / maxf(1.0, bb.size.y))
	var off: Vector2 = (size - bb.size * s) * 0.5 - bb.position * s
	var pts := PackedVector2Array()
	for p in T.pts:
		pts.append(p * s + off)
	pts.append(pts[0])
	draw_polyline(pts, Color("#2a3140"), 10.0, true)
	draw_polyline(pts, Color("#cbd5e1"), 3.0, true)
	# DRS 구간 (초록)
	for z in T.drs:
		var seg := PackedVector2Array()
		var ia: int = int(z["ia"])
		var ib: int = int(z["ib"])
		var i: int = ia
		var guard := 0
		while i != ib and guard < T.pts.size():
			seg.append(T.pts[i] * s + off)
			i = (i + 1) % T.pts.size()
			guard += 1
		if seg.size() >= 2:
			draw_polyline(seg, Color("#22c55e"), 3.0, true)
	# 섹터 경계 · 출발선
	var font: Font = get_theme_default_font()
	for si in range(1, T.sec_idx.size() - 1):
		var q: Vector2 = T.pts[int(T.sec_idx[si]) % T.pts.size()] * s + off
		draw_circle(q, 4.0, Color("#ffc53d"))
	var sf: Vector2 = T.pts[int(T.sf_at) % T.pts.size()] * s + off
	draw_rect(Rect2(sf - Vector2(6, 6), Vector2(12, 12)), Color.WHITE)
	draw_string(font, sf + Vector2(10, -8), "출발", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
