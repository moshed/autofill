import SwiftUI
import Sparkle

struct SettingsView: View {
    @ObservedObject var model: AppModel
    /// `-DemoSetup` opens on the Setup tab, so it can be looked at and captured.
    @State private var tab = CommandLine.arguments.contains("-DemoSetup") ? Tab.setup : Tab.data

    enum Tab: String, CaseIterable {
        case data = "Data", setup = "Setup"
        var symbol: String { self == .data ? "person.text.rectangle" : "gearshape" }
    }

    var body: some View {
        VStack(spacing: 0) {
            switch tab {
            case .data: DataView(model: model)
            case .setup: SetupView(model: model)
            }
        }
        .frame(minWidth: 820, minHeight: 600)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("", selection: $tab) {
                    ForEach(Tab.allCases, id: \.self) {
                        Image(systemName: $0.symbol)
                            .help($0.rawValue)
                            .tag($0)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 110)
            }
        }
        .overlay(alignment: .bottom) {
            if let note = model.note {
                HStack(spacing: 8) {
                    Text(note).font(.callout)
                    Button("OK") { model.note = nil }.buttonStyle(.plain).opacity(0.7)
                }
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(.quaternary))
                .shadow(radius: 8, y: 2)
                .padding(.bottom, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: model.note)
    }
}

// MARK: - Data

private struct DataView: View {
    @ObservedObject var model: AppModel
    @State private var selected: String?
    @State private var newName = ""
    @State private var importing = false
    @State private var addingField = false
    /// The pane keeps the width it was dragged to, across restarts.
    @AppStorage("sidebarWidth") private var sidebarWidth = 240.0

    private var person: Person? { model.data.people.first { $0.id == selected } }

