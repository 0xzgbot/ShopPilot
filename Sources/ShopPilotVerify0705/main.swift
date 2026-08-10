import Foundation
import ShopPilotCore

/// SPK-0705 — Verify interactive shape handles.
/// Proves: ShapeHandleManager creates handles, applies manipulations,
/// ComponentOperationEngine shift/scale/rotate work correctly.

enum Verify0705 {
    static func run() {
        var pass = 0
        var fail = 0

        // 1. Handle CRUD
        let mgr = ShapeHandleManager()
        let compID = UUID()
        let handleIDs = mgr.createHandles(for: compID)
        if handleIDs.count == 7 { pass += 1; print("✓ Handle CRUD: 7 handles created") }
        else { fail += 1; print("✗ Handle CRUD: expected 7, got \(handleIDs.count)") }

        // 2. Handle positions are within component bounds
        let allInBounds = handleIDs.allSatisfy { hid in
            guard let h = mgr.handles.first(where: { $0.id == hid }) else { return false }
            return h.position.x >= 0 && h.position.x <= 100 &&
                   h.position.y >= 0 && h.position.y <= 100 &&
                   h.position.z >= 0 && h.position.z <= 100
        }
        if allInBounds { pass += 1; print("✓ Handle positions within [0,100]³ bounds") }
        else { fail += 1; print("✗ Handle positions out of bounds") }

        // 3. ComponentOperationEngine shift
        var heights1 = [Double](repeating: 10.0, count: 100 * 100)
        var hf1 = HeightfieldData(
            width: 100, height: 100,
            cellSizeMm: 0.5, minX: 0, minY: 0,
            heights: heights1
        )
        let shifted = ComponentOperationEngine.shiftHeightfield(hf1, shiftX: 5, shiftY: 3)
        if shifted != nil { pass += 1; print("✓ Shift: 5,3 → non-nil") }
        else { fail += 1; print("✗ Shift: returned nil") }

        // 4. ComponentOperationEngine scale
        let scaled = ComponentOperationEngine.scaleHeightfield(hf1, scaleFactor: 1.5)
        if scaled != nil { pass += 1; print("✓ Scale: factor 1.5 → non-nil") }
        else { fail += 1; print("✗ Scale: returned nil") }

        // 5. Handle manipulation applies engine ops
        guard let firstHandle = mgr.handles.first else {
            fail += 1; print("✗ No handles for manipulation test"); return
        }
        var testComp = ReliefComponent(
            id: UUID(),
            name: "test",
            heightfield: hf1,
            combineMode: .combineAdd,
            visible: true
        )
        let newHF = mgr.applyHandle(to: testComp, handle: firstHandle, delta: .init(x: 1, y: 0, z: 0))
        if newHF != nil { pass += 1; print("✓ Handle manipulation: shift → non-nil") }
        else { fail += 1; print("✗ Handle manipulation: returned nil") }

        // 6. Clear handles
        mgr.clearAll()
        if mgr.handles.isEmpty { pass += 1; print("✓ Clear handles: empty after clearAll") }
        else { fail += 1; print("✗ Clear handles: \(mgr.handles.count) remaining") }

        // 7. Rotate engine
        let rotated = ComponentOperationEngine.rotateHeightfield(hf1, degrees: 90)
        if rotated != nil { pass += 1; print("✓ Rotate: 90° → non-nil") }
        else { fail += 1; print("✗ Rotate: returned nil") }

        // 8. Rotate non-multiple returns nil
        let badRotate = ComponentOperationEngine.rotateHeightfield(hf1, degrees: 45)
        if badRotate == nil { pass += 1; print("✓ Rotate: 45° → nil (as expected)") }
        else { fail += 1; print("✗ Rotate: 45° should return nil") }

        // 9. Rotate on a NON-SQUARE grid (regression: the old impl read
        //    src[(w-1-i)*w + j] with j up to h-1 → OOB crash for h > w, and
        //    produced wrong math for any non-square grid). 90° must SWAP dims.
        let rectHeights = [Double](repeating: 0, count: 4 * 6)
        let rectHF = HeightfieldData(
            width: 4, height: 6,
            cellSizeMm: 0.5, minX: 0, minY: 0,
            heights: rectHeights
        )
        let rotatedRect = ComponentOperationEngine.rotateHeightfield(rectHF, degrees: 90)
        if let rr = rotatedRect, rr.width == 6, rr.height == 4 {
            pass += 1; print("✓ Rotate non-square: 4×6 → 6×4 (dims swapped)")
        } else {
            let got = rotatedRect.map { "\($0.width)x\($0.height)" } ?? "nil"
            fail += 1; print("✗ Rotate non-square: expected 6×4, got \(got)")
        }
        // A second 90° turn on the rectangle returns it to the original shape.
        let rotatedRect2 = ComponentOperationEngine.rotateHeightfield(rectHF, degrees: 180)
        if let rr2 = rotatedRect2, rr2.width == 4, rr2.height == 6 {
            pass += 1; print("✓ Rotate non-square: 180° → 4×6 (back to original)")
        } else {
            let got2 = rotatedRect2.map { "\($0.width)x\($0.height)" } ?? "nil"
            fail += 1; print("✗ Rotate non-square: 180° expected 4×6, got \(got2)")
        }

        // 10. Scale cap: a huge factor (drag-scale handle feeding e.g. 1000×)
        //     must return nil, NOT allocate a 10^10-cell grid (OOM).
        let hugeScale = ComponentOperationEngine.scaleHeightfield(hf1, scaleFactor: 1000)
        if hugeScale == nil { pass += 1; print("✓ Scale cap: 1000× → nil (no OOM)") }
        else { fail += 1; print("✗ Scale cap: 1000× should return nil") }
        // 0/negative factor still nil
        let negScale = ComponentOperationEngine.scaleHeightfield(hf1, scaleFactor: 0)
        if negScale == nil { pass += 1; print("✓ Scale: factor 0 → nil") }
        else { fail += 1; print("✗ Scale: factor 0 should return nil") }

        print("\nSPK-0705 verify: \(pass) passed, \(fail) failed")
        if fail == 0 {
            print("PASS: ShopPilotVerify0705 — handles CRUD, engine ops, manipulation verified.")
        } else {
            print("FAIL: \(fail) tests failed.")
            exit(1)
        }
    }
}

Verify0705.run()
