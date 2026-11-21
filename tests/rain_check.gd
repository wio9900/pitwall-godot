extends SceneTree
## 비 레이스 측정: AI 만 달리는 비 레이스 여러 판 → 피트 수·날씨 피트·맞지 않는 타이어 랩 비율·팀 순위 흔들림
## 실행: godot --headless --path . --script res://tests/rain_check.gd

const RaceSimS = preload("res://scripts/sim/race_sim.gd")
const DB = preload("res://scripts/data/game_db.gd")
const CIRCS = ["melbourne", "silverstone", "suzuka", "interlagos", "spa_f1", "monza"]


func _init() -> void:
	DB.load_all()
	var n := 0
	var pits := 0.0
	var wrong := 0.0
	var laps_all := 0.0
	var dnf := 0.0
	var rank_err := 0.0
	var spread := 0.0
	var gap := 0.0
	var wl := 0.0
	for key in CIRCS:
		if not DB.circuits.has(key):
			continue
		for s in 8:
			var sim = RaceSimS.new()
			sim.new_race(key, -1, 25, "rain", ["M", "M"], 7000 + s * 13 + key.length(), {})
			sim.prepare_start()
			var guard := 0
			var last := -1
			while not sim.done and guard < 300000:
				sim.advance(2.0)
				guard += 1
				if sim.leader_lap != last:
					last = sim.leader_lap
					if sim.wet > 0.1:
						wl += 1.0
						spread += sim.sec_wet.max() - sim.sec_wet.min()
						for k in sim.NS:
							gap += sim.off_gap(k) / sim.NS
					for c in sim.cars:
						if c.is_running():
							laps_all += 1.0
							if sim.kind_of(c.comp) != sim.ideal_tyre(sim.wet):
								wrong += 1.0
			var ord: Array = sim.order()
			for i in ord.size():
				var c = ord[i]
				pits += c.pits
				if c.dnf != "":
					dnf += 1.0
				rank_err += absf(float(i) - float(c.team_idx) * 2.0)
			n += ord.size()
	print("비 레이스: 차당 피트 %.2f · 맞지 않는 타이어 랩 %.1f%% · 리타이어 %.1f%% · 팀 순위 흔들림 %.2f (%d대)" % [pits / n, wrong / laps_all * 100.0, dnf / n * 100.0, rank_err / n, n])
	print("젖은 랩: 섹터 차이(최대-최소) 평균 %.2f · 라인 밖이 더 젖은 정도 평균 %.2f" % [spread / maxf(1.0, wl), gap / maxf(1.0, wl)])
	quit(0)
