extends RefCounted
## 레이스 도중 저장·이어하기. race_sim 과 차(car)의 모든 스크립트 변수를 그대로 저장한다.
## 트랙(T)·서킷 데이터(CIRC)는 서킷 키로 다시 불러오고, 차끼리의 참조는 차 번호로 바꿔 저장한다.
## 화면 상태(모드·배속 등)는 meta 딕셔너리로 함께 저장한다.

const RaceSimS = preload("res://scripts/sim/race_sim.gd")
const CarS = preload("res://scripts/sim/car.gd")
const DB = preload("res://scripts/data/game_db.gd")
const PATH := "user://race_resume.bin"
const VER := 1
const SKIP := ["T", "CIRC", "rng", "cars", "_cuts_cache"]


static func _vars(o: Object) -> Array:
	var out: Array = []
	for p in o.get_property_list():
		if int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			out.append(String(p["name"]))
	return out


static func _enc(v: Variant) -> Variant:
	if v is Object:
		if v.get_script() == CarS:
			return {"__car": int(v.id)}
		return null
	if v is Dictionary:
		var d := {}
		for k in v:
			d[k] = _enc(v[k])
		return d
	if v is Array:
		var a: Array = []
		for x in v:
			a.append(_enc(x))
		return a
	return v


static func _dec(v: Variant, by_id: Dictionary) -> Variant:
	if v is Dictionary:
		if v.size() == 1 and v.has("__car"):
			return by_id.get(int(v["__car"]))
		var d := {}
		for k in v:
			d[k] = _dec(v[k], by_id)
		return d
	if v is Array:
		var a: Array = []
		for x in v:
			a.append(_dec(x, by_id))
		return a
	return v


## sim 상태 → 저장용 딕셔너리
static func pack(sim) -> Dictionary:
	var s := {}
	for n in _vars(sim):
		if not SKIP.has(n):
			s[n] = _enc(sim.get(n))
	var cs: Array = []
	for c in sim.cars:
		var d := {}
		for n in _vars(c):
			d[n] = _enc(c.get(n))
		cs.append(d)
	return {"sim": s, "cars": cs, "rng_seed": sim.rng.seed, "rng_state": sim.rng.state}


## 저장용 딕셔너리 → 새 sim
static func unpack(data: Dictionary):
	DB.load_all()
	var sim = RaceSimS.new()
	var s: Dictionary = data["sim"]
	sim.circ_key = s["circ_key"]
	sim.T = DB.track(sim.circ_key)
	sim.CIRC = DB.circuits[sim.circ_key]
	var by_id := {}
	var cars: Array = []
	for d in data["cars"]:
		var c = CarS.new()
		by_id[int(d["id"])] = c
		cars.append(c)
	for i in cars.size():
		var d: Dictionary = data["cars"][i]
		for n in d:
			cars[i].set(n, _dec(d[n], by_id))
	sim.cars = cars
	for n in s:
		sim.set(n, _dec(s[n], by_id))
	sim.rng.seed = int(data["rng_seed"])
	sim.rng.state = int(data["rng_state"])
	return sim


static func has_save() -> bool:
	return FileAccess.file_exists(PATH)


static func save(sim, meta: Dictionary, extra_sim = null) -> void:
	var data := {"ver": VER, "meta": meta, "main": pack(sim)}
	if extra_sim != null:
		data["extra"] = pack(extra_sim)
	var f = FileAccess.open(PATH, FileAccess.WRITE)
	if f != null:
		f.store_var(data)


## {meta, sim, extra} 또는 실패 시 빈 딕셔너리
static func load_save() -> Dictionary:
	if not has_save():
		return {}
	var f = FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return {}
	var data = f.get_var()
	if typeof(data) != TYPE_DICTIONARY or int(data.get("ver", 0)) != VER:
		return {}
	var out := {"meta": data["meta"], "sim": unpack(data["main"]), "extra": null}
	if data.has("extra"):
		out["extra"] = unpack(data["extra"])
	return out


## 메뉴에 보여줄 요약 (불러오지 않고 meta 만)
static func peek() -> Dictionary:
	if not has_save():
		return {}
	var f = FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return {}
	var data = f.get_var()
	if typeof(data) != TYPE_DICTIONARY or int(data.get("ver", 0)) != VER:
		return {}
	return data["meta"]


static func clear() -> void:
	if has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
