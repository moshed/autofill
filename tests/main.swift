// Runs the labelled cases straight against the Swift engine, with fake people.
// The keychain is never read or written here.
//
//   ./tests/run.sh            patterns + Jev
//   ./tests/run.sh --nojev    patterns only, free and offline
import Foundation

func field(_ label: String, name: String = "", value: String = "",
           section: String = "", autocomplete: String = "", placeholder: String = "",
           inputType: String = "", current: Bool = false) -> FormField {
    FormField(label: label, name: name, id: "", placeholder: placeholder,
              autocomplete: autocomplete.isEmpty ? nil : autocomplete,
              ariaLabel: nil, section: section.isEmpty ? nil : section,
              group: nil, value: value, current: current ? true : nil,
              inputType: inputType.isEmpty ? nil : inputType)
}

// Made-up people. Two rules when inventing one:
//  - at least 4 characters. A name shorter than that is ignored on the page on
//    purpose, so a 3-letter demo name silently fails every who-is-it test.
//  - not a substring of an ordinary word. "Sam" hid inside "same" and "Ruth"
//    inside "truth", and the leak check - which searches the whole prompt -
//    called both a leak.
let fake = StoreData(
    people: [
        Person(id: "nolan", aliases: ["Nolan", "Mo"],
               fields: ["given_name": [FieldValue(value: "Nolan")],
                        "family_name": [FieldValue(value: "Carter")],
                        "passport_number": [FieldValue(value: "M11111111")],
                        "dob": [FieldValue(value: "1901-01-01")],
                        "known_traveler": [FieldValue(value: "KT0001")],
                        "email": [FieldValue(label: "personal", value: "nolan@example.com"),
                                  FieldValue(label: "work", value: "nolan@acmecorp.com")]],
               isDefault: true),
        Person(id: "leon", aliases: ["Leon"],
               plain: ["given_name": "Leon", "family_name": "Carter",
                       "passport_number": "J22222222", "dob": "2012-02-02"]),
        Person(id: "freya", aliases: ["Freya", "Freya Rose"],
               plain: ["given_name": "Freya", "family_name": "Carter",
                        "passport_number": "C33333333", "dob": "2014-03-05"]),
    ],
    shared: [:])

/// Everything the family shares is a linked value on every person.
let familyAddress: [String: [FieldValue]] = [
    "address_line1": [FieldValue(label: "home", value: "1 Example Street", linked: true),
                      FieldValue(label: "work", value: "500 Trade Road", linked: true)],
    "city": [FieldValue(label: "home", value: "Monsey", linked: true),
             FieldValue(label: "work", value: "Brooklyn", linked: true)],
    "state": [FieldValue(value: "NY", linked: true)],
    "postal_code": [FieldValue(value: "10952", linked: true)],
    "country": [FieldValue(value: "United States", linked: true)],
]

// give every fake person the shared address
let fakeLinked: StoreData = {
    var d = fake
    for i in d.people.indices {
        for (k, v) in familyAddress { d.people[i].fields[k] = v }
    }
    return d
}()

struct Case { let name: String; let payload: FormPayload; let want: String }

