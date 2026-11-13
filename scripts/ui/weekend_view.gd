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
var q_comp := "S"
var anim: Variant = null  # {kind, t, dur, res, car}
var plan_edit := {}       # slot → {"A": [stops], "B": [stops], "key": "A", "opt": 최적 비용, "edited": bool}

var _box: BoxContainer
var _view
var _side: VBoxContainer
var _live: RichTextLabel
var _secs: HBoxContainer
var p_comp := "M"            # 연습 주행 타이어
var q_speed := 20            # 예선 진행 속도 (실제 1초 = 세션 N초). 0 = 멈춤. 레이스와 같은 기준: 1× = 4초
var q_comps: Array = ["S", "S"]
var q_pushes: Array = ["std", "std"]
var _q_ver := -1
var _q_head: RichTextLabel
var _q_car_txt: Array = []
var _q_table: RichTextLabel
var _q_log: RichTextLabel
var _q_tick := 0.0
var _landscape := -1


func open(sim_, wk_) -> void:
	sim = sim_
	wk = wk_
	phase = "practice"
	sel = 0
	anim = null
	plan_edit = {}
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
	K.center_col(mc, 1500.0)
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
	_secs.alignment = BoxContainer.ALIGNMENT_CENTER
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
	var u: Dictionary = wk.used_sets[slot]
	return "주말 타이어 (연습·예선·결승 공용) — 새 [color=#ef4444]S[/color] %d · [color=#facc15]M[/color] %d · H %d  /  쓴 S %d · M %d · H %d" % [s["S"], s["M"], s["H"], u["S"], u["M"], u["H"]]


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
	var ed: bool = anim == null
	_setup_slider(card, c, "wing", ed)
	card.add_child(K.label("타이어 공기압", 14, K.DIM))
	K.seg(card, [["low", "낮게"], ["std", "표준"], ["high", "높게"]], c.press, _on_press.bind(sel), 14, anim == null)
	card.add_child(K.label("연료 탑재", 14, K.DIM))
	K.seg(card, [["light", "가볍게 (-3%)"], ["std", "표준 (+2%)"], ["heavy", "넉넉하게 (+6%)"]], c.fuel_load, _on_fuel, 14, anim == null)
	# 세부 셋업
	var ct: Dictionary = sim.circ_traits()
	var ag: float = clampf((c.aggr - 0.6) / 0.15, -1.0, 1.0)
	var hint := []
	hint.append("연석·저속 코너가 많아요" if ct["bump"] > 0.3 else ("고속 코너 위주의 매끈한 노면" if ct["bump"] < -0.3 else "노면·코너 성격은 중간"))
	hint.append("코너 탈출 트랙션이 중요해요" if ct["trac"] > 0.3 else ("긴 직선·고속 구간 위주" if ct["trac"] < -0.3 else "트랙션 비중 보통"))
	hint.append("%s는 브레이킹이 공격적이에요" % c.name if ag > 0.3 else ("%s는 부드럽게 브레이킹해요" % c.name if ag < -0.3 else "%s의 브레이킹은 무난해요" % c.name))
	var dh = K.rtl(13)
	dh.text = "[color=#8b98a5]세부 셋업 · 서킷: %s[/color]" % " · ".join(hint)
	card.add_child(dh)
	for key in ["susp", "bbias", "diff"]:
		_setup_slider(card, c, key, ed)
	var eb = K.btn("🔧 엔지니어 추천값으로 맞추기 (%s)" % _eng_grade(), 14, _on_engineer)
	eb.disabled = not ed
	card.add_child(eb)
	var dx = K.rtl(12)
	dx.text = "[color=#8b98a5]노란 띠 = 엔지니어 추천 범위 (엔지니어가 좋을수록 좁아요). 정답은 띠 안 어딘가에 있어요 — 가운데가 정답은 아니에요. 테스트를 달릴수록 띠가 좁아지고, 드라이버 피드백이 방향을 알려줘요. 항목마다 딱 맞으면 랩당 약 0.09초 빨라져요. 서스펜션을 단단하게·디퍼렌셜을 잠글수록 타이어 마모가 늘고, 브레이크를 뒤로 보낼수록 실수가 늘어요.[/color]"
	card.add_child(dx)
	var left: int = wk.practice_left[sel]
	# 연습 타이어: 쓴 세트가 있으면 그걸로, 없으면 새 세트를 하나 열어요
	card.add_child(K.label("연습 타이어 — 쓴 세트가 있으면 그걸로 달리고, 없으면 새 세트를 하나 열어요 (연 세트는 예선·결승에서 헌 세트)", 13, K.DIM))
	var ps: Dictionary = wk.sets[sel]
	var pu: Dictionary = wk.used_sets[sel]
	var pitems: Array = []
	for k in ["S", "M", "H"]:
		if sim.is_wec() and not sim.wec_comps(c.cls).has(k):
			continue
		pitems.append([k, "%s (새 %d·쓴 %d)" % [RS.TYRE_KO[k], int(ps[k]), int(pu[k])]])
	if not wk.has_any(sel, p_comp):
		p_comp = "M"
	K.seg(card, pitems, p_comp, _on_pcomp, 14, anim == null)
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
			t += "%s  W%.1f %s %s  %s  [color=%s]%s[/color]  평균 %s  마모 %.1f%%/랩\n" % [r["code"], r["wing"], WK.PRESS_KO[r["press"]], r.get("detail", ""), "롱런" if r["kind"] == "long" else "테스트", col, K.fmt_lap(r["best"]), K.fmt_lap(r["avg"]), r["wear_lap"]]
		var rr = K.rtl(14)
		rr.text = t
		tc.add_child(rr)
	var b2 = K.hbox(6)
	_side.add_child(b2)
	b2.add_child(K.btn("⚡ 엔지니어에게 맡기기 (자동)", 15, _on_auto_practice))
	b2.add_child(K.btn("셋업 확정 · 예선으로 ▶", 17, _on_to_quali))
	_side.add_child(K.btn("◀ 뒤로", 14, _on_back))


