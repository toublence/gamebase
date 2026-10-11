#!/usr/bin/env python3
"""One bounded verification command. No APK build, installs, or production saves."""
from pathlib import Path
import os
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
GODOT = os.environ.get("GODOT") or shutil.which("godot") or "/Applications/Godot.app/Contents/MacOS/Godot"
errors = []
for path in ROOT.rglob("*"):
    if {".godot", "android", "android_plugin"} & set(path.parts) or path.suffix not in {".gd", ".tscn", ".tres", ".godot"}:
        continue
    for ref in re.findall(r'res://[^"\s]+', path.read_text()):
        if "%" in ref:
            continue  # format templates (checked explicitly below)
        if not (ROOT / ref[6:]).exists():
            errors.append(f"Missing resource: {path.relative_to(ROOT)} -> {ref}")
# Voice cheers: every line the game can ask for exists in English (used for every UI language).
for lang in ["en"]:
    for line in ["good", "nice", "yes", "woo", "bravo", "yahoo", "wow"]:
        if not (ROOT / f"assets/voice/{lang}/{line}.wav").exists():
            errors.append(f"Missing voice file: assets/voice/{lang}/{line}.wav")
source_keys = set(re.findall(r'^msgid "(.+)"', (ROOT / "localization/en.po").read_text(), re.M))
for path in (ROOT / "localization").glob("*.po"):
    keys = set(re.findall(r'^msgid "(.+)"', path.read_text(), re.M))
    if keys != source_keys:
        errors.append(f"Locale key mismatch: {path.name}")
presets = (ROOT / "export_presets.cfg").read_text()
# Each preset is "[preset.N]" plus "[preset.N.options]"; check them together.
grouped = {}
for chunk in presets.split("[preset.")[1:]:
    grouped.setdefault(chunk.split("]")[0].split(".")[0], []).append(chunk)
blocks = ["\n".join(chunks) for chunks in grouped.values()]
EXCLUDE = 'exclude_filter="tests/*,tools/*,docs/*,build/*,*.md,android_plugin/*,game/data/legacy/*,game/legacy/*,assets/voice/ko/*"'
for index, block in enumerate(blocks):
    for setting in ["permissions/vibrate=true", "permissions/internet=true", "permissions/access_network_state=true",
                    'package/unique_name="com.namslab.outtap"', "gradle_build/use_gradle_build=true"]:
        if setting not in block:
            errors.append(f"Preset {index}: missing {setting} (the ads plugin needs the Gradle build)")
    if EXCLUDE not in block:
        errors.append(f"Preset {index}: tests/tools/docs/plugin sources/legacy content must be excluded")
    # Godot refuses SDK overrides without the Gradle build.
    if 'gradle_build/use_gradle_build=false' in block and re.search(r'gradle_build/(min|target)_sdk="\d', block):
        errors.append(f"Preset {index}: SDK override requires use_gradle_build=true")
if "textures/vram_compression/import_etc2_astc=true" not in (ROOT / "project.godot").read_text():
    errors.append("Android export requires ETC2/ASTC import (rendering/textures/vram_compression/import_etc2_astc)")
if 'res://addons/outtap_ads/plugin.cfg' not in (ROOT / "project.godot").read_text():
    errors.append("OuttapAds editor plugin must be enabled (it packages the Android plugin)")
for aar in ["addons/outtap_ads/bin/outtap_ads-debug.aar", "addons/outtap_ads/bin/outtap_ads-release.aar"]:
    if not (ROOT / aar).exists():
        errors.append(f"Missing {aar}: run tools/build_android_plugin.sh")
level_check = subprocess.run([sys.executable, str(ROOT / "tools/validate_arrow_levels.py")], capture_output=True, text=True)
if level_check.returncode != 0:
    errors.append("Level data check failed:\n" + level_check.stdout)
if errors:
    print("\n".join(errors))
    sys.exit(1)
print(f"Static resources, {len(source_keys)} keys in 9 locales, export presets, ads plugin, level data: OK", flush=True)
commands = [
    [GODOT, "--headless", "--path", str(ROOT), "--editor", "--import"],
    [GODOT, "--headless", "--path", str(ROOT), "res://tests/verify.tscn", "--", "--verify-base"],
]
for command in commands:
    try:
        result = subprocess.run(command, cwd=ROOT, text=True, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, timeout=50)
    except subprocess.TimeoutExpired as exc:
        print(exc.stdout or "", "Verification timed out", sep="\n")
        sys.exit(1)
    print(result.stdout)
    if result.returncode or re.search(r"SCRIPT ERROR|Parse Error|ERROR:", result.stdout):
        sys.exit(1)
print("All base checks passed.")
