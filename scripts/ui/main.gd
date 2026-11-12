extends Control
## 메인 화면: 레이스 설정 메뉴 → 레이스 진행 HUD → 결과.
## UI는 모두 코드로 만든다(씬 파일을 손으로 편집하지 않아도 되도록).

const RaceSimS = preload("res://scripts/sim/race_sim.gd")
const RaceViewS = preload("res://scripts/ui/race_view.gd")
const SfxS = preload("res://scripts/ui/sfx.gd")
const DB = preload("res://scripts/data/game_db.gd")
const KitS = preload("res://scripts/ui/kit.gd")
const CareerS = preload("res://scripts/sim/career.gd")
const WeekendS = preload("res://scripts/sim/weekend.gd")
const HqViewS = preload("res://scripts/ui/hq_view.gd")
const WeekendViewS = preload("res://scripts/ui/weekend_view.gd")
const SeasonViewS = preload("res://scripts/ui/season_view.gd")
const HT = preload("res://scripts/ui/help_text.gd")
const RacePanelS = preload("res://scripts/ui/race_panel.gd")
const DebriefS = preload("res://scripts/ui/debrief.gd")
const RivalS = preload("res://scripts/ui/rival_card.gd")
const ST = preload("res://scripts/ui/settings.gd")
const SettingsViewS = preload("res://scripts/ui/settings_view.gd")

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

var sim: Variant = null
var speed_x := 4
var ui_timer := 0.0
var last_settings := {}

# 메뉴
var menu_box: Control
var opt_circuit: OptionButton
var opt_team: OptionButton
var opt_laps: OptionButton
var opt_weather: OptionButton
var opt_diff: OptionButton
var opt_start: Array = []
var circ_info: RichTextLabel
var menu_cols: BoxContainer
# 모드: quick(퀵 레이스) / career(커리어)
var mode := "quick"
var qseries := "f1"        # 퀵 레이스 시리즈 f1 / wec
var quick_keys: Array = [] # 현재 시리즈의 서킷 키
var quick_teams: Array = [] # 현재 시리즈의 팀 인덱스
var mode_btns: Array = []
var quick_left: Control
var quick_right: Control
var career_left: VBoxContainer
var career_right: VBoxContainer
var career = null
var wk = null
var hq_view
var wk_view
var season_view
var season_pending := false
var new_entry := "select"
var new_series := "f1"
var new_opts := {"name": "Korea GP Racing", "color": "#00d2be", "rim": "#ffffff", "engine": "Mercedes", "region": "uk", "tier": 1, "difficulty": 1}
var new_team := 6
var new_team_list: Array = []
var del_armed := 0   # 삭제 확인 중인 슬롯 (0 = 없음)
var new_slot := 1
var result_title: Label
var btn_again: Button
var btn_menu: Button
var btn_hq: Button
var settled := false
var sprint_mode := false   # F2 스프린트 레이스 중
var feature_sim = null     # 스프린트 뒤에 달릴 피처 레이스 (예선 그리드)
var btn_feature: Button
var btn_debrief: Button
var rival
var settings_view
var debrief

# 레이스
var race_box: Control
var top_label: RichTextLabel
var race_view
var race_panel            # 내 차 지시판 (race_panel.gd)
var info_label: RichTextLabel
var gap_mode := 0         # 순위표: 0 앞차 간격 / 1 선두와 차이 / 2 직전 랩타임
var gap_btn: Button
var tower: RichTextLabel
var radio: RichTextLabel
var result_box: Control
var result_text: RichTextLabel
var speed_btns: Array = []
var cam_btns: Array = []
var sfx
var mute_btn: Button
# 반응형 배치: 가로 화면(PC·가로 폰) / 세로 화면(세로 폰)
var hud_top: Control
var panels_box: Control
var tabs: TabContainer
var port_box: VBoxContainer
var land_box: HBoxContainer
var land_left: VBoxContainer
var land_right: VBoxContainer
var landscape := -1 # -1 = 아직 배치 전, 0 = 세로, 1 = 가로
var result_panel: PanelContainer
# 출발 신호
var starting := false
var start_t := 0.0
var start_hold := 4.5


func _ready() -> void:
	DB.load_all()
	ST.ensure()
	ST.apply_audio()
	for sl in range(CareerS.SLOTS, 0, -1):
		if not CareerS.has_save(sl):
			new_slot = sl
	theme = _make_theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg = ColorRect.new()
	bg.color = BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_build_menu()
	_build_race_ui()
	hq_view = HqViewS.new()
	hq_view.visible = false
	add_child(hq_view)
	hq_view.go_weekend.connect(_start_weekend_career)
	hq_view.go_menu.connect(_show_menu)
	hq_view.go_season.connect(_open_season)
	wk_view = WeekendViewS.new()
	wk_view.visible = false
	add_child(wk_view)
	wk_view.start_race.connect(_begin_race)
	wk_view.go_back.connect(_weekend_back)
	season_view = SeasonViewS.new()
	season_view.visible = false
	add_child(season_view)
	season_view.done.connect(_open_hq)
	_build_result()
	_show_menu()
	get_viewport().size_changed.connect(_on_resize)
	_on_resize()


func _on_resize() -> void:
	# 세로 화면(폴드 외부 화면 등)에서는 기준 해상도를 720×1280 으로 바꿔 글씨·버튼이 화면 폭에 맞게 커지도록
	var win := get_window()
	var ws: Vector2i = win.size
	var want := 1 if ws.x > ws.y * 1.05 else 0
	var base := Vector2i(1280, 720) if want == 1 else Vector2i(720, 1280)
	var scl: float = 1.0 / clampf(float(ST.get_v("ui_scale")), 0.8, 1.3)
	base = Vector2i(int(base.x * scl), int(base.y * scl))
	if win.content_scale_size != base:
		win.content_scale_size = base
	var vs: Vector2 = get_viewport_rect().size
	if want != landscape:
		landscape = want
		_apply_layout()
	# 메뉴는 넓은 화면에서 가운데 정렬된 기둥으로
	menu_cols.vertical = landscape == 0
	var side = maxf(24.0, (vs.x - (1200.0 if landscape == 1 else 820.0)) / 2.0)
	menu_box.add_theme_constant_override("margin_left", int(side))
	menu_box.add_theme_constant_override("margin_right", int(side))
	result_panel.custom_minimum_size = Vector2(minf(760.0, vs.x - 32.0), minf(900.0, vs.y - 32.0))


func _move(node: Control, parent: Control) -> void:
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	parent.add_child(node)