func _on_pcomp(v) -> void:
	p_comp = v
	refresh()


func _run_practice(kind: String) -> void:
	if anim != null:
		return
	var r: Dictionary = wk.practice_run(sel, kind, p_comp)
	if r.is_empty():
		_live.text = "[color=#ef4444]%s[/color]" % ("남은 연습 랩이 부족해요" if wk.practice_left[sel] < (5 if kind == "long" else 3) else "%s 타이어가 남아 있지 않아요" % RS.TYRE_KO[p_comp])
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
	_q_ver = int(wk.Q["ver"])
	_live.text = "[color=#8b98a5]라이브 예선 — 내 차가 어택하면 섹터 기록이 여기 떠요[/color]"
	# 세션 상태 · 진행 속도
	var hc = K.card(_side, "", K.RED)
	_q_head = K.rtl(17)
	hc.add_child(_q_head)
	# 배속 표시는 레이스 화면과 같은 기준 (1× = 시뮬레이션 4배)
	K.seg(hc, [["0", "⏸ 멈춤"], ["4", "1×"], ["20", "5×"], ["40", "10×"]], str(q_speed), _on_qspeed, 14)
	if wk.Q["stage_over"]:
		var oc = K.card(_side, "Q%d 종료" % st, K.AMBER)
		oc.add_child(K.label("탈락: %s" % ", ".join(wk.Q.get("cut_names", PackedStringArray())), 15, K.INK))
		var nb = K.btn("다음 세션 시작 ▶", 18, _on_next_stage)
		oc.add_child(nb)
	# 내 차: 차고에 있으면 타이어·강도를 골라 내보내고, 아웃랩 중이면 포기할 수 있다
	_q_car_txt = []
	for c in wk.my_cars():
		var slot: int = c.slot
		var card = K.card(_side, "#%d %s" % [slot + 1, c.name], K.AMBER)
		var stt = K.rtl(15)
		card.add_child(stt)
		_q_car_txt.append(stt)
		if not wk._participant(c, st) or wk.Q["stage_over"]:
			continue
		var ph: String = wk.q_phase(c)
		if ph == "":
			var s: Dictionary = wk.sets[slot]
			var u: Dictionary = wk.used_sets[slot]
			var items: Array = []
			var al: Array = ["S", "M", "H"]
			if sim.is_wec():
				al = ["M"] if st >= 2 else sim.wec_comps(c.cls)
			for k in al:
				if wk.has_any(slot, k):
					items.append([k, "%s (새 %d·쓴 %d)" % [RS.TYRE_KO[k], int(s[k]), int(u[k])]])
			if items.is_empty():
				card.add_child(K.label("남은 타이어가 없어요", 14, K.BAD))
				continue
			var have := false
			for it in items:
				if it[0] == q_comps[slot]:
					have = true
			if not have:
				q_comps[slot] = items[0][0]
			K.seg(card, items, q_comps[slot], _on_q_comp.bind(slot), 14)
			K.seg(card, [["safe", "안전하게"], ["std", "표준"], ["limit", "한계까지"]], q_pushes[slot], _on_q_push.bind(slot), 14)
			var go = K.btn("피트 출발 ▶", 18, _on_q_go.bind(slot))
			go.disabled = float(wk.Q["red_left"]) > 0.0 or float(wk.Q["t"]) > wk.q_last_dep()
			card.add_child(go)
		elif ph == "out":
			card.add_child(K.btn("어택 포기 · 피트로 (타이어는 이미 사용)", 14, _on_q_abort.bind(slot)))
	var tc = K.card(_side, "라이브 타이밍")
	_q_table = K.rtl(14)
	tc.add_child(_q_table)
	var lc = K.card(_side, "세션 소식")
	_q_log = K.rtl(13)
	lc.add_child(_q_log)
	var hint = K.rtl(12)
	hint.text = "[color=#8b98a5]노면은 차들이 랩을 쌓을수록 좋아져요. 막판엔 다들 나와서 트래픽이 심해지고, 레드 플래그가 나면 어택 중이던 랩은 무효예요. 체커기 %.1f분 전까지 피트를 나가야 어택을 시작할 수 있어요(아웃랩 한 바퀴). 한 번 나갈 때마다 타이어 한 세트(새 세트가 없으면 쓴 세트 +0.45초).[/color]" % wk.out_min()
	_side.add_child(hint)
	_side.add_child(K.btn("⚡ 남은 예선 자동 진행", 15, _on_auto_quali))
	_q_live_update()


