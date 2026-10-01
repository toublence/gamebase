extends Node
## No banners. Natural breaks only. All optional SDK failures leave navigation available.
signal availability_changed
const TEST_PUBLISHER := "ca-app-pub-3940256099942544"
const MIN_APP_AGE_MS := 30000
const COOLDOWN_MS := 180000
const MAX_INTERSTITIALS := 3
var _adapter: AdsAdapter
var _consent := false
var _busy := false
var _rewarded := false
var _earned := false
var _callback: Callable
var _request_id := 0
var _last_break_serial := -1
var _breaks := 0
var _shown := 0
var _last_shown := -COOLDOWN_MS
var _boot_time := 0
var _watchdog: Timer

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_boot_time = Time.get_ticks_msec()
	_watchdog = Timer.new()
	_watchdog.one_shot = true
	_watchdog.timeout.connect(_timeout)
	add_child(_watchdog)
	install_adapter(AdsAdapter.new())

func install_adapter(adapter: AdsAdapter, ids: Dictionary = {}) -> bool:
	if adapter == null or _busy:
		return false
	# Real providers must declare all IDs. Test IDs are fail-closed in release.
	if adapter.get_script() != preload("res://scripts/ads/ads_adapter.gd"):
		for key in ["app_id", "interstitial_id", "rewarded_id"]:
			var id := str(ids.get(key, ""))
			if id.is_empty() or (not OS.is_debug_build() and id.contains(TEST_PUBLISHER)):
				adapter.queue_free()
				return false
	if _adapter != null:
		_adapter.queue_free()
	_adapter = adapter
	_consent = false
	add_child(_adapter)
	_adapter.consent_resolved.connect(_on_consent)
	_adapter.impression.connect(_on_impression)
	_adapter.reward_earned.connect(_on_reward)
	_adapter.dismissed.connect(_on_dismissed)
	_adapter.failed.connect(_on_failed)
	_adapter.configure(ids.duplicate(true))
	_adapter.request_consent()
	return true

func _on_consent(allowed: bool) -> void:
	_consent = allowed
	availability_changed.emit()

func is_presenting() -> bool:
	return _busy

func is_rewarded_ready() -> bool:
	return _consent and not _busy and not AppManager.is_backgrounded and _adapter.rewarded_ready()

func privacy_options_required() -> bool:
	return _adapter.privacy_options_required()

func show_privacy_options() -> void:
	if not _busy:
		_adapter.show_privacy_options()

func show_interstitial_on_natural_break() -> bool:
	if AppManager.state != AppManager.State.RESULT or GameSession.state != GameSession.State.FINISHED:
		return false
	if _last_break_serial == GameSession.serial:
		return false
	_last_break_serial = GameSession.serial
	_breaks += 1
	var now := Time.get_ticks_msec()
	if _busy or not _consent or AppManager.is_backgrounded or not _adapter.interstitial_ready():
		return false
	if _breaks < 3 or _shown >= MAX_INTERSTITIALS or now - _boot_time < MIN_APP_AGE_MS or now - _last_shown < COOLDOWN_MS:
		return false
	_begin(false, Callable())
	if not _adapter.present_interstitial(_request_id):
		_finish(false)
		return false
	_last_shown = now
	_shown += 1
	return true

func show_rewarded(callback: Callable) -> bool:
	# Invoke from a user-selected button. Pause first; never interrupt active gameplay.
	if not callback.is_valid():
		return false
	if AppManager.state == AppManager.State.PLAYING or not is_rewarded_ready():
		callback.call(false)
		return false
	_begin(true, callback)
	if not _adapter.present_rewarded(_request_id):
		_finish(false)
		return false
	return true

func _begin(rewarded: bool, callback: Callable) -> void:
	_busy = true
	_rewarded = rewarded
	_earned = false
	_callback = callback
	_request_id += 1
	_watchdog.start(90.0)
	AudioManager.set_suspended(true)

func _on_impression(id: int, format: String) -> void:
	if _busy and id == _request_id:
		AnalyticsService.ad_impression(format)

func _on_reward(id: int) -> void:
	if _busy and id == _request_id and _rewarded:
		_earned = true

func _on_dismissed(id: int) -> void:
	if _busy and id == _request_id:
		_finish(_earned)

func _on_failed(id: int) -> void:
	if _busy and id == _request_id:
		_finish(false)

func _timeout() -> void:
	_adapter.cancel(_request_id)
	_finish(false)

func _finish(success: bool) -> void:
	if not _busy:
		return
	_watchdog.stop()
	var callback := _callback
	var grant := success and _rewarded
	_busy = false
	_callback = Callable()
	_rewarded = false
	AudioManager.set_suspended(AppManager.is_backgrounded)
	if grant:
		AnalyticsService.rewarded_completed()
	if callback.is_valid():
		callback.call(grant)
	availability_changed.emit()
