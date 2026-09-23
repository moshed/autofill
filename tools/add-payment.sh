#!/bin/bash
# Put card or bank details into Clerk without them passing through anybody else.
#
#   ./tools/add-payment.sh              # asks for each one, hidden as you type
#   ./tools/add-payment.sh --person judah
#
# Nothing is echoed, nothing is logged, and nothing is printed back. The working
# file lives in a private folder and is shredded at the end, even if you stop it
# half way.
#
# Clerk itself must be the process that writes the keychain item - macOS ties the
# item to whoever created it - so this hands the file to the app with
# -ImportFile rather than writing the keychain directly. Same reason the API key
# goes in the same way.
set -uo pipefail
APP=/Applications/Clerk.app
PERSON=""
[ "${1:-}" = "--person" ] && PERSON="${2:-}"

DIR="$(mktemp -d -t clerk-payment)"
chmod 700 "$DIR"
FILE="$DIR/store.json"
cleanup () {
  [ -f "$FILE" ] && /usr/bin/shred -u "$FILE" 2>/dev/null || rm -f "$FILE"
  rmdir "$DIR" 2>/dev/null
}
trap cleanup EXIT INT TERM

pkill -x Clerk 2>/dev/null; sleep 2
open -a "$APP" --args -ExportFile "$FILE"
for _ in $(seq 1 20); do [ -s "$FILE" ] && break; sleep 0.5; done
[ -s "$FILE" ] || { echo "Clerk did not hand over its data. Is it installed?"; exit 1; }
pkill -x Clerk 2>/dev/null; sleep 1

echo
echo "Type each one and press return. Leave it empty to skip."
echo "Nothing you type is shown, kept in your shell history, or seen by anyone else."
echo

ask () {                       # ask <variable name> <question>
  local v
  printf "  %-26s" "$2"
  IFS= read -rs v
  echo
  printf -v "$1" '%s' "$v"
}

ask CARD_NAME   "Name on card"
ask CARD_NUMBER "Card number"
ask CARD_EXPIRY "Expires (mm/yy)"
ask CARD_CVV    "Security code"
ask CARD_BRAND  "Card type (Visa, Amex…)"
ask CARD_LABEL  "A short label (personal, work…)"
ask IBAN_NUMBER "IBAN"

export CARD_NAME CARD_NUMBER CARD_EXPIRY CARD_CVV CARD_BRAND CARD_LABEL IBAN_NUMBER PERSON
python3 - "$FILE" <<'PY'
import json, os, sys

path = sys.argv[1]
d = json.load(open(path))
want = (os.environ.get("PERSON") or "").strip().lower()

people = d.get("people", [])
target = None
for p in people:
    if want:
        if p["id"].lower() == want or any(a.lower() == want for a in p.get("aliases", [])):
            target = p
    elif p.get("default"):
        target = p
if target is None and people:
    target = people[0]
if target is None:
    print("  no people in Clerk yet"); sys.exit(1)

label = (os.environ.get("CARD_LABEL") or "").strip()
pairs = [("card_name", "CARD_NAME"), ("card_number", "CARD_NUMBER"),
         ("card_expiry", "CARD_EXPIRY"), ("card_cvv", "CARD_CVV"),
         ("card_brand", "CARD_BRAND"), ("iban", "IBAN_NUMBER")]

added = 0
for key, env in pairs:
    value = (os.environ.get(env) or "").strip()
    if not value:
        continue
    rows = target.setdefault("fields", {}).setdefault(key, [])
    rows = [r for r in rows if r.get("label", "") != label]
    rows.append({"label": label, "value": value, "linked": False})
    target["fields"][key] = rows
    added += 1

json.dump(d, open(path, "w"), ensure_ascii=False)
print(f"  saving {added} of them to {target.get('aliases', [target['id']])[0]}")
PY
rc=$?
unset CARD_NAME CARD_NUMBER CARD_EXPIRY CARD_CVV CARD_BRAND IBAN_NUMBER
[ $rc -ne 0 ] && exit $rc

open -a "$APP" --args -ImportFile "$FILE"
sleep 6
pkill -x Clerk 2>/dev/null; sleep 1
open -a "$APP"
echo
echo "Done. Open Clerk and look under Payment to check it."
echo "Card and bank boxes are only filled once you turn that on in Setup."
