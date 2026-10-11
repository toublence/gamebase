extends ModalView
## Ad diagnostics (debug / QA builds only; Settings hides the entry elsewhere). Shows the real state
## reported by AdsManager and the native plugin. Developer tooling: English only by design.
var _status: Label
var _log: Label
var _refresh: Timer

func _ready() -> void:
	super._ready()
	if not AdsManager.diagnostics_available():
		close.call_deferred()
		return
	body.add_child(Design.title("Ad diagnostics", 26))
	var tools := HFlowContainer.new()
	tools.add_theme_constant_override("h_separation", 8)
	tools.add_theme_constant_override("v_separation", 8)
	body.add_child(tools)
	for pair in [["Reload interstitial", func(): AdsManager.retry(AdsManager.interstitial)],
			["Reload rewarded", AdsManager.retry_rewarded],
			["Test interstitial", _test_interstitial],
			["Test rewarded", _test_rewarded],
			["Ad Inspector", func(): UI.toast("Ad Inspector opened" if AdsManager.open_ad_inspector() else "Ad Inspector needs an initialized SDK")],
			["Privacy form", AdsManager.show_privacy_options],
			["Consent again", AdsManager.restart_consent_flow],
			["Reset consent", func():
				AdsManager.reset_consent_for_testing()
				UI.toast("UMP consent reset (restart the flow)")],
			["Debug geo: EEA", func():
				AdsManager.debug_geography = 1
				UI.toast("UMP debug geography = EEA; press 'Consent again'")],
			["QA: relax limits", func():
				AdsManager.policy.set_qa_relaxed(not AdsManager.policy.qa_relaxed)
				UI.toast("QA relaxed limits: %s (this run only)" % AdsManager.policy.qa_relaxed)],
			["Export log", _export]]:
		var button := Design.button(pair[0], pair[1], true)
		button.custom_minimum_size = Vector2(0, 52)
		button.add_theme_font_size_override("font_size", 15)
		tools.add_child(button)
	_status = Design.label("", 13, false, 500)
	_status.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	body.add_child(_status)
	body.add_child(Design.label("Recent ad events (newest first)", 15, false, 800))
	_log = Design.label("", 12, true, 500)
	_log.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	body.add_child(_log)
	body.add_child(Design.button("DONE", close))
	_refresh = Timer.new()
	_refresh.wait_time = 1.0
	_refresh.timeout.connect(_render)
	add_child(_refresh)
	_refresh.start()
	_render()

func _render() -> void:
	var s := AdsManager.get_status()
	var lines := PackedStringArray()
	var info: Dictionary = s["provider_info"]
	lines.append("Godot %s | mode %s | provider %s" % [s["godot"], s["mode"], s["provider"]])
	lines.append("plugin %s | SDK %s (%s) | UMP %s" % [info.get("plugin_version", "-"), info.get("sdk_version", "-"),
		info.get("sdk_family", "-"), info.get("ump_version", "-")])
	lines.append("manifest app id: %s" % info.get("manifest_app_id", "-"))
	for key in ["app_id", "banner", "interstitial", "rewarded"]:
		lines.append("  %s = %s" % [key, s["ids"][key]])
	if not s["config_errors"].is_empty():
		lines.append("CONFIG ERRORS: %s" % "; ".join(s["config_errors"]))
	var consent: Dictionary = s["consent"]
	lines.append("consent: %s | canRequestAds %s (live %s) | status %s | privacy options %s" % [consent["state"],
		consent["can_request_ads"], s["can_request_ads_now"], consent["consent_status"], consent["privacy_required"]])
	if not consent["last_error"].is_empty():
		lines.append("  consent error: %s" % JSON.stringify(consent["last_error"]))
	lines.append("sdk: %s %s" % [s["sdk"], JSON.stringify(s["sdk_info"].get("latency_ms", ""))])
	lines.append("activity resumed %s | network %s | form showing %s" % [s["activity_resumed"], s["network_available"], s["form_showing"]])
	lines.append("fullscreen lock: %s" % JSON.stringify(s["fullscreen_lock"]))
	for format in ["interstitial", "rewarded"]:
		var slot: Dictionary = s[format]
		lines.append("%s: %s req#%d fails %d cache %s retry_in %s last %s" % [format, slot["state"], slot["request_id"], slot["failures"],
			_ms(slot["cache_age_ms"]), _ms(slot["next_retry_in_ms"]), slot["last_result"]])
		if not slot["last_error"].is_empty():
			var e: Dictionary = slot["last_error"]
			lines.append("  error kind %s domain %s code %s: %s" % [e.get("kind", ""), e.get("domain", ""), e.get("code", ""), e.get("message", "")])
		if not str(slot["response_id"]).is_empty():
			lines.append("  response id %s" % slot["response_id"])
	var banner: Dictionary = s["banner"]
	lines.append("banner: %s visible %s %dx%dpx (%.0f units) owners %d last %s %s" % [banner["state"], banner["visible"], banner["width_px"],
		banner["height_px"], banner["height_logical"], s["banner_owners"], banner["last_result"], banner["skip_reason"]])
	var last: Dictionary = s["last_skip"]
	lines.append("last not shown: %s %s (%s ago)" % [last["format"], last["reason"], _ms(Time.get_ticks_msec() - int(last["ms"])) if int(last["ms"]) > 0 else "-"])
	var policy: Dictionary = s["policy"]
	lines.append("policy: play %s | session interstitials %d rewarded %d | counters %s | QA relaxed %s" % [_ms(policy["total_play_ms"]),
		policy["session_interstitials"], policy["session_rewarded"], JSON.stringify(policy["counters"]), policy["qa_relaxed"]])
	lines.append("native: %s" % JSON.stringify(s["native"]))
	_status.text = "\n".join(lines)
	var events := Diagnostics.entries("ads")
	var log_lines := PackedStringArray()
	for i in range(events.size() - 1, maxi(-1, events.size() - 40), -1):
		log_lines.append(Diagnostics.format_entry(events[i]))
	_log.text = "\n".join(log_lines)

func _ms(value: Variant) -> String:
	var ms := int(value)
	return "-" if ms < 0 else "%.1fs" % (ms / 1000.0)

func _test_interstitial() -> void:
	AdsManager.interstitial_opportunity("level_complete", {"level_index": 99, "mode": "diagnostics"},
		func(): UI.toast("Interstitial continuation ran (see log)"))

func _test_rewarded() -> void:
	AdsManager.show_rewarded("diagnostics", "diagnostics", func(tx: String): Diagnostics.log_event("ads", "diagnostics_reward_earned", {"tx": tx}),
		func(result: Dictionary): UI.toast("Rewarded closed: granted=%s %s" % [result["granted"], result["reason"]]))

func _export() -> void:
	var path := Diagnostics.save_export({"ads": AdsManager.get_status()})
	DisplayServer.clipboard_set(Diagnostics.export_text({"ads": AdsManager.get_status()}))
	UI.toast("Saved %s and copied to clipboard" % path if not path.is_empty() else "Export failed")
