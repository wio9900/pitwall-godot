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
const HUB = preload("res://scripts/ui/data_hub.gd")
const TraitsS = preload("res://scripts/sim/traits.gd")

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
var q_speed := 4             # 예선 진행 속도 (실제 1초 = 세션 N초). 0 = 멈춤. 레이스와 같은 기준: 1× = 4초 (기본 1×)
var q_comps: Array = ["S", "S"]
var q_pushes: Array = ["std", "std"]
var p_set := "auto"          # 연습 세트: auto(쓴 것 먼저) / new / used
var q_sets: Array = ["auto", "auto"]  # 예선 세트: auto(새 것 먼저) / new / used
var p_idx := -1              # 연습 '쓴 세트'에서 직접 고른 세트 번호 (used_sets 안, -1 = 가장 덜 쓴 것)
var q_idx: Array = [-1, -1]  # 예선 같은 것 (결승 출발은 wk.start_idx)
const SET_ITEMS := [["auto", "자동"], ["new", "새 세트"], ["used", "쓴 세트"]]
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
		" · ".join(pros), " · ".join(cons)] + ("\n[color=#ffc53d]◆ 특성: %s[/color]" % TraitsS.label(c.traits) if not c.traits.is_empty() else "")


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
	return "주말 타이어 (연습·예선·결승 공용) — 새 [color=#ef4444]S[/color] %d · [color=#facc15]M[/color] %d · H %d  /  쓴 S %d · M %d · H %d" % [s["S"], s["M"], s["H"], u["S"].size(), u["M"].size(), u["H"].size()]


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
	# ── 버튼으로 고르는 것끼리 ──
	_section(card, "공기압" if sim.is_wec() else "공기압 · 연료")
	var bg = GridContainer.new()
	bg.columns = 2 if get_viewport_rect().size.x >= 900.0 else 1
	bg.add_theme_constant_override("h_separation", 10)
	bg.add_theme_constant_override("v_separation", 6)
	card.add_child(bg)
	var pv = K.vbox(4)
	pv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bg.add_child(pv)
	_psi_block(pv, c, "q", ed)
	if not sim.is_wec(): # WEC 는 급유 레이스 — 출발 연료는 늘 가득, 연료량은 레이스 중 피트에서 정한다
		var fv = K.vbox(4)
		fv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bg.add_child(fv)
		fv.add_child(K.label("연료 탑재", 14, K.DIM))
		K.seg(fv, [["light", "가볍게 (-3%)"], ["std", "표준 (+2%)"], ["heavy", "넉넉하게 (+6%)"]], c.fuel_load, _on_fuel, 14, ed)
	# ── 슬라이더끼리 ──
	_section(card, "셋업 슬라이더")
	var ct: Dictionary = sim.circ_traits()
	var ag: float = clampf((c.aggr - 0.6) / 0.15, -1.0, 1.0)
	var hint := []
	hint.append("연석·저속 코너가 많아요" if ct["bump"] > 0.3 else ("고속 코너 위주의 매끈한 노면" if ct["bump"] < -0.3 else "노면·코너 성격은 중간"))
	hint.append("코너 탈출 트랙션이 중요해요" if ct["trac"] > 0.3 else ("긴 직선·고속 구간 위주" if ct["trac"] < -0.3 else "트랙션 비중 보통"))
	hint.append("%s는 브레이킹이 공격적이에요" % c.name if ag > 0.3 else ("%s는 부드럽게 브레이킹해요" % c.name if ag < -0.3 else "%s의 브레이킹은 무난해요" % c.name))
	var dh = K.rtl(13)
	dh.text = "[color=#8b98a5]서킷: %s[/color]" % " · ".join(hint)
	card.add_child(dh)
	for key in ["wing", "susp", "bbias", "diff"]:
		_setup_slider(card, c, key, ed)
	var eb = K.btn("🔧 엔지니어 추천값으로 맞추기 (%s)" % _eng_grade(), 14, _on_engineer)
	eb.disabled = not ed
	card.add_child(eb)
	var dx = K.rtl(12)
	dx.text = "[color=#8b98a5]노란 띠 = 엔지니어 추천 범위 (엔지니어가 좋을수록 좁아요). 엔지니어 추천은 결승까지 생각한 '안전한 타협안'이라 예선만 보면 조금 느릴 수 있고, 등급이 낮으면 틀린 곳을 가리킬 때도 있어요(테스트를 달릴수록 바로잡혀요). 세부 셋업은 정답 하나가 아니라 타협이에요 — 슬라이더 아래 숫자가 고속·저속·연석·브레이킹 중 어디서 얻고 잃는지 보여줘요(엔지니어 계산이라 등급만큼 부정확). 서킷마다 맞는 곳이 다르고, 단단하게·잠글수록 빠를 수 있지만 타이어 마모가 늘어 결승에서 아파요. 드라이버마다 취향이 있어서 취향과 멀면 속도는 같아도 실수가 늘어요(드라이버가 말해줘요). 공기압을 높이면 서스펜션도 더 단단해진 것처럼 느껴져요. 드라이버 피드백은 늘 맞는 방향을 알려줘요.[/color]"
	card.add_child(dx)
	var left: int = wk.practice_left[sel]
	# 연습 타이어: 쓴 세트가 있으면 그걸로, 없으면 새 세트를 하나 열어요
	card.add_child(K.label("연습 타이어 — 쓴 세트가 있으면 그걸로 달리고, 없으면 새 세트를 하나 열어요 (연 세트는 예선·결승에서 헌 세트)", 13, K.DIM))
	var ps: Dictionary = wk.sets[sel]
	var pu: Dictionary = wk.used_sets[sel]
	var pitems: Array = []
	for k in wk.dry_comps(c):
		pitems.append([k, "%s (새 %d·쓴 %d)" % [RS.TYRE_KO[k], int(ps[k]), (pu[k] as Array).size()]])
	if not wk.has_any(sel, p_comp) and not pitems.is_empty():
		p_comp = pitems[0][0]
	K.seg(card, pitems, p_comp, _on_pcomp, 14, anim == null)
	p_set = _set_seg(card, sel, p_comp, "쓴 것 먼저", p_set, _on_pset, anim == null)
	if p_set == "used":
		p_idx = _used_pick(card, sel, p_comp, p_idx, _on_pidx, "", anim == null)
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
	_update_live_feedback()
	# 기록
	if not wk.practice_runs.is_empty():
		var tc = K.card(_side, "연습 기록")
		var best := INF
		for r in wk.practice_runs:
			best = minf(best, r["best"])
		var t := ""
		for r in wk.practice_runs:
			var col := "#a855f7" if r["best"] == best else "#e6edf3"
			t += "%s  W%.1f %s %s  %s  [color=%s]%s[/color]  평균 %s  마모 %.1f%%/랩\n" % [r["code"], r["wing"], "%.1fpsi" % float(r.get("psi", 0.0)), r.get("detail", ""), "롱런" if r["kind"] == "long" else "테스트", col, K.fmt_lap(r["best"]), K.fmt_lap(r["avg"]), r["wear_lap"]]
		var rr = K.rtl(14)
		rr.text = t
		tc.add_child(rr)
		# 데이터 허브: 지금 셋업 기준 섹터별 예상 시간을 가장 빠를 것 같은 차와 비교
		var cc = _my(sel)
		var ref = null
		var ref_sum := INF
		for o in sim.cars:
			if o.mine or o.cls != cc.cls:
				continue
			var es: Array = sim.est_sectors(o)
			var sm := 0.0
			for x in es:
				sm += float(x)
			if sm < ref_sum:
				ref_sum = sm
				ref = o
		if ref != null:
			var hc = K.card(_side, "📊 데이터 허브 · %s vs %s (텔레메트리 예상 섹터)" % [cc.code, ref.code], K.AMBER)
			var hr = K.rtl(14)
			hr.text = HUB.report(sim, sim.est_sectors(cc), sim.est_sectors(ref), ref.code)
			hc.add_child(hr)
	var b2 = K.hbox(6)
	_side.add_child(b2)
	b2.add_child(K.btn("⚡ 엔지니어에게 맡기기 (자동)", 15, _on_auto_practice))
	b2.add_child(K.btn("셋업 확정 · 예선으로 ▶", 17, _on_to_quali))
	_side.add_child(K.btn("◀ 뒤로", 14, _on_back))


