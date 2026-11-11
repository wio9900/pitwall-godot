extends RefCounted
## 서킷 제어점(JSON)으로부터 레이스 라인·섹터·피트레인을 계산하는 트랙 형상 모듈.
## 원본 HTML 버전 buildTrack()을 그대로 옮긴 것 — 결과가 같아야 밸런스가 유지된다.

const SPC := 20 # 제어점 사이 샘플 수
const NS := 6   # 섹터 수

var key := ""
var C: Dictionary = {}
var pts: Array = []       # Vector2 샘플 (레이스 라인)
var cum: Array = []       # 누적 거리 (m+1개)
var L := 0.0              # 한 바퀴 길이
var tw: Array = []        # 누적 '시간 가중치' (코너는 느리게)
var sec_idx: Array = []   # 섹터 경계 샘플 인덱스 (NS+1개)
var sec_tw: Array = []    # 섹터별 시간 가중치
var share: Array = []     # 섹터가 랩타임에서 차지하는 비율
var m := 0
var head: Array = []      # 샘플별 진행 방향 (라디안)
var nrm: Array = []       # 샘플별 법선 벡터
var spd: Array = []       # 샘플별 상대 속도 (0.28~1, 연출용)
var drs: Array = []       # [{ia, ib, sec}]
var drs_secs: Dictionary = {}
var pit_idx: Array = []
var pit_pts: Array = []   # 스무딩된 피트레인 경로
var sf_at := 0
var inward := 1.0
var entry_frac := 0.0
var exit_frac := 0.0
var pit_in := 0
var pit_out := 0
var bbox := Rect2()


func build(key_: String, c: Dictionary) -> void:
	key = key_
	C = c
	var P: Array = c["pts"]
	var n = P.size()
	pts.clear()
	for i in n:
		var p0: Array = P[(i - 1 + n) % n]
		var p1: Array = P[i]
		var p2: Array = P[(i + 1) % n]
		var p3: Array = P[(i + 2) % n]
		for j in SPC:
			var t = float(j) / SPC
			var t2 = t * t
			var t3 = t2 * t
			var xy = [0.0, 0.0]
			for k in 2:
				xy[k] = 0.5 * ((2.0 * p1[k]) + (-p0[k] + p2[k]) * t + (2.0 * p0[k] - 5.0 * p1[k] + 4.0 * p2[k] - p3[k]) * t2 + (-p0[k] + 3.0 * p1[k] - 3.0 * p2[k] + p3[k]) * t3)
			pts.append(Vector2(xy[0], xy[1]))
	m = pts.size()
	var ds: Array = []
	for i in m:
		ds.append((pts[(i + 1) % m] - pts[i]).length())
	cum = [0.0]
	for i in range(1, m + 1):
		cum.append(cum[i - 1] + ds[i - 1])
	L = cum[m]
	head.clear()
	for i in m:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % m]
		head.append(atan2(b.y - a.y, b.x - a.x))
	var curv: Array = []
	for i in m:
		var d: float = head[(i + 1) % m] - head[(i - 1 + m) % m]
		d = abs(atan2(sin(d), cos(d)))
		curv.append(d / (ds[i] + ds[(i - 1 + m) % m]))
	spd.clear()
	for k in curv:
		spd.append(maxf(0.28, minf(1.0, sqrt((1.0 / maxf(k, 1e-4)) / 260.0))))
	for _pass in 2:
		for i in m:
			var p = (i - 1 + m) % m
			spd[i] = minf(spd[i], spd[p] + 0.004 * ds[p])
		for i in range(m - 1, -1, -1):
			var nx = (i + 1) % m
			spd[i] = minf(spd[i], spd[nx] + 0.007 * ds[i])
	tw = [0.0]
	for i in m:
		tw.append(tw[i] + ds[i] / spd[i])
	sec_idx.clear()
	for s in NS + 1:
		var target = L * s / NS
		var k = 0
		while k < m and cum[k] < target:
			k += 1
		sec_idx.append(m if s == NS else k)
	sec_tw.clear()
	share.clear()
	for s in NS:
		sec_tw.append(tw[sec_idx[s + 1]] - tw[sec_idx[s]])
	for s in NS:
		share.append(sec_tw[s] / tw[m])
	var cx = 0.0
	var cy = 0.0
	for p in pts:
		cx += p.x
		cy += p.y
	cx /= m
	cy /= m
	nrm.clear()
	for h in head:
		nrm.append(Vector2(-sin(h), cos(h)))
	drs.clear()
	drs_secs.clear()
	for pair in c["drs"]:
		var ia = _sample_of(int(pair[0]), n)
		var ib = _sample_of(int(pair[1]), n)
		var da: float = cum[ia]
		var db: float = cum[ib] if cum[ib] >= da else cum[ib] + L
		var at = fmod(da + (db - da) * 0.7, L)
		var sec = mini(NS - 1, int(floor(at / L * NS)))
		drs.append({"ia": ia, "ib": ib, "sec": sec})
		drs_secs[sec] = true
	pit_in = _sample_of(int(c["pit"][0]), n)
	pit_out = _sample_of(int(c["pit"][1]), n)
	var nm: Vector2 = nrm[0]
	inward = 1.0 if ((cx - pts[0].x) * nm.x + (cy - pts[0].y) * nm.y) > 0 else -1.0
	pit_idx.clear()
	var ii = pit_in
	while true:
		pit_idx.append(ii)
		if ii == pit_out:
			break
		ii = (ii + 1) % m
	sf_at = pit_idx.find(0)
	var last_s: int = sec_idx[NS - 1]
	entry_frac = clampf((tw[pit_in] - tw[last_s]) / sec_tw[NS - 1], 0.0, 0.98)
	exit_frac = clampf((tw[pit_out] - tw[0]) / sec_tw[0], 0.0, 0.95)
	var n_pit = pit_idx.size() - 1
	pit_pts.clear()
	for jj in n_pit + 1:
		var sx = 0.0
		var sy = 0.0
		var nxs = 0.0
		var nys = 0.0
		var cnt = 0
		for d in range(-16, 17):
			var kk = clampi(jj + d, 0, n_pit)
			var idx: int = pit_idx[kk]
			sx += pts[idx].x
			sy += pts[idx].y
			nxs += nrm[idx].x
			nys += nrm[idx].y
			cnt += 1
		var tr = minf(1.0, minf(jj, n_pit - jj) / 14.0)
		var ramp = tr * tr * (3.0 - 2.0 * tr)
		var i0: int = pit_idx[jj]
		var bx: float = pts[i0].x * (1.0 - ramp) + (sx / cnt) * ramp
		var by: float = pts[i0].y * (1.0 - ramp) + (sy / cnt) * ramp
		var nn = Vector2(nxs, nys).length()
		if nn == 0.0:
			nn = 1.0
		var o = inward * 18.0 * ramp
		pit_pts.append(Vector2(bx + (nxs / nn) * o, by + (nys / nn) * o))
	for _pass in 8:
		for jj in range(1, n_pit):
			pit_pts[jj] = pit_pts[jj - 1] * 0.25 + pit_pts[jj] * 0.5 + pit_pts[jj + 1] * 0.25
	var mn = Vector2(1e9, 1e9)
	var mx = Vector2(-1e9, -1e9)
	for p in pts:
		mn = mn.min(p)
		mx = mx.max(p)
	bbox = Rect2(mn, mx - mn)


