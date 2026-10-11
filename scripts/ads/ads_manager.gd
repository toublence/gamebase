extends Node
## Autoload "AdsManager". Owns consent, SDK initialization, the interstitial and rewarded slots, the
## anchored banner, frequency policy and the full-screen lock. Providers only relay real SDK events.
##
## Separate states, never one boolean:
##   provider   - native plugin connected / missing / unsupported platform
##   config     - IDs valid for the current mode
##   consent    - UMP update result and canRequestAds()
##   sdk        - MobileAds initialization
##   slots      - per-format object state (EMPTY/LOADING/READY/SHOWING/BACKOFF/BLOCKED)
##   lock       - one full-screen surface at a time (ad or consent/privacy form)
##   policy     - whether this opportunity may show (never blocks preloading)
signal availability_changed
signal rewarded_changed
signal banner_layout_changed(height_logical: float)
signal status_changed

const ERROR_KIND := {0: "INTERNAL", 1: "INVALID_REQUEST", 2: "NETWORK_ERROR", 3: "NO_FILL", 8: "INVALID_CONFIGURATION",
	9: "NO_FILL", 10: "REQUEST_ID_MISMATCH", 11: "INVALID_CONFIGURATION"}

var policy := AdPolicy.new()
var mode := AdsConfig.mode()
var ids := AdsConfig.ids()
var config_errors: Array[String] = []
var provider_status := "unknown" # connected | missing | unsupported | fake
var provider_info := {}
var consent := {"state": "not_started", "can_request_ads": false, "consent_status": -1, "privacy_required": false,
	"last_error": {}, "updated_ms": 0}
var sdk_state := "not_started" # not_started | initializing | ready | failed
var sdk_info := {}
var form_showing := false
var activity_resumed := true
var network_available := true
var interstitial: AdSlot
var rewarded: AdSlot
var banner := {"state": "NONE", "request_id": 0, "configured": false, "visible": false, "height_px": 0, "width_px": 0,
	"height_logical": 0.0, "failures": 0, "next_retry_ms": 0, "last_error": {}, "last_result": "", "skip_reason": ""}
var last_skip := {"format": "", "reason": "", "ms": 0}
var session_interstitials := 0
var session_rewarded := 0

var _adapter: AdsAdapter
var _request_counter := 0
var _lock := {"busy": false, "format": "", "request_id": 0, "since_ms": 0}
var _pending_continuation: Callable
var _pending_done := true
var _reward := {} # active rewarded transaction
var _recent_rewards := {} # request_id -> transaction kept briefly for late earned callbacks
var _resumed_since_ms := 0
var _banner_owners: Array = []
var _tick: Timer
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	interstitial = AdSlot.new("interstitial", str(ids["interstitial"]))
	rewarded = AdSlot.new("rewarded", str(ids["rewarded"]))
	_tick = Timer.new()
	_tick.wait_time = 1.0
	_tick.timeout.connect(_on_tick)
	add_child(_tick)
	_tick.start()
	config_errors = AdsConfig.validate(mode, ids)
	var adapter: AdsAdapter
	if Engine.has_singleton("OuttapAds"):
		adapter = load("res://scripts/ads/admob_android_adapter.gd").new()
	else:
		adapter = AdsAdapter.new()
	install_adapter(adapter, "missing" if OS.get_name() == "Android" and not Engine.has_singleton("OuttapAds") else "")
	get_viewport().size_changed.connect(_update_banner_layout)

## Replaces the provider. Tests use this with a fake; production calls it once from _ready.
func install_adapter(adapter: AdsAdapter, forced_status: String = "") -> void:
	if _adapter != null:
		_adapter.queue_free()
	_reset_runtime()
	_adapter = adapter
	add_child(_adapter)
	_adapter.sdk_event.connect(_on_sdk_event)
	provider_info = _adapter.connect_provider()
	if not forced_status.is_empty():
		provider_status = forced_status
	elif bool(provider_info.get("ok", false)):
		provider_status = str(provider_info.get("provider", "connected"))
	else:
		provider_status = "unsupported"
	match provider_status:
		"missing":
			# A real Android build without the plugin is a packaging error, not a quiet ad-free mode.
			Diagnostics.error("ads", "PLUGIN_MISSING", {"detail": "OuttapAds Android plugin is not in this build"})
		"unsupported":
			Diagnostics.log_event("ads", "provider_unsupported", {"platform": OS.get_name(), "detail": provider_info.get("reason", "")})
	if not config_errors.is_empty():
		Diagnostics.error("ads", "INVALID_CONFIGURATION", {"mode": mode, "problems": config_errors})
	if _provider_usable() and config_errors.is_empty():
		var manifest_id := str(provider_info.get("manifest_app_id", ids["app_id"]))
		if manifest_id != ids["app_id"]:
			config_errors.append("manifest App ID %s does not match %s config" % [manifest_id, mode])
			Diagnostics.error("ads", "INVALID_CONFIGURATION", {"manifest_app_id": manifest_id, "expected": ids["app_id"]})
	if _provider_usable() and config_errors.is_empty():
		_adapter.configure({"test_mode": mode == "test", "debug_build": OS.is_debug_build(),
			"max_ad_content_rating": AdsConfig.REQUEST["max_ad_content_rating"],
			"child_directed": AdsConfig.REQUEST["child_directed"],
			"under_age_of_consent": AdsConfig.REQUEST["under_age_of_consent"],
			"banner_unit": ids["banner"]})
		_start_consent.call_deferred()
	status_changed.emit()

