extends Control
## 팀 본부(HQ) 화면: 개요 · 개발 · 설비 · 인력 · 스폰서 · 리그.
## 모든 계산은 scripts/sim/career.gd 에 있고, 이 화면은 보여주고 버튼만 연결한다.

signal go_weekend
signal go_menu
signal go_season
signal go_resume
signal go_invite

const K = preload("res://scripts/ui/kit.gd")
const DB = preload("res://scripts/data/game_db.gd")
const CS = preload("res://scripts/sim/career.gd")
const RS = preload("res://scripts/sim/race_sim.gd")
const HT = preload("res://scripts/ui/help_text.gd")
const RaceSaveS = preload("res://scripts/sim/race_save.gd")
const TrackMapS = preload("res://scripts/ui/track_map.gd")
const REC = preload("res://scripts/sim/records.gd")

const TABS := [["home", "개요"], ["rnd", "개발"], ["base", "설비"], ["staff", "인력"], ["spon", "스폰서"], ["league", "리그"]]
const REGION_KO := {"uk": "영국 (공력)", "italy": "이탈리아 (엔진)", "germany": "독일 (섀시·내구)", "japan": "일본 (타이어)"}
const BRANCH_KO := {"downforce": "고다운포스", "balanced": "올라운더", "lowdrag": "저항 저감"}
const MISSION_KO := {"none": "약속 안 함", "both_finish": "두 대 모두 완주", "double_p8": "두 대 모두 P8 이내", "podium_one": "한 대 이상 포디움"}

var cr
var tab := "home"
var wec_target: Array = [0, 2]  # WEC 영입 시 바꿀 자리 [차, 순번]
var _head: VBoxContainer
var _tabs_row: HBoxContainer
var _body: VBoxContainer
var _foot: HBoxContainer


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
		mc.add_theme_constant_override("margin_" + side, 10)
	add_child(mc)
	K.center_col(mc, 1180.0)
	var v = K.vbox(8)
	mc.add_child(v)
	_head = K.vbox(4)
	v.add_child(_head)
	_tabs_row = K.hbox(4)
	_tabs_row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(_tabs_row)
	_body = K.scroll_v(v)
	_foot = K.hbox(8)
	v.add_child(_foot)


func refresh() -> void:
	cr.evaluate_engine_politics()
	_render_head()
	K.clear(_tabs_row)
	K.seg(_tabs_row, TABS, tab, _on_tab, 15)
	K.clear(_body)
	match tab:
		"home":
			_tab_home()
		"rnd":
			_tab_rnd()
		"base":
			_tab_base()
		"staff":
			_tab_staff()
		"spon":
			_tab_spon()
		_:
			_tab_league()
	K.clear(_foot)
	_foot.add_child(K.btn("◀ 메뉴", 15, _on_menu))
	var nc: Dictionary = DB.circuits[cr.next_circuit()]
	var go: Button
	# 레이스 도중 나왔으면 주말을 처음부터가 아니라 그 랩부터 이어서
	var rs: Dictionary = RaceSaveS.peek()
	if not rs.is_empty() and rs.get("mode", "") == "career" and int(rs.get("slot", 0)) == cr.save_slot:
		go = K.btn("▶ %s 레이스 이어하기 · L%d/%d" % [rs.get("circ", nc["name"]), int(rs.get("lap", 0)), int(rs.get("laps", 0))], 18, func(): go_resume.emit())
		go.add_theme_color_override("font_color", K.AMBER)
	else:
		go = K.btn("R%d %s 레이스 주말 ▶" % [cr.round_idx() + 1, nc["name"]], 18, _on_weekend)
		if bool(cr.hq.get("lemans_invite", false)):
			var inv = K.btn("🎟 르망 24시 초청 출전", 16, func(): go_invite.emit())
			inv.add_theme_color_override("font_color", K.AMBER)
			inv.size_flags_stretch_ratio = 1.6
			_foot.add_child(inv)
	go.size_flags_stretch_ratio = 3.0
	_foot.add_child(go)


func _on_tab(v) -> void:
	tab = v
	refresh()


func _on_menu() -> void:
	go_menu.emit()


func _on_weekend() -> void:
	go_weekend.emit()


func _act(ok: bool) -> void:
	if ok:
		cr.save()
	refresh()


func _h() -> Dictionary:
	return cr.hq


# ═════════ 머리글 ═════════
func _render_head() -> void:
	K.clear(_head)
	var h := _h()
	var hr = K.hbox(6)
	_head.add_child(hr)
	var r = K.rtl(20)
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.text = "[center][color=%s]■[/color] [b]%s[/b] [color=#8b98a5]HQ · %s · 시즌 %d · R%d/%d[/color]" % [h["team_color"], h["team_name"], cr.tier_meta()["short"], int(h["season"]), cr.round_idx() + 1, cr.cal_len()]
	r.text += "[/center]"
	hr.add_child(r)
	var tab_ko: String = "개요"
	for tt in TABS:
		if tt[0] == tab:
			tab_ko = tt[1]
	hr.add_child(K.help("HQ · " + tab_ko, HT.HQ.get(tab, "")))
	var cap: float = h["cost_cap_limit"]
	var spent: float = h["spent_cap"]
	var proj: float = cr.projected_spend()
	var r2 = K.rtl(15)
	var proj_col := "#ef4444" if proj > cap else ("#f59e0b" if cap - proj < 1.5 else "#22c55e")
	r2.text = "[center]자금 [b][color=#ffc53d]%.2fM[/color][/b] · 평판 [color=#a855f7]%d%%[/color] · 코스트캡 [b]%.2f / %.1fM[/b] · 남은 경기 운영비 포함 예상 [color=%s]%.2fM[/color]" % [float(h["cash"]), int(round(float(h["pop"]) * 100)), spent, cap, proj_col, proj]
	r2.text += "[/center]"
	_head.add_child(r2)
	var frac := spent / maxf(0.1, cap)
	K.bar(_head, frac, K.BAD if frac >= 0.9 else (K.WARN if frac >= 0.75 else K.GOOD), 6.0)


