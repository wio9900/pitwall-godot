extends Control
## 레이스 전략 복기: 랩 차트(순위 변화) · 내 차 랩타임 추이 · 스틴트 요약 · 피트 결정 평가.
## 끝난 sim 을 읽어 그리기만 한다. (HTML endDebrief 를 옮기고 차트를 더함)

signal closed

const K = preload("res://scripts/ui/kit.gd")
const RS = preload("res://scripts/sim/race_sim.gd")

var sim
var _body: VBoxContainer


## 순위 차트: 가로 = 랩, 세로 = 순위(위가 1위). SC 랩은 노란 띠, 피트 랩은 점.
class PosChart extends Control:
	var sim
	var cars: Array = []  # [{car, col, width}]
	var n_pos := 20

	func _init() -> void:
		custom_minimum_size = Vector2(0, 260)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var L: int = sim.laps
		var pad := Vector2(34, 14)
		var w: float = size.x - pad.x - 12
		var h: float = size.y - pad.y - 22
		draw_rect(Rect2(Vector2.ZERO, size), Color("#0f141b"))
		var font: Font = get_theme_default_font()
		for l in sim.sc_laps:
			var x0: float = pad.x + w * (float(l) - 0.5) / L
			draw_rect(Rect2(x0, pad.y, w / L, h), Color(0.96, 0.62, 0.04, 0.18))
		for p in range(1, n_pos + 1):
			if p == 1 or p % 5 == 0:
				var y: float = pad.y + h * (p - 1) / maxf(1.0, n_pos - 1)
				draw_line(Vector2(pad.x, y), Vector2(pad.x + w, y), Color(1, 1, 1, 0.06), 1.0)
				draw_string(font, Vector2(4, y + 5), "P%d" % p, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#8b98a5"))
		for l in range(0, L + 1, maxi(1, L / 10)):
			var x: float = pad.x + w * float(l) / L
			draw_string(font, Vector2(x - 8, size.y - 4), "L%d" % l, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#8b98a5"))
		for e in cars:
			var c = e["car"]
			var col: Color = e["col"]
			var pts := PackedVector2Array()
			pts.append(_pt(0, c.grid + 1, pad, w, h, L))
			for ph in c.pos_hist:
				pts.append(_pt(int(ph["lap"]), int(ph["pos"]), pad, w, h, L))
			if pts.size() >= 2:
				draw_polyline(pts, col, float(e["width"]), true)
			for pl in c.pit_log:
				var pos_at: int = c.grid + 1
				for ph in c.pos_hist:
					if int(ph["lap"]) <= int(pl["lap"]):
						pos_at = int(ph["pos"])
				var q := _pt(int(pl["lap"]), pos_at, pad, w, h, L)
				draw_circle(q, 4.5, Color(RS.TYRE_HEX.get(pl["to"], "#ffffff")))
				draw_arc(q, 4.5, 0, TAU, 12, Color("#0b0f14"), 1.2)
			if pts.size() >= 1:
				var last: Vector2 = pts[pts.size() - 1]
				draw_string(font, last + Vector2(4, 4), String(e["tag"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)

	func _pt(lap: int, pos: int, pad: Vector2, w: float, h: float, L: int) -> Vector2:
		return Vector2(pad.x + w * float(lap) / L, pad.y + h * float(pos - 1) / maxf(1.0, n_pos - 1))


## 랩타임 차트: 내 차 랩타임 (피트 랩·첫 랩 제외), 점 색 = 타이어, 절벽 랩은 빨간 테두리
class TimeChart extends Control:
	var sim
	var cars: Array = []  # [{car, col}]

	func _init() -> void:
		custom_minimum_size = Vector2(0, 200)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color("#0f141b"))
		var font: Font = get_theme_default_font()
		var vals: Array = []
		for e in cars:
			for r in e["car"].lap_times:
				if not r["pit"] and int(r["lap"]) > 1 and not _sc_lap(int(r["lap"])):
					vals.append(float(r["t"]))
		if vals.size() < 2:
			draw_string(font, Vector2(12, 24), "랩 기록이 부족해요", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#8b98a5"))
			return
		vals.sort()
		var lo: float = vals[0] - 0.3
		var hi: float = minf(vals[vals.size() - 1], vals[int(vals.size() * 0.9)] + 2.0) + 0.3
		var L: int = sim.laps
		var pad := Vector2(52, 12)
		var w: float = size.x - pad.x - 10
		var h: float = size.y - pad.y - 22
		for k in 4:
			var tv: float = lo + (hi - lo) * k / 3.0
			var y: float = pad.y + h * (1.0 - (tv - lo) / (hi - lo))
			draw_line(Vector2(pad.x, y), Vector2(pad.x + w, y), Color(1, 1, 1, 0.06), 1.0)
			draw_string(font, Vector2(2, y + 4), K.fmt_lap(tv), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#8b98a5"))
		for l in range(0, L + 1, maxi(1, L / 10)):
			draw_string(font, Vector2(pad.x + w * float(l) / L - 8, size.y - 4), "L%d" % l, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#8b98a5"))
		for e in cars:
			var col: Color = e["col"]
			var prev: Variant = null
			for r in e["car"].lap_times:
				if r["pit"] or int(r["lap"]) <= 1 or _sc_lap(int(r["lap"])):
					prev = null
					continue
				var tv: float = clampf(float(r["t"]), lo, hi)
				var q := Vector2(pad.x + w * float(r["lap"]) / L, pad.y + h * (1.0 - (tv - lo) / (hi - lo)))
				if prev != null:
					draw_line(prev, q, Color(col, 0.7), 1.6, true)
				draw_circle(q, 3.5, Color(RS.TYRE_HEX.get(r["comp"], "#ffffff")))
				if r.get("cliff", false):
					draw_arc(q, 5.5, 0, TAU, 12, Color("#ef4444"), 1.5)
				prev = q

	func _sc_lap(l: int) -> bool:
		return sim.sc_laps.has(l) or sim.sc_laps.has(l - 1)


func open(sim_) -> void:
	sim = sim_
	if _body == null:
		_build_shell()
	_render()
	visible = true


func _build_shell() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_to_group("modal")
	var bg = ColorRect.new()
	bg.color = K.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var mc = MarginContainer.new()
	mc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		mc.add_theme_constant_override("margin_" + side, 12)
	add_child(mc)
	var v = K.vbox(8)
	mc.add_child(v)
	_body = K.scroll_v(v)
	var close = K.btn("◀ 결과로 돌아가기", 18, _on_close)
	close.custom_minimum_size = Vector2(0, 48)
	v.add_child(close)


func _on_close() -> void:
	visible = false
	closed.emit()


func _txt(parent: Control, bb: String, fs := 14) -> RichTextLabel:
	var r = K.rtl(fs)
	r.text = bb
	parent.add_child(r)
	return r


func _render() -> void:
	K.clear(_body)
	var mine: Array = sim.my_cars()
	_body.add_child(K.label("📊 레이스 전략 복기 · %s" % sim.CIRC["name"], 24, K.AMBER))
	# 같은 클래스 차들 중에서 차트에 그릴 차: 내 차 + 포디움 + 내 차 바로 앞뒤로 끝난 차
	var cls: String = mine[0].cls if not mine.is_empty() else "F1"
	var ord: Array = []
	for o in sim.order():
		if o.cls == cls:
			ord.append(o)
	var pick: Array = []
	for i in mini(3, ord.size()):
		pick.append(ord[i])
	for c in mine:
		var i := ord.find(c)
		for j in [i - 1, i + 1]:
			if j >= 0 and j < ord.size() and not pick.has(ord[j]) and not ord[j].mine:
				pick.append(ord[j])
	var chart = PosChart.new()
	chart.sim = sim
	chart.n_pos = ord.size()
	for c in pick:
		if not c.mine:
			chart.cars.append({"car": c, "col": Color(c.color, 0.75), "width": 1.6, "tag": c.code})
	var my_cols := [K.AMBER, Color("#38bdf8")]
	for c in mine:
		chart.cars.append({"car": c, "col": my_cols[c.slot % 2], "width": 3.2, "tag": c.code})
	var c1 = K.card(_body, "순위 변화 (굵은 선 = 내 차 · 점 = 피트와 새 타이어 · 노란 띠 = SC/VSC)")
	c1.add_child(chart)
	var tc = TimeChart.new()
	tc.sim = sim
	for c in mine:
		tc.cars.append({"car": c, "col": my_cols[c.slot % 2]})
	var c2 = K.card(_body, "내 차 랩타임 추이 (점 색 = 타이어 · 빨간 테두리 = 마모 절벽 · 피트·SC 랩 제외)")
	c2.add_child(tc)
	# 차별 스틴트·피트 평가
	for c in mine:
		_car_report(c, ord)


func _car_report(c, ord: Array) -> void:
	var fin: String = "DNF (%s)" % c.dnf if c.dnf != "" else "P%d" % (ord.find(c) + 1)
	var card = K.card(_body, "#%d %s (%s) · 그리드 P%d → 최종 %s" % [c.slot + 1, c.name, c.code, c.grid + 1, fin], K.AMBER)
	# 스틴트
	var stints: Array = []
	var cur: Array = []
	for r in c.lap_times:
		cur.append(r)
		if r["pit"]:
			stints.append(cur)
			cur = []
	if not cur.is_empty():
		stints.append(cur)
	var t := "[b]스틴트[/b]\n"
	for si in stints.size():
		var st: Array = stints[si]
		var tot := 0.0
		var n := 0
		var best := INF
		var cliff := false
		for r in st:
			if not r["pit"] and int(r["lap"]) > 1:
				tot += float(r["t"])
				n += 1
				best = minf(best, float(r["t"]))
			if r.get("cliff", false):
				cliff = true
		var comp: String = st[0]["comp"]
		var first_t: float = INF
		var last_t: float = INF
		for r in st:
			if not r["pit"] and int(r["lap"]) > 1:
				if first_t == INF:
					first_t = float(r["t"])
				last_t = float(r["t"])
		var deg: String = "" if first_t == INF or n < 3 else " · 첫 랩 대비 마지막 랩 [b]%+.2f초[/b]" % (last_t - first_t)
		t += "S%d [color=%s]%s[/color] %d랩 · 평균 %s · 최고 %s%s%s\n" % [si + 1, RS.TYRE_HEX[comp], RS.TYRE_KO[comp], st.size(), K.fmt_lap(tot / n) if n > 0 else "-", K.fmt_lap(best) if best < INF else "-", deg, " [color=#ef4444][절벽 구간!][/color]" if cliff else ""]
	# 피트 평가 (HTML 방식: 2랩 뒤 순위 변화로 언더컷/오버컷 판정)
	t += "[b]피트 결정 평가[/b]\n"
	if c.pit_log.is_empty():
		t += "[color=#8b98a5]• 피트 없음 (원스틴트 주행)[/color]\n"
	for ev in c.pit_log:
		var after: int = int(ev["pos"])
		for ph in c.pos_hist:
			if int(ph["lap"]) <= int(ev["lap"]) + 2:
				after = int(ph["pos"])
		var diff: int = int(ev["pos"]) - after
		var gain: float = diff * 1.45 + (8.5 if String(ev["sc"]) != "" else 0.0)
		var tag := ""
		if String(ev["sc"]) != "":
			tag = "[color=#22c55e]%s 피트 이득[/color]" % ev["sc"]
		elif diff > 0:
			tag = "[color=#22c55e]언더컷·트랙 포지션 성공 (+%d위)[/color]" % diff
		elif diff < 0:
			tag = "[color=#f59e0b]트래픽·오버컷 손실 (%d위)[/color]" % diff
		else:
			tag = "포지션 유지"
		t += "• L%d 피트 (%s→%s): %s (%+.1f초 효과)\n" % [int(ev["lap"]), ev["from"], ev["to"], tag, gain]
	var pen := ""
	if c.penalty > 0.0:
		pen = "\n[color=#ef4444]페널티 +%.0f초[/color]" % c.penalty
	t += "[color=#8b98a5]추월 %d회 · 피트 %d회 · 개인 최고 %s[/color]%s" % [c.overtakes, c.pits, K.fmt_lap(c.best) if c.best < INF else "-", pen]
	_txt(card, t, 14)