func _reset_runtime() -> void:
	consent = {"state": "not_started", "can_request_ads": false, "consent_status": -1, "privacy_required": false,
		"last_error": {}, "updated_ms": 0}
	sdk_state = "not_started"
	form_showing = false
	interstitial = AdSlot.new("interstitial", str(ids["interstitial"]))
	rewarded = AdSlot.new("rewarded", str(ids["rewarded"]))
	_lock = {"busy": false, "format": "", "request_id": 0, "since_ms": 0}
	_reward = {}
	_banner_owners.clear()
	banner["state"] = "NONE"
	banner["configured"] = false
	banner["visible"] = false
	banner["height_logical"] = 0.0

func _provider_usable() -> bool:
	return provider_status in ["connected", "fake"]

func _now() -> int:
	return Time.get_ticks_msec()

# --- consent & initialization ------------------------------------------------------------------

## Runs on every launch: refresh consent info, show the form only if required, and in parallel use
## consent from a previous session if it already allows requests.
func _start_consent() -> void:
	consent["state"] = "requesting"
	Diagnostics.log_event("ads", "consent_update_requested", {})
	_adapter.request_consent_update(_consent_debug())
	if _adapter.can_request_ads():
		_maybe_initialize("previous_session_consent")

func _consent_debug() -> Dictionary:
	return {"debug_geography": debug_geography if OS.is_debug_build() else 0}

## Debug-only UMP geography override (0 disabled, 1 EEA, 2 not EEA), set from the diagnostics screen.
var debug_geography := 0

func _maybe_initialize(source: String) -> void:
	consent["can_request_ads"] = _adapter.can_request_ads()
	if sdk_state != "not_started":
		_pump()
		return
	if not consent["can_request_ads"]:
		Diagnostics.log_event("ads", "sdk_init_deferred", {"source": source, "reason": "CONSENT_NOT_READY"})
		return
	sdk_state = "initializing"
	Diagnostics.log_event("ads", "sdk_init_started", {"source": source})
	_adapter.initialize_sdk()
	status_changed.emit()

func _ads_allowed() -> bool:
	return _provider_usable() and config_errors.is_empty() and sdk_state == "ready" and bool(consent["can_request_ads"])

# --- event intake ------------------------------------------------------------------------------

func _on_sdk_event(name: String, data: Dictionary) -> void:
	match name:
		"consent_info_updated":
			consent["state"] = "updated"
			consent["consent_status"] = int(data.get("consent_status", -1))
			consent["privacy_required"] = bool(data.get("privacy_required", false))
			consent["updated_ms"] = _now()
			Diagnostics.log_event("ads", "consent_info_updated", data)
			form_showing = true
			_adapter.load_and_show_consent_form_if_required()
			_maybe_initialize("consent_updated")
		"consent_info_failed":
			consent["state"] = "error"
			consent["last_error"] = data.duplicate()
			Diagnostics.error("ads", "consent_info_failed", data)
			# The update failed, but consent from an earlier session may still allow requests.
			_maybe_initialize("consent_update_failed")
		"consent_form_dismissed", "privacy_form_dismissed":
			form_showing = false
			consent["privacy_required"] = bool(data.get("privacy_required", consent["privacy_required"]))
			if data.has("code"):
				consent["last_error"] = data.duplicate()
			Diagnostics.log_event("ads", name, data)
			_maybe_initialize(name)
			availability_changed.emit()
		"sdk_initialized":
			sdk_state = "ready"
			sdk_info = data.duplicate()
			Diagnostics.log_event("ads", "sdk_initialized", data)
			_pump()
		"ad_loaded": _on_loaded(data)
		"ad_load_failed": _on_load_failed(data)
		"ad_showed": _on_showed(data)
		"ad_impression":
			Diagnostics.log_event("ads", "ad_impression", data)
		"ad_clicked":
			Diagnostics.log_event("ads", "ad_clicked", data)
		"ad_show_failed": _on_show_failed(data)
		"ad_dismissed": _on_dismissed(data)
		"reward_earned": _on_reward_earned(data)
		"ad_paid", "banner_paid":
			_on_paid(data, "banner" if name == "banner_paid" else str(data.get("format", "")))
		"banner_loaded": _on_banner_loaded(data)
		"banner_failed": _on_banner_failed(data)
		"banner_impression":
			Diagnostics.log_event("ads", "banner_impression", data)
		"activity_state":
			activity_resumed = bool(data.get("resumed", true))
			_resumed_since_ms = _now() if activity_resumed else 0
			if activity_resumed:
				_pump()
		"network_state":
			var was := network_available
			network_available = bool(data.get("available", true))
			Diagnostics.log_event("ads", "network_state", data)
			if network_available and not was:
				_on_network_recovered()
		"ad_inspector_closed":
			Diagnostics.log_event("ads", "ad_inspector_closed", data)
		_:
			Diagnostics.log_event("ads", "unknown_event", {"name": name})
	status_changed.emit()