func _on_qspeed(v) -> void:
	q_speed = int(v)


func _on_q_comp(v, slot: int) -> void:
	q_comps[slot] = v


func _on_q_push(v, slot: int) -> void:
	q_pushes[slot] = v


func _on_q_go(slot: int) -> void:
	var err: String = wk.player_depart(slot, q_comps[slot], q_pushes[slot])
	if err != "":
		_live.text = "[color=#ef4444]%s[/color]" % err
	if q_speed == 0:
		q_speed = 20
	refresh()


func _on_q_abort(slot: int) -> void:
	wk.player_abort(slot)
	refresh()


func _on_next_stage() -> void:
	wk.next_stage()
	refresh()


## 매 프레임: 시계·차 상태·라이브 타이밍만 글자로 갱신 (버튼은 상태가 바뀔 때만 다시 만든다)
func _q_live_update() -> void:
	if _q_head == null or wk.Q.is_empty():
		return
	var Q: Dictionary = wk.Q
	var now: Dictionary = wk.q_now()
	var red: bool = float(Q["red_left"]) > 0.0
	var flag: String = "[bgcolor=#e10600][color=#ffffff] 🟥 레드 플래그 [/color][/bgcolor]  " if red else ("[bgcolor=#1f2937][color=#ffffff] 체커기 [/color][/bgcolor]  " if float(Q["t"]) >= wk.q_len() else "")
	var last_ok: bool = float(Q["t"]) <= wk.q_last_dep()
	_q_head.text = "%s남은 시간 [font_size=26][b]%s[/b][/font_size]   트랙 위 [b]%d대[/b] · 노면 [color=%s][b]%+.2f초[/b][/color] · 트래픽 [b]%d%%[/b]%s" % [
		flag, wk.q_clock_txt(), int(now["on"]), "#22c55e" if float(now["evo"]) < -0.1 else "#facc15", float(now["evo"]), int(round(float(now["risk"]) * 160)),
		"" if last_ok else "  [color=#ef4444]· 더 나갈 수 없음[/color]"]
	var cut: int = wk._cut_n()
	for c in wk.my_cars():
		if c.slot >= _q_car_txt.size():
			continue
		var t := ""
		var r: Variant = Q["res"].get(c.id)
		var best := "기록 없음"
		if r != null and int(r["stage"]) == int(Q["stage"]):
			best = "[color=#ef4444]기록 삭제[/color]" if r["deleted"] else K.fmt_lap(float(r["total"]))
		if not wk._participant(c, Q["stage"]):
			t = "[color=#8b98a5]이번 세션 탈락 · 그리드 확정[/color]"
		else:
			var pos: int = wk.q_class_order(c).find(c) + 1
			var safe: bool = pos <= cut and r != null and int(r["stage"]) == int(Q["stage"]) and not r["deleted"]
			var ph: String = wk.q_phase(c)
			var run: Variant = Q["run"].get(c.id)
			var st_txt := "차고 대기"
			if ph == "out":
				st_txt = "[color=#22c55e]아웃랩[/color] — %d초 뒤 어택 시작" % int(maxf(0.0, (float(run["t0"]) + float(run["dur"]) - float(Q["t"])) * 60.0))
			elif ph == "push":
				st_txt = "[color=#a855f7]어택 중[/color] (%s)" % RS.TYRE_KO[run["comp"]]
			elif ph == "in":
				st_txt = "인랩"
			var pcol: String = "#22c55e" if safe else "#ef4444"
			t = "%s · 최고 [b]%s[/b] · [color=%s][b]P%d[/b][/color] %s · 이번 세션 %d번 나감" % [st_txt, best, pcol, pos, ("(진출권)" if safe else "(탈락권)") if int(Q["stage"]) < int(Q["max_stage"]) else "", int(Q["runs"].get(c.id, 0))]
		_q_car_txt[c.slot].text = t
	# 라이브 타이밍
	var tt := ""
	var ord: Array = wk.q_order()
	var i := 0
	var lead: float = -1.0
	for c in ord:
		if sim.is_wec() and c.cls != wk.main_cls():
			continue
		if not wk._participant(c, Q["stage"]):
			continue
		i += 1
		if i == cut + 1 and int(Q["stage"]) < int(Q["max_stage"]):
			tt += "[color=#e10600]──────── 탈락선 ────────[/color]\n"
		var r: Variant = Q["res"].get(c.id)
		var g := "[color=#5d6674]—[/color]"
		if r != null and int(r["stage"]) == int(Q["stage"]):
			if r["deleted"]:
				g = "[color=#ef4444]삭제[/color]"
			elif lead < 0.0:
				lead = float(r["total"])
				g = K.fmt_lap(lead)
			else:
				g = "+%.3f" % (float(r["total"]) - lead)
		var ph: String = wk.q_phase(c)
		var tag: String = {"out": " [color=#22c55e]OUT[/color]", "push": " [color=#a855f7]●어택[/color]", "in": " [color=#8b98a5]IN[/color]"}.get(ph, "")
		var nm_col := "#ffc53d" if c.mine else "#e6edf3"
		var who: String = ("%s #%d" % [c.team, c.slot + 1]) if sim.is_wec() else c.code
		tt += "%2d  [color=%s]▌[/color][color=%s]%s[/color]  %s%s\n" % [i, K.hex(c.color), nm_col, who, g, tag]
	_q_table.text = tt
	_q_log.text = "\n".join(PackedStringArray(Q["log"]))


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
	if sim.is_wec():
		_title("%s 스타팅 그리드 확정" % sim.CIRC["name"], "WEC 규정: 모든 차가 새 타이어로 출발 · 이번 대회 드라이 %s · 레이스용 새 세트는 정해진 수만큼 (더블 스틴트가 기본)" % "·".join(PackedStringArray(sim.wec_comps(wk.main_cls()))))
	else:
		_title("%s 스타팅 그리드 확정" % sim.CIRC["name"], "파크 페르메: 윙은 예선 셋업으로 고정. Q3 진출 차는 그 세션 타이어로 출발하고, 나머지는 출발 타이어를 고를 수 있어요.")
	for c in wk.my_cars():
		var card = K.card(_side, "#%d %s · 그리드 P%d" % [c.slot + 1, c.name, (sim.class_pos(c) if false else c.grid + 1)], K.AMBER)
		var s: Dictionary = wk.sets[c.slot]
		var info = K.rtl(14)
		info.text = "윙 W%.1f 고정 · %s" % [c.wing, _sets_txt(c.slot)]
		card.add_child(info)
		card.add_child(K.label("출발 타이어" + (" (Q3 타이어 고정)" if c.q3_locked else " (자유 선택 · 새 세트 1개 사용)"), 14, K.DIM))
		var slot: int = c.slot
		var sitems: Array = [["S", "소프트 (새 %d)" % s["S"]], ["M", "미디엄 (새 %d)" % s["M"]], ["H", "하드 (새 %d)" % s["H"]]]
		if sim.is_wec():
			var sal: Array = sim.wec_comps(c.cls)
			sitems = []
			for k in sal:
				sitems.append([k, "%s (새 세트)" % RS.TYRE_KO[k]])
		K.seg(card, sitems, c.comp, _on_start_comp.bind(slot), 14, not c.q3_locked)
		card.add_child(K.label("출발 직전 공기압", 14, K.DIM))
		K.seg(card, [["low", "낮게"], ["std", "표준"], ["high", "높게"]], c.press, _on_press.bind(slot), 14)
		if not sim.is_wec() and not sim.rules.get("no_pits", false):
			_plan_editor(card, c)
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