func _on_pcomp(v) -> void:
	p_comp = v
	p_idx = -1
	refresh()


func _on_pset(v) -> void:
	p_set = v
	refresh()


func _on_pidx(v) -> void:
	p_idx = int(v)
	refresh()


## 새 세트 / 쓴 세트 고르기 버튼 (개수 표시, 없는 쪽은 "없음"). 쓴 세트는 마모 % 를 작은 순으로
func _set_items(slot: int, comp: String, auto_txt: String) -> Array:
	var nn: int = int(wk.sets[slot].get(comp, 0))
	var uu: int = wk.used_n(slot, comp)
	var ws: Array = []
	for st in wk.used_sets[slot].get(comp, []):
		ws.append(float(st["w"]))
	ws.sort()
	var pct: PackedStringArray = []
	for w in ws:
		pct.append("%d%%" % int(round(w * 100.0)))
	return [["auto", "자동 (%s)" % auto_txt], ["new", "새 세트 %d" % nn if nn > 0 else "새 세트 없음"], ["used", "쓴 %d (%s)" % [uu, " · ".join(pct)] if uu > 0 else "쓴 세트 없음"]]


## 쓴 세트 직접 고르기 줄 ("18% · 2회", 덜 쓴 순). cur = 고른 번호(-1 = 가장 덜 쓴 것, 그 버튼이 눌린 모양).
## kind: "q" 예선 손해 / "start" 결승 출발 손해 한 줄, "" 없음. 돌려주는 값 = 유효한 번호(-1 그대로 둠)
func _used_pick(card: Control, slot: int, comp: String, cur: int, cb: Callable, kind: String, enabled := true) -> int:
	var arr: Array = wk.used_sets[slot].get(comp, [])
	if arr.is_empty():
		return -1
	if cur >= arr.size():
		cur = -1
	var shown: int = cur if cur >= 0 else RS.least_worn(arr)
	var order: Array = range(arr.size())
	order.sort_custom(func(a, b): return float(arr[a]["w"]) < float(arr[b]["w"]))
	var flow := HFlowContainer.new() # 세로 폰에서 세트가 많으면 줄바꿈
	flow.add_theme_constant_override("h_separation", 4)
	flow.add_theme_constant_override("v_separation", 4)
	card.add_child(flow)
	var grp := ButtonGroup.new()
	for i in order:
		var b = K.btn("%d%% · %d회" % [int(round(float(arr[i]["w"]) * 100.0)), int(arr[i]["h"])], 12)
		b.toggle_mode = true
		b.button_group = grp
		b.button_pressed = i == shown
		b.disabled = not enabled
		b.pressed.connect(cb.bind(i))
		flow.add_child(b)
	var st: Dictionary = arr[shown]
	if kind == "q":
		card.add_child(K.label("이 세트로 어택: 예선 약 +%.2f초" % (wk.q_used_pen(comp, float(st["w"])) * sim.wsc()), 12, K.DIM))
	elif kind == "start":
		var hh: int = mini(3, int(st["h"]))
		card.add_child(K.label("달군 %d회 → 랩당 +%.2f초 · 마모 %d%%에서 출발" % [int(st["h"]), RS.HEAT_PEN * float(hh), int(round(float(st["w"]) * 100.0))], 12, K.DIM))
	return cur