# --- loading -----------------------------------------------------------------------------------

func _pump() -> void:
	if not _ads_allowed():
		return
	for slot in [interstitial, rewarded]:
		_maybe_load(slot)
	_update_banner()

func _maybe_load(slot: AdSlot) -> void:
	var now := _now()
	if slot.state == AdSlot.State.BACKOFF and now >= slot.next_retry_ms:
		slot.state = AdSlot.State.EMPTY
	if slot.state != AdSlot.State.EMPTY:
		return
	if not network_available:
		slot.waiting_for_network = true
		return
	slot.waiting_for_network = false
	_request_counter += 1
	slot.request_id = _request_counter
	slot.state = AdSlot.State.LOADING
	slot.load_started_ms = now
	slot.last_request_ms = now
	Diagnostics.log_event("ads", "ad_load_started", {"format": slot.format, "request_id": slot.request_id})
	AnalyticsService.track(&"ad_load_started", {"format": slot.format})
	_adapter.load_ad(slot.format, slot.request_id, slot.unit_id)
	if slot == rewarded:
		rewarded_changed.emit()

func _slot_for(format: String) -> AdSlot:
	return interstitial if format == "interstitial" else (rewarded if format == "rewarded" else null)

func _on_loaded(data: Dictionary) -> void:
	var slot := _slot_for(str(data.get("format", "")))
	var request_id := int(data.get("request_id", -1))
	if slot == null or request_id != slot.request_id or slot.state != AdSlot.State.LOADING:
		# Timed out or superseded: drop the native object so it can never be shown.
		Diagnostics.log_event("ads", "stale_load_ignored", data)
		_adapter.discard_ad(str(data.get("format", "")), request_id)
		return
	slot.state = AdSlot.State.READY
	slot.loaded_ms = _now()
	slot.failures = 0
	slot.last_result = "loaded"
	slot.last_error = {}
	slot.response_id = str(data.get("response_id", ""))
	slot.response_info = data.get("response_info", {}) if data.get("response_info") is Dictionary else {}
	Diagnostics.log_event("ads", "ad_loaded", {"format": slot.format, "request_id": request_id, "response_id": slot.response_id,
		"latency_ms": slot.loaded_ms - slot.load_started_ms})
	AnalyticsService.track(&"ad_loaded", {"format": slot.format, "latency_ms": slot.loaded_ms - slot.load_started_ms})
	if slot == rewarded:
		rewarded_changed.emit()

func _on_load_failed(data: Dictionary) -> void:
	var slot := _slot_for(str(data.get("format", "")))
	var request_id := int(data.get("request_id", -1))
	if slot == null or request_id != slot.request_id or slot.state != AdSlot.State.LOADING:
		Diagnostics.log_event("ads", "stale_failure_ignored", data)
		return
	var kind := classify(data)
	slot.last_error = data.duplicate()
	slot.last_error["kind"] = kind
	slot.last_result = "failed:" + kind
	slot.response_id = str(data.get("response_id", ""))
	_schedule_retry(slot, kind)
	Diagnostics.error("ads", "ad_load_failed", {"format": slot.format, "request_id": request_id, "kind": kind,
		"domain": data.get("domain", ""), "code": data.get("code", -1), "message": data.get("message", ""),
		"response_id": slot.response_id, "next_state": slot.state_name()})
	AnalyticsService.track(&"ad_load_failed", {"format": slot.format, "kind": kind, "code": data.get("code", -1)})
	if slot == rewarded:
		rewarded_changed.emit()

