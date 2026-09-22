import Foundation

/// What does the field under the cursor want, and whose value goes in it.
///
/// Two rules, and they are the whole design:
///
/// 1. **Jev decides the field type only.** It is asked about labels and never
///    sees a value, not from the page and not from the store.
/// 2. **Who the field belongs to is worked out in code.** Names already on the
///    page are matched against the store here on the Mac. Nothing leaves.

struct FormField: Codable {
    var label: String?
    var name: String?
    var id: String?
    var placeholder: String?
    var autocomplete: String?
    var ariaLabel: String?
    var section: String?
    var group: String?
    var value: String?
    var current: Bool?
    /// the input's `type` attribute - a `date` input only accepts ISO
    var inputType: String?

    enum CodingKeys: String, CodingKey {
        case label, name, id, placeholder, autocomplete, section, group, value, current
        case ariaLabel = "aria_label"
        case inputType = "input_type"
    }
}

struct FormPayload: Codable {
    var url: String?
    var title: String?
    var fields: [FormField]
    /// Set when Nolan picked somebody from the list on the page. Then there is
    /// no guessing to do: fill as this person, and prefer this labelled value.
    var person: String?
    var variant: String?
}

/// One line in that list: a person, or a person and one of their labelled values.
struct Profile: Codable {
    var person: String
    var label: String
    var name: String
}

struct Suggestion: Codable {
    var ok: Bool
    var value: String?
    var type: String?
    var typeLabel: String?
    var person: String?
    var confidence: Double?
    var why: String?
    var error: String?
    /// true when the app could not tell whose field this is. The extension then
    /// shows the list instead of filling, so nothing is guessed into a form.
    var unsure: Bool = false
    var alternatives: [Alternative] = []

    struct Alternative: Codable { var person: String; var name: String; var value: String }

    enum CodingKeys: String, CodingKey {
        case ok, value, type, person, confidence, why, error, unsure, alternatives
        case typeLabel = "type_label"
    }
}

/// One field's answer when the whole form is filled at once.
struct FillItem: Codable {
    var i: Int
    var value: String?
    var type: String?
    var typeLabel: String?
    var person: String?
    var confidence: Double = 0
    var unsure: Bool = false
    /// Why nothing was put here. Reported so a field that stays empty can be
    /// explained without another round of guessing.
    var skipped: String?
    var alternatives: [Suggestion.Alternative] = []

    enum CodingKeys: String, CodingKey {
        case i, value, type, person, confidence, unsure, skipped, alternatives
        case typeLabel = "type_label"
    }
}

struct FillAll: Codable {
    var ok: Bool = true
    var results: [FillItem] = []
}

enum Match {
    /// Set from Setup. `true` stops every call out, whichever key is in use.
    /// This used to be expressed by blanking the key, which no longer works:
    /// an empty key now means "use the shared key on the proxy".
    nonisolated(unsafe) static var offline = false

    /// A noul is a rank, not a probability. Tune these against tests/cases.json,
    /// never by eye.
    static let typeMin = 0.25
    static let margin = 0.10

    // MARK: - grouping

    static func groupKey(_ f: FormField) -> String {
        if let g = f.group, !g.isEmpty { return "g:\(g)" }
        if let s = f.section, !s.trimmingCharacters(in: .whitespaces).isEmpty {
            return "s:\(s.trimmingCharacters(in: .whitespaces).lowercased())"
        }
        // `pax1_ppt` and `pax1_fn` share the signature "1", so they are one block.
        let raw = "\(f.name ?? "") \(f.id ?? "")"
        let nums = raw.split(whereSeparator: { !$0.isNumber }).map(String.init)
        return nums.isEmpty ? "" : "n:\(nums.joined(separator: ","))"
    }

    // MARK: - naming a person

    static func norm(_ s: String) -> String {
        s.lowercased().filter { $0.isLetter && $0.isASCII }
    }

    /// How strongly does `text` name this person? 0 means not at all.
    ///
    /// A shared surname must score less than a first name, or "Carter" in a
    /// last-name field names the whole family and drowns out the "Leon" beside
    /// it. Scores are graded, then added across the fields in scope.
    static func score(_ p: Person, naming text: String) -> Int {
        let v = norm(text)
        guard !v.isEmpty else { return 0 }
        let given = p.text("given_name") ?? ""
        let family = p.text("family_name") ?? ""
        let tokens = Set(text.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init))

