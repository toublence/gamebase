@tool
extends EditorExportPlugin
## Android export glue for OuttapAds. Ad mode follows AdsConfig: debug exports and presets with the
## "ads_test" custom feature use Google's Android test IDs; any other export is production and
## must carry valid production IDs. An invalid production config is not shipped with the SDK at
## all (the game then reports PLUGIN_MISSING / INVALID_CONFIGURATION instead of crashing at launch
## on a missing App ID); tools/export_release.py refuses such exports before they start.
const AdsConfigScript := preload("res://scripts/ads/ads_config.gd")
## Keep in sync with android_plugin/outtap_ads/build.gradle.
const DEPENDENCIES := [
	"com.google.android.gms:play-services-ads:25.5.0",
	"com.google.android.ump:user-messaging-platform:4.0.0",
]

func _get_name() -> String:
	return "OuttapAds"

func _supports_platform(platform: EditorExportPlatform) -> bool:
	return platform is EditorExportPlatformAndroid

func _mode(debug: bool) -> String:
	var preset := get_export_preset()
	var features := preset.get_custom_features() if preset != null else ""
	return "test" if debug or AdsConfigScript.FEATURE_TEST_ADS in features.split(",", false) else "production"

func _usable(debug: bool) -> bool:
	var mode := _mode(debug)
	var problems := AdsConfigScript.validate(mode, AdsConfigScript.ids(mode))
	if not problems.is_empty():
		push_error("OuttapAds: %s ad configuration is invalid; the ads SDK is NOT packaged: %s" % [mode, "; ".join(problems)])
		return false
	return true

func _get_android_libraries(_platform: EditorExportPlatform, debug: bool) -> PackedStringArray:
	if not _usable(debug):
		return PackedStringArray()
	# Relative to res://addons/
	return PackedStringArray(["outtap_ads/bin/outtap_ads-%s.aar" % ("debug" if debug else "release")])

func _get_android_dependencies(_platform: EditorExportPlatform, debug: bool) -> PackedStringArray:
	return PackedStringArray(DEPENDENCIES) if _usable(debug) else PackedStringArray()

func _get_android_manifest_application_element_contents(_platform: EditorExportPlatform, debug: bool) -> String:
	if not _usable(debug):
		return ""
	var app_id := str(AdsConfigScript.ids(_mode(debug))["app_id"])
	return '\n        <meta-data android:name="com.google.android.gms.ads.APPLICATION_ID" android:value="%s"/>\n' % app_id