func _txt(parent: Control, bb: String, fsize := 14) -> RichTextLabel:
	var r = K.rtl(fsize)
	r.text = bb
	parent.add_child(r)
	return r


# ═════════ 개요 ═════════
func _tab_home() -> void:
	var h := _h()
	var ev: Variant = h.get("event")
	if ev != null:
		var ce = K.card(_body, ev["title"], K.AMBER)
		_txt(ce, "%s\n[color=#8b98a5]고르지 않고 주말로 가면 마지막 선택지로 처리돼요.[/color]" % ev["msg"], 15)
		var eh = K.hbox(6)
		ce.add_child(eh)
		var opts: Array = ev["opts"]
		for oi in opts.size():
			var b = K.btn(String(opts[oi]["label"]), 14, _on_event.bind(oi))
			b.custom_minimum_size = Vector2(0, 42)
			eh.add_child(b)
	var nmods: Dictionary = h.get("next_mods", {})
	if not nmods.is_empty():
		var parts: Array = []
		var fl: Array = nmods.get("focus", [0, 0])
		for sl in 2:
			if int(fl[sl]) != 0:
				parts.append("#%d 집중력 %+d" % [sl + 1, int(fl[sl])])
		var gl: Array = nmods.get("grid_pen", [0, 0])
		for sl in 2:
			if int(gl[sl]) > 0:
				parts.append("#%d 그리드 -%d" % [sl + 1, int(gl[sl])])
		if float(nmods.get("rel", 0.0)) != 0.0:
			parts.append("신뢰성 %+d%%" % int(round(float(nmods["rel"]) * 100)))
		if float(nmods.get("practice", 0.0)) > 0.0:
			parts.append("연습 -%d랩" % int(nmods["practice"]))
		if not parts.is_empty():
			_txt(_body, "[color=#ffc53d]다음 레이스 효과:[/color] %s" % " · ".join(parts), 14)
	var top = K.hbox(10)
	_body.add_child(top)
	# 차량 상태
	var c1 = K.card(top, "차량 상태")
	var st: Dictionary = cr.car_stats()
	_txt(c1, "종합 [b][color=#22c55e]OVR %d[/color][/b]" % st["ovr"], 15)
	for row in st["rows"]:
		var hb = K.hbox(6)
		c1.add_child(hb)
		var l = K.label(row[0], 14, K.DIM)
		l.custom_minimum_size = Vector2(96, 0)
		hb.add_child(l)
		var v: int = row[1]
		K.bar(hb, v / 100.0, K.PURPLE if v >= 90 else (K.GOOD if v >= 84 else K.AMBER), 10.0)
		var lv = K.rtl(14)
		lv.custom_minimum_size = Vector2(70, 0)
		lv.text = "[b]%d[/b] [color=#22c55e]%+d[/color]" % [v, row[2]]
		hb.add_child(lv)
	# 순위
	var c2 = K.card(top, "시즌 %d 컨스트럭터 순위" % int(h["season"]))
	var t := ""
	var i := 0
	for s in cr.standings():
		i += 1
		var col := "#ffc53d" if s["mine"] else "#e6edf3"
		t += "P%-2d [color=%s]■[/color] [color=%s]%s[/color]  [b]%d[/b]\n" % [i, s["color"], col, s["name"], s["pts"]]
	_txt(c2, t, 14)
	# 다음 레이스 + 미션
	var nk: String = cr.next_circuit()
	var nc: Dictionary = DB.circuits[nk]
	var c3o = K.card(_body, "다음 레이스 · R%d %s" % [cr.round_idx() + 1, nc["full"]], K.AMBER)
	var c3: Control = c3o
	# 넓은 화면(폴드 펼친 화면·가로)에선 왼쪽 정보 | 오른쪽 서킷 지도
	if get_viewport_rect().size.x >= 900.0:
		var hb = K.hbox(12)
		c3o.add_child(hb)
		var lv = K.vbox(6)
		lv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(lv)
		var mp = TrackMapS.new()
		mp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mp.custom_minimum_size = Vector2(0, 280)
		mp.set_circuit(nk)
		hb.add_child(mp)
		c3 = lv
		REC.ensure()
		var rc: Dictionary = REC.data["circuits"].get(nk, {})
		var rec_t := "[color=#8b98a5]이 서킷 첫 출전[/color]"
		if not rc.is_empty() and int(rc.get("races", 0)) > 0:
			var bp: int = int(rc.get("best_pos", 0))
			rec_t = "내 기록 · %d회 출전 · 최고 %s · 우승 %d · 최고 랩 %s" % [int(rc["races"]), ("P%d" % bp) if bp > 0 else "-", int(rc.get("wins", 0)), REC.fmt_lap(float(rc.get("best_lap", 0.0)))]
		_txt(lv, rec_t, 14)
	_txt(c3, "%s · %s · 강우 확률 [color=#3b82f6]%d%%[/color] · %d랩\n[color=#8b98a5]%s[/color]" % [nc["dir"], nc["desc"], int(float(nc["rain"]) * 100), cr.race_laps(), nc["setupHint"]])
	if cr.is_wec():
		_txt(c3, "[color=#8b98a5]%d시간 레이스 압축%s · 내 클래스 %s · %s[/color]" % [int(nc.get("hours", 6)), " · [color=#ffc53d]르망 24시: 포인트 2배[/color]" if cr.next_circuit() == "lemans" else "", {"HY": "하이퍼카", "P2": "LMP2", "P3": "LMP3", "GT": "LMGT3"}.get(cr.my_class(), cr.my_class()), _min_drive_txt()], 13)
	# 스폰서 미션 약속은 메인에서 빼고 '스폰서' 탭에만 둔다 (메인 화면 간결하게)
	var cal := ""
	var cal_arr: Array = cr.calendar()
	for ci in cal_arr.size():
		var nm: String = DB.circuits[cal_arr[ci]]["name"]
		if ci < cr.round_idx():
			cal += "[color=#5d6674]✓%s[/color]  " % nm
		elif ci == cr.round_idx():
			cal += "[color=#ffc53d][b]R%d %s[/b][/color]  " % [ci + 1, nm]
		else:
			cal += "[color=#8b98a5]%d %s[/color]  " % [ci + 1, nm]
	_txt(c3, cal, 13)
	# 재무 + 뉴스
	var bot = K.hbox(10)
	_body.add_child(bot)
	_finance(bot)
	var c5 = K.card(bot, "커리어 뉴스")
	var nt := ""
	var n := 0
	for s in h["news"]:
		n += 1
		if n > 9:
			break
		nt += "• %s\n" % s
	_txt(c5, nt, 13)