## Maps SDK errors to actionable kinds. Configuration errors stop automatic retries.
static func classify(data: Dictionary) -> String:
	var domain := str(data.get("domain", ""))
	var code := int(data.get("code", -1))
	if domain == "outtap" and str(data.get("kind", "")) != "":
		return str(data["kind"])
	if domain != "com.google.android.gms.ads" and domain != "":
		return "MEDIATION_OR_OTHER"
	var kind: String = ERROR_KIND.get(code, "UNKNOWN")
	return "INVALID_CONFIGURATION" if kind == "INVALID_REQUEST" else kind

func _schedule_retry(slot: AdSlot, kind: String) -> void:
	if kind == "INVALID_CONFIGURATION":
		slot.state = AdSlot.State.BLOCKED # never hammer a bad ad unit; manual retry in diagnostics
		return
	slot.failures += 1
	slot.state = AdSlot.State.BACKOFF
	slot.next_retry_ms = _now() + policy.backoff_ms(slot.failures, _rng.randf())
	slot.waiting_for_network = kind == "NETWORK_ERROR"

func _on_network_recovered() -> void:
	for slot in [interstitial, rewarded]:
		if slot.state == AdSlot.State.BACKOFF and (slot.waiting_for_network or str(slot.last_error.get("kind", "")) == "NETWORK_ERROR"):
			slot.next_retry_ms = _now()
		slot.waiting_for_network = false
	if str(banner["last_error"].get("kind", "")) == "NETWORK_ERROR":
		banner["next_retry_ms"] = _now()
	_pump()

## Manual retry (diagnostics, or the player tapping "retry" on a rewarded offer).
func retry_rewarded() -> void:
	retry(rewarded)

func retry(slot: AdSlot) -> void:
	if slot.state in [AdSlot.State.BACKOFF, AdSlot.State.BLOCKED]:
		slot.state = AdSlot.State.EMPTY
		slot.next_retry_ms = 0
	_pump()
	status_changed.emit()

func _on_tick() -> void:
	var now := _now()
	for slot in [interstitial, rewarded]:
		if slot.state == AdSlot.State.LOADING and now - slot.load_started_ms > int(policy.values["load_timeout_ms"]):
			Diagnostics.error("ads", "load_timeout", {"format": slot.format, "request_id": slot.request_id})
			_adapter.discard_ad(slot.format, slot.request_id)
			slot.last_result = "failed:TIMEOUT"
			slot.last_error = {"kind": "TIMEOUT", "domain": "outtap", "code": -1, "message": "no load callback in time"}
			_request_counter += 1
			slot.request_id = _request_counter # any late callback for the old id is now stale
			_schedule_retry(slot, "TIMEOUT")
		elif slot.state == AdSlot.State.READY and now - slot.loaded_ms > int(policy.values["cache_ttl_ms"]):
			Diagnostics.log_event("ads", "AD_EXPIRED", {"format": slot.format, "request_id": slot.request_id})
			_adapter.discard_ad(slot.format, slot.request_id)
			slot.state = AdSlot.State.EMPTY
			slot.last_result = "expired"
	# A show that never reported back while our own activity has been visibly resumed for a while
	# is lost. Only real activity state can release the lock, never elapsed time alone.
	if _lock["busy"] and activity_resumed and _resumed_since_ms > 0 and _adapter.is_activity_resumed() \
			and now - maxi(_resumed_since_ms, int(_lock["since_ms"])) > int(policy.values["stuck_show_resumed_ms"]):
		Diagnostics.error("ads", "SHOW_LOST", {"format": _lock["format"], "request_id": _lock["request_id"]})
		_end_fullscreen(str(_lock["format"]), false, "SHOW_LOST")
	_pump()
	for id in _recent_rewards.keys():
		if now - int(_recent_rewards[id]["closed_ms"]) > 30000:
			_recent_rewards.erase(id)

# --- interstitial ------------------------------------------------------------------------------

