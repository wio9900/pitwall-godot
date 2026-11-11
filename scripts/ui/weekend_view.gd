extends Control
## 레이스 주말 화면: 연습 주행(셋업·롱런) → 예선(Q1~Q3 원랩 어택) → 그리드 확정.
## 계산은 scripts/sim/weekend.gd 가 하고, 이 화면은 버튼과 표시만 맡는다.

signal start_race
signal go_back

const K = preload("res://scripts/ui/kit.gd")
const HT = preload("res://scripts/ui/help_text.gd")
const RS = preload("res://scripts/sim/race_sim.gd")
const WK = preload("res://scripts/sim/weekend.gd")
const RaceViewS = preload("res://scripts/ui/race_view.gd")

var sim
var wk
var phase := "practice"   # practice / quali / grid
var sel := 0
var q_push := "std"
var q_traffic := "clean"
var q_comp := "S"
var anim: Variant = null  # {kind, t, dur, res, car}

var _box: BoxContainer
var _view
var _side: VBoxContainer
var _live: RichTextLabel
var _secs: HBoxContainer
var _landscape := -1


func open(sim_, wk_) -> void:
	sim = sim_
	wk = wk_
	phase = "practice"
	sel = 0
	anim = null
	q_comp = "S"
	if _view == null:
		_build_shell()
	_view.reset()
	_view.sim = sim
	_view.solo = {"car": null, "dist": 0.0}
	_on_resize()
	refresh()


func _build_shell() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var mc = MarginContainer.new()
	mc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		mc.add_theme_constant_override("margin_" + side, 10)
	add_child(mc)
	_box = BoxContainer.new()
	_box.add_theme_constant_override("separation", 10)
	mc.add_child(_box)
	var left = K.vbox(6)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.2
	_box.add_child(left)
	_live = K.rtl(18)
	left.add_child(_live)
	_secs = K.hbox(4)
	left.add_child(_secs)
	_view = RaceViewS.new()
	_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_view.custom_minimum_size = Vector2(0, 260)
	_view.clip_contents = true
	left.add_child(_view)
	_side = K.scroll_v(_box)
	_side.get_parent().size_flags_stretch_ratio = 1.0
	get_viewport().size_changed.connect(_on_resize)


func _on_resize() -> void:
	if _box == null:
		return
	var vs: Vector2 = get_viewport_rect().size
	var want := 1 if vs.x > vs.y * 1.05 else 0
	if want != _landscape:
		_landscape = want
		_box.vertical = want == 0


func _my(slot: int):
	return wk.my_cars()[slot]


# ═════════ 그리기 ═════════
func refresh() -> void:
	K.clear(_side)
	_render_secs(null, 0)
	match phase:
		"practice":
			_render_practice()
		"quali":
			_render_quali()
		_:
			_render_grid()


func _title(t: String, sub: String) -> void:
	var th = K.hbox(6)
	_side.add_child(th)
	var tl = K.label(t, 22, K.AMBER)
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	th.add_child(tl)
	var hb: String = HT.PRACTICE if phase == "practice" else (HT.QUALI if phase == "quali" else HT.GRID)
	th.add_child(K.help({"practice": "연습", "quali": "예선"}.get(phase, "그리드"), hb))
	if sub != "":
		var r = K.rtl(14)
		r.text = "[color=#8b98a5]%s[/color]" % sub
		_side.add_child(r)


func _car_tabs(cb: Callable) -> void:
	var items: Array = []
	for c in wk.my_cars():
		items.append([str(c.slot), "#%d %s" % [c.slot + 1, c.code]])
	K.seg(_side, items, str(sel), cb, 15, anim == null)