    var body: some View {
        // A plain HSplitView cannot remember its position, and measuring it to
        // save the width fed straight back into the width it was given - the
        // pane grew until it hit the limit. A divider that is dragged by hand
        // has neither problem.
        HStack(spacing: 0) {
            sidebar.frame(width: sidebarWidth)
            Divider()
                .frame(width: 1)
                .overlay(Rectangle().fill(.clear).frame(width: 9).contentShape(Rectangle()))
                .onHover { $0 ? NSCursor.resizeLeftRight.push() : NSCursor.pop() }
                .gesture(DragGesture(coordinateSpace: .global)
                    .onChanged { g in
                        sidebarWidth = min(max(g.location.x, 180), 460)
                    })
            detail
        }
        .frame(maxHeight: .infinity)
        .onAppear { if selected == nil { selected = model.data.people.first?.id } }
        .sheet(isPresented: $importing) { ImportSheet(model: model) { importing = false } }
        .sheet(isPresented: $addingField) {
            NewFieldSheet(model: model) { addingField = false }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    importing = true
                } label: {
                    Label("Import", systemImage: "sparkles")
                }
                .labelStyle(.titleAndIcon)
                .help("Paste a block of details and let the AI sort it out")
            }
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $selected) {
                ForEach(model.data.people) { p in
                    HStack(spacing: 8) {
                        Text(p.displayName)
                        if p.isDefault {
                            Image(systemName: "star.fill")
                                .font(.caption2).foregroundStyle(.tertiary)
                                .help("The one used when a form names nobody")
                        }
                        Spacer()
                        Text("\(p.valueCount)").foregroundStyle(.tertiary).font(.caption)
                    }
                    .padding(.vertical, 2)
                    .tag(p.id)
                }
            }
            .listStyle(.sidebar)

            Divider()
            HStack(spacing: 6) {
                TextField("Add a person", text: $newName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(add)
                Button(action: add) { Image(systemName: "plus") }
                    .disabled(newName.isEmpty)
            }
            .padding(8)
        }
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private var detail: some View {
        if let p = person, let idx = model.data.people.firstIndex(of: p) {
            PersonEditor(model: model, index: idx, onAddField: { addingField = true })
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView {
                Label("Nobody selected", systemImage: "person.crop.circle")
            } description: {
                Text("Pick someone on the left, or use Import to paste a block of details.")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func add() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let parts = name.split(separator: " ").map(String.init)
        let id = (parts.first ?? name).lowercased()
        guard !model.data.people.contains(where: { $0.id == id }) else { return }
        var plain = ["given_name": parts.first ?? name]
        if parts.count > 1 { plain["family_name"] = parts.dropFirst().joined(separator: " ") }
        var p = Person(id: id, plain: plain)
        p.isDefault = model.data.people.isEmpty
        model.data.people.append(p)
        newName = ""
        selected = id
        model.save(editing: id)
    }
}

// MARK: - one person

private struct PersonEditor: View {
    @ObservedObject var model: AppModel
    let index: Int
    let onAddField: () -> Void

    @State private var renaming: String?
    @State private var renameTo = ""
    @State private var removing: FieldType?

    private var person: Person { model.data.people[index] }

    private var groups: [(String, [FieldType])] {
        // Derived fields are filled on a form but never typed in here.
        let hidden = Set(model.data.hiddenFields)
        let byGroup = Dictionary(grouping: Fields.all.filter {
            !$0.derived && !hidden.contains($0.key)
        }, by: \.group)
        let known = FieldGroup.order.compactMap { g -> (String, [FieldType])? in
            guard let list = byGroup[g], !list.isEmpty else { return nil }
            return (g, list)
        }
        let rest = byGroup.keys.filter { !FieldGroup.order.contains($0) }.sorted()
            .map { ($0, byGroup[$0] ?? []) }
        return known + rest
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                header

                ForEach(groups, id: \.0) { group, types in
                    VStack(alignment: .leading, spacing: 10) {
                        Label(group, systemImage: FieldGroup.symbol(group))
                            .font(.title3).fontWeight(.semibold)
                            .foregroundStyle(.primary)
                        VStack(spacing: 6) {
                            ForEach(types) { t in
                                FieldRows(type: t, list: binding(for: t.key),
                                          personID: person.id,
                                          nameOf: { id in
                                              model.data.person(id)?.displayName ?? id
                                          },
                                          othersWith: { others(holding: t.key) },
                                          shareAll: { label, value in
                                              model.data.share(t.key, label: label,
                                                               value: value, owner: person.id)
                                              model.save(editing: person.id)
                                          },
                                          save: { model.save(editing: person.id) })
                                .contextMenu {
                                    Button("Rename \u{201C}\(t.label)\u{201D}\u{2026}") {
                                        renaming = t.key
                                        renameTo = t.label
                                    }
                                    Button("Remove \u{201C}\(t.label)\u{201D}", role: .destructive) {
                                        removing = t
                                    }
                                }
                            }
                        }
                    }
                }

                Button(action: onAddField) {
                    Label("Add a field", systemImage: "plus.circle")
                }
                .buttonStyle(.link)
                .alert("Rename this field", isPresented: Binding(
                    get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                    TextField("Name", text: $renameTo)
                    Button("Rename", action: applyRename)
                    Button("Cancel", role: .cancel) { renaming = nil }
                } message: {
                    Text("Only the name changes. Everything already in this field stays.")
                }
                .confirmationDialog(
                    removing.map { "Remove \u{201C}\($0.label)\u{201D}?" } ?? "",
                    isPresented: Binding(get: { removing != nil },
                                         set: { if !$0 { removing = nil } }),
                    titleVisibility: .visible) {
                    Button("Remove and clear it for everyone", role: .destructive) {
                        if let t = removing {
                            model.data.forget(t.key)
                            model.save(editing: person.id)
                        }
                        removing = nil
                    }
                    Button("Keep it", role: .cancel) { removing = nil }
                } message: {
                    Text("It disappears from everyone, and whatever is in it is cleared.")
                }

                Divider()
                HStack {
                    Button("Use by default") { makeDefault() }
                        .disabled(person.isDefault)
                        .help("Fill this person in when a form names nobody")
                    Spacer()
                    Button("Delete \(person.displayName)", role: .destructive) {
                        let id = person.id
                        model.data.people.removeAll { $0.id == id }
                        model.save()
                    }
                }
                .padding(.bottom, 8)
            }
            .padding(22)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(person.displayName).font(.largeTitle).fontWeight(.semibold)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Also called").foregroundStyle(.secondary)
                TextField("Other names a form might use, comma separated",
                          text: Binding(get: { person.aliases.joined(separator: ", ") },
                                        set: {
                                            model.data.people[index].aliases = $0
                                                .split(separator: ",")
                                                .map { $0.trimmingCharacters(in: .whitespaces) }
                                                .filter { !$0.isEmpty }
                                            model.save(editing: person.id)
                                        }))
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private func binding(for key: String) -> Binding<[FieldValue]> {
        Binding(get: { model.data.people[index].fields[key] ?? [] },
                set: {
                    model.data.people[index].fields[key] = $0.isEmpty ? nil : $0
                    model.save(editing: model.data.people[index].id)
                })
    }

    /// Everybody else who already has something in this field, so linking can
    /// say WHOSE value to follow rather than just "share this".
    private func others(holding key: String) -> [(id: String, name: String, value: String)] {
        model.data.people.compactMap { p in
            guard p.id != person.id,
                  let v = (p.fields[key] ?? []).first(where: { !$0.value.isEmpty })
            else { return nil }
            return (p.id, p.displayName, v.value)
        }
    }

    private func applyRename() {
        guard let key = renaming else { return }
        let name = renameTo.trimmingCharacters(in: .whitespaces)
        renaming = nil
        guard !name.isEmpty else { return }
        if let i = model.data.customFields.firstIndex(where: { $0.key == key }) {
            model.data.customFields[i].label = name      // a custom field owns its name
        }
        model.data.fieldLabels[key] = name
        model.save(editing: person.id)
    }

    private func makeDefault() {
        let id = person.id
        for i in model.data.people.indices {
            model.data.people[i].isDefault = (model.data.people[i].id == id)
        }
        model.save(editing: id)
    }
}

/// One field type. Usually one line; press + for a second, and a short label box
/// appears so "work" and "personal" can be told apart. The chain marks a value
/// as the family's.
/// A softer, rounder box than `.roundedBorder`, which is square and dated.
struct MacField: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .textFieldStyle(.plain)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor)))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.14), lineWidth: 1))
    }
}

