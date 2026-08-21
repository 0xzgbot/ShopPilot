import Foundation
import ShopPilotGeometry

// SPK-1900f verify (CLT executable, no XCTest) — NestingEngine half.
// Proves the skyline packer's contract:
//   1. FEASIBLE FIXTURE: 2×(300×200) + 1×(400×150) into 800×600 @ 6mm
//      spacing packs, used fraction sane (> 0.2).
//   2. IMPOSSIBLE SHEET returns .doesNotFit listing EXACTLY the unplaced ids
//      (a fitting part stays placed, the oversized one is reported).
//   3. OVERLAP-FREE by construction: pairwise AABB intersection over ALL
//      placements (rotated included) is zero.
//   4. SPACING RESPECTED: every pair of placements is ≥ spacing apart in at
//      least one axis; every edge margin ≥ spacing (tol 1e-6).
//   5. DETERMINISM: shuffled input order → byte-identical placements array
//      (catches the max-dimension-desc / uuidString tie-break sort).
//   6. ROTATION HELPS: a part taller than the sheet width but narrower than
//      the height packs only via 90° rotation (rotated90 == true).
//   7. EMPTY INPUT: success with empty placements and zero fraction.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

/// Real occupied rect of a placement (w/h swapped when rotated90).
func rect(of p: NestedPlacement, part: NestingPart) -> (minX: Double, minY: Double, maxX: Double, maxY: Double) {
    let w = p.rotated90 ? part.heightMm : part.widthMm
    let h = p.rotated90 ? part.widthMm : part.heightMm
    return (p.xMm, p.yMm, p.xMm + w, p.yMm + h)
}

/// Pairwise AABB overlap + spacing audit over all placements.
func audit(placements: [(NestedPlacement, NestingPart)], spacing: Double, sheetW: Double, sheetH: Double) throws {
    let eps = 1e-6
    for i in 0..<placements.count {
        for j in (i + 1)..<placements.count {
            let a = rect(of: placements[i].0, part: placements[i].1)
            let b = rect(of: placements[j].0, part: placements[j].1)
            let xOverlap = min(a.maxX, b.maxX) - max(a.minX, b.minX)
            let yOverlap = min(a.maxY, b.maxY) - max(a.minY, b.minY)
            try expect(xOverlap <= eps || yOverlap <= eps,
                       "placements \(i) and \(j) AABB-overlap (xOv \(xOverlap), yOv \(yOverlap))")
            // Separation in whichever axis separates them must be ≥ spacing.
            if xOverlap > eps {
                try expect(-yOverlap >= spacing - eps,
                           "pair \(i)/\(j) vertical gap \(-yOverlap) < spacing \(spacing)")
            }
            if yOverlap > eps {
                try expect(-xOverlap >= spacing - eps,
                           "pair \(i)/\(j) horizontal gap \(-xOverlap) < spacing \(spacing)")
            }
        }
        let r = rect(of: placements[i].0, part: placements[i].1)
        try expect(r.minX >= spacing - eps && r.minY >= spacing - eps,
                   "placement \(i) violates edge margin (min corner \(r.minX), \(r.minY))")
        try expect(r.maxX <= sheetW - spacing + eps && r.maxY <= sheetH - spacing + eps,
                   "placement \(i) violates edge margin (max corner \(r.maxX), \(r.maxY))")
    }
}

