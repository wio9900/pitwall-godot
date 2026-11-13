extends RefCounted
## 드라이버 특성 태그 (FM 의 '선호 플레이'): 능력치·이름으로 정해지는 고유 습관 1~2개.
## 같은 드라이버는 언제나 같은 태그 (저장할 필요 없음). 효과는 race_sim 에서 상황별로 조금씩.

const KO := {
	"dive": "다이브봄 선호",       # 늦은 브레이킹 추월: 추월 성공↑, 접촉↑
	"saver": "타이어 온존",        # 마모↓, 스틴트 초반 2랩 조금 느림
	"rain": "레인 마스터",         # 젖은 노면에서 실수↓·속도↑
	"wall": "철벽 수비",           # 방어 시 추월 허용↓
	"rocket": "로켓 스타트",       # 출발 반응↑
	"closer": "막판 스퍼트",       # 레이스 마지막 15% 조금 빠름
	"night": "나이트 러너",        # (WEC) 밤 실수 증가가 작음
}
const DESC := {
	"dive": "추월 성공률↑ · 접촉 사고↑",
	"saver": "타이어 마모↓ · 스틴트 초반 랩타임↓",
	"rain": "젖은 노면에서 실수↓ · 속도↑",
	"wall": "뒤 차의 추월 성공률↓",
	"rocket": "출발 반응 속도↑",
	"closer": "마지막 15% 구간 페이스↑",
	"night": "밤 주행 실수 증가가 작음",
}


static func _h(sv: String) -> float:
	var h := 2166136261
	for ch in sv:
		h = ((h ^ ch.unicode_at(0)) * 16777619) & 0x7fffffff
	return float(h % 10000) / 10000.0


## 드라이버 사전(능력치 포함)으로 태그 목록 (최대 2개, 점수 높은 순)
static func of(d: Dictionary) -> Array:
	var nm: String = String(d.get("name", ""))
	var sc := {}
	var aggr: float = float(d.get("aggr", 0.55))
	var tm: float = float(d.get("tyreMgmt", 0.78))
	var wet: float = float(d.get("wet", 0.8))
	var df: float = float(d.get("def", 0.75))
	var cons: float = float(d.get("cons", 0.78))
	if aggr >= 0.66:
		sc["dive"] = aggr - 0.66 + _h(nm + "d") * 0.08
	if tm >= 0.87:
		sc["saver"] = tm - 0.87 + _h(nm + "s") * 0.08
	if wet >= 0.89:
		sc["rain"] = wet - 0.89 + _h(nm + "r") * 0.08
	if df >= 0.88:
		sc["wall"] = df - 0.88 + _h(nm + "w") * 0.08
	if _h(nm + "k") < 0.16:
		sc["rocket"] = 0.02 + _h(nm + "k2") * 0.05
	if _h(nm + "c") < 0.14:
		sc["closer"] = 0.02 + _h(nm + "c2") * 0.05
	if d.has("grade") and cons >= 0.84:
		sc["night"] = cons - 0.84 + _h(nm + "n") * 0.06
	var keys: Array = sc.keys()
	keys.sort_custom(func(a, b): return float(sc[a]) > float(sc[b]))
	return keys.slice(0, 2)


static func label(tags: Array) -> String:
	var out: PackedStringArray = []
	for t in tags:
		out.append(KO.get(t, t))
	return " · ".join(out)