let cases: [Case] = [
    Case(name: "passport, sibling first name Leon",
         payload: FormPayload(title: "Add traveler details", fields: [
            field("First name", name: "pax1_fn", value: "Leon"),
            field("Last name", name: "pax1_ln", value: "Carter"),
            field("Passport number", name: "pax1_ppt", current: true)]),
         want: "J22222222"),

    Case(name: "second block wins over the first",
         payload: FormPayload(title: "Passengers", fields: [
            field("First name", name: "pax1_fn", value: "Nolan"),
            field("Passport number", name: "pax1_ppt", value: "M11111111"),
            field("First name", name: "pax2_fn", value: "Leon"),
            field("Passport number", name: "pax2_ppt", current: true)]),
         want: "J22222222"),

    // Dates are stored ISO and written out the way the field asks.
    Case(name: "date of birth, no hint -> American order",
         payload: FormPayload(title: "Visa application", fields: [
            field("Given name", name: "g", value: "Freya"),
            field("Date of birth", name: "d", current: true)]),
         want: "03/05/2014"),

    Case(name: "date of birth into an <input type=date> stays ISO",
         payload: FormPayload(title: "Visa application", fields: [
            field("Given name", name: "g", value: "Freya"),
            field("Date of birth", name: "d", inputType: "date", current: true)]),
         want: "2014-03-05"),

    Case(name: "placeholder says DD/MM/YYYY",
         payload: FormPayload(title: "Booking", fields: [
            field("Given name", name: "g", value: "Freya"),
            field("Date of birth", name: "d", placeholder: "DD/MM/YYYY", current: true)]),
         want: "05/03/2014"),

    Case(name: "placeholder says MM/DD/YYYY on the same date",
         payload: FormPayload(title: "Booking", fields: [
            field("Given name", name: "g", value: "Nolan"),
            field("Date of birth", name: "d", placeholder: "MM/DD/YYYY", current: true)]),
         want: "01/01/1901"),

    Case(name: "placeholder says YYYY-MM-DD",
         payload: FormPayload(title: "Booking", fields: [
            field("Given name", name: "g", value: "Leon"),
            field("Date of birth", name: "d", placeholder: "YYYY-MM-DD", current: true)]),
         want: "2012-02-02"),

    // --- several values of the same kind ------------------------------------

    Case(name: "the field says Work, so the work address",
         payload: FormPayload(title: "Supplier form", fields: [
            field("Work email", name: "we", current: true)]),
         want: "nolan@acmecorp.com"),

    Case(name: "the field says Personal",
         payload: FormPayload(title: "Supplier form", fields: [
            field("Personal email", name: "pe", current: true)]),
         want: "nolan@example.com"),

    Case(name: "a Company field filled in elsewhere still means work",
         payload: FormPayload(title: "Order", fields: [
            field("Company", name: "co", value: "Acme"),
            field("Business e-mail", name: "e", current: true)]),
         want: "nolan@acmecorp.com"),

    Case(name: "a bare Email field takes the top one",
         payload: FormPayload(title: "Newsletter", fields: [
            field("Email address", name: "email", current: true)]),
         want: "nolan@example.com"),

    // --- what is ALREADY on the page decides which one ------------------------

    Case(name: "work email already typed in, so the work street",
         payload: FormPayload(title: "Order", fields: [
            field("Email", name: "e", value: "nolan@acmecorp.com"),
            field("Street address", name: "s", current: true)]),
         want: "500 Trade Road"),

    Case(name: "personal email already typed in, so the home street",
         payload: FormPayload(title: "Order", fields: [
            field("Email", name: "e", value: "nolan@example.com"),
            field("Street address", name: "s", current: true)]),
         want: "1 Example Street"),

    Case(name: "work email already typed in, so the work city too",
         payload: FormPayload(title: "Order", fields: [
            field("Email", name: "e", value: "nolan@acmecorp.com"),
            field("Town", name: "c", current: true)]),
         want: "Brooklyn"),

    Case(name: "a value on the page says whose form it is",
         payload: FormPayload(title: "Order", fields: [
            field("Contact", name: "c", value: "J22222222"),
            field("Date of birth", name: "d", current: true)]),
         want: "02/02/2012"),

    Case(name: "autocomplete attribute beats everything",
         payload: FormPayload(title: "Checkout", fields: [
            field("Naam", name: "x1", autocomplete: "given-name", current: true)]),
         want: "Nolan"),

    Case(name: "numbered ids group the block when labels are vague",
         payload: FormPayload(title: "Booking", fields: [
            field("Name", name: "traveler2_name", value: "Freya Carter"),
            field("Number", name: "traveler2_passport", current: true)]),
         want: "C33333333"),

    Case(name: "known traveler number for the adult",
         payload: FormPayload(title: "Check in", fields: [
            field("Passenger name", name: "n", value: "Nolan Carter"),
            field("Known Traveler Number", name: "ktn", current: true)]),
         want: "KT0001"),

    Case(name: "full name is built from the parts",
         payload: FormPayload(title: "Form", fields: [
            field("First name", name: "pax1_fn", value: "Leon"),
            field("Name on passport", name: "pax1_full", current: true)]),
         want: "Leon Carter"),

    Case(name: "vague label, a weak pattern still names it",
         payload: FormPayload(title: "Israeli entry form", fields: [
            field("Given name", name: "a", value: "Leon"),
            field("Travel document identifier", name: "b", current: true)]),
         want: "J22222222"),

    Case(name: "the traveler's name is a heading, not a filled field",
         payload: FormPayload(title: "Seat selection", fields: [
            field("Passport number", name: "p", section: "Traveler 2 - Freya Carter",
                  current: true)]),
         want: "C33333333"),

    // --- these two have no pattern to lean on: Jev has to carry them ---------

    Case(name: "label in French, no pattern matches",
         payload: FormPayload(title: "Formulaire", fields: [
            field("Prenom", name: "a", value: "Leon"),
            field("Numero du document de voyage", name: "b", current: true)]),
         want: "J22222222"),

    Case(name: "odd wording for a birth date",
         payload: FormPayload(title: "Entry form", fields: [
            field("Given name", name: "a", value: "Leon"),
            field("On which day were you brought into the world", name: "b", current: true)]),
         want: "02/02/2012"),
]

