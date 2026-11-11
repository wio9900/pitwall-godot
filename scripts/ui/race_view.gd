extends Control
## 탑뷰 레이스 화면. 시뮬레이션 상태(sim)를 읽어서 그리기만 한다 — 로직은 없다.
## 연출을 바꾸고 싶으면 이 파일만 고치면 된다.

const BG := Color("#0b0f14")
const RUNOFF := Color("#17202a")
const ASPHALT := Color("#3a4350")
const ASPHALT_WET := Color("#2a3b52")
const EDGE := Color("#c8d0da")
const KERB_A := Color("#e5484d")
const KERB_B := Color("#f1f5f9")
const PIT := Color("#252e39")
const AMBER := Color("#ffc53d")
const DRS_COL := Color(0.25, 0.85, 0.45, 0.35)
const TRACK_W := 11.0 # 트랙 폭 (트랙 좌표 단위)

var sim = null
var follow_slot := -1   # -1 = 전체 화면, 0/1 = 내 차 추적
var _cam_center := Vector2.ZERO
var _cam_zoom := 1.0
var _s := 1.0
var _off := Vector2.ZERO


func _X(p: Vector2) -> Vector2:
	return p * _s + _off


func _update_camera(delta: float) -> void:
	var T = sim.T
	var pad = 30.0
	var bb: Rect2 = T.bbox.grow(pad)
	var fit_s: float = minf(size.x / bb.size.x, size.y / bb.size.y)
	var want_center: Vector2 = bb.get_center()
	var want_zoom = 1.0
	if follow_slot >= 0:
		var mc: Array = sim.my_cars()
		if follow_slot < mc.size() and mc[follow_slot].dnf == "":
			want_center = sim.car_pos_angle(mc[follow_slot])[0]
			want_zoom = 2.6
	# 부드러운 카메라 이동
	var k = clampf(delta * 4.0, 0.0, 1.0)
	if _cam_center == Vector2.ZERO:
		_cam_center = want_center
		_cam_zoom = want_zoom
	_cam_center = _cam_center.lerp(want_center, k)
	_cam_zoom = lerpf(_cam_zoom, want_zoom, k)
	_s = fit_s * _cam_zoom
	_off = size / 2.0 - _cam_center * _s


func _process(delta: float) -> void:
	if sim != null and sim.T != null:
		_update_camera(delta)
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	if sim == null or sim.T == null:
		return
	var T = sim.T
	var tw = TRACK_W * _s
	var poly = PackedVector2Array()
	for p in T.pts:
		poly.append(_X(p))
	poly.append(poly[0])
	# 런오프 · 트랙 테두리 · 아스팔트
	draw_polyline(poly, RUNOFF, tw * 2.4, true)
	draw_polyline(poly, EDGE.darkened(0.35), tw + 2.0, true)
	var asphalt = ASPHALT.lerp(ASPHALT_WET, clampf(sim.wet * 1.4, 0.0, 1.0))
	draw_polyline(poly, asphalt, tw, true)
	_draw_kerbs(T, tw)
	# DRS 구간
	if sim.drs_on():
		for z in T.drs:
			var seg = PackedVector2Array()
			var i: int = z["ia"]
			var guard = 0
			while guard < T.m:
				seg.append(_X(T.pts[i]))
				if i == z["ib"]:
					break
				i = (i + 1) % T.m
				guard += 1
			if seg.size() >= 2:
				draw_polyline(seg, DRS_COL, tw * 0.35, true)
	# 피트레인
	var pit_poly = PackedVector2Array()
	for p in T.pit_pts:
		pit_poly.append(_X(p))
	draw_polyline(pit_poly, PIT, tw * 0.6, true)
	_draw_stalls(T, tw)
	_draw_start_line(T, tw)
	# 차량: AI 먼저, 내 차는 맨 위에
	var font = get_theme_default_font()
	for pass_mine in [false, true]:
		for c in sim.cars:
			if c.mine != pass_mine or c.dnf != "":
				continue
			var pa: Array = sim.car_pos_angle(c)
			_draw_car(_X(pa[0]), pa[1], c.color, c.rim, c.mine, c.drs and not sim.sc)
			if c.mine:
				draw_string(font, _X(pa[0]) + Vector2(-30, -16), c.code, HORIZONTAL_ALIGNMENT_CENTER, 60, 16, AMBER)
	# 세이프티카
	var scp: Array = sim.sc_pos_angle()
	if not scp.is_empty():
		_draw_car(_X(scp[0]), scp[1], Color("#f59e0b"), Color("#111827"), false, false)
		draw_string(font, _X(scp[0]) + Vector2(-20, -14), "SC", HORIZONTAL_ALIGNMENT_CENTER, 40, 15, Color("#f59e0b"))
	# 날씨·야간
	if sim.night:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.04, 0.12, 0.28))
	if sim.wet > 0.04:
		_draw_rain()
	if sim.sc:
		var label = "SAFETY CAR" if sim.sc_kind == "SC" else "VIRTUAL SAFETY CAR"
		draw_rect(Rect2(0, 0, size.x, 26), Color(0.96, 0.62, 0.04, 0.85))
		draw_string(font, Vector2(0, 19), label, HORIZONTAL_ALIGNMENT_CENTER, size.x, 17, Color("#111827"))


