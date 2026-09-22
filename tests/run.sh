#!/bin/bash
# Compiles the engine on its own and runs the labelled cases. No GUI, no keychain.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
CORE="$HERE/../app/Autofill/Autofill/Core"
OUT="${TMPDIR:-/tmp}/autofill-tests"

# -target matters: on macOS 27 a bare swiftc stamps a minos the binary cannot run on.
swiftc -target arm64-apple-macos13.0 -O \
  "$CORE/Fields.swift" "$CORE/Store.swift" "$CORE/Match.swift" \
  "$CORE/Jev.swift" "$CORE/Importer.swift" "$HERE/main.swift" \
  -o "$OUT"
# Read the key here, with the `security` tool the keychain already trusts. The
# test binary is compiled fresh every run, so it is a stranger to every keychain
# item and would pop a password prompt on each one.
export JEV_API_KEY="${JEV_API_KEY:-$(security find-generic-password -s jev_api -w 2>/dev/null)}"
"$OUT" "$@"