func _trait(c) -> String:
	var d: Dictionary = c.drivers[c.drv]
	var shift: float = sim.drv_wing_pref(c)
	var style := "뉴트럴 밸런스 선호"
	if shift >= 0.15:
		style = "하이 다운포스 선호 (코너 공격형)"
	elif shift <= -0.15:
		style = "로우 드래그 선호 (직선·타이어 관리형)"
	var pros: Array = []
	var cons: Array = []
	if d["speed"] >= 0.89:
		pros.append("원랩 페이스 최상급")
	if d["tyreMgmt"] >= 0.86:
		pros.append("타이어 관리 탁월")
	if d["cons"] >= 0.89:
		pros.append("실수 없는 정교함")
	if d["wet"] >= 0.89:
		pros.append("레인 마스터")
	if d["aggr"] >= 0.62:
		pros.append("과감한 추월")
	if pros.is_empty():
		pros.append("고른 기본기")
	if d["tyreMgmt"] <= 0.81:
		cons.append("타이어 마모 빠름")
	if d["aggr"] >= 0.62 and d["cons"] <= 0.85:
		cons.append("경합 실수 위험")
	if d["def"] <= 0.78:
		cons.append("방어 취약")
	if cons.is_empty():
		cons.append("뚜렷한 약점 없음")
	return "[b]%s[/b] · %s\n속도 %d · 일관 %d · 타이어 %d · 공격 %d · 방어 %d · 우천 %d\n[color=#22c55e]강점[/color] %s · [color=#ef4444]약점[/color] %s" % [
		c.name, style, int(d["speed"] * 100), int(d["cons"] * 100), int(d["tyreMgmt"] * 100), int(d["aggr"] * 100), int(d["def"] * 100), int(d["wet"] * 100),
		" · ".join(pros), " · ".join(cons)]


func _wing_desc(w: float) -> String:
	if w <= 1.8:
		return "초저저항"
	if w <= 2.6:
		return "로우 드래그"
	if w <= 3.4:
		return "미디엄"
	if w <= 4.2:
		return "하이 다운포스"
	return "최대 다운포스"


func _sets_txt(slot: int) -> String:
	var s: Dictionary = wk.sets[slot]
	return "새 타이어: [color=#ef4444]S[/color] %d · [color=#facc15]M[/color] %d · H %d (예선+결승 공용)" % [s["S"], s["M"], s["H"]]


# ── 연습 ──
func _render_practice() -> void:
	var duty: int = WK.PRACTICE_LAPS - int(wk.practice_left[0]) if wk.practice_runs.is_empty() else 0
	_title("%s 연습 주행" % sim.CIRC["name"], sim.CIRC["setupHint"] + ("  ·  스폰서 홍보 행사로 연습 %d랩 감소" % duty if duty > 0 else ""))
	_car_tabs(_on_sel)
	var c = _my(sel)
	var card = K.card(_side, "")
	var tr = K.rtl(14)
	tr.text = _trait(c)
	card.add_child(tr)
	# 윙
	var wl = K.rtl(15)
	wl.text = "윙 각도 [b]W %.1f[/b] · %s" % [c.wing, _wing_desc(c.wing)]
	card.add_child(wl)
	var sl = HSlider.new()
	sl.min_value = 1.0
	sl.max_value = 5.0
	sl.step = 0.1
	sl.value = c.wing
	sl.editable = anim == null
	sl.custom_minimum_size = Vector2(0, 28)
	sl.value_changed.connect(_on_wing.bind(wl))
	card.add_child(sl)
	card.add_child(K.label("타이어 공기압", 14, K.DIM))
	K.seg(card, [["low", "낮게"], ["std", "표준"], ["high", "높게"]], c.press, _on_press.bind(sel), 14, anim == null)
	card.add_child(K.label("연료 탑재", 14, K.DIM))
	K.seg(card, [["light", "가볍게 (-3%)"], ["std", "표준 (+2%)"], ["heavy", "넉넉하게 (+6%)"]], c.fuel_load, _on_fuel, 14, anim == null)
	var left: int = wk.practice_left[sel]
	var h = K.hbox(6)
	card.add_child(h)
	h.add_child(K.btn("셋업 테스트 (3랩)", 15, func(): _run_practice("short")))
	h.add_child(K.btn("롱런 (5랩 · 마모 측정)", 15, func(): _run_practice("long")))
	h.get_child(0).disabled = anim != null or left < 3
	h.get_child(1).disabled = anim != null or left < 5
	var info = K.rtl(14)
	info.text = "남은 연습 [b]%d랩[/b] · %s\n마모율 추정 (오차 ±%d%%%s): [color=#ef4444]S[/color] %s · [color=#facc15]M[/color] %s · H %s" % [
		left, _sets_txt(sel), int(round(float(wk.wear_est["err"]) * 100.0)), (", 롱런 %d회" % int(wk.wear_est["runs"])) if int(wk.wear_est["runs"]) > 0 else ", 미측정",
		wk.est_range_text("S"), wk.est_range_text("M"), wk.est_range_text("H")]
	card.add_child(info)
	if anim != null:
		_live.text = "[b]%s[/b] 주행 중…" % c.name
	elif wk.last_feedback != "":
		_live.text = "[color=#ffc53d]“%s”[/color]" % wk.last_feedback
	else:
		_live.text = "[color=#8b98a5]롱런을 하면 타이어 마모 추정 오차가 절반으로 줄어요 (35%→17%→9%).[/color]"
	# 기록
	if not wk.practice_runs.is_empty():
		var tc = K.card(_side, "연습 기록")
		var best := INF
		for r in wk.practice_runs:
			best = minf(best, r["best"])
		var t := ""
		for r in wk.practice_runs:
			var col := "#a855f7" if r["best"] == best else "#e6edf3"
			t += "%s  W%.1f %s  %s  [color=%s]%s[/color]  평균 %s  마모 %.1f%%/랩\n" % [r["code"], r["wing"], WK.PRESS_KO[r["press"]], "롱런" if r["kind"] == "long" else "테스트", col, K.fmt_lap(r["best"]), K.fmt_lap(r["avg"]), r["wear_lap"]]
		var rr = K.rtl(14)
		rr.text = t
		tc.add_child(rr)
	var b2 = K.hbox(6)
	_side.add_child(b2)
	b2.add_child(K.btn("⚡ 연습 자동 진행", 15, _on_auto_practice))
	b2.add_child(K.btn("셋업 확정 · 예선으로 ▶", 17, _on_to_quali))
	_side.add_child(K.btn("◀ 뒤로", 14, _on_back))