func _on_event(i) -> void:
	cr.resolve_event(int(i))
	refresh()


func _min_drive_txt() -> String:
	var md: Variant = CS.WEC_MIN_DRIVE.get(str(cr.tier())) if cr.is_spec_tier() else null
	if md == null:
		return "최소 주행 규정 없음"
	return "%s 드라이버 최소 %d%% 주행 (미달 시 60초)" % [{"B": "브론즈", "S": "실버"}[md["grade"]], int(float(md["pct"]) * 100)]


func _mission_seg(parent: Control) -> void:
	var items: Array = [["none", "약속 안 함"]]
	for k in ["both_finish", "double_p8", "podium_one"]:
		items.append([k, "%s (+%.2fM / 실패 평판 -%d%%)" % [MISSION_KO[k], cr.mission_reward(k), int(CS.MISSION_PEN[k] * 100)]])
	var col = K.vbox(4)
	parent.add_child(col)
	var grp = ButtonGroup.new()
	for it in items:
		var b = K.btn(it[1], 14)
		b.toggle_mode = true
		b.button_group = grp
		b.button_pressed = _h()["mission"] == it[0]
		b.pressed.connect(_on_mission.bind(it[0]))
		col.add_child(b)


func _on_mission(k) -> void:
	cr.set_mission(k)
	_act(true)


func _finance(parent: Control) -> void:
	var L: Dictionary = _h()["ledger"]
	var inc: float = L["owner"] + L["spon"] + L.get("pay", 0.0) + L["prize"] + L["mission"]
	var out: float = L["ops"] + L["repair"] + L["rnd"] + L["fac"] + L["salary"] + L["overhead"] + L["staff"]
	var c = K.card(parent, "시즌 %d 재무 (수입 %.2f · 지출 %.2f)" % [int(_h()["season"]), inc, out])
	_txt(c, "[color=#22c55e]수입[/color]  오너 %.2f · 스폰서 %.2f · 페이 드라이버 %.2f · 상금 %.2f · 미션 %.2f\n[color=#ef4444]캡 포함[/color]  운영 %.2f · R&D %.2f · 설비 감가 %.2f · 수리 %.2f\n[color=#8b98a5]캡 제외[/color]  연봉 %.2f · 간접비 %.2f · 인력 영입 %.2f\n시즌 종료 상금 예상 (현재 P%d): [color=#22c55e]%.2fM[/color]" % [
		L["owner"], L["spon"], L.get("pay", 0.0), L["prize"], L["mission"], L["ops"], L["rnd"], L["fac"], L["repair"], L["salary"], L["overhead"], L["staff"], cr.my_rank_now(), cr.prize_for(cr.my_rank_now())], 13)
	var cap_txt := "코스트캡 감사: 5%% 미만 초과는 [b]경미한 위반[/b](초과액 2배 벌금), 5%% 이상은 [b]중대한 위반[/b](3배 벌금·다음 시즌 캡 감액·풍동 10%% 삭감·평판 하락). 남은 캡은 최대 %.2fM 이월." % (float(cr.tier_meta()["cap"]) * float(cr.D["econ"]["carryPct"]))
	_txt(c, "[color=#8b98a5]%s[/color]" % cap_txt, 12)


