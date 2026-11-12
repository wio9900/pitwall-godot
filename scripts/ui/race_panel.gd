extends VBoxContainer
## 레이스 지시판 (HTML판 구성을 옮김)
## 엔지니어 제안 카드 · 내 차 칩 2개 · 선택한 차의 탭(주행 / 피트 / ERS·연료 / 랩타임) · 팀 오더.
## sim 상태를 읽어 그리고, 버튼은 sim 의 공개 함수만 부른다.

signal select_car(slot: int)
signal radio_prompt  # 새 엔지니어 제안이 떴을 때 (main 이 배속을 1×로)

const K = preload("res://scripts/ui/kit.gd")
const RS = preload("res://scripts/sim/race_sim.gd")

const TABS := [["drive", "주행"], ["pit", "피트"], ["power", "ERS · 연료"], ["laps", "랩타임"]]
const INSTR := [["free", "자유"], ["attack", "추월"], ["defend", "방어"], ["hold", "유지"], ["lift", "연비"]]
const PACE_ITEMS := [["attack", "공격"], ["standard", "표준"], ["save", "세이브"]]
const ERS_ITEMS := [["harvest", "충전"], ["balance", "밸런스"], ["deploy", "오버테이크"]]
const FUEL_ITEMS := [["lean", "세이브"], ["std", "표준"], ["rich", "리치"]]
const COLD := Color("#38bdf8")

var sim = null
var sel := 0
var tab := "drive"
var draft: Array = [{"comp": "", "tyres": true, "fuel": true, "driver": false}, {"comp": "", "tyres": true, "fuel": true, "driver": false}]
var _seen_seq := -1

var _prompt: PanelContainer
var _p_title: Label
var _p_msg: RichTextLabel
var _p_btns: HBoxContainer
var _chips: Array = []
var _chip_txt: Array = []
var _tab_btns: Array = []
var _pages := {}
# 주행
var _d_head: RichTextLabel
var _pace_btns: Array = []
var _d_instr_head: RichTextLabel
var _instr_btns: Array = []
var _d_tyre_head: RichTextLabel
var _temp_mark: ColorRect
var _wear_fill: ColorRect
var _d_hint: RichTextLabel
var _d_radio: RichTextLabel
# 피트
var _pred: RichTextLabel
var _radar_head: RichTextLabel
var _radar: Array = []
var _radar_sb: Array = []
var _radar_row: HBoxContainer
var _w_opts: VBoxContainer
var _w_tyre_btns: Array = []
var _w_fuel_btns: Array = []
var _w_drv_btns: Array = []
var _w_fuel_fill: ColorRect
var _tyre_btns: Array = []
var _tyre_keys: Array = []
var _pit_status: RichTextLabel
var _confirm: Button
var _cancel: Button
var _plan_box: VBoxContainer
var _plan_btns: Array = []
var _auto: Button
var _replan: Button
var _plan_line: RichTextLabel
var _p_radio: RichTextLabel
# ERS·연료
var _ers_box: VBoxContainer
var _ers_head: RichTextLabel
var _ers_btns: Array = []
var _ers_fill: ColorRect
var _fuel_head: RichTextLabel
var _fuel_btns: Array = []
var _fuel_hint: RichTextLabel
var _drv_info: RichTextLabel
# 랩타임
var _laps_rtl: RichTextLabel
# 팀 오더
var _order_row: HBoxContainer
var _order_btns: Array = []
var _swap_btn: Button


func _init() -> void:
	add_theme_constant_override("separation", 6)
	_build_prompt()
	var cr = K.hbox(6)
	add_child(cr)
	for i in 2:
		var b = Button.new()
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(0, 62)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_on_chip.bind(i))
		var r = K.rtl(14)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		r.offset_left = 10
		r.offset_top = 6
		r.offset_right = -8
		b.add_child(r)
		cr.add_child(b)
		_chips.append(b)
		_chip_txt.append(r)
	# 탭 막대 + 내용 카드
	var card = PanelContainer.new()
	card.add_theme_stylebox_override("panel", _box(K.PANEL, K.LINE, 10))
	add_child(card)
	var cv = K.vbox(6)
	card.add_child(cv)
	var tb = K.hbox(2)
	cv.add_child(tb)
	var grp = ButtonGroup.new()
	for t in TABS:
		var b = K.btn(t[1], 15)
		b.toggle_mode = true
		b.button_group = grp
		b.flat = true
		b.pressed.connect(_on_tab.bind(t[0]))
		tb.add_child(b)
		_tab_btns.append(b)
	for t in TABS:
		var pg = K.vbox(5)
		pg.visible = t[0] == tab
		cv.add_child(pg)
		_pages[t[0]] = pg
	_build_drive(_pages["drive"])
	_build_pit(_pages["pit"])
	_build_power(_pages["power"])
	_laps_rtl = K.rtl(14)
	_pages["laps"].add_child(_laps_rtl)
	# 팀 오더
	_order_row = K.hbox(4)
	add_child(_order_row)
	var ol = K.label("팀 오더", 14, K.DIM)
	ol.custom_minimum_size = Vector2(56, 0)
	_order_row.add_child(ol)
	_order_btns = _seg(_order_row, [["free", "자유 경쟁"], ["hold", "순서 유지"]], _on_order, 14)
	_swap_btn = K.sbtn("순서 교체", _on_swap, true, K.AMBER)
	_order_row.add_child(_swap_btn)
	_on_tab(tab)