## 세트 버튼 줄: 없는 쪽은 눌리지 않게 막고, 고른 쪽이 바닥났으면 "자동"으로 되돌린다. 돌려주는 값 = 실제 선택
func _set_seg(card: Control, slot: int, comp: String, auto_txt: String, cur: String, cb: Callable, enabled := true) -> String:
	var nn: int = int(wk.sets[slot].get(comp, 0))
	var uu: int = wk.used_n(slot, comp)
	if (cur == "new" and nn <= 0) or (cur == "used" and uu <= 0):
		cur = "auto"
	var bs: Array = K.seg(card, _set_items(slot, comp, auto_txt), cur, cb, 13, enabled)
	if bs.size() == 3:
		bs[1].disabled = bs[1].disabled or nn <= 0
		bs[2].disabled = bs[2].disabled or uu <= 0
	return cur


func _run_practice(kind: String) -> void:
	if anim != null:
		return
	var r: Dictionary = wk.practice_run(sel, kind, p_comp, p_set, p_idx if p_set == "used" else -1)
	if r.is_empty():
		_live.text = "[color=#ef4444]%s[/color]" % ("남은 연습 랩이 부족해요" if wk.practice_left[sel] < (5 if kind == "long" else 3) else "%s %s타이어가 남아 있지 않아요" % [RS.TYRE_KO[p_comp], {"new": "새 ", "used": "쓴 "}.get(p_set, "")])
		return
	anim = {"kind": "practice", "t": 0.0, "dur": 3.5 if kind == "long" else 2.4, "car": _my(sel), "laps": 3 if kind == "long" else 2}
	refresh()


