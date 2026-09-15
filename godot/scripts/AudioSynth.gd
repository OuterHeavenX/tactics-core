# ============================================================================
# Procedural sound effects and music.
#
# Every sound is synthesised into an AudioStreamWAV at load time, so the export
# ships no audio assets at all — which keeps the web build small and means the
# game makes noise the instant it boots, with nothing to stream.
# ============================================================================
class_name AudioSynth
extends Node

const RATE := 22050

var sfx_bus: Array[AudioStreamPlayer] = []
var music_player: AudioStreamPlayer
var _next := 0
var _cache: Dictionary = {}
var sound_on := true
var music_on := true

func _ready() -> void:
	# A small pool so overlapping hits do not cut each other off.
	for i in 6:
		var p := AudioStreamPlayer.new()
		p.volume_db = -6.0
		add_child(p)
		sfx_bus.append(p)
	music_player = AudioStreamPlayer.new()
	music_player.volume_db = -17.0
	add_child(music_player)
	_build_music()

func set_sound(on: bool) -> void:
	sound_on = on
func set_music(on: bool) -> void:
	music_on = on
	if on:
		if not music_player.playing:
			music_player.play()
	else:
		music_player.stop()

func play(name: String) -> void:
	if not sound_on:
		return
	if not _cache.has(name):
		_cache[name] = _build(name)
	var stream: AudioStreamWAV = _cache[name]
	if stream == null:
		return
	var p := sfx_bus[_next]
	_next = (_next + 1) % sfx_bus.size()
	p.stream = stream
	p.play()

# --------------------------------------------------------------- synthesis --
func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		var v := int(clampf(samples[i], -1.0, 1.0) * 32000.0)
		data.encode_s16(i * 2, v)
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = data
	return s

## One decaying oscillator. `slide` sweeps the pitch over the note's life.
func _tone(buf: PackedFloat32Array, start: float, dur: float, freq: float,
		slide: float, gain: float, wave: String) -> void:
	var n := int(dur * RATE)
	var offset := int(start * RATE)
	var phase := 0.0
	for i in n:
		var idx := offset + i
		if idx >= buf.size():
			break
		var t := float(i) / n
		var f: float = lerpf(freq, slide if slide > 0.0 else freq, t)
		phase += TAU * f / RATE
		var v := 0.0
		match wave:
			"square": v = 1.0 if sin(phase) > 0.0 else -1.0
			"saw": v = fmod(phase, TAU) / PI - 1.0
			"tri": v = asin(sin(phase)) * (2.0 / PI)
			_: v = sin(phase)
		buf[idx] += v * gain * pow(1.0 - t, 2.0)

func _noise(buf: PackedFloat32Array, start: float, dur: float, gain: float) -> void:
	var n := int(dur * RATE)
	var offset := int(start * RATE)
	var last := 0.0
	for i in n:
		var idx := offset + i
		if idx >= buf.size():
			break
		var t := float(i) / n
		# One-pole lowpass turns white noise into something percussive.
		last = lerpf(last, randf_range(-1.0, 1.0), 0.35)
		buf[idx] += last * gain * (1.0 - t)

func _buffer(seconds: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(seconds * RATE))
	b.fill(0.0)
	return b

func _build(name: String) -> AudioStreamWAV:
	var b: PackedFloat32Array
	match name:
		"select":
			b = _buffer(0.08); _tone(b, 0, 0.06, 680, 0, 0.3, "square")
		"cancel":
			b = _buffer(0.1); _tone(b, 0, 0.08, 300, 0, 0.28, "square")
		"move":
			b = _buffer(0.07); _tone(b, 0, 0.05, 420, 0, 0.25, "tri")
		"hit":
			b = _buffer(0.2); _noise(b, 0, 0.16, 0.5); _tone(b, 0, 0.12, 160, 70, 0.35, "saw")
		"crit":
			b = _buffer(0.35); _noise(b, 0, 0.22, 0.6); _tone(b, 0, 0.18, 240, 60, 0.45, "saw")
			_tone(b, 0.06, 0.1, 900, 0, 0.3, "square")
		"miss":
			b = _buffer(0.12); _tone(b, 0, 0.1, 520, 300, 0.22, "sine")
		"magic":
			b = _buffer(0.4); _tone(b, 0, 0.28, 520, 1500, 0.3, "sine")
			_tone(b, 0.07, 0.22, 780, 1900, 0.24, "sine")
		"heal":
			b = _buffer(0.5); _tone(b, 0, 0.18, 660, 0, 0.3, "sine")
			_tone(b, 0.09, 0.22, 880, 0, 0.26, "sine"); _tone(b, 0.18, 0.26, 1180, 0, 0.2, "sine")
		"ko":
			b = _buffer(0.55); _tone(b, 0, 0.5, 220, 60, 0.4, "saw"); _noise(b, 0, 0.4, 0.4)
		"levelup":
			b = _buffer(0.6)
			var up := [523.0, 659.0, 784.0, 1046.0]
			for i in up.size():
				_tone(b, i * 0.085, 0.2, up[i], 0, 0.3, "square")
		"victory":
			b = _buffer(1.1)
			var win := [523.0, 659.0, 784.0, 1046.0, 1318.0]
			for i in win.size():
				_tone(b, i * 0.13, 0.34, win[i], 0, 0.34, "tri")
		"defeat":
			b = _buffer(1.3)
			var lose := [392.0, 349.0, 311.0, 233.0]
			for i in lose.size():
				_tone(b, i * 0.19, 0.5, lose[i], 0, 0.3, "saw")
		"turn":
			b = _buffer(0.09); _tone(b, 0, 0.07, 880, 0, 0.2, "sine")
		"boss":
			b = _buffer(0.9); _tone(b, 0, 0.8, 90, 0, 0.45, "saw"); _noise(b, 0, 0.8, 0.3)
		_:
			return null
	return _wav(b)

## Eight-bar minor-key ostinato, rendered once and looped.
func _build_music() -> void:
	var bars := 8.0
	var beat := 0.25
	var b := _buffer(bars * 4.0 * beat)
	var scale := [220.0, 246.9, 261.6, 293.7, 329.6, 349.2, 392.0, 440.0]
	var bass := [110.0, 110.0, 146.8, 130.8]
	var steps := int(bars * 4)
	for s in steps:
		var t := s * beat
		if s % 4 == 0:
			_tone(b, t, 0.55, bass[(s / 4) % 4], 0, 0.42, "tri")
		if s % 2 == 0:
			_tone(b, t, 0.26, scale[(s * 3 + s / 8) % scale.size()] * 2.0, 0, 0.2, "sine")
		if s % 8 == 6:
			_tone(b, t, 0.2, scale[(s / 2) % scale.size()] * 4.0, 0, 0.1, "sine")
	var stream := _wav(b)
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = b.size()
	music_player.stream = stream
	if music_on:
		music_player.play()