# ═════════ 부품 ═════════
func _box(bg: Color, border: Color, pad := 8) -> StyleBoxFlat:
	var sb = StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(pad)
	return sb


func _seg(parent: Control, items: Array, cb: Callable, fs := 14) -> Array:
	var grp = ButtonGroup.new()
	var out: Array = []
	for it in items:
		var b = K.btn(it[1], fs)
		b.toggle_mode = true
		b.button_group = grp
		b.clip_text = true
		b.pressed.connect(cb.bind(it[0]))
		parent.add_child(b)
		out.append(b)
	return out


func _seg_row(parent: Control, items: Array, cb: Callable, fs := 14) -> Array:
	var row = K.hbox(4)
	parent.add_child(row)
	return _seg(row, items, cb, fs)


func _press(btns: Array, items: Array, v: String) -> void:
	for i in btns.size():
		btns[i].set_pressed_no_signal(String(items[i][0]) == v)


## 막대 (배경 + 채움). 채움 ColorRect 를 돌려준다 (anchor_right 로 비율 조절)
func _meter(parent: Control, col: Color, h := 7.0) -> ColorRect:
	var bg = ColorRect.new()
	bg.color = Color("#0b1016")
	bg.custom_minimum_size = Vector2(0, h)
	bg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(bg)
	var fg = ColorRect.new()
	fg.color = col
	fg.anchor_bottom = 1.0
	fg.anchor_right = 0.0
	bg.add_child(fg)
	return fg


func _rt(parent: Control, fs := 14) -> RichTextLabel:
	var r = K.rtl(fs)
	parent.add_child(r)
	return r


func _build_prompt() -> void:
	_prompt = PanelContainer.new()
	_prompt.add_theme_stylebox_override("panel", _box(Color("#2a2410"), K.AMBER, 10))
	_prompt.visible = false
	add_child(_prompt)
	var v = K.vbox(6)
	_prompt.add_child(v)
	_p_title = K.label("", 15, K.AMBER)
	v.add_child(_p_title)
	_p_msg = _rt(v, 15)
	_p_btns = K.hbox(6)
	v.add_child(_p_btns)


func _build_drive(pg: VBoxContainer) -> void:
	_d_head = _rt(pg, 14)
	_pace_btns = _seg_row(pg, PACE_ITEMS, _on_pace)
	_d_instr_head = _rt(pg, 14)
	_instr_btns = _seg_row(pg, INSTR, _on_instr)
	_d_tyre_head = _rt(pg, 14)
	# 타이어 온도: 차가움(파랑) · 적정(초록) · 과열(빨강) 구간 위에 현재 위치 표시
	var wrap = Control.new()
	wrap.custom_minimum_size = Vector2(0, 8)
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pg.add_child(wrap)
	var tbar = HBoxContainer.new()
	tbar.add_theme_constant_override("separation", 0)
	tbar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wrap.add_child(tbar)
	for part in [[COLD, 0.42], [K.GOOD, 0.38], [K.BAD, 0.2]]:
		var cr = ColorRect.new()
		cr.color = Color(part[0], 0.75)
		cr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cr.size_flags_stretch_ratio = part[1]
		tbar.add_child(cr)
	_temp_mark = ColorRect.new()
	_temp_mark.color = Color.WHITE
	_temp_mark.anchor_top = 0.0
	_temp_mark.anchor_bottom = 1.0
	_temp_mark.offset_left = -2
	_temp_mark.offset_right = 2
	_temp_mark.offset_top = -3
	_temp_mark.offset_bottom = 3
	wrap.add_child(_temp_mark)
	_wear_fill = _meter(pg, K.GOOD, 6.0)
	_d_hint = _rt(pg, 12)
	_d_radio = _rt(pg, 14)