## A natural break. `continuation` runs exactly once: immediately when no ad is shown, or after the
## ad closes or fails. A missed opportunity is gone; it is never replayed over a later screen.
func interstitial_opportunity(placement: String, context: Dictionary, continuation: Callable) -> void:
	var counters := Progress.ad_counters()
	var ctx := {"placement": placement, "level_index": int(context.get("level_index", 0)), "mode": str(context.get("mode", "")),
		"next_hard": bool(context.get("next_hard", false)),
		"total_play_ms": Progress.total_play_ms(), "play_ms_at_last_fullscreen": int(counters.get("play_ms_at_last_fullscreen", 0)),
		"fullscreen_count": int(counters.get("fullscreen_count", 0)),
		"new_clears_since_fullscreen": int(counters.get("new_clears_since_fullscreen", 0)), "session_interstitials": session_interstitials}
	Diagnostics.log_event("ads", "ad_opportunity", ctx)
	AnalyticsService.track(&"ad_opportunity", {"format": "interstitial", "placement": placement})
	var reason := _interstitial_skip_reason(ctx)
	if not reason.is_empty():
		_skip("interstitial", reason, ctx)
		continuation.call()
		return
	_pending_continuation = continuation
	_pending_done = false
	_begin_fullscreen(interstitial)

func _interstitial_skip_reason(ctx: Dictionary) -> String:
	var unavailable := _availability_reason()
	if not unavailable.is_empty():
		return unavailable
	var reason := policy.interstitial_block_reason(ctx)
	if not reason.is_empty():
		return reason
	return _slot_reason(interstitial)

## Why ads cannot be shown at all right now, or "".
func _availability_reason() -> String:
	if provider_status == "missing":
		return "PLUGIN_MISSING"
	if provider_status == "unsupported":
		return "UNSUPPORTED_PLATFORM"
	if not config_errors.is_empty():
		return "INVALID_CONFIGURATION"
	if not bool(consent["can_request_ads"]):
		return "CONSENT_NOT_READY"
	if sdk_state != "ready":
		return "SDK_NOT_INITIALIZED"
	if AppManager.is_backgrounded or not activity_resumed:
		return "APP_BACKGROUND"
	if _lock["busy"] or form_showing:
		return "FULLSCREEN_BUSY"
	return ""

func _slot_reason(slot: AdSlot) -> String:
	match slot.state:
		AdSlot.State.READY:
			if _now() - slot.loaded_ms > int(policy.values["cache_ttl_ms"]):
				_adapter.discard_ad(slot.format, slot.request_id)
				slot.state = AdSlot.State.EMPTY
				_pump()
				return "AD_EXPIRED"
			return ""
		AdSlot.State.LOADING:
			return "LOAD_IN_PROGRESS"
		AdSlot.State.BACKOFF, AdSlot.State.BLOCKED:
			var kind := str(slot.last_error.get("kind", ""))
			return kind if kind in ["NO_FILL", "NETWORK_ERROR", "INVALID_CONFIGURATION"] else "NO_CACHED_AD"
		_:
			return "NO_CACHED_AD"

func _skip(format: String, reason: String, ctx: Dictionary = {}) -> void:
	last_skip = {"format": format, "reason": reason, "ms": _now()}
	Diagnostics.log_event("ads", "ad_skipped", {"format": format, "reason": reason, "ctx": ctx})
	AnalyticsService.track(&"ad_skipped", {"format": format, "reason": reason})

func _begin_fullscreen(slot: AdSlot) -> void:
	_lock = {"busy": true, "format": slot.format, "request_id": slot.request_id, "since_ms": _now()}
	slot.state = AdSlot.State.SHOWING
	Diagnostics.log_event("ads", "ad_show_requested", {"format": slot.format, "request_id": slot.request_id})
	AnalyticsService.track(&"ad_show_requested", {"format": slot.format})
	AudioManager.set_suspended(true)
	status_changed.emit()
	if not _adapter.show_ad(slot.format, slot.request_id):
		_end_fullscreen(slot.format, false, "SHOW_FAILED", {"domain": "outtap", "code": -1, "message": "provider refused show"})

func _on_showed(data: Dictionary) -> void:
	if not _matches_lock(data):
		Diagnostics.log_event("ads", "stale_show_event", data)
		return
	Diagnostics.log_event("ads", "ad_showed", data)
	AnalyticsService.track(&"ad_showed", {"format": data.get("format", "")})
	Progress.note_fullscreen_ad_shown()
	if data.get("format") == "interstitial":
		session_interstitials += 1
	else:
		session_rewarded += 1

func _on_show_failed(data: Dictionary) -> void:
	if not _matches_lock(data):
		Diagnostics.log_event("ads", "stale_show_event", data)
		return
	_end_fullscreen(str(data.get("format", "")), false, "SHOW_FAILED", data)

func _on_dismissed(data: Dictionary) -> void:
	if not _matches_lock(data):
		Diagnostics.log_event("ads", "stale_dismiss_ignored", data)
		return
	_end_fullscreen(str(data.get("format", "")), true, "")

