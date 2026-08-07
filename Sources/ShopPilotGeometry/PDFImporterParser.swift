import Foundation
import ShopPilotCore

// MARK: - PDF content-stream parser (operators → VectorShape)

extension PDFImporter {

    /// Minimal tokenizer over a content stream. Tokens are numbers and
    /// operators; strings/dicts are skipped by the scanner so only path
    /// operators reach the parser.
    struct PDFToken {
        enum Kind { case number(Double), operatorName(String), other }
        let kind: Kind
    }

    struct ParseOutcome {
        let shapes: [VectorShape]
        let pathCount: Int
    }

    /// Parse one (inflated) content stream into shapes. Tracks the CTM stack
    /// (`cm`), current subpath, and closes/emits on painting operators.
    static func parseContentStream(_ stream: Data, scale: Double) -> ParseOutcome {
        guard let text = String(data: stream, encoding: .ascii) else {
            return ParseOutcome(shapes: [], pathCount: 0)
        }
        var shapes: [VectorShape] = []
        var pathCount = 0

        // Current path state (in user space, transformed by the CTM at emit).
        var currentPoints: [VectorPoint] = []
        var subpathStart: VectorPoint?
        var currentPoint: VectorPoint?

        var ctmStack: [[[Double]]] = [identityMatrix]
        var ctm = identityMatrix

        let tokens = tokenize(text)
        var i = 0
        while i < tokens.count {
            guard case .operatorName(let op) = tokens[i].kind else { i += 1; continue }
            switch op {
            case "m", "l":
                if let pt = argPoint(tokens, at: i - 2, scale: scale, ctm: ctm) {
                    if op == "m" {
                        currentPoints = [pt]
                        subpathStart = pt
                    } else if !currentPoints.isEmpty {
                        currentPoints.append(pt)
                    }
                    currentPoint = pt
                }
                i += 1
            case "c", "v", "y":
                // Cubic Bézier → sample into the current subpath.
                let args = argPoints(tokens, at: i, op: op, scale: scale, ctm: ctm)
                if args.count == 3, let cp0 = currentPoint, !currentPoints.isEmpty {
                    currentPoints.append(contentsOf: sampleBezier(cp0, args[0], args[1], args[2], steps: 12))
                    currentPoint = args[2]
                }
                i += 1
            case "re":
                if let rect = argRect(tokens, at: i, scale: scale, ctm: ctm) {
                    shapes.append(rect)
                    pathCount += 1
                }
                i += 1
            case "h":
                if !currentPoints.isEmpty, let start = subpathStart {
                    currentPoints.append(start)
                    currentPoint = start
                }
                i += 1
            case "S", "s", "f", "F", "B", "b", "n":
                // Painting operator: emit the accumulated subpath (if any).
                if currentPoints.count >= 2 {
                    shapes.append(.freehand(points: currentPoints))
                    pathCount += 1
                }
                currentPoints = []
                subpathStart = nil
                currentPoint = nil
                i += 1
            case "q":
                ctmStack.append(ctm)
                i += 1
            case "Q":
                if ctmStack.count > 1 {
                    ctm = ctmStack.removeLast()
                }
                i += 1
            case "cm":
                if let m = argMatrix(tokens, at: i) {
                    ctm = multiply(m, ctm)
                }
                i += 1
            case "BT", "ET", "Td", "TD", "Tm", "T*", "Tj", "TJ", "'", "\"":
                // Text block — skipped (not cuttable vectors).
                i += 1
            default:
                i += 1
            }
        }
        return ParseOutcome(shapes: shapes, pathCount: pathCount)
    }

    // MARK: - Tokenizer

    static func tokenize(_ text: String) -> [PDFToken] {
        var tokens: [PDFToken] = []
        var current = ""
        var inLiteralString = false
        var inHexString = false

        func flush() {
            let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { current = ""; return }
            if let n = Double(trimmed) {
                tokens.append(PDFToken(kind: .number(n)))
            } else if trimmed.range(of: #"^[a-zA-Z*'"]+$"#, options: .regularExpression) != nil {
                tokens.append(PDFToken(kind: .operatorName(trimmed)))
            } else {
                tokens.append(PDFToken(kind: .other))
            }
            current = ""
        }

        var index = text.startIndex
        while index < text.endIndex {
            let ch = text[index]
            if inLiteralString {
                if ch == "\\" {
                    let next = text.index(after: index)
                    if next < text.endIndex { index = next }
                } else if ch == ")" {
                    inLiteralString = false
                }
                index = text.index(after: index)
                continue
            }
            if inHexString {
                if ch == ">" { inHexString = false }
                index = text.index(after: index)
                continue
            }
            switch ch {
            case "(", "[":
                inLiteralString = true
                flush()
            case "<":
                inHexString = true
                flush()
            case "]", ")", ">":
                flush()
            case " ", "\n", "\r", "\t":
                flush()
            default:
                current.append(ch)
            }
            index = text.index(after: index)
        }
        flush()
        return tokens
    }

    // MARK: - Args

    static let identityMatrix: [[Double]] = [[1, 0, 0], [0, 1, 0], [0, 0, 1]]

