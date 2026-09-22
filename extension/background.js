/* Talks to the local matcher. The content script cannot: a content script is
 * bound by the page's CORS rules, the service worker is not. */

const BASE = "http://127.0.0.1:8771";

/* Safari gives an extension no console anyone can see without opening the Web
 * Inspector, so everything interesting is posted to the app, which writes
 * ~/Library/Logs/Clerk.log. Field labels and outcomes only - never a value. */
async function note(text) {
  try {
    await fetch(`${BASE}/log`, { method: "POST", body: `[bg] ${text}` });
  } catch (e) {
    console.log("[Clerk]", text, "(and the log post failed:", e.message, ")");
  }
}

note("background started");

/* No token: the app recognises an extension by the Origin the browser sets on
 * this request, which a web page cannot forge. */
chrome.runtime.onMessage.addListener((msg, sender, reply) => {
  /* The shortcut is set in the Mac app, so every page asks what it is. */
  if (msg.type === "note") {
    note(`[page] ${msg.text}`);
    reply(true);
    return true;
  }
  if (msg.type === "config") {
    (async () => {
      try {
        const r = await fetch(`${BASE}/config`, { method: "POST", body: "{}" });
        reply(await r.json());
      } catch (e) {
        note(`config failed: ${e.name}: ${e.message}`);
        reply(null);
      }
    })();
    return true;
  }
  if (msg.type === "profiles") {
    (async () => {
      try {
        const r = await fetch(`${BASE}/profiles`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(msg.payload || {}),
        });
        reply(await r.json());
      } catch (e) {
        note(`profiles failed: ${e.name}: ${e.message}`);
        reply(null);
      }
    })();
    return true;
  }
  if (msg.type === "fillForm") {
    (async () => {
      try {
        const r = await fetch(`${BASE}/fill-form`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(msg.payload),
        });
        reply(await r.json());
      } catch (e) {
        note(`fill-form failed: ${e.name}: ${e.message}`);
        reply({ error: `cannot reach the app (${e.message})` });
      }
    })();
    return true;
  }
  if (msg.type !== "suggest") return;
  (async () => {
    try {
      const r = await fetch(`${BASE}/suggest`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(msg.payload),
      });
      reply(await r.json());
    } catch (e) {
      note(`suggest failed: ${e.name}: ${e.message}`);
      reply({ ok: false, error: `cannot reach the app (${e.message})` });
    }
  })();
  return true;                       // keep the channel open for the async reply
});

/* Clicking the toolbar button has to work even when the extension has not been
 * given standing access to the site: nothing happens at all in that case,
 * because the content script was never injected. `activeTab` grants access for
 * this one click, so inject on demand and then ask it to fill. */
/* A browser hands `action.onClicked` a tab and nothing else - no modifier keys -
 * so shift-click and click are the same event and cannot be told apart. A SECOND
 * click soon after the first can be, so that opens the list. The first click
 * fills immediately either way, so nothing waits to find out. */
let lastClick = 0;

async function fire(tab) {
  if (!tab?.id) return;
  const now = Date.now();
  const menu = now - lastClick < 700;
  lastClick = now;
  note(menu ? "toolbar button clicked twice - showing the list"
            : "toolbar button clicked");

  const target = { tabId: tab.id, frameIds: [0] };

  /* Call the function in the page instead of sending it a message. A message
   * reaches a content script that loaded with the page, but NOT one that was
   * injected here - it registers its listener and never hears anything. Calling
   * works either way. */
  const call = () => chrome.scripting.executeScript({
    target,
    func: (wantMenu) => {
      const f = wantMenu ? window.__clerkMenu : window.__clerkFill;
      if (!f) return false;
      f();
      return true;
    },
    args: [menu],
  }).then((r) => r?.[0]?.result === true).catch(() => false);

  /* Inject FIRST, every time. Asking "does __clerkFill exist?" is not the same
   * as asking "is this page's copy alive". After the app is reinstalled the
   * extension gets a new identity and every page already open keeps the OLD
   * content script - whose globals are still on the window. The check said yes,
   * the dead copy ran, it could not reach this background, and so nothing was
   * filled AND nothing was logged. That is exactly what "it does nothing on the
   * page I already had open" looks like. Cost an El Al check-in on 2026-09-22.
   *
   * content.js calls __clerkTeardown on the old copy and takes over, so
   * injecting again is safe and cheap. */
  try {
    await chrome.scripting.executeScript({ target, files: ["content.js"] });
  } catch (e) {
    note(`could not inject: ${e.message}`);
    if (await call()) return;                 // a page we may not script, but alive
    return;
  }
  if (await call()) return;
  note("clicked, injected, and the page still has nothing to call");
}

chrome.action?.onClicked.addListener(fire);