# ═════════ 개발 ═════════
func _tab_rnd() -> void:
	var h := _h()
	var c0 = K.card(_body, "개발 환경 · 규정 주기 %d/%d년차" % [cr.reg_year(), int(cr.D["econ"]["regCycle"])])
	if cr.is_wec() and not cr.is_spec_tier():
		_txt(c0, "하이퍼카는 호몰로게이션으로 차가 고정돼서 성능 개발(공력·파워트레인·섀시)에 [b]EVO 조커[/b]가 필요해요. 남은 조커 [color=#ffc53d][b]%d/%d[/b][/color]. 신뢰성 개선은 조커 없이 가능해요. [b]BoP가 성능 이점의 40%%를 상쇄[/b]하고, 성적에 따라 매 경기 조정돼요 (현재 내 팀 BoP %+.2f%%)." % [int(h.get("jokers", 0)), int(cr.D["econ"]["jokersPerCycle"]), float(h.get("wec_bop", 0.0)) * 100])
	elif cr.is_spec_tier():
		_txt(c0, "%s는 [b]공통 섀시·엔진[/b]을 쓰는 스펙 시리즈라 공력·파워트레인 개발이 금지돼요. 섀시와 신뢰성만 개선할 수 있고, 여기서 쌓은 [b]설비와 인력은 상위 리그로 그대로 이어져요.[/b]" % cr.tier_meta()["short"])
	else:
		_txt(c0, "공력 개발 효율은 [b]ATR(공력 시험 제한)[/b]을 따라요. 기준 순위 P%d → 풍동·CFD 허용량 [color=#ffc53d][b]%d%%[/b][/color]%s. 시즌 전반은 지난 시즌 순위, 후반은 현재 순위로 정해요. %s" % [
			cr.atr_rank(), int(round(cr.atr_mult() * 100)), (" (코스트캡 제재 -%d%% 포함)" % int(float(h["atr_pen"]) * 100)) if float(h["atr_pen"]) > 0 else "",
			"워크스 팀이라 파워유닛을 직접 개발해요." if cr.is_works() else "커스터머 팀은 파워유닛 개발 효율이 40%예요."])
	if cr.reg_year() == int(cr.D["econ"]["regCycle"]) and not cr.is_spec_tier():
		_txt(c0, "[color=#a855f7]📜 다음 시즌 신규 기술 규정.[/color] 현행 차량 개발은 30%만 이어지고, 차세대 선행 개발은 100% 이어져요.")
		K.seg(c0, [["cur", "현행 차량 개발"], ["next", "차세대 차량 선행 개발"]], h["dev_target"], _on_dev_target, 14)
	_txt(c0, "연구 철학 (서킷 상성 보너스)", 14)
	K.seg(c0, [["downforce", "고다운포스 특화"], ["balanced", "올라운더"], ["lowdrag", "저항 저감 (직선)"]], h["rnd_branch"], _on_branch, 14)
	_engine_card()
	var proj: float = cr.projected_spend()
	var c1 = K.card(_body, "개발 프로젝트 (착수 즉시 비용이 코스트캡에 반영, 정해진 경기 후 투입)")
	for k in CS.DEV_AREAS:
		var pj: Variant = h["proj"][k]
		var lock: String = cr.proj_lock(k)
		var status := ""
		if pj != null:
			status = "[color=#ffc53d]🛠 %s%s 진행 중 · 투입까지 %d경기[/color]" % [cr.D["dev"][pj["size"]]["ko"], " (차세대)" if pj["next"] else "", maxi(0, int(pj["due"]) - int(h["race_count"]))]
		elif lock != "":
			status = "[color=#ef4444]🔒 %s[/color]" % lock
		else:
			var rs: Array = cr.dev_range(k, "s")
			var rl: Array = cr.dev_range(k, "l")
			status = "예상 효과 · 소형(%d경기) +%.1f~%.1f%% / 대형(%d경기) +%.1f~%.1f%%" % [cr.dev_lead("s"), rs[0] * 100, rs[1] * 100, cr.dev_lead("l"), rl[0] * 100, rl[1] * 100]
		var nxt: float = h["dev_next"][k]
		var fk: String = cr.D["dev"]["fac"][k]
		var txt := "[b]%s[/b] · 누적 [color=#22c55e]+%.1f%%[/color]%s\n%s\n[color=#8b98a5]%s Lv.%d · 평균 상관도 %d%%[/color]" % [cr.D["dev_ko_full"][k], float(h["dev"][k]) * 100, (" [color=#a855f7]차세대 +%.1f%%[/color]" % (nxt * 100)) if nxt > 0 else "", status, cr.D["fac_ko"][fk], int(h["base"][fk]), int(round(cr.corr_mean(k) * 100))]
		var btns: Array = []
		for sz in ["s", "l"]:
			var cost: float = cr.dev_cost(sz)
			var ok: bool = cr.can_start_project(k, sz)
			var over := proj + cost > float(h["cost_cap_limit"]) + 0.000001
			var lab := "%s %.2fM%s" % ["소형" if sz == "s" else "대형", cost, " ⚠캡" if over else ""]
			btns.append(K.sbtn(lab, _on_dev.bind(sz, k), ok, K.BAD if over else K.AMBER))
		K.row(c1, txt, btns, 14)


func _engine_card() -> void:
	var h := _h()
	var c = K.card(_body, "파워유닛 공급")
	if cr.is_wec():
		var eng: Dictionary = DB.wec["engines"].get(h["engine_supplier"], {"pwr": 0.88, "eff": 1.0})
		_txt(c, "현재 [b]%s[/b] · 출력 %d · 연비 %d%%" % [h["engine_supplier"], int(float(eng["pwr"]) * 100), int(float(eng["eff"]) * 100)])
		if h["entry"] == "create":
			var hb2 = K.hbox(4)
			c.add_child(hb2)
			for pk in CS.WEC_PKGS:
				var b2 = K.btn(CS.WEC_PKGS[pk], 13)
				b2.toggle_mode = true
				b2.button_pressed = pk == h["engine_supplier"]
				b2.disabled = not cr.is_preseason()
				b2.pressed.connect(_on_pkg.bind(pk))
				hb2.add_child(b2)
			_txt(c, "[color=#8b98a5]하이퍼카 패키지는 시즌 개막 전에만 바꿀 수 있어요.[/color]", 13)
		else:
			_txt(c, "[color=#8b98a5]제조사 워크스 팀은 자사 파워유닛으로 호몰로게이션이 고정돼요.[/color]", 13)
		return
	if cr.is_spec_tier():
		_txt(c, "스펙 시리즈 공통 엔진 사용 중 (성능 %d)" % int(cr.spec_engine() * 100))
		return
	if cr.is_works():
		_txt(c, "[b]%s[/b]는 자체 파워유닛을 만드는 워크스 팀이라 다른 엔진을 쓸 수 없어요." % h["team_name"])
		return
	var pre: bool = cr.is_preseason()
	_txt(c, "현재 [b]%s[/b] · %s" % [h["engine_supplier"], "🟢 시즌 개막 전: 교체 가능 (비용 50%는 코스트캡 반영)" if pre else "🔒 시즌 중에는 교체 불가"])
	var hb = K.hbox(4)
	c.add_child(hb)
	var reasons := ""
	for e in CS.ENGINE_CHOICES:
		var p: Dictionary = h["politics"][e]
		var b = K.btn(e + (" 🚫" if p["blocked"] else ""), 14)
		b.toggle_mode = true
		b.button_pressed = e == h["engine_supplier"]
		b.disabled = not pre or p["blocked"]
		b.pressed.connect(_on_engine.bind(e))
		hb.add_child(b)
		reasons += "[color=%s]• %s: %s (성능 %d)[/color]\n" % ["#ef4444" if p["blocked"] else "#8b98a5", e, p["reason"], int(float(h["engines"].get(e, 0.86)) * 100)]
	_txt(c, reasons, 13)


func _on_pkg(pk) -> void:
	_act(cr.change_package(pk))


func _on_dev_target(v) -> void:
	_h()["dev_target"] = v
	_act(true)


func _on_branch(v) -> void:
	_h()["rnd_branch"] = v
	_act(true)


func _on_engine(e) -> void:
	_act(cr.change_engine(e))


func _on_dev(sz, k) -> void:
	_act(cr.start_project(k, sz))