func _apply_layout() -> void:
	if landscape == 1:
		# 왼쪽: 상단 바 + 큰 트랙 / 오른쪽: 내 차 지시 + 순위·무전
		_move(hud_top, land_left)
		_move(race_view, land_left)
		_move(panels_box, land_right)
		_move(tabs, land_right)
		race_view.custom_minimum_size = Vector2(0, 0)
		tabs.custom_minimum_size = Vector2(0, 160)
		land_box.visible = true
		port_box.visible = false
	else:
		_move(hud_top, port_box)
		_move(race_view, port_box)
		_move(panels_box, port_box)
		_move(tabs, port_box)
		race_view.custom_minimum_size = Vector2(0, 520)
		tabs.custom_minimum_size = Vector2(0, 240)
		land_box.visible = false
		port_box.visible = true


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
		mc.add_theme_constant_override("margin_" + side, 24)
	add_child(mc)
	menu_box = mc
	# 화면이 작아도 잘리지 않게 스크롤 + 가로 화면에서는 2단 배치
	var scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	mc.add_child(scroll)
	KitS.drag_scroll(scroll)
	menu_cols = BoxContainer.new()
	menu_cols.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	menu_cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	menu_cols.add_theme_constant_override("separation", 28)
	scroll.add_child(menu_cols)
	var v = VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 12)
	menu_cols.add_child(v)
	var v2 = VBoxContainer.new()
	v2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v2.add_theme_constant_override("separation", 12)
	menu_cols.add_child(v2)
	v.add_child(_label("PIT WALL", 52, AMBER))
	v.add_child(_label("F1 피트월 전략 시뮬레이션 · Godot 프로토타입", 20, DIM))
	v.add_child(HSeparator.new())
	var mrow = KitS.hbox(6)
	v.add_child(mrow)
	mode_btns = KitS.seg(mrow, [["quick", "퀵 레이스"], ["career", "커리어"]], mode, _on_mode, 20)
	mrow.add_child(KitS.help("시작 메뉴", HT.QUICK + "\n\n" + HT.CAREER))
	var gear = KitS.btn("⚙", 18, _open_settings)
	gear.size_flags_horizontal = Control.SIZE_SHRINK_END
	gear.custom_minimum_size = Vector2(44, 0)
	mrow.add_child(gear)
	quick_left = KitS.vbox(12)
	v.add_child(quick_left)
	career_left = KitS.vbox(10)
	v.add_child(career_left)
	KitS.seg(quick_left, [["f1", "F1 그랑프리"], ["wec", "WEC 내구 (하이퍼카 + LMGT3)"]], qseries, _on_series, 17)
	var grid = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 12)
	quick_left.add_child(grid)
	opt_circuit = OptionButton.new()
	opt_circuit.item_selected.connect(_on_circ_pick)
	opt_team = OptionButton.new()
	opt_laps = OptionButton.new()
	opt_weather = OptionButton.new()
	for w in ["자동 (서킷 강우 확률)", "맑음", "비"]:
		opt_weather.add_item(w)
	opt_diff = OptionButton.new()
	for dn in RaceSimS.DIFF_KO:
		opt_diff.add_item(dn)
	opt_diff.select(1)
	var rows = [["서킷", opt_circuit], ["내 팀", opt_team], ["레이스 길이", opt_laps], ["날씨", opt_weather], ["난이도", opt_diff]]
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
	quick_right = KitS.vbox(12)
	quick_right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v2.add_child(quick_right)
	career_right = KitS.vbox(10)
	v2.add_child(career_right)
	circ_info = _rtl()
	quick_right.add_child(circ_info)
	var hint = _rtl()
	hint.text = "[color=#8b98a5]내 차는 직접 [b]박스(S/M/H)[/b]를 눌러야만 피트인해요. 드라이 레이스에서는 [b]두 가지 슬릭 컴파운드[/b]를 써야 하고, 안 쓰면 30초 페널티예요. 상대 AI는 서킷·마모를 계산해서 각자 다른 전략을 씁니다.[/color]"
	quick_right.add_child(hint)
	var spacer = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	quick_right.add_child(spacer)
	var wkb = _btn("주말 진행 (연습·예선) ▶", 26)
	wkb.custom_minimum_size = Vector2(0, 64)
	wkb.pressed.connect(_start_weekend_quick)
	quick_right.add_child(wkb)
	var start = _btn("바로 레이스 ▶ (그리드 자동)", 18)
	start.custom_minimum_size = Vector2(0, 44)
	start.pressed.connect(_on_start)
	quick_right.add_child(start)
	_fill_quick_options()


func _on_series(v) -> void:
	qseries = v
	_fill_quick_options()


func _on_circ_pick(_i: int) -> void:
	_fill_laps()
	_update_circ_info()


## 시리즈에 맞춰 서킷·팀·레이스 길이 목록을 다시 채운다
func _fill_quick_options() -> void:
	quick_keys = DB.wec_keys if qseries == "wec" else DB.circuit_keys
	opt_circuit.clear()
	for k in quick_keys:
		opt_circuit.add_item("%s  (%s)" % [DB.circuits[k]["name"], DB.circuits[k]["full"]])
	opt_team.clear()
	quick_teams = []
	if qseries == "wec":
		var hy: Array = DB.wec["hy"]
		for i in hy.size():
			if int(hy[i]["cars"]) > 1:
				quick_teams.append(i)
				opt_team.add_item("%s  ·  %s" % [hy[i]["name"], String(hy[i]["engine"]).split(" ")[0]])
		opt_team.select(0)
	else:
		for i in DB.teams.size():
			var t: Dictionary = DB.teams[i]
			quick_teams.append(i)
			opt_team.add_item("%s  ·  %s / %s" % [t["name"], t["drivers"][0]["name"], t["drivers"][1]["name"]])
		opt_team.select(6)
	_fill_laps()
	_update_circ_info()


func _fill_laps() -> void:
	var prev := opt_laps.selected
	opt_laps.clear()
	if qseries == "wec":
		var lo: Dictionary = DB.circuits[quick_keys[maxi(0, opt_circuit.selected)]]["lapsOpt"]
		opt_laps.add_item("짧게 %d랩" % int(lo["short"]))
		opt_laps.add_item("표준 %d랩" % int(lo["std"]))
		opt_laps.select(0 if prev < 0 or prev > 1 else prev)
	else:
		for n in [10, 15, 20]:
			opt_laps.add_item("%d랩" % n)
		opt_laps.select(1 if prev < 0 or prev > 2 else prev)


