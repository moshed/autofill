// A small accessibility walker, so a control can be pressed for real rather
// than trusting the code behind it.
//
//   ui dump              print every control in the front window
//   ui click "Check now" press the first button whose title holds that text
//   ui value "Version"   print the value beside that label
//   ui select "Leon"     pick a row in a list or sidebar (a row is not a button)
//
// System Events cannot do this: `entire contents` of a SwiftUI window returns
// an EMPTY list, although the window plainly has children. Walking the tree
// through the accessibility API works.
import ApplicationServices
import AppKit

let app = "Clerk"

func attr(_ e: AXUIElement, _ key: String) -> Any? {
    var v: AnyObject?
    guard AXUIElementCopyAttributeValue(e, key as CFString, &v) == .success else { return nil }
    return v
}
func str(_ e: AXUIElement, _ key: String) -> String {
    if let s = attr(e, key) as? String { return s }
    if let n = attr(e, key) as? NSNumber { return n.stringValue }
    return ""
}
func kids(_ e: AXUIElement) -> [AXUIElement] { attr(e, kAXChildrenAttribute as String) as? [AXUIElement] ?? [] }

/// Everything a control might call itself. SwiftUI scatters the text about.
func name(_ e: AXUIElement) -> String {
    for k in [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute,
              kAXHelpAttribute, kAXPlaceholderValueAttribute] as [String] {
        let s = str(e, k)
        if !s.isEmpty { return s }
    }
    return ""
}

guard let pid = NSWorkspace.shared.runningApplications
        .first(where: { $0.localizedName == app })?.processIdentifier else {
    print("\(app) is not running"); exit(1)
}
let ax = AXUIElementCreateApplication(pid)
guard let windows = attr(ax, kAXWindowsAttribute as String) as? [AXUIElement],
      let win = windows.first else { print("no window"); exit(1) }

let mode = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "dump"
let want = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : ""
var done = false

func walk(_ e: AXUIElement, _ depth: Int) {
    if done { return }
    let role = str(e, kAXRoleAttribute as String)
    let n = name(e)
    switch mode {
    case "dump":
        if !n.isEmpty || role == "AXButton" {
            print(String(repeating: "  ", count: depth) + role + "  |  " + n)
        }
    case "click":
        // Tabs and toggles are pressable too. An icon-only tab reports the
        // SF Symbol name, e.g. the Setup tab is "Gear Shape".
        if ["AXButton", "AXRadioButton", "AXCheckBox", "AXPopUpButton"].contains(role),
           n.localizedCaseInsensitiveContains(want) {
            AXUIElementPerformAction(e, kAXPressAction as CFString)
            print("clicked: \(n)"); done = true; return
        }
    case "select":
        // A sidebar row is an AXRow holding static text, not a button, so it is
        // chosen by setting AXSelected on the row rather than by pressing it.
        if role == "AXStaticText", n.localizedCaseInsensitiveContains(want) {
            var node: AXUIElement? = e
            for _ in 0..<6 {
                guard let cur = node else { break }
                if str(cur, kAXRoleAttribute as String) == "AXRow" {
                    AXUIElementSetAttributeValue(cur, kAXSelectedAttribute as CFString,
                                                 kCFBooleanTrue)
                    print("selected: \(n)"); done = true; return
                }
                var parent: AnyObject?
                AXUIElementCopyAttributeValue(cur, kAXParentAttribute as CFString, &parent)
                node = parent as! AXUIElement?
            }
        }
    case "value":
        if n.localizedCaseInsensitiveContains(want) {
            print("\(role)  |  \(n)"); done = true; return
        }
    default: break
    }
    for c in kids(e) { walk(c, depth + 1) }
}
walk(win, 0)
if mode != "dump" && !done { print("not found: \(want)"); exit(1) }