# ── 예선 ──
func _render_quali() -> void:
	var st: int = wk.Q["stage"]
	var sub: String = ["", "P16 이하 탈락", "P11~15 결정 · 상위 10대 Q3 진출", "상위 10대 폴 포지션 결정전"][st]
	var ttl := "%s 예선 Q%d" % [sim.CIRC["name"], st]
	if wk.single_quali():
		sub = "%s 예선 · 30분 단일 세션 · 탈락 없음 — 이 기록으로 그리드가 정해져요" % ("F3" if wk.fmt() == "f3" else "F2")
		ttl = "%s 예선" % sim.CIRC["name"]
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
		# 누가 다음 세션에 가고 누가 그리드가 정해졌는지 분명히 (내 차 둘 다 탈락이면 "전부 확정"처럼 보이던 것)
		var nx_name: String = "하이퍼폴" if sim.is_wec() else "Q%d" % (st + 1)
		var my_line: PackedStringArray = []
		for c in wk.my_cars():
			my_line.append("%s %s" % [c.code, ("[color=#22c55e]%s 진출[/color]" % nx_name) if wk._participant(c, st + 1) else "[color=#8b98a5]탈락 · 그리드 확정[/color]"])
		var oq = K.rtl(15)
		oq.text = "%s 진출: 상위 %d대%s\n내 차: %s\n탈락(그리드 확정): %s" % [nx_name, wk._cut_n(), (" (%s 클래스)" % wk.main_cls()) if sim.is_wec() else "", " · ".join(my_line), ", ".join(wk.Q.get("cut_names", PackedStringArray()))]
		oc.add_child(oq)
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
			var al: Array = wk.dry_comps(c)
			if sim.is_wec():
				al = sim.wec_comps(c.cls) # 하이퍼폴도 대회 허용 컴파운드 안에서 자유 (2026 르망: 대부분 소프트, 페라리 미디엄)
			for k in al:
				if wk.has_any(slot, k):
					items.append([k, "%s (새 %d·쓴 %d)" % [RS.TYRE_KO[k], int(s[k]), (u[k] as Array).size()]])
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
			q_sets[slot] = _set_seg(card, slot, q_comps[slot], "새 것 먼저", String(q_sets[slot]), _on_q_set.bind(slot))
			if q_sets[slot] == "used":
				q_idx[slot] = _used_pick(card, slot, q_comps[slot], int(q_idx[slot]), _on_q_idx.bind(slot), "q")
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
	hint.text = "[color=#8b98a5]노면은 차들이 랩을 쌓을수록 좋아져요. 막판엔 다들 나와서 트래픽이 심해지고, 레드 플래그가 나면 어택 중이던 랩은 무효예요. 체커기 %.1f분 전까지 피트를 나가야 어택을 시작할 수 있어요(아웃랩 한 바퀴). 한 번 나갈 때마다 타이어 한 세트(새 세트가 없으면 쓴 세트 — 많이 쓴 세트일수록 느려요).[/color]" % wk.out_min()
	_side.add_child(hint)
	_side.add_child(K.btn("⚡ 남은 예선 자동 진행", 15, _on_auto_quali))
	_q_live_update()


