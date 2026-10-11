extends AdsAdapter
## Forwards calls to the OuttapAds Android plugin (android_plugin/, packaged by addons/outtap_ads)
## and relays its "ads_event(name, json)" signal. All SDK work happens in Java on the main thread;
## Godot delivers the signal on its own thread.
var _plugin: Object

func connect_provider() -> Dictionary:
	_plugin = Engine.get_singleton("OuttapAds")
	if _plugin == null:
		return {"ok": false, "provider": "missing", "reason": "plugin_missing"}
	_plugin.connect("ads_event", _on_native_event)
	var info: Variant = JSON.parse_string(str(_plugin.getInfo()))
	var result: Dictionary = info if info is Dictionary else {}
	result["ok"] = true
	result["provider"] = "connected"
	return result

func _on_native_event(name: String, json: String) -> void:
	var data: Variant = JSON.parse_string(json)
	var payload: Dictionary = data if data is Dictionary else {}
	for key in ["request_id", "code", "consent_status", "precision", "height_px", "width_px"]:
		if payload.has(key):
			payload[key] = int(payload[key])
	if payload.has("value_micros"):
		payload["value_micros"] = int(payload["value_micros"])
	sdk_event.emit(name, payload)

func configure(config: Dictionary) -> void:
	_plugin.configure(JSON.stringify(config))

func request_consent_update(debug: Dictionary) -> void:
	_plugin.requestConsentInfoUpdate(int(debug.get("debug_geography", 0)))

func can_request_ads() -> bool:
	return bool(_plugin.canRequestAds())

func privacy_options_required() -> bool:
	return bool(_plugin.isPrivacyOptionsRequired())

func load_and_show_consent_form_if_required() -> void:
	_plugin.loadAndShowConsentFormIfRequired()

func show_privacy_options_form() -> void:
	_plugin.showPrivacyOptionsForm()

func initialize_sdk() -> void:
	_plugin.initializeSdk()

func load_ad(format: String, request_id: int, unit_id: String) -> void:
	_plugin.loadAd(format, request_id, unit_id)

func show_ad(format: String, request_id: int) -> bool:
	return bool(_plugin.showAd(format, request_id))

func discard_ad(format: String, request_id: int) -> void:
	_plugin.discardAd(format, request_id)

func banner_configure(unit_id: String) -> void:
	_plugin.bannerConfigure(unit_id)

func banner_load(request_id: int) -> void:
	_plugin.bannerLoad(request_id)

func banner_set_visible(visible: bool) -> void:
	_plugin.bannerSetVisible(visible)

func banner_destroy() -> void:
	_plugin.bannerDestroy()

func open_ad_inspector() -> bool:
	return bool(_plugin.openAdInspector())

func is_activity_resumed() -> bool:
	return bool(_plugin.isActivityResumed())

func reset_consent() -> void:
	_plugin.resetConsent()

func native_status() -> Dictionary:
	var data: Variant = JSON.parse_string(str(_plugin.nativeStatus()))
	return data if data is Dictionary else {}
