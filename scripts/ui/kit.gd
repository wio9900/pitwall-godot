extends RefCounted
## 화면 부품 공통 도구 (버튼·라벨·서식 텍스트·카드). 모든 화면이 같은 모양을 쓰도록 한곳에 모았다.

const HelpS = preload("res://scripts/ui/help.gd")
const TouchDragS = preload("res://scripts/ui/touch_drag.gd")
const BG := Color("#0b0f14")
const PANEL := Color("#141a22")
const PANEL2 := Color("#1b232d")
const LINE := Color("#2a3441")
const INK := Color("#e6edf3")
const DIM := Color("#8b98a5")
const AMBER := Color("#ffc53d")
const GOOD := Color("#22c55e")
const BAD := Color("#ef4444")
const PURPLE := Color("#a855f7")
const WARN := Color("#f59e0b")


static func label(text: String, fsize := 18, col := INK) -> Label:
	var l = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", fsize)
	l.add_theme_color_override("font_color", col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


static func rtl(fsize := 16, fit := true) -> RichTextLabel:
	var r = RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = fit
	r.scroll_active = not fit
	r.selection_enabled = false
	for k in ["normal_font_size", "bold_font_size", "italics_font_size", "bold_italics_font_size", "mono_font_size"]:
		r.add_theme_font_size_override(k, fsize)
	return r


static func btn(text: String, fsize := 16, cb: Variant = null) -> Button:
	var b = Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", fsize)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if cb != null:
		b.pressed.connect(cb)
	return b


## 고정 폭 버튼 (줄 끝에 붙이는 작은 버튼)
static func sbtn(text: String, cb: Variant = null, enabled := true, col: Color = AMBER) -> Button:
	var b = Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 14)
	b.disabled = not enabled
	if enabled:
		b.add_theme_color_override("font_color", col)
	if cb != null:
		b.pressed.connect(cb)
	return b


static func hbox(sep := 6) -> HBoxContainer:
	var h = HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


static func vbox(sep := 6) -> VBoxContainer:
	var v = VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


## 둥근 테두리 카드 (안에 VBox 를 돌려준다)
static func card(parent: Control, title: String = "", accent: Color = LINE) -> VBoxContainer:
	var pc = PanelContainer.new()
	var sb = StyleBoxFlat.new()
	sb.bg_color = PANEL
	sb.border_color = accent
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 10
	pc.add_theme_stylebox_override("panel", sb)
	pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(pc)
	var v = vbox(6)
	pc.add_child(v)
	if title != "":
		v.add_child(label(title, 16, AMBER))
	return v


## 토글 버튼 묶음. items: [[값, 글자], …]. cb(값) 호출.
static func seg(parent: Control, items: Array, current: String, cb: Callable, fsize := 14, enabled := true) -> Array:
	var row = hbox(4)
	parent.add_child(row)
	var grp = ButtonGroup.new()
	var out: Array = []
	for it in items:
		var b = btn(String(it[1]), fsize)
		b.toggle_mode = true
		b.button_group = grp
		b.button_pressed = String(it[0]) == current
		b.disabled = not enabled
		b.pressed.connect(cb.bind(it[0]))
		row.add_child(b)
		out.append(b)
	return out


## 글자 + 오른쪽 버튼들 한 줄
static func row(parent: Control, text_bb: String, buttons: Array = [], fsize := 15) -> HBoxContainer:
	var h = hbox(6)
	parent.add_child(h)
	var r = rtl(fsize)
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.text = text_bb
	h.add_child(r)
	for b in buttons:
		h.add_child(b)
	return h


## 가로 막대 (0~1)
static func bar(parent: Control, frac: float, col: Color, h := 8.0) -> void:
	var bg = ColorRect.new()
	bg.color = Color("#0b1016")
	bg.custom_minimum_size = Vector2(0, h)
	bg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(bg)
	var fg = ColorRect.new()
	fg.color = col
	fg.anchor_right = clampf(frac, 0.0, 1.0)
	fg.anchor_bottom = 1.0
	bg.add_child(fg)


static func clear(node: Node) -> void:
	for ch in node.get_children():
		node.remove_child(ch)
		ch.queue_free()


static func hex(c: Color) -> String:
	return "#" + c.to_html(false)


static func money(v: float) -> String:
	return "%.2fM" % v


static func pct(v: float) -> String:
	return "%d%%" % int(round(v * 100.0))


static func fmt_lap(t: float) -> String:
	var m := int(t / 60.0)
	return "%d:%06.3f" % [m, t - m * 60.0]


## 스크롤 가능한 세로 영역
static func scroll_v(parent: Control) -> VBoxContainer:
	var sc = ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(sc)
	drag_scroll(sc)
	var v = vbox(10)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(v)
	return v


## "?" 도움말 버튼 (누르면 설명 창)
static func help(title: String, body_bb: String) -> Button:
	var b = HelpS.new()
	b.setup(title, body_bb)
	return b


## 손가락 드래그 스크롤을 붙인다 (ScrollContainer · 스크롤되는 RichTextLabel)
static func drag_scroll(ctrl: Control) -> void:
	var n = TouchDragS.new()
	n.target = ctrl
	ctrl.add_child(n)
