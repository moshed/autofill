import AppKit
import SwiftUI

/// Click it, press a combination, done.
///
/// It records a JavaScript `KeyboardEvent.code` rather than the character,
/// because that is what the content script compares against and it does not
/// move when the keyboard layout does.
struct ShortcutRecorder: View {
    @Binding var shortcut: Shortcut
    @State private var recording = false
    @State private var monitor: Any?
    @State private var complaint: String?

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Button(recording ? "Press a combination…" : shortcut.display) {
                recording ? stop() : start()
            }
            .font(.system(.body, design: .monospaced))
            .frame(minWidth: 150)
            .tint(recording ? .accentColor : nil)

            if let complaint {
                Text(complaint).font(.caption).foregroundStyle(.orange)
            }
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        recording = true
        complaint = nil
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { stop(); return nil }          // Escape cancels
            guard let code = Self.jsCode(for: event) else {
                complaint = "Use a letter, a digit or the space bar."
                return nil
            }
            let f = event.modifierFlags
            let new = Shortcut(code: code,
                               alt: f.contains(.option), shift: f.contains(.shift),
                               ctrl: f.contains(.control), meta: f.contains(.command))
            guard new.hasModifier else {
                // Shift alone is not a modifier here: ⇧F is just F to a text field.
                complaint = "Add ⌥, ⌃ or ⌘, or it will type into the field."
                return nil
            }
            shortcut = new
            stop()
            return nil
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    /// AppKit key code -> the `code` a browser reports.
    private static func jsCode(for event: NSEvent) -> String? {
        if event.keyCode == 49 { return "Space" }
        guard let ch = event.charactersIgnoringModifiers?.lowercased().first else { return nil }
        if ch.isLetter, ch.isASCII { return "Key" + ch.uppercased() }
        if ch.isNumber, ch.isASCII { return "Digit" + String(ch) }
        return nil
    }
}
