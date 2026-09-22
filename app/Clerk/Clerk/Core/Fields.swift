import Foundation

/// The vocabulary of things a form field can be asking for, and the pattern
/// classifier that names one. Patterns are exact and free; Jev is asked only
/// about a field the patterns cannot settle.
struct FieldType: Identifiable {
    let key: String
    let label: String        // shown to Nolan
    let question: String     // the tail of the yes/no question Jev is asked
    let strong: [String]     // tried first
    let weak: [String]       // tried only when no strong pattern matched anything
    var shared = false       // the family's by default, so a new one starts linked
    var isName = false       // its value names the person a block is about
    var group = "Other"      // the heading it sits under in the app
    /// Worked out from other fields, so it is filled on a form but never shown
    /// as something to type in. Full name is first + last.
    var derived = false
    var id: String { key }
}

/// The order the groups appear in the app, and the symbol each one wears.
enum FieldGroup {
    static let order = ["Name", "Personal", "Contact", "Passport", "Travel",
                        "ID", "Address", "Work", "Vehicle", "Emergency", "Other"]

    static let symbols = [
        "Name": "textformat",
        "Personal": "person.fill",
        "Contact": "at",
        "Passport": "book.closed.fill",
        "Travel": "airplane",
        "ID": "creditcard.fill",
        "Address": "house.fill",
        "Work": "briefcase.fill",
        "Vehicle": "car.fill",
        "Emergency": "cross.case.fill",
        "Other": "square.grid.2x2.fill",
    ]

    static func symbol(_ group: String) -> String {
        symbols[group] ?? "tag.fill"
    }
}