## 셋업 슬라이더 한 줄: 이름·값 + 추천 범위 띠 + 슬라이더
const SET_FMT := {"wing": "W %.1f", "susp": "%.1f", "bbias": "앞 %.1f%%", "diff": "%d%%"}
const SET_END := {"wing": ["눕힘 (직선)", "세움 (코너)"], "susp": ["부드럽게", "단단하게"], "bbias": ["뒤쪽", "앞쪽"], "diff": ["열림", "잠김"]}


func _setup_val(c, key: String) -> float:
	return float(c.wing) if key == "wing" else float(c.get(key))


func _setup_label(c, key: String) -> String:
	var lh: Array = wk.band_lohi(c.slot, key)
	var v: float = _setup_val(c, key)
	var vs: String = SET_FMT[key] % (int(v) if key == "diff" else v)
	var ls: String = SET_FMT[key] % (int(lh[0]) if key == "diff" else float(lh[0]))
	var hs: String = SET_FMT[key] % (int(lh[1]) if key == "diff" else float(lh[1]))
	var extra: String = (" · " + _wing_desc(v)) if key == "wing" else ""
	return "[b]%s[/b] %s%s   [color=#ffc53d]추천 %s ~ %s[/color]" % [RS.SETUP_KO[key], vs, extra, ls, hs]