// --- the guarantee: nothing stored may ever appear in a Jev prompt ------------

func leakCheck() -> [String] {
    var bad = [String]()
    for c in cases {
        guard let cur = c.payload.fields.first(where: { $0.current == true }) else { continue }
        let state = Match.maskedState(c.payload, current: cur, data: fakeLinked)
        for secret in fakeLinked.allValues where state.localizedCaseInsensitiveContains(secret) {
            bad.append("\(c.name): prompt contains \(secret)")
        }
        for p in fakeLinked.people {
            for n in p.names where n.count >= 3 && state.localizedCaseInsensitiveContains(n) {
                bad.append("\(c.name): prompt contains the name \(n)")
            }
        }
    }
    return bad
}

// --- the paste importer ------------------------------------------------------

// Written the way notes actually get written: colons, dashes, and plenty of
// lines with no punctuation at all.
let pasted = """
Nolan
Passport: M11111111
Email  nolan@example.com
Mobile: +1 845 555 0101
Leon
Passport no - J22222222
Born on: 2012-02-02
expires 04/02/2031
KTN 998877
issued by United States
Address: 1 Example Street
Zip  10952
"""

// (label, expected type, expected person)  nil person means the household
let wantRows: [(String, String, String?)] = [
    ("Passport", "passport_number", "nolan"),
    ("Email", "email", "nolan"),
    ("Mobile", "phone", "nolan"),
    ("Passport no", "passport_number", "leon"),
    ("Born on", "dob", "leon"),
    ("expires", "passport_expiry", "leon"),
    ("KTN", "known_traveler", "leon"),
    ("issued by", "passport_country", "leon"),
    // These land on whoever the block is about; being LINKED is what spreads
    // them to everyone else, not which person they were typed under.
    ("Address", "address_line1", "leon"),
    ("Zip", "postal_code", "leon"),
]

func checkImporter() -> Int {
    let rows = Importer.parse(pasted, people: fakeLinked.people)
    var bad = 0
    print("\npaste importer")
    guard rows.count == wantRows.count else {
        print("  WRONG  \(rows.count) rows, wanted \(wantRows.count)")
        return 1
    }
    for (row, want) in zip(rows, wantRows) {
        let person = row.personID
        let ok = row.rawLabel == want.0 && row.type == want.1 && person == want.2
        if !ok { bad += 1 }
        let label = row.rawLabel.padding(toLength: 14, withPad: " ", startingAt: 0)
        print("  \(ok ? "ok   " : "WRONG") \(label) \(row.type ?? "nil") "
              + "\(person ?? "household")  \(row.masked)")
        if !ok { print("        wanted \(want.1) / \(want.2 ?? "household")") }
    }
    return bad
}

// --- boxes that must never be touched ---------------------------------------