# ═════════ 설비 ═════════
func _tab_base() -> void:
	var h := _h()
	var c0 = K.card(_body, "본부 지역 (연구 특화는 맞바꿈)")
	var items: Array = []
	for k in REGION_KO:
		items.append([k, REGION_KO[k]])
	K.seg(c0, items, h["region"], _on_region, 14)
	_txt(c0, "[color=#8b98a5]영국 공력 +1.0%/엔진·섀시 -0.4% · 이탈리아 엔진 +1.0%/공력·섀시 -0.4% · 독일 섀시·내구 +0.6%/공력·엔진 -0.4% · 일본 섀시 +0.6%·엔진 +0.3%/공력 -0.3%·내구 -0.4%[/color]", 13)
	var depr_next := 0.0
	for d in h["depr"]:
		if int(d["left"]) > 0:
			depr_next += float(d["per"])
	var c1 = K.card(_body, "설비 (최대 Lv.5)")
	_txt(c1, "[color=#8b98a5]설비는 개발 효율과 [b]규정 변경 때 새 차의 출발점[/b]을 정해요. 현금은 착공 때 전액 나가고, 코스트캡에는 %d시즌에 나눠 감가상각돼요. 다음 시즌 캡에 이미 잡힌 감가상각: [b]%.2fM[/b][/color]" % [int(cr.D["econ"]["deprSeasons"]), depr_next], 13)
	var desc := {
		"wind": ["풍동", "공력 개발 상관도↑·편차↓ · 공력 +0.6%/Lv"],
		"bench": ["파워트레인 다이나모", "파워트레인·신뢰성 개발 상관도↑ · 엔진 +0.6%/Lv · 신뢰성 +0.3%/Lv"],
		"rig": ["섀시 리그", "섀시 개발 상관도↑ · 섀시 +0.6%/Lv"],
		"sim": ["드라이버 시뮬레이터", "모든 개발 상관도 +2.5%/Lv · 유망주 성장 가속"],
		"factory": ["카본 복합재 공장", "Lv3·Lv5에서 개발 기간 -1경기 · 사고 수리비 -10%/Lv"],
		"pit": ["피트 크루 훈련센터", "피트 정차 시간 단축 (Lv당 약 0.2초)"],
	}
	var proj: float = cr.projected_spend()
	var ds := int(cr.D["econ"]["deprSeasons"])
	for k in CS.FAC_KEYS:
		var lv := int(h["base"][k])
		var cost: float = cr.fac_cost(k)
		var per := cost / ds
		var over := proj + per > float(h["cost_cap_limit"]) + 0.000001
		var ok := lv < 5 and float(h["cash"]) >= cost
		var lab := "MAX" if lv >= 5 else ("확장 %.1fM · 캡 %.2f×%d%s" % [cost, per, ds, " ⚠" if over else ""])
		K.row(c1, "[b]%s[/b] Lv.%d/5\n[color=#8b98a5]%s[/color]" % [desc[k][0], lv, desc[k][1]], [K.sbtn(lab, _on_fac.bind(k), ok, K.BAD if over else K.GOOD)], 14)


func _on_region(v) -> void:
	_h()["region"] = v
	_act(true)


func _on_fac(k) -> void:
	_act(cr.build_facility(k))


