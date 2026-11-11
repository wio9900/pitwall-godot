extends Control

signal cue(name: String) # 효과음 신호 (main 이 sfx 로 연결)
## 탑뷰 레이스 화면. 시뮬레이션 상태(sim)를 읽어서 그리기만 한다 — 규칙 로직은 없다.
## 연출을 바꾸고 싶으면 이 파일만 고치면 된다.

const BG := Color("#10161d")
const BG_NIGHT := Color("#0a0d12")
const RUNOFF := Color("#1a232d")
const ASPHALT := Color("#3a4250")
const ASPHALT_IN := Color("#272e39")
const WET_TINT := Color(0.29, 0.64, 1.0)
const EDGE := Color("#d7dde5")
const KERB_R := Color("#e8394a")
const KERB_W := Color("#e9edf2")
const AMBER := Color("#ffc53d")
const GREEN := Color("#3ecf8e")
const PURPLE := Color("#a855f7")
const LABEL := Color("#7d8796")
const TRACK_W := 11.0 # 트랙 폭 (트랙 좌표 단위)
const BANNER_H := 34.0 # 화면 아래 안내 띠 높이
const SPC := 20       # 서킷 제어점 하나당 샘플 수 (track.gd 와 같게)

var sim: Variant = null
var follow_slot := -1        # -1 = 전체 화면, 0/1 = 내 차 추적
var sel_slot := 0            # 강조 링을 굵게 그릴 내 차
var lights := -1             # 출발 신호: -1 숨김, 0~5 점등 개수
var lights_out_t := -10.0    # 소등 시각(실시간) — GO! 표시용
var banner_text := ""
var banner_kind := ""
var banner_t := -10.0
## 연습·예선 화면용: 차 한 대만 그린다 {car, dist(트랙 거리)}. null 이면 레이스 모드.
var solo: Variant = null

var _cam_center := Vector2.ZERO
var _cam_zoom := 1.0
var _s := 1.0
var _off := Vector2.ZERO
var _now := 0.0
var _smooth := {}      # car id → {p, a}
var _pit_seen := {}    # car id → 피트레인 진입 시각(시뮬레이션)
var _popups: Array = [] # {id, text, col, t}
var _last_pos := {}
var _last_radio := {}
var _radio_shown := {}
var _last_fastest := -1
var _last_log: Variant = null
var _stop_t := {}      # car id → 차고 정차 시작 시각(시뮬레이션)
var _fin_seen := {}    # car id → 체커기 받은 것 확인
var _flash := {}       # car id → 추월 강조 시작(실시간)
var _was_finishing := false


func reset() -> void:
	_smooth.clear()
	_pit_seen.clear()
	_popups.clear()
	_last_pos.clear()
	_last_radio.clear()
	_radio_shown.clear()
	_last_fastest = -1
	_last_log = null
	_stop_t.clear()
	_fin_seen.clear()
	_flash.clear()
	_was_finishing = false
	banner_text = ""
	_cam_center = Vector2.ZERO


func now() -> float:
	return _now


func _X(p: Vector2) -> Vector2:
	return p * _s + _off


func show_banner(text: String, kind: String) -> void:
	banner_text = text
	banner_kind = kind
	banner_t = _now


# ═════════ 카메라 ═════════
func _update_camera(delta: float) -> void:
	var T = sim.T
	var bb: Rect2 = T.bbox.grow(34.0)
	# 아래쪽 BANNER_H 만큼은 안내 띠 자리로 비워 둔다
	var avail := Vector2(size.x, size.y - BANNER_H)
	var fit_s: float = minf(avail.x / bb.size.x, avail.y / bb.size.y)
	var want_center: Vector2 = bb.get_center()
	var want_zoom = 1.0
	if follow_slot >= 0:
		var mc: Array = sim.my_cars()
		if follow_slot < mc.size() and mc[follow_slot].dnf == "" and _smooth.has(mc[follow_slot].id):
			want_center = _smooth[mc[follow_slot].id]["p"]
			want_zoom = 2.8
	var k = clampf(delta * (7.0 if follow_slot >= 0 else 3.5), 0.0, 1.0)
	if _cam_center == Vector2.ZERO:
		_cam_center = want_center
		_cam_zoom = want_zoom
	_cam_center = _cam_center.lerp(want_center, k)
	_cam_zoom = lerpf(_cam_zoom, want_zoom, k)
	_s = fit_s * _cam_zoom
	_off = avail / 2.0 - _cam_center * _s


