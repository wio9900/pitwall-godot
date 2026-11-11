extends Control
## 메인 화면: 레이스 설정 메뉴 → 레이스 진행 HUD → 결과.
## UI는 모두 코드로 만든다(씬 파일을 손으로 편집하지 않아도 되도록).

const RaceSimS = preload("res://scripts/sim/race_sim.gd")
const RaceViewS = preload("res://scripts/ui/race_view.gd")
const DB = preload("res://scripts/data/game_db.gd")

const BG := Color("#0b0f14")
const PANEL := Color("#141a22")
const PANEL2 := Color("#1b232d")
const LINE := Color("#2a3441")
const INK := Color("#e6edf3")
const DIM := Color("#8b98a5")
const AMBER := Color("#ffc53d")
const GOOD := Color("#22c55e")
const BAD := Color("#ef4444")
const SPEEDS := [0, 1, 2, 4, 8, 16]

var sim = null
var speed_x := 4
var ui_timer := 0.0
var last_settings := {}

# 메뉴
var menu_box: Control
var opt_circuit: OptionButton
var opt_team: OptionButton
var opt_laps: OptionButton
var opt_weather: OptionButton
var opt_start: Array = []
var circ_info: RichTextLabel

# 레이스
var race_box: Control
var top_label: RichTextLabel
var race_view
var car_panels: Array = [] # [{head, status, pace_btns, ers_btns, box_btns}]
var tower: RichTextLabel
var radio: RichTextLabel
var result_box: Control
var result_text: RichTextLabel
var speed_btns: Array = []
var cam_btns: Array = []


func _ready() -> void:
	DB.load_all()
	theme = _make_theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg = ColorRect.new()
	bg.color = BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_build_menu()
	_build_race_ui()
	_build_result()
	_show_menu()


# ═════════ 테마 ═════════
func _sb(bg_col: Color, border: Color, radius := 8, pad := 8) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = bg_col
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad * 0.6
	s.content_margin_bottom = pad * 0.6
	return s


func _make_theme() -> Theme:
	var th = Theme.new()
	var f = SystemFont.new()
	# 한글이 보이도록 OS별 한글 글꼴을 순서대로 시도한다
	f.font_names = PackedStringArray(["Malgun Gothic", "맑은 고딕", "Apple SD Gothic Neo", "Noto Sans CJK KR", "Noto Sans KR", "NanumGothic", "Droid Sans Fallback", "sans-serif"])
	th.default_font = f
	th.default_font_size = 20
	for t in ["Button", "OptionButton"]:
		th.set_stylebox("normal", t, _sb(PANEL2, LINE))
		th.set_stylebox("hover", t, _sb(PANEL2.lightened(0.06), LINE.lightened(0.2)))
		th.set_stylebox("pressed", t, _sb(Color("#3a2f12"), AMBER))
		th.set_stylebox("hover_pressed", t, _sb(Color("#3a2f12"), AMBER))
		th.set_stylebox("disabled", t, _sb(PANEL, LINE))
		th.set_stylebox("focus", t, StyleBoxEmpty.new())
		th.set_color("font_color", t, INK)
		th.set_color("font_pressed_color", t, AMBER)
		th.set_color("font_hover_pressed_color", t, AMBER)
		th.set_color("font_disabled_color", t, DIM)
	th.set_stylebox("panel", "PanelContainer", _sb(PANEL, LINE, 10, 10))
	th.set_color("font_color", "Label", INK)
	th.set_color("default_color", "RichTextLabel", INK)
	th.set_stylebox("normal", "RichTextLabel", StyleBoxEmpty.new())
	th.set_stylebox("panel", "TabContainer", _sb(PANEL, LINE, 10, 8))
	th.set_stylebox("tab_selected", "TabContainer", _sb(PANEL2, AMBER, 6, 10))
	th.set_stylebox("tab_unselected", "TabContainer", _sb(PANEL, LINE, 6, 10))
	th.set_stylebox("tab_hovered", "TabContainer", _sb(PANEL2, LINE, 6, 10))
	th.set_color("font_selected_color", "TabContainer", AMBER)
	th.set_color("font_unselected_color", "TabContainer", DIM)
	return th


