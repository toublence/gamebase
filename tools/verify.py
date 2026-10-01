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
    if ".godot" in path.parts or path.suffix not in {".gd", ".tscn", ".tres", ".godot"}:
        continue
    for ref in re.findall(r'res://[^"\s]+', path.read_text()):
        if not (ROOT / ref[6:]).exists():
            errors.append(f"Missing resource: {path.relative_to(ROOT)} -> {ref}")
source_keys = set(re.findall(r'^msgid "(.+)"', (ROOT / "localization/en.po").read_text(), re.M))
for path in (ROOT / "localization").glob("*.po"):
    keys = set(re.findall(r'^msgid "(.+)"', path.read_text(), re.M))
    if keys != source_keys:
        errors.append(f"Locale key mismatch: {path.name}")
presets = (ROOT / "export_presets.cfg").read_text()
if presets.count('permissions/vibrate=true') != 2:
    errors.append("Android preset mismatch: permissions/vibrate=true")
# Godot refuses to export when SDK levels are overridden without the Gradle build. The Debug APK
# preset uses the template's own min 24 / target 36; only the Gradle Release preset overrides them.
for setting in ['gradle_build/min_sdk="24"', 'gradle_build/target_sdk="36"']:
    if presets.count(setting) != 1:
        errors.append(f"Only the Gradle release preset may set {setting}")
for index, block in enumerate(presets.split("[preset.")[1:]):
    if 'gradle_build/use_gradle_build=false' in block and re.search(r'gradle_build/(min|target)_sdk="\d', block):
        errors.append(f"Preset {index}: SDK override requires use_gradle_build=true")
if "textures/vram_compression/import_etc2_astc=true" not in (ROOT / "project.godot").read_text():
    errors.append("Android export requires ETC2/ASTC import (rendering/textures/vram_compression/import_etc2_astc)")
if presets.count('exclude_filter="tests/*,tools/*,docs/*,*.md"') != 2:
    errors.append("Verification files must be excluded from both exports")
if errors:
    print("\n".join(errors))
    sys.exit(1)
print(f"Static resources, {len(source_keys)} keys in 9 locales, export presets: OK", flush=True)
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
