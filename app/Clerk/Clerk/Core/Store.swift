import Foundation
import Security

/// The personal data. One keychain item holds the lot, so there is no second
/// key to lose and nothing is ever written to a plain file.

/// One value for one field, with an optional short label saying which one it is:
/// "work", "personal", "gmail". A person can hold several per field.
struct FieldValue: Codable, Hashable, Identifiable {
    var label: String = ""
    var value: String
    /// The family's, not just this person's. Editing it on one person writes it
    /// to everyone - one home address, kept in one place, shown on each person.
    var linked: Bool = false
    /// Which person holds the MAIN copy. Everybody else's copy is a read-only
    /// echo of it: the editor greys theirs out and says where to go. nil on a
    /// linked value written before owners existed - then nobody owns it and it
    /// behaves the old way, editable anywhere.
    var owner: String?
    var id: String { label + "\u{1}" + value }

    init(label: String = "", value: String, linked: Bool = false, owner: String? = nil) {
        self.label = label
        self.value = value
        self.linked = linked
        self.owner = owner
    }

    /// Accepts a bare string as well as an object, so a store written before
    /// there were several values per field still reads.
    init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(),
           let s = try? single.decode(String.self) {
            label = ""
            value = s
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        value = try c.decode(String.self, forKey: .value)
        linked = try c.decodeIfPresent(Bool.self, forKey: .linked) ?? false
        owner = try c.decodeIfPresent(String.self, forKey: .owner)
    }
}

struct Person: Codable, Identifiable, Hashable {
    var id: String
    var aliases: [String] = []
    /// field type -> one or more values, most preferred first
    var fields: [String: [FieldValue]] = [:]
    var isDefault: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, aliases, fields
        case isDefault = "default"
    }

    init(id: String, aliases: [String] = [], fields: [String: [FieldValue]] = [:],
         isDefault: Bool = false) {
        self.id = id
        self.aliases = aliases
        self.fields = fields
        self.isDefault = isDefault
    }

    /// Written by hand because the synthesised decoder ignores the property
    /// defaults above and demands every key, and because `fields` may still be
    /// the old `[String: String]` shape.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        aliases = try c.decodeIfPresent([String].self, forKey: .aliases) ?? []
        isDefault = try c.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false
        if let many = try? c.decodeIfPresent([String: [FieldValue]].self, forKey: .fields) {
            fields = many
        } else if let one = try? c.decodeIfPresent([String: String].self, forKey: .fields) {
            fields = one.mapValues { [FieldValue(value: $0)] }
        } else {
            fields = [:]
        }
    }

    /// One value per field. Keeps demo data and tests readable.
    init(id: String, aliases: [String] = [], plain: [String: String],
         isDefault: Bool = false) {
        self.init(id: id, aliases: aliases,
                  fields: plain.mapValues { [FieldValue(value: $0)] }, isDefault: isDefault)
    }

    /// The preferred value for a field, as plain text.
    func text(_ type: String) -> String? {
        fields[type]?.first(where: { !$0.value.isEmpty })?.value
    }

    func values(_ type: String) -> [FieldValue] {
        (fields[type] ?? []).filter { !$0.value.isEmpty }
    }

    mutating func set(_ type: String, _ list: [FieldValue]) {
        let kept = list.filter { !$0.value.trimmingCharacters(in: .whitespaces).isEmpty }
        if kept.isEmpty { fields[type] = nil } else { fields[type] = kept }
    }

    /// Every string that could appear on a form and mean this person.
    var names: [String] {
        var out = aliases
        for k in ["given_name", "family_name", "middle_name", "full_name"] {
            if let v = text(k), !v.isEmpty { out.append(v) }
        }
        if let g = text("given_name"), let f = text("family_name") {
            out.append("\(g) \(f)")
        }
        out.append(id)
        var seen = Set<String>()
        return out.compactMap { n -> String? in
            let t = n.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty, seen.insert(t.lowercased()).inserted else { return nil }
            return t
        }
    }

    var displayName: String { names.first ?? id }

    var valueCount: Int { fields.values.reduce(0) { $0 + $1.count } }
}

/// A field Nolan added himself. It behaves like a built-in one once registered.
struct CustomField: Codable, Hashable, Identifiable {
    var key: String
    var label: String
    var group: String = "Miscellaneous"
    var shared: Bool = false
    var id: String { key }
}

