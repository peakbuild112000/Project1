extends Node
class_name ProceduralSfx

## Fully procedural sound effects. Every sample is synthesized into an
## AudioStreamWAV at startup, so the project has no audio asset dependencies.

const SAMPLE_RATE := 22050
const POLYPHONY := 10

var _players: Array[AudioStreamPlayer] = []
var _next_player := 0
var _streams: Dictionary = {}


func _ready() -> void:
	for i in range(POLYPHONY):
		var player := AudioStreamPlayer.new()
		player.name = "Voice%d" % i
		add_child(player)
		_players.append(player)


func play(name: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if _players.is_empty():
		return
	var stream := get_stream(name)
	if stream == null:
		return
	var player: AudioStreamPlayer = _players[_next_player]
	_next_player = (_next_player + 1) % _players.size()
	if player.playing:
		player.stop()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = clampf(pitch, 0.1, 4.0)
	player.play()


func get_stream(name: String) -> AudioStreamWAV:
	var key := name.to_lower().strip_edges()
	if _streams.has(key):
		return _streams[key]
	var stream: AudioStreamWAV
	match key:
		"anchor", "grab", "attach":
			stream = _build_anchor()
		"shoot", "fire", "launch":
			stream = _build_shoot()
		"stretch", "stretch_warning", "overstretch", "warning":
			stream = _build_warning()
		"ragdoll", "thud", "ragdoll_thud":
			stream = _build_thud()
		"recover", "recovery":
			stream = _build_recover()
		"checkpoint":
			stream = _build_checkpoint()
		"countdown", "beep", "tick":
			stream = _build_tone(660.0, 0.13, 0.42)
		"go", "start":
			stream = _build_go()
		"summit", "win", "victory":
			stream = _build_summit()
		"fall", "death", "lose":
			stream = _build_fall()
		_:
			stream = _build_tone(440.0, 0.10, 0.28)
	_streams[key] = stream
	return stream


func _write_sample(data: PackedByteArray, offset: int, value: float) -> void:
	var sample := clampi(int(value * 32767.0), -32768, 32767)
	data[offset] = sample & 0xFF
	data[offset + 1] = (sample >> 8) & 0xFF


func _make_stream(duration: float, generator: Callable) -> AudioStreamWAV:
	var frames := maxi(1, int(duration * float(SAMPLE_RATE)))
	var data := PackedByteArray()
	data.resize(frames * 2)
	for i in range(frames):
		var t := float(i) / float(SAMPLE_RATE)
		var value := float(generator.call(t, i, frames))
		_write_sample(data, i * 2, clampf(value, -1.0, 1.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	wav.data = data
	return wav


func _noise(t: float) -> float:
	var x := sin(t * 127.1 + 3.7) * 43758.5453
	return (x - floor(x)) * 2.0 - 1.0


func _tone(t: float, frequency: float, phase: float = 0.0) -> float:
	return sin(TAU * frequency * t + phase)


func _build_tone(frequency: float, duration: float, volume: float) -> AudioStreamWAV:
	return _make_stream(duration, func(t: float, _i: int, _n: int) -> float:
		var attack := clampf(t / 0.008, 0.0, 1.0)
		var envelope := attack * exp(-t * 9.0)
		return _tone(t, frequency) * envelope * volume
	)


func _build_anchor() -> AudioStreamWAV:
	return _make_stream(0.11, func(t: float, _i: int, _n: int) -> float:
		var envelope := exp(-t * 26.0)
		var frequency := lerpf(1250.0, 380.0, clampf(t / 0.11, 0.0, 1.0))
		return (_tone(t, frequency) * 0.72 + _noise(t) * 0.28) * envelope * 0.6
	)


func _build_shoot() -> AudioStreamWAV:
	return _make_stream(0.20, func(t: float, _i: int, _n: int) -> float:
		var p := clampf(t / 0.20, 0.0, 1.0)
		var envelope := sin(PI * p) * exp(-t * 3.0)
		var sweep := _tone(t, lerpf(1500.0, 260.0, p))
		return (sweep * 0.45 + _noise(t) * 0.55) * envelope * 0.55
	)


func _build_warning() -> AudioStreamWAV:
	return _make_stream(0.26, func(t: float, _i: int, _n: int) -> float:
		var pulse := 1.0 if sin(TAU * 11.0 * t) > 0.0 else 0.35
		var envelope := clampf(t / 0.004, 0.0, 1.0) * clampf((0.26 - t) / 0.03, 0.0, 1.0)
		return (_tone(t, 1180.0) * 0.7 + _tone(t, 890.0) * 0.3) * pulse * envelope * 0.34
	)


func _build_thud() -> AudioStreamWAV:
	return _make_stream(0.38, func(t: float, _i: int, _n: int) -> float:
		var body := _tone(t, lerpf(115.0, 42.0, clampf(t / 0.38, 0.0, 1.0))) * exp(-t * 9.0)
		var grit := _noise(t) * exp(-t * 24.0) * 0.42
		return (body * 0.85 + grit) * 0.75
	)


func _build_recover() -> AudioStreamWAV:
	return _make_stream(0.34, func(t: float, _i: int, _n: int) -> float:
		var p := clampf(t / 0.34, 0.0, 1.0)
		var envelope := sin(PI * p) * 0.55
		return (_tone(t, lerpf(280.0, 880.0, p)) + _tone(t, lerpf(560.0, 1320.0, p)) * 0.25) * envelope
	)


func _build_checkpoint() -> AudioStreamWAV:
	var notes := [523.25, 659.25, 783.99, 1046.5]
	return _make_stream(0.52, func(t: float, _i: int, _n: int) -> float:
		var index := mini(int(t / 0.13), notes.size() - 1)
		var local := t - float(index) * 0.13
		var envelope := clampf(local / 0.005, 0.0, 1.0) * exp(-local * 16.0)
		return (_tone(local, float(notes[index])) + _tone(local, float(notes[index]) * 2.0) * 0.2) * envelope * 0.36
	)


func _build_go() -> AudioStreamWAV:
	return _make_stream(0.32, func(t: float, _i: int, _n: int) -> float:
		var envelope := clampf(t / 0.006, 0.0, 1.0) * exp(-t * 5.0)
		return (_tone(t, 990.0) * 0.62 + _tone(t, 1320.0) * 0.3 + _tone(t, 1980.0) * 0.08) * envelope * 0.6
	)


func _build_summit() -> AudioStreamWAV:
	var notes := [523.25, 659.25, 783.99, 1046.5, 1318.5]
	return _make_stream(1.05, func(t: float, _i: int, _n: int) -> float:
		var index := mini(int(t / 0.17), notes.size() - 1)
		var local := t - float(index) * 0.17
		var pluck := (_tone(local, float(notes[index])) + _tone(local, float(notes[index]) * 0.5) * 0.35) * exp(-local * 3.4)
		var pad := (_tone(t, 261.63) + _tone(t, 392.0)) * 0.12 * clampf(t / 0.3, 0.0, 1.0)
		return (pluck * 0.34 + pad) * clampf((1.05 - t) / 0.12, 0.0, 1.0)
	)


func _build_fall() -> AudioStreamWAV:
	return _make_stream(0.78, func(t: float, _i: int, _n: int) -> float:
		var p := clampf(t / 0.78, 0.0, 1.0)
		var envelope := clampf(t / 0.015, 0.0, 1.0) * exp(-t * 2.2)
		var whistle := _tone(t, lerpf(760.0, 90.0, p)) * 0.55
		return (whistle + _noise(t) * 0.35 * p) * envelope * 0.55
	)