func _label(text: String, fsize := 20, col := INK) -> Label:
	var l = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", fsize)
	l.add_theme_color_override("font_color", col)
	return l


func _rtl(fit := true) -> RichTextLabel:
	var r = RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = fit
	r.scroll_active = not fit
	r.selection_enabled = false
	return r


func _btn(text: String, fsize := 18) -> Button:
	var b = Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", fsize)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return b


func _hex(c: Color) -> String:
	return "#" + c.to_html(false)


# ═════════ 메뉴 ═════════
func _build_menu() -> void:
	var mc = MarginContainer.new()
	mc.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		mc.add_theme_constant_override("margin_" + side, 28)
	add_child(mc)
	menu_box = mc
	var v = VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	mc.add_child(v)
	v.add_child(_label("PIT WALL", 64, AMBER))
	v.add_child(_label("F1 피트월 전략 시뮬레이션 · Godot 프로토타입", 20, DIM))
	v.add_child(HSeparator.new())
	var grid = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 12)
	v.add_child(grid)
	opt_circuit = OptionButton.new()
	for k in DB.circuit_keys:
		opt_circuit.add_item("%s  (%s)" % [DB.circuits[k]["name"], DB.circuits[k]["full"]])
	opt_circuit.item_selected.connect(func(_i): _update_circ_info())
	opt_team = OptionButton.new()
	for t in DB.teams:
		opt_team.add_item("%s  ·  %s / %s" % [t["name"], t["drivers"][0]["name"], t["drivers"][1]["name"]])
	opt_team.select(6)
	opt_laps = OptionButton.new()
	for n in [10, 15, 20]:
		opt_laps.add_item("%d랩" % n)
	opt_laps.select(1)
	opt_weather = OptionButton.new()
	for w in ["자동 (서킷 강우 확률)", "맑음", "비"]:
		opt_weather.add_item(w)
	var rows = [["서킷", opt_circuit], ["내 팀", opt_team], ["레이스 길이", opt_laps], ["날씨", opt_weather]]
	opt_start.clear()
	for k in 2:
		var o = OptionButton.new()
		for comp in ["S", "M", "H"]:
			o.add_item("%s (%s)" % [RaceSimS.TYRE_KO[comp], comp])
		o.select(1)
		opt_start.append(o)
		rows.append(["#%d 출발 타이어" % (k + 1), o])
	for r in rows:
		grid.add_child(_label(r[0], 20, DIM))
		var ctl: Control = r[1]
		ctl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(ctl)
	circ_info = _rtl()
	v.add_child(circ_info)
	var hint = _rtl()
	hint.text = "[color=#8b98a5]내 차는 직접 [b]박스(S/M/H)[/b]를 눌러야만 피트인해요. 드라이 레이스에서는 [b]두 가지 슬릭 컴파운드[/b]를 써야 하고, 안 쓰면 30초 페널티예요. 상대 AI는 서킷·마모를 계산해서 각자 다른 전략을 씁니다.[/color]"
	v.add_child(hint)
	var spacer = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(spacer)
	var start = _btn("레이스 시작 ▶", 28)
	start.custom_minimum_size = Vector2(0, 72)
	start.pressed.connect(_on_start)
	v.add_child(start)
	_update_circ_info()


func _update_circ_info() -> void:
	var k: String = DB.circuit_keys[opt_circuit.selected]
	var c: Dictionary = DB.circuits[k]
	var wear_txt = "높음" if c["wear"] >= 1.12 else ("낮음" if c["wear"] <= 0.95 else "보통")
	circ_info.text = "[b]%s[/b] · %s\n[color=#8b98a5]%s\n타이어 마모 %s · 피트 손실 %.1f초 · 강우 확률 %d%%%s[/color]" % [
		c["full"], c["desc"], c["setupHint"], wear_txt, c["pitLoss"], int(c["rain"] * 100), (" · 야간 레이스" if c.get("night") != null else "")]