struct StoreData: Codable {
    var people: [Person] = []
    /// the household's values - same shape, so a home and a work address both fit
    var shared: [String: [FieldValue]] = [:]
    var shortcut = Shortcut()
    /// Kept here, inside the app's OWN keychain item, rather than read from the
    /// `jev_api` item the other tools share. A newly signed build is a stranger
    /// to an item another program created, and reading it puts up a password
    /// dialog that blocks the app before it can even listen.
    var jevKey: String = ""
    var customFields: [CustomField] = []
    /// Field types taken off the screen. A built-in cannot really be deleted -
    /// it is part of the vocabulary that reads a form - but it can be hidden, and
    /// hiding it also clears whatever was in it. Unhiding brings the empty field
    /// back, not the old value.
    var hiddenFields: [String] = []
    /// A better name for a field, in Moshe's words. The key never changes, so
    /// renaming one keeps every value that is already in it.
    var fieldLabels: [String: String] = [:]
    /// Never call out at all. The patterns still name most fields; anything they
    /// cannot name is offered rather than guessed.
    var offline: Bool = false
    /// Card and bank boxes are only filled when this is on. Moshe asked for it
    /// on 2026-09-23, having stored his account and routing numbers.
    var fillPayment: Bool = false

    enum CodingKeys: String, CodingKey {
        case people, shared, shortcut, jevKey, customFields, offline
        case hiddenFields, fieldLabels, fillPayment
    }

    init(people: [Person] = [], shared: [String: [FieldValue]] = [:],
         shortcut: Shortcut = Shortcut()) {
        self.people = people
        self.shared = shared
        self.shortcut = shortcut
    }

    init(people: [Person], plainShared: [String: String]) {
        self.init(people: people, shared: plainShared.mapValues { [FieldValue(value: $0)] })
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        people = try c.decodeIfPresent([Person].self, forKey: .people) ?? []
        if let many = try? c.decodeIfPresent([String: [FieldValue]].self, forKey: .shared) {
            shared = many
        } else if let one = try? c.decodeIfPresent([String: String].self, forKey: .shared) {
            shared = one.mapValues { [FieldValue(value: $0)] }
        } else {
            shared = [:]
        }
        shortcut = try c.decodeIfPresent(Shortcut.self, forKey: .shortcut) ?? Shortcut()
        jevKey = try c.decodeIfPresent(String.self, forKey: .jevKey) ?? ""
        customFields = try c.decodeIfPresent([CustomField].self, forKey: .customFields) ?? []
        offline = try c.decodeIfPresent(Bool.self, forKey: .offline) ?? false
        fillPayment = try c.decodeIfPresent(Bool.self, forKey: .fillPayment) ?? false
        hiddenFields = try c.decodeIfPresent([String].self, forKey: .hiddenFields) ?? []
        fieldLabels = try c.decodeIfPresent([String: String].self, forKey: .fieldLabels) ?? [:]
        Fields.register(customFields, renamed: fieldLabels)
    }

    func person(_ id: String) -> Person? { people.first { $0.id == id } }

    var defaultPerson: Person? { people.first { $0.isDefault } ?? people.first }

    /// Every value stored for a person plus a field type, preferred first.
    ///
    /// A person with nothing of their own gets the family's linked values - that
    /// is how a child with no address on file still fills in the home one.
    func values(person id: String?, type: String) -> [FieldValue] {
        if let id, let p = person(id) {
            let own = p.values(type)
            if !own.isEmpty { return own }
            if type == "full_name", let g = p.text("given_name"), let f = p.text("family_name") {
                return [FieldValue(value: "\(g) \(f)")]
            }
        }
        return linkedValues(type)
    }

    /// The family's values for a field type, from whoever has them.
    func linkedValues(_ type: String) -> [FieldValue] {
        var out = [FieldValue](), seen = Set<String>()
        for p in people {
            for v in p.values(type) where v.linked && seen.insert(v.id).inserted {
                out.append(v)
            }
        }
        return out
    }

