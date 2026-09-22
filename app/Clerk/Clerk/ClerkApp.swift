import AppKit
import Combine
import SwiftUI
import ServiceManagement
import Sparkle
import UniformTypeIdentifiers

@main
struct ClerkApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("Clerk", id: "settings") {
            SettingsView(model: AppModel.shared)
                // `open clerk://settings` opens this window from anywhere,
                // which is also how the menu-bar icon reaches it.
                .onOpenURL { _ in NSApp.activate(ignoringOtherApps: true) }
        }
        .handlesExternalEvents(matching: ["settings"])
        .defaultSize(width: 860, height: 640)
        // Nothing on screen when the Mac starts it at login. Opened by hand -
        // from the Dock, the menu bar or the browser - it shows the window.
        .defaultLaunchBehavior(.suppressed)
    }
}

/// The menu-bar icon. One click opens the window - there was nothing worth
/// putting in a menu, so there is no menu. Right-click still offers Quit.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var item: NSStatusItem?

    func applicationDidFinishLaunching(_ note: Notification) {
        _ = AppModel.shared
        // A real app: a Dock icon, a menu bar of its own, and a place in the
        // app switcher. The status item stays as the quick way in.
        NSApp.setActivationPolicy(.regular)
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "text.cursor",
                                     accessibilityDescription: "Clerk")
        item.button?.target = self
        item.button?.action = #selector(clicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        self.item = item
    }

    /// Closing the window does not quit. The helper the browser talks to lives
    /// in this process, so quitting it would stop filling forms.
    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { false }

    /// Clicking the Dock icon with no window open brings the window back.
    func applicationShouldHandleReopen(_ app: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { openSettings() }
        return true
    }

    @objc private func clicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(withTitle: "Open Clerk", action: #selector(openSettings), keyEquivalent: "")
                .target = self
            menu.addItem(.separator())
            menu.addItem(withTitle: "Quit Clerk",
                         action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            item?.menu = menu
            item?.button?.performClick(nil)
            item?.menu = nil
            return
        }
        openSettings()
    }

    @objc private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        if let w = NSApp.windows.first(where: { $0.title == "Clerk" }) {
            w.makeKeyAndOrderFront(nil)
        } else {
            NSWorkspace.shared.open(URL(string: "clerk://settings")!)
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published var data = StoreData()
    @Published var server = Server()
    @Published var note: String?

    /// Sparkle. `startingUpdater: true` means it checks on its own schedule as
    /// well as when the button is pressed.
    let updater = SPUStandardUpdaterController(startingUpdater: true,
                                               updaterDelegate: nil,
                                               userDriverDelegate: nil)

    var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }
    /// Values are plain text in this window on purpose - it is his own Mac and
    /// he has to be able to read what is stored.
    @Published var revealImport = true

    /// Made-up people, so the window can be looked at and screenshotted without
    /// real details on screen. Nothing is read from or written to the keychain
    /// while it is on. `-DemoScreen` forces it; otherwise it is a setting, so it
    /// can be switched off from inside the app rather than by relaunching.
    @Published private(set) var demo: Bool =
        CommandLine.arguments.contains("-DemoScreen")
        || UserDefaults.standard.bool(forKey: "demoMode")

    init() {
        NSLog("Clerk: model starting, demo=\(demo)")
        // `-ImportFile <path>` loads an export at start up. It exists so the APP
        // is the process that creates the keychain item: an item written by any
        // other binary belongs to that binary, and the app then gets stopped by
        // a "wants to use your confidential information" password prompt.
        if let i = CommandLine.arguments.firstIndex(of: "-ImportFile"),
           i + 1 < CommandLine.arguments.count,
           let blob = try? Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[i + 1])),
           let incoming = try? JSONDecoder().decode(StoreData.self, from: blob) {
            try? Store.save(incoming)
            NSLog("Clerk: imported \(incoming.people.count) people at start up")
        }
        data = demo ? AppModel.demoData : Store.load()
        // `-ExportFile <path>` is the other half of -ImportFile: it lets the
        // store be read and written from a script without the app handing its
        // keychain item to a second binary, which is what causes the password
        // prompt. See the note in CLAUDE.md.
        if let i = CommandLine.arguments.firstIndex(of: "-ExportFile"),
           i + 1 < CommandLine.arguments.count {
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            try? enc.encode(data).write(to: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
            NSLog("Clerk: exported \(data.people.count) people at start up")
        }
        server.start(demo: demo ? AppModel.demoData : nil)
    }

    static let demoData = StoreData(
        people: [
            Person(id: "nolan", aliases: ["Nolan", "Mo"],
                   fields: ["given_name": [FieldValue(value: "Nolan")],
                            "family_name": [FieldValue(value: "Carter")],
                            "passport_number": [FieldValue(value: "M11111111")],
                            "passport_expiry": [FieldValue(value: "2031-04-02")],
                            "dob": [FieldValue(value: "1901-01-01")],
                            "known_traveler": [FieldValue(value: "KT0001")],
                            "email": [FieldValue(label: "personal", value: "nolan@example.com"),
                                      FieldValue(label: "work", value: "nolan@acmecorp.com")],
                            "phone": [FieldValue(label: "mobile", value: "+1 845 555 0101"),
                                      FieldValue(label: "work", value: "+1 212 555 0199")]],
                   isDefault: true),
            Person(id: "leon", aliases: ["Leon"],
                   plain: ["given_name": "Leon", "family_name": "Carter",
                            "passport_number": "J22222222", "dob": "2012-02-02"]),
            Person(id: "freya", aliases: ["Freya", "Freya Rose"],
                   plain: ["given_name": "Freya", "family_name": "Carter",
                            "passport_number": "C33333333", "dob": "2014-03-03"]),
        ],
        shared: [:])
        .withFamilyAddress()

    /// `editing` is the person whose details were just changed. Their copy of a
    /// linked value is the one that wins when it is written to everybody.
    /// Switch between the made-up people and the real store, without a restart.
    func setDemo(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: "demoMode")
        demo = on
        data = on ? AppModel.demoData : Store.load()
        server.start(demo: on ? AppModel.demoData : nil)
        note = on ? "Showing made-up people. Your own details are untouched."
                  : "Back to your own details."
    }

    func save(editing: String? = nil) {
        if demo { note = "Demo mode: nothing was saved."; return }
        do {
            try Store.save(data, editing: editing)
            data.propagateLinked(from: editing)
            server.reload(nil)
            note = "Saved."
        } catch {
            note = error.localizedDescription
        }
    }

    func reload() {
        data = Store.load()
        server.reload()
    }

    /// Writes the whole store to a JSON file he picks, for testing or a backup.
    func export() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "clerk-export.json"
        panel.allowedContentTypes = [.json]
        panel.message = "This file holds every value in plain text. Keep it somewhere safe."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            // The AI key is left out. An export gets mailed about and pasted
            // into bug reports, and a key in one is a key handed away.
            var safe = data
            safe.jevKey = ""
            try enc.encode(safe).write(to: url)
            note = "Exported to \(url.lastPathComponent). The AI key was left out."
        } catch {
            note = error.localizedDescription
        }
    }

    /// Reads a file written by Export back in, replacing what is stored.
    func importFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let incoming = try JSONDecoder().decode(StoreData.self, from: Data(contentsOf: url))
            data = incoming
            save()
            note = "Loaded \(incoming.people.count) people from \(url.lastPathComponent)."
        } catch {
            note = "That file does not look like an Clerk export: \(error.localizedDescription)"
        }
    }


    var openAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                newValue ? try SMAppService.mainApp.register()
                         : try SMAppService.mainApp.unregister()
            } catch {
                note = error.localizedDescription
            }
            objectWillChange.send()
        }
    }
}
