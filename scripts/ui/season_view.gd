extends Control
## 시즌 결산 화면: 트로피 · 최종 컨스트럭터/드라이버 순위 · 내 시즌 기록 · 역대 기록.
## career.hq["last_season"] 을 읽어 그리기만 한다.

signal done

const K = preload("res://scripts/ui/kit.gd")

var cr
var _body: VBoxContainer
var _trophy: Trophy


## 트로피 그림 (1위 금 · 2위 은 · 3위 동 · 그 밖은 기념 방패). 1위면 꽃가루가 흩날린다.
class Trophy extends Control:
	var rank := 1
	var t := 0.0
	var bits: Array = []

	func _init() -> void:
		custom_minimum_size = Vector2(170, 190)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_rank(r: int) -> void:
		rank = r
		bits.clear()
		if r == 1:
			var rng = RandomNumberGenerator.new()
			rng.seed = 77
			for i in 46:
				bits.append([rng.randf(), rng.randf() * 3.0, rng.randf_range(0.25, 0.6), [Color("#fbbf24"), Color("#ef4444"), Color("#22c55e"), Color("#38bdf8"), Color("#a855f7")][i % 5], rng.randf() * TAU])
		queue_redraw()

	func _process(delta: float) -> void:
		if not is_visible_in_tree():
			return
		t += delta
		queue_redraw()

	func _draw() -> void:
		var w: float = size.x
		var h: float = size.y
		var cx: float = w * 0.5
		var col: Color = Color("#fbbf24") if rank == 1 else (Color("#cbd5e1") if rank == 2 else (Color("#d97706") if rank == 3 else Color("#475569")))
		var dark: Color = col.darkened(0.35)
		var glow: float = 0.5 + 0.5 * sin(t * 2.2)
		draw_circle(Vector2(cx, h * 0.36), w * 0.42, Color(col.r, col.g, col.b, 0.08 + 0.06 * glow))
		if rank <= 3:
			# 컵 몸통
			var top_y: float = h * 0.1
			var cup := PackedVector2Array([Vector2(cx - w * 0.3, top_y), Vector2(cx + w * 0.3, top_y), Vector2(cx + w * 0.22, h * 0.42), Vector2(cx + w * 0.08, h * 0.55), Vector2(cx - w * 0.08, h * 0.55), Vector2(cx - w * 0.22, h * 0.42)])
			draw_colored_polygon(cup, col)
			draw_polyline(PackedVector2Array([cup[0], cup[1]]), dark, 3.0)
			# 손잡이
			draw_arc(Vector2(cx - w * 0.3, h * 0.24), w * 0.11, PI * 0.5, PI * 1.5, 18, col, 6.0)
			draw_arc(Vector2(cx + w * 0.3, h * 0.24), w * 0.11, -PI * 0.5, PI * 0.5, 18, col, 6.0)
			# 기둥·받침
			draw_rect(Rect2(cx - w * 0.04, h * 0.55, w * 0.08, h * 0.16), dark)
			draw_rect(Rect2(cx - w * 0.2, h * 0.71, w * 0.4, h * 0.07), col)
			draw_rect(Rect2(cx - w * 0.26, h * 0.78, w * 0.52, h * 0.1), dark)
			# 반짝임
			var sx: float = cx - w * 0.14 + w * 0.06 * sin(t * 1.3)
			draw_line(Vector2(sx, top_y + 10), Vector2(sx + 6, h * 0.4), Color(1, 1, 1, 0.45), 3.0)
		else:
			var sh := PackedVector2Array([Vector2(cx - w * 0.28, h * 0.12), Vector2(cx + w * 0.28, h * 0.12), Vector2(cx + w * 0.28, h * 0.5), Vector2(cx, h * 0.78), Vector2(cx - w * 0.28, h * 0.5)])
			draw_colored_polygon(sh, col)
			draw_polyline(sh + PackedVector2Array([sh[0]]), dark, 3.0)
		var font: Font = get_theme_default_font()
		var lab := "P%d" % rank
		var fs := 30
		var tw: float = font.get_string_size(lab, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var ty: float = h * 0.36 if rank <= 3 else h * 0.44
		draw_string(font, Vector2(cx - tw * 0.5, ty), lab, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("#0b0f14") if rank <= 3 else Color("#e6edf3"))
		# 꽃가루
		for b in bits:
			var y: float = fmod(float(b[1]) + t * float(b[2]), 1.25) - 0.15
			var x: float = float(b[0]) * w + sin(t * 2.0 + float(b[4])) * 8.0
			var a: float = t * 3.0 + float(b[4])
			var p := Vector2(x, y * h)
			draw_set_transform(p, a, Vector2.ONE)
			draw_rect(Rect2(-3, -1.5, 6, 3), b[3])
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func open(cr_) -> void:
	cr = cr_
	if _body == null:
		_build_shell()
	refresh()


func _build_shell() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var mc = MarginContainer.new()
	mc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		mc.add_theme_constant_override("margin_" + side, 12)
	add_child(mc)
	var v = K.vbox(8)
	mc.add_child(v)
	_body = K.scroll_v(v)
	var go = K.btn("본부(HQ)로 ▶  다음 시즌 준비", 20, _on_done)
	go.custom_minimum_size = Vector2(0, 54)
	v.add_child(go)


func _on_done() -> void:
	done.emit()


func _txt(parent: Control, bb: String, fsize := 14) -> RichTextLabel:
	var r = K.rtl(fsize)
	r.text = bb
	parent.add_child(r)
	return r


func refresh() -> void:
	K.clear(_body)
	var h: Dictionary = cr.hq
	var ls: Dictionary = h.get("last_season", {})
	if ls.is_empty():
		_txt(_body, "아직 끝난 시즌이 없어요.", 16)
		return
	var rank: int = int(ls["rank"])
	# 머리: 트로피 + 제목
	var top = K.hbox(14)
	_body.add_child(top)
	_trophy = Trophy.new()
	_trophy.set_rank(rank)
	top.add_child(_trophy)
	var tv = K.vbox(6)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(tv)
	var head := "시즌 %d 종료 · %s" % [int(ls["season"]), ls["tier_name"]]
	tv.add_child(K.label(head, 26, K.AMBER))
	var verdict: String = "🏆 컨스트럭터 챔피언!" if rank == 1 else ("포디움 피니시! 시즌 P%d" % rank if rank <= 3 else "시즌 최종 P%d" % rank)
	tv.add_child(K.label(verdict, 22, K.INK))
	var st: Dictionary = ls["stats"]
	var best: int = int(st.get("best", 99))
	_txt(tv, "[b]%d점[/b] · 우승 [b]%d[/b] · 포디움 [b]%d[/b] · 최고 [b]%s[/b] · 리타이어 %d · 상금 [color=#22c55e]+%.2fM[/color]" % [int(ls["pts"]), int(st.get("wins", 0)), int(st.get("podiums", 0)), ("P%d" % best) if best < 99 else "-", int(st.get("dnf", 0)), float(ls["prize"])], 16)
	var dc: String = ls["drv_champ"]
	var my_drv: int = int(ls["my_drv"])
	_txt(tv, "드라이버 챔피언 [b][color=#ffc53d]%s[/color][/b] · 컨스트럭터 챔피언 [b]%s[/b]%s" % [dc, ls["champ"], ("\n우리 드라이버 최고 순위 [b]P%d[/b]" % my_drv) if my_drv > 0 else ""], 15)
	# 순위표 두 개
	var row = K.hbox(10)
	_body.add_child(row)
	var c1 = K.card(row, "컨스트럭터 최종 순위")
	var t1 := ""
	var i := 0
	for r in ls["cons"]:
		i += 1
		var col := "#ffc53d" if r["mine"] else "#e6edf3"
		t1 += "%s P%-2d [color=%s]■[/color] [color=%s]%s[/color]  [b]%d[/b]\n" % [_medal(i), i, r["color"], col, r["name"], int(r["pts"])]
	_txt(c1, t1, 14)
	var c2 = K.card(row, "드라이버 챔피언십")
	var t2 := ""
	i = 0
	for r in ls["drivers"]:
		i += 1
		var col2 := "#ffc53d" if r["mine"] else "#e6edf3"
		t2 += "%s P%-2d [color=%s]■[/color] [color=%s]%s[/color] [color=#8b98a5]%s[/color]  [b]%d[/b]%s\n" % [_medal(i), i, r["color"], col2, r["name"], _short(String(r["team"])), int(r["pts"]), (" · %d승" % int(r["wins"])) if int(r["wins"]) > 0 else ""]
	_txt(c2, t2 if t2 != "" else "[color=#8b98a5]기록 없음[/color]", 14)
	# 시즌 정산 알림
	var notes: Array = ls.get("notes", [])
	if not notes.is_empty():
		var c3 = K.card(_body, "시즌 정산 · 다음 시즌 소식", K.AMBER)
		var nt := ""
		for n in notes:
			nt += "• %s\n" % n
		_txt(c3, nt, 13)
	# 트로피 진열장 + 역대 기록
	var c4 = K.card(_body, "트로피 진열장")
	var tr: Array = h.get("trophies", [])
	if tr.is_empty():
		_txt(c4, "[color=#8b98a5]아직 트로피가 없어요. 시즌 3위 안에 들면 여기에 쌓여요.[/color]", 14)
	else:
		var tt := ""
		for x in tr:
			var icon := "🏆" if int(x["rank"]) == 1 else ("🥈" if int(x["rank"]) == 2 else "🥉")
			if x.has("driver"):
				tt += "%s 시즌 %d %s 드라이버 챔피언 (%s)\n" % [icon, int(x["season"]), x["tier_name"], x["driver"]]
			else:
				tt += "%s 시즌 %d %s 컨스트럭터 P%d\n" % [icon, int(x["season"]), x["tier_name"], int(x["rank"])]
		_txt(c4, tt, 15)
	var c5 = K.card(_body, "역대 시즌")
	var t5 := ""
	for s in h["season_log"]:
		t5 += "시즌 %d · %s · [b]P%d[/b] · %d점 · 우승 %d · 포디움 %d · 챔피언 %s / %s\n" % [int(s["season"]), cr.tier_meta(int(s.get("tier", 3)))["short"], int(s["rank"]), int(s.get("pts", 0)), int(s.get("wins", 0)), int(s.get("podiums", 0)), s.get("champ", "-"), s.get("drv_champ", "-")]
	_txt(c5, t5, 13)


func _medal(i: int) -> String:
	return "🥇" if i == 1 else ("🥈" if i == 2 else ("🥉" if i == 3 else "   "))


func _short(n: String) -> String:
	return n if n.length() <= 16 else n.substr(0, 15) + "…"
