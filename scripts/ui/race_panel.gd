extends VBoxContainer
## 레이스 지시판 (HTML판 구성을 옮김)
## 엔지니어 제안 카드 · 내 차 칩 2개 · 선택한 차의 탭(주행 / 피트 / ERS·연료 / 랩타임) · 팀 오더.
## sim 상태를 읽어 그리고, 버튼은 sim 의 공개 함수만 부른다.

signal select_car(slot: int)
signal radio_prompt  # 새 엔지니어 제안이 떴을 때 (main 이 배속을 1×로)
signal tab_changed(t: String)  # 랩타임 탭에서만 상세 순위·무전을 보여주려고 main 이 듣는다

const K = preload("res://scripts/ui/kit.gd")
const RS = preload("res://scripts/sim/race_sim.gd")
const ChartS = preload("res://scripts/ui/strat_chart.gd")

const TABS := [["drive", "주행"], ["pit", "피트"], ["power", "ERS·연료"], ["laps", "랩타임"], ["strat", "전략"]]
const INSTR := [["free", "자유"], ["attack", "추월"], ["defend", "방어"], ["hold", "유지"], ["lift", "연비"]]
const PACE_ITEMS := [["attack", "공격"], ["standard", "표준"], ["save", "세이브"]]
const ERS_ITEMS := [["harvest", "충전"], ["balance", "밸런스"], ["deploy", "오버테이크"]]
const FUEL_ITEMS := [["lean", "세이브"], ["std", "표준"], ["rich", "리치"]]
const COLD := Color("#38bdf8")

var sim = null
var sel := 0
var tab := "drive"
## 피트 설정 초안 (WEC 드라이버는 기본 '교대' — 주행 시간 규정 때문에 보통 교대가 맞다)
var draft: Array = [{"comp": "", "tyres": true, "fuel": true, "driver": true, "drv": -1, "fuel_pick": "yes", "fill": 1.0}, {"comp": "", "tyres": true, "fuel": true, "driver": true, "drv": -1, "fuel_pick": "yes", "fill": 1.0}]
var _pits_seen: Array = [0, 0]
var _wec_comp_set := {}     # WEC 기본 컴파운드를 엔지니어 계산으로 넣었는지 ("차 id:피트 수")
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
var _pace_fx: RichTextLabel
var _d_instr_head: RichTextLabel
var _instr_btns: Array = []
var _instr_fx: RichTextLabel
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
var _wx_line: RichTextLabel # 섹터별 노면 + 크로스오버 (젖었을 때만)
var _w_opts: VBoxContainer
var _w_tyre_btns: Array = []
var _w_fuel_btns: Array = []
var _w_drv_btns: Array = []
var _w_fuel_fill: ColorRect
var _w_fuel_sl: HSlider       # WEC 급유 목표 (탱크 대비 0~1)
var _w_fuel_minus: Button     # 급유 −0.5랩 (표준 모드 기준)
var _w_fuel_plus: Button
var _w_fuel_txt: RichTextLabel
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
var _drv_card: PanelContainer
# 랩타임
var _laps_rtl: RichTextLabel
# 전략 뷰
var _st_pred: RichTextLabel
var _st_cut: RichTextLabel
var _st_chart: Control
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
		b.custom_minimum_size = Vector2(0, 98)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_on_chip.bind(i))
		# 내 차 카드: 선택되면 왼쪽 호박색 막대 + 밝은 바탕 (글씨 색은 그대로)
		var cn = _box(K.PANEL2, K.LINE, 6)
		var cp = _box(Color("#262b35"), K.AMBER, 6)
		cp.set_border_width_all(0)
		cp.border_width_left = 5
		for st in ["normal", "hover", "disabled"]:
			b.add_theme_stylebox_override(st, cn)
		for st in ["pressed", "hover_pressed"]:
			b.add_theme_stylebox_override(st, cp)
		var r = K.rtl(16)
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
		b.clip_text = true
		# 탭: 칸마다 테두리가 있는 버튼, 선택된 탭은 빨강 바탕 (구분이 확실하게)
		var tn = _box(K.PANEL2, Color("#454c59"), 6)
		var tp = _box(K.RED, K.RED, 6)
		for st in ["normal", "hover", "disabled", "focus"]:
			b.add_theme_stylebox_override(st, tn)
		for st in ["pressed", "hover_pressed"]:
			b.add_theme_stylebox_override(st, tp)
		b.add_theme_color_override("font_pressed_color", Color.WHITE)
		b.add_theme_color_override("font_hover_pressed_color", Color.WHITE)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	_st_pred = _rt(_pages["strat"], 14)
	_st_cut = _rt(_pages["strat"], 14)
	_st_chart = ChartS.new()
	_pages["strat"].add_child(_st_chart)
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
	sb.set_corner_radius_all(2)
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