func _matches_lock(data: Dictionary) -> bool:
	return _lock["busy"] and str(data.get("format", "")) == _lock["format"] and int(data.get("request_id", -1)) == int(_lock["request_id"])

func _end_fullscreen(format: String, dismissed: bool, reason: String, error: Dictionary = {}) -> void:
	var request_id := int(_lock["request_id"])
	_lock = {"busy": false, "format": "", "request_id": 0, "since_ms": 0}
	var slot := _slot_for(format)
	if slot != null and slot.state == AdSlot.State.SHOWING:
		slot.state = AdSlot.State.EMPTY # a shown object is never reused
	_adapter.discard_ad(format, request_id)
	AudioManager.set_suspended(AppManager.is_backgrounded)
	if dismissed:
		Diagnostics.log_event("ads", "ad_dismissed", {"format": format, "request_id": request_id})
		AnalyticsService.track(&"ad_dismissed", {"format": format})
	else:
		last_skip = {"format": format, "reason": reason, "ms": _now()}
		Diagnostics.error("ads", "ad_show_failed", {"format": format, "request_id": request_id, "reason": reason,
			"domain": error.get("domain", ""), "code": error.get("code", -1), "message": error.get("message", "")})
		AnalyticsService.track(&"ad_show_failed", {"format": format, "reason": reason, "code": error.get("code", -1)})
	if format == "interstitial":
		_run_continuation()
	elif format == "rewarded":
		_close_reward(dismissed, reason)
	status_changed.emit()
	rewarded_changed.emit()
	_pump.call_deferred() # preload the next one

func _run_continuation() -> void:
	if _pending_done:
		return
	_pending_done = true
	var callback := _pending_continuation
	_pending_continuation = Callable()
	if callback.is_valid():
		callback.call()

func is_presenting() -> bool:
	return bool(_lock["busy"]) or form_showing

# --- rewarded ----------------------------------------------------------------------------------

## "ready" (offer can be shown now), "loading" (being fetched; show progress), "retry" (failed,
## will retry or can be retried), "unavailable" (no ads possible: consent, platform, config).
func rewarded_offer_state() -> String:
	if not _provider_usable() or not config_errors.is_empty():
		return "unavailable"
	if sdk_state == "not_started" and consent["state"] in ["updated", "error"] and not bool(consent["can_request_ads"]):
		return "unavailable"
	match rewarded.state:
		AdSlot.State.READY:
			return "ready" if not is_presenting() else "loading"
		AdSlot.State.LOADING, AdSlot.State.EMPTY:
			return "loading"
		AdSlot.State.BLOCKED:
			return "unavailable"
		_:
			return "retry"

## Shows a rewarded ad the player explicitly chose. `on_earned(transaction_id)` runs once when the
## SDK reports the reward (possibly before the ad closes); `on_closed({granted, transaction_id,
## reason})` runs exactly once after the ad closes or fails. Returns false if nothing was shown
## (on_closed has already run).
func show_rewarded(kind: String, attempt_id: String, on_earned: Callable, on_closed: Callable) -> bool:
	var reason := _availability_reason()
	if reason.is_empty():
		reason = _slot_reason(rewarded)
	Diagnostics.log_event("ads", "ad_opportunity", {"format": "rewarded", "kind": kind, "attempt_id": attempt_id})
	AnalyticsService.track(&"ad_opportunity", {"format": "rewarded", "placement": kind})
	if not reason.is_empty():
		_skip("rewarded", reason, {"kind": kind})
		on_closed.call({"granted": false, "transaction_id": "", "reason": reason})
		return false
	var transaction := "%s-%d-%s" % [kind, int(Time.get_unix_time_from_system()), Crypto.new().generate_random_bytes(4).hex_encode()]
	_reward = {"transaction_id": transaction, "kind": kind, "attempt_id": attempt_id, "request_id": rewarded.request_id,
		"earned": false, "closed": false, "on_earned": on_earned, "on_closed": on_closed}
	_begin_fullscreen(rewarded)
	return true

func _on_reward_earned(data: Dictionary) -> void:
	var request_id := int(data.get("request_id", -1))
	if not _reward.is_empty() and request_id == int(_reward["request_id"]):
		if bool(_reward["earned"]):
			Diagnostics.log_event("ads", "duplicate_reward_ignored", data)
			return
		_grant(_reward, data)
		if bool(_reward["closed"]):
			_finish_reward()
		return
	if _recent_rewards.has(request_id) and not bool(_recent_rewards[request_id]["earned"]):
		# The earned callback arrived after we already reported "not earned": still honor it.
		var late: Dictionary = _recent_rewards[request_id]
		Diagnostics.log_event("ads", "late_reward_granted", data)
		_grant(late, data)
		UI.toast("REWARD_LATE")
		return
	Diagnostics.log_event("ads", "stale_reward_ignored", data)

