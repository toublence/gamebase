class_name AdsAdapter
extends Node
## Provider boundary. AdsManager owns all state and policy; an adapter only forwards calls to a
## native SDK and reports what the SDK actually said through `sdk_event(name, data)`.
## This base class is the "no native ads on this platform" provider (desktop editor). It never
## fakes consent, loads, impressions or rewards.
##
## Events (data keys):
##   consent_info_updated  {can_request_ads, consent_status, privacy_required}
##   consent_info_failed   {code, message, can_request_ads}
##   consent_form_dismissed / privacy_form_dismissed {code?, message?, can_request_ads, privacy_required}
##   sdk_initialized       {adapters, latency_ms}
##   ad_loaded             {format, request_id, response_id, response_info}
##   ad_load_failed        {format, request_id, domain, code, message, response_id, response_info}
##   ad_showed / ad_impression / ad_clicked / ad_dismissed {format, request_id}
##   ad_show_failed        {format, request_id, domain, code, message}
##   reward_earned         {format, request_id, type, amount}
##   ad_paid               {format, request_id, value_micros, currency, precision}
##   banner_loaded         {request_id, width_px, height_px, response_id}
##   banner_failed         {request_id, domain, code, message}
##   banner_impression / banner_paid
##   activity_state        {resumed}
##   network_state         {available}
##   ad_inspector_closed   {code, message}
signal sdk_event(name: String, data: Dictionary)

## {ok, provider, plugin_version, sdk_version, ump_version, manifest_app_id, reason?}
func connect_provider() -> Dictionary:
	return {"ok": false, "provider": "none", "reason": "unsupported_platform"}

func configure(_config: Dictionary) -> void:
	pass

func request_consent_update(_debug: Dictionary) -> void:
	pass

func can_request_ads() -> bool:
	return false

func privacy_options_required() -> bool:
	return false

func load_and_show_consent_form_if_required() -> void:
	pass

func show_privacy_options_form() -> void:
	pass

func initialize_sdk() -> void:
	pass

func load_ad(_format: String, _request_id: int, _unit_id: String) -> void:
	pass

## Returns whether the provider accepted the show call. When false, no further callbacks follow.
func show_ad(_format: String, _request_id: int) -> bool:
	return false

func discard_ad(_format: String, _request_id: int) -> void:
	pass

func banner_configure(_unit_id: String) -> void:
	pass

func banner_load(_request_id: int) -> void:
	pass

func banner_set_visible(_visible: bool) -> void:
	pass

func banner_destroy() -> void:
	pass

func open_ad_inspector() -> bool:
	return false

func is_activity_resumed() -> bool:
	return true

func reset_consent() -> void:
	pass

func native_status() -> Dictionary:
	return {}