enum Fields {
    /// Order matters: the specific types sit above the general ones.
    static let builtin: [FieldType] = [
        FieldType(key: "given_name", label: "First name",
                  question: "the person's first or given name",
                  strong: [#"\bgiven[\s_-]?name"#, #"\bfirst[\s_-]?name"#, #"\bfname\b"#,
                           #"\bforename"#, #"^first$"#, #"\bvorname"#],
                  weak: [], isName: true, group: "Name"),
        FieldType(key: "middle_name", label: "Middle name",
                  question: "the person's middle name or middle initial",
                  strong: [#"\bmiddle[\s_-]?(name|initial)"#, #"\bmname\b"#, #"\bmiddle\b"#],
                  weak: [], isName: true, group: "Name"),
        FieldType(key: "family_name", label: "Last name",
                  question: "the person's last, family or surname",
                  strong: [#"\bfamily[\s_-]?name"#, #"\blast[\s_-]?name"#, #"\bsurname"#,
                           #"\blname\b"#, #"^last$"#, #"\bnachname"#],
                  weak: [], isName: true, group: "Name"),
        FieldType(key: "full_name", label: "Full name",
                  question: "the person's whole name on one line",
                  strong: [#"\bfull[\s_-]?name"#, #"\bname[\s_-]?on[\s_-]?(card|passport|ticket)"#,
                           #"\bpassenger[\s_-]?name"#, #"\byour[\s_-]?name"#, #"^name$"#],
                  weak: [#"\bname\b"#], isName: true, group: "Name", derived: true),
        FieldType(key: "email", label: "Email", question: "an email address",
                  strong: [#"e[\s_-]?mail"#, #"\bmail[\s_-]?address"#], weak: [], group: "Contact"),
        FieldType(key: "phone", label: "Phone", question: "a telephone or mobile number",
                  strong: [#"\bphone"#, #"\bmobile"#, #"\btelephone"#, #"\btel\b"#, #"\bcell\b"#],
                  weak: [#"\bcontact[\s_-]?(no|num|number)"#], group: "Contact"),
        FieldType(key: "dob", label: "Date of birth", question: "the person's date of birth",
                  strong: [#"\b(date[\s_-]?of[\s_-]?birth|birth[\s_-]?date|dob)\b"#,
                           #"\bbirthday\b"#, #"\bborn[\s_-]?on"#],
                  weak: [#"\bbirth\b"#, #"\bborn\b"#, #"\bdate[\s_-]?born"#], group: "Personal"),
        FieldType(key: "sex", label: "Sex", question: "the person's sex or gender",
                  strong: [#"\bgender\b"#, #"\bsex\b"#], weak: [], group: "Personal"),
        FieldType(key: "nationality", label: "Nationality",
                  question: "the person's nationality or citizenship",
                  strong: [#"\bnationality"#, #"\bcitizenship"#, #"\bcitizen[\s_-]?of"#], weak: [], group: "Personal"),
        FieldType(key: "place_of_birth", label: "Place of birth",
                  question: "the town or country where the person was born",
                  strong: [#"\b(place|city|country|town)[\s_-]?of[\s_-]?birth"#,
                           #"\bbirth[\s_-]?(place|city|country)"#], weak: [], group: "Personal"),

        FieldType(key: "document_type", label: "Document type",
                  question: "which KIND of identity document this is - a passport, an identity card, a driving licence",
                  strong: [#"document[\s_-]?type"#, #"type[\s_-]?of[\s_-]?document"#,
                           #"\bid[\s_-]?type"#, #"travel[\s_-]?document[\s_-]?type"#,
                           #"identification[\s_-]?type"#],
                  weak: [], group: "Passport"),
        FieldType(key: "passport_number", label: "Passport number", question: "a passport number",
                  strong: [#"passport[\s_-]?(no|num|number|#|id)"#, #"\bppt[\s_-]?(no|num|number)"#,
                           #"\bdocument[\s_-]?(no|num|number)"#, #"\btravel[\s_-]?doc"#],
                  weak: [#"\bpassport\b"#, #"\bppt\b"#, #"\bpasseport\b"#, #"\bdarkon\b"#], group: "Passport"),
        FieldType(key: "passport_country", label: "Passport country",
                  question: "the country that issued the passport",
                  strong: [#"passport[\s_-]?(country|issuing|issued|nation|state)"#,
                           #"(country|place|state)[\s_-]?of[\s_-]?issue"#,
                           #"issuing[\s_-]?(country|authority)"#],
                  weak: [#"\bissued[\s_-]?by"#], group: "Passport"),
        FieldType(key: "passport_issued", label: "Passport issue date",
                  question: "the date the passport was issued",
                  strong: [#"passport[\s_-]?issue"#, #"issue[\s_-]?date"#,
                           #"date[\s_-]?of[\s_-]?issue"#], weak: [], group: "Passport"),
        FieldType(key: "passport_expiry", label: "Passport expiry",
                  question: "the date the passport expires",
                  strong: [#"passport[\s_-]?(exp|expiry|expiration)"#, #"\bexpir\w*[\s_-]?date"#,
                           #"valid[\s_-]?(un)?til"#, #"date[\s_-]?of[\s_-]?expir"#],
                  weak: [#"\bexpir"#, #"\bexp\b"#], group: "Passport"),
        FieldType(key: "eta_il", label: "ETA-IL number",
                  question: "an Israeli ETA-IL electronic travel authorisation number",
                  strong: [#"eta[\s_-]?il\b"#, #"\betail\b"#,
                           #"electronic[\s_-]?travel[\s_-]?authori[sz]ation"#,
                           #"israel\w*[\s_-]?(entry|authori[sz]ation)"#],
                  weak: [#"authori[sz]ation[\s_-]?(no|num|number)"#], group: "Travel"),
        FieldType(key: "eta_il_expiry", label: "ETA-IL valid until",
                  question: "the date an Israeli ETA-IL authorisation expires",
                  strong: [#"eta[\s_-]?il[\s_-]?(expiry|expires|valid)"#,
                           #"authori[sz]ation[\s_-]?(expiry|expires|valid[\s_-]?until)"#],
                  weak: [], group: "Travel"),
        FieldType(key: "known_traveler", label: "Known Traveler / Global Entry",
                  question: "a Known Traveler, TSA PreCheck or Global Entry number",
                  strong: [#"known[\s_-]?travel"#, #"\bktn\b"#, #"global[\s_-]?entry"#,
                           #"trusted[\s_-]?traveler"#, #"tsa[\s_-]?pre"#], weak: [], group: "Travel"),
        FieldType(key: "redress_number", label: "Redress number",
                  question: "a TSA redress number", strong: [#"\bredress"#], weak: [], group: "Travel"),
        FieldType(key: "frequent_flyer", label: "Frequent flyer",
                  question: "a frequent flyer or loyalty program number",
                  strong: [#"frequent[\s_-]?fly"#, #"loyalty[\s_-]?(no|num|number)"#,
                           #"\bffn\b"#, #"airline[\s_-]?program"#,
                           #"mileage[\s_-]?plus"#, #"sky[\s_-]?miles"#, #"aadvantage"#,
                           #"true[\s_-]?blue"#, #"matmid"#, #"rapid[\s_-]?rewards"#,
                           #"mileage[\s_-]?plan"#, #"miles[\s_-]?(and|&)[\s_-]?more"#,
                           #"\bavios\b"#, #"sky[\s_-]?wards"#],
                  weak: [#"\bmiles\b"#], group: "Travel"),
        FieldType(key: "loyalty_number", label: "Loyalty number",
                  question: "a hotel, lounge or shop loyalty or membership number",
                  strong: [#"\bbonvoy\b"#, #"\bhonors\b"#, #"world[\s_-]?of[\s_-]?hyatt"#,
                           #"priority[\s_-]?pass"#, #"\bloyalty\b"#,
                           #"rewards[\s_-]?(no|num|number|id)"#,
                           #"membership[\s_-]?(no|num|number|id)"#,
                           #"sky[\s_-]?pearl"#],
                  weak: [#"\bmember[\s_-]?(no|num|number)"#], group: "Travel"),
        FieldType(key: "national_id", label: "National ID / SSN",
                  question: "a national identity or social security number",
                  strong: [#"social[\s_-]?security"#, #"\bssn\b"#, #"national[\s_-]?id"#,
                           #"\bid[\s_-]?number"#, #"\bteudat"#],
                  weak: [#"\bid\b"#], group: "ID"),
        FieldType(key: "drivers_license", label: "Driver's license",
                  question: "a driver's license number",
                  strong: [#"driver'?s?[\s_-]?licen[sc]e"#, #"\bdl[\s_-]?(no|num|number)"#], weak: [], group: "ID"),

        FieldType(key: "address_line1", label: "Address line 1",
                  question: "the street part of a postal address",
                  strong: [#"address[\s_-]?(line)?[\s_-]?1\b"#, #"street[\s_-]?address"#,
                           #"\bstreet\b"#, #"^address$"#, #"\baddr1\b"#],
                  weak: [], shared: true, group: "Address"),
        FieldType(key: "address_line2", label: "Address line 2",
                  question: "the second line of a postal address, like an apartment number",
                  strong: [#"address[\s_-]?(line)?[\s_-]?2\b"#, #"\bapt\b"#, #"\bapartment"#,
                           #"\bsuite\b"#, #"\bunit\b"#, #"\baddr2\b"#],
                  weak: [], shared: true, group: "Address"),
        FieldType(key: "city", label: "City", question: "the town or city of a postal address",
                  strong: [#"\bcity\b"#, #"\btown\b"#, #"\blocality\b"#], weak: [], shared: true, group: "Address"),
        FieldType(key: "state", label: "State",
                  question: "the state, province or region of a postal address",
                  strong: [#"\bstate\b"#, #"\bprovince\b"#, #"\bregion\b"#, #"\bcounty\b"#],
                  weak: [], shared: true, group: "Address"),
        FieldType(key: "postal_code", label: "ZIP / postal code",
                  question: "a postal or ZIP code",
                  strong: [#"\bzip\b"#, #"postal[\s_-]?code"#, #"\bpostcode\b"#],
                  weak: [#"\bpost\w*[\s_-]?code"#], shared: true, group: "Address"),
        FieldType(key: "country", label: "Country", question: "the country of a postal address",
                  strong: [#"\bcountry\b"#], weak: [], shared: true, group: "Address"),

        FieldType(key: "emergency_contact", label: "Emergency contact",
                  question: "the name of somebody to call in an emergency",
                  strong: [#"emergency[\s_-]?contact"#, #"in[\s_-]?case[\s_-]?of[\s_-]?emergency"#,
                           #"\bice[\s_-]?contact"#, #"next[\s_-]?of[\s_-]?kin"#,
                           #"emergency[\s_-]?(name|person)"#],
                  weak: [], group: "Emergency"),
        FieldType(key: "emergency_phone", label: "Emergency contact phone",
                  question: "the telephone number of somebody to call in an emergency",
                  strong: [#"emergency[\s_-]?(phone|tel|number|no)"#,
                           #"emergency[\s_-]?contact[\s_-]?(phone|number)"#],
                  weak: [], group: "Emergency"),
        FieldType(key: "vehicle", label: "Vehicle",
                  question: "the make and model of a car",
                  strong: [#"\bvehicle\b"#, #"\bcar[\s_-]?(make|model|description)"#,
                           #"make[\s_-]?(and|&)[\s_-]?model"#],
                  weak: [], group: "Vehicle"),
        FieldType(key: "vehicle_vin", label: "VIN",
                  question: "a vehicle identification number",
                  strong: [#"\bvin\b"#, #"vehicle[\s_-]?identification"#],
                  weak: [], group: "Vehicle"),
        FieldType(key: "license_plate", label: "License plate",
                  question: "a vehicle's number plate",
                  strong: [#"licen[sc]e[\s_-]?plate"#, #"\bplate[\s_-]?(no|num|number)"#,
                           #"registration[\s_-]?(no|num|number|plate)"#, #"\btag[\s_-]?number"#],
                  weak: [], group: "Vehicle"),
        FieldType(key: "company", label: "Company",
                  question: "the name of a company or employer",
                  strong: [#"\bcompany\b"#, #"\borganisation\b"#, #"\borganization\b"#,
                           #"\bemployer\b"#, #"\bbusiness[\s_-]?name"#], weak: [], shared: true, group: "Work"),
        FieldType(key: "job_title", label: "Job title", question: "a job title or occupation",
                  strong: [#"\bjob[\s_-]?title"#, #"\boccupation\b"#, #"\bposition\b"#], weak: [], group: "Work"),
        FieldType(key: "website", label: "Website", question: "a website address",
                  strong: [#"\bwebsite\b"#, #"\bweb[\s_-]?site"#, #"\bhomepage\b"#, #"\burl\b"#],
                  weak: [], shared: true, group: "Contact"),
    ]

    /// Fields Nolan added himself. Registered from the store when it loads, so
    /// a custom field behaves like a built-in one everywhere.
    private(set) static var extra: [FieldType] = []
    private(set) static var byKey: [String: FieldType] =
        Dictionary(uniqueKeysWithValues: builtin.map { ($0.key, $0) })

    static var all: [FieldType] { builtin + extra }

    static func register(_ custom: [CustomField]) {
        extra = custom.map { c in
            // The label is the pattern: "Visa number" matches "visa number",
            // "visa_number", "Visa No." and so on.
            let words = c.label.lowercased()
                .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                .map(String.init)
            let pattern = words.isEmpty ? NSRegularExpression.escapedPattern(for: c.key)
                : "\\b" + words.map { NSRegularExpression.escapedPattern(for: $0) }
                    .joined(separator: "[\\s_-]?")
            return FieldType(key: c.key, label: c.label,
                             question: "the person's \(c.label.lowercased())",
                             strong: [pattern], weak: [],
                             shared: c.shared, isName: false, group: c.group)
        }
        byKey = Dictionary(all.map { ($0.key, $0) }, uniquingKeysWith: { _, b in b })
    }

    /// The `autocomplete` attribute is the one hint a site gives on purpose, so
    /// it outranks every pattern.
    static let autocomplete: [String: String] = [
        "given-name": "given_name", "additional-name": "middle_name",
        "family-name": "family_name", "name": "full_name", "nickname": "given_name",
        "email": "email", "tel": "phone", "tel-national": "phone",
        "bday": "dob", "sex": "sex",
        "organization": "company", "organization-title": "job_title", "url": "website",
        "street-address": "address_line1", "address-line1": "address_line1",
        "address-line2": "address_line2", "address-level2": "city", "address-level1": "state",
        "postal-code": "postal_code", "country": "country", "country-name": "country",
    ]

    static func label(_ key: String) -> String { byKey[key]?.label ?? key }
    static func isShared(_ key: String) -> Bool { byKey[key]?.shared ?? false }
    static func isName(_ key: String) -> Bool { byKey[key]?.isName ?? false }

    // MARK: - matching

    private static var cache = [String: NSRegularExpression]()
    private static let cacheLock = NSLock()

    /// How much of the text a pattern actually matched, 0 for no match. Used to
    /// pick the MOST SPECIFIC hit when several types match: "Emergency contact
    /// phone" hits both `emergency...phone` and a bare `phone`, and the longer
    /// match is the right one.
    static func matchLength(_ pattern: String, _ text: String) -> Int {
        cacheLock.lock()
        var re = cache[pattern]
        if re == nil {
            re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            cache[pattern] = re
        }
        cacheLock.unlock()
        guard let re,
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
        else { return 0 }
        return m.range.length
    }

    static func matches(_ pattern: String, _ text: String) -> Bool {
        cacheLock.lock()
        var re = cache[pattern]
        if re == nil {
            re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            cache[pattern] = re
        }
        cacheLock.unlock()
        guard let re else { return false }
        return re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    /// Boxes that are never personal data. Without this a site's own search
    /// field was handed a full name, because no pattern matched and the AI was
    /// asked to name it - and it answered confidently.
    static let neverFill = [
        #"\bsearch\b"#, #"\bquery\b"#, #"\bfilter\b"#, #"\bkeyword"#,
        #"\bcaptcha"#, #"\bcoupon"#, #"\bpromo"#, #"\bvoucher"#, #"\bdiscount"#,
        #"\bcomment"#, #"\bmessage\b"#, #"\bfeedback"#, #"\bsubject\b"#,
        #"\bquantity"#, #"\bamount\b"#, #"\bprice\b"#,
        #"\bverification"#, #"\bone[\s_-]?time"#, #"\botp\b"#, #"\bpasscode"#,
        // Card and bank details are never filled in. They are not in the store
        // and they are not going to be.
        #"\bcard[\s_-]?(number|no|num)"#, #"\bcc[\s_-]?(number|name|exp|csc|cvv)"#,
        #"\bcredit[\s_-]?card"#, #"\bdebit"#, #"\bcvv\b"#, #"\bcvc\b"#,
        #"\bsecurity[\s_-]?code"#, #"\biban\b"#, #"\brouting"#, #"\baccount[\s_-]?number"#,

        // The same boxes in other languages. Found on 2026-09-22: a French form's
        // "Rechercher sur le site" was NOT recognised as a search box. It only
        // escaped being filled because the whole-form fill refuses anything under
        // 0.7, which is luck, not a rule. A search box must be refused outright.
        //
        // Search
        #"\brecherche"#, #"\bbuscar\b"#, #"\bbúsqueda"#, #"\bbusca\b"#,
        #"\bpesquisa"#, #"\bsuche"#, #"\bsuchen\b"#, #"\bzoek"#,
        #"\bcerca\b"#, #"\bricerca"#, #"\bszukaj"#, #"\barama\b"#,
        #"\bпоиск"#, #"חיפוש"#, #"搜索"#, #"搜尋"#, #"查询"#, #"検索"#, #"검색"#, #"بحث"#,
        // Coupon and discount
        #"\bcodice[\s_-]?sconto"#, #"\bcupón"#, #"\bcupom"#, #"\bgutschein"#,
        #"\brabatt"#, #"\bkorting"#, #"优惠券"#, #"クーポン"#, #"쿠폰"#, #"קופון"#,
        // Comment and message
        #"\bcommentaire"#, #"\bcomentario"#, #"\bcomentário"#, #"\bkommentar"#,
        #"\bcommento"#, #"\bopmerking"#, #"\bnachricht"#, #"\bmensaje"#,
        #"备注"#, #"留言"#, #"コメント"#, #"댓글"#, #"הערה"#, #"הערות"#, #"תגובה"#,
        // One-time and verification codes
        #"\bcode[\s_-]?de[\s_-]?vérification"#, #"\bcódigo[\s_-]?de[\s_-]?verificaci"#,
        #"\bbestätigungscode"#, #"\bverifizierung"#, #"\bverifica"#,
        #"验证码"#, #"認証コード"#, #"確認コード"#, #"인증번호"#, #"קוד אימות"#,
        // Card security
        #"\bcarte[\s_-]?de[\s_-]?crédit"#, #"\btarjeta[\s_-]?de[\s_-]?crédito"#,
        #"\bkreditkarte"#, #"\bcarta[\s_-]?di[\s_-]?credito"#, #"信用卡"#, #"クレジットカード"#,
    ]

    /// A "card number" is usually a payment card and must never be filled - but
    /// a library card, a loyalty card and a gift card are all card numbers too.
    /// These win over the block list.
    static let fillAnyway = [
        #"\blibrary\b"#, #"\bloyalty\b"#, #"\bmembership\b"#, #"\brewards\b"#,
        #"\bbonvoy\b"#, #"\bhonors\b"#, #"\bhyatt\b"#, #"priority[\s_-]?pass"#,
    ]

    /// Everything readable on a field, lower-cased, with separators turned into
    /// spaces. `_` is a word character to the regex engine, so `\bpassport`
    /// would never match `traveler2_passport` without this.
    static func haystack(_ f: FormField) -> String {
        let parts = [f.label, f.name, f.id, f.placeholder, f.ariaLabel, f.section]
        let joined = parts.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ").lowercased()
        return joined.replacingOccurrences(of: "[^a-z0-9]+", with: " ",
                                           options: .regularExpression)
    }

    struct Guess { let key: String?; let confidence: Double; let why: String }

    static func guessType(_ f: FormField) -> Guess {
        for token in (f.autocomplete ?? "").lowercased().split(separator: " ") {
            if let k = autocomplete[String(token)] {
                return Guess(key: k, confidence: 1.0, why: "autocomplete=\(token)")
            }
        }
        let hay = haystack(f)
        if hay.trimmingCharacters(in: .whitespaces).isEmpty {
            return Guess(key: nil, confidence: 0, why: "nothing to read on the field")
        }
        if !fillAnyway.contains(where: { matches($0, hay) }),
           let p = neverFill.first(where: { matches($0, hay) }) {
            // -1 tells the caller not to bother the AI either.
            return Guess(key: nil, confidence: -1, why: "not a personal detail (/\(p)/)")
        }
        var hits = [(key: String, pattern: String, len: Int)]()
        for t in all {
            var best = (pattern: "", len: 0)
            for p in t.strong {
                let n = matchLength(p, hay)
                if n > best.len { best = (p, n) }
            }
            if best.len > 0 { hits.append((t.key, best.pattern, best.len)) }
        }
        if hits.count == 1 {
            return Guess(key: hits[0].key, confidence: 0.9, why: "matched /\(hits[0].pattern)/")
        }
        if !hits.isEmpty {
            let top = hits.map(\.len).max() ?? 0
            let best = hits.filter { $0.len == top }
            if best.count == 1 {
                return Guess(key: best[0].key, confidence: 0.9,
                             why: "matched /\(best[0].pattern)/, the most specific of \(hits.count)")
            }
            return Guess(key: nil, confidence: 0,
                         why: "ambiguous: " + hits.map(\.key).joined(separator: ", "))
        }
        var weak = [(String, String)]()
        for t in all {
            if let p = t.weak.first(where: { matches($0, hay) }) { weak.append((t.key, p)) }
        }
        if weak.count == 1 {
            return Guess(key: weak[0].0, confidence: 0.7, why: "weakly matched /\(weak[0].1)/")
        }
        if !weak.isEmpty {
            return Guess(key: nil, confidence: 0,
                         why: "weakly ambiguous: " + weak.map(\.0).joined(separator: ", "))
        }
        return Guess(key: nil, confidence: 0, why: "no pattern matched")
    }
}
