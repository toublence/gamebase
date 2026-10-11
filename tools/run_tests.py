#!/usr/bin/env python3
"""Runs every Outtap automated check with a hard time limit per process and prints a summary.
  python3 tools/run_tests.py            # all
  python3 tools/run_tests.py --quick    # skip the 10,000-board generator property test
"""
from pathlib import Path
import os
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
GODOT = os.environ.get("GODOT") or shutil.which("godot") or "/Applications/Godot.app/Contents/MacOS/Godot"
QUICK = "--quick" in sys.argv

SUITES = [
    ("parse", [GODOT, "--headless", "--path", ".", "res://tests/parse_check.tscn"], r"PARSE_CHECK failures=(\d+)", 120),
    ("arrow core rules", [GODOT, "--headless", "--path", ".", "-s", "res://tests/arrow_core_tests.gd"], r"ARROW_CORE_TESTS: (\d+) checks, (\d+) failures", 120),
    ("arrow game flow", [GODOT, "--headless", "--path", ".", "res://tests/arrow_flow_tests.tscn", "--", "--verify-base"], r"ARROW_FLOW_TESTS: (\d+) checks, (\d+) failures", 180),
    ("ads state machine", [GODOT, "--headless", "--path", ".", "res://tests/ads_tests.tscn", "--", "--verify-base"], r"ADS_TESTS: (\d+) checks, (\d+) failures", 180),
    ("base flow", [GODOT, "--headless", "--path", ".", "res://tests/verify.tscn", "--", "--verify-base"], r"BASE_VERIFY: (\d+) checks, (\d+) failures", 120),
    ("level data (python)", [sys.executable, "tools/validate_arrow_levels.py"], r"All (\d+) arrow-path-2 levels pass", 60),
]
if not QUICK:
    SUITES.append(("generator properties x10000", [GODOT, "--headless", "--path", ".", "-s", "res://tests/arrow_generator_property_tests.gd", "--", "10000"],
                   r"ARROW_GENERATOR_PROPERTIES: boards=(\d+) .*failures=(\d+)", 900))

failed = False
for name, command, pattern, limit in SUITES:
    if not (ROOT / command[-1].replace("res://", "")).exists() and command[-1].startswith("res://") and "--" not in command:
        pass
    try:
        result = subprocess.run(command, cwd=ROOT, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=limit)
        out = result.stdout
    except subprocess.TimeoutExpired as exc:
        out = (exc.stdout or "") if isinstance(exc.stdout, str) else ""
        print(f"[TIMEOUT] {name} after {limit}s")
        failed = True
        continue
    match = re.search(pattern, out)
    errors = re.findall(r"(SCRIPT ERROR.*|Parse Error.*)", out)
    ok = match is not None and result.returncode == 0 and not errors
    if match and len(match.groups()) == 2 and int(match.group(2)) != 0:
        ok = False
    if name == "parse" and match and int(match.group(1)) != 0:
        ok = False
    print(f"[{'PASS' if ok else 'FAIL'}] {name}: {match.group(0) if match else 'no result line'}")
    if not ok:
        failed = True
        for line in out.splitlines():
            if re.search(r"FAIL|ERROR|Parse Error|PARSE_FAIL", line) and not line.startswith("["):
                print("    " + line)
sys.exit(1 if failed else 0)