# ═════════ 차량 위치: 실제 순서보다 앞서 그리지 않고, 부드럽게 보간 ═════════
func _update_cars(delta: float) -> void:
	var T = sim.T
	# 화면에서 차가 겹치지 않을 만큼의 최소 간격 (차 길이 ≈ 15px)
	var gap_d: float = maxf(T.L * 0.0045, 15.0 * _car_scale(false) / maxf(_s, 0.01))
	var last_by_cls := {} # 클래스별로 앞차보다 앞서 그리지 않기
	var targets := {}
	for c in sim.order():
		if c.dnf != "":
			continue
		if not c.started:
			# 출발 전 그리드: 화면에서 겹치지 않는 간격 + 좌우 엇갈림
			var gap: float = maxf(T.L * 0.0035, 13.0 * _car_scale(false) / maxf(_s, 0.01))
			var gd: float = -(floor(c.grid / 2.0) + 1.0) * gap * 1.25 - float(c.grid % 2) * gap * 0.55
			var dv = gd
			if c.start_t > 0.0:
				dv = gd * (1.0 - clampf(sim.clock / c.start_t, 0.0, 1.0))
			var ha: float = T.head_at_dist(dv)
			var lat: float = TRACK_W * 0.22 * (1.0 if c.grid % 2 == 0 else -1.0)
			targets[c.id] = [T.point_at_dist(dv) + Vector2(-sin(ha), cos(ha)) * lat, ha]
			continue
		if c.finished or sim.is_pitting(c):
			var pa: Array = sim.car_pos_angle(c)
			targets[c.id] = [pa[0], pa[1]]
			continue
		var dist: float = sim.car_dist(c)
		var last_d: Variant = last_by_cls.get(c.cls)
		if last_d != null and last_d - dist < T.L * 0.5:
			dist = minf(dist, last_d - gap_d)
		last_by_cls[c.cls] = dist
		targets[c.id] = [T.point_at_dist(dist), T.head_at_dist(dist)]
	var kp = clampf(delta * 18.0, 0.0, 1.0)
	var ka = clampf(delta * 14.0, 0.0, 1.0)
	for id in targets:
		var tp: Vector2 = targets[id][0]
		var ta: float = targets[id][1]
		if not _smooth.has(id) or (_smooth[id]["p"] - tp).length() > 40.0:
			_smooth[id] = {"p": tp, "a": ta}
		else:
			var s: Dictionary = _smooth[id]
			s["p"] = s["p"].lerp(tp, kp)
			s["a"] = s["a"] + wrapf(ta - s["a"], -PI, PI) * ka
	for id in _smooth.keys():
		if not targets.has(id):
			_smooth.erase(id)


# ═════════ 팝업·말풍선·배너 (sim 상태 변화를 감지만 한다) ═════════
func _update_effects() -> void:
	var ord: Array = sim.order()
	for i in ord.size():
		var c = ord[i]
		var pos = i + 1
		if c.dnf == "" and c.started and not sim.sc and _last_pos.has(c.id) and pos < _last_pos[c.id]:
			if (c.mine or pos <= 3) and _smooth.has(c.id) and not sim.is_pitting(c):
				_popups.append({"id": c.id, "text": "▲ P%d" % pos, "col": GREEN if c.mine else Color.WHITE, "t": _now})
				if c.mine:
					_flash[c.id] = _now
					cue.emit("pass")
		_last_pos[c.id] = pos
		if c.mine and c.radio != "" and _last_radio.get(c.id, "") != c.radio:
			_last_radio[c.id] = c.radio
			_radio_shown[c.id] = _now
			cue.emit("radio")
	if sim.fastest_id >= 0 and sim.fastest_id != _last_fastest:
		_last_fastest = sim.fastest_id
		if sim.leader_lap >= 2:
			_popups.append({"id": sim.fastest_id, "text": "최고 랩 %.3f" % sim.fastest_t, "col": PURPLE, "t": _now})
	var keep: Array = []
	for p in _popups:
		if _now - p["t"] < 2.2:
			keep.append(p)
	_popups = keep
	# 차고 정차 감지: 목표 위치가 자기 차고 지점과 같으면 정차 중
	var T = sim.T
	for c in sim.cars:
		var stopped := false
		if c.dnf == "" and sim.is_pitting(c):
			var sp: Array = T.pit_lane_point(sim._stall_u(c.stall_idx))
			var tg: Array = sim.car_pos_angle(c)
			stopped = (tg[0] - sp[0]).length() < 0.8
		if stopped:
			if not _stop_t.has(c.id):
				_stop_t[c.id] = sim.clock
				if c.mine:
					cue.emit("gun")
		else:
			_stop_t.erase(c.id)
		# 체커기
		if c.finished and not _fin_seen.has(c.id):
			_fin_seen[c.id] = true
			if c.mine and _smooth.has(c.id):
				var fp = sim.order().find(c) + 1
				_popups.append({"id": c.id, "text": "🏁 P%d" % fp, "col": AMBER, "t": _now})
	if sim.finishing and not _was_finishing:
		_was_finishing = true
		cue.emit("flag")
	# 레이스 컨트롤 메시지 → 상단 배너
	if not sim.radio_log.is_empty():
		var top = sim.radio_log[0]
		if not is_same(top, _last_log):
			_last_log = top
			if top["kind"] != "driver" and top["kind"] != "sc":
				show_banner(top["msg"], top["kind"])