func _setup_slider(card: VBoxContainer, c, key: String, ed: bool) -> void:
	var lab = K.rtl(14)
	lab.text = _setup_label(c, key)
	card.add_child(lab)
	var r: Array = wk._span(key)
	var bar = BandBar.new()
	var lh: Array = wk.band_lohi(c.slot, key)
	bar.lo = (float(lh[0]) - float(r[0])) / (float(r[1]) - float(r[0]))
	bar.hi = (float(lh[1]) - float(r[0])) / (float(r[1]) - float(r[0]))
	card.add_child(bar)
	var sl = K.slider(float(r[0]), float(r[1]), {"wing": 0.1, "susp": 0.1, "bbias": 0.5, "diff": 1.0}[key], _setup_val(c, key), _on_setup_val.bind(key, lab), ed)
	card.add_child(sl)
	# 양 끝 설명 (띠·슬라이더와 같은 폭이 되도록 슬라이더 아래 한 줄로)
	var row = K.hbox(6)
	card.add_child(row)
	var l0 = K.label(SET_END[key][0], 12, K.DIM)
	l0.autowrap_mode = TextServer.AUTOWRAP_OFF
	l0.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l0)
	var l1 = K.label(SET_END[key][1], 12, K.DIM)
	l1.autowrap_mode = TextServer.AUTOWRAP_OFF
	l1.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(l1)