func _quick_laps() -> int:
	if qseries == "wec":
		var lo: Dictionary = DB.circuits[quick_keys[opt_circuit.selected]]["lapsOpt"]
		return int(lo["short"]) if opt_laps.selected == 0 else int(lo["std"])
	return [10, 15, 20][opt_laps.selected]


func _update_circ_info() -> void:
	if opt_circuit.selected < 0:
		return
	var k: String = quick_keys[opt_circuit.selected]
	var c: Dictionary = DB.circuits[k]
	var wear_txt = "높음" if c["wear"] >= 1.12 else ("낮음" if c["wear"] <= 0.95 else "보통")
	var pit_txt := "피트 손실 %.1f초" % float(c["pitLoss"]) if c.has("pitLoss") else "%d시간 레이스 · 스틴트 5랩마다 급유" % int(c.get("hours", 6))
	circ_info.text = "[b]%s[/b] · %s\n[color=#8b98a5]%s\n타이어 마모 %s · %s · 강우 확률 %d%%%s[/color]" % [
		c["full"], c["desc"], c["setupHint"], wear_txt, pit_txt, int(c["rain"] * 100), (" · 야간 구간 있음" if c.get("night") != null else "")]
	if qseries == "wec":
		circ_info.text += "\n[color=#8b98a5]WEC: 하이퍼카(내 팀)와 LMGT3가 함께 달려요. 박스 때 타이어·급유·드라이버 교대를 골라요. 연료는 약 5랩마다 채워야 하고, 한 드라이버가 오래 타면 피로로 실수가 늘어요.[/color]"


func _show_menu() -> void:
	_show_only(menu_box)
	_render_career_menu()


func _show_only(node: Control) -> void:
	if debrief != null:
		debrief.visible = false
	if rival != null:
		rival.close_card()
	for n in [menu_box, race_box, result_box, hq_view, wk_view, season_view]:
		if n != null:
			n.visible = n == node
	if sfx != null and node != race_box:
		sfx.set_engine(0.0)


func _on_mode(v) -> void:
	mode = v
	_render_career_menu()


# ═════════ 커리어 시작 메뉴 ═════════
func _render_career_menu() -> void:
	if career_left == null:
		return
	if mode_btns.size() == 2:
		mode_btns[0].set_pressed_no_signal(mode == "quick")
		mode_btns[1].set_pressed_no_signal(mode == "career")
	quick_left.visible = mode == "quick"
	quick_right.visible = mode == "quick"
	career_left.visible = mode == "career"
	career_right.visible = mode == "career"
	KitS.clear(career_left)
	KitS.clear(career_right)
	if mode != "career":
		return
	var c0 = KitS.card(career_left, "저장 슬롯", AMBER)
	for sl in range(1, CareerS.SLOTS + 1):
		var hb = KitS.hbox(6)
		c0.add_child(hb)
		var r = KitS.rtl(15)
		r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(r)
		var tmp = CareerS.new()
		if CareerS.has_save(sl) and tmp.load_save(sl):
			var h: Dictionary = tmp.hq
			r.text = "[b]%d[/b]  [color=%s]■[/color] [b]%s[/b] · %s · 시즌 %d R%d\n[color=#8b98a5]자금 %.1fM · 평판 %d%% · 난이도 %s[/color]" % [sl, h["team_color"], h["team_name"], tmp.tier_meta()["short"], int(h["season"]), tmp.round_idx() + 1, float(h["cash"]), int(float(h["pop"]) * 100), RaceSimS.DIFF_KO[clampi(int(h.get("difficulty", 1)), 0, 3)]]
			hb.add_child(KitS.sbtn("이어하기 ▶", _continue_career.bind(sl), true, GOOD))
			hb.add_child(KitS.sbtn("⚠ 한 번 더" if del_armed == sl else "삭제", _delete_save.bind(sl), true, BAD))
		else:
			r.text = "[b]%d[/b]  [color=#5d6674]빈 슬롯[/color]" % sl
	var c1 = KitS.card(career_left, "새 커리어")
	c1.add_child(KitS.label("저장할 슬롯", 14, DIM))
	var s_items: Array = []
	for sl in range(1, CareerS.SLOTS + 1):
		s_items.append([str(sl), "슬롯 %d%s" % [sl, " (덮어씀)" if CareerS.has_save(sl) else ""]])
	KitS.seg(c1, s_items, str(new_slot), _on_new_slot, 14)
	KitS.seg(c1, [["f1", "F1"], ["wec", "WEC 내구"]], new_series, _on_new_series, 16)
	var top_name := "Hypercar" if new_series == "wec" else "F1"
	KitS.seg(c1, [["select", "기존 팀으로 (%s)" % top_name], ["create", "신규 팀 창단"]], new_entry, _on_entry, 16)
	if new_entry == "select":
		var ob = OptionButton.new()
		var idx := 0
		var sel_i := 0
		new_team_list = []
		if new_series == "wec":
			var hy: Array = DB.wec["hy"]
			for i in hy.size():
				if int(hy[i]["cars"]) < 2:
					continue
				var ib0: Array = DB.wec["init_budget"].get(hy[i]["name"], [9.0, 0.7])
				ob.add_item("%s · 초기 자금 %.1fM · 평판 %d%%" % [hy[i]["name"], float(ib0[0]), int(float(ib0[1]) * 100)])
				new_team_list.append(i)
		else:
			for i in DB.teams.size():
				var t: Dictionary = DB.teams[i]
				var ib: Array = DB.career["init_budget"].get(t["name"], [8.5, 0.6])
				ob.add_item("%s · 초기 자금 %.1fM · 평판 %d%%" % [t["name"], float(ib[0]), int(float(ib[1]) * 100)])
				new_team_list.append(i)
		for i in new_team_list.size():
			if new_team_list[i] == new_team:
				sel_i = i
		ob.select(sel_i)
		new_team = new_team_list[sel_i]
		ob.item_selected.connect(_on_new_team)
		c1.add_child(ob)
	else:
		c1.add_child(KitS.label("팀 이름", 14, DIM))
		var le = LineEdit.new()
		le.text = new_opts["name"]
		le.max_length = 24
		le.text_changed.connect(_on_new_name)
		c1.add_child(le)
		c1.add_child(KitS.label("팀 색 / 포인트 색", 14, DIM))
		var sw = KitS.hbox(4)
		c1.add_child(sw)
		for col in DB.career["swatch_main"]:
			sw.add_child(_swatch(col, new_opts["color"] == col, _on_new_color.bind(col)))
		var sw2 = KitS.hbox(4)
		c1.add_child(sw2)
		for col in DB.career["swatch_rim"]:
			sw2.add_child(_swatch(col, new_opts["rim"] == col, _on_new_rim.bind(col)))
		c1.add_child(KitS.label("출발 리그", 14, DIM))
		if new_series == "wec":
			KitS.seg(c1, [["1", "LMGT3 (3부)"], ["2", "LMP2 (2부)"], ["3", "Hypercar (1부)"]], str(new_opts["tier"]), _on_new_tier, 15)
			c1.add_child(KitS.label("하이퍼카 패키지 (승격 후 사용)", 14, DIM))
			var pk_items: Array = []
			for pk in CareerS.WEC_PKGS:
				pk_items.append([pk, String(CareerS.WEC_PKGS[pk]).split(" ")[0]])
			KitS.seg(c1, pk_items, new_opts["engine"], _on_new_engine, 14)
		else:
			KitS.seg(c1, [["1", "F3 (3부)"], ["2", "F2 (2부)"], ["3", "F1 (1부)"]], str(new_opts["tier"]), _on_new_tier, 15)
			c1.add_child(KitS.label("파워유닛 (F1 승격 후 사용)", 14, DIM))
			KitS.seg(c1, [["Mercedes", "Mercedes"], ["Ferrari", "Ferrari"], ["Red Bull Ford", "RB Ford"], ["Honda", "Honda"]], new_opts["engine"], _on_new_engine, 14)
		c1.add_child(KitS.label("본부 지역", 14, DIM))
		KitS.seg(c1, [["uk", "영국(공력)"], ["italy", "이탈리아(엔진)"], ["germany", "독일(섀시)"], ["japan", "일본(타이어)"]], new_opts["region"], _on_new_region, 14)
	c1.add_child(KitS.label("난이도 (HQ에서 언제든 변경)", 14, DIM))
	var d_items: Array = []
	for di in RaceSimS.DIFF_KO.size():
		d_items.append([str(di), RaceSimS.DIFF_KO[di]])
	KitS.seg(c1, d_items, str(new_opts["difficulty"]), _on_new_diff, 15)
	var info = KitS.rtl(15)
	info.text = "[b]커리어 모드[/b]\n[color=#8b98a5]시즌 17라운드. 레이스마다 연습·예선·결승을 치르고, 사이사이 본부(HQ)에서 개발·설비·인력·스폰서를 운영해요.\n\n• [b]코스트캡[/b] 안에서 R&D와 설비에 투자하세요. 넘기면 벌금과 제재.\n• [b]스폰서[/b]는 시즌 전 제안 중 카테고리마다 하나를 골라요. 안정형·성과연동형·단기 고액은 성과 조항과 홍보 의무가 달라요.\n• 레이스 전에 [b]미션을 약속[/b]하면 보너스, 실패하면 평판 하락.\n• 신규 팀은 F3부터 시작해 승격을 노려요 (오너가 5시즌 동안 자본 지원).[/color]"
	career_right.add_child(info)
	var go = _btn("새 커리어 시작 ▶", 24)
	go.custom_minimum_size = Vector2(0, 60)
	go.pressed.connect(_new_career)
	career_right.add_child(go)
	if CareerS.has_save(new_slot):
		career_right.add_child(KitS.label("※ 슬롯 %d 에 저장된 커리어를 덮어써요." % new_slot, 13, BAD))