let neverCases: [(String, FormPayload)] = [
    ("a site's search box", FormPayload(title: "Docs", fields: [
        field("Search field", name: "tnb-google-search-input", current: true)])),
    ("a captcha", FormPayload(title: "Sign up", fields: [
        field("Enter the captcha", name: "captcha", current: true)])),
    ("a coupon code", FormPayload(title: "Checkout", fields: [
        field("Promo code", name: "promo", current: true)])),
    ("a one-time code", FormPayload(title: "Sign in", fields: [
        field("One-time passcode", name: "otp", current: true)])),
    ("a comment box", FormPayload(title: "Blog", fields: [
        field("Comment", name: "comment", current: true)])),

    // The same boxes in other languages. A French search box used to get through
    // this list and was only spared by the confidence bar.
    ("a French search box", FormPayload(title: "Demande de visa", fields: [
        field("Rechercher sur le site", name: "recherche", current: true)])),
    ("a Spanish search box", FormPayload(title: "Solicitud", fields: [
        field("Buscar en el sitio", name: "buscar", current: true)])),
    ("a German search box", FormPayload(title: "Antrag", fields: [
        field("Suche", name: "suche", current: true)])),
    ("a Chinese search box", FormPayload(title: "申请", fields: [
        field("搜索", name: "ss", current: true)])),
    ("a Hebrew search box", FormPayload(title: "בקשה", fields: [
        field("חיפוש באתר", name: "hipus", current: true)])),
    ("a Japanese verification code", FormPayload(title: "ログイン", fields: [
        field("確認コード", name: "code", current: true)])),
    ("a French comment box", FormPayload(title: "Contact", fields: [
        field("Commentaire", name: "c", current: true)])),
    ("a German credit card", FormPayload(title: "Kasse", fields: [
        field("Kreditkarte", name: "kk", current: true)])),
]


// --- real pages from the web ---------------------------------------------
//
// Field shapes taken off five public form-filling test pages with
// tools/webtest/extract.py, then saved in tests/pages. The expectations were
// written by hand from the label printed on the page, NOT from what Clerk
// answers, so a wrong answer stays wrong.
//
// Patterns only. These pages are in plain English, so anything that needs the
// AI here is a gap in the vocabulary worth seeing.

struct PageCase: Decodable {
    let name: String
    let url: String
    let title: String
    let fields: [FormField]
    let expect: [String: String]
}

func checkPages() async -> Int {
    var bad = 0
    let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("pages")
    let files = ((try? FileManager.default.contentsOfDirectory(atPath: here.path)) ?? [])
        .filter { $0.hasSuffix(".json") }.sorted()
    guard !files.isEmpty else { return 0 }

    print("\nreal pages from the web")
    for file in files {
        guard let blob = try? Data(contentsOf: here.appendingPathComponent(file)),
              let page = try? JSONDecoder().decode(PageCase.self, from: blob) else {
            print("  could not read \(file)"); bad += 1; continue
        }
        var wrong = [String]()
        for (idx, want) in page.expect.sorted(by: { Int($0.key)! < Int($1.key)! }) {
            guard let i = Int(idx), i < page.fields.count else { continue }
            var fields = page.fields
            fields[i].current = true
            let payload = FormPayload(url: page.url, title: page.title, fields: fields)
            let got = await Match.suggest(payload, data: fakeLinked, jevKey: "", allowJev: false)
            let label = fields[i].label ?? fields[i].name ?? "?"
            if want == "refused" {
                if got.value != nil { wrong.append("\(label): filled, must not be") }
            } else if got.type != want {
                wrong.append("\(label): \(got.type ?? got.error ?? "nothing"), wanted \(want)")
            }
        }
        let n = page.name.padding(toLength: 18, withPad: " ", startingAt: 0)
        print("  \(wrong.isEmpty ? "ok   " : "WRONG") \(n) \(page.expect.count - wrong.count) of \(page.expect.count) right")
        for w in wrong { print("        \(w)") }
        bad += wrong.count
    }
    return bad
}


// --- dates in the app, dates on a form -----------------------------------
//
// Stored ISO. Shown and typed American, because that is what Moshe reads.
// What a FORM gets is decided separately, by the page - see the fill cases.

