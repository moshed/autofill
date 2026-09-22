#!/bin/bash
# Reinstalls the built app, opens Settings and captures that WINDOW.
#
# Capturing a screen rectangle grabbed whatever happened to be on top, so this
# asks the window server for Autofill's window id and captures only that.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-/tmp/autofill-settings.png}"

pkill -x Autofill 2>/dev/null || true
sleep 1
rm -rf /Applications/Autofill.app
cp -R "$HERE/app/build/Build/Products/Release/Autofill.app" /Applications/
# -DemoScreen fills the window with made-up people and never touches the store.
open -a /Applications/Autofill.app --args -DemoScreen ${EXTRA_ARGS:-}
sleep 3
open "autofill://settings"
sleep 2
trap 'pkill -x Autofill 2>/dev/null; sleep 1; open -a /Applications/Autofill.app' EXIT

python3 - "$OUT" <<'PY'
import subprocess
import sys
import time
import Quartz

out = sys.argv[1]
wid = None
for _ in range(20):
    for w in Quartz.CGWindowListCopyWindowInfo(
            Quartz.kCGWindowListOptionOnScreenOnly, Quartz.kCGNullWindowID):
        if w.get("kCGWindowOwnerName") == "Autofill" and w.get("kCGWindowName") == "Autofill":
            wid = w["kCGWindowNumber"]
            break
    if wid:
        break
    time.sleep(0.5)

if not wid:
    sys.exit("no Autofill window on screen")
subprocess.run(["screencapture", "-x", "-o", "-l", str(wid), out], check=True)
print(out)
PY
