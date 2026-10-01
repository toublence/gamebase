class_name AdsAdapter
extends Node
## Override with a native SDK provider. Default is offline/no-op, never grants rewards.
## Every show must eventually emit dismissed or failed with its request id.
signal consent_resolved(can_request_ads: bool)
signal impression(request_id: int, format: String)
signal reward_earned(request_id: int)
signal dismissed(request_id: int)
signal failed(request_id: int)

func configure(_ids: Dictionary) -> void:
	return

func request_consent() -> void:
	consent_resolved.emit(false)
func privacy_options_required() -> bool:
	return false
func show_privacy_options() -> void:
	consent_resolved.emit(false)
func interstitial_ready() -> bool:
	return false
func rewarded_ready() -> bool:
	return false
func present_interstitial(_request_id: int) -> bool:
	return false
func present_rewarded(_request_id: int) -> bool:
	return false
func cancel(_request_id: int) -> void:
	return
