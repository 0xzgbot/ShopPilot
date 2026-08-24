import Foundation
import ApplicationServices
import AppKit
import CoreGraphics

// Swift AX driver — dump / press-by-description / setvalue, with timeouts.
// Usage:
//   swift ax_act.swift <pid> dump [maxDepth] [roleFilter]
//   swift ax_act.swift <pid> press <descSubstring> [window|menu] [role]
//   swift ax_act.swift <pid> setvalue <descSubstring> <value>
//   swift ax_act.swift <pid> presspos <x> <y>   (press element at position)
//   swift ax_act.swift <pid> closewin <index>   (press window N's close button)

func attr(_ el: AXUIElement, _ key: String) -> CFTypeRef? {
    var out: CFTypeRef?
    let err = AXUIElementCopyAttributeValue(el, key as CFString, &out)
    return err == .success ? out : nil
}

/// SPK-DOGFOOD-05 — safe children fetch. `as? [AXUIElement]` on a CFArray can
/// trap (SIGILL in the JIT-interpreted script) when the array holds elements
/// that are not all AXUIElement (deep Design-stage trees expose heterogeneous
/// refs at depth ≥7). Bridge element-wise with a type-ID check instead.
func childrenOf(_ el: AXUIElement) -> [AXUIElement] {
    guard let raw = attr(el, kAXChildrenAttribute) else { return [] }
    return axElementArray(raw)
}

/// Safe CFArray → [AXUIElement]: element-wise type-ID check, never traps on
/// heterogeneous arrays (windows attribute, children, etc.).
func axElementArray(_ raw: CFTypeRef) -> [AXUIElement] {
    guard CFGetTypeID(raw) == CFArrayGetTypeID() else { return [] }
    let arr = raw as! CFArray
    var out: [AXUIElement] = []
    out.reserveCapacity(CFArrayGetCount(arr))
    for i in 0..<CFArrayGetCount(arr) {
        let unmanaged: CFTypeRef = unsafeBitCast(CFArrayGetValueAtIndex(arr, i), to: CFTypeRef.self)
        if CFGetTypeID(unmanaged) == AXUIElementGetTypeID() {
            out.append(unmanaged as! AXUIElement)
        }
    }
    return out
}

/// Safe single-element cast: returns nil unless the ref really is an AXUIElement.
func asAXUIElement(_ raw: CFTypeRef?) -> AXUIElement? {
    guard let raw, CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
    let typed: AXUIElement = unsafeBitCast(raw, to: AXUIElement.self)
    return typed
}

func strAttr(_ el: AXUIElement, _ key: String) -> String {
    guard let v = attr(el, key) else { return "" }
    return v as? String ?? ""
}

func posOf(_ el: AXUIElement) -> (Int, Int) {
    // SPK-DOGFOOD-05 — bitcast after type-ID check. `as! AXValue` trapped
    // (SIGILL) on deep-tree elements whose position value bridged oddly.
    guard let pos = attr(el, kAXPositionAttribute),
          CFGetTypeID(pos) == AXValueGetTypeID() else { return (-1, -1) }
    let value: AXValue = unsafeBitCast(pos, to: AXValue.self)
    guard AXValueGetType(value) == .cgPoint else { return (-1, -1) }
    var p = CGPoint.zero
    AXValueGetValue(value, .cgPoint, &p)
    return (Int(p.x), Int(p.y))
}

func sizeOf(_ el: AXUIElement) -> (Int, Int) {
    guard let sz = attr(el, kAXSizeAttribute),
          CFGetTypeID(sz) == AXValueGetTypeID() else { return (-1, -1) }
    let value: AXValue = unsafeBitCast(sz, to: AXValue.self)
    guard AXValueGetType(value) == .cgSize else { return (-1, -1) }
    var s = CGSize.zero
    AXValueGetValue(value, .cgSize, &s)
    return (Int(s.width), Int(s.height))
}

var allElements: [AXUIElement] = []

func collect(_ el: AXUIElement) {
    allElements.append(el)
    for c in childrenOf(el) { collect(c) }
}

/// Depth-limited collect — the menu bar's Services submenu can hang the app's
/// AX handler when the service provider (e.g. Instruments' "File Activity")
/// is not responding, so presses must never descend past top-level menu items
/// and their direct submenu items (depth 2).
func collectLimited(_ el: AXUIElement, depth: Int, maxDepth: Int) {
    guard depth <= maxDepth else { return }
    allElements.append(el)
    for c in childrenOf(el) { collectLimited(c, depth: depth + 1, maxDepth: maxDepth) }
}

