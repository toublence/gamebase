extends AdsAdapter
## Test double for AdsManager error-injection tests. It never runs in a build (tests/ is excluded
## from exports) and its events are labelled as fake in the diagnostics log by the test.
var calls: Array = []
var consent_allows := false
var privacy_required := false
var show_accepts := true
var activity_resumed := true

func connect_provider() -> Dictionary:
	return {"ok": true, "provider": "fake", "manifest_app_id": AdsConfig.TEST_IDS["app_id"], "sdk_version": "fake"}

func _record(name: String, args: Array = []) -> void:
	calls.append([name, args])

func count(name: String) -> int:
	var n := 0
	for c in calls:
		if c[0] == name:
			n += 1
	return n

func last_args(name: String) -> Array:
	for i in range(calls.size() - 1, -1, -1):
		if calls[i][0] == name:
			return calls[i][1]
	return []

func emit_event(name: String, data: Dictionary = {}) -> void:
	sdk_event.emit(name, data)

func configure(config: Dictionary) -> void:
	_record("configure", [config])

func request_consent_update(debug: Dictionary) -> void:
	_record("request_consent_update", [debug])

func can_request_ads() -> bool:
	return consent_allows

func privacy_options_required() -> bool:
	return privacy_required

func load_and_show_consent_form_if_required() -> void:
	_record("load_and_show_consent_form")

func show_privacy_options_form() -> void:
	_record("show_privacy_options_form")

func initialize_sdk() -> void:
	_record("initialize_sdk")

func load_ad(format: String, request_id: int, unit_id: String) -> void:
	_record("load_ad", [format, request_id, unit_id])

func show_ad(format: String, request_id: int) -> bool:
	_record("show_ad", [format, request_id])
	return show_accepts

func discard_ad(format: String, request_id: int) -> void:
	_record("discard_ad", [format, request_id])

func banner_configure(unit_id: String) -> void:
	_record("banner_configure", [unit_id])

func banner_load(request_id: int) -> void:
	_record("banner_load", [request_id])

func banner_set_visible(visible: bool) -> void:
	_record("banner_set_visible", [visible])

func is_activity_resumed() -> bool:
	return activity_resumed
