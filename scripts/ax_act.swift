import Foundation
import ApplicationServices

// Swift AX driver — dump / press-by-description / setvalue, with timeouts.
// Usage:
//   swift ax_act.swift <pid> dump [maxDepth] [roleFilter]
//   swift ax_act.swift <pid> press <descSubstring>
//   swift ax_act.swift <pid> setvalue <descSubstring> <value>
//   swift ax_act.swift <pid> presspos <x> <y>   (press element at position)

func attr(_ el: AXUIElement, _ key: String) -> CFTypeRef? {
    var out: CFTypeRef?
    let err = AXUIElementCopyAttributeValue(el, key as CFString, &out)
    return err == .success ? out : nil
}

func strAttr(_ el: AXUIElement, _ key: String) -> String {
    guard let v = attr(el, key) else { return "" }
    return v as? String ?? ""
}

func posOf(_ el: AXUIElement) -> (Int, Int) {
    guard let pos = attr(el, kAXPositionAttribute), CFGetTypeID(pos) == AXValueGetTypeID(),
          AXValueGetType(pos as! AXValue) == .cgPoint else { return (-1, -1) }
    var p = CGPoint.zero; AXValueGetValue(pos as! AXValue, .cgPoint, &p)
    return (Int(p.x), Int(p.y))
}

func sizeOf(_ el: AXUIElement) -> (Int, Int) {
    guard let sz = attr(el, kAXSizeAttribute), CFGetTypeID(sz) == AXValueGetTypeID(),
          AXValueGetType(sz as! AXValue) == .cgSize else { return (-1, -1) }
    var s = CGSize.zero; AXValueGetValue(sz as! AXValue, .cgSize, &s)
    return (Int(s.width), Int(s.height))
}

var allElements: [AXUIElement] = []

func collect(_ el: AXUIElement) {
    allElements.append(el)
    if let children = attr(el, kAXChildrenAttribute) as? [AXUIElement] {
        for c in children { collect(c) }
    }
}

func walk(_ el: AXUIElement, depth: Int, maxDepth: Int, filter: String?, lines: inout [String]) {
    guard depth <= maxDepth else { return }
    let role = strAttr(el, kAXRoleAttribute)
    if filter == nil || role == filter {
        let (px, py) = posOf(el); let (sx, sy) = sizeOf(el)
        let desc = strAttr(el, kAXDescriptionAttribute)
        let title = strAttr(el, kAXTitleAttribute)
        let value = strAttr(el, kAXValueAttribute)
        let indent = String(repeating: "  ", count: depth)
        lines.append("\(indent)\(role)|d=\(desc)|t=\(title)|v=\(value)|p=\(px),\(py)|s=\(sx)x\(sy)")
    }
    if let children = attr(el, kAXChildrenAttribute) as? [AXUIElement] {
        for c in children { walk(c, depth: depth + 1, maxDepth: maxDepth, filter: filter, lines: &lines) }
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
    guard let windows = attr(app, kAXWindowsAttribute) as? [AXUIElement] else {
        print("no windows / AX denied"); exit(1)
    }
    print("== windows: \(windows.count)")
    var lines: [String] = []
    for (i, win) in windows.enumerated() {
        print("-- window \(i + 1): \(strAttr(win, kAXTitleAttribute))")
        walk(win, depth: 1, maxDepth: maxDepth, filter: filter, lines: &lines)
    }
    print(lines.joined(separator: "\n"))
} else if mode == "press" || mode == "setvalue" {
    let target = args[3]
    let newValue = args.count > 4 ? args[4] : ""
    guard let windows = attr(app, kAXWindowsAttribute) as? [AXUIElement] else {
        print("no windows"); exit(1)
    }
    allElements = []
    for w in windows { collect(w) }
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
    let (px, py) = posOf(el); let (sx, sy) = sizeOf(el)
    print("target: \(strAttr(el, kAXRoleAttribute)) d=\(strAttr(el, kAXDescriptionAttribute)) t=\(strAttr(el, kAXTitleAttribute)) v=\(strAttr(el, kAXValueAttribute)) p=\(px),\(py) s=\(sx)x\(sy)")
    if mode == "press" {
        let err = AXUIElementPerformAction(el, kAXPressAction as CFString)
        print(err == .success ? "PRESSED" : "PRESS FAILED: \(err.rawValue)")
    } else {
        let err = AXUIElementSetAttributeValue(el, kAXValueAttribute as CFString, newValue as CFTypeRef)
        print(err == .success ? "SET" : "SET FAILED: \(err.rawValue)")
    }
} else if mode == "presspos" {
    guard args.count >= 5, let x = Int(args[3]), let y = Int(args[4]) else { exit(2) }
    guard let windows = attr(app, kAXWindowsAttribute) as? [AXUIElement] else { print("no windows"); exit(1) }
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
}
