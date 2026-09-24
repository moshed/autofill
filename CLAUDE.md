# Clerk

A menu-bar Mac app plus a browser extension. Put the cursor in a form field,
press **Alt+Shift+F**, and it fills in the right person's detail — a passport
field next to "Judah" gets Judah's passport number, not Moshe's.

Built 2026-09-21. Bundle `com.DNZ.clerk`. Lives in `/Applications`.

## The two rules that shape everything

1. **Jev names the KIND of field. It never sees a value.**
   When filling a form, Jev is sent labels and headings only — no value from the
   page, no value from the store — and anything matching a stored name or value
   is scrubbed out of the prompt first. `tests/main.swift` asserts this: the leak
   check fails the suite if any stored string reaches a prompt.
2. **Whose field it is gets worked out in code.**
   Names already visible on the page are matched against the store here on the
   Mac. When that is not clear, the page shows a **list of people to pick from**
   rather than guessing something into a passport field.

The single exception is the **Extract with AI** button on the Data tab. That is a
one-off: it takes a block of unstructured text and sorts it into people and
fields. Pressing the button is the consent, so there is no switch to forget.

## Shape

```
extension/    the web extension (manifest v3): Safari and Chrome, same files
app/          GENERATED Xcode project - do not hand-edit, see below
  Clerk/Clerk/
    ClerkApp.swift   menu bar, the model, export/import, demo mode
    SettingsView.swift  two tabs: Data and Setup
    Core/
      Fields.swift    28 field types, the pattern classifier
      Store.swift     the data, in ONE macOS keychain item
      Match.swift     what does this field want / whose value is it
      Jev.swift       the TypeSafe System One call
      Server.swift    loopback HTTP on 127.0.0.1:8771, plus GET /config
      Importer.swift  pasted text -> rows to check
    ShortcutRecorder.swift  click, press a combination
tests/        labelled cases, compiled straight against Core/
tools/        build.sh, fix_project.py, shot.sh
icons/        the app icon source
```

### The Xcode project is generated. Build with `tools/build.sh`.

`safari-web-extension-converter` insists on writing a storyboard AppKit app, so
`tools/build.sh` deletes `app/`, runs the converter, puts the hand-written Swift
back, then `tools/fix_project.py` turns it into the SwiftUI menu-bar app: adds
the sources, turns the sandbox OFF, sets `LSUIElement`, restores the
`clerk://` URL scheme and fixes the bundle id case.

```bash
./tools/build.sh                 # build + install to /Applications
./tools/build.sh --no-install
```

**Never hand-edit `app/Clerk/Clerk.xcodeproj` — the next build throws it
away.** Anything that must survive goes in `tools/fix_project.py`.

The sandbox is off on purpose: a sandboxed app gets its own keychain and could
not read the item the rest of the system writes.

## Several values of the same kind

A person can hold more than one email, phone or address, each with a short label
("work", "personal", "mobile"). Press **+** beside a field in the app to add
another; the top one is the preferred one.

Which one gets used is decided in this order, and the first four are free:

1. **The field's own words** — "AAdvantage number" scores the american value 8.
2. **The site's HOST** — `aa.com`, `delta.com`, `portal.fescony.com` score 5. The
   host, not the whole page: Delta mentioned in a footer is not the same as being
   on delta.com. A stored value can also name the host — `moshed@fescony.com`
   against `portal.fescony.com`. All compared here on the Mac.
3. **The rest of the form** — a Company box filled in scores work 2.
4. **The page title** — 1.

The field beats the site on purpose: an AAdvantage box on delta.com is still an
AAdvantage box. Measured both ways.

`fescony` sits inside the "work" group rather than having one of its own, so
being on the company's own site means work — address, email and phone all switch.
4. **Jev**, asked about the LABELS only: "Does this field want the person's work
   email address?" No value is in that prompt.
5. **Nothing settled it** — every option comes back and the page shows the list.

### Whose it is and which one it is are separate questions

A list appears when EITHER is unclear. "Nobody is named on the page" is not
unclear: a form about one person plus a default person is a setting, not a
guess, so that answers outright. It scores 0.8. A genuine tie — two names on the
page and nothing saying which block the cursor is in — scores 0.4 and puts up
the list.

Getting this wrong made every sign-up form show the whole family.

## How a fill is decided

1. **What does the field want?** The `autocomplete` attribute wins if the site
   set one. Then strong regexes over label / name / id / placeholder / heading,
   then weak ones. Only if all of that ties does Jev get asked.
2. **Whose value is it?** Every filled field and the heading above the cursor is
   scored against every stored person. An exact full name scores 4, a first name
   3, a first name inside a longer string 2, a shared surname 1. Scores are added
   up, same block first, then the whole page.

Address, city, ZIP, country and company are marked shared, so they skip step 2.

### The most specific pattern wins

"Emergency contact phone" matches `emergency…phone` AND a bare `phone`. Two hits
used to mean ambiguous, so it went to the AI, which answered `phone` and filled
the wrong number. `guessType` now compares how much of the text each pattern
actually matched and takes the longest; only a genuine tie is ambiguous.

The same rule keeps "Passport expiry date" off `dob` and "Date of issue" on
`passport_issued`.

### Why the surname has to score less

A form holding "Judah" and "Dancykier" names three people if you match on any
name. Grading the score — and adding across fields — makes Judah win 4 to 1.
Plain set intersection got this wrong.

### Why any field can name somebody

A field the patterns read as a name counts however weakly it matches. Every other
field, and any heading, has to match a first or full name (2+), so a stray
"Dancykier" names nobody. This is why a French form works with no French in the
vocabulary: "Prenom" is not recognised, but its value "Judah" still is.

## Jev notes

- Model `jev-latest`, key in keychain `jev_api`. Yes/no (`noul`) questions only.
- **Jev cannot extract.** It cannot pull a name or a number out of a block of
  text. So the paste importer splits lines into label and value in code, and Jev
  only ever judges one line at a time.
- **Ask about every field type, not a shortlist.** A shortlist built from word
  overlap once offered only "Known Traveler Number" for a field labelled
  "Document identifier", because both contain "traveler" — so that is what it
  answered. All 28 types is one call, ~350 ms, and it then scored
  `passport_number` 0.68 against `national_id` 0.46.
- Jev sees the **whole page**, masked. "Document identifier" means nothing alone
  and is obvious beside a block of passport fields.
- Cutoffs `typeMin` 0.25, `margin` 0.10 in `Match.swift`. A noul is a rank, not a
  probability — re-tune against `tests/`, never by eye.

## The shortcut

Set in the app, on the Setup tab, and stored with everything else. The content
script asks the helper for it (`GET /config`) on every page load and listens for
it itself on a capture-phase `keydown`.

It deliberately does NOT use the extension `commands` API: that puts the setting
in each browser's own preferences, so it would have to be set twice and could not
be read or changed by the app. The recorder refuses a bare letter — without ⌥, ⌃
or ⌘ the key would just get typed into the field.

## Safari grants website access PER SITE, and that is the usual "not working"

The extension can be enabled, notarised, registered and perfectly healthy and
still do nothing, because Safari has only granted it the one site it was last
used on. Check it directly - this is the file, not a guess:

```bash
plutil -p ~/Library/Containers/com.apple.Safari/Data/Library/Safari/WebExtensions/Extensions.plist \
  | grep -A20 "com.DNZ.clerk"
```

`GrantedPermissionOrigins` listing a single site is the whole story: the content
script is never injected anywhere else, so the shortcut does nothing and no chip
appears - there is no code on the page to draw one.

The toolbar button is not a way round it. Safari intercepts the first click on a
site it has no access to and shows its own per-site popover instead of firing
`action.onClicked` (`OpenedPerSitePopover` in the same file).

Only the person can grant it, in Safari's own UI:
**Settings -> Extensions -> Clerk -> Allow on Every Website.**
`host_permissions` now declares `<all_urls>` so that is the offered choice.

## One press fills the whole form

- **Toolbar button** — fills every field it is confident about, in one request to
  `POST /fill-form`. Anything it is unsure of is left alone rather than guessed
  into a form.
- **The shortcut in a field** — fills that field, and again cycles the people.
- **The shortcut with the cursor nowhere** — the whole form.
- **The shortcut twice quickly, or "Someone else…" on the summary** — the list of
  profiles.

`GET`-style modifier detection is not possible: `chrome.action.onClicked` is
given a tab and nothing else, so **shift-clicking the toolbar button cannot be
told apart from clicking it**. That is why the picker hangs off a double press
and off the summary instead.

## The list is two levels, and opening it undoes the fill

Names only at the top. **→** opens that person's own labels (work, delta, home),
**↑↓** move, **⏎** fills, **←** closes, **esc** dismisses. Alan has no labels and
so has no chevron.

Three things had to be true for it to work at all:

1. **Opening the list clears what was filled.** Every box was already full after
   the first click, a full box is never a target, so picking somebody did
   nothing. `ourFills` records what this page set and `clearOurFill()` empties
   exactly those.
2. **A fill already in flight is cancelled.** The first of the two presses
   finished late, refilled the form and replaced the list with its own summary.
   Every fill carries a number; opening the list bumps it and a stale reply is
   dropped.
3. **A chosen profile does not override a field that names its own.** Picking
   "Moshe · american" put the AA number into the box labelled SkyMiles. A field
   whose own words name a different label keeps it.

## One click fills. Two clicks choose.

`chrome.action.onClicked` is handed a tab and nothing else - **no modifier keys**
- so a shift-click and a click are the same event and cannot be told apart. That
is an API limit, not a setting.

What CAN be told apart is a second click soon after the first, so:

- **click** - fills the whole form with the best guess, straight away
- **double-click** (within 700ms) - the list of people, ordered by what the page
  already shows, with "Best guess" first
- **the shortcut twice** - the same list, from the keyboard

The first click fills immediately either way; nothing waits to see whether a
second is coming. The window was proved by widening it to 3s, clicking twice
through System Events, and reading `toolbar button clicked twice` in the log,
then setting it back to 700ms.

`popup.html` is still in the bundle but no longer wired up - a popup meant a
click could not fill on its own, which is the thing worth optimising.

Everything the button does CALLS a function on the isolated world's window
(`__clerkFill`, `__clerkMenu`, `__clerkSnapshot`) rather than sending a
message, for the reason below.

## A message never reaches an injected content script

`tabs.sendMessage` reaches a content script that loaded WITH the page, but not
one injected by `executeScript`: it registers its listener, logs that it did, and
the message simply never arrives. Proven by logging "listener registered" and
still getting nothing back, six retries over 700ms.

Everything the button does therefore CALLS a function on the isolated world's
window - `__clerkFill`, `__clerkMenu`, `__clerkSnapshot` - rather than
asking for a reply.

## The sidebar keeps its width

Not an `HSplitView`: that cannot remember a position, and measuring it to save
the width fed straight back into the width it was given, so the pane grew until
it hit its limit. It is an `HStack` with a divider dragged by hand, saved in
`@AppStorage("sidebarWidth")`.

## Profiles: a person, or a person and one of their labels

`POST /profiles` returns "Moshe", "Moshe · work", "Michelle"… Picking one sets
`person` and `variant` on the payload, and then nothing is guessed: that person
is used, their value with that label comes first, and no field is reported
unsure.

Labels on **linked** values are skipped when building that list - they are the
family's, so every person would offer "home" and "work" and the list would run
to two dozen lines. Each person contributes at most their three commonest own
labels.

## A reinstall orphans every open tab, and the guard made it permanent

Installing the app gives the extension a **new identity**, and Safari reloads it.
Every page that was already open keeps the OLD content script, whose connection
to the extension is dead: the shortcut does nothing and the toolbar button does
nothing. A new tab works, an old one never recovers. That is exactly what "it
works in a new window but not the old one" means.

The toolbar button is supposed to rescue this by injecting the script on demand -
but the re-injection guard `if (window.__clerkLoaded) return` saw the flag the
DEAD copy had set and did nothing at all.

So the script no longer bails. It calls `window.__clerkTeardown()` first,
which the previous copy left behind: it removes that copy's `keydown` and
`focusin` listeners and its `runtime.onMessage` listener, then the new copy takes
over. Clicking the button on an orphaned tab now brings the whole thing back, the
keyboard included.

**Verified by actually clicking the button** (System Events on the real toolbar
item) on a tab that was open before a reinstall: `content script loaded
[takeover]` then `filled 9 of 11`, and the keyboard worked on the same tab
afterwards.

### Test the button, not only the keyboard

Every earlier "the button does not work" was shipped because the keyboard path
was tested and the button path was not. Dispatching a `keydown` from
`do JavaScript` does NOT exercise `action.onClicked`, `executeScript`, or the
re-injection path. Click the real thing:

```bash
osascript -e 'tell application "System Events" to tell process "Safari" to \
  click (first button of toolbar 1 of (first window whose name contains "fill.dev") \
  whose description is "Clerk: fill this field")'
```

## The toolbar button loses the focused field

Clicking Safari's toolbar takes focus out of the page, so by the time the fill
request arrives `document.activeElement` is the body, not the field. The content
script keeps a `lastField` from `focusin` and falls back to it.

`content.js` carries a `BUILD` string that goes into the log line on load.
Safari caches an extension, so without it there is no way to tell whether the
build you just installed is the one running.

## The test bench cannot be a local file

Tried and measured, not assumed: opening `testpage.html` from disk and watching
the log, **the content script never runs on a `file://` page**. Safari does not
offer an extension access to local files the way Chrome does. That is why the
app serves the page.

If the page will not fill, the helper is down, not the page. The popup says so
and offers **Start Clerk**, which opens `clerk://settings` - the only way
an extension can bring a Mac app back.

## The test bench

`http://127.0.0.1:8771/test` - the helper serves `extension/testpage.html`. A
copy sits at `Clerk test page.html`, but **opening that file directly does not
work**: Safari will not run an extension on a `file://` page. That is why the app
serves it.

It carries one of everything: three written date formats, a date picker, four
dropdowns, a radio group, a textarea, `autocomplete` attributes, two traveler
blocks, a heading-only block, work-vs-personal contact, awkward and foreign
labels, two fields sharing one container, and a row of boxes that must never be
touched.

## Things that cost an hour each