func _build_pit(pg: VBoxContainer) -> void:
	var pc = PanelContainer.new()
	pc.add_theme_stylebox_override("panel", _box(K.PANEL2, K.LINE, 8))
	pg.add_child(pc)
	_pred = K.rtl(14)
	pc.add_child(_pred)
	_radar_head = _rt(pg, 13)
	var rr = K.hbox(4)
	_radar_row = rr
	pg.add_child(rr)
	for i in 5:
		var cell = PanelContainer.new()
		var sb = _box(K.PANEL2, K.LINE, 4)
		cell.add_theme_stylebox_override("panel", sb)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rr.add_child(cell)
		var r = K.rtl(12)
		cell.add_child(r)
		_radar.append(r)
		_radar_sb.append(sb)
	# WEC: 타이어 교체 여부 · 급유 · 교대
	_w_opts = K.vbox(4)
	pg.add_child(_w_opts)
	_w_fuel_fill = _meter(_w_opts, K.AMBER, 6.0)
	var wr = K.hbox(4)
	_w_opts.add_child(wr)
	_w_tyre_btns = _seg(wr, [["yes", "타이어 교체"], ["no", "타이어 유지"]], _on_w_tyres, 13)
	var wr2 = K.hbox(4)
	_w_opts.add_child(wr2)
	_w_fuel_btns = _seg(wr2, [["yes", "급유"], ["no", "급유 안 함"]], _on_w_fuel, 13)
	_w_drv_btns = _seg(wr2, [["no", "드라이버 유지"], ["yes", "교대"]], _on_w_drv, 13)
	# 타이어 선택 (F1 5종 / WEC 4종)
	var tr = K.hbox(4)
	pg.add_child(tr)
	var grp = ButtonGroup.new()
	for comp in ["S", "M", "H", "I", "W"]:
		var b = Button.new()
		b.toggle_mode = true
		b.button_group = grp
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 46)
		b.add_theme_font_size_override("font_size", 14)
		b.add_theme_color_override("font_color", Color(RS.TYRE_HEX[comp]))
		b.add_theme_color_override("font_pressed_color", Color(RS.TYRE_HEX[comp]))
		var sb = _box(K.PANEL2, Color(RS.TYRE_HEX[comp]), 4)
		b.add_theme_stylebox_override("normal", sb)
		var sbp = _box(Color(RS.TYRE_HEX[comp]).darkened(0.65), Color(RS.TYRE_HEX[comp]), 4)
		sbp.set_border_width_all(2)
		b.add_theme_stylebox_override("pressed", sbp)
		b.pressed.connect(_on_draft_comp.bind(comp))
		tr.add_child(b)
		_tyre_btns.append(b)
		_tyre_keys.append(comp)
	_pit_status = _rt(pg, 13)
	var br = K.hbox(6)
	pg.add_child(br)
	_confirm = K.btn("핏스탑 확정", 16, _on_confirm)
	_confirm.custom_minimum_size = Vector2(0, 42)
	_confirm.size_flags_stretch_ratio = 1.6
	br.add_child(_confirm)
	_cancel = K.btn("✕ 크루 철수", 14, _on_cancel)
	_cancel.add_theme_color_override("font_color", K.BAD)
	br.add_child(_cancel)
	# 전략 플랜 A/B · 자동
	_plan_box = K.vbox(4)
	pg.add_child(_plan_box)
	var pr = K.hbox(4)
	_plan_box.add_child(pr)
	var pl = K.label("전략", 14, K.DIM)
	pl.custom_minimum_size = Vector2(40, 0)
	pr.add_child(pl)
	_plan_btns = _seg(pr, [["A", "플랜 A"], ["B", "플랜 B"]], _on_plan, 14)
	_auto = K.btn("자동 피트", 14)
	_auto.toggle_mode = true
	_auto.toggled.connect(_on_auto)
	pr.add_child(_auto)
	_replan = K.sbtn("최적 재계산", _on_replan, true, K.GOOD)
	pr.add_child(_replan)
	_plan_line = _rt(_plan_box, 13)
	_p_radio = _rt(pg, 14)


func _build_power(pg: VBoxContainer) -> void:
	_ers_box = K.vbox(4)
	pg.add_child(_ers_box)
	_ers_head = _rt(_ers_box, 14)
	_ers_btns = _seg_row(_ers_box, ERS_ITEMS, _on_ers)
	_ers_fill = _meter(_ers_box, K.AMBER, 7.0)
	var eh: RichTextLabel = _rt(_ers_box, 12)
	eh.text = "[color=#8b98a5]오버테이크는 랩당 약 0.6초 빠르고 추월이 쉬워지지만 몇 랩이면 배터리가 바닥나요. 충전은 느린 대신 배터리를 채워요.[/color]"
	_fuel_head = _rt(pg, 14)
	_fuel_btns = _seg_row(pg, FUEL_ITEMS, _on_fuel)
	_fuel_hint = _rt(pg, 12)
	_drv_info = _rt(pg, 13)


# ═════════ 상태 ═════════
func car() -> Variant:
	if sim == null:
		return null
	var mc: Array = sim.my_cars()
	if mc.is_empty():
		return null
	return mc[clampi(sel, 0, mc.size() - 1)]


func reset_for(sim_) -> void:
	sim = sim_
	sel = 0
	_seen_seq = -1
	for d in draft:
		d["comp"] = ""
		d["tyres"] = true
		d["fuel"] = true
		d["driver"] = false
	_press(_order_btns, [["free"], ["hold"]], "free")
	_on_tab("drive")


func _pct(x: float) -> String:
	return "%d%%" % int(round(x * 100.0))


