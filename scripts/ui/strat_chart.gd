extends Control
## 전략 뷰 스틴트 막대: 줄마다 [순위 이름 | 지난 스틴트(컴파운드 색) + 예상 다음 피트(점선 칸)], 지금 랩 세로선.
## rows: [{label, mine, sel, stints: [[comp, a, b]], est: [lo, hi] 또는 null}] — race_panel 이 채운다

const K = preload("res://scripts/ui/kit.gd")
const ROW_H := 20.0
const NAME_W := 64.0

var rows: Array = []
var laps := 1
var now_lap := 0
var tyre_hex: Dictionary = {}


func set_rows(r: Array, total: int, now: int, hexes: Dictionary) -> void:
	rows = r
	laps = maxi(1, total)
	now_lap = now
	tyre_hex = hexes
	custom_minimum_size = Vector2(0, ROW_H * rows.size() + 18.0)
	queue_redraw()


func _draw() -> void:
	var font := get_theme_default_font()
	var w: float = size.x - NAME_W - 4.0
	if w < 40.0:
		return
	var xl := func(l: float) -> float: return NAME_W + w * clampf(l / laps, 0.0, 1.0)
	# 위쪽 눈금: 1랩 · 지금 · 마지막 랩
	draw_string(font, Vector2(NAME_W, 11), "L1", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, K.DIM)
	draw_string(font, Vector2(NAME_W + w - 30, 11), "L%d" % laps, HORIZONTAL_ALIGNMENT_RIGHT, 30, 11, K.DIM)
	var nx: float = xl.call(now_lap)
	draw_string(font, Vector2(nx - 30, 11), "L%d" % now_lap, HORIZONTAL_ALIGNMENT_CENTER, 60, 11, K.INK)
	for i in rows.size():
		var r: Dictionary = rows[i]
		var y: float = 16.0 + i * ROW_H
		if r["sel"]:
			draw_rect(Rect2(0, y, size.x, ROW_H - 2), Color(K.AMBER, 0.16))
		draw_string(font, Vector2(2, y + 14), r["label"], HORIZONTAL_ALIGNMENT_LEFT, NAME_W - 4, 13, K.AMBER if r["mine"] else K.INK)
		for st in r["stints"]:
			var a: float = xl.call(float(st[1]))
			var b: float = xl.call(float(st[2]))
			if b - a < 1.0:
				continue
			draw_rect(Rect2(a, y + 4, b - a - 1.5, ROW_H - 10), Color(tyre_hex.get(st[0], "#888888")))
		if r["est"] != null:
			var ea: float = xl.call(float(r["est"][0]) - 0.5)
			var eb: float = xl.call(float(r["est"][1]) + 0.5)
			draw_rect(Rect2(ea, y + 2, eb - ea, ROW_H - 6), Color(K.INK, 0.12))
			draw_rect(Rect2(ea, y + 2, eb - ea, ROW_H - 6), Color(K.INK, 0.7), false, 1.0)
	draw_line(Vector2(nx, 14), Vector2(nx, size.y), Color(K.INK, 0.85), 1.0)