func _draw_kerbs(T, tw: float) -> void:
	# 느린 코너(속도 낮은 구간) 안쪽·바깥쪽에 빨강·흰색 연석
	var step = 3
	var i = 0
	while i < T.m:
		if T.spd[i] < 0.62:
			var j: int = (i + step) % T.m
			var off: Vector2 = T.nrm[i] * (TRACK_W * 0.5)
			var col = KERB_A if (i / step) % 2 == 0 else KERB_B
			for side in [1.0, -1.0]:
				draw_line(_X(T.pts[i] + off * side), _X(T.pts[j] + off * side), col, maxf(1.5, tw * 0.16))
		i += step


func _draw_stalls(T, tw: float) -> void:
	var colors = {}
	var mine = {}
	for c in sim.cars:
		colors[c.stall_idx] = c.color
		if c.mine:
			mine[c.stall_idx] = true
	for idx in sim.n_stalls:
		var pp: Array = T.pit_lane_point(sim._stall_u(idx))
		var ang: float = pp[1]
		var nrm: Vector2 = Vector2(-sin(ang), cos(ang)) * float(T.inward)
		var pos: Vector2 = _X(pp[0] + nrm * 7.0)
		var w = maxf(4.0, tw * 0.55)
		var col: Color = colors.get(idx, Color.GRAY)
		draw_set_transform(pos, ang, Vector2.ONE)
		draw_rect(Rect2(-w * 0.5, -w * 0.32, w, w * 0.64), col if mine.has(idx) else col.darkened(0.45))
		if mine.has(idx):
			draw_rect(Rect2(-w * 0.7, -w * 0.5, w * 1.4, w), AMBER, false, 2.0)
		draw_set_transform_matrix(Transform2D.IDENTITY)


func _draw_start_line(T, tw: float) -> void:
	var p: Vector2 = T.pts[0]
	var n: Vector2 = T.nrm[0]
	var dir = Vector2(cos(T.head[0]), sin(T.head[0]))
	var cells = 6
	var cell = TRACK_W / cells
	for k in cells:
		for r in 2:
			var a: Vector2 = p + n * (-TRACK_W * 0.5 + cell * k) + dir * (cell * r)
			var col = Color.WHITE if (k + r) % 2 == 0 else Color("#111827")
			var q = PackedVector2Array([_X(a), _X(a + n * cell), _X(a + n * cell + dir * cell), _X(a + dir * cell)])
			draw_colored_polygon(q, col)


func _draw_car(pos: Vector2, ang: float, body: Color, rim: Color, is_mine: bool, drs: bool) -> void:
	var sc = clampf(_s * 0.9, 1.4, 4.5)
	if is_mine:
		draw_circle(pos, 9.0 * sc * 0.75, Color(AMBER, 0.22))
	if drs:
		draw_circle(pos, 6.0 * sc * 0.75, Color(0.3, 0.9, 0.5, 0.25))
	draw_set_transform(pos, ang, Vector2(sc, sc))
	# 차체 (앞이 +x)
	var shape = PackedVector2Array([Vector2(-5, -2.0), Vector2(3, -1.5), Vector2(6, -0.6), Vector2(6, 0.6), Vector2(3, 1.5), Vector2(-5, 2.0)])
	draw_colored_polygon(shape, body)
	draw_rect(Rect2(-6.2, -2.8, 1.4, 5.6), Color("#0f172a"))  # 리어 윙
	draw_rect(Rect2(5.2, -2.6, 0.9, 5.2), rim)                # 프런트 윙
	draw_rect(Rect2(-4.6, -2.9, 2.2, 1.0), Color("#111827"))  # 리어 타이어
	draw_rect(Rect2(-4.6, 1.9, 2.2, 1.0), Color("#111827"))
	draw_rect(Rect2(2.6, -2.6, 1.8, 0.9), Color("#111827"))   # 프런트 타이어
	draw_rect(Rect2(2.6, 1.7, 1.8, 0.9), Color("#111827"))
	draw_circle(Vector2(-0.6, 0), 0.9, rim)                    # 헬멧
	draw_set_transform_matrix(Transform2D.IDENTITY)


func _draw_rain() -> void:
	var t = Time.get_ticks_msec() / 1000.0
	var n = int(140 * clampf(sim.wet, 0.0, 1.0)) + 20
	var col = Color(0.65, 0.78, 1.0, 0.18 + 0.25 * sim.wet)
	for i in n:
		var hx = fposmod(sin(i * 12.9898) * 43758.5453, 1.0)
		var hy = fposmod(sin(i * 78.233) * 12345.678, 1.0)
		var x = fposmod(hx * size.x + t * 40.0, size.x)
		var y = fposmod(hy * size.y + t * (420.0 + 180.0 * hx), size.y)
		draw_line(Vector2(x, y), Vector2(x - 3.0, y + 11.0), col, 1.2)
