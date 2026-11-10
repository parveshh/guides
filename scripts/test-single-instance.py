#!/usr/bin/env python3
"""Native single-instance regression. Refuses an existing command server; owns all test processes."""

import contextlib
import json
import os
import plistlib
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path


def main():
    if len(sys.argv) not in [2, 3]:
        raise SystemExit("Usage: python3 scripts/test-single-instance.py /absolute/path/to/Guides.app [legacy/Guides.app]")
    binary = Path(sys.argv[1]).resolve() / "Contents/MacOS/Guides"
    legacy_binary = None
    if len(sys.argv) == 3:
        legacy_app = Path(sys.argv[2]).resolve()
        assert not plistlib.loads((legacy_app / "Contents/Info.plist").read_bytes()).get("GuidesSingleInstance")
        legacy_binary = legacy_app / "Contents/MacOS/Guides"

    def call(*arguments, executable=binary):
        result = subprocess.run([str(executable), "--cli", *arguments], capture_output=True, text=True, timeout=14)
        assert result.returncode == 0, (arguments, result.stdout, result.stderr)
        return json.loads(result.stdout)

    initial = subprocess.run([str(binary), "--cli", "status"], capture_output=True, text=True, timeout=9)
    assert not json.loads(initial.stdout)["ok"], "An existing command server is running; leave the user's session alone."
    processes = []

    def start(executable):
        process = subprocess.Popen([str(executable)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        processes.append(process)
        return process

    def wait_ready(candidates):
        deadline = time.monotonic() + 10
        while True:
            result = subprocess.run([str(binary), "--cli", "status"], capture_output=True, text=True, timeout=9)
            reply = json.loads(result.stdout)
            if reply["ok"]:
                assert reply["state"]["pid"] in {p.pid for p in candidates}, "Another process owns the command server."
                return reply["state"]
            assert any(p.poll() is None for p in candidates) and time.monotonic() < deadline, reply
            time.sleep(0.1)

    def exits_duplicate(duplicate):
        try:
            duplicate.wait(timeout=3)
        except subprocess.TimeoutExpired:
            raise AssertionError(f"Duplicate GUI remains alive: duplicate={duplicate.pid}") from None
        assert duplicate.returncode == 0

    def stop(process, crash=False):
        if process.poll() is None:
            process.kill() if crash else process.terminate()
            process.wait(timeout=10)

    @contextlib.contextmanager
    def copied_bundle():
        with tempfile.TemporaryDirectory(prefix="Guides Instance QA ", dir="/private/tmp") as folder:
            app = Path(folder) / "Other Copy.app"
            shutil.copytree(binary.parents[2], app, symlinks=True)
            executable = app / "Contents/MacOS/Guides"
            try:
                yield app, executable
            finally:
                for process in reversed(processes):
                    stop(process)
                # A failed launch reply can still leave an NSWorkspace child running. Match only
                # this test's unique copied executable, never the user's installed application.
                listing = subprocess.run(["ps", "-axo", "pid=,comm="], capture_output=True, text=True, check=True)
                for line in listing.stdout.splitlines():
                    parts = line.strip().split(None, 1)
                    if len(parts) == 2 and parts[1] == str(executable):
                        try:
                            os.kill(int(parts[0]), 15)
                        except ProcessLookupError:
                            pass

    try:
        with copied_bundle() as (copied_app, copied_binary):
            primary = start(binary)
            state = wait_ready([primary])
            call("show", "area")
            call("area", "100", "150", "64", "80", "8")
            call("calibrate", "200")
            call("unit", "design-px")
            snapshot = call("pin")["state"]
            for executable in [binary, copied_binary, binary]:
                exits_duplicate(start(executable))
                assert primary.poll() is None and call("status")["state"] == snapshot
                launched = call("launch", executable=executable)
                assert launched["pid"] == primary.pid and launched["alreadyRunning"] is True
                assert call("status")["state"] == snapshot, "Launch changed pinned measurements, calibration or history."
            wrapper = Path(__file__).resolve().parents[1] / "skills/guides/scripts/guides"
            result = subprocess.run([str(wrapper), "launch"], env=dict(os.environ, GUIDES_APP=str(copied_app)),
                                    capture_output=True, text=True, timeout=14, check=True)
            assert json.loads(result.stdout)["pid"] == primary.pid
            assert call("status")["state"] == snapshot
            stop(primary)

            for _ in range(3):
                wave = [start(binary if index % 2 else copied_binary) for index in range(6)]
                state = wait_ready(wave)
                winner = next(p for p in wave if p.pid == state["pid"])
                for contender in wave:
                    if contender is not winner:
                        exits_duplicate(contender)
                assert sum(p.poll() is None for p in wave) == 1
                assert call("status")["state"]["pid"] == winner.pid
                stop(winner, crash=True)

            recovered = start(copied_binary)
            assert wait_ready([recovered])["pid"] == recovered.pid
            stop(recovered)

            if legacy_binary:
                legacy = start(legacy_binary)
                wait_ready([legacy])
                call("show", "area")
                call("area", "100", "150", "64", "80")
                legacy_snapshot = call("pin")["state"]
                exits_duplicate(start(binary))
                assert call("launch")["pid"] == legacy.pid
                assert call("status")["state"] == legacy_snapshot
                stop(legacy)

            cold = call("launch", executable=copied_binary)
            # NSWorkspace launched this process; it belongs to this test, although it is not a direct child.
            assert cold["alreadyRunning"] is False
            assert Path(cold["appPath"]).resolve() == copied_app.resolve(), "Do not terminate a foreign app."
            cold_pid = cold["pid"]
            try:
                assert call("status")["state"]["pid"] == cold_pid
                assert call("launch")["pid"] == cold_pid
            finally:
                os.kill(cold_pid, 15)
                deadline = time.monotonic() + 10
                while time.monotonic() < deadline:
                    result = subprocess.run([str(binary), "--cli", "status"], capture_output=True, text=True, timeout=9)
                    if not json.loads(result.stdout)["ok"]:
                        break
                    time.sleep(0.1)
                else:
                    raise AssertionError("Test-owned cold-launch process did not exit.")
            print("PASS: direct/copied launches, wrapper/native launch reuse, exact session preservation, three six-process startup races, crash recovery and cold launch keep one GUI instance." +
                  (" Legacy running-build reuse passed." if legacy_binary else ""))
    finally:
        for process in reversed(processes):
            if process.poll() is None:
                stop(process)


if __name__ == "__main__":
    main()