# ═════════ 인력 ═════════
func _tab_staff() -> void:
	var h := _h()
	var pre: bool = cr.is_preseason()
	if cr.is_wec():
		_staff_wec()
		return
	_txt(_body, ("[color=#22c55e]🟢 이적 시장 열림 (시즌 개막 전)[/color] — 자금·평판에 맞춰 엔지니어와 드라이버를 영입하세요." if pre else "[color=#ffc53d]🔒 시즌 중: 외부 영입은 다음 시즌 개막 전에만 가능해요. 리저브·유망주 교체는 언제든 가능해요.[/color]"), 14)
	var c1 = K.card(_body, "주전 드라이버")
	for slot in 2:
		var d: Dictionary = cr.my_driver(slot)
		var age := int(d.get("age", 25))
		var tag := ""
		if age >= 35:
			tag = " [color=#ef4444][은퇴 임박][/color]"
		elif age <= 24:
			tag = " [color=#22c55e][성장 중][/color]"
		var pay := ""
		if h["pay_drivers"].has(str(slot)):
			pay = " · [color=#22c55e]페이 드라이버 +%.2fM/시즌[/color]" % float(h["pay_drivers"][str(slot)])
		K.row(c1, "#%d [b]%s[/b] (%d세)%s\n[color=#8b98a5]속도 %d · 일관 %d · 타이어 %d · 우천 %d · 연봉 %.1fM%s[/color]" % [slot + 1, d["name"], age, tag, int(float(d["speed"]) * 100), int(float(d["cons"]) * 100), int(float(d["tyreMgmt"]) * 100), int(float(d["wet"]) * 100), cr.driver_salary(d), pay], [], 14)
	var rv: Dictionary = h["reserve"]
	K.row(c1, "리저브 [b]%s[/b] (%d세)\n[color=#8b98a5]속도 %d · 일관 %d · 타이어 %d · 추가 비용 없음[/color]" % [rv["name"], int(rv.get("age", 22)), int(float(rv["speed"]) * 100), int(float(rv["cons"]) * 100), int(float(rv["tyre"]) * 100)],
		[K.sbtn("#1과 교대", _on_swap.bind(0)), K.sbtn("#2와 교대", _on_swap.bind(1))], 14)
	# 엔지니어
	var c2 = K.card(_body, "수석 엔지니어 (최고 연봉 3인 → 코스트캡 제외)")
	var ce: Dictionary = h["chief"]
	_txt(c2, "공력 [b]%s[/b] [%s] · 파워 [b]%s[/b] [%s] · 섀시 [b]%s[/b] [%s]\n[color=#8b98a5]담당 부문 개발 효과 S급 +12%%, A급 +6%%. 세 부문 모두 A·S급이면 전 부문 +0.5%% 시너지.[/color]" % [ce["aero"]["name"], ce["aero"]["tier"], ce["power"]["name"], ce["power"]["tier"], ce["chassis"]["name"], ce["chassis"]["tier"]], 14)
	for i in h["eng_pool"].size():
		var en: Dictionary = h["eng_pool"][i]
		var lab := "%.1fM 영입" % float(en["cost"])
		if en["hired"]:
			lab = "재직 중"
		elif not pre:
			lab = "시즌 전"
		elif float(h["pop"]) < float(en["reqPop"]):
			lab = "평판 %d%% 필요" % int(float(en["reqPop"]) * 100)
		elif float(h["cash"]) < float(en["cost"]):
			lab = "자금 부족"
		K.row(c2, "[%s] [b]%s[/b] %s\n[color=#8b98a5]공력 +%.1f%% · 엔진 +%.1f%% · 섀시 +%.1f%% · 내구 +%.1f%%[/color]" % [en["tier"], en["name"], en["deptKo"], float(en["aeroMod"]) * 100, float(en["engMod"]) * 100, float(en["tyreMod"]) * 100, float(en["relMod"]) * 100],
			[K.sbtn(lab, _on_hire_eng.bind(i), cr.can_hire_engineer(i), K.GOOD)], 13)
	# FA
	var c3 = K.card(_body, "FA 드라이버 이적 시장")
	for i in h["market"].size():
		var m: Dictionary = h["market"][i]
		var ok: bool = cr.can_hire_driver(i)
		var need: float = cr.drv_req_pop(m)
		var lab2 := "평판 %d%%" % int(need * 100) if float(h["pop"]) < need else ("시즌 전" if not pre else "")
		K.row(c3, "[b]%s[/b] (%d세)\n[color=#8b98a5]속도 %d · 일관 %d · 타이어 %d · 연봉 %.1fM · 바이아웃 %.1fM[/color]" % [m["name"], int(m.get("age", 24)), int(float(m["speed"]) * 100), int(float(m["cons"]) * 100), int(float(m["tyre"]) * 100), float(m["salary"]), float(m["buyout"])],
			[K.sbtn(lab2 if lab2 != "" else "#1 영입", _on_hire_drv.bind(0, i), ok), K.sbtn(lab2 if lab2 != "" else "#2 영입", _on_hire_drv.bind(1, i), ok)], 13)
	# 페이 드라이버
	if not h["pay_pool"].is_empty():
		var c4 = K.card(_body, "페이 드라이버 (실력은 낮지만 후원금을 가져와요 · 1시즌)")
		for i in h["pay_pool"].size():
			var p: Dictionary = h["pay_pool"][i]
			K.row(c4, "[b]%s[/b] (%d세)\n[color=#8b98a5]속도 %d · 일관 %d · 타이어 %d · 후원금 [color=#22c55e]+%.2fM/시즌[/color][/color]" % [p["name"], int(p["age"]), int(float(p["speed"]) * 100), int(float(p["cons"]) * 100), int(float(p["tyre"]) * 100), cr.pay_driver_money(p)],
				[K.sbtn("#1 계약", _on_pay.bind(0, i), pre), K.sbtn("#2 계약", _on_pay.bind(1, i), pre)], 13)
	# 아카데미
	var c5 = K.card(_body, "유망주 아카데미 (정원 4명)")
	K.row(c5, "[color=#8b98a5]은퇴한 주전 자리는 가장 성장한 유망주가 자동으로 이어받아요. 훈련은 라운드당 1회.[/color]", [K.sbtn("신규 발굴 1.2M", _on_scout, float(h["cash"]) >= 1.2 and h["juniors"].size() < 4)], 13)
	for i in h["juniors"].size():
		var j: Dictionary = h["juniors"][i]
		var trained: bool = int(j.get("last_train", -1)) == int(h["race_count"])
		K.row(c5, "[b]%s[/b] (%d세)\n[color=#8b98a5]현재 %d / 잠재력 %d · 이적 가치 %.1fM[/color]" % [j["name"], int(j["age"]), int(float(j["cur"]) * 100), int(float(j["pot"]) * 100), float(j["value"])],
			[K.sbtn("훈련 완료" if trained else "훈련 0.8M", _on_train.bind(i), cr.can_train_junior(i)), K.sbtn("#1 승격", _on_promote.bind(0, i), true, K.PURPLE), K.sbtn("#2 승격", _on_promote.bind(1, i), true, K.PURPLE), K.sbtn("리저브", _on_jres.bind(i), true, K.GOOD), K.sbtn("판매", _on_sell.bind(i))], 13)