    /// Writes every linked value onto every person, so "the home address" is one
    /// address however many people show it.
    ///
    /// `from` is the person just edited, and their copy wins. Without that the
    /// last person iterated won, which meant a change was quietly reverted by
    /// somebody else's older copy of the same linked value.
    /// Hand one value to everybody: they each get a copy that follows `owner`.
    /// Deliberate, and only ever from the menu on the chain.
    mutating func share(_ key: String, label: String, value: String, owner: String) {
        for i in people.indices {
            var mine = people[i].fields[key] ?? []
            if let j = mine.firstIndex(where: { $0.label == label }) {
                mine[j].value = value
                mine[j].linked = true
                mine[j].owner = owner
            } else {
                mine.append(FieldValue(label: label, value: value, linked: true, owner: owner))
            }
            people[i].fields[key] = mine
        }
    }

    /// Take a field off the screen and clear it everywhere. Its values would
    /// otherwise stay in the store with nothing to show them.
    mutating func forget(_ key: String) {
        for i in people.indices { people[i].fields[key] = nil }
        customFields.removeAll { $0.key == key }
        fieldLabels[key] = nil
        if Fields.isBuiltin(key), !hiddenFields.contains(key) { hiddenFields.append(key) }
    }

    mutating func propagateLinked(from source: String? = nil) {
        // Which copy of a linked value wins. The OWNER's, if it has one - that
        // is the whole point of naming an owner, and it is why everybody else's
        // box is greyed out. Failing that the person just edited, and failing
        // that whichever was found first.
        var family = [String: [FieldValue]]()          // type -> the family's values

        func consider(_ v: FieldValue, _ type: String, holder: String) {
            var here = family[type] ?? []
            if let j = here.firstIndex(where: { $0.label == v.label }) {
                let winner = here[j]
                let ownerHolds = { (x: FieldValue, who: String) in x.owner == who }
                if ownerHolds(v, holder) && !ownerHolds(winner, holder) {
                    here[j] = v                        // the owner's copy beats it
                } else if v.owner != nil && winner.owner == nil {
                    here[j] = v
                }
            } else {
                here.append(v)
            }
            family[type] = here
        }

        let ordered = source == nil ? people
            : people.filter { $0.id == source } + people.filter { $0.id != source }
        for p in ordered {
            for (type, list) in p.fields {
                for v in list where v.linked { consider(v, type, holder: p.id) }
            }
        }
        // A second pass, so an owner's copy wins wherever it sits in the order.
        for p in people {
            for (type, list) in p.fields {
                for v in list where v.linked && v.owner == p.id {
                    var here = family[type] ?? []
                    if let j = here.firstIndex(where: { $0.label == v.label }) { here[j] = v }
                    else { here.append(v) }
                    family[type] = here
                }
            }
        }

        for i in people.indices {
            for (type, familyList) in family {
                var mine = people[i].fields[type] ?? []
                for fv in familyList {
                    // Only keep an EXISTING follower in step. Never create one.
                    // Adding the value to everybody meant that Leon choosing to
                    // follow Nolan's email quietly gave it to Freya too, who had
                    // asked for nothing. Following is one person's decision, and
                    // "share mine with everyone" is the separate, deliberate way
                    // to hand it to the rest - see StoreData.share.
                    if let j = mine.firstIndex(where: {
                        $0.linked && $0.label == fv.label
                            && ($0.owner == fv.owner || $0.owner == nil || fv.owner == nil)
                    }) {
                        mine[j] = fv
                    }
                }
                people[i].fields[type] = mine
            }
        }
    }

    /// Demo only: give everybody the same linked address, so the chain icons
    /// have something to show.
    func withFamilyAddress() -> StoreData {
        var d = self
        let family: [String: [FieldValue]] = [
            "address_line1": [FieldValue(label: "home", value: "1 Example Street", linked: true),
                              FieldValue(label: "work", value: "500 Trade Road", linked: true)],
            "city": [FieldValue(label: "home", value: "Monsey", linked: true),
                     FieldValue(label: "work", value: "Brooklyn", linked: true)],
            "state": [FieldValue(value: "NY", linked: true)],
            "postal_code": [FieldValue(value: "10952", linked: true)],
            "country": [FieldValue(value: "United States", linked: true)],
        ]
        // The first person holds the main copy, so the demo shows the greyed out
        // boxes and the chain on everybody else.
        let holder = d.people.first?.id
        for i in d.people.indices {
            for (k, v) in family {
                d.people[i].fields[k] = v.map { fv in
                    var x = fv; x.owner = holder; return x
                }
            }
        }
        return d
    }

