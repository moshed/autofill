/* Matching one option in a menu, or one button in a radio group, against a value
 * from the store - when the two are not written the same way.
 *
 * "United States" against "ארצות הברית", "NY" against "New York", "M" against
 * "זכר". Kept apart from content.js with no DOM of its own beyond the page's
 * language, so tests/options.test.js can run it under node.
 */
/* --- a country or a sex, written in whatever language the page uses ---------
 *
 * El Al's citizenship menu lists countries in Hebrew ("ארצות הברית") with a
 * country code as the value, while the store holds "United States". Nothing
 * matched and the box stayed empty. The browser already knows every country in
 * every language, so ask it rather than shipping a table.
 */
const REGION_CODES = (() => {
  const out = [];
  for (let a = 65; a <= 90; a++) {
    for (let b = 65; b <= 90; b++) out.push(String.fromCharCode(a, b));
  }
  return out;
})();

const normText = (s) => (s || "").toLowerCase()
  .normalize("NFD").replace(/[\u0300-\u036f]/g, "")
  .replace(/[^\p{L}\p{N}]+/gu, " ")
  .trim();

let countryIdx = null;
function countryIndex() {
  if (countryIdx) return countryIdx;
  const pageLang = (document.documentElement.lang || "").slice(0, 2);
  const langs = [...new Set(["en", pageLang, "he"].filter(Boolean))];
  const byName = new Map();
  const codes = new Set();
  for (const lang of langs) {
    let dn;
    try { dn = new Intl.DisplayNames([lang], { type: "region" }); } catch (e) { continue; }
    for (const code of REGION_CODES) {
      let n;
      try { n = dn.of(code); } catch (e) { continue; }
      if (!n || n === code) continue;          // not a real region
      byName.set(normText(n), code);
      codes.add(code);
    }
  }
  countryIdx = { byName, codes };
  return countryIdx;
}

/* Three-letter codes are common on travel forms and Intl does not know them. */
const ALPHA3 = {
  usa: "US", isr: "IL", gbr: "GB", fra: "FR", deu: "DE", can: "CA", aus: "AU",
  ita: "IT", esp: "ES", nld: "NL", che: "CH", bel: "BE", aut: "AT", swe: "SE",
  nor: "NO", dnk: "DK", fin: "FI", irl: "IE", prt: "PT", grc: "GR", pol: "PL",
  rus: "RU", chn: "CN", jpn: "JP", kor: "KR", ind: "IN", bra: "BR", mex: "MX",
  zaf: "ZA", tur: "TR", are: "AE", arg: "AR", nzl: "NZ", tha: "TH", sgp: "SG",
};

const codeCache = new Map();
function regionCode(text) {
  const t = normText(text);
  if (!t) return null;
  if (codeCache.has(t)) return codeCache.get(t);
  const { byName, codes } = countryIndex();
  let out = byName.get(t) || null;
  if (!out) {
    const up = t.toUpperCase();
    if (up.length === 2 && codes.has(up)) out = up;
    else if (ALPHA3[t]) out = ALPHA3[t];
  }
  codeCache.set(t, out);
  return out;
}

/* States and provinces. The store holds "NY"; a menu may list "New York", and
 * the initials trick that used to cover this gets "District of Columbia" wrong
 * and cannot go the other way at all. There is no Intl table for subdivisions,
 * so here is one. */