func _process(delta: float) -> void:
	_now += delta
	if sim != null and sim.T != null and size.x > 4 and size.y > 4:
		if solo != null:
			follow_slot = -1
			_update_camera(delta)
		else:
			_update_cars(delta)
			_update_camera(delta)
			_update_effects()
	queue_redraw()


# ═════════ 그리기 ═════════
func _draw() -> void:
	var night: bool = sim != null and sim.night
	draw_rect(Rect2(Vector2.ZERO, size), BG_NIGHT if night else BG)
	if sim == null or sim.T == null:
		return
	var T = sim.T
	var font = get_theme_default_font()
	_draw_backdrop()
	_draw_track(T, night)
	_draw_stalls(T)
	_draw_labels(T, font, night)
	if solo != null:
		if solo.get("car") != null:
			var d: float = solo["dist"]
			_draw_car(_X(T.point_at_dist(d)), T.head_at_dist(d), solo["car"], night)
		return
	var wet: float = sim.wet
	if wet > 0.2:
		for c in sim.cars:
			if _smooth.has(c.id) and c.started and not sim.is_pitting(c):
				_draw_spray(_smooth[c.id]["p"], _smooth[c.id]["a"], wet)
	for pass_mine in [false, true]:
		for c in sim.cars:
			if c.mine != pass_mine or not _smooth.has(c.id):
				continue
			var sp: Dictionary = _smooth[c.id]
			_draw_car(_X(sp["p"]), sp["a"], c, night)
	_draw_crews()
	_draw_flashes()
	_draw_my_labels(font)
	_draw_safety_car(font)
	_draw_popups(font)
	if night:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.04, 0.12, 0.22))
	if wet > 0.04:
		_draw_rain(wet)
	_draw_banner(font)
	_draw_checkered(font)
	_draw_lights(font)


func _draw_backdrop() -> void:
	# 은은한 격자 (방송 그래픽 느낌)
	var step := 48.0
	var col := Color(1, 1, 1, 0.025)
	var x := fposmod(_off.x, step)
	while x < size.x:
		draw_line(Vector2(x, 0), Vector2(x, size.y), col, 1.0)
		x += step
	var y := fposmod(_off.y, step)
	while y < size.y:
		draw_line(Vector2(0, y), Vector2(size.x, y), col, 1.0)
		y += step


