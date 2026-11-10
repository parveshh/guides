#!/usr/bin/env python3
"""Run real client/server acceptance checks in a fresh Guides process, without privacy grants.

Usage: python3 scripts/test-cli.py /absolute/path/to/Guides.app
An existing command server is refused so no user's measurement session is modified.
"""

import json
import signal
import subprocess
import sys
import time
from pathlib import Path


def main():
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    app = Path(sys.argv[1]).resolve()
    binary = app / "Contents/MacOS/Guides"

    def call(*args, ok=True, code=None):
        result = subprocess.run([str(binary), "--cli", *args], capture_output=True, text=True, timeout=9)
        reply = json.loads(result.stdout)
        assert reply["ok"] is ok, (args, result.returncode, reply)
        assert result.returncode == (code if code is not None else (0 if ok else 1)), (args, result)
        return reply

    help_result = subprocess.run([str(binary), "--cli", "--help"], capture_output=True, text=True, timeout=9)
    assert help_result.returncode == 0 and "Usage: guides" in help_result.stdout
    call("guide", "vertical", "nan", ok=False, code=2)
    absent = call("status", ok=False)
    assert "Open the CLI-enabled build" in absent["error"], absent
    server = subprocess.Popen([str(binary)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        deadline = time.monotonic() + 10
        while True:
            result = subprocess.run([str(binary), "--cli", "status"], capture_output=True, text=True, timeout=9)
            state = json.loads(result.stdout)
            if state["ok"]:
                break
            assert time.monotonic() < deadline and server.poll() is None, state
            time.sleep(0.1)
        assert state["state"]["pid"] == server.pid, "A different process owns the command server."
        assert state["state"]["mode"] == "hidden" and state["state"]["guides"] == []
        assert state["state"]["calibrated"] is False
        display = call("displays")["displays"][0]
        display_id = str(display["id"])
        assert display["width"] >= 400 and display["height"] >= 400
        call("show", "guides", "4294967295", ok=False)
        call("show", "guides", display_id)
        call("unit", "design-px", ok=False)
        gap = call("gap", "vertical", "300.125", "364.125")["state"]
        assert gap["value"] == "64 screen pt" and len(gap["guides"]) == 2
        call("read", "css", ok=False)
        call("guide", "vertical", str(display["width"] + 1), ok=False)
        assert len(call("status")["state"]["guides"]) == 2
        call("calibrate", "200")
        call("unit", "design-px")
        assert call("read", "css")["value"] == "gap: 32px;"
        assert call("read", "tailwind")["value"] == "gap-[32px]"
        ids = [guide["id"] for guide in gap["guides"]]
        call("select", *ids)
        assert call("undo")["state"]["guides"] == []
        assert len(call("redo")["state"]["guides"]) == 2
        area = call("area", "100", "150", "64", "80", "8")["state"]["area"]
        assert area == {"x": 100, "y": 150, "width": 64, "height": 80, "radius": 8}
        call("area", "100", "150", "-64", "80", ok=False)
        assert call("status")["state"]["area"] == area
        call("select", "area", "radius")
        assert call("read", "css")["value"] == "border-radius: 4px;"
        assert call("pin")["state"]["mode"] == "pinned"
        call("clear", ok=False)
        assert call("read")["value"] == "4px"
        assert call("hide")["state"]["mode"] == "hidden"
        call("show", "annotate", display_id)
        call("clear", ok=False)
        call("read", ok=False)
        call("show", "area", display_id)
        call("clear")
        assert call("undo")["state"]["area"] == area
        assert call("redo")["state"]["area"] is None
        call("hide")
        server.send_signal(signal.SIGSTOP)
        try:
            timeout = call("status", ok=False)
            assert "execution may be uncertain" in timeout["error"]
        finally:
            server.send_signal(signal.SIGCONT)
        assert call("status")["state"]["guides"] == []
        print("PASS: CLI help/errors, fresh launch, display selection, exact gap, calibration gating, formats, selection, undo/redo, Area/radius, invalid geometry, pin/hide, tool gating and timeout recovery.")
    finally:
        server.terminate()
        server.wait(timeout=10)


if __name__ == "__main__":
    main()