func _on_qspeed(v) -> void:
	q_speed = int(v)


func _on_q_comp(v, slot: int) -> void:
	q_comps[slot] = v
	q_idx[slot] = -1
	refresh()


func _on_q_set(v, slot: int) -> void:
	q_sets[slot] = v
	refresh()


func _on_q_idx(v, slot: int) -> void:
	q_idx[slot] = int(v)
	refresh()


func _on_q_push(v, slot: int) -> void:
	q_pushes[slot] = v


func _on_q_go(slot: int) -> void:
	var err: String = wk.player_depart(slot, q_comps[slot], q_pushes[slot], q_sets[slot], int(q_idx[slot]) if q_sets[slot] == "used" else -1)
	if err != "":
		_live.text = "[color=#ef4444]%s[/color]" % err
	if q_speed == 0:
		q_speed = 4
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
		_title("%s 스타팅 그리드 확정" % sim.CIRC["name"], ("파크 페르메: 윙은 예선 셋업으로 고정. 출발 타이어는 남은 할당 안에서 자유롭게 고를 수 있어요." if wk.single_quali() else "파크 페르메: 윙은 예선 셋업으로 고정. Q3 진출 차는 그 세션 타이어로 출발하고, 나머지는 출발 타이어를 고를 수 있어요."))
	for c in wk.my_cars():
		var card = K.card(_side, "#%d %s · 그리드 P%d" % [c.slot + 1, c.name, (sim.class_pos(c) if false else c.grid + 1)], K.AMBER)
		var s: Dictionary = wk.sets[c.slot]
		var info = K.rtl(14)
		info.text = "윙 W%.1f 고정 · %s" % [c.wing, _sets_txt(c.slot)]
		card.add_child(info)
		card.add_child(K.label("출발 타이어" + (" (Q3 타이어 고정)" if c.q3_locked else " (자유 선택)"), 14, K.DIM))
		var slot: int = c.slot
		var sitems: Array = []
		for k in wk.dry_comps(c):
			sitems.append([k, "%s (새 %d·쓴 %d)" % [RS.TYRE_KO[k], int(s[k]), wk.used_n(c.slot, k)]])
		if sim.is_wec():
			var sal: Array = sim.wec_comps(c.cls)
			sitems = []
			for k in sal:
				sitems.append([k, "%s (새 세트)" % RS.TYRE_KO[k]])
		K.seg(card, sitems, c.comp, _on_start_comp.bind(slot), 14, not c.q3_locked)
		if not sim.is_wec() and not c.q3_locked and RS.SLICK.has(c.comp):
			wk.start_pref[slot] = _set_seg(card, slot, c.comp, "새 것 먼저", String(wk.start_pref[slot]), _on_start_set.bind(slot))
			if wk.start_pref[slot] == "used":
				wk.start_idx[slot] = _used_pick(card, slot, c.comp, int(wk.start_idx[slot]), _on_start_idx.bind(slot), "start")
			else:
				wk.start_idx[slot] = -1
		_psi_block(card, c, "race", true)
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


