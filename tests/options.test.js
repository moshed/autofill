/* Matching an option written one way against a value written another.
 *
 *   node tests/options.test.js
 *
 * Runs extension/options.js under node with the smallest possible stand-in for
 * a page, so this can be checked without a browser.
 */
const fs = require("fs");
const path = require("path");

const lang = process.env.PAGE_LANG || "he";
const sandbox = { document: { documentElement: { lang } }, Intl, console };
const src = fs.readFileSync(path.join(__dirname, "..", "extension", "options.js"), "utf8");
new Function("document", "Intl", src + "\nthis.optionMatches = optionMatches;")
  .call(sandbox, sandbox.document, Intl);
const { optionMatches } = sandbox;

let bad = 0;
/** text and value as the MENU has them, want as the STORE has it. */
function hit(text, value, want, should, note) {
  const score = optionMatches(text, value, want);
  const ok = should ? score >= 2 : score < 2;
  if (!ok) bad++;
  console.log(`  ${ok ? "ok   " : "WRONG"} ${note.padEnd(46)} score ${score}`);
}

console.log("\nstates and provinces");
hit("New York", "NY", "NY", true, "menu says New York, store says NY");
hit("New York", "36", "NY", true, "menu says New York, value is a number");
hit("NY", "NY", "New York", true, "menu says NY, store says New York");
hit("District of Columbia", "DC", "DC", true, "District of Columbia, which initials miss");
hit("Ontario", "ON", "ON", true, "a Canadian province");
hit("New Jersey", "NJ", "NY", false, "New Jersey must NOT take NY");
hit("North Dakota", "ND", "NY", false, "North Dakota must NOT take NY");

console.log("\ncountries");
hit("ארצות הברית", "US", "United States", true, "Hebrew menu, English store");
hit("United States", "US", "United States", true, "plain English");
hit("United States", "USA", "United States", true, "a three letter value");
hit("ישראל", "IL", "United States", false, "Israel must NOT take United States");
hit("France", "FR", "United States", false, "France must NOT take United States");

console.log("\nsex");
hit("זכר", "1", "M", true, "Hebrew male against a stored M");
hit("נקבה", "0", "F", true, "Hebrew female against a stored F");
hit("נקבה", "0", "M", false, "female must NOT take M");
hit("Male", "1", "M", true, "English male");

console.log(bad === 0 ? "\nall good" : `\n${bad} failures`);
process.exit(bad === 0 ? 0 : 1);
