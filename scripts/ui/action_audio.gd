extends Node
## Quiet, opt-in PCM cues. No idle machinery loop or simulated alarm soundtrack.

var enabled: bool = false
var play_count: int = 0
var player: AudioStreamPlayer
var clips: Dictionary = {}
const FREQUENCIES := {"hoe": 185.0, "sow": 470.0, "water": 320.0, "harvest": 660.0, "refill": 390.0}


func _ready() -> void:
	player = AudioStreamPlayer.new()
	player.volume_db = -20
	add_child(player)
	for id in FREQUENCIES: clips[id] = tone(FREQUENCIES[id])


static func tone(frequency: float) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	var count: int = 2205
	var data := PackedByteArray()
	data.resize(count * 2)
	for index in range(count):
		var t := float(index) / stream.mix_rate
		var envelope := minf(1.0, float(index) / 100.0) * pow(1.0 - float(index) / count, 2)
		var sample := int(sin(TAU * frequency * t) * envelope * 14000.0)
		data.encode_s16(index * 2, sample)
	stream.data = data
	return stream


func action(result: Dictionary) -> void:
	if not enabled or not result.ok or not result.changed or not clips.has(result.code): return
	player.stream = clips[result.code]
	player.play()
	play_count += 1


func toggle() -> void:
	enabled = not enabled
	if not enabled and player != null: player.stop()