func _gap_str(c, ord: Array) -> Array:
	var same: Array = []
	for o in ord:
		if o.cls == c.cls:
			same.append(o)
	var i := same.find(c)
	var ga := "–"
	var gb := "–"
	if i >= 1 and c.dnf == "":
		var a: String = sim.gap_to(c, same[i - 1])
		ga = a.replace("+", "") if a != "" else "–"
	if i + 1 < same.size() and same[i + 1].dnf == "" and c.dnf == "":
		var b: String = sim.gap_to(same[i + 1], c)
		gb = b.replace("+", "") if b != "" else "–"
	return [ga, gb]


func _radio_line(c) -> String:
	if c.dnf != "":
		return "[color=#ef4444]리타이어: %s[/color]" % c.dnf
	if c.finished:
		return "[color=#22c55e]체커기 받았어요[/color]"
	if c.radio != "" and sim.clock - c.radio_t < 30.0:
		return "[color=#ffc53d]“%s”[/color]" % c.radio
	return "[color=#5d6674]무전 대기[/color]"


func refresh() -> void:
	if sim == null:
		return
	var wec: bool = sim.is_wec()
	var ord: Array = sim.order_ui()
	var mc: Array = sim.my_cars()
	# 엔지니어 제안
	if sim.active_radio != null:
		if _seen_seq != sim.radio_seq:
			_seen_seq = sim.radio_seq
			var pr: Dictionary = sim.active_radio
			_p_title.text = pr["title"]
			_p_msg.text = pr["msg"]
			K.clear(_p_btns)
			var opts: Array = pr["opts"]
			for i in opts.size():
				var b = K.btn(String(opts[i]["label"]), 14, _on_prompt.bind(i))
				b.custom_minimum_size = Vector2(0, 40)
				if i == 0:
					b.add_theme_color_override("font_color", K.AMBER)
				_p_btns.add_child(b)
			radio_prompt.emit()
		_prompt.visible = true
	else:
		_prompt.visible = false
	# 칩
	for i in 2:
		var ch: Button = _chips[i]
		ch.visible = i < mc.size()
		if i >= mc.size():
			continue
		var c = mc[i]
		ch.set_pressed_no_signal(i == sel)
		var pos: String = "–" if c.dnf != "" else "P%d" % (sim.class_pos(c) if wec else ord.find(c) + 1)
		var badge := ""
		if c.dnf != "":
			badge = ""
		elif sim.is_pitting(c):
			badge = "[bgcolor=#ffc53d][color=#111827] PIT [/color][/bgcolor]"
		elif c.pit_req != "" or c.boxing != null:
			badge = "[bgcolor=#ffc53d][color=#111827] BOX [/color][/bgcolor]"
		else:
			var fv := int(round(c.focus))
			var fc := "#a855f7" if fv >= 85 else ("#ef4444" if fv <= 55 else "#8b98a5")
			badge = "[color=%s]집중 %d%%[/color]" % [fc, fv]
		var temp_col := "#38bdf8" if c.tt < 0.42 else ("#ef4444" if c.tt > 0.8 else "#22c55e")
		var extra: String = ("연료 %.1f랩" % sim.fuel_laps(c)) if wec else ("ERS " + _pct(c.ers))
		var line2: String = c.dnf if c.dnf != "" else "%s %s [color=%s]●[/color] %s" % [RS.TYRE_KO[c.comp], _pct(c.wear), temp_col, extra]
		if c.mech_trouble != "":
			line2 += " [color=#ef4444]⚠%s[/color]" % c.mech_trouble
		if c.time_pen > 0.0:
			line2 += " [color=#ef4444]+%d초[/color]" % int(c.time_pen)
		elif c.tl_warn > 0 and c.dnf == "":
			line2 += " [color=#f59e0b]TL %d/2[/color]" % c.tl_warn
		var code: String = ("#%d %s" % [c.slot + 1, c.code]) if wec else c.code
		_chip_txt[i].text = "[font_size=24][b]%s[/b][/font_size]  [b]%s[/b]  %s\n[color=#8b98a5]%s[/color]" % [pos, code, badge, line2]
	var c = car()
	if c == null:
		return
	_tab_btns[2].text = "연료 · 드라이버" if wec else "ERS · 연료"
	match tab:
		"drive":
			_refresh_drive(c, ord)
		"pit":
			_refresh_pit(c)
		"power":
			_refresh_power(c)
		_:
			_refresh_laps(c)
	# 팀 오더: F1 에서 두 대 모두 달릴 때
	var both: bool = mc.size() == 2 and mc[0].is_running() and mc[1].is_running()
	_order_row.visible = not wec and both
	_press(_order_btns, [["free"], ["hold"]], sim.team_order)
	_swap_btn.disabled = sim.swap_req