- **A radio button carries its `value` whether or not it is chosen.** Reporting
  it as-is made every radio group look already filled, and a filled field is
  never a target - the group was silently never offered. `valueOf()` returns a
  value only for the CHECKED button.
- **Grouping was too fine.** Taking any ancestor with two inputs made every
  `.row` its own block, so one traveler came out as five and the "only fill the
  block that says who it is" rule threw most of them away. A block is a
  `<fieldset>`, or an ancestor holding four or more fields.
- **A whole-form fill must report what it did NOT do.** Every silent skip cost a
  round trip. `FillItem.skipped` carries the reason, and the content script
  logs it, including when a control refuses the value.

## The log names the FIELD, the KIND and the CONFIDENCE

After filling a form the extension writes one line like:

```
filled 9 of 11, 0 left: given-name[First name]->given_name@0.8 email[Email]->email@0.8 …
```

The field, the label that was read off the page, what it was taken for, and how
sure. **Never a value.** That one line has found every classification bug since;
before it existed each one took a round trip through Moshe.

It is how `fname[First name: Last name:]->full_name` was caught in a single
click - see below.

## A label must never cover two fields

`labelFor` used to fall back to the parent's whole text. On a form laid out as

```html
<label>First name:</label><input name="fname">
<label>Last name:</label><input name="lname">
```

in one container, BOTH fields got the label "First name: Last name:". That
matched the first-name pattern AND the last-name pattern, so it counted as
ambiguous, went to the AI, and came back `full_name` - the full name went into
both boxes.

Two rules now:

- `label[for=...]` is looked up **inside the field's own form first**. Duplicate
  ids across two forms on a page otherwise find the other form's label.
- The parent-text fallback only runs when the parent holds **exactly one** field.

## Apple Wallet is a source

`~/Library/Passes/Cards/*.pkpass` - on macOS these are **unpacked folders**, not
zip files, so read `pass.json` from inside each one. 144 passes, 43 distinct
issuers. `organizationName` plus the pass kind sorts them; the numbers live in
`primaryFields`, `secondaryFields`, `auxiliaryFields` and `backFields`.

Taken on 2026-09-22: Hilton Honors, Marriott Bonvoy, World of Hyatt, Priority
Pass, Cathay Pacific, China Southern Sky Pearl, Starlux, the UnitedHealthcare
member and group numbers, the library card and the Progressive policy number. It
also confirmed Nate's SkyMiles number independently.

Left alone: payment cards, boarding passes, event tickets and gift cards.

## Some boxes are never personal details

A site's own search box was given a full name: no pattern matched, so the AI was
asked, and it answered confidently. `Fields.neverFill` now stops that before any
question is asked - search, query, filter, captcha, coupon, promo, comment,
message, quantity, price, one-time code. `guessType` returns confidence `-1` and
`suggest` gives up there.

`Fields.fillAnyway` overrides the block list: a **library** card, a **loyalty**
card and a **membership** card are all "card numbers", and blocking them to keep
credit cards out was too blunt.

Filling a WHOLE form also refuses anything below 0.7 confidence. One field at a
time may still be unsure; the page shows a list in that case.

## The log

`~/Library/Logs/Clerk.log`. The extension posts to `POST /log` on the helper,
which appends a line. **Field labels and outcomes only — never a value.**

Safari gives an extension no console anyone can see without opening the Web
Inspector, so this is the only way to find out what it is doing. `/log` is the
one endpoint with no origin check, on purpose: the point is to hear from an
extension that cannot reach the others.

An empty log after loading a page means the content script never ran at all —
which is Safari, not the app.

## Fields are grouped, and can be added

Every field type carries a `group` ("Name", "Passport", "Address"…) and the
editor lays them out under those headings, in `FieldGroup.order`.

**Add a field…** at the bottom of the editor adds one of Moshe's own. It is
stored in `StoreData.customFields` and `Fields.register` turns it into a real
`FieldType` — matched, filled and offered exactly like a built-in one. Its
pattern is its own name: "Visa number" matches "visa number", "visa_number",
"Visa No.".

## The window

Two tabs in the toolbar, and nothing else in the chrome.

- **Data** — people on the left, one person's fields on the right, grouped under
  a symbol and a title. **Import** in the toolbar opens the paste sheet; the
  paste box is not on screen the rest of the time. Values are always shown in
  plain text; there is no reveal toggle, because hiding your own data from you on
  your own Mac is theatre.
- **Setup** — a plain grouped `Form`, the way a macOS settings window looks.

The menu-bar icon is an `NSStatusItem`, not a `MenuBarExtra`: **one click opens
the window.** There was nothing worth putting in a menu. Right-click still has
Quit.

**Demo people** are a SETTING (Setup tab, "Demo people"), not only a launch
argument, so they can be switched off from inside the app. `-DemoScreen` forces
them on for a screenshot and `-DemoSetup` opens on the Setup tab.

`tools/shot.sh` puts the app back on the real store when it finishes - leaving it
in demo mode means the browser quietly fills forms with made-up details.

## The paste importer

Pass 1 is always local:

- `Label: value`, `Label - value`, `Label = value`, tab, or two-plus spaces.
- No punctuation at all? A few words then something containing a digit reads as
  label + value — "expires 04/02/2031", "KTN 998877", "born 3 March 2014".
- Still nothing? The first one, two or three words are tried as a field label,
  shortest first, which is what turns "issued by United States" into passport
  country = United States.
- A line that is only a known name switches which person the next lines belong to.
- An unlabelled value can still be named by its shape (email, URL, phone, ISO
  date, ZIP), in code.

Pass 2 — only when **Extract with AI** is pressed — asks Jev about whatever is
left, one line at a time, and can also say whose line it is. Rows it could not
settle are pushed to the top, flagged orange and left unticked. Nothing is
written until Save.

## Privacy

- The store is one keychain item, `clerk_store`. Nothing is written to a file
  unless Moshe presses Export.
- The helper sends **no CORS headers on purpose**. A web page can fire a request
  at 127.0.0.1:8771 but the browser will not let it read the answer.
## Safari enforces CORS on an extension's fetch. Chrome does not.

This is the one that cost the most, on 2026-09-22. Every call from the extension
failed with a bare **`TypeError: Load failed`** and nothing else - no status, no
console anyone could see. The helper was running and answering `curl` perfectly.

Chrome lets an extension with a host permission bypass CORS entirely. Safari does
not: it sends a preflight for anything that is not a "simple" request, and it
refuses to hand the response back without `Access-Control-Allow-Origin`.

`Server.swift` now answers `OPTIONS` and echoes the origin back - **but only to an
extension origin** (`safari-web-extension://`, `chrome-extension://`,
`moz-extension://`). A web page's origin is `https://...`, gets no header, and
still cannot read a word of the answer. The security property is kept and Safari
is satisfied.

Proof, both directions:

```bash
curl -i -X OPTIONS http://127.0.0.1:8771/suggest -H "Origin: safari-web-extension://abc" \
  -H "Access-Control-Request-Method: POST"        # -> 204 with the headers
curl -i -X POST http://127.0.0.1:8771/config -H "Origin: https://evil.example.com" -d '{}' \
  | grep -i access-control                        # -> nothing
```

**The tell-tale was that `/log` appeared to work while nothing else did.** It did
not: the request reached the server, the response was blocked, and the `catch`
for that one call did not report anywhere visible.

