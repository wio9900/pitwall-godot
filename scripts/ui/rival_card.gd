extends Control
## 라이벌 분석 카드: 순위표에서 차를 누르면 뜬다. 관측 가능한 정보만 보여준다
## (상대의 실제 마모·연료·집중력은 비공개 — HTML 설계 원칙 그대로).

const K = preload("res://scripts/ui/kit.gd")
const TraitsS = preload("res://scripts/sim/traits.gd")
const RS = preload("res://scripts/sim/race_sim.gd")
const STYLE_DESC := {"aggressive": "스톱을 늘리고 소프트를 선호", "balanced": "계산상 최적에 가깝게 운영", "conservative": "스톱을 줄이고 긴 스틴트 선호", "reactive": "주변 차의 피트에 민감하게 커버"}

var sim
var car_id := -1
var _panel: PanelContainer
var _title: RichTextLabel
var _body: RichTextLabel
var _spark: Spark


## 최근 6랩 랩타임 표: 한 줄에 랩 · 타이어 · 랩타임 · 가장 빠른 랩보다 느린 만큼 막대.
## 피트 들른 랩은 회색 '피트'로 따로 표시 (막대 기준에서 뺀다)
class Spark extends Control:
	var vals: Array = []  # [{lap, t, pit, comp}] 오래된 랩 → 최근 랩
	const ROW := 30.0

	func _init() -> void:
		custom_minimum_size = Vector2(0, ROW * 6 + 4)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color("#0f141b"))
		var font: Font = get_theme_default_font()
		if vals.is_empty():
			draw_string(font, Vector2(10, 26), "아직 랩 데이터가 부족해요", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("#8b98a5"))
			return
		var best := INF
		for v in vals:
			if not v["pit"]:
				best = minf(best, float(v["t"]))
		var span := 1.0 # 막대 최대 = 1초 이상 느림 (그보다 크면 꽉 참)
		for v in vals:
			if not v["pit"] and best < INF:
				span = maxf(span, float(v["t"]) - best)
		span = minf(span, 3.0)
		var bar_x: float = size.x * 0.52
		var bar_w: float = size.x - bar_x - 70.0
		for i in vals.size():
			var v: Dictionary = vals[i]
			var y: float = 2.0 + i * ROW
			var by: float = y + ROW * 0.5 + 6.0
			if i % 2 == 0:
				draw_rect(Rect2(0, y, size.x, ROW), Color("#151b24"))
			draw_string(font, Vector2(8, by), "L%d" % int(v["lap"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("#8b98a5"))
			draw_string(font, Vector2(size.x * 0.13, by), String(v["comp"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(RS.TYRE_HEX.get(v["comp"], "#ffffff")))
			var t: float = float(v["t"])
			draw_string(font, Vector2(size.x * 0.20, by), "%d:%06.3f" % [int(t) / 60, fmod(t, 60.0)], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#e6edf3"))
			if v["pit"]:
				draw_string(font, Vector2(bar_x, by), "피트 들른 랩", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#6b7280"))
				continue
			var d: float = t - best
			if d < 0.005:
				draw_string(font, Vector2(bar_x, by), "가장 빠름", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#22c55e"))
				continue
			var col := Color("#ef4444") if d > 1.2 else (Color("#f59e0b") if d > 0.5 else Color("#22c55e"))
			var bw: float = clampf(d / span, 0.04, 1.0) * bar_w
			draw_rect(Rect2(bar_x, y + 8, bw, ROW - 16), col)
			draw_string(font, Vector2(bar_x + bw + 6, by), "+%.2f" % d, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, col)



func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	add_to_group("modal")
	var dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(_on_dim)
	add_child(dim)
	var cc = CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cc)
	_panel = PanelContainer.new()
	var sb = StyleBoxFlat.new()
	sb.bg_color = K.PANEL
	sb.border_color = K.AMBER
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(2)
	sb.set_content_margin_all(14)
	_panel.add_theme_stylebox_override("panel", sb)
	cc.add_child(_panel)
	var v = K.vbox(8)
	_panel.add_child(v)
	_title = K.rtl(18)
	v.add_child(_title)
	_body = K.rtl(14)
	v.add_child(_body)
	v.add_child(K.label("최근 랩타임 (막대 = 가장 빠른 랩보다 느린 만큼)", 14, K.DIM))
	_spark = Spark.new()
	v.add_child(_spark)
	v.add_child(K.btn("닫기", 16, close_card))


func show_car(sim_, id: int) -> void:
	sim = sim_
	car_id = id
	_panel.custom_minimum_size = Vector2(minf(560.0, get_viewport_rect().size.x - 32.0), 0)
	visible = true
	refresh()


func close_card() -> void:
	visible = false
	car_id = -1


func _on_dim(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed:
		close_card()


func refresh() -> void:
	if not visible or sim == null:
		return
	var c: Variant = null
	for o in sim.cars:
		if o.id == car_id:
			c = o
	if c == null:
		close_card()
		return
	var wec: bool = sim.is_wec()
	var who: String = ("%s #%d · %s" % [c.team, c.slot + 1, c.name]) if wec else ("%s (%s)" % [c.name, c.code])
	_title.text = "[color=%s]■[/color] [b]%s[/b]  [color=#8b98a5]%s[/color]" % [K.hex(c.color), who, c.team if not wec else RS.TYRE_KO.get(c.comp, "")]
	var pos: int = sim.class_pos(c)
	var t := ""
	if c.dnf != "":
		t += "[color=#ef4444]리타이어: %s[/color]\n" % c.dnf
	t += "현재 [b]P%d[/b] · 타이어 [color=%s][b]%s[/b][/color] [b]%d랩째[/b] · 피트 %d회\n" % [pos, RS.TYRE_HEX[c.comp], RS.TYRE_KO[c.comp], c.stint_laps, c.pits]
	if not c.traits.is_empty():
		t += "[color=#ffc53d]◆ %s[/color]\n" % TraitsS.label(c.traits)
	for pe in c.pen_log:
		t += "[color=#ef4444]🟨 L%d %s +%d초[/color]\n" % [int(pe["lap"]), pe["why"], int(pe["secs"])]
	if c.dnf != "" and c.dnf_detail != "":
		t += "[color=#ef4444]🔧 리타이어: %s[/color]\n" % c.dnf_detail
	t += "피트월 크루: %s\n" % ("[bgcolor=#ef4444][color=#ffffff] CREW OUT [/color][/bgcolor] 곧 박스할 수 있어요!" if c.crew_out else "차고 대기")
	# 피트 이력·사용한 타이어
	var ph: PackedStringArray = []
	for e in c.pit_log:
		ph.append("L%d → %s" % [int(e["lap"]), e["to"]])
	t += "피트 이력: %s\n" % (", ".join(ph) if not ph.is_empty() else "없음")
	if sim.need_two() and _slicks(c) < 2 and c.dnf == "":
		t += "[color=#f59e0b]아직 두 번째 컴파운드를 안 썼어요 → 피트가 남아 있어요[/color]\n"
	# 전략 성향
	if not c.mine and not wec:
		t += "전략가 성향: [b]%s[/b] · %s · 전략 능력 %d\n" % [RS.STRAT_KO.get(c.strat_style, "-"), STYLE_DESC.get(c.strat_style, ""), int(round(c.strategy * 100))]
	# 마모 추이 (최근 3랩 기울기) · 예상 다음 피트
	var recent: Array = []
	for lh in c.lap_hist:
		if lh["pit"]:
			break
		recent.append(lh)
	if recent.size() >= 3:
		var slope: float = (float(recent[0]["t"]) - float(recent[2]["t"])) / 2.0
		t += "페이스 추이: 랩당 [b]%+.2f초[/b] (%s)\n" % [slope, "⚠ 급격한 그립 저하·절벽 의심" if slope > 0.35 else ("완만한 마모 진행" if slope > 0.15 else "페이스 일정")]
	else:
		t += "[color=#8b98a5]페이스 추이: 데이터 수집 중 (3랩 필요)[/color]\n"
	if RS.SLICK.has(c.comp) and c.dnf == "" and not c.finished:
		var wr: float = float(RS.COMP[c.comp][1]) * float(sim.rules.get("wear_mult", 1.0)) * float(sim.CIRC["wear"]) * (RS.WEAR_SCALE / sim.laps) * 0.85
		var to_lim: int = int(maxf(0.0, (0.62 - c.stint_laps * wr) / maxf(0.001, wr)))
		var est: int = c.lap + 1 + to_lim
		t += "예상 다음 피트 (공칭 마모 기준): [b]%s[/b]" % (("L%d 전후" % est) if est < sim.laps - 1 else "끝까지 갈 수도")
	_body.text = t
	var sp: Array = []
	var hist: Array = c.lap_hist.slice(0, 6)
	hist.reverse()
	for lh in hist:
		sp.append({"lap": int(lh["lap"]), "t": float(lh["t"]), "pit": bool(lh.get("pit", false)), "comp": String(lh.get("comp", c.comp))})
	_spark.vals = sp
	_spark.queue_redraw()


func _slicks(c) -> int:
	return c.used_slicks()