func _run_practice(kind: String) -> void:
	if anim != null:
		return
	var r: Dictionary = wk.practice_run(sel, kind)
	if r.is_empty():
		return
	anim = {"kind": "practice", "t": 0.0, "dur": 3.5 if kind == "long" else 2.4, "car": _my(sel), "laps": 3 if kind == "long" else 2}
	refresh()


# ── 예선 ──
func _render_quali() -> void:
	var st: int = wk.Q["stage"]
	var sub: String = ["", "P16 이하 탈락", "P11~15 결정 · 상위 10대 Q3 진출", "상위 10대 폴 포지션 결정전"][st]
	var ttl := "%s 예선 Q%d" % [sim.CIRC["name"], st]
	if sim.is_wec():
		sub = "클래스 상위 8대 하이퍼폴 진출 · 다른 클래스는 기록순 그리드" if st == 1 else "클래스 상위 8대 폴 포지션 결정전"
		ttl = "%s %s" % [sim.CIRC["name"], "예선" if st == 1 else "하이퍼폴"]
	_title(ttl, sub)
	var c: Variant = wk.current_car()
	if c != null:
		var card = K.card(_side, "[Q%d] #%d %s 어택 준비" % [st, c.slot + 1, c.name], K.AMBER)
		var s: Dictionary = wk.sets[c.slot]
		card.add_child(K.label("어택 타이어 (새 세트가 없으면 헌 타이어 +0.45초)", 14, K.DIM))
		K.seg(card, [["S", "소프트 (새 %d)" % s["S"]], ["M", "미디엄 (새 %d)" % s["M"]], ["H", "하드 (새 %d)" % s["H"]]], q_comp, _on_qcomp, 14, anim == null)
		card.add_child(K.label("공기압", 14, K.DIM))
		K.seg(card, [["low", "낮게"], ["std", "표준"], ["high", "높게"]], c.press, _on_press.bind(c.slot), 14, anim == null)
		card.add_child(K.label("드라이버 어택 강도", 14, K.DIM))
		K.seg(card, [["safe", "안전하게"], ["std", "표준"], ["limit", "한계까지"]], q_push, _on_qpush, 14, anim == null)
		card.add_child(K.label("피트 출주 타이밍", 14, K.DIM))
		K.seg(card, [["early", "즉시 출주"], ["clean", "클린 에어 대기"], ["late", "막판 릴리즈"]], q_traffic, _on_qtrf, 14, anim == null)
		var hint = K.rtl(13)
		hint.text = "[color=#8b98a5]한계까지 밀면 빠르지만 트랙 리밋으로 기록이 지워질 수 있어요. 막판 릴리즈는 노면이 좋아지지만 트래픽 위험이 커요. Q1·Q2를 미디엄으로 넘기면 Q3용 새 소프트를 아낄 수 있어요.[/color]"
		card.add_child(hint)
		var go = K.btn("어택 랩 출발 ▶" if anim == null else "어택 중…", 18, _run_quali_lap)
		go.disabled = anim != null
		card.add_child(go)
	if anim == null:
		_live.text = "[color=#8b98a5]섹터 색: [color=#a855f7]보라[/color] 전체 최고 · [color=#22c55e]초록[/color] 폴보다 빠름 · [color=#facc15]노랑[/color] 느림[/color]"
	_render_q_table()
	_side.add_child(K.btn("⚡ 남은 예선 자동 진행", 15, _on_auto_quali))


