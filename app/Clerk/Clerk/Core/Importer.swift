import Foundation

/// Turns a block of pasted text into rows to check before anything is saved.
///
/// Pass 1 splits lines into a label and a value here, on the Mac, and names as
/// many as it can from patterns alone. Pass 2 hands whatever is left to Jev, one
/// line at a time - and that is the ONE place text ever leaves the Mac. Pressing
/// "Extract with AI" is the consent; there is no switch, because filling a form
/// never sends anything at all.

struct ImportRow: Identifiable, Hashable {
    let id = UUID()
    var rawLabel: String
    var value: String
    var type: String?
    /// "work", "personal" - which of several values of this type it is
    var variant: String = ""
    var personID: String?
    var include: Bool = true
    var sure: Bool = true
    var why: String = ""

    var masked: String {
        guard value.count > 2 else { return value }
        return String(value.first!) + String(repeating: "•", count: value.count - 2)
            + String(value.last!)
    }
}

enum Importer {
    /// Separators people actually paste: "Passport: X", "Passport - X",
    /// "Passport = X", a tab, or two or more spaces.
    private static let separators = [":", " - ", " – ", "=", "\t"]

    /// Pass 1, always local. A line that is only a name starts a person's block.
    static func parse(_ text: String, people: [Person]) -> [ImportRow] {
        var rows = [ImportRow]()
        var currentPerson = people.first(where: \.isDefault)?.id ?? people.first?.id

        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            var (label, value) = split(line)
            // Still nothing? Try reading the first few words as a label. That is
            // what turns "issued by United States" into passport country =
            // United States, with no digit anywhere to split on.
            if value.isEmpty, let (l, v) = splitByLeadingLabel(line) {
                label = l
                value = v
            }

            if value.isEmpty {
                // A bare line naming someone we know switches the block.
                if let p = people.max(by: { score($0, label) < score($1, label) }),
                   score(p, label) >= 3 {
                    currentPerson = p.id
                    continue
                }
                // A bare line we cannot read is still offered, marked unsure.
                rows.append(ImportRow(rawLabel: "", value: label, personID: currentPerson,
                                      include: false, sure: false,
                                      why: "no label on this line"))
                continue
            }

            // "Leon passport: X" - a name and a field on one line.
            var person = currentPerson
            for p in people where score(p, label) >= 2 { person = p.id }

            var row = ImportRow(rawLabel: label, value: value,
                                variant: variantIn(label), personID: person)
            let guess = Fields.guessType(FormField(label: label))
            if let k = guess.key {
                row.type = k
                row.why = guess.why
            } else if let k = typeFromShape(value) {
                row.type = k
                row.why = "the shape of the value, read on this Mac"
            } else {
                row.sure = false
                row.why = guess.why
            }
            rows.append(row)
        }
        return rows
    }

    private static func score(_ p: Person, _ text: String) -> Int {
        Match.score(p, naming: text)
    }

    /// Try the first word, then the first two, then three, as a field label.
    private static func splitByLeadingLabel(_ line: String) -> (String, String)? {
        let words = line.split(separator: " ").map(String.init)
        guard words.count >= 2 else { return nil }
        // Shortest first: "issued by" is the label, "United States" the value.
        // Longest first swallowed "United" into the label.
        for n in 1...min(3, words.count - 1) {
            let label = words.prefix(n).joined(separator: " ")
            if Fields.guessType(FormField(label: label)).key != nil {
                return (label, words.dropFirst(n).joined(separator: " "))
            }
        }
        return nil
    }

    private static func split(_ line: String) -> (String, String) {
        for sep in separators {
            if let r = line.range(of: sep) {
                return (String(line[..<r.lowerBound]).trimmingCharacters(in: .whitespaces),
                        String(line[r.upperBound...]).trimmingCharacters(in: .whitespaces))
            }
        }
        if let r = line.range(of: "  +", options: .regularExpression) {
            return (String(line[..<r.lowerBound]).trimmingCharacters(in: .whitespaces),
                    String(line[r.upperBound...]).trimmingCharacters(in: .whitespaces))
        }
        // No punctuation at all - "expires 04/02/2031", "KTN 998877",
        // "born 3 March 2014". People write like this and the first pass used to
        // give up on every one of them. A few words, then something with a digit
        // in it, reads as a label and a value.
        if let m = line.range(of: #"^[A-Za-z][A-Za-z'./-]*( [A-Za-z'./-]+){0,2} (?=.*\d)"#,
                              options: .regularExpression) {
            let label = String(line[m]).trimmingCharacters(in: .whitespaces)
            let value = String(line[m.upperBound...]).trimmingCharacters(in: .whitespaces)
            if !value.isEmpty { return (label, value) }
        }
        return (line, "")
    }

    /// Named from the value's shape alone, in code. Used when the label told us
    /// nothing, so an unlabelled value never has to go anywhere.
    static func typeFromShape(_ v: String) -> String? {
        let t = v.trimmingCharacters(in: .whitespaces)
        if t.contains("@"), t.contains("."), !t.contains(" ") { return "email" }
        if t.range(of: #"^https?://"#, options: .regularExpression) != nil { return "website" }
        if t.range(of: #"^\+?[\d\s().-]{9,}$"#, options: .regularExpression) != nil,
           t.filter(\.isNumber).count >= 9 { return "phone" }
        if t.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil { return "dob" }
        if t.range(of: #"^\d{5}(-\d{4})?$"#, options: .regularExpression) != nil { return "postal_code" }
        return nil
    }

    /// Pass 2. Ask Jev about the rows pass 1 could not name, one line at a time.
    /// It is given the line as pasted and can also say whose it is.
    /// A line that must never be sent anywhere, whatever the button says.
    ///
    /// The paste importer is the ONE place a value leaves the Mac, and that was
    /// fine while it was names and passport numbers. A card number is different:
    /// nobody should have to remember not to press the button. So a line that
    /// looks like a payment card, a routing number or a social security number
    /// is kept here and sorted by the patterns alone.
    static func sensitive(_ row: ImportRow) -> Bool {
        let label = row.rawLabel.lowercased()
        for word in ["card", "cvv", "cvc", "csc", "routing", "iban", "sort code",
                     "account number", "ssn", "social security", "aba"]
        where label.contains(word) { return true }

        let digits = row.value.filter(\.isNumber)
        if (13...19).contains(digits.count), luhn(digits) { return true }   // a card
        if digits.count == 9, aba(digits) { return true }                   // a routing number
        return false
    }

    /// The check digit every payment card carries.
    private static func luhn(_ digits: String) -> Bool {
        var sum = 0
        for (i, c) in digits.reversed().enumerated() {
            guard let d = c.wholeNumberValue else { return false }
            if i % 2 == 1 {
                let x = d * 2
                sum += x > 9 ? x - 9 : x
            } else {
                sum += d
            }
        }
        return sum % 10 == 0
    }

    /// The check digit a US routing number carries.
    private static func aba(_ digits: String) -> Bool {
        let d = digits.compactMap(\.wholeNumberValue)
        guard d.count == 9 else { return false }
        let total = 3 * (d[0] + d[3] + d[6]) + 7 * (d[1] + d[4] + d[7]) + (d[2] + d[5] + d[8])
        return total % 10 == 0
    }

    static func classifyLeftovers(_ rows: [ImportRow], people: [Person],
                                  key: String) async -> [ImportRow] {
        let todo = rows.enumerated()
            .filter { $0.element.type == nil && !sensitive($0.element) }
        guard !todo.isEmpty, !Match.offline else { return rows }

        var out = rows
        await withTaskGroup(of: (Int, String?, Double, String?)?.self) { group in
            for (i, row) in todo {
                group.addTask {
                    let line = row.rawLabel.isEmpty
                        ? row.value : "\(row.rawLabel): \(row.value)"
                    let state = "Someone is filling in a personal details form for a family. "
                        + "One line of their notes reads: \"\(line)\"."

                    var qs = Dictionary(uniqueKeysWithValues: Fields.all.map {
                        ("t_" + $0.key, "Does this line hold \($0.question)?")
                    })
                    for p in people {
                        qs["p_" + p.id] = "Is this line about \(p.displayName)?"
                    }
                    guard let scores = try? await Jev.nouls(state: state, questions: qs, key: key)
                    else { return nil }

                    let types = scores.filter { $0.key.hasPrefix("t_") }
                        .sorted { $0.value > $1.value }
                    guard let top = types.first, top.value >= Match.typeMin else { return nil }
                    let runner = types.count > 1 ? types[1].value : 0

                    var person: String?
                    let ps = scores.filter { $0.key.hasPrefix("p_") }
                        .sorted { $0.value > $1.value }
                    if let best = ps.first, best.value >= Match.typeMin,
                       best.value - (ps.count > 1 ? ps[1].value : 0) >= Match.margin {
                        person = String(best.key.dropFirst(2))
                    }
                    return (i, String(top.key.dropFirst(2)), top.value - runner, person)
                }
            }
            for await r in group {
                guard let (i, type, gap, person) = r, let type else { continue }
                out[i].type = type
                if let person { out[i].personID = person }
                // A clear winner is safe to tick; a close call is surfaced.
                out[i].sure = gap >= Match.margin
                out[i].include = true
                out[i].why = String(format: "AI read the line: %@ (gap %.2f)", type, gap)
            }
        }
        return out
    }

    /// Words in a pasted label that say WHICH value it is, rather than what
    /// kind: "Work email" is an email, labelled work.
    static func variantIn(_ label: String) -> String {
        let l = label.lowercased()
        for group in Match.variantWords {
            for w in group where l.contains(w) { return group[0] }
        }
        return ""
    }

    /// Writes the ticked rows into the store. A second value of the same kind is
    /// ADDED, not swapped in, so a work address does not wipe a personal one -
    /// unless it carries no label and one like it is already there.
    static func apply(_ rows: [ImportRow], to data: inout StoreData) -> Int {
        var n = 0
        for row in rows where row.include {
            guard let type = row.type, !row.value.isEmpty else { continue }
            // An address or a company is the family's by default, so it is
            // linked; the person it lands on is only where it is shown first.
            let incoming = FieldValue(label: row.variant, value: row.value,
                                      linked: Fields.isShared(type))
            let pid = row.personID ?? data.defaultPerson?.id
            if let pid, let idx = data.people.firstIndex(where: { $0.id == pid }) {
                data.people[idx].fields[type] = merge(data.people[idx].values(type), incoming)
                n += 1
            }
        }
        return n
    }

    private static func merge(_ existing: [FieldValue], _ incoming: FieldValue) -> [FieldValue] {
        var out = existing
        if let i = out.firstIndex(where: { $0.value == incoming.value }) {
            out[i] = incoming                       // same value, maybe a label now
        } else if let i = out.firstIndex(where: { $0.label == incoming.label }) {
            out[i] = incoming                       // same label, new value
        } else {
            out.append(incoming)
        }
        return out
    }
}