## 타이어 공기압: 넣을 때(차가운) 값 슬라이더 + −/+ (0.5 psi). 위 띠 = 엔지니어 추천, 아래 = 달리면 몇까지 오르는지
## kind: "q" 연습·예선 화면 / "race" 결승 출발 화면
func _psi_block(parent: Control, c, kind: String, ed: bool) -> void:
	var lab = K.rtl(14)
	lab.text = _psi_text(c, kind)
	parent.add_child(lab)
	var lo: float = sim.psi_min
	var span: float = RS.PSI_SPAN
	var row = K.hbox(6)
	parent.add_child(row)
	var mid = K.vbox(0)
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var bar = BandBar.new()
	var lh: Array = wk.psi_band(c.slot, kind)
	bar.lo = (float(lh[0]) - lo) / span
	bar.hi = (float(lh[1]) - lo) / span
	mid.add_child(bar)
	var sl = K.slider(lo, lo + span, 0.5, c.psi, _on_psi.bind(c.slot, kind, lab), ed)
	mid.add_child(sl)
	var mb = K.btn("−", 16, func(): sl.value = c.psi - 0.5)
	var pb = K.btn("+", 16, func(): sl.value = c.psi + 0.5)
	for b in [mb, pb]:
		b.disabled = not ed
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER # 슬라이더가 폭을 가져가게
		b.custom_minimum_size = Vector2(44, 36)
	row.add_child(mb)
	row.add_child(mid)
	row.add_child(pb)
	parent.add_child(K.label("낮게: 연석 잘 먹음 / 잘 안 데워짐·미끄럼 · 높게: 직선 조금 빠름 / 튐·과열·마모", 12, K.DIM))


func _psi_text(c, kind: String) -> String:
	var lh: Array = wk.psi_band(c.slot, kind)
	var rq: float = sim.press_rise("q")
	var rr: float = sim.press_rise("race")
	var run: String = "예선 런 약 [b]%.1f[/b] · 결승 약 [b]%.1f psi[/b]" % [c.psi + rq, c.psi + rr] if kind == "q" else "결승 약 [b]%.1f psi[/b]" % (c.psi + rr)
	return "타이어 공기압 [b]%.1f psi[/b] [color=#8b98a5](규정 최소 %.1f)[/color]\n[color=#8b98a5]노면 %d°C → 달리면 %s까지 올라요 · 노란 띠 = 엔지니어 추천 %s %.1f~%.1f[/color]" % [c.psi, sim.psi_min, int(round(sim.track_t)), run, "예선용" if kind == "q" else "결승용", float(lh[0]), float(lh[1])]


func _on_psi(v: float, slot: int, kind: String, lab) -> void:
	wk.set_psi(slot, v)
	lab.text = _psi_text(_my(slot), kind)
	if kind == "q":
		_update_live_feedback()


## 셋업 슬라이더 한 줄: 이름·값 + 추천 범위 띠 + 슬라이더
const SET_FMT := {"wing": "W %.1f", "susp": "%.1f", "bbias": "앞 %.1f%%", "diff": "%d%%"}
const SET_END := {"wing": ["눕힘 (직선)", "세움 (코너)"], "susp": ["부드럽게", "단단하게"], "bbias": ["뒤쪽", "앞쪽"], "diff": ["열림", "잠김"]}
const SET_END_SHORT := {"wing": ["직선", "코너"]} # 좁은 화면(세로 폰)에서 줄바꿈 안 되게


func _setup_val(c, key: String) -> float:
	return float(c.wing) if key == "wing" else float(c.get(key))