func _staff_wec() -> void:
	var h := _h()
	var c1 = K.card(_body, "드라이버 라인업 (차당 3명 · 등급제)")
	_txt(c1, "[color=#8b98a5]등급: 플래티넘 > 골드 > 실버 > 브론즈. %s. 한 드라이버가 세 스틴트 이상 연속으로 타면 피로로 실수가 늘어요. 맨 위 드라이버가 선발로 출발해요.[/color]" % _min_drive_txt(), 13)
	for slot in 2:
		_txt(c1, "[b]#%d 차[/b]" % (slot + 1), 15)
		var crew: Array = cr.my_crew(slot)
		for i in crew.size():
			var d: Dictionary = crew[i]
			var sel: bool = wec_target[0] == slot and wec_target[1] == i
			var btns: Array = [
				K.sbtn("선발" if i > 0 else "선발 ✓", _on_wec_starter.bind(slot, i), i > 0),
				K.sbtn("↔ #%d" % (2 - slot), _on_wec_swap.bind(i), true),
				K.sbtn("교체 대상 ✓" if sel else "교체 대상", _on_wec_target.bind(slot, i), not sel, K.AMBER),
			]
			K.row(c1, "%s%s [b]%s[/b] (%d세)\n[color=#8b98a5]속도 %d · 일관 %d · 타이어 %d · 우천 %d · 연봉 %.2fM[/color]" % ["▶ " if sel else "", _grade_tag(d.get("grade", "-")), d["name"], int(d.get("age", 28)), int(float(d["speed"]) * 100), int(float(d.get("cons", 0.75)) * 100), int(float(d.get("tyreMgmt", 0.75)) * 100), int(float(d.get("wet", 0.75)) * 100), cr.driver_salary(d)], btns, 13)
	# FA 시장
	var tgt: Array = cr.my_crew(wec_target[0])
	var tname: String = tgt[wec_target[1]]["name"] if wec_target[1] < tgt.size() else "-"
	var cm = K.card(_body, "드라이버 FA 시장 → #%d 차 %s 자리에 영입" % [wec_target[0] + 1, tname], K.AMBER)
	_txt(cm, "[color=#8b98a5]위 라인업에서 '교체 대상'을 고른 뒤 영입하세요. 내보낸 드라이버는 FA 시장으로 가요. 시장 명단은 시즌 개막 때 새로 바뀌어요. 연봉은 차마다 가장 비싼 드라이버 기준으로 나가요.[/color]", 12)
	var mk: Array = cr.wec_market()
	for i in mk.size():
		var fa: Dictionary = mk[i]
		var why: String = cr.wec_hire_block(i, wec_target[0], wec_target[1])
		var lab: String = ("%.2fM 영입" % float(fa["cost"])) if why == "" else why
		K.row(cm, "%s [b]%s[/b] (%d세)\n[color=#8b98a5]속도 %d · 일관 %d · 타이어 %d · 우천 %d · 연봉 %.2fM[/color]" % [_grade_tag(fa["grade"]), fa["name"], int(fa["age"]), int(float(fa["speed"]) * 100), int(float(fa["cons"]) * 100), int(float(fa["tyreMgmt"]) * 100), int(float(fa["wet"]) * 100), float(fa["salary"])],
			[K.sbtn(lab, _on_wec_hire.bind(i), why == "", K.GOOD)], 13)
	var c2 = K.card(_body, "수석 엔지니어")
	var ce: Dictionary = h["chief"]
	_txt(c2, "공력 [b]%s[/b] [%s] · 파워 [b]%s[/b] [%s] · 섀시 [b]%s[/b] [%s]" % [ce["aero"]["name"], ce["aero"]["tier"], ce["power"]["name"], ce["power"]["tier"], ce["chassis"]["name"], ce["chassis"]["tier"]], 14)
	var pre: bool = cr.is_preseason()
	for i in h["eng_pool"].size():
		var en: Dictionary = h["eng_pool"][i]
		var lab := "%.1fM 영입" % float(en["cost"])
		if en["hired"]:
			lab = "재직 중"
		elif not pre:
			lab = "시즌 전"
		elif float(h["pop"]) < float(en["reqPop"]):
			lab = "평판 %d%% 필요" % int(float(en["reqPop"]) * 100)
		K.row(c2, "[%s] [b]%s[/b] %s" % [en["tier"], en["name"], en["deptKo"]], [K.sbtn(lab, _on_hire_eng.bind(i), cr.can_hire_engineer(i), K.GOOD)], 13)


func _grade_tag(g: String) -> String:
	var gc: String = {"P": "#a855f7", "G": "#ffc53d", "S": "#cbd5e1", "B": "#c2410c"}.get(g, "#8b98a5")
	return "[color=%s][%s][/color]" % [gc, g]


func _on_wec_starter(slot, i) -> void:
	_act(cr.wec_set_starter(slot, i))


func _on_wec_swap(i) -> void:
	_act(cr.wec_swap_cars(i))


func _on_wec_target(slot, i) -> void:
	wec_target = [slot, i]
	refresh()


func _on_wec_hire(i) -> void:
	_act(cr.hire_wec(i, wec_target[0], wec_target[1]))


func _on_swap(slot) -> void:
	_act(cr.swap_reserve(slot))


func _on_hire_eng(i) -> void:
	_act(cr.hire_engineer(i))


func _on_hire_drv(slot, i) -> void:
	_act(cr.hire_driver(i, slot))


func _on_pay(slot, i) -> void:
	_act(cr.sign_pay_driver(i, slot))


func _on_scout() -> void:
	_act(cr.scout_junior())


func _on_train(i) -> void:
	_act(cr.train_junior(i))


func _on_promote(slot, i) -> void:
	_act(cr.promote_junior(i, slot))


func _on_jres(i) -> void:
	_act(cr.junior_to_reserve(i))


func _on_sell(i) -> void:
	_act(cr.sell_junior(i))


