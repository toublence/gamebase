extends Node
## AdsManager state-machine tests with an injected fake provider (error injection). These verify
## our own state handling only; they are NOT evidence that real Google test ads load or show —
## that is checked separately on a device.
##   godot --headless --path . res://tests/ads_tests.tscn -- --verify-base
const Fake := preload("res://tests/fake_ads_adapter.gd")
var checks := 0
var failures: Array[String] = []
var fake: Fake

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func _ready() -> void:
	if not OS.is_debug_build() or "--verify-base" not in OS.get_cmdline_user_args():
		get_tree().quit(2)
		return
	_run.call_deferred()

func _fresh(consent: bool) -> void:
	fake = Fake.new()
	fake.consent_allows = consent
	AdsManager.install_adapter(fake)
	AdsManager.policy = AdPolicy.new()
	AdsManager.policy.values["reward_grace_ms"] = 80
	AdsManager.policy.values["stuck_show_resumed_ms"] = 60
	AdsManager.session_interstitials = 0
	await get_tree().process_frame

func _ready_sdk() -> void:
	fake.emit_event("consent_info_updated", {"can_request_ads": true, "consent_status": 1, "privacy_required": false})
	fake.emit_event("consent_form_dismissed", {"can_request_ads": true})
	fake.emit_event("sdk_initialized", {"adapters": {}})

func _load_ok(format: String) -> int:
	var id := 0
	for c in fake.calls:
		if c[0] == "load_ad" and c[1][0] == format:
			id = c[1][1]
	fake.emit_event("ad_loaded", {"format": format, "request_id": id, "response_id": "fake-resp"})
	return id

func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true).timeout

func _run() -> void:
	for suffix in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveManager.storage_path + suffix))
	SaveManager.load_save()
	Progress.reload()
	await _test_consent()
	await _test_loading()
	await _test_interstitial()
	await _test_rewarded()
	await _test_lifecycle_and_banner()
	print("ADS_TESTS: %d checks, %d failures" % [checks, failures.size()])
	for suffix in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveManager.storage_path + suffix))
	get_tree().quit(0 if failures.is_empty() else 1)

func _test_consent() -> void:
	# Previous-session consent: initialize in parallel with the update, exactly once overall.
	await _fresh(true)
	check(fake.count("request_consent_update") == 1, "consent info requested on start")
	check(fake.count("initialize_sdk") == 1, "previous-session consent initializes immediately")
	_ready_sdk()
	check(fake.count("initialize_sdk") == 1, "this-session consent path does not initialize twice")
	check(fake.count("load_ad") == 2, "both formats preload after init")
	# No consent: nothing initializes or loads; offers are unavailable once consent resolved.
	await _fresh(false)
	fake.emit_event("consent_info_updated", {"can_request_ads": false, "consent_status": 2})
	fake.emit_event("consent_form_dismissed", {"can_request_ads": false})
	check(fake.count("initialize_sdk") == 0 and fake.count("load_ad") == 0, "no requests without consent")
	check(AdsManager.rewarded_offer_state() == "unavailable", "rewarded unavailable without consent")
	# Update error, but earlier consent still allows requests.
	await _fresh(false)
	fake.consent_allows = true
	fake.emit_event("consent_info_failed", {"code": 2, "message": "network"})
	check(fake.count("initialize_sdk") == 1, "consent update error still re-checks canRequestAds")
	# Consent form open blocks full-screen ads.
	await _fresh(true)
	_ready_sdk()
	_load_ok("interstitial")
	AdsManager.form_showing = true
	AdsManager.policy.set_qa_relaxed(true)
	var ran := [0]
	AdsManager.interstitial_opportunity("level_complete", {"level_index": 9}, func(): ran[0] += 1)
	check(ran[0] == 1 and AdsManager.last_skip["reason"] == "FULLSCREEN_BUSY", "privacy form blocks interstitial")
	AdsManager.form_showing = false