func _setup_label(c, key: String) -> String:
	var lh: Array = wk.band_lohi(c.slot, key)
	var v: float = _setup_val(c, key)
	var vs: String = SET_FMT[key] % (int(v) if key == "diff" else v)
	var ls: String = SET_FMT[key] % (int(lh[0]) if key == "diff" else float(lh[0]))
	var hs: String = SET_FMT[key] % (int(lh[1]) if key == "diff" else float(lh[1]))
	var extra: String = (" · " + _wing_desc(v)) if key == "wing" else ""
	var t: String = "[b]%s[/b] %s%s   [color=#ffc53d]추천 %s ~ %s[/color]" % [RS.SETUP_KO[key], vs, extra, ls, hs]
	if RS.SETUP_RANGE.has(key):
		# 가운데 대비 어디서 얻고 잃는지 (엔지니어 계산 — 등급만큼 부정확). 초록 = 빨라짐, 빨강 = 느려짐
		var sv: Dictionary = wk.setup_view(c.slot, key)
		var parts: PackedStringArray = []
		for ch in sv["ch"]:
			parts.append("%s [color=%s]%+.2f[/color]" % [ch[0], "#22c55e" if float(ch[1]) < -0.005 else ("#ef4444" if float(ch[1]) > 0.005 else "#8b98a5"), float(ch[1]) + 0.0]) # + 0.0: -0.00 대신 +0.00
		var wr: float = sv["wear"]
		parts.append("마모 [color=%s]%+.0f%%[/color]" % ["#ef4444" if wr > 0.5 else ("#22c55e" if wr < -0.5 else "#8b98a5"), wr])
		t += "\n[color=#8b98a5]가운데 대비 초/랩:[/color] %s · [color=#8b98a5]엔지니어 계산 합계[/color] %+.2f" % [" · ".join(parts), float(sv["tot"]) + 0.0]
	return t


func _setup_slider(card: VBoxContainer, c, key: String, ed: bool) -> void:
	# 한 항목 = 제목 줄 + [왼쪽 뜻 | 추천 띠·슬라이더 | 오른쪽 뜻] — 양끝 글자가 다음 항목에 붙어 보이지 않게 같은 줄 양옆에
	var blk = K.vbox(2)
	card.add_child(blk)
	var lab = K.rtl(15)
	lab.text = _setup_label(c, key)
	blk.add_child(lab)
	var row = K.hbox(8)
	blk.add_child(row)
	var narrow: bool = get_viewport_rect().size.x < 900.0
	var end_w: float = 64.0 if narrow else 92.0
	var ends: Array = SET_END_SHORT.get(key, SET_END[key]) if narrow else SET_END[key]
	var l0 = K.label(ends[0], 14, K.INK)
	l0.custom_minimum_size = Vector2(end_w, 0)
	l0.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l0.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	l0.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(l0)
	var mid = K.vbox(0)
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(mid)
	var r: Array = wk._span(key)
	var bar = BandBar.new()
	var lh: Array = wk.band_lohi(c.slot, key)
	bar.lo = (float(lh[0]) - float(r[0])) / (float(r[1]) - float(r[0]))
	bar.hi = (float(lh[1]) - float(r[0])) / (float(r[1]) - float(r[0]))
	mid.add_child(bar)
	var sl = K.slider(float(r[0]), float(r[1]), {"wing": 0.1, "susp": 0.1, "bbias": 0.5, "diff": 1.0}[key], _setup_val(c, key), _on_setup_val.bind(key, lab), ed)
	mid.add_child(sl)
	var l1 = K.label(ends[1], 14, K.INK)
	l1.custom_minimum_size = Vector2(end_w, 0)
	l1.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	l1.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(l1)
	# 항목 사이 간격
	var gap = Control.new()
	gap.custom_minimum_size = Vector2(0, 8)
	card.add_child(gap)


