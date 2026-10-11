class_name AdPolicy
extends RefCounted
## Every frequency number in one place. These are first-test values, not tuned optima.
## Limits gate showing only; preloading is never blocked by them.
const DEFAULTS := {
	# Interstitial: on the "next stage" transition after a clear, and on "restart" from the fail
	# sheet (never on the fail sheet itself or the free checkpoint).
	"interstitial_placements": ["level_complete", "level_failed"],
	"interstitial_exempt_levels": 5, # no interstitial after stages 1-5
	"interstitial_min_play_ms": 180000, # first 180 s of real play since install
	"interstitial_min_new_clears": 3, # new (first-time) clears since the last full-screen ad
	"fullscreen_gap_play_ms": 150000, # real play time since the last full-screen ad (incl. rewarded)
	"interstitial_session_cap": 4, # per app process
	# Loading
	"retry_backoff_s": [15, 30, 60, 120],
	"retry_jitter": 0.2,
	"load_timeout_ms": 60000,
	"cache_ttl_ms": 3300000, # interstitial/rewarded expire after 1 h; refresh a bit earlier
	# Showing
	"stuck_show_resumed_ms": 6000, # SHOWING while our activity is visibly resumed this long = lost
	"reward_grace_ms": 1500, # wait for a late earned-reward callback after dismissal
	"banner_min_content_height": 600.0, # logical units the page keeps above an anchored banner
}

var values := DEFAULTS.duplicate(true)
## Debug-only QA override (not persisted, not available in release): ignores the grace/frequency
## limits so the full show path can be exercised quickly. Never the default.
var qa_relaxed := false

func set_qa_relaxed(on: bool) -> void:
	qa_relaxed = on and OS.is_debug_build()

## Returns "" when an interstitial may be shown at this opportunity, otherwise a skip reason.
func interstitial_block_reason(ctx: Dictionary) -> String:
	if not values["interstitial_placements"].has(str(ctx.get("placement", ""))):
		return "NOT_A_TRANSITION"
	# Product rule, also under QA: nothing full-screen right before a HARD stage starts.
	if bool(ctx.get("next_hard", false)):
		return "HARD_AHEAD"
	if qa_relaxed:
		return ""
	if str(ctx.get("mode", "campaign")) == "campaign" and int(ctx.get("level_index", 0)) <= int(values["interstitial_exempt_levels"]):
		return "FIRST_LEVEL_GRACE"
	if int(ctx.get("total_play_ms", 0)) < int(values["interstitial_min_play_ms"]):
		return "PLAYTIME_GRACE"
	if int(ctx.get("session_interstitials", 0)) >= int(values["interstitial_session_cap"]):
		return "FREQUENCY_CAP"
	# New clears pace the clear transition only; a lost board is its own break.
	if str(ctx.get("placement", "")) == "level_complete" and int(ctx.get("new_clears_since_fullscreen", 0)) < int(values["interstitial_min_new_clears"]):
		return "FREQUENCY_CAP"
	var since_ad := int(ctx.get("total_play_ms", 0)) - int(ctx.get("play_ms_at_last_fullscreen", 0))
	if int(ctx.get("fullscreen_count", 0)) > 0 and since_ad < int(values["fullscreen_gap_play_ms"]):
		return "FREQUENCY_CAP"
	return ""

## Exponential backoff with jitter: 15 → 30 → 60 → 120 s (capped).
func backoff_ms(failures: int, roll: float) -> int:
	var steps: Array = values["retry_backoff_s"]
	var base := float(steps[clampi(failures - 1, 0, steps.size() - 1)]) * 1000.0
	var jitter := float(values["retry_jitter"])
	return int(base * (1.0 + (roll * 2.0 - 1.0) * jitter))