    /// Old stores kept one `shared` bag beside the people. Turn it into linked
    /// values on everybody, which is the same idea with a place to see it.
    mutating func migrateShared() {
        guard !shared.isEmpty else { return }
        for (type, list) in shared {
            for v in list where !v.value.isEmpty {
                for i in people.indices {
                    var mine = people[i].fields[type] ?? []
                    if !mine.contains(where: { $0.value == v.value }) {
                        mine.append(FieldValue(label: v.label, value: v.value, linked: true))
                    }
                    people[i].fields[type] = mine
                }
            }
        }
        shared = [:]
    }

    func text(person id: String?, type: String) -> String? {
        values(person: id, type: type).first?.value
    }

    /// Every secret string the store holds. Used to make sure none of them can
    /// leave the Mac in a Jev prompt.
    var allValues: [String] {
        var out = shared.values.flatMap { $0 }.map(\.value)
        for p in people { out.append(contentsOf: p.fields.values.flatMap { $0 }.map(\.value)) }
        return out.filter { $0.count >= 3 }
    }
}

/// The key combination that fires a fill.
///
/// `code` is a JavaScript `KeyboardEvent.code` ("KeyF", "Digit4", "Space"),
/// because that is what the content script compares against and it does not move
/// when the keyboard layout does.
struct Shortcut: Codable, Equatable {
    var code: String = "KeyF"
    var alt = true
    var shift = true
    var ctrl = false
    var meta = false

    var display: String {
        var out = ""
        if ctrl { out += "⌃" }
        if alt { out += "⌥" }
        if shift { out += "⇧" }
        if meta { out += "⌘" }
        return out + Shortcut.keyName(code)
    }

    static func keyName(_ code: String) -> String {
        if code.hasPrefix("Key") { return String(code.dropFirst(3)) }
        if code.hasPrefix("Digit") { return String(code.dropFirst(5)) }
        return code
    }

    var hasModifier: Bool { alt || ctrl || meta }
}

enum Store {
    static let service = "clerk_store"
    static let account = "default"

    static func load() -> StoreData {
        guard let data = keychainRead(service: service, account: account),
              let decoded = try? JSONDecoder().decode(StoreData.self, from: data)
        else { return StoreData() }
        Fields.register(decoded.customFields, renamed: decoded.fieldLabels)
        var out = decoded
        out.migrateShared()
        return out
    }

    static func save(_ data: StoreData, editing: String? = nil) throws {
        var data = data
        data.propagateLinked(from: editing)
        let blob = try JSONEncoder().encode(data)
        try keychainWrite(service: service, account: account, data: blob,
                          label: "Clerk personal data")
    }

    // MARK: - keychain

    static func keychainRead(service: String, account: String) -> Data? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }

    static func keychainWrite(service: String, account: String, data: Data,
                              label: String) throws {
        let find: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemUpdate(find as CFDictionary,
                                   [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = find
            add[kSecValueData as String] = data
            add[kSecAttrLabel as String] = label
            let s = SecItemAdd(add as CFDictionary, nil)
            if s != errSecSuccess { throw StoreError.keychain(s) }
        } else if status != errSecSuccess {
            throw StoreError.keychain(status)
        }
    }

    /// The TypeSafe key, for the test harness. The app reads it from the store
    /// instead - see `StoreData.jevKey`.
    ///
    /// `JEV_API_KEY` is checked first so the test binary never touches the
    /// keychain. A freshly compiled binary is a stranger to every item, so each
    /// `swiftc` run would otherwise pop a password prompt.
    static func jevKey() -> String {
        if let env = ProcessInfo.processInfo.environment["JEV_API_KEY"], !env.isEmpty {
            return env
        }
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "jev_api",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let d = out as? Data else { return "" }
        return String(data: d, encoding: .utf8) ?? ""
    }
}

enum StoreError: LocalizedError {
    case keychain(OSStatus)
    var errorDescription: String? {
        switch self {
        case .keychain(let s): return "keychain error \(s)"
        }
    }
}