func _refresh_drive(c, ord: Array) -> void:
	var g := _gap_str(c, ord)
	var fv := int(round(c.focus))
	var fs := "🔥 존 진입" if fv >= 85 else ("⚠ 흔들림 (실수 주의)" if fv <= 55 else "안정적")
	_d_head.text = "[color=#8b98a5]페이스%s · 집중력 %d%% (%s)[/color]   [b]앞 %s · 뒤 %s[/b]" % [(" · " + c.name) if sim.is_wec() else "", fv, fs, g[0], g[1]]
	_press(_pace_btns, PACE_ITEMS, c.pace)
	var mech: String = ("[color=#ef4444]⚠ %s (리프트 앤 코스트로 식혀요)[/color]" % c.mech_trouble) if c.mech_trouble != "" else "[color=#8b98a5]기계 부하 %d%% (정상)[/color]" % int(round(c.mech_stress * 100))
	_d_instr_head.text = "[color=#8b98a5]상황 지시[/color] · %s" % mech
	_press(_instr_btns, INSTR, c.instr)
	var tt_txt := "차가움" if c.tt < 0.42 else ("과열" if c.tt > 0.8 else "적정")
	_d_tyre_head.text = "[color=#8b98a5]타이어 온도 · 마모[/color]  [b]%s[/b] · %s %s [color=#8b98a5](소모 ×%.2f · 연비 ×%.2f)[/color]" % [tt_txt, RS.TYRE_KO[c.comp], _pct(c.wear), c.tyre_deg_rate, c.fuel_burn_rate]
	_temp_mark.anchor_left = clampf(c.tt, 0.0, 1.0)
	_temp_mark.anchor_right = clampf(c.tt, 0.0, 1.0)
	_wear_fill.anchor_right = clampf(c.wear, 0.0, 1.0)
	_wear_fill.color = K.BAD if c.wear > 0.7 else (K.WARN if c.wear > 0.45 else K.GOOD)
	_d_hint.text = "[color=#8b98a5]%s[/color]" % ("리프트 앤 코스트(연비)는 브레이크·기어박스 과열을 식히고 연료를 아껴요." if sim.is_wec() else "공격은 빠르지만 타이어와 브레이크가 과열돼요. 기계 트러블 경고가 뜨면 '연비'(리프트 앤 코스트)로 식혀요.")
	_d_radio.text = _radio_line(c)