func _run_quali_lap() -> void:
	if anim != null:
		return
	var c: Variant = wk.current_car()
	if c == null:
		return
	var res: Dictionary = wk.my_lap(q_comp, q_push, q_traffic)
	anim = {"kind": "quali", "t": 0.0, "res": res, "car": c}
	refresh()


func _render_q_table() -> void:
	var tc = K.card(_side, "예선 순위")
	var ord: Array = wk.q_order()
	var pole: Variant = wk.pole()
	var t := ""
	var i := 0
	for c in ord:
		if sim.is_wec() and c.cls != wk.main_cls():
			continue
		i += 1
		var r: Variant = wk.Q["res"].get(c.id)
		var g := "대기"
		if r != null:
			if r["deleted"]:
				g = "Q%d 삭제" % r["stage"]
			elif pole == null or is_same(r, pole) or i == 1:
				g = K.fmt_lap(r["total"])
			else:
				g = "+%.3f" % (r["total"] - pole["total"])
		var nm_col := "#ffc53d" if c.mine else "#e6edf3"
		var out := " [color=#ef4444]OUT[/color]" if wk.Q["eliminated"].has(c.id) else ""
		var comp := ""
		if r != null:
			comp = "[color=%s]%s[/color]" % [RS.TYRE_HEX[r["q_comp"]], r["q_comp"]]
		var who: String = ("%s #%d" % [c.team, c.slot + 1]) if sim.is_wec() else c.code
		t += "%2d  [color=%s]■[/color] [color=%s]%s[/color] [color=#8b98a5]%s[/color]  %s %s  [color=#8b98a5]Q%s[/color]%s\n" % [i, K.hex(c.color), nm_col, who, c.code if sim.is_wec() else c.team, g, comp, str(r["stage"]) if r != null else "-", out]
	var rr = K.rtl(14)
	rr.text = t
	tc.add_child(rr)


func _render_secs(res: Variant, upto: int) -> void:
	K.clear(_secs)
	var best: Array = wk.best_secs(res["id"]) if res != null else []
	var pole: Variant = wk.pole() if res != null and not wk.Q.is_empty() else null
	for i in 6:
		var l = K.rtl(15)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if res == null or i >= upto:
			l.text = "[color=#5d6674]S%d[/color]" % (i + 1)
		else:
			var tt: float = res["secs"][i]
			var col := "#facc15"
			if tt <= best[i]:
				col = "#a855f7"
			elif pole != null and tt <= pole["secs"][i]:
				col = "#22c55e"
			l.text = "[color=%s][b]%.2f[/b][/color]" % [col, tt]
		_secs.add_child(l)


# ── 그리드 확정 ──
func _render_grid() -> void:
	_title("%s 스타팅 그리드 확정" % sim.CIRC["name"], "파크 페르메: 윙은 예선 셋업으로 고정. %s 진출 차는 그 세션 타이어로 출발하고, 나머지는 출발 타이어를 고를 수 있어요." % ("하이퍼폴" if sim.is_wec() else "Q3"))
	for c in wk.my_cars():
		var card = K.card(_side, "#%d %s · 그리드 P%d" % [c.slot + 1, c.name, (sim.class_pos(c) if false else c.grid + 1)], K.AMBER)
		var s: Dictionary = wk.sets[c.slot]
		var info = K.rtl(14)
		info.text = "윙 W%.1f 고정 · %s" % [c.wing, _sets_txt(c.slot)]
		card.add_child(info)
		card.add_child(K.label("출발 타이어" + (" (Q3 타이어 고정)" if c.q3_locked else " (자유 선택 · 새 세트 1개 사용)"), 14, K.DIM))
		var slot: int = c.slot
		K.seg(card, [["S", "소프트 (새 %d)" % s["S"]], ["M", "미디엄 (새 %d)" % s["M"]], ["H", "하드 (새 %d)" % s["H"]]], c.comp, _on_start_comp.bind(slot), 14, not c.q3_locked)
		card.add_child(K.label("출발 직전 공기압", 14, K.DIM))
		K.seg(card, [["low", "낮게"], ["std", "표준"], ["high", "높게"]], c.press, _on_press.bind(slot), 14)
	_render_q_table()
	_live.text = "[b]예선 종료[/b] · 폴 포지션 [color=#a855f7]%s[/color]" % sim.cars[0].code
	_side.add_child(K.btn("레이스 시작 ▶", 20, _on_start_race))


