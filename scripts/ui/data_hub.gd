extends RefCounted
## 데이터 허브: 내 차와 기준 차(1위 등)의 섹터별 시간 비교 + "어디서 잃는지 → 무엇을 바꿀지" 조언.
## 연습(예상 섹터)과 레이스 복기(실제 베스트 섹터)에서 같이 쓴다.


static func kind_ko(slow: float) -> String:
	if slow >= 0.62:
		return "저속 코너"
	if slow <= 0.35:
		return "고속·직선"
	return "중속"


## 레이스 기록에서 차의 섹터별 베스트 (피트·SC·첫 랩 제외)
static func best_sectors(sim, c) -> Array:
	var ns: int = sim.NS
	var best: Array = []
	for i in ns:
		best.append(INF)
	var bad := {}
	for lt in c.lap_times:
		if lt.get("pit", false):
			bad[int(lt["lap"])] = true
	for l in sim.sc_laps:
		bad[int(l)] = true
	var nl: int = int(c.cross.size() / ns)
	for l in range(2, nl + 1):
		if bad.has(l) or bad.has(l + 1):
			continue
		for s in ns:
			var k0: int = (l - 1) * ns + s
			if k0 + 1 >= c.cross.size():
				break
			var dt: float = float(c.cross[k0 + 1]) - float(c.cross[k0])
			if dt > 0.0 and dt < best[s]:
				best[s] = dt
	return best


## 표 + 조언 (BBCode). mine/ref = 섹터별 시간 배열, ref_name = 기준 이름
static func report(sim, mine: Array, ref: Array, ref_name: String) -> String:
	var ns: int = mine.size()
	var t := "[table=5][cell][color=#8b98a5]섹터  [/color][/cell][cell][color=#8b98a5]성격  [/color][/cell][cell][color=#8b98a5]내 차  [/color][/cell][cell][color=#8b98a5]%s  [/color][/cell][cell][color=#8b98a5]차이[/color][/cell]" % ref_name
	var slow_d := 0.0
	var slow_w := 0.0
	var fast_d := 0.0
	var fast_w := 0.0
	var tot := 0.0
	var worst := -1
	var worst_v := -INF
	for i in ns:
		var a: float = float(mine[i])
		var b: float = float(ref[i])
		if a == INF or b == INF:
			continue
		var d: float = a - b
		tot += d
		var sl: float = float(sim.sec_slow[i]) if i < sim.sec_slow.size() else 0.5
		# 섹터 길이로 나눈 '같은 길이당' 차이로 성격별 비교
		var sh: float = maxf(0.02, float(sim.T.share[i]))
		var nd: float = d / sh
		slow_d += nd * sl
		slow_w += sl
		fast_d += nd * (1.0 - sl)
		fast_w += 1.0 - sl
		if d > worst_v:
			worst_v = d
			worst = i
		var col: String = "#22c55e" if d < -0.02 else ("#ef4444" if d > 0.05 else "#e6edf3")
		var bar: String = "█".repeat(clampi(int(round(absf(d) / 0.05)), 0, 8))
		t += "[cell]S%d  [/cell][cell]%s  [/cell][cell]%.3f  [/cell][cell]%.3f  [/cell][cell][color=%s]%+.3f %s[/color][/cell]" % [i + 1, kind_ko(sl), a, b, col, d, bar]
	t += "[/table]\n"
	t += "랩 전체 %s [b]%+.3f초[/b]\n" % ["손해" if tot > 0.0 else "이득", tot]
	var sm: float = slow_d / maxf(0.01, slow_w)
	var fm: float = fast_d / maxf(0.01, fast_w)
	var gapn: float = (sm - fm) * 0.15 # 대략 랩의 15% 구간 기준 초로
	if worst >= 0 and worst_v > 0.03:
		t += "가장 많이 잃는 곳: [b]S%d (%s)[/b] %+.3f초\n" % [worst + 1, kind_ko(float(sim.sec_slow[worst])), worst_v]
	if gapn > 0.02:
		t += "[color=#ffc53d]→ 저속 코너에서 직선보다 더 잃고 있어요. 다운포스(윙)를 올려 보세요.[/color]"
	elif gapn < -0.02:
		t += "[color=#ffc53d]→ 직선·고속 구간에서 더 잃고 있어요. 윙을 내리거나 타이어 압력(직선 속도)을 확인하세요.[/color]"
	else:
		t += "[color=#8b98a5]→ 구간별 손익이 고르게 퍼져 있어요. 셋업보다는 차·드라이버 기본 속도 차이예요.[/color]"
	return t
