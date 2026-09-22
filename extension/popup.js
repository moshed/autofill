/* The toolbar button opens this instead of firing an action, because a browser
 * never tells an extension whether a click had Shift held - so shift-click and
 * click cannot be told apart. A list that opens focused on the first entry gets
 * to the same place: tap, press Return. */
const BASE = "http://127.0.0.1:8771";
const list = document.getElementById("list");

async function activeTab() {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  return tab;
}

/* Ask the page for what it already has, so the order reflects the form. */
async function pageFields(tabId) {
  try {
    const r = await chrome.scripting.executeScript({
      target: { tabId, frameIds: [0] },
      func: () => (window.__autofillSnapshot ? window.__autofillSnapshot() : null),
    });
    return r?.[0]?.result || null;
  } catch (e) {
    return null;
  }
}

async function run(profile) {
  const tab = await activeTab();
  if (!tab?.id) return;
  const target = { tabId: tab.id, frameIds: [0] };
  const call = () => chrome.scripting.executeScript({
    target,
    func: (p) => {
      if (!window.__autofillFill) return false;
      window.__autofillFill(p);
      return true;
    },
    args: [profile],
  }).then((r) => r?.[0]?.result === true).catch(() => false);

  if (!(await call())) {
    try {
      await chrome.scripting.executeScript({ target, files: ["content.js"] });
    } catch (e) { /* nothing to do */ }
    await call();
  }
  window.close();
}

function row(label, sub, profile, first) {
  const li = document.createElement("li");
  li.tabIndex = 0;
  const name = document.createElement("span");
  name.textContent = label;
  li.appendChild(name);
  if (sub) {
    const k = document.createElement("span");
    k.className = "k";
    k.textContent = sub;
    li.appendChild(k);
  }
  li.onclick = () => run(profile);
  li.onkeydown = (e) => {
    if (e.key === "Enter" || e.key === " ") { e.preventDefault(); run(profile); }
    if (e.key === "ArrowDown") { e.preventDefault(); li.nextElementSibling?.focus(); }
    if (e.key === "ArrowUp") { e.preventDefault(); li.previousElementSibling?.focus(); }
    if (e.key === "Escape") window.close();
  };
  list.appendChild(li);
  if (first) requestAnimationFrame(() => li.focus());
}

(async () => {
  const tab = await activeTab();
  const snap = tab?.id ? await pageFields(tab.id) : null;
  let profiles = [];
  try {
    const r = await fetch(`${BASE}/profiles`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(snap || {}),
    });
    profiles = await r.json();
  } catch (e) {
    /* The app is not running. Opening its URL scheme starts it - which is the
     * only thing an extension can do to bring a Mac app back. */
    const li = document.createElement("li");
    li.tabIndex = 0;
    li.textContent = "Start Autofill";
    const act = () => {
      chrome.tabs.create({ url: "autofill://settings" });
      window.close();
    };
    li.onclick = act;
    li.onkeydown = (e) => { if (e.key === "Enter" || e.key === " ") act(); };
    list.appendChild(li);
    requestAnimationFrame(() => li.focus());
    document.querySelector(".hint").textContent =
      "The app is not running. Return starts it, then try again.";
    return;
  }
  /* First entry is no override: let it read the page and decide. */
  row("Best guess", "reads the page", null, true);
  for (const p of profiles) row(p.name, "", p.person ? p : null, false);
})();