func _test_loading() -> void:
	await _fresh(true)
	_ready_sdk()
	var loads := fake.count("load_ad")
	AdsManager._pump()
	AdsManager._pump()
	check(fake.count("load_ad") == loads, "no duplicate loads while one is in flight")
	# NO_FILL → backoff; no reload until it expires; manual retry reloads.
	var rid: int = fake.last_args("load_ad")[1]
	fake.emit_event("ad_load_failed", {"format": "rewarded", "request_id": rid, "domain": "com.google.android.gms.ads", "code": 3, "message": "No fill"})
	check(AdsManager.rewarded.state == AdSlot.State.BACKOFF and AdsManager.rewarded.last_error["kind"] == "NO_FILL", "no fill → backoff")
	var wait := AdsManager.rewarded.next_retry_ms - Time.get_ticks_msec()
	check(wait >= 12000 and wait <= 18000, "first backoff about 15 s with jitter (%d ms)" % wait)
	AdsManager._on_tick()
	check(fake.count("load_ad") == loads, "backoff holds the retry")
	check(AdsManager.rewarded_offer_state() == "retry", "offer shows retry state")
	AdsManager.retry_rewarded()
	check(fake.count("load_ad") == loads + 1, "manual retry reloads")
	# Repeated failures grow the delay and cap it.
	for i in 6:
		rid = fake.last_args("load_ad")[1]
		fake.emit_event("ad_load_failed", {"format": "rewarded", "request_id": rid, "domain": "com.google.android.gms.ads", "code": 0, "message": "internal"})
		AdsManager.retry_rewarded()
	var capped := AdsManager.policy.backoff_ms(20, 1.0)
	check(capped <= 144000 and capped >= 120000, "backoff capped near 120 s")
	# Invalid configuration blocks automatic retries.
	rid = fake.last_args("load_ad")[1]
	fake.emit_event("ad_load_failed", {"format": "rewarded", "request_id": rid, "domain": "com.google.android.gms.ads", "code": 1, "message": "Invalid ad unit"})
	check(AdsManager.rewarded.state == AdSlot.State.BLOCKED, "invalid request → blocked")
	var before := fake.count("load_ad")
	AdsManager._on_tick()
	check(fake.count("load_ad") == before, "blocked slot does not auto-retry")
	# Network error, then network recovery reloads right away.
	await _fresh(true)
	_ready_sdk()
	rid = fake.last_args("load_ad")[1]
	fake.emit_event("ad_load_failed", {"format": "rewarded", "request_id": rid, "domain": "com.google.android.gms.ads", "code": 2, "message": "network"})
	fake.emit_event("network_state", {"available": false})
	before = fake.count("load_ad")
	fake.emit_event("network_state", {"available": true})
	check(fake.count("load_ad") == before + 1, "network recovery re-evaluates and reloads")
	# Load timeout: old request becomes stale; its late success is discarded, never shown.
	AdsManager.policy.values["load_timeout_ms"] = -1
	var stale: int = AdsManager.interstitial.request_id
	AdsManager._on_tick()
	check(AdsManager.interstitial.request_id != stale, "timed-out request superseded")
	var discards := fake.count("discard_ad")
	fake.emit_event("ad_loaded", {"format": "interstitial", "request_id": stale})
	check(fake.count("discard_ad") == discards + 1 and AdsManager.interstitial.state != AdSlot.State.READY, "late load discarded")
	AdsManager.policy.values["load_timeout_ms"] = 60000
	# Expired cache is discarded and reloaded.
	await _fresh(true)
	_ready_sdk()
	_load_ok("interstitial")
	AdsManager.interstitial.loaded_ms -= 4000000
	before = fake.count("load_ad")
	AdsManager._on_tick()
	check(fake.count("load_ad") == before + 1 and AdsManager.interstitial.state == AdSlot.State.LOADING, "expired ad replaced")