func _poly(pts: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(_X(p))
	return out


func _draw_track(T, night: bool) -> void:
	var w = TRACK_W * _s
	var poly = _poly(T.pts)
	poly.append(poly[0])
	# 피트레인 (점선 중앙선)
	var pit = _poly(T.pit_pts)
	draw_polyline(pit, Color("#20262f") if night else Color("#2c3440"), maxf(3.0, w * 0.55), true)
	_dashed(pit, Color("#4b5564"), 1.0, 4.0, 5.0)
	# 런오프 → 흰 테두리 → 아스팔트 → 안쪽 레이싱 라인
	draw_polyline(poly, RUNOFF, w * 2.6, true)
	draw_polyline(poly, EDGE.darkened(0.55 if night else 0.15), w + maxf(2.0, w * 0.14), true)
	draw_polyline(poly, Color("#262c36") if night else ASPHALT, w, true)
	var inner: Color = Color("#171c24") if night else ASPHALT_IN
	if sim.wet > 0.05:
		inner = inner.lerp(WET_TINT, 0.15 + sim.wet * 0.45)
	draw_polyline(poly, inner, w * 0.62, true)
	# 연석: 느린 코너 바깥쪽에 빨강·흰색 교차
	var i := 0
	while i < T.m:
		if T.spd[i] <= 0.55:
			var a: Vector2 = T.pts[i]
			var b: Vector2 = T.pts[(i + 2) % T.m]
			var c0: Vector2 = T.pts[(i - 2 + T.m) % T.m]
			var hn := atan2(b.y - a.y, b.x - a.x)
			var hp := atan2(a.y - c0.y, a.x - c0.x)
			var side := -1.0 if wrapf(hn - hp, -PI, PI) > 0 else 1.0
			var n: Vector2 = T.nrm[i] * (TRACK_W * 0.55 * side)
			var col := KERB_W if (i / 2) % 2 == 1 else KERB_R
			if night:
				col = col.darkened(0.4)
			draw_line(_X(a + n), _X(b + n), col, maxf(2.0, w * 0.2))
		i += 2
	# DRS 구간
	if sim.drs_on():
		for z in T.drs:
			var seg := PackedVector2Array()
			var j: int = z["ia"]
			var guard := 0
			while guard < T.m:
				seg.append(_X(T.pts[j]))
				if j == z["ib"]:
					break
				j = (j + 1) % T.m
				guard += 1
			if seg.size() >= 2:
				draw_polyline(seg, Color(GREEN, 0.55), maxf(2.0, w * 0.22), true)
	# 출발선 (체커)
	var p0: Vector2 = T.pts[0]
	var n0: Vector2 = T.nrm[0]
	var d0 := Vector2(cos(T.head[0]), sin(T.head[0]))
	var cells := 6
	var cell := TRACK_W / cells
	for k in cells:
		for r in 2:
			var q: Vector2 = p0 + n0 * (-TRACK_W * 0.5 + cell * k) + d0 * (cell * r)
			var quad := PackedVector2Array([_X(q), _X(q + n0 * cell), _X(q + n0 * cell + d0 * cell), _X(q + d0 * cell)])
			draw_colored_polygon(quad, Color.WHITE if (k + r) % 2 == 0 else Color("#111827"))


func _dashed(pts: PackedVector2Array, col: Color, width: float, dash: float, gap: float) -> void:
	var on := true
	var left := dash
	for i in range(pts.size() - 1):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var seg_len := a.distance_to(b)
		if seg_len < 0.01:
			continue
		var t := 0.0
		while t < seg_len:
			var step := minf(left, seg_len - t)
			if on:
				draw_line(a.lerp(b, t / seg_len), a.lerp(b, (t + step) / seg_len), col, width)
			t += step
			left -= step
			if left <= 0.0:
				on = not on
				left = dash if on else gap


func _draw_stalls(T) -> void:
	var colors := {}
	var mine := {}
	var working := {}
	for c in sim.cars:
		colors[c.stall_idx] = c.color
		if c.mine:
			mine[c.stall_idx] = true
		if c.boxing != null and sim.is_pitting(c):
			working[c.stall_idx] = true
	for idx in sim.n_stalls:
		var pp: Array = T.pit_lane_point(sim._stall_u(idx))
		var ang: float = pp[1]
		var nrm: Vector2 = Vector2(-sin(ang), cos(ang)) * float(T.inward)
		var pos: Vector2 = _X(pp[0] + nrm * 7.5)
		var w := maxf(5.0, TRACK_W * _s * 0.6)
		var col: Color = colors.get(idx, Color.GRAY)
		draw_set_transform(pos, ang, Vector2.ONE)
		draw_rect(Rect2(-w * 0.5, -w * 0.3, w, w * 0.6), col if mine.has(idx) else col.darkened(0.5))
		if mine.has(idx):
			draw_rect(Rect2(-w * 0.7, -w * 0.48, w * 1.4, w * 0.96), AMBER, false, 2.0)
		# 피트 작업 중: 깜박이는 작업등
		if working.has(idx) and int(_now * 4.0) % 2 == 0:
			draw_rect(Rect2(-w * 0.8, -w * 0.58, w * 1.6, w * 1.16), Color(1, 1, 1, 0.55), false, 1.5)
		draw_set_transform_matrix(Transform2D.IDENTITY)


func _draw_labels(T, font, night: bool) -> void:
	var fs := 13
	var placed: Array = []
	var labels: Array = T.C.get("labels", [])
	for lb in labels:
		var si: int = (int(lb[0]) * SPC) % T.m
		var txt: String = lb[1]
		var p := _X(T.pts[si])
		var n: Vector2 = T.nrm[si]
		var tsz: Vector2 = font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var o: float = -float(T.inward) * 34.0
		var lp := Vector2(clampf(p.x + n.x * o - tsz.x / 2, 4, size.x - tsz.x - 4), clampf(p.y + n.y * o + 4, 14, size.y - 4))
		for step in 5:
			var hit := false
			for r in placed:
				if absf(lp.x + tsz.x / 2 - r.x) < (tsz.x + r.z) / 2 + 4 and absf(lp.y - r.y) < 13:
					hit = true
					break
			if not hit:
				break
			var k := 1.25 + step * 0.28
			var dy := 13.0 if step % 2 == 0 else -13.0
			lp = Vector2(clampf(p.x + n.x * o * k - tsz.x / 2, 4, size.x - tsz.x - 4), clampf(p.y + n.y * o * k + dy, 14, size.y - 4))
		placed.append(Vector3(lp.x + tsz.x / 2, lp.y, tsz.x))
		var anchor := lp + Vector2(tsz.x / 2, -4)
		if anchor.distance_to(p) > 26:
			draw_line(p, anchor, Color(LABEL, 0.45), 1.0)
		draw_string(font, lp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(Color("#5d6674") if night else LABEL, 0.8))
	if sim.drs_on():
		for z in T.drs:
			var q := _X(T.pts[z["ia"]])
			var nn: Vector2 = T.nrm[z["ia"]]
			draw_string(font, q - nn * float(T.inward) * 18.0 + Vector2(-12, 4), "DRS", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, GREEN)


func _car_scale(is_mine: bool) -> float:
	# 화면 크기에 맞춘 차 크기, 추적 카메라로 확대하면 조금 더 커진다
	var base := clampf(minf(size.x, size.y) / 520.0, 0.9, 2.0)
	return base * (1.15 if is_mine else 0.98) * clampf(sqrt(_cam_zoom), 1.0, 1.7)


func _draw_car(pos: Vector2, ang: float, c, night: bool) -> void:
	var sc := _car_scale(c.mine)
	draw_set_transform(pos, ang, Vector2(sc, sc))
	if night:
		var beam := Color(1, 0.97, 0.78, 0.38)
		var fade := Color(1, 0.97, 0.78, 0.0)
		draw_polygon(PackedVector2Array([Vector2(4, -2), Vector2(28, -9), Vector2(28, 9), Vector2(4, 2)]), PackedColorArray([beam, fade, fade, beam]))
	# 그림자
	draw_colored_polygon(_car_body(Vector2(0.8, 1.1)), Color(0, 0, 0, 0.35))
	# 내 차 강조 링 · DRS 오라
	if c.mine:
		_ellipse(Vector2.ZERO, Vector2(9.5, 6.2), AMBER, 2.0 if c.slot == sel_slot else 1.3)
	if c.drs and not sim.sc:
		_ellipse(Vector2(-1, 0), Vector2(10.5, 6.8), GREEN, 1.4)
	if c.cls != "F1":
		_draw_wec_body(c)
		draw_set_transform_matrix(Transform2D.IDENTITY)
		return
	# 오픈 휠 4개 + 컴파운드 색 띠
	var tyre := Color("#0b0e12")
	draw_rect(Rect2(2.6, -4.8, 3.2, 1.7), tyre)
	draw_rect(Rect2(2.6, 3.1, 3.2, 1.7), tyre)
	draw_rect(Rect2(-5.8, -5.0, 3.5, 1.9), tyre)
	draw_rect(Rect2(-5.8, 3.1, 3.5, 1.9), tyre)
	var tcol: Color = Color(sim.TYRE_HEX[c.comp])
	draw_rect(Rect2(3.7, -4.5, 1.0, 1.1), tcol)
	draw_rect(Rect2(3.7, 3.4, 1.0, 1.1), tcol)
	draw_rect(Rect2(-4.6, -4.7, 1.2, 1.3), tcol)
	draw_rect(Rect2(-4.6, 3.4, 1.2, 1.3), tcol)
	# 리어·프런트 윙
	draw_rect(Rect2(-7.2, -4.2, 1.6, 8.4), c.rim)
	draw_rect(Rect2(5.8, -4.4, 1.4, 8.8), c.rim)
	# 바디 (노즈 + 사이드포드)
	draw_colored_polygon(_car_body(Vector2.ZERO), c.color)
	draw_line(Vector2(-4.5, 0), Vector2(5.5, 0), c.color.lightened(0.35), 0.7)
	# 콕핏 · 헤일로
	_fill_ellipse(Vector2(-0.5, 0), Vector2(2.0, 1.1), Color("#11161d"))
	draw_arc(Vector2(-0.3, 0), 1.6, -1.2, 1.2, 8, Color("#6b7280"), 0.5)
	draw_set_transform_matrix(Transform2D.IDENTITY)


## WEC 하이퍼카(풀 카울 + 눈물방울 캐노피 + 샤크핀) / LMGT3(박스형 쿠페 + 스포일러)
func _draw_wec_body(c) -> void:
	var tcol: Color = Color(sim.TYRE_HEX[c.comp])
	if c.cls == "HY":
		_round_rect(Rect2(-6.8, -4.2, 13.6, 8.4), 3.2, c.color)
		_round_rect_line(Rect2(-6.8, -4.2, 13.6, 8.4), 3.2, c.rim, 0.6)
		_fill_ellipse(Vector2(0.6, 0), Vector2(2.8, 1.9), Color("#0f172a"))
		draw_line(Vector2(-1.8, 0), Vector2(-6.4, 0), c.rim, 0.6)
		draw_rect(Rect2(-7.0, -4.0, 1.4, 8.0), Color("#111827"))
		draw_rect(Rect2(3.0, -4.4, 1.6, 0.6), tcol)
		draw_rect(Rect2(3.0, 3.8, 1.6, 0.6), tcol)
	else:
		var g := 0.88
		_round_rect(Rect2(-5.8 * g, -3.8 * g, 11.6 * g, 7.6 * g), 1.8 * g, c.color)
		draw_rect(Rect2(-2.2 * g, -2.7 * g, 4.8 * g, 5.4 * g), Color("#111827"))
		draw_rect(Rect2(-1.8 * g, -2.1 * g, 2.6 * g, 4.2 * g), c.color)
		draw_rect(Rect2(-6.2 * g, -3.6 * g, 1.1 * g, 7.2 * g), Color("#0b0e12"))
		draw_rect(Rect2(2.6 * g, -4.0 * g, 1.4 * g, 0.5 * g), tcol)
		draw_rect(Rect2(2.6 * g, 3.5 * g, 1.4 * g, 0.5 * g), tcol)


func _round_rect(r: Rect2, rad: float, col: Color) -> void:
	draw_colored_polygon(_rr_pts(r, rad), col)


func _round_rect_line(r: Rect2, rad: float, col: Color, w: float) -> void:
	var pts := _rr_pts(r, rad)
	pts.append(pts[0])
	draw_polyline(pts, col, w, true)


func _rr_pts(r: Rect2, rad: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var cs := [r.position + Vector2(r.size.x - rad, rad), r.position + Vector2(r.size.x - rad, r.size.y - rad), r.position + Vector2(rad, r.size.y - rad), r.position + Vector2(rad, rad)]
	var a0 := [-PI / 2, 0.0, PI / 2, PI]
	for i in 4:
		for k in 5:
			var a: float = a0[i] + PI / 2 * k / 4.0
			pts.append(cs[i] + Vector2(cos(a), sin(a)) * rad)
	return pts


func _car_body(o: Vector2) -> PackedVector2Array:
	var pts := [Vector2(6.8, 0), Vector2(2.5, -1.6), Vector2(0.8, -3.3), Vector2(-4.8, -2.8), Vector2(-6.2, -1.4), Vector2(-6.2, 1.4), Vector2(-4.8, 2.8), Vector2(0.8, 3.3), Vector2(2.5, 1.6)]
	var out := PackedVector2Array()
	for p in pts:
		out.append(p + o)
	return out


func _ellipse(center: Vector2, r: Vector2, col: Color, width: float) -> void:
	var pts := PackedVector2Array()
	for k in 25:
		var a := TAU * k / 24.0
		pts.append(center + Vector2(cos(a) * r.x, sin(a) * r.y))
	draw_polyline(pts, col, width, true)


func _fill_ellipse(center: Vector2, r: Vector2, col: Color) -> void:
	var pts := PackedVector2Array()
	for k in 16:
		var a := TAU * k / 16.0
		pts.append(center + Vector2(cos(a) * r.x, sin(a) * r.y))
	draw_colored_polygon(pts, col)


func _draw_spray(p: Vector2, ang: float, wet: float) -> void:
	# 젖은 노면: 차 뒤로 퍼지는 물보라
	var back := Vector2(-cos(ang), -sin(ang))
	var side := Vector2(-back.y, back.x)
	var base := _X(p)
	var k := _car_scale(false)
	var ln := (16.0 + 18.0 * wet) * k
	var spread := (5.0 + 6.0 * wet) * k
	var mist := Color(0.85, 0.9, 1.0, 0.22 * wet + 0.08)
	var clear := Color(0.85, 0.9, 1.0, 0.0)
	draw_polygon(PackedVector2Array([base + side * 2.0, base + back * ln + side * spread, base + back * ln - side * spread, base - side * 2.0]), PackedColorArray([mist, clear, clear, mist]))


func _draw_my_labels(font) -> void:
	var shown_txt := ""
	for c in sim.my_cars():
		if not _smooth.has(c.id):
			continue
		var q := _X(_smooth[c.id]["p"])
		var sc := _car_scale(true)
		var tag: String = ("#%d %s" % [c.slot + 1, c.code]) if c.cls != "F1" else c.code
		if sim.is_pitting(c):
			if not _pit_seen.has(c.id):
				_pit_seen[c.id] = sim.clock
			tag += "  PIT %.1fs" % (sim.clock - _pit_seen[c.id])
		else:
			_pit_seen.erase(c.id)
		var lp := q + Vector2(11, -9) * sc
		draw_string_outline(font, lp, tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, 4, Color(0, 0, 0, 0.7))
		draw_string(font, lp, tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, AMBER)
		# 무전 말풍선 (4초)
		if _radio_shown.has(c.id) and _now - _radio_shown[c.id] < 4.0 and c.radio != "" and c.radio != shown_txt:
			shown_txt = c.radio
			var a := clampf((4.0 - (_now - _radio_shown[c.id])) / 0.6, 0.0, 1.0)
			var txt: String = c.radio
			if txt.length() > 26:
				txt = txt.substr(0, 25) + "…"
			var tsz: Vector2 = font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14)
			var bp := Vector2(clampf(q.x - tsz.x / 2, 10, size.x - tsz.x - 18), clampf(q.y - 40 * sc, 24, size.y - BANNER_H - 12))
			var box := Rect2(bp - Vector2(8, 18), tsz + Vector2(16, 10))
			draw_rect(box, Color(0.08, 0.1, 0.13, 0.88 * a))
			draw_rect(box, Color(AMBER, 0.8 * a), false, 1.5)
			draw_string(font, bp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, a))


