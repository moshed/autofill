#!/bin/bash
# Reinstalls the built app, opens Settings and captures that WINDOW.
#
# Capturing a screen rectangle grabbed whatever happened to be on top, so this
# asks the window server for Clerk's window id and captures only that.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-/tmp/clerk-settings.png}"

pkill -x Clerk 2>/dev/null || true
sleep 1
# ditto OVER the top, never delete-and-copy. A fresh bundle gives Safari a new
# identity and the extension drops out of its Extensions list.
ditto "$HERE/app/build/Build/Products/Release/Clerk.app" /Applications/Clerk.app
# -DemoScreen fills the window with made-up people and never touches the store.
open -a /Applications/Clerk.app --args -DemoScreen ${EXTRA_ARGS:-}
sleep 3
open "clerk://settings"
sleep 2
trap 'pkill -x Clerk 2>/dev/null; sleep 1; open -a /Applications/Clerk.app' EXIT

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
        if w.get("kCGWindowOwnerName") == "Clerk" and w.get("kCGWindowName") == "Clerk":
            wid = w["kCGWindowNumber"]
            break
    if wid:
        break
    time.sleep(0.5)

if not wid:
    sys.exit("no Clerk window on screen")
subprocess.run(["screencapture", "-x", "-o", "-l", str(wid), out], check=True)
print(out)
PY
