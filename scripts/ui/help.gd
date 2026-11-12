extends Button
## "?" 도움말 버튼: 누르면 화면 위에 설명 창을 띄운다. Kit.help(제목, 본문) 으로 만든다.

var title_txt := ""
var body_bb := ""
var _ov: Control = null


func setup(t: String, b: String) -> void:
	title_txt = t
	body_bb = b
	text = "?"
	tooltip_text = t
	custom_minimum_size = Vector2(36, 32)
	add_theme_font_size_override("font_size", 16)
	add_theme_color_override("font_color", Color("#38bdf8"))
	pressed.connect(open)


func open() -> void:
	if _ov != null and is_instance_valid(_ov):
		return
	var vp_size: Vector2 = get_viewport_rect().size
	_ov = Control.new()
	_ov.add_to_group("modal")
	_ov.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ov.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(_on_dim_input)
	_ov.add_child(dim)
	var cc = CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ov.add_child(cc)
	var pc = PanelContainer.new()
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color("#141a22")
	sb.border_color = Color("#38bdf8")
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(14)
	pc.add_theme_stylebox_override("panel", sb)
	pc.custom_minimum_size = Vector2(minf(680.0, vp_size.x - 32.0), 0)
	cc.add_child(pc)
	var v = VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	pc.add_child(v)
	var t = Label.new()
	t.text = "도움말 · " + title_txt
	t.add_theme_font_size_override("font_size", 20)
	t.add_theme_color_override("font_color", Color("#38bdf8"))
	v.add_child(t)
	var r = RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = false
	r.scroll_active = true
	r.custom_minimum_size = Vector2(0, minf(470.0, vp_size.y - 180.0))
	for k in ["normal_font_size", "bold_font_size"]:
		r.add_theme_font_size_override(k, 16)
	r.text = body_bb
	v.add_child(r)
	var td = load("res://scripts/ui/touch_drag.gd").new()
	td.target = r
	r.add_child(td)
	var close = Button.new()
	close.text = "닫기"
	close.add_theme_font_size_override("font_size", 18)
	close.custom_minimum_size = Vector2(0, 44)
	close.pressed.connect(close_help)
	v.add_child(close)
	# 테마(한글 글꼴·버튼 모양)를 물려받도록 테마가 있는 조상 아래에 띄운다
	var host: Node = self
	while host != null and not (host is Control and (host as Control).theme != null):
		host = host.get_parent()
	if host == null:
		get_viewport().add_child(_ov)
	else:
		host.add_child(_ov)
		_ov.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func close_help() -> void:
	if _ov != null and is_instance_valid(_ov):
		_ov.queue_free()
	_ov = null


func _on_dim_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed:
		close_help()


func _exit_tree() -> void:
	close_help()
