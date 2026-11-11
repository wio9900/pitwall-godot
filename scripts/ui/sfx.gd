extends Node
## 효과음. 소리 파일 없이 코드로 파형을 만들어 재생한다(용량 0, 라이선스 걱정 없음).
## play("beep") 처럼 부르면 되고, set_engine(0~1) 로 배경 엔진음 크기를 정한다.

const RATE := 22050

var muted := false
var _players := {}
var _drone: AudioStreamPlayer
var _pb: AudioStreamGeneratorPlayback = null
var _engine_target := 0.0
var _engine := 0.0
var _ph1 := 0.0
var _ph2 := 0.0
var _lp := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 7
	_add("beep", _tone(620.0, 0.22, 0.55, 0.0))
	_add("go", _tone(1240.0, 0.45, 0.6, 0.0))
	_add("radio", _radio())
	_add("gun", _airgun())
	_add("pass", _tone(980.0, 0.12, 0.25, 420.0))
	_add("flag", _chime())
	var gen = AudioStreamGenerator.new()
	gen.mix_rate = RATE
	gen.buffer_length = 0.2
	_drone = AudioStreamPlayer.new()
	_drone.stream = gen
	_drone.volume_db = -14.0
	add_child(_drone)
	_drone.play()
	_pb = _drone.get_stream_playback()


func play(name: String) -> void:
	if muted or not _players.has(name):
		return
	_players[name].play()


func set_engine(level: float) -> void:
	_engine_target = clampf(level, 0.0, 1.0)


func _process(delta: float) -> void:
	_engine = lerpf(_engine, 0.0 if muted else _engine_target, clampf(delta * 3.0, 0.0, 1.0))
	if _pb == null:
		return
	# 배경음: 여러 대의 엔진이 섞인 낮은 웅웅거림 + 바람 소리
	var n: int = _pb.get_frames_available()
	var f1 := 92.0 + 40.0 * _engine
	var f2 := f1 * 1.51
	for i in n:
		_ph1 = fposmod(_ph1 + f1 / RATE, 1.0)
		_ph2 = fposmod(_ph2 + f2 / RATE, 1.0)
		_lp = lerpf(_lp, _rng.randf_range(-1.0, 1.0), 0.08)
		var v := ((_ph1 * 2.0 - 1.0) * 0.5 + (_ph2 * 2.0 - 1.0) * 0.3 + _lp * 0.9) * 0.22 * _engine
		_pb.push_frame(Vector2(v, v))


func _add(name: String, stream: AudioStreamWAV) -> void:
	var p = AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = -6.0
	add_child(p)
	_players[name] = p


func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var w = AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w


func _tone(freq: float, dur: float, vol: float, slide: float) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		ph += (freq + slide * t / dur) / RATE
		var env := minf(1.0, t / 0.01) * (1.0 - t / dur)
		s[i] = sin(TAU * ph) * vol * env
	return _wav(s)


func _radio() -> AudioStreamWAV:
	# 무전 '치직' + 짧은 삐
	var n := int(0.28 * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		var v := 0.0
		if t < 0.09:
			v = _rng.randf_range(-1.0, 1.0) * 0.35 * (1.0 - t / 0.09)
		elif t > 0.12 and t < 0.24:
			v = sin(TAU * 1450.0 * t) * 0.25
		s[i] = v
	return _wav(s)


func _airgun() -> AudioStreamWAV:
	# 휠건 '드르륵' 4번
	var n := int(1.2 * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		var burst := fposmod(t, 0.3)
		var v := 0.0
		if burst < 0.16:
			var buzz := 1.0 if fposmod(t * 180.0, 1.0) < 0.5 else -1.0
			v = (buzz * 0.25 + _rng.randf_range(-1.0, 1.0) * 0.25) * (1.0 - burst / 0.16)
		s[i] = v
	return _wav(s)


func _chime() -> AudioStreamWAV:
	# 체커기: 세 음 상승
	var n := int(0.9 * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var notes := [784.0, 988.0, 1175.0]
	for i in n:
		var t := float(i) / RATE
		var k: int = mini(2, int(t / 0.22))
		var lt := t - k * 0.22
		s[i] = sin(TAU * notes[k] * t) * 0.4 * exp(-lt * 5.0)
	return _wav(s)