func _on_setup_val(v: float, key: String, lab) -> void:
	if key == "wing":
		wk.set_wing(sel, v)
	else:
		wk.set_detail(sel, key, v)
	lab.text = _setup_label(_my(sel), key)


func _eng_grade() -> String:
	var q: float = wk.eng_q
	return "엔지니어 S급" if q >= 0.9 else ("A급" if q >= 0.65 else ("B급" if q >= 0.4 else "C급"))


func _on_engineer() -> void:
	if anim == null:
		wk.engineer_apply(sel)
		refresh()


## 추천 범위 띠 (슬라이더 바로 위)
class BandBar extends Control:
	var lo := 0.0
	var hi := 1.0

	func _init() -> void:
		custom_minimum_size = Vector2(0, 6)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		# 슬라이더(K.DragSlider)와 같은 눈금: 양옆 12px 안쪽
		var x0 := 12.0
		var w: float = size.x - 24.0
		draw_rect(Rect2(x0, 0, w, size.y), Color("#1b232d"))
		draw_rect(Rect2(x0 + w * lo, 0, w * (hi - lo), size.y), Color(1.0, 0.77, 0.24, 0.75))


func _small_lab(t: String) -> Label:
	var l = K.label(t, 13, K.DIM)
	l.custom_minimum_size = Vector2(64, 0)
	return l


func _seg_into(row: HBoxContainer, items: Array, cur: String, cb: Callable, enabled: bool) -> void:
	var grp = ButtonGroup.new()
	for it in items:
		var b = K.btn(String(it[1]), 13)
		b.toggle_mode = true
		b.button_group = grp
		b.button_pressed = String(it[0]) == cur
		b.disabled = not enabled
		b.pressed.connect(cb.bind(it[0]))
		row.add_child(b)


func _on_detail(v, key: String, slot: int) -> void:
	wk.set_detail(slot, key, float(v))
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


func _on_start_comp(v, slot: int) -> void:
	wk.set_start_comp(slot, v)
	if plan_edit.has(slot) and not plan_edit[slot]["edited"]:
		plan_edit.erase(slot)
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
		_view.solo = {"car": null, "dist": 0.0}
		if wk.done_quali:
			phase = "grid"
		refresh()


func _on_back() -> void:
	go_back.emit()


func _on_start_race() -> void:
	for slot in plan_edit:
		var pe: Dictionary = plan_edit[slot]
		if pe["edited"]:
			var c = _my(int(slot))
			c.active_plan = pe["key"]
			sim.set_custom_plans(c, {"A": pe["A"], "B": pe["B"]})
	wk.commit_start_tyres()
	start_race.emit()