func _grant(transaction: Dictionary, data: Dictionary) -> void:
	transaction["earned"] = true
	var id := str(transaction["transaction_id"])
	if not Progress.claim_reward(id):
		Diagnostics.log_event("ads", "duplicate_reward_ignored", {"transaction_id": id})
		return
	Diagnostics.log_event("ads", "ad_reward_earned", {"transaction_id": id, "kind": transaction["kind"],
		"attempt_id": transaction["attempt_id"], "type": data.get("type", ""), "amount": data.get("amount", 0)})
	AnalyticsService.track(&"ad_reward_earned", {"kind": transaction["kind"]})
	var callback: Callable = transaction["on_earned"]
	if callback.is_valid():
		callback.call(id)
	Progress.flush_now()

func _close_reward(dismissed: bool, reason: String) -> void:
	if _reward.is_empty():
		return
	_reward["closed"] = true
	_reward["close_reason"] = reason if not dismissed else ""
	if bool(_reward["earned"]) or not dismissed:
		_finish_reward()
		return
	# Reward and close callbacks are not ordered; give a late earned callback a short window.
	var request_id := int(_reward["request_id"])
	get_tree().create_timer(float(policy.values["reward_grace_ms"]) / 1000.0, true).timeout.connect(func():
		if not _reward.is_empty() and int(_reward["request_id"]) == request_id:
			_finish_reward())

func _finish_reward() -> void:
	var transaction := _reward
	_reward = {}
	var granted := bool(transaction["earned"])
	var reason := "" if granted else (str(transaction.get("close_reason", "")) if not str(transaction.get("close_reason", "")).is_empty() else "dismissed_early")
	transaction["closed_ms"] = _now()
	_recent_rewards[int(transaction["request_id"])] = transaction
	var callback: Callable = transaction["on_closed"]
	if callback.is_valid():
		callback.call({"granted": granted, "transaction_id": transaction["transaction_id"], "reason": reason})

# --- revenue -----------------------------------------------------------------------------------

func _on_paid(data: Dictionary, format: String) -> void:
	var micros := int(data.get("value_micros", 0))
	var payload := {"format": format, "value_micros": micros, "value": micros / 1000000.0,
		"currency": str(data.get("currency", "")), "precision": int(data.get("precision", -1))}
	Diagnostics.log_event("ads", "ad_revenue", payload)
	AnalyticsService.track(&"ad_revenue", payload)

# --- banner ------------------------------------------------------------------------------------

func request_banner(owner: Object, wanted: bool) -> void:
	if wanted and not _banner_owners.has(owner):
		_banner_owners.append(owner)
	elif not wanted:
		_banner_owners.erase(owner)
	_update_banner()

func banner_height_logical() -> float:
	return float(banner["height_logical"]) if bool(banner["visible"]) else 0.0

func _update_banner() -> void:
	var wanted := not _banner_owners.is_empty()
	if not wanted or not _ads_allowed():
		_set_banner_visible(false)
		return
	if not bool(banner["configured"]):
		_adapter.banner_configure(str(ids["banner"]))
		banner["configured"] = true
	match str(banner["state"]):
		"LOADED":
			_set_banner_visible(_banner_fits())
		"LOADING":
			pass
		"BLOCKED":
			pass
		_:
			if _now() >= int(banner["next_retry_ms"]) and network_available:
				_request_counter += 1
				banner["request_id"] = _request_counter
				banner["state"] = "LOADING"
				Diagnostics.log_event("ads", "ad_load_started", {"format": "banner", "request_id": banner["request_id"]})
				_adapter.banner_load(int(banner["request_id"]))

func _banner_fits() -> bool:
	var view := get_viewport().get_visible_rect().size
	var insets := SafeArea.logical_insets(get_viewport())
	var free_height := view.y - insets.y - insets.w - float(banner["height_logical"])
	if free_height < float(policy.values["banner_min_content_height"]):
		if banner["skip_reason"] != "INSUFFICIENT_BANNER_SPACE":
			banner["skip_reason"] = "INSUFFICIENT_BANNER_SPACE"
			_skip("banner", "INSUFFICIENT_BANNER_SPACE", {"free_height": free_height})
		return false
	banner["skip_reason"] = ""
	return true