## 카드 안 소제목 (버튼 묶음 · 슬라이더 묶음 구분)
func _section(card: VBoxContainer, title: String) -> void:
	var gap = Control.new()
	gap.custom_minimum_size = Vector2(0, 4)
	card.add_child(gap)
	var t = K.label(title, 15, K.AMBER)
	card.add_child(t)
	var ln = ColorRect.new()
	ln.color = Color(1, 1, 1, 0.08)
	ln.custom_minimum_size = Vector2(0, 1)
	card.add_child(ln)


func _on_setup_val(v: float, key: String, lab) -> void:
	if key == "wing":
		wk.set_wing(sel, v)
	else:
		wk.set_detail(sel, key, v)
	lab.text = _setup_label(_my(sel), key)
	_update_live_feedback()


## 연습 드라이버 멘트 줄 (슬라이더를 움직이는 즉시 "셋업 바뀜" 표시가 뜨도록 따로 뺌)
func _update_live_feedback() -> void:
	var c = _my(sel)
	var fb: String = String(wk.last_feedback[sel]) if sel < wk.last_feedback.size() else ""
	var dirty: bool = bool(wk.setup_dirty[sel]) if sel < wk.setup_dirty.size() else false
	if anim != null:
		_live.text = "[b]%s[/b] 주행 중…" % c.name
	elif fb != "":
		var note: String = "[color=#8b98a5] · 연습 %d랩째 주행 기준[/color]" % int(wk.fb_lap[sel])
		if dirty:
			note = "\n[color=#f59e0b]⚠ 셋업이 바뀌었어요 — 다시 달려야 새 멘트를 들을 수 있어요[/color]"
		_live.text = "[color=#ffc53d]“%s”[/color]%s" % [fb, note]
	else:
		_live.text = "[color=#8b98a5]롱런을 하면 타이어 마모 추정 오차가 절반으로 줄어요 (35%→17%→9%).[/color]"


func _eng_grade() -> String:
	var g: String = wk.eng_grade()
	return "엔지니어 %s급 · 정확도 %s" % [g, {"S": "아주 높음", "A": "높음", "B": "보통", "C": "낮음", "D": "매우 낮음"}[g]]


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


func _on_start_set(v, slot: int) -> void:
	wk.start_pref[slot] = v
	refresh()


func _on_start_idx(v, slot: int) -> void:
	wk.start_idx[slot] = int(v)
	refresh()


func _on_start_comp(v, slot: int) -> void:
	wk.set_start_comp(slot, v)
	wk.start_idx[slot] = -1
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
		# 피트 입구·출구 (트랙 위 거리)
		var exit_d: float = fposmod(float(T.cum[T.pit_out]), T.L)
		var entry_d: float = fposmod(float(T.cum[T.pit_in]), T.L)
		const LANE_F := 0.15 # 아웃랩·인랩 중 피트레인에 있는 시간 비율
		match String(r["phase"]):
			"out":
				# 차고 → 피트레인 → 출구에서 트랙 합류 → 출발선까지
				if f < LANE_F:
					var pl: Array = T.pit_lane_point(sim._lane_u(0.35 + 0.65 * (f / LANE_F), sim._stall_u(c.stall_idx)))
					lst.append([c, pl[0], pl[1]])
					continue
				d = exit_d + (T.L - exit_d) * ((f - LANE_F) / (1.0 - LANE_F))
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
				# 인랩: 어택을 마친 곳(또는 포기한 곳)부터 피트 입구까지 돌고 → 피트레인으로 들어가 차고에서 사라짐
				var d0: float = float(r.get("d0", 0.0)) * T.L
				var tgt: float = entry_d if entry_d > d0 else entry_d + T.L
				if f < 1.0 - LANE_F:
					d = d0 + (tgt - d0) * (f / (1.0 - LANE_F))
				else:
					if f >= 0.999:
						continue
					var pl2: Array = T.pit_lane_point(sim._lane_u(0.35 * ((f - (1.0 - LANE_F)) / LANE_F), sim._stall_u(c.stall_idx)))
					lst.append([c, pl2[0], pl2[1]])
					continue
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