func _show_menu() -> void:
	menu_box.visible = true
	race_box.visible = false
	result_box.visible = false


func _on_start() -> void:
	last_settings = {
		"circ": DB.circuit_keys[opt_circuit.selected],
		"team": opt_team.selected,
		"laps": [10, 15, 20][opt_laps.selected],
		"wx": ["auto", "dry", "rain"][opt_weather.selected],
		"start": [["S", "M", "H"][opt_start[0].selected], ["S", "M", "H"][opt_start[1].selected]],
	}
	_start_race()


func _start_race() -> void:
	sim = RaceSimS.new()
	var s = last_settings
	sim.new_race(s["circ"], s["team"], s["laps"], s["wx"], s["start"])
	race_view.sim = sim
	race_view.follow_slot = -1
	menu_box.visible = false
	result_box.visible = false
	race_box.visible = true
	_set_speed(4)
	_set_cam(-1)
	for i in 2:
		var cp: Dictionary = car_panels[i]
		_press_only(cp["pace"], 1)
		_press_only(cp["ers"], 1)
	_refresh_ui()


# ═════════ 레이스 HUD ═════════
func _build_race_ui() -> void:
	var mc = MarginContainer.new()
	mc.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		mc.add_theme_constant_override("margin_" + side, 10)
	add_child(mc)
	race_box = mc
	var v = VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	mc.add_child(v)
	# 상단 정보 + 배속
	top_label = _rtl()
	v.add_child(top_label)
	var sp = HBoxContainer.new()
	sp.add_theme_constant_override("separation", 6)
	v.add_child(sp)
	speed_btns.clear()
	for s in SPEEDS:
		var b = _btn("멈춤" if s == 0 else "%d×" % s, 18)
		b.toggle_mode = true
		b.pressed.connect(_set_speed.bind(s))
		sp.add_child(b)
		speed_btns.append(b)
	var sep = VSeparator.new()
	sp.add_child(sep)
	cam_btns.clear()
	for i in [-1, 0, 1]:
		var b = _btn("전체" if i == -1 else "#%d" % (i + 1), 18)
		b.toggle_mode = true
		b.pressed.connect(_set_cam.bind(i))
		sp.add_child(b)
		cam_btns.append(b)
	# 트랙
	race_view = RaceViewS.new()
	race_view.custom_minimum_size = Vector2(0, 420)
	race_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	race_view.size_flags_stretch_ratio = 1.3
	race_view.clip_contents = true
	v.add_child(race_view)
	# 내 차 패널
	var h = HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	v.add_child(h)
	car_panels.clear()
	for i in 2:
		car_panels.append(_build_car_panel(h, i))
	# 순위 / 무전
	var tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.custom_minimum_size = Vector2(0, 260)
	v.add_child(tabs)
	tower = _rtl(false)
	tower.name = "순위"
	tabs.add_child(tower)
	radio = _rtl(false)
	radio.name = "무전"
	tabs.add_child(radio)


func _build_car_panel(parent: Control, slot: int) -> Dictionary:
	var pc = PanelContainer.new()
	pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(pc)
	var v = VBoxContainer.new()
	v.add_theme_constant_override("separation", 5)
	pc.add_child(v)
	var head = _rtl()
	v.add_child(head)
	var status = _rtl()
	v.add_child(status)
	var box_row = HBoxContainer.new()
	box_row.add_theme_constant_override("separation", 4)
	v.add_child(box_row)
	box_row.add_child(_label("박스", 16, DIM))
	var box_btns = []
	for comp in ["S", "M", "H"]:
		var b = _btn(comp, 18)
		b.add_theme_color_override("font_color", Color(RaceSimS.TYRE_HEX[comp]))
		b.pressed.connect(_on_box.bind(comp, slot))
		box_row.add_child(b)
		box_btns.append(b)
	var cancel = _btn("취소", 16)
	cancel.pressed.connect(_on_cancel.bind(slot))
	box_row.add_child(cancel)
	var pace = _toggle_row(v, "페이스", [["save", "세이브"], ["standard", "표준"], ["attack", "공격"]], _on_pace.bind(slot))
	var ers = _toggle_row(v, "ERS", [["harvest", "충전"], ["balance", "밸런스"], ["deploy", "오버"]], _on_ers.bind(slot))
	return {"panel": pc, "head": head, "status": status, "box": box_btns, "cancel": cancel, "pace": pace, "ers": ers}


