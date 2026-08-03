//  ShopPilotVerify0314a
//  Verify: VectorSelector.selectAll populates selection with all current vector ids.
//
//  AC:
//  - selectAll populates selection with all current vector ids

import Foundation
@testable import ShopPilotCore

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func main() throws {
    let selector = VectorSelector()

    // Add a few vectors to the available pool
    let v1 = VectorPath(id: UUID(), points: [VectorPoint(x: 0, y: 0), VectorPoint(x: 10, y: 10)])
    let v2 = VectorPath(id: UUID(), points: [VectorPoint(x: 5, y: 5), VectorPoint(x: 15, y: 15)])
    let v3 = VectorPath(id: UUID(), points: [VectorPoint(x: 100, y: 100), VectorPoint(x: 200, y: 200)])

    selector.addAvailableVector(v1)
    selector.addAvailableVector(v2)
    selector.addAvailableVector(v3)

    // Initially nothing selected
    try expect(selector.selectionCount == 0, "initially no vectors selected")
    try expect(!selector.hasSelection, "initially hasSelection is false")

    // selectAll should populate selection with all current vector ids
    selector.selectAll()

    try expect(selector.selectionCount == 3, "selectAll should select all 3 vectors, got \(selector.selectionCount)")
    try expect(selector.hasSelection, "after selectAll, hasSelection is true")

    // Verify the selected vector IDs match the available ones
    let availableIds = Set(selector.availableVectors.map { $0.id })
    let selectedIds = Set(selector.selectedSet.vectors.map { $0.id })
    try expect(availableIds == selectedIds, "selected vector ids must equal available vector ids")

    // Verify the mode was set to allInLayer
    try expect(selector.selectedSet.mode == .allInLayer, "mode should be .allInLayer after selectAll")

    // Calling selectAll again should still have all 3
    selector.selectAll()
    try expect(selector.selectionCount == 3, "re-selectAll still has all 3 vectors")

    // Clear then selectAll — should still work
    selector.clearSelection()
    try expect(selector.selectionCount == 0, "after clear, selection is empty")
    selector.selectAll()
    try expect(selector.selectionCount == 3, "after clear + selectAll, all 3 vectors selected")

    // selectAll on empty pool — selection should be empty
    let emptySelector = VectorSelector()
    emptySelector.selectAll()
    try expect(emptySelector.selectionCount == 0, "selectAll on empty pool selects nothing")
    try expect(emptySelector.selectedSet.mode == .allInLayer, "mode still set to .allInLayer even when empty")

    print("ShopPilotVerify0314a PASS — selectAll populates all vector ids correctly")
}

do {
    try main()
} catch {
    fputs("FAIL: \(error)\n", stderr)
    exit(1)
}
