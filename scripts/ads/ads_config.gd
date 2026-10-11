class_name AdsConfig
extends RefCounted
## Single source of ad unit configuration. Read by AdsManager at runtime and by the Android export
## plugin (addons/outtap_ads) when it writes the manifest App ID, so the two can never disagree.
##
## Mode: debug builds and builds exported with the "ads_test" custom feature use Google's official
## Android test IDs. Every other build is production and must have real IDs below; tools/
## export_release.py and the export plugin refuse to ship production with empty or test IDs, and at
## runtime an invalid production config disables ads with INVALID_CONFIGURATION (never falls back
## to test IDs).
const TEST_PUBLISHER := "ca-app-pub-3940256099942544"
const FEATURE_TEST_ADS := "ads_test"

## https://developers.google.com/admob/android/test-ads (Android only; not the iOS sample IDs).
const TEST_IDS := {
	"app_id": "ca-app-pub-3940256099942544~3347511713",
	"banner": "ca-app-pub-3940256099942544/9214589741",
	"interstitial": "ca-app-pub-3940256099942544/1033173712",
	"rewarded": "ca-app-pub-3940256099942544/5224354917",
}

## Fill from the AdMob console (Apps → Outtap → Ad units) before a store build.
const PRODUCTION_IDS := {
	"app_id": "",
	"banner": "",
	"interstitial": "",
	"rewarded": "",
}

## Request policy. Outtap is a general-audience puzzle game that is not directed at children.
## These values must match the Play Console target-audience declaration; if the audience ever
## includes children, set child_directed to 1 and review Families policy before release.
## -1 = unspecified (SDK default), 0 = false, 1 = true.
const REQUEST := {
	"max_ad_content_rating": "PG",
	"child_directed": -1,
	"under_age_of_consent": -1,
}

static func mode() -> String:
	return "test" if OS.is_debug_build() or OS.has_feature(FEATURE_TEST_ADS) else "production"

static func ids(for_mode: String = "") -> Dictionary:
	return (TEST_IDS if (for_mode if not for_mode.is_empty() else mode()) == "test" else PRODUCTION_IDS).duplicate()

## Returns human-readable problems; empty means the IDs may be used in that mode.
static func validate(for_mode: String, values: Dictionary) -> Array[String]:
	var problems: Array[String] = []
	var app_id := str(values.get("app_id", ""))
	var app_re := RegEx.create_from_string("^ca-app-pub-\\d{16}~\\d{10}$")
	var unit_re := RegEx.create_from_string("^ca-app-pub-\\d{16}/\\d{10}$")
	if app_re.search(app_id) == null:
		problems.append("app_id must look like ca-app-pub-XXXXXXXXXXXXXXXX~YYYYYYYYYY (uses ~)")
	for key in ["banner", "interstitial", "rewarded"]:
		var unit := str(values.get(key, ""))
		if unit_re.search(unit) == null:
			problems.append("%s unit must look like ca-app-pub-XXXXXXXXXXXXXXXX/YYYYYYYYYY (uses /)" % key)
	if for_mode == "production":
		for key in values:
			if str(values[key]).contains(TEST_PUBLISHER):
				problems.append("%s uses the Google test publisher in a production build" % key)
	else:
		for key in TEST_IDS:
			if str(values.get(key, "")) != TEST_IDS[key]:
				problems.append("%s is not the official Android test ID in test mode" % key)
	return problems