func _refresh_pit(c) -> void:
	var wec: bool = sim.is_wec()
	var d: Dictionary = draft[sel]
	# 복귀 예측
	var pr: Variant = sim.predict_pit(c) if c.is_running() and c.started else null
	if pr == null:
		_pred.text = "[color=#8b98a5]레이스가 시작되면 '지금 박스하면 몇 위로 복귀하는지' 예측이 나와요.[/color]"
	else:
		var a: String = ("앞: [b]%s[/b] 뒤 %.1f초" % [_nm(pr["ahead"][0]), float(pr["ahead"][1])]) if pr["ahead"] != null else "선두로 복귀"
		var b: String = ("뒤: [b]%s[/b] 앞 %.1f초" % [_nm(pr["behind"][0]), -float(pr["behind"][1])]) if pr["behind"] != null else "뒤에 차 없음"
		var u := ""
		if pr["under"] != null:
			var un: Dictionary = pr["under"]
			u = ("\n[color=#22c55e]언더컷 유력: %s보다 약 %.1f초 앞설 전망[/color]" % [un["code"], float(un["net"])]) if float(un["net"]) > 0.0 else ("\n[color=#f59e0b]언더컷 어려움: %s에 %.1f초 부족[/color]" % [un["code"], -float(un["net"])])
		_pred.text = "[font_size=26][b]P%d[/b][/font_size]  [color=#8b98a5]지금 박스 시 복귀 순위 (손실 약 %d초%s)[/color]\n%s · %s%s" % [int(pr["pos"]), int(round(float(pr["loss"]))), (", " + sim.sc_kind + " 중") if sim.sc else "", a, b, u]
	# 기상 레이더
	var cur: int = mini(sim.laps, sim.leader_lap + 1)
	# 앞으로 5랩 동안 비 걱정이 없으면 칸 대신 한 줄만
	var calm: bool = sim.wet < 0.05
	for i in 5:
		if cur + i + 1 <= sim.laps and sim.forecast_wet_at(cur + i + 1) >= 0.2:
			calm = false
	_radar_row.visible = not calm
	if calm:
		_radar_head.text = "[color=#8b98a5]날씨[/color]  ☀ 앞으로 5랩 비 걱정 없음 [color=#8b98a5](강수확률 %d%%)[/color]" % sim.forecast_prob_at(cur)
	else:
		_radar_head.text = "[color=#8b98a5]기상 레이더[/color]  지금 강수확률 [b]%d%%[/b] · 노면 수막 [b]%.1fmm[/b] [color=#8b98a5](인터 1.2mm · 웻 3.5mm부터)[/color]" % [sim.forecast_prob_at(cur), sim.wet_mm(sim.wet)]
	for i in 5:
		var tl: int = cur + i + 1
		var r: RichTextLabel = _radar[i]
		var sb: StyleBoxFlat = _radar_sb[i]
		if tl > sim.laps:
			r.text = "[center][color=#8b98a5]FIN[/color][/center]"
			sb.bg_color = K.PANEL2
			continue
		var fw: float = sim.forecast_wet_at(tl)
		var icon := "🌧" if fw >= 0.55 else ("🌦" if fw >= 0.2 else "☀")
		sb.bg_color = Color("#1e3a8a") if fw >= 0.55 else (Color("#1e3350") if fw >= 0.2 else K.PANEL2)
		r.text = "[center][b]L%d[/b] %s\n%d%% · %.1fmm[/center]" % [tl, icon, sim.forecast_prob_at(tl), sim.wet_mm(fw)]
	# 타이어 선택
	var ns: Variant = sim.next_stop(c)
	if String(d["comp"]) == "":
		var it: String = sim.ideal_tyre(sim.wet)
		d["comp"] = (String(ns["comp"]) if ns != null else "M") if it == "slick" else it
	if wec:
		d["comp"] = sim.wec_fit_comp(c.cls, String(d["comp"]))
	var allowed: Array = sim.wec_comps(c.cls) if wec else ["S", "M", "H"]
	for i in _tyre_btns.size():
		var comp: String = _tyre_keys[i]
		var b: Button = _tyre_btns[i]
		b.visible = not (wec and (comp == "I" or (RS.SLICK.has(comp) and not allowed.has(comp))))
		var sub: String = RS.TYRE_KO[comp]
		if wec:
			pass # WEC 새 세트 수는 컴파운드 공용이라 아래 한 줄에만 표시
		elif RS.SLICK.has(comp) and c.tyre_sets != null and c.tyre_sets.has(comp):
			var rem := int(c.tyre_sets[comp])
			sub = "새 %d세트" % rem if rem > 0 else "헌 (+0.45s)"
		b.text = "%s\n%s" % [comp, sub]
		b.set_pressed_no_signal(comp == String(d["comp"]))
		b.disabled = wec and not bool(d["tyres"])
	# WEC 옵션
	_w_opts.visible = wec
	if wec:
		_w_fuel_fill.anchor_right = clampf(c.fuel / RS.TANK, 0.0, 1.0)
		_press(_w_tyre_btns, [["yes"], ["no"]], "yes" if d["tyres"] else "no")
		_press(_w_fuel_btns, [["yes"], ["no"]], "yes" if d["fuel"] else "no")
		_press(_w_drv_btns, [["no"], ["yes"]], "yes" if d["driver"] else "no")
	# 상태줄 · 확정/철수
	var booked: bool = c.pit_req != "" or c.boxing != null
	var in_lane: bool = sim.is_pitting(c)
	var st := ""
	if c.crew_cooldown > 0:
		st = "[color=#ef4444]⛔ 크루 복귀 대기 (%d랩 동안 피트 불가)[/color]" % c.crew_cooldown
	elif in_lane:
		st = "[color=#ffc53d]🔧 피트레인 진입 (작업 중)[/color]"
	elif booked:
		var what: String = RS.TYRE_KO[c.pit_req] if c.pit_req != "" else RS.TYRE_KO[c.boxing["comp"]]
		if c.wec_req != null:
			what = ("%s 교체" % what if c.wec_req["tyres"] else "타이어 유지") + (" + 급유" if c.wec_req["fuel"] else "") + (" + 교대" if c.wec_req["driver"] else "")
		st = "[color=#22c55e]✅ 크루 대기 (CREW OUT) · 이번 랩 %s[/color]" % what
	else:
		var sets_txt := ""
		if wec:
			sets_txt = " · 새 드라이 %d세트 남음 (규정: %s)" % [c.wec_sets, "·".join(PackedStringArray(allowed))]
		elif c.tyre_sets != null:
			sets_txt = " · 새 타이어 S:%d M:%d H:%d" % [int(c.tyre_sets["S"]), int(c.tyre_sets["M"]), int(c.tyre_sets["H"])]
		var est := ""
		if wec:
			est = " · 예상 정차 약 %d초" % int(round(sim.wec_stop_time(c, bool(d["tyres"]), bool(d["driver"]), bool(d["fuel"]))))
		st = "[color=#ffc53d]선택: %s(%s)%s%s[/color]" % [RS.TYRE_KO[d["comp"]], d["comp"], sets_txt, est]
	_pit_status.text = st
	_confirm.text = ("🔄 %s로 예약 변경" if booked else "✅ %s 핏스탑 확정") % RS.TYRE_KO[d["comp"]]
	_confirm.disabled = not c.is_running() or in_lane or c.crew_cooldown > 0
	_cancel.disabled = not booked or in_lane
	# 플랜
	_plan_box.visible = not wec and not sim.rules.get("no_pits", false)
	if _plan_box.visible:
		for pi in 2:
			var key: String = ["A", "B"][pi]
			_plan_btns[pi].disabled = not c.plans.has(key)
			_plan_btns[pi].set_pressed_no_signal(c.plans.has(key) and c.active_plan == key)
		_auto.set_pressed_no_signal(c.auto_plan)
		var pa: String = sim.plan_text(c, "A")
		var pb: String = sim.plan_text(c, "B")
		var nxt: String = ("권장 박스 [b]L%d → %s[/b]" % [int(ns["lap"]), RS.TYRE_KO[ns["comp"]]]) if ns != null else "남은 권장 스톱 없음"
		_replan.visible = c.custom_plans
		_plan_line.text = "%s%s\n[color=#8b98a5]A: %s   B: %s%s[/color]" % [nxt, "  [color=#a855f7](직접 설계한 계획)[/color]" if c.custom_plans else "", pa if pa != "" else "-", pb if pb != "" else "-", ("\n[color=#38bdf8]자동 피트 켜짐: 계획 랩에 알아서 박스하고 노면 변화에도 대응해요[/color]" if c.auto_plan else "")]
	_p_radio.text = _radio_line(c)