/// Hebrew "מדינה" is country AND state. The fuller phrase must win.
func checkHebrewStateVsCountry() -> Int {
    var bad = 0
    print("\nstate or country")
    let cases: [(String, String)] = [
        ("מדינה בארה\u{05F4}ב", "state"),
        ("ארץ מגורים", "country"),
        ("ארץ", "country"),
        ("State / Province", "state"),
        ("Country", "country"),
    ]
    for (label, want) in cases {
        let got = Fields.guessType(FormField(label: label, name: "x")).key
        let ok = got == want
        if !ok { bad += 1 }
        print("  \(ok ? "ok   " : "WRONG") \(label.padding(toLength: 20, withPad: " ", startingAt: 0)) -> \(got ?? "nothing")")
    }
    return bad
}

func checkDates() -> Int {
    var bad = 0
    print("\ndates in the app")
    let shown: [(String, String)] = [
        ("2031-06-22", "06/22/2031"),
        ("2028-03-27", "03/27/2028"),
        ("", ""),
        ("06/22", "06/22"),                 // half typed, handed back untouched
    ]
    for (iso, want) in shown {
        let got = Dates.display(iso)
        let ok = got == want
        if !ok { bad += 1 }
        print("  \(ok ? "ok   " : "WRONG") show \(iso.isEmpty ? "(empty)" : iso) -> \(got)")
    }
    let typed: [(String, String?)] = [
        ("06/22/2031", "2031-06-22"),
        ("6/22/2031", "2031-06-22"),
        ("06-22-2031", "2031-06-22"),
        ("2031-06-22", "2031-06-22"),       // pasted ISO
        ("", ""),
        ("06/2", nil),                      // still typing: save nothing
        ("22/06/2031", nil),                // day first is not what he types
        ("hello", nil),
    ]
    for (text, want) in typed {
        let got = Dates.store(text)
        let ok = got == want
        if !ok { bad += 1 }
        print("  \(ok ? "ok   " : "WRONG") type \(text.isEmpty ? "(empty)" : text) -> \(got ?? "nothing saved")")
    }
    return bad
}


// --- renaming and removing a field ---------------------------------------

func checkFieldEditing() -> Int {
    var bad = 0
    print("\nrenaming and removing a field")

    // Renaming changes the NAME, never the key, so the value survives.
    var d = fakeLinked
    d.fieldLabels["passport_number"] = "Passport no."
    Fields.register(d.customFields, renamed: d.fieldLabels)
    let renamed = Fields.all.first { $0.key == "passport_number" }?.label ?? "?"
    let kept = d.people.first(where: { $0.id == "leon" })?.text("passport_number") ?? ""
    let ok1 = renamed == "Passport no." && kept == "J22222222"
    if !ok1 { bad += 1 }
    print("  \(ok1 ? "ok   " : "WRONG") renamed, value kept -> \(renamed) / \(kept)")

    // A renamed field still fills.
    Fields.register(d.customFields, renamed: d.fieldLabels)
    let guessed = Fields.guessType(FormField(label: "Passport number", name: "p")).key
    let ok2 = guessed == "passport_number"
    if !ok2 { bad += 1 }
    print("  \(ok2 ? "ok   " : "WRONG") a renamed field still matches -> \(guessed ?? "nothing")")

    // Removing clears it for everybody and takes it off the screen.
    d.forget("passport_number")
    let anyLeft = d.people.contains { !($0.values("passport_number").isEmpty) }
    let hidden = d.hiddenFields.contains("passport_number")
    let ok3 = !anyLeft && hidden
    if !ok3 { bad += 1 }
    print("  \(ok3 ? "ok   " : "WRONG") removed everywhere and hidden -> values left: \(anyLeft), hidden: \(hidden)")

    Fields.register([], renamed: [:])          // put the vocabulary back
    return bad
}

func checkNeverFill() async -> Int {
    var bad = 0
    print("\nnever filled")
    for (name, payload) in neverCases {
        let got = await Match.suggest(payload, data: fakeLinked, jevKey: "", allowJev: false)
        // "left alone" is not enough. A field nothing matched is ALSO left
        // alone, so this passed for months while the Hebrew and Chinese
        // patterns were being deleted before they were ever tried - the
        // haystack stripped every non-ASCII letter. Demand the RULE.
        let byRule = (got.why ?? "").contains("not a personal detail")
        let ok = !got.ok && byRule
        if !ok { bad += 1 }
        let n = name.padding(toLength: 44, withPad: " ", startingAt: 0)
        print("  \(ok ? "ok   " : "WRONG") \(n) -> \(byRule ? "refused by the rule" : (got.why ?? "left alone, but NOT by the rule"))")
    }
    return bad
}