# ── 전략 플랜 편집 (그리드) ──
func _init_plans(c) -> void:
	sim.make_plans(c)
	var pe := {"A": [], "B": [], "key": "A", "opt": 0.0, "edited": false}
	for key in ["A", "B"]:
		if c.plans.has(key):
			pe[key] = (c.plans[key]["stops"] as Array).duplicate(true)
	if c.plans.has("A"):
		pe["opt"] = float(c.plans["A"]["cost"])
	plan_edit[c.slot] = pe


func _plan_editor(card: VBoxContainer, c) -> void:
	if not plan_edit.has(c.slot):
		_init_plans(c)
	var pe: Dictionary = plan_edit[c.slot]
	var slot: int = c.slot
	var key: String = pe["key"]
	var stops: Array = pe[key]
	card.add_child(HSeparator.new())
	var hh = K.hbox(6)
	card.add_child(hh)
	var hl = K.label("전략 플랜 직접 설계", 15, K.AMBER)
	hl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hh.add_child(hl)
	hh.add_child(K.sbtn("최적 계획 불러오기", _on_plan_reset.bind(slot), true, K.GOOD))
	K.seg(card, [["A", "플랜 A (출발 계획)"], ["B", "플랜 B (예비)"]], key, _on_plan_key.bind(slot), 14)
	var sr = K.hbox(4)
	card.add_child(sr)
	sr.add_child(_small_lab("스톱 수"))
	_seg_into(sr, [["1", "1스톱"], ["2", "2스톱"], ["3", "3스톱"]], str(stops.size()), _on_plan_n.bind(slot), true)
	for i in stops.size():
		var st: Dictionary = stops[i]
		var row = K.hbox(4)
		card.add_child(row)
		row.add_child(_small_lab("%d번째" % (i + 1)))
		row.add_child(K.sbtn("−", _on_plan_lap.bind(slot, i, -1), int(st["lap"]) > 2))
		var ll = K.label("L%d" % int(st["lap"]), 15, K.INK)
		ll.custom_minimum_size = Vector2(44, 0)
		ll.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(ll)
		row.add_child(K.sbtn("+", _on_plan_lap.bind(slot, i, 1), int(st["lap"]) < sim.laps - 1))
		_seg_into(row, [["S", "S"], ["M", "M"], ["H", "H"]], String(st["comp"]), _on_plan_comp.bind(slot, i), true)
	var ev: Dictionary = sim.eval_plan(c, stops)
	var t := ""
	var parts: Array = []
	for sti in ev["stints"]:
		parts.append("[color=%s]%s[/color] L%d-%d [color=%s](끝 %d%%)[/color]" % [RS.TYRE_HEX[sti["comp"]], sti["comp"], int(sti["from"]), int(sti["to"]), "#ef4444" if sti["cliff"] else "#8b98a5", int(round(float(sti["end_wear"]) * 100))])
	t += " → ".join(parts)
	var diff: float = float(ev["cost"]) - float(pe["opt"])
	t += "\n예상 손실 [b]%.1f초[/b] · 최적 대비 %s" % [float(ev["cost"]), ("[color=#22c55e]%+.1f초[/color]" % diff) if diff <= 1.0 else ("[color=#f59e0b]%+.1f초[/color]" % diff)]
	for w in ev["warn"]:
		t += "\n[color=#ef4444]⚠ %s[/color]" % w
	t += "\n[color=#8b98a5]마모는 연습에서 잰 추정치 기준이에요 (오차 ±%d%%). 레이스 중 '피트' 탭에서 A·B를 바꾸거나 자동 피트를 켤 수 있어요.[/color]" % int(round(float(wk.wear_est["err"]) * 100.0))
	var r = K.rtl(13)
	r.text = t
	card.add_child(r)


func _plan_stops(slot: int) -> Array:
	var pe: Dictionary = plan_edit[slot]
	pe["edited"] = true
	return pe[pe["key"]]


func _on_plan_reset(slot: int) -> void:
	_init_plans(_my(slot))
	refresh()


