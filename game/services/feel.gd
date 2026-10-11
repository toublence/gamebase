class_name Feel
extends RefCounted
## Sound, voice and haptic pairing for game events. Escape and collision use clearly different
## vibrations (short and crisp vs. longer and soft) so they stay distinguishable with the sound off.
##
## Voice cheers (AI-synthesized, see assets/voice/README.md) are used only at key moments — a stage
## clear, a move that opens several exits at once ("wow"), a league promotion — never twice within
## VOICE_GAP_MS and never over another voice line. Cheers are always the English takes ("Wow!",
## "Nice!") whatever the UI language, since Outtap is a global game. The voice setting turned off
## keeps the same moments with sound effects and visuals only.
const TAP := preload("res://assets/audio/tap.wav")
const SLIDE_SHORT := preload("res://assets/audio/slide_short.wav")
const SLIDE := preload("res://assets/audio/slide.wav")
const SLIDE_LONG := preload("res://assets/audio/slide_long.wav")
const PATH := preload("res://assets/audio/path.wav")
const BUMP := preload("res://assets/audio/bump.wav")
const LIFE := preload("res://assets/audio/life.wav")
const STREAK := preload("res://assets/audio/combo.wav")
const CLEAR := preload("res://assets/audio/clear.wav")
const CLEAR_SMALL := preload("res://assets/audio/clear_small.wav")
const CLEAR_HARD := preload("res://assets/audio/clear_hard.wav")
const FAIL := preload("res://assets/audio/fail.wav")
const HINT := preload("res://assets/audio/hint.wav")
const UNLOCK := preload("res://assets/audio/unlock.wav")
const GOLD := preload("res://assets/audio/gold.wav")
const HARD_INTRO := preload("res://assets/audio/hard_intro.wav")
const PROMOTE := preload("res://assets/audio/promote.wav")
const WOW := preload("res://assets/audio/wow.wav")
const MUSIC_TENSE := "res://assets/audio/music_tense.ogg"
const MUSIC_HARD := "res://assets/audio/music_hard.ogg"
## Consecutive escapes climb a major pentatonic scale (in semitones) and then hold, so long streaks
## stay musical instead of shrill.
const STREAK_STEPS := [0, 2, 4, 7, 9, 12, 14]
const VOICE_LANG := "en"
const VOICE_GAP_MS := 2500
const WOW_GAP_MS := 12000
const CLEAR_LINES := ["good", "nice", "yes"]

static var _last_voice_ms := -100000
static var _last_wow_ms := -100000
static var _clear_line := 0
static var _voice_cache := {}

static func tap() -> void:
	AudioManager.play_sfx(TAP, 1.0, -16.0)
	HapticManager.pulse(8, 0.22)

## Length picks the slide (short flick, medium swoosh, long sweep); the streak raises the pitch. When
## the move opened an exit for other arrows a quiet airy lift sits under it.
static func escape(streak: int, length: int, opened: int = 0) -> void:
	var step: int = STREAK_STEPS[clampi(streak - 1, 0, STREAK_STEPS.size() - 1)]
	var pitch := pow(2.0, step / 12.0) * (1.0 - clampf((length - 4) * 0.008, 0.0, 0.05))
	var stream: AudioStream = SLIDE_SHORT if length <= 3 else (SLIDE if length <= 7 else SLIDE_LONG)
	AudioManager.play_sfx(stream, pitch, -7.0)
	if opened > 0:
		AudioManager.play_sfx(PATH, 1.0 + mini(opened, 4) * 0.05, -16.0 + mini(opened, 3) * 1.5)
	HapticManager.pulse(12, 0.5)

static func streak(count: int) -> void:
	AudioManager.play_sfx(STREAK, 1.0 + minf(count, 20) * 0.008, -13.0)

static func bump(life_lost: bool) -> void:
	AudioManager.play_sfx(BUMP, 1.0, -11.0)
	if life_lost:
		AudioManager.play_sfx(LIFE, 1.0, -13.0)
	HapticManager.pulse(40, 0.2)

## One star filling in on the clear sheet (rising pitch for the 2nd and 3rd).
static func star(i: int) -> void:
	AudioManager.play_sfx(STREAK, 1.0 + i * 0.12, -10.0)
	HapticManager.pulse(10, 0.3)

static func gold() -> void:
	AudioManager.play_sfx(GOLD, 1.0, -9.0)
	HapticManager.pulse(14, 0.35)

## A move that opened several exits at once. Returns whether the moment was played (rate limited).
static func wow() -> bool:
	var now := Time.get_ticks_msec()
	if now - _last_wow_ms < WOW_GAP_MS:
		return false
	_last_wow_ms = now
	AudioManager.play_sfx(WOW, 1.0, -9.0)
	voice("wow")
	HapticManager.success()
	return true

static func hard_intro() -> void:
	AudioManager.play_sfx(HARD_INTRO, 1.0, -7.0)
	HapticManager.pulse(30, 0.3)

## Stage clear: the jingle, then one exclamation (no words, just cheers). HARD stages get the bigger
## fanfare and "bravo", the chapter final "yahoo", a clear without mistakes "woo"; otherwise the
## cheer rotates (good, nice, yes).
static func clear(arrow_count: int, hard: bool = false, perfect: bool = false, final: bool = false) -> void:
	if hard:
		AudioManager.play_sfx(CLEAR_HARD, 1.0, -5.0)
		AudioManager.duck_music(-8.0, 1.8)
	else:
		# Small boards get a lighter flourish than full boards.
		AudioManager.play_sfx(CLEAR if arrow_count >= 8 else CLEAR_SMALL, 1.0, -6.0)
		AudioManager.duck_music(-5.0, 1.0)
	HapticManager.success()
	var line: String = "yahoo" if final else ("bravo" if hard else ("woo" if perfect else str(CLEAR_LINES[_clear_line % CLEAR_LINES.size()])))
	if not (final or hard or perfect):
		_clear_line += 1
	voice(line)

static func promote() -> void:
	AudioManager.play_sfx(PROMOTE, 1.0, -6.0)
	AudioManager.duck_music(-6.0, 1.2)
	HapticManager.success()
	_last_voice_ms = -100000 # a promotion always gets its cheer
	voice("wow")

static func fail() -> void:
	AudioManager.play_sfx(FAIL, 1.0, -9.0)
	HapticManager.pulse(70, 0.35)

static func hint() -> void:
	AudioManager.play_sfx(HINT, 1.0, -11.0)
	HapticManager.pulse(10, 0.3)

static func unlock() -> void:
	AudioManager.play_sfx(UNLOCK, 1.0, -8.0)
	HapticManager.success()

static func music_for(hard: bool) -> void:
	AudioManager.play_music(load(MUSIC_HARD if hard else MUSIC_TENSE))

## Plays a voice cheer when allowed. Returns whether it started.
static func voice(key: String) -> bool:
	if not AudioManager.voice_enabled():
		return false
	var now := Time.get_ticks_msec()
	if now - _last_voice_ms < VOICE_GAP_MS:
		return false
	var stream := voice_stream(key)
	if stream == null:
		return false
	if AudioManager.play_voice(stream):
		_last_voice_ms = now
		return true
	return false

## Drops cached voice streams (called when the audio service leaves the tree at exit).
static func release_cache() -> void:
	_voice_cache.clear()

## The English voice file for a cheer, or null when there is none.
static func voice_stream(key: String) -> AudioStream:
	var path := "res://assets/voice/%s/%s.wav" % [VOICE_LANG, key]
	if not _voice_cache.has(path):
		_voice_cache[path] = load(path) if ResourceLoader.exists(path) else null
	return _voice_cache[path]