# ═════════ 버튼 처리 ═════════
func _on_sel(v) -> void:
	sel = int(v)
	refresh()


func _on_wing(v: float, wl) -> void:
	wk.set_wing(sel, v)
	wl.text = "윙 각도 [b]W %.1f[/b] · %s" % [v, _wing_desc(v)]


func _on_press(v, slot: int) -> void:
	wk.set_press(slot, v)
	refresh()


func _on_fuel(v) -> void:
	wk.set_fuel_load(sel, v)
	refresh()


func _on_qcomp(v) -> void:
	q_comp = v
	refresh()


func _on_qpush(v) -> void:
	q_push = v
	refresh()


func _on_qtrf(v) -> void:
	q_traffic = v
	refresh()


func _on_start_comp(v, slot: int) -> void:
	wk.set_start_comp(slot, v)
	refresh()


func _on_auto_practice() -> void:
	if anim == null:
		wk.auto_practice()
		refresh()


func _on_to_quali() -> void:
	if anim == null:
		phase = "quali"
		wk.start_quali()
		refresh()


func _on_auto_quali() -> void:
	if anim == null:
		wk.auto_quali()
		if wk.done_quali:
			phase = "grid"
		refresh()


func _on_back() -> void:
	go_back.emit()


func _on_start_race() -> void:
	start_race.emit()


# ═════════ 애니메이션 ═════════
func _process(delta: float) -> void:
	if anim == null or sim == null:
		return
	var T = sim.T
	if anim["kind"] == "practice":
		anim["t"] += delta
		var f: float = fmod(anim["t"] / anim["dur"] * anim["laps"], 1.0)
		_view.solo = {"car": anim["car"], "dist": f * T.L}
		if anim["t"] >= anim["dur"]:
			anim = null
			_view.solo = {"car": null, "dist": 0.0}
			refresh()
		return
	# 예선: 섹터 시간대로 한 바퀴 (시뮬레이션 10배속)
	var res: Dictionary = anim["res"]
	anim["t"] += delta * 10.0
	var acc := 0.0
	var sec := 0
	while sec < 6 and acc + float(res["secs"][sec]) <= anim["t"]:
		acc += float(res["secs"][sec])
		sec += 1
	var frac := 1.0
	var dsec := 5
	if sec < 6:
		frac = (anim["t"] - acc) / float(res["secs"][sec])
		dsec = sec
	_view.solo = {"car": anim["car"], "dist": T.dist_at(dsec, frac)}
	_render_secs(res, sec)
	var pole: Variant = wk.pole()
	var dtxt := ""
	if pole != null and sec > 0:
		var a := 0.0
		var b := 0.0
		for i in sec:
			a += float(res["secs"][i])
			b += float(pole["secs"][i])
		var d := a - b
		dtxt = "  [color=%s]%s%.3f[/color] (폴 대비)" % ["#a855f7" if d <= 0 else "#facc15", "" if d <= 0 else "+", d]
	_live.text = "[b]%s[/b]  %s%s" % [anim["car"].code, K.fmt_lap(minf(anim["t"], res["total"])), dtxt]
	if anim["t"] >= res["total"]:
		var c = anim["car"]
		anim = null
		_view.solo = {"car": null, "dist": 0.0}
		wk.commit_lap(res)
		var note: String = res["note"]
		if wk.done_quali:
			phase = "grid"
		refresh()
		var pos: int = wk.q_order().find(c) + 1
		_live.text = "[b]%s[/b] %s · Q%d 현재 P%d%s" % [c.code, "[color=#ef4444]기록 삭제[/color]" if res["deleted"] else K.fmt_lap(res["total"]), res["stage"], pos, ("  ·  " + note) if note != "" else ""]
		_render_secs(res, 6)