func _sample_of(ci: int, n: int) -> int:
	return (ci % n) * SPC


## 섹터 내 시간 비율 → 샘플 위치 [인덱스, 보간 비율]
func locate(sec: int, frac: float) -> Array:
	var target: float = tw[sec_idx[sec]] + clampf(frac, 0.0, 1.0) * sec_tw[sec]
	var lo: int = sec_idx[sec]
	var hi: int = sec_idx[sec + 1]
	while hi - lo > 1:
		var mid = (lo + hi) >> 1
		if tw[mid] <= target:
			lo = mid
		else:
			hi = mid
	var seg: float = tw[lo + 1] - tw[lo]
	if seg == 0.0:
		seg = 1.0
	return [lo, (target - tw[lo]) / seg]


func point_at(sec: int, frac: float) -> Vector2:
	var r = locate(sec, frac)
	var a: Vector2 = pts[r[0] % m]
	var b: Vector2 = pts[(r[0] + 1) % m]
	return a.lerp(b, r[1])


func dist_at(sec: int, frac: float) -> float:
	var r = locate(sec, frac)
	return cum[r[0]] + (cum[r[0] + 1] - cum[r[0]]) * r[1]


func _seg_at_dist(d: float) -> int:
	var lo = 0
	var hi = m
	while hi - lo > 1:
		var mid = (lo + hi) >> 1
		if cum[mid] <= d:
			lo = mid
		else:
			hi = mid
	return lo


func point_at_dist(d: float) -> Vector2:
	d = fposmod(d, L)
	var lo = _seg_at_dist(d)
	var a: Vector2 = pts[lo]
	var b: Vector2 = pts[(lo + 1) % m]
	var seg: float = cum[lo + 1] - cum[lo]
	if seg == 0.0:
		seg = 1.0
	return a.lerp(b, (d - cum[lo]) / seg)


func head_at_dist(d: float) -> float:
	d = fposmod(d, L)
	return head[_seg_at_dist(d)]


## 피트레인 인덱스(실수) → [위치, 진행 방향]
func pit_lane_point(u: float) -> Array:
	var n = pit_pts.size() - 1
	var j = clampf(u, 0.0, n)
	var j0 = int(floor(j))
	var j1 = mini(n, j0 + 1)
	var f = j - j0
	var pos: Vector2 = pit_pts[j0].lerp(pit_pts[j1], f)
	var ja = clampi(int(floor(j)), 0, n - 1)
	var dv: Vector2 = pit_pts[ja + 1] - pit_pts[ja]
	return [pos, atan2(dv.y, dv.x)]
