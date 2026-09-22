# Autofill

A Mac app and Safari extension that fills any web form from details you keep on
your own Mac — names, emails, phone numbers, addresses, passports, frequent
flyer numbers, driving licences — for you and for everybody in your family.

It was built because filling a visa form for five people, one passport number
at a time, is miserable.

![the app](icons/icon-256.png)

## What it does

- **One click fills the whole form.** Every field, not just the one the cursor
  is in.
- **It works out whose field it is.** If a block of the form already says
  "Leon", the passport number it fills there is Leon's. It reads the labels
  around a field, the other fields already filled, the section heading and the
  address of the page.
- **Double click clears that and offers a list.** People first; press the right
  arrow on a name to choose between their work and home details, or the airline
  a frequent flyer number belongs to.
- **One value can belong to everybody.** A home address is stored on each
  person and marked linked, so changing it on one changes it on all of them.
- **It leaves things alone.** Search boxes, captchas, coupon codes, one-time
  codes, card numbers and comment boxes are never filled — but a library card
  or a loyalty number still is.

## What is sent where

**Your details never leave your Mac.** This is the rule the whole design is
built around.

- The extension asks the app, over `127.0.0.1` only, what a field wants.
- Working out *what kind* of field it is can need a language model. It is shown
  the **labels printed on the page** and nothing else: no value from the page,
  no value from your store, no names. Anything matching something you have
  stored is removed from the text first.
- Working out **whose** field it is happens entirely on your Mac. When that is
  not clear the page shows you a list instead of guessing.
- The one exception is the importer. Text you paste into Setup and press
  "Extract with AI" on is sent, because sorting it into people and fields is the
  whole point of that button. Nothing else ever is.
- There is a **Work offline** switch that stops every call out. The patterns
  still name most fields; anything they cannot name is offered to you instead.
- A test in `tests/` fails the build if any stored value or any name reaches a
  prompt.

Everything is stored in one macOS keychain item. Nothing is written to a file
unless you press Export, and an Export leaves the AI key out.

## The AI key

The app ships **no API key**. With the key box empty it posts to a small
endpoint that holds a shared key; paste your own
[TypeSafe](https://typesafe.ai) key in Setup and it talks to TypeSafe directly
and skips the middleman.

## Building it

```bash
tools/build.sh              # build, sign, notarise, install to /Applications
tools/build.sh --no-install # build only
tests/run.sh                # the matcher's tests, no GUI needed
tools/release.sh            # raise the build number, publish, update the feed
```

The Xcode project is generated on every build from `extension/` by
`safari-web-extension-converter`, then reshaped by `tools/fix_project.py`. The
files that matter are `extension/` and
`app/Autofill/Autofill/{Core,AutofillApp.swift,SettingsView.swift}`.

`CLAUDE.md` holds the long version: the architecture, and every trap that cost
an evening.

## Try the field bench

<https://dancykier.com/autofill/test> — 55 inputs, 4 dropdowns, radios, date
pickers, awkward labels and a section that must be left alone. There is no
`<form>` element on it, so nothing can be submitted anywhere.

## Requires

macOS 13 or later, and Safari.