## 고른 페이스·지시의 장점/대가 한 줄
func _fx_line(c, kind: String, key: String) -> String:
	var fx: Dictionary = sim.mode_effects(c, kind, key)
	var pros: Array = fx["pros"]
	var cons: Array = fx["cons"]
	var parts: PackedStringArray = []
	if not bool(fx["active"]):
		var wr: String = String(fx.get("wait_reason", ""))
		parts.append("[color=#f59e0b][b][대기 중%s][/b][/color]" % ((" · " + wr) if wr != "" else ""))
	if not pros.is_empty():
		parts.append("[color=#22c55e]장점: %s[/color]" % " · ".join(PackedStringArray(pros)))
	if not cons.is_empty():
		parts.append("[color=#ef4444]대가: %s[/color]" % " · ".join(PackedStringArray(cons)))
	if parts.is_empty():
		return "[color=#8b98a5]기준 상태 (추가 득실 없음)[/color]"
	return "  /  ".join(parts)


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
	_pace_fx = _rt(pg, 13)
	_d_instr_head = _rt(pg, 14)
	_instr_btns = _seg_row(pg, INSTR, _on_instr)
	_instr_fx = _rt(pg, 13)
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
	_wx_line = _rt(pg, 12)
	# WEC: 타이어 교체 여부 · 급유 · 교대
	_w_opts = K.vbox(4)
	pg.add_child(_w_opts)
	_w_fuel_fill = _meter(_w_opts, K.AMBER, 6.0)
	var wr = K.hbox(4)
	_w_opts.add_child(wr)
	_w_tyre_btns = _seg(wr, [["yes", "타이어 교체"], ["no", "타이어 유지"]], _on_w_tyres, 13)
	var wr2 = K.hbox(4)
	_w_opts.add_child(wr2)
	_w_fuel_btns = _seg(wr2, [["yes", "급유 하기"], ["none", "급유 안 함"]], _on_w_fuel, 13)
	# 급유량 직접 조절: 급유 후 연료(탱크 대비). 적게 넣으면 정차가 짧고 차가 가벼워 빠르지만 일찍 다시 들어와야 한다
	_w_fuel_sl = HSlider.new()
	_w_fuel_sl.min_value = 0.0
	_w_fuel_sl.max_value = 1.0
	_w_fuel_sl.step = 0.01
	_w_fuel_sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_w_fuel_sl.custom_minimum_size = Vector2(0, 28)
	_w_fuel_sl.value_changed.connect(_on_w_fuel_sl)
	# 슬라이더 양옆 −/+ : 손가락으로 미세 조절이 어려워 0.5랩씩
	var frow = K.hbox(6)
	_w_opts.add_child(frow)
	_w_fuel_minus = K.btn("−", 18, _on_w_fuel_step.bind(-1))
	_w_fuel_plus = K.btn("+", 18, _on_w_fuel_step.bind(1))
	for b in [_w_fuel_minus, _w_fuel_plus]:
		b.size_flags_horizontal = Control.SIZE_FILL
		b.custom_minimum_size.x = 48
	frow.add_child(_w_fuel_minus)
	frow.add_child(_w_fuel_sl)
	frow.add_child(_w_fuel_plus)
	_w_fuel_txt = K.rtl(12)
	_w_opts.add_child(_w_fuel_txt)
	# 다음 스틴트 드라이버: 크루 3명 중 직접 고른다 (지금 운전 중인 사람 = 유지)
	var wr3 = K.hbox(4)
	_w_opts.add_child(wr3)
	_w_drv_btns = []
	for i in 3:
		var db = K.btn("", 12)
		db.toggle_mode = true
		db.custom_minimum_size = Vector2(0, 54)
		db.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		db.size_flags_stretch_ratio = 1.0
		# 긴 줄("0랩 · 피로 0% · 최소 주행 6랩 남음")이 버튼을 넓혀 패널이 화면 밖으로 밀리지 않게 줄바꿈
		db.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		db.clip_text = false
		db.pressed.connect(_on_w_drv.bind(i))
		wr3.add_child(db)
		_w_drv_btns.append(db)
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
	# WEC: 드라이버 정보 카드를 맨 위에 크게 (피로 · 주행 시간 · 대기 드라이버)
	_drv_card = PanelContainer.new()
	_drv_card.add_theme_stylebox_override("panel", _box(K.PANEL2, Color("#454c59"), 10))
	pg.add_child(_drv_card)
	_drv_info = K.rtl(16)
	_drv_card.add_child(_drv_info)
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
		d["fuel_pick"] = "yes"
		d["fill"] = 1.0
		d["driver"] = true
	_pits_seen = [0, 0]
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
			# 카드는 짧게: 집중력은 낮을 때만 경고 (자세한 건 주행 탭)
			var fv := int(round(c.focus))
			badge = ("[color=#ef4444]집중 %d%%[/color]" % fv) if fv <= 55 else ""
		var temp_col := "#38bdf8" if c.tt < 0.42 else ("#ef4444" if c.tt > 0.8 else "#22c55e")
		var extra: String = ("연료 %.1f랩" % sim.fuel_laps(c)) if wec else (("ERS " + _pct(c.ers)) if sim.has_ers() else ("연료 %+.1f랩" % (c.fuel / maxf(0.01, RS.FPL * c.fuel_burn_rate * float(RS.FUEL[c.fuel_mode][1])) - float(maxi(0, sim.laps - c.lap)))))

		var line2: String = c.dnf if c.dnf != "" else "[color=%s][b]%s[/b][/color] %s [color=%s]●[/color] %s" % [RS.TYRE_HEX[c.comp], c.comp, _pct(c.wear), temp_col, extra]
		if c.mech_trouble != "":
			line2 += " [color=#ef4444]⚠%s[/color]" % c.mech_trouble
		if c.fault != null:
			line2 += " [color=#ef4444]🔧%s +%.1fs%s[/color]" % [c.fault["kind"], float(c.fault["dt"]), " (수리 예정)" if bool(c.fault["repair"]) else ""]
		if c.time_pen > 0.0:
			# 카드는 좁아서 빨간 "+5"만 (사유는 차 정보 창·결과에)
			line2 += " [color=#ef4444]+%d[/color]" % int(c.time_pen)
		elif c.tl_warn > 0 and c.dnf == "":
			line2 += " [color=#f59e0b]TL %d/2[/color]" % c.tl_warn
		var code: String = ("#%d %s" % [c.slot + 1, c.code]) if wec else c.code
		# 셋째 줄: 이 타이어로 몇 랩째 · 마모 추세로 본 남은 랩 · 최근 랩타임
		var line3 := ""
		if c.dnf == "":
			var rate: float = c.wear / maxf(1.0, float(c.stint_laps))
			var lim: float = RS.H_CLIFF if c.comp == "H" else 0.70
			var rem_t := "-"
			if c.stint_laps >= 1 and rate > 0.0005 and RS.SLICK.has(c.comp):
				rem_t = "+%d" % maxi(0, int((lim - c.wear) / rate))
			# 칸이 좁아서 짧게: "3랩째(+5) 1:18.7" = 이 타이어 3랩째, 약 5랩 더, 최근 랩
			var lt: float = c.last_lap_t
			var lt_t: String = ("%d:%04.1f" % [int(lt) / 60, fmod(lt, 60.0)]) if lt > 0.0 else "-"
			line3 = "%d랩째(%s) %s" % [c.stint_laps, rem_t, lt_t]
			# 등급 최소 주행(브론즈 등)은 칩에서도 늘 보이게: "3랩째 1:18.7 브론즈 4/8" (자리 때문에 남은 랩 추정은 뺌)
			if wec and sim.min_drive_done(c) >= 0:
				var mdn: int = sim.min_drive_need(c)
				var mdd: int = sim.min_drive_done(c)
				line3 = "%d랩째 %s [color=%s]%s %d/%d[/color]" % [c.stint_laps, lt_t, "#22c55e" if mdd >= mdn else "#f59e0b", RS.GRADE_KO.get(String(sim.min_drive["grade"]), ""), mdd, mdn]
		_chip_txt[i].text = "[font_size=30][b]%s[/b][/font_size]  [b]%s[/b]  %s\n[color=#8b98a5]%s[/color]\n[color=#e6edf3]%s[/color]" % [pos, code, badge, line2, line3]
	var c = car()
	if c == null:
		return
	_tab_btns[2].text = "드라이버/연료" if wec else ("ERS·연료" if sim.has_ers() else "연료")
	# 탭이 좁으면(가로 화면) 글자를 줄여서 다 보이게
	for b in _tab_btns:
		var bw: float = b.size.x - 12.0
		if bw > 10.0:
			var f: Font = b.get_theme_font("font")
			var fs := 16
			while fs > 11 and f.get_string_size(b.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > bw:
				fs -= 1
			if b.get_theme_font_size("font_size") != fs:
				b.add_theme_font_size_override("font_size", fs)
	match tab:
		"drive":
			_refresh_drive(c, ord)
		"pit":
			_refresh_pit(c)
		"power":
			_refresh_power(c)
		"strat":
			_refresh_strat(c)
		_:
			_refresh_laps(c)
	# 팀 오더: 두 대 모두 달릴 때 (WEC 는 같은 클래스끼리만 — sim 도 같은 클래스 팀메이트에만 적용)
	var both: bool = mc.size() == 2 and mc[0].is_running() and mc[1].is_running() and mc[0].cls == mc[1].cls
	_order_row.visible = both and tab == "drive" # 팀 오더는 주행 탭에서만
	_press(_order_btns, [["free"], ["hold"]], sim.team_order)
	_swap_btn.disabled = sim.swap_req


func _refresh_drive(c, ord: Array) -> void:
	var g := _gap_str(c, ord)
	var fv := int(round(c.focus))
	var fs := "🔥 존 진입" if fv >= 85 else ("⚠ 흔들림 (실수 주의)" if fv <= 55 else "안정적")
	_d_head.text = "[color=#8b98a5]페이스%s · 집중력 %d%% (%s)[/color]   [b]앞 %s · 뒤 %s[/b]" % [(" · " + c.name) if sim.is_wec() else "", fv, fs, g[0], g[1]]
	_press(_pace_btns, PACE_ITEMS, c.pace)
	_pace_fx.text = _fx_line(c, "pace", c.pace)
	var mech: String = ("[color=#ef4444]⚠ %s (리프트 앤 코스트로 식혀요)[/color]" % c.mech_trouble) if c.mech_trouble != "" else "[color=#8b98a5]기계 부하 %d%% (정상)[/color]" % int(round(c.mech_stress * 100))
	_d_instr_head.text = "[color=#8b98a5]상황 지시[/color] · %s" % mech
	for i in _instr_btns.size():
		var ik: String = String(INSTR[i][0])
		var base_lbl: String = String(INSTR[i][1])
		var waiting: bool = (ik == "attack" or ik == "defend" or ik == "hold") and not sim.instr_active(c, ik)
		# 대기 중이면 글자는 그대로, 색만 주황 (폰 가로에서 "(대기)" 가 잘림)
		if _instr_btns[i].text != base_lbl:
			_instr_btns[i].text = base_lbl
		if waiting:
			_instr_btns[i].add_theme_color_override("font_color", K.AMBER)
			_instr_btns[i].add_theme_color_override("font_pressed_color", Color("#b45309"))
		else:
			_instr_btns[i].remove_theme_color_override("font_color")
			_instr_btns[i].remove_theme_color_override("font_pressed_color")
	_press(_instr_btns, INSTR, c.instr)
	_instr_fx.text = _fx_line(c, "instr", c.instr)
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
	if not wec and sim.pit_closed():
		_pred.text = "[color=#ef4444][b]⛔ 피트레인 폐쇄 중 (L%d 까지)[/b] — 지금 들어가면 스톱 앤 고 10초 페널티[/color]\n" % sim.pit_closed_until + _pred.text
	# 기상 레이더 (내 팀 예보 — 팀 전략 능력만큼 오차, 랩마다 갱신)
	var cur: int = mini(sim.laps, sim.leader_lap + 1)
	# 앞으로 5랩 동안 비 걱정이 없으면 칸 대신 한 줄만
	var calm: bool = sim.wet < 0.05
	for i in 5:
		if cur + i + 1 <= sim.laps and (sim.forecast_wet_at(cur + i + 1, c) >= 0.2 or sim.forecast_prob_at(cur + i + 1, c) >= 40):
			calm = false
	_radar_row.visible = not calm
	_wx_line.visible = sim.wet >= 0.03 or sim.ever_wet
	if calm:
		_radar_head.text = "[color=#8b98a5]날씨[/color]  ☀ 앞으로 5랩 비 걱정 없음 [color=#8b98a5](강수확률 %d%%)[/color]" % sim.forecast_prob_at(cur, c)
	else:
		_radar_head.text = "[color=#8b98a5]기상 레이더 · 팀 예보 정확도 %s[/color]  지금 강수확률 [b]%d%%[/b] · 노면 수막 [b]%.1fmm[/b] [color=#8b98a5](인터 1.2mm · 웻 3.5mm부터)[/color]" % [_fc_grade(sim.fc_q(c)), sim.forecast_prob_at(cur, c), sim.wet_mm(sim.wet)]
	for i in 5:
		var tl: int = cur + i + 1
		var r: RichTextLabel = _radar[i]
		var sb: StyleBoxFlat = _radar_sb[i]
		if tl > sim.laps:
			r.text = "[center][color=#8b98a5]FIN[/color][/center]"
			sb.bg_color = K.PANEL2
			continue
		var fw: float = sim.forecast_wet_at(tl, c)
		var icon := "🌧" if fw >= 0.55 else ("🌦" if fw >= 0.2 else "☀")
		sb.bg_color = Color("#1e3a8a") if fw >= 0.55 else (Color("#1e3350") if fw >= 0.2 else K.PANEL2)
		r.text = "[center][b]L%d[/b] %s\n%d%% · %.1fmm[/center]" % [tl, icon, sim.forecast_prob_at(tl, c), sim.wet_mm(fw)]
	if _wx_line.visible:
		_wx_line.text = _wx_text(c)
	# 타이어 선택
	var ns: Variant = sim.next_stop(c)
	if String(d["comp"]) == "":
		var it: String = sim.ideal_tyre(sim.wet)
		d["comp"] = (String(ns["comp"]) if ns != null else "M") if it == "slick" else it
	# WEC 하이퍼카: 다음 타이어로 달릴 구간 가운데의 예상 노면 온도 → 컴파운드마다 온도 창 안/밖 (수정 24)
	var run_n: int = sim.wec_tyre_run(c, int(sim.laps_to_go(c))) if wec else 0
	var run_t: float = sim.run_temp(run_n) if wec else 0.0
	if wec:
		var ck := "%d:%d" % [c.id, c.pits] # 피트를 마칠 때마다 다시 계산
		if not _wec_comp_set.has(ck):
			_wec_comp_set[ck] = true
			if sim.ideal_tyre(sim.wet) == "slick":
				d["comp"] = sim.wec_pick_comp(c, run_n, false) # 기본 = 엔지니어 계산 (플레이어가 고르면 그대로)
		d["comp"] = sim.wec_fit_comp(c.cls, String(d["comp"]))
	var allowed: Array = sim.dry_list(c)
	for i in _tyre_btns.size():
		var comp: String = _tyre_keys[i]
		var b: Button = _tyre_btns[i]
		b.visible = not (wec and (comp == "I" or (RS.SLICK.has(comp) and not allowed.has(comp))))
		var sub: String = RS.TYRE_KO[comp]
		if wec:
			# WEC 새 세트 수는 컴파운드 공용이라 아래 한 줄에만 표시. 대신 온도 창
			if RS.SLICK.has(comp) and allowed.size() > 1:
				var wo: float = sim.win_off(c.cls, comp, run_t)
				sub = "창 안" if wo == 0.0 else ("뜨거움 +%d°" % int(ceil(wo)) if wo > 0.0 else "차가움 %d°" % int(floor(wo)))
		elif RS.SLICK.has(comp) and c.tyre_sets != null and c.tyre_sets.has(comp):
			var rem := int(c.tyre_sets[comp])
			sub = "새 %d세트" % rem if rem > 0 else "쓴 세트"
		b.text = "%s\n%s" % [comp, sub]
		b.set_pressed_no_signal(comp == String(d["comp"]))
		b.disabled = wec and not bool(d["tyres"])
	# WEC 옵션
	_w_opts.visible = wec
	if wec:
		_w_fuel_fill.anchor_right = clampf(c.fuel / RS.TANK, 0.0, 1.0)
		_press(_w_tyre_btns, [["yes"], ["no"]], "yes" if d["tyres"] else "no")
		# 급유: 하기(양은 슬라이더, 기본 가득) / 안 함. 얼마나 넣을지는 플레이어 판단 — 대신 손익을 숫자로 보여준다
		var pick: String = "none" if String(d.get("fuel_pick", "yes")) == "none" else "yes"
		var fill: float = 0.0 if pick == "none" else float(d.get("fill", 1.0))
		d["fill"] = fill
		d["fuel"] = pick == "yes" and sim.fuel_add(c, fill) > 0.0
		_press(_w_fuel_btns, [["yes"], ["none"]], pick)
		_w_fuel_sl.set_value_no_signal(fill)
		_w_fuel_sl.editable = pick == "yes"
		var burn: float = maxf(0.01, sim._wec_burn(c, c.fuel_mode))
		var need_l: float = sim.laps_to_go(c)
		var after: float = maxf(c.fuel, RS.TANK * fill) / burn
		var pit_l: int = c.lap + 1
		var col: String = "#ef4444" if after < minf(need_l, 1.5) else "#e6edf3"
		var t1: String = "급유 후 [b][color=%s]%.1f랩[/color][/b] 주행 → 다음 피트 약 [b]L%d[/b] (가득이면 L%d) · 체커까지 약 %.1f랩" % [col, after, pit_l + int(after), pit_l + int(RS.TANK / burn), need_l]
		var full_after: float = maxf(c.fuel, RS.TANK)
		var my_after: float = maxf(c.fuel, RS.TANK * fill)
		if pick == "yes" and my_after < full_after - 0.05:
			var stop_gain: float = sim.wec_stop_time(c, bool(d["tyres"]), bool(d["driver"]), true, 1.0) - sim.wec_stop_time(c, bool(d["tyres"]), bool(d["driver"]), true, fill)
			var lap_gain: float = (full_after - my_after) * sim.fuel_k()
			t1 += "\n[color=#22c55e]가득 대비: 정차 −%.1f초 · 피트 아웃 직후 랩당 −%.2f초[/color] [color=#8b98a5](대신 %d랩 일찍 다시 들어와요)[/color]" % [stop_gain, lap_gain, int(RS.TANK / burn) - int(after)]
		elif pick == "yes":
			t1 += "\n[color=#8b98a5]가득: 연료 무게로 피트 아웃 직후 랩당 약 +%.1f초 — 스틴트 끝으로 갈수록 가벼워져요[/color]" % (full_after * sim.fuel_k())
		# 이 양이면 모드별 몇 랩 (지금 모드 굵게)
		var base_f: float = maxf(c.fuel, RS.TANK * fill)
		var parts: Array = []
		for kv in [["표준", "std"], ["세이브", "lean"], ["리치", "rich"]]:
			var nm: String = ("[b]%s[/b]" % kv[0]) if kv[1] == c.fuel_mode else kv[0]
			parts.append("[color=#8b98a5]%s[/color] %.1f랩" % [nm, base_f / maxf(0.01, sim._wec_burn(c, kv[1]))])
		t1 += "\n[color=#8b98a5]이 양이면[/color] " + " · ".join(parts)
		# 다음 계획 정차(없으면 체커)까지 모자라면 경고
		var nst = sim.next_stop(c)
		var stop_tgt: float = (float(nst["lap"]) - float(c.lap)) if nst != null else need_l
		if pick == "yes" and after < stop_tgt:
			var where: String = ("다음 계획 정차(L%d)" % int(nst["lap"])) if nst != null else "체커"
			t1 += "\n[color=#ef4444]⚠ %s까지 %.1f랩 모자라요 → 더 넣거나 세이브[/color]" % [where, stop_tgt - after]
		_w_fuel_txt.text = t1
		_w_fuel_minus.disabled = pick != "yes"
		_w_fuel_plus.disabled = pick != "yes"
		# 피트를 한 번 마치면 다음 피트는 다시 기본값(추천 드라이버로 교대)으로
		if c.pits != int(_pits_seen[sel]):
			_pits_seen[sel] = c.pits
			d["driver"] = true
			d["drv"] = -1
			d["fuel_pick"] = "yes"
			d["fill"] = 1.0
		var rec_d: int = sim.next_driver(c) if c.drivers.size() >= 2 else c.drv
		var rec_why := ""
		if rec_d != c.drv:
			if sim.drv_short(c, rec_d) > 0:
				# 정말 지금 바꿔야 할 때만 "의무" — 최소 주행이 남았어도 나중에 채워도 되면 "교대 차례"
				rec_why = "(의무)" if sim.swap_due(c) else "(교대 차례)"
			elif sim.night:
				rec_why = "(야간)"
			elif sim.wet > 0.2:
				rec_why = "(우천)"
		if bool(d["driver"]) and (int(d["drv"]) < 0 or int(d["drv"]) == c.drv or sim.drv_block(c, int(d["drv"])) != ""):
			d["drv"] = rec_d
		var target: int = int(d["drv"]) if bool(d["driver"]) else c.drv
		var md_g: String = String(sim.min_drive["grade"]) if sim.min_drive != null else ""
		for i in _w_drv_btns.size():
			var db: Button = _w_drv_btns[i]
			db.visible = i < c.drivers.size()
			if not db.visible:
				continue
			var dd: Dictionary = c.drivers[i]
			var gr: String = String(dd.get("grade", "-"))
			var dn: String = String(dd["name"])
			var short_n: String = dn.substr(dn.find(" ") + 1) if dn.find(". ") == 1 else dn
			var laps_i: int = int(c.drv_laps[i]) if i < c.drv_laps.size() else 0
			# 버튼이 좁아서 짧은 줄로 나눈다: 표시 / 이름 등급 / 랩·피로 / 의무 / (밤·비) 능력치
			var lines: PackedStringArray = []
			var tag: String = "유지" if i == c.drv else (("추천" + rec_why) if i == rec_d else "")
			if tag != "":
				lines.append(tag)
			lines.append("%s %s" % [short_n, RS.GRADE_KO.get(gr, gr)])
			var blk: String = sim.drv_block(c, i) if i != c.drv else ""
			if blk != "":
				lines.append("🔒 " + blk)
			else:
				lines.append("%d랩·피로%d%%" % [laps_i, int(round(sim.fatigue(c, i) * 100))])
				var short_i: int = sim.drv_short(c, i)
				if short_i > 0:
					lines.append("최소 주행 %d랩 남음" % short_i)
				elif md_g != "" and gr == md_g:
					lines.append("최소 주행 충족")
				# 밤·비일 때만 그 조건에 맞는 능력치 (자동 교대·추천이 따지는 값)
				var cond: PackedStringArray = []
				if sim.night:
					cond.append("안정%d" % int(round(float(dd.get("cons", 0.8)) * 100)))
				if sim.wet > 0.2:
					cond.append("웻%d" % int(round(float(dd.get("wet", 0.8)) * 100)))
				if not cond.is_empty():
					lines.append("·".join(cond))
			db.text = "\n".join(lines)
			db.disabled = blk != ""
			db.set_pressed_no_signal(i == target)
		c.auto_swap = bool(d["driver"])
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
			var wq: Dictionary = c.wec_req
			var to_d: int = int(wq.get("drv", -1))
			what = ("%s 교체" % what if wq["tyres"] else "타이어 유지") + ((" + 급유 %.0f%%" % (float(wq.get("fill", 1.0)) * 100.0) if float(wq.get("fill", 1.0)) < 0.98 else " + 급유") if wq["fuel"] else "") + ((" + %s 교대" % c.drivers[to_d]["name"]) if (wq["driver"] and to_d >= 0 and to_d < c.drivers.size()) else (" + 교대" if wq["driver"] else ""))
		st = "[color=#22c55e]✅ 크루 대기 (CREW OUT) · 이번 랩 %s[/color]" % what
	else:
		var sets_txt := ""
		if wec:
			sets_txt = " · 새 드라이 %d세트 남음 (규정: %s)" % [c.wec_sets, "·".join(PackedStringArray(allowed))]
			if allowed.size() > 1:
				sets_txt += "\n[color=#8b98a5]노면 지금 %d°C · 이 타이어로 달릴 %d랩 동안 약 %d°C (창: S %s · M %s · H %s)[/color]" % [int(round(sim.track_now)), run_n, int(round(run_t)), _win_txt("S"), _win_txt("M"), _win_txt("H")]
		elif c.tyre_sets != null:
			sets_txt = " · 새 타이어 S:%d M:%d H:%d" % [int(c.tyre_sets["S"]), int(c.tyre_sets["M"]), int(c.tyre_sets["H"])]
		var est := ""
		if wec:
			est = " · 예상 정차 약 %d초" % int(round(sim.wec_stop_time(c, bool(d["tyres"]), bool(d["driver"]), bool(d["fuel"]), float(d.get("fill", 1.0)))))
		st = "[color=#ffc53d]선택: %s(%s)%s%s[/color]" % [RS.TYRE_KO[d["comp"]], d["comp"], sets_txt, est]
	if sim.rules.get("no_pits", false) and not wec:
		st = "[color=#8b98a5]이 레이스는 의무 피트가 없어요 — 손상·비가 아니면 들어갈수록 손해예요.[/color]\n" + st
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


## 전략 뷰: 박스 시 복귀 순위 · 언더컷 기회/위협 · 선두 + 내 차 앞뒤 4대 스틴트 막대 (WEC 는 내 클래스)
func _refresh_strat(c) -> void:
	var pr: Variant = sim.predict_pit(c) if c.is_running() and c.started else null
	if pr == null:
		_st_pred.text = "[color=#8b98a5]레이스가 시작되면 '지금 박스하면 몇 위로 복귀하는지'와 언더컷 계산이 나와요. 트랙에는 복귀 자리가 반투명 차로 보여요.[/color]"
	else:
		var a: String = ("[b]%s[/b] 뒤 %.1f초" % [_nm(pr["ahead"][0]), float(pr["ahead"][1])]) if pr["ahead"] != null else "선두로 복귀"
		var b: String = (" · [b]%s[/b] 앞 %.1f초" % [_nm(pr["behind"][0]), -float(pr["behind"][1])]) if pr["behind"] != null else ""
		_st_pred.text = "[color=#8b98a5]지금 박스하면[/color]  [font_size=22][b]P%d → P%d[/b][/font_size]\n%s%s [color=#8b98a5]· 손실 %.1f초[/color]" % [sim.class_pos(c), int(pr["pos"]), a, b, float(pr["loss"])]
	# 언더컷: 기회 = 내가 앞차를, 위협 = 뒤차가 나를 (상대 마모는 비공개 → 달린 랩으로 추정)
	var cls_ord: Array = []
	for o in sim.order_ui():
		if o.cls == c.cls and o.dnf == "":
			cls_ord.append(o)
	var i: int = cls_ord.find(c)
	var lines: Array = []
	if sim.is_wec():
		lines.append("[color=#8b98a5]WEC 는 정차 시간(급유·교대) 차이가 커서 언더컷 대신 위 복귀 예측으로 판단해요.[/color]")
	elif i >= 0 and c.is_running():
		var op: Variant = pr["under"] if pr != null else null
		if op != null:
			if float(op["net"]) > 0.0:
				lines.append("[color=#22c55e]▲ 기회: %s 언더컷 유력 +%.1f초[/color]" % [op["code"], float(op["net"])])
			else:
				lines.append("[color=#8b98a5]▲ %s 언더컷: %.1f초 부족[/color]" % [op["code"], -float(op["net"])])
		if i + 1 < cls_ord.size():
			var th: Variant = sim.undercut_net(cls_ord[i + 1], c)
			if th != null and float(th["net"]) > 0.0:
				lines.append("[color=#ef4444]▼ 위협: %s 가 먼저 들어오면 나를 넘음 (약 %.1f초)[/color]" % [th["code"], float(th["net"])])
			elif th != null:
				lines.append("[color=#8b98a5]▼ %s 언더컷 위협 낮음 (%.1f초 모자람)[/color]" % [th["code"], -float(th["net"])])
		lines.append("[color=#6b7280]상대 마모는 비공개 — 달린 랩·컴파운드로 추정[/color]")
	_st_cut.text = "\n".join(lines)
	# 스틴트 막대: 선두 + 내 차 앞뒤 4대
	var rows: Array = []
	for j in cls_ord.size():
		if j != 0 and absi(j - i) > 4:
			continue
		var o = cls_ord[j]
		rows.append({"label": "%d %s" % [j + 1, o.code], "mine": o.mine, "sel": o == c, "stints": sim.stints(o), "est": sim.est_next_pit(o)})
	_st_chart.set_rows(rows, sim.laps, mini(sim.laps, sim.leader_lap + 1), sim.TYRE_HEX)


const GRADE_COL := {"P": "#a855f7", "G": "#ffc53d", "S": "#cbd5e1", "B": "#d97706"}


func _refresh_power(c) -> void:
	var wec: bool = sim.is_wec()
	_ers_box.visible = sim.has_ers()
	if sim.has_ers():
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
		var t := "[color=#8b98a5]지금 운전[/color]  [font_size=22][b]%s[/b][/font_size]  [color=#8b98a5]등급[/color] [color=%s]%s[/color] [color=#8b98a5]· %d스틴트째 · %d랩[/color]\n피로 [font_size=20][color=%s][b]%d%%[/b][/color][/font_size]%s" % [c.name, GRADE_COL.get(String(c.drivers[c.drv].get("grade", "-")), "#8b98a5"), RS.GRADE_KO.get(String(c.drivers[c.drv].get("grade", "-")), "-"), c.stint_drv + 1, int(c.drv_laps[c.drv]) if c.drv < c.drv_laps.size() else 0, fcol, int(round(fat * 100)), " [color=#8b98a5](밤엔 빨리 쌓여요)[/color]" if sim.night else ""]
		var lim: Dictionary = sim.drive_limits()
		var inw: int = sim.drive_in_window(c, c.drv)
		var wcol: String = "#ef4444" if sim.must_swap(c) else "#8b98a5"
		t += "\n[color=%s]주행 시간: 최근 6시간 구간 %d/%d랩[/color]" % [wcol, inw, int(lim["max_win"])]
		if int(lim["max_total"]) < sim.laps:
			t += "[color=#8b98a5] · 누적 %d/%d랩 · 최소 %d랩[/color]" % [int(c.drv_laps[c.drv]) if c.drv < c.drv_laps.size() else 0, int(lim["max_total"]), sim.min_each(c)]
		if sim.must_swap(c):
			t += "\n[color=#f59e0b]⚠ 한 스틴트 더 달리면 주행 시간 초과 → 다음 피트에서 교대 필요[/color]"
		# 대기 드라이버: 이름 · 등급 · 피로 · 지금까지 달린 랩
		var others: PackedStringArray = []
		for di in c.drivers.size():
			if di != c.drv:
				var dn: String = String(c.drivers[di]["name"])
				var gr: String = String(c.drivers[di].get("grade", "-"))
				others.append("%s[b]%s[/b] [color=%s]%s[/color] 피로 %d%% · %d랩" % ["", dn.substr(dn.find(" ") + 1) if dn.find(". ") == 1 else dn, GRADE_COL.get(gr, "#8b98a5"), RS.GRADE_KO.get(gr, gr), int(round(sim.fatigue(c, di) * 100)), int(c.drv_laps[di]) if di < c.drv_laps.size() else 0])
		if not others.is_empty():
			t += "\n[color=#8b98a5]대기:[/color]%s" % "\n   ".join(others)
		t += "\n[color=#8b98a5]타이어 %d스틴트째 · 새 드라이 %d세트 남음 · 피트 %d회[/color]" % [c.stint_tyre + 1, c.wec_sets, c.pits]
		if sim.min_drive_done(c) >= 0:
			var short: int = sim.min_drive_short(c)
			var gk: String = RS.GRADE_KO.get(sim.min_drive["grade"], "")
			var md: String = "%s 최소 주행 [b]%d/%d랩[/b]" % [gk, sim.min_drive_done(c), sim.min_drive_need(c)]
			t += ("\n[color=#22c55e]%s · 충족[/color]" % md) if short <= 0 else ("\n[color=#f59e0b]%s · %d랩 더 필요 (미달 시 60초)[/color]" % [md, short])
		_drv_info.text = t
		_drv_card.visible = true
	else:
		var need: float = left * RS.FPL * float(RS.FUEL[c.fuel_mode][1]) * c.fuel_burn_rate
		var margin: float = (c.fuel - need) / (RS.FPL * c.fuel_burn_rate)
		_fuel_head.text = "[color=#8b98a5]연료 모드[/color]   %s" % ("[color=#22c55e]여유 %+.1f랩[/color]" % margin if margin >= 0 else "[color=#ef4444]부족 %.1f랩 → 세이브 필요[/color]" % -margin)
		_fuel_hint.text = "[color=#8b98a5]남은 %d랩. 리치는 빠르지만 연료를 약 8%% 더 쓰고, 세이브는 랩당 약 0.5초 느린 대신 10%% 아껴요.[/color]" % left
		_drv_card.visible = false


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
		_tab_btns[i].add_theme_color_override("font_color", Color.WHITE if TABS[i][0] == t else K.INK)
		_pages[TABS[i][0]].visible = TABS[i][0] == t
	tab_changed.emit(t)
	refresh()


func _on_prompt(i: int) -> void:
	sim.resolve_radio(i)
	refresh()


func _on_pace(v: String) -> void:
	var c = car()
	if c != null:
		sim.set_pace(c, v)
		refresh()


func _on_instr(v: String) -> void:
	var c = car()
	if c != null:
		sim.set_instr(c, v)
		refresh()


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
	draft[sel]["fuel_pick"] = v
	if v == "yes" and float(draft[sel].get("fill", 1.0)) <= 0.001:
		draft[sel]["fill"] = 1.0
	refresh()


func _on_w_fuel_sl(v: float) -> void:
	draft[sel]["fuel_pick"] = "yes" if v > 0.001 else "none"
	draft[sel]["fill"] = v
	refresh()


## −/+ : 표준 모드 0.5랩만큼, 지금 연료 ~ 가득 사이
func _on_w_fuel_step(dir: int) -> void:
	var c = car()
	if c == null or not _w_fuel_sl.editable:
		return
	var step_f: float = 0.5 * sim._wec_burn(c, "std") / RS.TANK
	var lo: float = clampf(c.fuel / RS.TANK, 0.0, 1.0)
	_on_w_fuel_sl(clampf(_w_fuel_sl.value + dir * step_f, lo, 1.0))


func _on_w_drv(i: int) -> void:
	var c = car()
	if c == null:
		return
	draft[sel]["driver"] = i != c.drv
	draft[sel]["drv"] = i if i != c.drv else -1
	refresh()


func _on_confirm() -> void:
	var c = car()
	if c == null:
		return
	var d: Dictionary = draft[sel]
	if sim.is_wec():
		sim.request_pit_wec(c, String(d["comp"]), bool(d["tyres"]), bool(d["fuel"]), bool(d["driver"]), int(d.get("drv", -1)), float(d.get("fill", 1.0)))
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


## 컴파운드 온도 창 글자 ("~28°" · "12~40°" · "25°~")
func _win_txt(k: String) -> String:
	var w: Array = sim.tyre_win(k)
	if float(w[0]) <= 0.0:
		return "~%d°" % int(w[1])
	if float(w[1]) >= 60.0:
		return "%d°~" % int(w[0])
	return "%d~%d°" % [int(w[0]), int(w[1])]


## 예보 정확도 글자 (팀 전략 능력 0~1)
func _fc_grade(q: float) -> String:
	return "높음" if q >= 0.7 else ("보통" if q >= 0.4 else "낮음")


## 섹터별 노면 칸 + 지금 타이어 vs 대안 (랩당 차이, 예보로 뒤집히는 랩)
func _wx_text(c) -> String:
	var secs: PackedStringArray = []
	for s in sim.NS:
		var w: float = sim.sec_w(s)
		var col: String = "#8b98a5" if w < 0.05 else ("#7dd3fc" if w < 0.22 else ("#22c55e" if w < 0.65 else "#3b82f6"))
		var dry_line: String = "·" if sim.off_gap(s) >= 0.08 else "" # 라인만 마른 섹터
		secs.append("[color=%s]S%d %.1f%s[/color]" % [col, s + 1, sim.wet_mm(w), dry_line])
	var t: String = "[color=#8b98a5]노면(mm)[/color] " + "  ".join(secs)
	var gap := 0.0
	for s in sim.NS:
		gap = maxf(gap, sim.off_gap(s))
	if gap >= 0.08:
		t += "  [color=#8b98a5](· = 라인만 마름 → 추월 어려움)[/color]"
	var xo: Dictionary = sim.crossover(c)
	var cur_ko: String = "슬릭" if sim.kind_of(c.comp) == "slick" else String(sim.TYRE_KO[c.comp])
	var alt_ko: String = "슬릭" if xo["alt"] == "slick" else String(sim.TYRE_KO[xo["alt"]])
	var now: float = float(xo["now"])
	var line: String
	if now > 0.0:
		var loss: float = sim.wec_stop_time(c, true, false) if sim.is_wec() else sim.pit_loss()
		var pay: int = int(ceil(loss / maxf(0.05, now)))
		line = "[color=#f59e0b]지금 %s 랩당 %.1f초 빠름[/color] [color=#8b98a5](피트 손실 약 %d초 → %d랩이면 회수)[/color]" % [_iga(alt_ko), now, int(round(loss)), pay]
	else:
		line = "[color=#22c55e]지금 %s 유지가 랩당 %.1f초 빠름[/color]" % [cur_ko, -now]
	if int(xo["lap"]) > 0:
		line += " · [b]L%d쯤 뒤집힘[/b] [color=#8b98a5](팀 예보)[/color]" % int(xo["lap"])
	return t + "\n[color=#8b98a5]%s vs %s:[/color] %s" % [cur_ko, alt_ko, line]


## 받침 이/가 (마지막 글자에 받침이 있으면 "이")
static func _iga(w: String) -> String:
	var u: int = w.unicode_at(w.length() - 1)
	return w + ("이" if u >= 0xAC00 and u <= 0xD7A3 and (u - 0xAC00) % 28 != 0 else "가")
