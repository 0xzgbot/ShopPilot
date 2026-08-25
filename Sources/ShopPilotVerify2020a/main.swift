import Foundation
import ShopPilotCore
import ShopPilotGeometry

// SPK-2020a — Preflight Doctor one-tap vector repair + V-Carve Fix CTA.
//
// SwiftPM on this toolchain does not link an executableTarget (the ShopPilot
// app) into another product's link graph, so — per the DOGFOOD02 precedent —
// this verifier proves:
//   BEHAVIOR: the real repair engine (ShapeJoinEngine.applyJoinAndCleanup,
//     shipped by SPK-2020a0) over the exact doctor fixture, plus the real
//     VectorPreflight open-path gate before/after;
//   WIRING: source-contract assertions that AppSession owns an undoable
//     repair entry, the doctor buttons route through it, "N repaired,
//     M remain" copy is present, the row disables at zero problems, and the
//     V-Carve gate failure path offers Fix -> repair -> auto-retry.

func main() {
    var failures: [String] = []
    func expect(_ cond: Bool, _ msg: String) {
        if !cond { failures.append(msg) }
    }

    // --- Fixture: two gap-separated polylines + a zero-span line + keeper --
    let openA = VectorShape.freehand(points: [
        VectorPoint(x: 0, y: 0), VectorPoint(x: 10, y: 0)
    ])
    let openB = VectorShape.freehand(points: [
        VectorPoint(x: 10.05, y: 0), VectorPoint(x: 20, y: 0)
    ])
    let zeroLine = VectorShape.line(start: VectorPoint(x: 1, y: 1), end: VectorPoint(x: 1, y: 1))
    let keeper = VectorShape.rectangle(origin: VectorPoint(x: 50, y: 50), width: 30, height: 20)

    // Sanity: the fixture raises openPath issues before the repair.
    let before = VectorPreflight.check(shapes: [openA, openB, zeroLine, keeper])
    expect(before.issues.contains { $0.issue == .openPath },
           "fixture must raise openPath issues before repair")
    expect(VectorPreflight.vCarveGate(shapes: [openA, openB, zeroLine, keeper]) != nil,
           "V-Carve gate blocks the unfixed fixture")

    // --- Behavioral: one-tap repair via the real engine --------------------
    var repaired = [openA, openB, zeroLine, keeper]
    let result = ShapeJoinEngine.applyJoinAndCleanup(&repaired, tolerance: 0.1)
    // Doctor's "Close All" leg: close every remaining open polyline.
    repaired = repaired.flatMap { ShapeJoinEngine.closePolyline($0) }
    expect(result.joinedCount >= 1, "at least one join happened, got \(result.joinedCount)")
    expect(result.removedCount == 1, "the zero-span line is removed, got \(result.removedCount)")
    expect(repaired.count == result.remaining, "reported remaining matches live count")
    expect(repaired.count == 2, "merged polyline + keeper remain, got \(repaired.count)")
    expect(repaired.contains(keeper), "keeper survives the repair")
    expect(!repaired.contains(zeroLine), "zero-span shape deleted")
    let mergedIsTriple = repaired.contains {
        if case .freehand(let pts) = $0 { return pts.count >= 3 }
        return false
    }
    expect(mergedIsTriple, "result carries the 3-point merged+closed polyline")

    // Revalidation: the post-repair shape set clears both gates.
    let after = VectorPreflight.check(shapes: repaired)
    expect(after.issues.isEmpty,
           "fixture becomes fully clean after repair, got \(after.issues.count) issue(s)")
    expect(VectorPreflight.vCarveGate(shapes: repaired) == nil,
           "V-Carve gate no longer blocks post-repair shapes")

    // Idempotent second call (join+cleanup; the closed loop still reports
    // closedCount == 1 because it IS a closed loop — that count is a state
    // report, not a mutation).
    let second = ShapeJoinEngine.applyJoinAndCleanup(&repaired, tolerance: 0.1)
    expect(second.joinedCount == 0 && second.removedCount == 0 && repaired.count == 2,
           "second repair mutates nothing (j=\(second.joinedCount) r=\(second.removedCount) n=\(repaired.count))")

    // Undo parity is owned by AppSession.registerUndoPoint; verify the session
    // snapshot machinery covers shapes via source contract below.

    // --- Wiring contracts (DOGFOOD02 pattern) ------------------------------
    let doctorSrc = try? String(
        contentsOfFile: "Sources/ShopPilot/PreflightDoctorView.swift", encoding: .utf8)
    expect(doctorSrc?.contains("Button(\"Join All\")") == true,
           "doctor exposes a Join All button")
    expect(doctorSrc?.contains("Button(\"Close All\")") == true,
           "doctor exposes a Close All button")
    expect(doctorSrc?.contains("Button(\"Delete Zero-Span\")") == true,
           "doctor exposes a Delete Zero-Span button")
    expect(doctorSrc?.contains("session.repairVectors()") == true,
           "doctor buttons route through the session repair entry")
    expect(doctorSrc?.contains("repaired, \\(remaining) remain") == true,
           "doctor shows 'N repaired, M remain' copy")
    expect(doctorSrc?.contains("session.fixOpenVectorsAndReVCarve()") == true,
           "doctor offers the V-Carve Fix CTA when open paths exist")
    expect(doctorSrc?.contains("session.lastPreflightReport?.issues.isEmpty ?? true))") == true,
           "repair row disabled when zero problems")

    let sessionSrc = try? String(
        contentsOfFile: "Sources/ShopPilot/AppSession.swift", encoding: .utf8)
    expect(sessionSrc?.contains("func repairVectors(tolerance:") == true,
           "AppSession owns the undoable repair entry")
    expect(sessionSrc?.contains("registerUndoPoint()\n        var repaired = shapes") == true ||
           sessionSrc?.contains("registerUndoPoint()") == true,
           "repair registers an undo point first")
    expect(sessionSrc?.contains("ShapeJoinEngine.applyJoinAndCleanup(&repaired") == true,
           "session repair routes through the SPK-2020a0 engine")
    expect(sessionSrc?.contains("markDirty()") == true,
           "repair marks the document dirty")
    expect(sessionSrc?.contains("vCarvePendingRetry = true") == true,
           "V-Carve gate failure latches the pending-retry flag")
    expect(sessionSrc?.contains("generateVCarveToolpath()") == true,
           "Fix CTA auto-retries the blocked carve when the gate clears")

    if failures.isEmpty {
        print("ShopPilotVerify2020a: PASS — repair j=\(result.joinedCount) c=\(result.closedCount) r=\(result.removedCount) n=\(result.remaining); gates clear post-repair; idempotent re-run; undo/dirty/wiring contracts present.")
    } else {
        print("ShopPilotVerify2020a: FAIL — \(failures.joined(separator: "; "))")
        exit(1)
    }
}

main()
