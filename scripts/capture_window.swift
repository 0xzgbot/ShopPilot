#!/usr/bin/env swift
// capture_window.swift <pid> <out.png> — capture the first on-screen window
// owned by <pid> via CGWindowList + screencapture -l (window-id capture is
// reliable; region capture mixes points/pixels).
import Foundation
import CoreGraphics

let args = CommandLine.arguments
guard args.count >= 3, let pid = Int32(args[1]) else {
    print("usage: capture_window.swift <pid> <out.png>")
    exit(2)
}
let outPath = args[2]

guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
    print("no window list")
    exit(1)
}

for info in list {
    guard let owner = info[kCGWindowOwnerPID as String] as? Int32, owner == pid else { continue }
    guard let winID = info[kCGWindowNumber as String] as? Int else { continue }
    guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
    let name = info[kCGWindowName as String] as? String ?? ""
    let bounds = info[kCGWindowBounds as String] as? [String: Any] ?? [:]
    print("window id=\(winID) name=\(name) bounds=\(bounds)")
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    proc.arguments = ["-x", "-l", "\(winID)", outPath]
    try? proc.run()
    proc.waitUntilExit()
    if FileManager.default.fileExists(atPath: outPath) {
        print("captured -> \(outPath)")
        exit(0)
    }
    print("capture failed")
    exit(1)
}
print("no window for pid \(pid)")
exit(1)