func _nm(o) -> String:
	if sim.is_wec():
		var n: String = o.team
		for w in [" Racing", " Team", " Endurance", " TotalEnergies", " Hertz", " Gazoo"]:
			n = n.replace(w, "")
		return "%s #%d" % [n, o.slot + 1]
	return o.code


func _refresh_power(c) -> void:
	var wec: bool = sim.is_wec()
	_ers_box.visible = not wec
	if not wec:
		_ers_head.text = "[color=#8b98a5]ERS 배치[/color]   배터리 [b]%s[/b]" % _pct(c.ers)
		_press(_ers_btns, ERS_ITEMS, c.ers_mode)
		_ers_fill.anchor_right = clampf(c.ers, 0.0, 1.0)
		_ers_fill.color = K.BAD if c.ers < 0.15 else K.AMBER
	_press(_fuel_btns, FUEL_ITEMS, c.fuel_mode)
	var left: int = maxi(0, sim.laps - c.lap)
	if wec:
		var fl: float = sim.fuel_laps(c)
		var full_s: float = RS.TANK / sim._wec_burn(c, "std")
		var full_l: float = RS.TANK / sim._wec_burn(c, "lean")
		_fuel_head.text = "[color=#8b98a5]연료 모드[/color]   남은 연료 [b]%.1f랩분[/b]  [color=#8b98a5]· 가득 채우면 표준 %.1f랩 / 세이브 %.1f랩 (지금 페이스 기준)[/color]" % [fl, full_s, full_l]
		_fuel_hint.text = "[color=#8b98a5]세이브는 느린 대신 급유 간격을 늘려요. 리치는 빠르지만 연료를 더 써요. 막판엔 세이브로 마지막 급유를 건너뛸 수도 있어요.[/color]"
		var fat: float = sim.fatigue(c)
		var fcol: String = "#ef4444" if fat > 0.45 else ("#f59e0b" if fat > 0.25 else "#22c55e")
		var t := "[b]드라이버[/b] %s (등급 %s) · 이번 차 %d스틴트째 · 피로 [color=%s][b]%d%%[/b][/color]%s" % [c.name, String(c.drivers[c.drv].get("grade", "-")), c.stint_drv + 1, fcol, int(round(fat * 100)), " [color=#8b98a5](밤엔 빨리 쌓여요)[/color]" if sim.night else ""]
		var lim: Dictionary = sim.drive_limits()
		var inw: int = sim.drive_in_window(c, c.drv)
		var wcol: String = "#ef4444" if sim.must_swap(c) else "#8b98a5"
		t += "\n[color=%s]주행 시간: 최근 6시간 구간 %d/%d랩[/color]" % [wcol, inw, int(lim["max_win"])]
		if int(lim["max_total"]) < sim.laps:
			t += "[color=#8b98a5] · 누적 %d/%d랩 · 최소 %d랩[/color]" % [int(c.drv_laps[c.drv]) if c.drv < c.drv_laps.size() else 0, int(lim["max_total"]), int(lim["min_each"])]
		if sim.must_swap(c):
			t += "\n[color=#f59e0b]⚠ 한 스틴트 더 달리면 주행 시간 초과 → 다음 피트에서 교대 필요[/color]"
		var others: PackedStringArray = []
		for di in c.drivers.size():
			if di != c.drv:
				var dn: String = String(c.drivers[di]["name"])
				others.append("%s 피로 %d%%" % [dn.substr(dn.find(" ") + 1) if dn.find(". ") == 1 else dn, int(round(sim.fatigue(c, di) * 100))])
		if not others.is_empty():
			t += "\n[color=#8b98a5]대기: %s[/color]" % " · ".join(others)
		t += "\n[color=#8b98a5]타이어 %d스틴트째 · 새 드라이 %d세트 남음 · 피트 %d회[/color]" % [c.stint_tyre + 1, c.wec_sets, c.pits]
		if sim.min_drive != null:
			var short: int = sim.min_drive_short(c)
			var gk: String = RS.GRADE_KO.get(sim.min_drive["grade"], "")
			t += ("\n[color=#22c55e]%s 최소 주행 충족[/color]" % gk) if short <= 0 else ("\n[color=#f59e0b]%s 드라이버가 %d랩 더 달려야 해요 (미달 시 60초)[/color]" % [gk, short])
		_drv_info.text = t
		_drv_info.visible = true
	else:
		var need: float = left * RS.FPL * float(RS.FUEL[c.fuel_mode][1]) * c.fuel_burn_rate
		var margin: float = (c.fuel - need) / (RS.FPL * c.fuel_burn_rate)
		_fuel_head.text = "[color=#8b98a5]연료 모드[/color]   %s" % ("[color=#22c55e]여유 %+.1f랩[/color]" % margin if margin >= 0 else "[color=#ef4444]부족 %.1f랩 → 세이브 필요[/color]" % -margin)
		_fuel_hint.text = "[color=#8b98a5]남은 %d랩. 리치는 빠르지만 연료를 약 8%% 더 쓰고, 세이브는 랩당 약 0.5초 느린 대신 10%% 아껴요.[/color]" % left
		_drv_info.visible = false