# ═════════ 스폰서 ═════════
func _tab_spon() -> void:
	var h := _h()
	var cl: int = cr.cal_len()
	var c0 = K.card(_body, "스폰서 계약 (카테고리당 1곳)")
	_txt(c0, "[color=#8b98a5][b]안정형[/b]은 고정 후원금 + 포디움 보너스, [b]성과연동형[/b]은 기본금이 낮은 대신 포인트마다 추가금, [b]단기 고액[/b]은 1시즌 높은 금액 대신 홍보 일정이 많아요. 성과 조항(시즌 순위)을 못 지키면 안정형은 다음 시즌 30%% 삭감, 성과연동형은 해지돼요.\n스폰서 홍보 행사 때문에 연습 주행이 차당 [b]%d랩[/b] 줄어요.[/color]" % cr.duty_laps(), 13)
	for cat in CS.SPON_CATS:
		var cd: Dictionary = CS.SPON_CATS[cat]
		var c: Variant = cr.contract_of(cat)
		if c != null:
			var money := "시즌 %.2fM" % cr.season_sponsor_value(c)
			if float(c["rate"]) > 0:
				money += " + 포인트당 %.3fM" % (float(c["rate"]) * cr.tier_scale())
			if float(c["bonus"]) > 0:
				money += " · 포디움 경기마다 +%.2fM" % (float(c["bonus"]) * cr.tier_scale() / cl)
			var kpi := int(c.get("kpi", 0))
			K.row(c0, "[color=#ffc53d][%s][/color] [b]%s[/b] · %s%s · 남은 %d시즌\n[color=#8b98a5]%s · 성과 조항 %s · 홍보 %d랩 · 만족도 %d%%[/color]" % [cd["ko"], c["name"], cr.kind_ko(c["kind"]), " [color=#ef4444](30% 삭감 중)[/color]" if c["reduced"] else "", int(c["seasons_left"]), money, ("시즌 P%d 이내" % kpi) if kpi > 0 else "없음", int(c["duty"]), int(float(c["sat"]) * 100)],
				[K.sbtn("해지 (위약금 1M)", _on_terminate.bind(cat), float(h["cash"]) >= 1.0, K.BAD)], 13)
		elif not cr.spon_eligible(cat):
			_txt(c0, "[color=#5d6674][%s] 비어 있음 · 자격 조건: 평판 %d%% 이상%s[/color]" % [cd["ko"], int(float(cd["pop"]) * 100), (" & 기준 순위 P%d 이내" % int(cd["rank"])) if int(cd["rank"]) < 99 else ""], 13)
		else:
			_txt(c0, "[color=#8b98a5][%s] 비어 있음 · 아래 제안 중에서 고르세요[/color]" % cd["ko"], 13)
	if not h["offers"].is_empty():
		var c1 = K.card(_body, "들어온 제안" + ("" if cr.is_preseason() else " (시즌 중에도 빈 카테고리는 계약 가능)"), K.AMBER)
		for i in h["offers"].size():
			var o: Dictionary = h["offers"][i]
			var money2 := "시즌 %.2fM" % (float(o["base"]) * cr.tier_scale())
			if float(o["rate"]) > 0:
				money2 += " + 포인트당 %.3fM" % (float(o["rate"]) * cr.tier_scale())
			if float(o["bonus"]) > 0:
				money2 += " · 포디움 +%.2fM/경기" % (float(o["bonus"]) * cr.tier_scale() / cl)
			var kpi2 := int(o.get("kpi", 0))
			K.row(c1, "[color=#ffc53d][%s][/color] [b]%s[/b]%s · %s · %d시즌\n[color=#8b98a5]%s · 성과 조항 %s · 홍보 %d랩[/color]" % [CS.SPON_CATS[o["cat"]]["ko"], o["name"], " [color=#22c55e](갱신 제안)[/color]" if o.get("renewal", false) else "", cr.kind_ko(o["kind"]), int(o["seasons"]), money2, ("시즌 P%d 이내" % kpi2) if kpi2 > 0 else "없음", int(o["duty"])],
				[K.sbtn("계약", _on_sign.bind(i), cr.contract_of(o["cat"]) == null, K.GOOD)], 13)
	var c2 = K.card(_body, "이번 레이스 미션 약속")
	_mission_seg(c2)


func _on_sign(i) -> void:
	_act(cr.sign_offer(i))


func _on_terminate(cat) -> void:
	_act(cr.terminate_contract(cat))


# ═════════ 리그 ═════════
func _tab_league() -> void:
	var h := _h()
	var c0 = K.card(_body, "리그 디비전")
	if h["entry"] != "create":
		_txt(c0, "공식 컨스트럭터 팀(%s)은 1부 월드 챔피언십에 계속 참가해요. 하위 리그 승강은 신규 팀 창단 모드에서 진행돼요." % h["team_name"])
	else:
		var steps := ""
		for t in [1, 2, 3]:
			var m: Dictionary = cr.tier_meta(t)
			steps += ("[color=#ffc53d][b]▶ %s[/b][/color]" if t == cr.tier() else "[color=#8b98a5]%s[/color]") % ("%s (캡 %.0fM)" % [m["short"], float(m["cap"])])
			if t < 3:
				steps += "  ›  "
		_txt(c0, steps, 16)
		var tm: Dictionary = cr.tier_meta()
		_txt(c0, "[color=#8b98a5]하위 리그에서 시즌 P1이면 [b]자동 승격(+2.5M)[/b], P%d 이내 또는 %d점 이상(혹은 평판 65%%)이면 시즌 개막 전에 라이선스 비용 %.1fM을 내고 승격할 수 있어요.[/color]" % [int(tm["reqRank"]), int(tm["reqPts"]), float(tm["fee"])], 13)
		if cr.tier() < 3:
			var lab := "상위 리그 승격 신청 (%.1fM)" % float(tm["fee"])
			if not (h["promo_qualified"] or float(h["pop"]) >= 0.65):
				lab = "승격 조건 미달"
			elif not cr.is_preseason():
				lab = "승격은 시즌 개막 전에만"
			var b = K.btn(lab, 16, _on_tier_up)
			b.disabled = not cr.can_tier_up()
			c0.add_child(b)
	# 진행 중인 시즌 드라이버 순위
	var cd = K.card(_body, "시즌 %d 드라이버 순위" % int(h["season"]))
	var td := ""
	var di := 0
	for r in cr.driver_standings():
		di += 1
		if di > 10:
			break
		td += "P%-2d [color=%s]■[/color] [color=%s]%s[/color] [color=#8b98a5]%s[/color]  [b]%d[/b]\n" % [di, r["color"], "#ffc53d" if r["mine"] else "#e6edf3", r["name"], r["team"], int(r["pts"])]
	_txt(cd, td if td != "" else "[color=#8b98a5]아직 레이스가 없어요.[/color]", 14)
	var c1 = K.card(_body, "지난 시즌 기록")
	var t2 := ""
	for s in h["season_log"]:
		t2 += "시즌 %d · %s · P%d · %d점 · 우승 %d · 자금 %.1fM · 캡 %.1f/%.1fM\n" % [int(s["season"]), cr.tier_meta(int(s.get("tier", 3)))["short"], int(s["rank"]), int(s.get("pts", 0)), int(s.get("wins", 0)), float(s["cash"]), float(s["spent"]), float(s["cap"])]
	_txt(c1, t2 if t2 != "" else "[color=#8b98a5]아직 끝난 시즌이 없어요.[/color]", 14)
	if h.has("last_season"):
		c1.add_child(K.btn("🏆 지난 시즌 결산 · 트로피 진열장 보기", 15, _on_season))


func _on_season() -> void:
	go_season.emit()


func _on_tier_up() -> void:
	_act(cr.tier_up())