func _swatch(col: String, on: bool, cb: Callable) -> Button:
	var b = Button.new()
	b.custom_minimum_size = Vector2(38, 30)
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(col)
	sb.set_corner_radius_all(6)
	sb.border_color = AMBER if on else Color(col)
	sb.set_border_width_all(3 if on else 1)
	for st in ["normal", "hover", "pressed"]:
		b.add_theme_stylebox_override(st, sb)
	b.pressed.connect(cb)
	return b


func _on_entry(v) -> void:
	new_entry = v
	_render_career_menu()


func _on_new_team(i: int) -> void:
	new_team = new_team_list[i]


func _on_new_series(v) -> void:
	new_series = v
	new_team = 0 if v == "wec" else 6
	new_opts["engine"] = "Ferrari F163 3.0L V6 Twin-Turbo Hybrid" if v == "wec" else "Mercedes"
	_render_career_menu()


func _on_new_name(t: String) -> void:
	new_opts["name"] = t


func _on_new_color(c) -> void:
	new_opts["color"] = c
	_render_career_menu()


func _on_new_rim(c) -> void:
	new_opts["rim"] = c
	_render_career_menu()


func _on_new_tier(v) -> void:
	new_opts["tier"] = int(v)
	_render_career_menu()


func _on_new_engine(v) -> void:
	new_opts["engine"] = v
	_render_career_menu()


func _on_new_diff(v) -> void:
	new_opts["difficulty"] = int(v)
	_render_career_menu()


func _on_new_region(v) -> void:
	new_opts["region"] = v
	_render_career_menu()


func _delete_save(sl: int) -> void:
	if del_armed != sl:
		del_armed = sl
		_render_career_menu()
		return
	del_armed = 0
	CareerS.delete_save(sl)
	_render_career_menu()


func _on_new_slot(v) -> void:
	new_slot = int(v)
	_render_career_menu()


func _new_career() -> void:
	career = CareerS.new()
	var nm: String = String(new_opts["name"]).strip_edges()
	if nm == "":
		nm = "Korea GP Racing"
	new_opts["name"] = nm
	new_opts["series"] = new_series
	career.new_career(new_entry, new_team, new_opts)
	career.save_slot = new_slot
	career.save()
	mode = "career"
	_open_hq()


func _continue_career(sl: int = 1) -> void:
	career = CareerS.new()
	if career.load_save(sl):
		mode = "career"
		_open_hq()


func _on_tower_click(meta) -> void:
	if sim != null:
		rival.show_car(sim, int(str(meta)))


func _open_settings() -> void:
	settings_view.open()


func _apply_settings() -> void:
	ST.apply_audio()
	if sim != null:
		sim.prompts_enabled = bool(ST.get_v("prompts"))
	_on_resize()


func _open_debrief() -> void:
	if sim != null:
		debrief.open(sim)


func _on_result_hq() -> void:
	if season_pending:
		season_pending = false
		_open_season()
	else:
		_open_hq()


func _open_season() -> void:
	_show_only(season_view)
	season_view.open(career)


func _open_hq() -> void:
	_show_only(hq_view)
	hq_view.open(career)