// --- when it is not sure, it must OFFER rather than decide -------------------

struct OfferCase { let name: String; let payload: FormPayload; let want: [String] }

let offers: [OfferCase] = [
    OfferCase(name: "bare Email, two addresses stored",
              payload: FormPayload(title: "Newsletter", fields: [
                field("Email", name: "e", current: true)]),
              want: ["Nolan · Personal", "Nolan · Work"]),

    // Two people named, nothing saying which block the cursor is in.
    OfferCase(name: "two travelers, no blocks to tell them apart",
              payload: FormPayload(title: "Visa", fields: [
                field("First name", name: "a", value: "Nolan"),
                field("First name", name: "b", value: "Leon"),
                field("Passport number", name: "p", current: true)]),
              want: ["Nolan", "Leon"]),
]

/// Cases that must be answered outright, with no list in the way.
let noOffer: [(String, FormPayload)] = [
    ("the field says Work email", FormPayload(title: "Supplier form", fields: [
        field("Work email", name: "we", current: true)])),
    ("a plain sign-up form", FormPayload(title: "Sign up", fields: [
        field("First name", name: "f", current: true)])),
    ("Leon is named right there", FormPayload(title: "Check in", fields: [
        field("First name", name: "pax1_fn", value: "Leon"),
        field("Passport number", name: "pax1_ppt", current: true)])),
]

func checkNoOffers() async -> Int {
    var bad = 0
    print("\nanswered outright, no list")
    for (name, payload) in noOffer {
        let got = await Match.suggest(payload, data: fakeLinked, jevKey: "", allowJev: false)
        let ok = got.ok && !got.unsure
        if !ok { bad += 1 }
        let n = name.padding(toLength: 44, withPad: " ", startingAt: 0)
        print("  \(ok ? "ok   " : "WRONG") \(n) -> \(got.value ?? "nil")\(got.unsure ? "  (put up a list)" : "")")
    }
    return bad
}

func checkOffers() async -> Int {
    var bad = 0
    print("\nwhen unsure, it offers")
    for c in offers {
        let got = await Match.suggest(c.payload, data: fakeLinked, jevKey: "", allowJev: false)
        let names = got.alternatives.map(\.name)
        let ok = got.unsure && c.want.allSatisfy(names.contains)
        if !ok { bad += 1 }
        let n = c.name.padding(toLength: 44, withPad: " ", startingAt: 0)
        print("  \(ok ? "ok   " : "WRONG") \(n) -> \(names.joined(separator: ", "))")
        if !ok { print("        wanted unsure with \(c.want.joined(separator: ", "))")
                 print("        got ok=\(got.ok) unsure=\(got.unsure) why=\(got.why ?? "-") error=\(got.error ?? "-")") }
    }
    return bad
}

// --- a linked value belongs to everybody -------------------------------------