## Do not re-register the extension on every build

`pluginkit -r` gives the appex a **new UUID**, Safari sees a different extension,
and it drops out of the Extensions list with its on/off state reset. It looks
exactly like the extension breaking. macOS picks up an updated appex by itself.

Only re-register when it is genuinely absent from:

```bash
pluginkit -mA -p com.apple.Safari.web-extension | grep clerk
```

## The household is gone: values are LINKED instead

There is no shared bag beside the people any more. Every value belongs to a
person, and a value can be marked **linked** — the family's. Editing a linked
value writes it to everyone; the chain icon in the editor shows which are.

`StoreData.propagateLinked(from:)` runs on every save. **`from` matters:** it is
the person just edited, and their copy wins. Without it the last person iterated
won, so a change was silently reverted by somebody else's older copy.

A person with no value of their own falls back to the family's linked one, which
is how a child with no address on file still fills in the home address.
`migrateShared()` turns an old `shared` bag into linked values on everybody.

## An unnotarised build makes the extension vanish

Safari silently drops an extension whose app Gatekeeper rejects - it does not
appear in the Extensions list and nothing says why. `tools/build.sh` therefore
notarises on EVERY install; only `--no-install` skips it.

```bash
spctl -a -vv /Applications/Clerk.app     # must say "source=Notarized Developer ID"
```

## Privacy

- **There is no `Origin` allow-list for reading, and there must not be one.** It was tried and it
  broke the extension in a way nothing visible pointed at: a GET carries no
  `Origin` header at all, so `/config` came back 403 and the extension quietly
  used a default; and a browser omits `Origin` on an extension's fetch to a host
  it already has permission for, so `/suggest` could be refused too. The log line
  `no shortcut came back from the app` was the only trace.

  What protects this is not a header: the listener is bound to 127.0.0.1 and the
  helper sends **no CORS headers**, so a web page can fire a request at it but
  the browser will never let that page read the answer. That is the guarantee,
  and it does not depend on anything the browser chooses to send.
- Values are shown in plain text in Settings by design. It is his Mac, behind his
  login, and he has to be able to read what is stored.

## Signing: Developer ID and notarised, and it has to stay that way

Safari refuses an extension whose app is signed with a DEVELOPMENT certificate
unless "Allow Unsigned Extensions" is on in the Develop menu, and that resets
every time Safari quits. So the build signs with **Developer ID Application:
Summit Electronics LLC (VWR39LZW5M)** and notarises.

```bash
./tools/build.sh --notarize      # a few minutes; only needed when shipping a build
```

Three traps, all hit on 2026-09-22:

1. **`CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO` deletes the WHOLE entitlements
   file**, not just `get-task-allow` — sandbox and network access with it. The
   extension then silently cannot reach the helper. `tools/build.sh` re-signs
   both parts afterwards with the entitlements read back and only that one key
   removed.
2. **The extension target had no outgoing network access.** The converter
   sandboxes the appex and does not set `ENABLE_OUTGOING_NETWORK_CONNECTIONS`,
   so its `fetch` to 127.0.0.1 failed and the page said "the helper is not
   running". It was. `tools/fix_project.py` sets it on both targets now.
3. **Changing the signature orphans every keychain item the old build made.**
   See below.

## The keychain item belongs to whoever created it

**Cost half an hour on 2026-09-22.** A one-off `swiftc` loader wrote the store,
and from then on the app froze at start up with no log line. The reason: macOS
puts the creating binary in the item's ACL, so when a *different* binary reads
it, `SecItemCopyMatching` **blocks** behind a "Clerk wants to use your
confidential information" password prompt. The app was not broken; it was
waiting on a dialog.

Rule: **the app must be the process that creates the item.** `-ImportFile <path>`
exists for exactly this — it loads an export at start up, so the keychain item is
born inside the app and nothing ever prompts.

```bash
open -a /Applications/Clerk.app --args -ImportFile /path/to/export.json
open -a /Applications/Clerk.app --args -ExportFile /tmp/out.json
```

`-ExportFile` is the other half: it writes the store to a file at start up, so a
script can read it, change it and import it back WITHOUT a second binary ever
touching the keychain item.

If a prompt does appear, "Always Allow" settles it; deleting the item with
`security delete-generic-password -s clerk_store` and re-importing through the
app is the clean fix.

**The identity is the code signature, so it changes when the signing certificate
does.** Moving from a development certificate to Developer ID orphaned the store,
and the app hung on the dialog before it could listen. Now that it is Developer
ID + notarised the signature is stable and rebuilds keep the same identity.

**Nothing may read a keychain item the app did not create.** Two things used to:

- the `jev_api` item the other tools share — now the key lives in the app's own
  store as `StoreData.jevKey`, seeded through `-ImportFile`;
- an `clerk_token` item, read on EVERY request — the token is gone entirely,
  the `Origin` header does that job.

Both prompted, and both prompted from inside a request, which stalls the reply
and looks exactly like a dead helper.

## Codable needs the decoder written by hand

A property default (`var isDefault = false`) does **not** make the synthesised
decoder treat the key as optional — it demands every key and throws
`keyNotFound` on an export that leaves one out. `Person` and `StoreData` both
have hand-written `init(from:)` using `decodeIfPresent`. Import was broken until
they did.

## Dates

Stored ISO, because that is the one way to write a date that cannot be read two
ways. `Match.formatDate` turns it into what the field is asking for: an
`<input type="date">` gets ISO back, a placeholder saying `DD/MM/YYYY` gets that
order, and anything with no hint gets the American `MM/DD/YYYY`.

## Testing

```bash
./tests/run.sh --nojev     # patterns only, free and offline
./tests/run.sh             # patterns + Jev
```

Compiles `Core/` on its own with `swiftc` — no GUI, no keychain, fake people in
the test file. Covers 13 fill cases, 10 importer rows, and the leak check.
All passing.

`-target arm64-apple-macos13.0` is not optional in `run.sh`: on macOS 27 a bare
`swiftc` stamps a minos the binary will not run on.

### Looking at the UI

```bash
./tools/shot.sh out.png                       # People tab, made-up people
EXTRA_ARGS=-DemoPaste ./tools/shot.sh out.png # Paste tab, already filled in
```

`-DemoScreen` fills the window and the helper with made-up people and never
touches the keychain; `-DemoPaste` also opens the Paste tab with sample text.
`shot.sh` captures the window by its window id — capturing a screen rectangle
grabbed whatever happened to be on top.

## What is loaded (2026-09-22)

Six people, read out of `~/Documents/Family` and Contacts: Moshe, Michelle,
Judah, Daniel, Nate, Alan. Per person — names, date of birth, sex, nationality,
place of birth, passport number, issuing country, issue and expiry dates. Plus
driver's licence for the two adults, and phone and email where Contacts had one.
Household: 45 Meadow Ln, Lawrence NY 11559, United States, FESCO Group.

Two names in the folder are not the names in the passport, and both are aliases
so either one on a page resolves: **Yehuda → Judah** and **Netanel → Nate**.
**Michal → Michelle** likewise; `given_name` is the passport spelling, because
this app is aimed at travel forms.

Deliberately NOT loaded:

- **Social Security numbers.** The cards are all in the folder. An app that types
  into web pages is the last place they belong, so they are left out until Moshe
  says otherwise.
- **Global Entry / Known Traveler numbers.** The PASSID is printed on the BACK of
  the card and the folder only holds the fronts.
- **ETA-IL.** Stored 2026-09-22 for all six, with the date each one lapses. The
  approval emails are TEXT pdfs, so PDFKit reads them without any OCR - but every
  string comes out repeated four times from the layered text, so take the first
  match, not the whole run. Michelle's is a phone screenshot and had to be read
  as an image.

## Safari showed the extension twice

Safari lists one entry per copy of the app that Launch Services has seen, and the
build output sat beside the installed copy. `tools/build.sh` now unregisters the
build copy after installing:

```bash
lsregister -u app/build/Build/Products/Release/Clerk.app
```

`lsregister -dump | grep -i "path:.*Clerk.app"` should print only
`/Applications/Clerk.app`.

## Still to do

- **iPhone.** A Safari Web Extension can ship on iOS and `Core/` is already plain
  Swift, so it would need an iOS app target and a different transport (the phone
  cannot reach this Mac's helper).
- **Preview and other native apps.** Needs a global hotkey reading the focused
  field through the Accessibility API. Preview exposes PDF form fields unevenly,
  so filling the PDF file directly (PyMuPDF) is likely the better answer there.
- More field types: visa number, ESTA, insurance, per-airline loyalty.

## History

The engine was first written in Python (`engine/`, a launchd helper). It is in
`Apps/_Old Versions/Clerk-python-engine/` — all of it was ported to Swift so
there is one implementation, and so the iOS version can reuse it.

## Updating (Sparkle)

`tools/release.sh` does the whole thing: raise the build number, build, notarise,
staple, install, zip, sign, write `appcast.xml`, deploy. `--local` stops before
the deploy.

- Feed: `https://dancykier.com/clerk/appcast.xml`, checked once a day.
- Public key `5oQ5ZKJha6WUKKnFHdfjS6/Kq74AkLgCtz5wVoLyyA0=` is in Info.plist;
  the private key is `tools/sparkle/eddsa_private.pem` (chmod 600, never shipped).
- **Sign with openssl, not Sparkle's `sign_update`.** That tool rejects a valid
  64-byte key ("must be 64 bytes or 96 bytes … Instead it is 64 bytes decoded")
  and `generate_keys` hangs on a keychain dialog.
  `openssl pkeyutl -sign -inkey eddsa_private.pem -rawin -in <zip>`
- **Sparkle's own helpers must be re-signed.** `Updater.app`, `Autoupdate` and
  the two XPC services ship signed by Sparkle's team with no secure timestamp,
  and notarisation refuses all of them. `tools/build.sh` re-signs them innermost
  first with `--preserve-metadata=entitlements`. Skipping this returns Invalid.
- **Sparkle compares `CFBundleVersion`, not `MARKETING_VERSION`.** The build
  number lives in `tools/build_number`, `fix_project.py` writes it into the
  project, and `release.sh` raises it every time. `MARKETING_VERSION` stays 0.0.1
  until Moshe says otherwise.
- Verified end to end on 2026-09-22 against a fake local feed: downloaded,
  checked the signature, replaced the bundle, relaunched. The Safari extension
  stayed registered and the new copy is still notarised.

## The AI key is NOT in the app

The app is published as a public zip, so anything inside it can be read. It
therefore ships **no key at all**.

- `https://dancykier.com/clerk/ai` is a Cloudflare Pages Function
  (`Apps/Web/apps-hub/functions/clerk/ai.js`) holding `JEV_KEY` as a secret.
  Set it with
  `npx wrangler pages secret put JEV_KEY --project-name dancykier`.
- Empty key in Setup -> the app posts to that URL. A key pasted in Setup -> the
  app calls TypeSafe directly and the proxy is not involved.
- The Function forwards only a System One noul call and checks the shape:
  model `jev-latest`, <=120 questions, <=64 KB. It was 40 questions at first and
  refused a real request - the app asks about all 38 field types at once.
- Export leaves the key out. An export gets mailed about; a key in one is a key
  handed away.
- `Match.offline` stops every call out. It used to be expressed by blanking the
  key, which no longer works: empty now means "use the shared key".

### A key in a shipped app CANNOT be hidden

Asked on 2026-09-22: can the key ship inside the app, encrypted? No, and this is
not a matter of trying harder. Whatever unlocks the key has to ship with it, so
anyone holding the app holds both. Even with perfect obfuscation they can attach
a debugger, read it out of memory, or watch the call go out. Obfuscation buys
minutes. That is exactly why the key lives on the proxy.

So the proxy is protected by bounding the damage instead:

1. **Shape check** - only a System One noul call gets through.
2. **Rate limit**, a Cloudflare rule on the zone: 6 requests per 10 seconds per
   IP on `/clerk/ai`, then 429. Real use is about one call per form, so this is
   several times what anybody needs. Verified by firing 14 calls: six 200s then
   eight 429s.
   The FREE plan allows only `period: 10` and `mitigation_timeout: 10` - any
   other value is rejected with "not entitled to use the period 60".
3. **A daily ceiling**, `CLERK_AI_DAILY`, default 3000. Past it the call is
   refused with 429 and "add your own key in Setup"; the app falls back to its
   patterns. `GET https://dancykier.com/clerk/ai` prints today's count.
4. **Kill switch**, `CLERK_AI_OFF=1`. Everyone with their own key carries on.

**A Pages SECRET does not take effect until the next deploy.** Measured, not
assumed: the cap was set to 1, the endpoint kept reporting 3000 and kept
answering, and only a redeploy applied it. So a change is two commands:

```bash
npx wrangler pages secret put CLERK_AI_OFF --project-name dancykier    # "1"
npx wrangler pages deploy . --project-name dancykier --branch main --commit-dirty=true
```

**The counter lives in the edge CACHE, so it is PER DATACENTER.** This account's
API tokens cannot create - or even list - KV, D1 or a Durable Object
("Authentication error" on all three), and Pages Functions have no other durable
store. A cache counter still turns an unbounded bill into a small one: one
attacker normally hits one or two datacenters, and the rate limit in front means
they reach the cap slowly. **Swap `readCount`/`writeCount` for KV the moment a
namespace exists** - nothing else in the file changes.

**What it costs if somebody does find it.** A call is about 300 tokens and Jev is
$42 per billion, so ~$0.000013 each. One machine flat out against the rate limit
is 51,840 calls a day, about **66 cents a day**. Many machines at once is the
only real exposure.

**Still missing: a hard daily ceiling.** It needs a KV counter, and the
Cloudflare token in the keychain (`cloudflare_api_token`, and the `_workers` one)
is NOT entitled to create a KV namespace - both return "Authentication error".
Widening the token, or making `clerk-ai-budget` in the dashboard, is all that is
in the way.

## Test bench

- Local: `http://127.0.0.1:8771/test`
- Public: `https://dancykier.com/clerk/test` (`noindex`, and there is no
  `<form>` element at all, so nothing can be submitted anywhere)
- 55 inputs, 4 dropdowns, 1 textarea, 9 sections, including a fieldset that must
  be left alone.

## Driving the real controls: `tools/ui`

System Events cannot read a SwiftUI window - `entire contents of window 1`
returns an EMPTY list although the window has children. `tools/ui` is a small
Swift accessibility walker that can:

```bash
tools/ui/ui dump                 # every control in the front window
tools/ui/ui click "Check now"    # press a button, tab or toggle by name
```

An icon-only tab reports its SF Symbol name, so the Setup tab is "Gear Shape".
Build it with `swiftc -target arm64-apple-macos13.0 -O main.swift -o ui`.

## The name

Renamed from **Autofill** to **Clerk** on 2026-09-22. "Autofill" is what Safari
and Chrome call their own feature, so it was impossible to search for and easy
to mistake for the browser's.

What moved with it: bundle `com.DNZ.clerk`, URL scheme `clerk://`, keychain item
`clerk_store`, repo `moshed/clerk`, site `dancykier.com/clerk`, feed and AI proxy
under the same path. `dancykier.com/autofill` redirects.

**A bundle-ID change orphans the keychain item** — the ACL holds the old code
requirement, so the app would have hung on a password dialog. The store was
carried across with `-ExportFile` out of the old app and `-ImportFile` into the
new one, which keeps the app the process that creates the item. The old item is
left in place, untouched.

Two things the rename pass missed, both worth remembering:

- **`.gitignore` has no extension**, so a rewrite that walks files by suffix
  skips it. Its allow-list still pointed at `app/Autofill/...` and every Swift
  source silently left the repo.
- **Demo names have two rules.** At least 4 characters, because anything shorter
  is ignored on a page on purpose; and not a substring of an ordinary word,
  because the leak check searches the whole prompt. "Leo" failed the first,
  "Sam" (in "same") and "Ruth" (in "truth") failed the second.

## The landing page

`Apps/Web/apps-hub/clerk/` — deployed with the rest of the site by
`npx wrangler pages deploy . --project-name dancykier`. `tools/release.sh` does
it as part of a release.

- An animated demo fills a fake visa form in the page itself: two traveler
  blocks filled with the right person's details, a block left alone, then the
  two-click people list over a scrim. Pure CSS and JS, pauses off screen,
  and honours `prefers-reduced-motion`.
- The screenshots in `shots/` are real windows captured by `tools/shot.sh` in
  **demo mode**, so no real detail is on them.

## Languages other than English

Measured on 2026-09-22, against the real matcher, not by eye.

- **Naming the field: 24 of 24** across French, Spanish, German, Italian,
  Portuguese, Dutch, Hebrew, Chinese, Japanese, Arabic, Russian, Polish, Korean
  and Turkish. **Hebrew alone: 15 of 15** — including passport issue date,
  passport expiry, place of birth, national ID and sex.
- Only ONE of those 24 matched a pattern (`Numéro de passeport`). **Everything
  else came from Jev.** So with **Work offline** on, a foreign form falls back to
  offering a list rather than filling. Worth knowing before promising anything.
- **Whose field it is works with no foreign vocabulary at all**, because a name
  is a name. A whole Hebrew form with two travelers filled 10 fields, every one
  to the right person, with the four Hebrew traps left alone.

Two real bugs came out of that test:

1. **`neverFill` was English only.** A French "Rechercher sur le site" was NOT
   recognised as a search box; it escaped only because a whole-form fill refuses
   anything under 0.7 confidence, which is luck, not a rule. Search, coupon,
   comment, verification code and credit card are now listed in fourteen
   languages, with tests.
2. **Dates were always written American.** An Israeli form was being given
   `07/12/2018`, which reads there as 7 December. `Match.monthFirst` now decides:
   a `.gov`, `.mil` or `.us` host is month first; any other two-letter country
   code is day first; any non-ASCII letter in the page's labels means the form is
   not American, so day first; otherwise month first as before.

## A stale content script makes the button do NOTHING, silently

The one that broke El Al check-in on 2026-09-22, and the real cause of every
earlier "it works in a new window but not the old one".

Installing the app gives the extension a NEW identity. Every page already open
keeps the OLD content script, and **that copy's globals are still on the
window**. The background asked "does `window.__clerkFill` exist?", got yes,
called it, and returned. The dead copy cannot reach the new background, so:

- nothing was filled, and
- **nothing was logged either**, because a page's log line is relayed through the
  background. The log showed `toolbar button clicked` and then silence.

That silence is the tell. **`toolbar button clicked` with no
`fill-all starting on N fields` after it means a stale copy, not a page problem.**

Fix: `background.js` now injects `content.js` FIRST on every click and calls
afterwards. `content.js` tears the old copy down and takes over, so re-injecting
is safe and costs nothing. Existence of a global is not evidence of life.

## What the real El Al page taught us

Moshe saved `~/Downloads/אל על.html` from elal.com check-in. Serving it and
clicking the real toolbar button found four bugs in one run. **Serve it, never
open it from disk** - Safari will not run an extension on `file://`:

```bash
mkdir -p /tmp/elal && cp "/Users/moshe/Downloads/אל על.html" /tmp/elal/index.html
cd /tmp/elal && python3 -m http.server 8899      # then open http://127.0.0.1:8899/
```

The page is a Knockout template: **no `<form>`, `<label for="">` empty on every
label, every input `name="name"`, ids like `Text1` repeated per passenger.**

1. **The matched text was stripped to `[a-z0-9]`.** Every Hebrew, Arabic,
   Chinese and Cyrillic letter was deleted before any pattern was tried, so no
   foreign pattern could ever match - including the never-fill list, which
   looked tested and was not. `clean()` keeps `\p{L}\p{N}` now, and the
   never-fill test demands the RULE fired rather than accepting "left alone",
   which any unmatched field also produces.
2. **`name="name"` read as a full-name field**, so the passport box was given a
   person's NAME, beside a label that said מספר דרכון. Two fixes: the visible
   label is classified first and the attributes are only a fallback, and
   `worthlessAttr` throws away generic values like `name`, `Text1`, `ctl00`.
3. **The section heading outranked the field's own label.** Under
   "כתובת מלאה ביעד" both City and Country came out as Address line 1, because
   the heading is a longer match than "עיר". `visibleText` and `haystack` no
   longer include the section. It still decides WHOSE field it is, and the AI
   still sees it.
4. **Hebrew is now in the patterns**, not only in the AI: 19 field types carry
   Hebrew words. That took the page from 13 of 29 to **18 of 29**, made the
   answers certain instead of 0.5, and works with Work offline on.

**Still open on that page - dropdowns and radios.** Six `<select>`s report
"nothing matched": the options are Hebrew ("ישראל") and the store holds English
("United States"). The sex radio is the same story: values `1`/`0`, labels
זכר/נקבה, store holds `M`. The fix is `Intl.DisplayNames` in `content.js` -
resolve a stored country to an ISO code, then match an option by its `value` or
by its name in the page's own language.

## Menus and radios in the page's own language

`אזרחות` was classified correctly as Nationality and still came back
"nothing matched": El Al lists countries in Hebrew ("ארצות הברית") with a
country code as the option value, while the store holds "United States".

`content.js` now asks the BROWSER rather than shipping a table.
`Intl.DisplayNames` names every region in any language, so:

- `regionCode()` turns a country written in English, Hebrew or the page's own
  language into an ISO code, and also accepts a bare `US` or a three-letter
  `USA`. Both sides of a comparison are resolved and the codes are compared.
- `sexKey()` does the same small job for a sex radio whose labels are זכר and
  נקבה while the store holds `M`. Matching is on the LABEL, never on a value
  like `1`/`0`, which means nothing on its own.

Both are tried only after an ordinary match fails, and the index is built once
and cached.

**Two limits were silently cutting pages short:**

- `suggestAll(limit:)` was **60**. The test bench alone is 71 fields, so its last
  block was never looked at - it did not appear as filled OR as skipped, which
  is what made it look like the Hebrew section was being ignored. Now 120, the
  same cap the content script uses for its snapshot.
- A person block with no name in it is skipped on purpose, unless it is the only
  one. Adding a NAMED Hebrew block to the bench therefore made the unnamed
  traveler blocks stop filling. That is the rule working, not a bug: without a
  name there is nothing to say whose passport number belongs there.

The bench now carries a right-to-left Hebrew fieldset with a country menu, a
sex radio and a Hebrew search box that must be refused.

## Real pages from the web are part of the local suite

Five public form-filling test pages are checked offline on every run. **No
browser is opened and nothing is submitted** - the pages are fetched once, the
field shapes are read out, and the cases live in `tests/pages/*.json`.

| page | fields | checked |
|---|---|---|
| fill.dev identity | 13 | 11 |
| fill.dev credit card | 8 | 6 |
| roboform all fields | 39 | 28 |
| Chrome's own autofill page | 44 | 28 |
| formy | 8 | 7 |

```bash
tools/webtest/extract.py page.html          # what the extension would see
tools/webtest/make_cases.py                 # refetch and rebuild tests/pages
./tests/run.sh                              # runs them with the rest
```

**The expectations are written by hand from the label printed on the page, never
from what Clerk answers**, so a wrong answer stays wrong. Anything genuinely
ambiguous is left out rather than forced.

First run: **74 of 79**. Two real findings, both fixed:

- **A box called simply `address` was not recognised at all.** Chrome's page has
  `<input name="address">` under a useless label. `^address$` could not match
  because the haystack also holds the label. A weak `\baddress\b` now does it,
  and "email address" and "address line 2" still win on specificity.
- **"Name on card" is refused**, because the input is `cc-name` and `cc[\s_-]?name`
  is on the never-fill list. That is deliberate and it stays: the name itself is
  harmless, but refusing is never the wrong way to be wrong next to a payment
  card. The expectation was corrected, not the rule.

**Chrome's page is the test that matters for the attribute fallback** - every
label on it is a section title, so the `name` attribute is the only signal.

## Do not drive Safari to test

Tried on 2026-09-22 and it went wrong: `window 1` and `front window` in System
Events do not reliably mean the window AppleScript just opened, and a click
meant for a local test page **landed on Moshe's live El Al check-in tab and
filled 25 fields on it**. Nothing was submitted, and a reload cleared it, but it
should never have been possible.

Test the matcher offline against saved pages instead. When the browser genuinely
has to be exercised, ask Moshe to press the button and read
`~/Library/Logs/Clerk.log` afterwards.

## A heading longer than 60 characters was thrown away

`sectionFor` accepted a styled `<div>` as a heading only when its text was 60
characters or fewer. El Al's passenger header is the name FOLLOWED by the
"fill in from a passport photo" link, in one container. Over the limit, the
heading was dropped, the block had no name, and **every passenger block then
falls back to the default person** - which is how somebody else's passport
expiry appears under Michelle's name.

`textOf` already stops at 80 characters, so the extra guard was doing nothing
but harm. Extra words in a heading are safe: `resolvePerson` only counts text
that matches a stored first or full name, so a link's wording names nobody.

**The fill log now names the heading each block was read under:**

```
fill-all starting on 29 fields; blocks: grp1="MICHELLE DANCYKIER …" | grp2="JUDAH …"
```

`(no heading)` there means the block has nothing to say whose it is, and the
default person will be used. That one line answers "why did it fill the wrong
person" without another round trip.

## Dates: stored one way, read another, filled a third

Three different things, and keeping them apart is the point.

- **Stored: ISO**, `2028-03-27`. The one way to write a date that cannot be read
  two ways.
- **Shown and typed in the app: American**, `03/27/2028`, because that is what
  Moshe reads. `Dates.display` / `Dates.store` in `Fields.swift`, tested.
  The box is only written back when what he has typed is a WHOLE date, so
  reformatting never fights him mid-keystroke - the half-typed text lives in
  `FieldRows.typing` until it parses.
- **Filled: whatever the FORM asks for.** `Match.formatDate` with
  `Match.monthFirst`: a `date` input gets ISO, a placeholder showing the order
  wins, then the page decides. Measured:

  | page | what it types |
  |---|---|
  | elal.com, Hebrew labels | `27/03/2028` |
  | elal.com, English page | `03/27/2028` |
  | travel.state.gov | `03/27/2028` |

**`Dates.store` refuses a day-first date on purpose.** `22/06/2031` saves
nothing, because in the app he types American; accepting both would make
`06/07` a coin toss.

## A linked value has an OWNER, and everybody else's copy is locked

`FieldValue.owner` holds the id of the person with the MAIN copy.

- Pressing the chain links the value and makes **that** person the owner.
- On anybody else the box is **greyed out and cannot be typed in**. A disabled
  control never hears a click, so a clear button sits on top of it for one
  reason: to answer one. Pressing it **shakes the box** and writes a line under
  the rows - "This is Nolan's Address line 1. Edit it there, or press the chain
  to make this one your own." Hovering the box, or the chain, says the same.
- The chain on a non-owner **unlinks just that person**: they keep a copy of
  their own and stop following.
- `propagateLinked` now gives the **owner's** copy the last word, whoever was
  edited. Without that an echo could quietly overwrite the real one, which is
  the failure the lock exists to prevent - and there is a test for it.

`owner` is nil on a value written before owners existed. Then nobody owns it and
it behaves the old way: editable anywhere, and the person just edited wins.

`tools/ui` gained `select`, because a sidebar row is an `AXRow` holding static
text rather than a button, so it is chosen by setting `AXSelected` rather than
by pressing it.

## The chain asks WHO to follow

Pressing the chain no longer toggles a flag. It opens a menu:

- **Follow \<name\> — \<their value\>**, one line per person who already has
  something in this field. Choosing one copies their value in, marks this copy
  linked, and records THEM as the owner. From then on this box is greyed out
  here and changes when theirs does.
- **Share mine with everyone** - this person keeps the main copy and everybody
  else follows it. This is the ONLY thing that touches other people, and it is a
  deliberate choice from the menu.
- On a copy you are following: **Stop following \<name\>**. You keep what is
  there and go your own way.
- On a copy you own: **Stop sharing this with everyone**.

## Renaming and removing a field

Right-click any field's rows.

- **Rename** changes only the NAME. The key never moves, so everything already
  stored in it survives, and the form matching is unaffected - there is a test
  that renames Passport number to "Passport no." and checks a form field labelled
  "Passport number" still matches.
- **Remove** clears the field for everybody and takes it off the screen.
  `StoreData.forget(key)` drops the values, removes a custom field outright, and
  puts a built-in on `hiddenFields` - a built-in cannot really be deleted,
  because it is part of the vocabulary that reads a form. Unhiding brings the
  empty field back, not the old value, and the question asked before removing
  says so.

`StoreData.fieldLabels` holds the renames and `Fields.register(_:renamed:)`
applies them to built-in and custom fields alike.


### Following one person must not drag in the rest

Caught by Moshe on 2026-09-22 - "does linking one auto link everyone? that's
nonsensical" - and he was right. `propagateLinked` used to APPEND a linked value
to every person who did not already have one, so Leon choosing to follow Nolan's
email quietly gave it to Freya, who had asked for nothing.

It now only keeps an **existing** follower in step and never creates one.
Handing a value round is a separate, explicit act: `StoreData.share`, reached
only from "Share mine with everyone" on the chain menu. Two tests hold the line -
one that following leaves the others alone, one that sharing on purpose still
reaches everybody.

## A real app while you are looking at it, invisible when you are not

Clerk used to be `LSUIElement` - no Dock icon, no menu bar of its own, no place
in the app switcher. Now the Dock icon follows the WINDOW.

- `INFOPLIST_KEY_LSUIElement` is gone from `tools/fix_project.py`. The app starts
  `.accessory` (no Dock icon), goes `.regular` when a window opens and back to
  `.accessory` when the last one closes - `matchDockToWindow()`.
- The policy is raised BEFORE the window is shown, or the window opens behind
  whatever is in front.
- `NSWindow.willCloseNotification` fires while the window is still there, so the
  check is deferred one run loop.
- **Closing the window does not quit it.**
  `applicationShouldTerminateAfterLastWindowClosed` returns false, because the
  helper the browser talks to lives in this process - quitting it would stop
  forms filling. Measured: closed the window, the process was still there and
  `POST /profiles` still answered 200.
- **Clicking the Dock icon with no window open brings the window back**, through
  `applicationShouldHandleReopen`.
- The status item stays as the quick way in, and `.defaultLaunchBehavior(.suppressed)`
  still means nothing appears when the Mac starts it at login.

Checked after installing:

```bash
lsappinfo list | grep -A2 '"Clerk"'                                  # type="Foreground"
osascript -e 'tell application "System Events" to tell process "Clerk" \
  to return name of every menu bar item of menu bar 1'               # Clerk, Edit, View, Window, Help
osascript -e 'tell application "System Events" to tell process "Clerk" \
  to return count of menu bar items of menu bar 2'                   # 1, the status item
```


Measured by driving it, not by reading it:

| | Dock icon |
|---|---|
| just launched, no window | no |
| window open | yes |
| window closed again | no |

The menu bar icon is there throughout, the process keeps running, and the helper
still answers 200 with no window on screen.

## A menu says "New York", the store says "NY"

Matching a menu option against a stored value when the two are not written the
same way. It lives in **`extension/options.js`**, on purpose: no DOM beyond the
page's language, so `tests/options.test.js` runs it under node and
`tests/run.sh` includes it.

Three tables, tried only after a plain match fails:

- **Countries** - the browser's own, through `Intl.DisplayNames`, in English, the
  page's language and Hebrew. Plus a short three-letter list, because travel
  forms use `USA` and Intl does not know it.
- **States and provinces** - a real table of the 50 states, DC, the territories
  and the Canadian provinces. There is no Intl table for subdivisions. The old
  trick of taking initials ("New York" -> "ny") still sits underneath as a last
  resort, but it gets **District of Columbia** wrong, so it is no longer first.
- **Sex** - so a radio labelled זכר / נקבה takes a stored `M`. Matched on the
  LABEL, never on a value like `1`/`0`, which means nothing by itself.

`node tests/options.test.js` checks both directions, including the ones that must
NOT match: New Jersey does not take NY, Israel does not take United States,
נקבה does not take M.

**"מדינה" is both country and state in Hebrew.** El Al's label is
"מדינה בארה״ב", state in the USA, and the longest match wins, so the fuller
phrase lands on state while a bare "מדינה" or "ארץ" stays on country. Tested.

## The editor's look, and what a label is called

- **Field names sit on the left, in black.** They were right aligned and grey,
  which read as a caption rather than as the name of the thing.
- **`MacField`** replaces `.roundedBorder`, which is square and dated: a 9pt
  continuous corner, a hairline border and the system text background.
- **`Labels.pretty`** shows the short word beside a value the way the airline
  writes it - `elal` becomes "El Al", `skymiles` becomes "SkyMiles", `starlux`
  becomes "STARLUX", `work` becomes "Work". Anything Moshe capitalised himself is
  left exactly as he typed it. It is used in the editor AND in the list of
  profiles the page shows, so "Moshe · american" now reads "Moshe · American".
  His stored labels were rewritten once to match.
- Picking a variant compares labels **without case**, so "American" and
  "american" are one label whichever way an older store spelled it.

## ID is identity, Miscellaneous is everything else

"ID" holds government issued identity only - a national ID or social security
number, and a driver's licence. Insurance cards, a library card, a policy number
and bank details are not identity; they sit under **Miscellaneous**, which is
also where a new field lands by default. The old catch-all called "Other" is
gone, so there is one place for the odds and ends rather than two.

## Putting card or bank details in without them passing through anyone

```bash
./tools/add-payment.sh                 # asks for each one, hidden as you type
./tools/add-payment.sh --person judah
```

Hidden input (`read -rs`), nothing echoed, nothing printed back, nothing in the
shell history. The working file sits in a `chmod 700` folder and is shredded on
exit, including on ctrl-C.

It hands the file to the app with `-ImportFile` rather than writing the keychain
itself, for the usual reason: macOS ties a keychain item to whoever created it,
so **Clerk has to be the process that writes it**. Same path the API key takes.

The other way in is Clerk's own **Import** box. Two buttons:

- **Sort it out here** - the local pass only. Nothing leaves the Mac.
- **Extract with AI** - also sends the lines the patterns could not read.

**A card, bank or social security line is never sent, whichever is pressed.**
`Importer.sensitive` holds back a row whose label mentions card, cvv, routing,
IBAN, account number or social security, and - with no label at all - any value
that passes the **Luhn** check at card length, or the **ABA** check at nine
digits. Tested both ways: those are held, while a name, an email, a passport
number and a street still go.

That guard exists because the importer is the ONE place a value leaves the Mac,
and nobody should have to remember which button not to press.

**Safari's saved cards cannot be read out.** They live in the keychain locked to
Safari, and pulling card numbers out of another app's credential store is not
something to automate. Safari -> Settings -> AutoFill -> Credit Cards -> Edit
shows them after a password prompt, and they can be pasted into Import.

## Apple's notary service can simply be down

2026-09-23: five refusals in a row - `HTTPClientError.deadlineExceeded`, a
timeout, and once "the certificate for this server is invalid". Meanwhile
`curl https://appstoreconnect.apple.com/notary/v2/submissions` answered 401 and
`timestamp.apple.com` answered 302, so the network and the certificates were
fine. Signing failed too, because `--timestamp` needs Apple as well.

**Do not install unnotarised to get around it** - Safari silently drops the
extension. Leave the working build in `/Applications`, commit the code, and try
again later.