# ═════════ 레이스 주말 ═════════
func _read_quick_settings() -> void:
	last_settings = {
		"circ": quick_keys[opt_circuit.selected],
		"team": quick_teams[opt_team.selected],
		"laps": _quick_laps(),
		"wx": ["auto", "dry", "rain"][opt_weather.selected],
		"start": [["S", "M", "H"][opt_start[0].selected], ["S", "M", "H"][opt_start[1].selected]],
		"diff": maxi(0, opt_diff.selected),
	}


func _start_weekend_quick() -> void:
	mode = "quick"
	_read_quick_settings()
	var s = last_settings
	sim = RaceSimS.new()
	sim.new_race(s["circ"], s["team"], s["laps"], s["wx"], ["M", "M"], 0, {"difficulty": s["diff"]})
	wk = WeekendS.new()
	wk.setup(sim, 0)
	_show_only(wk_view)
	wk_view.open(sim, wk)


func _start_weekend_career() -> void:
	mode = "career"
	career.resolve_event_default()
	sim = RaceSimS.new()
	var opts: Dictionary = career.race_opts()
	sim.new_race(career.next_circuit(), career.race_my_index(), career.race_laps(), "auto", ["M", "M"], 0, opts)
	wk = WeekendS.new()
	wk.setup(sim, career.duty_laps(), career.eng_quality())
	_show_only(wk_view)
	wk_view.open(sim, wk)


func _weekend_back() -> void:
	if mode == "career":
		_open_hq()
	else:
		_show_menu()


## 주말(연습·예선)을 마친 sim 으로 결승 시작. F2 라운드면 스프린트(예선 상위 10대 리버스 그리드)부터.
func _begin_race() -> void:
	if mode == "career" and career.has_sprint():
		feature_sim = sim
		var sp = RaceSimS.new()
		sp.new_race(career.next_circuit(), career.race_my_index(), career.race_laps(true), "auto", ["M", "M"], 0, career.race_opts(true))
		var keys: Array = feature_sim.grid_keys()
		var top: Array = keys.slice(0, 10)
		top.reverse()
		sp.apply_grid(top + keys.slice(10))
		sim = sp
		sprint_mode = true
		sim.event("F2 스프린트: 예선 상위 10대 리버스 그리드, 의무 피트 없음")
		sim.prepare_start()
		_launch_race()
		return
	sprint_mode = false
	sim.prepare_start()
	_launch_race()


func _start_feature() -> void:
	sim = feature_sim
	feature_sim = null
	sprint_mode = false
	sim.event("F2 피처 레이스: 예선 그리드, 두 컴파운드 의무 (피트 1회 이상)")
	sim.prepare_start()
	_launch_race()


func _on_start() -> void:
	mode = "quick"
	_read_quick_settings()
	_start_race()


func _start_race() -> void:
	sim = RaceSimS.new()
	var s = last_settings
	sim.new_race(s["circ"], s["team"], s["laps"], s["wx"], s["start"], 0, {"difficulty": s["diff"]})
	for c in sim.my_cars():
		sim.engineer_setup(c, sim.team_eng_q(c)) # 주말 없이 바로 달리면 엔지니어가 맞춘 셋업으로
	sim.prepare_start()
	_launch_race()


func _launch_race() -> void:
	settled = false
	race_view.reset()
	race_view.sim = sim
	race_view.follow_slot = -1
	# 출발 신호: 1초마다 빨간불 하나씩 → 잠깐 정지 → 소등과 함께 출발
	starting = true
	start_t = 0.0
	start_hold = 5.0 + randf_range(0.4, 1.1)
	race_view.lights = 0
	_show_only(race_box)
	_set_speed(int(ST.get_v("speed")))
	sim.prompts_enabled = bool(ST.get_v("prompts"))
	_set_cam(-1)
	race_panel.reset_for(sim)
	race_view.sel_slot = 0
	_refresh_ui()


# ═════════ 레이스 HUD ═════════
func _build_race_ui() -> void:
	var mc = MarginContainer.new()
	mc.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		mc.add_theme_constant_override("margin_" + side, 10)
	add_child(mc)
	race_box = mc
	var root = Control.new()
	mc.add_child(root)
	# 두 가지 뼈대를 미리 만들어 두고, 화면 방향에 따라 부품을 옮겨 끼운다
	port_box = VBoxContainer.new()
	port_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	port_box.add_theme_constant_override("separation", 8)
	root.add_child(port_box)
	land_box = HBoxContainer.new()
	land_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	land_box.add_theme_constant_override("separation", 10)
	root.add_child(land_box)
	land_left = VBoxContainer.new()
	land_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	land_left.size_flags_stretch_ratio = 1.55
	land_left.add_theme_constant_override("separation", 6)
	land_box.add_child(land_left)
	land_right = VBoxContainer.new()
	land_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	land_right.add_theme_constant_override("separation", 8)
	land_box.add_child(land_right)
	# 상단 정보 + 배속 + 카메라
	var top = VBoxContainer.new()
	top.add_theme_constant_override("separation", 4)
	hud_top = top
	top_label = _rtl()
	top.add_child(top_label)
	info_label = _rtl()
	_small_text(info_label, 14)
	top.add_child(info_label)
	var sp = HBoxContainer.new()
	sp.add_theme_constant_override("separation", 5)
	top.add_child(sp)
	speed_btns.clear()
	for s in SPEEDS:
		var b = _btn("멈춤" if s == 0 else "%d×" % s, 16)
		b.toggle_mode = true
		b.pressed.connect(_set_speed.bind(s))
		sp.add_child(b)
		speed_btns.append(b)
	sp.add_child(VSeparator.new())
	cam_btns.clear()
	for i in [-1, 0, 1]:
		var b = _btn("전체" if i == -1 else "#%d 추적" % (i + 1), 16)
		b.toggle_mode = true
		b.pressed.connect(_set_cam.bind(i))
		sp.add_child(b)
		cam_btns.append(b)
	sp.add_child(VSeparator.new())
	mute_btn = _btn("소리 켜짐", 16)
	mute_btn.toggle_mode = true
	mute_btn.pressed.connect(_on_mute)
	sp.add_child(mute_btn)
	sp.add_child(KitS.help("레이스", HT.RACE))
	var gear2 = _btn("⚙", 16)
	gear2.size_flags_horizontal = Control.SIZE_SHRINK_END
	gear2.custom_minimum_size = Vector2(40, 0)
	gear2.pressed.connect(_open_settings)
	sp.add_child(gear2)
	# 트랙
	sfx = SfxS.new()
	add_child(sfx)
	race_view = RaceViewS.new()
	race_view.cue.connect(func(n): sfx.play(n))
	race_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	race_view.size_flags_stretch_ratio = 1.6
	race_view.clip_contents = true
	# 내 차 지시판 (칩 · 탭 · 엔지니어 제안 · 팀 오더)
	race_panel = RacePanelS.new()
	race_panel.select_car.connect(_on_select_car)
	race_panel.radio_prompt.connect(_on_radio_prompt)
	panels_box = race_panel
	# 순위 / 무전
	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var tw = VBoxContainer.new()
	tw.name = "순위"
	tabs.add_child(tw)
	gap_btn = _btn("간격: 앞차 ⇄ 선두 ⇄ 랩타임  ·  이름을 누르면 라이벌 분석", 13)
	gap_btn.pressed.connect(_on_gap_mode)
	tw.add_child(gap_btn)
	tower = _rtl(false)
	tower.meta_underlined = false
	tower.meta_clicked.connect(_on_tower_click)
	tower.size_flags_vertical = Control.SIZE_EXPAND_FILL
	KitS.drag_scroll(tower)
	_small_text(tower, 16)
	tw.add_child(tower)
	radio = _rtl(false)
	radio.name = "무전"
	KitS.drag_scroll(radio)
	_small_text(radio, 16)
	tabs.add_child(radio)