        var best = 0
        let full = norm(given) + norm(family)
        if !full.isEmpty, v == full { best = 4 }
        for n in p.aliases + [given, p.text("middle_name") ?? "", p.text("full_name") ?? ""] {
            let nn = norm(n)
            guard !nn.isEmpty else { continue }
            if nn == v { best = max(best, 3) }
            else if tokens.contains(n.lowercased()) { best = max(best, 2) }
        }
        if !family.isEmpty, tokens.contains(family.lowercased()) { best = max(best, 1) }
        return best
    }

    struct PersonResult { let id: String?; let confidence: Double; let why: String; let others: [String] }

    static func resolvePerson(_ data: StoreData, payload: FormPayload,
                              current: FormField) -> PersonResult {
        guard !data.people.isEmpty else {
            return PersonResult(id: nil, confidence: 0, why: "the store has no people in it", others: [])
        }
        if data.people.count == 1 {
            return PersonResult(id: data.people[0].id, confidence: 1,
                                why: "only one person is stored", others: [])
        }

        // Anything on the page that carries a name: a filled name field, or the
        // heading the cursor sits under ("Traveler 2 - Freya Carter").
        // Any filled field can name somebody. A field the patterns already read
        // as a name counts however weakly it matches; every other field, and any
        // heading, has to match a first or full name (2 or more), so that a
        // stray "Carter" somewhere on the page names nobody.
        //
        // This is why a French label works with no French in the vocabulary:
        // "Prenom" is not recognised, but its value "Leon" still is.
        var sources = [(text: String, key: String, floor: Int)]()
        for f in payload.fields {
            guard f.current != true, let v = f.value, !v.trimmingCharacters(in: .whitespaces).isEmpty
            else { continue }
            let named = Fields.guessType(f).key.map(Fields.isName) ?? false
            sources.append((v, groupKey(f), named ? 1 : 2))
        }
        let cur = groupKey(current)
        if let s = current.section, !s.isEmpty { sources.append((s, cur, 2)) }

        // A value already on the page that belongs to exactly one person names
        // that person, whatever the field is called. Typing your own work email
        // in should be enough to say whose form this is.
        func valueOwners(sameBlockOnly: Bool) -> [String: Int] {
            var out = [String: Int]()
            for f in payload.fields {
                guard f.current != true else { continue }
                if sameBlockOnly, !(groupKey(f) == cur && !cur.isEmpty) { continue }
                let onPage = (f.value ?? "").trimmingCharacters(in: .whitespaces).lowercased()
                guard onPage.count >= 4 else { continue }
                let owners = data.people.filter { p in
                    p.fields.values.flatMap { $0 }.contains { $0.value.lowercased() == onPage }
                }
                if owners.count == 1 { out[owners[0].id, default: 0] += 3 }
            }
            return out
        }

        func tally(sameBlockOnly: Bool) -> (totals: [String: Int], seen: [String: String]) {
            var totals = [String: Int](), seen = [String: String]()
            for src in sources {
                if sameBlockOnly, !(src.key == cur && !cur.isEmpty) { continue }
                for p in data.people {
                    let s = score(p, naming: src.text)
                    if s >= src.floor {
                        totals[p.id, default: 0] += s
                        seen[p.id] = src.text
                    }
                }
            }
            return (totals, seen)
        }

        for (sameBlock, where_) in [(true, "in the same block"), (false, "on the page")] {
            var (totals, seen) = tally(sameBlockOnly: sameBlock)

            // A stored value sitting on the page only breaks a genuine TIE. As
            // evidence it is weaker than a name right beside the field: a filled
            // passport box would otherwise pull the next block to its owner.
            let byValue = valueOwners(sameBlockOnly: sameBlock)
            if totals.isEmpty || (totals.count > 1 && Set(totals.values).count == 1) {
                for (id, n) in byValue {
                    totals[id, default: 0] += n
                    if seen[id] == nil { seen[id] = "a value already on the page" }
                }
            }
            guard !totals.isEmpty else { continue }

            let ranked: [(key: String, value: Int)] = totals.sorted { $0.value > $1.value }
            if ranked.count == 1 || ranked[0].value > ranked[1].value {
                let id = ranked[0].key
                return PersonResult(id: id, confidence: 0.95,
                                    why: "\"\(seen[id] ?? "")\" \(where_) is \(id)",
                                    others: ranked.dropFirst().prefix(3).map { $0.key })
            }
            // A tie. The adult is the safe guess and the page shows the list.
            let d = data.defaultPerson
            return PersonResult(id: d?.id, confidence: 0.4,
                                why: "\(ranked.count) people match equally \(where_)",
                                others: ranked.map { $0.key }.filter { $0 != d?.id })
        }

        // Nobody is named anywhere on the page, so this is a form about one
        // person and the default is a deliberate setting, not a guess. Treating
        // it as unsure meant every sign-up form put up a list of the family.
        let d = data.defaultPerson
        return PersonResult(id: d?.id, confidence: 0.8,
                            why: "nobody is named on the page, so the default person",
                            others: data.people.map(\.id).filter { $0 != d?.id })
    }

    /// Flattens people x their values into the list the page shows.
    static func options(for people: [String], type: String, data: StoreData,
                        field: FormField, payload: FormPayload,
                        jevKey: String, allowJev: Bool,
                        preRanked: [FieldValue]? = nil) async -> [Suggestion.Alternative] {
        var out = [Suggestion.Alternative]()
        for pid in people {
            let vals = preRanked ?? data.values(person: pid, type: type)
            for v in vals where !v.value.isEmpty {
                out.append(.init(person: pid, name: nameFor(pid, v, data),
                                 value: value(v, type, field, payload)))
            }
        }
        return out
    }

    static func nameFor(_ pid: String?, _ v: FieldValue, _ data: StoreData) -> String {
        let who = pid.flatMap { data.person($0)?.displayName } ?? "Household"
        return v.label.isEmpty ? who : "\(who) · \(v.label)"
    }

    static func value(_ v: FieldValue, _ type: String, _ field: FormField,
                      _ page: FormPayload? = nil) -> String {
        dateTypes.contains(type) ? formatDate(v.value, for: field, on: page) : v.value
    }

    // MARK: - which of several values

    /// Words that mean the same kind of value. A stored label of "work" should
    /// also answer to "business" and "company" on the page.
    static let variantWords: [[String]] = [
        // fescony is in here, not a group of its own: being on the company's own
        // site is what "work" means in practice.
        ["work", "business", "company", "office", "corporate", "employer", "job",
         "official", "fescony", "fesco"],
        ["personal", "home", "private", "own"],
        ["school", "university", "college", "student"],
        ["mobile", "cell", "cellular"],
        ["billing", "invoice"],
        ["shipping", "delivery", "ship"],
        // Airlines, so a frequent flyer number labelled "united" is found on a
        // page that says MileagePlus, and on united.com.
        ["united", "mileageplus", "ua"],
        ["delta", "skymiles", "dl"],
        ["american", "aadvantage", "aa", "americanairlines"],
        ["jetblue", "trueblue", "b6"],
        ["elal", "el al", "matmid", "ly"],
        ["southwest", "rapidrewards", "wn"],
        ["alaska", "mileageplan", "as"],
        ["lufthansa", "miles and more", "lh"],
        ["british", "avios", "executive club", "ba"],
        ["emirates", "skywards", "ek"],
        ["marriott", "bonvoy"],
        ["hilton", "honors"],
        ["hyatt"],
        ["cathay", "cathaypacific", "asiamiles", "cx"],
        ["chinasouthern", "skypearl", "cz"],
        ["starlux", "jx"],
        ["prioritypass", "prioritypass"],
    ]

    static func words(for label: String) -> [String] {
        let l = label.lowercased().trimmingCharacters(in: .whitespaces)
        guard !l.isEmpty else { return [] }
        for group in variantWords where group.contains(l) { return group }
        return [l]
    }

    /// Which "side" of life the page is already about, read from what is
    /// ALREADY FILLED IN on it.
    ///
    /// If a box on the form holds the work email address, the form is about work,
    /// so the street address should be the work one. The comparison is between
    /// the page and the store, both here on the Mac - nothing is sent anywhere.
    /// Returns, for example, ["work": 2].
    static func labelsAlreadyOnPage(_ payload: FormPayload, _ data: StoreData) -> [String: Int] {
        var out = [String: Int]()
        var stored = [(label: String, value: String)]()
        for p in data.people {
            for list in p.fields.values {
                for v in list where !v.label.isEmpty { stored.append((v.label, v.value)) }
            }
        }
        for list in data.shared.values {
            for v in list where !v.label.isEmpty { stored.append((v.label, v.value)) }
        }
        guard !stored.isEmpty else { return out }

        for f in payload.fields {
            guard f.current != true else { continue }
            let onPage = (f.value ?? "").trimmingCharacters(in: .whitespaces).lowercased()
            guard onPage.count >= 4 else { continue }
            for s in stored where s.value.lowercased() == onPage {
                out[s.label, default: 0] += 1
            }
        }
        return out
    }

    struct VariantChoice { let ranked: [FieldValue]; let sure: Bool; let why: String }

    /// Nolan has a work address and a personal one. Which does this field want?
    ///
    /// The page is read first and it costs nothing: the field's own label, then
    /// the rest of the form, then the site's name. Jev is asked only when the
    /// page says nothing, and it is asked about LABELS - it never sees an
    /// address. If nothing settles it, every one comes back and the page shows
    /// the list.
    static func chooseVariant(_ values: [FieldValue], type: String, field: FormField,
                              payload: FormPayload, data: StoreData,
                              jevKey: String, allowJev: Bool) async -> VariantChoice {
        let labelled = values.filter { !$0.label.isEmpty }
        guard values.count > 1, !labelled.isEmpty else {
            return VariantChoice(ranked: values, sure: true, why: "one value stored")
        }

        // WORDS, not substrings. Matching "own" inside "town" made a field
        // labelled Town pick the home address over the work one.
        func tokens(_ text: String) -> Set<String> {
            Set(text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                .map(String.init))
        }
        // The site itself is a strong clue when the field is vague: a plain
        // "Frequent flyer number" box on aa.com wants the AA number. The HOST is
        // what counts, not the whole page - a mention of Delta in a footer is
        // not the same as being on delta.com.
        var hostWords = Set<String>()
        if let raw = payload.url, let u = URL(string: raw), let h = u.host?.lowercased() {
            for part in h.split(separator: ".").map(String.init)
            where !["www", "com", "net", "org", "co", "uk", "il", "io"].contains(part) {
                hostWords.insert(part)
            }
        }

        let near = tokens(Fields.haystack(field))
        // Only fields that are actually FILLED get a vote. Counting the labels of
        // empty boxes meant a page offering "Work email" and "Personal email"
        // pushed the plain "Email" box towards work for no reason.
        let form = tokens(payload.fields
            .filter { !($0.value ?? "").trimmingCharacters(in: .whitespaces).isEmpty }
            .map { Fields.haystack($0) }.joined(separator: " "))
        let site = tokens((payload.title ?? "") + " " + (payload.url ?? ""))

        let already = labelsAlreadyOnPage(payload, data)

        var scores = [Int](repeating: 0, count: values.count)
        for (i, v) in values.enumerated() {
            // The work email is already typed into this form, so use the work
            // address too. This is the strongest clue after the field's own words.
            if let n = already[v.label], n > 0 { scores[i] += 4 + n }
            for w in words(for: v.label) {
                // The field's own words beat the site. An AAdvantage box on
                // delta.com is still an AAdvantage box.
                if near.contains(w) { scores[i] += 8 }
                if hostWords.contains(w) { scores[i] += 5 }
                if form.contains(w) { scores[i] += 2 }
                if site.contains(w) { scores[i] += 1 }
            }
            // "work" against fescony.com: the label of the value is not the only
            // clue, the value itself can name the site. Compared here, never sent.
            if let domain = v.value.split(separator: "@").last,
               let stem = domain.split(separator: ".").first.map(String.init),
               stem.count >= 4,
               hostWords.contains(stem.lowercased()) || site.contains(stem.lowercased()) {
                scores[i] += 5
            }
        }

        func rank(_ s: [Int]) -> [FieldValue] {
            zip(values, s).sorted { $0.1 > $1.1 }.map(\.0)
        }
        let best = scores.max() ?? 0
        if best > 0, scores.filter({ $0 == best }).count == 1 {
            let winner = values[scores.firstIndex(of: best)!]
            let how = already[winner.label] != nil
                ? "the \(winner.label) details are already on this form"
                : "the page says \"\(winner.label)\""
            return VariantChoice(ranked: rank(scores), sure: true, why: how)
        }

        guard allowJev, !offline else {
            return VariantChoice(ranked: values, sure: false, why: "nothing on the page says which")
        }

        // Label-only question. The values are not in the prompt.
        let state = maskedState(payload, current: field, data: data)
        let noun = Fields.label(type).lowercased()
        var qs = [String: String]()
        for v in labelled {
            qs[v.label] = "Does this field want the person's \(v.label) \(noun), "
                + "rather than any other \(noun) they have?"
        }
        guard let answers = try? await Jev.nouls(state: state, questions: qs, key: jevKey),
              let top = answers.max(by: { $0.value < $1.value })
        else {
            return VariantChoice(ranked: values, sure: false, why: "could not ask")
        }
        let next = answers.filter { $0.key != top.key }.values.max() ?? 0
        let ordered = values.sorted { a, b in
            (answers[a.label] ?? -1) > (answers[b.label] ?? -1)
        }
        if top.value >= typeMin, top.value - next >= margin {
            return VariantChoice(ranked: ordered, sure: true,
                                 why: String(format: "AI read the labels: %@ %.2f", top.key, top.value))
        }
        return VariantChoice(ranked: ordered, sure: false,
                             why: String(format: "%@ and %@ are too close", top.key,
                                         answers.filter { $0.key != top.key }
                                             .max(by: { $0.value < $1.value })?.key ?? "another"))
    }

    // MARK: - dates

    static let dateTypes: Set<String> = ["dob", "passport_issued", "passport_expiry",
                                         "eta_il_expiry"]

    /// Dates are stored ISO because that is the one unambiguous way to write
    /// one. A form almost never wants it that way, so turn it into whatever the
    /// field is asking for, reading the placeholder first and falling back to
    /// the American order.
    /// Does this page write the month first?
    ///
    /// Only the United States really does. Everywhere else writes the day first,
    /// and `07/12` is 12 July in one reading and 7 December in the other - the
    /// worst kind of mistake, because the form accepts both and says nothing.
    /// Found on 2026-09-22: an Israeli form was being given the American order.
    static func monthFirst(_ page: FormPayload?) -> Bool {
        guard let page, let host = URL(string: page.url ?? "")?.host?.lowercased()
        else { return true }                       // nothing to go on: unchanged

        let tld = host.split(separator: ".").last.map(String.init) ?? ""
        if tld == "gov" || tld == "mil" || tld == "us" { return true }
        // A two-letter country code that is not the United States.
        if tld.count == 2 { return false }

        // A form written in another language is not an American form. Any letter
        // outside plain ASCII says so: Hebrew, Arabic, Chinese, Cyrillic, and
        // the accents in "Numéro" or "Geburtsdatum für".
        let text = ([page.title] + page.fields.flatMap {
            [$0.label, $0.placeholder, $0.section, $0.ariaLabel]
        }).compactMap { $0 }.joined(separator: " ")
        if text.unicodeScalars.contains(where: { $0.value > 0x7F && $0.properties.isAlphabetic }) {
            return false
        }
        return true
    }

    static func formatDate(_ iso: String, for field: FormField,
                           on page: FormPayload? = nil) -> String {
        let parts = iso.split(separator: "-").map(String.init)
        guard parts.count == 3, parts[0].count == 4 else { return iso }
        let (y, m, d) = (parts[0], parts[1], parts[2])

        // <input type="date"> and friends only accept ISO.
        if ["date", "month"].contains((field.inputType ?? "").lowercased()) { return iso }

        let hint = [field.placeholder, field.label, field.ariaLabel, field.name]
            .compactMap { $0 }.joined(separator: " ").lowercased()
        let sep = hint.contains(".") ? "." : (hint.contains("-") && !hint.contains("/") ? "-" : "/")

        if hint.contains("yyyy") || hint.contains("jjjj") || hint.contains("aaaa") {
            if let mm = hint.range(of: "mm"), let dd = hint.range(of: "dd") {
                if hint.contains("yyyy"), let yy = hint.range(of: "yyyy"),
                   yy.lowerBound < mm.lowerBound, yy.lowerBound < dd.lowerBound {
                    return [y, m, d].joined(separator: sep)
                }
                return dd.lowerBound < mm.lowerBound
                    ? [d, m, y].joined(separator: sep)
                    : [m, d, y].joined(separator: sep)
            }
        }
        // No hint on the field itself, so go by the page.
        return monthFirst(page)
            ? [m, d, y].joined(separator: sep)
            : [d, m, y].joined(separator: sep)
    }

    // MARK: - what Jev is allowed to see

    /// The page, described without a single value. Labels and headings only,
    /// and any text that matches something in the store is taken out.
    static func maskedState(_ payload: FormPayload, current: FormField,
                            data: StoreData) -> String {
        var lines = [String]()
        if let t = payload.title, !t.isEmpty { lines.append("The page is titled \"\(scrub(t, data))\".") }
        if let s = current.section, !s.isEmpty {
            lines.append("The empty field sits under the heading \"\(scrub(s, data))\".")
        }
        let cur = groupKey(current)
        for f in payload.fields {
            let label = [f.label, f.name, f.id].compactMap { $0 }.first { !$0.isEmpty } ?? "(unlabelled)"
            if f.current == true {
                lines.append("The cursor is in an empty field labelled \"\(scrub(label, data))\".")
                continue
            }
            let filled = !(f.value ?? "").trimmingCharacters(in: .whitespaces).isEmpty
            let same = (groupKey(f) == cur && !cur.isEmpty) ? "same block" : "elsewhere on the page"
            lines.append("There is \(filled ? "an already filled" : "another empty") "
                         + "field labelled \"\(scrub(label, data))\" (\(same)).")
        }
        return lines.joined(separator: "\n")
    }

    /// Takes every stored value and every stored name out of a piece of text.
    /// Belt and braces: labels should not contain them, but a heading might.
    static func scrub(_ text: String, _ data: StoreData) -> String {
        var out = text
        var secrets = data.allValues
        for p in data.people { secrets.append(contentsOf: p.names) }
        for s in secrets.sorted(by: { $0.count > $1.count }) where s.count >= 3 {
            out = out.replacingOccurrences(of: s, with: "someone", options: [.caseInsensitive])
        }
        return out
    }

    /// The list shown on the page: everybody, plus each labelled value they
    /// have, so "Nolan" and "Nolan · work" are both pickable.
    /// `page` puts the list in a sensible order: if the work email is already
    /// typed in, "Nolan · work" belongs near the top. Nothing is sent anywhere
    /// to work that out - the page is compared with the store here.
    static func profiles(_ data: StoreData, page: FormPayload? = nil) -> [Profile] {
        var out = [Profile]()
        for p in data.people {
            out.append(Profile(person: p.id, label: "", name: p.displayName))

            // Labels on LINKED values are the family's, so every person would
            // otherwise offer "home" and "work" and the list would be unusable.
            // Only a person's own labels say something about them.
            var count = [String: Int]()
            for list in p.fields.values {
                for v in list where !v.label.isEmpty && !v.linked {
                    count[v.label, default: 0] += 1
                }
            }
            for label in count.sorted(by: { ($0.value, $1.key) > ($1.value, $0.key) })
                .prefix(3).map(\.key) {
                out.append(Profile(person: p.id, label: label,
                                   name: "\(p.displayName) · \(label)"))
            }
        }

        guard let page else { return out }

        // Rank by what the page already shows.
        let labels = labelsAlreadyOnPage(page, data)
        var owner = [String: Int]()
        for f in page.fields {
            let v = (f.value ?? "").trimmingCharacters(in: .whitespaces).lowercased()
            guard v.count >= 4 else { continue }
            for p in data.people where p.fields.values.flatMap({ $0 })
                .contains(where: { $0.value.lowercased() == v }) {
                owner[p.id, default: 0] += 1
            }
        }
        return out.enumerated().sorted { a, b in
            func score(_ p: Profile) -> Int {
                (owner[p.person] ?? 0) * 2 + (p.label.isEmpty ? 0 : (labels[p.label] ?? 0) * 3)
            }
            let (sa, sb) = (score(a.element), score(b.element))
            return sa == sb ? a.offset < b.offset : sa > sb
        }.map(\.element)
    }

    /// Answer for EVERY empty field on the page at once, which is what the
    /// toolbar button does. Each one is worked out exactly as a single fill is,
    /// so the same rules about whose it is and which value apply.
    static func suggestAll(_ payload: FormPayload, data: StoreData, jevKey: String,
                           allowJev: Bool = true, limit: Int = 60) async -> FillAll {
        // A block that asks for a NAME belongs to a person. Fill one only when
        // it says who: either a name is typed into it, or it is the only such
        // block. Otherwise Traveler 2 and Traveler 3 quietly fill with whoever
        // Traveler 1 is - and pressing twice used to do exactly that, because
        // the first press made a name appear on the page.
        //
        // Contact, address and work sections carry no name, belong to the form
        // rather than to a traveler, and are always filled.
        var personBlocks = [String]()
        var namedBlocks = Set<String>()
        for f in payload.fields {
            let k = groupKey(f)
            guard !k.isEmpty else { continue }
            if let t = Fields.guessType(f).key, Fields.isName(t) {
                if !personBlocks.contains(k) { personBlocks.append(k) }
                let v = (f.value ?? "").trimmingCharacters(in: .whitespaces)
                if v.count >= 2, data.people.contains(where: { score($0, naming: v) >= 2 }) {
                    namedBlocks.insert(k)
                }
            }
        }
        var skipBlocks = Set(personBlocks).subtracting(namedBlocks)
        if namedBlocks.isEmpty, let first = personBlocks.first {
            skipBlocks.remove(first)                   // one block, no name: fine
        }

        let targets = payload.fields.enumerated()
            .filter { (_, f) in (f.value ?? "").trimmingCharacters(in: .whitespaces).isEmpty }
            .filter { (_, f) in !skipBlocks.contains(groupKey(f)) }
            .prefix(limit)
            .map(\.offset)
        guard !targets.isEmpty else { return FillAll() }

        var out = [FillItem]()
        await withTaskGroup(of: FillItem?.self) { group in
            for i in targets {
                group.addTask {
                    var one = payload
                    for j in one.fields.indices { one.fields[j].current = (j == i) ? true : nil }
                    let s = await suggest(one, data: data, jevKey: jevKey, allowJev: allowJev)
                    guard s.ok, let v = s.value else {
                        return FillItem(i: i, skipped: s.error ?? s.why ?? "no answer")
                    }
                    // Filling a whole form is not the place for a shaky guess: a
                    // site's own search box got a full name because a weak match
                    // was good enough. One field at a time can still be unsure;
                    // the page shows a list then.
                    guard (s.confidence ?? 0) >= 0.7 else {
                        return FillItem(i: i, type: s.type,
                                        confidence: s.confidence ?? 0,
                                        skipped: String(format: "only %.1f sure it is %@",
                                                        s.confidence ?? 0, s.type ?? "?"))
                    }
                    return FillItem(i: i, value: v, type: s.type, typeLabel: s.typeLabel,
                                    person: s.person, confidence: s.confidence ?? 0,
                                    unsure: s.unsure, alternatives: s.alternatives)
                }
            }
            for await item in group {
                if let item { out.append(item) }
            }
        }
        out.sort { $0.i < $1.i }
        return FillAll(results: out)
    }

    // MARK: - the answer

    static func suggest(_ payload: FormPayload, data: StoreData, jevKey: String,
                        allowJev: Bool = true) async -> Suggestion {
        guard let current = payload.fields.first(where: { $0.current == true }) else {
            return Suggestion(ok: false, error: "no field is marked current")
        }

        var type = Fields.guessType(current)
        if type.confidence < 0 {
            return Suggestion(ok: false, why: type.why, error: "not a field for personal details")
        }
        if type.key == nil, allowJev, !offline {
            // Ask about EVERY type, not a shortlist. A shortlist built from word
            // overlap once offered only "Known Traveler Number" for a field
            // labelled "Document identifier", because both contain "traveler" -
            // so that is what it answered. All of them is one call, ~350ms.
            let state = maskedState(payload, current: current, data: data)
            let qs = Dictionary(uniqueKeysWithValues: Fields.all.map {
                ($0.key, "Does this empty form field ask for \($0.question)?")
            })
            if let scores = try? await Jev.nouls(state: state, questions: qs, key: jevKey) {
                let ranked = scores.sorted { $0.value > $1.value }
                let top = ranked[0], next = ranked.count > 1 ? ranked[1].value : 0
                if top.value >= typeMin {
                    type = Fields.Guess(key: top.key,
                                        confidence: (top.value - next) >= margin ? 0.9 : 0.5,
                                        why: String(format: "jev: %@ %.2f (next %.2f)",
                                                    top.key, top.value, next))
                } else {
                    type = Fields.Guess(key: nil, confidence: top.value,
                                        why: String(format: "jev: nothing above %.2f (best %@ %.2f)",
                                                    typeMin, top.key, top.value))
                }
            }
        }

        guard let ftype = type.key else {
            return Suggestion(ok: false, why: type.why, error: "cannot tell what this field wants")
        }

        // Who first, then which of that person's values. Every value belongs to
        // a person now; an address shared by the family is a LINKED value on
        // each of them, so there is no separate household to special-case.
        let who = payload.person.map {
            PersonResult(id: $0, confidence: 1, why: "you picked them", others: [])
        } ?? resolvePerson(data, payload: payload, current: current)

        let mine = data.values(person: who.id, type: ftype)
        guard !mine.isEmpty else {
            let alts = await options(for: who.others, type: ftype, data: data,
                                     field: current, payload: payload,
                                     jevKey: jevKey, allowJev: allowJev)
            return Suggestion(ok: false, type: ftype, person: who.id,
                              why: "\(type.why); \(who.why)",
                              error: "nothing stored for \(who.id ?? "anyone") / \(Fields.label(ftype))",
                              alternatives: alts)
        }

        var pick = await chooseVariant(mine, type: ftype, field: current, payload: payload,
                                       data: data, jevKey: jevKey, allowJev: allowJev)
        // A chosen profile decides it - UNLESS the field names a different one
        // itself. Picking "Nolan · american" once put the AA number into the box
        // labelled SkyMiles; a box that says which it wants always wins.
        if let want = payload.variant, !want.isEmpty {
            let own = Set(Fields.haystack(current)
                .split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
            let namesItsOwn = mine.contains { v in
                !v.label.isEmpty && v.label != want && words(for: v.label).contains(where: own.contains)
            }
            if !namesItsOwn {
                let mineFirst = mine.filter { $0.label == want } + mine.filter { $0.label != want }
                pick = VariantChoice(ranked: mineFirst, sure: true, why: "you picked \(want)")
            } else {
                pick = VariantChoice(ranked: pick.ranked, sure: true,
                                     why: "\(pick.why); the field asks for its own")
            }
        }

        let personSure = who.confidence >= 0.6
        let unsure = !personSure || !pick.sure

        var alts = [Suggestion.Alternative]()
        if unsure {
            // Everything it could reasonably be, best guess first, so the page
            // can show the list instead of putting one of them in a form.
            let people: [String?] = personSure ? [who.id] : ([who.id] + who.others)
            for pid in people {
                alts += await options(for: [pid].compactMap { $0 }, type: ftype, data: data,
                                      field: current, payload: payload,
                                      jevKey: jevKey, allowJev: false,
                                      preRanked: pid == who.id ? pick.ranked : nil)
            }
        }
        alts = Array(alts.prefix(8))

        var best = pick.ranked.first?.value ?? mine[0].value
        if dateTypes.contains(ftype) { best = formatDate(best, for: current, on: payload) }

        return Suggestion(ok: true, value: best, type: ftype, typeLabel: Fields.label(ftype),
                          person: who.id, confidence: min(type.confidence, who.confidence),
                          why: "\(type.why); \(who.why); \(pick.why)",
                          unsure: unsure && alts.count > 1, alternatives: alts)
    }
}