func checkLinking() -> Int {
    var bad = 0
    print("\nlinked values")

    var d = fakeLinked
    // change the family's home street on ONE person
    if let i = d.people.firstIndex(where: { $0.id == "nolan" }) {
        var list = d.people[i].values("address_line1")
        if let j = list.firstIndex(where: { $0.label == "home" }) {
            list[j].value = "9 New Road"
            d.people[i].fields["address_line1"] = list
        }
    }
    d.propagateLinked(from: "nolan")

    for id in ["leon", "freya"] {
        let got = d.person(id)?.values("address_line1").first(where: { $0.label == "home" })?.value
        let ok = got == "9 New Road"
        if !ok { bad += 1 }
        print("  \(ok ? "ok   " : "WRONG") \(id) followed the change -> \(got ?? "nil")")
    }

    // an UNlinked value must not spread
    var e = fakeLinked
    if let i = e.people.firstIndex(where: { $0.id == "nolan" }) {
        e.people[i].fields["email"] = [FieldValue(label: "personal", value: "private@example.com")]
    }
    e.propagateLinked(from: "nolan")
    let judahEmail = e.person("leon")?.text("email")
    let ok = judahEmail != "private@example.com"
    if !ok { bad += 1 }
    print("  \(ok ? "ok   " : "WRONG") an unlinked email did not spread -> \(judahEmail ?? "none")")
    // Following ONE person must not drag everybody else in. "Follow Nolan" on
    // Leon is about Leon; Freya never asked for anything.
    var f = fake                                   // nobody linked to start with
    if let j = f.people.firstIndex(where: { $0.id == "leon" }) {
        f.people[j].fields["email"] = [FieldValue(label: "", value: "nolan@example.com",
                                                  linked: true, owner: "nolan")]
    }
    f.propagateLinked(from: "leon")
    let freyaGot = f.people.first(where: { $0.id == "freya" })?.values("email") ?? []
    let okOnlyMe = freyaGot.isEmpty
    if !okOnlyMe { bad += 1 }
    print("  \(okOnlyMe ? "ok   " : "WRONG") following one person left the others alone -> \(freyaGot.map(\.value).joined(separator: ", ").isEmpty ? "nothing" : freyaGot.map(\.value).joined(separator: ", "))")

    // "Share mine with everyone" is the deliberate way to hand it round, and it
    // must still work.
    var sh = fake
    sh.share("email", label: "", value: "nolan@example.com", owner: "nolan")
    sh.propagateLinked(from: "nolan")
    let everyone = sh.people.allSatisfy { p in
        p.values("email").contains { $0.value == "nolan@example.com" && $0.owner == "nolan" }
    }
    if !everyone { bad += 1 }
    print("  \(everyone ? "ok   " : "WRONG") sharing on purpose reached everybody -> \(everyone)")

    // The OWNER's copy wins, whoever was edited last. Without that, an echo of
    // a shared value could quietly overwrite the real one.
    var o = fakeLinked
    for i in o.people.indices {
        for (t, list) in o.people[i].fields {
            o.people[i].fields[t] = list.map { v in
                var x = v
                if x.linked { x.owner = "nolan" }
                return x
            }
        }
    }
    if let j = o.people.firstIndex(where: { $0.id == "leon" }) {
        var list = o.people[j].values("address_line1")
        if let k = list.firstIndex(where: { $0.label == "home" }) {
            list[k].value = "typed on the wrong person"
            o.people[j].fields["address_line1"] = list
        }
    }
    o.propagateLinked(from: "leon")
    let kept = o.people.first(where: { $0.id == "nolan" })?
        .values("address_line1").first(where: { $0.label == "home" })?.value ?? "?"
    let okOwner = kept != "typed on the wrong person"
    if !okOwner { bad += 1 }
    print("  \(okOwner ? "ok   " : "WRONG") an echo did not overwrite the owner -> \(kept)")

    return bad
}

// --- run ---------------------------------------------------------------------

let allowJev = !CommandLine.arguments.contains("--nojev")
let key = allowJev ? Store.jevKey() : ""
let sema = DispatchSemaphore(value: 0)
var failures = 0

Task {
    let leaks = leakCheck()
    if leaks.isEmpty {
        print("leak check: no stored value or name reaches a Jev prompt\n")
    } else {
        failures += leaks.count
        for l in leaks { print("LEAK  \(l)") }
        print("")
    }

    for c in cases {
        let got = await Match.suggest(c.payload, data: fakeLinked, jevKey: key, allowJev: allowJev)
        let ok = got.value == c.want
        if !ok { failures += 1 }
        let name = c.name.padding(toLength: 50, withPad: " ", startingAt: 0)
        print("\(ok ? "ok   " : "WRONG") \(name) -> \(got.value ?? "nil")")
        if !ok { print("      wanted \(c.want)   why: \(got.why ?? got.error ?? "")") }
    }
    failures += checkImporter()
    failures += await checkOffers()
    failures += await checkNoOffers()
    failures += checkLinking()
    failures += await checkNeverFill()
    failures += await checkPages()
    failures += checkHebrewStateVsCountry()
    failures += checkDates()
    failures += checkFieldEditing()
    print("\n\(failures == 0 ? "all good" : "\(failures) failures")")
    sema.signal()
}
sema.wait()
exit(failures == 0 ? 0 : 1)