func _test_interstitial() -> void:
	await _fresh(true)
	_ready_sdk()
	_load_ok("interstitial")
	var ran := [0]
	# Policy: first five stages never show.
	AdsManager.interstitial_opportunity("level_complete", {"level_index": 3, "mode": "campaign"}, func(): ran[0] += 1)
	check(ran[0] == 1 and AdsManager.last_skip["reason"] == "FIRST_LEVEL_GRACE" and fake.count("show_ad") == 0, "first levels skip")
	AdsManager.interstitial_opportunity("level_complete", {"level_index": 9, "mode": "campaign"}, func(): ran[0] += 1)
	check(AdsManager.last_skip["reason"] == "PLAYTIME_GRACE", "early play time skip")
	AdsManager.interstitial_opportunity("pause", {"level_index": 9}, func(): ran[0] += 1)
	check(AdsManager.last_skip["reason"] == "NOT_A_TRANSITION", "only at transitions")
	var policy := AdPolicy.new()
	var failed_ctx := {"placement": "level_failed", "level_index": 9, "mode": "campaign", "total_play_ms": 999999,
		"new_clears_since_fullscreen": 0, "fullscreen_count": 1, "play_ms_at_last_fullscreen": 0}
	check(policy.interstitial_block_reason(failed_ctx) == "", "running out of hearts is an interstitial break (no new clears needed)")
	failed_ctx["placement"] = "level_complete"
	check(policy.interstitial_block_reason(failed_ctx) == "FREQUENCY_CAP", "the clear transition still needs new clears")
	failed_ctx["placement"] = "level_failed"
	failed_ctx["play_ms_at_last_fullscreen"] = 999999 - 1000
	check(policy.interstitial_block_reason(failed_ctx) == "FREQUENCY_CAP", "fail interstitial keeps the gap since the last full-screen ad")
	failed_ctx["level_index"] = 3
	check(policy.interstitial_block_reason(failed_ctx) == "FIRST_LEVEL_GRACE", "no fail interstitial in stages 1-5")
	# QA relax (debug only) to exercise the show path.
	AdsManager.policy.set_qa_relaxed(true)
	ran[0] = 0
	AdsManager.interstitial_opportunity("level_complete", {"level_index": 9}, func(): ran[0] += 1)
	check(fake.count("show_ad") == 1 and ran[0] == 0 and AdsManager.is_presenting(), "show requested, game waits")
	var rid: int = fake.last_args("show_ad")[1]
	var other := [0]
	AdsManager.interstitial_opportunity("level_complete", {"level_index": 10}, func(): other[0] += 1)
	check(other[0] == 1 and AdsManager.last_skip["reason"] == "FULLSCREEN_BUSY", "no second full-screen ad over the first")
	fake.emit_event("ad_showed", {"format": "interstitial", "request_id": rid})
	fake.emit_event("ad_impression", {"format": "interstitial", "request_id": rid})
	fake.emit_event("ad_dismissed", {"format": "interstitial", "request_id": rid})
	fake.emit_event("ad_dismissed", {"format": "interstitial", "request_id": rid})
	check(ran[0] == 1 and not AdsManager.is_presenting(), "continuation runs exactly once after dismissal")
	await get_tree().process_frame
	check(AdsManager.interstitial.state == AdSlot.State.LOADING, "next interstitial preloads after close")
	check(Progress.ad_counters()["fullscreen_count"] >= 1, "shown ad counted for spacing")
	# Provider refuses the show: continue immediately.
	_load_ok("interstitial")
	fake.show_accepts = false
	ran[0] = 0
	AdsManager.interstitial_opportunity("level_complete", {"level_index": 11}, func(): ran[0] += 1)
	check(ran[0] == 1 and not AdsManager.is_presenting(), "refused show continues once")
	fake.show_accepts = true
	# Show failure callback: continue once.
	await get_tree().process_frame
	_load_ok("interstitial")
	ran[0] = 0
	AdsManager.interstitial_opportunity("level_complete", {"level_index": 12}, func(): ran[0] += 1)
	rid = fake.last_args("show_ad")[1]
	fake.emit_event("ad_show_failed", {"format": "interstitial", "request_id": rid, "domain": "com.google.android.gms.ads", "code": 3, "message": "app not foreground"})
	check(ran[0] == 1 and not AdsManager.is_presenting(), "show failure continues once")
	# Not ready: continue now; a later load never shows by itself.
	await get_tree().process_frame
	ran[0] = 0
	var shows := fake.count("show_ad")
	AdsManager.interstitial_opportunity("level_complete", {"level_index": 13}, func(): ran[0] += 1)
	check(ran[0] == 1 and AdsManager.last_skip["reason"] == "LOAD_IN_PROGRESS", "not ready continues immediately")
	_load_ok("interstitial")
	await get_tree().process_frame
	check(fake.count("show_ad") == shows, "no late interstitial after moving on")
	AdsManager.policy.set_qa_relaxed(false)

