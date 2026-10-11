extends Node
## Autoload "AudioManager". Buses (resources/default_bus_layout.tres):
##   Master — hard limiter at -1 dB, so stacked moments can never clip;
##   Music  — a compressor keyed by the Voice bus: the music dips while a voice line speaks;
##   SFX    — effects (10-voice pool, the same sound retriggered within 34 ms is dropped);
##   Voice  — one voice line at a time, never overlapping.
## Music crossfades between tracks (normal ↔ HARD). In the background and while a full-screen ad
## shows, music is paused — never restarted — so returning never doubles or restarts a track.
const VOICES := 10
## The same stream retriggered faster than this is dropped: rapid taps never stack into clipping.
const SAME_SOUND_GAP_MS := 34
const FADE_SECONDS := 1.2
const SILENT_DB := -40.0

var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _active: AudioStreamPlayer
var _fade: Tween
var _voice: AudioStreamPlayer
var _voices: Array[AudioStreamPlayer] = []
var _next_voice := 0
var _suspended := false
var _last_played := {}
var _duck_db := 0.0:
	set(value):
		_duck_db = value
		_apply_music_volume()
var _duck_tween: Tween

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for bus in ["Music", "SFX", "Voice"]:
		if AudioServer.get_bus_index(bus) == -1:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus)
			AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")
	_music_a = _player(&"Music")
	_music_b = _player(&"Music")
	_active = _music_a
	_voice = _player(&"Voice")
	for index in VOICES:
		_voices.append(_player(&"SFX"))
	SettingsManager.changed.connect(_settings_changed)
	_apply_settings()

func _exit_tree() -> void:
	if _fade != null and _fade.is_valid():
		_fade.kill()
	Feel.release_cache()
	for player in [_music_a, _music_b, _voice]:
		player.stop()
		player.stream = null

func _player(bus: StringName) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.bus = bus
	add_child(player)
	return player

func _settings_changed(_key: String, _value: Variant) -> void:
	_apply_settings()

func _apply_settings() -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), linear_to_db(maxf(float(SettingsManager.get_value("master_volume")), 0.0001)))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), linear_to_db(maxf(float(SettingsManager.get_value("sfx_volume")), 0.0001)))
	# Voice follows the effects volume, slightly forward so short words stay clear over effects.
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Voice"), linear_to_db(maxf(float(SettingsManager.get_value("sfx_volume")), 0.0001)) + 1.0)
	_apply_music_volume()
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Music"), not SettingsManager.get_value("music"))
	AudioServer.set_bus_mute(AudioServer.get_bus_index("SFX"), not SettingsManager.get_value("sound"))
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Voice"), not voice_enabled())

func _apply_music_volume() -> void:
	var base := linear_to_db(maxf(float(SettingsManager.get_value("music_volume")), 0.0001))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), base + _duck_db)

func voice_enabled() -> bool:
	var value: Variant = SettingsManager.get_value("voice")
	return value == null or bool(value)

## Crossfades to `stream` (null stops the music). The same track already playing is left untouched.
func play_music(stream: AudioStream, fade: float = FADE_SECONDS) -> void:
	if _fade != null and _fade.is_valid():
		_fade.kill()
	if stream == null:
		for player in [_music_a, _music_b]:
			player.stop()
			player.stream = null
		return
	if _active.stream == stream and _active.playing:
		_active.volume_db = 0.0
		var other := _music_b if _active == _music_a else _music_a
		other.stop()
		return
	var previous := _active
	var next := _music_b if _active == _music_a else _music_a
	next.stream = stream
	next.volume_db = SILENT_DB if previous.playing and fade > 0.0 else 0.0
	next.play()
	next.stream_paused = _suspended
	_active = next
	if not previous.playing or fade <= 0.0:
		previous.stop()
		next.volume_db = 0.0
		return
	_fade = create_tween().set_parallel()
	_fade.tween_property(next, "volume_db", 0.0, fade).set_trans(Tween.TRANS_SINE)
	_fade.tween_property(previous, "volume_db", SILENT_DB, fade).set_trans(Tween.TRANS_SINE)
	_fade.chain().tween_callback(previous.stop)

func current_music() -> AudioStream:
	return _active.stream if _active.playing else null

func play_sfx(stream: AudioStream, pitch: float = 1.0, volume_db: float = 0.0) -> void:
	if stream == null or _suspended or not SettingsManager.get_value("sound"):
		return
	var now := Time.get_ticks_msec()
	var key := stream.get_instance_id()
	if now - int(_last_played.get(key, -100000)) < SAME_SOUND_GAP_MS:
		return
	_last_played[key] = now
	var voice := _voices[_next_voice]
	_next_voice = (_next_voice + 1) % VOICES
	voice.stream = stream
	voice.pitch_scale = clampf(pitch, 0.5, 2.0)
	voice.volume_db = volume_db
	voice.play()

## Plays one voice line unless another is still speaking. Returns whether it started.
func play_voice(stream: AudioStream, volume_db: float = 0.0) -> bool:
	if stream == null or _suspended or not voice_enabled() or _voice.playing:
		return false
	_voice.stream = stream
	_voice.volume_db = volume_db
	_voice.play()
	return true

func is_voice_playing() -> bool:
	return _voice.playing

## Briefly lowers the music under a big jingle, then restores it.
func duck_music(amount_db: float = -6.0, hold: float = 1.2) -> void:
	if _duck_tween != null and _duck_tween.is_valid():
		_duck_tween.kill()
	_duck_tween = create_tween()
	_duck_tween.tween_property(self, "_duck_db", amount_db, 0.12)
	_duck_tween.tween_interval(hold)
	_duck_tween.tween_property(self, "_duck_db", 0.0, 0.6)

func set_suspended(value: bool) -> void:
	_suspended = value
	for player in [_music_a, _music_b]:
		player.stream_paused = value
	if value:
		for voice in _voices:
			voice.stop()
		_voice.stop()
