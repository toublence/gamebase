#!/usr/bin/env python3
"""Fail before export when a copied game still contains template identity/test IDs."""
from pathlib import Path
import os
import shutil
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
project = (root / 'project.godot').read_text()
presets = (root / 'export_presets.cfg').read_text()
problems = []
for marker in ['Namslab Base', 'Namslab/gamebase', 'com.namslab.gamebase.template']:
    if marker in project or marker in presets:
        problems.append(f'Replace template identity: {marker}')
for path in [root / 'project.godot', root / 'export_presets.cfg', *(root / 'resources').rglob('*.tres')]:
    if 'ca-app-pub-3940256099942544' in path.read_text():
        problems.append(f'Google test ID in release configuration: {path.relative_to(root)}')
if not (root / 'android/build').is_dir():
    problems.append('Install the matching Godot Android Gradle build template first.')
if problems:
    sys.exit('\n'.join(problems))
engine = os.environ.get('GODOT') or shutil.which('godot') or '/Applications/Godot.app/Contents/MacOS/Godot'
(root / 'build').mkdir(exist_ok=True)
sys.exit(subprocess.call([engine, '--headless', '--path', str(root), '--export-release', 'Android Release']))
