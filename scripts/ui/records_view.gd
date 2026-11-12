extends Control
## 기록실 (메뉴의 🏆 기록 버튼): 전체 누적 · 서킷별 최고 기록 · 최근 레이스 · 커리어 연대기.

const K = preload("res://scripts/ui/kit.gd")
const REC = preload("res://scripts/sim/records.gd")
const CareerS = preload("res://scripts/sim/career.gd")

var _box: VBoxContainer
var _panel: PanelContainer
var _tab := "circ"


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	add_to_group("modal")
	var dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var cc = CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(cc)
	_panel = PanelContainer.new()
	var sb = StyleBoxFlat.new()
	sb.bg_color = K.PANEL
	sb.border_color = K.AMBER
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(16)
	_panel.add_theme_stylebox_override("panel", sb)
	cc.add_child(_panel)
	_box = K.vbox(10)
	_panel.add_child(_box)


func open() -> void:
	var vs: Vector2 = get_viewport_rect().size
	_panel.custom_minimum_size = Vector2(minf(820.0, vs.x - 32.0), minf(640.0, vs.y - 40.0))
	visible = true
	_render()


func _on_tab(v) -> void:
	_tab = v
	_render()


func _render() -> void:
	K.clear(_box)
	REC.ensure()
	var head = K.hbox(10)
	_box.add_child(head)
	var tl = K.label("🏆 기록실", 24, K.AMBER)
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(tl)
	head.add_child(K.btn("닫기", 16, func(): visible = false))
	var tot: Dictionary = REC.data["totals"]
	var sum = K.rtl(16)
	sum.text = "레이스 [b]%d[/b] · 우승 [b][color=#ffc53d]%d[/color][/b] · 포디움 [b]%d[/b] · 포인트 [b]%d[/b] · 리타이어 [b]%d[/b]" % [
		int(tot["races"]), int(tot["wins"]), int(tot["podiums"]), int(tot["points"]), int(tot["dnf"])]
	_box.add_child(sum)
	K.seg(_box, [["circ", "서킷별 기록"], ["log", "최근 레이스"], ["career", "커리어 연대기"]], _tab, _on_tab, 15)
	var body = K.scroll_v(_box)
	match _tab:
		"circ":
			_render_circ(body)
		"log":
			_render_log(body)
		_:
			_render_career(body)


func _render_circ(body: VBoxContainer) -> void:
	var circs: Dictionary = REC.data["circuits"]
	if circs.is_empty():
		body.add_child(K.label("아직 기록이 없어요. 레이스를 완주하면 여기에 쌓여요.", 15, K.DIM))
		return
	var keys: Array = circs.keys()
	keys.sort_custom(func(a, b): return int(circs[a]["races"]) > int(circs[b]["races"]))
	var t := "[table=6][cell][color=#8b98a5]서킷[/color]  [/cell][cell][color=#8b98a5]레이스[/color]  [/cell][cell][color=#8b98a5]최고 순위[/color]  [/cell][cell][color=#8b98a5]우승[/color]  [/cell][cell][color=#8b98a5]포디움[/color]  [/cell][cell][color=#8b98a5]최고 랩[/color][/cell]"
	for k in keys:
		var c: Dictionary = circs[k]
		var bp: int = int(c["best_pos"])
		var bp_t: String = ("[color=#ffc53d][b]P%d[/b][/color]" % bp) if bp == 1 else (("P%d" % bp) if bp > 0 else "-")
		var tag: String = " [color=#8b98a5]WEC[/color]" if c.get("series", "") == "wec" else ""
		t += "[cell]%s%s  [/cell][cell]%d  [/cell][cell]%s  [/cell][cell]%d  [/cell][cell]%d  [/cell][cell]%s [color=#8b98a5]%s[/color][/cell]" % [
			c["name"], tag, int(c["races"]), bp_t, int(c["wins"]), int(c["podiums"]), REC.fmt_lap(float(c["best_lap"])), c.get("best_lap_by", "")]
	t += "[/table]"
	var r = K.rtl(15)
	r.text = t
	body.add_child(r)


func _render_log(body: VBoxContainer) -> void:
	var lg: Array = REC.data["log"]
	if lg.is_empty():
		body.add_child(K.label("아직 기록이 없어요.", 15, K.DIM))
		return
	var t := ""
	for e in lg:
		var pos: int = int(e["pos"])
		var pt: String = "[color=#ef4444]리타이어[/color]" if pos == 0 else ("[color=#ffc53d][b]P%d[/b][/color]" % pos if pos <= 3 else "P%d" % pos)
		var md: String = "커리어" if e.get("mode", "") == "career" else "퀵"
		var tag: String = (" · " + String(e["tag"])) if String(e.get("tag", "")) != "" else ""
		t += "[color=#8b98a5]%s[/color]  [b]%s[/b] [color=#8b98a5](%s%s · %d랩)[/color]  %s  %s · %d점\n" % [e["date"], e["circ"], md, tag, int(e["laps"]), e["team"], pt, int(e["pts"])]
	var r = K.rtl(15)
	r.text = t
	body.add_child(r)


func _render_career(body: VBoxContainer) -> void:
	var any := false
	for sl in range(1, CareerS.SLOTS + 1):
		if not CareerS.has_save(sl):
			continue
		var f = FileAccess.open(CareerS.path_for(sl), FileAccess.READ)
		if f == null:
			continue
		var hq = JSON.parse_string(f.get_as_text())
		if typeof(hq) != TYPE_DICTIONARY:
			continue
		any = true
		var card = K.card(body, "슬롯 %d · %s (시즌 %d 진행 중)" % [sl, hq.get("team_name", "?"), int(hq.get("season", 1))], K.AMBER)
		var t := ""
		var trophies: Array = hq.get("trophies", [])
		if not trophies.is_empty():
			var tp: PackedStringArray = []
			for tr_ in trophies:
				var medal: String = "🥇" if int(tr_["rank"]) == 1 else ("🥈" if int(tr_["rank"]) == 2 else "🥉")
				tp.append("%s S%d %s%s" % [medal, int(tr_["season"]), tr_.get("tier_name", ""), (" 드라이버 " + String(tr_["driver"])) if tr_.has("driver") else ""])
			t += "트로피: " + "  ".join(tp) + "\n"
		var slog: Array = hq.get("season_log", [])
		if slog.is_empty():
			t += "[color=#8b98a5]아직 끝난 시즌이 없어요.[/color]"
		for e in slog:
			var tn: String = String(e.get("tier_name", ""))
			if tn == "":
				tn = "티어 %d" % int(e.get("tier", 1))
			t += "[b]시즌 %d[/b] · %s · 컨스트럭터 [b]P%d[/b] (%d점) · 우승 %d · 포디움 %d · 챔피언 %s\n" % [
				int(e["season"]), tn, int(e["rank"]), int(e.get("pts", 0)), int(e.get("wins", 0)), int(e.get("podiums", 0)), e.get("champ", "-")]
		var r = K.rtl(15)
		r.text = t
		card.add_child(r)
	if not any:
		body.add_child(K.label("저장된 커리어가 없어요.", 15, K.DIM))
