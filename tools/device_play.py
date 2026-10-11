#!/usr/bin/env python3
"""Device QA driver for a debug build of Outtap on a connected Android phone.

It reads the debug-only layout/button log lines the game prints, then sends real `adb shell input
tap` events: arrows are tapped in each level's stored solution order (with one deliberate tap on a
blocked arrow on a hearts level), result sheets are advanced with their real buttons, and
screenshots plus a screen recording are saved to build/device_qa/. This proves the levels can be
completed through the real touch path on that device; it does not judge fun or feel.

Usage: python3 tools/device_play.py [LEVEL_COUNT] [--fresh]
  --fresh  clears the app's data first (first-launch flow)
"""
from pathlib import Path
import json
import os
import re
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "build/device_qa"
PKG = "com.namslab.outtap"
LEVELS = {lv["id"]: lv for lv in json.loads((ROOT / "game/data/v2/campaign.json").read_text())["levels"]}


def serial():
    if os.environ.get("ANDROID_SERIAL"):
        return os.environ["ANDROID_SERIAL"]
    lines = subprocess.run(["adb", "devices"], capture_output=True, text=True).stdout.splitlines()[1:]
    devices = [l.split()[0] for l in lines if l.strip().endswith("device")]
    if not devices:
        sys.exit("No device")
    return devices[0]


SERIAL = serial()


def adb(*args, text=True):
    return subprocess.run(["adb", "-s", SERIAL, *args], capture_output=True, text=text)


def log_events():
    out = adb("logcat", "-d", "-s", "godot:V").stdout
    events = []
    for line in out.splitlines():
        m = re.search(r"\[(\w+)\] (\w+) (\{.*\})\s*$", line)
        if m:
            try:
                events.append((m.group(1), m.group(2), json.loads(m.group(3))))
            except json.JSONDecodeError:
                pass
    return events


def wait_for(cat, event, after, timeout=20.0, predicate=None):
    end = time.time() + timeout
    while time.time() < end:
        events = log_events()
        for i in range(len(events) - 1, after - 1, -1):
            c, e, d = events[i]
            if c == cat and e == event and (predicate is None or predicate(d)):
                return i, d
        time.sleep(0.3)
    raise TimeoutError(f"no {cat}/{event}")


def tap(x, y, pause=0.0):
    adb("shell", "input", "tap", str(int(x)), str(int(y)))
    if pause:
        time.sleep(pause)


def shot(name):
    data = subprocess.run(["adb", "-s", SERIAL, "exec-out", "screencap", "-p"], capture_output=True).stdout
    (OUT / f"{name}.png").write_bytes(data)
    print("  screenshot", name)


def arrow_point(level, layout, arrow_id):
    flat = level["a"][arrow_id]
    cells = [(flat[i], flat[i + 1]) for i in range(0, len(flat), 2)]
    cx, cy = cells[len(cells) // 2]
    s = layout["screen_scale"]
    return ((layout["x"] + (cx + 0.5) * layout["cell"]) * s, (layout["y"] + (cy + 0.5) * layout["cell"]) * s)


def blocked_arrow(level):
    occ = {}
    for i, flat in enumerate(level["a"]):
        for k in range(0, len(flat), 2):
            occ[(flat[k], flat[k + 1])] = i
    for i, flat in enumerate(level["a"]):
        (hx, hy), (px, py) = (flat[-2], flat[-1]), (flat[-4], flat[-3])
        dx, dy = hx - px, hy - py
        x, y = hx + dx, hy + dy
        while 0 <= x < level["w"] and 0 <= y < level["h"]:
            if (x, y) in occ:
                return i
            x, y = x + dx, y + dy
    return None


def main():
    count = int(next((a for a in sys.argv[1:] if a.isdigit()), "20"))
    OUT.mkdir(parents=True, exist_ok=True)
    adb("shell", "am", "force-stop", PKG)
    if "--fresh" in sys.argv:
        adb("shell", "pm", "clear", PKG)
    adb("logcat", "-c")
    record = subprocess.Popen(["adb", "-s", SERIAL, "shell", "screenrecord", "--bit-rate", "6000000", "--time-limit", "175", "/sdcard/outtap_qa.mp4"])
    adb("shell", "monkey", "-p", PKG, "-c", "android.intent.category.LAUNCHER", "1")
    idx, buttons = wait_for("ui", "buttons", 0, 30, lambda d: d["tag"] == "route")
    if buttons["route"] == "menu":
        shot("01_home")
        key = "CONTINUE" if "CONTINUE" in buttons["buttons"] else "START"
        tap(*buttons["buttons"][key])
    played = 0
    cursor = idx
    while played < count:
        cursor, started = wait_for("analytics", "level_started", cursor + 1, 30)
        level = LEVELS[started["level_id"]]
        cursor, layout = wait_for("board", "layout", cursor, 20)
        time.sleep(0.5)
        _, layout = wait_for("board", "layout", cursor, 5)  # latest after settling
        number = int(level["id"][1:])
        print(f"level {level['id']} ({len(level['a'])} arrows)")
        if number in (1, 8, 20):
            shot(f"{number:02d}_start")
        if number == 4:
            blocked = blocked_arrow(level)
            if blocked is not None:
                tap(*arrow_point(level, layout, blocked), 0.12)
                shot("04_collision")
                time.sleep(0.6)
        for k, arrow_id in enumerate(level["sol"]):
            tap(*arrow_point(level, layout, arrow_id), 0.18)
            if number == 8 and k == 1:
                shot("08_escaping")
        cursor, sheet = wait_for("ui", "buttons", cursor, 20, lambda d: d["tag"] == "sheet")
        if number in (1, 4, 20):
            shot(f"{number:02d}_clear")
        played += 1
        if played < count and "NEXT_STAGE" in sheet["buttons"]:
            tap(*sheet["buttons"]["NEXT_STAGE"])
        else:
            tap(*sheet["buttons"]["HOME"])
            break
    cursor, home = wait_for("ui", "buttons", cursor, 20, lambda d: d["route"] == "menu")
    shot("30_home_after")
    stages = next(k for k in home["buttons"] if "·" in k)
    tap(*home["buttons"][stages])
    cursor, levels = wait_for("ui", "buttons", cursor, 20, lambda d: d["route"] == "levels")
    shot("31_stage_select")
    tap(*levels["buttons"]["BACK"])
    cursor, home = wait_for("ui", "buttons", cursor, 20, lambda d: d["route"] == "menu")
    tap(*home["buttons"]["SETTINGS"])
    cursor, _ = wait_for("ui", "buttons", cursor, 20, lambda d: d["tag"] == "modal")
    shot("32_settings")
    adb("shell", "input", "keyevent", "KEYCODE_BACK")
    time.sleep(1.0)
    record.terminate()
    time.sleep(2.0)
    adb("pull", "/sdcard/outtap_qa.mp4", str(OUT / "outtap_qa.mp4"))
    print(f"played {played} levels; results in {OUT}")


if __name__ == "__main__":
    main()