    /// Point from the two numbers before an `m`/`l` at token index `i`.
    static func argPoint(_ tokens: [PDFToken], at i: Int, scale: Double, ctm: [[Double]]) -> VectorPoint? {
        guard i >= 0, i + 1 < tokens.count,
              case .number(let x) = tokens[i].kind,
              case .number(let y) = tokens[i + 1].kind else { return nil }
        return transform(x: x, y: y, ctm: ctm, scale: scale)
    }

    /// Three control points for `c`/`v`/`y` (operand count differs per op).
    static func argPoints(_ tokens: [PDFToken], at i: Int, op: String, scale: Double, ctm: [[Double]]) -> [VectorPoint] {
        let operandCount = (op == "c") ? 6 : 4
        guard i - operandCount >= 0 else { return [] }
        var pts: [VectorPoint] = []
        var idx = i - operandCount
        while idx < i {
            if case .number(let x) = tokens[idx].kind,
               case .number(let y) = tokens[idx + 1].kind {
                pts.append(transform(x: x, y: y, ctm: ctm, scale: scale))
            } else {
                return []
            }
            idx += 2
        }
        return pts
    }

    /// Rectangle `re`: x y w h.
    static func argRect(_ tokens: [PDFToken], at i: Int, scale: Double, ctm: [[Double]]) -> VectorShape? {
        guard i - 4 >= 0,
              case .number(let x) = tokens[i - 4].kind,
              case .number(let y) = tokens[i - 3].kind,
              case .number(let w) = tokens[i - 2].kind,
              case .number(let h) = tokens[i - 1].kind else { return nil }
        let a = transform(x: x, y: y, ctm: ctm, scale: scale)
        let b = transform(x: x + w, y: y + h, ctm: ctm, scale: scale)
        return .rectangle(origin: VectorPoint(x: min(a.x, b.x), y: min(a.y, b.y)),
                          width: abs(b.x - a.x), height: abs(b.y - a.y))
    }

    /// Transformation matrix `cm`: a b c d e f (PDF row-major convention).
    static func argMatrix(_ tokens: [PDFToken], at i: Int) -> [[Double]]? {
        guard i - 6 >= 0 else { return nil }
        var vals: [Double] = []
        var idx = i - 6
        while idx < i {
            guard case .number(let n) = tokens[idx].kind else { return nil }
            vals.append(n)
            idx += 1
        }
        return [[vals[0], vals[1], 0], [vals[2], vals[3], 0], [vals[4], vals[5], 1]]
    }

    static func multiply(_ a: [[Double]], _ b: [[Double]]) -> [[Double]] {
        var out = [[Double]](repeating: [Double](repeating: 0, count: 3), count: 3)
        for r in 0..<3 {
            for c in 0..<3 {
                var sum = 0.0
                for k in 0..<3 { sum += a[r][k] * b[k][c] }
                out[r][c] = sum
            }
        }
        return out
    }

    static func transform(x: Double, y: Double, ctm: [[Double]], scale: Double) -> VectorPoint {
        let wx = ctm[0][0] * x + ctm[1][0] * y + ctm[2][0]
        let wy = ctm[0][1] * x + ctm[1][1] * y + ctm[2][1]
        return VectorPoint(x: wx * scale, y: wy * scale)
    }

    /// Sample a cubic Bézier into `steps` points (de Casteljau).
    static func sampleBezier(_ p0: VectorPoint, _ p1: VectorPoint, _ p2: VectorPoint, _ p3: VectorPoint, steps: Int) -> [VectorPoint] {
        var pts: [VectorPoint] = []
        for s in 1...steps {
            let t = Double(s) / Double(steps)
            let u = 1 - t
            let x = u*u*u*p0.x + 3*u*u*t*p1.x + 3*u*t*t*p2.x + t*t*t*p3.x
            let y = u*u*u*p0.y + 3*u*u*t*p1.y + 3*u*t*t*p2.y + t*t*t*p3.y
            pts.append(VectorPoint(x: x, y: y))
        }
        return pts
    }
}

// MARK: - Byte scanner (raw Data, so binary streams survive)

struct PDFScanner {
    let data: Data
    var index: Data.Index

    init(data: Data) {
        self.data = data
        self.index = data.startIndex
    }

    /// Advance past `needle` (the 8-bit ASCII keyword); true when found.
    mutating func skip(upTo needle: String) -> Bool {
        guard let needleData = needle.data(using: .ascii) else { return false }
        while index <= data.endIndex - needleData.count {
            let window = data[index..<(index + needleData.count)]
            if window.elementsEqual(needleData) {
                index = index + needleData.count
                return true
            }
            index += 1
        }
        return false
    }

    /// Return the bytes up to (excluding) `needle`, advancing past it.
    mutating func scan(upTo needle: String) -> Data? {
        guard let needleData = needle.data(using: .ascii) else { return nil }
        var search = index
        while search <= data.endIndex - needleData.count {
            let window = data[search..<(search + needleData.count)]
            if window.elementsEqual(needleData) {
                let out = data[index..<search]
                index = search + needleData.count
                return Data(out)
            }
            search += 1
        }
        return nil
    }

    mutating func skipEOL() {
        while index < data.endIndex {
            let byte = data[index]
            if byte == 0x0A || byte == 0x0D {
                index += 1
            } else {
                break
            }
        }
    }
}