func _on_plan_key(v, slot: int) -> void:
	plan_edit[slot]["key"] = String(v)
	plan_edit[slot]["edited"] = true
	refresh()


func _on_plan_n(v, slot: int) -> void:
	var st: Array = _plan_stops(slot)
	var n := int(v)
	var L: int = sim.laps
	while st.size() < n:
		var last: int = int(st[-1]["lap"]) if not st.is_empty() else 0
		var comp: String = "H" if st.is_empty() or String(st[-1]["comp"]) != "H" else "M"
		st.append({"lap": mini(L - 1, last + maxi(2, int((L - last) / 2.0))), "comp": comp})
	while st.size() > n:
		st.pop_back()
	# 균등 분할로 다시 배치
	for i in st.size():
		st[i]["lap"] = clampi(int(round(L * (i + 1) / float(n + 1))), 2, L - 1)
	refresh()


func _on_plan_lap(slot: int, i: int, d: int) -> void:
	var st: Array = _plan_stops(slot)
	var lo: int = (int(st[i - 1]["lap"]) + 1) if i > 0 else 2
	var hi: int = (int(st[i + 1]["lap"]) - 1) if i + 1 < st.size() else sim.laps - 1
	st[i]["lap"] = clampi(int(st[i]["lap"]) + d, lo, hi)
	refresh()


func _on_plan_comp(v, slot: int, i: int) -> void:
	var st: Array = _plan_stops(slot)
	st[i]["comp"] = String(v)
	refresh()


# ═════════ 애니메이션 ═════════
func _process(delta: float) -> void:
	if sim == null:
		return
	if phase == "quali" and anim == null:
		_quali_tick(delta)
		return
	if anim == null:
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


## 라이브 예선 진행: 세션 시계를 돌리고, 트랙 위 차를 그리고, 글자를 갱신
func _quali_tick(delta: float) -> void:
	if wk.Q.is_empty() or not is_visible_in_tree():
		return
	if wk.done_quali:
		phase = "grid"
		_view.solo = {"car": null, "dist": 0.0}
		refresh()
		return
	if q_speed > 0:
		wk.q_advance(delta * float(q_speed) / 60.0)
	var Q: Dictionary = wk.Q
	var T = sim.T
	var t: float = float(Q.get("t", 0.0))
	var lst: Array = []
	var my_push: Variant = null
	for id in Q.get("run", {}).keys():
		var r: Dictionary = Q["run"][id]
		var c = wk._car(id)
		var f: float = clampf((t - float(r["t0"])) / maxf(0.01, float(r["dur"])), 0.0, 1.0)
		var d: float = 0.0
		match String(r["phase"]):
			"out":
				d = f * T.L
			"push":
				var res: Dictionary = r["res"]
				var el: float = (t - float(r["t0"])) * 60.0
				var acc := 0.0
				var sec := 0
				while sec < 5 and acc + float(res["secs"][sec]) <= el:
					acc += float(res["secs"][sec])
					sec += 1
				d = T.dist_at(sec, clampf((el - acc) / float(res["secs"][sec]), 0.0, 1.0))
				if c.mine and my_push == null:
					my_push = [res, sec, el]
			_:
				# 인랩: 어택을 마친 곳(또는 포기한 곳)부터 남은 바퀴를 돌아 피트로
				var d0: float = float(r.get("d0", 0.0))
				d = (d0 + f * (1.0 - d0)) * T.L
		lst.append([c, d])
	_view.solo = {"list": lst}
	if my_push != null:
		_render_secs(my_push[0], my_push[1])
		_live.text = "[b]%s[/b] 어택 중  %s" % [wk._car(my_push[0]["id"]).code, K.fmt_lap(float(my_push[2]))]
	if int(Q["ver"]) != _q_ver:
		refresh()
		return
	_q_tick += delta
	if _q_tick >= 0.15:
		_q_tick = 0.0
		_q_live_update()
