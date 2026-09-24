#!/usr/bin/env python3
"""Tab S7 live compare — one mall at a time with ADB reset and cooldown."""
from __future__ import annotations

import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

ADB = r"C:\Users\tingo\AppData\Local\Android\sdk\platform-tools\adb.exe"
DEVICE = "R54RB01SMVB"  # Tab S7 only; emulator may stay connected for other projects
FLUTTER = r"C:\Dev\0.sdk\flutter\bin\flutter.bat"
APP_DIR = Path(r"C:\Users\tingo\Dev\2026-softstudio-project\wishlist-appversion2\flutter_app")
LOG_DIR = Path(r"C:\Users\tingo\Dev\2026-softstudio-project\wishlist-appversion2\audit-logs")

MALLS = [
    "에이블리",
    "SSG",
]

COOLDOWN_SEC = 12
EXTRACT_TIMEOUT_SEC = 900


def log(msg: str, log_path: Path) -> None:
    line = f"[{datetime.now():%H:%M:%S}] {msg}"
    with log_path.open("a", encoding="utf-8") as f:
        f.write(line + "\n")
    try:
        print(line, flush=True)
    except UnicodeEncodeError:
        print(line.encode("cp949", errors="replace").decode("cp949"), flush=True)


def adb(*args: str) -> None:
    subprocess.run([ADB, "-s", DEVICE, *args], capture_output=True)


def prep_device() -> None:
    # kill-server는 Tab을 offline으로 만드는 경우가 있어 생략. force-stop만.
    subprocess.run([ADB, "-s", DEVICE, "wait-for-device"], capture_output=True, timeout=60)
    adb("shell", "settings", "put", "global", "stay_on_while_plugged_in", "7")
    adb("shell", "input", "keyevent", "82")
    adb("shell", "am", "force-stop", "com.softstudio.wishlist")
    time.sleep(2)


def run_mall(mall: str, log_path: Path) -> tuple[int, bool]:
    """Returns (exit_code, got_live_compare)."""
    prep_device()
    out_file = LOG_DIR / f"compare-{mall}-{datetime.now():%H%M%S}.txt"
    cmd = [
        FLUTTER,
        "test",
        "integration_test/live_field_compare_test.dart",
        "-d",
        DEVICE,
        "--no-uninstall",
        f"--dart-define=LIVE_COMPARE_MALLS={mall}",
    ]
    log(f"RUN {mall}", log_path)
    try:
        with out_file.open("w", encoding="utf-8") as out:
            proc = subprocess.run(
                cmd,
                cwd=str(APP_DIR),
                stdout=out,
                stderr=subprocess.STDOUT,
                timeout=EXTRACT_TIMEOUT_SEC,
            )
    except subprocess.TimeoutExpired:
        log(f"TIMEOUT {mall} (>{EXTRACT_TIMEOUT_SEC}s)", log_path)
        return -1, False

    text = out_file.read_text(encoding="utf-8", errors="replace")
    has_probe = "LIVE_COMPARE_JS_PROBE" in text
    has_result = "LIVE_COMPARE_RESULT" in text
    for line in text.splitlines():
        if "LIVE_COMPARE_" in line:
            log(line.strip(), log_path)
    log(f"EXIT {proc.returncode} {mall} probe={has_probe} results={has_result}", log_path)
    ok = proc.returncode == 0 and has_result
    return proc.returncode, ok


def main() -> int:
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    log_path = LOG_DIR / f"compare-batch-{datetime.now():%Y-%m-%d-%H%M}.log"
    log(f"START {len(MALLS)} malls device={DEVICE} cooldown={COOLDOWN_SEC}s", log_path)

    failed = []
    for i, mall in enumerate(MALLS):
        code, ok = run_mall(mall, log_path)
        if not ok:
            failed.append(mall)
        if i < len(MALLS) - 1:
            log(f"COOLDOWN {COOLDOWN_SEC}s before next mall", log_path)
            time.sleep(COOLDOWN_SEC)

    log(f"DONE failed={failed}", log_path)
    return len(failed)


if __name__ == "__main__":
    sys.exit(main())