func _test_rewarded() -> void:
	await _fresh(true)
	_ready_sdk()
	_load_ok("rewarded")
	check(AdsManager.rewarded_offer_state() == "ready", "rewarded ready")
	var earned := []
	var closed := []
	check(AdsManager.show_rewarded("hint", "attempt-1", func(tx: String): earned.append(tx), func(r: Dictionary): closed.append(r)), "rewarded shows")
	var rid: int = fake.last_args("show_ad")[1]
	fake.emit_event("ad_showed", {"format": "rewarded", "request_id": rid})
	check(earned.is_empty(), "showing is not a reward")
	fake.emit_event("ad_impression", {"format": "rewarded", "request_id": rid})
	check(earned.is_empty(), "impression is not a reward")
	fake.emit_event("reward_earned", {"format": "rewarded", "request_id": rid, "type": "coins", "amount": 1})
	fake.emit_event("reward_earned", {"format": "rewarded", "request_id": rid, "type": "coins", "amount": 1})
	check(earned.size() == 1, "duplicate earned callback grants once")
	check(Progress.data["rewards"].has(earned[0]), "reward transaction persisted")
	fake.emit_event("ad_dismissed", {"format": "rewarded", "request_id": rid})
	check(closed.size() == 1 and closed[0]["granted"] == true, "closed after earn reports granted once")
	# Dismissed first, earned inside the grace window: still granted, exactly once.
	await get_tree().process_frame
	_load_ok("rewarded")
	earned.clear()
	closed.clear()
	AdsManager.show_rewarded("continue", "attempt-2", func(tx: String): earned.append(tx), func(r: Dictionary): closed.append(r))
	rid = fake.last_args("show_ad")[1]
	fake.emit_event("ad_dismissed", {"format": "rewarded", "request_id": rid})
	check(closed.is_empty(), "close without reward waits briefly for a late reward")
	fake.emit_event("reward_earned", {"format": "rewarded", "request_id": rid})
	check(earned.size() == 1 and closed.size() == 1 and closed[0]["granted"], "reverse callback order handled")
	# Closing early: no reward.
	await get_tree().process_frame
	_load_ok("rewarded")
	earned.clear()
	closed.clear()
	AdsManager.show_rewarded("hint", "attempt-3", func(tx: String): earned.append(tx), func(r: Dictionary): closed.append(r))
	rid = fake.last_args("show_ad")[1]
	fake.emit_event("ad_dismissed", {"format": "rewarded", "request_id": rid})
	await _wait(0.2)
	check(earned.is_empty() and closed.size() == 1 and not closed[0]["granted"] and closed[0]["reason"] == "dismissed_early", "closing early grants nothing")
	# Not ready: callback reports why, nothing shown.
	closed.clear()
	AdsManager.rewarded.state = AdSlot.State.LOADING
	check(not AdsManager.show_rewarded("hint", "attempt-4", func(_tx: String): pass, func(r: Dictionary): closed.append(r)), "not ready refuses")
	check(closed.size() == 1 and closed[0]["reason"] == "LOAD_IN_PROGRESS", "not ready reason reported")

func _test_lifecycle_and_banner() -> void:
	await _fresh(true)
	_ready_sdk()
	_load_ok("interstitial")
	AdsManager.policy.set_qa_relaxed(true)
	# Background blocks showing.
	AppManager.is_backgrounded = true
	var ran := [0]
	AdsManager.interstitial_opportunity("level_complete", {"level_index": 9}, func(): ran[0] += 1)
	check(ran[0] == 1 and AdsManager.last_skip["reason"] == "APP_BACKGROUND", "background skips")
	AppManager.is_backgrounded = false
	# Lost show: our activity is visibly resumed for a while without any callback → released.
	ran[0] = 0
	AdsManager.interstitial_opportunity("level_complete", {"level_index": 9}, func(): ran[0] += 1)
	check(AdsManager.is_presenting(), "showing")
	AdsManager._on_tick()
	check(AdsManager.is_presenting(), "lock held while there is no evidence the ad is gone")
	fake.emit_event("activity_state", {"resumed": true})
	await _wait(0.12)
	AdsManager._on_tick()
	check(not AdsManager.is_presenting() and ran[0] == 1, "lost show released by real activity state; continuation once")
	AdsManager.policy.set_qa_relaxed(false)
	# Banner: one view, loads only while wanted, hidden when no page wants it.
	var owner := Node.new()
	AdsManager.request_banner(owner, true)
	check(fake.count("banner_configure") == 1 and fake.count("banner_load") == 1, "banner created and loaded once")
	AdsManager.request_banner(owner, true)
	check(fake.count("banner_load") == 1, "no duplicate banner load")
	fake.emit_event("banner_loaded", {"request_id": fake.last_args("banner_load")[0], "height_px": 150, "width_px": 1080})
	check(fake.last_args("banner_set_visible") == [true] or AdsManager.banner["skip_reason"] == "INSUFFICIENT_BANNER_SPACE", "banner shown when it fits")
	AdsManager.request_banner(owner, false)
	check(fake.last_args("banner_set_visible") == [false] or fake.count("banner_set_visible") == 0, "banner hidden when unwanted")
	owner.free()
	# Revenue: micros converted, currency kept.
	fake.emit_event("ad_paid", {"format": "rewarded", "request_id": 1, "value_micros": 1250000, "currency": "USD", "precision": 1})
	var last := Diagnostics.last("ads", "ad_revenue")
	check(is_equal_approx(float(last["data"]["value"]), 1.25) and last["data"]["currency"] == "USD", "revenue micros converted")
	# Restore the real provider state for any later test.
	AdsManager.install_adapter(AdsAdapter.new())