func _refresh_laps(c) -> void:
	var fast := "-"
	if sim.fastest_id >= 0:
		for o in sim.cars:
			if o.id == sim.fastest_id:
				fast = "%s %s" % [o.code, K.fmt_lap(sim.fastest_t)]
	var last: String = K.fmt_lap(c.last_lap_t) if c.last_lap_t > 0.0 else "-"
	var best: String = K.fmt_lap(c.best) if c.best < INF else "-"
	var t := "[color=#8b98a5]전체 최고[/color] [color=#a855f7][b]%s[/b][/color]\n" % fast
	t += "[color=#8b98a5]직전 랩[/color] [font_size=20][b]%s[/b][/font_size]    [color=#8b98a5]개인 최고[/color] [font_size=20][b][color=#22c55e]%s[/color][/b][/font_size]\n" % [last, best]
	var secs: Array = c.last_sec_times
	if not secs.is_empty():
		var parts: PackedStringArray = []
		for i in secs.size():
			parts.append("S%d %.1f" % [i + 1, float(secs[i])])
		t += "[color=#8b98a5]직전 랩 섹터[/color]  %s\n" % "  ·  ".join(parts)
	t += "[color=#8b98a5]최근 랩 기록 · 트랙 그립 %d%%[/color]\n" % int(round(sim.track_evo * 100))
	var n := 0
	for h in c.lap_hist:
		n += 1
		if n > 8:
			break
		var hcol := "#a855f7" if absf(float(h["t"]) - c.best) < 0.001 else "#e6edf3"
		t += "L%-3d %s %s  [color=%s]%s[/color]%s\n" % [int(h["lap"]), "[color=%s]●[/color]" % RS.TYRE_HEX[h["comp"]], RS.TYRE_KO[h["comp"]], hcol, K.fmt_lap(float(h["t"])), " [color=#ffc53d]PIT[/color]" if h.get("pit", false) else ""]
	_laps_rtl.text = t


# ═════════ 입력 ═════════
func _on_chip(i: int) -> void:
	sel = i
	select_car.emit(i)
	refresh()


func _on_tab(t: String) -> void:
	tab = t
	for i in TABS.size():
		_tab_btns[i].set_pressed_no_signal(TABS[i][0] == t)
		_tab_btns[i].add_theme_color_override("font_color", K.AMBER if TABS[i][0] == t else K.DIM)
		_pages[TABS[i][0]].visible = TABS[i][0] == t
	refresh()


func _on_prompt(i: int) -> void:
	sim.resolve_radio(i)
	refresh()


func _on_pace(v: String) -> void:
	var c = car()
	if c != null:
		sim.set_pace(c, v)


func _on_instr(v: String) -> void:
	var c = car()
	if c != null:
		sim.set_instr(c, v)


func _on_ers(v: String) -> void:
	var c = car()
	if c != null:
		sim.set_ers(c, v)


func _on_fuel(v: String) -> void:
	var c = car()
	if c != null:
		sim.set_fuel_mode(c, v)


func _on_draft_comp(comp: String) -> void:
	draft[sel]["comp"] = comp
	refresh()


func _on_w_tyres(v: String) -> void:
	draft[sel]["tyres"] = v == "yes"
	refresh()


func _on_w_fuel(v: String) -> void:
	draft[sel]["fuel"] = v == "yes"
	refresh()


func _on_w_drv(v: String) -> void:
	draft[sel]["driver"] = v == "yes"
	refresh()


func _on_confirm() -> void:
	var c = car()
	if c == null:
		return
	var d: Dictionary = draft[sel]
	if sim.is_wec():
		sim.request_pit_wec(c, String(d["comp"]), bool(d["tyres"]), bool(d["fuel"]), bool(d["driver"]))
	else:
		sim.request_pit(c, String(d["comp"]))
	refresh()


func _on_cancel() -> void:
	var c = car()
	if c != null:
		sim.cancel_pit(c)
		refresh()


func _on_plan(k: String) -> void:
	var c = car()
	if c != null:
		sim.set_plan(c, k)
		refresh()


func _on_auto(on: bool) -> void:
	var c = car()
	if c != null:
		sim.set_auto(c, on)
		refresh()


func _on_replan() -> void:
	var c = car()
	if c != null:
		sim.reset_plans(c)
		refresh()


func _on_order(v: String) -> void:
	sim.set_team_order(v)


func _on_swap() -> void:
	sim.request_swap()
	refresh()
