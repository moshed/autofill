/* Reads the form around the focused field, and fills that field.
 *
 * The page is never asked to do anything clever. The one job that matters is
 * finding a label for every input, because the label is what the matcher reads.
 */

/* Reinstalling the app gives the extension a NEW identity, and Safari reloads
 * it. Pages that were already open keep the OLD script, whose connection to the
 * extension is dead - the shortcut and the toolbar button both do nothing, and
 * a tab that was open before the update stays broken until it is reloaded.
 *
 * So this does NOT bail when it finds itself already loaded. It tears the old
 * copy down and takes over. `__clerkTeardown` is what makes that possible.
 */
try { window.__clerkTeardown?.(); } catch (e) { /* the old context is dead */ }
try {
  window.__clerkLoaded = true;

const IGNORE_TYPES = new Set([
  "password", "hidden", "submit", "button", "reset", "image", "file",
  "checkbox", "range", "color",
]);

function visible(el) {
  const r = el.getBoundingClientRect();
  return r.width > 0 && r.height > 0;
}

function textOf(el) {
  return (el?.textContent || "").replace(/\s+/g, " ").trim().slice(0, 80);
}

/* A label, in the order of how much the page meant it.
 *
 * The rule that matters: never return text belonging to more than one field.
 * Scooping up a parent that held two inputs gave both of them the label
 * "First name: Last name:", which matched BOTH patterns, and the ambiguity sent
 * a plain first-name box to the AI, which called it a full name.
 */
function labelFor(el) {
  /* A radio button's own label says "Male", which tells you nothing about what
   * the QUESTION is. The label of the group does: take the heading above the
   * box that holds every button of that name. */
  if ((el.type || "").toLowerCase() === "radio" && el.name) {
    const group = [...document.querySelectorAll(
      `input[type=radio][name="${CSS.escape(el.name)}"]`)];
    let box = el.parentElement;
    while (box && !group.every((r) => box.contains(r))) box = box.parentElement;
    if (box) {
      const fs = box.closest("fieldset");
      const lg = fs?.querySelector("legend");
      if (lg) return textOf(lg);
      let n = box.previousElementSibling;
      for (let i = 0; i < 3 && n; i++, n = n.previousElementSibling) {
        if (n.querySelector?.("input,select,textarea")) break;
        const t = textOf(n);
        if (t && t.length < 60) return t;
      }
      const owner = box.closest("label");
      if (owner) {
        const clone = owner.cloneNode(true);
        clone.querySelectorAll("input,select,textarea,label").forEach((x) => x.remove());
        const t = textOf(clone);
        if (t) return t;
      }
    }
  }
  if (el.id) {
    const sel = `label[for="${CSS.escape(el.id)}"]`;
    /* Within this form first: ids are supposed to be unique and often are not,
     * and a document-wide lookup then finds another form's label. */
    const l = el.closest("form")?.querySelector(sel) || document.querySelector(sel);
    if (l) return textOf(l);
  }
  const wrap = el.closest("label");
  if (wrap) {
    const clone = wrap.cloneNode(true);
    clone.querySelectorAll("input,select,textarea").forEach((n) => n.remove());
    const t = textOf(clone);
    if (t) return t;
  }
  const by = el.getAttribute("aria-labelledby");
  if (by) {
    const parts = by.split(/\s+/).map((id) => textOf(document.getElementById(id)));
    const t = parts.filter(Boolean).join(" ");
    if (t) return t;
  }
  const aria = el.getAttribute("aria-label");
  if (aria) return aria.trim().slice(0, 80);

  /* Nothing declared. The nearest preceding element, and only if it holds no
   * field of its own. */
  let n = el.previousElementSibling;
  for (let i = 0; i < 3 && n; i++, n = n.previousElementSibling) {
    if (n.querySelector?.("input,select,textarea")) break;
    const t = textOf(n);
    if (t && t.length < 60) return t;
  }
  /* The parent, but ONLY when this is the one field in it. */
  const p = el.parentElement;
  if (p && p.querySelectorAll("input,select,textarea").length === 1) {
    const clone = p.cloneNode(true);
    clone.querySelectorAll("input,select,textarea").forEach((x) => x.remove());
    const t = textOf(clone);
    if (t && t.length < 60) return t;
  }
  return "";
}

/* The heading this field sits under - "Traveler 2", "Billing address". */
function sectionFor(el) {
  const fs = el.closest("fieldset");
  if (fs) {
    const lg = fs.querySelector("legend");
    if (lg) return textOf(lg);
  }
  /* Real headings first. Plenty of sites use a styled <div> instead, so a short
   * text-only block just above the field counts as a heading too - that is how
   * "Traveler 3 - Freya Carter" gets found. */
  let node = el;
  for (let depth = 0; depth < 6 && node; depth++) {
    let sib = node.previousElementSibling;
    while (sib) {
      if (/^H[1-6]$/.test(sib.tagName) || sib.getAttribute?.("role") === "heading") {
        const t = textOf(sib);
        if (t) return t;
      }
      const h = sib.querySelector?.("h1,h2,h3,h4,h5,h6,[role=heading]");
      if (h) {
        const t = textOf(h);
        if (t) return t;
      }
      /* A <label> above the field is the field's own label, not a heading. */
      if (sib.tagName !== "LABEL" && !sib.querySelector?.("input,select,textarea")) {
        /* textOf already stops at 80 characters. The old cut-off of 60 threw
         * away El Al's passenger header, which reads
         * "MICHELLE DANCYKIER" followed by the "fill in from a passport photo"
         * link - so the block had no name, and every passenger got the default
         * person's passport. Extra words are harmless: only text that actually
         * matches a stored name counts for anything. */
        const t = textOf(sib);
        if (t) return t;
      }
      sib = sib.previousElementSibling;
    }
    node = node.parentElement;
  }
  return "";
}

/* Fields that belong together - one traveler, one address.
 *
 * A <fieldset> is the honest answer. Failing that, an ancestor big enough to be
 * a SECTION. The old rule took any ancestor with two inputs, which made every
 * `.row` of a form its own block: one traveler came out as five, and a radio
 * group sitting in its own div was treated as a separate person and skipped.
 */
function groupFor(el, groups) {
  let box = el.closest("fieldset");
  if (!box) {
    let node = el.parentElement;
    while (node && node !== document.body) {
      const n = node.querySelectorAll("input,select,textarea").length;
      if (n >= 4 && n <= 30) { box = node; break; }
      node = node.parentElement;
    }
  }
  if (!box) return "";
  let id = groups.get(box);
  if (!id) { id = "grp" + (groups.size + 1); groups.set(box, id); }
  return id;
}

/* A radio button carries its `value` whether or not it is CHOSEN, so reporting
 * it as-is made every radio group look already filled in - and a field that
 * looks filled is never a target. Only a checked button has a value. */
function valueOf(el) {
  if ((el.type || "").toLowerCase() === "radio") {
    const chosen = [...document.querySelectorAll(
      `input[type=radio][name="${CSS.escape(el.name)}"]`)].find((r) => r.checked);
    return chosen ? chosen.value : "";
  }
  return el.value || "";
}

function snapshot(current) {
  const groups = new Map();
  const all = [...document.querySelectorAll("input,select,textarea")].filter(
    (el) => !IGNORE_TYPES.has((el.type || "").toLowerCase()) && (visible(el) || el === current)
  );
  const fields = all.slice(0, 120).map((el, i) => ({
    i,
    label: labelFor(el),
    name: el.name || "",
    id: el.id || "",
    placeholder: el.placeholder || "",
    autocomplete: el.getAttribute("autocomplete") || "",
    aria_label: el.getAttribute("aria-label") || "",
    input_type: (el.type || "").toLowerCase(),
    section: sectionFor(el),
    group: groupFor(el, groups),
    value: el === current ? "" : valueOf(el),
    current: el === current,
  }));
  return { url: location.href, title: document.title, fields };
}

/* --- putting the value in ------------------------------------------------- */

/* Matching a written value to what a control will actually accept: a dropdown
 * offering "New York" for "NY", a radio group, a date picker that only takes
 * ISO. */
function setValue(el, value) {
  const kind = (el.type || "").toLowerCase();

  if (el.tagName === "SELECT") {
    let best = null, bestScore = 0;
    for (const o of el.options) {
      const sc = optionMatches(o.text, o.value, value);
      if (sc > bestScore) { best = o; bestScore = sc; }
    }
    if (!best || bestScore < 2) return false;
    el.value = best.value;
  } else if (kind === "radio") {
    const group = [...document.querySelectorAll(
      `input[type=radio][name="${CSS.escape(el.name)}"]`)];
    let best = null, bestScore = 0;
    for (const r of group) {
      const sc = optionMatches(labelFor(r) || r.value, r.value, value);
      if (sc > bestScore) { best = r; bestScore = sc; }
    }
    if (!best || bestScore < 2) return false;
    best.checked = true;
    for (const type of ["input", "change"]) {
      best.dispatchEvent(new Event(type, { bubbles: true }));
    }
    return true;
  } else {
    let v = value;
    /* A month picker wants YYYY-MM, a date picker YYYY-MM-DD. */
    if (kind === "month") {
      const m = v.match(/(\d{4})-(\d{2})/);
      if (m) v = `${m[1]}-${m[2]}`;
    }
    /* React and friends watch the native setter, not the property. */
    const proto = el instanceof HTMLTextAreaElement
      ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
    const setter = Object.getOwnPropertyDescriptor(proto, "value")?.set;
    if (setter) setter.call(el, v); else el.value = v;
    if (kind === "date" || kind === "month") {
      if (!el.value) return false;                    // it refused the format
    }
  }
  for (const type of ["input", "change"]) {
    el.dispatchEvent(new Event(type, { bubbles: true }));
  }
  return true;
}

/* --- what it says back to you ---------------------------------------------- */

let overlay = null;
function clearOverlay() {
  overlay?.remove();
  overlay = null;
}

function box(tone) {
  clearOverlay();
  const d = document.createElement("div");
  d.style.cssText = `position:fixed;z-index:2147483647;right:16px;bottom:16px;
    padding:10px 12px;border-radius:10px;font:13px -apple-system,system-ui,sans-serif;
    color:#fff;background:${tone === "bad" ? "#b3261e" : "#1f6feb"};
    box-shadow:0 6px 20px rgba(0,0,0,.3);max-width:340px`;
  document.documentElement.appendChild(d);
  overlay = d;
  return d;
}

function chip(text, tone) {
  const d = box(tone);
  d.textContent = text;
  d.style.pointerEvents = "none";
  setTimeout(() => { if (overlay === d) clearOverlay(); }, 2600);
}

/* When the app cannot tell whose field it is, it says so and sends everyone who
 * has a value. Nothing is typed into the form until you pick - guessing a
 * passport number into a booking is worse than one keystroke. */
function askWho(el, res) {
  const d = box("good");
  const title = document.createElement("div");
  title.textContent = `Which ${res.type_label}?`;
  title.style.cssText = "font-weight:600;margin-bottom:6px";
  d.appendChild(title);

  const cleanup = () => {
    document.removeEventListener("keydown", onKey, true);
    clearOverlay();
  };

  res.alternatives.forEach((alt, i) => {
    const row = document.createElement("div");
    row.textContent = `${i + 1}.  ${alt.name}`;
    row.style.cssText = `padding:5px 8px;border-radius:6px;cursor:pointer;
      display:flex;justify-content:space-between;gap:16px`;
    row.onmouseenter = () => { row.style.background = "rgba(255,255,255,.18)"; };
    row.onmouseleave = () => { row.style.background = "transparent"; };
    row.onclick = () => { cleanup(); setValue(el, alt.value); chip(`${alt.name}`, "good"); };
    d.appendChild(row);
  });

  const hint = document.createElement("div");
  hint.textContent = "press a number, Return for the first, or Esc";
  hint.style.cssText = "margin-top:6px;opacity:.75;font-size:11px";
  d.appendChild(hint);

  function onKey(e) {
    if (e.key === "Escape") { e.preventDefault(); cleanup(); return; }
    /* Return takes the first, which is the one it thinks is likeliest. */
    const n = e.key === "Enter" ? 1 : parseInt(e.key, 10);
    if (n >= 1 && n <= res.alternatives.length) {
      e.preventDefault();
      e.stopPropagation();
      const alt = res.alternatives[n - 1];
      cleanup();
      setValue(el, alt.value);
      chip(`${alt.name}`, "good");
    }
  }
  document.addEventListener("keydown", onKey, true);
}

/* Everything this page filled, so choosing a different person can replace it.
 * Without this the second choice did nothing: every box was already full, and a
 * full box is never a target. */
let ourFills = [];
/* Every fill carries a number. Opening the list bumps it, so a fill that was
 * already in flight lands after the list is up and is thrown away - otherwise
 * the first of the two presses finishes late, refills the form and replaces the
 * list with its own summary. */
let fillGen = 0;

function clearOurFill() {
  note(`clearing ${ourFills.length} fields this page filled`);
  for (const { el } of ourFills) {
    if (!el.isConnected) continue;
    if ((el.type || "").toLowerCase() === "radio") { el.checked = false; }
    else if (el.tagName === "SELECT") { el.selectedIndex = 0; }
    else {
      const proto = el instanceof HTMLTextAreaElement
        ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
      const setter = Object.getOwnPropertyDescriptor(proto, "value")?.set;
      if (setter) setter.call(el, ""); else el.value = "";
    }
    for (const t of ["input", "change"]) el.dispatchEvent(new Event(t, { bubbles: true }));
  }
  ourFills = [];
}

/* --- choosing who to fill as ----------------------------------------------- */

/* A summary that stays put and offers a different person, rather than a chip
 * that vanishes before it can be read. */
function filledSummary(done, held, as) {
  const d = box("good");
  const line = document.createElement("div");
  line.textContent = as ? `Filled ${done} as ${as.name}`
    : held ? `Filled ${done} · ${held} need you`
    : `Filled ${done}`;
  line.style.fontWeight = "600";
  d.appendChild(line);

  const b = document.createElement("div");
  b.textContent = "Someone else…";
  b.style.cssText = `margin-top:7px;padding:5px 8px;border-radius:6px;cursor:pointer;
    background:rgba(255,255,255,.18);text-align:center`;
  b.onclick = chooseProfile;
  d.appendChild(b);

  const hint = document.createElement("div");
  hint.textContent = "or press the shortcut twice";
  hint.style.cssText = "margin-top:5px;opacity:.7;font-size:11px;text-align:center";
  d.appendChild(hint);

  clearTimeout(filledSummary.timer);
  filledSummary.timer = setTimeout(() => { if (overlay === d) clearOverlay(); }, 9000);
}

/* The list of people. Names only at the top level; the right arrow opens a
 * person's own labels - work, home, delta - so the common case is two keys.
 *
 * Up and down move, right opens, left closes, Return fills, Esc closes.
 */
function chooseProfile() {
  fillGen++;                                   // cancel anything still in flight
  const snap = window.__clerkSnapshot ? window.__clerkSnapshot() : {};
  chrome.runtime.sendMessage({ type: "profiles", payload: snap }, (list) => {
    if (!list || !list.length) { chip("Clerk: nobody stored yet", "bad"); return; }

    /* Group the flat list into a person and their labels. */
    const people = [];
    for (const p of list) {
      let row = people.find((x) => x.person === p.person);
      if (!row) { row = { person: p.person, name: "", subs: [] }; people.push(row); }
      if (p.label) row.subs.push(p); else row.name = p.name;
    }
    for (const row of people) if (!row.name) row.name = row.person;

    const items = [{ name: "Best guess", hint: "reads the page", profile: null, subs: [] }]
      .concat(people.map((p) => ({
        name: p.name, hint: p.subs.length ? "›" : "",
        profile: { person: p.person, label: "", name: p.name },
        subs: p.subs,
      })));

    const d = box("good");
    const title = document.createElement("div");
    title.textContent = "Fill this form as";
    title.style.cssText = "font-weight:600;margin-bottom:6px";
    d.appendChild(title);

    const holder = document.createElement("div");
    holder.style.cssText = "max-height:300px;overflow:auto";
    d.appendChild(holder);

    const hint = document.createElement("div");
    hint.textContent = "↑↓ move · → work or home · ⏎ fill · esc";
    hint.style.cssText = "margin-top:7px;opacity:.75;font-size:11px";
    d.appendChild(hint);

    let cursor = 0;
    let openAt = -1;          // which person is expanded
    let openSub = -1;         // which of their labels is highlighted, -1 = none

    const cleanup = () => {
      document.removeEventListener("keydown", onKey, true);
      clearOverlay();
    };

    function pick(profile) {
      cleanup();
      fillEverything(profile);
    }

    function draw() {
      holder.textContent = "";
      items.forEach((it, i) => {
        const row = document.createElement("div");
        row.style.cssText = `padding:5px 8px;border-radius:6px;cursor:pointer;
          display:flex;justify-content:space-between;gap:14px;
          background:${i === cursor && openSub < 0 ? "rgba(255,255,255,.22)" : "transparent"}`;
        const n = document.createElement("span");
        n.textContent = it.name;
        const h = document.createElement("span");
        h.textContent = it.hint;
        h.style.opacity = ".6";
        row.append(n, h);
        row.onclick = () => (it.subs.length ? (openAt = i, cursor = i, openSub = 0, draw())
                                            : pick(it.profile));
        holder.appendChild(row);

        if (openAt === i) {
          it.subs.forEach((sub, j) => {
            const sr = document.createElement("div");
            sr.textContent = "    " + sub.label;
            sr.style.cssText = `padding:4px 8px;border-radius:6px;cursor:pointer;font-size:12px;
              background:${openSub === j ? "rgba(255,255,255,.22)" : "transparent"}`;
            sr.onclick = () => pick(sub);
            holder.appendChild(sr);
          });
        }
      });
    }

    function onKey(e) {
      const it = items[cursor];
      if (e.key === "Escape") { e.preventDefault(); cleanup(); return; }
      if (e.key === "ArrowDown") {
        e.preventDefault();
        if (openAt === cursor && openSub < it.subs.length - 1) openSub++;
        else { openSub = -1; cursor = Math.min(cursor + 1, items.length - 1); openAt = -1; }
      } else if (e.key === "ArrowUp") {
        e.preventDefault();
        if (openAt === cursor && openSub > 0) openSub--;
        else if (openAt === cursor && openSub === 0) openSub = -1;
        else { cursor = Math.max(cursor - 1, 0); openAt = -1; openSub = -1; }
      } else if (e.key === "ArrowRight") {
        e.preventDefault();
        if (it.subs.length) { openAt = cursor; openSub = 0; }
      } else if (e.key === "ArrowLeft") {
        e.preventDefault();
        openAt = -1; openSub = -1;
      } else if (e.key === "Enter") {
        e.preventDefault();
        pick(openAt === cursor && openSub >= 0 ? it.subs[openSub] : it.profile);
        return;
      } else {
        return;
      }
      draw();
    }

    draw();
    document.addEventListener("keydown", onKey, true);
  });
}

/* --- filling the whole form ------------------------------------------------ */

/* A radio group is ONE field, not one per button, so only the first of each
 * name is offered and setValue picks the right button within it. */
function everyField() {
  const seenRadio = new Set();
  return [...document.querySelectorAll("input,select,textarea")].filter((el) => {
    if (IGNORE_TYPES.has((el.type || "").toLowerCase())) return false;
    if (!visible(el)) return false;
    if ((el.type || "").toLowerCase() === "radio") {
      if (seenRadio.has(el.name)) return false;
      seenRadio.add(el.name);
    }
    return true;
  }).slice(0, 120);
}

/* The toolbar button fills everything it is confident about in one go. Anything
 * it is unsure of is left alone rather than guessed into the page.
 * `as` forces a person, and optionally one of their labelled values. */
function fillEverything(as) {
  if (as) clearOurFill();          // a new choice replaces the last one
  const groups = new Map();
  const els = everyField();
  const fields = els.map((el, i) => ({
    i,
    label: labelFor(el),
    name: el.name || "",
    id: el.id || "",
    placeholder: el.placeholder || "",
    autocomplete: el.getAttribute("autocomplete") || "",
    aria_label: el.getAttribute("aria-label") || "",
    input_type: (el.type || "").toLowerCase(),
    section: sectionFor(el),
    group: groupFor(el, groups),
    value: valueOf(el),
  }));

  const gen = ++fillGen;
  const blocks = new Map();
  for (const f of fields) {
    if (!f.group) continue;
    if (!blocks.has(f.group)) blocks.set(f.group, f.section || "(no heading)");
  }
  note(`fill-all starting on ${els.length} fields; blocks: ` +
       [...blocks].map(([g, s]) => `${g}="${s}"`).join(" | "));
  chip(as ? `Filling as ${as.name}…` : "Filling the form…", "good");
  chrome.runtime.sendMessage({
    type: "fillForm",
    payload: {
      url: location.href, title: document.title, fields,
      person: as ? as.person : undefined,
      variant: as ? as.label : undefined,
    },
  }, (res) => {
    if (gen !== fillGen) return;              // superseded while it was in flight
    if (!res || !res.results) {
      chip(res && res.error ? `Clerk: ${res.error}` : "Clerk: no answer", "bad");
      return;
    }
    let done = 0, held = 0;
    const what = [], why = [];
    for (const r of res.results) {
      const el = els[r.i];
      if (!el) continue;
      if (!r.value) {
        if (r.skipped) why.push(`${el.name || el.id || el.type}[${labelFor(el).slice(0, 20)}]: ${r.skipped}`);
        continue;
      }
      if (r.unsure && !as) { held++; continue; }
      if (!setValue(el, r.value)) {
        /* The control refused it - a dropdown with no matching option, a date
         * picker that would not take the format. Silently dropping these hid a
         * radio group that never got set. */
        why.push(`${el.name || el.id || el.type}[${(el.tagName === "SELECT" ? "select" : el.type)}]: nothing matched for ${r.type}`);
        continue;
      }
      {
        ourFills.push({ el });          // so a different choice can replace it
        done++;
        /* The FIELD and the KIND it was taken for - never the value. This is
         * what tells a wrong fill from a missing one. */
        what.push(`${el.name || el.id || el.type}[${labelFor(el).slice(0, 24)}]->${r.type}@${r.confidence}`);
      }
    }
    note(`filled ${done} of ${els.length}, ${held} left: ${what.join(" ")}`);
    if (why.length) note(`left empty: ${why.slice(0, 12).join(" | ")}`);
    filledSummary(done, held, as);
  });
}

/* --- driven by the background worker -------------------------------------- */

let lastAlternatives = [];
let lastTarget = null;
let altIndex = 0;

function fieldOrNull(el) {
  while (el?.shadowRoot?.activeElement) el = el.shadowRoot.activeElement;
  if (!el || !/^(INPUT|TEXTAREA|SELECT)$/.test(el.tagName)) return null;
  if (IGNORE_TYPES.has((el.type || "").toLowerCase())) return null;
  return el;
}

/* Clicking the toolbar button takes focus OUT of the page, so by the time the
 * fill request arrives document.activeElement is no longer the field. Remember
 * the last one that was. */
let lastField = null;
function onFocusIn(e) {
  const el = fieldOrNull(e.target);
  if (el) lastField = el;
}
document.addEventListener("focusin", onFocusIn, true);

function focused() {
  return fieldOrNull(document.activeElement)
    || (lastField && lastField.isConnected ? lastField : null);
}

/* The shortcut lives in the Mac app, not in browser settings, so the same combo
 * works in every browser and Nolan sets it in one place. Listening here rather
 * than through chrome.commands is also what makes that possible. */
let shortcut = { code: "KeyF", alt: true, shift: true, ctrl: false, meta: false };

function note(text) {
  try { chrome.runtime.sendMessage({ type: "note", text }); } catch (e) { /* ignore */ }
}
/* Bumped by hand when the page code changes. Safari caches an extension, so
 * without this there is no way to tell from the log whether it is running the
 * build you just installed. */
const BUILD = "states";
note(`content script loaded on ${location.host} [${BUILD}]`);

chrome.runtime.sendMessage({ type: "config" }, (cfg) => {
  if (cfg && cfg.code) shortcut = cfg;
  note(cfg ? `shortcut is ${cfg.code}` : "no shortcut came back from the app");

  /* Prove the whole chain on load, so a broken link shows up in the log without
   * anyone having to press anything. It asks about a made-up field and fills
   * nothing; the log records only whether it worked and what KIND of field came
   * back, never a value. */
  chrome.runtime.sendMessage({
    type: "suggest",
    payload: { title: "self test", fields: [{ label: "Email", name: "selftest", current: true }] },
  }, (res) => {
    note(res && res.ok
      ? `self test ok, the app answered with a ${res.type}`
      : `self test FAILED: ${res ? res.error : "no reply at all"}`);
  });
});

function onShortcut(e) {
  if (e.code !== shortcut.code) return;
  note(`shortcut seen (alt=${e.altKey} shift=${e.shiftKey})`);
  if (e.altKey !== !!shortcut.alt || e.shiftKey !== !!shortcut.shift) return;
  if (e.ctrlKey !== !!shortcut.ctrl || e.metaKey !== !!shortcut.meta) return;
  e.preventDefault();
  e.stopPropagation();
  /* Twice in a row opens the list of people, so a profile can be chosen without
   * reaching for the mouse. Once: fill this field, or the whole form if the
   * cursor is not in one. */
  const now = Date.now();
  if (now - lastShortcut < 700) {
    lastShortcut = 0;
    clearOurFill();            // same as the double-click: make room to re-fill
    chooseProfile();
    return;
  }
  lastShortcut = now;
  if (focused()) doFill(); else fillEverything();
}
document.addEventListener("keydown", onShortcut, true);

let lastShortcut = 0;                                  /* capture, so a page cannot eat it */

function onFillMessage(msg, _sender, reply) {
  if (msg.type === "menu") {
    reply({ alive: true });
    /* Clear what the first click put in. Otherwise every box is full, a full box
     * is never a target, and picking somebody appears to do nothing at all. */
    setTimeout(() => { clearOurFill(); chooseProfile(); }, 0);
    return false;
  }
  if (msg.type !== "fill") return;
  /* Answer FIRST and do the work on the next tick. Filling inside the handler
   * sends more messages of its own before this reply has been flushed, and in
   * Safari the caller then gets nothing back - the button looks dead. Returning
   * true as well made it worse: that means "I will answer later", so Safari
   * waited for a reply that had already been sent. */
  reply({ alive: true, field: !!focused() });
  setTimeout(() => fillEverything(), 0);
  return false;
}
chrome.runtime.onMessage.addListener(onFillMessage);

/* Also hang them off the isolated world's window. `tabs.sendMessage` does not
 * reach a copy that was injected programmatically - the listener registers, the
 * message never arrives - so the toolbar button calls these directly with a
 * second executeScript instead of relying on a reply. */
window.__clerkFill = (profile) => fillEverything(profile || null);
window.__clerkMenu = () => { clearOurFill(); chooseProfile(); };
/* The popup asks for this so it can put the list in a sensible order. */
window.__clerkSnapshot = () => {
  const groups = new Map();
  return {
    url: location.href, title: document.title,
    fields: everyField().map((el, i) => ({
      i, label: labelFor(el), name: el.name || "", id: el.id || "",
      section: sectionFor(el), group: groupFor(el, groups), value: valueOf(el),
    })),
  };
};

/* Everything this copy attached, so the next copy can take over cleanly. */
window.__clerkTeardown = () => {
  document.removeEventListener("keydown", onShortcut, true);
  document.removeEventListener("focusin", onFocusIn, true);
  try { chrome.runtime.onMessage.removeListener(onFillMessage); } catch (e) { /* dead */ }
  clearOverlay();
  window.__clerkTeardown = null;
};

function doFill() {
  const el = focused();
  note(`fill asked for; focused field = ${el ? (el.name || el.id || el.type) : "none"}`);
  if (!el) {
    chip("Clerk: click into a field first", "bad");
    return;
  }

  /* Press again on the same field to walk through the other people. */
  if (el === lastTarget && lastAlternatives.length) {
    const alt = lastAlternatives[altIndex % lastAlternatives.length];
    altIndex++;
    setValue(el, alt.value);
    chip(`${alt.name} instead`, "good");
    return;
  }

  chrome.runtime.sendMessage({ type: "suggest", payload: snapshot(el) }, (res) => {
    if (!res || !res.ok) {
      chip(res?.error ? `Clerk: ${res.error}` : "Clerk: no answer", "bad");
      return;
    }
    if (res.unsure && (res.alternatives || []).length > 1) {
      askWho(el, res);
      return;
    }
    if (!setValue(el, res.value)) {
      chip(`No option matches "${res.value}"`, "bad");
      return;
    }
    lastTarget = el;
    lastAlternatives = res.alternatives || [];
    altIndex = 0;
    chip(`${res.person ? res.person + " \u00b7 " : ""}${res.type_label}`, "good");
  });
}

} catch (bootError) {
  /* Anything thrown here leaves the page with NO listener, so the button and the
   * shortcut both do nothing and there is no clue why. Say so in the log. */
  try {
    chrome.runtime.sendMessage({ type: "note",
      text: `content script blew up: ${bootError && bootError.message} @ ${bootError && bootError.stack ? String(bootError.stack).split("\n")[1] : "?"}` });
  } catch (e) { /* nothing left to report with */ }
}