func _toggle_row(parent: Control, title: String, items: Array, cb: Callable) -> Array:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	parent.add_child(row)
	var l = _label(title, 15, DIM)
	l.custom_minimum_size = Vector2(52, 0)
	row.add_child(l)
	var grp = ButtonGroup.new()
	var btns = []
	for it in items:
		var b = _btn(it[1], 15)
		b.toggle_mode = true
		b.button_group = grp
		b.pressed.connect(cb.bind(it[0]))
		row.add_child(b)
		btns.append(b)
	return btns


func _press_only(btns: Array, idx: int) -> void:
	for i in btns.size():
		btns[i].set_pressed_no_signal(i == idx)


func _set_speed(s: int) -> void:
	speed_x = s
	_press_only(speed_btns, SPEEDS.find(s))


func _set_cam(slot: int) -> void:
	race_view.follow_slot = slot
	_press_only(cam_btns, slot + 1)


func _my(slot: int):
	if sim == null:
		return null
	var mc: Array = sim.my_cars()
	return mc[slot] if slot < mc.size() else null


func _on_box(comp: String, slot: int) -> void:
	var c = _my(slot)
	if c != null:
		sim.request_pit(c, comp)
		_refresh_ui()


func _on_cancel(slot: int) -> void:
	var c = _my(slot)
	if c != null:
		sim.cancel_pit(c)
		_refresh_ui()


func _on_pace(p: String, slot: int) -> void:
	var c = _my(slot)
	if c != null:
		sim.set_pace(c, p)


func _on_ers(m: String, slot: int) -> void:
	var c = _my(slot)
	if c != null:
		sim.set_ers(c, m)


# ═════════ 진행 ═════════
func _process(delta: float) -> void:
	if sim == null or not race_box.visible:
		return
	if speed_x > 0 and not sim.done:
		sim.advance(delta * speed_x * RaceSimS.SPEED_BASE)
	ui_timer += delta
	if ui_timer >= 0.2:
		ui_timer = 0.0
		_refresh_ui()
		if sim.done and not result_box.visible:
			_show_result()


func _tyre_bb(comp: String) -> String:
	return "[color=%s][b]%s[/b][/color]" % [RaceSimS.TYRE_HEX[comp], comp]