/// Window close/cancel buttons — needed for Settings-window dismiss (the
/// "no Cancel in the form" bug class). Menubar collection happens separately
/// so presses can be scoped (window vs menu) — the Services submenu's
/// "File Activity" item must never shadow the top-level "File" menu.
func collectWindowChrome(_ windows: [AXUIElement]) {
    for w in windows {
        if let close = attr(w, kAXCloseButtonAttribute) {
            if let c = asAXUIElement(close) { collect(c) }
        }
        if let cancel = attr(w, kAXCancelButtonAttribute), let c = asAXUIElement(cancel) {
            collect(c)
        }
    }
}

func walk(_ el: AXUIElement, depth: Int, maxDepth: Int, filter: String?, lines: inout [String]) {
    // SPK-DOGFOOD-05 — iterative stack instead of recursion: deep Design-stage
    // trees at default depth 8 crashed the interpreted script (SIGILL); an
    // explicit LIFO also bounds memory deterministically.
    var stack: [(el: AXUIElement, depth: Int)] = [(el, depth)]
    while let (node, d) = stack.popLast() {
        guard d <= maxDepth else { continue }
        let role = strAttr(node, kAXRoleAttribute)
        if filter == nil || role == filter {
            // SPK-DOGFOOD-05 — position/size AX queries on deep-tree elements
            // (menu containers, canvas internals at depth >=7) can trap the
            // process (SIGILL inside posOf). Roles/titles carry the evidence
            // value; only query p/s for concrete control roles.
            // Geometry queries are depth-gated: some canvas-internal elements
            // at depth >=7 poison the AX position/size query (server-side
            // SIGILL). Roles/titles/values remain for ALL depths.
            let queryGeometry = d <= 5 && ["AXButton", "AXStaticText", "AXCheckBox",
                                 "AXRadioButton", "AXTextField", "AXPopUpButton",
                                 "AXMenuButton", "AXSlider", "AXImage", "AXMenuItem",
                                 "AXMenuBarItem"].contains(role)
            let (px, py): (Int, Int) = queryGeometry ? posOf(node) : (0, 0)
            let (sx, sy): (Int, Int) = queryGeometry ? sizeOf(node) : (0, 0)
            let desc = strAttr(node, kAXDescriptionAttribute)
            let title = strAttr(node, kAXTitleAttribute)
            let value = strAttr(node, kAXValueAttribute)
            let indent = String(repeating: "  ", count: d)
            lines.append("\(indent)\(role)|d=\(desc)|t=\(title)|v=\(value)|p=\(px),\(py)|s=\(sx)x\(sy)")
        }
        for c in childrenOf(node).reversed() {
            stack.append((c, d + 1))
        }
    }
}

let args = CommandLine.arguments
guard args.count >= 3, let pid = pid_t(args[1]) else {
    print("usage: ax_act <pid> dump|press|setvalue|presspos ..."); exit(2)
}
let app = AXUIElementCreateApplication(pid)
AXUIElementSetMessagingTimeout(app, 3.0)
let mode = args[2]

