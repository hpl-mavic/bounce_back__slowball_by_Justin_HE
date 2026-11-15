extends Node
## 音效管理器
##
## 音效都是程序生成的 WAV（tools/make_sfx.gd），放在 assets/sfx/ 下。
## 想换成自己的音效：同名覆盖即可，代码不用改。

const DIR := "res://assets/sfx/"
const NAMES := [
	"launch", "bounce", "ram", "hurt", "shield",
	"break", "shot", "upgrade", "win", "lose", "ui", "crack", "death",
]
const VOICES := 12            # 同时能响几个（超过就抢最早的那个）
const BASE_DB := -9.0         # 默认音量

var streams: Dictionary = {}
var players: Array[AudioStreamPlayer] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for n in NAMES:
		var path: String = DIR + str(n) + ".wav"
		if ResourceLoader.exists(path):
			streams[n] = load(path)
	for i in VOICES:
		var ap := AudioStreamPlayer.new()
		ap.volume_db = BASE_DB
		add_child(ap)
		players.append(ap)


func play(name: String, vol_db: float = 0.0, pitch: float = 1.0) -> void:
	var s: AudioStream = streams.get(name)
	if s == null:
		return
	for ap in players:
		if not ap.playing:
			_fire(ap, s, vol_db, pitch)
			return
	_fire(players[0], s, vol_db, pitch)


func _fire(ap: AudioStreamPlayer, s: AudioStream, vol_db: float, pitch: float) -> void:
	ap.stream = s
	ap.volume_db = BASE_DB + vol_db
	ap.pitch_scale = clampf(pitch, 0.5, 2.0)
	ap.play()