func _small_text(r: RichTextLabel, fsize: int) -> void:
	for k in ["normal_font_size", "bold_font_size", "italics_font_size", "bold_italics_font_size", "mono_font_size"]:
		r.add_theme_font_size_override(k, fsize)


func _press_only(btns: Array, idx: int) -> void:
	for i in btns.size():
		btns[i].set_pressed_no_signal(i == idx)


func _set_speed(s: int) -> void:
	speed_x = s
	_press_only(speed_btns, SPEEDS.find(s))


func _set_cam(slot: int) -> void:
	race_view.follow_slot = slot
	race_view.sel_slot = maxi(0, slot)
	_press_only(cam_btns, slot + 1)


func _my(slot: int) -> Variant:
	if sim == null:
		return null
	var mc: Array = sim.my_cars()
	return mc[slot] if slot < mc.size() else null


func _on_box(comp: String, slot: int) -> void:
	var c: Variant = _my(slot)
	if c != null:
		sim.request_pit(c, comp)
		_refresh_ui()


func _on_cancel(slot: int) -> void:
	var c: Variant = _my(slot)
	if c != null:
		sim.cancel_pit(c)
		_refresh_ui()


func _on_plan(key: String, slot: int) -> void:
	var c: Variant = _my(slot)
	if c != null:
		sim.set_plan(c, key)
		_refresh_ui()


func _on_auto(on: bool, slot: int) -> void:
	var c: Variant = _my(slot)
	if c != null:
		sim.set_auto(c, on)
		_refresh_ui()


func _on_instr(v: String, slot: int) -> void:
	var c: Variant = _my(slot)
	if c != null:
		sim.set_instr(c, v)


func _on_pace(p: String, slot: int) -> void:
	var c: Variant = _my(slot)
	if c != null:
		sim.set_pace(c, p)


func _on_wec_box(comp: String, slot: int) -> void:
	var c: Variant = _my(slot)
	if c == null:
		return
	if comp == "keep":
		sim.request_pit_wec(c, c.comp, false, true, false)
	else:
		sim.request_pit_wec(c, comp, true, true, false)
	_refresh_ui()


func _on_fuel_mode(m: String, slot: int) -> void:
	var c: Variant = _my(slot)
	if c != null:
		sim.set_fuel_mode(c, m)


func _on_ers(m: String, slot: int) -> void:
	var c: Variant = _my(slot)
	if c != null:
		sim.set_ers(c, m)


func _on_select_car(slot: int) -> void:
	race_view.sel_slot = slot
	if race_view.follow_slot >= 0:
		_set_cam(slot)


func _on_radio_prompt() -> void:
	if speed_x > 1 and bool(ST.get_v("prompt_slow")):
		_set_speed(1)
	sfx.play("radio")


func _on_gap_mode() -> void:
	gap_mode = (gap_mode + 1) % 3
	gap_btn.text = ["간격: 앞차 기준", "간격: 선두 기준", "직전 랩타임"][gap_mode] + "  ⇄"
	if sim != null:
		_refresh_ui()


# ═════════ 진행 ═════════
func _process(delta: float) -> void:
	if sim == null or not race_box.visible:
		if sfx != null:
			sfx.set_engine(0.0)
		return
	# 배경 엔진음: 출발 대기 중엔 공회전, 주행 중엔 배속에 따라
	var lvl = 0.0
	if starting:
		lvl = 0.25
	elif speed_x > 0 and not sim.done:
		lvl = 0.45 + 0.1 * log(float(speed_x)) / log(2.0)
	if not bool(ST.get_v("engine")):
		lvl = 0.0
	sfx.set_engine(lvl)
	if starting:
		_update_start(delta)
	elif speed_x > 0 and not sim.done:
		sim.advance(delta * speed_x * RaceSimS.SPEED_BASE)
	ui_timer += delta
	if ui_timer >= 0.2:
		ui_timer = 0.0
		_refresh_ui()
		if sim.done and not result_box.visible:
			_show_result()


func _update_start(delta: float) -> void:
	start_t += delta
	var n = mini(5, int(floor(start_t)) + 1)
	if start_t < start_hold:
		if n != race_view.lights:
			race_view.lights = n
			sfx.play("beep")
			top_label.text = "[font_size=28][b]%s[/b][/font_size]   [color=#ef4444]스타트 시그널 점등 중… (%d/5)[/color]" % [sim.CIRC["name"], n]
		return
	starting = false
	race_view.lights = -1
	race_view.lights_out_t = race_view.now()
	sfx.play("go")
	race_view.show_banner("소등! 레이스 시작", "green")


func _on_mute() -> void:
	sfx.muted = mute_btn.button_pressed
	mute_btn.text = "소리 꺼짐" if sfx.muted else "소리 켜짐"


func _tyre_bb(comp: String) -> String:
	return "[color=%s][b]%s[/b][/color]" % [RaceSimS.TYRE_HEX[comp], comp]


func _chip(text: String, bg: String, fg: String = "#0b0f14") -> String:
	return "[bgcolor=%s][color=%s][b] %s [/b][/color][/bgcolor]" % [bg, fg, text]


