class_name AdSlot
extends RefCounted
## One full-screen format (interstitial or rewarded). Lifecycle:
## EMPTY → LOADING → READY → SHOWING → EMPTY; failures go to BACKOFF (retry later) or BLOCKED
## (configuration error, no automatic retry). Only one load is ever in flight per slot; a callback
## whose request_id does not match the current request is stale and cannot change the state.
enum State { EMPTY, LOADING, READY, SHOWING, BACKOFF, BLOCKED }

var format := ""
var unit_id := ""
var state := State.EMPTY
var request_id := 0
var load_started_ms := 0
var loaded_ms := 0
var failures := 0
var next_retry_ms := 0
var last_request_ms := 0
var last_result := ""
var last_error := {}
var response_id := ""
var response_info := {}
var waiting_for_network := false

func _init(slot_format: String, unit: String) -> void:
	format = slot_format
	unit_id = unit

func state_name() -> String:
	return State.keys()[state]

func cache_age_ms(now: int) -> int:
	return now - loaded_ms if state == State.READY else -1

func snapshot(now: int) -> Dictionary:
	return {"format": format, "state": state_name(), "request_id": request_id, "failures": failures,
		"cache_age_ms": cache_age_ms(now), "next_retry_in_ms": maxi(0, next_retry_ms - now) if state == State.BACKOFF else 0,
		"last_request_ms_ago": now - last_request_ms if last_request_ms > 0 else -1, "last_result": last_result,
		"last_error": last_error.duplicate(), "response_id": response_id, "waiting_for_network": waiting_for_network}