func _refresh_ui() -> void:
	if sim == null:
		return
	var ord: Array = sim.order()
	var leader = ord[0]
	var lap_now = mini(sim.laps, leader.lap + 1)
	var wx = "맑음"
	if sim.wet >= 0.65:
		wx = "폭우 (웻)"
	elif sim.wet >= 0.22:
		wx = "젖음 (인터)"
	elif sim.wet > 0.04:
		wx = "약한 비"
	var fc_txt = ""
	if sim.fc != null and sim.leader_lap < sim.fc["lo"]:
		fc_txt = " · 예보 L%d-%d 비 %d%%" % [sim.fc["lo"], sim.fc["hi"], sim.fc["p"]]
	var sc_txt = ""
	if sim.sc:
		sc_txt = " · [color=#f59e0b][b]%s[/b][/color]" % sim.sc_kind
	top_label.text = "[b]%s[/b]  [color=#ffc53d]L%d/%d[/color]  · %s%s%s%s" % [sim.CIRC["name"], lap_now, sim.laps, wx, fc_txt, sc_txt, " · 야간" if sim.night else ""]
	# 내 차
	var mine: Array = sim.my_cars()
	for i in 2:
		var cp: Dictionary = car_panels[i]
		if i >= mine.size():
			cp["panel"].visible = false
			continue
		cp["panel"].visible = true
		var c = mine[i]
		var pos = ord.find(c) + 1
		var head_col = _hex(c.color)
		cp["head"].text = "[color=%s]■[/color] [b]P%d  %s[/b]  [color=#8b98a5]%s[/color]" % [head_col, pos, c.code, c.name]
		var st = ""
		if c.dnf != "":
			st = "[color=#ef4444]리타이어 (%s)[/color]" % c.dnf
		elif c.finished:
			st = "[color=#22c55e]완주[/color]%s" % (" [color=#ef4444]+30초 페널티[/color]" if c.penalty > 0 else "")
		else:
			var wear_col = "#22c55e" if c.wear < 0.45 else ("#facc15" if c.wear < 0.65 else "#ef4444")
			st = "%s %s [color=%s]마모 %d%%[/color] · %d랩째" % [_tyre_bb(c.comp), RaceSimS.TYRE_KO[c.comp], wear_col, int(round(c.wear * 100)), c.stint_laps]
			var ahead = ord[pos - 2] if pos >= 2 else null
			var behind = ord[pos] if pos < ord.size() else null
			var gtxt = ""
			if ahead != null and ahead.dnf == "":
				gtxt += "앞 %s %s" % [ahead.code, sim.gap_to(c, ahead).replace("+", "-")]
			if behind != null and behind.dnf == "" and behind.is_running():
				gtxt += ("  " if gtxt != "" else "") + "뒤 %s %s" % [behind.code, sim.gap_to(behind, c)]
			st += "\n[color=#8b98a5]%s[/color]" % gtxt
			st += "\n[color=#8b98a5]ERS %d%% · 연료 %.1f랩분 · 피트 %d회[/color]" % [int(c.ers * 100), c.fuel / RaceSimS.FPL, c.pits]
			if c.boxing != null:
				st += "\n[color=#ffc53d][b]▶ 피트 진입 중 → %s[/b][/color]" % RaceSimS.TYRE_KO[c.boxing["comp"]]
			elif c.pit_req != "":
				st += "\n[color=#ffc53d]박스 예약: %s (피트 입구 전까지 취소 가능)[/color]" % RaceSimS.TYRE_KO[c.pit_req]
			if c.used_slicks() < 2 and not sim.ever_wet:
				st += "\n[color=#f59e0b]두 번째 컴파운드 미사용[/color]"
		cp["status"].text = st
		var can_box: bool = c.is_running() and c.boxing == null
		for b in cp["box"]:
			b.disabled = not can_box
		cp["cancel"].disabled = c.pit_req == "" or c.boxing != null
	_refresh_tower(ord, leader)
	_refresh_radio()


func _refresh_tower(ord: Array, leader) -> void:
	var s = "[table=5]"
	s += "[cell][color=#8b98a5]P[/color][/cell][cell][color=#8b98a5]드라이버[/color][/cell][cell][color=#8b98a5]간격[/color][/cell][cell][color=#8b98a5]타이어[/color][/cell][cell][color=#8b98a5]피트[/color][/cell]"
	var pos = 0
	for c in ord:
		pos += 1
		var name_col = "#ffc53d" if c.mine else "#e6edf3"
		var gap = ""
		if c.dnf != "":
			gap = "[color=#ef4444]DNF[/color]"
		elif c == leader:
			gap = "선두"
		else:
			gap = sim.gap_to(c, leader)
		if c.boxing != null or c.pit_phase == 2:
			gap += " [color=#ffc53d]PIT[/color]"
		elif c.drs and not sim.sc:
			gap += " [color=#22c55e]DRS[/color]"
		# 라이벌 타이어 마모는 숨기고 스틴트 나이만 공개 (관측 가능한 정보)
		var tyre = "%s [color=#8b98a5]%dL[/color]" % [_tyre_bb(c.comp), c.stint_laps]
		if c.mine:
			tyre = "%s [color=#8b98a5]%d%%[/color]" % [_tyre_bb(c.comp), int(round(c.wear * 100))]
		s += "[cell]%d  [/cell][cell][color=%s]■[/color] [color=%s]%s[/color] [color=#8b98a5]%s[/color]  [/cell][cell]%s  [/cell][cell]%s  [/cell][cell]%d[/cell]" % [
			pos, _hex(c.color), name_col, c.code, c.team, gap, tyre, c.pits]
	s += "[/table]"
	tower.text = s