func _refresh_ui() -> void:
	if sim == null:
		return
	var ord: Array = sim.order()
	var leader = ord[0]
	var lap_now = mini(sim.laps, leader.lap + 1)
	# 상단: 큰 랩 숫자 + 상태 칩
	var chips := ""
	if sim.sc:
		chips += _chip(sim.sc_kind, "#f59e0b") + " "
	elif sim.finishing:
		chips += _chip("🏁 체커기", "#e6edf3") + " "
	else:
		chips += _chip("GREEN", "#22c55e") + " "
	if sim.drs_on() and not sim.sc:
		chips += _chip("DRS", "#0b0f14", "#22c55e") + " "
	if sim.wet >= 0.22:
		chips += _chip("WET", "#3b82f6", "#ffffff") + " "
	if sim.night:
		chips += _chip("NIGHT", "#312e81", "#ffffff") + " "
	var fmt_tag := ""
	if mode == "career" and career != null and career.has_sprint():
		fmt_tag = _chip("스프린트" if sprint_mode else "피처", "#a855f7", "#ffffff") + " "
	elif mode == "career" and career != null and career.race_format() == "f3":
		fmt_tag = _chip("F3", "#a855f7", "#ffffff") + " "
	if not starting:
		top_label.text = "[font_size=28][b]LAP %d[/b][/font_size][color=#8b98a5]/%d[/color]   %s%s" % [lap_now, sim.laps, fmt_tag, chips]
	# 날씨 줄: 서킷 · 노면 · 강수 확률 · 수막 · 그립 · 예보
	var evo_sec: float = -0.65 * sim.track_evo * (1.0 - sim.wet)
	var fc_txt := ""
	if sim.fc != null and sim.leader_lap < int(sim.fc["hi"]):
		fc_txt = " · 예보: L%d-%d 비 확률 %d%%" % [int(sim.fc["lo"]), int(sim.fc["hi"]), int(sim.fc["p"])]
	elif sim.fc == null:
		fc_txt = " · 예보: 맑음 유지"
	info_label.text = "[color=#8b98a5]%s · 노면 [b]%s[/b] · 강수확률 [b]%d%%[/b] · 수막 [b]%.1fmm[/b] · 그립 [b]%d%% (%.2fs)[/b]%s[/color]" % [
		sim.CIRC["name"], sim.surface_ko(), sim.forecast_prob_at(lap_now), sim.wet_mm(sim.wet), int(round(sim.track_evo * 100)), evo_sec, fc_txt]
	race_panel.refresh()
	rival.refresh()
	_refresh_tower(ord, leader)
	_refresh_radio()


func _wec_gaps(c) -> String:
	var same: Array = []
	for o in sim.order():
		if o.cls == c.cls:
			same.append(o)
	var i := same.find(c)
	var t := ""
	if i >= 1 and same[i - 1].dnf == "":
		t += "앞 #%s %s" % [same[i - 1].code, sim.gap_to(c, same[i - 1]).replace("+", "-")]
	if i + 1 < same.size() and same[i + 1].is_running():
		t += ("  " if t != "" else "") + "뒤 %s %s" % [same[i + 1].code, sim.gap_to(same[i + 1], c)]
	return t


func _refresh_tower(ord: Array, leader) -> void:
	if sim.is_wec():
		_refresh_tower_wec(ord)
		return
	var s = "[table=5]"
	s += "[cell][color=#8b98a5]P[/color][/cell][cell][color=#8b98a5]드라이버[/color][/cell][cell][color=#8b98a5]%s[/color][/cell][cell][color=#8b98a5]타이어[/color][/cell][cell][color=#8b98a5]피트[/color][/cell]" % ["앞차 간격", "선두와 차이", "직전 랩"][gap_mode]
	var pos = 0
	var prev: Variant = null
	for c in ord:
		pos += 1
		var name_col = "#ffc53d" if c.mine else "#e6edf3"
		var gap = ""
		if c.dnf != "":
			gap = "[color=#ef4444]DNF[/color]"
		elif gap_mode == 2:
			gap = KitS.fmt_lap(c.last_lap_t) if c.last_lap_t > 0.0 else "-"
			if c.id == sim.fastest_id:
				gap = "[color=#a855f7]%s[/color]" % gap
		elif c == leader:
			gap = "[color=#a855f7]◆[/color] 선두"
		elif gap_mode == 0 and prev != null:
			gap = sim.gap_to(c, prev)
		else:
			gap = sim.gap_to(c, leader)
		if c.time_pen > 0.0 and c.dnf == "":
			gap += " [color=#ef4444]+%ds[/color]" % int(c.time_pen)
		if c.boxing != null or c.pit_phase == 2:
			gap += " [color=#ffc53d]PIT[/color]"
		elif c.crew_out and c.dnf == "":
			gap += " [bgcolor=#ef4444][color=#ffffff] CREW [/color][/bgcolor]"
		elif c.drs and not sim.sc:
			gap += " [color=#22c55e]DRS[/color]"
		prev = c
		# 라이벌 타이어 마모는 숨기고 스틴트 나이만 공개 (관측 가능한 정보)
		var tyre = "%s [color=#8b98a5]%dL[/color]" % [_tyre_bb(c.comp), c.stint_laps]
		if c.mine:
			tyre = "%s [color=#8b98a5]%d%%[/color]" % [_tyre_bb(c.comp), int(round(c.wear * 100))]
		s += "[cell]%d  [/cell][cell][url=%d][color=%s]■[/color] [color=%s]%s[/color] [color=#8b98a5]%s[/color][/url]  [/cell][cell]%s  [/cell][cell]%s  [/cell][cell]%d[/cell]" % [
			pos, c.id, _hex(c.color), name_col, c.code, c.team, gap, tyre, c.pits]
	s += "[/table]"
	tower.text = s


func _short_team(n: String) -> String:
	for w in [" Racing", " Team", " Endurance", " TotalEnergies", " Hertz", " Gazoo"]:
		n = n.replace(w, "")
	return n


