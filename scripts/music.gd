extends Node
## Background music with crossfading. Registered as the "Music" autoload.
## Usage: Music.play("menu")   Music.stop()   Music.set_duck(-10.0)
## Tracks live in res://music/<name>.ogg and loop seamlessly.

const TRACKS := ["menu", "rock", "techno", "chiptune", "boss"]
## Gameplay tracks rotate by level: level 1 = rock, 2 = techno, 3 = chiptune, 4 = rock, ...
const LEVEL_TRACKS := ["rock", "techno", "chiptune"]
## Per-track volume in dB (music sits under the sound effects).
const VOLUME := {"menu": -9.0, "rock": -8.0, "techno": -10.5, "chiptune": -9.5, "boss": -8.0}
const SILENT := -60.0

var enabled := true
var current := ""
var _streams := {}
var _a: AudioStreamPlayer
var _b: AudioStreamPlayer
var _active: AudioStreamPlayer
var _duck := 0.0
var _tween: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for n in TRACKS:
		var path := "res://music/%s.ogg" % n
		if ResourceLoader.exists(path):
			var st = load(path)
			if st is AudioStreamOggVorbis:
				st.loop = true
			_streams[n] = st
	_a = AudioStreamPlayer.new()
	_b = AudioStreamPlayer.new()
	add_child(_a)
	add_child(_b)
	_active = _a


func level_track(level: int) -> String:
	return LEVEL_TRACKS[(maxi(level, 1) - 1) % LEVEL_TRACKS.size()]


func play(track: String, fade := 1.0) -> void:
	if track == current and _active.playing:
		return
	current = track
	if not enabled or not _streams.has(track):
		return
	var old := _active
	var nxt := _b if _active == _a else _a
	_active = nxt
	nxt.stream = _streams[track]
	nxt.volume_db = SILENT
	nxt.play()
	_new_tween()
	_tween.tween_property(nxt, "volume_db", _target_db(), fade)
	if old.playing:
		_tween.tween_property(old, "volume_db", SILENT, fade)
		_tween.chain().tween_callback(old.stop)


func stop(fade := 0.8) -> void:
	current = ""
	_new_tween()
	for p in [_a, _b]:
		if p.playing:
			_tween.tween_property(p, "volume_db", SILENT, fade)
	_tween.chain().tween_callback(func():
		if current == "":
			_a.stop()
			_b.stop()
	)


## Lower (negative dB) or restore (0) the music, e.g. while paused.
func set_duck(db: float, fade := 0.3) -> void:
	_duck = db
	if _active.playing and current != "":
		_new_tween()
		_tween.tween_property(_active, "volume_db", _target_db(), fade)
		var other := _b if _active == _a else _a
		if other.playing:
			_tween.tween_property(other, "volume_db", SILENT, fade)
			_tween.chain().tween_callback(other.stop)


func set_enabled(on: bool) -> void:
	enabled = on
	if not on:
		if _tween and _tween.is_valid():
			_tween.kill()
		_a.stop()
		_b.stop()
	elif current != "":
		var track := current
		current = ""
		play(track, 0.5)


func _target_db() -> float:
	return float(VOLUME.get(current, -9.0)) + _duck


func _new_tween() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_parallel(true)