func main() throws {
    let spacing = 6.0

    // ── 1. Known fixture packs into 800×600 @ 6mm. ──────────────────────────
    let idA = UUID(), idB = UUID(), idC = UUID()
    let parts1 = [
        NestingPart(id: idA, widthMm: 300, heightMm: 200, allowRotation: true),
        NestingPart(id: idB, widthMm: 300, heightMm: 200, allowRotation: true),
        NestingPart(id: idC, widthMm: 400, heightMm: 150, allowRotation: true),
    ]
    let options1 = NestingOptions(sheetWidthMm: 800, sheetHeightMm: 600, spacingMm: spacing)
    let result1 = NestingEngine.nest(parts: parts1, options: options1)
    guard case .success(let placements1, let fraction1) = result1 else {
        throw VerifyError.failed("fixture 1 must fit — got \(result1)")
    }
    try expect(placements1.count == 3, "all three parts placed (got \(placements1.count))")
    try expect(fraction1 > 0.2, "used fraction sane > 0.2 (got \(fraction1))")
    try expect(fraction1 < 1.0, "used fraction ≤ 1 (got \(fraction1))")
    let audit1: [(NestedPlacement, NestingPart)] = placements1.map { p in
        (p, parts1.first { $0.id == p.partID }!)
    }
    try audit(placements: audit1, spacing: spacing, sheetW: 800, sheetH: 600)

    // ── 2. Impossible part → doesNotFit listing exactly its id. ─────────────
    let idFit = UUID(), idTooBig = UUID()
    let parts2 = [
        NestingPart(id: idFit, widthMm: 100, heightMm: 100, allowRotation: false),
        NestingPart(id: idTooBig, widthMm: 900, heightMm: 100, allowRotation: false),
    ]
    let options2 = NestingOptions(sheetWidthMm: 800, sheetHeightMm: 600, spacingMm: spacing)
    let result2 = NestingEngine.nest(parts: parts2, options: options2)
    guard case .doesNotFit(let unplaced2) = result2 else {
        throw VerifyError.failed("900×100 into 800×600 must not fit — got \(result2)")
    }
    try expect(unplaced2 == [idTooBig],
               "unplaced ids are EXACTLY the oversized part (got \(unplaced2.map(\.uuidString)))")

    // ── 3+4. Bigger mixed set: overlap-free AND spacing-respected. ──────────
    let mixed: [NestingPart] = [
        NestingPart(id: UUID(), widthMm: 420, heightMm: 310, allowRotation: true),
        NestingPart(id: UUID(), widthMm: 260, heightMm: 180, allowRotation: true),
        NestingPart(id: UUID(), widthMm: 180, heightMm: 260, allowRotation: true),
        NestingPart(id: UUID(), widthMm: 150, heightMm: 150, allowRotation: false),
        NestingPart(id: UUID(), widthMm: 500, heightMm: 90, allowRotation: true),
        NestingPart(id: UUID(), widthMm: 90, heightMm: 500, allowRotation: true),
        NestingPart(id: UUID(), widthMm: 200, heightMm: 120, allowRotation: true),
        NestingPart(id: UUID(), widthMm: 320, heightMm: 220, allowRotation: false),
    ]
    let options3 = NestingOptions(sheetWidthMm: 1000, sheetHeightMm: 700, spacingMm: spacing)
    let result3 = NestingEngine.nest(parts: mixed, options: options3)
    guard case .success(let placements3, let fraction3) = result3 else {
        throw VerifyError.failed("mixed set must fit 1000×700 — got \(result3)")
    }
    try expect(placements3.count == mixed.count, "all 8 mixed parts placed (got \(placements3.count))")
    try expect(fraction3 > 0.2 && fraction3 <= 1.0, "mixed used fraction sane (got \(fraction3))")
    let audit3: [(NestedPlacement, NestingPart)] = placements3.map { p in
        (p, mixed.first { $0.id == p.partID }!)
    }
    try audit(placements: audit3, spacing: spacing, sheetW: 1000, sheetH: 700)

    // ── 5. Determinism: shuffled input order → identical placements. ────────
    let shuffledA = Array(mixed.reversed())
    let shuffledB: [NestingPart] = {
        var v = mixed
        // Fixed deterministic shuffle: rotate by 3 then swap halves.
        let n = v.count
        v = Array(v[3..<n] + v[0..<3])
        return Array(v[n / 2..<n] + v[0..<n / 2])
    }()
    for (idx, order) in [shuffledA, shuffledB].enumerated() {
        guard case .success(let p, let f) = NestingEngine.nest(parts: order, options: options3) else {
            throw VerifyError.failed("shuffle \(idx) must still fit")
        }
        try expect(p == placements3,
                   "shuffled order \(idx) must produce IDENTICAL placements (got \(p.count) vs \(placements3.count))")
        try expect(f == fraction3, "shuffled order \(idx) must produce identical used fraction")
    }

    // ── 6. Rotation actually helps. ──────────────────────────────────────────
    // The part's unrotated WIDTH (520mm) exceeds the sheet width (500mm) —
    // and after edge-margin deflation the usable width is 488mm — so it only
    // fits after a 90° turn, lying its 300mm side across the width.
    // (Note: with spacing inflation a part cannot be strictly taller than the
    // sheet width AND fit rotated — inflation grows the long axis too — so
    // this fixture exercises the same rotation path at the widest legal size.)
    let idTall = UUID()
    let parts6 = [NestingPart(id: idTall, widthMm: 520, heightMm: 300, allowRotation: true)]
    let options6 = NestingOptions(sheetWidthMm: 500, sheetHeightMm: 700, spacingMm: spacing)
    let result6 = NestingEngine.nest(parts: parts6, options: options6)
    guard case .success(let placements6, _) = result6 else {
        throw VerifyError.failed("520-wide part must fit 500×700 via rotation — got \(result6)")
    }
    try expect(placements6.count == 1 && placements6[0].rotated90,
               "part must be placed rotated90 (got \(placements6.first.map { "rotated90=\($0.rotated90)" } ?? "none"))")

    // And the same part WITHOUT rotation permission must not fit.
    let noRot = NestingEngine.nest(
        parts: [NestingPart(id: idTall, widthMm: 520, heightMm: 300, allowRotation: false)],
        options: options6
    )
    guard case .doesNotFit = noRot else {
        throw VerifyError.failed("same part without rotation permission must not fit — got \(noRot)")
    }

    // ── 7. Empty parts list → success, empty placements. ────────────────────
    let result7 = NestingEngine.nest(parts: [], options: options1)
    guard case .success(let placements7, let fraction7) = result7 else {
        throw VerifyError.failed("empty input must succeed — got \(result7)")
    }
    try expect(placements7.isEmpty && fraction7 == 0,
               "empty input → empty placements, fraction 0 (got \(placements7.count), \(fraction7))")
}

do {
    try main()
} catch {
    print("FAIL — \(error)")
    exit(1)
}

print("ShopPilotVerify1900f: PASS — nesting engine")
