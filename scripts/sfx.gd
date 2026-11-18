extends Node
## Sound effects player. Registered as the "Sfx" autoload in project.godot.
## Usage: Sfx.play("enemy_die")  or  Sfx.play("hit", -8.0, 0.1)
## To swap a sound, replace the matching .wav file in res://sounds/.

const NAMES := [
	"shoot", "hit", "enemy_die", "brute_die", "crate_hit", "powerup", "squad_hurt",
	"shield_block", "boss_alarm", "boss_hit", "boss_die", "victory", "defeat",
	"level_start", "tally_tick", "tally_row", "tally_total", "coins", "click", "new_best",
	"super_spawn", "super_pickup", "super_blast", "super_zap", "explosion",
]

## Base volume (dB) per sound, so frequent sounds don't drown out important ones.
const VOLUME := {
	"shoot": -17.0, "hit": -13.0, "enemy_die": -8.0, "brute_die": -4.0, "crate_hit": -11.0,
	"powerup": -4.0, "squad_hurt": -3.0, "shield_block": -5.0, "boss_alarm": -5.0,
	"boss_hit": -9.0, "boss_die": -1.0, "victory": -3.0, "defeat": -3.0, "level_start": -6.0,
	"tally_tick": -12.0, "tally_row": -8.0, "tally_total": -4.0, "coins": -5.0,
	"click": -8.0, "new_best": -4.0,
	"super_spawn": -3.0, "super_pickup": -2.0, "super_blast": 0.0, "super_zap": -15.0, "explosion": -6.0,
}

## Minimum seconds between two plays of the same sound (stops machine-gun stacking).
const MIN_GAP := {
	"shoot": 0.07, "hit": 0.035, "enemy_die": 0.03, "crate_hit": 0.05,
	"boss_hit": 0.08, "tally_tick": 0.04, "squad_hurt": 0.08,
	"super_zap": 0.05, "explosion": 0.045,
}

## Random pitch wobble per sound (0.05 = +/-5%) so repeats sound less robotic.
const PITCH_VAR := {
	"shoot": 0.08, "hit": 0.12, "enemy_die": 0.12, "brute_die": 0.06, "crate_hit": 0.08,
	"boss_hit": 0.08, "squad_hurt": 0.05, "click": 0.05,
	"super_zap": 0.15, "explosion": 0.2,
}

const VOICES := 24

var enabled := true
var master_db := 0.0
var _streams := {}
var _players: Array = []
var _next := 0
var _last := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for n in NAMES:
		var path := "res://sounds/%s.wav" % n
		if ResourceLoader.exists(path):
			_streams[n] = load(path)
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)


func play(sound: String, volume_offset := 0.0, pitch := 1.0) -> void:
	if not enabled or not _streams.has(sound):
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_last.get(sound, -10.0)) < float(MIN_GAP.get(sound, 0.0)):
		return
	_last[sound] = now
	var p: AudioStreamPlayer = _pick_player()
	var pv: float = PITCH_VAR.get(sound, 0.0)
	p.stream = _streams[sound]
	p.volume_db = master_db + float(VOLUME.get(sound, 0.0)) + volume_offset
	p.pitch_scale = pitch * randf_range(1.0 - pv, 1.0 + pv)
	p.play()


func _pick_player() -> AudioStreamPlayer:
	for i in VOICES:
		var idx := (_next + i) % VOICES
		if not _players[idx].playing:
			_next = (idx + 1) % VOICES
			return _players[idx]
	# All busy: steal the next one in line.
	var p: AudioStreamPlayer = _players[_next]
	_next = (_next + 1) % VOICES
	return p