func _draw_safety_car(font) -> void:
	var scp: Array = sim.sc_pos_angle()
	if scp.is_empty():
		return
	var p := _X(scp[0])
	var col := GREEN if sim.sc_in_pit_lane else AMBER
	var r := 7.0 * _car_scale(false)
	draw_circle(p, r, col)
	draw_arc(p, r, 0, TAU, 20, Color.WHITE, 1.6, true)
	var lbl := "IN" if sim.sc_in_pit_lane else "SC"
	draw_string(font, p + Vector2(-r, 4), lbl, HORIZONTAL_ALIGNMENT_CENTER, r * 2, 11, Color("#1a1300"))
	if sim.sc_in_notified:
		var t := "SC PIT IN ▸" if sim.sc_in_pit_lane else "SC IN THIS LAP"
		draw_string_outline(font, p + Vector2(-48, -r - 6), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 4, Color(0, 0, 0, 0.7))
		draw_string(font, p + Vector2(-48, -r - 6), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)


func _draw_popups(font) -> void:
	for pp in _popups:
		if not _smooth.has(pp["id"]):
			continue
		var age: float = _now - pp["t"]
		var a := clampf((2.2 - age) / 0.6, 0.0, 1.0)
		var q := _X(_smooth[pp["id"]]["p"]) + Vector2(-20, -22 - age * 18)
		draw_string_outline(font, q, pp["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, 4, Color(0, 0, 0, 0.7 * a))
		draw_string(font, q, pp["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(pp["col"], a))


func _draw_rain(wet: float) -> void:
	var n := int(160 * clampf(wet, 0.0, 1.0)) + 24
	var col := Color(0.65, 0.78, 1.0, 0.16 + 0.24 * wet)
	for i in n:
		var hx := fposmod(sin(i * 12.9898) * 43758.5453, 1.0)
		var hy := fposmod(sin(i * 78.233) * 12345.678, 1.0)
		var x := fposmod(hx * size.x + _now * 40.0, size.x)
		var y := fposmod(hy * size.y + _now * (420.0 + 180.0 * hx), size.y)
		draw_line(Vector2(x, y), Vector2(x - 3.0, y + 12.0), col, 1.2)


func _draw_banner(font) -> void:
	# 하단 안내 띠(트랙을 가리지 않게 아래에): 세이프티카는 상시, 그 외 메시지는 5초
	var text := ""
	var col := Color(0.12, 0.15, 0.2, 0.92)
	var fg := Color.WHITE
	var slide := 1.0
	if sim.sc:
		text = "SAFETY CAR" if sim.sc_kind == "SC" else "VIRTUAL SAFETY CAR"
		if sim.sc_in_notified:
			text += "  ·  이번 랩 종료"
		col = Color(0.96, 0.62, 0.04, 0.92)
		fg = Color("#111827")
	elif _now - banner_t < 5.0 and banner_text != "":
		text = banner_text
		slide = clampf((_now - banner_t) / 0.25, 0.0, 1.0)
		if banner_kind == "bad":
			col = Color(0.55, 0.12, 0.14, 0.92)
		elif banner_kind == "wet":
			col = Color(0.1, 0.3, 0.6, 0.92)
		elif banner_kind == "green":
			col = Color(0.08, 0.45, 0.25, 0.92)
	if text == "":
		return
	var h := BANNER_H
	var top := size.y - h * slide
	draw_rect(Rect2(0, top, size.x, h), col)
	draw_string(font, Vector2(14, top + 23), text, HORIZONTAL_ALIGNMENT_LEFT, size.x - 28, 17, fg)


func _draw_lights(font) -> void:
	# 출발 신호등: 5개 점등 → 소등 + GO!
	var go_age := _now - lights_out_t
	if lights < 0 and go_age > 1.4:
		return
	var n := 5
	var r := clampf(size.x / 40.0, 12.0, 26.0)
	var gap := r * 2.8
	var w := gap * (n - 1)
	var origin := Vector2(size.x / 2 - w / 2, size.y * 0.2)
	draw_rect(Rect2(origin - Vector2(r * 1.6, r * 1.6), Vector2(w + r * 3.2, r * 3.2)), Color(0.02, 0.03, 0.05, 0.9))
	for i in n:
		var on := lights > i
		var c := origin + Vector2(gap * i, 0)
		if on:
			draw_circle(c, r * 1.5, Color(1, 0.1, 0.12, 0.18))
		draw_circle(c, r, Color("#ef1d2a") if on else Color("#2a1416"))
	if lights < 0:
		var a := clampf((1.4 - go_age) / 0.4, 0.0, 1.0)
		var t := "GO!"
		var tsz: Vector2 = font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 52)
		draw_string_outline(font, Vector2(size.x / 2 - tsz.x / 2, origin.y + r * 4.4), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 52, 6, Color(0, 0, 0, 0.7 * a))
		draw_string(font, Vector2(size.x / 2 - tsz.x / 2, origin.y + r * 4.4), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 52, Color(GREEN, a))


# ═════════ 피트 작업: 크루 6명(휠 4·잭 2)이 붙어 타이어를 교체 ═════════
func _draw_crews() -> void:
	for c in sim.cars:
		if not _stop_t.has(c.id) or not _smooth.has(c.id):
			continue
		var e: float = sim.clock - _stop_t[c.id]
		var sp: Dictionary = _smooth[c.id]
		var sc := _car_scale(c.mine)
		draw_set_transform(_X(sp["p"]), sp["a"], Vector2(sc, sc))
		var come := clampf(e / 0.35, 0.0, 1.0)
		var crew: Color = c.rim
		var spots := [Vector2(4.2, -7.6), Vector2(4.2, 7.6), Vector2(-4.0, -7.8), Vector2(-4.0, 7.8)]
		for w in spots:
			var stand: Vector2 = w * lerpf(1.9, 1.0, come)
			draw_circle(stand, 1.5, crew)
			draw_circle(stand, 1.5, Color(0, 0, 0, 0.5), false, 0.4)
			# 헌 타이어 빼기(0.5~1.2) → 새 타이어 끼우기(1.2~1.9)
			var wheel: Vector2 = Vector2(w.x, signf(w.y) * 3.9)
			if e > 0.5 and e < 1.2:
				var k := (e - 0.5) / 0.7
				draw_rect(Rect2(wheel.lerp(wheel + Vector2(0, signf(w.y) * 6.0), k) - Vector2(1.6, 0.9), Vector2(3.2, 1.8)), Color("#2b2f36"))
			elif e >= 1.2 and e < 1.9:
				var k2 := (e - 1.2) / 0.7
				draw_rect(Rect2((wheel + Vector2(0, signf(w.y) * 6.0)).lerp(wheel, k2) - Vector2(1.6, 0.9), Vector2(3.2, 1.8)), Color(sim.TYRE_HEX[c.comp]))
		# 앞·뒤 잭
		draw_circle(Vector2(lerpf(18.0, 10.5, come), 0), 1.5, crew)
		draw_circle(Vector2(lerpf(-18.0, -10.5, come), 0), 1.5, crew)
		# 진행 링 (휠건 작업 약 2초)
		var frac := clampf(e / 2.1, 0.0, 1.0)
		var ring := GREEN if frac >= 1.0 else AMBER
		draw_arc(Vector2.ZERO, 12.5, -PI / 2, -PI / 2 + TAU * frac, 28, ring, 1.2, true)
		draw_set_transform_matrix(Transform2D.IDENTITY)


func _draw_flashes() -> void:
	for id in _flash.keys():
		var age: float = _now - _flash[id]
		if age > 0.9 or not _smooth.has(id):
			_flash.erase(id)
			continue
		var r := (10.0 + age * 26.0) * _car_scale(true)
		draw_arc(_X(_smooth[id]["p"]), r, 0, TAU, 32, Color(GREEN, 0.9 * (1.0 - age / 0.9)), 2.5, true)


func _draw_checkered(font) -> void:
	# 선두가 체커기를 받은 뒤: 출발선 옆에서 체커기가 흔들리고, 화면 오른쪽 위에 표시
	if not sim.finishing:
		return
	var T = sim.T
	var base := _X(T.pts[0] + T.nrm[0] * (-float(T.inward) * TRACK_W * 1.6))
	var cell := clampf(_s * 2.2, 3.0, 7.0)
	for i in 6:
		for j in 4:
			var wob := sin(_now * 7.0 + i * 0.7) * cell * 0.35
			var col := Color.WHITE if (i + j) % 2 == 0 else Color("#0b0f14")
			draw_rect(Rect2(base + Vector2(i * cell, j * cell + wob - cell * 4), Vector2(cell, cell)), col)
	draw_line(base + Vector2(0, -cell * 4), base + Vector2(0, cell * 3), Color("#9aa4b2"), 1.5)
	var t := "🏁 체커기"
	var tsz: Vector2 = font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 18)
	var box := Rect2(Vector2(size.x - tsz.x - 28, 10), tsz + Vector2(16, 12))
	draw_rect(box, Color(0.05, 0.06, 0.08, 0.85))
	draw_rect(box, Color.WHITE, false, 1.2)
	draw_string(font, box.position + Vector2(8, tsz.y + 2), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)