func _refresh_radio() -> void:
	var s = ""
	var n = 0
	for e in sim.radio_log:
		n += 1
		if n > 40:
			break
		var col: Color = e["color"]
		var msg_col = "#e6edf3"
		if e["kind"] == "bad":
			msg_col = "#fca5a5"
		elif e["kind"] == "sc":
			msg_col = "#fcd34d"
		elif e["kind"] == "wet":
			msg_col = "#93c5fd"
		s += "[color=#8b98a5]%s[/color] [color=%s][b]%s[/b][/color] [color=%s]%s[/color]\n" % [e["lap"], _hex(col), e["who"], msg_col, e["msg"]]
	radio.text = s


# ═════════ 결과 ═════════
func _build_result() -> void:
	var cc = CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(cc)
	result_box = cc
	var pc = PanelContainer.new()
	pc.custom_minimum_size = Vector2(660, 900)
	cc.add_child(pc)
	var v = VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	pc.add_child(v)
	v.add_child(_label("레이스 결과", 34, AMBER))
	result_text = _rtl(false)
	result_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(result_text)
	var h = HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	v.add_child(h)
	var again = _btn("같은 설정으로 다시", 22)
	again.pressed.connect(_start_race)
	h.add_child(again)
	var menu = _btn("메뉴로", 22)
	menu.pressed.connect(_show_menu)
	h.add_child(menu)


func _show_result() -> void:
	var res: Array = sim.results()
	var s = "[table=5]"
	s += "[cell][color=#8b98a5]P[/color][/cell][cell][color=#8b98a5]드라이버[/color][/cell][cell][color=#8b98a5]기록[/color][/cell][cell][color=#8b98a5]전략[/color][/cell][cell][color=#8b98a5]PTS[/color][/cell]"
	for r in res:
		var c = r["car"]
		var name_col = "#ffc53d" if c.mine else "#e6edf3"
		var strat = ""
		var hist: Array = c.lap_hist.duplicate()
		hist.reverse()
		# 실제 사용한 타이어 순서를 랩 기록에서 복원
		var seq = []
		var last = ""
		for hrec in hist:
			if hrec["comp"] != last:
				seq.append(hrec["comp"])
				last = hrec["comp"]
		for i in seq.size():
			strat += _tyre_bb(seq[i]) + (" " if i < seq.size() - 1 else "")
		var pen = " [color=#ef4444]+30s[/color]" if c.penalty > 0 else ""
		s += "[cell]%d  [/cell][cell][color=%s]■[/color] [color=%s]%s[/color] [color=#8b98a5]%s[/color]  [/cell][cell]%s%s  [/cell][cell]%s  [/cell][cell]%d[/cell]" % [
			r["pos"], _hex(c.color), name_col, c.code, c.team, r["gap"], pen, strat, r["points"]]
	s += "[/table]"
	if sim.fastest_id >= 0:
		var fc = sim.cars.filter(func(x): return x.id == sim.fastest_id)
		if not fc.is_empty():
			s += "\n[color=#a855f7]최고 랩[/color] %s %.3f초" % [fc[0].code, sim.fastest_t]
	result_text.text = s
	result_box.visible = true
