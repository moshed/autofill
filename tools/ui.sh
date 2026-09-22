#!/bin/bash
# Drive the app's real controls, because a code path passing is not proof.
#   ./tools/ui.sh dump              # print every control in the window
#   ./tools/ui.sh click "Check now" # press the first button with that name
set -euo pipefail
ACT="${1:-dump}"; WANT="${2:-}"
open "autofill://settings" >/dev/null 2>&1 || true
sleep 1
osascript - "$ACT" "$WANT" <<'AS'
on run argv
  set act to item 1 of argv
  set want to item 2 of argv
  tell application "System Events" to tell process "Autofill"
    set frontmost to true
    delay 0.4
    set out to ""
    repeat with e in (entire contents of window 1)
      try
        set r to role of e
        set n to ""
        try
          set n to (value of attribute "AXTitle" of e) as text
        end try
        if n is "" then
          try
            set n to (value of attribute "AXDescription" of e) as text
          end try
        end if
        if n is "" then
          try
            set n to (value of attribute "AXValue" of e) as text
          end try
        end if
        if act is "dump" then
          if n is not "" then set out to out & r & "  |  " & n & linefeed
        else
          if r is "AXButton" and n contains want then
            click e
            return "clicked: " & n
          end if
        end if
      end try
    end repeat
    if act is "dump" then return out
    return "not found: " & want
  end tell
end run
AS
