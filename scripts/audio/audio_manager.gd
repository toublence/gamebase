extends Node
const VOICES := 6
var _music: AudioStreamPlayer
var _voices: Array[AudioStreamPlayer] = []
var _next_voice := 0
var _suspended := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for bus in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bus) == -1:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus)
			AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")
	_music = AudioStreamPlayer.new()
	_music.bus = &"Music"
	add_child(_music)
	for index in VOICES:
		var voice := AudioStreamPlayer.new()
		voice.bus = &"SFX"
		add_child(voice)
		_voices.append(voice)
	SettingsManager.changed.connect(_settings_changed)
	_apply_settings()

func _settings_changed(_key: String, _value: Variant) -> void:
	_apply_settings()

func _apply_settings() -> void:
	for pair in [["Master", "master_volume"], ["Music", "music_volume"], ["SFX", "sfx_volume"]]:
		var volume := float(SettingsManager.get_value(pair[1]))
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index(pair[0]), linear_to_db(maxf(volume, 0.0001)))
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Music"), not SettingsManager.get_value("music"))
	AudioServer.set_bus_mute(AudioServer.get_bus_index("SFX"), not SettingsManager.get_value("sound"))

func play_music(stream: AudioStream) -> void:
	if stream == null:
		_music.stop()
		_music.stream = null
		return
	if _music.stream == stream and _music.playing:
		return
	_music.stream = stream
	_music.play()
	_music.stream_paused = _suspended

func play_sfx(stream: AudioStream) -> void:
	if stream == null or _suspended or not SettingsManager.get_value("sound"):
		return
	var voice := _voices[_next_voice]
	_next_voice = (_next_voice + 1) % VOICES
	voice.stream = stream
	voice.play()

func set_suspended(value: bool) -> void:
	_suspended = value
	_music.stream_paused = value
	if value:
		for voice in _voices:
			voice.stop()