/// Nudges a control sideways once, to say "you cannot type here".
private struct Shake: ViewModifier, Animatable {
    var shakes: CGFloat
    var animatableData: CGFloat {
        get { shakes }
        set { shakes = newValue }
    }
    func body(content: Content) -> some View {
        content.offset(x: sin(shakes * .pi * 3) * 5)
    }
}

private struct FieldRows: View {
    let type: FieldType
    @Binding var list: [FieldValue]
    let personID: String
    let nameOf: (String) -> String
    /// Everybody else who already has something in this field.
    let othersWith: () -> [(id: String, name: String, value: String)]
    /// Hand this value to everybody. Only ever from the chain menu.
    let shareAll: (String, String) -> Void
    let save: () -> Void

    /// Rows being nudged because somebody tried to type in a locked box.
    @State private var shakes = [Int: CGFloat]()
    @State private var complaint: (row: Int, text: String)?

    /// What is in the box while a date is being typed. Rewriting the box on
    /// every keystroke fights the person typing, so the store is only written
    /// when what they have typed is a whole date.
    @State private var typing = [Int: String]()

    private var isDate: Bool { Match.dateTypes.contains(type.key) }

    private var rows: [FieldValue] { list.isEmpty ? [FieldValue(value: "")] : list }

    var body: some View {
        VStack(spacing: 3) {
            ForEach(Array(rows.enumerated()), id: \.offset) { i, v in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(i == 0 ? type.label : "")
                        .frame(width: 168, alignment: .leading)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if rows.count > 1 {
                        TextField("which", text: bindLabel(i))
                            .textFieldStyle(MacField())
                            .frame(width: 92)
                    }

                    ZStack {
                        TextField(isDate ? "mm/dd/yyyy" : "", text: bindValue(i))
                            .textFieldStyle(MacField())
                            .disabled(lockedBy(i) != nil)
                            .foregroundStyle(lockedBy(i) == nil ? Color.primary : Color.secondary)
                            .modifier(Shake(shakes: shakes[i] ?? 0))

                        // A disabled field never hears a click, so a clear button
                        // sits on top of it purely to answer one.
                        if let owner = lockedBy(i) {
                            Button {
                                complaint = (i, "This is \(nameOf(owner))'s \(type.label). "
                                             + "Edit it there, or press the chain to make "
                                             + "this one your own.")
                                withAnimation(.linear(duration: 0.4)) {
                                    shakes[i] = (shakes[i] ?? 0) + 1
                                }
                            } label: { Color.clear.contentShape(Rectangle()) }
                            .buttonStyle(.plain)
                            .help("Linked to \(nameOf(owner))'s \(type.label)")
                        }
                    }

                    Menu {
                        if let owner = lockedBy(i) {
                            Button("Stop following \(nameOf(owner))") { unlink(i) }
                        } else if v.linked {
                            Button("Stop sharing this with everyone") { unlink(i) }
                        } else {
                            let others = othersWith()
                            if others.isEmpty {
                                Text("Nobody else has a \(type.label.lowercased()) yet")
                            } else {
                                ForEach(others, id: \.id) { o in
                                    Button("Follow \(o.name) — \(o.value)") {
                                        follow(i, owner: o.id, value: o.value)
                                    }
                                }
                                Divider()
                            }
                            Button("Share mine with everyone") { shareMine(i) }
                        }
                    } label: {
                        Image(systemName: lockedBy(i) != nil ? "link.circle.fill" : "link")
                            .foregroundStyle(v.linked ? Color.accentColor
                                                      : Color.secondary.opacity(0.35))
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .frame(width: 22)
                    .disabled(v.value.isEmpty && othersWith().isEmpty)
                    .help(linkHelp(i))

                    if i == rows.count - 1 {
                        Button { list = rows + [FieldValue(value: "")] } label: {
                            Image(systemName: "plus")
                        }
                        .buttonStyle(.borderless)
                        .disabled(v.value.isEmpty)
                        .help("Another \(type.label.lowercased()) — a work one, say")
                    } else {
                        Button {
                            list = rows.enumerated().filter { $0.offset != i }.map(\.element)
                        } label: {
                            Image(systemName: "minus")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            if let c = complaint, c.row < rows.count {
                HStack(spacing: 5) {
                    Image(systemName: "link")
                    Text(c.text)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .transition(.opacity)
            }
            if rows.count > 1 {
                Text("The top one is used when nothing on the page says which.")
                    .font(.caption2).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private func linkHelp(_ i: Int) -> String {
        guard rows.indices.contains(i) else { return "" }
        if let owner = lockedBy(i) {
            return "Linked to \(nameOf(owner))'s \(type.label). Press to unlink and keep "
                 + "your own copy."
        }
        if rows[i].linked {
            return "Everyone shares this one. You hold it, so changing it here changes it "
                 + "for all of them. Press to stop sharing."
        }
        return "Share this with everyone, kept here"
    }

    /// Who owns this value, when it is somebody else's to edit.
    private func lockedBy(_ i: Int) -> String? {
        guard rows.indices.contains(i) else { return nil }
        let v = rows[i]
        guard v.linked, let owner = v.owner, owner != personID else { return nil }
        return owner
    }

    /// Follow somebody else's value. This copy becomes a read-only echo of it.
    private func follow(_ i: Int, owner: String, value: String) {
        var r = rows
        guard r.indices.contains(i) else { return }
        r[i].value = value
        r[i].linked = true
        r[i].owner = owner
        complaint = nil
        list = r
        save()
    }

    /// Hand this value to everybody, and keep the main copy here.
    private func shareMine(_ i: Int) {
        guard rows.indices.contains(i) else { return }
        complaint = nil
        shareAll(rows[i].label, rows[i].value)
    }

    /// Keep what is here, stop following anyone.
    private func unlink(_ i: Int) {
        var r = rows
        guard r.indices.contains(i) else { return }
        r[i].linked = false
        r[i].owner = nil
        complaint = nil
        list = r
        save()
    }

    private func bindLabel(_ i: Int) -> Binding<String> {
        Binding(get: { rows.indices.contains(i) ? Labels.pretty(rows[i].label) : "" },
                set: { var r = rows; r[i].label = $0
                       list = r.filter { !$0.value.isEmpty || !$0.label.isEmpty } })
    }

    private func bindValue(_ i: Int) -> Binding<String> {
        guard isDate else {
            return Binding(get: { rows.indices.contains(i) ? rows[i].value : "" },
                           set: { var r = rows; r[i].value = $0; list = r })
        }
        return Binding(
            get: {
                if let t = typing[i] { return t }
                return Dates.display(rows.indices.contains(i) ? rows[i].value : "")
            },
            set: { text in
                typing[i] = text
                guard let iso = Dates.store(text) else { return }   // still typing
                var r = rows
                guard r.indices.contains(i) else { return }
                r[i].value = iso
                list = r
                typing[i] = nil                                     // show it back formatted
            })
    }
}

// MARK: - Import

private struct ImportSheet: View {
    @ObservedObject var model: AppModel
    let done: () -> Void

    @State private var raw = ""
    @State private var rows = [ImportRow]()
    @State private var busy = false

    private var unsure: Int { rows.filter { !$0.sure }.count }
    private var ticked: Int { rows.filter(\.include).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if rows.isEmpty { paste } else { review }
        }
        .frame(width: rows.isEmpty ? 640 : 940, height: rows.isEmpty ? 420 : 560)
    }

    private var paste: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Label("Import", systemImage: "sparkles").font(.title2).fontWeight(.semibold)
                Text("Paste anything — a passport, a page of notes, a whole family. "
                     + "You check every line before a single thing is saved.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            TextEditor(text: $raw)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
                .frame(maxHeight: .infinity)

            HStack {
                Button("Cancel") { done() }
                Spacer()
                Button(busy ? "Reading…" : "Extract with AI") { Task { await extract() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(raw.isEmpty || busy)
            }
        }
        .padding(20)
    }

    private var review: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Check this before it is saved").font(.title3).fontWeight(.semibold)
                Text(unsure == 0
                     ? "Everything was read cleanly."
                     : "\(unsure) at the top could not be read confidently. Fix or untick them.")
                    .font(.callout)
                    .foregroundStyle(unsure == 0 ? Color.secondary : Color.orange)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)

            Divider()

            Table($rows) {
                TableColumn("") { $r in Toggle("", isOn: $r.include).labelsHidden() }
                    .width(26)
                TableColumn("") { $r in
                    if !$r.wrappedValue.sure {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                }
                .width(20)
                TableColumn("Pasted") { $r in
                    Text($r.wrappedValue.rawLabel.isEmpty ? "(no label)" : $r.wrappedValue.rawLabel)
                        .lineLimit(1)
                        .foregroundStyle($r.wrappedValue.rawLabel.isEmpty ? .secondary : .primary)
                }
                TableColumn("Value") { $r in
                    Text($r.wrappedValue.value).monospaced().lineLimit(1)
                }
                TableColumn("Which") { $r in
                    TextField("", text: $r.variant).textFieldStyle(.roundedBorder)
                }
                .width(88)
                TableColumn("Field") { $r in
                    Picker("", selection: $r.type) {
                        Text("— skip —").tag(String?.none)
                        ForEach(Fields.all) { Text($0.label).tag(String?.some($0.key)) }
                    }
                    .labelsHidden()
                }
                TableColumn("Whose") { $r in
                    Picker("", selection: $r.personID) {
                        ForEach(model.data.people) { Text($0.displayName).tag(String?.some($0.id)) }
                    }
                    .labelsHidden()
                }
                TableColumn("How") { $r in
                    Text($r.wrappedValue.why).font(.caption).foregroundStyle(.tertiary).lineLimit(1)
                }
            }

            Divider()
            HStack {
                Button("Back") { rows = [] }
                Spacer()
                Button("Save \(ticked) of \(rows.count)") { apply() }
                    .buttonStyle(.borderedProminent)
                    .disabled(ticked == 0)
            }
            .padding(18)
        }
    }

    private func extract() async {
        busy = true
        defer { busy = false }
        let parsed = Importer.parse(raw, people: model.data.people)
        var out = await Importer.classifyLeftovers(parsed, people: model.data.people,
                                                   key: model.data.jevKey)
        out.sort { !$0.sure && $1.sure }
        rows = out
    }

    private func apply() {
        var data = model.data
        let n = Importer.apply(rows, to: &data)
        model.data = data
        model.save()
        model.note = "Saved \(n) \(n == 1 ? "value" : "values")."
        done()
    }
}

// MARK: - a field of Nolan's own

struct NewFieldSheet: View {
    @ObservedObject var model: AppModel
    let done: () -> Void

    @State private var label = ""
    @State private var group = "Miscellaneous"
    @State private var newGroup = ""

    private var key: String {
        let base = label.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .joined(separator: "_")
        return base.isEmpty ? "custom" : base
    }

    private var chosenGroup: String {
        let t = newGroup.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? group : t
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Add a field").font(.title3).fontWeight(.semibold)
                Text("A form box whose label matches this name will fill from it.")
                    .font(.callout).foregroundStyle(.secondary)
            }

            Form {
                TextField("Name", text: $label, prompt: Text("Visa number"))
                Picker("Group", selection: $group) {
                    ForEach(FieldGroup.order, id: \.self) {
                        Label($0, systemImage: FieldGroup.symbol($0)).tag($0)
                    }
                }
                TextField("Or a new group", text: $newGroup, prompt: Text("Insurance"))
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel") { done() }
                Spacer()
                Button("Add") { add() }
                    .buttonStyle(.borderedProminent)
                    .disabled(label.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    private func add() {
        guard !model.data.customFields.contains(where: { $0.key == key }),
              Fields.byKey[key] == nil else {
            model.note = "There is already a field called that."
            done()
            return
        }
        model.data.customFields.append(
            CustomField(key: key, label: label.trimmingCharacters(in: .whitespaces),
                        group: chosenGroup))
        Fields.register(model.data.customFields)
        model.save()
        done()
    }
}

// MARK: - Setup

private struct SetupView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section {
                LabeledContent("Shortcut") {
                    ShortcutRecorder(shortcut: Binding(
                        get: { model.data.shortcut },
                        set: { model.data.shortcut = $0; model.save() }))
                }
            } header: {
                Label("Filling", systemImage: "keyboard")
            } footer: {
                Text("Put the cursor in a form field and press it. Press again on the same "
                     + "field to cycle through the other people. Reload an open tab after "
                     + "changing it.")
            }

            Section {
                LabeledContent("Helper") {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(model.server.running ? Color.green : Color.orange)
                            .frame(width: 8, height: 8)
                        Text(model.server.running ? "Running" : "Stopped")
                            .foregroundStyle(.secondary)
                        Button(model.server.running ? "Stop" : "Start") {
                            model.server.running ? model.server.stop() : model.server.start()
                        }
                    }
                }
                LabeledContent("Browser extension") {
                    Text(extensionNote).foregroundStyle(.secondary)
                }
                Toggle("Open at login", isOn: Binding(get: { model.openAtLogin },
                                                      set: { model.openAtLogin = $0 }))
                Toggle("Demo people", isOn: Binding(get: { model.demo },
                                                    set: { model.setDemo($0) }))
            } header: {
                Label("Connection", systemImage: "antenna.radiowaves.left.and.right")
            } footer: {
                Text("The extension talks to this app on this Mac only, never over the network."
                     + (model.demo
                        ? "\n\nDemo people are showing. Nothing you change is saved, and forms "
                        + "are filled with made-up details. Turn it off to get your own back."
                        : ""))
            }

            Section {
                LabeledContent("Your data") {
                    HStack {
                        Button("Export…") { model.export() }
                        Button("Import…") { model.importFile() }
                    }
                }
            } header: {
                Label("Backup", systemImage: "externaldrive")
            } footer: {
                Text("Export writes everyone to a JSON file in plain text. Import reads one "
                     + "back and replaces what is stored.")
            }

            Section {
                LabeledContent("Version") {
                    HStack {
                        Text(model.version).foregroundStyle(.secondary)
                        Button("Check now") { model.updater.checkForUpdates(nil) }
                    }
                }
                LabeledContent("Your own AI key") {
                    SecureField("optional", text: Binding(
                        get: { model.data.jevKey },
                        set: { model.data.jevKey = $0; model.save() }))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                }
                Toggle("Fill card and bank details", isOn: Binding(
                    get: { model.data.fillPayment },
                    set: { model.data.fillPayment = $0; model.save() }))
                Toggle("Work offline — never ask the AI", isOn: Binding(
                    get: { model.data.offline },
                    set: { model.data.offline = $0; model.save() }))
            } header: {
                Label("Updates and AI", systemImage: "arrow.triangle.2.circlepath")
            } footer: {
                Text("Card and bank boxes are left alone until you switch them on. "
                     + "One click fills every box on a page, and an account and routing "
                     + "number together are enough to take money by direct debit, so this "
                     + "is worth deciding on purpose.\n\n"
                     + "Leave the key empty and the app uses a shared one. The key is not in "
                     + "the app - the request goes to dancykier.com, which holds it. Paste your "
                     + "own TypeSafe key to use that instead and skip the middleman.\n\n"
                     + "It checks for a new version once a day. Offline mode stops every call "
                     + "out: the patterns still name most fields, and anything they cannot "
                     + "name is offered to you instead of asked about.")
            }

            Section {
                Text("Filling a form never sends a value anywhere. The AI is given the labels "
                     + "printed on the page so it can say what kind of field it is, and any "
                     + "text matching something you have stored is taken out first. Whose "
                     + "field it is gets worked out here on this Mac; when that is not clear "
                     + "the page shows you a list instead of guessing.\n\nThe only thing ever "
                     + "sent is text you paste and press Extract with AI on.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Label("What the AI is told", systemImage: "lock.shield")
            }
        }
        .formStyle(.grouped)
    }

    private var extensionNote: String {
        guard let seen = model.server.lastSeen else {
            return "Never connected"
        }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return "Last seen \(f.localizedString(for: seen, relativeTo: Date()))"
    }
}