func _set_banner_visible(visible: bool) -> void:
	if bool(banner["visible"]) == visible:
		return
	banner["visible"] = visible
	_adapter.banner_set_visible(visible)
	banner_layout_changed.emit(banner_height_logical())

func _on_banner_loaded(data: Dictionary) -> void:
	if int(data.get("request_id", -1)) != int(banner["request_id"]):
		Diagnostics.log_event("ads", "stale_banner_ignored", data)
		return
	banner["state"] = "LOADED"
	banner["failures"] = 0
	banner["last_error"] = {}
	banner["last_result"] = "loaded"
	banner["height_px"] = int(data.get("height_px", 0))
	banner["width_px"] = int(data.get("width_px", 0))
	_update_banner_layout()
	Diagnostics.log_event("ads", "ad_loaded", {"format": "banner", "request_id": data.get("request_id"), "height_px": banner["height_px"],
		"response_id": data.get("response_id", "")})
	_update_banner()

func _on_banner_failed(data: Dictionary) -> void:
	if int(data.get("request_id", -1)) != int(banner["request_id"]):
		return
	var kind := classify(data)
	banner["last_error"] = data.duplicate()
	banner["last_error"]["kind"] = kind
	banner["last_result"] = "failed:" + kind
	if kind == "INVALID_CONFIGURATION":
		banner["state"] = "BLOCKED"
	else:
		banner["failures"] = int(banner["failures"]) + 1
		banner["state"] = "BACKOFF"
		banner["next_retry_ms"] = _now() + policy.backoff_ms(int(banner["failures"]), _rng.randf())
	Diagnostics.error("ads", "ad_load_failed", {"format": "banner", "kind": kind, "domain": data.get("domain", ""),
		"code": data.get("code", -1), "message": data.get("message", "")})
	_set_banner_visible(false)

func _update_banner_layout() -> void:
	var window := Vector2(DisplayServer.window_get_size())
	var view := get_viewport().get_visible_rect().size
	var ratio := view.y / window.y if window.y > 0 else 1.0
	banner["height_logical"] = float(banner["height_px"]) * ratio
	if bool(banner["visible"]):
		if not _banner_fits():
			_set_banner_visible(false)
		else:
			banner_layout_changed.emit(banner_height_logical())

# --- privacy & tools ---------------------------------------------------------------------------

func privacy_options_required() -> bool:
	return _provider_usable() and config_errors.is_empty() and (bool(consent["privacy_required"]) or _adapter.privacy_options_required())

func show_privacy_options() -> void:
	if is_presenting():
		UI.toast("AD_BUSY")
		return
	form_showing = true
	Diagnostics.log_event("ads", "privacy_form_requested", {})
	_adapter.show_privacy_options_form()

func diagnostics_available() -> bool:
	return OS.is_debug_build() or OS.has_feature(AdsConfig.FEATURE_TEST_ADS)

func open_ad_inspector() -> bool:
	if not _provider_usable() or sdk_state != "ready":
		return false
	return _adapter.open_ad_inspector()

## Debug only: forget UMP consent so the form flow can be tested again.
func reset_consent_for_testing() -> void:
	if not OS.is_debug_build():
		return
	_adapter.reset_consent()
	Diagnostics.log_event("ads", "consent_reset_for_testing", {})

func restart_consent_flow() -> void:
	if _provider_usable() and config_errors.is_empty() and not is_presenting():
		_start_consent()

func get_status() -> Dictionary:
	var now := _now()
	var native := _adapter.native_status() if _adapter != null else {}
	return {"mode": mode, "ids": ids.duplicate(), "config_errors": config_errors.duplicate(), "provider": provider_status,
		"provider_info": provider_info.duplicate(), "godot": Engine.get_version_info()["string"], "consent": consent.duplicate(true),
		"can_request_ads_now": _adapter.can_request_ads() if _adapter != null else false, "sdk": sdk_state,
		"sdk_info": sdk_info.duplicate(true), "form_showing": form_showing, "activity_resumed": activity_resumed,
		"network_available": network_available, "fullscreen_lock": _lock.duplicate(),
		"interstitial": interstitial.snapshot(now), "rewarded": rewarded.snapshot(now), "banner": banner.duplicate(true),
		"banner_owners": _banner_owners.size(), "last_skip": last_skip.duplicate(),
		"policy": {"session_interstitials": session_interstitials, "session_rewarded": session_rewarded,
			"total_play_ms": Progress.total_play_ms(), "counters": Progress.ad_counters(), "qa_relaxed": policy.qa_relaxed,
			"values": policy.values.duplicate(true)}, "native": native}