if mode == "dump" {
    let maxDepth = args.count > 3 ? Int(args[3]) ?? 8 : 8
    let filter = args.count > 4 ? args[4] : nil
    let windows = axElementArray(attr(app, kAXWindowsAttribute) ?? kCFNull as CFTypeRef)
    guard !windows.isEmpty else {
        // Only a genuinely untrusted process is "AX denied". A trusted
        // client querying a BUSY app (main thread generating toolpaths)
        // also gets nil here — that is NOT a TCC denial and must never
        // be labeled as one (SPK-UI-BUG-03 / driver hardening).
        if !AXIsProcessTrusted() { print("AX DENIED"); exit(1) }
        print("no windows (app busy or none)"); exit(1)
    }
    print("== windows: \(windows.count)")
    var lines: [String] = []
    for (i, win) in windows.enumerated() {
        var closeInfo = "close=none"
        if let closeRaw = attr(win, kAXCloseButtonAttribute) {
            guard let close = asAXUIElement(closeRaw) else { continue }
            let (cx, cy) = posOf(close)
            closeInfo = "close=d=\(strAttr(close, kAXDescriptionAttribute))|t=\(strAttr(close, kAXTitleAttribute))|p=\(cx),\(cy)"
        }
        print("-- window \(i + 1): \(strAttr(win, kAXTitleAttribute)) [\(closeInfo)]")
        walk(win, depth: 1, maxDepth: maxDepth, filter: filter, lines: &lines)
    }
    if let mb = attr(app, kAXMenuBarAttribute) {
        print("-- menubar")
        if let mb = asAXUIElement(mb) {
        walk(mb, depth: 1, maxDepth: min(maxDepth, 4), filter: filter, lines: &lines)
    }
    }
    print(lines.joined(separator: "\n"))
} else if mode == "press" {
    let target = args[3]
    let scope = args.count > 4 ? args[4] : nil
    let roleFilter = args.count > 5 ? args[5] : nil
    let windows = axElementArray(attr(app, kAXWindowsAttribute) ?? kCFNull as CFTypeRef)
    guard !windows.isEmpty else {
        if !AXIsProcessTrusted() { print("AX DENIED"); exit(1) }
        print("no windows (app busy or none)"); exit(1)
    }
    allElements = []
    if scope != "menu" {
        for w in windows { collect(w) }
        collectWindowChrome(windows)
    }
    if scope != "window", let mb = attr(app, kAXMenuBarAttribute) {
        // depth 3 reaches every menu item (menu bar item -> AXMenu -> item);
        // the Services submenu items ("File Activity", dead provider) sit at
        // depth 5 and must never be collected.
        if let mbEl = asAXUIElement(mb) { collectLimited(mbEl, depth: 0, maxDepth: 3) }
    }
    var hit: AXUIElement? = nil
    for el in allElements {
        if let roleFilter, strAttr(el, kAXRoleAttribute) != roleFilter { continue }
        let desc = strAttr(el, kAXDescriptionAttribute)
        let title = strAttr(el, kAXTitleAttribute)
        let value = strAttr(el, kAXValueAttribute)
        if desc.contains(target) || title.contains(target) || value.contains(target) {
            hit = el; break
        }
    }
    guard let el = hit else {
        print("NOT FOUND: \(target)"); exit(3)
    }
    let (px, py) = posOf(el); let (sx, sy) = sizeOf(el)
    print("target: \(strAttr(el, kAXRoleAttribute)) d=\(strAttr(el, kAXDescriptionAttribute)) t=\(strAttr(el, kAXTitleAttribute)) v=\(strAttr(el, kAXValueAttribute)) p=\(px),\(py) s=\(sx)x\(sy)")
    if mode == "press" {
        let err = AXUIElementPerformAction(el, kAXPressAction as CFString)
        print(err == .success ? "PRESSED" : "PRESS FAILED: \(err.rawValue)")
    }
} else if mode == "setvalue" {
    let target = args[3]
    let newValue = args.count > 4 ? args[4] : ""
    let windows = axElementArray(attr(app, kAXWindowsAttribute) ?? kCFNull as CFTypeRef)
    guard !windows.isEmpty else {
        print("no windows"); exit(1)
    }
    allElements = []
    for w in windows { collect(w) }
    collectWindowChrome(windows)
    var hit: AXUIElement? = nil
    for el in allElements {
        let desc = strAttr(el, kAXDescriptionAttribute)
        let title = strAttr(el, kAXTitleAttribute)
        let value = strAttr(el, kAXValueAttribute)
        if desc.contains(target) || title.contains(target) || value.contains(target) {
            hit = el; break
        }
    }
    guard let el = hit else {
        print("NOT FOUND: \(target)"); exit(3)
    }
    // Sliders expect a numeric AXValue (CFNumber), not a string.
    let cfValue: CFTypeRef = Double(newValue).map(NSNumber.init) ?? (newValue as CFTypeRef)
    let err = AXUIElementSetAttributeValue(el, kAXValueAttribute as CFString, cfValue)
    print(err == .success ? "SET" : "SET FAILED: \(err.rawValue)")
} else if mode == "activate" {
    guard let pid = pid_t(args[1]) else { exit(2) }
    guard let app = NSRunningApplication(processIdentifier: pid) else {
        print("NO APP"); exit(3)
    }
    print(app.activate(options: []) ? "ACTIVATED" : "ACTIVATE FAILED")
} else if mode == "frontmost" {
    guard let pid = pid_t(args[1]) else { exit(2) }
    let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
    print(front == pid ? "FRONTMOST" : "NOT FRONTMOST")
} else if mode == "closewin" {
    guard args.count >= 4, let idx = Int(args[3]) else {
        print("usage: ax_act <pid> closewin <index>"); exit(2)
    }
    let windows = axElementArray(attr(app, kAXWindowsAttribute) ?? kCFNull as CFTypeRef)
    guard !windows.isEmpty else {
        print("no windows"); exit(1)
    }
    guard idx >= 1, idx <= windows.count else {
        print("NO WINDOW \(idx) of \(windows.count)"); exit(3)
    }
    guard let closeRaw = attr(windows[idx - 1], kAXCloseButtonAttribute),
          let close = asAXUIElement(closeRaw) else {
        print("NO CLOSE BUTTON"); exit(3)
    }
    let err = AXUIElementPerformAction(close, kAXPressAction as CFString)
    print(err == .success ? "CLOSED" : "CLOSE FAILED: \(err.rawValue)")
} else if mode == "presskey" {
    // presskey <key> — simulate a key press (used for Escape to dismiss panels)
    guard args.count >= 4 else { exit(2) }
    let key = args[3]
    var keyCode: CGKeyCode = 53 // Escape by default
    switch key.lowercased() {
    case "escape", "esc": keyCode = 53
    case "return", "enter": keyCode = 36
    case "tab": keyCode = 48
    default: keyCode = 53
    }
    let src = CGEventSource(stateID: .hidSystemState)
    let keyDown = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true)
    let keyUp = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false)
    keyDown?.post(tap: .cghidEventTap)
    keyUp?.post(tap: .cghidEventTap)
    print("KEY PRESSED: \(key)")
} else if mode == "presspos" {
    guard args.count >= 5, let x = Int(args[3]), let y = Int(args[4]) else { exit(2) }
    let windows = axElementArray(attr(app, kAXWindowsAttribute) ?? kCFNull as CFTypeRef)
    guard !windows.isEmpty else { print("no windows"); exit(1) }
    allElements = []
    for w in windows { collect(w) }
    var best: AXUIElement? = nil
    var bestDist = Int.max
    for el in allElements {
        let (px, py) = posOf(el); let (sx, sy) = sizeOf(el)
        if px <= x && py <= y && px + sx >= x && py + sy >= y {
            let d = (x - px) + (y - py)
            if d < bestDist { bestDist = d; best = el }
        }
    }
    guard let el = best else { print("NO ELEMENT AT \(x),\(y)"); exit(3) }
    print("presspos hit: \(strAttr(el, kAXRoleAttribute)) d=\(strAttr(el, kAXDescriptionAttribute)) t=\(strAttr(el, kAXTitleAttribute)) v=\(strAttr(el, kAXValueAttribute)) p=\(posOf(el))")
    let err = AXUIElementPerformAction(el, kAXPressAction as CFString)
    print(err == .success ? "PRESSED" : "PRESS FAILED: \(err.rawValue)")
} else if mode == "setvaluepos" {
    // setvaluepos <x> <y> <value> — hit-test the element at (x,y) (like
    // presspos) and set its AXValue. Needed for sliders, which expose no
    // description/title to match by substring.
    guard args.count >= 6, let x = Int(args[3]), let y = Int(args[4]) else { exit(2) }
    let newValue = args[5]
    let windows = axElementArray(attr(app, kAXWindowsAttribute) ?? kCFNull as CFTypeRef)
    guard !windows.isEmpty else { print("no windows"); exit(1) }
    allElements = []
    for w in windows { collect(w) }
    var best: AXUIElement? = nil
    var bestDist = Int.max
    for el in allElements {
        let (px, py) = posOf(el); let (sx, sy) = sizeOf(el)
        if px <= x && py <= y && px + sx >= x && py + sy >= y {
            let d = (x - px) + (y - py)
            if d < bestDist { bestDist = d; best = el }
        }
    }
    guard let el = best else { print("NO ELEMENT AT \(x),\(y)"); exit(3) }
    print("setvaluepos hit: \(strAttr(el, kAXRoleAttribute)) d=\(strAttr(el, kAXDescriptionAttribute)) t=\(strAttr(el, kAXTitleAttribute)) v=\(strAttr(el, kAXValueAttribute)) p=\(posOf(el))")
    // Sliders expect a numeric AXValue (CFNumber), not a string.
    var err: AXError = .illegalArgument
    if let d = Double(newValue) {
        var v = d
        if let num = CFNumberCreate(kCFAllocatorDefault, .doubleType, &v) {
            err = AXUIElementSetAttributeValue(el, kAXValueAttribute as CFString, num)
        }
    } else {
        err = AXUIElementSetAttributeValue(el, kAXValueAttribute as CFString, newValue as CFTypeRef)
    }
    print(err == .success ? "SET" : "SET FAILED: \(err.rawValue)")
}