func _refresh_tower_wec(ord: Array) -> void:
	var s = "[table=5]"
	for cls in ["HY", "GT"]:
		s += "[cell][color=#ffc53d][b]%s[/b][/color][/cell][cell][/cell][cell][/cell][cell][/cell][cell][/cell]" % ("HYPERCAR" if cls == "HY" else "LMGT3")
		var lead: Variant = null
		var pos := 0
		for c in ord:
			if c.cls != cls:
				continue
			pos += 1
			if lead == null:
				lead = c
			var name_col := "#ffc53d" if c.mine else "#e6edf3"
			var gap: String = "선두" if c == lead else sim.gap_to(c, lead)
			if c.dnf != "":
				gap = "[color=#ef4444]DNF[/color]"
			if c.boxing != null or c.pit_phase == 2:
				gap += " [color=#ffc53d]PIT[/color]"
			var tyre := "%s [color=#8b98a5]%dL[/color]" % [_tyre_bb(c.comp), c.stint_laps]
			if c.mine:
				tyre = "%s [color=#8b98a5]%d%%[/color]" % [_tyre_bb(c.comp), int(round(c.wear * 100))]
			var nm: String = _short_team(c.team) + (" #%d" % (c.slot + 1))
			s += "[cell]%d  [/cell][cell][url=%d][color=%s]■[/color] [color=%s]%s[/color] [color=#8b98a5]%s[/color][/url]  [/cell][cell]%s  [/cell][cell]%s  [/cell][cell]%d[/cell]" % [pos, c.id, _hex(c.color), name_col, nm, c.code, gap, tyre, c.pits]
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
	var dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var cc = CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.add_child(cc)
	result_box = dim
	var pc = PanelContainer.new()
	pc.custom_minimum_size = Vector2(660, 680)
	result_panel = pc
	cc.add_child(pc)
	var v = VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	pc.add_child(v)
	result_title = _label("레이스 결과", 30, AMBER)
	v.add_child(result_title)
	result_text = _rtl(false)
	KitS.drag_scroll(result_text)
	result_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(result_text)
	var h = HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	v.add_child(h)
	btn_again = _btn("같은 설정으로 다시", 20)
	btn_again.pressed.connect(_start_race)
	h.add_child(btn_again)
	btn_menu = _btn("메뉴로", 20)
	btn_menu.pressed.connect(_show_menu)
	h.add_child(btn_menu)
	btn_hq = _btn("본부(HQ)로 ▶", 22)
	btn_hq.pressed.connect(_on_result_hq)
	h.add_child(btn_hq)
	btn_feature = _btn("피처 레이스 ▶", 22)
	btn_feature.pressed.connect(_start_feature)
	h.add_child(btn_feature)
	btn_debrief = _btn("📊 전략 복기", 18)
	btn_debrief.pressed.connect(_open_debrief)
	v.add_child(btn_debrief)
	v.move_child(btn_debrief, v.get_child_count() - 2)
	debrief = DebriefS.new()
	debrief.visible = false
	add_child(debrief)
	rival = RivalS.new()
	add_child(rival)
	settings_view = SettingsViewS.new()
	settings_view.changed.connect(_apply_settings)
	add_child(settings_view)


func _career_summary(ec: Dictionary) -> String:
	var mk: String = ec["mission_key"]
	var mtxt := ""
	if mk != "none":
		mtxt = (" · 미션 [color=#22c55e]달성 +%.2fM[/color]" % ec["mission"]) if ec["mission_ok"] else (" · 미션 [color=#ef4444]실패 (평판 -%d%%)[/color]" % int(ec["mission_pen"] * 100))
	var t := "[b][color=#ffc53d]커리어 정산[/color][/b] 내 팀 [b]%d점[/b]%s\n[color=#22c55e]스폰서 +%.2f · 페이 드라이버 +%.2f · 포인트 상금 +%.2f[/color] / [color=#ef4444]운영 -%.2f · 간접비 -%.2f · 연봉 -%.2f · 수리 -%.2f[/color] → 순익 [b]%+.2fM[/b] · 자금 [b]%.2fM[/b]" % [
		ec["total"], mtxt, ec["spon"], ec["pay"], ec["prize"], ec["ops"], ec["overhead"], ec["salary"], ec["repair"], ec["net"], ec["cash"]]
	for n in ec["notes"]:
		t += "\n• " + n
	return t + "\n"


func _show_result() -> void:
	var res: Array = sim.results()
	if sim.is_wec():
		var hy: Array = []
		var gt: Array = []
		for r in res:
			if r["cls"] == "HY":
				hy.append(r)
			else:
				gt.append(r)
		res = hy + gt
	var s = "[table=5]"
	s += "[cell][color=#8b98a5]P[/color][/cell][cell][color=#8b98a5]드라이버[/color][/cell][cell][color=#8b98a5]기록[/color][/cell][cell][color=#8b98a5]전략[/color][/cell][cell][color=#8b98a5]PTS[/color][/cell]"
	var last_cls := ""
	for r in res:
		var c = r["car"]
		if sim.is_wec() and c.cls != last_cls:
			last_cls = c.cls
			s += "[cell][color=#ffc53d][b]%s[/b][/color][/cell][cell][/cell][cell][/cell][cell][/cell][cell][/cell]" % ("HYPERCAR" if c.cls == "HY" else "LMGT3")
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
		var pen = (" [color=#ef4444]+%ds[/color]" % int(c.penalty)) if c.penalty > 0 else ""
		s += "[cell]%d  [/cell][cell][color=%s]■[/color] [color=%s]%s[/color] [color=#8b98a5]%s[/color]  [/cell][cell]%s%s  [/cell][cell]%s  [/cell][cell]%d[/cell]" % [
			r["pos"], _hex(c.color), name_col, (_short_team(c.team) + " #%d" % (c.slot + 1)) if sim.is_wec() else c.code, c.code if sim.is_wec() else c.team, r["gap"], pen, strat, r["points"]]
	s += "[/table]"
	if sim.fastest_id >= 0:
		var fc = sim.cars.filter(func(x): return x.id == sim.fastest_id)
		if not fc.is_empty():
			s += "\n[color=#a855f7]최고 랩[/color] %s %.3f초" % [fc[0].code, sim.fastest_t]
	btn_again.visible = mode != "career"
	btn_menu.visible = mode != "career"
	btn_hq.visible = mode == "career" and not sprint_mode
	btn_feature.visible = mode == "career" and sprint_mode
	result_title.text = "%s · %s" % ["스프린트 결과" if sprint_mode else "레이스 결과", sim.CIRC["name"]]
	if mode == "career" and not settled:
		settled = true
		if sprint_mode:
			var sp: Dictionary = career.after_sprint(sim)
			s = "[b][color=#ffc53d]스프린트[/color][/b] 내 팀 [b]%d점[/b] (상위 8위까지 10-8-6-5-4-3-2-1). 상금·스폰서 정산은 피처 레이스 뒤에 해요.\n\n" % sp["total"] + s
		else:
			var ec: Dictionary = career.after_race(sim)
			s = _career_summary(ec) + "\n" + s
			season_pending = ec.get("season_end", false)
	btn_hq.text = "시즌 결산 ▶" if season_pending else "본부(HQ)로 ▶"
	result_text.text = s
	result_box.visible = true