const SUBDIVISIONS = {
  AL: "Alabama", AK: "Alaska", AZ: "Arizona", AR: "Arkansas", CA: "California",
  CO: "Colorado", CT: "Connecticut", DE: "Delaware", FL: "Florida", GA: "Georgia",
  HI: "Hawaii", ID: "Idaho", IL: "Illinois", IN: "Indiana", IA: "Iowa",
  KS: "Kansas", KY: "Kentucky", LA: "Louisiana", ME: "Maine", MD: "Maryland",
  MA: "Massachusetts", MI: "Michigan", MN: "Minnesota", MS: "Mississippi",
  MO: "Missouri", MT: "Montana", NE: "Nebraska", NV: "Nevada",
  NH: "New Hampshire", NJ: "New Jersey", NM: "New Mexico", NY: "New York",
  NC: "North Carolina", ND: "North Dakota", OH: "Ohio", OK: "Oklahoma",
  OR: "Oregon", PA: "Pennsylvania", RI: "Rhode Island", SC: "South Carolina",
  SD: "South Dakota", TN: "Tennessee", TX: "Texas", UT: "Utah", VT: "Vermont",
  VA: "Virginia", WA: "Washington", WV: "West Virginia", WI: "Wisconsin",
  WY: "Wyoming", DC: "District of Columbia", PR: "Puerto Rico",
  VI: "Virgin Islands", GU: "Guam", AS: "American Samoa",
  MP: "Northern Mariana Islands", AA: "Armed Forces Americas",
  AE: "Armed Forces Europe", AP: "Armed Forces Pacific",
  // Canada, because a form that asks for a state often takes these too.
  AB: "Alberta", BC: "British Columbia", MB: "Manitoba", NB: "New Brunswick",
  NL: "Newfoundland and Labrador", NS: "Nova Scotia", NT: "Northwest Territories",
  NU: "Nunavut", ON: "Ontario", PE: "Prince Edward Island", QC: "Quebec",
  SK: "Saskatchewan", YT: "Yukon",
};
const SUBDIVISION_BY_NAME = (() => {
  const m = new Map();
  for (const [code, name] of Object.entries(SUBDIVISIONS)) m.set(normText(name), code);
  return m;
})();

/* "NY", "New York", "new  york" -> "NY". Null when it is not one. */
function subdivisionCode(text) {
  const t = normText(text);
  if (!t) return null;
  const up = t.toUpperCase();
  if (up.length === 2 && SUBDIVISIONS[up]) return up;
  return SUBDIVISION_BY_NAME.get(t) || null;
}

/* Male and female, for a radio group whose labels are זכר / נקבה. */
const SEX_WORDS = {
  m: ["m", "male", "man", "boy", "mr", "זכר", "ז", "mannlich", "mann", "homme",
      "masculin", "masculino", "hombre", "varon", "maschio", "uomo", "man",
      "mezczyzna", "erkek", "muzhskoy", "муж", "мужской", "男", "男性", "男の子",
      "남성", "남자", "ذكر"],
  f: ["f", "female", "woman", "girl", "ms", "mrs", "נקבה", "נ", "weiblich",
      "frau", "femme", "feminin", "femenino", "mujer", "femmina", "donna",
      "vrouw", "kobieta", "kadin", "жен", "женский", "女", "女性", "女の子",
      "여성", "여자", "أنثى"],
};
function sexKey(s) {
  const t = normText(s);
  if (!t) return null;
  for (const k of ["m", "f"]) {
    if (SEX_WORDS[k].some((w) => normText(w) === t)) return k;
  }
  return null;
}

function optionMatches(text, value, want) {
  const t = (text || "").trim().toLowerCase();
  const v = (value || "").trim().toLowerCase();
  const w = want.trim().toLowerCase();
  if (!w) return 0;
  if (v === w || t === w) return 4;

  /* The same country said another way, and the same sex said another way. */
  const wc = regionCode(w);
  if (wc && (regionCode(t) === wc || regionCode(v) === wc)) return 4;
  const ws = sexKey(w);
  if (ws && (sexKey(t) === ws || sexKey(v) === ws)) return 4;
  const wsub = subdivisionCode(w);
  if (wsub && (subdivisionCode(t) === wsub || subdivisionCode(v) === wsub)) return 4;

  if (v.startsWith(w) || t.startsWith(w)) return 3;
  if (w.startsWith(v) && v) return 2;                 // "United States" -> "US"
  if (w.startsWith(t) && t) return 2;
  /* A last resort for anything the tables above do not cover. It gets
   * "District of Columbia" wrong, which is why it sits below them. */
  const initials = t.split(/\s+/).map((x) => x[0] || "").join("");
  if (initials.length > 1 && initials === w) return 2;
  if (t.includes(w) || v.includes(w)) return 1;
  return 0;
}
