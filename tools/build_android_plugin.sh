#!/bin/sh
# Builds the OuttapAds Godot Android plugin AARs and copies them into addons/outtap_ads/bin.
# Requires the Godot 4.7.2 Android build template installed in android/build (Project → Install
# Android Build Template, or see docs/ADMOB_INTEGRATION.md) and a JDK 17.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
AAR="$ROOT/android/build/libs/release/godot-lib.template_release.aar"
[ -f "$AAR" ] || { echo "Missing $AAR — install the Godot 4.7.2 Android build template first."; exit 1; }
mkdir -p "$ROOT/android_plugin/libs"
TMP="$(mktemp -d)"
unzip -q -o "$AAR" classes.jar -d "$TMP"
mv "$TMP/classes.jar" "$ROOT/android_plugin/libs/godot-lib-4.7.2-classes.jar"
rmdir "$TMP"
if [ -z "${JAVA_HOME:-}" ] && [ -x /usr/libexec/java_home ]; then
  JAVA_HOME="$(/usr/libexec/java_home -v 17 2>/dev/null || true)"; export JAVA_HOME
fi
cd "$ROOT/android_plugin"
./gradlew --no-daemon -q :outtap_ads:assembleDebug :outtap_ads:assembleRelease
cp outtap_ads/build/outputs/aar/outtap_ads-debug.aar "$ROOT/addons/outtap_ads/bin/outtap_ads-debug.aar"
cp outtap_ads/build/outputs/aar/outtap_ads-release.aar "$ROOT/addons/outtap_ads/bin/outtap_ads-release.aar"
echo "OuttapAds AARs updated in addons/outtap_ads/bin"
